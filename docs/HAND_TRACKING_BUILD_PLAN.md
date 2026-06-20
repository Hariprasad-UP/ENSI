# ENSI Hand-Tracking — Principal Engineer Build Plan

**Status:** APPROVED FOR IMPLEMENTATION · **Decision:** Option B (wrap MediaPipe Tasks)
**Public API:** unchanged from [HAND_TRACKING_SPEC.md](HAND_TRACKING_SPEC.md) §5
**Goal:** cursor + gesture control in production, fastest path, lowest risk.

---

## PHASE 0 — ARCHITECTURE DECISION REVIEW

| Option | Impl effort | Risk | FPS | Latency | Maintenance | Prod-ready |
|---|---|---|---|---|---|---|
| **A** Raw TFLite (custom palm/anchors/NMS/ROI/track) | **20–30 dev-days** | **High** | 25–30 (after huge effort) | good | **High — we own the CV** | **4/10** |
| **B** MediaPipe Tasks + thin C ABI + FFI | **8–12 dev-days** | **Med** (native build) | **30+** | **<60 ms** | **Low — Google owns CV** | **8.5/10** |
| **C** OpenCV + DNN | 12–18 dev-days | Med-High | 15–25 | med | Med | 5/10 |
| **D1** Python sidecar (MediaPipe Python, frozen) | **4–6 dev-days** | **Low** (pip wheels) | 30+ | good (+~8 ms IPC) | Low | 8/10* |
| **D2** Community MediaPipe Flutter plugin | n/a | High (desktop immature) | ? | ? | unknown | 2/10 |

\* D1 is the raw speed champion **but ships a frozen Python runtime (~80 MB)** beside ENSI — conflicts with the stated "one Flutter app / no Python" constraint.

### Decision: **OPTION B**

Reasoning against the priorities (ship speed → risk → maintenance → UX → extensibility):

- **A is rejected.** Re-implementing palm detection, SSD anchor decode, NMS, ROI rotation, and tracking heuristics is exactly the "research project" we must not build. Highest effort, highest ongoing maintenance, and we'd be perpetually chasing MediaPipe's accuracy. Violates rules 2–4.
- **C is rejected.** OpenCV has no first-class hand-landmark model; you end up assembling palm+landmark models yourself → drifts back into Option A's work with worse FPS.
- **D1 (Python sidecar)** is genuinely the *fastest* and *lowest-risk* to a working demo. **If the team relaxes the "no Python" rule, take D1.** Given the user's explicit pure-Flutter / single-binary constraint, it's the documented fallback, not the pick.
- **B is selected.** It honors the OVERRIDE (wrap MediaPipe Tasks — no custom CV), keeps everything in the one ENSI binary, gives Google-grade FPS/latency, and pushes all CV maintenance onto Google. The single real cost is **building/vendoring the MediaPipe native lib once per OS** — a bounded, one-time risk we de-risk in Task 0.

> **The only thing that can change this decision is Task 0** (build/obtain the MediaPipe Tasks native lib for Windows). If Bazel-on-Windows proves intractable in 1 day, **fall back to D1** (Python sidecar) behind the identical `HandTracker` API. ENSI never learns which implementation it got.

---

## PHASE 1 — SPEC ANALYSIS

### Over-engineered (cut these)
1. **Entire raw-TFLite CV pipeline** (spec §6, `palm_detector.dart`, anchors, NMS, ROI). → Replaced by MediaPipe Tasks. **Delete from scope.**
2. **Per-OS Dart camera capture** (`windows_camera.dart` Media Foundation FFI, `linux_camera.dart` V4L2 FFI). → MediaPipe/OpenCV's `VideoCapture` is **already cross-platform** and lives in the native bridge. **No Dart camera FFI needed.** This removes the single most painful per-OS chunk.
3. **Dart↔native per-frame marshalling.** The spec implies frames flow into Dart. At 30 fps × 640×480×4 B = ~37 MB/s copied across the FFI boundary — wasteful. → **Native bridge owns the camera and only returns 21×3 floats per frame.**

### Hidden risks
- **MediaPipe native build (Bazel) on Windows** — the #1 risk. Mitigation: Task 0 spike; vendor prebuilt binaries; or fall back to D1.
- **Click drift** — pinching shifts the fingertip at click instant. Mitigation: freeze pointer ~150 ms on pinch edge.
- **Multi-monitor + DPI mapping** — ENSI hosts report a virtual desktop; mapping normalized→screen must use the **virtual-desktop bounds + per-monitor scale**, not a single screen. Missing from spec.
- **Camera privacy/indicator** — must show when the camera is live; release on stop.

### Simplifications adopted
- Native bridge = **camera + MediaPipe + threading**, one unit. Dart receives landmarks via a `NativeCallable.listener` (async, thread-safe; 30 cb/s is not a hot path).
- Dart does only **cheap** post-processing (gesture state machine + One-Euro + mapping) — runs comfortably on the platform thread.

### Performance bottlenecks & fixes
- UI jank → all capture+inference on the **native thread**; Dart gets floats.
- GC pressure → reuse typed-data buffers; no per-frame allocation in Dart.
- Latency → no frame round-trip to Dart; landmark→inject path is microseconds.

### Missing requirements (added)
- Multi-monitor/DPI-correct mapping; global **enable/disable hotkey** (panic-off); camera-in-use indicator; calibration persistence (`shared_preferences`); graceful camera-unplug recovery; metrics (fps, dropped frames) for the status UI.

---

## PHASE 2 — FINAL ARCHITECTURE

### Component diagram
```
┌───────────────────────────── ENSI (Flutter / Dart) ─────────────────────────────┐
│                                                                                   │
│  UI: HandControlToggle ──▶ AppState.enableHandTracking()                          │
│                                   │                                               │
│                            HandInputSource (adapter)                              │
│                                   │  HandPointer stream                           │
│                            HandTrackerImpl ──── GestureRecognizer                 │
│                                   │        └──── CursorMapper(OneEuroFilter)       │
│                                   │ landmarks (NativeCallable.listener)            │
│                            MediaPipeBridge (dart:ffi)                             │
│                                   │  InputEvent                                    │
│                     ┌─────────────┴─────────────┐                                 │
│                     ▼                           ▼                                 │
│            InputBackend.inject()        ControlRouter ── Session ── Transport ──▶ remote
└───────────────────────────────────────│──────────────────────────────────────────┘
                                         │ C ABI (extern "C")
                 ┌───────────────────────▼────────────────────────┐
                 │  libensi_handbridge  (C++ , per-OS .dll/.so)    │
                 │   OpenCV VideoCapture ─▶ MediaPipe HandLandmarker│
                 │   native worker thread ─▶ landmark callback      │
                 └─────────────────────────────────────────────────┘
```

### Data flow
`camera frame (native) → MediaPipe (native) → 21 landmarks (native) → C callback → NativeCallable.listener (Dart) → GestureRecognizer + CursorMapper → HandPointer → InputEvent → inject()/ControlRouter`.

### Sequence (per frame, steady state)
```
NativeThread: grab frame → landmarker.detect() → pack 63 floats → invoke cb(ptr)
Dart(listener): copy floats → recognizer.update() → mapper.map() → emit HandPointer
HandInputSource: HandPointer → InputEvent(mouseMove/down/up) → backend.inject()  (local)
                                                              → _router.onCaptured (edge→remote)
```

### Threading / isolate model
- **Native worker thread** (inside the bridge): owns camera + inference loop. Never blocks Dart.
- **Dart platform thread**: receives landmark callbacks (async via `NativeCallable.listener`), runs the *cheap* gesture/mapper math, emits the stream. **No Dart isolate required** (work is <0.2 ms/frame).
- Backpressure: bridge keeps only the **latest** result (drops stale frames) — pointer never lags behind reality.

### Native bridge architecture
- One C++ TU compiled to `libensi_handbridge.{dll,so}` linking MediaPipe Tasks + OpenCV.
- Exposes a tiny stable **C ABI** (Phase 5). MediaPipe types never cross the boundary.

### Memory lifecycle
- `create()` loads the `.task` model once + opens camera. Buffers (frame, landmark scratch) allocated once, reused.
- Per-callback: 63 floats copied into Dart (`Float32List`) inside the listener; native buffer reused.
- `destroy()` stops the thread, releases camera, frees model + buffers. Dart closes the `NativeCallable`.

---

## PHASE 3 — FOLDER STRUCTURE (every file)

```
packages/hand_tracker/
  pubspec.yaml
  lib/
    hand_tracker.dart                 # PUBLIC API (unchanged): HandTracker, HandPointer,
                                      #   HandGesture, HandTrackerConfig, CameraSource(SPI)
    src/
      hand_tracker_impl.dart          # wires bridge → gesture → mapper → Stream<HandPointer>
      mediapipe_bridge.dart           # dart:ffi bindings + NativeCallable + lifecycle
      gesture.dart                    # pinch/drag state machine (hysteresis/debounce)
      cursor_mapper.dart              # normalized→screen mapping (multi-monitor/DPI)
      one_euro_filter.dart            # 1€ filter (pure)
      landmarks.dart                  # Landmarks value type (21×3) + named accessors
      camera_source.dart              # SPI kept for optional Dart-owned-camera mode (not used in B)
  native/
    CMakeLists.txt                    # builds libensi_handbridge (Win + Linux)
    src/handbridge.cc                 # C++ shim: OpenCV cap + MediaPipe HandLandmarker
    include/handbridge.h              # extern "C" ABI
    third_party/                      # vendored MediaPipe + OpenCV libs/headers (per-OS)
  assets/
    hand_landmarker.task              # MediaPipe Tasks bundle (palm+landmark+tracking)
  test/
    one_euro_filter_test.dart
    cursor_mapper_test.dart
    gesture_test.dart
    landmarks_test.dart
    pipeline_replay_test.dart         # recorded-landmark-stream → pointer/gesture asserts

lib/input/hand_input_source.dart      # ENSI adapter: HandPointer → InputEvent → inject/router
lib/ui/hand_control_tile.dart         # toggle + status + calibrate button
# wiring: lib/core/app_state.dart (enable/disable), pubspec.yaml (path dep + asset)
windows/  linux/                      # CMake hooks to copy libensi_handbridge + asset to bundle
```

---

## PHASE 4 — DART CODE SKELETONS

### `lib/hand_tracker.dart` (PUBLIC — unchanged contract)
```dart
import 'dart:async';
import 'dart:ui' show Rect;

enum HandGesture { none, click, dragStart, drag, dragEnd }

/// One emitted pointer sample — already smoothed + mapped to screen pixels.
class HandPointer {
  final double x, y;          // absolute local-screen pixels
  final bool present;
  final HandGesture gesture;
  final double confidence;    // 0..1
  const HandPointer({
    required this.x, required this.y, required this.present,
    required this.gesture, required this.confidence,
  });
}

class HandTrackerConfig {
  final int targetFps;
  final Rect activeRegion;     // normalized 0..1 sub-rect of the frame
  final bool mirrorX;
  final double pinchOnThreshold, pinchOffThreshold;  // hysteresis
  final double minCutoff, beta;                       // 1€ filter
  final int cameraIndex, frameWidth, frameHeight;
  const HandTrackerConfig({
    this.targetFps = 30,
    this.activeRegion = const Rect.fromLTWH(0.15, 0.15, 0.7, 0.7),
    this.mirrorX = true,
    this.pinchOnThreshold = 0.045,
    this.pinchOffThreshold = 0.07,
    this.minCutoff = 1.0, this.beta = 0.007,
    this.cameraIndex = 0, this.frameWidth = 640, this.frameHeight = 480,
  });
}

abstract class HandTracker {
  Future<void> start(HandTrackerConfig config);
  Stream<HandPointer> get pointers;
  Future<void> calibrate();
  Future<void> stop();
  Future<void> dispose();

  /// Factory hides the implementation (Option B today; D1 swappable later).
  factory HandTracker() = HandTrackerImpl;   // wired via part/export
}
```

### `lib/src/hand_tracker_impl.dart`
```dart
class HandTrackerImpl implements HandTracker {
  final _out = StreamController<HandPointer>.broadcast();
  late final MediaPipeBridge _bridge;
  late GestureRecognizer _gesture;
  late CursorMapper _mapper;
  HandTrackerConfig? _cfg;
  bool _running = false;

  @override Stream<HandPointer> get pointers => _out.stream;

  @override
  Future<void> start(HandTrackerConfig config) async {
    if (_running) return;
    _cfg = config;
    _gesture = GestureRecognizer(config);
    _mapper = CursorMapper(config);          // resolves screen bounds/DPI
    _bridge = MediaPipeBridge();
    await _bridge.create(
      modelAsset: 'packages/hand_tracker/assets/hand_landmarker.task',
      config: config,
      onLandmarks: _onLandmarks,             // NativeCallable.listener
      onError: (e) => _out.addError(e),
    );
    await _bridge.start();
    _running = true;
  }

  void _onLandmarks(Landmarks lm) {
    if (!_running) return;
    final g = _gesture.update(lm);           // HandGesture + filtered pinch
    final p = _mapper.map(lm.indexTip, g, lm.presence); // 1€ + screen px
    if (!_out.isClosed) _out.add(p);
  }

  @override Future<void> calibrate() => _mapper.calibrate(_bridge);
  @override Future<void> stop() async { _running = false; await _bridge.stop(); }
  @override Future<void> dispose() async {
    _running = false;
    await _bridge.destroy();
    await _out.close();
  }
}
```

### `lib/src/mediapipe_bridge.dart`
```dart
typedef _LandmarksNative = Void Function(Pointer<Float> xyz63, Int32 count,
    Float presence, Int32 handedness, Int64 tsUs);
typedef _Create = Int32 Function(Pointer<Utf8> model, Int32 cam, Int32 w,
    Int32 h, Int32 fps, Pointer<NativeFunction<_LandmarksNative>> cb,
    Pointer<Pointer<Void>> outHandle);
// ... start/stop/destroy/lastError typedefs ...

class MediaPipeBridge {
  late final DynamicLibrary _lib;       // ensi_handbridge.dll / .so
  Pointer<Void> _handle = nullptr;
  NativeCallable<_LandmarksNative>? _cb;
  void Function(Landmarks)? _onLandmarks;

  Future<void> create({required String modelAsset, required HandTrackerConfig config,
      required void Function(Landmarks) onLandmarks,
      required void Function(Object) onError}) async {
    _lib = _open();                                  // platform-specific name
    _onLandmarks = onLandmarks;
    _cb = NativeCallable<_LandmarksNative>.listener(_trampoline); // async, thread-safe
    final modelPath = await _materializeAsset(modelAsset);        // copy asset → temp file
    final out = calloc<Pointer<Void>>();
    final rc = _createFn(modelPath.toNativeUtf8(), config.cameraIndex,
        config.frameWidth, config.frameHeight, config.targetFps,
        _cb!.nativeFunction, out);
    if (rc != 0) { onError(HandTrackerException(_lastError())); return; }
    _handle = out.value; calloc.free(out);
  }

  void _trampoline(Pointer<Float> xyz, int n, double presence, int handed, int ts) {
    if (n < 63) return;
    final data = xyz.asTypedList(63);                // copy out (native buffer reused)
    _onLandmarks?.call(Landmarks.fromFloat32(Float32List.fromList(data),
        presence: presence, handedness: handed, tsUs: ts));
  }
  Future<void> start();  Future<void> stop();  Future<void> destroy();
}
```

### `lib/src/one_euro_filter.dart`
```dart
/// 1€ filter (Casiez et al.) — low jitter at rest, low lag in motion. Pure.
class OneEuroFilter {
  final double minCutoff, beta, dCutoff;
  double? _xPrev, _dxPrev; int? _tPrevUs;
  OneEuroFilter({this.minCutoff = 1.0, this.beta = 0.007, this.dCutoff = 1.0});

  double filter(double x, int tUs) {
    if (_tPrevUs == null) { _xPrev = x; _dxPrev = 0; _tPrevUs = tUs; return x; }
    final dt = (tUs - _tPrevUs!) / 1e6; if (dt <= 0) return _xPrev!;
    final dx = (x - _xPrev!) / dt;
    final edx = _lp(dx, _alpha(dCutoff, dt), _dxPrev!); _dxPrev = edx;
    final cutoff = minCutoff + beta * edx.abs();
    final ex = _lp(x, _alpha(cutoff, dt), _xPrev!);
    _xPrev = ex; _tPrevUs = tUs; return ex;
  }
  static double _alpha(double c, double dt) { final t = 1/(2*3.14159*c); return 1/(1+t/dt); }
  static double _lp(double v, double a, double prev) => a*v + (1-a)*prev;
  void reset() { _xPrev = _dxPrev = null; _tPrevUs = null; }
}
```

### `lib/src/cursor_mapper.dart`
```dart
/// Maps normalized fingertip → absolute screen px across the virtual desktop,
/// with active-region crop, X-mirror, 1€ smoothing, and freeze-on-click.
class CursorMapper {
  final HandTrackerConfig cfg;
  final _fx = OneEuroFilter(), _fy = OneEuroFilter();
  late Rect _screen;            // virtual-desktop bounds (queried from backend)
  int _freezeUntilUs = 0; double _lx = 0, _ly = 0;
  CursorMapper(this.cfg);

  HandPointer map(Point3 tip, HandGesture g, double presence) {
    final tUs = tip.tsUs;
    if (g == HandGesture.click || g == HandGesture.dragStart) {
      _freezeUntilUs = tUs + 150000;          // freeze 150 ms — kill click drift
    }
    if (tUs < _freezeUntilUs) {
      return HandPointer(x:_lx,y:_ly,present:presence>0.5,gesture:g,confidence:presence);
    }
    var nx = ((tip.x - cfg.activeRegion.left) / cfg.activeRegion.width).clamp(0.0,1.0);
    final ny = ((tip.y - cfg.activeRegion.top) / cfg.activeRegion.height).clamp(0.0,1.0);
    if (cfg.mirrorX) nx = 1 - nx;
    _lx = _fx.filter(_screen.left + nx*_screen.width, tUs);
    _ly = _fy.filter(_screen.top  + ny*_screen.height, tUs);
    return HandPointer(x:_lx,y:_ly,present:presence>0.5,gesture:g,confidence:presence);
  }
  Future<void> calibrate(MediaPipeBridge b) async { /* learn active region/neutral */ }
}
```

### `lib/src/gesture.dart`
```dart
/// Pinch→click/drag with hysteresis (on/off thresholds), debounce, and
/// confidence gating. Emits exactly one click per pinch; drag after hold.
class GestureRecognizer {
  final HandTrackerConfig cfg;
  bool _pinched = false; int _pinchStartUs = 0; bool _dragging = false;
  int _lastClickUs = 0;
  static const _dragHoldUs = 250000, _debounceUs = 200000, _minConf = 0.5;
  GestureRecognizer(this.cfg);

  HandGesture update(Landmarks lm) {
    if (lm.presence < _minConf) { return _release(lm.tsUs); }
    final d = lm.pinchDistance;                       // |thumbTip-indexTip| / handSpan
    final on = d < cfg.pinchOnThreshold, off = d > cfg.pinchOffThreshold;
    if (!_pinched && on) { _pinched = true; _pinchStartUs = lm.tsUs; return HandGesture.none; }
    if (_pinched && !_dragging && lm.tsUs - _pinchStartUs > _dragHoldUs) {
      _dragging = true; return HandGesture.dragStart;
    }
    if (_pinched && _dragging) return HandGesture.drag;
    if (_pinched && off) return _release(lm.tsUs);     // pinch released
    return HandGesture.none;
  }
  HandGesture _release(int tUs) {
    final wasDrag = _dragging; final wasPinch = _pinched;
    _pinched = _dragging = false;
    if (wasDrag) return HandGesture.dragEnd;
    if (wasPinch && tUs - _lastClickUs > _debounceUs) { _lastClickUs = tUs; return HandGesture.click; }
    return HandGesture.none;
  }
}
```

### `lib/input/hand_input_source.dart` (ENSI adapter — reuses existing engine)
```dart
/// Bridges HandTracker → ENSI's existing input pipeline. Knows nothing about CV.
class HandInputSource {
  final HandTracker _tracker;
  final InputBackend _backend;        // inject locally; ControlRouter handles edge→remote
  StreamSubscription<HandPointer>? _sub;
  HandInputSource(this._tracker, this._backend);

  Future<void> enable(HandTrackerConfig cfg) async {
    await _tracker.start(cfg);
    _sub = _tracker.pointers.listen(_onPointer);
  }
  void _onPointer(HandPointer p) {
    if (!p.present) return;
    _backend.inject(InputEvent(type: InputEventType.mouseMove, x: p.x, y: p.y));
    switch (p.gesture) {
      case HandGesture.click:
        _backend.inject(const InputEvent(type: InputEventType.mouseDown, button: 0));
        _backend.inject(const InputEvent(type: InputEventType.mouseUp, button: 0));
      case HandGesture.dragStart:
        _backend.inject(const InputEvent(type: InputEventType.mouseDown, button: 0));
      case HandGesture.dragEnd:
        _backend.inject(const InputEvent(type: InputEventType.mouseUp, button: 0));
      default: break;
    }
  }
  Future<void> disable() async { await _sub?.cancel(); await _tracker.stop(); }
}
```
> Integration choice: injecting the **local** cursor lets ENSI's existing host capture + `ControlRouter` carry it across the edge to a paired machine for free. (Mode B — feed `ControlRouter` directly — is a later option, same adapter.)

### `lib/src/camera_source.dart` (SPI — **not used in Option B**)
```dart
/// Retained only for a possible Dart-owned-camera mode. In Option B the native
/// bridge owns the camera (OpenCV), so windows_camera.dart / linux_camera.dart
/// are intentionally NOT implemented. Kept to preserve the spec's SPI shape.
abstract class CameraSource {
  Future<void> open({int width, int height, int fps});
  Stream<CameraFrame> get frames;
  Future<void> close();
}
```

---

## PHASE 5 — NATIVE MEDIAPIPE INTEGRATION

### C ABI — `native/include/handbridge.h`
```c
#ifdef __cplusplus
extern "C" {
#endif
// 21 landmarks × (x,y,z) normalized to image; presence 0..1; handedness 0/1.
typedef void (*ensi_landmarks_cb)(const float* xyz63, int count,
                                  float presence, int handedness, long long ts_us);

int  ensi_ht_create(const char* model_path, int cam_index, int width,
                    int height, int fps, ensi_landmarks_cb cb, void** out_handle);
int  ensi_ht_start(void* handle);
int  ensi_ht_stop(void* handle);
void ensi_ht_destroy(void* handle);
const char* ensi_ht_last_error(void);
#ifdef __cplusplus
}
#endif
```

### `native/src/handbridge.cc` (shim — no custom CV)
```cpp
// Owns: cv::VideoCapture + mediapipe HandLandmarker (Tasks C++). Worker thread
// grabs frames, runs landmarker.Detect(), packs 63 floats, invokes cb.
struct Bridge {
  cv::VideoCapture cap;
  std::unique_ptr<mediapipe::tasks::vision::HandLandmarker> landmarker;
  ensi_landmarks_cb cb; std::thread worker; std::atomic<bool> running{false};
  void loop();   // grab → Detect → pack landmark 0..20 → cb(...)
};
// ensi_ht_create: build HandLandmarkerOptions{model_path, num_hands=1,
//   running_mode=VIDEO}, open camera. start: launch worker. stop/destroy: join+free.
```

### Windows — `native/CMakeLists.txt` + bundling
```cmake
add_library(ensi_handbridge SHARED src/handbridge.cc)
target_include_directories(ensi_handbridge PRIVATE include third_party/mediapipe/include
                                                    ${OpenCV_INCLUDE_DIRS})
target_link_libraries(ensi_handbridge PRIVATE mediapipe_tasks_vision ${OpenCV_LIBS})
# windows/CMakeLists.txt: install ensi_handbridge.dll + opencv dlls + .task to $<TARGET_FILE_DIR:ensi>
```
- DLL: `ensi_handbridge.dll` (+ MediaPipe/OpenCV runtime DLLs) copied next to `ensi.exe`.
- Dart binding: `DynamicLibrary.open('ensi_handbridge.dll')`.

### Linux — CMake + bundling
```cmake
# Same target → libensi_handbridge.so. linux/CMakeLists.txt installs it +
# libopencv_*.so + .task into the bundle's lib/ ; set RPATH=$ORIGIN/lib.
```
- Dart binding: `DynamicLibrary.open('libensi_handbridge.so')` (RPATH-resolved).

### Dart bindings — exact signatures: see `mediapipe_bridge.dart` (Phase 4).

> **Task 0** validates this whole phase: produce `ensi_handbridge.dll` that loads `hand_landmarker.task` and prints landmarks for one webcam frame. If the MediaPipe build can't be tamed in ~1 day, switch the bridge body to talk to a **frozen-Python MediaPipe sidecar over a localhost socket** — the C ABI / Dart side are unchanged.

---

## PHASE 6 — GESTURE SYSTEM
(Full state machine in `gesture.dart`, Phase 4.) Guarantees:
- **Move:** index tip every frame while `presence ≥ 0.5`.
- **Click:** pinch on→off within `_dragHoldUs`, **debounced** `200 ms`; exactly one click.
- **Drag:** pinch held `>250 ms` → `dragStart`; `drag` while held+moving; `dragEnd` on release.
- **Hysteresis:** separate `pinchOn (0.045)` / `pinchOff (0.07)` thresholds → no flicker.
- **Confidence gating:** below `0.5` presence forces a safe release (no stuck button).
- **Failure recovery:** hand lost mid-drag → emit `dragEnd` (NFR-2 parity: never leave a button down). Camera error → `HandTracker` emits stream error → UI disables.

---

## PHASE 7 — ENSI INTEGRATION (reuse only)
- `HandInputSource` (Phase 4) → `InputBackend.inject(InputEvent)` — **existing**.
- Cross-machine: handled by **existing** host capture + `ControlRouter` + `Session`/`Transport`. **No new routing.**
- `app_state.dart`: add `enableHandTracking()/disableHandTracking()` that own a `HandInputSource`; expose status for the UI.
- `hand_control_tile.dart`: toggle + live status (fps, present) + Calibrate + a global disable hotkey.

---

## PHASE 8 — TESTING STRATEGY (exact cases)

**Unit (pure, CI):**
- `one_euro_filter_test`: step input settles; constant input → constant out; higher speed → less lag (alpha monotonic).
- `cursor_mapper_test`: center→screen center; mirrorX flips; activeRegion crop maps edges to 0/full; freeze-on-click holds last point for 150 ms; multi-monitor virtual bounds.
- `gesture_test` (landmark fixtures): pinch→1 click; quick double pinch within debounce→1 click; hold→dragStart→drag→dragEnd; presence drop mid-drag→dragEnd; hysteresis no-flicker around threshold.
- `landmarks_test`: `fromFloat32` indexing (tip=8, thumb=4), pinchDistance normalization.

**Golden:** serialized landmark frames → expected `HandPointer`/gesture sequence (tolerance).

**Recorded-video / replay:** `pipeline_replay_test` feeds a recorded **landmark stream** (captured once from the bridge) through `HandTrackerImpl` (bridge stubbed) → assert pointer trajectory + gesture order. Deterministic, no camera/native in CI.

**E2E (manual + scripted):** webcam → cursor moves at ≥20 fps; pinch clicks a target; drag moves a window; control a **paired** ENSI machine across the edge; camera unplug → graceful disable.

---

## PHASE 9 — IMPLEMENTATION ROADMAP

| # | Task | Files | Cx | Risk | Hrs | Acceptance |
|---|---|---|---|---|---|---|
| 0 | **MediaPipe native spike** | native/* | H | **H** | 8–12 | `ensi_handbridge.dll` prints landmarks for 1 webcam frame; else fall back to D1 |
| 1 | Package scaffold + public API | pubspec, hand_tracker.dart, landmarks.dart | L | L | 2 | `dart analyze` clean; API matches spec §5 |
| 2 | One-Euro filter + tests | one_euro_filter.dart, test | L | L | 2 | unit tests green |
| 3 | Gesture recognizer + tests | gesture.dart, test | M | L | 4 | fixture tests green (click/drag/hysteresis) |
| 4 | Cursor mapper + tests | cursor_mapper.dart, test | M | M | 4 | mapping/mirror/freeze/multi-monitor tests green |
| 5 | FFI bridge + NativeCallable | mediapipe_bridge.dart | M | M | 6 | landmark callbacks reach Dart from the dll |
| 6 | HandTrackerImpl wiring | hand_tracker_impl.dart | M | L | 4 | live `Stream<HandPointer>` from webcam |
| 7 | ENSI adapter + app_state | hand_input_source.dart, app_state.dart | L | L | 4 | hand moves the local cursor + clicks |
| 8 | UI toggle/status/calibrate | hand_control_tile.dart | L | L | 4 | enable/disable/calibrate from UI |
| 9 | Replay/integration tests | pipeline_replay_test.dart | M | L | 4 | deterministic replay green in CI |
| 10 | Windows bundling | windows/CMake, native/CMake | M | M | 4 | dll+asset ship next to ensi.exe |
| 11 | Linux camera/bundle | native/CMake, linux/CMake | M | M | 6 | works on Ubuntu via same API |
| 12 | Polish (hotkey, drift, perf) | mapper/gesture/ui | M | L | 6 | ≥20 fps, no click drift, panic-off |

**Critical path:** Task 0 → 5 → 6 → 7. Tasks 2,3,4,9 are pure-Dart and parallelizable immediately (no native dependency).

---

## PHASE 10 — CLAUDE CODE EXECUTION PROMPTS

> Each is self-contained, independently testable, minimal overlap. Start 1–4 now (pure Dart); 0/5 unblock the rest.

**Task 1 —** "Create `packages/hand_tracker` Flutter package. Add `lib/hand_tracker.dart` with the exact public API from docs/HAND_TRACKING_SPEC.md §5 (HandTracker, HandPointer, HandGesture, HandTrackerConfig) plus `lib/src/landmarks.dart` (Landmarks value type over a Float32List of 21×3 with named accessors indexTip=8, thumbTip=4, wrist=0, and `pinchDistance`). Add a path dependency from the root app. `dart analyze` must be clean."

**Task 2 —** "Implement `lib/src/one_euro_filter.dart` (1€ filter, µs timestamps) + `test/one_euro_filter_test.dart`: settles to constant input, reduces lag as speed rises, reset() clears state."

**Task 3 —** "Implement `lib/src/gesture.dart` `GestureRecognizer` per docs/HAND_TRACKING_BUILD_PLAN.md Phase 6 + `test/gesture_test.dart` using synthetic Landmarks fixtures: one click per pinch, debounce, drag after 250 ms hold, dragEnd on loss, hysteresis no-flicker."

**Task 4 —** "Implement `lib/src/cursor_mapper.dart` (activeRegion crop, mirrorX, 1€ smoothing, freeze-on-click 150 ms, virtual-desktop mapping; screen bounds injected for tests) + `test/cursor_mapper_test.dart`."

**Task 0 —** "Create `native/` (handbridge.h, handbridge.cc, CMakeLists.txt). Build `ensi_handbridge.dll` on Windows that links MediaPipe Tasks HandLandmarker + OpenCV, opens camera 0, and prints 21 landmarks for one frame. Document the exact build steps. If the MediaPipe build is not working within the timebox, STOP and report — we switch to the Python-sidecar bridge body behind the same ABI."

**Task 5 —** "Implement `lib/src/mediapipe_bridge.dart`: dart:ffi bindings to handbridge.h, `NativeCallable.listener` trampoline → `Landmarks`, asset-materialization for the `.task`, full create/start/stop/destroy lifecycle + error propagation."

**Task 6 —** "Implement `lib/src/hand_tracker_impl.dart` wiring bridge → GestureRecognizer → CursorMapper → `Stream<HandPointer>`; lifecycle + dispose."

**Task 7 —** "Add `lib/input/hand_input_source.dart` (HandPointer → InputEvent → `InputBackend.inject`) and `enableHandTracking/disableHandTracking` in `lib/core/app_state.dart`. Reuse ControlRouter; introduce no new routing."

**Task 8 —** "Add `lib/ui/hand_control_tile.dart`: toggle, live status (fps/present), Calibrate, global disable hotkey; wire into home screen."

**Task 9 —** "Add `test/pipeline_replay_test.dart`: feed a recorded landmark stream through HandTrackerImpl with a stub bridge; assert pointer trajectory + gesture order. Deterministic, CI-safe."

**Task 10/11 —** "Wire `native/CMakeLists.txt` into windows/ and linux/ builds so `ensi_handbridge` + runtime libs + `hand_landmarker.task` ship in the bundle (RPATH=$ORIGIN/lib on Linux)."

**Task 12 —** "Polish: panic-off hotkey, verify freeze-on-click kills drift, perf pass to ≥20 fps, status metrics."

---

## FINAL DECISION STATEMENT

The specification's **Option A (raw-TFLite custom CV) is rejected** as the slowest, riskiest, highest-maintenance path. It is **replaced by Option B**: wrap **MediaPipe Hand Landmarker Tasks** behind a thin C ABI + `dart:ffi`, with the **native bridge owning camera + inference** (eliminating per-OS Dart camera code and per-frame marshalling). The **public `HandTracker` API is preserved verbatim** — ENSI cannot tell which engine runs, so we can swap to the **Python-sidecar fallback (D1)** without touching app code if Task 0 fails. This is the fastest path to a reliable, low-maintenance, cross-platform production feature that reuses ENSI's existing injection + routing + transport.
