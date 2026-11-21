# xml2::xml_find_all / xml_find_num / xml_find_chr / xml_find_lgl (libxml2's XPath 1.0) on
# well-formed documents with namespaces. A case holds the document and the expression ("in") and the
# answer written as text: a node-set is one record per node (type, local name, namespace URI and
# string-value joined by U+0002) joined by U+0001, a number is the hex of its IEEE bits, a string is
# itself and a boolean is TRUE or FALSE. XPath prefixes are the ones xml_ns() names (d1, d2 ... for
# default namespaces).
library(xml2)

hex <- function(x) if (is.nan(x) || is.na(x)) "NaN" else paste(rev(as.character(writeBin(as.numeric(x), raw(), endian = "little"))), collapse = "")

docs <- c(
  ns = '<r xmlns="urn:d" xmlns:p="urn:p" a="1" p:b="2"><p:c>x</p:c><d>y<!--c--><?pi z?></d><e/><p:c k="v">z<p:c>deep</p:c></p:c></r>',
  lib = paste0('<?xml version="1.0"?><lib>',
    '<book id="b1" year="1999" lang="en"><title>Alpha &amp; Omega</title><author>Ann</author><price>10.50</price></book>',
    '<book id="b2" year="2005" lang="en-US"><title>Beta</title><author>Bob</author><author>Cy</author><price>7</price></book>',
    '<book id="b3" year="1987"><title><![CDATA[<Gamma>]]></title><price>22.25</price><note>  spaced   out  </note></book>',
    '<!-- end --><?app go?></lib>'),
  deep = '<a><b><c n="1">one</c><c n="2">two<d>in</d></c></b><b><c n="3">three</c><e/></b>tail<f x="y"/></a>',
  mixed = '<p>Hello <b>big</b> and <i>small <b>nested</b></i> world<br/>!</p>',
  num = '<n><v>3</v><v>-1.5</v><v>10</v><v>abc</v><v/><v> 7 </v></n>',
  attrs = '<t a="1" b="two" c=" 3 "><u a="1"/><u a="2" b="x"/><u/></t>',
  nsq = '<x:root xmlns:x="urn:x" xmlns:y="urn:y"><x:a y:at="1">A</x:a><y:a>B</y:a><a>C</a><x:a><y:a>D</y:a></x:a></x:root>',
  ents = '<e a="&lt;&amp;&#65;&#x42;">&lt;t&gt; &amp; &quot;q&quot; &apos;a&apos; &#169;</e>',
  lang = '<d xml:lang="en"><p xml:lang="fr-CA"><q>x</q></p><r>y</r></d>'
)

nodes_expr <- list(
  ns = c("//d1:c", "//d1:d", "/d1:r/@a", "/d1:r/@p:b", "//comment()", "//processing-instruction()", "//text()", "/d1:r/*", "//*", "//p:c/p:c", "//p:c[@k]", "//p:c[@k='v']/text()", "/d1:r/d1:d/node()", "//@*", "//@p:*", "//p:*", "//d1:*", "//*[local-name()='c']", "//*[namespace-uri()='urn:p']", "//*[namespace-uri()='urn:d']", "//*[name()='p:c']", "//d1:e/preceding-sibling::*", "//d1:e/following-sibling::*", "//p:c/ancestor::*", "//p:c/ancestor-or-self::*", "//d1:d/self::node()", "//p:c[2]", "//p:c[last()]", "(//p:c)[last()]", "//*[not(*)]", "//*[count(*)>1]", "descendant::p:c", "/descendant-or-self::node()", "//d1:e/following::*", "//d1:e/preceding::*", "//node()[self::comment() or self::processing-instruction()]", "//processing-instruction('pi')", "//*[starts-with(local-name(), 'c')]", "id('x')"),
  lib = c("/lib/book", "/lib/book/title", "//title/text()", "//book[@year>2000]/title", "//book[price>10]/@id", "//book[author='Bob']/title", "//book[count(author)=2]/@id", "//book[last()]/title", "//book[position()=2]/@id", "//book[position()<3]/@id", "//book[not(@lang)]/@id", "//book[@lang='en']/@id", "//book[starts-with(@lang,'en')]/@id", "//book[contains(title,'Alpha')]/@id", "//author", "//author[1]", "(//author)[2]", "//author[last()]", "//price[. > 8]", "//price[number(.) < 10 or number(.) > 20]", "//book/*[self::title or self::price]", "//book[title='<Gamma>']/@id", "//note", "//note/text()", "//comment()", "//processing-instruction()", "/lib/node()", "//@id", "//@*", "//book[@id='b2']/preceding-sibling::book/@id", "//book[@id='b2']/following-sibling::*/@id", "//book[@id='b2']/following-sibling::node()", "//title/ancestor::lib", "//title/parent::book/@id", "//price/../@id", "//book[price=7]", "//book[1]/title | //book[2]/title", "//book/title | //book/author", "//book[@id='b1']/title/text()", "//book[year]", "//book[@year=1987]/note", "//book/@year[. < 2000]", "//book[normalize-space(note)='spaced out']/@id", "//*[@id and @year]/@id", "//*[@id or @lang]/@id", "//*[count(@*)=3]/@id", "//book[string-length(title) > 5]/@id", "//book[substring(title, 1, 1)='A']/@id", "//book[translate(@lang,'abcdefghijklmnopqrstuvwxyz','ABCDEFGHIJKLMNOPQRSTUVWXYZ')='EN']/@id", "//book[sum(price) > 20]/@id", "//book[floor(price) = 22]/@id", "//book[ceiling(price)=11]/@id", "//book[round(price)=11]/@id", "//book[price mod 2 = 1]/@id", "//book[price div 2 = 3.5]/@id", "//book[-price < -20]/@id", "//book[@year != 1999]/@id", "//book[@year >= 2005]/@id", "//book[@year <= 1999]/@id", "//lib/descendant::*[1]", "//lib/descendant::text()[normalize-space()][1]", "//title[1]/text()", "//book/title[text()='Beta']", "//book[contains(@lang,'-')]/@id", "//book[boolean(note)]/@id", "//book[true()]/@id", "//book[false()]/@id", "//book[lang('en')]/@id"),
  deep = c("//c", "//c[@n=2]", "//c/d", "//b[1]/c", "//b[2]/c", "//b/c[1]", "//b[c]", "//b[e]", "/a/text()", "/a/node()", "//d/ancestor::*", "//d/ancestor-or-self::*", "//c[@n=1]/following::*", "//c[@n=3]/preceding::*", "//c[@n=3]/preceding::c", "//c[@n=2]/following-sibling::*", "//e/preceding-sibling::*", "//b/following-sibling::*", "//b/following-sibling::b", "//f/@x", "//f/preceding-sibling::node()", "/a/b[1]/c[2]/d/text()", "//*[count(c)=2]", "//*[c and e]", "//*[not(node())]", "//*[text()]", "//*[text()='tail']", "/a/node()[3]", "/a/node()[last()]", "//c[position() mod 2 = 1]", "//c[last()-1]", "//node()[position()=1]", "//*[position()=1]", "//b/c[last()]", "//b[last()]/c", "(//c)[2]", "(//c)[position()>1]", "//a//c", "//a/b//d", "/descendant::c[2]", "//c/self::c", "//c/self::d", "/*", "/*/*", "/*/*/*", "//*[@n]", "//*[@n][2]", "//c[@n<3]", "//c[@n>1][1]", "//d/../@n", "//d/../../*", "//c[d]/@n", ".", "..", "/", "//b/c/text()", "//b/*/text()", "string(//d)"),
  mixed = c("//b", "//b/text()", "//i/b", "/p/text()", "/p/*", "//br", "//i/text()", "/p/node()", "//text()[contains(.,'and')]", "//b[1]/following::text()", "//b[2]/preceding::text()", "//*[text()='big']", "//p/i/following-sibling::*", "//p/b/following-sibling::text()[1]", "//br/preceding-sibling::*", "//br/preceding-sibling::*[1]", "//br/following-sibling::text()", "//text()[normalize-space()='']", "//text()"),
  num = c("//v", "//v[number(.) = 3]", "//v[number(.) > 0]", "//v[. > 0]", "//v[. = 10]", "//v[. = '10']", "//v[.='abc']", "//v[not(text())]", "//v[string-length() = 0]", "//v[normalize-space() = '7']", "//v[. = 7]", "//v[number(.) != number(.)]", "//v[. != 3]", "//v[floor(.) = -2]", "//v[ceiling(.) = -1]", "//v[round(.) = -1]", "//v[round(.) = 3]", "//v[. mod 2 = 1]", "//v[. * 2 = 20]", "//v[. + 1 = 4]", "//v[. - 1 = 2]", "//v[. div 2 = 5]"),
  attrs = c("//@*", "//@a", "//u/@a", "//u[@a]", "//u[@b]/@b", "//u[not(@*)]", "/t/@*", "/t/@b/..", "//@*[. = 1]", "//@*[. = '1']", "//@*[string-length(.) > 2]", "//@*[name()='b']", "//@a[. > 1]", "//u[@a=1]", "//u[@a=2 and @b='x']", "//u[@a or @b]", "//t/@c", "//@c[normalize-space(.)='3']", "//@*[local-name()='a']/parent::*", "/t/u[2]/@*", "//@*[position()=1]", "//u/@*[1]", "//u[2]/@*[last()]"),
  nsq = c("//x:a", "//y:a", "//a", "//x:a/@y:at", "//@y:at", "//*[local-name()='a']", "//*[namespace-uri()='urn:x']", "//*[namespace-uri()='urn:y']", "//*[namespace-uri()='']", "//*[name()='x:a']", "//x:a/y:a", "//x:*", "//y:*", "//*[local-name()='a'][namespace-uri()='urn:y']", "/x:root/*", "/x:root/x:a[1]", "/x:root/x:a[2]/y:a", "//x:a[@y:at]", "//x:a[y:a]", "//y:a/parent::x:a", "//y:a/ancestor::*", "//x:a[1]/following-sibling::*", "//x:a/text()", "//@*", "//@*[namespace-uri()='urn:y']", "//*[local-name()='root']/*[2]"),
  ents = c("/e", "/e/text()", "/e/@a", "//@a", "//text()"),
  lang = c("//*[lang('en')]", "//*[lang('fr')]", "//*[lang('fr-CA')]", "//*[lang('de')]", "//q[lang('fr')]", "//r[lang('en')]", "//p[lang('en')]")
)

scalar_expr <- list(
  ns = list(num = c("count(//d1:*)", "count(//p:*)", "count(//*)", "count(//@*)", "count(//node())", "count(//text())", "count(//comment())", "string-length(//p:c[@k])", "count(//p:c/p:c)", "count(/)", "sum(//@a)", "number(/d1:r/@a)", "number(/d1:r/@p:b) + 1", "string-length(name(//p:c))", "count(//*[namespace-uri()='urn:p'])"),
            chr = c("name(/*)", "local-name(//p:c)", "name(//p:c)", "namespace-uri(//p:c)", "namespace-uri(/*)", "namespace-uri(//@p:b)", "name(//@p:b)", "local-name(//@p:b)", "string(//d1:d)", "string(//p:c)", "string(/)", "string(//comment())", "string(//processing-instruction())", "name(//processing-instruction())", "name(//comment())", "name(//text())", "concat(name(/*), '|', count(//*))", "string(//p:c[2])", "string(//@*)", "name(//d1:e/following-sibling::*[1])", "string(//p:c/p:c)", "name(//*[2])", "name(//*[last()])", "string(//p:c[@k='v']/@k)"),
            lgl = c("boolean(//d1:e)", "boolean(//q)", "boolean(//p:c)", "//p:c/@k = 'v'", "//p:c = 'x'", "//p:c = 'deep'", "count(//*) > 5", "not(//p:c)", "true()", "false()", "boolean(//@p:b)", "//d1:d = 'y'", "//comment() = 'c'", "lang('en')", "starts-with(name(/*), 'r')", "contains(string(//d1:d), 'y')")),
  lib = list(num = c("count(//book)", "count(//author)", "count(//@*)", "sum(//price)", "sum(//book/@year)", "sum(//book/@year) div count(//book)", "count(//book[@year<2000])", "number(//price[1])", "number(//book[2]/price)", "string-length(//title[1])", "string-length(//note)", "string-length(normalize-space(//note))", "floor(sum(//price))", "ceiling(sum(//price))", "round(sum(//price))", "round(2.5)", "round(-2.5)", "round(0.5)", "round(-0.5)", "round(1.4999999)", "floor(-0.5)", "ceiling(-0.5)", "1 div 0", "-1 div 0", "0 div 0", "5 mod 3", "-5 mod 3", "5 mod -3", "5.5 mod 2", "2 + 3 * 4", "(2 + 3) * 4", "10 - 4 - 3", "2 * 3 div 4", "1 + 1 = 2", "number('1e3')", "number('  12  ')", "number('.5')", "number('5.')", "number('+5')", "number('-5')", "number('0x10')", "number('')", "number('1,5')", "number(true())", "number(false())", "string-length('héllo')", "string-length('日本語')", "count(//*[@id])", "count(//book[price > 10])", "count(//title[contains(., 'a')])", "count(//book[last()])", "number(//book[@id='b3']/price) * 2", "sum(//nothing)", "count(//nothing)", "number(//nothing)"),
        chr = c("string(//title[1])", "string(//book[1])", "string(//book[3]/title)", "name(/*)", "name(//@id)", "name(//book[1]/*[2])", "concat('a', 'b', 'c')", "concat(//book[1]/@id, '-', //book[2]/@id)", "substring('12345', 2, 3)", "substring('12345', 2)", "substring('12345', 0)", "substring('12345', -1, 3)", "substring('12345', 1.5, 2.6)", "substring('12345', 0, 3)", "substring('12345', 2, 0)", "substring('12345', 5, 5)", "substring-before('a=b=c', '=')", "substring-after('a=b=c', '=')", "substring-before('abc', 'x')", "substring-after('abc', 'x')", "substring-after('abc', '')", "substring-before('abc', '')", "normalize-space('  a   b  ')", "normalize-space(//note)", "normalize-space('')", "translate('abcabc', 'ab', 'xy')", "translate('abc', 'abc', 'x')", "translate('hello', 'el', '')", "translate('--aaa--', 'abc-', 'ABC')", "string(1 div 0)", "string(-1 div 0)", "string(0 div 0)", "string(0)", "string(-0)", "string(1.5)", "string(100)", "string(1e10)", "string(0.1 + 0.2)", "string(1 div 3)", "string(123456789012345678)", "string(0.000001)", "string(-0.5)", "string(true())", "string(false())", "string('x')", "string(//price[1])", "string(//@id)", "string(//nothing)", "string(number('x'))", "lower-case('A')", "upper-case('a')"),
        lgl = c("starts-with('abc', 'ab')", "starts-with('abc', '')", "starts-with('abc', 'bc')", "contains('abc', 'bc')", "contains('abc', '')", "contains('abc', 'x')", "boolean(//book)", "boolean(//nothing)", "boolean('')", "boolean('a')", "boolean(0)", "boolean(1)", "boolean(0 div 0)", "boolean(-0)", "boolean(//price[1])", "not(//nothing)", "//price = 7", "//price = 7.0", "//price > 22", "//price >= 22.25", "//price < 7", "//price != 7", "//book/@year = 1999", "//book/@year = '1999'", "//author = 'Cy'", "//author != 'Cy'", "not(//author = 'Cy')", "//title = //author", "//price = //book/@year", "count(//book) = 3", "true() and false()", "true() or false()", "1 = 1", "1 = '1'", "'a' = 'a'", "'a' < 'b'", "'10' < '9'", "10 < 9", "true() = 1", "false() = 0", "true() = 'x'", "//nothing = 1", "//nothing != 1", "not(//nothing = 1)", "lang('en')", "lang('en-US')", "0 div 0 = 0 div 0", "0 div 0 != 0 div 0", "1 div 0 = 1 div 0", "-1 div 0 < 1 div 0", "'1' = 1.0", "2 > 1 > 0", "1 < 2 < 3", "3 > 2 > 1", "1 = 1 = 1", "not(1) = 0", "string-length('') = 0")),
  deep = list(num = c("count(//c)", "count(//*)", "count(//text())", "count(//b[1]/c)", "count(/a/node())", "count(//c[d])", "count(//d/ancestor::*)", "count(//c/preceding::*)", "count(//c[@n=3]/preceding::*)", "count(//c[@n=1]/following::*)", "count(//*[not(*)])", "sum(//c/@n)", "count(//c/@n)", "count(//f/@*)"),
              chr = c("string(//c[@n=2])", "string(/a)", "string(//b[2])", "name(//d/..)", "name(//d/../..)", "string(//f/@x)", "name(//c[@n=3]/following-sibling::*)", "string(/a/text())", "name(/a/node()[3])", "string(/a/node()[3])", "string(//c[@n=1]/following::c[1]/@n)"),
              lgl = c("boolean(//d)", "//c/@n = 2", "//c = 'three'", "//b/c = 'one'", "count(//c) = 3", "//c[@n=2]/d = 'in'", "//f/@x = 'y'", "boolean(/a/text())", "boolean(//e/*)")),
  mixed = list(num = c("count(//b)", "count(//text())", "count(//node())", "count(/p/node())", "string-length(string(/p))", "string-length(normalize-space(string(/p)))"),
               chr = c("string(/p)", "string(//i)", "string(//b)", "string(//b[2])", "normalize-space(string(/p))", "string(//br)", "string(//i/b)", "concat(//b[1], '/', //b[2])", "translate(string(/p), ' ', '_')"),
               lgl = c("//b = 'big'", "//b = 'nested'", "//i = 'small nested'", "contains(/p, 'big and')", "boolean(//br)", "boolean(//br/*)", "boolean(//br/text())")),
  num = list(num = c("sum(//v)", "sum(//v[number(.) = number(.)])", "count(//v)", "count(//v[number(.) = number(.)])", "number(//v[1])", "number(//v[2])", "number(//v[4])", "number(//v[5])", "number(//v[6])", "sum(//v[1] | //v[3])", "number(//v[1]) + number(//v[2])", "number(//v[2]) * 2", "number(//v[3]) div number(//v[1])", "number(//v[3]) mod number(//v[1])", "floor(number(//v[2]))", "ceiling(number(//v[2]))", "round(number(//v[2]))", "number(//v[6]) + 1", "count(//v[. > 2])", "count(//v[. < 2])", "count(//v[. = 3])", "count(//v[. != 3])", "sum(//nothing)"),
             chr = c("string(//v[2])", "string(number(//v[2]))", "string(sum(//v[1] | //v[2]))", "string(//v[6])", "normalize-space(//v[6])", "string(number(//v[4]))", "string(number(//v[5]))", "string(sum(//v))", "string(count(//v))"),
             lgl = c("//v = 3", "//v = -1.5", "//v = 10", "//v = 'abc'", "//v = ''", "//v > 9", "//v < -1", "//v < -2", "//v >= 10", "//v != 3", "//v = 7", "//v = ' 7 '", "boolean(//v[5])", "boolean(//v[5]/text())", "boolean(number(//v[4]))")),
  attrs = list(num = c("count(//@*)", "count(//u)", "count(//u/@*)", "sum(//@a)", "sum(//u/@a)", "count(//@a)", "number(/t/@a)", "number(/t/@c)", "number(/t/@b)", "string-length(/t/@c)", "count(//u[@a])"),
               chr = c("string(/t/@a)", "string(/t/@c)", "normalize-space(/t/@c)", "name(/t/@*[2])", "name(//u[2]/@*[2])", "string(//u[2]/@b)", "string(//u[3]/@a)", "name(//@*[3])", "concat(/t/@a, /t/@b)"),
               lgl = c("/t/@a = 1", "/t/@a = '1'", "/t/@c = 3", "/t/@c = ' 3 '", "//u/@a = 2", "//u/@a > 1", "boolean(//u[3]/@*)", "boolean(//@zz)", "//@a = //@b")),
  nsq = list(num = c("count(//x:a)", "count(//y:a)", "count(//a)", "count(//*)", "count(//@*)", "count(//x:*)", "count(//y:*)", "count(//*[local-name()='a'])", "count(//*[namespace-uri()=''])", "count(//*[namespace-uri()='urn:x'])"),
             chr = c("string(//x:a)", "string(//y:a)", "string(//a)", "namespace-uri(//a)", "namespace-uri(//y:a)", "name(//y:a)", "local-name(//y:a)", "name(//@y:at)", "namespace-uri(//@y:at)", "name(/*)", "namespace-uri(/*)", "string(//x:a[2])", "string(/x:root)", "name(//x:a/y:a)", "namespace-uri(//x:a/y:a)"),
             lgl = c("boolean(//a)", "boolean(//z:a)", "//x:a = 'A'", "//y:a = 'B'", "//a = 'C'", "//x:a = 'D'", "count(//x:a) = 2")),
  ents = list(num = c("string-length(/e)", "string-length(/e/@a)", "count(//text())"),
              chr = c("string(/e)", "string(/e/@a)", "normalize-space(/e)", "translate(string(/e/@a), '&', 'E')"),
              lgl = c("/e = '<t> & \"q\" \\'a\\' ©'", "/e/@a = '<&AB'", "contains(/e, '&')", "contains(/e, '<t>')")),
  lang = list(num = c("count(//*[lang('en')])", "count(//*[lang('fr')])", "count(//*[lang('FR')])", "count(//*[lang('f')])", "count(//*[lang('')])"),
              chr = c("string(//*[lang('fr')][1])", "name(//*[lang('en')][2])", "string(//r)", "string(//q)"),
              lgl = c("//q[lang('fr')]", "//q[lang('fr-CA')]", "//r[lang('en')]", "boolean(//r[lang('fr')])", "lang('en')", "/d/p[lang('en')]"))
)

# number() on strings, number literals and the way a number becomes a string (libxml2's own rules)
numstr <- c("1e3", "1E3", "1e+3", "1e-3", ".5e1", "5.e1", "1e", "e1", "+5", "-5", " 12 ", "1 2", "0x10", "1_0", "Infinity", "NaN", "1.5.5", "--5", "5-", "  -5", "-  5", ".", "-.", "5.", "+.5", "1e5.5", "1\n", "\t7", "00012", "0.0", "-0", "0.1234567890123456789", "9007199254740993", "0.1", "0.30000000000000004", "123.456", "1e22", "1e23", "12345.6789e-2", "0.000001", "3.14159265358979", "  \n 4.5 \t")
literals <- c("0.1", "100000", "1000000000", "1000000001", "2147483647", "2147483648", "-2147483648", "4294967296", "1e9", "1e10", "999999999.5", "0.00001", "0.000011", "0.00001234", "123456.789", "1234567.89", "0.5", "-0.5", "1e15", "1e16", "123456789012", "0.1234567890123456", "12345678901234567", "2.5", "1 div 3", "2 div 3", "10 div 3", "100 div 3", "1000000 div 3", "0.1 + 0.2", "-1 div 0", "1 div 7", "22 div 7", "1 div 3 * 3", "0.1 * 3", "5e-5", "5e-6", "1.5e-5", "123456789.123456789", "0.99999999999999999", "99999999999999.9", "999999999999999.9", "9.99999999999999e14", "1e14", "123e-7", "-1e-7", "314.15926535897932 * 1e8", "7 div 1e6", "1 div 3 + 1e10", "2 mod 5", "7.5 mod 2", "-7.5 mod 2", "2 * 0.5", "1.000000000000001", "100.5", "0.007", "1e-5", "9.99999e-6")
ev <- function(doc, xp, kind, ns) {
  r <- tryCatch(suppressWarnings(
    switch(kind,
      nodes = {
        s <- xml_find_all(doc, xp, ns)
        # a CDATA section is a text node to XPath, and the document node has no name
        paste(vapply(s, function(n) {
          t <- xml_type(n)
          nm <- xml_name(n)
          if (t == "cdata") { t <- "text"; nm <- "text" }
          if (t == "document") nm <- ""
          paste(t, nm, xml_find_chr(n, "namespace-uri()", ns), xml_text(n), sep = "\u0002")
        }, ""), collapse = "\u0001")
      },
      num = hex(xml_find_num(doc, xp, ns)),
      chr = xml_find_chr(doc, xp, ns),
      lgl = if (xml_find_lgl(doc, xp, ns)) "TRUE" else "FALSE")),
    error = function(e) "ERR")
  if (length(r) == 0 || is.na(r)) "ERR" else r
}

cases <- list()
for (nm in names(docs)) {
  doc <- read_xml(docs[[nm]])
  ns <- xml_ns(doc)
  for (xp in nodes_expr[[nm]]) cases[[length(cases) + 1]] <- case("nodes", numeric(0), ev(doc, xp, "nodes", ns), input = c(docs[[nm]], xp))
  for (kind in c("num", "chr", "lgl")) for (xp in scalar_expr[[nm]][[kind]]) cases[[length(cases) + 1]] <- case(kind, numeric(0), ev(doc, xp, kind, ns), input = c(docs[[nm]], xp))
}

# read_xml on well-formed and malformed documents. xml2's read_xml raises on a malformed one even with
# options = "RECOVER" (it checks the parser's error state), so a malformed document is ERR and a
# well-formed one is compared by the node dump (type, local name, namespace URI, string-value of every
# node and attribute in document order).
parse_docs <- c("<!DOCTYPE a><a>x</a>", "<!DOCTYPE a SYSTEM \"a.dtd\"><a>x</a>", "<!DOCTYPE a PUBLIC \"-//X//Y\" \"a.dtd\"><a><b/></a>", "<!DOCTYPE a [<!ELEMENT a (#PCDATA)>]><a>x</a>", "<?xml version='1.0'?>\n<!DOCTYPE a>\n<a>x</a>", "<!DOCTYPE a><a>&e;</a>", "<a><!DOCTYPE a></a>", "<!DOCTYPE a><!DOCTYPE b><a/>", "<?xml version='1.1'?><a>x</a>", "<?xml version='1.1' encoding='UTF-8'?><a b='1'/>", "<?xml version='2.0'?><a/>", "<?xml version='1.0' encoding='UTF-8' standalone='yes'?><a/>", "<a><b>t</a>","<a><b></a>", "<a><b>x</b>", "<a>x</b></a>", "<a>&foo;</a>", "<a>1 < 2</a>", "<a>1 & 2</a>", "<a b=c>t</a>", "<a b='1' b='2'>t</a>", "<a b>t</a>", "<a><b/><c></a>", "<a><b><c></b></c></a>", "<a>t", "<a", "<a>", "<a/><b/>", "<a></a><b></b>", "<a>x</a>trail", "<?xml version='1.0'?><a>x</a>", "<a><!-- c </a>", "<a><![CDATA[x</a>", "<a><b></B></a>", "<a><1b/></a>", "<a b='1>t</a>", "<a>&#xZZ;</a>", "<a>&#65;&#x42;</a>", "<a>&amp;&lt;&gt;&quot;&apos;</a>", "<a>é</a>", "<a/>", "<a b=\"1\"/>", "<a>x<b/>y</a>", "<a><b>1</b><c>2</c></a>", "<a xmlns:p='u'><p:b/></a>", "<p:a/>", "<a><p:b xmlns:p='u'/></a>", "<a:b:c/>", "<a><b></a></b>", "<a></b>", "</a>", "<a><b>", "<a b='1' c=\"2\" d=3>x</a>", "<a >x</a >", "<a\n b='1'\n>x</a>", "<a><?pi?></a>", "<a><?pi x y?></a>", "<a>x]]>y</a>", "<a>\u0001</a>", "<a/ >", "<a b=''/>", "<a><b/>  <c/></a>", "<a> <b/> </a>", "<a>\n<b>x</b>\n</a>", "<a>  text  </a>", "<a><b> </b></a>", "<a>x<![CDATA[<y>]]>z</a>", "<a><![CDATA[]]></a>", "<a>&#0;</a>", "<a>&#x10FFFF;</a>", "<a>&#xD800;</a>", "<a b='&lt;&amp;'/>", "<a b='x\ty\nz'/>", "<a b=\"a'b\"/>", "<a b='a\"b'/>", "<a xmlns='u'><b/></a>", "<a xmlns='u' xmlns:p='v'><p:b p:c='1'/></a>", "<p:a xmlns:p='u'/>", "<p:a xmlns:q='u'/>", "<a xmlns:p=''/>", "<a xml:lang='en'/>", "<a xmlns:xml='http://www.w3.org/XML/1998/namespace'/>", "<a xmlns='u'><b xmlns=''/></a>", "<a><b/></a><!-- c -->", "<!-- c --><a/>", "<?pi x?><a/>", "<a/><?pi x?>", "<a/>  ", "  <a/>", "\n<a/>\n", "<?xml version='1.0' encoding='UTF-8'?><a/>", "<?xml version='1.0' encoding='ISO-8859-1'?><a>é</a>", "<?xml version='2.0'?><a/>", "<?xml?><a/>", "<a><!--x--y--></a>", "<a><!----></a>", "<a><?xml x?></a>", "<a b='1' B='2'/>", "<A/>", "<a><A/></a>", "<a_b-c.d/>", "<é/>", "<a b:c='1'/>", "<a xmlns:b='u' b:c='1' b:c='2'/>", "<a xmlns:b='u' xmlns:c='u' b:c='1' c:c='2'/>", "<a><b><c><d><e/></d></c></b></a>", "<a>\r\n</a>", "<a>x\ry</a>", "<a b='x\ry'/>")
# The second pass reads every document with options = RECOVER too: xml2 still raises, so a malformed
# document stays ERR and recovery is not part of xml2's read_xml.
for (k in seq_len(2 * length(parse_docs))) {
  d <- parse_docs[(k - 1) %% length(parse_docs) + 1]
  opts <- if (k > length(parse_docs)) c("RECOVER", "NOBLANKS") else "NOBLANKS"
  r <- tryCatch(suppressWarnings({
    doc <- read_xml(d, options = opts)
    ns <- xml_ns(doc)
    s <- xml_find_all(doc, "//node() | //@*", ns)
    paste(vapply(s, function(n) {
      t <- xml_type(n)
      nm <- xml_name(n)
      if (t == "cdata") { t <- "text"; nm <- "text" }
      tx <- xml_text(n)
      if (is.na(tx)) tx <- ""
      paste(t, nm, xml_find_chr(n, "namespace-uri()", ns), tx, sep = "\u0002")
    }, ""), collapse = "\u0001")
  }), error = function(e) "ERR")
  cases[[length(cases) + 1]] <- case("nodes", numeric(0), r, input = c(d, "//node() | //@*"))
}
doc_num <- read_xml("<n/>")
for (s in numstr) {
  e <- paste0("number('", s, "')")
  cases[[length(cases) + 1]] <- case("num", numeric(0), ev(doc_num, e, "num", xml_ns(doc_num)), input = c("<n/>", e))
}
for (s in literals) {
  e <- paste0("string(", s, ")")
  cases[[length(cases) + 1]] <- case("chr", numeric(0), ev(doc_num, e, "chr", xml_ns(doc_num)), input = c("<n/>", e))
  e <- paste0("number(", s, ")")
  cases[[length(cases) + 1]] <- case("num", numeric(0), ev(doc_num, e, "num", xml_ns(doc_num)), input = c("<n/>", e))
}

emit("xml2", "xml2", list(cases))
