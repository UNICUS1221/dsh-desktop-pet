/**
 * 开发用：在 DSH 之外把 host 半边跑起来（假 ctx），方便不重启 DSH 也能看效果。
 *   node lib/dev-run.mjs
 * 真装载时走 cordis，不需要这个文件。
 */
import { apply } from './index.js';

const handlers = [];
const timers = new Set();

const ctx = {
  get: () => undefined,
  on: (name, fn) => {
    handlers.push([name, fn]);
    return fn;
  },
  off: () => {},
  interval: (fn, ms) => {
    const t = setInterval(fn, ms);
    timers.add(t);
    return () => clearInterval(t);
  },
  effect: (fn) => {
    fn();
  },
};

apply(ctx, { tickMs: 5000, balanceMs: 60000, scale: 220, watchBalance: false });
console.log('[dev] host 半边已启动；Ctrl+C 退出');

// 假的一条会话事件，验证每轮消耗链路（会写进 state.json 的 turnSeq）
setTimeout(() => {
  const h = handlers.find(([n]) => n === 'session/event');
  if (!h) {
    console.log('[dev] 没有 session/event 订阅者');
    return;
  }
  const fn = h[1];
  fn({ id: 'dev-session' }, {
    type: 'assistant/message',
    message: { usage: { inputTokens: 12000, cacheReadTokens: 30000, outputTokens: 800 }, source: { model: 'deepseek-flash' } },
  });
  fn({ id: 'dev-session' }, { type: 'turn/end' });
  console.log('[dev] 打了一条假的轮次事件');
}, 3000);

const keep = setInterval(() => {}, 1 << 30);
keep.unref?.();
