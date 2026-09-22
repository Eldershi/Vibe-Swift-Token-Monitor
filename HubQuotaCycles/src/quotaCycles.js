import { reduceCycle, validateCycleObservation } from './quotaCycleReducer.js';

const STATE = 'quota:cycles:v1:state:';
const EVENT = 'quota:cycles:v1:event:';
async function digest(value) {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(hash)].map(v => v.toString(16).padStart(2, '0')).join('');
}

/** Call inside the SAME transaction that appends a new raw quota observation. */
export async function appendCycleObservation(tx, observation) {
  const decisions = [];
  for (const window of observation.windows || []) {
    const checked = validateCycleObservation(observation, window);
    if (checked.reason) { decisions.push(checked.reason); continue; }
    const key = STATE + await digest(JSON.stringify(checked.identity));
    const previous = await tx.get(key);
    const result = reduceCycle(previous, observation, window);
    decisions.push(result.reason);
    if (result.state !== previous) await tx.put(key, result.state);
    if (result.event) {
      const id = await digest(JSON.stringify([result.event.identity, result.event.resetsAt]));
      await tx.put(EVENT + result.event.recordedAt + ':' + id, { id, ...result.event });
    }
  }
  return decisions;
}

/** Pagination is by recordedAt, not inferredStartAt; late discoveries remain visible. */
export async function readCycleHistory(storage, url) {
  const requested = Number(url.searchParams.get('limit') || 100);
  const limit = Number.isInteger(requested) ? Math.max(1, Math.min(200, requested)) : 100;
  const cursor = url.searchParams.get('cursor');
  if (cursor && (!cursor.startsWith(EVENT) || cursor.length > 160)) return { error: 'invalid_cursor' };
  const from = url.searchParams.get('from');
  const through = url.searchParams.get('to') || new Date().toISOString();
  const start = from ? Date.parse(from) : null, end = Date.parse(through);
  if (!Number.isFinite(end) || (from && (!Number.isFinite(start) || start > end))) return { error: 'invalid_time_range' };
  const options = { prefix: EVENT, limit: limit + 1, end: EVENT + new Date(end).toISOString() + ';' };
  if (cursor) options.startAfter = cursor;
  else if (from) options.start = EVENT + new Date(start).toISOString();
  const entries = [...await storage.list(options)];
  const page = entries.slice(0, limit);
  return { schemaVersion: 1, policyVersion: 1, order: 'recordedAt_ascending',
    snapshotThrough: new Date(end).toISOString(), events: page.map(([, value]) => value),
    nextCursor: entries.length > limit ? page.at(-1)[0] : null };
}

const RAW = 'quota:v1:observation:';
const MIGRATION = 'quota:cycles:v1:backfill';
/**
 * Internal migration helper; expose no public write route. Run with live cycle
 * inference disabled, advance to a fixed snapshot, then catch up before enabling.
 * Each batch commits its cursor and derived records in one DO storage transaction.
 */
export async function backfillCycleHistory(storage, { through, limit = 100 } = {}) {
  if (!Number.isFinite(Date.parse(through)) || !Number.isInteger(limit) || limit < 1 || limit > 200) {
    throw new Error('invalid_backfill_range');
  }
  const snapshotThrough = new Date(through).toISOString();
  return storage.transaction(async tx => {
    const progress = await tx.get(MIGRATION);
    if (progress && snapshotThrough < progress.snapshotThrough) throw new Error('backfill_snapshot_regressed');
    if (progress?.complete && snapshotThrough === progress.snapshotThrough) return progress;
    const options = { prefix: RAW, limit: limit + 1, end: RAW + snapshotThrough + ';' };
    if (progress?.cursor) options.startAfter = progress.cursor;
    const rows = [...await tx.list(options)];
    const page = rows.slice(0, limit);
    for (const [, observation] of page) await appendCycleObservation(tx, observation);
    const next = { schemaVersion: 1, snapshotThrough, complete: rows.length <= limit,
      cursor: page.at(-1)?.[0] ?? progress?.cursor ?? null, count: (progress?.count || 0) + page.length };
    await tx.put(MIGRATION, next);
    return next;
  });
}
