#include <cstdint>
#include <cstdio>
#include <vector>

constexpr std::size_t N = 4194317, ITERS = 8;

int main() {
    std::vector<std::uint8_t> input(N), text(2 * N), back(N);
    constexpr char hex[] = "0123456789abcdef";
    for (std::size_t i = 0; i < N; ++i) input[i] = std::uint8_t(i * 73 + 19);
    for (std::size_t iteration = 0; iteration < ITERS; ++iteration) {
        for (std::size_t i = 0; i < N; ++i) {
            text[2 * i] = hex[input[i] >> 4];
            text[2 * i + 1] = hex[input[i] & 15];
        }
        for (std::size_t i = 0; i < N; ++i) {
            auto nibble = [](std::uint8_t c) { return std::uint8_t(c <= '9' ? c - '0' : c - 'a' + 10); };
            auto hi = nibble(text[2 * i]), lo = nibble(text[2 * i + 1]);
            if (hi > 15 || lo > 15) return 2;
            back[i] = std::uint8_t((hi << 4) | lo);
        }
    }
    std::uint64_t checksum = 0;
    for (std::size_t i = 0; i < N; ++i) { if (back[i] != input[i]) return 3; checksum += back[i]; }
    std::printf("gp09 %llu\n", static_cast<unsigned long long>(checksum));
}
