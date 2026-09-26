'use strict';
// Runs the production configuration renderer and submit callback against a small
// DOM/API double. This is not browser, authentication or network acceptance.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const html = fs.readFileSync(path.join(__dirname, '../host/admin.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
new Function(script);
const lines = script.split(/\r?\n/);
const production = ['async function loadConfig(', "$('configForm').addEventListener('submit'"].map(prefix => {
  const line = lines.find(value => value.startsWith(prefix));
  if (!line) throw new Error('Missing production code: ' + prefix);
  return line;
}).join('\n');
let passed = 0, failed = 0;
function check(condition, label) {
  if (condition) { passed++; console.log('PASS ' + label); }
  else { failed++; console.error('FAIL ' + label); }
}
class Element {
  constructor(tag, text = '') { this.tag = tag; this.textContent = text; this.children = []; this.dataset = {}; this._value = ''; }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children = children; }
  set value(value) { this._value = value; }
  get value() {
    return this.tag !== 'select' || this.children.some(option => option.value === this._value) ? this._value : '';
  }
  querySelectorAll() { return this.children.flatMap(child => child.tag === 'select' ? [child] : child.querySelectorAll()); }
}
function fixture(games, spaces) {
  const settings = {lobby_bind: '127.0.0.1', advertised_host: '127.0.0.1', lobby_port: 28300, max_rooms: 4, asset_spaces: spaces};
  const elements = {assetSpaces: new Element('div'), configForm: {elements: {}}};
  for (const name of ['lobby_bind', 'advertised_host', 'lobby_port', 'max_rooms']) elements.configForm.elements[name] = new Element('input');
  let submit, job, sent;
  elements.configForm.addEventListener = (event, callback) => { if (event === 'submit') submit = callback; };
  const context = vm.createContext({
    $: id => elements[id], node: (tag, text) => new Element(tag, text),
    document: {createElement: tag => new Element(tag)},
    renderConfigLock: () => {}, updateButtons: () => {}, stateIsStopped: () => true,
    reason: {name: 'reason'}, ask: value => { job = value; },
    api: async (action, payload) => {
      if (action === 'config.get') return {config: settings};
      if (action !== 'config.set') throw new Error('Unexpected API action: ' + action);
      sent = payload;
    },
    FormData: class {
      constructor(form) { this.fields = Object.entries(form.elements).map(([key, value]) => [key, value.value]); }
      [Symbol.iterator]() { return this.fields[Symbol.iterator](); }
    },
  });
  context.snapshot = {games};
  vm.runInContext('let currentConfig;\n' + production, context);
  return {
    render: () => vm.runInContext('loadConfig()', context),
    selects: () => elements.assetSpaces.querySelectorAll(),
    save: async () => {
      submit({preventDefault() {}, target: elements.configForm});
      if (!job) throw new Error('Save confirmation was not opened');
      await job.run({reason: 'Test generic asset space'});
      return sent.config;
    },
  };
}
(async () => {
  const f = fixture([
    {game_id: 'shooter', asset_space: 'shooter'},
    {game_id: 'racer', name: 'Racing', asset_space: 'garage'},
    {game_id: 'shared_game', asset_space: 'shared'},
  ], {shooter: 'shared', racer: 'garage', shared_game: 'shared'});
  await f.render();
  const [shooter, racer, shared] = f.selects();
  check(f.selects().length === 3, 'renderer lists every registered game');
  check(shooter.value === 'shared', 'existing shared selection survives loading');
  check(racer.value === 'garage', 'third game selects its declared default, not its game ID');
  check(racer.children.map(option => option.value).join(',') === 'garage,shared', 'choices contain only declared default and shared');
  check(shared.children.length === 1 && shared.value === 'shared', 'shared default does not create duplicate options');
  let saved = await f.save();
  check(saved.asset_spaces.racer === 'garage' && saved.asset_spaces.shooter === 'shared', 'submit preserves selected spaces keyed by game ID');
  check(!('garage' in saved.asset_spaces) && Object.keys(saved.asset_spaces).length === 3, 'default space is never mistaken for a game key');
  racer.value = 'shared';
  saved = await f.save();
  check(saved.asset_spaces.racer === 'shared', 'third game can submit the shared option');
  racer.value = 'garage';
  saved = await f.save();
  check(saved.asset_spaces.racer === 'garage', 'third game can return to its declared default');
  const defaults = fixture([{game_id: 'racer', asset_space: 'garage'}, {game_id: 'legacy_game'}], {});
  await defaults.render();
  check(defaults.selects()[0].value === 'garage', 'missing saved setting uses the registry default');
  check(defaults.selects()[1].value === 'legacy_game', 'older status rows without asset_space remain compatible');
  const invalid = fixture([{game_id: 'racer', asset_space: 'garage'}], {racer: 'unregistered_space'});
  await invalid.render();
  check(invalid.selects()[0].value === '' && invalid.selects()[0].required, 'invalid persisted space remains an unselected required input');
  console.log(`ADMIN_ASSET_SPACES_RESULT passed=${passed} failed=${failed}`);
  process.exitCode = failed ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
