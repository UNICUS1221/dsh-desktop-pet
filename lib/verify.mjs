/**
 * 验证用：不重启 DSH，直接跑 host 半边，看它会不会：
 *   ① 写出 state.json；② 从账本兜底拿到上一轮消耗。
 *   node lib/verify.mjs
 */
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir, homedir } from 'node:os';
import { apply } from './index.js';

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

apply(ctx, { tickMs: 2000, balanceMs: 60000, scale: 220, watchBalance: false, stateFile: join(tmpdir(), 'dsh-pet-state-verify.json') });

const stateFile = join(tmpdir(), 'dsh-pet-state-verify.json');
const bootFile = join(tmpdir(), 'dsh-pet-boot.json');

await new Promise((r) => setTimeout(r, 5000));

const state = existsSync(stateFile) ? JSON.parse(readFileSync(stateFile, 'utf8')) : null;
const boot = existsSync(bootFile) ? JSON.parse(readFileSync(bootFile, 'utf8')) : null;

console.log('boot =', JSON.stringify(boot));
console.log('state =', JSON.stringify(state));

const ok = state && Number.isFinite(state.turnSeq) && state.turnSeq > 0 && state.turnCost > 0;
console.log(ok ? '[PASS] 账本兜底拿到了每轮消耗' : '[FAIL] 没拿到每轮消耗');
process.exit(ok ? 0 : 1);
