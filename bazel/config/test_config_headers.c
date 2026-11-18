#include "config.h"
#include <stdio.h>

#ifndef PERL_RELOCATABLE_INC
#error "Expected PERL_RELOCATABLE_INC to be defined in config.h"
#endif

#ifndef OSNAME
#error "Expected OSNAME to be defined in config.h"
#endif

#ifndef ARCHNAME
#error "Expected ARCHNAME to be defined in config.h"
#endif

#if defined(PERL_NO_PTHREAD)
#ifdef I_PTHREAD
#error "Expected I_PTHREAD to be undefined when PERL_NO_PTHREAD is set"
#endif
#ifdef HAS_PTHREAD_ATFORK
#error "Expected HAS_PTHREAD_ATFORK to be undefined when PERL_NO_PTHREAD is set"
#endif
#else
#ifndef I_PTHREAD
#error "Expected I_PTHREAD to be defined by default"
#endif
#ifndef HAS_PTHREAD_ATFORK
#error "Expected HAS_PTHREAD_ATFORK to be defined by default"
#endif
#endif

int main(void) {
    printf("Target OS: %s, ARCH: %s, RELOCATABLE: %s\n", OSNAME, ARCHNAME, PERL_RELOCATABLE_INC);
    return 0;
}
