#!/usr/bin/env python3
"""SEO regression lint for the generated docs tree.

Walks docs/**/*.html and fails (exit 1) when an indexable page regresses on the
conditions listed in issue #341, and when a preview/tracker page is indexable.
This script is deliberately self-contained (stdlib only) so CI can run it with
the repository's own interpreter:

    build/uv-python/cpython-3.12.13-windows-x86_64-none/python.exe scripts/seo_lint.py

Options: --docs PATH (default: docs), --max-report N (default: 40).
"""

from __future__ import annotations

import argparse
import html
import os
import posixpath
import re
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser

MAX_TITLE = 60
MAX_DESCRIPTION = 160
OG_IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp")
TRACKER_HINTS = ("tracker", "progress")
SITEMAP_NS = "{http://www.sitemaps.org/schemas/sitemap/0.9}"


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.title_depth = 0
        self.title_text: list[str] = []
        self.h1 = 0
        self.meta: list[dict[str, str]] = []
        self.links: list[dict[str, str]] = []
        self.images: list[dict[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr = {k.lower(): (v if v is not None else "") for k, v in attrs}
        if tag == "title":
            self.title_depth += 1
        elif tag == "h1":
            self.h1 += 1
        elif tag == "meta":
            self.meta.append(attr)
        elif tag == "link":
            self.links.append(attr)
        elif tag == "img":
            self.images.append(attr)
        if tag not in ("meta", "link", "img", "br", "hr", "input", "source", "wbr"):
            self.stack.append(tag)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        if tag not in ("meta", "link", "img", "br", "hr", "input", "source", "wbr"):
            self.handle_endtag(tag)

    def handle_endtag(self, tag: str) -> None:
        if tag == "title" and self.title_depth:
            self.title_depth -= 1
        if tag in self.stack:
            while self.stack:
                open_tag = self.stack.pop()
                if open_tag == tag:
                    break

    def handle_data(self, data: str) -> None:
        if self.title_depth:
            self.title_text.append(data)


def parse_page(path: str) -> PageParser:
    parser = PageParser()
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        parser.feed(handle.read())
    parser.close()
    return parser


def meta_values(meta: list[dict[str, str]], key: str, value: str) -> list[str]:
    found = []
    for attrs in meta:
        if attrs.get(key, "").strip().lower() == value:
            found.append(attrs.get("content", ""))
    return found


def has_noindex(meta: list[dict[str, str]]) -> bool:
    for attrs in meta:
        if attrs.get("name", "").strip().lower() == "robots":
            if "noindex" in attrs.get("content", "").strip().lower():
                return True
    return False


def sitemap_entries(docs: str) -> dict[str, str | None]:
    """Map page paths (posix, relative to docs/) to their lastmod."""
    path = os.path.join(docs, "sitemap.xml")
    if not os.path.isfile(path):
        return {}
    entries: dict[str, str | None] = {}
    try:
        tree = ET.parse(path)
    except ET.ParseError as error:
        print(f"[seo-lint] cannot parse sitemap: {error}")
        return {}
    for url in tree.getroot().iter(f"{SITEMAP_NS}url"):
        loc = url.findtext(f"{SITEMAP_NS}loc") or ""
        lastmod = url.findtext(f"{SITEMAP_NS}lastmod")
        loc = loc.strip()
        loc_path = re.sub(r"^https?://[^/]+", "", loc)
        if not loc_path or loc_path == "/":
            page = "index.html"
        elif loc_path.endswith("/"):
            page = loc_path.lstrip("/") + "index.html"
        else:
            page = loc_path.lstrip("/")
        entries[page] = (lastmod or "").strip() or None
    return entries


def looks_like_tracker(name: str) -> bool:
    lowered = name.lower()
    return any(hint in lowered for hint in TRACKER_HINTS)


def target_exists(docs: str, page_rel: str, href: str) -> bool:
    href = html.unescape(href.strip())
    if not href or href.startswith(("#", "mailto:", "tel:", "javascript:", "data:")):
        return True
    # Absolute URL: the lint cannot check remote targets.
    if re.match(r"^[a-z][a-z0-9+.-]*:", href, re.IGNORECASE):
        return True
    href = href.split("#", 1)[0].split("?", 1)[0]
    if not href:
        return True
    if href.startswith("//"):
        return True
    if href.startswith("/"):
        # Site-relative: resolved from the docs root.
        resolved = href.lstrip("/")
        base = ""
    else:
        resolved = posixpath.normpath(posixpath.join(posixpath.dirname(page_rel), href))
        base = ""
    resolved = resolved.lstrip("./")
    candidate = os.path.join(docs, *resolved.split("/")) if resolved else docs
    if os.path.isfile(candidate):
        return True
    if href.endswith("/") or os.path.isdir(candidate):
        return os.path.isfile(os.path.join(candidate, "index.html"))
    return False


def main() -> int:
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    arg_parser = argparse.ArgumentParser(description="SEO lint for docs/**/*.html")
    arg_parser.add_argument("--docs", default=os.path.join(repo_root, "docs"))
    arg_parser.add_argument("--max-report", type=int, default=40)
    args = arg_parser.parse_args()

    docs = os.path.abspath(args.docs)
    pages = []
    for root, _dirs, files in os.walk(docs):
        for name in files:
            if name.endswith(".html"):
                pages.append(os.path.relpath(os.path.join(root, name), docs).replace(os.sep, "/"))
    pages.sort()

    failures: list[str] = []
    titles: dict[str, list[str]] = {}
    descriptions: dict[str, list[str]] = {}
    sitemap = sitemap_entries(docs)

    for rel in pages:
        path = os.path.join(docs, *rel.split("/"))
        parsed = parse_page(path)
        trackerish = looks_like_tracker(rel)
        indexable = not has_noindex(parsed.meta)

        if (rel.endswith("preview.html") or trackerish) and not has_noindex(parsed.meta):
            failures.append(f"{rel}: preview/tracker page is indexable (no noindex)")

        # Utility pages are not SEO pages: after the noindex requirement above, do not
        # also demand titles, descriptions and sitemap entries they were never meant to have.
        if rel.endswith("preview.html") or trackerish:
            continue

        if not indexable:
            continue

        # Sitemap.
        if rel not in sitemap:
            failures.append(f"{rel}: missing from sitemap.xml")
        elif not sitemap[rel]:
            failures.append(f"{rel}: sitemap entry has no lastmod")

        # Title.
        title = "".join(parsed.title_text).strip()
        if not title:
            failures.append(f"{rel}: missing <title>")
        elif len(title) > MAX_TITLE:
            failures.append(f"{rel}: title is {len(title)} chars (max {MAX_TITLE})")
        else:
            titles.setdefault(title, []).append(rel)

        # Description.
        descs = [d.strip() for d in meta_values(parsed.meta, "name", "description") if d.strip()]
        if not descs:
            failures.append(f"{rel}: missing meta description")
        for desc in descs:
            if len(desc) > MAX_DESCRIPTION:
                failures.append(f"{rel}: description is {len(desc)} chars (max {MAX_DESCRIPTION})")
            descriptions.setdefault(desc, []).append(rel)

        # Canonical.
        canonical = [
            link.get("href", "").strip()
            for link in parsed.links
            if "canonical" in link.get("rel", "").lower().split()
        ]
        if not canonical or not canonical[0]:
            failures.append(f"{rel}: missing rel=canonical")

        # Open Graph image.
        images = [i.strip() for i in meta_values(parsed.meta, "property", "og:image") if i.strip()]
        if not images:
            failures.append(f"{rel}: missing og:image")
        for image in images:
            clean = image.split("?", 1)[0].split("#", 1)[0].lower()
            if not clean.endswith(OG_IMAGE_SUFFIXES):
                failures.append(f"{rel}: og:image is not PNG/JPG/WebP: {image}")

        # Headings.
        if parsed.h1 != 1:
            failures.append(f"{rel}: {parsed.h1} <h1> elements (exactly one required)")

        # Images.
        for image in parsed.images:
            src = image.get("src", "")
            if "alt" not in image:
                failures.append(f"{rel}: <img> without alt: {src}")
            if not image.get("width", "").strip() or not image.get("height", "").strip():
                failures.append(f"{rel}: <img> without width/height: {src}")

        # Relative links.
        for link in parsed.links:
            href = link.get("href", "")
            if href and not target_exists(docs, rel, href):
                failures.append(f"{rel}: relative link leads nowhere: {href}")

    for title, owners in sorted(titles.items()):
        if len(owners) > 1:
            failures.append(f"duplicate title ({len(owners)}): {title!r} in {', '.join(owners)}")
    for desc, owners in sorted(descriptions.items()):
        if len(owners) > 1:
            failures.append(f"duplicate description ({len(owners)}): {desc[:60]!r}... in {', '.join(owners)}")

    failures.sort()
    print(f"seo-lint: {len(pages)} html pages, {len(failures)} failure(s)")
    for line in failures[: args.max_report]:
        print(f"  {line}")
    if len(failures) > args.max_report:
        print(f"  ... {len(failures) - args.max_report} more")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
