#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""wow-addons 一键发版脚本。

链路：预检 -> 仿真测试 -> Lua 语法检查 -> 打包 -> git 提交/tag/双路推送
      -> GitHub Release（建 Release + 传 zip 附件）
      -> [可选] CurseForge 上传（需 CF_API_TOKEN）

用法：
    python _tools/release.py                    # 按 toc 里的版本号发版
    python _tools/release.py --version 1.5.0    # 先把 toc 版本号改成 1.5.0 再发
    python _tools/release.py --dry-run          # 只做 预检+测试+打包，不碰任何远端
    CF_API_TOKEN=xxx python _tools/release.py --cf          # 附带上传 CurseForge
    CF_API_TOKEN=xxx python _tools/release.py --cf --cf-game-version 12.1.0

GitHub 令牌来源（按优先级）：
    1. 环境变量 GITHUB_TOKEN
    2. ~/.git-credentials 里 github.com 的 password 字段（本机已配置，权限 gist/repo/workflow）

CurseForge 令牌来源：环境变量 CF_API_TOKEN
   （在 authors-old.curseforge.com/account/api-tokens 生成，权限需含 projects:write）
    ⚠️ 该分支在拿到令牌前未经真机实测，首次使用请用 --dry-run 之外的步骤逐步核对。

设计约束（与本仓 SOP 一致）：
    - 版本号唯一来源是 .toc 的 ## Version，不在别处维护
    - 测试不绿就中止，不发版
    - zip 顶层必须是 <插件名>/（package.py 保证）
    - 双路冗余：origin=CNB，backup=本地裸仓 E:/repos/wow-addons.git
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ADDON = "AutoMountLite"
TOC = os.path.join(ROOT, "addons", ADDON, ADDON + ".toc")
DIST = os.path.join(ROOT, "dist")
GITHUB_REPO = "shadapang/wow-addons"
CF_PROJECT_ID = "1746390"
CF_UPLOAD_URL = "https://wow.curseforge.com/api/projects/%s/upload-file" % CF_PROJECT_ID
CF_VERSIONS_URL = "https://wow.curseforge.com/api/game/versions"

# subprocess 在 Windows 上不认 Git Bash 的 /c/ 路径，必须用 Windows 路径
GIT = "C:/Program Files/Git/cmd/git.exe"
if not os.path.exists(GIT):
    GIT = "git"
NODE = shutil.which("node") or r"C:\Users\Administrator\.workbuddy\binaries\node\versions\22.12.0\node.exe"
PYTHON = os.environ.get("RELEASE_PYTHON") or sys.executable


# ---------------------------------------------------------------- 基础工具

def log(msg):
    print(msg, flush=True)


def run(cmd, cwd=ROOT, check=True, env=None):
    e = dict(os.environ)
    e["GIT_TERMINAL_PROMPT"] = "0"
    if env:
        e.update(env)
    log("  $ %s" % " ".join(cmd))
    p = subprocess.run(cmd, cwd=cwd, env=e, capture_output=True, text=True)
    if check and p.returncode != 0:
        log(p.stdout)
        log(p.stderr)
        raise SystemExit("命令失败（exit=%d）：%s" % (p.returncode, " ".join(cmd)))
    return p


def die(msg):
    raise SystemExit("中止：%s" % msg)


def read_toc_version():
    with open(TOC, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^##\s*Version:\s*(\S+)", line)
            if m:
                return m.group(1)
    die("toc 里找不到 ## Version")


def bump_toc_version(new):
    with open(TOC, encoding="utf-8") as f:
        src = f.read()
    out, n = re.subn(r"(?m)^##\s*Version:\s*\S+", "## Version: %s" % new, src, count=1)
    if n != 1:
        die("toc 版本号替换失败")
    with open(TOC, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)


def github_token():
    tok = os.environ.get("GITHUB_TOKEN")
    if tok:
        return tok
    cred = os.path.expanduser("~/.git-credentials")
    if os.path.exists(cred):
        with open(cred, encoding="utf-8", errors="ignore") as f:
            for line in f:
                if "github.com" in line:
                    m = re.search(r"://[^:]+:([^@]+)@", line)
                    if m:
                        return m.group(1)
    die("拿不到 GitHub 令牌（设 GITHUB_TOKEN 或在 ~/.git-credentials 配 github.com）")


def http_json(url, token, method="GET", payload=None, timeout=90):
    headers = {"Authorization": "Bearer %s" % token, "Accept": "application/vnd.github+json"}
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read()
            return r.status, (json.loads(body.decode("utf-8")) if body else {})
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode("utf-8", "ignore") or "{}")


def http_upload(url, token, file_path, name, ctype, timeout=300):
    """二进制上传（GitHub assets / CurseForge upload-file 都用 multipart）。"""
    with open(file_path, "rb") as f:
        blob = f.read()
    boundary = "----wowaddons%s" % re.sub(r"\D", "", str(os.path.getsize(file_path)))
    parts = []
    parts.append(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n"
                  "Content-Type: %s\r\n\r\n" % (boundary, name, ctype)).encode("utf-8"))
    parts.append(blob)
    parts.append(("\r\n--%s--\r\n" % boundary).encode("utf-8"))
    body = b"".join(parts)
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Authorization": "Bearer %s" % token,
        "Content-Type": "multipart/form-data; boundary=%s" % boundary,
        "Content-Length": str(len(body)),
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode("utf-8", "ignore") or "{}")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "ignore")[:500]


# ---------------------------------------------------------------- 各步骤

def step_preflight():
    log("\n[1/6] 预检")
    st = run([GIT, "status", "--porcelain"]).stdout.strip()
    if st:
        log("  工作区有未提交改动（将随发版一起提交）：\n%s" % st)
    remotes = run([GIT, "remote", "-v"]).stdout
    for r in ("origin", "backup"):
        if "\n%s\t" % r not in "\n" + remotes and not remotes.startswith(r + "\t"):
            if not re.search(r"(?m)^%s\t" % r, remotes):
                die("缺少远端 %s（origin=CNB, backup=本地裸仓）" % r)
    log("  远端 origin / backup 均在位")


def step_tests():
    log("\n[2/6] 仿真测试（不绿即中止）")
    env = {"PYTHONPATH": os.path.join(os.path.expanduser("~"), ".workbuddy", "binaries",
                                      "python", "envs", "default", "Lib", "site-packages")}
    p = run([PYTHON, os.path.join("_tools", "test_runtime.py")], check=False, env=env)
    if p.returncode != 0 or "0 失败" not in p.stdout:
        log(p.stdout[-3000:])
        die("仿真测试未通过，终止发版")
    m = re.search(r"====\s*(\d+) 项检查.*?(\d+) 通过.*?(\d+) 失败", p.stdout, re.S)
    log("  测试 %s 项，%s 通过，%s 失败" % (m.group(1), m.group(2), m.group(3)) if m else "  测试通过")


def step_syntax():
    log("\n[3/6] Lua 语法检查")
    for f in (ADDON + ".lua", ADDON + "_Locale.lua"):
        p = run([NODE, os.path.join("_tools", "check.js"),
                 os.path.join("addons", ADDON, f)], check=False)
        if "SYNTAX_OK" not in p.stdout:
            log(p.stdout + p.stderr)
            die("%s 语法检查未通过" % f)
    log("  两个 lua 文件 SYNTAX_OK")


def step_package():
    log("\n[4/6] 打发布包")
    run([PYTHON, os.path.join("_tools", "package.py")])
    zip_path = os.path.join(DIST, "%s-%s.zip" % (ADDON, VERSION))
    if not os.path.exists(zip_path):
        die("打包后找不到 %s" % zip_path)
    log("  发布包：%s（%d bytes）" % (zip_path, os.path.getsize(zip_path)))
    return zip_path


def step_git(version, zip_path):
    log("\n[5/6] git 提交 / 打 tag / 双路推送")
    tag = "v%s" % version
    head = run([GIT, "rev-parse", "HEAD"]).stdout.strip()
    # 已暂存的改动才提交；toc 版本号若刚被改过会一起进来
    run([GIT, "add", "-A"])
    if run([GIT, "diff", "--cached", "--quiet"], check=False).returncode != 0:
        msg = "release: %s %s" % (ADDON, version)
        p = subprocess.run([GIT, "commit", "-m", msg], cwd=ROOT, capture_output=True, text=True,
                           env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
        if p.returncode != 0:
            log(p.stdout + p.stderr)
            die("git commit 失败")
        log("  已提交：%s" % msg)
    else:
        log("  无待提交改动")
    # tag 已存在且指向 HEAD 就不重建（避免改了 tagger 时间导致 sha 漂移）
    tag_sha = run([GIT, "rev-parse", "%s^{}" % tag], check=False).stdout.strip()
    if tag_sha == head:
        log("  tag %s 已指向 HEAD，沿用" % tag)
    else:
        run([GIT, "tag", "-f", "-a", tag, "-m", "%s %s" % (ADDON, version)])
        log("  tag %s -> %s" % (tag, run([GIT, "rev-parse", "--short", "HEAD"]).stdout.strip()))
    run([GIT, "push", "origin", "main"])
    run([GIT, "push", "backup", "main"])
    # tag：远端没有才推（避免无谓 force）
    remote_tags = run([GIT, "ls-remote", "origin", "refs/tags/%s" % tag], check=False).stdout.strip()
    if remote_tags:
        log("  远端已有 %s" % tag)
    else:
        run([GIT, "push", "origin", tag])
    run([GIT, "push", "backup", tag])
    fork = run([GIT, "rev-list", "--left-right", "--count", "backup/main...origin/main"]).stdout.strip()
    log("  两路分叉（backup/origin）：%s" % fork)


def release_body(version):
    return """## %s v%s

Auto-summon your mount when you start moving - lightweight, zero dependencies,
bilingual interface (English / 简体中文), built-in options panel.

- **Bilingual UI** - follows your client locale, or force 简体中文 / English in
  Options -> AddOns -> %s (or `/am lang`). Chat output, panel labels, dropdowns
  and key-binding descriptions are all localized.
- **Options panel** - Blizzard Settings API: summon mode, per-environment mount
  preference, post-spell delay, one-click diagnostics.
- Only official Blizzard APIs - no key simulation, no hooking, no injection.

### Install

Extract into `World of Warcraft/_retail_/Interface/AddOns/` - the zip top-level
folder is already `%s/`.

Also on CurseForge: https://www.curseforge.com/wow/addons/automountlite

MIT licensed. Source: https://github.com/%s
""" % (ADDON, version, ADDON, ADDON, GITHUB_REPO)


def step_github(version, zip_path):
    log("\n[6/6] GitHub Release")
    tok = github_token()
    tag = "v%s" % version
    name = os.path.basename(zip_path)
    code, rel = http_json("https://api.github.com/repos/%s/releases/tags/%s" % (GITHUB_REPO, tag), tok)
    if code == 200:
        log("  Release 已存在：%s" % rel.get("html_url"))
    else:
        code, rel = http_json("https://api.github.com/repos/%s/releases" % GITHUB_REPO, tok,
                              method="POST", payload={
                                  "tag_name": tag, "target_commitish": "main",
                                  "name": "v%s - %s %s" % (version, ADDON, version),
                                  "body": release_body(version),
                                  "draft": False, "prerelease": False})
        if code != 201:
            die("创建 Release 失败（%d）：%s" % (code, rel))
        log("  Release 已创建：%s" % rel.get("html_url"))
    # 同名附件先删后传，保证内容最新
    for a in rel.get("assets", []):
        if a.get("name") == name:
            c, _ = http_json(a["url"], tok, method="DELETE")
            log("  删除旧附件 %s（%d）" % (name, c))
    up = rel["upload_url"].split("{")[0]
    code, asset = http_upload(up, tok, zip_path, name, "application/zip")
    if code not in (201, 200):
        die("上传附件失败（%d）：%s" % (code, asset))
    log("  附件已传：%s（%s bytes）\n  直链：%s" % (
        asset.get("name"), asset.get("size"), asset.get("browser_download_url")))


def step_curseforge(version, zip_path, game_version):
    log("\n[附] CurseForge 上传")
    tok = os.environ.get("CF_API_TOKEN")
    if not tok:
        die("未设 CF_API_TOKEN，跳过 CF 上传（去 authors-old.curseforge.com/account/api-tokens 生成）")
    # 解析 gameVersionTypeId（WoW 的版本 ID 与 Interface 号不同，必须查 API）
    code, versions = http_json(CF_VERSIONS_URL, tok)
    if code != 200:
        die("查 CF 版本列表失败（%d）：%s" % (code, versions))
    want = []
    for v in versions:
        nm = str(v.get("name", ""))
        if nm.startswith(game_version) or nm == game_version:
            want.append(v.get("id"))
    if not want:
        die("CF 版本列表里找不到 %s（可用 --cf-game-version 指定，或在项目页看版本名）" % game_version)
    log("  gameVersionTypeIds: %s" % want)
    fields = {
        "changelog": "v%s: bilingual UI, options panel, random-favorite summon fix." % version,
        "displayName": "%s %s" % (ADDON, version),
        "gameVersions": want,
        "releaseType": "release",
    }
    code, resp = http_upload_multipart_cf(CF_UPLOAD_URL, tok, zip_path, fields)
    if code not in (200, 201, 202):
        die("CF 上传失败（%d）：%s" % (code, resp))
    log("  CF 上传成功：%s" % resp)


def http_upload_multipart_cf(url, token, file_path, fields):
    """CurseForge upload-file：metadata(JSON) + file 两个 multipart 字段。"""
    with open(file_path, "rb") as f:
        blob = f.read()
    boundary = "----cf%s" % re.sub(r"\D", "", str(len(blob)))
    parts = [("--%s\r\nContent-Disposition: form-data; name=\"metadata\"\r\n"
              "Content-Type: application/json\r\n\r\n%s\r\n"
              % (boundary, json.dumps(fields))).encode("utf-8"),
             ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n"
              "Content-Type: application/zip\r\n\r\n" % (boundary, os.path.basename(file_path))).encode("utf-8"),
             blob,
             ("\r\n--%s--\r\n" % boundary).encode("utf-8")]
    body = b"".join(parts)
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Authorization": "Bearer %s" % token,
        "Content-Type": "multipart/form-data; boundary=%s" % boundary,
        "Content-Length": str(len(body)),
    })
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return r.status, r.read().decode("utf-8", "ignore")[:300]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "ignore")[:500]


# ---------------------------------------------------------------- 主流程

VERSION = None


def main():
    global VERSION
    ap = argparse.ArgumentParser(description="wow-addons 一键发版")
    ap.add_argument("--version", help="先把 toc 版本号改成这个再发版")
    ap.add_argument("--dry-run", action="store_true", help="只做 预检+测试+打包，不碰远端")
    ap.add_argument("--skip-tests", action="store_true", help="跳过测试（不推荐）")
    ap.add_argument("--cf", action="store_true", help="附带上传 CurseForge（需 CF_API_TOKEN）")
    ap.add_argument("--cf-game-version", default="12.1.0", help="CF 上的游戏版本名，默认 12.1.0")
    args = ap.parse_args()

    VERSION = read_toc_version()
    if args.version:
        if args.version == VERSION:
            log("toc 版本号已是 %s" % VERSION)
        else:
            bump_toc_version(args.version)
            VERSION = args.version
            log("toc 版本号 -> %s" % VERSION)

    step_preflight()
    if not args.skip_tests:
        step_tests()
    step_syntax()
    zip_path = step_package()
    if args.dry_run:
        log("\n--dry-run：到此为止，未推送、未发 Release。发布包：%s" % zip_path)
        return
    step_git(VERSION, zip_path)
    step_github(VERSION, zip_path)
    if args.cf:
        step_curseforge(VERSION, zip_path, args.cf_game_version)
    else:
        log("\n（未加 --cf，跳过 CurseForge 上传；需要时：CF_API_TOKEN=xxx python _tools/release.py --cf）")
    log("\n完成：v%s 已双路推送 + GitHub Release 发布" % VERSION)


if __name__ == "__main__":
    main()
