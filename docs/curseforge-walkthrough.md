# CurseForge 创建项目与发布全流程

> 依据：CurseForge 官方作者文档（support.curseforge.com 9000197241 / 9000197242）
> 与 WoW 插件上传实测惯例，2026-10-15 整理。
> 本文件只讲「怎么走」；可直接粘贴的文案在 [publishing.md](publishing.md)。

## 总览：6 步，卡点只有两个

```
① 注册作者账号（普通 CF 账号即可，进 authors.curseforge.com）
② Create Project ── 填 general（你正在这个页面）
③ Description 页 ── 英文正文（Markdown）
④ License 页 ── MIT
⑤ 上传第一个 zip ── ★ 项目不上传文件就永远不会公开 ★
⑥ 等人工审核（几分钟～2 天）→ 通过即上线
      └─ 拿 Project ID（创建后就有）→ 回填 .toc → 以后就能自动化发版
```

两个真正的卡点：
1. **项目必须上传并过审至少一个文件才会公开**——光建项目等于什么都没发。
2. **新文件全部要人工审**——每次发版都要等，急不得。

---

## ② Create Project（general 页）字段逐项

| 字段 | 填什么 | 坑 |
| --- | --- | --- |
| **Project name** | `AutoMountLite` | 已查重，CF 上无同名（有的是 AutoMountFix / AutoMountGear / Auto Mount）。官方要求：名字里**别带类别、版本号或游戏名**——「AutoMountLite」本身合规。重名会被直接拒 |
| **Logo** | ✅ 已生成：`dist/AutoMountLite-logo.png`（512×512，立马头 + 青铜徽章环 + 双侧闪电；生成图右下角带「AI生成」水印，已用 Pillow 裁掉，可直接上传） | 不许：纯色/渐变、游戏 logo、商标素材、NSFW |
| **Summary** | 见下方，一句话 | **必须英文**；这是列表页预览，写清楚"干什么+怎么用" |
| **Class** | `Addons` | WoW 插件固定选这个 |
| **Main category** | `Companions` | WoW 没有独立 "Mounts" 分类；坐骑/宠物都归 Companions（同类插件 Auto Mount 即此类） |
| **Additional categories** | `Miscellaneous`（可选 0–4） | 别为了曝光乱加无关分类，会被退回重填 |
| **Allow Comments** | 勾上 | 早期反馈就靠这个 |
| **Unlisted project** | **不勾** | 勾了只在直连链接可见、搜不到 |
| **Social Links** | `https://github.com/shadapang/wow-addons` | **写 GitHub 不写 CNB**：CF 受众是国际玩家，GitHub 才被认可为「源码仓」，且带 issue 追踪；CNB 仓是自有主仓（`cnb.cool/wuhuarou-2026_799/wow-addons`），作为 backup 路不对 CF 用户展示 |

**Summary（已备好，直接粘）：**
```
Automatically summons your mount when you start moving — lightweight, zero
dependencies, bilingual (English / 简体中文), with a built-in options panel.
```

## ③ Description 页

- 富文本/Markdown，**必须英文**（官方明确：titles and descriptions must be in English）。
- 会被人工审：**语法错误或描述不充分会被退回**，所以直接用 [publishing.md](publishing.md)
  里那段英文正文（已按 CF 风格写好：Features / Commands 表 / Notes / Credits）。
- Credits 段落保留「功能灵感来自 Dugi，独立实现、不含其代码」的措辞——这是规避仿冒投诉的关键。

## ④ License 页

下拉选 **MIT**（仓库根已有 LICENSE，Copyright 2026 wuhuarou）。

## ⑤ Additional Images（截图）

- **插件类不强制**（只有材质包/模拟类强制）。跳过也行。
- 建议通过后补 2–3 张：设置面板全貌、模式/偏好下拉、游戏内自动上坐骑的瞬间。
  上传后每张可配标题和说明。

## ⑥ 上传第一个文件（Files 标签 → Upload file）

| 字段 | 填什么 | 坑 |
| --- | --- | --- |
| **Upload file** | `dist/AutoMountLite-1.4.0.zip` | 必须是**真 .zip**（rar 改名的一律拒），< 2GB |
| **Display Name** | `AutoMountLite v1.4.0` | 显示在文件列表里，建议带版本号 |
| **Release Type** | `Release` | ★ 必须至少一个 Release 文件，项目才会进 CF 客户端和网站默认下载 |
| **Release Options** | 默认（过审后自动上线） | 想定时上线才改 |
| **Changelog** | 见下方，英文 | 每次发版都写，用户只看这个 |
| **Supported Version** | `12.1.0` | 对应 `.toc` 的 `Interface: 120100`；想兼容更早补丁就多勾，但 toc 得跟着改 |
| **Related Projects** | 留空 | 本插件零依赖，没有必填前置 |

**zip 结构硬性要求（不符即拒）：**
```
AutoMountLite.zip
└── AutoMountLite/          ← 顶层必须是插件文件夹本身
    ├── AutoMountLite.toc
    ├── AutoMountLite.lua
    ├── AutoMountLite_Locale.lua
    ├── Bindings.xml
    ├── README.md
    └── LICENSE
```
- ❌ 不要外层再套 `AutoMountLite-1.4.0/` 版本号文件夹（解压后游戏认不出）
- ❌ 不要 `.DS_Store` / `Desktop.ini` / WowMatrix 文件
- ❌ zip 根目录不要直接放文件（必须都在文件夹里）
- ✅ `_tools/package.py` 产出的包已按此结构，自动排除 `.bak`

**Changelog（v1.4.0，直接粘）：**
```
First public release.

- Auto-summon when you start moving, with veto guards (combat, casting,
  mounted, indoors, dead, vehicle, falling, looting, recently dismounted).
- Two modes: Random favorite (C_MountJournal.SummonByID(0), same as the
  Mount Journal button) / Fastest for the current environment.
- Per-environment mount preference (ground / flying / aquatic).
- Bilingual interface: English and Simplified Chinese (auto-follows client
  locale, or set in Options > AddOns > AutoMountLite).
- Built-in options panel, ALT+Z toggle, and diagnostic commands.
```

## ⑥之后：审核

- 提交后文件状态 **Under Review**，人工审，**几分钟到 2 天**，结果邮件 + 站内通知
  （所以 CF 账号的邮箱要填真的）。
- 三种结果：通过（自动上线）/ **Changes Required**（要改）/ **Rejected**（拒，会告诉原因）。
- 超过 48 小时没消息：项目页右下角红色三角形 → Report → "Requires moderator attention"。

## 拿 Project ID（创建后即有，不用等审核）

> ✅ **已完成（2026-10-15）**：项目 `automountlite` 已创建，
> **Project ID = 1746390**（作者后台地址栏 `#/projects/1746390/general` 拿到），
> 已回填 `.toc`（`## X-Curse-Project-ID: 1746390`）并重打发布包、重指 tag v1.4.0（`cec0af1`）。

ID 是建项目时就分配的，三个办法，从最快到最兜底：

1. **作者后台（最快，建完项目就能拿）**：`authors.curseforge.com` → Projects 列表 →
   点进 AutoMountLite → General / Overview 页显示 **Project ID**；
   新面板是单页应用，打开项目后**浏览器地址栏里也带这串数字**（`#/projects/123456/...`），
   抄下来即可。
2. **项目公开页（过审后）**：打开项目页 → 右侧 **About Project** 框 →
   **Project ID**（2026 年 7 月起旁边有 **Copy** 按钮，点一下直接复制）。
3. **legacy 面板兜底**：后台顶部可切回 Legacy dashboard（`authors-old.curseforge.com`），
   项目编辑地址形如 `/project/123456/edit/general`，中间那串数字就是。

拿到后回填 `.toc`：

```
## X-Curse-Project-ID: 123456
```

然后重跑 `python _tools/package.py` + `_tools/deploy.py`，commit + 双路推送 + 打 tag。

> 注意：**手动上传不需要 Project ID**——它只用于自动化发版（`BigWigsMods/packager`
> 靠它认项目）和让客户端识别更新来源。所以拿不到也不影响你先手动发布，
> 拿到后告诉我数字即可，我回填并重打发布包。

## 以后每次发新版（重复第六步）

```
改 .toc 的 ## Version → test_runtime.py 全绿 → check.js → package.py
  → 真机验证 → commit + 双路推送 + tag
    → CF Files 页上传新 zip + changelog + 勾 12.1.0
      → 等审核 → 自动上线（CF 客户端用户几天内陆续收到更新）
```

## 常见退回原因清单（提交前对着过一遍）

- [ ] 项目名与已有项目重复
- [ ] Title/Description 非英文
- [ ] Description 太简陋或有语法问题
- [ ] Logo 是纯色/渐变/游戏图/商标图
- [ ] zip 是 rar 改名、或结构带多余外层文件夹、或根目录有散文件
- [ ] 没有 Release 类型的文件（只有 Alpha/Beta 进不了客户端）
- [ ] 乱加无关分类
- [ ] 描述里出现「复刻 / 官方 / Dugi 版」等仿冒嫌疑措辞
