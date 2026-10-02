'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const C = require('../docs/assets/network-report/core.js');
const fixtures = path.join(__dirname, 'fixtures/network-report');
const file = (bytes, name = 'synthetic.jsonl') => { const blob = new Blob([bytes]); blob.name = name; return blob; };
const fixture = name => file(fs.readFileSync(path.join(fixtures, name)), name);
const base = (at = 0, extra = {}) => ({ kind: 'sample', session_id: 'a'.repeat(32), monotonic_ms: at,
  phase: 'IN_ROOM', error: 'NONE', build: 'test', ...extra });
const line = value => JSON.stringify(value) + '\n';

test('N1 fixture: fields, real zero, maturity, markers and peak statistics', async () => {
  const r = await C.parseFile(fixture('normal.jsonl'));
  assert.equal(r.samples, 35); assert.equal(r.marks, 2); assert.equal(r.rejected, 0); assert.equal(r.warnings, 0);
  const s = r.sessions[0];
  assert.equal(s.samples[0].reliable_loss_percent, null);
  assert.equal(s.samples[10].reliable_loss_percent, 0);
  assert.equal(s.samples[0].tx_bytes_per_sec, null);
  assert.equal(s.samples[9].rtt_p50_ms, 43);
  assert.equal(C.stats(s.samples, 'rtt_ms', 10).max, 240);
  assert.equal(C.stats(s.samples, 'snapshot_age_ms').max, 700);
  assert.equal(C.stats(s.samples, 'fps').min, 32);
  assert.equal(C.stats(s.samples, 'frame_max_ms').max, 145);
  assert.equal(C.nearest(s, s.marks[0].at).line, 13);
  assert.equal(s.marks[0].fps, null);
  assert.equal(s.marks[0].phase, 'IDLE', 'actual N1 mark uses default phase, not the live room phase');
});
test('Unknown/immature values stay unknown; each session uses its own clock', async () => {
  const r = await C.parseFile(fixture('unknown.jsonl'));
  assert.equal(r.sessions.length, 2);
  assert.equal(r.sessions[0].start, 2000); assert.equal(r.sessions[1].start, 1000);
  assert.equal(r.sessions[0].samples[0].rtt_ms, null);
  assert.equal(r.sessions[0].samples[0].reliable_loss_percent, null);
  assert.equal(r.sessions[0].samples[0].rtt_p95_ms, null);
  assert.equal(C.stats(r.sessions[0].samples, 'rtt_ms', 10).median, null);
  assert.equal(C.stats([], 'fps').min, null);
});
test('Bad lines report precise locations; unknown and malicious content never survives projection', async () => {
  const r = await C.parseFile(fixture('malformed.jsonl'));
  assert.equal(r.accepted, 3); assert.equal(r.rejected, 3); assert.equal(r.warnings, 1);
  assert.deepEqual(r.issues.map(x => x.line), [2, 3, 4, 5]);
  const serialized = JSON.stringify(r.sessions, (_, v) => v instanceof Set ? [...v] : v);
  assert.ok(!serialized.includes('SYNTHETIC_SECRET_DO_NOT_RENDER'));
  assert.ok(!serialized.includes('<script>')); assert.ok(!serialized.includes('https://'));
  assert.equal(r.sessions[0].samples[0].build, '未知');
  assert.equal(r.sessions[0].samples[0].error, 'OTHER');
  assert.equal(r.sessions[0].samples[1].fps, null);
});
test('Byte bounds reject oversized file before reading, skip oversized lines, and reject invalid UTF-8', async () => {
  let touched = false;
  const r = await C.parseFile({ name: 'huge.jsonl', size: C.LIMITS.fileBytes + 1, slice() { touched = true; throw Error(); } });
  assert.equal(touched, false); assert.ok(r.failure.includes('8 MiB'));
  const mixed = await C.parseFile(file(Buffer.concat([Buffer.alloc(C.LIMITS.lineBytes + 1, 120), Buffer.from('\n'), Buffer.from(line(base(0))), Buffer.from([0xff, 10]), Buffer.from(line(base(1)))])));
  assert.equal(mixed.accepted, 2); assert.equal(mixed.rejected, 2);
  assert.deepEqual(mixed.issues.map(x => x.line), [1, 3]);
});
test('CRLF, BOM, blank, trailing line, chunk boundaries and UTF-8 are handled', async () => {
  const text = '\uFEFF' + line(base(0)).trimEnd() + '\r\n\n' + JSON.stringify(base(1, { ignored: '中文'.repeat(4000) }));
  const r = await C.parseFile(file(text));
  assert.equal(r.accepted, 2); assert.equal(r.blank, 1); assert.equal(r.rejected, 0);
  const large = await C.parseFile(file(Array.from({ length: 700 }, (_, i) => line(base(i))).join('')));
  assert.equal(large.accepted, 700); assert.equal(large.rejected, 0);
});
test('Record/session/issue/line caps bound storage and visibly mark truncation', async () => {
  const r = await C.parseFile(file(Array.from({ length: C.LIMITS.records + 2 }, (_, i) => line(base(i))).join('')));
  assert.equal(r.accepted, C.LIMITS.records); assert.equal(r.stopped, true); assert.equal(r.issues[0].line, C.LIMITS.records + 1);
  const sessions = await C.parseFile(file(Array.from({ length: 18 }, (_, i) => line(base(0, { session_id: i.toString(16).padStart(32, '0') }))).join('')));
  assert.equal(sessions.sessions.length, 16); assert.equal(sessions.rejected, 2);
  const issues = await C.parseFile(file('{bad\n'.repeat(150)));
  assert.equal(issues.rejected, 150); assert.equal(issues.issues.length, 100);
  const lines = await C.parseFile(file('\n'.repeat(C.LIMITS.lines + 1)));
  assert.equal(lines.stopped, true); assert.equal(lines.issues[0].line, C.LIMITS.lines + 1);
});
test('Cancellation, read failure and numeric edge values are explicit', async () => {
  assert.equal(await C.parseFile(fixture('normal.jsonl'), () => true), null);
  const failed = await C.parseFile({ name: 'unreadable', size: 1, slice() { throw Error('do not echo'); } });
  assert.ok(failed.failure); assert.equal(failed.stopped, true); assert.ok(!failed.failure.includes('do not echo'));
  for (const value of [null, '12', false, NaN, Infinity, -1, 1e100]) {
    const p = C.project(base(1, { fps: value }), 1);
    assert.equal(p.record.fps, null); assert.equal(p.invalid, true);
  }
  assert.equal(C.project(base(1, { fps: 0 }), 1).record.fps, 0);
  assert.equal(C.project(base(1, { reliable_loss_percent: 101, loss_sample_count: 1 }), 1).record.reliable_loss_percent, null);
  assert.equal(C.project(base(1, { rtt_sample_count: .5, rtt_ms: 20 }), 1).record.rtt_ms, null);
  const fractional = C.project(base(1, { snapshot_samples: 10.5, snapshot_interval_p95_ms: 80 }), 1);
  assert.equal(fractional.invalid, true);
  assert.equal(fractional.record.snapshot_samples, null);
  assert.equal(fractional.record.snapshot_interval_p95_ms, null);
  assert.equal(C.project(base(1, { snapshot_samples: 10, snapshot_interval_p95_ms: 80 }), 1).record.snapshot_interval_p95_ms, 80);
});
test('Local source has no remote loader, dynamic evaluation or unsafe HTML sink', () => {
  const folder = path.join(__dirname, '../docs/assets/network-report');
  const source = ['core.js', 'app.js', 'report.css'].map(f => fs.readFileSync(path.join(folder, f), 'utf8')).join('\n');
  assert.doesNotMatch(source, /\b(?:fetch|XMLHttpRequest|WebSocket|eval|Function|importScripts)\s*\(|innerHTML|outerHTML|insertAdjacentHTML|https?:\/\/|@import|url\(/);
  const html = fs.readFileSync(path.join(__dirname, '../NETWORK_REPORT.html'), 'utf8');
  assert.ok(html.includes("connect-src 'none'")); assert.doesNotMatch(html, /https?:\/\//);
});
