-- AutoMountLite.lua
-- 独立版「自动上坐骑」模块（逻辑复刻自 Dugi Questing Essential 的自动上坐骑）
-- 仅使用暴雪官方 API：C_Timer / C_MountJournal / 标准全局函数。
-- 不模拟按键、不注入、不 hook、不联网。
--
-- 与 Dugi 原版的差异：
--   * 去掉了对 Dugi 向导（GuideOn）的依赖 —— 本插件独立常驻。
--   * 开关/延迟/模式等改为本插件自己的存档（SavedVariables）。
--   * 核心选坐骑逻辑与环境速度权重与原版保持一致。
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

local ADDON  = "AutoMountLite"
local PREFIX = "|cff33ff99AutoMountLite|r: "

--====================== 默认配置 ======================--

local DEFAULTS = {
    enabled         = true,        -- 默认开启
    delayAfterSpell = 1.0,         -- 施法后延迟（秒），对应 Dugi 的 "Delay After Spell"
    mode            = "random",    -- 默认；"random"=从收藏坐骑里随机召唤(150544)，"fastest"=挑环境内最快坐骑
    preferred       = {            -- 指定优先坐骑；nil=自动， "none"=该环境不骑， 数字=坐骑ID
        -- ground / flying / aquatic
    },
}

local db                     -- 指向 AutoMountLiteDB
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

--====================== 坐骑选择（与 Dugi 一致） ======================--

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
    Print(db.enabled and "已开启（自动上坐骑）" or "已关闭")
end

--====================== 诊断辅助 ======================--

-- 当前所处的环境（对应 Dugi 权重表实际生效的分支）
local function EnvText()
    local swimming = IsSubmerged() or IsSwimming()
    local hasAdv   = (IsAdvancedFlyableArea and IsAdvancedFlyableArea()) and not swimming
    local hasFly   = IsFlyableArea() and not swimming
    if swimming then return "水下" end
    if hasAdv then return "史诗飞行区(御空坐骑权重最高)" end
    if hasFly then return "可飞区(普通飞行)" end
    return "不可飞区(地面)"
end

-- 按类型分组列出【收藏】坐骑：诊断 random 模式"总召某类坐骑"用
local function ListFavorites()
    if not (C_MountJournal and C_MountJournal.GetMountIDs) then
        Print("坐骑图鉴 API 不可用")
        return
    end
    local order   = {"advflying", "flying", "ground", "aquatic", "other"}
    local label   = {advflying = "御空", flying = "飞行", ground = "地面",
                     aquatic = "水下", other = "其它"}
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
                    string.format("%s(ID:%d)", name or "?", mountId)
                totalFav = totalFav + 1
                if named == "other" then
                    unknownFavTypes[mountTypeId] = (unknownFavTypes[mountTypeId] or 0) + 1
                end
            end
        end
    end

    Print(string.format("收藏坐骑 %d 只（random 模式只在这些里面随机）：", totalFav))
    for _, key in ipairs(order) do
        local list = groups[key]
        if list and #list > 0 then
            local shown = {}
            for i = 1, math.min(#list, 20) do shown[i] = list[i] end
            local tail = (#list > 20) and string.format(" …等 %d 只", #list) or ""
            Print(string.format("  [%s] %d 只: %s%s",
                label[key], #list, table.concat(shown, ", "), tail))
        else
            Print(string.format("  [%s] 0 只", label[key]))
        end
    end

    if next(unknownFavTypes) then
        local parts = {}
        for tid, n in pairs(unknownFavTypes) do
            parts[#parts + 1] = string.format("类型%d×%d", tid, n)
        end
        table.sort(parts)
        Print("收藏中有未识别类型: " .. table.concat(parts, ", ")
            .. "（请联系插件作者补充映射）")
    end

    local cnt = {}
    for _, key in ipairs(order) do
        cnt[#cnt + 1] = string.format("%s=%d", label[key], typeCount[key] or 0)
    end
    Print(string.format("已收集坐骑共 %d 只（%s）", totalAll, table.concat(cnt, " ")))

    if totalFav == 0 then
        Print("你还没有收藏任何坐骑。random 模式调用暴雪「随机召唤偏好坐骑」，"
            .. "没有收藏时的行为由客户端决定。")
    end
    Print("提示：/am pref 偏好设置只在 fastest 模式生效；random 模式改收藏构成"
        .. "（坐骑图鉴点星星）才能改变随机池。")
end

-- 诊断：列出星标收藏在当前区域的「可用性」。
-- 暴雪 SummonRandomFavoriteMount 的官方语义是「从收藏中选一个当前区域可用的」，
-- 所以只要看清哪些收藏 isUsable=false，就能解释「为什么 random 总召那几只」。
local function DiagFavorites()
    if not (C_MountJournal and C_MountJournal.GetMountIDs) then
        Print("坐骑图鉴 API 不可用")
        return
    end

    local usable, blocked = {}, {}
    for _, mountId in pairs(C_MountJournal.GetMountIDs()) do
        local name, _, _, _, isUsable, _, isFavorite, _, _, _, isCollected =
            C_MountJournal.GetMountInfoByID(mountId)
        if isCollected and isFavorite then
            local _, _, _, _, mountTypeId = C_MountJournal.GetMountInfoExtraByID(mountId)
            local named  = GetNamedMountType(mountTypeId)
            local line   = string.format("%s(ID:%d,类型%s/%d)",
                name or "?", mountId, named, mountTypeId or -1)
            if isUsable then
                usable[#usable + 1] = line
            else
                blocked[#blocked + 1] = line
            end
        end
    end

    local total = #usable + #blocked
    Print(string.format("诊断 · 星标收藏 %d 只 | 当前区域【可用】%d 只 | 【不可用】%d 只",
        total, #usable, #blocked))
    Print(string.format("环境：可飞=%s 御空=%s 水下=%s  —— random 只从「可用」里随机",
        tostring(IsFlyableArea()) and "是" or "否",
        (IsAdvancedFlyableArea and IsAdvancedFlyableArea()) and "是" or "否",
        (IsSubmerged() or IsSwimming()) and "是" or "否"))

    local function dump(tag, list)
        if #list == 0 then return end
        local cap   = 12
        local shown = {}
        for i = 1, math.min(#list, cap) do shown[i] = list[i] end
        local tail  = (#list > cap) and string.format(" …等 %d 只", #list) or ""
        Print(string.format("  [%s] %d 只: %s%s", tag, #list, table.concat(shown, ", "), tail))
    end
    dump("可用", usable)
    dump("不可用", blocked)

    -- v1.2.6 自检①：召唤 API 可用性（random 模式应走 SummonByID(0)）
    Print(string.format("召唤API：SummonByID=%s（0=随机收藏） SummonRandomFavoriteMount=%s",
        C_MountJournal.SummonByID and "可用" or "缺失",
        C_MountJournal.SummonRandomFavoriteMount and "可用" or "缺失"))

    -- v1.2.6 自检②：权重最高候选池
    -- （v1.1.0~v1.2.5 的 random 因 API 名写错，实际召的就是这个池子里的坐骑）
    local pool = GetTheFastestMount()
    if #pool > 0 then
        local names = {}
        for i = 1, math.min(#pool, 10) do
            local n = C_MountJournal.GetMountInfoByID(pool[i])
            names[i] = string.format("%s(ID:%d)", n or "?", pool[i])
        end
        local tail = (#pool > 10) and string.format(" …等 %d 只", #pool) or ""
        Print(string.format("权重最高候选池 %d 只（旧版 random 实际只召这里面的）: %s%s",
            #pool, table.concat(names, ", "), tail))
    end

    if #usable == 0 then
        Print("当前区域没有任何可用的星标收藏坐骑 → random 模式会无坐骑可召。")
    elseif #usable <= 2 then
        Print("可用池只有 " .. #usable .. " 只 → 这就是「只召这几只」的原因。")
    end
end

--====================== 状态 / 命令 ======================--

local function FmtPref(v)
    if v == nil then return "自动" end
    if v == "none" then return "不骑" end
    return "ID:" .. tostring(v)
end

local function StatusText()
    local p = db.preferred or {}
    return string.format("开关=%s  施法后延迟=%.1fs  模式=%s  地面=%s 飞行=%s 水下=%s",
        db.enabled and "开" or "关",
        db.delayAfterSpell or 1.0,
        db.mode or "random",
        FmtPref(p.ground), FmtPref(p.flying), FmtPref(p.aquatic))
        .. "  环境=" .. EnvText()
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
        db.enabled = true;  UpdateEnabled(); Print("已开启")
    elseif cmd == "off" then
        db.enabled = false; UpdateEnabled(); Print("已关闭")
    elseif cmd == "delay" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 10 then
            db.delayAfterSpell = n
            Print(string.format("施法后延迟 = %.1fs", n))
        else
            Print("用法: /am delay <0-10>")
        end
    elseif cmd == "mode" then
        local m = (rest or ""):lower()
        if m == "fastest" or m == "random" then
            db.mode = m; Print("模式 = " .. m)
        else
            Print("用法: /am mode fastest|random")
        end
    elseif cmd == "pref" then
        local slot, val = rest:match("^(%S+)%s*(.*)$")
        slot = (slot or ""):lower()
        if slot == "ground" or slot == "flying" or slot == "aquatic" then
            if val == "" or val == "auto" then
                db.preferred[slot] = nil; Print(slot .. " = 自动")
            elseif val == "none" then
                db.preferred[slot] = "none"; Print(slot .. " = 不骑")
            else
                local id = tonumber(val)
                if id then db.preferred[slot] = id; Print(slot .. " = ID:" .. id)
                else Print("用法: /am pref <ground|flying|aquatic> auto|none|坐骑ID") end
            end
            -- v1.2.4：random 模式下 pref 完全无效（走暴雪随机收藏），
            -- 设置时明确提示，避免"设了没反应"的困惑
            if db.mode == "random" then
                Print("注意：偏好设置只在 fastest 模式生效；当前是 random 模式，输入 /am mode fastest 切换")
            end
        else
            Print("用法: /am pref <ground|flying|aquatic> auto|none|坐骑ID")
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
        Print("已恢复默认 · " .. StatusText())
    else
        Print("命令：")
        Print("  /am                      切换 开/关")
        Print("  /am on | /am off          开启 / 关闭")
        Print("  /am status               查看状态")
        Print("  /am favs                 按类型列出收藏坐骑（名称+ID，诊断随机池）")
        Print("  /am diag                 诊断星标收藏在当前区域的可用性（解释只召某几只）")
        Print("  /am delay <0-10>         施法后延迟秒数")
        Print("  /am mode fastest|random  最快坐骑 / 随机召唤偏好坐骑")
        Print("  /am pref <ground|flying|aquatic> auto|none|坐骑ID")
        Print("  /am reset                恢复默认")
        Print("  快捷键：ALT+Z 直接 开/关（可在「按键设置 → 插件」里修改）")
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

        local category, layout = Settings.RegisterVerticalLayoutCategory("AutoMountLite")

        local function AddHeader(text)
            if canHead then
                layout:AddInitializer(Settings.CreateElementInitializer(
                    "SettingsListSectionHeaderTemplate", { name = text, tooltip = "" }))
            end
        end

        ----------------------------------------------------------------
        AddHeader("自动上坐骑")

        -- 总开关
        if canCheck then
            local s = Settings.RegisterAddOnSetting(category, "AutoMountLite_enabled",
                "enabled", db, VarType.Boolean, "启用自动上坐骑", DEFAULTS.enabled)
            if s.SetValueChangedCallback then
                s:SetValueChangedCallback(function() UpdateEnabled() end)
            end
            Settings.CreateCheckbox(category, s,
                "开启后：你落地静止时自动召唤坐骑。（快捷键 ALT+Z 或 /am 也可快速开关）")
        end

        -- 召唤模式
        if canCheck and canDrop then
            local s = Settings.RegisterAddOnSetting(category, "AutoMountLite_mode",
                "mode", db, VarType.String, "召唤模式", DEFAULTS.mode)
            local function GetOptions()
                local c = Settings.CreateControlTextContainer()
                c:Add("random",  "随机召唤偏好坐骑（从星标收藏里随机 · 推荐）")
                c:Add("fastest", "环境内最快坐骑（按权重表挑选）")
                return c:GetData()
            end
            Settings.CreateDropdown(category, s, GetOptions,
                "random：与坐骑图鉴的「随机召唤偏好坐骑」按钮行为完全一致，只从你的星标收藏里随机。\n"
                .. "fastest：按当前环境（御空 / 可飞 / 地面 / 水下）权重表挑最快坐骑，"
                .. "可用下方「指定坐骑偏好」精确控制。")
        end

        -- 施法后延迟
        if canCheck and canSlider then
            local s = Settings.RegisterAddOnSetting(category, "AutoMountLite_delayAfterSpell",
                "delayAfterSpell", db, VarType.Number, "施法后延迟", DEFAULTS.delayAfterSpell)
            local opts = Settings.CreateSliderOptions(0, 10, 0.5)
            local Lbl = _G.MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
            if Lbl and opts.SetLabelFormatter then
                opts:SetLabelFormatter(Lbl.Right, function(v)
                    return string.format("%.1f 秒", v)
                end)
            end
            Settings.CreateSlider(category, s, opts,
                "施放非坐骑法术后等待多久才自动召唤坐骑（避免打断施法）。")
        end

        ----------------------------------------------------------------
        AddHeader("指定坐骑偏好（仅 fastest 模式生效）")

        if canProxy and canDrop then
            local SLOTS = {
                { key = "ground",  label = "地面环境" },
                { key = "flying",  label = "飞行环境（含御空）" },
                { key = "aquatic", label = "水下环境" },
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
                    c:Add("auto", "自动（按权重表挑最快）")
                    c:Add("none", "不骑坐骑（该环境不自动召唤）")
                    if C_MountJournal and C_MountJournal.GetMountIDs then
                        local mounts = {}
                        for _, id in pairs(C_MountJournal.GetMountIDs()) do
                            local name, _, _, _, _, _, isFavorite, _, _, _, isCollected =
                                C_MountJournal.GetMountInfoByID(id)
                            if isCollected then
                                mounts[#mounts + 1] = {
                                    id = id, name = name or ("坐骑" .. id), fav = isFavorite,
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
                Settings.CreateDropdown(category, s, GetOptions,
                    "指定该环境下优先召唤的坐骑：选「自动」按权重表挑最快；"
                    .. "选具体坐骑则固定优先召它（须已收集）。")
            end
        end

        ----------------------------------------------------------------
        AddHeader("工具")

        if canBtn then
            layout:AddInitializer(CreateSettingsButtonInitializer(
                "输出诊断到聊天框", "查看收藏与状态",
                function()
                    Print(StatusText())
                    ListFavorites()
                end,
                "把当前配置、收藏坐骑构成与「只召某几只」的诊断信息打印到聊天框。", true))

            layout:AddInitializer(CreateSettingsButtonInitializer(
                "打开按键设置", "设置 ALT+Z 等快捷键",
                function()
                    if Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
                        Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
                    end
                end,
                "在「按键设置 → 插件」里查看或修改本插件的开关键（默认 ALT+Z）。", true))

            layout:AddInitializer(CreateSettingsButtonInitializer(
                "恢复默认设置", "重置全部选项",
                function()
                    ApplyDefaults()
                    UpdateEnabled()
                    if SettingsPanel and SettingsPanel.Refresh then SettingsPanel:Refresh() end
                    Print("已恢复默认 · " .. StatusText())
                end,
                "把开关、延迟、模式与所有坐骑偏好恢复为出厂默认。", true))
        end

        Settings.RegisterAddOnCategory(category)
    end)

    if not ok then
        Print("设置面板创建失败（不影响使用，可用 /am 命令配置）：" .. tostring(err))
    end
end

--====================== 快捷键开关（默认 ALT+Z） ======================--

BINDING_HEADER_AUTOMOUNTLITE      = "AutoMountLite"
BINDING_NAME_AUTOMOUNTLITE_TOGGLE = "开/关 自动上坐骑"

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
        Print("已将开关快捷键迁移为「插件」具名绑定：ALT+Z")
        return
    end
    if occupied and occupied ~= "" then
        if not db.bindingWarned then
            db.bindingWarned = true
            Print("ALT+Z 已被占用，未自动绑定；可到「按键设置 → 插件」里手动设置开关快捷键")
        end
        return
    end

    SetBinding("ALT-Z", BINDING_ID)
    SaveBindings(GetCurrentBindingSet())
    Print("已设置默认开关快捷键：ALT+Z（可在「按键设置 → 插件」里修改）")
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
        BuildSettingsPanel()

    elseif event == "PLAYER_LOGIN" then
        if math.randomseed then math.randomseed(time()) end
        RebuildMountSpells()
        EnsureDefaultBinding()
        UpdateEnabled()
        Print("已加载 · " .. StatusText() .. "（Alt+Z 开/关 · /am 查看命令）")

    elseif event == "NEW_MOUNT_ADDED" then
        RebuildMountSpells()

    elseif event == "PLAYER_ENTERING_WORLD" then
        lastMapUpdate = GetTime()
        RebuildMountSpells()

    else -- ZONE_CHANGED*
        lastMapUpdate = GetTime()
    end
end)
