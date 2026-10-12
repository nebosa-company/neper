// `e.fmt.cap` against an ElementTree walk of CAP 1.2 documents (scripts/gen_cap_test.py): a two-language alert
// with entities, CDATA, repeated categories and areas; a cancel message; a prefixed alert; and refusals. Every check
// has its own exit code.
use e.os
use e.mem
use e.str
use e.fmt.cap as cap

fn main(a: *mem.Arena, args: []str) -> err {
    let doc_two = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<alert xmlns=\"urn:oasis:names:tc:emergency:cap:1.2\">\n  <identifier>NWS-IDP-PROD-1234567</identifier>\n  <sender>w-nws.webmaster@noaa.gov</sender>\n  <sent>2026-10-12T09:30:00-07:00</sent>\n  <status>Actual</status>\n  <msgType>Alert</msgType>\n  <scope>Public</scope>\n  <info>\n    <language>en-US</language>\n    <category>Met</category>\n    <category>Safety</category>\n    <event>Severe Thunderstorm Warning</event>\n    <urgency>Immediate</urgency>\n    <severity>Severe</severity>\n    <certainty>Observed</certainty>\n    <effective>2026-10-12T09:30:00-07:00</effective>\n    <expires>2026-10-12T10:15:00-07:00</expires>\n    <senderName>NWS Seattle WA</senderName>\n    <headline>Severe Thunderstorm Warning issued October 12 at 9:30AM PDT</headline>\n    <description>At 930 AM PDT, a severe thunderstorm was located near Kent &amp; Auburn, moving east at 25 mph.</description>\n    <instruction><![CDATA[Move indoors <now>. Stay away from windows.]]></instruction>\n    <web>https://www.weather.gov/sew</web>\n    <area>\n      <areaDesc>King County; Pierce County</areaDesc>\n      <geocode><valueName>SAME</valueName><value>053033</value></geocode>\n    </area>\n    <area><areaDesc>Snohomish County</areaDesc></area>\n  </info>\n  <info>\n    <language>es-US</language>\n    <event>Aviso de tormenta severa</event>\n    <urgency>Immediate</urgency>\n    <severity>Severe</severity>\n    <certainty>Observed</certainty>\n    <headline>Aviso de tormenta severa</headline>\n    <area><areaDesc>Condado de King</areaDesc></area>\n  </info>\n</alert>\n"
    let (two, e_two) = cap.parse(a, doc_two)
    if e_two != ok { os.exit(1) }
    if !str.eq(two.identifier, "NWS-IDP-PROD-1234567") { os.exit(2) }
    if !str.eq(two.sender, "w-nws.webmaster@noaa.gov") { os.exit(3) }
    if !str.eq(two.sent, "2026-10-12T09:30:00-07:00") { os.exit(4) }
    if !str.eq(two.status, "Actual") { os.exit(5) }
    if !str.eq(two.message_type, "Alert") { os.exit(6) }
    if !str.eq(two.scope, "Public") { os.exit(7) }
    if two.infos.len != 2usize { os.exit(8) }
    if !str.eq(two.infos[0].language, "en-US") { os.exit(9) }
    if !str.eq(two.infos[0].category, "Met") { os.exit(10) }
    if !str.eq(two.infos[0].event, "Severe Thunderstorm Warning") { os.exit(11) }
    if !str.eq(two.infos[0].urgency, "Immediate") { os.exit(12) }
    if !str.eq(two.infos[0].severity, "Severe") { os.exit(13) }
    if !str.eq(two.infos[0].certainty, "Observed") { os.exit(14) }
    if !str.eq(two.infos[0].effective, "2026-10-12T09:30:00-07:00") { os.exit(15) }
    if !str.eq(two.infos[0].onset, "") { os.exit(16) }
    if !str.eq(two.infos[0].expires, "2026-10-12T10:15:00-07:00") { os.exit(17) }
    if !str.eq(two.infos[0].sender_name, "NWS Seattle WA") { os.exit(18) }
    if !str.eq(two.infos[0].headline, "Severe Thunderstorm Warning issued October 12 at 9:30AM PDT") { os.exit(19) }
    if !str.eq(two.infos[0].description, "At 930 AM PDT, a severe thunderstorm was located near Kent & Auburn, moving east at 25 mph.") { os.exit(20) }
    if !str.eq(two.infos[0].instruction, "Move indoors <now>. Stay away from windows.") { os.exit(21) }
    if !str.eq(two.infos[0].web, "https://www.weather.gov/sew") { os.exit(22) }
    if !str.eq(two.infos[0].area_description, "King County; Pierce County") { os.exit(23) }
    if two.infos[0].areas != 2usize { os.exit(24) }
    if !str.eq(two.infos[1].language, "es-US") { os.exit(25) }
    if !str.eq(two.infos[1].category, "") { os.exit(26) }
    if !str.eq(two.infos[1].event, "Aviso de tormenta severa") { os.exit(27) }
    if !str.eq(two.infos[1].urgency, "Immediate") { os.exit(28) }
    if !str.eq(two.infos[1].severity, "Severe") { os.exit(29) }
    if !str.eq(two.infos[1].certainty, "Observed") { os.exit(30) }
    if !str.eq(two.infos[1].effective, "") { os.exit(31) }
    if !str.eq(two.infos[1].onset, "") { os.exit(32) }
    if !str.eq(two.infos[1].expires, "") { os.exit(33) }
    if !str.eq(two.infos[1].sender_name, "") { os.exit(34) }
    if !str.eq(two.infos[1].headline, "Aviso de tormenta severa") { os.exit(35) }
    if !str.eq(two.infos[1].description, "") { os.exit(36) }
    if !str.eq(two.infos[1].instruction, "") { os.exit(37) }
    if !str.eq(two.infos[1].web, "") { os.exit(38) }
    if !str.eq(two.infos[1].area_description, "Condado de King") { os.exit(39) }
    if two.infos[1].areas != 1usize { os.exit(40) }
    let doc_cancel = "<alert xmlns=\"urn:oasis:names:tc:emergency:cap:1.2\"><identifier>c-1</identifier><sender>a@b</sender><sent>2026-10-12T10:00:00Z</sent>\n<status>Actual</status><msgType>Cancel</msgType><scope>Public</scope><references>a@b,x-1,2026-10-12T09:30:00Z</references></alert>"
    let (cancel, e_cancel) = cap.parse(a, doc_cancel)
    if e_cancel != ok { os.exit(41) }
    if !str.eq(cancel.identifier, "c-1") { os.exit(42) }
    if !str.eq(cancel.sender, "a@b") { os.exit(43) }
    if !str.eq(cancel.sent, "2026-10-12T10:00:00Z") { os.exit(44) }
    if !str.eq(cancel.status, "Actual") { os.exit(45) }
    if !str.eq(cancel.message_type, "Cancel") { os.exit(46) }
    if !str.eq(cancel.scope, "Public") { os.exit(47) }
    if cancel.infos.len != 0usize { os.exit(48) }
    let doc_prefixed = "<cap:alert xmlns:cap=\"urn:oasis:names:tc:emergency:cap:1.2\"><cap:identifier>p-9</cap:identifier>\n<cap:sender>met.no</cap:sender><cap:sent>2026-10-12T06:00:00+00:00</cap:sent><cap:status>Test</cap:status>\n<cap:msgType>Alert</cap:msgType><cap:scope>Restricted</cap:scope>\n<cap:info><cap:event>Gale warning</cap:event><cap:severity>Moderate</cap:severity><cap:urgency>Expected</cap:urgency>\n<cap:certainty>Likely</cap:certainty><cap:area><cap:areaDesc>Vestlandet</cap:areaDesc></cap:area></cap:info></cap:alert>"
    let (prefixed, e_prefixed) = cap.parse(a, doc_prefixed)
    if e_prefixed != ok { os.exit(49) }
    if !str.eq(prefixed.identifier, "p-9") { os.exit(50) }
    if !str.eq(prefixed.sender, "met.no") { os.exit(51) }
    if !str.eq(prefixed.sent, "2026-10-12T06:00:00+00:00") { os.exit(52) }
    if !str.eq(prefixed.status, "Test") { os.exit(53) }
    if !str.eq(prefixed.message_type, "Alert") { os.exit(54) }
    if !str.eq(prefixed.scope, "Restricted") { os.exit(55) }
    if prefixed.infos.len != 1usize { os.exit(56) }
    if !str.eq(prefixed.infos[0].language, "") { os.exit(57) }
    if !str.eq(prefixed.infos[0].category, "") { os.exit(58) }
    if !str.eq(prefixed.infos[0].event, "Gale warning") { os.exit(59) }
    if !str.eq(prefixed.infos[0].urgency, "Expected") { os.exit(60) }
    if !str.eq(prefixed.infos[0].severity, "Moderate") { os.exit(61) }
    if !str.eq(prefixed.infos[0].certainty, "Likely") { os.exit(62) }
    if !str.eq(prefixed.infos[0].effective, "") { os.exit(63) }
    if !str.eq(prefixed.infos[0].onset, "") { os.exit(64) }
    if !str.eq(prefixed.infos[0].expires, "") { os.exit(65) }
    if !str.eq(prefixed.infos[0].sender_name, "") { os.exit(66) }
    if !str.eq(prefixed.infos[0].headline, "") { os.exit(67) }
    if !str.eq(prefixed.infos[0].description, "") { os.exit(68) }
    if !str.eq(prefixed.infos[0].instruction, "") { os.exit(69) }
    if !str.eq(prefixed.infos[0].web, "") { os.exit(70) }
    if !str.eq(prefixed.infos[0].area_description, "Vestlandet") { os.exit(71) }
    if prefixed.infos[0].areas != 1usize { os.exit(72) }
    let (nc, nce) = cap.parse(a, "<feed><title>not an alert</title></feed>")
    if nce != cap.NotCap { os.exit(73) }
    let (br, bre) = cap.parse(a, "<alert><identifier>x</alert>")
    if bre == ok { os.exit(74) }
    ret ok
}
