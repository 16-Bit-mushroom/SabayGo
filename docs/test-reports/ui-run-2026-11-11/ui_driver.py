#!/usr/bin/env python3
"""Drive the SabayGo web apps in a headless Brave, as a person would.

    ui.py <role> <cmd> [args] [<cmd> [args] ...]

Each role (manager, cashier, dispatcher, passenger) gets its own browser
context, so their sign-ins never mix. Flutter draws on a canvas; its
accessibility tree (switched on with `sem`) gives every button, field and
text a DOM node with a label, which is how controls are found. Clicks and
typing are real input events at those nodes' positions.

Commands:
  open <url> <w> <h>    new isolated context + page at that size
  sem                   switch on Flutter's accessibility tree
  ls [regex]            list labelled nodes (optionally filtered)
  click <regex> [n]     click the n-th (0-based) smallest node matching
  tap <x> <y>           click at a point
  type <text>           type into the focused field
  field <regex> <text>  click a field, select all, type
  key <name>            Enter, Tab, Backspace, Escape, ArrowDown
  wheel <dy> [x y]      scroll the pointer's area
  wait <regex> [secs]   until a node matches (default 15 s)
  gone <regex> [secs]   until no node matches
  sleep <secs>
  shot <name>           screenshot to shots/<name>.png
  text                  print every label on screen, top to bottom
"""
import asyncio
import json
import os
import re
import sys
import time
import urllib.request

import websockets

HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(HERE, "sim_state.json")
SHOTS = os.path.join(HERE, "shots")
PORT = 9333


def state():
    try:
        return json.load(open(STATE))
    except Exception:
        return {}


def save(st):
    json.dump(st, open(STATE, "w"), indent=1)


class Conn:
    def __init__(self, ws):
        self.ws, self.i = ws, 0

    async def send(self, method, **params):
        self.i += 1
        mid = self.i
        await self.ws.send(json.dumps({"id": mid, "method": method, "params": params}))
        while True:
            m = json.loads(await asyncio.wait_for(self.ws.recv(), 60))
            if m.get("id") == mid:
                if "error" in m:
                    raise RuntimeError(f"{method}: {m['error']}")
                return m.get("result", {})

    async def js(self, expr):
        r = await self.send("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            raise RuntimeError(json.dumps(r["exceptionDetails"])[:400])
        return r["result"].get("value")


NODES_JS = r"""
(() => {
  const out = [];
  const seen = new Set();
  const vw = innerWidth, vh = innerHeight;
  document.querySelectorAll('flt-semantics, input, textarea, [role]').forEach(e => {
    const r = e.getBoundingClientRect();
    if (r.width < 2 || r.height < 2 || r.bottom < 0 || r.top > vh || r.right < 0 || r.left > vw) return;
    let label = e.getAttribute('aria-label') || '';
    if (!label && (e.tagName === 'INPUT' || e.tagName === 'TEXTAREA')) label = e.getAttribute('placeholder') || e.value || '';
    if (!label) {
      // own text only (not the children's), so a card does not swallow its rows
      label = Array.from(e.childNodes).filter(n => n.nodeType === 3).map(n => n.textContent).join(' ').trim();
      if (!label && e.children.length === 0) label = (e.textContent || '').trim();
    }
    const tag = e.tagName.toLowerCase();
    const role = e.getAttribute('role') || (tag === 'input' || tag === 'textarea' ? 'textbox' : '');
    const value = (tag === 'input' || tag === 'textarea') ? (e.value || '') : '';
    if (!label && !value) return;
    const key = [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height), label].join('|');
    if (seen.has(key)) return;
    seen.add(key);
    out.push({label: label.replace(/\s+/g, ' ').slice(0, 160), role, tag, value,
              x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width, h: r.height,
              disabled: e.getAttribute('aria-disabled') === 'true'});
  });
  out.sort((a, b) => (a.y - b.y) || (a.x - b.x));
  return out;
})()
"""


async def nodes(c, rx=None):
    ns = await c.js(NODES_JS) or []
    if rx:
        p = re.compile(rx, re.I)
        ns = [n for n in ns if p.search(n["label"]) or (n["value"] and p.search(n["value"]))]
    return ns


async def find(c, rx, idx=0, secs=10):
    end = time.time() + secs
    while True:
        ns = await nodes(c, rx)
        if ns:
            # smallest first: the button, not the card that holds it
            ns.sort(key=lambda n: n["w"] * n["h"])
            if idx < len(ns):
                return ns[idx]
        if time.time() > end:
            raise SystemExit(f"FAIL  nothing matches /{rx}/ (index {idx})")
        await asyncio.sleep(0.4)


async def mouse(c, x, y):
    await c.send("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y)
    await c.send("Input.dispatchMouseEvent", type="mousePressed", x=x, y=y, button="left", clickCount=1)
    await asyncio.sleep(0.05)
    await c.send("Input.dispatchMouseEvent", type="mouseReleased", x=x, y=y, button="left", clickCount=1)


KEYS = {
    "Enter": ("Enter", 13, "\r"), "Tab": ("Tab", 9, ""), "Backspace": ("Backspace", 8, ""),
    "Escape": ("Escape", 27, ""), "ArrowDown": ("ArrowDown", 40, ""), "ArrowUp": ("ArrowUp", 38, ""),
}


async def key(c, name):
    k, code, txt = KEYS[name]
    await c.send("Input.dispatchKeyEvent", type="keyDown", key=k, code=k, windowsVirtualKeyCode=code,
                 **({"text": txt} if txt else {}))
    await c.send("Input.dispatchKeyEvent", type="keyUp", key=k, code=k, windowsVirtualKeyCode=code)


async def select_all(c):
    await c.send("Input.dispatchKeyEvent", type="keyDown", key="a", code="KeyA", windowsVirtualKeyCode=65,
                 modifiers=2)
    await c.send("Input.dispatchKeyEvent", type="keyUp", key="a", code="KeyA", windowsVirtualKeyCode=65,
                 modifiers=2)


async def run(role, args):
    st = state()
    if args and args[0] == "open":
        url, w, h = args[1], int(args[2]), int(args[3])
        ver = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/version"))
        async with websockets.connect(ver["webSocketDebuggerUrl"], max_size=None) as bws:
            b = Conn(bws)
            if role in st:
                try:
                    await b.send("Target.closeTarget", targetId=st[role]["target"])
                except Exception:
                    pass
            ctx = (await b.send("Target.createBrowserContext", disposeOnDetach=False))["browserContextId"]
            tid = (await b.send("Target.createTarget", url="about:blank", browserContextId=ctx,
                                width=w, height=h))["targetId"]
        st[role] = {"target": tid, "w": w, "h": h}
        save(st)
        args = ["_size", str(w), str(h), "_goto", url] + args[4:]
    if role not in st:
        raise SystemExit(f"no page for {role}: open it first")
    t = st[role]
    async with websockets.connect(f"ws://127.0.0.1:{PORT}/devtools/page/{t['target']}", max_size=None) as ws:
        c = Conn(ws)
        await c.send("Page.enable")
        i = 0
        while i < len(args):
            cmd = args[i]
            i += 1
            if cmd == "_size":
                w, h = int(args[i]), int(args[i + 1]); i += 2
                await c.send("Emulation.setDeviceMetricsOverride", width=w, height=h, deviceScaleFactor=1,
                             mobile=False)
            elif cmd == "_goto":
                await c.send("Page.navigate", url=args[i]); i += 1
                await asyncio.sleep(4)
            elif cmd == "sem":
                for _ in range(40):
                    ok = await c.js("""(() => { const p = document.querySelector('flt-semantics-placeholder');
                        if (p) { p.click(); return 'clicked'; }
                        return document.querySelector('flt-semantics') ? 'on' : 'waiting'; })()""")
                    if ok == "on":
                        break
                    await asyncio.sleep(0.5)
                print(f"  {role}: accessibility tree {ok}")
            elif cmd == "ls":
                rx = args[i] if i < len(args) and args[i] not in CMDS else None
                if rx:
                    i += 1
                for n in await nodes(c, rx):
                    v = f" = {n['value']!r}" if n["value"] else ""
                    d = " (disabled)" if n["disabled"] else ""
                    print(f"  [{n['role'] or n['tag']}] {n['label']}{v}{d}  @{int(n['x'])},{int(n['y'])}")
            elif cmd == "text":
                print("  " + " | ".join(n["label"] for n in await nodes(c) if n["label"]))
            elif cmd == "click":
                rx = args[i]; i += 1
                idx = 0
                if i < len(args) and args[i].isdigit():
                    idx = int(args[i]); i += 1
                n = await find(c, rx, idx)
                if n["disabled"]:
                    print(f"  WARN  '{n['label']}' is disabled")
                await mouse(c, n["x"], n["y"])
                print(f"  {role}: clicked '{n['label']}'")
                await asyncio.sleep(0.8)
            elif cmd == "tap":
                await mouse(c, float(args[i]), float(args[i + 1])); i += 2
                await asyncio.sleep(0.6)
            elif cmd == "type":
                await c.send("Input.insertText", text=args[i]); i += 1
                await asyncio.sleep(0.3)
            elif cmd == "field":
                rx, text = args[i], args[i + 1]; i += 2
                n = await find(c, rx)
                await mouse(c, n["x"], n["y"])
                await asyncio.sleep(0.5)
                await select_all(c)
                await c.send("Input.insertText", text=text)
                print(f"  {role}: typed into '{n['label']}'")
                await asyncio.sleep(0.4)
            elif cmd == "key":
                await key(c, args[i]); i += 1
                await asyncio.sleep(0.5)
            elif cmd == "wheel":
                dy = float(args[i]); i += 1
                x, y = t["w"] / 2, t["h"] / 2
                if i + 1 < len(args) and re.fullmatch(r"\d+", args[i]) and re.fullmatch(r"\d+", args[i + 1]):
                    x, y = float(args[i]), float(args[i + 1]); i += 2
                await c.send("Input.dispatchMouseEvent", type="mouseWheel", x=x, y=y, deltaX=0, deltaY=dy)
                await asyncio.sleep(0.8)
            elif cmd in ("wait", "gone"):
                rx = args[i]; i += 1
                secs = 15.0
                if i < len(args) and re.fullmatch(r"\d+(\.\d+)?", args[i]):
                    secs = float(args[i]); i += 1
                end = time.time() + secs
                while True:
                    hit = await nodes(c, rx)
                    if (cmd == "wait") == bool(hit):
                        print(f"  {role}: {'sees' if cmd == 'wait' else 'no longer sees'} /{rx}/")
                        break
                    if time.time() > end:
                        raise SystemExit(f"FAIL  {role}: {'never saw' if cmd == 'wait' else 'still sees'} /{rx}/")
                    await asyncio.sleep(0.5)
            elif cmd == "geo":
                lat, lng = float(args[i]), float(args[i + 1]); i += 2
                ver = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/version"))
                async with websockets.connect(ver["webSocketDebuggerUrl"], max_size=None) as bws:
                    b = Conn(bws)
                    infos = (await b.send("Target.getTargets"))["targetInfos"]
                    ctx = next(x["browserContextId"] for x in infos if x["targetId"] == t["target"])
                    origin = await c.js("location.origin")
                    await b.send("Browser.setPermission", permission={"name": "geolocation"},
                                 setting="granted", origin=origin, browserContextId=ctx)
                    await b.send("Browser.grantPermissions", permissions=["geolocation"], browserContextId=ctx)
                await c.send("Emulation.setGeolocationOverride", latitude=lat, longitude=lng, accuracy=10)
                print(f"  {role}: location set to {lat},{lng}")
            elif cmd == "js":
                print("  js:", await c.js(args[i])); i += 1
            elif cmd == "reload":
                await c.send("Page.reload", ignoreCache=True)
                await asyncio.sleep(5)
            elif cmd == "sleep":
                await asyncio.sleep(float(args[i])); i += 1
            elif cmd == "shot":
                os.makedirs(SHOTS, exist_ok=True)
                import base64
                img = (await c.send("Page.captureScreenshot", format="png"))["data"]
                path = os.path.join(SHOTS, f"{args[i]}.png"); i += 1
                open(path, "wb").write(base64.b64decode(img))
                print(f"  {role}: screenshot {path}")
            else:
                raise SystemExit(f"unknown command {cmd!r}")


CMDS = {"js", "geo", "reload", "open", "sem", "ls", "click", "tap", "type", "field", "key", "wheel", "wait", "gone", "sleep", "shot", "text"}

if __name__ == "__main__":
    asyncio.run(run(sys.argv[1], sys.argv[2:]))
