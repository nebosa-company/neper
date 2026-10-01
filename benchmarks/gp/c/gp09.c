#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum { N = 4194317, ITERS = 8 };

static void encode(uint8_t *dst, const uint8_t *src) {
    static const uint8_t hex[] = "0123456789abcdef";
    for (size_t i = 0; i < N; ++i) {
        dst[2 * i] = hex[src[i] >> 4];
        dst[2 * i + 1] = hex[src[i] & 15];
    }
}

static int decode(uint8_t *dst, const uint8_t *src) {
    for (size_t i = 0; i < N; ++i) {
        uint8_t a = src[2 * i], b = src[2 * i + 1];
        uint8_t hi = a <= '9' ? a - '0' : a - 'a' + 10;
        uint8_t lo = b <= '9' ? b - '0' : b - 'a' + 10;
        if (hi > 15 || lo > 15) return 0;
        dst[i] = (uint8_t)((hi << 4) | lo);
    }
    return 1;
}

int main(void) {
    uint8_t *input = aligned_alloc(16, (N + 15) / 16 * 16), *text = malloc(2 * N), *back = malloc(N);
    if (!input || !text || !back) return 1;
    for (size_t i = 0; i < N; ++i) input[i] = (uint8_t)(i * 73 + 19);
    for (size_t i = 0; i < ITERS; ++i) { encode(text, input); if (!decode(back, text)) return 2; }
    uint64_t checksum = 0;
    for (size_t i = 0; i < N; ++i) { if (back[i] != input[i]) return 3; checksum += back[i]; }
    printf("gp09 %llu\n", (unsigned long long)checksum);
    free(back); free(text); free(input);
    return 0;
}
