from spec import LEAF_PER_GROUP

EXT, NAME = "rs", "rust"

def emit(groups):
    o = []
    for i in range(groups * LEAF_PER_GROUP):
        o.append(f"fn leaf_{i}(x: i64) -> i64 {{ (x * 7 + 13 + {i}) % 1009 }}")
    for g in range(groups):
        o.append(f"fn group_{g}() -> i64 {{")
        o.append("    let mut s: i64 = 0;")
        o += [f"    s += leaf_{g * LEAF_PER_GROUP + j}({j});" for j in range(LEAF_PER_GROUP)]
        o += ["    s", "}"]
    o.append("fn main() {")
    o.append("    let mut t: i64 = 0;")
    o += [f"    t += group_{g}();" for g in range(groups)]
    o += ['    println!("{}", t);', "}"]
    return "\n".join(o) + "\n"
