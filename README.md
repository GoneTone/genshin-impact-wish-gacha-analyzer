# 原神祈願卡池分析

## 專案設定
### 安裝依賴套件
```
npm install
```

### 編譯並執行 (開發)
```
npm run electron:serve
```

### 編譯並最小化 (生產，Windows exe)
ia32 和 x64
```
npm run electron:build:win
```

ia32
```
npm run electron:build:win32
```

x64
```
npm run electron:build:win64
```

## 功能和待做
- [x] 支援國際服
- [ ] 支援中國服
- [x] 總抽數統計
- [x] 中5星平均抽數統計
- [x] 保底進度條及剩餘抽數統計
- [x] 級別中獎率和中獎數統計
- [x] 角色武器中獎率和中獎數統計
- [x] 級別中獎數圓餅圖
- [x] 角色武器中獎數圓餅圖
- [x] 歷史紀錄 (官方 API 資料) 表單 (可自訂排序及搜尋)
- [x] 將抽卡紀錄導出 Excel
- [x] 依據玩家語言讀取官方 API 取得相對語言資料
- [ ] 自動更新版本
- [ ] 多國語言
- [ ] 多帳號切換
