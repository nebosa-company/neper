// WebP (RFC 9649) both ways. Decoding takes the simple lossy and lossless layouts and
// the extended one: a VP8 key frame (RFC 6386 -- the boolean decoder, segments,
// coefficient tokens, dequantisation, the WHT and the exact integer IDCT, the ten
// subblock and four macroblock intra modes with the frame-edge rules, both loop
// filters) with an optional `ALPH` plane, or a VP8L image (transforms, colour cache,
// meta prefix codes, LZ77 with the distance map). Lossy chroma is upsampled with the
// triangle filter and converted with BT.601, so a lossy decode lands within a few
// steps of libwebp's; a lossless decode is exact. `inspect` reads the container and
// the first frame's header, counting `ANMF` frames; decoding more than the first
// frame is `Unsupported`, as the fence says, and `first_frame_only` is honoured.
// Dimensions are checked against the options before any plane is taken; a zero
// limit is no limit.
//
// Encoding writes lossless VP8L: no transforms, no cache, one prefix group whose
// four channel codes are flat eight-bit codes and whose distance code is empty, so
// every pixel costs 32 bits plus the header. It is exact and deterministic and it is
// the whole of what `lossless: true` promises; `lossless: false` (lossy, `quality`)
// is `Unsupported`. ponytail: a VP8 encoder is a rate-distortion search over modes
// and quantisers, a different project; predictors and LZ77 for the lossless writer
// would shrink files and can be added behind the same header.

use e.bytes
use e.io
use e.mem
use e.gfx.image

type DecodeOptions = struct { max_width: u32, max_height: u32, max_pixels: u64, first_frame_only: bool }
type EncodeOptions = struct { quality: f32, lossless: bool }
error Invalid
error Unsupported
error TooLarge

const READ_LIMIT: usize = 1073741824usize

fn kf_bmode_probs() -> str { ret "\xe7x0Ysqx\x98p\x98\xb3@~\xaav.F_\xafE\x8fPURH\x9bg8:\x0a\xab\xda\xbd\x11\x0d\x98\x90G\x0a&\xab\xd5\x90\"\x1ar\x1a\x11\xa3,\xc3\x15\x0a\xady\x18P\xc3\x1a>,@U\xaa.7\x13\x88\xa0!\xceG?\x14\x08rr\xd0\x0c\x09\xe2Q(\x0b`\xb6T\x1d\x10$\x86\xb7Y\x89bej\xa5\x94H\xbbd\x82\x9do KPBf\xa7cJ>(\xea\x80)5\x09\xb2\xf1\x8d\x1a\x08khO\x0c\x1b\xd9\xffW\x11\x07J+\x1a\x92I\xa61\x17\x9dA&i\xa034\x1fs\x80WDG,r3\x0f\xba\x17/)\x0en\xb6\xb7\x15\x11\xc2B-\x19f\xc5\xbd\x17\x12\x16XX\x93\x96*.-\xc4\xcd+a\xb7uU&#\xb3='5\xc8W\x1a\x15+\xe8\xab8\"3hrf\x1d]Mk6 \x1a3\x01Q+\x1f'\x1cU\xab:\xa5Zb@\"\x16t\xce\x17\"+\xa6ID\x19j\x16@\xab$\xe1r\"\x13\x15f\x84\xbc\x10L|>\x12N_U9203\xc1e#\x9f\xd7oY.o<\x94\x1f\xac\xdb\xe4\x15\x12opqMU\xb3\xff&xr(*\x01\xc4\xf5\xd1\x0a\x19mdP\x08+\x9a\x013\x1aGX+\x1d\x8c\xa6\xd5%+\x9a=?\x1e\x9bC-D\x01\xd1\x8eNN\x10\xff\x80\"\xc5\xab)(\x05f\xd3\xb7\x04\x01\xdd32\x11\xa8\xd1\xc0\x17\x19R}b*XhUu\xafR_T5Y\x80dqe-KO{/3\x80Q\xab\x019\x11\x05Gf95)1s\x15\x02\x0af\xff\xa6\x17\x06&!\x0dy9I\x1a\x01U)\x0aC\x8aMnZ/re\x1d\x10\x0aU\x80e\xc4\x1a9\x12\x0aff\xd5\"\x14+u\x14\x0f$\xa3\x80D\x01\x1a\x8a\x1f$\xab\x1b\xa6&,\xe5CW:\xa9Rs\x1a;\xb3?;Z\xb4;\xa6]I\x9a((\x15t\x8f\xd1\"'\xaf9.\x16\x18\x80\x016\x11%/\x0f\x10\xb7\"\xdf1-\xb7.\x11!\xb7\x06b\x0f \xb7A Is\x1c\x80\x17\x80\xcd(\x03\x09s3\xc0\x12\x06\xdfW%\x09s;M@\x15/h7,\xda\x0965\x82\xe2@ZF\xcd()\x17\x1a969p\xb8\x05)&\xa6\xd5\x1e\"\x1a\x85\x98t\x0a \x86K \x0c3\xc0\xff\xa0+3'\x135\xdd\x1ar I\xff\x1f\x09A\xea\x02\x0f\x01vIX\x1f#CfU7\xbaU8\x15\x17o;\xcd-%\xc07&F|If\x01\"bf=G%\"5\x1f\xf3\xc0E<G&Iw\x1c\xde%D-\x80\"\x01/\x0b\xf5\xab>\x11\x13F\x92U7>FK\x0f\x09\x09@\xff\xb8w\x10%+%\x9ad\xa3U\xa0\x01?\x09\\\x88\x1c@ \xc9UV\x06\x1c\x05@\xff\x19\xf8\x018\x08\x11\x84\x89\xff7t\x80:\x0f\x14R\x879\x1ay(\xa42\x1f\x89\x9a\x85\x19#\xda3g,\x83\x83{\x1f\x06\x9eV(@\x87\x94\xe0-\xb7\x80\x16\x1a\x11\x83\xf0\x9a\x0e\x01\xd1S\x0c\x0d6\xc0\xffD/\x1c-\x10\x15[@\xde\x07\x01\xc58\x15'\x9b<\x8a\x17f\xd5U\x1aUU\x80\x80 \x92\xab\x12\x0b\x07?\x90\xab\x04\x04\xf6#\x1b\x0a\x92\xae\xab\x0c\x1a\x80\xbeP#c\xb4P~6-U~/W\xb03)\x14 eK\x80\x8bv\x92t\x80U8)\x0f\xb0\xecU%\x09>\x92$\x13\x1e\xab\xffa\x1b\x14G\x1e\x11wv\xff\x11\x12\x8ae&<\x8a7F+\x1a\x8e\x8a-=>\xdb\x01Q\xbc@ )\x14u\x97\x8e\x14\x15\xa3p\x13\x0c=\xc3\x800\x04\x18" }
fn coeff_update_probs() -> str { ret "\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xb0\xf6\xff\xff\xff\xff\xff\xff\xff\xff\xff\xdf\xf1\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xf9\xfd\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf4\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xea\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf6\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xef\xfd\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf8\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xfb\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xfb\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xfd\xff\xfe\xff\xff\xff\xff\xff\xff\xfa\xff\xfe\xff\xfe\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xd9\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xe1\xfc\xf1\xfd\xff\xff\xfe\xff\xff\xff\xff\xea\xfa\xf1\xfa\xfd\xff\xfd\xfe\xff\xff\xff\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xdf\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xee\xfd\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xf8\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xf9\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf7\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xfa\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xba\xfb\xfa\xff\xff\xff\xff\xff\xff\xff\xff\xea\xfb\xf4\xfe\xff\xff\xff\xff\xff\xff\xff\xfb\xfb\xf3\xfd\xfe\xff\xfe\xff\xff\xff\xff\xff\xfd\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xec\xfd\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xfb\xfd\xfd\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf8\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfa\xfe\xfc\xfe\xff\xff\xff\xff\xff\xff\xff\xf8\xfe\xf9\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xf6\xfd\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xfc\xfe\xfb\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xfe\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xf8\xfe\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xff\xfe\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xfb\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xf5\xfb\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xfd\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfb\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xfc\xfd\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xff\xf9\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfd\xff\xff\xff\xff\xff\xff\xff\xff\xfa\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" }
fn default_coeff_probs() -> str { ret "\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\xfd\x88\xfe\xff\xe4\xdb\x80\x80\x80\x80\x80\xbd\x81\xf2\xff\xe3\xd5\xff\xdb\x80\x80\x80j~\xe3\xfc\xd6\xd1\xff\xff\x80\x80\x80\x01b\xf8\xff\xec\xe2\xff\xff\x80\x80\x80\xb5\x85\xee\xfe\xdd\xea\xff\x9a\x80\x80\x80N\x86\xca\xf7\xc6\xb4\xff\xdb\x80\x80\x80\x01\xb9\xf9\xff\xf3\xff\x80\x80\x80\x80\x80\xb8\x96\xf7\xff\xec\xe0\x80\x80\x80\x80\x80Mn\xd8\xff\xec\xe6\x80\x80\x80\x80\x80\x01e\xfb\xff\xf1\xff\x80\x80\x80\x80\x80\xaa\x8b\xf1\xfc\xec\xd1\xff\xff\x80\x80\x80%t\xc4\xf3\xe4\xff\xff\xff\x80\x80\x80\x01\xcc\xfe\xff\xf5\xff\x80\x80\x80\x80\x80\xcf\xa0\xfa\xff\xee\x80\x80\x80\x80\x80\x80fg\xe7\xff\xd3\xab\x80\x80\x80\x80\x80\x01\x98\xfc\xff\xf0\xff\x80\x80\x80\x80\x80\xb1\x87\xf3\xff\xea\xe1\x80\x80\x80\x80\x80P\x81\xd3\xff\xc2\xe0\x80\x80\x80\x80\x80\x01\x01\xff\x80\x80\x80\x80\x80\x80\x80\x80\xf6\x01\xff\x80\x80\x80\x80\x80\x80\x80\x80\xff\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\xc6#\xed\xdf\xc1\xbb\xa2\xa0\x91\x9b>\x83-\xc6\xdd\xac\xb0\xdc\x9d\xfc\xdd\x01D/\x92\xd0\x95\xa7\xdd\xa2\xff\xdf\x80\x01\x95\xf1\xff\xdd\xe0\xff\xff\x80\x80\x80\xb8\x8d\xea\xfd\xde\xdc\xff\xc7\x80\x80\x80Qc\xb5\xf2\xb0\xbe\xf9\xca\xff\xff\x80\x01\x81\xe8\xfd\xd6\xc5\xf2\xc4\xff\xff\x80cy\xd2\xfa\xc9\xc6\xff\xca\x80\x80\x80\x17[\xa3\xf2\xaa\xbb\xf7\xd2\xff\xff\x80\x01\xc8\xf6\xff\xea\xff\x80\x80\x80\x80\x80m\xb2\xf1\xff\xe7\xf5\xff\xff\x80\x80\x80,\x82\xc9\xfd\xcd\xc0\xff\xff\x80\x80\x80\x01\x84\xef\xfb\xdb\xd1\xff\xa5\x80\x80\x80^\x88\xe1\xfb\xda\xbe\xff\xff\x80\x80\x80\x16d\xae\xf5\xba\xa1\xff\xc7\x80\x80\x80\x01\xb6\xf9\xff\xe8\xeb\x80\x80\x80\x80\x80|\x8f\xf1\xff\xe3\xea\x80\x80\x80\x80\x80#M\xb5\xfb\xc1\xd3\xff\xcd\x80\x80\x80\x01\x9d\xf7\xff\xec\xe7\xff\xff\x80\x80\x80y\x8d\xeb\xff\xe1\xe3\xff\xff\x80\x80\x80-c\xbc\xfb\xc3\xd9\xff\xe0\x80\x80\x80\x01\x01\xfb\xff\xd5\xff\x80\x80\x80\x80\x80\xcb\x01\xf8\xff\xff\x80\x80\x80\x80\x80\x80\x89\x01\xb1\xff\xe0\xff\x80\x80\x80\x80\x80\xfd\x09\xf8\xfb\xcf\xd0\xff\xc0\x80\x80\x80\xaf\x0d\xe0\xf3\xc1\xb9\xf9\xc6\xff\xff\x80I\x11\xab\xdd\xa1\xb3\xec\xa7\xff\xea\x80\x01_\xf7\xfd\xd4\xb7\xff\xff\x80\x80\x80\xefZ\xf4\xfa\xd3\xd1\xff\xff\x80\x80\x80\x9bM\xc3\xf8\xbc\xc3\xff\xff\x80\x80\x80\x01\x18\xef\xfb\xda\xdb\xff\xcd\x80\x80\x80\xc93\xdb\xff\xc4\xba\x80\x80\x80\x80\x80E.\xbe\xef\xc9\xda\xff\xe4\x80\x80\x80\x01\xbf\xfb\xff\xff\x80\x80\x80\x80\x80\x80\xdf\xa5\xf9\xff\xd5\xff\x80\x80\x80\x80\x80\x8d|\xf8\xff\xff\x80\x80\x80\x80\x80\x80\x01\x10\xf8\xff\xff\x80\x80\x80\x80\x80\x80\xbe$\xe6\xff\xec\xff\x80\x80\x80\x80\x80\x95\x01\xff\x80\x80\x80\x80\x80\x80\x80\x80\x01\xe2\xff\x80\x80\x80\x80\x80\x80\x80\x80\xf7\xc0\xff\x80\x80\x80\x80\x80\x80\x80\x80\xf0\x80\xff\x80\x80\x80\x80\x80\x80\x80\x80\x01\x86\xfc\xff\xff\x80\x80\x80\x80\x80\x80\xd5>\xfa\xff\xff\x80\x80\x80\x80\x80\x807]\xff\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\x80\xca\x18\xd5\xeb\xba\xbf\xdc\xa0\xf0\xaf\xff~&\xb6\xe8\xa9\xb8\xe4\xae\xff\xbb\x80=.\x8a\xdb\x97\xb2\xf0\xaa\xff\xd8\x80\x01p\xe6\xfa\xc7\xbf\xf7\x9f\xff\xff\x80\xa6m\xe4\xfc\xd3\xd7\xff\xae\x80\x80\x80'M\xa2\xe8\xac\xb4\xf5\xb2\xff\xff\x80\x014\xdc\xf6\xc6\xc7\xf9\xdc\xff\xff\x80|J\xbf\xf3\xb7\xc1\xfa\xdd\xff\xff\x80\x18G\x82\xdb\x9a\xaa\xf3\xb6\xff\xff\x80\x01\xb6\xe1\xf9\xdb\xf0\xff\xe0\x80\x80\x80\x95\x96\xe2\xfc\xd8\xcd\xff\xab\x80\x80\x80\x1cl\xaa\xf2\xb7\xc2\xfe\xdf\xff\xff\x80\x01Q\xe6\xfc\xcc\xcb\xff\xc0\x80\x80\x80{f\xd1\xf7\xbc\xc4\xff\xe9\x80\x80\x80\x14_\x99\xf3\xa4\xad\xff\xcb\x80\x80\x80\x01\xde\xf8\xff\xd8\xd5\x80\x80\x80\x80\x80\xa8\xaf\xf6\xfc\xeb\xcd\xff\xff\x80\x80\x80/t\xd7\xff\xd3\xd4\xff\xff\x80\x80\x80\x01y\xec\xfd\xd4\xd6\xff\xff\x80\x80\x80\x8dT\xd5\xfc\xc9\xca\xff\xdb\x80\x80\x80*P\xa0\xf0\xa2\xb9\xff\xcd\x80\x80\x80\x01\x01\xff\x80\x80\x80\x80\x80\x80\x80\x80\xf4\x01\xff\x80\x80\x80\x80\x80\x80\x80\x80\xee\x01\xff\x80\x80\x80\x80\x80\x80\x80\x80" }
fn dc_quant_table() -> str { ret "\x00\x04\x00\x05\x00\x06\x00\x07\x00\x08\x00\x09\x00\x0a\x00\x0a\x00\x0b\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x11\x00\x12\x00\x13\x00\x14\x00\x14\x00\x15\x00\x15\x00\x16\x00\x16\x00\x17\x00\x17\x00\x18\x00\x19\x00\x19\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00 \x00!\x00\"\x00#\x00$\x00%\x00%\x00&\x00'\x00(\x00)\x00*\x00+\x00,\x00-\x00.\x00.\x00/\x000\x001\x002\x003\x004\x005\x006\x007\x008\x009\x00:\x00;\x00<\x00=\x00>\x00?\x00@\x00A\x00B\x00C\x00D\x00E\x00F\x00G\x00H\x00I\x00J\x00K\x00L\x00L\x00M\x00N\x00O\x00P\x00Q\x00R\x00S\x00T\x00U\x00V\x00W\x00X\x00Y\x00[\x00]\x00_\x00`\x00b\x00d\x00e\x00f\x00h\x00j\x00l\x00n\x00p\x00r\x00t\x00v\x00z\x00|\x00~\x00\x80\x00\x82\x00\x84\x00\x86\x00\x88\x00\x8a\x00\x8c\x00\x8f\x00\x91\x00\x94\x00\x97\x00\x9a\x00\x9d" }
fn ac_quant_table() -> str { ret "\x00\x04\x00\x05\x00\x06\x00\x07\x00\x08\x00\x09\x00\x0a\x00\x0b\x00\x0c\x00\x0d\x00\x0e\x00\x0f\x00\x10\x00\x11\x00\x12\x00\x13\x00\x14\x00\x15\x00\x16\x00\x17\x00\x18\x00\x19\x00\x1a\x00\x1b\x00\x1c\x00\x1d\x00\x1e\x00\x1f\x00 \x00!\x00\"\x00#\x00$\x00%\x00&\x00'\x00(\x00)\x00*\x00+\x00,\x00-\x00.\x00/\x000\x001\x002\x003\x004\x005\x006\x007\x008\x009\x00:\x00<\x00>\x00@\x00B\x00D\x00F\x00H\x00J\x00L\x00N\x00P\x00R\x00T\x00V\x00X\x00Z\x00\\\x00^\x00`\x00b\x00d\x00f\x00h\x00j\x00l\x00n\x00p\x00r\x00t\x00w\x00z\x00}\x00\x80\x00\x83\x00\x86\x00\x89\x00\x8c\x00\x8f\x00\x92\x00\x95\x00\x98\x00\x9b\x00\x9e\x00\xa1\x00\xa4\x00\xa7\x00\xaa\x00\xad\x00\xb1\x00\xb5\x00\xb9\x00\xbd\x00\xc1\x00\xc5\x00\xc9\x00\xcd\x00\xd1\x00\xd5\x00\xd9\x00\xdd\x00\xe1\x00\xe5\x00\xea\x00\xef\x00\xf5\x00\xf9\x00\xfe\x01\x03\x01\x08\x01\x0d\x01\x12\x01\x17\x01\x1c" }
fn coeff_bands_table() -> str { ret "\x00\x01\x02\x03\x06\x04\x05\x06\x06\x06\x06\x06\x06\x06\x06\x07" }
fn vp8_zigzag() -> str { ret "\x00\x01\x04\x08\x05\x02\x03\x06\x09\x0c\x0d\x0a\x07\x0b\x0e\x0f" }
fn pcat6_probs() -> str { ret "\xfe\xfe\xf3\xe6\xc4\xb1\x99\x8c\x85\x82\x81\x00" }

fn le32(d: []const u8, at: usize) -> u32 {
    ret u32(d[at]) | (u32(d[at + 1usize]) << 8u32) | (u32(d[at + 2usize]) << 16u32) | (u32(d[at + 3usize]) << 24u32)
}

fn le24(d: []const u8, at: usize) -> u32 {
    ret u32(d[at]) | (u32(d[at + 1usize]) << 8u32) | (u32(d[at + 2usize]) << 16u32)
}

fn tag(d: []const u8, at: usize) -> u32 {
    ret le32(d, at)
}

// ------------------------------------------------------------------ container

type Container = struct {
    width: u32,
    height: u32,
    has_alpha: bool,
    animated: bool,
    frames: u32,
    lossless: bool,
    bitstream: []const u8,
    alpha: []const u8,
    has_bitstream: bool,
}

const TAG_RIFF: u32 = 1179011410u32
const TAG_WEBP: u32 = 1346520407u32
const TAG_VP8: u32 = 540561494u32
const TAG_VP8L: u32 = 1278758998u32
const TAG_VP8X: u32 = 1480085590u32
const TAG_ALPH: u32 = 1213221953u32
const TAG_ANMF: u32 = 1179471425u32

// The first frame's bitstream and alpha, and what the headers say about the file.
fn parse_container(d: []const u8) -> (Container, err) {
    var c: Container = zero
    c.frames = 1u32
    if d.len < 20usize || tag(d, 0usize) != TAG_RIFF || tag(d, 8usize) != TAG_WEBP { ret (zero, Invalid) }
    var end = usize(le32(d, 4usize)) + 8usize
    if end > d.len { end = d.len }
    var at = 12usize
    var frames = 0u32
    while at + 8usize <= end {
        let kind = tag(d, at)
        let size = usize(le32(d, at + 4usize))
        if at + 8usize + size > end { ret (zero, Invalid) }
        let body = d[at + 8usize..at + 8usize + size]
        if kind == TAG_VP8X {
            if size < 10usize { ret (zero, Invalid) }
            c.has_alpha = (body[0] & 16u8) != 0u8
            c.animated = (body[0] & 2u8) != 0u8
            c.width = le24(body, 4usize) + 1u32
            c.height = le24(body, 7usize) + 1u32
        } else if kind == TAG_ANMF {
            frames += 1u32
            // The first frame's data are the chunks inside the first ANMF.
            if !c.has_bitstream && size >= 16usize {
                let (inner, inner_error) = first_bitstream(body[16usize..])
                if inner_error != ok { ret (zero, inner_error) }
                c.bitstream = inner.bitstream
                c.alpha = inner.alpha
                c.lossless = inner.lossless
                c.has_bitstream = inner.has_bitstream
                if c.width == 0u32 {
                    c.width = inner.width
                    c.height = inner.height
                }
            }
        } else if kind == TAG_ALPH {
            if !c.has_bitstream { c.alpha = body }
        } else if kind == TAG_VP8 || kind == TAG_VP8L {
            if !c.has_bitstream {
                c.bitstream = body
                c.lossless = kind == TAG_VP8L
                c.has_bitstream = true
            }
        }
        at += 8usize + size + (size & 1usize)
    }
    if !c.has_bitstream { ret (zero, Invalid) }
    if frames > 1u32 { c.frames = frames }
    if c.width == 0u32 {
        let (w, h, alpha_hint, dims_error) = bitstream_dimensions(c.bitstream, c.lossless)
        if dims_error != ok { ret (zero, dims_error) }
        c.width = w
        c.height = h
        if c.lossless && alpha_hint { c.has_alpha = true }
    }
    if c.alpha.len > 0usize { c.has_alpha = true }
    ret (c, ok)
}

// The chunks inside an ANMF frame: its ALPH and its bitstream.
fn first_bitstream(d: []const u8) -> (Container, err) {
    var c: Container = zero
    var at = 0usize
    while at + 8usize <= d.len {
        let kind = tag(d, at)
        let size = usize(le32(d, at + 4usize))
        if at + 8usize + size > d.len { ret (zero, Invalid) }
        let body = d[at + 8usize..at + 8usize + size]
        if kind == TAG_ALPH { c.alpha = body }
        if (kind == TAG_VP8 || kind == TAG_VP8L) && !c.has_bitstream {
            c.bitstream = body
            c.lossless = kind == TAG_VP8L
            c.has_bitstream = true
            let (w, h, _, dims_error) = bitstream_dimensions(body, c.lossless)
            if dims_error != ok { ret (zero, dims_error) }
            c.width = w
            c.height = h
        }
        at += 8usize + size + (size & 1usize)
    }
    ret (c, ok)
}

fn bitstream_dimensions(b: []const u8, lossless: bool) -> (u32, u32, bool, err) {
    if lossless {
        if b.len < 5usize || b[0] != 47u8 { ret (0u32, 0u32, false, Invalid) }
        let bits = le32(b, 1usize)
        let w = (bits & 16383u32) + 1u32
        let h = ((bits >> 14u32) & 16383u32) + 1u32
        let alpha = ((bits >> 28u32) & 1u32) != 0u32
        if ((bits >> 29u32) & 7u32) != 0u32 { ret (0u32, 0u32, false, Invalid) }
        ret (w, h, alpha, ok)
    }
    if b.len < 10usize { ret (0u32, 0u32, false, Invalid) }
    if (b[0] & 1u8) != 0u8 { ret (0u32, 0u32, false, Unsupported) }
    if b[3] != 157u8 || b[4] != 1u8 || b[5] != 42u8 { ret (0u32, 0u32, false, Invalid) }
    let w = u32(b[6]) | ((u32(b[7]) & 63u32) << 8u32)
    let h = u32(b[8]) | ((u32(b[9]) & 63u32) << 8u32)
    if w == 0u32 || h == 0u32 { ret (0u32, 0u32, false, Invalid) }
    ret (w, h, false, ok)
}

fn info_of(c: Container) -> image.Info {
    var alpha: image.Alpha = .Opaque
    if c.has_alpha { alpha = .Straight }
    ret image.Info { width: c.width, height: c.height, format: .Rgba8, alpha: alpha, frames: c.frames }
}

fn inspect(source: io.Reader) -> (image.Info, err) {
    var r = source
    var head: [65536]u8 = zero
    var filled = 0usize
    while filled < head.len {
        let (got, read_error) = io.read(&r, head[filled..])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        filled += got
    }
    var data = head[..filled]
    if data.len >= 12usize {
        // Only the headers are needed: cap the RIFF size at what was read.
        let (c, c_error) = parse_container(data)
        if c_error != ok { ret (zero, c_error) }
        ret (info_of(c), ok)
    }
    ret (zero, Invalid)
}

fn within(w: u32, h: u32, options: DecodeOptions) -> err {
    if options.max_width != 0u32 && w > options.max_width { ret TooLarge }
    if options.max_height != 0u32 && h > options.max_height { ret TooLarge }
    if options.max_pixels != 0u64 && u64(w) * u64(h) > options.max_pixels { ret TooLarge }
    ret ok
}

// ------------------------------------------------------------------ VP8L bit reading and prefix codes

type LBits = struct { data: []const u8, at: usize, cache: u64, count: u32, overrun: bool }

fn lfill(b: *LBits) {
    while b.count <= 56u32 {
        var byte = 0u64
        if b.at < b.data.len {
            byte = u64(b.data[b.at])
            b.at += 1usize
        } else {
            if b.count == 0u32 { b.overrun = true }
            if b.at < b.data.len + 8usize { b.at += 1usize } else { b.overrun = true }
        }
        b.cache = b.cache | (byte << b.count)
        b.count += 8u32
    }
}

fn lread(b: *LBits, n: u32) -> u32 {
    if n == 0u32 { ret 0u32 }
    if b.count < n { lfill(b) }
    let v = u32(b.cache & ((1u64 << n) - 1u64))
    b.cache = b.cache >> n
    b.count -= n
    ret v
}

// A canonical prefix code over `lengths` in puff's shape: counts per length and the
// symbols sorted by length; a single-symbol code answers without consuming a bit.
type Code = struct { counts: [16]u32, symbols: []u32, single: i32 }

fn build_code(a: *mem.Arena, lengths: []const u32) -> (Code, err) {
    var c: Code = zero
    c.single = -1i32
    let (symbols, alloc_error) = mem.alloc[u32](a, lengths.len)
    if alloc_error != ok { ret (zero, alloc_error) }
    c.symbols = symbols
    var i = 0usize
    var nonzero = 0usize
    var last = 0usize
    while i < lengths.len {
        if lengths[i] > 15u32 { ret (zero, Invalid) }
        if lengths[i] != 0u32 {
            c.counts[usize(lengths[i])] += 1u32
            nonzero += 1usize
            last = i
        }
        i += 1usize
    }
    if nonzero == 0usize { ret (c, ok) }
    if nonzero == 1usize {
        c.single = i32(last)
        ret (c, ok)
    }
    // Kraft: a complete code, neither over- nor under-subscribed.
    var left = 1i32
    var len = 1usize
    while len < 16usize {
        left = left << 1u32
        left -= i32(c.counts[len])
        if left < 0i32 { ret (zero, Invalid) }
        len += 1usize
    }
    if left != 0i32 { ret (zero, Invalid) }
    var offsets: [17]u32 = zero
    len = 1usize
    while len < 16usize {
        offsets[len + 1usize] = offsets[len] + c.counts[len]
        len += 1usize
    }
    i = 0usize
    while i < lengths.len {
        if lengths[i] != 0u32 {
            c.symbols[usize(offsets[usize(lengths[i])])] = u32(i)
            offsets[usize(lengths[i])] += 1u32
        }
        i += 1usize
    }
    ret (c, ok)
}

fn decode_code(b: *LBits, c: *const Code) -> (u32, err) {
    if c.single >= 0i32 { ret (u32(c.single), ok) }
    var code = 0i32
    var first = 0i32
    var index = 0i32
    var len = 1usize
    while len < 16usize {
        code = code | i32(lread(b, 1u32))
        let count = i32(c.counts[len])
        if code - first < count { ret (c.symbols[usize(index + code - first)], ok) }
        index += count
        first += count
        first = first << 1u32
        code = code << 1u32
        len += 1usize
    }
    ret (0u32, Invalid)
}

fn code_length_order(i: usize) -> usize {
    let order: [19]u8 = [19]u8{ 17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
    ret usize(order[i])
}

// The code lengths of one prefix code over `alphabet` symbols, simple or normal.
fn read_code(a: *mem.Arena, b: *LBits, alphabet: usize) -> (Code, err) {
    let (lengths, alloc_error) = mem.alloc[u32](a, alphabet)
    if alloc_error != ok { ret (zero, alloc_error) }
    var i = 0usize
    while i < alphabet {
        lengths[i] = 0u32
        i += 1usize
    }
    if lread(b, 1u32) == 1u32 {
        let count = lread(b, 1u32) + 1u32
        let first_bits = 1u32 + 7u32 * lread(b, 1u32)
        let s0 = usize(lread(b, first_bits))
        if s0 >= alphabet { ret (zero, Invalid) }
        lengths[s0] = 1u32
        if count == 2u32 {
            let s1 = usize(lread(b, 8u32))
            if s1 >= alphabet { ret (zero, Invalid) }
            lengths[s1] = 1u32
        }
        let (code, code_error) = build_code(a, lengths)
        ret (code, code_error)
    }
    var meta_lengths: [19]u32 = zero
    let n = usize(lread(b, 4u32)) + 4usize
    i = 0usize
    while i < n {
        meta_lengths[code_length_order(i)] = lread(b, 3u32)
        i += 1usize
    }
    let (meta, meta_error) = build_code(a, meta_lengths[0..])
    if meta_error != ok { ret (zero, meta_error) }
    var max_symbol = alphabet
    if lread(b, 1u32) == 1u32 {
        let length_bits = 2u32 + 2u32 * lread(b, 3u32)
        max_symbol = 2usize + usize(lread(b, length_bits))
        if max_symbol > alphabet { ret (zero, Invalid) }
    }
    var previous = 8u32
    var symbol = 0usize
    while symbol < alphabet && max_symbol > 0usize {
        max_symbol -= 1usize
        let (code_length, length_error) = decode_code(b, &meta)
        if length_error != ok { ret (zero, length_error) }
        if code_length < 16u32 {
            lengths[symbol] = code_length
            symbol += 1usize
            if code_length != 0u32 { previous = code_length }
        } else {
            var repeat = 0usize
            var value = 0u32
            if code_length == 16u32 {
                repeat = 3usize + usize(lread(b, 2u32))
                value = previous
            } else if code_length == 17u32 {
                repeat = 3usize + usize(lread(b, 3u32))
            } else {
                repeat = 11usize + usize(lread(b, 7u32))
            }
            if symbol + repeat > alphabet { ret (zero, Invalid) }
            while repeat > 0usize {
                lengths[symbol] = value
                symbol += 1usize
                repeat -= 1usize
            }
        }
    }
    let (code, code_error) = build_code(a, lengths)
    ret (code, code_error)
}

type Group = struct { green: Code, red: Code, blue: Code, alpha: Code, distance: Code }

fn read_group(a: *mem.Arena, b: *LBits, cache_size: usize) -> (Group, err) {
    var g: Group = zero
    let (green, e1) = read_code(a, b, 256usize + 24usize + cache_size)
    if e1 != ok { ret (zero, e1) }
    let (red, e2) = read_code(a, b, 256usize)
    if e2 != ok { ret (zero, e2) }
    let (blue, e3) = read_code(a, b, 256usize)
    if e3 != ok { ret (zero, e3) }
    let (alpha, e4) = read_code(a, b, 256usize)
    if e4 != ok { ret (zero, e4) }
    let (distance, e5) = read_code(a, b, 40usize)
    if e5 != ok { ret (zero, e5) }
    g.green = green
    g.red = red
    g.blue = blue
    g.alpha = alpha
    g.distance = distance
    ret (g, ok)
}

// ------------------------------------------------------------------ VP8L images

type Transform = struct { kind: u32, size_bits: u32, xsize: usize, data: []u32, table_size: usize, width_bits: u32 }

fn div_round_up(n: usize, bits: u32) -> usize {
    ret (n + (1usize << bits) - 1usize) >> bits
}

fn prefix_value(b: *LBits, code: u32) -> u32 {
    if code < 4u32 { ret code + 1u32 }
    let extra = (code - 2u32) >> 1u32
    let offset = (2u32 + (code & 1u32)) << extra
    ret offset + lread(b, extra) + 1u32
}

fn distance_map(code: usize) -> (i32, i32) {
    let map: [240]i8 = [240]i8{
        0, 1, 1, 0, 1, 1, -1, 1, 0, 2, 2, 0, 1, 2, -1, 2, 2, 1, -2, 1, 2, 2, -2, 2, 0, 3, 3, 0, 1, 3, -1, 3, 3, 1, -3, 1, 2, 3, -2, 3,
        3, 2, -3, 2, 0, 4, 4, 0, 1, 4, -1, 4, 4, 1, -4, 1, 3, 3, -3, 3, 2, 4, -2, 4, 4, 2, -4, 2, 0, 5, 3, 4, -3, 4, 4, 3, -4, 3, 5, 0,
        1, 5, -1, 5, 5, 1, -5, 1, 2, 5, -2, 5, 5, 2, -5, 2, 4, 4, -4, 4, 3, 5, -3, 5, 5, 3, -5, 3, 0, 6, 6, 0, 1, 6, -1, 6, 6, 1, -6, 1,
        2, 6, -2, 6, 6, 2, -6, 2, 4, 5, -4, 5, 5, 4, -5, 4, 3, 6, -3, 6, 6, 3, -6, 3, 0, 7, 7, 0, 1, 7, -1, 7, 5, 5, -5, 5, 7, 1, -7, 1,
        4, 6, -4, 6, 6, 4, -6, 4, 2, 7, -2, 7, 7, 2, -7, 2, 3, 7, -3, 7, 7, 3, -7, 3, 5, 6, -5, 6, 6, 5, -6, 5, 8, 0, 4, 7, -4, 7, 7, 4,
        -7, 4, 8, 1, 8, 2, 6, 6, -6, 6, 8, 3, 5, 7, -5, 7, 7, 5, -7, 5, 8, 4, 6, 7, -6, 7, 7, 6, -7, 6, 8, 5, 7, 7, -7, 7, 8, 6, 8, 7 }
    ret (i32(map[code * 2usize]), i32(map[code * 2usize + 1usize]))
}

fn cache_hash(argb: u32, bits: u32) -> usize {
    ret usize((argb *% 506832829u32) >> (32u32 - bits))
}

// One entropy-coded image of `w` x `h` ARGB pixels; `main` images carry transforms
// and may use meta prefix codes, the subresolution ones neither.
fn decode_image(a: *mem.Arena, b: *LBits, w0: usize, h: usize, main: bool, transforms: []Transform, transform_count: *usize) -> ([]u32, err) {
    var w = w0
    if main {
        while lread(b, 1u32) == 1u32 {
            if *transform_count >= 4usize { ret (zero, Invalid) }
            var t: Transform = zero
            t.kind = lread(b, 2u32)
            t.xsize = w
            var seen = 0usize
            while seen < *transform_count {
                if transforms[seen].kind == t.kind { ret (zero, Invalid) }
                seen += 1usize
            }
            if t.kind == 0u32 || t.kind == 1u32 {
                t.size_bits = lread(b, 3u32) + 2u32
                let (sub, sub_error) = decode_image(a, b, div_round_up(w, t.size_bits), div_round_up(h, t.size_bits), false, transforms, transform_count)
                if sub_error != ok { ret (zero, sub_error) }
                t.data = sub
            } else if t.kind == 3u32 {
                t.table_size = usize(lread(b, 8u32)) + 1usize
                let (table, table_error) = decode_image(a, b, t.table_size, 1usize, false, transforms, transform_count)
                if table_error != ok { ret (zero, table_error) }
                var i = 1usize
                while i < t.table_size {
                    table[i] = add_pixels(table[i], table[i - 1usize])
                    i += 1usize
                }
                t.data = table
                if t.table_size <= 2usize { t.width_bits = 3u32 } else if t.table_size <= 4usize { t.width_bits = 2u32 } else if t.table_size <= 16usize { t.width_bits = 1u32 } else { t.width_bits = 0u32 }
                w = div_round_up(w, t.width_bits)
            }
            transforms[*transform_count] = t
            *transform_count += 1usize
        }
    }
    var cache_bits = 0u32
    if lread(b, 1u32) == 1u32 {
        cache_bits = lread(b, 4u32)
        if cache_bits < 1u32 || cache_bits > 11u32 { ret (zero, Invalid) }
    }
    var cache_size = 0usize
    if cache_bits > 0u32 { cache_size = 1usize << cache_bits }
    var prefix_bits = 0u32
    var entropy: []u32 = zero
    var groups_count = 1usize
    if main && lread(b, 1u32) == 1u32 {
        prefix_bits = lread(b, 3u32) + 2u32
        let (sub, sub_error) = decode_image(a, b, div_round_up(w, prefix_bits), div_round_up(h, prefix_bits), false, transforms, transform_count)
        if sub_error != ok { ret (zero, sub_error) }
        entropy = sub
        var i = 0usize
        while i < entropy.len {
            let group = usize((entropy[i] >> 8u32) & 65535u32)
            if group + 1usize > groups_count { groups_count = group + 1usize }
            i += 1usize
        }
    }
    let (groups, groups_error) = mem.alloc[Group](a, groups_count)
    if groups_error != ok { ret (zero, groups_error) }
    var g = 0usize
    while g < groups_count {
        let (group, group_error) = read_group(a, b, cache_size)
        if group_error != ok { ret (zero, group_error) }
        groups[g] = group
        g += 1usize
    }
    let (pixels, pixels_error) = mem.alloc[u32](a, w * h)
    if pixels_error != ok { ret (zero, pixels_error) }
    var cache: []u32 = zero
    if cache_size > 0usize {
        let (made, cache_error) = mem.alloc[u32](a, cache_size)
        if cache_error != ok { ret (zero, cache_error) }
        cache = made
        var i = 0usize
        while i < cache_size {
            cache[i] = 0u32
            i += 1usize
        }
    }
    var pos = 0usize
    let total = w * h
    var last_cached = 0usize
    while pos < total {
        var group_index = 0usize
        if prefix_bits > 0u32 {
            let x = pos % w
            let y = pos / w
            group_index = usize((entropy[(y >> prefix_bits) * div_round_up(w, prefix_bits) + (x >> prefix_bits)] >> 8u32) & 65535u32)
        }
        let group = &groups[group_index]
        let (s, s_error) = decode_code(b, &group.green)
        if s_error != ok { ret (zero, s_error) }
        if b.overrun { ret (zero, Invalid) }
        if s < 256u32 {
            let (red, red_error) = decode_code(b, &group.red)
            if red_error != ok { ret (zero, red_error) }
            let (blue, blue_error) = decode_code(b, &group.blue)
            if blue_error != ok { ret (zero, blue_error) }
            let (alpha, alpha_error) = decode_code(b, &group.alpha)
            if alpha_error != ok { ret (zero, alpha_error) }
            pixels[pos] = (alpha << 24u32) | (red << 16u32) | (s << 8u32) | blue
            pos += 1usize
        } else if s < 280u32 {
            let length = usize(prefix_value(b, s - 256u32))
            let (dcode, dcode_error) = decode_code(b, &group.distance)
            if dcode_error != ok { ret (zero, dcode_error) }
            let dist_code = prefix_value(b, dcode)
            var dist = 0i64
            if dist_code > 120u32 {
                dist = i64(dist_code) - 120i64
            } else {
                let (xi, yi) = distance_map(usize(dist_code) - 1usize)
                dist = i64(xi) + i64(yi) * i64(w)
                if dist < 1i64 { dist = 1i64 }
            }
            if i64(pos) < dist || pos + length > total { ret (zero, Invalid) }
            var i = 0usize
            while i < length {
                pixels[pos] = pixels[pos - usize(dist)]
                pos += 1usize
                i += 1usize
            }
        } else {
            let index = usize(s - 280u32)
            if index >= cache_size { ret (zero, Invalid) }
            // Every pixel up to here goes into the cache before it is consulted.
            while last_cached < pos {
                cache[cache_hash(pixels[last_cached], cache_bits)] = pixels[last_cached]
                last_cached += 1usize
            }
            pixels[pos] = cache[index]
            pos += 1usize
        }
        if cache_size > 0usize {
            while last_cached < pos {
                cache[cache_hash(pixels[last_cached], cache_bits)] = pixels[last_cached]
                last_cached += 1usize
            }
        }
    }
    ret (pixels, ok)
}

fn add_pixels(a: u32, b: u32) -> u32 {
    let ag = (a & 4278255360u32) +% (b & 4278255360u32)
    let rb = (a & 16711935u32) +% (b & 16711935u32)
    ret (ag & 4278255360u32) | (rb & 16711935u32)
}

fn average2(a: u32, b: u32) -> u32 {
    ret (((a ^ b) & 4278124286u32) >> 1u32) + (a & b)
}

fn channel(v: u32, shift: u32) -> i32 {
    ret i32((v >> shift) & 255u32)
}

fn clamp255(v: i32) -> u32 {
    if v < 0i32 { ret 0u32 }
    if v > 255i32 { ret 255u32 }
    ret u32(v)
}

fn select_pixel(l: u32, t: u32, tl: u32) -> u32 {
    var pl = 0i32
    var pt = 0i32
    var shift = 0u32
    while shift < 32u32 {
        let estimate = channel(l, shift) + channel(t, shift) - channel(tl, shift)
        var dl = estimate - channel(l, shift)
        if dl < 0i32 { dl = 0i32 - dl }
        var dt = estimate - channel(t, shift)
        if dt < 0i32 { dt = 0i32 - dt }
        pl += dl
        pt += dt
        shift += 8u32
    }
    if pl < pt { ret l }
    ret t
}

fn clamp_add_subtract_full(a: u32, b: u32, c: u32) -> u32 {
    var out = 0u32
    var shift = 0u32
    while shift < 32u32 {
        out = out | (clamp255(channel(a, shift) + channel(b, shift) - channel(c, shift)) << shift)
        shift += 8u32
    }
    ret out
}

fn clamp_add_subtract_half(a: u32, b: u32) -> u32 {
    var out = 0u32
    var shift = 0u32
    while shift < 32u32 {
        let av = channel(a, shift)
        out = out | (clamp255(av + (av - channel(b, shift)) / 2i32) << shift)
        shift += 8u32
    }
    ret out
}

fn predict(mode: u32, l: u32, t: u32, tr: u32, tl: u32) -> u32 {
    if mode == 0u32 { ret 4278190080u32 }
    if mode == 1u32 { ret l }
    if mode == 2u32 { ret t }
    if mode == 3u32 { ret tr }
    if mode == 4u32 { ret tl }
    if mode == 5u32 { ret average2(average2(l, tr), t) }
    if mode == 6u32 { ret average2(l, tl) }
    if mode == 7u32 { ret average2(l, t) }
    if mode == 8u32 { ret average2(tl, t) }
    if mode == 9u32 { ret average2(t, tr) }
    if mode == 10u32 { ret average2(average2(l, tl), average2(t, tr)) }
    if mode == 11u32 { ret select_pixel(l, t, tl) }
    if mode == 12u32 { ret clamp_add_subtract_full(l, t, tl) }
    if mode == 13u32 { ret clamp_add_subtract_half(average2(l, t), tl) }
    ret 4278190080u32
}

fn color_delta(t: u8, c: u8) -> i32 {
    var ti = i32(t)
    if ti >= 128i32 { ti -= 256i32 }
    var ci = i32(c)
    if ci >= 128i32 { ci -= 256i32 }
    ret (ti * ci) >> 5u32
}

fn inverse_transform(t: Transform, pixels: []u32, w: usize, h: usize, out: []u32) -> usize {
    if t.kind == 0u32 {
        var y = 0usize
        while y < h {
            var x = 0usize
            while x < w {
                let at = y * w + x
                var pred = 4278190080u32
                if y == 0usize && x > 0usize {
                    pred = pixels[at - 1usize]
                } else if y > 0usize && x == 0usize {
                    pred = pixels[at - w]
                } else if y > 0usize {
                    let mode = (t.data[(y >> t.size_bits) * div_round_up(w, t.size_bits) + (x >> t.size_bits)] >> 8u32) & 15u32
                    var tr = pixels[at - w + 1usize]
                    if x + 1usize == w { tr = pixels[at - w + 1usize - w] }
                    pred = predict(mode, pixels[at - 1usize], pixels[at - w], tr, pixels[at - w - 1usize])
                }
                pixels[at] = add_pixels(pixels[at], pred)
                x += 1usize
            }
            y += 1usize
        }
        ret w
    }
    if t.kind == 1u32 {
        var y = 0usize
        while y < h {
            var x = 0usize
            while x < w {
                let at = y * w + x
                let cte = t.data[(y >> t.size_bits) * div_round_up(w, t.size_bits) + (x >> t.size_bits)]
                let p = pixels[at]
                let green = u8((p >> 8u32) & 255u32)
                var red = i32((p >> 16u32) & 255u32)
                var blue = i32(p & 255u32)
                red += color_delta(u8(cte & 255u32), green)
                red = red & 255i32
                blue += color_delta(u8((cte >> 8u32) & 255u32), green)
                blue += color_delta(u8((cte >> 16u32) & 255u32), u8(red))
                blue = blue & 255i32
                pixels[at] = (p & 4278255360u32) | (u32(red) << 16u32) | u32(blue)
                x += 1usize
            }
            y += 1usize
        }
        ret w
    }
    if t.kind == 2u32 {
        var i = 0usize
        while i < w * h {
            let p = pixels[i]
            let green = (p >> 8u32) & 255u32
            let red = ((p >> 16u32) + green) & 255u32
            let blue = (p + green) & 255u32
            pixels[i] = (p & 4278255360u32) | (red << 16u32) | blue
            i += 1usize
        }
        ret w
    }
    // Colour indexing: unbundle the packed width back to `t.xsize`.
    let full = t.xsize
    let per_pixel = 1usize << t.width_bits
    let bits = 8u32 >> t.width_bits
    let mask = (1u32 << bits) - 1u32
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < full {
            let packed = pixels[y * w + x / per_pixel]
            let index = usize(((packed >> 8u32) >> (u32(x % per_pixel) * bits)) & mask)
            var value = 0u32
            if index < t.table_size { value = t.data[index] }
            out[y * full + x] = value
            x += 1usize
        }
        y += 1usize
    }
    ret full
}

// A whole VP8L image stream (transforms and all) into ARGB pixels of `w` x `h`.
fn decode_lossless_stream(a: *mem.Arena, data: []const u8, w: usize, h: usize) -> ([]u32, err) {
    var b = LBits { data: data, at: 0usize, cache: 0u64, count: 0u32, overrun: false }
    var transforms: [4]Transform = zero
    var count = 0usize
    let (decoded, decode_error) = decode_image(a, &b, w, h, true, transforms[0..], &count)
    if decode_error != ok { ret (zero, decode_error) }
    var pixels = decoded
    var width = w
    if count > 0usize && transforms[count - 1usize].kind == 3u32 { width = div_round_up(w, transforms[count - 1usize].width_bits) }
    // The image was decoded at the width the last transform left; undo in reverse.
    var i = count
    while i > 0usize {
        i -= 1usize
        if transforms[i].kind == 3u32 {
            let (full, full_error) = mem.alloc[u32](a, transforms[i].xsize * h)
            if full_error != ok { ret (zero, full_error) }
            width = inverse_transform(transforms[i], pixels, width, h, full)
            pixels = full
        } else {
            width = inverse_transform(transforms[i], pixels, width, h, pixels)
        }
    }
    if width != w { ret (zero, Invalid) }
    ret (pixels, ok)
}

fn decode_lossless(a: *mem.Arena, bitstream: []const u8, w: u32, h: u32, out: image.Image) -> err {
    if bitstream.len < 5usize || bitstream[0] != 47u8 { ret Invalid }
    let (pixels, pixels_error) = decode_lossless_stream(a, bitstream[5usize..], usize(w), usize(h))
    if pixels_error != ok { ret pixels_error }
    var y = 0usize
    while y < usize(h) {
        var x = 0usize
        while x < usize(w) {
            let p = pixels[y * usize(w) + x]
            let at = y * out.stride + x * 4usize
            out.pixels[at] = u8((p >> 16u32) & 255u32)
            out.pixels[at + 1usize] = u8((p >> 8u32) & 255u32)
            out.pixels[at + 2usize] = u8(p & 255u32)
            out.pixels[at + 3usize] = u8(p >> 24u32)
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// ------------------------------------------------------------------ VP8 boolean decoder

type Bool = struct { data: []const u8, at: usize, range: u32, value: u32, bit_count: u32 }

fn bool_init(data: []const u8) -> Bool {
    var b: Bool = zero
    b.data = data
    b.range = 255u32
    var i = 0usize
    while i < 2usize {
        b.value = b.value << 8u32
        if i < data.len { b.value = b.value | u32(data[i]) }
        i += 1usize
    }
    b.at = 2usize
    ret b
}

fn read_bool(b: *Bool, prob: u32) -> u32 {
    let split = 1u32 + (((b.range - 1u32) * prob) >> 8u32)
    let big = split << 8u32
    var result = 0u32
    if b.value >= big {
        result = 1u32
        b.range -= split
        b.value -= big
    } else {
        b.range = split
    }
    while b.range < 128u32 {
        b.value = b.value << 1u32
        b.range = b.range << 1u32
        b.bit_count += 1u32
        if b.bit_count == 8u32 {
            b.bit_count = 0u32
            if b.at < b.data.len { b.value = b.value | u32(b.data[b.at]) }
            b.at += 1usize
        }
    }
    ret result
}

fn read_literal(b: *Bool, n: u32) -> u32 {
    var v = 0u32
    var i = 0u32
    while i < n {
        v = (v << 1u32) | read_bool(b, 128u32)
        i += 1u32
    }
    ret v
}

// A magnitude of `n` bits followed by a sign, the shape every delta takes.
fn read_delta(b: *Bool, n: u32) -> i32 {
    if read_bool(b, 128u32) == 0u32 { ret 0i32 }
    let magnitude = i32(read_literal(b, n))
    if read_bool(b, 128u32) != 0u32 { ret 0i32 - magnitude }
    ret magnitude
}

// ------------------------------------------------------------------ VP8 frame

type Vp8 = struct {
    width: usize,
    height: usize,
    mb_w: usize,
    mb_h: usize,
    segmentation: bool,
    update_map: bool,
    segment_abs: bool,
    segment_quant: [4]i32,
    segment_filter: [4]i32,
    segment_probs: [3]u32,
    filter_simple: bool,
    filter_level: i32,
    sharpness: i32,
    delta_enabled: bool,
    ref_delta: [4]i32,
    mode_delta: [4]i32,
    probs: []u8,
    skip_enabled: bool,
    prob_skip: u32,
    quant: [4][6]i32,
    y: []u8,
    u: []u8,
    v: []u8,
    y_stride: usize,
    uv_stride: usize,
    modes: []u8,
    filter_inner: []bool,
    segments: []u8,
    above_nz: []u8,
    above_nz_dc: []u8,
    left_nz: [9]u8,
    left_nz_dc: u8,
    above_bmodes: []u8,
    left_bmodes: [4]u8,
    coeffs: [400]i32,
}

fn dc_q(q: i32) -> i32 {
    var i = q
    if i < 0i32 { i = 0i32 }
    if i > 127i32 { i = 127i32 }
    let t = dc_quant_table()
    ret (i32(t[usize(i) * 2usize]) << 8u32) | i32(t[usize(i) * 2usize + 1usize])
}

fn ac_q(q: i32) -> i32 {
    var i = q
    if i < 0i32 { i = 0i32 }
    if i > 127i32 { i = 127i32 }
    let t = ac_quant_table()
    ret (i32(t[usize(i) * 2usize]) << 8u32) | i32(t[usize(i) * 2usize + 1usize])
}

fn prob_index(t: usize, band: usize, ctx: usize, i: usize) -> usize {
    ret ((t * 8usize + band) * 3usize + ctx) * 11usize + i
}

fn parse_vp8_header(a: *mem.Arena, f: *Vp8, b: *Bool) -> err {
    let color_space = read_literal(b, 1u32)
    let clamping = read_literal(b, 1u32)
    f.segmentation = read_literal(b, 1u32) == 1u32
    var i = 0usize
    while i < 3usize {
        f.segment_probs[i] = 255u32
        i += 1usize
    }
    if f.segmentation {
        f.update_map = read_literal(b, 1u32) == 1u32
        let update_data = read_literal(b, 1u32) == 1u32
        if update_data {
            f.segment_abs = read_literal(b, 1u32) == 1u32
            i = 0usize
            while i < 4usize {
                f.segment_quant[i] = read_delta(b, 7u32)
                i += 1usize
            }
            i = 0usize
            while i < 4usize {
                f.segment_filter[i] = read_delta(b, 6u32)
                i += 1usize
            }
        }
        if f.update_map {
            i = 0usize
            while i < 3usize {
                if read_literal(b, 1u32) == 1u32 { f.segment_probs[i] = read_literal(b, 8u32) }
                i += 1usize
            }
        }
    }
    f.filter_simple = read_literal(b, 1u32) == 1u32
    f.filter_level = i32(read_literal(b, 6u32))
    f.sharpness = i32(read_literal(b, 3u32))
    f.delta_enabled = read_literal(b, 1u32) == 1u32
    if f.delta_enabled {
        if read_literal(b, 1u32) == 1u32 {
            i = 0usize
            while i < 4usize {
                if read_literal(b, 1u32) == 1u32 {
                    let magnitude = i32(read_literal(b, 6u32))
                    if read_literal(b, 1u32) == 1u32 { f.ref_delta[i] = 0i32 - magnitude } else { f.ref_delta[i] = magnitude }
                }
                i += 1usize
            }
            i = 0usize
            while i < 4usize {
                if read_literal(b, 1u32) == 1u32 {
                    let magnitude = i32(read_literal(b, 6u32))
                    if read_literal(b, 1u32) == 1u32 { f.mode_delta[i] = 0i32 - magnitude } else { f.mode_delta[i] = magnitude }
                }
                i += 1usize
            }
        }
    }
    ret ok
}

// ------------------------------------------------------------------ VP8 macroblock header and tokens

fn read_bmode(b: *Bool, above: u32, left: u32) -> u32 {
    let p = kf_bmode_probs()
    let base = (usize(above) * 10usize + usize(left)) * 9usize
    // bmode_tree with the probabilities at each even node.
    if read_bool(b, u32(p[base])) == 0u32 { ret 0u32 }
    if read_bool(b, u32(p[base + 1usize])) == 0u32 { ret 1u32 }
    if read_bool(b, u32(p[base + 2usize])) == 0u32 { ret 2u32 }
    if read_bool(b, u32(p[base + 3usize])) == 0u32 {
        if read_bool(b, u32(p[base + 4usize])) == 0u32 { ret 3u32 }
        if read_bool(b, u32(p[base + 5usize])) == 0u32 { ret 5u32 }
        ret 6u32
    }
    if read_bool(b, u32(p[base + 6usize])) == 0u32 { ret 4u32 }
    if read_bool(b, u32(p[base + 7usize])) == 0u32 { ret 7u32 }
    if read_bool(b, u32(p[base + 8usize])) == 0u32 { ret 8u32 }
    ret 9u32
}

fn extra_bits(b: *Bool, probs: str, first: usize) -> i32 {
    var v = 0i32
    var i = first
    while probs[i] != 0u8 {
        v += v + i32(read_bool(b, u32(probs[i])))
        i += 1usize
    }
    ret v
}

// The coefficients of one 4x4 block into `out` (natural order, dequantised); answers
// whether any was nonzero.
fn read_coefficients(f: *Vp8, b: *Bool, kind: usize, ctx0: usize, first: usize, dc_factor: i32, ac_factor: i32, out: []i32, out_at: usize) -> bool {
    let bands = coeff_bands_table()
    let zz = vp8_zigzag()
    var ctx = ctx0
    var i = first
    var nonzero = false
    var skip_eob = false
    while i < 16usize {
        let band = usize(bands[i])
        let p = prob_index(kind, band, ctx, 0usize)
        if !skip_eob {
            if read_bool(b, u32(f.probs[p])) == 0u32 { break }
        }
        if read_bool(b, u32(f.probs[p + 1usize])) == 0u32 {
            ctx = 0usize
            skip_eob = true
            i += 1usize
            continue
        }
        var v = 0i32
        if read_bool(b, u32(f.probs[p + 2usize])) == 0u32 {
            v = 1i32
            ctx = 1usize
        } else {
            ctx = 2usize
            if read_bool(b, u32(f.probs[p + 3usize])) == 0u32 {
                if read_bool(b, u32(f.probs[p + 4usize])) == 0u32 {
                    v = 2i32
                } else {
                    v = 3i32 + i32(read_bool(b, u32(f.probs[p + 5usize])))
                }
            } else if read_bool(b, u32(f.probs[p + 6usize])) == 0u32 {
                if read_bool(b, u32(f.probs[p + 7usize])) == 0u32 {
                    v = 5i32 + i32(read_bool(b, 159u32))
                } else {
                    v = 7i32 + 2i32 * i32(read_bool(b, 165u32))
                    v += i32(read_bool(b, 145u32))
                }
            } else {
                let bit1 = read_bool(b, u32(f.probs[p + 8usize]))
                let bit2 = read_bool(b, u32(f.probs[p + 9usize + usize(bit1)]))
                let cat = 2u32 * bit1 + bit2
                if cat == 0u32 {
                    v = 11i32 + extra_bits(b, "\xad\x94\x8c\x00", 0usize)
                } else if cat == 1u32 {
                    v = 19i32 + extra_bits(b, "\xb0\x9b\x8c\x87\x00", 0usize)
                } else if cat == 2u32 {
                    v = 35i32 + extra_bits(b, "\xb4\x9d\x8d\x86\x82\x00", 0usize)
                } else {
                    v = 67i32 + extra_bits(b, pcat6_probs(), 0usize)
                }
            }
        }
        if read_bool(b, 128u32) != 0u32 { v = 0i32 - v }
        var factor = ac_factor
        if i == 0usize { factor = dc_factor }
        out[out_at + usize(zz[i])] = v * factor
        nonzero = true
        skip_eob = false
        i += 1usize
    }
    ret nonzero
}

// ------------------------------------------------------------------ VP8 transforms

fn inverse_wht(input: []i32, at: usize, output: []i32) {
    var tmp: [16]i32 = zero
    var i = 0usize
    while i < 4usize {
        let a1 = input[at + i] + input[at + 12usize + i]
        let b1 = input[at + 4usize + i] + input[at + 8usize + i]
        let c1 = input[at + 4usize + i] - input[at + 8usize + i]
        let d1 = input[at + i] - input[at + 12usize + i]
        tmp[i] = a1 + b1
        tmp[4usize + i] = c1 + d1
        tmp[8usize + i] = a1 - b1
        tmp[12usize + i] = d1 - c1
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        let a1 = tmp[4usize * i] + tmp[4usize * i + 3usize]
        let b1 = tmp[4usize * i + 1usize] + tmp[4usize * i + 2usize]
        let c1 = tmp[4usize * i + 1usize] - tmp[4usize * i + 2usize]
        let d1 = tmp[4usize * i] - tmp[4usize * i + 3usize]
        output[4usize * i] = (a1 + b1 + 3i32) >> 3u32
        output[4usize * i + 1usize] = (c1 + d1 + 3i32) >> 3u32
        output[4usize * i + 2usize] = (a1 - b1 + 3i32) >> 3u32
        output[4usize * i + 3usize] = (d1 - c1 + 3i32) >> 3u32
        i += 1usize
    }
}

fn mul_cos(v: i32) -> i32 {
    ret v + ((v * 20091i32) >> 16u32)
}

fn mul_sin(v: i32) -> i32 {
    ret (v * 35468i32) >> 16u32
}

// The exact integer IDCT, added onto the prediction already in `plane`.
fn idct_add(input: []i32, at: usize, plane: []u8, dst: usize, stride: usize) {
    var tmp: [16]i32 = zero
    var i = 0usize
    while i < 4usize {
        let a1 = input[at + i] + input[at + 8usize + i]
        let b1 = input[at + i] - input[at + 8usize + i]
        let c1 = mul_sin(input[at + 4usize + i]) - mul_cos(input[at + 12usize + i])
        let d1 = mul_cos(input[at + 4usize + i]) + mul_sin(input[at + 12usize + i])
        tmp[i] = a1 + d1
        tmp[12usize + i] = a1 - d1
        tmp[4usize + i] = b1 + c1
        tmp[8usize + i] = b1 - c1
        i += 1usize
    }
    i = 0usize
    while i < 4usize {
        let a1 = tmp[4usize * i] + tmp[4usize * i + 2usize]
        let b1 = tmp[4usize * i] - tmp[4usize * i + 2usize]
        let c1 = mul_sin(tmp[4usize * i + 1usize]) - mul_cos(tmp[4usize * i + 3usize])
        let d1 = mul_cos(tmp[4usize * i + 1usize]) + mul_sin(tmp[4usize * i + 3usize])
        let row = dst + i * stride
        plane[row] = u8(clamp255(i32(plane[row]) + ((a1 + d1 + 4i32) >> 3u32)))
        plane[row + 3usize] = u8(clamp255(i32(plane[row + 3usize]) + ((a1 - d1 + 4i32) >> 3u32)))
        plane[row + 1usize] = u8(clamp255(i32(plane[row + 1usize]) + ((b1 + c1 + 4i32) >> 3u32)))
        plane[row + 2usize] = u8(clamp255(i32(plane[row + 2usize]) + ((b1 - c1 + 4i32) >> 3u32)))
        i += 1usize
    }
}

// ------------------------------------------------------------------ VP8 prediction

fn avg3(x: u32, y: u32, z: u32) -> u8 {
    ret u8((x + y + y + z + 2u32) >> 2u32)
}

fn avg2(x: u32, y: u32) -> u8 {
    ret u8((x + y + 1u32) >> 1u32)
}

// Fills a `size` x `size` block at `dst` with one of the four whole-block modes,
// `edge` saying which neighbours exist: bit 0 above, bit 1 left.
fn predict_block(plane: []u8, dst: usize, stride: usize, size: usize, mode: u32, edge: u32, shift: u32) {
    var above: [16]u32 = zero
    var left: [16]u32 = zero
    var i = 0usize
    while i < size {
        above[i] = 127u32
        left[i] = 129u32
        if (edge & 1u32) != 0u32 { above[i] = u32(plane[dst - stride + i]) }
        if (edge & 2u32) != 0u32 { left[i] = u32(plane[dst + i * stride - 1usize]) }
        i += 1usize
    }
    var corner = 127u32
    if (edge & 2u32) != 0u32 && (edge & 1u32) != 0u32 { corner = u32(plane[dst - stride - 1usize]) }
    if (edge & 2u32) != 0u32 && (edge & 1u32) == 0u32 { corner = 127u32 }
    if (edge & 2u32) == 0u32 && (edge & 1u32) != 0u32 { corner = 129u32 }
    var y = 0usize
    while y < size {
        var x = 0usize
        while x < size {
            var v = 0u32
            if mode == 0u32 {
                var sum = 0u32
                var count = 0u32
                if (edge & 1u32) != 0u32 {
                    i = 0usize
                    while i < size {
                        sum += above[i]
                        i += 1usize
                    }
                    count += u32(size)
                }
                if (edge & 2u32) != 0u32 {
                    i = 0usize
                    while i < size {
                        sum += left[i]
                        i += 1usize
                    }
                    count += u32(size)
                }
                if count == 0u32 {
                    v = 128u32
                } else {
                    var sh = shift
                    if count == 2u32 * u32(size) { sh += 1u32 }
                    v = (sum + (1u32 << (sh - 1u32))) >> sh
                }
            } else if mode == 1u32 {
                v = above[x]
            } else if mode == 2u32 {
                v = left[y]
            } else {
                v = clamp255(i32(left[y]) + i32(above[x]) - i32(corner))
            }
            plane[dst + y * stride + x] = u8(v)
            x += 1usize
        }
        y += 1usize
    }
}

// One 4x4 luma subblock from the nine edge pixels and the four above-right ones.
fn predict_subblock(plane: []u8, dst: usize, stride: usize, mode: u32, a: []u32, l: []u32, p: u32) {
    // a[0..7]: above and above-right; l[0..3]: left; p: above-left.
    var e: [9]u32 = zero
    e[0] = l[3]
    e[1] = l[2]
    e[2] = l[1]
    e[3] = l[0]
    e[4] = p
    e[5] = a[0]
    e[6] = a[1]
    e[7] = a[2]
    e[8] = a[3]
    var block: [16]u8 = zero
    if mode == 0u32 {
        var v = 4u32
        var i = 0usize
        while i < 4usize {
            v += a[i] + l[i]
            i += 1usize
        }
        v = v >> 3u32
        i = 0usize
        while i < 16usize {
            block[i] = u8(v)
            i += 1usize
        }
    } else if mode == 1u32 {
        var r = 0usize
        while r < 4usize {
            var c = 0usize
            while c < 4usize {
                block[r * 4usize + c] = u8(clamp255(i32(l[r]) + i32(a[c]) - i32(p)))
                c += 1usize
            }
            r += 1usize
        }
    } else if mode == 2u32 {
        var c = 0usize
        while c < 4usize {
            var prev = p
            if c > 0usize { prev = a[c - 1usize] }
            let v = avg3(prev, a[c], a[c + 1usize])
            block[c] = v
            block[4usize + c] = v
            block[8usize + c] = v
            block[12usize + c] = v
            c += 1usize
        }
    } else if mode == 3u32 {
        var r = 0usize
        while r < 4usize {
            var prev = p
            if r > 0usize { prev = l[r - 1usize] }
            var next = l[3]
            if r < 3usize { next = l[r + 1usize] }
            let v = avg3(prev, l[r], next)
            block[r * 4usize] = v
            block[r * 4usize + 1usize] = v
            block[r * 4usize + 2usize] = v
            block[r * 4usize + 3usize] = v
            r += 1usize
        }
    } else if mode == 4u32 {
        block[0] = avg3(a[0], a[1], a[2])
        block[1] = avg3(a[1], a[2], a[3])
        block[4] = block[1]
        block[2] = avg3(a[2], a[3], a[4])
        block[5] = block[2]
        block[8] = block[2]
        block[3] = avg3(a[3], a[4], a[5])
        block[6] = block[3]
        block[9] = block[3]
        block[12] = block[3]
        block[7] = avg3(a[4], a[5], a[6])
        block[10] = block[7]
        block[13] = block[7]
        block[11] = avg3(a[5], a[6], a[7])
        block[14] = block[11]
        block[15] = avg3(a[6], a[7], a[7])
    } else if mode == 5u32 {
        block[12] = avg3(e[0], e[1], e[2])
        block[13] = avg3(e[1], e[2], e[3])
        block[8] = block[13]
        block[14] = avg3(e[2], e[3], e[4])
        block[9] = block[14]
        block[4] = block[14]
        block[15] = avg3(e[3], e[4], e[5])
        block[10] = block[15]
        block[5] = block[15]
        block[0] = block[15]
        block[11] = avg3(e[4], e[5], e[6])
        block[6] = block[11]
        block[1] = block[11]
        block[7] = avg3(e[5], e[6], e[7])
        block[2] = block[7]
        block[3] = avg3(e[6], e[7], e[8])
    } else if mode == 6u32 {
        block[12] = avg3(e[1], e[2], e[3])
        block[8] = avg3(e[2], e[3], e[4])
        block[13] = avg3(e[3], e[4], e[5])
        block[4] = block[13]
        block[9] = avg2(e[4], e[5])
        block[0] = block[9]
        block[14] = avg3(e[4], e[5], e[6])
        block[5] = block[14]
        block[10] = avg2(e[5], e[6])
        block[1] = block[10]
        block[15] = avg3(e[5], e[6], e[7])
        block[6] = block[15]
        block[11] = avg2(e[6], e[7])
        block[2] = block[11]
        block[7] = avg3(e[6], e[7], e[8])
        block[3] = avg2(e[7], e[8])
    } else if mode == 7u32 {
        block[0] = avg2(a[0], a[1])
        block[4] = avg3(a[0], a[1], a[2])
        block[8] = avg2(a[1], a[2])
        block[1] = block[8]
        block[5] = avg3(a[1], a[2], a[3])
        block[12] = block[5]
        block[9] = avg2(a[2], a[3])
        block[2] = block[9]
        block[13] = avg3(a[2], a[3], a[4])
        block[6] = block[13]
        block[10] = avg2(a[3], a[4])
        block[3] = block[10]
        block[14] = avg3(a[3], a[4], a[5])
        block[7] = block[14]
        block[11] = avg3(a[4], a[5], a[6])
        block[15] = avg3(a[5], a[6], a[7])
    } else if mode == 8u32 {
        block[12] = avg2(e[0], e[1])
        block[13] = avg3(e[0], e[1], e[2])
        block[8] = avg2(e[1], e[2])
        block[14] = block[8]
        block[9] = avg3(e[1], e[2], e[3])
        block[15] = block[9]
        block[10] = avg2(e[2], e[3])
        block[4] = block[10]
        block[11] = avg3(e[2], e[3], e[4])
        block[5] = block[11]
        block[6] = avg2(e[3], e[4])
        block[0] = block[6]
        block[7] = avg3(e[3], e[4], e[5])
        block[1] = block[7]
        block[2] = avg3(e[4], e[5], e[6])
        block[3] = avg3(e[5], e[6], e[7])
    } else {
        block[0] = avg2(l[0], l[1])
        block[1] = avg3(l[0], l[1], l[2])
        block[2] = avg2(l[1], l[2])
        block[4] = block[2]
        block[3] = avg3(l[1], l[2], l[3])
        block[5] = block[3]
        block[6] = avg2(l[2], l[3])
        block[8] = block[6]
        block[7] = avg3(l[2], l[3], l[3])
        block[9] = block[7]
        block[10] = u8(l[3])
        block[11] = u8(l[3])
        block[12] = u8(l[3])
        block[13] = u8(l[3])
        block[14] = u8(l[3])
        block[15] = u8(l[3])
    }
    var r = 0usize
    while r < 4usize {
        var c = 0usize
        while c < 4usize {
            plane[dst + r * stride + c] = block[r * 4usize + c]
            c += 1usize
        }
        r += 1usize
    }
}

// ------------------------------------------------------------------ VP8 loop filter

fn sat8(v: i32) -> i32 {
    if v < -128i32 { ret -128i32 }
    if v > 127i32 { ret 127i32 }
    ret v
}

fn su(v: i32) -> u8 {
    ret u8(clamp255(v))
}

fn px(plane: []u8, at: usize, step: usize, k: i32) -> i32 {
    if k < 0i32 { ret i32(plane[at - step * usize(0i32 - k)]) }
    ret i32(plane[at + step * usize(k)])
}

fn iabs(v: i32) -> i32 {
    if v < 0i32 { ret 0i32 - v }
    ret v
}

// `at` is q0; p0 is one `step` before it.
fn simple_threshold(plane: []u8, at: usize, step: usize, limit: i32) -> bool {
    let p1 = px(plane, at, step, -2i32)
    let p0 = px(plane, at, step, -1i32)
    let q0 = px(plane, at, step, 0i32)
    let q1 = px(plane, at, step, 1i32)
    ret iabs(p0 - q0) * 2i32 + (iabs(p1 - q1) >> 1u32) <= limit
}

fn normal_threshold(plane: []u8, at: usize, step: usize, edge: i32, interior: i32) -> bool {
    if !simple_threshold(plane, at, step, 2i32 * edge + interior) { ret false }
    let p3 = px(plane, at, step, -4i32)
    let p2 = px(plane, at, step, -3i32)
    let p1 = px(plane, at, step, -2i32)
    let p0 = px(plane, at, step, -1i32)
    let q0 = px(plane, at, step, 0i32)
    let q1 = px(plane, at, step, 1i32)
    let q2 = px(plane, at, step, 2i32)
    let q3 = px(plane, at, step, 3i32)
    ret iabs(p3 - p2) <= interior && iabs(p2 - p1) <= interior && iabs(p1 - p0) <= interior && iabs(q3 - q2) <= interior && iabs(q2 - q1) <= interior && iabs(q1 - q0) <= interior
}

fn high_variance(plane: []u8, at: usize, step: usize, threshold: i32) -> bool {
    ret iabs(px(plane, at, step, -2i32) - px(plane, at, step, -1i32)) > threshold || iabs(px(plane, at, step, 1i32) - px(plane, at, step, 0i32)) > threshold
}

fn filter_common(plane: []u8, at: usize, step: usize, outer_taps: bool) {
    let p1 = px(plane, at, step, -2i32) - 128i32
    let p0 = px(plane, at, step, -1i32) - 128i32
    let q0 = px(plane, at, step, 0i32) - 128i32
    let q1 = px(plane, at, step, 1i32) - 128i32
    var a = 3i32 * (q0 - p0)
    if outer_taps { a += sat8(p1 - q1) }
    a = sat8(a)
    let f1 = sat8(a + 4i32) >> 3u32
    let f2 = sat8(a + 3i32) >> 3u32
    plane[at - step] = su(p0 + f2 + 128i32)
    plane[at] = su(q0 - f1 + 128i32)
    if !outer_taps {
        let adjust = (f1 + 1i32) >> 1u32
        plane[at - 2usize * step] = su(p1 + adjust + 128i32)
        plane[at + step] = su(q1 - adjust + 128i32)
    }
}

fn filter_mb_edge(plane: []u8, at: usize, step: usize) {
    let p2 = px(plane, at, step, -3i32) - 128i32
    let p1 = px(plane, at, step, -2i32) - 128i32
    let p0 = px(plane, at, step, -1i32) - 128i32
    let q0 = px(plane, at, step, 0i32) - 128i32
    let q1 = px(plane, at, step, 1i32) - 128i32
    let q2 = px(plane, at, step, 2i32) - 128i32
    let w = sat8(sat8(p1 - q1) + 3i32 * (q0 - p0))
    var a = sat8((27i32 * w + 63i32) >> 7u32)
    plane[at - step] = su(p0 + a + 128i32)
    plane[at] = su(q0 - a + 128i32)
    a = sat8((18i32 * w + 63i32) >> 7u32)
    plane[at - 2usize * step] = su(p1 + a + 128i32)
    plane[at + step] = su(q1 - a + 128i32)
    a = sat8((9i32 * w + 63i32) >> 7u32)
    plane[at - 3usize * step] = su(p2 + a + 128i32)
    plane[at + 2usize * step] = su(q2 - a + 128i32)
}

// Filters `count` segments along an edge: `step` crosses the edge, `along` walks it.
fn filter_edge(plane: []u8, at0: usize, step: usize, along: usize, count: usize, edge: i32, interior: i32, hev: i32, mb_edge: bool, simple: bool) {
    var at = at0
    var i = 0usize
    while i < count {
        if simple {
            if simple_threshold(plane, at, step, 2i32 * edge + interior) { filter_common(plane, at, step, true) }
        } else if normal_threshold(plane, at, step, edge, interior) {
            let hv = high_variance(plane, at, step, hev)
            if mb_edge {
                if hv { filter_common(plane, at, step, true) } else { filter_mb_edge(plane, at, step) }
            } else {
                filter_common(plane, at, step, hv)
            }
        }
        at += along
        i += 1usize
    }
}

fn loop_filter(f: *Vp8) {
    if f.filter_level == 0i32 { ret }
    var my = 0usize
    while my < f.mb_h {
        var mx = 0usize
        while mx < f.mb_w {
            let mb = my * f.mb_w + mx
            var level = f.filter_level
            if f.segmentation {
                if f.segment_abs { level = f.segment_filter[usize(f.segments[mb])] } else { level += f.segment_filter[usize(f.segments[mb])] }
            }
            if level > 63i32 { level = 63i32 }
            if level < 0i32 { level = 0i32 }
            if f.delta_enabled {
                level += f.ref_delta[0]
                if f.modes[mb] == 4u8 { level += f.mode_delta[0] }
            }
            if level > 63i32 { level = 63i32 }
            if level < 0i32 { level = 0i32 }
            if level > 0i32 {
                var interior = level
                if f.sharpness > 0i32 {
                    if f.sharpness > 4i32 { interior = interior >> 2u32 } else { interior = interior >> 1u32 }
                    if interior > 9i32 - f.sharpness { interior = 9i32 - f.sharpness }
                }
                if interior < 1i32 { interior = 1i32 }
                var hev = 0i32
                if level >= 40i32 { hev = 2i32 } else if level >= 15i32 { hev = 1i32 }
                let inner = f.filter_inner[mb]
                let y_at = my * 16usize * f.y_stride + mx * 16usize
                let uv_at = my * 8usize * f.uv_stride + mx * 8usize
                let simple = f.filter_simple
                if mx > 0usize {
                    filter_edge(f.y, y_at, 1usize, f.y_stride, 16usize, level + 2i32, interior, hev, true, simple)
                    if !simple {
                        filter_edge(f.u, uv_at, 1usize, f.uv_stride, 8usize, level + 2i32, interior, hev, true, false)
                        filter_edge(f.v, uv_at, 1usize, f.uv_stride, 8usize, level + 2i32, interior, hev, true, false)
                    }
                }
                if inner {
                    filter_edge(f.y, y_at + 4usize, 1usize, f.y_stride, 16usize, level, interior, hev, false, simple)
                    filter_edge(f.y, y_at + 8usize, 1usize, f.y_stride, 16usize, level, interior, hev, false, simple)
                    filter_edge(f.y, y_at + 12usize, 1usize, f.y_stride, 16usize, level, interior, hev, false, simple)
                    if !simple {
                        filter_edge(f.u, uv_at + 4usize, 1usize, f.uv_stride, 8usize, level, interior, hev, false, false)
                        filter_edge(f.v, uv_at + 4usize, 1usize, f.uv_stride, 8usize, level, interior, hev, false, false)
                    }
                }
                if my > 0usize {
                    filter_edge(f.y, y_at, f.y_stride, 1usize, 16usize, level + 2i32, interior, hev, true, simple)
                    if !simple {
                        filter_edge(f.u, uv_at, f.uv_stride, 1usize, 8usize, level + 2i32, interior, hev, true, false)
                        filter_edge(f.v, uv_at, f.uv_stride, 1usize, 8usize, level + 2i32, interior, hev, true, false)
                    }
                }
                if inner {
                    filter_edge(f.y, y_at + 4usize * f.y_stride, f.y_stride, 1usize, 16usize, level, interior, hev, false, simple)
                    filter_edge(f.y, y_at + 8usize * f.y_stride, f.y_stride, 1usize, 16usize, level, interior, hev, false, simple)
                    filter_edge(f.y, y_at + 12usize * f.y_stride, f.y_stride, 1usize, 16usize, level, interior, hev, false, simple)
                    if !simple {
                        filter_edge(f.u, uv_at + 4usize * f.uv_stride, f.uv_stride, 1usize, 8usize, level, interior, hev, false, false)
                        filter_edge(f.v, uv_at + 4usize * f.uv_stride, f.uv_stride, 1usize, 8usize, level, interior, hev, false, false)
                    }
                }
            }
            mx += 1usize
        }
        my += 1usize
    }
}

// ------------------------------------------------------------------ VP8 macroblocks

// Reconstructs one macroblock: modes from `hb` (the first partition), residual
// tokens from `tb` (its partition), prediction and the transforms into the planes.
fn decode_macroblock(f: *Vp8, hb: *Bool, tb: *Bool, mx: usize, my: usize) -> err {
    let mb = my * f.mb_w + mx
    var segment = 0usize
    if f.update_map {
        if read_bool(hb, f.segment_probs[0]) == 0u32 {
            segment = usize(read_bool(hb, f.segment_probs[1]))
        } else {
            segment = 2usize + usize(read_bool(hb, f.segment_probs[2]))
        }
    }
    f.segments[mb] = u8(segment)
    var skip = false
    if f.skip_enabled { skip = read_bool(hb, f.prob_skip) == 1u32 }
    // kf_ymode_tree: B_PRED first, then DC/V, H/TM.
    var ymode = 4u32
    if read_bool(hb, 145u32) != 0u32 {
        if read_bool(hb, 156u32) == 0u32 {
            ymode = read_bool(hb, 163u32)
        } else {
            ymode = 2u32 + read_bool(hb, 128u32)
        }
    }
    f.modes[mb] = u8(ymode)
    var bmodes: [16]u32 = zero
    if ymode == 4u32 {
        var i = 0usize
        while i < 16usize {
            let bx = i % 4usize
            let by = i / 4usize
            var above = 0u32
            if by > 0usize { above = bmodes[i - 4usize] } else { above = u32(f.above_bmodes[mx * 4usize + bx]) }
            var left = 0u32
            if bx > 0usize { left = bmodes[i - 1usize] } else { left = u32(f.left_bmodes[by]) }
            bmodes[i] = read_bmode(hb, above, left)
            i += 1usize
        }
    } else {
        // The whole-block mode's subblock equivalent, for the neighbours' contexts.
        var equivalent = 0u32
        if ymode == 1u32 { equivalent = 2u32 }
        if ymode == 2u32 { equivalent = 3u32 }
        if ymode == 3u32 { equivalent = 1u32 }
        var i = 0usize
        while i < 16usize {
            bmodes[i] = equivalent
            i += 1usize
        }
    }
    var i = 0usize
    while i < 4usize {
        f.above_bmodes[mx * 4usize + i] = u8(bmodes[12usize + i])
        f.left_bmodes[i] = u8(bmodes[i * 4usize + 3usize])
        i += 1usize
    }
    // uv_mode_tree.
    var uvmode = 0u32
    if read_bool(hb, 142u32) != 0u32 {
        if read_bool(hb, 114u32) == 0u32 { uvmode = 1u32 } else { uvmode = 2u32 + read_bool(hb, 183u32) }
    }
    // Residual.
    i = 0usize
    while i < 400usize {
        f.coeffs[i] = 0i32
        i += 1usize
    }
    var any_nonzero = false
    let q = f.quant[segment]
    if !skip {
        var first = 0usize
        var y_kind = 3usize
        if ymode != 4u32 {
            let ctx = usize(f.above_nz_dc[mx]) + usize(f.left_nz_dc)
            var y2: [16]i32 = zero
            let nz = read_coefficients(f, tb, 1usize, ctx, 0usize, q[4], q[5], y2[0..], 0usize)
            f.above_nz_dc[mx] = 0u8
            f.left_nz_dc = 0u8
            if nz {
                f.above_nz_dc[mx] = 1u8
                f.left_nz_dc = 1u8
                any_nonzero = true
            }
            var dc: [16]i32 = zero
            inverse_wht(y2[0..], 0usize, dc[0..])
            var k = 0usize
            while k < 16usize {
                f.coeffs[k * 16usize] = dc[k]
                k += 1usize
            }
            first = 1usize
            y_kind = 0usize
        }
        var by = 0usize
        while by < 4usize {
            var bx = 0usize
            while bx < 4usize {
                let ctx = usize(f.above_nz[mx * 4usize + bx]) + usize(f.left_nz[by])
                let nz = read_coefficients(f, tb, y_kind, ctx, first, q[0], q[1], f.coeffs[0..], (by * 4usize + bx) * 16usize)
                var flag = 0u8
                if nz { flag = 1u8 }
                f.above_nz[mx * 4usize + bx] = flag
                f.left_nz[by] = flag
                if nz { any_nonzero = true }
                bx += 1usize
            }
            by += 1usize
        }
        var plane = 0usize
        while plane < 2usize {
            by = 0usize
            while by < 2usize {
                var bx = 0usize
                while bx < 2usize {
                    let above_index = f.mb_w * 4usize + (mx * 2usize + bx) + plane * f.mb_w * 2usize
                    let left_index = 4usize + plane * 2usize + by
                    let ctx = usize(f.above_nz[above_index]) + usize(f.left_nz[left_index])
                    let nz = read_coefficients(f, tb, 2usize, ctx, 0usize, q[2], q[3], f.coeffs[0..], 256usize + (plane * 4usize + by * 2usize + bx) * 16usize)
                    var flag = 0u8
                    if nz { flag = 1u8 }
                    f.above_nz[above_index] = flag
                    f.left_nz[left_index] = flag
                    if nz { any_nonzero = true }
                    bx += 1usize
                }
                by += 1usize
            }
            plane += 1usize
        }
    } else {
        i = 0usize
        while i < 4usize {
            f.above_nz[mx * 4usize + i] = 0u8
            f.left_nz[i] = 0u8
            i += 1usize
        }
        i = 0usize
        while i < 2usize {
            f.above_nz[f.mb_w * 4usize + mx * 2usize + i] = 0u8
            f.above_nz[f.mb_w * 6usize + mx * 2usize + i] = 0u8
            f.left_nz[4usize + i] = 0u8
            f.left_nz[6usize + i] = 0u8
            i += 1usize
        }
        if ymode != 4u32 {
            f.above_nz_dc[mx] = 0u8
            f.left_nz_dc = 0u8
        }
    }
    f.filter_inner[mb] = any_nonzero || ymode == 4u32
    // Prediction and reconstruction.
    let y_at = my * 16usize * f.y_stride + mx * 16usize
    var edge = 0u32
    if my > 0usize { edge = edge | 1u32 }
    if mx > 0usize { edge = edge | 2u32 }
    if ymode == 4u32 {
        var sb = 0usize
        while sb < 16usize {
            let bx = sb % 4usize
            let by = sb / 4usize
            let dst = y_at + by * 4usize * f.y_stride + bx * 4usize
            var above: [8]u32 = zero
            var left: [4]u32 = zero
            var corner = 127u32
            let have_above = my > 0usize || by > 0usize
            let have_left = mx > 0usize || bx > 0usize
            var k = 0usize
            while k < 4usize {
                if have_above { above[k] = u32(f.y[dst - f.y_stride + k]) } else { above[k] = 127u32 }
                if have_left { left[k] = u32(f.y[dst + k * f.y_stride - 1usize]) } else { left[k] = 129u32 }
                k += 1usize
            }
            // Above-right: the row above the macroblock for the right column, the
            // above-right macroblock's last row past the frame's right edge.
            k = 0usize
            while k < 4usize {
                var v = 127u32
                if my > 0usize || by > 0usize {
                    if bx < 3usize {
                        v = u32(f.y[dst - f.y_stride + 4usize + k])
                    } else if my > 0usize {
                        if mx + 1usize < f.mb_w {
                            v = u32(f.y[y_at - f.y_stride + 16usize + k])
                        } else {
                            v = u32(f.y[y_at - f.y_stride + 15usize])
                        }
                    }
                }
                above[4usize + k] = v
                k += 1usize
            }
            if have_above && have_left {
                corner = u32(f.y[dst - f.y_stride - 1usize])
            } else if have_above {
                corner = 129u32
            } else if have_left {
                corner = 127u32
            }
            predict_subblock(f.y, dst, f.y_stride, bmodes[sb], above[0..], left[0..], corner)
            idct_add(f.coeffs[0..], sb * 16usize, f.y, dst, f.y_stride)
            sb += 1usize
        }
    } else {
        predict_block(f.y, y_at, f.y_stride, 16usize, ymode, edge, 4u32)
        var sb = 0usize
        while sb < 16usize {
            idct_add(f.coeffs[0..], sb * 16usize, f.y, y_at + (sb / 4usize) * 4usize * f.y_stride + (sb % 4usize) * 4usize, f.y_stride)
            sb += 1usize
        }
    }
    let uv_at = my * 8usize * f.uv_stride + mx * 8usize
    predict_block(f.u, uv_at, f.uv_stride, 8usize, uvmode, edge, 3u32)
    predict_block(f.v, uv_at, f.uv_stride, 8usize, uvmode, edge, 3u32)
    var sb = 0usize
    while sb < 4usize {
        let dst = uv_at + (sb / 2usize) * 4usize * f.uv_stride + (sb % 2usize) * 4usize
        idct_add(f.coeffs[0..], 256usize + sb * 16usize, f.u, dst, f.uv_stride)
        idct_add(f.coeffs[0..], 320usize + sb * 16usize, f.v, dst, f.uv_stride)
        sb += 1usize
    }
    ret ok
}

fn decode_lossy(a: *mem.Arena, bitstream: []const u8, out: image.Image) -> err {
    if bitstream.len < 10usize { ret Invalid }
    if (bitstream[0] & 1u8) != 0u8 { ret Unsupported }
    let first_size = usize(le24(bitstream, 0usize) >> 5u32)
    if 10usize + first_size > bitstream.len { ret Invalid }
    let (frames, frame_error) = mem.alloc[Vp8](a, 1usize)
    if frame_error != ok { ret frame_error }
    let f = &frames[0usize]
    var blank: Vp8 = zero
    frames[0usize] = blank
    f.width = usize(bitstream[6]) | ((usize(bitstream[7]) & 63usize) << 8u32)
    f.height = usize(bitstream[8]) | ((usize(bitstream[9]) & 63usize) << 8u32)
    f.mb_w = (f.width + 15usize) / 16usize
    f.mb_h = (f.height + 15usize) / 16usize
    var hb = bool_init(bitstream[10usize..10usize + first_size])
    let header_error = parse_vp8_header(a, f, &hb)
    if header_error != ok { ret header_error }
    let partitions = 1usize << read_literal(&hb, 2u32)
    // Quantisers.
    let base_q = i32(read_literal(&hb, 7u32))
    let y_dc_delta = read_delta(&hb, 4u32)
    let y2_dc_delta = read_delta(&hb, 4u32)
    let y2_ac_delta = read_delta(&hb, 4u32)
    let uv_dc_delta = read_delta(&hb, 4u32)
    let uv_ac_delta = read_delta(&hb, 4u32)
    var s = 0usize
    while s < 4usize {
        var q = base_q
        if f.segmentation {
            if f.segment_abs { q = f.segment_quant[s] } else { q += f.segment_quant[s] }
        }
        f.quant[s][0] = dc_q(q + y_dc_delta)
        f.quant[s][1] = ac_q(q)
        f.quant[s][2] = dc_q(q + uv_dc_delta)
        if f.quant[s][2] > 132i32 { f.quant[s][2] = 132i32 }
        f.quant[s][3] = ac_q(q + uv_ac_delta)
        f.quant[s][4] = dc_q(q + y2_dc_delta) * 2i32
        f.quant[s][5] = ac_q(q + y2_ac_delta) * 155i32 / 100i32
        if f.quant[s][5] < 8i32 { f.quant[s][5] = 8i32 }
        s += 1usize
    }
    let refresh = read_literal(&hb, 1u32)
    // Token probabilities: the defaults, then the header's updates.
    let (probs, probs_error) = mem.alloc[u8](a, 1056usize)
    if probs_error != ok { ret probs_error }
    mem.copy[u8](probs, default_coeff_probs())
    f.probs = probs
    let updates = coeff_update_probs()
    var i = 0usize
    while i < 1056usize {
        if read_bool(&hb, u32(updates[i])) != 0u32 { probs[i] = u8(read_literal(&hb, 8u32)) }
        i += 1usize
    }
    f.skip_enabled = read_literal(&hb, 1u32) == 1u32
    if f.skip_enabled { f.prob_skip = read_literal(&hb, 8u32) }
    // Token partitions: their sizes follow the first partition.
    var part_at = 10usize + first_size
    let sizes_at = part_at
    part_at += 3usize * (partitions - 1usize)
    if part_at > bitstream.len { ret Invalid }
    var readers: [8]Bool = zero
    var p = 0usize
    while p < partitions {
        var size = bitstream.len - part_at
        if p + 1usize < partitions {
            size = usize(le24(bitstream, sizes_at + 3usize * p))
            if part_at + size > bitstream.len { ret Invalid }
        }
        readers[p] = bool_init(bitstream[part_at..part_at + size])
        part_at += size
        p += 1usize
    }
    // Planes, padded to whole macroblocks.
    f.y_stride = f.mb_w * 16usize
    f.uv_stride = f.mb_w * 8usize
    let (y, y_error) = mem.alloc[u8](a, f.y_stride * f.mb_h * 16usize)
    if y_error != ok { ret y_error }
    let (u, u_error) = mem.alloc[u8](a, f.uv_stride * f.mb_h * 8usize)
    if u_error != ok { ret u_error }
    let (v, v_error) = mem.alloc[u8](a, f.uv_stride * f.mb_h * 8usize)
    if v_error != ok { ret v_error }
    f.y = y
    f.u = u
    f.v = v
    let (modes, modes_error) = mem.alloc[u8](a, f.mb_w * f.mb_h)
    if modes_error != ok { ret modes_error }
    let (inner, inner_error) = mem.alloc[bool](a, f.mb_w * f.mb_h)
    if inner_error != ok { ret inner_error }
    let (segments, segments_error) = mem.alloc[u8](a, f.mb_w * f.mb_h)
    if segments_error != ok { ret segments_error }
    let (above_nz, above_nz_error) = mem.alloc[u8](a, f.mb_w * 8usize)
    if above_nz_error != ok { ret above_nz_error }
    let (above_nz_dc, above_dc_error) = mem.alloc[u8](a, f.mb_w)
    if above_dc_error != ok { ret above_dc_error }
    let (above_bmodes, above_bmodes_error) = mem.alloc[u8](a, f.mb_w * 4usize)
    if above_bmodes_error != ok { ret above_bmodes_error }
    f.modes = modes
    f.filter_inner = inner
    f.segments = segments
    f.above_nz = above_nz
    f.above_nz_dc = above_nz_dc
    f.above_bmodes = above_bmodes
    i = 0usize
    while i < above_nz.len {
        above_nz[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < f.mb_w {
        above_nz_dc[i] = 0u8
        i += 1usize
    }
    i = 0usize
    while i < above_bmodes.len {
        above_bmodes[i] = 0u8
        i += 1usize
    }
    var my = 0usize
    while my < f.mb_h {
        i = 0usize
        while i < 9usize {
            f.left_nz[i] = 0u8
            i += 1usize
        }
        f.left_nz_dc = 0u8
        i = 0usize
        while i < 4usize {
            f.left_bmodes[i] = 0u8
            i += 1usize
        }
        var mx = 0usize
        while mx < f.mb_w {
            let mb_error = decode_macroblock(f, &hb, &readers[my % partitions], mx, my)
            if mb_error != ok { ret mb_error }
            mx += 1usize
        }
        my += 1usize
    }
    loop_filter(f)
    // Colour: BT.601 from the planes, chroma through the triangle filter.
    var py = 0usize
    while py < f.height {
        var pxl = 0usize
        while pxl < f.width {
            let at = py * out.stride + pxl * 4usize
            let yv = f32(f.y[py * f.y_stride + pxl])
            let uv = chroma_sample(f.u, f.uv_stride, f.mb_w * 8usize, f.mb_h * 8usize, pxl, py)
            let vv = chroma_sample(f.v, f.uv_stride, f.mb_w * 8usize, f.mb_h * 8usize, pxl, py)
            let yy = 1.164 * (yv - 16.0)
            out.pixels[at] = u8(clamp255(i32(yy + 1.596 * (vv - 128.0) + 0.5 + 256.0) - 256i32))
            out.pixels[at + 1usize] = u8(clamp255(i32(yy - 0.391 * (uv - 128.0) - 0.813 * (vv - 128.0) + 0.5 + 256.0) - 256i32))
            out.pixels[at + 2usize] = u8(clamp255(i32(yy + 2.018 * (uv - 128.0) + 0.5 + 256.0) - 256i32))
            out.pixels[at + 3usize] = 255u8
            pxl += 1usize
        }
        py += 1usize
    }
    ret ok
}

fn chroma_sample(plane: []u8, stride: usize, w: usize, h: usize, x: usize, y: usize) -> f32 {
    let sx = (f32(x) + 0.5) / 2.0 - 0.5
    let sy = (f32(y) + 0.5) / 2.0 - 0.5
    var x0 = 0i32
    if sx > 0.0 { x0 = i32(sx) }
    var y0 = 0i32
    if sy > 0.0 { y0 = i32(sy) }
    var wx = sx - f32(x0)
    var wy = sy - f32(y0)
    if wx < 0.0 { wx = 0.0 }
    if wy < 0.0 { wy = 0.0 }
    var x1 = x0 + 1i32
    var y1 = y0 + 1i32
    if x1 >= i32(w) { x1 = i32(w) - 1i32 }
    if y1 >= i32(h) { y1 = i32(h) - 1i32 }
    let top = f32(plane[usize(y0) * stride + usize(x0)]) * (1.0 - wx) + f32(plane[usize(y0) * stride + usize(x1)]) * wx
    let bottom = f32(plane[usize(y1) * stride + usize(x0)]) * (1.0 - wx) + f32(plane[usize(y1) * stride + usize(x1)]) * wx
    ret top * (1.0 - wy) + bottom * wy
}

// ------------------------------------------------------------------ ALPH

fn apply_alpha(a: *mem.Arena, chunk: []const u8, out: image.Image) -> err {
    if chunk.len < 1usize { ret Invalid }
    let method = u32(chunk[0]) & 3u32
    let filter = (u32(chunk[0]) >> 2u32) & 3u32
    let w = usize(out.width)
    let h = usize(out.height)
    let (alpha, alpha_error) = mem.alloc[u8](a, w * h)
    if alpha_error != ok { ret alpha_error }
    if method == 0u32 {
        if chunk.len < 1usize + w * h { ret Invalid }
        mem.copy[u8](alpha, chunk[1usize..1usize + w * h])
    } else if method == 1u32 {
        let (pixels, pixels_error) = decode_lossless_stream(a, chunk[1usize..], w, h)
        if pixels_error != ok { ret pixels_error }
        var i = 0usize
        while i < w * h {
            alpha[i] = u8((pixels[i] >> 8u32) & 255u32)
            i += 1usize
        }
    } else {
        ret Invalid
    }
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            var pred = 0i32
            if filter != 0u32 {
                if x == 0usize && y == 0usize {
                    pred = 0i32
                } else if y == 0usize {
                    pred = i32(alpha[x - 1usize])
                } else if x == 0usize {
                    pred = i32(alpha[(y - 1usize) * w])
                } else if filter == 1u32 {
                    pred = i32(alpha[y * w + x - 1usize])
                } else if filter == 2u32 {
                    pred = i32(alpha[(y - 1usize) * w + x])
                } else {
                    pred = i32(clamp255(i32(alpha[y * w + x - 1usize]) + i32(alpha[(y - 1usize) * w + x]) - i32(alpha[(y - 1usize) * w + x - 1usize])))
                }
            }
            if filter != 0u32 { alpha[y * w + x] = u8((pred + i32(alpha[y * w + x])) & 255i32) }
            out.pixels[y * out.stride + x * 4usize + 3usize] = alpha[y * w + x]
            x += 1usize
        }
        y += 1usize
    }
    ret ok
}

// ------------------------------------------------------------------ decode

fn decode(a: *mem.Arena, source: io.Reader, options: DecodeOptions) -> (image.Image, err) {
    var r = source
    let (data, read_error) = io.read_all(a, &r, READ_LIMIT)
    if read_error != ok { ret (zero, read_error) }
    let (c, c_error) = parse_container(data)
    if c_error != ok { ret (zero, c_error) }
    if c.animated && c.frames > 1u32 && !options.first_frame_only { ret (zero, Unsupported) }
    let (w, h, _, dims_error) = bitstream_dimensions(c.bitstream, c.lossless)
    if dims_error != ok { ret (zero, dims_error) }
    let within_error = within(w, h, options)
    if within_error != ok { ret (zero, within_error) }
    let info = info_of(c)
    let (out, out_error) = image.allocate(a, w, h, .Rgba8, info.alpha)
    if out_error != ok { ret (zero, out_error) }
    if c.lossless {
        let lossless_error = decode_lossless(a, c.bitstream, w, h, out)
        if lossless_error != ok { ret (zero, lossless_error) }
    } else {
        let lossy_error = decode_lossy(a, c.bitstream, out)
        if lossy_error != ok { ret (zero, lossy_error) }
        if c.alpha.len > 0usize {
            let alpha_error = apply_alpha(a, c.alpha, out)
            if alpha_error != ok { ret (zero, alpha_error) }
        }
    }
    ret (out, ok)
}

// ------------------------------------------------------------------ encode (lossless)

type LWriter = struct { sink: *io.Writer, buffer: [4096]u8, filled: usize, cache: u64, count: u32, total: usize }

fn lflush(w: *LWriter) -> err {
    if w.filled == 0usize { ret ok }
    let write_error = io.write_all(w.sink, w.buffer[..w.filled])
    w.total += w.filled
    w.filled = 0usize
    ret write_error
}

fn lput(w: *LWriter, value: u32, n: u32) -> err {
    w.cache = w.cache | (u64(value & ((1u32 << n) - 1u32)) << w.count)
    w.count += n
    while w.count >= 8u32 {
        if w.filled >= w.buffer.len { try lflush(w) }
        w.buffer[w.filled] = u8(w.cache & 255u64)
        w.filled += 1usize
        w.cache = w.cache >> 8u32
        w.count -= 8u32
    }
    ret ok
}

fn lput_byte(w: *LWriter, b: u8) -> err {
    ret lput(w, u32(b), 8u32)
}

// A flat eight-bit code over 256 symbols, written with the normal code length code:
// the length code has two symbols (0 and 8) of one bit each.
fn put_flat_code(w: *LWriter, alphabet: usize) -> err {
    try lput(w, 0u32, 1u32)
    // num_code_lengths = 4 + 15 = 19: in kCodeLengthCodeOrder, symbol 0 is position 2
    // and symbol 8 is position 11; every other length is 0.
    try lput(w, 15u32, 4u32)
    var i = 0usize
    while i < 19usize {
        var length = 0u32
        if code_length_order(i) == 0usize || code_length_order(i) == 8usize { length = 1u32 }
        try lput(w, length, 3u32)
        i += 1usize
    }
    // max_symbol: written as the whole alphabet (bit 0 = use the alphabet size).
    try lput(w, 0u32, 1u32)
    // Code lengths: symbol 0 has code "0" and symbol 8 code "1" (canonical order).
    i = 0usize
    while i < alphabet {
        var bit = 0u32
        if i < 256usize { bit = 1u32 }
        try lput(w, bit, 1u32)
        i += 1usize
    }
    ret ok
}

fn reverse8(v: u32) -> u32 {
    var out = 0u32
    var i = 0u32
    while i < 8u32 {
        out = (out << 1u32) | ((v >> i) & 1u32)
        i += 1u32
    }
    ret out
}

fn encode(writer: *io.Writer, value: image.ConstImage, options: EncodeOptions) -> err {
    if !options.lossless { ret Unsupported }
    if value.format == .Rgba16Float { ret Unsupported }
    if value.width == 0u32 || value.height == 0u32 || value.width > 16384u32 || value.height > 16384u32 { ret Invalid }
    let (_, size_error) = image.required_bytes(value.width, value.height, value.format, value.stride)
    if size_error != ok { ret Invalid }
    let w = usize(value.width)
    let h = usize(value.height)
    let bpp = image.bytes_per_pixel(value.format)
    // The VP8L payload: 5 header bytes, then bits: 0 (no transform), 0 (no cache),
    // 0 (one group), five codes, then 32 bits per pixel; padded to a byte.
    // A flat code costs 1 + 4 + 19 * 3 + 1 bits of header plus one bit per symbol.
    let payload_bits = 5usize * 8usize + 3usize + (63usize + 280usize) + 3usize * (63usize + 256usize) + 4usize + 32usize * w * h
    let payload = (payload_bits + 7usize) / 8usize
    let riff_size = 4usize + 8usize + payload + (payload & 1usize)
    var head: [20]u8 = zero
    head[0] = 82u8
    head[1] = 73u8
    head[2] = 70u8
    head[3] = 70u8
    head[4] = u8(riff_size & 255usize)
    head[5] = u8((riff_size >> 8u32) & 255usize)
    head[6] = u8((riff_size >> 16u32) & 255usize)
    head[7] = u8((riff_size >> 24u32) & 255usize)
    head[8] = 87u8
    head[9] = 69u8
    head[10] = 66u8
    head[11] = 80u8
    head[12] = 86u8
    head[13] = 80u8
    head[14] = 56u8
    head[15] = 76u8
    head[16] = u8(payload & 255usize)
    head[17] = u8((payload >> 8u32) & 255usize)
    head[18] = u8((payload >> 16u32) & 255usize)
    head[19] = u8((payload >> 24u32) & 255usize)
    try io.write_all(writer, head[0..])
    var lw: LWriter = zero
    lw.sink = writer
    try lput_byte(&lw, 47u8)
    try lput(&lw, u32(w - 1usize), 14u32)
    try lput(&lw, u32(h - 1usize), 14u32)
    var alpha_used = 0u32
    if value.alpha != .Opaque && value.format != .R8 { alpha_used = 1u32 }
    try lput(&lw, alpha_used, 1u32)
    try lput(&lw, 0u32, 3u32)
    try lput(&lw, 0u32, 1u32)
    try lput(&lw, 0u32, 1u32)
    try lput(&lw, 0u32, 1u32)
    try put_flat_code(&lw, 280usize)
    try put_flat_code(&lw, 256usize)
    try put_flat_code(&lw, 256usize)
    try put_flat_code(&lw, 256usize)
    // Distance: a simple code with the single symbol 0.
    try lput(&lw, 1u32, 1u32)
    try lput(&lw, 0u32, 1u32)
    try lput(&lw, 0u32, 1u32)
    try lput(&lw, 0u32, 1u32)
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            let at = y * value.stride + x * bpp
            var red = 0u32
            var green = 0u32
            var blue = 0u32
            var alpha = 255u32
            if value.format == .R8 {
                red = u32(value.pixels[at])
                green = red
                blue = red
            } else if value.format == .Bgra8 {
                blue = u32(value.pixels[at])
                green = u32(value.pixels[at + 1usize])
                red = u32(value.pixels[at + 2usize])
                if alpha_used == 1u32 { alpha = u32(value.pixels[at + 3usize]) }
            } else {
                red = u32(value.pixels[at])
                green = u32(value.pixels[at + 1usize])
                blue = u32(value.pixels[at + 2usize])
                if alpha_used == 1u32 { alpha = u32(value.pixels[at + 3usize]) }
            }
            // Canonical codes are the symbols themselves, packed most significant bit first.
            try lput(&lw, reverse8(green), 8u32)
            try lput(&lw, reverse8(red), 8u32)
            try lput(&lw, reverse8(blue), 8u32)
            try lput(&lw, reverse8(alpha), 8u32)
            x += 1usize
        }
        y += 1usize
    }
    if lw.count > 0u32 { try lput(&lw, 0u32, 8u32 - lw.count) }
    try lflush(&lw)
    if lw.total != payload { ret Invalid }
    if (payload & 1usize) != 0usize {
        var pad: [1]u8 = zero
        try io.write_all(writer, pad[0..])
    }
    ret ok
}
