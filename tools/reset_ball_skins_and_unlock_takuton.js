#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const admin = require('../functions/node_modules/firebase-admin');

const serviceAccount = require('/Users/takuto/hexagon-puzzle-prod-e811c-firebase-adminsdk-fbsvc-833def00e5.json');

const APPLY = process.argv.includes('--apply');
const DATABASE_URL =
  'https://hexagon-puzzle-prod-e811c-default-rtdb.asia-southeast1.firebasedatabase.app';
const TARGET_NAME = 'たくとんかつ';

function extractField(block, name) {
  const match = block.match(new RegExp(`${name}:\\s*'([^']*)'`));
  return match ? match[1] : null;
}

function extractEnum(block, enumName, fallback) {
  const match = block.match(new RegExp(`${enumName}\\.(\\w+)`));
  return match ? match[1] : fallback;
}

function extractCatalogItems() {
  const dartPath = path.resolve(__dirname, '../lib/data/models/game_item.dart');
  const source = fs.readFileSync(dartPath, 'utf8');
  const itemsById = new Map();
  const regex = /GameItem\(\s*([\s\S]*?)\s*\),/g;
  let match;
  while ((match = regex.exec(source)) !== null) {
    const block = match[1];
    const id = extractField(block, 'id');
    if (!id) {
      continue;
    }
    const type = extractEnum(block, 'ItemType', null);
    if (!type) {
      continue;
    }
    const rarity = extractEnum(block, 'ItemRarity', 'common');
    const levelMatch = block.match(/level:\s*(\d+)/);
    const item = {
      id,
      name: extractField(block, 'name') || id,
      type,
      rarity,
      level: type === 'stamp' ? 4 : Number.parseInt(levelMatch?.[1] ?? '1', 10),
    };
    const iconName = extractField(block, 'iconName');
    const colorName = extractField(block, 'colorName');
    const text = extractField(block, 'text');
    if (iconName) item.iconName = iconName;
    if (colorName) item.colorName = colorName;
    if (text) item.text = text;
    itemsById.set(id, item);
  }
  return [...itemsById.values()].filter((item) => item.id !== 'skin_luxury_prism');
}

function displayNameOf(uid, user, summary, lookupNames) {
  return (
    lookupNames.get(uid) ||
    user?.displayName ||
    user?.name ||
    user?.profile?.displayName ||
    summary?.displayName ||
    summary?.name ||
    ''
  ).toString();
}

function normalizeOwnedItems(raw) {
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw
    .filter((item) => item && typeof item === 'object' && typeof item.id === 'string')
    .map((item) => ({...item}));
}

function idsOf(items, type) {
  return items.filter((item) => item.type === type).map((item) => item.id);
}

function collectionPatchFor(items, equippedBallSkinId) {
  return {
    ownedItemCount: items.length,
    ownedItems: items,
    ownedStampIds: idsOf(items, 'stamp'),
    ownedSkinIds: idsOf(items, 'skin'),
    ownedIconIds: idsOf(items, 'icon'),
    ownedFrameIds: idsOf(items, 'frame'),
    ownedBannerIds: idsOf(items, 'banner'),
    ownedEffectIds: idsOf(items, 'vfx'),
    ownedAudioIds: idsOf(items, 'audio'),
    equippedBallSkinId,
  };
}

function mergeItems(existing, catalogItems) {
  const byId = new Map();
  for (const item of existing) {
    byId.set(item.id, item);
  }
  for (const item of catalogItems) {
    byId.set(item.id, item);
  }
  return [...byId.values()];
}

async function applyInChunks(db, updates, chunkSize = 400) {
  const entries = Object.entries(updates);
  for (let i = 0; i < entries.length; i += chunkSize) {
    await db.ref().update(Object.fromEntries(entries.slice(i, i + chunkSize)));
  }
}

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL: DATABASE_URL,
    });
  }

  const db = admin.database();
  const [usersSnap, summariesSnap, nameLookupSnap] = await Promise.all([
    db.ref('users').get(),
    db.ref('playerRecordSummaries').get(),
    db.ref('playerNameLookup').get(),
  ]);

  const users = usersSnap.val() || {};
  const summaries = summariesSnap.val() || {};
  const lookupNames = new Map();
  const exactTargetUids = new Set();
  const lookup = nameLookupSnap.val() || {};
  for (const [name, uidMap] of Object.entries(lookup)) {
    if (!uidMap || typeof uidMap !== 'object') {
      continue;
    }
    for (const uid of Object.keys(uidMap)) {
      if (name === TARGET_NAME) {
        exactTargetUids.add(uid);
      }
      lookupNames.set(uid, name);
    }
  }

  const catalogItems = extractCatalogItems();
  const allUids = new Set([...Object.keys(users), ...Object.keys(summaries)]);
  const updates = {};
  const report = {
    apply: APPLY,
    totalUsers: allUids.size,
    resetUsers: 0,
    resetSkinItemCount: 0,
    takutonUids: [],
    catalogItemCount: catalogItems.length,
    catalogCounts: {
      stamp: idsOf(catalogItems, 'stamp').length,
      skin: idsOf(catalogItems, 'skin').length,
      icon: idsOf(catalogItems, 'icon').length,
      frame: idsOf(catalogItems, 'frame').length,
      banner: idsOf(catalogItems, 'banner').length,
      vfx: idsOf(catalogItems, 'vfx').length,
      audio: idsOf(catalogItems, 'audio').length,
    },
  };

  for (const uid of allUids) {
    const user = users[uid] || {};
    const summary = summaries[uid] || {};
    const displayName = displayNameOf(uid, user, summary, lookupNames);
    const isTakuton =
      exactTargetUids.has(uid) ||
      displayName === TARGET_NAME ||
      user?.displayName === TARGET_NAME ||
      user?.name === TARGET_NAME ||
      user?.profile?.displayName === TARGET_NAME ||
      summary?.displayName === TARGET_NAME ||
      summary?.name === TARGET_NAME;
    const userCollection = user.collection || {};
    const summaryCollection = summary.collection || {};
    const existingItems = normalizeOwnedItems(
      userCollection.ownedItems || summaryCollection.ownedItems,
    );

    if (isTakuton) {
      const ownedItems = mergeItems(existingItems, catalogItems);
      const equippedBallSkinId =
        (userCollection.equippedBallSkinId ||
          summaryCollection.equippedBallSkinId ||
          'default').toString();
      const collection = collectionPatchFor(ownedItems, equippedBallSkinId);
      updates[`users/${uid}/collection`] = {
        ...userCollection,
        ...collection,
        updatedAt: admin.database.ServerValue.TIMESTAMP,
      };
      updates[`playerRecordSummaries/${uid}/collection`] = {
        ...summaryCollection,
        ...collection,
        updatedAt: admin.database.ServerValue.TIMESTAMP,
      };
      updates[`users/${uid}/updatedAt`] = admin.database.ServerValue.TIMESTAMP;
      updates[`playerRecordSummaries/${uid}/updatedAt`] =
        admin.database.ServerValue.TIMESTAMP;
      report.takutonUids.push(uid);
      continue;
    }

    const filteredItems = existingItems.filter((item) => item.type !== 'skin');
    const removed = existingItems.length - filteredItems.length;
    const needsReset =
      removed > 0 ||
      (!!userCollection.equippedBallSkinId &&
        userCollection.equippedBallSkinId !== 'default') ||
      (!!summaryCollection.equippedBallSkinId &&
        summaryCollection.equippedBallSkinId !== 'default') ||
      (Array.isArray(userCollection.ownedSkinIds) && userCollection.ownedSkinIds.length > 0) ||
      (Array.isArray(summaryCollection.ownedSkinIds) &&
        summaryCollection.ownedSkinIds.length > 0);

    if (!needsReset) {
      continue;
    }

    const collection = collectionPatchFor(filteredItems, 'default');
    updates[`users/${uid}/collection`] = {
      ...userCollection,
      ...collection,
      updatedAt: admin.database.ServerValue.TIMESTAMP,
    };
    updates[`playerRecordSummaries/${uid}/collection`] = {
      ...summaryCollection,
      ...collection,
      updatedAt: admin.database.ServerValue.TIMESTAMP,
    };
    updates[`users/${uid}/updatedAt`] = admin.database.ServerValue.TIMESTAMP;
    updates[`playerRecordSummaries/${uid}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;
    report.resetUsers += 1;
    report.resetSkinItemCount += removed;
  }

  console.log(JSON.stringify(report, null, 2));
  console.log(`updates=${Object.keys(updates).length}`);

  if (!APPLY) {
    console.log(
      '\nDRY RUN ONLY. Apply with: node tools/reset_ball_skins_and_unlock_takuton.js --apply',
    );
    return;
  }

  await applyInChunks(db, updates);
  console.log('Applied ball skin reset and Takutonkatsu collection unlock.');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
