#!/usr/bin/env node
// 飞书 Bug 机器人：轮询「夜航船 · Bug 反馈」群，@我 的消息交给 Claude Code 自动修复并提交。
// 用法：node bug-bot.mjs [--config <path>] [--state <path>] [--once]
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

const once = argv.includes('--once');
const configPath = path.resolve(getArg('--config', path.join(__dirname, 'config.json')));
const statePath = path.resolve(getArg('--state', path.join(__dirname, '.state.json')));
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const logsDir = path.join(__dirname, 'logs');
fs.mkdirSync(logsDir, { recursive: true });

const larkEnv = {
  ...process.env,
  LARKSUITE_CLI_NO_UPDATE_NOTIFIER: '1',
  LARKSUITE_CLI_NO_SKILLS_NOTIFIER: '1',
};

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
  const result = await run(config.larkCliPath, args, { env: larkEnv });
  const payload = parseJsonLoose(result.stdout);
  if (!payload) {
    log('lark-cli 返回无法解析', result.code, result.stderr.slice(0, 300));
    return { ok: false, error: { message: result.stderr.slice(0, 300) } };
  }
  return payload;
}

function loadState() {
  if (!fs.existsSync(statePath)) return null;
  try {
    return JSON.parse(fs.readFileSync(statePath, 'utf8'));
  } catch {
    return null;
  }
}

function saveState(state) {
  const tmp = `${statePath}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2));
  fs.renameSync(tmp, statePath);
}

const state = loadState() ?? { processed: [], baselineDone: false };
const processed = new Set(state.processed);

async function fetchMessages() {
  const res = await lark([
    'im', '+chat-messages-list',
    '--as', 'user',
    '--chat-id', config.chatId,
    '--order', 'desc',
    '--page-size', '50',
    '--no-reactions',
    '--json',
  ]);
  if (!res.ok) {
    log('拉取消息失败', JSON.stringify(res.error ?? res).slice(0, 300));
    return null;
  }
  return res.data?.messages ?? [];
}

function mentionText(message) {
  let text = message.content ?? '';
  for (const mention of message.mentions ?? []) {
    text = text.split(`@${mention.name}`).join('');
  }
  return text.replace(/\s+/g, ' ').trim();
}

function isBugMessage(message) {
  if (!['text', 'post'].includes(message.msg_type)) return false;
  if (processed.has(message.message_id)) return false;
  return (message.mentions ?? []).some((m) => m.id === config.triggerOpenId);
}

async function reply(messageId, markdown) {
  return lark([
    'im', '+messages-reply',
    '--as', 'user',
    '--message-id', messageId,
    '--markdown', markdown.slice(0, 4000),
  ]);
}

async function git(args, cwd) {
  return run('git', args, { cwd });
}

async function fixBug(message, text) {
  const title = text.split('\n')[0].slice(0, 80) || '(无描述)';
  const started = Date.now();
  log(`开始修复 ${message.message_id}：${title}`);

  const ack = await reply(message.message_id, `已收到 bug，开始自动修复。\n\n> ${title}`);
  if (!ack.ok) log('发送受理回执失败', ack.error?.message);

  const statusBefore = await git(['status', '--porcelain'], config.repoDir);
  const dirtyBefore = statusBefore.stdout.trim().length > 0;

  const prompt = [
    '你是「夜航船」iOS 项目的自动修复助手。用户在飞书群提交了一条 bug：',
    '',
    `消息来源：${message.message_id}`,
    `报告时间：${message.create_time}`,
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
    await reply(message.message_id, `**修复超时**（${Math.round(config.agentTimeoutMs / 60000)} 分钟）\n\n请拆小问题范围后重新提交。`);
    return;
  }

  const parsed = parseClaudeResult(agent.stdout);
  if (!parsed || parsed.is_error) {
    const detail = (parsed?.result || agent.stdout || agent.stderr || '无输出').slice(0, 1200);
    await reply(message.message_id, `**修复失败**\n\n\`\`\`\n${detail}\n\`\`\``);
    log('修复失败', message.message_id, detail.slice(0, 300));
    return;
  }

  const rawSummary = parsed.result || '';
  const summary = rawSummary.length > 1200 ? `${rawSummary.slice(0, 1200)}…` : rawSummary;
  const statusAfter = await git(['status', '--porcelain'], config.repoDir);
  const changedFiles = statusAfter.stdout.trim().split('\n').filter(Boolean).map((line) => line.slice(3));

  if (dirtyBefore) {
    await reply(message.message_id, [
      `**已执行修复，但未自动提交**`,
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
    await reply(message.message_id, `**未产生代码改动**\n\n${summary}`);
    return;
  }

  await git(['add', '-A'], config.repoDir);
  const commitMessage = [
    `${config.commitPrefix}: ${title}`,
    '',
    `来源：飞书群 ${config.chatId} 消息 ${message.message_id}`,
  ].join('\n');
  const commit = await git(['commit', '-m', commitMessage], config.repoDir);

  if (commit.code !== 0) {
    await reply(message.message_id, `**已修改但提交失败**\n\n\`\`\`\n${commit.stderr.slice(0, 800)}\n\`\`\``);
    return;
  }

  const hash = (await git(['rev-parse', '--short', 'HEAD'], config.repoDir)).stdout.trim();
  const stat = (await git(['show', '--stat', '--format=', 'HEAD'], config.repoDir)).stdout.trim();
  const cost = parsed.total_cost_usd ? `，耗时 ${Math.round((Date.now() - started) / 1000)}s` : '';

  await reply(message.message_id, [
    `**修复完成并已提交** \`${hash}\`${cost}`,
    '',
    '```',
    stat.slice(0, 1500),
    '```',
    '',
    summary,
  ].join('\n'));
  log(`修复完成 ${message.message_id} → ${hash}`);
}

async function tick() {
  const messages = await fetchMessages();
  if (!messages) return;

  if (!state.baselineDone) {
    for (const message of messages) processed.add(message.message_id);
    state.baselineDone = true;
    state.processed = [...processed].slice(-1000);
    saveState(state);
    log(`已建立基线，忽略 ${messages.length} 条历史消息`);
    return;
  }

  const bugs = [...messages].reverse().filter(isBugMessage);
  if (bugs.length === 0) return;

  for (const message of bugs) {
    processed.add(message.message_id);
    state.processed = [...processed].slice(-1000);
    saveState(state);

    const text = mentionText(message);
    if (!text) {
      await reply(message.message_id, '请在 @我 的同一条消息里附上 bug 描述。');
      continue;
    }
    await fixBug(message, text);
  }
}

let stopping = false;
process.on('SIGINT', () => {
  stopping = true;
  log('收到 SIGINT，准备退出');
});
process.on('SIGTERM', () => {
  stopping = true;
  log('收到 SIGTERM，准备退出');
});

async function main() {
  log(`启动：群 ${config.chatId}，仓库 ${config.repoDir}，轮询 ${config.pollIntervalMs}ms`);
  if (once) {
    await tick();
    return;
  }
  while (!stopping) {
    try {
      await tick();
    } catch (error) {
      log('轮询异常', error?.message ?? error);
    }
    await sleep(config.pollIntervalMs);
  }
  log('已退出');
}

main().then(() => process.exit(0));
