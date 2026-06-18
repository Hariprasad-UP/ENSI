# ENSI — Software Requirements Specification (SRS)

**ENSI** — *Effortless Network Shared Input*
A cross-platform application that lets one keyboard and mouse control multiple
devices on the same Wi‑Fi/LAN, with seamless cursor movement across the combined
display layout.

| Field | Value |
|---|---|
| Document type | Software Requirements Specification (IEEE‑830 style) |
| Version | 0.1.0 (Draft) |
| Status | Draft for review |
| Date | 2026-06-18 |
| Owner | Hariprasad-UP |
| Repository | https://github.com/Hariprasad-UP/ENSI.git |
| Framework | Flutter 3.38+ / Dart 3.10+ |

---

## 1. Introduction

### 1.1 Purpose
ENSI allows a user to share a **single keyboard and mouse** across **multiple
devices** connected to the **same local network (Wi‑Fi/LAN)**. One device is
designated the **Host** (the machine whose physical keyboard/mouse is shared);
the other devices are **Clients** that receive input as the cursor crosses
screen edges. This is a software KVM, conceptually similar to Synergy / Barrier /
Input Leap, built in Flutter for broad platform reach.

### 1.2 Scope
- **In scope:** desktop‑to‑desktop input sharing (Windows, Linux, macOS), mobile
  devices acting as input *senders* (touchpad/keyboard), automatic device
  discovery on the LAN, multi‑display layout/alignment, encrypted transport, and
  a one‑command auto‑installer.
- **Out of scope (v1):** screen mirroring / remote desktop video, controlling a
  phone's OS from a desktop (requires root/jailbreak), internet/WAN relay,
  audio sharing.

### 1.3 Definitions & Abbreviations
| Term | Meaning |
|---|---|
| **Host** | The device whose physical keyboard & mouse are shared (server role). |
| **Client** | A device that receives input from the Host (or, for mobile, sends input to the Host). |
| **Peer** | Any device participating in an ENSI session. |
| **Edge switch** | Cursor crossing one screen's edge to enter an adjacent device's screen. |
| **Layout** | The 2D arrangement of all participating screens. |
| **KVM** | Keyboard, Video, Mouse switch (here: software K & M only). |
| **mDNS** | Multicast DNS (Bonjour) — zero‑config service discovery. |
| **FFI** | Foreign Function Interface — Dart calling native C/C++ libraries. |

### 1.4 References
- IEEE Std 830‑1998 (SRS structure)
- Open‑source prior art: Synergy, Barrier, Input Leap, Deskflow
- Flutter desktop & FFI documentation

---

## 2. Overall Description

### 2.1 Product Perspective
ENSI is a standalone client application installed on each participating device.
There is no central server; one peer is elected/selected as Host per session.
The system has three logical layers:

```
+-----------------------------------------------------------+
|                       Flutter UI (Dart)                   |
|   device list · layout editor · settings · pairing        |
+-----------------------------------------------------------+
|                  Core engine (Dart)                       |
|  discovery · session mgmt · layout · clipboard · security |
+-----------------------------------------------------------+
|        Platform input layer (native via FFI/plugin)       |
|  capture (Host) + inject (Client) per OS                  |
+-----------------------------------------------------------+
```

### 2.2 User Classes
- **Single power user** (primary): one person with several machines at a desk.
- **Developer/tester:** runs builds, uses install script, files issues.

### 2.3 Operating Environment
| Platform | Min version | Role(s) |
|---|---|---|
| Windows | 10 (x64), 11 | Host, Client |
| macOS | 12 Monterey (Intel + Apple Silicon) | Host, Client |
| Linux | Ubuntu 22.04 / equivalent (X11 + Wayland) | Host, Client |
| Android | 8.0 (API 26)+ | Input‑sender client only |
| iOS | 15+ | Input‑sender client only |

All peers must be on the **same L2/Wi‑Fi subnet** with mDNS/UDP broadcast allowed.

### 2.4 Design & Implementation Constraints
- **C‑1 (critical):** Flutter cannot capture global input or inject OS‑level
  input on its own. Each desktop platform **requires native code** invoked via
  `dart:ffi` or a platform plugin:
  - **Windows:** capture via low‑level hooks (`SetWindowsHookEx`,
    `WH_KEYBOARD_LL`/`WH_MOUSE_LL`); inject via `SendInput`.
  - **macOS:** capture via `CGEventTap`; inject via `CGEventPost`. Requires the
    user to grant **Accessibility** (and **Input Monitoring**) permission.
  - **Linux/X11:** capture via `XInput2`/`XGrab`; inject via `XTEST`.
  - **Linux/Wayland:** capture/inject via `libinput` + `/dev/uinput`
    (needs appropriate udev/group permission). Wayland security model restricts
    global capture — document portal/compositor caveats.
- **C‑2:** Mobile OSes do not permit OS‑level input injection without
  root/jailbreak → phones are **senders only** in v1.
- **C‑3:** Single codebase in Flutter/Dart; native code isolated behind a common
  Dart interface (`InputBackend`).
- **C‑4:** No external/cloud dependency for core function — must work fully
  offline on the LAN.

### 2.5 Assumptions & Dependencies
- Users can grant OS permissions (Accessibility on macOS, udev/uinput on Linux,
  UAC/driver prompts on Windows).
- The network permits mDNS (UDP 5353) and the chosen TCP port.
- Builds are published as **GitHub Releases** for the installer to fetch.

---

## 3. Functional Requirements

> Priority: **M** = Mandatory (v1), **S** = Should, **C** = Could / stretch.

### 3.1 Device Discovery & Connection
- **FR‑1 (M):** On launch, a device SHALL auto‑discover other ENSI peers on the
  same LAN via **mDNS**, with **UDP broadcast** as fallback.
- **FR‑2 (M):** The UI SHALL list discovered devices with name, platform,
  IP, and online status.
- **FR‑3 (M):** A user SHALL be able to manually add a peer by IP:port when
  discovery is blocked.
- **FR‑4 (M):** Devices SHALL **pair** on first connection using a short
  **PIN/code** shown on the target device (prevents unauthorized control).
- **FR‑5 (S):** Paired devices SHALL auto‑reconnect when both come online.

### 3.2 Host / Client Roles
- **FR‑6 (M):** A user SHALL designate exactly one device as **Host** per
  session; all others act as **Clients**.
- **FR‑7 (M):** The Host SHALL capture local keyboard & mouse events and forward
  them to the active Client when the cursor is on that Client's screen.
- **FR‑8 (M):** Role SHALL be switchable without reinstalling (any desktop peer
  can become Host).
- **FR‑9 (S):** Support **handoff** — releasing the Host role to another device.

### 3.3 Input Sharing
- **FR‑10 (M):** The Host SHALL transmit **mouse move, click, scroll, and
  drag** events to the targeted device with end‑to‑end latency **< 50 ms** on a
  typical LAN.
- **FR‑11 (M):** The Host SHALL transmit **keyboard key‑down/key‑up** events,
  preserving modifier keys (Ctrl/Alt/Shift/Cmd/Win) and key‑repeat.
- **FR‑12 (M):** Keyboard layout/keycode mapping SHALL be translated correctly
  between source and target OS.
- **FR‑13 (S):** A global **hotkey** SHALL lock the cursor to the current screen
  / toggle sharing on/off.
- **FR‑14 (M, mobile):** A mobile Client SHALL provide a **touchpad + virtual
  keyboard** UI that sends input events TO the Host.

### 3.4 Multi‑Display Layout & Alignment
- **FR‑15 (M):** The app SHALL provide a **visual layout editor** where each
  device's screen(s) are positioned in a 2D grid (drag to arrange), defining
  which edges are adjacent.
- **FR‑16 (M):** Each device SHALL report its **display geometry** (resolution,
  count, relative position, DPI/scale) so the layout is to scale.
- **FR‑17 (M):** Moving the cursor past a configured edge SHALL **switch input**
  to the adjacent device at the correct entry coordinate (edge mapping).
- **FR‑18 (M):** The app SHALL support devices with **multiple monitors** and
  align edges per‑monitor, not per‑device.
- **FR‑19 (S):** Cursor speed SHALL be normalized across differing DPI/scaling so
  movement feels continuous.
- **FR‑20 (C):** Persist named **layout profiles** (e.g. "Office", "Home").

### 3.5 Clipboard & File Sharing (suggested)
- **FR‑21 (S):** Shared **clipboard (text)** SHALL sync across peers.
- **FR‑22 (C):** Clipboard **images/files** SHALL sync.
- **FR‑23 (C):** **Drag‑and‑drop file transfer** across screen edges.

### 3.6 Security
- **FR‑24 (M):** All peer‑to‑peer traffic SHALL be **encrypted (TLS)**.
- **FR‑25 (M):** Only **paired/trusted** devices SHALL be allowed to send/receive
  input (reject unknown peers).
- **FR‑26 (S):** The user SHALL be able to view and **revoke** trusted devices.

### 3.7 Installation & Updates
- **FR‑27 (M):** A **single terminal command** SHALL auto‑detect the device's
  **OS and CPU architecture** and install the correct ENSI build automatically.
  - Linux/macOS: `curl -fsSL https://raw.githubusercontent.com/Hariprasad-UP/ENSI/main/scripts/install.sh | bash`
  - Windows (PowerShell): `irm https://raw.githubusercontent.com/Hariprasad-UP/ENSI/main/scripts/install.ps1 | iex`
- **FR‑28 (M):** The installer SHALL fetch the matching artifact from **GitHub
  Releases** and place a launchable binary on PATH / in the apps menu.
- **FR‑29 (S):** The app SHALL check for and offer **updates** on launch.

---

## 4. Non‑Functional Requirements
- **NFR‑1 Performance:** input latency < 50 ms LAN; < 1% dropped events.
- **NFR‑2 Reliability:** auto‑reconnect within 5 s of network blip; no stuck/
  "ghost" modifier keys after disconnect (release all keys on drop).
- **NFR‑3 Usability:** first successful host↔client connection in < 3 minutes
  for a new user.
- **NFR‑4 Security:** encrypted transport; no plaintext input on the wire; explicit
  pairing required.
- **NFR‑5 Portability:** one Flutter codebase; native input layer isolated behind
  a single Dart interface.
- **NFR‑6 Resource use:** idle CPU < 2%; memory footprint < 150 MB desktop.
- **NFR‑7 Accessibility:** keyboard‑navigable UI, screen‑reader labels, high‑
  contrast support.
- **NFR‑8 Observability:** local log file + in‑app connection diagnostics.

---

## 5. System Architecture & Tech Stack

### 5.1 Components
| Component | Tech | Responsibility |
|---|---|---|
| UI | Flutter (Material 3) | device list, layout editor, settings, pairing |
| Core engine | Dart | discovery, session state, layout math, clipboard |
| Discovery | `multicast_dns` / `nsd` + UDP | find peers on LAN |
| Transport | TCP + TLS (`dart:io` `SecureSocket`) | ordered low‑latency input stream |
| Serialization | compact binary (or protobuf) | input event frames |
| Input backend | `dart:ffi` → native (C/C++/Obj‑C) | capture & inject per OS |
| Storage | `shared_preferences` / local file | trusted peers, layout profiles |

### 5.2 Input Backend Interface (per‑platform)
```dart
abstract class InputBackend {
  Stream<InputEvent> captureStream();      // Host side
  Future<void> inject(InputEvent event);   // Client side
  DisplayGeometry queryDisplays();
  void releaseAllKeys();                    // safety on disconnect
}
```
Implementations: `WindowsBackend`, `MacOSBackend`, `LinuxX11Backend`,
`LinuxWaylandBackend`, `MobileSenderBackend`.

### 5.3 Network protocol (high level)
1. **Discover** peers (mDNS) → 2. **Pair** (PIN + TLS cert exchange) →
3. **Negotiate** layout & display geometry → 4. **Stream** input frames →
5. **Heartbeat**/reconnect; on drop → `releaseAllKeys()`.

---

## 6. One‑Command Auto‑Install (FR‑27/28 detail)
The installer scripts MUST:
1. Detect OS (`Linux`/`Darwin`/`Windows`) and arch (`x64`/`arm64`).
2. Resolve the latest GitHub Release tag for ENSI.
3. Download the matching asset (`.exe`/`.msix`, `.dmg`, `.AppImage`/`.deb`).
4. Install/extract and register on PATH or app menu.
5. Verify checksum; print next‑steps (permissions to grant).

See [`scripts/install.sh`](../scripts/install.sh) and
[`scripts/install.ps1`](../scripts/install.ps1).

---

## 7. Acceptance Criteria (v1 "done")
- [ ] Two desktops (different OSes) auto‑discover and pair via a SAS code. *(implemented in M1; loopback‑tested, two‑machine field test pending)*
- [ ] Cursor crosses from Host screen edge to Client screen and back.
- [ ] Keyboard input (incl. modifiers) types correctly on the Client.
- [ ] Multi‑monitor device aligns per‑monitor in the layout editor.
- [ ] A phone connects and drives the Host as touchpad + keyboard.
- [x] Traffic is TLS‑encrypted; unpaired device is rejected. *(M1: server‑authenticated TLS + fingerprint‑pinned trust gating; covered by automated tests)*
- [ ] `install.sh` / `install.ps1` install the correct build on each OS via one command.
- [ ] No stuck keys after a forced disconnect.

---

## 8. Roadmap / Milestones
| Phase | Deliverable | Status |
|---|---|---|
| **M0** | Repo, SRS, installer skeleton, CI build matrix. | ✅ Done |
| **M1** | Discovery + pairing + TLS transport; two desktops connect. | ✅ Implemented (loopback‑tested; two‑machine field test pending) |
| **M2** | Windows capture/inject backend; single‑screen edge switch. | ⏳ Next |
| **M3** | macOS + Linux (X11) backends; multi‑monitor layout editor. | ⏳ Planned |
| **M4** | Mobile sender (touchpad/keyboard); shared text clipboard. | ⏳ Planned |
| **M5** | Wayland backend, auto‑reconnect, layout profiles, updater. | ⏳ Planned |
| **M6** | File drag‑and‑drop, image clipboard, polish & releases. | ⏳ Planned |

---

## 9. Risks & Open Questions
- **R‑1:** Wayland restricts global input capture — may need compositor‑specific
  portals; could limit Linux/Wayland Host support.
- **R‑2:** macOS permission friction (Accessibility) — needs clear onboarding.
- **R‑3:** Antivirus/UAC may flag low‑level hooks on Windows — code signing needed.
- **R‑4:** Keymap translation across OS layouts is error‑prone — needs a test matrix.
- **Q‑1:** Encode events as protobuf or custom binary? (latency vs. tooling)
- **Q‑2:** Should Host election be manual only, or auto by "who has the keyboard"?
