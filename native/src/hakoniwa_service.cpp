#include "hakoniwa_service.h"

#include <cstring>

#include <godot_cpp/core/class_db.hpp>

extern "C" {
#include <hako_asset_service.h>
}

namespace godot {

void HakoniwaServiceServer::_bind_methods() {
  ClassDB::bind_method(D_METHOD("initialize_service", "service_config_path"), &HakoniwaServiceServer::initialize_service);
  ClassDB::bind_method(D_METHOD("create", "asset_name", "service_name"), &HakoniwaServiceServer::create);
  ClassDB::bind_method(D_METHOD("is_created"), &HakoniwaServiceServer::is_created);
  ClassDB::bind_method(D_METHOD("poll"), &HakoniwaServiceServer::poll);
  ClassDB::bind_method(D_METHOD("get_request"), &HakoniwaServiceServer::get_request);
  ClassDB::bind_method(D_METHOD("get_response_template"), &HakoniwaServiceServer::get_response_template);
  ClassDB::bind_method(D_METHOD("put_response", "packet"), &HakoniwaServiceServer::put_response);
  ClassDB::bind_method(D_METHOD("get_last_error_text"), &HakoniwaServiceServer::get_last_error_text);

  ClassDB::bind_integer_constant(get_class_static(), StringName(), "EVENT_NONE", EVENT_NONE);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "EVENT_REQUEST_IN", EVENT_REQUEST_IN);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "EVENT_REQUEST_CANCEL", EVENT_REQUEST_CANCEL);
}

int HakoniwaServiceServer::initialize_service(const String &service_config_path) {
  if (service_config_path.is_empty()) {
    return fail("initialize_service failed: service_config_path is empty");
  }
  const CharString path_utf8 = service_config_path.utf8();
  const int err = hako_asset_service_initialize(path_utf8.get_data());
  if (err != 0) {
    return fail("initialize_service failed: error=" + String::num_int64(err) + " path=" + service_config_path);
  }
  set_last_error_text("");
  return 0;
}

int HakoniwaServiceServer::create(const String &asset_name, const String &service_name) {
  if (asset_name.is_empty()) {
    return fail("create failed: asset_name is empty (the server must be a registered asset)");
  }
  // The registration is kept across start/stop/reset (hakoniwa-core-pro#109).
  if (service_id_ >= 0) {
    set_last_error_text("");
    return service_id_;
  }
  const CharString asset_utf8 = asset_name.utf8();
  const CharString service_utf8 = service_name.utf8();
  const int service_id = hako_asset_service_server_create(asset_utf8.get_data(), service_utf8.get_data());
  if (service_id < 0) {
    return fail("create failed: error=" + String::num_int64(service_id) + " service=" + service_name);
  }
  service_id_ = service_id;
  set_last_error_text("");
  return service_id_;
}

bool HakoniwaServiceServer::is_created() const {
  return service_id_ >= 0;
}

int HakoniwaServiceServer::poll() {
  if (service_id_ < 0) {
    return fail("poll failed: server is not created");
  }
  const int event = hako_asset_service_server_poll(service_id_);
  if (event < 0) {
    return fail("poll failed: error=" + String::num_int64(event));
  }
  set_last_error_text("");
  return event;
}

PackedByteArray HakoniwaServiceServer::get_request() const {
  PackedByteArray out;
  if (service_id_ < 0) {
    fail("get_request failed: server is not created");
    return out;
  }
  char *packet = nullptr;
  size_t packet_len = 0;
  const int err = hako_asset_service_server_get_request(service_id_, &packet, &packet_len);
  if (err != 0 || packet == nullptr) {
    fail("get_request failed: error=" + String::num_int64(err));
    return out;
  }
  out.resize(static_cast<int64_t>(packet_len));
  std::memcpy(out.ptrw(), packet, packet_len);
  set_last_error_text("");
  return out;
}

// The core fills the response header (status DONE, result OK) in its buffer.
// Decode this, set the body, encode it and pass it to put_response.
PackedByteArray HakoniwaServiceServer::get_response_template() {
  PackedByteArray out;
  if (service_id_ < 0) {
    fail("get_response_template failed: server is not created");
    return out;
  }
  const int err = hako_asset_service_server_get_response_buffer(
      service_id_, &response_buffer_, &response_buffer_len_,
      HAKO_SERVICE_API_STATUS_DONE, HAKO_SERVICE_API_RESULT_CODE_OK);
  if (err != 0 || response_buffer_ == nullptr) {
    response_buffer_ = nullptr;
    response_buffer_len_ = 0;
    fail("get_response_template failed: error=" + String::num_int64(err));
    return out;
  }
  out.resize(static_cast<int64_t>(response_buffer_len_));
  std::memcpy(out.ptrw(), response_buffer_, response_buffer_len_);
  set_last_error_text("");
  return out;
}

// Returns 0 when the response is written, 1 when the channel is busy (call again
// on a later step), -1 on an error. A response of a previous run is refused.
int HakoniwaServiceServer::put_response(const PackedByteArray &packet) {
  if (service_id_ < 0) {
    return fail("put_response failed: server is not created");
  }
  if (response_buffer_ == nullptr) {
    return fail("put_response failed: call get_response_template first");
  }
  if (static_cast<size_t>(packet.size()) > response_buffer_len_) {
    return fail("put_response failed: packet size " + String::num_int64(packet.size()) +
                " exceeds the response buffer " + String::num_int64(static_cast<int64_t>(response_buffer_len_)));
  }
  std::memcpy(response_buffer_, packet.ptr(), static_cast<size_t>(packet.size()));
  const int err = hako_asset_service_server_put_response(service_id_, response_buffer_, static_cast<size_t>(packet.size()));
  if (err != 0) {
    set_last_error_text("put_response: not written, error=" + String::num_int64(err));
    return 1;
  }
  response_buffer_ = nullptr;
  response_buffer_len_ = 0;
  set_last_error_text("");
  return 0;
}

String HakoniwaServiceServer::get_last_error_text() const {
  return last_error_text_;
}

void HakoniwaServiceServer::set_last_error_text(const String &message) const {
  last_error_text_ = message;
}

int HakoniwaServiceServer::fail(const String &message) const {
  set_last_error_text(message);
  return -1;
}

} // namespace godot
