    const controlGroups = new Map([
      ["Content and display", "Avatar Badge Canvas Card Cover Divider EmptyState Gauge Icon Image Level Placeholder ProgressBar ProgressRing RichText SelectableText Skeleton Text".split(" ")],
      ["Layout and structure", "ActionRow Form FormField GroupBox HeaderRow ResizablePane Row SplitView".split(" ")],
      ["Actions", "Button Fab IconButton Link SpeedDial SplitButton SwipeActions ToggleButton Toolbar".split(" ")],
      ["Input and selection", "Autocomplete ButtonEdit Chip Choice ColorPicker ComboBox Dial FieldLabel FieldMessage FontPicker FormattedField MultiSelectList Picker Rating SearchBar SegmentedControl Select ShortcutRecorder Slider SpinBox Stepper Switch TextField TokenField ValidationSummary".split(" ")],
      ["Navigation", "AppBar Breadcrumbs DestinationBar DocumentTabs MenuBar NavigationDrawer NavigationSplit NavigationStack PageIndicator PageView Pagination Tabs WindowSwitcher Wizard".split(" ")],
      ["Collections and data", "DataGrid GridView KeyValueEditor List ListBox NotificationList Outline PropertyGrid ReorderableList ScrollBar Table TableRow Tree TreeTable VirtualGrid VirtualList".split(" ")],
      ["Overlays and feedback", "Accordion ActionSheet Banner CommandPalette ContextMenu Dialog Disclosure Flyout Menu Popover Popup Sheet Snackbar Tooltip".split(" ")],
      ["Date and time", "Calendar DatePicker DurationPicker TimePicker".split(" ")],
      ["Workspace", "Browser DockLayout DockPanel MultiDocumentWorkspace StatusBar".split(" ")],
      ["Media and refresh", "Carousel PullToRefresh".split(" ")]
    ])

    function renderCatalog(dialog, groups) {
      const output = dialog.querySelector(".catalog-dialog-groups")
      const fragment = document.createDocumentFragment()
      let count = 0
      for (const [category, items] of groups) {
        const collapsible = dialog.id === "algorithm-catalog"
        const group = document.createElement(collapsible ? "details" : "section")
        group.className = "catalog-dialog-group"
        const heading = document.createElement(collapsible ? "summary" : "h3")
        heading.textContent = dialog.id === "algorithm-catalog" ? `${category} (${items.length})` : category
        const grid = document.createElement("div")
        grid.className = "catalog-entry-grid"
        for (const item of items) {
          const card = document.createElement(item.href ? "a" : "div")
          card.className = "catalog-entry"
          if (item.href) {
            card.href = item.href
            if (item.preview) card.addEventListener("click", event => {
              if (event.ctrlKey || event.metaKey || event.shiftKey || event.button) return
              event.preventDefault()
              const detail = document.getElementById("control-detail")
              detail.querySelector("h2").textContent = item.name
              detail.querySelector("iframe").src = `ux/control-preview.html?name=${encodeURIComponent(item.name)}&detail`
              detail.querySelector("#control-detail-spec").href = `https://github.com/nebosa-company/neper/blob/master/docs/ux/components/${item.name}/README.md`
              detail.showModal()
            })
          }
          if (item.image) {
            const image = document.createElement("img")
            image.className = "catalog-entry-image"
            image.src = item.image
            image.width = 360
            image.height = 240
            image.loading = "lazy"
            image.alt = `${item.name} chart rendered by Neper`
            card.append(image)
          }
          if (item.preview) {
            const preview = document.createElement("span")
            preview.className = "catalog-entry-preview"
            const frame = document.createElement("iframe")
            frame.src = `ux/control-preview.html?name=${encodeURIComponent(item.preview)}`
            frame.loading = "lazy"
            frame.tabIndex = -1
            frame.setAttribute("aria-hidden", "true")
            preview.append(frame)
            card.append(preview)
          }
          const name = document.createElement("span")
          name.textContent = item.name
          card.append(name)
          if (item.description) {
            const description = document.createElement("p")
            description.textContent = item.description
            card.append(description)
          }
          if (item.detail) {
            const detail = document.createElement("code")
            detail.textContent = item.detail
            card.append(detail)
          }
          grid.append(card)
          count++
        }
        group.append(heading, grid)
        fragment.append(group)
      }
      if (!count) throw new Error("catalog is empty")
      if (dialog.id !== "control-catalog") dialog.querySelector("h2").textContent = `${count.toLocaleString("en-US")} ${{"module-catalog": "modules", "algorithm-catalog": "algorithms", "chart-catalog": "chart types"}[dialog.id]}`
      output.replaceChildren(fragment)
      dialog.querySelector(".catalog-dialog-status").hidden = true
      dialog.dataset.loaded = "true"
    }

    const moduleDescriptionOverrides = new Map([
      ["e.algo.bdd", "Reduced ordered binary decision diagrams with Boolean operations, evaluation, and model counting."],
      ["e.algo.bignum", "Arbitrary-precision integer arithmetic."],
      ["e.algo.bitset", "Creates, queries, and combines compact sets of bits."],
      ["e.algo.complex", "Complex-number arithmetic for 32-bit and 64-bit floating-point values."],
      ["e.algo.decimal", "Fixed-scale decimal arithmetic with explicit precision."],
      ["e.algo.deflate", "DEFLATE compression and decompression."],
      ["e.algo.disjoint_set", "Maintains disjoint sets for connectivity and grouping queries."],
      ["e.algo.hash", "Non-cryptographic hashing algorithms and checksums."],
      ["e.algo.linalg.matrix", "Dense and sparse matrix operations for linear algebra."],
      ["e.algo.linalg.tensor", "Multidimensional tensor views and operations for linear algebra."],
      ["e.algo.rand", "Generates repeatable random values and bounded random choices."],
      ["e.algo.rand.dist", "Samples common probability distributions from random-number generators."],
      ["e.algo.rand.quasi", "Generates low-discrepancy and quasi-random sequences."],
      ["e.algo.sketch", "Probabilistic data sketches for cardinality, frequency, similarity, and heavy-hitter estimation."],
      ["e.algo.smt", "Satisfiability-modulo-theories solving for equality logic and bit-vector constraints."],
      ["e.algo.sort", "Sorting, selection, partitioning, and ordering algorithms."],
      ["e.algo.stat", "Statistical summaries, distributions, sampling, and analysis."],
      ["e.algo.stat.test", "Statistical hypothesis tests and significance analysis."],
      ["e.algo.uuid", "Generates, parses, and formats universally unique identifiers."],
      ["e.audio.mixer", "Multichannel audio mixing, routing, gain, and buses."],
      ["e.audio.spatial", "Spatial audio positioning, attenuation, and listener transforms."],
      ["e.crypto.hash", "Cryptographic hash functions and secure digest operations."],
      ["e.concurrent.deque", "Work-stealing double-ended queues for concurrent task scheduling."],
      ["e.data.deque", "Double-ended queues with efficient insertion and removal at either end."],
      ["e.data.list", "Dynamic lists for ordered collections of values."],
      ["e.data.map", "Key-value maps for fast lookup and updates."],
      ["e.data.ring", "Fixed-capacity ring buffers for bounded streaming data."],
      ["e.data.window", "Maintains sliding windows over streaming data."],
      ["e.fmt.csv", "CSV parsing and generation with explicit dialect handling."],
      ["e.fmt.json.schema", "JSON Schema validation for types, values, arrays, objects, composition, and references."],
      ["e.fmt.html.template", "Generates HTML safely from templates and dynamic values."],
      ["e.fmt.mp3", "MP3 audio stream parsing and decoding."],
      ["e.fmt.msgpack", "MessagePack encoding and decoding."],
      ["e.fmt.wav", "WAV audio file encoding and decoding."],
      ["e.fmt.zlib", "Zlib encoding and decoding with RFC 1950 framing and Adler-32 integrity checks."],
      ["e.game.ai", "Artificial-intelligence behaviors and decision systems for games."],
      ["e.game.camera", "Game-camera transforms, tracking, bounds, and viewport control."],
      ["e.game.collide2d", "Two-dimensional collision detection and contact tests."],
      ["e.game.dialog", "Branching dialogue trees, conditions, and conversation state."],
      ["e.game.ecs", "Entity-component systems for organizing game objects and behavior."],
      ["e.game.grid", "Grid coordinates, neighborhoods, traversal, and spatial queries."],
      ["e.game.input", "Game-input actions, bindings, and device state."],
      ["e.game.loop", "Deterministic game-loop timing and frame scheduling."],
      ["e.game.netsync", "Network synchronization and state reconciliation for games."],
      ["e.game.particle", "Particle-system simulation, emission, and lifecycle updates."],
      ["e.game.sprite", "Two-dimensional sprite animation, batching, and rendering data."],
      ["e.game.tilemap", "Tile-map layers, coordinates, traversal, and queries."],
      ["e.game.vision", "Visibility, field-of-view, and line-of-sight calculations."],
      ["e.gpu.tensor", "GPU-accelerated tensor operations over deterministic linear-algebra views."],
      ["e.math", "Scalar mathematics, floating-point operations, and numerical helpers."],
      ["e.math.fixed", "Fixed-point arithmetic for deterministic numeric computations."],
      ["e.math.opt.convex", "Convex optimization models and solvers."],
      ["e.math.opt.meta", "Metaheuristic optimization for difficult search spaces."],
      ["e.ml.cluster.density", "Density-based clustering for machine learning."],
      ["e.net.snapshot", "Captures and reconciles networked application state."],
      ["e.net.http.auth", "HTTP authentication and authorization."],
      ["e.text.normalize", "Unicode text normalization and canonical equivalence."],
      ["e.text.unicode", "Unicode properties, categories, and character operations."],
      ["e.text.utf8", "UTF-8 validation, decoding, encoding, and traversal."],
      ["e.thread", "Native thread creation, coordination, and lifecycle management."],
      ["e.thread.pool", "Bounded thread pools, task submission, parallel ranges, work stealing, and orderly shutdown."],
      ["e.time", "Monotonic clocks, wall time, durations, and timers."],
      ["e.ui.collection", "Lists, tables, trees, grids, and virtualized user-interface collections."],
      ["e.ui.navigation", "Navigation stacks, tabs, breadcrumbs, drawers, and routing controls."],
      ["e.ui.overlay", "Dialogs, popovers, menus, tooltips, and other user-interface overlays."],
      ["e.ui.window", "Creates and manages native application windows."]
    ])

    const moduleTerms = new Map([
      ["aead", "authenticated encryption"], ["ai", "artificial intelligence"], ["align", "sequence alignment"],
      ["analysis", "analysis and feature extraction"], ["anti_entropy", "anti-entropy synchronization"],
      ["anim", "animation"], ["ann", "approximate nearest-neighbor search"], ["arrow", "Apache Arrow"],
      ["asn1", "ASN.1"], ["avro", "Apache Avro"], ["bdd", "binary decision diagrams"],
      ["app", "application lifecycle"], ["asset", "asset management"], ["auth", "authentication"],
      ["balance", "load balancing"], ["bayes", "Bayesian models"],
      ["bidi", "bidirectional text"], ["bignum", "arbitrary-precision numbers"], ["bitset", "bit sets"],
      ["bk_tree", "BK trees"], ["brotli", "Brotli"], ["bson", "BSON"], ["btree", "B-trees"],
      ["bzip2", "Bzip2"], ["cache", "caching"], ["calendar", "calendar calculations"],
      ["cbor", "CBOR"], ["cipher", "symmetric ciphers"], ["classic", "classical ciphers"],
      ["cli", "command-line interfaces"], ["clock", "logical clocks"], ["cluster", "clustering"],
      ["coding", "coding-theory"], ["collate", "collation"],
      ["coap", "CoAP"], ["collab", "collaborative editing"], ["collide2d", "two-dimensional collision detection"],
      ["collective", "collective communication"], ["color", "coloring"], ["combin", "combinatorics"],
      ["combopt", "combinatorial optimization"], ["commit", "distributed transactions"],
      ["community", "community detection"], ["consensus", "distributed consensus"],
      ["consistent_hash", "consistent hashing"], ["control", "controls"], ["crdt", "conflict-free replicated data types"],
      ["convex", "convex optimization"], ["cron", "scheduled jobs"], ["csp", "constraint satisfaction"],
      ["css", "CSS"], ["csv", "CSV"], ["curve", "curves and splines"], ["deadlock", "deadlock detection"],
      ["dht", "distributed hash tables"], ["diff", "differencing"],
      ["dns", "DNS"], ["dp", "dynamic programming"], ["ecc", "error correction"],
      ["ecs", "entity-component systems"], ["egraph", "equality-graph reasoning"], ["election", "leader election"],
      ["encoding", "encoding conversion"], ["failure_detector", "failure detection"], ["fenwick", "Fenwick trees"],
      ["fft", "fast Fourier transforms"], ["flac", "FLAC"], ["flatbuffers", "FlatBuffers"],
      ["float", "floating-point arithmetic"], ["fmt", "format"], ["fs", "filesystem"], ["fuzz", "fuzz testing"],
      ["fx", "effects"], ["geom", "two-dimensional geometry"], ["geom3", "three-dimensional geometry"],
      ["geo", "geospatial"], ["gf", "finite fields"], ["gfx", "graphics"], ["gossip", "gossip protocols"],
      ["gpu", "GPU"], ["gzip", "gzip"],
      ["hamt", "hash-array mapped tries"],
      ["hmm", "hidden Markov models"], ["html", "HTML"], ["http", "HTTP"], ["http3", "HTTP/3"],
      ["idna", "internationalized domain names"], ["ini", "INI"], ["io", "input and output"],
      ["hyphen", "hyphenation"], ["image", "image processing"], ["index", "indexing and search"],
      ["input", "input handling"], ["iso", "isomorphism"], ["iter", "iteration"], ["jpeg", "JPEG"], ["json", "JSON"],
      ["jwt", "JSON Web Tokens"],
      ["kdf", "key derivation"], ["knn", "k-nearest neighbors"], ["kx", "key exchange"], ["linear", "linear models and regression"],
      ["linalg", "linear algebra"], ["ll", "LL grammars"], ["lr", "LR grammars"], ["mac", "message authentication"],
      ["mc", "Monte Carlo methods"], ["mcmc", "Markov chain Monte Carlo methods"], ["mem", "memory"],
      ["linearize", "linearizability checking"], ["linked", "linked lists"], ["locale", "locale-aware operations"],
      ["lock", "distributed locking"], ["loss", "loss functions"], ["mail", "email"], ["map", "mapping and localization"],
      ["markdown", "Markdown"], ["match", "matching"], ["merkle", "Merkle trees and proofs"],
      ["metric", "measurement and similarity"], ["mime", "MIME"],
      ["mmap", "memory mapping"], ["mp3", "MP3"], ["mqtt", "MQTT"], ["lz4", "LZ4"],
      ["lzma", "LZMA"], ["lzw", "LZW"],
      ["motion", "motion generation and control"], ["msgpack", "MessagePack"], ["mutex", "distributed mutual exclusion"],
      ["nav", "navigation and pathfinding"], ["netsync", "network synchronization"], ["nn", "neural networks"],
      ["noise", "secure handshakes and sessions"],
      ["ntheory", "number theory"], ["ode", "ordinary differential equations"], ["opt", "optimization"],
      ["optim", "optimization"], ["opus", "Opus"], ["parquet", "Apache Parquet"], ["pem", "PEM"],
      ["paint", "vector painting"], ["particle", "particle systems"], ["physics", "physics simulation"],
      ["plan", "planning"], ["png", "PNG"], ["pool", "connection pooling"], ["pretty", "pretty-printing"], ["proc", "processes"],
      ["procgen", "procedural generation"], ["prop", "property-based testing"], ["protobuf", "Protocol Buffers"],
      ["query", "query processing"], ["quoted_printable", "quoted-printable data"], ["quic", "QUIC"],
      ["rand", "random numbers"], ["random", "secure random-number generation"], ["rank", "relevance ranking"],
      ["raster", "rasterization"], ["ratelimit", "rate limiting"], ["reclaim", "memory reclamation"],
      ["reduce", "dimensionality reduction"], ["regex", "regular expressions"], ["rl", "reinforcement learning"],
      ["reliable", "reliable messaging"], ["replica", "replication"], ["root", "root finding"],
      ["sample", "sampling"], ["sat", "Boolean satisfiability"], ["scene", "scene graphs"],
      ["schedule", "scheduling"], ["secret", "secret management"], ["segment", "segmentation"],
      ["semver", "semantic versions"], ["shade", "material shading"], ["shell", "shell integration"],
      ["sign", "digital signatures"], ["sim", "simulation-based testing"],
      ["simd", "vector processing"], ["smt", "satisfiability modulo theories"], ["snappy", "Snappy"],
      ["span", "spanning structures"],
      ["snapshot", "state snapshots"], ["spatial", "spatial indexing"], ["special", "special functions"],
      ["stat", "statistics"], ["state", "state management"], ["stem", "stemming"], ["stun", "STUN"],
      ["style", "styling and themes"], ["suffix", "suffix indexing"],
      ["support", "fixtures and helpers"], ["svm", "support vector machines"], ["synth", "sound synthesis"],
      ["sync", "clock synchronization"], ["tar", "TAR archives"], ["testing", "testing and diagnostics"],
      ["tilemap", "tile maps"], ["timeseries", "time-series analysis"], ["tls", "TLS"],
      ["template", "templating"], ["texture", "texture processing"], ["tokenize", "tokenization"], ["toml", "TOML"],
      ["tz", "time zones"], ["ui", "user interfaces"], ["uri", "URIs"], ["utf8", "UTF-8"],
      ["trace", "ray tracing"], ["undo", "undo and redo"], ["uuid", "unique-identifier"], ["vision", "computer vision"],
      ["watch", "file watching"], ["wav", "WAV"], ["webp", "WebP"], ["widget", "widget composition"],
      ["wrap", "line wrapping"], ["ws", "WebSockets"],
      ["x509", "X.509 certificates"], ["xml", "XML"], ["yaml", "YAML"], ["zip", "ZIP archives"],
      ["zlib", "zlib"], ["zstd", "Zstandard"]
    ])

    const moduleRootDescriptions = new Map([
      ["asset", "Embeds and retrieves immutable application assets."],
      ["async", "Coordinates non-blocking operations and readiness events."],
      ["atomic", "Provides atomic values, memory ordering, and lock-free primitives."],
      ["audio", "Represents audio buffers, streams, and core signal operations."],
      ["bytes", "Reads, writes, compares, and transforms byte sequences."],
      ["cancel", "Propagates cancellation requests and deadlines across operations."],
      ["channel", "Transfers typed values safely between concurrent workers."],
      ["cli", "Parses command-line arguments, options, and subcommands."],
      ["control", "Provides feedback controllers and control-system algorithms."],
      ["db", "Defines database connections, transactions, statements, and row streams."],
      ["debug", "Captures backtraces and resolves program symbols."],
      ["dsp", "Provides digital signal processing filters and transforms."],
      ["fs", "Reads, writes, watches, and manages files and directories."],
      ["gpu", "Runs compute and graphics workloads on CPU, Vulkan, and CUDA devices."],
      ["grep", "Searches text using patterns across strings and files."],
      ["io", "Provides typed input and output streams, readers, and writers."],
      ["log", "Emits structured application logs with levels and fields."],
      ["math", "Provides scalar mathematics, floating-point operations, and numerical helpers."],
      ["mem", "Controls memory layout, arenas, allocation, and byte views."],
      ["meta", "Inspects and transforms compile-time type information."],
      ["metrics", "Collects counters, gauges, histograms, and application measurements."],
      ["net", "Provides sockets, addresses, connections, and network protocols."],
      ["os", "Exposes operating-system services through one portable interface."],
      ["parse", "Builds tokenizers, parsers, syntax trees, and evaluators."],
      ["path", "Builds, normalizes, and compares platform-aware file paths."],
      ["proc", "Starts, supervises, and communicates with child processes."],
      ["ratelimit", "Controls request rates, quotas, and admission."],
      ["resilience", "Adds retries, backoff, circuit breaking, and load shedding."],
      ["simd", "Performs parallel numeric operations using CPU vector instructions."],
      ["str", "Builds, searches, parses, formats, and transforms byte strings."],
      ["sync", "Coordinates concurrent work with locks, semaphores, conditions, and barriers."],
      ["task", "Runs bounded tasks with cancellation, scheduling, and completion tracking."],
      ["test", "Provides assertions and shared primitives for automated testing."],
      ["thread", "Creates and coordinates native threads."],
      ["time", "Provides clocks, timestamps, durations, and timers."],
      ["trace", "Records structured execution traces and spans."],
      ["tz", "Converts times across IANA time zones and daylight-saving rules."],
      ["valid", "Validates values and reports structured validation errors."]
    ])

    const moduleDomainDescriptions = new Map([
      ["algo", "algorithms and utilities"], ["async", "for asynchronous programming"],
      ["audio", "for audio processing"], ["concurrent", "for concurrent execution"],
      ["crypto", "for cryptographic operations"], ["data", "for structured data"],
      ["db", "for database access"], ["dist", "for distributed systems"],
      ["fmt", "encoding, decoding, and validation"], ["fs", "for filesystem access"],
      ["game", "for game development"], ["gfx", "for graphics and rendering"],
      ["gpu", "for GPU computing"], ["math", "for numerical computing"],
      ["ml", "for machine learning"], ["net", "networking support"],
      ["os", "operating-system integration"], ["parse", "parsing tools"],
      ["robot", "for robotics"], ["test", "for software testing"],
      ["text", "for text processing"], ["thread", "for multithreaded execution"],
      ["time", "for time and scheduling"], ["ui", "for native user interfaces"]
    ])

    function describeModule(name) {
      if (moduleDescriptionOverrides.has(name)) return moduleDescriptionOverrides.get(name)
      const [_, domain, ...parts] = name.split(".")
      if (!parts.length) return moduleRootDescriptions.get(domain) || `${domain} standard-library capabilities.`
      const topic = parts.map(part => moduleTerms.get(part) || part.replaceAll("_", " ")).join(" ")
      const label = topic[0].toUpperCase() + topic.slice(1)
      return `${label} ${moduleDomainDescriptions.get(domain) || "capabilities and utilities"}.`
    }

    async function loadModules(dialog) {
      const modulesResponse = await fetch("modules.json")
      if (!modulesResponse.ok) throw new Error("module catalog unavailable")
      const plan = await modulesResponse.json()
      const modules = [...new Set(plan.tiers.flatMap(tier => tier.modules))].sort()
      const groups = new Map()
      for (const name of modules) {
        const namespace = name.split(".").slice(0, 2).join(".")
        if (!groups.has(namespace)) groups.set(namespace, [])
        groups.get(namespace).push({name, description: describeModule(name)})
      }
      renderCatalog(dialog, groups)
    }

    async function loadAlgorithms(dialog) {
      const response = await fetch("algos.md")
      if (!response.ok) throw new Error("algorithm catalog unavailable")
      const groups = new Map()
      let category = ""
      for (const line of (await response.text()).split(/\r?\n/)) {
        const heading = line.match(/^## \d+\.\s+(.+?)\s+\(\d+[–-]\d+\)$/)
        if (heading) category = heading[1]
        const entry = line.match(/^\d+\.\s+\*\*(.+?)\*\*.*?→ `((?:e|pacman)\.[^`]+)`/)
        if (!entry || !category) continue
        if (!groups.has(category)) groups.set(category, [])
        groups.get(category).push({name: entry[1], detail: entry[2]})
      }
      renderCatalog(dialog, groups)
    }

    async function loadCharts(dialog) {
      const guide = "blog/charts-field-guide.html"
      const response = await fetch(guide)
      if (!response.ok) throw new Error("chart guide unavailable")
      const page = new DOMParser().parseFromString(await response.text(), "text/html")
      const groups = new Map()
      let category = ""
      for (const node of page.querySelectorAll("h2, figure.chart-card")) {
        if (node.tagName === "H2") { category = node.textContent.trim(); continue }
        const image = node.querySelector("img")
        if (!category || !image) continue
        if (!groups.has(category)) groups.set(category, [])
        groups.get(category).push({name: node.querySelector("h3").textContent.trim(), image: `blog/${image.getAttribute("src")}`, href: `${guide}#${node.id}`})
      }
      renderCatalog(dialog, groups)
    }

    function loadControls(dialog) {
      const groups = new Map([...controlGroups].map(([category, names]) => [category, names.map(name => ({name, preview: name, href: `ux/control-preview.html?name=${name}`}))]))
      renderCatalog(dialog, groups)
    }

    for (const trigger of document.querySelectorAll("[data-catalog]")) {
      trigger.addEventListener("click", async () => {
        const dialog = document.getElementById(trigger.dataset.catalog)
        dialog.showModal()
        if (dialog.dataset.loaded) return
        try {
          if (dialog.id === "module-catalog") await loadModules(dialog)
          else if (dialog.id === "algorithm-catalog") await loadAlgorithms(dialog)
          else if (dialog.id === "chart-catalog") await loadCharts(dialog)
          else loadControls(dialog)
        } catch {
          const status = dialog.querySelector(".catalog-dialog-status")
          status.textContent = "Could not load this catalog."
          status.hidden = false
        }
      })
    }

    for (const dialog of document.querySelectorAll(".catalog-dialog")) {
      dialog.addEventListener("click", event => { if (event.target === dialog) dialog.close() })
    }

