# 1,000 Programming Functions and Algorithms

Converted from `1,000 Programming Functions and Algorithms - Google Gemini.pdf`, a Gemini chat transcript that ran to 1,750 items in 30 categories; sections 31–40 (1751–2250) were added afterwards in the same style.
Numbering is global; the ranges in the headings are the transcript's own.



## Standard library plan

Every entry below carries a verdict. 1232 entries map to a library function, 213 are duplicates of one of those (`see #N`), and 805 are skipped with a one-word reason.

- **`→ e.mod.fn`** — implementable; the proposed module and function name. Names follow the existing conventions in `docs/module-apis.md`: `snake_case`, arena-first for allocating calls, `[T: type]` generics.
- **→ see #N** — the same algorithm already appears at #N; implement it once, there.
- **→ skip: reason** — not a library function. Reasons:

  - **toy** — pedagogical only
  - **niche** — implementable, but too specialised for the standard library
  - **technique** — a technique applied per problem, not a reusable function
  - **internal** — an implementation detail of an existing module, not an API
  - **compiler** — belongs in the Neper compiler, not the library
  - **tooling** — belongs in the toolchain (build, test runner, pacman)
  - **kernel** — OS kernel internals
  - **hardware** — hardware or circuit design
  - **protocol** — network protocol beyond the library scope
  - **product** — a vendor product's architecture
  - **system** — a whole service or system, not a function
  - **model** — a trained ML model or training recipe
  - **research** — research-grade, no settled practical implementation
  - **physics** — domain simulation outside a general library
  - **quantum** — needs quantum hardware or a simulator
  - **finance** — quantitative-finance domain
  - **bio** — bioinformatics domain tool
  - **nogc** — Neper has ownership, not a garbage collector
  - **offensive** — attack technique
  - **legacy** — obsolete cryptography

### Modules

Existing modules are named in `docs/modules.json`; new ones are proposals, listed with the parent they extend.

| Module | Status | Entries |
|---|---|---|
| `e.algo.align` | new | #305, #306, #307, #1154 |
| `e.algo.bdd` | new | #1390 |
| `e.algo.bignum` | existing | #476, #491 |
| `e.algo.bitset` | existing | #842 |
| `e.algo.coding` | new | 19 entries, first #319 |
| `e.algo.combin` | new | #420, #421, #422, #423, #439, #847 |
| `e.algo.combopt` | new | #114, #115, #116, #117, #118, #415, #1984, #1986, #1995, #1997, #1998, #1999 |
| `e.algo.consistent_hash` | new | #255, #256, #928, #938 |
| `e.algo.csp` | new | #1971, #1973, #1979, #1980, #1981, #1982, #1983, #1985 |
| `e.algo.deflate` | existing | #620 |
| `e.algo.disjoint_set` | existing | #200, #201, #202, #1076 |
| `e.algo.dp` | new | 18 entries, first #266 |
| `e.algo.ecc` | new | #854, #855, #856, #859, #860 |
| `e.algo.egraph` | new | #1970 |
| `e.algo.exact_cover` | new | #217, #417 |
| `e.algo.geo` | new | #1672 |
| `e.algo.geom` | new | 37 entries, first #429 |
| `e.algo.geom.clip` | new (split from `e.algo.geom`) | #533, #534, #536, #537, #557, #558 |
| `e.algo.geom3` | new | #522, #523, #524, #525, #526, #1032, #1168, #2015, #2045, #2046 |
| `e.algo.graph` | existing | 25 entries, first #61 |
| `e.algo.graph.centrality` | new (under `e.algo.graph`) | #90, #91, #173, #174, #175 |
| `e.algo.graph.color` | new (under `e.algo.graph`) | #160, #161 |
| `e.algo.graph.community` | new (under `e.algo.graph`) | #105, #106, #107, #1177 |
| `e.algo.graph.cut` | new (under `e.algo.graph`) | #108, #110 |
| `e.algo.graph.flow` | new (under `e.algo.graph`) | #75, #76, #77, #164 |
| `e.algo.graph.iso` | new (under `e.algo.graph`) | #119, #120 |
| `e.algo.graph.match` | new (under `e.algo.graph`) | #78, #79, #102, #103, #165 |
| `e.algo.graph.path` | new (under `e.algo.graph`) | #65, #94, #95, #96, #98, #100, #101 |
| `e.algo.graph.tree` | new (under `e.algo.graph`) | #84, #85, #86, #87, #88, #89, #213, #215, #986 |
| `e.algo.hash` | existing | #455, #565, #567, #568, #569, #570, #571, #843 |
| `e.algo.linalg.matrix` | existing | 14 entries, first #501 |
| `e.algo.logic` | new | #1371 |
| `e.algo.privacy` | new | #1419, #1420, #1421 |
| `e.algo.query` | new | #283 |
| `e.algo.rand` | existing | 15 entries, first #57 |
| `e.algo.rand.dist` | new (under `e.algo.rand`) | 13 entries, first #1489 |
| `e.algo.rand.quasi` | new (under `e.algo.rand`) | #1948, #1949 |
| `e.algo.sat` | new | #1391, #1952, #1959, #1960, #1961, #1962, #1963 |
| `e.algo.schedule` | new | #406, #407, #409, #413 |
| `e.algo.search` | new | 13 entries, first #22 |
| `e.algo.sketch` | new | 42 entries, first #237 |
| `e.algo.smt` | new | #1966, #1968 |
| `e.algo.sort` | existing | 15 entries, first #1 |
| `e.algo.stat` | existing | 20 entries, first #1426 |
| `e.algo.stat.test` | new (under `e.algo.stat`) | 15 entries, first #1534 |
| `e.algo.timeseries` | new | #1498, #1500, #2196, #2197, #2198, #2199, #2200 |
| `e.algo.uuid` | existing | #954, #955, #956, #957, #958 |
| `e.async` | existing | #701, #1609 |
| `e.atomic` | existing | #664, #665, #666, #1327 |
| `e.audio` | existing | #1899 |
| `e.audio.analysis` | new (under `e.audio`) | #804, #1868, #1869, #1870, #1874, #1875, #1876, #1877, #1885, #1900 |
| `e.audio.fx` | new (under `e.audio`) | #1871, #1872, #1873, #1884, #1886, #1887, #1888, #1889, #1890, #1891, #1892 |
| `e.audio.synth` | new (under `e.audio`) | #1893, #1894, #1895, #1896 |
| `e.bytes` | existing | 21 entries, first #320 |
| `e.concurrent.deque` | new | #1273 |
| `e.concurrent.queue` | existing | #674 |
| `e.concurrent.reclaim` | new | #677, #678 |
| `e.concurrent.stack` | new | #675 |
| `e.control` | new | #1801, #1802, #1803, #1804, #1805, #1806, #1808, #1809, #1810 |
| `e.crypto.aead` | existing | #603 |
| `e.crypto.cipher` | new | #578, #580, #604, #605 |
| `e.crypto.classic` | new | #315, #316, #317, #318 |
| `e.crypto.hash` | existing | #561, #562, #563, #564 |
| `e.crypto.kdf` | existing | #573, #574, #575, #576, #577 |
| `e.crypto.kx` | existing | #583, #584, #592 |
| `e.crypto.mac` | existing | #572, #606 |
| `e.crypto.merkle` | new | #599 |
| `e.crypto.noise` | new | #1587 |
| `e.crypto.secret` | new | #588 |
| `e.crypto.sign` | existing | #582, #585, #586, #587, #593, #1442 |
| `e.crypto.x509` | existing | #1431 |
| `e.data.bitmap` | new | #633, #634 |
| `e.data.bk_tree` | new | #218 |
| `e.data.btree` | new | #191, #192, #193 |
| `e.data.cache` | new | #268, #269, #270, #271, #272, #273, #274 |
| `e.data.cartesian_tree` | new | #210 |
| `e.data.fenwick` | new | #194, #195 |
| `e.data.hamt` | new | #1084 |
| `e.data.heap` | existing | #228, #229, #230, #232, #233, #234, #235, #236, #1077, #1081 |
| `e.data.link_cut` | new | #211, #212, #1065, #1066 |
| `e.data.linked` | existing | #29, #260, #263 |
| `e.data.queue` | existing | #128 |
| `e.data.ring` | existing | #265 |
| `e.data.rope` | new | #288 |
| `e.data.segment_tree` | new | #196, #197, #198, #199 |
| `e.data.skip_list` | new | #226, #227 |
| `e.data.sparse_table` | new | #279, #280, #281 |
| `e.data.spatial` | new | 14 entries, first #219 |
| `e.data.splay` | new | #187, #278 |
| `e.data.stream` | new | #1297 |
| `e.data.succinct` | new | #225, #1051, #1052, #1053, #1054, #1055, #1056 |
| `e.data.treap` | new | #188, #189, #277, #1070 |
| `e.data.tree` | existing | #181, #182, #214 |
| `e.data.trie` | new | #203, #204, #205, #206, #900, #1085 |
| `e.data.window` | new | #267, #2180, #2182, #2183 |
| `e.db.pool` | new (under `e.db`) | #1673 |
| `e.db.query` | new (under `e.db`) | 16 entries, first #877 |
| `e.db.storage` | new (under `e.db`) | 18 entries, first #717 |
| `e.debug` | existing | #1337, #1347 |
| `e.dist.anti_entropy` | new | #934 |
| `e.dist.clock` | new | #147, #148 |
| `e.dist.collective` | new | #1255, #1256 |
| `e.dist.commit` | new | #720, #921, #922, #923, #1263 |
| `e.dist.consensus` | new | #134, #135, #912, #1257, #1259, #1260, #1292 |
| `e.dist.crdt` | new | #1268 |
| `e.dist.deadlock` | new | #111, #940 |
| `e.dist.dht` | new | #130, #131 |
| `e.dist.election` | new | #143, #144 |
| `e.dist.failure_detector` | new | #927 |
| `e.dist.gossip` | new | #142, #939 |
| `e.dist.lock` | new | #933, #1270 |
| `e.dist.mutex` | new | #145, #154 |
| `e.dist.replica` | new | #935, #936, #937 |
| `e.dist.snapshot` | new | #152 |
| `e.dsp` | new | 32 entries, first #794 |
| `e.fmt.arrow` | new | #2095 |
| `e.fmt.asn1` | existing | #2091, #2092 |
| `e.fmt.avro` | new | #2094 |
| `e.fmt.brotli` | new | #621 |
| `e.fmt.bson` | existing | #2093 |
| `e.fmt.cbor` | new | #2090 |
| `e.fmt.css` | new | #2103, #2104 |
| `e.fmt.csv` | existing | #966, #2071 |
| `e.fmt.flac` | new | #646 |
| `e.fmt.flatbuffers` | new | #2087 |
| `e.fmt.html` | existing | #965, #2101, #2102 |
| `e.fmt.ini` | existing | #2085 |
| `e.fmt.json` | existing | #343, #2072, #2073, #2074, #2075, #2077, #2078 |
| `e.fmt.json.schema` | new (under `e.fmt.json`) | #2076 |
| `e.fmt.jwt` | new | #1405 |
| `e.fmt.lz4` | new | #618 |
| `e.fmt.lzma` | new | #617 |
| `e.fmt.lzw` | existing | #614 |
| `e.fmt.markdown` | new | #346, #347 |
| `e.fmt.msgpack` | existing | #2089 |
| `e.fmt.opus` | new | #647 |
| `e.fmt.parquet` | new | #1660, #2096 |
| `e.fmt.pretty` | new | #341 |
| `e.fmt.protobuf` | existing | #2086 |
| `e.fmt.quoted_printable` | existing | #2054 |
| `e.fmt.semver` | new | #959, #2236 |
| `e.fmt.snappy` | new | #622 |
| `e.fmt.toml` | new | #2084 |
| `e.fmt.uri` | existing | #322, #972, #973 |
| `e.fmt.xml` | existing | #344, #345, #1435, #2080, #2081 |
| `e.fmt.yaml` | existing | #2083 |
| `e.fmt.zstd` | existing | #619 |
| `e.fs.mmap` | existing | #1623 |
| `e.game.ai` | existing | #443, #444, #445, #446, #448, #453, #454, #458, #1134, #1135, #1136, #1137 |
| `e.game.anim` | new | #1126, #1127, #1128, #1129 |
| `e.game.collide2d` | existing | #1125 |
| `e.game.grid` | existing | #126, #1839, #1844 |
| `e.game.nav` | new | #1130, #1131, #1132, #1133 |
| `e.game.physics` | new | #1030, #1119, #1120, #1122, #1123, #1124, #1737 |
| `e.game.procgen` | new | #1138, #1139, #1140, #1141 |
| `e.gfx.curve` | new | #553, #554, #555, #556 |
| `e.gfx.filter` | new | 20 entries, first #125 |
| `e.gfx.geometry` | existing | #2143, #2146 |
| `e.gfx.image` | existing | #640, #641, #642, #806, #807 |
| `e.gfx.mesh` | new | 18 entries, first #551 |
| `e.gfx.paint` | existing | #2139, #2140, #2141, #2142, #2144, #2145, #2147 |
| `e.gfx.raster` | new | #543, #544, #545 |
| `e.gfx.scene` | existing | 13 entries, first #1101 |
| `e.gfx.shade` | new | #1701 |
| `e.gfx.texture` | new | #644, #645 |
| `e.gfx.trace` | new | #1115, #1116, #1702, #2050 |
| `e.gfx.vision` | new | 13 entries, first #783 |
| `e.gpu` | existing | #19, #754 |
| `e.math` | existing | #828, #837 |
| `e.math.fft` | new (under `e.math`) | #489, #490, #495, #635, #636, #1864 |
| `e.math.filter` | new (under `e.math`) | #518, #519, #520, #1811, #1812, #1813 |
| `e.math.float` | new (under `e.math`) | #834, #835, #836 |
| `e.math.gf` | new (under `e.math`) | #833, #853 |
| `e.math.mc` | new (under `e.math`) | #1453, #1454 |
| `e.math.mcmc` | new (under `e.math`) | #1022, #1023, #1024, #1025 |
| `e.math.ntheory` | new (under `e.math`) | 21 entries, first #461 |
| `e.math.ode` | new (under `e.math`) | #1018, #1019, #1020, #1021, #1047 |
| `e.math.opt` | new (under `e.math`) | 14 entries, first #516 |
| `e.math.opt.meta` | new (split from `e.math.opt`) | #770, #771, #772, #773, #774, #779, #780 |
| `e.math.opt.convex` | new (split from `e.math.opt`) | #517, #1461 |
| `e.math.root` | new (under `e.math`) | #496, #497, #498, #499, #500 |
| `e.mem` | existing | #679, #680, #681, #682, #683 |
| `e.ml.ann` | new | #1096, #1226, #1227 |
| `e.ml.bayes` | new | #741 |
| `e.ml.cluster` | new | #639, #725, #726, #727, #728, #729, #730, #731, #1160, #2191, #2192 |
| `e.ml.hmm` | new | #1164, #1165, #1232 |
| `e.ml.knn` | new | #735 |
| `e.ml.linear` | new | #721, #722, #723, #724 |
| `e.ml.loss` | new | #759, #760, #1238, #1521 |
| `e.ml.nn` | new | #744, #745, #751, #752, #753 |
| `e.ml.optim` | new | #746, #747, #748, #749, #750, #1542, #2195 |
| `e.ml.reduce` | new | #732, #733, #2193, #2194 |
| `e.ml.rl` | new | #764, #765 |
| `e.ml.sample` | new | #755, #756, #757, #758, #1550 |
| `e.ml.svm` | new | #742, #743 |
| `e.ml.tree` | new | #736, #737, #738 |
| `e.net` | existing | #714, #952, #953, #1436 |
| `e.net.balance` | new (under `e.net`) | #712, #713, #1264 |
| `e.net.coap` | new (under `e.net`) | #1570 |
| `e.net.dns` | new (under `e.net`) | #1408, #1578 |
| `e.net.http` | existing | #1432, #1433, #1434 |
| `e.net.http.auth` | new (under `e.net.http`) | #1404, #1429 |
| `e.net.http3` | new (under `e.net`) | #1554 |
| `e.net.idna` | new (under `e.net`) | #2055 |
| `e.net.mqtt` | new (under `e.net`) | #1571 |
| `e.net.quic` | new (under `e.net`) | #1553 |
| `e.net.reliable` | new (under `e.net`) | #903, #904, #906, #907 |
| `e.net.stun` | new (under `e.net`) | #1561 |
| `e.net.tls` | existing | #1401 |
| `e.os` | existing | #1290, #1608, #1618, #1642 |
| `e.parse` | new | #328, #334, #335, #336, #337, #338, #339, #340, #342, #1537 |
| `e.parse.ll` | new | #329 |
| `e.parse.lr` | new | #330, #331, #332, #333 |
| `e.path` | existing | #354 |
| `e.ratelimit` | new | #705, #706, #707, #708, #709 |
| `e.resilience` | new | #710, #711, #715, #929, #2232, #2233, #2235 |
| `e.robot.kinematics` | new | #1814, #1815, #1816, #1817, #1818, #1819, #1820, #1822 |
| `e.robot.map` | new | #1843, #1845, #1846, #1847 |
| `e.robot.motion` | new | #1823, #1824, #1825, #1826, #1827, #1828, #1829, #1830, #1831, #1832, #1841 |
| `e.robot.plan` | new | #92, #93, #559, #560, #1833, #1834, #1835, #1836, #1837, #1838 |
| `e.simd` | existing | #1384 |
| `e.str` | existing | #355, #356, #357, #358 |
| `e.sync` | existing | #667, #668, #669, #672, #673, #1622 |
| `e.test.coverage` | existing | #2211, #2212, #2213 |
| `e.test.fuzz` | existing | #1444, #2203, #2204, #2205 |
| `e.test.linearize` | new (under `e.test`) | #2222 |
| `e.test.prop` | new (under `e.test`) | #2201, #2202 |
| `e.test.sim` | new (under `e.test`) | #2221 |
| `e.test.support` | existing | #2217, #2218, #2220, #2227 |
| `e.text.bidi` | new | #2065 |
| `e.text.casing` | new | #359, #363, #364 |
| `e.text.collab` | new | #1269, #2127, #2128 |
| `e.text.collate` | existing | #2066 |
| `e.text.diff` | new | #376, #377, #378, #974, #2242, #2244 |
| `e.text.distance` | new | #301, #302, #303, #304, #309, #379 |
| `e.text.encoding` | existing | #327, #2059, #2068, #2069 |
| `e.text.hyphen` | new | #2138 |
| `e.text.index` | new | #875, #876 |
| `e.text.layout` | existing | #365, #2108 |
| `e.text.metric` | new | #1235, #1236, #1247 |
| `e.text.normalize` | existing | #325 |
| `e.text.phonetic` | new | #312, #313, #314 |
| `e.text.rank` | new | #367, #368, #1224, #1225 |
| `e.text.regex` | existing | #348, #349, #350, #351, #353 |
| `e.text.search` | new | #291, #292, #293, #294, #295, #296, #297, #299 |
| `e.text.segment` | new | #2063, #2064 |
| `e.text.shape` | existing | #2135, #2136 |
| `e.text.stem` | new | #369, #370, #371, #380 |
| `e.text.suffix` | new | #207, #208, #209, #286, #300 |
| `e.text.tokenize` | new | #366, #373, #374, #375, #398, #1241 |
| `e.text.unicode` | existing | #326, #2061, #2062 |
| `e.text.utf8` | existing | #323, #324, #2057, #2058 |
| `e.text.wrap` | new | #360, #361, #362 |
| `e.thread` | existing | #1336 |
| `e.thread.pool` | new (under `e.thread`) | #657, #659, #660, #704, #1298 |
| `e.time` | existing | #961, #964 |
| `e.time.calendar` | existing | #962, #963 |
| `e.time.cron` | existing | #960 |
| `e.time.sync` | new (under `e.time`) | #149, #150, #151 |
| `e.trace` | new | #716, #1278 |
| `e.ui.accessibility` | existing | #2148, #2149 |
| `e.ui.app` | existing | #2129, #2130, #2131 |
| `e.ui.layout` | existing | #2107, #2109, #2110, #2111 |
| `e.ui.state` | new | #2121, #2122, #2124 |
| `e.ui.style` | existing | #2105 |
| `e.ui.undo` | new | #2125 |
| `e.ui.widget` | existing | #2116, #2117, #2119, #2132, #2133 |
| `e.ui.window` | existing | #2115 |
| `e.valid` | new | #948, #949, #950, #951 |
| `pacman` | tool | #1428, #2237, #2238 |

### Skipped by reason

| Reason | Entries |
|---|---|
| niche | 132 |
| compiler | 86 |
| model | 65 |
| kernel | 62 |
| hardware | 62 |
| internal | 50 |
| toy | 45 |
| finance | 40 |
| bio | 39 |
| product | 37 |
| research | 34 |
| protocol | 30 |
| system | 26 |
| technique | 24 |
| quantum | 24 |
| tooling | 22 |
| physics | 13 |
| nogc | 10 |
| legacy | 2 |
| offensive | 2 |


## 1. Sorting, Searching & Selection Algorithms (1–60)

1. **Quick Sort** – Partitioning array around a pivot recursively. → `e.algo.sort.quick`
2. **Merge Sort** – Divide-and-conquer stable sorting algorithm. → `e.algo.sort.merge`
3. **Heap Sort** – Binary heap-based comparison sort. → `e.algo.sort.heap`
4. **Bubble Sort** – Repeatedly swapping adjacent out-of-order elements. → skip: pedagogical only
5. **Insertion Sort** – Building sorted array one element at a time. → `e.algo.sort.insertion`
6. **Selection Sort** – In-place comparison search for minimum value. → skip: pedagogical only
7. **Counting Sort** – Non-comparison integer sorting by frequency keys. → `e.algo.sort.counting`
8. **Radix Sort** – Digit-by-digit positional integer sorting. → `e.algo.sort.radix_u32_in_place`
9. **Bucket Sort** – Distribution sort partitioning elements into buckets. → `e.algo.sort.bucket`
10. **Shell Sort** – In-place gap-based generalization of insertion sort. → `e.algo.sort.shell`
11. **Tim Sort** – Hybrid stable sort combining merge and insertion sort. → `e.algo.sort.stable_in_place`
12. **Comb Sort** – Improvement on bubble sort using variable gap sizes. → skip: pedagogical only
13. **Pigeonhole Sort** – Sorting where key count roughly equals element count. → see #7 (`e.algo.sort.counting`)
14. **Cycle Sort** – In-place unstable sort minimizing memory writes. → `e.algo.sort.cycle`
15. **Smoothsort** – Variation of heapsort using Leonardo numbers. → skip: implementable, but too specialised for the standard library
16. **Tournament Sort** – Tree-based selection sort using tournament trees. → skip: implementable, but too specialised for the standard library
17. **Cocktail Shaker Sort** – Bidirectional bubble sort. → skip: pedagogical only
18. **Gnome Sort** – Sorting by moving backward and forward like garden gnomes. → skip: pedagogical only
19. **Bitonic Sort** – Parallel sorting algorithm constructing bitonic sequences. → `e.gpu.sort_bitonic`
20. **Pancake Sort** – Sorting array using only prefix reversal operations. → skip: pedagogical only
21. **Bogo Sort** – Permuting array randomly until sorted (stochastic). → skip: pedagogical only
22. **Binary Search** – Divide-and-conquer search in sorted arrays. → `e.algo.search.binary`
23. **Linear Search** – Sequential element scan through collections. → `e.algo.search.linear`
24. **Interpolation Search** – Estimation-based search for uniformly distributed values. → `e.algo.search.interpolation`
25. **Exponential Search** – Bounded binary search for unbounded/infinite lists. → `e.algo.search.exponential`
26. **Fibonacci Search** – Search using Fibonacci numbers to divide ranges. → skip: implementable, but too specialised for the standard library
27. **Ternary Search** – Divide-and-conquer search dividing range into three parts. → `e.algo.search.ternary`
28. **Jump Search** – Block-based stepping search on sorted arrays. → skip: implementable, but too specialised for the standard library
29. **Sublist Search** – Checking if a linked list exists inside another list. → `e.data.linked.contains_sublist`
30. **Ubiquitous Binary Search** – Boundary-finding variant of binary search. → see #51 (`e.algo.search.lower_bound`)
31. **Fractional Cascading** – Speeding up consecutive binary searches across structures. → skip: implementable, but too specialised for the standard library
32. **Quickselect** – Selection algorithm to find k-th smallest element. → `e.algo.search.kth`
33. **Median of Medians** – Deterministic linear-time selection algorithm. → `e.algo.search.kth_deterministic`
34. **IntroSort** – Hybrid sort combining quicksort, heapsort, and insertion sort. → `e.algo.sort.in_place`
35. **Block Sort** – In-place merge sort running in O(1) extra memory. → skip: implementable, but too specialised for the standard library
36. **Library Sort** – Insertion sort with gaps to accelerate insertions. → skip: implementable, but too specialised for the standard library
37. **Strand Sort** – Sorting by repeatedly extracting sorted sub-lists. → skip: implementable, but too specialised for the standard library
38. **Patience Sorting** – Card-game inspired sort calculating longest increasing subsequences. → `e.algo.sort.patience`
39. **Tree Sort** – Inserting elements into a BST and reading in-order. → skip: pedagogical only
40. **Cascade Merge Sort** – External sorting algorithm for magnetic tape drives. → skip: implementable, but too specialised for the standard library
41. **Oscillating Merge Sort** – External sort using backward/forward tape reading. → skip: implementable, but too specialised for the standard library
42. **Polyphase Merge Sort** – Multi-way external merge sort minimizing tape runs. → `e.algo.sort.external_merge`
43. **American Flag Sort** – In-place radix sort for strings or integers. → `e.algo.sort.radix_bytes`
44. **Bead Sort (Gravity Sort)** – Natural sorting model simulating sliding beads. → skip: pedagogical only
45. **Flashsort** – Distribution sort estimating density distributions. → skip: implementable, but too specialised for the standard library
46. **Burstsort** – Fast string sorting using trie-based bucket structures. → `e.algo.sort.strings`
47. **Postman's Sort** – Hierarchical key sorting algorithm. → skip: implementable, but too specialised for the standard library
48. **Spreadsort** – Hybrid algorithm combining radix, bucket, and quicksort. → skip: implementable, but too specialised for the standard library
49. **Stooge Sort** – Recursive sorting algorithm with O(n2.71) complexity. → skip: pedagogical only
50. **Slowsort** – Multiply and surrender paradigm sorting. → skip: pedagogical only
51. **Binary Search Lower Bound** – Finding first element not less than target. → `e.algo.search.lower_bound`
52. **Binary Search Upper Bound** – Finding first element strictly greater than target. → `e.algo.search.upper_bound`
53. **Binary Search Equal Range** – Finding subrange matching given key. → `e.algo.search.equal_range`
54. **Saddleback Search** – Searching target in 2D sorted matrix. → `e.algo.search.matrix_sorted`
55. **Meta Binary Search** – One-pass binary search operating on binary bits. → skip: implementable, but too specialised for the standard library
56. **Galloping Search** – Searching sorted arrays with unknown lengths. → see #25 (`e.algo.search.exponential`)
57. **Shuffling (Fisher-Yates / Durstenfeld)** – Unbiased random array permutation. → `e.algo.rand.shuffle`
58. **Sattolo's Algorithm** – Generating cyclic permutations of array. → `e.algo.rand.cycle_permutation`
59. **Reservoir Sampling** – Randomly sampling k items from continuous stream. → `e.algo.rand.reservoir`
60. **Alias Method (Walker's)** – O(1) sampling from discrete probability distributions. → `e.algo.rand.alias_table`

## 2. Graph Algorithms & Network Analysis (61–180)

61. **Breadth-First Search (BFS)** – Layer-by-layer graph traversal. → `e.algo.graph.bfs`
62. **Depth-First Search (DFS)** – Deepest-path-first graph traversal. → `e.algo.graph.dfs`
63. **Dijkstra's Algorithm** – Single-source shortest path with non-negative weights. → `e.algo.graph.dijkstra`
64. **Bellman-Ford Algorithm** – Single-source shortest path handling negative weights. → `e.algo.graph.bellman_ford`
65. **A* Search Algorithm** – Heuristic-guided shortest path search. → `e.algo.graph.path.astar`
66. **Floyd-Warshall Algorithm** – All-pairs shortest paths via dynamic programming. → `e.algo.graph.floyd_warshall`
67. **Kruskal's Algorithm** – Minimum spanning tree using disjoint set union. → `e.algo.graph.mst_kruskal`
68. **Prim's Algorithm** – Minimum spanning tree via greedy vertex addition. → `e.algo.graph.mst_prim`
69. **Borůvka's Algorithm** – Parallel minimum spanning tree construction. → `e.algo.graph.mst_boruvka`
70. **Tarjan's SCC Algorithm** – Finding strongly connected components in O(V + E). → `e.algo.graph.strong_components`
71. **Kosaraju's Algorithm** – Two-pass DFS strongly connected components search. → see #70 (`e.algo.graph.strong_components`)
72. **Johnson's Algorithm** – All-pairs shortest path reweighting with Bellman-Ford. → `e.algo.graph.johnson`
73. **Kahn's Algorithm** – Topological sorting using vertex in-degrees. → `e.algo.graph.topological`
74. **Ford-Fulkerson Algorithm** – Augmenting-path method for maximum network flow. → see #75 (`e.algo.graph.flow.edmonds_karp`)
75. **Edmonds-Karp Algorithm** – BFS implementation of Ford-Fulkerson in O(V E²). → `e.algo.graph.flow.edmonds_karp`
76. **Dinic's Algorithm** – Level-graph blocking flow algorithm for max flow. → `e.algo.graph.flow.dinic`
77. **Push-Relabel Algorithm** – Preflow-push max flow algorithm with height labels. → `e.algo.graph.flow.push_relabel`
78. **Hopcroft-Karp Algorithm** – Maximum bipartite matching in O(E √V). → `e.algo.graph.match.hopcroft_karp`
79. **Hungarian Algorithm (Kuhn-Munkres)** – Solving the linear assignment problem. → `e.algo.graph.match.hungarian`
80. **Hierholzer's Algorithm** – Constructing Eulerian paths and circuits in O(E). → `e.algo.graph.euler_path`
81. **Fleury's Algorithm** – Finding Eulerian circuits by avoiding bridges. → skip: pedagogical only
82. **Bridge Finding Algorithm** – Finding critical edges whose removal disconnects graph. → `e.algo.graph.bridges`
83. **Articulation Points Algorithm** – Finding vertices whose removal disconnects graph. → `e.algo.graph.articulation_points`
84. **Lowest Common Ancestor (Binary Lifting)** – O(log N) tree LCA query. → `e.algo.graph.tree.lca_binary_lifting`
85. **Lowest Common Ancestor (Farach-Colton & Bender)** – O(1) query LCA via RMQ reduction. → `e.algo.graph.tree.lca_rmq`
86. **Heavy-Light Decomposition** – Decomposing trees into paths for segment tree queries. → `e.algo.graph.tree.heavy_light`
87. **Centroid Decomposition** – Divide-and-conquer tree decomposition around centroids. → `e.algo.graph.tree.centroid_decompose`
88. **Prüfer Sequence Encoding** – Converting labeled tree to unique sequence. → `e.algo.graph.tree.prufer_encode`
89. **Prüfer Sequence Decoding** – Reconstructing tree from Prüfer sequence. → `e.algo.graph.tree.prufer_decode`
90. **PageRank Algorithm** – Stationary distribution random-walk node importance. → `e.algo.graph.centrality.pagerank`
91. **HITS Algorithm** – Calculating Hub and Authority scores for network nodes. → `e.algo.graph.centrality.hits`
92. **D* Search Algorithm** – Incremental heuristic search for dynamic environments. → `e.robot.plan.dstar_lite`
93. **Lifelong Planning A* (LPA*)** – Incremental version of A* for changing graphs. → `e.robot.plan.lpa_star`
94. **Bidirectional Search** – Searching simultaneously from start and goal nodes. → `e.algo.graph.path.bidirectional`
95. **Iterative Deepening DFS (IDDFS)** – Depth-first search with bounded increasing depth. → `e.algo.graph.path.iddfs`
96. **Iterative Deepening A (IDA)** – Heuristic search combining IDDFS and A*. → `e.algo.graph.path.ida_star`
97. **Uniform Cost Search** – Dijkstra's variant finding optimal paths by path cost. → see #63 (`e.algo.graph.dijkstra`)
98. **Best-First Search** – Priority queue traversal using pure heuristic evaluations. → `e.algo.graph.path.best_first`
99. **Shortest Path Faster Algorithm (SPFA)** – Queue-optimized Bellman-Ford variant. → skip: implementable, but too specialised for the standard library
100. **Suurballe's Algorithm** – Finding pair of edge-disjoint paths with minimum total length. → `e.algo.graph.path.suurballe`
101. **Yen's Algorithm** – Finding K-shortest loopless paths in weighted graphs. → `e.algo.graph.path.yen_k_shortest`
102. **Gale-Shapley Algorithm** – Stable matching/marriage problem solution. → `e.algo.graph.match.stable_marriage`
103. **Blossom Algorithm (Edmonds')** – Maximum matching in general (non-bipartite) graphs. → `e.algo.graph.match.blossom`
104. **Bron-Kerbosch Algorithm** – Finding maximal cliques in undirected graphs. → `e.algo.graph.max_cliques`
105. **Girvan-Newman Algorithm** – Community detection removing high-betweenness edges. → `e.algo.graph.community.girvan_newman`
106. **Louvain Community Detection** – Modularity-maximization community extraction. → `e.algo.graph.community.louvain`
107. **Label Propagation Algorithm** – Community detection using network neighbor consensus. → `e.algo.graph.community.label_propagation`
108. **Karger's Algorithm** – Randomized min-cut algorithm via edge contractions. → `e.algo.graph.cut.karger`
109. **Karger-Stein Algorithm** – Fast recursive contraction min-cut algorithm. → skip: implementable, but too specialised for the standard library
110. **Stoer-Wagner Algorithm** – Deterministic global min-cut in undirected graphs. → `e.algo.graph.cut.stoer_wagner`
111. **Chandy-Misra-Haas Algorithm** – Distributed deadlock detection in resource networks. → `e.dist.deadlock.chandy_misra_haas`
112. **Maximum Cost Bipartite Matching** – Weighted assignment via min-cost max-flow. → see #79 (`e.algo.graph.match.hungarian`)
113. **Gabow's Matching Algorithm** – Degree-constrained maximum matching. → see #103 (`e.algo.graph.match.blossom`)
114. **Christofides Algorithm** – 3/2-approximation algorithm for Metric TSP. → `e.algo.combopt.tsp_christofides`
115. **Held-Karp Algorithm** – Dynamic programming exact solution for TSP. → `e.algo.combopt.tsp_held_karp`
116. **2-Opt Algorithm** – Local search heuristic untangling crossing edges in paths. → `e.algo.combopt.tsp_two_opt`
117. **3-Opt Algorithm** – Local search heuristic recombining 3 path segments. → `e.algo.combopt.tsp_three_opt`
118. **Lin-Kernighan Heuristic** – Variable k-opt edge swapping for TSP. → `e.algo.combopt.tsp_lin_kernighan`
119. **Boyer-Myrvold Planarity Test** – Linear-time check if graph is planar. → `e.algo.graph.iso.is_planar`
120. **VF2 Algorithm** – Subgraph isomorphism detection algorithm. → `e.algo.graph.iso.subgraph_vf2`
121. **Ullmann's Algorithm** – Backtracking search for subgraph isomorphism. → skip: implementable, but too specialised for the standard library
122. **Trémaux's Algorithm** – Maze routing using wall marking and backtracking. → skip: pedagogical only
123. **Pledge Algorithm** – Obstacle bypass navigation in unknown planar environments. → skip: implementable, but too specialised for the standard library
124. **Bug 1 / Bug 2 Algorithms** – Sensor-based robotic path planning around obstacles. → skip: implementable, but too specialised for the standard library
125. **Flood Fill Algorithm** – Multi-directional connected area labeling. → `e.gfx.filter.flood_fill`
126. **Lee's Algorithm** – Grid maze pathfinding using breadth-first search wave propagation. → `e.game.grid.path_bfs`
127. **Soukup's Algorithm** – Fast line-search pathfinding variant combining BFS and DFS. → skip: implementable, but too specialised for the standard library
128. **High-Low Watermark Algorithm** – Flow control queue threshold management. → `e.data.queue.watermarks`
129. **Dominator Tree Construction (Lengauer-Tarjan)** – Computing flow graph dominance. → skip: belongs in the Neper compiler, not the library
130. **Chord Protocol Lookup** – Distributed Hash Table (DHT) key routing. → `e.dist.dht.chord_lookup`
131. **Kademlia Routing Lookup** – XOR-metric based DHT lookup algorithm. → `e.dist.dht.kademlia_lookup`
132. **Pastry Routing Algorithm** – Prefix-based overlay network routing. → skip: implementable, but too specialised for the standard library
133. **Tapestry Routing Algorithm** – Mesh overlay network routing using Matched Prefixes. → skip: implementable, but too specialised for the standard library
134. **Raft Leader Election Algorithm** – Consensus-based leader selection in clusters. → `e.dist.consensus.raft_election`
135. **Paxos Consensus Algorithm** – Distributed agreement under unreliable networks. → `e.dist.consensus.paxos`
136. **Zab (ZooKeeper Atomic Broadcast)** – Crash-recovery atomic broadcast protocol algorithm. → skip: implementable, but too specialised for the standard library
137. **Byzantine Fault Tolerance (PBFT)** – Consensus reaching agreement with malicious nodes. → skip: implementable, but too specialised for the standard library
138. **Spanning Tree Protocol (STP / 802.1D)** – Loop prevention in Ethernet networks. → skip: network protocol beyond the library scope
139. **Distance Vector Routing (Bellman-Ford variant)** – Distributed router table calculation. → skip: network protocol beyond the library scope
140. **Link State Routing (Dijkstra variant)** – Router topology flooding and local shortest path. → skip: network protocol beyond the library scope
141. **BGP Path Vector Routing** – Inter-domain Internet routing path selection algorithm. → skip: network protocol beyond the library scope
142. **Gossip Protocol** – Epidemic peer-to-peer state dissemination. → `e.dist.gossip.disseminate`
143. **Bully Algorithm** – Distributed process leader election by rank. → `e.dist.election.bully`
144. **Ring Leader Election Algorithm** – Token-passing ring network election. → `e.dist.election.ring`
145. **Ricart-Agrawala Algorithm** – Distributed mutual exclusion via timestamped requests. → `e.dist.mutex.ricart_agrawala`
146. **Maekawa's Algorithm** – Quorum-based distributed mutual exclusion. → skip: implementable, but too specialised for the standard library
147. **Lamport's Logical Clocks** – Ordering events in distributed systems without physical clocks. → `e.dist.clock.lamport`
148. **Vector Clocks Algorithm** – Causality tracking across distributed nodes. → `e.dist.clock.vector`
149. **Marzullo's Algorithm** – Time synchronization combining overlapping noisy intervals. → `e.time.sync.marzullo`
150. **Berkeley Algorithm** – Internal physical clock synchronization for connected nodes. → `e.time.sync.berkeley`
151. **Cristian's Algorithm** – Time sync over client-server networks with unknown latency. → `e.time.sync.cristian`
152. **Chandy-Lamport Algorithm** – Distributed global snapshot recording without pausing. → `e.dist.snapshot.chandy_lamport`
153. **Raynal's Distributed Mutual Exclusion** – Request-based token pass mutual exclusion. → skip: implementable, but too specialised for the standard library
154. **Raymond's Tree-Based Algorithm** – Distributed mutual exclusion on token trees. → `e.dist.mutex.raymond_tree`
155. **Suzuki-Kasami Algorithm** – Token-based distributed mutual exclusion. → skip: implementable, but too specialised for the standard library
156. **Agrawal-El Abbadi Quorum Protocol** – Tree-structured quorum algorithm for fault tolerance. → skip: implementable, but too specialised for the standard library
157. **Gaffke's Minimum Spanning Tree** – Directed minimum spanning tree (Arborescence). → see #158 (`e.algo.graph.arborescence`)
158. **Edmonds' Branching Algorithm (Chu-Liu/Edmonds)** – Directed graph optimum arborescence. → `e.algo.graph.arborescence`
159. **Transitive Closure (Warshall's Algorithm)** – Reachability matrix computation. → `e.algo.graph.transitive_closure`
160. **Graph Coloring (Welsh-Powell)** – Greedy vertex coloring sorted by node degree. → `e.algo.graph.color.greedy`
161. **DSATUR Graph Coloring** – Vertex selection based on degree of saturation. → `e.algo.graph.color.dsatur`
162. **RLF (Recursive Largest First) Coloring** – Independent set construction graph coloring. → skip: implementable, but too specialised for the standard library
163. **Kempe Chains Algorithm** – Edge-swapping method used in planar graph coloring. → skip: implementable, but too specialised for the standard library
164. **Min-Max Flow Optimization** – Fair network bandwidth allocation. → `e.algo.graph.flow.max_min_fair`
165. **Max-Weight Bipartite Matching (Auction Algorithm)** – Distributed auction assignment. → `e.algo.graph.match.auction`
166. **Suurballe-Tarjan Shortest Path** – Fast two-disjoint-path routing. → see #100 (`e.algo.graph.path.suurballe`)
167. **Thorup's Algorithm** – O(V + E) single-source shortest paths on undirected graphs. → skip: research-grade, no settled practical implementation
168. **Dial's Algorithm** – Bucket-optimized Dijkstra for small integer weights. → `e.algo.graph.dial`
169. **Radix Heap Dijkstra** – Monotonic priority queue optimization for pathfinding. → `e.algo.graph.dijkstra_radix_heap`
170. **Shortest Path Tree Reconstruction** – Reconstructing actual path vectors from parents. → `e.algo.graph.path_to`
171. **Graph Center Finding Algorithm** – Vertex minimizing maximum distance to all nodes. → `e.algo.graph.center`
172. **Graph Periphery / Diameter Calculation** – Finding two most distant nodes in graph. → `e.algo.graph.diameter`
173. **Closeness Centrality Algorithm** – Reciprocal sum of shortest path distances to nodes. → `e.algo.graph.centrality.closeness`
174. **Betweenness Centrality (Brandes' Algorithm)** – Shortest-path vertex load calculation. → `e.algo.graph.centrality.betweenness`
175. **Eigenvector Centrality Algorithm** – Power-iteration node influence scoring. → `e.algo.graph.centrality.eigenvector`
176. **K-Core Decomposition Algorithm** – Subgraph extraction where all nodes have degree ≥ k. → `e.algo.graph.k_core`
177. **Truss Decomposition Algorithm** – Edge triangle-containment subnetwork extraction. → `e.algo.graph.k_truss`
178. **Triangle Counting (Forward Algorithm)** – Exact graph triangle enumeration. → `e.algo.graph.count_triangles`
179. **Min-Hash Graph Sparsification** – Preserving spectral properties while dropping edges. → skip: implementable, but too specialised for the standard library
180. **Stoer Min-Cut Phase Algorithm** – Repeated target-less min-cut contraction. → see #110 (`e.algo.graph.cut.stoer_wagner`)

## 3. Tree & Data Structure Operations (181–290)

181. **Binary Search Tree Insertion** – Placing items preserving left-smaller right-larger invariant. → `e.data.tree.put`
182. **Binary Search Tree Deletion** – Node removal handling 0, 1, or 2 children (inorder successor). → `e.data.tree.remove`
183. **AVL Tree Rotation (Left / Right)** – Single rotations rebalancing tree height. → skip: an implementation detail of an existing module, not an API
184. **AVL Tree Double Rotation (Left-Right / Right-Left)** – Dual rotation balancing skewed subtrees. → skip: an implementation detail of an existing module, not an API
185. **Red-Black Tree Insert Rebalancing** – Color flips and rotations preserving black-height. → skip: an implementation detail of an existing module, not an API
186. **Red-Black Tree Delete Rebalancing** – Handling double-black nodes using sibling transformations. → skip: an implementation detail of an existing module, not an API
187. **Splay Tree Splay Operation** – Zig, Zag, Zig-Zig, and Zig-Zag operations bringing node to root. → `e.data.splay.splay`
188. **Treap Split** – Splitting Treap into two trees based on key threshold. → `e.data.treap.split`
189. **Treap Merge** – Combining two Treaps matching priority invariants. → `e.data.treap.merge`
190. **Scapegoat Tree Rebuilding** – Rebalancing subtrees when balance alpha factor triggers. → skip: implementable, but too specialised for the standard library
191. **B-Tree Node Splitting** – Promoting median key upward when node exceeds capacity. → `e.data.btree.split_node`
192. **B-Tree Node Merging** – Combining underflow nodes during key deletion. → `e.data.btree.merge_node`
193. **B+ Tree Leaf Insertion** – Appending leaf items while updating parent range pointers. → `e.data.btree.insert`
194. **Fenwick Tree Point Update** – Adding value and propagating using LSB increment ( i += i & -i ). → `e.data.fenwick.add`
195. **Fenwick Tree Prefix Sum Query** – Accumulating range values using LSB decrement ( i -= i & -i ). → `e.data.fenwick.prefix_sum`
196. **Segment Tree Construction** – Building array-backed range-query tree in O(N). → `e.data.segment_tree.build`
197. **Segment Tree Range Query** – Aggregating sub-segments matching target interval. → `e.data.segment_tree.query`
198. **Segment Tree Lazy Propagation** – Deferred sub-tree updates for efficient range mutations. → `e.data.segment_tree.update_range`
199. **Persistent Segment Tree Modification** – Creating path-copy version history of tree states. → `e.data.segment_tree.persistent_update`
200. **Disjoint Set Union (DSU) Find** – Element root discovery using path compression. → `e.algo.disjoint_set.find`
201. **DSU Union by Rank / Size** – Merging smaller set root into larger set root. → `e.algo.disjoint_set.join` (`union` is a keyword)
202. **DSU Rollback** – Undoing tree unions using state history stacks. → `e.algo.disjoint_set.rollback`
203. **Trie Insertion** – Character-by-character child node path traversal. → `e.data.trie.insert`
204. **Trie Search** – Prefix or full-word node path validation. → `e.data.trie.get`
205. **Trie Deletion** – Unwinding unused child branches recursively. → `e.data.trie.remove`
206. **Compressed Trie (Radix/Patricia) Compact** – Merging single-child nodes to reduce depth. → `e.data.trie.compact`
207. **Suffix Tree Ukkonen's Algorithm** – Online linear-time suffix tree construction. → `e.text.suffix.tree_build`
208. **Suffix Array SA-IS Algorithm** – Linear-time induced sorting of suffix strings. → `e.text.suffix.array_build`
209. **Kasai's LCP Array Construction** – O(N) Longest Common Prefix calculation from suffix array. → `e.text.suffix.lcp_array`
210. **Cartesian Tree Construction** – Building heap-ordered tree from array in O(N). → `e.data.cartesian_tree.build`
211. **Link-Cut Tree Access Operation** – Preferred path updating in dynamic forest trees. → `e.data.link_cut.access`
212. **Link-Cut Tree Link / Cut** – Dynamic tree joining and detachment algorithms. → `e.data.link_cut.link`
213. **Euler Tour Technique** – Flattening tree into 1D array via entry/exit timestamps. → `e.algo.graph.tree.euler_tour`
214. **Tree Rebuilding from Traversal** – Reconstructing tree given Preorder and Inorder inputs. → `e.data.tree.from_traversals`
215. **AHU Tree Isomorphism Test** – Canonical string generation for unlabeled trees. → `e.algo.graph.tree.is_isomorphic`
216. **Van Emde Boas Tree Operations** – O(log log U) predecessor/successor searches. → skip: implementable, but too specialised for the standard library
217. **Dancing Links (Knuth's Algorithm X)** – Exact cover problem solver using sparse matrix links. → `e.algo.exact_cover.solve`
218. **BK-Tree Metric Distance Search** – String spell-checking via Levenshtein-distance tree traversal. → `e.data.bk_tree.search`
219. **Quadtree Insertion & Subdivision** – Splitting spatial node into 4 quadrants upon threshold. → `e.data.spatial.quadtree_insert`
220. **Octree Insertion & Subdivision** – Splitting 3D spatial node into 8 octants. → `e.data.spatial.octree_insert`
221. **KD-Tree Construction** – Splitting multidimensional points along alternating median axes. → `e.data.spatial.kd_build`
222. **KD-Tree Nearest Neighbor** – Hypersphere branch pruning range traversal. → `e.data.spatial.kd_nearest`
223. **R-Tree Spatial Insertion** – Bounding box expansion and minimal area node splitting. → `e.data.spatial.rtree_insert`
224. **Interval Tree Overlap Query** – Finding all intervals intersecting given range. → `e.data.spatial.interval_overlap`
225. **Wavelet Tree Quantile Query** – Finding k-th smallest value in subsegment in O(log Σ). → `e.data.succinct.wavelet_quantile`
226. **Skip List Insertion** – Probabilistic height assignment and multi-level forward linkage. → `e.data.skip_list.insert`
227. **Skip List Deletion** – Splice removal across indexed list layers. → `e.data.skip_list.remove`
228. **Binary Heap Sift-Up** – Moving parent element upward until min/max heap condition holds. → `e.data.heap.push`
229. **Binary Heap Sift-Down** – Moving node downward replacing smaller/larger child. → `e.data.heap.pop`
230. **Heapify (Floyd's Algorithm)** – Constructing array heap in linear O(N) time. → `e.data.heap.heapify`
231. **Fibonacci Heap Consolidate** – Linking equal-degree trees during minimum extraction. → skip: implementable, but too specialised for the standard library
232. **Binomial Heap Union** – Merging binomial trees of equal order. → `e.data.heap.binomial_merge`
233. **Pairing Heap Decrease-Key** – Two-pass tree merging priority queue operations. → `e.data.heap.pairing_decrease_key`
234. **Leftist Heap Merge** – Recursive structural combination maintaining null path length. → `e.data.heap.leftist_merge`
235. **Skew Heap Merge** – Self-adjusting heap merging unconditionally swapping subtrees. → `e.data.heap.skew_merge`
236. **Min-Max Heap Operations** – Single array structure supporting O(1) Min and Max extraction. → `e.data.heap.min_max`
237. **Bloom Filter Insertion** – Setting bits across k independent hash functions. → `e.algo.sketch.bloom_insert`
238. **Bloom Filter Membership Test** – Bitwise AND evaluation checking bit locations. → `e.algo.sketch.bloom_contains`
239. **Counting Bloom Filter Deletion** – Decrementing location counters instead of single bits. → `e.algo.sketch.counting_bloom_remove`
240. **Cuckoo Filter Insertion** – Kicking out existing keys to alternate hash locations. → `e.algo.sketch.cuckoo_insert`
241. **Quotient Filter Operations** – In-cache compact hashtable using fingerprint quotients. → `e.algo.sketch.quotient_filter`
242. **HyperLogLog Cardinality Estimation** – Estimating unique items using leading zero counts. → `e.algo.sketch.hll_estimate`
243. **Count-Min Sketch Update** – Adding item count across parallel frequency arrays. → `e.algo.sketch.count_min_add`
244. **Count-Min Sketch Query** – Extracting minimum value among hashed bucket locations. → `e.algo.sketch.count_min_estimate`
245. **Heavy Hitters Algorithm (Misra-Gries)** – Tracking top-k frequent stream items. → `e.algo.sketch.misra_gries`
246. **Space-Saving Algorithm** – Stream frequency estimation with bounded error. → `e.algo.sketch.space_saving`
247. **Hash Table Open Addressing (Linear Probing)** – Resolving collisions via step sequential scans. → skip: an implementation detail of an existing module, not an API
248. **Hash Table Quadratic Probing** – Collision resolution using quadratic step function. → skip: an implementation detail of an existing module, not an API
249. **Hash Table Double Hashing** – Using second hash output as secondary probe step size. → skip: an implementation detail of an existing module, not an API
250. **Robin Hood Hashing** – Stealing from rich keys to equalize probe sequence length. → skip: an implementation detail of an existing module, not an API
251. **Hopscotch Hashing** – Moving items within bounded neighborhood windows. → skip: an implementation detail of an existing module, not an API
252. **2-Choice Hashing** – Inserting item into shorter of two alternate hash buckets. → skip: an implementation detail of an existing module, not an API
253. **Cuckoo Hashing Lookup** – O(1) guaranteed lookup across dual hash tables. → skip: an implementation detail of an existing module, not an API
254. **Dynamic Resizing / Rehashing** – Allocating doubled array size and redistributing entries. → skip: an implementation detail of an existing module, not an API
255. **Consistent Hashing (Ring Topology)** – Distributing keys across nodes using hash ring slots. → `e.algo.consistent_hash.ring_lookup`
256. **Rendezvous Hashing (Highest Random Weight)** – Independent node selection for key replication. → `e.algo.consistent_hash.rendezvous`
257. **Locality-Sensitive Hashing (LSH)** – Hashing items so similar vectors map to same buckets. → `e.algo.sketch.lsh_bucket`
258. **MinHash Calculation** – Estimating Jaccard similarity between set items. → `e.algo.sketch.minhash`
259. **SimHash Algorithm** – Dimensionality reduction mapping text features to bitwise distance. → `e.algo.sketch.simhash`
260. **Doubly Linked List Node Splice** – Modifying 4 pointer links to insert/extract sequence. → `e.data.linked.splice`
261. **XOR Linked List Traversal** – Using pointer XOR combinations to traverse bidirectionally. → skip: pedagogical only
262. **Unrolled Linked List Search** – Array-node hybrid traversal for cache optimization. → skip: implementable, but too specialised for the standard library
263. **Self-Organizing List (Move-To-Front)** – Relocating accessed node directly to head. → `e.data.linked.move_to_front`
264. **Self-Organizing List (Transpose)** – Swapping accessed node with its immediate predecessor. → skip: implementable, but too specialised for the standard library
265. **Ring Buffer Enqueue/Dequeue** – Circular array head/tail pointer increment modulo size. → `e.data.ring.push`
266. **Monotonic Stack Construction** – Maintaining strictly increasing/decreasing element stack. → `e.algo.dp.monotonic_stack`
267. **Monotonic Queue Slide Window** – Maintaining min/max elements in sliding temporal window. → `e.data.window.monotonic_queue`
268. **LRU Cache Eviction** – Moving accessed keys in Doubly Linked List while popping tail. → `e.data.cache.lru`
269. **LFU Cache Eviction** – Frequency-bucketed doubly linked lists for access count removal. → `e.data.cache.lfu`
270. **ARC (Adaptive Replacement Cache)** – Balancing LRU and LFU dynamically based on hits. → `e.data.cache.arc`
271. **Clock (Second Chance) Eviction** – Array loop checking usage bits prior to page selection. → `e.data.cache.clock`
272. **FIFO Cache Eviction** – Queue-based first-in first-out element replacement. → `e.data.cache.fifo`
273. **2Q Cache Eviction** – Multi-queue caching separating single access from frequent items. → `e.data.cache.two_queue`
274. **SLRU (Segmented LRU)** – Protected and probationary cache buffer management. → `e.data.cache.slru`
275. **Tree Centroid Finding** – Single pass DFS counting subtree sizes to find balance point. → see #87 (`e.algo.graph.tree.centroid_decompose`)
276. **Heavy-Light Path Query** – Combining segment tree queries over light and heavy paths. → see #86 (`e.algo.graph.tree.heavy_light`)
277. **Treap Implicit Key Split** – Splitting random search tree by sub-tree node count. → `e.data.treap.split_at`
278. **Splay Tree Range Reverse** – Tagging Lazy propagation lazy flag to invert tree children. → `e.data.splay.reverse_range`
279. **Sparse Table Construction** – Precomputing static Range Minimum Queries in O(N log N). → `e.data.sparse_table.build`
280. **Sparse Table RMQ Lookup** – O(1) query combining overlapping power-of-two blocks. → `e.data.sparse_table.query`
281. **Disjoint Sparse Table** – Range queries on non-idempotent operations in O(1). → `e.data.sparse_table.disjoint_query`
282. **Block Decomposition (Sqrt Decomposition)** – Partitioning N items into N blocks. → skip: a technique applied per problem, not a reusable function
283. **Mo's Algorithm** – Offline query ordering by block boundaries to reduce pointer moves. → `e.algo.query.mo_order`
284. **Mo's Algorithm with Updates** – 3D query sorting incorporating time dimension. → skip: implementable, but too specialised for the standard library
285. **Mo's Algorithm on Trees** – Flattening tree via Euler Tour to process path queries offline. → skip: implementable, but too specialised for the standard library
286. **Suffix Automaton Construction** – Directed acyclic word graph minimal string acceptor. → `e.text.suffix.automaton_build`
287. **Directed Acyclic Word Graph (DAWG)** – Memory-efficient deterministic finite state automaton. → see #286 (`e.text.suffix.automaton_build`)
288. **Rope Insert / Concatenate** – Binary tree-backed long string editing and splicing. → `e.data.rope.insert`
289. **Zipper Data Structure Movement** – Functional cursor movement over nested structures. → skip: a technique applied per problem, not a reusable function
290. **Finger Tree Operations** – Deque structure supporting O(1) access at boundaries. → skip: implementable, but too specialised for the standard library

## 4. String Processing, Parsing & Text Formatting (291–380)

291. **Knuth-Morris-Pratt (KMP)** – String pattern matching using prefix function failure tables. → `e.text.search.kmp`
292. **Boyer-Moore Search** – Text search skipping alignments via bad character and good suffix rules. → `e.text.search.boyer_moore`
293. **Boyer-Moore-Horspool** – Simplified Boyer-Moore variant using bad-character rules. → `e.text.search.horspool`
294. **Rabin-Karp Algorithm** – Rolling hash string pattern search across text windows. → `e.text.search.rabin_karp`
295. **Aho-Corasick Algorithm** – Trie-based automaton for fast multi-pattern dictionary search. → `e.text.search.aho_corasick`
296. **Z-Algorithm** – Linear time computation of longest prefix-matching substrings. → `e.text.search.z_array`
297. **Manacher's Algorithm** – Linear time discovery of longest palindromic substrings. → `e.text.search.longest_palindrome`
298. **Commentz-Walter Algorithm** – Hybrid combining Boyer-Moore and Aho-Corasick multi-string search. → skip: implementable, but too specialised for the standard library
299. **Baeza-Yates-Gonnet (Bitap / Shift-Or)** – Bitwise string matching algorithm handling fuzzy searches. → `e.text.search.bitap`
300. **Suffix Array Binary Search** – Searching text patterns in O(M log N) via sorted suffix indices. → `e.text.suffix.array_search`
301. **Levenshtein Distance** – Dynamic programming metric for minimum single-character edits. → `e.text.distance.levenshtein`
302. **Damerau-Levenshtein Distance** – Edit distance accounting for insertions, deletions, substitutions, and transpositions. → `e.text.distance.damerau_levenshtein`
303. **Jaro-Winkler Distance** – String similarity metric weighting prefix matches higher. → `e.text.distance.jaro_winkler`
304. **Hamming Distance** – Bitwise or character positional difference count between equal-length strings. → `e.text.distance.hamming`
305. **Needleman-Wunsch Algorithm** – Global alignment dynamic programming for biological or text sequences. → `e.algo.align.global`
306. **Smith-Waterman Algorithm** – Local sequence alignment optimization for string sequence matching. → `e.algo.align.local`
307. **Hirschberg's Algorithm** – Space-efficient linear memory sequence alignment using divide-and-conquer. → `e.algo.align.global_linear_space`
308. **Longest Common Subsequence (LCS)** – Finding the maximum length order-preserving shared sub-sequence. → `e.algo.dp.lcs`
309. **Longest Common Substring** – Extracting the maximum length contiguous shared character sequence. → `e.text.distance.longest_common_substring`
310. **Longest Palindromic Subsequence** – Dynamic programming identification of internal palindromic sub-sequences. → `e.algo.dp.longest_palindromic_subsequence`
311. **Shortest Common Supersequence** – Finding the smallest string containing all input sequences as subsequences. → `e.algo.dp.shortest_common_supersequence`
312. **Soundex Algorithm** – Phonetic indexing algorithm encoding words by sound as pronounced in English. → `e.text.phonetic.soundex`
313. **Metaphone / Double Metaphone** – Phonetic algorithms encoding words into sound keys for fuzzy matching. → `e.text.phonetic.metaphone`
314. **NYSIIS Algorithm** – Phonetic coding system improving on Soundex for surname matching. → `e.text.phonetic.nysiis`
315. **Caesar Cipher Shift** – Simple substitution mapping by rotating characters by fixed distances. → `e.crypto.classic.caesar`
316. **Vigenère Cipher** – Polyalphabetic substitution using repeating keyword shift offsets. → `e.crypto.classic.vigenere`
317. **Atbash Cipher** – Substitution cipher mapping alphabet characters to their exact reversed position (A → Z). → `e.crypto.classic.atbash`
318. **ROT13 Substitution** – Alphabetical substitution rotating characters by 13 positions. → `e.crypto.classic.rot13`
319. **Run-Length Encoding (RLE)** – Lossless compression mapping adjacent duplicate characters to counts. → `e.algo.coding.rle_encode`
320. **Base64 Encoding** – Translating binary streams into 64 ASCII printable characters. → `e.bytes.base64_encode`
321. **Base85 / Ascii85 Encoding** – High-density string encoding mapping 4-byte sequences into 5 characters. → `e.bytes.base85_encode`
322. **URL Percent Encoding** – Converting non-ASCII and reserved symbols into %XX hex codes. → `e.fmt.uri.percent_encode`
323. **UTF-8 Byte Encoder/Decoder** – Variable-length multi-byte character mapping for Unicode codepoints. → `e.text.utf8.encode`
324. **UTF-16 Surrogate Pair Resolver** – Converting extended Unicode codepoint values into 16-bit code units. → `e.text.utf8.decode_utf16`
325. **Unicode Normalization (NFD/NFC/NFKD/NFKC)** – Canonical and compatibility character decomposition/composition. → `e.text.normalize.normalize`
326. **TR31 Identifier Validation** – Unicode standard rules verifying valid language variable names. → `e.text.unicode.is_identifier`
327. **Byte Order Mark (BOM) Detector** – Inspecting stream lead bytes to identify text file encoding format. → `e.text.encoding.detect_bom`
328. **Recursive Descent Parsing** – Top-down LL parser execution using mutually recursive functions. → `e.parse.recursive_descent`
329. **LL(1) Parser Table Generator** – Calculating FIRST and FOLLOW sets for context-free grammar rules. → `e.parse.ll.table`
330. **LR(0) Item Set Generation** – Building shift-reduce parser state graphs via item closure. → `e.parse.lr.items`
331. **SLR(1) Parsing Table Builder** – Simple LR parser generator using FOLLOW sets for conflict resolution. → `e.parse.lr.slr_table`
332. **LALR(1) Parsing Table Construction** – Look-ahead LR parser state merging to reduce table size. → `e.parse.lr.lalr_table`
333. **Canonical LR(1) Parser Construction** – Full look-ahead context-free grammar parsing table builder. → `e.parse.lr.canonical_table`
334. **CYK Algorithm (Cocke-Younger-Kasami)** – O(N3) parsing for grammars in Chomsky Normal Form. → `e.parse.cyk`
335. **Earley Parser** – Chart parsing algorithm handling arbitrary context-free grammars. → `e.parse.earley`
336. **Shunting-Yard Algorithm** – Converting infix expressions into Reverse Polish Notation (RPN). → `e.parse.shunting_yard`
337. **Abstract Syntax Tree (AST) Builder** – Constructing hierarchical tree nodes from parser token streams. → `e.parse.ast`
338. **Lexical Tokenizer Scan** – Regular expression scanner yielding typed atomic grammar tokens. → `e.parse.lex`
339. **Packrat Parsing (PEG)** – Linear-time parsing of Parsing Expression Grammars via memoization. → `e.parse.peg`
340. **Pratt Parser (Top-Down Operator Precedence)** – Parsing expressions using operator binding powers. → `e.parse.pratt`
341. **Pretty Printing Layout Algorithm** – Formatting AST structures into neatly indented text representations. → `e.fmt.pretty.layout`
342. **Indentation Level Tracking** – Off-side rule parser managing block scoping via indentation stacks. → `e.parse.lex_indent`
343. **JSON Parser State Machine** – Streaming character validation and parsing for key-value structures. → `e.fmt.json.parse`
344. **XML SAX Event Streaming** – Memory-efficient push parsing emitting element start/end callbacks. → `e.fmt.xml.stream`
345. **XML DOM Tree Construction** – Building complete in-memory hierarchical document trees. → `e.fmt.xml.parse`
346. **Markdown Block Parsing** – Line-oriented structural scanner classifying blocks, headers, and lists. → `e.fmt.markdown.parse_blocks`
347. **Markdown Inline Parsing** – Delimiter-matching engine for inline emphasis, code, and links. → `e.fmt.markdown.parse_inlines`
348. **Thompson's NFA Construction** – Building non-deterministic finite automata from regular expressions. → `e.text.regex.nfa_compile`
349. **Powerset Construction (NFA to DFA)** – Converting non-deterministic state machines to deterministic ones. → `e.text.regex.dfa_from_nfa`
350. **Hopcroft's DFA Minimization** – Merging equivalent state sets to construct minimal DFAs. → `e.text.regex.dfa_minimize`
351. **DFA Execution** – Fast single-pass text validation using state transition matrices. → `e.text.regex.dfa_run`
352. **Backtracking Regex Engine** – Recursive matching strategy supporting captures and backreferences. → skip: implementable, but too specialised for the standard library
353. **Pike Vectorized NFA Regex** – Parallel state set tracking preventing catastrophic backtracking. → `e.text.regex.pike_vm`
354. **Wildcard Pattern Matching** – Evaluating wildcard strings containing ? and * symbols. → `e.path.glob_match`
355. **String Trimming (LTRIM/RTRIM)** – Stripping leading and trailing whitespace characters. → `e.str.trim`
356. **String Padding** – Prepending or appending fill characters to meet target field widths. → `e.str.pad`
357. **String Splitting** – Tokenizing strings using multi-character delimiter bounds. → `e.str.split`
358. **String Joining / Interpolation** – Concatenating array elements with central glue strings. → `e.str.join`
359. **Naming Convention Converter** – Transforming strings between camelCase, snake_case, and PascalCase. → `e.text.casing.convert`
360. **Knuth's Word Wrap Algorithm** – Dynamic programming line-breaking minimizing line raggedness. → `e.text.wrap.optimal`
361. **Greedy Line Wrapping** – Breaking text lines immediately upon exceeding maximum column width. → `e.text.wrap.greedy`
362. **Justified Text Alignment** – Distributing inter-word whitespace evenly to align both margins. → `e.text.wrap.justify`
363. **Slugification** – Normalizing raw text into lowercase, clean, hyphenated URL-safe strings. → `e.text.casing.slug`
364. **Title Case Normalization** – Capitalizing principal words following linguistic style guides. → `e.text.casing.title`
365. **Truncation with Ellipsis** – Shortening text to fixed length while appending ellipsis cleanly. → `e.text.layout.ellipsis`
366. **K-Shingle Tokenization** – Breaking text documents into sets of k adjacent character/word slices. → `e.text.tokenize.shingles`
367. **TF-IDF Calculation** – Scoring term frequency against inverse document frequency in information retrieval. → `e.text.rank.tf_idf`
368. **BM25 Ranking Algorithm** – Probabilistic relevance framework for document searching. → `e.text.rank.bm25`
369. **Porter Stemming Algorithm** – Rule-based suffix stripping engine reducing English words to roots. → `e.text.stem.porter`
370. **Lancaster Stemmer** – Aggressive rule-driven word stemmer stripping suffixes iteratively. → `e.text.stem.lancaster`
371. **Snowball Framework** – Language-neutral domain language for specifying stemming algorithms. → `e.text.stem.snowball`
372. **Lemmatization (WordNet Lookup)** – Mapping inflected words to true dictionary canonical lemmas. → skip: a trained ML model or training recipe
373. **Byte-Pair Encoding (BPE)** – Subword tokenization merging frequent character pairs. → `e.text.tokenize.bpe`
374. **WordPiece Tokenizer** – Subword segmentation maximizing vocabulary likelihood. → `e.text.tokenize.wordpiece`
375. **Unigram Subword Tokenization** – Probabilistic subword extraction using vocabulary pruning. → `e.text.tokenize.unigram`
376. **Myers Diff Algorithm** – Finding minimal edit scripts and differences between two files. → `e.text.diff.myers`
377. **Patience Diff** – Human-readable line diffing focusing on unique matching lines. → `e.text.diff.patience`
378. **3-Way Text Merge** – Merging two divergent text revisions using their common base ancestor. → `e.text.diff.merge3`
379. **Trigram Fuzzy Matching** – Substring similarity calculation using character 3-gram overlapping sets. → `e.text.distance.trigram`
380. **Affix Stripping Parsing** – Analyzing complex compound words down to structural roots. → `e.text.stem.strip_affixes`

## 5. Dynamic Programming, Greedy & Backtracking Algorithms (381–460)

381. **0/1 Knapsack Problem** – DP selection of item subsets maximizing value under weight limits. → `e.algo.dp.knapsack`
382. **Fractional Knapsack Problem** – Greedy selection prioritizing value-to-weight ratios. → `e.algo.dp.knapsack_fractional`
383. **Unbounded Knapsack Problem** – DP allocation allowing infinite copies of each available item. → `e.algo.dp.knapsack_unbounded`
384. **Fibonacci Top-Down DP** – Memoized recursive computation of Fibonacci numbers. → skip: pedagogical only
385. **Fibonacci Bottom-Up DP** – Tabulated iterative array calculation for O(N) Fibonacci output. → skip: pedagogical only
386. **Longest Increasing Subsequence (LIS)** – O(N log N) patience-sorting approach for increasing subsequences. → `e.algo.dp.lis`
387. **Coin Change (Min Coins)** – DP calculation determining fewest coins needed for target values. → `e.algo.dp.coin_change_min`
388. **Coin Change (Total Ways)** – Counting all combinations of coins that sum to target amounts. → `e.algo.dp.coin_change_ways`
389. **Rod Cutting Problem** – Optimizing rod cuts to maximize cumulative piece selling values. → see #383 (`e.algo.dp.knapsack_unbounded`)
390. **Matrix Chain Multiplication** – DP finding optimal parenthesization minimizing matrix product ops. → `e.algo.dp.matrix_chain`
391. **Partition Equal Subset Sum** – Subproblem check verifying if array splits into equal-sum halves. → see #392 (`e.algo.dp.subset_sum`)
392. **Subset Sum Problem** – Determining if any combination of numbers sums exactly to target S. → `e.algo.dp.subset_sum`
393. **Kadane's Algorithm** – Linear time scan discovering maximum contiguous sum subarrays. → `e.algo.dp.max_subarray`
394. **Maximum Product Subarray** – Dual DP tracking minimum and maximum contiguous products. → `e.algo.dp.max_product_subarray`
395. **Box Stacking Problem** – Dynamic programming stacking 3D boxes to achieve maximum height. → skip: pedagogical only
396. **Egg Dropping Puzzle** – Minimizing worst-case test drops needed to identify breaking floors. → skip: pedagogical only
397. **Optimal Binary Search Tree** – Constructing search trees minimizing average search costs based on access frequencies. → `e.algo.dp.optimal_bst`
398. **Word Break Problem** – DP verification determining if strings can be segmented into valid dictionary words. → `e.text.tokenize.word_break`
399. **Palindromic Partitioning** – Computing minimal cuts needed to divide strings into palindromes. → skip: pedagogical only
400. **House Robber Problem** – Maximizing non-adjacent element selection along arrays or trees. → skip: pedagogical only
401. **Decode Ways** – Counting possible character decodings for continuous numeric strings. → skip: pedagogical only
402. **Interleaving String Verification** – DP check confirming if two strings weave together into a third string. → skip: pedagogical only
403. **Trapping Rain Water** – Calculating trapped surface liquid volumes between elevation bars. → skip: pedagogical only
404. **Largest Rectangle in Histogram** – Stack-driven linear time computation of maximum bar area. → `e.algo.dp.largest_rectangle_histogram`
405. **Maximal Rectangle in Binary Matrix** – Row-by-row reduction translating 2D grids to histogram max areas. → `e.gfx.filter.max_rectangle`
406. **Activity Selection Problem** – Greedy task scheduling maximizing non-overlapping time intervals. → `e.algo.schedule.activity_selection`
407. **Job Sequencing with Deadlines** – Greedy assignment using disjoint sets to maximize scheduling profit. → `e.algo.schedule.jobs_with_deadlines`
408. **Interval Scheduling Maximization** – Sorting interval finish times to maximize processed tasks. → see #406 (`e.algo.schedule.activity_selection`)
409. **Interval Covering Problem** – Finding the smallest set of points required to touch all intervals. → `e.algo.schedule.interval_cover`
410. **Minimum Refueling Stops** – Max-heap tracking reachable gas station fuel capacities. → skip: pedagogical only
411. **Gas Station Circuit (Petroleum Route)** – Greedy starting index validation for complete circular routes. → skip: pedagogical only
412. **Candy Distribution Problem** – Two-pass array sweep satisfying local rating constraints with minimal costs. → skip: pedagogical only
413. **Task Scheduler** – Arranging task queues around cooldown intervals to minimize CPU idle slots. → `e.algo.schedule.cooldown`
414. **Huffman Coding Tree Generation** – Priority-queue greedy merging for optimal prefix coding trees. → `e.algo.coding.huffman_build`
415. **Greedy Set Cover (Chvátal's)** – Logarithmic approximation choosing sets with maximum unvisited elements. → `e.algo.combopt.set_cover_greedy`
416. **N-Queens Problem** – Backtracking search placing N non-attacking queens on an N × N chessboard. → skip: pedagogical only
417. **Sudoku Solver** – Backtracking grid search integrated with constraint propagation. → `e.algo.exact_cover.sudoku`
418. **Knight's Tour Problem** – Warnsdorff's heuristic guiding knights to visit every board square once. → skip: pedagogical only
419. **Hamiltonian Path Backtracking** – Depth-first search looking for paths visiting all graph vertices once. → skip: pedagogical only
420. **Subset Generation (Power Set)** – Iterative or recursive bitmask expansion building all sub-combinations. → `e.algo.combin.subsets`
421. **Heap's Algorithm** – Generating all N! permutations of an array using single element swaps. → `e.algo.combin.permutations`
422. **Lexicographic Permutations** – Finding next permutations via pivot discovery and suffix inversion. → `e.algo.combin.next_permutation`
423. **Gosper's Hack** – Bitwise loop generating all k-element subset bitmasks efficiently. → `e.algo.combin.next_subset_same_popcount`
424. **Crossword Puzzle Solver** – Backtracking word placement across intersecting grid slots. → skip: pedagogical only
425. **Rat in a Maze** – Multi-directional recursive grid pathfinding with backtracking. → skip: pedagogical only
426. **Word Search in Grid (DFS + Trie)** – Grid character search guided by Trie prefix lookups. → skip: pedagogical only
427. **K-Equal Sum Subsets Partition** – Recursive subset construction with state memoization. → skip: pedagogical only
428. **Target Sum Expression Solver** – Evaluating binary sign variations over sequence values. → skip: pedagogical only
429. **Graham Scan (Convex Hull)** – O(N log N) polar angle sorting identifying 2D convex boundary points. → `e.algo.geom.hull_graham`
430. **Jarvis March / Gift Wrapping** – Convex hull generation wrapping around outer perimeter points. → `e.algo.geom.hull_jarvis`
431. **Monotone Chain Hull Algorithm** – Sorting 2D points to construct upper and lower convex hulls. → `e.algo.geom.hull`
432. **Quickhull** – Divide-and-conquer convex hull determination using furthest points from lines. → `e.algo.geom.hull_quick`
433. **Convex Hull Trick (CHT)** – DP optimization technique evaluating envelope lines in O(1) or O(log N). → `e.algo.dp.convex_hull_trick`
434. **Li Chao Tree** – Segment tree structure maintaining set of linear functions over ranges. → `e.algo.dp.li_chao_tree`
435. **Divide and Conquer DP Optimization** – Accelerating dynamic programming when cost functions meet Quadrangle Inequality. → skip: a technique applied per problem, not a reusable function
436. **Knuth's DP Optimization** – Speeding up range DP when split indices are monotonic. → skip: a technique applied per problem, not a reusable function
437. **Digit DP** – Dynamic programming counting numbers under bounds satisfying specific digit rules. → skip: a technique applied per problem, not a reusable function
438. **Bitmask DP** – Memoizing subproblems by encoding state flags into binary integers. → skip: a technique applied per problem, not a reusable function
439. **Sum Over Subsets (SOS DP)** – Efficiently computing aggregate functions across all subset bitmasks in O(N2N). → `e.algo.combin.subset_sums`
440. **Rerooting Tree DP** – Two-pass DFS collecting results for every node treated as tree root. → skip: a technique applied per problem, not a reusable function
441. **Broken Profile DP (Plug DP)** – Grid DP maintaining boundaries across cell-by-cell state contours. → skip: a technique applied per problem, not a reusable function
442. **Automata-Based DP** – Counting string states by modeling transitions with matrix exponentiation. → skip: a technique applied per problem, not a reusable function
443. **Minimax Algorithm** – Decision tree evaluation minimizing maximum potential losses in zero-sum games. → `e.game.ai.minimax`
444. **Alpha-Beta Pruning** – Optimizing minimax search by discarding non-viable decision branches. → `e.game.ai.alpha_beta`
445. **Monte Carlo Tree Search (MCTS)** – Heuristic game tree exploration using Selection, Expansion, Simulation, and Backpropagation. → `e.game.ai.mcts`
446. **Expectimax Search** – Game tree traversal accounting for chance probabilistic nodes. → `e.game.ai.expectimax`
447. **Negamax Variant** – Compact implementation of minimax relying on zero-sum property symmetries. → see #444 (`e.game.ai.alpha_beta`)
448. **Principal Variation Search (PVS)** – NegaScout variant evaluating primary move paths with narrow search bounds. → `e.game.ai.pvs`
449. **Proof-Number Search** – Game tree search targeting proving or disproving tree connectivity goals. → skip: implementable, but too specialised for the standard library
450. **Retrograde Analysis** – Solving endgame positions by working backward from known terminal states. → skip: implementable, but too specialised for the standard library
451. **SSS Algorithm*** – Game tree search using state-space search with best-first heuristic evaluation. → skip: implementable, but too specialised for the standard library
452. **B Tree Search*** – Best-first search evaluating intervals of optimistic and pessimistic leaf bounds. → skip: implementable, but too specialised for the standard library
453. **Iterative Deepening Negamax** – Progressive search depth expansion combining transposition tables. → `e.game.ai.iterative_deepening`
454. **Transposition Table Lookup** – Hash-based caching of analyzed game tree positions and evaluations. → `e.game.ai.transposition_table`
455. **Zobrist Hashing** – Fast XOR-based hash computation for board game positions. → `e.algo.hash.zobrist`
456. **Null-Move Pruning** – Passing turns in game trees to verify positional advantage safety. → skip: an implementation detail of an existing module, not an API
457. **Late Move Reductions (LMR)** – Reducing search depth for moves ordered later in candidate lists. → skip: an implementation detail of an existing module, not an API
458. **Quiescence Search** – Extending search depth at tactical positions until board states stabilize. → `e.game.ai.quiescence`
459. **Killer Heuristic** – Prioritizing non-capturing moves that previously caused beta cutoffs. → skip: an implementation detail of an existing module, not an API
460. **History Heuristic** – Scoring move success frequency across the entire game tree to guide move ordering. → skip: an implementation detail of an existing module, not an API

## 6. Numerical, Mathematical & Number Theory Algorithms (461–500)

461. **Euclidean Algorithm** – Computing Greatest Common Divisor (GCD) via repeated modulo ops. → `e.math.ntheory.gcd`
462. **Extended Euclidean Algorithm** – Finding GCD alongside Bézout coefficients x and y (ax + by = gcd(a,b)). → `e.math.ntheory.extended_gcd`
463. **Binary GCD (Stein's Algorithm)** – Computing GCD using bitwise shifts, subtractions, and parity operations. → `e.math.ntheory.gcd`
464. **Sieve of Eratosthenes** – Generating all prime numbers up to N by marking multiples. → `e.math.ntheory.sieve`
465. **Sieve of Sundaram** – Prime generation algorithm sifting out odd composite numbers. → skip: pedagogical only
466. **Sieve of Atkin** – Fast algorithm for finding primes using quadratic forms. → skip: implementable, but too specialised for the standard library
467. **Segmented Sieve** – Generating primes in contiguous blocks to optimize memory cache usage. → `e.math.ntheory.sieve_segmented`
468. **Linear Sieve** – Generating primes up to N in O(N) time while calculating multiplicative functions. → `e.math.ntheory.sieve_linear`
469. **Trial Division** – Basic primality test dividing N by integers up to N. → `e.math.ntheory.factor_trial`
470. **Fermat Primality Test** – Probabilistic test checking if ap−1 ≡ 1 (mod p). → skip: pedagogical only
471. **Miller-Rabin Primality Test** – Fast probabilistic primality test used widely in cryptography. → `e.math.ntheory.is_prime`
472. **Solovay-Strassen Test** – Probabilistic primality test based on Euler's criterion and Jacobi symbols. → skip: pedagogical only
473. **AKS Primality Test** – Unconditional, deterministic polynomial-time primality test. → skip: research-grade, no settled practical implementation
474. **Pollard's Rho Algorithm** – Integer factorization algorithm optimized for composite numbers with small factors. → `e.math.ntheory.factor_rho`
475. **Pollard's p − 1 Factorization** – Number-theoretic factorization effective when p − 1 has small prime factors. → `e.math.ntheory.factor_p_minus_1`
476. **Lenstra Elliptic-Curve Factorization (ECM)** – Factorization technique using arithmetic on elliptic curves. → `e.algo.bignum.factor_ecm`
477. **Quadratic Sieve** – General-purpose integer factorization algorithm for 50–100 digit numbers. → skip: research-grade, no settled practical implementation
478. **General Number Field Sieve (GNFS)** – Fastest known algorithm for factorizing integers larger than 10100. → skip: research-grade, no settled practical implementation
479. **Modular Exponentiation** – O(log E) computation of (BE ) (mod M) using repeated squaring. → `e.math.ntheory.pow_mod`
480. **Modular Multiplicative Inverse (Fermat's Little Theorem)** – Finding A−1 (mod P) when P is prime (AP−2 (mod P)). → `e.math.ntheory.inverse_mod`
481. **Chinese Remainder Theorem (CRT) Solver** – Solving systems of simultaneous modular congruences. → `e.math.ntheory.crt`
482. **Garner's Algorithm** – CRT implementation avoiding big-integer overhead by computing mixed-radix digits. → `e.math.ntheory.crt_garner`
483. **Euler's Totient Function (ϕ(n))** – Counting positive integers up to n that are coprime to n. → `e.math.ntheory.totient`
484. **Baby-Step Giant-Step** – O( N) algorithm for solving discrete logarithm problems ( ax ≡ b (mod m)). → `e.math.ntheory.discrete_log_bsgs`
485. **Pohlig-Hellman Algorithm** – Solving discrete logarithms when group order factors into small primes. → `e.math.ntheory.discrete_log_pohlig_hellman`
486. **Pollard's Kangaroo Algorithm** – Discrete logarithm algorithm searching within bounded ranges. → `e.math.ntheory.discrete_log_kangaroo`
487. **Tonelli-Shanks Algorithm** – Finding modular square roots (x2 ≡ n (mod p)). → `e.math.ntheory.sqrt_mod`
488. **Shanks-Mestre Point Counting** – Counting points on elliptic curves over finite fields. → skip: implementable, but too specialised for the standard library
489. **Fast Fourier Transform (FFT / Cooley-Tukey)** – O(N log N) transformation converting signals between time and frequency domains. → `e.math.fft.fft`
490. **Number Theoretic Transform (NTT)** – FFT equivalent operating over finite fields using primitive roots. → `e.math.fft.ntt`
491. **Karatsuba Multiplication** – Fast polynomial/integer multiplication running in O(N^log2(3)) ≈ O(N^1.58). → `e.algo.bignum.int_mul`
492. **Toom-Cook Multiplication** – Generalization of Karatsuba dividing numbers into k equal parts. → skip: an implementation detail of an existing module, not an API
493. **Schönhage-Strassen Algorithm** – Fast multiplication for large integers using FFT over 2^(2^n) + 1. → skip: an implementation detail of an existing module, not an API
494. **Harvey-Hoeven Multiplication** – O(N log N) ultra-large integer multiplication algorithm. → skip: research-grade, no settled practical implementation
495. **Fast Walsh-Hadamard Transform (FWHT)** – O(N log N) algorithm for bitwise XOR/AND/OR convolutions. → `e.math.fft.fwht`
496. **Newton-Raphson Method** – Root-finding algorithm using function derivatives (x(n+1) = x(n) − f(x(n)) / f′(x(n))). → `e.math.root.newton`
497. **Halley's Method** – Second-order root-finding method using first and second derivatives. → `e.math.root.halley`
498. **Secant Method** – Root-finding algorithm approximating derivatives using finite differences. → `e.math.root.secant`
499. **Bisection Method** – Deterministic root-finding repeatedly halving bracketed sign-change intervals. → `e.math.root.bisect`
500. **Brent's Method** – Hybrid root-finding combining bisection, secant, and inverse quadratic interpolation.  Yes do it → `e.math.root.brent`

## 7. Linear Algebra, Geometry & Spatial Algorithms (501–560)

501. **Gaussian Elimination** – Solving systems of linear equations via row-reduction to upper triangular form. → `e.algo.linalg.matrix.solve`
502. **Gauss-Jordan Elimination** – Reducing linear systems further to reduced row echelon form (RREF). → `e.algo.linalg.matrix.rref`
503. **LU Decomposition** – Factoring matrix A into lower (L) and upper (U) triangular matrices (A = LU). → `e.algo.linalg.matrix.lu`
504. **QR Decomposition** – Factoring matrix into orthogonal (Q) and upper triangular (R) matrices. → `e.algo.linalg.matrix.qr`
505. **Cholesky Decomposition** – Efficient factorization of symmetric positive-definite matrices (A = LLT). → `e.algo.linalg.matrix.cholesky`
506. **Singular Value Decomposition (SVD)** – Decomposing real matrix into singular vectors and singular values (A = UΣV T). → `e.algo.linalg.matrix.svd`
507. **Power Iteration** – Eigenvalue algorithm finding the dominant eigenvalue and eigenvector. → `e.algo.linalg.matrix.power_iteration`
508. **QR Algorithm for Eigenvalues** – Iterative matrix decomposition yielding all eigenvalues and eigenvectors. → `e.algo.linalg.matrix.eigen`
509. **Inverse Matrix Computation (Adjugate/Elimination)** – Finding matrix A−1 such that AA−1 = I. → `e.algo.linalg.matrix.inverse`
510. **Matrix Exponentiation** – O(log N) exponentiation for solving linear recurrences and graph path counts. → `e.algo.linalg.matrix.pow`
511. **Strassen's Matrix Multiplication** – Divide-and-conquer matrix multiplication running in O(N2.807). → skip: an implementation detail of an existing module, not an API
512. **Coppersmith-Winograd Algorithm** – Theoretical matrix multiplication algorithm running in O(N2.375). → skip: research-grade, no settled practical implementation
513. **Gram-Schmidt Process** – Orthonormalizing a set of vectors in an inner product space. → `e.algo.linalg.matrix.orthonormalize`
514. **Householder Reflection** – Constructing orthogonal matrices that reflect vectors across hyperplanes. → `e.algo.linalg.matrix.householder`
515. **Givens Rotation** – Applying planar rotations to zero out specific off-diagonal matrix elements. → `e.algo.linalg.matrix.givens`
516. **Simplex Algorithm** – Linear programming solver navigating vertices of a feasible polytope region. → `e.math.opt.simplex`
517. **Interior Point Method (Karmarkar's)** – Polynomial-time linear programming solver traversing polytope interiors. → `e.math.opt.convex.interior_point`
518. **Extended Kalman Filter (EKF)** – Non-linear state estimation using local first-order Taylor expansions. → `e.math.filter.ekf`
519. **Unscented Kalman Filter (UKF)** – Non-linear state estimation using deterministic sigma-point sampling. → `e.math.filter.ukf`
520. **Particle Filter (Sequential Monte Carlo)** – Non-parametric state estimation using weighted random particles. → `e.math.filter.particle`
521. **Ray-Casting Algorithm** – Determining point inclusion in 2D polygons by counting edge intersections. → `e.algo.geom.point_in_polygon`
522. **Ray-Box Intersection (Slab Method)** – Fast ray axis-aligned bounding box (AABB) intersection testing. → `e.algo.geom3.ray_box`
523. **Ray-Triangle Intersection (Möller-Trumbore)** – O(1) ray-triangle intersection without computing plane equations. → `e.algo.geom3.ray_triangle`
524. **Separating Axis Theorem (SAT)** – Collision detection checking projection overlaps on candidate axes. → `e.algo.geom3.separating_axis`
525. **Gilbert-Johnson-Keerthi (GJK)** – Collision detection and distance queries using Minkowski differences. → `e.algo.geom3.gjk`
526. **Expanding Polytope Algorithm (EPA)** – Finding penetration depth and contact vectors following GJK collisions. → `e.algo.geom3.epa`
527. **Bounding Volume Hierarchy (BVH)** – Tree structure organizing geometric primitives for spatial queries. → `e.data.spatial.bvh_build`
528. **Sweep-Line Algorithm (Bentley-Ottmann)** – O((N + K)log N) algorithm discovering K segment intersections. → `e.algo.geom.segment_intersections`
529. **Fortune's Algorithm** – O(N log N) sweep-line algorithm generating Voronoi diagrams. → `e.algo.geom.voronoi`
530. **Bowyer-Watson Algorithm** – Incremental generation of Delaunay triangulations in arbitrary dimensions. → `e.algo.geom.delaunay`
531. **Flip Algorithm** – Converting arbitrary triangulations to Delaunay triangulations via edge flipping. → `e.algo.geom.delaunay_flip`
532. **Winding Number Algorithm** – Exact point-in-polygon test calculating total signed rotation angle. → `e.algo.geom.winding_number`
533. **Ear Clipping Algorithm** – O(N2) polygon triangulation repeatedly cutting off non-overlapping ears. → `e.algo.geom.clip.triangulate_ear_clip`
534. **Sutherland-Hodgman Algorithm** – Clipping arbitrary polygons against convex clipping boundaries. → `e.algo.geom.clip.clip_convex`
535. **Weiler-Atherton Algorithm** – Polygon clipping algorithm supporting non-convex polygons with holes. → `e.algo.geom.clip_polygon`
536. **Cohen-Sutherland Line Clipping** – 2D line segment clipping using 4-bit outcodes. → `e.algo.geom.clip.clip_line`
537. **Liang-Barsky Line Clipping** – Parametric line segment clipping against rectangular viewports. → `e.algo.geom.clip.clip_line_liang_barsky`
538. **Line Segment Intersection Check** – Orientation-based cross-product test checking if two 2D segments cross. → `e.algo.geom.segments_intersect`
539. **Welzl's Algorithm** – Randomized linear-time O(N) algorithm finding minimum enclosing circle. → `e.algo.geom.enclosing_circle`
540. **Rotating Calipers** – Computing bounding boxes, maximum distance, or antipodal pairs in convex polygons. → `e.algo.geom.rotating_calipers`
541. **Closest Pair of Points** – O(N log N) divide-and-conquer search for closest 2D point pair. → `e.algo.geom.closest_pair`
542. **Furthest Pair of Points** – O(N log N) rotating calipers search over convex hull vertices. → `e.algo.geom.farthest_pair`
543. **Bresenham's Line Algorithm** – Integer-only incremental grid rasterization of line segments. → `e.gfx.raster.line`
544. **Midpoint Circle Algorithm** – Integer-based incremental circle drawing using 8-way symmetry. → `e.gfx.raster.circle`
545. **Xiaolin Wu's Line Algorithm** – Anti-aliased line drawing using coverage percentage weighting. → `e.gfx.raster.line_aa`
546. **Scanline Flood Fill** – Optimized flood filling operating on horizontal line segments instead of pixels. → `e.gfx.filter.flood_fill_scanline`
547. **Polygon Convexity Check** – Verifying polygon convexity via consistent cross-product sign evaluation. → `e.algo.geom.is_convex`
548. **Shoelace Formula (Gauss's Area Formula)** – Calculating area of non-self-intersecting polygons from coordinates. → `e.algo.geom.polygon_area`
549. **Pick's Theorem Computation** – Area calculation for lattice polygons using interior and boundary lattice points (A = I + B/2 − 1). → `e.algo.geom.lattice_points`
550. **Spatial Hash Grid Search** – Bucketing 2D/3D entities into fixed grid cells for O(1) neighbor queries. → `e.data.spatial.hash_grid`
551. **Marching Cubes** – Extracting 3D polygonal isosurface meshes from volumetric scalar fields. → `e.gfx.mesh.marching_cubes`
552. **Marching Squares** – Generating 2D contour lines from discrete 2D scalar fields. → `e.gfx.mesh.marching_squares`
553. **Catmull-Rom Spline Interpolation** – Constructing smooth space curves passing directly through control points. → `e.gfx.curve.catmull_rom`
554. **De Boor's Algorithm** – Fast evaluation of B-spline curves at parametric position t. → `e.gfx.curve.bspline`
555. **De Casteljau's Algorithm** – Recursive linear interpolation evaluating Bézier curves. → `e.gfx.curve.bezier`
556. **NURBS Surface Evaluation** – Calculating surface coordinates for Non-Uniform Rational B-Splines. → `e.gfx.curve.nurbs_surface`
557. **Douglas-Peucker Algorithm** – Polyline simplification reducing vertex count while maintaining topology tolerance. → `e.algo.geom.clip.simplify_douglas_peucker`
558. **Visvalingam-Whyatt Algorithm** – Line simplification incrementally removing vertices contributing least triangular area. → `e.algo.geom.clip.simplify_visvalingam`
559. **Rapidly-Exploring Random Tree (RRT)** – Sampling-based path planning searching high-dimensional spaces. → `e.robot.plan.rrt`
560. **RRT*** – Asymptotically optimal RRT rewiring tree branches to find shortest paths. → `e.robot.plan.rrt_star`

## 8. Cryptography, Security, Hashing & Compression (561–650)

561. **SHA-256** – Cryptographic hash function producing 256-bit message digests via Merkle-Damgård. → `e.crypto.hash.sha256`
562. **SHA-3 (Keccak)** – Cryptographic hash built on permutation-based sponge construction. → `e.crypto.hash.sha3_256`
563. **MD5 Algorithm** – Legacy 128-bit message digest function (now cryptographically broken). → `e.crypto.hash.legacy_md5`
564. **BLAKE3** – High-performance cryptographic hash using tree hashing and internal parallelism. → `e.crypto.hash.blake3`
565. **MurmurHash** – Fast non-cryptographic hash function optimized for general hash table lookups. → `e.algo.hash.murmur3`
566. **CityHash / FarmHash** – Non-cryptographic hash functions optimized for short string performance on CPUs. → skip: implementable, but too specialised for the standard library
567. **xxHash** – Extremely fast non-cryptographic hash operating at RAM speed limits. → `e.algo.hash.xxhash64`
568. **FNV-1a Hash** – Compact non-cryptographic hash using iterative multiplication and XOR operations. → `e.algo.hash.fnv1a64`
569. **Adler-32** – Fast 32-bit checksum combining two 16-bit modular sums. → `e.algo.hash.adler32`
570. **CRC32 Checksum** – Cyclic redundancy check detecting accidental data corruption via polynomial division. → `e.algo.hash.crc32`
571. **Fletcher's Checksum** – Error-detection algorithm providing comparable reliability to CRC32 at lower CPU cost. → `e.algo.hash.fletcher`
572. **HMAC** – Hash-based Message Authentication Code combining secret keys with cryptographic hashes. → `e.crypto.mac.hmac_sha256`
573. **HKDF** – Key derivation function extracting pseudo-random keys and expanding them to target lengths. → `e.crypto.kdf.hkdf_sha256_expand`
574. **PBKDF2** – Password-based key derivation applying repeated HMAC iterations with salt. → `e.crypto.kdf.pbkdf2`
575. **bcrypt** – Adaptive password hashing based on the Blowfish cipher incorporating a work factor. → `e.crypto.kdf.bcrypt`
576. **scrypt** – Memory-hard key derivation function designed to deter hardware ASIC attacks. → `e.crypto.kdf.scrypt`
577. **Argon2** – Password Hashing Competition winner optimizing memory-hardness (Argon2id/Argon2i/Argon2d). → `e.crypto.kdf.argon2id`
578. **AES (Rijndael)** – Symmetric block cipher operating on 128-bit blocks using substitution-permutation networks. → `e.crypto.cipher.aes_block`
579. **Triple DES (3DES)** – Legacy symmetric cipher applying DES encryption three times per block. → skip: obsolete cryptography
580. **ChaCha20** – High-speed symmetric stream cipher operating on 512-bit state matrices. → `e.crypto.cipher.chacha20`
581. **Salsa20** – Stream cipher precursor to ChaCha20 using quarter-round ARX operations. → skip: obsolete cryptography
582. **RSA Encryption & Signing** – Public-key cryptography reliant on the difficulty of prime factorization. → `e.crypto.sign.rsa_pss`
583. **Diffie-Hellman Key Exchange** – Method allowing two parties to establish a shared secret over an insecure channel. → `e.crypto.kx.dh`
584. **ECDH (Elliptic Curve Diffie-Hellman)** – Key agreement protocol using elliptic curve arithmetic. → `e.crypto.kx.x25519_exchange`
585. **ECDSA** – Elliptic Curve Digital Signature Algorithm providing digital authentication with shorter keys. → `e.crypto.sign.p256_sign`
586. **Ed25519 (EdDSA)** – High-speed, misuse-resistant digital signature scheme using Curve25519. → `e.crypto.sign.ed25519_sign`
587. **Schnorr Signature** – Efficient digital signature scheme supporting key and signature aggregation. → `e.crypto.sign.schnorr`
588. **Shamir's Secret Sharing** – Threshold scheme splitting secrets into N shares where any K can reconstruct it. → `e.crypto.secret.split`
589. **Paillier Cryptosystem** – Additively homomorphic public-key encryption scheme. → skip: implementable, but too specialised for the standard library
590. **Learning With Errors (LWE)** – Post-quantum cryptographic foundation based on high-dimensional lattice hardness. → skip: research-grade, no settled practical implementation
591. **NTRU Encryption** – Lattice-based public-key cryptosystem resilient to quantum attacks. → skip: implementable, but too specialised for the standard library
592. **Kyber (ML-KEM)** – Lattice-based key encapsulation mechanism standardized for post-quantum security. → `e.crypto.kx.ml_kem`
593. **Dilithium (ML-DSA)** – Lattice-based digital signature scheme standardized for post-quantum security. → `e.crypto.sign.ml_dsa`
594. **Groth16 (zk-SNARK)** – Zero-knowledge succinct non-interactive argument of knowledge with small proof size. → skip: research-grade, no settled practical implementation
595. **zk-STARK** – Zero-knowledge proof system requiring no trusted setup and offering post-quantum security. → skip: research-grade, no settled practical implementation
596. **Bulletproofs** – Short zero-knowledge range proofs requiring no trusted setup. → skip: research-grade, no settled practical implementation
597. **Ring Signatures** – Group digital signature obscuring the specific signer among a pool of public keys. → skip: implementable, but too specialised for the standard library
598. **Pedersen Commitments** – Cryptographic commitments hiding values while preserving additive homomorphic properties. → skip: implementable, but too specialised for the standard library
599. **Merkle Tree Construction** – Binary hash tree providing O(log N) data verification proofs. → `e.crypto.merkle.build`
600. **Merkle-Patricia Trie** – Modified radix trie providing cryptographically verifiable key- value state storage. → skip: implementable, but too specialised for the standard library
601. **Verkle Tree** – Tree structure using vector commitments to produce small state proofs. → skip: research-grade, no settled practical implementation
602. **BLS Signature Aggregation** – Aggregating multiple signatures across different keys into a single signature. → skip: implementable, but too specialised for the standard library
603. **AES-GCM** – Authenticated symmetric encryption mode providing both confidentiality and data integrity. → `e.crypto.aead.aes_gcm_seal`
604. **AES-CBC** – Cipher Block Chaining mode chaining plaintext blocks with previous ciphertext blocks. → `e.crypto.cipher.cbc`
605. **AES-CTR** – Counter mode converting block ciphers into stream ciphers using incrementing counters. → `e.crypto.cipher.ctr`
606. **Poly1305** – Fast, one-time authenticator creating 128-bit message authentication tags. → `e.crypto.mac.poly1305`
607. **One-Time Pad** – Information-theoretically unbreakable encryption using random keys matching message length. → skip: pedagogical only
608. **Feistel Cipher Structure** – Symmetric network splitting block states into left and right halves iteratively. → skip: a technique applied per problem, not a reusable function
609. **Substitution-Permutation Network (SPN)** – Cipher architecture alternating substitution boxes and permutation layers. → skip: a technique applied per problem, not a reusable function
610. **Chaum's Blind Signature** – Protocol allowing message signing without revealing message content to the signer. → skip: implementable, but too specialised for the standard library
611. **Huffman Coding** – Entropy encoding assigning variable-length bit codes based on character frequency. → `e.algo.coding.huffman_encode`
612. **Canonical Huffman Coding** – Huffman variant generating standardized bit patterns for compact tree storage. → `e.algo.coding.huffman_canonical`
613. **Adaptive Huffman Coding** – Dynamic entropy coding updating frequency trees on the fly during transmission. → skip: implementable, but too specialised for the standard library
614. **LZW Compression** – Dictionary-based lossless compression building code tables dynamically. → `e.fmt.lzw.encode`
615. **LZ77 (Sliding Window)** – Lossless compression replacing duplicate data with (distance, length) pointers. → skip: an implementation detail of an existing module, not an API
616. **LZ78** – Lossless compression constructing an explicit dictionary of phrases from input streams. → skip: implementable, but too specialised for the standard library
617. **LZMA** – High-ratio lossless compression using dictionary encoding and range coder backends. → `e.fmt.lzma.decode`
618. **LZ4** – Extremely fast byte-aligned compression optimized for high decompression throughput. → `e.fmt.lz4.encode`
619. **Zstandard (zstd)** – Lossless compression combining LZ77 with Finite State Entropy (FSE) backends. → `e.fmt.zstd.encode`
620. **DEFLATE** – Lossless data compression combining LZ77 and Huffman coding (used in Gzip/Zip). → `e.algo.deflate.encode`
621. **Brotli** – Lossless compression combining LZ77, Huffman coding, and static dictionary context modeling. → `e.fmt.brotli.decode`
622. **Snappy** – Fast byte-oriented compression designed for high-throughput string processing. → `e.fmt.snappy.encode`
623. **Burrows-Wheeler Transform (BWT)** – Block-sorting transform grouping identical characters together for compression. → `e.algo.coding.bwt`
624. **Move-To-Front (MTF) Transform** – Data transformation replacing recent symbols with index positions in a dynamic list. → `e.algo.coding.move_to_front`
625. **Arithmetic Coding** – Lossless entropy encoding mapping entire streams into a single floating-point interval. → `e.algo.coding.arithmetic_encode`
626. **Asymmetric Numeral Systems (ANS)** – Fast entropy coding offering arithmetic coding ratios at Huffman speeds. → `e.algo.coding.ans_encode`
627. **Delta Encoding** – Storing data streams as differences (deltas) between sequential values. → `e.algo.coding.delta_encode`
628. **Frame of Reference (FoR) Compression** – Storing integer arrays as small offsets relative to a minimum reference value. → `e.algo.coding.for_encode`
629. **Elias Gamma / Delta / Omega Coding** – Universal bit-level variable-length integer encoding schemes. → `e.algo.coding.elias_gamma`
630. **Golomb / Rice Coding** – Lossless variable-length encoding optimized for geometric distributions. → `e.algo.coding.rice_encode`
631. **Varint (Variable Byte) Encoding** – Encoding arbitrary integers into variable numbers of bytes using 7-bit chunks. → `e.algo.coding.varint_encode`
632. **ZigZag Encoding** – Mapping signed integers to unsigned integers so small negative values use fewer bits. → `e.algo.coding.zigzag_encode`
633. **Roaring Bitmaps** – Compressed bitmap data structure using arrays, run-length encodings, or raw bitsets. → `e.data.bitmap.roaring`
634. **Word-Aligned Hybrid (WAH)** – Compressed bit-vector structure optimizing logical AND/OR set operations. → `e.data.bitmap.wah`
635. **Discrete Cosine Transform (DCT)** – Lossy image compression algorithm packing energy into low frequencies (JPEG). → `e.math.fft.dct`
636. **Discrete Wavelet Transform (DWT)** – Multi-resolution image compression transform preserving spatial localization (JPEG 2000). → `e.math.fft.dwt`
637. **Quantization Matrix Application** – Lossy step dividing frequency coefficients to discard perceptually insignificant data. → skip: an implementation detail of an existing module, not an API
638. **Chroma Subsampling** – Color compression reducing chrominance resolution relative to luminance (4 : 2 : 2, 4 : 2 : 0). → skip: an implementation detail of an existing module, not an API
639. **Vector Quantization (LBG)** – Lossy vector clustering mapping continuous features to discrete codebook vectors. → `e.ml.cluster.vector_quantize`
640. **pHash (Perceptual Hash)** – Fingerprinting media files based on visual features rather than exact binary representations. → `e.gfx.image.phash`
641. **Average Hash (aHash)** – Fast perceptual image hash comparing pixels against average luminance. → `e.gfx.image.ahash`
642. **Difference Hash (dHash)** – Perceptual image hash tracking directional pixel brightness gradients. → `e.gfx.image.dhash`
643. **Block Truncation Coding (BTC)** – Lossy image compression preserving local sample mean and standard deviation. → skip: implementable, but too specialised for the standard library
644. **ASTC Texture Compression** – Fixed-rate GPU texture compression supporting arbitrary block sizes. → `e.gfx.texture.astc_decode`
645. **BC1–BC7 (DXTC / S3TC)** – Hardware-accelerated GPU texture block compression formats. → `e.gfx.texture.bc_decode`
646. **FLAC Linear Predictive Coding** – Lossless audio compression modeling audio samples via autoregressive linear prediction. → `e.fmt.flac.decode`
647. **Opus Audio Compression Engine** – Low-latency audio codec combining SILK (speech) and CELT (music) engines. → `e.fmt.opus.decode`
648. **Block-Matching Motion Estimation** – Video compression tracking spatial movement vectors between frames. → skip: implementable, but too specialised for the standard library
649. **HEVC Quad-Tree Intra Prediction** – Hierarchical video frame partitioning into coding tree units (CTUs). → skip: implementable, but too specialised for the standard library
650. **AV1 Film Grain Synthesis** – Video encoding stripping camera noise and re-synthesizing it parametrically at display time. → skip: implementable, but too specialised for the standard library

## 9. Operating Systems, Concurrency, Memory & Distributed Systems (651–720)

651. **Context Switching** – Saving and restoring CPU registers, program counters, and address spaces. → skip: OS kernel internals
652. **Round-Robin Scheduling** – Preemptive process scheduling assigning fixed CPU time slices sequentially. → skip: OS kernel internals
653. **Shortest Remaining Time First (SRTF)** – Preemptive scheduler prioritizing tasks with least remaining execution time. → skip: OS kernel internals
654. **Priority Scheduling with Aging** – Dynamic process scheduling increasing priority over time to prevent starvation. → skip: OS kernel internals
655. **Multilevel Feedback Queue (MLFQ)** – Adaptive scheduling adjusting process queues based on CPU vs I/O behavior. → skip: OS kernel internals
656. **Completely Fair Scheduler (CFS)** – Linux red-black tree scheduler balancing virtual runtime among processes. → skip: OS kernel internals
657. **Earliest Deadline First (EDF)** – Dynamic real-time task scheduling prioritizing upcoming execution deadlines. → `e.thread.pool.edf`
658. **Rate Monotonic Scheduling (RMS)** – Static-priority real-time scheduling assigning higher priority to frequent tasks. → skip: OS kernel internals
659. **Work-Stealing Scheduler** – Task scheduling where idle worker threads pull tasks from busy threads' deques. → `e.thread.pool.work_stealing`
660. **Fork-Join Framework** – Parallel execution model recursively splitting tasks and joining results. → `e.thread.pool.fork_join`
661. **Peterson's Algorithm** – Concurrent software lock guaranteeing mutual exclusion between two processes. → skip: pedagogical only
662. **Dekker's Algorithm** – First correct software solution for two-process mutual exclusion. → skip: pedagogical only
663. **Lamport's Bakery Algorithm** – N-process mutual exclusion algorithm assigning ordering tickets. → skip: pedagogical only
664. **Test-And-Set** – Hardware atomic instruction setting memory flags and returning previous values. → `e.atomic.xchg` (the intrinsic's spelling)
665. **Compare-And-Swap (CAS)** – Atomic instruction updating memory locations only if current values match expectations. → `e.atomic.cas` (the intrinsic's spelling)
666. **Fetch-And-Add (FAA)** – Hardware atomic primitive incrementing memory values in place. → `e.atomic.add` (the intrinsic's spelling)
667. **Read-Copy-Update (RCU)** – Synchronization mechanism allowing readers lock-free access while updates publish pointer swaps. → `e.sync.rcu`
668. **Reader-Writer Lock** – Synchronization primitive allowing concurrent reads or exclusive writes. → `e.sync.rwlock`
669. **Semaphore (P and V Operations)** – Signaling counter managing resource access units. → `e.sync.semaphore`
670. **Priority Inheritance Protocol** – Priority inversion solution boosting lower-priority task priorities holding required locks. → skip: OS kernel internals
671. **Priority Ceiling Protocol** – Real-time lock ceiling assignment preventing priority inversions and deadlocks. → skip: OS kernel internals
672. **Dissemination Barrier** – O(log N) thread synchronization barrier exchanging completion flags in rounds. → `e.sync.barrier`
673. **Spinlock with Exponential Backoff** – Busy-waiting lock delaying retry intervals exponentially to reduce memory bus pressure. → `e.sync.spin_lock`
674. **Michael-Scott Queue** – Concurrent lock-free FIFO queue using atomic CAS operations on linked lists. → `e.concurrent.queue.push`
675. **Treiber Stack** – Lock-free concurrent stack using Compare-And-Swap on head pointers. → `e.concurrent.stack.push`
676. **Split-Ordered Lists** – Lock-free hash table supporting dynamic resizing using bit-reversed key orders. → skip: an implementation detail of an existing module, not an API
677. **Hazard Pointers** – Memory reclamation technique preventing lock-free memory deallocation races. → `e.concurrent.reclaim.hazard`
678. **Epoch-Based Reclamation (EBR)** – Deferred lock-free memory freeing tied to global epoch state progression. → `e.concurrent.reclaim.epoch`
679. **Buddy Memory Allocation** – Memory management subdividing blocks into power-of-two halves ("buddies"). → `e.mem.buddy`
680. **Slab Allocation** – Kernel object caching eliminating memory fragmentation for fixed-size structures. → `e.mem.slab`
681. **Arena Allocator** – Region-based memory allocation releasing contiguous blocks all at once. → `e.mem.arena_from`
682. **Pool Allocator** – Fast fixed-size block memory allocation managed via free lists. → `e.mem.pool`
683. **Stack-Based Arena Allocator** – Sequential linear memory allocation supporting LIFO rewinds. → `e.mem.mark`
684. **First-Fit / Best-Fit Memory Search** – Free-list search strategies locating memory blocks for allocation requests. → skip: an implementation detail of an existing module, not an API
685. **Mark-and-Sweep GC** – Two-phase garbage collection marking reachable roots and sweeping unreferenced memory. → skip: Neper has ownership, not a garbage collector
686. **Cheney's Copying Collector** – Two-space GC copying reachable objects into a single contiguous destination space. → skip: Neper has ownership, not a garbage collector
687. **Generational Garbage Collection** – Memory reclamation prioritizing short-lived young generation objects. → skip: Neper has ownership, not a garbage collector
688. **Reference Counting with Trial Deletion** – Reference-counted memory management resolving cyclic references. → skip: Neper has ownership, not a garbage collector
689. **Tri-Color Marking** – Concurrent GC classifying objects into white (unvisited), grey (frontier), and black (visited). → skip: Neper has ownership, not a garbage collector
690. **ZGC Concurrent Marking** – Garbage collection using colored pointers and load barriers for sub-millisecond pauses. → skip: Neper has ownership, not a garbage collector
691. **Page Table Walk** – Hardware MMU multi-level tree traversal resolving virtual memory addresses to physical addresses. → skip: OS kernel internals
692. **TLB Miss Handling** – Virtual memory address translation falling back to page table walks upon TLB cache misses. → skip: OS kernel internals
693. **Inverted Page Table Lookup** – Hash-based page table mapping physical memory frames back to virtual pages. → skip: OS kernel internals
694. **LRU Page Replacement** – Evicting physical memory pages that have gone longest without access. → see #268 (`e.data.cache.lru`)
695. **Clock (Second-Chance) Page Eviction** – Circular page array loop checking usage bit flags prior to page eviction. → see #271 (`e.data.cache.clock`)
696. **Not Recently Used (NRU) Eviction** – Page selection categorizing pages by read/written status bits. → skip: OS kernel internals
697. **Working Set Page Model** – Thrashing prevention monitoring process page access frequencies within time windows. → skip: OS kernel internals
698. **Elevator Algorithm (SCAN)** – Disk I/O scheduling moving arm in one direction serving requests until reaching end bounds. → skip: OS kernel internals
699. **C-SCAN (Circular SCAN)** – Disk I/O scheduling serving requests in one direction only, jumping back to start immediately. → skip: OS kernel internals
700. **LOOK / C-LOOK Scheduling** – Elevator algorithm variant reversing direction upon servicing final request in current direction. → skip: OS kernel internals
701. **I/O Multiplexing (epoll / kqueue / io_uring)** – OS event notification mechanisms monitoring multiple file descriptors efficiently. → `e.async.poll`
702. **Reactor Pattern** – Event handling pattern dispatching incoming I/O requests synchronously to handlers. → skip: a technique applied per problem, not a reusable function
703. **Proactor Pattern** – Event handling pattern executing I/O operations asynchronously and notifying completion handlers. → skip: a technique applied per problem, not a reusable function
704. **Thread Pool Worker Loop** – Reusing fixed worker thread sets pulling tasks off synchronized queues. → `e.thread.pool.run`
705. **Token Bucket Algorithm** – Traffic shaping rate limiting allowing burst capacity within token refresh rates. → `e.ratelimit.token_bucket`
706. **Leaky Bucket Algorithm** – Traffic limiting enforcing smooth constant outbound request rates. → `e.ratelimit.leaky_bucket`
707. **Fixed Window Counter** – Rate limiting counting requests within fixed calendar time windows. → `e.ratelimit.fixed_window`
708. **Sliding Window Log** – Rate limiting logging exact timestamps per request to prevent boundary bursts. → `e.ratelimit.sliding_log`
709. **Sliding Window Counter** – Rate limiting combining current and previous window counts using weighted averages. → `e.ratelimit.sliding_window`
710. **Circuit Breaker Pattern** – Fault-tolerance state machine (Closed, Open, Half-Open) failing fast when downstream services error. → `e.resilience.circuit_breaker`
711. **Exponential Backoff with Jitter** – Retrying failed operations with exponentially increasing random delay intervals. → `e.resilience.backoff`
712. **Weighted Round-Robin Load Balancing** – Distributing incoming requests across servers proportional to assigned weights. → `e.net.balance.weighted_round_robin`
713. **Power of Two Choices (Maglev)** – Load balancing selecting the shorter queue between two randomly chosen nodes. → `e.net.balance.power_of_two`
714. **DNS Round-Robin** – Distributing network traffic by returning alternating IP addresses for domain queries. → `e.net.resolve`
715. **Heartbeat Monitoring** – Periodic ping messages tracking live status of remote cluster nodes. → `e.resilience.heartbeat`
716. **Distributed Tracing Context Propagation** – Injecting trace and span IDs across HTTP/RPC service headers. → `e.trace.propagate`
717. **LSM-Tree Compaction** – Merging and sorting immutable SSTables (Size-Tiered or Leveled) to reclaim disk space. → `e.db.storage.lsm_compact`
718. **Write-Ahead Logging (WAL)** – Ensuring ACID durability by logging mutations to append-only files before applying to state. → `e.db.storage.wal_append`
719. **ARIES Recovery Protocol** – Transaction recovery logging protocol executing Analysis, Redo, and Undo passes. → `e.db.storage.recover`
720. **Two-Phase Commit (2PC)** – Distributed consensus protocol coordinating distributed transaction commit or rollback steps. → `e.dist.commit.two_phase`

## 10. Machine Learning, Artificial Intelligence & Optimization (721–780)

721. **Ordinary Least Squares (OLS) Linear Regression** – Minimizing sum of squared residuals to fit linear relationships (y = Xβ + ϵ). → `e.ml.linear.ols`
722. **Ridge Regression** – Linear regression regularized with an L2 penalty term (λ∥β∥₂²) to prevent overfitting. → `e.ml.linear.ridge`
723. **Lasso Regression** – Linear regression regularized with an L1 penalty term (λ∥β∥₁) driving sparse coefficients. → `e.ml.linear.lasso`
724. **Logistic Regression (L-BFGS / Newton)** – Binary classification modeling log-odds of outcomes using sigmoid functions. → `e.ml.linear.logistic`
725. **K-Means Clustering** – Partitioning N observations into K clusters by minimizing squared distances to centroids. → `e.ml.cluster.kmeans`
726. **K-Means++ Initialization** – Seeding initial centroids proportional to squared distance from existing centroids. → `e.ml.cluster.kmeans_pp_init`
727. **K-Medoids (PAM Algorithm)** – Clustering using actual dataset objects (medoids) instead of mean centroids. → `e.ml.cluster.kmedoids`
728. **DBSCAN** – Density-based spatial clustering identifying core points, border points, and noise. → `e.ml.cluster.dbscan`
729. **OPTICS** – Density-based clustering ordering points to extract variable-density cluster hierarchies. → `e.ml.cluster.optics`
730. **Agglomerative Hierarchical Clustering** – Bottom-up clustering merging clusters based on linkage criteria (Single/Complete/Average). → `e.ml.cluster.agglomerative`
731. **Expectation-Maximization (EM) for GMM** – Iterative fitting of Gaussian Mixture Models optimizing data log-likelihood. → `e.ml.cluster.gmm_em`
732. **Principal Component Analysis (PCA)** – Dimensionality reduction projecting data onto orthogonal variance-maximizing eigenvectors. → `e.ml.reduce.pca`
733. **t-SNE** – Non-linear dimensionality reduction preserving local neighbor similarities via t-distributions. → `e.ml.reduce.tsne`
734. **UMAP** – Dimensionality reduction based on manifold learning and Riemannian geometry. → skip: implementable, but too specialised for the standard library
735. **K-Nearest Neighbors (KNN)** – Non-parametric classification/regression assigning labels based on K closest training instances. → `e.ml.knn.classify`
736. **Decision Tree Induction (CART / C4.5)** – Recursive dataset partitioning maximizing Information Gain or Gini Impurity reduction. → `e.ml.tree.cart`
737. **Random Forest Ensembling** – Combining decision trees trained on bootstrap samples with random feature subsets. → `e.ml.tree.random_forest`
738. **Gradient Boosting Decision Trees (GBDT)** – Sequential ensemble fitting new decision trees to negative gradients of loss functions. → `e.ml.tree.gradient_boost`
739. **XGBoost Algorithm** – Second-order gradient tree boosting with regularized objective functions and parallel building. → see #738 (`e.ml.tree.gradient_boost`)
740. **LightGBM Histogram Optimization** – Tree boosting bucketing continuous features into discrete bins to accelerate splits. → see #738 (`e.ml.tree.gradient_boost`)
741. **Naive Bayes Classification** – Probabilistic classifier applying Bayes' Theorem assuming feature independence. → `e.ml.bayes.naive`
742. **Sequential Minimal Optimization (SMO)** – Solving the quadratic programming problem in Support Vector Machine training. → `e.ml.svm.smo`
743. **SVM Kernel Trick** – Implicitly mapping inputs to high-dimensional feature spaces using inner product functions (RBF, Polynomial). → `e.ml.svm.kernel`
744. **Perceptron Learning Algorithm** – Single-layer binary classifier updating weights upon misclassification errors. → `e.ml.nn.perceptron`
745. **Backpropagation (Automatic Differentiation)** – Computing loss gradients across neural network weights via the chain rule. → `e.ml.nn.autodiff`
746. **Stochastic Gradient Descent (SGD)** – Iterative optimization updating parameters using single-sample loss gradients. → `e.ml.optim.sgd`
747. **SGD with Momentum** – Accelerating gradient descent updates by accumulating past directional velocity vectors. → `e.ml.optim.momentum`
748. **RMSprop Optimization** – Adaptive learning rate method dividing gradients by running root mean square averages. → `e.ml.optim.rmsprop`
749. **Adam Optimizer** – Optimization combining first-moment (mean) and second-moment (uncentered variance) gradient tracking. → `e.ml.optim.adam`
750. **AdamW Optimizer** – Adam optimization variant decoupling weight decay from gradient updates.  Yes do it → `e.ml.optim.adamw`
751. **Scaled Dot-Product Attention** – Calculating query-key similarity matrices with scaling factor √d_k. → `e.ml.nn.attention`
752. **Multi-Head Attention** – Parallel attention projections over subspace representations in Transformers. → `e.ml.nn.multi_head_attention`
753. **Rotary Position Embedding (RoPE)** – Injecting relative positional information using rotation matrices. → `e.ml.nn.rope`
754. **FlashAttention** – Tile-based memory-efficient exact attention computing blockwise updates. → `e.gpu.attention_flash`
755. **Beam Search** – Heuristic search maintaining top-k most probable sequence hypotheses. → `e.ml.sample.beam_search`
756. **Temperature Sampling** – Scaling logit distributions to control randomness during sequence generation. → `e.ml.sample.temperature`
757. **Top-K Sampling** – Filtering next-token candidate pools to the K highest-probability tokens. → `e.ml.sample.top_k`
758. **Top-P (Nucleus) Sampling** – Dynamic next-token candidate selection targeting cumulative probability P. → `e.ml.sample.top_p`
759. **Contrastive Loss (InfoNCE)** – Maximizing agreement between positive pairs while minimizing negative pairs. → `e.ml.loss.info_nce`
760. **Triplet Loss** – Minimizing anchor-positive distance while maximizing anchor-negative distance. → `e.ml.loss.triplet`
761. **GAN Minimax Optimization** – Adversarial training balancing generator and discriminator objectives. → skip: a trained ML model or training recipe
762. **DDPM Noise Estimation** – Denoising Diffusion Probabilistic Models predicting Gaussian noise steps. → skip: a trained ML model or training recipe
763. **VAE ELBO Maximization** – Optimizing Evidence Lower Bound combining reconstruction loss and KL divergence. → skip: a trained ML model or training recipe
764. **Q-Learning** – Off-policy temporal-difference reinforcement learning updating state-action values. → `e.ml.rl.q_learning`
765. **SARSA** – On-policy temporal-difference reinforcement learning updating value functions via executed actions. → `e.ml.rl.sarsa`
766. **Deep Q-Networks (DQN)** – Reinforcement learning combining Q-learning with neural networks and replay buffers. → skip: a trained ML model or training recipe
767. **Proximal Policy Optimization (PPO)** – Policy gradient RL optimizing clipped surrogate objectives. → skip: a trained ML model or training recipe
768. **Trust Region Policy Optimization (TRPO)** – Policy gradient method enforcing KL-divergence constraints on updates. → skip: a trained ML model or training recipe
769. **Asynchronous Advantage Actor-Critic (A3C)** – Parallel asynchronous worker threads updating global policy networks. → skip: a trained ML model or training recipe
770. **Simulated Annealing** – Probabilistic optimization accepting worse states controlled by a cooling temperature parameter. → `e.math.opt.meta.simulated_annealing`
771. **Genetic Algorithm** – Population-based optimization employing selection, crossover, and mutation operations. → `e.math.opt.meta.genetic`
772. **Particle Swarm Optimization (PSO)** – Population optimization navigating search spaces using velocity vectors. → `e.math.opt.meta.particle_swarm`
773. **Ant Colony Optimization (ACO)** – Probabilistic graph search guided by simulated pheromone decay and deposition. → `e.math.opt.meta.ant_colony`
774. **Differential Evolution** – Vector-based stochastic optimization mutating population candidates via differences. → `e.math.opt.meta.differential_evolution`
775. **Nelder-Mead Simplex Method** – Direct search optimization using geometric simplex transformations without derivatives. → `e.math.opt.nelder_mead`
776. **Conjugate Gradient Method** – Iterative solver for linear systems and non-linear optimization along orthogonal directions. → `e.math.opt.conjugate_gradient`
777. **BFGS Algorithm** – Quasi-Newton optimization method approximating the inverse Hessian matrix. → `e.math.opt.bfgs`
778. **L-BFGS Algorithm** – Limited-memory quasi-Newton optimization storing recent position/gradient updates. → `e.math.opt.lbfgs`
779. **Hill Climbing** – Local search algorithm continuously moving in the direction of increasing value. → `e.math.opt.meta.hill_climb`
780. **Tabu Search** – Metaheuristic search employing short-term memory lists to avoid previously visited local optima. → `e.math.opt.meta.tabu`

## 11. Image Processing, Computer Vision & Signal Processing (781–820)

781. **Sobel Filter Convolution** – Calculating image intensity spatial gradients using 3 × 3 derivative masks. → `e.gfx.filter.sobel`
782. **Canny Edge Detector** – Multi-stage edge detection combining Gaussian smoothing, gradients, non-maximum suppression, and hysteresis thresholding. → `e.gfx.filter.canny`
783. **Harris Corner Detector** – Identifying visual corner features based on local intensity gradient changes. → `e.gfx.vision.harris_corners`
784. **SIFT (Scale-Invariant Feature Transform)** – Detecting scale, rotation, and illumination invariant interest points. → `e.gfx.vision.sift`
785. **ORB (Oriented FAST and Rotated BRIEF)** – Fast binary feature detector combining FAST keypoints and oriented BRIEF descriptors. → `e.gfx.vision.orb`
786. **Hough Transform** – Feature extraction technique identifying geometric shapes (lines, circles) in binary images. → `e.gfx.vision.hough_lines`
787. **Gaussian Blur Filtering** – Low-pass image filtering using 2D Gaussian convolution kernels. → `e.gfx.filter.gaussian_blur`
788. **Bilateral Filter** – Edge-preserving image smoothing weighting pixels by spatial distance and color similarity. → `e.gfx.filter.bilateral`
789. **Otsu's Thresholding** – Automatic image binarization maximizing inter-class variance between foreground and background. → `e.gfx.filter.threshold_otsu`
790. **Watershed Algorithm** – Topographic region-growing segmentation treating image intensities as elevation relief maps. → `e.gfx.filter.watershed`
791. **Lucas-Kanade Optical Flow** – Local optical flow estimation assuming constant velocity within local neighborhood windows. → `e.gfx.vision.optical_flow_lk`
792. **Farneback Optical Flow** – Dense optical flow calculation approximating neighborhoods with quadratic polynomials. → `e.gfx.vision.optical_flow_farneback`
793. **Median Filter** – Non-linear spatial filter replacing pixel values with neighborhood medians to eliminate noise. → `e.gfx.filter.median`
794. **Moving Average Filter** – Smoothing discrete time-series data by averaging sliding window segments. → `e.dsp.moving_average`
795. **Exponential Moving Average (EMA)** – Time-series smoothing applying exponentially decreasing weights to older data points. → `e.dsp.ema`
796. **Savitzky-Golay Filter** – Smoothing signal data by fitting low-degree local polynomials via least squares. → `e.dsp.savitzky_golay`
797. **Finite Impulse Response (FIR) Filter** – Digital signal filter whose impulse response settles to zero in finite time. → `e.dsp.fir`
798. **Infinite Impulse Response (IIR) Filter** – Digital signal filter utilizing feedback loops for recursive impulse responses. → `e.dsp.iir`
799. **Butterworth Filter Design** – Signal processing filter maximizing frequency response passband flatness. → `e.dsp.design_butterworth`
800. **Chebyshev Filter Design** – Signal processing filter sacrificing passband/stopband ripple for steeper roll-off curves. → `e.dsp.design_chebyshev`
801. **Mel-Frequency Cepstral Coefficients (MFCC)** – Extracting spectral acoustic features mapped to human auditory perception scales. → `e.dsp.mfcc`
802. **Short-Time Fourier Transform (STFT)** – Computing frequency spectra over sliding windowed signal segments. → `e.dsp.stft`
803. **Constant-Q Transform** – Time-frequency transform using logarithmically spaced center frequencies. → `e.dsp.cqt`
804. **YIN Pitch Detection** – Monophonic pitch tracking based on modified autocorrelation functions. → `e.audio.analysis.pitch_yin`
805. **Dynamic Time Warping (DTW)** – Measuring similarity between temporal sequences with variable timing speeds. → `e.dsp.dtw`
806. **Peak Signal-to-Noise Ratio (PSNR)** – Objective quality metric evaluating pixel-level error between compressed and original images. → `e.gfx.image.psnr`
807. **Structural Similarity Index (SSIM)** – Perceptual quality metric comparing image luminance, contrast, and structural features. → `e.gfx.image.ssim`
808. **Connected Component Labeling** – Identifying contiguous pixel regions in binary images using two-pass sweeps. → `e.gfx.filter.label_components`
809. **Integral Image (Summed-Area Table)** – O(1) sub-rectangle pixel intensity summation precomputed in single passes. → `e.gfx.filter.integral_image`
810. **Guided Image Filter** – Edge-preserving smoothing filter using a guidance image to compute linear transformations. → `e.gfx.filter.guided`
811. **Laplacian Pyramid Construction** – Multi-scale bandpass image decomposition subtracting upsampled Gaussian levels. → `e.gfx.filter.laplacian_pyramid`
812. **Distance Transform** – Computing minimum distance from every grid pixel to nearest obstacle or boundary. → `e.gfx.filter.distance_transform`
813. **Morphological Erosion & Dilation** – Fundamental binary image shape operations expanding or shrinking boundaries. → `e.gfx.filter.morph_erode`
814. **Morphological Opening & Closing** – Compound operations removing background noise or filling foreground holes. → `e.gfx.filter.morph_open`
815. **Harris-Laplace Detector** – Scale-adapted corner detection combining Harris response with Laplacian scale selection. → skip: implementable, but too specialised for the standard library
816. **Haar Cascade Classifier** – Fast object detection using boosted decision trees over Haar-like visual features. → skip: a trained ML model or training recipe
817. **Mean Shift Segmentation** – Non-parametric feature-space clustering shifting points to local mode density peaks. → `e.gfx.filter.mean_shift`
818. **GrabCut Segmentation** – Interactive foreground extraction using iterative Graph Cuts and Gaussian Mixture Models. → skip: implementable, but too specialised for the standard library
819. **Phase Correlation** – Estimating relative translation offsets between two images using 2D Fourier transforms. → `e.gfx.vision.phase_correlate`
820. **Zero-Crossing Detector** – Identifying edge locations in signals or images where second derivatives flip signs. → `e.dsp.zero_crossings`

## 12. Bit Manipulation, Low-Level Arithmetic & Systems (821–860)

821. **Brian Kernighan's Algorithm** – Counting set bits in an integer by repeatedly clearing the lowest set bit ( x &= x - 1 ). → `e.bytes.count_ones`
822. **Population Count (Popcount)** – Parallel bitwise accumulation calculating total set bits in a word. → `e.bytes.count_ones`
823. **Count Leading Zeros (CLZ)** – Determining the number of consecutive zero bits preceding the most significant set bit. → `e.bytes.leading_zeros`
824. **Count Trailing Zeros (CTZ)** – Counting consecutive zero bits following the least significant set bit. → `e.bytes.trailing_zeros`
825. **Reverse Bits** – Inverting bit order across an integer using hierarchical parallel swaps. → `e.bytes.reverse_bits`
826. **Next Power of Two** – Rounding unsigned integers up to the nearest power of two using bitwise OR shifts. → `e.bytes.next_power_of_two`
827. **XOR Swap Algorithm** – Swapping two variables in place without auxiliary storage using XOR operations. → skip: pedagogical only
828. **Fast Inverse Square Root** – Computing 1/ x using IEEE 754 floating-point magic constant bit manipulation and Newton iterations. → `e.math.rsqrt`
829. **Gray Code Conversion** – Encoding binary values into Gray code (G = B ⊕ (B ≫ 1)) and decoding back. → `e.bytes.gray_encode`
830. **Parity Check** – Determining if the total count of set bits in a binary word is even or odd. → `e.bytes.parity`
831. **Bitwise Circular Shift (Rotate Left/Right)** – Rotating bits beyond word boundaries without bit loss. → `e.bytes.rotate_left`
832. **Bitmask Overlap Check** – Verifying set intersection between bit flags using bitwise AND operations ( (A & B) != 0 ). → skip: pedagogical only
833. **Carryless Multiplication** – Multiplying binary polynomials over Galois Field GF(2). → `e.math.gf.clmul`
834. **IEEE 754 Floating-Point Unpacking** – Extracting sign, exponent, and mantissa fields from 32-bit/64-bit float representations. → `e.math.float.unpack`
835. **Half-Precision (FP16) Conversion** – Packing/unpacking standard 32-bit floats to 16-bit floating point representations. → `e.math.float.to_f16`
836. **Bfloat16 Conversion** – Truncating 32-bit floats to 16-bit brain floating-point format preserving 8-bit exponent ranges. → `e.math.float.to_bf16`
837. **Saturated Arithmetic Operations** – Clamping arithmetic results to minimum or maximum byte/word bounds on overflow. → `e.math.saturating_add`
838. **Byte Swapping (Endianness Flip)** – Reversing byte order within multi-byte integers for network packet conversion. → `e.bytes.byte_swap`
839. **Variable-Length Quantity (VLQ)** – Encoding arbitrary-length integers using continuation bits per byte. → `e.algo.coding.vlq_encode`
840. **Delta-Delta Encoding** – Storing differences between consecutive differences in time-series data streams. → `e.algo.coding.delta_delta_encode`
841. **Bit-Packing Array** – Compacting K-bit integers into contiguous memory byte arrays. → `e.algo.coding.bit_pack`
842. **Bitset Intersection / Union** – Computing set operations over bit arrays using SIMD bitwise AND/OR instructions. → `e.algo.bitset.intersect`
843. **Longitudinal Redundancy Check (LRC)** – Error detection checksum calculating XOR sums across byte sequences. → `e.algo.hash.lrc`
844. **Cyclic Shift Hash** – Fast string hashing combining bitwise rotation and XOR operations. → skip: implementable, but too specialised for the standard library
845. **Interleaved Bit Multiplication (Morton Coding)** – Interleaving bits of multidimensional coordinates to generate Z-order curve keys. → `e.algo.geom.morton_encode`
846. **De Bruijn Bitscan** – Locating least significant set bit indices using precomputed De Bruijn lookup tables. → skip: an implementation detail of an existing module, not an API
847. **Bitwise Subset Traversal** – Iterating through all valid bitmask sub-combinations using sub = (sub - 1) & mask . → `e.algo.combin.subsets_of_mask`
848. **Sign Extension** – Expanding signed integer width while preserving sign bit values across bit boundaries. → `e.bytes.sign_extend`
849. **Log2 of Integer (Bitwise)** – Finding integer binary logarithm via leading zero counts or bitwise shifts. → `e.bytes.ilog2`
850. **Symmetric Bit Swap** – Swapping non-overlapping bit ranges within integers using bitmasks. → `e.bytes.swap_bits`
851. **Masked Bit Clear** – Unsetting specific bit ranges using inverted bitmasks ( x & ~mask ). → skip: pedagogical only
852. **Non-Zero Byte Detection (SWAR)** – Detecting zero bytes within 32/64-bit integer words without byte-by-byte loops. → `e.bytes.has_zero_byte`
853. **Galois Field Addition / Multiplication** – Arithmetic operations over GF(28) used in AES and Reed-Solomon coding. → `e.math.gf.mul`
854. **Reed-Solomon Error Correction** – Non-binary error-correcting code constructing polynomials over finite fields. → `e.algo.ecc.reed_solomon_decode`
855. **BCH Code Decoding (Berlekamp-Massey)** – Decoding binary error-correcting codes to fix multi-bit corruption. → `e.algo.ecc.bch_decode`
856. **Viterbi Algorithm** – Dynamic programming decoding optimal state sequences in Hidden Markov Models and convolutional codes. → `e.algo.ecc.viterbi_decode`
857. **Fano Algorithm** – Sequential decoding heuristic for convolutional error-correcting codes. → skip: implementable, but too specialised for the standard library
858. **Turbo Codes Iterative Decoding** – Soft-decision parallel concatenated convolutional decoding. → skip: implementable, but too specialised for the standard library
859. **LDPC Belief Propagation** – Message-passing algorithm over Tanner graphs decoding Low-Density Parity-Check codes. → `e.algo.ecc.ldpc_decode`
860. **Hamming (7,4) Error Correction** – Linear error-correcting code detecting and correcting single-bit errors. → `e.algo.ecc.hamming_decode`

## 13. Databases, Indexing & Storage Engine Operations (861–900)

861. **B-Tree Range Search** – Traversing node page bounds to extract entries within key intervals. → `e.db.storage.btree_range`
862. **B+ Tree Leaf Splitting** – Dividing full leaf nodes and inserting median keys into parent nodes. → see #191 (`e.data.btree.split_node`)
863. **LSM-Tree MemTable Flush** – Writing in-memory skiplists/trees to disk as immutable SSTables. → `e.db.storage.memtable_flush`
864. **SSTable Block Binary Search** – Searching block offset indexes to locate key positions on disk. → `e.db.storage.sstable_find`
865. **Write-Ahead Log Appending** – Sequential append-only logging of transaction operations prior to page updates. → see #718 (`e.db.storage.wal_append`)
866. **Buffer Pool Clock Eviction** – LRU-approximation page eviction managing cached disk blocks in memory. → `e.db.storage.buffer_pool_evict`
867. **Checkpoint Recovery Sweep** – Flushed dirty page logging enabling fast database crash recovery. → see #719 (`e.db.storage.recover`)
868. **Strict Two-Phase Locking (SS2PL)** – Concurrency control holding all exclusive locks until transaction commit. → `e.db.storage.txn_lock_2pl`
869. **Optimistic Concurrency Control (OCC)** – Validating read/write sets prior to commit to avoid locking overhead. → `e.db.storage.txn_occ`
870. **Multi-Version Concurrency Control (MVCC)** – Maintaining versioned tuples allowing non-blocking reads. → `e.db.storage.txn_mvcc`
871. **Snapshot Isolation Sweep** – Reading tuple states matching specific transaction start timestamps. → skip: an implementation detail of an existing module, not an API
872. **Extendible Hash Indexing** – Dynamic hash tables expanding directory depth without rehashing entire datasets. → `e.db.storage.hash_index_extendible`
873. **Linear Hashing** – Dynamic hash table growing incrementally page by page. → `e.db.storage.hash_index_linear`
874. **R-Tree Spatial Bounding Box Search** – Finding spatial objects intersecting target query bounding boxes. → `e.data.spatial.rtree_search`
875. **Inverted Index Construction** – Mapping tokenized terms to sorted posting lists of document IDs. → `e.text.index.build`
876. **Posting List Compression (Elias-Fano)** – Quasi-succinct encoding storing sorted integer lists in minimal space. → `e.text.index.postings_elias_fano`
877. **Nested Loop Join** – Simple relational join evaluating matching conditions for every outer/inner row pair. → `e.db.query.join_nested_loop`
878. **Hash Join** – Building in-memory hash tables on smaller relations and scanning larger relations to join. → `e.db.query.join_hash`
879. **Sort-Merge Join** – Sorting both join inputs on key columns and merging matching streams concurrently. → `e.db.query.join_sort_merge`
880. **Semi-Join Optimization** – Returning rows from outer table that have at least one match in inner table. → `e.db.query.join_semi`
881. **Anti-Join Execution** – Returning rows from outer table that have zero matches in inner table. → `e.db.query.join_anti`
882. **Predicate Pushdown** – Query optimizer rule moving filter conditions down logical plans closer to data sources. → `e.db.query.push_predicates`
883. **Projection Pushdown** – Discarding unused relation attributes early in physical query execution plans. → `e.db.query.push_projections`
884. **Common Table Expression (CTE) Materialization** – Executing temporary query sub-expressions once and caching outputs. → `e.db.query.materialize_cte`
885. **Volcano Iterator Model** – Volcano-style query processing calling open() , next() , and close() on plan operators. → `e.db.query.iterator`
886. **Vectorized Query Execution** – Processing database tuples in columnar batches using SIMD execution loops. → `e.db.query.vectorized`
887. **JIT Query Compilation (LLVM)** – Compiling query plans into native machine code to eliminate virtual dispatch overhead. → skip: implementable, but too specialised for the standard library
888. **Spatial Range Query (Quadtree)** – Querying bounding boxes in 2D quadtree structures recursively. → `e.data.spatial.quadtree_range`
889. **B-Tree Right-Sibling Pointer Traversal** – Scanning contiguous leaf pages sequentially in B+ trees. → `e.db.storage.btree_next_leaf`
890. **Write-Ahead Log Truncation** – Safely dropping log segments older than the active checkpoint. → `e.db.storage.wal_truncate`
891. **Dynamic Predicate Pushdown** – Injecting dynamic runtime Bloom filters into join build phases. → see #882 (`e.db.query.push_predicates`)
892. **Star Join Optimization** – Multi-table join plan optimization targeting data warehouse star schemas. → skip: implementable, but too specialised for the standard library
893. **Partition Pruning** – Query engine rule skipping table partitions outside filter ranges. → `e.db.query.prune_partitions`
894. **Parallel Hash Join Split** – Partitioning build and probe tables across parallel worker threads. → `e.db.query.join_hash_parallel`
895. **Page Compaction (Vacuuming)** – Reclaiming dead tuple slots within database storage pages. → `e.db.storage.vacuum`
896. **Sparse Index Lookup** – Locating key blocks in sorted data files using subset offset indices. → `e.db.storage.index_sparse`
897. **Dense Index Lookup** – Locating exact tuple record pointers using full key index records. → `e.db.storage.index_dense`
898. **Covering Index Scan** – Fulfilling query attribute requests entirely from index pages without table lookups. → `e.db.query.index_only_scan`
899. **Bitmap Index Scan** – Performing bitwise AND/OR operations over attribute bitmasks before tuple retrieval. → `e.db.storage.index_bitmap`
900. **Trie-Based Prefix Index Traversal** – Matching variable-length string keys using character edge transitions. → `e.data.trie.prefix_iter`

## 14. Distributed Protocols, Networking & Infrastructure (901–940)

901. **Token Bucket Traffic Shaping** – Controlling request rates by releasing tokens into queues at fixed speeds. → see #705 (`e.ratelimit.token_bucket`)
902. **Leaky Bucket Rate Limiting** – Smoothly discharging bursts of incoming network packets at constant rates. → see #706 (`e.ratelimit.leaky_bucket`)
903. **Sliding Window Protocol** – Reliable network packet transmission managing unacknowledged sender/receiver frames. → `e.net.reliable.sliding_window`
904. **Selective Repeat ARQ** – Automatic Repeat Request protocol retransmitting only corrupted or lost packets. → `e.net.reliable.selective_repeat`
905. **Nagle's Algorithm** – TCP optimization combining small outgoing messages into single TCP segments. → skip: OS kernel internals
906. **Jacobson's RTT Estimation** – Computing TCP round-trip times and retransmission timeouts using smooth variance tracking. → `e.net.reliable.rtt_estimate`
907. **Karn's Algorithm** – Preventing ambiguous TCP retransmission measurements when updating RTT estimates. → `e.net.reliable.rtt_karn`
908. **Consistent Hashing Ring Lookup** – Mapping keys to closest node tokens on virtual hash rings. → see #255 (`e.algo.consistent_hash.ring_lookup`)
909. **Rendezvous Hashing (HRW)** – Selecting target nodes maximizing pseudo-random weight functions per key. → see #256 (`e.algo.consistent_hash.rendezvous`)
910. **Chord Distributed Lookup** – Routing DHT queries across O(log N) finger table node shortcuts. → see #130 (`e.dist.dht.chord_lookup`)
911. **Kademlia Node Lookup** – DHT node discovery calculating target distance using bitwise XOR metrics. → see #131 (`e.dist.dht.kademlia_lookup`)
912. **Raft Consensus Replication** – Leader-driven log entry appending and commit index advancement. → `e.dist.consensus.raft_replicate`
913. **Paxos Multi-Prepare** – Two-phase consensus achieving agreement on sequence series of values. → see #135 (`e.dist.consensus.paxos`)
914. **Gossip State Dissemination** – Epidemic peer-to-peer state propagation sharing node rumors randomly. → see #142 (`e.dist.gossip.disseminate`)
915. **Vector Clock Causality Tracking** – Updating vector clock arrays to detect concurrent updates vs causal ordering. → see #148 (`e.dist.clock.vector`)
916. **Lamport Logical Clock Sync** – Ordering distributed events using monotonically increasing scalar counters. → see #147 (`e.dist.clock.lamport`)
917. **Bully Election Algorithm** – Highest-rank node asserting cluster leadership upon detecting leader failure. → see #143 (`e.dist.election.bully`)
918. **Ring Election Algorithm** – Token-passing ring network election gathering active node IDs. → see #144 (`e.dist.election.ring`)
919. **Chandy-Lamport Global Snapshot** – Recording distributed global states without freezing system execution. → see #152 (`e.dist.snapshot.chandy_lamport`)
920. **Two-Phase Commit (2PC)** – Coordinating distributed database transactions via Prepare and Commit phases. → see #720 (`e.dist.commit.two_phase`)
921. **Three-Phase Commit (3PC)** – Non-blocking distributed transaction commit protocol introducing Pre-Commit states. → `e.dist.commit.three_phase`
922. **Saga Pattern Choreography** – Distributed event-driven transaction execution using local compensations. → `e.dist.commit.saga_choreography`
923. **Saga Pattern Orchestration** – Central coordinator directing service steps and triggering rollback compensations. → `e.dist.commit.saga_orchestrate`
924. **Circuit Breaker State Transition** – Tripping service calls upon fault threshold breaches to allow recovery. → see #710 (`e.resilience.circuit_breaker`)
925. **Health Check Heartbeat Sweep** – Pinging cluster nodes periodically to detect offline instances. → see #715 (`e.resilience.heartbeat`)
926. **Distributed Tracing Span Propagation** – Injecting trace/span contexts into HTTP/RPC request headers. → see #716 (`e.trace.propagate`)
927. **Gossip-Based Failure Detector (Phi Accrual)** – Continuous probabilistic evaluation of node availability. → `e.dist.failure_detector.phi_accrual`
928. **Jump Consistent Hash** – Fast O(1) memory consistent hash algorithm mapping keys to buckets. → `e.algo.consistent_hash.jump`
929. **Load Shedding Drop Protocol** – Discarding low-priority traffic when service CPU/memory saturation triggers. → `e.resilience.load_shed`
930. **Slow Start (TCP Congestion Control)** – Exponentially expanding TCP congestion windows until loss or thresholds occur. → skip: OS kernel internals
931. **Congestion Avoidance (TCP AIMD)** – Additive Increase Multiplicative Decrease adjustment of TCP window sizes. → skip: OS kernel internals
932. **Fast Retransmit / Fast Recovery** – Retransmitting lost TCP packets upon receiving three duplicate ACKs. → skip: OS kernel internals
933. **Distributed Lock Renewal (Redlock)** – Acquiring time-bounded distributed locks across majority independent instances. → `e.dist.lock.redlock`
934. **Merkle Tree Anti-Entropy Sync** – Comparing hash tree branches between nodes to identify out-of-sync key ranges. → `e.dist.anti_entropy.merkle_sync`
935. **Read Repair Mechanism** – Background sync updating stale replica nodes when read operations detect inconsistency. → `e.dist.replica.read_repair`
936. **Hinted Handoff Execution** – Storing write operations locally for offline target nodes and replaying upon reconnect. → `e.dist.replica.hinted_handoff`
937. **Quorum Read/Write Evaluation** – Validating distributed consistency where R + W > N. → `e.dist.replica.quorum`
938. **Consistent Hash Virtual Node Placement** – Mapping physical hardware onto multiple virtual hash ring tokens to equalize load. → `e.algo.consistent_hash.virtual_nodes`
939. **Gossip Membership List Exchange** – Periodic pairwise state swaps updating cluster membership tables. → `e.dist.gossip.membership`
940. **Distributed Deadlock Detection (Wait-For Graph)** – Detecting cycles in distributed resource allocation dependency graphs. → `e.dist.deadlock.wait_for_graph`

## 15. General Utilities, Validation, Randomness & Core Functions (941–1000)

941. **Fisher-Yates (Durstenfeld) Shuffle** – Generating unbiased random permutations of arrays in O(N) time. → see #57 (`e.algo.rand.shuffle`)
942. **Reservoir Sampling** – Uniformly sampling k items from continuous data streams of unknown length. → see #59 (`e.algo.rand.reservoir`)
943. **Alias Method (Walker's)** – Generating random variates from discrete probability distributions in O(1) time. → see #60 (`e.algo.rand.alias_table`)
944. **Linear Congruential Generator (LCG)** – Pseudorandom number generator using modular linear equations (X = (aX + c) (mod m)). n+1 n → `e.algo.rand.lcg`
945. **Mersenne Twister (MT19937)** – High-period (219937 − 1) pseudorandom number generator based on linear recurrences. → `e.algo.rand.mt19937`
946. **Xorshift PRNG** – Fast pseudorandom number generation using repeated bitwise shifts and XOR operations. → `e.algo.rand.xorshift`
947. **PCG Random Number Generator** – Permuted Congruential Generator applying output permutation functions to LCG states. → `e.algo.rand.pcg64`
948. **Luhn Algorithm** – Modulo 10 checksum formula validating identification numbers (credit cards, IMEI). → `e.valid.luhn`
949. **ISBN-13 Checksum Validation** – Validating 13-digit book identifiers using alternating 1 and 3 weight multipliers. → `e.valid.isbn13`
950. **IBAN Validation Algorithm** – Validating International Bank Account Numbers using modulo 97 arithmetic. → `e.valid.iban`
951. **EAN-13 Barcode Verification** – Checking parity weighted checksums for global commercial barcodes. → `e.valid.ean13`
952. **CIDR Subnet Masking** – Calculating network/broadcast IP addresses and valid host ranges from bitmask lengths. → `e.net.cidr_contains`
953. **IPv6 Address Compression / Expansion** – Normalizing IPv6 address strings handling zero-block contractions ( :: ). → `e.net.format_ip`
954. **UUID v4 Generation** – Constructing 128-bit cryptographically secure random Universally Unique Identifiers. → `e.algo.uuid.v4`
955. **UUID v5 Namespace Hashing** – Generating deterministic UUIDs using SHA-1 hashing over namespace and name strings. → `e.algo.uuid.v5`
956. **Snowflake ID Generation** – Generating 64-bit unique IDs composed of timestamp, worker ID, and sequence counters. → `e.algo.uuid.snowflake`
957. **ULID Generation** – Universally Unique Lexicographically Sortable Identifiers combining millisecond timestamps and randomness. → `e.algo.uuid.ulid`
958. **Nanoid Generation** – Compact, URL-friendly unique string generation using secure random bytes. → `e.algo.uuid.nanoid`
959. **Semantic Versioning (SemVer) Parser** – Parsing and comparing MAJOR.MINOR.PATCH version string rules. → `e.fmt.semver.parse`
960. **Cron Expression Parser** – Parsing 5/6-field schedule expressions to compute next runtime execution timestamps. → `e.time.cron.parse`
961. **Interval Overlap Detection** – Checking intersection conditions between two time intervals (Start_A < End_B ∧ Start_B < End_A). → `e.time.intervals_overlap`
962. **Zeller's Congruence** – Calculating day of the week for any Julian or Gregorian calendar date. → `e.time.calendar.weekday`
963. **Julian Day Number Calculation** – Mapping calendar dates into continuous count of days since epoch start. → `e.time.calendar.julian_day`
964. **ISO 8601 Date Parser** – Parsing standardized date-time strings into unix epoch timestamps. → `e.time.parse_iso8601`
965. **HTML Entity Encoder / Decoder** – Translating special reserved characters to/from HTML named or numeric entities. → `e.fmt.html.escape`
966. **CSV Tokenizer** – Parsing comma-separated values respecting quoted fields, escaped quotes, and newlines. → `e.fmt.csv.reader`
967. **Levenshtein Matrix Alignment** – Constructing edit distance tables to extract actual insertion/deletion/substitution steps. → see #301 (`e.text.distance.levenshtein`)
968. **Soundex Phonetic Encoder** – Mapping English words to 4-character codes based on phonetic consonant categories. → see #312 (`e.text.phonetic.soundex`)
969. **Base64 Stream Encoder** – Converting binary byte buffers into printable 64-character ASCII strings. → `e.bytes.base64_encoder`
970. **Base64 Stream Decoder** – Unpacking Base64 ASCII text back into raw binary buffers. → `e.bytes.base64_decoder`
971. **Hexadecimal String Encoder** – Converting raw bytes to lowercase/uppercase two-character hex strings. → `e.bytes.hex_encode`
972. **URL Query String Builder** – Serializing key-value dictionary objects into URL-encoded parameter strings. → `e.fmt.uri.query_build`
973. **URL Query String Parser** – Deconstructing query parameter strings into key-value map structures. → `e.fmt.uri.query_parse`
974. **Diff Match Patch** – Computing line/character text differences and applying patch operations cleanly. → `e.text.diff.patch`
975. **CRC32 Table-Driven Calculation** – Accelerating 32-bit cyclic redundancy check calculations using 256-entry lookup tables. → see #570 (`e.algo.hash.crc32`)
976. **Adler-32 Checksum Engine** – Fast 32-bit checksum computation updating s1 and s2 rolling sums. → see #569 (`e.algo.hash.adler32`)
977. **MD5 Digest Computation** – Computing legacy 128-bit hashes over 512-bit message blocks. → see #563 (`e.crypto.hash.legacy_md5`)
978. **Floyd's Cycle Finding (Tortoise and Hare)** – O(1) memory pointers detecting cycles in linked lists or state sequences. → `e.algo.search.cycle_floyd`
979. **Brent's Cycle Finding** – Cycle detection using moving power-of-two teleporters running faster than Floyd's algorithm. → `e.algo.search.cycle_brent`
980. **Misra-Gries Heavy Hitters** – Finding items appearing more than N/k times in streaming data. → see #245 (`e.algo.sketch.misra_gries`)
981. **Flajolet-Martin Count** – Estimating number of distinct elements using trailing zero bit counts of hashed values. → `e.algo.sketch.flajolet_martin`
982. **Reservoir Sampling with Weights (A-Res)** – Weighted random sampling from streams using priority keys (U1/w). → `e.algo.rand.reservoir_weighted`
983. **Linear Counting Algorithm** – Cardinality estimation algorithm for datasets with low to medium distinct counts. → `e.algo.sketch.linear_counting`
984. **Exponential Decay Moving Average** – Time-weighted running average giving higher precedence to recent observations. → see #795 (`e.dsp.ema`)
985. **Topological Sort (Kahn's)** – In-degree tracking algorithm ordering directed acyclic graphs linearly. → see #73 (`e.algo.graph.topological`)
986. **Tarjan's Off-Line LCA Algorithm** – Finding lowest common ancestors for offline node pairs using disjoint sets during DFS. → `e.algo.graph.tree.lca_offline`
987. **Prüfer Code Generation** – Converting labeled trees into compact sequence representations. → see #88 (`e.algo.graph.tree.prufer_encode`)
988. **Stern-Brocot Tree Binary Search** – Representing all positive irreducible rational numbers using binary tree traversals. → `e.math.ntheory.stern_brocot_search`
989. **Farey Sequence Generation** – Generating ordered sequences of completely reduced fractions between 0 and 1. → `e.math.ntheory.farey`
990. **Fast Matrix Exponentiation** – Computing AN in O(M3 log N) time to solve linear recurrence relations. → see #510 (`e.algo.linalg.matrix.pow`)
991. **Strassen's Submatrix Multiplication** – Divide-and-conquer algorithm multiplying 2 × 2 submatrices using 7 multiplications instead of 8. → skip: an implementation detail of an existing module, not an API
992. **Coppersmith-Winograd Algorithm** – Theoretical fast matrix multiplication algorithm running in O(N2.3754). → skip: research-grade, no settled practical implementation
993. **Probing Sequence Generation** – Calculating secondary probe offsets in hash tables (Linear, Quadratic, Double Hashing). → skip: an implementation detail of an existing module, not an API
994. **Hopcroft-Karp Bipartite Matching** – O(E √V) maximum cardinality matching algorithm in bipartite graphs. → see #78 (`e.algo.graph.match.hopcroft_karp`)
995. **Hierholzer's Eulerian Circuit Finding** – Constructing Eulerian paths in O(E) time by splicing sub-tours. → see #80 (`e.algo.graph.euler_path`)
996. **Bron-Kerbosch Maximal Clique Search** – Recursive algorithm finding maximal cliques in undirected graphs. → see #104 (`e.algo.graph.max_cliques`)
997. **Johnson's All-Pairs Shortest Path** – Reweighting edge costs via Bellman-Ford to run Dijkstra from all vertices safely. → see #72 (`e.algo.graph.johnson`)
998. **A Pathfinding Heuristic Evaluation*** – Combining path costs (g(n)) and estimated distance (h(n)) to navigate weighted graphs. → see #65 (`e.algo.graph.path.astar`)
999. **Floyd-Warshall Shortest Path** – Dynamic programming algorithm computing all-pairs shortest paths in O(V 3). → see #66 (`e.algo.graph.floyd_warshall`)
1000. **Quickselect Selection Algorithm** – Partition-based selection finding k-th smallest elements in unsorted arrays in expected O(N) time. do another 250 → see #32 (`e.algo.search.kth`)

## 16. Quantum Computing, Physics & Scientific Simulation (1001–1050)

1001. **Quantum Fourier Transform (QFT)** – Quantum analogue of the discrete Fourier transform mapping state vectors into frequency bases in O((log N)2) gates. → skip: needs quantum hardware or a simulator
1002. **Shor's Algorithm** – Polynomial-time quantum algorithm for integer factorization using quantum period-finding. → skip: needs quantum hardware or a simulator
1003. **Grover's Search Algorithm** – Quadratic quantum speedup searching unstructured databases in O(√N) iterations. → skip: needs quantum hardware or a simulator
1004. **Variational Quantum Eigensolver (VQE)** – Hybrid quantum-classical algorithm estimating ground state energies of quantum system Hamiltonians. → skip: needs quantum hardware or a simulator
1005. **Quantum Approximate Optimization Algorithm (QAOA)** – Variational quantum algorithm solving combinatorial optimization problems on NISQ devices. → skip: needs quantum hardware or a simulator
1006. **Deutsch-Jozsa Algorithm** – Deterministic quantum algorithm evaluating whether black-box functions are constant or balanced in a single query. → skip: needs quantum hardware or a simulator
1007. **Bernstein-Vazirani Algorithm** – Quantum algorithm determining hidden binary bitstrings in a single oracle query. → skip: needs quantum hardware or a simulator
1008. **Simon's Algorithm** – Exponentially faster quantum algorithm discovering hidden periodic XOR masks. → skip: needs quantum hardware or a simulator
1009. **Quantum Phase Estimation (QPE)** – Estimating the eigenphase of a unitary operator given its eigenvector state. → skip: needs quantum hardware or a simulator
1010. **BB84 Protocol** – Quantum key distribution protocol detecting eavesdropping via quantum state collapse. → skip: needs quantum hardware or a simulator
1011. **E91 Protocol (Ekert91)** – Quantum key distribution relying on entangled photon pairs and Bell inequality testing. → skip: needs quantum hardware or a simulator
1012. **Quantum Teleportation Protocol** – Transmitting quantum states across arbitrary distances using shared entanglement and classical communication. → skip: needs quantum hardware or a simulator
1013. **Superdense Coding** – Transmitting two classical bits of information using a single transmitted qubit and shared entanglement. → skip: needs quantum hardware or a simulator
1014. **Shor's 9-Qubit Code** – Quantum error correction encoding one logical qubit into nine physical qubits to protect against arbitrary single-qubit errors. → skip: needs quantum hardware or a simulator
1015. **Surface Code Error Correction** – Topological quantum error correction topology executing 2D nearest-neighbor stabilizer measurements. → skip: needs quantum hardware or a simulator
1016. **Harrow-Hassidim-Lloyd (HHL) Algorithm** – Solving linear systems of equations Ax = b on quantum computers in logarithmic time relative to matrix size. → skip: needs quantum hardware or a simulator
1017. **Quantum Walk** – Quantum mechanics analogue of classical random walks exhibiting quadratic space-time propagation spread. → skip: needs quantum hardware or a simulator
1018. **Velocity Verlet Integration** – Second-order symplectic numerical integrator calculating position and velocity vectors in molecular dynamics. → `e.math.ode.verlet`
1019. **Leapfrog Integration** – Symplectic integrator stepping positions and velocities at interleaved half-time steps. → `e.math.ode.leapfrog`
1020. **Runge-Kutta 4th Order (RK4)** – Fourth-order numerical integration method solving ordinary differential equations using slope weighted averages. → `e.math.ode.rk4`
1021. **Euler-Maruyama Method** – Stochastic numerical method approximating solutions to stochastic differential equations (SDEs). → `e.math.ode.euler_maruyama`
1022. **Metropolis-Hastings MCMC** – Markov Chain Monte Carlo sampling drawing samples from probability distributions using proposal acceptance ratios. → `e.math.mcmc.metropolis_hastings`
1023. **Gibbs Sampling** – MCMC algorithm sampling multivariate distributions by updating one parameter conditioned on all others sequentially. → `e.math.mcmc.gibbs`
1024. **Hamiltonian Monte Carlo (HMC)** – MCMC algorithm using gradient-based molecular dynamics trajectories to propose distant state moves efficiently. → `e.math.mcmc.hmc`
1025. **No-U-Turn Sampler (NUTS)** – Automated extension of HMC eliminating manual path length tuning by building recursive binary trees. → `e.math.mcmc.nuts`
1026. **Particle-in-Cell (PIC) Method** – Simulating plasma and fluid dynamics by tracking discrete particles on Eulerian spatial grids. → skip: domain simulation outside a general library
1027. **Lattice Boltzmann Method (LBM)** – Fluid dynamics simulation modeling particle density distributions on discrete lattice grids. → skip: domain simulation outside a general library
1028. **Finite Element Method (FEM) Assembly** – Discretizing continuous physical fields into mesh element matrices to solve partial differential equations. → skip: domain simulation outside a general library
1029. **Finite-Difference Time-Domain (FDTD)** – Maxwell's equation solver grid-discretizing electric and magnetic fields in time and space. → skip: domain simulation outside a general library
1030. **Smoothed Particle Hydrodynamics (SPH)** – Meshfree Lagrangian method simulating fluid movement using smoothed particle kernel sums. → `e.game.physics.sph`
1031. **Fast Multipole Method (FMM)** – Accelerating N-body potential interactions from O(N2) to O(N) via multipole expansion tree structures. → skip: domain simulation outside a general library
1032. **Barnes-Hut Algorithm** – O(N log N) approximation for N-body simulation grouping distant particles using octrees. → `e.algo.geom3.barnes_hut`
1033. **Direct Simulation Monte Carlo (DSMC)** – Probabilistic gas dynamics method modeling rarefied gas flows using collisions among representative particles. → skip: domain simulation outside a general library
1034. **Kohn-Sham Density Functional Theory** – Quantum mechanical modeling method solving non-interacting electronic orbital equations. → skip: domain simulation outside a general library
1035. **Hartree-Fock Method** – Approximation method calculating molecular electronic structures via Slater determinant wavefunctions. → skip: domain simulation outside a general library
1036. **Diffusion Quantum Monte Carlo (DMC)** – Projecting ground state wavefunctions using imaginary-time Schrödinger equation propagation. → skip: domain simulation outside a general library
1037. **Continuous-Time Quantum Monte Carlo (CT-QMC)** – Exact quantum impurity solver evaluating Feynman diagram expansions. → skip: domain simulation outside a general library
1038. **Tensor Network Contraction (MPS / PEPS)** – Compressing quantum multi-body states into low-rank tensor chains and grids. → skip: domain simulation outside a general library
1039. **Density Matrix Renormalization Group (DMRG)** – Variational tensor network method calculating low-energy states of 1D quantum lattice systems. → skip: domain simulation outside a general library
1040. **Quantum Amplitude Estimation** – Estimating quantum state probability amplitudes with quadratic speedup over Monte Carlo sampling. → skip: needs quantum hardware or a simulator
1041. **Quantum Counting Algorithm** – Combining Grover search and Quantum Phase Estimation to count solutions in unstructured search spaces. → skip: needs quantum hardware or a simulator
1042. **Quantum Singular Value Transformation (QSVT)** – Unified framework applying polynomial transformations to singular values of block-encoded matrices. → skip: needs quantum hardware or a simulator
1043. **Variational Quantum Classifier (VQC)** – Supervised quantum machine learning model encoding data into quantum states and optimizing parameter gates. → skip: needs quantum hardware or a simulator
1044. **Quantum State Tomography** – Reconstructing unknown quantum state density matrices from sets of quantum measurements. → skip: needs quantum hardware or a simulator
1045. **Quantum Process Tomography** – Complete experimental characterization of unknown quantum channels and gate operations. → skip: needs quantum hardware or a simulator
1046. **Parameter Shift Rule** – Computing exact analytical gradients of parameterized quantum circuits on physical hardware. → skip: needs quantum hardware or a simulator
1047. **Symplectic Integrator (Yoshida Integration)** – High-order geometric integrator conserving total energy phase-space invariants in classical mechanics. → `e.math.ode.yoshida`
1048. **Multigrid Method (V-Cycle / W-Cycle)** – Solving PDE linear systems across hierarchical grid resolutions to accelerate convergence. → `e.algo.linalg.matrix.multigrid`
1049. **Fast Marching Method** – O(N log N) numerical algorithm solving Eikonal boundary value wave arrival time equations. → `e.gfx.filter.fast_marching`
1050. **Fast Sweeping Method** – Iterative grid algorithm solving Eikonal equations using alternating Gauss-Seidel spatial sweeps. → `e.gfx.filter.fast_sweeping`

## 17. Advanced Data Structures & Succinct Structures (1051–1100)

1051. **Succinct Rank / Select Operations** – Supporting O(1) count queries for k-th set bits in compressed bitvectors using auxiliary block structures. → `e.data.succinct.rank`
1052. **LOUDS Tree Encoding** – Level-Order Unary Degree Sequence representing arbitrary N-node tree topologies in 2N + O(1) bits. → `e.data.succinct.louds`
1053. **BP (Balanced Parentheses) Succinct Tree** – Representing tree hierarchies using balanced bracket sequences with O(1) navigation operations. → `e.data.succinct.balanced_parens`
1054. **Wavelet Tree** – Compact data structure supporting range quantile, rank, and select queries over arbitrary alphabets in O(log Σ) time. → `e.data.succinct.wavelet_tree`
1055. **Compressed Suffix Array (CSA)** – Text indexing structure reducing suffix array memory usage down to empirical text entropy bounds. → `e.data.succinct.compressed_suffix_array`
1056. **FM-Index Search** – Combining Burrows-Wheeler Transform and rank operations for fast string pattern matching in compressed text space. → `e.data.succinct.fm_index`
1057. **Compressed Suffix Tree (CST)** – Succinct data structure supporting full suffix tree operations using O(N log Σ) bits. → skip: implementable, but too specialised for the standard library
1058. **Dynamic Wavelet Matrix** – Variant of wavelet trees optimizing rank/select queries over large dynamically changing alphabets. → skip: implementable, but too specialised for the standard library
1059. **X-Fast Trie** – Bitwise trie combined with hash tables providing O(log w) successor queries for w-bit keys. → skip: implementable, but too specialised for the standard library
1060. **Y-Fast Trie** – Indirection structure combining x-fast tries with balanced BSTs to achieve O(log w) queries in O(N) space. → skip: implementable, but too specialised for the standard library
1061. **Fusion Tree** – w-wide tree structure achieving O(log N) searching time using w parallel bit comparison operations. → skip: research-grade, no settled practical implementation
1062. **Exponential Tree** – Search tree structure converting static search algorithms into dynamic implementations. → skip: research-grade, no settled practical implementation
1063. **Tango Tree** – Self-adjusting BST providing O(log log N) competitive ratio against optimal offline access sequences. → skip: research-grade, no settled practical implementation
1064. **Splay-Tree Multisplay Engine** – Multi-dimensional splay tree variant maintaining dynamic structural bounds. → skip: research-grade, no settled practical implementation
1065. **Link-Cut Tree** – Dynamic tree structure maintaining collections of rooted trees supporting path updates and link/cut operations in O(log N) time. → `e.data.link_cut.link`
1066. **Euler Tour Tree** – Dynamic graph structure tracking tree connectivity via Euler tour sequences over dynamic edge changes. → `e.data.link_cut.euler_tour_tree`
1067. **Top Tree** – Abstract data structure maintaining dynamic tree properties using recursive path and tree decompositions. → skip: implementable, but too specialised for the standard library
1068. **Kinetic Heap** – Priority queue structure maintaining dynamic priorities governed by continuous time functions. → skip: implementable, but too specialised for the standard library
1069. **Persistent Segment Tree** – Fully persistent segment tree maintaining all historical versions after updates in O(log N) time per change. → see #199 (`e.data.segment_tree.persistent_update`)
1070. **Fully Persistent Treap** – Search tree preserving functional immutability and complete revision history via node copying. → `e.data.treap.persistent_insert`
1071. **Retroactive Priority Queue** – Data structure allowing inserting, deleting, or Modifying historical queue operations at past time steps. → skip: implementable, but too specialised for the standard library
1072. **Priority R-Tree** – Worst-case optimal spatial index tree maintaining bounding boxes with O( N + K) query performance. → skip: implementable, but too specialised for the standard library
1073. **Hilbert R-Tree** – Spatial R-tree variant sorting bounding box centroids along space-filling Hilbert curves. → `e.data.spatial.rtree_hilbert`
1074. **Range Tree with Fractional Cascading** – Multi-dimensional search structure reducing range search query times to O(log N + K). → `e.data.spatial.range_tree`
1075. **Interval Tree with Fractional Cascading** – Accelerating 2D range overlap queries by maintaining pointers between adjacent coordinate lists. → see #224 (`e.data.spatial.interval_overlap`)
1076. **Disjoint Set Union with Path Halving** – Optimization of DSU skipping every other parent node during path traversal. → `e.algo.disjoint_set.find`
1077. **Randomized Meldable Heap** – Priority queue allowing O(log N) expected heap merging via random node swaps. → `e.data.heap.meldable`
1078. **Brodal Queue** – Heap structure offering O(1) worst-case push/meld and O(log N) delete-min bounds. → skip: research-grade, no settled practical implementation
1079. **Soft Heap** – Priority queue achieving O(1) amortized bounds by corrupting values of a small fraction of keys. → skip: research-grade, no settled practical implementation
1080. **Strict Fibonacci Heap** – Heap variant achieving worst-case O(1) insertion/decrease-key and O(log N) deletion bounds. → skip: research-grade, no settled practical implementation
1081. **Pairing Heap (Lazy Variant)** – Self-adjusting heap variant postponing tree restructuring until explicit deletion calls. → `e.data.heap.pairing_merge`
1082. **Hollow Heap** – Simple heap structure matching Fibonacci heap bounds using DAG-based hollow node tags. → skip: research-grade, no settled practical implementation
1083. **Van Emde Boas Tree** – Bit-vector search tree supporting predecessor/successor queries in O(log log U) time. → skip: implementable, but too specialised for the standard library
1084. **Hash Array Mapped Trie (HAMT)** – Immutable array-mapped trie balancing key paths using bit-popcount branching. → `e.data.hamt.put`
1085. **Patricia Trie (Compressed Radix)** – Compact prefix tree merging single-child nodes to reduce memory footprints. → `e.data.trie.compact`
1086. **Cuckoo Filter** – Probabilistic set membership structure supporting item deletion using Cuckoo hashing tables. → see #240 (`e.algo.sketch.cuckoo_insert`)
1087. **XOR Filter** – Space-efficient probabilistic filter evaluating membership using three-way XOR lookup arrays. → `e.algo.sketch.xor_filter`
1088. **Binary Fuse Filter** – Fast probabilistic filter outperforming XOR filters in space efficiency and construction speed. → `e.algo.sketch.binary_fuse_filter`
1089. **Quotient Filter** – Probabilistic filter storing fingerprints in contiguous slotted hash tables to optimize cache locality. → see #241 (`e.algo.sketch.quotient_filter`)
1090. **Count-Min Sketch with Conservative Update** – Frequency estimation sketch ignoring updates when current cell estimates exceed minimum readings. → `e.algo.sketch.count_min_add_conservative`
1091. **Heavy-Keeper Algorithm** – Streaming algorithm using decay-based count tracking to locate top-k frequent items. → skip: implementable, but too specialised for the standard library
1092. **Space-Saving Algorithm** – Streaming algorithm maintaining fixed-size stream tables for stream frequency estimation. → see #246 (`e.algo.sketch.space_saving`)
1093. **t-Digest Quantile Sketch** – Data structure approximating online order-statistics and quantiles over streaming numeric data. → `e.algo.sketch.tdigest`
1094. **KLL Quantile Sketch** – Streaming algorithm providing provable rank-error guarantees for quantile estimation. → `e.algo.sketch.kll`
1095. **DDSketch** – Fully mergeable relative-error quantile sketch maintaining relative error bounds across extreme values. → `e.algo.sketch.ddsketch`
1096. **MinHash LSH Indexing** – Locality-Sensitive Hashing indexing Jaccard similarity between document set signatures. → `e.ml.ann.minhash_lsh`
1097. **SimHash Near-Duplicate Detection** – Cosine-distance LSH hashing multi-dimensional feature vectors into bit masks. → see #259 (`e.algo.sketch.simhash`)
1098. **Weight-Balanced Tree (BB[α])** – Self-balancing binary search tree maintaining balance ratios based on subtree node counts. → skip: an implementation detail of an existing module, not an API
1099. **Compressed Matrix Trie** – Succinct multi-dimensional array mapping multi-index structures into linear memory spaces. → skip: implementable, but too specialised for the standard library
1100. **R-S-Tree (Succinct B-Tree)** – Compressed internal node layout combining succinct bitvectors with standard B-tree branch structures. → skip: implementable, but too specialised for the standard library

## 18. Game Development, Physics Engines & Computer Graphics (1101–1150)

1101. **Percentage-Closer Filtering (PCF)** – Soft shadow anti-aliasing technique averaging depth comparison results across pixel grid samples. → `e.gfx.scene.shadow_pcf`
1102. **Cascaded Shadow Maps (CSM)** – Rendering multi-resolution shadow maps split across camera view frustum depth slices. → `e.gfx.scene.shadow_cascades`
1103. **Variance Shadow Maps (VSM)** – Fast shadow mapping technique storing depth and squared-depth moments to permit filtering. → skip: implementable, but too specialised for the standard library
1104. **Screen Space Ambient Occlusion (SSAO)** – Screen-space image effect approximating local ambient contact shadowing using depth buffer sampling. → `e.gfx.scene.ssao`
1105. **Horizon-Based Ambient Occlusion (HBAO)** – Raymarching depth buffers along horizon angle directions to generate realistic contact shadows. → see #1104 (`e.gfx.scene.ssao`)
1106. **Ground Truth Ambient Occlusion (GTAO)** – Physically-based ambient occlusion calculating closed-form visibility integrals over view horizons. → see #1104 (`e.gfx.scene.ssao`)
1107. **Screen Space Reflections (SSR)** – Tracing ray trajectories in screen-space depth buffers to evaluate specular surface reflections. → `e.gfx.scene.ssr`
1108. **Fast Approximate Anti-Aliasing (FXAA)** – Single-pass post-processing anti-aliasing algorithm smoothing high-contrast color edges. → `e.gfx.scene.fxaa`
1109. **Subpixel Morphological Anti-Aliasing (SMAA)** – Post-processing anti-aliasing detecting subpixel pattern shapes and blending weights. → skip: implementable, but too specialised for the standard library
1110. **Temporal Anti-Aliasing (TAA)** – Anti-aliasing technique combining jittered subpixel samples accumulated over consecutive rendered frames. → `e.gfx.scene.taa`
1111. **Deep Learning Super Sampling (DLSS)** – AI-driven temporal upscaling evaluating low-resolution frames and motion vectors. → skip: a trained ML model or training recipe
1112. **Clustered Forward Rendering** – Partitioning view frustums into 3D grid clusters to assign light lists for forward shading. → `e.gfx.scene.clustered_lights`
1113. **Deferred Shading G-Buffer Pass** – Decoupling geometry processing from lighting calculation by storing material properties in intermediate buffers. → `e.gfx.scene.deferred`
1114. **Ray Tracing Hardware BVH Traversal** – Stackless acceleration tree traversal evaluating ray-primitive intersections on GPU ray cores. → skip: hardware or circuit design
1115. **Path Tracing Next Event Estimation (NEE)** – Explicitly sampling light sources at path bounces to reduce Monte Carlo image noise. → `e.gfx.trace.next_event_estimation`
1116. **Multiple Importance Sampling (MIS)** – Combining surface BRDF sampling and light source sampling to minimize variance in path tracing. → `e.gfx.trace.multiple_importance`
1117. **Bidirectional Path Tracing (BDPT)** – Tracing eye paths from camera and light paths from sources, connecting path vertices in pairs. → skip: implementable, but too specialised for the standard library
1118. **ReSTIR (Reservoir-based Resampling)** – Spatiotemporal importance resampling tracking dynamic light contributions across light samples. → skip: implementable, but too specialised for the standard library
1119. **Position-Based Dynamics (PBD)** – Simulating physical systems (cloth, soft bodies) by modifying positions directly to satisfy geometric constraints. → `e.game.physics.pbd_step`
1120. **Extended Position-Based Dynamics (XPBD)** – PBD extension incorporating physical compliance constants independent of frame rates and iterations. → `e.game.physics.xpbd_step`
1121. **Material Point Method (MPM)** – Continuum mechanics solver combining Eulerian grids and particle representations for snow, mud, and sand. → skip: domain simulation outside a general library
1122. **Projected Gauss-Seidel Constraint Solver** – Iteratively computing impulse vectors to solve rigid body contact constraints. → `e.game.physics.solve_gauss_seidel`
1123. **Conservative Advancement CCD** – Continuous Collision Detection stepping time forward safely without penetrating fast-moving geometries. → `e.game.physics.ccd_conservative`
1124. **Sweep and Prune** – Broadphase collision detection algorithm sorting axis-aligned bounding box endpoints along principal axes. → `e.game.physics.sweep_and_prune`
1125. **Spatial Grid Broadphase** – Hashing object bounding boxes into fixed 3D grid buckets to isolate candidate collision pairs. → `e.game.collide2d.grid_insert`
1126. **FABRIK (Forward And Backward Reaching IK)** – Iterative inverse kinematics algorithm adjusting joint positions forwards and backwards along bone chains. → `e.game.anim.ik_fabrik`
1127. **Cyclic Coordinate Descent (CCD IK)** – Inverse kinematics optimization adjusting one joint angle at a time to align end effectors with target positions. → `e.game.anim.ik_ccd`
1128. **Dual Quaternion Skinning** – Character mesh animation solver eliminating artifact volume loss at bending joints ("candy wrapper" effect). → `e.game.anim.skin_dual_quaternion`
1129. **Linear Blend Skinning (LBS)** – Animating vertices by blending transformations across weighted joint hierarchies. → `e.game.anim.skin_linear_blend`
1130. **Recast Navigation Mesh Generation** – Voxelizing 3D geometry and extracting walkable polygon surface meshes for pathfinding. → `e.game.nav.build_navmesh`
1131. **Funnel Algorithm (String Pulling)** – Finding shortest straight paths across sequences of convex navigation mesh polygons. → `e.game.nav.funnel`
1132. **Flow Field Pathfinding** – Generating vector direction fields across spatial grids to navigate large crowds of agents toward goals. → `e.game.nav.flow_field`
1133. **Hierarchical Pathfinding (HPA)*** – Abstracting large grid maps into macro-node graphs to accelerate path searches. → `e.game.nav.hierarchical_astar`
1134. **Behavior Tree Traversal Engine** – Evaluating hierarchical Selector, Sequence, and Decorator nodes to manage game AI states. → `e.game.ai.behavior_tick`
1135. **Goal-Oriented Action Planning (GOAP)** – Searching action graphs using A* to generate optimal sequences fulfilling AI goal states. → `e.game.ai.goap_plan`
1136. **Utility AI Evaluator** – Scoring available behaviors using continuous utility curves to select high-value AI choices. → `e.game.ai.utility_select`
1137. **Boids Flocking Model (Reynolds)** – Simulating crowd movement using Separation, Alignment, and Cohesion steering vectors. → `e.game.ai.boids`
1138. **Wave Function Collapse (WFC)** – Procedural generation algorithm generating grid layouts satisfying adjacent edge compatibility constraints. → `e.game.procgen.wave_function_collapse`
1139. **Perlin Noise Generation** – Gradient noise function creating continuous procedural textures, terrain, and natural forms. → `e.game.procgen.perlin`
1140. **Simplex Noise Generation** – Higher-dimensional procedural noise function using simplex grid layouts to improve computational complexity. → `e.game.procgen.simplex`
1141. **Worley (Cellular) Noise** – Distance-based noise function generating cell patterns for stone, water, and biological textures. → `e.game.procgen.worley`
1142. **Tessendorf FFT Ocean Waves** – Simulating realistic ocean surface waves using statistical wind spectrum Fast Fourier Transforms. → skip: implementable, but too specialised for the standard library
1143. **Volumetric Fog Raymarching** – Raymarching light-scattering participation media using 3D volume noise textures. → `e.gfx.scene.volumetric_fog`
1144. **Bruneton Atmosphere Scattering** – Precomputing multiple atmospheric light scattering integrals for real-time sky rendering. → skip: implementable, but too specialised for the standard library
1145. **SDF Raymarching (Sphere Tracing)** – Marching camera rays along dynamic distances defined by Signed Distance Fields. → `e.gfx.scene.sdf_raymarch`
1146. **Meshlet Cone Culling** – GPU geometry pipeline culling mesh clusters (meshlets) based on backface normal cones and bounding spheres. → skip: hardware or circuit design
1147. **Virtual Shadow Maps (VSM)** – High-resolution clipmap shadow mapping dividing shadow projections into dynamically allocated physical pages. → skip: implementable, but too specialised for the standard library
1148. **Dynamic Mesh LOD Simplification** – Simplifying dense geometries dynamically by collapsing edge pairs while maintaining topology metrics. → `e.gfx.mesh.decimate`
1149. **Screen-Space Horizon Traversal (SSHT)** – Raymarching screen space height fields to compute detailed contact ambient shadows. → skip: implementable, but too specialised for the standard library
1150. **Distance Field Ambient Occlusion (DFAO)** – Approximating ambient occlusion using mesh-generated signed distance field representations. → skip: implementable, but too specialised for the standard library

## 19. Bioinformatics, Computational Biology & Genomics Algorithms (1151–1200)

1151. **Needleman-Wunsch Algorithm** – O(MN) dynamic programming algorithm computing global sequence alignment between nucleotide/protein sequences. → see #305 (`e.algo.align.global`)
1152. **Smith-Waterman Algorithm** – Dynamic programming algorithm finding optimal local sequence alignment regions between two sequences. → see #306 (`e.algo.align.local`)
1153. **Hirschberg's Algorithm** – Dynamic programming variant reducing sequence alignment space complexity to O(min(M,N)). → see #307 (`e.algo.align.global_linear_space`)
1154. **Gotoh's Algorithm** – Optimized sequence alignment incorporating affine gap penalties in O(MN) time. → `e.algo.align.affine_gap`
1155. **BLAST Seed-and-Extend** – Heuristic sequence alignment discovering short exact word matches and extending them into High-Scoring Segment Pairs. → skip: bioinformatics domain tool
1156. **Burrows-Wheeler Aligner (BWA)** – Mapping short sequencing reads against reference genomes using Burrows-Wheeler Transform indexing. → skip: bioinformatics domain tool
1157. **Bowtie Seeded Alignment** – Fast short-read alignment engine building compact FM-Indexes of human reference genomes. → skip: bioinformatics domain tool
1158. **De Bruijn Graph Genome Assembly** – Constructing directed graphs over overlapping k-mer substrings to assemble raw DNA reads into contigs. → skip: bioinformatics domain tool
1159. **Overlap-Layout-Consensus (OLC) Assembly** – Genome assembly paradigm computing pairwise read overlaps to construct string graphs. → skip: bioinformatics domain tool
1160. **Neighbor-Joining Algorithm** – Bottom-up clustering method constructing phylogenetic trees based on evolutionary distance matrices. → `e.ml.cluster.neighbor_joining`
1161. **UPGMA Clustering** – Agglomerative hierarchical clustering method generating ultrametric phylogenetic trees. → see #730 (`e.ml.cluster.agglomerative`)
1162. **Felsenstein's Pruning Algorithm** – Dynamic programming algorithm computing maximum likelihood scores across phylogenetic tree nodes. → skip: bioinformatics domain tool
1163. **Profile HMM Search (HMMER)** – Modeling domain protein families using Hidden Markov Models to detect distant sequence homologs. → skip: bioinformatics domain tool
1164. **Viterbi Decoding for Gene Prediction** – Identifying exon-intron gene structures across DNA sequences using HMM state decoding. → `e.ml.hmm.viterbi`
1165. **Baum-Welch Algorithm** – Expectation-Maximization algorithm estimating unknown transition and emission probabilities of Hidden Markov Models. → `e.ml.hmm.baum_welch`
1166. **Nussinov RNA Folding Algorithm** – Dynamic programming algorithm predicting RNA secondary structures by maximizing base pair counts. → skip: bioinformatics domain tool
1167. **Zuker RNA Folding Algorithm** – Predicting minimum free energy RNA secondary structures using thermodynamic base-pair energy parameters. → skip: bioinformatics domain tool
1168. **Kabsch Algorithm** – Calculating optimal rotation matrix minimizing Root Mean Square Deviation (RMSD) between aligned protein coordinate sets. → `e.algo.geom3.kabsch`
1169. **TM-align Algorithm** – Structural alignment algorithm scoring protein pair similarities independently of sequence length differences. → skip: bioinformatics domain tool
1170. **DALI Protein Alignment** – Aligning 3D protein structures by comparing internal distance matrices of contact patterns. → skip: bioinformatics domain tool
1171. **Linear Mixed Model (GWAS)** – Controlling for population structure and family relatedness when testing genetic variants in GWAS datasets. → skip: bioinformatics domain tool
1172. **GATK HaplotypeCaller Graph Assembly** – Re-assembling local sequence reads using de Bruijn graphs to call single-nucleotide variants and indels. → skip: bioinformatics domain tool
1173. **Salmon Pseudoalignment** – Ultra-fast RNA-seq transcript quantification skipping full alignment using k-mer equivalence classes. → skip: bioinformatics domain tool
1174. **Kallisto Pseudoalignment** – Mapping RNA-seq reads directly to transcript target de Bruijn graphs without computing base-level alignments. → skip: bioinformatics domain tool
1175. **DESeq2 Negative Binomial Regression** – Modeling count variance across biological replicates in RNA-seq differential expression analysis. → skip: bioinformatics domain tool
1176. **Louvain Community Detection for Single-Cell** – Graph-based clustering partitioning single-cell expression profiles using modularity optimization. → see #106 (`e.algo.graph.community.louvain`)
1177. **Leiden Community Detection** – Improved single-cell graph clustering algorithm resolving disconnected community artifacts found in Louvain. → `e.algo.graph.community.leiden`
1178. **Monocle Pseudotime Inference** – Ordering single-cell gene expression profiles along developmental trajectories using minimum spanning trees. → skip: bioinformatics domain tool
1179. **Kraken K-mer Taxonomic Classification** – Classifying metagenomic reads by matching k-mer strings to lowest common ancestor database trees. → skip: bioinformatics domain tool
1180. **Minimap2 Alignment** – Pairwise alignment engine mapping long reads (PacBio/Nanopore) using minimizer seed chains. → skip: bioinformatics domain tool
1181. **Flye Assembly Algorithm** – Long-read genome assembler constructing repeat graphs from error-prone reads. → skip: bioinformatics domain tool
1182. **AutoDock Vina Scoring** – Molecular docking software calculating empirical affinity binding scores between protein targets and drug ligands. → skip: bioinformatics domain tool
1183. **Pharmacophore Matching Grid Search** – Mapping 3D spatial arrangements of essential molecular interaction features onto small molecules. → skip: bioinformatics domain tool
1184. **BLAT (BLAST-Like Alignment Tool)** – Fast DNA/protein sequence alignment using index tables of non-overlapping k-mer keywords. → skip: bioinformatics domain tool
1185. **Plink Identity-by-State (IBS)** – Evaluating genetic similarity metrics across individual genotypes to identify pairwise sample relationships. → skip: bioinformatics domain tool
1186. **Linkage Disequilibrium Calculation** – Measuring non-random association of alleles at different genetic loci within populations. → skip: bioinformatics domain tool
1187. **Sankoff Algorithm** – Parsimony-based dynamic programming scoring character state changes on phylogenetic tree structures. → skip: bioinformatics domain tool
1188. **Cufflinks Assembly Engine** – Assembling RNA-seq alignments into minimal sets of transcript isoforms using overlap graphs. → skip: bioinformatics domain tool
1189. **MetaBAT2 Binning** – Grouping metagenomic contigs into draft genomes using sequence co-abundance and tetranucleotide frequencies. → skip: bioinformatics domain tool
1190. **Centrifuge Taxonomic Profiler** – Compressed FM-index classification engine matching sequencing reads against large microbial reference sets. → skip: bioinformatics domain tool
1191. **CellPhoneDB Interaction Mapping** – Estimating cell-cell communication networks by analyzing single-cell ligand-receptor pair expression. → skip: bioinformatics domain tool
1192. **CRISPR Off-Target Scoring (CFD)** – Predicting CRISPR-Cas9 guide RNA cleavage efficiency across potential genomic off-target sites. → skip: bioinformatics domain tool
1193. **Distance Geometry Protein Reconstruction** – Calculating 3D atomic coordinates from lower and upper bounds of nuclear magnetic resonance (NMR) distances. → skip: bioinformatics domain tool
1194. **EdgeR Empirical Bayes Analysis** – Testing differential expression in digital gene expression data using empirical Bayes moderated dispersion estimates. → skip: bioinformatics domain tool
1195. **CANU Long-Read Pipeline** – Assembling noisy long reads through overlapping, error correction, and string graph construction steps. → skip: bioinformatics domain tool
1196. **StringGraph Assembler (SGA)** – Memory-efficient genome assembly using the FM-Index to build string graphs directly. → skip: bioinformatics domain tool
1197. **Variant Call Format (VCF) Likelihood Engine** – Calculating posterior genotype probabilities across genomic loci given read quality scores. → skip: bioinformatics domain tool
1198. **AlphaFold Frame Aligner** – Translating transformer sequence representations into 3D Euclidean frame coordinates for protein structure prediction. → skip: bioinformatics domain tool
1199. **Cell Ranger Demultiplexing** – Mapping single-cell GEM barcodes and UMIs to quantify cellular transcript abundances. → skip: bioinformatics domain tool
1200. **N-Gram Genomic Profiling** – Evaluating species similarity profiles by computing distance metrics over genomic k-mer frequency vectors. → skip: bioinformatics domain tool

## 20. Natural Language Processing, Speech & Information Retrieval (1201–1250)

1201. **Byte-Pair Encoding (BPE)** – Subword tokenization iteratively merging the most frequent character/token byte pairs. → see #373 (`e.text.tokenize.bpe`)
1202. **WordPiece Tokenization** – Subword tokenization picking subword merges that maximize language model likelihood scores. → see #374 (`e.text.tokenize.wordpiece`)
1203. **Unigram Language Model Tokenization** – SentencePiece subword tokenization optimizing vocabulary sets by iteratively dropping low-probability subwords. → see #375 (`e.text.tokenize.unigram`)
1204. **Word2Vec Skip-Gram (SGNS)** – Learning word vector representations by predicting surrounding context words using negative sampling. → skip: a trained ML model or training recipe
1205. **Word2Vec Continuous Bag-of-Words (CBOW)** – Learning word embeddings by predicting center words given averaged surrounding context vectors. → skip: a trained ML model or training recipe
1206. **GloVe Embedding Factorization** – Matrix factorization learning word embeddings by modeling global log co-occurrence count matrices. → skip: a trained ML model or training recipe
1207. **FastText Subword Embeddings** – Enhancing word embeddings by representing words as character n-gram bag sums to handle out-of-vocabulary terms. → skip: a trained ML model or training recipe
1208. **BERT Masked Language Modeling (MLM)** – Training bidirectional text representations by predicting randomly masked tokens within context sequences. → skip: a trained ML model or training recipe
1209. **RoBERTa Optimization** – Enhancing BERT performance by removing Next Sentence Prediction tasks and dynamically shifting token mask patterns. → skip: a trained ML model or training recipe
1210. **ELECTRA Replaced Token Detection** – Pre-training transformer models using discriminators that identify tokens replaced by generator models. → skip: a trained ML model or training recipe
1211. **DeBERTa Disentangled Attention** – Disentangling transformer self-attention calculations into distinct word content and relative position vectors. → skip: a trained ML model or training recipe
1212. **T5 Text-to-Text Framework** – Framing all NLP tasks (summarization, translation, classification) into a unified text input to text output sequence model. → skip: a trained ML model or training recipe
1213. **GPT Autoregressive Language Modeling** – Pre-training generative transformers using causal next-token prediction loss over left-to-right context. → skip: a trained ML model or training recipe
1214. **LLaMA Architecture Adjustments** – Enhancing autoregressive LLMs using pre-normalization (RMSNorm), SwiGLU activation functions, and Rotary Embeddings (RoPE). → skip: a trained ML model or training recipe
1215. **Grouped-Query Attention (GQA)** – Transformer attention architecture sharing key/value head projections across query head groups to accelerate generation. → skip: a trained ML model or training recipe
1216. **Low-Rank Adaptation (LoRA)** – Parameter-efficient LLM fine-tuning injecting trainable low-rank decomposition matrices into frozen attention layers. → skip: a trained ML model or training recipe
1217. **QLoRA (Quantized LoRA)** – Fine-tuning LLMs by combining 4-bit NormalFloat (NF4) quantization with low-rank adapter weights. → skip: a trained ML model or training recipe
1218. **Direct Preference Optimization (DPO)** – Aligning language models with human preferences using direct log-ratio classification loss without external reward models. → skip: a trained ML model or training recipe
1219. **RLHF (PPO Alignment)** – Fine-tuning LLM generation policies using Proximal Policy Optimization updates guided by human preference reward models. → skip: a trained ML model or training recipe
1220. **BM25 Lexical Retrieval** – Probabilistic Document Retrieval scoring keyword relevance using term frequency and inverse document frequency with length normalization parameters. → see #368 (`e.text.rank.bm25`)
1221. **TF-IDF Weighting** – Scoring term importance in document collections combining Term Frequency and Inverse Document Frequency logarithms. → see #367 (`e.text.rank.tf_idf`)
1222. **Dense Passage Retrieval (DPR)** – Retrieving text passages by computing cosine similarities between dense dual-encoder vector embeddings. → skip: a trained ML model or training recipe
1223. **ColBERT Late Interaction** – Information retrieval model computing token-level fine-grained similarity matrix max-sim sums across query and document terms. → skip: a trained ML model or training recipe
1224. **Reciprocal Rank Fusion (RRF)** – Combining rank positions from multiple distinct retrieval systems into unified document score rankings. → `e.text.rank.reciprocal_rank_fusion`
1225. **Maximal Marginal Relevance (MMR)** – Re-ranking document search results to maximize relevance while penalizing similarity to already selected items. → `e.text.rank.maximal_marginal_relevance`
1226. **HNSW Vector Search** – Approximate nearest neighbor vector search building multi-layer small-world graphs supporting O(log N) searches. → `e.ml.ann.hnsw`
1227. **Inverted File with Product Quantization (IVF-PQ)** – Vector search index dividing high-dimensional spaces into Voronoi cells and compressing sub-vectors. → `e.ml.ann.ivf_pq`
1228. **ScaNN Anisotropic Quantization** – Quantizing high-dimensional vectors by optimizing inner product preservation rather than Euclidean distance errors. → skip: a vendor product's architecture
1229. **DiskANN Vector Index** – Graph-based approximate nearest neighbor index serving multi-billion scale vector sets directly from SSD storage. → skip: a vendor product's architecture
1230. **Double Metaphone Algorithm** – Phonetic encoding algorithm generating primary and secondary codes for words based on English pronunciation edge cases. → see #313 (`e.text.phonetic.metaphone`)
1231. **Porter Stemmer Algorithm** – Rule-based suffix stripping algorithm mapping English words to their canonical morphological stems. → see #369 (`e.text.stem.porter`)
1232. **Viterbi POS Tagging** – Assigning optimal Part-of-Speech tag sequences to sentences using Hidden Markov Model dynamic programming. → `e.ml.hmm.viterbi`
1233. **Conditional Random Fields (CRF)** – Discriminative sequence modeling algorithm calculating global normalizations for named entity recognition (NER). → skip: a trained ML model or training recipe
1234. **Transition-Based Arc-Eager Dependency Parsing** – Constructing dependency parse trees using shift-reduce stack transition operations. → skip: a trained ML model or training recipe
1235. **BLEU Score Evaluation** – Automated evaluation metric comparing n-gram precision matching between machine translation outputs and reference texts. → `e.text.metric.bleu`
1236. **ROUGE Metric Evaluation** – Recall-oriented metric suite evaluating text summarization quality using n-gram and longest common subsequence counts. → `e.text.metric.rouge`
1237. **BERTScore Semantic Metric** – Evaluating text generation quality by computing contextual embedding token cosine similarities. → skip: a trained ML model or training recipe
1238. **Connectionist Temporal Classification (CTC)** – Loss function training sequence models (ASR, OCR) without explicit time-alignment labels. → `e.ml.loss.ctc`
1239. **WFST Speech Decoding** – Decoding speech audio frames into text using Weighted Finite-State Transducers combining Grammar, Lexicon, and Acoustic models. → skip: implementable, but too specialised for the standard library
1240. **Whisper Speech Encoder-Decoder** – Multitask speech recognition processing log- Mel spectrograms through audio encoders and autoregressive text decoders. → skip: a trained ML model or training recipe
1241. **SentencePiece Unigram Sampler** – Regularizing NLP model training by probabilistically sampling alternative subword tokenizations. → `e.text.tokenize.unigram_sample`
1242. **Kahneman-Tversky Optimization (KTO)** – Model alignment strategy directly maximizing utility functions derived from human loss-aversion behavioral principles. → skip: a trained ML model or training recipe
1243. **Prefix Tuning** – Parameter-efficient fine-tuning prepending continuous trainable task-specific prefix vectors to transformer key/value layers. → skip: a trained ML model or training recipe
1244. **Sliding Window Attention** – Reducing self-attention memory overhead by limiting attention fields to local fixed-size contextual windows. → skip: a trained ML model or training recipe
1245. **Eisner's Dependency Parsing** – O(N3) dynamic programming algorithm finding maximum spanning dependency trees over parsed sentences. → skip: implementable, but too specialised for the standard library
1246. **Inside-Outside Algorithm** – Calculating production rule expectations for Probabilistic Context-Free Grammars (PCFGs). → skip: implementable, but too specialised for the standard library
1247. **METEOR Evaluation Metric** – Translation assessment metric incorporating exact matches, stem matches, synonymy, and word order penalties. → `e.text.metric.meteor`
1248. **Snowball Stemmer** – Framework and algorithm generating customizable stemmers across multiple European languages. → see #371 (`e.text.stem.snowball`)
1249. **FastSpeech Feed-Forward TTS** – Non-autoregressive text-to-speech generation generating mel-spectrograms in parallel using duration predictors. → skip: a trained ML model or training recipe
1250. **Soundex Indexing** – Classifying English words by phonetic sound to index names despite minor spelling variations.  Yes yes → see #312 (`e.text.phonetic.soundex`)

## 21. Parallel, Distributed & Cloud Computing Systems (1251–1300)

1251. **MapReduce Paradigm** – Distributed data processing framework partitioning computations into parallel Map and Reduce phases. → skip: a technique applied per problem, not a reusable function
1252. **Apache Spark RDD Lineage Engine** – Fault-tolerant dynamic memory computation tracking operation graphs to rebuild lost partitions. → skip: a vendor product's architecture
1253. **Parameter Server Architecture** – Distributed machine learning framework separating worker node computations from parameter state synchronization. → skip: a whole service or system, not a function
1254. **Bulk Synchronous Parallel (BSP) Model** – Parallel execution abstraction operating in iterative supersteps bounded by global barriers. → skip: a technique applied per problem, not a reusable function
1255. **Ring-AllReduce Algorithm** – Bandwidth-optimal collective communication algorithm transferring array gradients across ring-connected worker nodes. → `e.dist.collective.all_reduce_ring`
1256. **MPI Scatter-Gather & Broadcast** – High-performance computing primitives distributing single arrays to multiple nodes and gathering responses. → `e.dist.collective.broadcast`
1257. **Multi-Paxos Consensus** – Optimized Paxos variant streamlining consensus rounds by electing long-term leaders for stream logging. → `e.dist.consensus.multi_paxos`
1258. **Egalitarian Paxos (EPaxos)** – Leaderless distributed consensus protocol allowing nodes to commit command instances without centralized bottlenecks. → skip: implementable, but too specialised for the standard library
1259. **Viewstamped Replication (VR)** – Primary-backup state machine replication protocol handling network reconfigurations via view changes. → `e.dist.consensus.viewstamped`
1260. **Raft Log Compaction & Snapshotting** – Compacting state machine logs by persisting state snapshots and discarding applied entries. → `e.dist.consensus.raft_snapshot`
1261. **Google Spanner TrueTime API Sync** – Distributed consistency primitive utilizing atomic clocks and GPS receivers to bound clock uncertainty (ϵ). → skip: a vendor product's architecture
1262. **Two-Phase Commit with Paxos (2PC-Paxos)** – Combining 2PC with Paxos-replicated transaction cohorts to eliminate coordinator single-point-of-failure blocks. → see #720 (`e.dist.commit.two_phase`)
1263. **Try-Confirm-Cancel (TCC) Pattern** – Application-level distributed transaction pattern reserving, committing, or releasing resources explicitly across services. → `e.dist.commit.tcc`
1264. **Maglev Consistent Hash Load Balancer** – Network load balancer mapping service flows into lookup tables to ensure uniform traffic distribution during backend churn. → `e.net.balance.maglev`
1265. **Power of Two Random Choices (P2C)** – Load balancing heuristic selecting the least loaded backend among two randomly chosen candidates. → see #713 (`e.net.balance.power_of_two`)
1266. **Directory-Based Cache Coherence** – Maintaining distributed shared memory consistency across hardware nodes via centralized state directories. → skip: hardware or circuit design
1267. **Active-Active Database Replication** – Replicating transactions concurrently across multiple geographically distributed write-capable nodes. → skip: a whole service or system, not a function
1268. **Conflict-Free Replicated Data Types (CRDTs)** – Data structures converging concurrently edited states without coordination (State-based / Operation-based). → `e.dist.crdt.merge`
1269. **Operational Transformation (OT)** – Concurrent text editing engine transforming local editing operations relative to concurrent remote updates. → `e.text.collab.transform`
1270. **Distributed Weighted Lease Renewal** – Time-bounded resource allocation protocol using heartbeat renewals to manage lease ownership. → `e.dist.lock.lease_renew`
1271. **Distributed Snapshot (Chandy-Lamport)** – Recording global system states in distributed systems by propagating state markers across channel queues. → see #152 (`e.dist.snapshot.chandy_lamport`)
1272. **Epidemic Gossip Push-Pull State Sync** – Exchanging missing cluster state vectors pairwise to achieve exponential network-wide convergence. → see #142 (`e.dist.gossip.disseminate`)
1273. **Chase-Lev Work-Stealing Deque** – Lock-free single-producer multi-consumer deque enabling worker threads to steal tasks efficiently. → `e.concurrent.deque.steal`
1274. **MapReduce Combiner Optimization** – Executing localized sub-aggregations on mapper outputs to minimize network serialization volume. → skip: a technique applied per problem, not a reusable function
1275. **Distributed Lock Manager (DLM) Escalation** – Managing clustered resource locks via lock escalation and distributed deadlock detection graphs. → skip: a whole service or system, not a function
1276. **Redis Cluster Key Hash Slot Sharding** – Partitioning keyspace into 16,384 deterministic hash slots assigned across cluster nodes. → skip: a vendor product's architecture
1277. **Memcached Slab Allocation Engine** – Memory manager pre-allocating fixed-size slab classes to eliminate heap memory fragmentation. → see #680 (`e.mem.slab`)
1278. **W3C Trace Context Propagation** – Injecting standardized traceparent and tracestate headers across HTTP/RPC boundaries for distributed tracing. → `e.trace.propagate`
1279. **Cloud Autoscaling Reactive Control Loops** – Monitoring real-time system metrics (CPU, memory, queue depth) to scale infrastructure capacity via PID controllers. → skip: a whole service or system, not a function
1280. **Proactive Predictive Autoscaling** – Forecasting traffic spikes using time-series models (Holt-Winters, ARIMA) to provision capacity prior to load arrival. → skip: a whole service or system, not a function
1281. **Kubernetes Horizontal Pod Autoscaler (HPA)** – Controller loop calculating target metric ratios to adjust replica counts dynamically. → skip: a vendor product's architecture
1282. **Envoy Outlier Detection** – Service mesh circuit breaking pattern isolating backends that exhibit elevated HTTP 5xx error rates. → skip: a vendor product's architecture
1283. **eBPF Sidecar Proxy Interception** – Bypassing standard TCP/IP stack overhead by redirecting socket traffic at the Linux kernel level. → skip: a vendor product's architecture
1284. **DFS Chunk Metadata Management (GFS / HDFS)** – Dividing massive files into 64MB/128MB chunks and managing locations via centralized master nodes. → skip: a whole service or system, not a function
1285. **Erasure Coding (Reed-Solomon) in Distributed Storage** – Splitting storage objects into K data chunks and M parity chunks to recover from M simultaneous node failures. → see #854 (`e.algo.ecc.reed_solomon_decode`)
1286. **Ceph CRUSH Map Placement Algorithm** – Algorithmic pseudo-random data object placement mapping objects directly to storage devices without lookup tables. → skip: a vendor product's architecture
1287. **Amazon Dynamo Eventual Consistency Read-Repair** – Reconciling stale replica data asynchronously during read operations using vector clock comparisons. → see #935 (`e.dist.replica.read_repair`)
1288. **Distributed Outbox Pattern** – Writing domain events to local database tables within transactions before publishing to asynchronous message brokers. → skip: a technique applied per problem, not a reusable function
1289. **Apache Kafka Log Segment Rolling** – Appending messages to immutable commit logs on disk and rolling segments based on age or byte bounds. → skip: a vendor product's architecture
1290. **Zero-Copy Socket Transfer ( sendfile )** – Transferring data directly from OS page caches to network sockets without copying memory to user space. → `e.os.send_file`
1291. **Asynchronous Event-Driven I/O ( io_uring )** – Offloading kernel system calls via shared submission and completion ring buffers. → skip: an implementation detail of an existing module, not an API
1292. **Consensus-Driven Dynamic Membership Change** – Transitioning cluster membership configurations safely using joint consensus states in Raft/Paxos. → `e.dist.consensus.membership_change`
1293. **Redis Sliding Window Rate Limiter** – Atomic Lua script enforcing precise rolling-window rate limits using sorted set scores ( ZADD / ZREMRANGEBYSCORE ). → see #709 (`e.ratelimit.sliding_window`)
1294. **Pregel BSP Graph Compute Engine** – Iterative graph processing framework executing user-defined compute functions at vertices during BSP supersteps. → skip: a technique applied per problem, not a reusable function
1295. **Distributed Vector Index Sharding** – Partitioning high-dimensional vector collections across nodes using multi-index or k-means space partitioning. → skip: a whole service or system, not a function
1296. **Flink Chandy-Lamport Checkpointing** – Injecting barrier markers into stream processing pipelines to record consistent state snapshots without stopping execution. → see #152 (`e.dist.snapshot.chandy_lamport`)
1297. **Stream Processing Watermarking** – Emitting monotonically increasing timestamp bounds to track event-time progress in out-of-order data streams. → `e.data.stream.watermark`
1298. **DAG Task Scheduler Execution Engine** – Resolving inter-task dependency graphs to schedule parallel processing stages (e.g., Apache Spark, Airflow). → `e.thread.pool.run_dag`
1299. **Multi-Cluster Ingress Global Traffic Routing** – Routing user requests across geographically distributed clusters using latency-based DNS or BGP Anycast. → skip: a whole service or system, not a function
1300. **Chandy-Misra-Haas Deadlock Detection** – Edge-chasing algorithm detecting deadlocks in distributed resource allocation systems. → see #111 (`e.dist.deadlock.chandy_misra_haas`)

## 22. Advanced Software Architecture, Compilers & Runtimes (1301–1350)

1301. **Cytron's SSA Form Construction** – Placing ϕ-functions at iterated dominance frontiers to construct Static Single Assignment representations. → skip: belongs in the Neper compiler, not the library
1302. **Lengauer-Tarjan Dominator Tree Algorithm** – Computing dominator trees in control-flow graphs using depth-first search and semi-dominators in O(E ⋅ α(V ,E)) time. → skip: belongs in the Neper compiler, not the library
1303. **Global Value Numbering (GVN)** – Compiler pass identifying redundant expressions across control-flow paths by assigning value numbers to SSA variables. → skip: belongs in the Neper compiler, not the library
1304. **Sparse Conditional Constant Propagation (SCCP)** – Propagating constants and evaluating branches simultaneously to eliminate dead code and simplify expressions. → skip: belongs in the Neper compiler, not the library
1305. **Loop-Invariant Code Motion (LICM)** – Hoisting computations that produce identical values across iterations out of loop bodies. → skip: belongs in the Neper compiler, not the library
1306. **Chaitin-Briggs Graph Coloring Register Allocation** – Modeling register allocation as a graph coloring problem over register interference graphs. → skip: belongs in the Neper compiler, not the library
1307. **Linear Scan Register Allocation** – Fast single-pass register allocator assigning registers by processing variable live ranges sequentially. → skip: belongs in the Neper compiler, not the library
1308. **Escape Analysis** – Compiler optimization determining if object allocations outlive execution frames to allocate memory on stacks instead of heaps. → skip: belongs in the Neper compiler, not the library
1309. **Aggressive Dead Code Elimination (ADCE)** – Removing instructions lacking observable side effects by operating control-dependence graphs in reverse. → skip: belongs in the Neper compiler, not the library
1310. **Trace JIT Compilation** – Hotpath runtime optimization recording executed basic-block traces and compiling them into native machine code. → skip: belongs in the Neper compiler, not the library
1311. **Method JIT Compilation** – Compiling frequently invoked functions or methods into optimized native code based on execution counters. → skip: belongs in the Neper compiler, not the library
1312. **On-Stack Replacement (OSR)** – Replacing unoptimized running frame stacks with optimized native frames during active loop execution. → skip: belongs in the Neper compiler, not the library
1313. **Pratt Parser (Top-Down Operator Precedence)** – Extensible parsing algorithm associating precedence levels and binding power with tokens. → see #340 (`e.parse.pratt`)
1314. **Packrat Parsing (PEG)** – Linear-time parsing algorithm executing Parsing Expression Grammars via memoization. → see #339 (`e.parse.peg`)
1315. **LALR(1) Parser Construction** – Merging LR(1) items with identical core items to build compact parsing tables for context-free grammars. → see #332 (`e.parse.lr.lalr_table`)
1316. **Algorithm W (Hindley-Milner Type Inference)** – Recursively unifying type equations to infer principal types without explicit type annotations. → skip: belongs in the Neper compiler, not the library
1317. **Continuation-Passing Style (CPS) Transformation** – Transforming functional code such that control is passed explicitly via continuation functions. → skip: belongs in the Neper compiler, not the library
1318. **Defunctionalization** – Replacing first-class functions or closures with data structures and dispatch functions. → skip: belongs in the Neper compiler, not the library
1319. **Tail-Call Optimization (TCO)** – Reusing current stack frames for tail-recursive calls to enable infinite recursion within O(1) space. → skip: belongs in the Neper compiler, not the library
1320. **G1 GC Card Table Marking** – Tracking cross-region object references using card tables and write barriers during concurrent garbage collection. → skip: Neper has ownership, not a garbage collector
1321. **Shenandoah Brooks Pointers** – Supporting concurrent compaction by routing object accesses through forwarding pointers updated during GC phases. → skip: Neper has ownership, not a garbage collector
1322. **Immix Region-Based Garbage Collection** – Managing memory using blocks and lines to balance contiguous allocation speed with low fragmentation. → skip: Neper has ownership, not a garbage collector
1323. **ZGC Colored Pointers & Load Barriers** – Encoding reference metadata directly inside 64-bit pointer bits to run concurrent marking and relocation phases. → skip: Neper has ownership, not a garbage collector
1324. **AST Pattern Lowering** – Transforming high-level Abstract Syntax Tree constructs into lower-level intermediate representations (IR). → skip: belongs in the Neper compiler, not the library
1325. **Monadic Bind & Composable Effect System** – Structuring side-effects sequentially using algebraic effect handlers or monadic compositions. → skip: a technique applied per problem, not a reusable function
1326. **Software Transactional Memory (STM) TLog Validation** – Executing memory updates inside thread-local logs and committing changes via atomic validation passes. → skip: implementable, but too specialised for the standard library
1327. **Acquire-Release Memory Ordering** – Enforcing hardware memory fence rules to guarantee cross-thread operation visibility without full barriers. → `e.atomic.load` (the intrinsic's spelling; the ordering is its argument)
1328. **AddressSanitizer (ASan) Shadow Memory Mapping** – Intercepting memory allocations and mapping 8-byte application regions to 1-byte shadow memory flags to detect out-of-bound accesses. → skip: belongs in the toolchain (build, test runner, pacman)
1329. **ThreadSanitizer (TSan) Shadow State Algorithm** – Tracking memory access vector clocks per thread to detect data races. → skip: belongs in the toolchain (build, test runner, pacman)
1330. **MemorySanitizer (MSan) Shadow Bits** – Tracking initialization state for every memory bit to catch uninitialized memory reads. → skip: belongs in the toolchain (build, test runner, pacman)
1331. **LLVM Intermediate Representation (IR) Pass Management** – Scheduling transform, analysis, and optimization passes over SSA-based IR. → skip: belongs in the Neper compiler, not the library
1332. **Superword-Level Parallelism (SLP) Vectorization** – Combining independent scalar instructions within basic blocks into single-instruction multi-data (SIMD) operations. → skip: belongs in the Neper compiler, not the library
1333. **Profile-Guided Optimization (PGO)** – Utilizing execution profile feedback to optimize branch prediction layouts, function inlining, and code coldness. → skip: belongs in the Neper compiler, not the library
1334. **Link-Time Optimization (LTO)** – Merging compiler IR across compilation units at link time to execute global optimizations. → skip: belongs in the Neper compiler, not the library
1335. **Foreign Function Interface (FFI) Trampolines** – Generating dynamic assembly trampolines to translate calling conventions between programming languages. → skip: belongs in the Neper compiler, not the library
1336. **Green Thread Fiber Scheduling** – Cooperatively or preemptively scheduling lightweight user-space threads onto OS worker threads. → `e.thread.fiber`
1337. **DWARF Stack Unwinding** – Reading call frame information (.eh_frame) sections to unwind execution stack frames during exception handling. → `e.debug.backtrace`
1338. **Structural Subtyping Type Checker** – Validating type compatibility based on structural shape and signature parity rather than explicit inheritance declarations. → skip: belongs in the Neper compiler, not the library
1339. **Software Fault Isolation (SFI)** – Restricting untrusted modules by rewriting memory access instructions to keep reads/writes inside isolated memory ranges. → skip: implementable, but too specialised for the standard library
1340. **WebAssembly Bytecode Validation Engine** – Validating type-safety, stack balance, and structured control flow in Wasm modules prior to compilation. → skip: implementable, but too specialised for the standard library
1341. **Direct Threaded Virtual Machine Interpreter** – Accelerating bytecode execution by replacing switch-based dispatch loops with arrays of instruction handler addresses. → skip: a technique applied per problem, not a reusable function
1342. **Copy-on-Write (CoW) Memory Page Mapping** – Sharing physical memory pages between processes until write operations trigger page-fault duplication. → skip: OS kernel internals
1343. **PLT/GOT Dynamic Linking Resolution** – Deferring dynamic library symbol resolution until runtime using Procedure Linkage Tables and Global Offset Tables. → skip: belongs in the Neper compiler, not the library
1344. **Automatic Reference Counting (ARC) Insertion** – Inserting retain and release calls statically during compilation to manage object lifecycles. → skip: belongs in the Neper compiler, not the library
1345. **Non-Blocking CAS Loop Construction** – Constructing lock-free operations using Atomic Compare-And-Swap loops with exponential backoff handling. → skip: a technique applied per problem, not a reusable function
1346. **Stack Canary Protection** – Inserting guard values onto stack frames before return addresses to detect buffer overflow attacks. → skip: belongs in the Neper compiler, not the library
1347. **Symbol Demangling Engine** – Decoding compiler-mangled name strings back into human-readable class, method, and type signatures. → `e.debug.demangle`
1348. **Control Flow Guard (CFG) Indirect Call Validation** – Checking target addresses of indirect function calls against valid target bitmasks prior to execution. → skip: belongs in the Neper compiler, not the library
1349. **Whole Program Reflection Metadata Generation** – Emitting compile-time type descriptor tables to allow runtime inspection and dynamic invocation. → skip: belongs in the Neper compiler, not the library
1350. **Escape Analysis Stack-to-Register Promotion** – Promoting non-escaping scalar fields of allocated objects directly into virtual registers. → skip: belongs in the Neper compiler, not the library

## 23. Hardware, Computer Architecture & VLSI Algorithms (1351–1400)

1351. **TAGE (TAgged GEometric) Branch Predictor** – High-accuracy branch predictor tracking history across geometrically increasing history lengths using tagged tables. → skip: hardware or circuit design
1352. **Two-Level Adaptive Branch Prediction** – Predicting conditional branches using global shift registers and pattern history tables. → skip: hardware or circuit design
1353. **Tournament Branch Predictor** – Dynamic predictor selecting between local and global branch predictors using meta-predictor state machines. → skip: hardware or circuit design
1354. **MESI Cache Coherence Protocol** – Protocol managing multi-core L1/L2 cache line states (Modified, Exclusive, Shared, Invalid). → skip: hardware or circuit design
1355. **MOESI Cache Coherence Protocol** – Coherence protocol adding an "Owner" state to enable sharing dirty cache lines without writing back to main memory. → skip: hardware or circuit design
1356. **Tomasulo's Algorithm** – Out-of-order instruction execution pipeline dynamic scheduling scheme using reservation stations and register renaming. → skip: hardware or circuit design
1357. **Reorder Buffer (ROB) In-Order Commit** – Reordering speculatively executed out-of-order instructions to ensure in-order state updates and precise exceptions. → skip: hardware or circuit design
1358. **Register Renaming Map Tables** – Mapping architectural registers to physical register files to eliminate WAR and WAW hazards. → skip: hardware or circuit design
1359. **Adaptive Replacement Cache (ARC)** – Self-tuning cache replacement policy balancing Recency (LRU) and Frequency (LFU) sub-lists. → see #270 (`e.data.cache.arc`)
1360. **Segmented LRU (SLRU) Cache Engine** – Partitioning cache lines into probationary and protected segments to prevent cache pollution from single-use scans. → see #274 (`e.data.cache.slru`)
1361. **Stride Hardware Prefetcher** – Detecting constant memory access strides to speculatively load data blocks into L1/L2 caches. → skip: hardware or circuit design
1362. **Stream Buffer Prefetching** – Prefetching sequential memory blocks into dedicated FIFO buffers ahead of execution demands. → skip: hardware or circuit design
1363. **Wallace Tree Multiplier** – Hardware reduction tree structure reducing partial products using 3:2 full adders in O(log N) stages. → skip: hardware or circuit design
1364. **Booth's Multiplication Algorithm** – Recoding binary multipliers into signed digit representations to reduce partial product additions. → skip: an implementation detail of an existing module, not an API
1365. **Systolic Array Acceleration Engine** – Grid of tightly coupled processing elements streaming data through local registers to execute matrix multiplications (e.g., Google TPU). → skip: hardware or circuit design
1366. **Wormhole Routing Network-on-Chip (NoC)** – Splitting packet structures into tiny flow control units (flits) to route data through NoCs with minimal router buffer overhead. → skip: hardware or circuit design
1367. **Virtual Channel NoC Allocation** – Multiplexing physical NoC link bandwidth across multiple virtual flit queues to avoid head-of-line blocking. → skip: hardware or circuit design
1368. **XY Dimension-Order Routing** – Minimal non-adaptive routing algorithm directing packets along X coordinates before Y coordinates in 2D mesh topologies. → skip: hardware or circuit design
1369. **Clock Tree Synthesis (CTS) H-Tree** – Constructing symmetric clock distribution networks to minimize clock skew across physical silicon dies. → skip: hardware or circuit design
1370. **Static Timing Analysis (STA)** – Computing maximum signal propagation delays across combinational logic paths to verify setup and hold time constraints. → skip: hardware or circuit design
1371. **Quine-McCluskey Boolean Minimization** – Exact method for minimizing boolean functions by grouping prime implicants. → `e.algo.logic.quine_mccluskey`
1372. **Espresso Heuristic Logic Minimizer** – Fast heuristic algorithm reducing boolean function expressions for programmable logic arrays (PLAs). → skip: implementable, but too specialised for the standard library
1373. **Floorplanning via Simulated Annealing** – Optimizing module placement, die area, and wire interconnect length using stochastic thermal cooling models. → skip: hardware or circuit design
1374. **Scan Chain Insertion (DFT)** – Connecting internal flip-flops into shift registers during Design-for-Testability modes to enable post-fabrication fault testing. → skip: hardware or circuit design
1375. **Built-In Self-Test (BIST) LFSR Engine** – Utilizing Linear Feedback Shift Registers to generate pseudo-random test patterns on-chip. → `e.algo.rand.lfsr`
1376. **Content-Addressable Memory (CAM) Search Circuitry** – Parallel hardware architecture comparing input data terms against stored bit arrays in O(1) clock cycles. → skip: hardware or circuit design
1377. **TLB Shootdown IPI Handler** – Inter-Processor Interrupt mechanism forcing core CPUs to invalidate stale translation lookaside buffer entries. → skip: OS kernel internals
1378. **Rank-Level Memory Controller Scheduling** – Scheduling DDR DRAM read/write commands to maximize bank-level parallelism and minimize bus turnaround penalties. → skip: hardware or circuit design
1379. **Target Row Refresh (TRR)** – Memory controller mechanism tracking activation counts to mitigate Rowhammer electromagnetic leakage faults in DRAM. → skip: hardware or circuit design
1380. **High Bandwidth Memory (HBM) Silicon Interposer** – Stacking DRAM dies vertically over logic dies using Through-Silicon Vias (TSVs) to maximize bus width. → skip: hardware or circuit design
1381. **NUMA First-Touch Allocation Policy** – Allocating physical memory pages on the local NUMA node associated with the thread initiating the allocation. → skip: OS kernel internals
1382. **Branch Target Buffer (BTB)** – High-speed hardware cache storing destination addresses of direct/indirect branch instructions. → skip: hardware or circuit design
1383. **Hardware Transactional Memory (HTM) Conflict Detection** – Tracking read-sets and write-sets via L1 cache line tags to detect transactional memory collisions. → skip: hardware or circuit design
1384. **Vector Register Lane Masking** – Executing conditional vector operations by applying predicate register bitmasks across execution lanes. → `e.simd.select`
1385. **Floating-Point Alignment Shifter** – Aligning significand fractions during floating-point addition/subtraction operations by shifting smaller exponents. → skip: hardware or circuit design
1386. **Asynchronous FIFO Gray Code Synchronization** – Dual-clock domain FIFO synchronization passing read/write pointers across clock boundaries using Gray codes. → see #829 (`e.bytes.gray_encode`)
1387. **Dynamic Voltage and Frequency Scaling (DVFS)** – Adjusting processor operating clock frequencies and supply voltages dynamically based on workload profiles. → skip: hardware or circuit design
1388. **Retiming Logic Optimization** – Relocating flip-flops across combinational logic blocks to minimize critical path delays without changing circuit functionality. → skip: hardware or circuit design
1389. **High-Level Synthesis (HLS) C-to-RTL Scheduling** – Transforming high-level algorithmic C/C++ representations into cycle-accurate Verilog/VHDL RTL hardware implementations. → skip: hardware or circuit design
1390. **Reduced Ordered Binary Decision Diagrams (ROBDD)** – Canonical graph representation of boolean functions supporting canonical equality checks. → `e.algo.bdd.build`
1391. **SAT-Based Formal Equivalence Checking** – Proving equivalence between gate-level netlists and high-level RTL specifications using Boolean SAT solvers. → `e.algo.sat.equivalent`
1392. **IEEE 1149.1 JTAG Boundary Scan** – Standardized shift-register architecture inspecting chip pin states and executing device testing. → skip: hardware or circuit design
1393. **DMA Scatter-Gather Controller Engine** – Processing memory descriptor chains to execute non-contiguous memory transfers without host CPU interventions. → skip: hardware or circuit design
1394. **Write-Combining Buffer Execution** – Coalescing sequential memory writes into temporary store buffers to issue single burst memory bus requests. → skip: hardware or circuit design
1395. **Store Buffer & Invalidation Queue Memory Pipeline** – Decoupling CPU core writes from cache interconnect delays using speculation queues and memory barriers. → skip: hardware or circuit design
1396. **Hardware-Assisted Virtualization (Nested Page Tables / EPT)** – Hardware MMU translation mapping guest virtual addresses through guest physical addresses directly to host physical addresses. → skip: hardware or circuit design
1397. **Advanced Programmable Interrupt Controller (APIC) Routing** – Priority-based routing engine directing hardware and software interrupts to specific CPU cores. → skip: hardware or circuit design
1398. **Round-Robin Bus Arbitration Logic** – Fair arbitration logic allocating shared hardware bus access sequentially among competing masters. → skip: hardware or circuit design
1399. **Delay-Locked Loop (DLL) Clock Alignment** – Aligning clock signal phases across high-speed DDR memory interfaces using controllable delay lines. → skip: hardware or circuit design
1400. **SECDED Error-Correcting Code Logic** – Single Error Correction, Double Error Detection Hamming code logic protecting SRAM/DRAM lines against soft errors. → see #860 (`e.algo.ecc.hamming_decode`)

## 24. Cybersecurity, Network Defense & Cryptographic Protocols (1401–1450)

1401. **TLS 1.3 1-RTT & 0-RTT Handshake Protocols** – Establishing encrypted session keys using Diffie-Hellman key exchanges while eliminating legacy round-trips. → `e.net.tls.handshake`
1402. **IPsec ESP (Encapsulating Security Payload)** – Encrypting and authenticating IP packet payloads in Tunnel or Transport modes. → skip: OS kernel internals
1403. **Kerberos V5 Authentication** – Ticket-granting authentication system using symmetric key cryptography and trusted KDCs. → skip: implementable, but too specialised for the standard library
1404. **OAuth 2.0 PKCE (Proof Key for Code Exchange)** – Authorization code protocol utilizing dynamic code verifiers and code challenges to prevent authorization code interception. → `e.net.http.auth.pkce`
1405. **OpenID Connect (OIDC) ID Token Validation** – Validating JWT identity tokens by verifying cryptographically signed JSON Web Keys (JWKS). → `e.fmt.jwt.verify`
1406. **Aho-Corasick Multi-Pattern Inspection Engine** – Constructing finite-state pattern matching automata to inspect network payloads against signature dictionaries in single passes. → see #295 (`e.text.search.aho_corasick`)
1407. **WAF ModSecurity Rules Engine** – Evaluating incoming HTTP requests against regular expression rule sets to filter out XSS and SQL Injection payloads. → skip: a vendor product's architecture
1408. **DNSSEC Chain of Trust Validation** – Authenticating DNS record responses by recursively validating RRSIG , DNSKEY , and DS record signatures back to the root zone key. → `e.net.dns.dnssec_validate`
1409. **RPKI Route Origin Validation (ROV)** – Validating BGP route announcements against cryptographically signed Route Origin Authorizations (ROAs). → skip: network protocol beyond the library scope
1410. **TCP SYN Cookie Generation** – Mitigating SYN flood attacks by encoding connection parameters into TCP initial sequence numbers (ISN) without allocating connection state. → skip: OS kernel internals
1411. **BGP Anycast Traffic Scrubbing** – Announcing identical IP prefixes via Anycast to distribute volumetric DDoS traffic to scrubbing centers. → skip: a whole service or system, not a function
1412. **Time-Based Blind SQL Injection Exfiltration** – Extracting schema data character by character using conditional database delay commands ( SLEEP() , pg_sleep() ). → skip: attack technique
1413. **Address Space Layout Randomization (ASLR)** – Randomizing address space positions of program stacks, heaps, and libraries in memory to block exploitation. → skip: OS kernel internals
1414. **Data Execution Prevention (DEP / NX Bit)** – Marking stack and memory pages as non-executable to prevent execution of injected shellcode. → skip: OS kernel internals
1415. **Stack Canary Protection Verification** – Checking stack frame integrity using randomized canary values prior to function return instructions. → skip: belongs in the Neper compiler, not the library
1416. **Control Flow Integrity (CFI)** – Restricting runtime execution transfers to valid target call graphs to eliminate Return-Oriented Programming (ROP) exploits. → skip: belongs in the Neper compiler, not the library
1417. **CKKS Fully Homomorphic Encryption** – Homomorphic encryption scheme supporting fixed-point arithmetic vector operations over encrypted data. → skip: research-grade, no settled practical implementation
1418. **BFV / BGV Fully Homomorphic Encryption** – Homomorphic encryption schemes supporting exact integer polynomial ring arithmetic operations over encrypted data. → skip: research-grade, no settled practical implementation
1419. **Differential Privacy Laplace Mechanism** – Preserving privacy in statistical data queries by adding noise drawn from Laplace distributions proportional to query sensitivity (Δf/ϵ). → `e.algo.privacy.laplace`
1420. **Differential Privacy Gaussian Mechanism** – Adding Gaussian-distributed noise to numeric query outputs to satisfy (ϵ,δ)-differential privacy bounds. → `e.algo.privacy.gaussian`
1421. **Differential Privacy Exponential Mechanism** – Selecting non-numeric query outputs from candidate sets while preserving differential privacy. → `e.algo.privacy.exponential`
1422. **Yao's Garbled Circuits** – Two-party secure computation protocol evaluating boolean circuit functions over private inputs without revealing raw data. → skip: research-grade, no settled practical implementation
1423. **Goldreich-Micali-Wigderson (GMW) MPC Protocol** – Multi-party computation framework evaluating circuits using secret-shared input values and Oblivious Transfer. → skip: research-grade, no settled practical implementation
1424. **PLONK Zero-Knowledge Proof System** – Universal zero-knowledge proof scheme using polynomial commitments (KZG) over custom constraint systems. → skip: research-grade, no settled practical implementation
1425. **Nova Recursive ZK-Proof Folding** – Folding two instances of relaxed Rank-1 Constraint Systems (R1CS) recursively to generate incremental zero-knowledge proofs. → skip: research-grade, no settled practical implementation
1426. **Ransomware I/O Entropy Analysis Heuristic** – Detecting active file encryption attacks by monitoring file write operations for sudden entropy shifts toward 8.0 bits per byte. → `e.algo.stat.entropy`
1427. **Dynamic Sandbox Hooking & Anti-Evasion** – Intercepting OS API calls inside isolated virtual machines while obfuscating sandbox artifacts (hypervisor flags, timing delays). → skip: a whole service or system, not a function
1428. **Software Bill of Materials (SBOM) Dependency Resolution** – Constructing dependency graphs to trace vulnerability propagation across software supply chains. → `pacman.resolve`
1429. **WebAuthn / FIDO2 Passkey Signature Verification** – Authenticating users via asymmetric public-key cryptography stored on hardware authenticators or Secure Enclaves. → `e.net.http.auth.webauthn_verify`
1430. **HMAC-SHA256 Token Authentication** – Verifying message integrity and authenticity using shared secret keys combined with iterated cryptographic hashing. → see #572 (`e.crypto.mac.hmac_sha256`)
1431. **Certificate Transparency (CT) Merkle Audit** – Verifying TLS certificate issuance by querying append-only, publicly verifiable Merkle tree logs. → `e.crypto.x509.ct_verify`
1432. **Content Security Policy (CSP) Nonce Validation** – Blocking cross-site scripting by requiring script tags to include matching single-use cryptographic nonces. → `e.net.http.csp_nonce`
1433. **SameSite Cookie Enforcement Engine** – Enforcing browser cookie policies ( Strict , Lax , None ) to prevent Cross-Site Request Forgery (CSRF) vulnerabilities. → `e.net.http.cookie_same_site`
1434. **CORS Preflight Evaluation** – Handling browser OPTIONS requests to validate cross-origin resource access rights prior to processing state-changing calls. → `e.net.http.cors_preflight`
1435. **XML External Entity (XXE) Safe Parsing** – Disabling inline DTD loading and external entity expansion within XML parsers. → `e.fmt.xml.parse`
1436. **SSRF IP Whitelist / Blacklist Validation** – Validating URLs to block internal IP ranges ( 10.0.0.0/8, 127.0.0.1, link-local 169.254.169.254) prior to initiating HTTP requests. → `e.net.is_private`
1437. **Format String Vulnerability Exploitation Mitigation** – Enforcing compile-time checks requiring static literal strings as format arguments in print functions. → skip: belongs in the Neper compiler, not the library
1438. **Return-Oriented Programming (ROP) Gadget Chain Construction** – Chaining short assembly sequences ending in ret instructions to bypass executable space protections. → skip: attack technique
1439. **Jump-Oriented Programming (JOP) Mitigation** – Restricting indirect jump table branches using branch target instructions (e.g., ARM BTI, Intel CET). → skip: belongs in the Neper compiler, not the library
1440. **ML-KEM (Kyber) Post-Quantum Key Encapsulation** – Standardized lattice-based key encapsulation mechanism built on Module Learning-With-Errors (M-LWE). → see #592 (`e.crypto.kx.ml_kem`)
1441. **ML-DSA (Dilithium) Post-Quantum Signature** – Standardized lattice-based digital signature scheme relying on Module Learning-With-Errors hardness. → see #593 (`e.crypto.sign.ml_dsa`)
1442. **Stateful Hash-Based Signatures (LMS / XMSS)** – Quantum-resistant digital signatures utilizing Merkle trees built over One-Time Signature schemes (WOTS+). → `e.crypto.sign.xmss`
1443. **STRIDE Threat Modeling Surface Analysis** – Evaluating system security boundaries against Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, and Elevation of Privilege. → skip: a technique applied per problem, not a reusable function
1444. **Coverage-Guided Fuzzing (AFL / libFuzzer)** – Mutating program inputs guided by code coverage edge feedback to discover crash-inducing states. → `e.test.fuzz.run`
1445. **Symbolic Execution Pathfinder (KLEE)** – Executing programs with symbolic inputs to generate path constraints and auto-solve input payloads for uncovered code paths. → skip: belongs in the toolchain (build, test runner, pacman)
1446. **Taint Analysis Data Flow Tracking** – Marking user input as "tainted" and tracking its propagation through instructions to sink functions to identify security flaws. → skip: belongs in the toolchain (build, test runner, pacman)
1447. **TPM PCR Quote Remote Attestation** – Validating platform boot integrity by verifying signed Platform Configuration Register quotes generated by Trusted Platform Modules. → skip: a whole service or system, not a function
1448. **Confidential Computing Enclave Attestation** – Validating hardware-isolated enclave measurements (Intel SGX, AMD SEV) via signed hardware manufacturer certificates. → skip: a whole service or system, not a function
1449. **SIEM Log Correlation Rule Engine** – Normalizing event logs from heterogeneous hosts to identify attack patterns across sliding time windows. → skip: a vendor product's architecture
1450. **Network Intrusion Detection Flow Reassembly** – Reassembling fragmented IP packets and out-of-order TCP streams to reconstruct full protocol payloads for deep packet inspection. → skip: implementable, but too specialised for the standard library

## 25. Financial Engineering, Quantitative Finance & Algorithmic Trading (1451–1500)

1451. **Black-Scholes-Merton PDE Solver** – Computing European option prices by solving parabolic partial differential equations via finite difference methods. → skip: quantitative-finance domain
1452. **Cox-Ross-Rubinstein Binomial Option Pricing** – Pricing options over discrete binomial trees tracking underlying asset upward and downward movement probabilities. → skip: quantitative-finance domain
1453. **Monte Carlo Pricing with Antithetic Variates** – Reducing Monte Carlo sample variance by pairing generated random path samples (Z) with complementary inverted paths (−Z). → `e.math.mc.antithetic`
1454. **Monte Carlo Pricing with Control Variates** – Accelerating option simulation convergence by adjusting generated estimates using known analytical expected values of correlated assets. → `e.math.mc.control_variate`
1455. **Heston Stochastic Volatility Model Calibration** – Calibrating European option surfaces using stochastic volatility dynamics modeled via Square-Root Feller processes. → skip: quantitative-finance domain
1456. **SABR Model Calibration** – Fitting implied volatility smiles using Stochastic Alpha, Beta, Rho model parameterization. → skip: quantitative-finance domain
1457. **Historical Value at Risk (VaR)** – Calculating maximum portfolio losses at specific confidence levels (95%,99%) by ranking historical returns directly. → `e.algo.stat.quantile`
1458. **Parametric Value at Risk (VaR)** – Computing portfolio loss distribution bounds using portfolio return means, standard deviations, and covariance matrices. → skip: quantitative-finance domain
1459. **Monte Carlo Value at Risk (VaR)** – Simulating thousands of forward market paths to estimate non-linear portfolio loss distributions. → skip: quantitative-finance domain
1460. **Conditional Value at Risk (CVaR / Expected Shortfall)** – Measuring expected tail losses exceeding specified Value at Risk thresholds. → `e.algo.stat.expected_shortfall`
1461. **Markowitz Mean-Variance Optimization** – Constructing efficient investment portfolios that maximize expected return for given levels of target portfolio variance. → `e.math.opt.convex.quadratic_program`
1462. **Black-Litterman Portfolio Model** – Blending market equilibrium returns with subjective investor views using Bayesian updating to produce stable portfolio weights. → skip: quantitative-finance domain
1463. **Limit Order Book (LOB) Matching Engine** – Executing financial trades by maintaining price-time priority arrays across bid and ask queues. → skip: quantitative-finance domain
1464. **Order Flow Imbalance (OFI) Signal Computation** – Measuring net order flow changes across top-of-book quotes to forecast short-term price movements. → skip: quantitative-finance domain
1465. **Volume-Weighted Average Price (VWAP) Execution** – Slicing large parent orders into historical volume distribution buckets to minimize execution market impact. → skip: quantitative-finance domain
1466. **Time-Weighted Average Price (TWAP) Execution** – Splitting orders evenly across fixed time intervals to achieve benchmark average price executions. → skip: quantitative-finance domain
1467. **Almgren-Chriss Optimal Execution Framework** – Formulating optimal order liquidation trajectories balancing market impact costs against inventory risk volatility. → skip: quantitative-finance domain
1468. **Engle-Granger Two-Step Cointegration Test** – Detecting stationary mean-reverting linear combinations between non-stationary asset price series for pairs trading. → skip: quantitative-finance domain
1469. **Johansen Cointegration Test Engine** – Testing for multiple cointegrating vectors across multivariate time series using vector autoregressive models. → skip: quantitative-finance domain
1470. **Kalman Filter Dynamic Hedge Ratio Estimation** – Tracking time-varying hedge ratios (β) dynamically between cointegrated pairs trading assets. → see #518 (`e.math.filter.ekf`)
1471. **Zero-Coupon Yield Curve Bootstrapping** – Extracting zero-coupon discount factors sequentially from observed market cash rates, futures, and interest rate swaps. → skip: quantitative-finance domain
1472. **Overnight Index Swap (OIS) Discounting Engine** – Discounting derivative cash flows using risk-free OIS rates (SOFR, ESTR) to construct multi-curve frameworks. → skip: quantitative-finance domain
1473. **Merton Structural Credit Risk Model** – Modeling company default probabilities by evaluating firm asset value processes as European call options over liabilities. → skip: quantitative-finance domain
1474. **CreditMetrics Portfolio Simulation** – Simulating credit migration and default correlation across debt portfolios to calculate Value at Risk. → skip: quantitative-finance domain
1475. **Vasicek Short-Rate Interest Rate Model** – Modeling interest rate evolution using mean-reverting stochastic differential equations. → skip: quantitative-finance domain
1476. **Cox-Ingersoll-Ross (CIR) Interest Rate Model** – Modeling short-term interest rates using square-root diffusion processes to ensure non-negative rates. → skip: quantitative-finance domain
1477. **Heath-Jarrow-Morton (HJM) Framework** – Modeling the entire forward rate curve dynamically driven by multi-factor volatility structures. → skip: quantitative-finance domain
1478. **Hull-White One-Factor Model** – Extending the Vasicek model with time-varying parameters to fit current term structures of interest rates exactly. → skip: quantitative-finance domain
1479. **Longstaff-Schwartz American Option Pricing** – Pricing American-style options in Monte Carlo simulations using least-squares regressions to estimate early exercise values. → skip: quantitative-finance domain
1480. **Stochastic Volatility Inspired (SVI) Parametrization** – Fitting arbitrage-free implied volatility smiles across option expiry slices using smooth curves. → skip: quantitative-finance domain
1481. **Dupire's Local Volatility Model** – Extracting unique local volatility surface functions directly from continuous European option market prices. → skip: quantitative-finance domain
1482. **Delta-Gamma Financial Hedging Engine** – Rebalancing options portfolios by offsetting first-order (Δ) and second-order (Γ) price sensitivities relative to underlying movement. → skip: quantitative-finance domain
1483. **Square Root Law of Market Impact** – Modeling price impact (ΔP) of large institutional orders as proportional to volatility and the square root of relative size (V / V_daily). → skip: quantitative-finance domain
1484. **Avellaneda-Stoikov Market Making Model** – Computing optimal bid-ask spread quotes and reservation prices for market makers managing inventory risk. → skip: quantitative-finance domain
1485. **High-Frequency LOB Feature Extraction** – Calculating real-time features (micro-price, order book slope, queue depth ratios) to drive high-frequency trading alphas. → skip: quantitative-finance domain
1486. **Smart Order Router (SOR) Execution Engine** – Routing liquidity sweeps across multiple competing exchanges to fill orders at optimal prices. → skip: quantitative-finance domain
1487. **Optimal Stopping Boundary Computation** – Calculating exercise boundaries for early-exercise financial derivatives using free-boundary PDE solvers. → skip: quantitative-finance domain
1488. **PCA Yield Curve Factor Decomposition** – Decomposing yield curve shifts into dominant orthogonal factors: Level, Slope, and Curvature. → see #732 (`e.ml.reduce.pca`)
1489. **Copula Dependency Modeling (Gaussian / t-Copula)** – Joining marginal asset return distributions to model non-linear joint tail dependencies in credit derivatives. → `e.algo.rand.dist.copula_gaussian`
1490. **Credit Default Swap (CDS) Hazard Rate Bootstrapping** – Extracting term structures of default probabilities from market CDS credit spreads. → skip: quantitative-finance domain
1491. **Collateralized Loan Obligation (CLO) Cash Flow Waterfall** – Simulating interest and principal payment distribution rules across structured tranche priorities (Equity, Mezzanine, Senior AAA). → skip: quantitative-finance domain
1492. **Constant Proportion Portfolio Insurance (CPPI)** – Dynamically rebalancing portfolio exposure between risky assets and safe assets based on cushions over guaranteed floors. → skip: quantitative-finance domain
1493. **Risk Parity Portfolio Allocation** – Weighting portfolio assets such that each asset class contributes equally to total portfolio risk variance. → skip: quantitative-finance domain
1494. **Kelly Criterion Optimal Position Sizing** – Calculating optimal capital allocation fractions (f∗ = pb−q) to maximize long-term logarithmic growth of wealth. b → skip: quantitative-finance domain
1495. **Sharpe, Sortino, and Information Ratio Calculation** – Evaluating risk-adjusted investment returns relative to total volatility, downside deviation, and benchmark tracking error. → skip: quantitative-finance domain
1496. **Deflated Sharpe Ratio (DSR)** – Adjusting observed Sharpe ratios to account for selection bias, non-normality, and multiple backtest trial evaluations. → skip: quantitative-finance domain
1497. **Markov-Switching Autoregressive Model** – Detecting changing market regimes (high volatility vs low volatility) by modeling transition probabilities between unobserved states. → skip: quantitative-finance domain
1498. **GARCH(1,1) Volatility Forecasting** – Modeling time-varying financial volatility clustering based on past squared residuals and previous variance estimates. → `e.algo.timeseries.garch`
1499. **Alpha Signal Decay Modeling** – Tracking predictive decay rates of quantitative signals over time to determine optimal rebalancing frequencies. → skip: quantitative-finance domain
1500. **Hawkes Self-Exciting Point Process** – Modeling high-frequency trade arrival clusters and order book flash crashes via self-exciting point processes.  Yes do it → `e.algo.timeseries.hawkes`

## 26. Machine Learning Systems, LLM Infrastructure & AI Engineering (1501–1550)

1501. **FlashAttention-2 Kernel Optimization** – IO-aware exact attention algorithm minimizing GPU HBM reads/writes via tiling and online softmax scaling. → see #754 (`e.gpu.attention_flash`)
1502. **Quantized Low-Rank Adaptation (QLoRA)** – Parameter-efficient fine-tuning method utilizing 4-bit NormalFloat (NF4) quantization and double quantization. → skip: a trained ML model or training recipe
1503. **Grouped-Query Attention (GQA)** – Attention mechanism partitioning key-value heads into groups to balance inference memory bandwidth and model capacity. → skip: a trained ML model or training recipe
1504. **PagedAttention Virtual Memory Management** – Attention algorithm managing KV-cache memory using dynamic page allocation to eliminate internal fragmentation (vLLM). → skip: a whole service or system, not a function
1505. **Tensor Parallelism (Megatron-LM)** – Intra-layer model parallelism splitting weight matrices across matrix multiplication operations in multi-GPU nodes. → skip: a whole service or system, not a function
1506. **Pipeline Parallelism (GPipe / 1F1B Schedule)** – Inter-layer parallelism partitioning model layers sequentially across nodes using One-Forward-One-Backward scheduling. → skip: a whole service or system, not a function
1507. **DeepSpeed ZeRO Memory Optimization** – Memory redundancy elimination partitioning optimizer states (ZeRO-1), gradients (ZeRO-2), and parameters (ZeRO-3) across data-parallel ranks. → skip: a whole service or system, not a function
1508. **Speculative Decoding with Draft Models** – Accelerating inference latency by using lightweight draft models to generate candidate tokens verified in parallel by target models. → skip: a trained ML model or training recipe
1509. **Rotary Position Embedding (RoPE)** – Incorporating explicit relative positional information into self-attention by applying rotation matrices to query/key vectors. → see #753 (`e.ml.nn.rope`)
1510. **Continuous Batching Engine** – Dynamic iteration-level scheduling algorithm batching incoming text generation requests at every forward step. → skip: a whole service or system, not a function
1511. **Direct Preference Optimization (DPO)** – Parameter alignment method optimizing language model preferences analytically without training explicit reward models or using PPO. → skip: a trained ML model or training recipe
1512. **Mixture of Experts (MoE) Top-k Gating** – Dynamic routing mechanism directing input tokens to sub-networks (experts) using auxiliary load-balancing losses. → skip: a trained ML model or training recipe
1513. **Activation Checkpointing** – Memory-saving technique recomputing intermediate activations during backward passes instead of caching them in GPU memory. → skip: a trained ML model or training recipe
1514. **Activation-aware Weight Quantization (AWQ)** – Quantizing LLM weights to 3-bit/4-bit precisions by protecting top 1% salient activation channels. → skip: a trained ML model or training recipe
1515. **Hierarchical Navigable Small World (HNSW)** – Multi-layer graph algorithm executing approximate nearest neighbor (ANN) vector search in O(log N) time. → see #1226 (`e.ml.ann.hnsw`)
1516. **Inverted File Index with Product Quantization (IVF-PQ)** – Vector indexing scheme combining Voronoi space partitioning with compressed vector quantization. → see #1227 (`e.ml.ann.ivf_pq`)
1517. **Retrieval-Augmented Generation (RAG) Reciprocal Rank Fusion** – Combining document retrieval scores across disparate vector and keyword search pipelines. → see #1224 (`e.text.rank.reciprocal_rank_fusion`)
1518. **OpenAI Triton GPU Compiler** – Domain-specific C-based programming language and compiler compiling high-level Python code into optimized NVIDIA PTX code. → skip: a vendor product's architecture
1519. **Unified Heterogeneous GPU Memory Management** – Mapping host RAM and GPU VRAM into unified virtual address spaces to handle dynamic model offloading. → skip: a whole service or system, not a function
1520. **Distributed Data Parallel (DDP) AllReduce Overlap** – Overlapping backward pass gradient computations with asynchronous ring-AllReduce network communications. → skip: a whole service or system, not a function
1521. **Knowledge Distillation KL-Divergence Matching** – Training compact student networks by minimizing Kullback-Leibler divergence relative to teacher probability distributions. → `e.ml.loss.kl_divergence`
1522. **ZeRO-Infinity NVMe Memory Offloading** – Leveraging NVMe memory architectures to offload massive model states beyond standard system RAM bounds. → skip: a whole service or system, not a function
1523. **Lottery Ticket Hypothesis Pruning** – Identifying sparse, trainable sub-networks within dense initializations that achieve baseline accuracy. → skip: a trained ML model or training recipe
1524. **Direct Feedback Alignment (DFA)** – Biologically plausible backpropagation alternative transmitting error signals directly from output layers to hidden layers using fixed random matrices. → skip: research-grade, no settled practical implementation
1525. **CLIP Multimodal Embedding Alignment** – Jointly training text and image encoders using contrastive loss functions over cross-modal pairs. → skip: a trained ML model or training recipe
1526. **Denoising Diffusion Implicit Models (DDIM)** – Accelerating diffusion model sampling by formulating generation as deterministic non-Markovian forward processes. → skip: a trained ML model or training recipe
1527. **Low-Rank Adaptation (LoRA)** – Parameter-efficient fine-tuning injecting trainable rank decomposition matrices (A × B) into frozen linear weights. → skip: a trained ML model or training recipe
1528. **Byte-Pair Encoding (BPE) Tokenization** – Iteratively merging common adjacent byte pairs to build subword vocabulary dictionaries. → see #373 (`e.text.tokenize.bpe`)
1529. **Automatic Mixed Precision (AMP) Dynamic Scaling** – Running model computations in FP16/BF16 while dynamically scaling loss to prevent floating-point underflow. → skip: a trained ML model or training recipe
1530. **AI Agent ReAct Loop Execution** – Iterative prompt control architecture interleaving reasoning steps ("Thought") with environmental execution tools ("Action"). → skip: a whole service or system, not a function
1531. **Graph Neural Network (GNN) Neighbor Sampling** – Scalable training scheme approximating full graph aggregations by sampling localized node neighborhoods. → skip: a trained ML model or training recipe
1532. **Differentiable Architecture Search (DARTS)** – Relaxing discrete neural architecture search spaces into continuous differentiable optimization problems. → skip: research-grade, no settled practical implementation
1533. **Feature Store Low-Latency Serving (Feast/Tecton)** – Maintaining synchronized offline batch data and online low-latency KV stores for real-time model inference features. → skip: a vendor product's architecture
1534. **Concept Drift Detection (KS-Test / PSI)** – Monitoring statistical distribution shifts in inference inputs using Kolmogorov-Smirnov tests and Population Stability Indexes. → `e.algo.stat.test.ks`
1535. **ML Metadata Lineage Tracking Graphs** – Tracking operational provenance across datasets, pipelines, hyperparameters, and model artifacts as directed acyclic graphs. → skip: a vendor product's architecture
1536. **Attention Softmax Scaling Factor ( 1 )** – Scaling dot-product attention queries and d k keys to prevent softmax gradients from vanishing at large dimensionality. → see #751 (`e.ml.nn.attention`)
1537. **Structured Guardrails & Grammar Enforcers** – Steering LLM output generation at the token sampling level using Pushdown Automata and Context-Free Grammars. → `e.parse.constrained_decode`
1538. **Hogwild! Lock-Free Asynchronous SGD** – Parallel stochastic gradient descent allowing worker threads to read and update shared parameters without synchronization locks. → skip: implementable, but too specialised for the standard library
1539. **L-BFGS Optimization for Deep Learning** – Quasi-Newton optimization algorithm approximating Hessian matrix inversions using limited past gradient vectors. → see #778 (`e.math.opt.lbfgs`)
1540. **Sharpness-Aware Minimization (SAM)** – Optimization algorithm seeking model parameters in flat loss terrain neighborhoods to improve model generalization. → skip: a trained ML model or training recipe
1541. **AdamW Decoupled Weight Decay** – Correcting standard L2 regularization implementation in Adam by decoupling weight decay from adaptive gradient updates. → see #750 (`e.ml.optim.adamw`)
1542. **Cosine Annealing Learning Rate Schedule** – Decay schedule decreasing learning rates following cosine curves with periodic warm restarts. → `e.ml.optim.cosine_schedule`
1543. **MinHash LSH Data Deduplication** – Locality-Sensitive Hashing filtering redundant text records across massive pre-training corpora using Jaccard similarity bounds. → see #1096 (`e.ml.ann.minhash_lsh`)
1544. **Reinforcement Learning from Human Feedback (RLHF)** – Aligning model output distributions using Proximal Policy Optimization (PPO) against learned reward models. → skip: a trained ML model or training recipe
1545. **Tree-of-Thoughts (ToT) Search Decoding** – Framework generalizing language model decoding over explicit tree structures using Breadth-First or Depth-First tree searches. → skip: a trained ML model or training recipe
1546. **Multimodal Cross-Attention Projection** – Aligning dense vector representations across visual encoders and text decoders via cross-attention layers. → skip: a trained ML model or training recipe
1547. **On-Device NPU Weight INT4 Quantization** – Optimizing language models for mobile Neural Processing Units using uniform post-training vector quantization. → skip: a trained ML model or training recipe
1548. **Selective Concept Erasure (Machine Unlearning)** – Removing specific learned facts or protected data from trained neural network parameters without full retraining. → skip: research-grade, no settled practical implementation
1549. **Federated Learning Differential Privacy (FedAvg)** – Aggregating distributed edge-device weight updates locally before adding Gaussian noise to guarantee client privacy bounds. → skip: a trained ML model or training recipe
1550. **Contrastive Decoding** – Enhancing text generation quality by evaluating log-likelihood differences between large target models and small amateur models. → `e.ml.sample.contrastive`

## 27. Networks, Telecommunications & Distributed Protocols (1551–1600)

1551. **BGP Path Vector Routing Protocol** – Inter-domain routing protocol exchanging AS-PATH attributes to compute policy-driven loop-free network paths. → skip: network protocol beyond the library scope
1552. **Multipath TCP (MPTCP)** – Transport protocol enabling single socket connections to stream data across multiple network interfaces simultaneously. → skip: OS kernel internals
1553. **QUIC Protocol Connection Migration** – UDP-based transport protocol maintaining active connections across client IP shifts using unique 64-bit Connection IDs. → `e.net.quic.migrate`
1554. **HTTP/3 Binary Frame Multiplexing** – Layering application communications over independent QUIC streams to eliminate TCP head-of-line blocking. → `e.net.http3.frames`
1555. **Segment Routing over IPv6 (SRv6)** – Source-routing architecture encoding packet forwarding paths directly into ordered IPv6 extension header segment lists. → skip: network protocol beyond the library scope
1556. **MPLS Label Distribution Protocol (LDP)** – Distributing label-to-prefix mappings across router nodes to build Label Switched Paths (LSPs). → skip: network protocol beyond the library scope
1557. **Software-Defined Networking (SDN) OpenFlow Pipeline** – Decoupling network control planes from data planes using centralized controllers to inject flow tables into switches. → skip: network protocol beyond the library scope
1558. **Network Function Virtualization (NFV) Service Chaining** – Directing traffic steering dynamically through sequential virtual network functions (firewalls, NATs, load balancers). → skip: a whole service or system, not a function
1559. **Virtual Extensible LAN (VXLAN)** – Layer 2 overlay scheme encapsulating Ethernet frames inside UDP packets using 24-bit Network Identifiers (VNIs). → skip: network protocol beyond the library scope
1560. **Ethernet EVPN Control Plane** – Utilizing MP-BGP to distribute Layer 2 MAC and Layer 3 IP reachability information across network fabrics. → skip: network protocol beyond the library scope
1561. **ICE/STUN/TURN NAT Traversal** – Framework discovering peer-to-peer communication paths across restrictive network NAT boundaries. → `e.net.stun.gather_candidates`
1562. **Bidirectional Forwarding Detection (BFD)** – Lightweight protocol detecting link interface failures across intermediate physical hops within sub-second thresholds. → skip: network protocol beyond the library scope
1563. **TCP BBR Congestion Control Algorithm** – Model-based congestion control dynamically measuring Bottleneck Bandwidth and Round-Trip Time (RTT) to maximize throughput without bufferbloat. → skip: OS kernel internals
1564. **Explicit Congestion Notification (ECN)** – Router mechanism marking IP headers (CE bits) during congestion to trigger client rate reductions without dropping packets. → skip: OS kernel internals
1565. **Wi-Fi 7 Multi-Link Operation (MLO)** – Wireless communication standard aggregating 2.4 GHz, 5 GHz, and 6 GHz radio bands across single device connections simultaneously. → skip: hardware or circuit design
1566. **5G Massive MIMO Beamforming** – Concentrating spatial antenna radio signals dynamically toward targeted mobile user devices using active phased arrays. → skip: hardware or circuit design
1567. **5G Network Slicing & User Plane Function (UPF)** – Partitioning single physical 5G infrastructure into isolated virtual end-to-end networks optimized for distinct SLAs. → skip: network protocol beyond the library scope
1568. **LEO Satellite Inter-Satellite Laser Links (ISLL)** – Routing internet traffic across low-Earth-orbit satellite constellations via optical laser transceivers in space. → skip: hardware or circuit design
1569. **DNSSEC Trust Chain Validation** – Cryptographically verifying DNS records by building chains of trust from target RRSIG records up to root domain keys. → see #1408 (`e.net.dns.dnssec_validate`)
1570. **Constrained Application Protocol (CoAP)** – Specialized binary web transfer protocol executing HTTP-like operations over UDP for resource-constrained IoT devices. → `e.net.coap.request`
1571. **MQTT Quality of Service (QoS 0, 1, 2) Protocols** – IoT messaging guarantees spanning At-Most-Once, At-Least-Once, and Exactly-Once delivery handshakes. → `e.net.mqtt.publish`
1572. **LoRaWAN Adaptive Data Rate (ADR)** – Dynamic optimization scheme tuning data rates, airtime, and transmission power for long-range, low-power IoT devices. → skip: hardware or circuit design
1573. **RIP Split Horizon with Poison Reverse** – Preventing routing loops by advertising unreachable metrics (16 hops) back on interfaces where routes were learned. → skip: network protocol beyond the library scope
1574. **OSPF Link-State Advertisement (LSA) Flooding** – Propagating topological changes across OSPF areas to ensure identical Link-State Databases (LSDBs) on all routers. → skip: network protocol beyond the library scope
1575. **IEEE 802.1Q VLAN & QinQ Double Tagging** – Multiplexing network segments by injecting 12-bit VLAN IDs into Ethernet frames, extended via nested service provider tags. → skip: network protocol beyond the library scope
1576. **Link Aggregation Control Protocol (LACP)** – Combining multiple physical network interfaces into single logical channels to multiply bandwidth and provide redundancy. → skip: network protocol beyond the library scope
1577. **Carrier-Grade NAT (CGNAT) Port Block Allocation** – Translating private IP addresses across thousands of subscribers by pre-allocating contiguous outbound port blocks per user. → skip: network protocol beyond the library scope
1578. **DNS over HTTPS (DoH) / DNS over TLS (DoT)** – Encrypting plain-text DNS queries inside TLS tunnels to prevent eavesdropping and DNS spoofing. → `e.net.dns.query_doh`
1579. **Spanning Tree Protocol (RSTP / MSTP)** – Eliminating physical loops in switched Ethernet networks by calculating non-blocking tree topologies. → skip: network protocol beyond the library scope
1580. **Dynamic ARP Inspection (DAI)** – Mitigating ARP poisoning attacks by validating network address bindings against trusted DHCP snooping databases. → skip: network protocol beyond the library scope
1581. **Precision Time Protocol (IEEE 1588 PTP)** – Hardware-timestamped synchronization protocol achieving sub-microsecond clock alignment across distributed network nodes. → skip: OS kernel internals
1582. **NTP Marzullo's Intersection Algorithm** – Selecting optimal time synchronization sources by identifying overlapping confidence intervals among noisy clock sources. → see #149 (`e.time.sync.marzullo`)
1583. **TCP Fast Open (TFO)** – Accelerating TCP session setup by enabling cryptographic cookie validation and initial payload transfers inside SYN packets. → skip: OS kernel internals
1584. **FQ-CoDel Active Queue Management** – Combining Fair Queueing with Controlled Delay algorithms to prevent bufferbloat and manage latency across bottleneck queues. → skip: OS kernel internals
1585. **ICMP Path MTU Discovery (PMTUD)** – Dynamically determining the maximum transmission unit (MTU) size across end-to-end network paths using ICMP "Fragmentation Needed" messages. → skip: OS kernel internals
1586. **Generic Routing Encapsulation (GRE)** – Tunneling arbitrary network layer protocols by encapsulating payloads inside standard IP transport headers. → skip: network protocol beyond the library scope
1587. **WireGuard Noise IK Pattern Key Handshake** – Modern VPN protocol establishing noise-authenticated, single-round-trip key exchanges over UDP. → `e.crypto.noise.handshake_ik`
1588. **BGP Route Reflector Topologies** – Eliminating full-mesh internal BGP (iBGP) requirements by re-advertising routes through centralized reflector nodes. → skip: network protocol beyond the library scope
1589. **Graceful Restart Routing Protocols** – Preserving packet forwarding hardware state while routing control plane daemons restart following crashes. → skip: network protocol beyond the library scope
1590. **P4 Network Data Plane Programmability** – Hardware-independent domain-specific language defining how packets are parsed, processed, and forwarded in network switches. → skip: hardware or circuit design
1591. **Data Center Bridging Priority Flow Control (PFC)** – Eliminating packet loss over Ethernet fabrics by issuing pause frames per IEEE 802.1p priority class. → skip: hardware or circuit design
1592. **RDMA over Converged Ethernet Version 2 (RoCEv2)** – Remote Direct Memory Access protocol routing memory transfers across UDP Layer 3 networks. → skip: hardware or circuit design
1593. **InfiniBand Credit-Based Flow Control** – Hardware flow control mechanism preventing buffer overflows by issuing transmitter credits per virtual lane. → skip: hardware or circuit design
1594. **Dynamic Multipoint VPN (DMVPN) NHRP** – Building dynamic, mesh-connected IPsec VPN tunnels across spoke sites using Next Hop Resolution Protocol. → skip: network protocol beyond the library scope
1595. **High-Availability Seamless Redundancy (HSR)** – Zero-failover redundancy protocol duplicating frames across dual-port ring topologies in industrial Ethernet systems. → skip: network protocol beyond the library scope
1596. **Loop-Free Alternate (LFA) Fast Reroute** – Pre-computing backup IP paths to redirect traffic in hardware immediately upon primary link failure detection. → skip: network protocol beyond the library scope
1597. **BGP EVPN VXLAN Integrated Routing and Bridging (IRB)** – Executing simultaneous Layer 2 bridging and Layer 3 routing within VXLAN fabric VTEPs. → skip: network protocol beyond the library scope
1598. **L2TPv3 Pseudo-wire Encapsulation** – Transporting Layer 2 protocols (Ethernet, Frame Relay, HDLC) directly across IP core backbones. → skip: network protocol beyond the library scope
1599. **IS-IS Link-State Routing Protocol** – Flexible interior gateway protocol routing IP and non-IP traffic using Type-Length-Value (TLV) data tuples. → skip: network protocol beyond the library scope
1600. **BGP Route Flap Damping** – Suppressing unstable, oscillating route announcements to protect global core routing tables from control plane instability. → skip: network protocol beyond the library scope

## 28. Operating Systems, Virtualization & Systems Programming (1601–1650)

1601. **Linux Completely Fair Scheduler (CFS)** – O(log N) task scheduling engine tracking virtual runtime (vruntime) via self-balancing Red-Black Trees. → skip: OS kernel internals
1602. **eBPF In-Kernel Virtual Machine** – Running sandboxed, bytecode-verified programs inside the Linux kernel to extend networking, tracing, and security functionality dynamically. → skip: OS kernel internals
1603. **Linux cgroups v2 Unified Hierarchy** – Kernel resource management subsystem organizing system resources (CPU, Memory, I/O, PIDs) into unified hierarchical trees. → skip: OS kernel internals
1604. **Linux Namespaces (PID, Mount, Net, User)** – Kernel abstraction isolates system resources per container process, masking underlying operating system states. → skip: OS kernel internals
1605. **Virtual Memory Page Table Walks** – Translating virtual memory addresses to physical memory addresses using multi-level hardware page tables and Translation Lookaside Buffers (TLB). → skip: OS kernel internals
1606. **Linux Copy-on-Write (CoW) Fork** – Deferring memory page duplication during fork() operations until child or parent processes write to pages. → skip: OS kernel internals
1607. **Linux Page Cache Writeback Engine** – Managing dirty page flushing asynchronously from main RAM to block storage using system flusher threads. → skip: OS kernel internals
1608. **Linux Futex (Fast Userspace Mutex)** – Fast synchronization primitive managing uncontested locks entirely in user space while delegating contested locks to kernel wait queues. → `e.os.wait_u32`
1609. **Linux epoll Event Multiplexing** – High-performance I/O event notification mechanism returning ready file descriptors in O(1) time via shared memory ring buffers. → `e.async.poll`
1610. **Linux SLUB Memory Allocator** – Unifying kernel memory allocation by managing object slabs without per-slab metadata overhead or fragmenting physical pages. → skip: OS kernel internals
1611. **Linux Auto-NUMA Memory Balancing** – Migrating physical memory pages and tasks dynamically to place data on NUMA nodes local to processing threads. → skip: OS kernel internals
1612. **Virtual File System (VFS) Inode & Dentry Caches** – Linux kernel Abstraction layer providing unified file access interfaces via LRU-managed dentry and inode objects. → skip: OS kernel internals
1613. **KVM Hardware-Assisted Virtualization** – Turning Linux kernels into Type-1 hypervisors using Intel VT-x or AMD-V CPU instructions. → skip: OS kernel internals
1614. **Xen Hypervisor Paravirtualization (PV)** – Virtualization approach modifying guest operating system kernels to issue hypercalls directly to underlying hypervisors. → skip: OS kernel internals
1615. **QEMU Dynamic Binary Translation** – Emulating non-native CPU instruction architectures by translating guest target instructions to host instructions at runtime. → skip: implementable, but too specialised for the standard library
1616. **SR-IOV PCIe Virtualization** – Partitioning single physical PCI Express hardware devices into multiple isolated Virtual Functions (V F) mapped directly to virtual machines. → skip: hardware or circuit design
1617. **MicroVM Execution Environments (Firecracker)** – Lightweight virtual machines leveraging KVM to launch isolated user spaces in milliseconds with minimal memory footprints. → skip: a vendor product's architecture
1618. **Linux Seccomp-BPF System Call Filtering** – Restricting process capabilities by intercepting system calls using configurable eBPF filter programs. → `e.os.sandbox`
1619. **Linux Mandatory Access Control (SELinux / AppArmor)** – Enforcing system access constraints based on security labels assigned to subjects and objects. → skip: OS kernel internals
1620. **Linux Kyber & BFQ I/O Schedulers** – Block-layer schedulers prioritizing throughput or latencies by calculating queue depth targets and budget allocations. → skip: OS kernel internals
1621. **Linux Out-Of-Memory (OOM) Killer** – Subsystem terminating high-badness processes when system RAM and swap capacity are completely exhausted. → skip: OS kernel internals
1622. **POSIX Thread Synchronization Primitives** – Managing concurrency via pthread mutexes, condition variables, read-write locks, and barrier abstractions. → `e.sync.mutex`
1623. **Memory-Mapped I/O ( mmap ) Execution** – Mapping storage files or physical hardware memory addresses directly into application virtual memory address spaces. → `e.fs.mmap.map`
1624. **Read-Copy-Update (RCU) Synchronization** – Lock-free kernel synchronization mechanism permitting readers concurrent access while writers defer reclamation until grace periods expire. → see #667 (`e.sync.rcu`)
1625. **Linux Kernel Module Loading ( insmod / modprobe )** – Dynamically linking compiled object code into running kernel spaces, resolving symbols on the fly. → skip: OS kernel internals
1626. **Linux Device Tree Compilation & Parsing** – Passing hardware structural descriptions to OS kernels via compiled flattened device trees ( .dtb ). → skip: OS kernel internals
1627. **systemd Service Dependency Graph Engine** – Parallelizing Linux boot execution by modeling service initializations as concurrent dependency graphs. → skip: a vendor product's architecture
1628. **Hardware Inter-Processor Interrupts (IPI)** – Low-level hardware signaling mechanism allowing individual CPU cores to trigger immediate execution events on other cores. → skip: hardware or circuit design
1629. **Linux Top-Half & Bottom-Half Interrupt Processing** – Splitting interrupt handling into fast critical tasks (Hard IRQ) and deferred processing (Softirqs, Tasklets, Workqueues). → skip: OS kernel internals
1630. **Linux Transparent Huge Pages (THP)** – Automatically consolidating standard 4KB memory pages into 2MB/1GB pages to reduce TLB cache misses. → skip: OS kernel internals
1631. **OverlayFS Multi-Layer Merging** – Union mount filesystem layering dynamic writeable file directories ( upperdir ) over read-only image bases ( lowerdir ). → skip: OS kernel internals
1632. **FUSE (Filesystem in Userspace)** – Executing custom file system logic inside user space programs by routing VFS requests through kernel modules. → skip: implementable, but too specialised for the standard library
1633. **Unikernel Execution Model** – Compiling application code together with minimal Library OS dependencies into single-address-space binary images running directly on hypervisors. → skip: a whole service or system, not a function
1634. **Linux Process Memory Layout** – Organizing process virtual address spaces into distinct segments: Text, Data, BSS, Heap, Memory Mapping, and Stack. → skip: OS kernel internals
1635. **Priority Inversion & Priority Inheritance Protocols** – Preventing high-priority thread starvation by temporarily elevating lower-priority threads holding required shared resource locks. → skip: OS kernel internals
1636. **Rate-Monotonic Scheduling (RMS)** – Deterministic real-time scheduling algorithm assigning higher priorities to tasks with shorter periodic interval execution cycles. → skip: OS kernel internals
1637. **Earliest Deadline First (EDF) Scheduling** – Dynamic real-time scheduling algorithm prioritizing tasks closest to their execution deadlines. → see #657 (`e.thread.pool.edf`)
1638. **Memory Protection Keys (MPK)** – Intel hardware feature allowing user-space applications to toggle access permissions on memory pages without executing system calls. → skip: OS kernel internals
1639. **Intel Extended Page Tables (EPT)** – Hardware MMU feature executing two-dimensional page table walks (Guest Virtual → Guest Physical → Host Physical). → skip: hardware or circuit design
1640. **WASI Capability-Based Security Model** – WebAssembly System Interface constraining sandbox environments by requiring explicit file descriptor capabilities for system accesses. → skip: implementable, but too specialised for the standard library
1641. **Direct Threaded Interpreter Engine** – Accelerating virtual machine bytecode execution by replacing switch dispatch loops with arrays storing target instruction handler addresses directly. → skip: a technique applied per problem, not a reusable function
1642. **POSIX Signal Handling Subsystem** – Interrupting process control flows to execute registered signal routines upon receiving kernel signals ( SIGSEGV , SIGKILL , SIGINT ). → `e.os.signal`
1643. **Linux Kernel Dynamic Probing (kprobes / uprobes)** – Attaching debug handlers dynamically to arbitrary kernel or user space instruction addresses without recompilation. → skip: OS kernel internals
1644. **Hardware Performance Monitor Units (PMU)** – Reading specialized CPU registers to profile cycle counts, instruction retirements, and cache misses ( perf ). → skip: implementable, but too specialised for the standard library
1645. **Core Dump Generation & Memory Parsing** – Writing complete process memory images to ELF binary files upon fatal system crashes for post-mortem analysis. → skip: implementable, but too specialised for the standard library
1646. **Linux Pressure Stall Information (PSI)** – Real-time metrics monitoring hardware resource starvation across CPU, Memory, and I/O subsystems. → skip: OS kernel internals
1647. **Linux zram Compressed Block Device** – Offloading memory pressures by creating compressed RAM block devices that act as fast swap spaces. → skip: OS kernel internals
1648. **Rust Compile-Time Ownership & Borrow Checker** – Enforcing thread safety and memory safety statically without garbage collectors by enforcing strict reference ownership lifetimes. → skip: belongs in the Neper compiler, not the library
1649. **C++11 Memory Model & Sequential Consistency** – Language-level primitives defining hardware atomic operation visibility and memory ordering constraints across threads. → see #1327 (`e.atomic.load_acquire`)
1650. **Hardware Transactional Memory (Intel TSX)** – Execution model speculatively executing memory operations in hardware, aborting and rolling back if data conflicts occur. → skip: hardware or circuit design

## 29. Database Engines, Storage Systems & Big Data Architecture (1651–1700)

1651. **B+ Tree Index Structural Operations** – Self-balancing search tree keeping data in linked leaf nodes, guaranteeing O(log N) search, insert, and sequential range scans. → see #193 (`e.data.btree.insert`)
1652. **LSM-Tree MemTable, WAL & SSTable Mechanics** – Write-optimized storage architecture buffering writes in volatile MemTables before flushing immutable, sorted SSTables to disk. → see #863 (`e.db.storage.memtable_flush`)
1653. **LSM-Tree Leveled vs. Size-Tiered Compaction** – Merging overlapping SSTable files to minimize read amplification factors or control write amplification penalties. → see #717 (`e.db.storage.lsm_compact`)
1654. **ARIES Database Recovery Algorithm** – Crash recovery protocol executing three sequential passes: Analysis, Redo (repeating history), and Undo (rolling back uncommitted transactions). → see #719 (`e.db.storage.recover`)
1655. **Multi-Version Concurrency Control (MVCC)** – Database isolation engine enabling lock-free reads by storing concurrent transaction row versions. → see #870 (`e.db.storage.txn_mvcc`)
1656. **PostgreSQL Heap-Only Tuples (HOT)** – Optimizing update performance by storing updated tuple versions on the same data page, eliminating index update overheads. → skip: a vendor product's architecture
1657. **MySQL InnoDB Buffer Pool Management** – Managing cached database pages in RAM using LRU lists split into young and old sub-segments to prevent table scan pollution. → see #866 (`e.db.storage.buffer_pool_evict`)
1658. **SQLite Write-Ahead Logging (WAL)** – Appending concurrent database writes to separate WAL files, enabling non-blocking reads during active transactions. → see #718 (`e.db.storage.wal_append`)
1659. **Apache Cassandra Distributed Consistent Hashing** – Ring-based distributed NoSQL database mapping data keys to cluster token ranges using Murmur3 hashing. → skip: a vendor product's architecture
1660. **Apache Parquet Columnar Compression Encoding** – Efficient binary file format organizing data by columns using Dictionary, Run-Length (RLE), and Bit-Packing encodings. → `e.fmt.parquet.decode`
1661. **Apache Iceberg Snapshot-Based Table Format** – Open table format providing ACID guarantees on object stores using explicit JSON/AVRO metadata manifests. → skip: a vendor product's architecture
1662. **Delta Lake ACID Transaction Log Protocol** – Storage layer maintaining transactional consistency over cloud object stores using ordered JSON delta logs. → skip: a vendor product's architecture
1663. **ClickHouse Vectorized Columnar Engine** – High-throughput OLAP database processing data blocks in memory using SIMD CPU instructions over columnar storage. → skip: a vendor product's architecture
1664. **Apache Druid Real-Time Segment Indexing** – Distributed OLAP store indexing time-series data into immutable columnar segments containing dictionary-encoded inverted bitmaps. → skip: a vendor product's architecture
1665. **Snowflake Multi-Cluster Shared-Data Architecture** – Decoupling compute virtual warehouses from centralized cloud storage objects to scale storage and compute independently. → skip: a vendor product's architecture
1666. **Google BigQuery Dremel Execution Tree** – Serverless query engine organizing parallel execution nodes into hierarchical execution trees to aggregate columnar data. → skip: a vendor product's architecture
1667. **Volcano Query Processing Iterator Model** – Classic relational query engine processing data tuples sequentially via open-next-close iterator interfaces. → see #885 (`e.db.query.iterator`)
1668. **Cost-Based Query Optimizer (CBO)** – Query planner estimating physical plan execution costs using table histograms, column cardinalities, and join selectivity models. → `e.db.query.optimize`
1669. **Dynamic Programming Join Order Enumeration** – Generating optimal join trees for complex multi-table queries by evaluating sub-query execution costs. → `e.db.query.join_order`
1670. **Bloom Filter Data Skipping** – Probabilistic data structure evaluated against storage block headers to skip reading blocks lacking matching keys. → see #238 (`e.algo.sketch.bloom_contains`)
1671. **Z-Order Space-Filling Curves** – Mapping multi-dimensional spatial points to 1D data spaces to preserve data locality across multi-column query filters. → see #845 (`e.algo.geom.morton_encode`)
1672. **Google S2 Spatial Indexing System** – Projecting Earth's sphere onto a cube, indexing hierarchical grid cells using 64-bit Hilbert space-filling curve integers. → `e.algo.geo.s2_cell`
1673. **HikariCP High-Performance Connection Pooling** – Eliminating JDBC overheads using optimized byte-code generation and array-backed thread-local lock-free list structures. → `e.db.pool.acquire`
1674. **Distributed Hash Join Execution** – Partitioning build-side and probe-side datasets across network clusters using matching join key hash functions. → skip: a whole service or system, not a function
1675. **Database Index-Only Scans** – Executing queries entirely within index structures without reading underlying main table heap pages. → see #898 (`e.db.query.index_only_scan`)
1676. **Write Amplification Factor (WAF) in SSDs** – Measuring physical data written to flash media relative to logical data issued by host operating systems. → skip: hardware or circuit design
1677. **NVMe Flash Translation Layer (FTL)** – Solid-state drive controller firmware mapping logical block addresses (LBA) to physical flash memory locations while handling garbage collection. → skip: hardware or circuit design
1678. **Zoned Namespaces (ZNS) NVMe Interface** – Storage interface requiring sequential data writes into contiguous physical drive zones, bypassing standard SSD FTL garbage collection. → skip: hardware or circuit design
1679. **Erasure Coding (Reed-Solomon K + M)** – Object storage data protection splitting data objects into K data blocks and M parity blocks to survive M hardware failures. → see #854 (`e.algo.ecc.reed_solomon_decode`)
1680. **AWS DynamoDB Single-Table Design** – Data modeling technique representing multiple relational entities inside a single NoSQL table using overloaded primary/sort keys. → skip: a vendor product's architecture
1681. **CockroachDB Multi-Raft Partitioning** – Distributed SQL database partitioning keyspaces into dynamic contiguous ranges managed by independent Raft consensus groups. → skip: a vendor product's architecture
1682. **TiDB Distributed HTAP Engine** – Hybrid Transactional/Analytical Processing database replicating Raft row-based engine data (TiKV) asynchronously to columnar vector engines (TiFlash). → skip: a vendor product's architecture
1683. **Redis In-Memory AOF Append-Only File Rewrite** – Compacting transaction logs in the background into minimal instruction sets to keep recovery logs compact. → skip: a vendor product's architecture
1684. **Apache Flink Event Time & Watermarking** – Stream processing framework tracking event-time progress across out-of-order streams using monotonic watermark markers. → see #1297 (`e.data.stream.watermark`)
1685. **Apache Kafka Partition Log Compaction** – Retaining the most recent record value for every message key within a topic partition log on disk. → skip: a vendor product's architecture
1686. **Debezium Transaction Log Change Data Capture (CDC)** – Tapping database transaction logs directly to capture row-level mutations as real-time event streams. → skip: a vendor product's architecture
1687. **Data Mesh Federated Architecture** – Decentralized data architecture organizing data platforms into domain-driven data products with federated computational governance. → skip: a technique applied per problem, not a reusable function
1688. **Spanner Distributed Lock-Free Read Transactions** – Executing globally consistent read operations across multi-region databases without acquiring read locks, powered by TrueTime bounded uncertainty. → skip: a vendor product's architecture
1689. **B-Tree Write-Ahead Logging Frame Checkpointing** – Flushing dirty memory pages from RAM back to persistent database files to advance recovery checkpoints. → see #719 (`e.db.storage.recover`)
1690. **PostgreSQL Generalized Inverted Index (GIN)** – Multi-element index structure mapping composite column items (JSONB arrays, text search documents) to matching row IDs. → see #875 (`e.text.index.build`)
1691. **Data Lakehouse Format Manifest Evolution** – Metadata abstraction layers tracking structural schema changes and data file partitioning without rewriting underlying Parquet datasets. → skip: a vendor product's architecture
1692. **Apache Calcite Query Parser & Optimization Engine** – Extensible SQL parsing and optimization framework transforming AST expressions into physical query operators. → skip: a vendor product's architecture
1693. **Partition Pruning Engine** – Query optimizer pass static or dynamic execution paths to evaluate table partition constraints and ignore non-matching partition directories. → see #893 (`e.db.query.prune_partitions`)
1694. **Columnar Vectorized Execution Memory Alignment** – Structuring database memory arrays to align with CPU L1/L2 cache lines, maximizing SIMD instruction efficiency. → see #886 (`e.db.query.vectorized`)
1695. **Distributed Dynamic Shuffle Service** – Decoupling intermediate map-side shuffle outputs from streaming/batch execution nodes to persistent cluster storage nodes. → skip: a whole service or system, not a function
1696. **Storage Class Memory (PMEM) Byte-Addressable Persistence** – Programming memory-mapped persistence architectures directly over byte-addressable non-volatile RAM interfaces. → skip: hardware or circuit design
1697. **Redis Hash Slot Keyspace Partitioning** – Routing database commands across cluster nodes using CRC16 checksum modulo calculations over 16,384 slots. → skip: a vendor product's architecture
1698. **RabbitMQ AMQP Queue Architecture** – Decoupling producers and consumers by routing messages through exchanges to bound queues using binding keys. → skip: a vendor product's architecture
1699. **Apache Pulsar Decoupled Storage Topology** – Separating stateless serve nodes (Brokers) from stateful storage nodes (BookKeeper) to scale compute and storage independently. → skip: a vendor product's architecture
1700. **Vector Database Inverted File (IVF) Centroid Clustering** – Partitioning multi-dimensional vector spaces into Voronoi cells using k-means clustering to bound search queries. → see #1227 (`e.ml.ann.ivf_pq`)

## 30. Computer Vision, Graphics & Spatial Computing (1701–1750)

1701. **PBR Bidirectional Reflectance Distribution Function (BRDF)** – Mathematical model defining light reflection off surfaces, incorporating Fresnel, Roughness, and Metallic parameters. → `e.gfx.shade.brdf_ggx`
1702. **Monte Carlo Path Tracing** – Rendering algorithm estimating light transport integrals by firing random light paths through image pixels. → `e.gfx.trace.path_trace`
1703. **Bounding Volume Hierarchy (BVH) Traversal** – Accelerating ray-scene intersection tests by organizing geometric primitives into spatial tree hierarchies. → `e.data.spatial.bvh_traverse`
1704. **Radiance Cascades Global Illumination** – Spherical harmonic lighting technique organizing radiative transfer calculations into multi-resolution spatial cascades. → skip: research-grade, no settled practical implementation
1705. **Neural Radiance Fields (NeRF)** – Representing complex 3D scenes as continuous volumetric functions parameterized by deep multilayer perceptrons (MLP). → skip: a trained ML model or training recipe
1706. **3D Gaussian Splatting Rasterization** – Scene representation model rendering real-time 3D scenes by rasterizing anisotropic 3D Gaussians onto 2D image planes. → skip: a trained ML model or training recipe
1707. **Deferred Shading Rendering Pipeline** – Rendering architecture separating geometry pass execution from lighting computations by writing geometric properties to intermediate G-Buffers. → see #1113 (`e.gfx.scene.deferred`)
1708. **Screen-Space Ambient Occlusion (SSAO)** – Graphics technique approximating ambient occlusion shadows in real time by evaluating nearby depth-buffer differences around pixels. → see #1104 (`e.gfx.scene.ssao`)
1709. **Temporal Anti-Aliasing (TAA)** – Anti-aliasing method blending previous frame colors with current frames using motion vectors to reduce sub-pixel aliasing. → see #1110 (`e.gfx.scene.taa`)
1710. **DLSS / FSR Super Resolution Upscaling** – Enhancing low-resolution rendered frames to higher target resolutions using temporal reconstruction models or deep learning models. → skip: a trained ML model or training recipe
1711. **Vulkan / DirectX 12 Command Buffer Recording** – Explicit low-overhead graphics API paradigm recording draw commands across parallel CPU worker threads before submission to GPU queues. → skip: an implementation detail of an existing module, not an API
1712. **GPU Memory Pipeline Barriers & Fences** – Explicit synchronization primitives forcing memory visibility and instruction completion order between GPU pipeline stages. → skip: an implementation detail of an existing module, not an API
1713. **Mesh & Amplification Shaders** – Modern GPU geometry pipeline replacing legacy fixed-function processing with compute-like shader threads operating on meshlets. → skip: hardware or circuit design
1714. **Visual Simultaneous Localization and Mapping (V-SLAM)** – Estimating camera poses while concurrently constructing 3D spatial environment maps using visual sensor feeds. → skip: a whole service or system, not a function
1715. **Structure from Motion (SfM) 3D Reconstruction** – Reconstructing 3D point cloud geometry and camera positions from overlapping collections of 2D photographs. → `e.gfx.vision.structure_from_motion`
1716. **Epipolar Geometry & Fundamental Matrix Calculation** – Geometric relationship constrained across two stereo views, mapping points in one image to epipolar lines in another. → `e.gfx.vision.fundamental_matrix`
1717. **RANSAC (Random Sample Consensus) Model Estimation** – Iterative parameter estimation algorithm calculating geometric transformations in the presence of strong dataset outliers. → `e.gfx.vision.ransac`
1718. **Lucas-Kanade Optical Flow Sparse Tracking** – Calculating pixel motion vectors across sequential frames assuming spatial brightness constancy inside local pixel windows. → see #791 (`e.gfx.vision.optical_flow_lk`)
1719. **Scale-Invariant Feature Transform (SIFT)** – Computer vision algorithm detecting scale- and rotation-invariant feature keypoints across Difference-of-Gaussians scale spaces. → see #784 (`e.gfx.vision.sift`)
1720. **YOLO (You Only Look Once) One-Stage Object Detection** – Frame object detection framing bounding box coordinates and class probabilities as single regression problems. → skip: a trained ML model or training recipe
1721. **Mask R-CNN ROI Align Mechanics** – Preserving exact spatial locations in feature maps using bilinear interpolation to extract accurate pixel-level instance segmentation masks. → skip: a trained ML model or training recipe
1722. **Vision Transformer (ViT) Patch Embeddings** – Image processing architecture splitting images into non-overlapping spatial patches mapped into standard Transformer input sequences. → skip: a trained ML model or training recipe
1723. **Swin Transformer Shifted Window Attention** – Hierarchical Vision Transformer restricting self-attention calculations to local non-overlapping shifted windows. → skip: a trained ML model or training recipe
1724. **Segment Anything Model (SAM) Promptable Mask Engine** – Zero-shot image segmentation architecture generating object masks based on point, box, or text prompt inputs. → skip: a trained ML model or training recipe
1725. **Extended Kalman Filter (EKF) Sensor Fusion** – Fusing high-frequency IMU telemetry with lower-frequency visual camera frames to compute ultra-low-latency AR/VR head poses. → see #518 (`e.math.filter.ekf`)
1726. **Asynchronous Timewarp (ATW) VR Motion Latency Compensation** – Warping rendered VR frames based on updated head orientation telemetry right before display scanouts to mitigate motion sickness. → skip: implementable, but too specialised for the standard library
1727. **Foveated Rendering Pipeline** – Optimizing rendering performance by targeting full resolution at eye gaze points while reducing shading quality across peripheral vision. → skip: hardware or circuit design
1728. **Point Cloud Octree Space Partitioning** – Structuring non-uniform 3D point cloud collections into recursive octree spatial data structures. → see #220 (`e.data.spatial.octree_insert`)
1729. **Iterative Closest Point (ICP) Rigid Alignment** – Minimizing distances between point clouds iteratively to calculate rigid 3D spatial transformations. → `e.gfx.vision.icp`
1730. **Marching Cubes Isosurface Extraction** – Extracting 3D polygonal mesh surfaces from scalar volumetric density fields using lookup tables across voxel configurations. → see #551 (`e.gfx.mesh.marching_cubes`)
1731. **Signed Distance Functions (SDF) Sphere Tracing** – Ray-marching volumetric surfaces defined analytically as distance fields along ray paths. → see #1145 (`e.gfx.scene.sdf_raymarch`)
1732. **Cascaded Shadow Maps (CSM)** – Mitigating shadow perspective aliasing by splitting view frustums into multiple depth zones rendered into separate shadow maps. → see #1102 (`e.gfx.scene.shadow_cascades`)
1733. **Screen Space Reflections (SSR) Ray Marching** – Rendering real-time reflections by marching rays along depth buffer spaces to locate surface intersections. → see #1107 (`e.gfx.scene.ssr`)
1734. **Order-Independent Transparency (OIT) Depth Peeling** – Rendering transparent geometry accurately without pre-sorting polygons by peeling geometric layers across multiple depth passes. → `e.gfx.scene.depth_peel`
1735. **Position-Based Dynamics (PBD) Simulation** – Simulating physical constraints (cloth, soft bodies) by manipulating particle positions directly rather than integrating forces. → see #1119 (`e.game.physics.pbd_step`)
1736. **Smoothed Particle Hydrodynamics (SPH) Fluid Simulation** – Lagrangian computational fluid dynamics method modeling fluid flow as interacting particle masses. → see #1030 (`e.game.physics.sph`)
1737. **Eulerian Fluid Marker-And-Cell (MAC) Grids** – Simulating fluid motion on fixed spatial grids, decoupling velocity components across staggered cell faces. → `e.game.physics.fluid_mac`
1738. **Inverse Kinematics FABRIK Solver** – Solving joint positions along kinematic chains iteratively using forward and backward reaching passes. → see #1126 (`e.game.anim.ik_fabrik`)
1739. **SPIR-V Intermediate Shader Representation** – Cross-platform byte-code language compiling high-level shader code (HLSL, GLSL) into unified GPU pipeline representations. → skip: belongs in the toolchain (build, test runner, pacman)
1740. **Variable Rate Shading (VRS)** – Dynamically varying shading rates across screen space regions to allocate rendering power to visually salient areas. → skip: hardware or circuit design
1741. **GPU-Driven Bindless Rendering** – Architecture accessing thousands of material textures and buffers from unified descriptor arrays without per-draw binding state changes. → skip: hardware or circuit design
1742. **Homographic Transformation Matrix Operations** – Mapping projective transformations between two 2D planar projections using 3 × 3 linear transform matrices. → `e.gfx.vision.homography`
1743. **Canny Edge Detection Multi-Stage Filter** – Image processing pipeline detecting structural edges via Gaussian blurring, Sobel gradient intensity checks, non-maximum suppression, and hysteresis thresholding. → see #782 (`e.gfx.filter.canny`)
1744. **Convolutional Receptive Field Calculation** – Determining spatial input regions contributing to specific activations in deep convolutional layers. → skip: pedagogical only
1745. **Radiance Field Depth Regularization** – Constraining 3D scene reconstruction models using monocular depth priors to eliminate floating artifacts in sparse regions. → skip: a trained ML model or training recipe
1746. **GPU Early-Z Depth Testing** – Discarding occluded fragment executions before running expensive pixel shader stages by checking frag depths against existing depth buffers. → skip: hardware or circuit design
1747. **Ray Tracing Shader Execution Reordering (SER)** – Dynamically sorting divergent ray execution threads on modern GPUs to maximize execution cache coherence. → skip: hardware or circuit design
1748. **OpenCV Camera Calibration Calibration Matrices** – Extracting intrinsic parameters (focal length, principal point) and radial distortion coefficients using checkerboard target projections. → `e.gfx.vision.calibrate_camera`
1749. **Bilateral Filter Edge-Preserving Denoising** – Blending pixel values based on spatial distance and photometric intensity similarities to reduce noise without blurring structural edges. → see #788 (`e.gfx.filter.bilateral`)
1750. **Physically Based Hair & Fur Rendering (Marschner Model)** – Modeling light scattering through translucent cylindrical fibers using reflection, transmission, and internal refraction paths (R,TT,TRT). → skip: implementable, but too specialised for the standard library
## 31. Compiler Optimization & Program Analysis (1751–1800)

1751. **Constant Folding** – Evaluating expressions whose operands are all compile-time constants. → skip: belongs in the Neper compiler, not the library
1752. **Constant Propagation** – Replacing uses of a variable with its known constant value along all paths. → skip: belongs in the Neper compiler, not the library
1753. **Jump Threading** – Redirecting a branch whose outcome is known on an incoming edge straight to its target. → skip: belongs in the Neper compiler, not the library
1754. **Copy Propagation** – Replacing uses of a copied variable with the original source variable. → skip: belongs in the Neper compiler, not the library
1755. **Common Subexpression Elimination (CSE)** – Reusing a previously computed value for an identical expression. → skip: belongs in the Neper compiler, not the library
1756. **Value Range Propagation** – Tracking integer intervals per variable to fold comparisons and drop checks. → skip: belongs in the Neper compiler, not the library
1757. **Partial Redundancy Elimination (PRE)** – Hoisting expressions computed on some paths so no path computes them twice. → skip: belongs in the Neper compiler, not the library
1758. **Dead Code Elimination** – Removing computations whose results are never observed. → skip: belongs in the Neper compiler, not the library
1759. **Store-to-Load Forwarding** – Replacing a load with the value of a dominating store to the same address. → skip: belongs in the Neper compiler, not the library
1760. **Unreachable Block Elimination** – Deleting basic blocks no control-flow path can enter. → skip: belongs in the Neper compiler, not the library
1761. **Loop Rotation** – Turning a top-tested loop into a bottom-tested one behind a guarded entry. → skip: belongs in the Neper compiler, not the library
1762. **Strength Reduction** – Replacing expensive operations with cheaper equivalents, such as multiplication by induction-variable addition. → skip: belongs in the Neper compiler, not the library
1763. **Induction Variable Elimination** – Rewriting derived loop counters in terms of a single canonical counter. → skip: belongs in the Neper compiler, not the library
1764. **Loop Unrolling** – Replicating a loop body to cut branch overhead and expose instruction-level parallelism. → skip: belongs in the Neper compiler, not the library
1765. **Loop Peeling** – Splitting off the first or last iterations so the main body needs no boundary checks. → skip: belongs in the Neper compiler, not the library
1766. **Loop Fusion** – Merging adjacent loops over the same range into one to improve locality. → skip: belongs in the Neper compiler, not the library
1767. **Loop Fission (Distribution)** – Splitting a loop into several loops to enable vectorization or reduce register pressure. → skip: belongs in the Neper compiler, not the library
1768. **Loop Interchange** – Swapping nested loop order to walk memory in stride-one order. → skip: belongs in the Neper compiler, not the library
1769. **Loop Tiling (Blocking)** – Restructuring nested loops so working sets fit in cache. → skip: belongs in the Neper compiler, not the library
1770. **Loop Unswitching** – Moving a loop-invariant conditional outside the loop and duplicating the body per branch. → skip: belongs in the Neper compiler, not the library
1771. **Software Pipelining (Modulo Scheduling)** – Overlapping iterations so each cycle executes stages from different iterations. → skip: belongs in the Neper compiler, not the library
1772. **Tail Call Elimination** – Replacing a call in tail position with a jump reusing the current frame. → skip: belongs in the Neper compiler, not the library
1773. **Function Inlining Heuristics** – Deciding by call-site cost and callee size whether to substitute a body for a call. → skip: belongs in the Neper compiler, not the library
1774. **Interprocedural Constant Propagation** – Propagating constant arguments across call boundaries into callee bodies. → skip: belongs in the Neper compiler, not the library
1775. **Memory-to-Register Promotion (mem2reg)** – Lifting stack slots whose address never escapes into SSA registers. → skip: belongs in the Neper compiler, not the library
1776. **Scalar Replacement of Aggregates (SROA)** – Splitting a non-escaping struct into independent scalar variables. → skip: belongs in the Neper compiler, not the library
1777. **Alias Analysis (Andersen's)** – Inclusion-based points-to analysis solved as a constraint graph. → skip: belongs in the Neper compiler, not the library
1778. **Alias Analysis (Steensgaard's)** – Unification-based near-linear points-to analysis using union-find. → skip: belongs in the Neper compiler, not the library
1779. **Type-Based Alias Analysis (TBAA)** – Ruling out aliasing between accesses whose declared types cannot overlap. → skip: belongs in the Neper compiler, not the library
1780. **Reaching Definitions Analysis** – Computing which assignments may reach each program point. → skip: belongs in the Neper compiler, not the library
1781. **Live Variable Analysis** – Backward dataflow determining which variables hold values still needed later. → skip: belongs in the Neper compiler, not the library
1782. **Available Expressions Analysis** – Forward dataflow finding expressions already computed on every incoming path. → skip: belongs in the Neper compiler, not the library
1783. **Iterative Dataflow Fixpoint Solver** – Worklist iteration over a lattice until transfer functions stop changing. → skip: belongs in the Neper compiler, not the library
1784. **Dominance Frontier Computation** – Finding the blocks where a definition's dominance ends, used to place phi nodes. → skip: belongs in the Neper compiler, not the library
1785. **Phi Node Placement** – Inserting SSA merge nodes at iterated dominance frontiers of each definition. → skip: belongs in the Neper compiler, not the library
1786. **Out-of-SSA Translation** – Replacing phi nodes with parallel copies while resolving the lost-copy and swap problems. → skip: belongs in the Neper compiler, not the library
1787. **Instruction Selection (Tree Pattern Matching)** – Covering an expression tree with target instructions of minimum cost. → skip: belongs in the Neper compiler, not the library
1788. **Instruction Selection (BURS)** – Bottom-up rewrite system tabulating optimal tree covers with dynamic programming. → skip: belongs in the Neper compiler, not the library
1789. **List Scheduling** – Greedy ordering of instructions by priority within a basic block subject to dependences. → skip: belongs in the Neper compiler, not the library
1790. **Trace Scheduling** – Scheduling across basic blocks along the most likely execution path with compensation code. → skip: belongs in the Neper compiler, not the library
1791. **Basic Block Layout (Pettis-Hansen)** – Ordering blocks so hot edges fall through and cold code moves away. → skip: belongs in the Neper compiler, not the library
1792. **Hot-Cold Code Splitting** – Moving rarely executed blocks into a separate section to improve instruction cache use. → skip: belongs in the Neper compiler, not the library
1793. **Branch Prediction Hints Insertion** – Annotating likely branch directions from static heuristics or profiles. → skip: belongs in the Neper compiler, not the library
1794. **Bounds Check Elimination** – Proving array indices in range so runtime checks can be dropped. → skip: belongs in the Neper compiler, not the library
1795. **Null Check Elimination** – Removing dereference guards on references proven non-null by dataflow. → skip: belongs in the Neper compiler, not the library
1796. **Devirtualization** – Replacing an indirect virtual call with a direct call when the receiver class is known. → skip: belongs in the Neper compiler, not the library
1797. **Speculative Inlining with Deoptimization** – Inlining a probable target and falling back to the interpreter if the guard fails. → skip: belongs in the Neper compiler, not the library
1798. **Polyhedral Loop Optimization** – Representing loop nests as integer polyhedra and applying affine transformations. → skip: belongs in the Neper compiler, not the library
1799. **Auto-Vectorization Dependence Testing** – Using GCD and Banerjee tests to prove loop iterations independent. → skip: belongs in the Neper compiler, not the library
1800. **Identical Code Folding** – Merging functions with byte-identical bodies at link time. → skip: belongs in the Neper compiler, not the library

## 32. Robotics, Control Systems & Motion Planning (1801–1850)

1801. **PID Controller** – Correcting error with proportional, integral, and derivative terms. → `e.control.pid`
1802. **Anti-Windup PID** – Clamping or back-calculating the integral term to prevent saturation overshoot. → `e.control.pid_anti_windup`
1803. **Ziegler-Nichols Tuning** – Setting PID gains from the ultimate gain and oscillation period. → `e.control.pid_tune_ziegler_nichols`
1804. **Bang-Bang Control** – Switching the actuator fully on or off around a threshold. → `e.control.bang_bang`
1805. **Feedforward Control** – Adding a model-predicted command so feedback only corrects residual error. → `e.control.feedforward`
1806. **Linear Quadratic Regulator (LQR)** – Optimal state feedback minimizing quadratic cost via the Riccati equation. → `e.control.lqr`
1807. **Model Predictive Control (MPC)** – Solving a finite-horizon optimization each step and applying only the first action. → skip: implementable, but too specialised for the standard library
1808. **Sliding Mode Control** – Driving the state onto a switching surface and holding it there with discontinuous control. → `e.control.sliding_mode`
1809. **Pole Placement (Ackermann's Formula)** – Choosing feedback gains that set closed-loop eigenvalues. → `e.control.pole_placement`
1810. **Luenberger Observer** – Estimating unmeasured state from outputs with a model plus correction gain. → `e.control.observer`
1811. **Complementary Filter** – Fusing gyroscope and accelerometer readings with high- and low-pass blending. → `e.math.filter.complementary`
1812. **Madgwick Filter** – Gradient-descent orientation estimate from IMU and magnetometer data. → `e.math.filter.madgwick`
1813. **Mahony Filter** – Proportional-integral orientation correction using measured reference vectors. → `e.math.filter.mahony`
1814. **Dead Reckoning** – Integrating velocity and heading over time to estimate position. → `e.robot.kinematics.dead_reckon`
1815. **Odometry from Wheel Encoders** – Converting wheel tick counts into pose changes for a differential drive. → `e.robot.kinematics.odometry`
1816. **Differential Drive Kinematics** – Mapping left and right wheel speeds to linear and angular velocity. → `e.robot.kinematics.differential_drive`
1817. **Ackermann Steering Geometry** – Computing inner and outer wheel angles for a car-like vehicle. → `e.robot.kinematics.ackermann`
1818. **Denavit-Hartenberg Parameters** – Describing serial-link geometry with four parameters per joint. → `e.robot.kinematics.dh_transform`
1819. **Forward Kinematics** – Composing joint transforms to find the end-effector pose. → `e.robot.kinematics.forward`
1820. **Jacobian Inverse Kinematics** – Iterating joint updates using the pseudo-inverse of the manipulator Jacobian. → `e.robot.kinematics.ik_jacobian`
1821. **Cyclic Coordinate Descent (CCD) IK** – Rotating one joint at a time toward the target until convergence. → see #1127 (`e.game.anim.ik_ccd`)
1822. **Damped Least Squares IK** – Regularizing the Jacobian inverse to stay stable near singularities. → `e.robot.kinematics.ik_damped_least_squares`
1823. **Trapezoidal Velocity Profile** – Planning motion with constant-acceleration ramps and a cruise phase. → `e.robot.motion.trapezoid_profile`
1824. **S-Curve Motion Profile** – Limiting jerk by smoothing the acceleration transitions of a trapezoidal profile. → `e.robot.motion.s_curve_profile`
1825. **Cubic Spline Trajectory** – Joining waypoints with piecewise cubics continuous in velocity. → `e.robot.motion.spline_trajectory`
1826. **Minimum-Jerk Trajectory** – Fifth-order polynomial minimizing the integral of squared jerk. → `e.robot.motion.min_jerk`
1827. **Pure Pursuit Path Tracking** – Steering toward a lookahead point on the path with a circular arc. → `e.robot.motion.pure_pursuit`
1828. **Stanley Controller** – Combining heading error and cross-track error for front-axle path tracking. → `e.robot.motion.stanley`
1829. **Dynamic Window Approach (DWA)** – Sampling admissible velocities and scoring short forward simulations. → `e.robot.motion.dynamic_window`
1830. **Velocity Obstacles** – Choosing velocities outside the cones that lead to collision with moving agents. → `e.robot.motion.velocity_obstacles`
1831. **Reciprocal Velocity Obstacles (RVO / ORCA)** – Sharing avoidance responsibility between agents so they do not oscillate. → `e.robot.motion.orca`
1832. **Artificial Potential Fields** – Attracting toward the goal and repelling from obstacles with summed gradients. → `e.robot.motion.potential_field`
1833. **Probabilistic Roadmap (PRM)** – Sampling free configurations and connecting neighbors into a query graph. → `e.robot.plan.prm`
1834. **Kinodynamic RRT** – Extending the random tree with dynamically feasible controls integrated forward in time. → `e.robot.plan.rrt_kinodynamic`
1835. **RRT-Connect** – Growing two trees from start and goal and joining them greedily. → `e.robot.plan.rrt_connect`
1836. **Informed RRT*** – Restricting samples to the ellipsoid that can still improve the current solution. → `e.robot.plan.rrt_informed`
1837. **Hybrid A*** – Searching over continuous headings with kinematically feasible motion primitives. → `e.robot.plan.hybrid_astar`
1838. **State Lattice Planning** – Searching precomputed feasible motion primitives on a discretized state grid. → `e.robot.plan.state_lattice`
1839. **Theta* Any-Angle Pathfinding** – Grid search with line-of-sight parent shortcuts for straighter paths. → `e.game.grid.path_theta_star`
1840. **D* Lite** – Incremental replanning from the goal as edge costs change during execution. → see #92 (`e.robot.plan.dstar_lite`)
1841. **Elastic Band Path Smoothing** – Deforming a path with internal contraction and external repulsion forces. → `e.robot.motion.elastic_band`
1842. **Timed Elastic Band (TEB)** – Optimizing waypoints and time intervals jointly under kinodynamic constraints. → skip: implementable, but too specialised for the standard library
1843. **Occupancy Grid Mapping** – Updating cell occupancy log-odds from range sensor inverse models. → `e.robot.map.occupancy_update`
1844. **Bresenham Ray Casting on Grids** – Marking free cells along a sensor ray up to the hit cell. → `e.game.grid.ray_cells`
1845. **Scan Matching (Point-to-Line ICP)** – Aligning consecutive laser scans by minimizing point-to-line distances. → `e.robot.map.scan_match`
1846. **Adaptive Monte Carlo Localization (AMCL)** – Particle-filter localization with KLD-sampling to resize the particle set. → `e.robot.map.localize_amcl`
1847. **Graph SLAM Pose Graph Optimization** – Minimizing relative-pose constraint residuals with sparse least squares. → `e.robot.map.pose_graph_optimize`
1848. **Loop Closure Detection (Bag of Words)** – Recognizing revisited places by matching visual word histograms. → skip: a trained ML model or training recipe
1849. **Grasp Planning (Force Closure)** – Selecting contact points whose wrenches span the full wrench space. → skip: implementable, but too specialised for the standard library
1850. **Zero Moment Point (ZMP) Walking** – Keeping the ground reaction point inside the support polygon for biped balance. → skip: implementable, but too specialised for the standard library

## 33. Audio, Music & Digital Signal Processing (1851–1900)

1851. **Comb Filter** – Adding a delayed copy of the signal to itself, producing evenly spaced spectral notches or peaks. → `e.dsp.comb`
1852. **One-Pole Low-Pass Filter** – First-order recursive smoothing with a single coefficient. → `e.dsp.one_pole`
1853. **Biquad Filter (Direct Form II Transposed)** – Second-order IIR section with numerically stable state variables. → `e.dsp.biquad`
1854. **Elliptic (Cauer) Filter Design** – Allowing ripple in both bands for the steepest possible transition. → `e.dsp.design_elliptic`
1855. **Bessel Filter Design** – Maximally flat group delay preserving waveform shape. → `e.dsp.design_bessel`
1856. **Windowed-Sinc Filter Design** – Truncating the ideal low-pass impulse response with a window function. → `e.dsp.design_windowed_sinc`
1857. **Parks-McClellan Algorithm** – Equiripple FIR design via the Remez exchange algorithm. → `e.dsp.design_parks_mcclellan`
1858. **Bilinear Transform** – Mapping an analog filter prototype to a digital one while warping frequency. → `e.dsp.bilinear_transform`
1859. **Hann / Hamming / Blackman Windows** – Tapering a frame to reduce spectral leakage before an FFT. → `e.dsp.window`
1860. **Gabor Transform** – STFT with a Gaussian window meeting the time-frequency uncertainty bound. → see #802 (`e.dsp.stft`)
1861. **Inverse STFT with Overlap-Add** – Reconstructing a signal from modified frames with window compensation. → `e.dsp.istft`
1862. **Discrete Wavelet Transform (Mallat)** – Cascaded filter banks with downsampling for multi-resolution analysis. → see #636 (`e.math.fft.dwt`)
1863. **Discrete Cosine Transform (DCT-II)** – Real-valued energy-compacting transform used in audio and image coding. → see #635 (`e.math.fft.dct`)
1864. **Modified Discrete Cosine Transform (MDCT)** – Lapped transform with perfect reconstruction used in AAC and Opus. → `e.math.fft.mdct`
1865. **Cepstrum Computation** – Inverse FFT of the log spectrum separating source from filter. → `e.dsp.cepstrum`
1866. **Linear Predictive Coding (LPC)** – Modeling each sample as a linear combination of previous samples. → `e.dsp.lpc`
1867. **Levinson-Durbin Recursion** – Solving the Toeplitz normal equations of LPC in O(p²). → `e.dsp.levinson_durbin`
1868. **Autocorrelation Pitch Detection** – Finding the lag of the first strong autocorrelation peak. → `e.audio.analysis.pitch_autocorrelation`
1869. **Harmonic Product Spectrum** – Multiplying downsampled spectra so the fundamental reinforces itself. → `e.audio.analysis.pitch_hps`
1870. **pYIN Probabilistic Pitch Tracking** – Combining YIN candidates with an HMM for smooth pitch contours. → `e.audio.analysis.pitch_pyin`
1871. **Phase Vocoder Time Stretching** – Changing duration without pitch by rescaling phase advances between frames. → `e.audio.fx.time_stretch`
1872. **Pitch Shifting by Resampling** – Combining time stretch with playback-rate change to alter pitch. → `e.audio.fx.pitch_shift`
1873. **PSOLA (Pitch-Synchronous Overlap-Add)** – Shifting pitch by repositioning pitch-period grains. → `e.audio.fx.psola`
1874. **Onset Detection (Spectral Flux)** – Flagging beats where positive spectral change exceeds a threshold. → `e.audio.analysis.onsets`
1875. **Beat Tracking (Dynamic Programming)** – Choosing beat times that maximize onset strength and tempo regularity. → `e.audio.analysis.beats`
1876. **Tempo Estimation (Autocorrelation of Onset Envelope)** – Finding the dominant periodicity of onset strength. → `e.audio.analysis.tempo`
1877. **Chroma Feature Extraction** – Folding spectral energy into twelve pitch classes. → `e.audio.analysis.chroma`
1878. **Dynamic Time Warping for Audio Alignment** – Aligning two feature sequences with a monotone warping path. → see #805 (`e.dsp.dtw`)
1879. **Spectral Subtraction Noise Reduction** – Removing an estimated noise spectrum from each frame's magnitude. → `e.dsp.spectral_subtract`
1880. **Wiener Filter Denoising** – Scaling each frequency bin by its estimated signal-to-noise ratio. → `e.dsp.wiener`
1881. **Adaptive LMS Filter** – Updating filter taps by stochastic gradient to track a reference signal. → `e.dsp.lms`
1882. **Normalized LMS (NLMS)** – Step size scaled by input power for stable convergence. → `e.dsp.nlms`
1883. **Recursive Least Squares (RLS) Filter** – Exponentially weighted least-squares tap updates with fast convergence. → `e.dsp.rls`
1884. **Acoustic Echo Cancellation** – Subtracting an adaptively filtered far-end signal from the microphone input. → `e.audio.fx.echo_cancel`
1885. **Voice Activity Detection (Energy + Zero-Crossing)** – Classifying frames as speech or silence from simple features. → `e.audio.analysis.voice_activity`
1886. **Dynamic Range Compressor** – Reducing gain above a threshold with attack and release smoothing. → `e.audio.fx.compressor`
1887. **Lookahead Limiter** – Delaying the signal so gain can drop before a peak arrives. → `e.audio.fx.limiter`
1888. **Noise Gate** – Muting the signal while its level stays below a threshold. → `e.audio.fx.gate`
1889. **Parametric Equalizer** – Cascading peaking and shelving biquads with adjustable center, gain, and Q. → `e.audio.fx.equalizer`
1890. **Schroeder Reverberator** – Combining parallel comb filters with series all-pass filters. → `e.audio.fx.reverb_schroeder`
1891. **Feedback Delay Network Reverb** – Mixing several delay lines through an orthogonal feedback matrix. → `e.audio.fx.reverb_fdn`
1892. **Convolution Reverb (Partitioned FFT)** – Applying a long impulse response in uniform frequency-domain blocks. → `e.audio.fx.reverb_convolution`
1893. **Karplus-Strong String Synthesis** – Feeding a short noise burst through a delay line with a low-pass loop. → `e.audio.synth.karplus_strong`
1894. **Wavetable Synthesis** – Reading a stored single-cycle waveform at a rate set by the desired pitch. → `e.audio.synth.wavetable`
1895. **Band-Limited Oscillator (PolyBLEP)** – Correcting discontinuities in saw and square waves to suppress aliasing. → `e.audio.synth.oscillator_polyblep`
1896. **ADSR Envelope Generator** – Shaping amplitude through attack, decay, sustain, and release stages. → `e.audio.synth.adsr`
1897. **Sample Rate Conversion (Polyphase)** – Interpolating and decimating with a filter split into subfilters. → `e.dsp.resample_polyphase`
1898. **Sinc Interpolation Resampling** – Reconstructing the band-limited signal between samples. → `e.dsp.resample_sinc`
1899. **Dither with Noise Shaping** – Adding shaped noise before quantization to push error out of audible bands. → `e.audio.dither`
1900. **Loudness Measurement (ITU-R BS.1770)** – K-weighted gated mean-square loudness in LUFS. → `e.audio.analysis.loudness_lufs`

## 34. Probability, Statistics & Sampling (1901–1950)

1901. **Welford's Online Variance** – Numerically stable running mean and variance in one pass. → `e.algo.stat.moments_add`
1902. **Parallel Variance Merge (Chan's Algorithm)** – Combining mean and M2 from disjoint partitions. → `e.algo.stat.moments_merge`
1903. **Exponentially Weighted Moving Average** – Smoothing a series with geometrically decaying weights. → see #795 (`e.dsp.ema`)
1904. **Kahan-Compensated Mean** – Summing with error compensation before dividing. → `e.algo.stat.mean_compensated`
1905. **Sample Skewness and Kurtosis** – Third and fourth standardized central moments. → `e.algo.stat.skewness`
1906. **Pearson Correlation Coefficient** – Normalized covariance measuring linear association. → `e.algo.stat.correlation_pearson`
1907. **Spearman Rank Correlation** – Pearson correlation applied to ranks. → `e.algo.stat.correlation_spearman`
1908. **Kendall's Tau** – Concordant minus discordant pair fraction, computed in O(n log n) with a Fenwick tree. → `e.algo.stat.correlation_kendall`
1909. **Covariance Matrix Estimation** – Averaging outer products of centered observations. → `e.algo.stat.covariance_matrix`
1910. **Ledoit-Wolf Shrinkage** – Shrinking a sample covariance toward a structured target with an optimal weight. → `e.algo.stat.covariance_shrink`
1911. **Student's t-Test** – Comparing means under unknown variance using the t distribution. → `e.algo.stat.test.t_test`
1912. **Welch's t-Test** – Two-sample t-test without assuming equal variances. → `e.algo.stat.test.welch`
1913. **Mann-Whitney U Test** – Rank-sum test for a difference between two distributions. → `e.algo.stat.test.mann_whitney`
1914. **Wilcoxon Signed-Rank Test** – Paired nonparametric test on signed rank sums. → `e.algo.stat.test.wilcoxon`
1915. **Chi-Squared Goodness-of-Fit Test** – Comparing observed and expected category counts. → `e.algo.stat.test.chi_squared`
1916. **Fisher's Exact Test** – Hypergeometric p-value for 2×2 contingency tables. → `e.algo.stat.test.fisher_exact`
1917. **Kolmogorov-Smirnov Test** – Maximum distance between empirical and reference CDFs. → `e.algo.stat.test.ks`
1918. **Anderson-Darling Test** – CDF distance test weighting the tails more heavily. → `e.algo.stat.test.anderson_darling`
1919. **Shapiro-Wilk Normality Test** – Correlating ordered sample values with normal order statistics. → `e.algo.stat.test.shapiro_wilk`
1920. **One-Way ANOVA** – Comparing group means by partitioning variance between and within groups. → `e.algo.stat.test.anova`
1921. **Kruskal-Wallis Test** – Rank-based ANOVA across three or more groups. → `e.algo.stat.test.kruskal_wallis`
1922. **Benjamini-Hochberg Procedure** – Controlling the false discovery rate over many p-values. → `e.algo.stat.test.benjamini_hochberg`
1923. **Bonferroni Correction** – Dividing the significance level by the number of tests. → `e.algo.stat.test.bonferroni`
1924. **Bootstrap Confidence Interval** – Resampling with replacement to estimate an estimator's distribution. → `e.algo.stat.bootstrap`
1925. **Jackknife Estimator** – Leave-one-out resampling for bias and variance estimates. → `e.algo.stat.jackknife`
1926. **Permutation Test** – Building the null distribution by shuffling labels. → `e.algo.stat.test.permutation`
1927. **Wilson Score Interval** – Binomial proportion confidence interval well-behaved at small counts. → `e.algo.stat.interval_wilson`
1928. **Clopper-Pearson Interval** – Exact binomial interval from beta quantiles. → `e.algo.stat.interval_clopper_pearson`
1929. **Kernel Density Estimation** – Smoothing sample points with a bandwidth-scaled kernel. → `e.algo.stat.kde`
1930. **Silverman's Bandwidth Rule** – Rule-of-thumb kernel bandwidth from sample standard deviation and size. → `e.algo.stat.kde_bandwidth`
1931. **Maximum Likelihood Estimation (Newton)** – Maximizing log-likelihood with gradient and Hessian steps. → `e.algo.stat.fit_mle`
1932. **Method of Moments Estimation** – Matching sample moments to distribution moments. → `e.algo.stat.fit_moments`
1933. **Expectation-Maximization for Mixtures** – Alternating responsibility and parameter updates for a mixture model. → see #731 (`e.ml.cluster.gmm_em`)
1934. **Box-Muller Transform** – Generating standard normals from two uniforms. → `e.algo.rand.dist.normal_box_muller`
1935. **Marsaglia Polar Method** – Rejection-based normal generation without trigonometric functions. → `e.algo.rand.dist.normal_polar`
1936. **Ziggurat Algorithm** – Fast normal or exponential sampling from stacked rectangular layers. → `e.algo.rand.dist.normal`
1937. **Inverse Transform Sampling** – Mapping a uniform through the quantile function. → `e.algo.rand.dist.inverse_transform`
1938. **Rejection Sampling** – Accepting proposals with probability proportional to the target-to-envelope ratio. → `e.algo.rand.dist.rejection`
1939. **Importance Sampling** – Weighting samples from a proposal by target-to-proposal density ratio. → `e.algo.rand.dist.importance_weights`
1940. **Poisson Sampling (Knuth)** – Multiplying uniforms until the product drops below e^(−λ). → `e.algo.rand.dist.poisson`
1941. **Binomial Sampling (BTPE)** – Efficient generation for large n via a triangle-parallelogram-exponential envelope. → `e.algo.rand.dist.binomial`
1942. **Gamma Sampling (Marsaglia-Tsang)** – Squeeze-based rejection for shape parameter ≥ 1. → `e.algo.rand.dist.gamma`
1943. **Beta Sampling via Gammas** – Normalizing two gamma variates. → `e.algo.rand.dist.beta`
1944. **Dirichlet Sampling** – Normalizing a vector of gamma variates by their sum. → `e.algo.rand.dist.dirichlet`
1945. **Multivariate Normal Sampling (Cholesky)** – Transforming standard normals by the covariance's Cholesky factor. → `e.algo.rand.dist.multivariate_normal`
1946. **Stratified Sampling** – Drawing from each stratum in proportion to its size to reduce variance. → `e.algo.rand.stratified`
1947. **Latin Hypercube Sampling** – Placing one sample per row and column of a stratified grid. → `e.algo.rand.latin_hypercube`
1948. **Sobol Sequence Generation** – Low-discrepancy quasi-random points from direction numbers. → `e.algo.rand.quasi.sobol`
1949. **Halton Sequence Generation** – Radical-inverse quasi-random sequences in coprime bases. → `e.algo.rand.quasi.halton`
1950. **Weighted Reservoir Sampling (Efraimidis-Spirakis)** – Keeping the k items with the largest u^(1/w) keys. → see #982 (`e.algo.rand.reservoir_weighted`)

## 35. Constraint Solving, SAT/SMT & Combinatorial Search (1951–2000)

1951. **DPLL Algorithm** – Backtracking SAT search with unit propagation and pure-literal elimination. → skip: an implementation detail of an existing module, not an API
1952. **Conflict-Driven Clause Learning (CDCL)** – Learning clauses from conflicts and backjumping non-chronologically. → `e.algo.sat.solve`
1953. **Two-Watched-Literal Scheme** – Tracking two literals per clause to make unit propagation cheap. → skip: an implementation detail of an existing module, not an API
1954. **First-UIP Conflict Analysis** – Cutting the implication graph at the first unique implication point. → skip: an implementation detail of an existing module, not an API
1955. **VSIDS Variable Ordering** – Bumping and decaying activity scores to pick decision variables. → skip: an implementation detail of an existing module, not an API
1956. **Phase Saving** – Reusing the last assigned polarity when re-deciding a variable. → skip: an implementation detail of an existing module, not an API
1957. **Luby Restart Schedule** – Restarting search at intervals following the Luby sequence. → skip: an implementation detail of an existing module, not an API
1958. **Clause Database Reduction (LBD)** – Deleting learned clauses with high literal block distance. → skip: an implementation detail of an existing module, not an API
1959. **Bounded Variable Elimination** – Preprocessing by resolving out variables that shrink the formula. → `e.algo.sat.preprocess`
1960. **WalkSAT Local Search** – Flipping variables in unsatisfied clauses with noise-guided choice. → `e.algo.sat.walksat`
1961. **Tseitin Transformation** – Converting an arbitrary circuit to equisatisfiable CNF in linear size. → `e.algo.sat.tseitin`
1962. **Cardinality Constraint Encoding (Sequential Counter)** – Encoding at-most-k with auxiliary variables. → `e.algo.sat.encode_at_most`
1963. **Pseudo-Boolean to CNF (BDD Encoding)** – Compiling linear constraints through a binary decision diagram. → `e.algo.sat.encode_pseudo_boolean`
1964. **DPLL(T)** – Integrating theory solvers with SAT search for satisfiability modulo theories. → skip: research-grade, no settled practical implementation
1965. **Nelson-Oppen Theory Combination** – Sharing equalities between disjoint theory solvers. → skip: research-grade, no settled practical implementation
1966. **Congruence Closure** – Deciding equality with uninterpreted functions via union-find on terms. → `e.algo.smt.congruence_closure`
1967. **Simplex for Linear Real Arithmetic (Dutertre-de Moura)** – Bounds-based simplex tailored to SMT backtracking. → skip: research-grade, no settled practical implementation
1968. **Bit-Blasting** – Reducing bit-vector formulas to propositional circuits. → `e.algo.smt.bit_blast`
1969. **Model-Based Quantifier Instantiation** – Instantiating quantifiers with terms drawn from candidate models. → skip: research-grade, no settled practical implementation
1970. **E-Graph Equality Saturation** – Applying rewrite rules to all equivalent terms without losing any. → `e.algo.egraph.saturate`
1971. **AC-3 Arc Consistency** – Pruning domain values lacking support in binary constraints. → `e.algo.csp.ac3`
1972. **AC-4 Arc Consistency** – Support counting for arc consistency in optimal worst-case time. → skip: implementable, but too specialised for the standard library
1973. **Maintaining Arc Consistency (MAC)** – Re-establishing arc consistency after each search assignment. → `e.algo.csp.solve`
1974. **Forward Checking** – Removing conflicting values from future variables after each assignment. → skip: an implementation detail of an existing module, not an API
1975. **Minimum Remaining Values Heuristic** – Choosing the variable with the fewest legal values. → skip: an implementation detail of an existing module, not an API
1976. **Least Constraining Value Heuristic** – Trying the value that rules out the fewest options for neighbors. → skip: an implementation detail of an existing module, not an API
1977. **Conflict-Directed Backjumping** – Returning to the most recent variable involved in the conflict. → skip: an implementation detail of an existing module, not an API
1978. **Nogood Recording** – Storing partial assignments proven inconsistent to prune later search. → skip: an implementation detail of an existing module, not an API
1979. **Global Constraint AllDifferent (Régin)** – Bipartite matching based filtering for all-different constraints. → `e.algo.csp.all_different`
1980. **Global Cardinality Constraint Filtering** – Flow-based pruning of value occurrence bounds. → `e.algo.csp.global_cardinality`
1981. **Cumulative Constraint (Time-Table)** – Enforcing resource capacity over scheduled task intervals. → `e.algo.csp.cumulative`
1982. **Element Constraint Propagation** – Linking an index variable to an array lookup result. → `e.algo.csp.element`
1983. **Table Constraint (Compact-Table)** – Bitset-based filtering over explicit tuple lists. → `e.algo.csp.table`
1984. **Large Neighborhood Search** – Repeatedly freeing part of a solution and re-solving it. → `e.algo.combopt.large_neighborhood_search`
1985. **Limited Discrepancy Search** – Exploring paths in order of how often they disobey the heuristic. → `e.algo.csp.limited_discrepancy`
1986. **Branch and Bound** – Pruning subtrees whose bound cannot beat the incumbent. → `e.algo.combopt.branch_and_bound`
1987. **Branch and Cut** – Adding violated cutting planes to LP relaxations within branch and bound. → skip: implementable, but too specialised for the standard library
1988. **Gomory Cut Generation** – Deriving integer cuts from fractional simplex rows. → skip: implementable, but too specialised for the standard library
1989. **Lagrangian Relaxation** – Moving hard constraints into the objective with multipliers and solving the dual. → skip: implementable, but too specialised for the standard library
1990. **Column Generation** – Pricing new variables into a restricted master problem. → skip: implementable, but too specialised for the standard library
1991. **Dantzig-Wolfe Decomposition** – Reformulating block-structured programs with convex combinations of extreme points. → skip: implementable, but too specialised for the standard library
1992. **Benders Decomposition** – Splitting a problem into a master and subproblem linked by optimality cuts. → skip: implementable, but too specialised for the standard library
1993. **Hungarian Method on Rectangular Costs** – Padding to square and solving assignment with dummy rows. → see #79 (`e.algo.graph.match.hungarian`)
1994. **Held-Karp TSP Dynamic Programming** – Exact traveling salesman over subsets in O(n² 2ⁿ). → see #115 (`e.algo.combopt.tsp_held_karp`)
1995. **Nearest Neighbor Tour Construction** – Building a TSP tour by always visiting the closest unvisited city. → `e.algo.combopt.tsp_nearest_neighbor`
1996. **2-opt / Or-opt Local Search** – Reversing or relocating tour segments to shorten a route. → see #116 (`e.algo.combopt.tsp_two_opt`)
1997. **Vehicle Routing (Clarke-Wright Savings)** – Merging routes in order of the largest distance saving. → `e.algo.combopt.vrp_savings`
1998. **Knapsack Branch and Bound** – Fractional-knapsack bounds pruning the 0/1 search. → `e.algo.combopt.knapsack_branch_and_bound`
1999. **Bin Packing First Fit Decreasing** – Placing items largest-first into the first bin with room. → `e.algo.combopt.bin_pack_ffd`
2000. **Job Shop Scheduling (Shifting Bottleneck)** – Sequencing one machine at a time using one-machine subproblems. → skip: implementable, but too specialised for the standard library

## 36. Computational Geometry, Meshes & CAD (2001–2050)

2001. **Orientation Predicate (Exact)** – Sign of a 2×2 determinant with adaptive precision arithmetic. → `e.algo.geom.orient`
2002. **In-Circle Predicate** – Testing whether a point lies inside the circumcircle of a triangle. → `e.algo.geom.in_circle`
2003. **Segment Intersection Test** – Combining orientation tests to decide if two segments cross. → see #538 (`e.algo.geom.segments_intersect`)
2004. **Bentley-Ottmann Sweep** – Reporting all segment intersections in O((n+k) log n). → see #528 (`e.algo.geom.segment_intersections`)
2005. **Point in Polygon (Ray Casting)** – Counting edge crossings of a ray from the point. → see #521 (`e.algo.geom.point_in_polygon`)
2006. **Point in Polygon (Winding Number)** – Summing signed angle contributions of edges. → see #532 (`e.algo.geom.winding_number`)
2007. **Polygon Triangulation (Ear Clipping)** – Removing convex ears until three vertices remain. → see #533 (`e.algo.geom.triangulate_ear_clip`)
2008. **Polygon Triangulation (Monotone Decomposition)** – Splitting into y-monotone pieces and triangulating each in linear time. → `e.algo.geom.triangulate_monotone`
2009. **Delaunay Triangulation (Bowyer-Watson)** – Inserting points and re-triangulating the cavity of violated triangles. → see #530 (`e.algo.geom.delaunay`)
2010. **Delaunay Triangulation (Divide and Conquer)** – Merging half triangulations with a rising bubble. → skip: implementable, but too specialised for the standard library
2011. **Constrained Delaunay Triangulation** – Forcing required edges while keeping the Delaunay property elsewhere. → `e.algo.geom.delaunay_constrained`
2012. **Voronoi Diagram (Fortune's Sweep)** – Beach-line sweep producing Voronoi cells in O(n log n). → see #529 (`e.algo.geom.voronoi`)
2013. **Voronoi from Delaunay Dual** – Connecting circumcenters of adjacent Delaunay triangles. → `e.algo.geom.voronoi_from_delaunay`
2014. **Lloyd's Relaxation** – Moving sites to Voronoi cell centroids to even out a distribution. → `e.algo.geom.lloyd_relax`
2015. **Convex Hull 3D (Quickhull)** – Recursively adding the farthest point outside each face. → `e.algo.geom3.hull`
2016. **Convex Hull 3D (Incremental)** – Adding points one at a time and re-stitching the horizon. → skip: implementable, but too specialised for the standard library
2017. **Minkowski Sum of Convex Polygons** – Merging edge sequences by angle. → `e.algo.geom.minkowski_sum`
2018. **Polygon Clipping (Sutherland-Hodgman)** – Clipping a polygon against each edge of a convex window. → see #534 (`e.algo.geom.clip_convex`)
2019. **Polygon Clipping (Weiler-Atherton)** – Clipping arbitrary polygons by walking intersection points. → see #535 (`e.algo.geom.clip_polygon`)
2020. **Polygon Boolean Operations (Greiner-Hormann)** – Union, intersection, and difference via intersection-marked vertex lists. → `e.algo.geom.polygon_boolean`
2021. **Polygon Offsetting (Vatti / Clipper)** – Insetting or outsetting a polygon by a fixed distance. → `e.algo.geom.polygon_offset`
2022. **Line Simplification (Douglas-Peucker)** – Dropping points closer than a tolerance to the chord. → see #557 (`e.algo.geom.simplify_douglas_peucker`)
2023. **Line Simplification (Visvalingam-Whyatt)** – Removing points of least effective area. → see #558 (`e.algo.geom.simplify_visvalingam`)
2024. **Farthest Pair (Diameter via Calipers)** – Antipodal-pair scan of a convex hull for the maximum distance. → see #542 (`e.algo.geom.farthest_pair`)
2025. **Smallest Enclosing Circle (Welzl)** – Randomized incremental minimum enclosing disk. → see #539 (`e.algo.geom.enclosing_circle`)
2026. **Minimum Bounding Rectangle (Rotating Calipers)** – Smallest-area oriented box around a convex hull. → `e.algo.geom.min_bounding_rect`
2027. **Largest Empty Circle** – Finding the Voronoi vertex farthest from all sites. → `e.algo.geom.largest_empty_circle`
2028. **k-d Tree Nearest Neighbor** – Branch-and-bound descent with sibling pruning by split distance. → see #222 (`e.data.spatial.kd_nearest`)
2029. **Ball Tree Nearest Neighbor** – Hierarchical enclosing spheres pruning by triangle inequality. → `e.data.spatial.ball_tree_nearest`
2030. **Half-Edge Mesh Data Structure** – Storing each edge twice with next, twin, and face pointers. → `e.gfx.mesh.half_edge`
2031. **Edge Collapse Decimation (Garland-Heckbert)** – Contracting edges by minimum quadric error. → see #1148 (`e.gfx.mesh.decimate`)
2032. **Loop Subdivision** – Refining triangle meshes with weighted vertex and edge rules. → `e.gfx.mesh.subdivide_loop`
2033. **Catmull-Clark Subdivision** – Refining quad meshes toward a bicubic B-spline limit surface. → `e.gfx.mesh.subdivide_catmull_clark`
2034. **Laplacian Mesh Smoothing** – Moving each vertex toward the average of its neighbors. → `e.gfx.mesh.smooth_laplacian`
2035. **Taubin Smoothing** – Alternating positive and negative Laplacian steps to avoid shrinkage. → `e.gfx.mesh.smooth_taubin`
2036. **Mesh Parameterization (Least Squares Conformal Maps)** – Flattening a mesh to 2D minimizing angle distortion. → `e.gfx.mesh.parameterize_lscm`
2037. **Geodesic Distance (Fast Marching on Meshes)** – Propagating distances across triangles with an update rule. → `e.gfx.mesh.geodesic_fast_marching`
2038. **Heat Method for Geodesics** – Diffusing heat then solving a Poisson equation for distance. → `e.gfx.mesh.geodesic_heat`
2039. **Mesh Boolean via BSP Trees** – Classifying polygons against a binary space partition of the other solid. → `e.gfx.mesh.boolean_bsp`
2040. **Point Cloud Normal Estimation (PCA)** – Fitting a plane to each point's neighborhood. → `e.gfx.mesh.estimate_normals`
2041. **Poisson Surface Reconstruction** – Solving for an indicator function whose gradient matches oriented normals. → `e.gfx.mesh.reconstruct_poisson`
2042. **Ball-Pivoting Surface Reconstruction** – Rolling a ball over points to grow triangles. → `e.gfx.mesh.reconstruct_ball_pivot`
2043. **Dual Contouring** – Placing one vertex per cell from Hermite data to preserve sharp features. → `e.gfx.mesh.dual_contouring`
2044. **Signed Distance Field from Mesh** – Computing distance to the closest triangle with a sign from pseudonormals. → `e.gfx.mesh.signed_distance`
2045. **Ray-Sphere Intersection** – Solving the quadratic from substituting the ray into the sphere equation. → `e.algo.geom3.ray_sphere`
2046. **Ray-Plane and Ray-Disk Intersection** – Solving for the parameter where the ray meets a plane, then bounding by radius. → `e.algo.geom3.ray_plane`
2047. **Bezier Curve Evaluation (De Casteljau)** – Repeated linear interpolation of control points. → see #555 (`e.gfx.curve.bezier`)
2048. **B-Spline Evaluation (De Boor)** – Local recursive evaluation using the knot vector. → see #554 (`e.gfx.curve.bspline`)
2049. **Surface of Revolution Generation** – Sweeping a profile curve around an axis into a mesh. → `e.gfx.mesh.revolve`
2050. **Constructive Solid Geometry Ray Evaluation** – Combining interval hits along a ray with set operations. → `e.gfx.trace.csg`

## 37. Text Encoding, Serialization & Data Formats (2051–2100)

2051. **Base32 Encoding** – Mapping five-bit groups to a 32-character alphabet. → `e.bytes.base32_encode`
2052. **Base58 Encoding** – Big-number base conversion excluding ambiguous characters. → `e.bytes.base58_encode`
2053. **Base85 (Ascii85) Encoding** – Encoding four bytes as five printable characters. → see #321 (`e.bytes.base85_encode`)
2054. **Quoted-Printable Encoding** – Escaping non-ASCII bytes as =XX for 7-bit transports. → `e.fmt.quoted_printable.encode`
2055. **Punycode Encoding** – Representing Unicode domain labels in ASCII with a generalized variable-length integer scheme. → `e.net.idna.punycode_encode`
2056. **Percent-Encoding** – Escaping reserved URL bytes as %XX. → see #322 (`e.fmt.uri.percent_encode`)
2057. **UTF-8 Validation (DFA)** – Checking well-formedness with a table-driven state machine. → `e.text.utf8.validate`
2058. **UTF-8 Validation (SIMD)** – Vectorized lookup-based checking of continuation patterns. → `e.text.utf8.validate`
2059. **UTF-16 to UTF-8 Transcoding** – Decoding surrogate pairs and re-encoding as 1–4 bytes. → `e.text.encoding.to_utf8`
2060. **Unicode Normalization (NFC / NFD)** – Composing or decomposing characters with canonical ordering. → see #325 (`e.text.normalize.normalize`)
2061. **Unicode Case Folding** – Mapping characters to a case-insensitive comparison form. → `e.text.unicode.casefold`
2062. **Unicode Grapheme Cluster Segmentation** – Splitting text at user-perceived character boundaries. → `e.text.unicode.graphemes`
2063. **Unicode Word Segmentation (UAX #29)** – Finding word boundaries from character properties. → `e.text.segment.words`
2064. **Unicode Line Breaking (UAX #14)** – Finding permitted line-break opportunities. → `e.text.segment.line_breaks`
2065. **Bidirectional Text Algorithm (UAX #9)** – Resolving embedding levels and reordering mixed-direction runs. → `e.text.bidi.reorder`
2066. **Unicode Collation Algorithm** – Comparing strings by multi-level collation element weights. → `e.text.collate.compare`
2067. **Byte Order Mark Detection** – Sniffing UTF-8, UTF-16, and UTF-32 from leading bytes. → see #327 (`e.text.encoding.detect_bom`)
2068. **Charset Detection (n-gram statistics)** – Guessing a legacy encoding from byte frequency profiles. → `e.text.encoding.detect`
2069. **Code Page Transcoding (Table Lookup)** – Mapping single-byte encodings to and from Unicode. → `e.text.encoding.to_utf8`
2070. **CSV Parsing (RFC 4180)** – Handling quoted fields, escaped quotes, and embedded newlines. → see #966 (`e.fmt.csv.reader`)
2071. **TSV / Delimited Writer with Quoting** – Emitting fields with minimal quoting rules. → `e.fmt.csv.writer`
2072. **JSON Serializer with Escaping** – Emitting strings with control-character and Unicode escapes. → `e.fmt.json.write`
2073. **JSON Pointer Resolution** – Walking a document by a /a/0/b path with ~0 and ~1 unescaping. → `e.fmt.json.pointer`
2074. **JSON Patch Application** – Applying add, remove, replace, move, copy, and test operations. → `e.fmt.json.patch`
2075. **JSON Merge Patch** – Recursively merging objects with null meaning delete. → `e.fmt.json.merge_patch`
2076. **JSON Schema Validation** – Checking a document against type, property, and constraint keywords. → `e.fmt.json.schema.validate`
2077. **JSON Canonicalization (RFC 8785)** – Producing a deterministic byte form for hashing and signing. → `e.fmt.json.canonicalize`
2078. **Streaming JSON Tokenizer (SAX-style)** – Emitting events without building the full tree. → `e.fmt.json.tokenizer`
2079. **XML Tokenizer** – Lexing tags, attributes, entities, and CDATA sections. → see #344 (`e.fmt.xml.stream`)
2080. **XML Namespace Resolution** – Mapping prefixes to URIs through scoped declarations. → `e.fmt.xml.namespaces`
2081. **XPath Evaluation** – Walking axes and predicates over a document tree. → `e.fmt.xml.xpath`
2082. **XSLT Template Matching** – Applying the highest-priority matching template to each node. → skip: implementable, but too specialised for the standard library
2083. **YAML Block Scalar Parsing** – Handling literal and folded multi-line strings with indentation rules. → `e.fmt.yaml.parse`
2084. **TOML Parser** – Parsing tables, arrays of tables, and dotted keys. → `e.fmt.toml.parse`
2085. **INI Parser with Sections** – Reading key-value pairs grouped by [section] headers. → `e.fmt.ini.parse`
2086. **Protocol Buffers Wire Decoding** – Reading tag-length-value fields keyed by field number and wire type. → `e.fmt.protobuf.decode`
2087. **FlatBuffers Zero-Copy Access** – Reading fields through vtable offsets without deserialization. → `e.fmt.flatbuffers.get`
2088. **Cap'n Proto Pointer Encoding** – Locating structs and lists through segment-relative pointers. → skip: implementable, but too specialised for the standard library
2089. **MessagePack Encoding** – Compact binary tagging of maps, arrays, strings, and integers. → `e.fmt.msgpack.encode`
2090. **CBOR Encoding** – Concise binary object representation with major types and tags. → `e.fmt.cbor.encode`
2091. **ASN.1 DER Encoding** – Distinguished tag-length-value encoding used by X.509. → `e.fmt.asn1.der_encode`
2092. **ASN.1 BER Decoding** – Handling indefinite-length and constructed encodings. → `e.fmt.asn1.ber_decode`
2093. **BSON Encoding** – Binary JSON with typed fields and length prefixes. → `e.fmt.bson.encode`
2094. **Avro Schema Resolution** – Reconciling writer and reader schemas during decoding. → `e.fmt.avro.resolve`
2095. **Apache Arrow Columnar Layout** – Validity bitmaps plus offset and data buffers per column. → `e.fmt.arrow.columns`
2096. **Parquet Page Encoding (RLE / Bit-Packing)** – Hybrid run-length and bit-packed encoding of levels and values. → `e.fmt.parquet.decode_page`
2097. **Delta Encoding of Integers** – Storing successive differences to shrink monotone sequences. → see #627 (`e.algo.coding.delta_encode`)
2098. **Frame-of-Reference Encoding** – Storing offsets from a block minimum in fixed bit widths. → see #628 (`e.algo.coding.for_encode`)
2099. **Simple8b Integer Packing** – Packing runs of small integers into 64-bit words by selector. → `e.algo.coding.simple8b_encode`
2100. **Dictionary Encoding** – Replacing repeated values with indices into a value table. → `e.algo.coding.dictionary_encode`

## 38. Web Browsers, Frontend & UI Algorithms (2101–2150)

2101. **HTML Tokenizer (WHATWG)** – State-machine tokenization with insertion-mode recovery rules. → `e.fmt.html.tokenize`
2102. **HTML Tree Construction** – Building the DOM from tokens with the adoption agency algorithm. → `e.fmt.html.parse`
2103. **CSS Selector Matching** – Matching right-to-left through compound selectors and combinators. → `e.fmt.css.select`
2104. **CSS Cascade and Specificity Resolution** – Ordering declarations by origin, specificity, and source order. → `e.fmt.css.cascade`
2105. **CSS Inheritance and Computed Values** – Resolving relative units and inherited properties per element. → `e.ui.style.resolve`
2106. **Style Invalidation (Descendant Invalidation Sets)** – Restyling only subtrees affected by a class or attribute change. → skip: an implementation detail of an existing module, not an API
2107. **Block Layout (Normal Flow)** – Stacking block boxes vertically with margin collapsing. → `e.ui.layout.flow`
2108. **Inline Layout and Line Breaking** – Packing inline boxes into line boxes with baseline alignment. → `e.text.layout.layout`
2109. **Flexbox Layout Algorithm** – Distributing free space along the main axis with grow and shrink factors. → `e.ui.layout.flex`
2110. **CSS Grid Layout (Track Sizing)** – Resolving track sizes through intrinsic, flexible, and auto phases. → `e.ui.layout.grid`
2111. **Table Layout (Automatic Algorithm)** – Computing column widths from cell minimum and maximum widths. → `e.ui.layout.table`
2112. **Stacking Context Painting Order** – Painting layers by z-index in the order the specification defines. → `e.gfx.scene.paint_order`
2113. **Compositing Layer Assignment** – Promoting elements to GPU layers and squashing overlapping ones. → skip: an implementation detail of an existing module, not an API
2114. **Display List Rasterization** – Recording paint commands then rasterizing tiles on worker threads. → `e.gfx.scene.rasterize`
2115. **Damage Rectangle Tracking** – Repainting only regions invalidated since the last frame. → `e.ui.window.damage`
2116. **Hit Testing** – Finding the topmost element under a point through the layer and box trees. → `e.ui.widget.hit_test`
2117. **Scroll Anchoring** – Keeping the visible content stable while offscreen content changes size. → `e.ui.widget.scroll_anchor`
2118. **Virtual DOM Diffing** – Comparing two element trees and emitting minimal patch operations. → skip: an implementation detail of an existing module, not an API
2119. **Keyed List Reconciliation** – Matching children by key to move nodes instead of recreating them. → `e.ui.widget.reconcile_keyed`
2120. **Fiber Scheduling with Time Slicing** – Splitting rendering work into interruptible units by priority. → skip: an implementation detail of an existing module, not an API
2121. **Fine-Grained Reactivity (Signals)** – Tracking dependencies at read time and re-running only affected effects. → `e.ui.state.signal`
2122. **Topological Effect Scheduling** – Running derived computations in dependency order to avoid glitches. → `e.ui.state.schedule_effects`
2123. **Immutable Structural Sharing Updates** – Copying only the path to a changed node in a persistent tree. → see #1084 (`e.data.hamt.put`)
2124. **Memoized Selector Computation** – Recomputing derived state only when input references change. → `e.ui.state.memo`
2125. **Undo/Redo Command Stack** – Recording inverse operations for reversible edits. → `e.ui.undo.push`
2126. **Operational Transformation** – Transforming concurrent edits so they converge on all replicas. → see #1269 (`e.text.collab.transform`)
2127. **CRDT Text Sequence (RGA / YATA)** – Merging concurrent text edits with unique identifiers and tombstones. → `e.text.collab.crdt_insert`
2128. **Fractional Indexing** – Generating keys between two neighbors for orderable lists. → `e.text.collab.order_key_between`
2129. **Debounce and Throttle** – Limiting handler frequency by delaying or rate-capping invocations. → `e.ui.app.debounce`
2130. **Request Animation Frame Scheduling** – Aligning visual updates to the display refresh. → `e.ui.app.request_frame`
2131. **Idle Callback Scheduling** – Running low-priority work in frame slack time. → `e.ui.app.request_idle`
2132. **Intersection-Based Lazy Loading** – Deferring resource loads until elements near the viewport. → `e.ui.widget.lazy_load`
2133. **Windowed List Virtualization** – Rendering only the rows intersecting the scroll viewport. → `e.ui.widget.virtual_list`
2134. **Text Measurement and Ellipsis Truncation** – Fitting text to a width with binary search over characters. → see #365 (`e.text.layout.ellipsis`)
2135. **Font Fallback Resolution** – Choosing fonts per character run by coverage. → `e.text.shape.fallback_font`
2136. **Text Shaping (HarfBuzz-style)** – Applying OpenType substitution and positioning to glyph runs. → `e.text.shape.shape`
2137. **Line Breaking (Knuth-Plass)** – Choosing break points minimizing total badness over a paragraph. → see #360 (`e.text.wrap.optimal`)
2138. **Hyphenation (Liang's Algorithm)** – Finding break points from pattern-derived odd/even digit rules. → `e.text.hyphen.break_points`
2139. **Subpixel Text Rendering** – Filtering glyph coverage across RGB subpixels. → `e.gfx.paint.glyph_subpixel`
2140. **Signed Distance Field Font Rendering** – Rendering scalable glyphs from a distance texture. → `e.gfx.paint.glyph_sdf`
2141. **Color Space Conversion (sRGB ↔ Linear)** – Applying the transfer function before and after blending. → `e.gfx.paint.srgb_to_linear`
2142. **Alpha Compositing (Porter-Duff)** – Combining premultiplied colors with the over operator. → `e.gfx.paint.composite`
2143. **Bezier Path Flattening** – Subdividing curves into line segments within a tolerance. → `e.gfx.geometry.flatten`
2144. **Nonzero and Even-Odd Fill Rules** – Deciding path interiors from winding counts. → `e.gfx.paint.fill_rule`
2145. **Scanline Polygon Rasterization with Coverage** – Accumulating fractional coverage for antialiased fills. → `e.gfx.paint.fill_path`
2146. **Stroke Geometry Generation** – Offsetting paths with joins and caps into fill geometry. → `e.gfx.geometry.stroke`
2147. **Gradient Rasterization** – Mapping pixels to color stops along linear or radial parameters. → `e.gfx.paint.gradient`
2148. **Focus Order Traversal** – Ordering focusable elements by tabindex and document position. → `e.ui.accessibility.focus_order`
2149. **Accessibility Tree Construction** – Deriving roles, names, and states from DOM and ARIA attributes. → `e.ui.accessibility.tree`
2150. **Prefetch and Preload Prioritization** – Scheduling resource fetches by predicted need and render blocking. → skip: implementable, but too specialised for the standard library

## 39. Streaming, Sketches & Approximate Algorithms (2151–2200)

2151. **Sticky Sampling** – Probabilistic frequency tracking with a sampling rate that decreases as the stream grows. → skip: implementable, but too specialised for the standard library
2152. **Top-k via Count-Min plus Min-Heap** – Maintaining candidate heavy hitters keyed by sketch estimates. → `e.algo.sketch.top_k`
2153. **Lossy Counting** – Bucketed frequency estimates with periodic pruning of low counts. → `e.algo.sketch.lossy_counting`
2154. **Count Sketch** – Hashed counters with random signs for unbiased frequency estimates. → `e.algo.sketch.count_sketch`
2155. **AMS Sketch (F2 Estimation)** – Estimating the second frequency moment with ±1 hash projections. → `e.algo.sketch.ams_f2`
2156. **Flajolet-Martin Sketch** – Estimating distinct counts from the maximum trailing-zero count. → see #981 (`e.algo.sketch.flajolet_martin`)
2157. **LogLog / SuperLogLog** – Bucketed maximum-rank estimators preceding HyperLogLog. → see #242 (`e.algo.sketch.hll_estimate`)
2158. **HyperLogLog++** – Sparse representation and bias correction for small cardinalities. → `e.algo.sketch.hll_sparse`
2159. **HyperLogLog Merge** – Taking the per-register maximum to union two sketches. → `e.algo.sketch.hll_merge`
2160. **KMV (K Minimum Values) Sketch** – Estimating cardinality from the k-th smallest hash. → `e.algo.sketch.kmv`
2161. **Theta Sketch Set Operations** – Union, intersection, and difference of sampled hash sets with thresholds. → `e.algo.sketch.theta_union`
2162. **MinHash Signatures** – Estimating Jaccard similarity from per-hash minimum values. → see #258 (`e.algo.sketch.minhash`)
2163. **One-Permutation Hashing** – Producing many MinHash values from a single hash pass. → `e.algo.sketch.minhash_one_permutation`
2164. **b-Bit MinHash** – Storing only the low bits of each minimum to shrink signatures. → `e.algo.sketch.minhash_b_bit`
2165. **SimHash** – Locality-sensitive fingerprinting where Hamming distance tracks cosine similarity. → see #259 (`e.algo.sketch.simhash`)
2166. **Locality-Sensitive Hashing (Random Projection)** – Bucketing vectors by the signs of random hyperplanes. → see #257 (`e.algo.sketch.lsh_bucket`)
2167. **Locality-Sensitive Hashing (p-Stable)** – Quantized random projections for Euclidean nearest neighbors. → `e.algo.sketch.lsh_p_stable`
2168. **Morton Filter** – Compressed cuckoo-style filter with block-local overflow tracking. → skip: implementable, but too specialised for the standard library
2169. **Bloomier Filter** – Static structure mapping keys to values with false positives only on non-keys. → skip: implementable, but too specialised for the standard library
2170. **Ribbon Filter** – Near-optimal space static filter built by solving a banded linear system. → `e.algo.sketch.ribbon_filter`
2171. **Vacuum Filter** – Cuckoo-style filter choosing alternate buckets nearby for cache locality. → skip: implementable, but too specialised for the standard library
2172. **Counting Quotient Filter** – Quotient filter variant with variable-length counters. → `e.algo.sketch.counting_quotient_filter`
2173. **Stable Bloom Filter** – Bloom filter with random decrements for unbounded streams. → `e.algo.sketch.stable_bloom`
2174. **Age-Partitioned Bloom Filter** – Sliding-window membership by rotating segment groups. → `e.algo.sketch.bloom_windowed`
2175. **Greenwald-Khanna Quantiles** – Deterministic quantile summary with tuple-based error bounds. → `e.algo.sketch.gk_quantiles`
2176. **KLL Sketch** – Compactor-based quantile sketch with near-optimal space. → see #1094 (`e.algo.sketch.kll`)
2177. **UDDSketch** – Uniform-collapse DDSketch variant keeping bounded relative error under merges. → see #1095 (`e.algo.sketch.ddsketch`)
2178. **Frugal Streaming Median** – One-counter streaming median estimate. → `e.algo.sketch.frugal_median`
2179. **P² Algorithm** – Quantile estimation with five parabolic-interpolated markers. → `e.algo.sketch.p_square`
2180. **Exponential Histogram (Datar-Gionis)** – Sliding-window counts with logarithmically merged buckets. → `e.data.window.exponential_histogram`
2181. **Sliding HyperLogLog** – Timestamped registers answering cardinality over recent windows. → `e.algo.sketch.hll_sliding`
2182. **Sliding Window Sum (Two-Stack Queue)** – Amortized O(1) aggregate over a moving window. → `e.data.window.two_stack`
2183. **DABA Sliding Window Aggregation** – Worst-case O(1) window aggregation without inverses. → `e.data.window.daba`
2184. **Reservoir Sampling with Time Decay** – Biasing retention toward recent items. → `e.algo.rand.reservoir_decayed`
2185. **Priority Sampling** – Order sampling with weight-derived priorities for subset-sum estimates. → `e.algo.rand.priority_sample`
2186. **VarOpt Sampling** – Variance-optimal weighted sampling for subset sums. → `e.algo.rand.varopt_sample`
2187. **Bloom Filter Sizing** – Choosing bits and hash count from target false-positive rate. → `e.algo.sketch.bloom_size`
2188. **Kirsch-Mitzenmacher Double Hashing** – Deriving k hash values from two base hashes. → skip: an implementation detail of an existing module, not an API
2189. **Count-Min Point Query with Range Trees** – Dyadic decomposition for range frequency estimates. → `e.algo.sketch.count_min_range`
2190. **Sketch-Based Join Size Estimation** – Estimating result cardinality from AMS sketch inner products. → `e.db.query.estimate_join_size`
2191. **Streaming k-Means (Coreset Tree)** – Merging weighted coresets to cluster an unbounded stream. → `e.ml.cluster.kmeans_streaming`
2192. **BIRCH Clustering Feature Tree** – Incremental clustering with summarized subclusters. → `e.ml.cluster.birch`
2193. **Streaming PCA (Oja's Rule)** – Updating a principal component with each arriving vector. → `e.ml.reduce.pca_online`
2194. **Frequent Directions** – Deterministic matrix sketch by shrinking singular values. → `e.ml.reduce.frequent_directions`
2195. **Online Gradient Descent** – Updating a model per example with a decaying step. → `e.ml.optim.online_gd`
2196. **Adaptive Windowing (ADWIN)** – Detecting concept drift by comparing subwindow means. → `e.algo.timeseries.adwin`
2197. **CUSUM Change Detection** – Accumulating deviations from a target to flag shifts. → `e.algo.timeseries.cusum`
2198. **Page-Hinkley Test** – Cumulative difference test for mean change in a stream. → `e.algo.timeseries.page_hinkley`
2199. **Seasonal-Trend Decomposition (STL)** – Splitting a series into trend, seasonal, and remainder by LOESS. → `e.algo.timeseries.stl`
2200. **Holt-Winters Forecasting** – Triple exponential smoothing with level, trend, and seasonality. → `e.algo.timeseries.holt_winters`

## 40. Testing, Reliability, Fuzzing & Software Engineering Tooling (2201–2250)

2201. **Property-Based Testing Generators** – Producing random structured inputs from combinator descriptions. → `e.test.prop.generate`
2202. **Test Case Shrinking** – Reducing a failing input to a minimal counterexample. → `e.test.prop.shrink`
2203. **Delta Debugging (ddmin)** – Bisecting an input to isolate the failure-inducing subset. → `e.test.fuzz.minimize`
2204. **Hierarchical Delta Debugging** – Minimizing tree-structured inputs level by level. → `e.test.fuzz.minimize_tree`
2205. **Grammar-Based Fuzzing** – Generating inputs by expanding a grammar with random productions. → `e.test.fuzz.grammar`
2206. **Mutation-Based Fuzzing** – Flipping, inserting, and splicing bytes of seed inputs. → see #1444 (`e.test.fuzz.run`)
2207. **Concolic Execution** – Running concretely while collecting path constraints to flip branches. → skip: belongs in the toolchain (build, test runner, pacman)
2208. **Symbolic Execution with Path Merging** – Exploring program paths as constraint sets solved by SMT. → skip: belongs in the toolchain (build, test runner, pacman)
2209. **Mutation Testing** – Injecting small code changes and checking that tests fail. → skip: belongs in the toolchain (build, test runner, pacman)
2210. **Equivalent Mutant Detection** – Filtering mutants that cannot change behavior. → skip: belongs in the toolchain (build, test runner, pacman)
2211. **Code Coverage Instrumentation (Basic Block)** – Recording executed blocks via inserted counters. → `e.test.coverage.blocks`
2212. **Branch Coverage Measurement** – Tracking both outcomes of each conditional. → `e.test.coverage.branches`
2213. **MC/DC Coverage Analysis** – Verifying each condition independently affects a decision. → `e.test.coverage.mcdc`
2214. **Test Impact Analysis** – Selecting tests whose covered code changed. → skip: belongs in the toolchain (build, test runner, pacman)
2215. **Test Prioritization by Failure History** – Ordering tests by recent failure probability. → skip: belongs in the toolchain (build, test runner, pacman)
2216. **Flaky Test Detection (Rerun Statistics)** – Identifying tests whose outcome varies without code change. → skip: belongs in the toolchain (build, test runner, pacman)
2217. **Snapshot Testing with Serialization** – Comparing serialized output against a stored baseline. → `e.test.support.snapshot`
2218. **Golden Master Comparison** – Diffing current output against recorded legacy behavior. → `e.test.support.golden`
2219. **Contract Testing (Consumer-Driven)** – Verifying a provider against consumer-recorded expectations. → skip: implementable, but too specialised for the standard library
2220. **Record and Replay of HTTP Interactions** – Capturing responses for deterministic replay. → `e.test.support.http_replay`
2221. **Deterministic Simulation Testing** – Running distributed code on a simulated scheduler with seeded randomness. → `e.test.sim.run`
2222. **Jepsen-Style Linearizability Checking** – Verifying histories against a sequential model. → `e.test.linearize.check`
2223. **Knossos / Porcupine Linearizability Check** – Searching for a linearization of a concurrent history. → see #2222 (`e.test.linearize.check`)
2224. **Model Checking (Explicit State)** – Exhaustively exploring state space for property violations. → skip: implementable, but too specialised for the standard library
2225. **Bounded Model Checking** – Unrolling transitions to a depth and checking with SAT. → skip: implementable, but too specialised for the standard library
2226. **TLA+ State Space Exploration** – Breadth-first exploration of specification states with invariants. → skip: belongs in the toolchain (build, test runner, pacman)
2227. **Chaos Fault Injection** – Introducing latency, errors, and crashes to test resilience. → `e.test.support.inject_fault`
2228. **Circuit Breaker State Machine** – Opening after failures and probing before closing. → see #710 (`e.resilience.circuit_breaker`)
2229. **Retry with Exponential Backoff and Jitter** – Spacing retries randomly to avoid thundering herds. → see #711 (`e.resilience.backoff`)
2230. **Token Bucket Rate Limiting** – Admitting requests while tokens remain and refilling at a fixed rate. → see #705 (`e.ratelimit.token_bucket`)
2231. **Sliding Log Rate Limiting** – Counting timestamps within a trailing window. → see #708 (`e.ratelimit.sliding_log`)
2232. **Bulkhead Isolation** – Partitioning resources so one failing dependency cannot exhaust all threads. → `e.resilience.bulkhead`
2233. **Health Check Aggregation** – Combining dependency probes into liveness and readiness states. → `e.resilience.health`
2234. **Canary Analysis (Statistical Comparison)** – Comparing canary and baseline metrics with hypothesis tests. → see #1911 (`e.algo.stat.test.t_test`)
2235. **Feature Flag Percentage Rollout** – Hashing user identifiers to a stable bucket for gradual exposure. → `e.resilience.rollout_bucket`
2236. **Semantic Version Range Resolution** – Selecting versions satisfying caret, tilde, and range constraints. → `e.fmt.semver.satisfies`
2237. **Dependency Resolution (PubGrub)** – Version solving with conflict-driven incompatibility learning. → `pacman.resolve`
2238. **Lockfile Generation** – Recording exact resolved versions and hashes for reproducible installs. → `pacman.lock`
2239. **Build Graph Incremental Rebuild** – Re-executing only targets whose inputs changed. → skip: belongs in the toolchain (build, test runner, pacman)
2240. **Content-Addressed Build Caching** – Keying outputs by hashes of inputs and commands. → skip: belongs in the toolchain (build, test runner, pacman)
2241. **Three-Way Merge** – Combining two changes against a common ancestor. → see #378 (`e.text.diff.merge3`)
2242. **Merge Conflict Hunk Detection** – Identifying overlapping changed regions. → `e.text.diff.conflicts`
2243. **Git Bisect** – Binary searching commit history for the first bad revision. → skip: belongs in the toolchain (build, test runner, pacman)
2244. **Rename Detection by Similarity** – Pairing deleted and added files with high content similarity. → `e.text.diff.similarity`
2245. **Blame Line Attribution** – Tracing each line to its last modifying commit. → skip: belongs in the toolchain (build, test runner, pacman)
2246. **Semantic Diff (AST-Based)** – Comparing syntax trees to ignore formatting noise. → skip: belongs in the toolchain (build, test runner, pacman)
2247. **Code Clone Detection (Token-Based)** – Finding duplicate fragments via suffix-tree token matching. → skip: belongs in the toolchain (build, test runner, pacman)
2248. **Cyclomatic Complexity Calculation** – Counting linearly independent paths through a function. → skip: belongs in the toolchain (build, test runner, pacman)
2249. **Dead Code Detection via Call Graph** – Flagging functions unreachable from entry points. → skip: belongs in the Neper compiler, not the library
2250. **Static Taint Analysis** – Tracking untrusted data from sources to sensitive sinks. → skip: belongs in the toolchain (build, test runner, pacman)

