-- AutoMountLite.lua
-- 独立版「自动上坐骑」插件。
-- 功能灵感来自 Dugi Questing Essential 的自动上坐骑模块，本文件为独立实现，
-- 不含 Dugi 的任何代码；环境速度权重的设计思路参考自该模块。
-- 仅使用暴雪官方 API：C_Timer / C_MountJournal / 标准全局函数。
-- 不模拟按键、不注入、不 hook、不联网。
--
-- 与参考模块（Dugi）的差异：
--   * 去掉了对 Dugi 向导（GuideOn）的依赖 —— 本插件独立常驻。
--   * 开关/延迟/模式等改为本插件自己的存档（SavedVariables）。
--   * 核心选坐骑逻辑与环境速度权重的思路与参考模块一致。
--   * v1.1.0：
--       - mode=random 改为直接调用暴雪「随机召唤偏好坐骑」(法术150544)；
--         修正"没有设置收藏坐骑时完全不召唤"的问题（原来被 GetNumFavorites 拦截）。
--       - 新增默认开关快捷键 ALT+Z（Bindings.xml + 隐藏按钮，仅在该键空闲时自动绑定）。
--   * v1.2.0：
--       - 快捷键改为绑定「具名绑定」AUTOMOUNTLITE_TOGGLE（而非原始命令串），
--         使「按键设置 → 插件」里的条目与实际键位一致；并自动迁移旧版绑定。
--       - GetTheFastestMount 只返回 id 列表（去掉未使用的第二个返回值）。
--       - 明确：默认模式 = random（从收藏坐骑里随机召唤）；fastest 为可选。
--   * v1.2.1：
--       - 纠正 v1.2.0 的错误：Bindings.xml 由客户端【自动加载】，不能写进 .toc；
--         写进 toc 会被当成普通 UI XML 解析，报 "Unrecognized XML: Binding"（已回退）。
--       - Bindings.xml 的 <Binding> 属性由过时的 header= 改为 category=（现代写法）。
--   * v1.2.3：
--       - 【重要】重写坐骑类型映射表：402 与 424 均为御空（Dragonriding/Skyriding），
--         248 为普通飞行；补齐 225/229/238/263/269/284/398/407/408/412/426/428/429/436/437/444/445
--         等现代类型ID（依据 warcraft.wiki.gg API 文档 + MJE 的 MountType DB2 映射）。
--         v1.2.2 及以前沿用 Dugi 旧表（仅 230/248/254/231/232/402），导致 424 等
--         新类型的御空坐骑全部落入"其它"，/am favs 显示"御空 0 只"与事实不符，
--         使用户误以为 random 模式召唤的不是收藏坐骑。
--       - /am favs：收藏中落入"其它"的坐骑现会打印原始类型ID（如"类型424×43"），
--         暴雪将来新增类型ID 时可自诊断；每组名称显示上限 12 → 20。
--       - /am status 环境行文案更正：史诗飞行区是【御空】坐骑权重最高（非普通飞行）。
--   * v1.2.4：
--       - /am pref 在 random 模式下设置时追加提示："偏好设置只在 fastest 模式生效；
--         当前是 random 模式，输入 /am mode fastest 切换"。
--         random 模式走暴雪 SummonRandomFavoriteMount，pref 权重表完全不参与，
--         此前用户设置 pref 无任何反馈，容易误判为插件失效。
--   * v1.2.5：
--       - 新增 /am diag：逐条列出【星标收藏在当前区域的可用性】（可用/不可用两组，
--         含名称、mountID、类型名与原始类型ID）。暴雪 SummonRandomFavoriteMount 的
--         语义是"从收藏里选一个【当前区域可用】的坐骑"，此命令用于解释
--         "random 模式为什么总召那几只"——查可用池的实际大小即可。
--       - 本插件 random 模式不经过任何自研权重/类型映射，直接调用暴雪 API；
--         类型映射表（GetNamedMountType）仅服务于 fastest 模式的权重计算。
--   * v1.2.6：
--       - 【重大修复·真凶】random 模式调用的是一个【不存在的 API】：
--         v1.1.0~v1.2.5 写的是 C_MountJournal.SummonRandomFavoriteMount，
--         但当前客户端 C_MountJournal 命名空间（50 个函数，见官方 APIDocumentation
--         MountJournalDocumentation.lua / warcraft.wiki.gg）中【没有】这个函数。
--         → if 判断恒为假 → random 模式每次都掉到下面「最快坐骑」权重兜底分支。
--         现象：random 模式只召唤「权重最高那一类收藏」（用户只有 2 只同为普通飞行类型的
--         收藏 → 就只出那 2 只）；而手动点坐骑图鉴的「随机召唤偏好坐骑」按钮却能出很多只
--         （按钮走的是正确的 C_MountJournal.SummonByID(0)）。
--       - 修正为 C_MountJournal.SummonByID(0)：
--         官方文档 API:C_MountJournal.SummonByID —— "0 to summon a random favorite mount
--         appropriate to the current area"，与图鉴按钮【完全同一行为】。
--         用 pcall 包裹（防被保护/报错），失败才退回权重兜底；旧函数名保留为二级兜底。
--       - /am diag 增加自检：召唤 API 可用性 + 「权重最高候选池」明细
--         （旧版 random 实际召的就是这个池子，用于复现/解释"只召某几只"）。
--   * v1.2.7：
--       - 修正 UnitCastingInfo 的返回值取位：castingSpellID 在现代客户端是【第 9 个】
--         返回值（8.0 之后移除了 nameSubtext），旧代码写死 select(10) 取到的是 castBarID。
--         后果：IsCastingMountSpell() 恒 false（"上坐骑 4 秒防抖"失效）、
--         IsCastingNonMountSpell() 对任何施法都返回 true。
--         改为按类型判断的 CastingSpellID()（先试第 9 个，非数字再退第 10 个）。
--   * v1.3.0：
--       - 新增【可视化设置面板】：正式接入暴雪 Settings API，出现在
--         「选项 → 插件 → AutoMountLite」里，可用鼠标完成全部常用配置
--         （开关 / 召唤模式 / 施法后延迟 / 各环境指定坐骑 / 恢复默认 / 一键诊断）。
--         老客户端没有 Settings API 时自动跳过，斜杠命令依旧可用。
--       - /am reset 改为【原地重置】存档表（不再替换表引用），
--         否则设置面板绑定的是旧表、重置后会写不进去。
--   * v1.4.0：
--       - 【界面双语】新增 AutoMountLite_Locale.lua（简体中文 / English 两张文案表），
--         所有面向用户的文字（聊天输出、设置面板、按键绑定描述）改走 T() 取文案。
--         语言三档：跟随客户端 / 简体中文 / English，可用 /am lang 或面板下拉切换。
--         未翻译的 key 自动回退英文（并在离线测试里强制校验两张表 key 一致）。

local ADDON  = "AutoMountLite"
local PREFIX = "|cff33ff99AutoMountLite|r: "

--====================== 界面语言 ======================--
-- 文案表在 AutoMountLite_Locale.lua（.toc 里先于本文件加载）。
-- AutoMountLiteLocale 在客户端语言下已初始化（auto=跟随 GetLocale）；
-- db 加载完成后按用户设置再同步一次（ApplyLang）。
local function T(key, ...)
    return AutoMountLiteLocale.T(key, ...)
end

local db                     -- 指向 AutoMountLiteDB
-- ⚠️ db 必须先于下面三个函数声明：Lua 的 upvalue 在【函数定义处】捕获，
--    若 ApplyLang 定义时 db 还没声明为 local，函数体内的 db 会解析成全局(nil)，
--    ApplyLang 将永远传入 "auto"（表现为 /am lang 切换不生效）。

local function ApplyLang()
    return AutoMountLiteLocale.SetLang(db and db.lang or "auto")
end

local function LangName(code)
    code = code or "auto"
    return T("lang_name_" .. code)
end

--====================== 默认配置 ======================--

local DEFAULTS = {
    enabled         = true,        -- 默认开启
    delayAfterSpell = 1.0,         -- 施法后延迟（秒），对应 Dugi 的 "Delay After Spell"
    mode            = "random",    -- 默认；"random"=从收藏坐骑里随机召唤(150544)，"fastest"=挑环境内最快坐骑
    lang            = "auto",      -- 界面语言：auto=跟随客户端，zhCN=简体中文，enUS=English
    preferred       = {            -- 指定优先坐骑；nil=自动， "none"=该环境不骑， 数字=坐骑ID
        -- ground / flying / aquatic
    },
}

local autoMountTicker = nil  -- 0.5s 心跳

--====================== 运行态时间戳 ======================--

local lastMapUpdate            = GetTime()
local lastCombatTime           = GetTime()
local lastCastingNoneMountTime = GetTime()
local lastCastingMountTime     = GetTime()
local lastMountedTime          = GetTime()
local lastMovingTime           = GetTime()

local mountSpellSet = {}       -- spellID -> true（判断"正在施放的是不是坐骑法术"）

--====================== 基础工具 ======================--

local function DeepCopy(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = DeepCopy({}, v)
        else
            dst[k] = v
        end
    end
    return dst
end

local function Print(msg)
    print(PREFIX .. tostring(msg))
end

local function IsCasting()
    return UnitCastingInfo("player") ~= nil
end

local function IsLootFrameOpenend()
    return GetNumLootItems() > 0
end

local function RebuildMountSpells()
    mountSpellSet = {}
    if not (C_MountJournal and C_MountJournal.GetMountIDs) then return end
    for _, mountId in pairs(C_MountJournal.GetMountIDs()) do
        local _, spellID = C_MountJournal.GetMountInfoByID(mountId)
        if spellID then mountSpellSet[spellID] = true end
    end
end

local function IsMountSpell(spellID)
    return spellID and mountSpellSet[spellID] or false
end

-- 当前正在施放的法术 ID。
-- ⚠️ 返回值位置随版本变化，v1.2.7 修正（此前写死 select(10)，取到的是 castBarID）：
--   * 12.x（当前，官方 API 文档）：
--     name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill, castID,
--     notInterruptible, castingSpellID, castBarID, delayTimeMs  → spellID 是【第 9 个】
--   * 8.0 之前：第二个返回值还是 nameSubtext，当时 spellID 是【第 10 个】
-- 旧代码取到 castBarID（一个数字但不是法术ID）的后果：
--   IsCastingMountSpell() 恒 false → "上坐骑 4 秒防抖"完全失效；
--   IsCastingNonMountSpell() 对任何施法都返回 true → 上坐骑本身也被当成"非坐骑施法"。
local function CastingSpellID()
    local v9  = select(9,  UnitCastingInfo("player"))
    local v10 = select(10, UnitCastingInfo("player"))
    if type(v9)  == "number" then return v9  end   -- 现代客户端（8.0+）
    if type(v10) == "number" then return v10 end   -- 旧客户端（8.0 之前）
    return nil
end

local function IsCastingNonMountSpell()
    local spellID = CastingSpellID()
    return spellID ~= nil and not IsMountSpell(spellID)
end

local function IsCastingMountSpell()
    local spellID = CastingSpellID()
    return spellID ~= nil and IsMountSpell(spellID)
end

local function WasCastingNoneMount()
    local delay = (db and db.delayAfterSpell) or 1.0
    return (GetTime() - lastCastingNoneMountTime) <= delay
end

-- 特殊增益/减益图标（钓鱼筏 / 吃喝 / 假死 / 潜行 / Jani 诅咒）
local function IsUsingSpecialBuff()
    local i = 1
    while i <= 200 do
        local b = C_UnitAuras.GetBuffDataByIndex("player", i)
        local d = C_UnitAuras.GetDebuffDataByIndex("player", i)
        if not b and not d then break end
        local icon1 = (type(b) == "table") and b.icon or nil
        local icon2 = (type(d) == "table") and d.icon or nil
        if icon1 == 774121 or icon2 == 774121      -- inv_misc_fishing_raft
            or icon1 == 134062 or icon1 == 132805  -- 吃喝
            or icon1 == 132293                     -- 假死
            or icon1 == 132320                     -- 潜行
            or icon1 == 266311 then                -- Jani 诅咒
            return true
        end
        i = i + 1
    end
    return false
end

local function IsFeignDeath()
    if UnitIsFeignDeath("player") then return true end
    if GetMirrorTimerInfo(3) == "FEIGNDEATH" then return true end
    return false
end

local function IsShapeShift()
    local form = GetShapeshiftForm()
    if form and tonumber(form) > 0 then
        local cls = select(2, UnitClass("player"))
        if cls == "SHAMAN" or cls == "DRUID" then return true end
    end
    return false
end

--====================== 坐骑选择（权重思路同参考模块） ======================--

-- 坐骑类型ID → 分类。
-- v1.2.3 重写：v1.2.2 及以前沿用 Dugi 旧表（只有 230/248/254/231/232/402），
-- 缺 424 等较新加入的类型ID，导致大量现代坐骑落入"其它"（用户 48 只收藏中
-- 43 只未分类，/am favs 显示"御空 0 只"与实际不符）。
-- 依据（2026-10 核对）：
--   * warcraft.wiki.gg API C_MountJournal.GetMountInfoExtraByID（mountTypeID 说明）
--   * MountJournalEnhanced/Database.lua 中的 MountType DB2 映射（wago.tools/db2/MountType）
-- 关键事实：402 与 424 都是御空（Dragonriding/Skyriding）；248 是【普通】飞行。
local ADV_FLYING_TYPES = { [402] = true, [424] = true }
local FLYING_TYPES = {
    [229] = true, [238] = true, [247] = true, [248] = true, [263] = true,
    [426] = true, [428] = true, [429] = true, [437] = true, [444] = true, [445] = true,
}
local GROUND_TYPES = {
    [225] = true, [230] = true, [241] = true, [269] = true, [284] = true,
    [398] = true, [408] = true, [412] = true,
}
local AQUATIC_TYPES = { [231] = true, [232] = true, [254] = true, [407] = true, [436] = true }

local function GetNamedMountType(mountType)
    if ADV_FLYING_TYPES[mountType] then return "advflying" end
    if FLYING_TYPES[mountType]      then return "flying" end
    if GROUND_TYPES[mountType]      then return "ground" end
    if AQUATIC_TYPES[mountType]     then return "aquatic" end
    return "other"
end

-- 速度"权重"：随环境（可推进飞行 / 可飞 / 不可飞 / 水下）动态变化
local function GetMountSpeed(mountId)
    local _, _, _, _, isUsable, _, isFavorite, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountId)
    local _, _, _, _, mountTypeId = C_MountJournal.GetMountInfoExtraByID(mountId)
    if not isUsable or not isCollected then return nil end

    local swimming    = IsSubmerged() or IsSwimming()
    local isFlyable   = IsFlyableArea() and not swimming
    local isAdvFly    = (IsAdvancedFlyableArea and IsAdvancedFlyableArea()) and not swimming
    local isNoneFly   = (not IsFlyableArea()) and not (IsAdvancedFlyableArea and IsAdvancedFlyableArea()) and not swimming

    local named = GetNamedMountType(mountTypeId)
    local pref  = (db and db.preferred) or {}
    local speed = 0

    if isAdvFly then
        local p = pref.flying
        if p and p == mountId then speed = 6
        else speed = ({advflying = 5, flying = 4, ground = 3, aquatic = 2, other = 1})[named] end
        if p == "none" then speed = nil end
    end
    if isFlyable then
        local p = pref.flying
        if p and p == mountId then speed = 6
        else speed = ({advflying = 4, flying = 5, ground = 3, aquatic = 2, other = 1})[named] end
        if p == "none" then speed = nil end
    end
    if isNoneFly then
        local p = pref.ground
        if p and p == mountId then speed = 6
        else speed = ({advflying = 3, flying = 4, ground = 5, aquatic = 2, other = 1})[named] end
        if p == "none" then speed = nil end
    end
    if swimming then
        local p = pref.aquatic
        if p and p == mountId then speed = 6
        else speed = ({advflying = 2, flying = 4, ground = 3, aquatic = 5, other = 1})[named] end
        if p == "none" then speed = nil end
    end

    if isFavorite and speed ~= nil then speed = speed + 0.1 end -- 同速优先收藏
    return speed
end

local function GetTheFastestMount()
    local ids, highest = {}, nil
    for _, mountId in pairs(C_MountJournal.GetMountIDs()) do
        local speed = GetMountSpeed(mountId)
        if speed and (highest == nil or speed >= highest) then
            if highest and speed > highest then ids = {} end
            ids[#ids + 1] = mountId
            highest = speed
        end
    end
    return ids
end

--====================== 上坐骑主逻辑 ======================--

local function MountTheFastestMount()
    -- 任一条件命中则本次不召唤
    if IsFlying() or IsPlayerMoving() or IsIndoors()
        or IsMounted()
        or UnitIsDead("player") or UnitIsGhost("player")
        or (C_PetBattles and C_PetBattles.IsInBattle())
        or (UnitOnTaxi and UnitOnTaxi("player"))
        or IsShapeShift()
        or (LootFrame and LootFrame:IsVisible())
        or IsCasting()
        or IsLootFrameOpenend()
        or (GetTime() - lastCombatTime) <= 1
        or (UnitInVehicle and UnitInVehicle("player"))
        or (UnitUsingVehicle and UnitUsingVehicle("player"))
        or WasCastingNoneMount()
        or (GetTime() - lastCastingMountTime) <= 4
        or (CastingBarFrame and CastingBarFrame:IsVisible())
        or (SpellBookProfessionFrame and SpellBookProfessionFrame:IsVisible())
        or (GetTime() - lastMapUpdate) <= 1        -- 刚过图，IsFlyableArea 尚未刷新
        or UnitAffectingCombat("player")
        or (GetTime() - lastMountedTime) <= 1
        or (GetTime() - lastMovingTime) <= 0.4
        or IsUsingSpecialBuff()
        or IsFeignDeath()
        or IsFalling() then
        return
    end

    if db.mode == "random" then
        -- 暴雪「随机召唤偏好坐骑」(法术 150544)。当前客户端的正确 API 是：
        --     C_MountJournal.SummonByID(0)
        -- 官方文档（API:C_MountJournal.SummonByID）原文：
        --     "or 0 to summon a random favorite mount appropriate to the current area"
        -- 即：从【星标收藏】里随机一只【当前区域可用】的坐骑；若没有任何本区域可用的
        -- 收藏，客户端会提示 "You have no valid favorite mounts."（不召唤）。
        -- 这与坐骑图鉴上的「随机召唤偏好坐骑」按钮是同一个行为。
        --
        -- !! v1.2.6 重大修正 !!
        -- v1.1.0~v1.2.5 这里写的是 C_MountJournal.SummonRandomFavoriteMount ——
        -- 该函数在当前客户端【根本不存在】（见官方 MountJournal API 函数清单），
        -- 所以 if 恒为假，random 模式每次都掉到下面的权重兜底分支，表现为
        -- "random 模式只召固定的那几只（权重最高的一类收藏）"。
        if C_MountJournal.SummonByID then
            local ok = pcall(C_MountJournal.SummonByID, 0)
            if ok then return end
            -- 被保护/调用失败 → 落到下面的兜底
        end
        -- 二级兜底：极老客户端的函数名（当前客户端不存在，保留以兼容）
        if C_MountJournal.SummonRandomFavoriteMount then
            local ok = pcall(C_MountJournal.SummonRandomFavoriteMount)
            if ok then return end
        end
        -- 三级兜底：API 都不可用时退回"最快坐骑"权重
    end

    local ids = GetTheFastestMount()
    if #ids > 0 and C_MountJournal.SummonByID then
        C_MountJournal.SummonByID(ids[math.random(1, #ids)])
    end
end

local function CancelAutoMountingIfNeeded()
    if IsLootFrameOpenend() and not IsFlying() and not IsMounted() then
        C_MountJournal.Dismiss()
    end
end

local function UpdateEnabled()
    local want = db and db.enabled
    if want then
        if not autoMountTicker then
            autoMountTicker = C_Timer.NewTicker(0.5, function()
                if IsCastingNonMountSpell() then lastCastingNoneMountTime = GetTime() end
                if IsMounted()           then lastMountedTime          = GetTime() end
                if IsPlayerMoving()      then lastMovingTime           = GetTime() end
                if IsCastingMountSpell() then lastCastingMountTime     = GetTime() end
                if UnitAffectingCombat("player") then lastCombatTime   = GetTime() end

                CancelAutoMountingIfNeeded()
                MountTheFastestMount()
            end)
        end
    else
        if autoMountTicker then
            autoMountTicker:Cancel()
            autoMountTicker = nil
        end
    end
end

-- 开/关（斜杠命令与 ALT+Z 快捷键共用）
local function ToggleEnabled()
    db.enabled = not db.enabled
    UpdateEnabled()
    Print(db.enabled and T("msg_enabled_toggle") or T("msg_disabled"))
end

--====================== 诊断辅助 ======================--

-- 当前所处的环境（对应参考模块权重表实际生效的分支）
local function EnvText()
    local swimming = IsSubmerged() or IsSwimming()
    local hasAdv   = (IsAdvancedFlyableArea and IsAdvancedFlyableArea()) and not swimming
    local hasFly   = IsFlyableArea() and not swimming
    if swimming then return T("env_water") end
    if hasAdv then return T("env_adv") end
    if hasFly then return T("env_fly") end
    return T("env_ground")
end

-- 按类型分组列出【收藏】坐骑：诊断 random 模式"总召某类坐骑"用
local function ListFavorites()
    if not (C_MountJournal and C_MountJournal.GetMountIDs) then
        Print(T("api_unavailable"))
        return
    end
    local order   = {"advflying", "flying", "ground", "aquatic", "other"}
    local function label(key) return T("type_" .. key) end
    local groups, typeCount, totalFav, totalAll = {}, {}, 0, 0
    local unknownFavTypes = {}   -- 收藏中未识别类型ID -> 数量（自诊断用）

    for _, mountId in pairs(C_MountJournal.GetMountIDs()) do
        local name, _, _, _, _, _, isFavorite, _, _, _, isCollected =
            C_MountJournal.GetMountInfoByID(mountId)
        if isCollected then
            local _, _, _, _, mountTypeId = C_MountJournal.GetMountInfoExtraByID(mountId)
            local named = GetNamedMountType(mountTypeId)
            typeCount[named] = (typeCount[named] or 0) + 1
            totalAll = totalAll + 1
            if isFavorite then
                groups[named] = groups[named] or {}
                groups[named][#groups[named] + 1] =
                    string.format("%s(ID:%d)", name or T("mount_fallback", mountId), mountId)
                totalFav = totalFav + 1
                if named == "other" then
                    unknownFavTypes[mountTypeId] = (unknownFavTypes[mountTypeId] or 0) + 1
                end
            end
        end
    end

    Print(T("favs_header", totalFav))
    for _, key in ipairs(order) do
        local list = groups[key]
        if list and #list > 0 then
            local shown = {}
            for i = 1, math.min(#list, 20) do shown[i] = list[i] end
            local tail = (#list > 20) and T("favs_more", #list) or ""
            Print(T("favs_group", label(key), #list, table.concat(shown, ", "), tail))
        else
            Print(T("favs_empty", label(key)))
        end
    end

    if next(unknownFavTypes) then
        local parts = {}
        for tid, n in pairs(unknownFavTypes) do
            parts[#parts + 1] = T("favs_unknown_each", tid, n)
        end
        table.sort(parts)
        Print(T("favs_unknown", table.concat(parts, ", ")))
    end

    local cnt = {}
    for _, key in ipairs(order) do
        cnt[#cnt + 1] = string.format("%s=%d", label(key), typeCount[key] or 0)
    end
    Print(T("favs_collected", totalAll, table.concat(cnt, " ")))

    if totalFav == 0 then
        Print(T("favs_none"))
    end
    Print(T("favs_hint"))
end

-- 诊断：列出星标收藏在当前区域的「可用性」。
-- 暴雪 SummonRandomFavoriteMount 的官方语义是「从收藏中选一个当前区域可用的」，
-- 所以只要看清哪些收藏 isUsable=false，就能解释「为什么 random 总召那几只」。
local function DiagFavorites()
    if not (C_MountJournal and C_MountJournal.GetMountIDs) then
        Print(T("api_unavailable"))
        return
    end

    local usable, blocked = {}, {}
    for _, mountId in pairs(C_MountJournal.GetMountIDs()) do
        local name, _, _, _, isUsable, _, isFavorite, _, _, _, isCollected =
            C_MountJournal.GetMountInfoByID(mountId)
        if isCollected and isFavorite then
            local _, _, _, _, mountTypeId = C_MountJournal.GetMountInfoExtraByID(mountId)
            local named  = GetNamedMountType(mountTypeId)
            local line   = T("diag_line",
                name or T("mount_fallback", mountId), mountId, named, mountTypeId or -1)
            if isUsable then
                usable[#usable + 1] = line
            else
                blocked[#blocked + 1] = line
            end
        end
    end

    local total = #usable + #blocked
    Print(T("diag_header", total, #usable, #blocked))
    Print(T("diag_env",
        tostring(IsFlyableArea()) and T("yes") or T("no"),
        (IsAdvancedFlyableArea and IsAdvancedFlyableArea()) and T("yes") or T("no"),
        (IsSubmerged() or IsSwimming()) and T("yes") or T("no")))

    local function dump(tag, list)
        if #list == 0 then return end
        local cap   = 12
        local shown = {}
        for i = 1, math.min(#list, cap) do shown[i] = list[i] end
        local tail  = (#list > cap) and T("favs_more", #list) or ""
        Print(T("favs_group", tag, #list, table.concat(shown, ", "), tail))
    end
    dump(T("diag_usable"), usable)
    dump(T("diag_blocked"), blocked)

    -- v1.2.6 自检①：召唤 API 可用性（random 模式应走 SummonByID(0)）
    Print(T("diag_api",
        C_MountJournal.SummonByID and T("api_ok") or T("api_missing"),
        C_MountJournal.SummonRandomFavoriteMount and T("api_ok") or T("api_missing")))

    -- v1.2.6 自检②：权重最高候选池
    -- （v1.1.0~v1.2.5 的 random 因 API 名写错，实际召的就是这个池子里的坐骑）
    local pool = GetTheFastestMount()
    if #pool > 0 then
        local names = {}
        for i = 1, math.min(#pool, 10) do
            local n = C_MountJournal.GetMountInfoByID(pool[i])
            names[i] = string.format("%s(ID:%d)", n or T("mount_fallback", pool[i]), pool[i])
        end
        local tail = (#pool > 10) and T("favs_more", #pool) or ""
        Print(T("diag_pool", #pool, table.concat(names, ", "), tail))
    end

    if #usable == 0 then
        Print(T("diag_no_usable"))
    elseif #usable <= 2 then
        Print(T("diag_few_usable", #usable))
    end
end

--====================== 状态 / 命令 ======================--

local function FmtPref(v)
    if v == nil then return T("pref_auto") end
    if v == "none" then return T("pref_none") end
    return T("pref_id", v)
end

local function StatusText()
    local p = db.preferred or {}
    return T("status_line",
        db.enabled and T("on") or T("off"),
        db.delayAfterSpell or 1.0,
        db.mode or "random",
        FmtPref(p.ground), FmtPref(p.flying), FmtPref(p.aquatic),
        EnvText())
end

-- 恢复默认：必须【原地】改写 db 表，不能 db = DeepCopy(...) 换引用 ——
-- 因为设置面板（Settings API）在注册时就绑定了这张表的引用，
-- 换引用会导致面板继续读写旧表、重置后设置"写不进去"。
local function ApplyDefaults()
    for k in pairs(db) do db[k] = nil end
    for k, v in pairs(DEFAULTS) do
        if type(v) == "table" then
            db[k] = DeepCopy({}, v)
        else
            db[k] = v
        end
    end
end

local function HandleSlash(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "toggle" then
        ToggleEnabled()
    elseif cmd == "on" then
        db.enabled = true;  UpdateEnabled(); Print(T("msg_enabled"))
    elseif cmd == "off" then
        db.enabled = false; UpdateEnabled(); Print(T("msg_disabled"))
    elseif cmd == "delay" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 10 then
            db.delayAfterSpell = n
            Print(T("msg_delay", n))
        else
            Print(T("usage_delay"))
        end
    elseif cmd == "mode" then
        local m = (rest or ""):lower()
        if m == "fastest" or m == "random" then
            db.mode = m; Print(T("msg_mode", m))
        else
            Print(T("usage_mode"))
        end
    elseif cmd == "pref" then
        local slot, val = rest:match("^(%S+)%s*(.*)$")
        slot = (slot or ""):lower()
        if slot == "ground" or slot == "flying" or slot == "aquatic" then
            if val == "" or val == "auto" then
                db.preferred[slot] = nil; Print(T("msg_pref_set", T("slot_" .. slot), T("pref_auto")))
            elseif val == "none" then
                db.preferred[slot] = "none"; Print(T("msg_pref_set", T("slot_" .. slot), T("pref_none")))
            else
                local id = tonumber(val)
                if id then db.preferred[slot] = id; Print(T("msg_pref_set", T("slot_" .. slot), T("pref_id", id)))
                else Print(T("usage_pref")) end
            end
            -- v1.2.4：random 模式下 pref 完全无效（走暴雪随机收藏），
            -- 设置时明确提示，避免"设了没反应"的困惑
            if db.mode == "random" then
                Print(T("note_pref_mode"))
            end
        else
            Print(T("usage_pref"))
        end
    elseif cmd == "status" then
        Print(StatusText())
    elseif cmd == "favs" or cmd == "mounts" then
        ListFavorites()
    elseif cmd == "diag" then
        DiagFavorites()
    elseif cmd == "reset" then
        ApplyDefaults()
        UpdateEnabled()
        Print(T("msg_reset", StatusText()))
    elseif cmd == "lang" then
        local l = (rest or ""):lower()
        if l == "auto" or l == "zhcn" or l == "enus" then
            local code = (l == "zhcn") and "zhCN" or ((l == "enus") and "enUS" or "auto")
            db.lang = code
            local effective = ApplyLang()
            if code == "auto" then
                Print(T("msg_lang", T("lang_name_auto") .. " (" .. effective .. ")"))
            else
                Print(T("msg_lang_reload", LangName(code)))
            end
        elseif l == "" then
            Print(T("msg_lang", LangName(db.lang) .. " (" .. (AutoMountLiteLocale.GetLang() or "?") .. ")"))
        else
            Print(T("usage_lang"))
        end
    else
        Print(T("help_title"))
        Print(T("help_toggle"))
        Print(T("help_onoff"))
        Print(T("help_status"))
        Print(T("help_favs"))
        Print(T("help_diag"))
        Print(T("help_delay"))
        Print(T("help_mode"))
        Print(T("help_pref"))
        Print(T("help_reset"))
        Print(T("help_lang"))
        Print(T("help_binding"))
    end
end

SLASH_AUTOMOUNTLITE1 = "/am"
SLASH_AUTOMOUNTLITE2 = "/automountlite"
SlashCmdList["AUTOMOUNTLITE"] = HandleSlash

--====================== 可视化设置面板（暴雪 Settings API） ======================--
-- 让本插件的配置出现在「选项 → 插件 → AutoMountLite」，鼠标即可完成常用设置。
-- API 取材自当前客户端（与本机已装插件 MinimapButtonButton / GSE 的实现逐一对齐）：
--   Settings.RegisterVerticalLayoutCategory / RegisterAddOnCategory
--   Settings.RegisterAddOnSetting（表内键自动读写）
--   Settings.RegisterProxySetting（自定义 get/set，用于三处坐骑偏好）
--   Settings.CreateCheckbox / CreateSlider(+CreateSliderOptions) / CreateDropdown
--   CreateSettingsButtonInitializer（按钮）· Settings.CreateElementInitializer（分节标题）
-- 老客户端没有这套 API 时整体跳过，斜杠命令依旧可用。

local settingsBuilt = false

local function BuildSettingsPanel()
    if settingsBuilt then return end
    settingsBuilt = true
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

    local ok, err = pcall(function()
        local VarType = Settings.VarType
            or { Boolean = "boolean", Number = "number", String = "string" }
        local canCheck = Settings.RegisterAddOnSetting and Settings.CreateCheckbox
        local canSlider = Settings.CreateSlider and Settings.CreateSliderOptions
        local canDrop  = Settings.CreateDropdown and Settings.CreateControlTextContainer
        local canProxy = Settings.RegisterProxySetting
        local canHead  = Settings.CreateElementInitializer
        local canBtn   = _G.CreateSettingsButtonInitializer

        local category, layout = Settings.RegisterVerticalLayoutCategory(T("panel_title"))

        local function AddHeader(text)
            if canHead then
                layout:AddInitializer(Settings.CreateElementInitializer(
                    "SettingsListSectionHeaderTemplate", { name = text, tooltip = "" }))
            end
        end

        ----------------------------------------------------------------
        AddHeader(T("panel_title"))

        -- 界面语言（放最上面：先选语言，下面每个控件的文字都跟着变）
        if canProxy and canDrop then
            local s = Settings.RegisterProxySetting(category, "AutoMountLite_lang",
                VarType.String, T("dd_lang"), "auto",
                function() return db.lang or "auto" end,
                function(val)
                    db.lang = val
                    -- 立刻切语言：聊天输出、下拉选项、提示文字即时生效；
                    -- 已建好的面板标题文字是静态的，需 /reload 后刷新（已在下拉说明里告知）
                    local effective = ApplyLang()
                    if val ~= "auto" then
                        Print(T("msg_lang_reload", LangName(val)))
                    else
                        Print(T("msg_lang", T("lang_name_auto") .. " (" .. effective .. ")"))
                    end
                end)
            local function GetOptions()
                local c = Settings.CreateControlTextContainer()
                c:Add("auto",  T("dd_lang_auto"))
                c:Add("zhCN",  T("dd_lang_zhCN"))
                c:Add("enUS",  T("dd_lang_enUS"))
                return c:GetData()
            end
            Settings.CreateDropdown(category, s, GetOptions, T("dd_lang_tip"))
        end

        -- 总开关
        if canCheck then
            local s = Settings.RegisterAddOnSetting(category, "AutoMountLite_enabled",
                "enabled", db, VarType.Boolean, T("cb_enabled"), DEFAULTS.enabled)
            if s.SetValueChangedCallback then
                s:SetValueChangedCallback(function() UpdateEnabled() end)
            end
            Settings.CreateCheckbox(category, s, T("cb_enabled_tip"))
        end

        -- 召唤模式
        if canCheck and canDrop then
            local s = Settings.RegisterAddOnSetting(category, "AutoMountLite_mode",
                "mode", db, VarType.String, T("dd_mode"), DEFAULTS.mode)
            local function GetOptions()
                local c = Settings.CreateControlTextContainer()
                c:Add("random",  T("dd_mode_random"))
                c:Add("fastest", T("dd_mode_fastest"))
                return c:GetData()
            end
            Settings.CreateDropdown(category, s, GetOptions, T("dd_mode_tip"))
        end

        -- 施法后延迟
        if canCheck and canSlider then
            local s = Settings.RegisterAddOnSetting(category, "AutoMountLite_delayAfterSpell",
                "delayAfterSpell", db, VarType.Number, T("slider_delay"), DEFAULTS.delayAfterSpell)
            local opts = Settings.CreateSliderOptions(0, 10, 0.5)
            local Lbl = _G.MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
            if Lbl and opts.SetLabelFormatter then
                opts:SetLabelFormatter(Lbl.Right, function(v)
                    return T("slider_fmt", v)
                end)
            end
            Settings.CreateSlider(category, s, opts, T("slider_tip"))
        end

        ----------------------------------------------------------------
        AddHeader(T("header_pref"))

        if canProxy and canDrop then
            local SLOTS = {
                { key = "ground",  label = T("slot_label_ground") },
                { key = "flying",  label = T("slot_label_flying") },
                { key = "aquatic", label = T("slot_label_aquatic") },
            }
            for _, slotInfo in ipairs(SLOTS) do
                local k = slotInfo.key
                -- 存档取值：nil=自动（转成 "auto" 以便下拉框显示）/"none"/坐骑ID
                local function GetValue()
                    local v = db.preferred and db.preferred[k]
                    if v == nil then return "auto" end
                    if v == "none" then return "none" end
                    return tostring(v)
                end
                local function SetValue(val)
                    db.preferred = db.preferred or {}
                    if val == nil or val == "" or val == "auto" then
                        db.preferred[k] = nil
                    elseif val == "none" then
                        db.preferred[k] = "none"
                    else
                        db.preferred[k] = tonumber(val) or nil
                    end
                end

                local s = Settings.RegisterProxySetting(category, "AutoMountLite_pref_" .. k,
                    VarType.String, slotInfo.label, "auto", GetValue, SetValue)

                local function GetOptions()
                    local c = Settings.CreateControlTextContainer()
                    c:Add("auto", T("opt_auto"))
                    c:Add("none", T("opt_none"))
                    if C_MountJournal and C_MountJournal.GetMountIDs then
                        local mounts = {}
                        for _, id in pairs(C_MountJournal.GetMountIDs()) do
                            local name, _, _, _, _, _, isFavorite, _, _, _, isCollected =
                                C_MountJournal.GetMountInfoByID(id)
                            if isCollected then
                                mounts[#mounts + 1] = {
                                    id = id, name = name or T("mount_fallback", id), fav = isFavorite,
                                }
                            end
                        end
                        -- 排序：收藏(★)排前面，其余按名称
                        table.sort(mounts, function(a, b)
                            if a.fav ~= b.fav then return a.fav end
                            return a.name < b.name
                        end)
                        for _, m in ipairs(mounts) do
                            c:Add(tostring(m.id),
                                string.format("%s%s (ID:%d)", m.fav and "★" or "", m.name, m.id))
                        end
                    end
                    return c:GetData()
                end
                Settings.CreateDropdown(category, s, GetOptions, T("dd_pref_tip"))
            end
        end

        ----------------------------------------------------------------
        AddHeader(T("header_tools"))

        if canBtn then
            layout:AddInitializer(CreateSettingsButtonInitializer(
                T("btn_diag"), T("btn_diag_desc"),
                function()
                    Print(StatusText())
                    ListFavorites()
                end,
                T("btn_diag_tip"), true))

            layout:AddInitializer(CreateSettingsButtonInitializer(
                T("btn_keys"), T("btn_keys_desc"),
                function()
                    if Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
                        Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
                    end
                end,
                T("btn_keys_tip"), true))

            layout:AddInitializer(CreateSettingsButtonInitializer(
                T("btn_reset"), T("btn_reset_desc"),
                function()
                    ApplyDefaults()
                    UpdateEnabled()
                    if SettingsPanel and SettingsPanel.Refresh then SettingsPanel:Refresh() end
                    Print(T("msg_reset", StatusText()))
                end,
                T("btn_reset_tip"), true))
        end

        Settings.RegisterAddOnCategory(category)
    end)

    if not ok then
        Print(T("panel_error", tostring(err)))
    end
end

--====================== 快捷键开关（默认 ALT+Z） ======================--
-- 这两条全局变量客户端在 Bindings.xml 之后读取，用来显示键位描述。
-- Locale 文件先于本文件加载，此时已按客户端语言初始化，直接取文案即可。
BINDING_HEADER_AUTOMOUNTLITE      = "AutoMountLite"
BINDING_NAME_AUTOMOUNTLITE_TOGGLE = T("binding_name")

-- 具名绑定（在 Bindings.xml 中声明），使键位在「按键设置 → 插件」里可见、可改
local BINDING_ID = "AUTOMOUNTLITE_TOGGLE"
-- 旧版把 ALT+Z 绑到了这条原始命令串；检测到则自动迁移到具名绑定
local LEGACY_BINDING_ACTION = "CLICK AutoMountLiteToggleButton:LeftButton"

-- 供 Bindings.xml 的 <Binding> 正文调用（现代客户端会把正文当 Lua 代码编译执行）
function AutoMountLite_Toggle()
    ToggleEnabled()
end

local toggleBtn = CreateFrame("Button", "AutoMountLiteToggleButton", UIParent)
toggleBtn:SetSize(1, 1)
toggleBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, -200)
toggleBtn:RegisterForClicks("AnyUp")
toggleBtn:SetScript("OnClick", function() AutoMountLite_Toggle() end)

local function EnsureDefaultBinding()
    -- 自愈式：每次登录都核对【实际】绑定状态，不依赖一次性标志
    -- （v1.2.0/v1.2.1 用 bindingInit2 标志，一旦置真就不再重试，导致修好 XML 后仍不生效）
    local key = GetBindingKey(BINDING_ID)
    if key and key ~= "" then return end

    local occupied = GetBindingAction("ALT-Z")
    if occupied == LEGACY_BINDING_ACTION then
        -- 旧版绑到了原始命令串，迁移为具名绑定
        SetBinding("ALT-Z", BINDING_ID)
        SaveBindings(GetCurrentBindingSet())
        Print(T("binding_migrated"))
        return
    end
    if occupied and occupied ~= "" then
        if not db.bindingWarned then
            db.bindingWarned = true
            Print(T("binding_occupied"))
        end
        return
    end

    SetBinding("ALT-Z", BINDING_ID)
    SaveBindings(GetCurrentBindingSet())
    Print(T("binding_set"))
end

--====================== 事件 ======================--

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("NEW_MOUNT_ADDED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        if type(AutoMountLiteDB) ~= "table" then AutoMountLiteDB = {} end
        db = AutoMountLiteDB
        for k, v in pairs(DEFAULTS) do
            if type(v) == "table" then
                if type(db[k]) ~= "table" then db[k] = DeepCopy({}, v) end
            elseif db[k] == nil then
                db[k] = v
            end
        end
        AutoMountLiteDB = db
        ApplyLang()      -- 按用户设置的语言（默认 auto=跟随客户端）生效
        BuildSettingsPanel()

    elseif event == "PLAYER_LOGIN" then
        if math.randomseed then math.randomseed(time()) end
        RebuildMountSpells()
        EnsureDefaultBinding()
        UpdateEnabled()
        Print(T("msg_loaded", StatusText()))

    elseif event == "NEW_MOUNT_ADDED" then
        RebuildMountSpells()

    elseif event == "PLAYER_ENTERING_WORLD" then
        lastMapUpdate = GetTime()
        RebuildMountSpells()

    else -- ZONE_CHANGED*
        lastMapUpdate = GetTime()
    end
end)
