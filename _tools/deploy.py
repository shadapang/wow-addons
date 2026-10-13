#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 addons/ 下的插件一键部署到魔兽世界的 Interface/AddOns 目录。

用法：
    python _tools/deploy.py                      # 部署到默认目录
    python _tools/deploy.py --dest "D:\\..."     # 指定 AddOns 目录
    python _tools/deploy.py --only AutoMountLite # 只部署某个插件
    python _tools/deploy.py --dry-run            # 只看会同步什么，不真写

不复制：*.bak / *.pyc / __pycache__ / 隐藏文件。
复制后逐个文件做 md5 校验，源和目标不一致会报错退出（退出码 1）。
"""

import argparse
import hashlib
import shutil
import sys
from pathlib import Path

DEFAULT_DEST = r"D:\World of Warcraft\_retail_\Interface\AddOns"
ROOT = Path(__file__).resolve().parent.parent
ADDONS_DIR = ROOT / "addons"

IGNORE = shutil.ignore_patterns("*.bak", "*.pyc", "__pycache__", ".*")


def md5(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def deploy_one(src: Path, dest_root: Path, dry_run: bool) -> tuple[int, int, list[str]]:
    """返回 (新增, 更新, 错误列表)"""
    target = dest_root / src.name
    added = updated = 0
    errors: list[str] = []

    if dry_run:
        for f in sorted(src.rglob("*")):
            if f.is_file() and not f.name.endswith(".bak"):
                rel = f.relative_to(src)
                print(f"   [预览] {src.name}/{rel}")
                added += 1
        return added, 0, errors

    target.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, target, ignore=IGNORE, dirs_exist_ok=True)

    for f in sorted(src.rglob("*")):
        if not f.is_file():
            continue
        if f.name.endswith(".bak") or f.name.startswith("."):
            continue
        rel = f.relative_to(src)
        dst = target / rel
        if not dst.exists():
            errors.append(f"{src.name}/{rel}: 目标缺失")
            continue
        if md5(f) != md5(dst):
            errors.append(f"{src.name}/{rel}: md5 不一致（源 {md5(f)[:8]} / 目标 {md5(dst)[:8]}）")
            continue
        if dst.stat().st_mtime <= f.stat().st_mtime:
            updated += 1
        else:
            added += 1

    return added, updated, errors


def main() -> int:
    ap = argparse.ArgumentParser(description="部署 wow-addons 插件到游戏 AddOns 目录")
    ap.add_argument("--dest", default=DEFAULT_DEST, help=f"目标 AddOns 目录（默认 {DEFAULT_DEST}）")
    ap.add_argument("--only", help="只部署指定插件（目录名）")
    ap.add_argument("--dry-run", action="store_true", help="只预览不写入")
    args = ap.parse_args()

    if not ADDONS_DIR.is_dir():
        print(f"[错误] 找不到源目录：{ADDONS_DIR}")
        return 1

    dest_root = Path(args.dest)
    if not args.dry_run and not dest_root.is_dir():
        print(f"[错误] 目标目录不存在：{dest_root}")
        print("       换一个：python _tools/deploy.py --dest \"你的 AddOns 路径\"")
        return 1

    plugins = sorted(p for p in ADDONS_DIR.iterdir() if p.is_dir())
    if args.only:
        plugins = [p for p in plugins if p.name == args.only]
        if not plugins:
            print(f"[错误] addons/ 下没有插件：{args.only}")
            return 1

    print(f"源：{ADDONS_DIR}")
    print(f"目标：{dest_root}{'（预览模式，不写入）' if args.dry_run else ''}")
    print("-" * 60)

    total_a = total_u = 0
    all_errors: list[str] = []
    for p in plugins:
        print(f"\n[{p.name}]")
        a, u, errs = deploy_one(p, dest_root, args.dry_run)
        if not args.dry_run:
            print(f"   新增 {a} / 更新 {u} 个文件")
        total_a += a
        total_u += u
        all_errors.extend(errs)

    print("\n" + "=" * 60)
    if args.dry_run:
        print(f"预览完成：{len(plugins)} 个插件，共 {total_a} 个文件会被同步")
        return 0

    print(f"部署完成：{len(plugins)} 个插件，新增 {total_a} / 更新 {total_u}")
    if all_errors:
        print("\n[校验失败]")
        for e in all_errors:
            print(f"   {e}")
        return 1
    print("md5 校验全部通过。重启游戏（不是 /reload）后生效。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
