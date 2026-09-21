'use strict';
// Executes the actual HTML API function with a controllable fetch transport and
// a small DOM/sessionStorage double. This is not browser or visual acceptance.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const html = fs.readFileSync(path.join(__dirname, '../host/admin.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
new Function(script);
const lines = script.split(/\r?\n/);
const definitions = ['const errors=', 'function errorText(', 'async function api('].map(prefix => {
  const line = lines.find(value => value.startsWith(prefix));
  if (!line) throw new Error('Missing production function: ' + prefix);
  return line;
}).join('\n');
let passed = 0, failed = 0;
function check(condition, label) {
  if (condition) { passed++; console.log('PASS ' + label); }
  else { failed++; console.error('FAIL ' + label); }
}
function fixture() {
  const store = new Map([['token', 'existing-session']]);
  const elements = {appView: {hidden: false}, authView: {hidden: true}, authError: {textContent: ''}};
  const replies = [];
  const context = vm.createContext({
    AbortController, setTimeout: () => 1, clearTimeout: () => {},
    $: id => elements[id],
    sessionStorage: {removeItem: key => store.delete(key)},
    authState: async () => {},
    fetch: async () => {
      if (!replies.length) throw new Error('Unplanned fetch');
      return await replies.shift();
    },
  });
  vm.runInContext("let token='existing-session'; const tokenKey='token';\n" + definitions, context);
  return {context, store, elements, replies, call: action => vm.runInContext(`api(${JSON.stringify(action)})`, context), token: () => vm.runInContext('token', context)};
}
function response(code) { return {ok: code !== 'AUTH_FAILED', status: code === 'AUTH_FAILED' ? 401 : 200, json: async () => ({ok: false, code})}; }
async function rejected(promise) { try { await promise; throw new Error('Expected business error'); } catch (error) { return error; } }
(async () => {
  for (const code of ['STORAGE_UNAVAILABLE', 'RATE_LIMITED', 'STORAGE_MAINTENANCE']) {
    const f = fixture(); f.replies.push(response(code));
    const error = await rejected(f.call('status'));
    check(error.code === code && f.token() === 'existing-session' && f.store.has('token') && f.elements.authView.hidden, code + ' preserves browser session');
    f.replies.push({ok: true, status: 200, json: async () => ({ok: true, payload: {recovered: true}})});
    check((await f.call('status')).recovered === true, code + ' can recover without another login');
  }
  for (const code of ['AUTH_FAILED', 'AUTH_REQUIRED', 'SESSION_EXPIRED', 'ADMIN_REQUIRED']) {
    const f = fixture(); f.replies.push(response(code)); await rejected(f.call('status'));
    check(f.token() === '' && !f.store.has('token') && f.elements.appView.hidden && !f.elements.authView.hidden && f.elements.authError.textContent.length > 0, code + ' clears invalid session and explains it on visible login page');
  }
  const login = fixture(); login.replies.push(response('AUTH_FAILED')); await rejected(login.call('admin.login'));
  check(login.token() === 'existing-session', 'failed explicit login is handled by its own form');
  const late = fixture(); let finish;
  late.replies.push(new Promise(resolve => { finish = resolve; }));
  const pending = rejected(late.call('status'));
  vm.runInContext("token='replacement-session'", late.context);
  finish(response('AUTH_FAILED')); await pending;
  check(late.token() === 'replacement-session' && late.elements.authView.hidden, 'late rejection of old token cannot revoke a newer login');
  console.log(`ADMIN_AUTH_ERRORS_RESULT passed=${passed} failed=${failed}`);
  process.exitCode = failed ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
