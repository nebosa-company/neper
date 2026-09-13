from spec import LEAF_PER_GROUP

EXT, NAME = "e", "neper"

def emit(groups):
    o = ["use e.mem", "use e.io", ""]
    for i in range(groups * LEAF_PER_GROUP):
        o += [f"fn leaf_{i}(x: i64) -> i64 {{",
              f"    ret (x * 7 + 13 + {i}) % 1009",
              "}", ""]
    for g in range(groups):
        o += [f"fn group_{g}() -> i64 {{", "    var s = 0i64"]
        o += [f"    s += leaf_{g * LEAF_PER_GROUP + j}({j})" for j in range(LEAF_PER_GROUP)]
        o += ["    ret s", "}", ""]
    o += ["fn main(a: *mem.Arena, args: []str) -> err {", "    var t = 0i64"]
    o += [f"    t += group_{g}()" for g in range(groups)]
    o += ['    try io.printf["{}' + chr(92) + 'n"](t)', "    ret ok", "}"]
    return "\n".join(o) + "\n"
