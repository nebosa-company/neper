// The builder half of the string surface. A builder owns the top of an arena, so
// appending is a bump of the arena offset with no reallocation and no copying; the
// one precondition the compiler cannot prove — that nothing else has allocated since
// the builder was made — is checked on every push and reported as `NotOnTop`.
//
// The searching, slicing and joining half is here too. It allocates only where the
// frozen signature takes an arena: every search, trim and split result borrows the
// input. What is still missing is the float pushes, the float parsers, `push_err`
// and `format`.
use e.mem

type Sink = struct { ctx: *void, write: fn(ctx: *void, bytes: []const u8) -> err }

// `Split` carries a whole traversal by value, so iterating allocates nothing. An
// empty `separator` is the one state `split` cannot produce -- it returns
// `InvalidSeparator` instead -- so `lines` marks its own mode with it, which is the
// only spare bit a frozen four-field struct has.
type Split = struct { source: str, separator: str, off: usize, finished: bool }

type Builder = struct { arena: *mem.Arena, start: usize, len: usize, reserved: usize, sink: Sink, flushing: bool }

error NotOnTop
error InvalidSeparator
error BadNumber

fn builder(a: *mem.Arena, cap: usize) -> (Builder, err) {
    var b: Builder = zero
    b.arena = a
    b.start = mem.mark(a)
    if cap > 0usize {
        let (claim, claim_error) = mem.alloc[u8](a, cap)
        if claim_error != ok { ret (b, claim_error) }
        b.reserved = claim.len
    }
    ret (b, ok)
}

fn builder_to(a: *mem.Arena, cap: usize, sink: Sink) -> (Builder, err) {
    var b: Builder = zero
    b.arena = a
    b.start = mem.mark(a)
    b.sink = sink
    b.flushing = true
    if cap > 0usize {
        let (claim, claim_error) = mem.alloc[u8](a, cap)
        if claim_error != ok { ret (b, claim_error) }
        b.reserved = claim.len
    }
    ret (b, ok)
}

fn done(b: *Builder) -> str {
    let bytes = mem.view(b.arena, b.start, b.len)
    // End the claim by giving the unwritten tail back. The written bytes stay below
    // the new offset, so the result outlives the builder exactly as an allocation does.
    if b.arena.off == b.start + b.reserved { mem.reset(b.arena, b.start + b.len) }
    b.reserved = b.len
    ret bytes
}

fn push(b: *Builder, s: str) -> err {
    var written = 0usize
    while true {
        // One compare turns a silent overwrite of somebody else's allocation into an
        // error, and it is the whole cost of the fast path.
        if b.arena.off != b.start + b.reserved { ret NotOnTop }
        if written == s.len { ret ok }
        let room = b.reserved - b.len
        if room > 0usize {
            var take = room
            if take > s.len - written { take = s.len - written }
            let destination = mem.view(b.arena, b.start + b.len, take)
            var at = 0usize
            while at < take {
                destination[at] = s[written + at]
                at += 1usize
            }
            b.len += take
            written += take
            continue
        }
        // Out of room: grow the claim in place. Nothing can sit between the old claim
        // and the new bytes, because the compare above proved the claim is still on
        // top and `u8` needs no alignment padding. Doubling keeps a long run of small
        // pushes linear; the exact retry keeps the last push working in an arena that
        // has room for the bytes but not for the doubling.
        let needed = s.len - written
        var grow = needed
        if grow < b.reserved { grow = b.reserved }
        let (extra, grow_error) = mem.alloc[u8](b.arena, grow)
        if grow_error == ok {
            b.reserved += extra.len
            continue
        }
        if grow > needed {
            let (exact, exact_error) = mem.alloc[u8](b.arena, needed)
            if exact_error == ok {
                b.reserved += exact.len
                continue
            }
        }
        // A builder with no sink stops here; one with a sink drains what it holds and
        // carries on, which is why a push on a flushing builder never reports
        // `mem.Exhausted` and why a push larger than the buffer streams through.
        if !b.flushing || b.len == 0usize { ret grow_error }
        try b.sink.write(b.sink.ctx, mem.view(b.arena, b.start, b.len))
        b.len = 0usize
    }
    ret ok
}

fn push_byte(b: *Builder, v: u8) -> err {
    var one: [1]u8 = zero
    one[0usize] = v
    ret push(b, one[0usize..1usize])
}

fn push_bool(b: *Builder, v: bool) -> err {
    if v { ret push(b, "true") }
    ret push(b, "false")
}

fn push_i8(b: *Builder, v: i8) -> err {
    ret push_i64(b, i64(v))
}

fn push_i16(b: *Builder, v: i16) -> err {
    ret push_i64(b, i64(v))
}

fn push_i32(b: *Builder, v: i32) -> err {
    ret push_i64(b, i64(v))
}

fn push_i64(b: *Builder, v: i64) -> err {
    // 20 digits plus a sign is the widest decimal `i64` has.
    var digits: [21]u8 = zero
    var at = 21usize
    var rest = 0u64
    if v < 0i64 {
        // The most negative `i64` has no positive counterpart, so peel the last digit
        // off before negating: `v % 10` is in `-9..=0` and `v / 10` always negates.
        at -= 1usize
        digits[at] = 48u8 + u8(0i64 - (v % 10i64))
        rest = u64(0i64 - (v / 10i64))
    } else {
        rest = u64(v)
        if rest == 0u64 {
            at -= 1usize
            digits[at] = 48u8
        }
    }
    while rest > 0u64 {
        at -= 1usize
        digits[at] = 48u8 + u8(rest % 10u64)
        rest = rest / 10u64
    }
    if v < 0i64 {
        at -= 1usize
        digits[at] = 45u8
    }
    ret push(b, digits[at..21usize])
}

fn push_isize(b: *Builder, v: isize) -> err {
    ret push_i64(b, i64(v))
}

fn push_u8(b: *Builder, v: u8) -> err {
    ret push_u64(b, u64(v))
}

fn push_u16(b: *Builder, v: u16) -> err {
    ret push_u64(b, u64(v))
}

fn push_u32(b: *Builder, v: u32) -> err {
    ret push_u64(b, u64(v))
}

fn push_u64(b: *Builder, v: u64) -> err {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = v
    if rest == 0u64 {
        at -= 1usize
        digits[at] = 48u8
    }
    while rest > 0u64 {
        at -= 1usize
        digits[at] = 48u8 + u8(rest % 10u64)
        rest = rest / 10u64
    }
    ret push(b, digits[at..20usize])
}

fn push_usize(b: *Builder, v: usize) -> err {
    ret push_u64(b, u64(v))
}

fn push_hex_u32(b: *Builder, v: u32) -> err {
    // `{x}` writes the digits alone, so the narrow form is the wide one's output.
    ret push_hex_u64(b, u64(v))
}

fn push_hex_u64(b: *Builder, v: u64) -> err {
    var digits: [16]u8 = zero
    var at = 16usize
    var rest = v
    if rest == 0u64 {
        at -= 1usize
        digits[at] = 48u8
    }
    while rest > 0u64 {
        at -= 1usize
        let nibble = u8(rest & 15u64)
        if nibble < 10u8 { digits[at] = 48u8 + nibble } else { digits[at] = 87u8 + nibble }
        rest = rest >> 4u64
    }
    ret push(b, digits[at..16usize])
}

// `{.N}`: exactly `precision` digits after the point, rounded half to even. The
// value is expanded to its exact decimal first -- a f64 is a dyadic rational, so it
// has one -- and the rounding then reads digits rather than arithmetic, which is what
// makes a tie a tie. The digit array is large enough for that expansion in full
// (1200 entries against a worst case of about 1091), so nothing is truncated and
// no sticky bit is needed.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `push_f32_fixed`; the two are
// generated from one template rather than written twice.
// `{}`: the fewest significant digits `p` such that the exact value rounded half to even
// to `p` digits reads back as this value. Ryu (D1593) finds them directly, in integer
// arithmetic over a 128-bit power-of-five table, which is the whole cost for every value
// but 46 powers of two: there the rounding interval is lopsided, the nearest
// `p`-digit value can miss it while a farther one hits, and Ryu's `p` is one short of
// this rule's. Those fall back to the exact search -- the value's exact decimal rounded at
// each `p` of a bisection over `1..17`, tested by `parse_f64` -- so every result is the
// one that search defines.
//
// The point is placed per section 4: fixed notation while the leading digit's decimal
// exponent is in `[-5, 15]`, scientific otherwise.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `push_f32`; the two are
// generated from one template rather than written twice.
fn push_f64(b: *Builder, v: f64) -> err {
    let bits = mem.bitcast[u64](v)
    let sign = bits >> 63u64
    let exponent_field = bits >> 52u64 & 2047u64
    let mantissa_field = bits & 4503599627370495u64
    if exponent_field == 2047u64 {
        if mantissa_field != 0u64 { ret push(b, "nan") }
        if sign == 1u64 { ret push(b, "-inf") }
        ret push(b, "inf")
    }
    if exponent_field == 0u64 && mantissa_field == 0u64 {
        if sign == 1u64 { ret push(b, "-0") }
        ret push(b, "0")
    }
    // The shortest digits by Ryu (Adams, PLDI 2018; D1593). `vr`, `vp` and `vm` are the value
    // and the two ends of its rounding interval scaled to decimal by one 128-bit multiply,
    // then shortened together while the ends still differ; at the length that stops, `vr`
    // rounded half to even is the value's correctly rounded digits. That is this function's
    // rule -- the fewest digits whose correct rounding reads back -- except where Ryu bumps
    // `vr` up because it sits on an excluded lower end: at a power of two the interval is
    // lopsided, and there the rule wants more digits, which the exact search below finds.
    var shortest: [24]u8 = zero
    var shortest_used = 0usize
    var shortest_exponent = 0i64
    var settled = false
    // 5^-q scaled up (342 entries, for a binary exponent >= 0) and 5^i scaled down (326
    // entries), 125 significant bits each, as 32 hex digits. Generated by
    // tests/selfhost/fixtures/link/str_float_vectors/powers.py.
    let ryu_inverse = "200000000000000000000000000000011999999999999999999999999999999a147ae147ae147ae147ae147ae147ae1510624dd2f1a9fbe76c8b4395810624de1a36e2eb1c432ca57a786c226809d49614f8b588e368f08461f9f01b866e43ab10c6f7a0b5ed8d36b4c7f349385836221ad7f29abcaf485787a6520ec08d236a15798ee2308c39df9fb841a566d74f88112e0be826d694b2e62d01511f12a6071b7cdfd9d7bdbab7d6ae6881cb5109a415fd7fe17964955fdef1ed34a2a73aea119799812dea11197f27f0f6e885c8bb1c25c268497681c2650cb4be40d60df816849b86a12b9b01ea70909833de71931203af9ee756159b21f3a6e0297ec1431cd2b297d889bc2b6985d7cd0f313537170ef54646d496892137dfd73f5a90f912725dd1d243aba0e75fe645cc4873fa1d83c94fb6d2ac34a5663d3c7a0d865d179ca10c9242235d511e976394d79eb112e3b40a0e9b4f7dda7edf82dd794bc11e392010175ee5962a6498d1625bac68182db34012b25144eeb6e0a781e2f0531357c299a88ea76a58924d52ce4f26a91ef2d0f5da7dd8aa27507bb7b07ea44118c240c4aecb13bb52a6c95fc065503413ce9a36f23c0fc90eebd44c99eaa6901fb0f6be50601941b17953adc3110a80195a5efea6b34767c12ddc8b0274086714484bfeebc29f863424b06f3529a0521039d66589687f9e901d59f290ee19db19f623d5a8a732974cfbc31db4b0295f14c4e977ba1f5bac3d9635b15d59bab2109d8792fb4c495697ab5e277de162281a95a5b7f87a0ef0f2abc9d8c9689d0d154484932d2e725a5bbca17a3aba173e11039d428a8b8eaeafca1ac82efb45cb1b38fb9daa78e44ab2dcf7a6b192094515c72fb1552d836ef57d92ebc141a104116c262777579c58c46475896767b4031be03d0bf225c6f46d6d88dbd8a5ecd2164cfda3281e38c38abe071646eb23db11d7314f534b609c6efe6c11d255b6491c8b821885456760b197134fb6ef8a0e16d601ad376ab91a27ac0f72f8bfa1a51244ce242c5560e1b95672c260994e1e1d3ae36d13bbce35f5571e03cdc2169517624f8a762fd82b2aac18030b01abab12b50c6ec4f31355bbbce0026f3489561dee7a4ad4b81eef92c7ccd0b1eda88917f1fb6f10934bf2dbd30a408e57ba071327fc58da0f6ff57ca8d50071dfc8061ea6608e29b24cbbfaa7bb33e9660cd618851a0b548ea3c99552fc298784d711139dae6f76d88307aaa8c9bad2d0ac0e1f62b0b257c0d1a5dddadc5e1e1aace3191bc08eac9a41517e48b04b4b488a4f141633a556e1cddacb6d59d5d5d3a1d91011c2eaabe7d7e23c577b1177dc817b19b604aaaca62636c6f25e825960cf2a14919d5556eb51c56bf518684780a5bb10747ddddf22a7d1232a79ed060084961a53fc9631d10c81d1dd8fe1a3340756150ffd44f4a73d34a7e4731ae8f66c4510d9976a5d52975d531d28e253f8569e1af5bf109550f22eeb61db03b98d5762159165a6ddda5b58bc4e48cfc7a445e811411e1f17e1e2ad6371d3d96c836b201b9b6364f30304489f1c8628ad9f11cd1615e91d8f359d06e5b06b53be18db0b11ab20e472914a6beaf3890fcb4715a21c45016d841baa4644b8db4c7871bc37169d9abe0349550503c715d6c6c1635f1217aefe690777373638de456bcde9191cf2b1970e72585856c163a2461641c117288e1271f51379df011c81d1ab67ce1286d80ec190dc617f3416ce4155eca51da48ce468e7c7026520247d3556476e17b6d71d20b96c01ea801d30f778392512f8ac174d612334bb99b0f3f92cfa841e5aacf2156838545f5c4e532847f73918488a5b445360437f7d0b75b9d32c2e136d3b7c36a919cf9930d5f7c7dc23581f152bf9f10e8fb28eb4898c72f9d22618ddbcc7f40ba628722a07a38f2e41b813e497065cd61e86c1bb394fa5be9afa1fd424d6faf030d79c5ec2190930f7f6197683df2f268d7949e56814075a5ff8145ecfe5bf520ac76e51201005e1e660104bd984990e6f05f1da800cd181851a1a12f5a0f4e3e4d64fc400148268d4f514dbf7b3f71cb711d96999aa01ed772b10aff95cc5b09274adee1488018ac5bc1ab328946f80ea54497ceda668de092c155c2076bf9a55103aca57b853e4d4241116805effaeaa73623b7960431d76831b5733cb32b110b89d2bf566d1c8bd9e15df5ca28ef40d607dbcc452416d647f117f7d4ed8c33de6cafd69db678ab6cc1bff2ee48e052fd7ab2f0fc572778adf1665bf1d3e6a8cac88f273045b92d58011eaff4a98553d56d3f528d0494244661cab3210f3bb9557b988414d4203a0a316ef5b40c2fc77796139cdd76802e6e9125915cd68c9f92de7617179200252541d5b561574765b7ca568b58e999d5086177c44ddf6c515fd5120913ee14aa6d212c9d0b1923744caa74d40ff1aa21f0e1e0fb44f50586e110baece64f769cb4a180c903f7379f1a73c8bd850c5ee3c3b133d4032c2c7f485ca0979da37f1c9c91ec866b79e0cba6fa9a8c2f6bfe942db18a0522c7e7095262153cf2bccba9be313b374f06526ddb81aa97289709549821f8587e7083e2f8cf775840f1a88759d19379fec0698260a5f9136727ba05e17142c7ff0054684d51940f85b9619e4df1023998cd1053710e100c6afab47ea4c19d28f47b4d524e7ce67a44c453fdd4714a8729fc3ddb71fd852e9d69dccb1061086c219697e2c1979dbee454b0a27381a71368f0f30468f295fe3a211a9d85915275ed8d8f36ba5bab31c81a7bb137a10ec4be0ad8f89516228e39aec95a92f1b13ac9aaf4c0ee89d0e38f7e0ef751715a956e225d67253b0d82d931a592a7911544581b7dec1dc8d79be0f4847552e1bba08cf8c979c94158f967eda0bbb7c162e6d72d6dfb07677a611ff14d62f9711bebdf578b2f391f951a7ff43de8c791c6463225ab7ec1cc21c3ffed2fdad8e16b6b5b5155ff01701b0333242648ad8122bc490dde659ac0159c28e9b83a2461d12d41afca3c2accef604175f3903a317424348ca1c9bbd725e69ac4c2d9c83129b69070816e2fdf5185489d68ae39c1dc574d80cf16b2fee8d540fbdab05c617d12a4670c1228cbed77672fe226b05130dbb6b8d674ed6ff12c528cb4ebc041e7c5f127bd87e24cb513b74787df9a018637f41fcad31b7090dc929f9fe614d1382cc34ca2427c5a0d7d42194cb810a1f37ad21436d0c6f67bfb9cf5478ce7718f9574dcf8a70591fcc94a5dd2d71f913faac3e3fa1f37a7fd6dd517dbdf4c71ff779fd329cb8c3ffbe2ee8c92fee0b1992c7fdc216fa366631bf20a0f324d614756ccb01abfb5eb827cc1a1a5c1d78105df0a267bcc918935309ae7b7ce4601a2fe76a3f9474f41eeb42b0c594a09914f31f8832dd2a5ce58902270476e6e110c27fa028b0eeb0b7a0ce859d2bebe71ad0cc33744e4ab459014a6f61dfdfd81573d68f903ea229e0cdd525e7e64cad11297872d9cbb4ee4d7177518651d6f11b758d848fac54b07be8bee8d6e957e815f7a46a0c89dd59fcba3253df2113201192e9ee706e4aae63c8284318e742801c1e43171a4a1117060d0d3827d86a66167e9c127b6e74126b3da42cecad21eb11fee341fc585cdb88fe1cf0bd574e561ccb0536608d615f419694b462254a231708d0f84d3de77f67abaa29e81dd4e9126d73f9d764b932b95621bb2017dd871d7becc2f23ac1eac223692b668c95a5179657025b6234bbce82ba891ed6de1d12deac01e2b4f6fca53562074bdf18181e3113363787f1943b889cd87964f35918274291c6065adcfc6d4a46c783f5e113529ba7d19eaf1730576e9f06032b1a1eea92a61c3118251a257dcb3cd1de9018bba884e35a79b7481dfe3c30a7e54013c9539d82aec7c5d34b31c9c08651001fa885c8d117a6095211e942cda3b4cd19539e3a40dfb80774db21023e1c90a41442e4fb67196005f715b401cb4a0d50103583fc527ab337f8de299b09080aa719ef3993b72ab8598e304291a80cddd714bf6142f8eef9e13e8d020e200a4b1310991a9bfa58c7e7653d9b3e80083c0f1a8e90f9908e0ca56ec8f864000d2ce4153eda614071a3b78bd3f9e999a423ea10ff151a99f482f93ca994bae1501cbb1b31bb5dc320d18ec775bac49bb3612b15c162b168e70e0bd2c4956a16291a8911678227871f3e6fdbd0778811ba7ba11bd8d03f3e9863e62c80bf401c5d929b16470cff6546b651bd33cc3349e4754911d270cc51055ea7ca8fd68f6e505dd41c83e7ad4e6efdd94419574be3b3c95316cfec8aa52597e10347790982f63aa9123ff06eea847980cf6c60d468c4fbba1d331a4b10d3f59ae57a34870e07f92a175c1508da432ae2512e906c0b39942212b010d3e1cf5581da8ba6bcd5c7a9b51de6815302e5559c90df712e22d90f8717eb9aa8cf1dde16da4c5a8b4f140c6c1322e220a5b17e78aea37ba2a5a9a38a1e9e369aa2b597277dd25f6aa2a905a9187e92154ef7ac1f97db7f888220d154139874ddd8c6234c797c6606ce80a7771f5a549627a36bad8f2d700ae4010bf1191510781fb5efbe0c2459a25000d65a1410d9f9b2f7f2fe701d1481d99a4515100d7b2e28c65bfec017439b147b6a7719af2b7d0e0a2ccaccf205c4ed9243f2148c22ca71a1bd6f0a5b37d0be0e9cc210701bd527b4978c0848f973cb3ee3ce1a4cf9550c5425acda0e5bec78649fb0150a6110d6a9b7bd7b3eaff060507fc010d51a73deee2c9795cbbff3804066331aee90b964b04758efac665266cd7052158ba6fab6f36c472623850eb8a459db113c85955f29236c1e82d0d893b6ae491b9408eefea838acfd9e1af41f8ab07516100725988693bd97b1af29b2d559f711a66c1e139edc97ac8e25baf5777b2c1c3d79c9b8fe2dbf7a7d092b2258c513169794a160cb57cc61fda0ef4ead6a761212dd4de7091309e7fe1a590bbdeec51ceafbafd80e84dca6635d5b45fcb13a172262f3133ed0b0851c4aaf6b308dc81281e8c275cbda26d0e36ef2bc26d7d41d9ca79d894629d7b49f17eac6a48c8617b08617a104ee462a18dfef0550706b12f39e794d9d8b6b54e0b3259dd9f3891e5297287c2f457887cdeb6f62f6527418421286c9bf6ac6d30b22bf825ea85d13680ed23aff889f0f3c1bcc684bb9e41f0ce4839198da9818602c7a4079296d18d71d360e13e21346b356c83394212413df4a91a4dcb4dc388f78a029434db61fcbaa82a16121605a7f2766a86baf8a196fbb9bb44db44d153285ebb9efbfa2145962e2f6a4903daa8ed189618c994e1047824f2bb6d9caeed8a7a11ad6e10c1a0c03b1df8af6117e27729b5e249b4514d6695b193bf80dfe85f549181d490410ab877c142ff9a4cb9e5dd4134aa0d01aac0bf9b9e65c3adf63c9535211014d15566ffafb1eb02f191ca10f74da67711111f32f2f4bc025adb080d92a4852c11b4feb7eb212cd0915e7348eaa0d513415d98932280f0a6dab1f5d3eee710dc4117ad428200c0857bc1917658b8da49d1bf7b9d9cce00d592cf4f23c127c3a94165fc7e170b33de0f0c3f4fcdb96954311e6398126f5cb1a5a365d97161211031ca38f350b22de909056fc24f01ce80416e93f5da2824ba6d9df301d8ce3ecd0125432b14ecea2ebe17f59b13d8323da1d53844ee47dd17968cbc2b52f38395c177603725064a79453d6355dbf602de312c4cf8ea6b6ec76a9782ab165e68b1c1e07b27dd78b13f10f26aab56fd744fa18062864ac6f43273f52222abfdf6a621338205089f29c1f65db4e88997f884e1ec033b40fea93656fc54a7428cc0d4a1899c2f673220f84596aa1f68709a43b13ae3591f5b4d936adeee7f86c07b6961f7d228322baf524497e3ff3e00c57561930e868e89590e9d464fff64cd6ac4514272053ed4473ee4383fff83d7889d1101f4d0ff1038ff1cf9cccc69793a17419cbae7fe805b31c7f6147a425b9025214a2f1ffecd15c16cc4dd2e9b7c7350f10825b3323dab0123d0b0f215fd290d91a6a2b85062ab35061ab4b689950e7c11521bc6a6b555c404e22a2ba1440b96710e7c9eebc4449cd0b4ee894dd0094531b0c764ac6d3a9481217da87c800ed5115a391d56bdc876cdb46486ca000bdda114fa7ddefe39f8a490506bd4ccd64af1bb2a62fe638ff43a8080ac87ae23ab1162884f31e93ff695339a239fbe82ef411ba03f5b20fff8775c7b4fb2fecf25d1c5cd322b67fff3f22d92191e647ea2e16b0a8e891ffff65b57a8141850654f21226ed86db3332b7c4620101373843f51d0b15a491eb84593a366801f1f39fee173c115074bc69e0fb5eb99b27f6198b129674405d6387e72f7efae2865e7ad61dbd86cd6238d971e597f7d0d6fd915617cad23de82d7ac18479930d78cadaab1308a831868ac89ad06142712d6f15561e74404f3daada914d686a4eaf182222185d003f6488aedaa453883ef279b4e8137d99cc506d58aee9dc6cff28615d871f2f5c7a1a488de4a960ae650d6895a418f2b061aea07183bab3beb73ded448313f559e7bee6c1362ef6322c318a9d361feef63f97d79b89e4bd1d13827761f0198bf832dfdfafa183ca7da9352c4e5a146ff9c24cb2f2e79ca1fe20f756a5151059949b708f28b94a1b31b3f9121daa1a28edc580e50df5435eb5ecc1b695dd14ed8b04671da4c435e55e57015ede4a10be08d0527e1d69c4b77eac0118b1d51ac9a7b3b7302f0fa12597799b5ab622156e1fc2f8f358d94db7ac6149155e811124e63593f5e0add7c6238107444b9b1b6e3d2286563449593d059b3ed3ac2b15f1ca820511c36de0fd9e15cbdc89bc118e3b9b37416924b3fe18116fe3a1631c16c5c525357507866359b57fd29bd116789e3750f790d2d1e91491330ee30e11fa182c40c60d7574ba76da8f3f1c0b1cc359e067a348bbedf72490e531c6781702ae4d1fb5d3c98b2c1d40b75b052d12688b70e62b0fd46f567dcd5f7c04241d74124e3d11b2ed7ef0c94898c66d0617900ea4fda7c25798c0a106e09ebd9f12d9a550caec9b79470080d24d4bcae61e29088144adc58ed800ce1d487944a21820d39a9d57d13f1333d8176d2dd082134d76154aaca765a8f646792424a6ce1ee25688777aa56f74bd3d8ea03aa47d18b51206c5fbb78c5d64313ee695506413c40e6bd1962c704ab68dcbebaaa6b71fa01712e8f0471a1124161312aaa457194cdf4253f36c14da8344dc0eeee9df143d7f6843292343e2029d7cd8bf2180103132b9cf541c364e687dfd7a32813319e851294bb9c6bd4a40c9959050ceb814b9da876fc7d2310833d477a6a70bc61094aed2bfd30e8da02976c61eec096b1a877e1dffb81749004257a364acdbdf153931b1996012a0cd01dfb5ea23e31910fa8e27ade6754d70ce4c91881cb5ae1b2a7d0c4970bbaf1ae3adb5a69455e215bb973d078d62f27be957c4854377e81162df64060ab58ec987796a0435f9871bd1656cd67788e475a58f1006bcc27116411df0ab92d3e9f7b7a5a66bca352711cdb18d560f0fee5fc61e1ebca1c41f1c7c4f4889b1b316ffa363646102d36516c9d906d48e28df32e91c504d9bdc51123b140576d820b28f20e37371497d0e1d2b533bf159cdea7e9b0585820f2e7c1755dc2ff447d7eecbaf379e01a5beca12ab168cc36cacbf0958f94b348498a1"
    let ryu_forward = "1000000000000000000000000000000014000000000000000000000000000000190000000000000000000000000000001f40000000000000000000000000000013880000000000000000000000000000186a00000000000000000000000000001e8480000000000000000000000000001312d00000000000000000000000000017d784000000000000000000000000001dcd650000000000000000000000000012a05f20000000000000000000000000174876e80000000000000000000000001d1a94a200000000000000000000000012309ce540000000000000000000000016bcc41e9000000000000000000000001c6bf52634000000000000000000000011c37937e0800000000000000000000016345785d8a0000000000000000000001bc16d674ec8000000000000000000001158e460913d0000000000000000000015af1d78b58c400000000000000000001b1ae4d6e2ef5000000000000000000010f0cf064dd592000000000000000000152d02c7e14af68000000000000000001a784379d99db4200000000000000000108b2a2c28029094000000000000000014adf4b7320334b9000000000000000019d971e4fe8401e740000000000000001027e72f1f12813088000000000000001431e0fae6d7217caa00000000000000193e5939a08ce9dbd4800000000000001f8def8808b02452c9a000000000000013b8b5b5056e16b3be0400000000000018a6e32246c99c60ad850000000000001ed09bead87c0378d8e640000000000013426172c74d822b878fe800000000001812f9cf7920e2b66973e200000000001e17b84357691b6403d0da800000000012ced32a16a1b11e8262889000000000178287f49c4a1d6622fb2ab4000000001d6329f1c35ca4bfabb9f56100000000125dfa371a19e6f7cb54395ca000000016f578c4e0a060b5be2947b3c80000001cb2d6f618c878e32db399a0ba00000011efc659cf7d4b8dfc90400474400000166bb7f0435c9e717bb45005915000001c06a5ec5433c60ddaa16406f5a40000118427b3b4a05bc8a8a4de845986800015e531a0a1c872bad2ce16256fe820001b5e7e08ca3a8f6987819baecbe22800111b0ec57e6499a1f4b1014d3f6d59001561d276ddfdc00a71dd41a08f48af401aba4714957d300d0e549208b31adb1010b46c6cdd6e3e0828f4db456ff0c8ea14e1878814c9cd8a33321216cbecfb241a19e96a19fc40ecbffe969c7ee839ed105031e2503da893f7ff1e21cf51243414643e5ae44d12b8f5fee5aa43256d41197d4df19d605767337e9f14d3eec8921fdca16e04b86d41005e46da08ea7ab613e9e4e4c2f34448a03aec4845928cb218e45e1df3b0155ac849a75a56f72fde1f1d75a5709c1ab17a5c1130ecb4fbd613726987666190aeec798abe93f11d65184f03e93ff9f4daa797ed6e38ed64bf1e62c4e38ff87211517de8c9c728bdef12fdbb0e39fb474ad2eeb17e1c7976b517bd29d1c87a191d87aa5ddda397d4621dac74463a989f64e994f5550c7dc97b128bc8abe49f639f11fd195527ce9ded172ebad6ddc73c86d67c5faa71c245681cfa698c95390ba88c1b77950e32d6c2121c81f7dd43a74957912abd28dfc63916a3a275d494911bad75756c7317b7c81c4c8b1349b9b56298d2d2c78fdda5ba11afd6ec0e14115d9f83c3bcb9ea8794161bcca7119915b50764b4abe86529791ba2bfd0d5ff5b22493de1d6e27e73d71145b7e285bf98f56dc6ad264d8f0866159725db272f7f32c938586fe0f2ca801afcef51f0fb5eff7b866e8bd92f7d2010de1593369d1b5fad34051767bdae3415159af8044462379881065d41ad19c11a5b01b605557ac57ea147f4921860321078e111c3556cbb6f24ccf8db4f3c1f14971956342ac7ea4aee003712230b2719bcdfabc13579e4dda98044d6abcdf010160bcb58c16c2f0a89f02b062b60b6141b8ebe2ef1c73acd2c6c35c7b638e41922726dbaae39098077874339a3c71d1f6b0f092959c74be0956914080cb8e413a2e965b9d81c8f6c5d61ac8507f38e188ba3bf284e23b34774ba17a649f0721eae8caef261aca01951e89d8fdc6c8f132d17ed577d0be40fd3316279e9c3d917f85de8ad5c4edd13c7fdbb186434cf1df67562d8b3629458b9fd29de7d420312ba095dc7701d9cb7743e3a2b0e494217688bb5394c2503e5514dc8b5d1db921d42aea2879f2e44dea5a13ae34652771249ad2594c37ceb0b2784c4ce0bf38a16dc186ef9f45c25cdf165f6018ef06d1c931e8ab871732f416dbf7381f2ac8811dbf316b346e7fd88e497a83137abd51652efdc6018a1fceb1dbd923d8596ca1be7abd3781eca7c25e52cf6cce6fc7d1170cb642b133e8d97af3c1a40105dce15ccfe3d35d80e30fd9b0b20d01475421b403dcc834e11bd3d01cde9041992921108269fd210cb16462120b1a28ffb9b154a3047c694fddbd7a968de0b33fa821a9cbc59b83a3d52cd93c3158e00f92310a1f5b813246653c07c59ed78c09bb614ca732617ed7fe8b09b7068d6f0c2a319fd0fef9de8dfe2dcc24c830cacf34c103e29f5c2b18bedc9f96fd1e7ec180f144db473335deee93c77cbc661e71e131961219000356aa38b95beb7fa60e5981fb969f40042c54c6e7b2e65f8f91efe13d3e2388029bb4fc50cfcffbb9bb35f18c8dac6a0342a23b6503c3faa82a0371efb1178484134aca3e44b4f95234844135ceaeb2d28c0ebe66eaf11bd360d2b183425a5f872f126e00a5ad62c8390751e412f0f768fad70980cf18bb7a4749312e8bd69aa19cc665f0816f752c6c8dc17a2ecc414a03f7ff6ca1cb527787b131d8ba7f519c84f5ff47ca3e2715699d7127748f9301d319bf8cde66d86d6202617151b377c247e02f7016008e88ba8301cda62055b2d9d83b4c1b80b22ae923c12087d4358fc827250f91306f5ad1b65168a9c942f3ba30ee53757c8b318623f1c2d43b93b0a8bd29e852dbadfde7acf119c4a53c4e69763a3133c94cbeb0cc116035ce8b6203d3c8bd80bb9fee5cff11b843422e3a84c8baece0ea87e9f43ee1132a095ce492fd74d40c9294f238a75157f48bb41db7bcd2090fb73a2ec6d121adf1aea12525ac068b53a508ba7885610cb70d24b7378b8417144725748b53614fe4d06de5056e651cd958eed1ae2831a3de04895e46c9fe640faf2a8619b241066ac2d5daec3e3efe89cd7a93d00f714805738b51a74dcebe2c40d938c413419a06d06e261121426db7510f86f5181100444244d7cab4c9849292a9b4592f11405552d60dbd61fbe5b73754216f7ad1906aa78b912cba7adf25052929cb5981f485516e7577e91996ee4673743e2ff138d352e5096af1affe54ec0828a6ddf18708279e4bc5ae1bfdea270a32d09571e8ca3185deb719a2fd64b0ccbf84bad1317e5ef3ab327005de5eee7ff7b2f4c17dddf6b095ff0c0755f6aa1ff59fb1f1dd55745cbb7ecf092b7454a7f3079e712a5568b9f52f4165bb28b4e8f7e4c30174eac2e8727b11bf29f2e22335ddf3c1d22573a28f19d62ef46f9aac035570b123576845997025dd58c5c0ab821566716c2d4256ffcc2f54aef730d6629ac011c73892ecbfbf3b29dab4fd0bfb4170111c835bd3f7d784fa28b11e277d08e60163a432c8f5cd6638b2dd65b15c4b1f91bc8d3f7b3340bfc6df94bf1db35de77115d847ad000877dc4bbcf772901ab0a15b4e5998400a95d35eac354f34215cd1b221effe500d3b48365742a30129b4010f5535fef208450d21f689a5e0ba1081532a837eae8a56506a742c0f58e894a1a7f5245e5a2cebe4851137132f22b9d108f936baf85c136ed32ac26bfd75b4214b378469b673184a87f57306fcd321219e056584240fde5d29f2cfc8bc07e97102c35f729689eafa3a37c1dd7584f1e14374374f3c2c65b8c8c5b254d2e62e61945145230b377f26faf71eea079fb9f1f965966bce055ef0b9b4e6a48987a8713bdf7e0360c35b5674111026d5f4c9418ad75d8438f4322c111554308b71fba1ed8d34e547313eb7155aa93cae4e7a813478410f4c7ec7326d58a9c5ecf10c91819651531f9e78ff08aed437682d4fb1e1fbe5a7e786173ecada89454238a3a12d3d6f88f0b3ce873ec895cb49636641788ccb6b2ce0c2290e7abb3e1bbc3fd1d6affe45f818f2b352196a0da2ab4fd1262dfeebbb0f97b0134fe24885ab11e16fb97ea6a9d37d9c1823dadaa715d651cba7de5054485d031e2cd19150db4bf11f48eaf234ad3a21f2dc02fad2890f71671b25aec1d888aa6f9303b9872b5351c0e1ef1a724eaad50b77c4a7e8f62821188d357087712ac5272adae8f199d9115eb082cca94d757670f591a32e004f61b65ca37fd3a0d2d40d32f60bf980633111f9e62fe44483c4883fd9c77bf03e0156785fbbdd55a4b5aa4fd0395aec4d81ac1677aad4ab0de314e3c447b1a760e10b8e0acac4eae8aded0e5aaccf089c914e718d7d7625a2d96851f15802cac3b1a20df0dcd3af0b8fc2666dae037d74a10548b68a044d6739d980048cc22e68e1469ae42c8560c1084fe005aff2ba032198419d37a6b8f14a63d8071bef6883e1fe52048590672d9cfcce08e2eb42a4e13ef342d37a407c821e00c58dd309a7018eb0138858d09ba2a580f6f147cc10d1f25c186a6f04c28b4ee134ad99bf150137798f428562f997114cc0ec80176d218557f31326bbb7fcd59ff127a01d4861e6adefd7f06aa5fc0b07ed7188249a81302cb5e6f642a7bd86e4f466f516e0917c37e360b3d351ace89e3180b25c98b1db45dc38e0c8261822c5bde0def3bee1290ba9a38c7d17cf15bb96ac8b585751734e940c6f9c5dc2db2a7c57ae2e6d21d022390f8b83753391f51b6d99ba0861221563a9b73229403b393124801445416a9abc9424feb3904a077d6da0195691c5416bb92e3e60745c895cc9081fac311b48e353bce6fc48b9d5d9fda513cba1621b1c28ac20bb5ae84b507d0e58be81baa1e332d728ea31a25e249c51eeee3114a52dffc679925f057ad6e1b33554d159ce797fb817f6f6c6d98c9a2002aa11b04217dfa61df4b4788fefc0a80354910e294eebc7d2b8f0cb59f5d8690214e151b3a2a6b9c7672cfe30734e83429a11a6208b50683940f83dbc9022241340a107d457124123c89b2695da15568c086149c96cd6d16cbac1f03b509aac2f0a719c3bc80c85c7e9726c4a24c1573acd1101a55d07d39cf1e783ae56f8d684c031420eb449c8842e616499ecb70c25f0319292615c3aa539f9bdc067e4cf2f6c41f736f9b3494e88782d3081de02fb47613a825c100dd1154b1c3e512ac1dd0c918922f31411455a9de34de57572544fc1eb6bafd91596b1455c215ed2cee963b133234de7ad7e2ecb5994db43c151de517fec216198ddba7e2ffa1214b1a655e1dfe729b9ff15291dbbf89699de0feb612bf07a143f6d39b2957b5e202ac9f31176ec98994f48881f3ada35a8357c6fe1d4a7bebfa31aaa270990c31242db8bd124e8d737c5f0aa5865fa79eb69c937616e230d05b76cd4ee7f791866443b8541c9abd04725480a2a1f575e7fd54a66911e0b622c774d065a53969b0fe54e8011658e3ab7952047f0e87c41d3dea22021bef1c9657a6859ed229b5248d64aa82117571ddf6c81383435a1136d85eea9115d2ce55747a1864143095848e76a5361b4781ead1989e7d193cbae5b2144e83110cb132c2ff630e2fc5f4cf8f4cb112154fdd7f73bf3bd1bbb77203731fdd561aa3d4df50af0ac62aa54e844fe7d4ac10a6650b926d66bbdaa75112b1f0e4eb14cffe4e7708c06ad15125575e6d1e261a03fde214caf08585a56ead360865b010427ead4cfed6537387652c41c53f8e14531e58a03e8be850693e7752368f711967e5eec84e2ee264838e1526c4334e1fc1df6a7a61ba9afda4719a7075402213d92ba28c7d14a0de86c7008649481518cf768b2f9c59c9162878c0a7db9a1a1f03542dfb83703b5bb296f0d1d280a11362149cbd322625194f9e5683239064183a99c3ec7eafae5fa385ec23ec747e1e494034e79e5b99f78c67672ce7919d12edc82110c2f9403ab7c0a07c10bb0217a93a2954f3b7904965b0c89b14e9c31d9388b3aa30a5745bbf1cfac1da2433127c35704a5e6768b957721cb92856a0171b42cc5cf60142e7ad4ea3e7726c481ce2137f74338193a198a24ce14f075a120d4c2fa8a030fc44ff65700cd1649816909f3b92c83d3b563f3ecc1005bdbe1c34c70a777a4c8a2bcf0e7f14072d2e11a0fc668aac6fd65b61690f6c847c3d16093b802d578bcbf239c35347a59b4c1b8b8a6038ad6ebeeec83428198f021f1137367c236c6537553d20990ff961531585041b2c477e852a8c68bf53f7b9a81ae64521f7595e26752f82ef28f5a81210cfeb353a97dad8093db1d57999890b1503e602893dd18e0b8d1e4ad7ffeb4e1a44df832b8d45f18e7065dd8dffe622106b0bb1fb384bb6f9063faa78bfefd51485ce9e7a065ea4b747cf9516efebca19a742461887f64de519c37a5cabe6bd1008896bcf54f9f0af301a2c79eb7036140aabc6c32a386cdafc20b798664c43190d56b873f4c68811bb28e57e7fdf541f50ac6690f1f82a1629f31ede1fd72a13926bc01a973b1a4dda37f34ad3e67a187706b0213d09e0e150c5f01d88e0191e94c85c298c4c5919a4f76c24eb181f131cfd3999f7afb7b0071aa39712ef1317e43c8800759ba59c08e14c7cd7aad81ddd4baa0093028f030b199f9c0d958e12aa4f4a405be19961e6f003c1887d791754e31cd072d9ffba60ac04b1ea9cd71d2a1be4048f907fa8f8d705de65440d123a516e82d9ba4fc99b8663aaff4a8816c8e5ca239028e3bc0267fc95bf1d2a1c7b1f3cac74331cab0301fbbb2ee47411ccf385ebc89ff1eae1e13d54fd4ec91640306766bac7ee659a598caa3ca27b1bd03c81406979e9ff00efefd4cbcb1a116225d0c841ec323f6095f5e4ff5ef015baaf44fa52673ecf38bb735e3f36ac1b295b1638e7010e8306ea5035cf045710f9d8ede39060a911e4527221a162b615384f295c7478d3565d670eaa09bb641a8662f3b39197082bf4c0d2548c2a3d1093fdd8503afe651b78f88374d79a6614b8fd4e6449bdfe625736a4520d810019e73ca1fd5c2d7dfaed044d6690e140103085e53e599c6ebcd422b0601a8cc8143ca75e8df0038a6c092b5c78212ffa194bd136316c046d070b763396297bf81f9ec583bdc7058848ce53c07bb3daf613c33b72569c63752d80f4584d5068da18b40a4eec437c5278e1316e60a48310"
    var e2 = 0i64
    var m2 = 0u64
    if exponent_field == 0u64 {
        e2 = -1076i64
        m2 = mantissa_field
    } else {
        e2 = i64(exponent_field) - 1077i64
        m2 = mantissa_field | 4503599627370496u64
    }
    let accept_bounds = m2 & 1u64 == 0u64
    let mv = 4u64 * m2
    var mm_shift = 0u64
    if mantissa_field != 0u64 || exponent_field <= 1u64 { mm_shift = 1u64 }
    var vm_zeros = false
    var vr_zeros = false
    var q = 0i64
    var e10 = 0i64
    var shift_by = 0i64
    var entry_text = ryu_inverse
    var entry_at = 0usize
    if e2 >= 0i64 {
        // q = floor(e2 * log10(2)), less one past e2 = 3.
        q = e2 * 78913i64 / 262144i64
        if e2 > 3i64 { q = q - 1i64 }
        e10 = q
        let pow5_bits_q = q * 1217359i64 / 524288i64 + 1i64
        shift_by = 0i64 - e2 + q + 125i64 + pow5_bits_q - 1i64
        entry_at = usize(q) * 32usize
    } else {
        q = (0i64 - e2) * 732923i64 / 1048576i64
        if 0i64 - e2 > 1i64 { q = q - 1i64 }
        e10 = q + e2
        let power_index = 0i64 - e2 - q
        let pow5_bits_i = power_index * 1217359i64 / 524288i64 + 1i64
        shift_by = q - (pow5_bits_i - 125i64)
        entry_text = ryu_forward
        entry_at = usize(power_index) * 32usize
    }
    // The entry's two 64-bit halves.
    var entry_high = 0u64
    var entry_low = 0u64
    var nibble_at = entry_at
    while nibble_at < entry_at + 32usize {
        let symbol = entry_text[nibble_at]
        var nibble = u64(symbol) - 48u64
        if symbol >= 97u8 { nibble = u64(symbol) - 87u64 }
        if nibble_at < entry_at + 16usize {
            entry_high = entry_high << 4u64 | nibble
        } else {
            entry_low = entry_low << 4u64 | nibble
        }
        nibble_at += 1usize
    }
    // (m * entry) >> shift_by for m = 4*m2, 4*m2 + 2 and 4*m2 - 1 - mm_shift: a 64 x 128
    // product from four 32-bit multiplies per half, then a 128-bit shift.
    var vr = 0u64
    var vp = 0u64
    var vm = 0u64
    var which = 0usize
    while which < 3usize {
        var multiplicand = mv
        if which == 1usize { multiplicand = mv + 2u64 }
        if which == 2usize { multiplicand = mv - 1u64 - mm_shift }
        var half_high = 0u64
        var half_low = 0u64
        var sum_high = 0u64
        var sum_low = 0u64
        var part = 0usize
        while part < 2usize {
            var factor = entry_low
            if part == 1usize { factor = entry_high }
            let a_low = multiplicand & 4294967295u64
            let a_high = multiplicand >> 32u64
            let b_low = factor & 4294967295u64
            let b_high = factor >> 32u64
            let p0 = a_low * b_low
            let p1 = a_low * b_high
            let p2 = a_high * b_low
            let p3 = a_high * b_high
            let middle = (p0 >> 32u64) + (p1 & 4294967295u64) + (p2 & 4294967295u64)
            let product_low = ((middle & 4294967295u64) << 32u64) | (p0 & 4294967295u64)
            let product_high = p3 + (p1 >> 32u64) + (p2 >> 32u64) + (middle >> 32u64)
            if part == 0usize {
                half_high = product_high
                half_low = product_low
            } else {
                // (m * low) >> 64 plus m * high: the product's top 128 bits.
                sum_low = product_low +% half_high
                sum_high = product_high
                if sum_low < product_low { sum_high += 1u64 }
            }
            part += 1usize
        }
        let rest_shift = shift_by - 64i64
        var shifted = 0u64
        if rest_shift >= 64i64 {
            shifted = sum_high >> u64(rest_shift - 64i64)
        } else if rest_shift == 0i64 {
            shifted = sum_low
        } else {
            // The result fits 64 bits, so sum_high has no bits at or above rest_shift; the
            // mask says so to the shift.
            let kept_high = sum_high & ((1u64 << u64(rest_shift)) - 1u64)
            shifted = (kept_high << u64(64i64 - rest_shift)) | (sum_low >> u64(rest_shift))
        }
        if which == 0usize { vr = shifted }
        if which == 1usize { vp = shifted }
        if which == 2usize { vm = shifted }
        which += 1usize
    }
    // Whether the dropped digits of vr (or vm) are all zeros, decided exactly where the
    // scaled values can still be integers.
    if e2 >= 0i64 {
        if q <= 21i64 {
            var tested = mv
            if mv % 5u64 != 0u64 {
                if accept_bounds { tested = mv - 1u64 - mm_shift } else { tested = mv + 2u64 }
            }
            var fives = 0i64
            var remaining = tested
            while remaining % 5u64 == 0u64 && fives < q {
                remaining = remaining / 5u64
                fives += 1i64
            }
            if mv % 5u64 == 0u64 {
                vr_zeros = fives >= q
            } else if accept_bounds {
                vm_zeros = fives >= q
            } else if fives >= q {
                vp = vp - 1u64
            }
        }
    } else {
        if q <= 1i64 {
            vr_zeros = true
            if accept_bounds { vm_zeros = mm_shift == 1u64 } else { vp = vp - 1u64 }
        } else if q < 63i64 {
            vr_zeros = mv & ((1u64 << u64(q)) - 1u64) == 0u64
        }
    }
    var removed = 0i64
    var last_removed = 0u64
    while vp / 10u64 > vm / 10u64 {
        vm_zeros = vm_zeros && vm % 10u64 == 0u64
        vr_zeros = vr_zeros && last_removed == 0u64
        last_removed = vr % 10u64
        vr = vr / 10u64
        vp = vp / 10u64
        vm = vm / 10u64
        removed += 1i64
    }
    if vm_zeros {
        while vm % 10u64 == 0u64 {
            vr_zeros = vr_zeros && last_removed == 0u64
            last_removed = vr % 10u64
            vr = vr / 10u64
            vp = vp / 10u64
            vm = vm / 10u64
            removed += 1i64
        }
    }
    // Exactly ...50...0 removed: round half to even.
    if vr_zeros && last_removed == 5u64 && vr % 2u64 == 0u64 { last_removed = 4u64 }
    let round_up = last_removed >= 5u64
    let off_the_end = vr == vm && (!accept_bounds || !vm_zeros)
    if !(off_the_end && !round_up) {
        var output = vr
        if off_the_end || round_up { output += 1u64 }
        var backwards: [24]u8 = zero
        var digit_count = 0usize
        while output > 0u64 {
            backwards[digit_count] = u8(output % 10u64)
            digit_count += 1usize
            output = output / 10u64
        }
        var put = 0usize
        while put < digit_count {
            shortest[put] = backwards[digit_count - 1usize - put]
            put += 1usize
        }
        shortest_used = digit_count
        shortest_exponent = e10 + removed + i64(digit_count)
        while shortest_used > 0usize && shortest[shortest_used - 1usize] == 0u8 { shortest_used = shortest_used - 1usize }
        settled = true
    }
    if !settled {
        var scale = mantissa_field
        var power = 0i64
        if exponent_field == 0u64 {
            power = -1074i64
        } else {
            scale = mantissa_field + 4503599627370496u64
            power = i64(exponent_field) - 1075i64
        }
        // The exact decimal of `scale * 2^power`, as `0.digits * 10^exponent`.
        var digits: [1200]u8 = zero
        var used = 0usize
        var exponent = 0i64
        var reversed: [24]u8 = zero
        var length = 0usize
        var rest = scale
        while rest > 0u64 {
            reversed[length] = u8(rest % 10u64)
            length += 1usize
            rest = rest / 10u64
        }
        exponent = i64(length)
        var back = 0usize
        while back < length {
            digits[back] = reversed[length - 1usize - back]
            back += 1usize
        }
        used = length
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
        var steps = power
        while steps != 0i64 && used != 0usize {
            if steps > 0i64 {
                var carry = 0u8
                var scan = used
                while scan > 0usize {
                    scan = scan - 1usize
                    let value = digits[scan] * 2u8 + carry
                    digits[scan] = value % 10u8
                    carry = value / 10u8
                }
                if carry != 0u8 {
                    used += 1usize
                    var shift = used
                    while shift > 1usize {
                        shift = shift - 1usize
                        digits[shift] = digits[shift - 1usize]
                    }
                    digits[0usize] = carry
                    exponent += 1i64
                }
                steps = steps - 1i64
            } else {
                var remainder = 0u8
                var scan = 0usize
                while scan < used {
                    let value = remainder * 10u8 + digits[scan]
                    digits[scan] = value / 2u8
                    remainder = value % 2u8
                    scan += 1usize
                }
                if remainder != 0u8 {
                    digits[used] = 5u8
                    used += 1usize
                }
                if digits[0usize] == 0u8 {
                    var shift = 0usize
                    while shift + 1usize < used {
                        digits[shift] = digits[shift + 1usize]
                        shift += 1usize
                    }
                    used = used - 1usize
                    exponent = exponent - 1i64
                }
                steps += 1i64
            }
            while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
        }
        // Bisect for the fewest significant digits that read back as this value. The
        // magnitude is what is compared, because the candidate never carries the sign.
        let magnitude = bits & 9223372036854775807u64
        var low = 1usize
        var high = 17usize
        while low < high {
            let middle = (low + high) / 2usize
            var trial: [24]u8 = zero
            var trial_used = middle
            var trial_exponent = exponent
            var fill = 0usize
            while fill < middle {
                var digit = 0u8
                if fill < used { digit = digits[fill] }
                trial[fill] = digit
                fill += 1usize
            }
            var lift = false
            if middle < used {
                let first = digits[middle]
                if first > 5u8 { lift = true }
                if first == 5u8 {
                    var beyond = false
                    var scan = middle + 1usize
                    while scan < used {
                        if digits[scan] != 0u8 { beyond = true }
                        scan += 1usize
                    }
                    if beyond {
                        lift = true
                    } else {
                        lift = trial[middle - 1usize] % 2u8 == 1u8
                    }
                }
            }
            if lift {
                var carry = true
                var at = trial_used
                while at > 0usize && carry {
                    at = at - 1usize
                    if trial[at] == 9u8 {
                        trial[at] = 0u8
                    } else {
                        trial[at] = trial[at] + 1u8
                        carry = false
                    }
                }
                if carry {
                    var shift = trial_used
                    while shift > 0usize {
                        trial[shift] = trial[shift - 1usize]
                        shift = shift - 1usize
                    }
                    trial[0usize] = 1u8
                    trial_used += 1usize
                    trial_exponent += 1i64
                }
            }
            while trial_used > 0usize && trial[trial_used - 1usize] == 0u8 { trial_used = trial_used - 1usize }
            // `0.<digits>e<exponent>` is a spelling `parse_f64` accepts for any candidate.
            var candidate: [40]u8 = zero
            candidate[0usize] = 48u8
            candidate[1usize] = 46u8
            var written = 2usize
            var emit = 0usize
            while emit < trial_used {
                candidate[written] = 48u8 + trial[emit]
                written += 1usize
                emit += 1usize
            }
            candidate[written] = 101u8
            written += 1usize
            var power_left = trial_exponent
            if power_left < 0i64 {
                candidate[written] = 45u8
                written += 1usize
                power_left = 0i64 - power_left
            }
            var power_digits: [8]u8 = zero
            var power_length = 0usize
            while power_left > 0i64 {
                power_digits[power_length] = u8(power_left % 10i64)
                power_length += 1usize
                power_left = power_left / 10i64
            }
            if power_length == 0usize {
                candidate[written] = 48u8
                written += 1usize
            }
            while power_length > 0usize {
                power_length = power_length - 1usize
                candidate[written] = 48u8 + power_digits[power_length]
                written += 1usize
            }
            let (reread, reread_error) = parse_f64(candidate[0usize..written])
            var enough = false
            if reread_error == ok {
                if mem.bitcast[u64](reread) == magnitude { enough = true }
            }
            if enough {
                high = middle
            } else {
                low = middle + 1usize
            }
        }
        // Round once more at the length the bisection settled on, and keep the result.
        shortest_used = low
        shortest_exponent = exponent
        var fill = 0usize
        while fill < low {
            var digit = 0u8
            if fill < used { digit = digits[fill] }
            shortest[fill] = digit
            fill += 1usize
        }
        var lift = false
        if low < used {
            let first = digits[low]
            if first > 5u8 { lift = true }
            if first == 5u8 {
                var beyond = false
                var scan = low + 1usize
                while scan < used {
                    if digits[scan] != 0u8 { beyond = true }
                    scan += 1usize
                }
                if beyond {
                    lift = true
                } else {
                    lift = shortest[low - 1usize] % 2u8 == 1u8
                }
            }
        }
        if lift {
            var carry = true
            var at = shortest_used
            while at > 0usize && carry {
                at = at - 1usize
                if shortest[at] == 9u8 {
                    shortest[at] = 0u8
                } else {
                    shortest[at] = shortest[at] + 1u8
                    carry = false
                }
            }
            if carry {
                var shift = shortest_used
                while shift > 0usize {
                    shortest[shift] = shortest[shift - 1usize]
                    shift = shift - 1usize
                }
                shortest[0usize] = 1u8
                shortest_used += 1usize
                shortest_exponent += 1i64
            }
        }
        while shortest_used > 0usize && shortest[shortest_used - 1usize] == 0u8 { shortest_used = shortest_used - 1usize }
    }
    // Section 4's notation rule is on the leading digit's exponent, which is one less
    // than the exponent of `0.digits`.
    let leading = shortest_exponent - 1i64
    var text: [48]u8 = zero
    var written = 0usize
    if sign == 1u64 {
        text[written] = 45u8
        written += 1usize
    }
    if leading >= -5i64 && leading <= 15i64 {
        if shortest_exponent <= 0i64 {
            text[written] = 48u8
            written += 1usize
            text[written] = 46u8
            written += 1usize
            var fill_count = 0i64 - shortest_exponent
            while fill_count > 0i64 {
                text[written] = 48u8
                written += 1usize
                fill_count = fill_count - 1i64
            }
            var emit = 0usize
            while emit < shortest_used {
                text[written] = 48u8 + shortest[emit]
                written += 1usize
                emit += 1usize
            }
        } else {
            var whole = usize(shortest_exponent)
            var emit = 0usize
            while emit < whole {
                var digit = 0u8
                if emit < shortest_used { digit = shortest[emit] }
                text[written] = 48u8 + digit
                written += 1usize
                emit += 1usize
            }
            if shortest_used > whole {
                text[written] = 46u8
                written += 1usize
                while emit < shortest_used {
                    text[written] = 48u8 + shortest[emit]
                    written += 1usize
                    emit += 1usize
                }
            }
        }
    } else {
        text[written] = 48u8 + shortest[0usize]
        written += 1usize
        if shortest_used > 1usize {
            text[written] = 46u8
            written += 1usize
            var emit = 1usize
            while emit < shortest_used {
                text[written] = 48u8 + shortest[emit]
                written += 1usize
                emit += 1usize
            }
        }
        text[written] = 101u8
        written += 1usize
        var power_left = leading
        if power_left < 0i64 {
            text[written] = 45u8
            written += 1usize
            power_left = 0i64 - power_left
        }
        var power_digits: [8]u8 = zero
        var power_length = 0usize
        while power_left > 0i64 {
            power_digits[power_length] = u8(power_left % 10i64)
            power_length += 1usize
            power_left = power_left / 10i64
        }
        if power_length == 0usize {
            text[written] = 48u8
            written += 1usize
        }
        while power_length > 0usize {
            power_length = power_length - 1usize
            text[written] = 48u8 + power_digits[power_length]
            written += 1usize
        }
    }
    ret push(b, text[0usize..written])
}

// `{}`: the fewest significant digits `p` such that the exact value rounded half to even
// to `p` digits reads back as this value. Ryu (D1593) finds them directly, with 64-bit
// tables; where it bumps a candidate off an excluded lower end of the interval -- at 3
// powers of two -- the rule wants more digits, and the exact search decides: the
// value's exact decimal rounded at each `p` of a bisection over `1..9`, tested by
// `parse_f32`.
//
// The point is placed per section 4: fixed notation while the leading digit's decimal
// exponent is in `[-5, 15]`, scientific otherwise.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `push_f64`; the two are
// generated from one template rather than written twice.
fn push_f32(b: *Builder, v: f32) -> err {
    let bits = mem.bitcast[u32](v)
    let sign = bits >> 31u32
    let exponent_field = bits >> 23u32 & 255u32
    let mantissa_field = bits & 8388607u32
    if exponent_field == 255u32 {
        if mantissa_field != 0u32 { ret push(b, "nan") }
        if sign == 1u32 { ret push(b, "-inf") }
        ret push(b, "inf")
    }
    if exponent_field == 0u32 && mantissa_field == 0u32 {
        if sign == 1u32 { ret push(b, "-0") }
        ret push(b, "0")
    }
    // The shortest digits by Ryu (Adams, PLDI 2018; D1593), as in `push_f64`: the value and
    // the ends of its rounding interval scaled to decimal and shortened together; the
    // correctly rounded digits at that length, except where Ryu bumps `vr` off an excluded
    // lower end, which the exact search below decides.
    var shortest: [24]u8 = zero
    var shortest_used = 0usize
    var shortest_exponent = 0i64
    var settled = false
    // 5^-q scaled up (31 entries, 59 bits) and 5^i scaled down (47 entries, 61 bits), as
    // 16 hex digits. Generated by tests/selfhost/fixtures/link/str_float_vectors/powers.py.
    let ryu_inverse = "08000000000000010666666666666667051eb851eb851eb904189374bc6a7efa068db8bac710cb2a053e2d6238da3c220431bde82d7b634e06b5fca6af2bd216055e63b88c230e78044b82fa09b5a52d06df37f675ef6eae057f5ff85e5925580465e6604b7a84470709709a125da07105a126e1a84ae6c10480ebe7b9d585670734aca5f6226f0b05c3bd5191b525a3049c97747490eae90760f253edb4ab0e05e72843249088d804b8ed0283a6d3e0078e480405d7b966060b6cd004ac945204d5f0a66a23a9db07bcb43d769f762b063090312bb2c4ef04f3a68dbc8f03f307ec3daf94180651065697bfa9acd1da051212ffbaf0a7e2"
    let ryu_forward = "1000000000000000140000000000000019000000000000001f400000000000001388000000000000186a0000000000001e848000000000001312d0000000000017d78400000000001dcd65000000000012a05f2000000000174876e8000000001d1a94a20000000012309ce54000000016bcc41e900000001c6bf5263400000011c37937e080000016345785d8a000001bc16d674ec800001158e460913d000015af1d78b58c40001b1ae4d6e2ef500010f0cf064dd59200152d02c7e14af6801a784379d99db420108b2a2c2802909414adf4b7320334b919d971e4fe8401e71027e72f1f1281301431e0fae6d7217c193e5939a08ce9db1f8def8808b0245213b8b5b5056e16b318a6e32246c99c601ed09bead87c037813426172c74d822b1812f9cf7920e2b61e17b84357691b6412ced32a16a1b11e178287f49c4a1d661d6329f1c35ca4bf125dfa371a19e6f716f578c4e0a060b51cb2d6f618c878e311efc659cf7d4b8d166bb7f0435c9e711c06a5ec5433c60d"
    var e2 = 0i64
    var m2 = 0u64
    if exponent_field == 0u32 {
        e2 = -151i64
        m2 = u64(mantissa_field)
    } else {
        e2 = i64(exponent_field) - 152i64
        m2 = u64(mantissa_field) | 8388608u64
    }
    let accept_bounds = m2 & 1u64 == 0u64
    let mv = 4u64 * m2
    var mm_shift = 0u64
    if mantissa_field != 0u32 || exponent_field <= 1u32 { mm_shift = 1u64 }
    var vm_zeros = false
    var vr_zeros = false
    var last_removed = 0u64
    var q = 0i64
    var e10 = 0i64
    // Up to four scaled products: vr, vp, vm, and -- when the loop below may remove no
    // digit -- the digit vr would have lost one power earlier.
    var job_values: [4]u64 = zero
    var job_entries: [4]usize = zero
    var job_shifts: [4]i64 = zero
    var job_forward = false
    var extra_entry = 0usize
    var extra_shift = 0i64
    if e2 >= 0i64 {
        q = e2 * 78913i64 / 262144i64
        e10 = q
        let pow5_bits_q = q * 1217359i64 / 524288i64 + 1i64
        let shift_q = 0i64 - e2 + q + 59i64 + pow5_bits_q - 1i64
        job_entries[0] = usize(q)
        job_shifts[0] = shift_q
        if q != 0i64 {
            let pow5_bits_before = (q - 1i64) * 1217359i64 / 524288i64 + 1i64
            extra_entry = usize(q - 1i64)
            extra_shift = 0i64 - e2 + q - 1i64 + 59i64 + pow5_bits_before - 1i64
        }
    } else {
        q = (0i64 - e2) * 732923i64 / 1048576i64
        e10 = q + e2
        let power_index = 0i64 - e2 - q
        let pow5_bits_i = power_index * 1217359i64 / 524288i64 + 1i64
        job_entries[0] = usize(power_index)
        job_shifts[0] = q - (pow5_bits_i - 61i64)
        job_forward = true
        if q != 0i64 {
            let pow5_bits_next = (power_index + 1i64) * 1217359i64 / 524288i64 + 1i64
            extra_entry = usize(power_index + 1i64)
            extra_shift = q - 1i64 - (pow5_bits_next - 61i64)
        }
    }
    job_values[0] = mv
    job_values[1] = mv + 2u64
    job_values[2] = mv - 1u64 - mm_shift
    job_entries[1] = job_entries[0]
    job_entries[2] = job_entries[0]
    job_shifts[1] = job_shifts[0]
    job_shifts[2] = job_shifts[0]
    var results: [4]u64 = zero
    var job_count = 3usize
    var job = 0usize
    while job < job_count {
        var entry_text = ryu_inverse
        if job_forward { entry_text = ryu_forward }
        var factor = 0u64
        var nibble_at = job_entries[job] * 16usize
        let nibble_end = nibble_at + 16usize
        while nibble_at < nibble_end {
            let symbol = entry_text[nibble_at]
            var nibble = u64(symbol) - 48u64
            if symbol >= 97u8 { nibble = u64(symbol) - 87u64 }
            factor = factor << 4u64 | nibble
            nibble_at += 1usize
        }
        let multiplicand = job_values[job]
        let a_low = multiplicand & 4294967295u64
        let a_high = multiplicand >> 32u64
        let b_low = factor & 4294967295u64
        let b_high = factor >> 32u64
        let p0 = a_low * b_low
        let p1 = a_low * b_high
        let p2 = a_high * b_low
        let p3 = a_high * b_high
        let middle = (p0 >> 32u64) + (p1 & 4294967295u64) + (p2 & 4294967295u64)
        let product_low = ((middle & 4294967295u64) << 32u64) | (p0 & 4294967295u64)
        let product_high = p3 + (p1 >> 32u64) + (p2 >> 32u64) + (middle >> 32u64)
        let shift = job_shifts[job]
        if shift >= 64i64 {
            results[job] = product_high >> u64(shift - 64i64)
        } else if shift == 0i64 {
            results[job] = product_low
        } else {
            let kept_high = product_high & ((1u64 << u64(shift)) - 1u64)
            results[job] = (kept_high << u64(64i64 - shift)) | (product_low >> u64(shift))
        }
        if job == 2usize && q != 0i64 && (results[1] - 1u64) / 10u64 <= results[2] / 10u64 {
            job_values[3] = mv
            job_entries[3] = extra_entry
            job_shifts[3] = extra_shift
            job_count = 4usize
        }
        job += 1usize
    }
    var vr = results[0]
    var vp = results[1]
    var vm = results[2]
    if job_count == 4usize { last_removed = results[3] % 10u64 }
    if e2 >= 0i64 {
        if q <= 9i64 {
            var tested = mv
            if mv % 5u64 != 0u64 {
                if accept_bounds { tested = mv - 1u64 - mm_shift } else { tested = mv + 2u64 }
            }
            var fives = 0i64
            var remaining = tested
            while remaining % 5u64 == 0u64 && fives < q {
                remaining = remaining / 5u64
                fives += 1i64
            }
            if mv % 5u64 == 0u64 {
                vr_zeros = fives >= q
            } else if accept_bounds {
                vm_zeros = fives >= q
            } else if fives >= q {
                vp = vp - 1u64
            }
        }
    } else {
        if q <= 1i64 {
            vr_zeros = true
            if accept_bounds { vm_zeros = mm_shift == 1u64 } else { vp = vp - 1u64 }
        } else if q < 31i64 {
            vr_zeros = mv & ((1u64 << u64(q - 1i64)) - 1u64) == 0u64
        }
    }
    var removed = 0i64
    while vp / 10u64 > vm / 10u64 {
        vm_zeros = vm_zeros && vm % 10u64 == 0u64
        vr_zeros = vr_zeros && last_removed == 0u64
        last_removed = vr % 10u64
        vr = vr / 10u64
        vp = vp / 10u64
        vm = vm / 10u64
        removed += 1i64
    }
    if vm_zeros {
        while vm % 10u64 == 0u64 {
            vr_zeros = vr_zeros && last_removed == 0u64
            last_removed = vr % 10u64
            vr = vr / 10u64
            vp = vp / 10u64
            vm = vm / 10u64
            removed += 1i64
        }
    }
    if vr_zeros && last_removed == 5u64 && vr % 2u64 == 0u64 { last_removed = 4u64 }
    let round_up = last_removed >= 5u64
    let off_the_end = vr == vm && (!accept_bounds || !vm_zeros)
    if !(off_the_end && !round_up) {
        var output = vr
        if off_the_end || round_up { output += 1u64 }
        var backwards: [24]u8 = zero
        var digit_count = 0usize
        while output > 0u64 {
            backwards[digit_count] = u8(output % 10u64)
            digit_count += 1usize
            output = output / 10u64
        }
        var put = 0usize
        while put < digit_count {
            shortest[put] = backwards[digit_count - 1usize - put]
            put += 1usize
        }
        shortest_used = digit_count
        shortest_exponent = e10 + removed + i64(digit_count)
        while shortest_used > 0usize && shortest[shortest_used - 1usize] == 0u8 { shortest_used = shortest_used - 1usize }
        settled = true
    }
    if !settled {
        var scale = mantissa_field
        var power = 0i64
        if exponent_field == 0u32 {
            power = -149i64
        } else {
            scale = mantissa_field + 8388608u32
            power = i64(exponent_field) - 150i64
        }
        // The exact decimal of `scale * 2^power`, as `0.digits * 10^exponent`.
        var digits: [256]u8 = zero
        var used = 0usize
        var exponent = 0i64
        var reversed: [24]u8 = zero
        var length = 0usize
        var rest = scale
        while rest > 0u32 {
            reversed[length] = u8(rest % 10u32)
            length += 1usize
            rest = rest / 10u32
        }
        exponent = i64(length)
        var back = 0usize
        while back < length {
            digits[back] = reversed[length - 1usize - back]
            back += 1usize
        }
        used = length
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
        var steps = power
        while steps != 0i64 && used != 0usize {
            if steps > 0i64 {
                var carry = 0u8
                var scan = used
                while scan > 0usize {
                    scan = scan - 1usize
                    let value = digits[scan] * 2u8 + carry
                    digits[scan] = value % 10u8
                    carry = value / 10u8
                }
                if carry != 0u8 {
                    used += 1usize
                    var shift = used
                    while shift > 1usize {
                        shift = shift - 1usize
                        digits[shift] = digits[shift - 1usize]
                    }
                    digits[0usize] = carry
                    exponent += 1i64
                }
                steps = steps - 1i64
            } else {
                var remainder = 0u8
                var scan = 0usize
                while scan < used {
                    let value = remainder * 10u8 + digits[scan]
                    digits[scan] = value / 2u8
                    remainder = value % 2u8
                    scan += 1usize
                }
                if remainder != 0u8 {
                    digits[used] = 5u8
                    used += 1usize
                }
                if digits[0usize] == 0u8 {
                    var shift = 0usize
                    while shift + 1usize < used {
                        digits[shift] = digits[shift + 1usize]
                        shift += 1usize
                    }
                    used = used - 1usize
                    exponent = exponent - 1i64
                }
                steps += 1i64
            }
            while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
        }
        // Bisect for the fewest significant digits that read back as this value. The
        // magnitude is what is compared, because the candidate never carries the sign.
        let magnitude = bits & 2147483647u32
        var low = 1usize
        var high = 9usize
        while low < high {
            let middle = (low + high) / 2usize
            var trial: [24]u8 = zero
            var trial_used = middle
            var trial_exponent = exponent
            var fill = 0usize
            while fill < middle {
                var digit = 0u8
                if fill < used { digit = digits[fill] }
                trial[fill] = digit
                fill += 1usize
            }
            var lift = false
            if middle < used {
                let first = digits[middle]
                if first > 5u8 { lift = true }
                if first == 5u8 {
                    var beyond = false
                    var scan = middle + 1usize
                    while scan < used {
                        if digits[scan] != 0u8 { beyond = true }
                        scan += 1usize
                    }
                    if beyond {
                        lift = true
                    } else {
                        lift = trial[middle - 1usize] % 2u8 == 1u8
                    }
                }
            }
            if lift {
                var carry = true
                var at = trial_used
                while at > 0usize && carry {
                    at = at - 1usize
                    if trial[at] == 9u8 {
                        trial[at] = 0u8
                    } else {
                        trial[at] = trial[at] + 1u8
                        carry = false
                    }
                }
                if carry {
                    var shift = trial_used
                    while shift > 0usize {
                        trial[shift] = trial[shift - 1usize]
                        shift = shift - 1usize
                    }
                    trial[0usize] = 1u8
                    trial_used += 1usize
                    trial_exponent += 1i64
                }
            }
            while trial_used > 0usize && trial[trial_used - 1usize] == 0u8 { trial_used = trial_used - 1usize }
            // `0.<digits>e<exponent>` is a spelling `parse_f32` accepts for any candidate.
            var candidate: [40]u8 = zero
            candidate[0usize] = 48u8
            candidate[1usize] = 46u8
            var written = 2usize
            var emit = 0usize
            while emit < trial_used {
                candidate[written] = 48u8 + trial[emit]
                written += 1usize
                emit += 1usize
            }
            candidate[written] = 101u8
            written += 1usize
            var power_left = trial_exponent
            if power_left < 0i64 {
                candidate[written] = 45u8
                written += 1usize
                power_left = 0i64 - power_left
            }
            var power_digits: [8]u8 = zero
            var power_length = 0usize
            while power_left > 0i64 {
                power_digits[power_length] = u8(power_left % 10i64)
                power_length += 1usize
                power_left = power_left / 10i64
            }
            if power_length == 0usize {
                candidate[written] = 48u8
                written += 1usize
            }
            while power_length > 0usize {
                power_length = power_length - 1usize
                candidate[written] = 48u8 + power_digits[power_length]
                written += 1usize
            }
            let (reread, reread_error) = parse_f32(candidate[0usize..written])
            var enough = false
            if reread_error == ok {
                if mem.bitcast[u32](reread) == magnitude { enough = true }
            }
            if enough {
                high = middle
            } else {
                low = middle + 1usize
            }
        }
        // Round once more at the length the bisection settled on, and keep the result.
        shortest_used = low
        shortest_exponent = exponent
        var fill = 0usize
        while fill < low {
            var digit = 0u8
            if fill < used { digit = digits[fill] }
            shortest[fill] = digit
            fill += 1usize
        }
        var lift = false
        if low < used {
            let first = digits[low]
            if first > 5u8 { lift = true }
            if first == 5u8 {
                var beyond = false
                var scan = low + 1usize
                while scan < used {
                    if digits[scan] != 0u8 { beyond = true }
                    scan += 1usize
                }
                if beyond {
                    lift = true
                } else {
                    lift = shortest[low - 1usize] % 2u8 == 1u8
                }
            }
        }
        if lift {
            var carry = true
            var at = shortest_used
            while at > 0usize && carry {
                at = at - 1usize
                if shortest[at] == 9u8 {
                    shortest[at] = 0u8
                } else {
                    shortest[at] = shortest[at] + 1u8
                    carry = false
                }
            }
            if carry {
                var shift = shortest_used
                while shift > 0usize {
                    shortest[shift] = shortest[shift - 1usize]
                    shift = shift - 1usize
                }
                shortest[0usize] = 1u8
                shortest_used += 1usize
                shortest_exponent += 1i64
            }
        }
        while shortest_used > 0usize && shortest[shortest_used - 1usize] == 0u8 { shortest_used = shortest_used - 1usize }
    }
    // Section 4's notation rule is on the leading digit's exponent, which is one less
    // than the exponent of `0.digits`.
    let leading = shortest_exponent - 1i64
    var text: [48]u8 = zero
    var written = 0usize
    if sign == 1u32 {
        text[written] = 45u8
        written += 1usize
    }
    if leading >= -5i64 && leading <= 15i64 {
        if shortest_exponent <= 0i64 {
            text[written] = 48u8
            written += 1usize
            text[written] = 46u8
            written += 1usize
            var fill_count = 0i64 - shortest_exponent
            while fill_count > 0i64 {
                text[written] = 48u8
                written += 1usize
                fill_count = fill_count - 1i64
            }
            var emit = 0usize
            while emit < shortest_used {
                text[written] = 48u8 + shortest[emit]
                written += 1usize
                emit += 1usize
            }
        } else {
            var whole = usize(shortest_exponent)
            var emit = 0usize
            while emit < whole {
                var digit = 0u8
                if emit < shortest_used { digit = shortest[emit] }
                text[written] = 48u8 + digit
                written += 1usize
                emit += 1usize
            }
            if shortest_used > whole {
                text[written] = 46u8
                written += 1usize
                while emit < shortest_used {
                    text[written] = 48u8 + shortest[emit]
                    written += 1usize
                    emit += 1usize
                }
            }
        }
    } else {
        text[written] = 48u8 + shortest[0usize]
        written += 1usize
        if shortest_used > 1usize {
            text[written] = 46u8
            written += 1usize
            var emit = 1usize
            while emit < shortest_used {
                text[written] = 48u8 + shortest[emit]
                written += 1usize
                emit += 1usize
            }
        }
        text[written] = 101u8
        written += 1usize
        var power_left = leading
        if power_left < 0i64 {
            text[written] = 45u8
            written += 1usize
            power_left = 0i64 - power_left
        }
        var power_digits: [8]u8 = zero
        var power_length = 0usize
        while power_left > 0i64 {
            power_digits[power_length] = u8(power_left % 10i64)
            power_length += 1usize
            power_left = power_left / 10i64
        }
        if power_length == 0usize {
            text[written] = 48u8
            written += 1usize
        }
        while power_length > 0usize {
            power_length = power_length - 1usize
            text[written] = 48u8 + power_digits[power_length]
            written += 1usize
        }
    }
    ret push(b, text[0usize..written])
}

fn push_f64_fixed(b: *Builder, v: f64, precision: u8) -> err {
    if precision > 99u8 { ret BadNumber }
    let bits = mem.bitcast[u64](v)
    let sign = bits >> 63u64
    let exponent_field = bits >> 52u64 & 2047u64
    let mantissa_field = bits & 4503599627370495u64
    // A non-finite value writes its token and no fractional suffix at all.
    if exponent_field == 2047u64 {
        if mantissa_field != 0u64 { ret push(b, "nan") }
        if sign == 1u64 { ret push(b, "-inf") }
        ret push(b, "inf")
    }
    // The value is `scale * 2^power`, exactly.
    var scale = mantissa_field
    var power = 0i64
    if exponent_field == 0u64 {
        power = -1074i64
    } else {
        scale = mantissa_field + 4503599627370496u64
        power = i64(exponent_field) - 1075i64
    }
    var digits: [1200]u8 = zero
    var used = 0usize
    var exponent = 0i64
    if scale != 0u64 {
        var reversed: [24]u8 = zero
        var length = 0usize
        var rest = scale
        while rest > 0u64 {
            reversed[length] = u8(rest % 10u64)
            length += 1usize
            rest = rest / 10u64
        }
        exponent = i64(length)
        var back = 0usize
        while back < length {
            digits[back] = reversed[length - 1usize - back]
            back += 1usize
        }
        used = length
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // Apply the binary exponent one bit at a time, which keeps the decimal exact.
    var steps = power
    while steps != 0i64 && used != 0usize {
        if steps > 0i64 {
            var carry = 0u8
            var scan = used
            while scan > 0usize {
                scan = scan - 1usize
                let value = digits[scan] * 2u8 + carry
                digits[scan] = value % 10u8
                carry = value / 10u8
            }
            if carry != 0u8 {
                used += 1usize
                var shift = used
                while shift > 1usize {
                    shift = shift - 1usize
                    digits[shift] = digits[shift - 1usize]
                }
                digits[0usize] = carry
                exponent += 1i64
            }
            steps = steps - 1i64
        } else {
            var remainder = 0u8
            var scan = 0usize
            while scan < used {
                let value = remainder * 10u8 + digits[scan]
                digits[scan] = value / 2u8
                remainder = value % 2u8
                scan += 1usize
            }
            if remainder != 0u8 {
                digits[used] = 5u8
                used += 1usize
            }
            if digits[0usize] == 0u8 {
                var shift = 0usize
                while shift + 1usize < used {
                    digits[shift] = digits[shift + 1usize]
                    shift += 1usize
                }
                used = used - 1usize
                exponent = exponent - 1i64
            }
            steps += 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // `cut` is how many digits of `digits` survive scaling by `10^precision`, which
    // makes the answer an integer and the rounding an ordinary digit comparison.
    let places = usize(precision)
    var cut = exponent + i64(places)
    var round_up = false
    if cut >= 0i64 && usize(cut) < used {
        let first = digits[usize(cut)]
        if first > 5u8 { round_up = true }
        if first == 5u8 {
            var beyond = false
            var scan = usize(cut) + 1usize
            while scan < used {
                if digits[scan] != 0u8 { beyond = true }
                scan += 1usize
            }
            if beyond {
                round_up = true
            } else {
                // An exact tie goes to the even last kept digit; a digit past the end
                // of the expansion is a zero, which is even.
                var last = 0u8
                if cut > 0i64 && usize(cut) - 1usize < used { last = digits[usize(cut) - 1usize] }
                round_up = last % 2u8 == 1u8
            }
        }
    }
    var kept: [512]u8 = zero
    var digits_kept = 0usize
    if cut > 0i64 { digits_kept = usize(cut) }
    var at = 0usize
    while at < digits_kept {
        var digit = 0u8
        if at < used { digit = digits[at] }
        kept[at] = digit
        at += 1usize
    }
    if round_up {
        var carry = true
        var back = digits_kept
        while back > 0usize && carry {
            back = back - 1usize
            if kept[back] == 9u8 {
                kept[back] = 0u8
            } else {
                kept[back] = kept[back] + 1u8
                carry = false
            }
        }
        if carry {
            var shift = digits_kept
            while shift > 0usize {
                kept[shift] = kept[shift - 1usize]
                shift = shift - 1usize
            }
            kept[0usize] = 1u8
            digits_kept += 1usize
        }
    }
    // The kept digits are the value times `10^precision`; the point goes that many
    // places from the right, and a sign is written even for a negative zero.
    var text: [512]u8 = zero
    var length = 0usize
    if sign == 1u64 {
        text[0usize] = 45u8
        length = 1usize
    }
    if digits_kept > places {
        var whole = 0usize
        while whole < digits_kept - places {
            text[length] = 48u8 + kept[whole]
            length += 1usize
            whole += 1usize
        }
    } else {
        text[length] = 48u8
        length += 1usize
    }
    if places > 0usize {
        text[length] = 46u8
        length += 1usize
        var fill_count = 0usize
        if digits_kept < places { fill_count = places - digits_kept }
        while fill_count > 0usize {
            text[length] = 48u8
            length += 1usize
            fill_count = fill_count - 1usize
        }
        var tail = 0usize
        if digits_kept > places { tail = digits_kept - places }
        while tail < digits_kept {
            text[length] = 48u8 + kept[tail]
            length += 1usize
            tail += 1usize
        }
    }
    ret push(b, text[0usize..length])
}

// `{.N}`: exactly `precision` digits after the point, rounded half to even. The
// value is expanded to its exact decimal first -- a f32 is a dyadic rational, so it
// has one -- and the rounding then reads digits rather than arithmetic, which is what
// makes a tie a tie. The digit array is large enough for that expansion in full
// (256 entries against a worst case of about 173), so nothing is truncated and
// no sticky bit is needed.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `push_f64_fixed`; the two are
// generated from one template rather than written twice.
fn push_f32_fixed(b: *Builder, v: f32, precision: u8) -> err {
    if precision > 99u8 { ret BadNumber }
    let bits = mem.bitcast[u32](v)
    let sign = bits >> 31u32
    let exponent_field = bits >> 23u32 & 255u32
    let mantissa_field = bits & 8388607u32
    // A non-finite value writes its token and no fractional suffix at all.
    if exponent_field == 255u32 {
        if mantissa_field != 0u32 { ret push(b, "nan") }
        if sign == 1u32 { ret push(b, "-inf") }
        ret push(b, "inf")
    }
    // The value is `scale * 2^power`, exactly.
    var scale = mantissa_field
    var power = 0i64
    if exponent_field == 0u32 {
        power = -149i64
    } else {
        scale = mantissa_field + 8388608u32
        power = i64(exponent_field) - 150i64
    }
    var digits: [256]u8 = zero
    var used = 0usize
    var exponent = 0i64
    if scale != 0u32 {
        var reversed: [24]u8 = zero
        var length = 0usize
        var rest = scale
        while rest > 0u32 {
            reversed[length] = u8(rest % 10u32)
            length += 1usize
            rest = rest / 10u32
        }
        exponent = i64(length)
        var back = 0usize
        while back < length {
            digits[back] = reversed[length - 1usize - back]
            back += 1usize
        }
        used = length
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // Apply the binary exponent one bit at a time, which keeps the decimal exact.
    var steps = power
    while steps != 0i64 && used != 0usize {
        if steps > 0i64 {
            var carry = 0u8
            var scan = used
            while scan > 0usize {
                scan = scan - 1usize
                let value = digits[scan] * 2u8 + carry
                digits[scan] = value % 10u8
                carry = value / 10u8
            }
            if carry != 0u8 {
                used += 1usize
                var shift = used
                while shift > 1usize {
                    shift = shift - 1usize
                    digits[shift] = digits[shift - 1usize]
                }
                digits[0usize] = carry
                exponent += 1i64
            }
            steps = steps - 1i64
        } else {
            var remainder = 0u8
            var scan = 0usize
            while scan < used {
                let value = remainder * 10u8 + digits[scan]
                digits[scan] = value / 2u8
                remainder = value % 2u8
                scan += 1usize
            }
            if remainder != 0u8 {
                digits[used] = 5u8
                used += 1usize
            }
            if digits[0usize] == 0u8 {
                var shift = 0usize
                while shift + 1usize < used {
                    digits[shift] = digits[shift + 1usize]
                    shift += 1usize
                }
                used = used - 1usize
                exponent = exponent - 1i64
            }
            steps += 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // `cut` is how many digits of `digits` survive scaling by `10^precision`, which
    // makes the answer an integer and the rounding an ordinary digit comparison.
    let places = usize(precision)
    var cut = exponent + i64(places)
    var round_up = false
    if cut >= 0i64 && usize(cut) < used {
        let first = digits[usize(cut)]
        if first > 5u8 { round_up = true }
        if first == 5u8 {
            var beyond = false
            var scan = usize(cut) + 1usize
            while scan < used {
                if digits[scan] != 0u8 { beyond = true }
                scan += 1usize
            }
            if beyond {
                round_up = true
            } else {
                // An exact tie goes to the even last kept digit; a digit past the end
                // of the expansion is a zero, which is even.
                var last = 0u8
                if cut > 0i64 && usize(cut) - 1usize < used { last = digits[usize(cut) - 1usize] }
                round_up = last % 2u8 == 1u8
            }
        }
    }
    var kept: [256]u8 = zero
    var digits_kept = 0usize
    if cut > 0i64 { digits_kept = usize(cut) }
    var at = 0usize
    while at < digits_kept {
        var digit = 0u8
        if at < used { digit = digits[at] }
        kept[at] = digit
        at += 1usize
    }
    if round_up {
        var carry = true
        var back = digits_kept
        while back > 0usize && carry {
            back = back - 1usize
            if kept[back] == 9u8 {
                kept[back] = 0u8
            } else {
                kept[back] = kept[back] + 1u8
                carry = false
            }
        }
        if carry {
            var shift = digits_kept
            while shift > 0usize {
                kept[shift] = kept[shift - 1usize]
                shift = shift - 1usize
            }
            kept[0usize] = 1u8
            digits_kept += 1usize
        }
    }
    // The kept digits are the value times `10^precision`; the point goes that many
    // places from the right, and a sign is written even for a negative zero.
    var text: [256]u8 = zero
    var length = 0usize
    if sign == 1u32 {
        text[0usize] = 45u8
        length = 1usize
    }
    if digits_kept > places {
        var whole = 0usize
        while whole < digits_kept - places {
            text[length] = 48u8 + kept[whole]
            length += 1usize
            whole += 1usize
        }
    } else {
        text[length] = 48u8
        length += 1usize
    }
    if places > 0usize {
        text[length] = 46u8
        length += 1usize
        var fill_count = 0usize
        if digits_kept < places { fill_count = places - digits_kept }
        while fill_count > 0usize {
            text[length] = 48u8
            length += 1usize
            fill_count = fill_count - 1usize
        }
        var tail = 0usize
        if digits_kept > places { tail = digits_kept - places }
        while tail < digits_kept {
            text[length] = 48u8 + kept[tail]
            length += 1usize
            tail += 1usize
        }
    }
    ret push(b, text[0usize..length])
}

fn push_bin_u32(b: *Builder, v: u32) -> err {
    ret push_bin_u64(b, u64(v))
}

fn push_bin_u64(b: *Builder, v: u64) -> err {
    var digits: [64]u8 = zero
    var at = 64usize
    var rest = v
    if rest == 0u64 {
        at -= 1usize
        digits[at] = 48u8
    }
    while rest > 0u64 {
        at -= 1usize
        digits[at] = 48u8 + u8(rest & 1u64)
        rest = rest >> 1u64
    }
    ret push(b, digits[at..64usize])
}

fn concat(a: *mem.Arena, x: str, y: str) -> (str, err) {
    var (b, builder_error) = builder(a, x.len + y.len)
    if builder_error != ok { ret ("", builder_error) }
    let x_error = push(&b, x)
    if x_error != ok { ret ("", x_error) }
    let y_error = push(&b, y)
    if y_error != ok { ret ("", y_error) }
    let out = done(&b)
    ret (out, ok)
}

fn join(a: *mem.Arena, parts: []const str, sep: str) -> (str, err) {
    // The exact size up front, so the one claim covers the whole result and the
    // builder never has to grow.
    var total = 0usize
    var at = 0usize
    while at < parts.len {
        total += parts[at].len
        at += 1usize
    }
    if parts.len > 1usize { total += sep.len * (parts.len - 1usize) }
    var (b, builder_error) = builder(a, total)
    if builder_error != ok { ret ("", builder_error) }
    at = 0usize
    while at < parts.len {
        if at > 0usize {
            let sep_error = push(&b, sep)
            if sep_error != ok { ret ("", sep_error) }
        }
        let part_error = push(&b, parts[at])
        if part_error != ok { ret ("", part_error) }
        at += 1usize
    }
    let out = done(&b)
    ret (out, ok)
}

fn eq(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var at = 0usize
    while at < x.len {
        if x[at] != y[at] { ret false }
        at += 1usize
    }
    ret true
}

fn parse_i64(s: str) -> (i64, err) {
    let (value, value_error) = parse_i64_radix(s, 10u8)
    ret (value, value_error)
}

fn parse_u64(s: str) -> (u64, err) {
    let (value, value_error) = parse_u64_radix(s, 10u8)
    ret (value, value_error)
}

// The magnitude is parsed unsigned, because `i64`'s most negative value has no
// positive counterpart to build and then negate. Its own magnitude is written out
// rather than converted: section 4 makes `i64(x)` checked, so `i64` of 2**63 is a
// `narrow` trap the moment section 11's check table is emitted, even though the
// current back end truncates it to the answer this returns.
fn parse_i64_radix(s: str, radix: u8) -> (i64, err) {
    var digits = s
    var negative = false
    if s.len > 0usize && s[0usize] == 45u8 {
        negative = true
        digits = s[1usize..]
    }
    let (magnitude, magnitude_error) = parse_u64_radix(digits, radix)
    if magnitude_error != ok { ret (0i64, magnitude_error) }
    if negative {
        if magnitude > 9223372036854775808u64 { ret (0i64, BadNumber) }
        if magnitude == 9223372036854775808u64 { ret (-9223372036854775807i64 - 1i64, ok) }
        ret (0i64 - i64(magnitude), ok)
    }
    if magnitude > 9223372036854775807u64 { ret (0i64, BadNumber) }
    ret (i64(magnitude), ok)
}

// Every byte is a digit or the input is malformed: no sign, no prefix, no separators
// and no surrounding space. Overflow is checked before the multiply rather than
// after, because there is no wrapping arithmetic to detect it with.
fn parse_u64_radix(s: str, radix: u8) -> (u64, err) {
    if radix < 2u8 || radix > 36u8 { ret (0u64, BadNumber) }
    if s.len == 0usize { ret (0u64, BadNumber) }
    let base = u64(radix)
    let limit = 18446744073709551615u64
    var value = 0u64
    var at = 0usize
    while at < s.len {
        let byte = s[at]
        // 37 is past every radix, so a byte that is not a digit at all fails the
        // same comparison as one that is out of range for this radix.
        var digit = 37u8
        if byte >= 48u8 && byte <= 57u8 { digit = byte - 48u8 }
        if byte >= 65u8 && byte <= 90u8 { digit = byte - 55u8 }
        if byte >= 97u8 && byte <= 122u8 { digit = byte - 87u8 }
        if digit >= radix { ret (0u64, BadNumber) }
        let scaled = u64(digit)
        if value > (limit - scaled) / base { ret (0u64, BadNumber) }
        value = value * base + scaled
        at += 1usize
    }
    ret (value, ok)
}

// The exact inverse of what `push_f64` writes: the nearest f64 to the input, ties to even.
// Up to 19 significant digits take a fast path (D1593) -- Clinger's single exact IEEE
// operation, or Eisel-Lemire's 128-bit multiply by a power of five -- whose answer is that
// same nearest double. Longer inputs, and the rare product that cannot decide the
// rounding, take the exact path: the digits become an arbitrary-precision decimal that is
// halved and doubled one bit at a time until the binary exponent falls out and the
// mantissa can be read off the front. That path is linear in the decimal exponent, about
// a thousand passes over the digits near either end of the range.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `parse_f32`; the two are
// generated from one template rather than written twice.
fn parse_f64(s: str) -> (f64, err) {
    // The non-finite spellings are exact tokens, not numbers, and the NaN handed back
    // is section 11's canonical quiet one rather than whatever an operation produced.
    if eq(s, "inf") { ret (mem.bitcast[f64](9218868437227405312u64), ok) }
    if eq(s, "-inf") { ret (mem.bitcast[f64](18442240474082181120u64), ok) }
    if eq(s, "nan") { ret (mem.bitcast[f64](9221120237041090560u64), ok) }
    // 768 digits is past the longest exact tie this width has (768 of them),
    // so a tie always fits and a decimal that does not fit is never one: what
    // spills past the end can only be the sticky bit `truncated` carries.
    var digits: [768]u8 = zero
    var used = 0usize
    var truncated = false
    var negative = false
    var at = 0usize
    if s.len > 0usize && s[0usize] == 45u8 {
        negative = true
        at = 1usize
    }
    // The grammar is the one the pushes write and nothing else: at least one digit,
    // at most one point with digits on both sides, no separators, no leading `+`, no
    // surrounding space, and a lowercase `e` exponent with at least one digit.
    var integer_digits = 0usize
    var fraction_digits = 0usize
    var leading_zeros = 0usize
    var started = false
    var in_fraction = false
    while at < s.len {
        let byte = s[at]
        if byte == 46u8 && !in_fraction && integer_digits > 0usize {
            in_fraction = true
            at += 1usize
            continue
        }
        if byte < 48u8 || byte > 57u8 { break }
        if in_fraction { fraction_digits += 1usize } else { integer_digits += 1usize }
        let digit = byte - 48u8
        if !started && digit == 0u8 {
            leading_zeros += 1usize
        } else {
            started = true
            if used < digits.len {
                digits[used] = digit
                used += 1usize
            } else {
                if digit != 0u8 { truncated = true }
            }
        }
        at += 1usize
    }
    if integer_digits == 0usize { ret (0.0f64, BadNumber) }
    if in_fraction && fraction_digits == 0usize { ret (0.0f64, BadNumber) }
    // `I.F` is `0.(I F) * 10^len(I)`, and every leading zero dropped takes one off it.
    var exponent = i64(integer_digits) - i64(leading_zeros)
    if at < s.len && s[at] == 101u8 {
        at += 1usize
        var exponent_negative = false
        if at < s.len && (s[at] == 43u8 || s[at] == 45u8) {
            exponent_negative = s[at] == 45u8
            at += 1usize
        }
        var magnitude = 0i64
        var exponent_digits = 0usize
        while at < s.len {
            let byte = s[at]
            if byte < 48u8 || byte > 57u8 { break }
            exponent_digits += 1usize
            // Past six digits the value is out of range either way, and the clamp is
            // what keeps the normalization below finite.
            if magnitude < 1000000i64 { magnitude = magnitude * 10i64 + i64(byte - 48u8) }
            at += 1usize
        }
        if exponent_digits == 0usize { ret (0.0f64, BadNumber) }
        if exponent_negative { exponent = exponent - magnitude } else { exponent = exponent + magnitude }
    }
    if at != s.len { ret (0.0f64, BadNumber) }
    while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    // An exact zero keeps its sign; it is the one zero a parse may return.
    if used == 0usize {
        var zero_pattern = 0u64
        if negative { zero_pattern = 9223372036854775808u64 }
        ret (mem.bitcast[f64](zero_pattern), ok)
    }
    // Bounds that only keep the loops finite. Anything outside them is out of range by
    // a wide margin; anything inside is decided exactly below.
    if exponent > 400i64 || exponent < -450i64 { ret (0.0f64, BadNumber) }
    // The fast paths (D1593). Up to 19 significant digits are an exact integer `w`, and
    // the value is `w * 10^q`. Clinger: when `w` is at most 2^53 and `|q|` at most 22,
    // both operands are exact doubles, so one IEEE multiply or divide is the correctly
    // rounded answer. Eisel-Lemire: otherwise `w` times a 128-bit truncation of 5^q
    // decides the rounding from its top bits, and when the truncation leaves it undecided
    // the exact path below takes over. Both answer the nearest double, ties to even --
    // the same bits the exact path computes -- and a zero or an infinity is the same
    // BadNumber it reports.
    if !truncated && used <= 19usize {
        var w = 0u64
        var taken_digits = 0usize
        while taken_digits < used {
            w = w * 10u64 + u64(digits[taken_digits])
            taken_digits += 1usize
        }
        let q = exponent - i64(used)
        var fast_bits = 0u64
        var fast_done = false
        if w <= 9007199254740992u64 && q >= -22i64 && q <= 22i64 {
            // Every power of ten up to 10^22 is exact, and so is each product that builds it.
            var power_of_ten = 1.0f64
            var raised = 0i64
            var reach = q
            if reach < 0i64 { reach = 0i64 - reach }
            while raised < reach {
                power_of_ten = power_of_ten * 10.0f64
                raised += 1i64
            }
            var nearest = f64(w)
            if q >= 0i64 {
                nearest = nearest * power_of_ten
            } else {
                nearest = nearest / power_of_ten
            }
            fast_bits = mem.bitcast[u64](nearest)
            fast_done = true
        } else if q >= -342i64 && q <= 308i64 {
            // 5^q for q in [-342, 308], each as 32 hex digits: the top 128 bits, truncated
            // (for q < 0, of 2^k / 5^-q rounded up). Generated by
            // tests/selfhost/fixtures/link/str_float_vectors/powers.py.
            let powers = "eef453d6923bd65a113faa2906a13b3f9558b4661b6565f84ac7ca59a424c507baaee17fa23ebf765d79bcf00d2df649e95a99df8ace6f53f4d82c2c107973dc91d8a02bb6c1059479071b9b8a4be869b64ec836a47146f99748e2826cdee284e3e27a444d8d98b7fd1b1b2308169b258e6d8c6ab0787f72fe30f0f5e50e20f7b208ef855c969f4fbdbd2d335e51a935de8b2b66b3bc4723ad2c788035e613828b16fb203055ac764c3bcb5021afcc31addcb9e83c6b1793df4abe242a1bbf3dd953e8624b85dd78d71d6dad34a2af0d87d4713d6f33aa6b8672648c40e5ad68a9c98d8ccb009506680efdaf511f18c2d43bf0effdc0ba480212bd1b2566def284a57695fe98746d014bb630f7604b57a5ced43b7e3e9188419ea3bd35385e2dcf42894a5dce35ea52064cac828675b9818995ce7aa0e1b27343efebd1940993a1ebfb4219491a1f1014ebe6c5f90bf8ca66fa129f9b60a6d41a26e077774ef6fd00b897478238d08920b098955522b49e20735e8cb1638255b46e5f5d5535b0c5a890362fddbc62eb2189f734aa831df712b443bbd52b7ba5e9ec7501d523e49a6bb0aa55653b2d47b233c92125366ec1069cd4eabe89f8999ec0bb696e840af148440a256e2c76c00670ea43ca250d96cd2a865764dbca380406926a5e5728bc807527ed3e12bcc605083704f5ecf2eba09271e88d976bf7864a44c633682e93445b8731587ea37ab3ee6afbe0211db8157268fdae9e4c5960ea05bad82964e61acf033d1a45df6fb92487298e33bd8fd0c16206306baba5d3b6d479f8e056b3c4f1ba87bc86968f48a4899877186ce0b62e2929aba83c331acdabfe94de878c71dcd9ba0b49259ff0c08b7f1d0b14af8e5410288e1b6f07ecf0ae5ee44dd9db71e91432b1a24ac9e82cd9f69d6150892731ac9faf056ebe311c083a225cd2ab70fe17c79ac6ca6dbd630a48aaf406d64d3d9db981787d092cbbccdad5b10885f0468293f0eb4e25bbf56008c58ea5a76c582338ed2621af2af2b80af6f24ed1476e2c07286faa1af5af660db4aee182cca4db847945ca50d98d9fc890ed4da37fce126597973ce50ff107bab528a0cc5fc196fefd7d0c1e53ed49a96272c8ff77b1fcbebcdc4f25e8e89c13bb0f7a9faacf3df73609b177b191618c54e9acc795830d75038c1dd59df5b9ef6a2417f97ae3d0d2446f254b0573286b44ad1d9becce62836ac5774ee367f9430aec32c2e801fb244576d5229c41f793cda73ff3a20279ed56d48a6b43527578c1110f9845418c345644d6830a13896b78aaa9be5691ef416bd60c23cc986bc656d553edec366b11c6cb8f2cbfbe86b7ec8aa894b3a202eb1c3f397bf7d71432f3d6a9b9e08a83a5e34f07daf5ccd93fb0cc53e858ad248f5c22c9d1b3400f8f9cff6891376c36d99995be23100809b9c21fa1b58547448ffffb2dabd40a0c2832a78ae2e69915b3fff9f916c90c8f323f516c8dd01fad907ffc3bae3da7d97f6792e3b1442798f49ffb4a99cd11cfdf41779cdd95317f31c7fa1d40405643d711d5838a7d3eef7f1cfc52482835ea666b2572ad1c8eab5ee43b66da3243650005eecfd863b256369d4a4090bed43e40076a82873e4f75e2224e685a7744a6e804a291a90de3535aaae202711515d0a205cb36d3515c2831559a830d5a5b44ca873e038412d9991ed58091e858790afe9486c2a5178fff668ae0b6626e974dbe39a872ce5d73ff402d98e3fb0a3d212dc8128f80fa687f881c7f8e7ce66634bc9d0b99a139029f6a239f721c1fffc1ebc44e80c987434744ac874ea327ffb266b56220fbe9141915d7a9224bf1ff9f0062baa89d71ac8fada6c9b56f773fc3603db4a9c4ce17b399107c22cb550fb4384d21d3f6019da07f549b2b7e2a53a146606a4899c102844f94e0fb2eda7444cbfc426dc0314325637a1939fa911155fefb5308f03d93eebc589f88793555ab7eba27ca96267c7535b763b54bc1558b2f3458debbb01b9283253ca29eb1aaedfb016f16ea9c227723ee8bcb465e15a979c1cadc92a1958a7675175f0bfacd89ec191ec9b749faed14125d36cef980ec671f667be51c79a85916f48482b7e12780e7401a8f31cc0937ae58d2d1b2ecb8b0908810b2fe3f0b8599ef07861fa7e6dcb4aa15dfbdcece67006ac967a791e093e1d49a8bd6a141006042bde0c8bb2c5c6d24e0aecc49914078536d58fae9f773886e18da7f5bf590966848af39a475506a899e888f99797a5e012d6d8406c952429603aab37fd7d8f58178c8e5087ba6d33b83d5605fcdcf32e1d6fb1e4a9a90880a64855c3be0a17fcd265cf2eea09a55067fa6b34ad8c9dfc06ff42faa48c0ea481ed0601d8efc57b08bf13b94daf124da26823c12795db6ce5776c53d08d6b70858a2cb1717b52481ed54768c4b0c64ca6ecb7ddcdda26da268a9942f5dcf7dfd09fe5d54150b090b02d3f93b35435d7c4c9efa548d26e5a6e1c47bc5014a1a6dafc6b8e9b0709f109a359ab6419ca1091bf867241c8cc6d4c0c30163d203c94b629b407691d7fc44f879e0de63425dcf1dc21094364dfb5636985915fc12f542e4f294b943e17a2bc43e6f5b7b17b2939d979cf3ca6cec5b5aa705992ceecf9c42bd8430bd0827723150c6ff782a838353ece53cec4a314ebda4f8bf5635246428940f4613ae5ed136871b7795e136be99b913179899f6858428e2557b59846e3fe757dd7ec07426e5331aeada2fe589cf9096ea6f3848984f3ff0d2c85def7621b4bca50b065abe630fed077a756b53a9e1ebce4dc7f16dfbd3e8495912c628948d3360f09cf6e4bd64712dd7abbbd95cb080392cc4349decbd8d794d96aacfb3dca04777f541c567ecf0d7a0fc5583a089e42caaf9491b60f41686c49db57244ac5d37d5b79b6239311c2875c522ced5d77485cb25823ac77d633293366b828b86a8d39ef77164bcae5dff9c02033197a8530886b54dbdebd9f57f830283fdfcd267caa862a12d66d072df63c324fd7b8380dea93da4bc604247cb9e59f71e6da46116538d0deb7852d9be85f074e608cd795be87051665667902e276c921f8b806bd9714632dff600ba1cd8a3db53b6a086cfcd97bf97f380e8a40eccd228a4c8a883c0fdaf7df06122cd128006b2cdfad2a4b13d1b5d6c796b805720085f819cc3a6eec6311a63cbe3303674053bb0c3f490aa77bd60fcbedbfc4411068a9cf4f1b4d515acb93bee92fb5515482d44991711052d8bf3c5751bdd152d4d1c4abf5cd54678eef0b6d262d45a78a0635def340a98172aace486fb897116c87c349580869f0e7aac0ed45d35e6ae3d4da0bae0a846d21957128974836059cca109e998d258869facd72bd1a438703fc94b91ff83775423cc067b6306a34627ddcfb67f6455292cbf081a3bc84c17b1d542e41f3d6a7377eeca20caba5f1d9e4a938e938662882af53e547eb47b7282ee9cb23867fb2a35b28de99e619a4f23aa43dec681f9f4c31f316405fa00e2ec94d48b3c113c38f9f37ede83bc408dd3dd04ae0b158b4738705e9624ab50b148d445d98ddaee19068c763badd624dd9b095787f8a8d4cfa417c9e54ca5d70a80e5d6a9f6d30a038d1dbc5e9fcf4ccd211f4cd47487cc8470652b7647c3200069671f84c8d4dfd2c63f3b29ecd9f40041e073a5fb0a17c777cf09f468107100525890cf79cc9db955c2cc7182148d4066eeb481ac1fe293d599bfc6f14cd848405530a21727db38cb002fb8ada00e5a506a7cca9cf1d206fdc03ba6d90811f0e4851cfd442e4688bd304a908f4a166d1da6639e4a9cec15763e2e9a598e4e043287fec5dd44271ad3cdba40eff1e1853f29fdf7549530e188c128d12bee59e68ef47c9a94dd3e8cf578b982bb74f8301958cec13a148e3032d6e7e36a52363c1faf01f18899b1bc3f8ca1dc44e6c3cb279ac196f5600f15a7b7e529ab103a5ef8c0b9bcb2b812db11a5de7415d448f6b6f0e7ebdf661791d60f56111b495b3464ad21936b9fcebb25c995cab10dd900beec34b84687c269ef3bfb3d5d514f40eea742e65829b3046b0afa0cb4a5a3112a51128ff71a0fe2c2e6dc47f0e785eaba72abb3f4e093db73a09359ed216765690f56e0f218b8d25088b8306869c13ec3532c8c974f73837255731e414218c73a13fbafbd2350644eeacfe5d1929ef90898fadbac6c247d62a583df45f746b74abf39894bc396ce5da7726b8bba8c328eb783ab9eb47c81f5114f066ea92f3f326564d686619ba27255a2c80a537b0efefebd8613fd0145877585bd06742ce95f5f36a798fc4196e952e72c48113823b73704d17f3b51fca3a7a0f75a15862ca504c582ef85133de648c49a984d73dbe722fba3ab66580d5fdaf5c13e60d0d2e0ebbacc963fee10b7d1b3318df905079926a8ffbbcfe994e5c61ffdf17746497f70529fd561f1fd0f9bd3feb6ea8bedefa633c7caba6e7c5382c8fe64a52ee96b8fc0f9bd690a1b68637b3dfdce7aa3c673b09c1661a651213e2d06bea10ca65c084ec31bfa0fe5698db8486e494fcff30a62f3e2f893dec3f1265a89dba3c3efccfa986ddb5c6b3a76b7f89629465a75e01cbe89523386091465f6bbb397f1135823ee2ba6c0678b597f746aa07ded582e2c94db483840b717efa8c2a44eb4571cdcba121a4650e4ddeb92f34d62616ce413e896a0d7e51e156677b020baf9c81d17915e2486ef32cd600ace1474dc1d122eb5b5ada8aaff80b80d819992132456bae3231912d5bf60e610e1fff697ed6c698df5efabc5979c8fca8d3ffa1ef463c1b1736b96b6fd83b3bd308ff8a6b17cb2ddd0467c64bce4a0ac7cb3f6d05ddbde8aa22c0dbef60ee46bcdf07a423aa96bad4ab7112eb3929d86c16c98d2c953c6d89d64d57a607744e871c7bf077ba8b787625f056c7c4a8b11471cd764ad4972a93af6c6c79b5d2dd598e40d3dd89bcfd389b478798234794aff1d108d4ec2c3843610cb4bf160cbcedf722a585139baa54394fe1eedb8fec2974eb4ee658828ce947a3da6a9273e733d226229feea32811ccc668829b8870806357d5a3f525fa163ff802a3426a8ca07c2dcb0cf26f7c9bcff6034c13052fc89b393dd02f0b5fc2c3f3841f17c67bbac2078d443ace29d9ba7832936edc0d54b944b84aa4c0dc5029163f384a9310a9e795e65d4df11f64335bcf065d37d4d4617b5ff4a16d599ea0196163fa42e504bced1bf8e4e45c06481fb9bcf8d39e45ec2862f71e1d6f07da27a82c370885d767327bb4e5a4c964e858c91ba26553a6a07f8d510f86fbbe226efb628afea890489f70a55368beadab0aba3b2dbe52b45ac74ccea842e92c8ae6b464fc96f3b0b8bc90012929db77ada0617e3bbcb09ce6ebb40173744e55990879ddcaabdcc420a6a101d05158f57fa54c2a9eab69fa946824a12232db32df8e9f354656447939822dc96abf9dff9772470297ebd59787e2b93bc56f78bfbea76c619ef3657eb4edb3c55b65aaefae51477a06b03ede622920b6b23f1dab99e59958885c4e95fab368e45eced88b402f7fd75539b11dbcb0218ebb414aae103b5fcd2a881d652bdc29f26a119d59944a37c0752a24be76d3346f0495f857fcae62d8493a56f70a4400c562ddba6dfbd9fb8e5b88ecb4ccd500f6bb952d097ad07a71f26b27e2000a41346a7a7825ecc24c873782f8ed400668c0c28c8a2f67f2dfa90563b728900802f0f32facbb41ef979346bca4f2b40a03ad2ffb9fea126b7d78186bce2f610c84987bfa89f24b832e6b0f4360dd9ca7d2df4d7c9c6ede63fa05d314391503d1c79720dbbf8a95fcf88747d9475a44c6397ce912a9b69dbe1b548ce7cc986afbe3ee11abac24452da229b021bfbe85badce996168f2d56790ab41c2a2fae27299423fb9c397c560ba6b0919a5dccd879fc967d41abdb6b8e905cb600f5400e987bbc1c920ed246723473e3813290123e9aab23b689436c0760c86e30bf9a0b6720aaf6521b94470938fa89bcef808e40e8d5b3e69e7958cb87392c2c2b60b1d1230b20e0490bd77f3483bb9b9b1c6f22b5e6f48c2b4ecd5f01a4aa8281e38aeb6360b1af3e2280b6c20dd523225c6da63c38de1b08d590723948a535f579c487e5a38ad0eb0af48ec79ace8372d835a9df0c6d851dcdb1b2798182244f8e431456cf88e658a08f0f8bf0f156b1b8e9ecb641b58ffac8b2d36eed2dac5e272467e3d222f3fd7adf884aa8791775b0ed81dcc6abb0f86ccbb52ea94baea98e947129fc2b4e9a87fea27a539e9a53f2398d747b36224d29fe4b18e88640e8eec7f0d19a03aad83a3eeeef9153e891953cf68300424aca48ceaaab75a8e2b5fa8c3423c052dd7cdb02555653131b63792f412cb06794d808e17555f3ebf11e2bbd88bbee40bd0a0b19d2ab70e6ed65b6aceaeae9d0ec4c8de047564d20a8bf245825a5a445275fb158592be068d2eeed6e2f0f0d567129ced737bb6c4183d55464dd69685606bc428d05aa4751e4caa97e14c3c26b886f53304714d9265dfd53dd99f4b3066a8993fe2c6d07b7fabe546a8038efe4029bf8fdb78849a5f96de98520472bdd033ef73d256a5c0f77c963e66858f6d444095a8637627989aaddde7001379a44aa8bb127c53b17ec1595560c018580d5d52e9d71b689dde71afaab8f01e6e10b4a69226712162ab070dcab3961304ca70e8b6b00d69bb55c8d13d607b97c5fd0d22e45c10c42a2b3b058cb89a7db77c506a8eb98a7a9a5b04e377f3608e92adb242b267ed1940f1c61c55f038b237591ed3df01e85f912e37a36b6c46dec52f66888b61313bbabce2c62323ac4b3b3da015ae397d8aa96c1b77abec975e0a0d081ad9c7dced53c7225596e7bd358c904a21881cea14545c75757e50d64177da2e54aa242499697392d2dde50bd1d5d0b9e9d4ad2dbfc3d07787955e4ec64b44e86484ec3c97da624ab4bd5af13bef0b113ea6274bbdd0fadd61ecb1ad8aeacdd58ecfb11ead453994ba67de18eda5814af281ceb32c4b43fcf480eacf948770ced7a2425ff75e14fc31a1258379a94d028dcad2f7f5359a3b3e096ee45813a04330fd87b5f28300ca0d8bca9d6e188853fc9e74d1b791e07e48775ea264cf55347ec612062576589dda95364afe032a819ef79687aed3eec5513a83ddbd83f522059abe14cd44753b52c4926a9672793543c16d9a0095928a2775b7053c0f178294f1c90080baf72cb15324c68b12dd6339971da05074da7beed3f6fc16ebca5e04bce5086492111aea88f4bb1ca6bcf585ec1e4a7db69561a52b31e9e3d06c32e69392ee8e921d5d073aff322e62439fd0b877aa3236a4b44909befeb9fad487c3e69594bec44de15b4c2ebe687989a9b4901d7cf73ab0acd90f9d37014bf60a11b424dc35095cd80f538484c19ef38c95e12e13424bb40e132865a5f206b06fba8cbccc096f5088cbf93f87b7442e45d4afebff0bcb24aafef78f69a51539d749dbe6fecebdedd5beb573440e5a884d1c89705f4136b4a59731680a88f8953031abcc77118461cefcfdc20d2b36ba7c3ed6bf94d5e57a42bc3d32907604691b4d8637bd05af6c69b5a63f9a49c2c1b110a7c5ac471b4784230fcf80dc33721d54d1b71758e219652bd3c36113404ea4a983126e978d4fdf3b645a1cac083126eaa3d70a3d70a3d70a3d70a3d70a3d70a4cccccccccccccccccccccccccccccccd80000000000000000000000000000000a0000000000000000000000000000000c8000000000000000000000000000000fa0000000000000000000000000000009c400000000000000000000000000000c3500000000000000000000000000000f424000000000000000000000000000098968000000000000000000000000000bebc2000000000000000000000000000ee6b28000000000000000000000000009502f900000000000000000000000000ba43b740000000000000000000000000e8d4a5100000000000000000000000009184e72a000000000000000000000000b5e620f4800000000000000000000000e35fa931a000000000000000000000008e1bc9bf040000000000000000000000b1a2bc2ec50000000000000000000000de0b6b3a7640000000000000000000008ac7230489e800000000000000000000ad78ebc5ac6200000000000000000000d8d726b7177a80000000000000000000878678326eac90000000000000000000a968163f0a57b4000000000000000000d3c21bcecceda100000000000000000084595161401484a00000000000000000a56fa5b99019a5c80000000000000000cecb8f27f4200f3a0000000000000000813f3978f89409844000000000000000a18f07d736b90be55000000000000000c9f2c9cd04674edea400000000000000fc6f7c40458122964d000000000000009dc5ada82b70b59df020000000000000c5371912364ce3056c28000000000000f684df56c3e01bc6c7320000000000009a130b963a6c115c3c7f400000000000c097ce7bc90715b34b9f100000000000f0bdc21abb48db201e86d4000000000096769950b50d88f41314448000000000bc143fa4e250eb3117d955a000000000eb194f8e1ae525fd5dcfab080000000092efd1b8d0cf37be5aa1cae500000000b7abc627050305adf14a3d9e40000000e596b7b0c643c7196d9ccd05d00000008f7e32ce7bea5c6fe4820023a2000000b35dbf821ae4f38bdda2802c8a800000e0352f62a19e306ed50b2037ad2000008c213d9da502de454526f422cc340000af298d050e4395d69670b12b7f410000daf3f04651d47b4c3c0cdd765f11400088d8762bf324cd0fa5880a69fb6ac800ab0e93b6efee00538eea0d047a457a00d5d238a4abe9806872a4904598d6d88085a36366eb71f04147a6da2b7f864750a70c3c40a64e6c51999090b65f67d924d0cf4b50cfe20765fff4b4e3f741cf6d82818f1281ed449fbff8f10e7a8921a4a321f2d7226895c7aff72d52192b6a0dcbea6f8ceb02bb399bf4f8a69f764490fee50b7025c36a0802f236d04753d5b49f4f2726179a224501d762422c946590c722f0ef9d80aad6424d3ad2b7b97ef5f8ebad2b84e0d58bd2e0898765a7deb29b934c3b330c857763cc55f49f88eb2fc2781f49ffcfa6d53cbf6b71c76b25fbf316271c7fc3908a8bef464e3945ef7a97edd871cfda3a5697758bf0e3cbb5acbde94e8e43d0c8ec3d52eeed1cbea317ed63a231d4c4fb274ca7aaa863ee4bdd945e455f24fb1cf88fe8caa93e74ef6ab975d6b6ee39e436b3e2fd538e122b44e7d34c64a9c85d4460dbbca87196b61690e40fbeea1d3a4abc8955e946fe31cdb51d13aea4a488dd6babab6398bdbe41e264589a4dcdab14c696963c7eed2dd18d7eb76070a08aecfc1e1de5cf543ca2b0de65388cc8ada83b25a55f43294bcbdd15fe86affad91249ef0eb713f39ebe8a2dbf142dfcc7ab6e3569326c784337acb92ed9397bf99649c2c37f07965404d7e77a8f87daf7fbdc33745ec97be90686f0ac99b4e8dafd69a028bb3ded71a3a8acd7c0222311bcc40832ea0d68ce0cd2d80db02aabd62bf50a3fa490c3019083c7088e1aab65db792667c6da79e0faa4b8cab1a1563f52577001b891185938cde6fd5e09abcf26ed4c0226b55e6f8680b05e5ac60b6178544f8158315b05b4a0dc75f1778e39d6696361ae3db1c721c913936dd571c84c03bc3a19cd1e38e9fb5878494ace3a5f04ab48a04065c7239d174b2dcec0e47b62eb0d64283f9c76c45d1df942711d9a3ba5d0bd324f8394f5746577930d6500ca8f44ec7ee364799968bf6abbe85f207e998b13cf4e1ecbbfc2ef456ae276e89e3fedd8c321a67eefb3ab16c59b14a2c5cfe94ef3ea101e95d04aee3b80ece5bba1f1d158724a12bb445da9ca61281f2a8a6e45ae8edc97ea1575143cf97226f52d09d71a3293bd924d692ca61be758593c2626705f9c56b6e0c377cfa2e12e6f8b2fb00c77836ce498f455c38b997a0b6dfb9c0f9564478edf98b59a373fec4724bd4189bd5eacb2977ee300c50fe758edec91ec2cb657df3d5e9bc0f653e12f2967b66737e3ed8b865b215899f46cbd79e0d20082ee74ae67f1e9aec07187ecd8590680a3aa11da01ee641a708de9e80e6f4820cc9495884134fe908658b23109058d147fdcddaa51823e34a7eedebd4b46f0599fd415d4e5e2cdc1d1ea966c9e18ac7007c91a850fadc09923329e03e2cf6bc604ddb0a6539930bf6bff4584db8346b786151ccfe87f7cef46ff16e612641865679a6381f14fae158c5f6e4fcb7e8f3f60c07ea26da3999aef7749e3be5e330f38f09dcb090c8001ab551c5cadf5bfd3072cc5fdcb4fa002162a6373d9732fc7c8f7f69e9f11c4014dda7e2867e7fddcdd9afac646d63501a1511db281e1fd541501b8f7d88bc24209a5651f225a7ca91a42269ae757596946075f3375788de9b06958c1a12d2fc39789370052d6b1641c83aef209787bb47d6b84c0678c5dbd23a49a9745eb4d50ce6332f840b7ba963646e0bd176620a501fbffb650e5a93bc3d898ec5d3fa8ce427affa3e51f138ab4cebe93ba47c980e98cdfc66f336c36b10137b8a8d9bbe123f017b80b0047445d4184e6d3102ad96cec1da60dc059157491e59043ea1ac7e4139287c89837ad68db2fb454e4a179dd187729babe4598c311fbe16a1dc9d8545e94f4296dd6fef3d67a8ce2529e2734bb1d1899e4a65f58660cb01ae745b101e9e45ec05dcff72e7f8fdc21a1171d42645d76707543f4fa1f73899504ae72497eba6a06494a791c53a8abfa45da0edbde690487db9d17636892d6f8d7509292d60345a9d2845d3c42b6865b86925b9bc5c20b8a2392ba45a9b2a7f26836f282b7328e6cac7768d7141ed1ef0244af2364ff3207d795430cd9268335616aed761f1f7f44e6bd49e807b8a402b9c5a8d3a6e75f16206c9c6209a6cd036837130890a136dba887c37a8c0f802221226be55a64c2494954da2c9789a02aa96b06deb0fdf2db9baa10b7bd6cc83553c5c8965d3d6f92829494e5acc7fa42a8b73abbf48ccb772339ba1f17f99c69a97284b578d7ff2a760414536efbc38413cf25e2d70dfef5138519684abaf46518c2ef5b8cd17eb258665fc25d6998bf2f79d5993802ef2f773ffbd97a61beeefb584aff8603aafb550ffacfd8faeeaaba2e5dbf678495ba2a53f983cf38952ab45cfa97a0b2dd945a747bf26183ba756174393d88df94f971119aeef9e4e912b9d1478ceb177a37cd5601aab85d91abb422ccb812eeac62e055c10ab33ab616a12b7fe617aa577b986b314d6009e39c49765fdf9d94ed5a7e85fda0b80b8e41ade9fbebc27d14588f13be847307b1d219647ae6b31c596eb2d8ae258fc8de469fbd99a05fe36fca5f8ed9aef3bb8aec23d680043bee25de7bb9480d5854ada72ccc20054ae9af561aa79a10ae6ad910f7ff28069da41b2ba1518094da0487aa9aff7904228690fb44d2f05d0842a99541bf57452b28353a1607ac744a53d3fa922f2d1675f242889b8997915ce8847c9b5d7c2e09b769956135febada11a59bc234db398c2543fab9837e699095cf02b2c21207ef2e94f967e45e03f4bb8161afb94b44f57d1d1be0eebac278f5a1ba1ba79e1632dc6462d92a69731732ca28a291859bbf937d7b8f7503cfdcfefcb2cb35e702af785cda735244c3d43e9defbf01b061adab3a0888136afa64a7c56baec21c7a1916088aaa1845b8fdd0f6c69a72a3989f5b8aad549e57273d459a3c2087a63f639936ac54e2f678864bc0cb28a98fcf3c7f84576a1bb416a7ddf0fdf2d3f3c30b9f656d44a2a11c51d5969eb7c47859e7439f644ae5a4b1b325bc4665b596706114873d5d9f0dde1feeeb57ff22fc0c7959a90cb506d155a7ea9316ff75dd87cbd809a7f12442d588f2b7dcbf5354e9bece0c11ed6d538aeb2fe5d3ef282a242e818f1668c8a86da5fa8fa475791a569d10f96e017d694487bcb38d92d760ec445537c981dcc395a9ace070f78d3927556a85bbe253f47b14178c469ab843b8956293956d7478ccec8eaf58416654a6babb387ac8d1970027b2db2e51bfe9d0696a06997b05fcc0319e88fcf317f22241e2441fece3bdf81f03ab3c2fddeeaad25ad527e81cad7626c3d60b3bd56a5586f18a71e223d8d3b07485c7056562757456f6872d5667844e49a738c6bebb12d16cb428f8ac016561dbd106f86e69d785c7e13336d701beba5282a45b450226b39cecc0024661173473a34d721642b0608427f002d7f95d0190cc20ce9bd35c78a531ec038df7b441f4ff290242c83396ce7e67047175a152719f79a169bd203e410f0062c6e984d386c75809c42c684dd152c07b78a3e60868f92e0c3537826145a7709a56ccdf8a829bbcc7a142b17ccb88a66076400bb691c2abf989935ddbfe6acff893d00ea435f356f7ebf83552fe0583f6b8c4124d4398165af37b2153dec3727a337a8b704abe1bf1b059e9a8d6744f18c0592e4c5ceda2ee1c7064130c1162def06f79df739485d4d1c63e8be78addcb5645ac2ba8b9a74a0637ce2ee16d953e2bd7173692e8111c87c5c1ba99c8fa8db6ccdd0437910ab1d4db9914a01d9c9892400a22a2b54d5e4a127f59c82503beb6d00cab4be2a0b5dc971f303a2e44ae64840fd61d8da471a9de737e245ceaecfed289e5d2b10d8e1456105dad7425a83e872c5f47dd50f1996b947518d12f124e28f777198a5296ffe33cc92f82bd6b70d99aaa6face73cbfdc0bfb7b636cc64d1001550bd8210befd30efa5a3c47f7e05401aa4e8714a775e3e95c7865acfaec34810a71a8d9d1535ce3b3967f1839a741a14d0dd31045a8341ca07c1ede48111209a05083ea2b892091e44d934aed0aab460432a4e4b66b68b65d60f81da84d5617853fce1de40642e3f4b936251260ab9d668e80d2ae83e9ce78f3c1d72b7c6b426019a1075a24e4421730b24cf65b8612f81fc94930ae1d529cfcdee033f26797b627fb9b7cd9a4a7443c169840ef017da3b19d412e0806e88aa58e1f289560ee864ec491798a08a2ad4ef1a6f2bab92a27e2f5b5d7ec8acb58a2ae10af696774b1db9991a6f3d6bf1765acca6da1e0a8ef29bff610b0cc6edd3f17fd090a58d32af3eff394dcff8a948eddfc4b4cef07f5b095f83d0a1fb69cd94abdaf101564f98ebb764c4ca7a4440f9d6d1ad41abe37f1ea53df5fd18d551384c86189216dc5ed92746b9be2f8552c32fd3cf5b4e49bb4b7118682dbb66a773fbc8c33221dc2a1e4d5e82392a405150fabaf3feaa5334a8f05b1163ba6832d29cb4d87f2a7400eb2c71d5bca9023f8743e20e9ef511012df78e4b2bd342cf6914da9246b2554168bab8eefb6409c1a1ad089b6c2f7548eae9672aba3d0c320a184ac2473b529b1da3c0f568cc4f3e8c9e5d72d90a2741e8865899617fb18717e2fa67c7a658892aa7eebfb9df9de8dddbb901b98feeab7d51ea6fa85785631552a74227f3ea5658533285c936b35ded53a88958f87275fa67ff273b84603568a892abaf368f137d01fef10a657842c2d2b7569b0432d858213f56a67f6b29b9c3b29620e29fc73a298f2c501f45f428349f3ba91b47b8fcb3f2f7642717713241c70a936219a73fe0efb53d30dd4d7ed238cd383aa01109ec95d1463e8a506f4363804324a40aac67bb4597ce2ce48b143c6053edcd0d5f81aa16fdc1b81dadd94b7868e94050a9b10a4e5e9913128ca7cf2b4191c8326c1d4ce1f63f57d72fd1c2f611f63a3f0f24a01a73cf2dccfbc633b39673c8cec976e41088617ca01d5be0503e085d813bd49d14aa79dbc824b2d8644d8a74e18ec9c459d51852ba2ddf8e7d60ed1219e93e1ab8252f33b45cabb90e5c942b503b8da1662e7b00a173d6a751f3b936243e7109bfba19c0c9d0cc512670a783ad4906a617d450187e227fb2b80668b24c5b484f9dc9641e9dab1f9f660802dedf6e1a63853bbd264515e7873f8a03969738d07e33455637eb2db0b487b6423e1e8b049dc016abc5e5f91ce1a9a3d2cda62dc5c5301c56b75f77641a140cc7810fb89b9b3e11b6329baa9e904c87fcb0a9dac2820d9623bf429546345fa9fbdcd44d732290fbacaf133a97c177947ad4095867f59a9d4bed6c049ed8eabcccc485da81f301449ee8c705c68f256bfff5a74d226fc195c6a2f8c73832eec6fff311183585d8fd9c25db7c831fd53c5ff7eaba42e74f3d032f525ba3e7ca8b77f5e55cd3a1230c43fb26f28ce1bd2e55f35eb80444b5e7aa7cf857980d163cf5b81b3a0555e361951c366d7e105bcc332621fc86ab5c39fa634408dd9472bf3fefaa7fa856334878fc150b14f98f6f0feb9519c935e00d4b9d8d26ed1bf9a569f33d3c3b8358109e84f070a862f80ec4700c8f4a642e14c6262c8cd27bb612758c0fa98e7e9cccfbd7dbd8038d51cb897789cbf21e44003acdd2ce0470a63e6bd56c3eeea5d50049814781858ccfce06cac7495527a5202df0ccb0f37801e0c43ebc8baa718e68396cffdd30560258f54e6bae950df20247c83fd47c6b82ef32a206991d28b7416cdd27e4cdc331d57fa5441b6472e511c81471de0133fe4adf8e952e3d8f9e563a198e558180fddd97723a68e679c2f5e44ff8f570f09eaa7ea7648"
            var shifted_w = w
            var zeros = 0u64
            while shifted_w & 9223372036854775808u64 == 0u64 {
                shifted_w = shifted_w << 1u64
                zeros += 1u64
            }
            let entry_at = usize(q + 342i64) * 32usize
            var high = 0u64
            var low = 0u64
            var pass = 0usize
            while pass < 2usize {
                // The entry's top or bottom 64 bits, then a 64 x 64 -> 128 product in halves.
                var factor = 0u64
                var nibble_at = entry_at + pass * 16usize
                let nibble_end = nibble_at + 16usize
                while nibble_at < nibble_end {
                    let symbol = powers[nibble_at]
                    var nibble = u64(symbol) - 48u64
                    if symbol >= 97u8 { nibble = u64(symbol) - 87u64 }
                    factor = factor << 4u64 | nibble
                    nibble_at += 1usize
                }
                let a_low = shifted_w & 4294967295u64
                let a_high = shifted_w >> 32u64
                let b_low = factor & 4294967295u64
                let b_high = factor >> 32u64
                let p0 = a_low * b_low
                let p1 = a_low * b_high
                let p2 = a_high * b_low
                let p3 = a_high * b_high
                let middle = (p0 >> 32u64) + (p1 & 4294967295u64) + (p2 & 4294967295u64)
                let product_low = ((middle & 4294967295u64) << 32u64) | (p0 & 4294967295u64)
                let product_high = p3 + (p1 >> 32u64) + (p2 >> 32u64) + (middle >> 32u64)
                if pass == 0usize {
                    high = product_high
                    low = product_low
                    // Nine bits below the 55 that matter all set: the rounding may depend
                    // on the bottom half of the entry.
                    if high & 511u64 != 511u64 { break }
                } else {
                    let summed = low +% product_high
                    if summed < low { high += 1u64 }
                    low = summed
                }
                pass += 1usize
            }
            if !(high & 511u64 == 511u64 && low == 18446744073709551615u64) {
                let upper_bit = high >> 63u64
                let shift = upper_bit + 9u64
                var mantissa = high >> shift
                // floor(q * log2(10)) as a fixed-point multiply; the shift floors toward
                // minus infinity for a negative q as well.
                let scaled_q = 217706i64 * q
                var log2_floor = 0i64
                if scaled_q >= 0i64 {
                    log2_floor = scaled_q / 65536i64
                } else {
                    log2_floor = 0i64 - (0i64 - scaled_q + 65535i64) / 65536i64
                }
                var power2 = log2_floor + 63i64 + i64(upper_bit) - i64(zeros) + 1023i64
                if power2 <= 0i64 {
                    // Subnormal, or zero when every bit is shifted out.
                    if 0i64 - power2 + 1i64 >= 64i64 {
                        fast_bits = 0u64
                    } else {
                        mantissa = mantissa >> u64(0i64 - power2 + 1i64)
                        mantissa += mantissa & 1u64
                        mantissa = mantissa >> 1u64
                        var subnormal_field = 0u64
                        if mantissa >= 4503599627370496u64 { subnormal_field = 1u64 }
                        fast_bits = (subnormal_field << 52u64) | (mantissa & 4503599627370495u64)
                    }
                } else {
                    // An exact tie: the discarded bits are exactly one half, so round to even.
                    if low <= 1u64 && q >= -4i64 && q <= 23i64 && mantissa & 3u64 == 1u64 {
                        if mantissa << shift == high { mantissa = mantissa - 1u64 }
                    }
                    mantissa += mantissa & 1u64
                    mantissa = mantissa >> 1u64
                    if mantissa >= 9007199254740992u64 {
                        mantissa = 4503599627370496u64
                        power2 += 1i64
                    }
                    mantissa = mantissa & 4503599627370495u64
                    if power2 >= 2047i64 {
                        fast_bits = 9218868437227405312u64
                    } else {
                        fast_bits = (u64(power2) << 52u64) | mantissa
                    }
                }
                fast_done = true
            }
        }
        if fast_done {
            if fast_bits == 0u64 || fast_bits >= 9218868437227405312u64 { ret (0.0f64, BadNumber) }
            if negative { fast_bits = fast_bits | 9223372036854775808u64 }
            ret (mem.bitcast[f64](fast_bits), ok)
        }
    }
    var binary_exponent = 0i64
    while true {
        if used == 0usize { break }
        // `0.digits * 10^exponent` with a leading digit of at least one lies in
        // `[0.1, 1)`, so both comparisons are on the exponent alone.
        var halving = false
        var doubling = false
        if exponent >= 1i64 {
            halving = true
        } else {
            if exponent < 0i64 {
                doubling = true
            } else {
                if digits[0usize] < 5u8 { doubling = true }
            }
        }
        if !halving && !doubling { break }
        if halving {
            var remainder = 0u8
            var scan = 0usize
            while scan < used {
                let value = remainder * 10u8 + digits[scan]
                digits[scan] = value / 2u8
                remainder = value % 2u8
                scan += 1usize
            }
            if remainder != 0u8 {
                if used < digits.len {
                    digits[used] = 5u8
                    used += 1usize
                } else {
                    truncated = true
                }
            }
            // The division can leave one leading zero, which belongs to the exponent.
            if digits[0usize] == 0u8 {
                var back = 0usize
                while back + 1usize < used {
                    digits[back] = digits[back + 1usize]
                    back += 1usize
                }
                used = used - 1usize
                exponent = exponent - 1i64
            }
            binary_exponent += 1i64
        } else {
            var carry = 0u8
            var scan = used
            while scan > 0usize {
                scan = scan - 1usize
                let value = digits[scan] * 2u8 + carry
                digits[scan] = value % 10u8
                carry = value / 10u8
            }
            if carry != 0u8 {
                if used == digits.len {
                    if digits[used - 1usize] != 0u8 { truncated = true }
                } else {
                    used += 1usize
                }
                var back = used
                while back > 1usize {
                    back = back - 1usize
                    digits[back] = digits[back - 1usize]
                }
                digits[0usize] = carry
                exponent += 1i64
            }
            binary_exponent = binary_exponent - 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // The value is `m * 2^binary_exponent` with `m` in `[0.5, 1)`, which fixes a
    // normal number's exponent field and leaves only the mantissa to read.
    var biased = binary_exponent - 1i64 + 1023i64
    var bits = 53i64
    if biased < 1i64 {
        // Subnormal: the exponent field is pinned at zero and the mantissa loses one
        // bit for every step below the smallest normal. `bits` is the value's exponent
        // in units of that smallest subnormal, so a negative one is less than half of
        // it and rounds to a zero the input did not write.
        bits = 53i64 + biased - 1i64
        biased = 0i64
        if bits < 0i64 { ret (0.0f64, BadNumber) }
    }
    var shifted = 0i64
    while shifted < bits {
        var carry = 0u8
        var scan = used
        while scan > 0usize {
            scan = scan - 1usize
            let value = digits[scan] * 2u8 + carry
            digits[scan] = value % 10u8
            carry = value / 10u8
        }
        if carry != 0u8 {
            if used == digits.len {
                if digits[used - 1usize] != 0u8 { truncated = true }
            } else {
                used += 1usize
            }
            var back = used
            while back > 1usize {
                back = back - 1usize
                digits[back] = digits[back - 1usize]
            }
            digits[0usize] = carry
            exponent += 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
        shifted += 1i64
    }
    var mantissa = 0u64
    var taken = 0i64
    while taken < exponent {
        var digit = 0u8
        if usize(taken) < used { digit = digits[usize(taken)] }
        mantissa = mantissa * 10u64 + u64(digit)
        taken += 1i64
    }
    // Round to nearest, ties to even, on the digits the integer part left behind.
    var round_up = false
    if exponent >= 0i64 && usize(exponent) < used {
        let first = digits[usize(exponent)]
        if first > 5u8 { round_up = true }
        if first == 5u8 {
            var beyond = truncated
            var scan = usize(exponent) + 1usize
            while scan < used {
                if digits[scan] != 0u8 { beyond = true }
                scan += 1usize
            }
            if beyond {
                round_up = true
            } else {
                round_up = mantissa % 2u64 == 1u64
            }
        }
    }
    if round_up { mantissa += 1u64 }
    let implicit = 1u64 << 52u64
    if biased == 0i64 {
        // The carry out of a subnormal's mantissa is exactly the smallest normal.
        if mantissa >= implicit { biased = 1i64 }
    } else {
        if mantissa >= implicit * 2u64 {
            mantissa = mantissa / 2u64
            biased += 1i64
        }
    }
    if biased > 2046i64 { ret (0.0f64, BadNumber) }
    var fraction = mantissa
    if biased >= 1i64 { fraction = mantissa - implicit }
    if biased == 0i64 && fraction == 0u64 { ret (0.0f64, BadNumber) }
    var pattern = u64(biased) << 52u64
    pattern = pattern + fraction
    if negative { pattern = pattern + 9223372036854775808u64 }
    ret (mem.bitcast[f64](pattern), ok)
}

// The exact inverse of what `push_f32` writes: the nearest f32 to the input, ties to even.
// The fast path (D1593) rounds `parse_f64`'s nearest double to the nearest float, which is
// exact unless the double sits exactly on a midpoint between two floats. That case, and
// any input the double parse refuses, take the exact path: the digits become an
// arbitrary-precision decimal that is halved and doubled one bit at a time until the
// binary exponent falls out and the mantissa can be read off the front.
//
// `e.str` is frozen at its declared surface and a neper module exports every
// declaration it has, so this cannot be shared with `parse_f64`; the two are
// generated from one template rather than written twice.
fn parse_f32(s: str) -> (f32, err) {
    // The non-finite spellings are exact tokens, not numbers, and the NaN handed back
    // is section 11's canonical quiet one rather than whatever an operation produced.
    if eq(s, "inf") { ret (mem.bitcast[f32](2139095040u32), ok) }
    if eq(s, "-inf") { ret (mem.bitcast[f32](4286578688u32), ok) }
    if eq(s, "nan") { ret (mem.bitcast[f32](2143289344u32), ok) }
    // The fast path (D1593): the grammar is `parse_f64`'s, so its answer -- the nearest
    // double -- is rounded again to the nearest float. Rounding twice gives the nearest
    // float to the input unless the double landed exactly on a midpoint between two
    // floats, since every float and every midpoint is a double; that one case, and any
    // input the double parse refuses, is decided exactly below.
    let (wide, wide_error) = parse_f64(s)
    if wide_error == ok {
        let wide_bits = mem.bitcast[u64](wide)
        let sign_bit = u32.trunc(wide_bits >> 32u64) & 2147483648u32
        let magnitude = wide_bits & 9223372036854775807u64
        if magnitude == 0u64 { ret (mem.bitcast[f32](sign_bit), ok) }
        let field = magnitude >> 52u64
        // A subnormal double is far below half the smallest float: that rounds to zero.
        if field == 0u64 { ret (0.0f32, BadNumber) }
        let significand = (magnitude & 4503599627370495u64) | 4503599627370496u64
        // The value is `significand * 2^scale`; a float keeps 24 bits above its quantum,
        // which never goes below 2^-149.
        let scale = i64(field) - 1075i64
        var quantum = scale + 52i64 - 23i64
        if quantum < -149i64 { quantum = -149i64 }
        let drop = quantum - scale
        var kept = 0u64
        var decided = true
        if drop >= 64i64 {
            // Strictly below half the quantum: zero.
            kept = 0u64
        } else {
            kept = significand >> u64(drop)
            let rest = significand & ((1u64 << u64(drop)) - 1u64)
            let half = 1u64 << u64(drop - 1i64)
            if rest == half {
                decided = false
            } else if rest > half {
                kept += 1u64
            }
        }
        if decided {
            if kept == 0u64 { ret (0.0f32, BadNumber) }
            if kept >= 16777216u64 {
                kept = kept >> 1u64
                quantum += 1i64
            }
            var narrow_bits = 0u32
            if kept >= 8388608u64 {
                let narrow_field = quantum + 150i64
                if narrow_field >= 255i64 { ret (0.0f32, BadNumber) }
                narrow_bits = u32(narrow_field) << 23u32 | u32(kept - 8388608u64)
            } else {
                narrow_bits = u32(kept)
            }
            ret (mem.bitcast[f32](narrow_bits | sign_bit), ok)
        }
    }
    // 256 digits is past the longest exact tie this width has (113 of them),
    // so a tie always fits and a decimal that does not fit is never one: what
    // spills past the end can only be the sticky bit `truncated` carries.
    var digits: [256]u8 = zero
    var used = 0usize
    var truncated = false
    var negative = false
    var at = 0usize
    if s.len > 0usize && s[0usize] == 45u8 {
        negative = true
        at = 1usize
    }
    // The grammar is the one the pushes write and nothing else: at least one digit,
    // at most one point with digits on both sides, no separators, no leading `+`, no
    // surrounding space, and a lowercase `e` exponent with at least one digit.
    var integer_digits = 0usize
    var fraction_digits = 0usize
    var leading_zeros = 0usize
    var started = false
    var in_fraction = false
    while at < s.len {
        let byte = s[at]
        if byte == 46u8 && !in_fraction && integer_digits > 0usize {
            in_fraction = true
            at += 1usize
            continue
        }
        if byte < 48u8 || byte > 57u8 { break }
        if in_fraction { fraction_digits += 1usize } else { integer_digits += 1usize }
        let digit = byte - 48u8
        if !started && digit == 0u8 {
            leading_zeros += 1usize
        } else {
            started = true
            if used < digits.len {
                digits[used] = digit
                used += 1usize
            } else {
                if digit != 0u8 { truncated = true }
            }
        }
        at += 1usize
    }
    if integer_digits == 0usize { ret (0.0f32, BadNumber) }
    if in_fraction && fraction_digits == 0usize { ret (0.0f32, BadNumber) }
    // `I.F` is `0.(I F) * 10^len(I)`, and every leading zero dropped takes one off it.
    var exponent = i64(integer_digits) - i64(leading_zeros)
    if at < s.len && s[at] == 101u8 {
        at += 1usize
        var exponent_negative = false
        if at < s.len && (s[at] == 43u8 || s[at] == 45u8) {
            exponent_negative = s[at] == 45u8
            at += 1usize
        }
        var magnitude = 0i64
        var exponent_digits = 0usize
        while at < s.len {
            let byte = s[at]
            if byte < 48u8 || byte > 57u8 { break }
            exponent_digits += 1usize
            // Past six digits the value is out of range either way, and the clamp is
            // what keeps the normalization below finite.
            if magnitude < 1000000i64 { magnitude = magnitude * 10i64 + i64(byte - 48u8) }
            at += 1usize
        }
        if exponent_digits == 0usize { ret (0.0f32, BadNumber) }
        if exponent_negative { exponent = exponent - magnitude } else { exponent = exponent + magnitude }
    }
    if at != s.len { ret (0.0f32, BadNumber) }
    while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    // An exact zero keeps its sign; it is the one zero a parse may return.
    if used == 0usize {
        var zero_pattern = 0u32
        if negative { zero_pattern = 2147483648u32 }
        ret (mem.bitcast[f32](zero_pattern), ok)
    }
    // Bounds that only keep the loops finite. Anything outside them is out of range by
    // a wide margin; anything inside is decided exactly below.
    if exponent > 60i64 || exponent < -60i64 { ret (0.0f32, BadNumber) }
    var binary_exponent = 0i64
    while true {
        if used == 0usize { break }
        // `0.digits * 10^exponent` with a leading digit of at least one lies in
        // `[0.1, 1)`, so both comparisons are on the exponent alone.
        var halving = false
        var doubling = false
        if exponent >= 1i64 {
            halving = true
        } else {
            if exponent < 0i64 {
                doubling = true
            } else {
                if digits[0usize] < 5u8 { doubling = true }
            }
        }
        if !halving && !doubling { break }
        if halving {
            var remainder = 0u8
            var scan = 0usize
            while scan < used {
                let value = remainder * 10u8 + digits[scan]
                digits[scan] = value / 2u8
                remainder = value % 2u8
                scan += 1usize
            }
            if remainder != 0u8 {
                if used < digits.len {
                    digits[used] = 5u8
                    used += 1usize
                } else {
                    truncated = true
                }
            }
            // The division can leave one leading zero, which belongs to the exponent.
            if digits[0usize] == 0u8 {
                var back = 0usize
                while back + 1usize < used {
                    digits[back] = digits[back + 1usize]
                    back += 1usize
                }
                used = used - 1usize
                exponent = exponent - 1i64
            }
            binary_exponent += 1i64
        } else {
            var carry = 0u8
            var scan = used
            while scan > 0usize {
                scan = scan - 1usize
                let value = digits[scan] * 2u8 + carry
                digits[scan] = value % 10u8
                carry = value / 10u8
            }
            if carry != 0u8 {
                if used == digits.len {
                    if digits[used - 1usize] != 0u8 { truncated = true }
                } else {
                    used += 1usize
                }
                var back = used
                while back > 1usize {
                    back = back - 1usize
                    digits[back] = digits[back - 1usize]
                }
                digits[0usize] = carry
                exponent += 1i64
            }
            binary_exponent = binary_exponent - 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
    }
    // The value is `m * 2^binary_exponent` with `m` in `[0.5, 1)`, which fixes a
    // normal number's exponent field and leaves only the mantissa to read.
    var biased = binary_exponent - 1i64 + 127i64
    var bits = 24i64
    if biased < 1i64 {
        // Subnormal: the exponent field is pinned at zero and the mantissa loses one
        // bit for every step below the smallest normal. `bits` is the value's exponent
        // in units of that smallest subnormal, so a negative one is less than half of
        // it and rounds to a zero the input did not write.
        bits = 24i64 + biased - 1i64
        biased = 0i64
        if bits < 0i64 { ret (0.0f32, BadNumber) }
    }
    var shifted = 0i64
    while shifted < bits {
        var carry = 0u8
        var scan = used
        while scan > 0usize {
            scan = scan - 1usize
            let value = digits[scan] * 2u8 + carry
            digits[scan] = value % 10u8
            carry = value / 10u8
        }
        if carry != 0u8 {
            if used == digits.len {
                if digits[used - 1usize] != 0u8 { truncated = true }
            } else {
                used += 1usize
            }
            var back = used
            while back > 1usize {
                back = back - 1usize
                digits[back] = digits[back - 1usize]
            }
            digits[0usize] = carry
            exponent += 1i64
        }
        while used > 0usize && digits[used - 1usize] == 0u8 { used = used - 1usize }
        shifted += 1i64
    }
    var mantissa = 0u32
    var taken = 0i64
    while taken < exponent {
        var digit = 0u8
        if usize(taken) < used { digit = digits[usize(taken)] }
        mantissa = mantissa * 10u32 + u32(digit)
        taken += 1i64
    }
    // Round to nearest, ties to even, on the digits the integer part left behind.
    var round_up = false
    if exponent >= 0i64 && usize(exponent) < used {
        let first = digits[usize(exponent)]
        if first > 5u8 { round_up = true }
        if first == 5u8 {
            var beyond = truncated
            var scan = usize(exponent) + 1usize
            while scan < used {
                if digits[scan] != 0u8 { beyond = true }
                scan += 1usize
            }
            if beyond {
                round_up = true
            } else {
                round_up = mantissa % 2u32 == 1u32
            }
        }
    }
    if round_up { mantissa += 1u32 }
    let implicit = 1u32 << 23u32
    if biased == 0i64 {
        // The carry out of a subnormal's mantissa is exactly the smallest normal.
        if mantissa >= implicit { biased = 1i64 }
    } else {
        if mantissa >= implicit * 2u32 {
            mantissa = mantissa / 2u32
            biased += 1i64
        }
    }
    if biased > 254i64 { ret (0.0f32, BadNumber) }
    var fraction = mantissa
    if biased >= 1i64 { fraction = mantissa - implicit }
    if biased == 0i64 && fraction == 0u32 { ret (0.0f32, BadNumber) }
    var pattern = u32(biased) << 23u32
    pattern = pattern + fraction
    if negative { pattern = pattern + 2147483648u32 }
    ret (mem.bitcast[f32](pattern), ok)
}

fn compare(x: str, y: str) -> i32 {
    var at = 0usize
    while at < x.len && at < y.len {
        if x[at] != y[at] {
            if x[at] < y[at] { ret -1i32 }
            ret 1i32
        }
        at += 1usize
    }
    if x.len < y.len { ret -1i32 }
    if x.len > y.len { ret 1i32 }
    ret 0i32
}

fn compare_ascii_fold(x: str, y: str) -> i32 {
    var at = 0usize
    while at < x.len && at < y.len {
        var xb = x[at]
        var yb = y[at]
        if xb >= 65u8 && xb <= 90u8 { xb += 32u8 }
        if yb >= 65u8 && yb <= 90u8 { yb += 32u8 }
        if xb != yb {
            if xb < yb { ret -1i32 }
            ret 1i32
        }
        at += 1usize
    }
    if x.len < y.len { ret -1i32 }
    if x.len > y.len { ret 1i32 }
    ret 0i32
}

fn starts_with(s: str, prefix: str) -> bool {
    if prefix.len > s.len { ret false }
    var at = 0usize
    while at < prefix.len {
        if s[at] != prefix[at] { ret false }
        at += 1usize
    }
    ret true
}

fn ends_with(s: str, suffix: str) -> bool {
    if suffix.len > s.len { ret false }
    let base = s.len - suffix.len
    var at = 0usize
    while at < suffix.len {
        if s[base + at] != suffix[at] { ret false }
        at += 1usize
    }
    ret true
}

fn contains(s: str, needle: str) -> bool {
    let (_, found) = find_from(s, needle, 0usize)
    ret found
}

fn find(s: str, needle: str) -> (usize, bool) {
    let (at, found) = find_from(s, needle, 0usize)
    ret (at, found)
}

// An empty needle matches at every boundary, so it is found at `start` itself as long
// as `start` is one. A `start` past the end is not a boundary and matches nothing.
fn find_from(s: str, needle: str, start: usize) -> (usize, bool) {
    if start > s.len { ret (0usize, false) }
    if needle.len == 0usize { ret (start, true) }
    if needle.len > s.len { ret (0usize, false) }
    let last = s.len - needle.len
    var at = start
    while at <= last {
        var k = 0usize
        var matched = true
        while k < needle.len {
            if s[at + k] != needle[k] {
                matched = false
                break
            }
            k += 1usize
        }
        if matched { ret (at, true) }
        at += 1usize
    }
    ret (0usize, false)
}

fn rfind(s: str, needle: str) -> (usize, bool) {
    if needle.len == 0usize { ret (s.len, true) }
    if needle.len > s.len { ret (0usize, false) }
    var at = s.len - needle.len
    while true {
        var k = 0usize
        var matched = true
        while k < needle.len {
            if s[at + k] != needle[k] {
                matched = false
                break
            }
            k += 1usize
        }
        if matched { ret (at, true) }
        if at == 0usize { break }
        at -= 1usize
    }
    ret (0usize, false)
}

// Non-overlapping, so `count("aaa", "aa")` is 1. An empty needle sits at every
// boundary, which is one more than there are bytes.
fn count(s: str, needle: str) -> usize {
    if needle.len == 0usize { ret s.len + 1usize }
    var total = 0usize
    var at = 0usize
    while true {
        let (found_at, found) = find_from(s, needle, at)
        if !found { break }
        total += 1usize
        at = found_at + needle.len
    }
    ret total
}

fn trim(s: str) -> str {
    var at = 0usize
    while at < s.len && is_ascii_space(s[at]) { at += 1usize }
    var end = s.len
    while end > at && is_ascii_space(s[end - 1usize]) { end -= 1usize }
    ret s[at..end]
}

fn trim_start(s: str) -> str {
    var at = 0usize
    while at < s.len && is_ascii_space(s[at]) { at += 1usize }
    ret s[at..]
}

fn trim_end(s: str) -> str {
    var end = s.len
    while end > 0usize && is_ascii_space(s[end - 1usize]) { end -= 1usize }
    ret s[0usize..end]
}

fn trim_bytes(s: str, bytes: str) -> str {
    var at = 0usize
    while at < s.len {
        var head_hit = false
        var head_k = 0usize
        while head_k < bytes.len {
            if bytes[head_k] == s[at] {
                head_hit = true
                break
            }
            head_k += 1usize
        }
        if !head_hit { break }
        at += 1usize
    }
    var end = s.len
    while end > at {
        var tail_hit = false
        var tail_k = 0usize
        while tail_k < bytes.len {
            if bytes[tail_k] == s[end - 1usize] {
                tail_hit = true
                break
            }
            tail_k += 1usize
        }
        if !tail_hit { break }
        end -= 1usize
    }
    ret s[at..end]
}

fn split_once(s: str, separator: str) -> (str, str, bool) {
    let (at, found) = find_from(s, separator, 0usize)
    if !found { ret (s, "", false) }
    let head = s[0usize..at]
    let tail = s[at + separator.len..]
    ret (head, tail, true)
}

fn split(s: str, separator: str) -> (Split, err) {
    var it: Split = zero
    if separator.len == 0usize { ret (it, InvalidSeparator) }
    it.source = s
    it.separator = separator
    ret (it, ok)
}

fn split_next(it: *Split) -> (str, bool) {
    if it.finished { ret ("", false) }
    // Line mode, which only `lines` produces. The terminator is LF; a CR directly
    // before one goes with it; and the input's own trailing terminator ends the
    // traversal rather than opening a final empty line.
    if it.separator.len == 0usize {
        if it.off >= it.source.len {
            it.finished = true
            ret ("", false)
        }
        var scan = it.off
        while scan < it.source.len && it.source[scan] != 10u8 { scan += 1usize }
        var end = scan
        if scan < it.source.len && end > it.off && it.source[end - 1usize] == 13u8 { end -= 1usize }
        let line = it.source[it.off..end]
        it.off = scan + 1usize
        if scan == it.source.len {
            it.finished = true
            it.off = scan
        }
        ret (line, true)
    }
    let (at, found) = find_from(it.source, it.separator, it.off)
    if !found {
        let last = it.source[it.off..]
        it.off = it.source.len
        it.finished = true
        ret (last, true)
    }
    let field = it.source[it.off..at]
    it.off = at + it.separator.len
    ret (field, true)
}

fn lines(s: str) -> Split {
    var it: Split = zero
    it.source = s
    ret it
}

// Non-overlapping, on the same boundaries `count` reports: an empty needle puts the
// replacement at every one of them, which is between each pair of bytes and at both
// ends.
fn replace(a: *mem.Arena, s: str, needle: str, replacement: str) -> (str, err) {
    var (b, builder_error) = builder(a, s.len)
    if builder_error != ok { ret ("", builder_error) }
    if needle.len == 0usize {
        var boundary = 0usize
        while true {
            let empty_error = push(&b, replacement)
            if empty_error != ok { ret ("", empty_error) }
            if boundary == s.len { break }
            let byte_error = push_byte(&b, s[boundary])
            if byte_error != ok { ret ("", byte_error) }
            boundary += 1usize
        }
        let spread = done(&b)
        ret (spread, ok)
    }
    var at = 0usize
    while at < s.len {
        let (found_at, found) = find_from(s, needle, at)
        if !found { break }
        let head_error = push(&b, s[at..found_at])
        if head_error != ok { ret ("", head_error) }
        let replacement_error = push(&b, replacement)
        if replacement_error != ok { ret ("", replacement_error) }
        at = found_at + needle.len
    }
    let tail_error = push(&b, s[at..])
    if tail_error != ok { ret ("", tail_error) }
    let out = done(&b)
    ret (out, ok)
}

fn repeat(a: *mem.Arena, s: str, repeat_count: usize) -> (str, err) {
    var (b, builder_error) = builder(a, s.len * repeat_count)
    if builder_error != ok { ret ("", builder_error) }
    var at = 0usize
    while at < repeat_count {
        let push_error = push(&b, s)
        if push_error != ok { ret ("", push_error) }
        at += 1usize
    }
    let out = done(&b)
    ret (out, ok)
}

fn ascii_lower_in_place(s: []u8) {
    var at = 0usize
    while at < s.len {
        if s[at] >= 65u8 && s[at] <= 90u8 { s[at] += 32u8 }
        at += 1usize
    }
}

fn ascii_upper_in_place(s: []u8) {
    var at = 0usize
    while at < s.len {
        if s[at] >= 97u8 && s[at] <= 122u8 { s[at] -= 32u8 }
        at += 1usize
    }
}

fn is_ascii_space(b: u8) -> bool {
    ret b == 32u8 || (b >= 9u8 && b <= 13u8)
}

fn is_ascii_digit(b: u8) -> bool {
    ret b >= 48u8 && b <= 57u8
}

fn is_ascii_alpha(b: u8) -> bool {
    if b >= 65u8 && b <= 90u8 { ret true }
    ret b >= 97u8 && b <= 122u8
}

fn is_ascii_alnum(b: u8) -> bool {
    ret is_ascii_digit(b) || is_ascii_alpha(b)
}

// --- Padding to a width counted in UTF-8 code points (#356).

type Side = enum u8 { Left, Right, Center }

// Code points in `s`: every byte that is not a continuation byte.
fn count_points(s: str) -> usize {
    var n = 0usize
    var at = 0usize
    while at < s.len {
        if (s[at] & 192u8) != 128u8 { n += 1usize }
        at += 1usize
    }
    ret n
}

fn push_repeated(b: *Builder, fill: str, times: usize) -> err {
    var at = 0usize
    while at < times {
        let push_error = push(b, fill)
        if push_error != ok { ret push_error }
        at += 1usize
    }
    ret ok
}

// `s` padded with copies of `fill` (one code point, any width in bytes) to
// `width` code points on `side`; a string already that wide comes back as it
// is. `Center` puts the odd extra copy on the right. An empty `fill` is
// `InvalidSeparator`.
fn pad(a: *mem.Arena, s: str, width: usize, side: Side, fill: str) -> (str, err) {
    if fill.len == 0usize { ret ("", InvalidSeparator) }
    let have = count_points(s)
    if have >= width { ret (s, ok) }
    let extra = width - have
    var before = 0usize
    if side == .Left { before = extra }
    if side == .Center { before = extra / 2usize }
    let after = extra - before
    var (b, builder_error) = builder(a, s.len + extra * fill.len)
    if builder_error != ok { ret ("", builder_error) }
    let before_error = push_repeated(&b, fill, before)
    if before_error != ok { ret ("", before_error) }
    let push_error = push(&b, s)
    if push_error != ok { ret ("", push_error) }
    let after_error = push_repeated(&b, fill, after)
    if after_error != ok { ret ("", after_error) }
    let out = done(&b)
    ret (out, ok)
}

fn pad_left(a: *mem.Arena, s: str, width: usize, fill: str) -> (str, err) {
    let (out, pad_error) = pad(a, s, width, .Left, fill)
    ret (out, pad_error)
}

fn pad_right(a: *mem.Arena, s: str, width: usize, fill: str) -> (str, err) {
    let (out, pad_error) = pad(a, s, width, .Right, fill)
    ret (out, pad_error)
}

fn pad_center(a: *mem.Arena, s: str, width: usize, fill: str) -> (str, err) {
    let (out, pad_error) = pad(a, s, width, .Center, fill)
    ret (out, pad_error)
}
