#!/usr/bin/env bash
# 量測 Android 實機上某一頁的出幀節奏（profile 或 release 版，需 adb 連線）。
#
# 輸出兩個數字：
#   idle    靜止 1.5 秒內的出幀率；SurfaceFlinger 只留最近約 127 幀（扣掉尚未上屏的
#           約剩 125），取到 120 幀以上就顯示「滿」：實際約等於螢幕刷新率。
#   準時率  放手後慣性滑動的幀間隔 ≤ 1.5 個 vsync（165Hz 下 9.1ms）的比例。
# 只量慣性滑動：adb 注入的拖曳事件取樣不足，會讓輕量頁面也出現假的「晚一拍」。
#
# 用法：bash tool/measure_frame_pacing.sh <標籤> <側欄項目 y 座標>
#   y 座標為 0 表示量目前畫面；否則先點左上角漢堡選單（73,179）再點該 y。
#   座標以 1080x2400 手機為準，其他機型用 `adb shell uiautomator dump` 查。
# 判定門檻（165Hz 時 9.1/15.2ms）寫死在下方 awk，其他刷新率要改。
export MSYS_NO_PATHCONV=1
label=$1; y=$2
if [ "$y" != 0 ]; then adb shell input tap 73 179; sleep 0.8; adb shell input tap 400 $y; sleep 3; fi
layer=$(adb shell dumpsys SurfaceFlinger --list | tr -d '\r\000' | grep -a 'SurfaceView\[tw.reh.genshin.gacha' | grep -a BLAST | sed -E 's/^RequestedLayerState\{//; s/ parentId=.*//' | head -1)
lat() { adb shell "dumpsys SurfaceFlinger --latency '$layer'" | tr -d '\r' | awk 'NR>1 && $2>0 && $2<9e18 {print $2}' | sort -n; }
clr() { adb shell dumpsys SurfaceFlinger --latency-clear >/dev/null; }
clr; sleep 1.5
idle=$(lat | awk '{n++} END{ if(n>=120) print "滿"; else if(n<2) print 0; else printf "%.0f", (n-1)/1.5 }')
all=""
for d in "1900 900" "1900 900" "900 1900" "900 1900" "1900 900" "900 1900"; do
  set -- $d
  adb shell input swipe 540 $1 540 $2 80; clr; sleep 0.6
  all="$all
$(lat | awk 'NR>1{d=($1-p)/1e6; if(d<50) printf "%.2f\n", d} {p=$1}')"
  sleep 1.2
done
echo "$all" | awk -v L="$label" -v I="$idle" 'NF{n++; if($1<=9.1) ok++; else if($1<=15.2) l1++; else l2++} END{ if(n==0){printf "%s idle=%s (無法捲動)\n", L, I; exit} printf "%s idle=%s fling幀=%d 準時=%.1f%% 晚1拍=%.1f%% 晚2+拍=%.1f%%\n", L, I, n, 100*ok/n, 100*l1/n, 100*l2/n}'
