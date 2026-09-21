## D836 — Ten more modules: number theory, roots, combinatorics, range queries, DP, caches, tries and consistent hashing

Batches two and three of the algos.md stream (D834), landed together
because the suites were the long pole and the modules share no code:
`e.math.ntheory` (binary gcd, extended gcd, overflow-free `mul_mod` and
`pow_mod`, the deterministic twelve-base Miller-Rabin, three sieves,
trial, Brent-rho and p-1 factoring, Garner's CRT, baby-step giant-step,
Pohlig-Hellman and the kangaroo, Tonelli-Shanks, Stern-Brocot and
Farey), `e.math.root` (bisection, Newton, Halley, secant, Brent over a
function passed as a value), `e.algo.combin` (checked binomials,
lexicographic permutations and combinations, Heap's algorithm, subsets
and submasks, Gosper's hack, the subset-sum zeta and Möbius
transforms), `e.data.fenwick` and `e.data.sparse_table` (prefix sums
with the lower-bound descent; `O(1)` range extremes and the disjoint
table for sums), `e.algo.dp` (three knapsacks, LIS, generic LCS, coin
change, subset sum, Kadane, matrix chain, optimal BST, the histogram
rectangle, a monotonic stack, the Li Chao tree and the convex hull
trick), `e.data.segment_tree` (a generic fold tree, the lazy `i64` tree
with range add and range sum/min, and a persistent tree over a node
pool), `e.data.cache` (a keyed LRU with its own open-addressing index,
plus FIFO, Clock, LFU, SLRU and 2Q as slot policies over a caller's key
index), `e.data.trie` (a sibling-list byte trie with prefix queries and
an ordered walk) and `e.algo.consistent_hash` (a sorted ring of virtual
nodes, rendezvous, and jump).

What the fixtures found. Every expected value was computed by Python or
SymPy before it went into a fixture, and the ones written from memory
were wrong five times (an unbounded knapsack, a product of negatives, an
optimal BST cost, two jump-hash outputs and a node count), which is the
argument for the rule. The kangaroo needs its wild walk uncapped -- the
distance to the trap is the interval plus the tame walk, not the
interval -- and p-1's bound is on prime powers, so `2^16 - 1` needs a
bound of 65536, not 16. A Fenwick `lower_bound` that returns `len` for
"never" is ambiguous with "the whole array"; it answers `len + 1`. The
persistent tree's pool grows by the depth of the updated leaf, so seven
updates over seven values took 27 nodes, not 28. A slot policy's
`evict` names free slots first, which makes the SLRU "protected tail"
branch unreachable from a caller that refills what it evicts; the
fixture says so rather than pretending. Three more language facts: a
local may not share a name with a module-scope function (`main` in a
fixture), `target` is reserved everywhere, and a two-value call cannot
be forwarded with `ret f()` -- bind it first.

## D837 — Geometry, special functions, random variates, statistical tests and the graph family

Batches four and five of the algos.md stream (D834). `e.algo.geom`
(orientation and segment predicates, the monotone-chain and Jarvis
hulls, closest and farthest pairs, the minimum enclosing circle,
minimum-area rectangle, Pick's theorem and Morton codes) and, because a
single file crossed the parser's token budget at 782 lines,
`e.algo.geom.clip` (Sutherland-Hodgman, Cohen-Sutherland and
Liang-Barsky clipping, ear-clipping triangulation, Douglas-Peucker and
Visvalingam simplification); `e.math.special` (log-gamma, gamma, erf,
the regularised incomplete gamma and beta functions, and the normal,
Student, chi-squared and F distributions on top of them);
`e.algo.rand.dist` (normal by polar method and Box-Muller,
exponential, Poisson, binomial, gamma, beta, Dirichlet, a multivariate
normal by Cholesky, inverse-transform and rejection sampling, the alias
table, weighted reservoirs, stratified and Latin-hypercube designs,
Halton and Sobol) with `e.algo.rand` gaining shuffles, a cycle
permutation and the plain reservoir; `e.algo.stat.test` (one- and
two-sample and Welch t tests, Mann-Whitney, Wilcoxon, chi-squared,
Fisher's exact, Kolmogorov-Smirnov, one-way ANOVA, Kruskal-Wallis, a
permutation test, Bonferroni and Benjamini-Hochberg). The graph family
sits under `e.algo.graph`: `flow` (Edmonds-Karp, Dinic, push-relabel,
the minimum cut, per-edge flow), `match` (Hopcroft-Karp, the Hungarian
algorithm, Gale-Shapley, the blossom algorithm), `path` (Bellman-Ford,
Floyd-Warshall, Dial, Johnson, A*, bidirectional search, IDDFS,
IDA*), `tree` (binary lifting, LCA online and offline, Euler tour,
heavy-light decomposition, centroid decomposition, Prüfer codes, AHU
canonical labels) and `span` (Kruskal, Prim, Borůvka, second-best
tree, bridges and articulation points, Euler paths, transitive
closure).

What the fixtures found. Every expected value came from Python, SciPy
or a hand-built reference again, and the disagreements were on the
fixture's side each time: the KS p-value uses the Numerical Recipes
small-sample correction, a hull output array must not be reused for
the second hull, a point cloud sorted in place is no longer the input,
and the unscented filter of the next batch showed the same trap. The
fixed `lca_offline` is Tarjan's, so it needs a real DFS postorder over
an explicit stack rather than the reverse of a preorder. A module
constant of type `f64` is refused at the top of the file, so `path`
answers its unreachable distance through `fn infinity()`;
`e.algo.sort` has no `cmp` for `f64`, so ranks in `stat.test` sort by
hand. A bool-returning call cannot stand alone as a statement
(`dsu.join`), a generic helper called from a generic needs its argument
spelled (`twin[E]`), and `capacity` and `main` collide with
module-scope names in a fixture.

## D838 — Transforms, integrators, estimators, optimisers, samplers and bit formats

Batches six and seven of the algos.md stream (D834). Six: `e.math.fft` (the radix-2
transform over split real and imaginary arrays, real convolution
through it, the number-theoretic transform over 998244353 and its
convolution, Walsh-Hadamard, and the unnormalised DCT-II and DCT-III),
`e.math.ode` (Euler, RK4, adaptive RKF45 answering the step taken and
the next to try, Störmer-Verlet, leapfrog, the fourth-order Yoshida
composition, Euler-Maruyama with the caller's normal draws),
`e.math.filter` (the linear, extended and unscented Kalman filters over
row-major caller matrices, a resampling particle filter, and the
complementary, Madgwick and Mahony attitude filters), `e.math.opt`
(steepest descent, Polak-Ribière conjugate gradient, BFGS, L-BFGS,
Nelder-Mead, and the two-phase dense simplex) and `e.math.opt.meta`
(simulated annealing, hill climbing, tabu search, a genetic algorithm,
particle swarm, differential evolution, ant colony). `opt` was near the
token budget, so the metaheuristics are a submodule. Seven:
`e.math.opt.convex` (one infeasible-start primal-dual interior-point
method with a dense pivoting Newton solve behind `interior_point` for
linear and `quadratic_program` for convex quadratic programmes; an
equality is two inequalities and a programme that never reaches the
tolerance is `Stalled`), `e.math.mcmc` (random-walk Metropolis-Hastings,
Gibbs through the caller's conditional draw, HMC, and NUTS as Hoffman
and Gelman's algorithm 3 with the recursion's records laid out one per
depth in caller scratch), `e.math.mc` (plain, antithetic and
control-variate estimators over a standard normal), `e.math.float`
(IEEE 754 fields, binary16 and bfloat16 conversions rounding to nearest
even through subnormals) and `e.math.gf` (GF(2^8) over the caller's
polynomial with tables, carry-less 64-bit multiplication and reduction).

What the fixtures found. L-BFGS with the same Armijo backtracking that
serves BFGS never converged on Rosenbrock: a Python replica showed 497
of 500 curvature pairs rejected, so the limited memory was empty and
the method was steepest descent. It now uses a weak-Wolfe search by
bisection on the bracket the two conditions close, and converges in
under forty iterations; a rejected pair also must not overwrite the
oldest stored one, so the pair is tested before it is stored. The DCT
convention is SciPy's up to `2 / N`; the particle step needs
`count * (n + 1)` scratch, which the fixture learned by sizing; the
unscented filter over a range observation is even in position, so the
prior starts on the right side of the origin. Tabu search over a
continuous space needs a move wide enough to cross a basin, which
Python parameter sweeps showed before the fixture pinned the seed.
Batch seven's finds: `0.0 - 0.0` is `+0`, so a negative zero must be
built from its bits; a fixture written by a heredoc that fails a
preceding `&&` step silently does not exist, and the compiler then
reports the missing file as an internal `os.NotFound` rather than naming
it. And a compiler bug worth its own row: a module-scope function in
the fixture named `gradient`, passed as a value into a generic library
function whose body has a local `gradient`, fails lowering with
E-TYPE-9999 (the single-module shape is refused up front as
E-NAME-0003); the fixture calls its function `grad` meanwhile.

## D843 — Text algorithms: phonetics, conventions, stemming, wrapping, scoring, suffix structures, diffs, retrieval and tokenisers

Batches eight and nine of the algos.md stream (D834), ten `e.text`
modules. `e.text.phonetic` (Soundex, the original Metaphone, NYSIIS),
`e.text.casing` (identifier words and the five conventions, slugs, title
case; `case` is a keyword, so the planned `e.text.case` is `casing`),
`e.text.stem` (Porter as published, the Paice/Husk Lancaster rules kept
as their original rule text and interpreted, caller affix stripping),
`e.text.wrap` (greedy and Knuth minimum-raggedness breaking,
justification), `e.text.metric` (BLEU, ROUGE-N and ROUGE-L, exact-match
METEOR), `e.text.suffix` (the suffix array by prefix doubling, Kasai,
range search, the suffix automaton, and the suffix tree derived from the
array), `e.text.diff` (Myers with every frontier kept, patience diff,
patch, three-way merge, conflict ranges, a similarity ratio),
`e.text.rank` (TF-IDF, BM25, reciprocal rank fusion, MMR),
`e.text.index` (an inverted index in the arena, AND and OR over
postings, Elias-Fano) and `e.text.tokenize` (shingles, word breaking,
byte-pair merges, WordPiece, unigram Viterbi and its sampler).

What the fixtures found. Phonetic codes were compared with jellyfish on
166 names and the stemmers with NLTK on 126 words before a single one
went into a fixture, and the port reproduced both -- but jellyfish's
Rust and Python implementations disagree (`Dumb`: TM against TMB), so
the Rust one, which is what the package runs, is the reference. Myers
needed a Python replica to find that the previous diagonal in the
previous frontier's numbering is `k'` for the move down and `k' - 2`
for the move right, not `k' ± 1`; the replica was then run against an
LCS oracle on three thousand random pairs. The first three-way merge
walked both edit scripts in step and silently skipped the other side's
deletion inside a one-sided hunk; the merge now works on hunk regions
(a side's maximal runs of non-keeps as base spans, unioned across sides
until nothing overlaps), which also gives `conflicts` for free. A
suffix tree built from the array without a terminator byte hangs a
whole-suffix leaf under the next suffix; a leaf left on the stack top
now becomes the first child of a new internal node. `0.0 - 0.0` is
`+0`; a bash heredoc holding an apostrophe never reaches the file; and
a Neper name may not be `case`, `error`, `target` or `text` in some
positions -- the fixture and module names changed instead. The suffix
array is prefix doubling rather than the planned SA-IS, and the tree
comes from the array rather than Ukkonen's online construction; both
are noted in algos.md's plan, whose annotations now point at the
modules that actually hold a function when a planned module split
(`e.algo.geom.clip`, `e.math.opt.meta`, `e.math.opt.convex`,
`e.text.casing`).

`docs/progress.html` now counts the selected algorithms: the Modules
tile's denominator includes every `→ e.mod.fn` annotation of algos.md
whose function does not yet exist (fenced or not, duplicates once), so
the percentage measures the library against the plan the user chose
rather than against the fences already written, and it is re-rendered
with every batch of five modules. On this commit it reads 3,713 of
4,605 declarations with 326 of 1,218 selected algorithms delivered.

## D846 — Statistical learning opens: linear models, clustering, neighbours and naive Bayes

Batch ten of the algos.md stream (D834), the first `e.ml` modules, all
over row-major `f64` samples in caller storage and all checked against
scikit-learn (installed for the purpose, with NumPy references where its
estimators differ in convention). `e.ml.linear` (OLS and ridge by the
normal equations with a pivoting solve, lasso by coordinate descent with
soft thresholding, logistic regression by Newton with a ridge so that
separable data stays finite), `e.ml.cluster` (k-means from caller
centroids with k-means++ seeding, an online update and LBG splitting,
PAM k-medoids, agglomerative clustering under three linkages over a
caller distance matrix, a diagonal Gaussian mixture by EM, neighbour
joining), `e.ml.cluster.density` (DBSCAN and OPTICS by full scans),
`e.ml.knn` and `e.ml.bayes` (Gaussian and multinomial). scikit-learn
counts a point among its own neighbours for `min_samples`, so the
library does too; its ridge and lasso leave the intercept unpenalised
through centring, which the coordinate descent reproduces by never
thresholding the last coefficient; its logistic `C` is the reciprocal
of the ridge here. A check for `k > n` must precede the storage check
or the wrong error answers; neighbour joining splits the final distance
evenly, where the textbook leaves it to the reader; BIRCH and the
coreset stream were left for later, the online update standing in for
the stream.

## D847 — Trees, margins, updates, losses and decoders

Batch eleven of the algos.md stream (D834): `e.ml.tree` (CART with Gini
or squared error in the arena, random forests on bootstrap rows with a
feature subset per split, gradient boosting on residuals), `e.ml.svm`
(three kernels and the simplified SMO with a random partner),
`e.ml.optim` (SGD, momentum, RMSprop, Adam and AdamW as single steps,
the cosine schedule with warm restarts, online gradient descent),
`e.ml.loss` (InfoNCE, the triplet hinge, distillation KL, CTC by the
forward algorithm in log space) and `e.ml.sample` (softmax, top-k,
nucleus, contrastive decoding, beam search over a caller's scoring
step). CTC was checked against a brute-force sum over every alignment
of four frames; the beam search against every four-token path of a toy
chain, where greedy decoding takes a different road. scikit-learn
breaks tied splits at random, so the classifier fixture accepts either
tied root; a fixture cannot name a local `error`.

## D848 — Networks, Markov models, tabular control, reduction and approximate search

Batch twelve of the algos.md stream (D834): `e.ml.nn` (the perceptron,
a scalar reverse-mode tape over caller arrays, scaled dot-product and
multi-head attention, rotary embedding), `e.ml.hmm` (forward, Viterbi,
one Baum-Welch pass, against a NumPy reference), `e.ml.rl` (Q-learning
and SARSA updates with epsilon-greedy choice, converging on a corridor
to the discounted goal values), `e.ml.reduce` (PCA by cyclic Jacobi,
Oja's rule, frequent directions through the eigenpairs of the sketch's
Gram matrix, exact t-SNE) and `e.ml.ann` (MinHash with LSH banding, a
navigable small-world graph that is the base layer of HNSW, IVF-PQ over
`e.ml.cluster`). The multi-head attention gathered each head's block
into the output buffer, which is too small when there are fewer than
three heads; the block now lives in scratch. `math.tanh` does not exist,
so the tape's tanh goes through `exp`. HNSW's upper layers and a
complete DABA are deferred (DABA was written from memory, did not
survive scrutiny, and was removed rather than shipped unverified).

## D849 — Node-pool structures: treaps, skip lists, splay trees, windows and a B+ tree

Batch thirteen of the algos.md stream (D834): `e.data.treap` (keyed
treaps by `K.cmp` with split and merge, the implicit treap over a
sequence, persistent inserts by path copying), `e.data.skip_list`
(geometric heights from the caller's generator, a free list for removed
slots), `e.data.splay` (a positional splay tree with a lazy reversal
flag; range reversal splits the range out by two splays), `e.data.window`
(the monotonic queue, the two-stack window fold, the exponential
histogram) and `e.data.btree` (a B+ tree with chained leaves, borrowing
and merging on removal, freed nodes reused). Every structure was run
against a plain array or sorted model through hundreds of random
operations rather than a handful of hand cases. The B+ tree first had
no free list, so three thousand random operations exhausted a pool of
five hundred nodes; then its merge rule let two half-full nodes exceed
the order, so merge and borrow are now chosen by whether both fit in
one node. The monotonic queue expired its front one push early. Node
pools use `0` (treap, splay) or `NONE` (skip list, B+ tree) as the empty
link, and a function may not be named like a parameter (`at`, `next`).

## D850 — Alignment, scheduling, time series, exact cover and metric search

Batch fourteen of the algos.md stream (D834): `e.algo.align`
(Needleman-Wunsch, Smith-Waterman, Gotoh, Hirschberg), `e.algo.schedule`
(activity selection, interval covering, jobs with deadlines over
disjoint slots, the cooldown bound), `e.algo.timeseries` (Holt-Winters,
LOESS and a plain STL, CUSUM, Page-Hinkley and ADWIN as streaming
states, GARCH(1,1) with a Nelder-Mead fit through `e.math.opt`, the
Hawkes process with thinning), `e.algo.exact_cover` (dancing links and
Algorithm X, Sudoku through the 729 × 324 cover) and `e.data.bk_tree`
(metric search over the caller's distance). The alignment scores were
checked against a NumPy dynamic programme and Hirschberg's operations
replayed to both strings; the GARCH fit recovered simulated parameters
within a few hundredths; the change detectors fired within a handful of
samples of a shift and not before. The exact-cover fixture first carried
a hand-typed matrix with a wrong bit, which the solver duly refused --
the one-line generator that prints the bits from the matrix is the
cure, as it was for every hand-typed constant before it.

## D855 — The graph family grows: centralities, colouring, communities, cuts and isomorphism

Batch fifteen of the algos.md stream (D834), all over `e.data.graph`:
`e.algo.graph.centrality` (PageRank, HITS, eigenvector, closeness,
Brandes betweenness), `e.algo.graph.color` (Welsh-Powell, DSATUR),
`e.algo.graph.community` (modularity, label propagation, Louvain with
dense aggregation, edge betweenness and Girvan-Newman),
`e.algo.graph.cut` (Stoer-Wagner, Karger) and `e.algo.graph.iso`
(VF2-style subgraph and graph isomorphism). Every number was checked on
Zachary's karate club against NetworkX -- whose club carries edge
weights from the original paper, so the first references were the
weighted answers (a PageRank of 0.0885 for node 0 against the
unweighted 0.0970, a minimum cut of three edges against one); the
references were regenerated on the unweighted edge list. Two formulas
were wrong on the first run: modularity had summed only adjacent pairs,
leaving out the `-k_v k_w / 2m` of the non-adjacent pairs of a
community, and edge betweenness counted every unordered source pair
twice, which NetworkX halves for an undirected graph. `shared` and
`target` are keywords in fixture locals too; planarity (Boyer-Myrvold)
and Leiden are left for later.

## D856 — Combinatorial optimisation, satisfiability, constraints, minimisation and decision diagrams

Batch sixteen of the algos.md stream (D834): `e.algo.combopt` (tour
construction and 2-opt and Or-opt improvement, Held-Karp, greedy set
cover, first-fit-decreasing, Clarke-Wright, knapsack branch and bound,
a generic branch and bound over caller callbacks, large neighbourhood
search), `e.algo.sat` (a CNF builder with Tseitin gates, the sequential
counter and a decision-diagram pseudo-boolean encoding; DPLL with unit
propagation, flipping backtrack and a learned clause per conflict;
WalkSAT; unit preprocessing; equivalence by a miter), `e.algo.csp`
(AC-3, MAC, limited discrepancy search, and the all-different, element,
table and cumulative filters), `e.algo.logic` (Quine-McCluskey) and
`e.algo.bdd` (ROBDDs with a unique table and apply). The encodings were
checked against plain counting on every assignment of their inputs,
which is the only honest test of an encoding; the tours against the
brute-force optimum of eight cities; Quine-McCluskey on the textbook
function. Christofides, Lin-Kernighan, bounded variable elimination and
Régin's full filtering are left for later. The fixture lessons: five
formulas built over one literal pool overwrite each other (the fixture
rebuilds the one it reuses), and a hand-computed assignment optimum was
wrong by four -- the brute-force check is the point of the fixture, not
the confirmation of the author's arithmetic.

## D857 — Spatial indexes, succinct structures, ropes, Cartesian trees and compressed bitmaps

Batch seventeen of the algos.md stream (D834): `e.data.spatial` (an
implicit k-d tree, quadtree and octree over node pools, a centred
interval tree, a hash grid, an R-tree with quadratic splits and Hilbert
bulk loading, a BVH with ray traversal, a two-dimensional range tree and
a ball tree), `e.data.succinct` (bit vectors with rank and select over
a count per word, LOUDS and balanced-parentheses trees, a wavelet
matrix, a compressed suffix array as Psi plus sampled positions and an
FM-index over a BWT held in the wavelet matrix), `e.data.rope`,
`e.data.cartesian_tree` and `e.data.bitmap` (roaring containers and
word-aligned hybrid vectors whose and/or run over the encoded streams).
From this batch on the modules are written by parallel subagents, one
module each, against the brief in the session scratchpad; the
registration, decision rows, readiness page and suites stay serial.
Every fixture takes its expected values from a Python reference over
LCG-generated inputs. Two lessons: a LOUDS sequence has 2n + 1 bits,
not 2n + 2 (one zero per node plus the super root), and the Hilbert
rotation reflects about the full grid, not the current quadrant --
both were caught by the fixture, not by reading. Deferred with
`ponytail:` notes: fractional cascading in the range tree, a range-min-max
tree for the parentheses, run containers and bitset demotion in roaring,
Boehm's fibonacci rebalance for the rope.

## D858 — Persistent tries, dynamic trees, event-time streams, rate limits and resilience

Batch eighteen of the algos.md stream (D834), the first written entirely
by parallel subagents: `e.data.hamt` (a persistent hash array mapped
trie whose versions share every node off the changed path),
`e.data.link_cut` (splay-based link-cut trees and a dynamic Euler tour
tree), `e.data.stream` (bounded out-of-orderness watermarks, a merge
over idle-aware sources, tumbling and sliding windows fired by the
mark), `e.ratelimit` (token and leaky buckets, fixed window, sliding log
and sliding window over the caller's clock in exact integers) and
`e.resilience` (circuit breaker, jittered backoff, heartbeats, EWMA load
shedding, bulkheads, health aggregation and stable rollout buckets).
The fixtures replay a Python replica of each state machine on the same
LCG inputs and compare hashes of every answer, which is how five modules
by five agents can be trusted at once: nothing in the fixture is derived
from the module under test. Subagent lessons worth keeping: `try`
inside a tuple-returning function type-checks but does not lower, a
discarded non-void call is refused (`let _ = f()`), fixed arrays are
written `[N]T{ a, b }`, and a `usize` where a `u64` is wanted is reported
at the enclosing `if`, not at the argument.

## D859 — Identifier validation, control loops, versions, CBOR and parsing

Batch nineteen of the algos.md stream (D834), by parallel subagents:
`e.valid` (Luhn, ISBN, EAN, UPC and IBAN checks), `e.control` (PID with
anti-windup and Ziegler-Nichols tuning, bang-bang, feedforward, sliding
mode, a discrete LQR by Riccati iteration, Ackermann pole placement and
a Luenberger observer, reusing the matrix helpers of e.math.filter),
`e.fmt.semver` (parsing, precedence and node-style ranges, verified
against node's own semver over 168 pairs rather than a replica),
`e.fmt.cbor` (a streaming encoder and a full-grammar decoder, byte-equal
to cbor2 on the RFC 8949 appendix) and `e.parse` (a scanner, the
off-side rule, shunting-yard, Pratt and recursive descent over one AST
pool, CYK, Earley with next-terminal prediction for constrained
decoding, and a packrat PEG). The control fixture is `control_loop`
because `link/control` already names a compiler fixture. Where a real
implementation was reachable (node semver, cbor2, scipy's place_poles)
the fixture was measured against it; the one hand-typed expectation in
the batch was the wrong one, again.

## D860 — TOML, Markdown, clock synchronisation, trace context and hyphenation

Batch twenty of the algos.md stream (D834), by parallel subagents:
`e.fmt.toml` (a pull parser measured event by event against tomllib),
`e.fmt.markdown` (a CommonMark block and inline subset rendered against
97 examples of the specification and cross-checked with markdown-it),
`e.time.sync` (Marzullo, Berkeley, Cristian), `e.trace` (W3C
traceparent and tracestate) and `e.text.hyphen` (Liang's algorithm with
the pattern subset that reproduces hyph_en_US on the fixture words).
The markdown parser keeps to ASCII whitespace and punctuation for the
flanking rules and reads reference links, entities and raw HTML as
text; the TOML parser detects no duplicate keys, since that needs the
tree a pull parser exists not to build. Both are noted in the sources.

## D861 — Distributed clocks, elections, gossip, failure detection and LL(1)

Batch twenty-one of the algos.md stream (D834): `e.dist.clock`
(Lamport, vector and hybrid logical clocks), `e.dist.election` (bully
and ring, simulated with every message recorded), `e.dist.gossip`
(push/pull rumour rounds and a SWIM-style membership table with
incarnation precedence), `e.dist.failure_detector` (phi accrual through
the exact normal tail) and `e.parse.ll` (nullable, FIRST, FOLLOW, the
LL(1) table and a table-driven parse over e.parse grammars). Every
distributed protocol is a pure state machine over caller storage whose
messages the caller delivers, so a fixture can replay a Python replica
on the same generator stream and compare each answer.

## D862 — LR parsing, collaborative text, property testing, simulation and linearizability

Batch twenty-two of the algos.md stream (D834): `e.parse.lr` (LR(0)
and LR(1) collections, SLR, canonical and LALR tables, a table-driven
parse), `e.text.collab` (operational transformation, an RGA text CRDT
and fractional indexing), `e.test.prop` (generators and shrinkers),
`e.test.sim` (a seeded deterministic scheduler with delays and drops)
and `e.test.linearize` (Wing-Gong search against register, counter and
set models). The lessons the agents reported: a `const` of type `str`
does not type-check (a nullary function holding the literal does), a
public function may not share the name of an imported module (`parse`
in a module that uses e.parse -- import with an alias), and the
linearizability search has no memo, so it is exponential past a dozen
concurrent operations.

## D863 — Pretty printing, JSON Schema, CSS, and the consensus and commit protocols

Batch twenty-three of the algos.md stream (D834): `e.fmt.pretty`
(Wadler layout with a lazy fits lookahead), `e.fmt.json.schema`
(validation over e.fmt.json trees, judged as jsonschema does on 53
pairs), `e.fmt.css` (selector matching right to left, specificity,
cascade, matched as lxml.cssselect does), `e.dist.consensus` (Raft
election, replication, snapshots and joint membership; single-decree
and multi Paxos; viewstamped replication) and `e.dist.commit`
(two- and three-phase commit, sagas, try-confirm-cancel). The consensus
fixture delivers messages from a pool in a seeded order with drops and
checks the safety properties in-fixture (one leader per term, committed
entries never change) as well as the replica's answers. Deferred, in
the sources: no pre-vote, configuration not reverted on truncation,
Multi-Paxos promises carry no accepted values, VR delivered in order.

## D864 — Replicas, collectives, error-correcting codes and quasi-random sequences

Batch twenty-four of the algos.md stream (D834): `e.dist.replica`
(quorum reads and writes by vector clock, read repair, hinted handoff),
`e.dist.collective` (ring all-reduce, binomial broadcast, scatter,
gather with transfer counts), `e.algo.ecc` (Reed-Solomon with errors
and erasures over the GF(2^8) tables of e.math.gf, BCH, a Viterbi
decoder, min-sum LDPC, Hamming and SECDED) and `e.algo.rand.quasi`
(Sobol in Gray-code order, van der Corput, Halton, bit-equal to scipy)
and `e.algo.geom3` (rays, the separating axis theorem, GJK and EPA,
Barnes-Hut, Kabsch by Horn's quaternion, quickhull). The brief handed the agent "n = 5, r = 2,
w = 3 is consistent", which is wrong (2 + 3 is not more than 5); the
fixture asserts the truth, which is the reason the references are
programs rather than sentences.

## D865 — Game navigation, procedural generation, physics, animation and curves

Batch twenty-five of the algos.md stream (D834): `e.game.nav` (a
rectangle navmesh with portals, the funnel, flow fields, hierarchical
A*), `e.game.procgen` (Perlin, simplex and Worley noise, wave function
collapse), `e.game.physics` (position-based and extended position-based
dynamics, projected Gauss-Seidel, conservative advancement, sweep and
prune, SPH, a MAC-grid fluid step) and `e.game.anim` (FABRIK and CCD
inverse kinematics, linear-blend and dual-quaternion skinning) and
`e.gfx.curve` (Bezier, B-spline, Catmull-Rom, NURBS surfaces). Two
agents found the same back-end fault from different sides -- a
pointer-to-float parameter read from a neighbouring slot after float
or excess integer arguments -- and worked around it by returning tuples
or passing a record; the fault is filed as a task, not fixed here.

## D866 — Robot kinematics, motion, planning and mapping, and a signal-processing library

Batch twenty-six of the algos.md stream (D834): `e.robot.kinematics`
(dead reckoning, odometry and Ackermann over one exact arc model,
Denavit-Hartenberg forward kinematics, Jacobian-transpose and
damped-least-squares inverse kinematics), `e.robot.motion` (trapezoid
and S-curve profiles, natural cubic trajectories, minimum jerk, pure
pursuit, Stanley, the dynamic window, velocity obstacles, ORCA with the
RVO2 linear programs, potential fields, elastic bands),
`e.robot.plan` (RRT, RRT*, informed and connect variants, kinodynamic
RRT, PRM, hybrid A*, state lattices, with the generator draw order
stated so a replica can follow), `e.robot.map` (occupancy grids by
Bresenham log-odds, point-to-line ICP, adaptive Monte Carlo
localisation, pose-graph optimisation by Gauss-Newton) and `e.dsp`
(thirty-two entries: smoothing, FIR and IIR filters and their designs
including elliptic prototypes through the complete Jacobi machinery,
windows, Parks-McClellan, STFT and its inverse, MFCC, constant-Q,
cepstrum, LPC, DTW, LMS/NLMS/RLS, polyphase and sinc resampling),
measured against scipy.signal to 1e-9 wherever scipy has the function.
The replica caught a sign error in the velocity-obstacle time to
collision that both the Neper and the first Python version shared; two
independent derivations agreeing is not evidence, a third is.

## D867 — The address of a float carries its pointer type

An address instruction (`FieldAddress`, `IndexAddress`, a local's frame
slot) carries the type of what it addresses, and a call classifies its
arguments by the defining instruction's type. So `&x` with `x: f64`
was classified as a float: the caller moved the address into an xmm
register (or, past the register arguments on System V, counted it in
the float file for the stack layout) while the callee read a pointer
from the integer file. Win64 showed it as `fn f(x: f64, y: f64, seed:
u64, p: *f64)` reading `p` from the seed's register; System V as a
`*f64` seventh or eighth argument reading nil or zero. Two library
agents met it independently (D865, D857) and worked around it with
tuples and a record. The fix is in lowering: `&place` whose place is a
float now passes through a `Bitcast` to the pointer type, the way
`mem.address_of` already retypes to `usize` (D210), so every consumer
that reads a value's type -- argument classification, comparison
selection -- sees a pointer. Only float places are retyped; every other
address already classifies as an integer. The link fixture
`pointer_float_args` covers pointers after floats (both widths), the
seventh, eighth and ninth arguments, a slice before the pointers, the
address of a field and of an element, and a compared pointer; it
crashes under the previous compiler on both hosts.

## D868 — Meshes, rasterisation, shading, path tracing and compressed textures

Batch twenty-seven of the algos.md stream (D834): `e.gfx.mesh` (half
edges, normals, Laplacian and Taubin smoothing, Loop and Catmull-Clark
subdivision, quadric decimation, marching squares and cubes with a
generated table, dual contouring, signed distance, fast-marching and
heat geodesics, LSCM, ball-pivot and a one-grid Poisson reconstruction,
BSP booleans, revolution), `e.gfx.raster` (Bresenham, Wu, midpoint
circles and ellipses, top-left-rule triangles), `e.gfx.shade`
(GGX/Smith/Schlick with importance sampling), `e.gfx.trace` (a sphere
path tracer in three modes and interval CSG) and `e.gfx.texture` (the
BC family and a complete LDR ASTC decoder measured against astcenc
itself over fifty blocks). The mesh replica caught four errors before
the first build -- the Catmull-Clark vertex rule, an in-place
compaction, the LSCM pin residual and an unguarded quadric optimum --
which is the argument for writing the replica first. The agent that
wrote the mesh module also cleared the session scratchpad, taking the
registration tooling and the batch descriptions with it; the tooling
was rewritten from this conversation and the brief now says what a
scratchpad is.

## D869 — Anti-entropy, CRDTs, deadlock detection, distributed hash tables and locks

Batch twenty-eight of the algos.md stream (D834): `e.dist.anti_entropy`
(Merkle trees over key-range buckets with a counted top-down sync),
`e.dist.crdt` (G- and PN-counters, LWW registers, OR-sets with tags and
tombstones, one `merge` dispatch), `e.dist.deadlock` (wait-for-graph
cycles and Chandy-Misra-Haas edge chasing, where an initiator outside
the cycle correctly detects nothing), `e.dist.dht` (Chord finger tables
and Kademlia XOR lookups) and `e.dist.lock` (Redlock with skew and
latency, leases with due-time renewal). None of the five imports
anything: they are arithmetic over caller arrays.

## D870 — Distributed mutual exclusion, global snapshots and image filters

Batch twenty-nine of the algos.md stream (D834): `e.dist.mutex`
(Ricart-Agrawala and Raymond's tree with exact message counts),
`e.dist.snapshot` (Chandy-Lamport over FIFO channels, checked by token
conservation) and `e.gfx.filter` (twenty grid filters from Gaussian
blur to watershed, each pixel-exact or within 1e-9 of scipy.ndimage or
scikit-image, including Canny once its non-maximum suppression became
the bilinear one scikit-image uses -- the quantised-direction variant
was ten percent off, which the replica showed and the plan text never
would have). Also `e.gfx.vision`: Harris, Hough, homographies and
fundamental matrices, RANSAC, phase correlation, Lucas-Kanade and
Farneback flow, ICP, ORB, SIFT, Zhang calibration and two-view structure
from motion, each against a replica cross-checked with scikit-image.
And `e.audio.analysis` (pitch by YIN, pYIN, autocorrelation and HPS,
onsets, tempo and beats, chroma, BS.1770 loudness, voice activity).

## D871 — Audio effects and synthesis

Batch thirty of the algos.md stream (D834): `e.audio.fx` (compressor,
limiter, gate, equaliser, NLMS echo cancellation, Schroeder and
feedback-delay-network reverbs, convolution reverb, phase-vocoder
stretch and shift, TD-PSOLA) and `e.audio.synth` (ADSR, PolyBLEP
oscillators, wavetables, Karplus-Strong), both over `e.dsp`. The
analysis module of the same family (`e.audio.analysis`: pitch, onsets,
tempo and beats, chroma, LUFS loudness, voice activity) landed with
batch twenty-nine. A lesson the agent recorded: `mem.alloc` hands back
unzeroed memory, so a module clears any scratch it reads before it
writes.
