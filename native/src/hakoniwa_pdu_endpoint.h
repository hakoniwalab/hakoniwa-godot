#pragma once

#include <godot_cpp/classes/node.hpp>

namespace godot {

class HakoniwaPduEndpoint : public Node {
  GDCLASS(HakoniwaPduEndpoint, Node)

protected:
  static void _bind_methods();

public:
  HakoniwaPduEndpoint() = default;
  ~HakoniwaPduEndpoint() override = default;

  String get_backend_name() const;
  bool probe_native_backend() const;
};

} // namespace godot
