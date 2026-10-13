# -*- coding: utf-8 -*-
"""
WoW 监控 v2 —— AutoMountLite v1.2.2 上线验证专用
在 v1（内存/进程/崩溃文件）基础上增加：
  * FrameXML.log 增量读取：AutoMountLite/AUTOMOUNTLITE 相关报错即时事件
  * SavedVariables\\AutoMountLite.lua 写入事件（插件存活的铁证）
  * bindings-cache.wtf 变动事件（快捷键自愈逻辑是否运行的铁证）
  * 提交内存低于 6GB 预警（昨晚 OOM 崩溃的教训）

输出（本项目 _tools 目录）：
  wow-monitor2.csv   每 2s 采样
  wow-events2.log    关键事件
"""
import ctypes
import datetime
import os
import subprocess
import time

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(OUT_DIR, "wow-monitor2.csv")
EVENTS = os.path.join(OUT_DIR, "wow-events2.log")
ERRORS_DIR = r"D:\World of Warcraft\_retail_\Errors"
LOGS_DIR = r"D:\World of Warcraft\_retail_\Logs"
FRAMEXML = os.path.join(LOGS_DIR, "FrameXML.log")
SAVED_VARS = r"D:\World of Warcraft\_retail_\WTF\Account\XIAOYI_KX7\SavedVariables\AutoMountLite.lua"
BINDINGS_CACHE = r"D:\World of Warcraft\_retail_\WTF\Account\XIAOYI_KX7\bindings-cache.wtf"

WATCH_PATTERNS = ("AutoMountLite", "AUTOMOUNTLITE", "Bindings")
COMMIT_WARN_GB = 6.0

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
GetProcessMemoryInfo = kernel32.K32GetProcessMemoryInfo
GetProcessMemoryInfo.restype = ctypes.c_bool
GetProcessMemoryInfo.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulong]


class MEMORYSTATUSEX(ctypes.Structure):
    _fields_ = [
        ("dwLength", ctypes.c_ulong),
        ("dwMemoryLoad", ctypes.c_ulong),
        ("ullTotalPhys", ctypes.c_ulonglong),
        ("ullAvailPhys", ctypes.c_ulonglong),
        ("ullTotalPageFile", ctypes.c_ulonglong),
        ("ullAvailPageFile", ctypes.c_ulonglong),
        ("ullTotalVirtual", ctypes.c_ulonglong),
        ("ullAvailVirtual", ctypes.c_ulonglong),
        ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
    ]


class PMC_EX(ctypes.Structure):
    _fields_ = [
        ("cb", ctypes.c_ulong),
        ("PageFaultCount", ctypes.c_ulong),
        ("PeakWorkingSetSize", ctypes.c_size_t),
        ("WorkingSetSize", ctypes.c_size_t),
        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
        ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
        ("PagefileUsage", ctypes.c_size_t),
        ("PeakPagefileUsage", ctypes.c_size_t),
        ("PrivateUsage", ctypes.c_size_t),
    ]


def sysmem():
    m = MEMORYSTATUSEX()
    m.dwLength = ctypes.sizeof(m)
    kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    return m


def find_wow():
    try:
        r = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq Wow.exe", "/FO", "CSV", "/NH"],
            capture_output=True, text=True, errors="ignore", timeout=10,
        )
    except Exception:
        return []
    pids = []
    for line in r.stdout.splitlines():
        if "Wow.exe" in line:
            parts = [p.strip('"') for p in line.split('","')]
            try:
                pids.append(int(parts[1]))
            except Exception:
                pass
    return pids


def procmem(pid):
    h = kernel32.OpenProcess(0x0410, False, pid)
    if not h:
        return None
    p = PMC_EX()
    p.cb = ctypes.sizeof(p)
    ok = GetProcessMemoryInfo(h, ctypes.byref(p), p.cb)
    kernel32.CloseHandle(h)
    return p if ok else None


def snapshot_dir(d):
    try:
        return set(os.listdir(d))
    except Exception:
        return set()


def mtime(p):
    try:
        return os.path.getmtime(p)
    except Exception:
        return None


def read_framexml_new(offset):
    """增量读取 FrameXML.log，返回 (新行列表, 新offset)"""
    try:
        size = os.path.getsize(FRAMEXML)
    except Exception:
        return [], offset
    if size < offset:          # 日志被截断/重建（游戏重启）
        offset = 0
    if size == offset:
        return [], offset
    try:
        with open(FRAMEXML, "rb") as f:
            f.seek(offset)
            data = f.read(size - offset)
    except Exception:
        return [], offset
    lines = data.decode("utf-8", errors="ignore").splitlines()
    return [ln for ln in lines if ln.strip()], size


def main():
    prev_errors = snapshot_dir(ERRORS_DIR)
    prev_wow = False
    fx_offset = 0
    prev_sv_mtime = mtime(SAVED_VARS)
    prev_bc_mtime = mtime(BINDINGS_CACHE)
    warned_commit = False

    with open(LOG, "w", encoding="utf-8") as f, \
            open(EVENTS, "a", encoding="utf-8") as ev:
        f.write("ts,memload_pct,avail_phys_gb,commit_limit_gb,commit_avail_gb,"
                "commit_used_gb,wow_pids,wow_ws_mb,wow_commit_mb,"
                "new_error_files,framexml_new_lines,framexml_watch_hits\n")
        f.flush()
        ev.write("==== monitor2 started %s (AutoMountLite v1.2.2 verify) ====\n"
                 % datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        ev.flush()

        while True:
            m = sysmem()
            commit_avail_gb = m.ullAvailPageFile / 2 ** 30
            pids = find_wow()
            ws = cm = 0
            for pid in pids:
                p = procmem(pid)
                if p:
                    ws += p.WorkingSetSize
                    cm += p.PagefileUsage
            cur_errors = snapshot_dir(ERRORS_DIR)
            new_err = sorted(cur_errors - prev_errors)
            ts = datetime.datetime.now().strftime("%H:%M:%S")

            # ---- FrameXML.log 增量 ----
            fx_lines, fx_offset = read_framexml_new(fx_offset)
            watch_hits = [ln for ln in fx_lines
                          if any(pat in ln for pat in WATCH_PATTERNS)]
            other_errs = [ln for ln in fx_lines
                          if ("Error" in ln or "error" in ln)
                          and ln not in watch_hits]

            # ---- 存档/按键缓存变动 ----
            sv_m = mtime(SAVED_VARS)
            sv_saved = sv_m is not None and sv_m != prev_sv_mtime
            bc_m = mtime(BINDINGS_CACHE)
            bc_changed = bc_m is not None and bc_m != prev_bc_mtime

            f.write("%s,%d,%.2f,%.2f,%.2f,%.2f,%s,%.0f,%.0f,%s,%d,%d\n" % (
                ts, m.dwMemoryLoad, m.ullAvailPhys / 2 ** 30,
                m.ullTotalPageFile / 2 ** 30, commit_avail_gb,
                (m.ullTotalPageFile - m.ullAvailPageFile) / 2 ** 30,
                ";".join(map(str, pids)), ws / 2 ** 20, cm / 2 ** 20,
                "|".join(new_err), len(fx_lines), len(watch_hits)))
            f.flush()

            # ---- 事件 ----
            if watch_hits:
                for ln in watch_hits[:5]:
                    ev.write("%s FRAMEXML_AUTOMOUNT %s\n" % (ts, ln.strip()))
                ev.flush()
            if other_errs:
                for ln in other_errs[:3]:
                    ev.write("%s FRAMEXML_OTHER_ERROR %s\n" % (ts, ln.strip()))
                ev.flush()
            if new_err:
                ev.write("%s NEW_CRASH_FILES %s  commit_avail=%.2fGB\n"
                         % (ts, new_err, commit_avail_gb))
                ev.flush()
                prev_errors |= set(new_err)
            if pids and not prev_wow:
                ev.write("%s WOW_STARTED pids=%s commit_avail=%.2fGB avail_phys=%.2fGB\n"
                         % (ts, pids, commit_avail_gb, m.ullAvailPhys / 2 ** 30))
                ev.flush()
                warned_commit = False
            if not pids and prev_wow:
                ev.write("%s WOW_EXITED commit_avail=%.2fGB\n"
                         % (ts, commit_avail_gb))
                ev.flush()
            if sv_saved:
                ev.write("%s AUTOMOUNT_SAVED (SavedVariables 写入，插件存活铁证)\n" % ts)
                ev.flush()
                prev_sv_mtime = sv_m
            if bc_changed:
                ev.write("%s BINDINGS_CACHE_CHANGED (按键缓存变动，自愈逻辑可能已运行)\n" % ts)
                ev.flush()
                prev_bc_mtime = bc_m
            if pids and commit_avail_gb < COMMIT_WARN_GB and not warned_commit:
                ev.write("%s COMMIT_LOW_WARN avail=%.2fGB (<%.1fGB，昨晚OOM崩溃前兆)\n"
                         % (ts, commit_avail_gb, COMMIT_WARN_GB))
                ev.flush()
                warned_commit = True

            prev_wow = bool(pids)
            time.sleep(2)


if __name__ == "__main__":
    main()
