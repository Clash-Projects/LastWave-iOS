<div align="center">

<img src="LastWave_Desktop_v7_1440p.png" alt="LastWave Banner" width="100%" style="border-radius: 16px;" />

<h1>LastWave for iOS</h1>

**A YouTube Music client for iPhone and iPad, built with Flutter. Automix, lossless addons, synced lyrics and more.**

<br/>

<p align="center">
  <a href="https://t.me/clashprojects" target="_blank"><img src="docs/badges/btn_telegram_support.svg" alt="Telegram Support" height="42" /></a>
  <a href="https://t.me/MaterialYouApp" target="_blank"><img src="docs/badges/btn_telegram_channel.svg" alt="Telegram Channel" height="42" /></a>
  <a href="https://discord.gg/DmyM2p2fMe" target="_blank"><img src="docs/badges/btn_discord.svg" alt="Discord Community" height="42" /></a>
</p>

</div>

---

## Overview

LastWave for iOS is the iPhone and iPad port of [LastWave Desktop](https://github.com/Clash-Projects/LastWave-Desktop). It shares the Flutter codebase with the desktop app, and its mobile interface follows the design of the Android app, [LastWave-Native](https://github.com/Clash-Projects/LastWave-Native). See [UPSTREAM_NOTICES.md](UPSTREAM_NOTICES.md) for what was adapted from where.

The port is a work in progress. The feature list below comes from the shared codebase, and not everything on it has been verified on iOS yet. In particular, background playback is declared but still needs on-device testing, and desktop-only items (Bit-Perfect output, system tray, global hotkeys, Discord Rich Presence, mini-player window) do not apply on iPhone or iPad.

---

## Features

<table>
  <tr>
    <td width="50%" valign="top">

#### Playback
- Stream any track or video from YouTube Music
- Background audio playback & system media controls
- High-res audio downloads with embedded metadata & `.lrc` lyrics
- Download & cache for offline listening
- Skip silence & sleep timer

</td>
    <td width="50%" valign="top">

#### Audio
- Bit-Perfect audio output (direct hardware bypass)
- Lossless FLAC addon support (up to 24-bit Hi-Res)
- 15-band Parametric Equalizer & AutoEQ presets
- Smart Automix transitions & smooth crossfade
- Audio normalization (ReplayGain / LUFS)
- Real-time tempo & pitch control

</td>
  </tr>
  <tr>
    <td width="50%" valign="top">

#### Lyrics & Discovery
- Live millisecond-synchronized lyrics (LRCLIB)
- Lyrics romanization for non-Latin scripts (Japanese, Korean, etc.)
- Multi-language lyrics translation
- Spotify Canvas & animated video backgrounds
- Personalized quick picks, mood radios & genre discovery
- Search songs, albums, artists, videos, and playlists

</td>
    <td width="50%" valign="top">

#### Library & Account
- Full library management & offline cached library
- Spotify Integration (Account login, Liked Songs sync & deep links)
- Import public playlists from Spotify & Apple Music
- YouTube Music account login & bidirectional sync
- Local & cloud playlists with custom reordering
- Custom audio tag editing & cover art selection

</td>
  </tr>
  <tr>
    <td width="50%" valign="top">

#### Social
- Listen together with friends in real-time
- Built-in Last.fm scrobbler with background tracking
- Safe Discord Rich Presence with live album art
- Export and share lyrics as aesthetic quote cards

</td>
    <td width="50%" valign="top">

#### Interface
- Clean WinUI & Fluent design interface
- Real-time acrylic blur and backdrop refraction
- Dynamic color theming + preset palettes
- Light, Dark, and Pure Black modes
- Global media hotkeys & mini-player

</td>
  </tr>
</table>

---

## Getting Started

### Installation

There is no App Store release. The GitHub Actions workflow **LastWave iOS** builds an unsigned `.ipa` on every push to `main`; download it from the workflow run's artifacts (kept for 14 days). An unsigned build has to be signed before it will install on a device, for example with Xcode or a sideloading tool. It requires iOS 15 or later.

| Platform | Source |
|:---|:---|
| **iPhone / iPad** | This repository (unsigned `.ipa` from CI, or build from source below) |
| **Windows, Linux, macOS** | [LastWave-Desktop](https://github.com/Clash-Projects/LastWave-Desktop/releases) |
| **Android** | [LastWave-Native](https://github.com/Clash-Projects/LastWave-Native) |

### Quick Setup

1. Install the signed build on your device.
2. *(Optional)* Open **Settings → Audio** to configure:
   - **Equalizer Presets:** Apply parametric EQ curves or headphone correction.
   - **Lossless Addons:** Enable the modular addon service for Hi-Res FLAC playback.
3. Start streaming music, exploring smart radios, and enjoying synced lyrics.

---

## Building from Source

### Prerequisites
- **macOS** with **Xcode** and **CocoaPods** installed (iOS builds only run on a Mac)
- **Flutter SDK 3.47.9**, the version CI uses (Dart `^3.13.3`, see `pubspec.yaml`)

### Build Instructions

```bash
# Clone the repository
git clone https://github.com/Clash-Projects/LastWave-iOS.git
cd LastWave-iOS

# Generate the build-time secrets file (lib/core/env/secrets.g.dart).
# Works without a .env; see .env.example for the optional values.
dart tool/obfuscate_secrets.dart

# Generate and configure the iOS host project
bash tool/prepare_ios.sh

# Install dependencies
flutter pub get

# Build an unsigned release
flutter build ios --release --no-codesign
```

`lib/core/env/secrets.g.dart` is gitignored, so the app will not compile until the `obfuscate_secrets.dart` step has run.

> [!TIP]
> For local development and hot reload, connect a device or start a simulator and run `flutter run`.

---

## Support the Project

If LastWave has been useful to you, consider supporting its development.

<div align="left">
  <table style="margin: 0 auto; border-collapse: collapse; border: none;">
    <tr>
      <td align="center" style="padding: 15px; border: none;">
        <a href="https://buymeacoffee.com/ajisth" target="_blank" style="text-decoration:none;"><img src="docs/badges/bmac.png" alt="Buy Me A Coffee" width="140" style="border-radius: 12px; box-shadow: 0 8px 16px rgba(0,0,0,0.2);"/></a>
      </td>
      <td align="center" style="padding: 15px; border: none;">
        <a href="https://buymeachai.ezee.li/ajisth69" target="_blank" style="text-decoration:none;"><img src="docs/badges/upi.png" alt="UPI (Buy Me A Chai)" width="140" style="border-radius: 12px; box-shadow: 0 8px 16px rgba(0,0,0,0.2);"/></a>
      </td>
      <td align="center" style="padding: 15px; border: none;">
        <a href="https://github.com/sponsors/ajisth69" target="_blank" style="text-decoration:none;"><img src="docs/badges/github_sponsors.svg" alt="GitHub Sponsors" width="140" style="border-radius: 12px; box-shadow: 0 8px 16px rgba(0,0,0,0.2);"/></a>
      </td>
    </tr>
  </table>
</div>

---

## Acknowledgements

LastWave for iOS builds on [LastWave-Desktop](https://github.com/Clash-Projects/LastWave-Desktop) and adapts UI from [LastWave-Native](https://github.com/Clash-Projects/LastWave-Native), both by Clash-Projects. It is made possible thanks to these open-source projects:

- **[media_kit](https://github.com/media-kit/media-kit)** — Audio playback engine powered by libmpv
- **[Limusic](https://github.com/chenyandian/Limusic)** — InnerTube client registry & stream resolution fast path
- **[LRCLIB](https://lrclib.net/)** — Real-time millisecond-synchronized lyrics database
- **[NewPipe](https://github.com/TeamNewPipe/NewPipeExtractor)** — Signature decipher patterns & extraction logic
- **[fluent_ui](https://github.com/bdlukaa/fluent_ui)** — WinUI & Fluent design system for desktop

---

## Contributors

LastWave wouldn't be possible without our incredible community of contributors. Thank you for making it better every day!

<p align="center">
  <a href="https://github.com/Clash-Projects/LastWave-iOS/graphs/contributors">
    <img src="https://contrib.rocks/image?repo=Clash-Projects/LastWave-iOS" alt="Contributors" />
  </a>
</p>

---

## Disclaimer

LastWave is an open-source, non-commercial application developed strictly for educational and research purposes.

- **No Affiliation:** This project is not affiliated with, funded, authorized, endorsed by, or in any way associated with Google LLC, YouTube, YouTube Music, Spotify, Apple Inc., Last.fm, or any of their subsidiaries.
- **Content Delivery:** LastWave does not host, store on private servers, or distribute copyrighted media. All playback streams and metadata are resolved directly from public endpoints.
- **Trademarks:** All product names, logos, trademarks, and registered trademarks belong to their respective owners.
