// Drive headless Chromium over CDP: node shoot.mjs <steps.json>
// steps: [{"go":url}|{"wait":ms}|{"click":[x,y]}|{"type":"text"}|{"key":"Enter"}|{"shot":"path"}|{"size":[w,h]}
//         |{"wheel":[x,y,dy]}|{"move":[x,y]}|{"eval":"js"}]
import { readFileSync } from 'node:fs';
import { writeFileSync } from 'node:fs';

const port = process.env.CDP_PORT || '9333';
const steps = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
let page = targets.find((t) => t.type === 'page');
if (!page) page = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r, { once: true }));
let id = 0;
const pending = new Map();
ws.addEventListener('message', (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
const send = (method, params = {}) => new Promise((res) => {
  const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params }));
});
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

await send('Page.enable');
for (const s of steps) {
  if (s.size) {
    await send('Emulation.setDeviceMetricsOverride', { width: s.size[0], height: s.size[1], deviceScaleFactor: 1, mobile: false });
  } else if (s.go) {
    await send('Page.navigate', { url: s.go });
  } else if (s.wait) {
    await sleep(s.wait);
  } else if (s.click) {
    const [x, y] = s.click;
    for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) {
      await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    }
  } else if (s.wheel) {
    const [x, y, dy] = s.wheel;
    await send('Input.dispatchMouseEvent', { type: 'mouseWheel', x, y, deltaX: 0, deltaY: dy });
  } else if (s.move) {
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: s.move[0], y: s.move[1] });
  } else if (s.type) {
    await send('Input.insertText', { text: s.type });
  } else if (s.key) {
    const k = s.key;
    const code = { Enter: 13, Tab: 9, Escape: 27 }[k];
    await send('Input.dispatchKeyEvent', { type: 'keyDown', key: k, code: k, windowsVirtualKeyCode: code });
    await send('Input.dispatchKeyEvent', { type: 'keyUp', key: k, code: k, windowsVirtualKeyCode: code });
  } else if (s.eval) {
    const r = await send('Runtime.evaluate', { expression: s.eval, returnByValue: true });
    console.log(JSON.stringify(r.result?.result?.value));
  } else if (s.shot) {
    const r = await send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(s.shot, Buffer.from(r.result.data, 'base64'));
    console.log('shot', s.shot);
  }
}
ws.close();
