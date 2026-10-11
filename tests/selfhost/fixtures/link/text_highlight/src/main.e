// `e.text.highlight`: a snippet in each of the languages classified byte by byte and compared with the classes an
// independent implementation of the same rules (scripts/gen_highlight.py) gave, and the language picked by
// file extension. Written by scripts/gen_highlight.py. Every check has its own exit code.
use e.os
use e.mem
use e.str
use e.text.highlight as hl

fn check(i: usize, text: str, want: []const u8) -> bool {
    var got: [512]u8 = zero
    let n = hl.classify(i, text, got[0..])
    if n != want.len { ret false }
    var k = 0usize
    while k < n {
        if got[k] != want[k] { ret false }
        k += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    if hl.LANGUAGES != 32usize { os.exit(1) }
    let t0 = "fn main() -> err {\n    let n = 42usize // count\n    ret ok\n}\n"
    let w0: [61]u8 = [61]u8{ 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 3, 3, 0, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 0, 0, 0 }
    if !str.eq(hl.name(0usize), "Neper") { os.exit(2) }
    if !check(0usize, t0, w0[0..]) { os.exit(3) }
    let t1 = "# add\nclass Counter:\n    def add(self, word):\n        return \"x\" + str(1)\n"
    let w1: [74]u8 = [74]u8{ 4, 4, 4, 4, 4, 0, 1, 1, 1, 1, 1, 0, 5, 5, 5, 5, 5, 5, 5, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0 }
    if !str.eq(hl.name(1usize), "Python") { os.exit(4) }
    if !check(1usize, t1, w1[0..]) { os.exit(5) }
    let t2 = "/* sum */\nint sum(int n) {\n    return n + 10; // done\n}\n"
    let w2: [56]u8 = [56]u8{ 4, 4, 4, 4, 4, 4, 4, 4, 4, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 3, 3, 0, 0, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0 }
    if !str.eq(hl.name(2usize), "C") { os.exit(6) }
    if !check(2usize, t2, w2[0..]) { os.exit(7) }
    let t3 = "class Box {\npublic:\n    int size() const { return 3; }\n};\n"
    let w3: [58]u8 = [58]u8{ 1, 1, 1, 1, 1, 0, 5, 5, 5, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 3, 0, 0, 0, 0, 0, 0, 0 }
    if !str.eq(hl.name(3usize), "C++") { os.exit(8) }
    if !check(3usize, t3, w3[0..]) { os.exit(9) }
    let t4 = "public class App {\n    // greeter\n    static void main(String[] args) { int i = 0; }\n}\n"
    let w4: [87]u8 = [87]u8{ 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 5, 5, 5, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 5, 5, 5, 5, 5, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0 }
    if !str.eq(hl.name(4usize), "Java") { os.exit(10) }
    if !check(4usize, t4, w4[0..]) { os.exit(11) }
    let t5 = "using System;\nnamespace Demo {\n    public class P { string s = \"hi\"; }\n}\n"
    let w5: [73]u8 = [73]u8{ 1, 1, 1, 1, 1, 0, 5, 5, 5, 5, 5, 5, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 5, 5, 5, 5, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 5, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0 }
    if !str.eq(hl.name(5usize), "C#") { os.exit(12) }
    if !check(5usize, t5, w5[0..]) { os.exit(13) }
    let t6 = "async function show(id) {\n  const r = await fetch(`/u/${id}`) // get\n  return r\n}\n"
    let w6: [82]u8 = [82]u8{ 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 4, 4, 4, 4, 4, 4, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0 }
    if !str.eq(hl.name(6usize), "JavaScript") { os.exit(14) }
    if !check(6usize, t6, w6[0..]) { os.exit(15) }
    let t7 = "interface User { name: string }\nlet u: User = { name: \"a\" }\n"
    let w7: [60]u8 = [60]u8{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 5, 5, 5, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 5, 5, 5, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0 }
    if !str.eq(hl.name(7usize), "TypeScript") { os.exit(16) }
    if !check(7usize, t7, w7[0..]) { os.exit(17) }
    let t8 = "package main\nfunc main() {\n\tx := 3 // three\n}\n"
    let w8: [46]u8 = [46]u8{ 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0 }
    if !str.eq(hl.name(8usize), "Go") { os.exit(18) }
    if !check(8usize, t8, w8[0..]) { os.exit(19) }
    let t9 = "Public Class Form1\n    Dim x As Integer = 3 ' three\nEnd Class\n"
    let w9: [62]u8 = [62]u8{ 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 5, 5, 5, 5, 5, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 3, 0, 4, 4, 4, 4, 4, 4, 4, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0 }
    if !str.eq(hl.name(9usize), "Visual Basic") { os.exit(20) }
    if !check(9usize, t9, w9[0..]) { os.exit(21) }
    let t10 = "program Hello;\nbegin\n  writeln('hi'); { greet }\nend.\n"
    let w10: [53]u8 = [53]u8{ 1, 1, 1, 1, 1, 1, 1, 0, 5, 5, 5, 5, 5, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 0, 0, 0, 4, 4, 4, 4, 4, 4, 4, 4, 4, 0, 1, 1, 1, 0, 0 }
    if !str.eq(hl.name(10usize), "Pascal") { os.exit(22) }
    if !check(10usize, t10, w10[0..]) { os.exit(23) }
    let t11 = "-- best\nSELECT name FROM orders WHERE total > 100 LIMIT 10;\n"
    let w11: [60]u8 = [60]u8{ 4, 4, 4, 4, 4, 4, 4, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3, 0, 1, 1, 1, 1, 1, 0, 3, 3, 0, 0 }
    if !str.eq(hl.name(11usize), "SQL") { os.exit(24) }
    if !check(11usize, t11, w11[0..]) { os.exit(25) }
    let t12 = "program hi\n  integer :: n = 3 ! three\n  print *, n\nend program\n"
    let w12: [63]u8 = [63]u8{ 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0 }
    if !str.eq(hl.name(12usize), "Fortran") { os.exit(26) }
    if !check(12usize, t12, w12[0..]) { os.exit(27) }
    let t13 = "use strict;\nmy $x = 3; # three\nprint \"hi\\n\";\n"
    let w13: [45]u8 = [45]u8{ 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 3, 0, 0, 4, 4, 4, 4, 4, 4, 4, 0, 1, 1, 1, 1, 1, 0, 2, 2, 2, 2, 2, 2, 0, 0 }
    if !str.eq(hl.name(13usize), "Perl") { os.exit(28) }
    if !check(13usize, t13, w13[0..]) { os.exit(29) }
    let t14 = "f <- function(x) { if (x > 1) TRUE else FALSE } # test\n"
    let w14: [55]u8 = [55]u8{ 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 3, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 4, 4, 4, 4, 4, 4, 0 }
    if !str.eq(hl.name(14usize), "R") { os.exit(30) }
    if !check(14usize, t14, w14[0..]) { os.exit(31) }
    let t15 = "<?php\n// say\nfunction hi($n) { return \"hi \" . $n; }\n"
    let w15: [52]u8 = [52]u8{ 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4, 4, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 2, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    if !str.eq(hl.name(15usize), "PHP") { os.exit(32) }
    if !check(15usize, t15, w15[0..]) { os.exit(33) }
    let t16 = "fn main() {\n    let mut x = 5; // five\n    println!(\"{}\", x);\n}\n"
    let w16: [64]u8 = [64]u8{ 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 3, 0, 0, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0 }
    if !str.eq(hl.name(16usize), "Rust") { os.exit(34) }
    if !check(16usize, t16, w16[0..]) { os.exit(35) }
    let t17 = "% sum\nfunction y = f(x)\n  y = x + 1;\nend\n"
    let w17: [41]u8 = [41]u8{ 4, 4, 4, 4, 4, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 1, 1, 1, 0 }
    if !str.eq(hl.name(17usize), "MATLAB") { os.exit(36) }
    if !check(17usize, t17, w17[0..]) { os.exit(37) }
    let t18 = "procedure Hello is\nbegin\n  Put_Line (\"hi\"); -- say\nend Hello;\n"
    let w18: [62]u8 = [62]u8{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 5, 5, 5, 5, 5, 0, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 5, 5, 5, 5, 5, 5, 5, 5, 0, 0, 2, 2, 2, 2, 0, 0, 0, 4, 4, 4, 4, 4, 4, 0, 1, 1, 1, 0, 5, 5, 5, 5, 5, 0, 0 }
    if !str.eq(hl.name(18usize), "Ada") { os.exit(38) }
    if !check(18usize, t18, w18[0..]) { os.exit(39) }
    let t19 = "fun main() {\n    val x = 3 // three\n    println(\"hi\")\n}\n"
    let w19: [56]u8 = [56]u8{ 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 3, 0, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 0, 0, 0, 0 }
    if !str.eq(hl.name(19usize), "Kotlin") { os.exit(40) }
    if !check(19usize, t19, w19[0..]) { os.exit(41) }
    let t20 = "let greeting = \"hi\"\nfunc say() { print(greeting) } // go\n"
    let w20: [57]u8 = [57]u8{ 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4, 0 }
    if !str.eq(hl.name(20usize), "Swift") { os.exit(42) }
    if !check(20usize, t20, w20[0..]) { os.exit(43) }
    let t21 = "IDENTIFICATION DIVISION.\nPROGRAM-ID. HELLO.\nPROCEDURE DIVISION.\n    DISPLAY \"HI\".\n    STOP RUN.\n"
    let w21: [96]u8 = [96]u8{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 5, 5, 5, 5, 5, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 5, 5, 5, 0, 0 }
    if !str.eq(hl.name(21usize), "COBOL") { os.exit(44) }
    if !check(21usize, t21, w21[0..]) { os.exit(45) }
    let t22 = "; square\n(defun sq (x) (* x x))\n(print \"hi\")\n"
    let w22: [45]u8 = [45]u8{ 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 0, 0 }
    if !str.eq(hl.name(22usize), "Lisp") { os.exit(46) }
    if !check(22usize, t22, w22[0..]) { os.exit(47) }
    let t23 = "% parent\nparent(tom, bob).\nX is 3 + 4.\n"
    let w23: [39]u8 = [39]u8{ 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 1, 1, 0, 3, 0, 0, 0, 3, 3, 0 }
    if !str.eq(hl.name(23usize), "Prolog") { os.exit(48) }
    if !check(23usize, t23, w23[0..]) { os.exit(49) }
    let t24 = "void main() {\n  var x = 3; // three\n  print(\"hi\");\n}\n"
    let w24: [53]u8 = [53]u8{ 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 3, 0, 0, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 0, 0, 0, 0, 0 }
    if !str.eq(hl.name(24usize), "Dart") { os.exit(50) }
    if !check(24usize, t24, w24[0..]) { os.exit(51) }
    let t25 = "local function f(x)\n  return x + 1 -- inc\nend\n"
    let w25: [46]u8 = [46]u8{ 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 3, 0, 4, 4, 4, 4, 4, 4, 0, 1, 1, 1, 0 }
    if !str.eq(hl.name(25usize), "Lua") { os.exit(52) }
    if !check(25usize, t25, w25[0..]) { os.exit(53) }
    let t26 = "@interface Foo\n- (int)n; // count\n@end\n"
    let w26: [39]u8 = [39]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 5, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0 }
    if !str.eq(hl.name(26usize), "Objective-C") { os.exit(54) }
    if !check(26usize, t26, w26[0..]) { os.exit(55) }
    let t27 = "-- double\ndouble :: Int -> Int\ndouble x = x * 2\n"
    let w27: [48]u8 = [48]u8{ 4, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 5, 0, 0, 0, 0, 5, 5, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0 }
    if !str.eq(hl.name(27usize), "Haskell") { os.exit(56) }
    if !check(27usize, t27, w27[0..]) { os.exit(57) }
    let t28 = "# add\nfunction f(x)\n    return x + 1\nend\n"
    let w28: [41]u8 = [41]u8{ 4, 4, 4, 4, 4, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 3, 0, 1, 1, 1, 0 }
    if !str.eq(hl.name(28usize), "Julia") { os.exit(58) }
    if !check(28usize, t28, w28[0..]) { os.exit(59) }
    let t29 = "# greet\ndef hi(n)\n  puts \"hi #{n}\"\nend\n"
    let w29: [39]u8 = [39]u8{ 4, 4, 4, 4, 4, 4, 4, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 1, 1, 1, 0 }
    if !str.eq(hl.name(29usize), "Ruby") { os.exit(60) }
    if !check(29usize, t29, w29[0..]) { os.exit(61) }
    let t30 = "object Main {\n  val x = 3 // three\n  def main(args: Array[String]) = println(\"hi\")\n}\n"
    let w30: [85]u8 = [85]u8{ 1, 1, 1, 1, 1, 1, 0, 5, 5, 5, 5, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 3, 0, 4, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5, 5, 5, 5, 0, 5, 5, 5, 5, 5, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 0, 0, 0, 0 }
    if !str.eq(hl.name(30usize), "Scala") { os.exit(62) }
    if !check(30usize, t30, w30[0..]) { os.exit(63) }
    let t31 = "#!/bin/sh\nfor f in *.txt; do echo \"$f\"; done # list\n"
    let w31: [52]u8 = [52]u8{ 4, 4, 4, 4, 4, 4, 4, 4, 4, 0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 2, 2, 2, 2, 0, 0, 1, 1, 1, 1, 0, 4, 4, 4, 4, 4, 4, 0 }
    if !str.eq(hl.name(31usize), "Bash") { os.exit(64) }
    if !check(31usize, t31, w31[0..]) { os.exit(65) }
    // By extension: a name's last dot, in lower case.
    let (p66, f66) = hl.language_for("main.py")
    if !f66 || p66 != 1usize { os.exit(66) }
    let (p67, f67) = hl.language_for("lib.RS")
    if !f67 || p67 != 16usize { os.exit(67) }
    let (p68, f68) = hl.language_for("app.js")
    if !f68 || p68 != 6usize { os.exit(68) }
    let (p69, f69) = hl.language_for("q.sql")
    if !f69 || p69 != 11usize { os.exit(69) }
    let (p70, f70) = hl.language_for("x.cpp")
    if !f70 || p70 != 3usize { os.exit(70) }
    let (p71, f71) = hl.language_for("hello.ne")
    if !f71 || p71 != 0usize { os.exit(71) }
    let (p72, f72) = hl.language_for("a.b.go")
    if !f72 || p72 != 8usize { os.exit(72) }
    let (p73, f73) = hl.language_for("run.sh")
    if !f73 || p73 != 31usize { os.exit(73) }
    let (nx, nf) = hl.language_for("README")
    if nf { os.exit(74) }
    let (ux, uf) = hl.language_for("data.unknownext")
    if uf { os.exit(75) }
    ret ok
}
