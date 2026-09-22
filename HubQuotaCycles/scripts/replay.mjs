// Offline-only experiment. No network access, service registration or app configuration.
import fs from 'node:fs/promises';
import path from 'node:path';
import { appendCycleObservation, readCycleHistory } from '../src/quotaCycles.js';
const [input, output] = process.argv.slice(2);
if (!input || !output || path.resolve(input) === path.resolve(output)) {
  throw new Error('Usage: node scripts/replay.mjs observations.json isolated-state.json');
}
const source = JSON.parse(await fs.readFile(input, 'utf8'));
const rows = [...source.observations].sort((a, b) => a.receivedAt.localeCompare(b.receivedAt) || a.id.localeCompare(b.id));
let saved;
try { saved = JSON.parse(await fs.readFile(output, 'utf8')); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
if (saved && saved.schemaVersion !== 1) throw new Error('incompatible_schema');
const entries = new Map(saved?.entries || []);
const seen = new Set(saved?.seen || []);
const tx = {
  async get(key) { return structuredClone(entries.get(key)); },
  async put(key, value) { entries.set(key, structuredClone(value)); },
  async list(options) {
    return new Map([...entries].sort(([a], [b]) => a.localeCompare(b)).filter(([key]) =>
      key.startsWith(options.prefix) && (!options.startAfter || key > options.startAfter) &&
      (!options.start || key >= options.start) && (!options.end || key < options.end)).slice(0, options.limit));
  },
};
const decisions = {};
for (const observation of rows) {
  if (seen.has(observation.id)) { decisions.duplicate = (decisions.duplicate || 0) + 1; continue; }
  for (const reason of await appendCycleObservation(tx, observation)) decisions[reason] = (decisions[reason] || 0) + 1;
  seen.add(observation.id);
}
await fs.mkdir(path.dirname(output), { recursive: true, mode: 0o700 });
const temp = output + '.' + crypto.randomUUID() + '.tmp';
try {
  await fs.writeFile(temp, JSON.stringify({schemaVersion: 1, seen: [...seen], entries: [...entries]}), { mode: 0o600, flag: 'wx' });
  await fs.rename(temp, output);
} finally { await fs.rm(temp, { force: true }); }
const report = await readCycleHistory(tx, new URL('https://offline.invalid/api/quota/cycles?limit=200'));
console.log(JSON.stringify({observations: seen.size, decisions, ...report}, null, 2));
