/**
 * dsh-desktop-pet · Host 半边
 *
 * 干三件事：
 *   ① 把桌上的小鲸鱼（pet/pet.ps1）拉起来并看住她；
 *   ② 每 tick 把「余额 / 今日已用 / 峰谷 / 上一轮消耗」算好，落到 %TEMP%\dsh-pet-state.json，她去读；
 *   ③ 她退出/插件卸载时收尾（卸载会留一张 quit 纸条，她自己体面地关窗）。
 *
 * 数据来源与 dsh-whale-widget 一致：
 *   - 余额：先 DEEPSEEK_API_KEY（ctx.credentials.resolve），再账号登录态（ctx.get('deepseekAccount')）；
 *   - 每轮消耗：ctx.on('session/event') 里 assistant/message 的 usage，按峰谷价目换算；
 *   - 峰谷：北京时间工作日 9-12、14-18 为峰，其余（含周末）为谷。
 */
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync, statSync, unlinkSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir, homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

export const name = 'desktop-pet';

/** timer 是硬需要；credentials / deepseekAccount 用 ctx.get 取，取不到就降级。 */
export const inject = ['timer'];

const HERE = dirname(fileURLToPath(import.meta.url));
const PET_DIR = join(HERE, '..', 'pet');
const PET_SCRIPT = join(PET_DIR, 'pet.ps1');

const DEFAULTS = {
  enabled: true,
  /** 多久把状态刷一次（毫秒） */
  tickMs: 5000,
  /** 余额多久查一次（毫秒） */
  balanceMs: 60000,
  /** 桌宠尺寸（像素） */
  scale: 220,
  /** 不看余额就填 false */
  watchBalance: true,
  /** 状态文件路径（默认 %TEMP%\dsh-pet-state.json；测试时换位置，避免和别的实例互踩） */
  stateFile: '',
  /** 余额低于这个值就在气泡里提醒（0 = 关） */
  alertBelow: 5,
  /** 今日已用超过这个值就在气泡里提醒（0 = 关） */
  budget: 10,
  /** 到点自己开口（把 dsh-selfwake 那套搬进来） */
  selfwake: {
    enabled: true,
    intervalMinutes: 60,
    jitterMinutes: 8,
    minIdleMinutes: 45,
    maxUnanswered: 7,
    quietStartHour: 22,
    quietEndHour: 8,
    dailyMax: 3,
  },
};

// ---- 价目（元 / 百万 token，[谷, 峰]；抄 dsh-whale-widget 的 PRICING） ----
const BASE_PRICE = { hit: [0.02, 0.04], miss: [1, 2], out: [4, 8] };
const PRO_PRICE = { hit: [0.15, 0.3], miss: [4.5, 9.0], out: [13.5, 27.0] };

export function priceFor(model = '') {
  const m = String(model).toLowerCase();
  // pro / reasoner 走高价表；其余（flash / chat）走基础表
  return m.includes('pro') || m.includes('reasoner') ? PRO_PRICE : BASE_PRICE;
}

/** 北京时间的小时；周末一律算谷。 */
export function isPeak(nowMs) {
  const shifted = new Date(nowMs + 8 * 3600 * 1000);
  const day = shifted.getUTCDay(); // 0 = 周日
  if (day === 0 || day === 6) return false;
  const hour = shifted.getUTCHours();
  return (hour >= 9 && hour < 12) || (hour >= 14 && hour < 18);
}

/** 峰谷文字 + 距下次切换多久。 */
export function peakText(nowMs) {
  const peak = isPeak(nowMs);
  const shifted = new Date(nowMs + 8 * 3600 * 1000);
  const next = new Date(shifted.getTime());
  // 逐分钟往后找下一个状态切换点（最多找 24 小时）
  for (let i = 1; i <= 24 * 60; i += 1) {
    next.setUTCMinutes(next.getUTCMinutes() + 1);
    if (isPeak(next.getTime() - 8 * 3600 * 1000) !== peak) {
      const mins = i;
      const h = Math.floor(mins / 60);
      const m = mins % 60;
      const tail = h > 0 ? `${h} 小时${m > 0 ? ` ${m} 分` : ''}` : `${m} 分`;
      return `${peak ? '峰价时段' : '谷价时段'} · ${tail}后切换`;
    }
  }
  return peak ? '峰价时段' : '谷价时段';
}

/** 单轮金额（元）。reasoning token 已含在 output 里，不另加。 */
export function turnCost(usage = {}, model = '', nowMs = Date.now()) {
  const p = priceFor(model);
  const off = isPeak(nowMs) ? 1 : 0;
  const cache = Number(usage.cacheReadTokens || 0);
  const input = Number(usage.inputTokens || 0);
  const output = Number(usage.outputTokens || 0);
  return (cache / 1e6) * p.hit[off] + (input / 1e6) * p.miss[off] + (output / 1e6) * p.out[off];
}

export function resolveConfig(input = {}) {
  const cfg = { ...DEFAULTS, ...(input ?? {}) };
  for (const k of ['tickMs', 'balanceMs', 'scale']) {
    if (!Number.isFinite(cfg[k]) || cfg[k] <= 0) cfg[k] = DEFAULTS[k];
  }
  if (typeof cfg.enabled !== 'boolean') cfg.enabled = DEFAULTS.enabled;
  if (typeof cfg.watchBalance !== 'boolean') cfg.watchBalance = DEFAULTS.watchBalance;
  if (typeof cfg.stateFile !== 'string') cfg.stateFile = DEFAULTS.stateFile;
  if (!Number.isFinite(cfg.alertBelow) || cfg.alertBelow < 0) cfg.alertBelow = DEFAULTS.alertBelow;
  if (!Number.isFinite(cfg.budget) || cfg.budget < 0) cfg.budget = DEFAULTS.budget;
  cfg.selfwake = { ...DEFAULTS.selfwake, ...(input?.selfwake ?? {}) };
  const sw = cfg.selfwake;
  for (const k of ['intervalMinutes', 'jitterMinutes', 'minIdleMinutes', 'maxUnanswered', 'quietStartHour', 'quietEndHour', 'dailyMax']) {
    if (!Number.isFinite(sw[k]) || sw[k] < 0) sw[k] = DEFAULTS.selfwake[k];
  }
  if (typeof sw.enabled !== 'boolean') sw.enabled = DEFAULTS.selfwake.enabled;
  return cfg;
}

/** 用量汇总：今日 / 近 7 天 / 合计 / 按模型 / 最近若干条。 */
export function summarizeUsage(events, nowMs = Date.now()) {
  const dayOf = (ts) => new Date(ts + 8 * 3600 * 1000).toISOString().slice(0, 10);
  const today = dayOf(nowMs);
  const weekAgo = nowMs - 7 * 86400_000;
  const out = { todayCost: 0, todayTokens: 0, weekCost: 0, totalCost: 0, totalTokens: 0, byModel: [], recent: [] };
  const models = new Map();
  for (const e of events) {
    const cost = Number(e.cost || 0);
    const tokens = Number(e.tokens || 0);
    out.totalCost += cost;
    out.totalTokens += tokens;
    if (dayOf(Number(e.ts || 0)) === today) {
      out.todayCost += cost;
      out.todayTokens += tokens;
    }
    if (Number(e.ts || 0) >= weekAgo) out.weekCost += cost;
    const m = String(e.model || '未知模型');
    const cur = models.get(m) ?? { model: m, cost: 0, tokens: 0, count: 0 };
    cur.cost += cost;
    cur.tokens += tokens;
    cur.count += 1;
    models.set(m, cur);
  }
  out.byModel = [...models.values()].sort((a, b) => b.cost - a.cost);
  out.recent = events.slice(-20).reverse().map((e) => ({
    ts: Number(e.ts || 0),
    cost: Number(e.cost || 0),
    tokens: Number(e.tokens || 0),
    model: String(e.model || ''),
  }));
  return out;
}

function readJson(path, fallback) {
  try {
    if (!existsSync(path)) return fallback;
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJsonAtomic(path, obj) {
  try {
    mkdirSync(dirname(path), { recursive: true });
    const tmp = `${path}.tmp`;
    writeFileSync(tmp, JSON.stringify(obj), 'utf8');
    renameSync(tmp, path);
  } catch {
    /* 写不进去就算了，桌宠那边用旧数据 */
  }
}

export function apply(ctx, input = {}) {
  const cfg = resolveConfig(input);
  const home = process.env.DSH_HOME || join(homedir(), '.dsh');
  const stateFile = cfg.stateFile || join(tmpdir(), 'dsh-pet-state.json');
  const aliveFile = join(tmpdir(), 'dsh-pet-alive.txt');
  const quitFile = join(tmpdir(), 'dsh-pet-quit.txt');
  const ledgerFile = join(home, '.dsh-pet-ledger.json');
  const logFile = join(home, 'desktop-pet.log');

  const say = (line) => {
    try {
      mkdirSync(home, { recursive: true });
      writeFileSync(logFile, `${new Date().toISOString()} ${line}\r\n`, { flag: 'a' });
    } catch {
      /* 日志失败不影响主流程 */
    }
  };

  const hasCred = typeof ctx.get('credentials')?.resolve === 'function';
  const hasAcct = typeof ctx.get('deepseekAccount')?.getBalance === 'function';
  say(`[boot] 服务：credentials=${hasCred} deepseekAccount=${hasAcct}`);

  if (!cfg.enabled) {
    say('[apply] enabled=false，什么都不做');
    return;
  }

  // ---------- 往她的收件箱塞一句话（桌宠每秒读，弹气泡） ----------
  const inboxFile = join(tmpdir(), 'dsh-pet-inbox.jsonl');
  const pushBubble = (title, body) => {
    try {
      const line = `${JSON.stringify({ title, body, ts: new Date().toISOString() })}\r\n`;
      writeFileSync(inboxFile, line, { encoding: 'utf8', flag: 'a' });
      return true;
    } catch (error) {
      say(`[bubble] 投递失败：${String(error?.message ?? error)}`);
      return false;
    }
  };

  // ---------- 提醒（余额预警 / 今日预算），同一天只提醒一次 ----------
  const alertState = readJson(join(home, '.dsh-pet-alerts.json'), { day: '', balance: false, budget: false });
  const todayKey = () => new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);
  const checkAlerts = (balance, todayUsed) => {
    const day = todayKey();
    if (alertState.day !== day) {
      alertState.day = day;
      alertState.balance = false;
      alertState.budget = false;
    }
    let changed = false;
    if (cfg.alertBelow > 0 && balance !== null && balance < cfg.alertBelow && !alertState.balance) {
      alertState.balance = true;
      changed = true;
      pushBubble('余额预警', `余额只剩 ¥${balance.toFixed(2)} 了喵（阈值 ¥${cfg.alertBelow}）`);
      say(`[alert] 余额预警：¥${balance.toFixed(2)} < ¥${cfg.alertBelow}`);
    }
    if (cfg.budget > 0 && todayUsed > cfg.budget && !alertState.budget) {
      alertState.budget = true;
      changed = true;
      pushBubble('今日预算', `今天已经花了 ¥${todayUsed.toFixed(2)} 喵（预算 ¥${cfg.budget}）`);
      say(`[alert] 预算提醒：¥${todayUsed.toFixed(2)} > ¥${cfg.budget}`);
    }
    if (changed) writeJsonAtomic(join(home, '.dsh-pet-alerts.json'), alertState);
  };

  // ---------- 到点自己开口（dsh-selfwake 的那套闸门） ----------
  const swFile = join(home, '.dsh-pet-selfwake.json');
  const sw = readJson(swFile, { lastSpokeAt: 0, nextAllowedAt: 0, dailyDay: '', dailyCount: 0, unanswered: 0, fired: 0 });
  let lastUserAt = Date.now();
  let poolCache = null;
  const getPool = () => {
    if (poolCache) return poolCache;
    const candidates = [join(PET_DIR, 'lines.txt'), join(home, 'selfwake', 'pool-默认.txt')];
    const lines = [];
    for (const f of candidates) {
      try {
        if (!existsSync(f)) continue;
        for (const raw of readFileSync(f, 'utf8').split(/\r?\n/)) {
          const s = raw.trim();
          if (s && !s.startsWith('#')) lines.push(s);
        }
        if (lines.length) break;
      } catch { /* 读不到就换下一个 */ }
    }
    poolCache = lines.length ? lines : ['主人，我在这儿喵'];
    return poolCache;
  };
  const inQuiet = (now) => {
    const h = new Date(now + 8 * 3600 * 1000).getUTCHours();
    const { quietStartHour: a, quietEndHour: b } = cfg.selfwake;
    return a === b ? false : (a < b ? h >= a && h < b : h >= a || h < b);
  };
  const maybeSpeak = (now) => {
    const c = cfg.selfwake;
    if (!c.enabled) return;
    if (inQuiet(now)) return;
    if (sw.dailyDay !== todayKey()) {
      sw.dailyDay = todayKey();
      sw.dailyCount = 0;
    }
    if (c.dailyMax > 0 && sw.dailyCount >= c.dailyMax) return;
    if (now < sw.nextAllowedAt) return;
    if (now - lastUserAt < c.minIdleMinutes * 60_000) return;
    if (sw.unanswered >= c.maxUnanswered) return;

    const pool = getPool();
    const line = pool[Math.floor(Math.random() * pool.length)];
    if (pushBubble('大肥鱼', line)) {
      sw.fired += 1;
      sw.lastSpokeAt = now;
      sw.dailyCount += 1;
      sw.unanswered += 1;
      const base = c.intervalMinutes * 60_000;
      const jitter = c.jitterMinutes * 60_000 * (Math.random() * 2 - 1);
      const backoff = 1 + sw.unanswered * 0.5;
      sw.nextAllowedAt = now + Math.max(5 * 60_000, base * backoff + jitter);
      writeJsonAtomic(swFile, sw);
      say(`[selfwake] 到点开口（今天第 ${sw.dailyCount} 次，没回 ${sw.unanswered} 次）：${line}`);
    }
  };

  // ---------- 桌宠进程 ----------
  let child = null;
  const petAlive = () => {
    try {
      if (!existsSync(aliveFile)) return false;
      return Date.now() - statSync(aliveFile).mtimeMs < 15000;
    } catch {
      return false;
    }
  };

  const startPet = () => {
    if (petAlive()) return;
    if (!existsSync(PET_SCRIPT)) {
      say(`[pet] 找不到脚本：${PET_SCRIPT}`);
      return;
    }
    const vbs = join(PET_DIR, 'start-pet.vbs');
    try {
      try { unlinkSync(quitFile); } catch { /* 没有就算了 */ }
      // 用 wscript 当二传手：DSH 宿主是没有控制台的 GUI 进程，
      // 直接从它 spawn powershell.exe 会因为拿不到控制台而瞬间以 0 退出；
      // wscript 是 GUI 子系统，再由它用窗口样式 0 拉起 powershell 就正常了。
      child = spawn('wscript.exe', [vbs], {
        detached: false,
        stdio: 'ignore',
        windowsHide: true,
      });
      child.unref();
      say(`[pet] 已拉起 pid=${child.pid}`);
    } catch (error) {
      say(`[pet] 拉起失败：${String(error?.message ?? error)}`);
    }
  };

  // ---------- 余额 ----------
  let balanceCache = { at: 0, value: null, note: '' };

  const fetchBalance = async () => {
    const now = Date.now();
    if (now - balanceCache.at < cfg.balanceMs) return balanceCache;
    let result = { at: now, value: null, note: '' };

    const creds = ctx.get('credentials');
    if (creds && typeof creds.resolve === 'function') {
      try {
        const cred = await creds.resolve('DEEPSEEK_API_KEY');
        const key = cred && cred.value;
        if (key) {
          const res = await fetch('https://api.deepseek.com/user/balance', {
            headers: { Authorization: `Bearer ${key}` },
            signal: AbortSignal.timeout(8000),
          });
          if (res.ok) {
            const data = await res.json();
            const infos = Array.isArray(data?.balance_infos) ? data.balance_infos : [];
            const pick = infos.find((i) => i.currency === 'CNY' && Number(i.total_balance) > 0) ?? infos[0];
            if (pick) result = { at: now, value: Number(pick.total_balance), note: '' };
            else result = { at: now, value: 0, note: '余额字段为空' };
          } else {
            result = { at: now, value: null, note: `余额接口 ${res.status}` };
          }
        } else {
          result = { at: now, value: null, note: '没配 DEEPSEEK_API_KEY' };
        }
      } catch (error) {
        result = { at: now, value: null, note: `余额请求失败` };
        say(`[balance] 请求失败：${String(error?.message ?? error)}`);
      }
    }

    // API key 拿不到 → 账号登录态
    if (result.value === null) {
      const acct = ctx.get('deepseekAccount');
      if (acct && typeof acct.getBalance === 'function') {
        try {
          const r = await acct.getBalance({
            version: 1,
            locale: 'zh-CN',
            timezoneOffsetSeconds: -new Date().getTimezoneOffset() * 60,
          });
          if (r && r.status === 'ready') {
            const wallets = [...(r.value ?? []), ...(r.bonusWallets ?? [])];
            const total = wallets.reduce((sum, w) => sum + Number(w?.balance ?? 0), 0);
            result = { at: now, value: total, note: '' };
          } else {
            result = { at: now, value: null, note: result.note || '账号余额未登录' };
          }
        } catch (error) {
          say(`[balance] 账号余额失败：${String(error?.message ?? error)}`);
        }
      }
    }

    balanceCache = result;
    return result;
  };

  // ---------- 今日已用（余额下降累计） ----------
  const observeUsage = (balance) => {
    const today = new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);
    const led = readJson(ledgerFile, { day: today, lastBalance: null, todayUsed: 0 });
    if (led.day !== today) {
      led.day = today;
      led.lastBalance = balance;
      led.todayUsed = 0;
    } else if (balance !== null && led.lastBalance !== null) {
      const delta = led.lastBalance - balance;
      if (delta > 0) led.todayUsed = Number(led.todayUsed || 0) + delta; // 余额降 = 花掉
    }
    if (balance !== null) led.lastBalance = balance;
    writeJsonAtomic(ledgerFile, led);
    return Number(led.todayUsed || 0);
  };

  // ---------- 每轮消耗 ----------
  const seenEvents = new Set();
  const turn = { seq: 0, cost: 0, model: '', at: 0, pending: new Map() };

  const onSessionEvent = (session, event) => {
    try {
      const sid = session?.id ?? 'default';
      const ev = event ?? {};
      // 有人在说话 → 更新"安静多久"和"没被回"的计数
      if (ev.type === 'agent/inbox/spliced' || ev.type === 'turn/start') {
        lastUserAt = Date.now();
        if (sw.unanswered !== 0) {
          sw.unanswered = 0;
          writeJsonAtomic(swFile, sw);
        }
      }
      // 头几个事件把原始形状打出来，省得靠猜（只在抓到前 3 个时写日志）
      if (ev.type && seenEvents.size < 3) {
        seenEvents.add(`${ev.type}`);
        say(`[event] ${ev.type} :: ${JSON.stringify(ev).slice(0, 400)}`);
      }
      // 一轮里可能有多次 assistant/message，先把最全的那次 usage 记下来
      if (ev.type === 'assistant/message') {
        const usage = ev.message?.usage ?? ev.usage ?? null;
        const model = ev.message?.source?.model ?? ev.model ?? '';
        if (usage) {
          const prev = turn.pending.get(sid) ?? { usage: {}, model: '', at: 0 };
          const pick = (a, b) => (Number(b || 0) > Number(a || 0) ? b : a);
          prev.usage = {
            inputTokens: pick(prev.usage.inputTokens, usage.inputTokens),
            cacheReadTokens: pick(prev.usage.cacheReadTokens, usage.cacheReadTokens),
            outputTokens: pick(prev.usage.outputTokens, usage.outputTokens),
          };
          if (model) prev.model = model;
          prev.at = Date.now();
          turn.pending.set(sid, prev);
        }
      }
      if (ev.type === 'turn/end') {
        const got = turn.pending.get(sid);
        turn.pending.delete(sid);
        if (got) {
          const cost = turnCost(got.usage, got.model, Date.now());
          if (cost > 0) {
            turn.seq += 1;
            turn.cost = cost;
            turn.model = got.model || '';
            turn.at = Date.now();
            say(`[turn] 第 ${turn.seq} 轮 ¥${cost.toFixed(4)}（${got.model || '未知模型'}）`);
          }
        }
      }
    } catch (error) {
      say(`[turn] 解析出错：${String(error?.message ?? error)}`);
    }
  };

  // 订阅：主路是 session/event（与 dsh-whale-widget 一致）；
  // 另外两条是保险丝——万一桌面宿主的事件名不同，也能看出来到底哪个名字在响
  const subscribed = [];
  for (const evName of ['session/event', 'session/turn/end', 'turn/end']) {
    try {
      ctx.on(evName, onSessionEvent);
      subscribed.push(evName);
    } catch (error) {
      say(`[apply] 订阅 ${evName} 失败：${String(error?.message ?? error)}`);
    }
  }
  say(`[apply] 订阅事件：${subscribed.join(', ') || '（一个都没订上）'}`);
  try {
    writeFileSync(join(tmpdir(), 'dsh-pet-boot.json'), JSON.stringify({
      at: new Date().toISOString(),
      version: 'r2',
      hasCred,
      hasAcct,
      subscribed,
      petDir: PET_DIR,
    }, null, 2), 'utf8');
  } catch { /* 探针写不出来不影响 */ }

  // ---------- 每轮消耗的兜底来源 ----------
  // 万一 session/event 在这个宿主里没喂到我们（桌面端事件名可能不一样），
  // 就直接读 dsh-whale-widget 的账本 —— 它本来就在按同样的口径记每轮消耗。
  const widgetUsageFile = join(home, '.dshw-usage.json');
  const fallbackTurn = { ts: 0, seq: 0, cost: 0, model: '' };
  const readFallbackTurn = () => {
    try {
      const j = readJson(widgetUsageFile, null);
      const list = Array.isArray(j?.events) ? j.events : [];
      if (list.length === 0) return null;
      const last = list[list.length - 1];
      return { ts: Number(last.ts || 0), cost: Number(last.cost || 0), model: String(last.model || '') };
    } catch {
      return null;
    }
  };

  // ---------- 状态落地 ----------
  const publish = async () => {
    startPet();
    const bal = cfg.watchBalance ? await fetchBalance() : { value: null, note: '' };
    const used = observeUsage(bal.value);
    const now = Date.now();

    // 事件路优先；一条事件都没收到时走账本兜底
    let seq = turn.seq;
    let cost = turn.cost;
    let model = turn.model;
    if (seq === 0) {
      const fb = readFallbackTurn();
      if (fb && fb.ts > fallbackTurn.ts) {
        fallbackTurn.ts = fb.ts;
        fallbackTurn.seq += 1;
        fallbackTurn.cost = fb.cost;
        fallbackTurn.model = fb.model;
        say(`[turn] 账本兜底：第 ${fallbackTurn.seq} 轮 ¥${fb.cost.toFixed(4)}（${fb.model || '未知模型'}）`);
      }
      if (fallbackTurn.seq > 0) {
        seq = fallbackTurn.seq;
        cost = fallbackTurn.cost;
        model = fallbackTurn.model;
      }
    }

    // 用量汇总 + 两条提醒 + 到点自己开口
    let usage = null;
    try {
      const ledger = readJson(widgetUsageFile, null);
      const events = Array.isArray(ledger?.events) ? ledger.events : [];
      usage = summarizeUsage(events, now);
    } catch { /* 汇总失败不影响主流程 */ }
    try { checkAlerts(bal.value, used); } catch (e) { say(`[alert] 出错：${String(e?.message ?? e)}`); }
    try { maybeSpeak(now); } catch (e) { say(`[selfwake] 出错：${String(e?.message ?? e)}`); }

    const state = {
      updatedAt: new Date(now).toISOString(),
      balance: bal.value,
      todayUsed: used,
      peakText: peakText(now),
      isPeak: isPeak(now),
      turnSeq: seq,
      turnCost: seq > 0 ? Number(cost.toFixed(6)) : null,
      lastModel: model,
      model: model || '',
      note: bal.value === null ? bal.note || '余额取不到' : '',
      alertBelow: cfg.alertBelow,
      budget: cfg.budget,
      usage,
      selfwake: {
        enabled: cfg.selfwake.enabled,
        dailyCount: sw.dailyCount,
        dailyMax: cfg.selfwake.dailyMax,
        unanswered: sw.unanswered,
        nextAt: sw.nextAllowedAt ? new Date(sw.nextAllowedAt).toISOString() : '',
      },
    };
    writeJsonAtomic(stateFile, state);
  };

  startPet();
  Promise.resolve().then(publish).catch((e) => say(`[publish] 初见失败：${String(e?.message ?? e)}`));

  const stop = ctx.interval(() => {
    Promise.resolve()
      .then(publish)
      .catch((error) => say(`[tick] 出错（不影响下轮）：${String(error?.message ?? error)}`));
  }, cfg.tickMs);

  ctx.effect(() => () => {
    try { if (typeof stop === 'function') stop(); } catch { /* ignore */ }
    try {
      ctx.off?.('session/event', onSessionEvent);
    } catch { /* ignore */ }
    // 留张纸条让她自己关窗（不去 kill，免得留下半个进程）
    try {
      writeFileSync(quitFile, new Date().toISOString(), 'utf8');
    } catch { /* ignore */ }
    say('[stop] 桌面小鲸鱼已请她退场');
  });

  say(`[apply] 桌面小鲸鱼起来了：每 ${Math.round(cfg.tickMs / 1000)}s 刷状态 / 每 ${Math.round(cfg.balanceMs / 1000)}s 查余额 / 尺寸 ${cfg.scale}`);
  say(`[apply] 提醒：余额<¥${cfg.alertBelow} / 今日>¥${cfg.budget}；自己开口：${cfg.selfwake.enabled ? `开（${cfg.selfwake.intervalMinutes}±${cfg.selfwake.jitterMinutes} 分 / 安静 ≥${cfg.selfwake.minIdleMinutes} 分 / 每天 ≤${cfg.selfwake.dailyMax} 次 / 静默 ${cfg.selfwake.quietStartHour}-${cfg.selfwake.quietEndHour} 点）` : '关'}`);
}
