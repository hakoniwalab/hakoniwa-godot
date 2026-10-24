#pragma once

#include <cstddef>

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {

// Service (RPC) server of hakoniwa-core-pro for a polling asset.
// The asset must be registered (HakoniwaCoreAsset) and calls these in this order:
//   initialize_service  while Stopped, before the first start
//   create              on the Start event, before the start feedback
//   poll / get_request / get_response_template / put_response
//                       only while Running, from the thread that polls
class HakoniwaServiceServer : public Node {
  GDCLASS(HakoniwaServiceServer, Node)

protected:
  static void _bind_methods();

public:
  enum ServerEvent {
    EVENT_NONE = 0,
    EVENT_REQUEST_IN = 1,
    EVENT_REQUEST_CANCEL = 2,
  };

  HakoniwaServiceServer() = default;
  ~HakoniwaServiceServer() override = default;

  int initialize_service(const String &service_config_path);
  int create(const String &asset_name, const String &service_name);
  bool is_created() const;
  int poll();
  PackedByteArray get_request() const;
  PackedByteArray get_response_template();
  int put_response(const PackedByteArray &packet);
  String get_last_error_text() const;

private:
  int service_id_ = -1;
  char *response_buffer_ = nullptr;
  size_t response_buffer_len_ = 0;
  mutable String last_error_text_;

  void set_last_error_text(const String &message) const;
  int fail(const String &message) const;
};

} // namespace godot
