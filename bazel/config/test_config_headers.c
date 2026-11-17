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

int main(void) {
    printf("Target OS: %s, ARCH: %s, RELOCATABLE: %s\n", OSNAME, ARCHNAME, PERL_RELOCATABLE_INC);
    return 0;
}
