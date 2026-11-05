// `e.fmt.hcl` and `e.fmt.sevenzip` against hostile input: a deeply nested HCL document is refused
// (`TooDeep`) instead of overflowing the stack, `\u`/`\U` escapes outside Unicode and in the
// surrogate range are `Invalid`, and a `%{ }` directive ends at its own closing brace rather than at a
// `}` inside a string. A 7z file with no SubStreamsInfo maps each folder to its own substream, so the
// unset first_sub index is never read. `main` runs one module's checks alone when given `hcl` or
// `sevenzip`.
use e.algo.hash as hash
use e.fmt.hcl
use e.fmt.sevenzip
use e.io
use e.mem
use e.os

fn same(x: []const u8, y: []const u8) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn append_text(dst: []u8, start: usize, t: str) -> usize {
    var i = 0usize
    while i < t.len {
        dst[start + i] = t[i]
        i += 1usize
    }
    ret start + t.len
}

fn put64(dst: []u8, start: usize, value: u64) {
    var i = 0usize
    while i < 8usize {
        dst[start + i] = u8((value >> u32(i * 8usize)) & 255u64)
        i += 1usize
    }
}

fn put32(dst: []u8, start: usize, value: u32) {
    var i = 0usize
    while i < 4usize {
        dst[start + i] = u8((value >> u32(i * 8usize)) & 255u32)
        i += 1usize
    }
}

fn check_hcl(a: *mem.Arena) -> i32 {
    // 10: a unary chain is refused at the depth limit, not by exhausting the stack
    let (unary, unary_error) = mem.alloc[u8](a, 60000usize)
    if unary_error != ok { ret 10i32 }
    var at = 0usize
    at = append_text(unary, at, "x = ")
    var n = 0usize
    while n < 50000usize {
        unary[at] = 33u8
        at += 1usize
        n += 1usize
    }
    at = append_text(unary, at, "true")
    let (_, unary_parse) = hcl.parse(a, unary[0..at])
    if unary_parse != hcl.TooDeep { ret 10i32 }

    // 11: a binary chain is refused at the depth limit
    let (binary, binary_error) = mem.alloc[u8](a, 200010usize)
    if binary_error != ok { ret 11i32 }
    at = append_text(binary, 0usize, "x = 0")
    n = 0usize
    while n < 100000usize {
        at = append_text(binary, at, "+1")
        n += 1usize
    }
    let (_, binary_parse) = hcl.parse(a, binary[0..at])
    if binary_parse != hcl.TooDeep { ret 11i32 }

    // 12: nested blocks are refused at the depth limit
    let (blocks, blocks_error) = mem.alloc[u8](a, 300000usize)
    if blocks_error != ok { ret 12i32 }
    at = 0usize
    n = 0usize
    while n < 50000usize {
        at = append_text(blocks, at, "a {\n")
        n += 1usize
    }
    n = 0usize
    while n < 50000usize {
        at = append_text(blocks, at, "}\n")
        n += 1usize
    }
    let (_, blocks_parse) = hcl.parse(a, blocks[0..at])
    if blocks_parse != hcl.TooDeep { ret 12i32 }

    // 13: escapes past U+10FFFF and in the surrogate range are refused; a valid astral escape is kept
    let (_, above_range) = hcl.parse(a, "a = \"\\UFFFFFFFF\"")
    if above_range != hcl.Invalid { ret 13i32 }
    let (_, surrogate) = hcl.parse(a, "a = \"\\uD800\"")
    if surrogate != hcl.Invalid { ret 13i32 }
    let (_, beyond) = hcl.parse(a, "a = \"\\U00110000\"")
    if beyond != hcl.Invalid { ret 13i32 }
    let (emoji_body, emoji_error) = hcl.parse(a, "a = \"\\U0001F600\"")
    if emoji_error != ok || emoji_body.len != 1usize { ret 13i32 }
    let emoji = emoji_body[0usize].value[0usize]
    if emoji.kind != .String || emoji.text.len != 4usize { ret 13i32 }
    if !same(emoji.text, "\xf0\x9f\x98\x80") { ret 13i32 }

    // 14: a `%{ }` directive closes at its own brace, not at the `}` inside the quoted string
    let (dir_body, dir_error) = hcl.parse(a, "a = \"%{ if x == \"}\" }yes%{ endif }\"")
    if dir_error != ok || dir_body.len != 1usize { ret 14i32 }
    let dir = dir_body[0usize].value[0usize]
    if dir.kind != .Template || dir.parts.len != 3usize { ret 14i32 }
    if dir.parts[0usize].kind != .Directive || dir.parts[1usize].kind != .Literal || dir.parts[2usize].kind != .Directive { ret 14i32 }
    if !same(dir.parts[1usize].text, "yes") { ret 14i32 }
    ret 0i32
}

fn check_sevenzip(a: *mem.Arena) -> i32 {
    let zip_limits = sevenzip.default_limits()

    // 20: one folder, two coders (Delta over Copy), no SubStreamsInfo: the packed stream is the
    // unbound coder's input (index 1), not a substream index
    let (header, header_error) = mem.alloc[u8](a, 37usize)
    if header_error != ok { ret 20i32 }
    header[0] = 1u8
    header[1] = 4u8
    header[2] = 6u8
    header[3] = 37u8
    header[4] = 1u8
    header[5] = 9u8
    header[6] = 3u8
    header[7] = 0u8
    header[8] = 7u8
    header[9] = 11u8
    header[10] = 1u8
    header[11] = 0u8
    header[12] = 2u8
    header[13] = 33u8
    header[14] = 3u8
    header[15] = 1u8
    header[16] = 0u8
    header[17] = 1u8
    header[18] = 0u8
    header[19] = 0u8
    header[20] = 1u8
    header[21] = 12u8
    header[22] = 3u8
    header[23] = 3u8
    header[24] = 0u8
    header[25] = 0u8
    header[26] = 5u8
    header[27] = 1u8
    header[28] = 17u8
    header[29] = 5u8
    header[30] = 0u8
    header[31] = 65u8
    header[32] = 0u8
    header[33] = 0u8
    header[34] = 0u8
    header[35] = 0u8
    header[36] = 0u8
    let (zip, zip_error) = mem.alloc[u8](a, 72usize)
    if zip_error != ok { ret 20i32 }
    var i = 0usize
    while i < 32usize {
        zip[i] = 0u8
        i += 1usize
    }
    zip[0] = 55u8
    zip[1] = 122u8
    zip[2] = 188u8
    zip[3] = 175u8
    zip[4] = 39u8
    zip[5] = 28u8
    zip[6] = 0u8
    zip[7] = 4u8
    put64(zip, 20usize, 37u64)
    put32(zip, 28usize, hash.crc32(header[0..37]))
    put32(zip, 8usize, hash.crc32(zip[12usize..32usize]))
    i = 0usize
    while i < 37usize {
        zip[32usize + i] = header[i]
        i += 1usize
    }
    zip[69] = 65u8
    zip[70] = 1u8
    zip[71] = 1u8
    var (archive, archive_error) = sevenzip.open(a, zip[0..72], zip_limits)
    if archive_error != ok { ret 20i32 }
    let listed = sevenzip.entries(&archive)
    if listed.len != 1usize || !same(listed[0usize].name, "A") || listed[0usize].size != 3u64 { ret 20i32 }
    let (data, data_error) = sevenzip.extract(a, &archive, 0usize)
    if data_error != ok || !same(data, "ABC") { ret 20i32 }

    // 21: two single-coder folders, no SubStreamsInfo: each file reads its own folder's substream
    let (header2, header2_error) = mem.alloc[u8](a, 39usize)
    if header2_error != ok { ret 21i32 }
    header2[0] = 1u8
    header2[1] = 4u8
    header2[2] = 6u8
    header2[3] = 39u8
    header2[4] = 2u8
    header2[5] = 9u8
    header2[6] = 2u8
    header2[7] = 1u8
    header2[8] = 0u8
    header2[9] = 7u8
    header2[10] = 11u8
    header2[11] = 2u8
    header2[12] = 0u8
    header2[13] = 1u8
    header2[14] = 1u8
    header2[15] = 0u8
    header2[16] = 1u8
    header2[17] = 1u8
    header2[18] = 0u8
    header2[19] = 12u8
    header2[20] = 2u8
    header2[21] = 1u8
    header2[22] = 0u8
    header2[23] = 0u8
    header2[24] = 5u8
    header2[25] = 2u8
    header2[26] = 17u8
    header2[27] = 9u8
    header2[28] = 0u8
    header2[29] = 65u8
    header2[30] = 0u8
    header2[31] = 0u8
    header2[32] = 0u8
    header2[33] = 66u8
    header2[34] = 0u8
    header2[35] = 0u8
    header2[36] = 0u8
    header2[37] = 0u8
    header2[38] = 0u8
    let (zip2, zip2_error) = mem.alloc[u8](a, 74usize)
    if zip2_error != ok { ret 21i32 }
    i = 0usize
    while i < 32usize {
        zip2[i] = 0u8
        i += 1usize
    }
    zip2[0] = 55u8
    zip2[1] = 122u8
    zip2[2] = 188u8
    zip2[3] = 175u8
    zip2[4] = 39u8
    zip2[5] = 28u8
    zip2[6] = 0u8
    zip2[7] = 4u8
    put64(zip2, 20usize, 39u64)
    put32(zip2, 28usize, hash.crc32(header2[0..39]))
    put32(zip2, 8usize, hash.crc32(zip2[12usize..32usize]))
    i = 0usize
    while i < 39usize {
        zip2[32usize + i] = header2[i]
        i += 1usize
    }
    zip2[71] = 65u8
    zip2[72] = 66u8
    zip2[73] = 67u8
    var (archive2, archive2_error) = sevenzip.open(a, zip2[0..74], zip_limits)
    if archive2_error != ok { ret 21i32 }
    let listed2 = sevenzip.entries(&archive2)
    if listed2.len != 2usize || !same(listed2[0usize].name, "A") || !same(listed2[1usize].name, "B") { ret 21i32 }
    let (first, first_error) = sevenzip.extract(a, &archive2, 0usize)
    if first_error != ok || !same(first, "AB") { ret 21i32 }
    let (second, second_error) = sevenzip.extract(a, &archive2, 1usize)
    if second_error != ok || !same(second, "C") { ret 21i32 }

    // 22: the EmptyFile bit vector marks the empty-stream entries in order: a file, then a directory
    let (header3, header3_error) = mem.alloc[u8](a, 22usize)
    if header3_error != ok { ret 22i32 }
    header3[0] = 1u8
    header3[1] = 5u8
    header3[2] = 2u8
    header3[3] = 14u8
    header3[4] = 1u8
    header3[5] = 192u8
    header3[6] = 15u8
    header3[7] = 1u8
    header3[8] = 128u8
    header3[9] = 17u8
    header3[10] = 9u8
    header3[11] = 0u8
    header3[12] = 65u8
    header3[13] = 0u8
    header3[14] = 0u8
    header3[15] = 0u8
    header3[16] = 66u8
    header3[17] = 0u8
    header3[18] = 0u8
    header3[19] = 0u8
    header3[20] = 0u8
    header3[21] = 0u8
    let (zip3, zip3_error) = mem.alloc[u8](a, 54usize)
    if zip3_error != ok { ret 22i32 }
    i = 0usize
    while i < 32usize {
        zip3[i] = 0u8
        i += 1usize
    }
    zip3[0] = 55u8
    zip3[1] = 122u8
    zip3[2] = 188u8
    zip3[3] = 175u8
    zip3[4] = 39u8
    zip3[5] = 28u8
    zip3[6] = 0u8
    zip3[7] = 4u8
    put64(zip3, 20usize, 22u64)
    put32(zip3, 28usize, hash.crc32(header3[0..22]))
    put32(zip3, 8usize, hash.crc32(zip3[12usize..32usize]))
    i = 0usize
    while i < 22usize {
        zip3[32usize + i] = header3[i]
        i += 1usize
    }
    var (archive3, archive3_error) = sevenzip.open(a, zip3[0..54], zip_limits)
    if archive3_error != ok { ret 22i32 }
    let listed3 = sevenzip.entries(&archive3)
    if listed3.len != 2usize || listed3[0usize].directory || !listed3[1usize].directory { ret 22i32 }
    let (empty_file, empty_file_error) = sevenzip.extract(a, &archive3, 0usize)
    if empty_file_error != ok || empty_file.len != 0usize { ret 22i32 }
    let (_, directory_error) = sevenzip.extract(a, &archive3, 1usize)
    if directory_error != sevenzip.Invalid { ret 22i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var run_hcl = true
    var run_zip = true
    if args.len > 1usize {
        run_hcl = same(args[1usize], "hcl")
        run_zip = same(args[1usize], "sevenzip")
    }
    if run_hcl {
        let hcl_code = check_hcl(a)
        if hcl_code != 0i32 { os.exit(hcl_code) }
    }
    if run_zip {
        let zip_code = check_sevenzip(a)
        if zip_code != 0i32 { os.exit(zip_code) }
    }
    try io.print("fmt gaps ok\n")
    ret ok
}
