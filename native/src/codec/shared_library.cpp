#include "codec/shared_library.h"

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

#include <utility>

namespace hako::godot_codec {

namespace {

std::string default_error_message() {
  return "shared library operation failed";
}

#if defined(_WIN32)
std::string format_windows_error_message(DWORD error_code) {
  if (error_code == 0) {
    return default_error_message();
  }

  LPSTR raw_message = nullptr;
  const DWORD size = FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                                        FORMAT_MESSAGE_IGNORE_INSERTS,
                                    nullptr,
                                    error_code,
                                    MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                                    reinterpret_cast<LPSTR>(&raw_message),
                                    0,
                                    nullptr);
  if (size == 0 || raw_message == nullptr) {
    return default_error_message();
  }

  std::string message(raw_message, size);
  LocalFree(raw_message);
  while (!message.empty() && (message.back() == '\r' || message.back() == '\n')) {
    message.pop_back();
  }
  return message;
}
#endif

} // namespace

SharedLibrary::~SharedLibrary() {
  close();
}

SharedLibrary::SharedLibrary(SharedLibrary &&other) noexcept
    : path_(std::move(other.path_)), handle_(other.handle_) {
  other.reset();
}

SharedLibrary &SharedLibrary::operator=(SharedLibrary &&other) noexcept {
  if (this == &other) {
    return *this;
  }
  close();
  path_ = std::move(other.path_);
  handle_ = other.handle_;
  other.reset();
  return *this;
}

bool SharedLibrary::open(const std::string &path, std::string *error_message) {
  close();

#if defined(_WIN32)
  HMODULE module = LoadLibraryA(path.c_str());
  if (module == nullptr) {
    if (error_message != nullptr) {
      *error_message = format_windows_error_message(GetLastError());
    }
    return false;
  }
  handle_ = module;
#else
  handle_ = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (handle_ == nullptr) {
    if (error_message != nullptr) {
      const char *message = dlerror();
      *error_message = (message != nullptr) ? message : default_error_message();
    }
    return false;
  }
#endif

  path_ = path;
  return true;
}

void SharedLibrary::close() {
  if (handle_ == nullptr) {
    reset();
    return;
  }

#if defined(_WIN32)
  FreeLibrary(reinterpret_cast<HMODULE>(handle_));
#else
  dlclose(handle_);
#endif
  reset();
}

bool SharedLibrary::is_open() const {
  return handle_ != nullptr;
}

void *SharedLibrary::resolve_symbol(const char *symbol_name, std::string *error_message) const {
  if (handle_ == nullptr || symbol_name == nullptr) {
    if (error_message != nullptr) {
      *error_message = "shared library is not open";
    }
    return nullptr;
  }

#if defined(_WIN32)
  FARPROC symbol = GetProcAddress(reinterpret_cast<HMODULE>(handle_), symbol_name);
  if (symbol == nullptr) {
    if (error_message != nullptr) {
      *error_message = format_windows_error_message(GetLastError());
    }
    return nullptr;
  }
  return reinterpret_cast<void *>(symbol);
#else
  dlerror();
  void *symbol = dlsym(handle_, symbol_name);
  const char *message = dlerror();
  if (message != nullptr) {
    if (error_message != nullptr) {
      *error_message = message;
    }
    return nullptr;
  }
  return symbol;
#endif
}

const std::string &SharedLibrary::path() const {
  return path_;
}

void SharedLibrary::reset() {
  path_.clear();
  handle_ = nullptr;
}

} // namespace hako::godot_codec
