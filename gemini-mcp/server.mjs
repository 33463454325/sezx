#!/usr/bin/env node
// MCP-сервер (stdio) для Google Gemini без внешних зависимостей.
// Даёт Claude Code инструменты: ask_gemini, gemini_review_files, gemini_list_models.
//
// Ключ: переменная GEMINI_API_KEY. В облачной сессии Claude Code ключ можно
// сохранить как секрет окружения для generativelanguage.googleapis.com —
// тогда прокси сам подставит заголовок x-goog-api-key, и переменная не нужна.

import { readFile } from "node:fs/promises";
import path from "node:path";
import { createInterface } from "node:readline";

const API_BASE = process.env.GEMINI_API_BASE || "https://generativelanguage.googleapis.com/v1beta";
const DEFAULT_MODEL = process.env.GEMINI_MODEL || "gemini-flash-latest";
const MAX_FILE_BYTES = 2_000_000;

// ---------- Gemini API ----------

function headers() {
  // Если ключа нет, отправляем заглушку: прокси облачного окружения заменит её на сохранённый секрет.
  return {
    "content-type": "application/json",
    "x-goog-api-key": process.env.GEMINI_API_KEY || "proxy-injected",
  };
}

async function geminiRequest(url, init = {}) {
  const res = await fetch(url, { ...init, headers: headers() });
  const text = await res.text();
  if (!res.ok) {
    let hint = "";
    if (res.status === 401 || res.status === 403 || text.includes("API_KEY_INVALID")) {
      hint =
        "\nПохоже, нет доступа к Gemini API: задайте GEMINI_API_KEY или сохраните ключ " +
        "как секрет окружения для generativelanguage.googleapis.com.";
    }
    throw new Error(`Gemini API ${res.status}: ${text.slice(0, 1000)}${hint}`);
  }
  return JSON.parse(text);
}

export async function generate({ prompt, model, system, temperature }) {
  const m = (model || DEFAULT_MODEL).replace(/^models\//, "");
  const body = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
  };
  if (system) body.systemInstruction = { parts: [{ text: system }] };
  if (typeof temperature === "number") body.generationConfig = { temperature };

  const data = await geminiRequest(`${API_BASE}/models/${encodeURIComponent(m)}:generateContent`, {
    method: "POST",
    body: JSON.stringify(body),
  });

  const cand = data.candidates?.[0];
  const out = (cand?.content?.parts || []).map((p) => p.text || "").join("");
  if (!out) {
    const reason = cand?.finishReason || data.promptFeedback?.blockReason || "unknown";
    throw new Error(`Gemini вернул пустой ответ (причина: ${reason})`);
  }
  return out;
}

async function listModels() {
  const data = await geminiRequest(`${API_BASE}/models?pageSize=200`);
  return (data.models || [])
    .filter((m) => (m.supportedGenerationMethods || []).includes("generateContent"))
    .map((m) => `${m.name.replace(/^models\//, "")} — ${m.displayName || ""}`)
    .join("\n");
}

async function readFilesForPrompt(paths) {
  const root = process.cwd();
  const chunks = [];
  for (const p of paths) {
    const abs = path.resolve(root, p);
    const buf = await readFile(abs);
    if (buf.length > MAX_FILE_BYTES) throw new Error(`Файл слишком большой: ${p}`);
    chunks.push(`===== ${path.relative(root, abs) || p} =====\n${buf.toString("utf8")}`);
  }
  return chunks.join("\n\n");
}

// ---------- Описание инструментов ----------

const TOOLS = [
  {
    name: "ask_gemini",
    description:
      "Задать вопрос модели Google Gemini и получить её ответ. Полезно для второго мнения, " +
      "мозгового штурма, проверки решения или задач с очень большим контекстом.",
    inputSchema: {
      type: "object",
      properties: {
        prompt: { type: "string", description: "Текст запроса для Gemini" },
        model: { type: "string", description: `Модель (по умолчанию ${DEFAULT_MODEL})` },
        system: { type: "string", description: "Необязательная системная инструкция" },
        temperature: { type: "number", description: "Температура 0–2" },
      },
      required: ["prompt"],
    },
  },
  {
    name: "gemini_review_files",
    description:
      "Отправить содержимое файлов проекта в Gemini вместе с вопросом (ревью кода, анализ, поиск ошибок). " +
      "Пути — относительно корня проекта.",
    inputSchema: {
      type: "object",
      properties: {
        paths: { type: "array", items: { type: "string" }, description: "Список файлов" },
        question: { type: "string", description: "Что нужно сделать с файлами" },
        model: { type: "string", description: `Модель (по умолчанию ${DEFAULT_MODEL})` },
      },
      required: ["paths", "question"],
    },
  },
  {
    name: "gemini_list_models",
    description: "Показать модели Gemini, доступные по текущему ключу.",
    inputSchema: { type: "object", properties: {} },
  },
];

async function callTool(name, args = {}) {
  switch (name) {
    case "ask_gemini":
      return generate(args);
    case "gemini_review_files": {
      const files = await readFilesForPrompt(args.paths || []);
      return generate({ prompt: `${args.question}\n\n${files}`, model: args.model });
    }
    case "gemini_list_models":
      return listModels();
    default:
      throw new Error(`Неизвестный инструмент: ${name}`);
  }
}

// ---------- MCP JSON-RPC по stdio ----------

const SERVER_INFO = { name: "gemini", version: "1.0.0" };

function send(msg) {
  process.stdout.write(JSON.stringify(msg) + "\n");
}

async function handle(msg) {
  const { id, method, params } = msg;
  const isRequest = id !== undefined && id !== null;
  try {
    let result;
    switch (method) {
      case "initialize":
        result = {
          protocolVersion: params?.protocolVersion || "2025-06-18",
          capabilities: { tools: {} },
          serverInfo: SERVER_INFO,
        };
        break;
      case "ping":
        result = {};
        break;
      case "tools/list":
        result = { tools: TOOLS };
        break;
      case "tools/call":
        try {
          const text = await callTool(params?.name, params?.arguments);
          result = { content: [{ type: "text", text }] };
        } catch (e) {
          result = { content: [{ type: "text", text: String(e.message || e) }], isError: true };
        }
        break;
      default:
        if (!isRequest) return; // уведомления (notifications/*) игнорируем
        send({ jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } });
        return;
    }
    if (isRequest) send({ jsonrpc: "2.0", id, result });
  } catch (e) {
    if (isRequest) send({ jsonrpc: "2.0", id, error: { code: -32603, message: String(e.message || e) } });
  }
}

const isMain = import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("server.mjs");
if (isMain) {
  const rl = createInterface({ input: process.stdin });
  rl.on("line", (line) => {
    if (!line.trim()) return;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      send({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
      return;
    }
    handle(msg);
  });
}
