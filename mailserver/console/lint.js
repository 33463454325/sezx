'use strict';
// Проверки письма перед отправкой, очистка HTML и создание текстовой версии.
// Цель — чтобы письмо не выглядело как спам и не вредило репутации сервера.

const SHORTENERS = ['bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'cutt.ly', 'is.gd', 'ow.ly', 'rebrand.ly', 'shorturl.at'];

const SPAM_PATTERNS = [
  /бесплатн/i, /выигр[аы]ш/i, /без\s+отказа/i, /100\s*%\s*гарант/i, /только\s+сегодня/i,
  /казино/i, /микрозайм/i, /быстрый\s+заработок/i,
  /\bviagra\b/i, /\bcasino\b/i, /\bfree\s+money\b/i, /\bclick\s+here\b/i, /\bact\s+now\b/i,
  /\bwinner\b/i, /\bno\s+obligation\b/i, /\bearn\s+\$/i,
];

const ENTITIES = { nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", laquo: '«', raquo: '»', mdash: '—', ndash: '–', hellip: '…', copy: '©' };

function decodeEntities(s) {
  return s
    .replace(/&#(\d+);/g, (_, n) => { try { return String.fromCodePoint(Number(n)); } catch { return ''; } })
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => { try { return String.fromCodePoint(parseInt(n, 16)); } catch { return ''; } })
    .replace(/&([a-z]+);/gi, (m, n) => (ENTITIES[n.toLowerCase()] !== undefined ? ENTITIES[n.toLowerCase()] : m));
}

// Убирает опасные и «спамные» для почты элементы. HTML пишет сам пользователь,
// поэтому это гигиена, а не защита от злоумышленника.
function sanitizeHtml(html) {
  let s = String(html || '');
  s = s.replace(/<(script|iframe|object|embed|applet|form)\b[\s\S]*?<\/\1\s*>/gi, '');
  s = s.replace(/<\/?(script|iframe|object|embed|applet|form|input|button|textarea|select|link)\b[^>]*>/gi, '');
  s = s.replace(/<meta\s+http-equiv[^>]*>/gi, '');
  s = s.replace(/\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/gi, '');
  s = s.replace(/(href|src)\s*=\s*(["'])\s*javascript:[^"']*\2/gi, '$1=$2#$2');
  return s;
}

function htmlToText(html) {
  let s = String(html || '');
  s = s.replace(/<(script|style|head|title)\b[\s\S]*?<\/\1\s*>/gi, '');
  s = s.replace(/<a\s[^>]*?href\s*=\s*["']?([^"'\s>]+)["']?[^>]*>([\s\S]*?)<\/a\s*>/gi, (m, href, inner) => {
    const label = inner.replace(/<[^>]+>/g, '').trim();
    if (!label || label === href || /^mailto:/i.test(href) || href.startsWith('#')) return label || href;
    return `${label} (${href})`;
  });
  s = s.replace(/<br\s*\/?>/gi, '\n');
  s = s.replace(/<li\b[^>]*>/gi, '• ');
  s = s.replace(/<\/(p|div|h[1-6]|li|tr|table|ul|ol|blockquote|section|article)\s*>/gi, '\n\n');
  s = s.replace(/<[^>]+>/g, '');
  s = decodeEntities(s);
  return s.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}

function extractUrls(text, html) {
  const urls = new Set();
  const re = /https?:\/\/[^\s<>"')\]]+/gi;
  for (const src of [text || '', html || '']) for (const m of src.matchAll(re)) urls.add(m[0].replace(/[.,;:!?]+$/, ''));
  return [...urls];
}

function hostOf(u) {
  try { return new URL(u).hostname.toLowerCase().replace(/^www\./, ''); } catch { return ''; }
}

/**
 * Возвращает { issues: [{level, text}], text, html }
 * level: 'error' — отправка запрещена, 'warn' — предупреждение, 'info' — заметка.
 */
function lint({ subject = '', text = '', html = '' } = {}) {
  const issues = [];
  const add = (level, t) => issues.push({ level, text: t });

  subject = String(subject);
  const cleanHtml = html ? sanitizeHtml(html) : '';
  const hasText = String(text).trim().length > 0;
  const hasHtml = cleanHtml.trim().length > 0;

  // --- обязательное
  if (!subject.trim()) add('error', 'Укажите тему письма. Письма без темы чаще попадают в спам.');
  if (/[\r\n]/.test(subject)) add('error', 'В теме не должно быть переводов строк.');
  if (!hasText && !hasHtml) add('error', 'Письмо пустое: введите текст или HTML.');
  if (html && cleanHtml !== html) add('info', 'Из HTML удалены скрипты, формы и другие небезопасные элементы: почтовые клиенты их не поддерживают, а спам-фильтры не любят.');

  // --- текстовая версия
  let finalText = String(text);
  if (!hasText && hasHtml) {
    finalText = htmlToText(cleanHtml);
    add('info', 'Текстовая версия создана автоматически из HTML. Письмо уйдёт сразу в двух форматах, это улучшает доставляемость.');
  } else if (hasText && !hasHtml) {
    add('info', 'Письмо уйдёт простым текстом. Это нормально и даже надёжнее для личной переписки.');
  }

  // --- тема
  if (subject.length > 78) add('warn', `Тема длинная (${subject.length} символов). Лучше уложиться в 60–70.`);
  const letters = subject.replace(/[^A-Za-zА-Яа-яЁё]/g, '');
  const upper = letters.replace(/[^A-ZА-ЯЁ]/g, '');
  if (letters.length >= 8 && upper.length / letters.length > 0.6) add('warn', 'Тема написана ЗАГЛАВНЫМИ буквами: фильтры считают это признаком спама.');
  if (/!{2,}|\${2,}|\?{3,}/.test(subject)) add('warn', 'В теме много «!», «?» или «$». Уберите лишние знаки.');
  if (/^\s*(re|fwd?|отв|пересл)\s*:/i.test(subject)) add('warn', 'Тема начинается с «Re:»/«Fwd:», но это не ответ на письмо. Так делать нельзя: это приём спамеров.');

  // --- слова-триггеры
  const body = `${subject}\n${finalText}\n${hasHtml ? htmlToText(cleanHtml) : ''}`;
  const hits = SPAM_PATTERNS.filter((re) => re.test(body));
  if (hits.length) add('warn', `Найдены «спамные» формулировки (${hits.length}). Перепишите нейтральнее.`);

  // --- ссылки
  const urls = extractUrls(finalText, cleanHtml);
  const hosts = [...new Set(urls.map(hostOf).filter(Boolean))];
  if (urls.length > 3) add('warn', `В письме ${urls.length} ссылок. Для первых писем держитесь в пределах 1–3.`);
  const short = hosts.filter((h) => SHORTENERS.includes(h));
  if (short.length) add('warn', `Сокращатели ссылок (${short.join(', ')}) сильно повышают риск спама. Используйте полные адреса.`);
  if (urls.some((u) => u.startsWith('http://'))) add('warn', 'Есть ссылки на http://. Лучше использовать https://.');
  for (const m of cleanHtml.matchAll(/<a\s[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a\s*>/gi)) {
    const label = m[2].replace(/<[^>]+>/g, '').trim();
    if (/^https?:\/\//i.test(label) && hostOf(label) && hostOf(m[1]) && hostOf(label) !== hostOf(m[1])) {
      add('warn', `Текст ссылки показывает «${hostOf(label)}», а ведёт она на «${hostOf(m[1])}». Это выглядит как фишинг.`);
      break;
    }
  }

  // --- содержимое HTML
  if (hasHtml) {
    const imgs = (cleanHtml.match(/<img\b/gi) || []).length;
    const visible = htmlToText(cleanHtml).length;
    if (imgs > 0 && visible < 200) add('warn', 'Много картинок и мало текста: такие письма часто считаются спамом. Добавьте текст.');
    if (imgs > 5) add('warn', `В письме ${imgs} картинок. Старайтесь не больше 3–5.`);
    if (/<img\b(?![^>]*\balt\s*=)[^>]*>/i.test(cleanHtml)) add('info', 'У некоторых картинок нет атрибута alt: добавьте описание.');
    if (cleanHtml.length > 100 * 1024) add('warn', 'HTML очень большой (больше 100 КБ). Gmail обрежет такое письмо.');
  }
  if (urls.length >= 1 && finalText.replace(/https?:\/\/\S+/g, '').trim().length < 40 && !hasHtml) {
    add('warn', 'Письмо почти целиком состоит из ссылки. Добавьте пару предложений текста.');
  }

  return { issues, text: finalText, html: cleanHtml };
}

module.exports = { lint, sanitizeHtml, htmlToText };
