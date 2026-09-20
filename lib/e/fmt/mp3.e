// MPEG audio Layer III decoding (MPEG-1, MPEG-2 and MPEG-2.5), a port of minimp3
// (lieff, CC0): frame sync, side information, scalefactors, Huffman, requantisation,
// mid/side and intensity stereo, reordering, alias reduction, IMDCT and the polyphase
// synthesis filterbank. Layers I and II and free-format streams answer `Unsupported`.
//
// The whole stream is in memory, so the bit reservoir is a window over the last frames'
// main data and `seek` is a header walk: it restarts two frames before the target so the
// overlap and the reservoir are warm when the target's samples are delivered. A frame
// whose reservoir reaches before the start (the first frames after `open` or a seek)
// decodes as silence rather than being dropped, so `granule` always counts one PCM
// frame per stream frame and `frames` is the exact total. ID3v2 at the front and ID3v1
// at the back are skipped; a damaged header resynchronises on the next valid one.
//
// `decode_into` fills the caller's buffer -- whose rate and channel count must match
// `format` -- from `granule` on and answers the frames written, 0 at the end. Samples
// are 16-bit as the reference decoder rounds them, so a decode agrees with minimp3 and
// ffmpeg to the last bit or one beside it. The tables (`huff_*`, `scf_*`, `synth_window`)
// are minimp3's, emitted by the fixture's `reference.py`.

use e.audio
use e.math
use e.mem

type Decoder = struct { bytes: []const u8, at: usize, format: audio.Format, frames: usize, granule: usize, state: *void }
error Invalid
error Unsupported

const RESERVOIR: usize = 511usize
const MAX_FRAME: usize = 2304usize
const MAX_SCFI: i32 = 44i32

type Bits = struct { data: []const u8, pos: usize, limit: usize }

type Granule = struct {
    sfb: str,
    part_23_length: u32,
    big_values: u32,
    scalefac_compress: u32,
    global_gain: u32,
    block_type: u32,
    mixed_block_flag: u32,
    n_long_sfb: u32,
    n_short_sfb: u32,
    table_select: [3]u32,
    region_count: [3]u32,
    subblock_gain: [3]u32,
    preflag: u32,
    scalefac_scale: u32,
    count1_table: u32,
    scfsi: u32,
}

type State = struct {
    hdr: []u8,
    reserv: usize,
    reserv_buf: []u8,
    maindata: []u8,
    overlap: []f32,
    qmf: []f32,
    grbuf: []f32,
    scf: []f32,
    syn: []f32,
    ist_pos: []u8,
    iscf: []u8,
    gr: []Granule,
    pow43: []f32,
    pcm: []i16,
    pcm_count: usize,
    pcm_read: usize,
    start: usize,
    end: usize,
}

// The Huffman reader: a 32-bit cache over the main data, as minimp3 keeps it.
type Cache = struct { data: []const u8, next: usize, cache: u32, sh: i32 }

fn huff_tabs() -> str { ret "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x11\x03\x11\x03\x11\x03\x11\x03\x10\x03\x10\x03\x10\x03\x10\x03\x01\x02\x01\x02\x01\x02\x01\x02\x01\x02\x01\x02\x01\x02\x01\x02\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x01\xff!\x05\x12\x05\x02\x05\x11\x03\x11\x03\x11\x03\x11\x03\x10\x03\x10\x03\x10\x03\x10\x03\x01\x03\x01\x03\x01\x03\x01\x03\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\"\x01 \x01\x01\xff!\x05\x12\x05\x02\x05\x01\x03\x01\x03\x01\x03\x01\x03\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x10\x02\x10\x02\x10\x02\x10\x02\x10\x02\x10\x02\x10\x02\x10\x02\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02\"\x01 \x01\x03\xff\xc2\xfe\xa1\xfe\x91\xfe\x11\x03\x11\x03\x11\x03\x11\x03\x10\x03\x10\x03\x10\x03\x10\x03\x01\x03\x01\x03\x01\x03\x01\x03\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x013\x032\x03#\x02#\x02\x13\x01\x13\x01\x13\x01\x13\x011\x020\x02\x03\x02\"\x02!\x01\x12\x01 \x01\x02\x01\x02\xff\xe1\xfe1\x05\x13\x05\"\x05 \x05!\x04!\x04\x12\x04\x12\x04\x02\x04\x02\x04\x10\x03\x10\x03\x10\x03\x10\x03\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x01\x03\x01\x03\x01\x03\x01\x03\x00\x03\x00\x03\x00\x03\x00\x033\x020\x022\x012\x01#\x01\x03\x01\x04\xffc\xfe#\xfe\xe2\xfd\x12\x05\xc1\xfd\x11\x04\x11\x04\x10\x03\x10\x03\x10\x03\x10\x03\x01\x03\x01\x03\x01\x03\x01\x03\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x81\xfeq\xfeS\x04D\x04R\x04%\x04Q\x03Q\x03\x15\x03\x15\x03P\x04C\x04\x05\x03\x05\x034\x043\x04U\x01T\x01E\x015\x01B\x03$\x03A\x02A\x02\x14\x02\x14\x02\x04\x02\x04\x02@\x032\x03#\x030\x031\x021\x02\x13\x02\x13\x02\x03\x02\"\x02!\x01!\x01 \x01\x02\x01\x04\xffS\xfe\x13\xfe\xd1\xfd!\x04!\x04\x12\x04\x12\x04\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x11\x02\x10\x03\x10\x03\x10\x03\x10\x03\x01\x03\x01\x03\x01\x03\x01\x03\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02\x82\xfe5\x04a\xfeR\x04%\x04P\x04Q\x03Q\x03\x15\x03\x15\x03C\x044\x04\x05\x043\x04B\x03B\x03U\x02E\x02T\x01T\x01S\x01D\x01$\x03A\x03\x14\x02\x14\x02@\x03\x04\x032\x03#\x031\x03\x13\x030\x03\x03\x03\"\x01\"\x01\"\x01\"\x01 \x01\x02\x01\x03\xff\xa3\xfeb\xfeA\xfe1\xfe1\x05\x13\x05!\xfe\"\x05 \x05!\x04!\x04\x12\x04\x12\x04\x02\x04\x02\x04\x11\x03\x11\x03\x11\x03\x11\x03\x10\x03\x10\x03\x10\x03\x10\x03\x01\x03\x01\x03\x01\x03\x01\x03\x00\x03\x00\x03\x00\x03\x00\x03\xc1\xfeS\x035\x03\xb1\xfeD\x03R\x03%\x03Q\x03U\x01T\x01E\x01P\x01\x15\x02\x15\x02C\x02C\x024\x024\x02\x05\x03@\x03B\x02$\x023\x02\x04\x02A\x01\x14\x012\x01#\x010\x01\x03\x01\x05\xff\xc4\xfd#\xfd\xc2\xfc\xa1\xfc\x91\xfc\x11\x04\x11\x04\x10\x03\x10\x03\x10\x03\x10\x03\x01\x03\x01\x03\x01\x03\x01\x03\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x01\xfe\xf1\xfd\xe1\xfdt\x05G\x05e\x05V\x05s\x057\x05d\x05\xd1\xfd6\x05r\x04r\x04'\x04'\x04F\x05p\x05\x07\x04\x07\x04&\x04&\x04T\x05S\x05`\x04`\x045\x05D\x05q\x03q\x03q\x03q\x03w\x01v\x01g\x01u\x01W\x01f\x01U\x01E\x01\x17\x03\x17\x03c\x04b\x04A\xfdQ\x04\x15\x041\xfda\x03a\x03\x16\x03\x16\x03\x06\x03\x06\x03P\x04\x05\x04R\x01%\x01C\x014\x01\xe1\xfc\xd1\xfcA\x03\x14\x03\x04\x032\x03#\x030\x03B\x01$\x013\x01@\x011\x02\x13\x02\x03\x02\"\x02!\x01\x12\x01 \x01\x02\x01\x05\xff\xf3\xfd\xa3\xfdS\xfd\x03\xfd\xc1\xfc\xb2\xfc\x12\x05!\x04!\x04 \x05\x02\x05\x11\x03\x11\x03\x11\x03\x11\x03\x10\x03\x10\x03\x10\x03\x10\x03\x01\x03\x01\x03\x01\x03\x01\x03\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02\x00\x02w\x05v\x05g\x05W\x05f\x05t\x05G\x05\x01\xfee\x05V\x05s\x04s\x047\x047\x04d\x04d\x04T\x05E\x05S\x055\x05r\x03r\x03r\x03r\x03'\x03'\x03'\x03'\x03F\x04F\x04p\x04p\x04u\x01U\x01\x17\x02\x17\x02q\x03\x07\x03c\x036\x03\x06\x03\xb1\xfdD\x01R\x01a\xfdQ\x03&\x02&\x02b\x03`\x03a\x02a\x02%\x01P\x01\x16\x02\x16\x02\x15\x03C\x03\x05\x03\x11\xfdB\x03$\x034\x013\x01A\x03\x14\x03@\x03\x04\x032\x022\x02#\x02#\x021\x01\x13\x010\x02\x03\x02\"\x01\"\x01\x04\xffs\xfe#\xfe\xd3\xfd\x92\xfds\xfd1\xfd!\xfd\x12\xfd1\x05\x13\x05\"\x05!\x04!\x04\x12\x04\x12\x04 \x05\x02\x05\x00\x04\x00\x04\x11\x03\x11\x03\x11\x03\x11\x03\x10\x03\x10\x03\x10\x03\x10\x03\x01\x03\x01\x03\x01\x03\x01\x03\x81\xfeg\x04u\x04W\x04f\x04t\x04G\x04V\x04e\x03e\x03s\x03s\x037\x04U\x04r\x03r\x03w\x01v\x01'\x03d\x03F\x03q\x03\x17\x031\xfec\x036\x03p\x01\x07\x01T\x03E\x03D\x03\xe1\xfdb\x02b\x02&\x02&\x02`\x01P\x01\x16\x02\x16\x02a\x03\x06\x03S\x035\x03R\x03%\x03Q\x02\x15\x02C\x024\x02\x05\x03@\x03B\x02B\x02$\x02$\x02A\x02A\x023\x01\x14\x012\x01#\x01\x04\x020\x02\x03\x01\x03\x01\x06\xff\xc5\xf75\xf64\xf5\xa3\xf4b\xf4A\xf41\xf4\x11\x04\x11\x04\x10\x04\x10\x04\x01\x03\x01\x03\x01\x03\x01\x03\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x01\xfd\xe4\xfbC\xfb\x03\xfb\xb2\xfa\x83\xfaC\xfa\x01\xfa\xf2\xf9\xd2\xf9\xb2\xf9\x91\xf9\x82\xf9b\xf9B\xf9!\xf9\x12\xf9\xf1\xf8\xe2\xf8\xc2\xf8\xa2\xf8\x1d\x06\x81\xf8q\xf8a\xf8Q\xf8\xc3\x06\xc2\x06,\x06\xb5\x06A\xf8\xc1\x06\x1c\x061\xf8\x0c\x06!\xf8\x11\xf8\xb3\x06;\x06\x01\xf8\xb2\x06\xf1\xf7J\x06\xe1\xf7I\x06\xd1\xf7+\x05+\x05\xb1\x05\xb1\x05\x1b\x05\x1b\x05\xb0\x06\x0b\x06i\x06\xa4\x06\xa3\x06:\x06\x95\x06Y\x06\xa2\x05\xa2\x05*\x05*\x05\xf4\xfc3\xfcr\xfc\xff\x04\xfe\x04\xfd\x04\xee\x04\xfc\x04\xed\x04\xfb\x04\xbf\x04\xec\x04\xcd\x04A\xfc\xce\x03\xce\x03\xdd\x03\xdd\x03Q\xfc\xdf\x02\xde\x01\xde\x01\xef\x01\xcf\x01\xfa\x01\x9e\x01\xf1\xfb\xeb\x03\xbe\x03\xf9\x03\x9f\x03\xae\x03\xdb\x03\xbd\x03\xaf\x01\xdc\x01\xf8\x04\x8f\x04\xcc\x04a\xfb\xe8\x04Q\xfb\x7f\x03\x7f\x03\xad\x03\xad\x03\xda\x04\xcb\x04\xbc\x04o\x04\xf6\x03\xf6\x03\xea\x01\xe9\x01\xf7\x01\xe7\x01\x8e\x03\xf5\x03\xd9\x03\x9d\x03_\x03~\x03\xca\x03\xbb\x03\xf4\x03O\x03\xc1\xfa?\x03\xf3\x02\xf3\x02\xd8\x03\x8d\x03\xac\x01n\x01\xf2\x02/\x02\x91\xfa\xf0\x02\xe6\x01\xc9\x01\x9c\x03\xe5\x03\xba\x02\xba\x02\xd7\x03}\x03\xe4\x02\xe4\x02\x8c\x03m\x03\xe3\x02\xe3\x02\x9b\x02\x9b\x02\xb9\x03\xaa\x03\xf1\x01\x1f\x01\x0f\x01\x0f\x01\xab\x02^\x02N\x02\xc8\x02\xd6\x02>\x02.\x01.\x01\xe2\x02\xe0\x02\xe1\x01\x1e\x01\x0e\x02\xd5\x02]\x02\xc7\x02|\x02\xd4\x02\xb8\x02\x8b\x02M\x02\xa9\x02\x9a\x02\xc6\x02l\x01\xd3\x01=\x02\xb7\x02\xd2\x01\xd2\x01-\x01\xd1\x01{\x01{\x01\xc5\x02\\\x02\x99\x02\xa7\x02<\x01<\x01z\x02y\x02\xb4\x01\xb4\x01\xd0\x01\x0d\x01\xa8\x01\x8a\x01\xc4\x01L\x01\xb6\x01k\x01[\x01\x98\x01\x89\x01\xc0\x01K\x01\xa6\x01j\x01\x97\x01\x88\x01\xa5\x01Z\x01\x96\x01\x87\x01x\x01w\x01g\x01\xa1\x05\x1a\x05\xc1\xf6\x0a\x05\xb1\xf69\x05\xa1\xf6\x91\xf6\x92\x05)\x05\x81\xf6\x83\x058\x05q\xf6a\xf6Q\xf6\x91\x04\x91\x04\x19\x04\x19\x04\x90\x05\x09\x05\x84\x05H\x05'\x05A\xf6\x82\x04\x82\x04(\x04(\x04\x81\x04\x81\x04\xa0\x01\x86\x01h\x01\x94\x01\x93\x01\x85\x01X\x01v\x01u\x01W\x01f\x01t\x01G\x01e\x01V\x017\x01d\x01F\x01s\x05r\x05q\x04q\x04\x17\x04\x17\x04U\x05p\x05\x07\x05c\x056\x05T\x05E\x05b\x05&\x05S\x05\x18\x03\x18\x03\x18\x03\x18\x03\x80\x04\x80\x04\x08\x04\x08\x04a\x04a\x04\x16\x04\x16\x04`\x04`\x04\x06\x04\x06\x04\xb1\xf4R\x04%\x04P\x04Q\x03Q\x03\x15\x03\x15\x03C\x044\x04\x05\x04B\x04$\x043\x04A\x03A\x035\x01D\x01\x14\x02\x14\x02@\x03\x04\x032\x03#\x031\x021\x02\x13\x020\x02\x03\x02\"\x02!\x01\x12\x01 \x01\x02\x01\x06\xffe\xfb\xd5\xf9\xd4\xf84\xf8\xb4\xf73\xf7\xe3\xf6\x93\xf6S\xf6\x12\xf6\xf2\xf5\xd1\xf5\xc2\xf5\xa1\xf5\"\x05!\x05\x12\x05 \x05\x02\x05\x11\x03\x11\x03\x11\x03\x11\x03\x10\x04\x10\x04\x01\x04\x01\x04\x00\x03\x00\x03\x00\x03\x00\x03\x02\xfd\xe2\xfc\xc2\xfc\xa2\xfc\x81\xfcq\xfca\xfcQ\xfcA\xfc1\xfc!\xfc\x11\xfc\x01\xfc\xf1\xfb\xe1\xfb\xd2\xfb\xbc\x06o\x06\xb1\xfb\xa1\xfb_\x06\xe7\x06~\x06\xca\x06\xac\x06\xbb\x06\x91\xfb\xf4\x06O\x06\xf3\x06?\x06\x8d\x06n\x06\xf2\x06/\x06\x81\xfb\xf1\x06\x1f\x06\xc9\x06\x9c\x06\xe5\x06\xba\x06\xab\x06^\x06\xd7\x06}\x06\xe4\x06N\x06\xc8\x06\x8c\x06\xe3\x06\xd6\x06m\x06>\x06\xb9\x06\x9b\x06\xe2\x06\xaa\x06.\x06\xe1\x06\x1e\x06q\xfb\xd5\x06]\x06\xff\x02\xfe\x02\xef\x02\xfd\x02\xee\x01\xee\x01\xdf\x02\xfc\x02\xcf\x02\xed\x02\xde\x02\xfb\x02\xbf\x01\xbf\x01\xec\x02\xce\x02\xdd\x01\xfa\x01\xaf\x01\xeb\x01\xbe\x01\xdc\x01\xcd\x01\xf9\x01\x9f\x01\xae\x01\xdb\x01\xbd\x01\xf8\x01\x8f\x01\xcc\x01\xe9\x01\x9e\x01\xf7\x01\x7f\x01\xda\x01\xad\x01\xcb\x01\xf6\x01\xf6\x01\xea\x02\xf0\x02\xe8\x01\x8e\x01\xf5\x01\xd9\x01\x9d\x01\xd8\x01\xe6\x01\x0f\x01\xe0\x01\x0e\x01a\xfaQ\xfaM\x05A\xfa1\xfa!\xfa=\x05-\x05\x11\xfa\xd1\x05\xb7\x05{\x05\x1d\x05\x01\xfa\\\x05\xa8\x05\x8a\x05\xc4\x05L\x05\xb6\x05k\x05\xf1\xf9\xc3\x05<\x05\xa7\x05z\x05j\x05\xe1\xf9,\x04,\x04\xc2\x05\xb5\x05\xc7\x01|\x01\xd4\x01\xb8\x01\x8b\x01\xa9\x01\x9a\x01\xc6\x01l\x01\xd3\x01\xd2\x01\xd0\x01\xc5\x01\x0d\x01\x99\x01\xc0\x01\x0c\x01\xb0\x01[\x05\xc1\x05\x98\x05\x89\x05\x1c\x05\xb4\x05K\x05\xa6\x05\xb3\x05\x97\x05;\x04;\x04y\x05\x88\x05\xb2\x05\xa5\x05+\x04+\x04Z\x05\xb1\x05\x1b\x04\x1b\x04\x0b\x05\x96\x05i\x05\xa4\x05J\x05\x87\x05x\x05\xa3\x05:\x04:\x04\x95\x04Y\x04\xa2\x04*\x04\xa1\x04\x1a\x04Q\xf8\x86\x04h\x04\x94\x04I\x04\x93\x049\x04A\xf8\x85\x04X\x04\xa0\x01\x0a\x01w\x01\x90\x01\x92\x04v\x04g\x04)\x04\x19\x03\x19\x03\x91\x04\x09\x04\x84\x04H\x04u\x04W\x04\x83\x048\x04f\x04t\x04\x82\x03\x82\x03(\x03(\x03\x81\x03\x81\x03\x18\x03\x18\x03G\x04\x80\x04\x08\x04e\x04V\x04s\x047\x04d\x04r\x03'\x03F\x03q\x03U\x03\x17\x03\xf1\xf6c\x03p\x01\x07\x016\x03T\x03E\x03b\x03&\x03a\x03\xa1\xf6S\x03`\x01\x06\x01\x16\x02\x16\x025\x03D\x03R\x02R\x02%\x02%\x02Q\x02Q\x02\x15\x02\x15\x02P\x03\x05\x03C\x02C\x024\x02B\x02$\x023\x02\x14\x01\x14\x01A\x02@\x022\x01#\x01\x04\x020\x021\x011\x01\x13\x01\x03\x01\x05\xff\x84\xfc\xf6\xf7\xc4\xf5\xf4\xf4s\xf41\xf4!\xf4\x11\x04\x11\x04\x10\x04\x10\x04\x01\x03\x01\x03\x01\x03\x01\x03\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x00\x01\x01\xfe\xf1\xfd\xe1\xfd\xd1\xfd\xfa\x05\xc1\xfd\xb1\xfd\xf8\x05\xf7\x05\x7f\x05\xf6\x05o\x05\xff\x03\xff\x03\xff\x03\xff\x03\xf5\x05_\x05\xf4\x04\xf4\x04O\x04O\x04?\x04?\x04\x0f\x04\x0f\x04\xf3\x05\xa4\xfd/\x03/\x03/\x03/\x03\xfe\x01\xef\x01\xfd\x01\xdf\x01\xfc\x01\xcf\x01\xfb\x01\xbf\x01\xaf\x01\xf9\x01\x9f\x01\x8f\x01\"\xfd\xf2\xfc\xee\x04\xd1\xfc\xeb\x04\xdc\x04\xc1\xfc\xea\x04\xcc\x04\xb1\xfc\xa1\xfc\xac\x04\x91\xfc\xe5\x04\xdb\x03\xdb\x03\xec\x02\x01\xfd\xed\x01\xed\x01\xce\x01\xdd\x01\x9e\x01\x9e\x01\xae\x02\x9d\x02\xde\x01\xbe\x01\xcd\x01\xbd\x01\xda\x01\xad\x01\xe7\x01\xca\x01\x9c\x01\xd7\x01\xf2\x04\xf0\x04\xf1\x03\xf1\x03\x1f\x03\x1f\x03\x05\xfc\x04\xfbT\xfa\xd3\xf9s\xf9#\xf9\xe3\xf8\xa2\xf8s\xf83\xf8\xe9\x04\xe9\x04\xcb\x05\xbc\x05\xe8\x05\x8e\x05\xd9\x05~\x05\xbb\x05\xd8\x05\x8d\x05\xe6\x05n\x04n\x04\xc9\x04\xc9\x04\xba\x05\xab\x05^\x05}\x05\xe4\x04\xe4\x04N\x05\xc8\x05\x8c\x04\x8c\x04\xe3\x04\xe3\x04\xd6\x04\xd6\x04m\x05\xb9\x05\x81\xfa\x1e\x04M\x04q\xfa\xb7\x04a\xfa>\x03>\x03\xe0\x04\x0e\x04\xd5\x04]\x04\xc7\x04|\x04\xd4\x04\xb8\x04\x9b\x01\xaa\x01\x8b\x01\x9a\x01{\x01\x0d\x01\xa9\x04\xc6\x04l\x04\xd3\x04\xc5\x04\\\x04\xd0\x03\xd0\x03\xa8\x04\x8a\x04\x99\x04\xc4\x04k\x04\xa7\x04\xc3\x03\xc3\x03\x91\xf9\xc1\x03\x0c\x03\x81\xf9.\x02.\x02\xe2\x03\xe1\x03\xb5\x01\x98\x01\x89\x01\x97\x01=\x03\xd2\x03-\x03\x1d\x03\xb3\x031\xf9\xd1\x02\xd1\x02y\x01\x88\x01L\x03\xb6\x03<\x03z\x03\xc2\x02\xc2\x02,\x03[\x03\x1c\x03\xc0\x03\xb4\x03K\x03\xa6\x03j\x03;\x02;\x02\x81\xf8\xb2\x02+\x02\xb1\x02\xa5\x01Z\x01\x1b\x02\x1b\x02\xb0\x03\x0b\x03\x96\x03i\x03\xa4\x03J\x03\x87\x03x\x03:\x02:\x02\xa3\x03\x95\x03\xa2\x02\xa2\x02\xf1\xf5\x1a\x06\xe1\xf5I\x06\xd1\xf5v\x06*\x05*\x05\xa1\x05\xa1\x05\xa0\x06\x0a\x06\x93\x069\x06\x85\x06X\x06\x92\x05\x92\x05)\x05)\x05g\x06\x90\x06\x91\x05\x91\x05\x19\x05\x19\x05\x09\x06\x84\x06H\x06W\x06\x83\x068\x06f\x06\x82\x06(\x05(\x05t\x06G\x06\x81\x05\x81\x05\x18\x05\x18\x05\x08\x05\x08\x05\x80\x06e\x06s\x05s\x057\x057\x05V\x06d\x06r\x05r\x05'\x05'\x05F\x06U\x06p\x05p\x05q\x04q\x04q\x04q\x04Y\x01\x86\x01h\x01w\x01\x94\x01u\x01\x17\x04A\xf51\xf5!\xf5&\x04a\x04\x16\x04\x11\xf55\x04\x01\xf5R\x04%\x04\x15\x03\x15\x03Q\x04P\x04\x07\x01c\x016\x01T\x01E\x01b\x01`\x01\x06\x01S\x01D\x01C\x044\x04\x05\x04B\x04$\x043\x04A\x03A\x03\x14\x03\x14\x03@\x04\x04\x042\x032\x03#\x03#\x031\x021\x02\x13\x02\x13\x020\x03\x03\x03\"\x02\"\x02!\x01\x12\x01 \x01\x02\x01\x03\xff\xc3\xfe\x83\xfeB\xfe\"\xfe\x03\xfe\xff\x04\xff\x04\xd5\xfce\xfbU\xfa$\xf9\x94\xf8\x14\xf8s\xf73\xf7\xe3\xf6\x92\xf6s\xf61\xf6\"\xf6!\x05\x12\x05\x01\xf6\x11\x04\x11\x04\x10\x04\x10\x04\x01\x04\x01\x04\x00\x04\x00\x04\xfe\x03\xef\x03\xfd\x03\xdf\x03\xfc\x03\xcf\x03\xfb\x03\xbf\x03\xaf\x02\xaf\x02\xfa\x03\xf9\x03\x9f\x02\x9f\x02\x8f\x02\x8f\x02\xf8\x03\xf7\x03\x7f\x02\x7f\x02\xf6\x02\xf6\x02o\x02o\x02\xf5\x02_\x02\xf4\x02O\x02\xf3\x02?\x02\xf2\x02/\x02\x1f\x02\x1f\x02\xf1\x03\x0f\x03\xc1\xfd\x93\xfdS\xfd\x13\xfd\xf0\x01\xb2\xfd\xee\x02\xed\x02\xde\x02\xec\x02\xce\x03\xdd\x03\xeb\x03\xbe\x03\xdc\x03\xcd\x03\xea\x03\xae\x03\xdb\x03\xbd\x03\xcc\x03\xe9\x03\x9e\x03\xda\x03\xad\x03\xcb\x03\xbc\x03\xe8\x03\x8e\x03\xd9\x03\x9d\x03\xe7\x03~\x03\xca\x03\xd1\xfb\xc1\xfb\xb2\xfbn\x05\x91\xfb\x9c\x05\xe5\x05\xab\x05^\x05\x81\xfb}\x05N\x05\xc8\x05\x8c\x05q\xfb\xe3\x05\xd6\x05m\x05>\x05\xb9\x05\x9b\x05\xaa\x05.\x05\xe1\x05\x1e\x05\xd5\x05]\x05\xc7\x05|\x05\xd4\x05\xb8\x05\x8b\x05\xac\x01\xbb\x01\xd8\x01\x8d\x01\xe0\x02\x0e\x02\xd0\x01\xd0\x01\xe6\x01\xc9\x01\xba\x01\xd7\x01\xe4\x01\xe2\x01M\x05\xa9\x05\x9a\x05\xc6\x05l\x05\xd3\x05=\x05\xd2\x05-\x05\xd1\x05\xb7\x05{\x05\x1d\x05\xc5\x05\\\x05\xa8\x05\x8a\x05\x99\x05\xc4\x05L\x05\xb6\x05k\x05a\xfa\xc3\x05<\x05\xa7\x05z\x05\xc2\x05,\x05\xb5\x05[\x05\xc1\x05\x0d\x01\xc0\x01\x98\x05\x89\x05\x1c\x05\xb4\x05Q\xf9\xb3\x05A\xf9\xa1\x05K\x04K\x04\xa6\x05j\x05\x97\x05y\x051\xf9\x09\x05;\x04;\x04\x88\x04\x88\x04\xb2\x05\xa5\x05+\x04+\x04Z\x05\xb1\x05\x1b\x05\x96\x05i\x04i\x04J\x04J\x04\x0c\x01\xb0\x01\x0b\x01\xa0\x01\x0a\x01\x90\x01\xa1\xf8x\x04\xa3\x04:\x04\x95\x04Y\x04\xa2\x04*\x04\x1a\x04\x86\x04h\x04w\x04\x94\x04I\x04\x93\x049\x04\xa4\x01\x87\x01\x85\x04X\x04\x92\x04v\x04g\x04)\x04\x91\x04\x19\x04\x84\x04H\x04u\x04W\x04\x83\x048\x04f\x04\x82\x04(\x04\x81\x04t\x04G\x04\x18\x04\x91\xf7e\x04V\x04q\x04\x81\xf77\x037\x03s\x04r\x04'\x03'\x03\x80\x01\x08\x01p\x01\x07\x01d\x03F\x03U\x03\x17\x03c\x036\x03T\x03E\x03b\x03&\x03a\x03\x16\x03\xf1\xf6S\x035\x03D\x03`\x01\x06\x01R\x03%\x03Q\x03\xa1\xf6\x15\x02\x15\x02C\x034\x03P\x01\x05\x01B\x02$\x023\x02A\x02\x14\x02\x14\x02@\x03\x04\x032\x022\x02#\x02#\x021\x01\x13\x010\x02\x03\x02\"\x01\"\x01 \x01\x02\x01" }

fn huff_tab32() -> str { ret "\x82\xa2\xc1\xd1,\x1cL\x8c\x09\x09\x09\x09\x09\x09\x09\x09\xbe\xfe\xde\xee~^\x9d\x9dm=\xad\xcd" }

fn huff_tab33() -> str { ret "\xfc\xec\xdc\xcc\xbc\xac\x9c\x8c|l\\L<,\x1c\x0c" }

fn huff_index() -> str { ret "\x00\x00 \x00@\x00b\x00\x00\x00\x84\x00\xb4\x00\xda\x00$\x01l\x01\xaa\x01\x1a\x02\x88\x02\xea\x02\x00\x00f\x04\xb4\x05\xb4\x05\xb4\x05\xb4\x05\xb4\x05\xb4\x05\xb4\x05\xb4\x052\x072\x072\x072\x072\x072\x072\x072\x07" }

fn huff_linbits() -> str { ret "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04\x06\x08\x0a\x0d\x04\x05\x06\x07\x08\x09\x0b\x0d" }

fn scf_long_table() -> str { ret "\x06\x06\x06\x06\x06\x06\x08\x0a\x0c\x0e\x10\x14\x18\x1c &.4<D:6\x00\x0c\x0c\x0c\x0c\x0c\x0c\x10\x14\x18\x1c (08@LZ\x02\x02\x02\x02\x02\x00\x06\x06\x06\x06\x06\x06\x08\x0a\x0c\x0e\x10\x14\x18\x1c &.4<D:6\x00\x06\x06\x06\x06\x06\x06\x08\x0a\x0c\x0e\x10\x12\x16\x1a &.6>FL$\x00\x06\x06\x06\x06\x06\x06\x08\x0a\x0c\x0e\x10\x14\x18\x1c &.4<D:6\x00\x04\x04\x04\x04\x04\x04\x06\x06\x08\x08\x0a\x0c\x10\x14\x18\x1c\"*26L\x9e\x00\x04\x04\x04\x04\x04\x04\x06\x06\x06\x08\x0a\x0c\x10\x12\x16\x1c\"(.66\xc0\x00\x04\x04\x04\x04\x04\x04\x06\x06\x08\x0a\x0c\x10\x14\x18\x1e&.8DTf\x1a\x00" }

fn scf_short_table() -> str { ret "\x04\x04\x04\x04\x04\x04\x04\x04\x04\x06\x06\x06\x08\x08\x08\x0a\x0a\x0a\x0c\x0c\x0c\x0e\x0e\x0e\x12\x12\x12\x18\x18\x18\x1e\x1e\x1e(((\x12\x12\x12\x00\x08\x08\x08\x08\x08\x08\x08\x08\x08\x0c\x0c\x0c\x10\x10\x10\x14\x14\x14\x18\x18\x18\x1c\x1c\x1c$$$\x02\x02\x02\x02\x02\x02\x02\x02\x02\x1a\x1a\x1a\x00\x04\x04\x04\x04\x04\x04\x04\x04\x04\x06\x06\x06\x06\x06\x06\x08\x08\x08\x0a\x0a\x0a\x0e\x0e\x0e\x12\x12\x12\x1a\x1a\x1a   ***\x12\x12\x12\x00\x04\x04\x04\x04\x04\x04\x04\x04\x04\x06\x06\x06\x08\x08\x08\x0a\x0a\x0a\x0c\x0c\x0c\x0e\x0e\x0e\x12\x12\x12\x18\x18\x18   ,,,\x0c\x0c\x0c\x00\x04\x04\x04\x04\x04\x04\x04\x04\x04\x06\x06\x06\x08\x08\x08\x0a\x0a\x0a\x0c\x0c\x0c\x0e\x0e\x0e\x12\x12\x12\x18\x18\x18\x1e\x1e\x1e(((\x12\x12\x12\x00\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x06\x06\x06\x08\x08\x08\x0a\x0a\x0a\x0c\x0c\x0c\x0e\x0e\x0e\x12\x12\x12\x16\x16\x16\x1e\x1e\x1e888\x00\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x06\x06\x06\x06\x06\x06\x0a\x0a\x0a\x0c\x0c\x0c\x0e\x0e\x0e\x10\x10\x10\x14\x14\x14\x1a\x1a\x1aBBB\x00\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x04\x06\x06\x06\x08\x08\x08\x0c\x0c\x0c\x10\x10\x10\x14\x14\x14\x1a\x1a\x1a\"\"\"***\x0c\x0c\x0c\x00" }

fn scf_mixed_table() -> str { ret "\x06\x06\x06\x06\x06\x06\x06\x06\x06\x08\x08\x08\x0a\x0a\x0a\x0c\x0c\x0c\x0e\x0e\x0e\x12\x12\x12\x18\x18\x18\x1e\x1e\x1e(((\x12\x12\x12\x00\x00\x00\x00\x0c\x0c\x0c\x04\x04\x04\x08\x08\x08\x0c\x0c\x0c\x10\x10\x10\x14\x14\x14\x18\x18\x18\x1c\x1c\x1c$$$\x02\x02\x02\x02\x02\x02\x02\x02\x02\x1a\x1a\x1a\x00\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x08\x08\x08\x0a\x0a\x0a\x0e\x0e\x0e\x12\x12\x12\x1a\x1a\x1a   ***\x12\x12\x12\x00\x00\x00\x00\x06\x06\x06\x06\x06\x06\x06\x06\x06\x08\x08\x08\x0a\x0a\x0a\x0c\x0c\x0c\x0e\x0e\x0e\x12\x12\x12\x18\x18\x18   ,,,\x0c\x0c\x0c\x00\x00\x00\x00\x06\x06\x06\x06\x06\x06\x06\x06\x06\x08\x08\x08\x0a\x0a\x0a\x0c\x0c\x0c\x0e\x0e\x0e\x12\x12\x12\x18\x18\x18\x1e\x1e\x1e(((\x12\x12\x12\x00\x00\x00\x00\x04\x04\x04\x04\x04\x04\x06\x06\x04\x04\x04\x06\x06\x06\x08\x08\x08\x0a\x0a\x0a\x0c\x0c\x0c\x0e\x0e\x0e\x12\x12\x12\x16\x16\x16\x1e\x1e\x1e888\x00\x00\x04\x04\x04\x04\x04\x04\x06\x06\x04\x04\x04\x06\x06\x06\x06\x06\x06\x0a\x0a\x0a\x0c\x0c\x0c\x0e\x0e\x0e\x10\x10\x10\x14\x14\x14\x1a\x1a\x1aBBB\x00\x00\x04\x04\x04\x04\x04\x04\x06\x06\x04\x04\x04\x06\x06\x06\x08\x08\x08\x0c\x0c\x0c\x10\x10\x10\x14\x14\x14\x1a\x1a\x1a\"\"\"***\x0c\x0c\x0c\x00\x00" }

fn scf_partitions() -> str { ret "\x06\x05\x05\x05\x06\x05\x05\x05\x06\x05\x07\x03\x0b\x0a\x00\x00\x07\x07\x07\x00\x06\x06\x06\x03\x08\x08\x05\x00\x08\x09\x06\x0c\x06\x09\x09\x09\x06\x09\x0c\x06\x0f\x12\x00\x00\x06\x0f\x0c\x00\x06\x0c\x09\x06\x06\x12\x09\x00\x09\x09\x06\x0c\x09\x09\x09\x09\x09\x09\x0c\x06\x12\x12\x00\x00\x0c\x0c\x0c\x00\x0c\x09\x09\x06\x0f\x0c\x09\x00" }

fn scfc_decode() -> str { ret "\x00\x01\x02\x03\x0c\x05\x06\x07\x09\x0a\x0b\x0d\x0e\x0f\x12\x13" }

fn lsf_mod() -> str { ret "\x05\x05\x04\x04\x05\x05\x04\x01\x04\x03\x01\x01\x05\x06\x06\x01\x04\x04\x04\x01\x04\x03\x01\x01" }

fn preamp() -> str { ret "\x01\x01\x01\x01\x02\x02\x03\x03\x03\x02" }

fn synth_window() -> str { ret "\xff\xff\xff\xff\x1a\x00\x00\x00\xe1\xff\xff\xff\xd0\x00\x00\x00\xda\x00\x00\x00\x91\x01\x00\x00\xf9\xfd\xff\xff\x0f\x08\x00\x00\xd0\x07\x00\x00\xb4\x12\x00\x00s\xea\xff\xff\xde\x1b\x00\x00G\x17\x00\x008\x8b\x00\x00Xf\xff\xff\xf0$\x01\x00\xff\xff\xff\xff\x18\x00\x00\x00\xdd\xff\xff\xff\xca\x00\x00\x00\xde\x00\x00\x00[\x01\x00\x00\xbb\xfd\xff\xff \x08\x00\x00\xa0\x07\x00\x00I\x11\x00\x00\x09\xe9\xff\xff\xd8\x1d\x00\x00\xa8\x14\x00\x00\xff\x83\x00\x00(_\xff\xffh$\x01\x00\xff\xff\xff\xff\x15\x00\x00\x00\xda\xff\xff\xff\xc4\x00\x00\x00\xe1\x00\x00\x00&\x01\x00\x00{\xfd\xff\xff'\x08\x00\x00e\x07\x00\x00\xdf\x0f\x00\x00\xa3\xe7\xff\xff\x9c\x1f\x00\x00\xd1\x11\x00\x00\xcb|\x00\x00\x02X\xff\xff\x86#\x01\x00\xff\xff\xff\xff\x13\x00\x00\x00\xd7\xff\xff\xff\xbe\x00\x00\x00\xe3\x00\x00\x00\xf4\x00\x00\x009\xfd\xff\xff%\x08\x00\x00\x1e\x07\x00\x00y\x0e\x00\x00C\xe6\xff\xff,!\x00\x00\xc0\x0e\x00\x00\xa0u\x00\x00\xebP\xff\xffI\"\x01\x00\xff\xff\xff\xff\x11\x00\x00\x00\xd3\xff\xff\xff\xb7\x00\x00\x00\xe4\x00\x00\x00\xc5\x00\x00\x00\xf5\xfc\xff\xff\x1b\x08\x00\x00\xcb\x06\x00\x00\x17\x0d\x00\x00\xe9\xe4\xff\xff\x88\"\x00\x00w\x0b\x00\x00\x81n\x00\x00\xe7I\xff\xff\xb4 \x01\x00\xff\xff\xff\xff\x10\x00\x00\x00\xcf\xff\xff\xff\xb0\x00\x00\x00\xe4\x00\x00\x00\x99\x00\x00\x00\xb0\xfc\xff\xff\x09\x08\x00\x00l\x06\x00\x00\xbc\x0b\x00\x00\x99\xe3\xff\xff\xb3#\x00\x00\xf5\x07\x00\x00rg\x00\x00\xfaB\xff\xff\xc7\x1e\x01\x00\xfe\xff\xff\xff\x0e\x00\x00\x00\xcb\xff\xff\xff\xa9\x00\x00\x00\xe3\x00\x00\x00o\x00\x00\x00i\xfc\xff\xff\xf0\x07\x00\x00\xff\x05\x00\x00g\x0a\x00\x00S\xe2\xff\xff\xad$\x00\x00:\x04\x00\x00v`\x00\x00'<\xff\xff\x83\x1c\x01\x00\xfe\xff\xff\xff\x0d\x00\x00\x00\xc6\xff\xff\xff\xa1\x00\x00\x00\xe0\x00\x00\x00H\x00\x00\x00!\xfc\xff\xff\xd1\x07\x00\x00\x86\x05\x00\x00\x1a\x09\x00\x00\x1a\xe1\xff\xffx%\x00\x00F\x00\x00\x00\x91Y\x00\x00s5\xff\xff\xe9\x19\x01\x00\xfe\xff\xff\xff\x0b\x00\x00\x00\xc1\xff\xff\xff\x9a\x00\x00\x00\xdd\x00\x00\x00$\x00\x00\x00\xd8\xfb\xff\xff\xaa\x07\x00\x00\x00\x05\x00\x00\xd6\x07\x00\x00\xef\xdf\xff\xff\x16&\x00\x00\x1a\xfc\xff\xff\xc5R\x00\x00\xe2.\xff\xff\xfc\x16\x01\x00\xfe\xff\xff\xff\x0a\x00\x00\x00\xbc\xff\xff\xff\x93\x00\x00\x00\xd7\x00\x00\x00\x02\x00\x00\x00\x8f\xfb\xff\xff\x7f\x07\x00\x00k\x04\x00\x00\x9c\x06\x00\x00\xd5\xde\xff\xff\x87&\x00\x00\xb6\xf7\xff\xff\x16L\x00\x00v(\xff\xff\xbe\x13\x01\x00\xfd\xff\xff\xff\x09\x00\x00\x00\xb7\xff\xff\xff\x8b\x00\x00\x00\xd0\x00\x00\x00\xe3\xff\xff\xffF\xfb\xff\xffN\x07\x00\x00\xca\x03\x00\x00l\x05\x00\x00\xcd\xdd\xff\xff\xcf&\x00\x00\x1c\xf3\xff\xff\x87E\x00\x006\"\xff\xff/\x10\x01\x00\xfd\xff\xff\xff\x08\x00\x00\x00\xb1\xff\xff\xff\x84\x00\x00\x00\xc8\x00\x00\x00\xc7\xff\xff\xff\xfd\xfa\xff\xff\x19\x07\x00\x00\x1a\x03\x00\x00G\x04\x00\x00\xda\xdc\xff\xff\xee&\x00\x00K\xee\xff\xff\x1b?\x00\x00#\x1c\xff\xffT\x0c\x01\x00\xfc\xff\xff\xff\x07\x00\x00\x00\xab\xff\xff\xff}\x00\x00\x00\xbd\x00\x00\x00\xad\xff\xff\xff\xb4\xfa\xff\xff\xdf\x06\x00\x00]\x02\x00\x00.\x03\x00\x00\xfd\xdb\xff\xff\xe7&\x00\x00F\xe9\xff\xff\xd48\x00\x00B\x16\xff\xff-\x08\x01\x00\xfc\xff\xff\xff\x07\x00\x00\x00\xa5\xff\xff\xffu\x00\x00\x00\xb1\x00\x00\x00\x96\xff\xff\xffl\xfa\xff\xff\xa2\x06\x00\x00\x92\x01\x00\x00!\x02\x00\x008\xdb\xff\xff\xbc&\x00\x00\x0e\xe4\xff\xff\xb42\x00\x00\x97\x10\xff\xff\xbe\x03\x01\x00\xfb\xff\xff\xff\x06\x00\x00\x00\x9f\xff\xff\xffo\x00\x00\x00\xa3\x00\x00\x00\x81\xff\xff\xff&\xfa\xff\xffb\x06\x00\x00\xb9\x00\x00\x00 \x01\x00\x00\x8f\xda\xff\xffn&\x00\x00\xa4\xde\xff\xff\xbf,\x00\x00$\x0b\xff\xff\x0a\xff\x00\x00" }

fn halfrate() -> str { ret "\x00\x04\x08\x0c\x10\x14\x18\x1c (08@HP\x00\x04\x08\x0c\x10\x14\x18\x1c (08@HP\x00\x10\x18\x1c (08@HPX`p\x80\x00\x10\x14\x18\x1c (08@P`p\x80\xa0\x00\x10\x18\x1c (08@P`p\x80\xa0\xc0\x00\x10 0@P`p\x80\x90\xa0\xb0\xc0\xd0\xe0" }


fn tb(t: str, i: usize) -> u32 {
    ret u32(t[i])
}

fn t32(t: str, i: usize) -> i32 {
    let v = u32(t[4usize * i]) | (u32(t[4usize * i + 1usize]) << 8u32) | (u32(t[4usize * i + 2usize]) << 16u32) | (u32(t[4usize * i + 3usize]) << 24u32)
    ret mem.bitcast[i32](v)
}

fn t16(t: str, i: usize) -> i32 {
    let v = u32(t[2usize * i]) | (u32(t[2usize * i + 1usize]) << 8u32)
    if v >= 32768u32 { ret i32(v) - 65536i32 }
    ret i32(v)
}

// ------------------------------------------------------------------ frame headers

fn hdr_layer(h: []const u8) -> u32 { ret (u32(h[1]) >> 1u32) & 3u32 }
fn hdr_bitrate_index(h: []const u8) -> u32 { ret u32(h[2]) >> 4u32 }
fn hdr_sample_rate_index(h: []const u8) -> u32 { ret (u32(h[2]) >> 2u32) & 3u32 }
fn hdr_mpeg1(h: []const u8) -> bool { ret (u32(h[1]) & 8u32) != 0u32 }
fn hdr_not_mpeg25(h: []const u8) -> bool { ret (u32(h[1]) & 16u32) != 0u32 }
fn hdr_mono(h: []const u8) -> bool { ret (u32(h[3]) & 192u32) == 192u32 }
fn hdr_ms_stereo(h: []const u8) -> bool { ret (u32(h[3]) & 224u32) == 96u32 }
fn hdr_test_ms(h: []const u8) -> bool { ret (u32(h[3]) & 32u32) != 0u32 }
fn hdr_test_intensity(h: []const u8) -> bool { ret (u32(h[3]) & 16u32) != 0u32 }
fn hdr_crc(h: []const u8) -> bool { ret (u32(h[1]) & 1u32) == 0u32 }
fn hdr_padding(h: []const u8) -> usize {
    if (u32(h[2]) & 2u32) != 0u32 { ret 1usize }
    ret 0usize
}
fn hdr_layer1(h: []const u8) -> bool { ret (u32(h[1]) & 6u32) == 6u32 }
fn hdr_frame_576(h: []const u8) -> bool { ret (u32(h[1]) & 14u32) == 2u32 }

fn hdr_my_sample_rate(h: []const u8) -> u32 {
    ret hdr_sample_rate_index(h) + (((u32(h[1]) >> 3u32) & 1u32) + ((u32(h[1]) >> 4u32) & 1u32)) * 3u32
}

fn hdr_valid(h: []const u8) -> bool {
    if h.len < 4usize || u32(h[0]) != 255u32 { ret false }
    let b1 = u32(h[1])
    if (b1 & 240u32) != 240u32 && (b1 & 254u32) != 226u32 { ret false }
    ret hdr_layer(h) != 0u32 && hdr_bitrate_index(h) != 15u32 && hdr_sample_rate_index(h) != 3u32
}

fn hdr_compare(h1: []const u8, h2: []const u8) -> bool {
    if !hdr_valid(h2) { ret false }
    if ((u32(h1[1]) ^ u32(h2[1])) & 254u32) != 0u32 { ret false }
    if ((u32(h1[2]) ^ u32(h2[2])) & 12u32) != 0u32 { ret false }
    ret ((u32(h1[2]) & 240u32) == 0u32) == ((u32(h2[2]) & 240u32) == 0u32)
}

fn hdr_bitrate_kbps(h: []const u8) -> u32 {
    var v = 0usize
    if hdr_mpeg1(h) { v = 1usize }
    ret 2u32 * tb(halfrate(), v * 45usize + usize(hdr_layer(h) - 1u32) * 15usize + usize(hdr_bitrate_index(h)))
}

fn hdr_sample_rate_hz(h: []const u8) -> u32 {
    var hz = 44100u32
    let index = hdr_sample_rate_index(h)
    if index == 1u32 { hz = 48000u32 }
    if index == 2u32 { hz = 32000u32 }
    if !hdr_mpeg1(h) { hz = hz >> 1u32 }
    if !hdr_not_mpeg25(h) { hz = hz >> 1u32 }
    ret hz
}

fn hdr_frame_samples(h: []const u8) -> usize {
    if hdr_layer1(h) { ret 384usize }
    if hdr_frame_576(h) { ret 576usize }
    ret 1152usize
}

// Zero for a free-format stream, which this decoder does not take.
fn hdr_frame_bytes(h: []const u8) -> usize {
    var bytes = hdr_frame_samples(h) * usize(hdr_bitrate_kbps(h)) * 125usize / usize(hdr_sample_rate_hz(h))
    if hdr_layer1(h) { bytes = bytes & 18446744073709551612usize }
    ret bytes
}

// The following frames agree with this header, as far as the data reaches.
fn match_frame(d: []const u8, at: usize, frame_bytes: usize) -> bool {
    var i = at
    var matches = 0usize
    while matches < 10usize {
        i += hdr_frame_bytes(d[i..]) + hdr_padding(d[i..])
        if i + 4usize > d.len { ret matches > 0usize }
        if !hdr_compare(d[at..], d[i..]) { ret false }
        matches += 1usize
    }
    ret true
}

// The next frame at or after `from`, and its size with padding; `d.len` when none.
fn find_frame(d: []const u8, from: usize) -> (usize, usize) {
    var i = from
    while i + 4usize <= d.len {
        let h = d[i..]
        if hdr_valid(h) {
            let frame_bytes = hdr_frame_bytes(h)
            let whole = frame_bytes + hdr_padding(h)
            if frame_bytes != 0usize && i + whole <= d.len && (match_frame(d, i, frame_bytes) || (i == from && i + whole == d.len)) {
                ret (i, whole)
            }
        }
        i += 1usize
    }
    ret (d.len, 0usize)
}

// ------------------------------------------------------------------ bit reading

fn get_bits(bs: *Bits, n: u32) -> u32 {
    let s = u32(bs.pos & 7usize)
    var shl = i32(n) + i32(s)
    var p = bs.pos >> 3u32
    bs.pos += usize(n)
    if bs.pos > bs.limit { ret 0u32 }
    var next = u32(bs.data[p]) & (255u32 >> s)
    p += 1usize
    var cache = 0u32
    shl -= 8i32
    while shl > 0i32 {
        cache = cache | (next << u32(shl))
        next = 0u32
        if p < bs.data.len { next = u32(bs.data[p]) }
        p += 1usize
        shl -= 8i32
    }
    ret cache | (next >> u32(0i32 - shl))
}

// ------------------------------------------------------------------ side information

fn read_side_info(bs: *Bits, gr: []Granule, h: []const u8) -> (i32, bool) {
    var sr_idx = usize(hdr_my_sample_rate(h))
    if sr_idx != 0usize { sr_idx -= 1usize }
    var gr_count = 2usize
    if hdr_mono(h) { gr_count = 1usize }
    var main_data_begin = 0i32
    var scfsi = 0u32
    if hdr_mpeg1(h) {
        gr_count *= 2usize
        main_data_begin = i32(get_bits(bs, 9u32))
        scfsi = get_bits(bs, 7u32 + u32(gr_count))
    } else {
        main_data_begin = i32(get_bits(bs, 8u32 + u32(gr_count)) >> u32(gr_count))
    }
    var part_23_sum = 0usize
    var g = 0usize
    while g < gr_count {
        if hdr_mono(h) { scfsi = scfsi << 4u32 }
        gr[g].part_23_length = get_bits(bs, 12u32)
        part_23_sum += usize(gr[g].part_23_length)
        gr[g].big_values = get_bits(bs, 9u32)
        if gr[g].big_values > 288u32 { ret (0i32, false) }
        gr[g].global_gain = get_bits(bs, 8u32)
        if hdr_mpeg1(h) {
            gr[g].scalefac_compress = get_bits(bs, 4u32)
        } else {
            gr[g].scalefac_compress = get_bits(bs, 9u32)
        }
        gr[g].sfb = scf_long_table()[sr_idx * 23usize..sr_idx * 23usize + 23usize]
        gr[g].n_long_sfb = 22u32
        gr[g].n_short_sfb = 0u32
        var tables = 0u32
        if get_bits(bs, 1u32) != 0u32 {
            gr[g].block_type = get_bits(bs, 2u32)
            if gr[g].block_type == 0u32 { ret (0i32, false) }
            gr[g].mixed_block_flag = get_bits(bs, 1u32)
            gr[g].region_count[0] = 7u32
            gr[g].region_count[1] = 255u32
            if gr[g].block_type == 2u32 {
                scfsi = scfsi & 3855u32
                if gr[g].mixed_block_flag == 0u32 {
                    gr[g].region_count[0] = 8u32
                    gr[g].sfb = scf_short_table()[sr_idx * 40usize..sr_idx * 40usize + 40usize]
                    gr[g].n_long_sfb = 0u32
                    gr[g].n_short_sfb = 39u32
                } else {
                    gr[g].sfb = scf_mixed_table()[sr_idx * 40usize..sr_idx * 40usize + 40usize]
                    gr[g].n_long_sfb = 6u32
                    if hdr_mpeg1(h) { gr[g].n_long_sfb = 8u32 }
                    gr[g].n_short_sfb = 30u32
                }
            }
            tables = get_bits(bs, 10u32) << 5u32
            gr[g].subblock_gain[0] = get_bits(bs, 3u32)
            gr[g].subblock_gain[1] = get_bits(bs, 3u32)
            gr[g].subblock_gain[2] = get_bits(bs, 3u32)
        } else {
            gr[g].block_type = 0u32
            gr[g].mixed_block_flag = 0u32
            tables = get_bits(bs, 15u32)
            gr[g].region_count[0] = get_bits(bs, 4u32)
            gr[g].region_count[1] = get_bits(bs, 3u32)
            gr[g].region_count[2] = 255u32
        }
        gr[g].table_select[0] = tables >> 10u32
        gr[g].table_select[1] = (tables >> 5u32) & 31u32
        gr[g].table_select[2] = tables & 31u32
        if hdr_mpeg1(h) {
            gr[g].preflag = get_bits(bs, 1u32)
        } else {
            gr[g].preflag = 0u32
            if gr[g].scalefac_compress >= 500u32 { gr[g].preflag = 1u32 }
        }
        gr[g].scalefac_scale = get_bits(bs, 1u32)
        gr[g].count1_table = get_bits(bs, 1u32)
        gr[g].scfsi = (scfsi >> 12u32) & 15u32
        scfsi = scfsi << 4u32
        g += 1usize
    }
    if part_23_sum + bs.pos > bs.limit + usize(main_data_begin) * 8usize { ret (0i32, false) }
    ret (main_data_begin, true)
}

// ------------------------------------------------------------------ scalefactors

fn ldexp_q2(y0: f32, exp0: i32) -> f32 {
    var y = y0
    var exp_q2 = exp0
    while true {
        var e = exp_q2
        if e > 120i32 { e = 120i32 }
        var frac: f32 = 0.0
        let which = e & 3i32
        if which == 0i32 { frac = 9.31322575e-10 }
        if which == 1i32 { frac = 7.83145814e-10 }
        if which == 2i32 { frac = 6.58544508e-10 }
        if which == 3i32 { frac = 5.53767716e-10 }
        y = y * frac * f32(1073741824i32 >> u32(e >> 2u32))
        exp_q2 -= e
        if exp_q2 <= 0i32 { break }
    }
    ret y
}

// `scfsi` negative means MPEG-2: no sharing, and the largest code marks an illegal
// intensity position.
fn read_scalefactors(scf: []u8, ist_pos: []u8, scf_size: [4]u32, partition: str, part_at: usize, bs: *Bits, scfsi0: i32) {
    var scfsi = scfsi0
    var at = 0usize
    var i = 0usize
    while i < 4usize && tb(partition, part_at + i) != 0u32 {
        let cnt = usize(tb(partition, part_at + i))
        if (scfsi & 8i32) != 0i32 {
            var k = 0usize
            while k < cnt {
                scf[at + k] = ist_pos[at + k]
                k += 1usize
            }
        } else {
            let bits = scf_size[i]
            if bits == 0u32 {
                var k = 0usize
                while k < cnt {
                    scf[at + k] = 0u8
                    ist_pos[at + k] = 0u8
                    k += 1usize
                }
            } else {
                var max_scf = -1i32
                if scfsi < 0i32 { max_scf = (1i32 << bits) - 1i32 }
                var k = 0usize
                while k < cnt {
                    let s = i32(get_bits(bs, bits))
                    if s == max_scf {
                        ist_pos[at + k] = 255u8
                    } else {
                        ist_pos[at + k] = u8(s)
                    }
                    scf[at + k] = u8(s)
                    k += 1usize
                }
            }
        }
        at += cnt
        i += 1usize
        scfsi *= 2i32
    }
    scf[at] = 0u8
    scf[at + 1usize] = 0u8
    scf[at + 2usize] = 0u8
}

fn decode_scalefactors(st: *State, h: []const u8, ist_pos: []u8, bs: *Bits, g: usize, ch: usize) {
    let gr = st.gr[g]
    var part_row = 0usize
    if gr.n_short_sfb != 0u32 { part_row = 1usize }
    if gr.n_long_sfb == 0u32 { part_row += 1usize }
    var part_at = part_row * 28usize
    var scf_size: [4]u32 = zero
    let scf_shift = gr.scalefac_scale + 1u32
    var scfsi = i32(gr.scfsi)
    if hdr_mpeg1(h) {
        let part = tb(scfc_decode(), usize(gr.scalefac_compress))
        scf_size[0] = part >> 2u32
        scf_size[1] = part >> 2u32
        scf_size[2] = part & 3u32
        scf_size[3] = part & 3u32
    } else {
        var ist = 0usize
        if hdr_test_intensity(h) && ch != 0usize { ist = 1usize }
        var sfc = i32(gr.scalefac_compress >> u32(ist))
        var k = ist * 12usize
        while sfc >= 0i32 {
            var modprod = 1i32
            var i = 3usize
            while true {
                let m = i32(tb(lsf_mod(), k + i))
                scf_size[i] = u32(sfc / modprod % m)
                modprod *= m
                if i == 0usize { break }
                i -= 1usize
            }
            sfc -= modprod
            k += 4usize
        }
        part_at += k
        scfsi = -16i32
    }
    read_scalefactors(st.iscf, ist_pos, scf_size, scf_partitions(), part_at, bs, scfsi)
    if gr.n_short_sfb != 0u32 {
        let sh = 3u32 - scf_shift
        var i = 0usize
        while i < usize(gr.n_short_sfb) {
            let base = usize(gr.n_long_sfb) + i
            st.iscf[base] = u8(u32(st.iscf[base]) + (gr.subblock_gain[0] << sh))
            st.iscf[base + 1usize] = u8(u32(st.iscf[base + 1usize]) + (gr.subblock_gain[1] << sh))
            st.iscf[base + 2usize] = u8(u32(st.iscf[base + 2usize]) + (gr.subblock_gain[2] << sh))
            i += 3usize
        }
    } else if gr.preflag != 0u32 {
        var i = 0usize
        while i < 10usize {
            st.iscf[11usize + i] = u8(u32(st.iscf[11usize + i]) + tb(preamp(), i))
            i += 1usize
        }
    }
    var gain_exp = i32(gr.global_gain) - 4i32 - 210i32
    if hdr_ms_stereo(h) { gain_exp -= 2i32 }
    let gain = ldexp_q2(2048.0, MAX_SCFI - gain_exp)
    var i = 0usize
    while i < usize(gr.n_long_sfb + gr.n_short_sfb) {
        st.scf[i] = ldexp_q2(gain, i32(u32(st.iscf[i]) << scf_shift))
        i += 1usize
    }
}

// ------------------------------------------------------------------ Huffman and requantisation

fn pow_43(st: *State, x: i32) -> f32 {
    if x < 129i32 { ret st.pow43[usize(16i32 + x)] }
    var mult: f32 = 256.0
    var v = x
    if v < 1024i32 {
        mult = 16.0
        v = v << 3u32
    }
    let sign = (2i32 * v) & 64i32
    let frac = f32((v & 63i32) - sign) / f32((v & -64i32) + sign)
    ret st.pow43[usize(16i32 + ((v + sign) >> 6u32))] * (1.0 + frac * (1.3333333 + frac * 0.22222222)) * mult
}

fn peek(c: *Cache, n: u32) -> u32 {
    ret c.cache >> (32u32 - n)
}

fn flush(c: *Cache, n: u32) {
    c.cache = c.cache << n
    c.sh += i32(n)
}

fn check_bits(c: *Cache) {
    while c.sh >= 0i32 {
        var b = 0u32
        if c.next < c.data.len { b = u32(c.data[c.next]) }
        c.cache = c.cache | (b << u32(c.sh))
        c.next += 1usize
        c.sh -= 8i32
    }
}

fn cache_pos(c: *Cache) -> i32 {
    ret i32(c.next) * 8i32 - 24i32 + c.sh
}

fn byte_or_zero(d: []const u8, at: usize) -> u32 {
    if at < d.len { ret u32(d[at]) }
    ret 0u32
}

fn huffman(st: *State, dst: []f32, bs: *Bits, g: usize, limit: usize) {
    let gr = st.gr[g]
    var c = Cache { data: bs.data, next: bs.pos / 8usize, cache: 0u32, sh: i32(bs.pos & 7usize) - 8i32 }
    c.cache = (((byte_or_zero(c.data, c.next) * 256u32 + byte_or_zero(c.data, c.next + 1usize)) * 256u32 + byte_or_zero(c.data, c.next + 2usize)) * 256u32 + byte_or_zero(c.data, c.next + 3usize)) << u32(bs.pos & 7usize)
    c.next += 4usize
    var one: f32 = 0.0
    var ireg = 0usize
    var big_val_cnt = i32(gr.big_values)
    var sfb_at = 0usize
    var scf_at = 0usize
    var out = 0usize
    let tabs = huff_tabs()
    var np = 0i32
    while big_val_cnt > 0i32 {
        let tab_num = usize(gr.table_select[ireg])
        var sfb_cnt = i32(gr.region_count[ireg])
        ireg += 1usize
        let codebook = usize(t16(huff_index(), tab_num))
        let linbits = tb(huff_linbits(), tab_num)
        while true {
            np = i32(tb(gr.sfb, sfb_at) / 2u32)
            sfb_at += 1usize
            var pairs = np
            if big_val_cnt < pairs { pairs = big_val_cnt }
            one = st.scf[scf_at]
            scf_at += 1usize
            while pairs > 0i32 {
                var w = 5u32
                var leaf = t16(tabs, codebook + usize(peek(&c, w)))
                while leaf < 0i32 {
                    flush(&c, w)
                    w = u32(leaf & 7i32)
                    leaf = t16(tabs, usize(i32(codebook) + i32(peek(&c, w)) - (leaf >> 3u32)))
                }
                flush(&c, u32(leaf >> 8u32))
                var j = 0usize
                while j < 2usize {
                    var lsb = leaf & 15i32
                    if lsb == 15i32 && linbits != 0u32 {
                        lsb += i32(peek(&c, linbits))
                        flush(&c, linbits)
                        check_bits(&c)
                        var value = one * pow_43(st, lsb)
                        if (c.cache & 2147483648u32) != 0u32 { value = 0.0 - value }
                        dst[out] = value
                    } else {
                        var index = 16i32 + lsb
                        if (c.cache & 2147483648u32) != 0u32 { index -= 16i32 }
                        dst[out] = st.pow43[usize(index)] * one
                    }
                    if lsb != 0i32 { flush(&c, 1u32) }
                    out += 1usize
                    leaf = leaf >> 4u32
                    j += 1usize
                }
                check_bits(&c)
                pairs -= 1i32
            }
            big_val_cnt -= np
            sfb_cnt -= 1i32
            if !(big_val_cnt > 0i32 && sfb_cnt >= 0i32) { break }
        }
    }
    np = 1i32 - big_val_cnt
    var count1 = huff_tab32()
    if gr.count1_table != 0u32 { count1 = huff_tab33() }
    while true {
        var leaf = i32(tb(count1, usize(peek(&c, 4u32))))
        if (leaf & 8i32) == 0i32 {
            let extra = u32(leaf & 3i32)
            var offset = 0u32
            if extra != 0u32 { offset = (c.cache << 4u32) >> (32u32 - extra) }
            leaf = i32(tb(count1, usize((leaf >> 3u32) + i32(offset))))
        }
        flush(&c, u32(leaf & 7i32))
        if cache_pos(&c) > i32(limit) { break }
        np -= 1i32
        if np == 0i32 {
            np = i32(tb(gr.sfb, sfb_at) / 2u32)
            sfb_at += 1usize
            if np == 0i32 { break }
            one = st.scf[scf_at]
            scf_at += 1usize
        }
        var s = 0usize
        while s < 2usize {
            if (leaf & (128i32 >> u32(s))) != 0i32 {
                var value = one
                if (c.cache & 2147483648u32) != 0u32 { value = 0.0 - one }
                dst[out + s] = value
                flush(&c, 1u32)
            }
            s += 1usize
        }
        np -= 1i32
        if np == 0i32 {
            np = i32(tb(gr.sfb, sfb_at) / 2u32)
            sfb_at += 1usize
            if np == 0i32 { break }
            one = st.scf[scf_at]
            scf_at += 1usize
        }
        s = 2usize
        while s < 4usize {
            if (leaf & (128i32 >> u32(s))) != 0i32 {
                var value = one
                if (c.cache & 2147483648u32) != 0u32 { value = 0.0 - one }
                dst[out + s] = value
                flush(&c, 1u32)
            }
            s += 1usize
        }
        check_bits(&c)
        out += 4usize
    }
    bs.pos = limit
}

// ------------------------------------------------------------------ stereo

fn midside_stereo(left: []f32, at: usize, n: usize) {
    var i = 0usize
    while i < n {
        let a = left[at + i]
        let b = left[at + 576usize + i]
        left[at + i] = a + b
        left[at + 576usize + i] = a - b
        i += 1usize
    }
}

fn intensity_band(left: []f32, at: usize, n: usize, kl: f32, kr: f32) {
    var i = 0usize
    while i < n {
        left[at + 576usize + i] = left[at + i] * kr
        left[at + i] = left[at + i] * kl
        i += 1usize
    }
}

fn stereo_top_band(right: []f32, at0: usize, sfb: str, nbands: usize, max_band: []i32) {
    max_band[0] = -1i32
    max_band[1] = -1i32
    max_band[2] = -1i32
    var at = at0
    var i = 0usize
    while i < nbands {
        let width = usize(tb(sfb, i))
        var k = 0usize
        while k < width {
            if right[at + k] != 0.0 || right[at + k + 1usize] != 0.0 {
                max_band[i % 3usize] = i32(i)
                break
            }
            k += 2usize
        }
        at += width
        i += 1usize
    }
}

fn pan_value(ipos: u32, right: bool) -> f32 {
    var index = ipos
    if right { index = 6u32 - ipos }
    if index == 0u32 { ret 0.0 }
    if index == 1u32 { ret 0.21132487 }
    if index == 2u32 { ret 0.36602540 }
    if index == 3u32 { ret 0.5 }
    if index == 4u32 { ret 0.63397460 }
    if index == 5u32 { ret 0.78867513 }
    ret 1.0
}

fn stereo_process(left: []f32, ist_pos: []u8, sfb: str, h: []const u8, max_band: []i32, mpeg2_sh: u32) {
    var max_pos = 64u32
    if hdr_mpeg1(h) { max_pos = 7u32 }
    var at = 0usize
    var i = 0usize
    while tb(sfb, i) != 0u32 {
        let width = usize(tb(sfb, i))
        let ipos = u32(ist_pos[i])
        if i32(i) > max_band[i % 3usize] && ipos < max_pos {
            var s: f32 = 1.0
            if hdr_test_ms(h) { s = 1.41421356 }
            var kl: f32 = 1.0
            var kr: f32 = 1.0
            if hdr_mpeg1(h) {
                kl = pan_value(ipos, false)
                kr = pan_value(ipos, true)
            } else {
                kr = ldexp_q2(1.0, i32(((ipos + 1u32) >> 1u32) << mpeg2_sh))
                if (ipos & 1u32) != 0u32 {
                    kl = kr
                    kr = 1.0
                }
            }
            intensity_band(left, at, width, kl * s, kr * s)
        } else if hdr_test_ms(h) {
            midside_stereo(left, at, width)
        }
        at += width
        i += 1usize
    }
}

fn intensity_stereo(st: *State, left: []f32, ist_pos: []u8, g: usize, h: []const u8) {
    let gr = st.gr[g]
    let n_sfb = usize(gr.n_long_sfb + gr.n_short_sfb)
    var max_blocks = 1usize
    if gr.n_short_sfb != 0u32 { max_blocks = 3usize }
    var max_band: [3]i32 = zero
    stereo_top_band(left, 576usize, gr.sfb, n_sfb, max_band[0..])
    if gr.n_long_sfb != 0u32 {
        var top = max_band[0]
        if max_band[1] > top { top = max_band[1] }
        if max_band[2] > top { top = max_band[2] }
        max_band[0] = top
        max_band[1] = top
        max_band[2] = top
    }
    var i = 0usize
    while i < max_blocks {
        var default_pos = 0u8
        if hdr_mpeg1(h) { default_pos = 3u8 }
        let itop = n_sfb - max_blocks + i
        let prev = itop - max_blocks
        if max_band[i] >= i32(prev) {
            ist_pos[itop] = default_pos
        } else {
            ist_pos[itop] = ist_pos[prev]
        }
        i += 1usize
    }
    stereo_process(left, ist_pos, gr.sfb, h, max_band[0..], st.gr[g + 1usize].scalefac_compress & 1u32)
}

// ------------------------------------------------------------------ reorder, alias reduction, IMDCT

fn reorder(grbuf: []f32, at: usize, scratch: []f32, sfb: str, sfb_at: usize) {
    var src = at
    var dst = 0usize
    var s = sfb_at
    while tb(sfb, s) != 0u32 {
        let len = usize(tb(sfb, s))
        var i = 0usize
        while i < len {
            scratch[dst] = grbuf[src + i]
            scratch[dst + 1usize] = grbuf[src + i + len]
            scratch[dst + 2usize] = grbuf[src + i + 2usize * len]
            dst += 3usize
            i += 1usize
        }
        src += 3usize * len
        s += 3usize
    }
    mem.copy[f32](grbuf[at..at + dst], scratch[..dst])
}

fn antialias(grbuf: []f32, at0: usize, nbands: i32) {
    let aa0: [8]f32 = [8]f32{ 0.85749293, 0.88174200, 0.94962865, 0.98331459, 0.99551782, 0.99916056, 0.99989920, 0.99999316 }
    let aa1: [8]f32 = [8]f32{ 0.51449576, 0.47173197, 0.31337745, 0.18191320, 0.09457419, 0.04096558, 0.01419856, 0.00369997 }
    var at = at0
    var n = nbands
    while n > 0i32 {
        var i = 0usize
        while i < 8usize {
            let u = grbuf[at + 18usize + i]
            let d = grbuf[at + 17usize - i]
            grbuf[at + 18usize + i] = u * aa0[i] - d * aa1[i]
            grbuf[at + 17usize - i] = u * aa1[i] + d * aa0[i]
            i += 1usize
        }
        n -= 1i32
        at += 18usize
    }
}

fn dct3_9(y: []f32) {
    var s0 = y[0]
    var s2 = y[2]
    var s4 = y[4]
    var s6 = y[6]
    var s8 = y[8]
    var t0 = s0 + s6 * 0.5
    s0 = s0 - s6
    var t4 = (s4 + s2) * 0.93969262
    var t2 = (s8 + s2) * 0.76604444
    s6 = (s4 - s8) * 0.17364818
    s4 = s4 + s8 - s2
    s2 = s0 - s4 * 0.5
    y[4] = s4 + s0
    s8 = t0 - t2 + s6
    s0 = t0 - t4 + t2
    s4 = t0 + t4 - s6
    var s1 = y[1]
    var s3 = y[3]
    var s5 = y[5]
    var s7 = y[7]
    s3 = s3 * 0.86602540
    t0 = (s5 + s1) * 0.98480775
    t4 = (s5 - s7) * 0.34202014
    t2 = (s1 + s7) * 0.64278761
    s1 = (s1 - s5 - s7) * 0.86602540
    s5 = t0 - s3 - t2
    s7 = t4 - s3 - t0
    s3 = t4 + s3 - t2
    y[0] = s4 - s7
    y[1] = s2 + s1
    y[2] = s0 - s3
    y[3] = s8 + s5
    y[5] = s8 - s5
    y[6] = s0 + s3
    y[7] = s2 - s1
    y[8] = s4 + s7
}

fn imdct36(grbuf: []f32, at0: usize, overlap: []f32, ov0: usize, window: [18]f32, nbands: usize) {
    let twid: [18]f32 = [18]f32{ 0.73727734, 0.79335334, 0.84339145, 0.88701083, 0.92387953, 0.95371695, 0.97629601, 0.99144486, 0.99904822, 0.67559021, 0.60876143, 0.53729961, 0.46174861, 0.38268343, 0.30070580, 0.21643961, 0.13052619, 0.04361938 }
    var at = at0
    var ov = ov0
    var j = 0usize
    while j < nbands {
        var co: [9]f32 = zero
        var si: [9]f32 = zero
        co[0] = 0.0 - grbuf[at]
        si[0] = grbuf[at + 17usize]
        var i = 0usize
        while i < 4usize {
            si[8usize - 2usize * i] = grbuf[at + 4usize * i + 1usize] - grbuf[at + 4usize * i + 2usize]
            co[1usize + 2usize * i] = grbuf[at + 4usize * i + 1usize] + grbuf[at + 4usize * i + 2usize]
            si[7usize - 2usize * i] = grbuf[at + 4usize * i + 4usize] - grbuf[at + 4usize * i + 3usize]
            co[2usize + 2usize * i] = 0.0 - (grbuf[at + 4usize * i + 3usize] + grbuf[at + 4usize * i + 4usize])
            i += 1usize
        }
        dct3_9(co[0..])
        dct3_9(si[0..])
        si[1] = 0.0 - si[1]
        si[3] = 0.0 - si[3]
        si[5] = 0.0 - si[5]
        si[7] = 0.0 - si[7]
        i = 0usize
        while i < 9usize {
            let ovl = overlap[ov + i]
            let sum = co[i] * twid[9usize + i] + si[i] * twid[i]
            overlap[ov + i] = co[i] * twid[i] - si[i] * twid[9usize + i]
            grbuf[at + i] = ovl * window[i] - sum * window[9usize + i]
            grbuf[at + 17usize - i] = ovl * window[9usize + i] + sum * window[i]
            i += 1usize
        }
        j += 1usize
        at += 18usize
        ov += 9usize
    }
}

fn idct3(x0: f32, x1: f32, x2: f32, dst: []f32) {
    let m1 = x1 * 0.86602540
    let a1 = x0 - x2 * 0.5
    dst[1] = x0 + x2
    dst[0] = a1 + m1
    dst[2] = a1 - m1
}

fn imdct12(x: []f32, xa: usize, dst: []f32, da: usize, overlap: []f32, oa: usize) {
    let twid: [6]f32 = [6]f32{ 0.79335334, 0.92387953, 0.99144486, 0.60876143, 0.38268343, 0.13052619 }
    var co: [3]f32 = zero
    var si: [3]f32 = zero
    idct3(0.0 - x[xa], x[xa + 6usize] + x[xa + 3usize], x[xa + 12usize] + x[xa + 9usize], co[0..])
    idct3(x[xa + 15usize], x[xa + 12usize] - x[xa + 9usize], x[xa + 6usize] - x[xa + 3usize], si[0..])
    si[1] = 0.0 - si[1]
    var i = 0usize
    while i < 3usize {
        let ovl = overlap[oa + i]
        let sum = co[i] * twid[3usize + i] + si[i] * twid[i]
        overlap[oa + i] = co[i] * twid[i] - si[i] * twid[3usize + i]
        dst[da + i] = ovl * twid[2usize - i] - sum * twid[5usize - i]
        dst[da + 5usize - i] = ovl * twid[5usize - i] + sum * twid[2usize - i]
        i += 1usize
    }
}

fn imdct_short(grbuf: []f32, at0: usize, overlap: []f32, ov0: usize, nbands: usize) {
    var at = at0
    var ov = ov0
    var n = nbands
    while n > 0usize {
        var tmp: [18]f32 = zero
        mem.copy[f32](tmp[0..], grbuf[at..at + 18usize])
        mem.copy[f32](grbuf[at..at + 6usize], overlap[ov..ov + 6usize])
        imdct12(tmp[0..], 0usize, grbuf, at + 6usize, overlap, ov + 6usize)
        imdct12(tmp[0..], 1usize, grbuf, at + 12usize, overlap, ov + 6usize)
        imdct12(tmp[0..], 2usize, overlap, ov, overlap, ov + 6usize)
        n -= 1usize
        ov += 9usize
        at += 18usize
    }
}

fn change_sign(grbuf: []f32, at0: usize) {
    var b = 0usize
    var at = at0 + 18usize
    while b < 32usize {
        var i = 1usize
        while i < 18usize {
            grbuf[at + i] = 0.0 - grbuf[at + i]
            i += 2usize
        }
        b += 2usize
        at += 36usize
    }
}

fn imdct_gr(grbuf: []f32, at: usize, overlap: []f32, ov: usize, block_type: u32, n_long_bands: usize) {
    let long_window: [18]f32 = [18]f32{ 0.99904822, 0.99144486, 0.97629601, 0.95371695, 0.92387953, 0.88701083, 0.84339145, 0.79335334, 0.73727734, 0.04361938, 0.13052619, 0.21643961, 0.30070580, 0.38268343, 0.46174861, 0.53729961, 0.60876143, 0.67559021 }
    let stop_window: [18]f32 = [18]f32{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.99144486, 0.92387953, 0.79335334, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.13052619, 0.38268343, 0.60876143 }
    var here = at
    var ovh = ov
    if n_long_bands != 0usize {
        imdct36(grbuf, here, overlap, ovh, long_window, n_long_bands)
        here += 18usize * n_long_bands
        ovh += 9usize * n_long_bands
    }
    if block_type == 2u32 {
        imdct_short(grbuf, here, overlap, ovh, 32usize - n_long_bands)
    } else if block_type == 3u32 {
        imdct36(grbuf, here, overlap, ovh, stop_window, 32usize - n_long_bands)
    } else {
        imdct36(grbuf, here, overlap, ovh, long_window, 32usize - n_long_bands)
    }
}

// ------------------------------------------------------------------ the reservoir and one granule

fn save_reservoir(st: *State, bs: *Bits) {
    var pos = (bs.pos + 7usize) / 8usize
    var remains = 0usize
    if bs.limit / 8usize > pos { remains = bs.limit / 8usize - pos }
    if remains > RESERVOIR {
        pos += remains - RESERVOIR
        remains = RESERVOIR
    }
    if remains > 0usize { mem.copy[u8](st.reserv_buf[..remains], st.maindata[pos..pos + remains]) }
    st.reserv = remains
}

// Lays the reservoir's tail and this frame's payload out contiguously; false when the
// frame reaches further back than the reservoir holds.
fn restore_reservoir(st: *State, frame: *Bits, main_data_begin: usize) -> (Bits, bool) {
    let frame_bytes = (frame.limit - frame.pos) / 8usize
    var bytes_have = st.reserv
    if main_data_begin < bytes_have { bytes_have = main_data_begin }
    var from = 0usize
    if st.reserv > main_data_begin { from = st.reserv - main_data_begin }
    if bytes_have > 0usize { mem.copy[u8](st.maindata[..bytes_have], st.reserv_buf[from..from + bytes_have]) }
    mem.copy[u8](st.maindata[bytes_have..bytes_have + frame_bytes], frame.data[frame.pos / 8usize..frame.pos / 8usize + frame_bytes])
    let bs = Bits { data: st.maindata, pos: 0usize, limit: (bytes_have + frame_bytes) * 8usize }
    ret (bs, st.reserv >= main_data_begin)
}

fn decode_granule(st: *State, bs: *Bits, h: []const u8, g0: usize, nch: usize) {
    var ch = 0usize
    while ch < nch {
        let limit = bs.pos + usize(st.gr[g0 + ch].part_23_length)
        decode_scalefactors(st, h, st.ist_pos[ch * 39usize..ch * 39usize + 39usize], bs, g0 + ch, ch)
        huffman(st, st.grbuf[ch * 576usize..ch * 576usize + 576usize], bs, g0 + ch, limit)
        ch += 1usize
    }
    if hdr_test_intensity(h) {
        intensity_stereo(st, st.grbuf, st.ist_pos[39usize..78usize], g0, h)
    } else if hdr_ms_stereo(h) {
        midside_stereo(st.grbuf, 0usize, 576usize)
    }
    ch = 0usize
    while ch < nch {
        let gr = st.gr[g0 + ch]
        var aa_bands = 31i32
        var n_long_bands = 0usize
        if gr.mixed_block_flag != 0u32 {
            n_long_bands = 2usize
            if hdr_my_sample_rate(h) == 2u32 { n_long_bands = 4usize }
        }
        if gr.n_short_sfb != 0u32 {
            aa_bands = i32(n_long_bands) - 1i32
            reorder(st.grbuf, ch * 576usize + n_long_bands * 18usize, st.syn, gr.sfb, usize(gr.n_long_sfb))
        }
        antialias(st.grbuf, ch * 576usize, aa_bands)
        imdct_gr(st.grbuf, ch * 576usize, st.overlap, ch * 288usize, gr.block_type, n_long_bands)
        change_sign(st.grbuf, ch * 576usize)
        ch += 1usize
    }
}

// ------------------------------------------------------------------ synthesis

fn sec_value(i: usize) -> f32 {
    let sec: [24]f32 = [24]f32{ 10.19000816, 0.50060302, 0.50241929, 3.40760851, 0.50547093, 0.52249861, 2.05778098, 0.51544732, 0.56694406, 1.48416460, 0.53104258, 0.64682180, 1.16943991, 0.55310392, 0.78815460, 0.97256821, 0.58293498, 1.06067765, 0.83934963, 0.62250412, 1.72244716, 0.74453628, 0.67480832, 5.10114861 }
    ret sec[i]
}

fn dct_ii(grbuf: []f32, base: usize, n: usize) {
    var k = 0usize
    while k < n {
        var t: [32]f32 = zero
        let y = base + k
        var i = 0usize
        while i < 8usize {
            let x0 = grbuf[y + i * 18usize]
            let x1 = grbuf[y + (15usize - i) * 18usize]
            let x2 = grbuf[y + (16usize + i) * 18usize]
            let x3 = grbuf[y + (31usize - i) * 18usize]
            let t0 = x0 + x3
            let t1 = x1 + x2
            let t2 = (x1 - x2) * sec_value(3usize * i)
            let t3 = (x0 - x3) * sec_value(3usize * i + 1usize)
            t[i] = t0 + t1
            t[8usize + i] = (t0 - t1) * sec_value(3usize * i + 2usize)
            t[16usize + i] = t3 + t2
            t[24usize + i] = (t3 - t2) * sec_value(3usize * i + 2usize)
            i += 1usize
        }
        i = 0usize
        while i < 4usize {
            let x = i * 8usize
            var x0 = t[x]
            var x1 = t[x + 1usize]
            var x2 = t[x + 2usize]
            var x3 = t[x + 3usize]
            var x4 = t[x + 4usize]
            var x5 = t[x + 5usize]
            var x6 = t[x + 6usize]
            var x7 = t[x + 7usize]
            var xt = x0 - x7
            x0 = x0 + x7
            x7 = x1 - x6
            x1 = x1 + x6
            x6 = x2 - x5
            x2 = x2 + x5
            x5 = x3 - x4
            x3 = x3 + x4
            x4 = x0 - x3
            x0 = x0 + x3
            x3 = x1 - x2
            x1 = x1 + x2
            t[x] = x0 + x1
            t[x + 4usize] = (x0 - x1) * 0.70710677
            x5 = x5 + x6
            x6 = (x6 + x7) * 0.70710677
            x7 = x7 + xt
            x3 = (x3 + x4) * 0.70710677
            x5 = x5 - x7 * 0.198912367
            x7 = x7 + x5 * 0.382683432
            x5 = x5 - x7 * 0.198912367
            x0 = xt - x6
            xt = xt + x6
            t[x + 1usize] = (xt + x7) * 0.50979561
            t[x + 2usize] = (x4 + x3) * 0.54119611
            t[x + 3usize] = (x0 - x5) * 0.60134488
            t[x + 5usize] = (x0 + x5) * 0.89997619
            t[x + 6usize] = (x4 - x3) * 1.30656302
            t[x + 7usize] = (xt - x7) * 2.56291556
            i += 1usize
        }
        var yy = y
        i = 0usize
        while i < 7usize {
            grbuf[yy] = t[i]
            grbuf[yy + 18usize] = t[16usize + i] + t[24usize + i] + t[24usize + i + 1usize]
            grbuf[yy + 36usize] = t[8usize + i] + t[8usize + i + 1usize]
            grbuf[yy + 54usize] = t[16usize + i + 1usize] + t[24usize + i] + t[24usize + i + 1usize]
            yy += 72usize
            i += 1usize
        }
        grbuf[yy] = t[7]
        grbuf[yy + 18usize] = t[23] + t[31]
        grbuf[yy + 36usize] = t[15]
        grbuf[yy + 54usize] = t[31]
        k += 1usize
    }
}

fn scale_pcm(sample: f32) -> i16 {
    if sample >= 32766.5 { ret 32767i16 }
    if sample <= -32767.5 { ret (-32767i16 - 1i16) }
    var s = i32(sample + 0.5)
    if s < 0i32 { s -= 1i32 }
    ret i16(s)
}

// One pair of subbands into 64 interleaved samples, `lins` being the sliding window.
// The two samples per 32 the sliding window's centre taps produce.
fn synth_pair(st: *State, pcm_at: usize, nch: usize, z: usize) {
    let lins = st.syn
    var a = (lins[z + 14usize * 64usize] - lins[z]) * 29.0
    a += (lins[z + 64usize] + lins[z + 13usize * 64usize]) * 213.0
    a += (lins[z + 12usize * 64usize] - lins[z + 2usize * 64usize]) * 459.0
    a += (lins[z + 3usize * 64usize] + lins[z + 11usize * 64usize]) * 2037.0
    a += (lins[z + 10usize * 64usize] - lins[z + 4usize * 64usize]) * 5153.0
    a += (lins[z + 5usize * 64usize] + lins[z + 9usize * 64usize]) * 6574.0
    a += (lins[z + 8usize * 64usize] - lins[z + 6usize * 64usize]) * 37489.0
    a += lins[z + 7usize * 64usize] * 75038.0
    st.pcm[pcm_at] = scale_pcm(a)
    let y = z + 2usize
    a = lins[y + 14usize * 64usize] * 104.0
    a += lins[y + 12usize * 64usize] * 1567.0
    a += lins[y + 10usize * 64usize] * 9727.0
    a += lins[y + 8usize * 64usize] * 64019.0
    a += lins[y + 6usize * 64usize] * -9975.0
    a += lins[y + 4usize * 64usize] * -45.0
    a += lins[y + 2usize * 64usize] * 146.0
    a += lins[y] * -5.0
    st.pcm[pcm_at + 16usize * nch] = scale_pcm(a)
}

fn synth_pair_bands(st: *State, xl: usize, xr: usize, pcm_at: usize, nch: usize, lins_at: usize) {
    let lins = st.syn
    let win = synth_window()
    let zlin = lins_at + 15usize * 64usize
    lins[zlin + 60usize] = st.grbuf[xl + 18usize * 16usize]
    lins[zlin + 61usize] = st.grbuf[xr + 18usize * 16usize]
    lins[zlin + 62usize] = st.grbuf[xl]
    lins[zlin + 63usize] = st.grbuf[xr]
    lins[zlin + 124usize] = st.grbuf[xl + 1usize + 18usize * 16usize]
    lins[zlin + 125usize] = st.grbuf[xr + 1usize + 18usize * 16usize]
    lins[zlin + 126usize] = st.grbuf[xl + 1usize]
    lins[zlin + 127usize] = st.grbuf[xr + 1usize]
    let right = nch - 1usize
    synth_pair(st, pcm_at + right, nch, lins_at + 61usize)
    synth_pair(st, pcm_at + right + 32usize * nch, nch, lins_at + 125usize)
    synth_pair(st, pcm_at, nch, lins_at + 60usize)
    synth_pair(st, pcm_at + 32usize * nch, nch, lins_at + 124usize)
    var i = 15usize
    while i > 0usize {
        i -= 1usize
        lins[zlin + 4usize * i] = st.grbuf[xl + 18usize * (31usize - i)]
        lins[zlin + 4usize * i + 1usize] = st.grbuf[xr + 18usize * (31usize - i)]
        lins[zlin + 4usize * i + 2usize] = st.grbuf[xl + 1usize + 18usize * (31usize - i)]
        lins[zlin + 4usize * i + 3usize] = st.grbuf[xr + 1usize + 18usize * (31usize - i)]
        lins[zlin + 4usize * (i + 16usize)] = st.grbuf[xl + 1usize + 18usize * (1usize + i)]
        lins[zlin + 4usize * (i + 16usize) + 1usize] = st.grbuf[xr + 1usize + 18usize * (1usize + i)]
        lins[zlin + 4usize * i + 2usize - 64usize] = st.grbuf[xl + 18usize * (1usize + i)]
        lins[zlin + 4usize * i + 3usize - 64usize] = st.grbuf[xr + 18usize * (1usize + i)]
        var a: [4]f32 = zero
        var b: [4]f32 = zero
        var k = 0usize
        while k < 8usize {
            let w0 = f32(t32(win, (14usize - i) * 16usize + 2usize * k))
            let w1 = f32(t32(win, (14usize - i) * 16usize + 2usize * k + 1usize))
            let vz = zlin + 4usize * i - k * 64usize
            let vy = zlin + 4usize * i - (15usize - k) * 64usize
            var j = 0usize
            while j < 4usize {
                if k == 0usize {
                    b[j] = lins[vz + j] * w1 + lins[vy + j] * w0
                    a[j] = lins[vz + j] * w0 - lins[vy + j] * w1
                } else if (k & 1usize) == 0usize {
                    b[j] += lins[vz + j] * w1 + lins[vy + j] * w0
                    a[j] += lins[vz + j] * w0 - lins[vy + j] * w1
                } else {
                    b[j] += lins[vz + j] * w1 + lins[vy + j] * w0
                    a[j] += lins[vy + j] * w1 - lins[vz + j] * w0
                }
                j += 1usize
            }
            k += 1usize
        }
        st.pcm[pcm_at + (15usize - i) * nch + right] = scale_pcm(a[1])
        st.pcm[pcm_at + (17usize + i) * nch + right] = scale_pcm(b[1])
        st.pcm[pcm_at + (15usize - i) * nch] = scale_pcm(a[0])
        st.pcm[pcm_at + (17usize + i) * nch] = scale_pcm(b[0])
        st.pcm[pcm_at + (47usize - i) * nch + right] = scale_pcm(a[3])
        st.pcm[pcm_at + (49usize + i) * nch + right] = scale_pcm(b[3])
        st.pcm[pcm_at + (47usize - i) * nch] = scale_pcm(a[2])
        st.pcm[pcm_at + (49usize + i) * nch] = scale_pcm(b[2])
    }
}

fn synth_granule(st: *State, nch: usize, pcm_at: usize) {
    var ch = 0usize
    while ch < nch {
        dct_ii(st.grbuf, 576usize * ch, 18usize)
        ch += 1usize
    }
    mem.copy[f32](st.syn[..960usize], st.qmf)
    var i = 0usize
    while i < 18usize {
        synth_pair_bands(st, i, i + 576usize * (nch - 1usize), pcm_at + 32usize * nch * i, nch, i * 64usize)
        i += 2usize
    }
    mem.copy[f32](st.qmf, st.syn[18usize * 64usize..18usize * 64usize + 960usize])
}

// ------------------------------------------------------------------ frames

fn reset(st: *State) {
    st.reserv = 0usize
    var i = 0usize
    while i < st.overlap.len {
        st.overlap[i] = 0.0
        i += 1usize
    }
    i = 0usize
    while i < st.qmf.len {
        st.qmf[i] = 0.0
        i += 1usize
    }
}

// Decodes the frame at `d.at` into `st.pcm` (silence when its reservoir is missing) and
// advances `d.at`; false at the end of the stream.
fn decode_frame(d: *Decoder) -> bool {
    let st = mem.cast[*State](d.state)
    let data = d.bytes[..st.end]
    let (at, size) = find_frame(data, d.at)
    if size == 0usize {
        d.at = st.end
        ret false
    }
    let h = data[at..at + 4usize]
    mem.copy[u8](st.hdr, h)
    d.at = at + size
    var nch = 2usize
    if hdr_mono(h) { nch = 1usize }
    let samples = hdr_frame_samples(h)
    st.pcm_count = samples * nch
    st.pcm_read = 0usize
    var i = 0usize
    while i < st.pcm_count {
        st.pcm[i] = 0i16
        i += 1usize
    }
    var frame = Bits { data: data[at + 4usize..at + size], pos: 0usize, limit: (size - 4usize) * 8usize }
    if hdr_crc(h) { let crc = get_bits(&frame, 16u32) }
    let (main_data_begin, side_ok) = read_side_info(&frame, st.gr, h)
    if !side_ok || frame.pos > frame.limit {
        reset(st)
        ret true
    }
    let (made, complete) = restore_reservoir(st, &frame, usize(main_data_begin))
    var bs = made
    if complete {
        var granules = 1usize
        if hdr_mpeg1(h) { granules = 2usize }
        var g = 0usize
        while g < granules {
            i = 0usize
            while i < 1152usize {
                st.grbuf[i] = 0.0
                i += 1usize
            }
            decode_granule(st, &bs, h, g * nch, nch)
            synth_granule(st, nch, g * 576usize * nch)
            g += 1usize
        }
    }
    save_reservoir(st, &bs)
    ret true
}

fn open(a: *mem.Arena, source_bytes: []const u8) -> (Decoder, err) {
    var start = 0usize
    while start + 10usize <= source_bytes.len && source_bytes[start] == 73u8 && source_bytes[start + 1usize] == 68u8 && source_bytes[start + 2usize] == 51u8 {
        let size = (usize(source_bytes[start + 6usize] & 127u8) << 21u32) | (usize(source_bytes[start + 7usize] & 127u8) << 14u32) | (usize(source_bytes[start + 8usize] & 127u8) << 7u32) | usize(source_bytes[start + 9usize] & 127u8)
        let footer = (source_bytes[start + 5usize] & 16u8) != 0u8
        start += 10usize + size
        if footer { start += 10usize }
    }
    var end = source_bytes.len
    if end >= start + 128usize && source_bytes[end - 128usize] == 84u8 && source_bytes[end - 127usize] == 65u8 && source_bytes[end - 126usize] == 71u8 { end -= 128usize }
    if start > end { ret (zero, Invalid) }
    let data = source_bytes[..end]
    let (first, first_size) = find_frame(data, start)
    if first_size == 0usize { ret (zero, Invalid) }
    let h = data[first..first + 4usize]
    if hdr_layer(h) != 1u32 { ret (zero, Unsupported) }
    var nch = 2usize
    if hdr_mono(h) { nch = 1usize }
    let fmt = audio.Format { rate: hdr_sample_rate_hz(h), channels: u8(nch), sample: .I16 }
    var frames = 0usize
    var at = first
    while true {
        let (here, size) = find_frame(data, at)
        if size == 0usize { break }
        let fh = data[here..here + 4usize]
        if hdr_layer(fh) != 1u32 { ret (zero, Unsupported) }
        if hdr_sample_rate_hz(fh) != fmt.rate || hdr_mono(fh) != (nch == 1usize) { ret (zero, Unsupported) }
        frames += hdr_frame_samples(fh)
        at = here + size
    }
    let (states, state_error) = mem.alloc[State](a, 1usize)
    if state_error != ok { ret (zero, state_error) }
    let (hdr, hdr_error) = mem.alloc[u8](a, 4usize)
    if hdr_error != ok { ret (zero, hdr_error) }
    let (reserv_buf, reserv_error) = mem.alloc[u8](a, RESERVOIR)
    if reserv_error != ok { ret (zero, reserv_error) }
    let (maindata, maindata_error) = mem.alloc[u8](a, RESERVOIR + MAX_FRAME)
    if maindata_error != ok { ret (zero, maindata_error) }
    let (overlap, overlap_error) = mem.alloc[f32](a, 576usize)
    if overlap_error != ok { ret (zero, overlap_error) }
    let (qmf, qmf_error) = mem.alloc[f32](a, 960usize)
    if qmf_error != ok { ret (zero, qmf_error) }
    let (grbuf, grbuf_error) = mem.alloc[f32](a, 1152usize)
    if grbuf_error != ok { ret (zero, grbuf_error) }
    let (scf, scf_error) = mem.alloc[f32](a, 40usize)
    if scf_error != ok { ret (zero, scf_error) }
    let (syn, syn_error) = mem.alloc[f32](a, 33usize * 64usize)
    if syn_error != ok { ret (zero, syn_error) }
    let (ist_pos, ist_error) = mem.alloc[u8](a, 78usize)
    if ist_error != ok { ret (zero, ist_error) }
    let (iscf, iscf_error) = mem.alloc[u8](a, 48usize)
    if iscf_error != ok { ret (zero, iscf_error) }
    let (gr, gr_error) = mem.alloc[Granule](a, 4usize)
    if gr_error != ok { ret (zero, gr_error) }
    let (pow43, pow43_error) = mem.alloc[f32](a, 145usize)
    if pow43_error != ok { ret (zero, pow43_error) }
    let (pcm, pcm_error) = mem.alloc[i16](a, 2304usize)
    if pcm_error != ok { ret (zero, pcm_error) }
    var i = 0usize
    while i < 16usize {
        pow43[i] = 0.0 - f32(math.pow[f64](f64(i), 1.3333333333333333))
        i += 1usize
    }
    i = 0usize
    while i < 129usize {
        pow43[16usize + i] = f32(math.pow[f64](f64(i), 1.3333333333333333))
        i += 1usize
    }
    var blank: Granule = zero
    i = 0usize
    while i < 4usize {
        gr[i] = blank
        i += 1usize
    }
    states[0usize] = State { hdr: hdr, reserv: 0usize, reserv_buf: reserv_buf, maindata: maindata, overlap: overlap, qmf: qmf, grbuf: grbuf, scf: scf, syn: syn, ist_pos: ist_pos, iscf: iscf, gr: gr, pow43: pow43, pcm: pcm, pcm_count: 0usize, pcm_read: 0usize, start: first, end: end }
    var d = Decoder { bytes: source_bytes, at: first, format: fmt, frames: frames, granule: 0usize, state: mem.cast[*void](&states[0usize]) }
    reset(&states[0usize])
    ret (d, ok)
}

fn format(d: Decoder) -> audio.Format {
    ret d.format
}

fn frame_count(d: Decoder) -> usize {
    ret d.frames
}

fn decode_into(d: *Decoder, out: *audio.Frames) -> (usize, err) {
    if out.format.rate != d.format.rate || out.format.channels != d.format.channels { ret (0usize, Unsupported) }
    if out.count > audio.frames_in(out.format, out.bytes.len) { ret (0usize, Unsupported) }
    let st = mem.cast[*State](d.state)
    let nch = usize(d.format.channels)
    var written = 0usize
    while written < out.count {
        if st.pcm_read >= st.pcm_count {
            if !decode_frame(d) { break }
            continue
        }
        var ch = 0usize
        while ch < nch {
            let write_error = audio.set_sample_i32(out, written, u8(ch), i32(st.pcm[st.pcm_read + ch]) * 65536i32)
            if write_error != ok { ret (written, write_error) }
            ch += 1usize
        }
        st.pcm_read += nch
        written += 1usize
        d.granule += 1usize
    }
    ret (written, ok)
}

// Restarts far enough before the frame holding `frame` -- two frames for the overlap
// and the synthesis state, and a kilobyte more for the reservoir -- and decodes up to it.
fn seek(d: *Decoder, frame: usize) -> err {
    if frame > d.frames { ret Invalid }
    let st = mem.cast[*State](d.state)
    let data = d.bytes[..st.end]
    var ring_at: [32]usize = zero
    var ring_position: [32]usize = zero
    var at = st.start
    var position = 0usize
    var n = 0usize
    while true {
        let (here, size) = find_frame(data, at)
        if size == 0usize { break }
        let samples = hdr_frame_samples(data[here..here + 4usize])
        if position + samples > frame { break }
        ring_at[n % 32usize] = here
        ring_position[n % 32usize] = position
        position += samples
        at = here + size
        n += 1usize
    }
    var restart = 0usize
    if n > 2usize {
        let base = n - 2usize
        restart = base
        var m = 0usize
        while m < 29usize && m < base {
            if ring_at[base % 32usize] - ring_at[(base - m) % 32usize] >= 1024usize { break }
            m += 1usize
        }
        restart = base - m
    }
    var earlier_at = st.start
    var earlier_position = 0usize
    if n > 0usize {
        earlier_at = ring_at[restart % 32usize]
        earlier_position = ring_position[restart % 32usize]
    }
    reset(st)
    st.pcm_count = 0usize
    st.pcm_read = 0usize
    d.at = earlier_at
    d.granule = earlier_position
    while d.granule < frame {
        if st.pcm_read >= st.pcm_count {
            if !decode_frame(d) { break }
            continue
        }
        let skip = (frame - d.granule) * usize(d.format.channels)
        var take = st.pcm_count - st.pcm_read
        if skip < take { take = skip }
        st.pcm_read += take
        d.granule += take / usize(d.format.channels)
    }
    ret ok
}
