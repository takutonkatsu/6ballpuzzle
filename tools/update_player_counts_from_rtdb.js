#!/usr/bin/env node

const { execFileSync } = require('child_process');

const args = process.argv.slice(2);
const projectIndex = args.indexOf('--project');
const project =
  projectIndex >= 0 && args[projectIndex + 1] ? args[projectIndex + 1] : 'prod';

function firebaseJson(commandArgs) {
  const output = execFileSync('firebase', commandArgs, {
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 64,
  }).trim();
  if (!output || output === 'null') {
    return null;
  }
  return JSON.parse(output);
}

function firebaseWrite(path, value) {
  execFileSync(
    'firebase',
    [
      'database:set',
      path,
      '--data',
      JSON.stringify(value),
      '--force',
      '--project',
      project,
    ],
    {
      stdio: 'inherit',
      maxBuffer: 1024 * 1024 * 16,
    },
  );
}

function recordsFrom(raw) {
  if (!raw) {
    return [];
  }
  if (Array.isArray(raw)) {
    return raw.filter((value) => value && typeof value === 'object');
  }
  if (typeof raw === 'object') {
    return Object.values(raw).filter((value) => value && typeof value === 'object');
  }
  return [];
}

function jstDateKey(date) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Tokyo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  return formatter.format(date);
}

function jstDateTimeText(date) {
  const parts = new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Asia/Tokyo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).format(date);
  return parts.replace(' ', 'T') + '+09:00';
}

function accountCreatedAt(summary) {
  const raw = summary?.overall?.accountCreatedAt;
  if (typeof raw !== 'string' || raw.trim() === '') {
    return null;
  }
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

const summaries = recordsFrom(
  firebaseJson(['database:get', '/playerRecordSummaries', '--project', project]),
);
const now = new Date();
const todayKeyJst = jstDateKey(now);
let todayNewPlayers = 0;

for (const summary of summaries) {
  const createdAt = accountCreatedAt(summary);
  if (createdAt && jstDateKey(createdAt) === todayKeyJst) {
    todayNewPlayers += 1;
  }
}

const payload = {
  totalPlayers: summaries.length,
  todayNewPlayers,
  todayKeyJst,
  sourcePath: 'playerRecordSummaries',
  updatedAt: Date.now(),
  updatedAtTextJst: jstDateTimeText(now),
};

firebaseWrite('/adminStats/playerCounts', payload);
console.log(JSON.stringify(payload, null, 2));
