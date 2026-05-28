const {onValueCreated} = require('firebase-functions/v2/database');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

admin.initializeApp();

const PLAYER_COUNTS_PATH = 'adminStats/playerCounts';
const PLAYER_SUMMARY_SOURCE_PATH = 'playerRecordSummaries';
const DAILY_WIN_FINALIZATION_PATH = 'adminStats/dailyWinRankFinalizations';

exports.updatePlayerCountsOnSummaryCreate = onValueCreated(
  {
    ref: '/playerRecordSummaries/{uid}',
    region: 'asia-southeast1',
  },
  async (event) => {
    const summary = event.data.val() || {};
    const now = new Date();
    const todayKeyJst = jstDateKey(now);
    const createdKeyJst = accountCreatedDateKey(summary) || todayKeyJst;
    const uid = event.params.uid || '';

    const countsRef = admin.database().ref(PLAYER_COUNTS_PATH);
    await countsRef.transaction((current) => {
      const previous = isObject(current) ? current : {};
      const previousTodayKey =
        typeof previous.todayKeyJst === 'string' ? previous.todayKeyJst : '';
      const totalPlayers = numberValue(previous.totalPlayers) + 1;
      const baseTodayNewPlayers =
        previousTodayKey === todayKeyJst
          ? numberValue(previous.todayNewPlayers)
          : 0;
      const todayNewPlayers = baseTodayNewPlayers + 1;

      return {
        ...previous,
        totalPlayers,
        todayNewPlayers,
        todayKeyJst,
        sourcePath: PLAYER_SUMMARY_SOURCE_PATH,
        updatedAt: admin.database.ServerValue.TIMESTAMP,
        updatedAtTextJst: jstDateTimeText(now),
      };
    });

    logger.info('Player count stats updated.', {
      uid,
      todayKeyJst,
      createdKeyJst,
    });
  },
);

exports.finalizeDailyWinRankPlacements = onSchedule(
  {
    schedule: '5 0 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const targetDate = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const dateKey = jstDateKey(targetDate);
    const finalizationRef = admin
      .database()
      .ref(`${DAILY_WIN_FINALIZATION_PATH}/${dateKey}`);
    const finalizationSnapshot = await finalizationRef.get();
    if (finalizationSnapshot.exists()) {
      logger.info('Daily win rank placements already finalized.', {dateKey});
      return;
    }

    const entries = await dailyWinEntriesForDate(dateKey);
    const rankedEntries = entries
      .filter((entry) => entry.dailyWins > 0 && entry.rating >= 1001)
      .sort((a, b) => {
        if (b.dailyWins !== a.dailyWins) return b.dailyWins - a.dailyWins;
        return b.rating - a.rating;
      });

    if (rankedEntries.length === 0) {
      await finalizationRef.set({
        finalizedAt: admin.database.ServerValue.TIMESTAMP,
        targetDate: dateKey,
        winnerCount: 0,
      });
      logger.info('No daily win rankings to finalize.', {dateKey});
      return;
    }

    const updates = {};
    let winnerCount = 0;
    let previousWins = null;
    let displayRank = 0;
    for (let i = 0; i < rankedEntries.length && i < 100; i++) {
      const entry = rankedEntries[i];
      if (previousWins === null || entry.dailyWins !== previousWins) {
        displayRank = i + 1;
        previousWins = entry.dailyWins;
      }
      const rankLabel = `${displayRank}位`;
      updates[
        `playerRecordSummaries/${entry.uid}/ranked/dailyWinRankPlacements/${rankLabel}`
      ] = admin.database.ServerValue.increment(1);
      updates[`playerRecordSummaries/${entry.uid}/updatedAt`] =
        admin.database.ServerValue.TIMESTAMP;
      if (displayRank === 1) {
        winnerCount++;
      }
    }

    updates[`${DAILY_WIN_FINALIZATION_PATH}/${dateKey}`] = {
      finalizedAt: admin.database.ServerValue.TIMESTAMP,
      targetDate: dateKey,
      entryCount: Math.min(rankedEntries.length, 100),
      winnerCount,
    };
    await admin.database().ref().update(updates);
    logger.info('Daily win rank placements finalized.', {
      dateKey,
      entryCount: Math.min(rankedEntries.length, 100),
      winnerCount,
    });
  },
);

async function dailyWinEntriesForDate(dateKey) {
  const snapshots = await Promise.all([
    admin.database().ref('rankedSeasons/seasons').get(),
    admin.database().ref('rankings/global').get(),
  ]);
  const seasonRoot = isObject(snapshots[0].val()) ? snapshots[0].val() : {};
  const legacyRoot = isObject(snapshots[1].val()) ? snapshots[1].val() : {};
  const seasonEntries = [];

  for (const [seasonId, seasonData] of Object.entries(seasonRoot)) {
    const rankings = isObject(seasonData?.rankings)
      ? seasonData.rankings
      : {};
    for (const [uid, raw] of Object.entries(rankings)) {
      appendDailyEntry(seasonEntries, uid, raw, dateKey);
    }
  }

  const seasonMerged = mergeDailyEntries(seasonEntries, {
    combineDuplicateWins: true,
  });
  const legacyEntries = [];
  for (const [uid, raw] of Object.entries(legacyRoot)) {
    appendDailyEntry(legacyEntries, uid, raw, dateKey);
  }
  const legacyMerged = mergeDailyEntries(legacyEntries, {
    combineDuplicateWins: false,
  });
  const merged = new Map(seasonMerged);
  for (const [key, entry] of legacyMerged.entries()) {
    if (!merged.has(key)) {
      merged.set(key, entry);
    }
  }
  return [...merged.values()];
}

function appendDailyEntry(entries, uid, raw, dateKey) {
  if (!isObject(raw)) return;
  if (raw.dailyWinDate === dateKey && numberValue(raw.dailyWins) > 0) {
    entries.push(normalizedRankingEntry(uid, raw, raw.dailyWins, dateKey));
  }
  if (
    raw.previousDailyWinDate === dateKey &&
    numberValue(raw.previousDailyWins) > 0
  ) {
    entries.push(
      normalizedRankingEntry(uid, raw, raw.previousDailyWins, dateKey),
    );
  }
}

function normalizedRankingEntry(uid, raw, dailyWins, dateKey) {
  return {
    uid: typeof raw.uid === 'string' && raw.uid.trim() ? raw.uid : uid,
    publicId: typeof raw.publicId === 'string' ? raw.publicId : '',
    displayName:
      typeof raw.displayName === 'string' && raw.displayName.trim()
        ? raw.displayName
        : typeof raw.name === 'string' && raw.name.trim()
          ? raw.name
          : 'Player',
    rating: numberValue(raw.rating),
    dailyWins: numberValue(dailyWins),
    dailyWinDate: dateKey,
    updatedAt: numberValue(raw.updatedAt),
  };
}

function mergeDailyEntries(entries, {combineDuplicateWins}) {
  const merged = new Map();
  for (const entry of entries) {
    const key = entry.publicId ? `public:${entry.publicId}` : entry.uid;
    const previous = merged.get(key);
    if (!previous) {
      merged.set(key, entry);
      continue;
    }
    const newer = entry.updatedAt >= previous.updatedAt ? entry : previous;
    merged.set(key, {
      ...newer,
      rating: Math.max(previous.rating, entry.rating),
      dailyWins: combineDuplicateWins
        ? previous.dailyWins + entry.dailyWins
        : Math.max(previous.dailyWins, entry.dailyWins),
    });
  }
  return merged;
}

function accountCreatedDateKey(summary) {
  const raw = summary?.overall?.accountCreatedAt;
  if (typeof raw !== 'string' || raw.trim() === '') {
    return null;
  }
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }
  return jstDateKey(parsed);
}

function jstDateKey(date) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Tokyo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

function jstDateTimeText(date) {
  return (
    new Intl.DateTimeFormat('sv-SE', {
      timeZone: 'Asia/Tokyo',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    })
      .format(date)
      .replace(' ', 'T') + '+09:00'
  );
}

function numberValue(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  const parsed = Number.parseInt(`${value}`, 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
