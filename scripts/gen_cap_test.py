#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/fmt_cap/src/main.e (C156): e.fmt.cap against CAP 1.2 documents read by an
independent ElementTree walk. Documents: a two-language alert with areas, entities and CDATA; a minimal cancel
message; a namespace-prefixed alert; and refusals (a different root, malformed XML)."""
import xml.etree.ElementTree as ET
from pathlib import Path

NS = "urn:oasis:names:tc:emergency:cap:1.2"

DOCS = {}
DOCS["two"] = f'''<?xml version="1.0" encoding="UTF-8"?>
<alert xmlns="{NS}">
  <identifier>NWS-IDP-PROD-1234567</identifier>
  <sender>w-nws.webmaster@noaa.gov</sender>
  <sent>2026-10-12T09:30:00-07:00</sent>
  <status>Actual</status>
  <msgType>Alert</msgType>
  <scope>Public</scope>
  <info>
    <language>en-US</language>
    <category>Met</category>
    <category>Safety</category>
    <event>Severe Thunderstorm Warning</event>
    <urgency>Immediate</urgency>
    <severity>Severe</severity>
    <certainty>Observed</certainty>
    <effective>2026-10-12T09:30:00-07:00</effective>
    <expires>2026-10-12T10:15:00-07:00</expires>
    <senderName>NWS Seattle WA</senderName>
    <headline>Severe Thunderstorm Warning issued October 12 at 9:30AM PDT</headline>
    <description>At 930 AM PDT, a severe thunderstorm was located near Kent &amp; Auburn, moving east at 25 mph.</description>
    <instruction><![CDATA[Move indoors <now>. Stay away from windows.]]></instruction>
    <web>https://www.weather.gov/sew</web>
    <area>
      <areaDesc>King County; Pierce County</areaDesc>
      <geocode><valueName>SAME</valueName><value>053033</value></geocode>
    </area>
    <area><areaDesc>Snohomish County</areaDesc></area>
  </info>
  <info>
    <language>es-US</language>
    <event>Aviso de tormenta severa</event>
    <urgency>Immediate</urgency>
    <severity>Severe</severity>
    <certainty>Observed</certainty>
    <headline>Aviso de tormenta severa</headline>
    <area><areaDesc>Condado de King</areaDesc></area>
  </info>
</alert>
'''
DOCS["cancel"] = f'''<alert xmlns="{NS}"><identifier>c-1</identifier><sender>a@b</sender><sent>2026-10-12T10:00:00Z</sent>
<status>Actual</status><msgType>Cancel</msgType><scope>Public</scope><references>a@b,x-1,2026-10-12T09:30:00Z</references></alert>'''
DOCS["prefixed"] = '''<cap:alert xmlns:cap="urn:oasis:names:tc:emergency:cap:1.2"><cap:identifier>p-9</cap:identifier>
<cap:sender>met.no</cap:sender><cap:sent>2026-10-12T06:00:00+00:00</cap:sent><cap:status>Test</cap:status>
<cap:msgType>Alert</cap:msgType><cap:scope>Restricted</cap:scope>
<cap:info><cap:event>Gale warning</cap:event><cap:severity>Moderate</cap:severity><cap:urgency>Expected</cap:urgency>
<cap:certainty>Likely</cap:certainty><cap:area><cap:areaDesc>Vestlandet</cap:areaDesc></cap:area></cap:info></cap:alert>'''
NOT_CAP = "<feed><title>not an alert</title></feed>"
BROKEN = "<alert><identifier>x</alert>"


def strip(tag):
    return tag.rsplit("}", 1)[-1]


def parse(text):
    root = ET.fromstring(text)
    alert = {"infos": []}
    for child in root:
        name = strip(child.tag)
        if name == "info":
            info = {"areas": 0, "area_description": ""}
            for f in child:
                n = strip(f.tag)
                if n == "area":
                    info["areas"] += 1
                    if info["areas"] == 1:
                        for part in f:
                            if strip(part.tag) == "areaDesc":
                                info["area_description"] = (part.text or "").strip()
                else:
                    value = (f.text or "").strip()
                    if n == "category":
                        info.setdefault("category", value)
                    else:
                        info[n] = value
            alert["infos"].append(info)
        else:
            alert[name] = (child.text or "").strip()
    return alert


def e_string(s):
    out = ""
    for ch in s:
        out += {"\n": "\\n", "\t": "\\t", '"': '\\"', "\\": "\\\\"}.get(ch, ch)
    return '"%s"' % out


def main():
    out = ["// `e.fmt.cap` against an ElementTree walk of CAP 1.2 documents (scripts/gen_cap_test.py): a two-language alert\n",
           "// with entities, CDATA, repeated categories and areas; a cancel message; a prefixed alert; and refusals. Every check\n",
           "// has its own exit code.\n",
           "use e.os\nuse e.mem\nuse e.str\nuse e.fmt.cap as cap\n\n",
           "fn main(a: *mem.Arena, args: []str) -> err {\n"]
    n = 0

    def check(cond):
        nonlocal n
        n += 1
        out.append("    if %s { os.exit(%d) }\n" % (cond, n))

    for key in ("two", "cancel", "prefixed"):
        text = DOCS[key]
        expected = parse(text)
        out.append("    let doc_%s = %s\n" % (key, e_string(text)))
        out.append("    let (%s, e_%s) = cap.parse(a, doc_%s)\n" % (key, key, key))
        check("e_%s != ok" % key)
        for field, attr in (("identifier", "identifier"), ("sender", "sender"), ("sent", "sent"), ("status", "status"),
                            ("msgType", "message_type"), ("scope", "scope")):
            check("!str.eq(%s.%s, %s)" % (key, attr, e_string(expected.get(field, ""))))
        check("%s.infos.len != %dusize" % (key, len(expected["infos"])))
        for i, info in enumerate(expected["infos"]):
            for field, attr in (("language", "language"), ("category", "category"), ("event", "event"), ("urgency", "urgency"),
                                ("severity", "severity"), ("certainty", "certainty"), ("effective", "effective"),
                                ("onset", "onset"), ("expires", "expires"), ("senderName", "sender_name"),
                                ("headline", "headline"), ("description", "description"), ("instruction", "instruction"),
                                ("web", "web"), ("area_description", "area_description")):
                if field in info or True:
                    check("!str.eq(%s.infos[%d].%s, %s)" % (key, i, attr, e_string(info.get(field, ""))))
            check("%s.infos[%d].areas != %dusize" % (key, i, info["areas"]))
    out.append("    let (nc, nce) = cap.parse(a, %s)\n" % e_string(NOT_CAP))
    check("nce != cap.NotCap")
    out.append("    let (br, bre) = cap.parse(a, %s)\n" % e_string(BROKEN))
    check("bre == ok")
    out.append("    ret ok\n}\n")
    target = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/fmt_cap/src/main.e"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote", target, "checks", n)


main()
