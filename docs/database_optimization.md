# Database optimization notes

## Goals

- Keep existing production data readable.
- Prefer additive changes over destructive migrations.
- Reduce Realtime Database reads before adding new persistent paths.
- Keep detailed inspection possible through narrow, purpose-specific paths.

## Current high-level paths

| Path | Purpose | Lifetime | Cost notes |
| --- | --- | --- | --- |
| `users/{uid}` | Player display data and rating source | Persistent | Small per-user reads/writes. Safe to keep as the canonical player summary. |
| `rankings/global/{uid}` | Ranking display data | Persistent | Must avoid full scans as player count grows. Use indexed queries for top lists. |
| `playerRecordSummaries/{uid}` | Admin-friendly player record summary | Persistent | Additive summary only. Does not include match history. Throttled client writes. |
| `playerNameLookup/{normalizedName}/{uid}` | Display name to uid lookup | Persistent | Small helper index for console inspection. Names can collide, so each name contains uid children. |
| `matchmaking/{uid}` | Ranked matchmaking queue | Temporary | Full queue reads are acceptable only while the queue is small. Consider bucketed queues if traffic grows. |
| `arena_matchmaking/{uid}` | Arena matchmaking queue | Temporary | Same shape as ranked matchmaking, split by mode. |
| `rooms/{roomId}` | Live match state and short-term recovery data | Temporary | Most expensive path during online play. Prefer small child listeners over whole-room listeners. |
| `reports/{reportId}` | User reports | Persistent/admin | Write-only from clients. Review from Firebase console or admin tooling. |
| `giftCodes/adRemoval/{code}` | Redeemed ad-removal gift codes | Persistent | Small point reads/writes only. |

## Safe optimization order

1. Ranking reads
   - Keep `rankings/global/{uid}` unchanged.
   - Fetch top rating with `orderByChild('rating').limitToLast(100)`.
   - Fetch daily wins with `orderByChild('dailyWinDate').equalTo(today)`.
   - Avoid exact rank calculation outside the visible top 100, because the UI only shows `圏外`.

2. Live room listeners
   - Avoid listening to `rooms/{roomId}` if only `status`, `players`, or rematch state is needed.
   - Keep board, active piece, attacks, stamps, and ojama queues on separate child listeners.
   - Remove consumed push events quickly.

3. Matchmaking
   - Current queue scan is simple and compatible with existing data.
   - If concurrent users grow, add bucket paths such as `matchmakingByRating/{bucket}/{uid}` while continuing to write the old `matchmaking/{uid}` path during rollout.

4. Inspection paths
   - For detailed debugging, add tiny append-only summaries instead of copying full match state.
   - Example: `debugMatchSummaries/{date}/{roomId}` with mode, status, participants, result, and timestamps only.
   - Keep this disabled by default or sample it, because debug logs can become the highest-cost data.

5. Player record inspection
   - Use `playerRecordSummaries/{uid}` for cumulative and same-day aggregate stats.
   - Use `playerNameLookup/{normalizedName}/{uid}` when the Firebase console needs a name-based lookup.
   - Do not sync match history unless there is a separate admin feature that truly needs it.

## Realtime Database rule indexes

The following indexes should stay configured:

- `rankings/global`: `rating`, `dailyWinDate`, `dailyWins`, `updatedAt`
- `playerRecordSummaries`: `publicId`, `displayName`, `updatedAt`, `recordDate`
- `matchmaking`: `rating`, `timestamp`, `joinedAt`
- `arena_matchmaking`: `wins`, `timestamp`, `joinedAt`
- `reports`: `reportedUid`, `createdAt`

## Migration policy

- Never delete or rewrite production nodes as part of an optimization release.
- Add new paths first, write both old and new paths if needed, then switch reads after verifying data.
- Keep old reads as fallback until at least one released version has been live long enough.
- Prefer local caches and short TTLs before adding more database writes.
