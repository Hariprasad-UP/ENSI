# ENSI — Effortless Network Shared Input

Share **one keyboard and mouse across multiple devices** on the same Wi‑Fi/LAN.
Move your cursor off the edge of one screen and it appears on the next device —
a cross‑platform software KVM built with **Flutter**.

> Status: **early / requirements phase.** See the full spec in
> [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md).

## Features (target)
- 🖱️ **Shared keyboard & mouse** across Windows, macOS, Linux
- 📱 **Mobile as input sender** (Android/iOS act as touchpad + keyboard)
- 🧭 **One device = Host**, others are Clients (role switchable)
- 🖥️ **Multi‑display / multi‑monitor alignment** via a visual layout editor
- 📡 **Auto‑discovery** on the LAN (mDNS + UDP fallback)
- 🔒 **Encrypted (TLS)** transport with **PIN pairing**
- 📋 Shared clipboard & drag‑and‑drop file transfer *(planned)*
- ⚡ **One‑command install** that auto‑detects your OS/architecture

## Platform support
| Platform | Host | Client | Input sender |
|---|:--:|:--:|:--:|
| Windows 10/11 | ✅ | ✅ | ✅ |
| macOS 12+ | ✅ | ✅ | ✅ |
| Linux (X11/Wayland) | ✅ | ✅ | ✅ |
| Android 8+ | — | — | ✅ |
| iOS 15+ | — | — | ✅ |

## One‑command install
**Linux / macOS**
```bash
curl -fsSL https://raw.githubusercontent.com/Hariprasad-UP/ENSI/main/scripts/install.sh | bash
```
**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/Hariprasad-UP/ENSI/main/scripts/install.ps1 | iex
```
> The installer detects your OS + CPU architecture and fetches the matching
> build from GitHub Releases. (Builds must be published as Releases first.)

## Build from source
```bash
flutter pub get
flutter build windows --release   # or: macos / linux / apk / ios
```

## How it works
1. **Discover** peers on the LAN → 2. **Pair** with a PIN (TLS) →
3. **Arrange** screens in the layout editor → 4. **Move** the cursor across edges.

See architecture & protocol in [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md).

## Why not just use Synergy/Barrier?
ENSI targets the same problem with a **single Flutter codebase** spanning desktop
**and** mobile, modern auto‑discovery, and a one‑command installer. Prior art
(Synergy, Barrier, Input Leap/Deskflow) is great inspiration and reference.

## Contributing
Roadmap and milestones are in the SRS. Issues & PRs welcome.

## License
TBD (recommend MIT or Apache‑2.0).
