#include <cstdint>
#include <cstdio>
#include <vector>

constexpr std::size_t N = 1048576, ITERS = 16;

int main() {
    std::vector<std::uint32_t> x(N), y(N, 1);
    for (std::size_t i = 0; i < N; ++i) x[i] = std::uint32_t(i & 1023);
    for (std::size_t iteration = 0; iteration < ITERS; ++iteration)
        for (std::size_t i = 0; i < N; ++i) y[i] = 3u * x[i] + y[i];
    std::uint64_t checksum = 0;
    for (auto value : y) checksum += value;
    std::printf("gp10 %llu\n", static_cast<unsigned long long>(checksum));
}
