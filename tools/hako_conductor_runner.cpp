#include "hako_conductor.h"

#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string_view>
#include <thread>

#ifdef _WIN32
#include <windows.h>
#endif

namespace {

volatile std::sig_atomic_t g_stop_requested = 0;

void request_stop() {
  if (g_stop_requested != 0) {
    return;
  }
  g_stop_requested = 1;
  hako_conductor_stop();
}

void handle_signal(int) {
  request_stop();
}

#ifdef _WIN32
BOOL WINAPI handle_console_ctrl(DWORD ctrl_type) {
  switch (ctrl_type) {
    case CTRL_C_EVENT:
    case CTRL_BREAK_EVENT:
    case CTRL_CLOSE_EVENT:
    case CTRL_SHUTDOWN_EVENT:
      request_stop();
      return TRUE;
    default:
      return FALSE;
  }
}
#endif

bool parse_int64(const char* text, std::int64_t& out_value) {
  char* end_ptr = nullptr;
  errno = 0;
  const long long parsed = std::strtoll(text, &end_ptr, 10);
  if (errno != 0 || end_ptr == text || *end_ptr != '\0') {
    return false;
  }
  out_value = static_cast<std::int64_t>(parsed);
  return true;
}

void print_usage(const char* argv0) {
  std::cerr
      << "Usage: " << argv0
      << " [--delta-usec N] [--max-delay-usec N] [--sleep-sec N]\n";
}

}  // namespace

int main(int argc, char** argv) {
  std::int64_t delta_usec = 10000;
  std::int64_t max_delay_usec = 20000;
  std::int64_t sleep_sec = 0;

  for (int index = 1; index < argc; ++index) {
    const std::string_view arg(argv[index]);
    if (arg == "--delta-usec" || arg == "--max-delay-usec" || arg == "--sleep-sec") {
      if (index + 1 >= argc) {
        print_usage(argv[0]);
        return 2;
      }
      std::int64_t value = 0;
      if (!parse_int64(argv[index + 1], value) || value < 0) {
        std::cerr << "invalid numeric value for " << arg << ": " << argv[index + 1] << '\n';
        return 2;
      }
      if (arg == "--delta-usec") {
        delta_usec = value;
      } else if (arg == "--max-delay-usec") {
        max_delay_usec = value;
      } else {
        sleep_sec = value;
      }
      ++index;
      continue;
    }
    if (arg == "-h" || arg == "--help") {
      print_usage(argv[0]);
      return 0;
    }
    std::cerr << "unknown option: " << arg << '\n';
    print_usage(argv[0]);
    return 2;
  }

  std::signal(SIGINT, handle_signal);
  std::signal(SIGTERM, handle_signal);
#ifdef _WIN32
  SetConsoleCtrlHandler(handle_console_ctrl, TRUE);
#endif

  const int start_result = hako_conductor_start(
      static_cast<hako_time_t>(delta_usec),
      static_cast<hako_time_t>(max_delay_usec));
  if (start_result != 0) {
    std::cerr << "failed to start conductor: " << start_result << '\n';
    return 1;
  }

  if (sleep_sec > 0) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(sleep_sec);
    while (g_stop_requested == 0 && std::chrono::steady_clock::now() < deadline) {
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    request_stop();
    return 0;
  }

  while (g_stop_requested == 0) {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  return 0;
}
