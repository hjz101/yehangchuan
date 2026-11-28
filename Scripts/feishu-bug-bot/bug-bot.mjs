#!/usr/bin/env node
// 飞书 Bug 机器人：通过长连接接收「夜航船」群里 @机器人 的消息，交给 Claude Code 自动修复并提交。
// 用法：node bug-bot.mjs [--config <path>] [--state <path>]
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);

function getArg(name, fallback) {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
}

const configPath = path.resolve(getArg('--config', path.join(__dirname, 'config.json')));
const statePath = path.resolve(getArg('--state', path.join(__dirname, '.state.json')));
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
fs.mkdirSync(path.join(__dirname, 'logs'), { recursive: true });

const larkEnv = {
  ...process.env,
  LARKSUITE_CLI_NO_UPDATE_NOTIFIER: '1',
  LARKSUITE_CLI_NO_SKILLS_NOTIFIER: '1',
};
delete larkEnv.LARKSUITE_CLI_USER_ACCESS_TOKEN;

let cachedToken = null;
let tokenExpireAt = 0;

async function tenantToken() {
  if (cachedToken && Date.now() < tokenExpireAt) return cachedToken;
  const appId = process.env.LARKSUITE_CLI_APP_ID;
  const appSecret = process.env.LARKSUITE_CLI_APP_SECRET;
  if (!appId || !appSecret) throw new Error('缺少 LARKSUITE_CLI_APP_ID / APP_SECRET');
  const res = await fetch('https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ app_id: appId, app_secret: appSecret }),
  });
  const data = await res.json();
  if (!data.tenant_access_token) throw new Error(`获取 tenant token 失败：${JSON.stringify(data)}`);
  cachedToken = data.tenant_access_token;
  tokenExpireAt = Date.now() + Math.max(60, data.expire - 300) * 1000;
  return cachedToken;
}

function log(...parts) {
  console.log(`[${new Date().toISOString()}]`, ...parts);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function run(cmd, args, options = {}) {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, {
      cwd: options.cwd,
      env: options.env ?? process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    let timer = null;
    let timedOut = false;

    if (options.timeoutMs) {
      timer = setTimeout(() => {
        timedOut = true;
        child.kill('SIGKILL');
      }, options.timeoutMs);
    }

    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('error', (error) => {
      if (timer) clearTimeout(timer);
      resolve({ code: -1, stdout, stderr: `${stderr}\nspawn error: ${error.message}`, timedOut });
    });
    child.on('close', (code) => {
      if (timer) clearTimeout(timer);
      resolve({ code, stdout, stderr, timedOut });
    });
  });
}

function parseJsonLoose(text) {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    return null;
  }
}

function parseClaudeResult(text) {
  const lines = text.split('\n').filter((line) => line.trim().startsWith('{'));
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    try {
      const obj = JSON.parse(lines[i]);
      if (obj && typeof obj === 'object' && 'result' in obj) return obj;
    } catch {
      // 忽略非 JSON 行
    }
  }
  return null;
}

async function lark(args) {
  const token = await tenantToken();
  const result = await run(config.larkCliPath, args, {
    env: { ...larkEnv, LARKSUITE_CLI_TENANT_ACCESS_TOKEN: token },
  });
  const payload = parseJsonLoose(result.stdout);
  if (!payload) {
    log('lark-cli 返回无法解析', result.code, result.stderr.slice(0, 300));
    return { ok: false, error: { message: result.stderr.slice(0, 300) } };
  }
  if (!payload.ok && payload.error?.code === 99991663) cachedToken = null;
  return payload;
}

function loadState() {
  if (!fs.existsSync(statePath)) return { processed: [] };
  try {
    const parsed = JSON.parse(fs.readFileSync(statePath, 'utf8'));
    return { processed: Array.isArray(parsed.processed) ? parsed.processed : [] };
  } catch {
    return { processed: [] };
  }
}

const state = loadState();
const processed = new Set(state.processed);

function saveState() {
  const tmp = `${statePath}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify({ processed: [...processed].slice(-2000) }, null, 2));
  fs.renameSync(tmp, statePath);
}

async function reply(messageId, markdown) {
  return lark([
    'im', '+messages-reply',
    '--as', 'bot',
    '--message-id', messageId,
    '--markdown', markdown.slice(0, 4000),
  ]);
}

async function git(args, cwd) {
  return run('git', args, { cwd });
}

function mentionText(event) {
  let text = event.content ?? '';
  for (const mention of event.mentions ?? []) {
    text = text.split(`@${mention.name}`).join('');
  }
  return text.replace(/\s+/g, ' ').trim();
}

const queue = [];
let working = false;

async function drainQueue() {
  if (working) return;
  working = true;
  try {
    while (queue.length) {
      const item = queue.shift();
      try {
        await fixBug(item.event, item.text);
      } catch (error) {
        log('处理失败', error?.message ?? error);
      }
    }
  } finally {
    working = false;
  }
}

async function fixBug(event, text) {
  const title = text.split('\n')[0].slice(0, 80) || '(无描述)';
  const started = Date.now();
  log(`开始修复 ${event.message_id}：${title}`);

  const ack = await reply(event.message_id, `已收到 bug，开始自动修复。\n\n> ${title}`);
  if (!ack.ok) log('发送受理回执失败', ack.error?.message);

  const statusBefore = await git(['status', '--porcelain'], config.repoDir);
  const dirtyBefore = statusBefore.stdout.trim().length > 0;

  const prompt = [
    '你是「夜航船」iOS 项目的自动修复助手。用户在飞书群提交了一条 bug：',
    '',
    `消息来源：${event.message_id}`,
    `报告人：${event.sender_id}`,
    'bug 内容：',
    text,
    '',
    '处理要求：',
    '1. 先阅读相关代码和 AGENTS.md，定位根因，做最小必要修改。',
    '2. 不要执行 git commit / git push，提交由调用脚本统一完成。',
    '3. 如果编译或测试成本较低，请验证修改；不要为此长时间阻塞。',
    '4. 完成后用中文简要说明：根因、改动文件、验证情况，控制在 300 字以内。',
    '5. 如果信息不足，不要臆测，直接说明需要用户补充哪些信息。',
    '6. 忽略与本 bug 无关的环境提示（记忆插件、登录状态、模型告警等），不要写进结论。',
  ].join('\n');

  const agent = await run(config.claudePath, [
    '-p',
    '--permission-mode', 'acceptEdits',
    '--output-format', 'json',
    prompt,
  ], {
    cwd: config.repoDir,
    timeoutMs: config.agentTimeoutMs,
  });

  if (agent.timedOut) {
    await reply(event.message_id, `**修复超时**（${Math.round(config.agentTimeoutMs / 60000)} 分钟）\n\n请拆小问题范围后重新提交。`);
    return;
  }

  const parsed = parseClaudeResult(agent.stdout);
  log(`Claude 退出 code=${agent.code} timedOut=${agent.timedOut} stdout=${agent.stdout.length}B stderr=${agent.stderr.length}B`);
  if (!parsed || parsed.is_error) {
    const detail = (parsed?.result || agent.stdout || agent.stderr || '无输出').slice(0, 1200);
    await reply(event.message_id, `**修复失败**\n\n\`\`\`\n${detail}\n\`\`\``);
    log('修复失败', event.message_id, detail.slice(0, 300));
    return;
  }

  const rawSummary = parsed.result || '';
  const summary = rawSummary.length > 1200 ? `${rawSummary.slice(0, 1200)}…` : rawSummary;
  const statusAfter = await git(['status', '--porcelain'], config.repoDir);
  const changedFiles = statusAfter.stdout.trim().split('\n').filter(Boolean).map((line) => line.slice(3));

  if (dirtyBefore) {
    await reply(event.message_id, [
      '**已执行修复，但未自动提交**',
      '',
      '工作区在任务开始前已有未提交改动，为避免误提交，提交需你手动完成。',
      '',
      `改动文件：${changedFiles.length ? changedFiles.map((f) => `\`${f}\``).join('、') : '无'}`,
      '',
      summary,
    ].join('\n'));
    return;
  }

  if (changedFiles.length === 0) {
    await reply(event.message_id, `**未产生代码改动**\n\n${summary}`);
    return;
  }

  await git(['add', '-A'], config.repoDir);
  const commitMessage = [
    `${config.commitPrefix}: ${title}`,
    '',
    `来源：飞书群 ${config.chatId} 消息 ${event.message_id}`,
  ].join('\n');
  const commit = await git(['commit', '-m', commitMessage], config.repoDir);

  if (commit.code !== 0) {
    await reply(event.message_id, `**已修改但提交失败**\n\n\`\`\`\n${commit.stderr.slice(0, 800)}\n\`\`\``);
    return;
  }

  const hash = (await git(['rev-parse', '--short', 'HEAD'], config.repoDir)).stdout.trim();
  const stat = (await git(['show', '--stat', '--format=', 'HEAD'], config.repoDir)).stdout.trim();

  await reply(event.message_id, [
    `**修复完成并已提交** \`${hash}\`，耗时 ${Math.round((Date.now() - started) / 1000)}s`,
    '',
    '```',
    stat.slice(0, 1500),
    '```',
    '',
    summary,
  ].join('\n'));
  log(`修复完成 ${event.message_id} → ${hash}`);
}

function handleEvent(event) {
  if (event?.type !== 'im.message.receive_v1') return;
  if (event.chat_id !== config.chatId) return;
  if (processed.has(event.message_id)) return;
  if (event.sender_type !== 'user') return;
  if (!['text', 'post'].includes(event.message_type)) return;
  const mentioned = (event.mentions ?? []).some((m) => m.id === config.triggerOpenId);
  if (!mentioned) return;

  processed.add(event.message_id);
  saveState();

  const text = mentionText(event);
  if (!text) return;
  queue.push({ event, text });
  drainQueue();
}

let stopping = false;
let consumer = null;

async function startConsumer() {
  cachedToken = null;
  const token = await tenantToken();
  log('启动事件长连接');
  consumer = spawn(config.larkCliPath, [
    'event', 'consume', 'im.message.receive_v1',
    '--as', 'bot',
  ], {
    env: { ...larkEnv, LARKSUITE_CLI_TENANT_ACCESS_TOKEN: token },
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  let buffer = '';
  consumer.stdout.on('data', (chunk) => {
    buffer += chunk.toString();
    const lines = buffer.split('\n');
    buffer = lines.pop() ?? '';
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed.startsWith('{')) {
        if (trimmed) log(trimmed.slice(0, 200));
        continue;
      }
      const parsed = parseJsonLoose(trimmed);
      if (parsed) handleEvent(parsed);
    }
  });
  consumer.stderr.on('data', (chunk) => {
    const text = chunk.toString().trim();
    if (text) log(text.slice(0, 300));
  });
  consumer.on('close', (code) => {
    if (stopping) return;
    log(`事件连接退出（code ${code}），5 秒后重连`);
    setTimeout(() => {
      startConsumer().catch((error) => log('重连失败', error?.message ?? error));
    }, 5000);
  });
}

process.on('SIGINT', () => {
  stopping = true;
  consumer?.kill('SIGTERM');
  log('收到 SIGINT，退出');
  process.exit(0);
});
process.on('SIGTERM', () => {
  stopping = true;
  consumer?.kill('SIGTERM');
  log('收到 SIGTERM，退出');
  process.exit(0);
});

async function main() {
  log(`启动：群 ${config.chatId}，仓库 ${config.repoDir}`);
  await startConsumer();
}

main().catch((error) => {
  log('启动失败', error?.message ?? error);
  process.exit(1);
});
