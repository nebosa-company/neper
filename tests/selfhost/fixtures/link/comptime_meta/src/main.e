// Meta-only calls in an evaluated body (D1576, C066): a constant's function walks a
// struct's fields (their names and offsets) and an enum's members (their names and
// values), and asks for a type's name, size, alignment, array length and signedness
// -- the checker's answers, folded into the evaluation as a body folds them.
use e.mem
use e.meta

error Wrong

type Header = struct { tag: u8, length: u32, flags: u16 }
type Level = enum u8 { Low = 1, Mid = 5, High = 9 }

fn layout_sum() -> usize {
    var total = 0usize
    for f in meta.fields[Header]() {
        total += f.name.len * 100usize + f.offset
    }
    ret total
}

fn member_sum() -> usize {
    var total = 0usize
    for m in meta.members[Level]() {
        total += usize(m.value) * 10usize + m.name.len
    }
    ret total
}

fn questions() -> usize {
    let name = meta.type_name[Header]()
    var answer = name.len
    answer += mem.size_of[Header]() * 100usize
    answer += mem.align_of[Header]() * 10000usize
    answer += meta.array_len[[7]u8]() * 100000usize
    if meta.signed[i16]() && !meta.signed[u16]() { answer += 1000000usize }
    ret answer
}

const LAYOUT = layout_sum()
const MEMBERS = member_sum()
const QUESTIONS = questions()

fn main() -> err {
    if LAYOUT != 1412usize { ret Wrong }
    if MEMBERS != 160usize { ret Wrong }
    if QUESTIONS != 1741206usize { ret Wrong }
    var sized: [MEMBERS]u8 = zero
    if sized.len != 160usize { ret Wrong }
    ret ok
}
