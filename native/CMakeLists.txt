set(HAKONIWA_GODOT_NATIVE_TARGET hakoniwa_godot_native)
set(HAKONIWA_GODOT_ADDON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../addons/hakoniwa")
set(HAKONIWA_GODOT_BIN_DIR "${HAKONIWA_GODOT_ADDON_DIR}/bin")
set(HAKONIWA_GODOT_CODEC_DIR "${HAKONIWA_GODOT_ADDON_DIR}/codecs")
set(HAKONIWA_PDU_REGISTRY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/hakoniwa-core-pro/hakoniwa-pdu-registry")
set(HAKONIWA_GODOT_TEMPLATE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/templates")

add_library(${HAKONIWA_GODOT_NATIVE_TARGET} SHARED)

add_library(hakoniwa_godot_codec_runtime STATIC)

target_sources(
  hakoniwa_godot_codec_runtime
  PRIVATE
    src/codec/codec_plugin_registry.cpp
    src/codec/shared_library.cpp
)

target_include_directories(
  hakoniwa_godot_codec_runtime
  PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_link_libraries(
  hakoniwa_godot_codec_runtime
  PUBLIC
    godot-cpp
)

set_target_properties(
  hakoniwa_godot_codec_runtime
  PROPERTIES
    CXX_STANDARD 20
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
)

target_sources(
  ${HAKONIWA_GODOT_NATIVE_TARGET}
  PRIVATE
    src/hakoniwa_core_asset.cpp
    src/hakoniwa_codec_registry.cpp
    src/hakoniwa_pdu_endpoint.cpp
    src/register_types.cpp
)

target_include_directories(
  ${HAKONIWA_GODOT_NATIVE_TARGET}
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${HAKONIWA_GODOT_CORE_PRO_DIR}/include"
)

target_link_libraries(
  ${HAKONIWA_GODOT_NATIVE_TARGET}
  PRIVATE
    godot-cpp
    hakoniwa_godot_codec_runtime
    hakoniwa_pdu_endpoint
    shakoc
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

function(hakoniwa_add_codec_plugin package_name)
  set(package_dir "${HAKONIWA_PDU_REGISTRY_DIR}/pdu/godot_cpp/${package_name}")
  file(GLOB package_headers "${package_dir}/pdu_conv_*.hpp")
  if(NOT package_headers)
    return()
  endif()

  set(codec_include_lines "")
  set(codec_function_lines "")
  set(codec_entry_lines "")

  foreach(header_path IN LISTS package_headers)
    get_filename_component(header_name "${header_path}" NAME)
    string(REGEX REPLACE "^pdu_conv_(.+)\\.hpp$" "\\1" message_name "${header_name}")

    string(APPEND codec_include_lines "#include \"${package_name}/${header_name}\"\n")
    string(APPEND codec_function_lines
"godot::Dictionary decode_${message_name}(const godot::PackedByteArray &payload) {\n"
"  return hako::godot_pdu::${package_name}::pdu_to_godot_${message_name}(payload);\n"
"}\n\n"
"godot::PackedByteArray encode_${message_name}(const godot::Dictionary &value) {\n"
"  return hako::godot_pdu::${package_name}::godot_to_pdu_${message_name}(value);\n"
"}\n\n")
    string(APPEND codec_entry_lines
"    {\"${message_name}\", &decode_${message_name}, &encode_${message_name}},\n")
  endforeach()

  set(CODEC_PACKAGE_NAME "${package_name}")
  set(CODEC_LIBRARY_NAME "${package_name}_codec")
  set(CODEC_INIT_SYMBOL "${package_name}_codec_library_init")
  set(CODEC_INCLUDE_LINES "${codec_include_lines}")
  set(CODEC_FUNCTION_LINES "${codec_function_lines}")
  set(CODEC_ENTRY_LINES "${codec_entry_lines}")

  set(generated_dir "${CMAKE_CURRENT_BINARY_DIR}/generated/${package_name}")
  file(MAKE_DIRECTORY "${generated_dir}")

  configure_file("${HAKONIWA_GODOT_TEMPLATE_DIR}/codec_plugin.cpp.in"
                 "${generated_dir}/${package_name}_codec_plugin.cpp" @ONLY)
  configure_file("${HAKONIWA_GODOT_TEMPLATE_DIR}/codec_plugin_init.cpp.in"
                 "${generated_dir}/${package_name}_codec_plugin_init.cpp" @ONLY)
  configure_file("${HAKONIWA_GODOT_TEMPLATE_DIR}/codec_plugin.gdextension.in"
                 "${HAKONIWA_GODOT_CODEC_DIR}/${package_name}_codec.gdextension" @ONLY)

  add_library(${package_name}_codec SHARED)

  target_sources(
    ${package_name}_codec
    PRIVATE
      "${generated_dir}/${package_name}_codec_plugin.cpp"
      "${generated_dir}/${package_name}_codec_plugin_init.cpp"
  )

  target_include_directories(
    ${package_name}_codec
    PRIVATE
      "${CMAKE_CURRENT_SOURCE_DIR}/src"
      "${HAKONIWA_PDU_REGISTRY_DIR}/pdu"
      "${HAKONIWA_PDU_REGISTRY_DIR}/pdu/godot_cpp"
  )

  target_link_libraries(
    ${package_name}_codec
    PRIVATE
      godot-cpp
  )

  set_target_properties(
    ${package_name}_codec
    PROPERTIES
      CXX_STANDARD 20
      CXX_EXTENSIONS OFF
      POSITION_INDEPENDENT_CODE ON
      BUILD_RPATH_USE_ORIGIN ON
      LIBRARY_OUTPUT_DIRECTORY "${HAKONIWA_GODOT_CODEC_DIR}"
      RUNTIME_OUTPUT_DIRECTORY "${HAKONIWA_GODOT_CODEC_DIR}"
      PDB_OUTPUT_DIRECTORY "${HAKONIWA_GODOT_CODEC_DIR}"
      OUTPUT_NAME "${package_name}_codec"
      PREFIX ""
  )

  if(APPLE)
    set_target_properties(
      ${package_name}_codec
      PROPERTIES
        SUFFIX ".dylib"
    )
  endif()
endfunction()

if(EXISTS "${HAKONIWA_PDU_REGISTRY_DIR}/pdu/godot_cpp_runtime/PduRuntime.hpp")
  file(GLOB codec_package_dirs LIST_DIRECTORIES true "${HAKONIWA_PDU_REGISTRY_DIR}/pdu/godot_cpp/*")
  set(available_codec_packages "")
  foreach(codec_package_dir IN LISTS codec_package_dirs)
    if(IS_DIRECTORY "${codec_package_dir}")
      get_filename_component(codec_package_name "${codec_package_dir}" NAME)
      list(APPEND available_codec_packages "${codec_package_name}")
    endif()
  endforeach()

  if(HAKONIWA_GODOT_CODEC_PACKAGES STREQUAL "all")
    set(selected_codec_packages ${available_codec_packages})
  else()
    set(selected_codec_packages ${HAKONIWA_GODOT_CODEC_PACKAGES})
  endif()

  foreach(selected_codec_package IN LISTS selected_codec_packages)
    list(FIND available_codec_packages "${selected_codec_package}" codec_package_index)
    if(codec_package_index EQUAL -1)
      message(FATAL_ERROR
        "Unknown codec package '${selected_codec_package}'. Available packages: ${available_codec_packages}")
    endif()
    hakoniwa_add_codec_plugin("${selected_codec_package}")
  endforeach()
endif()
