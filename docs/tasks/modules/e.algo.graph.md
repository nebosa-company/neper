# e.algo.graph — 1 of 59 declarations missing

| field | value |
|---|---|
| file to create | `lib/e/algo/graph.e` |
| plan row | layer 2, surface `partial`, milestone none, schedule `later` |
| blocked by | nothing recorded in `modules.json` |
| unmet dependencies | none — every dependency has source |

## Definition of done

Implement **exactly** the public fence below in `lib/e/algo/graph.e`; nothing more, nothing less, same spelling, same order. A module is delivered only when `python scripts/check_module_surfaces.py` finds every declaration, its `modules.json` row moves to `surface:"source"` in the same commit, and a `link/<module>` fixture proves the behaviour on both hosts (README §Fixture template).

Roadmap wave (`docs/roadmap.md`, 'Later toolchain-library waves'):

> **Extended containers and graph algorithms:** `e.data.tree`, `e.data.graph`, `e.data.slot_map`, `e.algo.disjoint_set` and `e.algo.graph`. Existing collections gain deterministic non-mutating iterators; `e.data.heap` also gains comparator/context and linear-time bulk construction. Graph delivery covers BFS, DFS, deterministic topological sorting, weak/strong components and Dijkstra over immutable CSR views.

## Dependencies

| dependency | surface | source file | layer |
|---|---|---|---|
| `e.data.graph` | source | `lib/e/data/graph.e` | 2 |
| `e.data.heap` | source | `lib/e/data/heap.e` | 2 |
| `e.mem` | spec | `lib/e/mem.e` | 0 |

The module may `use` only these (`scripts/check_module_plan.py` enforces it). Layer 2 may depend on layers [0, 1, 2].

## Public API fence (verbatim from `docs/module-apis.md`)

```neper
type Traversal = struct { order: []const graph.NodeId, parent: []const graph.NodeId }
type Components = struct { component: []const u32, count: u32 }
type Paths = struct { distance: []const f64, previous: []const graph.NodeId }
type Entry = struct { distance: f64, node: graph.NodeId }
type Forest = struct { edges: []const usize, weight: f64, trees: usize }
type WeightedEdge = struct { weight: f64, index: usize }
type LowLinks = struct { disc: []u32, low: []u32, is_bridge: []u8, is_cut: []u8, time: u32 }
error Cycle
error InvalidWeight
error TooLarge
error NegativeCycle
error NoPath
error NoArborescence
error NotEulerian
error Disconnected
error TooSmall

fn fresh_parents(a: *mem.Arena, count: usize, start: graph.NodeId) -> ([]graph.NodeId, err)
fn bfs[E: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId) -> (Traversal, err)
fn dfs[E: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId) -> (Traversal, err)
fn topological[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const graph.NodeId, err)
fn weak_components[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (Components, err)
fn build_reverse[E: type](g: *const graph.Graph[E], reverse_offsets: []usize, reverse: []graph.NodeId)
fn strong_components[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (Components, err)
fn entry_cmp(ctx: *u8, x: Entry, y: Entry) -> i32
fn dijkstra[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Paths, err)
fn unreached() -> f64
fn path_to(a: *mem.Arena, previous: []const graph.NodeId, start: graph.NodeId, goal: graph.NodeId) -> ([]const graph.NodeId, err)
fn bellman_ford[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> (Paths, err)
fn floyd_warshall[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> ([]f64, err)
fn dijkstra_indexed[E: type](g: *const graph.Graph[E], start: graph.NodeId, w: []const f64, distance: []f64, queue: *heap.HeapBy[Entry, u8]) -> err
fn johnson[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64) -> ([]f64, err)
fn dial[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, max_weight: usize, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> usize) -> ([]usize, err)
fn bucket_of(key: u32, last: u32) -> usize
fn dijkstra_radix_heap[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> u32) -> ([]u32, err)
fn bfs_levels[E: type](g: *const graph.Graph[E], start: graph.NodeId, level: []u32, queue: []graph.NodeId) -> u32
fn eccentricities[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]u32, err)
fn center[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const graph.NodeId, err)
fn diameter[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (u32, err)
fn count_triangles[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (u64, err)
fn k_core[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]u32, err)
fn twin[E: type](g: *const graph.Graph[E], k: usize) -> usize
fn k_truss[E: type](a: *mem.Arena, g: *const graph.Graph[E], k: u32) -> ([]u8, err)
fn clique_search[Ctx: type](ctx: *Ctx, visit: fn(*Ctx, []const graph.NodeId), adj: []const u8, n: usize, r: []graph.NodeId, depth: usize, members: []graph.NodeId, p_count: usize, scratch: []graph.NodeId) -> usize
fn max_cliques[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, visit: fn(*Ctx, []const graph.NodeId)) -> (usize, err)
fn find_top(above: []const u32, x: u32) -> u32
fn arborescence[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], root: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, chosen: []usize) -> (Forest, err)
fn low_visit[E: type](g: *const graph.Graph[E], s: *LowLinks, u: graph.NodeId, from: graph.NodeId)
fn low_links[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> (LowLinks, err)
fn articulation_points[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const graph.NodeId, err)
fn bridges[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const usize, err)
fn euler_path[E: type](a: *mem.Arena, g: *const graph.Graph[E]) -> ([]const graph.NodeId, err)
fn transitive_closure[E: type](g: *const graph.Graph[E], reach: []u8) -> err
fn set_find(sets: []u32, x: u32) -> u32
fn set_join(sets: []u32, x: u32, y: u32) -> bool
fn fresh_sets(a: *mem.Arena, n: usize) -> ([]u32, err)
fn weighted_edge_cmp(ctx: *u8, x: WeightedEdge, y: WeightedEdge) -> i32
fn mst_kruskal[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, chosen: []usize) -> (Forest, err)
fn mst_prim[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], start: graph.NodeId, ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, chosen: []usize) -> (Forest, err)
fn mst_boruvka[E: type, Ctx: type](a: *mem.Arena, g: *const graph.Graph[E], ctx: *Ctx, weight: fn(*Ctx, graph.Edge[E]) -> f64, chosen: []usize) -> (Forest, err)
```

Traversal order is deterministic from node order and each adjacency list's insertion
order. An unreachable node has parent `graph.NONE`; the start is its own parent.
Topological sorting returns the lexicographically smallest available node first and
returns `Cycle` without a partial order. Component identifiers are assigned by the
smallest node in each component. Dijkstra rejects negative, NaN and infinite weights
as `InvalidWeight`; unreachable distance is positive infinity and its predecessor is
`graph.NONE`. All returned slices are arena-owned.

## Missing declarations

- [ ] `low_visit`

## Style references

Delivered modules beside this one — copy their idioms (arena parameter first, `(value, err)` returns, no hidden allocation, `error` names as declared):

- `lib/e/algo/align.e`
- `lib/e/algo/batch.e`
- `lib/e/algo/bdd.e`
- `lib/e/algo/bignum.e`
- `lib/e/algo/bitset.e`
- `lib/e/algo/chain.e`
- `lib/e/algo/check.e`
- `lib/e/algo/checksum.e`†

## Verification

- `build/windows/tests/selfhost/neper-self.exe parse-file lib/e/algo/graph.e` prints `parse file ok`.
- A fixture `tests/selfhost/fixtures/link/algo_graph/src/main.e` that prints one fixed line on success, registered in both runners.
- `python scripts/check_module_surfaces.py --compiler <neper-self> --arch x64 --os <host>` and `python tests/test_module_plan.py` pass.
- Both suites green; `python scripts/render_progress.py` shows the module declaration count rising by 1.

## Session procedure

1. Read `docs/tasks/README.md` once: model limits, repository traps, the build and
   verification commands, the fixture template.
2. Pick **one** line of the remaining checklist above. Do not attempt the whole item.
3. Read the anchors listed here by line range (`git grep -n IDENT FILE`, then
   `sed -n 'A,Bp' FILE`), never a whole file over 120 KB.
4. Write the change, the fixture, and both runner entries (`tests/selfhost/run.ps1`
   and `run.sh`) in the same increment.
5. Build and run both suites (README). A green C-bootstrap build proves nothing on its
   own; the self-hosted stage must build and stage 2 must equal stage 3.
6. Append `## D<n> — <title>` to `docs/decisions.md` for any design choice.
7. Update this item's `score` and `evidence` in `docs/work-queue.json`: append the new sentence to the evidence and keep the `Not yet:` clause truthful. Run `python scripts/render_progress.py` and commit only the touched paths.
