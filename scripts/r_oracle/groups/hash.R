# digest's xxhash32, xxh3_64, xxh3_128 and digest2int. A case is (len, salt, seed): the input
# is byte i = (31 i + 17 salt + 7) mod 256 for i < len; digest2int strings use printable
# bytes 32 + (7 i + salt) mod 95. Lengths straddle every path boundary of the algorithms
# (16, 128, 240, and the 1024-byte blocks of the long path).
library(digest)
lens <- unique(c(0:300, 511:513, 1000, 1023:1026, 2047:2049, 4096, 5000, 10000))
seeds <- c(0, 1, 12345)

raw_input <- function(len, salt) as.raw(((seq_len(len) - 1) * 31 + salt * 17 + 7) %% 256)

hashes <- function(fn, algo) {
  unlist(lapply(lens, function(len) lapply(seeds, function(seed) {
    salt <- len %% 7
    case(fn, c(len, salt, seed), digest(raw_input(len, salt), algo = algo, serialize = FALSE, seed = seed))
  })), recursive = FALSE)
}

text_input <- function(len, salt) rawToChar(as.raw(32 + ((seq_len(len) - 1) * 7 + salt) %% 95))

jenkins <- unlist(lapply(0:40, function(len) lapply(c(0, 1, 12345, 99999), function(seed) {
  salt <- len %% 11
  case("digest2int", c(len, salt, seed), digest2int(text_input(len, salt), seed), rel = 0)
})), recursive = FALSE)

emit("hash", "digest", list(
  hashes("xxhash32", "xxhash32"),
  hashes("xxh3_64", "xxh3_64"),
  hashes("xxh3_128", "xxh3_128"),
  jenkins
))

# spookyhash hashes the serialization of the R object, header skipped: for a raw vector that
# is the flags word 0x18, the length, then the bytes, all little-endian (binary format).
emit("spooky", "digest", list(unlist(lapply(lens, function(len) {
  salt <- len %% 7
  list(case("spookyhash", c(len, salt), digest(raw_input(len, salt), algo = "spookyhash")))
}), recursive = FALSE)))
