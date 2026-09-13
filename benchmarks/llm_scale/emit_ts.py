from spec import LEAF_PER_GROUP

EXT, NAME = "ts", "typescript"

def emit(groups):
    o = []
    for i in range(groups * LEAF_PER_GROUP):
        o.append(f"const leaf{i} = (x: number): number => (x * 7 + 13 + {i}) % 1009;")
    for g in range(groups):
        o.append(f"function group{g}(): number {{")
        o.append("  let s = 0;")
        o += [f"  s += leaf{g * LEAF_PER_GROUP + j}({j});" for j in range(LEAF_PER_GROUP)]
        o += ["  return s;", "}"]
    o.append("let t = 0;")
    o += [f"t += group{g}();" for g in range(groups)]
    o.append("console.log(t);")
    return "\n".join(o) + "\n"
