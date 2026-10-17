/**
 * 验证「到点自己开口」：跑 host 半边，把安静门槛设成 0，
 * 看它会不会往桌宠收件箱塞一句新话。
 *   node lib/verify-selfwake.mjs
 */
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { apply } from './index.js';

const inbox = join(tmpdir(), 'dsh-pet-inbox.jsonl');
const startedAt = Date.now();

const ctx = {
  get: () => undefined,
  on: () => {},
  off: () => {},
  interval: (fn, ms) => {
    const t = setInterval(fn, ms);
    return () => clearInterval(t);
  },
  effect: (fn) => fn(),
};

apply(ctx, {
  tickMs: 1000,
  watchBalance: false,
  stateFile: join(tmpdir(), 'dsh-pet-state-verify2.json'),
  alertBelow: 0,
  budget: 0,
  selfwake: {
    enabled: true,
    intervalMinutes: 60,
    jitterMinutes: 0,
    minIdleMinutes: 0,
    maxUnanswered: 7,
    quietStartHour: 0,
    quietEndHour: 0,
    dailyMax: 3,
  },
});

await new Promise((r) => setTimeout(r, 3000));

let ok = false;
let last = '';
if (existsSync(inbox)) {
  const lines = readFileSync(inbox, 'utf8').split(/\r?\n/).filter(Boolean);
  last = lines[lines.length - 1] ?? '';
  try {
    const obj = JSON.parse(last);
    const ts = Date.parse(obj.ts);
    ok = obj.title === '大肥鱼' && Number.isFinite(ts) && Math.abs(ts - startedAt) < 15000;
  } catch { /* 解析不了就算失败 */ }
}

console.log('最新一条:', last);
console.log(ok ? '[PASS] 到点自己开口，已投进她的收件箱' : '[FAIL] 没开口');
setTimeout(() => process.exit(ok ? 0 : 1), 100);
