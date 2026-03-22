#include "codec/codec_plugin_registry.h"

#include <godot_cpp/variant/char_string.hpp>

namespace hako::godot_codec {

namespace {

constexpr char kCodecFactorySymbol[] = "hako_godot_codec_get_plugin_v1";

bool is_valid_plugin(const CodecPluginV1 *plugin) {
  return plugin != nullptr && plugin->abi_version == kCodecPluginAbiVersion &&
         plugin->package_name != nullptr && plugin->entries != nullptr;
}

} // namespace

bool CodecPluginRegistry::load_plugin(const ::godot::String &plugin_path,
                                      ::godot::String *error_message) {
  auto plugin = std::make_unique<LoadedPlugin>();
  std::string native_error;
  const std::string path = to_utf8(plugin_path);
  if (!plugin->library.open(path, &native_error)) {
    set_error(error_message, native_error);
    return false;
  }

  void *symbol = plugin->library.resolve_symbol(kCodecFactorySymbol, &native_error);
  if (symbol == nullptr) {
    set_error(error_message, native_error);
    return false;
  }

  auto *get_plugin = reinterpret_cast<GetCodecPluginFn>(symbol);
  plugin->api = get_plugin();
  if (!is_valid_plugin(plugin->api)) {
    set_error(error_message, "codec plugin ABI mismatch");
    return false;
  }

  for (uint32_t i = 0; i < plugin->api->entry_count; ++i) {
    const CodecEntryV1 &entry = plugin->api->entries[i];
    if (entry.message_name == nullptr || entry.decode == nullptr || entry.encode == nullptr) {
      continue;
    }
    codecs_[make_codec_key(plugin->api->package_name, entry.message_name)] =
        CodecRecord{entry.decode, entry.encode};
  }

  plugins_.push_back(std::move(plugin));
  return true;
}

bool CodecPluginRegistry::has_codec(const ::godot::String &package_name,
                                    const ::godot::String &message_name) const {
  const std::string package_utf8 = to_utf8(package_name);
  const std::string message_utf8 = to_utf8(message_name);
  return codecs_.contains(make_codec_key(package_utf8.c_str(), message_utf8.c_str()));
}

::godot::Dictionary CodecPluginRegistry::decode(const ::godot::String &package_name,
                                                const ::godot::String &message_name,
                                                const ::godot::PackedByteArray &payload,
                                                ::godot::String *error_message) const {
  const std::string package_utf8 = to_utf8(package_name);
  const std::string message_utf8 = to_utf8(message_name);
  const auto it = codecs_.find(make_codec_key(package_utf8.c_str(), message_utf8.c_str()));
  if (it == codecs_.end()) {
    set_error(error_message, "codec not found");
    return {};
  }
  return it->second.decode(payload);
}

::godot::PackedByteArray CodecPluginRegistry::encode(const ::godot::String &package_name,
                                                     const ::godot::String &message_name,
                                                     const ::godot::Dictionary &value,
                                                     ::godot::String *error_message) const {
  const std::string package_utf8 = to_utf8(package_name);
  const std::string message_utf8 = to_utf8(message_name);
  const auto it = codecs_.find(make_codec_key(package_utf8.c_str(), message_utf8.c_str()));
  if (it == codecs_.end()) {
    set_error(error_message, "codec not found");
    return {};
  }
  return it->second.encode(value);
}

std::string CodecPluginRegistry::make_codec_key(const char *package_name, const char *message_name) {
  const char *safe_package = (package_name != nullptr) ? package_name : "";
  const char *safe_message = (message_name != nullptr) ? message_name : "";
  return std::string(safe_package) + "/" + safe_message;
}

std::string CodecPluginRegistry::to_utf8(const ::godot::String &value) {
  const ::godot::CharString utf8 = value.utf8();
  return utf8.get_data();
}

void CodecPluginRegistry::set_error(::godot::String *out_error, const std::string &message) {
  if (out_error != nullptr) {
    *out_error = ::godot::String(message.c_str());
  }
}

} // namespace hako::godot_codec
