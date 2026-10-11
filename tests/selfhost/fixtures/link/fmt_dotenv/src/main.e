// e.fmt.dotenv against python-dotenv's parser and variable resolution (DotEnv.dict with interpolation, both
// override settings): quoting and escapes, comments, `export`, bare keys, multi-line values, invalid lines, line
// endings, a byte-order mark, and `${NAME}` / `${NAME:-default}` over earlier bindings and an external environment.
// A record is OVERRIDE GS EXTERNAL GS TEXT GS EXPECTED RS; the expected text is `key US (N | V value) FS` for each
// distinct key in first-seen order (the last binding's value).
use e.io
use e.mem
use e.os
use e.fmt.dotenv
use e.str

fn field(rec: str, index: usize) -> str {
    var at = 0usize
    var current = 0usize
    var start = 0usize
    while at <= rec.len {
        if at == rec.len || rec[at] == 29u8 {
            if current == index { ret rec[start..at] }
            current += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    ret ""
}

fn externals(a: *mem.Arena, text: str, out: []dotenv.Entry) -> usize {
    var n = 0usize
    var at = 0usize
    var start = 0usize
    while at <= text.len {
        if at == text.len || text[at] == 28u8 {
            if at > start {
                let pair = text[start..at]
                var sep = 0usize
                while sep < pair.len && pair[sep] != 31u8 { sep += 1usize }
                out[n] = dotenv.Entry { key: pair[0usize..sep], value: pair[sep + 1usize..pair.len], has_value: true }
                n += 1usize
            }
            start = at + 1usize
        }
        at += 1usize
    }
    ret n
}

// The result as `key US (N | V value) FS` for each distinct key in first-seen order.
fn serialize(a: *mem.Arena, entries: []const dotenv.Entry) -> (str, err) {
    var (b, builder_error) = str.builder(a, 64usize)
    if builder_error != ok { ret ("", builder_error) }
    var i = 0usize
    while i < entries.len {
        var seen = false
        var j = 0usize
        while j < i {
            if str.eq(entries[j].key, entries[i].key) { seen = true }
            j += 1usize
        }
        if !seen {
            let (last, found) = dotenv.get(entries, entries[i].key)
            try str.push(&b, entries[i].key)
            try str.push_byte(&b, 31u8)
            if last.has_value {
                try str.push_byte(&b, 86u8)
                try str.push(&b, last.value)
            } else {
                try str.push_byte(&b, 78u8)
            }
            try str.push_byte(&b, 28u8)
        }
        i += 1usize
    }
    ret (str.done(&b), ok)
}

fn run_record(a: *mem.Arena, rec: str) -> (str, err) {
    var ext: [16]dotenv.Entry = zero
    let ext_count = externals(a, field(rec, 1usize), ext[0usize..16usize])
    var entries: [64]dotenv.Entry = zero
    let (n, skipped, parse_error) = dotenv.parse(a, field(rec, 2usize), entries[0usize..64usize])
    if parse_error != ok { ret ("", parse_error) }
    let override = field(rec, 0usize)[0usize] == 49u8
    let resolve_error = dotenv.interpolate(a, entries[0usize..n], ext[0usize..ext_count], override)
    if resolve_error != ok { ret ("", resolve_error) }
    let (text, text_error) = serialize(a, entries[0usize..n])
    ret (text, text_error)
}

fn run(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 30u8 {
            let mark = mem.mark(a)
            let rec = text[start..i]
            let (got, run_error) = run_record(a, rec)
            if run_error != ok { ret 1u8 }
            if !str.eq(got, field(rec, 3usize)) { ret 2u8 }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}
fn dotenv_vectors_0() -> str {
    ret "1\x1DE_ENV\x1F\x1CEMPTY\x1F\x1D=novalue\x1D\x1E0\x1DE_ENV\x1Ffrom env\x1CHOME\x1Ffrom env\x1CMISSING2\x1F\x1Dexport\r\nX=\"multi\nline value\"\r\nB2='unterminated\r\nV=\"tab\\there \\\\ backslash \\\" quote\"\r\n'quoted key'=qv\r\nF2=\xC3\xA9\xC3\xA8 unicode\r\nF=\"double quoted\"\r\nH=\r\nB=two words\r\n\x1Dexport\x1FN\x1CX\x1FVmulti\nline value\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1CF\x1FVdouble quoted\x1CH\x1FV\x1CB\x1FVtwo words\x1C\x1E1\x1DA\x1Fx y\x1CMISSING2\x1Ffrom env\x1DI= # only a comment\n'quoted key'=qv\nJ=#hash\nA=override later\nQ2=\\n literal\nT=\"line1\\nline2\"\n\x1DI\x1FV\x1Cquoted key\x1FVqv\x1CJ\x1FV#hash\x1CA\x1FVoverride later\x1CQ2\x1FV\\n literal\x1CT\x1FVline1\nline2\x1C\x1E0\x1DMISSING2\x1Ffrom env\x1DQ=$A\r\nN=${A}\r\nQ=$A\r\nE2=trailing   \r\nU='it\\'s'\r\n\x1DQ\x1FV$A\x1CN\x1FV\x1CE2\x1FVtrailing\x1CU\x1FVit's\x1C\x1E1\x1DHOME\x1F/home/me\x1CMISSING2\x1Fx y\x1DA=override later\rL2=${A\rN=${A}\rF=\"double quoted\"\rL=\"a # not a comment\" # real\rM\rB=two words\rV2=${A:-}\rQ2=\\n literal\r\x1DA\x1FVoverride later\x1CL2\x1FV${A\x1CN\x1FVoverride later\x1CF\x1FVdouble quoted\x1CL\x1FVa # not a comment\x1CM\x1FN\x1CB\x1FVtwo words\x1CV2\x1FVoverride later\x1CQ2\x1FV\\n literal\x1C\x1E1\x1DA\x1Ffrom env\x1DX=\"multi\nline value\"\nU='it\\'s'\nQ2=\\n literal\nexport D=exported\nD2=tab\tseparated\t# c\nN2='${A}'\n\x1DX\x1FVmulti\nline value\x1CU\x1FVit's\x1CQ2\x1FV\\n literal\x1CD\x1FVexported\x1CD2\x1FVtab\tseparated\x1CN2\x1FVfrom env\x1C\x1E1\x1DE_ENV\x1Ffrom env\x1D\xEF\xBB\xBFH2=${HOME:-nohome}\r\nQ2=\\n literal\r\nA2=\"x\" junk\r\n   \r\n#=x\r\nS=${}\r\nZ2=\"\"\r\nH2=${HOME:-nohome}\r\n\x1DH2\x1FVnohome\x1CQ2\x1FV\\n literal\x1CS\x1FV\x1CZ2\x1FV\x1C\x1E0\x1DE_ENV\x1F\x1DO2 = \"q\" # c\rQ2=\\n literal\r=novalue\rR=${A:b}\r   # indented comment\rA=1\rG='single quoted'\rT=\"line1\\nline2\"\r\x1DO2\x1FVq\x1CQ2\x1FV\\n literal\x1CR\x1FV${A:b}\x1CA\x1FV1\x1CG\x1FVsingle quoted\x1CT\x1FVline1\nline2\x1C\x1E1\x1D\x1DM2=\"${A}\"\rL=\"a # not a comment\" # real\rD2=tab\tseparated\t# c\rY='multi\nline'\rD2=tab\tseparated\t# c\r\x1DM2\x1FV\x1CL\x1FVa # not a comment\x1CD2\x1FVtab\tseparated\x1CY\x1FVmulti\nline\x1C\x1E1\x1DA\x1F\x1CMISSING2\x1Ffrom env\x1DS=${}\nH=\nB2='unterminated\x1DS\x1FV\x1CH\x1FV\x1C\x1E1\x1DE_ENV\x1F\x1CHOME\x1F/home/me\x1CA\x1Ffrom env\x1D'quoted key'=qv\rW=\"unknown \\q escape\"\rT2=  leading\rN2='${A}'\rO=${MISSING:-fallback}\r\x1Dquoted key\x1FVqv\x1CW\x1FVunknown \\q escape\x1CT2\x1FVleading\x1CN2\x1FVfrom env\x1CO\x1FVfallback\x1C\x1E0\x1DE_ENV\x1F/home/me\x1CHOME\x1F/home/me\x1CA\x1Ffrom env\x1CEMPTY\x1Ffrom env\x1DS2='\\n stays'\r\n\x1DS2\x1FV\\n stays\x1C\x1E"
}

fn dotenv_vectors_1() -> str {
    ret "0\x1DHOME\x1F\x1CA\x1F/home/me\x1CMISSING2\x1Ffrom env\x1DX=\"multi\nline value\"\nW2=${E_ENV:-${A}}\nJ2=${A:-${B}}\n   \nK2=a${\nL=\"a # not a comment\" # real\nV=\"tab\\there \\\\ backslash \\\" quote\"\nC = spaced\n\x1DX\x1FVmulti\nline value\x1CW2\x1FV${A}\x1CJ2\x1FV/home/me}\x1CK2\x1FVa${\x1CL\x1FVa # not a comment\x1CV\x1FVtab\there \\ backslash \" quote\x1CC\x1FVspaced\x1C\x1E0\x1DA\x1Fx y\x1DU2=a\\\rP2=a=b=c\rZ2=\"\"\r# a comment\r   # indented comment\rG2=${E_ENV}\rJ=#hash\x1DU2\x1FVa\\\x1CP2\x1FVa=b=c\x1CZ2\x1FV\x1CG2\x1FV\x1CJ\x1FV#hash\x1C\x1E1\x1DA\x1Ffrom env\x1CEMPTY\x1Fx y\x1DO=${MISSING:-fallback}\nQ2=\\n literal\nT=\"line1\\nline2\"\nU='it\\'s'\nL2=${A\n\x1DO\x1FVfallback\x1CQ2\x1FV\\n literal\x1CT\x1FVline1\nline2\x1CU\x1FVit's\x1CL2\x1FV${A\x1C\x1E1\x1DEMPTY\x1F\x1DQ2=\\n literal\nD2=tab\tseparated\t# c\n\x1DQ2\x1FV\\n literal\x1CD2\x1FVtab\tseparated\x1C\x1E0\x1DMISSING2\x1Ffrom env\x1DC2=\"unterminated\nJ=#hash\nexport   E=more\nB=two words\nZ B=1\nR2=\"\\a\\b\\f\\v\\r\"\n=novalue\nX=\"multi\nline value\"\n\x1DX\x1FVmulti\nline value\x1C\x1E1\x1DE_ENV\x1F\x1CEMPTY\x1Fx y\x1DB=${A}\nR=${A:b}\nexport D=exported\nW2=${E_ENV:-${A}}\nE2=trailing   \nU='it\\'s'\nV2=${A:-}\n#=x\n\x1DB\x1FV\x1CR\x1FV${A:b}\x1CD\x1FVexported\x1CW2\x1FV}\x1CE2\x1FVtrailing\x1CU\x1FVit's\x1CV2\x1FV\x1C\x1E0\x1DA\x1Fx y\x1CMISSING2\x1F/home/me\x1DV2=${A:-}\nP=${A:-d}x${B}\nW=\"unknown \\q escape\"\n   # indented comment\nD2=tab\tseparated\t# c\n\nQ2=\\n literal\nF=\"double quoted\"\nY='multi\nline'\n\x1DV2\x1FVx y\x1CP\x1FVx yx\x1CW\x1FVunknown \\q escape\x1CD2\x1FVtab\tseparated\x1CQ2\x1FV\\n literal\x1CF\x1FVdouble quoted\x1CY\x1FVmulti\nline\x1C\x1E1\x1DE_ENV\x1F/home/me\x1CEMPTY\x1F\x1DP2=a=b=c\r\nP=${A:-d}x${B}\r\nA=override later\r\n   \r\nG2=${E_ENV}\r\nX=\"multi\nline value\"\r\nS2='\\n stays'\r\n\x1DP2\x1FVa=b=c\x1CP\x1FVdx\x1CA\x1FVoverride later\x1CG2\x1FV/home/me\x1CX\x1FVmulti\nline value\x1CS2\x1FV\\n stays\x1C\x1E0\x1DE_ENV\x1Fx y\x1CA\x1F/home/me\x1CEMPTY\x1F/home/me\x1DW=\"unknown \\q escape\"\rM\rF=\"double quoted\"\rA2=\"x\" junk\rG='single quoted'\rQ=$A\rR2=\"\\a\\b\\f\\v\\r\"\rU2=a\\\x1DW\x1FVunknown \\q escape\x1CM\x1FN\x1CF\x1FVdouble quoted\x1CG\x1FVsingle quoted\x1CQ\x1FV$A\x1CR2\x1FV\x07\x08\x0C\x0B\r\x1CU2\x1FVa\\\x1C\x1E0\x1DE_ENV\x1Ffrom env\x1CHOME\x1F/home/me\x1DM2=\"${A}\"\rN2='${A}'\x1DM2\x1FV\x1CN2\x1FV\x1C\x1E0\x1D\x1Dexport =1\nexport   E=more\nJ2=${A:-${B}}\nH2=${HOME:-nohome}\nK=value # trailing\n\x1DE\x1FVmore\x1CJ2\x1FV${B}\x1CH2\x1FVnohome\x1CK\x1FVvalue\x1C\x1E1\x1DA\x1Fx y\x1CEMPTY\x1Ffrom env\x1DY='multi\nline'\rA2=\"x\" junk\rI= # only a comment\r\x1DY\x1FVmulti\nline\x1CI\x1FV\x1C\x1E"
}

fn dotenv_vectors_2() -> str {
    ret "0\x1DA\x1F/home/me\x1CMISSING2\x1F\x1DK=value # trailing\r\n'quoted key'=qv\r\nN2='${A}'\r\nG='single quoted'\r\nexport =1\r\n\x1DK\x1FVvalue\x1Cquoted key\x1FVqv\x1CN2\x1FV/home/me\x1CG\x1FVsingle quoted\x1C\x1E1\x1DE_ENV\x1F\x1CHOME\x1Fx y\x1CA\x1F/home/me\x1CEMPTY\x1F\x1CMISSING2\x1Ffrom env\x1D\xEF\xBB\xBFE2=trailing   \r\nL=\"a # not a comment\" # real\r\n   # indented comment\r\nexport   E=more\r\nS=${}\r\nV=\"tab\\there \\\\ backslash \\\" quote\"\r\n\x1DE2\x1FVtrailing\x1CL\x1FVa # not a comment\x1CE\x1FVmore\x1CS\x1FV\x1CV\x1FVtab\there \\ backslash \" quote\x1C\x1E0\x1DEMPTY\x1Fx y\x1D#=x\nP2=a=b=c\nN2='${A}'\nexport\nU2=a\\\n\x1DP2\x1FVa=b=c\x1CN2\x1FV\x1Cexport\x1FN\x1CU2\x1FVa\\\x1C\x1E1\x1DE_ENV\x1F\x1CHOME\x1F\x1CEMPTY\x1Ffrom env\x1DZ2=\"\"\n\nN2='${A}'\n\x1DZ2\x1FV\x1CN2\x1FV\x1C\x1E1\x1DE_ENV\x1F/home/me\x1CMISSING2\x1Fx y\x1DN=${A}\nY='multi\nline'\nM2=\"${A}\"\x1DN\x1FV\x1CY\x1FVmulti\nline\x1CM2\x1FV\x1C\x1E0\x1DE_ENV\x1Fx y\x1CMISSING2\x1F\x1DZ2=\"\"\rexport\rC = spaced\rB=two words\rY='multi\nline'\rC2=\"unterminated\rQ=$A\rB2='unterminated\rR2=\"\\a\\b\\f\\v\\r\"\x1DZ2\x1FV\x1Cexport\x1FN\x1CC\x1FVspaced\x1CB\x1FVtwo words\x1CY\x1FVmulti\nline\x1C\x1E0\x1DE_ENV\x1Ffrom env\x1CEMPTY\x1F/home/me\x1CMISSING2\x1F/home/me\x1DO2 = \"q\" # c\r\nZ2=\"\"\r\nU='it\\'s'\r\n   \r\nF=\"double quoted\"\r\n\x1DO2\x1FVq\x1CZ2\x1FV\x1CU\x1FVit's\x1CF\x1FVdouble quoted\x1C\x1E0\x1D\x1DB=two words\r\nU2=a\\\r\n\x1DB\x1FVtwo words\x1CU2\x1FVa\\\x1C\x1E1\x1DHOME\x1F/home/me\x1CEMPTY\x1Ffrom env\x1Dexport   E=more\nQ=$A\nS=${}\n\x1DE\x1FVmore\x1CQ\x1FV$A\x1CS\x1FV\x1C\x1E1\x1DHOME\x1F\x1CEMPTY\x1F\x1CMISSING2\x1Ffrom env\x1D\xEF\xBB\xBF'quoted key'=qv\r\rG='single quoted'\rN2='${A}'\rexport D=exported\rO2 = \"q\" # c\rE2=trailing   \rT=\"line1\\nline2\"\x1Dquoted key\x1FVqv\x1CG\x1FVsingle quoted\x1CN2\x1FV\x1CD\x1FVexported\x1CO2\x1FVq\x1CE2\x1FVtrailing\x1CT\x1FVline1\nline2\x1C\x1E0\x1DE_ENV\x1Fx y\x1D\xEF\xBB\xBFP=${A:-d}x${B}\rH=\rS2='\\n stays'\rP2=a=b=c\rS=${}\x1DP\x1FVdx\x1CH\x1FV\x1CS2\x1FV\\n stays\x1CP2\x1FVa=b=c\x1CS\x1FV\x1C\x1E0\x1DEMPTY\x1Ffrom env\x1CMISSING2\x1Fx y\x1DE2=trailing   \nB2='unterminated\nJ2=${A:-${B}}\nS2='\\n stays'\x1DE2\x1FVtrailing\x1C\x1E"
}

fn dotenv_vectors_3() -> str {
    ret "1\x1DEMPTY\x1Fx y\x1DM2=\"${A}\"\r\nC2=\"unterminated\r\n\x1DM2\x1FV\x1C\x1E0\x1DE_ENV\x1F/home/me\x1CMISSING2\x1F/home/me\x1Dexport D=exported\nJ=#hash\nS=${}\nA=1\nV2=${A:-}\nJ=#hash\nS2='\\n stays'\nO2 = \"q\" # c\n   # indented comment\n\x1DD\x1FVexported\x1CJ\x1FV#hash\x1CS\x1FV\x1CA\x1FV1\x1CV2\x1FV1\x1CS2\x1FV\\n stays\x1CO2\x1FVq\x1C\x1E0\x1D\x1DT=\"line1\\nline2\"\nN=${A}\nR2=\"\\a\\b\\f\\v\\r\"\n#=x\nB2='unterminated\nN2='${A}'\nS=${}\x1DT\x1FVline1\nline2\x1CN\x1FV\x1CR2\x1FV\x07\x08\x0C\x0B\r\x1CS\x1FV\x1C\x1E1\x1DEMPTY\x1F/home/me\x1DD2=tab\tseparated\t# c\nY='multi\nline'\nN2='${A}'\nexport   E=more\n\x1DD2\x1FVtab\tseparated\x1CY\x1FVmulti\nline\x1CN2\x1FV\x1CE\x1FVmore\x1C\x1E0\x1DE_ENV\x1Fx y\x1CA\x1F/home/me\x1CMISSING2\x1Fx y\x1DI2=${A}${A}\x1DI2\x1FV/home/me/home/me\x1C\x1E0\x1DA\x1Ffrom env\x1CEMPTY\x1F\x1CMISSING2\x1F\x1DC = spaced\nM2=\"${A}\"\nI2=${A}${A}\nA=1\nF=\"double quoted\"\nG2=${E_ENV}\nF2=\xC3\xA9\xC3\xA8 unicode\n\x1DC\x1FVspaced\x1CM2\x1FVfrom env\x1CI2\x1FVfrom envfrom env\x1CA\x1FV1\x1CF\x1FVdouble quoted\x1CG2\x1FV\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1C\x1E0\x1DE_ENV\x1Ffrom env\x1CA\x1F\x1CMISSING2\x1Ffrom env\x1DF=\"double quoted\"\nW=\"unknown \\q escape\"\nE2=trailing   \nB2='unterminated\nN2='${A}'\nZ B=1\nL2=${A\n\x1DF\x1FVdouble quoted\x1CW\x1FVunknown \\q escape\x1CE2\x1FVtrailing\x1CL2\x1FV${A\x1C\x1E1\x1DHOME\x1Ffrom env\x1DE2=trailing   \rexport\rG='single quoted'\rA=override later\rQ=$A\rU='it\\'s'\r\x1DE2\x1FVtrailing\x1Cexport\x1FN\x1CG\x1FVsingle quoted\x1CA\x1FVoverride later\x1CQ\x1FV$A\x1CU\x1FVit's\x1C\x1E1\x1DEMPTY\x1F\x1DX=\"multi\nline value\"\nF2=\xC3\xA9\xC3\xA8 unicode\nexport\n\x1DX\x1FVmulti\nline value\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1Cexport\x1FN\x1C\x1E0\x1DE_ENV\x1Ffrom env\x1CEMPTY\x1F/home/me\x1DA2=\"x\" junk\rQ=$A\rV2=${A:-}\rO=${MISSING:-fallback}\rL=\"a # not a comment\" # real\rA=override later\rexport\r\r\x1DQ\x1FV$A\x1CV2\x1FV\x1CO\x1FVfallback\x1CL\x1FVa # not a comment\x1CA\x1FVoverride later\x1Cexport\x1FN\x1C\x1E0\x1DE_ENV\x1Ffrom env\x1CMISSING2\x1Ffrom env\x1DN=${A}\n=novalue\nI= # only a comment\nS=${}\nG='single quoted'\x1DN\x1FV\x1CI\x1FV\x1CS\x1FV\x1CG\x1FVsingle quoted\x1C\x1E0\x1D\x1DP=${A:-d}x${B}\nI= # only a comment\nR=${A:b}\nC2=\"unterminated\nQ2=\\n literal\nZ B=1\nB=${A}\nM\n\x1DP\x1FVdx\x1CI\x1FV\x1CR\x1FV${A:b}\x1CQ2\x1FV\\n literal\x1CB\x1FV\x1CM\x1FN\x1C\x1E"
}

fn dotenv_vectors_4() -> str {
    ret "0\x1DE_ENV\x1Fx y\x1CA\x1F\x1CEMPTY\x1Ffrom env\x1CMISSING2\x1F/home/me\x1DC2=\"unterminated\nZ2=\"\"\nexport D=exported\n   \n   \n\x1DD\x1FVexported\x1C\x1E1\x1DE_ENV\x1F/home/me\x1CA\x1Ffrom env\x1D#=x\r\nV2=${A:-}\r\nexport D=exported\r\nK2=a${\r\nT=\"line1\\nline2\"\r\nT2=  leading\r\nV2=${A:-}\r\n\x1DV2\x1FVfrom env\x1CD\x1FVexported\x1CK2\x1FVa${\x1CT\x1FVline1\nline2\x1CT2\x1FVleading\x1C\x1E1\x1DHOME\x1F/home/me\x1CMISSING2\x1F\x1D\xEF\xBB\xBFI= # only a comment\nL2=${A\nH2=${HOME:-nohome}\n\x1DI\x1FV\x1CL2\x1FV${A\x1CH2\x1FV/home/me\x1C\x1E0\x1DEMPTY\x1Ffrom env\x1Dexport X2\nZ2=\"\"\x1DX2\x1FN\x1CZ2\x1FV\x1C\x1E1\x1DE_ENV\x1F\x1CMISSING2\x1Ffrom env\x1DA=1\nL2=${A\nA=override later\nN2='${A}'\nF2=\xC3\xA9\xC3\xA8 unicode\nF2=\xC3\xA9\xC3\xA8 unicode\nN=${A}\x1DA\x1FVoverride later\x1CL2\x1FV${A\x1CN2\x1FVoverride later\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1CN\x1FVoverride later\x1C\x1E0\x1DHOME\x1Fx y\x1CMISSING2\x1F\x1DV=\"tab\\there \\\\ backslash \\\" quote\"\nZ2=\"\"\nL=\"a # not a comment\" # real\nX=\"multi\nline value\"\n\x1DV\x1FVtab\there \\ backslash \" quote\x1CZ2\x1FV\x1CL\x1FVa # not a comment\x1CX\x1FVmulti\nline value\x1C\x1E0\x1DE_ENV\x1Fx y\x1DI= # only a comment\n=novalue\nL=\"a # not a comment\" # real\nM2=\"${A}\"\nO=${MISSING:-fallback}\nF2=\xC3\xA9\xC3\xA8 unicode\nB2='unterminated\nexport\n\x1DI\x1FV\x1CL\x1FVa # not a comment\x1CM2\x1FV\x1CO\x1FVfallback\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1Cexport\x1FN\x1C\x1E0\x1DE_ENV\x1Ffrom env\x1CA\x1F\x1CMISSING2\x1Fx y\x1DQ2=\\n literal\nexport X2\nT=\"line1\\nline2\"\nS=${}\nZ B=1\nZ2=\"\"\nI2=${A}${A}\nF2=\xC3\xA9\xC3\xA8 unicode\n\x1DQ2\x1FV\\n literal\x1CX2\x1FN\x1CT\x1FVline1\nline2\x1CS\x1FV\x1CZ2\x1FV\x1CI2\x1FV\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1C\x1E0\x1DA\x1F\x1CMISSING2\x1Fx y\x1DL=\"a # not a comment\" # real\nT=\"line1\\nline2\"\nG='single quoted'\nT=\"line1\\nline2\"\x1DL\x1FVa # not a comment\x1CT\x1FVline1\nline2\x1CG\x1FVsingle quoted\x1C\x1E0\x1D\x1DA2=\"x\" junk\x1D\x1E0\x1DA\x1F\x1DV=\"tab\\there \\\\ backslash \\\" quote\"\nN2='${A}'\nG2=${E_ENV}\nC = spaced\nY2=''\n\x1DV\x1FVtab\there \\ backslash \" quote\x1CN2\x1FV\x1CG2\x1FV\x1CC\x1FVspaced\x1CY2\x1FV\x1C\x1E1\x1DEMPTY\x1F/home/me\x1DA=1\nL=\"a # not a comment\" # real\nP2=a=b=c\nM2=\"${A}\"\nF2=\xC3\xA9\xC3\xA8 unicode\x1DA\x1FV1\x1CL\x1FVa # not a comment\x1CP2\x1FVa=b=c\x1CM2\x1FV1\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1C\x1E"
}

fn dotenv_vectors_5() -> str {
    ret "1\x1D\x1DV=\"tab\\there \\\\ backslash \\\" quote\"\x1DV\x1FVtab\there \\ backslash \" quote\x1C\x1E1\x1DA\x1Fx y\x1CMISSING2\x1Fx y\x1D   # indented comment\rG2=${E_ENV}\rS2='\\n stays'\rN2='${A}'\r\x1DG2\x1FV\x1CS2\x1FV\\n stays\x1CN2\x1FVx y\x1C\x1E0\x1DHOME\x1F/home/me\x1CA\x1F\x1DY2=''\nS=${}\nJ=#hash\nW=\"unknown \\q escape\"\n'quoted key'=qv\n\x1DY2\x1FV\x1CS\x1FV\x1CJ\x1FV#hash\x1CW\x1FVunknown \\q escape\x1Cquoted key\x1FVqv\x1C\x1E1\x1DE_ENV\x1F/home/me\x1CEMPTY\x1Ffrom env\x1DJ2=${A:-${B}}\nD2=tab\tseparated\t# c\n   # indented comment\nI2=${A}${A}\nexport X2\n\x1DJ2\x1FV${B}\x1CD2\x1FVtab\tseparated\x1CI2\x1FV\x1CX2\x1FN\x1C\x1E1\x1DHOME\x1F/home/me\x1CA\x1F/home/me\x1DL2=${A\r\nH=\r\nI2=${A}${A}\r\nB=two words\r\nL=\"a # not a comment\" # real\r\nM2=\"${A}\"\r\nR2=\"\\a\\b\\f\\v\\r\"\r\nA=1\r\n\x1DL2\x1FV${A\x1CH\x1FV\x1CI2\x1FV/home/me/home/me\x1CB\x1FVtwo words\x1CL\x1FVa # not a comment\x1CM2\x1FV/home/me\x1CR2\x1FV\x07\x08\x0C\x0B\r\x1CA\x1FV1\x1C\x1E1\x1DE_ENV\x1F\x1CHOME\x1F/home/me\x1DL=\"a # not a comment\" # real\nR2=\"\\a\\b\\f\\v\\r\"\n#=x\nW=\"unknown \\q escape\"\nO2 = \"q\" # c\nO=${MISSING:-fallback}\nA2=\"x\" junk\n\x1DL\x1FVa # not a comment\x1CR2\x1FV\x07\x08\x0C\x0B\r\x1CW\x1FVunknown \\q escape\x1CO2\x1FVq\x1CO\x1FVfallback\x1C\x1E1\x1DE_ENV\x1Ffrom env\x1CHOME\x1F\x1DC = spaced\nR=${A:b}\nM2=\"${A}\"\n\x1DC\x1FVspaced\x1CR\x1FV${A:b}\x1CM2\x1FV\x1C\x1E1\x1DE_ENV\x1F\x1CA\x1Ffrom env\x1CMISSING2\x1Ffrom env\x1DA=1\rexport X2\x1DA\x1FV1\x1CX2\x1FN\x1C\x1E1\x1DE_ENV\x1F/home/me\x1CA\x1Ffrom env\x1CEMPTY\x1F\x1CMISSING2\x1Ffrom env\x1DR2=\"\\a\\b\\f\\v\\r\"\nV=\"tab\\there \\\\ backslash \\\" quote\"\nE2=trailing   \n# a comment\nP2=a=b=c\nQ=$A\nP=${A:-d}x${B}\nM\n\x1DR2\x1FV\x07\x08\x0C\x0B\r\x1CV\x1FVtab\there \\ backslash \" quote\x1CE2\x1FVtrailing\x1CP2\x1FVa=b=c\x1CQ\x1FV$A\x1CP\x1FVfrom envx\x1CM\x1FN\x1C\x1E1\x1DE_ENV\x1Ffrom env\x1DV2=${A:-}\n\x1DV2\x1FV\x1C\x1E0\x1DHOME\x1F/home/me\x1CMISSING2\x1F\x1DB=two words\n\x1DB\x1FVtwo words\x1C\x1E0\x1D\x1DI2=${A}${A}\nE2=trailing   \nW=\"unknown \\q escape\"\nI2=${A}${A}\nV2=${A:-}\n\x1DI2\x1FV\x1CE2\x1FVtrailing\x1CW\x1FVunknown \\q escape\x1CV2\x1FV\x1C\x1E"
}

fn dotenv_vectors_6() -> str {
    ret "1\x1DMISSING2\x1Ffrom env\x1D=novalue\r\nN2='${A}'\r\nM\r\nW=\"unknown \\q escape\"\r\nQ=$A\r\nP=${A:-d}x${B}\r\nP=${A:-d}x${B}\r\nF2=\xC3\xA9\xC3\xA8 unicode\r\nL2=${A\r\n\x1DN2\x1FV\x1CM\x1FN\x1CW\x1FVunknown \\q escape\x1CQ\x1FV$A\x1CP\x1FVdx\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1CL2\x1FV${A\x1C\x1E1\x1DE_ENV\x1F\x1CMISSING2\x1F/home/me\x1DS2='\\n stays'\nI2=${A}${A}\n   # indented comment\nQ2=\\n literal\nV=\"tab\\there \\\\ backslash \\\" quote\"\nO=${MISSING:-fallback}\x1DS2\x1FV\\n stays\x1CI2\x1FV\x1CQ2\x1FV\\n literal\x1CV\x1FVtab\there \\ backslash \" quote\x1CO\x1FVfallback\x1C\x1E1\x1DHOME\x1F\x1CEMPTY\x1Ffrom env\x1CMISSING2\x1Ffrom env\x1DL2=${A\nT2=  leading\nT=\"line1\\nline2\"\nB=${A}\nQ=$A\nO=${MISSING:-fallback}\nB=${A}\n\x1DL2\x1FV${A\x1CT2\x1FVleading\x1CT\x1FVline1\nline2\x1CB\x1FV\x1CQ\x1FV$A\x1CO\x1FVfallback\x1C\x1E0\x1DMISSING2\x1F\x1DR2=\"\\a\\b\\f\\v\\r\"\rH=\rX=\"multi\nline value\"\rI2=${A}${A}\rZ B=1\rV2=${A:-}\rA=1\r\x1DR2\x1FV\x07\x08\x0C\x0B\r\x1CH\x1FV\x1CX\x1FVmulti\nline value\x1CI2\x1FV\x1CV2\x1FV\x1CA\x1FV1\x1C\x1E1\x1D\x1D\xEF\xBB\xBFH2=${HOME:-nohome}\rN2='${A}'\r\x1DH2\x1FVnohome\x1CN2\x1FV\x1C\x1E1\x1DMISSING2\x1F\x1DK=value # trailing\nX=\"multi\nline value\"\n=novalue\nexport X2\nB=two words\nH=\nB=two words\nC = spaced\n#=x\n\x1DK\x1FVvalue\x1CX\x1FVmulti\nline value\x1CX2\x1FN\x1CB\x1FVtwo words\x1CH\x1FV\x1CC\x1FVspaced\x1C\x1E1\x1DHOME\x1F\x1Dexport X2\nL=\"a # not a comment\" # real\nQ=$A\nR=${A:b}\nX=\"multi\nline value\"\n\x1DX2\x1FN\x1CL\x1FVa # not a comment\x1CQ\x1FV$A\x1CR\x1FV${A:b}\x1CX\x1FVmulti\nline value\x1C\x1E1\x1DEMPTY\x1Ffrom env\x1DU='it\\'s'\n'quoted key'=qv\nA=1\nK2=a${\n\x1DU\x1FVit's\x1Cquoted key\x1FVqv\x1CA\x1FV1\x1CK2\x1FVa${\x1C\x1E1\x1DHOME\x1F/home/me\x1CEMPTY\x1F\x1CMISSING2\x1Fx y\x1DW2=${E_ENV:-${A}}\r\nQ2=\\n literal\r\n#=x\r\nL2=${A\r\nT=\"line1\\nline2\"\r\nJ=#hash\r\nQ=$A\r\n\r\n\x1DW2\x1FV${A}\x1CQ2\x1FV\\n literal\x1CL2\x1FV${A\x1CT\x1FVline1\nline2\x1CJ\x1FV#hash\x1CQ\x1FV$A\x1C\x1E1\x1DHOME\x1F\x1CA\x1F\x1CMISSING2\x1F/home/me\x1D'quoted key'=qv\rG2=${E_ENV}\rI2=${A}${A}\rexport =1\rY='multi\nline'\rF2=\xC3\xA9\xC3\xA8 unicode\rJ=#hash\x1Dquoted key\x1FVqv\x1CG2\x1FV\x1CI2\x1FV\x1CY\x1FVmulti\nline\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1CJ\x1FV#hash\x1C\x1E0\x1DA\x1F/home/me\x1CMISSING2\x1Fx y\x1DM\rN=${A}\rJ2=${A:-${B}}\rS=${}\rexport X2\rP2=a=b=c\rB=${A}\rexport X2\rO2 = \"q\" # c\r\x1DM\x1FN\x1CN\x1FV/home/me\x1CJ2\x1FV/home/me}\x1CS\x1FV\x1CX2\x1FN\x1CP2\x1FVa=b=c\x1CB\x1FV/home/me\x1CO2\x1FVq\x1C\x1E0\x1DEMPTY\x1F/home/me\x1CMISSING2\x1F/home/me\x1Dexport D=exported\rW2=${E_ENV:-${A}}\r\x1DD\x1FVexported\x1CW2\x1FV${A}\x1C\x1E"
}

fn dotenv_vectors_7() -> str {
    ret "1\x1DE_ENV\x1Fx y\x1CEMPTY\x1F/home/me\x1DN2='${A}'\rB=two words\rY='multi\nline'\rB2='unterminated\rD2=tab\tseparated\t# c\rA2=\"x\" junk\rN2='${A}'\x1DN2\x1FV\x1CB\x1FVtwo words\x1CY\x1FVmulti\nline\x1C\x1E0\x1DE_ENV\x1F\x1CHOME\x1F\x1CMISSING2\x1Ffrom env\x1DQ=$A\rexport =1\rN2='${A}'\rN=${A}\rV2=${A:-}\rexport\rU2=a\\\rB=two words\r\x1DQ\x1FV$A\x1CN2\x1FV\x1CN\x1FV\x1CV2\x1FV\x1Cexport\x1FN\x1CU2\x1FVa\\\x1CB\x1FVtwo words\x1C\x1E1\x1DHOME\x1F/home/me\x1CA\x1F/home/me\x1DR2=\"\\a\\b\\f\\v\\r\"\rexport D=exported\r# a comment\r\x1DR2\x1FV\x07\x08\x0C\x0B\r\x1CD\x1FVexported\x1C\x1E0\x1DE_ENV\x1Ffrom env\x1CA\x1Ffrom env\x1CEMPTY\x1F/home/me\x1Dexport =1\n\nexport\nR=${A:b}\n\x1Dexport\x1FN\x1CR\x1FV${A:b}\x1C\x1E1\x1DE_ENV\x1F/home/me\x1CHOME\x1Ffrom env\x1CA\x1Fx y\x1DX=\"multi\nline value\"\rD2=tab\tseparated\t# c\rR2=\"\\a\\b\\f\\v\\r\"\r   # indented comment\rH2=${HOME:-nohome}\rF=\"double quoted\"\r\x1DX\x1FVmulti\nline value\x1CD2\x1FVtab\tseparated\x1CR2\x1FV\x07\x08\x0C\x0B\r\x1CH2\x1FVfrom env\x1CF\x1FVdouble quoted\x1C\x1E0\x1DHOME\x1Ffrom env\x1CA\x1Fx y\x1DA2=\"x\" junk\nT=\"line1\\nline2\"\n   \n\x1DT\x1FVline1\nline2\x1C\x1E0\x1DHOME\x1F\x1CMISSING2\x1Fx y\x1DH=\r\x1DH\x1FV\x1C\x1E1\x1DA\x1F/home/me\x1DN2='${A}'\nT=\"line1\\nline2\"\n\nH2=${HOME:-nohome}\nZ B=1\n# a comment\nE2=trailing   \nexport   E=more\nV=\"tab\\there \\\\ backslash \\\" quote\"\x1DN2\x1FV/home/me\x1CT\x1FVline1\nline2\x1CH2\x1FVnohome\x1CE2\x1FVtrailing\x1CE\x1FVmore\x1CV\x1FVtab\there \\ backslash \" quote\x1C\x1E0\x1DE_ENV\x1Ffrom env\x1CEMPTY\x1F/home/me\x1CMISSING2\x1Fx y\x1D\xEF\xBB\xBFexport =1\rexport D=exported\rZ B=1\r\x1DD\x1FVexported\x1C\x1E1\x1DEMPTY\x1F\x1DU2=a\\\n=novalue\n#=x\nV=\"tab\\there \\\\ backslash \\\" quote\"\nP2=a=b=c\nQ=$A\nQ2=\\n literal\nR=${A:b}\n\x1DU2\x1FVa\\\x1CV\x1FVtab\there \\ backslash \" quote\x1CP2\x1FVa=b=c\x1CQ\x1FV$A\x1CQ2\x1FV\\n literal\x1CR\x1FV${A:b}\x1C\x1E1\x1DHOME\x1Fx y\x1DD2=tab\tseparated\t# c\nK=value # trailing\nS2='\\n stays'\nA=override later\x1DD2\x1FVtab\tseparated\x1CK\x1FVvalue\x1CS2\x1FV\\n stays\x1CA\x1FVoverride later\x1C\x1E0\x1DE_ENV\x1F\x1CHOME\x1F/home/me\x1CA\x1F/home/me\x1CMISSING2\x1F\x1DW2=${E_ENV:-${A}}\r\nJ=#hash\r\nG='single quoted'\r\nK=value # trailing\r\n'quoted key'=qv\r\n\x1DW2\x1FV}\x1CJ\x1FV#hash\x1CG\x1FVsingle quoted\x1CK\x1FVvalue\x1Cquoted key\x1FVqv\x1C\x1E"
}

fn dotenv_vectors_8() -> str {
    ret "0\x1DA\x1Fx y\x1CEMPTY\x1F/home/me\x1D\xEF\xBB\xBFU2=a\\\rR2=\"\\a\\b\\f\\v\\r\"\rM2=\"${A}\"\rN=${A}\r   # indented comment\rB=two words\rT2=  leading\rZ2=\"\"\r\x1DU2\x1FVa\\\x1CR2\x1FV\x07\x08\x0C\x0B\r\x1CM2\x1FVx y\x1CN\x1FVx y\x1CB\x1FVtwo words\x1CT2\x1FVleading\x1CZ2\x1FV\x1C\x1E0\x1DE_ENV\x1Fx y\x1CMISSING2\x1F\x1DG2=${E_ENV}\n\x1DG2\x1FVx y\x1C\x1E1\x1DHOME\x1F\x1DA2=\"x\" junk\r\rF2=\xC3\xA9\xC3\xA8 unicode\r\x1DF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1C\x1E1\x1DA\x1Ffrom env\x1DW=\"unknown \\q escape\"\nR=${A:b}\nY='multi\nline'\nP2=a=b=c\nexport D=exported\nU2=a\\\n'quoted key'=qv\nR2=\"\\a\\b\\f\\v\\r\"\nQ=$A\x1DW\x1FVunknown \\q escape\x1CR\x1FV${A:b}\x1CY\x1FVmulti\nline\x1CP2\x1FVa=b=c\x1CD\x1FVexported\x1CU2\x1FVa\\\x1Cquoted key\x1FVqv\x1CR2\x1FV\x07\x08\x0C\x0B\r\x1CQ\x1FV$A\x1C\x1E0\x1DE_ENV\x1F\x1CHOME\x1Ffrom env\x1CA\x1F\x1Dexport =1\n\x1D\x1E1\x1DMISSING2\x1Ffrom env\x1DL2=${A\r\nI= # only a comment\r\nA=1\r\nC2=\"unterminated\r\nF=\"double quoted\"\r\nR=${A:b}\r\nR2=\"\\a\\b\\f\\v\\r\"\r\nW2=${E_ENV:-${A}}\r\nP2=a=b=c\x1DL2\x1FV${A\x1CI\x1FV\x1CA\x1FV1\x1CR\x1FV${A:b}\x1CR2\x1FV\x07\x08\x0C\x0B\r\x1CW2\x1FV${A}\x1CP2\x1FVa=b=c\x1C\x1E1\x1DE_ENV\x1Fx y\x1CHOME\x1F/home/me\x1CEMPTY\x1Fx y\x1CMISSING2\x1Fx y\x1DQ=$A\rM\r\x1DQ\x1FV$A\x1CM\x1FN\x1C\x1E0\x1D\x1DU='it\\'s'\nexport X2\nexport D=exported\nU2=a\\\n\x1DU\x1FVit's\x1CX2\x1FN\x1CD\x1FVexported\x1CU2\x1FVa\\\x1C\x1E0\x1DHOME\x1F\x1CEMPTY\x1Fx y\x1CMISSING2\x1Fx y\x1DU2=a\\\nW2=${E_ENV:-${A}}\nW2=${E_ENV:-${A}}\n\x1DU2\x1FVa\\\x1CW2\x1FV${A}\x1C\x1E0\x1D\x1DD2=tab\tseparated\t# c\rI2=${A}${A}\rP=${A:-d}x${B}\r# a comment\r\x1DD2\x1FVtab\tseparated\x1CI2\x1FV\x1CP\x1FVdx\x1C\x1E0\x1DE_ENV\x1F/home/me\x1CHOME\x1F/home/me\x1CA\x1F\x1CEMPTY\x1F\x1D   # indented comment\nF2=\xC3\xA9\xC3\xA8 unicode\nP2=a=b=c\nexport X2\nexport X2\nT=\"line1\\nline2\"\nZ2=\"\"\nexport   E=more\n\x1DF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1CP2\x1FVa=b=c\x1CX2\x1FN\x1CT\x1FVline1\nline2\x1CZ2\x1FV\x1CE\x1FVmore\x1C\x1E0\x1DHOME\x1F/home/me\x1CA\x1Fx y\x1DL2=${A\nF2=\xC3\xA9\xC3\xA8 unicode\nA=1\nD2=tab\tseparated\t# c\nC = spaced\nZ2=\"\"\n\x1DL2\x1FV${A\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1CA\x1FV1\x1CD2\x1FVtab\tseparated\x1CC\x1FVspaced\x1CZ2\x1FV\x1C\x1E"
}

fn dotenv_vectors_9() -> str {
    ret "1\x1DA\x1F/home/me\x1DP=${A:-d}x${B}\n   \nK=value # trailing\n   # indented comment\nT2=  leading\nO=${MISSING:-fallback}\nV=\"tab\\there \\\\ backslash \\\" quote\"\n\x1DP\x1FV/home/mex\x1CK\x1FVvalue\x1CT2\x1FVleading\x1CO\x1FVfallback\x1CV\x1FVtab\there \\ backslash \" quote\x1C\x1E1\x1DE_ENV\x1Ffrom env\x1CA\x1F/home/me\x1D   \rZ B=1\rO2 = \"q\" # c\r\x1DO2\x1FVq\x1C\x1E0\x1DE_ENV\x1Fx y\x1CA\x1F/home/me\x1CEMPTY\x1F\x1CMISSING2\x1Fx y\x1D\xEF\xBB\xBFN=${A}\nexport =1\nF=\"double quoted\"\nL2=${A\nN=${A}\nG='single quoted'\nC = spaced\x1DN\x1FV/home/me\x1CF\x1FVdouble quoted\x1CL2\x1FV${A\x1CG\x1FVsingle quoted\x1CC\x1FVspaced\x1C\x1E1\x1DEMPTY\x1F/home/me\x1D#=x\r\n   # indented comment\r\n\x1D\x1E0\x1DHOME\x1F/home/me\x1CA\x1Ffrom env\x1CMISSING2\x1F/home/me\x1DD2=tab\tseparated\t# c\nI= # only a comment\nL2=${A\nJ=#hash\nK=value # trailing\n\x1DD2\x1FVtab\tseparated\x1CI\x1FV\x1CL2\x1FV${A\x1CJ\x1FV#hash\x1CK\x1FVvalue\x1C\x1E0\x1DE_ENV\x1Ffrom env\x1CHOME\x1Fx y\x1D# a comment\rO2 = \"q\" # c\rC2=\"unterminated\rU='it\\'s'\rM\rP=${A:-d}x${B}\rO2 = \"q\" # c\r\x1DO2\x1FVq\x1C\x1E0\x1DEMPTY\x1Fx y\x1DM\x1DM\x1FN\x1C\x1E1\x1DA\x1F\x1CEMPTY\x1F/home/me\x1CMISSING2\x1F\x1DV2=${A:-}\nI= # only a comment\nW=\"unknown \\q escape\"\nB=two words\nexport X2\n   \nO2 = \"q\" # c\nY='multi\nline'\n#=x\n\x1DV2\x1FV\x1CI\x1FV\x1CW\x1FVunknown \\q escape\x1CB\x1FVtwo words\x1CX2\x1FN\x1CO2\x1FVq\x1CY\x1FVmulti\nline\x1C\x1E0\x1DA\x1Ffrom env\x1CEMPTY\x1F\x1DL=\"a # not a comment\" # real\rB2='unterminated\rO2 = \"q\" # c\rW=\"unknown \\q escape\"\rQ=$A\rI2=${A}${A}\rM\rY='multi\nline'\rY2=''\r\x1DL\x1FVa # not a comment\x1Cline'\x1FN\x1CY2\x1FV\x1C\x1E0\x1DEMPTY\x1Fx y\x1DF=\"double quoted\"\rP2=a=b=c\rA=1\rB=${A}\rY='multi\nline'\r\x1DF\x1FVdouble quoted\x1CP2\x1FVa=b=c\x1CA\x1FV1\x1CB\x1FV1\x1CY\x1FVmulti\nline\x1C\x1E1\x1DE_ENV\x1F/home/me\x1D=novalue\r\nO=${MISSING:-fallback}\r\nW2=${E_ENV:-${A}}\r\nP=${A:-d}x${B}\r\nP2=a=b=c\r\nS=${}\r\nH2=${HOME:-nohome}\r\n#=x\r\nB2='unterminated\r\n\x1DO\x1FVfallback\x1CW2\x1FV/home/me}\x1CP\x1FVdx\x1CP2\x1FVa=b=c\x1CS\x1FV\x1CH2\x1FVnohome\x1C\x1E0\x1DE_ENV\x1F/home/me\x1CHOME\x1Fx y\x1DJ2=${A:-${B}}\nG2=${E_ENV}\nN=${A}\nG2=${E_ENV}\nC = spaced\nO2 = \"q\" # c\nB=${A}\n\x1DJ2\x1FV${B}\x1CG2\x1FV/home/me\x1CN\x1FV\x1CC\x1FVspaced\x1CO2\x1FVq\x1CB\x1FV\x1C\x1E"
}

fn dotenv_vectors_10() -> str {
    ret "0\x1DEMPTY\x1F/home/me\x1CMISSING2\x1Fx y\x1DR=${A:b}\nT2=  leading\n\x1DR\x1FV${A:b}\x1CT2\x1FVleading\x1C\x1E1\x1DE_ENV\x1F\x1DS=${}\nT2=  leading\n\x1DS\x1FV\x1CT2\x1FVleading\x1C\x1E1\x1DE_ENV\x1F/home/me\x1CA\x1F\x1CMISSING2\x1Ffrom env\x1DE2=trailing   \n\nE2=trailing   \n'quoted key'=qv\nA=1\nC = spaced\nF2=\xC3\xA9\xC3\xA8 unicode\n\x1DE2\x1FVtrailing\x1Cquoted key\x1FVqv\x1CA\x1FV1\x1CC\x1FVspaced\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1C\x1E0\x1D\x1DQ2=\\n literal\n   # indented comment\nD2=tab\tseparated\t# c\nR=${A:b}\nH=\nM2=\"${A}\"\nT2=  leading\nexport\n\x1DQ2\x1FV\\n literal\x1CD2\x1FVtab\tseparated\x1CR\x1FV${A:b}\x1CH\x1FV\x1CM2\x1FV\x1CT2\x1FVleading\x1Cexport\x1FN\x1C\x1E0\x1DHOME\x1F/home/me\x1CEMPTY\x1F\x1DV2=${A:-}\rH2=${HOME:-nohome}\rB=two words\rJ2=${A:-${B}}\rI= # only a comment\r\x1DV2\x1FV\x1CH2\x1FV/home/me\x1CB\x1FVtwo words\x1CJ2\x1FV${B}\x1CI\x1FV\x1C\x1E0\x1DHOME\x1Ffrom env\x1CEMPTY\x1F/home/me\x1CMISSING2\x1F\x1DH2=${HOME:-nohome}\rF=\"double quoted\"\r   # indented comment\rI2=${A}${A}\rR2=\"\\a\\b\\f\\v\\r\"\rA2=\"x\" junk\rG2=${E_ENV}\rF2=\xC3\xA9\xC3\xA8 unicode\rL2=${A\r\x1DH2\x1FVfrom env\x1CF\x1FVdouble quoted\x1CI2\x1FV\x1CR2\x1FV\x07\x08\x0C\x0B\r\x1CG2\x1FV\x1CF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1CL2\x1FV${A\x1C\x1E1\x1DE_ENV\x1F/home/me\x1CHOME\x1F/home/me\x1DJ2=${A:-${B}}\r\nA2=\"x\" junk\r\nY2=''\r\nN2='${A}'\r\n   # indented comment\r\nX=\"multi\nline value\"\r\nQ=$A\r\nK=value # trailing\r\n\x1DJ2\x1FV${B}\x1CY2\x1FV\x1CN2\x1FV\x1CX\x1FVmulti\nline value\x1CQ\x1FV$A\x1CK\x1FVvalue\x1C\x1E0\x1DHOME\x1F/home/me\x1CMISSING2\x1Fx y\x1DN2='${A}'\x1DN2\x1FV\x1C\x1E0\x1DE_ENV\x1Fx y\x1CA\x1Ffrom env\x1CEMPTY\x1Ffrom env\x1CMISSING2\x1Ffrom env\x1Dexport   E=more\nT=\"line1\\nline2\"\n\nE2=trailing   \nF=\"double quoted\"\nI= # only a comment\n\x1DE\x1FVmore\x1CT\x1FVline1\nline2\x1CE2\x1FVtrailing\x1CF\x1FVdouble quoted\x1CI\x1FV\x1C\x1E0\x1D\x1DW2=${E_ENV:-${A}}\nA2=\"x\" junk\nU2=a\\\nA=override later\nZ B=1\x1DW2\x1FV${A}\x1CU2\x1FVa\\\x1CA\x1FVoverride later\x1C\x1E1\x1DE_ENV\x1Fx y\x1CHOME\x1F/home/me\x1CMISSING2\x1F/home/me\x1D\xEF\xBB\xBF   # indented comment\rA2=\"x\" junk\r'quoted key'=qv\rB2='unterminated\rG='single quoted'\rP2=a=b=c\rG='single quoted'\rM\r\x1Dquoted key\x1FVqv\x1CP2\x1FVa=b=c\x1CG\x1FVsingle quoted\x1CM\x1FN\x1C\x1E0\x1DMISSING2\x1Fx y\x1D\xEF\xBB\xBFexport =1\rO2 = \"q\" # c\r   # indented comment\rO2 = \"q\" # c\rJ=#hash\rI= # only a comment\r\x1DO2\x1FVq\x1CJ\x1FV#hash\x1CI\x1FV\x1C\x1E"
}

fn dotenv_vectors_11() -> str {
    ret "0\x1DHOME\x1Fx y\x1CA\x1F\x1DF2=\xC3\xA9\xC3\xA8 unicode\nZ B=1\nN2='${A}'\nN=${A}\nY='multi\nline'\nP2=a=b=c\nH2=${HOME:-nohome}\n\x1DF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1CN2\x1FV\x1CN\x1FV\x1CY\x1FVmulti\nline\x1CP2\x1FVa=b=c\x1CH2\x1FVx y\x1C\x1E0\x1DHOME\x1Ffrom env\x1CEMPTY\x1F/home/me\x1DF=\"double quoted\"\rQ2=\\n literal\r\rO=${MISSING:-fallback}\r=novalue\rR=${A:b}\rexport D=exported\rT2=  leading\r\x1DF\x1FVdouble quoted\x1CQ2\x1FV\\n literal\x1CO\x1FVfallback\x1CR\x1FV${A:b}\x1CD\x1FVexported\x1CT2\x1FVleading\x1C\x1E1\x1DHOME\x1F\x1CMISSING2\x1F\x1DC = spaced\r\nG2=${E_ENV}\r\nL=\"a # not a comment\" # real\r\nU2=a\\\r\n\x1DC\x1FVspaced\x1CG2\x1FV\x1CL\x1FVa # not a comment\x1CU2\x1FVa\\\x1C\x1E0\x1DE_ENV\x1Ffrom env\x1CA\x1F\x1CEMPTY\x1F/home/me\x1DJ2=${A:-${B}}\nR=${A:b}\nI= # only a comment\n#=x\n   \n\x1DJ2\x1FV}\x1CR\x1FV${A:b}\x1CI\x1FV\x1C\x1E1\x1D\x1DQ2=\\n literal\nP2=a=b=c\nB2='unterminated\n# a comment\nexport =1\nO2 = \"q\" # c\nU2=a\\\nexport\nG='single quoted'\n\x1DQ2\x1FV\\n literal\x1CP2\x1FVa=b=c\x1C\x1E1\x1DA\x1F/home/me\x1CMISSING2\x1F/home/me\x1DY='multi\nline'\nexport   E=more\nJ=#hash\nA=override later\nZ2=\"\"\nZ2=\"\"\nO=${MISSING:-fallback}\nJ=#hash\n\x1DY\x1FVmulti\nline\x1CE\x1FVmore\x1CJ\x1FV#hash\x1CA\x1FVoverride later\x1CZ2\x1FV\x1CO\x1FVfallback\x1C\x1E1\x1DE_ENV\x1Fx y\x1CHOME\x1F\x1CEMPTY\x1Fx y\x1DU2=a\\\nC = spaced\nF=\"double quoted\"\nP=${A:-d}x${B}\nM2=\"${A}\"\n\x1DU2\x1FVa\\\x1CC\x1FVspaced\x1CF\x1FVdouble quoted\x1CP\x1FVdx\x1CM2\x1FV\x1C\x1E1\x1DMISSING2\x1F\x1DC = spaced\x1DC\x1FVspaced\x1C\x1E0\x1DE_ENV\x1Ffrom env\x1DT2=  leading\nA=1\nL=\"a # not a comment\" # real\n\x1DT2\x1FVleading\x1CA\x1FV1\x1CL\x1FVa # not a comment\x1C\x1E1\x1DHOME\x1F/home/me\x1CA\x1F\x1CMISSING2\x1Fx y\x1DH2=${HOME:-nohome}\nP2=a=b=c\nZ B=1\nM\nexport =1\nN=${A}\nC = spaced\n\x1DH2\x1FV/home/me\x1CP2\x1FVa=b=c\x1CM\x1FN\x1CN\x1FV\x1CC\x1FVspaced\x1C\x1E0\x1DE_ENV\x1Fx y\x1CA\x1Fx y\x1D   \n#=x\n\x1D\x1E0\x1DE_ENV\x1Fx y\x1CEMPTY\x1Fx y\x1CMISSING2\x1Fx y\x1DG2=${E_ENV}\nL2=${A\x1DG2\x1FVx y\x1CL2\x1FV${A\x1C\x1E"
}

fn dotenv_vectors_12() -> str {
    ret "0\x1DA\x1Ffrom env\x1DF2=\xC3\xA9\xC3\xA8 unicode\rR2=\"\\a\\b\\f\\v\\r\"\rZ2=\"\"\rW2=${E_ENV:-${A}}\rY2=''\rI2=${A}${A}\r\x1DF2\x1FV\xC3\xA9\xC3\xA8 unicode\x1CR2\x1FV\x07\x08\x0C\x0B\r\x1CZ2\x1FV\x1CW2\x1FV${A}\x1CY2\x1FV\x1CI2\x1FVfrom envfrom env\x1C\x1E0\x1DMISSING2\x1F\x1DF=\"double quoted\"\nV2=${A:-}\nM2=\"${A}\"\nW=\"unknown \\q escape\"\n   \nW2=${E_ENV:-${A}}\nW=\"unknown \\q escape\"\n\x1DF\x1FVdouble quoted\x1CV2\x1FV\x1CM2\x1FV\x1CW\x1FVunknown \\q escape\x1CW2\x1FV${A}\x1C\x1E1\x1DE_ENV\x1Fx y\x1CHOME\x1Ffrom env\x1CMISSING2\x1F\x1D\xEF\xBB\xBFK2=a${\nZ2=\"\"\nexport =1\nW=\"unknown \\q escape\"\n=novalue\nJ2=${A:-${B}}\nT2=  leading\nO2 = \"q\" # c\n\x1DK2\x1FVa${\x1CZ2\x1FV\x1CW\x1FVunknown \\q escape\x1CJ2\x1FV${B}\x1CT2\x1FVleading\x1CO2\x1FVq\x1C\x1E1\x1DE_ENV\x1F\x1CHOME\x1F/home/me\x1CA\x1F/home/me\x1CEMPTY\x1Fx y\x1DW=\"unknown \\q escape\"\nR=${A:b}\nR2=\"\\a\\b\\f\\v\\r\"\nK2=a${\nK=value # trailing\nO2 = \"q\" # c\nY2=''\nE2=trailing   \n'quoted key'=qv\n\x1DW\x1FVunknown \\q escape\x1CR\x1FV${A:b}\x1CR2\x1FV\x07\x08\x0C\x0B\r\x1CK2\x1FVa${\x1CK\x1FVvalue\x1CO2\x1FVq\x1CY2\x1FV\x1CE2\x1FVtrailing\x1Cquoted key\x1FVqv\x1C\x1E1\x1D\x1DU2=a\\\r\nU2=a\\\r\n=novalue\r\nJ=#hash\r\nQ2=\\n literal\r\n\r\nP2=a=b=c\r\nexport   E=more\r\n\x1DU2\x1FVa\\\x1CJ\x1FV#hash\x1CQ2\x1FV\\n literal\x1CP2\x1FVa=b=c\x1CE\x1FVmore\x1C\x1E1\x1DEMPTY\x1F/home/me\x1DX=\"multi\nline value\"\n\x1DX\x1FVmulti\nline value\x1C\x1E"
}

fn main(a: *mem.Arena, args: []str) -> err {
    if run(a, dotenv_vectors_0()) != 0u8 { os.exit(1i32) }
    if run(a, dotenv_vectors_1()) != 0u8 { os.exit(2i32) }
    if run(a, dotenv_vectors_2()) != 0u8 { os.exit(3i32) }
    if run(a, dotenv_vectors_3()) != 0u8 { os.exit(4i32) }
    if run(a, dotenv_vectors_4()) != 0u8 { os.exit(5i32) }
    if run(a, dotenv_vectors_5()) != 0u8 { os.exit(6i32) }
    if run(a, dotenv_vectors_6()) != 0u8 { os.exit(7i32) }
    if run(a, dotenv_vectors_7()) != 0u8 { os.exit(8i32) }
    if run(a, dotenv_vectors_8()) != 0u8 { os.exit(9i32) }
    if run(a, dotenv_vectors_9()) != 0u8 { os.exit(10i32) }
    if run(a, dotenv_vectors_10()) != 0u8 { os.exit(11i32) }
    if run(a, dotenv_vectors_11()) != 0u8 { os.exit(12i32) }
    if run(a, dotenv_vectors_12()) != 0u8 { os.exit(13i32) }
    // More bindings than room is TooMany, not a silent truncation.
    var tiny: [1]dotenv.Entry = zero
    let (_, _, too_many) = dotenv.parse(a, "A=1\nB=2\n", tiny[0usize..1usize])
    if too_many != dotenv.TooMany { os.exit(90i32) }
    // Invalid lines are counted.
    var room: [4]dotenv.Entry = zero
    let (count, skipped, count_error) = dotenv.parse(a, "A=1\n=bad\nB='open\nC=3\n", room[0usize..4usize])
    if count_error != ok || count != 2usize || skipped != 2usize { os.exit(91i32) }
    try io.print("fmt dotenv ok")
    ret ok
}
