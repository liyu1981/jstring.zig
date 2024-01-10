#ifndef _CPP_STDSTRING_H_
#define _CPP_STDSTRING_H_

#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

// translate-c provide: new_string
void* new_string(const char* buf, size_t buf_len);
// translate-c provide: free_string
void free_string(void* ptr);

#ifdef __cplusplus
}
#endif

#endif
