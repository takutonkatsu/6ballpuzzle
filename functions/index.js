const {onValueCreated} = require('firebase-functions/v2/database');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

admin.initializeApp();

const PLAYER_COUNTS_PATH = 'adminStats/playerCounts';
const PLAYER_SUMMARY_SOURCE_PATH = 'playerRecordSummaries';

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
