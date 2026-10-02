/* Local DOM renderer. Never insert report text as HTML or evaluate log content. */
(function () {
  'use strict';
  const C = window.NetworkReportCore;
  const $ = id => document.getElementById(id);
  const state = { reports: [], sessions: [], active: null, marker: -1, page: 0, generation: 0 };
  const safeName = name => String(name).replace(/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, '').slice(0, 160);
  const fmt = (value, unit = '') => value === null || value === undefined ? '未知' :
    `${Number(value.toFixed(1)).toLocaleString('zh-CN')}${unit}`;
  const seconds = ms => fmt(ms / 1000, ' s');
  function element(tag, text, cls) {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    if (cls) node.className = cls;
    return node;
  }
  function option(text, value) { const node = element('option', text); node.value = value; return node; }
  function table(headings, rows) {
    const node = element('table'), head = element('thead'), tr = element('tr');
    headings.forEach(text => { const th = element('th', text); th.scope = 'col'; tr.append(th); });
    head.append(tr); node.append(head);
    const body = element('tbody');
    rows.forEach(row => {
      const line = element('tr');
      row.forEach((text, i) => { const cell = element(i ? 'td' : 'th', text); if (!i) cell.scope = 'row'; line.append(cell); });
      body.append(line);
    });
    node.append(body); return node;
  }
  function reset() {
    state.generation++; state.reports = []; state.sessions = []; state.active = null; state.marker = -1; state.page = 0;
    $('files').value = ''; $('files').disabled = false;
    for (const id of ['comparison', 'file-notices', 'session', 'marker', 'sample-table', 'focus-metrics']) $(id).replaceChildren();
    for (const id of ['session-info', 'selection', 'rtt-caption', 'snapshot-caption', 'rows-page']) $(id).textContent = '';
    $('overview').hidden = $('explorer').hidden = true;
    $('sample-details').open = false;
    // Release file-derived chart pixels as well as parsed objects.
    for (const id of ['rtt-chart', 'snapshot-chart']) {
      $(id).getContext('2d').clearRect(0, 0, $(id).width, $(id).height);
      $(id).setAttribute('aria-label', '尚未加载图表');
    }
    $('status').textContent = '已清空。文件仅在当前页面内存中读取，关闭或清空后不保留。';
  }
  async function loadFiles() {
    const files = Array.from($('files').files);
    if (!files.length) return; // Cancelling the chooser leaves the previous view intact.
    reset();
    if (files.length > C.LIMITS.files) { $('status').textContent = '选择超过 8 个文件，整批未读取；请减少文件数量后重选。'; return; }
    const generation = state.generation;
    $('files').disabled = true;
    for (let i = 0; i < files.length; i++) {
      $('status').textContent = `正在本地读取 ${i + 1} / ${files.length}：${safeName(files[i].name)}。可点「清空」取消。`;
      const report = await C.parseFile(files[i], () => generation !== state.generation);
      if (!report || generation !== state.generation) return;
      state.reports.push(report);
    }
    $('files').disabled = false;
    $('status').textContent = `已读取 ${state.reports.length} 个文件；接受 ${state.reports.reduce((n, r) => n + r.accepted, 0)} 条记录。` +
      (state.reports.some(r => r.failure || r.rejected || r.warnings) ? '存在拒绝或警告，请查看下方行号与原因。' : '没有发现坏行。') + ' 全部处理均在本地。';
    renderOverview();
  }
  function renderOverview() {
    const headings = ['观测范围', ...state.reports.map((r, i) => `${i + 1}. ${safeName(r.name)}`)];
    const samples = state.reports.map(r => r.sessions.flatMap(s => s.samples));
    const row = (label, fn) => [label, ...state.reports.map((r, i) => fn(r, samples[i]))];
    const rows = [
      row('读取状态', r => r.failure ? '读取失败 / 拒绝' : r.stopped ? '不完整：达到上限' : r.rejected || r.warnings ? '有问题，见行号' : '完成'),
      row('文件大小 / 会话', r => `${fmt(r.size / 1024, ' KiB')} / ${r.sessions.length}`),
      row('样本 / 卡顿标记', r => `${r.samples} / ${r.marks}`),
      row('坏行 / 数值警告', r => `${r.rejected} / ${r.warnings}`),
      row('各会话跨度之和', r => r.sessions.length ? seconds(r.sessions.reduce((n, s) => n + s.end - s.start, 0)) : '未知'),
      row('RTT 观测中位数（≥10条）', (_, s) => fmt(C.stats(s, 'rtt_ms', 10).median, ' ms')),
      row('RTT 观测峰值', (_, s) => fmt(C.stats(s, 'rtt_ms').max, ' ms')),
      row('快照未更新峰值', (_, s) => fmt(C.stats(s, 'snapshot_age_ms').max, ' ms')),
      row('FPS 观测最低值', (_, s) => fmt(C.stats(s, 'fps').min)),
      row('最近 1 秒最慢帧 · 峰值', (_, s) => fmt(C.stats(s, 'frame_max_ms').max, ' ms')),
      row('可靠发送丢包估计 · 峰值', (_, s) => fmt(C.stats(s, 'reliable_loss_percent').max, '%')),
      row('已知 RTT / 丢包估计条数', (_, s) => `${C.stats(s, 'rtt_ms').count} / ${C.stats(s, 'reliable_loss_percent').count}`)
    ];
    $('comparison').replaceChildren(table(headings, rows));
    $('overview').hidden = false;
    $('file-notices').replaceChildren();
    state.reports.forEach((report, index) => {
      if (report.failure) $('file-notices').append(element('p', `${index + 1}. ${safeName(report.name)}：${report.failure}`, 'warning'));
      if (report.issues.length) {
        const details = element('details', undefined, 'file-notice');
        details.append(element('summary', `${index + 1}. ${safeName(report.name)}：${report.rejected} 个拒绝，${report.warnings} 个数值警告（展开行号）`));
        const list = element('ul');
        report.issues.forEach(item => list.append(element('li', `第 ${item.line} 行：${item.message}`)));
        details.append(list);
        if (report.rejected + report.warnings > report.issues.length) details.append(element('p', `仅列前 ${C.LIMITS.issues} 个位置，另有 ${report.rejected + report.warnings - report.issues.length} 个问题。`));
        $('file-notices').append(details);
      }
      if (report.stopped) $('file-notices').append(element('p', `${index + 1}. 数据不完整；摘要和图表只覆盖已接受记录。`, 'warning'));
      if (!report.accepted && !report.failure) $('file-notices').append(element('p', `${index + 1}. 没有可显示的 N1 记录；空行 ${report.blank}，拒绝 ${report.rejected}。`, 'warning'));
      report.sessions.forEach((session, i) => {
        const slot = state.sessions.length;
        state.sessions.push({ session, report, fileIndex: index });
        $('session').append(option(`文件 ${index + 1} · 会话 ${i + 1} · ${session.id.slice(0, 8)} · ${session.samples.length} 样本`, slot));
      });
    });
    if (state.sessions.length) { $('explorer').hidden = false; chooseSession(0); }
  }
  function chooseSession(index) {
    state.active = state.sessions[index]; state.marker = -1; state.page = 0;
    const { session: s, report, fileIndex } = state.active;
    $('session-info').textContent = `文件 ${fileIndex + 1}：${safeName(report.name)} · 会话 ${s.id} · 构建 ${Array.from(s.builds).slice(0, 3).join(' / ')}${s.builds.size > 3 ? ' 等' : ''} · 跨度 ${seconds(s.end - s.start)} · 首条 UTC ${s.utc || '未知'}（仅参考）`;
    $('marker').replaceChildren(option(s.marks.length ? `全程 · ${s.marks.length} 个标记` : '没有卡顿标记', -1));
    s.marks.forEach((mark, i) => $('marker').append(option(`#${i + 1} · +${seconds(mark.at - s.start)} · 行 ${mark.line}`, i)));
    $('marker').disabled = !s.marks.length;
    renderTimeline();
  }
  function bounds() {
    const s = state.active.session, mark = s.marks[state.marker];
    return mark ? [Math.max(s.start, mark.at - 15000), Math.min(s.end, mark.at + 15000)] : [s.start, s.end];
  }
  function windowRecords() {
    const [start, end] = bounds();
    return state.active.session.records.filter(r => r.at >= start && r.at <= end);
  }
  function renderTimeline() {
    const s = state.active.session, mark = s.marks[state.marker], [start, end] = bounds();
    $('marker').value = state.marker;
    $('previous').disabled = !s.marks.length || state.marker <= 0;
    $('next').disabled = !s.marks.length || state.marker >= s.marks.length - 1;
    $('all').disabled = state.marker < 0;
    let text = mark ? `标记 #${state.marker + 1} · 第 ${mark.line} 行 · +${seconds(mark.at - s.start)}；窗口为标记前后 15 秒（受文件边界限制）。` : '正在查看全程。紫色竖线是「刚才卡顿」标记；选择标记可查看附近 30 秒。';
    if (mark) {
      const nearby = C.nearest(s, mark.at);
      text += nearby ? ` 最近观测在第 ${nearby.line} 行，与标记相距 ${seconds(Math.abs(nearby.at - mark.at))}。` : ' 会话没有指标观测。';
      if (nearby && Math.abs(nearby.at - mark.at) > 2500) text += ' 附近 2.5 秒没有观测，不能视为同时采样。';
    }
    $('selection').textContent = text;
    drawChart('rtt-chart', [{ key: 'rtt_ms', color: '#70dccb', name: 'RTT' }], 'rtt-caption');
    drawChart('snapshot-chart', [{ key: 'snapshot_age_ms', color: '#70dccb', name: '未更新' },
      { key: 'snapshot_interval_ms', color: '#ffc184', name: '到达间隔', dash: true }], 'snapshot-caption');
    const records = windowRecords();
    const metrics = [ ['FPS 最低观测', C.stats(records, 'fps').min, '', 'fps'],
      ['最近 1 秒最慢帧 · 峰值', C.stats(records, 'frame_max_ms').max, ' ms', 'frame_max_ms'],
      ['可靠发送丢包估计 · 峰值', C.stats(records, 'reliable_loss_percent').max, '%', 'reliable_loss_percent'],
      ['快照未更新 · 峰值', C.stats(records, 'snapshot_age_ms').max, ' ms', 'snapshot_age_ms'] ];
    $('focus-metrics').replaceChildren();
    metrics.forEach(([label, value, unit, key]) => {
      const card = element('div', undefined, 'metric');
      card.append(element('p', label), element('strong', fmt(value, unit)), element('small', `当前窗口 · ${C.stats(records, key).count} 条已知观测`));
      $('focus-metrics').append(card);
    });
    renderRows();
  }
  function drawChart(id, series, captionId) {
    const canvas = $(id), ctx = canvas.getContext('2d'), s = state.active.session;
    const [start, end] = bounds(), records = s.samples.filter(r => r.at >= start && r.at <= end);
    const left = 90, right = 975, top = 30, bottom = 205;
    let peak = 0, known = 0;
    for (const r of records) for (const seriesItem of series) if (r[seriesItem.key] !== null) { known++; peak = Math.max(peak, r[seriesItem.key]); }
    const yMax = Math.max(1, peak * 1.15), span = Math.max(1, end - start);
    const x = at => left + (at - start) / span * (right - left);
    const y = value => bottom - value / yMax * (bottom - top);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.font = '20px system-ui'; ctx.textBaseline = 'middle';
    for (let i = 0; i <= 4; i++) {
      const yy = top + (bottom - top) * i / 4;
      ctx.strokeStyle = '#334455'; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(left, yy); ctx.lineTo(right, yy); ctx.stroke();
      ctx.fillStyle = '#a5b6c5'; ctx.textAlign = 'right';
      const value = yMax * (1 - i / 4);
      ctx.fillText(value >= 10000 ? value.toExponential(1) : fmt(value), left - 10, yy);
    }
    ctx.textAlign = 'center';
    [0, .5, 1].forEach(part => ctx.fillText(`+${fmt((start + span * part - s.start) / 1000)} s`, left + part * (right - left), 235));
    // Do not imply continuity through unknown samples or long logging gaps.
    for (const seriesItem of series) {
      ctx.strokeStyle = seriesItem.color; ctx.fillStyle = seriesItem.color; ctx.lineWidth = 3;
      ctx.setLineDash(seriesItem.dash ? [10, 7] : []);
      let last = null;
      for (const r of records) {
        const value = r[seriesItem.key];
        if (value === null) { last = null; continue; }
        if (last && r.at - last.at <= 2500 && r.phase === last.phase) {
          ctx.beginPath(); ctx.moveTo(x(last.at), y(last[seriesItem.key])); ctx.lineTo(x(r.at), y(value)); ctx.stroke();
        }
        ctx.beginPath(); ctx.arc(x(r.at), y(value), 3, 0, Math.PI * 2); ctx.fill(); last = r;
      }
    }
    ctx.setLineDash([]);
    for (let i = 0; i < s.marks.length; i++) {
      const mark = s.marks[i]; if (mark.at < start || mark.at > end) continue;
      ctx.strokeStyle = '#dcb8fa'; ctx.lineWidth = i === state.marker ? 4 : 1;
      ctx.beginPath(); ctx.moveTo(x(mark.at), top); ctx.lineTo(x(mark.at), bottom); ctx.stroke();
    }
    if (!known) { ctx.fillStyle = '#a5b6c5'; ctx.textAlign = 'center'; ctx.fillText('当前窗口无已知观测', (left + right) / 2, 110); }
    const description = series.map(item => `${item.name}：${C.stats(records, item.key).count} 条已知，峰值 ${fmt(C.stats(records, item.key).max, ' ms')}`).join('；');
    $(captionId).textContent = `${description}。缺测 / 超过 2.5 秒的采样间隔断线；纵轴自动缩放，不宜直接比较两图高度。`;
    canvas.setAttribute('aria-label', `${description}。窗口 +${seconds(start - s.start)} 至 +${seconds(end - s.start)}。逐条数值见下方详情。`);
  }
  function renderRows() {
    const records = windowRecords(), pageCount = Math.max(1, Math.ceil(records.length / 100));
    state.page = Math.min(state.page, pageCount - 1);
    const s = state.active.session;
    const rows = records.slice(state.page * 100, (state.page + 1) * 100).map(r => [
      `${r.line} · +${seconds(r.at - s.start)}${r.kind === 'mark' ? ' · 卡顿标记' : ''}`,
      r.kind === 'mark' ? '未采集（卡顿标记）' : `${r.phase} / ${r.error}`, fmt(r.rtt_ms, ' ms'), fmt(r.snapshot_age_ms, ' ms'), fmt(r.snapshot_interval_ms, ' ms'),
      fmt(r.fps), fmt(r.frame_max_ms, ' ms'), fmt(r.reliable_loss_percent, '%')
    ]);
    $('sample-table').replaceChildren(table(['行号 / 相对时间', '阶段 / 错误类别', 'RTT', '快照未更新', '到达间隔', 'FPS', '最慢帧', '可靠发送丢包估计'], rows));
    $('rows-page').textContent = `${state.page + 1} / ${pageCount} 页 · ${records.length} 条记录`;
    $('rows-prev').disabled = state.page === 0; $('rows-next').disabled = state.page + 1 >= pageCount;
  }
  function chooseMarker(index) { state.marker = index; state.page = 0; renderTimeline(); }
  $('files').addEventListener('change', () => { loadFiles().catch(() => { $('files').disabled = false; $('status').textContent = '页面读取失败，请清空后重新选择；未上传任何文件。'; }); });
  $('clear').addEventListener('click', reset);
  $('session').addEventListener('change', () => chooseSession(Number($('session').value)));
  $('marker').addEventListener('change', () => chooseMarker(Number($('marker').value)));
  $('previous').addEventListener('click', () => chooseMarker(Math.max(0, state.marker - 1)));
  $('next').addEventListener('click', () => chooseMarker(Math.min(state.active.session.marks.length - 1, state.marker + 1)));
  $('all').addEventListener('click', () => chooseMarker(-1));
  $('rows-prev').addEventListener('click', () => { state.page--; renderRows(); });
  $('rows-next').addEventListener('click', () => { state.page++; renderRows(); });
})();
