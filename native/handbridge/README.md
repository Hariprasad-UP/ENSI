# ensi_handbridge — native hand-tracking bridge

Produces `ensi_handbridge.dll` (Windows) / `libensi_handbridge.so` (Linux) that
the Dart side ([lib/hand/mediapipe_bridge.dart](../../lib/hand/mediapipe_bridge.dart))
loads via `dart:ffi`. Implements the C ABI in [include/handbridge.h](include/handbridge.h):
OpenCV camera capture → MediaPipe Hand Landmarker → 21×3 landmark floats via callback.

The whole Dart app **builds and runs without this library** — `MediaPipeBridge`
reports `available == false` and the Hand-cursor toggle shows "unavailable" until
the lib + model are present.

## Inputs you must supply
1. **OpenCV** dev libs (`find_package(OpenCV)` must succeed).
2. **MediaPipe Tasks (Vision)** headers + prebuilt libs under
   `third_party/mediapipe/{include,lib}` (MediaPipe builds with **Bazel**; build
   `:hand_landmarker` once and vendor the artifacts, or use a prebuilt).
3. The model bundle **`hand_landmarker.task`** placed at
   `lib/hand/assets/hand_landmarker.task` and declared in `pubspec.yaml` assets.

## Build (Task 0 — the de-risking spike)
```bash
cmake -S native/handbridge -B build/handbridge -DOpenCV_DIR=<opencv> \
      -DMEDIAPIPE_DIR=<vendored-mediapipe>
cmake --build build/handbridge --config Release
# copy ensi_handbridge.{dll,so} (+ OpenCV/MediaPipe runtime libs) next to the ENSI binary
```
Acceptance: launching ENSI → Hand-cursor toggle enables; index finger moves the
cursor; pinch clicks.

## If the MediaPipe Bazel build is impractical (fallback D1)
Keep this exact C ABI but implement the worker loop as an **IPC client to a
frozen-Python MediaPipe sidecar** (mediapipe + opencv via PyInstaller). The Dart
side does not change. See docs/HAND_TRACKING_BUILD_PLAN.md Phase 0 (Option D1).

## Bundling (Tasks 10/11)
Add an `install`/copy step in `windows/CMakeLists.txt` and `linux/CMakeLists.txt`
to ship `ensi_handbridge` + OpenCV/MediaPipe runtime + `hand_landmarker.task` in
the app bundle (Linux: `RPATH=$ORIGIN`).
