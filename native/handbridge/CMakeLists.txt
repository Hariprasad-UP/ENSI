# Builds libensi_handbridge (Windows .dll / Linux .so).
# Requires: OpenCV, and MediaPipe Tasks (Vision) headers + libs (see README.md).
cmake_minimum_required(VERSION 3.16)
project(ensi_handbridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)

find_package(OpenCV REQUIRED)

# MediaPipe is built with Bazel; point these at your vendored artifacts.
set(MEDIAPIPE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/mediapipe"
    CACHE PATH "MediaPipe Tasks headers + prebuilt libs")

add_library(ensi_handbridge SHARED src/handbridge.cc)

target_include_directories(ensi_handbridge PRIVATE
    include
    ${OpenCV_INCLUDE_DIRS}
    ${MEDIAPIPE_DIR}/include)

target_link_directories(ensi_handbridge PRIVATE ${MEDIAPIPE_DIR}/lib)

target_link_libraries(ensi_handbridge PRIVATE
    ${OpenCV_LIBS}
    mediapipe_tasks_vision)   # name of the vendored MediaPipe Tasks lib

# Linux: resolve bundled .so siblings via $ORIGIN.
if(UNIX AND NOT APPLE)
  set_target_properties(ensi_handbridge PROPERTIES
      INSTALL_RPATH "$ORIGIN"
      BUILD_WITH_INSTALL_RPATH ON)
endif()
