# tm: stopwords("english"). Args: the characters of the word as codes; the answer is 1 when tm lists it, else 0
suppressMessages(library(tm))
cases <- list()
sw <- stopwords("english")
set.seed(20262490)
pool <- c(sw, sw, c("cat", "dog", "running", "analysis", "statistics", "the", "THE", "i'm", "youre", "wont", "isnt", "mustn't", "shan't", "o'clock", "aint", "gonna", "yourself", "yourselves", "hers", "ours", "also", "would", "could", "may", "might", "very", "too", "just"))
for (w in unique(pool)) cases[[length(cases) + 1]] <- case("sw", utf8ToInt(w), as.numeric(w %in% sw), rel = 0, abs = 0)
# removePunctuation: "rp" with the characters of the text as codes; the answers are the result length ("rpn") and sum(position * code) ("rps")
chars <- c(letters, LETTERS, 0:9, " ", " ", intToUtf8(c(33:47, 58:64, 91:96, 123:126), multiple = TRUE))
for (rep in 1:60) {
  txt <- paste(sample(chars, sample(1:40, 1), TRUE), collapse = "")
  r <- removePunctuation(txt); cc <- utf8ToInt(r)
  cases[[length(cases) + 1]] <- case("rpn", utf8ToInt(txt), length(cc), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("rps", utf8ToInt(txt), sum(cc * seq_along(cc)), rel = 0, abs = 0)
}
emit("tm_stop", "tm", list(cases))
