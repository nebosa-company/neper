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

# Each entry lists candidate paths; the first one that exists is used.
DOCUMENTS = [
    {"title": "Language specification", "paths": ["docs/spec.md"]},
    {"title": "Module architecture", "paths": ["docs/modules.md"]},
    {"title": "Module API catalogue", "paths": ["docs/module-apis.md"]},
    {"title": "Roadmap", "paths": ["docs/roadmap.md"]},
    {"title": "Decisions", "paths": ["docs/decisions.md", "DECISIONS.md"]},
    {"title": "Diagnostic fixtures",
     "paths": ["tests/selfhost/fixtures/diagnostics"]},
    {"title": "General-purpose verification",
     "paths": ["docs/general-purpose-verification.md"]},
    {"title": "Grammar", "paths": ["docs/grammar.ebnf", "grammar.ebnf"]},
    {"title": "pacman package manager", "paths": ["docs/pacman.md"]},
    {"title": "Tooling protocol", "paths": ["docs/tooling.md"]},
    {"title": "UI framework", "paths": ["docs/ui-framework.md"]},
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
    "\u2022": "-", "\u00b7": "-",
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
                replacement = "?"
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


def resolve_documents():
    resolved, missing = [], []
    for index, entry in enumerate(DOCUMENTS):
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
        })
    return resolved, missing


def source_files(entry):
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
    if entry["path"].is_dir():
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


def manifest_flowables(entries, renderer, styles, text_tool):
    flows = []
    part = Paragraph("Source manifest", styles["part"])
    part._toc_level = 0
    part._toc_text = "Source manifest"
    part._toc_key = "manifest"
    flows.append(part)
    flows.append(Paragraph(
        esc("Every file rendered above, with its size and SHA-256. "
            "Re-running scripts/build-docs-pdf.py over the same inputs "
            "reproduces the same content."), styles["body"]))
    rows = [["Path", "Bytes", "SHA-256"]]
    plains = [["Path", "Bytes", "SHA-256"]]
    for entry in entries:
        for path in source_files(entry):
            rel = path.relative_to(REPO_ROOT).as_posix()
            size = str(path.stat().st_size)
            digest = sha256_of(path)
            cell = ('<font face="%s" size="6.8">%s</font>'
                    % (renderer.mono["regular"], digest))
            rows.append([esc(rel), size, cell])
            plains.append([rel, size, digest])
    flows.extend(renderer.build_table(rows, plains, 1, 0.0))
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
                 "Language specification, module plan, roadmap, verification "
                 "and tooling contracts")), styles["cover_sub"]),
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

    for entry in entries:
        story.extend(document_flowables(entry, renderer, styles, md, text_tool))
    story.extend(manifest_flowables(entries, renderer, styles, text_tool))
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
        sys.stderr.write("warning: characters replaced with '?': %s\n" % codes)

    if not args.quiet:
        print("wrote %s (%d pages, %.1f MiB)"
              % (out_path, doc.page, out_path.stat().st_size / (1024 * 1024)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
