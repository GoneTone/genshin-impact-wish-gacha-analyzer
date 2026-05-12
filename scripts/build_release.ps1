# scripts/build_release.ps1
#
# Genshin Impact Wish Gacha Analyzer — Windows 一鍵打包腳本
#
# 流程:
#   1. 從 pubspec.yaml 讀版本號
#   2. 偵測 Inno Setup 6 是否安裝
#   3. flutter pub get + flutter build windows --release
#   4. 呼叫 ISCC.exe 編譯 installer.iss
#
# 用法:
#   .\scripts\build_release.ps1

$ErrorActionPreference = 'Stop'

# 切到專案根目錄(以本腳本為基準往上一層)
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $ProjectRoot

# --- 1. 讀版本號 -------------------------------------------------------------
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
if (-not (Test-Path $PubspecPath)) {
    throw "找不到 pubspec.yaml:$PubspecPath"
}

$VersionLine = Select-String -Path $PubspecPath -Pattern '^version:\s*([^\s+]+)' | Select-Object -First 1
if (-not $VersionLine) {
    throw "無法從 pubspec.yaml 抓到 version"
}
$Version = $VersionLine.Matches[0].Groups[1].Value
Write-Host "版本號:$Version" -ForegroundColor Cyan
