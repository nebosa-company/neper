// A magic-number signature database: `sniff` names the format of a byte prefix by the
// leading (or fixed-offset) bytes the format's specification requires, the way file(1)'s
// magic database does, answering a MIME type, a conventional extension and a description.
// It is the byte-level companion to text and content-type guessing: nothing here reads
// beyond the offsets the table names, so a prefix of the file is enough (the largest offset is
// 257, for `ustar` in a tar header, so 262 bytes decide every row).
//
// The 74 rows are ordered, first match wins, with wildcard bytes written `??` (RIFF sizes).
// A family sharing a prefix lists its specific members first: RIFF (WebP, WAVE, AVI), ISO
// base-media `ftyp` brands (MP4, M4A, QuickTime, AVIF, HEIC), ZIP versus the OOXML/ODF
// containers it also is (those need a directory read and are not guessed here). The rows are
// generated from `scripts/magic_table.py` by `scripts/gen_magic.py`.

type Match = struct { mime: str, extension: str, description: str, offset: u32 }

fn hex_nibble(c: u8) -> i32 {
    if c >= 48u8 && c <= 57u8 { ret i32(c - 48u8) }
    if c >= 65u8 && c <= 70u8 { ret i32(c - 55u8) }
    if c >= 97u8 && c <= 102u8 { ret i32(c - 87u8) }
    ret -1i32
}

// One `offset|HEX|mime|extension|description` row per line.
fn scan(rows: str, data: []const u8) -> (Match, bool) {
    var start = 0usize
    var i = 0usize
    while i < rows.len {
        if rows[i] == 10u8 {
            let row = rows[start..i]
            var fields: [5]usize = zero
            var count = 0usize
            var k = 0usize
            fields[0usize] = 0usize
            while k < row.len && count < 4usize {
                if row[k] == 124u8 {
                    count += 1usize
                    fields[count] = k + 1usize
                }
                k += 1usize
            }
            if count == 4usize {
                var offset = 0usize
                var d = 0usize
                while d < fields[1usize] - 1usize {
                    offset = offset * 10usize + usize(row[d] - 48u8)
                    d += 1usize
                }
                let hex = row[fields[1usize]..fields[2usize] - 1usize]
                var good = offset + hex.len / 2usize <= data.len
                var p = 0usize
                while good && p + 1usize < hex.len {
                    if hex[p] != 63u8 {
                        let hi = hex_nibble(hex[p])
                        let lo = hex_nibble(hex[p + 1usize])
                        if hi < 0i32 || lo < 0i32 || data[offset + p / 2usize] != u8(hi * 16i32 + lo) { good = false }
                    }
                    p += 2usize
                }
                if good {
                    var m: Match = zero
                    m.mime = row[fields[2usize]..fields[3usize] - 1usize]
                    m.extension = row[fields[3usize]..fields[4usize] - 1usize]
                    m.description = row[fields[4usize]..row.len]
                    m.offset = u32(offset)
                    ret (m, true)
                }
            }
            start = i + 1usize
        }
        i += 1usize
    }
    ret (zero, false)
}

fn sniff(data: []const u8) -> (Match, bool) {
    let (hit_magic_rows_0, found_magic_rows_0) = scan(magic_rows_0(), data)
    if found_magic_rows_0 { ret (hit_magic_rows_0, true) }
    let (hit_magic_rows_1, found_magic_rows_1) = scan(magic_rows_1(), data)
    if found_magic_rows_1 { ret (hit_magic_rows_1, true) }
    ret (zero, false)
}

fn row_count() -> usize { ret 74usize }

fn magic_rows_0() -> str {
    ret "0|89504E470D0A1A0A|image/png|png|PNG image\n0|FFD8FF|image/jpeg|jpg|JPEG image\n0|474946383761|image/gif|gif|GIF image (87a)\n0|474946383961|image/gif|gif|GIF image (89a)\n0|52494646????????57454250|image/webp|webp|WebP image\n0|49492A00|image/tiff|tif|TIFF image (little endian)\n0|4D4D002A|image/tiff|tif|TIFF image (big endian)\n0|38425053|image/vnd.adobe.photoshop|psd|Photoshop document\n0|00000100|image/x-icon|ico|Windows icon\n0|0000000C6A5020200D0A870A|image/jp2|jp2|JPEG 2000 image\n0|716F6966|image/qoi|qoi|QOI image\n0|424D|image/bmp|bmp|Windows bitmap\n0|504B0304|application/zip|zip|ZIP archive\n0|504B0506|application/zip|zip|ZIP archive (empty)\n0|504B0708|application/zip|zip|ZIP archive (spanned)\n0|1F8B08|application/gzip|gz|gzip data\n0|425A68|application/x-bzip2|bz2|bzip2 data\n0|FD377A585A00|application/x-xz|xz|XZ data\n0|377ABCAF271C|application/x-7z-compressed|7z|7-zip archive\n0|526172211A070100|application/vnd.rar|rar|RAR archive (v5)\n0|526172211A0700|application/x-rar-compressed|rar|RAR archive\n0|28B52FFD|application/zstd|zst|Zstandard data\n0|04224D18|application/x-lz4|lz4|LZ4 data\n0|4D534346|application/vnd.ms-cab-compressed|cab|Microsoft cabinet\n257|7573746172|application/x-tar|tar|POSIX tar archive\n0|213C617263683E0A|application/x-unix-archive|a|ar archive\n0|EDABEEDB|application/x-rpm|rpm|RPM package\n0|1F9D|application/x-compress|Z|compress data\n0|25504446|application/pdf|pdf|PDF document\n0|2521|application/postscript|ps|PostScript\n0|7B5C72746631|application/rtf|rtf|Rich Text Format\n0|D0CF11E0A1B11AE1|application/x-ole-storage|doc|OLE2 compound document\n0|53514C69746520666F726D6174203300|application/vnd.sqlite3|sqlite|SQLite 3 database\n0|4F626A01|application/avro|avro|Avro object container\n0|50415231|application/vnd.apache.parquet|parquet|Parquet file\n0|2D2D2D2D2D424547494E|application/x-pem-file|pem|PEM text\n0|7F454C46|application/x-elf|elf|ELF executable\n0|4D5A|application/vnd.microsoft.portable-executable|exe|DOS/PE executable\n0|0061736D|application/wasm|wasm|WebAssembly module\n0|CFFAEDFE|application/x-mach-binary|macho|Mach-O 64-bit\n0|CEFAEDFE|application/x-mach-binary|macho|Mach-O 32-bit\n0|CAFEBABE|application/java-vm|class|Java class or Mach-O fat\n0|2321|text/x-script|sh|script with interpreter line\n0|494433|audio/mpeg|mp3|MP3 with ID3 tag\n0|FFFB|audio/mpeg|mp3|MP3 frame\n0|FFF3|audio/mpeg|mp3|MP3 frame\n0|FFF2|audio/mpeg|mp3|MP3 frame\n0|4F676753|audio/ogg|ogg|Ogg container\n0|664C6143|audio/x-flac|flac|FLAC audio\n0|52494646????????57415645|audio/x-wav|wav|RIFF WAVE audio\n0|464F524D????????41494646|audio/x-aiff|aiff|AIFF audio\n0|4D546864|audio/midi|mid|MIDI file\n4|667479704D3441|audio/mp4|m4a|MPEG-4 audio (M4A)\n4|66747970717420|video/quicktime|mov|QuickTime movie\n4|6674797069736F6D|video/mp4|mp4|MP4 (isom)\n4|667479706D703432|video/mp4|mp4|MP4 (mp42)\n4|6674797033677035|video/mp4|mp4|MP4 (3gp5)\n4|667479704D345620|video/x-m4v|m4v|MPEG-4 video (M4V)\n4|6674797061766966|image/avif|avif|AVIF image\n4|6674797068656963|image/heic|heic|HEIC image\n0|52494646????????41564920|video/x-msvideo|avi|AVI video\n0|1A45DFA3|video/x-matroska|mkv|Matroska or WebM\n0|464C5601|video/x-flv|flv|Flash video\n0|000001BA|video/mpeg|mpg|MPEG program stream\n0|000001B3|video/mpeg|mpg|MPEG video\n0|774F4646|font/woff|woff|WOFF font\n0|774F4632|font/woff2|woff2|WOFF2 font\n0|4F54544F|font/otf|otf|OpenType font\n0|0001000000|font/ttf|ttf|TrueType font\n0|D4C3B2A1|application/vnd.tcpdump.pcap|pcap|pcap capture (little endian)\n"
}

fn magic_rows_1() -> str {
    ret "0|A1B2C3D4|application/vnd.tcpdump.pcap|pcap|pcap capture (big endian)\n0|0A0D0D0A|application/x-pcapng|pcapng|pcapng capture\n0|3C3F786D6C20|application/xml|xml|XML document\n0|EFBBBF|text/plain|txt|UTF-8 text with BOM\n"
}
