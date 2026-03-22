#pragma once

#include "codec/codec_plugin_api.h"
#include "codec/shared_library.h"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace hako::godot_codec {

class CodecPluginRegistry {
public:
  bool load_plugin(const ::godot::String &plugin_path, ::godot::String *error_message);
  bool has_codec(const ::godot::String &package_name, const ::godot::String &message_name) const;
  ::godot::Dictionary decode(const ::godot::String &package_name,
                             const ::godot::String &message_name,
                             const ::godot::PackedByteArray &payload,
                             ::godot::String *error_message) const;
  ::godot::PackedByteArray encode(const ::godot::String &package_name,
                                  const ::godot::String &message_name,
                                  const ::godot::Dictionary &value,
                                  ::godot::String *error_message) const;

private:
  struct CodecRecord {
    DecodeFn decode = nullptr;
    EncodeFn encode = nullptr;
  };

  struct LoadedPlugin {
    SharedLibrary library;
    const CodecPluginV1 *api = nullptr;
  };

  static std::string make_codec_key(const char *package_name, const char *message_name);
  static std::string to_utf8(const ::godot::String &value);
  static void set_error(::godot::String *out_error, const std::string &message);

  std::vector<std::unique_ptr<LoadedPlugin>> plugins_;
  std::unordered_map<std::string, CodecRecord> codecs_;
};

} // namespace hako::godot_codec
