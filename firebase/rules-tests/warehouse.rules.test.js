// Security rules tests for the Nolifa warehouse.
// Run with:  npm test   (needs Java; starts the Firestore emulator itself)
import { test, before, beforeEach, after, describe } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, deleteDoc } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ubuntu-drop-warehouse',
    firestore: { rules: readFileSync('../../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8089 },
  });
});
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const as = (uid, claims = {}) => env.authenticatedContext(uid, { verified: true, ...claims }).firestore();
const staff = () => as('hubby', { hub: true });

const lot = (over = {}) => ({
  id: 'l1',
  hub: 'Durban hub',
  farmerId: 'farmer',
  farmName: 'Fatboy Butcheries',
  product: 'Beef mince',
  category: 'meat',
  unit: 'kg',
  qty: 40,
  remaining: 0,
  zone: 'chilled',
  useBy: 9000,
  expectedAt: 1000,
  status: 'expected',
  tag: null,
  bay: null,
  events: [],
  ...over,
});
const seed = (over = {}) =>
  env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'warehouseLots', 'l1'), lot(over)));
const ref = (db) => doc(db, 'warehouseLots', 'l1');

describe('announcing a deposit', () => {
  test('a verified farm announces its own deposit', async () => {
    await assertSucceeds(setDoc(ref(as('farmer')), lot()));
  });
  test('not for someone else, and not already in storage', async () => {
    await assertFails(setDoc(ref(as('other')), lot()));
    await assertFails(setDoc(ref(as('farmer')), lot({ status: 'stored', remaining: 40, tag: 'NLF-DBN-0001' })));
  });
  test('a bad room or quantity is refused', async () => {
    await assertFails(setDoc(ref(as('farmer')), lot({ zone: 'sauna' })));
    await assertFails(setDoc(ref(as('farmer')), lot({ qty: 0 })));
  });
});

describe('checking in and picking', () => {
  test('staff check a deposit in with a tag', async () => {
    await seed();
    await assertSucceeds(updateDoc(ref(staff()), { status: 'stored', remaining: 40, tag: 'NLF-DBN-0001', bay: 'C1-01' }));
  });
  test('the farm cannot tag or store its own goods', async () => {
    await seed();
    await assertFails(updateDoc(ref(as('farmer')), { status: 'stored', remaining: 40, tag: 'NLF-DBN-0001' }));
  });
  test('staff cannot change what the goods are or when they expire', async () => {
    await seed();
    await assertFails(updateDoc(ref(staff()), { product: 'Fillet' }));
    await assertFails(updateDoc(ref(staff()), { useBy: 99999 }));
    await assertFails(updateDoc(ref(staff()), { zone: 'ambient' }));
  });
  test('nothing is deleted', async () => {
    await seed();
    await assertFails(deleteDoc(ref(staff())));
  });
});

describe('who can read', () => {
  test('a farm reads its own lot only', async () => {
    await seed();
    await assertSucceeds(getDoc(ref(as('farmer'))));
    await assertFails(getDoc(ref(as('other'))));
    await assertSucceeds(getDoc(ref(staff())));
  });
  test('temperature readings are for staff', async () => {
    await assertSucceeds(setDoc(doc(staff(), 'warehouseReadings', 'r1'), { hub: 'Durban hub', zone: 'chilled', c: 2.1, at: 1 }));
    await assertFails(setDoc(doc(as('farmer'), 'warehouseReadings', 'r2'), { hub: 'Durban hub', zone: 'chilled', c: 2.1, at: 1 }));
    await assertFails(getDoc(doc(as('farmer'), 'warehouseReadings', 'r1')));
  });
});

// --------------------------------------------------- staff and certifiers

const addStaff = (uid) =>
  env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'staff', uid), { role: 'hub' }));
const addCertifier = (uid) =>
  env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'certifiers', uid), { org: 'KZN Food Safety' }));

describe('who counts as staff', () => {
  test('a person an admin listed in staff can check goods in, with no custom claim', async () => {
    await seed();
    await addStaff('hubby2');
    await assertSucceeds(updateDoc(ref(as('hubby2')), { status: 'stored', remaining: 40, tag: 'NLF-DBN-0002', bay: 'C1-02' }));
  });
  test('nobody can add themselves to staff or certifiers', async () => {
    await assertFails(setDoc(doc(as('sneaky'), 'staff', 'sneaky'), { role: 'hub' }));
    await assertFails(setDoc(doc(as('sneaky'), 'certifiers', 'sneaky'), { org: 'x' }));
  });
  test('a person can read only their own staff entry', async () => {
    await addStaff('hubby2');
    await assertSucceeds(getDoc(doc(as('hubby2'), 'staff', 'hubby2')));
    await assertFails(getDoc(doc(as('other'), 'staff', 'hubby2')));
  });
});

const cert = (over = {}) => ({
  id: 'c1',
  hub: 'Durban hub',
  certifierId: 'inspector',
  certifierName: 'T. Naidoo',
  organisation: 'KZN Food Safety Inspectors',
  certNumber: 'FS-2026-0042',
  rooms: ['chilled', 'frozen'],
  issuedAt: 1000,
  expiresAt: 9000,
  checksPassed: ['a'],
  notes: '',
  ...over,
});

describe('warehouse certificates', () => {
  test('a listed certifier records a certificate as themselves', async () => {
    await addCertifier('inspector');
    await assertSucceeds(setDoc(doc(as('inspector'), 'warehouseCerts', 'c1'), cert()));
  });
  test('nobody else can, and not in someone else\'s name', async () => {
    await addCertifier('inspector');
    await assertFails(setDoc(doc(as('farmer'), 'warehouseCerts', 'c1'), cert({ certifierId: 'farmer' })));
    await assertFails(setDoc(doc(as('inspector'), 'warehouseCerts', 'c2'), cert({ certifierId: 'someone-else' })));
    await addStaff('hubby2');
    await assertFails(setDoc(doc(as('hubby2'), 'warehouseCerts', 'c3'), cert({ certifierId: 'hubby2' })));
  });
  test('a certificate must name a room and run forward in time', async () => {
    await addCertifier('inspector');
    await assertFails(setDoc(doc(as('inspector'), 'warehouseCerts', 'c4'), cert({ rooms: [] })));
    await assertFails(setDoc(doc(as('inspector'), 'warehouseCerts', 'c5'), cert({ expiresAt: 500 })));
  });
  test('certificates cannot be edited or deleted, and farms cannot read them', async () => {
    await addCertifier('inspector');
    await setDoc(doc(as('inspector'), 'warehouseCerts', 'c1'), cert());
    await assertFails(updateDoc(doc(as('inspector'), 'warehouseCerts', 'c1'), { expiresAt: 99999 }));
    await assertFails(deleteDoc(doc(as('inspector'), 'warehouseCerts', 'c1')));
    await assertFails(getDoc(doc(as('farmer'), 'warehouseCerts', 'c1')));
    await assertSucceeds(getDoc(doc(as('inspector'), 'warehouseCerts', 'c1')));
  });
});

describe('cut records', () => {
  test('staff write and read them, nobody else', async () => {
    await assertSucceeds(setDoc(doc(staff(), 'warehousePicks', 'UD-1'), { orderId: 'UD-1', lines: { 0: { kg: 2 } } }));
    await assertSucceeds(getDoc(doc(staff(), 'warehousePicks', 'UD-1')));
    await assertFails(setDoc(doc(as('farmer'), 'warehousePicks', 'UD-2'), { orderId: 'UD-2' }));
    await assertFails(getDoc(doc(as('farmer'), 'warehousePicks', 'UD-1')));
    await assertFails(deleteDoc(doc(staff(), 'warehousePicks', 'UD-1')));
  });
});
