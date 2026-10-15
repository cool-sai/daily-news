#!/usr/bin/env python3
"""扫描 data/*.md 生成 data/index.json（无第三方依赖）。用法: python3 build_index.py"""
import json, re, pathlib
ROOT = pathlib.Path(__file__).parent
SECS = ["AI / 大模型", "跨行业重点", "热门影视", "个人开发者案例", "产品建议"]
def norm_sec(h):
    for s in SECS:
        if s.replace(" ", "") in h.replace(" ", ""): return s
    return h.strip()
def parse(md):
    sec, items, hl, in_hl = "AI / 大模型", [], [], False
    for line in md.splitlines():
        s = line.strip()
        if s.startswith("## "): sec = norm_sec(s[3:]); in_hl = False; continue
        if s.startswith("**今日重点"): in_hl = True; continue
        m = re.match(r"^(\d+)[.、]\s*(.+)$", s)
        if m:
            t = re.sub(r"\*\*|\[|\]\([^)]*\)", "", m.group(2)).strip()
            if in_hl: hl.append(t)
            else: items.append({"section": sec, "title": t})
        elif not s: pass
        elif in_hl and not s.startswith(tuple("0123456789")): in_hl = False
    return items, hl
out = []
for f in sorted((ROOT / "data").glob("????-??-??.md"), reverse=True):
    md = f.read_text(encoding="utf-8")
    items, hl = parse(md)
    counts = {}
    for it in items: counts[it["section"]] = counts.get(it["section"], 0) + 1
    out.append({"date": f.stem, "headline": md.strip().splitlines()[0][:120], "highlights": hl[:3] or [i["title"] for i in items[:3]],
                "counts": counts, "items": items, "text": re.sub(r"\s+", " ", md)})
(ROOT / "data" / "index.json").write_text(json.dumps(out, ensure_ascii=False, indent=0), encoding="utf-8")
print(f"index: {len(out)} 期")
