#!/usr/bin/env python3
"""把发布备注 Markdown 转成 Sparkle appcast 内嵌的发布说明 HTML。

只覆盖本仓库发布备注实际用到的语法:标题、段落、有序/无序列表、粗体、
行内代码、链接、分隔线、引用、简单表格。超出语法的内容按纯文本转义输出,
不会产生破损 HTML。
"""
import html
import re
import sys
from pathlib import Path


def inline(value: str) -> str:
    value = html.escape(value, quote=False)
    value = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", value)
    value = re.sub(r"`([^`]+)`", r"<code>\1</code>", value)
    value = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', value)
    return value


def convert(text: str) -> str:
    out, paragraph, list_tag = [], [], None

    def flush_paragraph():
        nonlocal paragraph
        if paragraph:
            out.append("<p>%s</p>" % inline(" ".join(paragraph)))
            paragraph = []

    def flush_list():
        nonlocal list_tag
        if list_tag:
            out.append("</%s>" % list_tag)
            list_tag = None

    def set_list(tag: str):
        nonlocal list_tag
        if list_tag == tag:
            return
        flush_list()
        out.append("<%s>" % tag)
        list_tag = tag

    lines = text.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index].rstrip()
        if not line.strip():
            flush_paragraph()
            flush_list()
            index += 1
            continue
        if (re.match(r"^\s*\|", line) and index + 1 < len(lines)
                and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[index + 1])):
            flush_paragraph()
            flush_list()
            rows = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                cells = [c.strip() for c in lines[index].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-+:?", c) for c in cells):
                    rows.append(cells)
                index += 1
            out.append("<table>")
            for position, cells in enumerate(rows):
                tag = "th" if position == 0 else "td"
                out.append("<tr>" + "".join(
                    f"<{tag}>{inline(cell)}</{tag}>" for cell in cells) + "</tr>")
            out.append("</table>")
            continue
        heading = re.match(r"^(#{1,6})\s+(.*)$", line)
        if heading:
            flush_paragraph()
            flush_list()
            level = min(len(heading.group(1)) + 1, 6)
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
            index += 1
            continue
        if re.match(r"^\s*(-{3,}|\*{3,})\s*$", line):
            flush_paragraph()
            flush_list()
            out.append("<hr/>")
            index += 1
            continue
        bullet = re.match(r"^\s*[-*]\s+(.*)$", line)
        if bullet:
            flush_paragraph()
            set_list("ul")
            out.append("<li>%s</li>" % inline(bullet.group(1)))
            index += 1
            continue
        numbered = re.match(r"^\s*\d+\.\s+(.*)$", line)
        if numbered:
            flush_paragraph()
            set_list("ol")
            out.append("<li>%s</li>" % inline(numbered.group(1)))
            index += 1
            continue
        quote = re.match(r"^\s*>\s?(.*)$", line)
        if quote:
            flush_list()
            flush_paragraph()
            out.append("<blockquote><p>%s</p></blockquote>" % inline(quote.group(1)))
            index += 1
            continue
        paragraph.append(line.strip())
        index += 1

    flush_paragraph()
    flush_list()
    body = "\n".join(out)
    return body if body else "<p>详见 GitHub Release 页。</p>"


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if target is None or not target.is_file():
        print("<p>详见 GitHub Release 页。</p>")
    else:
        print(convert(target.read_text(encoding="utf-8")))
