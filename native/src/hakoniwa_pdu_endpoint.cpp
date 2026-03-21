#include "hakoniwa_pdu_endpoint.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <array>
#include <cstring>
#include <vector>

extern "C" {
#include <hakoniwa/pdu/c_endpoint.h>
}

namespace godot {

namespace {

constexpr size_t kRobotNameMax = HAKO_PDU_C_ENDPOINT_ROBOT_NAME_MAX;
constexpr size_t kPduNameMax = HAKO_PDU_C_ENDPOINT_PDU_NAME_MAX;
constexpr size_t kDefaultRecvBufferSize = 1024 * 1024;

template <size_t N>
bool copy_string_to_cbuf(const String &value, std::array<char, N> &out) {
  out.fill('\0');
  const CharString utf8 = value.utf8();
  const char *src = utf8.get_data();
  if (src == nullptr || src[0] == '\0') {
    return false;
  }
  const size_t len = std::strlen(src);
  if (len >= N) {
    return false;
  }
  std::memcpy(out.data(), src, len);
  return true;
}

bool make_name_key(const String &robot, const String &pdu_name, hako_pdu_key_t &out_key) {
  std::array<char, kRobotNameMax> robot_buf{};
  std::array<char, kPduNameMax> pdu_buf{};
  if (!copy_string_to_cbuf(robot, robot_buf) || !copy_string_to_cbuf(pdu_name, pdu_buf)) {
    return false;
  }
  std::memcpy(out_key.robot, robot_buf.data(), robot_buf.size());
  std::memcpy(out_key.pdu, pdu_buf.data(), pdu_buf.size());
  return true;
}

bool make_resolved_key(const String &robot, int channel_id, hako_pdu_resolved_key_t &out_key) {
  std::array<char, kRobotNameMax> robot_buf{};
  if (!copy_string_to_cbuf(robot, robot_buf) || channel_id < 0) {
    return false;
  }
  std::memcpy(out_key.robot, robot_buf.data(), robot_buf.size());
  out_key.channel_id = static_cast<uint32_t>(channel_id);
  return true;
}

PackedByteArray copy_payload(const void *data, size_t size) {
  PackedByteArray payload;
  payload.resize(static_cast<int64_t>(size));
  if (size > 0 && data != nullptr) {
    std::memcpy(payload.ptrw(), data, size);
  }
  return payload;
}

} // namespace

void HakoniwaPduEndpoint::_bind_methods() {
  ClassDB::bind_method(D_METHOD("get_backend_name"), &HakoniwaPduEndpoint::get_backend_name);
  ClassDB::bind_method(D_METHOD("probe_native_backend"), &HakoniwaPduEndpoint::probe_native_backend);
  ClassDB::bind_method(D_METHOD("set_endpoint_name", "name"), &HakoniwaPduEndpoint::set_endpoint_name);
  ClassDB::bind_method(D_METHOD("get_endpoint_name"), &HakoniwaPduEndpoint::get_endpoint_name);
  ClassDB::bind_method(D_METHOD("set_direction", "direction"), &HakoniwaPduEndpoint::set_direction);
  ClassDB::bind_method(D_METHOD("get_direction"), &HakoniwaPduEndpoint::get_direction);
  ClassDB::bind_method(D_METHOD("get_last_error"), &HakoniwaPduEndpoint::get_last_error);
  ClassDB::bind_method(D_METHOD("open", "config_path"), &HakoniwaPduEndpoint::open);
  ClassDB::bind_method(D_METHOD("close"), &HakoniwaPduEndpoint::close);
  ClassDB::bind_method(D_METHOD("start"), &HakoniwaPduEndpoint::start);
  ClassDB::bind_method(D_METHOD("post_start"), &HakoniwaPduEndpoint::post_start);
  ClassDB::bind_method(D_METHOD("stop"), &HakoniwaPduEndpoint::stop);
  ClassDB::bind_method(D_METHOD("process_recv_events"), &HakoniwaPduEndpoint::process_recv_events);
  ClassDB::bind_method(D_METHOD("is_running"), &HakoniwaPduEndpoint::is_running);
  ClassDB::bind_method(D_METHOD("get_pending_count"), &HakoniwaPduEndpoint::get_pending_count);
  ClassDB::bind_method(D_METHOD("set_recv_event", "robot", "channel_id"), &HakoniwaPduEndpoint::set_recv_event);
  ClassDB::bind_method(D_METHOD("recv_by_name", "robot", "pdu_name"), &HakoniwaPduEndpoint::recv_by_name);
  ClassDB::bind_method(D_METHOD("recv_next"), &HakoniwaPduEndpoint::recv_next);
  ClassDB::bind_method(D_METHOD("send_by_name", "robot", "pdu_name", "payload"), &HakoniwaPduEndpoint::send_by_name);

  ADD_PROPERTY(PropertyInfo(Variant::STRING, "endpoint_name"), "set_endpoint_name", "get_endpoint_name");
  ADD_PROPERTY(PropertyInfo(Variant::INT, "direction"), "set_direction", "get_direction");
}

HakoniwaPduEndpoint::HakoniwaPduEndpoint() = default;

HakoniwaPduEndpoint::~HakoniwaPduEndpoint() {
  if (handle_ != nullptr) {
    (void)hako_pdu_endpoint_stop(handle_);
    (void)hako_pdu_endpoint_close(handle_);
  }
  destroy_handle();
}

String HakoniwaPduEndpoint::get_backend_name() const {
  return "hakoniwa-pdu-endpoint";
}

bool HakoniwaPduEndpoint::probe_native_backend() const {
  hako_pdu_endpoint_handle_t *handle =
      hako_pdu_endpoint_create("hakoniwa_godot_probe", HAKO_PDU_ENDPOINT_DIRECTION_IN);
  if (handle == nullptr) {
    return false;
  }
  hako_pdu_endpoint_destroy(handle);
  return true;
}

void HakoniwaPduEndpoint::set_endpoint_name(const String &name) {
  if (!name.is_empty()) {
    endpoint_name_ = name;
  }
}

String HakoniwaPduEndpoint::get_endpoint_name() const {
  return endpoint_name_;
}

void HakoniwaPduEndpoint::set_direction(int direction) {
  if (direction >= HAKO_PDU_ENDPOINT_DIRECTION_IN &&
      direction <= HAKO_PDU_ENDPOINT_DIRECTION_INOUT) {
    direction_ = direction;
  }
}

int HakoniwaPduEndpoint::get_direction() const {
  return direction_;
}

int HakoniwaPduEndpoint::get_last_error() const {
  return last_error_;
}

int HakoniwaPduEndpoint::open(const String &config_path) {
  if (!ensure_handle()) {
    set_last_error(HAKO_PDU_ERR_OUT_OF_MEMORY);
    return last_error_;
  }
  String resolved_path = config_path;
  if (resolved_path.begins_with("res://") || resolved_path.begins_with("user://")) {
    resolved_path = ProjectSettings::get_singleton()->globalize_path(resolved_path);
  }
  CharString path = resolved_path.utf8();
  const int err = hako_pdu_endpoint_open(handle_, path.get_data());
  set_last_error(err);
  return err;
}

void HakoniwaPduEndpoint::close() {
  if (handle_ == nullptr) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return;
  }
  set_last_error(hako_pdu_endpoint_close(handle_));
}

int HakoniwaPduEndpoint::start() {
  if (handle_ == nullptr) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return last_error_;
  }
  set_last_error(hako_pdu_endpoint_start(handle_));
  return last_error_;
}

int HakoniwaPduEndpoint::post_start() {
  if (handle_ == nullptr) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return last_error_;
  }
  set_last_error(hako_pdu_endpoint_post_start(handle_));
  return last_error_;
}

void HakoniwaPduEndpoint::stop() {
  if (handle_ == nullptr) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return;
  }
  set_last_error(hako_pdu_endpoint_stop(handle_));
}

void HakoniwaPduEndpoint::process_recv_events() {
  if (handle_ == nullptr) {
    return;
  }
  hako_pdu_endpoint_process_recv_events(handle_);
}

bool HakoniwaPduEndpoint::is_running() const {
  if (handle_ == nullptr) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return false;
  }
  hako_pdu_bool_t running = HAKO_PDU_FALSE;
  const int err = hako_pdu_endpoint_is_running(handle_, &running);
  set_last_error(err);
  return err == HAKO_PDU_ERR_OK && running == HAKO_PDU_TRUE;
}

int HakoniwaPduEndpoint::get_pending_count() const {
  if (handle_ == nullptr) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return 0;
  }
  size_t count = 0;
  const int err = hako_pdu_endpoint_get_pending_count(handle_, &count);
  set_last_error(err);
  if (err != HAKO_PDU_ERR_OK) {
    return 0;
  }
  return static_cast<int>(count);
}

int HakoniwaPduEndpoint::set_recv_event(const String &robot, int channel_id) {
  if (handle_ == nullptr) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return last_error_;
  }
  hako_pdu_resolved_key_t key{};
  if (!make_resolved_key(robot, channel_id, key)) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return last_error_;
  }
  set_last_error(hako_pdu_endpoint_set_recv_event(handle_, &key));
  return last_error_;
}

Dictionary HakoniwaPduEndpoint::recv_by_name(const String &robot, const String &pdu_name) {
  Dictionary result;
  if (handle_ == nullptr) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return result;
  }

  hako_pdu_key_t key{};
  if (!make_name_key(robot, pdu_name, key)) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return result;
  }

  const size_t expected_size = hako_pdu_endpoint_get_pdu_size(handle_, &key);
  if (expected_size == 0) {
    set_last_error(HAKO_PDU_ERR_INVALID_PDU_KEY);
    return result;
  }

  std::vector<std::byte> buffer(expected_size);
  size_t received_size = 0;
  const int err = hako_pdu_endpoint_recv_by_name(
      handle_, &key, buffer.data(), buffer.size(), &received_size);
  set_last_error(err);
  if (err != HAKO_PDU_ERR_OK) {
    return result;
  }

  const int channel_id = hako_pdu_endpoint_get_pdu_channel_id(handle_, &key);
  result = make_record_dict(robot, channel_id, pdu_name, 0, copy_payload(buffer.data(), received_size));
  return result;
}

Dictionary HakoniwaPduEndpoint::recv_next() {
  Dictionary result;
  if (handle_ == nullptr) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return result;
  }

  std::vector<std::byte> buffer(kDefaultRecvBufferSize);
  hako_pdu_resolved_key_t key{};
  uint64_t timestamp_ns = 0;
  size_t received_size = 0;
  const int err = hako_pdu_endpoint_recv_next(
      handle_, buffer.data(), buffer.size(), &key, &timestamp_ns, &received_size);
  set_last_error(err);
  if (err != HAKO_PDU_ERR_OK) {
    return result;
  }

  char pdu_name[kPduNameMax] = {};
  String pdu_name_string;
  const int name_err = hako_pdu_endpoint_get_pdu_name(handle_, &key, pdu_name, sizeof(pdu_name));
  if (name_err == HAKO_PDU_ERR_OK) {
    pdu_name_string = String(pdu_name);
  }

  result = make_record_dict(String(key.robot),
                            static_cast<int>(key.channel_id),
                            pdu_name_string,
                            timestamp_ns,
                            copy_payload(buffer.data(), received_size));
  return result;
}

int HakoniwaPduEndpoint::send_by_name(const String &robot,
                                      const String &pdu_name,
                                      const PackedByteArray &payload) {
  if (handle_ == nullptr) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return last_error_;
  }
  hako_pdu_key_t key{};
  if (!make_name_key(robot, pdu_name, key)) {
    set_last_error(HAKO_PDU_ERR_INVALID_ARGUMENT);
    return last_error_;
  }
  const void *data = payload.is_empty() ? nullptr : payload.ptr();
  set_last_error(hako_pdu_endpoint_send_by_name(handle_, &key, data, payload.size()));
  return last_error_;
}

bool HakoniwaPduEndpoint::ensure_handle() {
  if (handle_ != nullptr) {
    return true;
  }
  CharString name = endpoint_name_.utf8();
  handle_ = hako_pdu_endpoint_create(
      name.get_data(), static_cast<HakoPduEndpointDirectionType>(direction_));
  return handle_ != nullptr;
}

void HakoniwaPduEndpoint::destroy_handle() {
  if (handle_ != nullptr) {
    hako_pdu_endpoint_destroy(handle_);
    handle_ = nullptr;
  }
}

void HakoniwaPduEndpoint::set_last_error(int error) const {
  last_error_ = error;
}

Dictionary HakoniwaPduEndpoint::make_record_dict(const String &robot,
                                                 int channel_id,
                                                 const String &pdu_name,
                                                 uint64_t timestamp_ns,
                                                 const PackedByteArray &payload) {
  Dictionary result;
  result["robot"] = robot;
  result["channel_id"] = channel_id;
  result["pdu_name"] = pdu_name;
  result["timestamp_ns"] = static_cast<int64_t>(timestamp_ns);
  result["payload"] = payload;
  return result;
}

} // namespace godot
