cmake_minimum_required(VERSION 3.16)

project(hakoniwa_godot LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(HAKONIWA_GODOT_BUILD_EXAMPLES "Build Godot example assets with the native extension" ON)
option(HAKONIWA_GODOT_BUILD_TESTS "Build hakoniwa-godot tests" ON)
option(
  HAKONIWA_GODOT_MINIMAL_DEP_BUILD
  "Build only the third-party dependency components required for the addon/runtime"
  ON
)
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
set(HAKO_PDU_ENDPOINT_ENABLE_HAKONIWA_CORE ON CACHE BOOL "" FORCE)
set(HAKO_PDU_ENDPOINT_HAKONIWA_CORE_SOURCE_DIR "${HAKONIWA_GODOT_CORE_PRO_DIR}" CACHE PATH "" FORCE)
set(HAKO_PDU_ENDPOINT_INSTALL OFF CACHE BOOL "" FORCE)
set(HAKO_PDU_ENDPOINT_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(HAKO_PDU_ENDPOINT_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(HAKO_PDU_ENDPOINT_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
if(NOT EXISTS "${HAKONIWA_GODOT_CORE_PRO_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "hakoniwa-core-pro is missing. Initialize submodules before building.")
endif()

if(WIN32)
  set(
    HAKO_CLIENT_OPTION_FILEPATH
    "${HAKONIWA_GODOT_CORE_PRO_DIR}/cmake-options/win-cmake-options.cmake"
    CACHE FILEPATH
    "Hakoniwa core-pro CMake options file"
    FORCE
  )
endif()

if(HAKONIWA_GODOT_MINIMAL_DEP_BUILD)
  set(HAKO_CORE_PRO_BUILD_COMMAND OFF CACHE BOOL "" FORCE)
  set(HAKO_CORE_PRO_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(HAKO_CORE_PRO_BUILD_PYTHON_BINDINGS OFF CACHE BOOL "" FORCE)
else()
  set(HAKO_CORE_PRO_BUILD_COMMAND ON CACHE BOOL "" FORCE)
  set(HAKO_CORE_PRO_BUILD_EXAMPLES ON CACHE BOOL "" FORCE)
  set(HAKO_CORE_PRO_BUILD_PYTHON_BINDINGS ON CACHE BOOL "" FORCE)
endif()

set(HAKO_ENABLE_GTEST OFF CACHE BOOL "" FORCE)
add_subdirectory("${HAKONIWA_GODOT_CORE_PRO_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/third_party/hakoniwa-core-pro")
add_subdirectory("${HAKONIWA_GODOT_PDU_ENDPOINT_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/third_party/hakoniwa-pdu-endpoint")

if(WIN32)
  add_executable(hako_conductor_runner "${CMAKE_CURRENT_SOURCE_DIR}/tools/hako_conductor_runner.cpp")
  target_include_directories(
    hako_conductor_runner
    PRIVATE
      "${HAKONIWA_GODOT_CORE_PRO_DIR}/include"
  )
  target_link_libraries(
    hako_conductor_runner
    PRIVATE
      conductor
  )
  set_target_properties(
    hako_conductor_runner
    PROPERTIES
      CXX_STANDARD 20
      CXX_EXTENSIONS OFF
      RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/tools"
      PDB_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/tools"
  )
  if(CMAKE_CONFIGURATION_TYPES)
    foreach(config Debug Release RelWithDebInfo MinSizeRel)
      string(TOUPPER "${config}" config_upper)
      set_target_properties(
        hako_conductor_runner
        PROPERTIES
          "RUNTIME_OUTPUT_DIRECTORY_${config_upper}" "${CMAKE_CURRENT_BINARY_DIR}/tools"
          "PDB_OUTPUT_DIRECTORY_${config_upper}" "${CMAKE_CURRENT_BINARY_DIR}/tools"
      )
    endforeach()
  endif()
endif()

add_subdirectory(native)

if(HAKONIWA_GODOT_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()
