#include "cpp_stdstring.h"

#include <cstring>
#include <string>

extern "C" {
  void* new_string(const char* str, size_t str_len) {
      std::string* s = new std::string(str, str_len);
      return (void*)s;
  }

  void free_string(void* ptr) {
    delete (std::string*)ptr;
  }
}
