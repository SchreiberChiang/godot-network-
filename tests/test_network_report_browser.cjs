'use strict';
// Dev-only browser acceptance. No npm install is needed by the delivered viewer.
// Use an already available Playwright and Chromium, never download dependencies here.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { pathToFileURL } = require('node:url');
let chromium;
try { ({ chromium } = require('playwright')); } catch { /* Explicit skip below, not a browser pass. */ }
const executablePath = process.env.CHROMIUM_EXECUTABLE || '/usr/bin/chromium';
const supported = chromium && fs.existsSync(executablePath);
const fixtures = path.join(__dirname, 'fixtures/network-report');

test('Actual Chromium file:// selection, charts, markers, privacy and repeated flows', { skip: supported ? false : 'UNTESTED: existing Playwright/Chromium unavailable' }, async () => {
  const browser = await chromium.launch({ executablePath, headless: true, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ offline: true, viewport: { width: 1360, height: 1100 } });
    const page = await context.newPage();
    const errors = [], remote = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
    page.on('request', request => { if (!request.url().startsWith('file:')) remote.push(request.url()); });
    await page.goto(pathToFileURL(path.join(__dirname, '../NETWORK_REPORT.html')).href);
    assert.equal(await page.title(), 'RoomKit · 离线网络报告');
    assert.equal(await page.locator('#explorer').isVisible(), false);
    const chooserEvent = page.waitForEvent('filechooser');
    await page.locator('#files').click();
    const chooser = await chooserEvent;
    await chooser.setFiles(['normal.jsonl', 'unknown.jsonl', 'malformed.jsonl'].map(f => path.join(fixtures, f)));
    await page.waitForFunction(() => document.getElementById('status').textContent.includes('已读取 3 个文件'));
    assert.equal(await page.locator('#comparison thead th').count(), 4);
    assert.equal(await page.locator('#session option').count(), 4);
    assert.match(await page.locator('#comparison').innerText(), /240 ms/);
    assert.match(await page.locator('#rtt-caption').innerText(), /35 条已知/);
    assert.match(await page.locator('#snapshot-caption').innerText(), /700 ms/);
    assert.equal(await page.locator('#sample-details').getAttribute('open'), null);
    const pixelCount = await page.locator('#rtt-chart').evaluate(canvas => {
      const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
      let visible = 0; for (let i = 3; i < pixels.length; i += 4) if (pixels[i]) visible++; return visible;
    });
    assert.ok(pixelCount > 5000, 'chart must really render, not only parse records');
    if (process.env.NETWORK_REPORT_EVIDENCE) {
      fs.mkdirSync(process.env.NETWORK_REPORT_EVIDENCE, { recursive: true });
      await page.screenshot({ path: path.join(process.env.NETWORK_REPORT_EVIDENCE, 'overview.png'), fullPage: true });
    }
    await page.locator('#next').click();
    assert.match(await page.locator('#selection').innerText(), /标记 #1.*第 14 行/);
    assert.equal(await page.locator('#previous').isDisabled(), true);
    await page.locator('#next').click();
    assert.match(await page.locator('#selection').innerText(), /标记 #2/);
    assert.equal(await page.locator('#next').isDisabled(), true);
    await page.locator('#previous').click();
    assert.match(await page.locator('#selection').innerText(), /标记 #1/);
    if (process.env.NETWORK_REPORT_EVIDENCE) await page.screenshot({ path: path.join(process.env.NETWORK_REPORT_EVIDENCE, 'marker.png'), fullPage: true });
    await page.locator('#all').click();
    assert.match(await page.locator('#selection').innerText(), /正在查看全程/);
    await page.locator('#session').selectOption('1');
    assert.match(await page.locator('#rtt-caption').innerText(), /0 条已知，峰值 未知/);
    await page.locator('#session').selectOption('3');
    await page.locator('#sample-details summary').click();
    assert.match(await page.locator('#sample-table').innerText(), /未采集（卡顿标记）/);
    const text = await page.locator('body').innerText();
    assert.ok(!text.includes('SYNTHETIC_SECRET_DO_NOT_RENDER')); assert.ok(!text.includes('<script>'));
    assert.equal(await page.evaluate(() => globalThis.pwned), undefined);
    assert.equal(await page.locator('img, iframe').count(), 0);
    await page.locator('.file-notice summary').first().click();
    assert.match(await page.locator('#file-notices').innerText(), /第 2 行：JSON/);
    await page.locator('#clear').click();
    assert.equal(await page.locator('#overview').isVisible(), false);
    for (const id of ['session-info', 'selection', 'rtt-caption', 'snapshot-caption', 'rows-page']) assert.equal(await page.locator('#' + id).textContent(), '');
    assert.equal(await page.locator('#rtt-chart').getAttribute('aria-label'), '尚未加载图表');
    assert.ok(!(await page.locator('body').textContent()).includes('n1-synthetic'));
    // Large file is a browser-created synthetic input; no large fixture on disk.
    await page.locator('#files').setInputFiles({ name: 'oversized.jsonl', mimeType: 'application/x-ndjson', buffer: Buffer.alloc(8 * 1024 * 1024 + 1, 32) });
    await page.waitForFunction(() => document.getElementById('status').textContent.includes('已读取 1 个文件'));
    assert.match(await page.locator('#file-notices').innerText(), /超过 8 MiB/);
    assert.equal(await page.locator('#explorer').isVisible(), false);
    const oversizedLine = Buffer.concat([Buffer.alloc(65537, 120), Buffer.from('\n'), fs.readFileSync(path.join(fixtures, 'normal.jsonl'))]);
    await page.locator('#files').setInputFiles({ name: 'long-line.jsonl', mimeType: 'application/x-ndjson', buffer: oversizedLine });
    await page.waitForFunction(() => document.getElementById('status').textContent.includes('接受 37 条记录'));
    await page.locator('.file-notice summary').click();
    assert.match(await page.locator('#file-notices').innerText(), /第 1 行：行超过 64 KiB/);
    // Re-selecting the same file and repeated reset must not duplicate sessions.
    await page.locator('#files').setInputFiles(path.join(fixtures, 'normal.jsonl'));
    await page.waitForFunction(() => document.getElementById('status').textContent.includes('没有发现坏行'));
    assert.equal(await page.locator('#session option').count(), 1);
    await page.locator('#files').setInputFiles(path.join(fixtures, 'normal.jsonl'));
    await page.waitForFunction(() => document.getElementById('status').textContent.includes('没有发现坏行'));
    assert.equal(await page.locator('#session option').count(), 1);
    for (const width of [760, 390]) {
      await page.setViewportSize({ width, height: 844 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'narrow layout must not overflow the page');
      if (process.env.NETWORK_REPORT_EVIDENCE) await page.screenshot({ path: path.join(process.env.NETWORK_REPORT_EVIDENCE, `narrow-${width}.png`), fullPage: true });
    }
    await page.locator('#clear').click(); await page.locator('#clear').click();
    assert.deepEqual(remote, []); assert.deepEqual(errors, []);
    console.log(`Browser verified: ${await browser.version()}; file://; offline; zero remote requests and zero console errors`);
  } finally { await browser.close(); }
});

// Optional read-only acceptance with reports from an isolated real-client run.
// Never scans arbitrary client-data folders; only the explicit reports directory.
if (process.env.NETWORK_REPORT_SAMPLE_DIR) test('Real client JSONL renders in offline file:// viewer', { skip: supported ? false : 'UNTESTED: existing Playwright/Chromium unavailable' }, async () => {
  const C = require('../docs/assets/network-report/core.js');
  const folder = process.env.NETWORK_REPORT_SAMPLE_DIR;
  const files = fs.readdirSync(folder, { withFileTypes: true }).filter(e => e.isFile() && e.name.endsWith('.jsonl')).map(e => path.join(folder, e.name));
  assert.ok(files.length > 0 && files.length <= C.LIMITS.files);
  const reports = [];
  for (const file of files) {
    assert.ok(fs.statSync(file).size <= C.LIMITS.fileBytes);
    const blob = new Blob([fs.readFileSync(file)]); blob.name = path.basename(file);
    const report = await C.parseFile(blob);
    assert.equal(report.failure, null); assert.equal(report.rejected, 0); assert.equal(report.warnings, 0);
    assert.ok(report.samples > 0); reports.push(report);
  }
  const browser = await chromium.launch({ executablePath, headless: true, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ offline: true, viewport: { width: 1360, height: 1100 } });
    const page = await context.newPage(), errors = [], remote = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
    page.on('request', request => { if (!request.url().startsWith('file:')) remote.push(request.url()); });
    await page.goto(pathToFileURL(path.join(__dirname, '../NETWORK_REPORT.html')).href);
    await page.locator('#files').setInputFiles(files);
    await page.waitForFunction(count => document.getElementById('status').textContent.includes(`已读取 ${count} 个文件`), files.length);
    assert.equal(await page.locator('#comparison thead th').count(), files.length + 1);
    const sessions = reports.flatMap(r => r.sessions);
    assert.equal(await page.locator('#session option').count(), sessions.length);
    for (let i = 0; i < sessions.length; i++) {
      await page.locator('#session').selectOption(String(i));
      const count = C.stats(sessions[i].samples, 'rtt_ms').count;
      assert.ok((await page.locator('#rtt-caption').innerText()).includes(`${count} 条已知`));
      assert.equal(await page.locator('#explorer').isVisible(), true);
    }
    if (process.env.NETWORK_REPORT_EVIDENCE) {
      fs.mkdirSync(process.env.NETWORK_REPORT_EVIDENCE, { recursive: true });
      await page.screenshot({ path: path.join(process.env.NETWORK_REPORT_EVIDENCE, 'real-client.png'), fullPage: true });
    }
    assert.deepEqual(errors, []); assert.deepEqual(remote, []);
    console.log(`Real reports verified: ${files.length} files; ${sessions.length} sessions; ${reports.reduce((n, r) => n + r.samples, 0)} samples; zero rejected/warnings/remote/errors`);
  } finally { await browser.close(); }
});
