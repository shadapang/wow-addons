# -*- coding: utf-8 -*-
"""
AutoMountLite 运行时仿真测试
用 Python mock 整套魔兽 API，把 AutoMountLite.lua 装进 Lua 虚拟机里真跑，
覆盖：/am favs、/am status（环境识别）、random/fastest 选坐骑、权重表、
      pref none 行为、ALT+Z 绑定正文（AutoMountLite_Toggle）、按键自愈迁移。
运行：python test_runtime.py
"""
import os
import sys
from lupa import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS_DIR = os.path.join(HERE, "..", "addons")
LUA_PATH = os.path.join(ADDONS_DIR, "AutoMountLite", "AutoMountLite.lua")

if not os.path.isfile(LUA_PATH):
    raise SystemExit(
        "[错误] 找不到插件源码：%s\n"
        "       仓库已改为 addons/<插件名>/ 布局，确认插件目录还在。" % LUA_PATH
    )

LEGACY_CLICK = "CLICK AutoMountLiteToggleButton:LeftButton"

DEFAULT_MOUNTS = [
    dict(id=1, name="迅捷白马",   type=230, favorite=False, collected=True,  usable=True),
    dict(id=2, name="御空巨龙",   type=402, favorite=True,  collected=True,  usable=True),
    dict(id=3, name="普通狮鹫",   type=248, favorite=True,  collected=True,  usable=True),
    dict(id=4, name="深海海马",   type=231, favorite=True,  collected=True,  usable=True),
    dict(id=5, name="绝版幽灵虎", type=230, favorite=True,  collected=False, usable=True),
    # v1.2.3 回归：424 是较新加入的御空（Dragonriding）类型ID，旧映射表缺它
    dict(id=6, name="午夜幼龙",   type=424, favorite=True,  collected=True,  usable=True),
    # 未知类型ID：验证 favs 会打印原始类型ID供自诊断
    dict(id=7, name="未来坐骑",   type=999, favorite=True,  collected=True,  usable=True),
]


class PyObjectMixin(object):
    """lupa 对 Python 对象的 obj.attr 访问走 getitem 通道，统一转发到 getattr。

    注意：找不到的属性必须返回 None（=Lua nil），不能抛 AttributeError。
    因为真实客户端里插件探测的某些 API 确实【不存在】
    （如 C_MountJournal.SummonRandomFavoriteMount）——若这里抛异常，
    就会掩盖"插件探测了不存在的 API"这类真实缺陷（v1.2.5 及以前的假绿根因之一）。
    """

    def __getitem__(self, key):
        return getattr(self, key, None)


class Frame(PyObjectMixin):
    def __init__(self, world, ftype, name=None):
        self._w = world
        self.ftype = ftype
        self.name = name

    def RegisterEvent(self, ev):
        pass

    def RegisterForClicks(self, *a):
        pass

    def SetSize(self, *a):
        pass

    def SetPoint(self, *a):
        pass

    def SetScript(self, script, fn):
        if script == "OnEvent":
            self._w.event_handler = fn
        elif script == "OnClick":
            self._w.click_handler = fn

    def IsVisible(self):
        return False

    def Cancel(self):
        self._w.ticker_cancelled = True

    def __getattr__(self, item):
        def noop(*a, **k):
            return None
        return noop


class MountJournal(PyObjectMixin):
    def __init__(self, world):
        self._w = world

    def GetMountIDs(self):
        # lupa 不会把 Python list 转成 Lua table，必须显式构造
        return self._w._lua.table_from([m["id"] for m in self._w.mounts])

    def _find(self, mid):
        for m in self._w.mounts:
            if m["id"] == mid:
                return m
        return None

    def GetMountInfoByID(self, mid):
        m = self._find(mid)
        if not m:
            return None
        return (m["name"], 1000 + mid, "icon", False, m["usable"], 1,
                m["favorite"], False, None, False, m["collected"])

    def GetMountInfoExtraByID(self, mid):
        m = self._find(mid)
        if not m:
            return None
        return (1, "desc", "src", True, m["type"])

    def SummonByID(self, mid):
        # mid == 0 → 暴雪「随机召唤偏好坐骑」（= 坐骑图鉴那个按钮的同一个调用）
        #          官方：API:C_MountJournal.SummonByID "0 to summon a random favorite
        #          mount appropriate to the current area"
        # mid  > 0 → 召唤指定坐骑
        if mid == 0:
            self._w.byid0_calls += 1
            if getattr(self._w, "byid0_errors", False):
                raise RuntimeError("SummonByID(0) blocked (simulated protected call)")
        self._w.summoned.append(mid)
        self._w.mounted = True

    # ⚠️ 刻意【不实现】SummonRandomFavoriteMount：
    #    真实客户端 C_MountJournal 命名空间（50 个函数，官方 MountJournalDocumentation.lua）
    #    里【没有】这个函数。v1.1.0~v1.2.5 的 AutoMountLite 正是调用它 → if 恒假 →
    #    每次掉进"最快坐骑"权重兜底，导致"random 模式只召固定那几只"。
    #    这里保持缺失，才能让测试覆盖到这个真机场景（之前的假绿就是因为它被 mock 出来了）。


class Auras(PyObjectMixin):
    def GetBuffDataByIndex(self, *a):
        return None

    def GetDebuffDataByIndex(self, *a):
        return None


class PetBattles(PyObjectMixin):
    def IsInBattle(self):
        return False


class Ticker(PyObjectMixin):
    def __init__(self, world, fn):
        self._w = world
        self._fn = fn

    def Cancel(self):
        self._w.ticker_cancelled = True


class Timer(PyObjectMixin):
    def __init__(self, world):
        self._w = world

    def NewTicker(self, interval, fn):
        self._w.ticker_fn = fn
        return Ticker(self._w, fn)


class UIParent(PyObjectMixin):
    pass


# ===================== 暴雪 Settings API（设置面板）仿真 =====================
# 用于验证 v1.3.0 的「选项 → 插件」可视化面板真的按正确签名注册了控件，
# 以及三处坐骑偏好下拉框的 get/set 映射（auto / none / 坐骑ID）是否正确。
# 参考实现：本机 MinimapButtonButton/Settings/SettingsMenu.lua 与 GSE_Options/Options.lua。

# 注意（lupa 坑）：Lua 的 `obj:Method(x)` 会额外把 obj 作为第一个实参传进 Python，
# 而 `obj.Method(x)` 不会。暴雪 Settings API 全部用冒号调用（旧代码的 C_MountJournal
# 全是点号，所以此前没踩到）。这里统一用 *a 兼容两种调用形式。
class VarTypes(PyObjectMixin):
    Boolean = "boolean"
    Number = "number"
    String = "string"


class SettingsLayout(PyObjectMixin):
    def __init__(self, world):
        self._w = world
        self.initializers = []

    def AddInitializer(self, *a):
        self.initializers.append(a[-1])


class SettingsCategory(PyObjectMixin):
    def __init__(self, world, name):
        self._w = world
        self.name = name
        self.layout = SettingsLayout(world)

    def GetID(self, *a):
        return self.name


class SettingsSetting(PyObjectMixin):
    """一个设置项。kind="table"（自动读写表键）或 "proxy"（自定义 get/set）。"""

    def __init__(self, world, kind, key, name, default, get_value=None, set_value=None):
        self._w = world
        self.kind = kind
        self.key = key
        self.name = name
        self.default = default
        self.get_value = get_value
        self.set_value = set_value
        self.change_cb = None

    def SetValueChangedCallback(self, *a):
        self.change_cb = a[-1]


class SettingsControlTextContainer(PyObjectMixin):
    def __init__(self, world):
        self._w = world
        self.items = []

    def Add(self, *a):
        # 冒号调用 → (obj, value, text)；点号调用 → (value, text)
        self.items.append((a[-2], a[-1]))

    def GetData(self, *a):
        # 真实 API 返回一个数据表；测试只关心"加了哪些选项"，记到 world 上即可
        self._w.settings_options = list(self.items)
        return None


class SliderOptions(PyObjectMixin):
    def __init__(self, mn, mx, step):
        self.min = mn
        self.max = mx
        self.step = step
        self.formatter = None

    def SetLabelFormatter(self, *a):
        self.formatter = (a[-2], a[-1]) if len(a) >= 2 else (a[-1], None)


class SliderLabels(PyObjectMixin):
    Right = "Right"
    Left = "Left"
    Both = "Both"


class MinimalSliderMixin(PyObjectMixin):
    Label = SliderLabels()


class SettingsMock(PyObjectMixin):
    KEYBINDINGS_CATEGORY_ID = 5

    def __init__(self, world):
        self._w = world
        self.VarType = VarTypes()
        self.categories = []
        self.addon_categories = []
        self.settings = []
        self.checkboxes = []
        self.sliders = []
        self.dropdowns = []          # [(setting, getOptions)]
        self.headers = []
        self.opened = []

    # ---- 注册 ----
    def RegisterVerticalLayoutCategory(self, name):
        if not name:
            raise ValueError("category name required")
        cat = SettingsCategory(self._w, name)
        self.categories.append(cat)
        return cat, cat.layout

    def RegisterAddOnCategory(self, cat):
        self.addon_categories.append(cat)

    def RegisterAddOnSetting(self, category, variable, variable_key, table, var_type, name, default):
        if not variable_key:
            raise ValueError("variableKey required")
        s = SettingsSetting(self._w, "table", variable_key, name, default)
        self.settings.append(s)
        return s

    def RegisterProxySetting(self, category, setting_id, var_type, name, default, get_value, set_value):
        s = SettingsSetting(self._w, "proxy", setting_id, name, default, get_value, set_value)
        self.settings.append(s)
        return s

    # ---- 控件 ----
    def CreateCheckbox(self, category, setting, tooltip=None):
        if setting is None:
            raise ValueError("checkbox needs a setting")
        self.checkboxes.append(setting)

    def CreateSliderOptions(self, mn, mx, step=1):
        return SliderOptions(mn, mx, step)

    def CreateSlider(self, category, setting, options, tooltip=None):
        if setting is None or options is None:
            raise ValueError("slider needs setting + options")
        self.sliders.append((setting, options))

    def CreateControlTextContainer(self):
        return SettingsControlTextContainer(self._w)

    def CreateDropdown(self, category, setting, get_options, tooltip=None):
        if setting is None or get_options is None:
            raise ValueError("dropdown needs setting + getOptions")
        self.dropdowns.append((setting, get_options))

    def CreateElementInitializer(self, template, data):
        self.headers.append(data)
        return ("header", data)

    def OpenToCategory(self, cat_id, *a):
        self.opened.append(cat_id)


class SettingsPanelMock(PyObjectMixin):
    def __init__(self, world):
        self._w = world

    def GetLayout(self, *a):
        return a[-1].layout

    def Refresh(self, *a):
        self._w.settings_refreshed = True


class World(object):
    """可操控的假魔兽世界"""

    def __init__(self):
        self.clock = 1000.0
        self.prints = []
        self.locale = "zhCN"        # 客户端语言码（v1.4.0 界面语言）
        self.area = {"adv": True, "fly": True, "swim": False}
        self.mounts = [dict(m) for m in DEFAULT_MOUNTS]
        self.summoned = []           # SummonByID 的实参记录（0 = 随机收藏）
        self.byid0_calls = 0         # SummonByID(0) 调用次数
        self.byid0_errors = False    # True = 模拟 SummonByID(0) 被保护/报错
        self.bindings = {}       # action -> key   （GetBindingKey）
        self.key_actions = {}    # key -> action   （GetBindingAction）
        self.set_binding_calls = []
        self.ticker_fn = None
        self.ticker_cancelled = False
        self.event_handler = None
        self.click_handler = None
        self.loot_open = False
        self.casting = None      # None=没在施法；否则=正在施放的法术ID
        self.mounted = False     # 召唤后置真，模拟"已上坐骑"
        self._lua = None         # make_world 里注入，用于构造 Lua table
        # ---- v1.3.0 设置面板 ----
        self.settings = None            # SettingsMock 实例
        self.settings_buttons = []      # CreateSettingsButtonInitializer 调用记录
        self.settings_options = []      # 最近一次下拉框收集到的选项 [(value, text)]
        self.settings_refreshed = False # SettingsPanel:Refresh 是否被调用

    # ---- 时间 ----
    def GetTime(self):
        self.clock += 0.5
        return self.clock

    def bump(self, seconds):
        self.clock += seconds

    # ---- 输出 ----
    def print(self, *args):
        self.prints.append(" ".join(str(a) for a in args))

    def out(self):
        return "\n".join(self.prints)

    # ---- 帧/UI ----
    def CreateFrame(self, ftype, name=None, parent=None):
        return Frame(self, ftype, name)

    # ---- 坐骑 ----
    def IsFlyableArea(self):
        return self.area["fly"]

    def IsAdvancedFlyableArea(self):
        return self.area["adv"]

    def IsSubmerged(self):
        return self.area["swim"]

    def IsSwimming(self):
        return self.area["swim"]

    # ---- 状态守卫（默认全部“安全”）----
    def IsFlying(self): return False
    def IsPlayerMoving(self): return False
    def IsIndoors(self): return False
    def IsMounted(self): return self.mounted
    def IsFalling(self): return False
    def UnitIsDead(self, u): return False
    def UnitIsGhost(self, u): return False
    def UnitAffectingCombat(self, u): return False
    def UnitIsFeignDeath(self, u): return False
    def UnitOnTaxi(self, u): return False
    def UnitInVehicle(self, u): return False
    def UnitUsingVehicle(self, u): return False
    def GetNumLootItems(self): return 0
    def GetShapeshiftForm(self): return 0
    def GetMirrorTimerInfo(self, i): return ""

    def UnitCastingInfo(self, u):
        if not self.casting:
            return None
        # 12.x 返回值顺序（官方 API 文档 UnitCastingInfo）：
        # name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill,
        # castID, notInterruptible, castingSpellID, castBarID, delayTimeMs
        # ⚠️ castingSpellID 是【第 9 个】；第 10 个是 castBarID —— 旧代码 select(10)
        # 误取到 castBarID，导致 IsCastingMountSpell() 恒 false、防抖失效。
        return ("法术", "法术", 1, 0, 1000, False, "Cast-1", False,
                self.casting, 77, 0)

    def UnitClass(self, u):
        return ("WARRIOR", "Warrior", "human")

    # ---- 按键绑定 ----
    def GetBindingKey(self, action):
        return self.bindings.get(action) or ""

    def GetBindingAction(self, key):
        return self.key_actions.get(key) or ""

    def SetBinding(self, key, action):
        self.set_binding_calls.append((key, action))
        self.key_actions[key] = action

    def SaveBindings(self, binding_set):
        pass

    def GetCurrentBindingSet(self):
        return 1


def make_world(area=None, mounts=None, key_actions=None, bindings=None,
               omit_byid=False, byid0_errors=False, no_settings=False, locale="zhCN"):
    w = World()
    w.locale = locale
    if area:
        w.area.update(area)
    if mounts is not None:
        w.mounts = mounts
    if key_actions:
        w.key_actions.update(key_actions)
    if bindings:
        w.bindings.update(bindings)
    w.byid0_errors = byid0_errors

    lua = LuaRuntime(unpack_returned_tuples=True)
    w._lua = lua
    g = lua.globals()
    # 客户端提供的全局表，裸 Lua 里不存在，需预建
    lua.execute("SlashCmdList = {}")
    mj = MountJournal(w)
    if omit_byid:
        # 极端客户端：连 SummonByID 都没有 → 插件必须优雅降级（不抛错）
        mj.SummonByID = None
    mocks = {
        "print": w.print,
        "GetTime": w.GetTime,
        "time": lambda: int(w.clock),   # WoW 提供的全局 time()，lupa 没有
        "GetLocale": lambda: w.locale,  # v1.4.0 界面语言：客户端语言码
        "CreateFrame": w.CreateFrame,
        "UIParent": UIParent(),
        "C_Timer": Timer(w),
        "C_MountJournal": mj,
        "C_UnitAuras": Auras(),
        "C_PetBattles": PetBattles(),
        "IsFlyableArea": w.IsFlyableArea,
        "IsAdvancedFlyableArea": w.IsAdvancedFlyableArea,
        "IsSubmerged": w.IsSubmerged,
        "IsSwimming": w.IsSwimming,
        "IsFlying": w.IsFlying,
        "IsPlayerMoving": w.IsPlayerMoving,
        "IsIndoors": w.IsIndoors,
        "IsMounted": w.IsMounted,
        "IsFalling": w.IsFalling,
        "UnitIsDead": w.UnitIsDead,
        "UnitIsGhost": w.UnitIsGhost,
        "UnitAffectingCombat": w.UnitAffectingCombat,
        "UnitIsFeignDeath": w.UnitIsFeignDeath,
        "UnitOnTaxi": w.UnitOnTaxi,
        "UnitInVehicle": w.UnitInVehicle,
        "UnitUsingVehicle": w.UnitUsingVehicle,
        "UnitCastingInfo": w.UnitCastingInfo,
        "UnitClass": w.UnitClass,
        "GetNumLootItems": w.GetNumLootItems,
        "GetShapeshiftForm": w.GetShapeshiftForm,
        "GetMirrorTimerInfo": w.GetMirrorTimerInfo,
        "GetBindingKey": w.GetBindingKey,
        "GetBindingAction": w.GetBindingAction,
        "SetBinding": w.SetBinding,
        "SaveBindings": w.SaveBindings,
        "GetCurrentBindingSet": w.GetCurrentBindingSet,
    }
    if not no_settings:
        # v1.3.0：模拟客户端自带的暴雪 Settings API（设置面板用）
        w.settings = SettingsMock(w)
        mocks["Settings"] = w.settings
        mocks["SettingsPanel"] = SettingsPanelMock(w)
        mocks["MinimalSliderWithSteppersMixin"] = MinimalSliderMixin()

        def create_settings_button_initializer(name, desc, onclick, tooltip=None, full_width=None):
            w.settings_buttons.append({
                "name": name, "desc": desc, "onclick": onclick,
                "tooltip": tooltip, "full": full_width,
            })
            return ("button", name)

        mocks["CreateSettingsButtonInitializer"] = create_settings_button_initializer
    for k, v in mocks.items():
        setattr(g, k, v)

    # v1.4.0：Locale 文件先加载（.toc 顺序），主文件里的 T() 才能取到文案
    locale_path = os.path.join(ADDONS_DIR, "AutoMountLite", "AutoMountLite_Locale.lua")
    with open(locale_path, encoding="utf-8") as f:
        lua.execute(f.read())
    with open(LUA_PATH, encoding="utf-8") as f:
        lua.execute(f.read())
    return w, lua


def slash(w, lua, msg):
    fn = lua.globals().SlashCmdList["AUTOMOUNTLITE"]
    fn(msg)


def fire(w, event, *args):
    """WoW 的 OnEvent 处理函数第一个参数是帧自身(self)"""
    w.bump(10)
    w.event_handler(None, event, *args)


def login(w):
    fire(w, "ADDON_LOADED", "AutoMountLite")   # 初始化 db
    fire(w, "PLAYER_LOGIN")                    # 注册快捷键+启动心跳


def tick(w, secs=10):
    w.bump(secs)
    w.ticker_fn()


RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, ok, detail))
    line = "%s %s%s" % ("PASS" if ok else "FAIL", name,
                        ("  -> " + detail) if (detail and not ok) else "")
    print(line)
    with open(os.path.join(HERE, "rt_out.txt"), "a", encoding="utf-8") as f:
        f.write(line + "\n")


def t_favs_basic():
    w, lua = make_world()
    login(w)
    slash(w, lua, "favs")
    o = w.out()
    check("favs.收藏计数=5(排除未收集)", "收藏坐骑 5 只" in o)
    check("favs.御空分组含402和424", "[御空] 2 只: 御空巨龙(ID:2), 午夜幼龙(ID:6)" in o)
    check("favs.飞行分组", "[飞行] 1 只: 普通狮鹫(ID:3)" in o)
    check("favs.水下分组", "[水下] 1 只: 深海海马(ID:4)" in o)
    check("favs.地面空组", "[地面] 0 只" in o)
    check("favs.其它分组", "[其它] 1 只: 未来坐骑(ID:7)" in o)
    check("favs.未识别类型原始ID", "收藏中有未识别类型: 类型999×1" in o)
    check("favs.已收集总数=6", "已收集坐骑共 6 只" in o)
    check("favs.pref提示", "只在 fastest 模式生效" in o)


def t_status_env():
    w, lua = make_world(area={"adv": True, "fly": True, "swim": False})
    login(w)
    slash(w, lua, "status")
    check("status.史诗飞行区", "环境=史诗飞行区(御空坐骑权重最高)" in w.out())

    w2, l2 = make_world(area={"adv": False, "fly": True, "swim": False})
    login(w2)
    slash(w2, l2, "status")
    check("status.可飞区", "环境=可飞区(普通飞行)" in w2.out())

    w3, l3 = make_world(area={"adv": False, "fly": False, "swim": False})
    login(w3)
    slash(w3, l3, "status")
    check("status.不可飞区", "环境=不可飞区(地面)" in w3.out())

    w4, l4 = make_world(area={"adv": True, "fly": True, "swim": True})
    login(w4)
    slash(w4, l4, "status")
    check("status.水中优先", "环境=水下" in w4.out())
    check("status.默认模式random", "模式=random" in w4.out())


def t_random_mode():
    """v1.2.6：random 模式必须调用 C_MountJournal.SummonByID(0) ——
    与坐骑图鉴「随机召唤偏好坐骑」按钮完全同一个调用（0 = 从星标收藏里随机一只
    【当前区域可用】的坐骑）。

    旧版（v1.1.0~v1.2.5）调用的是不存在的 C_MountJournal.SummonRandomFavoriteMount，
    if 恒假 → 掉进权重兜底 → 这就是"random 模式只召固定几只"的真凶。"""
    w, lua = make_world()
    login(w)
    slash(w, lua, "mode random")
    tick(w)
    check("random.调用 SummonByID(0)", w.summoned == [0], str(w.summoned))
    check("random.未走权重兜底（没召具体坐骑ID）", 3 not in w.summoned, str(w.summoned))


def t_random_not_weight_pool_bug():
    """回归真机 Bug（2026-10-13 肖哥实报）：
    收藏很多，但其中只有 2 只是"普通飞行(248)"类型；在 adv+fly 双真区域里，
    权重表是【四个独立 if 依次覆盖】→ 可飞分支的 flying=5 覆盖掉御空分支的 advflying=4，
    收藏再 +0.1 → "权重最高候选池"恰好只剩这 2 只。

    旧版 random 因 API 名写错掉进该兜底分支 → 永远只出这 2 只（症状完全吻合）；
    新版必须走 SummonByID(0)（= 手动点图鉴按钮的同一个调用）。"""
    mounts = [
        dict(id=901, name="炽燃勇鸷", type=248, favorite=True, collected=True, usable=True),
        dict(id=902, name="魅力信使", type=248, favorite=True, collected=True, usable=True),
        dict(id=910, name="御空甲",   type=424, favorite=True, collected=True, usable=True),
        dict(id=911, name="御空乙",   type=424, favorite=True, collected=True, usable=True),
        dict(id=912, name="御空丙",   type=424, favorite=True, collected=True, usable=True),
        dict(id=920, name="地面马",   type=230, favorite=True, collected=True, usable=True),
    ]
    w, lua = make_world(mounts=mounts)          # 默认 adv=True fly=True（史诗飞行区）
    login(w)
    slash(w, lua, "mode random")
    tick(w)
    check("回归.random 走 SummonByID(0)", w.summoned == [0], str(w.summoned))
    check("回归.未掉进权重兜底（没只召 901/902）",
          901 not in w.summoned and 902 not in w.summoned, str(w.summoned))

    # /am diag 必须能揭示"权重池只有 2 只"——这就是真机上的病根现场
    w.prints = []
    slash(w, lua, "diag")
    check("回归.diag 揭示权重最高池=2只", "权重最高候选池 2 只" in w.out(), w.out())
    check("回归.diag 权重池正是那 2 只飞行坐骑",
          "ID:901" in w.out() and "ID:902" in w.out(), w.out())
    check("回归.diag 报出召唤API可用", "召唤API：SummonByID=可用" in w.out(), w.out())


def t_random_fallback_when_byid0_blocked():
    """健壮性：若 SummonByID(0) 被保护/抛错（pcall 捕获），应退回权重兜底而非崩溃。"""
    w, lua = make_world(byid0_errors=True)
    login(w)
    slash(w, lua, "mode random")
    tick(w)
    check("兜底.byid0 报错时退回权重池", w.summoned == [3], str(w.summoned))


def t_casting_spellid_index():
    """v1.2.7：UnitCastingInfo 的 castingSpellID 在现代客户端是【第 9 个】返回值
    （8.0 之后移除了 nameSubtext）；第 10 个是 castBarID。

    旧代码写死 select(10) → 取到 castBarID（数字但不是法术ID）→
      · IsCastingMountSpell() 恒 false → "上坐骑 4 秒防抖"完全失效
      · IsCastingNonMountSpell() 对【任何】施法都返回 true → 连"正在上坐骑"
        也被当成"非坐骑施法"，从而被 delayAfterSpell 拦截

    判别式：正在施放【坐骑法术】时，不该触发"施法后延迟"拦截。
    （mock 里坐骑 ID=3 的法术 ID 是 1003）"""
    w, lua = make_world()
    login(w)
    slash(w, lua, "delay 10")     # 放大延迟窗口，便于区分
    w.casting = 1003              # 正在施放坐骑法术
    tick(w, 1)
    check("施法.坐骑法术期间不召唤", w.summoned == [], str(w.summoned))
    w.casting = None
    tick(w, 5)                    # 已过 4 秒防抖、但仍在 10 秒延迟窗口内
    check("施法.上坐骑本身不算'非坐骑施法'(未被延迟拦截)",
          w.summoned == [0], str(w.summoned))


def t_missing_byid_no_crash():
    """健壮性：极端客户端连 SummonByID 都没有时，必须优雅降级（不抛 Lua 错误）。"""
    w, lua = make_world(omit_byid=True)
    login(w)
    tick(w)
    check("健壮.缺 SummonByID 时不召唤也不报错", w.summoned == [], str(w.summoned))


def t_fastest_adv_area():
    w, lua = make_world(area={"adv": True, "fly": True, "swim": False})
    login(w)
    slash(w, lua, "mode fastest")
    tick(w)
    # 可飞分支后命中：飞行(248)=5 > 御空(402)=4 → 狮鹫(ID:3)胜出
    check("fastest.史诗飞行区召飞行坐骑", w.summoned == [3], str(w.summoned))


def t_fastest_ground_area():
    w, lua = make_world(area={"adv": False, "fly": False, "swim": False})
    login(w)
    slash(w, lua, "mode fastest")
    tick(w)
    # 地面分支：ground=5 → 白马(ID:1)
    check("fastest.不可飞区召地面坐骑", w.summoned == [1], str(w.summoned))


def t_fastest_water():
    w, lua = make_world(area={"adv": False, "fly": False, "swim": True})
    login(w)
    slash(w, lua, "mode fastest")
    tick(w)
    # 水下分支：aquatic=5 → 海马(ID:4)
    check("fastest.水下召水生坐骑", w.summoned == [4], str(w.summoned))


def t_fastest_favorite_bonus():
    # 同速时收藏优先：两只地面坐骑，收藏的那只 +0.1
    mounts = [
        dict(id=10, name="普通马", type=230, favorite=False, collected=True, usable=True),
        dict(id=11, name="收藏马", type=230, favorite=True,  collected=True, usable=True),
    ]
    w, lua = make_world(area={"adv": False, "fly": False, "swim": False}, mounts=mounts)
    login(w)
    slash(w, lua, "mode fastest")
    tick(w)
    check("fastest.收藏+0.1优先", w.summoned == [11], str(w.summoned))


def t_pref_none_flyable_blocks():
    w, lua = make_world(area={"adv": True, "fly": True, "swim": False})
    login(w)
    slash(w, lua, "mode fastest")
    slash(w, lua, "pref flying none")
    tick(w)
    # Dugi 忠实行为：可飞/史诗分支里 pref=none → 所有坐骑权重 nil → 不召唤
    check("pref.飞行区flying=none不召唤", w.summoned == [], str(w.summoned))


def t_pref_none_ground_area_mounts():
    w, lua = make_world(area={"adv": False, "fly": False, "swim": False})
    login(w)
    slash(w, lua, "mode fastest")
    slash(w, lua, "pref flying none")
    tick(w)
    # 地面区不受 flying 偏好影响 → 正常召地面坐骑
    check("pref.地面区flying=none仍召地面", w.summoned == [1], str(w.summoned))


def t_pref_specific_id():
    w, lua = make_world(area={"adv": True, "fly": True, "swim": False})
    login(w)
    slash(w, lua, "mode fastest")
    slash(w, lua, "pref flying 2")   # 指定御空巨龙 → speed=6 最高
    tick(w)
    check("pref.指定ID=6分优先", w.summoned == [2], str(w.summoned))


def t_toggle_binding_body():
    w, lua = make_world()
    login(w)
    toggle = lua.globals().AutoMountLite_Toggle
    toggle()   # 等价于 Bindings.xml 正文被执行（ALT+Z 按下）
    check("binding.正文切换为关闭", "已关闭" in w.out())
    check("binding.关闭后取消心跳", w.ticker_cancelled)
    toggle()
    check("binding.再切为开启", "已开启" in w.out())


def t_binding_migrate_legacy():
    w, lua = make_world(key_actions={"ALT-Z": LEGACY_CLICK})
    login(w)
    check("binding.迁移旧版CLICK绑定",
          w.set_binding_calls == [("ALT-Z", "AUTOMOUNTLITE_TOGGLE")],
          str(w.set_binding_calls))
    check("binding.迁移提示语", "迁移" in w.out())


def t_binding_occupied_warn_once():
    w, lua = make_world(key_actions={"ALT-Z": "TOGGLEAUTORUN"})
    login(w)
    check("binding.占用不抢绑", w.set_binding_calls == [])
    check("binding.占用告警一次", "已被占用" in w.out())
    # 再来一次登录：不应重复告警（bindingWarned 持久化）
    w.prints = []
    login(w)
    check("binding.告警不重复", "已被占用" not in w.out())


def t_binding_already_bound():
    w, lua = make_world(bindings={"AUTOMOUNTLITE_TOGGLE": "ALT-Z"})
    login(w)
    check("binding.已绑定则不动", w.set_binding_calls == [])


def t_binding_fresh_default():
    w, lua = make_world()
    login(w)
    check("binding.空闲时设默认键",
          w.set_binding_calls == [("ALT-Z", "AUTOMOUNTLITE_TOGGLE")],
          str(w.set_binding_calls))


def t_favs_empty():
    mounts = [dict(m) for m in DEFAULT_MOUNTS]
    for m in mounts:
        m["favorite"] = False
    w, lua = make_world(mounts=mounts)
    login(w)
    slash(w, lua, "favs")
    o = w.out()
    check("favs.空收藏提示", "还没有收藏任何坐骑" in o)
    check("favs.空收藏计数0", "收藏坐骑 0 只" in o)


def t_help_and_misc():
    w, lua = make_world()
    login(w)
    slash(w, lua, "xyz")   # 无效命令 → 打印帮助
    check("help.包含favs", "/am favs" in w.out())
    slash(w, lua, "delay 2")
    check("cmd.delay设置", "施法后延迟 = 2.0s" in w.out())
    slash(w, lua, "pref ground 42")
    check("cmd.pref指定ID", "地面 = ID:42" in w.out())
    slash(w, lua, "status")
    check("cmd.status显示指定ID", "地面=ID:42" in w.out())
    slash(w, lua, "delay 99")
    check("cmd.delay越界拒绝", "用法: /am delay" in w.out())
    slash(w, lua, "mode silly")
    check("cmd.mode非法拒绝", "用法: /am mode" in w.out())
    slash(w, lua, "reset")
    check("cmd.reset恢复默认", "已恢复默认" in w.out())
    slash(w, lua, "status")
    check("cmd.reset后delay回1.0", "施法后延迟=1.0s" in w.out())


def t_guards_combat():
    # 脱战 1 秒内不召唤（lastCombatTime 由心跳刷新）
    w, lua = make_world()
    login(w)
    slash(w, lua, "mode fastest")
    w.bump(10)
    w.ticker_fn()                     # 第一次：召唤成功
    check("guard.首次召唤", w.summoned == [3], str(w.summoned))
    w.prints = []
    w.bump(0.2)
    w.ticker_fn()                     # 紧接着：坐骑 CD/上骑守卫内 → 不重复召
    check("guard.连续心跳不重复召", w.summoned == [3], str(w.summoned))


def t_fastest_424_advflying():
    # v1.2.3 回归：纯御空区（adv 真、fly 假）只有御空分支生效：
    # 424 与 402 同属 advflying → 权重 5（收藏 +0.1），压过 248 飞行(4.1)
    mounts = [
        dict(id=20, name="新御空龙", type=424, favorite=True, collected=True, usable=True),
        dict(id=21, name="老御空龙", type=402, favorite=True, collected=True, usable=True),
        dict(id=22, name="普通飞机", type=248, favorite=True, collected=True, usable=True),
        dict(id=23, name="地面马",   type=230, favorite=True, collected=True, usable=True),
    ]
    w, lua = make_world(area={"adv": True, "fly": False, "swim": False}, mounts=mounts)
    login(w)
    slash(w, lua, "mode fastest")
    tick(w)
    # 424 与 402 同权重 5.1，随机取一；但绝不可能是 248/230
    check("fastest.424按御空计权", w.summoned and w.summoned[0] in (20, 21),
          str(w.summoned))


def t_phoenix_only():
    """v1.2.4 场景：肖哥要"只召唤凤凰"（奥的灰烬，mountID=183，type=248 普通飞行）。
    坐骑池模拟他的真实收藏构成：一只凤凰 + 一批御空 + 一只飞机 + 一马一海马，全部收藏。"""
    mounts = [
        dict(id=183, name="奥的灰烬",   type=248, favorite=True,  collected=True, usable=True),
        dict(id=1577, name="御空甲虫", type=424, favorite=True,  collected=True, usable=True),
        dict(id=1291, name="翔龙",     type=424, favorite=True,  collected=True, usable=True),
        dict(id=3,   name="普通狮鹫",   type=248, favorite=True,  collected=True, usable=True),
        dict(id=1,   name="迅捷白马",   type=230, favorite=True,  collected=True, usable=True),
        dict(id=4,   name="深海海马",   type=231, favorite=True,  collected=True, usable=True),
    ]

    # ① 御空区（adv+fly 双真）：pref flying 183 → 183 得 6 分，压过御空 5.1
    w, lua = make_world(area={"adv": True, "fly": True, "swim": False}, mounts=mounts)
    login(w)
    slash(w, lua, "mode fastest")
    slash(w, lua, "pref flying 183")
    tick(w)
    check("凤凰.御空区只召凤凰", w.summoned == [183], str(w.summoned))

    # ② 可飞区（fly only）：同样只召凤凰
    w, lua = make_world(area={"adv": False, "fly": True, "swim": False}, mounts=mounts)
    login(w)
    slash(w, lua, "mode fastest")
    slash(w, lua, "pref flying 183")
    tick(w)
    check("凤凰.可飞区只召凤凰", w.summoned == [183], str(w.summoned))

    # ③ 地面区：flying pref 不生效 → 召白马（凤凰飞不起来），证明地面需单独处理
    w, lua = make_world(area={"adv": False, "fly": False, "swim": False}, mounts=mounts)
    login(w)
    slash(w, lua, "mode fastest")
    slash(w, lua, "pref flying 183")
    tick(w)
    check("凤凰.地面区不受flying pref影响(召白马)", w.summoned == [1], str(w.summoned))

    # ④ 全环境真·只召凤凰：flying 183 + ground none + aquatic none
    #    飞行环境召凤凰；地面/水下一律不自动召
    for env_name, area in (("御空区", {"adv": True,  "fly": True,  "swim": False}),
                           ("可飞区", {"adv": False, "fly": True,  "swim": False}),
                           ("地面区", {"adv": False, "fly": False, "swim": False}),
                           ("水下",   {"adv": False, "fly": False, "swim": True})):
        w, lua = make_world(area=area, mounts=mounts)
        login(w)
        slash(w, lua, "mode fastest")
        slash(w, lua, "pref flying 183")
        slash(w, lua, "pref ground none")
        slash(w, lua, "pref aquatic none")
        tick(w)
        if env_name in ("御空区", "可飞区"):
            check("凤凰.全环境配置-%s召凤凰" % env_name, w.summoned == [183], str(w.summoned))
        else:
            check("凤凰.全环境配置-%s不召唤" % env_name, w.summoned == [], str(w.summoned))

    # ⑤ random 模式下 pref 被完全无视（走暴雪随机收藏），证明必须先切 fastest
    w, lua = make_world(area={"adv": False, "fly": True, "swim": False}, mounts=mounts)
    login(w)
    slash(w, lua, "pref flying 183")   # 不切模式，保持默认 random
    tick(w)
    check("凤凰.random模式pref无效(走随机收藏API)", w.summoned == [0],
          "summoned=%s" % w.summoned)

    # ⑥ 凤凰未收集时不召（collected 守卫），退到其它最快坐骑
    mounts_nc = [dict(m) for m in mounts]
    mounts_nc[0]["collected"] = False
    w, lua = make_world(area={"adv": False, "fly": True, "swim": False}, mounts=mounts_nc)
    login(w)
    slash(w, lua, "mode fastest")
    slash(w, lua, "pref flying 183")
    tick(w)
    check("凤凰.未收集时不召凤凰", w.summoned and w.summoned[0] != 183, str(w.summoned))

    # ⑦ 稳定性：御空区连续心跳只出凤凰（不重复召、不漂移）
    w, lua = make_world(area={"adv": True, "fly": True, "swim": False}, mounts=mounts)
    login(w)
    slash(w, lua, "mode fastest")
    slash(w, lua, "pref flying 183")
    tick(w)
    check("凤凰.御空区首召凤凰", w.summoned == [183], str(w.summoned))


def t_pref_random_mode_warns():
    """v1.2.4：random 模式下设 pref 必须提示切换 fastest（防止"设了没反应"）。"""
    # random 模式（默认）：提示出现
    w, lua = make_world()
    login(w)
    slash(w, lua, "pref flying 183")
    check("pref.random模式提示切换", "只在 fastest 模式生效" in w.out(), w.out())
    check("pref.random模式提示含切换命令", "/am mode fastest" in w.out())
    # fastest 模式：不该出现该提示
    w, lua = make_world()
    login(w)
    slash(w, lua, "mode fastest")
    w.prints = []
    slash(w, lua, "pref flying 183")
    check("pref.fastest模式无多余提示", "只在 fastest 模式生效" not in w.out(), w.out())
    # random 模式恢复 auto 也提示（统一行为）
    w, lua = make_world()
    login(w)
    slash(w, lua, "pref ground auto")
    check("pref.random模式auto也提示", "只在 fastest 模式生效" in w.out(), w.out())


def t_diag_usability():
    """v1.2.5：/am diag 列出星标收藏在当前区域的可用性，解释"只召某几只"。"""
    mounts = [
        dict(id=1247422, name="炽燃勇鸷", type=248, favorite=True, collected=True, usable=True),
        dict(id=443660,  name="魅力信使", type=248, favorite=True, collected=True, usable=True),
        dict(id=183,     name="奥的灰烬", type=248, favorite=True, collected=True, usable=False),
        dict(id=1577,    name="御空甲虫", type=424, favorite=True, collected=True, usable=False),
        dict(id=1,       name="迅捷白马", type=230, favorite=True, collected=True, usable=True),
        dict(id=99,      name="没收藏的", type=248, favorite=False, collected=True, usable=True),
    ]
    w, lua = make_world(area={"adv": True, "fly": True, "swim": False}, mounts=mounts)
    login(w)
    slash(w, lua, "diag")
    o = w.out()
    check("diag.计数正确(5收藏/3可用/2不可用)",
          "星标收藏 5 只" in o and "【可用】3 只" in o and "【不可用】2 只" in o, o)
    check("diag.环境行", "可飞=是" in o and "御空=是" in o, o)
    check("diag.可用组含凤凰之外的可用坐骑", "[可用] 3 只" in o and "炽燃勇鸷(ID:1247422" in o, o)
    check("diag.不可用组含凤凰", "[不可用] 2 只" in o and "奥的灰烬(ID:183" in o, o)
    check("diag.非收藏不出现", "没收藏的" not in o, o)

    # 可用池 ≤2 时给出"这就是只召这几只的原因"提示
    mounts2 = [
        dict(id=1247422, name="炽燃勇鸷", type=248, favorite=True, collected=True, usable=True),
        dict(id=443660,  name="魅力信使", type=248, favorite=True, collected=True, usable=True),
        dict(id=183,     name="奥的灰烬", type=248, favorite=True, collected=True, usable=False),
    ]
    w, lua = make_world(area={"adv": True, "fly": True, "swim": False}, mounts=mounts2)
    login(w)
    slash(w, lua, "diag")
    check("diag.可用池≤2时给出结论提示", "可用池只有 2 只" in w.out(), w.out())

    # 全部可用时不出现该提示
    mounts3 = [dict(m) for m in mounts2]
    for m in mounts3:
        m["usable"] = True
    w, lua = make_world(area={"adv": True, "fly": True, "swim": False}, mounts=mounts3)
    login(w)
    slash(w, lua, "diag")
    check("diag.池子充足无冗余提示", "可用池只有" not in w.out(), w.out())

    # 帮助里列出 diag
    w, lua = make_world()
    login(w)
    slash(w, lua, "zzz")
    check("diag.帮助含diag", "/am diag" in w.out(), w.out())


def t_settings_panel():
    """v1.3.0：可视化设置面板是否按【正确签名】注册（暴雪 Settings API）"""
    w, lua = make_world()
    login(w)
    s = w.settings
    check("设置.注册了AutoMountLite分类",
          any(c.name == "自动上坐骑" for c in s.categories),
          str([c.name for c in s.categories]))
    check("设置.已登记为AddOn分类", len(s.addon_categories) == 1)

    keys = [x.key for x in s.settings]
    check("设置.开关项→enabled", "enabled" in keys, str(keys))
    check("设置.模式项→mode", "mode" in keys)
    check("设置.延迟项→delayAfterSpell", "delayAfterSpell" in keys)
    for k in ("ground", "flying", "aquatic"):
        check("设置.偏好项→pref_%s" % k, ("AutoMountLite_pref_" + k) in keys, str(keys))

    check("设置.复选框1个", len(s.checkboxes) == 1)
    check("设置.滑块1个", len(s.sliders) == 1)
    check("设置.下拉框5个(语言+模式+3偏好)", len(s.dropdowns) == 5, str(len(s.dropdowns)))
    check("设置.分节标题3个", len(s.headers) == 3, str(s.headers))
    check("设置.按钮3个", len(w.settings_buttons) == 3,
          str([b["name"] for b in w.settings_buttons]))
    check("设置.构建无失败提示", "设置面板创建失败" not in w.out(), w.out())

    # 模式下拉框选项
    mode_opts = [d for d in s.dropdowns if d[0].key == "mode"][0][1]
    mode_opts()
    vals = [v for v, _ in w.settings_options]
    check("设置.模式选项=random/fastest", vals == ["random", "fastest"], str(vals))

    # 延迟滑块：0–10 步长 0.5
    slider_setting, slider_opts = s.sliders[0]
    check("设置.滑块绑定delayAfterSpell", slider_setting.key == "delayAfterSpell")
    check("设置.滑块范围0-10步长0.5",
          (slider_opts.min, slider_opts.max, slider_opts.step) == (0, 10, 0.5),
          str((slider_opts.min, slider_opts.max, slider_opts.step)))

    # 「恢复默认设置」按钮 → 真的原地重置 + 刷新面板
    reset_btn = [b for b in w.settings_buttons if b["name"] == "恢复默认设置"][0]
    dbp = lua.globals().AutoMountLiteDB
    dbp["mode"] = "fastest"
    dbp["delayAfterSpell"] = 9
    reset_btn["onclick"]()          # 模拟点击
    check("设置.重置按钮恢复mode=random", dbp["mode"] == "random", str(dbp["mode"]))
    check("设置.重置按钮恢复delay=1.0", abs(dbp["delayAfterSpell"] - 1.0) < 1e-9,
          str(dbp["delayAfterSpell"]))
    check("设置.重置后请求刷新面板", w.settings_refreshed)

    # 「输出诊断」按钮 → 打印状态与收藏
    diag_btn = [b for b in w.settings_buttons if b["name"] == "输出诊断到聊天框"][0]
    w.prints = []
    diag_btn["onclick"]()
    check("设置.诊断按钮输出状态行", "模式=random" in w.out(), w.out())
    check("设置.诊断按钮输出收藏清单", "收藏坐骑" in w.out())


def t_settings_pref_proxy():
    """v1.3.0：三处坐骑偏好下拉框的取/存映射（auto / none / 坐骑ID）"""
    w, lua = make_world()
    login(w)
    s = w.settings
    by_key = {x.key: x for x in s.settings}
    gs = by_key["AutoMountLite_pref_flying"]
    check("设置.偏好初始读回auto", gs.get_value() == "auto", str(gs.get_value()))

    # 下拉框选项：auto + none + 每只【已收集】坐骑（收藏加 ★）
    get_opts = [d for d in s.dropdowns
                if d[0].key == "AutoMountLite_pref_flying"][0][1]
    get_opts()
    vals = [v for v, _ in w.settings_options]
    labels = dict(w.settings_options)
    check("设置.偏好选项前两项=auto/none", vals[:2] == ["auto", "none"], str(vals[:2]))
    check("设置.偏好选项含已收集坐骑ID", "2" in vals and "6" in vals, str(vals))
    check("设置.偏好选项排除未收集坐骑", "5" not in vals, str(vals))
    check("设置.收藏坐骑标★", labels.get("2", "").startswith("★"), str(labels.get("2")))
    check("设置.非收藏坐骑不标★", not labels.get("1", "").startswith("★"),
          str(labels.get("1")))

    # 存/取映射
    dbp = lua.globals().AutoMountLiteDB
    gs.set_value("183")
    check("设置.偏好写入ID存为数字", dbp["preferred"]["flying"] == 183,
          str(dbp["preferred"]["flying"]))
    check("设置.偏好读回=183", gs.get_value() == "183", str(gs.get_value()))
    gs.set_value("none")
    check("设置.偏好写入none", dbp["preferred"]["flying"] == "none",
          str(dbp["preferred"]["flying"]))
    check("设置.偏好读回=none", gs.get_value() == "none")
    gs.set_value("auto")
    check("设置.偏好清空为nil", dbp["preferred"]["flying"] is None,
          str(dbp["preferred"]["flying"]))

    # 面板写进去的偏好，必须被 fastest 模式真正采纳（端到端）
    gs.set_value("2")                       # 2 = 御空巨龙(advflying)
    slash(w, lua, "mode fastest")
    w.summoned = []
    tick(w)
    check("设置.面板写入的偏好在fastest模式生效",
          w.summoned == [2], str(w.summoned))


def t_settings_absent_ok():
    """老客户端没有 Settings API 时必须优雅降级（斜杠命令照常可用）"""
    w, lua = make_world(no_settings=True)
    login(w)
    check("设置.无SettingsAPI时正常加载", "已加载" in w.out(), w.out())
    check("设置.无SettingsAPI时无失败提示", "设置面板创建失败" not in w.out(), w.out())
    slash(w, lua, "reset")
    check("设置.无SettingsAPI时reset仍可用", "已恢复默认" in w.out())


#====================== v1.4.0 界面双语 ======================--
# 覆盖：两张表 key 一致、默认跟随客户端、/am lang 切换、面板语言下拉、漏翻译自检。
# 这一组是整个 i18n 的安全网——加文案时只改一张表，这里立刻红。

def t_locale_tables_consistent():
    """两张语言表的 key 必须完全一致（漏翻 = 显示英文，属于静默降级，必须测出来）"""
    w, lua = make_world()
    loc = lua.globals().AutoMountLiteLocale
    zh = set(loc.zhCN.keys())
    en = set(loc.enUS.keys())
    check("i18n.两张表key一致", zh == en,
          "仅中文有:%s 仅英文有:%s" % (sorted(zh - en), sorted(en - zh)))
    check("i18n.文案条数>100", len(zh) > 100, str(len(zh)))


def t_locale_every_key_has_text():
    """每个 key 在两张表里都必须有非空文案（防空串）"""
    w, lua = make_world()
    loc = lua.globals().AutoMountLiteLocale
    for lang in ("zhCN", "enUS"):
        table_ = getattr(loc, lang)
        empty = [k for k in table_.keys() if not (table_[k] and str(table_[k]).strip())]
        check("i18n.%s无空文案" % lang, not empty, str(empty))


def t_locale_default_follows_client():
    """不设 lang 时跟随客户端语言：zhCN 客户端→中文，enUS 客户端→英文"""
    w, lua = make_world(locale="zhCN")
    login(w)
    check("i18n.默认中文(zhCN客户端)", "已加载" in w.out() and "开关=" in w.out(), w.out())

    w, lua = make_world(locale="enUS")
    login(w)
    out = w.out()
    check("i18n.默认英文(enUS客户端)", "Loaded - Enabled=" in out, out)


def t_locale_alias_zhTW():
    """繁体客户端复用简体文案表（不是回退英文）"""
    w, lua = make_world(locale="zhTW")
    login(w)
    loc = lua.globals().AutoMountLiteLocale
    check("i18n.zhTW映射zhCN", loc.GetLang() == "zhCN", str(loc.GetLang()))


def t_locale_lang_switch():
    """/am lang 切换语言：聊天输出、status、help 全部跟着变"""
    w, lua = make_world()
    login(w)
    slash(w, lua, "lang enUS")
    out = w.out()
    check("i18n.切英文有提示", "Language set to" in out, out)

    w.prints = []
    slash(w, lua, "status")
    check("i18n.status英文", "Enabled=" in w.out() and "开关=" not in w.out(), w.out())

    w.prints = []
    slash(w, lua, "favs")
    check("i18n.favs英文", "favorite mounts" in w.out(), w.out()[-400:])

    w.prints = []
    slash(w, lua, "help")
    check("i18n.help英文", "Commands:" in w.out() and "命令：" not in w.out(), w.out()[-400:])

    slash(w, lua, "lang zhCN")
    w.prints = []
    slash(w, lua, "status")
    check("i18n.切回中文", "开关=" in w.out(), w.out())


def t_locale_lang_invalid():
    """非法语言码给用法提示，不改动当前语言"""
    w, lua = make_world()
    login(w)
    slash(w, lua, "lang xx")
    check("i18n.非法语言提示用法", "用法: /am lang" in w.out(), w.out())
    slash(w, lua, "status")
    check("i18n.非法语言不改动", "开关=" in w.out(), w.out())


def t_locale_saved_and_reset():
    """lang 写进存档；reset 恢复 auto"""
    w, lua = make_world()
    login(w)
    slash(w, lua, "lang enUS")
    check("i18n.lang写入存档", lua.globals().AutoMountLiteDB.lang == "enUS",
          str(lua.globals().AutoMountLiteDB.lang))
    slash(w, lua, "reset")
    check("i18n.reset恢复auto", lua.globals().AutoMountLiteDB.lang == "auto",
          str(lua.globals().AutoMountLiteDB.lang))


def t_locale_panel_lang_dropdown():
    """面板里有语言下拉，选项为 auto/zhCN/enUS"""
    w, lua = make_world()
    login(w)
    s = w.settings
    keys = [x.key for x in s.settings]
    check("i18n.面板含lang项", "AutoMountLite_lang" in keys, str(keys))
    opts = None
    for d in s.dropdowns:
        if d[0].key == "AutoMountLite_lang":
            d[1]()   # 调用 getOptions：mock 会把选项记到 w.settings_options
            opts = [o[0] for o in w.settings_options]
    check("i18n.语言下拉3个选项", opts == ["auto", "zhCN", "enUS"], str(opts))
    check("i18n.分节标题4个(语言不算)", len(s.headers) == 3, str(s.headers))


def t_locale_binding_name_localized():
    """按键设置里的描述跟随客户端语言（BINDING_NAME 全局变量）"""
    w, lua = make_world(locale="enUS")
    login(w)
    check("i18n.英文客户端键位描述",
          lua.globals().BINDING_NAME_AUTOMOUNTLITE_TOGGLE == "Toggle Auto Mount",
          str(lua.globals().BINDING_NAME_AUTOMOUNTLITE_TOGGLE))
    w, lua = make_world(locale="zhCN")
    login(w)
    check("i18n.中文客户端键位描述",
          lua.globals().BINDING_NAME_AUTOMOUNTLITE_TOGGLE == "开/关 自动上坐骑",
          str(lua.globals().BINDING_NAME_AUTOMOUNTLITE_TOGGLE))


def t_locale_no_hardcoded_zh_in_runtime():
    """主文件运行时不得再有硬编码中文（源码级扫描，防回归）"""
    import io
    src = io.open(LUA_PATH, encoding="utf-8").read()
    zh_ranges = ("\u4e00", "\u9fff")
    bad = []
    for i, line in enumerate(src.split("\n"), 1):
        stripped = line.lstrip()
        if stripped.startswith("--"):
            continue
        # 去掉行内注释后再找中文（注释允许中文）
        code = line.split("--")[0] if "--" in line else line
        if any(zh_ranges[0] <= ch <= zh_ranges[1] for ch in code):
            bad.append((i, line.strip()[:60]))
    check("i18n.运行时无硬编码中文", not bad, str(bad[:5]))


def main():
    # 清空上一轮日志
    open(os.path.join(HERE, "rt_out.txt"), "w", encoding="utf-8").close()
    tests = [
        t_favs_basic, t_status_env, t_random_mode, t_random_not_weight_pool_bug,
        t_random_fallback_when_byid0_blocked, t_missing_byid_no_crash,
        t_casting_spellid_index,
        t_fastest_adv_area,
        t_fastest_ground_area, t_fastest_water, t_fastest_favorite_bonus,
        t_pref_none_flyable_blocks, t_pref_none_ground_area_mounts,
        t_pref_specific_id, t_pref_random_mode_warns, t_phoenix_only,
        t_diag_usability, t_toggle_binding_body, t_binding_migrate_legacy,
        t_binding_occupied_warn_once, t_binding_already_bound,
        t_binding_fresh_default, t_favs_empty, t_help_and_misc, t_guards_combat,
        t_fastest_424_advflying,
        t_settings_panel, t_settings_pref_proxy, t_settings_absent_ok,
        t_locale_tables_consistent, t_locale_every_key_has_text,
        t_locale_default_follows_client, t_locale_alias_zhTW,
        t_locale_lang_switch, t_locale_lang_invalid,
        t_locale_saved_and_reset, t_locale_panel_lang_dropdown,
        t_locale_binding_name_localized, t_locale_no_hardcoded_zh_in_runtime,
    ]
    for t in tests:
        try:
            t()
        except Exception as e:
            check(t.__name__ + ".[异常]", False, repr(e))
    failed = [r for r in RESULTS if not r[1]]
    print("\n==== %d 项检查，%d 通过，%d 失败 ====" %
          (len(RESULTS), len(RESULTS) - len(failed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
