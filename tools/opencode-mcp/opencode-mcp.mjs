#!/usr/bin/env node
// opencode MCP server for MWX: Claude hands execution tasks to opencode (DeepSeek) and gets the
// reports back. stdio, newline-delimited JSON-RPC 2.0. Nothing but protocol messages goes to stdout.
//
// Settings (env, set in the MCP client config):
//   OPENCODE_EXE              opencode command                (default "opencode")
//   OPENCODE_MODEL            e.g. "deepseek/<model id>"      (default: opencode's own default)
//   MWX_WORKDIR               working directory for opencode  (default C:\Games\cod-hwm)
//   MWX_TASKDIR               where task/report/log files go  (default <MWX_WORKDIR>\mwx-opencode)
//   OPENCODE_TIMEOUT_MINUTES  hard limit per task             (default 60)
import { spawn, execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";

const isWin = process.platform === "win32";
const env = (k, d) => (process.env[k] && process.env[k].trim()) || d;
const OPENCODE = env("OPENCODE_EXE", "opencode");
const MODEL = env("OPENCODE_MODEL", "");
const WORKDIR = env("MWX_WORKDIR", isWin ? "C:\\Games\\cod-hwm" : process.cwd());
const TASKDIR = env("MWX_TASKDIR", path.join(WORKDIR, "mwx-opencode"));
const TIMEOUT_MS = Number(env("OPENCODE_TIMEOUT_MINUTES", "60")) * 60 * 1000;
const MAX_WAIT = 110;
fs.mkdirSync(TASKDIR, { recursive: true });

const RULES = `# Executor rules (read first)

You are the EXECUTOR in the MWX workflow. Claude plans, designs, troubleshoots and reviews;
you carry out exactly one task and report back. Read C:\\Games\\cod-hwm\\cod-mwx\\AGENTS.md.

- Do exactly the task below. Do not widen the scope, refactor, or "improve" other things.
- Do not make design decisions. If the task is ambiguous, or a step fails and the fix is not
  obvious from the task, STOP and report (status BLOCKED) instead of guessing.
- Never change game files, .ff or .pak files, or hmw-mod.exe by hand. Only mwx.exe -repack /
  -repack-restore may change zones (they back up first). Never delete backups.
- Commit only when the task says so, on branch mwx, with the message the task gives (or a short one).
- Run everything the task asks for and copy the important output lines into the report.

Write the report to {{REPORT}} in this format:

    ## Status
    DONE | BLOCKED | FAILED  (one line why)
    ## What I did
    numbered steps, commands run, exit codes
    ## Changes
    files changed, commits (hash + message), files created; "none" if none
    ## Output
    the important output / log lines, measured numbers
    ## Problems / questions
    anything unexpected; "none" if none
`;

const tasks = new Map(); // id -> { id, title, dir, proc, start, end, exitCode, timedOut, cancelled }

const files = (dir) => ({
  task: path.join(dir, "task.md"),
  report: path.join(dir, "report.md"),
  log: path.join(dir, "opencode.log"),
  result: path.join(dir, "result.json"),
});
const stripAnsi = (s) => s.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "");
const readText = (f) => { try { return fs.readFileSync(f, "utf8"); } catch { return null; } };
const tail = (s, n) => s.split(/\r?\n/).slice(-n).join("\n");
const cap = (s, n = 60000) => (s.length > n ? s.slice(0, n) + `\n... (cut, ${s.length} chars)` : s);
const slug = (s) => (s || "task").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40) || "task";
const stamp = () => { const d = new Date(), p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`; };

function killTree(proc) {
  if (!proc || proc.exitCode !== null) return;
  if (isWin) execFile("taskkill.exe", ["/T", "/F", "/PID", String(proc.pid)], () => {});
  else { try { process.kill(-proc.pid, "SIGKILL"); } catch { try { proc.kill("SIGKILL"); } catch {} } }
}

function finish(t) {
  t.end = Date.now();
  fs.writeFileSync(files(t.dir).result, JSON.stringify({
    id: t.id, title: t.title, exitCode: t.exitCode, timedOut: t.timedOut, cancelled: t.cancelled,
    seconds: Math.round((t.end - t.start) / 1000),
  }, null, 2));
}

function running() { return [...tasks.values()].find((t) => !t.end); }

function startTask(text, title) {
  const busy = running();
  if (busy) throw new Error(`task ${busy.id} is still running; wait for it or cancel it first`);
  const id = `${stamp()}-${slug(title)}`;
  const dir = path.join(TASKDIR, id);
  fs.mkdirSync(dir, { recursive: true });
  const f = files(dir);
  fs.writeFileSync(f.task, RULES.replace("{{REPORT}}", f.report) + `\n\n# Task ${id}${title ? ` — ${title}` : ""}\n\n${text}\n`);
  const msg = `You are the executor. Read the task file ${f.task} and do exactly what it says. Write your report to ${f.report}.`;
  const args = ["run", ...(MODEL ? ["-m", MODEL] : []), msg];
  const out = fs.openSync(f.log, "w");
  // stdin from nothing, stdout/stderr into the log: opencode must never see or write our stdio.
  const proc = isWin
    ? spawn("cmd.exe", ["/d", "/s", "/c", `"${[OPENCODE, ...args].map((a) => `"${a}"`).join(" ")}"`],
        { cwd: WORKDIR, stdio: ["ignore", out, out], windowsHide: true, windowsVerbatimArguments: true })
    : spawn(OPENCODE, args, { cwd: WORKDIR, stdio: ["ignore", out, out], detached: true });
  const t = { id, title: title || "", dir, proc, start: Date.now(), end: null, exitCode: null, timedOut: false, cancelled: false };
  tasks.set(id, t);
  proc.on("exit", (code) => { fs.closeSync(out); if (!t.end) { t.exitCode = code; finish(t); } });
  proc.on("error", (e) => { fs.appendFileSync(f.log, `\n[mcp] could not start ${OPENCODE}: ${e.message}\n`); });
  t.timer = setTimeout(() => { if (!t.end) { t.timedOut = true; killTree(proc); } }, TIMEOUT_MS);
  t.timer.unref?.();
  return t;
}

function loadFromDisk(id) {
  const dir = path.join(TASKDIR, id);
  if (!fs.existsSync(dir)) return null;
  const r = readText(files(dir).result);
  const info = r ? JSON.parse(r) : {};
  return { id, title: info.title || "", dir, proc: null, start: 0, end: r ? 1 : null,
    exitCode: info.exitCode ?? null, timedOut: !!info.timedOut, cancelled: !!info.cancelled, orphan: !r };
}
const getTask = (id) => tasks.get(id) || loadFromDisk(id);

function describe(t) {
  const f = files(t.dir);
  const secs = Math.round(((t.end && t.start ? t.end : Date.now()) - (t.start || Date.now())) / 1000);
  if (!t.end) {
    if (t.orphan) return `Task ${t.id}: no result (the MCP server restarted while it ran).\n\nLast log lines:\n${tail(stripAnsi(readText(f.log) || ""), 30)}`;
    return `Task ${t.id}: RUNNING for ${secs}s. Call opencode_wait again.\n\nLast log lines:\n${tail(stripAnsi(readText(f.log) || ""), 15)}`;
  }
  const state = t.cancelled ? "CANCELLED" : t.timedOut ? "TIMED OUT" : `FINISHED (exit ${t.exitCode})`;
  const report = readText(f.report);
  let s = `Task ${t.id}: ${state}${t.start ? ` after ${secs}s` : ""}.\nFiles: ${t.dir}\n\n`;
  s += report ? `# Report\n\n${report}` : `No report was written. Last opencode output:\n\n${tail(stripAnsi(readText(f.log) || ""), 80)}`;
  return cap(s);
}

async function waitFor(t, seconds) {
  const until = Date.now() + Math.min(Math.max(seconds ?? 50, 0), MAX_WAIT) * 1000;
  while (!t.end && t.proc && Date.now() < until) await new Promise((r) => setTimeout(r, 500));
  return describe(t);
}

const TOOLS = [
  { name: "opencode_task",
    description: "Start an execution task in opencode (DeepSeek) in the MWX workspace. The executor rules (do only this task, no design decisions, fixed report format) are added automatically. Only one task runs at a time. Waits up to wait_seconds and returns the report if it finished, otherwise the task id to use with opencode_wait.",
    inputSchema: { type: "object", properties: {
      task: { type: "string", description: "Full, self-contained task description with exact steps and acceptance checks" },
      title: { type: "string", description: "Short name, used in the task id" },
      wait_seconds: { type: "integer", description: `How long to wait for the result (0-${MAX_WAIT}, default 50)` } },
      required: ["task"] } },
  { name: "opencode_wait",
    description: "Wait for a task (up to wait_seconds) and return its status, or its report once it finished.",
    inputSchema: { type: "object", properties: {
      id: { type: "string" }, wait_seconds: { type: "integer", description: `0-${MAX_WAIT}, default 50` } },
      required: ["id"] } },
  { name: "opencode_list",
    description: "List the most recent tasks with their state.",
    inputSchema: { type: "object", properties: { count: { type: "integer", description: "default 15" } } } },
  { name: "opencode_cancel",
    description: "Stop a running task (kills opencode and its child processes).",
    inputSchema: { type: "object", properties: { id: { type: "string" } }, required: ["id"] } },
];

async function callTool(name, a = {}) {
  switch (name) {
    case "opencode_task": {
      if (!a.task || !String(a.task).trim()) throw new Error("task is empty");
      const t = startTask(String(a.task), a.title);
      return waitFor(t, a.wait_seconds);
    }
    case "opencode_wait": {
      const t = getTask(a.id); if (!t) throw new Error(`unknown task ${a.id}`);
      return waitFor(t, a.wait_seconds);
    }
    case "opencode_list": {
      const ids = fs.readdirSync(TASKDIR).filter((d) => fs.statSync(path.join(TASKDIR, d)).isDirectory())
        .sort().reverse().slice(0, a.count || 15);
      if (!ids.length) return "No tasks yet.";
      return ids.map((id) => { const t = getTask(id);
        const st = !t.end ? (t.orphan ? "no result" : "RUNNING") : t.cancelled ? "cancelled" : t.timedOut ? "timed out" : `exit ${t.exitCode}`;
        return `${id}  ${st}${fs.existsSync(files(t.dir).report) ? "  (report)" : ""}`; }).join("\n");
    }
    case "opencode_cancel": {
      const t = tasks.get(a.id); if (!t || t.end) throw new Error(`task ${a.id} is not running`);
      t.cancelled = true; killTree(t.proc);
      return `Cancelling ${t.id}.`;
    }
    default: throw new Error(`unknown tool ${name}`);
  }
}

const send = (m) => process.stdout.write(JSON.stringify(m) + "\n");

async function handle(m) {
  switch (m.method) {
    case "initialize":
      return { protocolVersion: m.params?.protocolVersion || "2025-06-18", capabilities: { tools: {} },
        serverInfo: { name: "mwx-opencode", version: "1.0.0" },
        instructions: "Hands execution tasks to opencode (DeepSeek). Claude plans and reviews; opencode executes. Review every report and approve it or send a revision task." };
    case "ping": return {};
    case "tools/list": return { tools: TOOLS };
    case "tools/call":
      try { return { content: [{ type: "text", text: await callTool(m.params?.name, m.params?.arguments || {}) }] }; }
      catch (e) { return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true }; }
    default: { const e = new Error(`method not found: ${m.method}`); e.code = -32601; throw e; }
  }
}

// Requests are handled one after another so a long wait never interleaves with another call.
let chain = Promise.resolve();
readline.createInterface({ input: process.stdin }).on("line", (line) => {
  if (!line.trim()) return;
  let m;
  try { m = JSON.parse(line); } catch { send({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "parse error" } }); return; }
  if (m.id === undefined) return; // notification
  chain = chain.then(async () => {
    try { send({ jsonrpc: "2.0", id: m.id, result: await handle(m) }); }
    catch (e) { send({ jsonrpc: "2.0", id: m.id, error: { code: e.code || -32603, message: e.message } }); }
  });
}).on("close", () => chain.then(() => process.exit(0)));
