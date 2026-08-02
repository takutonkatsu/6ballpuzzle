#!/usr/bin/env node

const admin = require('../functions/node_modules/firebase-admin');

function databaseUrl(projectName) {
  if (projectName === 'prod' || projectName === 'hexagon-puzzle-prod-e811c') {
    return 'https://hexagon-puzzle-prod-e811c-default-rtdb.asia-southeast1.firebasedatabase.app';
  }
  throw new Error(`Unknown project: ${projectName}`);
}

function initialize(projectName) {
  const credentialPath =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ||
    '/Users/takuto/hexagon-puzzle-prod-e811c-firebase-adminsdk-fbsvc-833def00e5.json';
  admin.initializeApp({
    credential: admin.credential.cert(credentialPath),
    databaseURL: databaseUrl(projectName),
  });
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function numberValue(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  const parsed = Number.parseInt(`${value}`, 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function keySafe(value) {
  return `${value}`.replace(/[.#$\[\]\/]/g, '_');
}

function expirationIndexKey(expiresAt, uid, grantId) {
  return `${String(Math.trunc(expiresAt)).padStart(13, '0')}_${keySafe(uid)}_${keySafe(grantId)}`;
}

async function main() {
  const projectName = process.argv[2] || 'prod';
  initialize(projectName);
  const snapshot = await admin.database().ref('adminGrants').get();
  const grantsByUid = isObject(snapshot.val()) ? snapshot.val() : {};
  const updates = {};
  let indexedCount = 0;
  for (const [uid, grants] of Object.entries(grantsByUid)) {
    if (!isObject(grants)) continue;
    for (const [grantId, grant] of Object.entries(grants)) {
      if (!isObject(grant)) continue;
      const expiresAt = numberValue(grant.expiresAt);
      if (expiresAt <= 0) continue;
      const indexKey = expirationIndexKey(expiresAt, uid, grantId);
      updates[`adminGrants/${uid}/${grantId}/expirationIndexKey`] = indexKey;
      updates[`adminGrantExpirations/${indexKey}`] = {
        uid,
        grantId,
        expiresAt,
      };
      indexedCount++;
    }
  }
  if (indexedCount > 0) {
    await admin.database().ref().update(updates);
  }
  console.log(`Backfilled admin grant expirations: ${indexedCount}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
