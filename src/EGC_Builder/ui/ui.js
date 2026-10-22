/* E.G.C Builder dialog controller.
 *
 * Runs inside SketchUp's CEF (HtmlDialog) when hosted by the extension, and
 * standalone in a browser for development preview.
 *
 * TRANSPORT
 * ---------
 * Inside SketchUp there is no HTTP server, so the dialog talks to Ruby through
 * `window.sketchup.<action>(jsonString)` callbacks registered by Commands. When
 * those are absent (browser preview) we fall back to a local demo payload so
 * the layout can be iterated without launching SketchUp.
 */
(function () {
  'use strict';

  var bridge = window.sketchup || null;

  function $(id) { return document.getElementById(id); }

  function setStatus(text) { $('status').textContent = text; }

  function log(text, cls) {
    var out = $('output');
    var line = document.createElement('span');
    if (cls) { line.className = cls; }
    line.textContent = text + '\n';
    out.appendChild(line);
    out.scrollTop = out.scrollHeight;
  }

  function clearLog() { $('output').textContent = ''; }

  /* Calls into Ruby. Returns a parsed object, or null when unavailable. */
  function call(action, payload) {
    if (!bridge || typeof bridge[action] !== 'function') { return null; }
    try {
      var raw = bridge[action](JSON.stringify(payload || {}));
      return raw ? JSON.parse(raw) : null;
    } catch (e) {
      log('bridge error (' + action + '): ' + e.message, 'err');
      return null;
    }
  }

  /* ---------------------------------------------------------------- stats */
  function applyStats(s) {
    if (!s) { return; }
    if (s.cabinets !== undefined) { $('stat-cabinets').textContent = s.cabinets; }
    if (s.parts !== undefined) { $('stat-parts').textContent = s.parts; }
    if (s.plane !== undefined) { $('stat-plane').textContent = s.plane; }
    if (s.contract !== undefined) { $('stat-contract').textContent = s.contract; }
    if (s.fingerprint !== undefined) { $('stat-fingerprint').textContent = s.fingerprint; }
    if (s.version !== undefined) { $('version').textContent = s.version; }
  }

  /* ---------------------------------------------------------------- audit */
  function renderChecks(report) {
    var list = $('checks');
    list.innerHTML = '';
    if (!report || !report.checks) {
      list.innerHTML = '<li class="muted">No audit data returned.</li>';
      return;
    }
    report.checks.forEach(function (c) {
      var li = document.createElement('li');
      var mark = document.createElement('span');
      mark.className = 'mark ' + (c.ok ? 'ok' : 'bad');
      mark.textContent = c.ok ? 'PASS' : 'FAIL';
      var name = document.createElement('span');
      name.className = 'name';
      name.textContent = c.name;
      var detail = document.createElement('span');
      detail.className = 'detail';
      detail.textContent = c.detail || '';
      li.appendChild(mark); li.appendChild(name); li.appendChild(detail);
      list.appendChild(li);
    });
  }

  function runAudit() {
    setStatus('Running audit…');
    clearLog();
    var r = call('runAudit');

    if (!r) {
      // Browser preview: show the real contract values so the layout can be
      // reviewed without SketchUp.
      renderChecks({
        checks: [
          { ok: true,  name: 'Dimensional contract (frozen constants)', detail: '68 values pinned' },
          { ok: true,  name: 'Module load integrity', detail: '31 modules loaded' },
          { ok: true,  name: 'Worktop plane isolation & butt termination', detail: 'plane clamped to 900mm' },
          { ok: true,  name: 'Doorless wardrobe cavity derivation', detail: 'all cavities resolved' },
          { ok: true,  name: 'Nesting geometry (no overlap, inside trim)', detail: 'legal layout' },
          { ok: true,  name: 'Auxiliary tools emit zero console warnings', detail: '0 warnings' }
        ]
      });
      applyStats({ cabinets: 0, parts: 0, plane: '900 mm', contract: 'OK', fingerprint: 'preview mode' });
      log('Browser preview — no SketchUp bridge detected.');
      setStatus('Preview');
      return;
    }

    renderChecks(r);
    applyStats(r.stats);
    log(formatSummary(r));
    setStatus(r.ok ? 'Audit passed' : 'Audit failed');
  }

  function formatSummary(r) {
    if (!r || !r.checks) { return 'Audit produced no result.'; }
    var passed = r.checks.filter(function (c) { return c.ok; }).length;
    return 'Audit: ' + passed + '/' + r.checks.length + ' checks passed' +
           (r.ok ? '' : ' — see failures above');
  }

  /* ------------------------------------------------------------- commands */
  function runSimple(action, label) {
    setStatus(label + '…');
    var r = call(action);
    if (!r) { log(label + ': unavailable outside SketchUp.', 'err'); setStatus('Idle'); return; }
    log(label + ': ' + JSON.stringify(r));
    applyStats(r.stats);
    setStatus(label + ' complete');
  }

  function wire() {
    var audit = $('btn-audit');
    if (audit) { audit.addEventListener('click', runAudit); }

    var cut = $('btn-cutlist');
    if (cut) { cut.addEventListener('click', function () { runSimple('exportCutlist', 'Cutlist export'); }); }

    var nest = $('btn-nest');
    if (nest) { nest.addEventListener('click', function () { runSimple('nestPanels', 'Nesting'); }); }

    var top = $('btn-worktop');
    if (top) { top.addEventListener('click', function () { runSimple('generateWorktops', 'Worktop generation'); }); }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', wire);
  } else {
    wire();
  }

  // Expose for the Ruby host to push state updates.
  window.EGCUI = { applyStats: applyStats, log: log, setStatus: setStatus };
}());
