# AutoMountLite — 自动上坐骑（独立版）

功能灵感来自 Dugi Questing Essential 的「自动上坐骑」模块，本插件为**独立实现，不含 Dugi 的任何代码**。
只调用暴雪官方 API（C_Timer / C_MountJournal），不模拟按键、不注入、不 hook、不联网。

> 涉及的「环境速度权重」设计思路参考自上述模块；Dugi 是第三方插件，与本插件无隶属关系。

## 文件
- AutoMountLite/AutoMountLite.toc —— 插件清单（Interface 120100 = 客户端 12.1.0）
- AutoMountLite/AutoMountLite.lua —— 全部逻辑（单文件）
- AutoMountLite/Bindings.xml —— 快捷键绑定声明（默认 ALT+Z 开/关）。
  **注意：此文件由客户端自动加载，不要写进 .toc**（写进去会被当作普通 UI XML 解析并报错）。

## 安装与「插件列表」显示
1. 把 AutoMountLite 整个文件夹放进 D:\World of Warcraft\_retail_\Interface\AddOns\
   （本机已自动装入该目录）。
2. 完全退出并重启游戏（新插件要重启客户端才会被扫描到，/reload 不够）。
3. 进入游戏后，它会和其它插件一样出现在「插件」列表里（角色选择界面的“插件”面板，
   或游戏内 系统 -> 插件管理）：
   - 有一个勾选框，默认勾选 = 启用。
   - 取消勾选 = 该插件完全不加载（引擎层面，等价于没装）。
   注意区分两层开关：
   - 插件列表勾选：控制 AutoMountLite.lua 是否被引擎加载。
   - /am 命令：控制加载之后是否真的执行“自动召唤”逻辑。
   两层都开（勾选 + /am 开启）时才会自动骑。

## 命令（游戏内输入）
> v1.3.0 起，常用配置都能在**图形设置面板**里点鼠标完成：
> 「选项（Esc）→ 插件 → AutoMountLite」。见下方「可视化设置面板」一节。
> 命令行依然保留，适合快速切换与诊断。

| 命令 | 作用 |
| --- | --- |
| /am | 切换 开 / 关 |
| /am on   /am off | 直接开启 / 关闭 |
| /am status | 查看当前状态与配置（含当前环境） |
| /am favs | 按类型列出收藏坐骑（名称+ID），诊断随机池构成 |
| /am diag | 诊断：星标收藏的当前区域可用性 + 召唤API 自检 + 权重最高候选池 |
| /am delay <0-10> | 施法后延迟秒数（默认 1.0s） |
| /am mode fastest\|random | 从收藏坐骑随机（默认）/ 环境内最快坐骑 |
| /am pref <ground\|flying\|aquatic> auto\|none\|坐骑ID | 指定某环境优先坐骑 |
| /am lang auto\|zhCN\|enUS | 界面语言：跟随客户端 / 简体中文 / English |
| /am reset | 恢复默认 |

## 可视化设置面板（v1.3.0 新增）
在「选项 → 插件」左侧列表里找到 **AutoMountLite**，点进去即可鼠标配置：

| 控件 | 对应设置 |
| --- | --- |
| ☑ 启用自动上坐骑 | 总开关（等同 /am on\|off） |
| 召唤模式（下拉） | 随机召唤偏好坐骑 / 环境内最快坐骑（等同 /am mode） |
| 施法后延迟（滑块 0–10s，步长 0.5） | 等同 /am delay |
| 地面 / 飞行（含御空）/ 水下环境（三个下拉） | 等同 /am pref；可选「自动」「不骑坐骑」或任意一只**已收集**坐骑（收藏的坐骑标 ★） |
| 输出诊断到聊天框（按钮） | 打印状态 + 收藏构成（等同 /am status + /am favs） |
| 打开按键设置（按钮） | 跳到「按键设置 → 插件」改开关键（默认 ALT+Z） |
| 恢复默认设置（按钮） | 原地重置全部选项（等同 /am reset） |

说明：
- 「指定坐骑偏好」**只在 fastest 模式生效**；random 模式走暴雪「随机召唤偏好坐骑」，请在坐骑图鉴里点星星调整收藏。
- 老客户端若没有暴雪 Settings API，插件会自动跳过面板构建（不报错），斜杠命令照常可用。
- 面板基于暴雪官方 `Settings` API（`RegisterVerticalLayoutCategory` / `RegisterAddOnSetting` /
  `RegisterProxySetting` / `CreateCheckbox` / `CreateSlider` / `CreateDropdown`），
  与本机 `MinimapButtonButton`、`GSE` 用的是同一套接口。


## 工作原理（权重思路参考 Dugi，独立实现）
1. 0.5 秒心跳：C_Timer.NewTicker(0.5, ...)，只在开关打开时存在。
2. 时间戳打点：每次心跳刷新 5 个时间戳（战斗 / 非坐骑施法 / 坐骑施法 / 已上坐骑 / 正在移动），
   靠“安静够久”满足阈值。
3. 一票否决守卫：任一命中本次不召唤 ——
   飞行中 / 移动中 / 室内 / 已骑 / 死亡或灵魂 / 宠物对战 / 载具 / 德鲁伊萨满变形 /
   拾取窗 / 施法（含施法条 / 专业界面）/ 战斗中或脱战≤1s / 停移≤0.4s /
   坐骑 CD≤4s / 刚过图≤1s / 施法后延迟内 / 特殊增益（钓鱼筏·吃喝·假死·潜行·Jani）/ 坠落中。
4. 选坐骑（仅 /am mode fastest）：遍历 C_MountJournal.GetMountIDs()，按“环境速度权重”挑最快的一批，
   随机取一个交给 C_MountJournal.SummonByID(id)。
   权重随环境（可推进飞行 / 可飞 / 不可飞 / 水下）变化；同权重下收藏坐骑优先。
   四个环境分支是【独立 if（后者覆盖前者）】，不是 elseif 互斥 —— 与参考模块一致。
5. 贴心细节：拾取框打开且未飞未骑时主动 C_MountJournal.Dismiss() 下坐骑，保证正常拾取。

## 界面语言（v1.4.0 新增）

插件界面支持**简体中文 / English 双语**，三档可选：

| 档位 | 说明 |
| --- | --- |
| **跟随客户端**（默认） | 按 `GetLocale()` 自动判断：简体中文客户端显示中文，英语客户端显示英文；繁体客户端暂复用简体文案 |
| **简体中文** | 强制中文 |
| **English** | 强制英文 |

两种切换方式：

1. **设置面板**：「选项 → 插件 → AutoMountLite → 界面语言」下拉（在最上面）
2. **命令**：`/am lang auto` / `/am lang zhCN` / `/am lang enUS`；不带参数则查看当前语言

覆盖范围：**聊天框全部输出**（status / favs / diag / 提示 / 帮助）、**设置面板的控件标题与说明文字**、
**下拉选项**、**按键设置里的键位描述**。

> ⚠️ 已知限制：切换语言后，设置面板里已建好的**标题文字是静态的**，需要 `/reload` 后刷新；
> 聊天输出、下拉选项、提示都是即时生效的（插件会在切换时提示这一点）。

技术实现：文案集中在 `AutoMountLite_Locale.lua`（两张表，106 条 key），主文件所有面向用户的
文字一律走 `AutoMountLiteLocale.T(key)`；当前语言缺某个 key 时自动回退英文。
离线测试里有 13 项专门校验：两张表 key 必须完全一致、不允许空文案、切换后输出确实变语言、
面板含语言下拉、**主文件运行时不得再有硬编码中文**（防回归）。

## 关于“总是召唤御空（史诗飞行）坐骑”
> 注意：本节只对 **/am mode fastest** 生效。默认的 **random** 模式走暴雪「随机收藏坐骑」，
> 不经过下面的权重表 —— 它只会在你标记为收藏(favorite)的坐骑里随机。

fastest 模式的权重表（思路同参考模块）。注意：四个环境分支是【独立 if，后者覆盖前者】，
不是互斥的 if/elseif —— 若某处同时满足多个条件，**最后一个命中的分支**决定权重
（顺序：史诗飞行 → 可飞 → 不可飞 → 水下）。各分支权重表：
- 史诗飞行分支：御空(advflying)=5 > 飞行(flying)=4 > 地面=3 > 水下=2
- 可飞分支：飞行(flying)=5 > 御空(advflying)=4 > 地面=3
- 不可飞(地面)分支：地面(ground)=5 > 飞行=4 > 御空=3
- 水下分支：水下=5 > 飞行=4 > 地面=3

因此，在“史诗飞行区”（`IsFlyableArea` 与 `IsAdvancedFlyableArea` 同时为真的地方），
实际生效的是【可飞分支】：飞行坐骑(248)=5 高于御空坐骑(402/424)=4，即普通飞行坐骑优先。
（v1.2.0 已按参考模块改回“独立 if”，修正了此前误用 elseif 造成“御空永远最高”的偏差。）

所以你会看到飞行/御空坐骑，通常是这两种原因之一：
1. 你现在站在“可飞/史诗飞行区”——飞行类坐骑权重永远高于地面，这是正确行为。
2. 你的坐骑收藏里飞行/御空坐骑很多，同权重下随机取，命中率就高。

想固定某环境只骑某只坐骑：/am pref <ground|flying|aquatic> <坐骑ID>
想某环境一律不自动骑：/am pref <槽位> none
坐骑 ID 的查法：游戏里输入 /am favs，收藏坐骑的名称后面直接带 (ID:数字)。

## 随机召唤“偏好”坐骑（默认模式）
- **本插件默认就是这个模式**（mode=random）。
- /am mode random 调用的是 **C_MountJournal.SummonByID(0)** —— 与你在坐骑图鉴上
  手动点「随机召唤偏好坐骑」按钮是**同一个调用**。官方文档原文：
  `0 to summon a random favorite mount appropriate to the current area`。
  **它只会召唤你收藏的坐骑**，绝不可能召唤未收藏的坐骑——这是暴雪 API 的语义。
- ⚠️ **v1.2.6 重大修复（真凶）**：v1.1.0~v1.2.5 这里调用的是
  `C_MountJournal.SummonRandomFavoriteMount`，但当前客户端**根本没有这个函数**
  （官方 MountJournal API 函数清单里查无此名）。于是该判断恒为假 →
  random 模式每次都掉到下面的「最快坐骑」权重兜底分支，
  表现为**"random 模式永远只召固定的那几只"**（那几只 = 当前区域权重最高的一类收藏）。
  症状特征：**手动点图鉴按钮能随机出很多只，插件却只出固定的几只**。
  已改用与图鉴按钮完全一致的 `SummonByID(0)`。
- 暴雪这个 API 本身确实会做一次区域过滤：只从「当前区域可用」的收藏里挑
  （法术 150544："需要能够在当前区域使用"）。禁飞区里纯飞行坐骑会被排除——
  但这是暴雪行为，手动点按钮也一样，不会造成"只剩 2 只"。
- 想看清"哪些收藏可用、当前权重最高候选池是哪几只"，输入 `/am diag`：
  它打印 星标收藏数 / 当前区域可用数、**召唤 API 可用性自检**、以及
  **权重最高候选池明细**（后者正是旧版 random 出错时实际在召的那一批）。
- /am favs 按类型列出收藏构成（名称+ID）。
- 处置路径（想改变随机结果）：
  1. 去坐骑图鉴把不想随机到的坐骑取消收藏（点掉的星星），随机池就变了；
  2. 切到 /am mode fastest，用 /am pref flying none（或指定坐骑ID）精确控制。
- 注意：**/am pref 偏好设置只在 fastest 模式生效**，random 模式不走权重表。
- 如果想“在某环境的最快坐骑里随机”（保持最快、但不固定同一只），切到 /am mode fastest 即可——
  它本来就会在“最快一批（同权重）”里随机取一个。

## 与参考模块（Dugi）的差异
- 去掉对 Dugi 向导（GuideOn()）的依赖——本插件独立常驻、随登录即生效。
- 开关 / 延迟 / 模式 / 优先坐骑改为本插件自己的存档 AutoMountLiteDB。
- 默认开启（装了就干活）；想静默用 /am off。
- 默认模式改为 random（从收藏坐骑里随机召唤，= 暴雪「随机偏好坐骑」）；
  想要参考模块的「环境内最快」行为，用 /am mode fastest。

## 常见配置示例

**只召唤某一只坐骑（以奥的灰烬为例，mountID=183）：**

```
/am mode fastest        ← 必须先切（random 模式 pref 无效，插件会提示）
/am pref flying 183     ← 御空区、可飞区都只召它（flying 偏好同时覆盖两种飞行环境）
```

说明：
- 该坐骑在**当前环境不可用**时不会召（如飞行坐骑在不可飞区权重输给地面坐骑）。
  要"绝对只召它"（宁可不骑），追加 `/am pref ground none` + `/am pref aquatic none`。
- `/am pref <槽位> auto` 恢复自动选择；`/am reset` 恢复全部默认。

## 注意
- 若你仍在用 Dugi 自带的自动上坐骑，建议只留一个，避免重复召唤
  （Dugi 侧：/dugi automountoff）。
- 本插件只能静态编写，无法替你进游戏实测；如报错请把 BugSack 的报错原文发来。

## 版本记录
- **v1.4.0**：新增**中英双语界面**（简体中文 / English，默认跟随客户端，`/am lang` 或面板下拉切换）。
  文案集中到 `AutoMountLite_Locale.lua`（两张表 106 条 key），聊天输出、设置面板、下拉选项、
  键位描述全部走 `T()` 取文案；缺 key 自动回退英文。离线测试新增 13 项 i18n 校验
  （两表 key 一致、无空文案、切换生效、无硬编码中文回归）。
  ⚠️ 已知限制：切换语言后设置面板的标题文字需 `/reload` 刷新（其余即时生效）。
- **v1.3.0**：新增**可视化设置面板**，正式接入暴雪 `Settings` API——插件配置出现在
  「选项 → 插件 → AutoMountLite」，鼠标即可完成开关 / 模式 / 施法后延迟 / 各环境指定坐骑 /
  恢复默认 / 一键诊断。（`/am reset` 同时改为**原地重置**存档表，否则面板绑定的是旧表、
  重置后设置会写不进去。老客户端无 Settings API 时自动跳过面板，命令照常可用。）
- **v1.2.7**：修正 `UnitCastingInfo` 的返回值取位——`castingSpellID` 在现代客户端是
  **第 9 个**返回值（8.0 后移除了 nameSubtext），旧代码写死 `select(10)` 取到的是
  `castBarID`。后果：IsCastingMountSpell() 恒 false（"上坐骑 4 秒防抖"失效）、
  IsCastingNonMountSpell() 对任何施法都返回 true。已改为按类型判断（先试第 9、再退第 10）。
- **v1.2.6**：**【重大修复】** random 模式召唤 API 名写错——旧版调用
  `C_MountJournal.SummonRandomFavoriteMount`（当前客户端不存在，判断恒假），
  导致 random 模式每次都掉进「最快坐骑」权重兜底分支，
  症状为"random 模式永远只召固定那几只"。改用与坐骑图鉴按钮完全一致的
  `C_MountJournal.SummonByID(0)`（pcall 保护 + 二级兜底）。
  /am diag 增加召唤 API 可用性自检与权重最高候选池明细。
- **v1.2.5**：新增 /am diag（诊断星标收藏在当前区域的可用性，可用/不可用分组，解释"只召某几只"）。
- **v1.2.3**：重写坐骑类型映射表——402 与 424 均为御空（Dragonriding/Skyriding），
  248 为普通飞行；补齐 225/229/238/263/269/284/398/407/408/412/426/428/429/436/437/444/445
  等现代类型ID（依据 warcraft.wiki.gg API 文档 + MountJournalEnhanced 的 MountType DB2 映射）。
  修复 v1.2.2 及以前沿用参考模块（Dugi）旧表导致 424 等新御空坐骑全部落入"其它"、
  /am favs 显示"御空 0 只"与事实不符的问题。/am favs 增加未识别类型ID原始值显示；
  /am status 环境行文案更正（史诗飞行区是御空坐骑权重最高）。
- **v1.2.4**：/am pref 在 random 模式下设置时追加提示"偏好设置只在 fastest 模式生效；
  当前是 random 模式，输入 /am mode fastest 切换"（random 走暴雪随机收藏，pref 权重表不参与）。
- **v1.2.2**：新增 /am favs（按类型列出收藏坐骑，名称+ID）；/am status 增加当前环境行。
- **v1.2.1**：Bindings.xml 移出 .toc（客户端按文件名自动加载，写进 toc 会报
  Unrecognized XML: Binding）；header= 改为 category=；快捷键自愈逻辑改为每次登录核对实际绑定状态。
- **v1.2.0**：快捷键改为「插件」具名绑定 AUTOMOUNTLITE_TOGGLE（可在按键设置里修改）；
  GetTheFastestMount 去掉多余返回值。（该版引入两处回归，已在 v1.2.1 修复）
- **v1.1.0**：新增 ALT+Z 快捷键开关（Bindings.xml + 隐藏按钮）；random 模式不再被
  “没有收藏”拦截。
- **v1.0**：功能参考 Dugi Questing Essential 的自动上坐骑，独立实现核心逻辑（四张环境权重表 +
  isFavorite +0.1 + 一票否决守卫 + 0.5s 心跳）。

## 开发自测（离线仿真）
_tools/test_runtime.py 用 Python mock 整套魔兽 API、把本插件载入 Lua 虚拟机真跑，
覆盖 /am favs、四种环境选坐骑、权重表、pref 行为、快捷键绑定与自愈迁移、424 新御空类型
回归、未识别类型ID自诊断，以及 v1.3.0 设置面板的注册签名与偏好读写映射
（共 **114 项检查**）。
运行方式：
```
$env:PYTHONPATH = "C:\Users\Administrator\.workbuddy\binaries\python\envs\default\Lib\site-packages"
& "C:\Users\Administrator\.workbuddy-ai\binaries\python\versions\3.13.12\python.exe" _tools\test_runtime.py
```
另有 _tools/check.js 做 luaparse 语法检查（期望输出 SYNTAX_OK）。
