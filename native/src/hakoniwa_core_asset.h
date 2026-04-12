#pragma once

#include <string>

#include <godot_cpp/classes/node.hpp>

namespace godot {

class HakoniwaCoreAsset : public Node {
  GDCLASS(HakoniwaCoreAsset, Node)

protected:
  static void _bind_methods();

public:
  enum SimulationState {
    STATE_STOPPED = 0,
    STATE_RUNNABLE = 1,
    STATE_RUNNING = 2,
    STATE_STOPPING = 3,
    STATE_RESETTING = 4,
    STATE_ERROR = 5,
    STATE_TERMINATED = 6,
  };

  enum SimulationEvent {
    EVENT_NONE = 0,
    EVENT_START = 1,
    EVENT_STOP = 2,
    EVENT_RESET = 3,
    EVENT_ERROR = 4,
  };

  HakoniwaCoreAsset() = default;
  ~HakoniwaCoreAsset() override = default;

  int initialize_asset(const String &asset_name);
  int unregister_asset();
  int poll_event() const;
  int get_simulation_state() const;
  int request_start() const;
  int request_stop() const;
  int request_reset() const;
  int start_feedback_ok() const;
  int stop_feedback_ok() const;
  int reset_feedback_ok() const;
  bool is_pdu_created() const;
  bool is_pdu_sync_mode() const;
  void notify_write_pdu_done() const;
  void notify_simtime(int64_t simtime_usec);
  int64_t get_world_time_usec() const;
  int64_t get_simtime_usec() const;
  String get_registered_asset_name() const;
  String get_last_error_text() const;

private:
  mutable String last_error_text_;
  String asset_name_;
  int64_t simtime_usec_ = 0;

  static bool s_registered_;
  static std::string s_registered_asset_name_;

  void set_last_error_text(const String &message) const;
  int fail(const String &message) const;
};

} // namespace godot
