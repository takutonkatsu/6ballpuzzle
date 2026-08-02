#!/usr/bin/env node

const fs = require('fs');

const admin = require('../functions/node_modules/firebase-admin');

const allowedKeys = new Set(['name', 'publicId', 'rating', 'updatedAt']);
const args = process.argv.slice(2);
const projectIndex = args.indexOf('--project');
const project =
  projectIndex >= 0 && args[projectIndex + 1] ? args[projectIndex + 1] : 'prod';

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

async function main() {
  initializeAdmin();
  const snapshot = await admin.database().ref('users').get();
  const users = snapshot.val();
  if (!users || typeof users !== 'object') {
    console.log('No /users data found.');
    return;
  }

  const updates = {};
  let prunedUsers = 0;
  let removedFields = 0;
  for (const [uid, value] of Object.entries(users)) {
    if (!value || typeof value !== 'object') {
      continue;
    }
    let prunedThisUser = false;
    for (const key of Object.keys(value)) {
      if (!allowedKeys.has(key)) {
        updates[`users/${uid}/${key}`] = null;
        removedFields++;
        prunedThisUser = true;
      }
    }
    if (prunedThisUser) {
      prunedUsers++;
    }
  }

  if (removedFields > 0) {
    await admin.database().ref().update(updates);
  }
  console.log(`Pruned ${removedFields} fields from ${prunedUsers} users.`);
}

main()
  .then(() => Promise.all(admin.apps.map((app) => app.delete())))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
