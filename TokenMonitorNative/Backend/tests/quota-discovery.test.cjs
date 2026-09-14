const test = require('node:test');
const assert = require('node:assert/strict');
const { mapCodexRateLimitsToProvider } = require('../vendor/src/shared/providers/codex/limits');
const window = minutes => ({ usedPercent: 0, windowDurationMins: minutes, resetsAt: 1800000000 });
const main = { primary: window(300), secondary: window(10080) };

test('Codex public quota metadata carries arbitrary additional lanes and removes absent lanes', () => {
  const before = mapCodexRateLimitsToProvider({ rateLimitsByLimitId: {
    codex: main, spark: { limitName: 'Spark', primary: window(300), secondary: window(10080) }
  }});
  assert.equal(before.windows.length, 4);
  assert.equal(before.windows.filter(w => w.additional).length, 2);
  assert.equal(before.windows.find(w => w.limitId === 'spark').windowMinutes, 300);
  const after = mapCodexRateLimitsToProvider({ rateLimitsByLimitId: {
    codex: { secondary: window(10080) }, 'new-metered-feature': { limitName: 'Future model', secondary: window(10080) }
  }});
  assert.equal(after.windows.length, 2);
  assert.equal(after.windows.some(w => w.limitId === 'spark'), false);
  assert.equal(after.windows.some(w => w.kind === 'session'), false);
  assert.equal(after.windows.find(w => w.additional).limitId, 'new-metered-feature');
  assert.equal(after.windows[0].remainingPercent, 100);
});
