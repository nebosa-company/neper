#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum { N = 1048576, ITERS = 16 };

int main(void) {
    uint32_t *x = malloc(N * sizeof(*x)), *y = malloc(N * sizeof(*y));
    if (!x || !y) return 1;
    for (size_t i = 0; i < N; ++i) { x[i] = (uint32_t)(i & 1023); y[i] = 1; }
    for (size_t iteration = 0; iteration < ITERS; ++iteration)
        for (size_t i = 0; i < N; ++i) y[i] = 3u * x[i] + y[i];
    uint64_t checksum = 0;
    for (size_t i = 0; i < N; ++i) checksum += y[i];
    printf("gp10 %llu\n", (unsigned long long)checksum);
    free(y); free(x);
    return 0;
}
