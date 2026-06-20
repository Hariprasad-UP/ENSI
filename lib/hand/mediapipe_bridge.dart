import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'hand_tracker.dart';
import 'landmark_source.dart';
import 'landmarks.dart';

// --- C ABI (native/include/handbridge.h) ----------------------------------
typedef _LandmarksNative = Void Function(
    Pointer<Float>, Int32, Float, Int32, Int64);
typedef _CreateNative = Int32 Function(
    Pointer<Utf8>, Int32, Int32, Int32, Int32,
    Pointer<NativeFunction<_LandmarksNative>>, Pointer<Pointer<Void>>);
typedef _CreateDart = int Function(Pointer<Utf8>, int, int, int, int,
    Pointer<NativeFunction<_LandmarksNative>>, Pointer<Pointer<Void>>);
typedef _HandleNative = Int32 Function(Pointer<Void>);
typedef _HandleDart = int Function(Pointer<Void>);
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);
typedef _LastErrNative = Pointer<Utf8> Function();
typedef _LastErrDart = Pointer<Utf8> Function();

const String _modelAsset = 'assets/hand_landmarker.task';

/// Real [LandmarkSource]: FFI to `ensi_handbridge` (OpenCV + MediaPipe Tasks).
/// Degrades gracefully — if the native library or model isn't present,
/// [available] is false and [start] throws a clear [HandTrackerException]
/// rather than crashing the app. (Build it via docs Task 0, or swap the
/// native body for the Python-sidecar fallback — this Dart side is unchanged.)
class MediaPipeBridge implements LandmarkSource {
  final _controller = StreamController<Landmarks>.broadcast();
  DynamicLibrary? _lib;
  Pointer<Void> _handle = nullptr;
  NativeCallable<_LandmarksNative>? _cb;
  bool? _availableCache;

  @override
  Stream<Landmarks> get landmarks => _controller.stream;

  @override
  bool get available => _availableCache ??= _probe();

  bool _probe() {
    try {
      _openLib();
      return true;
    } catch (_) {
      return false;
    }
  }

  DynamicLibrary _openLib() {
    if (Platform.isWindows) return DynamicLibrary.open('ensi_handbridge.dll');
    if (Platform.isLinux) return DynamicLibrary.open('libensi_handbridge.so');
    throw HandTrackerException('hand tracking is not supported on this OS');
  }

  @override
  Future<void> start(HandTrackerConfig config) async {
    if (_handle != nullptr) return;
    final lib = _lib ??= _openLib(); // throws if missing → caller handles
    final create = lib.lookupFunction<_CreateNative, _CreateDart>('ensi_ht_create');
    final startFn = lib.lookupFunction<_HandleNative, _HandleDart>('ensi_ht_start');
    final lastErr =
        lib.lookupFunction<_LastErrNative, _LastErrDart>('ensi_ht_last_error');

    final modelPath = await _materializeModel();
    _cb = NativeCallable<_LandmarksNative>.listener(_onNativeLandmarks);

    final pModel = modelPath.toNativeUtf8();
    final out = calloc<Pointer<Void>>();
    try {
      final rc = create(pModel, config.cameraIndex, config.frameWidth,
          config.frameHeight, config.targetFps, _cb!.nativeFunction, out);
      if (rc != 0) {
        throw HandTrackerException(lastErr().toDartString());
      }
      _handle = out.value;
      startFn(_handle);
    } finally {
      calloc.free(pModel);
      calloc.free(out);
    }
  }

  void _onNativeLandmarks(
      Pointer<Float> xyz, int count, double presence, int handedness, int tsUs) {
    if (count < 63 || _controller.isClosed) return;
    final copy = Float32List.fromList(xyz.asTypedList(63)); // copy out of native buffer
    _controller.add(Landmarks(copy,
        presence: presence, handedness: handedness, tsUs: tsUs));
  }

  /// Copy the bundled `.task` model out to a temp file the native side can read.
  Future<String> _materializeModel() async {
    final data = await rootBundle.load('packages/hand_tracker/$_modelAsset')
        .catchError((_) => rootBundle.load(_modelAsset));
    final file = File('${Directory.systemTemp.path}/ensi_hand_landmarker.task');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }

  @override
  Future<void> stop() async {
    final lib = _lib;
    if (lib != null && _handle != nullptr) {
      lib.lookupFunction<_HandleNative, _HandleDart>('ensi_ht_stop')(_handle);
    }
  }

  @override
  Future<void> dispose() async {
    final lib = _lib;
    if (lib != null && _handle != nullptr) {
      lib.lookupFunction<_DestroyNative, _DestroyDart>('ensi_ht_destroy')(_handle);
    }
    _handle = nullptr;
    _cb?.close();
    _cb = null;
    if (!_controller.isClosed) await _controller.close();
  }
}
