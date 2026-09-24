const W = 1280
const H = 720
const BG = "#080a0f"
const SURFACE = "#121318"
const HIGH = "#1e1f24"
const TEXT = "#e1e2e9"
const MUTED = "#c3c6d5"
const BLUE = "#b3c5ff"
const BLUE_DARK = "#00468b"
const GREEN = "#a0f3bd"
const GREEN_DARK = "#11522e"
const COPPER = "#ffb692"
const FONT = "Metropolis"
const MONO = "Montserrat"

const enter = {
  enter: { from: { y: 28, opacity: 0 }, duration: 0.45, easing: "house" },
  exit: { to: { y: -18, opacity: 0 }, duration: 0.28, easing: "ease-in", anchor: "end" },
}

const title = (eyebrow, headline, body) => (
  <frame width={1120} height={138} layout="none">
    <text x={0} y={0} width={1120} height={22} fontFamily={FONT} fontSize={14} fontWeight={600} letterSpacing={1.2} color={BLUE}>{eyebrow}</text>
    <text x={0} y={32} width={1120} height={54} fontFamily={FONT} fontSize={42} fontWeight={500} color={TEXT}>{headline}</text>
    <text x={0} y={95} width={1080} height={38} fontFamily={FONT} fontSize={18} lineHeight={26} color={MUTED}>{body}</text>
  </frame>
)

const chip = (label, x, width) => (
  <frame x={x} y={0} width={width} height={40} layout="none" background="#39475f" radius={20}>
    <text x={0} y={10} width={width} height={22} align="center" fontFamily={FONT} fontSize={13} fontWeight={600} color="#d6e3ff">{label}</text>
  </frame>
)

const metric = (label, value, note, x, width = 320) => (
  <frame x={x} y={0} width={width} height={166} layout="none" background={SURFACE} radius={16}>
    <text x={24} y={22} width={width - 48} height={20} fontFamily={FONT} fontSize={12} fontWeight={600} letterSpacing={1} color={MUTED}>{label}</text>
    <text x={24} y={56} width={width - 48} height={54} fontFamily={FONT} fontSize={38} fontWeight={500} color={TEXT}>{value}</text>
    <text x={24} y={118} width={width - 48} height={24} fontFamily={FONT} fontSize={14} color={MUTED}>{note}</text>
  </frame>
)

const check = (label, y) => (
  <frame x={0} y={y} width={480} height={34} layout="none">
    <rect x={0} y={4} width={24} height={24} radius={12} fill={GREEN} />
    <text x={5} y={5} width={14} height={18} align="center" fontFamily={FONT} fontSize={14} fontWeight={700} color="#08441f">✓</text>
    <text x={38} y={5} width={430} height={22} fontFamily={FONT} fontSize={16} color={TEXT}>{label}</text>
  </frame>
)

export default async ({ project }) => {
  const p = await project({ dir: "neper-capabilities", size: `${W}x${H}`, fps: 30, background: BG })
  const forge = await p.add("forge.png")

  p.compose(
    <frame width={W} height={H} layout="none" background={BG} motion={enter}>
      <rect x={-150} y={-220} width={700} height={700} radius={350} fill={{kind:"radial",stops:[{offset:0,color:"#173f78",opacity:.78},{offset:1,color:BG,opacity:0}]}} />
      <frame x={84} y={78} width={74} height={74} layout="none" background={BLUE_DARK} radius={20}>
        <text x={0} y={4} width={74} height={68} align="center" fontFamily={FONT} fontSize={52} fontWeight={500} italic color="#ffffff">e</text>
      </frame>
      <text x={84} y={210} width={1100} height={82} fontFamily={FONT} fontSize={64} fontWeight={500} color={TEXT}>From prompt to proof.</text>
      <text x={88} y={306} width={1020} height={74} fontFamily={FONT} fontSize={26} lineHeight={36} color={MUTED}>The first general-purpose programming language optimized end to end for LLM-generated software.</text>
      <frame x={86} y={438} width={900} height={40} layout="none">{chip("MIT open source",0,160)}{chip("100% written in Neper",176,220)}{chip("Windows · Linux · macOS",412,240)}</frame>
      <text x={88} y={620} width={1080} height={28} fontFamily={MONO} fontSize={15} color={BLUE}>neper.dev  ·  deterministic by design</text>
    </frame>,
    { at: 0, dur: 3.5, name: "From prompt to proof" }
  )

  p.compose(
    <frame width={W} height={H} layout="none" background={BG} motion={enter}>
      <frame x={80} y={55} width={1120} height={138} layout="none">{title("01  /  PROMPT → NATIVE", "One short program. One tiny binary.", "No VM, no garbage collector, no LLVM runtime.")}</frame>
      <frame x={80} y={226} width={710} height={390} layout="none" background="#0c0e14" radius={18} shadow={{x:0,y:16,blur:36,color:"#00000088"}}>
        <rect x={0} y={0} width={710} height={52} radius={18} fill={HIGH} />
        <rect x={0} y={34} width={710} height={18} fill={HIGH} />
        <text x={24} y={16} width={650} height={22} fontFamily={MONO} fontSize={13} color={MUTED}>hello.e — neper</text>
        <text x={30} y={82} width={640} height={250} fontFamily={MONO} fontSize={20} lineHeight={34} color={TEXT}>{`use e.io\n\nfn main(args: []str) -> err {\n    try io.print("hello, neper\\n")\n    ret ok\n}\n\n$ neper run hello.e`}</text>
        <text x={30} y={342} width={650} height={30} fontFamily={MONO} fontSize={18} fontWeight={600} color={GREEN}>(34 msec, 6144 bytes)   hello, neper</text>
      </frame>
      <frame x={826} y={226} width={374} height={390} layout="none">
        <frame x={0} y={0} width={374} height={112} layout="none" background={BLUE_DARK} radius={18}><text x={24} y={20} width={326} height={50} fontFamily={FONT} fontSize={36} color="#ffffff">34 ms</text><text x={24} y={72} width={326} height={22} fontFamily={FONT} fontSize={14} color="#dae2ff">prompt to running program</text></frame>
        <frame x={0} y={130} width={374} height={112} layout="none" background={SURFACE} radius={18}><text x={24} y={20} width={326} height={50} fontFamily={FONT} fontSize={36} color={TEXT}>6,144 B</text><text x={24} y={72} width={326} height={22} fontFamily={FONT} fontSize={14} color={MUTED}>native executable</text></frame>
        <frame x={0} y={260} width={374} height={112} layout="none" background={GREEN_DARK} radius={18}><text x={24} y={20} width={326} height={50} fontFamily={FONT} fontSize={36} color={GREEN}>0 VM</text><text x={24} y={72} width={326} height={22} fontFamily={FONT} fontSize={14} color={GREEN}>ship the program, not the toolchain</text></frame>
      </frame>
    </frame>,
    { at: 3.5, dur: 4.5, name: "Native build" }
  )

  p.compose(
    <frame width={W} height={H} layout="none" background={BG} motion={enter}>
      <frame x={80} y={58} width={1120} height={138} layout="none">{title("02  /  ULTRA BY DESIGN", "One million lines. Under one second.", "Compile at thought speed, then keep only the bits the program can reach.")}</frame>
      <frame x={80} y={238} width={1120} height={220} layout="none">{metric("THROUGHPUT","1M+ LOC","per second, per core",0,354)}{metric("REBUILD","< 1 sec","whole-project target",383,354)}{metric("DEAD WEIGHT","0 bytes","extreme dead-code elimination",766,354)}</frame>
      <frame x={80} y={506} width={1120} height={90} layout="none" background={SURFACE} radius={16}>
        <text x={24} y={18} width={1000} height={22} fontFamily={FONT} fontSize={13} fontWeight={600} color={MUTED}>WHOLE-PROJECT BUILD</text>
        <rect x={24} y={52} width={1072} height={10} radius={5} fill="#39475f" />
        <rect x={24} y={52} width={1010} height={10} radius={5} fill={BLUE} animate={[{property:"scaleX",from:0,to:1,at:0,duration:1.3,easing:"house"}]} />
      </frame>
      <text x={80} y={630} width={1120} height={24} fontFamily={MONO} fontSize={14} color={COPPER}>direct emitter · own linker · reachable code only · no LLVM</text>
    </frame>,
    { at: 8, dur: 4, name: "Ultra performance" }
  )

  p.compose(
    <frame width={W} height={H} layout="none" background={BG} motion={enter}>
      <frame x={80} y={55} width={1120} height={138} layout="none">{title("03  /  ONE MODULE, EVERY PROCESSOR", "Write once. Step on CPU. Launch on GPU.", "The same typed kernel targets CPU, Vulkan, or CUDA without changing languages.")}</frame>
      <frame x={80} y={224} width={650} height={382} layout="none" background="#0c0e14" radius={18}>
        <text x={28} y={32} width={590} height={300} fontFamily={MONO} fontSize={18} lineHeight={31} color={TEXT}>{`use e.gpu\n\n@gpu(256)\nfn saxpy(a: f32, x: []const f32, y: []f32) {\n    let i = usize(gpu.gid.x)\n    if i < x.len { y[i] = a*x[i] + y[i] }\n}\n\ngpu.launch[saxpy](q, grid, 2.0, dx, dy)`}</text>
      </frame>
      <frame x={774} y={224} width={426} height={382} layout="none">
        <frame x={0} y={0} width={426} height={102} layout="none" background={BLUE_DARK} radius={18}><text x={24} y={24} width={120} height={42} fontFamily={FONT} fontSize={28} color="#ffffff">CPU</text><text x={142} y={30} width={250} height={30} fontFamily={FONT} fontSize={15} color="#dae2ff">exact deterministic debugging</text></frame>
        <frame x={0} y={122} width={426} height={102} layout="none" background={SURFACE} radius={18}><text x={24} y={24} width={150} height={42} fontFamily={FONT} fontSize={28} color={BLUE}>Vulkan</text><text x={174} y={30} width={218} height={30} fontFamily={FONT} fontSize={15} color={MUTED}>portable GPU compute</text></frame>
        <frame x={0} y={244} width={426} height={102} layout="none" background={SURFACE} radius={18}><text x={24} y={24} width={150} height={42} fontFamily={FONT} fontSize={28} color={GREEN}>CUDA</text><text x={174} y={30} width={218} height={30} fontFamily={FONT} fontSize={15} color={MUTED}>native NVIDIA path</text></frame>
      </frame>
    </frame>,
    { at: 12, dur: 4.25, name: "CPU and GPU" }
  )

  p.compose(
    <frame width={W} height={H} layout="none" background={BG} motion={enter}>
      <text x={80} y={46} width={1120} height={28} fontFamily={FONT} fontSize={14} fontWeight={600} letterSpacing={1.2} color={BLUE}>04  /  NATIVE UI</text>
      <text x={80} y={82} width={1120} height={52} fontFamily={FONT} fontSize={40} fontWeight={500} color={TEXT}>112 controls. One coherent system.</text>
      <frame x={84} y={156} width={1112} height={500} layout="none" background={SURFACE} radius={20} shadow={{x:0,y:18,blur:44,color:"#00000099"}} animate={[{property:"scale",from:.965,to:1.01,at:0,duration:4,easing:"smooth"}]}>
        <media file={forge} x={18} y={18} width={1076} height={464} fit="contain" radius={14} />
      </frame>
    </frame>,
    { at: 16.25, dur: 4.5, name: "Neper Forge" }
  )

  p.compose(
    <frame width={W} height={H} layout="none" background={BG} motion={enter}>
      <frame x={80} y={55} width={1120} height={138} layout="none">{title("05  /  VERIFIED SOFTWARE", "Every change ends in evidence.", "The compiler connects intent, source, edits, tests, dependencies, and native artifacts.")}</frame>
      <frame x={80} y={225} width={560} height={390} layout="none" background={BLUE_DARK} radius={24}>
        <text x={34} y={28} width={480} height={32} fontFamily={FONT} fontSize={22} fontWeight={600} color="#ffffff">Verification receipt</text>
        <text x={34} y={70} width={470} height={22} fontFamily={MONO} fontSize={13} color="#dae2ff">sha256:7fc2a091…e44ba91e</text>
        <frame x={34} y={118} width={480} height={210} layout="none">{check("Snapshot is immutable",0)}{check("248 tests passed",46)}{check("0 unsafe boundaries",92)}{check("Stage 2 equals stage 3",138)}</frame>
        <text x={34} y={346} width={480} height={22} fontFamily={FONT} fontSize={13} color="#dae2ff">neper 0.9.0 · x64 · reproducible</text>
      </frame>
      <frame x={676} y={225} width={524} height={390} layout="none">
        <frame x={0} y={0} width={524} height={114} layout="none" background={SURFACE} radius={18}><text x={24} y={20} width={460} height={42} fontFamily={FONT} fontSize={30} color={TEXT}>26 LLM-native features</text><text x={24} y={72} width={460} height={22} fontFamily={FONT} fontSize={14} color={MUTED}>context · diagnostics · repairs · receipts</text></frame>
        <frame x={0} y={134} width={524} height={114} layout="none" background={SURFACE} radius={18}><text x={24} y={20} width={460} height={42} fontFamily={FONT} fontSize={30} color={TEXT}>7,963 functions</text><text x={24} y={72} width={460} height={22} fontFamily={FONT} fontSize={14} color={MUTED}>one ultra-rich standard library</text></frame>
        <frame x={0} y={268} width={524} height={114} layout="none" background={SURFACE} radius={18}><text x={24} y={20} width={460} height={42} fontFamily={FONT} fontSize={30} color={TEXT}>1,232 algorithms</text><text x={24} y={72} width={460} height={22} fontFamily={FONT} fontSize={14} color={MUTED}>versioned, fenced, fixture-driven</text></frame>
      </frame>
    </frame>,
    { at: 20.75, dur: 4.5, name: "Verification proof" }
  )

  p.compose(
    <frame width={W} height={H} layout="none" background={BG} motion={{enter:{from:{scale:.94,opacity:0},duration:.5,easing:"house"}}}>
      <rect x={-120} y={-280} width={800} height={800} radius={400} fill={{kind:"radial",stops:[{offset:0,color:"#173f78",opacity:.8},{offset:1,color:BG,opacity:0}]}} />
      <frame x={603} y={104} width={74} height={74} layout="none" background={BLUE_DARK} radius={20}><text x={0} y={4} width={74} height={68} align="center" fontFamily={FONT} fontSize={52} fontWeight={500} italic color="#ffffff">e</text></frame>
      <text x={80} y={228} width={1120} height={78} align="center" fontFamily={FONT} fontSize={54} fontWeight={500} color={TEXT}>Build what models can prove.</text>
      <text x={160} y={330} width={960} height={40} align="center" fontFamily={FONT} fontSize={22} color={MUTED}>MIT open source · 100% Neper · multiplatform</text>
      <frame x={281} y={424} width={718} height={40} layout="none">{chip("github.com/nebosa-company/neper",0,342)}{chip("discord.gg/AdRneEsbCu",360,258)}</frame>
      <text x={80} y={620} width={1120} height={24} align="center" fontFamily={MONO} fontSize={14} color={BLUE}>neper — from prompt to proof</text>
    </frame>,
    { at: 25.25, dur: 3.25, name: "Close" }
  )

  await p.frame(1.8, "renders/neper-capabilities-poster.png")
  await p.render("renders/neper-capabilities.mp4", { bitrate: 5000000, concurrency: 4 })
}
