const fs = require('fs');
const path = require('path');
const admin = require('../functions/node_modules/firebase-admin');

const serviceAccountPath =
  '/Users/takuto/hexagon-puzzle-prod-e811c-firebase-adminsdk-fbsvc-833def00e5.json';
const databaseURL =
  'https://hexagon-puzzle-prod-e811c-default-rtdb.asia-southeast1.firebasedatabase.app';
const candidatesCsv = path.resolve(
  __dirname,
  '../reports/ranked_season_2026-07_only_candidates_2026-08-13.csv',
);

const currentSeasonId = '2026-08';
const noticeId = 'ranked_season_2026_08_rating_fix_1_4_2';
const noticeTitle = 'ランク戦レート補正のお知らせ';
const noticeMessage =
  'シーズン切替時の不具合により、ランク戦ランキングに正しく掲載されない状態が発生していました。ご迷惑をおかけし申し訳ございません。今シーズンの勝敗数に基づいてレートを補正し、ランキングへ反映しました。';
const noticeMinBuild = 51;

function parseCsvLine(line) {
  const result = [];
  let current = '';
  let quoted = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (ch === '"') {
      if (quoted && line[i + 1] === '"') {
        current += '"';
        i += 1;
      } else {
        quoted = !quoted;
      }
    } else if (ch === ',' && !quoted) {
      result.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  result.push(current);
  return result;
}

function readCandidates() {
  const raw = fs.readFileSync(candidatesCsv, 'utf8').trim();
  const [headerLine, ...lines] = raw.split(/\r?\n/);
  const headers = parseCsvLine(headerLine);
  return lines
    .filter((line) => line.trim().length > 0)
    .map((line) => {
      const values = parseCsvLine(line);
      const row = Object.fromEntries(headers.map((header, index) => [header, values[index] ?? '']));
      return {
        uid: row.uid,
        displayName: row.displayName,
        publicId: row.publicId,
        seasonId: row.seasonId,
        beforeRating: Number.parseInt(row.beforeRating, 10),
        correctedRating: Number.parseInt(row.correctedRating, 10),
        winsAfterSwitch: Number.parseInt(row.winsAfterSwitch, 10),
        lossesAfterSwitch: Number.parseInt(row.lossesAfterSwitch, 10),
        matchesAfterSwitch: Number.parseInt(row.matchesAfterSwitch, 10),
        maxWinStreakAfterSwitch: Number.parseInt(row.maxWinStreakAfterSwitch, 10),
      };
    });
}

async function main() {
  const apply = process.argv.includes('--apply');
  const serviceAccount = require(serviceAccountPath);
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL,
    });
  }
  const db = admin.database();
  const candidates = readCandidates().filter(
    (candidate) => candidate.seasonId === '2026-07' && candidate.uid,
  );

  const updates = {};
  const publishedAt = new Date().toISOString();
  for (const candidate of candidates) {
    const summarySnap = await db
      .ref(`playerRecordSummaries/${candidate.uid}`)
      .get();
    const summary = summarySnap.val() || {};
    const displayName =
      (summary.displayName || candidate.displayName || 'プレイヤー').toString();
    const publicId = (summary.publicId || candidate.publicId || '').toString();
    const currentWinStreak = Math.max(0, candidate.maxWinStreakAfterSwitch);

    updates[`playerRecordSummaries/${candidate.uid}/displayName`] = displayName;
    updates[`playerRecordSummaries/${candidate.uid}/publicId`] = publicId;
    updates[`playerRecordSummaries/${candidate.uid}/ranked/seasonId`] =
      currentSeasonId;
    updates[`playerRecordSummaries/${candidate.uid}/ranked/seasonWins`] =
      candidate.winsAfterSwitch;
    updates[`playerRecordSummaries/${candidate.uid}/ranked/seasonLosses`] =
      candidate.lossesAfterSwitch;
    updates[`playerRecordSummaries/${candidate.uid}/ranked/seasonMatches`] =
      candidate.matchesAfterSwitch;
    updates[`playerRecordSummaries/${candidate.uid}/ranked/seasonMaxWinStreak`] =
      candidate.maxWinStreakAfterSwitch;
    updates[`playerRecordSummaries/${candidate.uid}/ranked/currentRating`] =
      candidate.correctedRating;
    updates[`playerRecordSummaries/${candidate.uid}/ranked/currentWinStreak`] =
      currentWinStreak;
    updates[`playerRecordSummaries/${candidate.uid}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;

    updates[`publicProfiles/${candidate.uid}/displayName`] = displayName;
    updates[`publicProfiles/${candidate.uid}/publicId`] = publicId;
    updates[`publicProfiles/${candidate.uid}/currentRating`] =
      candidate.correctedRating;
    updates[`publicProfiles/${candidate.uid}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;

    updates[`users/${candidate.uid}/name`] = displayName;
    updates[`users/${candidate.uid}/publicId`] = publicId;
    updates[`users/${candidate.uid}/rating`] = candidate.correctedRating;
    updates[`users/${candidate.uid}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;

    updates[
      `rankedSeasons/seasons/${currentSeasonId}/rankings/${candidate.uid}`
    ] = {
      uid: candidate.uid,
      publicId,
      displayName,
      rating: candidate.correctedRating,
      highestEndlessScore: Number(summary?.endless?.highestScore || 0),
      seasonWins: candidate.winsAfterSwitch,
      seasonLosses: candidate.lossesAfterSwitch,
      updatedAt: admin.database.ServerValue.TIMESTAMP,
    };

    updates[`userNotices/${candidate.uid}/${noticeId}`] = {
      enabled: true,
      title: noticeTitle,
      message: noticeMessage,
      platforms: ['all'],
      minBuild: noticeMinBuild,
      publishedAt,
      createdAt: publishedAt,
    };
  }

  const report = candidates.map((candidate) => ({
    uid: candidate.uid,
    displayName: candidate.displayName,
    beforeRating: candidate.beforeRating,
    correctedRating: candidate.correctedRating,
    wins: candidate.winsAfterSwitch,
    losses: candidate.lossesAfterSwitch,
  }));
  console.table(report);
  console.log(`updates=${Object.keys(updates).length} candidates=${candidates.length} apply=${apply}`);

  if (!apply) {
    console.log('Dry run only. Re-run with --apply to write to RTDB.');
    return;
  }
  await db.ref().update(updates);
  console.log('Applied ranked season corrections and personal notices.');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
