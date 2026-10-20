#!/usr/bin/env python3
"""Render the normative neper documents into one PDF (docs/neper.pdf).

Repeatable build:

    scripts/build-docs-pdf.ps1     (Windows, PowerShell)
    scripts/build-docs-pdf.sh      (Linux, macOS)

Both wrappers create .venv-docs-pdf/, install the pinned dependencies from
scripts/docs-pdf-requirements.txt and run this script. To run it directly in an
environment that already has those dependencies:

    python scripts/build-docs-pdf.py [--out docs/neper.pdf] [--quiet]

The DOCUMENTS list below is the authority for what the PDF contains and in
which order. Markdown files are rendered as formatted text; every other file is
rendered as a verbatim listing. A directory entry expands to its files, sorted.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import reportlab
from markdown_it import MarkdownIt
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.utils import ImageReader
from reportlab.platypus import (BaseDocTemplate, Frame, HRFlowable, Image,
                                PageBreak, PageTemplate, Paragraph, Spacer,
                                Table, TableStyle, XPreformatted)
from reportlab.platypus.tableofcontents import TableOfContents

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = REPO_ROOT / "docs" / "neper.pdf"
LOGO_DIR = REPO_ROOT / "docs" / "gtm" / "logo"
LOGO = LOGO_DIR / "neper-lockup.png"
HEADER_MARK = LOGO_DIR / "neper-mark-small.png"   # the small cut, for 9 pt

# The order is the reading order: the language, then the toolchain and what it
# targets, then the library, then the UI, then how it is verified, then history.
# Each entry lists candidate paths; the first one that exists is used. An entry
# with a "kind" is generated from the repository instead of read from one file
# (see GENERATORS); its inputs are the files the generator read.
DOCUMENTS = [
    {"title": "Language specification", "paths": ["docs/spec.md"],
     "about": "Syntax, types, memory, errors, GPU profile; section 13 holds "
              "every compiler command and flag."},
    {"title": "Grammar", "paths": ["docs/grammar.ebnf", "grammar.ebnf"],
     "about": "The formal grammar."},
    {"title": "Diagnostic codes", "paths": ["docs/diagnostics.md"],
     "about": "The registry of stable diagnostic codes."},
    {"title": "Tooling protocol", "paths": ["docs/tooling.md"],
     "about": "Machine-readable output of every compiler command."},
    {"title": "Supported targets", "kind": "targets",
     "about": "Architectures, operating systems, GPU targets and CPU levels."},
    {"title": "GPU contracts", "paths": ["docs/m25-gpu-contracts.md"],
     "about": "How host and device work compose; frozen before the GPU profile."},
    {"title": "NeperOS", "kind": "neperos",
     "about": "The microkernel, its servers and apps, the e.os surface, the "
              "app kit and the open work."},
    {"title": "pacman package manager", "paths": ["docs/pacman.md"],
     "about": "Packages and the project layout."},
    {"title": "Module architecture", "paths": ["docs/modules.md"],
     "about": "How the standard library is layered and delivered."},
    {"title": "Standard-library hardening",
     "paths": ["docs/stdlib-hardening.md"],
     "about": "Composition rules and acceptance for the library."},
    {"title": "Module API catalogue", "paths": ["docs/module-apis.md"],
     "about": "The designed public surface of each e.* module."},
    {"title": "Library reference", "kind": "library",
     "about": "Every e.* and x.* module in lib/ with every function signature, "
              "read from source."},
    {"title": "Algorithm map", "paths": ["docs/algos.md"],
     "about": "Algorithms and the e.* functions that implement them."},
    {"title": "UI framework", "paths": ["docs/ui-framework.md"],
     "about": "The e.ui architecture."},
    {"title": "Design language",
     "files": ["docs/ux/README.md", "docs/ux/platforms.md",
               "docs/ux/accessibility-bridge.md", "docs/ui/looks-plan.md",
               "docs/ui/looks-howto.md", "docs/ux/tokens.json"],
     "about": "Tokens, platform rules, accessibility and the platform looks."},
    {"title": "Controls", "kind": "controls",
     "about": "Every UI control and its specification."},
    {"title": "Data grid", "paths": ["docs/grid.md"],
     "about": "Requirements and design proposal for the data grid."},
    {"title": "Charts", "kind": "charts",
     "about": "The chart gallery: every chart the engine renders."},
    {"title": "Diagnostic fixtures",
     "paths": ["tests/selfhost/fixtures/diagnostics"],
     "about": "Source of every compiler diagnostic."},
    {"title": "General-purpose verification",
     "paths": ["docs/general-purpose-verification.md"],
     "about": "How general-purpose behaviour is verified."},
    {"title": "Security",
     "files": ["docs/security-audit-2026-09-24.md", "docs/security-findings.md",
               "docs/ethical-hacking.md"],
     "about": "The security audit, its findings and the defensive-tooling plan."},
    {"title": "Roadmap", "paths": ["docs/roadmap.md"],
     "about": "Milestones and what is planned."},
]

PAGE_SIZE = A4
PAGE_W, PAGE_H = PAGE_SIZE
MARGIN_X = 18 * mm
MARGIN_TOP = 20 * mm
MARGIN_BOTTOM = 18 * mm
FRAME_W = PAGE_W - 2 * MARGIN_X

INK = colors.HexColor("#101418")
MUTED = colors.HexColor("#5a6470")
RULE = colors.HexColor("#b9c0c9")
ACCENT = colors.HexColor("#1a3f7a")
CODE_INK = colors.HexColor("#123a2c")
CODE_BG = colors.HexColor("#f4f5f7")
HEAD_BG = colors.HexColor("#e6eaf0")

BODY_SIZE = 9.2
CODE_SIZE = 7.6
CELL_SIZE = 7.8

# Applied only to characters the selected fonts cannot render.
SUBSTITUTIONS = {
    "\u2014": "--", "\u2013": "-", "\u2212": "-", "\u00a0": " ",
    "\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"',
    "\u2026": "...", "\u2192": "->", "\u2190": "<-", "\u2194": "<->",
    "\u21d2": "=>", "\u00a7": "S", "\u00d7": "x", "\u00b1": "+/-",
    "\u00b2": "^2", "\u00b3": "^3", "\u2264": "<=", "\u2265": ">=",
    "\u2022": "-", "\u00b7": "-", "\u2081": "1", "\u2318": "Cmd",
    "\u21e7": "Shift", "\u2303": "Ctrl", "\u2325": "Alt", "\u232b": "Bksp",
    "\u25b8": ">", "\u25c2": "<", "\u2082": "2", "\u2208": "in",
    "\u2217": "*", "\u2225": "||", "\u2227": "and", "\u226a": "<<",
    "\u226b": ">>", "\u2295": "(+)", "\u22c5": ".", "\u25b6": ">",
    "\u25c0": "<", "\u2605": "*", "\u2713": "ok",
}


def _vera(name):
    return str(Path(reportlab.__file__).resolve().parent / "fonts" / name)


SANS_FAMILIES = [
    ("C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/arialbd.ttf",
     "C:/Windows/Fonts/ariali.ttf", "C:/Windows/Fonts/arialbi.ttf"),
    ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
     "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
     "/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf",
     "/usr/share/fonts/truetype/dejavu/DejaVuSans-BoldOblique.ttf"),
    ("/usr/share/fonts/dejavu/DejaVuSans.ttf",
     "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
     "/usr/share/fonts/dejavu/DejaVuSans-Oblique.ttf",
     "/usr/share/fonts/dejavu/DejaVuSans-BoldOblique.ttf"),
    ("/System/Library/Fonts/Supplemental/Arial.ttf",
     "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
     "/System/Library/Fonts/Supplemental/Arial Italic.ttf",
     "/System/Library/Fonts/Supplemental/Arial Bold Italic.ttf"),
    (_vera("Vera.ttf"), _vera("VeraBd.ttf"), _vera("VeraIt.ttf"),
     _vera("VeraBI.ttf")),
]

MONO_FAMILIES = [
    ("C:/Windows/Fonts/consola.ttf", "C:/Windows/Fonts/consolab.ttf",
     "C:/Windows/Fonts/consolai.ttf", "C:/Windows/Fonts/consolaz.ttf"),
    ("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
     "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
     "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Oblique.ttf",
     "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-BoldOblique.ttf"),
    ("/usr/share/fonts/dejavu/DejaVuSansMono.ttf",
     "/usr/share/fonts/dejavu/DejaVuSansMono-Bold.ttf",
     "/usr/share/fonts/dejavu/DejaVuSansMono-Oblique.ttf",
     "/usr/share/fonts/dejavu/DejaVuSansMono-BoldOblique.ttf"),
    ("C:/Windows/Fonts/cour.ttf", "C:/Windows/Fonts/courbd.ttf",
     "C:/Windows/Fonts/couri.ttf", "C:/Windows/Fonts/courbi.ttf"),
    ("/System/Library/Fonts/Supplemental/Courier New.ttf",
     "/System/Library/Fonts/Supplemental/Courier New Bold.ttf",
     "/System/Library/Fonts/Supplemental/Courier New Italic.ttf",
     "/System/Library/Fonts/Supplemental/Courier New Bold Italic.ttf"),
]

FACE_KEYS = ("regular", "bold", "italic", "bolditalic")


def _register_family(alias, candidates):
    """Register the first fully present TTF family; return (faces, coverage)."""
    for paths in candidates:
        if not all(Path(p).exists() for p in paths):
            continue
        faces = {
            "regular": alias,
            "bold": alias + "-Bold",
            "italic": alias + "-Italic",
            "bolditalic": alias + "-BoldItalic",
        }
        coverage = set()
        for key, path in zip(FACE_KEYS, paths):
            font = TTFont(faces[key], path)
            pdfmetrics.registerFont(font)
            if key == "regular":
                coverage = set(font.face.charToGlyph.keys())
        pdfmetrics.registerFontFamily(alias, faces["regular"], faces["bold"],
                                      faces["italic"], faces["bolditalic"])
        return faces, coverage
    return None, None


def setup_fonts():
    sans, sans_cov = _register_family("NeperSans", SANS_FAMILIES)
    if sans is None:
        sans = {"regular": "Helvetica", "bold": "Helvetica-Bold",
                "italic": "Helvetica-Oblique",
                "bolditalic": "Helvetica-BoldOblique"}
        sans_cov = set(range(256))
    mono, mono_cov = _register_family("NeperMono", MONO_FAMILIES)
    if mono is None:
        mono = {"regular": "Courier", "bold": "Courier-Bold",
                "italic": "Courier-Oblique",
                "bolditalic": "Courier-BoldOblique"}
        mono_cov = set(range(256))
    return sans, mono, sans_cov & mono_cov


class Text:
    """Escapes and font-substitutes source text for the chosen fonts."""

    def __init__(self, supported):
        self.supported = supported
        self.unmapped = set()

    def sanitize(self, text):
        out = []
        for ch in text:
            code = ord(ch)
            if code < 128 or code in self.supported:
                out.append(ch)
                continue
            replacement = SUBSTITUTIONS.get(ch)
            if replacement is None:
                self.unmapped.add(ch)
                replacement = "[U+%04X]" % code
            out.append(replacement)
        return "".join(out)

    def bullet(self, preferred, fallback):
        return preferred if ord(preferred) in self.supported else fallback


def esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def esc_attr(text):
    return esc(text).replace('"', "&quot;")


def build_styles(sans, mono):
    def style(name, **kw):
        kw.setdefault("fontName", sans["regular"])
        kw.setdefault("fontSize", BODY_SIZE)
        kw.setdefault("leading", kw["fontSize"] * 1.42)
        kw.setdefault("textColor", INK)
        return ParagraphStyle(name, **kw)

    return {
        "cover_title": style("cover_title", fontName=sans["bold"], fontSize=44,
                             leading=50, textColor=ACCENT, spaceAfter=8),
        "cover_sub": style("cover_sub", fontSize=13, leading=19,
                           textColor=MUTED, spaceAfter=20),
        "cover_meta": style("cover_meta", fontName=mono["regular"],
                            fontSize=8.2, leading=13, textColor=MUTED),
        "part": style("part", fontName=sans["bold"], fontSize=21, leading=25,
                      textColor=ACCENT, spaceAfter=2),
        "part_meta": style("part_meta", fontName=mono["regular"], fontSize=7.4,
                           leading=11, textColor=MUTED, spaceAfter=14),
        "h1": style("h1", fontName=sans["bold"], fontSize=15.5, leading=19,
                    textColor=ACCENT, spaceBefore=16, spaceAfter=6),
        "h2": style("h2", fontName=sans["bold"], fontSize=12.4, leading=16,
                    spaceBefore=13, spaceAfter=5),
        "h3": style("h3", fontName=sans["bold"], fontSize=10.4, leading=14,
                    spaceBefore=10, spaceAfter=4),
        "h4": style("h4", fontName=sans["bolditalic"], fontSize=9.6,
                    leading=13, spaceBefore=9, spaceAfter=3),
        "body": style("body", spaceAfter=6),
        "tight": style("tight", spaceAfter=2),
        "mod_meta": style("mod_meta", fontName=mono["regular"], fontSize=7.2,
                          leading=10, textColor=MUTED, spaceAfter=3),
        "mod_desc": style("mod_desc", fontName=sans["italic"], fontSize=8.4,
                          leading=11.5, spaceAfter=7),
        "thumb": style("thumb", fontSize=7, leading=9, spaceAfter=0),
        "code": ParagraphStyle("code", fontName=mono["regular"],
                               fontSize=CODE_SIZE, leading=CODE_SIZE * 1.34,
                               textColor=CODE_INK, backColor=CODE_BG,
                               borderPadding=(5, 6, 5, 6), spaceBefore=3,
                               spaceAfter=9),
        "cell": ParagraphStyle("cell", fontName=sans["regular"],
                               fontSize=CELL_SIZE, leading=CELL_SIZE * 1.32,
                               textColor=INK),
        "cell_head": ParagraphStyle("cell_head", fontName=sans["bold"],
                                    fontSize=CELL_SIZE,
                                    leading=CELL_SIZE * 1.32, textColor=INK),
        "toc0": ParagraphStyle("toc0", fontName=sans["bold"], fontSize=9.6,
                               leading=15, spaceBefore=8, textColor=ACCENT),
        "toc1": ParagraphStyle("toc1", fontName=sans["regular"], fontSize=8.8,
                               leading=12.5, leftIndent=12, textColor=INK),
        "toc2": ParagraphStyle("toc2", fontName=sans["regular"], fontSize=8.4,
                               leading=11.5, leftIndent=26, textColor=INK),
        "toc3": ParagraphStyle("toc3", fontName=sans["regular"], fontSize=8.0,
                               leading=11, leftIndent=42, textColor=MUTED),
        "toc4": ParagraphStyle("toc4", fontName=sans["regular"], fontSize=8.0,
                               leading=11, leftIndent=56, textColor=MUTED),
    }


class Renderer:
    """Turns markdown-it tokens and verbatim files into platypus flowables."""

    def __init__(self, styles, sans, mono, text_tool, doc_anchors):
        self.styles = styles
        self.sans = sans
        self.mono = mono
        self.text = text_tool
        self.doc_anchors = doc_anchors
        self.bullets = [text_tool.bullet("\u2022", "-"), "-",
                        text_tool.bullet("\u00b7", "*")]
        self._keys = 0
        self._indent_cache = {}
        self._link_stack = []

    def new_key(self, prefix):
        self._keys += 1
        return "%s%d" % (prefix, self._keys)

    def indented(self, base, indent):
        if indent <= 0:
            return base
        cache_key = (base.name, indent)
        style = self._indent_cache.get(cache_key)
        if style is None:
            style = ParagraphStyle("%s_i%d" % (base.name, int(indent)),
                                   parent=base)
            style.leftIndent = base.leftIndent + indent
            style.bulletIndent = base.bulletIndent + max(0.0, indent - 12)
            style.bulletFontName = self.sans["regular"]
            style.bulletFontSize = base.fontSize
            self._indent_cache[cache_key] = style
        return style

    def resolve_link(self, href):
        if href.startswith(("http://", "https://", "mailto:")):
            return href
        target = href.split("#", 1)[0]
        if not target:
            return None
        key = self.doc_anchors.get(target.rsplit("/", 1)[-1])
        return "#" + key if key else None

    def heading_flowable(self, markup, plain, level, style_name):
        para = Paragraph(markup, self.styles[style_name])
        para._toc_level = level
        para._toc_text = plain
        para._toc_key = self.new_key("h")
        return para

    def inline(self, token):
        out, plain = [], []
        for tok in (token.children or []):
            kind = tok.type
            if kind == "text":
                out.append(esc(tok.content))
                plain.append(tok.content)
            elif kind == "code_inline":
                out.append('<font face="%s" size="%.1f" color="#123a2c">%s</font>'
                           % (self.mono["regular"], CODE_SIZE + 0.5,
                              esc(tok.content)))
                plain.append(tok.content)
            elif kind == "strong_open":
                out.append("<b>")
            elif kind == "strong_close":
                out.append("</b>")
            elif kind == "em_open":
                out.append("<i>")
            elif kind == "em_close":
                out.append("</i>")
            elif kind == "s_open":
                out.append("<strike>")
            elif kind == "s_close":
                out.append("</strike>")
            elif kind == "link_open":
                dest = self.resolve_link(tok.attrGet("href") or "")
                if dest:
                    out.append('<link href="%s" color="#1a4fa0">'
                               % esc_attr(dest))
                else:
                    out.append('<font color="#1a4fa0">')
                self._link_stack.append(bool(dest))
            elif kind == "link_close":
                closed = self._link_stack.pop() if self._link_stack else False
                out.append("</link>" if closed else "</font>")
            elif kind == "softbreak":
                out.append(" ")
                plain.append(" ")
            elif kind == "hardbreak":
                out.append("<br/>")
                plain.append(" ")
            elif kind in ("html_inline", "image"):
                out.append(esc(tok.content))
                plain.append(tok.content)
        return "".join(out), " ".join("".join(plain).split())

    def blocks(self, toks, i, stop, indent=0.0):
        out = []
        while i < len(toks):
            tok = toks[i]
            if stop is not None and tok.type == stop:
                return out, i
            kind = tok.type
            if kind == "heading_open":
                level = int(tok.tag[1:])
                markup, plain = self.inline(toks[i + 1])
                out.append(self.heading_flowable(markup, plain, level,
                                                 "h%d" % min(level, 4)))
                i += 3
            elif kind == "paragraph_open":
                markup, _ = self.inline(toks[i + 1])
                base = self.styles["tight"] if tok.hidden else self.styles["body"]
                out.append(Paragraph(markup, self.indented(base, indent)))
                i += 3
            elif kind in ("fence", "code_block"):
                out.extend(self.code_block(tok.content, indent))
                i += 1
            elif kind == "hr":
                out.append(Spacer(1, 4))
                out.append(HRFlowable(width="100%", thickness=0.5, color=RULE))
                out.append(Spacer(1, 6))
                i += 1
            elif kind in ("bullet_list_open", "ordered_list_open"):
                items, i = self.list_block(toks, i, indent)
                out.extend(items)
            elif kind == "blockquote_open":
                inner, i = self.blocks(toks, i + 1, "blockquote_close",
                                       indent + 14)
                out.append(Spacer(1, 2))
                out.extend(inner)
                out.append(Spacer(1, 4))
                i += 1
            elif kind == "table_open":
                table, i = self.table_block(toks, i, indent)
                out.extend(table)
            else:
                i += 1
        return out, i

    def list_block(self, toks, i, indent):
        opener = toks[i]
        ordered = opener.type == "ordered_list_open"
        close = "ordered_list_close" if ordered else "bullet_list_close"
        number = int(opener.attrGet("start") or 1) if ordered else 1
        depth = int(indent // 14)
        marker_char = self.bullets[min(depth, len(self.bullets) - 1)]
        i += 1
        out = []
        while i < len(toks) and toks[i].type != close:
            if toks[i].type != "list_item_open":
                i += 1
                continue
            inner, i = self.blocks(toks, i + 1, "list_item_close", indent + 14)
            i += 1
            marker = ("%d." % number) if ordered else marker_char
            number += 1
            for flow in inner:
                if isinstance(flow, Paragraph):
                    flow.bulletText = marker
                    break
            out.extend(inner)
        out.append(Spacer(1, 4))
        return out, i + 1

    def table_block(self, toks, i, indent):
        rows, plains, header_rows = [], [], 0
        i += 1
        while i < len(toks) and toks[i].type != "table_close":
            tok = toks[i]
            if tok.type == "thead_open":
                header_rows = 1
                i += 1
                continue
            if tok.type != "tr_open":
                i += 1
                continue
            cells, plain_cells = [], []
            i += 1
            while i < len(toks) and toks[i].type != "tr_close":
                if toks[i].type in ("th_open", "td_open"):
                    if i + 1 < len(toks) and toks[i + 1].type == "inline":
                        markup, plain = self.inline(toks[i + 1])
                        i += 3
                    else:
                        markup, plain = "", ""
                        i += 2
                    cells.append(markup)
                    plain_cells.append(plain)
                else:
                    i += 1
            rows.append(cells)
            plains.append(plain_cells)
            i += 1
        i += 1
        if not rows:
            return [], i
        return self.build_table(rows, plains, header_rows, indent), i

    def build_table(self, rows, plains, header_rows, indent):
        ncols = max(len(r) for r in rows)
        pad = 4.0
        usable = FRAME_W - indent - ncols * 2 * pad
        natural = [1.0] * ncols
        for row_index, plain_row in enumerate(plains):
            style = (self.styles["cell_head"] if row_index < header_rows
                     else self.styles["cell"])
            for col in range(ncols):
                text = plain_row[col] if col < len(plain_row) else ""
                width = pdfmetrics.stringWidth(text, style.fontName,
                                               style.fontSize)
                natural[col] = max(natural[col], min(width, usable * 0.55))
        total = sum(natural)
        widths = [max(28.0, usable * n / total) for n in natural]
        scale = usable / sum(widths)
        widths = [w * scale + 2 * pad for w in widths]

        data = []
        for row_index, row in enumerate(rows):
            style = (self.styles["cell_head"] if row_index < header_rows
                     else self.styles["cell"])
            data.append([Paragraph(row[c] if c < len(row) else "", style)
                         for c in range(ncols)])
        table = Table(data, colWidths=widths, repeatRows=header_rows,
                      hAlign="LEFT")
        commands = [
            ("GRID", (0, 0), (-1, -1), 0.3, RULE),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), pad),
            ("RIGHTPADDING", (0, 0), (-1, -1), pad),
            ("TOPPADDING", (0, 0), (-1, -1), 2.5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
        ]
        if header_rows:
            commands.append(("BACKGROUND", (0, 0), (-1, header_rows - 1),
                             HEAD_BG))
        table.setStyle(TableStyle(commands))
        return [Spacer(1, 3), table, Spacer(1, 9)]

    def code_block(self, text, indent=0.0):
        style = self.indented(self.styles["code"], indent)
        avail = FRAME_W - indent - 16
        char_w = pdfmetrics.stringWidth("0", style.fontName, style.fontSize)
        limit = max(24, int(avail / (char_w or 4.0)))
        lines = []
        for raw in text.rstrip("\n").split("\n"):
            raw = raw.replace("\t", "    ")
            while len(raw) > limit:
                lines.append(raw[:limit])
                raw = raw[limit:]
            lines.append(raw)
        return [XPreformatted(esc("\n".join(lines)), style)]


class NeperDoc(BaseDocTemplate):
    """Adds PDF outline entries, TOC notifications and a running header."""

    def __init__(self, filename, **kw):
        BaseDocTemplate.__init__(self, filename, **kw)
        self.current_title = ""
        self._outline_prev = -1

    def beforeDocument(self):
        self.current_title = ""
        self._outline_prev = -1

    def afterFlowable(self, flowable):
        key = getattr(flowable, "_toc_key", None)
        if key is None:
            return
        title = flowable._toc_text or ""
        if flowable._toc_level == 0:
            self.current_title = title
        if getattr(flowable, "_toc_drop", False):
            return
        level = getattr(flowable, "_toc_display", flowable._toc_level)
        self.canv.bookmarkPage(key)
        outline_level = min(level, self._outline_prev + 1)
        self._outline_prev = outline_level
        self.canv.addOutlineEntry(title[:120], key, level=outline_level,
                                  closed=outline_level >= 1)
        self.notify("TOCEntry", (level, title, self.page, key))


def collapse_single_child_levels(story, report=None):
    """Remove headings that are the only child of their parent.

    A lone child adds a bookmark level without adding a choice: the document
    part "Language specification" and its single "The neper language --
    specification" heading name the same place. The lone child is dropped and
    its own children are promoted, repeatedly, so a level exists only where
    there is more than one entry to pick from. Document parts are never
    dropped; the running header is derived from them.
    """
    root = {"level": -1, "flow": None, "children": []}
    stack = [root]
    for flow in story:
        if getattr(flow, "_toc_key", None) is None:
            continue
        level = flow._toc_level
        while len(stack) > 1 and stack[-1]["level"] >= level:
            stack.pop()
        node = {"level": level, "flow": flow, "children": []}
        stack[-1]["children"].append(node)
        stack.append(node)

    def collapse(node):
        while len(node["children"]) == 1:
            only = node["children"][0]
            only["flow"]._toc_drop = True
            if report is not None:
                report.append(only["flow"]._toc_text or "")
            node["children"] = only["children"]
        for child in node["children"]:
            collapse(child)

    def assign(node, depth):
        for child in node["children"]:
            child["flow"]._toc_display = depth
            assign(child, depth + 1)

    for part in root["children"]:
        collapse(part)
    assign(root, 0)


def make_decorator(sans):
    # One ImageReader, so the mark is embedded once and reused on every page.
    mark = ImageReader(str(HEADER_MARK)) if HEADER_MARK.exists() else None
    mark_size = 9.0

    def decorate(canvas, doc):
        if doc.page == 1:
            return
        canvas.saveState()
        canvas.setFont(sans["regular"], 7.4)
        canvas.setFillColor(MUTED)
        top = PAGE_H - MARGIN_TOP + 9
        text_x = MARGIN_X
        if mark is not None:
            canvas.drawImage(mark, MARGIN_X, top - 1.6, width=mark_size,
                             height=mark_size, mask="auto")
            text_x += mark_size + 4.5
        canvas.drawString(text_x, top, "neper documentation")
        title = (doc.current_title or "")[:70]
        canvas.drawRightString(PAGE_W - MARGIN_X, top, title)
        canvas.setStrokeColor(RULE)
        canvas.setLineWidth(0.4)
        canvas.line(MARGIN_X, top - 3.5, PAGE_W - MARGIN_X, top - 3.5)
        canvas.drawCentredString(PAGE_W / 2.0, MARGIN_BOTTOM - 12,
                                 str(doc.page))
        canvas.restoreState()
    return decorate


def git_description():
    def run(args):
        try:
            out = subprocess.run(args, cwd=str(REPO_ROOT), check=True,
                                 capture_output=True, text=True)
        except (OSError, subprocess.CalledProcessError):
            return None
        return out.stdout.strip()

    commit = run(["git", "rev-parse", "--short", "HEAD"])
    if commit is None:
        return "unknown revision"
    status = run(["git", "status", "--porcelain"])
    dirty = " + uncommitted changes" if status else ""
    return "commit %s%s" % (commit, dirty)


# ---- generated sections ----------------------------------------------------
# Each generator reads the repository, so the section cannot drift from it. A
# generator has "inputs" (the files it reads, counted on the cover) and
# "build" (the flowables, after the part heading).

def read_repo(rel):
    return (REPO_ROOT / rel).read_text(encoding="utf-8", errors="replace")


def rel_posix(path):
    return path.relative_to(REPO_ROOT).as_posix()


def leading_comment(text, limit=260):
    """The `//` block that opens a source file, as one line."""
    lines = []
    for line in text.replace("\r\n", "\n").split("\n"):
        if line.startswith("//"):
            lines.append(line[2:].strip())
        elif lines or line.strip():
            break
    words = " ".join(" ".join(lines).split())
    if len(words) > limit:
        words = words[:limit].rsplit(" ", 1)[0] + "..."
    return words


def first_sentence(markdown):
    for para in re.split(r"\n\s*\n", markdown):
        para = para.strip()
        if not para or para.startswith("#"):
            continue
        para = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", para)
        para = " ".join(re.sub(r"[`*_]", "", para).split())
        found = re.match(r"(.+?[.!?])(\s|$)", para)
        return found.group(1) if found else para
    return ""


def render_markdown(markdown, renderer, md, text_tool):
    tokens = md.parse(text_tool.sanitize(markdown))
    flows, _ = renderer.blocks(tokens, 0, None)
    return flows


def section_between(text, start, end):
    first = text.find(start)
    last = text.find(end, first + 1) if first >= 0 else -1
    if first < 0 or last < 0:
        raise SystemExit("error: cannot find %r .. %r" % (start, end))
    return text[first:last]


def table_flows(renderer, header, rows):
    return renderer.build_table(
        [[esc(c) for c in header]] + [[esc(c) for c in r] for r in rows],
        [list(header)] + [list(r) for r in rows], 1, 0.0)


# -- library --

LIB_ROOTS = ("lib/e", "lib/x")
FN_LINE = re.compile(r"^(?:extern\s+)?fn\s")


def library_inputs():
    files = []
    for root in LIB_ROOTS:
        files.extend((REPO_ROOT / root).rglob("*.e"))
    return sorted(files, key=lambda p: rel_posix(p))


def library_module(path):
    return rel_posix(path)[len("lib/"):-2].replace("/", ".")


def library_group(name):
    parts = name.split(".")
    return ".".join(parts[:2]) if len(parts) > 2 else parts[0]


def cut_signature(sig):
    start = sig.find("(")
    if start < 0:
        return " ".join(sig.split())
    depth, end = 0, start
    for at in range(start, len(sig)):
        if sig[at] == "(":
            depth += 1
        elif sig[at] == ")":
            depth -= 1
            if depth == 0:
                end = at
                break
    tail = re.split(r"\s*\{", sig[end + 1:], 1)[0].split("//")[0].rstrip()
    return " ".join((sig[:end + 1] + tail).split())


def library_declarations(text):
    lines = text.replace("\r\n", "\n").split("\n")
    functions, types, errors, constants = [], [], 0, 0
    at = 0
    while at < len(lines):
        line = lines[at]
        if FN_LINE.match(line):
            sig = line
            depth = sig.count("(") - sig.count(")")
            while depth > 0 and at + 1 < len(lines):
                at += 1
                sig += " " + lines[at].strip()
                depth += lines[at].count("(") - lines[at].count(")")
            functions.append(cut_signature(sig))
        elif line.startswith("type "):
            types.append(" ".join(re.split(r"\s*\{", line, 1)[0]
                                  .split("//")[0].split()))
        elif line.startswith("error "):
            errors += 1
        elif line.startswith("const "):
            constants += 1
        at += 1
    return functions, types, errors, constants


def build_library(entry, renderer, styles, md, text_tool):
    modules = []
    for path in entry["inputs"]:
        name = library_module(path)
        text = path.read_text(encoding="utf-8", errors="replace")
        modules.append((library_group(name), name, path, text,
                        library_declarations(text)))
    modules.sort(key=lambda m: (m[0], m[1]))
    total_fn = sum(len(m[4][0]) for m in modules)
    total_ty = sum(len(m[4][1]) for m in modules)
    flows = [Paragraph(esc(text_tool.sanitize(
        "%d modules, %d functions, %d types, read from the source files in "
        "lib/e and lib/x. Each module lists every top-level function and type "
        "exactly as written, whether or not docs/modules.json fences it as "
        "public; a per-target variant (os.linux, os.windows, ...) is its own "
        "entry. The designed surface is in the Module API catalogue."
        % (len(modules), total_fn, total_ty))), styles["body"])]
    group = None
    for grp, name, path, text, decls in modules:
        functions, types, errors, constants = decls
        if grp != group:
            group = grp
            title = grp + " (top level)" if "." not in grp else grp
            flows.append(renderer.heading_flowable(esc(title), title, 1, "h1"))
        flows.append(renderer.heading_flowable(esc(name), name, 2, "h2"))
        meta = "%s | %d functions | %d types | %d errors | %d constants" % (
            rel_posix(path), len(functions), len(types), errors, constants)
        flows.append(Paragraph(esc(text_tool.sanitize(meta)),
                               styles["mod_meta"]))
        desc = leading_comment(text)
        if desc:
            flows.append(Paragraph(esc(text_tool.sanitize(desc)),
                                   styles["mod_desc"]))
        listing = types + functions
        if listing:
            flows.extend(renderer.code_block(
                text_tool.sanitize("\n".join(listing))))
        else:
            flows.append(Spacer(1, 4))
    return flows


# -- controls --

COMPONENTS = "docs/ux/components"


def control_names():
    root = REPO_ROOT / COMPONENTS
    return sorted((d.name for d in root.iterdir() if d.is_dir()),
                  key=str.lower)


def control_readme(name):
    return REPO_ROOT / COMPONENTS / name / "README.md"


def controls_inputs():
    return [control_readme(n) for n in control_names()
            if control_readme(n).exists()]


def build_controls(entry, renderer, styles, md, text_tool):
    names = control_names()
    readmes = {n: control_readme(n).read_text(encoding="utf-8", errors="replace")
               for n in names if control_readme(n).exists()}
    rows = [[str(i + 1), n, first_sentence(readmes[n]) if n in readmes
             else "No written specification yet."]
            for i, n in enumerate(names)]
    rows = [[text_tool.sanitize(c) for c in r] for r in rows]
    flows = [renderer.heading_flowable("Index", "Index", 1, "h1"),
             Paragraph(esc("%d controls, the browser control included. The "
                           "specifications follow in the same order."
                           % len(names)), styles["body"])]
    flows.extend(table_flows(renderer, ["#", "Control", "What it is"], rows))
    for n in names:
        if n in readmes:
            flows.extend(render_markdown(readmes[n], renderer, md, text_tool))
    return flows


# -- charts --

CHARTS_DOC = "docs/charts.md"
CHART_DIR = "docs/chart-previews"
THUMB_PX = 240
THUMB_COLUMNS = 4


def chart_list():
    rows = re.findall(
        r"^\| (.+?) \| !\[[^\]]*\]\(chart-previews/([A-Za-z0-9_]+)\.png\)",
        read_repo(CHARTS_DOC), re.M)
    return [(name, REPO_ROOT / CHART_DIR / (slug + ".png")) for name, slug in rows]


def charts_inputs():
    return [REPO_ROOT / CHARTS_DOC] + [p for _, p in chart_list()]


def thumbnail(path):
    from PIL import Image as PilImage
    with PilImage.open(path) as image:
        if "A" in image.getbands():
            flat = PilImage.new("RGB", image.size, "white")
            flat.paste(image, mask=image.getchannel("A"))
            image = flat
        image = image.convert("RGB")
        image.thumbnail((THUMB_PX, THUMB_PX))
        buf = io.BytesIO()
        image.save(buf, "JPEG", quality=72)
        buf.seek(0)
        return buf, image.size


def build_charts(entry, renderer, styles, md, text_tool):
    charts = chart_list()
    cell_w = FRAME_W / THUMB_COLUMNS - 8
    cells = []
    for number, (name, path) in enumerate(charts, 1):
        label = Paragraph(esc(text_tool.sanitize("%d. %s" % (number, name))),
                          styles["thumb"])
        if path.exists():
            buf, (w, h) = thumbnail(path)
            cells.append([Image(buf, width=cell_w, height=cell_w * h / w), label])
        else:
            cells.append([label])
    while len(cells) % THUMB_COLUMNS:
        cells.append("")
    grid = [cells[i:i + THUMB_COLUMNS] for i in range(0, len(cells), THUMB_COLUMNS)]
    table = Table(grid, colWidths=[FRAME_W / THUMB_COLUMNS] * THUMB_COLUMNS,
                  hAlign="LEFT")
    table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    flows = [renderer.heading_flowable("Gallery", "Gallery", 1, "h1"),
             Paragraph(esc("%d charts and diagrams, each rendered by the Neper "
                           "charting engine; every chart also exists as an SVG "
                           "in %s." % (len(charts), CHART_DIR)), styles["body"]),
             table]
    notes = section_between(read_repo(CHARTS_DOC),
                            "## Charting-engine delivery evidence",
                            "## Neper charting engine plan")
    flows.extend(render_markdown(notes, renderer, md, text_tool))
    return flows


# -- targets --

TARGET_DOCS = ("macos", "ios", "android", "freebsd")
OS_FORMAT = {"windows": "PE", "linux": "ELF", "macos": "Mach-O"}


def targets_inputs():
    return [REPO_ROOT / "docs/spec.md", REPO_ROOT / "src/project.e"] + [
        REPO_ROOT / ("docs/%s-cross-compilation.md" % n) for n in TARGET_DOCS]


def build_targets(entry, renderer, styles, md, text_tool):
    spec, project = read_repo("docs/spec.md"), read_repo("src/project.e")
    sentence = re.search(r"A host target is (.+?); unsupported", spec, re.S).group(1)
    hosts = re.findall(r"`([a-z0-9]+-[a-z0-9]+)`", sentence)

    def accepted(fn, var):
        body = re.search(r"fn %s\(.*?\n}\n" % fn, project, re.S).group(0)
        return re.findall(r'same\(%s, "(\w+)"\)' % var, body)

    arches, systems = accepted("valid_arch", "arch"), accepted("valid_os", "value")
    kernel = re.search(r"// (aarch64-none is [^\n]*)", project).group(1)
    neperos = re.search(r"// (aarch64-neperos is [^\n]*)", project).group(1)
    levels = []
    block = section_between(spec, "### Target CPU levels", "**`x64-v3` is the default")
    in_table = False
    for line in block.splitlines():
        if line.startswith("|"):
            levels.append(line)
            in_table = True
        elif in_table:
            levels.append("")
            in_table = False
    out = ["# Host targets", "",
           "A host target builds an executable for one architecture and "
           "operating system. `--target ARCH-OS` selects it; the operating "
           "system is never inferred from the build machine, so any host "
           "target can be built from any build host.", "",
           "| Target | Architecture | Operating system | Executable format |",
           "|---|---|---|---|"]
    for host in hosts:
        arch, system = host.split("-", 1)
        out.append("| `%s` | %s | %s | %s |"
                   % (host, arch, system, OS_FORMAT.get(system, "?")))
    out += ["", "# Freestanding and NeperOS targets", "",
            "- `aarch64-none`: " + kernel.split(" is ", 1)[1],
            "- `aarch64-neperos`: " + neperos.split(" is ", 1)[1], "",
            "# GPU device targets", "",
            "`spv` (SPIR-V) and `ptx` (NVIDIA PTX) build device modules only, "
            "for inspection with `neper dis`; they produce no executable. A "
            "host build embeds them with `--gpu spv,ptx|none` (default `spv`).",
            "", "# Instruction levels (`--cpu`)", ""]
    out += levels
    out += ["", "# Accepted names", "",
            "The compiler accepts these architectures: " + ", ".join(
                "`%s`" % a for a in arches) + ".", "",
            "It accepts these operating systems: " + ", ".join(
                "`%s`" % s for s in systems) + ".", "",
            "A combination outside the host, freestanding and device lists "
            "above is an option error.", "", "# Platform status", ""]
    for name in TARGET_DOCS:
        text = read_repo("docs/%s-cross-compilation.md" % name)
        status = re.search(r"^Status:(.*?)(?:\n\n|\Z)", text, re.S | re.M)
        out.append("- **%s**: %s" % (
            name, " ".join(status.group(1).split()) if status else "no status"))
    return render_markdown("\n".join(out), renderer, md, text_tool)


# -- NeperOS --

NEPEROS_SRC = "neperos/src"
NEPEROS_DOCS = ("docs/appkit-api.md", "docs/neperos-display-research.md")
NEPEROS_SURFACE = ("lib/e/os.neperos.e", "src/runtime_neperos_a64.e")
# The files whose opening comment says how the system is put together.
NEPEROS_OVERVIEW = ("main", "mmu", "vm", "init", "fs_server", "input_server",
                    "net_server", "settings_server", "shell", "launcher",
                    "package", "vault")


def neperos_sources():
    return sorted((REPO_ROOT / NEPEROS_SRC).glob("*.e"))


def neperos_tasks():
    return sorted((REPO_ROOT / "docs/tasks/compiler").glob("C*-neperos-*.md"))


def neperos_scripts():
    return sorted((REPO_ROOT / "scripts").glob("neperos*.py"))


def neperos_inputs():
    return (neperos_sources() + neperos_tasks() + neperos_scripts()
            + [REPO_ROOT / f for f in NEPEROS_SURFACE + NEPEROS_DOCS])


def script_summary(text, limit=300):
    lines = text.replace("\r\n", "\n").split("\n")
    if lines and lines[0].startswith("#!"):
        lines = lines[1:]
    joined = "\n".join(lines).lstrip()
    if joined.startswith('"""'):
        body = joined[3:].split('"""', 1)[0]
        summary = " ".join(body.split())
    else:
        block = []
        for line in lines:
            if line.startswith("#"):
                block.append(line[1:].strip())
            elif block:
                break
        summary = " ".join(" ".join(block).split())
    return summary if len(summary) <= limit else (
        summary[:limit].rsplit(" ", 1)[0] + "...")


def build_neperos(entry, renderer, styles, md, text_tool):
    sources = neperos_sources()
    tasks = neperos_tasks()
    scripts = neperos_scripts()
    san = text_tool.sanitize

    def para(text, style="body"):
        return Paragraph(esc(san(text).replace("`", "")), styles[style])

    def h1(title):
        return renderer.heading_flowable(esc(title), title, 1, "h1")

    flows = [para("NeperOS is Neper's own operating system: an aarch64 "
                  "microkernel whose drivers, filesystem, network, settings and "
                  "input run as EL0 servers that apps reach over capability-gated "
                  "IPC. Apps are ordinary Neper programs built with "
                  "`--target aarch64-neperos`. Everything below is read from "
                  "the repository: %d source files in %s, %d open work items, "
                  "and the documents it keeps." % (len(sources), NEPEROS_SRC,
                                                   len(tasks)))]

    flows.append(h1("How it is put together"))
    by_name = {p.stem: p for p in sources}
    for name in NEPEROS_OVERVIEW:
        if name in by_name:
            flows.append(para("%s/%s.e: %s" % (
                NEPEROS_SRC, name, leading_comment(
                    by_name[name].read_text(encoding="utf-8", errors="replace"),
                    700)), "tight"))
            flows.append(Spacer(1, 4))

    flows.append(h1("Platform surface"))
    for rel in NEPEROS_SURFACE:
        text = read_repo(rel)
        flows.append(para("%s: %s" % (rel, leading_comment(text, 1500)), "tight"))
        flows.append(Spacer(1, 4))
    flows.append(para("The functions of the e.os surface on NeperOS are listed in "
                      "the Library reference under e.os.neperos."))

    flows.append(h1("Source inventory"))
    rows = [[p.name, leading_comment(
        p.read_text(encoding="utf-8", errors="replace"), 220) or "-"]
        for p in sources]
    flows.extend(table_flows(renderer, ["File in %s" % NEPEROS_SRC,
                                        "What it is"],
                             [[san(c) for c in r] for r in rows]))

    for rel in NEPEROS_DOCS:
        flows.extend(render_markdown(read_repo(rel), renderer, md, text_tool))

    flows.append(h1("Open work"))
    flows.append(para("Every NeperOS item still on the work queue. A delivered "
                      "item leaves the queue; its regression test is its "
                      "specification."))
    rows = []
    for path in tasks:
        text = path.read_text(encoding="utf-8", errors="replace")
        title = re.match(r"# (C\d+)\s+\S+\s+(.*)", text)
        score = re.search(r"\|\s*score\s*\|\s*([\d.]+) of 1", text)
        rows.append([title.group(1) if title else path.stem[:4],
                     title.group(2).strip() if title else path.stem,
                     score.group(1) if score else "?"])
    flows.extend(table_flows(renderer, ["Item", "Title", "Score"],
                             [[san(c) for c in r] for r in rows]))

    flows.append(h1("Verification tooling"))
    rows = [[rel_posix(p), script_summary(
        p.read_text(encoding="utf-8", errors="replace"))] for p in scripts]
    flows.extend(table_flows(renderer, ["Script", "What it does"],
                             [[san(c) for c in r] for r in rows]))
    return flows


GENERATORS = {
    "neperos": {"inputs": neperos_inputs, "build": build_neperos},
    "targets": {"inputs": targets_inputs, "build": build_targets},
    "library": {"inputs": library_inputs, "build": build_library},
    "controls": {"inputs": controls_inputs, "build": build_controls},
    "charts": {"inputs": charts_inputs, "build": build_charts},
}


def resolve_documents():
    resolved, missing = [], []
    for index, entry in enumerate(DOCUMENTS):
        if entry.get("kind"):
            resolved.append({
                "title": entry["title"], "path": None, "kind": entry["kind"],
                "rel": "generated:" + entry["kind"],
                "anchor": "doc%d" % index, "names": [], "about": entry["about"],
                "inputs": GENERATORS[entry["kind"]]["inputs"](),
            })
            continue
        if entry.get("files"):
            inputs = [REPO_ROOT / f for f in entry["files"]]
            absent = [rel_posix(p) for p in inputs if not p.exists()]
            if absent:
                missing.extend(absent)
                continue
            resolved.append({
                "title": entry["title"], "path": None, "kind": None,
                "rel": entry["files"][0], "anchor": "doc%d" % index,
                "names": [Path(f).name for f in entry["files"]],
                "about": entry["about"], "inputs": inputs,
            })
            continue
        found = None
        for candidate in entry["paths"]:
            path = REPO_ROOT / candidate
            if path.exists():
                found = path
                break
        if found is None:
            missing.append(" or ".join(entry["paths"]))
            continue
        resolved.append({
            "title": entry["title"],
            "path": found,
            "rel": found.relative_to(REPO_ROOT).as_posix(),
            "anchor": "doc%d" % index,
            "names": [Path(c).name for c in entry["paths"]],
            "about": entry["about"],
        })
    return resolved, missing


def source_files(entry):
    if entry.get("inputs") is not None:
        return entry["inputs"]
    path = entry["path"]
    if path.is_dir():
        return sorted(p for p in path.rglob("*") if p.is_file())
    return [path]


def sha256_of(path):
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def read_text(path, text_tool):
    raw = path.read_text(encoding="utf-8", errors="replace")
    return text_tool.sanitize(raw.replace("\r\n", "\n").replace("\r", "\n"))


def document_flowables(entry, renderer, styles, md, text_tool):
    flows = []
    title = text_tool.sanitize(entry["title"])
    part = Paragraph(esc(title), styles["part"])
    part._toc_level = 0
    part._toc_text = title
    part._toc_key = entry["anchor"]
    flows.append(part)

    files = source_files(entry)
    if entry.get("kind"):
        meta = "generated by scripts/build-docs-pdf.py from %d files" % len(files)
        flows.append(Paragraph(esc(meta), styles["part_meta"]))
        flows.extend(GENERATORS[entry["kind"]]["build"](
            entry, renderer, styles, md, text_tool))
        flows.append(PageBreak())
        return flows
    if entry["path"] is None or entry["path"].is_dir():
        meta = "%s | %d files" % (entry["rel"], len(files))
    else:
        meta = "%s | %d bytes | sha256 %s" % (
            entry["rel"], entry["path"].stat().st_size,
            sha256_of(entry["path"])[:16])
    flows.append(Paragraph(esc(meta), styles["part_meta"]))

    for path in files:
        rel = path.relative_to(REPO_ROOT).as_posix()
        text = read_text(path, text_tool)
        if len(files) > 1:
            heading = renderer.heading_flowable(esc(rel), rel, 2, "h2")
            flows.append(heading)
        if path.suffix.lower() in (".md", ".markdown"):
            tokens = md.parse(text)
            body, _ = renderer.blocks(tokens, 0, None)
            flows.extend(body)
        else:
            flows.extend(renderer.code_block(text))
    flows.append(PageBreak())
    return flows


def build_story(entries, renderer, styles, md, text_tool, generated_at, revision):
    if LOGO.exists():
        pixel_w, pixel_h = ImageReader(str(LOGO)).getSize()
        logo_w = 122 * mm
        title = Image(str(LOGO), width=logo_w,
                      height=logo_w * pixel_h / pixel_w, mask="auto")
        title.hAlign = "LEFT"
    else:
        title = Paragraph("neper", styles["cover_title"])
    story = [Spacer(1, 62 * mm), title, Spacer(1, 14),
             Paragraph(esc(text_tool.sanitize(
                 "Language, toolchain and targets, library reference, UI "
                 "controls, charts, verification and decisions")),
                 styles["cover_sub"]),
             HRFlowable(width="100%", thickness=0.8, color=RULE),
             Spacer(1, 12)]
    total_files = sum(len(source_files(e)) for e in entries)
    cover_lines = [
        "%d documents, %d source files" % (len(entries), total_files),
        "source revision: %s" % revision,
        "generated: %s" % generated_at,
        "generator: scripts/build-docs-pdf.py",
    ]
    for line in cover_lines:
        story.append(Paragraph(esc(line), styles["cover_meta"]))
    story.append(PageBreak())

    toc = TableOfContents()
    toc.levelStyles = [styles["toc0"], styles["toc1"], styles["toc2"],
                       styles["toc3"], styles["toc4"]]
    toc.dotsMinLevel = 0
    story.append(Paragraph("Contents", styles["h1"]))
    story.append(Spacer(1, 6))
    story.append(toc)
    story.append(PageBreak())

    story.append(Paragraph("Reading guide", styles["h1"]))
    story.append(Spacer(1, 6))
    story.extend(table_flows(
        renderer, ["Part", "What it holds"],
        [["%d. %s" % (i, text_tool.sanitize(e["title"])),
          text_tool.sanitize(e["about"])] for i, e in enumerate(entries, 1)]))
    story.append(PageBreak())

    for entry in entries:
        story.extend(document_flowables(entry, renderer, styles, md, text_tool))
    if isinstance(story[-1], PageBreak):
        story.pop()
    return story


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Build docs/neper.pdf from the neper documentation set.")
    parser.add_argument("--out", default=str(DEFAULT_OUTPUT),
                        help="output PDF path (default: docs/neper.pdf)")
    parser.add_argument("--quiet", action="store_true",
                        help="suppress progress output")
    args = parser.parse_args(argv)

    entries, missing = resolve_documents()
    if missing:
        for item in missing:
            sys.stderr.write("error: missing document: %s\n" % item)
        return 1

    sans, mono, supported = setup_fonts()
    text_tool = Text(supported)
    styles = build_styles(sans, mono)

    anchors = {}
    for entry in entries:
        for name in entry["names"]:
            anchors.setdefault(name, entry["anchor"])
        anchors.setdefault(entry["rel"].rsplit("/", 1)[-1], entry["anchor"])

    renderer = Renderer(styles, sans, mono, text_tool, anchors)
    md = MarkdownIt("commonmark").enable("table").enable("strikethrough")

    generated_at = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
    revision = git_description()

    if not args.quiet:
        print("fonts: %s / %s" % (sans["regular"], mono["regular"]))
        for entry in entries:
            print("  + %-52s %s" % (entry["rel"], entry["title"]))

    story = build_story(entries, renderer, styles, md, text_tool,
                        generated_at, revision)
    dropped = []
    collapse_single_child_levels(story, dropped)
    if dropped and not args.quiet:
        print("collapsed %d single-child outline level(s):" % len(dropped))
        for title in dropped:
            print("  - %s" % title)

    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = REPO_ROOT / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)

    doc = NeperDoc(str(out_path), pagesize=PAGE_SIZE,
                   title="neper documentation", author="neper project",
                   subject="neper language, toolchain and library documentation",
                   creator="scripts/build-docs-pdf.py")
    frame = Frame(MARGIN_X, MARGIN_BOTTOM, FRAME_W,
                  PAGE_H - MARGIN_TOP - MARGIN_BOTTOM, id="body",
                  leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    doc.addPageTemplates([PageTemplate(id="main", frames=[frame],
                                       onPageEnd=make_decorator(sans))])
    doc.multiBuild(story)

    if text_tool.unmapped:
        codes = ", ".join(sorted("U+%04X" % ord(c) for c in text_tool.unmapped))
        sys.stderr.write("warning: characters printed as [U+XXXX]: %s\n" % codes)

    if not args.quiet:
        print("wrote %s (%d pages, %.1f MiB)"
              % (out_path, doc.page, out_path.stat().st_size / (1024 * 1024)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
