/* RoomKit D1: bounded, allowlisted N1 projection. No filesystem or network access. */
(function (root) {
  'use strict';
  const LIMITS = Object.freeze({ files: 8, fileBytes: 8 * 1024 * 1024, lineBytes: 64 * 1024,
    chunkBytes: 64 * 1024, records: 10000, sessions: 16, issues: 100, lines: 100000 });
  const NUMBERS = ['fps', 'frame_max_ms', 'rtt_ms', 'rtt_variance_ms', 'reliable_loss_percent',
    'rx_bytes_per_sec', 'tx_bytes_per_sec', 'snapshot_interval_ms', 'snapshot_age_ms',
    'snapshot_interval_p50_ms', 'snapshot_interval_p95_ms', 'snapshot_samples',
    'rtt_p50_ms', 'rtt_p95_ms', 'sample_count', 'rtt_sample_count', 'loss_sample_count',
    'transport_sample_count', 'window_ms', 'sample_mono_ms'];
  const PHASES = new Set(['IDLE', 'CLOSED', 'CONNECTING_LOBBY', 'LOBBY', 'CONNECTING',
    'AUTHENTICATING', 'AUTHENTICATING_ACCOUNT', 'LOADING', 'SYNCHRONIZING', 'IN_ROOM', 'OTHER']);
  const ERRORS = new Set(['NONE', 'OTHER', 'AUTH_FAILED', 'AUTH_REQUIRED', 'BUILD_MISMATCH',
    'CONTROL_UNAVAILABLE', 'DISCONNECTED', 'INVALID_SNAPSHOT', 'LOAD_FAILED', 'LOAD_TIMEOUT',
    'INVALID_RESPONSE', 'UNEXPECTED_REPLY', 'INVALID_OPTIONS', 'RATE_LIMITED', 'ALREADY_IN_ROOM',
    'ALREADY_CONNECTED', 'ROOM_NOT_FOUND', 'ROOM_FULL', 'ROOM_NOT_READY', 'ROOM_STOPPED',
    'TICKET_EXPIRED', 'VERSION_MISMATCH']);
  const finite = n => typeof n === 'number' && Number.isFinite(n) && n >= 0 && n <= 1e12;
  const token = value => typeof value === 'string' && /^[a-zA-Z0-9_.-]{1,96}$/.test(value);
  function project(value, line) {
    if (!value || Array.isArray(value) || typeof value !== 'object' ||
        !['sample', 'mark'].includes(value.kind) ||
        typeof value.session_id !== 'string' || !/^[a-fA-F0-9]{32}$/.test(value.session_id) ||
        !finite(value.monotonic_ms) || !Number.isSafeInteger(value.monotonic_ms)) return null;
    const record = { kind: value.kind, session: value.session_id, at: value.monotonic_ms, line,
      build: token(value.build) ? value.build : '未知',
      phase: PHASES.has(value.phase) ? value.phase : 'OTHER',
      error: ERRORS.has(value.error) ? value.error : 'OTHER', utc: null };
    // Wall clock is display-only; never used to align machines or compute duration.
    if (typeof value.utc === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value.utc) &&
        Number.isFinite(Date.parse(value.utc))) record.utc = value.utc;
    let invalid = false;
    for (const key of NUMBERS) {
      let v = value[key];
      if (v !== undefined && (!finite(v) || ((key.endsWith('count') || key === 'snapshot_samples') && !Number.isSafeInteger(v)) ||
          (key === 'reliable_loss_percent' && v > 100))) { invalid = true; v = null; }
      record[key] = finite(v) ? v : null;
    }
    // N1 omits unknown negative values. Counts, rather than elapsed time, establish maturity.
    if (!(record.rtt_sample_count > 0)) { record.rtt_ms = null; record.rtt_variance_ms = null; }
    if (!(record.rtt_sample_count >= 10)) { record.rtt_p50_ms = null; record.rtt_p95_ms = null; }
    if (!(record.loss_sample_count > 0)) record.reliable_loss_percent = null;
    if (!(record.transport_sample_count > 0)) { record.rx_bytes_per_sec = null; record.tx_bytes_per_sec = null; }
    if (!(record.snapshot_samples >= 10)) { record.snapshot_interval_p50_ms = null; record.snapshot_interval_p95_ms = null; }
    // A mark has no metric observations even if a foreign file supplies them.
    if (record.kind === 'mark') for (const key of NUMBERS) record[key] = null;
    return { record, invalid };
  }
  function newReport(name, size) {
    return { name, size, sessions: [], accepted: 0, samples: 0, marks: 0, lines: 0, blank: 0,
      rejected: 0, warnings: 0, issues: [], stopped: false, failure: null };
  }
  function issue(report, line, message, warning = false) {
    report[warning ? 'warnings' : 'rejected']++;
    if (report.issues.length < LIMITS.issues) report.issues.push({ line, message });
  }
  async function parseFile(file, cancelled = () => false) {
    const report = newReport(file.name, file.size);
    if (!Number.isSafeInteger(file.size) || file.size < 0 || file.size > LIMITS.fileBytes) {
      report.failure = '文件超过 8 MiB 上限，未读取；请只选 client-data/reports 中的单个 JSONL 报告。'; return report;
    }
    const sessions = new Map();
    const buffer = new Uint8Array(LIMITS.lineBytes);
    const decoder = new TextDecoder('utf-8', { fatal: true });
    let used = 0, oversized = false, stopped = false;
    function lineEnd() {
      if (stopped) return;
      const line = ++report.lines;
      if (line > LIMITS.lines) {
        issue(report, line, '超过 100000 行上限；后续未读取。'); report.stopped = stopped = true; return;
      }
      if (oversized) { issue(report, line, '行超过 64 KiB，已拒绝整行。'); return; }
      let text;
      try { text = decoder.decode(buffer.subarray(0, used)); }
      catch { issue(report, line, '不是有效 UTF-8，已拒绝整行。'); return; }
      if (!text.trim()) { report.blank++; return; }
      let value;
      try { value = JSON.parse(text); }
      catch { issue(report, line, 'JSON 语法错误，已拒绝整行。'); return; }
      const projected = project(value, line);
      if (!projected) { issue(report, line, '不是支持的 N1 记录（kind/session_id/monotonic_ms）。'); return; }
      if (report.accepted >= LIMITS.records) {
        issue(report, line, '超过 10000 条记录上限；后续未读取。'); report.stopped = stopped = true; return;
      }
      const r = projected.record;
      let session = sessions.get(r.session);
      if (!session) {
        if (sessions.size >= LIMITS.sessions) { issue(report, line, '超过 16 个会话上限，已拒绝该行。'); return; }
        session = { id: r.session, start: r.at, end: r.at, utc: r.utc, records: [], samples: [], marks: [], builds: new Set() };
        sessions.set(r.session, session); report.sessions.push(session);
      }
      if (r.at < session.end) { issue(report, line, '同会话单调时钟倒退，已拒绝该行；未重排或跨设备对时。'); return; }
      if (projected.invalid) issue(report, line, '已忽略非法数值字段，其值按未知处理。', true);
      session.end = r.at;
      session.builds.add(r.build);
      session.records.push(r);
      session[r.kind === 'sample' ? 'samples' : 'marks'].push(r);
      report.accepted++; report[r.kind === 'sample' ? 'samples' : 'marks']++;
    }
    try {
      for (let offset = 0; offset < file.size && !stopped; offset += LIMITS.chunkBytes) {
        if (cancelled()) return null;
        const bytes = new Uint8Array(await file.slice(offset, offset + LIMITS.chunkBytes).arrayBuffer());
        if (cancelled()) return null;
        for (const byte of bytes) {
          if (byte === 10) { lineEnd(); used = 0; oversized = false; if (stopped) break; }
          else if (!oversized) {
            if (used === buffer.length) oversized = true;
            else buffer[used++] = byte;
          }
        }
      }
      if (!stopped && (used || oversized)) lineEnd();
    } catch {
      report.failure = '本地文件读取失败；仅已读部分可见，请重新选择文件。'; report.stopped = true;
    }
    return report;
  }
  function values(records, key) { return records.filter(r => r.kind === 'sample' && r[key] !== null).map(r => r[key]); }
  function stats(records, key, minimum = 1) {
    const list = values(records, key).sort((a, b) => a - b);
    return { count: list.length, min: list.length ? list[0] : null, max: list.length ? list[list.length - 1] : null,
      median: list.length >= minimum ? list[Math.ceil(list.length / 2) - 1] : null };
  }
  function nearest(session, at) {
    let best = null;
    for (const sample of session.samples) if (best === null || Math.abs(sample.at - at) < Math.abs(best.at - at)) best = sample;
    return best;
  }
  const api = Object.freeze({ LIMITS, NUMBERS, project, parseFile, stats, nearest });
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.NetworkReportCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
