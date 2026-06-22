const {onValueCreated} = require('firebase-functions/v2/database');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

admin.initializeApp();

const PLAYER_COUNTS_PATH = 'adminStats/playerCounts';
const PLAYER_SUMMARY_SOURCE_PATH = 'playerRecordSummaries';
const DAILY_WIN_FINALIZATION_PATH = 'adminStats/dailyWinRankFinalizations';
const DAILY_STATS_PATH = 'adminStats/dailyStats';
const DAILY_GLOBAL_STATS_SOURCE_PATH = 'dailyGlobalStats';
const RANKED_BASE_SEASON_ID = '2026-05';
const RANKED_SEASON_END_HOUR_JST = 21;
const RANKED_INITIAL_RATING = 1000;
const RANKED_MIN_LISTED_RATING = 1001;
const RANKED_FINAL_TOP_LIMIT = 100;
const RANKED_FINAL_TOP_SCHEMA_VERSION = 6;
const ROOM_CLEANUP_FINISHED_MAX_AGE_MS = 30 * 60 * 1000;
const ROOM_CLEANUP_WAITING_MAX_AGE_MS = 6 * 60 * 60 * 1000;
const ROOM_CLEANUP_PLAYING_MAX_AGE_MS = 12 * 60 * 60 * 1000;

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
      .filter((entry) => entry.dailyWins > 0 && entry.rating > 0)
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

exports.aggregateDailyPlayerStats = onSchedule(
  {
    schedule: '10 0 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const targetDate = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const dateKey = jstDateKey(targetDate);
    const [summariesSnapshot, globalStatsSnapshot] = await Promise.all([
      admin.database().ref(PLAYER_SUMMARY_SOURCE_PATH).get(),
      admin.database().ref(`${DAILY_GLOBAL_STATS_SOURCE_PATH}/${dateKey}`).get(),
    ]);
    const summaries = isObject(summariesSnapshot.val())
      ? summariesSnapshot.val()
      : {};
    const globalStats = isObject(globalStatsSnapshot.val())
      ? globalStatsSnapshot.val()
      : {};
    const stats = buildDailyStats(dateKey, summaries, globalStats);

    await admin.database().ref(`${DAILY_STATS_PATH}/${dateKey}`).set({
      ...stats,
      generatedAt: admin.database.ServerValue.TIMESTAMP,
      generatedAtTextJst: jstDateTimeText(new Date()),
      sourcePath: DAILY_GLOBAL_STATS_SOURCE_PATH,
    });
    logger.info('Daily player stats aggregated.', {
      dateKey,
      activePlayers: stats.loginPlayers.count,
      registeredPlayers: stats.registeredPlayers.count,
    });
  },
);

exports.maintainRankedSeasonTransition = onSchedule(
  {
    schedule: '*/15 * * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const now = new Date();
    const currentSeasonId = rankedCurrentSeasonId(now);
    const previousSeasonId = rankedPreviousSeasonId(currentSeasonId);
    const transitionRef = admin
      .database()
      .ref(`adminStats/rankedSeasonTransitions/${currentSeasonId}`);
    const transitionSnapshot = await transitionRef.get();
    const transition = isObject(transitionSnapshot.val())
      ? transitionSnapshot.val()
      : {};

    const finalTop100 = await finalizeRankedSeason(previousSeasonId);
    if (transition.resetCompleted === true) {
      const sanitizeStats =
        await sanitizeImpossibleCurrentSeasonRatings(currentSeasonId);
      logger.info('Ranked season transition already reset.', {
        currentSeasonId,
        previousSeasonId,
        ...sanitizeStats,
      });
      return;
    }

    const resetStats = await resetRankedSeason(currentSeasonId);
    await transitionRef.set({
      currentSeasonId,
      previousSeasonId,
      resetCompleted: true,
      resetCompletedAt: admin.database.ServerValue.TIMESTAMP,
      resetCompletedAtTextJst: jstDateTimeText(now),
      previousFinalTopCount: Object.keys(finalTop100).length,
      ...resetStats,
    });
    logger.info('Ranked season transition maintained.', {
      currentSeasonId,
      previousSeasonId,
      previousFinalTopCount: Object.keys(finalTop100).length,
      ...resetStats,
    });
  },
);

exports.cleanupStaleRooms = onSchedule(
  {
    schedule: '*/30 * * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const now = Date.now();
    const snapshot = await admin.database().ref('rooms').get();
    const rooms = isObject(snapshot.val()) ? snapshot.val() : {};
    const updates = {};
    let removedCount = 0;

    for (const [roomId, room] of Object.entries(rooms)) {
      if (!isObject(room)) continue;
      const status = typeof room.status === 'string' ? room.status : '';
      const updatedAt = roomTimestamp(room);
      const ageMs = now - updatedAt;
      const shouldRemove =
        status === 'game_over' ||
        status === 'finished' ||
        status === 'cancelled' ||
        status === 'left'
          ? ageMs >= ROOM_CLEANUP_FINISHED_MAX_AGE_MS
          : status === 'waiting'
            ? ageMs >= ROOM_CLEANUP_WAITING_MAX_AGE_MS
            : ageMs >= ROOM_CLEANUP_PLAYING_MAX_AGE_MS;
      if (shouldRemove) {
        updates[`rooms/${roomId}`] = null;
        removedCount++;
      }
    }

    if (removedCount > 0) {
      await admin.database().ref().update(updates);
    }
    logger.info('Stale rooms cleanup complete.', {removedCount});
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
    combineDuplicateWins: false,
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

async function finalizeRankedSeason(seasonId) {
  const seasonRef = admin.database().ref(`rankedSeasons/seasons/${seasonId}`);
  const snapshot = await seasonRef.get();
  const season = isObject(snapshot.val()) ? snapshot.val() : {};
  if (
    season.finalized === true &&
    season.finalTop100SchemaVersion === RANKED_FINAL_TOP_SCHEMA_VERSION &&
    isObject(season.finalTop100)
  ) {
    return season.finalTop100;
  }

  const rankings = isObject(season.rankings) ? season.rankings : {};
  let entries = rankingEntriesFromMap(rankings);
  if (seasonId === RANKED_BASE_SEASON_ID) {
    const legacySnapshot = await admin.database().ref('rankings/global').get();
    entries = mergeRankingEntries(
      entries,
      rankingEntriesFromMap(legacySnapshot.val()),
    );
  }
  entries = entries
    .filter((entry) => entry.rating >= RANKED_MIN_LISTED_RATING)
    .sort((a, b) => {
      if (b.rating !== a.rating) return b.rating - a.rating;
      return a.updatedAt - b.updatedAt;
    })
    .slice(0, RANKED_FINAL_TOP_LIMIT);

  const finalTop100 = {};
  entries.forEach((entry, index) => {
    const rank = index + 1;
    finalTop100[`rank_${String(rank).padStart(3, '0')}`] = {
      uid: entry.uid,
      publicId: entry.publicId,
      displayName: entry.displayName,
      rating: entry.rating,
      rank,
      updatedAt: entry.updatedAt,
      seasonWins: entry.seasonWins,
      seasonLosses: entry.seasonLosses,
    };
  });

  await seasonRef.update({
    finalTop100,
    finalTop100SchemaVersion: RANKED_FINAL_TOP_SCHEMA_VERSION,
    finalized: true,
    finalizedAt: admin.database.ServerValue.TIMESTAMP,
  });
  return finalTop100;
}

async function resetRankedSeason(currentSeasonId) {
  const [currentSeasonSnapshot, globalSnapshot, summariesSnapshot, lookupSnapshot] =
    await Promise.all([
      admin
        .database()
        .ref(`rankedSeasons/seasons/${currentSeasonId}/rankings`)
        .get(),
      admin.database().ref('rankings/global').get(),
      admin.database().ref(PLAYER_SUMMARY_SOURCE_PATH).get(),
      admin.database().ref('playerNameLookup').get(),
    ]);
  const currentSeasonRankings = isObject(currentSeasonSnapshot.val())
    ? currentSeasonSnapshot.val()
    : {};
  const globalRankings = isObject(globalSnapshot.val())
    ? globalSnapshot.val()
    : {};
  const summaries = isObject(summariesSnapshot.val())
    ? summariesSnapshot.val()
    : {};
  const lookup = isObject(lookupSnapshot.val()) ? lookupSnapshot.val() : {};
  const updates = {};
  const resetUids = new Set([
    ...Object.keys(currentSeasonRankings),
    ...Object.keys(globalRankings),
    ...Object.keys(summaries),
  ]);

  for (const uid of Object.keys(currentSeasonRankings)) {
    updates[
      `rankedSeasons/seasons/${currentSeasonId}/rankings/${uid}/rating`
    ] = RANKED_INITIAL_RATING;
    updates[
      `rankedSeasons/seasons/${currentSeasonId}/rankings/${uid}/seasonWins`
    ] = 0;
    updates[
      `rankedSeasons/seasons/${currentSeasonId}/rankings/${uid}/seasonLosses`
    ] = 0;
    updates[
      `rankedSeasons/seasons/${currentSeasonId}/rankings/${uid}/updatedAt`
    ] = admin.database.ServerValue.TIMESTAMP;
  }
  for (const uid of Object.keys(globalRankings)) {
    updates[`rankings/global/${uid}/rating`] = RANKED_INITIAL_RATING;
    updates[`rankings/global/${uid}/seasonWins`] = 0;
    updates[`rankings/global/${uid}/seasonLosses`] = 0;
    updates[`rankings/global/${uid}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;
  }
  for (const uid of Object.keys(summaries)) {
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/ranked/currentRating`] =
      RANKED_INITIAL_RATING;
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/ranked/seasonId`] =
      currentSeasonId;
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/ranked/seasonWins`] = 0;
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/ranked/seasonLosses`] = 0;
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/ranked/seasonMatches`] = 0;
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;
  }
  for (const [lookupKey, players] of Object.entries(lookup)) {
    if (!isObject(players)) continue;
    for (const uid of Object.keys(players)) {
      if (!resetUids.has(uid)) continue;
      updates[`playerNameLookup/${lookupKey}/${uid}/currentRating`] =
        RANKED_INITIAL_RATING;
      updates[`playerNameLookup/${lookupKey}/${uid}/updatedAt`] =
        admin.database.ServerValue.TIMESTAMP;
    }
  }

  updates['rankedSeasons/currentSeasonId'] = currentSeasonId;
  await admin.database().ref().update(updates);
  return {
    resetCurrentSeasonEntries: Object.keys(currentSeasonRankings).length,
    resetGlobalEntries: Object.keys(globalRankings).length,
    resetSummaryEntries: Object.keys(summaries).length,
  };
}

async function sanitizeImpossibleCurrentSeasonRatings(currentSeasonId) {
  const seasonRankingsRef = admin
    .database()
    .ref(`rankedSeasons/seasons/${currentSeasonId}/rankings`);
  const snapshot = await seasonRankingsRef.get();
  const rankings = isObject(snapshot.val()) ? snapshot.val() : {};
  const staleUids = Object.entries(rankings)
    .filter(([, raw]) => isImpossibleFreshSeasonRating(raw))
    .map(([uid]) => uid);
  if (staleUids.length === 0) {
    return {sanitizedEntries: 0};
  }

  const lookupSnapshot = await admin.database().ref('playerNameLookup').get();
  const lookup = isObject(lookupSnapshot.val()) ? lookupSnapshot.val() : {};
  const updates = {};
  for (const uid of staleUids) {
    updates[
      `rankedSeasons/seasons/${currentSeasonId}/rankings/${uid}/rating`
    ] = RANKED_INITIAL_RATING;
    updates[
      `rankedSeasons/seasons/${currentSeasonId}/rankings/${uid}/seasonWins`
    ] = 0;
    updates[
      `rankedSeasons/seasons/${currentSeasonId}/rankings/${uid}/seasonLosses`
    ] = 0;
    updates[
      `rankedSeasons/seasons/${currentSeasonId}/rankings/${uid}/updatedAt`
    ] = admin.database.ServerValue.TIMESTAMP;
    updates[`rankings/global/${uid}/rating`] = RANKED_INITIAL_RATING;
    updates[`rankings/global/${uid}/seasonWins`] = 0;
    updates[`rankings/global/${uid}/seasonLosses`] = 0;
    updates[`rankings/global/${uid}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/ranked/currentRating`] =
      RANKED_INITIAL_RATING;
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/ranked/seasonId`] =
      currentSeasonId;
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/ranked/seasonWins`] = 0;
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/ranked/seasonLosses`] = 0;
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/ranked/seasonMatches`] = 0;
    updates[`${PLAYER_SUMMARY_SOURCE_PATH}/${uid}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;
  }
  for (const [lookupKey, players] of Object.entries(lookup)) {
    if (!isObject(players)) continue;
    for (const uid of staleUids) {
      if (!isObject(players[uid])) continue;
      updates[`playerNameLookup/${lookupKey}/${uid}/currentRating`] =
        RANKED_INITIAL_RATING;
      updates[`playerNameLookup/${lookupKey}/${uid}/updatedAt`] =
        admin.database.ServerValue.TIMESTAMP;
    }
  }
  await admin.database().ref().update(updates);
  return {sanitizedEntries: staleUids.length};
}

function isImpossibleFreshSeasonRating(raw) {
  if (!isObject(raw)) return false;
  const rating = numberValue(raw.rating);
  const wins = numberValue(raw.seasonWins);
  const losses = numberValue(raw.seasonLosses);
  const maxReachable = RANKED_INITIAL_RATING + wins * 95 - losses * 5;
  const minReachable = RANKED_INITIAL_RATING + wins * 5 - losses * 95;
  return rating > maxReachable || rating < minReachable;
}

function rankingEntriesFromMap(raw) {
  if (!isObject(raw)) return [];
  return Object.entries(raw)
    .filter(([, value]) => isObject(value))
    .map(([uid, value]) => normalizedSeasonRankingEntry(uid, value));
}

function normalizedSeasonRankingEntry(uid, raw) {
  return {
    uid: typeof raw.uid === 'string' && raw.uid.trim() ? raw.uid : uid,
    publicId: typeof raw.publicId === 'string' ? raw.publicId : '',
    displayName:
      typeof raw.displayName === 'string' && raw.displayName.trim()
        ? raw.displayName.trim()
        : typeof raw.name === 'string' && raw.name.trim()
          ? raw.name.trim()
          : 'Player',
    rating: numberValue(raw.rating),
    updatedAt: numberValue(raw.updatedAt),
    seasonWins: numberValue(raw.seasonWins),
    seasonLosses: numberValue(raw.seasonLosses),
  };
}

function mergeRankingEntries(primary, fallback) {
  const merged = new Map();
  for (const entry of [...primary, ...fallback]) {
    const key = entry.publicId ? `public:${entry.publicId}` : entry.uid;
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

function buildDailyStats(dateKey, summaries, globalStats = {}) {
  const registeredPlayers = [];
  const activePlayers = isObject(globalStats.activePlayers)
    ? Object.values(globalStats.activePlayers).filter(isObject)
    : [];
  const totals = isObject(globalStats.totals) ? globalStats.totals : {};
  const chains = isObject(globalStats.chains) ? globalStats.chains : {};
  const endless = isObject(globalStats.endless) ? globalStats.endless : {};
  const ranked = isObject(globalStats.ranked) ? globalStats.ranked : {};
  const modePlayCounts = intMap(globalStats.modePlayCounts);
  const formationCounts = intMap(globalStats.formationCounts);
  const dailyEconomy = isObject(globalStats.economy)
    ? intMap(globalStats.economy)
    : {};
  const economy = {
    coinsEarned: numberValue(dailyEconomy.coinsEarned),
    coinsSpent: numberValue(dailyEconomy.coinsSpent),
    netCoins: numberValue(dailyEconomy.netCoins),
    expEarned: numberValue(dailyEconomy.expEarned),
  };
  const holdings = {
    totalCoinsHeld: 0,
    totalExpHeld: 0,
    adsRemovedPlayers: 0,
  };

  for (const [uid, summary] of Object.entries(summaries)) {
    if (!isObject(summary)) continue;
    const profile = isObject(summary.profile) ? summary.profile : {};
    const overall = isObject(summary.overall) ? summary.overall : {};
    const name =
      typeof profile.displayName === 'string' && profile.displayName.trim()
        ? profile.displayName.trim()
        : typeof summary.displayName === 'string' && summary.displayName.trim()
          ? summary.displayName.trim()
          : 'Player';
    const publicId =
      typeof profile.publicId === 'string' ? profile.publicId : '';
    const player = {uid, name, publicId};

    if (accountCreatedDateKey(summary) === dateKey) {
      registeredPlayers.push(player);
    }

    const eco = isObject(summary.economy) ? summary.economy : {};
    holdings.totalCoinsHeld += numberValue(eco.coins);
    holdings.totalExpHeld += numberValue(eco.exp);
    if (eco.adsRemoved === true) {
      holdings.adsRemovedPlayers++;
    }
  }

  return {
    date: dateKey,
    registeredPlayers: {
      count: registeredPlayers.length,
      players: registeredPlayers,
    },
    loginPlayers: {
      count: activePlayers.length,
      players: activePlayers,
    },
    modePlayCounts,
    formationCounts,
    results: {
      totalMatches: numberValue(totals.matches),
      totalWins: numberValue(totals.wins),
      totalLosses: numberValue(totals.losses),
      totalClearedBalls: numberValue(totals.clearedBalls),
      totalNormalClearedBalls: numberValue(totals.normalClearedBalls),
      totalMaxChain: numberValue(chains.totalMaxChain),
      endlessPlayCount: numberValue(endless.playCount),
      endlessScoreTotal: numberValue(endless.scoreTotal),
    },
    ranked: {
      matches: numberValue(ranked.matches),
      wins: numberValue(ranked.wins),
      losses: numberValue(ranked.losses),
      ratingDelta: numberValue(ranked.ratingDelta),
    },
    economy,
    holdings,
  };
}

function intMap(value) {
  if (!isObject(value)) return {};
  return Object.fromEntries(
    Object.entries(value).map(([key, raw]) => [key, numberValue(raw)]),
  );
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

function rankedCurrentSeasonId(date) {
  const wall = jstWallClockDate(date);
  const year = wall.getUTCFullYear();
  const month = wall.getUTCMonth() + 1;
  const end = Date.UTC(
    year,
    month - 1,
    lastDayOfMonth(year, month),
    RANKED_SEASON_END_HOUR_JST,
  );
  if (wall.getTime() < end) {
    return formatSeasonId(year, month);
  }
  return month === 12 ? formatSeasonId(year + 1, 1) : formatSeasonId(year, month + 1);
}

function rankedPreviousSeasonId(seasonId) {
  const match = /^(\d{4})-(\d{2})$/.exec(seasonId);
  if (!match) return RANKED_BASE_SEASON_ID;
  const year = Number.parseInt(match[1], 10);
  const month = Number.parseInt(match[2], 10);
  return month === 1 ? formatSeasonId(year - 1, 12) : formatSeasonId(year, month - 1);
}

function jstWallClockDate(date) {
  return new Date(date.getTime() + 9 * 60 * 60 * 1000);
}

function lastDayOfMonth(year, month) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function formatSeasonId(year, month) {
  return `${year}-${String(month).padStart(2, '0')}`;
}

function numberValue(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  const parsed = Number.parseInt(`${value}`, 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function roomTimestamp(room) {
  const candidates = [
    room.updatedAt,
    room.resultKnownAt,
    room.startedAt,
    room.createdAt,
    room.matchmaking?.timestamp,
  ];
  for (const candidate of candidates) {
    const value = numberValue(candidate);
    if (value > 0) {
      return value;
    }
  }
  return 0;
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
