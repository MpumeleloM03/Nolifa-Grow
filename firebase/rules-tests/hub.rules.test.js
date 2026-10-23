// Security rules tests for hub orders: farm drop-off, hub check-in and release.
// Run with:  npm test   (needs Java; starts the Firestore emulator itself)
import { test, before, beforeEach, after, describe } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ubuntu-drop-hub',
    firestore: { rules: readFileSync('../../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8089 },
  });
});
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const as = (uid, claims = {}) => env.authenticatedContext(uid, { verified: true, ...claims }).firestore();
const staff = () => as('hubby', { hub: true });

const order = (over = {}) => ({
  id: 'o1',
  lines: [{ name: 'Spinach', qty: 2, price: 20, ownerId: 'farmer' }],
  deliveryFee: 35,
  serviceFee: 2,
  commission: 0.08,
  method: 'fnbPay',
  status: 'findingDriver',
  customer: 'Buyer',
  pickup: 'Farm',
  dropArea: 'Umlazi',
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
  route: 'hub',
  hub: 'Durban hub',
  hubStage: 'toHub',
  rev: 0,
  ...over,
});

const seed = (over = {}) =>
  env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'marketOrders', 'o1'), order(over)));
const ref = (db) => doc(db, 'marketOrders', 'o1');

describe('farm drop-off', () => {
  test('the selling farm can say it dropped the order at the hub', async () => {
    await seed();
    await assertSucceeds(updateDoc(ref(as('farmer')), { hubStage: 'droppedOff', rev: 1 }));
  });
  test('nobody else can', async () => {
    await seed();
    await assertFails(updateDoc(ref(as('buyer')), { hubStage: 'droppedOff', rev: 1 }));
    await assertFails(updateDoc(ref(as('stranger')), { hubStage: 'droppedOff', rev: 1 }));
  });
  test('the farm cannot skip the hub check or release its own order', async () => {
    await seed();
    await assertFails(updateDoc(ref(as('farmer')), { hubStage: 'received', rev: 1 }));
    await assertFails(updateDoc(ref(as('farmer')), { hubStage: 'released', rev: 1 }));
  });
});

describe('hub staff', () => {
  test('staff can check in a dropped order, then release it', async () => {
    await seed({ hubStage: 'droppedOff' });
    await assertSucceeds(updateDoc(ref(staff()), { hubStage: 'received', rev: 1 }));
    await assertSucceeds(updateDoc(ref(staff()), { hubStage: 'released', rev: 2 }));
  });
  test('staff cannot release an order that has not been checked in', async () => {
    await seed({ hubStage: 'droppedOff' });
    await assertFails(updateDoc(ref(staff()), { hubStage: 'released', rev: 1 }));
  });
  test('an ordinary verified user cannot do hub steps', async () => {
    await seed({ hubStage: 'droppedOff' });
    await assertFails(updateDoc(ref(as('driver')), { hubStage: 'received', rev: 1 }));
  });
  test('staff cannot change anything else on the order', async () => {
    await seed({ hubStage: 'droppedOff' });
    await assertFails(updateDoc(ref(staff()), { hubStage: 'received', deliveryFee: 1, rev: 1 }));
  });
  test('staff can read hub orders they are not part of', async () => {
    await seed();
    await assertSucceeds(getDoc(ref(staff())));
  });
});

describe('drivers', () => {
  test('a driver cannot see or take a hub order that is not released', async () => {
    await seed({ hubStage: 'received' });
    await assertFails(getDoc(ref(as('driver'))));
    await assertFails(updateDoc(ref(as('driver')), { status: 'assigned', driver: 'D', driverId: 'driver', participants: ['buyer', 'farmer', 'driver'], rev: 1 }));
  });
  test('once released it is an open job', async () => {
    await seed({ hubStage: 'released' });
    await assertSucceeds(getDoc(ref(as('driver'))));
    await assertSucceeds(updateDoc(ref(as('driver')), { status: 'assigned', driver: 'D', driverId: 'driver', participants: ['buyer', 'farmer', 'driver'], rev: 1 }));
  });
});

describe('placing an order', () => {
  test('a buyer cannot create an order that is already released to drivers or dropped off', async () => {
    const db = as('buyer');
    const base = order({ participants: ['buyer', 'farmer'], status: 'findingDriver', customerId: 'buyer' });
    await assertFails(setDoc(doc(db, 'marketOrders', 'x1'), { ...base, hubStage: 'released' }));
    await assertFails(setDoc(doc(db, 'marketOrders', 'x2'), { ...base, hubStage: 'droppedOff' }));
    await assertSucceeds(setDoc(doc(db, 'marketOrders', 'x3'), { ...base, hubStage: 'toHub' }));
    await assertSucceeds(setDoc(doc(db, 'marketOrders', 'x4'), { ...base, hubStage: null }));
  });
});
