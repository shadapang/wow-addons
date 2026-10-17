#!/usr/bin/env node
/**
 * cdp.mjs — 极简 Chrome DevTools Protocol 直连客户端
 *
 * 用途：agent-browser daemon 卡死时的备援通道；也用于 CF 作者后台这类
 * 需要人工登录的页面自动化（登录态留在用户可见的 Chrome 窗口里）。
 *
 * 用法：
 *   node cdp.mjs js "<表达式>"        在当前页面执行 JS，打印返回值
 *   node cdp.mjs nav <url>            导航到 URL
 *   node cdp.mjs url                  打印当前 URL
 *   node cdp.mjs wait <子串> [超秒数]  等 URL 包含子串（默认 120s）
 *   node cdp.mjs snap                 打印页面可交互元素摘要（a/button/input）
 *
 * 前置：Chrome 以 --remote-debugging-port=9222 启动（本机 127.0.0.1:9222）。
 */
const BASE = "http://127.0.0.1:9222";
const [cmd, ...args] = process.argv.slice(2);

async function targets() {
  const r = await fetch(BASE + "/json");
  return r.json();
}

function pageTarget(list) {
  // 优先取 http(s) 页面，跳过 devtools/extension 页
  const pages = list.filter((t) => t.type === "page" && /^https?:/.test(t.url));
  return pages[pages.length - 1] || list.find((t) => t.type === "page");
}

async function connect() {
  const list = await targets();
  const t = pageTarget(list);
  if (!t) throw new Error("没有可用的 page target");
  const ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((res, rej) => {
    ws.onopen = res;
    ws.onerror = (e) => rej(new Error("WS 连接失败: " + e.message));
  });
  let id = 0;
  const pending = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const { res, rej } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? rej(new Error(msg.error.message)) : res(msg.result);
    }
  };
  const send = (method, params = {}) =>
    new Promise((res, rej) => {
      const mid = ++id;
      pending.set(mid, { res, rej });
      ws.send(JSON.stringify({ id: mid, method, params }));
      setTimeout(() => {
        if (pending.has(mid)) {
          pending.delete(mid);
          rej(new Error(method + " 超时"));
        }
      }, 30000);
    });
  await send("Runtime.enable");
  return { send, close: () => ws.close(), url: t.url };
}

async function main() {
  const c = await connect();
  try {
    if (cmd === "js") {
      const r = await c.send("Runtime.evaluate", {
        expression: args[0],
        returnByValue: true,
        awaitPromise: true,
      });
      if (r.exceptionDetails) {
        console.error("JS 异常: " + JSON.stringify(r.exceptionDetails.exception?.description || r.exceptionDetails.text));
        process.exit(1);
      }
      console.log(r.result.value ?? JSON.stringify(r.result));
    } else if (cmd === "url") {
      console.log(c.url);
    } else if (cmd === "nav") {
      await c.send("Page.navigate", { url: args[0] });
      console.log("navigating -> " + args[0]);
    } else if (cmd === "wait") {
      const want = args[0];
      const limit = (Number(args[1]) || 120) * 1000;
      const t0 = Date.now();
      for (;;) {
        const list = await targets();
        const t = pageTarget(list);
        const u = t?.url || "";
        if (u.includes(want)) {
          console.log("OK: " + u);
          return;
        }
        if (Date.now() - t0 > limit) {
          console.error("等待超时，当前: " + u);
          process.exit(1);
        }
        await new Promise((r) => setTimeout(r, 2000));
      }
    } else if (cmd === "snap") {
      const r = await c.send("Runtime.evaluate", {
        returnByValue: true,
        expression: `JSON.stringify([...document.querySelectorAll('a,button,input,select,[role=button]')].slice(0,80).map(e=>({tag:e.tagName.toLowerCase(),text:(e.innerText||e.value||e.placeholder||'').trim().slice(0,60),href:e.href||'',type:e.type||''})))`,
      });
      const items = JSON.parse(r.result.value || "[]");
      items.forEach((e, i) => console.log(`${i}\t${e.tag}\t${e.type}\t${e.text}\t${e.href}`));
    } else {
      console.error("未知命令: " + cmd);
      process.exit(1);
    }
  } finally {
    c.close();
  }
}

main().catch((e) => {
  console.error("✗ " + e.message);
  process.exit(1);
});
