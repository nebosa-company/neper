# tm: stopwords("english"). Args: the characters of the word as codes; the answer is 1 when tm lists it, else 0
suppressMessages(library(tm))
cases <- list()
sw <- stopwords("english")
set.seed(20262490)
pool <- c(sw, sw, c("cat", "dog", "running", "analysis", "statistics", "the", "THE", "i'm", "youre", "wont", "isnt", "mustn't", "shan't", "o'clock", "aint", "gonna", "yourself", "yourselves", "hers", "ours", "also", "would", "could", "may", "might", "very", "too", "just"))
for (w in unique(pool)) cases[[length(cases) + 1]] <- case("sw", utf8ToInt(w), as.numeric(w %in% sw), rel = 0, abs = 0)
emit("tm_stop", "tm", list(cases))
