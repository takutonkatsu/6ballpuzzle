const {onValueCreated, onValueWritten} = require('firebase-functions/v2/database');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

admin.initializeApp();

const PLAYER_COUNTS_PATH = 'adminStats/playerCounts';
const PLAYER_SUMMARY_SOURCE_PATH = 'playerRecordSummaries';
const DAILY_WIN_FINALIZATION_PATH = 'adminStats/dailyWinRankFinalizations';
const DAILY_CHALLENGE_FINALIZATION_PATH =
  'adminStats/dailyChallengeRankFinalizations';
const DAILY_STATS_PATH = 'adminStats/dailyStats';
const DAILY_RAW_STATS_PATH = 'adminStats/dailyRawStats';
const LEGACY_DAILY_GLOBAL_STATS_SOURCE_PATH = 'dailyGlobalStats';
const ADMIN_GRANT_EXPIRATIONS_PATH = 'adminGrantExpirations';
const RANKED_BASE_SEASON_ID = '2026-05';
const RANKED_SEASON_END_HOUR_JST = 21;
const RANKED_INITIAL_RATING = 1000;
const RANKED_MIN_LISTED_RATING = 1001;
const RANKED_FINAL_TOP_LIMIT = 100;
const RANKED_FINAL_TOP_SCHEMA_VERSION = 6;
const ENDLESS_SEASON_SWITCH_WEEKDAY_JST = 1;
const ENDLESS_SEASON_SWITCH_HOUR_JST = 21;
const ENDLESS_FINAL_TOP_LIMIT = 100;
const ENDLESS_FINAL_TOP_SCHEMA_VERSION = 1;
const RANKED_REWARD_LIMIT = 100;
const ENDLESS_REWARD_LIMIT = 50;
const DAILY_WIN_REWARD_LIMIT = 10;
const DAILY_CHALLENGE_REWARD_LIMIT = 10;
const ROOM_CLEANUP_FINISHED_MAX_AGE_MS = 30 * 60 * 1000;
const ROOM_CLEANUP_WAITING_MAX_AGE_MS = 6 * 60 * 60 * 1000;
const ROOM_CLEANUP_PLAYING_MAX_AGE_MS = 12 * 60 * 60 * 1000;
const MATCHMAKING_CLEANUP_MAX_AGE_MS = 3 * 60 * 1000;
const GAME_ACTIVITY_CLEANUP_MAX_AGE_MS = 60 * 60 * 1000;
const SERVER_TIME_PING_CLEANUP_DAYS = 2;
const INVITE_REWARD_COINS = 50000;
const INVITE_ELIGIBLE_AUTH_CREATED_AFTER_MS = Date.parse('2026-06-22T15:00:00.000Z');
const INVITE_CODE_CLEANUP_GRACE_MS = 2 * 24 * 60 * 60 * 1000;
const JST_OFFSET_MS = 9 * 60 * 60 * 1000;

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
    await admin
      .database()
      .ref(`${DAILY_RAW_STATS_PATH}/${createdKeyJst}`)
      .update({
        date: createdKeyJst,
        updatedAt: admin.database.ServerValue.TIMESTAMP,
        [`registeredPlayers/${uid}/uid`]: uid,
        [`registeredPlayers/${uid}/publicId`]:
          typeof summary?.profile?.publicId === 'string' ? summary.profile.publicId : '',
        [`registeredPlayers/${uid}/displayName`]:
          typeof summary?.profile?.displayName === 'string' &&
          summary.profile.displayName.trim()
            ? summary.profile.displayName.trim()
            : typeof summary?.displayName === 'string' && summary.displayName.trim()
              ? summary.displayName.trim()
              : 'Player',
        [`registeredPlayers/${uid}/createdAt`]: admin.database.ServerValue.TIMESTAMP,
      })
      .catch((error) => {
        logger.warn('Failed to append registered player daily stats.', {
          uid,
          createdKeyJst,
          error,
        });
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
    const checkedDateKeys = [];
    let finalizedCount = 0;
    for (const daysAgo of [1, 2, 3]) {
      const targetDate = new Date(Date.now() - daysAgo * 24 * 60 * 60 * 1000);
      const dateKey = jstDateKey(targetDate);
      checkedDateKeys.push(dateKey);
      if (await finalizeDailyWinRankPlacementsForDate(dateKey)) {
        finalizedCount++;
      }
    }
    logger.info('Daily win rank placement sweep complete.', {
      checkedDateKeys,
      finalizedCount,
    });
  },
);

exports.finalizeDailyChallengeRankRewards = onSchedule(
  {
    schedule: '8 0 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const checkedDateKeys = [];
    let finalizedCount = 0;
    for (const daysAgo of [1, 2, 3]) {
      const targetDate = new Date(Date.now() - daysAgo * 24 * 60 * 60 * 1000);
      const dateKey = jstDateKey(targetDate);
      checkedDateKeys.push(dateKey);
      if (await finalizeDailyChallengeRankRewardsForDate(dateKey)) {
        finalizedCount++;
      }
    }
    logger.info('Daily challenge rank reward sweep complete.', {
      checkedDateKeys,
      finalizedCount,
    });
  },
);

async function finalizeDailyWinRankPlacementsForDate(dateKey) {
  const finalizationRef = admin
    .database()
    .ref(`${DAILY_WIN_FINALIZATION_PATH}/${dateKey}`);
  const finalizationSnapshot = await finalizationRef.get();
  if (finalizationSnapshot.exists()) {
    logger.info('Daily win rank placements already finalized.', {dateKey});
    return false;
  }

  const entries = await dailyWinEntriesForDate(dateKey);
  const rankedEntries = entries
    .filter((entry) => entry.dailyWins > 0)
    .sort((a, b) => {
      if (b.dailyWins !== a.dailyWins) return b.dailyWins - a.dailyWins;
      return b.rating - a.rating;
    });

  if (rankedEntries.length === 0) {
    logger.info('No daily win rankings to finalize yet.', {dateKey});
    return false;
  }

  const updates = {};
  let winnerCount = 0;
  let previousWins = null;
  let displayRank = 0;
  const rewardCandidates = [];
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
    if (displayRank <= DAILY_WIN_REWARD_LIMIT) {
      const coins = dailyWinRankingRewardCoins(displayRank);
      if (coins > 0) {
        rewardCandidates.push({
          uid: entry.uid,
          publicId: entry.publicId,
          displayName: entry.displayName,
          rank: displayRank,
          dailyWins: entry.dailyWins,
          coins,
        });
        Object.assign(
          updates,
          adminGrantWriteUpdates(
            entry.uid,
            `daily_win_${dateKey}`,
            rankingRewardGrant({
              type: 'daily_win_ranking_reward',
              title: '今日の勝利数ランキング報酬',
              message:
                `今日の勝利数ランキング ${japaneseDateLabel(dateKey)} ` +
                `${displayRank}位報酬として ` +
                `${coins.toLocaleString('ja-JP')} コインを受け取れます。`,
              coins,
              rank: displayRank,
              seasonId: dateKey,
              expiresAt: dailyWinRewardExpiresAt(dateKey),
            }),
          ),
        );
      }
    }
  }

  updates[`${DAILY_WIN_FINALIZATION_PATH}/${dateKey}`] = {
    finalizedAt: admin.database.ServerValue.TIMESTAMP,
    targetDate: dateKey,
    entryCount: Math.min(rankedEntries.length, 100),
    winnerCount,
    rewardCandidates,
  };
  await admin.database().ref().update(updates);
  logger.info('Daily win rank placements finalized.', {
    dateKey,
    entryCount: Math.min(rankedEntries.length, 100),
    winnerCount,
  });
  return true;
}

async function finalizeDailyChallengeRankRewardsForDate(dateKey) {
  const finalizationRef = admin
    .database()
    .ref(`${DAILY_CHALLENGE_FINALIZATION_PATH}/${dateKey}`);
  const finalizationSnapshot = await finalizationRef.get();
  if (finalizationSnapshot.exists()) {
    logger.info('Daily challenge rewards already finalized.', {dateKey});
    return false;
  }

  const rankingsSnapshot = await admin
    .database()
    .ref(`dailyChallengeRankings/${dateKey}`)
    .orderByChild('score')
    .limitToLast(100)
    .get();
  const entries = dailyChallengeEntriesFromMap(rankingsSnapshot.val())
    .filter((entry) => entry.score > 0)
    .sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return a.updatedAt - b.updatedAt;
    });

  if (entries.length === 0) {
    logger.info('No daily challenge rankings to finalize yet.', {dateKey});
    return false;
  }

  const updates = {};
  let previousScore = null;
  let displayRank = 0;
  const rewardCandidates = [];
  for (let i = 0; i < entries.length && i < 100; i++) {
    const entry = entries[i];
    if (previousScore === null || entry.score !== previousScore) {
      displayRank = i + 1;
      previousScore = entry.score;
    }
    if (displayRank > DAILY_CHALLENGE_REWARD_LIMIT) {
      continue;
    }
    const coins = dailyWinRankingRewardCoins(displayRank);
    if (coins <= 0 || !entry.uid) {
      continue;
    }
    rewardCandidates.push({
      uid: entry.uid,
      publicId: entry.publicId,
      displayName: entry.displayName,
      rank: displayRank,
      score: entry.score,
      coins,
    });
    Object.assign(
      updates,
      adminGrantWriteUpdates(
        entry.uid,
        `daily_challenge_${dateKey}`,
        rankingRewardGrant({
          type: 'daily_challenge_ranking_reward',
          title: 'デイリーランキング報酬',
          message:
            `デイリーランキング ${japaneseDateLabel(dateKey)} ` +
            `${displayRank}位報酬として ` +
            `${coins.toLocaleString('ja-JP')} コインを受け取れます。`,
          coins,
          rank: displayRank,
          seasonId: dateKey,
          expiresAt: dailyWinRewardExpiresAt(dateKey),
        }),
      ),
    );
  }

  updates[`${DAILY_CHALLENGE_FINALIZATION_PATH}/${dateKey}`] = {
    finalizedAt: admin.database.ServerValue.TIMESTAMP,
    targetDate: dateKey,
    entryCount: Math.min(entries.length, 100),
    rewardCandidates,
  };
  await admin.database().ref().update(updates);
  logger.info('Daily challenge rank rewards finalized.', {
    dateKey,
    entryCount: Math.min(entries.length, 100),
    rewardCount: rewardCandidates.length,
  });
  return true;
}

exports.aggregateDailyPlayerStats = onSchedule(
  {
    schedule: '10 0 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const targetDate = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const dateKey = jstDateKey(targetDate);
    const [playerCountsSnapshot, rawStatsSnapshot, legacyStatsSnapshot] =
      await Promise.all([
      admin.database().ref(PLAYER_COUNTS_PATH).get(),
      admin.database().ref(`${DAILY_RAW_STATS_PATH}/${dateKey}`).get(),
      admin
        .database()
        .ref(`${LEGACY_DAILY_GLOBAL_STATS_SOURCE_PATH}/${dateKey}`)
        .get(),
    ]);
    const playerCounts = isObject(playerCountsSnapshot.val())
      ? playerCountsSnapshot.val()
      : {};
    const rawStats = isObject(rawStatsSnapshot.val()) ? rawStatsSnapshot.val() : {};
    const legacyStats = isObject(legacyStatsSnapshot.val())
      ? legacyStatsSnapshot.val()
      : {};
    const stats = buildDailyStats(
      dateKey,
      mergeDailyRawStats(rawStats, legacyStats),
      playerCounts,
    );

    await admin.database().ref(`${DAILY_STATS_PATH}/${dateKey}`).set({
      ...stats,
      generatedAt: admin.database.ServerValue.TIMESTAMP,
      generatedAtTextJst: jstDateTimeText(new Date()),
      sourcePath: DAILY_RAW_STATS_PATH,
      legacySourcePath: LEGACY_DAILY_GLOBAL_STATS_SOURCE_PATH,
    });
    logger.info('Daily player stats aggregated.', {
      dateKey,
      activePlayers: stats.loginPlayers.count,
      registeredPlayers: stats.registeredPlayers.count,
      skippedFullPlayerSummaryScan: true,
    });
  },
);

exports.cleanupExpiredAdminGrants = onSchedule(
  {
    schedule: '17 3 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const now = Date.now();
    const snapshot = await admin
      .database()
      .ref(ADMIN_GRANT_EXPIRATIONS_PATH)
      .orderByChild('expiresAt')
      .endAt(now)
      .limitToFirst(1000)
      .get();
    const indexedGrants = isObject(snapshot.val()) ? snapshot.val() : {};
    const updates = {};
    let expiredCount = 0;
    let checkedCount = 0;
    for (const [indexKey, indexEntry] of Object.entries(indexedGrants)) {
      checkedCount++;
      if (!isObject(indexEntry)) {
        updates[`${ADMIN_GRANT_EXPIRATIONS_PATH}/${indexKey}`] = null;
        continue;
      }
      const uid = typeof indexEntry.uid === 'string' ? indexEntry.uid : '';
      const grantId =
        typeof indexEntry.grantId === 'string' ? indexEntry.grantId : '';
      const indexedExpiresAt = numberValue(indexEntry.expiresAt);
      if (!uid || !grantId || indexedExpiresAt <= 0) {
        updates[`${ADMIN_GRANT_EXPIRATIONS_PATH}/${indexKey}`] = null;
        continue;
      }
      const grantSnapshot = await admin
        .database()
        .ref(`adminGrants/${uid}/${grantId}`)
        .get();
      const grant = grantSnapshot.val();
      const expiresAt = isObject(grant)
        ? numberValue(grant.expiresAt)
        : indexedExpiresAt;
      if (!isObject(grant) || (expiresAt > 0 && expiresAt <= now)) {
        if (isObject(grant)) {
          updates[`expiredAdminGrants/${uid}/${grantId}`] = {
            grantId,
            uid,
            type: typeof grant.type === 'string' ? grant.type : '',
            title: typeof grant.title === 'string' ? grant.title : '',
            message: typeof grant.message === 'string' ? grant.message : '',
            coins: numberValue(grant.coins),
            rank: numberValue(grant.rank),
            seasonId: typeof grant.seasonId === 'string' ? grant.seasonId : '',
            createdAt: numberValue(grant.createdAt),
            expiresAt,
            expiredAt: admin.database.ServerValue.TIMESTAMP,
            expiredAtTextJst: jstDateTimeText(new Date(now)),
          };
        }
        updates[`adminGrants/${uid}/${grantId}`] = null;
        updates[`${ADMIN_GRANT_EXPIRATIONS_PATH}/${indexKey}`] = null;
        expiredCount++;
      }
    }
    updates[`adminStats/adminGrantExpirationCleanups/${jstDateKey(new Date(now))}`] = {
      cleanedAt: admin.database.ServerValue.TIMESTAMP,
      checkedCount,
      expiredCount,
    };
    if (Object.keys(updates).length > 0) {
      await admin.database().ref().update(updates);
    }
    logger.info('Expired admin grants cleanup complete.', {
      checkedCount,
      expiredCount,
    });
  },
);

exports.cleanupDailyRawStats = onSchedule(
  {
    schedule: '37 3 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const cutoffKey = jstDateKey(new Date(Date.now() - 2 * 24 * 60 * 60 * 1000));
    const updates = {};
    let removedCount = 0;
    for (const rootPath of [DAILY_RAW_STATS_PATH, LEGACY_DAILY_GLOBAL_STATS_SOURCE_PATH]) {
      const snapshot = await admin
        .database()
        .ref(rootPath)
        .orderByKey()
        .endAt(cutoffKey)
        .limitToFirst(500)
        .get();
      const days = isObject(snapshot.val()) ? snapshot.val() : {};
      for (const dateKey of Object.keys(days)) {
        if (/^\d{4}-\d{2}-\d{2}$/.test(dateKey) && dateKey <= cutoffKey) {
          updates[`${rootPath}/${dateKey}`] = null;
          removedCount++;
        }
      }
    }
    if (removedCount > 0) {
      await admin.database().ref().update(updates);
    }
    logger.info('Daily raw stats cleanup complete.', {cutoffKey, removedCount});
  },
);

exports.cleanupExpiredInviteCodes = onSchedule(
  {
    schedule: '47 3 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const now = Date.now();
    const cutoff = now - INVITE_CODE_CLEANUP_GRACE_MS;
    const inviteCodesRef = admin.database().ref('inviteCodes');
    let removedCount = 0;
    let checkedCount = 0;

    for (let page = 0; page < 20; page++) {
      const snapshot = await inviteCodesRef
        .orderByChild('expiresAt')
        .endAt(cutoff)
        .limitToFirst(500)
        .get();
      const codes = isObject(snapshot.val()) ? snapshot.val() : {};
      const updates = {};
      for (const [code, value] of Object.entries(codes)) {
        checkedCount++;
        if (!isObject(value)) continue;
        const expiresAt = numberValue(value.expiresAt);
        const fallbackUpdatedAt =
          numberValue(value.updatedAt) || numberValue(value.createdAt);
        const isExpired = expiresAt > 0 && expiresAt <= cutoff;
        const isLegacyExpired =
          expiresAt <= 0 && (fallbackUpdatedAt <= 0 || fallbackUpdatedAt <= cutoff);
        if (isExpired || isLegacyExpired) {
          updates[code] = null;
          removedCount++;
        }
      }
      if (Object.keys(updates).length === 0) {
        break;
      }
      await inviteCodesRef.update(updates);
      if (Object.keys(codes).length < 500) {
        break;
      }
    }

    logger.info('Expired invite codes cleanup complete.', {
      checkedCount,
      removedCount,
      cutoff,
    });
  },
);

exports.cleanupPresenceAndServerTimePings = onSchedule(
  {
    schedule: '57 3 * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const now = Date.now();
    const staleActivityCutoff = now - GAME_ACTIVITY_CLEANUP_MAX_AGE_MS;
    const stalePingCutoff =
      jstStartOfDayMillis(now) -
      (SERVER_TIME_PING_CLEANUP_DAYS - 1) * 24 * 60 * 60 * 1000;
    const [activitySnapshot, pingsSnapshot] = await Promise.all([
      admin
        .database()
        .ref('realtimeGameActivity')
        .orderByChild('enteredAt')
        .endAt(staleActivityCutoff)
        .limitToFirst(1000)
        .get(),
      admin
        .database()
        .ref('serverTimePings')
        .orderByChild('current/timestamp')
        .endAt(stalePingCutoff - 1)
        .limitToFirst(1000)
        .get(),
    ]);
    const activities = isObject(activitySnapshot.val())
      ? activitySnapshot.val()
      : {};
    const pings = isObject(pingsSnapshot.val()) ? pingsSnapshot.val() : {};
    const updates = {};
    let removedActivityCount = 0;
    let removedPingCount = 0;

    for (const [uid, activity] of Object.entries(activities)) {
      if (!isObject(activity)) continue;
      const enteredAt = numberValue(activity.enteredAt);
      if (enteredAt > 0 && enteredAt <= staleActivityCutoff) {
        updates[`realtimeGameActivity/${uid}`] = null;
        removedActivityCount++;
      }
    }

    for (const [uid, ping] of Object.entries(pings)) {
      if (!isObject(ping)) continue;
      const current = isObject(ping.current) ? ping.current : {};
      const timestamp = numberValue(current.timestamp);
      if (timestamp > 0 && timestamp < stalePingCutoff) {
        updates[`serverTimePings/${uid}`] = null;
        removedPingCount++;
      }
    }

    if (removedActivityCount > 0 || removedPingCount > 0) {
      await admin.database().ref().update(updates);
    }
    logger.info('Presence and server time pings cleanup complete.', {
      staleActivityCutoff,
      stalePingCutoff,
      removedActivityCount,
      removedPingCount,
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

exports.maintainEndlessSeasonTransition = onSchedule(
  {
    schedule: '*/15 * * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const now = new Date();
    const currentSeasonId = endlessCurrentSeasonId(now);
    const previousSeasonId = endlessPreviousSeasonId(currentSeasonId);
    const transitionRef = admin
      .database()
      .ref(`adminStats/endlessSeasonTransitions/${currentSeasonId}`);
    const transitionSnapshot = await transitionRef.get();
    const transition = isObject(transitionSnapshot.val())
      ? transitionSnapshot.val()
      : {};

    const [finalTop100, seedStats] = await Promise.all([
      finalizeEndlessSeason(previousSeasonId),
      seedCurrentEndlessSeasonRankings(currentSeasonId),
    ]);
    await admin.database().ref('endlessSeasons/currentSeasonId').set(currentSeasonId);
    if (transition.finalized === true) {
      logger.info('Endless season transition already finalized.', {
        currentSeasonId,
        previousSeasonId,
        previousFinalTopCount: Object.keys(finalTop100).length,
        ...seedStats,
      });
      return;
    }

    await transitionRef.set({
      currentSeasonId,
      previousSeasonId,
      finalized: true,
      finalizedAt: admin.database.ServerValue.TIMESTAMP,
      finalizedAtTextJst: jstDateTimeText(now),
      previousFinalTopCount: Object.keys(finalTop100).length,
      ...seedStats,
    });
    logger.info('Endless season transition maintained.', {
      currentSeasonId,
      previousSeasonId,
      previousFinalTopCount: Object.keys(finalTop100).length,
      ...seedStats,
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
    const candidateCutoff = now - ROOM_CLEANUP_FINISHED_MAX_AGE_MS;
    const rooms = await fetchCandidateChildrenByCutoffs('rooms', [
      ['updatedAt', candidateCutoff],
      ['resultKnownAt', candidateCutoff],
      ['startedAt', candidateCutoff],
      ['createdAt', candidateCutoff],
      ['matchmaking/timestamp', candidateCutoff],
    ]);
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
    logger.info('Stale rooms cleanup complete.', {
      candidateCount: Object.keys(rooms).length,
      removedCount,
    });
  },
);

exports.cleanupStaleMatchmakingEntries = onSchedule(
  {
    schedule: '*/5 * * * *',
    timeZone: 'Asia/Tokyo',
    region: 'asia-southeast1',
  },
  async () => {
    const now = Date.now();
    const updates = {};
    let removedCount = 0;

    for (const path of ['matchmaking', 'arena_matchmaking']) {
      const cutoff = now - MATCHMAKING_CLEANUP_MAX_AGE_MS;
      const entries = await fetchCandidateChildrenByCutoffs(path, [
        ['timestamp', cutoff],
        ['assignedAt', cutoff],
        ['joinedAt', cutoff],
        ['createdAt', cutoff],
      ]);
      for (const [uid, entry] of Object.entries(entries)) {
        if (!isObject(entry)) {
          updates[`${path}/${uid}`] = null;
          removedCount++;
          continue;
        }
        const timestamp = matchmakingTimestamp(entry);
        const status = typeof entry.status === 'string' ? entry.status : '';
        const shouldRemove =
          timestamp <= 0 ||
          now - timestamp >= MATCHMAKING_CLEANUP_MAX_AGE_MS ||
          !['waiting', 'matching', 'assigned', 'matched'].includes(status);
        if (shouldRemove) {
          updates[`${path}/${uid}`] = null;
          removedCount++;
        }
      }
    }

    if (removedCount > 0) {
      await admin.database().ref().update(updates);
    }
    logger.info('Stale matchmaking entries cleanup complete.', {removedCount});
  },
);

exports.processInviteCompletion = onValueWritten(
  {
    ref: '/inviteCompletions/{uid}',
    region: 'asia-southeast1',
  },
  async (event) => {
    if (!event.data.after.exists()) {
      return;
    }
    const invitedUid = event.params.uid || '';
    if (!invitedUid) {
      return;
    }

    const claimRef = admin.database().ref(`inviteClaims/${invitedUid}`);
    const inviteeEligible = await isInviteEligibleNewUser(invitedUid);
    if (!inviteeEligible) {
      await rejectPendingInviteClaim(claimRef, 'existing_account');
      await admin.database().ref(`inviteCompletions/${invitedUid}`).remove();
      return;
    }

    const pendingClaimSnapshot = await claimRef.get();
    const pendingClaim = pendingClaimSnapshot.val();
    if (!isObject(pendingClaim) || pendingClaim.status !== 'pending') {
      return;
    }
    const inviteValidation = await validateFriendInviteClaim(
      invitedUid,
      pendingClaim,
    );
    if (!inviteValidation.ok) {
      await rejectPendingInviteClaim(claimRef, inviteValidation.reason);
      await admin.database().ref(`inviteCompletions/${invitedUid}`).remove();
      return;
    }

    const transactionResult = await claimRef.transaction((current) => {
      if (!isObject(current) || current.status !== 'pending') {
        return undefined;
      }
      const inviterUid =
        typeof current.inviterUid === 'string' ? current.inviterUid : '';
      if (!inviterUid || inviterUid === invitedUid) {
        return {
          ...current,
          status: 'rejected',
          rejectedReason: 'invalid_inviter',
          rejectedAt: admin.database.ServerValue.TIMESTAMP,
        };
      }
      return {
        ...current,
        status: 'completed',
        completedAt: admin.database.ServerValue.TIMESTAMP,
        rewardCoins: INVITE_REWARD_COINS,
      };
    });

    if (!transactionResult.committed) {
      return;
    }
    const claimForReward = transactionResult.snapshot.val();
    if (!isObject(claimForReward) || claimForReward.status !== 'completed') {
      return;
    }

    const inviteCode =
      typeof claimForReward.inviteCode === 'string'
        ? claimForReward.inviteCode
        : '';
    const inviterUid = claimForReward.inviterUid;
    const [inviterName, inviteeName] = await Promise.all([
      publicDisplayName(inviterUid),
      publicDisplayName(invitedUid),
    ]);
    const now = new Date();
    const dateKey = jstDateKey(now);
    const grantId = `invite_${invitedUid}`;
    const updates = {};

    Object.assign(updates, adminGrantWriteUpdates(invitedUid, grantId, {
      type: 'invite_reward',
      role: 'invitee',
      coins: INVITE_REWARD_COINS,
      inviteCode,
      inviterUid,
      title: '招待コード特典',
      message: `${inviterName}さんの招待コード特典として ${INVITE_REWARD_COINS.toLocaleString('ja-JP')} コインを受け取りました。`,
      createdAt: admin.database.ServerValue.TIMESTAMP,
    }));
    Object.assign(updates, adminGrantWriteUpdates(inviterUid, grantId, {
      type: 'invite_reward',
      role: 'inviter',
      coins: INVITE_REWARD_COINS,
      inviteCode,
      invitedUid,
      title: '招待コード特典',
      message: `${inviteeName}さんが招待コードを使ってプレイしました。${INVITE_REWARD_COINS.toLocaleString('ja-JP')} コインを受け取りました。`,
      createdAt: admin.database.ServerValue.TIMESTAMP,
    }));
    updates[`inviteStats/${inviterUid}/inviteCode`] = inviteCode;
    updates[`inviteStats/${inviterUid}/completedInvites`] =
      admin.database.ServerValue.increment(1);
    updates[`inviteStats/${inviterUid}/totalRewardCoins`] =
      admin.database.ServerValue.increment(INVITE_REWARD_COINS);
    updates[`inviteStats/${inviterUid}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;
    updates[`inviteStats/${invitedUid}/usedInviteCode`] = inviteCode;
    updates[`inviteStats/${invitedUid}/inviterUid`] = inviterUid;
    updates[`inviteStats/${invitedUid}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;
    updates[`adminStats/invites/daily/${dateKey}/completed`] =
      admin.database.ServerValue.increment(1);
    updates[`adminStats/invites/daily/${dateKey}/rewardCoins`] =
      admin.database.ServerValue.increment(INVITE_REWARD_COINS * 2);
    updates[`adminStats/invites/daily/${dateKey}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;

    await admin.database().ref().update(updates);
    logger.info('Invite reward granted.', {
      invitedUid,
      inviterUid,
      inviteCode,
      rewardCoins: INVITE_REWARD_COINS,
    });
  },
);

async function dailyWinEntriesForDate(dateKey) {
  const dailySnapshot = await admin
    .database()
    .ref(`dailyWinRankings/${dateKey}`)
    .orderByChild('dailyWins')
    .limitToLast(100)
    .get();
  const dailyEntries = dailyWinRankingEntriesFromMap(dailySnapshot.val(), dateKey);
  const dailyMerged = mergeDailyEntries(dailyEntries, {
    combineDuplicateWins: false,
  });
  const targetDate = new Date(`${dateKey}T12:00:00+09:00`);
  const currentSeasonId = rankedCurrentSeasonId(targetDate);
  const seasonIds = [
    currentSeasonId,
    rankedPreviousSeasonId(currentSeasonId),
  ].filter((seasonId, index, list) => {
    return seasonId && list.indexOf(seasonId) === index;
  });
  const snapshots = await Promise.all([
    ...seasonIds.map((seasonId) =>
      admin.database().ref(`rankedSeasons/seasons/${seasonId}/rankings`).get(),
    ),
  ]);
  const seasonEntries = [];

  seasonIds.forEach((seasonId, index) => {
    const rankings = isObject(snapshots[index].val())
      ? snapshots[index].val()
      : {};
    for (const [uid, raw] of Object.entries(rankings)) {
      appendDailyEntry(seasonEntries, uid, raw, dateKey);
    }
  });

  const seasonMerged = mergeDailyEntries(seasonEntries, {
    combineDuplicateWins: false,
  });
  const merged = new Map(dailyMerged);
  for (const [key, entry] of seasonMerged.entries()) {
    const previous = merged.get(key);
    if (!previous || entry.dailyWins > previous.dailyWins) {
      merged.set(key, entry);
    }
  }
  return [...merged.values()];
}

function dailyWinRankingEntriesFromMap(raw, dateKey) {
  if (!isObject(raw)) return [];
  return Object.entries(raw)
    .filter(([, value]) => isObject(value) && numberValue(value.dailyWins) > 0)
    .map(([uid, value]) => normalizedRankingEntry(uid, value, value.dailyWins, dateKey));
}

function dailyChallengeEntriesFromMap(raw) {
  if (!isObject(raw)) return [];
  return Object.entries(raw)
    .filter(([, value]) => isObject(value) && numberValue(value.score) > 0)
    .map(([uid, value]) => ({
      uid: typeof value.uid === 'string' && value.uid.trim() ? value.uid : uid,
      publicId: typeof value.publicId === 'string' ? value.publicId : '',
      displayName:
        typeof value.displayName === 'string' && value.displayName.trim()
          ? value.displayName.trim()
          : 'Player',
      score: numberValue(value.score),
      updatedAt: numberValue(value.updatedAt),
    }));
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

  const rewardUpdates = rankingRewardUpdates({
    entries,
    limit: RANKED_REWARD_LIMIT,
    rewardFn: rankedRankingRewardCoins,
    grantPrefix: `ranked_${seasonId}`,
    type: 'ranked_season_ranking_reward',
    title: 'ランク戦シーズン報酬',
    seasonId,
    label: 'ランク戦',
  });
  const badgeUpdates = rankedRankBadgeUpdates({entries, seasonId});

  await admin.database().ref().update({
    ...rewardUpdates,
    ...badgeUpdates,
    [`rankedSeasons/seasons/${seasonId}/finalTop100`]: finalTop100,
    [`rankedSeasons/seasons/${seasonId}/finalTop100SchemaVersion`]:
      RANKED_FINAL_TOP_SCHEMA_VERSION,
    [`rankedSeasons/seasons/${seasonId}/finalized`]: true,
    [`rankedSeasons/seasons/${seasonId}/finalizedAt`]:
      admin.database.ServerValue.TIMESTAMP,
    [`adminStats/rankedSeasonFinalizations/${seasonId}`]: {
      seasonId,
      finalizedAt: admin.database.ServerValue.TIMESTAMP,
      entryCount: entries.length,
      topSample: entries.slice(0, 10).map((entry, index) => ({
        uid: entry.uid,
        publicId: entry.publicId,
        displayName: entry.displayName,
        rank: index + 1,
        rating: entry.rating,
        seasonWins: entry.seasonWins,
        seasonLosses: entry.seasonLosses,
      })),
    },
    [`rankedSeasons/archivedSeasonIds/${seasonId}`]: true,
  });
  return finalTop100;
}

function rankedRankBadgeUpdates({entries, seasonId}) {
  const updates = {};
  for (let i = 0; i < entries.length && i < RANKED_REWARD_LIMIT; i++) {
    const entry = entries[i];
    const rank = i + 1;
    if (!entry.uid || rank <= 0) continue;
    updates[`rankedSeasonRankBadges/${entry.uid}/${seasonId}`] = {
      rank,
      rating: numberValue(entry.rating),
    };
  }
  return updates;
}

async function finalizeEndlessSeason(seasonId) {
  if (!seasonId) return {};
  const seasonRef = admin.database().ref(`endlessSeasons/seasons/${seasonId}`);
  const snapshot = await seasonRef.get();
  const season = isObject(snapshot.val()) ? snapshot.val() : {};
  if (
    season.finalized === true &&
    season.finalTop100SchemaVersion === ENDLESS_FINAL_TOP_SCHEMA_VERSION &&
    isObject(season.finalTop100)
  ) {
    return season.finalTop100;
  }

  let entries = endlessRankingEntriesFromMap(season.rankings);
  entries = entries
    .filter((entry) => entry.highestEndlessScore > 0)
    .sort((a, b) => {
      if (b.highestEndlessScore !== a.highestEndlessScore) {
        return b.highestEndlessScore - a.highestEndlessScore;
      }
      return a.updatedAt - b.updatedAt;
    })
    .slice(0, ENDLESS_FINAL_TOP_LIMIT);

  const finalTop100 = {};
  entries.forEach((entry, index) => {
    const rank = index + 1;
    finalTop100[`rank_${String(rank).padStart(3, '0')}`] = {
      uid: entry.uid,
      publicId: entry.publicId,
      displayName: entry.displayName,
      highestEndlessScore: entry.highestEndlessScore,
      rank,
      updatedAt: entry.updatedAt,
    };
  });

  const rewardUpdates = rankingRewardUpdates({
    entries,
    limit: ENDLESS_REWARD_LIMIT,
    rewardFn: endlessRankingRewardCoins,
    grantPrefix: `endless_${seasonId}`,
    type: 'endless_weekly_ranking_reward',
    title: 'エンドレス週間ランキング報酬',
    seasonId,
    label: 'エンドレス',
  });
  const badgeUpdates = endlessRankBadgeUpdates({entries, seasonId});

  await admin.database().ref().update({
    ...rewardUpdates,
    ...badgeUpdates,
    [`endlessSeasons/seasons/${seasonId}/finalTop100`]: finalTop100,
    [`endlessSeasons/seasons/${seasonId}/finalTop100SchemaVersion`]:
      ENDLESS_FINAL_TOP_SCHEMA_VERSION,
    [`endlessSeasons/seasons/${seasonId}/finalized`]: true,
    [`endlessSeasons/seasons/${seasonId}/finalizedAt`]:
      admin.database.ServerValue.TIMESTAMP,
    [`endlessSeasons/archivedSeasonIds/${seasonId}`]: true,
  });
  return finalTop100;
}

function endlessRankBadgeUpdates({entries, seasonId}) {
  const updates = {};
  for (let i = 0; i < entries.length && i < ENDLESS_REWARD_LIMIT; i++) {
    const entry = entries[i];
    const rank = i + 1;
    if (!entry.uid || rank <= 0) continue;
    updates[`endlessSeasonRankBadges/${entry.uid}/${seasonId}`] = {
      rank,
      score: numberValue(entry.highestEndlessScore),
    };
  }
  return updates;
}

async function resetRankedSeason(currentSeasonId) {
  const [currentSeasonSnapshot, summariesSnapshot] =
    await Promise.all([
      admin
        .database()
        .ref(`rankedSeasons/seasons/${currentSeasonId}/rankings`)
        .get(),
      admin.database().ref(PLAYER_SUMMARY_SOURCE_PATH).get(),
    ]);
  const currentSeasonRankings = isObject(currentSeasonSnapshot.val())
    ? currentSeasonSnapshot.val()
    : {};
  const summaries = isObject(summariesSnapshot.val())
    ? summariesSnapshot.val()
    : {};
  const updates = {};

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
    updates[`users/${uid}/rating`] = RANKED_INITIAL_RATING;
    updates[`users/${uid}/updatedAt`] = admin.database.ServerValue.TIMESTAMP;
    updates[`publicProfiles/${uid}/ranked/currentRating`] =
      RANKED_INITIAL_RATING;
    updates[`publicProfiles/${uid}/updatedAt`] =
      admin.database.ServerValue.TIMESTAMP;
  }

  updates['rankedSeasons/currentSeasonId'] = currentSeasonId;
  await admin.database().ref().update(updates);
  return {
    resetCurrentSeasonEntries: Object.keys(currentSeasonRankings).length,
    resetSummaryEntries: Object.keys(summaries).length,
  };
}

async function seedCurrentEndlessSeasonRankings(seasonId) {
  if (!seasonId) {
    return {endlessSeededEntries: 0};
  }
  const seasonRef = admin.database().ref(`endlessSeasons/seasons/${seasonId}`);
  const snapshot = await seasonRef.get();
  const season = isObject(snapshot.val()) ? snapshot.val() : {};
  if (season.startsFromZero === true) {
    return {endlessSeededEntries: 0};
  }
  await seasonRef.update({
    startsFromZero: true,
    legacySeededFromGlobal: false,
    initializedAt: admin.database.ServerValue.TIMESTAMP,
  });
  return {endlessSeededEntries: 0};
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

  const updates = {};
  const sanitizedSamples = [];
  for (const uid of staleUids) {
    const raw = rankings[uid];
    if (sanitizedSamples.length < 30 && isObject(raw)) {
      sanitizedSamples.push({
        uid,
        publicId: typeof raw.publicId === 'string' ? raw.publicId : '',
        displayName: typeof raw.displayName === 'string' ? raw.displayName : '',
        previousRating: numberValue(raw.rating),
        previousSeasonWins: numberValue(raw.seasonWins),
        previousSeasonLosses: numberValue(raw.seasonLosses),
        correctedRating: RANKED_INITIAL_RATING,
      });
    }
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
  updates[`adminStats/rankedSeasonSanitizations/${currentSeasonId}`] = {
    seasonId: currentSeasonId,
    sanitizedAt: admin.database.ServerValue.TIMESTAMP,
    sanitizedEntries: staleUids.length,
    samples: sanitizedSamples,
  };
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

function endlessRankingEntriesFromMap(raw) {
  if (!isObject(raw)) return [];
  return Object.entries(raw)
    .filter(([, value]) => isObject(value) && value.seededFromLegacy !== true)
    .map(([uid, value]) => normalizedEndlessRankingEntry(uid, value));
}

function normalizedEndlessRankingEntry(uid, raw) {
  return {
    uid: typeof raw.uid === 'string' && raw.uid.trim() ? raw.uid : uid,
    publicId: typeof raw.publicId === 'string' ? raw.publicId : '',
    displayName:
      typeof raw.displayName === 'string' && raw.displayName.trim()
        ? raw.displayName.trim()
        : typeof raw.name === 'string' && raw.name.trim()
          ? raw.name.trim()
          : 'Player',
    highestEndlessScore: numberValue(raw.highestEndlessScore),
    updatedAt: numberValue(raw.updatedAt),
  };
}

function rankedRankingRewardCoins(rank) {
  if (rank === 1) return 300000;
  if (rank <= 3) return 150000;
  if (rank <= 10) return 80000;
  if (rank <= 30) return 30000;
  if (rank <= 50) return 10000;
  if (rank <= 100) return 5000;
  return 0;
}

function endlessRankingRewardCoins(rank) {
  if (rank === 1) return 100000;
  if (rank <= 3) return 50000;
  if (rank <= 10) return 25000;
  if (rank <= 30) return 10000;
  if (rank <= 50) return 5000;
  return 0;
}

function dailyWinRankingRewardCoins(rank) {
  if (rank === 1) return 50000;
  if (rank <= 3) return 20000;
  if (rank <= 10) return 5000;
  return 0;
}

function rankingRewardUpdates({
  entries,
  limit,
  rewardFn,
  grantPrefix,
  type,
  title,
  seasonId,
  label,
}) {
  const updates = {};
  for (let i = 0; i < entries.length && i < limit; i++) {
    const entry = entries[i];
    const rank = i + 1;
    const coins = rewardFn(rank);
    if (!entry.uid || coins <= 0) continue;
    Object.assign(
      updates,
      adminGrantWriteUpdates(
        entry.uid,
        `${grantPrefix}_rank_${rank}`,
        rankingRewardGrant({
        type,
        title,
        message:
          `${label} ${rewardSeasonLabel({type, seasonId})} ${rank}位報酬として ` +
          `${coins.toLocaleString('ja-JP')} コインを受け取れます。`,
        coins,
        rank,
        seasonId,
        expiresAt: rewardExpiresAt({type, seasonId}),
        }),
      ),
    );
  }
  return updates;
}

function adminGrantWriteUpdates(uid, grantId, grant) {
  const expiresAt = numberValue(grant?.expiresAt);
  if (expiresAt <= 0) {
    return {
      [`adminGrants/${uid}/${grantId}`]: grant,
    };
  }
  const expirationIndexKey = adminGrantExpirationKey(expiresAt, uid, grantId);
  return {
    [`adminGrants/${uid}/${grantId}`]: {
      ...grant,
      expirationIndexKey,
    },
    [`${ADMIN_GRANT_EXPIRATIONS_PATH}/${expirationIndexKey}`]: {
      uid,
      grantId,
      expiresAt,
    },
  };
}

function adminGrantExpirationKey(expiresAt, uid, grantId) {
  const paddedExpiresAt = String(Math.trunc(expiresAt)).padStart(13, '0');
  return `${paddedExpiresAt}_${rtdbKeySafe(uid)}_${rtdbKeySafe(grantId)}`;
}

function rtdbKeySafe(value) {
  return `${value}`.replace(/[.#$\[\]\/]/g, '_');
}

function rankingRewardGrant({
  type,
  title,
  message,
  coins,
  rank,
  seasonId,
  expiresAt,
}) {
  return {
    type,
    title,
    message,
    coins,
    rank,
    seasonId,
    createdAt: admin.database.ServerValue.TIMESTAMP,
    ...(expiresAt > 0 ? {expiresAt} : {}),
  };
}

function rewardExpiresAt({type, seasonId}) {
  if (type === 'ranked_season_ranking_reward') {
    return rankedRewardExpiresAt(seasonId);
  }
  if (type === 'endless_weekly_ranking_reward') {
    return endlessRewardExpiresAt(seasonId);
  }
  if (type === 'daily_win_ranking_reward') {
    return dailyWinRewardExpiresAt(seasonId);
  }
  if (type === 'daily_challenge_ranking_reward') {
    return dailyWinRewardExpiresAt(seasonId);
  }
  return 0;
}

function rewardSeasonLabel({type, seasonId}) {
  if (type === 'ranked_season_ranking_reward') {
    return rankedSeasonLabel(seasonId);
  }
  if (type === 'endless_weekly_ranking_reward') {
    return endlessSeasonLabel(seasonId);
  }
  return seasonId;
}

function japaneseDateLabel(dateKey) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey);
  if (!match) return dateKey;
  const year = Number.parseInt(match[1], 10);
  const month = Number.parseInt(match[2], 10);
  const day = Number.parseInt(match[3], 10);
  if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
    return dateKey;
  }
  return `${year}年${month}月${day}日`;
}

function rankedSeasonLabel(seasonId) {
  const number = rankedSeasonNumber(seasonId);
  return `シーズン${number}`;
}

function rankedSeasonNumber(seasonId) {
  const base = /^(\d{4})-(\d{2})$/.exec(RANKED_BASE_SEASON_ID);
  const current = /^(\d{4})-(\d{2})$/.exec(seasonId);
  if (!base || !current) return 0;
  const baseYear = Number.parseInt(base[1], 10);
  const baseMonth = Number.parseInt(base[2], 10);
  const year = Number.parseInt(current[1], 10);
  const month = Number.parseInt(current[2], 10);
  return (year - baseYear) * 12 + (month - baseMonth);
}

function endlessSeasonLabel(seasonId) {
  const match = /^(\d{4})-W(\d{2})$/.exec(seasonId);
  if (!match) return seasonId;
  const year = Number.parseInt(match[1], 10);
  const week = Number.parseInt(match[2], 10);
  if (!Number.isFinite(year) || !Number.isFinite(week)) return seasonId;
  return `${year}年第${week}週`;
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

function buildDailyStats(dateKey, globalStats = {}, playerCounts = {}) {
  const registeredPlayers = isObject(globalStats.registeredPlayers)
    ? Object.values(globalStats.registeredPlayers).filter(isObject)
    : [];
  const activePlayers = isObject(globalStats.activePlayers)
    ? Object.values(globalStats.activePlayers).filter(isObject)
    : [];
  const totals = isObject(globalStats.totals) ? globalStats.totals : {};
  const ranked = isObject(globalStats.ranked) ? globalStats.ranked : {};
  const modePlayCounts = normalizedModePlayCounts(globalStats.modePlayCounts);
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
  return {
    date: dateKey,
    totalPlayers: numberValue(playerCounts.totalPlayers),
    registeredPlayers: {
      count: registeredPlayers.length,
      players: registeredPlayers,
    },
    loginPlayers: {
      count: activePlayers.length,
    },
    modePlayCounts,
    formationCounts,
    results: {
      totalMatches: numberValue(totals.matches),
      totalWins: numberValue(totals.wins),
      totalLosses: numberValue(totals.losses),
      totalClearedBalls: numberValue(totals.clearedBalls),
      totalNormalClearedBalls: numberValue(totals.normalClearedBalls),
    },
    ranked: {
      matches: numberValue(ranked.matches),
      wins: numberValue(ranked.wins),
      losses: numberValue(ranked.losses),
      ratingDelta: numberValue(ranked.ratingDelta),
    },
    economy,
  };
}

function mergeDailyRawStats(primary = {}, legacy = {}) {
  if (!isObject(primary)) return isObject(legacy) ? legacy : {};
  if (!isObject(legacy)) return primary;
  return {
    date: primary.date || legacy.date,
    updatedAt: Math.max(numberValue(primary.updatedAt), numberValue(legacy.updatedAt)),
    registeredPlayers: {
      ...(isObject(legacy.registeredPlayers) ? legacy.registeredPlayers : {}),
      ...(isObject(primary.registeredPlayers) ? primary.registeredPlayers : {}),
    },
    activePlayers: {
      ...(isObject(legacy.activePlayers) ? legacy.activePlayers : {}),
      ...(isObject(primary.activePlayers) ? primary.activePlayers : {}),
    },
    totals: sumObjectMaps(legacy.totals, primary.totals),
    ranked: sumObjectMaps(legacy.ranked, primary.ranked),
    modePlayCounts: sumObjectMaps(legacy.modePlayCounts, primary.modePlayCounts),
    formationCounts: sumObjectMaps(legacy.formationCounts, primary.formationCounts),
    economy: sumObjectMaps(legacy.economy, primary.economy),
  };
}

function sumObjectMaps(...maps) {
  const result = {};
  for (const map of maps) {
    if (!isObject(map)) continue;
    for (const [key, value] of Object.entries(map)) {
      result[key] = numberValue(result[key]) + numberValue(value);
    }
  }
  return result;
}

function normalizedModePlayCounts(raw) {
  const counts = intMap(raw);
  const endless = numberValue(counts.ENDLESS) + numberValue(counts.SOLO);
  const ranked = numberValue(counts.RANKED);
  const rankedPvp = numberValue(counts.RANKED_PVP);
  const friend = Math.max(
    numberValue(counts.FRIEND),
    numberValue(counts.FRIEND_PVP),
  );
  const result = {};
  if (ranked > 0) result.RANKED = ranked;
  if (rankedPvp > 0) result.RANKED_PVP = rankedPvp;
  if (endless > 0) result.ENDLESS = endless;
  if (numberValue(counts.CPU) > 0) result.CPU = numberValue(counts.CPU);
  if (friend > 0) result.FRIEND = friend;
  if (numberValue(counts.ARENA) > 0) result.ARENA = numberValue(counts.ARENA);
  const versus = friend + rankedPvp;
  if (versus > 0) result.VERSUS = versus;
  for (const [key, value] of Object.entries(counts)) {
    if (
      [
        'SOLO',
        'ENDLESS',
        'RANKED',
        'RANKED_PVP',
        'CPU',
        'FRIEND',
        'FRIEND_PVP',
        'ARENA',
        'ARENA_PVP',
        'VERSUS',
      ].includes(key)
    ) {
      continue;
    }
    if (value > 0) result[key] = value;
  }
  return result;
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

function jstStartOfDayMillis(timestampMillis) {
  const shifted = new Date(timestampMillis + JST_OFFSET_MS);
  const startUtcMillis = Date.UTC(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth(),
    shifted.getUTCDate(),
  );
  return startUtcMillis - JST_OFFSET_MS;
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

function rankedNextSeasonId(seasonId) {
  const match = /^(\d{4})-(\d{2})$/.exec(seasonId);
  if (!match) return '';
  const year = Number.parseInt(match[1], 10);
  const month = Number.parseInt(match[2], 10);
  return month === 12 ? formatSeasonId(year + 1, 1) : formatSeasonId(year, month + 1);
}

function rankedSeasonEndAtMillis(seasonId) {
  const match = /^(\d{4})-(\d{2})$/.exec(seasonId);
  if (!match) return 0;
  const year = Number.parseInt(match[1], 10);
  const month = Number.parseInt(match[2], 10);
  if (!Number.isFinite(year) || !Number.isFinite(month)) return 0;
  return Date.UTC(
    year,
    month - 1,
    lastDayOfMonth(year, month),
    RANKED_SEASON_END_HOUR_JST,
  ) - JST_OFFSET_MS;
}

function rankedRewardExpiresAt(seasonId) {
  const nextSeasonId = rankedNextSeasonId(seasonId);
  return nextSeasonId ? rankedSeasonEndAtMillis(nextSeasonId) : 0;
}

function endlessCurrentSeasonId(date) {
  const wall = jstWallClockDate(date);
  return formatEndlessWeekId(endlessWeekStartDate(wall));
}

function endlessPreviousSeasonId(seasonId) {
  const start = endlessWeekStartDateForId(seasonId);
  if (!start) return '';
  return formatEndlessWeekId(new Date(start.getTime() - 7 * 24 * 60 * 60 * 1000));
}

function endlessRewardExpiresAt(seasonId) {
  const start = endlessWeekStartDateForId(seasonId);
  if (!start) return 0;
  return Date.UTC(
    start.getUTCFullYear(),
    start.getUTCMonth(),
    start.getUTCDate() + 14,
    ENDLESS_SEASON_SWITCH_HOUR_JST,
  ) - JST_OFFSET_MS;
}

function dailyWinRewardExpiresAt(dateKey) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey);
  if (!match) return 0;
  const year = Number.parseInt(match[1], 10);
  const month = Number.parseInt(match[2], 10);
  const day = Number.parseInt(match[3], 10);
  if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
    return 0;
  }
  return Date.UTC(year, month - 1, day + 2, 0) - JST_OFFSET_MS;
}

function endlessWeekStartDate(wall) {
  const dayStart = Date.UTC(
    wall.getUTCFullYear(),
    wall.getUTCMonth(),
    wall.getUTCDate(),
  );
  const day = new Date(dayStart);
  const jsDay = day.getUTCDay();
  const weekday = jsDay === 0 ? 7 : jsDay;
  const monday = new Date(
    dayStart - (weekday - ENDLESS_SEASON_SWITCH_WEEKDAY_JST) * 24 * 60 * 60 * 1000,
  );
  const switchAt = Date.UTC(
    monday.getUTCFullYear(),
    monday.getUTCMonth(),
    monday.getUTCDate(),
    ENDLESS_SEASON_SWITCH_HOUR_JST,
  );
  if (wall.getTime() < switchAt) {
    return new Date(monday.getTime() - 7 * 24 * 60 * 60 * 1000);
  }
  return monday;
}

function endlessWeekStartDateForId(seasonId) {
  const match = /^(\d{4})-W(\d{2})$/.exec(seasonId);
  if (!match) return null;
  const year = Number.parseInt(match[1], 10);
  const week = Number.parseInt(match[2], 10);
  if (!Number.isFinite(year) || !Number.isFinite(week) || week < 1 || week > 53) {
    return null;
  }
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const jsDay = jan4.getUTCDay();
  const weekday = jsDay === 0 ? 7 : jsDay;
  const week1Monday = new Date(
    jan4.getTime() - (weekday - 1) * 24 * 60 * 60 * 1000,
  );
  return new Date(week1Monday.getTime() + (week - 1) * 7 * 24 * 60 * 60 * 1000);
}

function formatEndlessWeekId(weekStart) {
  const thursday = new Date(
    weekStart.getTime() + (4 - isoWeekday(weekStart)) * 24 * 60 * 60 * 1000,
  );
  const weekYear = thursday.getUTCFullYear();
  const firstThursday = new Date(Date.UTC(weekYear, 0, 4));
  const diffDays = Math.floor((thursday.getTime() - firstThursday.getTime()) /
    (24 * 60 * 60 * 1000));
  const week = 1 + Math.floor((diffDays + isoWeekday(firstThursday) - 1) / 7);
  return `${weekYear}-W${String(week).padStart(2, '0')}`;
}

function isoWeekday(date) {
  const jsDay = date.getUTCDay();
  return jsDay === 0 ? 7 : jsDay;
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

async function fetchCandidateChildrenByCutoffs(path, indexedCutoffs, limit = 1000) {
  const merged = {};
  const ref = admin.database().ref(path);
  const snapshots = await Promise.all(
    indexedCutoffs.map(([childPath, cutoff]) =>
      ref.orderByChild(childPath).endAt(cutoff).limitToFirst(limit).get(),
    ),
  );
  for (const snapshot of snapshots) {
    const values = isObject(snapshot.val()) ? snapshot.val() : {};
    for (const [key, value] of Object.entries(values)) {
      merged[key] = value;
    }
  }
  return merged;
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

function matchmakingTimestamp(entry) {
  const candidates = [
    entry.timestamp,
    entry.assignedAt,
    entry.joinedAt,
    entry.createdAt,
  ];
  for (const candidate of candidates) {
    const value = numberValue(candidate);
    if (value > 0) {
      return value;
    }
  }
  return 0;
}

async function publicDisplayName(uid) {
  if (!uid) return 'プレイヤー';
  const snapshot = await admin.database().ref(`publicProfiles/${uid}/displayName`).get();
  const value = snapshot.val();
  const name = typeof value === 'string' ? value.trim() : '';
  return name || 'プレイヤー';
}

async function validateFriendInviteClaim(invitedUid, claim) {
  const inviteCode =
    typeof claim.inviteCode === 'string' ? claim.inviteCode.trim() : '';
  const inviterUid =
    typeof claim.inviterUid === 'string' ? claim.inviterUid.trim() : '';
  if (!inviteCode || !inviterUid || inviterUid === invitedUid) {
    return {ok: false, reason: 'invalid_claim'};
  }

  const codeSnapshot = await admin.database().ref(`inviteCodes/${inviteCode}`).get();
  const code = codeSnapshot.val();
  if (!isObject(code)) {
    return {ok: false, reason: 'invite_code_not_found'};
  }
  if (code.disabled === true) {
    return {ok: false, reason: 'invite_code_disabled'};
  }
  if (code.uid !== inviterUid) {
    return {ok: false, reason: 'invite_code_owner_mismatch'};
  }
  const usedUids = isObject(code.usedUids) ? code.usedUids : {};
  const hasModernReservation = isObject(usedUids[invitedUid]);
  const hasLegacyReservation = code.usedByUid === invitedUid;
  if (!['active', 'used'].includes(code.status) ||
      (!hasModernReservation && !hasLegacyReservation)) {
    return {ok: false, reason: 'invite_code_not_reserved'};
  }
  const expiresAt = numberValue(code.expiresAt);
  if (expiresAt > 0 && Date.now() > expiresAt) {
    return {ok: false, reason: 'invite_code_expired'};
  }
  const maxUses = numberValue(code.maxUses);
  const usedCount = numberValue(code.usedCount);
  if (maxUses > 0 && usedCount > maxUses) {
    return {ok: false, reason: 'invite_code_overused'};
  }
  const eligibleDateKey =
    typeof code.eligibleInviteeDateKey === 'string' && code.eligibleInviteeDateKey
      ? code.eligibleInviteeDateKey
      : typeof code.inviteDateKey === 'string'
        ? code.inviteDateKey
        : '';
  if (eligibleDateKey) {
    const inviteeDateEligible = await isInviteEligibleNewUserForDate(
      invitedUid,
      eligibleDateKey,
    );
    if (!inviteeDateEligible) {
      return {ok: false, reason: 'invitee_created_on_different_date'};
    }
  }
  return {ok: true, reason: ''};
}

async function rejectPendingInviteClaim(claimRef, reason) {
  await claimRef.transaction((current) => {
    if (!isObject(current) || current.status !== 'pending') {
      return undefined;
    }
    return {
      ...current,
      status: 'rejected',
      rejectedReason: reason,
      rejectedAt: admin.database.ServerValue.TIMESTAMP,
    };
  });
}

async function isInviteEligibleNewUser(uid) {
  const createdAtMs = await authCreatedAtMs(uid);
  return createdAtMs >= INVITE_ELIGIBLE_AUTH_CREATED_AFTER_MS;
}

async function isInviteEligibleNewUserForDate(uid, dateKey) {
  const createdAtMs = await authCreatedAtMs(uid);
  if (createdAtMs < INVITE_ELIGIBLE_AUTH_CREATED_AFTER_MS) {
    return false;
  }
  return jstDateKey(new Date(createdAtMs)) === dateKey;
}

async function authCreatedAtMs(uid) {
  try {
    const user = await admin.auth().getUser(uid);
    const creationTime = user?.metadata?.creationTime;
    const createdAtMs = Date.parse(creationTime || '');
    if (Number.isNaN(createdAtMs)) {
      return 0;
    }
    return createdAtMs;
  } catch (error) {
    logger.warn('Failed to verify invite eligibility.', {
      uid,
      error: error?.message || String(error),
    });
    return 0;
  }
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
