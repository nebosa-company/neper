# -*- coding: utf-8 -*-
"""UI resource and command consistency audit over declared manifests (T035).

Usage:  python scripts/ui_audit.py MANIFEST.json [MANIFEST.json ...]

A manifest is the JSON an application or a generator emits from its actual
registries; this tool never searches source text for dynamic references, so a
reference it was not told about is not proven. Members (all optional):

  resources   [name]                       declared icon / image resource names
  references  [{resource, at}]             uses; `at` is "file:line" for the report
  locales     {locale: {key: text}}        message catalogues; the first (or `base`) is the source
  base        locale name                  which catalogue the others are checked against
  commands    [{id, label?, callback?, menu?, mnemonic?, at?}]
  callbacks   [name]                       the callbacks the host provides

Checks, each finding `at: [code] message` and the exit status 1 when any fires:
  unknown-resource      a reference names no declared resource
  duplicate-key         a key repeated within one catalogue (JSON object keys)
  missing-translation   a key of the base catalogue absent from a locale
  extra-translation     a locale key the base catalogue does not have
  placeholder-mismatch  the `{name}` / `%s` / `%d` placeholders of a text differ from the base's
  duplicate-command     two commands share an id
  missing-callback      a command's callback is not provided
  mnemonic-missing      a mnemonic letter is not in the command's label
  mnemonic-conflict     two commands of one menu take the same mnemonic (case-insensitive)
"""
import json
import re
import sys

PLACEHOLDER = re.compile(r"\{[A-Za-z_][A-Za-z0-9_]*\}|%[sdif]|%\d+\$[sdif]")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def catalogue_duplicates(path):
    """Duplicated keys inside each locale object, by locale, read from the raw JSON."""
    out = {}
    with open(path, encoding="utf-8") as f:
        raw = json.loads(f.read(), object_pairs_hook=lambda items: items)
    locales = dict(raw).get("locales") if isinstance(raw, list) else None
    if not isinstance(locales, list):
        return out
    for locale, entries in locales:
        if not isinstance(entries, list):
            continue
        seen, dup = set(), []
        for key, _value in entries:
            if key in seen:
                dup.append(key)
            seen.add(key)
        if dup:
            out[locale] = dup
    return out


def audit(path):
    findings = []
    data = load(path)
    resources = set(data.get("resources", []))
    for ref in data.get("references", []):
        if ref.get("resource") not in resources:
            findings.append((ref.get("at", path), "unknown-resource", "no resource named %r" % ref.get("resource")))
    for locale, keys in sorted(catalogue_duplicates(path).items()):
        for key in keys:
            findings.append((path, "duplicate-key", "%s repeats key %r" % (locale, key)))
    locales = data.get("locales", {})
    if locales:
        base = data.get("base") or next(iter(locales))
        source = locales.get(base, {})
        for locale, entries in locales.items():
            if locale == base:
                continue
            for key, text in source.items():
                if key not in entries:
                    findings.append((path, "missing-translation", "%s lacks key %r" % (locale, key)))
                elif sorted(PLACEHOLDER.findall(str(text))) != sorted(PLACEHOLDER.findall(str(entries[key]))):
                    findings.append((path, "placeholder-mismatch", "%s key %r: %s vs %s" % (
                        locale, key, sorted(PLACEHOLDER.findall(str(entries[key]))), sorted(PLACEHOLDER.findall(str(text))))))
            for key in entries:
                if key not in source:
                    findings.append((path, "extra-translation", "%s has key %r the base %s lacks" % (locale, key, base)))
    callbacks = set(data.get("callbacks", []))
    ids, mnemonics = {}, {}
    for command in data.get("commands", []):
        at = command.get("at", path)
        ident = command.get("id")
        if ident in ids:
            findings.append((at, "duplicate-command", "command %r is also declared at %s" % (ident, ids[ident])))
        ids.setdefault(ident, at)
        if "callbacks" in data and command.get("callback") not in callbacks:
            findings.append((at, "missing-callback", "command %r names callback %r, which the host does not provide" % (ident, command.get("callback"))))
        mnemonic = command.get("mnemonic")
        if mnemonic:
            label = command.get("label", "")
            if mnemonic.lower() not in label.lower():
                findings.append((at, "mnemonic-missing", "command %r mnemonic %r is not in its label %r" % (ident, mnemonic, label)))
            slot = (command.get("menu", ""), mnemonic.lower())
            if slot in mnemonics:
                findings.append((at, "mnemonic-conflict", "menu %r: commands %r and %r both take %r" % (slot[0], mnemonics[slot], ident, mnemonic)))
            mnemonics.setdefault(slot, ident)
    return findings


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    status = 0
    for path in argv:
        for at, code, message in audit(path):
            print("%s: [%s] %s" % (at, code, message))
            status = 1
    if status == 0:
        print("ui audit ok (%d manifest(s))" % len(argv))
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
