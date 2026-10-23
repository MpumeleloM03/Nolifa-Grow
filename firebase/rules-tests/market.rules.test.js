// Security rules tests for the Nolifa Drop marketplace.
// Run with:  npm test   (needs Java; starts the Firestore emulator itself)
import { test, before, beforeEach, after, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ubuntu-drop',
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

const order = (over = {}) => ({
  id: 'o1',
  lines: [{ name: 'Eggs', qty: 1, price: 80, ownerId: 'farmer' }],
  deliveryFee: 25,
  serviceFee: 3.15,
  commission: 0.08,
  method: 'fnbPay',
  status: 'newOrder',
  customer: 'Buyer',
  pickup: 'Farm',
  dropArea: 'Street',
  pinHash: 'abc123',
  driver: null,
  customerId: 'buyer',
  farmerId: 'farmer',
  driverId: null,
  participants: ['buyer', 'farmer'],
  pickupProof: false,
  pinAttempts: 0,
  released: false,
  placed: 1,
  deliveredAt: null,
  dispute: null,
  rating: 0,
  rev: 0,
  ...over,
});

/** Writes an order directly, bypassing rules, to set up a scenario. */
const seed = (data) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'marketOrders', data.id), data);
  });

const seedProfile = (uid, plan) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'marketProfiles', uid), { state: { plan } });
  });

const ref = (db, id = 'o1') => doc(db, 'marketOrders', id);

describe('private profiles', () => {
  test('only the owner can read or write', async () => {
    await assertSucceeds(setDoc(doc(as('a'), 'marketProfiles', 'a'), { state: { plan: 'free' } }));
    await assertSucceeds(getDoc(doc(as('a'), 'marketProfiles', 'a')));
    await assertFails(getDoc(doc(as('b'), 'marketProfiles', 'a')));
    await assertFails(setDoc(doc(as('b'), 'marketProfiles', 'a'), { state: {} }));
  });

  test('signed-out users get nothing', async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'marketProfiles', 'a')));
    await assertFails(getDoc(doc(anon, 'marketProducts', 'p')));
  });
});

describe('products', () => {
  const product = (over = {}) => ({ id: 'p1', name: 'Carrots', price: 60, ownerId: 'farmer', ...over });

  test('a farmer lists as themselves, everyone can browse', async () => {
    await assertSucceeds(setDoc(doc(as('farmer'), 'marketProducts', 'p1'), product()));
    await assertSucceeds(getDoc(doc(as('buyer'), 'marketProducts', 'p1')));
  });

  test('cannot list in someone else\'s name, or with a bad price', async () => {
    await assertFails(setDoc(doc(as('buyer'), 'marketProducts', 'p1'), product()));
    await assertFails(setDoc(doc(as('farmer'), 'marketProducts', 'p1'), product({ price: -5 })));
    await assertFails(setDoc(doc(as('farmer'), 'marketProducts', 'p1'), product({ price: 999999 })));
    await assertFails(setDoc(doc(as('farmer'), 'marketProducts', 'p1'), product({ name: '' })));
  });

  test('only the owner can change a listing', async () => {
    await assertSucceeds(setDoc(doc(as('farmer'), 'marketProducts', 'p1'), product()));
    await assertFails(updateDoc(doc(as('buyer'), 'marketProducts', 'p1'), { price: 1 }));
    await assertSucceeds(updateDoc(doc(as('farmer'), 'marketProducts', 'p1'), { price: 70 }));
  });
});

describe('creating and reading orders', () => {
  test('a buyer creates their own order', async () => {
    await assertSucceeds(setDoc(ref(as('buyer')), order()));
  });

  test('cannot create an order as someone else', async () => {
    await assertFails(setDoc(ref(as('mallory')), order()));
  });

  test('cannot create an order that is already paid out, disputed or assigned', async () => {
    await assertFails(setDoc(ref(as('buyer')), order({ released: true })));
    await assertFails(setDoc(ref(as('buyer')), order({ driverId: 'buyer' })));
    await assertFails(setDoc(ref(as('buyer')), order({ status: 'delivered' })));
    await assertFails(
      setDoc(ref(as('buyer')), order({ dispute: { stage: 'resolved', outcome: 'fullRefund' } })),
    );
  });

  test('cannot create an order without a PIN hash or with no items', async () => {
    const { pinHash, ...noPin } = order();
    await assertFails(setDoc(ref(as('buyer')), noPin));
    await assertFails(setDoc(ref(as('buyer')), order({ lines: [] })));
  });

  test('participants read; strangers do not', async () => {
    await seed(order());
    await assertSucceeds(getDoc(ref(as('buyer'))));
    await assertSucceeds(getDoc(ref(as('farmer'))));
    await assertFails(getDoc(ref(as('mallory'))));
  });

  test('open jobs are visible to any driver, assigned ones are not', async () => {
    await seed(order({ status: 'findingDriver' }));
    await assertSucceeds(getDoc(ref(as('anyDriver'))));
    await seed(order({ status: 'assigned', driverId: 'd1', participants: ['buyer', 'farmer', 'd1'] }));
    await assertFails(getDoc(ref(as('anyDriver'))));
    await assertSucceeds(getDoc(ref(as('d1'))));
  });

  test('a missing order can be checked before creating it, but others\' orders stay private', async () => {
    await assertSucceeds(getDoc(ref(as('buyer'), 'does-not-exist')));
    await seed(order());
    await assertFails(getDoc(ref(as('mallory'))));
  });

  test('orders can never be deleted', async () => {
    await seed(order());
    const { deleteDoc } = await import('firebase/firestore');
    await assertFails(deleteDoc(ref(as('buyer'))));
    await assertFails(deleteDoc(ref(as('farmer'))));
  });
});

describe('money cannot be edited', () => {
  for (const [field, value] of [
    ['deliveryFee', 1],
    ['serviceFee', 0],
    ['lines', []],
    ['pinHash', 'known'],
    ['customerId', 'mallory'],
    ['farmerId', 'mallory'],
  ]) {
    test(`nobody can change ${field}`, async () => {
      await seed(order({ status: 'findingDriver' }));
      for (const uid of ['buyer', 'farmer', 'mallory']) {
        await assertFails(updateDoc(ref(as(uid)), { [field]: value, rev: 1 }));
      }
    });
  }
});

describe('farmer packs an order', () => {
  test('commission is locked to their plan', async () => {
    await seedProfile('farmer', 'grow');
    await seed(order());
    await assertFails(updateDoc(ref(as('farmer')), { status: 'findingDriver', commission: 0, rev: 1 }));
    await assertFails(updateDoc(ref(as('farmer')), { status: 'findingDriver', commission: 0.08, rev: 1 }));
    await assertSucceeds(updateDoc(ref(as('farmer')), { status: 'findingDriver', commission: 0.05, rev: 1 }));
  });

  test('only the farmer on the order can pack it', async () => {
    await seedProfile('farmer', 'free');
    await seed(order());
    await assertFails(updateDoc(ref(as('buyer')), { status: 'findingDriver', commission: 0.08, rev: 1 }));
    await assertFails(updateDoc(ref(as('mallory')), { status: 'findingDriver', commission: 0.08, rev: 1 }));
  });
});

describe('driver flow', () => {
  const open = () => order({ status: 'findingDriver' });

  test('a driver claims an open job for themselves', async () => {
    await seed(open());
    await assertSucceeds(
      updateDoc(ref(as('d1')), {
        status: 'assigned',
        driver: 'D1',
        driverId: 'd1',
        participants: ['buyer', 'farmer', 'd1'],
        rev: 1,
      }),
    );
  });

  test('cannot claim in someone else\'s name or take a job that is already taken', async () => {
    await seed(open());
    await assertFails(
      updateDoc(ref(as('d1')), {
        status: 'assigned', driver: 'x', driverId: 'd2', participants: ['buyer', 'farmer', 'd2'], rev: 1,
      }),
    );
    await seed(order({ status: 'assigned', driverId: 'd1', participants: ['buyer', 'farmer', 'd1'] }));
    await assertFails(
      updateDoc(ref(as('d2')), {
        driverId: 'd2', participants: ['buyer', 'farmer', 'd2'], rev: 2,
      }),
    );
  });

  test('pickup needs the photo, delivery needs pickup', async () => {
    const assigned = order({ status: 'assigned', driverId: 'd1', participants: ['buyer', 'farmer', 'd1'] });
    await seed(assigned);
    await assertFails(updateDoc(ref(as('d1')), { status: 'pickedUp', pickupProof: false, rev: 1 }));
    await assertFails(updateDoc(ref(as('d1')), { status: 'delivered', deliveredAt: 5, rev: 1 }));
    await assertSucceeds(updateDoc(ref(as('d1')), { status: 'pickedUp', pickupProof: true, rev: 1 }));
    await assertSucceeds(updateDoc(ref(as('d1')), { status: 'delivered', deliveredAt: 5, rev: 2 }));
  });

  test('a driver can never release money or touch a dispute', async () => {
    await seed(order({ status: 'delivered', driverId: 'd1', deliveredAt: Date.now(), participants: ['buyer', 'farmer', 'd1'] }));
    await assertFails(updateDoc(ref(as('d1')), { released: true, rev: 1 }));
    await assertFails(updateDoc(ref(as('d1')), { dispute: { stage: 'resolved', outcome: 'released' }, rev: 1 }));
  });

  test('a different driver cannot progress the order', async () => {
    await seed(order({ status: 'assigned', driverId: 'd1', participants: ['buyer', 'farmer', 'd1'] }));
    await assertFails(updateDoc(ref(as('d2')), { status: 'pickedUp', pickupProof: true, rev: 1 }));
  });
});

describe('delivery PIN attempts', () => {
  const inTransit = (over = {}) =>
    order({ status: 'pickedUp', driverId: 'd1', pickupProof: true, participants: ['buyer', 'farmer', 'd1'], ...over });

  test('a wrong PIN can only add one try at a time', async () => {
    await seed(inTransit());
    await assertSucceeds(updateDoc(ref(as('d1')), { pinAttempts: 1, rev: 1 }));
    await assertFails(updateDoc(ref(as('d1')), { pinAttempts: 0, rev: 2 }), 'cannot reset the count');
    await assertFails(updateDoc(ref(as('d1')), { pinAttempts: 3, rev: 2 }), 'cannot skip ahead');
    await assertSucceeds(updateDoc(ref(as('d1')), { pinAttempts: 2, rev: 2 }));
  });

  test('the third wrong try must open a pinLocked dispute with it', async () => {
    await seed(inTransit({ pinAttempts: 2 }));
    await assertFails(updateDoc(ref(as('d1')), { pinAttempts: 3, rev: 1 }), 'locking without a dispute is refused');
    await assertFails(
      updateDoc(ref(as('d1')), { pinAttempts: 3, dispute: { reason: 'late', stage: 'open', outcome: null }, rev: 1 }),
      'the dispute must be the PIN one',
    );
    await assertSucceeds(
      updateDoc(ref(as('d1')), {
        pinAttempts: 3,
        dispute: { reason: 'pinLocked', stage: 'open', outcome: null, note: '', timeline: [] },
        rev: 1,
      }),
    );
  });

  test('once locked the driver cannot deliver, and only the driver on the order can count tries', async () => {
    await seed(inTransit({ pinAttempts: 3, dispute: { reason: 'pinLocked', stage: 'open', outcome: null } }));
    await assertFails(updateDoc(ref(as('d1')), { status: 'delivered', deliveredAt: 5, rev: 1 }));
    await seed(inTransit({ id: 'o2' }));
    await assertFails(updateDoc(ref(as('d2'), 'o2'), { pinAttempts: 1, rev: 1 }));
    await assertFails(updateDoc(ref(as('buyer'), 'o2'), { pinAttempts: 1, rev: 1 }));
  });
});

describe('buyer protection', () => {
  const delivered = (over = {}) =>
    order({ status: 'delivered', driverId: 'd1', deliveredAt: Date.now(), participants: ['buyer', 'farmer', 'd1'], ...over });

  test('buyer confirms only after delivery', async () => {
    await seed(order({ status: 'pickedUp', driverId: 'd1', participants: ['buyer', 'farmer', 'd1'] }));
    await assertFails(updateDoc(ref(as('buyer')), { released: true, rev: 1 }));
    await seed(delivered());
    await assertSucceeds(updateDoc(ref(as('buyer')), { released: true, rating: 5, rev: 1 }));
  });

  test('the farmer cannot release early; anyone on the order can after two hours', async () => {
    await seed(delivered());
    await assertFails(updateDoc(ref(as('farmer')), { released: true, rev: 1 }));
    await assertFails(updateDoc(ref(as('d1')), { released: true, rev: 1 }));
    await seed(delivered({ deliveredAt: Date.now() - 3 * 3600 * 1000 }));
    await assertSucceeds(updateDoc(ref(as('farmer')), { released: true, rev: 1 }));
  });

  test('a stranger can never release', async () => {
    await seed(delivered({ deliveredAt: Date.now() - 9 * 3600 * 1000 }));
    await assertFails(updateDoc(ref(as('mallory')), { released: true, rev: 1 }));
  });

  test('the buyer opens a dispute, which freezes payment', async () => {
    await seed(delivered());
    await assertSucceeds(
      updateDoc(ref(as('buyer')), {
        dispute: { reason: 'damaged', note: '', stage: 'open', outcome: null, timeline: [] },
        rev: 1,
      }),
    );
  });

  test('only the buyer can open a dispute, and not with a ready-made outcome', async () => {
    await seed(delivered());
    const d = { reason: 'damaged', note: '', stage: 'open', outcome: null, timeline: [] };
    await assertFails(updateDoc(ref(as('farmer')), { dispute: d, rev: 1 }));
    await assertFails(updateDoc(ref(as('buyer')), { dispute: { ...d, outcome: 'fullRefund' }, rev: 1 }));
    await assertFails(updateDoc(ref(as('buyer')), { dispute: { ...d, stage: 'resolved' }, rev: 1 }));
  });

  test('a disputed order cannot be released by anyone but a mediator', async () => {
    const d = { reason: 'damaged', stage: 'open', outcome: null, timeline: [] };
    await seed(delivered({ dispute: d, deliveredAt: Date.now() - 9 * 3600 * 1000 }));
    await assertFails(updateDoc(ref(as('buyer')), { released: true, rev: 1 }));
    await assertFails(updateDoc(ref(as('farmer')), { released: true, rev: 1 }));
    await assertFails(
      updateDoc(ref(as('buyer')), { dispute: { ...d, stage: 'resolved', outcome: 'released' }, released: true, rev: 1 }),
    );
    await assertSucceeds(
      updateDoc(ref(as('med1', { mediator: true })), {
        dispute: { ...d, stage: 'resolved', outcome: 'fullRefund' },
        released: true,
        rev: 1,
      }),
    );
  });

  test('a mediator still cannot change the money on an order', async () => {
    const d = { reason: 'damaged', stage: 'open', outcome: null, timeline: [] };
    await seed(delivered({ dispute: d }));
    await assertFails(updateDoc(ref(as('med1', { mediator: true })), { deliveryFee: 0, rev: 1 }));
  });
});

describe('outbreak cases', () => {
  const c = (over = {}) => ({
    id: 'c1',
    title: 'Leaf rust',
    area: 'Hillcrest',
    stage: 'aiChecked',
    confirmations: 0,
    confirmedBy: [],
    aiConfidence: 78,
    reporterId: 'r',
    ...over,
  });
  const cref = (db) => doc(db, 'marketCases', 'c1');

  test('file a case as yourself, starting unverified', async () => {
    await assertSucceeds(setDoc(cref(as('r')), c()));
    await assertFails(setDoc(cref(as('mallory')), c()));
    await assertFails(setDoc(cref(as('r')), c({ stage: 'vetVerified' })));
    await assertFails(setDoc(cref(as('r')), c({ confirmations: 5 })));
    await assertFails(setDoc(cref(as('r')), c({ title: '' })));
  });

  test('neighbours confirm once each, and the reporter cannot confirm their own', async () => {
    await assertSucceeds(setDoc(cref(as('r')), c()));
    await assertFails(
      updateDoc(cref(as('r')), { confirmedBy: ['r'], confirmations: 1 }),
    );
    await assertSucceeds(updateDoc(cref(as('n1')), { confirmedBy: ['n1'], confirmations: 1 }));
    await assertFails(
      updateDoc(cref(as('n1')), { confirmedBy: ['n1', 'n1'], confirmations: 2 }),
    );
    await assertFails(
      updateDoc(cref(as('n2')), { confirmedBy: ['n1', 'n2'], confirmations: 5 }),
    );
    await assertSucceeds(
      updateDoc(cref(as('n2')), { confirmedBy: ['n1', 'n2'], confirmations: 2, stage: 'corroborated' }),
    );
  });

  test('an unverified account cannot confirm a case, however many accounts it makes', async () => {
    await assertSucceeds(setDoc(cref(as('r')), c()));
    await assertFails(updateDoc(cref(as('fake1', { verified: false })), { confirmedBy: ['fake1'], confirmations: 1 }));
    await assertFails(updateDoc(cref(as('fake2', { verified: false })), { confirmedBy: ['fake2'], confirmations: 1 }));
    await assertSucceeds(updateDoc(cref(as('real')), { confirmedBy: ['real'], confirmations: 1 }));
  });

  test('a neighbour cannot jump a case to vet verified', async () => {
    await assertSucceeds(setDoc(cref(as('r')), c()));
    await assertFails(
      updateDoc(cref(as('n1')), { confirmedBy: ['n1'], confirmations: 1, stage: 'vetVerified' }),
    );
    await assertFails(updateDoc(cref(as('r')), { stage: 'vetVerified' }));
  });

  test('only a vet can verify or reject', async () => {
    await assertSucceeds(setDoc(cref(as('r')), c()));
    await assertSucceeds(updateDoc(cref(as('vet1', { vet: true })), { stage: 'vetVerified' }));
  });

  test('cases are public to read and never deleted', async () => {
    await assertSucceeds(setDoc(cref(as('r')), c()));
    await assertSucceeds(getDoc(cref(as('anyone'))));
    const { deleteDoc } = await import('firebase/firestore');
    await assertFails(deleteDoc(cref(as('r'))));
  });
});
