#!/usr/bin/env python3
"""由 translations.py 生成 Resources/Localizable.xcstrings，并校验：
   key 全覆盖、占位符一致、无空译文。用法：python3 scripts/i18n/build_catalog.py [keys.json]"""
import json, os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
from translations import T, LANGS
root = os.path.dirname(os.path.dirname(here))
ph = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f)")
errors = []
for k, row in T.items():
    if len(row) != len(LANGS): errors.append(f"列数不对：{k}")
    for lang, v in zip(LANGS, row):
        if not v.strip(): errors.append(f"空译文：{lang} {k}")
        if sorted(ph.findall(k)) != sorted(ph.findall(v)): errors.append(f"占位符不一致：{lang} {k!r} → {v!r}")
if len(sys.argv) > 1:   # 与编译提取出的 key 对比
    extracted = set(json.load(open(sys.argv[1])))
    for k in sorted(extracted - set(T)): errors.append(f"缺翻译：{k!r}")
    for k in sorted(set(T) - extracted): print(f"提示：翻译表里多余的 key {k!r}")
if errors:
    print("\n".join(errors)); sys.exit(1)
cat = {"sourceLanguage": "zh-Hans", "version": "1.0", "strings": {}}
for k, row in sorted(T.items()):
    locs = {"zh-Hans": {"stringUnit": {"state": "translated", "value": k}}}
    for lang, v in zip(LANGS, row):
        locs[lang] = {"stringUnit": {"state": "translated", "value": v}}
    cat["strings"][k] = {"localizations": locs}
out = os.path.join(root, "Resources", "Localizable.xcstrings")
json.dump(cat, open(out, "w"), ensure_ascii=False, indent=2, sort_keys=True)
print(f"OK：{len(T)} 条 × {len(LANGS) + 1} 种语言 → {out}")
