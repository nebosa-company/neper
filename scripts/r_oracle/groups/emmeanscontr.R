# the coefficient matrices of emmeans' *.emmc functions for k levels: "emmc" args (kind 0 pairwise, 1 revpairwise, 2 trt.vs.ctrl, 3 trt.vs.ctrlk, 4 consec, 5 eff, 6 del.eff, 7 poly, k, r, c) level r of contrast c
suppressMessages(library(emmeans))
cases <- list()
fns <- c("pairwise", "revpairwise", "trt.vs.ctrl", "trt.vs.ctrlk", "consec", "eff", "del.eff", "poly")
for (kind in 0:7) for (k in 3:7) {
  M <- as.matrix(get(paste0(fns[kind + 1], ".emmc"))(1:k))
  for (r in seq_len(nrow(M))) for (cc in seq_len(ncol(M))) cases[[length(cases) + 1]] <- case("emmc", c(kind, k, r - 1, cc - 1), M[r, cc], rel = 1e-9, abs = 1e-9)
}
emit("emmeanscontr", "emmeans", list(cases))
