#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
发布打包：把 addons/<插件名>/ 打成可直接上传到 CurseForge / Wago 的 zip。

要点：
  1. zip 内顶层必须是「插件名/」目录，否则玩家解压后目录名不对，游戏认不出。
  2. 只打包插件运行需要的文件，*.bak / *.orig / 测试产物一律排除
     （.bak 里是旧版代码，混进去会让玩家加载到错误的实现）。
  3. 条目分隔符用正斜杠 —— WoW 与其它解压工具对反斜杠路径处理不一致。
  4. 版本号从 .toc 的 ## Version 读，不手动维护，避免与文件名不一致。

用法：
  python _tools/package.py                       # 打包 AutoMountLite
  python _tools/package.py --addon XXX           # 打包指定插件
  python _tools/package.py --dest D:/tmp         # 指定输出目录（默认 dist/）
"""
import argparse
import hashlib
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# 允许进包的扩展名（小写比较）
INCLUDE_EXT = {".lua", ".toc", ".xml", ".txt", ".md", ".license"}
# 显式包含的文件名（无扩展名或不在上面列表里的）
INCLUDE_NAME = {"license", "changelog", "changelog.txt"}
# 明确排除
EXCLUDE_SUFFIX = {".bak", ".orig", ".zip"}
EXCLUDE_DIR = {"__pycache__", ".git"}


def read_toc_version(toc_path: str) -> str:
    with open(toc_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r"^##\s*Version:\s*(.+?)\s*$", line, re.I)
            if m:
                return m.group(1).strip()
    return "0.0.0"


def should_include(name: str) -> bool:
    if name.lower() in EXCLUDE_DIR:
        return False
    low = name.lower()
    if any(low.endswith(s) for s in EXCLUDE_SUFFIX):
        return False
    ext = os.path.splitext(low)[1]
    return ext in INCLUDE_EXT or low in INCLUDE_NAME


def main() -> int:
    ap = argparse.ArgumentParser(description="打包 WoW 插件为发布用 zip")
    ap.add_argument("--addon", default="AutoMountLite", help="插件目录名（默认 AutoMountLite）")
    ap.add_argument("--dest", default=os.path.join(ROOT, "dist"), help="输出目录（默认 dist/）")
    args = ap.parse_args()

    src = os.path.join(ROOT, "addons", args.addon)
    toc = os.path.join(src, args.addon + ".toc")
    if not os.path.isfile(toc):
        print(f"[FAIL] 找不到 {toc}", file=sys.stderr)
        print("       addons/<插件名>/<插件名>.toc 必须存在，且文件名与目录名一致。", file=sys.stderr)
        return 1

    version = read_toc_version(toc)
    os.makedirs(args.dest, exist_ok=True)
    out = os.path.join(args.dest, f"{args.addon}-{version}.zip")

    files = []
    for dirpath, dirnames, filenames in os.walk(src):
        dirnames[:] = [d for d in dirnames if d.lower() not in EXCLUDE_DIR]
        for fn in sorted(filenames):
            if not should_include(fn):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, src).replace("\\", "/")
            files.append((full, f"{args.addon}/{rel}"))

    if not files:
        print(f"[FAIL] {src} 下没有可打包文件", file=sys.stderr)
        return 1

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for full, arc in files:
            z.write(full, arc)

    h = hashlib.md5()
    with open(out, "rb") as f:
        h.update(f.read())

    print(f"[OK] {out}")
    print(f"     version = {version}   files = {len(files)}   md5 = {h.hexdigest()}")
    for _, arc in files:
        print(f"       - {arc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
