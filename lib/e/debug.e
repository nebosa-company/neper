// Stack frames and symbols, allocation-free. There is no symbol data in a neper
// executable yet and no intrinsic to read the frame chain, so `backtrace` answers
// no frames and `symbolize` an address with empty names and line zero -- the shape
// the fence assigns to missing data, kept honest rather than guessed. When the
// compiler emits a frame walk and a symbol table, both fill in here and no caller
// changes.
type Frame = struct { address: usize, function: str, file: str, line: u32 }

fn backtrace(dst: []Frame) -> []Frame {
    ret dst[0usize..0usize]
}

fn symbolize(address: usize) -> Frame {
    ret Frame { address: address, function: "", file: "", line: 0u32 }
}


// --- Demangling (#1347). A neper symbol is `module.function` as the symbol
// table after the code spells it (D206): the module's dotted path, one dot,
// the function's declared name. A generic instance carries its template's
// name -- the arguments are not in the symbol -- and a protocol function the
// compiler supplied is `<snake type>_eq`, `_cmp` or `_hash`. `demangle_neper`
// splits at the last dot. `demangle` renders an Itanium C++ ABI name (`_Z`)
// the way c++filt does, for the subset below, and hands any other name back
// as it is.
//
// Itanium subset: nested names `N [K] ... E` and plain source names
// (`<len><chars>`), `St` for `std::`, constructors `C1/C2/C3` and destructors
// `D0/D1/D2`, the builtin types, `P` pointer, `R` reference, `O` rvalue
// reference, `K` const, `V` volatile and `z` for `...`.
// ponytail: no template arguments (`I...E`), substitutions (`S_`), function
// types, arrays or operator names; those answer `Unsupported`.

type Symbol = struct { module: str, function: str }
type Out = struct { dst: []u8, used: usize }
error Malformed
error Unsupported
error TooSmall

fn demangle_neper(symbol: str) -> (Symbol, err) {
    var dot = symbol.len
    var at = 0usize
    while at < symbol.len {
        if symbol[at] == 46u8 { dot = at }
        at += 1usize
    }
    if dot == 0usize || dot + 1usize >= symbol.len { ret (zero, Malformed) }
    ret (Symbol { module: symbol[..dot], function: symbol[dot + 1usize..] }, ok)
}

fn emit(o: *Out, text: str) -> err {
    if o.used + text.len > o.dst.len { ret TooSmall }
    var i = 0usize
    while i < text.len {
        o.dst[o.used + i] = text[i]
        i += 1usize
    }
    o.used += text.len
    ret ok
}

// `<len><chars>` at `at`; answers the name and the position after it.
fn source_name(s: str, at: usize) -> (str, usize, err) {
    var n = 0usize
    var p = at
    while p < s.len && s[p] >= 48u8 && s[p] <= 57u8 {
        n = n * 10usize + usize(s[p] - 48u8)
        p += 1usize
    }
    if p == at || n == 0usize || p + n > s.len { ret ("", at, Malformed) }
    ret (s[p..p + n], p + n, ok)
}

fn builtin(c: u8) -> str {
    if c == 118u8 { ret "void" }
    if c == 98u8 { ret "bool" }
    if c == 99u8 { ret "char" }
    if c == 97u8 { ret "signed char" }
    if c == 104u8 { ret "unsigned char" }
    if c == 115u8 { ret "short" }
    if c == 116u8 { ret "unsigned short" }
    if c == 105u8 { ret "int" }
    if c == 106u8 { ret "unsigned int" }
    if c == 108u8 { ret "long" }
    if c == 109u8 { ret "unsigned long" }
    if c == 120u8 { ret "long long" }
    if c == 121u8 { ret "unsigned long long" }
    if c == 102u8 { ret "float" }
    if c == 100u8 { ret "double" }
    if c == 101u8 { ret "long double" }
    if c == 119u8 { ret "wchar_t" }
    if c == 122u8 { ret "..." }
    ret ""
}

// A name: nested `N...E`, `St<source>` or a bare source name; the last
// component is answered too so a constructor can repeat it.
fn parse_name(s: str, at: usize, o: *Out) -> (usize, str, err) {
    var p = at
    var last = ""
    if p < s.len && s[p] == 78u8 {
        p += 1usize
        var qualifiers = 0usize
        while p < s.len && (s[p] == 75u8 || s[p] == 86u8) {
            qualifiers += 1usize
            p += 1usize
        }
        if qualifiers != 0usize { ret (p, "", Unsupported) }
        var first = true
        while p < s.len && s[p] != 69u8 {
            if !first {
                let separator_error = emit(o, "::")
                if separator_error != ok { ret (p, "", separator_error) }
            }
            first = false
            if s[p] == 83u8 && p + 1usize < s.len && s[p + 1usize] == 116u8 {
                let std_error = emit(o, "std")
                if std_error != ok { ret (p, "", std_error) }
                p += 2usize
                continue
            }
            if s[p] == 67u8 || s[p] == 68u8 {
                if p + 1usize >= s.len || last.len == 0usize { ret (p, "", Malformed) }
                if s[p] == 68u8 {
                    let tilde_error = emit(o, "~")
                    if tilde_error != ok { ret (p, "", tilde_error) }
                }
                let repeat_error = emit(o, last)
                if repeat_error != ok { ret (p, "", repeat_error) }
                p += 2usize
                continue
            }
            if s[p] == 73u8 || s[p] == 83u8 { ret (p, "", Unsupported) }
            let (name, after, name_error) = source_name(s, p)
            if name_error != ok { ret (p, "", name_error) }
            let name_emit = emit(o, name)
            if name_emit != ok { ret (p, "", name_emit) }
            last = name
            p = after
        }
        if p >= s.len { ret (p, "", Malformed) }
        ret (p + 1usize, last, ok)
    }
    if p + 1usize < s.len && s[p] == 83u8 && s[p + 1usize] == 116u8 {
        let std_error = emit(o, "std::")
        if std_error != ok { ret (p, "", std_error) }
        p += 2usize
    }
    let (name, after, name_error) = source_name(s, p)
    if name_error != ok { ret (p, "", name_error) }
    let name_emit = emit(o, name)
    if name_emit != ok { ret (p, "", name_emit) }
    ret (after, name, ok)
}

// One type at `at`, rendered; answers the position after it.
fn parse_type(s: str, at: usize, o: *Out) -> (usize, err) {
    if at >= s.len { ret (at, Malformed) }
    let c = s[at]
    if c == 80u8 || c == 82u8 || c == 79u8 || c == 75u8 || c == 86u8 {
        let (after, inner_error) = parse_type(s, at + 1usize, o)
        if inner_error != ok { ret (after, inner_error) }
        var suffix = "*"
        if c == 82u8 { suffix = "&" }
        if c == 79u8 { suffix = "&&" }
        if c == 75u8 { suffix = " const" }
        if c == 86u8 { suffix = " volatile" }
        let suffix_error = emit(o, suffix)
        ret (after, suffix_error)
    }
    if c == 78u8 || (c >= 48u8 && c <= 57u8) || (c == 83u8 && at + 1usize < s.len && s[at + 1usize] == 116u8) {
        let (after, _, name_error) = parse_name(s, at, o)
        ret (after, name_error)
    }
    let text = builtin(c)
    if text.len == 0usize { ret (at, Unsupported) }
    let text_error = emit(o, text)
    ret (at + 1usize, text_error)
}

fn demangle(symbol: str, dst: []u8) -> (str, err) {
    if symbol.len < 3usize || symbol[0usize] != 95u8 || symbol[1usize] != 90u8 {
        if symbol.len > dst.len { ret ("", TooSmall) }
        var o = Out { dst: dst, used: 0usize }
        let copy_error = emit(&o, symbol)
        if copy_error != ok { ret ("", copy_error) }
        ret (dst[..o.used], ok)
    }
    var o = Out { dst: dst, used: 0usize }
    let (after_name, _, name_error) = parse_name(symbol, 2usize, &o)
    if name_error != ok { ret ("", name_error) }
    var p = after_name
    if p >= symbol.len { ret (dst[..o.used], ok) }
    let open_error = emit(&o, "(")
    if open_error != ok { ret ("", open_error) }
    var count = 0usize
    while p < symbol.len {
        if symbol[p] == 118u8 && count == 0usize && p + 1usize == symbol.len {
            p += 1usize
            continue
        }
        if count != 0usize {
            let comma_error = emit(&o, ", ")
            if comma_error != ok { ret ("", comma_error) }
        }
        let (after, type_error) = parse_type(symbol, p, &o)
        if type_error != ok { ret ("", type_error) }
        p = after
        count += 1usize
    }
    let close_error = emit(&o, ")")
    if close_error != ok { ret ("", close_error) }
    ret (dst[..o.used], ok)
}
