#pragma once

#include "codec/codec_plugin_registry.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

namespace godot {

class HakoniwaCodecRegistry : public Node {
  GDCLASS(HakoniwaCodecRegistry, Node)

protected:
  static void _bind_methods();
  void _notification(int p_what);

public:
  HakoniwaCodecRegistry() = default;
  ~HakoniwaCodecRegistry() override = default;

  void set_plugin_paths(const PackedStringArray &paths);
  PackedStringArray get_plugin_paths() const;

  void set_auto_load_on_ready(bool enabled);
  bool get_auto_load_on_ready() const;

  String get_last_error() const;

  bool load_plugin(const String &plugin_path);
  int load_configured_plugins();
  bool has_codec(const String &package_name, const String &message_name) const;
  Dictionary decode(const String &package_name,
                    const String &message_name,
                    const PackedByteArray &payload) const;
  PackedByteArray encode(const String &package_name,
                         const String &message_name,
                         const Dictionary &value) const;

private:
  String resolve_plugin_path(const String &plugin_path) const;
  void set_last_error(const String &message) const;
  static String platform_library_suffix();

  hako::godot_codec::CodecPluginRegistry registry_;
  PackedStringArray plugin_paths_;
  bool auto_load_on_ready_ = true;
  mutable String last_error_;
};

} // namespace godot
