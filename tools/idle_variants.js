'use strict';
/*
 * IDLE-TIME VARIANTS — Node mirror of idle_variants.py
 * ===================================================
 * Mirror, do not improve: same function names, same behaviour, same markdown
 * output as idle_variants.py, so README Part 7 §2/§3/§4 (and the new §4b) can
 * be regenerated without Python. Neither script has ever actually executed on
 * this machine's model against the CURRENT data — the numbers this prints have
 * not been cross-checked against a real `python idle_variants.py` run (there is
 * no Python here). Treat them as "what the Node port computes", pending that.
 *
 *   node --max-old-space-size=6144 tools/idle_variants.js
 *
 * S0 sequencing (today's planner) across every plan date in the FULL file —
 * idle_variants.py is deliberately unscoped by WEBSITE_MONTHS (README Part 8
 * §5 HARD CHANGE #4). Prints only; writes nothing.
 *
 * Since 2026-11-09 it measures the published carry-over model (carryTimeline(),
 * one running timeline over all 199 plan dates, machines at the G2 standard
 * pace, blocked minutes = the staffed wait for table length). The
 * cold-start model it used to measure (every plan date a closed day,
 * raw-clock wait) was removed, so those numbers cannot be re-run: they
 * are kept as OLD below from the saved `npm run idle` output of 2026-11-09 and
 * printed beside the new ones. The two are NOT like for like (different floor
 * model); the gap is the floor model, not a rule.
 */
const path = require('path');
const A = require('./assumptions');
const M = require('./model');

const REPO = path.join(__dirname, '..');
const SEQUENCING_MODE = 'today';       // S0 — README Part 7 quotes S0 throughout
const SATURATED_CUTTER_PCT = 90;

// ---- the routing what-ifs (this analysis only — see idle_variants.py) ----
const FLEX_TODAY = Object.assign({}, A.FLEXIBLE_CUT);

const FLEX_NEIGHBOUR = Object.assign({}, FLEX_TODAY);
FLEX_NEIGHBOUR['24-10'] = ['24MC4', '24MC5'];
FLEX_NEIGHBOUR['24-13'] = ['24MC5', '24MC1'];

const FLEX_ANY = {};
for (const m of M.SPREADERS) FLEX_ANY[m] = Object.keys(A.CUT_GROUPS);

const CUTTER_LADDER = A.SIM_CUTTER_COUNTS;

// HISTORICAL cold-start results (closed-day model, full G2 speed, raw-clock
// blocked wait), from the `npm run idle` output saved on 2026-11-09 before the
// cold start was removed. Not re-runnable.
const OLD = {
  sec2: { work: 5273, blocked: 1563, over: 16, lastCut: '21:15' },
  sec3: {
    '24MC1': { busy: '43%', lost: 237, did: 1413, ratio: '17%' },
    '24MC2': { busy: '68%', lost: 138, did: 776, ratio: '18%' },
    '24MC3': { busy: '66%', lost: 213, did: 775, ratio: '28%' },
    '24MC4': { busy: '81%', lost: 484, did: 1155, ratio: '42%' },
    '24MC5': { busy: '81%', lost: 491, did: 1155, ratio: '43%' },
  },
  // blocked/day, over window %, in the order of section4()'s variants
  sec4: [[1563, 16], [1452, 12], [1373, 10], [1104, 9], [1006, 7], [953, 6], [559, 3]],
  sec4b: { 5: [1563, 16, '21:15'], 6: [900, 4, '20:00'], 7: [825, 5, '19:59'], 8: [724, 4, '19:52'] },
};

// run `fn` with a different F8 routing, then put it back. carryTimeline() reads
// A.FLEXIBLE_CUT at call time, so swapping the module attribute is enough
// (mirrors idle_variants.py's `routing` context manager). carryTimeline's cache
// key does NOT include the routing, so every measurement passes it a fresh
// shallow copy of `days` (a new WeakMap key) or it would return the first
// routing's result for all of them.
function withRouting(flexibleCut, fn) {
  const original = A.FLEXIBLE_CUT;
  A.FLEXIBLE_CUT = flexibleCut;
  try { return fn(); } finally { A.FLEXIBLE_CUT = original; }
}

// ---- one measurement: a table length and a routing, over every plan date ----
function measure(days, metres, flexibleCut) {
  const groups = Object.keys(A.CUT_GROUPS);
  const cutterBusy = {}, blockedByGroup = {}, spreadByGroup = {};
  for (const c of groups) { cutterBusy[c] = 0; blockedByGroup[c] = 0; spreadByGroup[c] = 0; }
  let work = 0, blocked = 0, lastCut = 0;
  let machinesOver = 0, machineDays = 0;

  withRouting(flexibleCut, () => {
    // fresh copy of `days`: carryTimeline's cache key ignores the routing
    const sim = M.carryTimeline(Object.assign({}, days), SEQUENCING_MODE, undefined, metres * A.YARDS_PER_METRE);
    sim.dates.forEach((date, di) => {
      const tasks = sim.byDate[date], mt = sim.metricsByDate[date];

      work += tasks.reduce((s, t) => s + t.spread_minutes, 0);
      blocked += mt.spreading_blocked_minutes;
      machinesOver += mt.machines_over_window;
      machineDays += M.SPREADERS.length;
      lastCut += Math.max(...tasks.map(t => t.cut_end - sim.off[di]));

      for (const t of tasks) {
        const group = M.PRIMARY_CUT[t.machine];
        cutterBusy[t.cutter] += t.cut_minutes;
        blockedByGroup[group] += t.blocked_minutes;
        spreadByGroup[group] += t.spread_minutes;
      }
    });
  });

  const n = Object.keys(days).length;
  const perDay = o => { const r = {}; for (const k of Object.keys(o)) r[k] = o[k] / n; return r; };
  return {
    days: n,
    work: work / n,
    blocked: blocked / n,
    over_pct: 100 * machinesOver / machineDays,
    last_cut: lastCut / n,
    cutter_busy: perDay(cutterBusy),
    blocked_by_group: perDay(blockedByGroup),
    spread_by_group: perDay(spreadByGroup),
  };
}

// ---- §4b: blocked minutes and over-window share at one cutter count ----
function measureCutters(days, cutters) {
  const layout = M.machineLayout(A.CUT_GROUPS_BY_CUTTER_COUNT[cutters]);
  const yards = A.SPREADING_TABLE_LENGTH_M * A.YARDS_PER_METRE;
  let blocked = 0, lastCut = 0, machinesOver = 0, machineDays = 0;
  const sim = M.carryTimeline(Object.assign({}, days), SEQUENCING_MODE, layout, yards);
  sim.dates.forEach((date, di) => {
    const tasks = sim.byDate[date], mt = sim.metricsByDate[date];
    blocked += mt.spreading_blocked_minutes;
    machinesOver += mt.machines_over_window;
    machineDays += layout.spreaders.length;
    lastCut += Math.max(...tasks.map(t => t.cut_end - sim.off[di]));
  });
  const n = Object.keys(days).length;
  return { cutters, blocked: blocked / n, over_pct: 100 * machinesOver / machineDays, last_cut: lastCut / n };
}

// ---- formatting helpers ----
const bold = s => `**${s}**`;
const comma = x => Math.round(x).toLocaleString('en-US');

function clock(minutesFromShiftStart) {
  // round the whole minute BEFORE splitting — matches idle_variants.py's clock()
  const abs = ((Math.round(minutesFromShiftStart + A.SHIFT_START_MINUTE) % 1440) + 1440) % 1440;
  return String(Math.floor(abs / 60)).padStart(2, '0') + ':' + String(abs % 60).padStart(2, '0');
}

// ---- the tables ----
function section2(base) {
  const o = OLD.sec2;
  console.log('## 2. What it costs\n');
  console.log(`| | Per day, across ${M.SPREADERS.length} spreading machines (carry-over) | Cold start (HISTORICAL) |`);
  console.log('|---|---|---|');
  console.log(`| Actual spreading work | ${comma(base.work)} min | ${comma(o.work)} min |`);
  console.log(`| Lost to blocking | **${comma(base.blocked)} min** — ${(base.blocked / 60).toFixed(0)} machine-hours | ${comma(o.blocked)} min — ${(o.blocked / 60).toFixed(0)} machine-hours |`);
  console.log(`| Machine-days over their staffed window | **${base.over_pct.toFixed(0)}%** | ${o.over}% |`);
  console.log(`| Last cut of the day finishes | ${clock(base.last_cut)} | ${o.lastCut} |`);
}

function section3(base) {
  console.log('\n## 3. Where it concentrates — and why\n');
  console.log('| Cut group | Spreaders | Cutter busy | Blocked / day | Spreading / day | Blocked / work | Cold start (HISTORICAL): busy, blocked, spreading, ratio |');
  console.log('|---|---|---|---|---|---|---|');
  for (const [group, spreaders] of Object.entries(A.CUT_GROUPS)) {
    const busy = 100 * base.cutter_busy[group] / M.CUTTER_MINUTES[group];
    const lost = base.blocked_by_group[group];
    const did = base.spread_by_group[group];
    const nights = A.NIGHT_SHIFT_CUTTERS.has(group) ? ' *(runs nights)*' : '';
    const old = OLD.sec3[group];
    const b = busy >= SATURATED_CUTTER_PCT ? bold : (s => String(s));
    console.log(`| ${b(group)} | ${b(spreaders.length)} | ${b(busy.toFixed(0) + '%')}${nights} | `
      + `${b(comma(lost) + ' min')} | ${b(comma(did) + ' min')} | ${b((100 * lost / did).toFixed(0) + '%')} | `
      + `${old.busy}, ${comma(old.lost)} min, ${comma(old.did)} min, ${old.ratio} |`);
  }
}

function section4(days) {
  const metres = A.SPREADING_TABLE_LENGTH_M;
  const variants = [
    [`**Today** — ${metres.toFixed(1)} m`,      metres, FLEX_TODAY,     '—',                false],
    ['24-10 and 24-13 borrow a neighbour',      metres, FLEX_NEIGHBOUR, 'a routing rule',   false],
    ['**Any cutter may serve any spreader**',   metres, FLEX_ANY,       'a routing rule',   true],
    ['Table to 24 m',                           24,     FLEX_TODAY,     'floor space',      false],
    ['Table to 24 m + neighbour routing',       24,     FLEX_NEIGHBOUR, 'both',             false],
    ['**Table to 24 m + any cutter**',          24,     FLEX_ANY,       'both',             true],
    ['Table to 27 m + any cutter',              27,     FLEX_ANY,       'both, more space', false],
  ];
  console.log('\n## 4. What fixes it\n');
  console.log('| Change | Blocked/day | Over window | Cost | Cold start (HISTORICAL): blocked/day, over window |');
  console.log('|---|---|---|---|---|');
  variants.forEach(([label, length, flex, cost, emphasised], i) => {
    const r = measure(days, length, flex);
    const b = emphasised ? bold : (s => String(s));
    console.log(`| ${label} | ${b(comma(r.blocked))} | ${b(r.over_pct.toFixed(0) + '%')} | ${cost} | ${comma(OLD.sec4[i][0])}, ${OLD.sec4[i][1]}% |`);
  });
}

function section4b(days) {
  console.log('\n## 4b. The cutting-machine-count ladder\n');
  console.log(`Rule F2 fixes **5** cutting machines against the 13 spreaders today; Part 7 §4`);
  console.log(`recommendation 4 names a sixth as the "only if volume grows" option. S0`);
  console.log(`sequencing, ${A.SPREADING_TABLE_LENGTH_M.toFixed(1)} m table, F8 routing as written — only the cutter count`);
  console.log(`moves. \`24MC1\` keeps 24-01/02/03 at every count, so the night shift is`);
  console.log(`unchanged throughout; only the ten day-only spreaders re-partition.\n`);
  console.log('| Cutters | Spreaders/cutter | Blocked/day | Over window | Last cut | Cold start (HISTORICAL): blocked/day, over window, last cut |');
  console.log('|---|---|---|---|---|---|');
  for (const n of CUTTER_LADDER) {
    const r = measureCutters(days, n);
    const old = OLD.sec4b[n];
    console.log(`| ${n} | ${(M.SPREADERS.length / n).toFixed(2)} | ${comma(r.blocked)} min | `
      + `${r.over_pct.toFixed(0)}% | ${clock(r.last_cut)} | ${comma(old[0])} min, ${old[1]}%, ${old[2]} |`);
  }
  console.log('\nThe trolley-number half of this ladder is table T-C (`tools/tc_table.js`,');
  console.log('README Part 8 §4): the cutter count moves trolley utilization by ~1 point on');
  console.log('S0 and not at all on S1–S3.');
}

function main() {
  const [days] = M.loadDays(path.join(REPO, A.DATA_FILE), true);
  const base = measure(days, A.SPREADING_TABLE_LENGTH_M, FLEX_TODAY);
  const tables = Object.values(days).reduce((s, ts) => s + ts.length, 0);
  console.log(`# README.md Part 7 — regenerated (Node port, carry-over model) from ${base.days} plan dates, ${tables} tables, S0 sequencing`);
  console.log('# NOTE: python idle_variants.py has never run here — these are the Node port\'s numbers, not cross-checked.\n');
  section2(base);
  section3(base);
  section4(days);
  section4b(days);
}

main();
