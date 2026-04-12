#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

extern "C" {
#include <hakoniwa/pdu/c_endpoint.h>
}

namespace godot {

class HakoniwaPduEndpoint : public Node {
  GDCLASS(HakoniwaPduEndpoint, Node)

protected:
  static void _bind_methods();

public:
  HakoniwaPduEndpoint();
  ~HakoniwaPduEndpoint() override;

  String get_backend_name() const;
  bool probe_native_backend() const;
  void set_endpoint_name(const String &name);
  String get_endpoint_name() const;
  void set_direction(int direction);
  int get_direction() const;
  int get_last_error() const;

  int open(const String &config_path);
  void close();
  int start();
  int post_start();
  void stop();
  void process_recv_events();
  bool is_running() const;
  int get_pending_count() const;
  int set_recv_event(const String &robot, int channel_id);
  int get_pdu_channel_id_by_name(const String &robot, const String &pdu_name) const;
  Dictionary recv_by_name(const String &robot, const String &pdu_name);
  Dictionary recv_next();
  int send_by_name(const String &robot, const String &pdu_name, const PackedByteArray &payload);

private:
  hako_pdu_endpoint_handle_t *handle_ = nullptr;
  String endpoint_name_ = "hakoniwa_godot_endpoint";
  int direction_ = 2;
  mutable int last_error_ = 0;

  bool ensure_handle();
  void destroy_handle();
  void set_last_error(int error) const;
  static Dictionary make_record_dict(const String &robot,
                                     int channel_id,
                                     const String &pdu_name,
                                     uint64_t timestamp_ns,
                                     const PackedByteArray &payload);
};

} // namespace godot
