#include "hakoniwa_pdu_endpoint.h"

#include <godot_cpp/core/class_db.hpp>

extern "C" {
#include <hakoniwa/pdu/c_endpoint.h>
}

namespace godot {

void HakoniwaPduEndpoint::_bind_methods() {
  ClassDB::bind_method(D_METHOD("get_backend_name"), &HakoniwaPduEndpoint::get_backend_name);
  ClassDB::bind_method(D_METHOD("probe_native_backend"), &HakoniwaPduEndpoint::probe_native_backend);
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

} // namespace godot
