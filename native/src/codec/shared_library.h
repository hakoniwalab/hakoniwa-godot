#pragma once

#include <cstdint>
#include <string>

namespace hako::godot_codec {

class SharedLibrary {
public:
  SharedLibrary() = default;
  ~SharedLibrary();

  SharedLibrary(const SharedLibrary &) = delete;
  SharedLibrary &operator=(const SharedLibrary &) = delete;

  SharedLibrary(SharedLibrary &&other) noexcept;
  SharedLibrary &operator=(SharedLibrary &&other) noexcept;

  bool open(const std::string &path, std::string *error_message);
  void close();
  [[nodiscard]] bool is_open() const;
  [[nodiscard]] void *resolve_symbol(const char *symbol_name, std::string *error_message) const;
  [[nodiscard]] const std::string &path() const;

private:
  void reset();

  std::string path_;
#if defined(_WIN32)
  void *handle_ = nullptr;
#else
  void *handle_ = nullptr;
#endif
};

} // namespace hako::godot_codec
