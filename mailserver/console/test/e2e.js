'use strict';
// Сквозные тесты консоли: поднимает поддельный SMTP-сервер и саму консоль,
// проверяет защиту (вход, CSRF, отправитель, лимиты) и формат письма.
// Запуск: npm install && npm test

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { SMTPServer } = require('smtp-server');
const { simpleParser } = require('mailparser');

const ROOT = path.join(__dirname, '..');
let passed = 0, failed = 0;
async function t(name, fn) {
  try { await fn(); passed++; console.log('  ok   ', name); } catch (e) { failed++; console.log('  FAIL ', name, '\n       ', e.message); }
}

function startSmtp() {
  const received = [];
  const server = new SMTPServer({
    authOptional: false, allowInsecureAuth: false, disabledCommands: [],
    onAuth(auth, session, cb) { return auth.password === 'pw-info-123' || auth.password === 'pw-mail-456' ? cb(null, { user: auth.username }) : cb(new Error('Invalid credentials')); },
    onRcptTo(addr, session, cb) {
      if (addr.address === 'bad@example.test') { const e = new Error('550 5.1.1 User unknown'); e.responseCode = 550; return cb(e); }
      cb();
    },
    onData(stream, session, cb) {
      simpleParser(stream).then((m) => { m._user = session.user; received.push(m); cb(); }).catch(cb);
    },
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({ server, received, port: server.server.address().port })));
}

function startConsole(smtpPort, extra = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'console-test-'));
  const cfgPath = path.join(dir, 'config.json');
  fs.writeFileSync(cfgPath, JSON.stringify({
    mailHost: 'mail.dpsradar.world', smtpHost: '127.0.0.1', smtpPort,
    adminPassword: 'test-admin-password',
    accounts: { 'info@dpsradar.world': 'pw-info-123', 'mail@dpsradar.net': { pass: 'pw-mail-456', name: 'Дежурный' } },
    perHour: 100, dailyLimit: 100, ...extra,
  }));
  const port = 20000 + Math.floor(Math.random() * 20000);
  const child = spawn(process.execPath, ['server.js'], {
    cwd: ROOT,
    env: { ...process.env, DATA_DIR: dir, CONFIG_PATH: cfgPath, PORT: String(port), INSECURE_HTTP: '1', SKIP_MX_CHECK: '1', SMTP_TLS_INSECURE: '1', HOST: '127.0.0.1' },
  });
  return new Promise((resolve, reject) => {
    let out = '';
    child.stdout.on('data', (d) => { out += d; if (out.includes('Почтовая консоль')) resolve({ child, base: `http://127.0.0.1:${port}`, dir }); });
    child.stderr.on('data', (d) => { out += d; });
    child.on('exit', (c) => reject(new Error('консоль упала: ' + out)));
  });
}

function client(base) {
  let cookie = '', csrf = '';
  const call = async (method, p, body, headers = {}) => {
    const res = await fetch(base + p, {
      method, redirect: 'manual',
      headers: { ...(body !== undefined && typeof body !== 'string' ? { 'Content-Type': 'application/json' } : {}), ...(cookie ? { cookie } : {}), ...headers },
      body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
    });
    const sc = res.headers.get('set-cookie');
    if (sc) cookie = sc.split(';')[0];
    const text = await res.text();
    let json = null; try { json = JSON.parse(text); } catch { /* не JSON */ }
    return { status: res.status, headers: res.headers, text, json };
  };
  return {
    call,
    async login(pw = 'test-admin-password') {
      const r = await call('POST', '/api/login', { password: pw });
      if (r.status === 200) csrf = (await call('GET', '/api/session')).json.csrf;
      return r;
    },
    post: (p, body) => call('POST', p, body, { 'X-CSRF-Token': csrf }),
    get: (p) => call('GET', p),
    csrf: () => csrf,
  };
}

const goodMail = { from: 'info@dpsradar.world', to: ['anna@example.org'], subject: 'Привет, Анна', text: 'Добрый день! Это тестовое письмо.' };

(async () => {
  const smtp = await startSmtp();
  const app = await startConsole(smtp.port);
  const c = client(app.base);
  console.log('Консоль:', app.base, ' SMTP:', smtp.port);

  await t('страница и заголовки безопасности', async () => {
    const r = await c.get('/');
    assert.equal(r.status, 200);
    assert(/default-src 'none'/.test(r.headers.get('content-security-policy')));
    assert.equal(r.headers.get('x-frame-options'), 'DENY');
    assert.equal(r.headers.get('cache-control'), 'no-store');
  });

  await t('без входа API закрыт', async () => {
    assert.equal((await c.get('/api/log')).status, 401);
    assert.equal((await c.call('POST', '/api/send', goodMail)).status, 401);
    assert.equal((await c.get('/api/session')).json.authenticated, false);
  });

  await t('неверный пароль отклоняется, 6-я попытка блокируется', async () => {
    const c2 = client(app.base);
    for (let i = 0; i < 5; i++) assert.equal((await c2.login('wrong-password-' + i)).status, 401);
    assert.equal((await c2.login('wrong-again')).status, 429);
    assert.equal((await c2.login()).status, 429, 'даже верный пароль не пускает во время блокировки');
  });
  // блокировка по IP: перезапускаем консоль, чтобы остальные тесты шли с чистого листа
  app.child.kill();
  const app2 = await startConsole(smtp.port);
  const a = client(app2.base);

  await t('вход с верным паролем, cookie HttpOnly + SameSite=Strict', async () => {
    const r = await a.login();
    assert.equal(r.status, 200);
    const sc = r.headers.get('set-cookie');
    assert(/HttpOnly/i.test(sc) && /SameSite=Strict/i.test(sc), sc);
    const s = (await a.get('/api/session')).json;
    assert.equal(s.authenticated, true);
    assert.deepEqual(s.accounts.map((x) => x.address).sort(), ['info@dpsradar.world', 'mail@dpsradar.net']);
    assert(!JSON.stringify(s).includes('pw-info-123'), 'пароли ящиков не должны попадать в браузер');
  });

  await t('POST без CSRF-токена запрещён', async () => {
    const r = await a.call('POST', '/api/send', goodMail);
    assert.equal(r.status, 403);
    const r2 = await a.call('POST', '/api/send', goodMail, { 'X-CSRF-Token': 'forged-token' });
    assert.equal(r2.status, 403);
  });

  await t('нельзя отправлять с чужого адреса (подмена отправителя)', async () => {
    const r = await a.post('/api/send', { ...goodMail, from: 'ceo@gmail.com' });
    assert.equal(r.status, 400);
    assert(smtp.received.length === 0);
  });

  await t('валидация: нет получателя, плохой адрес, пустая тема, пустое тело', async () => {
    assert.equal((await a.post('/api/send', { ...goodMail, to: [] })).status, 422);
    assert.equal((await a.post('/api/send', { ...goodMail, to: ['не-адрес'] })).status, 422);
    assert.equal((await a.post('/api/send', { ...goodMail, subject: '  ' })).status, 422);
    assert.equal((await a.post('/api/send', { ...goodMail, text: '', html: '' })).status, 422);
    assert.equal((await a.post('/api/send', { ...goodMail, subject: 'Тема\r\nBcc: x@evil.test' })).status, 422, 'инъекция заголовков');
    assert(smtp.received.length === 0);
  });

  await t('больше 5 получателей запрещено (нет рассылок)', async () => {
    const to = Array.from({ length: 6 }, (_, i) => `u${i}@example.org`);
    const r = await a.post('/api/send', { ...goodMail, to });
    assert.equal(r.status, 422);
    assert(/максимум/i.test(r.json.error));
  });

  await t('успешная отправка простым текстом', async () => {
    const r = await a.post('/api/send', goodMail);
    assert.equal(r.status, 200, r.text);
    const m = smtp.received.at(-1);
    assert.equal(m.from.value[0].address, 'info@dpsradar.world');
    assert.equal(m.to.value[0].address, 'anna@example.org');
    assert.equal(m.subject, 'Привет, Анна');
    assert(m.text.includes('Добрый день'));
    assert(/@dpsradar\.world>$/.test(m.messageId), 'Message-ID должен быть с вашего домена: ' + m.messageId);
    assert(!m.headers.get('x-mailer'), 'не выдаём X-Mailer');
    assert(m.headers.get('date'));
  });

  await t('HTML: письмо multipart/alternative, текст создан автоматически, скрипты вырезаны', async () => {
    const html = '<h1>Здравствуйте</h1><p>Ссылка: <a href="https://example.org/doc">документ</a></p><script>alert(1)</script><img src="x" onerror="alert(2)">';
    const r = await a.post('/api/send', { ...goodMail, from: 'mail@dpsradar.net', fromName: 'Анна "Тест"', text: '', html });
    assert.equal(r.status, 200, r.text);
    const m = smtp.received.at(-1);
    assert.equal(m._user, 'mail@dpsradar.net', 'вход в SMTP именно под ящиком отправителя');
    assert.equal(m.headers.get('content-type').value, 'multipart/alternative');
    assert(m.text.includes('документ (https://example.org/doc)'), m.text);
    assert(m.html.includes('<h1>'), 'HTML сохранён');
    assert(!/<script|onerror/i.test(m.html), 'скрипты и обработчики удалены: ' + m.html);
    assert(/@dpsradar\.net>$/.test(m.messageId));
    assert.equal(m.from.value[0].name, 'Анна Тест');
  });

  await t('копия и скрытая копия', async () => {
    const r = await a.post('/api/send', { ...goodMail, cc: ['cc@example.org'], bcc: ['hidden@example.org'], replyTo: 'reply@dpsradar.world' });
    assert.equal(r.status, 200, r.text);
    const m = smtp.received.at(-1);
    assert.equal(m.cc.value[0].address, 'cc@example.org');
    assert(!JSON.stringify(m.headers.get('bcc') || '').includes('hidden'), 'Bcc не должен попасть в заголовки');
    assert.equal(m.replyTo.value[0].address, 'reply@dpsradar.world');
  });

  await t('проверка текста: ловит спамные приёмы', async () => {
    const r = await a.post('/api/lint', { subject: 'БЕСПЛАТНО!!! ВЫИГРЫШ ТОЛЬКО СЕГОДНЯ', text: 'Жми https://bit.ly/abc и https://tinyurl.com/x и http://a.b/1 https://c.d/2', html: '' });
    const txt = r.json.issues.map((i) => i.text).join('\n');
    assert(/ЗАГЛАВНЫМИ/.test(txt), txt);
    assert(/спамные/i.test(txt), txt);
    assert(/Сокращатели/.test(txt), txt);
    assert(/http:\/\//.test(txt), txt);
    assert(/ссылок/.test(txt), txt);
  });

  await t('фишинговая ссылка (текст и адрес не совпадают) помечается', async () => {
    const r = await a.post('/api/lint', { subject: 'Счёт', text: '', html: '<p><a href="https://evil.example/x">https://mybank.com</a></p>' });
    assert(r.json.issues.some((i) => /фишинг/.test(i.text)), JSON.stringify(r.json));
  });

  await t('отклонённый сервером адрес запоминается и повторно не используется', async () => {
    const r1 = await a.post('/api/send', { ...goodMail, to: ['bad@example.test'] });
    assert.notEqual(r1.status, 200);
    const r2 = await a.post('/api/send', { ...goodMail, to: ['bad@example.test'] });
    assert.equal(r2.status, 422, r2.text);
    assert(/ранее был отклонён/.test(r2.json.error));
    const sup = JSON.parse(fs.readFileSync(path.join(app2.dir, 'suppressed.json'), 'utf8'));
    assert(sup['bad@example.test']);
  });

  await t('журнал и лимиты считаются', async () => {
    const log = (await a.get('/api/log')).json.items;
    assert(log.length >= 3 && log[0].status);
    const s = (await a.get('/api/session')).json.usage;
    assert(s.hour.used >= 3 && s.day.limit === 100 && s.maxRecipients === 5);
    assert(fs.statSync(path.join(app2.dir, 'sent.jsonl')).mode & 0o600);
  });

  await t('предпросмотр: нужен CSRF, ответ изолирован (sandbox) и без скриптов', async () => {
    const body = (csrf) => new URLSearchParams({ csrf, html: '<b>жирный</b><script>alert(1)</script>', text: '' }).toString();
    const ct = { 'Content-Type': 'application/x-www-form-urlencoded' };
    assert.equal((await a.call('POST', '/preview', body('чужой'), ct)).status, 403);
    const ok = await a.call('POST', '/preview', body(a.csrf()), ct);
    assert.equal(ok.status, 200);
    assert(/^sandbox/.test(ok.headers.get('content-security-policy')), ok.headers.get('content-security-policy'));
    assert(ok.text.includes('<b>жирный</b>') && !ok.text.includes('<script'));
  });

  await t('выход закрывает сессию', async () => {
    const b = client(app2.base);
    await b.login();
    assert.equal((await b.post('/api/logout', {})).status, 200);
    assert.equal((await b.get('/api/log')).status, 401);
  });

  // ---------------- лимиты (отдельный экземпляр с жёсткими лимитами)
  const app3 = await startConsole(smtp.port, { perHour: 2, dailyLimit: 3 });
  const l = client(app3.base);
  await l.login();
  await t('часовой лимит: третье письмо блокируется', async () => {
    assert.equal((await l.post('/api/send', goodMail)).status, 200);
    assert.equal((await l.post('/api/send', goodMail)).status, 200);
    const r = await l.post('/api/send', goodMail);
    assert.equal(r.status, 429, r.text);
    assert(/час/.test(r.json.error));
  });

  // ---------------- параллельные запросы не обходят лимит
  const app5 = await startConsole(smtp.port, { perHour: 2, dailyLimit: 50 });
  const par = client(app5.base);
  await par.login();
  await t('5 одновременных отправок при лимите 2 в час: уходит не больше 2', async () => {
    const before = smtp.received.length;
    const results = await Promise.all(Array.from({ length: 5 }, () => par.post('/api/send', goodMail)));
    const ok = results.filter((r) => r.status === 200).length;
    assert(ok >= 1 && ok <= 2, 'успешных: ' + ok + ' (' + results.map((r) => r.status).join(',') + ')');
    assert(smtp.received.length - before <= 2, 'реально доставлено: ' + (smtp.received.length - before));
  });

  // ---------------- ограничение по IP
  const app4 = await startConsole(smtp.port, { allowedIps: ['203.0.113.9'] });
  await t('список разрешённых IP: чужой адрес получает 403', async () => {
    assert.equal((await client(app4.base).get('/')).status, 403);
  });

  for (const x of [app2, app3, app4, app5]) x.child.kill();
  smtp.server.close();
  console.log(`\nИтого: ${passed} успешно, ${failed} с ошибкой`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
