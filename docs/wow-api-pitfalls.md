# WoW API 踩坑记录

每个坑都是「代码看着完全正确，但游戏里就是不work」的那类问题。
**不要凭记忆写 API 名字和参数位置，先查本机已装插件的源码或官方 wiki。**

---

## 1. `C_MountJournal.SummonRandomFavoriteMount` 根本不存在

**现象**：随机模式永远只召唤固定的 2 只坐骑，用户手动点图鉴的「随机召唤偏好坐骑」
按钮却能出各种坐骑。

**真凶**：代码里写了 `C_MountJournal.SummonRandomFavoriteMount()`。这个函数
**在客户端里不存在**，调用恒为 nil 报错，被 `if` 挡掉后一路 fallback 到自己的权重
分支，而权重池在「可飞 + 可御空」区域只剩 2 只符合条件的收藏 → 永远是这 2 只。

**正确写法**：随机召唤偏好坐骑用的是 `C_MountJournal.SummonByID(0)`，
传 0 就是图鉴那个「随机偏好」按钮的行为。

```lua
C_MountJournal.SummonByID(0)   -- 随机召唤一只偏好坐骑
C_MountJournal.SummonByID(id)  -- 召唤指定 mountID
```

**教训**：
- 怀疑「暴雪按区域过滤了收藏」之前，先确认自己调的 API 真的存在。
- API 不存在不会报明显错误，只会静默走 fallback，极难发现。

---

## 2. `UnitCastingInfo` 的 spellID 是第 9 个返回值，不是第 10 个

**现象**：施法结束后的延迟防抖时灵时不灵，有时刚放完技能就立刻上坐骑把技能打断。

**真凶**：用 `select(10, UnitCastingInfo("player"))` 取 spellID，取到的是
`castBarID`，恒不为目标值 → 判断「是否在施法」永远为假。

**正确写法**：8.0 之后返回值前移，spellID 在第 9 位。兼容写法是按类型探测：

```lua
local function CastingSpellID()
    local id = select(9, UnitCastingInfo("player"))
    if type(id) ~= "number" then
        id = select(10, UnitCastingInfo("player"))
    end
    if type(id) ~= "number" then return nil end
    return id
end
```

---

## 3. `Bindings.xml` 由客户端自动加载，不能写进 `.toc`

**现象**：进游戏报错，快捷键不生效。

**真凶**：把 `Bindings.xml` 写进了 `.toc` 的文件列表。客户端会**自动**加载插件目录下
的 `Bindings.xml`，写进 toc 会被当成普通 UI XML 解析，语法不同 → 报错。

另外 `<Binding>` 标签的正文是 **Lua 代码**，不是按键名。按键名用 `category=`，
实际的 key 绑定写在 `bindings-cache.wtf` 里（由玩家在按键设置里改，或手动加一行
`bind ALT-Z AUTOMOUNTLITE_TOGGLE`）。

---

## 4. 测试环境的「假绿」：mock 里实现了不存在的 API

**现象**：离线测试全绿，真实游戏里功能完全没有。

**真凶**：为了让测试通过，在 Python mock 里顺手实现了
`SummonRandomFavoriteMount`。这样测试当然通过——但真实客户端没这函数。

**规则**：mock 必须严格按真实 API 实现。**不确定的 API 一律不要在 mock 里补**，
让 `obj.Foo` 返回 nil，这样测试会立刻暴露问题。

配套做法：改完 bug 后做**变异测试**——故意把代码改回错误版本，确认测试变红，
再改回来确认变绿。测试不会变红的测试，等于没有测试。

---

## 5. `C_MountJournal` 里「收藏」和「夹子」是两套数据

- `isFavorite`（`GetMountInfoByID` 的第 7 个返回值）= 图鉴里的**星标收藏**
- Dugi / MJE 之类的「收藏夹」是插件自己的 SavedVariables 数据

两者互不相干。本插件用的是星标收藏。

---

## 6. 坐骑类型 ID 要持续维护，不能只写几个老 ID

`GetMountInfoExtraByID` 返回的 `mountTypeID` 决定坐骑能不能飞、能不能御空。
常见的几个：

| mountTypeID | 含义 |
| --- | --- |
| 230 / 231 / 241 / 269 / 284 | 地面 |
| 247 / 248 | 普通飞行 |
| 254 / 407 / 412 / 424 | 水下 / 水面 |
| **402 / 424** | 御空（Dragonriding） |

**注意 424 既是御空也可能被归到水类**，判断顺序很重要。遇到未识别的类型，
把原始 ID 打出来（`/am favs` 会显示 `类型424×43` 这种），别猜。

---

## 7. 设置面板绑定的是表引用，`reset` 不能换表

**现象**：点「恢复默认」后，面板上的开关点了没反应。

**真凶**：`db = DeepCopy({}, DEFAULTS)` 把 `db` 指向了一个新表，但 Settings API
的 `RegisterAddOnSetting` 已经绑定了**旧表**的引用，之后面板读写的是旧表。

**正确写法**：原地重置，不动表本身。

```lua
local function ApplyDefaults()
    for k in pairs(db) do db[k] = nil end
    for k, v in pairs(DEFAULTS) do db[k] = DeepCopy(v) end
end
```
