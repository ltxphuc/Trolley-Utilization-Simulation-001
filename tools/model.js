'use strict';
/*
THE MODEL — mirrors model.py exactly, stage for stage:

    1. READ      loadDays() reads data/planppc.xlsx via SheetJS
    2. SEQUENCE  sequence() / sequenceToday() / sequencePairs() / sequenceMoAware()
    3. TIME      carryTimeline() — spreading and cutting, blocking, cut_end
    4. LOAD      loadingEvents() / loadTrolleys() — trolley compartments

Every tunable lives in assumptions.js (itself a mirror of assumptions.py).
Nothing is hard-coded here. Function names match model.py's so the two files
can be diffed side by side.

Two JS-specific traps, both already fought and fixed once in dashboard.py's
browser port (see its comment at "Maps, not objects"):

  - Film widths (90/100/110) look like array indices to a plain JS object,
    which silently reorders them ascending regardless of insertion order.
    Python dicts (and the validated browser port) preserve insertion order,
    and that order decides which film opens a trolley first once the 52
    trolley bays are full (H7). Every film-keyed structure here is a Map.
  - Garment sizes ('XXS'..'4XL') and machine names ('24-01'..) are not
    integer-like strings, so plain objects preserve their insertion order
    correctly and are used for those.
*/
const path = require('path');
const A = require('./assumptions');
const Floor = require('./floor');

// ===================================================================== util
function minBy(arr, keyFn) {
  // Python's min(iterable, key=...): first element wins on ties.
  let best = arr[0], bestKey = keyFn(arr[0]);
  for (let i = 1; i < arr.length; i++) {
    const k = keyFn(arr[i]);
    if (k < bestKey) { best = arr[i]; bestKey = k; }
  }
  return best;
}

function meanOf(arr) {
  return arr.reduce((a, b) => a + b, 0) / arr.length;
}

// Unambiguous join for composite dict keys built from variable-length string
// fields (mo/color/batch/film/machine/table number/day). Python's dict uses
// real tuples as keys, which can never collide; a bare template-literal join
// of variable-length parts could (mo='AB'+color='C' vs mo='A'+color='BC').
// Built via fromCharCode rather than a '\x01'-style string escape, so the
// separator is a plain, visible expression in this source file instead of an
// invisible raw control byte that round-trips oddly through JSON-based tools.
const KEYSEP = String.fromCharCode(1);

// ===================================================================== shifts
function workingIntervals(nights) {
  const [s0, e0] = nights ? A.NIGHT_SHIFT : A.DAY_SHIFT;
  const start = Math.min(s0, A.DAY_SHIFT[0]);
  const end = e0;
  let breaks = A.DAY_BREAKS.concat(nights ? A.NIGHT_BREAKS : []);
  if (!A.BREAKS_STOP_MACHINES) breaks = [];
  breaks = breaks.slice().sort((a, b) => (a[0] - b[0]) || (a[1] - b[1]));

  const spans = [];
  let cursor = start;
  for (const [bStart, bEnd] of breaks) {
    if (bEnd <= cursor || bStart >= end) continue;
    if (bStart > cursor) spans.push([cursor, Math.min(bStart, end)]);
    cursor = Math.max(cursor, bEnd);
  }
  if (cursor < end) spans.push([cursor, end]);
  return spans;
}

function advance(spans, t) {
  for (const [s, e] of spans) {
    if (t < s) return s;
    if (t < e) return t;
  }
  return t;
}

function occupy(spans, start, minutes) {
  let t = advance(spans, start);
  const began = t;
  let left = minutes;
  for (const [s, e] of spans) {
    if (left <= 0) break;
    if (e <= t) continue;
    t = Math.max(t, s);
    const room = e - t;
    if (room >= left) return [began, t + left];
    left -= room;
    t = e;
  }
  return [began, t + left];
}

// ============================================================= machine layout
// One grouping of spreaders under cutters decides everything the sequencer and
// the timeline need to know about the machines — mirrors model.py's
// machine_layout(). Passing a layout in beats mutating module state, because a
// build interleaves layouts.
function machineLayout(cutGroups) {
  const cutters = Object.keys(cutGroups);
  const primaryCut = {};
  for (const c of cutters) for (const m of cutGroups[c]) primaryCut[m] = c;
  const spreaders = Object.keys(primaryCut);

  const spreaderShift = {};
  for (const m of spreaders) spreaderShift[m] = workingIntervals(A.NIGHT_SHIFT_SPREADERS.has(m));
  const cutterShift = {};
  for (const c of cutters) cutterShift[c] = workingIntervals(A.NIGHT_SHIFT_CUTTERS.has(c));

  // Staffed minutes, net of breaks — derived, never hard-coded.
  const machineMinutes = {};
  for (const m of spreaders) machineMinutes[m] = spreaderShift[m].reduce((s, [a, b]) => s + (b - a), 0);
  const cutterMinutes = {};
  for (const c of cutters) cutterMinutes[c] = cutterShift[c].reduce((s, [a, b]) => s + (b - a), 0);

  let shiftEnd = -Infinity;
  for (const m of spreaders) for (const [, e] of spreaderShift[m]) shiftEnd = Math.max(shiftEnd, e);

  return {
    cut_groups: cutGroups,
    primary_cut: primaryCut,
    spreaders,
    spreader_shift: spreaderShift,
    cutter_shift: cutterShift,
    machine_minutes: machineMinutes,
    cutter_minutes: cutterMinutes,
    shift_end: shiftEnd,
  };
}

const LAYOUT = machineLayout(A.CUT_GROUPS);

// The old top-level names, kept as aliases into the default layout so
// build.js and daytrace.js read exactly as they did.
const PRIMARY_CUT = LAYOUT.primary_cut;
const SPREADERS = LAYOUT.spreaders;
const SPREADER_SHIFT = LAYOUT.spreader_shift;
const CUTTER_SHIFT = LAYOUT.cutter_shift;
const MACHINE_MINUTES = LAYOUT.machine_minutes;
const CUTTER_MINUTES = LAYOUT.cutter_minutes;
const SHIFT_END = LAYOUT.shift_end;

// ===================================================================== scenario
// sequencing_mode mirrors model.py's Scenario.sequencing_mode: 'today' |
// 'same_batch' | 'cross_batch'. Not derived from max_batches — see model.py's
// field comment.
// mo_one_group (default false): the OLD S1-S3 rule, a whole MO + colour kept on
// one cut group (sequenceMoAware). Off = the pairs rule (sequencePairs). Only
// has an effect when sequencing_mode is not 'today'.
function makeScenario({ name, sequencing_mode = 'today', max_batches = 1,
                        wip_hold_minutes = 0, hold_any_workstation = true,
                        mo_one_group = false }) {
  return {
    name, sequencing_mode, max_batches, wip_hold_minutes, hold_any_workstation,
    cross_batch: max_batches >= 2,
    mo_one_group,
  };
}

// ===================================================================== 1. READ
function parseMarkerRatio(raw) {
  const out = {};
  const s = (raw === null || raw === undefined) ? '' : String(raw);
  for (const part of s.split(',')) {
    const idx = part.lastIndexOf('/');
    if (idx === -1) continue;
    const size = part.slice(0, idx).trim();
    const countStr = part.slice(idx + 1).trim();
    if (countStr === '') continue;
    const n = Number(countStr);
    if (!Number.isNaN(n)) out[size] = Math.trunc(n);
  }
  return out;
}

// Days between the Excel 1900-date-system epoch (1899-12-30) and the Unix
// epoch — the standard constant for serial -> JS Date conversion.
const EXCEL_EPOCH_OFFSET_DAYS = 25569;

// SheetJS's own `cellDates:true` conversion was verified (empirically,
// against this exact workbook) to mishandle the 1900 date system on a host
// whose local timezone is not UTC: a plain-integer serial (e.g. 46167, which
// the cell itself is formatted and displays as "25 May 2026") comes back as
// a Date one calendar day earlier with a spurious ~7-hour time-of-day (this
// host is UTC+7) instead of midnight. Reading the raw numeric serial
// (`cellDates:false`) and converting it ourselves — the textbook formula,
// cross-checked against several cells' own formatted `.w` display — sidesteps
// the bug entirely rather than working around it.
function excelSerialToDate(serial) {
  return new Date(Math.round((serial - EXCEL_EPOCH_OFFSET_DAYS) * 86400000));
}

function asDatetime(v) {
  return (typeof v === 'number') ? excelSerialToDate(v) : null;
}

// ---------------------------------------------------------------- C setup (G3)
// Mirrors model.py's _table_key / _fnv1a32 / _c_setup_minutes. The setup a C
// table adds is drawn from the table's own identity, never at random — a random
// draw would make every rebuild disagree with the last one.
function tableKey(value) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'number') {
    if (!Number.isInteger(value)) {
      throw new Error(`Table No ${value} is a non-integer number: Python and JS `
        + 'do not agree on its decimal spelling, so the C-setup seed would '
        + 'differ between the model and its port.');
    }
    return String(value);
  }
  return String(value).trim();
}

function fnv1a32(s) {
  let h = A.C_SETUP_HASH_OFFSET >>> 0;
  const bytes = Buffer.from(s, 'utf8');
  for (let i = 0; i < bytes.length; i++) {
    h = (h ^ bytes[i]) >>> 0;
    h = Math.imul(h, A.C_SETUP_HASH_PRIME) >>> 0;   // Math.imul is MANDATORY:
  }                                                 // h * 16777619 can exceed
  return h >>> 0;                                   // 2^53 and lose precision.
}

// `day` is already the 'YYYY-MM-DD' string Python's day.isoformat() produces.
function cSetupMinutes(day, tableNo) {
  const steps = A.C_SETUP_MINUTES_MAX_TENTHS - A.C_SETUP_MINUTES_MIN_TENTHS + 1;
  const h = fnv1a32(`${day}|${tableKey(tableNo)}`);
  const tenths = A.C_SETUP_MINUTES_MIN_TENTHS + (h % steps);
  return tenths / 10.0;
}

// 'YYYY-MM-DD' from the naive Excel datetime. SheetJS (cellDates:true)
// encodes the naive Excel serial as Date.UTC(y,m,d,h,mi,s), so the UTC
// getters recover exactly the naive components openpyxl's .date() sees —
// using the local getters here would drift the date on a UTC+N host near
// midnight boundaries.
function ymd(d) {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  const day = String(d.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function midnightUTC(ymdStr) {
  const [y, m, d] = ymdStr.split('-').map(Number);
  return Date.UTC(y, m - 1, d);
}

function loadDays(filePath, withStats) {
  const XLSX = require('xlsx');
  const wb = XLSX.readFile(filePath || A.DATA_FILE, { cellDates: false });
  const ws = wb.Sheets[A.DATA_SHEET];
  const allRows = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: null });
  const header = allRows[0];
  const col = {};
  header.forEach((name, i) => { col[name] = i; });
  // r[0] truthy — positional, exactly what model.py checks (column A, "MO").
  const rows = allRows.slice(1).filter(r => r[0]);

  // Counted, not just collected — C_SETUP_PER_C_ROW switches between one setup
  // per physical table (today) and one per C row. Mirrors the Counter in
  // model.py's load_days().
  const cTables = new Map();
  for (const r of rows) {
    if (r[col['Type']] === 'C' && typeof r[col['Plan Date']] === 'number') {
      const k = `${ymd(excelSerialToDate(r[col['Plan Date']]))}${KEYSEP}${r[col['Table No']]}`;
      cTables.set(k, (cTables.get(k) || 0) + 1);
    }
  }

  const days = new Map();        // 'YYYY-MM-DD' -> [task, ...], first-seen order
  const skipped = new Map();     // 'YYYY-MM-DD' -> count            (J2)

  for (const r of rows) {
    const planDate = asDatetime(r[col['Plan Date']]);
    if (r[col['Type']] !== 'B' || r[col['First Table']] === 'Y') {
      if (planDate) {
        const k = ymd(planDate);
        skipped.set(k, (skipped.get(k) || 0) + 1);
      }
      continue;
    }
    if (!planDate) continue;

    const ratio = parseMarkerRatio(r[col['Marker Ratio']]);
    const layers = r[col['Act LayerQty']] || 0;
    const markerLen = r[col['Marker Length']] || 0;
    if (Object.keys(ratio).length === 0 || layers <= 0 || markerLen <= 0) {
      const k = ymd(planDate);
      skipped.set(k, (skipped.get(k) || 0) + 1);
      continue;
    }

    const day = ymd(planDate);
    // J3 — only universal-size markers get trolley accounting.
    const universal = Object.keys(ratio).every(s =>
      Object.prototype.hasOwnProperty.call(A.FILM_SIZE_BY_GARMENT_SIZE, s));
    const tableNo = r[col['Table No']];
    const cRows = cTables.get(`${day}${KEYSEP}${tableNo}`) || 0;
    const setup = cRows
      ? cSetupMinutes(day, tableNo) * (A.C_SETUP_PER_C_ROW ? cRows : 1)
      : 0;

    const piecesBySize = {};
    if (universal) for (const s of Object.keys(ratio)) piecesBySize[s] = ratio[s] * layers;

    const markerLenF = Number(markerLen);
    const task = {
      table_no: tableNo,
      mo: r[col['MO']],
      style: r[col['STYLE']],
      color: r[col['Color']],
      lot: r[col['Lot']],
      batch: r[col['Batch No']],
      layers,
      marker_length: markerLenF,
      needs_trolleys: universal,
      pieces_by_size: piecesBySize,
      // every piece the table cuts (equals Cut Qty), universal sizes or not
      pieces_total: Object.keys(ratio).reduce((s, k) => s + ratio[k], 0) * layers,
      spread_minutes: layers * A.SPREAD_MIN_PER_LAYER_PER_YARD * markerLenF + setup,
      cut_minutes: layers * A.CUT_MIN_PER_LAYER_PER_YARD * markerLenF,
      // Carried separately as well as inside spread_minutes — mirrors
      // model.py:287 exactly (was a mirror gap: nothing here read it either,
      // but "mirror, do not improve" means the field belongs on every task
      // dict regardless of whether anything downstream uses it yet).
      c_setup_minutes: setup,
      plan_date: day,
      has_pattern: asDatetime(r[col['Marker Date']]) !== null,
      has_fabric: !!r[col['Lot']] && !!r[col['Batch No']],
      spread_done_at: asDatetime(r[col['Pull Date']]),
      // order type (订单类型: QR / Normal / SQR): S0's Job Sequence priority. Last field on purpose.
      order_type: r[col['订单类型']] == null ? '' : String(r[col['订单类型']]).trim(),
      // when the marker is ready, in minutes after its own plan date's 07:15 (negative: before it).
      // The live floor starts no table before it. Marker Date is always before Pull Date.
      marker_rel: asDatetime(r[col['Marker Date']]) === null ? 0
        : (asDatetime(r[col['Marker Date']]).getTime() - midnightUTC(day)) / 60000 - A.SHIFT_START_MINUTE,
    };
    if (!days.has(day)) days.set(day, []);
    days.get(day).push(task);
  }

  stampBatchReadiness(days);

  const daysObj = {};
  for (const [k, v] of days) daysObj[k] = v;
  if (withStats) {
    const skippedObj = {};
    for (const [k, v] of skipped) skippedObj[k] = v;
    return [daysObj, skippedObj];
  }
  return daysObj;
}

function stampBatchReadiness(days) {
  const firstPlan = new Map();   // batch -> 'YYYY-MM-DD' (min)
  const lastTable = new Map();   // batch -> [doneAt(Date), task]

  for (const [date, tasks] of days) {
    for (const t of tasks) {
      const batch = t.batch;
      if (!firstPlan.has(batch) || date < firstPlan.get(batch)) firstPlan.set(batch, date);
      const done = t.spread_done_at;
      if (done !== null) {
        const previous = lastTable.get(batch);
        if (!previous || done.getTime() > previous[0].getTime()) lastTable.set(batch, [done, t]);
      }
    }
  }

  for (const [, tasks] of days) {
    for (const t of tasks) {
      const arrived = firstPlan.get(t.batch);
      t.batch_first_planned = arrived;
      t.batch_first_offset_minutes = (midnightUTC(arrived) - midnightUTC(t.plan_date)) / 60000;
      const lt = lastTable.get(t.batch);
      t.is_batch_last = !!(lt && lt[1] === t);
    }
  }
}

// ============================================================ COMPARTMENT MATHS
function compartmentsFor(piecesBySize) {
  const out = new Map();   // film -> [pieces in each compartment], insertion order
  for (const size of Object.keys(piecesBySize)) {
    const qty = piecesBySize[size];
    const film = A.FILM_SIZE_BY_GARMENT_SIZE[size];
    const full = Math.floor(qty / A.COMPARTMENT_CAP);
    const remainder = qty - full * A.COMPARTMENT_CAP;
    if (!out.has(film)) out.set(film, []);
    const list = out.get(film);
    for (let k = 0; k < full; k++) list.push(A.COMPARTMENT_CAP);
    if (remainder) list.push(remainder);
  }
  return out;
}

function trolleysFor(comps) {
  let n = 0;
  for (const list of comps.values()) if (list.length) n += Math.ceil(list.length / A.TROLLEY_COMPARTMENTS);
  return n;
}

function mergePiecesBySize(a, b) {
  const merged = {};
  for (const s of Object.keys(a)) merged[s] = a[s];
  for (const s of Object.keys(b)) merged[s] = (merged[s] || 0) + b[s];
  return merged;
}

function combinedCompartments(a, b) {
  if (a.batch === b.batch) {
    return compartmentsFor(mergePiecesBySize(a.pieces_by_size, b.pieces_by_size));
  }
  const out = new Map();
  for (const table of [a, b]) {
    for (const [film, comps] of compartmentsFor(table.pieces_by_size)) {
      if (!out.has(film)) out.set(film, []);
      out.get(film).push(...comps);
    }
  }
  return out;
}

function canCombine(a, b, crossBatch) {
  if (!a.needs_trolleys || !b.needs_trolleys) return null;
  if (a.mo !== b.mo || a.color !== b.color) return null;
  if (a.batch !== b.batch && !crossBatch) return null;
  const comps = combinedCompartments(a, b);
  if (trolleysFor(comps) > A.MAX_TROLLEYS_PER_COMBINE) return null;
  return comps;
}

// ===================================================================== 2. SEQUENCE
function pickMachine(candidates, load, work, layout) {
  const spreaders = layout.spreaders;
  const machineMinutes = layout.machine_minutes;
  let room = candidates.filter(m => load[m] + work <= machineMinutes[m] * A.MACHINE_FILL_TARGET);
  if (room.length) return minBy(room, m => load[m]);
  room = spreaders.filter(m => load[m] + work <= machineMinutes[m] * A.MACHINE_FILL_TARGET);
  if (room.length) return minBy(room, m => load[m]);
  return minBy(spreaders, m => load[m] / machineMinutes[m]);
}

function sequence(tasks, sequencingMode, layout, initLoad, initCut, moOneGroup) {
  if (layout === undefined || layout === null) layout = LAYOUT;
  const groupLoad = {}; for (const c of Object.keys(layout.cut_groups)) groupLoad[c] = 0.0;
  const machineLoad = {}; for (const m of layout.spreaders) machineLoad[m] = 0.0;
  // initLoad (carry-over floor only): minutes of work each spreader already
  // has committed when the day is planned, so the planner balances around it.
  if (initLoad) {
    for (const m of layout.spreaders) machineLoad[m] = initLoad[m];
    for (const c of Object.keys(layout.cut_groups)) for (const m of layout.cut_groups[c]) groupLoad[c] += machineLoad[m];
  }
  const plan = {}; for (const m of layout.spreaders) plan[m] = [];
  // 'today' is S0, the real Job Sequence (sequenceJobSeq). 'today_grouped' is the
  // model's S0 before 2026-11-10 (kept only so npm run beforeafter can reproduce it).
  // Both ignore moOneGroup.
  if (sequencingMode === 'today') return sequenceJobSeq(tasks, plan, machineLoad, layout);
  if (sequencingMode === 'today_grouped') return sequenceToday(tasks, plan, machineLoad, groupLoad, layout);
  const crossBatch = sequencingMode === 'cross_batch';
  if (moOneGroup) return sequenceMoAware(tasks, plan, machineLoad, groupLoad, layout, crossBatch);
  return sequencePairs(tasks, plan, machineLoad, groupLoad, layout, crossBatch, initCut);
}

function clusterBy(tasks, keyFn) {
  const clusters = new Map();
  for (const t of tasks) {
    const k = keyFn(t);
    if (!clusters.has(k)) clusters.set(k, []);
    clusters.get(k).push(t);
  }
  return clusters;
}

function sumSpread(ts) { return ts.reduce((s, t) => s + t.spread_minutes, 0); }

// S0, the real Job Sequence: data/SQL Job Sequence Logic.sql, P_Task_Calculate (core loop only).
//  Pass 1 (L2105-2344): every table is given a CUTTER. Tables go in order of priority (order
//   type SQR < QR < Normal, A.ORDER_TYPE_PRIORITY), then plan order. A table goes to a cutter
//   that already holds a table of the same MO + batch this date, if any, else to any cutter;
//   among those, the one with the least load = spreading minutes / spreadCount. spreadCount
//   counts each spreader against its FIXED cutter as 1/(cutters it maps to) (24MC1 2.5, 24MC2
//   1.5, 24MC3 2, 24MC4 3, 24MC5 3). The load starts at the spreading minutes already committed
//   (initLoad) on the cutter's fixed spreaders, unweighted.
//  Pass 2 (L3693-): the spreader with the least spreading minutes (NOT divided by its shift
//   minutes) takes the next table, from the tables whose cutter it feeds (primary or flexible),
//   or from all tables if none: by priority, then the SHORTEST spreading time, then plan order.
//   The SQL's "closest to the cutter's gap" term never runs (L3715, L3773-3777): mirrored
//   as written. No fill target, no changeover; carryTimeline then runs the plan on the floor.
function sequenceJobSeq(tasks, plan, machineLoad, layout) {
  const spreaders = layout.spreaders, primary = layout.primary_cut;
  const cutters = Object.keys(layout.cut_groups);
  const mapOf = m => A.FLEXIBLE_CUT[m] || [primary[m]];
  const P = A.ORDER_TYPE_PRIORITY;
  const prioOf = t => (Object.prototype.hasOwnProperty.call(P, t.order_type) ? P[t.order_type] : A.ORDER_TYPE_PRIORITY_DEFAULT);

  const spreadCount = {}, raw = {};
  for (const c of cutters) { spreadCount[c] = 0; raw[c] = 0; }
  for (const m of spreaders) { spreadCount[primary[m]] += 1 / mapOf(m).length; raw[primary[m]] += machineLoad[m]; }

  const n = tasks.length;
  const prio = tasks.map(prioOf);
  const order = [];
  for (let i = 0; i < n; i++) order.push(i);
  order.sort((a, b) => prio[a] - prio[b] || a - b);

  const cutterOf = new Array(n);
  const held = new Map();                       // MO + batch -> cutters holding one this date
  for (const i of order) {
    const t = tasks[i];
    const key = `${t.mo}${KEYSEP}${t.batch}`;
    const has = held.get(key);
    const cands = has ? cutters.filter(c => has.has(c)) : cutters;
    const c = minBy(cands, x => raw[x] / spreadCount[x]);
    raw[c] += t.spread_minutes;
    cutterOf[i] = c;
    if (!has) held.set(key, new Set([c])); else has.add(c);
  }

  const placed = new Array(n).fill(false);
  let remaining = n;
  while (remaining > 0) {
    const m = minBy(spreaders, x => machineLoad[x]);
    const feeds = mapOf(m);
    let best = -1;
    const better = (i, j) => prio[i] - prio[j] || tasks[i].spread_minutes - tasks[j].spread_minutes || i - j;
    for (let i = 0; i < n; i++) {
      if (placed[i] || feeds.indexOf(cutterOf[i]) < 0) continue;
      if (best < 0 || better(i, best) < 0) best = i;
    }
    if (best < 0) {
      for (let i = 0; i < n; i++) {
        if (placed[i]) continue;
        if (best < 0 || better(i, best) < 0) best = i;
      }
    }
    placed[best] = true; remaining -= 1;
    plan[m].push(tasks[best]);
    machineLoad[m] += tasks[best].spread_minutes;
  }
  return plan;
}

// The model's S0 until 2026-11-10: clusters by MO + colour + batch and sends each cluster whole to
// one cut group. Not the real Job Sequence (user, 2026-11-09). Kept as mode 'today_grouped'.
function sequenceToday(tasks, plan, machineLoad, groupLoad, layout) {
  const clusters = clusterBy(tasks, t => `${t.mo}${KEYSEP}${t.color}${KEYSEP}${t.batch}`);
  const groups = Array.from(clusters.values())
    .sort((a, b) => sumSpread(b) - sumSpread(a));    // stable: descending spread_minutes

  const cutGroups = layout.cut_groups;
  for (const groupTasks of groups) {
    const cutGroup = minBy(Object.keys(groupLoad), c => groupLoad[c] / cutGroups[c].length);
    const machines = cutGroups[cutGroup];
    const ordered = groupTasks.slice().sort((a, b) => b.spread_minutes - a.spread_minutes);
    for (const task of ordered) {
      const machine = pickMachine(machines, machineLoad, task.spread_minutes, layout);
      plan[machine].push(task);
      machineLoad[machine] += task.spread_minutes;
      groupLoad[cutGroup] += task.spread_minutes;
    }
  }
  return plan;
}

function sequenceMoAware(tasks, plan, machineLoad, groupLoad, layout, crossBatch) {
  const clusters = clusterBy(tasks, t => `${t.mo}${KEYSEP}${t.color}`);
  const groups = Array.from(clusters.values())
    .sort((a, b) => sumSpread(b) - sumSpread(a));

  // pass 1 (different-batch pairing) only runs when crossBatch — see
  // model.py's matching comment for why this is the 2026-09-08 fix.
  const passes = crossBatch ? [true, false] : [true];

  for (const groupTasks of groups) {
    const ordered = groupTasks.slice().sort((a, b) => {
      const ba = String(a.batch), bb = String(b.batch);
      if (ba < bb) return -1;
      if (ba > bb) return 1;
      return b.spread_minutes - a.spread_minutes;
    });
    const taken = new Array(ordered.length).fill(false);
    const units = [];

    for (const sameBatchPass of passes) {
      for (let i = 0; i < ordered.length; i++) {
        if (taken[i]) continue;
        for (let j = i + 1; j < ordered.length; j++) {
          if (taken[j]) continue;
          const isSameBatch = ordered[i].batch === ordered[j].batch;
          if (isSameBatch !== sameBatchPass) continue;
          if (canCombine(ordered[i], ordered[j], true)) {
            units.push([ordered[i], ordered[j]]);
            taken[i] = taken[j] = true;
            break;
          }
        }
      }
    }
    for (let i = 0; i < ordered.length; i++) if (!taken[i]) units.push([ordered[i]]);

    const cutGroups = layout.cut_groups;
    const cutGroup = minBy(Object.keys(groupLoad), c => groupLoad[c] / cutGroups[c].length);
    const orderedUnits = units.slice().sort((a, b) => sumSpread(b) - sumSpread(a));
    for (const unit of orderedUnits) {
      const work = sumSpread(unit);
      const machine = pickMachine(cutGroups[cutGroup], machineLoad, work, layout);
      plan[machine].push(...unit);
      machineLoad[machine] += work;
      groupLoad[cutGroup] += work;
    }
  }
  return plan;
}

// The pairs rule (S1-S3 default): pair first, exactly as sequenceMoAware pairs,
// then put every unit (a pair or a lone table) of the whole day, largest first,
// on whichever cut group is least busy on its busier side: spreading load over
// its spreader minutes, or cutting load over its cutter minutes. The user's
// aim is cutter output, so the cutter backlog (initCut) counts, not only the
// spreaders'. Pairs from one MO + colour are therefore spread over the floor
// instead of all landing on one cut group.
function sequencePairs(tasks, plan, machineLoad, groupLoad, layout, crossBatch, initCut) {
  const clusters = clusterBy(tasks, t => `${t.mo}${KEYSEP}${t.color}`);
  const groups = Array.from(clusters.values())
    .sort((a, b) => sumSpread(b) - sumSpread(a));       // sets the tie order of the units

  const passes = crossBatch ? [true, false] : [true];
  const allUnits = [];

  for (const groupTasks of groups) {
    const ordered = groupTasks.slice().sort((a, b) => {
      const ba = String(a.batch), bb = String(b.batch);
      if (ba < bb) return -1;
      if (ba > bb) return 1;
      return b.spread_minutes - a.spread_minutes;
    });
    const taken = new Array(ordered.length).fill(false);
    const units = [];

    for (const sameBatchPass of passes) {
      for (let i = 0; i < ordered.length; i++) {
        if (taken[i]) continue;
        for (let j = i + 1; j < ordered.length; j++) {
          if (taken[j]) continue;
          const isSameBatch = ordered[i].batch === ordered[j].batch;
          if (isSameBatch !== sameBatchPass) continue;
          if (canCombine(ordered[i], ordered[j], true)) {
            units.push([ordered[i], ordered[j]]);
            taken[i] = taken[j] = true;
            break;
          }
        }
      }
    }
    for (let i = 0; i < ordered.length; i++) if (!taken[i]) units.push([ordered[i]]);
    for (const u of units) allUnits.push(u);
  }

  const cutGroups = layout.cut_groups;
  const cutters = Object.keys(cutGroups);
  const spCap = {}, cutLoad = {};
  for (const c of cutters) {
    spCap[c] = 0;
    for (const m of cutGroups[c]) spCap[c] += layout.machine_minutes[m];
    cutLoad[c] = initCut ? initCut[c] : 0;
  }

  for (const unit of allUnits.slice().sort((a, b) => sumSpread(b) - sumSpread(a))) {
    const work = sumSpread(unit);
    const cw = unit.reduce((s, t) => s + t.cut_minutes, 0);
    const cutGroup = minBy(cutters, c => Math.max((groupLoad[c] + work) / spCap[c],
                                                  (cutLoad[c] + cw) / layout.cutter_minutes[c]));
    const machine = pickMachine(cutGroups[cutGroup], machineLoad, work, layout);
    // pickMachine can fall outside the chosen group when it is full (Q8), so the
    // loads go to the machine's real group or the next unit would be balanced on
    // a lie. The cut side is credited to that group although FLEXIBLE_CUT lets a
    // few tables be cut by another cutter: an approximation, kept on purpose.
    const g = layout.primary_cut[machine];
    plan[machine].push(...unit);
    machineLoad[machine] += work;
    groupLoad[g] += work;
    cutLoad[g] += cw;
  }
  return plan;
}

// ===================================================================== 3. TIME
function freeLength(lays, tableLength, when) {
  let used = 0.0;
  for (const [length, cutStart, cutEnd] of lays) {
    if (when >= cutEnd) continue;
    if (when <= cutStart || cutEnd <= cutStart) used += length;
    else used += length * (cutEnd - when) / (cutEnd - cutStart);
  }
  return tableLength - used;
}

function roomAt(lays, tableLength, earliest, need) {
  if (freeLength(lays, tableLength, earliest) >= need) return earliest;
  const marks = [];
  for (const [, cs, ce] of lays) {
    if (cs > earliest) marks.push(cs);
    if (ce > earliest) marks.push(ce);
  }
  marks.sort((a, b) => a - b);
  let low = earliest;
  for (const mark of marks) {
    if (freeLength(lays, tableLength, mark) >= need) {
      let high = mark;
      for (let i = 0; i < 40; i++) {
        const mid = (low + high) / 2;
        if (freeLength(lays, tableLength, mid) >= need) high = mid;
        else low = mid;
      }
      return high;
    }
    low = mark;
  }
  let m = earliest;
  for (const [, , ce] of lays) m = Math.max(m, ce);
  return m;
}

// ===================================================================== 4. LOAD
function loadingEvents(plan, crossBatch) {
  const events = [];
  for (const machine of Object.keys(plan)) {
    const seq = plan[machine];
    let i = 0;
    while (i < seq.length) {
      if (!seq[i].needs_trolleys) { i += 1; continue; }
      const pair = (i + 1 < seq.length) ? canCombine(seq[i], seq[i + 1], crossBatch) : null;
      let comps, batches, when, table;
      if (pair) {
        comps = combinedCompartments(seq[i], seq[i + 1]);
        batches = new Set([seq[i].batch, seq[i + 1].batch]);
        when = Math.max(seq[i].cut_end, seq[i + 1].cut_end);
        table = seq[i];
        i += 2;
      } else {
        comps = compartmentsFor(seq[i].pieces_by_size);
        batches = new Set([seq[i].batch]);
        when = seq[i].cut_end;
        table = seq[i];
        i += 1;
      }
      events.push({ when, table, comps, batches, machine });
    }
  }
  events.sort((a, b) => a.when - b.when);   // Array#sort is stable (Node >= 11)
  return events;
}

function loadTrolleys(plan, scenario) {
  const events = loadingEvents(plan, scenario.cross_batch);
  const hold = scenario.wip_hold_minutes;

  const parked = new Map();   // key -> [{free, at, batches:Set}, ...]
  const parkedNow = () => { let n = 0; for (const v of parked.values()) n += v.length; return n; };

  let compartmentsUsed = 0, trolleysOpened = 0, pieces = 0, combines = 0;
  const waits = [];
  let blockedBySpace = 0;

  for (const { when, table, comps, batches, machine } of events) {
    if (batches.size > 1) combines += 1;

    for (const key of Array.from(parked.keys())) {
      const stillWaiting = [];
      for (const trolley of parked.get(key)) {
        if (when - trolley.at <= hold) stillWaiting.push(trolley);
        else waits.push(when - trolley.at);
      }
      parked.set(key, stillWaiting);
    }

    for (const [film, compartmentList] of comps) {
      if (!compartmentList.length) continue;
      compartmentsUsed += compartmentList.length;
      for (const q of compartmentList) pieces += q;

      let key = `${table.mo}${KEYSEP}${table.color}${KEYSEP}${film}`;
      if (!scenario.hold_any_workstation) key += `${KEYSEP}${machine}`;

      let need = compartmentList.length;
      const arr = parked.get(key) || [];
      for (const trolley of arr) {
        if (need === 0) break;
        const wouldCarry = new Set([...trolley.batches, ...batches]);
        if (wouldCarry.size > A.MAX_BATCHES_PER_TROLLEY) continue;   // 3rd batch
        const take = Math.min(trolley.free, need);
        if (take === 0) continue;
        trolley.free -= take;
        trolley.batches = wouldCarry;
        need -= take;
      }
      parked.set(key, arr.filter(t => t.free > 0));

      while (need > 0) {
        const take = Math.min(A.TROLLEY_COMPARTMENTS, need);
        need -= take;
        trolleysOpened += 1;
        const spare = A.TROLLEY_COMPARTMENTS - take;
        if (spare && hold > 0) {
          if (parkedNow() < A.TROLLEY_BAYS) {
            const cur = parked.get(key) || [];
            cur.push({ free: spare, at: when, batches: new Set(batches) });
            parked.set(key, cur);
          } else {
            blockedBySpace += 1;
          }
        }
      }
    }
  }

  return {
    compartments: compartmentsUsed,
    trolleys: trolleysOpened,
    pieces,
    combines,
    avg_wait_hours: waits.length ? meanOf(waits) / 60 : 0.0,
    blocked_by_space: blockedBySpace,
  };
}

// ===================================================================== RUN
// Pools per-plan-date results into the published aggregate, for runCarry().
function pool(scenario, perDay) {
  const dayKeys = Object.keys(perDay);
  const avg = (k) => meanOf(dayKeys.map(d => perDay[d][k]));

  let totalComps = 0, totalTrolleys = 0, totalPieces = 0;
  for (const d of dayKeys) {
    totalComps += perDay[d].compartments;
    totalTrolleys += perDay[d].trolleys;
    totalPieces += perDay[d].pieces;
  }

  return {
    scenario: scenario.name,
    settings: {
      sequencing_mode: scenario.sequencing_mode,
      max_batches: scenario.max_batches,
      wip_hold_minutes: scenario.wip_hold_minutes,
      hold_any_workstation: scenario.hold_any_workstation,
    },
    // utilization is pooled over all days, not a mean of daily percentages
    utilization_pct: 100 * totalComps / (A.TROLLEY_COMPARTMENTS * totalTrolleys),
    trolleys_per_day: totalTrolleys / dayKeys.length,
    peak_trolleys_in_a_day: Math.max(...dayKeys.map(d => perDay[d].trolleys)),
    compartments_per_day: totalComps / dayKeys.length,
    // how full the compartments that got OPENED actually are — the number
    // utilization_pct does not carry. utilization_pct counts compartments
    // opened (H6); this is pieces on board vs what those same compartments
    // could hold (COMPARTMENT_CAP each). Pooled, matching utilization_pct's
    // own basis, not a mean of daily percentages.
    compartment_fill_pct: 100 * totalPieces / (A.COMPARTMENT_CAP * totalComps),
    // what the compartments actually opened could hold, if every one of
    // them were full — the number 750 (ceiling) and 306ish (pieces on
    // board) both need a bridge to reconcile against; this is it.
    garments_per_trolley_capacity: A.COMPARTMENT_CAP * totalComps / totalTrolleys,
    // Option A: pooled (totalPieces / totalTrolleys), matching
    // utilization_pct's basis — was avg('pieces_per_trolley'), a mean of 20
    // daily ratios, which does not equal capacity x fill even once
    // compartment_fill_pct exists (~1% residual). See README Part 8.
    pieces_per_trolley: totalPieces / totalTrolleys,
    spreading_blocked_pct: avg('spreading_blocked_pct'),
    cutting_blocked_pct: avg('cutting_blocked_pct'),
    spreading_makespan_hours: avg('spreading_makespan_hours'),
    spreading_blocked_minutes: avg('spreading_blocked_minutes'),
    spreading_overrun_minutes: avg('spreading_overrun_minutes'),
    machines_over_window: avg('machines_over_window'),
    avg_wait_hours: avg('avg_wait_hours'),
    blocked_by_space: dayKeys.reduce((s, d) => s + perDay[d].blocked_by_space, 0),
    per_day: perDay,
  };
}

// ============================================================ CARRY-OVER FLOOR
// The published model (user rule, 2026-11-06): there is no cold start. One
// timeline runs over every plan date, in staffed hours only, so work a machine
// did not finish carries into the next shift, and the Job Sequence of each plan
// date is planned on its own morning around what every spreader still has
// committed. Machines run at the G2 standard pace (no speed factor).
// The closed-day cold-start model was removed on 2026-11-09 (user: "there will
// never be a cold start").
function staffedBetween(spans, a, b) {
  if (b <= a) return 0;
  let s = 0;
  for (const [x, y] of spans) { if (x >= b) break; s += Math.max(0, Math.min(y, b) - Math.max(x, a)); }
  return s;
}

const carryCache = new WeakMap();

// Stage 2+3 for the whole run. Depends on the sequencing mode, layout, table
// length, not on the loading settings, so it is cached per days object.
function carryTimeline(days, sequencingMode, layout, tableLength, moOneGroup) {
  if (layout === undefined || layout === null) layout = LAYOUT;
  if (tableLength === undefined || tableLength === null) tableLength = A.SPREADING_TABLE_LENGTH;
  const key = JSON.stringify([sequencingMode, !!moOneGroup, layout.cut_groups, tableLength,
    A.CUT_SETUP_MO_COLOR_MINUTES, A.CUT_TRAVEL_MINUTES, A.LIVE_FLOOR, A.REPLAN_MINUTES, A.PLAN_HORIZON_HOURS]);
  let byKey = carryCache.get(days);
  if (!byKey) { byKey = new Map(); carryCache.set(days, byKey); }
  if (byKey.has(key)) return byKey.get(key);

  const dates = Object.keys(days).sort();
  const nDays = dates.length, day0 = midnightUTC(dates[0]);
  const off = dates.map(d => (midnightUTC(d) - day0) / 60000);
  const spreaders = layout.spreaders, cutters = Object.keys(layout.cut_groups);
  const primaryCut = layout.primary_cut;

  // every task of every date, copied (sequence()/the timeline stamp them)
  let totSpread = 0, totCut = 0;
  const byDate = {};
  dates.forEach((d, di) => {
    byDate[d] = days[d].map((t, i) => {
      const c = Object.assign({}, t, { _i: i, date: d, dayIdx: di });
      totSpread += c.spread_minutes; totCut += c.cut_minutes;
      return c;
    });
  });

  // staffed spans over every plan date, plus synthetic days after the last,
  // sized to the work so the last tables also finish on staffed hours
  let spCap = 0, cuCap = 0;
  for (const m of spreaders) spCap += layout.machine_minutes[m];
  for (const c of cutters) cuCap += layout.cutter_minutes[c];
  const extra = Math.min(3000, Math.ceil(2 * Math.max(totSpread / spCap, totCut / cuCap)) + 14);
  const offsets = off.slice();
  for (let k = 1; k <= extra; k++) offsets.push(off[nDays - 1] + k * 1440);
  const repeat = spans => { const out = []; for (const x of offsets) for (const [a, b] of spans) out.push([x + a, x + b]); return out; };
  const spSp = {}, cuSp = {};
  for (const m of spreaders) spSp[m] = repeat(layout.spreader_shift[m]);
  for (const c of cutters) cuSp[c] = repeat(layout.cutter_shift[c]);

  const free = {}, lays = {}, cutFree = {};
  for (const m of spreaders) { free[m] = 0.0; lays[m] = []; }
  for (const c of cutters) cutFree[c] = 0.0;
  // what each cutter cut last: it carries across plan dates, like cutFree
  const lastCut = {};
  for (const c of cutters) lastCut[c] = null;
  const planByDate = {};

  if (A.LIVE_FLOOR) {
    // The live floor (tools/floor.js, user rules 2026-11-10): re-plan every REPLAN_MINUTES, every
    // table starts only once it is READY (plan date, Marker Date, fabric), and a free cutter takes
    // the lay that has waited longest. Fabric readiness is the Lab's relaxing ESTIMATE.
    const spanMin = Math.round((A.RELAX_ARRIVAL_LEAD_MAX_H - A.RELAX_ARRIVAL_LEAD_MIN_H) * 60);
    const fabric = new Map(), all = [];
    for (const date of dates) for (const t of byDate[date]) {
      const bk = String(t.batch);
      let fr = fabric.get(bk);
      if (fr === undefined) {
        const first = (midnightUTC(t.batch_first_planned) - day0) / 60000;
        const lead = Math.round(A.RELAX_ARRIVAL_LEAD_MIN_H * 60) + (fnv1a32('relax|' + bk) % (spanMin + 1));
        fr = first - lead + A.RELAX_HOURS * 60;
        fabric.set(bk, fr);
      }
      t._rel = Math.max(Math.max(off[t.dayIdx], fr), off[t.dayIdx] + t.marker_rel);
      all.push(t);
    }
    const FIELD = { m: 'machine', sb: 'spread_start', se: 'spread_end', blockedStaffed: 'blocked_minutes', cutter: 'cutter',
      cutWait: 'cut_wait', setup: 'cut_setup_minutes', travel: 'cut_travel_minutes', cb: 'cut_start', ce: 'cut_end' };
    const res = Floor.run({
      spreaders, cutters, primary: primaryCut,
      flexOf: Object.fromEntries(spreaders.map(m => [m, A.FLEXIBLE_CUT[m] || [primaryCut[m]]])),
      spSp, cuSp, tableLength, setupMin: A.CUT_SETUP_MO_COLOR_MINUTES, travelMin: A.CUT_TRAVEL_MINUTES,
      tasks: all, tickMin: A.REPLAN_MINUTES, horizonMin: A.PLAN_HORIZON_HOURS * 60,
      seqFn: (group, init, initCut) => sequence(group, sequencingMode, layout, init, initCut, moOneGroup),
      // S1-S3 pair first (rule (a)): the partner of a started table is pinned next on its spreader
      isPair: (sequencingMode === 'today' || sequencingMode === 'today_grouped') ? undefined
        : (a, b) => (sequencingMode === 'cross_batch' || a.batch === b.batch) && canCombine(a, b, true) !== null,
      get: { rel: t => t._rel, spread: t => t.spread_minutes, cut: t => t.cut_minutes, len: t => t.marker_length,
        mo: t => t.mo, color: t => t.color, day: t => t.dayIdx },
      put: (t, r) => { for (const k of Object.keys(r)) if (FIELD[k]) t[FIELD[k]] = r[k]; },
    });
    for (const d of dates) { const p = {}; for (const m of spreaders) p[m] = []; planByDate[d] = p; }
    for (const m of spreaders) for (const t of res.seq[m]) planByDate[t.date][m].push(t);
  } else dates.forEach((date, di) => {
    // the planner sees what each machine still has committed at the day's start
    const init = {};
    for (const m of spreaders) init[m] = staffedBetween(spSp[m], off[di], free[m]);
    // and what each cutter still has to cut, in staffed minutes
    const initCut = {};
    for (const c of cutters) initCut[c] = staffedBetween(cuSp[c], off[di], cutFree[c]);
    const plan = sequence(byDate[date], sequencingMode, layout, init, initCut, moOneGroup);
    planByDate[date] = plan;
    const ptr = {}; for (const m of spreaders) ptr[m] = 0;
    let remaining = byDate[date].length;
    while (remaining > 0) {
      const cands = spreaders.filter(m => ptr[m] < plan[m].length);
      const machine = minBy(cands, m => advance(spSp[m], free[m]));
      const eff = advance(spSp[machine], free[machine]);
      if (eff < off[di]) { free[machine] = off[di]; continue; }   // the plan date has not begun
      const task = plan[machine][ptr[machine]++];
      remaining -= 1;

      lays[machine] = lays[machine].filter(l => l[2] > eff);
      const start = roomAt(lays[machine], tableLength, eff, task.marker_length);
      task.blocked_minutes = staffedBetween(spSp[machine], eff, start);
      const [spreadStart, spreadEnd] = occupy(spSp[machine], start, task.spread_minutes);
      free[machine] = spreadEnd;

      const flex = A.FLEXIBLE_CUT[machine] || [primaryCut[machine]];
      const cutter = minBy(flex, c => cutFree[c]);
      task.cut_wait = Math.max(0.0, spreadEnd - cutFree[cutter]);
      // Cutter changeover (user rule, 2026-11-09, ESTIMATES): an MO or colour change
      // against the cutter's last cut costs CUT_SETUP_MO_COLOR_MINUTES; moving to a
      // different spreader than its last cut costs CUT_TRAVEL_MINUTES. Both are
      // added on top of the G2 pace (they are walking and cleaning, not machine rate), and
      // lab.js dispatch() is the same rule, added left to right for exact equality.
      // Strings are compared because the Lab's tasks hold String(mo)/String(color).
      const lc = lastCut[cutter];
      const setup = lc && (String(lc.mo) !== String(task.mo) || String(lc.color) !== String(task.color))
        ? A.CUT_SETUP_MO_COLOR_MINUTES : 0;
      const travel = lc && lc.machine !== machine ? A.CUT_TRAVEL_MINUTES : 0;
      const [cutStart, cutEnd] = occupy(cuSp[cutter], Math.max(spreadEnd, cutFree[cutter]), task.cut_minutes + setup + travel);
      cutFree[cutter] = cutEnd;
      lastCut[cutter] = { mo: task.mo, color: task.color, machine };
      // Q19: the spreading table stays occupied through the changeover and the move
      // (the fabric is still on it until it is cut). The table frees from
      // cutStart + setup + travel on the RAW clock, so a break inside the setup
      // starts the freeing early (capped at cutEnd). Mirrored from the Lab, not fixed.
      lays[machine].push([task.marker_length, Math.min(cutEnd, cutStart + setup + travel), cutEnd]);

      task.machine = machine; task.cutter = cutter;
      task.cut_setup_minutes = setup; task.cut_travel_minutes = travel;
      task.spread_start = spreadStart; task.spread_end = spreadEnd;
      task.cut_start = cutStart; task.cut_end = cutEnd;
    }
  });

  // per-plan-date idle-time figures, from the tables that date planned
  const metricsByDate = {};
  dates.forEach((date, di) => {
    const ts = byDate[date];
    let sBusy = 0, sBlocked = 0, cBusy = 0, cWait = 0, last = 0, overrun = 0;
    const over = new Set();
    for (const t of ts) {
      sBusy += t.spread_minutes; sBlocked += t.blocked_minutes;
      cBusy += t.cut_minutes; cWait += t.cut_wait;
      last = Math.max(last, t.spread_end);
      const winEnd = off[di] + layout.spreader_shift[t.machine][layout.spreader_shift[t.machine].length - 1][1];
      if (t.spread_end > winEnd) {
        over.add(t.machine);
        overrun += staffedBetween(spSp[t.machine], Math.max(t.spread_start, winEnd), t.spread_end);
      }
    }
    metricsByDate[date] = {
      spreading_blocked_pct: (sBusy + sBlocked) ? 100 * sBlocked / (sBusy + sBlocked) : 0.0,
      cutting_blocked_pct: (cBusy + cWait) ? 100 * cWait / (cBusy + cWait) : 0.0,
      spreading_makespan_hours: ts.length ? (last - off[di]) / 60 : 0.0,
      spreading_blocked_minutes: sBlocked,
      spreading_overrun_minutes: overrun,
      machines_over_window: over.size,
    };
  });

  const sim = { dates, off, byDate, planByDate, metricsByDate };
  byKey.set(key, sim);
  return sim;
}

function runCarry(scenario, days, opts) {
  opts = opts || {};
  const sim = carryTimeline(days, scenario.sequencing_mode, opts.layout, opts.tableLength, scenario.mo_one_group);
  const perDay = {};
  for (const date of sim.dates) {
    const loading = loadTrolleys(sim.planByDate[date], scenario);
    const comps = loading.compartments, trolleys = loading.trolleys;
    const mt = sim.metricsByDate[date];
    perDay[String(date)] = {
      tasks: sim.byDate[date].length,
      combines: loading.combines,
      compartments: comps,
      trolleys,
      pieces: loading.pieces,
      trolley_utilization_pct: trolleys ? 100 * comps / (A.TROLLEY_COMPARTMENTS * trolleys) : 0.0,
      compartment_fill_pct: comps ? 100 * loading.pieces / (A.COMPARTMENT_CAP * comps) : 0.0,
      pieces_per_trolley: trolleys ? loading.pieces / trolleys : 0.0,
      spreading_blocked_pct: mt.spreading_blocked_pct,
      cutting_blocked_pct: mt.cutting_blocked_pct,
      spreading_makespan_hours: mt.spreading_makespan_hours,
      spreading_blocked_minutes: mt.spreading_blocked_minutes,
      spreading_overrun_minutes: mt.spreading_overrun_minutes,
      machines_over_window: mt.machines_over_window,
      avg_wait_hours: loading.avg_wait_hours,
      blocked_by_space: loading.blocked_by_space,
    };
  }
  return pool(scenario, perDay);
}

// ===================================================================== fleet
function fleetRequired(trolleysPerDay, cycleDays) {
  return trolleysPerDay * cycleDays;
}

function longestSustainableCycle(trolleysPerDay, fleet) {
  return (fleet || A.FLEET_SIZE) / trolleysPerDay;
}

module.exports = {
  A,
  minBy, meanOf,
  workingIntervals, advance, occupy,
  machineLayout, LAYOUT,
  PRIMARY_CUT, SPREADERS, SPREADER_SHIFT, CUTTER_SHIFT, MACHINE_MINUTES, CUTTER_MINUTES, SHIFT_END,
  makeScenario,
  parseMarkerRatio, asDatetime, ymd, midnightUTC, loadDays, stampBatchReadiness,
  compartmentsFor, trolleysFor, combinedCompartments, canCombine,
  clusterBy, sumSpread,
  pickMachine, sequence, sequenceToday, sequenceMoAware, sequencePairs,
  freeLength, roomAt,
  loadingEvents, loadTrolleys,
  pool,
  staffedBetween, carryTimeline, runCarry,
  fleetRequired, longestSustainableCycle,
};
