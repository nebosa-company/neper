// Table-driven syntax highlighting (C123, C142): for each of the languages below, the rules that decide
// what every byte of a source text is -- plain (0), keyword (1), string (2), number (3), comment (4) or
// type (5, a capitalised name that is not a keyword) -- and the file extensions that pick the language.
// Written by scripts/gen_highlight.py from its tables. The language list is the leading languages of the
// TIOBE index as remembered for October 2025 plus Neper; refresh it from tiobe.com when the item is rebuilt.
// The rules are the same for every language: a block comment, a line comment (up to two markers), a string
// in one of the language's quote characters (a backslash escapes, a newline ends it), a number (a digit and
// the letters, digits and dots after it), and a name looked up in the keyword list (without regard to case
// for the languages that have none).

const COBOL_INDEX: usize = 21usize
const PLAIN: u8 = 0u8
const KEYWORD: u8 = 1u8
const STRING: u8 = 2u8
const NUMBER: u8 = 3u8
const COMMENT: u8 = 4u8
const TYPE: u8 = 5u8
const LANGUAGES: usize = 32usize

fn name(i: usize) -> str {
    if i == 0usize { ret "Neper" }
    if i == 1usize { ret "Python" }
    if i == 2usize { ret "C" }
    if i == 3usize { ret "C++" }
    if i == 4usize { ret "Java" }
    if i == 5usize { ret "C#" }
    if i == 6usize { ret "JavaScript" }
    if i == 7usize { ret "TypeScript" }
    if i == 8usize { ret "Go" }
    if i == 9usize { ret "Visual Basic" }
    if i == 10usize { ret "Pascal" }
    if i == 11usize { ret "SQL" }
    if i == 12usize { ret "Fortran" }
    if i == 13usize { ret "Perl" }
    if i == 14usize { ret "R" }
    if i == 15usize { ret "PHP" }
    if i == 16usize { ret "Rust" }
    if i == 17usize { ret "MATLAB" }
    if i == 18usize { ret "Ada" }
    if i == 19usize { ret "Kotlin" }
    if i == 20usize { ret "Swift" }
    if i == 21usize { ret "COBOL" }
    if i == 22usize { ret "Lisp" }
    if i == 23usize { ret "Prolog" }
    if i == 24usize { ret "Dart" }
    if i == 25usize { ret "Lua" }
    if i == 26usize { ret "Objective-C" }
    if i == 27usize { ret "Haskell" }
    if i == 28usize { ret "Julia" }
    if i == 29usize { ret "Ruby" }
    if i == 30usize { ret "Scala" }
    if i == 31usize { ret "Bash" }
    ret ""
}

// The extensions of a language, each between spaces.
fn extensions(i: usize) -> str {
    if i == 0usize { ret " ne e " }
    if i == 1usize { ret " py pyw " }
    if i == 2usize { ret " c h " }
    if i == 3usize { ret " cpp cc cxx hpp hh " }
    if i == 4usize { ret " java " }
    if i == 5usize { ret " cs " }
    if i == 6usize { ret " js mjs cjs jsx " }
    if i == 7usize { ret " ts tsx " }
    if i == 8usize { ret " go " }
    if i == 9usize { ret " vb bas " }
    if i == 10usize { ret " pas pp dpr " }
    if i == 11usize { ret " sql " }
    if i == 12usize { ret " f90 f95 f03 for f " }
    if i == 13usize { ret " pl pm " }
    if i == 14usize { ret " r " }
    if i == 15usize { ret " php " }
    if i == 16usize { ret " rs " }
    if i == 17usize { ret " m " }
    if i == 18usize { ret " adb ads " }
    if i == 19usize { ret " kt kts " }
    if i == 20usize { ret " swift " }
    if i == 21usize { ret " cob cbl " }
    if i == 22usize { ret " lisp lsp cl scm el " }
    if i == 23usize { ret " pro prolog " }
    if i == 24usize { ret " dart " }
    if i == 25usize { ret " lua " }
    if i == 26usize { ret " mm " }
    if i == 27usize { ret " hs lhs " }
    if i == 28usize { ret " jl " }
    if i == 29usize { ret " rb rake " }
    if i == 30usize { ret " scala sc " }
    if i == 31usize { ret " sh bash zsh " }
    ret ""
}

fn line_comment_1(i: usize) -> str {
    if i == 0usize { ret "//" }
    if i == 1usize { ret "#" }
    if i == 2usize { ret "//" }
    if i == 3usize { ret "//" }
    if i == 4usize { ret "//" }
    if i == 5usize { ret "//" }
    if i == 6usize { ret "//" }
    if i == 7usize { ret "//" }
    if i == 8usize { ret "//" }
    if i == 9usize { ret "'" }
    if i == 10usize { ret "//" }
    if i == 11usize { ret "--" }
    if i == 12usize { ret "!" }
    if i == 13usize { ret "#" }
    if i == 14usize { ret "#" }
    if i == 15usize { ret "//" }
    if i == 16usize { ret "//" }
    if i == 17usize { ret "%" }
    if i == 18usize { ret "--" }
    if i == 19usize { ret "//" }
    if i == 20usize { ret "//" }
    if i == 21usize { ret "*>" }
    if i == 22usize { ret ";" }
    if i == 23usize { ret "%" }
    if i == 24usize { ret "//" }
    if i == 25usize { ret "--" }
    if i == 26usize { ret "//" }
    if i == 27usize { ret "--" }
    if i == 28usize { ret "#" }
    if i == 29usize { ret "#" }
    if i == 30usize { ret "//" }
    if i == 31usize { ret "#" }
    ret ""
}

fn line_comment_2(i: usize) -> str {
    if i == 15usize { ret "#" }
    ret ""
}

fn block_open(i: usize) -> str {
    if i == 2usize { ret "/*" }
    if i == 3usize { ret "/*" }
    if i == 4usize { ret "/*" }
    if i == 5usize { ret "/*" }
    if i == 6usize { ret "/*" }
    if i == 7usize { ret "/*" }
    if i == 8usize { ret "/*" }
    if i == 10usize { ret "{" }
    if i == 11usize { ret "/*" }
    if i == 15usize { ret "/*" }
    if i == 16usize { ret "/*" }
    if i == 17usize { ret "%{" }
    if i == 19usize { ret "/*" }
    if i == 20usize { ret "/*" }
    if i == 22usize { ret "#|" }
    if i == 23usize { ret "/*" }
    if i == 24usize { ret "/*" }
    if i == 25usize { ret "--[[" }
    if i == 26usize { ret "/*" }
    if i == 27usize { ret "{-" }
    if i == 28usize { ret "#=" }
    if i == 29usize { ret "=begin" }
    if i == 30usize { ret "/*" }
    ret ""
}

fn block_close(i: usize) -> str {
    if i == 2usize { ret "*/" }
    if i == 3usize { ret "*/" }
    if i == 4usize { ret "*/" }
    if i == 5usize { ret "*/" }
    if i == 6usize { ret "*/" }
    if i == 7usize { ret "*/" }
    if i == 8usize { ret "*/" }
    if i == 10usize { ret "}" }
    if i == 11usize { ret "*/" }
    if i == 15usize { ret "*/" }
    if i == 16usize { ret "*/" }
    if i == 17usize { ret "%}" }
    if i == 19usize { ret "*/" }
    if i == 20usize { ret "*/" }
    if i == 22usize { ret "|#" }
    if i == 23usize { ret "*/" }
    if i == 24usize { ret "*/" }
    if i == 25usize { ret "]]" }
    if i == 26usize { ret "*/" }
    if i == 27usize { ret "-}" }
    if i == 28usize { ret "=#" }
    if i == 29usize { ret "=end" }
    if i == 30usize { ret "*/" }
    ret ""
}

fn quotes(i: usize) -> str {
    if i == 0usize { ret "\"" }
    if i == 1usize { ret "\"'" }
    if i == 2usize { ret "\"'" }
    if i == 3usize { ret "\"'" }
    if i == 4usize { ret "\"'" }
    if i == 5usize { ret "\"'" }
    if i == 6usize { ret "\"'`" }
    if i == 7usize { ret "\"'`" }
    if i == 8usize { ret "\"'`" }
    if i == 9usize { ret "\"" }
    if i == 10usize { ret "'" }
    if i == 11usize { ret "'\"" }
    if i == 12usize { ret "\"'" }
    if i == 13usize { ret "\"'`" }
    if i == 14usize { ret "\"'`" }
    if i == 15usize { ret "\"'" }
    if i == 16usize { ret "\"" }
    if i == 17usize { ret "\"'" }
    if i == 18usize { ret "\"" }
    if i == 19usize { ret "\"'" }
    if i == 20usize { ret "\"" }
    if i == 21usize { ret "\"'" }
    if i == 22usize { ret "\"" }
    if i == 23usize { ret "\"'" }
    if i == 24usize { ret "\"'" }
    if i == 25usize { ret "\"'" }
    if i == 26usize { ret "\"'" }
    if i == 27usize { ret "\"'" }
    if i == 28usize { ret "\"'`" }
    if i == 29usize { ret "\"'`" }
    if i == 30usize { ret "\"'" }
    if i == 31usize { ret "\"'`" }
    ret ""
}

fn caseless(i: usize) -> bool {
    if i == 9usize { ret true }
    if i == 10usize { ret true }
    if i == 11usize { ret true }
    if i == 12usize { ret true }
    if i == 18usize { ret true }
    if i == 21usize { ret true }
    if i == 22usize { ret true }
    ret false
}

// The keywords of a language, each between spaces (lower case for a caseless language).
fn keywords(i: usize) -> str {
    if i == 0usize { ret " fn type const var let ret if else while for in break continue use error struct enum union try match true false zero ok " }
    if i == 1usize { ret " False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield self " }
    if i == 2usize { ret " auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while NULL " }
    if i == 3usize { ret " alignas alignof and asm auto bool break case catch char class const constexpr continue decltype default delete do double else enum explicit export extern false float for friend goto if inline int long mutable namespace new noexcept not nullptr operator or private protected public register return short signed sizeof static struct switch template this throw true try typedef typeid typename union unsigned using virtual void volatile while " }
    if i == 4usize { ret " abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false null var record " }
    if i == 5usize { ret " abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using var virtual void volatile while async await record " }
    if i == 6usize { ret " async await break case catch class const continue debugger default delete do else export extends false finally for function if import in instanceof let new null of return static super switch this throw true try typeof undefined var void while with yield " }
    if i == 7usize { ret " abstract any as async await boolean break case catch class const constructor continue declare default delete do else enum export extends false finally for from function get if implements import in instanceof interface is keyof let module namespace never new null number of private protected public readonly return set static string super switch this throw true try type typeof undefined unknown var void while yield " }
    if i == 8usize { ret " break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil iota " }
    if i == 9usize { ret " addhandler addressof and as boolean byref byte byval call case catch class const continue date declare default dim do double each else elseif end enum error event exit false finally for friend function get goto if implements imports in inherits integer interface is let long loop me module mod mustinherit namespace new next not nothing object of on option optional or overrides private property protected public raiseevent readonly redim resume return select set shared short single static step stop string structure sub then throw to true try typeof until using variant when while with writeonly " }
    if i == 10usize { ret " and array as asm begin case class const constructor destructor div do downto else end except exports false file finalization finally for function goto if implementation in inherited initialization inline interface is label mod nil not object of on or out packed private procedure program property protected public raise record repeat set shl shr string then threadvar to true try type unit until uses var while with xor " }
    if i == 11usize { ret " add all alter and any as asc between by case check column constraint create cross database default delete desc distinct drop else end exists foreign from full group having in index inner insert into is join key left like limit not null on or order outer primary references right select set table then top union unique update values view when where with " }
    if i == 12usize { ret " allocatable allocate call case character close common complex contains continue cycle data deallocate dimension do double else elseif end endif enddo exit format function goto if implicit in integer intent interface logical module nullify only open out parameter pointer precision print private program public read real recursive result return save select stop subroutine target then type use where while write " }
    if i == 13usize { ret " and bless chomp chop close continue defined delete die do each else elsif eval exists exit for foreach format goto grep if keys last local map my next no not open or our package pop print push redo ref require return reverse scalar shift sort splice split sub tie undef unless unshift until use values wantarray warn while write xor " }
    if i == 14usize { ret " if else repeat while function for next break TRUE FALSE NULL Inf NaN NA in library require return " }
    if i == 15usize { ret " abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends false final finally fn for foreach function global goto if implements include instanceof interface isset list match namespace new null or print private protected public require return static switch throw trait true try unset use var while xor yield " }
    if i == 16usize { ret " as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while " }
    if i == 17usize { ret " break case catch classdef continue else elseif end for function global if otherwise parfor persistent return switch try while true false " }
    if i == 18usize { ret " abort abs abstract accept access all and array at begin body case constant declare delay delta digits do else elsif end entry exception exit for function generic goto if in interface is limited loop mod new not null of or others out overriding package pragma private procedure protected raise range record rem renames requeue return reverse select separate some subtype synchronized tagged task terminate then type until use when while with xor " }
    if i == 19usize { ret " abstract as break by catch class companion const constructor continue data do else enum false final finally for fun if import in inline interface internal is lateinit null object open operator override package private protected public return sealed super this throw true try typealias val var when where while " }
    if i == 20usize { ret " actor any as associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate for func guard if import in init inout internal is let nil open operator private protocol public repeat rethrows return self Self static struct subscript super switch throw throws true try typealias var where while " }
    if i == 21usize { ret " accept add after all and before call close compute continue data display divide division else end-if end-perform evaluate exit fd file giving go goback identification if in into move multiply not open or perform pic picture procedure program-id read return section select set stop string subtract then to until using value varying when working-storage write zero " }
    if i == 22usize { ret " and cond defmacro defun defvar defparameter defstruct do dolist dotimes else flet if lambda let let* loop nil not or progn quote return setf setq t unless when " }
    if i == 23usize { ret " is mod rem not dynamic discontiguous module use_module true fail halt assert asserta assertz retract findall bagof setof " }
    if i == 24usize { ret " abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for Function get hide if implements import in interface is late library mixin new null on operator part required rethrow return set show static super switch sync this throw true try typedef var void while with yield " }
    if i == 25usize { ret " and break do else elseif end false for function goto if in local nil not or repeat return then true until while " }
    if i == 26usize { ret " auto break case char const continue default do double else enum extern float for goto if id inline int long nil NO return self short signed sizeof static struct super switch typedef union unsigned void volatile while YES @interface @implementation @end @property @protocol " }
    if i == 27usize { ret " case class data default deriving do else forall foreign if import in infix infixl infixr instance let module newtype of qualified then type where True False " }
    if i == 28usize { ret " abstract baremodule begin break catch const continue do else elseif end export false finally for function global if import in let local macro module mutable nothing primitive quote return struct true try using where while " }
    if i == 29usize { ret " BEGIN END alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield " }
    if i == 30usize { ret " abstract case catch class def do else extends false final finally for forSome if implicit import lazy match new null object override package private protected return sealed super this throw trait true try type val var while with yield given using enum " }
    if i == 31usize { ret " case do done elif else esac exit export fi for function if in local read return select set shift then time until unset while echo cd source alias " }
    ret ""
}

fn lower(c: u8) -> u8 {
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
