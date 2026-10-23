// Replays every write the real Dart app made (recorded by
// test/export_rules_fixture_test.dart) against the security rules, in order.
// If the app and the rules ever disagree, this fails.
//
// Regenerate the fixture after changing the app's writes:
//   flutter test test/export_rules_fixture_test.dart
import { test, before, beforeEach, after } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ubuntu-drop-contract',
    firestore: {
      rules: readFileSync('../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8089,
    },
  });
});
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

test('every write the app makes is allowed by the rules', async () => {
  const writes = JSON.parse(readFileSync('fixtures/dart-writes.json', 'utf8'));
  for (const [i, w] of writes.entries()) {
    const db = env.authenticatedContext(w.uid, { verified: true }).firestore();
    await assertSucceeds(setDoc(doc(db, w.path), w.data)).catch((e) => {
      e.message = `write #${i} by ${w.uid} to ${w.path} was denied: ${e.message}`;
      throw e;
    });
  }
});
