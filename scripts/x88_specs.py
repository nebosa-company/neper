"""The dialog bodies baked by gen_x88.py: capture, window size, rectangles (capture pixels: x includes the window's 8 px left border)."""
SPECS = {}

SPECS['custom'] = dict(cap='dialog-customization-rest', w=164, h=293, texts=[
    ('Bands', (14, 36, 50, 52)), ('Columns', (56, 36, 104, 52)),
    ('Artist', (16, 60, 100, 75)),
    ('Edition Name', (16, 79, 120, 95)), ('Flavor', (16, 98, 120, 114)), ('Legal', (16, 117, 120, 133)), ('No', (16, 136, 120, 152)),
    ('Power', (16, 155, 120, 171)), ('Row', (16, 174, 120, 190)), ('Toughness', (16, 193, 120, 209)),
])


def buttons(rects, color=(240, 240, 240)):
    """live buttons of a form (window coordinates x, y, w, h): their pixels are the face in the skin"""
    return [(x + 8 - 2, y - 2, x + 8 + w + 2, y + h + 2, color) for (x, y, w, h) in rects]


SPECS['adv'] = dict(cap='dialog-advanced-filter-rest', w=544, h=347,
                    erase=buttons([(308, 315, 75, 25), (389, 315, 75, 25), (470, 315, 75, 25), (96, 315, 75, 25), (15, 315, 75, 25)]),
                    texts=[('Filter', (16, 36, 45, 48), dict(face=7)), ('And', (57, 36, 77, 49), dict(face=7, underline=True, ink=(255, 0, 51))),
                           ('<root>', (84, 35, 122, 49), dict(face=7)), ('press the button to add a new condition', (15, 56, 213, 70), dict(face=7))])

SPECS['cond'] = dict(cap='dialog-conditional-formatting-rest', w=684, h=413,
                     erase=buttons([(415, 378, 85, 25), (506, 378, 85, 25), (597, 378, 85, 25)]),
                     pics=[(40, 88, 58, 102), (172, 88, 192, 105), (303, 88, 323, 105)],
                     texts=[('&Show formatting rules for:', (16, 42, 146, 60), dict(face=8)), ('All', (152, 46, 170, 58), dict(face=8)),
                            ('&New Rule...', (59, 89, 121, 103), dict(face=8)), ('&Edit Rule...', (192, 89, 251, 103), dict(face=8)), ('&Delete Rule', (323, 89, 383, 103), dict(face=8)),
                            ('Rule (applied in order shown)', (18, 119, 168, 134), dict(face=8)), ('Format', (277, 119, 330, 134), dict(face=8)), ('Applies to', (382, 119, 440, 134), dict(face=8)),
                            ('Apply to the record', (485, 119, 590, 134), dict(face=8)), ('Stop If True', (597, 119, 665, 134), dict(face=8))])

_tabs = [('&Colors', (37, 38, 70, 51)), ('&Rarity', (97, 36, 130, 52)), ('Card &Type', (156, 36, 210, 52)), ('&Editions', (236, 36, 277, 52)),
         ('&Mana Analyser', (303, 36, 378, 52)), ('Mana Product', (404, 36, 474, 52)), ('Power Analyser', (500, 36, 579, 52)), ('&Probability', (605, 36, 660, 52)),
         ('Mana &Slots', (685, 36, 741, 52)), ('Start &Hand', (766, 36, 823, 52)), ('Advanced', (849, 36, 901, 52))]
SPECS['stats'] = dict(cap='dialog-statistics-rest', w=941, h=501, erase=buttons([(865, 471, 75, 23)]),
                      pics=[(271, 112, 555, 396)],
                      texts=[(t, b, dict(face=8)) for (t, b) in _tabs] + [
                          ('Card breakdown by card colors.', (398, 68, 556, 84), dict(face=8)),
                          ('Green', (874, 114, 912, 131), dict(face=7, size=12)), ('Multicolor', (874, 132, 935, 149), dict(face=7, size=12)), ('Colorless', (874, 150, 935, 167), dict(face=7, size=12)),
                          ('Red', (874, 168, 915, 185), dict(face=7, size=12)), ('White', (874, 186, 915, 203), dict(face=7, size=12)),
                          ('Total: 12', (382, 416, 444, 432), dict(face=7, size=15))])


def _legality():
    return [('Deck Legality for', (28, 157, 128, 172), dict(size=13)), ('Standard', (129, 157, 191, 172), dict(weight=700, size=13)), ('format -', (191, 157, 243, 172), dict(size=13)),
            ('NOT LEGAL', (244, 157, 318, 172), dict(weight=700, ink=(128, 0, 0), size=13))]


_rules = ['Jet Collector', 'Euru, Acorn Scrounger', 'Dust to Dust', 'Chaos Warp', 'Chromatic Lantern', 'Fellwar Stone', 'Jeweled Amulet', 'Mind Stone', 'Swiftfoot Boots']
_first = ['deck. You', 'in', 'deck. You', 'deck. You have', 'deck.', 'deck. You', 'deck.', 'deck. You have', 'deck. You']
_second = ['have 1 copy of Jet Collector.', 'deck. You have 1 copy of Euru, Acorn Scrounger.', 'have 1 copy of Dust to Dust.', '1 copy of Chaos Warp.',
           'You have 1 copy of Chromatic Lantern.', 'have 1 copy of Fellwar Stone.', 'You have 1 copy of Jeweled Amulet.', '1 copy of Mind Stone.', 'have 1 copy of Swiftfoot Boots.']
_lines = []
for _i, _name in enumerate(_rules):
    _y = 185 + 26 * _i
    _lines.append(('Rule %d:' % (_i + 1), (28, _y - 1, 72, _y + 12), dict(size=13)))
    _lines.append(('Passed.', (72, _y - 1, 126, _y + 12), dict(weight=700, ink=(0, 128, 0), size=13)))
    _lines.append(('Not more than 4 copies of %s are allowed %s' % (_name, 'in ' + _first[_i] if _first[_i] != 'in' else 'in'), (126, _y - 1, 524, _y + 12), dict(size=13)))
    _lines.append((_second[_i], (28, _y + 12, 524, _y + 25), dict(size=13)))

SPECS['legality'] = dict(cap='dialog-deck-legality-rest', w=539, h=479,
                         erase=buttons([(22, 448, 75, 23), (460, 448, 75, 23)] + [(x, y, 75, 23) for x in (41, 122, 203, 284, 365, 446) for y in (66, 95)]) + [(33, 38, 549, 136, (240, 240, 240))],
                         texts=_legality() + _lines + [('Last update on October 10, 2026', (110, 448, 385, 470), dict(face=8))])

SPECS['about'] = dict(cap='dialog-about-rest', w=436, h=365, levels=6, block=2, erase=buttons([(360, 334, 75, 23)]),
                      pics=[(242, 55, 444, 325)],
                      texts=[('&MTG Studio', (16, 36, 74, 51), dict(face=8)), ('D&etails', (80, 36, 116, 51), dict(face=8)),
                             ('MTG Studio', (58, 66, 184, 90), dict(face=7, weight=700, size=22)), ('version 3.235.0', (66, 92, 172, 106), dict(face=7, weight=700, size=13)),
                             ('Send email to Support', (64, 273, 174, 288), dict(face=8, underline=True)), ('https://mtg.studio', (74, 296, 166, 311), dict(face=8, underline=True))])

_pn = ['Name', 'Author', 'e-mail', 'Created', 'Modified', 'Version', 'Description', 'File Name', 'File Type']
_py = [106, 125, 144, 163, 182, 202, 221, 239, 258]
_pv = ['New Deck', 'gaddl', '', '10/11/2026', '10/11/2026', '1.0', '', 'C:\\Users\\gaddl\\Desktop\\New...', 'MTG Studio (Xml)']
_pt = [('General', (33, 83, 92, 98)), ('Computed', (33, 277, 92, 292))]
for _i in range(9):
    _pt.append((_pn[_i], (44, _py[_i] - 3, 180, _py[_i] + 12), dict(ink=(255, 255, 255)) if _i == 0 else dict()))
    if _pv[_i]:
        _pt.append((_pv[_i], (183, _py[_i] - 3, 356, _py[_i] + 12), dict(face=7)))
_pt += [('Deck', (62, 297, 94, 311)), ('Sideboard', (120, 297, 175, 311)), ('12', (200, 297, 232, 311), dict(face=7)), ('0', (296, 297, 312, 311), dict(face=7)),
        ('Land', (61, 316, 90, 331)), ('Crea', (107, 316, 135, 331)), ('Spell', (152, 316, 180, 331)),
        ('2', (200, 316, 216, 331), dict(face=7)), ('8', (256, 316, 272, 331), dict(face=7)), ('2', (310, 316, 326, 331), dict(face=7)),
        ('Colors', (44, 334, 100, 349)), ('Archetype', (44, 355, 100, 370)), ('Unspecified', (181, 355, 270, 370), dict(face=7)),
        ('Very Aggressive', (220, 375, 302, 389), dict(face=7)), ('Strategy', (44, 379, 100, 393)), ('Legality', (44, 400, 100, 414))]
SPECS['props'] = dict(cap='dialog-deck-properties-rest', w=348, h=545, key=(240, 240, 240),
                      erase=buttons([(188, 514, 75, 23), (272, 514, 75, 23)]) + [(64, 34, 356, 54, (240, 240, 240)), (64, 55, 356, 72, (240, 240, 240))],
                      pics=[(16, 36, 52, 70), (43, 313, 61, 331, (255, 255, 255)), (89, 313, 107, 331, (255, 255, 255)), (135, 313, 153, 331, (255, 255, 255)),
                            (225, 331, 304, 353, (255, 255, 255)), (224, 399, 302, 417, (255, 255, 255)), (182, 386, 346, 398, (255, 255, 255))], texts=_pt)

_fn = ['Expansions', 'Core Sets', 'Masters', 'Draft Innovation', 'Duel Decks', 'Alchemy', 'Archenemy', 'Arsenal', 'Box', 'Commander', 'From the Vault', 'Funny', 'Masterpiece', 'Memorabilia',
       'Planechase', 'Premium Deck', 'Promo', 'Spellbook']
SPECS['filter'] = dict(cap='dialog-filter-rest', w=692, h=485,
                       erase=buttons([(28, 413, 75, 23), (109, 413, 75, 23), (195, 413, 75, 23)], (249, 249, 249)) + buttons([(23, 455, 75, 23), (104, 455, 75, 23), (451, 455, 75, 23), (532, 455, 75, 23), (616, 455, 75, 23)]),
                       texts=[('Blocks / Formats / Editions', (16, 36, 151, 51)), ('Cards', (151, 36, 189, 51)), ('Options', (192, 36, 240, 51)),
                              ('Blocks', (35, 65, 70, 82)), ('Formats', (123, 65, 168, 82)), ('Editions', (218, 65, 261, 82)),
                              ('Abbr.', (47, 91, 80, 105)), ('ES', (107, 91, 124, 105)), ('Block/Edition', (127, 91, 193, 105)), ('Released', (252, 91, 302, 105)),
                              ('Expansions', (355, 80, 440, 98), dict(weight=700, face=7, size=13))] +
                             [(_fn[_k], (126, 112 + 17 * _k - 3, 245, 112 + 17 * _k + 12), dict(face=7, ink=(255, 0, 0)) if _k == 0 else dict(face=7)) for _k in range(18)])
