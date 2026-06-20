// ENSI hand-tracking native bridge — stable C ABI.
//
// Implemented by libensi_handbridge (OpenCV camera + MediaPipe Hand Landmarker).
// The Dart side (lib/hand/mediapipe_bridge.dart) FFIs exactly these symbols.
// Keep this ABI stable: MediaPipe/OpenCV types must never cross it.
#ifndef ENSI_HANDBRIDGE_H
#define ENSI_HANDBRIDGE_H

#include <stdint.h>

#ifdef _WIN32
#define ENSI_API __declspec(dllexport)
#else
#define ENSI_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Called once per processed frame on the bridge's worker thread.
//   xyz63      : 21 landmarks * (x,y,z), x/y normalized 0..1 to the image.
//   count      : number of floats (== 63 when a hand is present).
//   presence   : 0..1 hand-presence/landmark confidence.
//   handedness : 0 = left, 1 = right.
//   ts_us      : capture timestamp in microseconds.
typedef void (*ensi_landmarks_cb)(const float* xyz63, int count,
                                  float presence, int handedness,
                                  int64_t ts_us);

// Returns 0 on success, non-zero on failure (see ensi_ht_last_error()).
ENSI_API int  ensi_ht_create(const char* model_path, int cam_index,
                             int width, int height, int fps,
                             ensi_landmarks_cb cb, void** out_handle);
ENSI_API int  ensi_ht_start(void* handle);   // launch capture/inference thread
ENSI_API int  ensi_ht_stop(void* handle);    // pause the thread
ENSI_API void ensi_ht_destroy(void* handle); // join thread, release camera/model
ENSI_API const char* ensi_ht_last_error(void);

#ifdef __cplusplus
}
#endif

#endif // ENSI_HANDBRIDGE_H
