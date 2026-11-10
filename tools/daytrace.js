'use strict';
/*
THE TRACE — mirrors daytrace.py exactly. Per-plan-date detail for the
Simulation tab: the Job Sequence (order/time) and the loading-stage "expected"
lookup the browser's own loading port checks itself against (the parity
gate). See daytrace.py's module docstring for why the trolley maths itself is
NOT exported — the browser recomputes stage 4 live.
*/
const A = require('./assumptions');
const S = require('./scenarios');
const M = require('./model');
const { bankersRound } = require('./round');

// label == the sequencing_mode value itself — see model.js's makeScenario.
const MODES = [['today', 'today'], ['same_batch', 'same_batch'], ['cross_batch', 'cross_batch']];

// See daytrace.py's SIM_VARIANTS comment — the cutter axis ships in full at
// today's table length; the two extra table lengths ship as aggregates only
// (no time/order/expected), which is why the Gantt does not redraw at them.
// Mirrors daytrace.py's matching comment — 6/8 cutters dropped to aggregate-
// only 2026-09-08 (page-size budget; see assumptions.py's WEBSITE_MONTHS
// comment for the full reasoning).
const SIM_VARIANTS = [
  [A.SPREADING_TABLE_LENGTH_M, 5, true],
  [A.SPREADING_TABLE_LENGTH_M, 6, false],
  [A.SPREADING_TABLE_LENGTH_M, 7, true],
  [A.SPREADING_TABLE_LENGTH_M, 8, false],
  [24.0, 5, false],
  [27.0, 5, false],
];
const BASELINE_VARIANT = [A.SPREADING_TABLE_LENGTH_M, 5];

// Python's f'{m:g}' — general format, strips insignificant trailing zeros.
function metresKey(m) {
  if (Number.isInteger(m)) return String(m);
  let s = m.toPrecision(6);
  if (s.indexOf('e') !== -1 || s.indexOf('E') !== -1) return String(m);
  if (s.indexOf('.') !== -1) s = s.replace(/0+$/, '').replace(/\.$/, '');
  return s;
}

function variantKey(metres, cutters) {
  return `${metresKey(metres)}/${cutters}`;
}

// Field 14 used to be batch_first_offset_minutes — dropped, never read by the
// page's tasksFor() — so is_batch_last and spread_done_minutes each shifted
// down one. TASK_FIELDS and daytrace.py's tuple must stay in step.
const TASK_FIELDS = [
  'table_no', 'mo', 'style', 'color', 'batch', 'lot',
  'layers', 'marker_length', 'spread_minutes', 'cut_minutes',
  'pieces_by_size', 'needs_trolleys',
  'has_pattern', 'has_fabric', 'is_batch_last',
  'spread_done_minutes',
];

function minutesIntoDay(when, day) {
  if (when === null) return null;
  const midnight = M.midnightUTC(day);
  return bankersRound((when.getTime() - midnight) / 60000, 1);
}

function record(task, day) {
  return [
    task.table_no, task.mo, task.style, task.color,
    task.batch, task.lot,
    task.layers, bankersRound(task.marker_length, 2),
    bankersRound(task.spread_minutes, 1), bankersRound(task.cut_minutes, 1),
    Object.assign({}, task.pieces_by_size),
    task.needs_trolleys ? 1 : 0,
    task.has_pattern ? 1 : 0, task.has_fabric ? 1 : 0,
    task.is_batch_last ? 1 : 0,
    minutesIntoDay(task.spread_done_at, day),
  ];
}

function expected(plan, sequencingMode) {
  const out = {};
  for (const maxBatches of S.SWEEP_MAX_BATCHES) {
    for (const hold of S.SWEEP_HOLD_MINUTES) {
      for (const anyWs of S.SWEEP_ANY_WORKSTATION) {
        const key = S.sweepKey(sequencingMode, maxBatches, hold, anyWs);
        if (Object.prototype.hasOwnProperty.call(out, key)) continue;
        const loading = M.loadTrolleys(plan, M.makeScenario({
          name: key, sequencing_mode: sequencingMode, max_batches: maxBatches,
          wip_hold_minutes: hold, hold_any_workstation: anyWs,
        }));
        const comps = loading.compartments, trolleys = loading.trolleys;
        out[key] = [
          trolleys ? bankersRound(100 * comps / (A.TROLLEY_COMPARTMENTS * trolleys), 2) : 0.0,
          trolleys, comps, loading.combines,
        ];
      }
    }
  }
  return out;
}

// Mirrors daytrace.py's _groups_block(), which itself reuses
// idle_variants.py's attribution (lines 109-113) verbatim: blocked/spread
// minutes credited to the SPREADING machine's own group; cutter-busy minutes
// to the cutter that actually ran the task (which under F8 need not be its
// own group's).
function groupsBlock(copies, layout, spreadingAgg) {
  const primaryCut = layout.primary_cut;
  const cutGroups = layout.cut_groups;
  const cutterBusy = {}, blockedByGroup = {}, spreadByGroup = {};
  for (const c of Object.keys(cutGroups)) { cutterBusy[c] = 0; blockedByGroup[c] = 0; spreadByGroup[c] = 0; }

  for (const t of copies) {
    const group = primaryCut[t.machine];
    cutterBusy[t.cutter] += t.cut_minutes;
    blockedByGroup[group] += t.blocked_minutes;
    spreadByGroup[group] += t.spread_minutes;
  }

  const groups = {};
  for (const c of Object.keys(cutGroups)) {
    groups[c] = [
      bankersRound(cutterBusy[c], 1), bankersRound(blockedByGroup[c], 1),
      bankersRound(spreadByGroup[c], 1), cutGroups[c].length,
    ];
  }
  return { groups, over: [spreadingAgg.machines_over, layout.spreaders.length] };
}

// Each batch's first plan date across the whole file (stampBatchReadiness), so
// the Rules Lab's simulated fabric arrival is the same on every month page.
function batchFirstOf(days) {
  const out = {};
  for (const d of Object.keys(days)) for (const t of days[d]) out[String(t.batch)] = t.batch_first_planned;
  return out;
}

// The Rules Lab engine's task shape (tools/lab.js), straight from model.js's
// tasks and UNROUNDED, so the engine reproduces model.js exactly.
function labInput(days) {
  const dates = Object.keys(days).sort();
  const tasks = {};
  for (const d of dates) {
    tasks[d] = days[d].map((t, i) => ({
      i, tableNo: t.table_no, mo: String(t.mo), color: String(t.color), batch: String(t.batch),
      spread: t.spread_minutes, cut: t.cut_minutes, len: t.marker_length,
      pieces: Object.assign({}, t.pieces_by_size), needs: !!t.needs_trolleys, pt: t.pieces_total,
      ot: t.order_type, mk: t.marker_rel,
    }));
  }
  return { dates, tasks, batchFirst: batchFirstOf(days) };
}

// The same tasks as columns, for the page: dictionaries for the repeated
// strings and marker ratios, then one array per field. lab.js decode() turns
// it back into exactly labInput()'s output (lab_table.js checks that).
function labData(days) {
  const dates = Object.keys(days).sort();
  const dict = () => ({ list: [], map: new Map() });
  const idx = (dd, v) => {
    if (!dd.map.has(v)) { dd.map.set(v, dd.list.length); dd.list.push(v); }
    return dd.map.get(v);
  };
  const mo = dict(), co = dict(), ba = dict(), ra = dict(), ot = dict();
  const t = { d: [], no: [], mo: [], co: [], ba: [], ra: [], ly: [], ml: [], cs: [], nd: [], pt: [], ot: [], mk: [] };
  dates.forEach((date, di) => {
    for (const x of days[date]) {
      // pieces = ratio x layers, both integers, so the division is exact
      const ratio = {};
      for (const s of Object.keys(x.pieces_by_size)) ratio[s] = x.pieces_by_size[s] / x.layers;
      t.d.push(di); t.no.push(x.table_no);
      t.mo.push(idx(mo, String(x.mo))); t.co.push(idx(co, String(x.color))); t.ba.push(idx(ba, String(x.batch)));
      t.ra.push(idx(ra, JSON.stringify(ratio)));
      t.ly.push(x.layers); t.ml.push(x.marker_length); t.cs.push(x.c_setup_minutes); t.nd.push(x.needs_trolleys ? 1 : 0); t.pt.push(x.pieces_total);
      t.ot.push(idx(ot, x.order_type)); t.mk.push(x.marker_rel);
    }
  });
  const bf = {};
  const first = batchFirstOf(days);
  for (const b of Object.keys(first)) bf[ba.map.get(b)] = first[b];
  return { dates, mo: mo.list, co: co.list, ba: ba.list, ratio: ra.list.map(s => JSON.parse(s)), ot: ot.list, t, bf };
}

// `days` are the plan dates this file draws (one month); `allDays` is every
// in-scope plan date. The published model has no cold start (M.carryTimeline):
// a date's tables are timed on one timeline with the dates before it, so the
// simulation must run over all of them, and only this file's dates are kept.
// Times are shipped relative to each plan date's own 07:15.
function buildTrace(days, skipped, allDays) {
  skipped = skipped || {};
  allDays = allDays || days;
  const dates = Object.keys(days).sort();
  const out = { fields: TASK_FIELDS.slice(), dates: dates.slice(), days: {}, batchFirst: batchFirstOf(days) };
  // the minutes the model actually ran (the G2 time of each table)
  const sim0 = M.carryTimeline(allDays, 'today');

  for (const date of dates) {
    const off = sim0.off[sim0.dates.indexOf(date)];
    const day = {
      tasks: sim0.byDate[date].map(t => record(t, date)),
      skipped: skipped[date] || 0,
      seq: {},
    };

    for (const [mode, seqMode] of MODES) {
      const byVariant = {};

      for (const [metres, cutters, full] of SIM_VARIANTS) {
        const layout = M.machineLayout(A.CUT_GROUPS_BY_CUTTER_COUNT[cutters]);

        // one carry-over run per (mode, layout, table length), cached across
        // dates and months; its task copies carry the stamps and `_i`
        const sim = M.carryTimeline(allDays, seqMode, layout, metres * A.YARDS_PER_METRE);
        const copies = sim.byDate[date], plan = sim.planByDate[date];
        const spreadingAgg = { machines_over: sim.metricsByDate[date].machines_over_window };

        const variant = { blocked: bankersRound(copies.reduce((s, t) => s + t.blocked_minutes, 0), 1) };
        Object.assign(variant, groupsBlock(copies, layout, spreadingAgg));

        if (full) {
          const cuttersList = Object.keys(layout.cut_groups);
          const cutterIndex = {};
          cuttersList.forEach((c, i) => { cutterIndex[c] = i; });
          const n = copies.length;
          const ss = new Array(n).fill(null), se = new Array(n).fill(null);
          const cs = new Array(n).fill(null), ce = new Array(n).fill(null);
          const cut = new Array(n).fill(null);

          // order[machine] MUST live inside this per-variant object — see
          // daytrace.py's matching comment. A different cutter count
          // re-partitions the cut groups, which changes the sequence.
          const order = {};
          for (const machine of Object.keys(plan)) {
            const queue = plan[machine];
            if (!queue.length) continue;
            order[machine] = queue.map(t => t._i);
            for (const t of queue) {
              const i = t._i;
              ss[i] = bankersRound(t.spread_start - off, 1);
              se[i] = bankersRound(t.spread_end - off, 1);
              cs[i] = bankersRound(t.cut_start - off, 1);
              // cut_end is NOT rounded — see model.py/daytrace.py's own note;
              // the dashboard sorts loading events by it.
              ce[i] = t.cut_end - off;
              cut[i] = cutterIndex[t.cutter];
            }
          }

          variant.order = order;
          variant.time = { ss, se, cs, ce, cut };
          variant.cutters = cuttersList;
          variant.expected = expected(plan, seqMode);
        }

        byVariant[variantKey(metres, cutters)] = variant;
      }

      day.seq[mode] = { table: byVariant };
    }

    out.days[date] = day;
  }

  return out;
}

module.exports = {
  MODES, SIM_VARIANTS, BASELINE_VARIANT, metresKey, variantKey, TASK_FIELDS, buildTrace,
  labInput, labData, batchFirstOf,
};
