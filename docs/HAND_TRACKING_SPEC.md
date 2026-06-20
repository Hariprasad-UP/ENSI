# ENSI — Camera Hand-Tracking Cursor Control (Gesture Input)

**Engineering spec / work order** · v1 draft · Owner: TBD · Status: Ready for estimation

---

## 1. Context & goal

ENSI is a Flutter software-KVM. It already has a **native input-injection layer**
(`InputBackend.inject(InputEvent)` → Win32 `SendInput` / X11 `XTest`), an
**edge-switch router** (`ControlRouter`), and an **encrypted LAN session**
(`transport.dart` / `session.dart`). 

**Goal:** let a user move and click the cursor with **hand gestures via a webcam**.
The cursor it drives is ENSI's existing one — so a hand can control **this machine
or any paired machine**, reusing the injection + networking we already have.

**This is an input *source*, not a new output path.** The vision pipeline emits
`InputEvent`s; everything downstream already exists.

## 2. Scope

**In (v1):**
- Cross-platform `hand_tracker` Dart package with **one public API** (see §5).
- Hand-landmark inference on-device via `tflite_flutter` (no cloud, no Python).
- Camera capture on **Windows first**, Linux second (same interface).
- Gestures: **move** (index fingertip), **left-click** (pinch), **drag**
  (pinch-hold + move).
- Pointer smoothing (One-Euro filter), configurable active region, X-mirror.
- ENSI integration: a toggle that routes hand input through `ControlRouter`
  (local or remote machine). On-screen calibration + status.

**Out (v1, backlog):** right-click/scroll/multi-hand, macOS/mobile camera,
sign-language/typing gestures, GPU delegates.

## 3. Approach & key decisions

- **One SDK, not per-app code.** Mirror the existing `InputBackend` pattern:
  a `HandTracker` interface with a shared inference core and a swappable,
  per-OS `CameraSource`. ~90% is shared; only frame capture forks per OS.
- **`tflite_flutter`** for inference — it's FFI to the TFLite C API and runs on
  Flutter **desktop** (Win/Linux/macOS) and mobile. Models are the standard
  MediaPipe **`palm_detection`** + **`hand_landmark`** `.tflite` files bundled as
  assets.
- **Windows-first rollout** to de-risk on the dev machine; Linux camera is a
  drop-in `CameraSource` afterward with **zero app changes**.
- **Inference off the UI isolate** (`Isolate`/`compute`) to hold frame rate.

## 4. Architecture

```
 Webcam frames                      hand_tracker package
 ┌───────────────┐   frame    ┌──────────────────────────────────────┐
 │ CameraSource  │──────────▶ │ HandPipeline (shared)                 │
 │  (per-OS)     │            │  palm-detect → ROI → landmark model   │
 └───────────────┘            │  → 21 landmarks → GestureRecognizer   │
                              │  → CursorMapper (One-Euro, mapping)   │
                              └───────────────┬──────────────────────┘
                                              │ Stream<HandPointer>
                                              ▼
                          ENSI adapter: HandPointer → InputEvent
                                              │
                                              ▼
                 backend.inject()  /  ControlRouter  /  session  (EXISTING)
                          local machine            paired machine
```

**Integration mode (v1):** the adapter injects to the **local** cursor
(`InputEvent.mouseMove/down/up`). ENSI's existing host capture + `ControlRouter`
then handle edge-crossing to a remote machine automatically — so the SDK needs to
know nothing about networking. (Mode B, feeding `ControlRouter` directly as a
virtual source, is a later refinement.)

### Module layout
```
packages/hand_tracker/            # standalone, reusable Dart package
  lib/hand_tracker.dart           # public API (HandTracker, HandPointer, config)
  lib/src/pipeline.dart           # palm-detect + landmark + tracking orchestration
  lib/src/palm_detector.dart      # tflite + anchor decode + NMS
  lib/src/landmark_model.dart     # tflite 21-landmark inference
  lib/src/gesture.dart            # pinch/drag state machine
  lib/src/cursor_mapper.dart      # One-Euro filter + frame→screen mapping
  lib/src/camera/camera_source.dart        # interface
  lib/src/camera/windows_camera.dart       # Media Foundation (FFI) — first
  lib/src/camera/linux_camera.dart         # V4L2 (FFI) — second
  assets/palm_detection.tflite, assets/hand_landmark.tflite
lib/input/hand_input_source.dart  # ENSI adapter: HandPointer → InputEvent → inject/router
```

## 5. Public API (contracts the senior dev implements)

```dart
/// One emitted pointer sample (already smoothed + mapped to screen pixels).
class HandPointer {
  final double x, y;            // absolute screen pixels on the local display
  final bool present;          // is a hand currently detected
  final HandGesture gesture;   // none | click | dragStart | dragEnd | drag
  final double confidence;     // 0..1 landmark/presence score
}

enum HandGesture { none, click, dragStart, drag, dragEnd }

class HandTrackerConfig {
  final int targetFps;             // default 30
  final Rect activeRegion;         // normalized 0..1 sub-rect of the frame used
  final bool mirrorX;              // default true (selfie view)
  final double pinchOnThreshold;   // normalized thumb-index distance
  final double pinchOffThreshold;  // hysteresis
  final double minCutoff, beta;    // One-Euro filter params
}

abstract class HandTracker {
  Future<void> start(HandTrackerConfig config);
  Stream<HandPointer> get pointers;   // ~targetFps
  Future<void> calibrate();           // optional: learn active region/neutral
  Future<void> stop();
  Future<void> dispose();
}

abstract class CameraSource {            // the only per-OS piece
  Future<void> open({int width, int height, int fps});
  Stream<CameraFrame> get frames;        // BGRA/RGB bytes + dims + timestamp
  Future<void> close();
}
```

## 6. CV pipeline (the core work)

MediaPipe-style, reimplemented over raw TFLite (this is the bulk of the effort):

1. **Palm detection** (`palm_detection.tflite`, ~192×192 input): SSD-style.
   Dev implements **anchor generation**, box/score decode, and **NMS** → palm
   boxes. Run only when no hand is being tracked (see step 4).
2. **ROI**: from a palm box, compute a square, **rotation-normalized** crop
   (align wrist→middle-finger axis) → landmark model input (~224×224).
3. **Hand landmark** (`hand_landmark.tflite`): outputs **21 (x,y,z)** landmarks +
   **presence** + handedness. Map back through the ROI transform to frame coords.
4. **Tracking optimization**: once landmarks are found, derive next-frame ROI from
   them and **skip palm detection** until presence drops — this is what makes it
   real-time. Re-detect on loss.
5. **Outputs used**: landmark **8** (index tip) → pointer; **4 & 8** distance,
   normalized by hand span (e.g., landmark 0↔9), → pinch.

> Risk note: re-implementing palm post-processing (anchors/NMS) and ROI rotation
> is fiddly. **Mitigation / alt**: evaluate MediaPipe **Tasks** "Hand Landmarker"
> via a thin native (C++) FFI wrapper if raw-TFLite post-processing proves too
> costly — same `HandTracker` API either way.

## 7. Gesture → control mapping

| Gesture | Detection | Action (emits) |
|---|---|---|
| Move | index fingertip (landmark 8) | `mouseMove(x,y)` |
| Left click | pinch thumb↔index (with hysteresis + debounce) | `mouseDown` → `mouseUp` |
| Drag | pinch held > 250 ms then move | `mouseDown` … `mouseMove*` … `mouseUp` |
| (v2) Right-click | thumb↔middle pinch | `mouseDown/Up(button:1)` |
| (v2) Scroll | two-finger vertical | `mouseScroll` |
| Dwell-click (a11y opt) | pointer still > N ms | `mouseDown/Up` |

**Mapping:** fingertip normalized → clamp to `activeRegion` → mirror X → scale to
local screen px. **Smoothing:** One-Euro filter (`minCutoff`, `beta`) — standard
for pointing; low lag when moving, low jitter when still.

## 8. Non-functional requirements

- **≥ 20 fps** sustained (target 30); **end-to-end pointer latency < 80 ms**.
- Inference on a **background isolate**; **drop/skip frames** under load, never
  block the UI.
- Idle CPU when tracking off = 0 (camera released).
- Graceful **no-camera / no-hand** handling; clear status; never crash the app.
- Models bundled as assets; **verify model licenses** before shipping.

## 9. Phases & deliverables (each independently demoable)

1. **Inference spike** — `tflite_flutter` loads `hand_landmark.tflite`, runs on a
   static image, prints 21 landmarks. *Proves desktop inference. (highest risk)*
2. **Windows camera** — `WindowsCameraSource` (Media Foundation FFI) streams
   frames; show a preview + fps.
3. **Full pipeline** — palm-detect + ROI + landmark + tracking → `Stream<HandPointer>`
   at target fps.
4. **Cursor mapper** — One-Euro + screen mapping; move the real cursor (local
   inject) smoothly with the index finger.
5. **Gestures** — pinch click + pinch-hold drag (state machine + debounce).
6. **ENSI integration** — `hand_input_source.dart`: route `HandPointer` →
   `InputEvent` → `inject`/`ControlRouter`; UI **toggle + calibration + status**;
   control local *and* a paired machine.
7. **Linux camera** — `LinuxCameraSource` (V4L2 FFI); no app changes.
8. **Polish** — settings (active region, smoothing, dwell-click a11y), perf pass.

## 10. Test strategy

- **Unit (pure, CI):** One-Euro filter; frame→screen mapping (mirror/clamp/scale);
  pinch state machine from **landmark fixtures**; palm NMS/anchor decode against
  known vectors.
- **Golden:** recorded frames → expected landmark sets (tolerance-based).
- **Integration:** feed a **recorded video** through the pipeline headless →
  assert pointer trajectory/gestures (deterministic, no camera needed).
- **Manual:** latency/jitter feel; lighting/background robustness matrix; control
  a paired ENSI machine end-to-end.

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Raw-TFLite palm post-processing complexity | Spike first; fall back to MediaPipe Tasks via FFI behind same API |
| Desktop camera capture (esp. Linux) | Windows-first; isolate behind `CameraSource`; consider OpenCV FFI if V4L2 is painful |
| Performance / UI jank | Background isolate, frame skipping, tracking-without-redetect |
| Jitter & fatigue ("gorilla arm") | One-Euro filter, active region, dwell-click, on/off hotkey |
| Model licensing | Confirm license of bundled `.tflite`; document |

## 12. Dependencies

`tflite_flutter`, `image` (decode/resize), `vector_math`; per-OS camera via
`dart:ffi` (Media Foundation / V4L2) or `camera_windows`; bundled hand `.tflite`
models. No Python, no cloud.

## 13. Acceptance criteria

- [ ] Move the cursor with the index finger on **Windows** at **≥20 fps**, smooth.
- [ ] **Pinch = click**, **pinch-hold = drag** — reliable with debounce.
- [ ] Toggle hand-control on/off; calibration sets the active region.
- [ ] Works through ENSI to control the **local** machine **and a paired** one
      (cursor crosses the edge like the physical mouse).
- [ ] **Linux** works via the same API by adding only `LinuxCameraSource`.
- [ ] Unit + recorded-video integration tests green in CI.

## 14. Open questions

1. Index-fingertip pointer vs palm-center? (fingertip = precise, palm = stable)
2. Default click gesture: pinch vs dwell? (a11y users prefer dwell)
3. Bundle model size vs accuracy (`_lite` vs `_full` variants)?
4. Camera resolution/fps default (640×480@30 is usually the sweet spot).

## 15. Reuse — existing ENSI seams (don't reinvent)

- Injection: `lib/input/input_backend.dart` → `InputBackend.inject(InputEvent)`.
- Event shape: `lib/models/input_event.dart` (`mouseMove/down/up/scroll`).
- Routing local↔remote: `lib/core/control_router.dart` (`ControlRouter`).
- Host input wiring point: `lib/core/app_state.dart` `becomeHost()` —
  `backend.captureStream().listen(_router.onCaptured)`; add the hand source here.
- Network forwarding: `lib/core/session.dart`, `lib/core/transport.dart`.
