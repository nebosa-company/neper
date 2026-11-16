# bnlearn network scores of a given DAG: discrete (loglik, aic, bic, bde, k2) and Gaussian (loglik-g, aic-g, bic-g).
#   args: (n, v, kind 0 discrete 1 gaussian, iss, nlev[v] (0 for gaussian), adj[v*v] row-major (p * v + i = arc p -> i), data[n*v] row-major, discrete as 0-based codes)
#   fn: "loglik" "aic" "bic" "bde" "k2" "loglik-g" "aic-g" "bic-g"
suppressMessages(library(bnlearn))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
set.seed(20261223)
for (rep in 1:24) {
  v <- sample(3:6, 1); n <- sample(60:300, 1); kind <- rep %% 2
  ord <- sample(v); adj <- matrix(0, v, v)
  for (i in 2:v) for (j in 1:(i - 1)) if (runif(1) < 0.45 && sum(adj[, ord[i]]) < 3) adj[ord[j], ord[i]] <- 1
  nodes <- paste0("V", seq_len(v))
  arcs <- which(adj == 1, arr.ind = TRUE)
  g <- empty.graph(nodes); if (nrow(arcs)) arcs(g) <- matrix(nodes[arcs], ncol = 2)
  iss <- sample(1:5, 1) + 0.5
  if (kind == 0) {
    nlev <- sample(2:3, v, TRUE)
    d <- as.data.frame(lapply(seq_len(v), function(i) factor(sample(0:(nlev[i] - 1), n, TRUE), levels = 0:(nlev[i] - 1)))); names(d) <- nodes
    for (i in seq_len(v)) { pa <- which(adj[, i] == 1); if (length(pa)) { sh <- rowSums(sapply(pa, function(p) as.numeric(as.character(d[[p]])))); flip <- runif(n) < 0.7; d[[i]] <- factor(ifelse(flip, sh %% nlev[i], as.numeric(as.character(d[[i]]))), levels = 0:(nlev[i] - 1)) } }
    a <- c(n, v, 0, iss, nlev, as.vector(t(adj)), as.vector(t(sapply(d, function(f) as.numeric(as.character(f))))))
    # the data matrix is rows by variables: rebuild row-major from columns
    m <- sapply(d, function(f) as.numeric(as.character(f))); a <- c(n, v, 0, iss, nlev, as.vector(t(adj)), as.vector(t(m)))
    for (s in c("loglik", "aic", "bic", "bde", "k2")) add(s, a, as.numeric(score(g, d, type = s, iss = iss)))
  } else {
    d <- as.data.frame(matrix(rnorm(n * v), n)); names(d) <- nodes
    for (i in ord) { pa <- which(adj[, i] == 1); if (length(pa)) d[[i]] <- d[[i]] + as.vector(as.matrix(d[, pa, drop = FALSE]) %*% runif(length(pa), 0.3, 1)) }
    a <- c(n, v, 1, iss, rep(0, v), as.vector(t(adj)), as.vector(t(as.matrix(d))))
    for (s in c("loglik-g", "aic-g", "bic-g")) add(s, a, as.numeric(score(g, d, type = s)))
  }
}
emit("bnlearn", "bnlearn", list(cases))
