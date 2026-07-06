# 原神祈愿卡池分析 Genshin Impact Wish Gacha Analyzer

[繁體中文](README.md) | 简体中文 | [English](README_EN.md) | [日本語](README_JA-JP.md)

[![Crowdin](https://badges.crowdin.net/genshin-impact-wish-gacha-analyzer/localized.svg)](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer)

我开发了一套用来分析祈愿卡池历史记录的软件，一打开各种数据清清楚楚，不用再手动计算啦！

本软件的原理是：按下「更新数据」后会在本机启动一个只跑在您电脑上的代理服务器，并自动安装一张本机生成的根证书，借此拦截原神 WebView 对 miHoYo 卡池历史 API 的请求，所以要在按下更新后再到游戏内打开卡池历史记录才能拦到，拿到网址后解析参数，参数会用于 miHoYo 原神相关的 API。

第一次按下「更新数据」会加载您完整的卡池历史，这可能需要一些时间，完成后会将数据保存在您的电脑上，这样下次打开软件就不用再花时间等待数据加载。之后想获取新数据按一下「更新数据」即可，软件会记住先前拦到的网址，能用就直接用、不用每次重新拦截；如果网址过期，软件会请您再到游戏打开一次卡池历史页面以重新获取网址。

请放心：本软件不会读取或篡改任何游戏文件、内存与游戏传输的数据，只会在 WebView 打开卡池历史页面时拦下那一条请求网址，所以不会有账号被封禁的风险。如果您被封号，请思考是否因为其他原因被封禁，不要怪我们。

帖子：
- 巴哈姆特：<https://forum.gamer.com.tw/C.php?bsn=36730&snA=11990>
- HoYoLAB：<https://www.hoyolab.com/genshin/article/552176>
- 原神资讯站：<https://genshininfo.reh.tw/archives/97>

## 多国语言

请帮我们将软件翻译成各国语言！

<https://crowdin.com/project/genshin-impact-wish-gacha-analyzer>

## 下载软件

软件在安装或运行时有可能会被杀毒软件拦截。原因是本软件会自行生成并安装一张本机根证书，并在按下更新时短暂设置系统代理以拦截原神 WebView 的卡池历史请求——这类行为与恶意程序相似，但本软件只拦截 `*.hoyoverse.com` 上的 `getGachaLog`（祈愿）与 `getBeyondGachaLog`（颂愿）这两条卡池历史 API，且证书只留在您的电脑上。如果无法正常运行，请尝试关闭杀毒软件后再运行试试，本软件保证无毒。

<https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases>

### 也有支持其他游戏的版本

- 鸣潮：<https://github.com/GoneTone/wuthering-waves-convene-gacha-analyzer>
- 未来可能新增支持更多游戏...

## 使用方法

1. 启动原神，先别打开卡池历史页面。
2. 打开本软件并按下「更新数据」，软件会在后台启动本机代理服务器并等候拦截。
3. 切回游戏，到「祈愿 → 历史记录」打开卡池历史页面。
4. 软件拦到网址后会自动关闭代理、还原系统代理设置并开始抓取数据；之后想再更新只要重复步骤 2，网址未过期就会直接使用。

## 功能与特色

- 自动拦截原神 WebView 对 miHoYo 卡池历史 API（通过本机代理服务器与自签根证书），无需手动粘贴网址
- 支持国际服（暂不支持国服）
- 涵盖 7 种卡池：角色活动祈愿、武器活动祈愿、集录祈愿、常驻祈愿、新手祈愿、活动颂愿、常驻颂愿
- 多账号 (UID) 管理：自定义别名、拖动排序、一键切换
- 自动合并新旧数据，不覆盖过往记录，不会因为官方历史记录过期而丢失
- 总抽数及 5★ / 4★ / 3★ / 2★ 数量与占比统计
- 5★ 与 4★ 双保底进度条，并显示距离保底的剩余抽数
- 5★ / 4★ 平均出货抽数统计（各卡池与整体）
- 各卡池 5★ 时间轴
- 5★ 总览：横向陈列抽到过的所有不重复 5★，每个附累计次数徽章、可点开详情；各卡池页、综合数据页与分享图都会显示
- 各卡池最高稀有度数量对比柱状图
- 稀有度分布饼图
- 类型分布饼图
- 历史记录表格：多列排序、模糊搜索、稀有度与物品类型筛选、分页
- 自动补上角色 / 武器的图标与资料（来源：[HoYoWiki](https://wiki.hoyolab.com/pc/genshin/home)）：表格与时间轴都附图标；点击物品可查看官方插画、描述与标签，并一键跳转 HoYoWiki
- 一键生成分享图（可选深色 / 浅色主题、UID 全显或只留前三码遮罩），自动存档并复制到剪贴板
- 账号数据导出 / 导入 JSON
- 深色 / 浅色主题切换
- 多国语言（[协助翻译](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer)）
- 可在设置开启界面 UID 遮罩（只显示前三码），保护隐私
- 启动时自动检查新版本，也可在设置页手动触发
- 云端同步（可选）：关联自己的 Google 账号后，卡池记录会自动备份到您自己的 Google 云端硬盘，并在多台电脑间双向同步；删除账号时可勾选一并从云端移除
- 所有数据默认留在本机；云端同步为可选功能，启用后也只会备份到您自己的 Google 云端硬盘

## 截图

![综合数据页](docs/images/zh-Hans/1.png)
![角色活动祈愿页](docs/images/zh-Hans/2.png)
![武器活动祈愿页](docs/images/zh-Hans/3.png)
![活动颂愿页](docs/images/zh-Hans/4.png)
![设置页](docs/images/zh-Hans/5.png)
![分享图生成设置](docs/images/zh-Hans/6.png)
![分享图](docs/images/zh-Hans/7.png)
![物品详情显示](docs/images/zh-Hans/8.png)

## 开发

### 前置需求

- 目前仅支持 Windows
- [Flutter SDK](https://docs.flutter.dev/install)（最新稳定版）
- [Rust toolchain](https://rustup.rs/)（stable）
- 运行 `flutter doctor`，根据提示补齐缺少的工具

### 获取源代码并安装依赖

```bash
git clone https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer.git
cd genshin-impact-wish-gacha-analyzer
flutter pub get
```

Rust 会在 `flutter run` / `flutter build` 时由 `rust_builder/` 的 cargokit 自动编译，无需手动 `cargo build`（但需先安装 Rust toolchain）。

### 开发模式运行

```bash
flutter run -d windows
```

### Rust ↔ Dart 桥接代码生成

修改 `rust/src/api/` 内的 Rust 函数后，重新生成桥接代码。第一次使用前先安装 codegen 工具：

```bash
cargo install flutter_rust_bridge_codegen --version 2.12.0
```

之后每次修改 API 都运行：

```bash
flutter_rust_bridge_codegen generate
```

生成的文件位于 `lib/src/rust/`。

### 编译生产版

```bash
flutter build windows --release
```

输出：`build\windows\x64\runner\Release\`

### 运行测试

```bash
flutter test
cargo test --manifest-path rust/Cargo.toml
```

### 云端同步凭据（开发者）

云端同步的 Google OAuth 凭据不随 repo 发布，fork 后需自备才能启用此功能：

1. 到 [Google Cloud Console](https://console.cloud.google.com/) 创建项目并启用 **Google Drive API**。
2. 配置 OAuth 同意屏幕（scopes：`.../auth/drive.appdata` 与 `email`），并创建「桌面应用（Desktop app）」类型的 OAuth 客户端 ID。
3. 在项目根目录创建 git-ignored 的 `secrets/cloud_sync_defines.json`：

    ```json
    {
      "CLOUD_SYNC_CLIENT_ID": "<your-client-id>",
      "CLOUD_SYNC_CLIENT_SECRET": "<your-client-secret>"
    }
    ```

4. 构建脚本（`scripts/build_installer/build_release.ps1`）会自动带入；直接运行 `flutter run` 时加上 `--dart-define-from-file=secrets/cloud_sync_defines.json`。未设置时 App 照常运行，仅云端同步区块显示未设置提示。

发布 CI 由 repo Actions secrets `CLOUD_SYNC_CLIENT_ID`／`CLOUD_SYNC_CLIENT_SECRET` 生成同一文件。
