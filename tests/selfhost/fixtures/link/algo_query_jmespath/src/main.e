// e.algo.query.jmespath against python-jmespath: field, index, slice, projection, filter, pipe, multi-select,
// literal and function expressions over four documents, hand-written and seeded random, with the expected JSON
// (`E` where python-jmespath raises a JMESPath error). A line is `DOC TAB EXPRESSION TAB EXPECTED`.
use e.algo.query.jmespath
use e.fmt.json
use e.io
use e.mem
use e.os
use e.str

fn field(line: str, index: usize) -> str {
    var at = 0usize
    var current_index = 0usize
    var start = 0usize
    while at <= line.len {
        if at == line.len || line[at] == 9u8 {
            if current_index == index { ret line[start..at] }
            current_index += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    ret ""
}

fn index_of(text: str) -> usize {
    var v = 0usize
    var i = 0usize
    while i < text.len {
        v = v * 10usize + usize(text[i] - 48u8)
        i += 1usize
    }
    ret v
}

// Ordered deep equality, numbers by value: stricter than `equals`, which takes objects as maps.
fn same(x: json.Value, y: json.Value) -> bool {
    let kx = jmespath.kind_of(x)
    if kx != jmespath.kind_of(y) { ret false }
    if kx == 4u8 {
        let ax = jmespath.as_array(x)
        let ay = jmespath.as_array(y)
        if ax.len != ay.len { ret false }
        var i = 0usize
        while i < ax.len {
            if !same(ax[i], ay[i]) { ret false }
            i += 1usize
        }
        ret true
    }
    if kx == 5u8 {
        let ox = jmespath.as_object(x)
        let oy = jmespath.as_object(y)
        if ox.len != oy.len { ret false }
        var j = 0usize
        while j < ox.len {
            if !str.eq(ox[j].key, oy[j].key) { ret false }
            if !same(ox[j].value, oy[j].value) { ret false }
            j += 1usize
        }
        ret true
    }
    ret jmespath.equals(x, y)
}
fn documents() -> str {
    ret "{\"a\": {\"b\": {\"c\": [1, 2, 3, {\"d\": \"x\"}]}}, \"arr\": [1, 2, 3, 4, 5], \"n\": null, \"t\": true, \"f\": false, \"s\": \"hello\", \"people\": [{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}], \"nested\": [[1, 2], [3, [4, 5]], []], \"obj\": {\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}}, \"nums\": [3, 1.5, 2, -4], \"strs\": [\"b\", \"a\", \"c\"], \"empty\": [], \"emptyo\": {}, \"u\": \"h\\u00e9llo w\\u00f6rld\", \"mixed\": [1, \"a\", null, true, [2], {\"k\": 1}], \"num_strs\": [\"10\", \"2.5\", \"x\", \" 7 \", \"-3\"], \"zero\": 0, \"e\": \"\"}\n[{\"id\": 1, \"v\": {\"k\": \"a\", \"n\": 10}}, {\"id\": 2, \"v\": {\"k\": \"b\", \"n\": 20}}, {\"id\": 3, \"v\": {\"k\": \"a\"}}, {\"id\": 4}]\n\"just a string\"\n{\"foo\": [{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}], \"f-g\": 1, \"quoted key\": {\"inner\": [10, 20, 30]}, \"list\": [[1, 2, 3], [4, 5, 6], [7, 8, 9]], \"words\": [\"apple\", \"banana\", \"cherry\", \"date\"], \"wrap\": {\"a\": {\"a\": {\"a\": 1}}}}"
}

fn load_documents(a: *mem.Arena, out: []json.Value) -> err {
    let text = documents()
    var start = 0usize
    var n = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == 10u8 {
            var opts: json.Options = zero
            let (value, parse_error) = json.parse(a, text[start..i], opts)
            if parse_error != ok { ret parse_error }
            out[n] = value
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret ok
}

fn run(a: *mem.Arena, text: str, docs: []const json.Value) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let line = text[start..i]
            let mark = mem.mark(a)
            let (result, run_error) = jmespath.search(a, field(line, 1usize), docs[index_of(field(line, 0usize))])
            let want = field(line, 2usize)
            if str.eq(want, "E") {
                if run_error == ok {
                    let shown = io.print(line)
                    ret 1u8
                }
            } else {
                if run_error != ok {
                    let shown = io.print(line)
                    ret 2u8
                }
                var opts: json.Options = zero
                opts.allow_duplicate_keys = true
                let (expected, expected_error) = json.parse(a, want, opts)
                if expected_error != ok { ret 3u8 }
                if !same(result, expected) {
                    let shown = io.print(line)
                    ret 4u8
                }
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}
fn jmes_vectors_0() -> str {
    ret "0\t@\t{\"a\": {\"b\": {\"c\": [1, 2, 3, {\"d\": \"x\"}]}}, \"arr\": [1, 2, 3, 4, 5], \"n\": null, \"t\": true, \"f\": false, \"s\": \"hello\", \"people\": [{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}], \"nested\": [[1, 2], [3, [4, 5]], []], \"obj\": {\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}}, \"nums\": [3, 1.5, 2, -4], \"strs\": [\"b\", \"a\", \"c\"], \"empty\": [], \"emptyo\": {}, \"u\": \"h\\u00e9llo w\\u00f6rld\", \"mixed\": [1, \"a\", null, true, [2], {\"k\": 1}], \"num_strs\": [\"10\", \"2.5\", \"x\", \" 7 \", \"-3\"], \"zero\": 0, \"e\": \"\"}\n0\ta\t{\"b\": {\"c\": [1, 2, 3, {\"d\": \"x\"}]}}\n0\ta.b\t{\"c\": [1, 2, 3, {\"d\": \"x\"}]}\n0\ta.b.c\t[1, 2, 3, {\"d\": \"x\"}]\n0\ta.b.c[0]\t1\n0\ta.b.c[-1]\t{\"d\": \"x\"}\n0\ta.b.c[3].d\t\"x\"\n0\ta.b.c[5]\tnull\n0\tarr[0]\t1\n0\tarr[-1]\t5\n0\tarr[10]\tnull\n0\tarr[1:3]\t[2, 3]\n0\tarr[:2]\t[1, 2]\n0\tarr[2:]\t[3, 4, 5]\n0\tarr[::2]\t[1, 3, 5]\n0\tarr[::-1]\t[5, 4, 3, 2, 1]\n0\tarr[-2:]\t[4, 5]\n0\tarr[1:4:2]\t[2, 4]\n0\tarr[10:20]\t[]\n0\tarr[3:1]\t[]\n0\tarr[3:0:-1]\t[4, 3, 2]\n0\tarr[-1:-4:-1]\t[5, 4, 3]\n0\tarr[:-1]\t[1, 2, 3, 4]\n0\tarr[::3]\t[1, 4]\n0\tpeople[*].name\t[\"alice\", \"bob\", \"carol\"]\n0\tpeople[].name\t[\"alice\", \"bob\", \"carol\"]\n0\tpeople[*].tags\t[[\"a\", \"b\"], [], [\"c\"]]\n0\tpeople[*].tags[]\t[\"a\", \"b\", \"c\"]\n0\tpeople[*].tags[0]\t[\"a\", \"c\"]\n0\tpeople[0]\t{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}\n0\tpeople[1:].name\t[\"bob\", \"carol\"]\n0\tpeople[?age > `28`].name\t[\"alice\", \"carol\"]\n0\tpeople[?age >= `30`].name\t[\"alice\", \"carol\"]\n0\tpeople[?age < `30`]\t[{\"name\": \"bob\", \"age\": 25, \"tags\": []}]\n0\tpeople[?city].name\t[\"carol\"]\n0\tpeople[?!city].name\t[\"alice\", \"bob\"]\n0\tpeople[?name == 'bob']\t[{\"name\": \"bob\", \"age\": 25, \"tags\": []}]\n0\tpeople[?name != 'bob'].name\t[\"alice\", \"carol\"]\n0\tpeople[?tags[0] == 'a'].name\t[\"alice\"]\n0\tpeople[?age > `20` && age < `32`].name\t[\"alice\", \"bob\"]\n"
}

fn jmes_vectors_1() -> str {
    ret "0\tpeople[?age > `33` || name == 'bob'].name\t[\"bob\", \"carol\"]\n0\tpeople[?contains(tags, 'b')].name\t[\"alice\"]\n0\tpeople[?length(tags) > `0`].name\t[\"alice\", \"carol\"]\n0\tnested[]\t[1, 2, 3, [4, 5]]\n0\tnested[][]\t[1, 2, 3, 4, 5]\n0\tnested[*][0]\t[1, 3]\n0\tnested[0]\t[1, 2]\n0\tnested[1][1]\t[4, 5]\n0\tnested[*]\t[[1, 2], [3, [4, 5]], []]\n0\tnested[1][1][0]\t4\n0\tobj.*\t[1, 2, {\"w\": 3}]\n0\tobj.*.w\t[3]\n0\tobj.z.w\t3\n0\tobj.*.*\t[[3]]\n0\t*\t[{\"b\": {\"c\": [1, 2, 3, {\"d\": \"x\"}]}}, [1, 2, 3, 4, 5], true, false, \"hello\", [{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}], [[1, 2], [3, [4, 5]], []], {\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}}, [3, 1.5, 2, -4], [\"b\", \"a\", \"c\"], [], {}, \"h\\u00e9llo w\\u00f6rld\", [1, \"a\", null, true, [2], {\"k\": 1}], [\"10\", \"2.5\", \"x\", \" 7 \", \"-3\"], 0, \"\"]\n0\t*.x\t[1]\n0\tobj.z.*\t[3]\n0\t[*]\tnull\n0\t[]\tnull\n0\twrap.a.a.a\tnull\n0\tn\tnull\n0\tn.x\tnull\n0\tt\ttrue\n0\tf\tfalse\n0\t!t\tfalse\n0\t!f\ttrue\n0\t!n\ttrue\n0\t!s\tfalse\n0\t!zero\tfalse\n0\t!e\ttrue\n0\t!empty\ttrue\n0\t!arr\tfalse\n0\tzero || arr\t0\n0\tn || s\t\"hello\"\n0\te || n || t\ttrue\n0\tf && t\tfalse\n0\tt && s\t\"hello\"\n0\tn && s\tnull\n0\tempty || emptyo\t{}\n0\ta.b || arr\t{\"c\": [1, 2, 3, {\"d\": \"x\"}]}\n"
}

fn jmes_vectors_2() -> str {
    ret "0\ts || 'x'\t\"hello\"\n0\t[a.b.c[0], arr[1]]\t[1, 2]\n0\t[arr[0], nums[1], n, s]\t[1, 1.5, null, \"hello\"]\n0\t{x: arr[0], y: s}\t{\"x\": 1, \"y\": \"hello\"}\n0\t{\"first\": people[0].name, second: people[1].name}\t{\"first\": \"alice\", \"second\": \"bob\"}\n0\t{a: n, b: t}\t{\"a\": null, \"b\": true}\n0\tpeople[*].{name: name, age: age}\t[{\"name\": \"alice\", \"age\": 30}, {\"name\": \"bob\", \"age\": 25}, {\"name\": \"carol\", \"age\": 35}]\n0\tpeople[*].[name, age]\t[[\"alice\", 30], [\"bob\", 25], [\"carol\", 35]]\n0\tpeople[].{n: name, t: length(tags)}\t[{\"n\": \"alice\", \"t\": 2}, {\"n\": \"bob\", \"t\": 0}, {\"n\": \"carol\", \"t\": 1}]\n0\tobj.{x: x, w: z.w}\t{\"x\": 1, \"w\": 3}\n0\tobj.[x, y]\t[1, 2]\n0\tarr | [0]\t1\n0\tpeople[*].name | [0]\t\"alice\"\n0\tpeople | length(@)\t3\n0\tarr[1:] | [0]\t2\n0\tlength(arr)\t5\n0\tlength(s)\t5\n0\tlength(u)\t11\n0\tlength(obj)\t3\n0\tlength(n)\tE\n0\tlength(zero)\tE\n0\tlength(`\"abc\"`)\t3\n0\tlength(@)\t18\n0\tabs(nums[3])\t4\n0\tabs(nums[0])\t3\n0\tabs(nums[1])\t1.5\n0\tabs(s)\tE\n0\tavg(arr)\t3.0\n0\tavg(nums)\t0.625\n0\tavg(empty)\tnull\n0\tavg(strs)\tE\n0\tsum(arr)\t15\n0\tsum(nums)\t2.5\n0\tsum(empty)\t0\n0\tceil(nums[1])\t2\n0\tfloor(nums[1])\t1\n0\tceil(nums[3])\t-4\n0\tfloor(nums[3])\t-4\n0\tceil(arr[0])\t1\n0\tcontains(arr, `3`)\ttrue\n"
}

fn jmes_vectors_3() -> str {
    ret "0\tcontains(arr, `9`)\tfalse\n0\tcontains(s, 'ell')\ttrue\n0\tcontains(s, 'zzz')\tfalse\n0\tcontains(strs, 'a')\ttrue\n0\tcontains(people, `1`)\tfalse\n0\tstarts_with(s, 'he')\ttrue\n0\tstarts_with(s, 'lo')\tfalse\n0\tends_with(s, 'llo')\ttrue\n0\tends_with(s, 'he')\tfalse\n0\tends_with(s, 'hello world')\tfalse\n0\tjoin(', ', strs)\t\"b, a, c\"\n0\tjoin('', strs)\t\"bac\"\n0\tjoin('-', empty)\t\"\"\n0\tjoin(',', arr)\tE\n0\tkeys(obj)\t[\"x\", \"y\", \"z\"]\n0\tvalues(obj)\t[1, 2, {\"w\": 3}]\n0\tkeys(emptyo)\t[]\n0\tkeys(arr)\tE\n0\tmap(&name, people)\t[\"alice\", \"bob\", \"carol\"]\n0\tmap(&age, people)\t[30, 25, 35]\n0\tmap(&length(@), people[*].tags)\t[2, 0, 1]\n0\tmap(&[name], people)\t[[\"alice\"], [\"bob\"], [\"carol\"]]\n0\tmax(arr)\t5\n0\tmin(arr)\t1\n0\tmax(nums)\t3\n0\tmin(nums)\t-4\n0\tmax(strs)\t\"c\"\n0\tmin(strs)\t\"a\"\n0\tmax(empty)\tnull\n0\tmax(mixed)\tE\n0\tmax_by(people, &age).name\t\"carol\"\n0\tmin_by(people, &age).name\t\"bob\"\n0\tmax_by(people, &name).age\t35\n0\tmin_by(people, &name).age\t30\n0\tmax_by(empty, &a)\tnull\n0\tmerge(obj, {extra: `1`})\t{\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}, \"extra\": 1}\n0\tmerge(obj, obj.z)\t{\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}, \"w\": 3}\n0\tmerge({a: `1`, b: `2`}, {b: `3`, c: `4`})\t{\"a\": 1, \"b\": 3, \"c\": 4}\n0\tmerge(@)\t{\"a\": {\"b\": {\"c\": [1, 2, 3, {\"d\": \"x\"}]}}, \"arr\": [1, 2, 3, 4, 5], \"n\": null, \"t\": true, \"f\": false, \"s\": \"hello\", \"people\": [{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}], \"nested\": [[1, 2], [3, [4, 5]], []], \"obj\": {\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}}, \"nums\": [3, 1.5, 2, -4], \"strs\": [\"b\", \"a\", \"c\"], \"empty\": [], \"emptyo\": {}, \"u\": \"h\\u00e9llo w\\u00f6rld\", \"mixed\": [1, \"a\", null, true, [2], {\"k\": 1}], \"num_strs\": [\"10\", \"2.5\", \"x\", \" 7 \", \"-3\"], \"zero\": 0, \"e\": \"\"}\n0\tnot_null(n, s)\t\"hello\"\n"
}

fn jmes_vectors_4() -> str {
    ret "0\tnot_null(n, n)\tnull\n0\tnot_null(n, zero, s)\t0\n0\treverse(arr)\t[5, 4, 3, 2, 1]\n0\treverse(s)\t\"olleh\"\n0\treverse(u)\t\"dlr\\u00f6w oll\\u00e9h\"\n0\treverse(empty)\t[]\n0\treverse(obj)\tE\n0\tsort(nums)\t[-4, 1.5, 2, 3]\n0\tsort(strs)\t[\"a\", \"b\", \"c\"]\n0\tsort(arr)\t[1, 2, 3, 4, 5]\n0\tsort(mixed)\tE\n0\tsort(empty)\t[]\n0\tsort_by(people, &age)[*].name\t[\"bob\", \"alice\", \"carol\"]\n0\tsort_by(people, &name)[*].age\t[30, 25, 35]\n0\tsort_by(people, &city)\tE\n0\tsort_by(empty, &a)\t[]\n0\tto_array(s)\t[\"hello\"]\n0\tto_array(arr)\t[1, 2, 3, 4, 5]\n0\tto_array(n)\t[null]\n0\tto_string(arr)\t\"[1,2,3,4,5]\"\n0\tto_string(obj)\t\"{\\\"x\\\":1,\\\"y\\\":2,\\\"z\\\":{\\\"w\\\":3}}\"\n0\tto_string(s)\t\"hello\"\n0\tto_string(zero)\t\"0\"\n0\tto_string(t)\t\"true\"\n0\tto_string(n)\t\"null\"\n0\tto_string(u)\t\"h\\u00e9llo w\\u00f6rld\"\n0\tto_string(people[0])\t\"{\\\"name\\\":\\\"alice\\\",\\\"age\\\":30,\\\"tags\\\":[\\\"a\\\",\\\"b\\\"]}\"\n0\tto_number(num_strs[0])\t10\n0\tto_number(num_strs[1])\t2.5\n0\tto_number(num_strs[2])\tnull\n0\tto_number(num_strs[3])\t7\n0\tto_number(num_strs[4])\t-3\n0\tto_number(arr)\tnull\n0\tto_number(n)\tnull\n0\tto_number(t)\tnull\n0\tto_number(zero)\t0\n0\tnum_strs[].to_number(@)\t[10, 2.5, 7, -3]\n0\tmap(&to_number(@), num_strs)\t[10, 2.5, null, 7, -3]\n0\ttype(arr)\t\"array\"\n0\ttype(s)\t\"string\"\n"
}

fn jmes_vectors_5() -> str {
    ret "0\ttype(n)\t\"null\"\n0\ttype(t)\t\"boolean\"\n0\ttype(zero)\t\"number\"\n0\ttype(obj)\t\"object\"\n0\ttype(nums[1])\t\"number\"\n0\ttype(missing)\t\"null\"\n0\tunknown(arr)\tE\n0\tlength()\tE\n0\tlength(arr, arr)\tE\n0\tabs()\tE\n0\tsort_by(people)\tE\n0\tmap(arr, people)\tE\n0\tmax_by(people, name)\tE\n0\tpeople[?age > `28`] | [*].name\t[\"alice\", \"carol\"]\n0\tpeople[?age > `28`].{n: name}\t[{\"n\": \"alice\"}, {\"n\": \"carol\"}]\n0\t`[1,2,3]`\t[1, 2, 3]\n0\t`{\"a\": 1}`\t{\"a\": 1}\n0\t`\"str\"`\t\"str\"\n0\t`true`\ttrue\n0\t`null`\tnull\n0\t`1.5`\t1.5\n0\t`[1, 2, {\"a\": [3]}]`\t[1, 2, {\"a\": [3]}]\n0\t'raw string'\t\"raw string\"\n0\t'it\\'s'\t\"it's\"\n0\t\"quoted key\"\tnull\n0\t\"quoted key\".inner\tnull\n0\t\"f-g\"\tnull\n0\tfoo[*].bar[*].baz\tnull\n0\tfoo[].bar[].baz\tnull\n0\tfoo[*].bar[0].baz\tnull\n0\tfoo[0].bar[1].baz\tnull\n0\tfoo[?bar[0].baz == `1`]\tnull\n0\tlist[*][1]\tnull\n0\tlist[][1]\tnull\n0\tlist[1][1:]\tnull\n0\tlist[::2][0]\tnull\n0\tlist[0:2][0]\tnull\n0\tlist[0:2][*][0]\tnull\n0\twords[?starts_with(@, 'b')]\tnull\n0\twords[?length(@) > `4`]\tnull\n"
}

fn jmes_vectors_6() -> str {
    ret "0\twords[1:3]\tnull\n0\twords[-2:]\tnull\n0\tsort_by(words, &length(@))\tE\n0\tmax_by(words, &length(@))\tE\n0\twords | sort(@) | reverse(@) | [0]\tE\n0\t[words[0], words[-1]] | join('-', @)\tE\n0\tfoo[*].bar[?baz == `1`]\tnull\n0\tfoo[*].bar[?baz].baz | []\tnull\n0\tfoo[?length(bar) > `0`] | length(@)\tE\n0\t\tE\n0\ta.\tE\n0\t.a\tE\n0\ta[\tE\n0\ta[]]\tE\n0\ta..b\tE\n0\ta[0\tE\n0\t[a,\tE\n0\t{a:}\tE\n0\t{a b}\tE\n0\ta ||\tE\n0\t| a\tE\n0\ta b\tE\n0\t(a\tE\n0\t`not json`\t\"not json\"\n0\t\"unterminated\tE\n0\t'unterminated\tE\n0\ta[?]\tE\n0\ta[?b\tE\n0\ta.[\tE\n0\ta.{\tE\n0\ta[1:2:3:4]\tE\n0\ta[1:x]\tE\n0\t1\tE\n0\t-\tE\n0\ta == \tE\n0\ta.&b\tE\n0\t*.\tE\n0\ta !b\tE\n0\ta[*\tE\n0\t@@\tE\n"
}

fn jmes_vectors_7() -> str {
    ret "0\t=\tE\n0\ta = b\tE\n0\t[?a]\tnull\n0\ta.1\tE\n0\ta[-]\tE\n1\t@\t[{\"id\": 1, \"v\": {\"k\": \"a\", \"n\": 10}}, {\"id\": 2, \"v\": {\"k\": \"b\", \"n\": 20}}, {\"id\": 3, \"v\": {\"k\": \"a\"}}, {\"id\": 4}]\n1\ta\tnull\n1\ta.b\tnull\n1\ta.b.c\tnull\n1\ta.b.c[0]\tnull\n1\ta.b.c[-1]\tnull\n1\ta.b.c[3].d\tnull\n1\ta.b.c[5]\tnull\n1\tarr[0]\tnull\n1\tarr[-1]\tnull\n1\tarr[10]\tnull\n1\tarr[1:3]\tnull\n1\tarr[:2]\tnull\n1\tarr[2:]\tnull\n1\tarr[::2]\tnull\n1\tarr[::-1]\tnull\n1\tarr[-2:]\tnull\n1\tarr[1:4:2]\tnull\n1\tarr[10:20]\tnull\n1\tarr[3:1]\tnull\n1\tarr[3:0:-1]\tnull\n1\tarr[-1:-4:-1]\tnull\n1\tarr[:-1]\tnull\n1\tarr[::3]\tnull\n1\tpeople[*].name\tnull\n1\tpeople[].name\tnull\n1\tpeople[*].tags\tnull\n1\tpeople[*].tags[]\tnull\n1\tpeople[*].tags[0]\tnull\n1\tpeople[0]\tnull\n1\tpeople[1:].name\tnull\n1\tpeople[?age > `28`].name\tnull\n1\tpeople[?age >= `30`].name\tnull\n1\tpeople[?age < `30`]\tnull\n1\tpeople[?city].name\tnull\n"
}

fn jmes_vectors_8() -> str {
    ret "1\tpeople[?!city].name\tnull\n1\tpeople[?name == 'bob']\tnull\n1\tpeople[?name != 'bob'].name\tnull\n1\tpeople[?tags[0] == 'a'].name\tnull\n1\tpeople[?age > `20` && age < `32`].name\tnull\n1\tpeople[?age > `33` || name == 'bob'].name\tnull\n1\tpeople[?contains(tags, 'b')].name\tnull\n1\tpeople[?length(tags) > `0`].name\tnull\n1\tnested[]\tnull\n1\tnested[][]\tnull\n1\tnested[*][0]\tnull\n1\tnested[0]\tnull\n1\tnested[1][1]\tnull\n1\tnested[*]\tnull\n1\tnested[1][1][0]\tnull\n1\tobj.*\tnull\n1\tobj.*.w\tnull\n1\tobj.z.w\tnull\n1\tobj.*.*\tnull\n1\t*\tnull\n1\t*.x\tnull\n1\tobj.z.*\tnull\n1\t[*]\t[{\"id\": 1, \"v\": {\"k\": \"a\", \"n\": 10}}, {\"id\": 2, \"v\": {\"k\": \"b\", \"n\": 20}}, {\"id\": 3, \"v\": {\"k\": \"a\"}}, {\"id\": 4}]\n1\t[]\t[{\"id\": 1, \"v\": {\"k\": \"a\", \"n\": 10}}, {\"id\": 2, \"v\": {\"k\": \"b\", \"n\": 20}}, {\"id\": 3, \"v\": {\"k\": \"a\"}}, {\"id\": 4}]\n1\twrap.a.a.a\tnull\n1\tn\tnull\n1\tn.x\tnull\n1\tt\tnull\n1\tf\tnull\n1\t!t\ttrue\n1\t!f\ttrue\n1\t!n\ttrue\n1\t!s\ttrue\n1\t!zero\ttrue\n1\t!e\ttrue\n1\t!empty\ttrue\n1\t!arr\ttrue\n1\tzero || arr\tnull\n1\tn || s\tnull\n1\te || n || t\tnull\n"
}

fn jmes_vectors_9() -> str {
    ret "1\tf && t\tnull\n1\tt && s\tnull\n1\tn && s\tnull\n1\tempty || emptyo\tnull\n1\ta.b || arr\tnull\n1\ts || 'x'\t\"x\"\n1\t[a.b.c[0], arr[1]]\t[null, null]\n1\t[arr[0], nums[1], n, s]\t[null, null, null, null]\n1\t{x: arr[0], y: s}\t{\"x\": null, \"y\": null}\n1\t{\"first\": people[0].name, second: people[1].name}\t{\"first\": null, \"second\": null}\n1\t{a: n, b: t}\t{\"a\": null, \"b\": null}\n1\tpeople[*].{name: name, age: age}\tnull\n1\tpeople[*].[name, age]\tnull\n1\tpeople[].{n: name, t: length(tags)}\tnull\n1\tobj.{x: x, w: z.w}\tnull\n1\tobj.[x, y]\tnull\n1\tarr | [0]\tnull\n1\tpeople[*].name | [0]\tnull\n1\tpeople | length(@)\tE\n1\tarr[1:] | [0]\tnull\n1\tlength(arr)\tE\n1\tlength(s)\tE\n1\tlength(u)\tE\n1\tlength(obj)\tE\n1\tlength(n)\tE\n1\tlength(zero)\tE\n1\tlength(`\"abc\"`)\t3\n1\tlength(@)\t4\n1\tabs(nums[3])\tE\n1\tabs(nums[0])\tE\n1\tabs(nums[1])\tE\n1\tabs(s)\tE\n1\tavg(arr)\tE\n1\tavg(nums)\tE\n1\tavg(empty)\tE\n1\tavg(strs)\tE\n1\tsum(arr)\tE\n1\tsum(nums)\tE\n1\tsum(empty)\tE\n1\tceil(nums[1])\tE\n"
}

fn jmes_vectors_10() -> str {
    ret "1\tfloor(nums[1])\tE\n1\tceil(nums[3])\tE\n1\tfloor(nums[3])\tE\n1\tceil(arr[0])\tE\n1\tcontains(arr, `3`)\tE\n1\tcontains(arr, `9`)\tE\n1\tcontains(s, 'ell')\tE\n1\tcontains(s, 'zzz')\tE\n1\tcontains(strs, 'a')\tE\n1\tcontains(people, `1`)\tE\n1\tstarts_with(s, 'he')\tE\n1\tstarts_with(s, 'lo')\tE\n1\tends_with(s, 'llo')\tE\n1\tends_with(s, 'he')\tE\n1\tends_with(s, 'hello world')\tE\n1\tjoin(', ', strs)\tE\n1\tjoin('', strs)\tE\n1\tjoin('-', empty)\tE\n1\tjoin(',', arr)\tE\n1\tkeys(obj)\tE\n1\tvalues(obj)\tE\n1\tkeys(emptyo)\tE\n1\tkeys(arr)\tE\n1\tmap(&name, people)\tE\n1\tmap(&age, people)\tE\n1\tmap(&length(@), people[*].tags)\tE\n1\tmap(&[name], people)\tE\n1\tmax(arr)\tE\n1\tmin(arr)\tE\n1\tmax(nums)\tE\n1\tmin(nums)\tE\n1\tmax(strs)\tE\n1\tmin(strs)\tE\n1\tmax(empty)\tE\n1\tmax(mixed)\tE\n1\tmax_by(people, &age).name\tE\n1\tmin_by(people, &age).name\tE\n1\tmax_by(people, &name).age\tE\n1\tmin_by(people, &name).age\tE\n1\tmax_by(empty, &a)\tE\n"
}

fn jmes_vectors_11() -> str {
    ret "1\tmerge(obj, {extra: `1`})\tE\n1\tmerge(obj, obj.z)\tE\n1\tmerge({a: `1`, b: `2`}, {b: `3`, c: `4`})\t{\"a\": 1, \"b\": 3, \"c\": 4}\n1\tmerge(@)\tE\n1\tnot_null(n, s)\tnull\n1\tnot_null(n, n)\tnull\n1\tnot_null(n, zero, s)\tnull\n1\treverse(arr)\tE\n1\treverse(s)\tE\n1\treverse(u)\tE\n1\treverse(empty)\tE\n1\treverse(obj)\tE\n1\tsort(nums)\tE\n1\tsort(strs)\tE\n1\tsort(arr)\tE\n1\tsort(mixed)\tE\n1\tsort(empty)\tE\n1\tsort_by(people, &age)[*].name\tE\n1\tsort_by(people, &name)[*].age\tE\n1\tsort_by(people, &city)\tE\n1\tsort_by(empty, &a)\tE\n1\tto_array(s)\t[null]\n1\tto_array(arr)\t[null]\n1\tto_array(n)\t[null]\n1\tto_string(arr)\t\"null\"\n1\tto_string(obj)\t\"null\"\n1\tto_string(s)\t\"null\"\n1\tto_string(zero)\t\"null\"\n1\tto_string(t)\t\"null\"\n1\tto_string(n)\t\"null\"\n1\tto_string(u)\t\"null\"\n1\tto_string(people[0])\t\"null\"\n1\tto_number(num_strs[0])\tnull\n1\tto_number(num_strs[1])\tnull\n1\tto_number(num_strs[2])\tnull\n1\tto_number(num_strs[3])\tnull\n1\tto_number(num_strs[4])\tnull\n1\tto_number(arr)\tnull\n1\tto_number(n)\tnull\n1\tto_number(t)\tnull\n"
}

fn jmes_vectors_12() -> str {
    ret "1\tto_number(zero)\tnull\n1\tnum_strs[].to_number(@)\tnull\n1\tmap(&to_number(@), num_strs)\tE\n1\ttype(arr)\t\"null\"\n1\ttype(s)\t\"null\"\n1\ttype(n)\t\"null\"\n1\ttype(t)\t\"null\"\n1\ttype(zero)\t\"null\"\n1\ttype(obj)\t\"null\"\n1\ttype(nums[1])\t\"null\"\n1\ttype(missing)\t\"null\"\n1\tunknown(arr)\tE\n1\tlength()\tE\n1\tlength(arr, arr)\tE\n1\tabs()\tE\n1\tsort_by(people)\tE\n1\tmap(arr, people)\tE\n1\tmax_by(people, name)\tE\n1\tpeople[?age > `28`] | [*].name\tnull\n1\tpeople[?age > `28`].{n: name}\tnull\n1\t`[1,2,3]`\t[1, 2, 3]\n1\t`{\"a\": 1}`\t{\"a\": 1}\n1\t`\"str\"`\t\"str\"\n1\t`true`\ttrue\n1\t`null`\tnull\n1\t`1.5`\t1.5\n1\t`[1, 2, {\"a\": [3]}]`\t[1, 2, {\"a\": [3]}]\n1\t'raw string'\t\"raw string\"\n1\t'it\\'s'\t\"it's\"\n1\t\"quoted key\"\tnull\n1\t\"quoted key\".inner\tnull\n1\t\"f-g\"\tnull\n1\tfoo[*].bar[*].baz\tnull\n1\tfoo[].bar[].baz\tnull\n1\tfoo[*].bar[0].baz\tnull\n1\tfoo[0].bar[1].baz\tnull\n1\tfoo[?bar[0].baz == `1`]\tnull\n1\tlist[*][1]\tnull\n1\tlist[][1]\tnull\n1\tlist[1][1:]\tnull\n"
}

fn jmes_vectors_13() -> str {
    ret "1\tlist[::2][0]\tnull\n1\tlist[0:2][0]\tnull\n1\tlist[0:2][*][0]\tnull\n1\twords[?starts_with(@, 'b')]\tnull\n1\twords[?length(@) > `4`]\tnull\n1\twords[1:3]\tnull\n1\twords[-2:]\tnull\n1\tsort_by(words, &length(@))\tE\n1\tmax_by(words, &length(@))\tE\n1\twords | sort(@) | reverse(@) | [0]\tE\n1\t[words[0], words[-1]] | join('-', @)\tE\n1\tfoo[*].bar[?baz == `1`]\tnull\n1\tfoo[*].bar[?baz].baz | []\tnull\n1\tfoo[?length(bar) > `0`] | length(@)\tE\n1\t\tE\n1\ta.\tE\n1\t.a\tE\n1\ta[\tE\n1\ta[]]\tE\n1\ta..b\tE\n1\ta[0\tE\n1\t[a,\tE\n1\t{a:}\tE\n1\t{a b}\tE\n1\ta ||\tE\n1\t| a\tE\n1\ta b\tE\n1\t(a\tE\n1\t`not json`\t\"not json\"\n1\t\"unterminated\tE\n1\t'unterminated\tE\n1\ta[?]\tE\n1\ta[?b\tE\n1\ta.[\tE\n1\ta.{\tE\n1\ta[1:2:3:4]\tE\n1\ta[1:x]\tE\n1\t1\tE\n1\t-\tE\n1\ta == \tE\n"
}

fn jmes_vectors_14() -> str {
    ret "1\ta.&b\tE\n1\t*.\tE\n1\ta !b\tE\n1\ta[*\tE\n1\t@@\tE\n1\t=\tE\n1\ta = b\tE\n1\t[?a]\t[]\n1\ta.1\tE\n1\ta[-]\tE\n2\t@\t\"just a string\"\n2\ta\tnull\n2\ta.b\tnull\n2\ta.b.c\tnull\n2\ta.b.c[0]\tnull\n2\ta.b.c[-1]\tnull\n2\ta.b.c[3].d\tnull\n2\ta.b.c[5]\tnull\n2\tarr[0]\tnull\n2\tarr[-1]\tnull\n2\tarr[10]\tnull\n2\tarr[1:3]\tnull\n2\tarr[:2]\tnull\n2\tarr[2:]\tnull\n2\tarr[::2]\tnull\n2\tarr[::-1]\tnull\n2\tarr[-2:]\tnull\n2\tarr[1:4:2]\tnull\n2\tarr[10:20]\tnull\n2\tarr[3:1]\tnull\n2\tarr[3:0:-1]\tnull\n2\tarr[-1:-4:-1]\tnull\n2\tarr[:-1]\tnull\n2\tarr[::3]\tnull\n2\tpeople[*].name\tnull\n2\tpeople[].name\tnull\n2\tpeople[*].tags\tnull\n2\tpeople[*].tags[]\tnull\n2\tpeople[*].tags[0]\tnull\n2\tpeople[0]\tnull\n"
}

fn jmes_vectors_15() -> str {
    ret "2\tpeople[1:].name\tnull\n2\tpeople[?age > `28`].name\tnull\n2\tpeople[?age >= `30`].name\tnull\n2\tpeople[?age < `30`]\tnull\n2\tpeople[?city].name\tnull\n2\tpeople[?!city].name\tnull\n2\tpeople[?name == 'bob']\tnull\n2\tpeople[?name != 'bob'].name\tnull\n2\tpeople[?tags[0] == 'a'].name\tnull\n2\tpeople[?age > `20` && age < `32`].name\tnull\n2\tpeople[?age > `33` || name == 'bob'].name\tnull\n2\tpeople[?contains(tags, 'b')].name\tnull\n2\tpeople[?length(tags) > `0`].name\tnull\n2\tnested[]\tnull\n2\tnested[][]\tnull\n2\tnested[*][0]\tnull\n2\tnested[0]\tnull\n2\tnested[1][1]\tnull\n2\tnested[*]\tnull\n2\tnested[1][1][0]\tnull\n2\tobj.*\tnull\n2\tobj.*.w\tnull\n2\tobj.z.w\tnull\n2\tobj.*.*\tnull\n2\t*\tnull\n2\t*.x\tnull\n2\tobj.z.*\tnull\n2\t[*]\tnull\n2\t[]\tnull\n2\twrap.a.a.a\tnull\n2\tn\tnull\n2\tn.x\tnull\n2\tt\tnull\n2\tf\tnull\n2\t!t\ttrue\n2\t!f\ttrue\n2\t!n\ttrue\n2\t!s\ttrue\n2\t!zero\ttrue\n2\t!e\ttrue\n"
}

fn jmes_vectors_16() -> str {
    ret "2\t!empty\ttrue\n2\t!arr\ttrue\n2\tzero || arr\tnull\n2\tn || s\tnull\n2\te || n || t\tnull\n2\tf && t\tnull\n2\tt && s\tnull\n2\tn && s\tnull\n2\tempty || emptyo\tnull\n2\ta.b || arr\tnull\n2\ts || 'x'\t\"x\"\n2\t[a.b.c[0], arr[1]]\t[null, null]\n2\t[arr[0], nums[1], n, s]\t[null, null, null, null]\n2\t{x: arr[0], y: s}\t{\"x\": null, \"y\": null}\n2\t{\"first\": people[0].name, second: people[1].name}\t{\"first\": null, \"second\": null}\n2\t{a: n, b: t}\t{\"a\": null, \"b\": null}\n2\tpeople[*].{name: name, age: age}\tnull\n2\tpeople[*].[name, age]\tnull\n2\tpeople[].{n: name, t: length(tags)}\tnull\n2\tobj.{x: x, w: z.w}\tnull\n2\tobj.[x, y]\tnull\n2\tarr | [0]\tnull\n2\tpeople[*].name | [0]\tnull\n2\tpeople | length(@)\tE\n2\tarr[1:] | [0]\tnull\n2\tlength(arr)\tE\n2\tlength(s)\tE\n2\tlength(u)\tE\n2\tlength(obj)\tE\n2\tlength(n)\tE\n2\tlength(zero)\tE\n2\tlength(`\"abc\"`)\t3\n2\tlength(@)\t13\n2\tabs(nums[3])\tE\n2\tabs(nums[0])\tE\n2\tabs(nums[1])\tE\n2\tabs(s)\tE\n2\tavg(arr)\tE\n2\tavg(nums)\tE\n2\tavg(empty)\tE\n"
}

fn jmes_vectors_17() -> str {
    ret "2\tavg(strs)\tE\n2\tsum(arr)\tE\n2\tsum(nums)\tE\n2\tsum(empty)\tE\n2\tceil(nums[1])\tE\n2\tfloor(nums[1])\tE\n2\tceil(nums[3])\tE\n2\tfloor(nums[3])\tE\n2\tceil(arr[0])\tE\n2\tcontains(arr, `3`)\tE\n2\tcontains(arr, `9`)\tE\n2\tcontains(s, 'ell')\tE\n2\tcontains(s, 'zzz')\tE\n2\tcontains(strs, 'a')\tE\n2\tcontains(people, `1`)\tE\n2\tstarts_with(s, 'he')\tE\n2\tstarts_with(s, 'lo')\tE\n2\tends_with(s, 'llo')\tE\n2\tends_with(s, 'he')\tE\n2\tends_with(s, 'hello world')\tE\n2\tjoin(', ', strs)\tE\n2\tjoin('', strs)\tE\n2\tjoin('-', empty)\tE\n2\tjoin(',', arr)\tE\n2\tkeys(obj)\tE\n2\tvalues(obj)\tE\n2\tkeys(emptyo)\tE\n2\tkeys(arr)\tE\n2\tmap(&name, people)\tE\n2\tmap(&age, people)\tE\n2\tmap(&length(@), people[*].tags)\tE\n2\tmap(&[name], people)\tE\n2\tmax(arr)\tE\n2\tmin(arr)\tE\n2\tmax(nums)\tE\n2\tmin(nums)\tE\n2\tmax(strs)\tE\n2\tmin(strs)\tE\n2\tmax(empty)\tE\n2\tmax(mixed)\tE\n"
}

fn jmes_vectors_18() -> str {
    ret "2\tmax_by(people, &age).name\tE\n2\tmin_by(people, &age).name\tE\n2\tmax_by(people, &name).age\tE\n2\tmin_by(people, &name).age\tE\n2\tmax_by(empty, &a)\tE\n2\tmerge(obj, {extra: `1`})\tE\n2\tmerge(obj, obj.z)\tE\n2\tmerge({a: `1`, b: `2`}, {b: `3`, c: `4`})\t{\"a\": 1, \"b\": 3, \"c\": 4}\n2\tmerge(@)\tE\n2\tnot_null(n, s)\tnull\n2\tnot_null(n, n)\tnull\n2\tnot_null(n, zero, s)\tnull\n2\treverse(arr)\tE\n2\treverse(s)\tE\n2\treverse(u)\tE\n2\treverse(empty)\tE\n2\treverse(obj)\tE\n2\tsort(nums)\tE\n2\tsort(strs)\tE\n2\tsort(arr)\tE\n2\tsort(mixed)\tE\n2\tsort(empty)\tE\n2\tsort_by(people, &age)[*].name\tE\n2\tsort_by(people, &name)[*].age\tE\n2\tsort_by(people, &city)\tE\n2\tsort_by(empty, &a)\tE\n2\tto_array(s)\t[null]\n2\tto_array(arr)\t[null]\n2\tto_array(n)\t[null]\n2\tto_string(arr)\t\"null\"\n2\tto_string(obj)\t\"null\"\n2\tto_string(s)\t\"null\"\n2\tto_string(zero)\t\"null\"\n2\tto_string(t)\t\"null\"\n2\tto_string(n)\t\"null\"\n2\tto_string(u)\t\"null\"\n2\tto_string(people[0])\t\"null\"\n2\tto_number(num_strs[0])\tnull\n2\tto_number(num_strs[1])\tnull\n2\tto_number(num_strs[2])\tnull\n"
}

fn jmes_vectors_19() -> str {
    ret "2\tto_number(num_strs[3])\tnull\n2\tto_number(num_strs[4])\tnull\n2\tto_number(arr)\tnull\n2\tto_number(n)\tnull\n2\tto_number(t)\tnull\n2\tto_number(zero)\tnull\n2\tnum_strs[].to_number(@)\tnull\n2\tmap(&to_number(@), num_strs)\tE\n2\ttype(arr)\t\"null\"\n2\ttype(s)\t\"null\"\n2\ttype(n)\t\"null\"\n2\ttype(t)\t\"null\"\n2\ttype(zero)\t\"null\"\n2\ttype(obj)\t\"null\"\n2\ttype(nums[1])\t\"null\"\n2\ttype(missing)\t\"null\"\n2\tunknown(arr)\tE\n2\tlength()\tE\n2\tlength(arr, arr)\tE\n2\tabs()\tE\n2\tsort_by(people)\tE\n2\tmap(arr, people)\tE\n2\tmax_by(people, name)\tE\n2\tpeople[?age > `28`] | [*].name\tnull\n2\tpeople[?age > `28`].{n: name}\tnull\n2\t`[1,2,3]`\t[1, 2, 3]\n2\t`{\"a\": 1}`\t{\"a\": 1}\n2\t`\"str\"`\t\"str\"\n2\t`true`\ttrue\n2\t`null`\tnull\n2\t`1.5`\t1.5\n2\t`[1, 2, {\"a\": [3]}]`\t[1, 2, {\"a\": [3]}]\n2\t'raw string'\t\"raw string\"\n2\t'it\\'s'\t\"it's\"\n2\t\"quoted key\"\tnull\n2\t\"quoted key\".inner\tnull\n2\t\"f-g\"\tnull\n2\tfoo[*].bar[*].baz\tnull\n2\tfoo[].bar[].baz\tnull\n2\tfoo[*].bar[0].baz\tnull\n"
}

fn jmes_vectors_20() -> str {
    ret "2\tfoo[0].bar[1].baz\tnull\n2\tfoo[?bar[0].baz == `1`]\tnull\n2\tlist[*][1]\tnull\n2\tlist[][1]\tnull\n2\tlist[1][1:]\tnull\n2\tlist[::2][0]\tnull\n2\tlist[0:2][0]\tnull\n2\tlist[0:2][*][0]\tnull\n2\twords[?starts_with(@, 'b')]\tnull\n2\twords[?length(@) > `4`]\tnull\n2\twords[1:3]\tnull\n2\twords[-2:]\tnull\n2\tsort_by(words, &length(@))\tE\n2\tmax_by(words, &length(@))\tE\n2\twords | sort(@) | reverse(@) | [0]\tE\n2\t[words[0], words[-1]] | join('-', @)\tE\n2\tfoo[*].bar[?baz == `1`]\tnull\n2\tfoo[*].bar[?baz].baz | []\tnull\n2\tfoo[?length(bar) > `0`] | length(@)\tE\n2\t\tE\n2\ta.\tE\n2\t.a\tE\n2\ta[\tE\n2\ta[]]\tE\n2\ta..b\tE\n2\ta[0\tE\n2\t[a,\tE\n2\t{a:}\tE\n2\t{a b}\tE\n2\ta ||\tE\n2\t| a\tE\n2\ta b\tE\n2\t(a\tE\n2\t`not json`\t\"not json\"\n2\t\"unterminated\tE\n2\t'unterminated\tE\n2\ta[?]\tE\n2\ta[?b\tE\n2\ta.[\tE\n2\ta.{\tE\n"
}

fn jmes_vectors_21() -> str {
    ret "2\ta[1:2:3:4]\tE\n2\ta[1:x]\tE\n2\t1\tE\n2\t-\tE\n2\ta == \tE\n2\ta.&b\tE\n2\t*.\tE\n2\ta !b\tE\n2\ta[*\tE\n2\t@@\tE\n2\t=\tE\n2\ta = b\tE\n2\t[?a]\tnull\n2\ta.1\tE\n2\ta[-]\tE\n3\t@\t{\"foo\": [{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}], \"f-g\": 1, \"quoted key\": {\"inner\": [10, 20, 30]}, \"list\": [[1, 2, 3], [4, 5, 6], [7, 8, 9]], \"words\": [\"apple\", \"banana\", \"cherry\", \"date\"], \"wrap\": {\"a\": {\"a\": {\"a\": 1}}}}\n3\ta\tnull\n3\ta.b\tnull\n3\ta.b.c\tnull\n3\ta.b.c[0]\tnull\n3\ta.b.c[-1]\tnull\n3\ta.b.c[3].d\tnull\n3\ta.b.c[5]\tnull\n3\tarr[0]\tnull\n3\tarr[-1]\tnull\n3\tarr[10]\tnull\n3\tarr[1:3]\tnull\n3\tarr[:2]\tnull\n3\tarr[2:]\tnull\n3\tarr[::2]\tnull\n3\tarr[::-1]\tnull\n3\tarr[-2:]\tnull\n3\tarr[1:4:2]\tnull\n3\tarr[10:20]\tnull\n3\tarr[3:1]\tnull\n3\tarr[3:0:-1]\tnull\n3\tarr[-1:-4:-1]\tnull\n3\tarr[:-1]\tnull\n3\tarr[::3]\tnull\n3\tpeople[*].name\tnull\n"
}

fn jmes_vectors_22() -> str {
    ret "3\tpeople[].name\tnull\n3\tpeople[*].tags\tnull\n3\tpeople[*].tags[]\tnull\n3\tpeople[*].tags[0]\tnull\n3\tpeople[0]\tnull\n3\tpeople[1:].name\tnull\n3\tpeople[?age > `28`].name\tnull\n3\tpeople[?age >= `30`].name\tnull\n3\tpeople[?age < `30`]\tnull\n3\tpeople[?city].name\tnull\n3\tpeople[?!city].name\tnull\n3\tpeople[?name == 'bob']\tnull\n3\tpeople[?name != 'bob'].name\tnull\n3\tpeople[?tags[0] == 'a'].name\tnull\n3\tpeople[?age > `20` && age < `32`].name\tnull\n3\tpeople[?age > `33` || name == 'bob'].name\tnull\n3\tpeople[?contains(tags, 'b')].name\tnull\n3\tpeople[?length(tags) > `0`].name\tnull\n3\tnested[]\tnull\n3\tnested[][]\tnull\n3\tnested[*][0]\tnull\n3\tnested[0]\tnull\n3\tnested[1][1]\tnull\n3\tnested[*]\tnull\n3\tnested[1][1][0]\tnull\n3\tobj.*\tnull\n3\tobj.*.w\tnull\n3\tobj.z.w\tnull\n3\tobj.*.*\tnull\n3\t*\t[[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}], 1, {\"inner\": [10, 20, 30]}, [[1, 2, 3], [4, 5, 6], [7, 8, 9]], [\"apple\", \"banana\", \"cherry\", \"date\"], {\"a\": {\"a\": {\"a\": 1}}}]\n3\t*.x\t[]\n3\tobj.z.*\tnull\n3\t[*]\tnull\n3\t[]\tnull\n3\twrap.a.a.a\t1\n3\tn\tnull\n3\tn.x\tnull\n3\tt\tnull\n3\tf\tnull\n3\t!t\ttrue\n"
}

fn jmes_vectors_23() -> str {
    ret "3\t!f\ttrue\n3\t!n\ttrue\n3\t!s\ttrue\n3\t!zero\ttrue\n3\t!e\ttrue\n3\t!empty\ttrue\n3\t!arr\ttrue\n3\tzero || arr\tnull\n3\tn || s\tnull\n3\te || n || t\tnull\n3\tf && t\tnull\n3\tt && s\tnull\n3\tn && s\tnull\n3\tempty || emptyo\tnull\n3\ta.b || arr\tnull\n3\ts || 'x'\t\"x\"\n3\t[a.b.c[0], arr[1]]\t[null, null]\n3\t[arr[0], nums[1], n, s]\t[null, null, null, null]\n3\t{x: arr[0], y: s}\t{\"x\": null, \"y\": null}\n3\t{\"first\": people[0].name, second: people[1].name}\t{\"first\": null, \"second\": null}\n3\t{a: n, b: t}\t{\"a\": null, \"b\": null}\n3\tpeople[*].{name: name, age: age}\tnull\n3\tpeople[*].[name, age]\tnull\n3\tpeople[].{n: name, t: length(tags)}\tnull\n3\tobj.{x: x, w: z.w}\tnull\n3\tobj.[x, y]\tnull\n3\tarr | [0]\tnull\n3\tpeople[*].name | [0]\tnull\n3\tpeople | length(@)\tE\n3\tarr[1:] | [0]\tnull\n3\tlength(arr)\tE\n3\tlength(s)\tE\n3\tlength(u)\tE\n3\tlength(obj)\tE\n3\tlength(n)\tE\n3\tlength(zero)\tE\n3\tlength(`\"abc\"`)\t3\n3\tlength(@)\t6\n3\tabs(nums[3])\tE\n3\tabs(nums[0])\tE\n"
}

fn jmes_vectors_24() -> str {
    ret "3\tabs(nums[1])\tE\n3\tabs(s)\tE\n3\tavg(arr)\tE\n3\tavg(nums)\tE\n3\tavg(empty)\tE\n3\tavg(strs)\tE\n3\tsum(arr)\tE\n3\tsum(nums)\tE\n3\tsum(empty)\tE\n3\tceil(nums[1])\tE\n3\tfloor(nums[1])\tE\n3\tceil(nums[3])\tE\n3\tfloor(nums[3])\tE\n3\tceil(arr[0])\tE\n3\tcontains(arr, `3`)\tE\n3\tcontains(arr, `9`)\tE\n3\tcontains(s, 'ell')\tE\n3\tcontains(s, 'zzz')\tE\n3\tcontains(strs, 'a')\tE\n3\tcontains(people, `1`)\tE\n3\tstarts_with(s, 'he')\tE\n3\tstarts_with(s, 'lo')\tE\n3\tends_with(s, 'llo')\tE\n3\tends_with(s, 'he')\tE\n3\tends_with(s, 'hello world')\tE\n3\tjoin(', ', strs)\tE\n3\tjoin('', strs)\tE\n3\tjoin('-', empty)\tE\n3\tjoin(',', arr)\tE\n3\tkeys(obj)\tE\n3\tvalues(obj)\tE\n3\tkeys(emptyo)\tE\n3\tkeys(arr)\tE\n3\tmap(&name, people)\tE\n3\tmap(&age, people)\tE\n3\tmap(&length(@), people[*].tags)\tE\n3\tmap(&[name], people)\tE\n3\tmax(arr)\tE\n3\tmin(arr)\tE\n3\tmax(nums)\tE\n"
}

fn jmes_vectors_25() -> str {
    ret "3\tmin(nums)\tE\n3\tmax(strs)\tE\n3\tmin(strs)\tE\n3\tmax(empty)\tE\n3\tmax(mixed)\tE\n3\tmax_by(people, &age).name\tE\n3\tmin_by(people, &age).name\tE\n3\tmax_by(people, &name).age\tE\n3\tmin_by(people, &name).age\tE\n3\tmax_by(empty, &a)\tE\n3\tmerge(obj, {extra: `1`})\tE\n3\tmerge(obj, obj.z)\tE\n3\tmerge({a: `1`, b: `2`}, {b: `3`, c: `4`})\t{\"a\": 1, \"b\": 3, \"c\": 4}\n3\tmerge(@)\t{\"foo\": [{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}], \"f-g\": 1, \"quoted key\": {\"inner\": [10, 20, 30]}, \"list\": [[1, 2, 3], [4, 5, 6], [7, 8, 9]], \"words\": [\"apple\", \"banana\", \"cherry\", \"date\"], \"wrap\": {\"a\": {\"a\": {\"a\": 1}}}}\n3\tnot_null(n, s)\tnull\n3\tnot_null(n, n)\tnull\n3\tnot_null(n, zero, s)\tnull\n3\treverse(arr)\tE\n3\treverse(s)\tE\n3\treverse(u)\tE\n3\treverse(empty)\tE\n3\treverse(obj)\tE\n3\tsort(nums)\tE\n3\tsort(strs)\tE\n3\tsort(arr)\tE\n3\tsort(mixed)\tE\n3\tsort(empty)\tE\n3\tsort_by(people, &age)[*].name\tE\n3\tsort_by(people, &name)[*].age\tE\n3\tsort_by(people, &city)\tE\n3\tsort_by(empty, &a)\tE\n3\tto_array(s)\t[null]\n3\tto_array(arr)\t[null]\n3\tto_array(n)\t[null]\n3\tto_string(arr)\t\"null\"\n3\tto_string(obj)\t\"null\"\n3\tto_string(s)\t\"null\"\n3\tto_string(zero)\t\"null\"\n3\tto_string(t)\t\"null\"\n3\tto_string(n)\t\"null\"\n"
}

fn jmes_vectors_26() -> str {
    ret "3\tto_string(u)\t\"null\"\n3\tto_string(people[0])\t\"null\"\n3\tto_number(num_strs[0])\tnull\n3\tto_number(num_strs[1])\tnull\n3\tto_number(num_strs[2])\tnull\n3\tto_number(num_strs[3])\tnull\n3\tto_number(num_strs[4])\tnull\n3\tto_number(arr)\tnull\n3\tto_number(n)\tnull\n3\tto_number(t)\tnull\n3\tto_number(zero)\tnull\n3\tnum_strs[].to_number(@)\tnull\n3\tmap(&to_number(@), num_strs)\tE\n3\ttype(arr)\t\"null\"\n3\ttype(s)\t\"null\"\n3\ttype(n)\t\"null\"\n3\ttype(t)\t\"null\"\n3\ttype(zero)\t\"null\"\n3\ttype(obj)\t\"null\"\n3\ttype(nums[1])\t\"null\"\n3\ttype(missing)\t\"null\"\n3\tunknown(arr)\tE\n3\tlength()\tE\n3\tlength(arr, arr)\tE\n3\tabs()\tE\n3\tsort_by(people)\tE\n3\tmap(arr, people)\tE\n3\tmax_by(people, name)\tE\n3\tpeople[?age > `28`] | [*].name\tnull\n3\tpeople[?age > `28`].{n: name}\tnull\n3\t`[1,2,3]`\t[1, 2, 3]\n3\t`{\"a\": 1}`\t{\"a\": 1}\n3\t`\"str\"`\t\"str\"\n3\t`true`\ttrue\n3\t`null`\tnull\n3\t`1.5`\t1.5\n3\t`[1, 2, {\"a\": [3]}]`\t[1, 2, {\"a\": [3]}]\n3\t'raw string'\t\"raw string\"\n3\t'it\\'s'\t\"it's\"\n3\t\"quoted key\"\t{\"inner\": [10, 20, 30]}\n"
}

fn jmes_vectors_27() -> str {
    ret "3\t\"quoted key\".inner\t[10, 20, 30]\n3\t\"f-g\"\t1\n3\tfoo[*].bar[*].baz\t[[1, 2], [3], []]\n3\tfoo[].bar[].baz\t[1, 2, 3]\n3\tfoo[*].bar[0].baz\t[1, 3]\n3\tfoo[0].bar[1].baz\t2\n3\tfoo[?bar[0].baz == `1`]\t[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}]\n3\tlist[*][1]\t[2, 5, 8]\n3\tlist[][1]\t[]\n3\tlist[1][1:]\t[5, 6]\n3\tlist[::2][0]\t[1, 7]\n3\tlist[0:2][0]\t[1, 4]\n3\tlist[0:2][*][0]\t[[], []]\n3\twords[?starts_with(@, 'b')]\t[\"banana\"]\n3\twords[?length(@) > `4`]\t[\"apple\", \"banana\", \"cherry\"]\n3\twords[1:3]\t[\"banana\", \"cherry\"]\n3\twords[-2:]\t[\"cherry\", \"date\"]\n3\tsort_by(words, &length(@))\t[\"date\", \"apple\", \"banana\", \"cherry\"]\n3\tmax_by(words, &length(@))\t\"banana\"\n3\twords | sort(@) | reverse(@) | [0]\t\"date\"\n3\t[words[0], words[-1]] | join('-', @)\t\"apple-date\"\n3\tfoo[*].bar[?baz == `1`]\t[[{\"baz\": 1}], [], []]\n3\tfoo[*].bar[?baz].baz | []\t[1, 2, 3]\n3\tfoo[?length(bar) > `0`] | length(@)\t2\n3\t\tE\n3\ta.\tE\n3\t.a\tE\n3\ta[\tE\n3\ta[]]\tE\n3\ta..b\tE\n3\ta[0\tE\n3\t[a,\tE\n3\t{a:}\tE\n3\t{a b}\tE\n3\ta ||\tE\n3\t| a\tE\n3\ta b\tE\n3\t(a\tE\n3\t`not json`\t\"not json\"\n3\t\"unterminated\tE\n"
}

fn jmes_vectors_28() -> str {
    ret "3\t'unterminated\tE\n3\ta[?]\tE\n3\ta[?b\tE\n3\ta.[\tE\n3\ta.{\tE\n3\ta[1:2:3:4]\tE\n3\ta[1:x]\tE\n3\t1\tE\n3\t-\tE\n3\ta == \tE\n3\ta.&b\tE\n3\t*.\tE\n3\ta !b\tE\n3\ta[*\tE\n3\t@@\tE\n3\t=\tE\n3\ta = b\tE\n3\t[?a]\tnull\n3\ta.1\tE\n3\ta[-]\tE\n0\tstrs\t[\"b\", \"a\", \"c\"]\n0\tt\ttrue\n3\t[words[?x < `1`], nested][*]\t[[]]\n1\t{k1: obj, k2: f.b}\t{\"k1\": null, \"k2\": null}\n3\t{k1: nums[?z == `[1,2]`][0], k2: [s, v][-2][]}\t{\"k1\": null, \"k2\": null}\n3\ts && words.f | type(x) || tags\t\"null\"\n3\t!f || people[:4].id\ttrue\n3\tfoo\t[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}]\n1\t[tags.*.strs[1], [tags, x[:-2]][:-2]]\t[null, []]\n0\t[strs, {k1: k[?obj > `1`], k2: [t, nested]}[]]\t[[\"b\", \"a\", \"c\"], null]\n0\tobj\t{\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}}\n3\tlist\t[[1, 2, 3], [4, 5, 6], [7, 8, 9]]\n1\t[strs.*[:] | {k1: y[3], k2: id}, age[*]]\t[null, null]\n3\t[[obj[?a <= `2`].age, [nums, y][]], x[2].*[*]]\t[[null, []], null]\n2\t!age[:0][1][2]\ttrue\n2\t{k1: n[::0] && s[*][:], k2: v[?b <= 'a'][1][-3]}\t{\"k1\": null, \"k2\": null}\n0\t[people, nums]\t[[{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}], [3, 1.5, 2, -4]]\n2\t{k1: nums[*][][], k2: {k1: words[3][2], k2: age[:-2]}}\t{\"k1\": null, \"k2\": {\"k1\": null, \"k2\": null}}\n0\t{k1: reverse([f[*], foo[1]]), k2: age[]}\t{\"k1\": [null, null], \"k2\": null}\n1\t{k1: {k1: n, k2: f}.nums[?z < 'a'], k2: tags}\t{\"k1\": null, \"k2\": null}\n"
}

fn jmes_vectors_29() -> str {
    ret "3\t[!tags[*][*], strs.*.*[-1:0:-4]]\t[true, null]\n3\tlength({k1: {k1: nums.v, k2: !baz}, k2: b[2::3] || to_number(name)})\t2\n3\t!tags[:-4].strs[?nums != `0`]\ttrue\n0\tsort(arr[::-1])\t[1, 2, 3, 4, 5]\n1\t[z[?nested != `[1,2]`], {k1: foo || n, k2: name.*}.*]\t[null, []]\n2\t{k1: !x[][*], k2: {k1: s, k2: arr}[-2]}\t{\"k1\": null, \"k2\": null}\n0\t{k1: [nums[?b >= 'a'][-3], strs[*].f], k2: baz}\t{\"k1\": [[], []], \"k2\": null}\n1\t[n[:1].list[], to_array({k1: f, k2: words | t})]\t[null, [{\"k1\": null, \"k2\": null}]]\n0\tobj || map(&a, !a.*)\t{\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}}\n0\tf\tfalse\n0\ts\t\"hello\"\n1\t[y.v.name[?n <= `[1,2]`], !list]\t[null, true]\n2\tnums || !k[1:1][*]\ttrue\n0\t!id\ttrue\n0\tarr\t[1, 2, 3, 4, 5]\n0\tobj.*\t[1, 2, {\"w\": 3}]\n1\tto_array(baz)\t[null]\n2\t{k1: !foo.*, k2: f[*][?words == `true`][2]}\t{\"k1\": null, \"k2\": null}\n1\t{k1: [age, n][?a >= 'b'][2:2], k2: n[*][1] | foo[-3] && n[-2]}\t{\"k1\": [], \"k2\": null}\n0\tstrs\t[\"b\", \"a\", \"c\"]\n0\tstrs || x.age\t[\"b\", \"a\", \"c\"]\n0\tpeople\t[{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}]\n0\tmap(&n, [f, list.bar][])\t[null]\n0\tnested\t[[1, 2], [3, [4, 5]], []]\n0\t{k1: arr, k2: z}\t{\"k1\": [1, 2, 3, 4, 5], \"k2\": null}\n0\t!{k1: obj[-2] || v[*], k2: to_number(nums[::1])}\tfalse\n0\t[words.strs[?z <= `null`].nested, age[?obj < `true`][?zero != `null`][*]]\t[null, null]\n3\t!{k1: foo, k2: f}[*][?age <= 'b']\ttrue\n0\tpeople\t[{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}]\n3\tfoo\t[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}]\n3\t{k1: !people || nums[*][*], k2: obj.strs}\t{\"k1\": true, \"k2\": null}\n0\tpeople\t[{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}]\n1\t[foo.*, bar | name.tags] || arr\t[null, null]\n0\ttype(tags)\t\"null\"\n1\t!obj\ttrue\n0\t{k1: {k1: age || k, k2: n[?words <= `30`]} | bar, k2: nested}\t{\"k1\": null, \"k2\": [[1, 2], [3, [4, 5]], []]}\n0\t{k1: obj.*.*.foo, k2: to_array({k1: name, k2: [list, tags]})}\t{\"k1\": [[]], \"k2\": [{\"k1\": null, \"k2\": [null, null]}]}\n0\tf\tfalse\n0\tpeople\t[{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}]\n0\tstrs\t[\"b\", \"a\", \"c\"]\n"
}

fn jmes_vectors_30() -> str {
    ret "1\t[v[?b >= `true`][*].id, y[-2:-1][3][*]]\t[null, null]\n0\tzero\t0\n0\tpeople\t[{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}]\n0\t{k1: e.baz[?e != `null`] | f.*[], k2: {k1: map(&a, strs), k2: nums[0::-4]} | arr[?name <= `2`].f}\t{\"k1\": null, \"k2\": null}\n0\tnested\t[[1, 2], [3, [4, 5]], []]\n3\twords\t[\"apple\", \"banana\", \"cherry\", \"date\"]\n2\t{k1: nums.baz.*, k2: [s | a, k[?arr >= `true`]][*]}\t{\"k1\": null, \"k2\": []}\n3\t[arr | strs[].f, bar]\t[null, null]\n0\tpeople[2]\t{\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}\n3\t{k1: foo, k2: obj.words} || list[3][*]\t{\"k1\": [{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}], \"k2\": null}\n2\t!id\ttrue\n3\t[z.n[*], [tags, arr[*]]][:4]\t[[null, null]]\n2\t{k1: age, k2: strs[:2][1][*]}\t{\"k1\": null, \"k2\": null}\n3\tto_array({k1: [bar, s], k2: a && t}[-2])\t[null]\n1\tto_array(bar | e.*[1])\t[null]\n2\treverse([[a, v][?nested > 'x'], words.*.e])\t[null, []]\n0\tnums[]\t[3, 1.5, 2, -4]\n1\t{k1: e || zero.*.*, k2: b[][*][*]}\t{\"k1\": null, \"k2\": null}\n3\twords || min_by(k, &strs)[?people != `true`][1]\t[\"apple\", \"banana\", \"cherry\", \"date\"]\n3\tlist[-3]\t[1, 2, 3]\n0\ttype(list)\t\"null\"\n1\ttype(n) || z[*].b[]\t\"null\"\n0\tnested\t[[1, 2], [3, [4, 5]], []]\n3\t[bar, zero[2][3:][?baz != `null`]]\t[null, null]\n0\t{k1: nested[:1][0][?y == 'b'], k2: x[3:]}\t{\"k1\": [], \"k2\": null}\n3\twords\t[\"apple\", \"banana\", \"cherry\", \"date\"]\n3\tfoo || sum(bar)[?people != `0`]\t[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}]\n0\t[b, nums] || !id.id.name\t[null, [3, 1.5, 2, -4]]\n3\t{k1: people[?x == `1`], k2: !z[2]}\t{\"k1\": null, \"k2\": true}\n0\t{k1: baz[?k > `2`][-3], k2: x[2:].name[*]}\t{\"k1\": null, \"k2\": null}\n3\t{k1: x[:-2], k2: arr[?x >= 'b']} || a[][][4:4]\t{\"k1\": null, \"k2\": null}\n0\t{k1: obj, k2: [foo, b].list}.*\t[{\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}}]\n2\t{k1: tags || b, k2: [s, x]}.* | !b || foo[]\ttrue\n1\tlength(type(x.x.people))\t4\n0\tnested\t[[1, 2], [3, [4, 5]], []]\n0\tf\tfalse\n0\t!people\tfalse\n3\t[y.v[-3], y]\t[null, null]\n0\tnums\t[3, 1.5, 2, -4]\n1\t[nums[*], a.*[3] | zero && a[:]]\t[null, null]\n"
}

fn jmes_vectors_31() -> str {
    ret "2\t[strs, [bar[?bar >= `[1,2]`][:-3], tags[:][*]]]\t[null, [null, null]]\n0\t{k1: [nested, age.list][*], k2: strs[*]}\t{\"k1\": [[[1, 2], [3, [4, 5]], []]], \"k2\": [\"b\", \"a\", \"c\"]}\n3\t[obj, !s[-3:]][]\t[true]\n3\ttype(y)\t\"null\"\n0\tpeople\t[{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}]\n0\t!strs\tfalse\n2\t[baz, arr[?obj <= 'b'][?foo != `[1,2]`][-2]]\t[null, null]\n3\t{k1: bar, k2: nested.nums && [{k1: b, k2: e}, s[0]]}\t{\"k1\": null, \"k2\": null}\n1\t!age[0]\ttrue\n3\tfoo\t[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}]\n0\t{k1: name, k2: nums}\t{\"k1\": null, \"k2\": [3, 1.5, 2, -4]}\n1\t[y | a | nested[][?arr == 'x'], [obj, a][*] || k]\t[null, null]\n0\t[x | b[?zero > 'x'][0], [bar, baz]]\t[null, [null, null]]\n0\tmap(&obj, nested)\t[null, null, null]\n1\t[[n, list], words[*]]\t[[null, null], null]\n0\tobj\t{\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}}\n2\t{k1: f.foo, k2: zero[*]} || zero[?tags > 'x']\t{\"k1\": null, \"k2\": null}\n1\tto_string(words[?nested <= 'x'][][?v >= 'b'])\t\"null\"\n0\t[{k1: words, k2: z}[?zero > `[1,2]`][], obj[]]\t[null, null]\n3\t[{k1: {k1: v, k2: arr}, k2: v}, [tags, {k1: age, k2: people}]][-1:]\t[[null, {\"k1\": null, \"k2\": null}]]\n2\t[a[-1:][][], baz[0][?y != `1`][3:1]]\t[null, null]\n1\t[x[?baz < `2`].f[-1], nums]\t[null, null]\n3\tlist\t[[1, 2, 3], [4, 5, 6], [7, 8, 9]]\n2\t[list || a[], v.foo[-1].*]\t[null, null]\n3\tcontains(foo[*][:] && age.a[?tags == `2`], 'x')\tfalse\n0\t{k1: s[*].*.*, k2: s}\t{\"k1\": null, \"k2\": \"hello\"}\n3\t{k1: k.baz[*], k2: b[?id == `null`].k.a}\t{\"k1\": null, \"k2\": null}\n0\tt\ttrue\n1\t{k1: people.baz, k2: v[-2][:-2][]}\t{\"k1\": null, \"k2\": null}\n0\t[people || t[0].t, s]\t[[{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}], \"hello\"]\n3\tlist[2]\t[7, 8, 9]\n0\tt\ttrue\n0\tnested[*]\t[[1, 2], [3, [4, 5]], []]\n3\tmap(&a, foo)\t[null, null, null]\n1\t[name.*.age[-1], e]\t[null, null]\n3\t[id, n]\t[null, null]\n3\t[foo[3:].b.foo, arr | {k1: f, k2: people}[*]]\t[[], null]\n0\tnums\t[3, 1.5, 2, -4]\n0\t{k1: bar.v.v, k2: id || [nested, v][]}\t{\"k1\": null, \"k2\": [[1, 2], [3, [4, 5]], []]}\n0\ty || zero\t0\n"
}

fn jmes_vectors_32() -> str {
    ret "1\t[nums[?id != `1`] || bar[-1][-2], list]\t[null, null]\n1\t[words[*], {k1: n[?strs <= `null`], k2: obj.s}][1]\t{\"k1\": null, \"k2\": null}\n2\tto_string(nested)\t\"null\"\n3\t[b, z] || strs[][?name < `\"s\"`].b\t[null, null]\n3\tlist\t[[1, 2, 3], [4, 5, 6], [7, 8, 9]]\n0\tto_array(s[0][-3][*])\t[null]\n1\tto_array(baz)\t[null]\n1\tto_array(type(f)[*][?tags < `\"s\"`])\t[null]\n0\tmap(&t, strs)\t[null, null, null]\n3\tfoo\t[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}]\n1\t{k1: f[*].*.strs, k2: foo[?x != 'a'][?y >= `[1,2]`]}\t{\"k1\": null, \"k2\": null}\n1\tmap(&name, [a[].nums, k[?age == 'x']])\t[null, null]\n1\t[contains([age, v], `30`) || obj[?t > `[1,2]`].a, s.foo]\t[null, null]\n3\tfoo\t[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}]\n2\tto_array(list)\t[null]\n0\tobj[][:][::3] || [to_string(obj), s[:]][]\t[\"{\\\"x\\\":1,\\\"y\\\":2,\\\"z\\\":{\\\"w\\\":3}}\"]\n0\t{k1: f[], k2: {k1: a, k2: !age}.*}\t{\"k1\": null, \"k2\": [{\"b\": {\"c\": [1, 2, 3, {\"d\": \"x\"}]}}, true]}\n3\t[n && foo[*][3:3], b[*]]\t[null, null]\n0\ta\t{\"b\": {\"c\": [1, 2, 3, {\"d\": \"x\"}]}}\n2\t!zero[*].*.*\ttrue\n3\t[to_number(nums || b)[], b.*[].name]\t[null, null]\n0\t[map(&a, [nums, zero[]]), n[-2][3][?v != `\"s\"`]]\t[[null, null], null]\n3\tfoo\t[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}]\n2\t{k1: [list, x][0][?tags == 'a'], k2: f}\t{\"k1\": null, \"k2\": null}\n1\tto_string(!f[?b != `true`][-2])\t\"null\"\n0\t{k1: b[?tags >= `null`], k2: !e.nested}\t{\"k1\": null, \"k2\": null}\n0\tarr[]\t[1, 2, 3, 4, 5]\n1\t!k || age[*][0]\ttrue\n3\tfoo\t[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}]\n0\tobj\t{\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}}\n0\t{k1: obj[0] || nested, k2: name} || map(&z, tags).nums && [nested[], a]\t{\"k1\": [[1, 2], [3, [4, 5]], []], \"k2\": null}\n0\tcontains(strs, `2`)\tfalse\n2\t{k1: y | people[-1], k2: nested.n[0]} && [{k1: t, k2: b}[?k == `30`], zero[1][*]]\t[null, null]\n0\ts\t\"hello\"\n2\t[zero, [id[3], foo[]].nested]\t[null, null]\n3\tto_array(foo)\t[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}]\n2\t[!{k1: arr, k2: a}, id][:]\t[false]\n1\t[v, people[-1]]\t[null, null]\n3\tto_string(v[-3::-1])\t\"null\"\n2\tto_string(e.*[:][1:])\t\"null\"\n"
}

fn jmes_vectors_33() -> str {
    ret "0\t!v[1]\ttrue\n0\tstrs\t[\"b\", \"a\", \"c\"]\n3\t{k1: n | [arr[?b != 'b'], id], k2: {k1: obj, k2: age}[-3].a}\t{\"k1\": null, \"k2\": null}\n1\t[!obj, f || strs] || words[4:][*][?bar >= `null`]\t[true, null]\n0\ttype(type(zero)[][?zero <= `null`])\t\"null\"\n0\tzero && age[0] || {k1: z, k2: tags} || bar[?b <= `\"s\"`] || arr\t{\"k1\": null, \"k2\": null}\n2\t!z\ttrue\n2\t{k1: nested[*][], k2: t}\t{\"k1\": null, \"k2\": null}\n2\t!bar[*]\ttrue\n3\t!a\ttrue\n0\tpeople\t[{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}]\n1\t{k1: foo[1][?foo <= `0`].tags, k2: people[?y == `null`] || !strs[2]}\t{\"k1\": null, \"k2\": true}\n3\tfoo || f[2][*][*]\t[{\"bar\": [{\"baz\": 1}, {\"baz\": 2}]}, {\"bar\": [{\"baz\": 3}, {\"qux\": 4}]}, {\"bar\": []}]\n2\ttype({k1: type(e)[4:-4], k2: [obj, {k1: e, k2: strs}]})\t\"object\"\n3\tlist\t[[1, 2, 3], [4, 5, 6], [7, 8, 9]]\n3\t[zero | age.age[?z < 'a'], s[0]]\t[null, null]\n2\t[name[:][?tags != `null`], [arr, b][?age <= 'b']][?words != 'x']\t[[]]\n3\tlist\t[[1, 2, 3], [4, 5, 6], [7, 8, 9]]\n0\t[z, age[:][][3]]\t[null, null]\n3\t!zero[] | !k[:-2][:]\ttrue\n0\tobj\t{\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}}\n1\ttype(list.f.t[::4])\t\"null\"\n0\tt\ttrue\n0\ta\t{\"b\": {\"c\": [1, 2, 3, {\"d\": \"x\"}]}}\n3\t!arr\ttrue\n2\t[{k1: t[-3], k2: a[*]}[3], s]\t[null, null]\n0\tf\tfalse\n0\tt\ttrue\n0\tnested[:]\t[[1, 2], [3, [4, 5]], []]\n0\t!nested[*].nums[*]\ttrue\n2\t[v, nums]\t[null, null]\n0\tnested\t[[1, 2], [3, [4, 5]], []]\n3\tmap(&foo, words)\t[null, null, null, null]\n0\tobj\t{\"x\": 1, \"y\": 2, \"z\": {\"w\": 3}}\n1\t[nums || name && zero.v.people, list.*]\t[null, null]\n1\t!{k1: zero, k2: strs}[*][2]\ttrue\n3\tto_string(list.f)\t\"null\"\n0\t[list | v[?z < 'x'] && baz[:-4] | name[?b < `[1,2]`], [t[*], list.zero].nested]\t[null, null]\n3\t{k1: nested[*][?arr > 'a'][?t < `null`], k2: strs[?words <= 'a'][]}\t{\"k1\": null, \"k2\": null}\n1\t{k1: v, k2: k}\t{\"k1\": null, \"k2\": null}\n"
}

fn jmes_vectors_34() -> str {
    ret "1\t{k1: baz.bar[-3:-3], k2: a.n[?b == `null`][*]}\t{\"k1\": null, \"k2\": null}\n1\t{k1: type(zero), k2: a.people | y.*[-3]}\t{\"k1\": \"null\", \"k2\": null}\n3\t[people, a] || s[:4:2]\t[null, null]\n3\t[list[].nums, nums]\t[[], null]\n2\t{k1: tags[:][], k2: {k1: arr, k2: v}[*][2]}\t{\"k1\": null, \"k2\": null}\n1\tto_string(y[-2:-2])\t\"null\"\n1\t[{k1: [bar[0], f[1]], k2: z[*].k}, z.name[:]]\t[{\"k1\": [null, null], \"k2\": null}, null]\n3\tmap(&nums, foo)\t[null, null, null]\n0\tarr\t[1, 2, 3, 4, 5]\n2\t{k1: arr | obj.y, k2: v}\t{\"k1\": null, \"k2\": null}\n1\t[a[][3], arr.y || id[*].x]\t[null, null]\n3\t[bar.age, n[?zero <= `null`][-4:4]]\t[null, null]\n0\tnums\t[3, 1.5, 2, -4]\n2\ttype(tags[*][-2].b)\t\"null\"\n3\t[name, s] || {k1: tags[], k2: age}\t[null, null]\n0\t!arr[-1:0]\ttrue\n3\twords[]\t[\"apple\", \"banana\", \"cherry\", \"date\"]\n0\t[a[?f <= `2`].v | age[][:-3:-2], {k1: nums && foo[:0], k2: [age.*, people.x]}]\t[null, {\"k1\": null, \"k2\": [null, null]}]\n0\tnums[-1]\t-4\n1\t!t\ttrue\n3\t[x[*].a && !name.t, n[:]]\t[null, null]\n0\tarr\t[1, 2, 3, 4, 5]\n0\t{k1: nums, k2: words}\t{\"k1\": [3, 1.5, 2, -4], \"k2\": null}\n0\tpeople.e.a[] || !name || n[3]\ttrue\n2\tto_array(strs.*[?list > `30`].*)\t[null]\n2\t[baz, baz]\t[null, null]\n1\t!f\ttrue\n0\t{k1: v, k2: {k1: strs | strs[-1], k2: words}}\t{\"k1\": null, \"k2\": {\"k1\": null, \"k2\": null}}\n2\t{k1: zero[*][-3:2:4] | {k1: bar[-3], k2: b && v}, k2: {k1: {k1: list.nums, k2: nested}, k2: k}}\t{\"k1\": null, \"k2\": {\"k1\": {\"k1\": null, \"k2\": null}, \"k2\": null}}\n3\ta[?nums >= `null`].k || [tags, strs]\t[null, null]\n2\t[name, name]\t[null, null]\n2\t!f[*]\ttrue\n2\t!words[-4:1][*]\ttrue\n3\t[t[:], zero]\t[null, null]\n0\tnested\t[[1, 2], [3, [4, 5]], []]\n2\t[n[:-2][0][*], baz[1][]]\t[null, null]\n0\t{k1: v[2].words, k2: v[?e < `0`][-1]} || map(&nested, sort_by(min_by(f, &b), &nums))\t{\"k1\": null, \"k2\": null}\n0\tto_array([k, n.*[:-3]])\t[null, null]\n2\tv.* || [bar, zero] || [name, arr][].t\t[null, null]\n0\t[people[*].e, v.foo[-1]]\t[[], null]\n"
}

fn jmes_vectors_35() -> str {
    ret "2\tto_string(e.*[1][])\t\"null\"\n0\tf\tfalse\n0\tstrs[2]\t\"c\"\n0\t[tags | {k1: v.y, k2: max_by(list, &nested)}, [length(e)[:], people | words[*]]]\t[null, [null, null]]\n1\t![n, obj][*][*]\ttrue\n0\tcontains([nums, x.f.name], `0`)\tfalse\n1\t{k1: baz, k2: f} && name[] || !k[*].y\ttrue\n1\t[v[][3][], nums[?bar == `2`][][*]]\t[null, null]\n0\tstrs\t[\"b\", \"a\", \"c\"]\n3\t{k1: nums, k2: f[-4::-1][:][]}\t{\"k1\": null, \"k2\": null}\n0\tstrs[1:]\t[\"a\", \"c\"]\n2\t{k1: b[:][2] && y.* || obj || bar, k2: [foo[?list < 'a'], list][*]}\t{\"k1\": null, \"k2\": []}\n0\t!!s || tags[?age > `0`]\ttrue\n0\tpeople\t[{\"name\": \"alice\", \"age\": 30, \"tags\": [\"a\", \"b\"]}, {\"name\": \"bob\", \"age\": 25, \"tags\": []}, {\"name\": \"carol\", \"age\": 35, \"tags\": [\"c\"], \"city\": \"paris\"}]\n0\tstrs[:3]\t[\"b\", \"a\", \"c\"]\n0\ta\t{\"b\": {\"c\": [1, 2, 3, {\"d\": \"x\"}]}}\n1\t[contains([y.k, nested], `true`), name.people]\t[false, null]\n0\t{k1: x, k2: [tags, words][0].id}\t{\"k1\": null, \"k2\": null}\n3\t[type(nested || z[:]), k]\t[\"null\", null]\n0\tarr[]\t[1, 2, 3, 4, 5]\n0\ts\t\"hello\"\n2\ttype([arr, obj][?z > `2`][-1])\t\"array\"\n0\t[nums, age[*][*][:]]\t[[3, 1.5, 2, -4], null]\n2\t{k1: z[2].*, k2: baz[:]}\t{\"k1\": null, \"k2\": null}\n3\tlist[0:][*][3].*\t[[], [], []]\n1\t[obj, f]\t[null, null]\n3\twords || baz[][?foo <= 'x'][]\t[\"apple\", \"banana\", \"cherry\", \"date\"]\n0\tstrs[]\t[\"b\", \"a\", \"c\"]\n0\t[s | s, {k1: a[*], k2: people || e}[]]\t[null, null]\n3\twords[1]\t\"banana\"\n0\tnums\t[3, 1.5, 2, -4]\n2\t{k1: [baz, people], k2: nums[-2]}.*[*]\t[[]]\n3\t!t\ttrue\n3\ttype(words)\t\"array\"\n0\ts\t\"hello\"\n0\ta\t{\"b\": {\"c\": [1, 2, 3, {\"d\": \"x\"}]}}\n3\t[id[?f > `30`] | nums[1:0:3].foo, arr[-2]]\t[null, null]\n2\tz[-1] | [s, words] | to_array(nums) || name.obj.e\t[null]\n3\tmap(&list, foo)\t[null, null, null]\n3\t{k1: {k1: tags, k2: x}[-2], k2: y[?nums < `true`][?t > `1`]} || y\t{\"k1\": null, \"k2\": null}\n"
}

fn main(a: *mem.Arena, args: []str) -> err {
    var docs: [8]json.Value = zero
    try load_documents(a, docs[0usize..8usize])
    if run(a, jmes_vectors_0(), docs[0usize..8usize]) != 0u8 { os.exit(1i32) }
    if run(a, jmes_vectors_1(), docs[0usize..8usize]) != 0u8 { os.exit(2i32) }
    if run(a, jmes_vectors_2(), docs[0usize..8usize]) != 0u8 { os.exit(3i32) }
    if run(a, jmes_vectors_3(), docs[0usize..8usize]) != 0u8 { os.exit(4i32) }
    if run(a, jmes_vectors_4(), docs[0usize..8usize]) != 0u8 { os.exit(5i32) }
    if run(a, jmes_vectors_5(), docs[0usize..8usize]) != 0u8 { os.exit(6i32) }
    if run(a, jmes_vectors_6(), docs[0usize..8usize]) != 0u8 { os.exit(7i32) }
    if run(a, jmes_vectors_7(), docs[0usize..8usize]) != 0u8 { os.exit(8i32) }
    if run(a, jmes_vectors_8(), docs[0usize..8usize]) != 0u8 { os.exit(9i32) }
    if run(a, jmes_vectors_9(), docs[0usize..8usize]) != 0u8 { os.exit(10i32) }
    if run(a, jmes_vectors_10(), docs[0usize..8usize]) != 0u8 { os.exit(11i32) }
    if run(a, jmes_vectors_11(), docs[0usize..8usize]) != 0u8 { os.exit(12i32) }
    if run(a, jmes_vectors_12(), docs[0usize..8usize]) != 0u8 { os.exit(13i32) }
    if run(a, jmes_vectors_13(), docs[0usize..8usize]) != 0u8 { os.exit(14i32) }
    if run(a, jmes_vectors_14(), docs[0usize..8usize]) != 0u8 { os.exit(15i32) }
    if run(a, jmes_vectors_15(), docs[0usize..8usize]) != 0u8 { os.exit(16i32) }
    if run(a, jmes_vectors_16(), docs[0usize..8usize]) != 0u8 { os.exit(17i32) }
    if run(a, jmes_vectors_17(), docs[0usize..8usize]) != 0u8 { os.exit(18i32) }
    if run(a, jmes_vectors_18(), docs[0usize..8usize]) != 0u8 { os.exit(19i32) }
    if run(a, jmes_vectors_19(), docs[0usize..8usize]) != 0u8 { os.exit(20i32) }
    if run(a, jmes_vectors_20(), docs[0usize..8usize]) != 0u8 { os.exit(21i32) }
    if run(a, jmes_vectors_21(), docs[0usize..8usize]) != 0u8 { os.exit(22i32) }
    if run(a, jmes_vectors_22(), docs[0usize..8usize]) != 0u8 { os.exit(23i32) }
    if run(a, jmes_vectors_23(), docs[0usize..8usize]) != 0u8 { os.exit(24i32) }
    if run(a, jmes_vectors_24(), docs[0usize..8usize]) != 0u8 { os.exit(25i32) }
    if run(a, jmes_vectors_25(), docs[0usize..8usize]) != 0u8 { os.exit(26i32) }
    if run(a, jmes_vectors_26(), docs[0usize..8usize]) != 0u8 { os.exit(27i32) }
    if run(a, jmes_vectors_27(), docs[0usize..8usize]) != 0u8 { os.exit(28i32) }
    if run(a, jmes_vectors_28(), docs[0usize..8usize]) != 0u8 { os.exit(29i32) }
    if run(a, jmes_vectors_29(), docs[0usize..8usize]) != 0u8 { os.exit(30i32) }
    if run(a, jmes_vectors_30(), docs[0usize..8usize]) != 0u8 { os.exit(31i32) }
    if run(a, jmes_vectors_31(), docs[0usize..8usize]) != 0u8 { os.exit(32i32) }
    if run(a, jmes_vectors_32(), docs[0usize..8usize]) != 0u8 { os.exit(33i32) }
    if run(a, jmes_vectors_33(), docs[0usize..8usize]) != 0u8 { os.exit(34i32) }
    if run(a, jmes_vectors_34(), docs[0usize..8usize]) != 0u8 { os.exit(35i32) }
    if run(a, jmes_vectors_35(), docs[0usize..8usize]) != 0u8 { os.exit(36i32) }
    // equals takes objects as maps, numbers by value.
    var opts: json.Options = zero
    let (x, x_error) = json.parse(a, "{\"a\":1,\"b\":[1.0,2]}", opts)
    let (y, y_error) = json.parse(a, "{\"b\":[1,2.0],\"a\":1}", opts)
    if x_error != ok || y_error != ok || !jmespath.equals(x, y) { os.exit(90i32) }
    // A compiled expression runs over many documents.
    let (expr, expr_error) = jmespath.compile(a, "people[?age > `28`].name")
    if expr_error != ok { os.exit(91i32) }
    let (hit, hit_error) = jmespath.eval_expr(a, expr, docs[0usize])
    let (text, text_error) = jmespath.stringify(a, hit)
    if hit_error != ok || text_error != ok || !str.eq(text, "[\"alice\",\"carol\"]") { os.exit(92i32) }
    // Compile errors are distinguishable from runtime ones.
    let (_, syntax) = jmespath.compile(a, "a[")
    if syntax != jmespath.Syntax { os.exit(93i32) }
    let (_, unknown) = jmespath.search(a, "nope(a)", docs[0usize])
    if unknown != jmespath.UnknownFunction { os.exit(94i32) }
    let (_, wrong) = jmespath.search(a, "abs(s)", docs[0usize])
    if wrong != jmespath.Type { os.exit(95i32) }
    let (_, arity) = jmespath.search(a, "abs(arr, arr)", docs[0usize])
    if arity != jmespath.Arity { os.exit(96i32) }
    try io.print("algo query jmespath ok")
    ret ok
}
