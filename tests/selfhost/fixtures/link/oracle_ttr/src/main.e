// e.algo.stat.ttr against TTR: SMA, EMA, WMA, DEMA, RSI, MACD, BBands, ROC, OBV, ATR and TR.
// tests/oracle/ttr.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ttr`; the
// layout is at the top of scripts/r_oracle/groups/ttr.R.

use e.algo.stat.ttr as ttr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn series(a: *mem.Arena, x: []const f64, id: u8, n: usize, p2: f64, p3: f64, flag: bool, len: usize) -> []f64 {
    let px = x[6usize..6usize + len]
    let y = x[6usize + len..6usize + 2usize * len]
    let z = x[6usize + 2usize * len..6usize + 3usize * len]
    var out: []f64 = zero
    var e = ok
    if id == 0u8 { let (r, re) = ttr.sma(a, px, n)
        out = r
        e = re }
    if id == 1u8 { let (r, re) = ttr.ema(a, px, n, flag, 0.0f64)
        out = r
        e = re }
    if id == 2u8 { let (r, re) = ttr.wma(a, px, n)
        out = r
        e = re }
    if id == 3u8 { let (r, re) = ttr.dema(a, px, n, p2, flag)
        out = r
        e = re }
    if id == 4u8 { let (r, re) = ttr.rsi(a, px, n)
        out = r
        e = re }
    if id == 5u8 { let (r, re) = ttr.macd(a, px, n, usize(p2), usize(p3), flag, false)
        out = r
        e = re }
    if id == 6u8 { let (r, re) = ttr.macd(a, px, n, usize(p2), usize(p3), flag, true)
        out = r
        e = re }
    if id >= 7u8 && id <= 10u8 { let (r, re) = ttr.bbands(a, px, n, p2, id - 7u8)
        out = r
        e = re }
    if id == 11u8 { let (r, re) = ttr.roc(a, px, n, false)
        out = r
        e = re }
    if id == 12u8 { let (r, re) = ttr.roc(a, px, n, true)
        out = r
        e = re }
    if id == 13u8 { let (r, re) = ttr.obv(a, px, y)
        out = r
        e = re }
    if id == 14u8 { let (r, re) = ttr.atr(a, px, y, z, n)
        out = r
        e = re }
    if id == 15u8 { let (r, re) = ttr.tr(a, px, y, z)
        out = r
        e = re }
    if id == 16u8 { let (r, re) = ttr.zlema(a, px, n)
        out = r
        e = re }
    if id == 17u8 { let (r, re) = ttr.cci(a, px, y, z, n, 0.015f64)
        out = r
        e = re }
    if id >= 18u8 && id <= 20u8 { let (r, re) = ttr.stoch(a, px, y, z, n, usize(p2), usize(p3), id - 18u8)
        out = r
        e = re }
    if id >= 21u8 && id <= 24u8 { let (r, re) = ttr.adx(a, px, y, z, n, id - 21u8)
        out = r
        e = re }
    if id == 25u8 { let (r, re) = ttr.sar(a, px, y, p2, p3)
        out = r
        e = re }
    if id == 26u8 || id == 27u8 { let (r, re) = ttr.delt(a, px, n, id == 27u8)
        out = r
        e = re }
    if id >= 28u8 && id <= 30u8 {
        let (buf, be) = mem.alloc[f64](a, len)
        if be != ok { os.exit(6) }
        let np = ttr.period_return(a, px, z, id - 28u8, flag, buf)
        out = buf[0usize..np]
    }
    if e != ok { os.exit(6) }
    ret out
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let id = u8(x[0usize])
    let flag = x[4usize] != 0.0f64
    let len = usize(x[5usize])
    var idd = id
    // macd with percent flag: the flag column of the case says percent
    let v = series(a, x, idd, usize(x[1usize]), x[2usize], x[3usize], flag, len)
    let stat = u8(x[x.len - 1usize])
    if stat == 0u8 { ret f64(v.len) }
    var s = 0.0f64
    var w = 0.0f64
    var nas = 0.0f64
    var i = 0usize
    while i < v.len {
        if v[i] == v[i] {
            s += v[i]
            w += f64(i + 1usize) * v[i]
        } else {
            nas += 1.0f64
        }
        i += 1usize
    }
    if stat == 1u8 { ret s }
    if stat == 2u8 { ret w }
    if stat == 3u8 { ret v[0usize] }
    if stat == 4u8 { ret v[v.len - 1usize] }
    ret nas
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ttr.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
