// How a synced table reads its source page by page (L037), after the second half of appdor's `src/sync/synced-table.js`
// and the connector type map `src/connectors/connector-type-map.js`:
//
//   * the type map: a connector's native column types to field types, what has no equivalent arriving as read-only text
//     with a diagnostic, the proposed schema of a declared column list, the mapping the wizard proposes, a column's
//     synced configuration and badge, and a base URL's `{placeholders}` filled from a connection's configuration;
//   * pagination: which declared pagination an entity's GET action carries (the matching path with the fewest
//     placeholders), the next-page cursor of a response (cursor path, `Link: rel="next"`, offset, page), and the request
//     it makes (same-origin only, relative to the base path, a cursor that does not move stops the pull);
//   * records: a vendor's record envelope (`fields`, `properties`) unwrapped to a flat row, unless the stored mapping
//     keeps the blob; the page loop with its page and record ceilings over a host-supplied page fetch.
//
// Values are JSON. The page fetch is a host callback taking the request `{url, method, headers}` and answering `{ok,
// body, headers?, reason?, status?}`; words come back through the host's translator (key, variable). The inferred
// half of `proposeMapping` (a column type read from sample values, `io/infer.js`) is not here.
//
// ponytail: URLs are special-scheme (`http`, `https`) and ASCII; the path's dot segments and percent-encoding follow the
// WHATWG path state for the characters a path carries.
//
// Memory: the arena is retained; every value a function returns lives in it.

use e.algo.ir as ir
use e.algo.sync as sync
use e.algo.syncjob as syncjob
use e.algo.writeback as wb
use e.data.list as list
use e.fmt.json as json
use e.mem
use e.net.ssrf as ssrf
use e.str

fn max_pull_pages() -> i64 { ret 200i64 }

fn max_pull_records() -> i64 { ret 100000i64 }

fn min_interval_minutes() -> i64 { ret 5i64 }

fn preview_row_limit() -> i64 { ret 25i64 }

// A host-supplied page fetch.
type FetchPage = struct { ctx: *void, run: fn(*void, json.Value) -> json.Value }

// --- the type map ----------------------------------------------------------------------------------------------------

fn type_map_text() -> str {
    ret "{\"postgresql\":{\"connectorId\":\"postgresql\",\"nativeToLc8\":{\"smallint\":\"number\",\"integer\":\"number\",\"bigint\":\"number\",\"decimal\":\"number\",\"numeric\":\"number\",\"real\":\"number\",\"double precision\":\"number\",\"serial\":\"number\",\"bigserial\":\"number\",\"varchar\":\"text\",\"char\":\"text\",\"text\":\"text\",\"uuid\":\"text\",\"boolean\":\"checkbox\",\"date\":\"date\",\"timestamp without time zone\":\"dateTime\",\"timestamp with time zone\":\"dateTime\",\"time\":\"text\",\"time with time zone\":\"text\",\"interval\":\"text\",\"json\":\"longText\",\"jsonb\":\"longText\",\"bytea\":\"text\",\"character varying\":\"text\",\"character\":\"text\",\"xml\":\"text\",\"cidr\":\"text\",\"inet\":\"text\",\"macaddr\":\"text\",\"point\":\"text\",\"line\":\"text\",\"lseg\":\"text\",\"box\":\"text\",\"path\":\"text\",\"polygon\":\"text\",\"circle\":\"text\"},\"textFallback\":[\"time\",\"time with time zone\",\"interval\",\"bytea\",\"xml\",\"cidr\",\"inet\",\"macaddr\",\"point\",\"line\",\"lseg\",\"box\",\"path\",\"polygon\",\"circle\"],\"lc8ToNative\":{\"number\":\"numeric\",\"text\":\"text\",\"checkbox\":\"boolean\",\"date\":\"date\",\"dateTime\":\"timestamp with time zone\",\"longText\":\"text\"}},\"google-sheets\":{\"connectorId\":\"google-sheets\",\"nativeToLc8\":{\"string\":\"text\",\"number\":\"number\",\"boolean\":\"checkbox\",\"date\":\"date\",\"datetime\":\"dateTime\",\"formula\":\"text\"},\"textFallback\":[\"formula\"],\"lc8ToNative\":{\"text\":\"string\",\"number\":\"number\",\"checkbox\":\"boolean\",\"date\":\"date\",\"dateTime\":\"datetime\"}},\"mysql\":{\"connectorId\":\"mysql\",\"nativeToLc8\":{\"tinyint\":\"number\",\"smallint\":\"number\",\"mediumint\":\"number\",\"int\":\"number\",\"bigint\":\"number\",\"decimal\":\"number\",\"float\":\"number\",\"double\":\"number\",\"varchar\":\"text\",\"char\":\"text\",\"tinytext\":\"text\",\"text\":\"text\",\"mediumtext\":\"longText\",\"longtext\":\"longText\",\"boolean\":\"checkbox\",\"bit\":\"number\",\"date\":\"date\",\"datetime\":\"dateTime\",\"timestamp\":\"dateTime\",\"time\":\"text\",\"year\":\"number\",\"json\":\"longText\",\"enum\":\"singleSelect\",\"set\":\"multiSelect\",\"blob\":\"text\",\"tinyblob\":\"text\",\"mediumblob\":\"text\",\"longblob\":\"text\",\"binary\":\"text\",\"varbinary\":\"text\"},\"textFallback\":[\"time\",\"blob\",\"tinyblob\",\"mediumblob\",\"longblob\",\"binary\",\"varbinary\"],\"lc8ToNative\":{\"number\":\"decimal\",\"text\":\"varchar(255)\",\"checkbox\":\"tinyint(1)\",\"date\":\"date\",\"dateTime\":\"datetime\",\"longText\":\"text\",\"singleSelect\":\"varchar(255)\",\"multiSelect\":\"varchar(255)\"}},\"sqlserver\":{\"connectorId\":\"sqlserver\",\"nativeToLc8\":{\"tinyint\":\"number\",\"smallint\":\"number\",\"int\":\"number\",\"bigint\":\"number\",\"decimal\":\"number\",\"numeric\":\"number\",\"money\":\"number\",\"smallmoney\":\"number\",\"float\":\"number\",\"real\":\"number\",\"char\":\"text\",\"varchar\":\"text\",\"nchar\":\"text\",\"nvarchar\":\"text\",\"text\":\"longText\",\"ntext\":\"longText\",\"nvarchar(max)\":\"longText\",\"varchar(max)\":\"longText\",\"bit\":\"checkbox\",\"date\":\"date\",\"datetime\":\"dateTime\",\"datetime2\":\"dateTime\",\"smalldatetime\":\"dateTime\",\"datetimeoffset\":\"dateTime\",\"time\":\"text\",\"uniqueidentifier\":\"text\",\"xml\":\"longText\",\"json\":\"longText\"},\"textFallback\":[\"rowversion\",\"timestamp\",\"binary\",\"varbinary\",\"image\",\"geography\",\"geometry\",\"hierarchyid\",\"sql_variant\"],\"lc8ToNative\":{\"number\":\"decimal(18,4)\",\"text\":\"nvarchar(255)\",\"checkbox\":\"bit\",\"date\":\"date\",\"dateTime\":\"datetime2\",\"longText\":\"nvarchar(max)\",\"singleSelect\":\"nvarchar(255)\",\"multiSelect\":\"nvarchar(255)\",\"email\":\"nvarchar(320)\",\"phone\":\"nvarchar(50)\",\"url\":\"nvarchar(2048)\"}},\"sap-s4hana\":{\"connectorId\":\"sap-s4hana\",\"nativeToLc8\":{\"Edm.String\":\"text\",\"Edm.Guid\":\"text\",\"Edm.Boolean\":\"checkbox\",\"Edm.Byte\":\"number\",\"Edm.SByte\":\"number\",\"Edm.Int16\":\"number\",\"Edm.Int32\":\"number\",\"Edm.Int64\":\"number\",\"Edm.Single\":\"number\",\"Edm.Double\":\"number\",\"Edm.Decimal\":\"number\",\"Edm.Date\":\"date\",\"Edm.DateTime\":\"dateTime\",\"Edm.DateTimeOffset\":\"dateTime\",\"Edm.TimeOfDay\":\"text\",\"Edm.Time\":\"text\"},\"textFallback\":[\"Edm.Duration\",\"Edm.Binary\",\"Edm.Stream\",\"Edm.Geography\",\"Edm.GeographyPoint\"],\"lc8ToNative\":{\"number\":\"Edm.Decimal\",\"text\":\"Edm.String\",\"checkbox\":\"Edm.Boolean\",\"date\":\"Edm.Date\",\"dateTime\":\"Edm.DateTimeOffset\",\"longText\":\"Edm.String\",\"singleSelect\":\"Edm.String\",\"multiSelect\":\"Edm.String\",\"email\":\"Edm.String\",\"phone\":\"Edm.String\",\"url\":\"Edm.String\"}},\"business-central\":{\"connectorId\":\"business-central\",\"nativeToLc8\":{\"Edm.String\":\"text\",\"Edm.Guid\":\"text\",\"Edm.Boolean\":\"checkbox\",\"Edm.Byte\":\"number\",\"Edm.SByte\":\"number\",\"Edm.Int16\":\"number\",\"Edm.Int32\":\"number\",\"Edm.Int64\":\"number\",\"Edm.Single\":\"number\",\"Edm.Double\":\"number\",\"Edm.Decimal\":\"number\",\"Edm.Date\":\"date\",\"Edm.DateTime\":\"dateTime\",\"Edm.DateTimeOffset\":\"dateTime\",\"Edm.TimeOfDay\":\"text\",\"Edm.Time\":\"text\"},\"textFallback\":[\"Edm.Duration\",\"Edm.Binary\",\"Edm.Stream\",\"Edm.Geography\",\"Edm.GeographyPoint\"],\"lc8ToNative\":{\"number\":\"Edm.Decimal\",\"text\":\"Edm.String\",\"checkbox\":\"Edm.Boolean\",\"date\":\"Edm.Date\",\"dateTime\":\"Edm.DateTimeOffset\",\"longText\":\"Edm.String\",\"singleSelect\":\"Edm.String\",\"multiSelect\":\"Edm.String\",\"email\":\"Edm.String\",\"phone\":\"Edm.String\",\"url\":\"Edm.String\"}},\"epicor-kinetic\":{\"connectorId\":\"epicor-kinetic\",\"nativeToLc8\":{\"Edm.String\":\"text\",\"Edm.Guid\":\"text\",\"Edm.Boolean\":\"checkbox\",\"Edm.Byte\":\"number\",\"Edm.SByte\":\"number\",\"Edm.Int16\":\"number\",\"Edm.Int32\":\"number\",\"Edm.Int64\":\"number\",\"Edm.Single\":\"number\",\"Edm.Double\":\"number\",\"Edm.Decimal\":\"number\",\"Edm.Date\":\"date\",\"Edm.DateTime\":\"dateTime\",\"Edm.DateTimeOffset\":\"dateTime\",\"Edm.TimeOfDay\":\"text\",\"Edm.Time\":\"text\"},\"textFallback\":[\"Edm.Duration\",\"Edm.Binary\",\"Edm.Stream\",\"Edm.Geography\",\"Edm.GeographyPoint\"],\"lc8ToNative\":{\"number\":\"Edm.Decimal\",\"text\":\"Edm.String\",\"checkbox\":\"Edm.Boolean\",\"date\":\"Edm.Date\",\"dateTime\":\"Edm.DateTimeOffset\",\"longText\":\"Edm.String\",\"singleSelect\":\"Edm.String\",\"multiSelect\":\"Edm.String\",\"email\":\"Edm.String\",\"phone\":\"Edm.String\",\"url\":\"Edm.String\"}},\"microsoft-graph\":{\"connectorId\":\"microsoft-graph\",\"nativeToLc8\":{\"Edm.String\":\"text\",\"Edm.Guid\":\"text\",\"Edm.Boolean\":\"checkbox\",\"Edm.Byte\":\"number\",\"Edm.SByte\":\"number\",\"Edm.Int16\":\"number\",\"Edm.Int32\":\"number\",\"Edm.Int64\":\"number\",\"Edm.Single\":\"number\",\"Edm.Double\":\"number\",\"Edm.Decimal\":\"number\",\"Edm.Date\":\"date\",\"Edm.DateTime\":\"dateTime\",\"Edm.DateTimeOffset\":\"dateTime\",\"Edm.TimeOfDay\":\"text\",\"Edm.Time\":\"text\"},\"textFallback\":[\"Edm.Duration\",\"Edm.Binary\",\"Edm.Stream\",\"Edm.Geography\",\"Edm.GeographyPoint\"],\"lc8ToNative\":{\"number\":\"Edm.Decimal\",\"text\":\"Edm.String\",\"checkbox\":\"Edm.Boolean\",\"date\":\"Edm.Date\",\"dateTime\":\"Edm.DateTimeOffset\",\"longText\":\"Edm.String\",\"singleSelect\":\"Edm.String\",\"multiSelect\":\"Edm.String\",\"email\":\"Edm.String\",\"phone\":\"Edm.String\",\"url\":\"Edm.String\"}},\"dynamics-365\":{\"connectorId\":\"dynamics-365\",\"nativeToLc8\":{\"String\":\"text\",\"Memo\":\"longText\",\"Integer\":\"number\",\"BigInt\":\"number\",\"Decimal\":\"number\",\"Double\":\"number\",\"Money\":\"number\",\"Boolean\":\"checkbox\",\"DateTime\":\"dateTime\",\"Picklist\":\"singleSelect\",\"MultiSelectPicklist\":\"multiSelect\",\"State\":\"singleSelect\",\"Status\":\"singleSelect\",\"Uniqueidentifier\":\"text\"},\"textFallback\":[\"Lookup\",\"Customer\",\"Owner\",\"Image\",\"File\",\"Virtual\"],\"lc8ToNative\":{\"number\":\"Decimal\",\"text\":\"String\",\"checkbox\":\"Boolean\",\"date\":\"DateTime\",\"dateTime\":\"DateTime\",\"longText\":\"Memo\",\"singleSelect\":\"Picklist\",\"multiSelect\":\"MultiSelectPicklist\"}},\"microsoft-excel\":{\"connectorId\":\"microsoft-excel\",\"nativeToLc8\":{\"String\":\"text\",\"Double\":\"number\",\"Boolean\":\"checkbox\"},\"textFallback\":[\"Empty\",\"Error\"],\"lc8ToNative\":{\"number\":\"Double\",\"text\":\"String\",\"checkbox\":\"Boolean\",\"date\":\"Double\",\"dateTime\":\"Double\",\"longText\":\"String\",\"singleSelect\":\"String\",\"multiSelect\":\"String\"}},\"sharepoint\":{\"connectorId\":\"sharepoint\",\"nativeToLc8\":{\"Text\":\"text\",\"Note\":\"longText\",\"Choice\":\"singleSelect\",\"MultiChoice\":\"multiSelect\",\"Number\":\"number\",\"Currency\":\"number\",\"Counter\":\"number\",\"Boolean\":\"checkbox\",\"DateTime\":\"dateTime\",\"URL\":\"url\"},\"textFallback\":[\"User\",\"Lookup\",\"Calculated\",\"Attachments\"],\"lc8ToNative\":{\"number\":\"Number\",\"text\":\"Text\",\"checkbox\":\"Boolean\",\"date\":\"DateTime\",\"dateTime\":\"DateTime\",\"longText\":\"Note\",\"singleSelect\":\"Choice\",\"multiSelect\":\"MultiChoice\",\"url\":\"URL\"}},\"aveva-pi\":{\"connectorId\":\"aveva-pi\",\"nativeToLc8\":{\"Float16\":\"number\",\"Float32\":\"number\",\"Float64\":\"number\",\"Int16\":\"number\",\"Int32\":\"number\",\"Int64\":\"number\",\"Digital\":\"singleSelect\",\"String\":\"text\",\"Timestamp\":\"dateTime\"},\"textFallback\":[\"Blob\"],\"lc8ToNative\":{}},\"kepware\":{\"connectorId\":\"kepware\",\"nativeToLc8\":{\"Boolean\":\"checkbox\",\"SByte\":\"number\",\"Byte\":\"number\",\"Int16\":\"number\",\"UInt16\":\"number\",\"Int32\":\"number\",\"UInt32\":\"number\",\"Int64\":\"number\",\"UInt64\":\"number\",\"Float\":\"number\",\"Double\":\"number\",\"String\":\"text\",\"DateTime\":\"dateTime\"},\"textFallback\":[\"Guid\",\"ByteString\"],\"lc8ToNative\":{\"number\":\"Double\",\"text\":\"String\",\"checkbox\":\"Boolean\",\"dateTime\":\"DateTime\"}},\"salesforce\":{\"connectorId\":\"salesforce\",\"nativeToLc8\":{\"ID\":\"text\",\"reference\":\"text\",\"masterdetail\":\"text\",\"string\":\"text\",\"textarea\":\"longText\",\"longtextarea\":\"longText\",\"richtextarea\":\"longText\",\"email\":\"email\",\"phone\":\"phone\",\"url\":\"url\",\"integer\":\"number\",\"double\":\"number\",\"currency\":\"number\",\"percent\":\"number\",\"boolean\":\"checkbox\",\"date\":\"date\",\"datetime\":\"dateTime\",\"picklist\":\"singleSelect\",\"multipicklist\":\"multiSelect\",\"combobox\":\"text\",\"encryptedstring\":\"text\",\"address\":\"text\",\"location\":\"text\",\"anyType\":\"text\"},\"textFallback\":[\"encryptedstring\",\"address\",\"location\",\"anyType\",\"combobox\"],\"lc8ToNative\":{\"text\":\"string\",\"number\":\"double\",\"checkbox\":\"boolean\",\"date\":\"date\",\"dateTime\":\"datetime\",\"email\":\"email\",\"phone\":\"phone\",\"url\":\"url\",\"singleSelect\":\"picklist\",\"multiSelect\":\"multipicklist\"}}}"
}

// The registered maps by connector id: `{nativeToLc8, textFallback, lc8ToNative}`.
fn type_maps(a: *mem.Arena) -> json.Value {
    let (v, e) = json.parse(a, type_map_text(), json.Options { allow_duplicate_keys: false, max_depth: 20u16 })
    if e != ok { ret .Null }
    ret v
}

fn has_member(v: json.Value, key: str) -> bool {
    let (x, found) = sync.get(v, key)
    ret found
}

fn includes_text(values: json.Value, s: str) -> bool {
    let xs = sync.items(values)
    var at = 0usize
    while at < xs.len {
        let (t, is_text) = ir.string_of(xs[at])
        if is_text && str.eq(t, s) { ret true }
        at += 1usize
    }
    ret false
}

// The field type a connector's native type maps to: `{lc8Type, downgraded}` or, for a type with no equivalent, `{lc8Type:
// "text", downgraded: true, diagnostic}`. A connector with no map downgrades everything.
fn map_external_type(a: *mem.Arena, connector: str, native: json.Value, has_native: bool, translate: *const syncjob.Translate) -> json.Value {
    var o = sync.obj(a)
    let maps = type_maps(a)
    let (map, found) = sync.get(maps, connector)
    if !found {
        sync.put(&o, "lc8Type", sync.text("text"))
        sync.put(&o, "downgraded", sync.flag(true))
        sync.put(&o, "diagnostic", sync.text(translate.run(translate.ctx, "connectors.typeMap.noMapForConnector", connector)))
        ret ir.obj_value(&o)
    }
    let native_text = wb.js_string(a, native, has_native)
    let (lc8, have_lc8) = sync.get(ir.value_of(map, "nativeToLc8"), native_text)
    if have_lc8 && ir.truthy(lc8) {
        sync.put(&o, "lc8Type", lc8)
        sync.put(&o, "downgraded", sync.flag(false))
        ret ir.obj_value(&o)
    }
    sync.put(&o, "lc8Type", sync.text("text"))
    sync.put(&o, "downgraded", sync.flag(true))
    if has_native && includes_text(ir.value_of(map, "textFallback"), native_text) {
        sync.put(&o, "diagnostic", sync.text(translate.run(translate.ctx, "connectors.typeMap.noEquivalent", native_text)))
    } else {
        sync.put(&o, "diagnostic", sync.text(translate.run(translate.ctx, "connectors.typeMap.unrecognisedType", native_text)))
    }
    ret ir.obj_value(&o)
}

// The native type a field type is written as for a connector, or null.
fn map_lc8_to_native(a: *mem.Arena, connector: str, lc8: str) -> json.Value {
    let maps = type_maps(a)
    let (map, found) = sync.get(maps, connector)
    if !found { ret .Null }
    let (native, have) = sync.get(ir.value_of(map, "lc8ToNative"), lc8)
    if have && ir.truthy(native) { ret native }
    ret .Null
}

// The native types a connector's map knows, in registration order.
fn list_native_types(a: *mem.Arena, connector: str) -> json.Value {
    let maps = type_maps(a)
    let (map, found) = sync.get(maps, connector)
    if !found { ret ir.empty_array() }
    var out = sync.empty_list(a)
    let (members, is_object) = ir.members_of(ir.value_of(map, "nativeToLc8"))
    var at = 0usize
    while at < members.len {
        sync.push_value(&out, sync.text(members[at].key))
        at += 1usize
    }
    ret json.Value{ Array: list.slice_const[json.Value](&out) }
}

// `{proposed: [{name, lc8Type, nativeType, downgraded, diagnostic}], downgradeCount}` for a declared column list.
fn propose_schema(a: *mem.Arena, connector: str, columns: []const json.Value, translate: *const syncjob.Translate) -> json.Value {
    var proposed = sync.empty_list(a)
    var downgrades = 0i64
    var at = 0usize
    while at < columns.len {
        let column = columns[at]
        at += 1usize
        let (native, have_native) = sync.get(column, "nativeType")
        let mapped = map_external_type(a, connector, native, have_native, translate)
        if ir.truthy(ir.value_of(mapped, "downgraded")) { downgrades += 1i64 }
        var c = sync.obj(a)
        let (name, have_name) = sync.get(column, "name")
        if have_name { sync.put(&c, "name", name) }
        sync.put(&c, "lc8Type", ir.value_of(mapped, "lc8Type"))
        if have_native { sync.put(&c, "nativeType", native) }
        sync.put(&c, "downgraded", ir.value_of(mapped, "downgraded"))
        sync.put(&c, "diagnostic", ir.or_falsy(mapped, "diagnostic", .Null))
        sync.push_value(&proposed, ir.obj_value(&c))
    }
    var o = sync.obj(a)
    sync.put(&o, "proposed", json.Value{ Array: list.slice_const[json.Value](&proposed) })
    sync.put(&o, "downgradeCount", sync.number(a, downgrades))
    ret ir.obj_value(&o)
}

// The mapping proposed for a declared column list: `{columns, downgradeCount, inferred: false}`; `ok` is false when no
// columns were declared (the sample-inferred half is not ported).
fn propose_mapping(a: *mem.Arena, connector: str, columns: json.Value, translate: *const syncjob.Translate) -> (json.Value, bool) {
    let (xs, is_array) = ir.items_of(columns)
    if !is_array || xs.len == 0usize { ret (.Null, false) }
    let schema = propose_schema(a, connector, xs, translate)
    var out = sync.empty_list(a)
    let proposed = sync.items(ir.value_of(schema, "proposed"))
    var at = 0usize
    while at < proposed.len {
        var c = wb.copy_of(a, proposed[at])
        sync.put(&c, "diagnostic", ir.or_falsy(proposed[at], "diagnostic", .Null))
        sync.put(&c, "structured", sync.flag(false))
        sync.push_value(&out, ir.obj_value(&c))
        at += 1usize
    }
    var o = sync.obj(a)
    sync.put(&o, "columns", json.Value{ Array: list.slice_const[json.Value](&out) })
    sync.put(&o, "downgradeCount", ir.value_of(schema, "downgradeCount"))
    sync.put(&o, "inferred", sync.flag(false))
    ret (ir.obj_value(&o), true)
}

// A column's synced configuration: `{readOnly, synced: {source, nativeType, downgraded, diagnostic, direction}}`.
fn synced_column_config(a: *mem.Arena, column: json.Value, source_label: json.Value, has_label: bool) -> json.Value {
    let two_way = wb.pushes(column)
    let downgraded = wb.strict_true(column, "downgraded")
    var synced = sync.obj(a)
    if has_label { sync.put(&synced, "source", source_label) }
    let (native, have_native) = sync.get(column, "nativeType")
    if have_native { sync.put(&synced, "nativeType", native) }
    sync.put(&synced, "downgraded", sync.flag(downgraded))
    if downgraded { sync.put(&synced, "diagnostic", ir.or_falsy(column, "diagnostic", .Null)) } else { sync.put(&synced, "diagnostic", .Null) }
    if two_way { sync.put(&synced, "direction", ir.value_of(column, "direction")) } else { sync.put(&synced, "direction", sync.text("pull")) }
    var o = sync.obj(a)
    sync.put(&o, "readOnly", sync.flag(!two_way))
    sync.put(&o, "synced", ir.obj_value(&synced))
    ret ir.obj_value(&o)
}

// The badges a synced column shows: `{synced, badge, downgradeBadge, diagnostic}`.
fn synced_column_badge(a: *mem.Arena, config: json.Value, translate: *const syncjob.Translate) -> json.Value {
    var o = sync.obj(a)
    let synced = ir.value_of(config, "synced")
    if !ir.truthy(config) || !ir.truthy(synced) {
        sync.put(&o, "synced", sync.flag(false))
        sync.put(&o, "badge", .Null)
        sync.put(&o, "downgradeBadge", .Null)
        sync.put(&o, "diagnostic", .Null)
        ret ir.obj_value(&o)
    }
    let (source, have_source) = sync.get(synced, "source")
    sync.put(&o, "synced", sync.flag(true))
    sync.put(&o, "badge", sync.text(translate.run(translate.ctx, "sync.column.syncedFrom", wb.js_string(a, source, have_source))))
    if ir.truthy(ir.value_of(synced, "downgraded")) {
        sync.put(&o, "downgradeBadge", sync.text(translate.run(translate.ctx, "sync.column.downgraded", "")))
        sync.put(&o, "diagnostic", ir.or_falsy(synced, "diagnostic", .Null))
    } else {
        sync.put(&o, "downgradeBadge", .Null)
        sync.put(&o, "diagnostic", .Null)
    }
    ret ir.obj_value(&o)
}

// --- base URL and request --------------------------------------------------------------------------------------------

fn is_word_char(c: u8) -> bool { ret (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 95u8 }

// `{ok: true, baseUrl}` with each `{name}` filled from the configuration, or `{ok: false, reason}`: `no-base-url` when
// neither the configuration nor the channel has one, `incomplete-base-url` when a placeholder is left.
fn resolve_base_url(a: *mem.Arena, channel_base_url: json.Value, config: json.Value) -> json.Value {
    var o = sync.obj(a)
    let template_value = ir.or_falsy(config, "baseUrl", channel_base_url)
    var template = ""
    if ir.truthy(template_value) { template = wb.js_string(a, template_value, true) }
    if template.len == 0usize {
        sync.put(&o, "ok", sync.flag(false))
        sync.put(&o, "reason", sync.text("no-base-url"))
        ret ir.obj_value(&o)
    }
    let (b, e) = str.builder(a, template.len + 32usize)
    if e != ok { ret .Null }
    var out = b
    var at = 0usize
    while at < template.len {
        var replaced = false
        if template[at] == 123u8 {
            var end = at + 1usize
            while end < template.len && is_word_char(template[end]) { end += 1usize }
            if end > at + 1usize && end < template.len && template[end] == 125u8 {
                let name = template[at + 1usize..end]
                let (value, have) = sync.get(config, name)
                var usable = have && !ir.is_null(value)
                if usable {
                    let (s, is_text) = ir.string_of(value)
                    if is_text && s.len == 0usize { usable = false }
                }
                if usable {
                    let p = str.push(&out, wb.js_string(a, value, true))
                } else {
                    let p = str.push(&out, template[at..end + 1usize])
                }
                at = end + 1usize
                replaced = true
            }
        }
        if !replaced {
            let p = str.push_byte(&out, template[at])
            at += 1usize
        }
    }
    let filled = str.done(&out)
    if str.contains(filled, "{") {
        sync.put(&o, "ok", sync.flag(false))
        sync.put(&o, "reason", sync.text("incomplete-base-url"))
        ret ir.obj_value(&o)
    }
    sync.put(&o, "ok", sync.flag(true))
    sync.put(&o, "baseUrl", sync.text(filled))
    ret ir.obj_value(&o)
}

// A GET of the entity with the query: `{url, method, headers}` or `{url, error}` from the SSRF check.
fn build_pull_request(a: *mem.Arena, connection: json.Value, entity: str, query: json.Value) -> json.Value {
    var path = entity
    if !str.starts_with(path, "/") { path = sync.cat(a, "/", path) }
    var request = sync.obj(a)
    sync.put(&request, "path", sync.text(path))
    sync.put(&request, "method", sync.text("GET"))
    let (members, is_object) = ir.members_of(query)
    if ir.truthy(query) && is_object && members.len > 0usize { sync.put(&request, "query", query) }
    var conn = connection
    if !ir.truthy(connection) { conn = ir.empty_object() }
    ret wb.build_request(a, conn, ir.obj_value(&request))
}

// --- pagination ------------------------------------------------------------------------------------------------------

// A value at a dotted path or under the whole text as one key, null when absent.
fn pluck_path(a: *mem.Arena, body: json.Value, path: str) -> json.Value {
    if path.len == 0usize { ret body }
    let (whole, have_whole) = sync.get(body, path)
    if have_whole { ret whole }
    var cursor = body
    var start = 0usize
    var i = 0usize
    while i <= path.len {
        if i == path.len || path[i] == 46u8 {
            let key = path[start..i]
            start = i + 1usize
            let (members, is_object) = ir.members_of(cursor)
            let (elements, is_array) = ir.items_of(cursor)
            if is_object {
                let (next, found) = sync.get(cursor, key)
                if !found { ret .Null }
                cursor = next
            } else if is_array {
                if str.eq(key, "length") {
                    cursor = sync.number(a, i64(elements.len))
                } else if all_digits(key) && digits_at(key) < i64(elements.len) {
                    cursor = elements[usize(digits_at(key))]
                } else {
                    ret .Null
                }
            } else {
                ret .Null
            }
        }
        i += 1usize
    }
    ret cursor
}

fn all_digits(s: str) -> bool {
    if s.len == 0usize { ret false }
    var at = 0usize
    while at < s.len {
        if s[at] < 48u8 || s[at] > 57u8 { ret false }
        at += 1usize
    }
    ret true
}

fn digits_at(s: str) -> i64 {
    var n = 0i64
    var at = 0usize
    while at < s.len && at < 12usize {
        n = n * 10i64 + i64(s[at] - 48u8)
        at += 1usize
    }
    ret n
}

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 10u8 || c == 11u8 || c == 12u8 || c == 13u8 }

// The target of the first `<url>; rel="next"` in a Link header, or none.
fn next_link(link: str) -> (str, bool) {
    var at = 0usize
    while at < link.len {
        if link[at] == 60u8 {
            var close = at + 1usize
            while close < link.len && link[close] != 62u8 { close += 1usize }
            if close < link.len && close > at + 1usize {
                var k = close + 1usize
                if k < link.len && link[k] == 59u8 {
                    k += 1usize
                    while k < link.len && is_space(link[k]) { k += 1usize }
                    let want = "rel=\"next\""
                    if k + want.len <= link.len && str.eq(link[k..k + want.len], want) { ret (link[at + 1usize..close], true) }
                }
            }
        }
        at += 1usize
    }
    ret ("", false)
}

fn cursor_value(a: *mem.Arena, style: str, value: json.Value) -> json.Value {
    var o = sync.obj(a)
    sync.put(&o, "style", sync.text(style))
    sync.put(&o, "value", value)
    ret ir.obj_value(&o)
}

// The next-page cursor of a response, `{style, value}`, or null when there is none. `headers` is `{link|Link}`.
fn pull_cursor(a: *mem.Arena, body: json.Value, pagination: json.Value, headers: json.Value) -> json.Value {
    if !ir.truthy(pagination) { ret .Null }
    let style = wb.str_member(pagination, "style")
    if str.eq(style, "none") { ret .Null }
    if str.eq(style, "cursor") {
        var path = "next_cursor"
        let given = ir.value_of(pagination, "cursorPath")
        if ir.truthy(given) { path = wb.js_string(a, given, true) }
        let next = pluck_path(a, body, path)
        if !ir.truthy(next) { ret .Null }
        ret cursor_value(a, "cursor", sync.text(wb.js_string(a, next, true)))
    }
    if str.eq(style, "link-header") {
        let link = ir.or_falsy(headers, "link", ir.or_falsy(headers, "Link", sync.text("")))
        let (link_href, found) = next_link(wb.js_string(a, link, true))
        if !found { ret .Null }
        ret cursor_value(a, "link-header", sync.text(link_href))
    }
    if str.eq(style, "offset") || str.eq(style, "page") {
        var items_path = ""
        let given = ir.value_of(pagination, "itemsPath")
        if ir.truthy(given) { items_path = wb.js_string(a, given, true) }
        var found_items = pluck_path(a, body, items_path)
        if ir.is_null(found_items) { found_items = body }
        let (elements, is_array) = ir.items_of(found_items)
        var size = 0i64
        if is_array { size = i64(elements.len) }
        var limit = 100.0f64
        let given_limit = ir.value_of(pagination, "limit")
        if ir.truthy(given_limit) { limit = syncjob.number_or(given_limit, 100.0f64) }
        if size == 0i64 || f64(size) < limit { ret .Null }
        if str.eq(style, "page") { ret cursor_value(a, style, sync.number(a, 1i64)) }
        ret cursor_value(a, style, sync.number(a, size))
    }
    ret .Null
}

// --- URLs ------------------------------------------------------------------------------------------------------------

type Url = struct { valid: bool, origin: str, path: str, query: str }

fn bad_url() -> Url { ret Url { valid: false, origin: "", path: "", query: "" } }

fn hex_upper(n: u8) -> u8 {
    if n < 10u8 { ret 48u8 + n }
    ret 55u8 + n
}

fn path_encode_byte(c: u8) -> bool {
    ret c <= 32u8 || c == 34u8 || c == 35u8 || c == 60u8 || c == 62u8 || c == 63u8 || c == 96u8 || c == 123u8 || c == 125u8 || c >= 127u8
}

fn dot_segment(seg: str) -> i32 {
    if str.eq(seg, ".") || str.eq(seg, "%2e") || str.eq(seg, "%2E") { ret 1i32 }
    if str.eq(seg, "..") || str.eq(seg, ".%2e") || str.eq(seg, ".%2E") || str.eq(seg, "%2e.") || str.eq(seg, "%2E.") || str.eq(seg, "%2e%2e") || str.eq(seg, "%2E%2E") || str.eq(seg, "%2e%2E") || str.eq(seg, "%2E%2e") { ret 2i32 }
    ret 0i32
}

// The origin (`scheme://host[:port]`, a default port left out), the path and the query of an http(s) URL.
fn parse_url(a: *mem.Arena, text: str) -> Url {
    let p = ssrf.parse_href(a, text)
    if !p.valid || !p.special { ret bad_url() }
    if !str.eq(p.scheme, "http") && !str.eq(p.scheme, "https") { ret bad_url() }
    let trimmed = str.trim(text)
    let (colon, have_colon) = str.find(trimmed, ":")
    var rest = trimmed[colon + 1usize..trimmed.len]
    var k = 0usize
    while k < rest.len && (rest[k] == 47u8 || rest[k] == 92u8) { k += 1usize }
    rest = rest[k..rest.len]
    var fragment_at = rest.len
    var i = 0usize
    while i < rest.len {
        if rest[i] == 35u8 {
            fragment_at = i
            break
        }
        i += 1usize
    }
    rest = rest[0usize..fragment_at]
    var end = 0usize
    while end < rest.len && rest[end] != 47u8 && rest[end] != 92u8 && rest[end] != 63u8 { end += 1usize }
    let authority = rest[0usize..end]
    var tail = rest[end..rest.len]
    var query = ""
    let (path_text, query_text, has_query) = str.split_once(tail, "?")
    if has_query {
        tail = path_text
        query = query_text
    }
    // the port, from the last colon outside brackets
    var port_text = ""
    var last_colon = -1i64
    var close_bracket = -1i64
    var c = 0usize
    while c < authority.len {
        if authority[c] == 58u8 { last_colon = i64(c) }
        if authority[c] == 93u8 { close_bracket = i64(c) }
        if authority[c] == 64u8 {
            last_colon = -1i64
            close_bracket = -1i64
        }
        c += 1usize
    }
    if last_colon > close_bracket { port_text = authority[usize(last_colon) + 1usize..authority.len] }
    var port_value = 0i64
    var has_port = false
    if port_text.len > 0usize {
        if !all_digits(port_text) { ret bad_url() }
        has_port = true
        port_value = digits_at(port_text)
    }
    var origin = sync.cat(a, sync.cat(a, p.scheme, "://"), p.host)
    if has_port && !(port_value == 80i64 && str.eq(p.scheme, "http")) && !(port_value == 443i64 && str.eq(p.scheme, "https")) {
        origin = sync.cat(a, sync.cat(a, origin, ":"), wb.js_string(a, sync.number(a, port_value), true))
    }
    // the path: backslashes are slashes, dot segments resolved, the characters of the path encode set escaped
    if tail.len == 0usize { tail = "/" }
    let (segments_buf, e) = mem.alloc[str](a, tail.len + 2usize)
    var count = 0usize
    var start = 1usize
    var s = 1usize
    while s <= tail.len {
        if s == tail.len || tail[s] == 47u8 || tail[s] == 92u8 {
            let seg = tail[start..s]
            let kind = dot_segment(seg)
            let last = s == tail.len
            if kind == 2i32 {
                if count > 0usize { count -= 1usize }
                if last {
                    segments_buf[count] = ""
                    count += 1usize
                }
            } else if kind == 1i32 {
                if last {
                    segments_buf[count] = ""
                    count += 1usize
                }
            } else {
                segments_buf[count] = seg
                count += 1usize
            }
            start = s + 1usize
        }
        s += 1usize
    }
    let (b, be) = str.builder(a, tail.len * 3usize + 8usize)
    if be != ok { ret bad_url() }
    var out = b
    var n = 0usize
    while n < count {
        let pushed = str.push_byte(&out, 47u8)
        let seg = segments_buf[n]
        var m = 0usize
        while m < seg.len {
            let ch = seg[m]
            if path_encode_byte(ch) {
                let h1 = str.push_byte(&out, 37u8)
                let h2 = str.push_byte(&out, hex_upper(ch / 16u8))
                let h3 = str.push_byte(&out, hex_upper(ch % 16u8))
            } else {
                let h = str.push_byte(&out, ch)
            }
            m += 1usize
        }
        n += 1usize
    }
    ret Url { valid: true, origin: origin, path: str.done(&out), query: query }
}

fn hex_val(c: u8) -> i64 {
    if c >= 48u8 && c <= 57u8 { ret i64(c) - 48i64 }
    if c >= 97u8 && c <= 102u8 { ret i64(c) - 87i64 }
    if c >= 65u8 && c <= 70u8 { ret i64(c) - 55i64 }
    ret -1i64
}

fn form_decode(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    if e != ok { ret s }
    var n = 0usize
    var at = 0usize
    while at < s.len {
        let c = s[at]
        if c == 43u8 {
            out[n] = 32u8
            n += 1usize
            at += 1usize
        } else if c == 37u8 && at + 2usize < s.len + 0usize && hex_val(s[at + 1usize]) >= 0i64 && hex_val(s[at + 2usize]) >= 0i64 {
            out[n] = u8(hex_val(s[at + 1usize]) * 16i64 + hex_val(s[at + 2usize]))
            n += 1usize
            at += 3usize
        } else {
            out[n] = c
            n += 1usize
            at += 1usize
        }
    }
    ret out[0usize..n]
}

// A query string as an object: later pairs of a name replace the value, keeping the name's first position.
fn query_object(a: *mem.Arena, query: str) -> json.Value {
    var o = sync.obj(a)
    var at = 0usize
    while at <= query.len {
        var end = at
        while end < query.len && query[end] != 38u8 { end += 1usize }
        let pair = query[at..end]
        if pair.len > 0usize {
            let (k, v, found) = str.split_once(pair, "=")
            var key = pair
            var value = ""
            if found {
                key = k
                value = v
            }
            sync.put(&o, form_decode(a, key), sync.text(form_decode(a, value)))
        }
        at = end + 1usize
    }
    ret ir.obj_value(&o)
}

// `{path, query}` of an absolute cursor URL relative to the base URL, or `{refused}` when it is not a URL or not on the
// base's origin.
fn relative_to(a: *mem.Arena, base_url: str, absolute: str) -> json.Value {
    var o = sync.obj(a)
    let base = parse_url(a, base_url)
    let next = parse_url(a, absolute)
    if !base.valid || !next.valid {
        sync.put(&o, "refused", sync.text("cursor-not-a-url"))
        ret ir.obj_value(&o)
    }
    if !str.eq(base.origin, next.origin) {
        sync.put(&o, "refused", sync.text("cursor-off-origin"))
        ret ir.obj_value(&o)
    }
    var prefix = base.path
    while prefix.len > 0usize && prefix[prefix.len - 1usize] == 47u8 { prefix = prefix[0usize..prefix.len - 1usize] }
    var path = next.path
    if prefix.len > 0usize && str.starts_with(next.path, sync.cat(a, prefix, "/")) { path = next.path[prefix.len..next.path.len] }
    sync.put(&o, "path", sync.text(path))
    sync.put(&o, "query", query_object(a, next.query))
    ret ir.obj_value(&o)
}

// `Number(v)` of a scalar: a number as is, a numeric text parsed (NaN when it is not one), a boolean 1 or 0; a
// container is NaN.
fn js_number(v: json.Value) -> f64 {
    switch v {
    case .Number as n:
        let (x, e) = json.number_f64(n)
        if e == ok { ret x }
        ret syncjob.nan()
    case .String as s:
        ret syncjob.parse_decimal(str.trim(s))
    case .Bool as b:
        if b { ret 1.0f64 }
        ret 0.0f64
    case .Null:
        ret 0.0f64
    default:
        ret syncjob.nan()
    }
}

// `Number(query[param] || fallback) + plus` as a number value, null where that is NaN.
fn step_value(a: *mem.Arena, query: json.Value, param: str, fallback: f64, plus: f64) -> json.Value {
    let held = ir.value_of(query, param)
    var current = fallback
    if ir.truthy(held) { current = js_number(held) }
    let total = current + plus
    if total != total { ret .Null }
    ret syncjob.number_value(a, total)
}

// What to ask next after a page: `{done: true}`, `{refused}`, or `{path, query}`.
fn advance_pull(a: *mem.Arena, cursor: json.Value, pagination: json.Value, path: str, query: json.Value, base_url: str) -> json.Value {
    var o = sync.obj(a)
    if !ir.truthy(cursor) {
        sync.put(&o, "done", sync.flag(true))
        ret ir.obj_value(&o)
    }
    let style = wb.str_member(cursor, "style")
    let value = ir.value_of(cursor, "value")
    if str.eq(style, "link-header") { ret relative_to(a, base_url, wb.js_string(a, value, true)) }
    var next_query = wb.copy_of(a, query)
    if str.eq(style, "cursor") {
        let text = wb.js_string(a, value, true)
        if is_http_url(a, text) { ret relative_to(a, base_url, text) }
        let param = wb.js_string(a, ir.or_falsy(pagination, "cursorParam", sync.text("cursor")), true)
        sync.put(&next_query, param, value)
    } else if str.eq(style, "offset") {
        let param = wb.js_string(a, ir.or_falsy(pagination, "offsetParam", sync.text("offset")), true)
        let step = js_number(value)
        sync.put(&next_query, param, step_value(a, query, param, 0.0f64, step))
    } else if str.eq(style, "page") {
        let param = wb.js_string(a, ir.or_falsy(pagination, "pageParam", sync.text("page")), true)
        sync.put(&next_query, param, step_value(a, query, param, 1.0f64, 1.0f64))
    } else {
        sync.put(&o, "done", sync.flag(true))
        ret ir.obj_value(&o)
    }
    sync.put(&o, "path", sync.text(path))
    sync.put(&o, "query", ir.obj_value(&next_query))
    ret ir.obj_value(&o)
}

fn is_http_url(a: *mem.Arena, s: str) -> bool {
    let lowered = wb.lower_ascii(a, s)
    ret str.starts_with(lowered, "http://") || str.starts_with(lowered, "https://")
}

// --- records and pages -----------------------------------------------------------------------------------------------

fn segments_of(a: *mem.Arena, path: str) -> []const str {
    var text = path
    let (head, tail, has_query) = str.split_once(text, "?")
    if has_query { text = head }
    var from = 0usize
    var to = text.len
    while from < to && text[from] == 47u8 { from += 1usize }
    while to > from && text[to - 1usize] == 47u8 { to -= 1usize }
    let clean = text[from..to]
    if clean.len == 0usize { ret zero }
    let (buf, e) = mem.alloc[str](a, clean.len + 2usize)
    if e != ok { ret zero }
    var count = 0usize
    var start = 0usize
    var at = 0usize
    while at <= clean.len {
        if at == clean.len || clean[at] == 47u8 {
            buf[count] = clean[start..at]
            count += 1usize
            start = at + 1usize
        }
        at += 1usize
    }
    ret buf[0usize..count]
}

fn path_matches(declared: []const str, entity: []const str) -> bool {
    if declared.len != entity.len { ret false }
    var at = 0usize
    while at < declared.len {
        let seg = declared[at]
        let placeholder = seg.len >= 2usize && seg[0] == 123u8 && seg[seg.len - 1usize] == 125u8
        if placeholder {
            if entity[at].len == 0usize { ret false }
        } else if !str.eq(seg, entity[at]) {
            ret false
        }
        at += 1usize
    }
    ret true
}

// The pagination a channel declares for the GET action whose path matches the entity, preferring the path with the
// fewest `{placeholders}`; null when none declares one.
fn pull_pagination(a: *mem.Arena, channel: json.Value, entity: str) -> json.Value {
    let actions = ir.value_of(channel, "actions")
    if !ir.truthy(channel) || !ir.truthy(actions) { ret .Null }
    let wanted = segments_of(a, entity)
    if wanted.len == 0usize { ret .Null }
    var best: json.Value = .Null
    var fewest = 1000000i64
    let (members, is_object) = ir.members_of(actions)
    var at = 0usize
    while at < members.len {
        let action = members[at].value
        at += 1usize
        if !wb.member_is(action, "method", "GET") { continue }
        let declared = ir.value_of(action, "pagination")
        if !ir.truthy(declared) { continue }
        let style = ir.value_of(declared, "style")
        if !ir.truthy(style) || wb.member_is(declared, "style", "none") { continue }
        let segs = segments_of(a, wb.js_string(a, ir.or_falsy(action, "path", sync.text("")), true))
        if !path_matches(segs, wanted) { continue }
        var placeholders = 0i64
        var k = 0usize
        while k < segs.len {
            if segs[k].len > 0usize && segs[k][0] == 123u8 { placeholders += 1i64 }
            k += 1usize
        }
        if placeholders < fewest {
            best = declared
            fewest = placeholders
        }
    }
    ret best
}

fn record_shape(a: *mem.Arena, name: str) -> json.Value {
    var o = sync.obj(a)
    if str.eq(name, "airtable") {
        sync.put(&o, "fieldsPath", sync.text("fields"))
        var keep = sync.empty_list(a)
        sync.push_value(&keep, sync.text("id"))
        sync.push_value(&keep, sync.text("createdTime"))
        sync.put(&o, "keep", json.Value{ Array: list.slice_const[json.Value](&keep) })
        ret ir.obj_value(&o)
    }
    if str.eq(name, "notion") {
        sync.put(&o, "fieldsPath", sync.text("properties"))
        var keep = sync.empty_list(a)
        sync.push_value(&keep, sync.text("id"))
        sync.push_value(&keep, sync.text("created_time"))
        sync.push_value(&keep, sync.text("last_edited_time"))
        sync.put(&o, "keep", json.Value{ Array: list.slice_const[json.Value](&keep) })
        ret ir.obj_value(&o)
    }
    ret .Null
}

// A record with the envelope's fields lifted to its top level, next to the members the shape keeps; a lifted name that a
// kept member holds is prefixed with the envelope's path. A record without the envelope is returned as it is.
fn unwrap_record(a: *mem.Arena, shape: json.Value, record: json.Value) -> json.Value {
    if !ir.truthy(shape) { ret record }
    let (record_members, is_object) = ir.members_of(record)
    if !is_object { ret record }
    let fields_path = wb.js_string(a, ir.value_of(shape, "fieldsPath"), true)
    let fields = pluck_path(a, record, fields_path)
    let (field_members, fields_are_object) = ir.members_of(fields)
    if !fields_are_object { ret record }
    var out = sync.obj(a)
    let kept = sync.items(ir.value_of(shape, "keep"))
    var at = 0usize
    while at < kept.len {
        let (name, is_text) = ir.string_of(kept[at])
        at += 1usize
        if !is_text { continue }
        let (value, have) = sync.get(record, name)
        if have { sync.put(&out, name, value) }
    }
    var f = 0usize
    while f < field_members.len {
        let key = field_members[f].key
        let (existing, held) = sync.get(ir.obj_value(&out), key)
        if held {
            sync.put(&out, sync.cat(a, sync.cat(a, fields_path, "."), key), field_members[f].value)
        } else {
            sync.put(&out, key, field_members[f].value)
        }
        f += 1usize
    }
    ret ir.obj_value(&out)
}

// The records of a batch unwrapped through the shape, or the batch itself when there is none.
fn unwrap_records(a: *mem.Arena, shape: json.Value, records: json.Value) -> []const json.Value {
    let rows = sync.items(records)
    if !ir.truthy(shape) { ret rows }
    var out = sync.empty_list(a)
    var at = 0usize
    while at < rows.len {
        sync.push_value(&out, unwrap_record(a, shape, rows[at]))
        at += 1usize
    }
    ret list.slice_const[json.Value](&out)
}

// The envelope shape to unwrap a source's records with: the channel's own `recordShape`, else a known vendor's, unless
// the stored mapping keeps the blob as its one structured column; null when none.
fn pull_record_shape(a: *mem.Arena, channel: json.Value, connector: json.Value, stored_mapping: json.Value) -> json.Value {
    var id = ""
    if ir.truthy(connector) {
        id = wb.js_string(a, connector, true)
    } else {
        let own = ir.value_of(channel, "id")
        if ir.truthy(own) { id = wb.js_string(a, own, true) }
    }
    var shape = ir.value_of(channel, "recordShape")
    if !ir.truthy(shape) { shape = record_shape(a, id) }
    if !ir.truthy(shape) { ret .Null }
    let stored = sync.items(stored_mapping)
    let fields_path = wb.js_string(a, ir.value_of(shape, "fieldsPath"), true)
    let keep = ir.value_of(shape, "keep")
    var blob = false
    var nothing_else = true
    var at = 0usize
    while at < stored.len {
        let column = stored[at]
        at += 1usize
        let name = wb.str_member(column, "name")
        let present = ir.truthy(column)
        if present && str.eq(name, fields_path) && wb.strict_true(column, "structured") { blob = true }
        if !present || !(str.eq(name, fields_path) || includes_text(keep, name)) { nothing_else = false }
    }
    if blob && nothing_else { ret .Null }
    ret shape
}

fn failed_pull(a: *mem.Arena, reason: str, status: json.Value, has_status: bool) -> json.Value {
    var o = sync.obj(a)
    sync.put(&o, "ok", sync.flag(false))
    sync.put(&o, "reason", sync.text(reason))
    if has_status { sync.put(&o, "status", status) }
    ret ir.obj_value(&o)
}

fn asked_before(asked: list.List[json.Value], url: str) -> bool {
    var at = 0usize
    while at < asked.len {
        let (s, is_text) = ir.string_of(asked.items[at])
        if is_text && str.eq(s, url) { ret true }
        at += 1usize
    }
    ret false
}

// Page through a source: `{ok: true, rows, pages, truncated}` or `{ok: false, reason, status?}`. `limit` stops once that
// many rows are read (`has_limit`); the page and record ceilings stop a runaway.
fn pull_pages(a: *mem.Arena, connection: json.Value, entity: str, pagination: json.Value, shape: json.Value, limit: i64, has_limit: bool, fetch: *const FetchPage) -> json.Value {
    var rows = sync.empty_list(a)
    var asked = sync.empty_list(a)
    var path = entity
    var query: json.Value = ir.empty_object()
    var pages = 0i64
    var truncated: json.Value = .Null
    var done = false
    var base_url = ""
    let (b, have_base) = sync.member_text(connection, "baseUrl")
    if have_base { base_url = b }
    while !done {
        let request = build_pull_request(a, connection, path, query)
        let (problem, have_problem) = sync.member_text(request, "error")
        if have_problem { ret failed_pull(a, problem, .Null, false) }
        let url = wb.str_member(request, "url")
        if asked_before(asked, url) {
            truncated = sync.text("cursor-not-advancing")
            break
        }
        sync.push_value(&asked, sync.text(url))
        let page = fetch.run(fetch.ctx, request)
        if !ir.truthy(page) || !ir.truthy(ir.value_of(page, "ok")) {
            var reason = "source-unreachable"
            if ir.truthy(page) {
                let given = ir.value_of(page, "reason")
                if ir.truthy(given) { reason = wb.js_string(a, given, true) }
            }
            if !ir.truthy(page) { ret failed_pull(a, reason, .Null, true) }
            let (status, have_status) = sync.get(page, "status")
            ret failed_pull(a, reason, status, have_status)
        }
        let body = ir.value_of(page, "body")
        let (batch, listed) = syncjob.records_from_body(body)
        if !listed { ret failed_pull(a, "source-not-a-record-list", .Null, false) }
        let unwrapped = unwrap_records(a, shape, batch)
        var at = 0usize
        while at < unwrapped.len {
            sync.push_value(&rows, unwrapped[at])
            at += 1usize
        }
        pages += 1i64
        if has_limit && i64(rows.len) >= limit { break }
        if i64(rows.len) >= max_pull_records() {
            truncated = sync.text("record-ceiling")
            break
        }
        if pages >= max_pull_pages() {
            truncated = sync.text("page-ceiling")
            break
        }
        let cursor = pull_cursor(a, body, pagination, ir.or_falsy(page, "headers", ir.empty_object()))
        let next = advance_pull(a, cursor, pagination, path, query, base_url)
        if ir.truthy(ir.value_of(next, "done")) { break }
        let (refused, was_refused) = sync.member_text(next, "refused")
        if was_refused {
            truncated = sync.text(refused)
            break
        }
        path = wb.str_member(next, "path")
        query = ir.value_of(next, "query")
    }
    var result = list.slice_const[json.Value](&rows)
    if has_limit && i64(result.len) > limit {
        var keep = limit
        if keep < 0i64 { keep = 0i64 }
        result = result[0usize..usize(keep)]
    }
    var o = sync.obj(a)
    sync.put(&o, "ok", sync.flag(true))
    sync.put(&o, "rows", json.Value{ Array: result })
    sync.put(&o, "pages", sync.number(a, pages))
    sync.put(&o, "truncated", truncated)
    ret ir.obj_value(&o)
}
