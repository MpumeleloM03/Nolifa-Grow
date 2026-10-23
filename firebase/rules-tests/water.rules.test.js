// Security rules tests for the water radar: zones, incidents, votes and prefs,
// plus the stock fields on products.
// Run with:  npm test   (needs Java; starts the Firestore emulator itself)
import { test, before, beforeEach, after, describe } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, deleteDoc, writeBatch, runTransaction } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ubuntu-drop-water',
    firestore: {
      rules: readFileSync('../../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8089,
    },
  });
});

after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

// Everyone is a verified person unless a test says otherwise.
const as = (uid, claims = {}) => env.authenticatedContext(uid, { verified: true, ...claims }).firestore();
const provider = () => as('provider', { utility: true });

// ---------------------------------------------------------------- fixtures

const zoneDoc = (over = {}) => ({
  id: 'z1',
  name: 'Umlazi',
  provider: 'Provider (test)',
  reservoir: 'Test Dam',
  population: 25000,
  voteThreshold: 3,
  readings: [{ t: 1000, level: 35 }],
  latest: 35,
  ...over,
});

const incidentDoc = (over = {}) => ({
  id: 'z1-1',
  zoneId: 'z1',
  epoch: 1,
  stage: 'open',
  votes: 1,
  threshold: 3,
  openedAt: 1000,
  requestedAt: null,
  acknowledgedAt: null,
  dispatchedAt: null,
  resolvedAt: null,
  trucks: 0,
  etaMinutes: 0,
  note: '',
  ...over,
});

/** Writes data directly, bypassing the rules, to set up a scenario. */
const seedZone = (over = {}) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    const z = zoneDoc(over);
    await setDoc(doc(ctx.firestore(), 'waterZones', z.id), z);
  });

const seedIncident = (over = {}, voters = []) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const i = incidentDoc(over);
    await setDoc(doc(db, 'waterIncidents', i.id), i);
    for (const uid of voters) {
      await setDoc(doc(db, 'waterIncidents', i.id, 'votes', uid), { uid, at: 1000 });
    }
  });

const incRef = (db, id = 'z1-1') => doc(db, 'waterIncidents', id);
const voteRef = (db, uid, id = 'z1-1') => doc(db, 'waterIncidents', id, 'votes', uid);

/** What the app does for a first voter: the vote and the new incident, atomically. */
const openIncident = (db, uid, over = {}, { docId = 'z1-1', voteUid = uid, voteData } = {}) => {
  const b = writeBatch(db);
  b.set(voteRef(db, voteUid, docId), voteData ?? { uid: voteUid, at: 1000 });
  b.set(incRef(db, docId), incidentDoc(over));
  return b.commit();
};

/**
 * What the app does for a later voter: their vote document and the counter
 * moving, atomically. `current` is the incident as it stands, `changes` what
 * the update sets on top of it.
 */
const castVote = (db, uid, changes, { id = 'z1-1', voteUid = uid, voteDoc = true, voteData } = {}) => {
  const b = writeBatch(db);
  if (voteDoc) b.set(voteRef(db, voteUid, id), voteData ?? { uid: voteUid, at: 2000 });
  b.update(incRef(db, id), changes);
  return b.commit();
};

// ------------------------------------------------------------------- zones

describe('water zones', () => {
  test('anyone signed in can read; signed-out users cannot', async () => {
    await seedZone();
    await assertSucceeds(getDoc(doc(as('anyone'), 'waterZones', 'z1')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'waterZones', 'z1')));
  });

  test('the provider (utility claim) creates and updates a zone', async () => {
    await assertSucceeds(setDoc(doc(provider(), 'waterZones', 'z1'), zoneDoc()));
    await assertSucceeds(
      setDoc(
        doc(provider(), 'waterZones', 'z1'),
        zoneDoc({ readings: [{ t: 1000, level: 35 }, { t: 2000, level: 30 }], latest: 30 }),
      ),
    );
  });

  test('a zone with no readings yet can be created', async () => {
    await assertSucceeds(setDoc(doc(provider(), 'waterZones', 'z1'), zoneDoc({ readings: [], latest: null })));
  });

  test('a normal user cannot create or update a zone', async () => {
    await assertFails(setDoc(doc(as('farmer'), 'waterZones', 'z1'), zoneDoc()));
    await seedZone();
    await assertFails(updateDoc(doc(as('farmer'), 'waterZones', 'z1'), { latest: 90 }));
    await assertFails(setDoc(doc(as('farmer'), 'waterZones', 'z1'), zoneDoc({ latest: 90 })));
  });

  test('only a real utility claim counts', async () => {
    await assertFails(setDoc(doc(as('x', { utility: false }), 'waterZones', 'z1'), zoneDoc()));
    await assertFails(setDoc(doc(as('x', { utility: 'true' }), 'waterZones', 'z1'), zoneDoc()));
    await assertFails(setDoc(doc(as('x', { mediator: true, vet: true }), 'waterZones', 'z1'), zoneDoc()));
  });

  test('nobody can delete a zone, not even the provider', async () => {
    await seedZone();
    await assertFails(deleteDoc(doc(provider(), 'waterZones', 'z1')));
    await assertFails(deleteDoc(doc(as('farmer'), 'waterZones', 'z1')));
  });

  test('malformed zones are refused', async () => {
    const put = (over) => setDoc(doc(provider(), 'waterZones', 'z1'), zoneDoc(over));
    await assertFails(put({ id: 'other' }));
    await assertFails(put({ name: '' }));
    await assertFails(put({ voteThreshold: 0 }));
    await assertFails(put({ voteThreshold: 2.5 }));
    await assertFails(put({ population: -1 }));
    await assertFails(put({ latest: 101 }));
    await assertFails(put({ latest: -1 }));
    await assertFails(put({ latest: 'low' }));
    await assertFails(put({ readings: Array.from({ length: 49 }, (_, i) => ({ t: i, level: 50 })) }));
    await assertSucceeds(put({ readings: Array.from({ length: 48 }, (_, i) => ({ t: i, level: 50 })), latest: 50 }));
    await assertFails(put({ sneaky: true }));
  });
});

// --------------------------------------------------------- opening an incident

describe('only verified people can vote', () => {
  test('an unverified account cannot open an incident or add a vote', async () => {
    await seedZone();
    await assertFails(openIncident(as('fake', { verified: false }), 'fake'));
    await assertSucceeds(openIncident(as('real'), 'real'));
  });
});

describe('the first voter opens an incident', () => {
  test('on a Low zone, with their own vote in the same write', async () => {
    await seedZone();
    await assertSucceeds(openIncident(as('n1'), 'n1'));
  });

  test('works through a transaction too, the way the app writes it', async () => {
    await seedZone();
    const db = as('n1');
    await assertSucceeds(
      runTransaction(db, async (tx) => {
        const existing = await tx.get(voteRef(db, 'n1'));
        if (existing.exists()) return;
        tx.set(voteRef(db, 'n1'), { uid: 'n1', at: 1000 });
        tx.set(incRef(db), incidentDoc());
      }),
    );
  });

  test('also on a Critical zone, and right up to the 40% line', async () => {
    await seedZone({ latest: 8 });
    await assertSucceeds(openIncident(as('n1'), 'n1'));
    await seedZone({ id: 'z2', latest: 39.9 });
    await assertSucceeds(openIncident(as('n1'), 'n1', { id: 'z2-1', zoneId: 'z2' }, { docId: 'z2-1' }));
  });

  test('cannot open one on a healthy or watch zone', async () => {
    await seedZone({ latest: 80 });
    await assertFails(openIncident(as('n1'), 'n1'));
    await seedZone({ latest: 50 });
    await assertFails(openIncident(as('n1'), 'n1'));
    await seedZone({ latest: 40 });
    await assertFails(openIncident(as('n1'), 'n1'));
  });

  test('cannot open one on a zone with no reading yet, or one that does not exist', async () => {
    await seedZone({ readings: [], latest: null });
    await assertFails(openIncident(as('n1'), 'n1'));
    await assertFails(openIncident(as('n1'), 'n1', { id: 'ghost-1', zoneId: 'ghost' }, { docId: 'ghost-1' }));
  });

  test('cannot point the incident at a different zone than its id says', async () => {
    await seedZone();
    await seedZone({ id: 'z2', latest: 10 });
    // Named for z1 but claiming z2, and the other way round.
    await assertFails(openIncident(as('n1'), 'n1', { id: 'z1-1', zoneId: 'z2' }));
    await assertFails(openIncident(as('n1'), 'n1', { id: 'z2-1', zoneId: 'z1' }, { docId: 'z1-1' }));
    await assertFails(openIncident(as('n1'), 'n1', { id: 'z2-1', zoneId: 'z1' }, { docId: 'z2-1' }));
  });

  test('the id must be zoneId-epoch, with epoch at least 1', async () => {
    await seedZone();
    await assertFails(openIncident(as('n1'), 'n1', { id: 'z1-2', epoch: 1 }, { docId: 'z1-2' }));
    await assertFails(openIncident(as('n1'), 'n1', { id: 'z1-0', epoch: 0 }, { docId: 'z1-0' }));
    await assertFails(openIncident(as('n1'), 'n1', { id: 'z1-1.5', epoch: 1.5 }, { docId: 'z1-1.5' }));
    await assertFails(openIncident(as('n1'), 'n1', { id: 'other', epoch: 1 }, { docId: 'z1-1' }));
    // A matching id is not enough: epoch 7 has no resolved epoch 6 behind it.
    await assertFails(openIncident(as('n1'), 'n1', { id: 'z1-7', epoch: 7 }, { docId: 'z1-7' }));
    await assertSucceeds(openIncident(as('n1'), 'n1'));
  });

  test('a new incident follows on from a resolved one, one epoch at a time', async () => {
    await seedZone();
    await seedIncident({ votes: 3, stage: 'resolved', requestedAt: 2, acknowledgedAt: 3, dispatchedAt: 4, resolvedAt: 5, trucks: 1, etaMinutes: 30 }, ['a', 'b', 'c']);
    const next = (n) => ({ id: `z1-${n}`, epoch: n });
    await assertFails(openIncident(as('n1'), 'n1', next(3), { docId: 'z1-3' })); // skips epoch 2
    await assertFails(openIncident(as('n1'), 'n1', next(999999), { docId: 'z1-999999' }));
    await assertSucceeds(openIncident(as('n1'), 'n1', next(2), { docId: 'z1-2' }));
  });

  test('cannot open a new incident while the last one is still going', async () => {
    await seedZone();
    const stages = [
      ['open', { votes: 1 }],
      ['requested', { votes: 3, requestedAt: 2 }],
      ['acknowledged', { votes: 3, requestedAt: 2, acknowledgedAt: 3 }],
      ['dispatched', { votes: 3, requestedAt: 2, acknowledgedAt: 3, dispatchedAt: 4, trucks: 1, etaMinutes: 30 }],
    ];
    for (const [stage, extra] of stages) {
      await seedIncident({ stage, ...extra }, ['a', 'b', 'c']);
      await assertFails(openIncident(as('n1'), 'n1', { id: 'z1-2', epoch: 2 }, { docId: 'z1-2' }));
    }
  });

  test('an invented high epoch cannot mask the real incident, even with a vote inside', async () => {
    await seedZone();
    await seedIncident({ votes: 3, stage: 'requested', requestedAt: 3000 }, ['a', 'b', 'c']);
    const db = as('mallory');
    const b = writeBatch(db);
    b.set(voteRef(db, 'mallory', 'z1-1'), { uid: 'mallory', at: 2000 });
    b.set(voteRef(db, 'mallory', 'z1-999999'), { uid: 'mallory', at: 2000 });
    b.update(incRef(db, 'z1-1'), { votes: 4 });
    b.set(incRef(db, 'z1-999999'), incidentDoc({ id: 'z1-999999', epoch: 999999 }));
    await assertFails(b.commit());
    await assertFails(openIncident(db, 'mallory', { id: 'z1-999999', epoch: 999999 }, { docId: 'z1-999999' }));
  });

  test('one person cannot vote in several incidents of a zone by inventing epochs', async () => {
    await seedZone();
    const db = as('m');
    await assertSucceeds(openIncident(db, 'm'));
    await assertFails(openIncident(db, 'm', { id: 'z1-2', epoch: 2 }, { docId: 'z1-2' }));
    await assertFails(openIncident(db, 'm', { id: 'z1-3', epoch: 3 }, { docId: 'z1-3' }));
  });

  test('the threshold must be the zone\'s own', async () => {
    await seedZone();
    await assertFails(openIncident(as('n1'), 'n1', { threshold: 1 }));
    await assertFails(openIncident(as('n1'), 'n1', { threshold: 2 }));
    await assertFails(openIncident(as('n1'), 'n1', { threshold: 99 }));
  });

  test('it starts with exactly one vote, no progress and no trucks', async () => {
    await seedZone();
    await assertFails(openIncident(as('n1'), 'n1', { votes: 2 }));
    await assertFails(openIncident(as('n1'), 'n1', { votes: 0 }));
    await assertFails(openIncident(as('n1'), 'n1', { stage: 'requested', requestedAt: 5 }));
    await assertFails(openIncident(as('n1'), 'n1', { stage: 'dispatched' }));
    await assertFails(openIncident(as('n1'), 'n1', { requestedAt: 5 }));
    await assertFails(openIncident(as('n1'), 'n1', { acknowledgedAt: 5 }));
    await assertFails(openIncident(as('n1'), 'n1', { trucks: 3 }));
    await assertFails(openIncident(as('n1'), 'n1', { etaMinutes: 30 }));
    await assertFails(openIncident(as('n1'), 'n1', { note: 'trucks are coming' }));
    await assertFails(openIncident(as('n1'), 'n1', { sneaky: true }));
  });

  test('a zone that needs only one voice goes straight to requested', async () => {
    await seedZone({ voteThreshold: 1 });
    await assertFails(openIncident(as('n1'), 'n1', { threshold: 1, stage: 'open' }));
    await assertFails(openIncident(as('n1'), 'n1', { threshold: 1, stage: 'requested', requestedAt: null }));
    await assertSucceeds(openIncident(as('n1'), 'n1', { threshold: 1, stage: 'requested', requestedAt: 1000 }));
  });

  test('the incident must come with the opener\'s own vote document', async () => {
    await seedZone();
    const db = as('n1');
    await assertFails(setDoc(incRef(db), incidentDoc())); // no vote at all
    await assertFails(openIncident(db, 'n1', {}, { voteUid: 'someoneElse' })); // vote filed for another person
  });

  test('cannot overwrite an incident that already exists', async () => {
    await seedZone();
    await seedIncident({ votes: 2 }, ['a', 'b']);
    await assertFails(openIncident(as('n1'), 'n1')); // would reset votes to 1
  });

  test('signed-out users cannot open one', async () => {
    await seedZone();
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(setDoc(incRef(anon), incidentDoc()));
  });
});

// ------------------------------------------------------------------ voting

describe('later voters add one vote', () => {
  test('a second voice moves the counter and stays open', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    await assertSucceeds(castVote(as('n2'), 'n2', { votes: 2, stage: 'open' }));
  });

  test('the vote that reaches the threshold sends it on', async () => {
    await seedZone();
    await seedIncident({ votes: 2 }, ['n1', 'n2']);
    await assertSucceeds(castVote(as('n3'), 'n3', { votes: 3, stage: 'requested', requestedAt: 3000 }));
  });

  test('voters can still add their voice after it was sent on', async () => {
    await seedZone();
    await seedIncident({ votes: 3, stage: 'requested', requestedAt: 3000 }, ['n1', 'n2', 'n3']);
    await assertSucceeds(castVote(as('n4'), 'n4', { votes: 4 }));
  });

  test('sending it on is not optional: crossing the threshold must move the stage', async () => {
    await seedZone();
    await seedIncident({ votes: 2 }, ['n1', 'n2']);
    await assertFails(castVote(as('n3'), 'n3', { votes: 3, stage: 'open' }));
    await assertFails(castVote(as('n3'), 'n3', { votes: 3, stage: 'requested' })); // requestedAt missing
    await assertFails(castVote(as('n3'), 'n3', { votes: 3, requestedAt: 3000 })); // stage left behind
  });

  test('a recovered zone still lets the vote that reaches the threshold through', async () => {
    await seedZone({ latest: 85, readings: [{ t: 1000, level: 85 }] });
    await seedIncident({ votes: 2 }, ['n1', 'n2']);
    await assertSucceeds(castVote(as('n3'), 'n3', { votes: 3, stage: 'requested', requestedAt: 3000 }));
  });

  test('a vote that does not cross the threshold still counts on a recovered zone', async () => {
    await seedZone({ latest: 85, readings: [{ t: 1000, level: 85 }] });
    await seedIncident({}, ['n1']);
    await assertSucceeds(castVote(as('n2'), 'n2', { votes: 2, stage: 'open' }));
  });

  test('the 40% line decides who can open an incident', async () => {
    await seedZone({ latest: 40 });
    await assertFails(openIncident(as('n1'), 'n1'));
    await seedZone({ latest: 39.9 });
    await assertSucceeds(openIncident(as('n1'), 'n1'));
  });

  test('cannot send it on early', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    await assertFails(castVote(as('n2'), 'n2', { votes: 2, stage: 'requested', requestedAt: 2000 }));
    await assertFails(castVote(as('n2'), 'n2', { votes: 2, requestedAt: 2000 }));
  });

  test('cannot bump the counter by more than one', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    await assertFails(castVote(as('n2'), 'n2', { votes: 3, stage: 'requested', requestedAt: 2000 }));
    await assertFails(castVote(as('n2'), 'n2', { votes: 100 }));
  });

  test('cannot lower the counter or leave it where it was', async () => {
    await seedZone();
    await seedIncident({ votes: 2 }, ['n1', 'n2']);
    await assertFails(castVote(as('n3'), 'n3', { votes: 1 }));
    await assertFails(castVote(as('n3'), 'n3', { votes: 2 }));
  });

  test('cannot jump the stage to dispatched, acknowledged or resolved', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    for (const stage of ['dispatched', 'acknowledged', 'resolved']) {
      await assertFails(castVote(as('n2'), 'n2', { votes: 2, stage }));
    }
    await seedIncident({ votes: 3, stage: 'requested', requestedAt: 3000 }, ['n1', 'n2', 'n3']);
    await assertFails(castVote(as('n4'), 'n4', { votes: 4, stage: 'dispatched', dispatchedAt: 1, trucks: 1, etaMinutes: 1 }));
    await assertFails(castVote(as('n4'), 'n4', { votes: 4, stage: 'open' }));
  });

  test('a vote cannot change anything but the counter, stage and request time', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    for (const extra of [
      { threshold: 1 },
      { trucks: 5 },
      { etaMinutes: 10 },
      { note: 'hello' },
      { zoneId: 'z2' },
      { epoch: 9 },
      { openedAt: 1 },
      { acknowledgedAt: 5 },
      { dispatchedAt: 5 },
      { resolvedAt: 5 },
      { sneaky: true },
    ]) {
      await assertFails(castVote(as('n2'), 'n2', { votes: 2, ...extra }));
    }
  });

  test('cannot vote twice', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    // The opener again: their vote document already exists, so it cannot be created.
    await assertFails(castVote(as('n1'), 'n1', { votes: 2 }));
    // Bumping the counter without writing a vote document.
    await assertFails(castVote(as('n1'), 'n1', { votes: 2 }, { voteDoc: false }));
    // A second voter, then the second voter again.
    await assertSucceeds(castVote(as('n2'), 'n2', { votes: 2 }));
    await assertFails(castVote(as('n2'), 'n2', { votes: 3, stage: 'requested', requestedAt: 3000 }));
  });

  test('cannot vote twice by rewriting your own vote document', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    const db = as('n1');
    const b = writeBatch(db);
    b.update(voteRef(db, 'n1'), { at: 5000 });
    b.update(incRef(db), { votes: 2 });
    await assertFails(b.commit());
  });

  test('cannot vote with a counter bump and no vote document', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    await assertFails(updateDoc(incRef(as('n2')), { votes: 2 }));
  });

  test('cannot file a vote under someone else\'s uid', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    await assertFails(castVote(as('mallory'), 'mallory', { votes: 2 }, { voteUid: 'victim' }));
    await assertFails(
      castVote(as('mallory'), 'mallory', { votes: 2 }, { voteData: { uid: 'victim', at: 2000 } }),
    );
  });

  test('cannot vote once the provider has taken it on', async () => {
    await seedZone();
    for (const [stage, extra] of [
      ['acknowledged', { requestedAt: 3000, acknowledgedAt: 4000 }],
      ['dispatched', { requestedAt: 3000, dispatchedAt: 5000, trucks: 2, etaMinutes: 60 }],
      ['resolved', { requestedAt: 3000, dispatchedAt: 5000, resolvedAt: 6000, trucks: 2, etaMinutes: 60 }],
    ]) {
      await seedIncident({ stage, votes: 3, ...extra }, ['n1', 'n2', 'n3']);
      await assertFails(castVote(as('n4'), 'n4', { votes: 4 }));
    }
  });

  test('a stand-alone vote document is refused', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    await assertFails(setDoc(voteRef(as('n2'), 'n2'), { uid: 'n2', at: 2000 }));
  });

  test('a vote document needs a counter that moved with it', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    const db = as('n2');
    const b = writeBatch(db);
    b.set(voteRef(db, 'n2'), { uid: 'n2', at: 2000 });
    b.update(incRef(db), { votes: 1 }); // nothing moved
    await assertFails(b.commit());
  });

  test('a vote document cannot be filed for an incident that does not exist', async () => {
    await assertFails(setDoc(voteRef(as('n1'), 'n1', 'z9-1'), { uid: 'n1', at: 1000 }));
  });

  test('a vote document must carry the voter\'s own uid and nothing else', async () => {
    await seedZone();
    await assertFails(openIncident(as('n1'), 'n1', {}, { voteData: { uid: 'n2', at: 1000 } }));
    await assertFails(openIncident(as('n1'), 'n1', {}, { voteData: { uid: 'n1', at: 'now' } }));
    await assertFails(openIncident(as('n1'), 'n1', {}, { voteData: { uid: 'n1', at: 1000, extra: 1 } }));
  });

  test('vote documents are private, permanent and cannot be edited', async () => {
    await seedZone();
    await seedIncident({}, ['n1']);
    await assertSucceeds(getDoc(voteRef(as('n1'), 'n1')));
    await assertFails(getDoc(voteRef(as('n2'), 'n1')));
    await assertFails(updateDoc(voteRef(as('n1'), 'n1'), { at: 1 }));
    await assertFails(deleteDoc(voteRef(as('n1'), 'n1')));
    // Checking before voting: a missing vote document is readable by its would-be owner.
    await assertSucceeds(getDoc(voteRef(as('n2'), 'n2')));
  });

  test('anyone signed in can read an incident; signed-out users cannot', async () => {
    await seedIncident({}, ['n1']);
    await assertSucceeds(getDoc(incRef(as('anyone'))));
    await assertFails(getDoc(incRef(env.unauthenticatedContext().firestore())));
  });
});

// ---------------------------------------------------------- the provider acts

describe('the provider moves an incident forward', () => {
  const requested = { votes: 3, stage: 'requested', requestedAt: 3000 };
  const acknowledged = { ...requested, stage: 'acknowledged', acknowledgedAt: 4000 };
  const dispatched = { ...acknowledged, stage: 'dispatched', dispatchedAt: 5000, trucks: 2, etaMinutes: 90 };
  const dispatchChange = { stage: 'dispatched', dispatchedAt: 5000, trucks: 2, etaMinutes: 90, note: 'Two 10 kL tankers' };

  test('requested to acknowledged', async () => {
    await seedIncident(requested);
    await assertSucceeds(updateDoc(incRef(provider()), { stage: 'acknowledged', acknowledgedAt: 4000 }));
  });

  test('acknowledged to dispatched, with trucks, ETA and a note', async () => {
    await seedIncident(acknowledged);
    await assertSucceeds(updateDoc(incRef(provider()), dispatchChange));
  });

  test('requested straight to dispatched (acknowledging is optional)', async () => {
    await seedIncident(requested);
    await assertSucceeds(updateDoc(incRef(provider()), dispatchChange));
  });

  test('dispatched to resolved', async () => {
    await seedIncident(dispatched);
    await assertSucceeds(updateDoc(incRef(provider()), { stage: 'resolved', resolvedAt: 6000 }));
  });

  test('a threshold-one incident can go all the way through', async () => {
    await seedZone({ voteThreshold: 1 });
    await assertSucceeds(openIncident(as('n1'), 'n1', { threshold: 1, stage: 'requested', requestedAt: 1000 }));
    await assertSucceeds(updateDoc(incRef(provider()), dispatchChange));
    await assertSucceeds(updateDoc(incRef(provider()), { stage: 'resolved', resolvedAt: 6000 }));
  });

  test('it cannot skip a step', async () => {
    await seedIncident({}); // open
    await assertFails(updateDoc(incRef(provider()), { stage: 'acknowledged', acknowledgedAt: 4000 }));
    await assertFails(updateDoc(incRef(provider()), dispatchChange));
    await assertFails(updateDoc(incRef(provider()), { stage: 'resolved', resolvedAt: 6000 }));
    await seedIncident(requested);
    await assertFails(updateDoc(incRef(provider()), { stage: 'resolved', resolvedAt: 6000 }));
    await seedIncident(acknowledged);
    await assertFails(updateDoc(incRef(provider()), { stage: 'resolved', resolvedAt: 6000 }));
  });

  test('it cannot send an open request on itself, or go backwards, or repeat a step', async () => {
    await seedIncident({});
    await assertFails(updateDoc(incRef(provider()), { stage: 'requested', requestedAt: 2000 }));
    await seedIncident(dispatched);
    await assertFails(updateDoc(incRef(provider()), { stage: 'acknowledged', acknowledgedAt: 4500 }));
    await assertFails(updateDoc(incRef(provider()), { stage: 'requested' }));
    await assertFails(updateDoc(incRef(provider()), { ...dispatchChange, trucks: 3 })); // dispatch twice
    await seedIncident(acknowledged);
    await assertFails(updateDoc(incRef(provider()), { stage: 'acknowledged', acknowledgedAt: 4500 }));
  });

  test('a resolved incident is final', async () => {
    await seedIncident({ ...dispatched, stage: 'resolved', resolvedAt: 6000 });
    await assertFails(updateDoc(incRef(provider()), { stage: 'dispatched' }));
    await assertFails(updateDoc(incRef(provider()), { stage: 'resolved', resolvedAt: 7000 }));
    await assertFails(updateDoc(incRef(provider()), { note: 'edited later' }));
  });

  test('trucks must be a whole number from 1 to 20', async () => {
    await seedIncident(requested);
    for (const trucks of [0, -1, 21, 2.5, '2', null]) {
      await assertFails(updateDoc(incRef(provider()), { ...dispatchChange, trucks }));
    }
    await assertSucceeds(updateDoc(incRef(provider()), { ...dispatchChange, trucks: 20 }));
  });

  test('trucks at the lower bound, and no trucks at all', async () => {
    await seedIncident(requested);
    const { trucks, ...noTrucks } = dispatchChange;
    await assertFails(updateDoc(incRef(provider()), noTrucks)); // trucks stays 0
    await assertSucceeds(updateDoc(incRef(provider()), { ...dispatchChange, trucks: 1 }));
  });

  test('ETA must be a whole number of minutes from 1 to 1440', async () => {
    await seedIncident(requested);
    for (const etaMinutes of [0, -5, 1441, 30.5, '30', null]) {
      await assertFails(updateDoc(incRef(provider()), { ...dispatchChange, etaMinutes }));
    }
    await assertSucceeds(updateDoc(incRef(provider()), { ...dispatchChange, etaMinutes: 1440 }));
  });

  test('the note is text of at most 280 characters', async () => {
    await seedIncident(requested);
    await assertFails(updateDoc(incRef(provider()), { ...dispatchChange, note: 'x'.repeat(281) }));
    await assertFails(updateDoc(incRef(provider()), { ...dispatchChange, note: 42 }));
    await assertSucceeds(updateDoc(incRef(provider()), { ...dispatchChange, note: 'x'.repeat(280) }));
  });

  test('a dispatch needs its timestamp', async () => {
    await seedIncident(requested);
    await assertFails(updateDoc(incRef(provider()), { ...dispatchChange, dispatchedAt: null }));
    await assertFails(updateDoc(incRef(provider()), { ...dispatchChange, dispatchedAt: 'soon' }));
  });

  test('each step changes only its own fields', async () => {
    await seedIncident(requested);
    await assertFails(updateDoc(incRef(provider()), { stage: 'acknowledged', acknowledgedAt: 4000, votes: 50 }));
    await assertFails(updateDoc(incRef(provider()), { stage: 'acknowledged', acknowledgedAt: 4000, threshold: 1 }));
    await assertFails(updateDoc(incRef(provider()), { stage: 'acknowledged', acknowledgedAt: 4000, trucks: 4 }));
    await assertFails(updateDoc(incRef(provider()), { stage: 'acknowledged', acknowledgedAt: 4000, requestedAt: 1 }));
    await assertFails(updateDoc(incRef(provider()), { ...dispatchChange, votes: 50 }));
    await assertFails(updateDoc(incRef(provider()), { ...dispatchChange, zoneId: 'z2' }));
    await assertFails(updateDoc(incRef(provider()), { ...dispatchChange, resolvedAt: 9 }));
    await seedIncident(dispatched);
    await assertFails(updateDoc(incRef(provider()), { stage: 'resolved', resolvedAt: 6000, trucks: 9 }));
    await assertFails(updateDoc(incRef(provider()), { stage: 'resolved', resolvedAt: 6000, note: 'edited' }));
    await assertFails(updateDoc(incRef(provider()), { stage: 'resolved', resolvedAt: 6000, etaMinutes: 1 }));
  });

  test('a step needs its timestamp', async () => {
    await seedIncident(requested);
    await assertFails(updateDoc(incRef(provider()), { stage: 'acknowledged' }));
    await seedIncident(dispatched);
    await assertFails(updateDoc(incRef(provider()), { stage: 'resolved' }));
    await assertFails(updateDoc(incRef(provider()), { stage: 'resolved', resolvedAt: 'later' }));
  });

  test('nobody else can acknowledge, dispatch or resolve', async () => {
    for (const who of [as('n1'), as('farmer'), as('x', { utility: false }), as('x', { utility: 'true' }), as('x', { mediator: true })]) {
      await seedIncident(requested);
      await assertFails(updateDoc(incRef(who), { stage: 'acknowledged', acknowledgedAt: 4000 }));
      await assertFails(updateDoc(incRef(who), dispatchChange));
      await seedIncident(dispatched);
      await assertFails(updateDoc(incRef(who), { stage: 'resolved', resolvedAt: 6000 }));
    }
  });

  test('voters cannot touch trucks, ETA or notes', async () => {
    await seedIncident(requested, ['n1', 'n2', 'n3']);
    await assertFails(castVote(as('n4'), 'n4', { votes: 4, trucks: 20, etaMinutes: 1, note: 'on my way' }));
    await assertFails(updateDoc(incRef(as('n1')), { trucks: 20 }));
    await assertFails(updateDoc(incRef(as('n1')), { note: 'x' }));
  });

  test('the provider cannot open an incident without a vote of its own', async () => {
    await seedZone();
    await assertFails(setDoc(incRef(provider()), incidentDoc()));
  });
});

// ----------------------------------------------------------------- deletion

describe('nothing in the water module can be deleted', () => {
  test('incidents', async () => {
    await seedIncident({ votes: 3, stage: 'requested', requestedAt: 3000 }, ['n1']);
    for (const db of [as('n1'), as('other'), provider()]) {
      await assertFails(deleteDoc(incRef(db)));
    }
  });

  test('votes', async () => {
    await seedIncident({}, ['n1']);
    await assertFails(deleteDoc(voteRef(as('n1'), 'n1')));
    await assertFails(deleteDoc(voteRef(provider(), 'n1')));
  });
});

// ------------------------------------------------------------------- prefs

describe('water preferences', () => {
  const prefs = (over = {}) => ({ zoneId: 'z1', household: 4, tankLitres: 5000, herd: 0, ...over });

  test('only the owner can read or write', async () => {
    await assertSucceeds(setDoc(doc(as('a'), 'waterPrefs', 'a'), prefs()));
    await assertSucceeds(getDoc(doc(as('a'), 'waterPrefs', 'a')));
    await assertFails(getDoc(doc(as('b'), 'waterPrefs', 'a')));
    await assertFails(setDoc(doc(as('b'), 'waterPrefs', 'a'), prefs()));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'waterPrefs', 'a')));
  });

  test('the provider cannot read them either', async () => {
    await assertSucceeds(setDoc(doc(as('a'), 'waterPrefs', 'a'), prefs()));
    await assertFails(getDoc(doc(provider(), 'waterPrefs', 'a')));
  });

  test('zone can be unset; values must be sensible whole numbers', async () => {
    const put = (over) => setDoc(doc(as('a'), 'waterPrefs', 'a'), prefs(over));
    await assertSucceeds(put({ zoneId: null }));
    await assertSucceeds(put({ herd: 120, tankLitres: 0 }));
    await assertFails(put({ household: -1 }));
    await assertFails(put({ household: 'four' }));
    await assertFails(put({ tankLitres: -10 }));
    await assertFails(put({ tankLitres: 1.5 }));
    await assertFails(put({ herd: 10000000 }));
    await assertFails(put({ zoneId: 7 }));
    await assertFails(put({ sneaky: true }));
  });

  test('the owner can erase their own', async () => {
    await assertSucceeds(setDoc(doc(as('a'), 'waterPrefs', 'a'), prefs()));
    await assertFails(deleteDoc(doc(as('b'), 'waterPrefs', 'a')));
    await assertSucceeds(deleteDoc(doc(as('a'), 'waterPrefs', 'a')));
  });
});

// ----------------------------------------------------------- product stock

describe('product stock', () => {
  const product = (over = {}) => ({ id: 'p1', name: 'Carrots', price: 60, ownerId: 'farmer', ...over });
  const put = (over, uid = 'farmer') => setDoc(doc(as(uid), 'marketProducts', 'p1'), product(over));

  test('stock is optional, and null means not tracked', async () => {
    await assertSucceeds(put({}));
    await assertSucceeds(put({ stock: null }));
  });

  test('a whole number from 0 to 100000 is accepted', async () => {
    for (const stock of [0, 1, 12, 100000]) await assertSucceeds(put({ stock }));
  });

  test('anything else is refused', async () => {
    for (const stock of [-1, 100001, 1e9, 1.5, '12', true, [], {}]) await assertFails(put({ stock }));
  });

  test('available must be true or false when present', async () => {
    await assertSucceeds(put({ available: true }));
    await assertSucceeds(put({ available: false }));
    for (const available of ['yes', 1, 0, null]) await assertFails(put({ available }));
  });

  test('the owner restocks or pauses a listing; bad values are still refused on update', async () => {
    await assertSucceeds(put({ stock: 10, available: true }));
    const ref = doc(as('farmer'), 'marketProducts', 'p1');
    await assertSucceeds(updateDoc(ref, { stock: 25 }));
    await assertSucceeds(updateDoc(ref, { available: false }));
    await assertSucceeds(updateDoc(ref, { stock: null }));
    await assertFails(updateDoc(ref, { stock: -3 }));
    await assertFails(updateDoc(ref, { stock: 100001 }));
    await assertFails(updateDoc(ref, { stock: 2.5 }));
    await assertFails(updateDoc(ref, { available: 'no' }));
  });

  test('only the owner can change stock, and nobody can create stock in someone else\'s name', async () => {
    await assertSucceeds(put({ stock: 10 }));
    await assertFails(updateDoc(doc(as('buyer'), 'marketProducts', 'p1'), { stock: 0 }));
    await assertFails(updateDoc(doc(as('buyer'), 'marketProducts', 'p1'), { stock: 9999 }));
    await assertFails(put({ stock: 10 }, 'buyer'));
  });
});
