#ifndef _CPP_STDSTRING_BINDING_H_
#define _CPP_STDSTRING_BINDING_H_

#include <cstring>

extern "C" {
  void hello(char* buf, std::size_t buf_len);
}

#endif
