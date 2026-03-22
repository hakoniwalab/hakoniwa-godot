#pragma once

#include <cstdint>

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#if defined(_WIN32)
#if defined(HAKO_GODOT_CODEC_PLUGIN_BUILD)
#define HAKO_GODOT_CODEC_PLUGIN_EXPORT __declspec(dllexport)
#else
#define HAKO_GODOT_CODEC_PLUGIN_EXPORT __declspec(dllimport)
#endif
#else
#define HAKO_GODOT_CODEC_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

namespace hako::godot_codec {

constexpr uint32_t kCodecPluginAbiVersion = 1U;

using DecodeFn = ::godot::Dictionary (*)(const ::godot::PackedByteArray &payload);
using EncodeFn = ::godot::PackedByteArray (*)(const ::godot::Dictionary &value);

struct CodecEntryV1 {
  const char *message_name = nullptr;
  DecodeFn decode = nullptr;
  EncodeFn encode = nullptr;
};

struct CodecPluginV1 {
  uint32_t abi_version = kCodecPluginAbiVersion;
  const char *package_name = nullptr;
  uint32_t entry_count = 0;
  const CodecEntryV1 *entries = nullptr;
};

// Phase-1 plugin ABI:
// - exported symbol name uses C ABI for robust dynamic loading
// - converter callbacks keep Godot value types so they align with generated
//   hakoniwa-pdu-registry output today
// If Windows packaging later needs a looser boundary, replace DecodeFn /
// EncodeFn with a pure C bridge without changing the loader surface.
using GetCodecPluginFn = const CodecPluginV1 *(*)();

} // namespace hako::godot_codec

extern "C" HAKO_GODOT_CODEC_PLUGIN_EXPORT const hako::godot_codec::CodecPluginV1 *
hako_godot_codec_get_plugin_v1(void);
