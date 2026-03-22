cmake_minimum_required(VERSION 3.16)

project(hakoniwa_godot LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(HAKONIWA_GODOT_BUILD_EXAMPLES "Build Godot example assets with the native extension" ON)
option(HAKONIWA_GODOT_BUILD_TESTS "Build hakoniwa-godot tests" ON)
set(HAKONIWA_GODOT_CODEC_PACKAGES "hako_msgs" CACHE STRING "Semicolon-separated codec packages to build, or 'all'")
set(HAKONIWA_GODOT_GODOT_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/godot-cpp" CACHE PATH "Path to the godot-cpp checkout")
set(HAKONIWA_GODOT_PDU_ENDPOINT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/hakoniwa-pdu-endpoint" CACHE PATH "Path to the hakoniwa-pdu-endpoint checkout")
set(HAKONIWA_GODOT_CORE_PRO_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/hakoniwa-core-pro" CACHE PATH "Path to the hakoniwa-core-pro checkout")
set(HAKONIWA_GODOT_EXECUTABLE "/Applications/Godot_mono.app/Contents/MacOS/Godot" CACHE FILEPATH "Path to the Godot executable for headless smoke tests")

if(NOT EXISTS "${HAKONIWA_GODOT_GODOT_CPP_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "godot-cpp is missing. Initialize submodules before building.")
endif()

if(NOT EXISTS "${HAKONIWA_GODOT_PDU_ENDPOINT_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "hakoniwa-pdu-endpoint is missing. Initialize submodules before building.")
endif()

set(GODOTCPP_ENABLE_TESTING OFF CACHE BOOL "" FORCE)
add_subdirectory("${HAKONIWA_GODOT_GODOT_CPP_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/third_party/godot-cpp")

set(HAKO_PDU_ENDPOINT_ENABLE_ZENOH OFF CACHE BOOL "" FORCE)
set(HAKO_PDU_ENDPOINT_ENABLE_MQTT OFF CACHE BOOL "" FORCE)
set(HAKO_PDU_ENDPOINT_ENABLE_HAKONIWA_CORE OFF CACHE BOOL "" FORCE)
set(HAKO_PDU_ENDPOINT_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(HAKO_PDU_ENDPOINT_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(HAKO_PDU_ENDPOINT_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
add_subdirectory("${HAKONIWA_GODOT_PDU_ENDPOINT_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/third_party/hakoniwa-pdu-endpoint")

add_subdirectory(native)

if(HAKONIWA_GODOT_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()
