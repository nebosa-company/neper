// e.algo.stat.sm's sm.options defaults, sm.regression's sigma and model.y against sm. tests/oracle/sm_opt.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sm_opt`; the layout is at the top of scripts/r_oracle/groups/sm_opt.R.

use e.algo.stat.sm as sm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sm_opt.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        var ok_case = false
        var shown = 0.0f64
        if str.eq(c.name, "optt") {
            let (t, found) = sm.option_text(c.inputs[0usize])
            ok_case = found && oracle.agrees_text(t, c)
        } else if str.eq(c.name, "opts") {
            let (v, found) = sm.option_scalar(c.inputs[0usize])
            shown = v
            ok_case = found && oracle.agrees(v, c)
        } else if str.eq(c.name, "optv") {
            shown = sm.option_vector(c.inputs[0usize], usize(c.args[0usize]))
            ok_case = oracle.agrees(shown, c)
        } else if str.eq(c.name, "hsig") {
            let n = usize(c.args[0usize])
            let (sg, e) = sm.sm_sigma(a, c.args[1usize..1usize + n], c.args[1usize + n..1usize + 2usize * n])
            if e != ok { os.exit(4) }
            shown = sg
            ok_case = oracle.agrees(sg, c)
        } else if str.eq(c.name, "hmy") {
            let n = usize(c.args[0usize])
            shown = sm.model_fit(c.args[3usize..3usize + n], c.args[3usize + n..3usize + 2usize * n], usize(c.args[1usize]), c.args[2usize])
            ok_case = oracle.agrees(shown, c)
        }
        if !ok_case {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(c.name)
                if c.inputs.len > 0usize {
                    let _ = io.print(" ")
                    let _ = io.print(c.inputs[0usize])
                }
                let _ = io.print(" mismatch\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
