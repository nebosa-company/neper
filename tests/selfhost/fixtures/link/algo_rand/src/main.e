// Each generator here is a named published algorithm, so the only thing worth
// checking is that its stream is that algorithm's stream and not a near miss. Every
// expected value below comes from a separate implementation of the reference: PCG
// `setseq_64_rxs_m_xs_64`, xoshiro256**, and MT19937 with `init_genrand` seeding.
// D92 records the choice of variant for each name.

use e.algo.rand
use e.mem

error Failed

fn main(a: *mem.Arena, args: []str) -> err {
    // PCG, seeded the way the reference test does.
    var p = rand.pcg64(42u64, 54u64)
    if rand.pcg64_next(&p) != 16270310837369308859u64 { ret Failed }
    if rand.pcg64_next(&p) != 7310394323356280452u64 { ret Failed }
    if rand.pcg64_next(&p) != 14358865894078177398u64 { ret Failed }
    if rand.pcg64_next(&p) != 11430022384407591164u64 { ret Failed }
    if rand.pcg64_next(&p) != 16026402467362515374u64 { ret Failed }
    if rand.pcg64_next(&p) != 2755291261097131045u64 { ret Failed }
    if rand.pcg64_next(&p) != 18360926800957773746u64 { ret Failed }
    if rand.pcg64_next(&p) != 11823633708181627575u64 { ret Failed }
    if rand.pcg64_next(&p) != 2623160854467839973u64 { ret Failed }
    if rand.pcg64_next(&p) != 11646537823097761623u64 { ret Failed }
    if rand.pcg64_next(&p) != 1010030192253667823u64 { ret Failed }
    if rand.pcg64_next(&p) != 3478420626757013970u64 { ret Failed }
    if rand.pcg64_next(&p) != 14367304472197368549u64 { ret Failed }
    if rand.pcg64_next(&p) != 2460530239090633079u64 { ret Failed }
    if rand.pcg64_next(&p) != 7837261542341456869u64 { ret Failed }
    if rand.pcg64_next(&p) != 16003047387846457489u64 { ret Failed }
    if rand.pcg64_next(&p) != 6615981487653394329u64 { ret Failed }
    if rand.pcg64_next(&p) != 6488982601606920016u64 { ret Failed }
    if rand.pcg64_next(&p) != 3010332869272215069u64 { ret Failed }
    if rand.pcg64_next(&p) != 8858837538201923378u64 { ret Failed }
    if rand.pcg64_next(&p) != 1362602522209518528u64 { ret Failed }
    if rand.pcg64_next(&p) != 14787804551630716903u64 { ret Failed }
    if rand.pcg64_next(&p) != 3760812761212022359u64 { ret Failed }
    if rand.pcg64_next(&p) != 4018847720723564373u64 { ret Failed }
    if rand.pcg64_next(&p) != 18086893862739763687u64 { ret Failed }
    if rand.pcg64_next(&p) != 17166471194887899714u64 { ret Failed }
    if rand.pcg64_next(&p) != 160535777249015351u64 { ret Failed }
    if rand.pcg64_next(&p) != 11867959906922149469u64 { ret Failed }
    if rand.pcg64_next(&p) != 6266673149084992599u64 { ret Failed }
    if rand.pcg64_next(&p) != 12651260015060155116u64 { ret Failed }
    if rand.pcg64_next(&p) != 11798748940297657634u64 { ret Failed }
    if rand.pcg64_next(&p) != 17663791427609582262u64 { ret Failed }

    // A zero seed and a zero stream are ordinary inputs, not a special case.
    var p2 = rand.pcg64(0u64, 0u64)
    if rand.pcg64_next(&p2) != 17952179573506161629u64 { ret Failed }
    if rand.pcg64_next(&p2) != 16744828303690364247u64 { ret Failed }
    if rand.pcg64_next(&p2) != 8781261625613687140u64 { ret Failed }
    if rand.pcg64_next(&p2) != 10648084260111100392u64 { ret Failed }
    if rand.pcg64_next(&p2) != 9869280887118012696u64 { ret Failed }
    if rand.pcg64_next(&p2) != 262797565944218772u64 { ret Failed }
    if rand.pcg64_next(&p2) != 14177166670544307807u64 { ret Failed }
    if rand.pcg64_next(&p2) != 7197306614106581902u64 { ret Failed }

    // Two streams from one seed are different sequences; that is what the
    // stream selector is for.
    var stream_one = rand.pcg64(99u64, 1u64)
    var stream_two = rand.pcg64(99u64, 2u64)
    if rand.pcg64_next(&stream_one) != 14072398658292306722u64 { ret Failed }
    if rand.pcg64_next(&stream_two) != 4460347947916033284u64 { ret Failed }
    if rand.pcg64_next(&stream_one) != 11814555569204804595u64 { ret Failed }
    if rand.pcg64_next(&stream_two) != 17375462837274371974u64 { ret Failed }
    if rand.pcg64_next(&stream_one) != 6530870516186388579u64 { ret Failed }
    if rand.pcg64_next(&stream_two) != 10414569938296113444u64 { ret Failed }
    if rand.pcg64_next(&stream_one) != 10809672162695689467u64 { ret Failed }
    if rand.pcg64_next(&stream_two) != 4509221078369057729u64 { ret Failed }

    // Bounded draws reject the values that would bias the low residues, so the
    // sequence they consume is not the same as an unbounded one.
    var pb = rand.pcg64(7u64, 1u64)
    if rand.pcg64_bounded(&pb, 1u64) != 0u64 { ret Failed }
    if rand.pcg64_bounded(&pb, 2u64) != 1u64 { ret Failed }
    if rand.pcg64_bounded(&pb, 6u64) != 4u64 { ret Failed }
    if rand.pcg64_bounded(&pb, 10u64) != 7u64 { ret Failed }
    if rand.pcg64_bounded(&pb, 1000u64) != 184u64 { ret Failed }
    if rand.pcg64_bounded(&pb, 3037000499u64) != 1397879110u64 { ret Failed }
    if rand.pcg64_bounded(&pb, 18446744073709551615u64) != 11100165177677767564u64 { ret Failed }
    if rand.pcg64_bounded(&pb, 0u64) != 0u64 { ret Failed }

    // The top 53 bits over 2**53, which lands on a double exactly.
    var pf = rand.pcg64(3u64, 9u64)
    if rand.pcg64_f64(&pf) != 0.23177527869266967f64 { ret Failed }
    if rand.pcg64_f64(&pf) != 0.14627631161393562f64 { ret Failed }
    if rand.pcg64_f64(&pf) != 0.41739629899852326f64 { ret Failed }
    if rand.pcg64_f64(&pf) != 0.67322956679245904f64 { ret Failed }
    if rand.pcg64_f64(&pf) != 0.83606831332076081f64 { ret Failed }
    if rand.pcg64_f64(&pf) != 0.40264205828967925f64 { ret Failed }

    // xoshiro256**. The four words are the state itself.
    var seed: [4]u64 = zero
    seed[0usize] = 1u64
    seed[1usize] = 2u64
    seed[2usize] = 3u64
    seed[3usize] = 4u64
    var x = rand.xoshiro256(seed)
    if rand.xoshiro256_next(&x) != 11520u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 0u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 1509978240u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 1215971899390074240u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 1216172134540287360u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 607988272756665600u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 16172922978634559625u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 8476171486693032832u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 10595114339597558777u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 2904607092377533576u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 14472116193441429536u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 1266835380287703300u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 13063346333101044364u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 10781165923750339612u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 16528717425338217767u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 15524255879139051068u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 1619207689294935088u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 4087387419851923072u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 8826159522108219u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 12045626803839186140u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 11775070433031778569u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 11601369151438517687u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 17121876937238016452u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 3906761529340364028u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 7540380926365142056u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 1258907133428272883u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 13693050709007155469u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 10602646324252674653u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 11472893300548746075u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 18255046607807502600u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 7582222165988406339u64 { ret Failed }
    if rand.xoshiro256_next(&x) != 1715322903843008753u64 { ret Failed }

    // An all-zero state is the one this generator cannot leave, so it is
    // replaced rather than accepted: the stream below is not all zeros.
    var empty: [4]u64 = zero
    var z = rand.xoshiro256(empty)
    if rand.xoshiro256_next(&z) != 12992990478997550358u64 { ret Failed }
    if rand.xoshiro256_next(&z) != 11168005641907819923u64 { ret Failed }
    if rand.xoshiro256_next(&z) != 3255846277966946507u64 { ret Failed }
    if rand.xoshiro256_next(&z) != 10530155880730433916u64 { ret Failed }
    if rand.xoshiro256_next(&z) != 14254680902416795501u64 { ret Failed }
    if rand.xoshiro256_next(&z) != 2407289117002610596u64 { ret Failed }

    seed[0usize] = 9u64
    seed[1usize] = 8u64
    seed[2usize] = 7u64
    seed[3usize] = 6u64
    var xb = rand.xoshiro256(seed)
    if rand.xoshiro256_bounded(&xb, 1u64) != 0u64 { ret Failed }
    if rand.xoshiro256_bounded(&xb, 3u64) != 0u64 { ret Failed }
    if rand.xoshiro256_bounded(&xb, 7u64) != 2u64 { ret Failed }
    if rand.xoshiro256_bounded(&xb, 100u64) != 20u64 { ret Failed }
    if rand.xoshiro256_bounded(&xb, 65536u64) != 5760u64 { ret Failed }
    if rand.xoshiro256_bounded(&xb, 18446744073709551615u64) != 1419230722612170816u64 { ret Failed }
    if rand.xoshiro256_bounded(&xb, 0u64) != 0u64 { ret Failed }
    seed[0usize] = 5u64
    seed[1usize] = 5u64
    seed[2usize] = 5u64
    seed[3usize] = 5u64
    var xf = rand.xoshiro256(seed)
    if rand.xoshiro256_f64(&xf) != 1.5543122344752192e-15f64 { ret Failed }
    if rand.xoshiro256_f64(&xf) != 1.5543122344752192e-15f64 { ret Failed }
    if rand.xoshiro256_f64(&xf) != 2.0463630789890885e-10f64 { ret Failed }
    if rand.xoshiro256_f64(&xf) != 2.0463786221114333e-10f64 { ret Failed }
    if rand.xoshiro256_f64(&xf) != 0.054958462715148926f64 { ret Failed }
    if rand.xoshiro256_f64(&xf) != 0.054958567488938792f64 { ret Failed }

    // MT19937 from 5489, whose first outputs are the reference implementation's
    // own published test vector.
    var m = rand.mt19937(5489u32)
    if rand.mt19937_next(&m) != 3499211612u32 { ret Failed }
    if rand.mt19937_next(&m) != 581869302u32 { ret Failed }
    if rand.mt19937_next(&m) != 3890346734u32 { ret Failed }
    if rand.mt19937_next(&m) != 3586334585u32 { ret Failed }
    if rand.mt19937_next(&m) != 545404204u32 { ret Failed }
    if rand.mt19937_next(&m) != 4161255391u32 { ret Failed }
    if rand.mt19937_next(&m) != 3922919429u32 { ret Failed }
    if rand.mt19937_next(&m) != 949333985u32 { ret Failed }
    if rand.mt19937_next(&m) != 2715962298u32 { ret Failed }
    if rand.mt19937_next(&m) != 1323567403u32 { ret Failed }
    if rand.mt19937_next(&m) != 418932835u32 { ret Failed }
    if rand.mt19937_next(&m) != 2350294565u32 { ret Failed }
    if rand.mt19937_next(&m) != 1196140740u32 { ret Failed }
    if rand.mt19937_next(&m) != 809094426u32 { ret Failed }
    if rand.mt19937_next(&m) != 2348838239u32 { ret Failed }
    if rand.mt19937_next(&m) != 4264392720u32 { ret Failed }
    if rand.mt19937_next(&m) != 4112460519u32 { ret Failed }
    if rand.mt19937_next(&m) != 4279768804u32 { ret Failed }
    if rand.mt19937_next(&m) != 4144164697u32 { ret Failed }
    if rand.mt19937_next(&m) != 4156218106u32 { ret Failed }
    if rand.mt19937_next(&m) != 676943009u32 { ret Failed }
    if rand.mt19937_next(&m) != 3117454609u32 { ret Failed }
    if rand.mt19937_next(&m) != 4168664243u32 { ret Failed }
    if rand.mt19937_next(&m) != 4213834039u32 { ret Failed }
    if rand.mt19937_next(&m) != 4111000746u32 { ret Failed }
    if rand.mt19937_next(&m) != 471852626u32 { ret Failed }
    if rand.mt19937_next(&m) != 2084672536u32 { ret Failed }
    if rand.mt19937_next(&m) != 3427838553u32 { ret Failed }
    if rand.mt19937_next(&m) != 3437178460u32 { ret Failed }
    if rand.mt19937_next(&m) != 1275731771u32 { ret Failed }
    if rand.mt19937_next(&m) != 609397212u32 { ret Failed }
    if rand.mt19937_next(&m) != 20544909u32 { ret Failed }

    // Past 624 draws the block is twisted again, and past 1248 a third time, so
    // this reaches the path that reads state the same pass already rewrote.
    var m2 = rand.mt19937(1u32)
    var skip = 0usize
    while skip < 1300usize {
        let ignored = rand.mt19937_next(&m2)
        skip += 1usize
    }
    if rand.mt19937_next(&m2) != 1533567918u32 { ret Failed }
    if rand.mt19937_next(&m2) != 3866642891u32 { ret Failed }
    if rand.mt19937_next(&m2) != 464137042u32 { ret Failed }
    if rand.mt19937_next(&m2) != 3836764460u32 { ret Failed }
    if rand.mt19937_next(&m2) != 3382509376u32 { ret Failed }
    if rand.mt19937_next(&m2) != 2578611749u32 { ret Failed }
    if rand.mt19937_next(&m2) != 457774255u32 { ret Failed }
    if rand.mt19937_next(&m2) != 3367360969u32 { ret Failed }
    ret ok
}
