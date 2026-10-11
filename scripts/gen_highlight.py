#!/usr/bin/env python3
"""Write lib/e/text/highlight.e (the rule tables) and tests/selfhost/fixtures/link/text_highlight/src/main.e.

The tables are the data below: for each language a name, the file extensions that pick it, its line comment
markers, its block comment pair, its string quote characters, whether its keywords ignore case, and its keywords.
The module classifies every byte of a text as plain (0), keyword (1), string (2), number (3), comment (4) or type
(5, a capitalised name that is not a keyword); the fixture's expected classes come from `classify` below, an
independent implementation of the same rules in Python, run over a snippet per language.

The language list is the leading languages of the TIOBE index as the author remembered it for October 2025 (the
item records the month it used; refresh the list from tiobe.com when rebuilding), plus Neper.
"""
from pathlib import Path

# name, extensions, line comments, block (open, close) or None, quotes, caseless, keywords
LANGS = [
    ("Neper", ["ne", "e"], ["//"], None, '"', False,
     "fn type const var let ret if else while for in break continue use error struct enum union try match true false zero ok"),
    ("Python", ["py", "pyw"], ["#"], None, "\"'", False,
     "False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield self"),
    ("C", ["c", "h"], ["//"], ("/*", "*/"), "\"'", False,
     "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while NULL"),
    ("C++", ["cpp", "cc", "cxx", "hpp", "hh"], ["//"], ("/*", "*/"), "\"'", False,
     "alignas alignof and asm auto bool break case catch char class const constexpr continue decltype default delete do double else enum explicit export extern false float for friend goto if inline int long mutable namespace new noexcept not nullptr operator or private protected public register return short signed sizeof static struct switch template this throw true try typedef typeid typename union unsigned using virtual void volatile while"),
    ("Java", ["java"], ["//"], ("/*", "*/"), "\"'", False,
     "abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false null var record"),
    ("C#", ["cs"], ["//"], ("/*", "*/"), "\"'", False,
     "abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using var virtual void volatile while async await record"),
    ("JavaScript", ["js", "mjs", "cjs", "jsx"], ["//"], ("/*", "*/"), "\"'`", False,
     "async await break case catch class const continue debugger default delete do else export extends false finally for function if import in instanceof let new null of return static super switch this throw true try typeof undefined var void while with yield"),
    ("TypeScript", ["ts", "tsx"], ["//"], ("/*", "*/"), "\"'`", False,
     "abstract any as async await boolean break case catch class const constructor continue declare default delete do else enum export extends false finally for from function get if implements import in instanceof interface is keyof let module namespace never new null number of private protected public readonly return set static string super switch this throw true try type typeof undefined unknown var void while yield"),
    ("Go", ["go"], ["//"], ("/*", "*/"), "\"'`", False,
     "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil iota"),
    ("Visual Basic", ["vb", "bas"], ["'"], None, '"', True,
     "AddHandler AddressOf And As Boolean ByRef Byte ByVal Call Case Catch Class Const Continue Date Declare Default Dim Do Double Each Else ElseIf End Enum Error Event Exit False Finally For Friend Function Get GoTo If Implements Imports In Inherits Integer Interface Is Let Long Loop Me Module Mod MustInherit Namespace New Next Not Nothing Object Of On Option Optional Or Overrides Private Property Protected Public RaiseEvent ReadOnly ReDim Resume Return Select Set Shared Short Single Static Step Stop String Structure Sub Then Throw To True Try TypeOf Until Using Variant When While With WriteOnly"),
    ("Pascal", ["pas", "pp", "dpr"], ["//"], ("{", "}"), "'", True,
     "and array as asm begin case class const constructor destructor div do downto else end except exports false file finalization finally for function goto if implementation in inherited initialization inline interface is label mod nil not object of on or out packed private procedure program property protected public raise record repeat set shl shr string then threadvar to true try type unit until uses var while with xor"),
    ("SQL", ["sql"], ["--"], ("/*", "*/"), "'\"", True,
     "add all alter and any as asc between by case check column constraint create cross database default delete desc distinct drop else end exists foreign from full group having in index inner insert into is join key left like limit not null on or order outer primary references right select set table then top union unique update values view when where with"),
    ("Fortran", ["f90", "f95", "f03", "for", "f"], ["!"], None, "\"'", True,
     "allocatable allocate call case character close common complex contains continue cycle data deallocate dimension do double else elseif end endif enddo exit format function goto if implicit in integer intent interface logical module nullify only open out parameter pointer precision print private program public read real recursive result return save select stop subroutine target then type use where while write"),
    ("Perl", ["pl", "pm"], ["#"], None, "\"'`", False,
     "and bless chomp chop close continue defined delete die do each else elsif eval exists exit for foreach format goto grep if keys last local map my next no not open or our package pop print push redo ref require return reverse scalar shift sort splice split sub tie undef unless unshift until use values wantarray warn while write xor"),
    ("R", ["r"], ["#"], None, "\"'`", False,
     "if else repeat while function for next break TRUE FALSE NULL Inf NaN NA in library require return"),
    ("PHP", ["php"], ["//", "#"], ("/*", "*/"), "\"'", False,
     "abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends false final finally fn for foreach function global goto if implements include instanceof interface isset list match namespace new null or print private protected public require return static switch throw trait true try unset use var while xor yield"),
    ("Rust", ["rs"], ["//"], ("/*", "*/"), '"', False,
     "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while"),
    ("MATLAB", ["m"], ["%"], ("%{", "%}"), "\"'", False,
     "break case catch classdef continue else elseif end for function global if otherwise parfor persistent return switch try while true false"),
    ("Ada", ["adb", "ads"], ["--"], None, '"', True,
     "abort abs abstract accept access all and array at begin body case constant declare delay delta digits do else elsif end entry exception exit for function generic goto if in interface is limited loop mod new not null of or others out overriding package pragma private procedure protected raise range record rem renames requeue return reverse select separate some subtype synchronized tagged task terminate then type until use when while with xor"),
    ("Kotlin", ["kt", "kts"], ["//"], ("/*", "*/"), "\"'", False,
     "abstract as break by catch class companion const constructor continue data do else enum false final finally for fun if import in inline interface internal is lateinit null object open operator override package private protected public return sealed super this throw true try typealias val var when where while"),
    ("Swift", ["swift"], ["//"], ("/*", "*/"), '"', False,
     "actor any as associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate for func guard if import in init inout internal is let nil open operator private protocol public repeat rethrows return self Self static struct subscript super switch throw throws true try typealias var where while"),
    ("COBOL", ["cob", "cbl"], ["*>"], None, "\"'", True,
     "ACCEPT ADD AFTER ALL AND BEFORE CALL CLOSE COMPUTE CONTINUE DATA DISPLAY DIVIDE DIVISION ELSE END-IF END-PERFORM EVALUATE EXIT FD FILE GIVING GO GOBACK IDENTIFICATION IF IN INTO MOVE MULTIPLY NOT OPEN OR PERFORM PIC PICTURE PROCEDURE PROGRAM-ID READ RETURN SECTION SELECT SET STOP STRING SUBTRACT THEN TO UNTIL USING VALUE VARYING WHEN WORKING-STORAGE WRITE ZERO"),
    ("Lisp", ["lisp", "lsp", "cl", "scm", "el"], [";"], ("#|", "|#"), '"', True,
     "and cond defmacro defun defvar defparameter defstruct do dolist dotimes else flet if lambda let let* loop nil not or progn quote return setf setq t unless when"),
    ("Prolog", ["pro", "prolog"], ["%"], ("/*", "*/"), "\"'", False,
     "is mod rem not dynamic discontiguous module use_module true fail halt assert asserta assertz retract findall bagof setof"),
    ("Dart", ["dart"], ["//"], ("/*", "*/"), "\"'", False,
     "abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for Function get hide if implements import in interface is late library mixin new null on operator part required rethrow return set show static super switch sync this throw true try typedef var void while with yield"),
    ("Lua", ["lua"], ["--"], ("--[[", "]]"), "\"'", False,
     "and break do else elseif end false for function goto if in local nil not or repeat return then true until while"),
    ("Objective-C", ["mm"], ["//"], ("/*", "*/"), "\"'", False,
     "auto break case char const continue default do double else enum extern float for goto if id inline int long nil NO return self short signed sizeof static struct super switch typedef union unsigned void volatile while YES @interface @implementation @end @property @protocol"),
    ("Haskell", ["hs", "lhs"], ["--"], ("{-", "-}"), "\"'", False,
     "case class data default deriving do else forall foreign if import in infix infixl infixr instance let module newtype of qualified then type where True False"),
    ("Julia", ["jl"], ["#"], ("#=", "=#"), "\"'`", False,
     "abstract baremodule begin break catch const continue do else elseif end export false finally for function global if import in let local macro module mutable nothing primitive quote return struct true try using where while"),
    ("Ruby", ["rb", "rake"], ["#"], ("=begin", "=end"), "\"'`", False,
     "BEGIN END alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield"),
    ("Scala", ["scala", "sc"], ["//"], ("/*", "*/"), "\"'", False,
     "abstract case catch class def do else extends false final finally for forSome if implicit import lazy match new null object override package private protected return sealed super this throw trait true try type val var while with yield given using enum"),
    ("Bash", ["sh", "bash", "zsh"], ["#"], None, "\"'`", False,
     "case do done elif else esac exit export fi for function if in local read return select set shift then time until unset while echo cd source alias"),
]

CLASS_NAMES = {0: "plain", 1: "keyword", 2: "string", 3: "number", 4: "comment", 5: "type"}


def is_alpha(c):
    return c.isalpha() or c == "_" or ord(c) >= 128


def classify(lang, text):
    name, exts, lines, block, quotes, caseless, kws = lang
    words = set((w.lower() if caseless else w) for w in kws.split())
    out = [0] * len(text)
    i = 0
    n = len(text)
    while i < n:
        if block and text.startswith(block[0], i):
            end = text.find(block[1], i + len(block[0]))
            end = n if end < 0 else end + len(block[1])
            for k in range(i, end):
                out[k] = 4
            i = end
            continue
        hit = None
        for m in lines:
            if text.startswith(m, i):
                hit = m
        if hit:
            end = text.find("\n", i)
            end = n if end < 0 else end
            for k in range(i, end):
                out[k] = 4
            i = end
            continue
        c = text[i]
        if c in quotes:
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                if text[j] == "\\" and j + 1 < n:
                    j += 1
                j += 1
            if j < n and text[j] == c:
                j += 1
            for k in range(i, j):
                out[k] = 2
            i = j
            continue
        if c.isdigit():
            j = i
            while j < n and (text[j].isdigit() or text[j] == "." or is_alpha(text[j])):
                j += 1
            for k in range(i, j):
                out[k] = 3
            i = j
            continue
        if is_alpha(c):
            j = i
            while j < n and (is_alpha(text[j]) or text[j].isdigit() or text[j] == "-" and caseless and name == "COBOL"):
                j += 1
            word = text[i:j]
            key = word.lower() if caseless else word
            klass = 0
            if key in words:
                klass = 1
            elif word[0].isupper():
                klass = 5
            for k in range(i, j):
                out[k] = klass
            i = j
            continue
        i += 1
    return out


SNIPPETS = {
    "Neper": 'fn main() -> err {\n    let n = 42usize // count\n    ret ok\n}\n',
    "Python": '# add\nclass Counter:\n    def add(self, word):\n        return "x" + str(1)\n',
    "C": '/* sum */\nint sum(int n) {\n    return n + 10; // done\n}\n',
    "C++": 'class Box {\npublic:\n    int size() const { return 3; }\n};\n',
    "Java": 'public class App {\n    // greeter\n    static void main(String[] args) { int i = 0; }\n}\n',
    "C#": 'using System;\nnamespace Demo {\n    public class P { string s = "hi"; }\n}\n',
    "JavaScript": 'async function show(id) {\n  const r = await fetch(`/u/${id}`) // get\n  return r\n}\n',
    "TypeScript": 'interface User { name: string }\nlet u: User = { name: "a" }\n',
    "Go": 'package main\nfunc main() {\n\tx := 3 // three\n}\n',
    "Visual Basic": "Public Class Form1\n    Dim x As Integer = 3 ' three\nEnd Class\n",
    "Pascal": "program Hello;\nbegin\n  writeln('hi'); { greet }\nend.\n",
    "SQL": "-- best\nSELECT name FROM orders WHERE total > 100 LIMIT 10;\n",
    "Fortran": "program hi\n  integer :: n = 3 ! three\n  print *, n\nend program\n",
    "Perl": 'use strict;\nmy $x = 3; # three\nprint "hi\\n";\n',
    "R": "f <- function(x) { if (x > 1) TRUE else FALSE } # test\n",
    "PHP": '<?php\n// say\nfunction hi($n) { return "hi " . $n; }\n',
    "Rust": 'fn main() {\n    let mut x = 5; // five\n    println!("{}", x);\n}\n',
    "MATLAB": "% sum\nfunction y = f(x)\n  y = x + 1;\nend\n",
    "Ada": 'procedure Hello is\nbegin\n  Put_Line ("hi"); -- say\nend Hello;\n',
    "Kotlin": 'fun main() {\n    val x = 3 // three\n    println("hi")\n}\n',
    "Swift": 'let greeting = "hi"\nfunc say() { print(greeting) } // go\n',
    "COBOL": "IDENTIFICATION DIVISION.\nPROGRAM-ID. HELLO.\nPROCEDURE DIVISION.\n    DISPLAY \"HI\".\n    STOP RUN.\n",
    "Lisp": '; square\n(defun sq (x) (* x x))\n(print "hi")\n',
    "Prolog": "% parent\nparent(tom, bob).\nX is 3 + 4.\n",
    "Dart": 'void main() {\n  var x = 3; // three\n  print("hi");\n}\n',
    "Lua": 'local function f(x)\n  return x + 1 -- inc\nend\n',
    "Objective-C": '@interface Foo\n- (int)n; // count\n@end\n',
    "Haskell": '-- double\ndouble :: Int -> Int\ndouble x = x * 2\n',
    "Julia": '# add\nfunction f(x)\n    return x + 1\nend\n',
    "Ruby": '# greet\ndef hi(n)\n  puts "hi #{n}"\nend\n',
    "Scala": 'object Main {\n  val x = 3 // three\n  def main(args: Array[String]) = println("hi")\n}\n',
    "Bash": '#!/bin/sh\nfor f in *.txt; do echo "$f"; done # list\n',
}


def lit(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


def module():
    out = []
    out.append("// Table-driven syntax highlighting (C123, C142): for each of the languages below, the rules that decide\n")
    out.append("// what every byte of a source text is -- plain (0), keyword (1), string (2), number (3), comment (4) or\n")
    out.append("// type (5, a capitalised name that is not a keyword) -- and the file extensions that pick the language.\n")
    out.append("// Written by scripts/gen_highlight.py from its tables. The language list is the leading languages of the\n")
    out.append("// TIOBE index as remembered for October 2025 plus Neper; refresh it from tiobe.com when the item is rebuilt.\n")
    out.append("// The rules are the same for every language: a block comment, a line comment (up to two markers), a string\n")
    out.append("// in one of the language's quote characters (a backslash escapes, a newline ends it), a number (a digit and\n")
    out.append("// the letters, digits and dots after it), and a name looked up in the keyword list (without regard to case\n")
    out.append("// for the languages that have none).\n\n")
    cobol = [l[0] for l in LANGS].index("COBOL")
    out.append("const COBOL_INDEX: usize = " + str(cobol) + "usize\n")
    out.append("const PLAIN: u8 = 0u8\nconst KEYWORD: u8 = 1u8\nconst STRING: u8 = 2u8\nconst NUMBER: u8 = 3u8\nconst COMMENT: u8 = 4u8\nconst TYPE: u8 = 5u8\n")
    out.append(f"const LANGUAGES: usize = {len(LANGS)}usize\n\n")
    out.append("fn name(i: usize) -> str {\n")
    for i, l in enumerate(LANGS):
        out.append(f"    if i == {i}usize {{ ret {lit(l[0])} }}\n")
    out.append('    ret ""\n}\n\n')
    out.append("// The extensions of a language, each between spaces.\nfn extensions(i: usize) -> str {\n")
    for i, l in enumerate(LANGS):
        out.append(f"    if i == {i}usize {{ ret {lit(' ' + ' '.join(l[1]) + ' ')} }}\n")
    out.append('    ret ""\n}\n\n')
    out.append("fn line_comment_1(i: usize) -> str {\n")
    for i, l in enumerate(LANGS):
        if l[2]:
            out.append(f"    if i == {i}usize {{ ret {lit(l[2][0])} }}\n")
    out.append('    ret ""\n}\n\n')
    out.append("fn line_comment_2(i: usize) -> str {\n")
    for i, l in enumerate(LANGS):
        if len(l[2]) > 1:
            out.append(f"    if i == {i}usize {{ ret {lit(l[2][1])} }}\n")
    out.append('    ret ""\n}\n\n')
    out.append("fn block_open(i: usize) -> str {\n")
    for i, l in enumerate(LANGS):
        if l[3]:
            out.append(f"    if i == {i}usize {{ ret {lit(l[3][0])} }}\n")
    out.append('    ret ""\n}\n\n')
    out.append("fn block_close(i: usize) -> str {\n")
    for i, l in enumerate(LANGS):
        if l[3]:
            out.append(f"    if i == {i}usize {{ ret {lit(l[3][1])} }}\n")
    out.append('    ret ""\n}\n\n')
    out.append("fn quotes(i: usize) -> str {\n")
    for i, l in enumerate(LANGS):
        out.append(f"    if i == {i}usize {{ ret {lit(l[4])} }}\n")
    out.append('    ret ""\n}\n\n')
    out.append("fn caseless(i: usize) -> bool {\n")
    for i, l in enumerate(LANGS):
        if l[5]:
            out.append(f"    if i == {i}usize {{ ret true }}\n")
    out.append("    ret false\n}\n\n")
    out.append("// The keywords of a language, each between spaces (lower case for a caseless language).\nfn keywords(i: usize) -> str {\n")
    for i, l in enumerate(LANGS):
        words = l[6].lower() if l[5] else l[6]
        out.append(f"    if i == {i}usize {{ ret {lit(' ' + words + ' ')} }}\n")
    out.append('    ret ""\n}\n\n')
    out.append('''fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn is_alpha(c: u8) -> bool {
    ret (c >= 97u8 && c <= 122u8) || (c >= 65u8 && c <= 90u8) || c == 95u8 || c >= 128u8
}

fn is_digit(c: u8) -> bool {
    ret c >= 48u8 && c <= 57u8
}

fn starts(text: str, at: usize, marker: str) -> bool {
    if marker.len == 0usize || at + marker.len > text.len { ret false }
    var k = 0usize
    while k < marker.len {
        if text[at + k] != marker[k] { ret false }
        k += 1usize
    }
    ret true
}

// Whether the keyword list of language `i` has `word` (between spaces), ignoring case when the language does.
fn is_keyword(i: usize, word: str) -> bool {
    let list = keywords(i)
    let fold = caseless(i)
    var at = 0usize
    while at < list.len {
        while at < list.len && list[at] == 32u8 { at += 1usize }
        var end = at
        while end < list.len && list[end] != 32u8 { end += 1usize }
        if end - at == word.len && end > at {
            var k = 0usize
            var same = true
            while k < word.len {
                var c = word[k]
                if fold { c = lower(c) }
                if list[at + k] != c { same = false }
                k += 1usize
            }
            if same { ret true }
        }
        at = end
    }
    ret false
}

// The language for a file name (its extension, in lower case), and whether there is one.
fn language_for(file: str) -> (usize, bool) {
    var dot = file.len
    var k = 0usize
    while k < file.len {
        if file[k] == 46u8 { dot = k }
        k += 1usize
    }
    if dot >= file.len { ret (0usize, false) }
    let ext = file[dot + 1usize..file.len]
    var i = 0usize
    while i < LANGUAGES {
        let list = extensions(i)
        var at = 0usize
        while at < list.len {
            while at < list.len && list[at] == 32u8 { at += 1usize }
            var end = at
            while end < list.len && list[end] != 32u8 { end += 1usize }
            if end - at == ext.len && end > at {
                var j = 0usize
                var same = true
                while j < ext.len {
                    if list[at + j] != lower(ext[j]) { same = false }
                    j += 1usize
                }
                if same { ret (i, true) }
            }
            at = end
        }
        i += 1usize
    }
    ret (0usize, false)
}

fn has_quote(i: usize, c: u8) -> bool {
    let q = quotes(i)
    var k = 0usize
    while k < q.len {
        if q[k] == c { ret true }
        k += 1usize
    }
    ret false
}

// Classify every byte of `text` for language `i` into out[0..text.len]; the length written.
fn classify(i: usize, text: str, out: []u8) -> usize {
    let n = text.len
    var at = 0usize
    let open = block_open(i)
    let close = block_close(i)
    let line1 = line_comment_1(i)
    let line2 = line_comment_2(i)
    while at < n && at < out.len {
        out[at] = PLAIN
        if starts(text, at, open) {
            var end = at + open.len
            var found = false
            while end < n && !found {
                if starts(text, end, close) {
                    end += close.len
                    found = true
                } else {
                    end += 1usize
                }
            }
            var k = at
            while k < end && k < out.len {
                out[k] = COMMENT
                k += 1usize
            }
            at = end
        } else if starts(text, at, line1) || starts(text, at, line2) {
            var end = at
            while end < n && text[end] != 10u8 { end += 1usize }
            var k = at
            while k < end && k < out.len {
                out[k] = COMMENT
                k += 1usize
            }
            at = end
        } else if has_quote(i, text[at]) {
            let quote = text[at]
            var j = at + 1usize
            while j < n && text[j] != quote && text[j] != 10u8 {
                if text[j] == 92u8 && j + 1usize < n { j += 1usize }
                j += 1usize
            }
            if j < n && text[j] == quote { j += 1usize }
            var k = at
            while k < j && k < out.len {
                out[k] = STRING
                k += 1usize
            }
            at = j
        } else if is_digit(text[at]) {
            var j = at
            while j < n && (is_digit(text[j]) || text[j] == 46u8 || is_alpha(text[j])) { j += 1usize }
            var k = at
            while k < j && k < out.len {
                out[k] = NUMBER
                k += 1usize
            }
            at = j
        } else if is_alpha(text[at]) {
            var j = at
            while j < n && (is_alpha(text[j]) || is_digit(text[j]) || (text[j] == 45u8 && i == COBOL_INDEX)) { j += 1usize }
            let word = text[at..j]
            var klass = PLAIN
            if is_keyword(i, word) {
                klass = KEYWORD
            } else if word[0usize] >= 65u8 && word[0usize] <= 90u8 {
                klass = TYPE
            }
            var k = at
            while k < j && k < out.len {
                out[k] = klass
                k += 1usize
            }
            at = j
        } else {
            at += 1usize
        }
    }
    ret n
}
''')
    return "".join(out)


def fixture():
    out = []
    out.append("// `e.text.highlight`: a snippet in each of the languages classified byte by byte and compared with the classes an\n")
    out.append("// independent implementation of the same rules (scripts/gen_highlight.py) gave, and the language picked by\n")
    out.append("// file extension. Written by scripts/gen_highlight.py. Every check has its own exit code.\n")
    out.append("use e.os\nuse e.mem\nuse e.str\nuse e.text.highlight as hl\n\n")
    out.append("fn check(i: usize, text: str, want: []const u8) -> bool {\n")
    out.append("    var got: [512]u8 = zero\n    let n = hl.classify(i, text, got[0..])\n    if n != want.len { ret false }\n")
    out.append("    var k = 0usize\n    while k < n {\n        if got[k] != want[k] { ret false }\n        k += 1usize\n    }\n    ret true\n}\n\n")
    out.append("fn main(a: *mem.Arena, args: []str) -> err {\n")
    out.append(f"    if hl.LANGUAGES != {len(LANGS)}usize {{ os.exit(1) }}\n")
    code = 2
    for i, l in enumerate(LANGS):
        text = SNIPPETS[l[0]]
        classes = classify(l, text)
        out.append(f"    let t{i} = {lit(text)}\n")
        out.append(f"    let w{i}: [{len(classes)}]u8 = [{len(classes)}]u8{{ " + ", ".join(str(c) for c in classes) + " }\n")
        out.append(f"    if !str.eq(hl.name({i}usize), {lit(l[0])}) {{ os.exit({code}) }}\n")
        code += 1
        out.append(f"    if !check({i}usize, t{i}, w{i}[0..]) {{ os.exit({code}) }}\n")
        code += 1
    out.append("    // By extension: a name's last dot, in lower case.\n")
    picks = [("main.py", "Python"), ("lib.RS", "Rust"), ("app.js", "JavaScript"), ("q.sql", "SQL"), ("x.cpp", "C++"),
             ("hello.ne", "Neper"), ("a.b.go", "Go"), ("run.sh", "Bash")]
    for name, lang in picks:
        idx = [l[0] for l in LANGS].index(lang)
        out.append(f"    let (p{code}, f{code}) = hl.language_for({lit(name)})\n    if !f{code} || p{code} != {idx}usize {{ os.exit({code}) }}\n")
        code += 1
    out.append(f"    let (nx, nf) = hl.language_for(\"README\")\n    if nf {{ os.exit({code}) }}\n")
    code += 1
    out.append(f"    let (ux, uf) = hl.language_for(\"data.unknownext\")\n    if uf {{ os.exit({code}) }}\n")
    out.append("    ret ok\n}\n")
    return "".join(out)


root = Path(__file__).resolve().parent.parent
(root / "lib" / "e" / "text").mkdir(parents=True, exist_ok=True)
(root / "lib" / "e" / "text" / "highlight.e").write_text(module(), encoding="utf-8", newline="\n")
fx = root / "tests" / "selfhost" / "fixtures" / "link" / "text_highlight" / "src"
fx.mkdir(parents=True, exist_ok=True)
(fx / "main.e").write_text(fixture(), encoding="utf-8", newline="\n")
print("wrote", len(LANGS), "languages")
