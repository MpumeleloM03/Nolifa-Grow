// Replays every write the real Dart water module made (recorded by
// test/export_water_fixture_test.dart) against the security rules, in order.
// Provider writes carry the utility claim; everyone else is an ordinary user.
// Entries that share a `tx` were one transaction in the app, so they are
// committed as one atomic batch. If the app and the rules ever disagree, this
// fails.
//
// Regenerate the fixture after changing the app's writes:
//   cd ../../packages/ubuntu_core && flutter test test/export_water_fixture_test.dart
import { test, before, beforeEach, after } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, writeBatch } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ubuntu-drop-water-contract',
    firestore: {
      rules: readFileSync('../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8089,
    },
  });
});
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

/** The recorded writes, grouped into the atomic commits the app made. */
const commits = () => {
  const writes = JSON.parse(readFileSync('fixtures/water-writes.json', 'utf8'));
  const groups = [];
  for (const w of writes) {
    const last = groups[groups.length - 1];
    if (last && last.tx === w.tx) last.writes.push(w);
    else groups.push({ tx: w.tx, uid: w.uid, utility: w.utility === true, writes: [w] });
  }
  return groups;
};

const commit = (c) => {
  const db = env.authenticatedContext(c.uid, { verified: true, ...(c.utility ? { utility: true } : {}) }).firestore();
  const batch = writeBatch(db);
  for (const w of c.writes) batch.set(doc(db, w.path), w.data);
  return batch.commit();
};

const denied = (c, why) => (e) => {
  e.message = `commit #${c.tx} by ${c.uid} (${c.writes.map((w) => w.path).join(', ')}) ${why}: ${e.message}`;
  throw e;
};

test('the fixture covers the whole lifecycle', () => {
  const paths = commits().flatMap((c) => c.writes.map((w) => w.path));
  for (const needle of ['waterZones/', 'waterIncidents/umlazi-1', 'waterIncidents/umlazi-2', '/votes/', 'waterPrefs/']) {
    if (!paths.some((p) => p.includes(needle))) throw new Error(`fixture has no write to ${needle}`);
  }
  const stages = new Set(commits().flatMap((c) => c.writes.map((w) => w.data.stage)));
  for (const stage of ['open', 'requested', 'acknowledged', 'dispatched', 'resolved']) {
    if (!stages.has(stage)) throw new Error(`fixture never reaches stage ${stage}`);
  }
});

test('every write the app makes is allowed by the rules', async () => {
  for (const c of commits()) {
    await assertSucceeds(commit(c)).catch(denied(c, 'was denied'));
  }
});

test('the provider\'s writes are refused without the utility claim', async () => {
  for (const c of commits()) {
    if (c.utility) {
      const ordinary = { ...c, utility: false };
      await assertFails(commit(ordinary)).catch(denied(c, 'was allowed without the utility claim'));
    }
    await assertSucceeds(commit(c)).catch(denied(c, 'was denied'));
  }
});
