# SnowballC wordStem: language "porter" (0) and "english" (1). Args: (language, the bytes of a lower-case word); the answer is 1e6 * nchar(stem) + sum(position * code) of the stem
suppressMessages(library(SnowballC))
cases <- list()
txt <- tolower(readLines(file.path(R.home("doc"), "COPYING"), warn = FALSE))
words <- unique(unlist(strsplit(txt, "[^a-z]+"))); words <- words[nchar(words) >= 2]
set.seed(20262492)
words <- sample(words, min(700, length(words)))
for (lg in 0:1) for (w in words) {
  s <- wordStem(w, c("porter", "english")[lg + 1]); cc <- as.integer(charToRaw(s))
  cases[[length(cases) + 1]] <- case("st", c(lg, as.integer(charToRaw(w))), 1e6 * length(cc) + sum(cc * seq_along(cc)), rel = 0, abs = 0)
}
emit("snowball", "SnowballC", list(cases))
