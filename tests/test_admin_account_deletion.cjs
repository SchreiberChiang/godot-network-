'use strict';
// Runs the production account-deletion dialog code of host/admin.html against a small
// API/dialog double: backup warning, typed username, final browser confirmation and
// the request that is sent. This is not browser, authentication or network acceptance.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const html = fs.readFileSync(path.join(__dirname, '../host/admin.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
new Function(script);
const lines = script.split(/\r?\n/);
const production = ['const errors=', 'function errorText(', 'function accountState(', 'async function deleteAccount('].map(prefix => {
  const line = lines.find(value => value.startsWith(prefix));
  if (!line) throw new Error('Missing production code: ' + prefix);
  return line;
}).join('\n');
let passed = 0, failed = 0;
function check(condition, label) {
  if (condition) { passed++; console.log('PASS ' + label); }
  else { failed++; console.error('FAIL ' + label); }
}
function fixture(confirmAnswer) {
  const calls = [];
  let job = null;
  const context = vm.createContext({
    selectedUser: 'user_a', reason: {name: 'reason'},
    ask: value => { job = value; },
    api: async (action, payload) => {
      calls.push([action, payload]);
      if (action === 'backup.list') return {backups: [{backup_id: 'backup-old', created_at: 50}, {backup_id: 'backup-new', created_at: 200}]};
      if (action === 'account.delete') return {subject: 'deleted_x', assets: {asset_states: 2, asset_receipts: 3, results_deidentified: 1}, backups_may_restore: [{backup_id: 'backup-new'}], residual_files: {outbox_pending: 0, outbox_rejected: 0, files: []}, was_online: true, still_online: false};
      throw new Error('Unexpected API action: ' + action);
    },
    window: {confirm: () => confirmAnswer},
    $: () => ({replaceChildren() {}}), node: () => ({}), loadAccounts: async () => {},
  });
  vm.runInContext(production, context);
  return {context, calls, job: () => job};
}
(async () => {
  const account = {user_id: 'user_a', username: 'tester', created_at: 100, role: 'player'};
  let f = fixture(true);
  await vm.runInContext('deleteAccount', f.context)(account);
  const dialog = f.job();
  check(dialog && dialog.danger && dialog.title.includes('永久删除'), 'separate danger dialog opened');
  check(dialog.intro.includes('不可恢复') && dialog.intro.includes('1 个备份') && dialog.intro.includes('backup-new') && !dialog.intro.includes('backup-old'), 'dialog warns irreversibility and names backups made after registration');
  check(dialog.fields.some(field => field.name === 'confirm_username') && dialog.fields.some(field => field.type === 'checkbox'), 'typed username and acknowledgement required');
  let error = null;
  try { await dialog.run({confirm_username: 'someone', reason: 'test'}); } catch (e) { error = e; }
  check(error && error.code === 'DELETE_CONFIRMATION_MISMATCH' && !f.calls.some(call => call[0] === 'account.delete'), 'mismatched username never sends a request');
  const result = await dialog.run({confirm_username: ' Tester ', reason: 'test'});
  const sent = f.calls.find(call => call[0] === 'account.delete');
  check(sent && sent[1].user_id === 'user_a' && sent[1].confirm_username === 'Tester' && sent[1].reason === 'test' && Object.keys(sent[1]).length === 3, 'request carries only user_id, typed username and reason');
  const text = dialog.success(result);
  check(text.includes('deleted_x') && text.includes('backup-new') && text.includes('踢下线'), 'success message reports pseudonym, remaining backups and kick');
  f = fixture(false);
  await vm.runInContext('deleteAccount', f.context)(account);
  error = null;
  try { await f.job().run({confirm_username: 'tester', reason: 'test'}); } catch (e) { error = e; }
  check(error && !f.calls.some(call => call[0] === 'account.delete'), 'declining the final confirmation sends nothing');
  check(vm.runInContext('accountState', f.context)({deletion_pending: true, banned: true}) === 'DELETING', 'pending deletion shown separately from deactivation');
  check(vm.runInContext('errorText', f.context)({code: 'ACCOUNT_DELETION_INCOMPLETE'}).includes('未完成'), 'incomplete deletion explained, not shown as success');
  console.log(passed + ' passed, ' + failed + ' failed');
  process.exit(failed ? 1 : 0);
})().catch(error => { console.error(error); process.exit(1); });
