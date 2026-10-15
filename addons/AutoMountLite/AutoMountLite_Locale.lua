-- AutoMountLite_Locale.lua
-- 界面语言表：简体中文(zhCN) + English(enUS)。
-- 由 AutoMountLite.lua 引用，主文件里所有面向用户的文字一律走 AutoMountLiteLocale.T(key)。
--
-- 约定：
--   1. 两张表的 key 必须完全一致（缺 key 的一方会自动回退到 enUS，但那是兜底不是许可）。
--   2. 需要插值的文案用 %s/%d 占位，调用处 T("key", a, b)。
--   3. 语言码对齐 WoW GetLocale()："zhCN"=简体，"zhTW"=繁体，"enUS"/"enGB"=英语。
--      zhTW 暂复用简体文案（暴雪繁体客户端用户看简体可懂，后续可补独立繁体表）。
--   4. 本文件只放文案，不放逻辑；加新语言只需在这里加一张表 + 在 LOCALES 注册。

local ADDON = "AutoMountLite"

local ZH_CN = {
    ---------------------------------------------------------- 环境描述
    env_water       = "水下",
    env_adv         = "史诗飞行区(御空坐骑权重最高)",
    env_fly         = "可飞区(普通飞行)",
    env_ground      = "不可飞区(地面)",

    ---------------------------------------------------------- 坐骑类型名
    type_advflying  = "御空",
    type_flying     = "飞行",
    type_ground     = "地面",
    type_aquatic    = "水下",
    type_other      = "其它",

    ---------------------------------------------------------- 通用
    yes             = "是",
    no              = "否",
    api_unavailable = "坐骑图鉴 API 不可用",
    mount_fallback  = "坐骑%d",

    ---------------------------------------------------------- /am favs
    favs_header     = "收藏坐骑 %d 只（random 模式只在这些里面随机）：",
    favs_group      = "  [%s] %d 只: %s%s",
    favs_empty      = "  [%s] 0 只",
    favs_more       = " …等 %d 只",
    favs_unknown    = "收藏中有未识别类型: %s（请联系插件作者补充映射）",
    favs_unknown_each = "类型%d×%d",
    favs_collected  = "已收集坐骑共 %d 只（%s）",
    favs_none       = "你还没有收藏任何坐骑。random 模式调用暴雪「随机召唤偏好坐骑」，没有收藏时的行为由客户端决定。",
    favs_hint       = "提示：/am pref 偏好设置只在 fastest 模式生效；random 模式改收藏构成（坐骑图鉴点星星）才能改变随机池。",

    ---------------------------------------------------------- /am diag
    diag_header     = "诊断 · 星标收藏 %d 只 | 当前区域【可用】%d 只 | 【不可用】%d 只",
    diag_env        = "环境：可飞=%s 御空=%s 水下=%s  —— random 只从「可用」里随机",
    diag_usable     = "可用",
    diag_blocked    = "不可用",
    diag_api        = "召唤API：SummonByID=%s（0=随机收藏） SummonRandomFavoriteMount=%s",
    api_ok          = "可用",
    api_missing     = "缺失",
    diag_pool       = "权重最高候选池 %d 只（旧版 random 实际只召这里面的）: %s%s",
    diag_no_usable  = "当前区域没有任何可用的星标收藏坐骑 → random 模式会无坐骑可召。",
    diag_few_usable = "可用池只有 %d 只 → 这就是「只召这几只」的原因。",
    diag_line       = "%s(ID:%d,类型%s/%d)",

    ---------------------------------------------------------- /am status
    status_line     = "开关=%s  施法后延迟=%.1fs  模式=%s  地面=%s 飞行=%s 水下=%s  环境=%s",
    on              = "开",
    off             = "关",
    pref_auto       = "自动",
    pref_none       = "不骑",
    pref_id         = "ID:%d",

    ---------------------------------------------------------- 命令反馈
    msg_enabled     = "已开启",
    msg_enabled_toggle = "已开启（自动上坐骑）",
    msg_disabled    = "已关闭",
    msg_delay       = "施法后延迟 = %.1fs",
    msg_mode        = "模式 = %s",
    msg_pref_set    = "%s = %s",
    msg_reset       = "已恢复默认 · %s",
    msg_loaded      = "已加载 · %s（Alt+Z 开/关 · /am 查看命令）",
    note_pref_mode  = "注意：偏好设置只在 fastest 模式生效；当前是 random 模式，输入 /am mode fastest 切换",
    usage_delay     = "用法: /am delay <0-10>",
    usage_mode      = "用法: /am mode fastest|random",
    usage_pref      = "用法: /am pref <ground|flying|aquatic> auto|none|坐骑ID",
    usage_lang      = "用法: /am lang auto|zhCN|enUS",
    slot_ground     = "地面",
    slot_flying     = "飞行",
    slot_aquatic    = "水下",

    ---------------------------------------------------------- 命令帮助
    help_title      = "命令：",
    help_toggle     = "  /am                      切换 开/关",
    help_onoff      = "  /am on | /am off          开启 / 关闭",
    help_status     = "  /am status               查看状态",
    help_favs       = "  /am favs                 按类型列出收藏坐骑（名称+ID，诊断随机池）",
    help_diag       = "  /am diag                 诊断星标收藏在当前区域的可用性（解释只召某几只）",
    help_delay      = "  /am delay <0-10>         施法后延迟秒数",
    help_mode       = "  /am mode fastest|random  最快坐骑 / 随机召唤偏好坐骑",
    help_pref       = "  /am pref <ground|flying|aquatic> auto|none|坐骑ID",
    help_reset      = "  /am reset                恢复默认",
    help_lang       = "  /am lang auto|zhCN|enUS  界面语言：跟随客户端 / 简体中文 / English",
    help_binding    = "  快捷键：ALT+Z 直接 开/关（可在「按键设置 → 插件」里修改）",

    ---------------------------------------------------------- 快捷键绑定
    binding_name        = "开/关 自动上坐骑",
    binding_migrated    = "已将开关快捷键迁移为「插件」具名绑定：ALT+Z",
    binding_occupied    = "ALT+Z 已被占用，未自动绑定；可到「按键设置 → 插件」里手动设置开关快捷键",
    binding_set         = "已设置默认开关快捷键：ALT+Z（可在「按键设置 → 插件」里修改）",

    ---------------------------------------------------------- 界面语言
    dd_lang             = "界面语言",
    dd_lang_auto        = "跟随客户端",
    dd_lang_zhCN        = "简体中文",
    dd_lang_enUS        = "English",
    dd_lang_tip         = "切换界面语言。下拉选项、聊天框输出即时生效；设置面板里的标题文字需要 /reload 后刷新。",
    msg_lang            = "界面语言 = %s",
    msg_lang_reload     = "界面语言已切换为「%s」。设置面板中的标题文字需 /reload 后刷新，其余即时生效。",
    lang_name_auto      = "跟随客户端",
    lang_name_zhCN      = "简体中文",
    lang_name_enUS      = "English",

    ---------------------------------------------------------- 设置面板
    panel_title      = "自动上坐骑",
    panel_error     = "设置面板创建失败（不影响使用，可用 /am 命令配置）：%s",
    cb_enabled      = "启用自动上坐骑",
    cb_enabled_tip  = "开启后：你落地静止时自动召唤坐骑。（快捷键 ALT+Z 或 /am 也可快速开关）",
    dd_mode         = "召唤模式",
    dd_mode_random  = "随机召唤偏好坐骑（从星标收藏里随机 · 推荐）",
    dd_mode_fastest = "环境内最快坐骑（按权重表挑选）",
    dd_mode_tip     = "random：与坐骑图鉴的「随机召唤偏好坐骑」按钮行为完全一致，只从你的星标收藏里随机。\n"
                      .. "fastest：按当前环境（御空 / 可飞 / 地面 / 水下）权重表挑最快坐骑，"
                      .. "可用下方「指定坐骑偏好」精确控制。",
    slider_delay    = "施法后延迟",
    slider_fmt      = "%.1f 秒",
    slider_tip      = "施放非坐骑法术后等待多久才自动召唤坐骑（避免打断施法）。",
    header_pref     = "指定坐骑偏好（仅 fastest 模式生效）",
    slot_label_ground  = "地面环境",
    slot_label_flying  = "飞行环境（含御空）",
    slot_label_aquatic = "水下环境",
    opt_auto        = "自动（按权重表挑最快）",
    opt_none        = "不骑坐骑（该环境不自动召唤）",
    dd_pref_tip     = "指定该环境下优先召唤的坐骑：选「自动」按权重表挑最快；"
                      .. "选具体坐骑则固定优先召它（须已收集）。",
    header_tools    = "工具",
    btn_diag        = "输出诊断到聊天框",
    btn_diag_desc   = "查看收藏与状态",
    btn_diag_tip    = "把当前配置、收藏坐骑构成与「只召某几只」的诊断信息打印到聊天框。",
    btn_keys        = "打开按键设置",
    btn_keys_desc   = "设置 ALT+Z 等快捷键",
    btn_keys_tip    = "在「按键设置 → 插件」里查看或修改本插件的开关键（默认 ALT+Z）。",
    btn_reset       = "恢复默认设置",
    btn_reset_desc  = "重置全部选项",
    btn_reset_tip   = "把开关、延迟、模式与所有坐骑偏好恢复为出厂默认。",
}

local EN_US = {
    ---------------------------------------------------------- Environment text
    env_water       = "Underwater",
    env_adv         = "Advanced flying area (skyriding preferred)",
    env_fly         = "Flyable area (flying)",
    env_ground      = "No-fly area (ground)",

    ---------------------------------------------------------- Mount type names
    type_advflying  = "Skyriding",
    type_flying     = "Flying",
    type_ground     = "Ground",
    type_aquatic    = "Aquatic",
    type_other      = "Other",

    ---------------------------------------------------------- Common
    yes             = "Yes",
    no              = "No",
    api_unavailable = "Mount Journal API unavailable",
    mount_fallback  = "Mount %d",

    ---------------------------------------------------------- /am favs
    favs_header     = "%d favorite mounts (random mode picks only from these):",
    favs_group      = "  [%s] %d mounts: %s%s",
    favs_empty      = "  [%s] 0 mounts",
    favs_more       = " ...and %d more",
    favs_unknown    = "Unrecognized types among favorites: %s (please report to the addon author)",
    favs_unknown_each = "type %d x%d",
    favs_collected  = "%d collected mounts (%s)",
    favs_none       = "You have no favorite mounts yet. Random mode calls Blizzard's \"Summon Random Favorite Mount\"; behavior with none is up to the client.",
    favs_hint       = "Tip: /am pref only applies in fastest mode. In random mode, change your favorites (stars in the Mount Journal) to change the pool.",

    ---------------------------------------------------------- /am diag
    diag_header     = "Diagnostics - %d favorites | %d usable here | %d not usable",
    diag_env        = "Environment: flyable=%s skyriding=%s underwater=%s - random picks only from usable",
    diag_usable     = "Usable",
    diag_blocked    = "Not usable",
    diag_api        = "Summon API: SummonByID=%s (0=random favorite) SummonRandomFavoriteMount=%s",
    api_ok          = "available",
    api_missing     = "missing",
    diag_pool       = "Top-weight pool %d mounts (what old random mode summoned): %s%s",
    diag_no_usable  = "No usable favorite mounts in this area - random mode cannot summon.",
    diag_few_usable = "Only %d usable - that's why you always see the same few.",
    diag_line       = "%s(ID:%d, %s type %s/%d)",

    ---------------------------------------------------------- /am status
    status_line     = "Enabled=%s  delay after spell=%.1fs  mode=%s  ground=%s flying=%s aquatic=%s  env=%s",
    on              = "On",
    off             = "Off",
    pref_auto       = "Auto",
    pref_none       = "None",
    pref_id         = "ID:%d",

    ---------------------------------------------------------- Command feedback
    msg_enabled     = "Enabled",
    msg_enabled_toggle = "Enabled (auto mount)",
    msg_disabled    = "Disabled",
    msg_delay       = "Delay after spell = %.1fs",
    msg_mode        = "Mode = %s",
    msg_pref_set    = "%s = %s",
    msg_reset       = "Defaults restored - %s",
    msg_loaded      = "Loaded - %s (Alt+Z toggles - /am for commands)",
    note_pref_mode  = "Note: mount preferences only apply in fastest mode. Current mode is random - type /am mode fastest to switch.",
    usage_delay     = "Usage: /am delay <0-10>",
    usage_mode      = "Usage: /am mode fastest|random",
    usage_pref      = "Usage: /am pref <ground|flying|aquatic> auto|none|mountID",
    usage_lang      = "Usage: /am lang auto|zhCN|enUS",
    slot_ground     = "Ground",
    slot_flying     = "Flying",
    slot_aquatic    = "Underwater",

    ---------------------------------------------------------- Command help
    help_title      = "Commands:",
    help_toggle     = "  /am                      toggle on / off",
    help_onoff      = "  /am on | /am off         enable / disable",
    help_status     = "  /am status               show current status",
    help_favs       = "  /am favs                 list favorite mounts by type (with IDs)",
    help_diag       = "  /am diag                 diagnose favorite availability in this area",
    help_delay      = "  /am delay <0-10>         delay after spellcasting",
    help_mode       = "  /am mode fastest|random  fastest mount / random favorite mount",
    help_pref       = "  /am pref <ground|flying|aquatic> auto|none|mountID",
    help_reset      = "  /am reset                restore defaults",
    help_lang       = "  /am lang auto|zhCN|enUS  interface language: follow client / Chinese / English",
    help_binding    = "  Hotkey: ALT+Z toggles on/off (rebind in Key Bindings -> AddOns)",

    ---------------------------------------------------------- Key binding
    binding_name        = "Toggle Auto Mount",
    binding_migrated    = "Toggle key migrated to the named AddOn binding: ALT+Z",
    binding_occupied    = "ALT+Z is already bound - set the toggle key manually in Key Bindings -> AddOns",
    binding_set         = "Default toggle key set: ALT+Z (changeable in Key Bindings -> AddOns)",

    ---------------------------------------------------------- Interface language
    dd_lang             = "Interface language",
    dd_lang_auto        = "Follow client",
    dd_lang_zhCN        = "Simplified Chinese",
    dd_lang_enUS        = "English",
    dd_lang_tip         = "Change the interface language. Dropdowns and chat output apply immediately; headings in the options panel refresh after /reload.",
    msg_lang            = "Interface language = %s",
    msg_lang_reload     = "Language set to \"%s\". Headings in the options panel refresh after /reload; everything else applies immediately.",
    lang_name_auto      = "Follow client",
    lang_name_zhCN      = "Simplified Chinese",
    lang_name_enUS      = "English",

    ---------------------------------------------------------- Options panel
    panel_title      = "Auto Mount",
    panel_error      = "Options panel failed to load (slash commands still work): %s",
    cb_enabled       = "Enable auto mount",
    cb_enabled_tip   = "When on, your mount is summoned automatically once you stop moving. (ALT+Z or /am also toggles.)",
    dd_mode          = "Summon mode",
    dd_mode_random   = "Random favorite (from starred favorites - recommended)",
    dd_mode_fastest  = "Fastest for area (by weight table)",
    dd_mode_tip      = "random: exactly the same as the \"Summon Random Favorite Mount\" button in the Mount Journal - only your starred favorites.\n"
                       .. "fastest: picks the fastest mount for the current environment (skyriding / flying / ground / underwater) "
                       .. "and can be fine-tuned with the mount preferences below.",
    slider_delay     = "Delay after spell",
    slider_fmt       = "%.1f s",
    slider_tip       = "How long to wait after casting a non-mount spell before summoning (avoids interrupting casts).",
    header_pref      = "Mount preferences (fastest mode only)",
    slot_label_ground  = "Ground",
    slot_label_flying  = "Flying (incl. skyriding)",
    slot_label_aquatic = "Underwater",
    opt_auto         = "Auto (fastest by weight table)",
    opt_none         = "None (never summon in this environment)",
    dd_pref_tip      = "Pick the preferred mount for this environment: \"Auto\" uses the weight table; "
                       .. "a specific mount is always preferred (must be collected).",
    header_tools     = "Tools",
    btn_diag         = "Print diagnostics to chat",
    btn_diag_desc    = "Review favorites and status",
    btn_diag_tip     = "Prints the current config, favorite mount composition and why only some mounts appear.",
    btn_keys         = "Open key bindings",
    btn_keys_desc    = "Set ALT+Z and other hotkeys",
    btn_keys_tip     = "View or change the toggle key in Key Bindings -> AddOns (default ALT+Z).",
    btn_reset        = "Restore defaults",
    btn_reset_desc   = "Reset all options",
    btn_reset_tip    = "Restores the toggle, delay, mode and all mount preferences to defaults.",
}

--====================== 语言模块 ======================--
-- 全局表 AutoMountLiteLocale：主文件通过它取文案。
--   SetLang(code)：code = "auto"(跟随 GetLocale) | "zhCN" | "enUS"
--   T(key, ...)：取当前语言文案；当前语言缺该 key 时回退 enUS，再缺则返回 key 本身
--                 （返回 key 是为了让漏翻译在测试里暴露，而不是静默显示空白）
--   GetLang()：返回当前生效的语言码

local M = {}

M.enUS = EN_US
M.zhCN = ZH_CN

-- 语言别名：把暴雪的语言码收敛到我们有的表
local ALIAS = {
    zhCN = "zhCN", zhTW = "zhCN", zhSG = "zhCN",
    enUS = "enUS", enGB = "enUS", enMX = "enUS", enAU = "enUS", enNZ = "enUS",
}

M.current = nil   -- 当前生效的文案表
M.code    = nil   -- 当前生效的语言码

function M.SetLang(code)
    code = code or "auto"
    if code == "auto" then
        local loc = "enUS"
        if GetLocale then loc = GetLocale() or "enUS" end
        code = ALIAS[loc] or "enUS"
    else
        code = ALIAS[code] or code
    end
    local table_ = M[code]
    if not table_ then
        -- 未知语言码：回退英文，但记住用户选的码
        table_, code = M.enUS, "enUS"
    end
    M.current = table_
    M.code = code
    return code
end

function M.GetLang()
    return M.code
end

function M.T(key, ...)
    local t = M.current or M.enUS
    local s = t[key]
    if s == nil then s = M.enUS[key] end
    if s == nil then return tostring(key) end
    if select("#", ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        if ok then return out end
        return s .. " (fmt error: " .. tostring(key) .. ")"
    end
    return s
end

-- 加载即按客户端语言初始化（此时 db 还未加载，auto 就是正确默认）
M.SetLang("auto")

AutoMountLiteLocale = M
