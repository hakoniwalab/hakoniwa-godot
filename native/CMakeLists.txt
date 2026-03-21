set(HAKONIWA_GODOT_NATIVE_TARGET hakoniwa_godot_native)
set(HAKONIWA_GODOT_ADDON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../addons/hakoniwa")
set(HAKONIWA_GODOT_BIN_DIR "${HAKONIWA_GODOT_ADDON_DIR}/bin")

add_library(${HAKONIWA_GODOT_NATIVE_TARGET} SHARED)

target_sources(
  ${HAKONIWA_GODOT_NATIVE_TARGET}
  PRIVATE
    src/hakoniwa_pdu_endpoint.cpp
    src/register_types.cpp
)

target_include_directories(
  ${HAKONIWA_GODOT_NATIVE_TARGET}
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_link_libraries(
  ${HAKONIWA_GODOT_NATIVE_TARGET}
  PRIVATE
    godot-cpp
    hakoniwa_pdu_endpoint
)

set_target_properties(
  ${HAKONIWA_GODOT_NATIVE_TARGET}
  PROPERTIES
    CXX_STANDARD 20
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
    BUILD_RPATH_USE_ORIGIN ON
    LIBRARY_OUTPUT_DIRECTORY "${HAKONIWA_GODOT_BIN_DIR}"
    RUNTIME_OUTPUT_DIRECTORY "${HAKONIWA_GODOT_BIN_DIR}"
    PDB_OUTPUT_DIRECTORY "${HAKONIWA_GODOT_BIN_DIR}"
    OUTPUT_NAME "hakoniwa_godot_native"
)

if(APPLE)
  set_target_properties(
    ${HAKONIWA_GODOT_NATIVE_TARGET}
    PROPERTIES
      SUFFIX ".dylib"
  )
endif()
