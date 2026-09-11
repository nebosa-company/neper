// `e.math`'s exact set, which section 11 says is one value on every target: `sqrt` as the
// instruction, and `abs`, `min`, `max`, `floor`, `ceil`, `round`, `trunc` and `copysign` as
// source. Exact means bit-for-bit, so the answers are compared through their bits where a
// sign could hide -- `-0` and `+0` compare equal as values and are not the same answer.

use e.mem
use e.os
use e.math

fn bits64(x: f64) -> u64 { ret mem.bitcast[u64](x) }
fn bits32(x: f32) -> u32 { ret mem.bitcast[u32](x) }
fn negative_zero() -> f64 { ret mem.bitcast[f64](9223372036854775808u64) }
fn quiet_nan() -> f64 { ret 0.0f64 / 0.0f64 }
fn infinity() -> f64 { ret 1.0f64 / 0.0f64 }

fn main(a: *mem.Arena) -> err {
    // --- sqrt is the instruction: correctly rounded, on both widths, with the special values
    // section 11 fixes. `sqrt(2)` is checked by its bits, which is what correctly rounded means.
    if math.sqrt[f64](4.0f64) != 2.0f64 { os.exit(10i32) }
    if bits64(math.sqrt[f64](2.0f64)) != 4609047870845172685u64 { os.exit(11i32) }
    if math.sqrt[f32](9.0f32) != 3.0f32 { os.exit(12i32) }
    if bits32(math.sqrt[f32](2.0f32)) != 1068827891u32 { os.exit(13i32) }
    let root_of_less = math.sqrt[f64](-1.0f64)
    if root_of_less == root_of_less { os.exit(14i32) }
    if bits64(math.sqrt[f64](negative_zero())) != bits64(negative_zero()) { os.exit(15i32) }
    if math.sqrt[f64](infinity()) != infinity() { os.exit(16i32) }
    if math.sqrt[f64](0.0f64) != 0.0f64 { os.exit(17i32) }
    // Through a generic, where the width is a type parameter until the instance.
    if root_of[f64](16.0f64) != 4.0f64 { os.exit(18i32) }
    if root_of[f32](16.0f32) != 4.0f32 { os.exit(19i32) }

    // --- rsqrt: 1 / sqrt, within a ULP.
    if math.rsqrt[f64](4.0f64) != 0.5f64 { os.exit(20i32) }
    if math.rsqrt[f32](0.25f32) != 2.0f32 { os.exit(21i32) }

    // --- abs clears the sign and nothing else; copysign moves it, NaN included.
    if math.abs[f64](-3.5f64) != 3.5f64 { os.exit(30i32) }
    if math.abs[f32](-3.5f32) != 3.5f32 { os.exit(31i32) }
    if bits64(math.abs[f64](negative_zero())) != bits64(0.0f64) { os.exit(32i32) }
    if math.copysign[f64](3.0f64, -1.0f64) != -3.0f64 { os.exit(33i32) }
    if math.copysign[f64](-3.0f64, 1.0f64) != 3.0f64 { os.exit(34i32) }
    if bits64(math.copysign[f64](0.0f64, -1.0f64)) != bits64(negative_zero()) { os.exit(35i32) }
    if math.copysign[f32](2.0f32, -0.0f32) != -2.0f32 { os.exit(36i32) }
    let signed_nan = math.copysign[f64](quiet_nan(), -1.0f64)
    if (bits64(signed_nan) >> 63u32) != 1u64 { os.exit(37i32) }

    // --- min and max are IEEE 754-2019 minimum and maximum: a NaN wins, and the zeros are
    // ordered with `-0` below `+0`.
    if math.min[f64](1.0f64, 2.0f64) != 1.0f64 { os.exit(40i32) }
    if math.max[f64](1.0f64, 2.0f64) != 2.0f64 { os.exit(41i32) }
    if math.min[f32](-1.0f32, -2.0f32) != -2.0f32 { os.exit(42i32) }
    let min_with_nan = math.min[f64](1.0f64, quiet_nan())
    if min_with_nan == min_with_nan { os.exit(43i32) }
    let max_with_nan = math.max[f64](quiet_nan(), 1.0f64)
    if max_with_nan == max_with_nan { os.exit(44i32) }
    if bits64(math.min[f64](0.0f64, negative_zero())) != bits64(negative_zero()) { os.exit(45i32) }
    if bits64(math.min[f64](negative_zero(), 0.0f64)) != bits64(negative_zero()) { os.exit(46i32) }
    if bits64(math.max[f64](0.0f64, negative_zero())) != bits64(0.0f64) { os.exit(47i32) }
    if bits64(math.max[f64](negative_zero(), 0.0f64)) != bits64(0.0f64) { os.exit(48i32) }

    // --- The four rounders, on the values where they differ from each other.
    if math.trunc[f64](2.7f64) != 2.0f64 { os.exit(50i32) }
    if math.trunc[f64](-2.7f64) != -2.0f64 { os.exit(51i32) }
    if math.floor[f64](2.7f64) != 2.0f64 { os.exit(52i32) }
    if math.floor[f64](-2.7f64) != -3.0f64 { os.exit(53i32) }
    if math.ceil[f64](2.2f64) != 3.0f64 { os.exit(54i32) }
    if math.ceil[f64](-2.2f64) != -2.0f64 { os.exit(55i32) }
    // Ties to even: 2.5 down, 3.5 up, -2.5 up toward zero, and a value just under the half down.
    if math.round[f64](2.5f64) != 2.0f64 { os.exit(56i32) }
    if math.round[f64](3.5f64) != 4.0f64 { os.exit(57i32) }
    if math.round[f64](-2.5f64) != -2.0f64 { os.exit(58i32) }
    if math.round[f64](-3.5f64) != -4.0f64 { os.exit(59i32) }
    if math.round[f64](2.4999999f64) != 2.0f64 { os.exit(60i32) }
    if math.round[f64](2.5000001f64) != 3.0f64 { os.exit(61i32) }
    if math.round[f64](0.5f64) != 0.0f64 { os.exit(62i32) }
    if math.round[f64](1.5f64) != 2.0f64 { os.exit(63i32) }
    // The sign of a zero result is the sign of the input.
    if bits64(math.trunc[f64](-0.5f64)) != bits64(negative_zero()) { os.exit(64i32) }
    if bits64(math.ceil[f64](-0.5f64)) != bits64(negative_zero()) { os.exit(65i32) }
    if bits64(math.round[f64](-0.4f64)) != bits64(negative_zero()) { os.exit(66i32) }
    if bits64(math.floor[f64](0.5f64)) != bits64(0.0f64) { os.exit(67i32) }
    // Already integral, infinite or NaN: the value is its own answer.
    if math.floor[f64](3.0f64) != 3.0f64 { os.exit(68i32) }
    if math.round[f64](4503599627370497.0f64) != 4503599627370497.0f64 { os.exit(69i32) }
    if math.trunc[f64](infinity()) != infinity() { os.exit(70i32) }
    let rounded_nan = math.round[f64](quiet_nan())
    if rounded_nan == rounded_nan { os.exit(71i32) }
    // The same four in single precision, where the threshold is 2^23.
    if math.floor[f32](-2.5f32) != -3.0f32 { os.exit(72i32) }
    if math.ceil[f32](2.5f32) != 3.0f32 { os.exit(73i32) }
    if math.round[f32](2.5f32) != 2.0f32 { os.exit(74i32) }
    if math.trunc[f32](-2.5f32) != -2.0f32 { os.exit(75i32) }
    if math.round[f32](8388609.0f32) != 8388609.0f32 { os.exit(76i32) }

    // --- fma: one rounding, checked against the exact rational `a * b + c` rounded once, which
    // Python's `Fraction` computes with no float in the way. The hand cases are the ones a
    // twice-rounding version gets wrong -- a tie at half an ulp, a cancellation that exposes
    // the product's low bits, an addend at the rounding position -- and the special values;
    // the `naive differs` cases are random ones where `a * b + c` in two roundings disagrees.
    // The special values, first.
    let fma_nan = math.fma[f64](quiet_nan(), 1.0f64, 1.0f64)
    if fma_nan == fma_nan { os.exit(180i32) }
    let inf_times_zero = math.fma[f64](infinity(), 0.0f64, 1.0f64)
    if inf_times_zero == inf_times_zero { os.exit(181i32) }
    let inf_minus_inf = math.fma[f64](infinity(), 1.0f64, -infinity())
    if inf_minus_inf == inf_minus_inf { os.exit(182i32) }
    if math.fma[f64](infinity(), -2.0f64, 5.0f64) != -infinity() { os.exit(183i32) }
    if math.fma[f64](2.0f64, 3.0f64, -infinity()) != -infinity() { os.exit(184i32) }
    if math.fma[f64](0.0f64, 5.0f64, 7.0f64) != 7.0f64 { os.exit(185i32) }
    if bits64(math.fma[f64](negative_zero(), 5.0f64, negative_zero())) != bits64(negative_zero()) { os.exit(186i32) }
    if bits64(math.fma[f64](negative_zero(), 5.0f64, 0.0f64)) != bits64(0.0f64) { os.exit(187i32) }
    // Through a generic.
    if fused[f64](2.0f64, 3.0f64, 4.0f64) != 10.0f64 { os.exit(188i32) }
    if fused[f32](2.0f32, 3.0f32, 4.0f32) != 10.0f32 { os.exit(189i32) }
    // plain
    if bits64(math.fma[f64](f64_of(4611686018427387904u64), f64_of(4613937818241073152u64), f64_of(4616189618054758400u64))) != 4621819117588971520u64 { os.exit(200i32) }
    // exact cancellation
    if bits64(math.fma[f64](f64_of(4607182418800017408u64), f64_of(4607182418800017408u64), f64_of(13830554455654793216u64))) != 0u64 { os.exit(201i32) }
    // overflow
    if bits64(math.fma[f64](f64_of(9214871658872686752u64), f64_of(4621819117588971520u64), f64_of(0u64))) != 9218868437227405312u64 { os.exit(202i32) }
    // underflow to subnormal or zero
    if bits64(math.fma[f64](f64_of(2213095475689254516u64), f64_of(2213095475689254516u64), f64_of(0u64))) != 2024u64 { os.exit(203i32) }
    // subnormal sum
    if bits64(math.fma[f64](f64_of(103582791429521408u64), f64_of(4156822456062967808u64), f64_of(1u64))) != 1u64 { os.exit(204i32) }
    // product bits below the sum
    if bits64(math.fma[f64](f64_of(4607182418800017409u64), f64_of(4607182418800017409u64), f64_of(13830554455654793216u64))) != 4377498837804122112u64 { os.exit(205i32) }
    // addend at the rounding position
    if bits64(math.fma[f64](f64_of(4845873199050653696u64), f64_of(4607182418800017409u64), f64_of(4607182418800017408u64))) != 4845873199050653698u64 { os.exit(206i32) }
    // large magnitudes
    if bits64(math.fma[f64](f64_of(7598952565167317594u64), f64_of(7598952565167317594u64), f64_of(18318360957983683996u64))) != 9218868437227405312u64 { os.exit(207i32) }
    // subnormal operands
    if bits64(math.fma[f64](f64_of(4613937818241073152u64), f64_of(1u64), f64_of(1u64))) != 4u64 { os.exit(208i32) }
    // tiny product against one
    if bits64(math.fma[f64](f64_of(4607182418800017408u64), f64_of(4336966441157787648u64), f64_of(4607182418800017408u64))) != 4607182418800017408u64 { os.exit(209i32) }
    // tie: half ulp exactly, rounds to even
    if bits64(math.fma[f64](f64_of(4607182418800017408u64), f64_of(4368491638549381120u64), f64_of(4607182418800017408u64))) != 4607182418800017408u64 { os.exit(210i32) }
    // above half ulp
    if bits64(math.fma[f64](f64_of(4607182418800017408u64), f64_of(4370743438363066368u64), f64_of(4607182418800017408u64))) != 4607182418800017409u64 { os.exit(211i32) }
    // subtract exactly half ulp, ties to even below one
    if bits64(math.fma[f64](f64_of(13830554455654793216u64), f64_of(4368491638549381120u64), f64_of(4607182418800017408u64))) != 4607182418800017407u64 { os.exit(212i32) }
    // cancellation exposes low bits
    if bits64(math.fma[f64](f64_of(4607182418800017408u64), f64_of(4363988038922010624u64), f64_of(13830554455654793215u64))) != 13830554455654793214u64 { os.exit(213i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(4617048811928003592u64), f64_of(13768630915333749376u64), f64_of(4556902261404363968u64))) != 4545876461268018597u64 { os.exit(214i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(13874048898622247776u64), f64_of(13910448313481805760u64), f64_of(4659477930210240220u64))) != 4730771232220837360u64 { os.exit(215i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(13882732492716627806u64), f64_of(13747656327621120224u64), f64_of(13761787234453776024u64))) != 4576826741527473168u64 { os.exit(216i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(4684659168489094946u64), f64_of(13806534885699865080u64), f64_of(4498856533909968028u64))) != 13884609790820418057u64 { os.exit(217i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(13844735754190192922u64), f64_of(13866753679826353116u64), f64_of(13850334650441507920u64))) != 4657539335187510432u64 { os.exit(218i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(13960656859974830264u64), f64_of(4605605943412115332u64), f64_of(13841340986144527864u64))) != 13959168244044612874u64 { os.exit(219i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(13832585496167086050u64), f64_of(13970713901038750604u64), f64_of(13954959631941918388u64))) != 4749163003963631384u64 { os.exit(220i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(4744126926461503920u64), f64_of(13740172290660842716u64), f64_of(4607953275148547248u64))) != 13877203491238221839u64 { os.exit(221i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(13735335398292160688u64), f64_of(13906337324805447880u64), f64_of(13731683579304261592u64))) != 4587801797353637969u64 { os.exit(222i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(4500965792896198144u64), f64_of(13920659245310037290u64), f64_of(13776422079279001484u64))) != 13814473653827658522u64 { os.exit(223i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(4707791710258779274u64), f64_of(13897818782864475038u64), f64_of(4725829680136516216u64))) != 13998520743002109021u64 { os.exit(224i32) }
    // naive differs
    if bits64(math.fma[f64](f64_of(13783487843120088960u64), f64_of(13964280021811657914u64), f64_of(4694865578263370744u64))) != 4699012904205304813u64 { os.exit(225i32) }
    // random
    if bits64(math.fma[f64](f64_of(13874556955191545166u64), f64_of(4643379848980139336u64), f64_of(13916802585129545752u64))) != 13918870652755004994u64 { os.exit(226i32) }
    // random
    if bits64(math.fma[f64](f64_of(4641220151379453576u64), f64_of(13867998616511593770u64), f64_of(4688950293487579456u64))) != 4687348094158480837u64 { os.exit(227i32) }
    // random
    if bits64(math.fma[f64](f64_of(4645494217985076004u64), f64_of(4642729242780375024u64), f64_of(13917916684465866086u64))) != 13917113752917837134u64 { os.exit(228i32) }
    // random
    if bits64(math.fma[f64](f64_of(13853516987712067856u64), f64_of(13852060242756406080u64), f64_of(4696364855058702538u64))) != 4696373433324713070u64 { os.exit(229i32) }
    // random
    if bits64(math.fma[f64](f64_of(13873628587672183090u64), f64_of(13871549641837286830u64), f64_of(13894810844243261568u64))) != 4691156075933039028u64 { os.exit(230i32) }
    // random
    if bits64(math.fma[f64](f64_of(4646056608408937612u64), f64_of(13869625168858274110u64), f64_of(13902795447091819376u64))) != 13911111949925179055u64 { os.exit(231i32) }
    // random
    if bits64(math.fma[f64](f64_of(4647911315934609782u64), f64_of(4651889448360563562u64), f64_of(4681481436902606880u64))) != 4693618780096267940u64 { os.exit(232i32) }
    // random
    if bits64(math.fma[f64](f64_of(13868705761820376896u64), f64_of(13873868981552512456u64), f64_of(13901041625826131040u64))) != 4688100251454450334u64 { os.exit(233i32) }
    // random
    if bits64(math.fma[f64](f64_of(13869482836202102242u64), f64_of(13874034172526867555u64), f64_of(4668502747891206016u64))) != 4690095071307654030u64 { os.exit(234i32) }
    // random
    if bits64(math.fma[f64](f64_of(4651912472147715812u64), f64_of(4651901174504050818u64), f64_of(13910387772081284500u64))) != 4694698072802632618u64 { os.exit(235i32) }
    // random
    if bits64(math.fma[f64](f64_of(4650539324978441390u64), f64_of(4650785286208711400u64), f64_of(13918927344233033681u64))) != 13907195874484636428u64 { os.exit(236i32) }
    // random
    if bits64(math.fma[f64](f64_of(13873790716861514952u64), f64_of(4647415261965599560u64), f64_of(13915299830836190124u64))) != 13919195222058989327u64 { os.exit(237i32) }
    // random
    if bits64(math.fma[f64](f64_of(13867021172269225066u64), f64_of(4641477733902302312u64), f64_of(4688267697331554392u64))) != 4686292933379692772u64 { os.exit(238i32) }
    // random
    if bits64(math.fma[f64](f64_of(13869835418197069094u64), f64_of(13873397101018305393u64), f64_of(13911747736300857448u64))) != 4679676673469956766u64 { os.exit(239i32) }
    // random
    if bits64(math.fma[f64](f64_of(13839813961526761472u64), f64_of(4649828432726476804u64), f64_of(13909890780944005944u64))) != 13909999967434452914u64 { os.exit(240i32) }
    // random
    if bits64(math.fma[f64](f64_of(13872581039891206574u64), f64_of(4651126988328100968u64), f64_of(4689982932644710476u64))) != 13911217485672731608u64 { os.exit(241i32) }
    // random
    if bits64(math.fma[f64](f64_of(13864231576420770888u64), f64_of(4646700899280016432u64), f64_of(13908372034156613564u64))) != 13911325198506032064u64 { os.exit(242i32) }
    // random
    if bits64(math.fma[f64](f64_of(13866294308381876272u64), f64_of(13873252285839018422u64), f64_of(13912911300135645854u64))) != 13907748255811213509u64 { os.exit(243i32) }
    // random
    if bits64(math.fma[f64](f64_of(13868252836030386266u64), f64_of(13867769929010482828u64), f64_of(13909603599583259984u64))) != 13904291763528316012u64 { os.exit(244i32) }
    // random
    if bits64(math.fma[f64](f64_of(4650949684669238328u64), f64_of(13871935831193547760u64), f64_of(13920007807680061626u64))) != 13922616442132619362u64 { os.exit(245i32) }
    // plain
    if bits32(math.fma[f32](f32_of(1073741824u32), f32_of(1077936128u32), f32_of(1082130432u32))) != 1092616192u32 { os.exit(246i32) }
    // cancel
    if bits32(math.fma[f32](f32_of(1065353216u32), f32_of(1065353216u32), f32_of(3212836864u32))) != 0u32 { os.exit(247i32) }
    // tie
    if bits32(math.fma[f32](f32_of(1065353216u32), f32_of(864026624u32), f32_of(1065353216u32))) != 1065353216u32 { os.exit(248i32) }
    // overflow
    if bits32(math.fma[f32](f32_of(2123789977u32), f32_of(1092616192u32), f32_of(0u32))) != 2139095040u32 { os.exit(249i32) }
    // underflow
    if bits32(math.fma[f32](f32_of(228737632u32), f32_of(228737632u32), f32_of(0u32))) != 0u32 { os.exit(250i32) }
    // subnormal
    if bits32(math.fma[f32](f32_of(1077936128u32), f32_of(1u32), f32_of(1u32))) != 4u32 { os.exit(251i32) }
    // naive differs
    if bits32(math.fma[f32](f32_of(3326283176u32), f32_of(1152825023u32), f32_of(3343207289u32))) != 3414923672u32 { os.exit(252i32) }
    // naive differs
    if bits32(math.fma[f32](f32_of(3237338430u32), f32_of(3341042792u32), f32_of(1040486356u32))) != 1218298739u32 { os.exit(253i32) }
    // naive differs
    if bits32(math.fma[f32](f32_of(3077119930u32), f32_of(3369196585u32), f32_of(898358674u32))) != 1086266214u32 { os.exit(254i32) }
    // naive differs
    if bits32(math.fma[f32](f32_of(1176548043u32), f32_of(959246085u32), f32_of(901255351u32))) != 1071193184u32 { os.exit(255i32) }
    // naive differs
    if bits32(math.fma[f32](f32_of(3108304580u32), f32_of(1233458520u32), f32_of(941449614u32))) != 3276589373u32 { os.exit(256i32) }
    // naive differs
    if bits32(math.fma[f32](f32_of(1159893265u32), f32_of(911875485u32), f32_of(3160020012u32))) != 3147768747u32 { os.exit(257i32) }
    // naive differs
    if bits32(math.fma[f32](f32_of(3390532202u32), f32_of(990595219u32), f32_of(1165140885u32))) != 3299722873u32 { os.exit(258i32) }
    // naive differs
    if bits32(math.fma[f32](f32_of(958620429u32), f32_of(1156000344u32), f32_of(3109569554u32))) != 1049849439u32 { os.exit(259i32) }
    ret ok
}

fn f64_of(bits: u64) -> f64 { ret mem.bitcast[f64](bits) }
fn f32_of(bits: u32) -> f32 { ret mem.bitcast[f32](bits) }

fn fused[F: type](a: F, b: F, c: F) -> F {
    ret math.fma[F](a, b, c)
}

fn root_of[F: type](x: F) -> F {
    ret math.sqrt[F](x)
}
