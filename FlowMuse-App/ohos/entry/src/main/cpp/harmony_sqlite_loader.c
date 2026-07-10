#include <dlfcn.h>

int harmony_sqlite_make_global(void) {
    void* self = dlopen("libharmony_sqlite.z.so", RTLD_NOW | RTLD_GLOBAL);
    return self ? 0 : 1;
}
