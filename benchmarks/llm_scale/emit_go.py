from spec import LEAF_PER_GROUP

EXT, NAME = "go", "go"

def emit(groups):
    o = ["package main", "", 'import "fmt"', ""]
    for i in range(groups * LEAF_PER_GROUP):
        o.append(f"func leaf{i}(x int64) int64 {{ return (x*7 + 13 + {i}) % 1009 }}")
    for g in range(groups):
        o.append(f"func group{g}() int64 {{")
        o.append("\tvar s int64")
        o += [f"\ts += leaf{g * LEAF_PER_GROUP + j}({j})" for j in range(LEAF_PER_GROUP)]
        o += ["\treturn s", "}"]
    o.append("func main() {")
    o.append("\tvar t int64")
    o += [f"\tt += group{g}()" for g in range(groups)]
    o += ["\tfmt.Println(t)", "}"]
    return "\n".join(o) + "\n"
