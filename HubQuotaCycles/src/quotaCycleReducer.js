// Runtime-independent quota-cycle inference. Runs in Cloudflare Workers without Node.
export const CYCLE_POLICY = Object.freeze({
  version: 1,
  providers: ['codex'],
  deadlineJitterMs: 2000,
  confirmationCount: 2,
  confirmationSpanMs: 60_000,
  maxTransportDelayMs: 15 * 60_000,
  futureClockToleranceMs: 60_000,
});
const time = value => typeof value === 'string' ? Date.parse(value) : NaN;
const iso = value => new Date(value).toISOString();
const nonempty = value => typeof value === 'string' && value.length > 0;
const finite = value => typeof value === 'number' && Number.isFinite(value);

export function cycleIdentity(observation, window) {
  const durationMs = finite(window.windowSeconds) ? window.windowSeconds * 1000
    : finite(window.windowMinutes) ? window.windowMinutes * 60_000 : NaN;
  if (!Number.isSafeInteger(durationMs) || durationMs <= 0) return null;
  if (window.windowSeconds != null && window.windowMinutes != null &&
      (!finite(window.windowSeconds) || !finite(window.windowMinutes) ||
       Math.abs(window.windowSeconds * 1000 - window.windowMinutes * 60_000) > 1)) return null;
  if (!nonempty(window.limitId) || !nonempty(observation.sourceDeviceId)) return null;
  return {
    provider: observation.provider,
    accountId: nonempty(observation.accountId) ? observation.accountId : null,
    deviceScope: nonempty(observation.accountId) ? null : observation.sourceDeviceId,
    kind: window.kind,
    limitId: window.limitId,
    durationMs,
  };
}

export function validateCycleObservation(observation, window) {
  if (observation.schemaVersion != null && observation.schemaVersion !== 1) return { reason: 'unsupported_schema' };
  if (observation.status !== 'ok') return { reason: 'unhealthy' };
  if (!CYCLE_POLICY.providers.includes(observation.provider) ||
      !['weekly', 'session'].includes(window.kind) || window.rolling === true ||
      window.boundaryKind === 'rolling') return { reason: 'unsupported' };
  const identity = cycleIdentity(observation, window);
  const observedMs = time(observation.sourceObservedAt);
  const receivedMs = time(observation.receivedAt);
  const deadlineMs = time(window.resetsAt);
  if (!identity || !nonempty(observation.id) || !Number.isFinite(observedMs) ||
      !Number.isFinite(receivedMs) || !Number.isFinite(deadlineMs) || deadlineMs <= observedMs ||
      observedMs > receivedMs + CYCLE_POLICY.futureClockToleranceMs ||
      deadlineMs - identity.durationMs > observedMs + CYCLE_POLICY.futureClockToleranceMs) {
    return { reason: 'invalid' };
  }
  if (receivedMs - observedMs > CYCLE_POLICY.maxTransportDelayMs) return { reason: 'delayed' };
  return { identity, observedMs, receivedMs, deadlineMs };
}

/**
 * Calculate period start from a stable deadline, never from a percent drop.
 * Initial discovery is a reconstructed cycle, not a witnessed reset.
 * The source contract cannot tell scheduled reset from replenishment; cause stays unknown.
 */
export function reduceCycle(previous, observation, window) {
  const checked = validateCycleObservation(observation, window);
  if (checked.reason) return { state: previous, event: null, reason: checked.reason };
  const { identity, observedMs, receivedMs, deadlineMs } = checked;
  if (previous && (previous.policyVersion !== CYCLE_POLICY.version ||
      JSON.stringify(previous.identity) !== JSON.stringify(identity))) {
    throw new Error('cycle_state_contract_mismatch');
  }
  if (previous && observedMs <= previous.latestSourceMs) {
    return { state: previous, event: null, reason: 'stale' };
  }
  const state = previous ? structuredClone(previous) : {
    policyVersion: CYCLE_POLICY.version, identity, active: null, pending: null,
  };
  state.latestSourceMs = observedMs;
  state.latestReceivedAt = iso(receivedMs);
  if (state.active) {
    const shift = deadlineMs - time(state.active.resetsAt);
    if (Math.abs(shift) <= CYCLE_POLICY.deadlineJitterMs) {
      state.pending = null;
      return { state, event: null, reason: 'unchanged' };
    }
    if (shift < 0) {
      state.pending = null;
      return { state, event: null, reason: 'regressed' };
    }
  }
  const usedPercent = finite(window.usedPercent) ? window.usedPercent : null;
  // Compare to the fixed first sample, not the last one, so slow drift cannot
  // accumulate into a false stable deadline. Zero percent alone does not confirm anything.
  if (state.pending && Math.abs(deadlineMs - state.pending.deadlineMs) <= CYCLE_POLICY.deadlineJitterMs) {
    state.pending.count += 1;
    state.pending.lastObservedAt = iso(observedMs);
    state.pending.latestUsedPercent = usedPercent;
    state.pending.devices = [...new Set([...state.pending.devices, observation.sourceDeviceId])].sort();
    // Keep the anchor and the most recent evidence, rather than an unbounded list.
    state.pending.observationIds = [state.pending.observationIds[0],
      ...state.pending.observationIds.slice(1).slice(-14), observation.id];
  } else {
    state.pending = {
      deadlineMs, count: 1, firstObservedAt: iso(observedMs), lastObservedAt: iso(observedMs),
      firstUsedPercent: usedPercent, latestUsedPercent: usedPercent,
      devices: [observation.sourceDeviceId], observationIds: [observation.id],
    };
  }
  const p = state.pending;
  if (p.count < CYCLE_POLICY.confirmationCount || observedMs - time(p.firstObservedAt) < CYCLE_POLICY.confirmationSpanMs) {
    return { state, event: null, reason: 'pending' };
  }
  const event = {
    schemaVersion: 1,
    policyVersion: CYCLE_POLICY.version,
    identity,
    kind: state.active ? 'cycleChanged' : 'initialDiscovery',
    derivation: 'stableDeadlineMinusDuration',
    inferredStartAt: iso(p.deadlineMs - identity.durationMs),
    resetsAt: iso(p.deadlineMs),
    previousStartAt: state.active?.inferredStartAt ?? null,
    firstObservedAt: p.firstObservedAt,
    confirmedAt: iso(observedMs),
    recordedAt: iso(receivedMs),
    evidenceObservationIds: p.observationIds,
    evidenceDevices: p.devices,
    firstUsedPercent: p.firstUsedPercent,
    latestUsedPercent: p.latestUsedPercent,
    identityConfidence: identity.accountId ? 'account' : 'deviceOnly',
    deadlineToleranceMs: CYCLE_POLICY.deadlineJitterMs,
    cause: 'unspecified',
  };
  state.active = { inferredStartAt: event.inferredStartAt, resetsAt: event.resetsAt };
  state.pending = null;
  return { state, event, reason: 'confirmed' };
}
