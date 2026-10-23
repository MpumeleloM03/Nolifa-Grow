// Security rules tests for road hazard warnings.
// Run with:  npm test   (needs Java; starts the Firestore emulator itself)
import { test, before, beforeEach, after, describe } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, deleteDoc } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ubuntu-drop-roads',
    firestore: { rules: readFileSync('../../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8089 },
  });
});

after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const as = (uid, claims = {}) => env.authenticatedContext(uid, { verified: true, ...claims }).firestore();
const stranger = () => env.authenticatedContext('nobody', {}).firestore(); // signed in, not verified

const now = () => Date.now();

const hazard = (over = {}) => ({
  kind: 'pothole',
  lat: -29.97,
  lng: 30.88,
  reportedAt: now(),
  lastSeen: now(),
  reporter: 'rita',
  reporterName: 'Rita',
  confirms: ['rita'],
  denies: [],
  note: 'Deep hole',
  ...over,
});

const seed = (over = {}) =>
  env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'roadHazards', 'h1'), hazard(over)));

const ref = (db) => doc(db, 'roadHazards', 'h1');

describe('creating a warning', () => {
  test('a verified driver can report as themselves', async () => {
    await assertSucceeds(setDoc(ref(as('rita')), hazard()));
  });

  test('an unverified account cannot', async () => {
    await assertFails(setDoc(ref(stranger()), hazard({ reporter: 'nobody', confirms: ['nobody'] })));
  });

  test('signed out cannot', async () => {
    await assertFails(setDoc(ref(env.unauthenticatedContext().firestore()), hazard()));
  });

  test('cannot report as someone else', async () => {
    await assertFails(setDoc(ref(as('sam')), hazard()));
  });

  test('cannot start with extra sightings or a gone vote', async () => {
    await assertFails(setDoc(ref(as('rita')), hazard({ confirms: ['rita', 'a', 'b'] })));
    await assertFails(setDoc(ref(as('rita')), hazard({ denies: ['x'] })));
  });

  test('rejects an unknown kind, a spot outside South Africa and a long note', async () => {
    await assertFails(setDoc(ref(as('rita')), hazard({ kind: 'ufo' })));
    await assertFails(setDoc(ref(as('rita')), hazard({ lat: 48.8, lng: 2.3 })));
    await assertFails(setDoc(ref(as('rita')), hazard({ note: 'x'.repeat(141) })));
  });

  test('cannot back-date a warning to keep it alive or invent a future one', async () => {
    await assertFails(setDoc(ref(as('rita')), hazard({ reportedAt: now() - 3600_000, lastSeen: now() - 3600_000 })));
    await assertFails(setDoc(ref(as('rita')), hazard({ reportedAt: now() + 3600_000, lastSeen: now() + 3600_000 })));
  });

  test('rejects unknown fields', async () => {
    await assertFails(setDoc(ref(as('rita')), { ...hazard(), admin: true }));
  });
});

describe('reading', () => {
  test('any signed-in person can read, signed-out cannot', async () => {
    await seed();
    await assertSucceeds(getDoc(ref(stranger())));
    await assertFails(getDoc(ref(env.unauthenticatedContext().firestore())));
  });
});

describe('still there', () => {
  test('another verified driver adds themselves and renews the clock', async () => {
    await seed({ lastSeen: now() - 60_000 });
    await assertSucceeds(updateDoc(ref(as('sam')), { confirms: ['rita', 'sam'], lastSeen: now() }));
  });

  test('cannot add someone else, or two people at once', async () => {
    await seed();
    await assertFails(updateDoc(ref(as('sam')), { confirms: ['rita', 'tom'], lastSeen: now() }));
    await assertFails(updateDoc(ref(as('sam')), { confirms: ['rita', 'sam', 'tom'], lastSeen: now() }));
  });

  test('cannot remove other people\'s sightings', async () => {
    await seed({ confirms: ['rita', 'tom'] });
    await assertFails(updateDoc(ref(as('sam')), { confirms: ['sam'], lastSeen: now() }));
  });

  test('cannot change what or where the hazard is', async () => {
    await seed();
    await assertFails(updateDoc(ref(as('sam')), { confirms: ['rita', 'sam'], lastSeen: now(), kind: 'flooding' }));
    await assertFails(updateDoc(ref(as('sam')), { confirms: ['rita', 'sam'], lastSeen: now(), lat: -30.1 }));
  });

  test('an unverified account cannot confirm', async () => {
    await seed();
    await assertFails(updateDoc(ref(stranger()), { confirms: ['rita', 'nobody'], lastSeen: now() }));
  });

  test('the clock cannot be pushed into the future', async () => {
    await seed();
    await assertFails(updateDoc(ref(as('sam')), { confirms: ['rita', 'sam'], lastSeen: now() + 3600_000 }));
  });
});

describe('gone', () => {
  test('a verified driver can say it is gone, for themselves only', async () => {
    await seed();
    await assertSucceeds(updateDoc(ref(as('sam')), { denies: ['sam'] }));
    await assertFails(updateDoc(ref(as('tom')), { denies: ['someone-else'] }));
  });

  test('saying gone does not renew the clock', async () => {
    await seed({ lastSeen: now() - 60_000 });
    await assertFails(updateDoc(ref(as('sam')), { denies: ['sam'], lastSeen: now() }));
  });

  test('cannot erase the reporter\'s own sighting', async () => {
    await seed();
    await assertFails(updateDoc(ref(as('sam')), { denies: ['sam'], confirms: [] }));
  });

  test('cannot clear other people\'s gone votes', async () => {
    await seed({ denies: ['tom', 'ann'] });
    await assertFails(updateDoc(ref(as('sam')), { denies: ['sam'] }));
  });
});

describe('deleting', () => {
  test('nobody can delete, not even the reporter', async () => {
    await seed();
    await assertFails(deleteDoc(ref(as('rita'))));
  });
});
