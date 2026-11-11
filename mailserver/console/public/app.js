(() => {
  'use strict';

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const EMAIL = /^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$/;

  const state = { csrf: '', accounts: [], usage: null, issues: [], maxRecipients: 5 };
  const chips = { to: [], cc: [], bcc: [] };
  let lintTimer = 0;
  let lintSeq = 0;

  // ---------------------------------------------------------------- утилиты
  function el(tag, props = {}, ...kids) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (k === 'class') n.className = v;
      else if (k === 'text') n.textContent = v;
      else n.setAttribute(k, v);
    }
    for (const kid of kids) if (kid) n.append(kid);
    return n;
  }

  async function api(path, body) {
    const opts = { method: body === undefined ? 'GET' : 'POST', headers: {}, credentials: 'same-origin' };
    if (body !== undefined) {
      opts.headers['Content-Type'] = 'application/json';
      opts.headers['X-CSRF-Token'] = state.csrf;
      opts.body = JSON.stringify(body);
    }
    let res;
    try { res = await fetch(path, opts); } catch { throw Object.assign(new Error('Нет связи с сервером.'), { network: true }); }
    let data = {};
    try { data = await res.json(); } catch { /* пустой ответ */ }
    if (res.status === 401 && path !== '/api/login') { showLogin(); throw Object.assign(new Error('Требуется вход.'), { handled: true }); }
    if (!res.ok) throw Object.assign(new Error(data.error || `Ошибка ${res.status}`), { data, status: res.status });
    return data;
  }

  let toastTimer = 0;
  function toast(text, isErr) {
    const t = $('#toast');
    t.textContent = text;
    t.className = 'toast' + (isErr ? ' err' : '');
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.hidden = true; }, isErr ? 6000 : 3200);
  }

  // ---------------------------------------------------------------- тема
  function applyTheme(t) {
    if (t) document.documentElement.setAttribute('data-theme', t);
  }
  try { applyTheme(localStorage.getItem('theme')); } catch { /* хранилище недоступно */ }
  $('#themeBtn').addEventListener('click', () => {
    const cur = document.documentElement.getAttribute('data-theme')
      || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    const next = cur === 'dark' ? 'light' : 'dark';
    applyTheme(next);
    try { localStorage.setItem('theme', next); } catch { /* ignore */ }
  });

  // ---------------------------------------------------------------- вход / выход
  function showLogin() {
    $('#app').hidden = true;
    $('#login').hidden = false;
    $('#loginPass').value = '';
    $('#loginPass').focus();
  }
  function showApp() {
    $('#login').hidden = true;
    $('#app').hidden = false;
  }

  $('#loginForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const err = $('#loginError');
    err.hidden = true;
    const btn = $('#loginForm button[type=submit]');
    btn.disabled = true;
    try {
      await api('/api/login', { password: $('#loginPass').value });
      await boot();
    } catch (ex) {
      err.textContent = ex.message;
      err.hidden = false;
      $('#loginPass').select();
    } finally { btn.disabled = false; }
  });

  $('#logoutBtn').addEventListener('click', async () => {
    try { await api('/api/logout', {}); } catch { /* всё равно выходим */ }
    showLogin();
  });

  // ---------------------------------------------------------------- получатели (чипсы)
  function initChips(box) {
    const key = box.dataset.field;
    const input = $('input', box);

    function render() {
      $$('.chip', box).forEach((c) => c.remove());
      chips[key].forEach((addr, i) => {
        const rm = el('button', { type: 'button', 'aria-label': `Убрать ${addr}`, text: '×' });
        rm.addEventListener('click', () => { chips[key].splice(i, 1); render(); scheduleCheck(); });
        box.insertBefore(el('span', { class: 'chip' }, el('span', { text: addr }), rm), input);
      });
    }

    function commit() {
      const parts = input.value.split(/[\s,;]+/).filter(Boolean);
      let bad = false;
      for (const p of parts) {
        const a = p.toLowerCase();
        if (!EMAIL.test(a)) { bad = true; continue; }
        if (!chips[key].includes(a)) chips[key].push(a);
      }
      input.value = bad ? parts.filter((p) => !EMAIL.test(p.toLowerCase())).join(' ') : '';
      input.classList.toggle('bad', bad);
      render();
      scheduleCheck();
      return !bad;
    }

    input.addEventListener('keydown', (e) => {
      if (['Enter', ',', ';', ' ', 'Tab'].includes(e.key) && input.value.trim()) {
        if (e.key !== 'Tab') e.preventDefault();
        commit();
      } else if (e.key === 'Backspace' && !input.value && chips[key].length) {
        chips[key].pop(); render(); scheduleCheck();
      }
    });
    input.addEventListener('blur', () => { if (input.value.trim()) commit(); });
    input.addEventListener('paste', () => setTimeout(commit, 0));
    input.addEventListener('input', () => input.classList.remove('bad'));
    box.addEventListener('click', (e) => { if (e.target === box) input.focus(); });
    box.commit = commit;
    box.render = render;
  }
  $$('.chips').forEach(initChips);

  $('#moreBtn').addEventListener('click', () => {
    const open = $$('.row.opt')[0].hidden;
    $$('.row.opt').forEach((r) => { r.hidden = !open; });
    $('#moreBtn').setAttribute('aria-expanded', String(open));
    $('#moreBtn').textContent = open ? 'Скрыть' : 'Копия';
  });

  // ---------------------------------------------------------------- отправитель
  function fromStatus() {
    const v = $('#from').value.trim().toLowerCase();
    const badge = $('#fromState');
    if (!v) { badge.hidden = true; return null; }
    const known = state.accounts.some((a) => a.address === v);
    badge.hidden = false;
    badge.className = 'badge ' + (known ? 'ok' : 'err');
    badge.textContent = known ? 'Ящик подключён' : 'Нет такого ящика на сервере';
    return known;
  }
  $('#from').addEventListener('input', () => {
    fromStatus();
    const acc = state.accounts.find((a) => a.address === $('#from').value.trim().toLowerCase());
    if (acc && acc.name && !$('#fromName').value) $('#fromName').value = acc.name;
    scheduleCheck();
  });

  // ---------------------------------------------------------------- вкладки
  const HINTS = {
    text: 'Простой текст. Так лучше всего читаются личные письма.',
    html: 'Если оставить «Текст» пустым, текстовая версия создастся из HTML автоматически.',
    preview: 'Так письмо увидит получатель (скрипты и формы удалены).',
  };
  let currentTab = 'text';
  function setTab(tab) {
    currentTab = tab;
    $$('.tabs button').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.tab === tab)));
    $('#text').hidden = tab !== 'text';
    $('#html').hidden = tab !== 'html';
    $('#previewPane').hidden = tab !== 'preview';
    $('#tabHint').textContent = HINTS[tab];
    if (tab === 'preview') {
      $('#pvCsrf').value = state.csrf;
      $('#pvText').value = $('#text').value;
      $('#pvHtml').value = $('#html').value;
      $('#previewForm').submit();
    }
  }
  $$('.tabs button').forEach((b) => b.addEventListener('click', () => setTab(b.dataset.tab)));

  // ---------------------------------------------------------------- проверка письма
  function allRecipients() {
    return [...new Set([...chips.to, ...chips.cc, ...chips.bcc])];
  }

  function clientChecks() {
    const out = [];
    const known = fromStatus();
    if (known === false) out.push({ level: 'error', text: 'Отправитель не совпадает ни с одним ящиком сервера. Письмо не будет отправлено.' });
    const n = allRecipients().length;
    if (n > state.maxRecipients) out.push({ level: 'error', text: `Получателей ${n}, а можно не больше ${state.maxRecipients}. Это консоль для личных писем, не для рассылок.` });
    return out;
  }

  function renderChecks() {
    const list = $('#checks');
    list.replaceChildren();
    const items = [...clientChecks(), ...state.issues];
    if (!items.length) items.push({ level: 'ok', text: 'Замечаний нет. Письмо выглядит нормально.' });
    for (const it of items) list.append(el('li', { class: it.level, text: it.text }));
  }

  function scheduleCheck() {
    renderChecks();
    clearTimeout(lintTimer);
    lintTimer = setTimeout(runLint, 500);
  }

  async function runLint() {
    const seq = ++lintSeq;
    const subject = $('#subject').value, text = $('#text').value, html = $('#html').value;
    if (!subject && !text && !html) { state.issues = []; renderChecks(); return; }
    try {
      const r = await api('/api/lint', { subject, text, html });
      if (seq !== lintSeq) return;
      // пока письмо не заполнено, ошибки «пусто» не показываем
      const incomplete = !subject.trim() || (!text.trim() && !html.trim());
      state.issues = r.issues.filter((i) => !(incomplete && i.level === 'error'));
      renderChecks();
    } catch { /* проверка необязательна */ }
  }

  $('#subject').addEventListener('input', () => { $('#subjCount').textContent = String($('#subject').value.length); scheduleCheck(); });
  $('#text').addEventListener('input', scheduleCheck);
  $('#html').addEventListener('input', scheduleCheck);
  $('#fromName').addEventListener('input', scheduleCheck);

  // ---------------------------------------------------------------- лимиты и журнал
  function renderUsage() {
    const u = state.usage;
    if (!u) return;
    const box = $('#meters');
    box.replaceChildren();
    for (const [label, m] of [['За последний час', u.hour], ['За сутки', u.day]]) {
      const pct = Math.min(100, Math.round((m.used / m.limit) * 100));
      const meter = el('div', { class: 'meter' + (pct >= 100 ? ' full' : pct >= 80 ? ' hot' : '') },
        el('div', { class: 'meter-top' }, el('span', { text: label }), el('b', { text: `${m.used} / ${m.limit}` })),
        el('div', { class: 'bar' }, el('i')));
      $('i', meter).style.setProperty('--w', pct + '%');
      box.append(meter);
    }
    $('#warmNote').textContent = u.warmupDay <= 14
      ? `Идёт «прогрев» нового сервера, день ${u.warmupDay}. Лимит растёт сам: так Gmail и другие почтовики привыкают к вашему адресу.`
      : 'Лимиты считаются по числу получателей.';
    state.maxRecipients = u.maxRecipients || 5;
  }

  async function loadLog() {
    try {
      const { items } = await api('/api/log');
      const ul = $('#logList');
      ul.replaceChildren();
      if (!items.length) { ul.append(el('li', { class: 'empty', text: 'Пока ничего не отправлено.' })); return; }
      for (const it of items.slice(0, 8)) {
        const who = it.to[0] + (it.to.length > 1 ? ` и ещё ${it.to.length - 1}` : '');
        const when = new Date(it.t).toLocaleString('ru-RU', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
        const li = el('li', { title: it.error || '' },
          el('span', { class: 'dot ' + (it.status === 'sent' ? '' : 'failed') }),
          el('div', { class: 'main' }, el('b', { text: it.subject || '(без темы)' }), el('small', { text: `${it.from} → ${who}` })),
          el('time', { text: when }));
        ul.append(li);
      }
    } catch { /* ignore */ }
  }

  // ---------------------------------------------------------------- отправка
  function showFormError(msg) {
    const b = $('#formError');
    b.textContent = msg || '';
    b.hidden = !msg;
    if (msg) b.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }

  function payload() {
    return {
      from: $('#from').value.trim().toLowerCase(),
      fromName: $('#fromName').value.trim(),
      to: chips.to, cc: chips.cc, bcc: chips.bcc,
      replyTo: $('#replyTo').value.trim(),
      subject: $('#subject').value.trim(),
      text: $('#text').value,
      html: $('#html').value,
    };
  }

  function validateLocal(p) {
    if (!p.from) return 'Укажите, с какого ящика отправлять.';
    if (!state.accounts.some((a) => a.address === p.from)) return 'Такого ящика нет на сервере. Отправлять можно только с созданных ящиков.';
    if (!p.to.length) return 'Добавьте хотя бы одного получателя в поле «Кому».';
    if (allRecipients().length > state.maxRecipients) return `Слишком много получателей (максимум ${state.maxRecipients}).`;
    if (!p.subject) return 'Укажите тему письма.';
    if (!p.text.trim() && !p.html.trim()) return 'Письмо пустое: напишите текст или вставьте HTML.';
    return '';
  }

  $('#composeForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    showFormError('');
    $$('.chips').forEach((c) => c.commit && c.commit());
    const p = payload();
    const problem = validateLocal(p);
    if (problem) { showFormError(problem); return; }

    // свежая серверная проверка для окна подтверждения
    let issues = [];
    try { issues = (await api('/api/lint', { subject: p.subject, text: p.text, html: p.html })).issues; } catch (ex) { if (ex.handled) return; }
    const blocking = issues.find((i) => i.level === 'error');
    if (blocking) { showFormError(blocking.text); return; }

    const info = $('#confirmInfo');
    info.replaceChildren();
    const row = (k, v) => info.append(el('div', {}, el('dt', { text: k }), el('dd', { text: v })));
    row('От', p.fromName ? `${p.fromName} <${p.from}>` : p.from);
    row('Кому', p.to.join(', '));
    if (p.cc.length) row('Копия', p.cc.join(', '));
    if (p.bcc.length) row('Скрытая', p.bcc.join(', '));
    row('Тема', p.subject);
    row('Формат', p.html.trim() ? (p.text.trim() ? 'текст + HTML' : 'HTML + автотекст') : 'простой текст');
    const w = $('#confirmWarn');
    w.replaceChildren();
    issues.filter((i) => i.level === 'warn').forEach((i) => w.append(el('li', { class: 'warn', text: i.text })));

    const dlg = $('#confirm');
    $('#confirmForm').onsubmit = null;
    dlg.returnValue = '';
    dlg.showModal();
    dlg.onclose = () => { if (dlg.returnValue === 'ok') doSend(p); };
  });

  async function doSend(p) {
    const btn = $('#sendBtn');
    const label = $('span', btn);
    btn.disabled = true;
    label.textContent = 'Отправляю…';
    try {
      const r = await api('/api/send', p);
      state.usage = r.usage;
      renderUsage();
      toast('Письмо отправлено');
      chips.to = []; chips.cc = []; chips.bcc = [];
      $$('.chips').forEach((c) => c.render());
      $('#subject').value = ''; $('#subjCount').textContent = '0';
      $('#text').value = ''; $('#html').value = '';
      state.issues = [];
      renderChecks();
      if (currentTab === 'preview') setTab('text');
      loadLog();
    } catch (ex) {
      if (ex.handled) return;
      showFormError(ex.message);
      toast('Письмо не отправлено', true);
      loadLog();
    } finally {
      btn.disabled = false;
      label.textContent = 'Проверить и отправить';
    }
  }

  document.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter' && !$('#app').hidden && !$('#confirm').open) {
      e.preventDefault();
      $('#composeForm').requestSubmit();
    }
  });

  // ---------------------------------------------------------------- запуск
  async function boot() {
    let s;
    try { s = await api('/api/session'); } catch (ex) { showLogin(); return; }
    if (!s.authenticated) { showLogin(); return; }
    state.csrf = s.csrf;
    state.accounts = s.accounts;
    state.usage = s.usage;
    $('#hostPill').textContent = s.mailHost;
    const dl = $('#accountList');
    dl.replaceChildren(...s.accounts.map((a) => el('option', { value: a.address })));
    if (!$('#from').value && s.accounts.length) {
      $('#from').value = s.accounts[0].address;
      if (s.accounts[0].name) $('#fromName').value = s.accounts[0].name;
    }
    $('#tabHint').textContent = HINTS[currentTab];
    showApp();
    fromStatus();
    renderUsage();
    renderChecks();
    loadLog();
  }
  boot();
})();
