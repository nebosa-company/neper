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
# the preserve options: "rq" with args (flags 1 contractions 2 dashes 3 both, then the text codes): length and position-weighted sum
for (rep in 1:80) {
  txt <- paste(sample(c(letters[1:6], "'", "-", " ", ".", "_", "1", "'", "-"), sample(3:30, 1), TRUE), collapse = ""); fl <- 1 + rep %% 3
  r <- removePunctuation(txt, preserve_intra_word_contractions = fl %in% c(1, 3), preserve_intra_word_dashes = fl %in% c(2, 3)); cc <- utf8ToInt(r)
  cases[[length(cases) + 1]] <- case("rqn", c(fl, utf8ToInt(txt)), length(cc), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("rqs", c(fl, utf8ToInt(txt)), sum(cc * seq_along(cc)), rel = 0, abs = 0)
}
# tokenizers::tokenize_words (tidytext unnest_tokens words): "tw" the text codes; the tokens joined by newlines, as length ("twn") and position-weighted code sum ("tws")
suppressMessages(library(tokenizers))
for (rep in 1:100) {
  txt <- paste(sample(c(letters[1:5], LETTERS[1:3], "0", "1", "7", " ", " ", ".", "'", ",", "-", "_", "!", "?", "a", "b"), sample(3:40, 1), TRUE), collapse = "")
  tk <- tokenize_words(txt)[[1]]; r <- paste(tk, collapse = "
"); cc <- utf8ToInt(r)
  cases[[length(cases) + 1]] <- case("twn", utf8ToInt(txt), length(cc), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("tws", utf8ToInt(txt), sum(cc * seq_along(cc)), rel = 0, abs = 0)
}
emit("tm_stop", "tm", list(cases))
