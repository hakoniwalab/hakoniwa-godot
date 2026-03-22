#include "hakoniwa_codec_registry.h"

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

void HakoniwaCodecRegistry::_bind_methods() {
  ClassDB::bind_method(D_METHOD("set_plugin_paths", "paths"), &HakoniwaCodecRegistry::set_plugin_paths);
  ClassDB::bind_method(D_METHOD("get_plugin_paths"), &HakoniwaCodecRegistry::get_plugin_paths);
  ClassDB::bind_method(D_METHOD("set_auto_load_on_ready", "enabled"),
                       &HakoniwaCodecRegistry::set_auto_load_on_ready);
  ClassDB::bind_method(D_METHOD("get_auto_load_on_ready"), &HakoniwaCodecRegistry::get_auto_load_on_ready);
  ClassDB::bind_method(D_METHOD("get_last_error"), &HakoniwaCodecRegistry::get_last_error);
  ClassDB::bind_method(D_METHOD("load_plugin", "plugin_path"), &HakoniwaCodecRegistry::load_plugin);
  ClassDB::bind_method(D_METHOD("load_configured_plugins"), &HakoniwaCodecRegistry::load_configured_plugins);
  ClassDB::bind_method(D_METHOD("has_codec", "package_name", "message_name"),
                       &HakoniwaCodecRegistry::has_codec);
  ClassDB::bind_method(D_METHOD("decode", "package_name", "message_name", "payload"),
                       &HakoniwaCodecRegistry::decode);
  ClassDB::bind_method(D_METHOD("encode", "package_name", "message_name", "value"),
                       &HakoniwaCodecRegistry::encode);

  ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "plugin_paths"),
               "set_plugin_paths",
               "get_plugin_paths");
  ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_load_on_ready"),
               "set_auto_load_on_ready",
               "get_auto_load_on_ready");
}

void HakoniwaCodecRegistry::_notification(int p_what) {
  if (p_what == NOTIFICATION_READY && auto_load_on_ready_) {
    load_configured_plugins();
  }
}

void HakoniwaCodecRegistry::set_plugin_paths(const PackedStringArray &paths) {
  plugin_paths_ = paths;
}

PackedStringArray HakoniwaCodecRegistry::get_plugin_paths() const {
  return plugin_paths_;
}

void HakoniwaCodecRegistry::set_auto_load_on_ready(bool enabled) {
  auto_load_on_ready_ = enabled;
}

bool HakoniwaCodecRegistry::get_auto_load_on_ready() const {
  return auto_load_on_ready_;
}

String HakoniwaCodecRegistry::get_last_error() const {
  return last_error_;
}

bool HakoniwaCodecRegistry::load_plugin(const String &plugin_path) {
  String error_message;
  const String resolved_path = resolve_plugin_path(plugin_path);
  if (!registry_.load_plugin(resolved_path, &error_message)) {
    set_last_error(error_message);
    return false;
  }
  set_last_error("");
  return true;
}

int HakoniwaCodecRegistry::load_configured_plugins() {
  int loaded_count = 0;
  for (int i = 0; i < plugin_paths_.size(); ++i) {
    if (!load_plugin(plugin_paths_[i])) {
      return loaded_count;
    }
    ++loaded_count;
  }
  return loaded_count;
}

bool HakoniwaCodecRegistry::has_codec(const String &package_name, const String &message_name) const {
  return registry_.has_codec(package_name, message_name);
}

Dictionary HakoniwaCodecRegistry::decode(const String &package_name,
                                         const String &message_name,
                                         const PackedByteArray &payload) const {
  String error_message;
  Dictionary result = registry_.decode(package_name, message_name, payload, &error_message);
  set_last_error(error_message);
  return result;
}

PackedByteArray HakoniwaCodecRegistry::encode(const String &package_name,
                                              const String &message_name,
                                              const Dictionary &value) const {
  String error_message;
  PackedByteArray result = registry_.encode(package_name, message_name, value, &error_message);
  set_last_error(error_message);
  return result;
}

String HakoniwaCodecRegistry::resolve_plugin_path(const String &plugin_path) const {
  String resolved_path = plugin_path;
  if (resolved_path.begins_with("res://") || resolved_path.begins_with("user://")) {
    resolved_path = ProjectSettings::get_singleton()->globalize_path(resolved_path);
  }

  const String suffix = platform_library_suffix();
  if (!suffix.is_empty() && !resolved_path.ends_with(suffix)) {
    resolved_path += suffix;
  }
  return resolved_path;
}

void HakoniwaCodecRegistry::set_last_error(const String &message) const {
  last_error_ = message;
}

String HakoniwaCodecRegistry::platform_library_suffix() {
#if defined(_WIN32)
  return ".dll";
#elif defined(__APPLE__)
  return ".dylib";
#else
  return ".so";
#endif
}

} // namespace godot
