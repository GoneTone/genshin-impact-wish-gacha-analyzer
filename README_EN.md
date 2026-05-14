# 原神祈願卡池分析 Genshin Impact Wish Gacha Analyzer

[繁體中文](README.md) | [简体中文](README_ZH-CN.md) | English

[![Crowdin](https://badges.crowdin.net/genshin-impact-wish-gacha-analyzer/localized.svg)](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer)

I have developed a utility for analyzing gacha history, where all data and numbers are well-organized in a convenient manner.

When you press *Update*, the utility starts a local proxy server (running only on your computer) and automatically installs a locally generated root certificate, so it can intercept Genshin Impact's WebView request to the miHoYo wish history API. You therefore need to open the wish history page in the game *after* pressing *Update*, so the request can be captured. The captured URL is parsed and the resulting parameters are used to call miHoYo's API.

The first time you press *Update*, the utility loads your full gacha history, which may take a while. The data is then stored locally so you don't have to wait again on the next launch. To pull new records, just press *Update*: the utility remembers the previously captured URL and reuses it as long as it's still valid, so you don't have to repeat the capture every time. If the captured URL has expired, the utility will ask you to open the wish history page in the game again to re-capture.

Rest assured: this utility does not read or modify any game file, game memory, or in-game network traffic. It only intercepts the wish history page request that the in-game WebView itself makes, so there is no risk of being banned for using it. If you have been banned, it was likely for a different reason. Please do not blame us, thanks.

Posts:
- 巴哈姆特 (Bahamut): <https://forum.gamer.com.tw/C.php?bsn=36730&snA=11990&tnum=4>
- HoYoLAB: <https://www.hoyolab.com/genshin/article/552176>
 
## Multiple Language
 
Please help us translate this software.
 
<https://crowdin.com/project/genshin-impact-wish-gacha-analyzer>
 
## Download Software
 
The utility may trigger anti-virus software during installation and execution. This is because it generates and installs a local root certificate, and briefly configures a system proxy when you press *Update* to intercept the in-game WebView's wish history request — behavior that resembles malware. However, the utility only intercepts the single `*.hoyoverse.com/getGachaLog` endpoint, and the certificate stays on your computer. If the utility doesn't function correctly, please try disabling any anti-virus software you have installed. We guarantee this utility is safe and virus-free.

<https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/releases>

## How to Use

1. Launch Genshin Impact (don't open the wish history page yet).
2. Open this utility and press *Update*. The utility will start a local proxy server in the background and wait for the request.
3. Switch back to the game and open *Wish → History* to view the wish history page.
4. Once captured, the utility automatically shuts down the proxy, restores your system proxy settings, and starts fetching your data. To update again later, just repeat step 2 — the captured URL will be reused if still valid.

## Features

- Auto-intercepts the in-game WebView's request to the miHoYo wish history API via a local proxy and a self-signed root certificate — no need to paste URLs by hand
- Supports the Global server (CN server not supported yet)
- Covers all 7 gacha types: Character Event Wish, Weapon Event Wish, Chronicled Wish, Standard Wish, Beginners' Wish, Event Odes, Standard Odes
- Multi-account (UID) management: custom aliases, drag-to-reorder, one-click switching
- Incremental updates merge new records without overwriting old ones, so entries that fall off the official history won't disappear
- Total pulls and 5★ / 4★ / 3★ / 2★ counts with their share of the total
- Dual pity progress (5★ and 4★) showing remaining pulls until pity
- Per-gacha 5★ timeline
- Bar chart comparing each gacha's highest-rarity counts
- Rarity distribution pie chart
- Item type distribution pie chart
- Wish history table: multi-column sort, fuzzy search, rarity and item-type filters, pagination
- Export / Import accounts as JSON
- Dark / Light theme toggle
- Multi-language ([help us translate](https://crowdin.com/project/genshin-impact-wish-gacha-analyzer))
- Automatic update check on launch, with a manual trigger in Settings
- All data stays on your machine — nothing is uploaded

## Screenshot

![Overall Data Chart](docs/images/en/1.png)
![Character Event Wish-Data Chart](docs/images/en/2.png)
![Drop Rate](docs/images/en/3.png)
![Table 1](docs/images/en/4.png)
![Table 2](docs/images/en/5.png)
![Daily Check-in](docs/images/en/6.png)
![Teyvat Interactive Map](docs/images/en/7.png)

## Development

### Prerequisites

- Windows only for now
- [Flutter SDK](https://docs.flutter.dev/install) (latest stable)
- [Rust toolchain](https://rustup.rs/) (stable)
- Run `flutter doctor` and install anything it flags as missing

### Clone and install dependencies

```bash
git clone https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer.git
cd genshin-impact-wish-gacha-analyzer
flutter pub get
cargo build --manifest-path rust/Cargo.toml
```

### Run in development mode

```bash
flutter run -d windows
```

### Rust ↔ Dart bridge code generation

After changing Rust functions in `rust/src/api/`, regenerate the bridge code. Install the codegen tool on first use:

```bash
cargo install flutter_rust_bridge_codegen
```

Then run this whenever the API changes:

```bash
flutter_rust_bridge_codegen generate
```

Generated files live in `lib/src/rust/`.

### Build for release

```bash
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\`

### Run tests

```bash
flutter test
cargo test --manifest-path rust/Cargo.toml
```
