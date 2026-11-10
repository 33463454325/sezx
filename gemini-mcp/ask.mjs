#!/usr/bin/env node
// Быстрый вызов Gemini из терминала:
//   node gemini-mcp/ask.mjs "твой вопрос"
//   cat file.js | node gemini-mcp/ask.mjs "найди ошибки в этом коде"
import { fstatSync } from "node:fs";
import { generate } from "./server.mjs";

const question = process.argv.slice(2).join(" ");
let stdin = "";
let piped = false;
try {
  const st = fstatSync(0);
  piped = st.isFIFO() || st.isFile();
} catch {}
if (piped) {
  for await (const chunk of process.stdin) stdin += chunk;
}
const prompt = [question, stdin].filter(Boolean).join("\n\n");
if (!prompt) {
  console.error('Использование: node gemini-mcp/ask.mjs "вопрос"  (можно передать текст через stdin)');
  process.exit(1);
}
try {
  console.log(await generate({ prompt }));
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
