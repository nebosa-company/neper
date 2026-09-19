"""Regenerate the readable PDF catalogue from authoritative Markdown and tier data."""
import argparse
from hashlib import sha256
from html import escape
import json
from pathlib import Path
import re

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, Preformatted, SimpleDocTemplate, Spacer


ROOT = Path(__file__).resolve().parents[1]


def printable(text):
    return text.translate(str.maketrans({"—": "-", "–": "-", "‑": "-", "→": "->"}))


def inline(text):
    text = printable(text)
    # The PDF is a readable export, not the machine-readable signature authority.
    text = re.sub(r"\[([^]]+)\]\(([^)]+)\)", lambda m: m[1] + " (" + m[2] + ")", text)
    text = escape(text)
    text = re.sub(r"`([^`]+)`", r'<font name="Code">\1</font>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "output/pdf/module-apis.pdf")
    parser.add_argument("--fonts", type=Path, default=Path("C:/Windows/Fonts"))
    args = parser.parse_args()
    for name, filename in [("Body", "segoeui.ttf"), ("BodyBold", "segoeuib.ttf"), ("Code", "consola.ttf")]:
        pdfmetrics.registerFont(TTFont(name, str(args.fonts / filename)))
    pdfmetrics.registerFontFamily("Body", normal="Body", bold="BodyBold", italic="Body", boldItalic="BodyBold")
    raw = (ROOT / "docs/module-apis.md").read_bytes()
    source = raw.decode("utf-8")
    plan = json.loads((ROOT / "docs/modules.json").read_text(encoding="utf-8"))
    tiers = {name: tier["id"] for tier in plan["tiers"] for name in tier["modules"]}
    styles = {
        "body": ParagraphStyle("body", fontName="Body", fontSize=8.3, leading=11.5, spaceAfter=6),
        "h1": ParagraphStyle("h1", fontName="BodyBold", fontSize=21, leading=25, spaceAfter=14, keepWithNext=True),
        "h2": ParagraphStyle("h2", fontName="BodyBold", fontSize=13, leading=17, spaceBefore=15, spaceAfter=8, keepWithNext=True),
        "h3": ParagraphStyle("h3", fontName="BodyBold", fontSize=10.5, leading=14, spaceBefore=12, spaceAfter=6, keepWithNext=True),
        "code": ParagraphStyle("code", fontName="Code", fontSize=7, leading=9.2, spaceAfter=8),
    }
    story, paragraph, code = [], [], []
    fenced = False

    def flush_paragraph():
        if paragraph:
            story.append(Paragraph(inline(" ".join(paragraph)), styles["body"]))
            paragraph.clear()

    for line in source.splitlines():
        if line.startswith("```"):
            flush_paragraph()
            if fenced:
                story.append(Preformatted(printable("\n".join(code)), styles["code"],
                                          maxLineLength=115, splitChars=" ,", newLineChars="    "))
                code.clear()
            fenced = not fenced
            continue
        if fenced:
            code.append(line)
        elif line.startswith("# "):
            flush_paragraph()
            story.append(Paragraph(inline(line[2:]), styles["h1"]))
            counts = ", ".join(f"{len(t['modules'])} {t['id']}" for t in plan["tiers"])
            story.append(Paragraph(f"Next-contract design - {len(tiers)} modules ({counts}).<br/>"
                                   "Generated from docs/module-apis.md; not evidence of implementation.", styles["body"]))
        elif line.startswith("## "):
            flush_paragraph()
            story.append(Paragraph(inline(line[3:]), styles["h2"]))
        elif line.startswith("### "):
            flush_paragraph()
            module = line[4:].strip("`")
            label = module + (" / " + tiers[module] if module in tiers else "")
            story.append(Paragraph(escape(label), styles["h3"]))
        elif not line.strip() or line == "---":
            flush_paragraph()
        else:
            paragraph.append(line)
    flush_paragraph()
    if fenced:
        raise ValueError("Unclosed Markdown code fence")
    story.append(Spacer(1, 12))
    story.append(Paragraph("Source SHA-256: " + sha256(raw).hexdigest(), styles["body"]))

    def page_frame(canvas, document):
        width, height = A4
        canvas.saveState()
        canvas.setFont("Body", 7)
        canvas.setFillColor(colors.HexColor("#526273"))
        canvas.drawString(40, height - 25, "NEPER / STANDARD LIBRARY / NEXT-CONTRACT DESIGN")
        canvas.drawRightString(width - 40, 23, str(document.page))
        canvas.drawString(40, 23, "Source of truth: docs/module-apis.md + docs/modules.json")
        canvas.restoreState()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    document = SimpleDocTemplate(str(args.output), pagesize=A4, leftMargin=40, rightMargin=40,
                                 topMargin=43, bottomMargin=40, title="Neper module API catalogue",
                                 author="Neper", subject="Next-contract library design; generated from Markdown")
    document.build(story, onFirstPage=page_frame, onLaterPages=page_frame)
    print(args.output)


if __name__ == "__main__":
    main()
