'use strict';
/* RULES LAB — gates and tables, from the same engine the page runs.
 * ================================================================
 * tools/build.js inlines tools/lab.js into the page, so what this prints is
 * what the Rules Lab tab shows for the same options.
 *
 *   node --max-old-space-size=6144 tools/lab_table.js            # checks + tables
 *   node --max-old-space-size=6144 tools/lab_table.js --checks   # checks only
 *
 * The checks prove the Lab, on its defaults, IS the published model:
 *   1. the page's compact data decodes to exactly model.js's tasks;
 *   2. every one of the 117 sweep scenarios + the 4 headline + 5 hold variants
 *      equals model.runCarry() on every reported field, exactly, with the pairs
 *      rule (default) and with the option "Keep an MO on one cut group" on; the
 *      39 'today' keys must not move with the option;
 *   3. every task's machine, cutter, spread/cut start and end, and cutter setup and
 *      travel minutes equal model.js's carryTimeline(), for every date and mode;
 *   4. the arrangement detail (pairs, trolleys, setup, travel) adds up.
 *
 * ESTIMATES (assumptions.py): fabric arrival window, cutter setup minutes,
 * cutter travel minutes. None is measured. Cutter setup and travel are part of
 * the published floor since 2026-11-09; the arrival window is an add-on.
 */
const path = require('path');
const A = require('./assumptions');
const M = require('./model');
const S = require('./scenarios');
const DT = require('./daytrace');
const Lab = require('./lab');

const REPO = path.join(__dirname, '..');
const cfg = Lab.makeConfig(A);
const E = Lab.createEngine(cfg);
const V = cfg.addOnValues;
// ESTIMATE sensitivity only (not a model default): a longer setup/travel, to see how lost time responds.
const SENS_SETUP = 10, SENS_TRAVEL = 2;

function scopeDays(all, months) {
  const out = {};
  for (const d of Object.keys(all)) if (months.includes(d.slice(0, 7))) out[d] = all[d];
  return out;
}
const pct = (a, b) => (b ? (100 * a / b).toFixed(1) : '0.0');
const f1 = v => v.toFixed(1), f2 = v => v.toFixed(2);

// model.runCarry() key -> where the Lab reports the same quantity
const FIELDS = [
  ['utilization_pct', r => r.utilizationPct], ['trolleys_per_day', r => r.trolleysPerDay],
  ['peak_trolleys_in_a_day', r => r.model.peak], ['compartments_per_day', r => r.compartmentsPerDay],
  ['compartment_fill_pct', r => r.fillPct], ['garments_per_trolley_capacity', r => r.garmentsCapacity],
  ['pieces_per_trolley', r => r.piecesPerTrolley], ['spreading_blocked_pct', r => r.model.spreadingBlockedPct],
  ['cutting_blocked_pct', r => r.model.cuttingBlockedPct], ['spreading_makespan_hours', r => r.model.spreadingMakespanH],
  ['spreading_blocked_minutes', r => r.model.spreadingBlockedMin], ['spreading_overrun_minutes', r => r.model.spreadingOverrunMin],
  ['machines_over_window', r => r.model.machinesOverWindow], ['avg_wait_hours', r => r.avgWaitH],
  ['blocked_by_space', r => r.blockedBySpace],
];

// ---------------------------------------------------------------- checks
function checks(days) {
  let ok = true;
  const say = (pass, msg) => { ok = ok && pass; console.log(`   ${pass ? 'PASS' : 'FAIL'}  ${msg}`); };
  const raw = DT.labInput(days);

  console.log('\n1. DATA — the page\'s compact form decodes to model.js\'s tasks, bit for bit');
  const dec = Lab.decode(JSON.parse(JSON.stringify(DT.labData(days))), cfg);
  let bad = 0, nT = 0;
  for (const d of raw.dates) {
    const a = raw.tasks[d], b = dec.tasks[d];
    if (!b || a.length !== b.length) { bad += 1; continue; }
    for (let k = 0; k < a.length; k++) {
      nT += 1;
      const x = a[k], y = b[k];
      if (x.i !== y.i || x.tableNo !== y.tableNo || x.mo !== y.mo || x.color !== y.color || x.batch !== y.batch
        || x.spread !== y.spread || x.cut !== y.cut || x.len !== y.len || x.needs !== y.needs || x.pt !== y.pt
        || JSON.stringify(x.pieces) !== JSON.stringify(y.pieces)) bad += 1;
    }
  }
  const bfBad = Object.keys(raw.batchFirst).filter(b => raw.batchFirst[b] !== dec.batchFirst[b]).length;
  say(bad === 0 && bfBad === 0, `${nT} tasks across ${raw.dates.length} dates, ${Object.keys(raw.batchFirst).length} batch first-dates`);
  const gz = require('zlib').gzipSync(Buffer.from(JSON.stringify(DT.labData(days)))).length;
  console.log(`         compact data ${(gz / 1024).toFixed(0)} KB gzipped (${(gz * 4 / 3 / 1024).toFixed(0)} KB base64)`);

  console.log('\n2. SAME RESULTS — every reported field, exact, against the model');
  const combos = S.sweepScenarios();
  const all = [];
  for (const [key, sc] of combos) all.push([key, sc]);
  for (const sc of S.HEADLINE) all.push([sc.name, sc]);
  for (const sc of S.HOLD_VARIANTS) all.push([sc.name, sc]);
  // the option "Keep an MO on one cut group" (old S1-S3 rule), on every scenario it can change
  const nDefault = all.length;
  for (const [key, sc] of combos) if (sc.sequencing_mode !== 'today') all.push([key + ' [MO on one cut group]', M.makeScenario(Object.assign({}, sc, { mo_one_group: true }))]);
  for (const sc of S.HEADLINE.concat(S.HOLD_VARIANTS)) if (sc.sequencing_mode !== 'today') all.push([sc.name + ' [MO on one cut group]', M.makeScenario(Object.assign({}, sc, { mo_one_group: true }))]);
  const cmp = { n: 0, bad: 0, worst: '' };
  for (const [name, sc] of all) {
    const key = S.sweepKey(sc.sequencing_mode, sc.max_batches, sc.wip_hold_minutes, sc.hold_any_workstation);
    const m = M.runCarry(sc, days), r = E.run(raw, Object.assign(Lab.optFromSweepKey(key), { moOneGroup: sc.mo_one_group }));
    for (const [mk, get] of FIELDS) {
      cmp.n += 1;
      if (get(r) !== m[mk]) { cmp.bad += 1; if (!cmp.worst) cmp.worst = `${name} ${mk}: lab ${get(r)} model ${m[mk]}`; }
    }
  }
  say(cmp.bad === 0, `Lab vs model.runCarry()                : ${nDefault} pairs-rule scenarios + ${all.length - nDefault} with the MO kept on one cut group, x ${FIELDS.length} fields = ${cmp.n} comparisons, ${cmp.bad} differ${cmp.worst ? '  (first: ' + cmp.worst + ')' : ''}`);

  // S0 ignores the option: every 'today' sweep key must be bit-identical with it on and off
  let tBad = 0, tN = 0;
  for (const [key, sc] of combos) {
    if (sc.sequencing_mode !== 'today') continue;
    tN += 1;
    const off = M.runCarry(sc, days), on = M.runCarry(M.makeScenario(Object.assign({}, sc, { mo_one_group: true })), days);
    const lo = E.run(raw, Lab.optFromSweepKey(key)), ln = E.run(raw, Object.assign(Lab.optFromSweepKey(key), { moOneGroup: true }));
    if (JSON.stringify(off) !== JSON.stringify(on) || JSON.stringify(Lab.summary(lo)) !== JSON.stringify(Lab.summary(ln))) tBad += 1;
  }
  say(tBad === 0 && tN === 39, `S0 ignores the option: ${tN} 'today' sweep keys identical with it on and off, model and Lab (${tBad} differ)`);

  // The what-ifs moved from the Simulation tab (2026-11-14): cutter count and table length, against
  // model.runCarry() on the same layout and table. Only the selection gets them; S0 stays at today's floor.
  const floors = [];
  for (const n of cfg.cutterCounts) for (const m of cfg.tableOptionsM) if (n !== A.CUTTER_COUNT || m !== A.SPREADING_TABLE_LENGTH_M) floors.push([n, m]);
  const fcmp = { n: 0, bad: 0, worst: '' };
  for (const [n, metres] of floors) {
    const layout = M.machineLayout(A.CUT_GROUPS_BY_CUTTER_COUNT[n]);
    for (const sc of S.HEADLINE) {
      const key = S.sweepKey(sc.sequencing_mode, sc.max_batches, sc.wip_hold_minutes, sc.hold_any_workstation);
      const m = M.runCarry(sc, days, { layout, tableLength: metres * A.YARDS_PER_METRE });
      const r = E.run(raw, Object.assign(Lab.optFromSweepKey(key), { cutters: n, tableM: metres }));
      for (const [mk, get] of FIELDS) {
        fcmp.n += 1;
        if (get(r) !== m[mk]) { fcmp.bad += 1; if (!fcmp.worst) fcmp.worst = `${n} cutters ${metres} m ${sc.name} ${mk}: lab ${get(r)} model ${m[mk]}`; }
      }
    }
  }
  say(fcmp.bad === 0, `Lab vs model.runCarry() on other floors  : ${floors.length} floors (cutters ${cfg.cutterCounts.join('/')} x table ${cfg.tableOptionsM.join('/')} m, but today's) x ${S.HEADLINE.length} scenarios x ${FIELDS.length} fields = ${fcmp.n} comparisons, ${fcmp.bad} differ${fcmp.worst ? '  (first: ' + fcmp.worst + ')' : ''}`);
  const f5 = E.run(raw, Object.assign(Lab.optFromSweepKey('today|1|0|1'), { cutters: A.CUTTER_COUNT, tableM: A.SPREADING_TABLE_LENGTH_M }));
  say(JSON.stringify(Lab.summary(f5)) === JSON.stringify(Lab.summary(E.run(raw, Lab.optFromSweepKey('today|1|0|1')))), 'the default floor chosen explicitly equals the default (cutters 5, 21.2 m)');

  console.log('\n3. SAME ARRANGEMENT — every task\'s machine, cutter and times');
  let cStamp = 0, cBad = 0, cWorst = '', cRuns = 0;
  for (const [mode, flag] of [['today', false], ['same_batch', false], ['cross_batch', false], ['same_batch', true], ['cross_batch', true]]) {
    // the same tasks, one timeline, against model.carryTimeline()
    cRuns += 1;
    const rc = E.run(raw, Object.assign(Lab.optFromSweepKey(`${mode}|1|0|1`), { moOneGroup: flag }));
    const sim = M.carryTimeline(days, mode, undefined, undefined, flag), byDateC = {};
    for (const t of rc.detail.tasks) (byDateC[t.date] || (byDateC[t.date] = [])).push(t);
    for (const d of sim.dates) sim.byDate[d].forEach((c, i) => {
      const t = byDateC[d][i];
      cStamp += 1;
      if (t.m !== c.machine || t.cutter !== c.cutter || t.sb !== c.spread_start || t.se !== c.spread_end
        || t.cb !== c.cut_start || t.ce !== c.cut_end || t.setup !== c.cut_setup_minutes || t.travel !== c.cut_travel_minutes) { cBad += 1; if (!cWorst) cWorst = `${mode}${flag ? ' [MO on one cut group]' : ''} ${d} table ${c.table_no}`; }
    });
  }
  say(cBad === 0, `Lab vs model.carryTimeline():        ${cRuns} runs (3 modes + 2 with the MO kept on one cut group) x ${raw.dates.length} dates, ${cStamp} tasks, ${cBad} differ${cWorst ? '  (first: ' + cWorst + ')' : ''}`);

  // The live floor's own rules (tools/floor.js), checked on every table of the published S0 and S3 runs.
  for (const key of ['today|1|0|1', 'cross_batch|2|60|1']) {
    const ts = E.run(raw, Lab.optFromSweepKey(key)).detail.tasks;
    let early = 0, notReady = 0, overlap = 0;
    const byCutter = {};
    for (const t of ts) {
      if (t.cbA < t.seA - 1e-9) early += 1;           // a cut never starts before its spreading ends
      if (t.sbA < t.rel - 1e-9) notReady += 1;        // a table never starts before it is ready
      (byCutter[t.cutter] || (byCutter[t.cutter] = [])).push(t);
    }
    for (const c of Object.keys(byCutter)) {
      const a = byCutter[c].slice().sort((x, y) => x.cbA - y.cbA);
      for (let i = 1; i < a.length; i++) if (a[i].cbA < a[i - 1].ceA - 1e-6) overlap += 1;   // a cutter never cuts two lays at once
    }
    say(early === 0 && notReady === 0 && overlap === 0,
      `live floor, ${key}: ${ts.length} tables, cut before spread end ${early}, started before ready ${notReady}, cutter overlaps ${overlap}`);
  }

  console.log('\n4. ARRANGEMENT DETAIL — adds up, on the add-ons that change it most');
  const sel = { ruleA: true, mix: true, holdMin: V.holdMin, recall: 'sameFirst',
    relax: true, setupMin: V.setupMin, travelMin: V.travelMin, pullAhead: V.pullAhead };
  for (const [label, opt] of [['published S3', Lab.optFromSweepKey('cross_batch|2|60|1')],
    ['carry-over, all add-ons', sel], ['night only', Object.assign({}, sel, { shift: 'night' })],
    ['day only', Object.assign({}, sel, { shift: 'day' })]]) {
    const r = E.run(raw, opt), dt = r.detail;
    const nTasks = raw.dates.reduce((s, d) => s + raw.tasks[d].length, 0);
    const ids = new Set(dt.tasks.map(t => t.id));
    const compSum = dt.trolleys.reduce((s, t) => s + t.comps.length, 0);
    const qty = dt.trolleys.reduce((s, t) => s + t.comps.reduce((a, c) => a + c.qty, 0), 0);
    const byId = new Map(dt.tasks.map(t => [t.id, t]));
    const adjacent = dt.pairs.every(([a, b]) => { const x = byId.get(a), y = byId.get(b);
      return x.m === y.m && x.date === y.date && x.seA <= y.sbA + 1e-9; });
    const setupSum = dt.tasks.reduce((s, t) => s + t.setup, 0), travelSum = dt.tasks.reduce((s, t) => s + t.travel, 0);
    const busy = r.sp.busy + r.sp.blocked + r.sp.starved <= r.sp.staffed * (1 + 1e-9)
      && r.cu.cut + r.cu.setup + r.cu.travel <= r.cu.staffed * (1 + 1e-9);
    say(ids.size === nTasks && dt.tasks.length === nTasks && dt.trolleys.length === r.trolleys && compSum === r.compartments
      && qty === r.pieces && Math.abs(setupSum - r.cu.setup) < 1e-6 && Math.abs(travelSum - r.cu.travel) < 1e-6
      && adjacent && busy && dt.trolleys.every(t => t.leftAt !== null),
      `${label.padEnd(24)} tasks ${nTasks} once, ${r.trolleys} trolleys, ${compSum} compartments, ${dt.pairs.length} pairs adjacent, setup/travel sum`);
    const cutOk = Math.abs(r.cu.cut - r.cutMinutes) < 1e-6;
    say(cutOk, `${label.padEnd(24)} cut minutes conserved (${f1(r.cu.cut)} = ${f1(r.cutMinutes)})`);
  }
  const a1 = JSON.stringify(E.run(raw, sel).spM), a2 = JSON.stringify(E.run(raw, sel).spM);
  say(a1 === a2, 'two runs with the same options are identical (deterministic)');
  const z = E.run(raw, Object.assign({}, sel, { setupMin: 0, travelMin: 0 }));
  say(z.cu.setup === 0 && z.cu.travel === 0, 'setup and travel are 0 when both are 0');
  const nr = E.run(raw, Object.assign({}, sel, { relax: false })), wr = E.run(raw, sel);
  say(wr.sp.starved >= nr.sp.starved, `relaxing adds spreader starved time (${f1(nr.sp.starved)} -> ${f1(wr.sp.starved)} min)`);
  console.log('\n5. OUTPUT — pieces, and the 100k-a-day plan');
  const req = cfg.required;
  const nTab = raw.dates.reduce((s, d) => s + raw.tasks[d].length, 0);
  const totPcs = raw.dates.reduce((s, d) => s + raw.tasks[d].reduce((a, t) => a + t.pt, 0), 0);
  const cutQty = Object.keys(days).reduce((s, d) => s + days[d].reduce((a, t) => a + t.pieces_total, 0), 0);
  say(totPcs === cutQty && totPcs > 0, `pieces over ${raw.dates.length} dates: ${totPcs} (${f1(totPcs / raw.dates.length)} a day)`);
  const rb = E.rebucket(raw);
  const rbTables = rb.dates.reduce((s, d) => s + rb.tasks[d].length, 0);
  const rbPcs = rb.dates.map(d => rb.tasks[d].reduce((a, t) => a + t.pt, 0));
  say(rbTables + rb.droppedTables === nTab, `re-bucket keeps every table once: ${rbTables} in ${rb.dates.length} dates + ${rb.droppedTables} unplaced tail tables = ${nTab}`);
  say(rbPcs.every(p => p >= req), `every re-bucketed date holds at least ${req} pieces (min ${Math.min(...rbPcs)}, max ${Math.max(...rbPcs)})`);
  say(rb.dates.every((d, i) => d === raw.dates[i] || i >= raw.dates.length), 're-bucketed dates reuse the real calendar in order');
  for (const [label, o] of [['published S0', Lab.optFromSweepKey('today|1|0|1')], ['published S3', Lab.optFromSweepKey('cross_batch|2|60|1')]]) {
    for (const [pl, r, tot] of [['real plan', E.run(raw, o), totPcs], ['100k plan', E.run100k(raw, o), rbPcs.reduce((a, b) => a + b, 0)]]) {
      const out = r.output;
      const sumDay = r.perDay.reduce((s, x) => s + x.cutPieces, 0);
      say(Math.abs(out.cutPerDay * r.days + out.backlogPieces - tot) < 1e-6 && Math.abs(sumDay - out.cutPerDay * r.days) < 1e-6,
        `${label} ${pl}: cut ${f1(out.cutPerDay)} a day x ${r.days} + backlog ${out.backlogPieces} = ${tot}`);
    }
  }
  console.log(ok ? '\n=> ALL CHECKS PASS' : '\n=> CHECKS FAILED');
  return ok;
}

// ---------------------------------------------------------------- tables
function clock(minFrom0715) {
  const abs = ((Math.round(minFrom0715 + A.SHIFT_START_MINUTE) % 1440) + 1440) % 1440;
  const days = Math.floor((minFrom0715 + A.SHIFT_START_MINUTE) / 1440);
  return String(Math.floor(abs / 60)).padStart(2, '0') + ':' + String(abs % 60).padStart(2, '0') + (days > 0 ? `+${days}d` : '');
}
function row(label, r) {
  const sp = r.sp, cu = r.cu;
  return `  ${label.padEnd(28)}│ ${f2(r.utilizationPct).padStart(6)} │ ${f1(r.trolleysPerDay).padStart(5)} │ ${String(Math.round(r.trolleysPerDay * A.CYCLE_DAYS_ESTIMATED)).padStart(5)} │ ${f2(r.tablesPerShiftHour).padStart(5)} │ ${clock(r.dayDoneMeanMin).padStart(8)} │ ${f1(r.onTimePct).padStart(5)} │ `
    + `${pct(sp.busy, sp.staffed).padStart(4)} ${pct(sp.blocked, sp.staffed).padStart(4)} ${pct(sp.starved, sp.staffed).padStart(4)} ${pct(sp.idle, sp.staffed).padStart(4)} │ `
    + `${pct(cu.cut, cu.staffed).padStart(4)} ${pct(cu.setup, cu.staffed).padStart(4)} ${pct(cu.travel, cu.staffed).padStart(4)} ${pct(cu.idle, cu.staffed).padStart(4)}`;
}
function header(title) {
  console.log(`\n${title}`);
  console.log(`  ${'step'.padEnd(28)}│ util%  │ tr/day│ fleet │ tb/sh │ day done │ ontm% │ spreader: busy blk strv idle │ cutter: cut setup trav idle`);
  console.log(`  ${'─'.repeat(28)}┼────────┼───────┼───────┼───────┼──────────┼───────┼${'─'.repeat(30)}┼${'─'.repeat(30)}`);
}
function ladderTable(title, raw, sel) {
  header(title);
  for (const st of Lab.ladder(sel, V)) console.log(row(st.name, E.run(raw, st.opt)));
}

// Output against the requirement: pieces cut a day and the shift hours that takes,
// on the real plan and on the re-bucketed 100k-a-day plan, per rule step.
function outputTable(raw, full, allOn, label) {
  const rb = E.rebucket(raw);
  console.log(`\n--- OUTPUT in pieces (every piece cut), requirement ${cfg.required} a day; G2 standard pace --- ${label || ''}`);
  console.log(`real plan: ${raw.dates.length} dates.  100k plan: the same tables dealt into ${rb.dates.length} dates of >= ${cfg.required} pieces (${rb.droppedTables} tail tables unplaced).`);
  console.log('cut/day = pieces finished inside the plan period / plan dates.  h/100k = staffed shift hours to cut 100k pieces.  days>=req = plan days that cut at least the requirement.');
  console.log('h/day columns = run hours / (shift-hours-to-last-cut / one shift window). cutter lost = setup + travel + waiting for a table, all 5 cutters summed (waiting = cu.idle, a residual clamped at 0: staffed - cut - setup - travel; lost = setup + travel + waiting). day window h = one shift window. spreader waiting = blocked for table space, all 13 spreaders summed.');
  for (const [title, runner] of [['real plan', (o) => E.run(raw, o)], ['100k plan', (o) => E.run100k(raw, o)]]) {
    console.log(`\n  ${title}`);
    console.log(`  ${'step'.padEnd(28)}│ planned/day │ cut/day │ vs S0  │ backlog │ days>=req │ h/100k │ pieces/h │ day done │ setup h/day │ cutter lost h/day │ cutter waiting h/day │ cutter travel h/day │ day window h │ spreader waiting-for-table h/day`);
    let s0 = 0;
    for (const st of Lab.ladder(Object.assign({}, full, allOn), V)) {
      const r = runner(st.opt), o = r.output;
      if (!s0) s0 = o.cutPerDay;
      const d = r.finishHours / r.dayWindowHours;
      console.log(`  ${st.name.padEnd(28)}│ ${String(Math.round(o.plannedPerDay)).padStart(11)} │ ${String(Math.round(o.cutPerDay)).padStart(7)} │ ${((100 * (o.cutPerDay - s0) / s0).toFixed(1) + '%').padStart(6)} │ ${String(o.backlogPieces).padStart(7)} │ ${(o.daysMeeting + '/' + r.days).padStart(9)} │ ${f1(o.hoursPer100k).padStart(6)} │ ${String(Math.round(o.piecesPerShiftHour)).padStart(8)} │ ${clock(r.dayDoneMeanMin).padStart(8)} │ ${f2(r.cu.setup / 60 / d).padStart(11)} │ ${f2((r.cu.setup + r.cu.travel + r.cu.idle) / 60 / d).padStart(17)} │ ${f2(r.cu.idle / 60 / d).padStart(20)} │ ${f2(r.cu.travel / 60 / d).padStart(19)} │ ${f1(r.dayWindowHours).padStart(12)} │ ${f2(r.sp.blocked / 60 / d).padStart(32)}`);
    }
  }
}

// Rule (a), both ways, on the same base floor: case 1 = pairs spread over the floor (the
// default), case 2 = a whole MO + colour kept on one cut group. Cutter output and the trolley
// findings are separate columns and are not traded against each other. S0 does not move.
function pairsRuleTable(raw, full) {
  const rb = E.rebucket(raw);
  console.log(`\n--- RULE (a) TWO WAYS, base floor, G2 standard pace, cutter setup ${full.setupMin} min, travel ${full.travelMin} min ---`);
  console.log('case 1 = pairs over the floor (default); case 2 = keep an MO on one cut group (the old S1-S3). Output = pieces the CUTTERS cut.');
  console.log('cutter cut% = cutting minutes / staffed cutter minutes up to the last cut. pairs = tables loaded back-to-back as a pair. S0 is identical in both cases.');
  for (const [title, runner] of [['real plan', o => E.run(raw, o)], ['100k plan', o => E.run100k(raw, o)]]) {
    console.log(`\n  ${title}`);
    console.log(`  ${'case / step'.padEnd(40)}│ cut/day │ vs S0  │ h/100k │ cutter cut% │ util%  │ tr/day │ fleet │ pairs │ combines`);
    for (const [label, flag] of [['case 1 pairs over the floor', false], ['case 2 MO on one cut group', true]]) {
      let s0 = 0;
      for (const st of Lab.ladder(Object.assign({}, full, { moOneGroup: flag }), V)) {
        const r = runner(st.opt), o = r.output;
        if (!s0) s0 = o.cutPerDay;
        console.log(`  ${(label.slice(0, 6) + ' ' + st.name).padEnd(40)}│ ${String(Math.round(o.cutPerDay)).padStart(7)} │ ${((100 * (o.cutPerDay - s0) / s0).toFixed(2) + '%').padStart(6)} │ ${f1(o.hoursPer100k).padStart(6)} │ ${pct(r.cu.cut, r.cu.staffed).padStart(11)} │ ${f2(r.utilizationPct).padStart(6)} │ ${f1(r.trolleysPerDay).padStart(6)} │ ${String(Math.round(r.trolleysPerDay * A.CYCLE_DAYS_ESTIMATED)).padStart(5)} │ ${String(r.detail.pairs.length).padStart(5)} │ ${String(r.combines).padStart(8)}`);
      }
    }
  }
}

function tables(days) {
  const raw = DT.labInput(days);
  const nT = raw.dates.reduce((s, d) => s + raw.tasks[d].length, 0);
  console.log(`\nRULES LAB  [${A.WEBSITE_MONTHS.join(', ')}]  ${raw.dates.length} plan dates, ${nT} tables, all dates pooled, unrounded inputs`);
  console.log(`ESTIMATES in the add-on rows: fabric arrival ${cfg.defaults.relaxMinH}-${cfg.defaults.relaxMaxH} h before the first plan date + ${cfg.relaxHours} h relaxing; `
    + `hold ${V.holdMin} min; pull-ahead ${V.pullAhead} day(s). Cutter setup ${V.setupMin} min (MO/colour change) and travel ${V.travelMin} min per move are part of the published floor (ESTIMATES)`);
  console.log('fleet = trolleys/day x 7-day round trip (ESTIMATE). tb/sh = tables per shift-hour up to the last cut. day done = mean clock time a plan date is fully cut.');
  console.log('ontm% = cut inside its own plan date window. time shares are of STAFFED minutes up to the last cut.');

  const full = { shift: 'both', dispatch: 'static', recall: 'model', relax: cfg.defaults.relax,
    setupMin: cfg.defaults.setupMin, travelMin: cfg.defaults.travelMin, pullAhead: 0, holdMin: 0, relaxMinH: cfg.defaults.relaxMinH, relaxMaxH: cfg.defaults.relaxMaxH, colorGroup: false };
  const allOn = { recall: 'sameFirst', relax: true, setupMin: V.setupMin, travelMin: V.travelMin, pullAhead: V.pullAhead };
  const rlx = full.relax ? 'with fabric relaxing' : 'no fabric relaxing';
  ladderTable(`--- PUBLISHED MODEL: carry-over floor, G2 standard pace --- the Utilization tab`, raw, full);
  pairsRuleTable(raw, full);
  ladderTable('--- carry-over floor + every add-on', raw, Object.assign({}, full, allOn));
  for (const shift of A.LAB_SHIFT_OPTIONS) {
    ladderTable(`--- carry-over floor, shift: ${shift} --- all add-ons`, raw, Object.assign({}, full, allOn, { shift }));
  }
  ladderTable('--- carry-over floor, pull-ahead = all (capacity test)', raw, Object.assign({}, full, allOn, { pullAhead: 99 }));

  outputTable(raw, full, allOn, 'published logic steps then every new rule (all add-ons on the floor: setup, travel, relaxing)');
  // Like for like: cutter setup and travel are floor facts, so S0 carries them too.
  outputTable(raw, full, {},
    `SAME FLOOR IN EVERY ROW: the PUBLISHED floor (live: re-plan every ${cfg.replanMin} min, marker and fabric ready, cutter takes the longest wait), cutter setup ${full.setupMin} min, travel ${full.travelMin} min (ESTIMATES), ${rlx}`);
  outputTable(raw, Object.assign({}, full, { relax: !full.relax }), {},
    `SAME FLOOR IN EVERY ROW: the published floor with fabric relaxing switched ${full.relax ? 'OFF' : 'ON'} (ESTIMATES)`);
  outputTable(raw, Object.assign({}, full, { setupMin: 0, travelMin: 0 }), {},
    `BELOW the published floor: no cutter setup, no travel, ${rlx}`);
  outputTable(raw, Object.assign({}, full, { setupMin: SENS_SETUP, travelMin: SENS_TRAVEL }), {},
    `SAME FLOOR IN EVERY ROW: cutter setup ${SENS_SETUP} min, travel ${SENS_TRAVEL} min (ESTIMATES), ${rlx}`);

  header('--- ESTIMATE sensitivity, carry-over floor, all add-ons on');
  const sel = Object.assign({}, full, { recall: 'sameFirst', relax: true, setupMin: V.setupMin,
    travelMin: V.travelMin, pullAhead: V.pullAhead, ruleA: true, mix: true, seqMode: 'cross_batch', holdMin: V.holdMin });
  for (const [label, o] of [
    ['as selected', {}], ['relaxing off', { relax: false }], ['setup 0 / travel 0', { setupMin: 0, travelMin: 0 }],
    [`setup ${SENS_SETUP} / travel ${SENS_TRAVEL}`, { setupMin: SENS_SETUP, travelMin: SENS_TRAVEL }], ['relax window 24-72 h', { relaxMinH: 24, relaxMaxH: 72 }],
    ['relax window 0-24 h', { relaxMinH: 0, relaxMaxH: 24 }],
    ['recall: same only', { recall: 'sameOnly' }], ['recall: published order', { recall: 'model' }],
    ['floor of 2026-11-09 (plan once, no readiness)', { live: false, relax: false }],
  ]) console.log(row(label, E.run(raw, Object.assign({}, sel, o))));
  const r = E.run(raw, sel);
  console.log(`\nas selected: recalls same-batch ${r.recallsSame}, different-batch ${r.recallsCross}; combines ${r.combines}; avg wait ${f2(r.avgWaitH)} h`);
}

function main() {
  const [all] = M.loadDays(path.join(REPO, A.DATA_FILE), true);
  const days = scopeDays(all, A.WEBSITE_MONTHS);
  const ok = checks(days);
  if (!process.argv.includes('--checks')) tables(days);
  process.exit(ok ? 0 : 1);
}

main();
