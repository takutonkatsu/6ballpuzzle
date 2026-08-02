#!/usr/bin/env node

const { execFileSync } = require('child_process');
const fs = require('fs');

const admin = require('../functions/node_modules/firebase-admin');

const args = process.argv.slice(2);
const projectIndex = args.indexOf('--project');
const project =
  projectIndex >= 0 && args[projectIndex + 1] ? args[projectIndex + 1] : 'prod';

function firebaseJson(commandArgs) {
  const output = execFileSync('firebase', commandArgs, {
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 128,
  }).trim();
  if (!output || output === 'null') {
    return null;
  }
  return JSON.parse(output);
}

function databaseUrlForProject(projectName) {
  if (projectName === 'prod' || projectName === 'hexagon-puzzle-prod-e811c') {
    return 'https://hexagon-puzzle-prod-e811c-default-rtdb.asia-southeast1.firebasedatabase.app';
  }
  if (projectName === 'dev' || projectName === 'ballpuzzle-81978') {
    return 'https://ballpuzzle-81978-default-rtdb.asia-southeast1.firebasedatabase.app';
  }
  return `https://${projectName}-default-rtdb.asia-southeast1.firebasedatabase.app`;
}

function initializeAdmin() {
  if (admin.apps.length > 0) {
    return;
  }
  const credentialPath =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    '/Users/takuto/hexagon-puzzle-prod-e811c-firebase-adminsdk-fbsvc-833def00e5.json';
  if (fs.existsSync(credentialPath)) {
    admin.initializeApp({
      credential: admin.credential.cert(require(credentialPath)),
      databaseURL: databaseUrlForProject(project),
    });
    return;
  }
  admin.initializeApp({
    databaseURL: databaseUrlForProject(project),
  });
}

async function firebaseUpdate(path, value) {
  initializeAdmin();
  await admin.database().ref(path).update(value);
}

function recordsFrom(raw) {
  if (!raw || typeof raw !== 'object') {
    return [];
  }
  return Object.entries(raw).filter(
    ([, value]) => value && typeof value === 'object',
  );
}

function numberValue(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.trunc(parsed) : 0;
  }
  return 0;
}

function stringValue(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function upsertBest(bestByUid, uid, source) {
  if (!uid) {
    return;
  }
  const highestEndlessScore = Math.max(0, numberValue(source.highestEndlessScore));
  if (highestEndlessScore <= 0) {
    return;
  }
  const previous = bestByUid.get(uid);
  if (
    previous &&
    previous.highestEndlessScore > highestEndlessScore
  ) {
    return;
  }
  if (
    previous &&
    previous.highestEndlessScore === highestEndlessScore &&
    previous.updatedAt >= numberValue(source.updatedAt)
  ) {
    return;
  }
  bestByUid.set(uid, {
    uid,
    publicId: stringValue(source.publicId),
    displayName: stringValue(source.displayName) || 'プレイヤー',
    highestEndlessScore,
    updatedAt: numberValue(source.updatedAt) || Date.now(),
  });
}

const globalRankings = firebaseJson([
  'database:get',
  '/rankings/global',
  '--project',
  project,
]);
const summaries = firebaseJson([
  'database:get',
  '/playerRecordSummaries',
  '--project',
  project,
]);

const bestByUid = new Map();

for (const [uid, value] of recordsFrom(globalRankings)) {
  upsertBest(bestByUid, stringValue(value.uid) || uid, value);
}

for (const [uid, value] of recordsFrom(summaries)) {
  const endless = value.endless && typeof value.endless === 'object'
    ? value.endless
    : {};
  upsertBest(bestByUid, stringValue(value.uid) || uid, {
    uid: stringValue(value.uid) || uid,
    publicId: value.publicId,
    displayName: value.displayName,
    highestEndlessScore: endless.highestScore,
    updatedAt: value.updatedAt,
  });
}

const payload = {};
for (const [uid, value] of bestByUid.entries()) {
  payload[uid] = value;
}

if (Object.keys(payload).length === 0) {
  console.log('No endless all-time ranking entries to migrate.');
  process.exit(0);
}

firebaseUpdate('/endlessAllTimeRankings', payload)
  .then(() => {
    console.log(
      `Migrated ${Object.keys(payload).length} entries to /endlessAllTimeRankings.`,
    );
    return Promise.all(admin.apps.map((app) => app.delete()));
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
