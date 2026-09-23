# -*- coding: utf-8 -*-
"""Render the Neper UI v2 tokens (docs/ux/tokens.json) into lib/e/ui/style.e.

Usage:  python scripts/render_ux_theme.py [--check]   (from the repository root)

Writes the block between the two GENERATED markers in style.e: the colour roles'
value per palette and the fifteen type styles. The tokens are the source of truth
(D937); the block is never hand-edited. --check exits 1 when the block is stale.
"""
import json, re, sys
from pathlib import Path

TOKENS = Path('docs/ux/tokens.json')
STYLE = Path('lib/e/ui/style.e')
BEGIN = '// ---- GENERATED from docs/ux/tokens.json by scripts/render_ux_theme.py; do not edit ----'
END = '// ---- END GENERATED ----'
PALETTES = [('Light', 'light'), ('Dark', 'dark'), ('HighContrast', 'high-contrast'), ('HighContrastDark', 'high-contrast-dark')]
# The fourteen roles of D805 are kept as aliases of the v2 roles until every control
# is restyled; the v2 roles follow them, in tokens.json order.
ALIASES = [('Background', 'surface'), ('Surface', 'surface-container-lowest'), ('SurfaceVariant', 'surface-container-highest'),
           ('Primary', 'primary'), ('OnPrimary', 'on-primary'), ('Secondary', 'secondary'), ('OnSecondary', 'on-secondary'),
           ('Text', 'on-surface'), ('TextMuted', 'on-surface-variant'), ('Border', 'outline'), ('Focus', 'focus-ring'),
           ('Error', 'error'), ('OnError', 'on-error'), ('Selection', 'secondary-container')]
TEXT_ALIASES = [('Body', 'body-medium'), ('BodySmall', 'body-small'), ('Title', 'title-large'), ('Heading', 'headline-small'),
                ('Label', 'label-large'), ('Caption', 'label-small'), ('Code', 'code')]


def pascal(name):
    return ''.join(part.capitalize() for part in name.split('-'))


def num(v):
    s = ('%.4f' % v).rstrip('0')
    return s + '0' if s.endswith('.') else s


def rgba(value):
    h = value.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
    return 'paint.rgba(%s, %s, %s, %s)' % (num(r), num(g), num(b), num(a))


def resolve(tokens, name, theme, depth=0):
    value = tokens[name]
    if isinstance(value, dict):
        value = value.get(theme, value[PALETTES[0][1]])
    m = re.fullmatch(r'\{([A-Za-z0-9_.-]+)\}', value)
    if m:
        if depth > 16:
            raise SystemExit('alias chain too deep: ' + name)
        return resolve(tokens, m.group(1), theme, depth + 1)
    return value


def render():
    doc = json.loads(TOKENS.read_text(encoding='utf-8'))
    colors = {t['name']: t['value'] for t in doc['color']['tokens']}
    v2 = [t['name'] for t in doc['color']['tokens'] if t['name'] != 'brand-ink']
    # A v2 role whose name an alias already has is spelled by that alias: v2
    # `surface` (the window ground) is `.Background`, D805's `Surface` staying the
    # lowest container until the controls move off it.
    aliases = {a for a, _ in ALIASES}
    roles = [a for a, _ in ALIASES] + [pascal(n) for n in v2 if pascal(n) not in aliases]
    source = {a: v for a, v in ALIASES}
    for n in v2:
        if pascal(n) not in aliases:
            source[pascal(n)] = n
    styles = [s for g in doc['type']['groups'] for s in g['styles']]
    aliased = {a for a, _ in TEXT_ALIASES}
    text_roles = [a for a, _ in TEXT_ALIASES] + [pascal(s['name']) for s in styles if pascal(s['name']) not in aliased]
    text_source = dict(TEXT_ALIASES)
    for s in styles:
        text_source.setdefault(pascal(s['name']), s['name'])
    by_name = {s['name']: s for s in styles}
    out = [BEGIN, '',
           'type ColorRole = enum u8 { %s }' % ', '.join(roles),
           'type TextRole = enum u8 { %s }' % ', '.join(text_roles),
           'type ThemeTokens = struct { palette: Palette, profile: Profile, direction: Direction, colors: [%d]paint.Color, text: [%d]TextStyle, spacing: Spacing, radii: Radii, borders: Borders, elevation: [6]f32, states: States, sizes: Sizes, motion: Motion, durations: Durations, metrics: Metrics }' % (len(roles), len(text_roles)), '',
           '// A role\'s slot in `ThemeTokens.colors`.',
           'fn color_index(role: ColorRole) -> usize {']
    for i, r in enumerate(roles[1:], 1):
        out.append('    if role == .%s { ret %dusize }' % (r, i))
    out += ['    ret 0usize', '}', '',
            '// A text role\'s slot in `ThemeTokens.text`.',
            'fn text_index(role: TextRole) -> usize {']
    for i, r in enumerate(text_roles[1:], 1):
        out.append('    if role == .%s { ret %dusize }' % (r, i))
    out += ['    ret 0usize', '}', '',
            '// Every role\'s colour in one of the four palettes (Custom starts from Light).',
            'fn fill_palette(t: *ThemeTokens, palette: Palette) {']
    for enum, _ in PALETTES[1:]:
        out.append('    if palette == .%s {' % enum)
        out.append('        fill_%s(t)' % enum.lower())
        out.append('        ret')
        out.append('    }')
    out += ['    fill_%s(t)' % PALETTES[0][0].lower(), '}']
    # One function per palette keeps each under the per-function statement budget.
    for enum, theme in PALETTES:
        out += ['', 'fn fill_%s(t: *ThemeTokens) {' % enum.lower()]
        for i, r in enumerate(roles):
            out.append('    t.colors[%d] = %s' % (i, rgba(resolve(colors, source[r], theme))))
        out.append('}')
    out += ['',
            '// The fifteen type styles, the seven roles of D805 mapped onto them.',
            'fn fill_type_scale(t: *ThemeTokens) {']
    for i, r in enumerate(text_roles):
        st = by_name[text_source[r]]
        size = float(st['fontSize'].rstrip('px')); line = float(st['lineHeight'].rstrip('px'))
        out.append('    t.text[%d] = TextStyle { size: %s, line_height: %s, weight: %du16, italic: false }' % (i, repr(size), repr(line), int(st['fontWeight'])))
    out += ['}', '', END]
    return '\n'.join(out)


def main():
    text = STYLE.read_text(encoding='utf-8')
    if BEGIN not in text or END not in text:
        raise SystemExit('style.e has no GENERATED block')
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    new = head + render() + tail
    if '--check' in sys.argv:
        if new != text:
            print('lib/e/ui/style.e: the generated theme block is stale; run scripts/render_ux_theme.py')
            return 1
        return 0
    STYLE.write_text(new, encoding='utf-8', newline='\n')
    print('wrote the theme block of', STYLE)
    return 0


if __name__ == '__main__':
    sys.exit(main())
