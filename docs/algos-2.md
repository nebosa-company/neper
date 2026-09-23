# Algorithm Library Requirements — Books vs. e.lib Gap Analysis

Derived from: *Problems on Algorithms* (Parberry & Gasarch), *Introduction of Advanced Algorithms in Software Engineering* (Nazar), *Advanced Algorithms* (Bandiera), *CMU 15-850* (Gupta), *1,000 Programming Functions and Algorithms*.

Status: requirements proposal. Names are placeholders pending `modules.json` and `module-apis.md` amendment. Not a commitment to a delivery milestone.

---

## Already in e.lib (not repeated here)

The following algorithm categories from the books are already implemented or have direct equivalents in the current e.lib:

- **Sorting** — `e.algo.sort`
- **Searching** — `e.algo.search`
- **Shortest paths** — Bellman-Ford, Floyd-Warshall, Johnson's, Dijkstra, A*, IDA*, Dial — `e.algo.graph.path`
- **Network flow** — Edmonds-Karp, Dinic, Push-Relabel, Min-Cut — `e.algo.graph.flow`
- **Graph matching, coloring, centrality, community, min-cut** — `e.algo.graph.*`
- **Union-Find** — `e.algo.disjoint_set`
- **Dynamic programming** — Knapsack, LCS, Matrix Chain, Optimal BST, Kadane, LICS — `e.algo.dp`
- **Combinatorial optimization** — TSP (2-opt, OR-opt, Held-Karp), Set Cover, Bin Packing, Knapsack B&B, LNS, generic B&B — `e.algo.combopt`
- **Graph data structures** — `e.data.graph`, `.list`, `.heap`, `.tree`, `.map`, etc.
- **Streaming sketches** — Bloom Filter, Count-Min, HyperLogLog, Misra-Gries, Space-Saving, MinHash, SimHash — `e.algo.sketch`
- **Optimization** — Gradient Descent, Conjugate Gradient, BFGS, L-BFGS, Nelder-Mead, Simplex LP — `e.math.opt`
- **Linear models** — OLS, Ridge, Lasso, Logistic — `e.ml.linear`
- **Hashing, random, UUID, bitset, statistics** — `e.algo.hash`, `.rand`, `.uuid`, `.bitset`, `.stat`
- **Math** — FFT, N-theory, roots, special, ODE, filter, convex opt — `e.math.*`
- **Machine learning** — 15 modules (NN, SVM, Bayes, clustering, RL, etc.) — `e.ml.*`
- **Geometry clipping** — `e.algo.geom.clip`

---

## Tier 1 — Best fits (high value, low implementation friction)

### T1.1 — `e.algo.string` — String Algorithms

**Source books:** Book 5 (1,000 algorithms, section 4: string algorithms), Book 2 (string matching section)

**Gap:** Neper has `e.str` for byte-string manipulation and `e.text.*` for Unicode, but no dedicated string-matching algorithm module. Suffix arrays, KMP, Boyer-Moore, and Aho-Corasick are not planned anywhere in `modules.json`.

**Algorithms to implement:**

| Algorithm | Complexity | Notes |
|---|---|---|
| Prefix function / KMP | O(n + m) | Build failure function, search pattern in text |
| Z-function | O(n) | Compute Z-array, pattern matching |
| Boyer-Moore | O(n/m) worst case | Bad character + good suffix heuristics |
| Rabin-Karp | O(n + m) avg | Rolling hash, multi-pattern |
| Aho-Corasick | O(n + m + z) | Multi-pattern automaton |
| Suffix Array | O(n log n) | SA-IS or prefix-doubling |
| Suffix Array + LCP | O(n) | Kasai's algorithm |
| Extended KMP (Z-algorithm) | O(n) | Pattern matching variant |

**Proposed module path:** `e.algo.string`
**Dependencies:** `e.str`, `e.math` (for hashing)
**Surface:** `source`
**Fit rationale:** Pure deterministic algorithms, no allocation beyond caller storage, directly compatible with Neper's procedural model. High practical value for text processing.

**Signature sketch:**
```neper
// Prefix function for KMP.
fn prefix_function(s: []const u8) -> ([]usize, err)

// KMP search. Returns all match positions.
fn kmp_search(text: []const u8, pattern: []const u8) -> ([]usize, err)

// Boyer-Moore search.
fn boyer_moore_search(text: []const u8, pattern: []const u8) -> ([]usize, err)

// Rabin-Karp search with configurable base and modulus.
fn rabin_karp_search(text: []const u8, pattern: []const u8) -> ([]usize, err)

// Aho-Corasick automaton.
type AhoCorasick = struct { ... }
fn aho_corasick_init(patterns: [][]const u8) -> (AhoCorasick, err)
fn aho_corasick_search(ac: *const AhoCorasick, text: []const u8) -> ([]usize, err)

// Suffix array (SA-IS or prefix-doubling).
fn suffix_array(s: []const u8) -> ([]usize, err)

// LCP array from suffix array (Kasai).
fn lcp_array(s: []const u8, sa: []const usize) -> ([]usize, err)
```

---

### T1.2 — `e.algo.approx` — Approximation Algorithm Framework

**Source books:** Book 2 (Nazar — approximation algorithms section), Book 3 (Bandiera — vertex cover, set cover, TSP approximation)

**Gap:** `e.algo.combopt` has heuristics (nearest neighbor, 2-opt, greedy set cover) but provides no approximation guarantees. There is no formal `e.algo.approx` module implementing algorithms with provable competitive ratios.

**Algorithms to implement:**

| Algorithm | Problem | Approx Ratio | Notes |
|---|---|---|---|
| Vertex Cover 2-approx | Vertex Cover | 2 | Greedy maximal matching |
| Set Cover ln(n)-approx | Set Cover | H(n) | Chvátal's greedy (exists in combopt, needs guarantee wrapper) |
| Metric TSP Christofides | TSP | 3/2 | MST + perfect matching + Euler circuit |
| Min-Cut approximation | Max Cut | 1/2 | Randomized + derandomized |
| Knapsack FPTAS | Knapsack | (1-ε) | Scaling + DP |
| Bin Packing FFDA | Bin Packing | 11/9 · OPT + 1 | First-fit decreasing analysis |
| Scheduling LPT | Makespan | 4/3 - 1/(3m) | Longest processing time first |
| Load Balancing | Makespan | 2 - 1/m | Greedy assignment |

**Proposed module path:** `e.algo.approx`
**Dependencies:** `e.algo.combopt`, `e.algo.graph.span`, `e.algo.graph.match`, `e.algo.graph.path`
**Surface:** `source`
**Fit rationale:** Extends existing heuristics in `e.algo.combopt` with formal approximation ratio tracking. Each algorithm is pure computation over caller-owned data. The framework can return both the solution and its proven bound.

**Signature sketch:**
```neper
// Approximation result with guaranteed bound.
type ApproxResult = struct { cost: f64, ratio: f64, guarantee: []const u8 }

// Vertex Cover 2-approximation.
fn vertex_cover_2approx(g: *const graph.Graph, ...) -> ([]usize, ApproxResult, err)

// Christofides TSP 3/2-approximation.
fn christofides_tsp(d: []const f64, n: usize, ...) -> ([]usize, f64, ApproxResult, err)

// Knapsack FPTAS.
fn knapsack_fptas(weights: []const f64, values: []const f64, capacity: f64, eps: f64) -> (f64, ApproxResult, err)
```

---

### T1.3 — `e.algo.online` — Online and Competitive Algorithms

**Source books:** Book 3 (ski rental, paging, k-server, online experts), Book 4 (weighted majority, hedge, bandits)

**Gap:** No dedicated online algorithm module exists. `e.ml` has online learning (Hedge, Weighted Majority) but the formal competitive analysis framework (paging, ski rental, k-server, snoopy caching) is absent.

**Algorithms to implement:**

| Algorithm | Problem | Competitive Ratio | Notes |
|---|---|---|---|
| Ski Rental | Online leasing | 2 - 1/e ≈ 1.63 | Deterministic optimal |
| Marking / Bélády | Paging | k (number of pages) | LRU is k-competitive |
| k-Server | Metrical task system | 2k - 1 | Work-function algorithm |
| CLIQUE / BALANCE | Load balancing | 2 - 1/m | Greedy assignment |
| Move-to-Front | List access | 2 - H_k | Amortized analysis |
| Ski Rental with predictions | Online leasing with advice | 1 + ε | ML-augmented |
| Online Facility Location | Facility placement | O(log n) | Greedy + primal-dual |

**Proposed module path:** `e.algo.online`
**Dependencies:** `e.math`, `e.data.heap`, `e.data.list`
**Surface:** `source`
**Fit rationale:** Online algorithms are pure state machines operating on adversarial input sequences. They fit Neper's procedural model perfectly — no GC, no allocation beyond scratch space. The competitive ratio analysis can be baked into the return values.

**Signature sketch:**
```neper
// Ski rental: buy vs. rent. Returns total cost and ratio.
fn ski_rental(periods: usize, buy_cost: usize) -> (usize, f64, err)

// Paging: LRU, FIFO, Marking algorithms. Returns cache misses.
type PageReplacement = enum { lru, fifo, marking, optimal }
fn paging(pages: []const usize, cache_size: usize, strategy: PageReplacement) -> (usize, err)

// Move-to-Front on access sequences.
fn move_to_front(accesses: []const usize, list: []usize) -> (usize, err)

// Online load balancing (greedy / balanced).
fn load_balance(jobs: []const usize, machines: usize, strategy: Strategy) -> ([]usize, err)

// Online k-server (work-function algorithm).
fn k_server(requests: []const usize, distances: []const f64, k: usize) -> (f64, err)
```

---

### T1.4 — `e.algo.linalg` extension — Advanced Matrix Algorithms

**Source books:** Book 1 (Strassen's algorithm), Book 4 (SVD, dimension reduction)

**Gap:** `e.algo.linalg.matrix` and `e.algo.linalg.tensor` exist but lack advanced algorithms: Strassen's multiplication, SVD, QR decomposition, eigenvalue decomposition, and iterative solvers.

**Algorithms to implement:**

| Algorithm | Complexity | Notes |
|---|---|---|
| Strassen's matrix multiplication | O(n^log₂7) ≈ O(n^2.81) | Recursive, threshold to naive |
| QR decomposition (Householder) | O(n³) | Orthogonal-triangular factorization |
| SVD (Golub-Kahan) | O(n³) | Singular value decomposition |
| Eigenvalue (QR algorithm) | O(n³) | Hessenberg + QR iteration |
| LU decomposition with partial pivoting | O(n³/3) | Forward-back substitution |
| Cholesky decomposition | O(n³/6) | For SPD matrices |
| Conjugate gradient for linear systems | O(n·nnz) | Iterative, SPD matrices |
| GMRES | O(n·nnz·k) | Iterative, general systems |

**Proposed module path:** Extend `e.algo.linalg.matrix` and `.tensor`
**Dependencies:** `e.algo.linalg.matrix`, `e.math`
**Surface:** `source`
**Fit rationale:** Direct extension of the existing linalg module. These are standard numerical algorithms with well-defined inputs and outputs. Strassen's fits the matrix multiplication interface; SVD and QR extend it.

**Signature sketch:**
```neper
// Strassen's matrix multiplication (thresholds to naive below n).
fn strassen(a: []const f64, b: []const f64, n: usize, threshold: usize) -> ([]f64, err)

// QR decomposition: A = Q·R.
fn qr(a: []const f64, m: usize, n: usize) -> (q: []f64, r: []f64, err)

// Singular value decomposition: A = U·Σ·Vᵀ.
fn svd(a: []const f64, m: usize, n: usize) -> (u: []f64, sigma: []f64, vt: []f64, err)

// Eigenvalue decomposition (symmetric matrices).
fn eigenvalues(a: []const f64, n: usize) -> (values: []f64, vectors: []f64, err)

// Conjugate gradient for A·x = b (SPD).
fn conj_gradient(a: []const f64, b: []const f64, n: usize, tol: f64, max_iter: u32) -> ([]f64, err)
```

---

## Tier 2 — Good fits (medium friction, high value)

### T2.1 — `e.algo.geom` extension — Computational Geometry

**Source books:** Book 1 (geometry problems), Book 5 (computational geometry)

**Gap:** `e.algo.geom.clip` exists but the module lacks fundamental algorithms: convex hull, Delaunay triangulation, Voronoi diagrams, line segment intersection, and point location.

**Algorithms to implement:**

| Algorithm | Complexity | Notes |
|---|---|---|
| Graham scan | O(n log n) | Convex hull |
| Andrew's monotone chain | O(n log n) | Convex hull, simpler |
| Quickhull | O(n log n) avg | Expected-case convex hull |
| Delaunay triangulation | O(n log n) | From convex hull or incremental |
| Voronoi diagram | O(n log n) | Dual of Delaunay |
| Line segment intersection | O((n + k) log n) | Bentley-Ottmann sweep |
| Point location | O(log n) | Kirkpatrick's hierarchy or trapezoidal |
| Closest pair | O(n log n) | Divide and conquer |
| Convex hull trick | O(n log n) | Lower envelope of lines |

**Proposed module path:** Extend `e.algo.geom`
**Dependencies:** `e.algo.geom.clip`, `e.algo.sort`, `e.data.stack`
**Surface:** `source`
**Fit rationale:** Extends the existing geometry module with fundamental algorithms. All are pure computational geometry with well-defined numerical inputs.

---

### T2.2 — `e.algo.dimreduction` — Dimension Reduction

**Source book:** Book 4 (CMU 850 — Johnson-Lindenstrauss Lemma)

**Gap:** No dimension reduction module exists. The JL Lemma and PCA are fundamental for ML pipelines but not planned.

**Algorithms to implement:**

| Algorithm | Complexity | Notes |
|---|---|---|
| Johnson-Lindenstrauss | O(nk + k²) | Random projection |
| PCA | O(nd² + d³) | Covariance + eigendecomposition |
| Random Projection | O(nk) | Gaussian/sparse projection matrix |
| MDS (Multidimensional Scaling) | O(n²d) | Classical MDS |

**Proposed module path:** `e.algo.dimreduction`
**Dependencies:** `e.algo.linalg.matrix`, `e.algo.linalg.tensor`, `e.math`, `e.algo.rand`
**Surface:** `source`
**Fit rationale:** ML/data science pipeline component. Extends existing linalg and random modules. Pure computation.

---

### T2.3 — `e.algo.coding` extension — Advanced Coding Theory

**Source book:** Book 5 (coding algorithms)

**Gap:** `e.algo.coding` exists but is minimal. Missing Huffman coding (may exist elsewhere), arithmetic coding, LZW, Burrows-Wheeler transform, and suffix-tree-based algorithms.

**Algorithms to implement:**

| Algorithm | Complexity | Notes |
|---|---|---|
| Huffman coding | O(n log n) | Optimal prefix code |
| Arithmetic coding | O(n) | Fractional-bit coding |
| Burrows-Wheeler Transform | O(n log n) | BWT + MTF for compression |
| LZW | O(n) | Dictionary-based compression |
| Suffix tree (Ukkonen) | O(n) | Linear-time suffix tree |
| Prefix-free codes | O(n) | Shannon-Fano / Huffman variant |

**Proposed module path:** Extend `e.algo.coding`
**Dependencies:** `e.algo.coding`, `e.data.heap`, `e.algo.string`
**Surface:** `source`
**Fit rationale:** Coding algorithms are pure, stateless, and directly useful in `e.fmt` modules and compression formats.

---

### T2.4 — `e.algo.deterministic` — Randomized-to-Deterministic Conversions

**Source book:** Book 3 (approximation through randomness, derandomization)

**Gap:** `e.algo.rand` provides randomness but no framework for derandomization (method of conditional expectations, pairwise independence, universal hashing for deterministic algorithms).

**Algorithms to implement:**

| Algorithm | Notes |
|---|---|
| Method of conditional expectations | Derandomization of randomized approximation |
| Universal hashing | Deterministic hash families |
| Pairwise independent permutations | Derandomization of geometric algorithms |
| ε-net construction | Deterministic ε-nets for range spaces |
| Discrepancy theory algorithms | Beck-Fiala, Spencer's theorem |

**Proposed module path:** `e.algo.deterministic`
**Dependencies:** `e.algo.rand`, `e.algo.hash`, `e.math`
**Surface:** `source`
**Fit rationale:** Provides the theoretical bridge between randomized and deterministic algorithms, complementing `e.algo.approx`.

---

## Summary

| Tier | Module | Source Books | Priority | Surface |
|---|---|---|---|---|
| 1.1 | `e.algo.string` | Book 2, Book 5 | High | `source` |
| 1.2 | `e.algo.approx` | Book 2, Book 3 | High | `source` |
| 1.3 | `e.algo.online` | Book 3, Book 4 | High | `source` |
| 1.4 | `e.algo.linalg` ext | Book 1, Book 4 | High | `source` |
| 2.1 | `e.algo.geom` ext | Book 1, Book 5 | Medium | `source` |
| 2.2 | `e.algo.dimreduction` | Book 4 | Medium | `source` |
| 2.3 | `e.algo.coding` ext | Book 5 | Medium | `source` |
| 2.4 | `e.algo.deterministic` | Book 3 | Medium | `source` |

None of the following are recommended for implementation: quantum algorithms (Neper targets x64/SPIR-V/PTX), distributed algorithms (Neper is single-node), SDP solvers (requires full math framework first), interior-point methods (simplex in `e.math.opt` covers LP), NP-completeness proofs (theory, not runtime).
