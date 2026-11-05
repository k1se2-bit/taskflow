const { before, beforeEach, after, test } = require('node:test');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, query, where, serverTimestamp } = require('firebase/firestore');

let env;
const dbFor = uid => env.authenticatedContext(uid).firestore();
const task = (assignedTo = 'member') => ({ title: 'Task', description: '', assignedTo, creatorId: 'owner', status: 'todo', deadline: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
const taskRef = uid => doc(dbFor(uid), 'organizations/team/tasks/assigned');

before(async () => {
  if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080') throw new Error('Tests require the local Firestore emulator on 127.0.0.1:8080.');
  env = await initializeTestEnvironment({ projectId: 'demo-taskflow-rules', firestore: { host: '127.0.0.1', port: 8080, rules: readFileSync(join(__dirname, '../firestore.rules'), 'utf8') } });
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'organizations/team'), { name: 'Team', ownerId: 'owner', memberIds: ['owner', 'member', 'other'], memberNames: { owner: 'Owner', member: 'Member', other: 'Other' }, createdAt: serverTimestamp() });
    await setDoc(doc(db, 'organizations/team/tasks/assigned'), task());
    await setDoc(doc(db, 'organizations/team/tasks/other'), task('other'));
    await setDoc(doc(db, 'users/owner'), { teamReminders: {} });
    await setDoc(doc(db, 'users/owner/tasks/private'), { title: 'Private task' });
  });
});
after(async () => { if (env) await env.cleanup(); });

test('unauthenticated users cannot read a team', async () => {
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'organizations/team')));
});
test('outsiders cannot read a team', async () => {
  await assertFails(getDoc(doc(dbFor('outsider'), 'organizations/team')));
});
test('members can read their team', async () => {
  await assertSucceeds(getDoc(doc(dbFor('member'), 'organizations/team')));
});
test('owners can read all team tasks', async () => {
  await assertSucceeds(getDocs(collection(dbFor('owner'), 'organizations/team/tasks')));
});
test('members can read an assigned task', async () => {
  await assertSucceeds(getDoc(taskRef('member')));
});
test('members cannot read another persons task', async () => {
  await assertFails(getDoc(doc(dbFor('member'), 'organizations/team/tasks/other')));
});
test('members can query only their assignments', async () => {
  await assertSucceeds(getDocs(query(collection(dbFor('member'), 'organizations/team/tasks'), where('assignedTo', '==', 'member'))));
});
test('unfiltered member task queries are denied', async () => {
  await assertFails(getDocs(collection(dbFor('member'), 'organizations/team/tasks')));
});
test('owners can create a task for a member', async () => {
  await assertSucceeds(setDoc(doc(dbFor('owner'), 'organizations/team/tasks/new'), task()));
});
test('owners cannot assign a task to an outsider', async () => {
  await assertFails(setDoc(doc(dbFor('owner'), 'organizations/team/tasks/new'), task('outsider')));
});
test('members cannot create team tasks', async () => {
  await assertFails(setDoc(doc(dbFor('member'), 'organizations/team/tasks/new'), { ...task(), creatorId: 'member' }));
});
test('assignees can change status', async () => {
  await assertSucceeds(updateDoc(taskRef('member'), { status: 'inProgress', updatedAt: serverTimestamp() }));
});
test('assignees cannot change task titles', async () => {
  await assertFails(updateDoc(taskRef('member'), { title: 'Changed', updatedAt: serverTimestamp() }));
});
test('assignees cannot reassign tasks', async () => {
  await assertFails(updateDoc(taskRef('member'), { assignedTo: 'other', updatedAt: serverTimestamp() }));
});
test('invalid statuses are denied', async () => {
  await assertFails(updateDoc(taskRef('member'), { status: 'invalid', updatedAt: serverTimestamp() }));
});
test('owners can edit and reassign tasks', async () => {
  await assertSucceeds(updateDoc(taskRef('owner'), { title: 'Updated', assignedTo: 'other', updatedAt: serverTimestamp() }));
});
test('task creator identity cannot be replaced', async () => {
  await assertFails(updateDoc(taskRef('owner'), { creatorId: 'other', updatedAt: serverTimestamp() }));
});
test('task deletion is denied even for owners in this version', async () => {
  await assertFails(deleteDoc(taskRef('owner')));
});
test('members cannot modify team membership', async () => {
  await assertFails(updateDoc(doc(dbFor('member'), 'organizations/team'), { memberIds: ['owner', 'member', 'other', 'outsider'] }));
});
test('owners can rename team members', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('owner'), 'organizations/team'), { 'memberNames.member': 'New name' }));
});
test('personal tasks are private from team members', async () => {
  await assertFails(getDoc(doc(dbFor('member'), 'users/owner/tasks/private')));
});
test('users can store their own reminder preferences', async () => {
  await assertSucceeds(setDoc(doc(dbFor('member'), 'users/member'), { teamReminders: { team_assigned: { remindAt: serverTimestamp() } } }, { merge: true }));
});
test('users cannot read another persons reminder preferences', async () => {
  await assertFails(getDoc(doc(dbFor('member'), 'users/owner')));
});
test('users cannot change another persons reminder preferences', async () => {
  await assertFails(updateDoc(doc(dbFor('member'), 'users/owner'), { teamReminders: {} }));
});
test('new teams with initial owner name can be created', async () => {
  await assertSucceeds(setDoc(doc(dbFor('newOwner'), 'organizations/newTeam'), { name: 'New team', ownerId: 'newOwner', memberIds: ['newOwner'], memberNames: { newOwner: 'Владелец' }, createdAt: serverTimestamp() }));
});
