if(NOT EXISTS "${HAKONIWA_GODOT_EXECUTABLE}")
  message(WARNING "Godot executable not found, skipping codec smoke tests: ${HAKONIWA_GODOT_EXECUTABLE}")
  return()
endif()

if(NOT TARGET hako_msgs_codec)
  message(WARNING "hako_msgs codec plugin target is not available, skipping codec smoke tests")
  return()
endif()

add_test(
  NAME hakoniwa_codec_smoke
  COMMAND "${HAKONIWA_GODOT_EXECUTABLE}" --headless --path "${CMAKE_SOURCE_DIR}/examples/basic_subscriber" --quit
)

set_tests_properties(
  hakoniwa_codec_smoke
  PROPERTIES
    PASS_REGULAR_EXPRESSION "HAKONIWA_CODEC_SMOKE_OK"
)
