'use strict';
/*
RUN EVERYTHING — mirrors run.py + dashboard.py's build_dashboard() exactly.

    node tools/build.js

Reads data/planppc.xlsx, runs every scenario, and writes into out/:

    index.html     <- the live site file (run.py's dashboard.html equivalent)
    results.json    <- every scenario and every plan date
    sweep.json      <- what the dashboard's sliders read from

Nothing here decides anything — every assumption is in assumptions.js
(itself a mirror of assumptions.py).
*/
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const A = require('./assumptions');
const M = require('./model');
const S = require('./scenarios');
const DT = require('./daytrace');
const Lab = require('./lab');
const { bankersRound } = require('./round');

const REPO = path.join(__dirname, '..');
const OUT = path.join(REPO, 'out');

// Mirrors run.py's compute_slip() exactly: how far the floor ran behind the
// plan, over every plan date passed in. Computed straight from
// spread_done_at rather than from a trace, because the trace is now built
// one month at a time (see main()) and this needs every date at once.
function computeSlip(days) {
  let dated = 0, late = 0, veryLate = 0;
  for (const date of Object.keys(days)) {
    const midnight = M.midnightUTC(date);
    for (const t of days[date]) {
      const done = t.spread_done_at;
      if (done === null) continue;
      dated += 1;
      const minutes = (done.getTime() - midnight) / 60000;
      if (minutes > 1440) late += 1;
      if (minutes > 2 * 1440) veryLate += 1;
    }
  }
  return {
    dated, late, veryLate,
    latePct: dated ? Math.round(100 * late / dated) : 0,
    veryLatePct: dated ? Math.round(100 * veryLate / dated) : 0,
  };
}

function summarise(result) {
  const perDay = result.per_day;
  delete result.per_day;
  const tpd = result.trolleys_per_day;
  result.fleet_required_allowed_cycle = M.fleetRequired(tpd, A.CYCLE_DAYS_ALLOWED);
  result.fleet_required_estimated_cycle = M.fleetRequired(tpd, A.CYCLE_DAYS_ESTIMATED);
  result.fleet_gap_estimated_cycle = A.FLEET_SIZE - result.fleet_required_estimated_cycle;
  result.longest_sustainable_cycle_days = M.longestSustainableCycle(tpd);
  result.fits_in_fleet = result.fleet_required_estimated_cycle <= A.FLEET_SIZE;
  return perDay;
}

// The rounded sweep-dict shape — mirrors run.py's sweep dict (lines 94-103 +
// step A4's two new keys), applied once at build time (banker's rounding).
function sweepRow(r) {
  return {
    utilization_pct: bankersRound(r.utilization_pct, 2),
    trolleys_per_day: bankersRound(r.trolleys_per_day, 1),
    peak: r.peak_trolleys_in_a_day,
    pieces_per_trolley: bankersRound(r.pieces_per_trolley, 0),
    compartment_fill_pct: bankersRound(r.compartment_fill_pct, 1),
    garments_per_trolley_capacity: bankersRound(r.garments_per_trolley_capacity, 0),
    avg_wait_hours: bankersRound(r.avg_wait_hours, 2),
    spreading_blocked_pct: bankersRound(r.spreading_blocked_pct, 1),
    cutting_blocked_pct: bankersRound(r.cutting_blocked_pct, 1),
    blocked_by_space: r.blocked_by_space,
  };
}

function buildPayload({ started, days, skipped }) {
  // The published model is the carry-over floor (M.runCarry): no cold start,
  // work is always left from the day before.
  const headline = {};
  const headlineDays = {};
  for (const scenario of S.HEADLINE) {
    const r = M.runCarry(scenario, days);
    headlineDays[scenario.name] = summarise(r);
    headline[scenario.name] = r;
  }

  const variants = {};
  for (const scenario of S.HOLD_VARIANTS) {
    const r = M.runCarry(scenario, days);
    summarise(r);
    variants[scenario.name] = r;
  }

  const combos = S.sweepScenarios();
  const sweep = {};
  for (const [key, scenario] of combos) {
    const r = M.runCarry(scenario, days);
    summarise(r);
    sweep[key] = sweepRow(r);
  }

  const slip = computeSlip(days);

  // What the Gantt draws its shift bands from, at every cutter count the
  // Simulation tab's control can reach — not just the 5-cutter default.
  const layoutsByCount = {};
  for (const n of A.SIM_CUTTER_COUNTS) layoutsByCount[n] = M.machineLayout(A.CUT_GROUPS_BY_CUTTER_COUNT[n]);

  const dateKeys = Object.keys(days);
  const tableCount = dateKeys.reduce((s, d) => s + days[d].length, 0);

  const payload = {
    generated_seconds: bankersRound((Date.now() - started) / 1000, 1),
    plan_dates: dateKeys.length,
    tables: tableCount,
    assumptions: {
      fleet_size: A.FLEET_SIZE,
      cycle_days_allowed: A.CYCLE_DAYS_ALLOWED,
      cycle_days_estimated: A.CYCLE_DAYS_ESTIMATED,
      trolley_compartments: A.TROLLEY_COMPARTMENTS,
      compartment_cap: A.COMPARTMENT_CAP,
      max_batches_per_trolley: A.MAX_BATCHES_PER_TROLLEY,
      trolley_bays: A.TROLLEY_BAYS,
      wip_hold_minutes: A.WIP_HOLD_MINUTES,
      wip_hold_any_workstation: A.WIP_HOLD_ANY_WORKSTATION,
      max_trolleys_per_combine: A.MAX_TROLLEYS_PER_COMBINE,
      relax_hours: A.RELAX_HOURS,
      spreading_table_length_m: A.SPREADING_TABLE_LENGTH_M,
      shift_start_minute: A.SHIFT_START_MINUTE,
      film_size_by_garment_size: A.FILM_SIZE_BY_GARMENT_SIZE,
    },
    cut_groups: A.CUT_GROUPS,
    night_shift_spreaders: Array.from(A.NIGHT_SHIFT_SPREADERS).sort(),
    night_shift_cutters: Array.from(A.NIGHT_SHIFT_CUTTERS).sort(),
    spreader_shift: Object.fromEntries(M.SPREADERS.map(m => [m, M.SPREADER_SHIFT[m]])),
    cutter_shift: Object.fromEntries(Object.keys(A.CUT_GROUPS).map(c => [c, M.CUTTER_SHIFT[c]])),
    machine_minutes: M.MACHINE_MINUTES,
    shift_end: M.SHIFT_END,
    day_shift_end: A.DAY_SHIFT[1],
    // unique table lengths across the variants, in variant order — still
    // just ['21.2', '24', '27'], the table-length control's own axis.
    table_lengths_m: Array.from(new Set(DT.SIM_VARIANTS.map(([m]) => DT.metresKey(m)))),
    status_colors: A.TASK_STATUS_COLORS,
    status_not_simulated: A.TASK_STATUS_NOT_SIMULATED,
    headline,
    hold_variants: variants,
    sweep,
    sweep_axes: {
      hold_minutes: S.SWEEP_HOLD_MINUTES,
      max_batches: S.SWEEP_MAX_BATCHES,
    },
    per_day: headlineDays,
    // ---- the cutter axis (plan §6.5's new payload keys) ----
    sim_variants: DT.SIM_VARIANTS.map(([m, c, full]) => ({
      key: DT.variantKey(m, c), metres: m, cutters: c, full,
      label: `${DT.metresKey(m)} m / ${c} cutters`,
    })),
    cutter_counts: Array.from(A.SIM_CUTTER_COUNTS),
    cut_groups_by_cutter_count: A.CUT_GROUPS_BY_CUTTER_COUNT,
    cutter_shift_by_cutter_count: Object.fromEntries(
      A.SIM_CUTTER_COUNTS.map(n => [String(n), layoutsByCount[n].cutter_shift])),
    cutter_minutes_by_cutter_count: Object.fromEntries(
      A.SIM_CUTTER_COUNTS.map(n => [String(n), layoutsByCount[n].cutter_minutes])),
    slip,
    baseline_variant: DT.variantKey(...DT.BASELINE_VARIANT),
  };

  return { payload };
}

// ------------------------------------------------------------- the template
// dashboard.py holds the whole page as one raw string, `TEMPLATE = r"""..."""`
// from its own line 52 to line 1595. Slice that block out and do the exact
// same replace dashboard.py's build_dashboard() does — never hand-copy the
// HTML/JS into a .js file, so dashboard.py stays the single source of the
// page (and of the Gantt fix).
function extractTemplate() {
  const src = fs.readFileSync(path.join(REPO, 'dashboard.py'), 'utf8');
  const marker = 'TEMPLATE = r"""';
  const start = src.indexOf(marker);
  if (start === -1) throw new Error('dashboard.py: TEMPLATE marker not found');
  const bodyStart = start + marker.length;
  const end = src.indexOf('"""', bodyStart);
  if (end === -1) throw new Error('dashboard.py: TEMPLATE close not found');
  return src.slice(bodyStart, end);
}

// The Rules Lab tab. The page runs tools/lab.js itself (inlined below); this
// precomputes a few option sets with the SAME file in Node, so the page can
// re-run them and prove both runtimes agree (parity_check.js -> __labCheck).
// Node-only: dashboard.py's Python build carries no `lab` and the tab stays
// hidden there.
const LAB_CFG = Lab.makeConfig(A);
// The Lab pools every in-scope plan date, as the Utilization tab does, so this
// block is the same in every month file: built once. The tasks travel as
// gzipped columnar JSON (base64); the page unzips them with the browser's own
// DecompressionStream. `expected` are option sets Node ran with the same
// lab.js, which the page re-runs to prove both runtimes agree.
function labBlock(days) {
  const E = Lab.createEngine(LAB_CFG);
  const input = DT.labInput(days);
  const V = LAB_CFG.addOnValues;
  const full = { shift: 'both', dispatch: 'static', recall: 'model',
    relax: LAB_CFG.defaults.relax, setupMin: LAB_CFG.defaults.setupMin, travelMin: LAB_CFG.defaults.travelMin, pullAhead: 0, holdMin: 0, relaxMinH: LAB_CFG.defaults.relaxMinH,
    relaxMaxH: LAB_CFG.defaults.relaxMaxH };
  const cont = Object.assign({}, full, { recall: 'sameFirst', relax: true, setupMin: V.setupMin,
    travelMin: V.travelMin, pullAhead: V.pullAhead, ruleA: true, mix: true, seqMode: 'cross_batch', holdMin: V.holdMin });
  const sets = [];
  for (const st of Lab.ladder(full, V)) sets.push(st.opt);
  for (const st of Lab.ladder(cont, V)) sets.push(st.opt);
  for (const shift of ['day', 'night']) sets.push(Object.assign({}, cont, { shift }));
  sets.push(Object.assign({}, cont, { relax: false }));
  sets.push(Object.assign({}, cont, { recall: 'sameOnly' }));
  sets.push(Object.assign({}, cont, { live: false, relax: false }));    // the floor of 2026-11-09, as the page can still run it
  const seen = new Set(), expected = [];
  for (const opt of sets) {
    const k = JSON.stringify(opt);
    if (seen.has(k)) continue;
    seen.add(k);
    expected.push({ opt, r: Lab.summary(E.run(input, opt)) });
  }
  // the 100k-a-day plan (Output panel): the published S0 and S3, and every add-on on
  const fullSteps = Lab.ladder(full, V), contSteps = Lab.ladder(cont, V);
  const expected100 = [fullSteps[0].opt, fullSteps[3].opt, contSteps[contSteps.length - 1].opt]
    .map(opt => ({ opt, r: Lab.summary(E.run100k(input, opt)) }));
  const gz = zlib.gzipSync(Buffer.from(JSON.stringify(DT.labData(days))), { level: 9 });
  return { cfg: LAB_CFG, expected, expected100, data: gz.toString('base64') };
}

// Mirrors dashboard.py's build_dashboard() exactly. `payload` is identical
// across every month file (G7); `trace`, `months`, `month` and `lab` are this
// file's own.
function buildDashboardHtml(payload, trace, months, month, lab) {
  const data = {
    sweep: payload.sweep,
    assumptions: payload.assumptions,
    headline: Object.fromEntries(Object.entries(payload.headline).map(([k, v]) => [k, {
      name: k,
      util: bankersRound(v.utilization_pct, 2),
      tpd: bankersRound(v.trolleys_per_day, 1),
      settings: v.settings,
    }])),
    holdMinutes: payload.sweep_axes.hold_minutes,
    maxBatches: payload.sweep_axes.max_batches,
    planDates: payload.plan_dates,
    tables: payload.tables,
    slip: payload.slip,
    baselineVariant: payload.baseline_variant,
    months,
    month,
    cutGroups: payload.cut_groups,
    simVariants: payload.sim_variants,
    cutterCounts: payload.cutter_counts,
    cutGroupsByCutterCount: payload.cut_groups_by_cutter_count,
    cutterShiftByCutterCount: payload.cutter_shift_by_cutter_count,
    cutterMinutesByCutterCount: payload.cutter_minutes_by_cutter_count,
    nightSpreaders: payload.night_shift_spreaders,
    nightShiftCutters: payload.night_shift_cutters,
    spreaderShift: payload.spreader_shift,
    cutterShift: payload.cutter_shift,
    shiftEnd: payload.shift_end,
    dayShiftEnd: payload.day_shift_end,
    tableLengths: payload.table_lengths_m,
    statusColors: payload.status_colors,
    statusNotSimulated: payload.status_not_simulated,
    trace,
    lab,
  };
  const json = JSON.stringify(data);
  const template = extractTemplate();
  if (template.indexOf('/*__DATA__*/null') === -1) {
    throw new Error('dashboard.py: /*__DATA__*/null marker not found in TEMPLATE');
  }
  if (template.indexOf('/*__LAB__*/') === -1) {
    throw new Error('dashboard.py: /*__LAB__*/ marker not found in TEMPLATE');
  }
  // floor.js (the live floor's timeline, shared with model.js) goes in before lab.js, which needs it
  const labSrc = fs.readFileSync(path.join(__dirname, 'floor.js'), 'utf8') + '\n' + fs.readFileSync(path.join(__dirname, 'lab.js'), 'utf8');
  if (labSrc.indexOf('</script') !== -1) throw new Error('tools/floor.js or tools/lab.js contains </script and cannot be inlined');
  // function replacers: the engine and the JSON may contain '$' sequences
  return template.replace('/*__LAB__*/', () => labSrc).replace('/*__DATA__*/null', () => json);
}

function main() {
  const started = Date.now();
  console.log('Reading', A.DATA_FILE);
  const [allDays, allSkipped] = M.loadDays(path.join(REPO, A.DATA_FILE), true);
  console.log(`  ${Object.keys(allDays).length} plan dates in the file, ` +
              `${Object.keys(allDays).reduce((s, d) => s + allDays[d].length, 0)} tables`);

  // WEBSITE SCOPE — mirrors run.py's matching filter (assumptions.py has the
  // full reasoning, user decision 2026-09-08). loadDays() above still read
  // every date in the file; this is the one place the scope narrows.
  const inScope = d => A.WEBSITE_MONTHS.includes(d.slice(0, 7));
  const days = {}, skipped = {};
  for (const d of Object.keys(allDays)) if (inScope(d)) days[d] = allDays[d];
  for (const d of Object.keys(allSkipped)) if (inScope(d)) skipped[d] = allSkipped[d];
  const dateKeys = Object.keys(days);
  const tableCount = dateKeys.reduce((s, d) => s + days[d].length, 0);
  console.log(`  scoped to [${A.WEBSITE_MONTHS.join(', ')}]: ${dateKeys.length} plan dates, ` +
              `${tableCount} tables, ${Math.round(tableCount / dateKeys.length)} per day\n`);

  const { payload } = buildPayload({ started, days, skipped });

  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, 'results.json'), JSON.stringify(payload, null, 1));
  fs.writeFileSync(path.join(OUT, 'sweep.json'),
    JSON.stringify({ sweep: payload.sweep, assumptions: payload.assumptions }, null, 1));
  console.log(`wrote ${OUT}\\results.json  ${OUT}\\sweep.json`);

  // ------------------------------------------------------- the month files
  // Built one calendar month at a time and freed before the next — the full
  // 199-date trace does not fit the page's size budget (plan §6.2/§6.3), and
  // holding all of it in memory at once was the dominant cost of this build.
  const monthsChrono = Array.from(new Set(dateKeys.map(d => d.slice(0, 7)))).sort();
  const monthsInfo = monthsChrono.map(m => ({
    key: m, count: dateKeys.filter(d => d.slice(0, 7) === m).length,
  }));

  // June is the stress test — the most dates of any month — so it is built
  // first and checked against the size gate (plan §6.3's decision rule)
  // before the other 7 months are spent building.
  const buildOrder = monthsChrono.slice();
  const juneIdx = buildOrder.indexOf('2026-06');
  if (juneIdx > 0) { buildOrder.splice(juneIdx, 1); buildOrder.unshift('2026-06'); }

  const lab = labBlock(days);
  console.log(`RULES LAB — ${lab.expected.length} option sets precomputed, ${(lab.data.length / 1024).toFixed(0)} KB of task data per file`);
  console.log(`TRACE — ${buildOrder.length} month files`);
  // Keyed by month, not "whatever the loop processed last" — buildOrder is
  // reordered above (June-first) purely so the size-gate check runs before
  // the other months are spent building; it must not also decide which
  // month out/index.html mirrors. A bug of exactly this shape shipped in
  // Phase 4 and stayed invisible for as long as June (the reordered month)
  // also happened to be chronologically last across all 8 months — it
  // surfaced the moment the scope narrowed to Apr-Jun, where June is still
  // chronologically last but processed FIRST by buildOrder, so the old
  // "lastPath = outPath on every iteration" pattern silently pointed
  // index.html at May instead. Fixed 2026-09-08.
  const outputByMonth = {};
  for (const month of buildOrder) {
    const monthDays = {};
    for (const d of dateKeys) if (d.slice(0, 7) === month) monthDays[d] = days[d];
    const trace = DT.buildTrace(monthDays, skipped, days);
    const outPath = path.join(OUT, `sim-${month}.html`);
    const html = buildDashboardHtml(payload, trace, monthsInfo, month, lab);
    fs.writeFileSync(outPath, html, 'utf8');
    const mb = Buffer.byteLength(html, 'utf8') / (1024 * 1024);
    const nDates = Object.keys(monthDays).length;
    const nTables = Object.values(monthDays).reduce((s, v) => s + v.length, 0);
    console.log(`  wrote ${outPath}  (${nDates} dates, ${nTables} tables, ${mb.toFixed(2)} MB)`);
    if (month === '2026-06') {
      console.log(`  SIZE GATE — June ${mb.toFixed(2)} MB against the 1.7 MB budget `
        + `(${mb <= 1.7 ? 'within budget' : 'OVER BUDGET — see plan §6.3\'s decision rule'})`);
    }
    outputByMonth[month] = outPath;
  }
  const lastPath = outputByMonth[monthsChrono[monthsChrono.length - 1]];

  // out/index.html mirrors the most recent month, so the existing entry
  // point keeps working without every reader needing to know the month URLs.
  fs.copyFileSync(lastPath, path.join(OUT, 'index.html'));
  console.log(`wrote ${OUT}\\index.html (copy of ${lastPath})`);

  console.log(`\ndone in ${((Date.now() - started) / 1000).toFixed(0)}s`);
}

module.exports = { summarise, sweepRow, computeSlip, buildPayload, buildDashboardHtml, extractTemplate, labBlock };

if (require.main === module) {
  main();
}
