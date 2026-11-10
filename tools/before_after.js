'use strict';
/* BEFORE / AFTER — the four stages of the 2026-11-09 change, one rule at a time.
 * ================================================================
 * A MEASUREMENT script (never feeds the build). All four stages are computed here,
 * April-June 2026 (A.WEBSITE_MONTHS), carry-over floor. There is no cold start.
 *
 *   (0) the model as published on 2026-11-06: S1-S3 send a whole MO + colour to ONE
 *       cut group (the option "mo_one_group"), no cutter changeover or moving, and
 *       machines at OLD_SPEED 0.80 of the G2 pace;
 *   (i) + rule (a) as the user meant it: pairs first, counted by pairs, each pair
 *       assigned over the whole floor (sequencePairs), back-to-back;
 *   (ii) + cutter changeover (A.CUT_SETUP_MO_COLOR_MINUTES) and moving
 *       (A.CUT_TRAVEL_MINUTES), both ESTIMATES, cutters only (SIM_SPEC Q19);
 *   (iii) + the speed factor removed (user, 2026-11-09): the G2 standard pace.
 *       The published model of 2026-11-09. Its headline is frozen below (PUBLISHED_1109).
 *   (iv) + S0 is the real Job Sequence (user, 2026-11-10; data/SQL Job Sequence Logic.sql,
 *       sequenceJobSeq). Stages (0)-(iii) run S0 as the old 'today_grouped' mode (a whole
 *       MO + colour + batch cluster on one cut group), which is kept only for this script.
 *       Only S0 and the 39 'today' sweep keys may move from (iii) to (iv); S1-S3, the hold
 *       variants and the other 78 keys must not move by one bit (asserted).
 *       This is the published model now and must equal out/results.json.
 *
 * OLD_SPEED is the 2026-11-06 calibration, an ESTIMATE, NO LONGER IN THE MODEL. It
 * is reproduced here by a measurement-only scaling: a copy of the loaded days whose
 * tasks have spread_minutes and cut_minutes divided by 0.80, the same float
 * operation the removed code did per task. The assert at stage (0) proves the
 * scaling reproduces the 2026-11-06 headline.
 *
 * Trolley findings (model.runCarry, tables loaded per plan date) and cutter-output
 * findings (Rules Lab engine, pieces the cutters cut) are separate blocks. They are
 * independent findings and are never traded against each other.
 *
 * The earlier comparison, cold start -> carry-over (2026-11-06), is RETIRED: the
 * cold-start model was removed on 2026-11-09. Its table is kept as history in
 * SIM_SPEC.md §18 and cannot be reproduced.
 *
 *   node --max-old-space-size=6144 tools/before_after.js     (npm run beforeafter)
 *
 * Exits non-zero if an assert fails.
 */
const fs = require('fs');
const path = require('path');
const A = require('./assumptions');
const M = require('./model');
const S = require('./scenarios');
const DT = require('./daytrace');
const Lab = require('./lab');

const REPO = path.join(__dirname, '..');
const OLD_SPEED = 0.80;   // the 2026-11-06 calibration, an ESTIMATE, no longer in the model; measurement-only scaling

const [all] = M.loadDays(path.join(REPO, A.DATA_FILE), true);
const days = {};
for (const d of Object.keys(all)) if (A.WEBSITE_MONTHS.includes(d.slice(0, 7))) days[d] = all[d];
const scaledDays = {};
for (const d of Object.keys(days)) {
  scaledDays[d] = days[d].map(t => Object.assign({}, t, { spread_minutes: t.spread_minutes / OLD_SPEED, cut_minutes: t.cut_minutes / OLD_SPEED }));
}

const cfg = Lab.makeConfig(A);              // made before A is touched: V holds the published 5 / 1.5
const E = Lab.createEngine(cfg);
const V = cfg.addOnValues;
const SETUP = A.CUT_SETUP_MO_COLOR_MINUTES, TRAVEL = A.CUT_TRAVEL_MINUTES;

const STAGES = [
  { id: '(0)', name: 'published 2026-11-06', moOne: true, setup: 0, travel: 0, scaled: true, s0: 'today_grouped', live: false },
  { id: '(i)', name: '+ pairs rule', moOne: false, setup: 0, travel: 0, scaled: true, s0: 'today_grouped', live: false },
  { id: '(ii)', name: '+ changeover/moving', moOne: false, setup: SETUP, travel: TRAVEL, scaled: true, s0: 'today_grouped', live: false },
  { id: '(iii)', name: '+ no speed factor', moOne: false, setup: SETUP, travel: TRAVEL, scaled: false, s0: 'today_grouped', live: false },
  { id: '(iv)', name: '+ S0 = real Job Seq', moOne: false, setup: SETUP, travel: TRAVEL, scaled: false, s0: 'today', live: false },
  { id: '(v)', name: '+ live floor', moOne: false, setup: SETUP, travel: TRAVEL, scaled: false, s0: 'today', live: true },
];
const LIVE0 = A.LIVE_FLOOR;

// A scenario as a stage runs it: S0 ('today') takes the stage's S0 mode; the flag keeps an MO on one cut group.
const scFor = (sc, st) => {
  let o = sc;
  if (sc.sequencing_mode === 'today') o = Object.assign({}, o, { sequencing_mode: st.s0 });
  if (st.moOne) o = Object.assign({}, o, { mo_one_group: true });
  return o === sc ? sc : M.makeScenario(o);
};
const fleet7 = r => r.trolleys_per_day * A.CYCLE_DAYS_ESTIMATED;

// One stage, everything computed with A's cutter constants set for the stage.
function runStage(st) {
  A.CUT_SETUP_MO_COLOR_MINUTES = st.setup; A.CUT_TRAVEL_MINUTES = st.travel; A.LIVE_FLOOR = !!st.live;
  try {
    const D = st.scaled ? scaledDays : days;
    const out = { st, head: [], hold: [], sweep: new Map(), full: {} };
    for (const sc of S.HEADLINE) out.head.push(M.runCarry(scFor(sc, st), D));
    for (const sc of S.HOLD_VARIANTS) out.hold.push(M.runCarry(scFor(sc, st), D));
    for (const [key, sc] of S.sweepScenarios()) {
      const r = M.runCarry(scFor(sc, st), D);
      out.sweep.set(key, JSON.stringify([r.utilization_pct, r.trolleys_per_day, r.peak_trolleys_in_a_day]));
    }
    // cutter output, Rules Lab engine on the same (scaled) tasks, the same floor
    const raw = DT.labInput(D);
    const sel = { shift: 'both', dispatch: 'static', recall: 'model', relax: !!st.live, setupMin: st.setup, travelMin: st.travel,
      pullAhead: 0, holdMin: 0, relaxMinH: cfg.defaults.relaxMinH, relaxMaxH: cfg.defaults.relaxMaxH, colorGroup: false, moOneGroup: st.moOne };
    out.lab = Lab.ladder(sel, V).map(step0 => {
      const step = { name: step0.name, opt: Object.assign({}, step0.opt, { live: !!st.live }, step0.opt.seqMode === 'today' ? { seqMode: st.s0 } : {}) };
      return { name: step.name, real: E.run(raw, step.opt), k100: E.run100k(raw, step.opt) };
    });
    out.rb = E.rebucket(raw);
    out.raw = raw;
    out.full = JSON.stringify(out.head[0]);    // S0, every field, for the bit-identical assert
    return out;
  } finally { A.CUT_SETUP_MO_COLOR_MINUTES = SETUP; A.CUT_TRAVEL_MINUTES = TRAVEL; A.LIVE_FLOOR = LIVE0; }
}

const R = STAGES.map(runStage);

// case 2 at stages (ii) and (iii): the same floor, an MO kept on one cut group
const case2Ii = runStage(Object.assign({}, STAGES[2], { moOne: true }));
const case2 = runStage(Object.assign({}, STAGES[3], { moOne: true }));
const case2Iv = runStage(Object.assign({}, STAGES[4], { moOne: true }));
const case2V = runStage(Object.assign({}, STAGES[5], { moOne: true }));

// ---------------------------------------------------------------- printing
const f = (v, d) => (d === 0 ? Math.round(v).toLocaleString('en-US') : v.toFixed(d));
const SC = ['S0', 'S1', 'S2', 'S3'];
const HOLD_NAMES = S.HOLD_VARIANTS.map(s => s.name);
const nPlan = Object.keys(days).length, nTab = R[0].raw.dates.reduce((s, d) => s + R[0].raw.tasks[d].length, 0);

console.log(`\nBEFORE / AFTER  [${A.WEBSITE_MONTHS.join(', ')}]  ${nPlan} plan dates, ${nTab} tables, carry-over floor, no relaxing`);
console.log('The cold start -> carry-over comparison (2026-11-06) is RETIRED: the cold-start model was removed on 2026-11-09. It is kept as history in SIM_SPEC.md §18.');
console.log(`ESTIMATES: cutter changeover ${SETUP} min and moving ${TRAVEL} min (stages ii, iii); OLD_SPEED ${OLD_SPEED.toFixed(2)} (stages 0, i, ii) is the 2026-11-06 calibration, no longer in the model, measurement-only scaling; fleet = trolleys/day x ${A.CYCLE_DAYS_ESTIMATED}-day round trip (ESTIMATE, never timed).`);
console.log('');
for (const st of STAGES) console.log(`  ${st.id.padEnd(6)} ${st.name.padEnd(24)} ${st.live ? 'LIVE floor (re-plan 30 min, marker + fabric, cutter takes the longest wait)' : 'plan once at 07:15, every table ready, cutter in spread order'} | S0 ${st.s0 === 'today' ? 'real Job Sequence (SQL)   ' : 'MO+colour+batch -> 1 group'} | S1-S3 ${st.moOne ? 'keep an MO on one cut group' : 'pairs over the floor   '} | changeover ${String(st.setup).padStart(1)} / moving ${String(st.travel).padEnd(3)} | pace ${st.scaled ? 'G2 / ' + OLD_SPEED.toFixed(2) + ' (old speed)' : 'G2 standard   '}`);

function stageTable(title, rows, get, d) {
  console.log(`\n${title}`);
  console.log(`  ${'scenario'.padEnd(36)}` + STAGES.map(s => '│ ' + s.id.padStart(9) + ' ').join(''));
  console.log(`  ${'─'.repeat(36)}` + STAGES.map(() => '┼' + '─'.repeat(11)).join(''));
  for (const [label, idx, grp] of rows) console.log(`  ${label.padEnd(36)}` + R.map(r => '│ ' + f(get(r[grp][idx]), d).padStart(9) + ' ').join(''));
}
const trolleyRows = [...SC.map((n, i) => [S.HEADLINE[i].name, i, 'head']), ...HOLD_NAMES.map((n, i) => ['hold: ' + n, i, 'hold'])];

console.log('\n==================== TROLLEY FINDINGS (model.runCarry, tables loaded per plan date) ====================');
stageTable('trolley utilization %', trolleyRows, r => r.utilization_pct, 2);
stageTable('trolleys / day', trolleyRows, r => r.trolleys_per_day, 1);
stageTable(`fleet needed @ ${A.CYCLE_DAYS_ESTIMATED}-day trip (ESTIMATE; ${A.FLEET_SIZE} owned)`, trolleyRows, fleet7, 0);
stageTable('fleet gap vs owned (negative = short)', trolleyRows, r => A.FLEET_SIZE - fleet7(r), 0);
stageTable('peak trolleys in a day', trolleyRows, r => r.peak_trolleys_in_a_day, 0);

console.log('\nsweep keys that moved against the stage before (utilization, trolleys/day or peak), of 117, and of the 39 "today" keys:');
console.log(`  ${'stage'.padEnd(8)}│ moved of 117 │ of 39 today │ hold variants moved of 5`);
for (let i = 1; i < R.length; i++) {
  let mv = 0, mvToday = 0;
  for (const [key, s] of R[i].sweep) if (s !== R[i - 1].sweep.get(key)) { mv += 1; if (key.startsWith('today|')) mvToday += 1; }
  const mh = R[i].hold.filter((r, k) => r.utilization_pct !== R[i - 1].hold[k].utilization_pct || r.trolleys_per_day !== R[i - 1].hold[k].trolleys_per_day || r.peak_trolleys_in_a_day !== R[i - 1].hold[k].peak_trolleys_in_a_day).length;
  console.log(`  ${STAGES[i].id.padEnd(8)}│ ${String(mv).padStart(12)} │ ${String(mvToday).padStart(11)} │ ${String(mh).padStart(8)}`);
}

console.log('\n==================== CUTTER OUTPUT FINDINGS (Rules Lab engine, pieces the cutters cut) ====================');
console.log('cut/day = pieces finished inside the plan period / plan dates. h/100k = staffed shift hours to cut 100k pieces. Same floor in every row: only the rules differ.');
const labRows = SC.map((n, i) => [S.HEADLINE[i].name, i]);
function outTable(title, pick, get, d) {
  console.log(`\n${title}`);
  console.log(`  ${'scenario'.padEnd(36)}` + STAGES.map(s => '│ ' + s.id.padStart(9) + ' ').join(''));
  console.log(`  ${'─'.repeat(36)}` + STAGES.map(() => '┼' + '─'.repeat(11)).join(''));
  for (const [label, i] of labRows) console.log(`  ${label.padEnd(36)}` + R.map(r => '│ ' + f(get(r.lab[i][pick]), d).padStart(9) + ' ').join(''));
}
console.log(`\nreal plan: ${nPlan} plan dates, ${f(R[0].lab[0].real.output.plannedPerDay, 0)} pieces planned a day.   100k plan: the same tables dealt into ${R[0].rb.dates.length} dates of >= ${cfg.required} pieces (${R[0].rb.droppedTables} tail tables unplaced).`);
outTable('real plan: pieces cut / day', 'real', r => r.output.cutPerDay, 0);
outTable('real plan: hours per 100k pieces', 'real', r => r.output.hoursPer100k, 1);
outTable('real plan: pieces left uncut at the end', 'real', r => r.output.backlogPieces, 0);
outTable('real plan: pairs loaded back-to-back', 'real', r => r.detail.pairs.length, 0);
outTable('100k plan: pieces cut / day', 'k100', r => r.output.cutPerDay, 0);
outTable('100k plan: hours per 100k pieces', 'k100', r => r.output.hoursPer100k, 1);
outTable('100k plan: pieces left uncut at the end', 'k100', r => r.output.backlogPieces, 0);
outTable(`100k plan: days cutting at least ${cfg.required} (of ${R[0].rb.dates.length})`, 'k100', r => r.output.daysMeeting, 0);

console.log('\n==================== CUTTER LOST TIME, hours a day summed over the 5 cutters (real plan; lost = setup + moving + waiting for a table) ====================');
console.log(`  ${'scenario'.padEnd(36)}` + STAGES.map(s => '│ ' + (s.id + ' set/mov/wait').padStart(18) + ' ').join(''));
for (const [label, i] of labRows) {
  console.log(`  ${label.padEnd(36)}` + R.map(r => {
    const x = r.lab[i].real, d = x.finishHours / x.dayWindowHours;
    return '│ ' + [x.cu.setup, x.cu.travel, x.cu.idle].map(v => (v / 60 / d).toFixed(1).padStart(5)).join(' ') + '  ';
  }).join(''));
}

console.log('\n==================== CASE 1 vs CASE 2: changeover/moving on; stage (ii) at the old speed 0.80, stages (iii) and (iv) at the G2 pace ====================');
console.log('case 1 = pairs over the floor (published); case 2 = keep an MO on one cut group (the 2026-11-06 rule). S0 is identical in both. Output and trolley columns are separate findings. S0 -> S1 is "new dispatcher + pairing" (two changes) at stage (iv).');
console.log(`  ${'case / scenario'.padEnd(34)}│ util %  │ tr/day │ fleet │ real cut/day │ vs S0   │ 100k cut/day │ vs S0   │ real h/100k │ 100k h/100k │ cutter cut%`);
console.log(`  ${'─'.repeat(34)}┼─────────┼────────┼───────┼──────────────┼─────────┼──────────────┼─────────┼─────────────┼─────────────┼────────────`);
const cutPct = r => (100 * r.cu.cut / r.cu.staffed).toFixed(1);
for (const [label, run] of [['(ii) case 1', R[2]], ['(ii) case 2', case2Ii], ['(iii) case 1', R[3]], ['(iii) case 2', case2], ['(iv) case 1', R[4]], ['(iv) case 2', case2Iv], ['(v) case 1', R[5]], ['(v) case 2', case2V]]) {
  const s0r = run.lab[0].real.output.cutPerDay, s0k = run.lab[0].k100.output.cutPerDay;
  SC.forEach((n, i) => {
    const m = run.head[i], lr = run.lab[i].real, lk = run.lab[i].k100;
    console.log(`  ${(label + ' ' + n).padEnd(34)}│ ${m.utilization_pct.toFixed(2).padStart(7)} │ ${m.trolleys_per_day.toFixed(1).padStart(6)} │ ${f(fleet7(m), 0).padStart(5)} │ ${f(lr.output.cutPerDay, 0).padStart(12)} │ ${((100 * (lr.output.cutPerDay - s0r) / s0r).toFixed(2) + '%').padStart(7)} │ ${f(lk.output.cutPerDay, 0).padStart(12)} │ ${((100 * (lk.output.cutPerDay - s0k) / s0k).toFixed(2) + '%').padStart(7)} │ ${lr.output.hoursPer100k.toFixed(1).padStart(11)} │ ${lk.output.hoursPer100k.toFixed(1).padStart(11)} │ ${cutPct(lr).padStart(8)}`);
  });
}

// ---------------------------------------------------------------- asserts
console.log('\n==================== ASSERTS ====================');
let ok = true;
const say = (pass, msg) => { ok = ok && pass; console.log(`  ${pass ? 'PASS' : 'FAIL'}  ${msg}`); };
const hl = r => `${r.utilization_pct.toFixed(2)} / ${r.trolleys_per_day.toFixed(1)} / ${Math.round(fleet7(r))}`;
// the 2026-11-06 headline (April-June): proves the 0.80 scaling reproduces the removed speed factor
const PUBLISHED_1106 = ['52.49 / 201.1 / 1408', '58.75 / 173.6 / 1216', '64.65 / 157.8 / 1105', '69.77 / 146.2 / 1024'];
SC.forEach((n, i) => say(hl(R[0].head[i]) === PUBLISHED_1106[i], `stage (0) ${n} equals the 2026-11-06 headline ${PUBLISHED_1106[i]} (util / trolleys a day / fleet): got ${hl(R[0].head[i])}`));
say(R[0].full === R[1].full, 'S0 is bit-identical from stage (0) to stage (i) (every field)');
let todayMoved = 0;
for (const [key, s] of R[1].sweep) if (key.startsWith('today|') && s !== R[0].sweep.get(key)) todayMoved += 1;
say(todayMoved === 0, `the 39 'today' sweep keys are identical from stage (0) to stage (i) (${todayMoved} differ)`);
// stage (iii) is the published model of 2026-11-09: frozen headline (util / trolleys a day / fleet)
const PUBLISHED_1109 = ['53.49 / 195.9 / 1371', '58.75 / 173.6 / 1216', '64.67 / 157.8 / 1104', '68.77 / 148.4 / 1039'];
SC.forEach((n, i) => say(hl(R[3].head[i]) === PUBLISHED_1109[i], `stage (iii) ${n} equals the 2026-11-09 headline ${PUBLISHED_1109[i]}: got ${hl(R[3].head[i])}`));
// stage (iv) is the published model of 2026-11-10 (S0 = the real Job Sequence), on the floor of 2026-11-09: frozen headline
const PUBLISHED_1110 = ['51.92 / 203.5 / 1424', '58.75 / 173.6 / 1216', '64.67 / 157.8 / 1104', '68.77 / 148.4 / 1039'];
SC.forEach((n, i) => say(hl(R[4].head[i]) === PUBLISHED_1110[i], `stage (iv) ${n} equals the 2026-11-10 headline ${PUBLISHED_1110[i]}: got ${hl(R[4].head[i])}`));
// stage (iii) -> (iv): only S0 and the 39 'today' keys may move
const sameJson = (a, b) => JSON.stringify(a) === JSON.stringify(b);
say([1, 2, 3].every(i => sameJson(R[3].head[i], R[4].head[i])), 'S1, S2, S3 (every field) are bit-identical from stage (iii) to stage (iv)');
say(R[3].hold.every((r, k) => sameJson(r, R[4].hold[k])), `the ${R[3].hold.length} hold variants (every field) are bit-identical from stage (iii) to stage (iv)`);
let nonTodayMoved = 0, nonToday = 0, todayNow = 0;
for (const [key, s] of R[4].sweep) {
  if (key.startsWith('today|')) { if (s !== R[3].sweep.get(key)) todayNow += 1; continue; }
  nonToday += 1;
  if (s !== R[3].sweep.get(key)) nonTodayMoved += 1;
}
say(nonTodayMoved === 0, `the ${nonToday} non-'today' sweep keys are identical from stage (iii) to stage (iv) (${nonTodayMoved} differ); ${todayNow} of the 39 'today' keys moved`);
// stage (iv) equals the published build at full precision
const pub = JSON.parse(fs.readFileSync(path.join(REPO, 'out', 'results.json'), 'utf8'));
let nCmp = 0, nBad = 0, first = '';
const cmpAll = (grp, name, r) => {
  for (const k of Object.keys(pub[grp][name])) {
    // build.js adds the fleet fields on top of runCarry(); compare what runCarry() returns
    if (r[k] === undefined || (typeof pub[grp][name][k] !== 'number' && typeof pub[grp][name][k] !== 'boolean')) continue;
    nCmp += 1;
    if (r[k] !== pub[grp][name][k]) { nBad += 1; if (!first) first = `${name} ${k}: here ${r[k]} out/results.json ${pub[grp][name][k]}`; }
  }
};
R[5].head.forEach((r, i) => cmpAll('headline', S.HEADLINE[i].name, r));
R[5].hold.forEach((r, i) => cmpAll('hold_variants', S.HOLD_VARIANTS[i].name, r));
say(nBad === 0, `stage (v) equals out/results.json (headline + hold variants) at full precision: ${nCmp} fields, ${nBad} differ${first ? ' (first: ' + first + ')' : ''}`);
let sBad = 0;
for (const [key, s] of R[5].sweep) {
  const [u, t, p] = JSON.parse(s);
  const row = pub.sweep[key];
  const bk = require('./round').bankersRound;
  if (bk(u, 2) !== row.utilization_pct || bk(t, 1) !== row.trolleys_per_day || p !== row.peak) sBad += 1;
}
say(sBad === 0, `stage (v) equals out/results.json sweep on all ${R[5].sweep.size} keys (utilization, trolleys/day, peak, as rounded in the build): ${sBad} differ`);
// the Lab engine and the model agree on every stage (the Lab check in lab_table.js, here on the staged floors)
let lBad = 0;
R.concat([case2Ii, case2, case2Iv, case2V]).forEach(r => r.head.forEach((m, i) => { if (r.lab[i].real.utilizationPct !== m.utilization_pct || r.lab[i].real.trolleysPerDay !== m.trolleys_per_day) lBad += 1; }));
say(lBad === 0, `Lab engine utilization and trolleys/day equal model.runCarry() for S0-S3 at every stage and for case 2 at stages (ii), (iii) and (iv) (${lBad} differ)`);
// A restored
say(A.CUT_SETUP_MO_COLOR_MINUTES === SETUP && A.CUT_TRAVEL_MINUTES === TRAVEL, 'assumptions restored after the staged runs');
console.log(ok ? '\n=> ALL ASSERTS PASS' : '\n=> ASSERTS FAILED');
process.exit(ok ? 0 : 1);
