#include "hakoniwa_core_asset.h"

#include <godot_cpp/core/class_db.hpp>

extern "C" {
#include <hakoniwa_asset_polling.h>
}

namespace godot {

bool HakoniwaCoreAsset::s_registered_ = false;
std::string HakoniwaCoreAsset::s_registered_asset_name_;

void HakoniwaCoreAsset::_bind_methods() {
  ClassDB::bind_method(D_METHOD("initialize_asset", "asset_name"), &HakoniwaCoreAsset::initialize_asset);
  ClassDB::bind_method(D_METHOD("unregister_asset"), &HakoniwaCoreAsset::unregister_asset);
  ClassDB::bind_method(D_METHOD("poll_event"), &HakoniwaCoreAsset::poll_event);
  ClassDB::bind_method(D_METHOD("get_simulation_state"), &HakoniwaCoreAsset::get_simulation_state);
  ClassDB::bind_method(D_METHOD("request_start"), &HakoniwaCoreAsset::request_start);
  ClassDB::bind_method(D_METHOD("request_stop"), &HakoniwaCoreAsset::request_stop);
  ClassDB::bind_method(D_METHOD("request_reset"), &HakoniwaCoreAsset::request_reset);
  ClassDB::bind_method(D_METHOD("start_feedback_ok"), &HakoniwaCoreAsset::start_feedback_ok);
  ClassDB::bind_method(D_METHOD("stop_feedback_ok"), &HakoniwaCoreAsset::stop_feedback_ok);
  ClassDB::bind_method(D_METHOD("reset_feedback_ok"), &HakoniwaCoreAsset::reset_feedback_ok);
  ClassDB::bind_method(D_METHOD("is_pdu_created"), &HakoniwaCoreAsset::is_pdu_created);
  ClassDB::bind_method(D_METHOD("is_pdu_sync_mode"), &HakoniwaCoreAsset::is_pdu_sync_mode);
  ClassDB::bind_method(D_METHOD("notify_write_pdu_done"), &HakoniwaCoreAsset::notify_write_pdu_done);
  ClassDB::bind_method(D_METHOD("notify_simtime", "simtime_usec"), &HakoniwaCoreAsset::notify_simtime);
  ClassDB::bind_method(D_METHOD("get_world_time_usec"), &HakoniwaCoreAsset::get_world_time_usec);
  ClassDB::bind_method(D_METHOD("get_simtime_usec"), &HakoniwaCoreAsset::get_simtime_usec);
  ClassDB::bind_method(D_METHOD("get_registered_asset_name"), &HakoniwaCoreAsset::get_registered_asset_name);
  ClassDB::bind_method(D_METHOD("get_last_error_text"), &HakoniwaCoreAsset::get_last_error_text);

  ClassDB::bind_integer_constant(get_class_static(), StringName(), "STATE_STOPPED", STATE_STOPPED);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "STATE_RUNNABLE", STATE_RUNNABLE);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "STATE_RUNNING", STATE_RUNNING);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "STATE_STOPPING", STATE_STOPPING);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "STATE_RESETTING", STATE_RESETTING);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "STATE_ERROR", STATE_ERROR);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "STATE_TERMINATED", STATE_TERMINATED);

  ClassDB::bind_integer_constant(get_class_static(), StringName(), "EVENT_NONE", EVENT_NONE);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "EVENT_START", EVENT_START);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "EVENT_STOP", EVENT_STOP);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "EVENT_RESET", EVENT_RESET);
  ClassDB::bind_integer_constant(get_class_static(), StringName(), "EVENT_ERROR", EVENT_ERROR);
}

int HakoniwaCoreAsset::initialize_asset(const String &asset_name) {
  if (asset_name.is_empty()) {
    return fail("initialize_asset failed: asset_name is empty");
  }
  if (s_registered_) {
    return fail("initialize_asset failed: hakoniwa asset already registered: " +
                String(s_registered_asset_name_.c_str()));
  }

  const CharString asset_name_utf8 = asset_name.utf8();
  const int simevent_err = hakoniwa_simevent_init();
  if (simevent_err != 0) {
    return fail("initialize_asset failed: hakoniwa_simevent_init error=" + String::num_int64(simevent_err));
  }
  const int init_err = hakoniwa_asset_init();
  if (init_err != 0) {
    return fail("initialize_asset failed: hakoniwa_asset_init error=" + String::num_int64(init_err));
  }
  const int register_err = hakoniwa_asset_register_polling(asset_name_utf8.get_data());
  if (register_err != 0) {
    return fail("initialize_asset failed: hakoniwa_asset_register_polling error=" + String::num_int64(register_err));
  }

  asset_name_ = asset_name;
  simtime_usec_ = 0;
  s_registered_ = true;
  s_registered_asset_name_ = asset_name_utf8.get_data();
  set_last_error_text("");
  return 0;
}

int HakoniwaCoreAsset::unregister_asset() {
  if (asset_name_.is_empty()) {
    return fail("unregister_asset failed: no registered asset");
  }
  const CharString asset_name_utf8 = asset_name_.utf8();
  const int err = hakoniwa_asset_unregister(asset_name_utf8.get_data());
  if (err != 0) {
    return fail("unregister_asset failed: error=" + String::num_int64(err));
  }
  asset_name_ = "";
  simtime_usec_ = 0;
  s_registered_ = false;
  s_registered_asset_name_.clear();
  set_last_error_text("");
  return 0;
}

int HakoniwaCoreAsset::poll_event() const {
  if (asset_name_.is_empty()) {
    return fail("poll_event failed: no registered asset");
  }
  const CharString asset_name_utf8 = asset_name_.utf8();
  const int event = hakoniwa_asset_get_event(asset_name_utf8.get_data());
  if (event < 0) {
    return fail("poll_event failed: error=" + String::num_int64(event));
  }
  set_last_error_text("");
  return event;
}

int HakoniwaCoreAsset::get_simulation_state() const {
  const int state = hakoniwa_simevent_get_state();
  if (state < 0) {
    return fail("get_simulation_state failed: error=" + String::num_int64(state));
  }
  set_last_error_text("");
  return state;
}

int HakoniwaCoreAsset::request_start() const {
  const int err = hakoniwa_simevent_start();
  if (err != 0) {
    return fail("request_start failed: error=" + String::num_int64(err));
  }
  set_last_error_text("");
  return 0;
}

int HakoniwaCoreAsset::request_stop() const {
  const int err = hakoniwa_simevent_stop();
  if (err != 0) {
    return fail("request_stop failed: error=" + String::num_int64(err));
  }
  set_last_error_text("");
  return 0;
}

int HakoniwaCoreAsset::request_reset() const {
  const int err = hakoniwa_simevent_reset();
  if (err != 0) {
    return fail("request_reset failed: error=" + String::num_int64(err));
  }
  set_last_error_text("");
  return 0;
}

int HakoniwaCoreAsset::start_feedback_ok() const {
  if (asset_name_.is_empty()) {
    return fail("start_feedback_ok failed: no registered asset");
  }
  const CharString asset_name_utf8 = asset_name_.utf8();
  const int err = hakoniwa_asset_start_feedback_ok(asset_name_utf8.get_data());
  if (err != 0) {
    return fail("start_feedback_ok failed: error=" + String::num_int64(err));
  }
  set_last_error_text("");
  return 0;
}

int HakoniwaCoreAsset::stop_feedback_ok() const {
  if (asset_name_.is_empty()) {
    return fail("stop_feedback_ok failed: no registered asset");
  }
  const CharString asset_name_utf8 = asset_name_.utf8();
  const int err = hakoniwa_asset_stop_feedback_ok(asset_name_utf8.get_data());
  if (err != 0) {
    return fail("stop_feedback_ok failed: error=" + String::num_int64(err));
  }
  set_last_error_text("");
  return 0;
}

int HakoniwaCoreAsset::reset_feedback_ok() const {
  if (asset_name_.is_empty()) {
    return fail("reset_feedback_ok failed: no registered asset");
  }
  const CharString asset_name_utf8 = asset_name_.utf8();
  const int err = hakoniwa_asset_reset_feedback_ok(asset_name_utf8.get_data());
  if (err != 0) {
    return fail("reset_feedback_ok failed: error=" + String::num_int64(err));
  }
  set_last_error_text("");
  return 0;
}

bool HakoniwaCoreAsset::is_pdu_created() const {
  const int created = hakoniwa_asset_is_pdu_created();
  if (created < 0) {
    fail("is_pdu_created failed: error=" + String::num_int64(created));
    return false;
  }
  set_last_error_text("");
  return created != 0;
}

bool HakoniwaCoreAsset::is_pdu_sync_mode() const {
  if (asset_name_.is_empty()) {
    fail("is_pdu_sync_mode failed: no registered asset");
    return false;
  }
  const CharString asset_name_utf8 = asset_name_.utf8();
  const int sync_mode = hakoniwa_asset_is_pdu_sync_mode(asset_name_utf8.get_data());
  if (sync_mode < 0) {
    fail("is_pdu_sync_mode failed: error=" + String::num_int64(sync_mode));
    return false;
  }
  set_last_error_text("");
  return sync_mode != 0;
}

void HakoniwaCoreAsset::notify_write_pdu_done() const {
  if (asset_name_.is_empty()) {
    fail("notify_write_pdu_done failed: no registered asset");
    return;
  }
  const CharString asset_name_utf8 = asset_name_.utf8();
  hakoniwa_asset_notify_write_pdu_done(asset_name_utf8.get_data());
  set_last_error_text("");
}

void HakoniwaCoreAsset::notify_simtime(int64_t simtime_usec) {
  if (asset_name_.is_empty()) {
    fail("notify_simtime failed: no registered asset");
    return;
  }
  const CharString asset_name_utf8 = asset_name_.utf8();
  hakoniwa_asset_notify_simtime(asset_name_utf8.get_data(), simtime_usec);
  simtime_usec_ = simtime_usec;
  set_last_error_text("");
}

int64_t HakoniwaCoreAsset::get_world_time_usec() const {
  set_last_error_text("");
  return static_cast<int64_t>(hakoniwa_asset_get_worldtime());
}

int64_t HakoniwaCoreAsset::get_simtime_usec() const {
  return simtime_usec_;
}

String HakoniwaCoreAsset::get_registered_asset_name() const {
  return asset_name_;
}

String HakoniwaCoreAsset::get_last_error_text() const {
  return last_error_text_;
}

void HakoniwaCoreAsset::set_last_error_text(const String &message) const {
  last_error_text_ = message;
}

int HakoniwaCoreAsset::fail(const String &message) const {
  set_last_error_text(message);
  return -1;
}

} // namespace godot
