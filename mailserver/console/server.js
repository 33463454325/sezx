'use strict';
// HTTPS-консоль для ручной отправки писем через собственный почтовый сервер.
// Защита от спама встроена: вход по паролю, отправка только с ваших ящиков,
// лимиты в час и в сутки (с «прогревом» нового IP), не более N получателей,
// проверка домена получателя, список отклонённых адресов, проверка текста.

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const dns = require('dns').promises;
const { promisify } = require('util');
const nodemailer = require('nodemailer');
const { lint } = require('./lint');
const scrypt = promisify(crypto.scrypt);

// ------------------------------------------------------------------ конфигурация
const DATA_DIR = process.env.DATA_DIR || '/data';
const CONFIG_PATH = process.env.CONFIG_PATH || path.join(DATA_DIR, 'config.json');
const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));

const MAIL_HOST = cfg.mailHost || 'mail.localhost';
const SMTP_HOST = cfg.smtpHost || '127.0.0.1';
const SMTP_PORT = Number(cfg.smtpPort || 587);
const PORT = Number(process.env.PORT || cfg.port || 8443);
const HTTPS_ON = process.env.INSECURE_HTTP !== '1';
const MAX_RECIPIENTS = Number(cfg.maxRecipients || 5);
const PER_HOUR = Number(cfg.perHour || 20);
const ALLOWED_IPS = Array.isArray(cfg.allowedIps) ? cfg.allowedIps : [];
const PUBLIC_DIR = path.join(__dirname, 'public');

const accounts = {};
for (const [addr, v] of Object.entries(cfg.accounts || {})) {
  accounts[addr.toLowerCase()] = { pass: typeof v === 'string' ? v : v.pass, name: (v && v.name) || '' };
}
if (!Object.keys(accounts).length) throw new Error('В config.json нет ни одного ящика (accounts)');
if (!cfg.adminPassword || String(cfg.adminPassword).length < 10) throw new Error('adminPassword должен быть не короче 10 символов');

// пароль администратора хранится в памяти только как scrypt-хеш
const SALT = crypto.randomBytes(16);
const ADMIN_HASH = crypto.scryptSync(String(cfg.adminPassword), SALT, 32);

// ------------------------------------------------------------------ хранилище
fs.mkdirSync(DATA_DIR, { recursive: true });
const LOG_FILE = path.join(DATA_DIR, 'sent.jsonl');
const STATE_FILE = path.join(DATA_DIR, 'state.json');
const SUPPRESS_FILE = path.join(DATA_DIR, 'suppressed.json');

function readJson(file, fallback) { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; } }
function writeJson(file, obj) { fs.writeFileSync(file, JSON.stringify(obj, null, 2), { mode: 0o600 }); }

const state = readJson(STATE_FILE, null) || { startedAt: Date.now() };
if (!state.startedAt) state.startedAt = Date.now();
writeJson(STATE_FILE, state);

const suppressed = readJson(SUPPRESS_FILE, {});   // { "addr": { reason, at } }

let history = [];
try {
  history = fs.readFileSync(LOG_FILE, 'utf8').split('\n').filter(Boolean).slice(-5000).map((l) => JSON.parse(l));
} catch { /* файла ещё нет */ }
function pushLog(entry) {
  history.push(entry);
  if (history.length > 5000) history.shift();
  fs.appendFileSync(LOG_FILE, JSON.stringify(entry) + '\n', { mode: 0o600 });
}

// ------------------------------------------------------------------ лимиты
function warmupDay() { return Math.floor((Date.now() - state.startedAt) / 86400000) + 1; }
function dailyLimit() {
  if (cfg.dailyLimit) return Number(cfg.dailyLimit);
  if (cfg.warmup === false) return 300;
  const d = warmupDay();
  if (d <= 3) return 10;
  if (d <= 7) return 30;
  if (d <= 14) return 100;
  return 300;
}
function usage() {
  const now = Date.now();
  let hour = 0, day = 0;
  for (const e of history) {
    if (e.status !== 'sent') continue;
    const age = now - Date.parse(e.t);
    const n = (e.to || []).length;
    if (age < 3600e3) hour += n;
    if (age < 86400e3) day += n;
  }
  return { hour: { used: hour, limit: PER_HOUR }, day: { used: day, limit: dailyLimit() }, warmupDay: warmupDay(), maxRecipients: MAX_RECIPIENTS };
}

// ------------------------------------------------------------------ утилиты
const EMAIL_RE = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]{1,64}@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/;
const isEmail = (s) => typeof s === 'string' && s.length <= 254 && EMAIL_RE.test(s);
const norm = (s) => String(s || '').trim().toLowerCase();

function parseList(v) {
  const arr = Array.isArray(v) ? v : String(v || '').split(/[\s,;]+/);
  return [...new Set(arr.map(norm).filter(Boolean))];
}

function cleanName(s) {
  return String(s || '').replace(/[\r\n"<>\\]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60);
}

async function domainCanReceive(domain) {
  const missing = (e) => e && (e.code === 'ENODATA' || e.code === 'ENOTFOUND' || e.code === 'NXDOMAIN');
  try {
    const mx = await dns.resolveMx(domain);
    if (mx.length === 1 && mx[0].exchange === '') return false;      // «Null MX»: домен не принимает почту
    if (mx.length) return true;
  } catch (e) { if (!missing(e)) return true; }                      // сбой DNS — не блокируем
  try { return (await dns.resolve4(domain)).length > 0; } catch (e) { return !missing(e); }
}

function ipAllowed(ip) {
  if (!ALLOWED_IPS.length) return true;
  const plain = String(ip || '').replace(/^::ffff:/, '');
  return ALLOWED_IPS.includes(plain);
}

// ------------------------------------------------------------------ сессии и защита входа
const sessions = new Map();     // sid -> { csrf, expires, last }
const attempts = new Map();     // ip -> { n, first }
const SESSION_ABS = 12 * 3600e3, SESSION_IDLE = 2 * 3600e3;
const LOGIN_MAX = 5, LOGIN_WINDOW = 15 * 60e3;

setInterval(() => {
  const now = Date.now();
  for (const [k, s] of sessions) if (now > s.expires || now - s.last > SESSION_IDLE) sessions.delete(k);
  for (const [k, a] of attempts) if (now - a.first > LOGIN_WINDOW) attempts.delete(k);
}, 60e3).unref();

function parseCookies(req) {
  const out = {};
  for (const part of String(req.headers.cookie || '').split(';')) {
    const i = part.indexOf('=');
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  }
  return out;
}
function getSession(req) {
  const sid = parseCookies(req).sid;
  const s = sid && sessions.get(sid);
  if (!s) return null;
  const now = Date.now();
  if (now > s.expires || now - s.last > SESSION_IDLE) { sessions.delete(sid); return null; }
  s.last = now;
  s.sid = sid;
  return s;
}
function safeEqual(a, b) {
  const x = Buffer.from(String(a)), y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

// ------------------------------------------------------------------ HTTP-помощники
const SEC_HEADERS = {
  'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'no-referrer',
  'Cache-Control': 'no-store',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Resource-Policy': 'same-origin',
};
if (HTTPS_ON) SEC_HEADERS['Strict-Transport-Security'] = 'max-age=31536000';

function send(res, status, body, headers = {}) {
  res.writeHead(status, { ...SEC_HEADERS, ...headers });
  res.end(body);
}
function sendJson(res, status, obj, headers = {}) {
  send(res, status, JSON.stringify(obj), { 'Content-Type': 'application/json; charset=utf-8', ...headers });
}

function readBody(req, limit = 600 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) { reject(Object.assign(new Error('too large'), { status: 413 })); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}
async function readJsonBody(req) {
  const raw = await readBody(req);
  try { return raw ? JSON.parse(raw) : {}; } catch { throw Object.assign(new Error('bad json'), { status: 400 }); }
}

const STATIC = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/app.js': ['app.js', 'text/javascript; charset=utf-8'],
  '/app.css': ['app.css', 'text/css; charset=utf-8'],
};

// ------------------------------------------------------------------ отправка
let sending = false;

function friendlySmtpError(err) {
  const r = String(err && err.response || '');
  if (err && err.code === 'EAUTH') return 'Почтовый сервер не принял пароль ящика. Проверьте /opt/mailserver/console-data/config.json.';
  if (err && (err.code === 'ECONNECTION' || err.code === 'ESOCKET' || err.code === 'ETIMEDOUT')) return 'Не удалось соединиться с почтовым сервером (порт 587). Проверьте, что контейнер mailserver запущен.';
  if (/rate|too many|limit/i.test(r)) return 'Почтовый сервер временно ограничил скорость отправки. Подождите и повторите.';
  return (r || (err && err.message) || 'Неизвестная ошибка отправки').slice(0, 300);
}

async function handleSend(req, res) {
  const b = await readJsonBody(req);
  const fail = (status, error, extra = {}) => sendJson(res, status, { ok: false, error, ...extra });

  // отправитель — только собственные ящики
  const from = norm(b.from);
  const account = accounts[from];
  if (!account) return fail(400, 'Отправлять можно только с ящиков, созданных на этом сервере: ' + Object.keys(accounts).join(', '));

  // получатели
  const to = parseList(b.to), cc = parseList(b.cc), bcc = parseList(b.bcc);
  const all = [...new Set([...to, ...cc, ...bcc])];
  if (!to.length) return fail(422, 'Укажите хотя бы одного получателя в поле «Кому».');
  const badAddr = all.find((a) => !isEmail(a));
  if (badAddr) return fail(422, `Некорректный адрес: ${badAddr}`);
  if (all.length > MAX_RECIPIENTS) return fail(422, `Слишком много получателей (${all.length}). Максимум ${MAX_RECIPIENTS}: это консоль для личной переписки, а не для рассылок.`);
  const replyTo = norm(b.replyTo);
  if (replyTo && !isEmail(replyTo)) return fail(422, 'Некорректный адрес в поле «Ответить на».');

  // тема и тело
  const subject = String(b.subject || '').trim();
  if (subject.length > 200) return fail(422, 'Тема слишком длинная (максимум 200 символов).');
  const textIn = String(b.text || ''), htmlIn = String(b.html || '');
  if (textIn.length > 200e3 || htmlIn.length > 200e3) return fail(422, 'Письмо слишком большое (максимум 200 КБ на часть).');
  const result = lint({ subject, text: textIn, html: htmlIn });
  const errors = result.issues.filter((i) => i.level === 'error');
  if (errors.length) return fail(422, errors[0].text, { issues: result.issues });

  // список адресов, которые сервер уже отклонял
  const sup = all.find((a) => suppressed[a]);
  if (sup) return fail(422, `Адрес ${sup} ранее был отклонён почтовым сервером получателя. Повторные попытки вредят репутации — исправьте адрес или уберите его.`);

  // Одно письмо за раз. Замок берём ДО проверки лимитов и DNS: иначе параллельные
  // запросы проходят проверку по одному и тому же счётчику и превышают лимит.
  if (sending) return fail(429, 'Предыдущее письмо ещё отправляется. Подождите пару секунд.');
  sending = true;
  const entry = { t: new Date().toISOString(), from, to: all, subject, status: 'failed' };
  try {
    // лимиты
    const u = usage();
    if (u.hour.used + all.length > u.hour.limit) return fail(429, `Лимит в час исчерпан (${u.hour.used} из ${u.hour.limit}). Подождите немного.`);
    if (u.day.used + all.length > u.day.limit) return fail(429, `Дневной лимит исчерпан (${u.day.used} из ${u.day.limit}). Лимит растёт по мере «прогрева» нового IP.`);

    // домены получателей должны существовать и принимать почту
    if (process.env.SKIP_MX_CHECK !== '1') {
      for (const d of [...new Set(all.map((a) => a.split('@')[1]))]) {
        if (!(await domainCanReceive(d))) return fail(422, `Домен «${d}» не принимает почту (нет MX-записей). Проверьте адрес на опечатки.`);
      }
    }

    const fromName = cleanName(b.fromName) || cleanName(account.name);
    const transport = nodemailer.createTransport({
      host: SMTP_HOST, port: SMTP_PORT, secure: false, requireTLS: true, name: MAIL_HOST,
      auth: { user: from, pass: account.pass },
      tls: { servername: MAIL_HOST, rejectUnauthorized: process.env.SMTP_TLS_INSECURE !== '1' },
      connectionTimeout: 15000, greetingTimeout: 15000, socketTimeout: 60000,
    });
    const info = await transport.sendMail({
      from: fromName ? { name: fromName, address: from } : from,
      to, cc: cc.length ? cc : undefined, bcc: bcc.length ? bcc : undefined,
      replyTo: replyTo || undefined,
      subject,
      text: result.text,
      html: result.html || undefined,
      xMailer: false,
    });
    transport.close();
    entry.status = info.rejected && info.rejected.length ? (info.accepted.length ? 'partial' : 'failed') : 'sent';
    entry.messageId = info.messageId;
    if (info.rejected && info.rejected.length) {
      entry.error = 'Отклонены сервером: ' + info.rejected.join(', ');
      for (const a of info.rejected) suppressed[norm(a)] = { reason: 'rejected', at: entry.t };
      writeJson(SUPPRESS_FILE, suppressed);
    }
    if (entry.status === 'partial') entry.status = 'sent';
    pushLog(entry);
    if (info.accepted && !info.accepted.length) return fail(502, entry.error || 'Сервер отклонил всех получателей.');
    return sendJson(res, 200, { ok: true, messageId: info.messageId, accepted: info.accepted, rejected: info.rejected, usage: usage(), issues: result.issues });
  } catch (err) {
    entry.error = friendlySmtpError(err);
    // постоянный отказ для получателя (5xx) — запоминаем, чтобы не долбить повторно
    if (err && err.responseCode >= 500 && err.rejected && err.rejected.length) {
      for (const a of err.rejected) suppressed[norm(a)] = { reason: entry.error, at: entry.t };
      writeJson(SUPPRESS_FILE, suppressed);
    }
    pushLog(entry);
    return fail(502, entry.error);
  } finally {
    sending = false;
  }
}

// ------------------------------------------------------------------ маршруты
async function handler(req, res) {
  try {
    if (!ipAllowed(req.socket.remoteAddress)) return send(res, 403, 'Forbidden', { 'Content-Type': 'text/plain' });
    const url = new URL(req.url, 'http://x');
    const p = url.pathname;

    if (req.method === 'GET' && STATIC[p]) {
      const [file, type] = STATIC[p];
      return send(res, 200, fs.readFileSync(path.join(PUBLIC_DIR, file)), { 'Content-Type': type });
    }

    if (req.method === 'POST' && p === '/api/login') {
      const ip = req.socket.remoteAddress;
      const now = Date.now();
      let a = attempts.get(ip);
      if (!a || now - a.first > LOGIN_WINDOW) { a = { n: 0, first: now }; attempts.set(ip, a); }
      if (a.n >= LOGIN_MAX) {
        const wait = Math.ceil((LOGIN_WINDOW - (now - a.first)) / 60e3);
        return sendJson(res, 429, { ok: false, error: `Слишком много попыток входа. Повторите через ${wait} мин.` });
      }
      const b = await readJsonBody(req);
      const given = await scrypt(String(b.password || ''), SALT, 32);   // асинхронно: не блокирует сервер
      if (!crypto.timingSafeEqual(given, ADMIN_HASH)) {
        a.n++;
        await new Promise((r) => setTimeout(r, 700));
        return sendJson(res, 401, { ok: false, error: 'Неверный пароль.' });
      }
      attempts.delete(ip);
      const sid = crypto.randomBytes(32).toString('hex');
      sessions.set(sid, { csrf: crypto.randomBytes(24).toString('hex'), expires: now + SESSION_ABS, last: now });
      const cookie = `sid=${sid}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_ABS / 1000}${HTTPS_ON ? '; Secure' : ''}`;
      return sendJson(res, 200, { ok: true }, { 'Set-Cookie': cookie });
    }

    const sess = getSession(req);

    if (req.method === 'GET' && p === '/api/session') {
      if (!sess) return sendJson(res, 200, { authenticated: false });
      return sendJson(res, 200, {
        authenticated: true, csrf: sess.csrf, mailHost: MAIL_HOST,
        accounts: Object.entries(accounts).map(([address, v]) => ({ address, name: v.name })),
        usage: usage(),
      });
    }

    // ниже — только для вошедших
    if (!sess) return sendJson(res, 401, { ok: false, error: 'Требуется вход.' });

    if (req.method === 'GET' && p === '/api/log') {
      const items = history.slice(-30).reverse().map((e) => ({ t: e.t, from: e.from, to: e.to, subject: e.subject, status: e.status, error: e.error }));
      return sendJson(res, 200, { items });
    }

    if (req.method === 'POST' && p === '/preview') {
      const form = new URLSearchParams(await readBody(req));
      if (!safeEqual(form.get('csrf') || '', sess.csrf)) return send(res, 403, 'CSRF', { 'Content-Type': 'text/plain' });
      const l = lint({ subject: 'x', text: form.get('text') || '', html: form.get('html') || '' });
      const esc = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
      const content = l.html || `<pre style="white-space:pre-wrap;font:inherit">${esc(l.text)}</pre>`;
      const page = `<!doctype html><meta charset="utf-8"><style>body{margin:16px;background:#fff;color:#111;font:14px/1.55 system-ui,sans-serif}img{max-width:100%;height:auto}</style>${content}`;
      return send(res, 200, page, {
        'Content-Type': 'text/html; charset=utf-8',
        'Content-Security-Policy': "sandbox; default-src 'none'; style-src 'unsafe-inline'; img-src https: data:; font-src https: data:",
        'X-Frame-Options': 'SAMEORIGIN',
      });
    }

    if (req.method === 'POST') {
      if (!safeEqual(req.headers['x-csrf-token'] || '', sess.csrf)) return sendJson(res, 403, { ok: false, error: 'Сессия устарела. Обновите страницу.' });
      if (p === '/api/logout') { sessions.delete(sess.sid); return sendJson(res, 200, { ok: true }, { 'Set-Cookie': 'sid=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0' }); }
      if (p === '/api/lint') {
        const b = await readJsonBody(req);
        const l = lint({ subject: String(b.subject || ''), text: String(b.text || ''), html: String(b.html || '') });
        return sendJson(res, 200, { issues: l.issues });
      }
      if (p === '/api/send') return await handleSend(req, res);
    }

    return sendJson(res, 404, { ok: false, error: 'Not found' });
  } catch (err) {
    const status = err.status || 500;
    if (status === 500) console.error('Ошибка:', err);
    if (!res.headersSent) sendJson(res, status, { ok: false, error: status === 413 ? 'Слишком большой запрос.' : 'Внутренняя ошибка сервера.' });
  }
}

// ------------------------------------------------------------------ запуск
function createServer() {
  if (!HTTPS_ON) return http.createServer(handler);
  const certDir = process.env.CERT_DIR || `/etc/letsencrypt/live/${MAIL_HOST}`;
  const load = () => ({ key: fs.readFileSync(path.join(certDir, 'privkey.pem')), cert: fs.readFileSync(path.join(certDir, 'fullchain.pem')) });
  const server = https.createServer({ ...load(), minVersion: 'TLSv1.2' }, handler);
  // подхватываем обновлённый сертификат без перезапуска
  setInterval(() => { try { server.setSecureContext(load()); } catch (e) { console.error('Не удалось перечитать сертификат:', e.message); } }, 6 * 3600e3).unref();
  return server;
}

const server = createServer();
server.listen(PORT, process.env.HOST || '0.0.0.0', () => {
  console.log(`Почтовая консоль: ${HTTPS_ON ? 'https' : 'http'}://0.0.0.0:${PORT}  (ящики: ${Object.keys(accounts).join(', ')})`);
});
