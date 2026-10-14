# 发布指南（CurseForge / Wago）

> 状态：2026-10-14 查证。渠道选择结论：**CurseForge 为主，Wago 顺手加**。

## 进度看板（2026-10-15 更新）

| 渠道 / 事项 | 状态 | 阻塞原因 | 下一步 |
| --- | --- | --- | --- |
| CNB Release v1.3.0 | ✅ 已发布 | — | ⚠️ 附件是**旧包**（3 文件、无 LICENSE、toc 含旧措辞），需在 Release 页重新上传 `dist/AutoMountLite-1.3.0.zip` |
| CNB → GitHub 镜像 | ✅ 已配（`.cnb.yml` → `github.com/shadapang/wow-addons`） | — | 自动发布（方案 A）的前置已就绪 |
| CurseForge | ❌ 未开始 | 需注册作者账号（我无法代办） | 用下方表单 + `dist/AutoMountLite-1.3.0.zip` 上传 |
| Wago.io | ❌ 未开始 | 需账号 | 同一份 zip，描述复用英文版 |
| NGA 发帖 | 📝 文案已写好 | 需账号发帖 | 见 [nga-post.md](nga-post.md)，可直接粘贴 |
| `.toc` 的 Project ID | ❌ 待回填 | 需先有 CF/Wago 项目 | 拿到 ID 后填 `X-Curse-Project-ID` / `X-Wago-ID` |

> ⚠️ **已知限制（实测）**：`cnb` CLI 有 `releases`（13 tools）和 `assets`（4 tools）模块，
> 但**都不能上传 Release 附件**——`post-release` 无文件参数，`assets` 只有 delete/list。
> 直接调 API（`/v1/repos/.../releases/{id}/assets` 等多种路径）均返回 404。
> **结论：Release 附件只能在网页上传。**
> 国服不用单独找平台——黑盒工坊、网易有爱等国服插件客户端的内容都从 CurseForge 同步，
> 发一处即覆盖全球 + 国服。NGA 属于「发帖引流」不是托管渠道，发布后去发个介绍贴带链接即可。
> WoWInterface 老牌但流量小，可略。

## 一、发布前的硬性检查（每次发版都要走）

```bash
# 1. 离线仿真必须全绿（改了逻辑就要有对应新测试）
PYTHONPATH="<venv>/Lib/site-packages" python _tools/test_runtime.py
# 2. Lua 语法检查
node _tools/check.js addons/AutoMountLite/AutoMountLite.lua     # 期望 SYNTAX_OK
# 3. 打发布包（自动排除 .bak，版本号从 .toc 读）
python _tools/package.py
# 4. 真机验证：装进游戏跑一遍（自动化测不出客户端差异）
python _tools/deploy.py
```

**版本号必须先在 `.toc` 里改**（`## Version: x.y.z`），`package.py` 和文件名都从它读，
不要另外维护一份。

## 二、CurseForge 表单（可直接粘贴）

### 项目名
```
AutoMountLite
```

### Summary（一句话，会显示在列表页）
```
Automatically summons your mount when you start moving — lightweight, zero dependencies, with a built-in options panel.
```

### Description（英文正文，CurseForge 主站用）

````markdown
## AutoMountLite — Auto-Summon Your Mount

A tiny, dependency-free addon that summons your mount automatically when you
start moving and you're not doing anything else. Configuration lives in
**Options → AddOns → AutoMountLite** — no slash commands required.

### Features

- **Auto-summon on the move.** A 0.5s heartbeat checks a set of veto guards
  (in combat, casting, mounted, indoors, dead, in a vehicle, falling, looting,
  recently dismounted, ...) and only acts when you're actually idle-free.
- **Two summon modes.**
  - *Random favorite* (default): calls `C_MountJournal.SummonByID(0)` — the exact
    same call as the "Summon Random Favorite Mount" button in your Mount Journal.
    It only ever summons mounts **you** have marked as favorite.
  - *Fastest for the zone*: picks the fastest mount for the current environment
    (ground / flying / advanced flying / underwater) using a speed-weight table.
- **Per-environment mount preference.** Force a specific mount (or "none") for
  ground, flying and underwater separately.
- **Configurable delay** after spellcasting (0–10s, default 1.0s).
- **Built-in options panel** (Blizzard `Settings` API) and diagnostic commands.
- **ALT+Z** toggles the addon (rebindable in Key Bindings → AddOns).

### Commands

| Command | Effect |
| --- | --- |
| `/am` | Toggle on / off |
| `/am status` | Current state, config and detected environment |
| `/am favs` | List your favorite mounts grouped by type (with IDs) |
| `/am diag` | Diagnostics: zone availability, summon-API self-check, top-weight pool |
| `/am mode random\|fastest` | Switch summon mode |
| `/am delay <0-10>` | Delay after spellcasting |
| `/am pref <ground\|flying\|aquatic> auto\|none\|<mountID>` | Per-environment preference |
| `/am reset` | Restore defaults |

### Notes

- Only official Blizzard APIs are used (`C_Timer`, `C_MountJournal`). No key
  simulation, no hooking, no injection, no network calls.
- If you've marked no mounts as favorite, *Random favorite* mode has nothing to
  pick from — use the Mount Journal stars, or switch to `/am mode fastest`.
- The mount-type mapping is maintained for current mount type IDs
  (402/424 = advanced flying, 248 = flying, ...). See the repo for details.

### Credits

Functionality inspired by the auto-summon module of *Dugi Questing Essential*;
this addon is an independent implementation and contains none of its code.
Dugi is a third-party addon with no affiliation to this project.

MIT licensed. Source: https://cnb.cool/wuhuarou-2026_799/wow-addons
````

### Description（中文版，用于 NGA / 国服社区发帖）

````markdown
## AutoMountLite —— 自动上坐骑

零依赖小插件：你一动、且没在干别的事，就自动上坐骑。
配置在「选项 → 插件 → AutoMountLite」里鼠标点，不用记命令。

**功能**
- 0.5 秒心跳 + 一票否决守卫：战斗中 / 施法中 / 已骑乘 / 室内 / 死亡 / 载具 /
  坠落 / 拾取窗 / 刚下坐骑 等任一命中就不召唤。
- 两种模式：
  - *随机偏好*（默认）：调用 `C_MountJournal.SummonByID(0)`，和你在坐骑图鉴里
    点「随机召唤偏好坐骑」是同一个调用，**只会召唤你标了星星的坐骑**。
  - *环境内最快*：按当前环境（地面 / 飞行 / 御空 / 水下）的速度权重挑最快的一批随机取。
- 可按环境指定坐骑（地面 / 飞行 / 水下分别设置），也可设成「不骑」。
- 施法后延迟可调（0–10 秒，默认 1.0 秒）。
- 自带图形设置面板 + `/am diag` 诊断命令。
- ALT+Z 开关（可在「按键设置 → 插件」改）。

**只调用暴雪官方 API**，不模拟按键、不注入、不 hook、不联网。

功能灵感来自 Dugi Questing Essential 的自动上坐骑模块，本插件为独立实现，
不含其任何代码。MIT 开源。
源码：https://cnb.cool/wuhuarou-2026_799/wow-addons
````

### 其它字段

| 字段 | 值 |
| --- | --- |
| Category | Mounts & Companions |
| License | MIT |
| Game Version | 12.1.0（`Interface: 120100`，与 `.toc` 一致） |
| 附件 | `dist/AutoMountLite-<version>.zip` |
| 截图 | 设置面板截图（选项 → 插件 → AutoMountLite） |

### 拿到 Project ID 之后

注册并建好项目后，把 ID 回填到 `.toc`（自动化打包靠它认项目）：

```
## X-Curse-Project-ID: 123456
## X-Wago-ID: abcdefgh
```

## 三、Wago.io

建项目 → 上传同一个 zip → 描述可复用英文版。Wago 对作者有 HTTP API
（一个 POST 就能发版），后续可自动化。

## 四、发版流程（SOP）

```
改代码
  └─ test_runtime.py 加/改测试（先让它变红，再改代码变绿）
       └─ 改 .toc 的 ## Version
            └─ 语法检查 + 仿真测试 + package.py
                 └─ 真机验证（deploy.py + 进游戏跑）
                      └─ git commit → 双路推送（origin=CNB, backup=本地裸仓）
                           └─ git tag vX.Y.Z → 推 tag
                                └─ 上传 zip 到 CurseForge / Wago
                                     └─ CNB 上基于该 tag 发 Release（附 zip）
```

## 五、自动化发布（可选，等有用户再做）

行业标准 `BigWigsMods/packager`（推 tag → 自动发 CF + WoWInterface + Wago +
GitHub Releases）。它围绕 GitHub Actions 设计，本仓在 CNB，三条路：

- **A** 镜像到 GitHub + Actions（一次配置长期省事）
- **B** 在 CNB 的 `.cnb.yml` 里跑（CI 装 perl 即可）
- **C** 手动打包上传（5 分钟，零维护）← 现阶段推荐

插件还没用户时先搭 CI 是纯投入，建议手动发几次再决定。

## 六、合规红线

1. **描述里不许写「复刻 / Dugi 版 / 官方分支」**——功能复刻不侵权，但措辞会被
   当成仿冒而招投诉。统一用「功能灵感来自 / 独立实现 / 不含其代码」。
2. 不引用暴雪未公开的 API、不打包任何第三方代码。
3. 12.x「至暗之夜」的新规主要卡**战斗数据**（secrets 机制）。本插件只用坐骑与
   `C_Timer` API，不受影响——已在 12.1.0 客户端实测跑通。
