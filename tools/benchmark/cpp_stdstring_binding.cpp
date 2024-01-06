#include "cpp_stdstring_binding.h"

extern "C" {
  void hello(char* buf, std::size_t buf_len) {
      const char* world = "world";
      std::memcpy(buf, world, buf_len);
  }
}
