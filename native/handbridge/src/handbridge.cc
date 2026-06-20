// ENSI hand-tracking native bridge — OpenCV capture + MediaPipe Hand Landmarker.
//
// NO custom computer vision here: MediaPipe Tasks owns palm detection, ROI,
// landmarks, and tracking. This file only: opens the camera, hands frames to the
// HandLandmarker in VIDEO mode, packs 21x3 floats, and invokes the C callback.
//
// Build: see CMakeLists.txt + README.md (Task 0). If the MediaPipe C++ build is
// impractical, replace the body of the worker loop with an IPC client to the
// Python-sidecar (D1) — this file's C ABI stays identical, so Dart is unchanged.

#include "handbridge.h"

#include <atomic>
#include <chrono>
#include <cstring>
#include <string>
#include <thread>

#include <opencv2/opencv.hpp>

// MediaPipe Tasks (Vision) — Hand Landmarker.
#include "mediapipe/tasks/cc/vision/hand_landmarker/hand_landmarker.h"
#include "mediapipe/tasks/cc/core/base_options.h"
#include "mediapipe/framework/formats/image.h"
#include "mediapipe/framework/formats/image_frame.h"

namespace mp = ::mediapipe::tasks::vision::hand_landmarker;

static thread_local std::string g_err;
static std::string g_last_error;
static void set_error(const std::string& e) { g_last_error = e; }

struct Bridge {
  cv::VideoCapture cap;
  std::unique_ptr<mp::HandLandmarker> landmarker;
  ensi_landmarks_cb cb = nullptr;
  std::thread worker;
  std::atomic<bool> running{false};
  int cam_index = 0, width = 640, height = 480, fps = 30;

  void loop() {
    cv::Mat bgr, rgb;
    while (running.load()) {
      if (!cap.read(bgr) || bgr.empty()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
        continue;
      }
      cv::cvtColor(bgr, rgb, cv::COLOR_BGR2RGB);
      // Wrap RGB into a MediaPipe Image (ImageFrame, no copy beyond cvtColor).
      auto frame = std::make_shared<mediapipe::ImageFrame>(
          mediapipe::ImageFormat::SRGB, rgb.cols, rgb.rows,
          rgb.step, rgb.data, [](uint8_t*) {});
      mediapipe::Image image(frame);
      const int64_t ts_us =
          std::chrono::duration_cast<std::chrono::microseconds>(
              std::chrono::steady_clock::now().time_since_epoch()).count();

      auto result = landmarker->DetectForVideo(image, ts_us / 1000);
      if (!result.ok()) continue;
      const auto& res = result.value();

      float xyz[63] = {0};
      float presence = 0.f; int handed = 1;
      if (!res.hand_landmarks.empty()) {
        const auto& lms = res.hand_landmarks[0].landmarks;
        for (int i = 0; i < 21 && i < (int)lms.size(); ++i) {
          xyz[i * 3 + 0] = lms[i].x;
          xyz[i * 3 + 1] = lms[i].y;
          xyz[i * 3 + 2] = lms[i].z;
        }
        presence = 1.f; // Tasks gates by detection confidence already
        if (!res.handedness.empty() && !res.handedness[0].categories.empty())
          handed = res.handedness[0].categories[0].category_name == "Left" ? 0 : 1;
      }
      if (cb) cb(xyz, res.hand_landmarks.empty() ? 0 : 63, presence, handed, ts_us);
    }
  }
};

extern "C" {

int ensi_ht_create(const char* model_path, int cam_index, int width, int height,
                   int fps, ensi_landmarks_cb cb, void** out_handle) {
  try {
    auto* b = new Bridge();
    b->cb = cb; b->cam_index = cam_index;
    b->width = width; b->height = height; b->fps = fps;

    auto options = std::make_unique<mp::HandLandmarkerOptions>();
    options->base_options.model_asset_path = model_path;
    options->running_mode = mediapipe::tasks::vision::core::RunningMode::VIDEO;
    options->num_hands = 1;
    auto lm = mp::HandLandmarker::Create(std::move(options));
    if (!lm.ok()) { set_error(std::string(lm.status().message())); delete b; return 2; }
    b->landmarker = std::move(lm.value());

    b->cap.open(cam_index);
    if (!b->cap.isOpened()) { set_error("cannot open camera"); delete b; return 3; }
    b->cap.set(cv::CAP_PROP_FRAME_WIDTH, width);
    b->cap.set(cv::CAP_PROP_FRAME_HEIGHT, height);
    b->cap.set(cv::CAP_PROP_FPS, fps);

    *out_handle = b;
    return 0;
  } catch (const std::exception& e) { set_error(e.what()); return 1; }
}

int ensi_ht_start(void* handle) {
  auto* b = static_cast<Bridge*>(handle);
  if (!b) return 1;
  if (b->running.exchange(true)) return 0;
  b->worker = std::thread([b] { b->loop(); });
  return 0;
}

int ensi_ht_stop(void* handle) {
  auto* b = static_cast<Bridge*>(handle);
  if (!b) return 1;
  b->running.store(false);
  if (b->worker.joinable()) b->worker.join();
  return 0;
}

void ensi_ht_destroy(void* handle) {
  auto* b = static_cast<Bridge*>(handle);
  if (!b) return;
  ensi_ht_stop(handle);
  if (b->cap.isOpened()) b->cap.release();
  delete b;
}

const char* ensi_ht_last_error(void) { return g_last_error.c_str(); }

} // extern "C"
