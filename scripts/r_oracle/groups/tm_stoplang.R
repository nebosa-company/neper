# tm: stopwords(language) for the thirteen Snowball languages. Args: (language index 0 .. 12, then the bytes of the word); the answer is 1 when tm lists the word for that language, else 0
suppressMessages(library(tm))
cases <- list()
langs <- c("danish","dutch","english","finnish","french","german","hungarian","italian","norwegian","portuguese","russian","spanish","swedish")
sw <- lapply(langs, stopwords); allw <- unique(unlist(sw))
set.seed(20262491)
for (k in seq_along(langs)) {
  inl <- sample(sw[[k]], min(40, length(sw[[k]]))); out <- sample(setdiff(allw, sw[[k]]), 40)
  for (w in c(inl, out)) cases[[length(cases) + 1]] <- case("sl", c(k - 1, as.integer(charToRaw(enc2utf8(w)))), as.numeric(w %in% sw[[k]]), rel = 0, abs = 0)
}
emit("tm_stoplang", "tm", list(cases))
