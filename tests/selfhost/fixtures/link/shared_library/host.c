#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
    void *lib = dlopen(argv[1], RTLD_NOW);
    if (!lib) { printf("dlopen: %s\n", dlerror()); return 1; }
    unsigned long (*sum)(unsigned long) = dlsym(lib, "neper_sum");
    unsigned long (*calls)(void) = dlsym(lib, "neper_calls");
    if (!sum || !calls) { printf("dlsym: %s\n", dlerror()); return 2; }
    if (dlsym(lib, "neper_raw_string") != NULL) {
        printf("raw string text became an exported symbol\n");
        return 4;
    }
    unsigned long a = sum(100), b = sum(10);
    printf("sum(100)=%lu sum(10)=%lu calls=%lu\n", a, b, calls());
    return (a == 5050 && b == 55 && calls() == 2) ? 0 : 3;
}
