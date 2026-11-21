# xml2::read_html (libxml2's HTML 4 parser, which recovers from everything): the node dump of the
# tree it builds for ill-formed markup -- implied html/head/body, paragraphs closed by blocks, list and
# table rows closed by their siblings, unmatched end tags, entities, boolean attributes. A case holds
# the markup ("in") and the dump: every node and attribute in document order as
# type, name, string-value and parent element name joined by U+0002, records joined by U+0001 (a CDATA node, which is a
# script or style body here, is written as text). oracle_xml2_html checks it against e.fmt.html4, the libxml2 tree builder
# (e.fmt.html is the WHATWG one and builds different trees).
library(xml2)

docs <- c("<p>one<p>two<b>bold<i>it</b>x", "<html><head><title>T</title></head><body><p>a</p></body></html>", "<b>x</b>", "<ul><li>a<li>b</ul>", "<table><tr><td>a<td>b<tr><td>c</table>", "<div><p>a<div>b</div></p></div>", "<a href=x>l</a>", "<a href=\"x\" href=\"y\">l</a>", "<br><br/>t", "<img src=a.png alt=b>", "<script>if (a<b) {}</script>", "<style>p{color:red}</style><p>x", "<!-- c --><p>x", "<p>a &amp; b &lt; c &foo; &#65; &nbsp;</p>", "<P CLASS=A>x</P>", "<div id=a class='b c'>t</div>", "<title>t</title><p>x", "<head><meta charset=utf-8></head><body>x", "<p>a<br>b</p>", "<select><option>a<option>b</select>", "<dl><dt>a<dd>b<dt>c</dl>", "<h1>a<h2>b</h1>", "<form><input name=a><input name=b></form>", "<p>x</div>y", "</p>x", "<a><b></a></b>", "<td>x</td>", "<tr><td>x", "<span><div>x</div></span>", "<p>a</p>b<p>c</p>", "<body onload=x>t", "<html><body>a</body></html>trail", "<?xml version='1.0'?><p>x", "<!DOCTYPE html><html><body>x</body></html>", "<textarea><b>x</b></textarea>", "<pre>\nx\n y</pre>", "<p>é日</p>", "<input disabled>", "<option selected>x", "<a b>t</a>", "<p/>", "<div/>x", "<ol start=2><li>x</ol>",
  "<p>a<p>b<p>c", "<ul><li>a<ul><li>b</ul><li>c</ul>", "<table><tr><td>a</table>x", "<table><thead><tr><th>h<tbody><tr><td>d</table>", "<div><span>a</div>b", "<b><i>x</b>y</i>", "<p><div>x</div></p>", "<h1><p>x</h1>", "<a href=1><a href=2>x</a></a>", "<form><form>x</form></form>", "<li>a<li>b", "<dd>x", "<option>a", "<body><body>x", "<html><html><p>x", "<head><title>a</title></head><head><title>b</title></head>", "<title>x", "<script>a</script>b<script>c</script>", "<img><img>", "<hr>x<hr>", "<input><input>x", "<p>a</p></p>b", "<em>a<p>b</em>c", "<center><p>a</center>b", "<font><p>a</font>", "<table><td>a</table>", "<ul><p>a</ul>", "<select><option>a</select><p>b", "<object><param name=a>x</object>", "<map><area>x</map>", "<br>a</br>b", "<p>1 < 2 and 3 > 2</p>", "<p>a<!-- c -->b</p>", "<p>&lt;&gt;&amp;&quot;&copy;&eacute;&Eacute;&euro;</p>", "<a title=\"a&amp;b\" id=x>y</a>", "<div class=a CLASS=b>x</div>", "<meta http-equiv=a content=b>", "<link rel=a href=b>x", "<base href=a>x", "<frameset><frame src=a></frameset>", "<noscript>x</noscript>", "<iframe>x</iframe>", "<button>a<button>b</button></button>", "<label>a<label>b</label></label>", "<abbr>a</abbr><acronym>b</acronym>", "<tt>a</tt><big>b</big><small>c</small><strike>d</strike><u>e</u>")
# Further cases found by probing libxml2: whitespace judged ignorable or kept, references, bogus markup,
# raw script and style bodies, content after </html>, an unterminated start tag (xml2 raises: ERR).
more <- c(
  "<script>a<script>b</script>",
  "<style>a<style>b</style>",
  "<script>a<noscript>b</noscript>",
  "<style>a<body>b",
  "<title>a<body>b",
  "<html a=1><html b=2 a=3><p>x",
  "<p>a<!foo>b</p>",
  "<p>a<![CDATA[x]]>b</p>",
  "<p>a<?pi x?>b</p>",
  "<p>a<?>b",
  "<body/>x",
  "<p>a &amp b &#x41 &#0; &#xD800; &#1114112; &#65;</p>",
  "<a title=a&b href=x&amp=1 c=\"&lt;&nbsp;&foo;\">x</a>",
  "<!-- c -->",
  "text",
  "a<b>c",
  "<p>  </p>",
  "<ul> <li>a</li> <li>b</li> </ul>",
  "<div> <p>a</p> </div>",
  "<table> <tr> <td>a</td> </tr> </table>",
  "<html> <body> <p>a</p> </body> </html>",
  "<p>a</p>  <!-- c -->  <p>b</p>",
  "<p>a <b>b</b> <i>c</i></p>",
  "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\"><html><body> <p>a</p> </body></html>",
  "<a href=x/>t",
  "<a / href=x>t",
  "<a =x>t",
  "<p>a</p></body></html>x",
  "</html>x",
  "x</html>y",
  "<head></head>x",
  "<html><head></head>y",
  "<p>a</ p>b",
  "</>x",
  "<p>a</p3>b",
  "<a b=\"x>y\" c='z'>t</a>",
  "<a b=\"x>t",
  "<p>a<",
  "<p>a</",
  "<p>a</b",
  "<p>a<b",
  "<p>a<b c",
  "<p>1<2",
  "<p>a<3>b",
  "<p>a<:b>c",
  "<p>x<embed src=a>y",
  "<script>a</scr>b</script>c",
  "<script>a</SCRIPT>c",
  "<script></script>",
  "<script>  </script>",
  "<p>a<script>b</script>c",
  "<head><script>a</script></head><body>b",
  "<html><script>a</script>b",
  "<style>a{}</style><script>b</script>",
  "<noscript><p>a</p></noscript>",
  "<p>a</p><frameset><frame></frameset>",
  "<frameset><noframes>a</noframes></frameset>",
  "<body><p>a<body><p>b",
  "<html><head><title>a</title></head><body bgcolor=red><p>x</body></html><p>y",
  "<tr><td>a<tr><td>b",
  "<table><caption>c<tr><td>x</table>",
  "<select><option>a<optgroup><option>b</select>",
  "<dl><dt>a<dd>b<dd>c<dt>d</dl>",
  "<h1>a<h2>b<h3>c",
  "<a><div>x</div></a>",
  "<p>a<span>b<p>c",
  "<b><p>a</b>b",
  "<li>a<ul><li>b</ul>",
  "<ol><li>a<li>b</ol>",
  "<td>a<td>b",
  "<th>a<th>b",
  "<form><p>a<form>b",
  "<button><button>x",
  "<i><b>a</i></b>",
  "<center>a<center>b",
  "<img src=a><img src=b>x",
  "<hr/><hr>",
  "<ul><li>a<p>b<li>c",
  "<p>a&eacute;&Eacute;&euro;&hearts;&apos;&nbsp;&copy;&zwnj;&OElig;</p>",
  "<p>a&AMP;&Amp;&LT;&lt&gt;</p>",
  "é<p>日本",
  "<script><script>b</script>",
  "<style><style>b</style>",
  "<script><noscript>b</noscript>",
  "<style><body>b",
  "<script>x</script><script><body>b",
  "<head><style><body>b",
  "<html><body><script><noscript>b",
  "<html><body><p><script><p>b",
  "<html><body><script><p>b",
  "<title><body>b",
  "<title><p>b",
  "<title>a<b>c</b>",
  "<table><tr><td> <b>x</b> </td> </tr></table>",
  "<h2> <b>x</b></h2><h3> <b>y</b></h3><h4> <b>z</b></h4><h5> <i>y</i></h5>",
  "",
  " ",
  "\n\n",
  "<p>a</p>\n",
  "<p>a</p>\n\n<p>b</p>\n",
  "<html>\n<head>\n<title>t</title>\n</head>\n<body>\n<p>a</p>\n</body>\n</html>\n",
  "<div>\n  <span>a</span>\n  <span>b</span>\n</div>",
  "<ul>\n<li>a</li>\n<li>b</li>\n</ul>",
  "<pre>  a  </pre>",
  "<p>a\tb</p>",
  "<p>a\001b</p>",
  "<p>é&#233;&#xe9;</p>",
  "<a href=\"a b\">x</a>",
  "<a href='x\"y'>t</a>",
  "<p>a</p><b>",
  "<br><br><br>",
  "<p><br></p>",
  "<table><tr><th>a<th>b<tr><td>1<td>2</table>",
  "<table><tbody><tr><td>a</table>",
  "<p>a<p>b</p>c</p>",
  "<em><em>a</em></em>",
  "<h1>a</h1><h2>b</h2>",
  "<div><div><div>a</div></div></div>",
  "<p>a</p><div>b</div><p>c",
  "<span>a</span> <span>b</span>",
  "<b>a</b> <i>b</i>",
  "<tr><td>a</td> <td>b</td> </tr>",
  "<ol> <li>a</li> </ol>",
  "<dl> <dt>a</dt> <dd>b</dd> </dl>",
  "<select> <option>a</option> </select>",
  "<head> <title>a</title> </head> <body> a </body>")
docs <- c(docs, more)
parent_name <- function(x) {
  if (xml_type(x) == "attribute") return(xml_name(xml_parent(x)))
  p <- xml_parent(x)
  if (inherits(p, "xml_document") || xml_type(p) == "document") "" else xml_name(p)
}
dump <- function(d) {
  n <- xml_find_all(d, "//node() | //@*")
  paste(vapply(n, function(x) {
    t <- xml_type(x)
    nm <- xml_name(x)
    if (t == "cdata") { t <- "text"; nm <- "text" }
    tx <- xml_text(x)
    if (is.na(tx)) tx <- ""
    paste(t, nm, tx, parent_name(x), sep = "\u0002")
  }, ""), collapse = "\u0001")
}
# xml2 takes a string with no "<" for a file name, which is not libxml2's parser: those are left out.
docs <- docs[grepl("<", docs, fixed = TRUE)]
cases <- lapply(docs, function(d) {
  r <- tryCatch(suppressWarnings(dump(read_html(d))), error = function(e) "ERR")
  case("html", numeric(0), r, input = d)
})
emit("xml2_html", "xml2", list(cases))
