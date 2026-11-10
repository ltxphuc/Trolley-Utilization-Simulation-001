'use strict';
/*
THE 18-DATE REGRESSION GATE

    node --max-old-space-size=6144 tools/regress.js       (npm run regress)

The data file moved from the 20-date export (A.PIN_DATA_FILE, now only the
fixture this gate reads) to the 199-date workbook (A.DATA_FILE). The new file
is a strict superset of the old one on the same sheet. Every plan date that
appears in BOTH files with the same table count (18 of them) must produce
byte-identical results from either workbook. This script is the gate that
says so.

WHAT THIS IS NOT. It is not a check against Python, and the numbers R1 and R3
compute are READER CHECKS, NOT published per-date numbers: the carry-over model
(runCarry) is run on a subset that holds ONLY the 18 unchanged dates, in each
file, so it is a different run from the published April-June one. The gate
compares two runs of the SAME port on two DIFFERENT files. It catches a
data-loading change, not a porting error. (The old pin against out/*.bak was
retired on 2026-11-09 with the cold-start model; the .bak files are no longer
read by any gate.)

    R0  inputs  — same C-table keys and the same task records, as a multiset,
                  on the shared dates. Multiset and not position: the 199-date
                  workbook does not preserve the old export's row order.
    R1  per-day — runCarry(sc, subset).per_day identical across all 117 sweep
                  scenarios, at full float precision, on all 16 result keys,
                  where the subset holds exactly the 18 unchanged dates on
                  both files, the new file put in the old file's row order
                  (the reader sums blocked minutes in row order, so the last
                  float digit of three sums moves with it; the as-loaded
                  order is printed as an informational line)
    R2  informational — is_batch_last flips. `_stamp_batch_readiness` takes a
                  batch's last table by Pull Date ACROSS THE WHOLE FILE, so it
                  is not row-local and it is EXPECTED to move on dates whose
                  own data did not change. It reaches bar colour only.
    R3  pooled  — the pooled runCarry over the same subset, so it catches an
                  aggregation-order bug R1 cannot see.

Non-zero exit if R0, R1 or R3 fails. R2 never fails; it reports.
*/
const path = require('path');
const A = require('./assumptions');
const M = require('./model');
const S = require('./scenarios');

const REPO = path.join(__dirname, '..');

// Gate expectations, not model tunables — they describe the two fixture files
// this script compares, so they live here rather than in assumptions.py.
// The old export stops mid-day on its last two dates, so those two carry fewer
// tables in it than in the new workbook and are correctly NOT in the unchanged
// set. Derived at run time below; these are only what the derivation must find.
const EXPECTED_UNCHANGED_DATES = 18;
const EXPECTED_TRUNCATED = ['2026-05-25', '2026-05-26'];

// The task fields load_days() writes that the model can read. Everything the
// sequencer, the timeline and the loading stage touch is in here.
const TASK_FIELDS = [
  'table_no', 'mo', 'style', 'color', 'lot', 'batch', 'layers', 'marker_length',
  'needs_trolleys', 'pieces_by_size', 'spread_minutes', 'cut_minutes',
  'has_pattern', 'has_fabric', 'spread_done_at', 'order_type', 'marker_rel',
];

const DAY_KEYS = [
  'tasks', 'combines', 'compartments', 'trolleys', 'pieces',
  'trolley_utilization_pct', 'compartment_fill_pct', 'pieces_per_trolley',
  'spreading_blocked_pct', 'cutting_blocked_pct', 'spreading_makespan_hours',
  'spreading_blocked_minutes', 'spreading_overrun_minutes',
  'machines_over_window', 'avg_wait_hours', 'blocked_by_space',
];

const POOLED_KEYS = [
  'utilization_pct', 'trolleys_per_day', 'compartments_per_day',
  'pieces_per_trolley', 'compartment_fill_pct', 'garments_per_trolley_capacity',
];

// ------------------------------------------------------------------ helpers
function cTableKeys(file) {
  // The same set model.js builds inside loadDays(), rebuilt here so R0 can
  // compare the INPUT to the setup-minutes rule rather than only its effect.
  const XLSX = require('xlsx');
  const wb = XLSX.readFile(path.join(REPO, file), { cellDates: false });
  const rows = XLSX.utils.sheet_to_json(wb.Sheets[A.DATA_SHEET],
    { header: 1, raw: true, defval: null });
  const col = {};
  rows[0].forEach((name, i) => { col[name] = i; });
  const out = new Set();
  for (const r of rows.slice(1)) {
    if (!r[0]) continue;
    if (r[col['Type']] === 'C' && typeof r[col['Plan Date']] === 'number') {
      out.add(`${M.ymd(M.asDatetime(r[col['Plan Date']]))}|${r[col['Table No']]}`);
    }
  }
  return out;
}

function fieldSig(v) {
  if (v instanceof Date) return String(v.getTime());
  if (v && typeof v === 'object') {
    // Insertion order is part of the record, not an accident of it:
    // compartments_for walks pieces_by_size in it and that order decides
    // which film width opens a trolley first once the 52 bays fill.
    return Object.keys(v).map(k => `${k}:${fieldSig(v[k])}`).join('/');
  }
  return String(v);
}

function taskSig(t) {
  return TASK_FIELDS.map(f => fieldSig(t[f])).join('|');
}

// The days of one file restricted to the shared dates: the subset runCarry is
// run on in R1 and R3, built once per file.
function subsetOf(days, dates) {
  const out = {};
  for (const d of dates) out[d] = days[d];
  return out;
}

// The new file's tasks on the shared dates, put in the OLD file's row order
// (matched by task signature; R0 proves the two are the same multiset). The
// carry-over reader sums blocked minutes over a date's tasks in row order, and
// floating-point addition is order-dependent, so R1/R3 compare the two files in
// ONE row order and exactly. The as-loaded order is reported by R1 as well, not
// hidden. If a signature has no match (R0 will already have failed), the date
// is left in the new file's own order and R1 reports what differs.
function subsetInOrderOf(days, orderDays, dates) {
  const out = {};
  for (const d of dates) {
    const pool = new Map();
    for (const t of days[d]) {
      const s = taskSig(t);
      if (!pool.has(s)) pool.set(s, []);
      pool.get(s).push(t);
    }
    const ordered = orderDays[d].map(o => (pool.get(taskSig(o)) || []).shift());
    out[d] = ordered.every(t => t !== undefined) ? ordered : days[d];
  }
  return out;
}

// ------------------------------------------------------------------- gates
function deriveUnchangedDates(oldDays, newDays) {
  const shared = Object.keys(oldDays).filter(d =>
    Object.prototype.hasOwnProperty.call(newDays, d)).sort();
  const unchanged = shared.filter(d => oldDays[d].length === newDays[d].length);
  const differing = shared.filter(d => oldDays[d].length !== newDays[d].length);

  console.log(`Old file: ${Object.keys(oldDays).length} plan dates. ` +
              `New file: ${Object.keys(newDays).length}.`);
  console.log(`Shared dates: ${shared.length}. Same table count on ${unchanged.length}.`);
  for (const d of differing) {
    console.log(`  dropped — ${d}: ${oldDays[d].length} tables old, ${newDays[d].length} new`);
  }
  console.log(`UNCHANGED_DATES (${unchanged.length}): ${unchanged.join(', ')}`);

  let ok = true;
  if (unchanged.length !== EXPECTED_UNCHANGED_DATES) {
    console.log(`  ASSERTION FAILED: expected ${EXPECTED_UNCHANGED_DATES} unchanged dates.`);
    ok = false;
  }
  for (const d of EXPECTED_TRUNCATED) {
    if (unchanged.includes(d)) {
      console.log(`  ASSERTION FAILED: ${d} was truncated in the old export and must not be here.`);
      ok = false;
    }
  }
  return { unchanged, ok };
}

function gateR0(dates, oldDays, newDays) {
  console.log('\nR0 — inputs');
  let failures = 0;

  // --- R0a: the C-table key set, and the part of it that can actually bite.
  // Only a key that matches a modelled Type B table on the same date adds
  // setup minutes, so that intersection is the hard half; the raw set is
  // reported alongside it rather than swallowed.
  const oldC = cTableKeys(A.PIN_DATA_FILE);
  const newC = cTableKeys(A.DATA_FILE);
  const onDates = (set) => new Set(Array.from(set).filter(k => dates.includes(k.slice(0, 10))));
  const effective = (set, days) => new Set(Array.from(set).filter(k => {
    const date = k.slice(0, 10), tableNo = k.slice(11);
    return days[date].some(t => String(t.table_no) === tableNo);
  }));
  const o = onDates(oldC), n = onDates(newC);
  const oe = effective(o, oldDays), ne = effective(n, newDays);
  const diff = (a, b) => Array.from(a).filter(k => !b.has(k));
  console.log(`  c_tables on the ${dates.length} dates: ${o.size} old, ${n.size} new; ` +
              `matching a modelled B table: ${oe.size} old, ${ne.size} new.`);
  const rawOnly = diff(o, n).concat(diff(n, o));
  if (rawOnly.length) {
    console.log(`  raw set differs on ${rawOnly.length}: ${rawOnly.slice(0, 10).join(', ')}`);
  }
  const effOnly = diff(oe, ne).concat(diff(ne, oe));
  if (effOnly.length) {
    failures += effOnly.length;
    console.log(`  EFFECTIVE set differs on ${effOnly.length}: ${effOnly.slice(0, 10).join(', ')}`);
    console.log('  spread_minutes legitimately differs on those tables. Report the difference;');
    console.log('  do not tolerate it silently.');
  } else if (rawOnly.length) {
    console.log('  none of them matches a Type B table on its date, so no setup minutes move.');
  }

  // --- R0b: the day's tasks, as a multiset. The 199-date workbook does NOT
  // preserve the 20-date export's row order (see R0c), so a positional
  // compare would report a permutation as a data change. Compare the records
  // themselves; the order is checked separately and explicitly.
  let compared = 0, orderMismatch = 0, orderDates = 0;
  for (const d of dates) {
    const a = oldDays[d].map(taskSig), b = newDays[d].map(taskSig);
    const moved = a.filter((s, i) => s !== b[i]).length;
    orderMismatch += moved;
    if (moved) orderDates += 1;
    const sa = a.slice().sort(), sb = b.slice().sort();
    for (let i = 0; i < sa.length; i++) {
      compared += TASK_FIELDS.length;
      if (sa[i] !== sb[i]) {
        failures += 1;
        if (failures <= 10) console.log(`  ${d}: old task not in new -> ${sa[i]}`);
      }
    }
  }
  console.log(`  task fields compared: ${compared} (${dates.length} dates x ` +
              `${TASK_FIELDS.length} fields).`);

  // --- R0c: row order. Informational. clusterBy() builds its map in first-seen
  // order, and both cluster and within-cluster sorts are stable, so a tie
  // between two equal-spread_minutes tables is broken by row order. R1's
  // informational line (the new file in its own row order) shows whether any
  // count moved with the order; R1's gate runs both files in one order.
  console.log(`  row ORDER differs on ${orderMismatch} of ` +
              `${dates.reduce((s, d) => s + oldDays[d].length, 0)} tables, ` +
              `across ${orderDates} of ${dates.length} dates. Informational: the records are`);
  console.log('  the same multiset; R1 below runs both files in one row order, and also reports the as-loaded order.');

  console.log(`R0: ${failures ? `FAILED, ${failures} differences` : 'PASSED'}`);
  return failures === 0;
}

function gateR1(dates, oldSub, newSub, combos, newAsLoaded) {
  console.log(`\nR1 — runCarry per-day results on the ${dates.length}-date subset, all ${combos.size} sweep scenarios, full float precision`);
  console.log('     (a reader check, NOT the published per-date numbers: the subset is only the unchanged dates)');
  console.log('     (both files in the old file\'s row order, compared exactly with Object.is)');
  let failures = 0, checks = 0;
  const loadedDiff = {};          // informational: the new file in its own row order
  for (const [key, scenario] of combos) {
    const pa = M.runCarry(scenario, oldSub).per_day;
    const pb = M.runCarry(scenario, newSub).per_day;
    const pc = M.runCarry(scenario, newAsLoaded).per_day;
    for (const d of dates) {
      const ra = pa[d], rb = pb[d], rc = pc[d];
      for (const k of DAY_KEYS) {
        checks += 1;
        if (!Object.is(ra[k], rb[k])) {
          failures += 1;
          if (failures <= 10) {
            console.log(`  ${d} ${key} ${k}: old=${ra[k]} new=${rb[k]}`);
          }
        }
        if (!Object.is(ra[k], rc[k])) loadedDiff[k] = (loadedDiff[k] || 0) + 1;
      }
    }
  }
  console.log(`R1: ${failures ? `FAILED, ${failures} of ${checks}` : 'PASSED'}, ` +
              `${dates.length}/${dates.length} dates x ${combos.size} scenarios x ` +
              `${DAY_KEYS.length} fields = ${checks} checks`);
  const loadedKeys = Object.keys(loadedDiff);
  console.log(`R1 (informational) new file in its OWN row order: ${loadedKeys.length ? loadedKeys.map(k => `${k} differs on ${loadedDiff[k]}`).join(', ') : 'no difference'}.`);
  console.log('     The model sums blocked minutes over a date\'s tasks in row order; a different row order moves');
  console.log('     only the last float digit of those sums, never a count (tasks, trolleys, compartments, pieces...).');
  return failures === 0;
}

function gateR2(dates, oldDays, newDays) {
  console.log('\nR2 — is_batch_last (informational, expected to move)');
  let flips = 0, tables = 0, oldStretch = 0, newStretch = 0;
  let offsetMoves = 0;
  for (const d of dates) {
    const a = oldDays[d], b = newDays[d];
    for (let i = 0; i < a.length; i++) {
      tables += 1;
      if (a[i].is_batch_last) oldStretch += 1;
      if (b[i].is_batch_last) newStretch += 1;
      if (a[i].is_batch_last !== b[i].is_batch_last) flips += 1;
      if (!Object.is(a[i].batch_first_offset_minutes, b[i].batch_first_offset_minutes)) {
        offsetMoves += 1;
      }
    }
  }
  const pct = (n) => (100 * n / tables).toFixed(1);
  console.log(`R2: ${flips} of ${tables} tables flip is_batch_last on the ${dates.length} shared dates.`);
  console.log(`    stretch-spreading share on those dates: ${oldStretch} of ${tables} ` +
              `(${pct(oldStretch)}%) old -> ${newStretch} of ${tables} (${pct(newStretch)}%) new.`);

  const wholeFile = (days) => {
    let t = 0, s = 0;
    for (const d of Object.keys(days)) for (const task of days[d]) { t += 1; if (task.is_batch_last) s += 1; }
    return [s, t];
  };
  const [so, to] = wholeFile(oldDays), [sn, tn] = wholeFile(newDays);
  console.log(`    whole-file share: ${so} of ${to} (${(100 * so / to).toFixed(0)}%) old, ` +
              `${sn} of ${tn} (${(100 * sn / tn).toFixed(0)}%) new.`);
  console.log(`    batch_first_offset_minutes moves on ${offsetMoves} of ${tables} tables — ` +
              'a dead field, never read by the page.');
  console.log('    is_batch_last reaches daytrace field 14 (was 15 before Phase 4 dropped field 14,');
  console.log('    batch_first_offset_minutes, from the shipped trace) -> the page\'s batchLast -> statusOf()');
  console.log('    -> bar colour, and nothing else. No trolley or blocking number depends on it.');
  return true;
}

function gateR3(dates, oldSub, newSub, combos) {
  console.log('\nR3 — pooled runCarry over the shared dates only (a reader check, not a published number)');
  let failures = 0, checks = 0;
  for (const [key, scenario] of combos) {
    const ra = M.runCarry(scenario, oldSub);
    const rb = M.runCarry(scenario, newSub);
    for (const k of POOLED_KEYS) {
      checks += 1;
      if (!Object.is(ra[k], rb[k])) {
        failures += 1;
        if (failures <= 10) console.log(`  ${key} ${k}: old=${ra[k]} new=${rb[k]}`);
      }
    }
  }
  console.log(`R3: ${failures ? `FAILED, ${failures} of ${checks}` : 'PASSED'}, ` +
              `${combos.size} scenarios x ${POOLED_KEYS.length} keys = ${checks} checks`);
  return failures === 0;
}

// ====================================================================== main
function main() {
  const started = Date.now();
  console.log('Old (regress fixture):', A.PIN_DATA_FILE);
  console.log('New (the build\'s data file):', A.DATA_FILE, '\n');

  const oldDays = M.loadDays(path.join(REPO, A.PIN_DATA_FILE), false);
  const newDays = M.loadDays(path.join(REPO, A.DATA_FILE), false);

  const { unchanged, ok } = deriveUnchangedDates(oldDays, newDays);
  const combos = S.sweepScenarios();

  const oldSub = subsetOf(oldDays, unchanged);
  const newAsLoaded = subsetOf(newDays, unchanged);
  const newSub = subsetInOrderOf(newDays, oldDays, unchanged);

  // The live floor waits for each batch's fabric, which depends on the batch's FIRST plan date in
  // the file (stampBatchReadiness): that legitimately differs between the 20-date export and the
  // 199-date workbook. For R1 and R3 (a reader check) both subsets are copied and re-stamped from
  // their own 18 dates, so only what the readers read can make them differ.
  const restamp = sub => {
    const out = {};
    for (const d of Object.keys(sub)) out[d] = sub[d].map(t => Object.assign({}, t));
    M.stampBatchReadiness(new Map(Object.entries(out)));
    return out;
  };
  const oldSubR = restamp(oldSub), newSubR = restamp(newSub), newLoadedR = restamp(newAsLoaded);

  const r0 = gateR0(unchanged, oldDays, newDays);
  const r1 = gateR1(unchanged, oldSubR, newSubR, combos, newLoadedR);
  gateR2(unchanged, oldDays, newDays);
  const r3 = gateR3(unchanged, oldSubR, newSubR, combos);

  const passed = ok && r0 && r1 && r3;
  console.log('\n============================================================');
  console.log(`R0/R1/R3: ${passed ? 'PASSED' : 'FAILED'}, ${unchanged.length}/${unchanged.length} ` +
              `dates x ${combos.size} scenarios x ${DAY_KEYS.length} fields`);
  console.log('R2: reported above — informational, expected to move.');
  console.log('============================================================');
  console.log(`done in ${((Date.now() - started) / 1000).toFixed(0)}s`);

  if (!passed) {
    console.error('\nREGRESSION GATE FAILED. Do not proceed: the two workbooks disagree on dates');
    console.error('whose data did not change, which means the data loading changed, not the data.');
    process.exitCode = 1;
  }
}

module.exports = { deriveUnchangedDates, gateR0, gateR1, gateR2, gateR3 };

if (require.main === module) {
  main();
}
