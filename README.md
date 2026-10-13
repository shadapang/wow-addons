# wow-addons

> 仓库地址：<https://cnb.cool/wuhuarou-2026_799/wow-addons>

魔兽世界插件集合仓（正式服 / retail）。每个插件一个目录，放在 `addons/` 下，
和游戏 `Interface/AddOns/` 的目录结构 1:1，可以直接复制或一键部署。

所有插件只调用暴雪官方 API，不模拟按键、不注入、不 hook、不联网。

## 插件列表

| 插件 | 版本 | 说明 | 状态 |
| --- | --- | --- | --- |
| [AutoMountLite](addons/AutoMountLite/README.md) | 1.3.0 | 自动上坐骑（复刻 Dugi 的同名模块），支持图形设置面板 | ✅ 可用 |

## 目录结构

```
wow-addons/
├── addons/                 每个插件一个目录（与游戏 AddOns 目录同名）
│   └── AutoMountLite/
├── _tools/                 共享开发工具，新插件直接复用
│   ├── test_runtime.py     lupa + 全量 WoW API mock，离线跑真实 Lua 代码
│   ├── check.js            Lua 语法检查
│   ├── deploy.py           一键同步 addons/* → 游戏 AddOns 目录
│   └── wow_monitor2.py     游戏内存 / 日志 / 崩溃监控
├── docs/                   开发踩坑记录
└── README.md
```

## 安装

**方式一：一键部署（推荐，开发环境）**

```bash
python _tools/deploy.py            # 默认部署到 D:\World of Warcraft\_retail_\Interface\AddOns
python _tools/deploy.py --dest "E:\ Games\..."   # 指定别的 AddOns 目录
python _tools/deploy.py --dry-run                # 只看会同步什么，不真写
```

**方式二：手动**

把 `addons/` 里需要的插件文件夹整个复制进：

```
<魔兽目录>\_retail_\Interface\AddOns\
```

然后**完全退出并重启游戏**（新插件要重启客户端才会被扫描到，`/reload` 不够）。

想跟着更新就克隆本仓库，之后重复上面两步即可：

```bash
git clone https://cnb.cool/wuhuarou-2026_799/wow-addons.git
```

## 开发

新插件直接复用 `_tools` 的离线仿真，不用重复搭测试环境：

```bash
PYTHONPATH="<venv>/Lib/site-packages" python _tools/test_runtime.py   # 跑全套仿真测试
node _tools/check.js addons/<插件名>/<插件名>.lua                      # 语法检查，期望 SYNTAX_OK
```

`test_runtime.py` 用 Python 实现了整套 WoW API 的 mock，然后用 lupa 把插件的 Lua
源码**真的跑起来**——事件、C_Timer 心跳、坐骑图鉴全都可模拟。这意味着不用上游戏
就能验证逻辑，也是能抓出「调用了根本不存在的 API」这类问题的唯一办法。

改代码前先让测试变红、改完再变绿（变异测试），避免写出「假绿」的测试。

## 踩坑记录

见 [docs/](docs/)。尤其是 [WoW API 踩坑](docs/wow-api-pitfalls.md)——
里面记的每一个坑，都是靠「在真实客户端里反复重试」才发现的。
