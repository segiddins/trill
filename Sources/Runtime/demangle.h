//
//  demangle.hpp
//  Trill
//

#ifndef demangle_hpp
#define demangle_hpp

#include <stdio.h>
#include "defines.h"

#ifdef __cplusplus
#include <string>
namespace trill {
bool demangle(std::string &symbol, std::string &out);

extern "C" {
#endif
  
char *trill_demangle(const char *symbol);

#ifdef __cplusplus
}
}
#endif

#endif /* demangle_hpp */
