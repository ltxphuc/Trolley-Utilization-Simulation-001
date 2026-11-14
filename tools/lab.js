'use strict';
/*
THE RULES LAB ENGINE.

    node:  const Lab = require('./lab');
    page:  build.js inlines this file, so the page runs the SAME code (no port).

One floor, the published model (user rule, 2026-11-06: no cold start, work is
always left from the day before; the cold-start floor was removed 2026-11-09).
One timeline over all plan dates, staffed hours only. With plan 'backlog' each
plan date is sequenced on its own morning around what every spreader still has
committed. Machines run at the G2 standard pace (no speed factor, removed
2026-11-09). With the defaults the results equal tools/model.js runCarry() to the
last bit (npm run lab checks all 117 sweep scenarios).

Cutter SETUP on an MO/colour change and cutter TRAVEL between workstations are
part of the published floor (defaults 5 / 1.5 min, ESTIMATES) and can be changed.
These are optional add-ons, all off by default: simulated fabric RELAXING,
DYNAMIC dispatch, pull-ahead, rule (a)/(b)/(c) variants and a day / night shift
option. Arrival, setup and travel are ESTIMATES (assumptions.py). Loading is
per plan date, as in the model.

It is Node-and-page only: there is no lab.py (Python cannot run here, and one
shared file removes the port risk). model.js is the independent reference.
All numbers come from `cfg` (makeConfig(assumptions)), never from this file.

A task is: { i, mo, color, batch(String), spread, cut, len, pieces, needs, tableNo }.
Raw (unrounded) inputs reproduce model.js; see daytrace.js labInput().
*/
(function (exports) {

const KEYSEP = String.fromCharCode(1);
const Floor = (typeof module !== 'undefined' && module.exports) ? require('./floor') : window.Floor;

function makeConfig(A) {
  return {
    tableLength: A.SPREADING_TABLE_LENGTH,
    film: A.FILM_SIZE_BY_GARMENT_SIZE,
    cap: A.COMPARTMENT_CAP,
    comps: A.TROLLEY_COMPARTMENTS,
    maxPerCombine: A.MAX_TROLLEYS_PER_COMBINE,
    bays: A.TROLLEY_BAYS,
    maxBatches: A.MAX_BATCHES_PER_TROLLEY,
    cutGroups: A.CUT_GROUPS,
    // the what-ifs moved from the Simulation tab (2026-11-14): cutter count and table length. Part of
    // the SELECTION only: S0 (ladder()) never gets them, so S0 stays at today's floor (5 cutters, 21.2 m).
    cutGroupsByCount: A.CUT_GROUPS_BY_CUTTER_COUNT, cutterCounts: A.SIM_CUTTER_COUNTS,
    tableOptionsM: A.LAB_TABLE_LENGTHS_M, yardsPerMetre: A.YARDS_PER_METRE,
    flex: A.FLEXIBLE_CUT,
    nightSpreaders: Array.from(A.NIGHT_SHIFT_SPREADERS),
    nightCutters: Array.from(A.NIGHT_SHIFT_CUTTERS),
    dayShift: A.DAY_SHIFT, nightShift: A.NIGHT_SHIFT,
    dayBreaks: A.DAY_BREAKS, nightBreaks: A.NIGHT_BREAKS,
    breaksStop: A.BREAKS_STOP_MACHINES,
    fillTarget: A.MACHINE_FILL_TARGET,
    orderPrio: A.ORDER_TYPE_PRIORITY, orderPrioDefault: A.ORDER_TYPE_PRIORITY_DEFAULT,
    replanMin: A.REPLAN_MINUTES, horizonMin: A.PLAN_HORIZON_HOURS * 60,
    required: A.REQUIRED_PIECES_PER_DAY,
    shiftStart: A.SHIFT_START_MINUTE,
    relaxHours: A.RELAX_HOURS,
    spreadRate: A.SPREAD_MIN_PER_LAYER_PER_YARD,
    cutRate: A.CUT_MIN_PER_LAYER_PER_YARD,
    hashOffset: A.C_SETUP_HASH_OFFSET, hashPrime: A.C_SETUP_HASH_PRIME,
    // The defaults ARE the published model, so the tab opens on the same
    // numbers as the Utilization tab. Cutter setup and travel are part of the
    // published floor (2026-11-09, ESTIMATES); every other add-on starts off.
    defaults: {
      plan: 'backlog',
      shift: 'both', dispatch: 'static', seqMode: 'today', moOneGroup: false,
      ruleA: false, mix: false, holdMin: 0, anyWs: true, recall: 'model', colorGroup: false,
      // the live floor (A.LIVE_FLOOR) waits for fabric relaxing (ESTIMATE) and the marker; live: false is the floor of 2026-11-09
      live: A.LIVE_FLOOR, relax: A.LIVE_FLOOR, relaxMinH: A.RELAX_ARRIVAL_LEAD_MIN_H, relaxMaxH: A.RELAX_ARRIVAL_LEAD_MAX_H,
      setupMin: A.CUT_SETUP_MO_COLOR_MINUTES, travelMin: A.CUT_TRAVEL_MINUTES, pullAhead: 0,
      cutters: A.CUTTER_COUNT, tableM: A.SPREADING_TABLE_LENGTH_M,
    },
    // What each add-on is set to when it is switched on (ESTIMATES).
    addOnValues: {
      setupMin: A.CUT_SETUP_MO_COLOR_MINUTES, travelMin: A.CUT_TRAVEL_MINUTES,
      pullAhead: A.PULL_AHEAD_DAYS, holdMin: A.WIP_HOLD_MINUTES,
    },
  };
}

// A published sweep key 'mode|batches|hold|anyWs' as engine options. The
// published model runs batches >= 2 as cross-batch loading and always caps a
// parked trolley at the global 2 batches, so 2 and 3 are identical.
// setupMin and travelMin are left to cfg.defaults (the published cutter setup
// and travel).
function optFromSweepKey(key) {
  const [mode, batches, hold, anyWs] = key.split('|');
  return { plan: 'backlog', shift: 'both', dispatch: 'static', seqMode: mode, moOneGroup: false, ruleA: mode !== 'today',
    mix: +batches >= 2, holdMin: +hold, anyWs: anyWs === '1', recall: 'model', colorGroup: false,
    pullAhead: 0 };
}

function createEngine(cfg) {
  const FILM = cfg.film, CAP = cfg.cap;

  // ------------------------------------------------------------------ util
  function minBy(arr, f) {
    let b = arr[0], bk = f(b);
    for (let i = 1; i < arr.length; i++) { const k = f(arr[i]); if (k < bk) { b = arr[i]; bk = k; } }
    return b;
  }
  const meanOf = a => a.reduce((x, y) => x + y, 0) / a.length;
  function utcDay(s) { const p = s.split('-'); return Date.UTC(+p[0], +p[1] - 1, +p[2]); }
  function fnv1a32(s) {
    const bytes = unescape(encodeURIComponent(s));
    let h = cfg.hashOffset >>> 0;
    for (let i = 0; i < bytes.length; i++) {
      h = (h ^ bytes.charCodeAt(i)) >>> 0;
      h = Math.imul(h, cfg.hashPrime) >>> 0;
    }
    return h >>> 0;
  }

  // ------------------------------------------------------------- shifts
  function intervals(start, end, breaksIn) {
    const breaks = cfg.breaksStop ? breaksIn.slice() : [];
    breaks.sort((a, b) => (a[0] - b[0]) || (a[1] - b[1]));
    const spans = []; let cursor = start;
    for (const [bs, be] of breaks) {
      if (be <= cursor || bs >= end) continue;
      if (bs > cursor) spans.push([cursor, Math.min(bs, end)]);
      cursor = Math.max(cursor, be);
    }
    if (cursor < end) spans.push([cursor, end]);
    return spans;
  }
  function daySpans(shift, night) {
    if (shift === 'day') return intervals(cfg.dayShift[0], cfg.dayShift[1], cfg.dayBreaks);
    if (shift === 'night') {
      return night ? intervals(cfg.nightShift[0], cfg.nightShift[1], cfg.dayBreaks.concat(cfg.nightBreaks)) : [];
    }
    return night
      ? intervals(Math.min(cfg.nightShift[0], cfg.dayShift[0]), cfg.nightShift[1], cfg.dayBreaks.concat(cfg.nightBreaks))
      : intervals(cfg.dayShift[0], cfg.dayShift[1], cfg.dayBreaks);
  }
  function windowOf(shift) {
    if (shift === 'day') return cfg.dayShift;
    if (shift === 'night') return cfg.nightShift;
    return [cfg.dayShift[0], cfg.nightShift[1]];
  }
  function firstSpan(spans, t) {
    let lo = 0, hi = spans.length;
    while (lo < hi) { const mid = (lo + hi) >> 1; if (spans[mid][1] > t) hi = mid; else lo = mid + 1; }
    return lo;
  }
  function advance(spans, t) {
    const i = firstSpan(spans, t);
    return i === spans.length ? t : Math.max(t, spans[i][0]);
  }
  function occupy(spans, start, minutes) {
    let t = advance(spans, start);
    const began = t;
    let left = minutes;
    for (let i = firstSpan(spans, t); i < spans.length; i++) {
      if (left <= 0) break;
      const s = spans[i][0], e = spans[i][1];
      if (e <= t) continue;
      t = Math.max(t, s);
      const room = e - t;
      if (room >= left) return [began, t + left];
      left -= room; t = e;
    }
    return [began, t + left];
  }
  function staffedBetween(spans, a, b) {
    if (b <= a) return 0;
    let s = 0;
    for (let i = firstSpan(spans, a); i < spans.length; i++) {
      if (spans[i][0] >= b) break;
      s += Math.max(0, Math.min(spans[i][1], b) - Math.max(spans[i][0], a));
    }
    return s;
  }

  // ---------------------------------------------- G6 table length (model.js)
  function freeLength(lays, when, L) {
    let used = 0;
    for (const [length, cs, ce] of lays) {
      if (when >= ce) continue;
      if (when <= cs || ce <= cs) used += length;
      else used += length * (ce - when) / (ce - cs);
    }
    return L - used;
  }
  function roomAt(lays, earliest, need, L) {
    if (freeLength(lays, earliest, L) >= need) return earliest;
    const marks = [];
    for (const [, cs, ce] of lays) { if (cs > earliest) marks.push(cs); if (ce > earliest) marks.push(ce); }
    marks.sort((a, b) => a - b);
    let low = earliest;
    for (const mark of marks) {
      if (freeLength(lays, mark, L) >= need) {
        let high = mark;
        for (let i = 0; i < 40; i++) {
          const mid = (low + high) / 2;
          if (freeLength(lays, mid, L) >= need) high = mid; else low = mid;
        }
        return high;
      }
      low = mark;
    }
    let m = earliest;
    for (const [, , ce] of lays) m = Math.max(m, ce);
    return m;
  }

  // ---------------------------------------------- compartments (model.js)
  function compartmentsFor(pieces) {
    const out = new Map();
    for (const size of Object.keys(pieces)) {
      const qty = pieces[size], film = FILM[size];
      const full = Math.floor(qty / CAP), rem = qty - full * CAP;
      if (!out.has(film)) out.set(film, []);
      const list = out.get(film);
      for (let k = 0; k < full; k++) list.push(CAP);
      if (rem) list.push(rem);
    }
    return out;
  }
  function trolleysFor(comps) {
    let n = 0;
    for (const l of comps.values()) if (l.length) n += Math.ceil(l.length / cfg.comps);
    return n;
  }
  function combinedCompartments(a, b) {
    if (a.batch === b.batch) {
      const merged = {};
      for (const s of Object.keys(a.pieces)) merged[s] = a.pieces[s];
      for (const s of Object.keys(b.pieces)) merged[s] = (merged[s] || 0) + b.pieces[s];
      return compartmentsFor(merged);
    }
    const out = new Map();
    for (const t of [a, b]) for (const [film, c] of compartmentsFor(t.pieces)) {
      if (!out.has(film)) out.set(film, []);
      out.get(film).push(...c);
    }
    return out;
  }
  function canCombine(a, b, cross) {
    if (!a.needs || !b.needs) return null;
    if (a.mo !== b.mo || a.color !== b.color) return null;
    if (a.batch !== b.batch && !cross) return null;
    const comps = combinedCompartments(a, b);
    if (trolleysFor(comps) > cfg.maxPerCombine) return null;
    return comps;
  }

  // ----------------------------------------- static Job Sequence (model.js)
  function sumSpread(ts) { return ts.reduce((s, t) => s + t.spread, 0); }
  function clusterBy(tasks, keyFn) {
    const m = new Map();
    for (const t of tasks) { const k = keyFn(t); if (!m.has(k)) m.set(k, []); m.get(k).push(t); }
    return m;
  }
  function pickMachine(cands, load, work, lay) {
    let room = cands.filter(m => load[m] + work <= lay.minutes[m] * cfg.fillTarget);
    if (room.length) return minBy(room, m => load[m]);
    room = lay.spreaders.filter(m => load[m] + work <= lay.minutes[m] * cfg.fillTarget);
    if (room.length) return minBy(room, m => load[m]);
    return minBy(lay.spreaders, m => load[m] / lay.minutes[m]);
  }
  // S0, the real Job Sequence (tools/model.js sequenceJobSeq has the full comment):
  // pass 1 gives every table a cutter, pass 2 lets the least-loaded spreader take the
  // shortest waiting table of its cutters. Same expressions as model.js, in the same order.
  function sequenceJobSeq(tasks, plan, machineLoad, lay) {
    const spreaders = lay.spreaders, primary = lay.primary;
    const cutters = Object.keys(lay.cutGroups);
    const mapOf = m => cfg.flex[m] || [primary[m]];
    const P = cfg.orderPrio;
    const prioOf = t => (Object.prototype.hasOwnProperty.call(P, t.ot) ? P[t.ot] : cfg.orderPrioDefault);

    const spreadCount = {}, raw = {};
    for (const c of cutters) { spreadCount[c] = 0; raw[c] = 0; }
    for (const m of spreaders) { spreadCount[primary[m]] += 1 / mapOf(m).length; raw[primary[m]] += machineLoad[m]; }

    const n = tasks.length;
    const prio = tasks.map(prioOf);
    const order = [];
    for (let i = 0; i < n; i++) order.push(i);
    order.sort((a, b) => prio[a] - prio[b] || a - b);

    const cutterOf = new Array(n);
    const held = new Map();
    for (const i of order) {
      const t = tasks[i];
      const key = t.mo + KEYSEP + t.batch;
      const has = held.get(key);
      const cands = has ? cutters.filter(c => has.has(c)) : cutters;
      const c = minBy(cands, x => raw[x] / spreadCount[x]);
      raw[c] += t.spread;
      cutterOf[i] = c;
      if (!has) held.set(key, new Set([c])); else has.add(c);
    }

    const placed = new Array(n).fill(false);
    let remaining = n;
    const better = (i, j) => prio[i] - prio[j] || tasks[i].spread - tasks[j].spread || i - j;
    while (remaining > 0) {
      const m = minBy(spreaders, x => machineLoad[x]);
      const feeds = mapOf(m);
      let best = -1;
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
      machineLoad[m] += tasks[best].spread;
    }
    return plan;
  }
  // initLoad (optional): minutes of work each spreader already has committed
  // when the day is planned, so the planner balances around the backlog.
  // initCut (optional): staffed minutes each cutter still has to cut. moOneGroup
  // keeps a whole MO + colour on one cut group (the old S1-S3).
  function sequenceDay(tasks, mode, lay, initLoad, initCut, moOneGroup) {
    const groupLoad = {}, machineLoad = {}, plan = {};
    for (const c of Object.keys(lay.cutGroups)) groupLoad[c] = 0;
    for (const m of lay.spreaders) { machineLoad[m] = initLoad ? initLoad[m] : 0; plan[m] = []; }
    if (initLoad) for (const c of Object.keys(lay.cutGroups)) for (const m of lay.cutGroups[c]) groupLoad[c] += machineLoad[m];
    const pickGroup = () => minBy(Object.keys(groupLoad), c => groupLoad[c] / lay.cutGroups[c].length);

    if (mode === 'today') return sequenceJobSeq(tasks, plan, machineLoad, lay);

    // the model's S0 until 2026-11-10 (mode 'today_grouped'; npm run beforeafter only)
    if (mode === 'today_grouped') {
      const groups = Array.from(clusterBy(tasks, t => t.mo + KEYSEP + t.color + KEYSEP + t.batch).values())
        .sort((a, b) => sumSpread(b) - sumSpread(a));
      for (const g of groups) {
        const cg = pickGroup();
        const ordered = g.slice().sort((a, b) => b.spread - a.spread);
        for (const t of ordered) {
          const m = pickMachine(lay.cutGroups[cg], machineLoad, t.spread, lay);
          plan[m].push(t); machineLoad[m] += t.spread; groupLoad[cg] += t.spread;
        }
      }
      return plan;
    }
    const cross = mode === 'cross_batch';
    const passes = cross ? [true, false] : [true];
    const groups = Array.from(clusterBy(tasks, t => t.mo + KEYSEP + t.color).values())
      .sort((a, b) => sumSpread(b) - sumSpread(a));
    const allUnits = [];
    for (const g of groups) {
      const ordered = g.slice().sort((a, b) => {
        if (a.batch < b.batch) return -1;
        if (a.batch > b.batch) return 1;
        return b.spread - a.spread;
      });
      const taken = new Array(ordered.length).fill(false), units = [];
      for (const sameBatchPass of passes) {
        for (let i = 0; i < ordered.length; i++) {
          if (taken[i]) continue;
          for (let j = i + 1; j < ordered.length; j++) {
            if (taken[j]) continue;
            if ((ordered[i].batch === ordered[j].batch) !== sameBatchPass) continue;
            if (canCombine(ordered[i], ordered[j], true)) {
              units.push([ordered[i], ordered[j]]); taken[i] = taken[j] = true; break;
            }
          }
        }
      }
      for (let i = 0; i < ordered.length; i++) if (!taken[i]) units.push([ordered[i]]);
      if (!moOneGroup) { for (const u of units) allUnits.push(u); continue; }
      const cg = pickGroup();
      for (const u of units.slice().sort((a, b) => sumSpread(b) - sumSpread(a))) {
        const work = sumSpread(u);
        const m = pickMachine(lay.cutGroups[cg], machineLoad, work, lay);
        plan[m].push(...u); machineLoad[m] += work; groupLoad[cg] += work;
      }
    }
    if (moOneGroup) return plan;
    // The pairs rule (model.js sequencePairs): every unit of the day, largest
    // first, to the cut group least busy on its busier side, spreading or cutting.
    const cutters = Object.keys(lay.cutGroups);
    const spCap = {}, cutLoad = {};
    for (const c of cutters) {
      spCap[c] = 0;
      for (const m of lay.cutGroups[c]) spCap[c] += lay.minutes[m];
      cutLoad[c] = initCut ? initCut[c] : 0;
    }
    const groupOf = {};
    for (const c of cutters) for (const m of lay.cutGroups[c]) groupOf[m] = c;
    for (const u of allUnits.slice().sort((a, b) => sumSpread(b) - sumSpread(a))) {
      const work = sumSpread(u);
      const cw = u.reduce((s, t) => s + t.cut, 0);
      const cg = minBy(cutters, c => Math.max((groupLoad[c] + work) / spCap[c], (cutLoad[c] + cw) / lay.cutMinutes[c]));
      const m = pickMachine(lay.cutGroups[cg], machineLoad, work, lay);
      const g = groupOf[m];   // pickMachine can leave the group (Q8): credit the machine's real one
      plan[m].push(...u); machineLoad[m] += work; groupLoad[g] += work; cutLoad[g] += cw;
    }
    return plan;
  }

  // ----------------------------------------------------------- simulate
  // Stage 1: sequence + timeline. Depends on the dispatch and the add-ons, not
  // on loading, so it is cached per (input, these options).
  const simCache = new WeakMap();
  function simKey(o) {
    const dyn = o.dispatch === 'dynamic';
    return JSON.stringify([o.shift, o.dispatch, o.plan, dyn ? [o.ruleA, o.mix, o.colorGroup] : (o.seqMode === 'today' ? 'today' : [o.seqMode, !!o.moOneGroup]),
      o.relax, o.relaxMinH, o.relaxMaxH, o.setupMin, o.travelMin, o.pullAhead, !!o.live, o.cutters, o.tableM]);
  }

  function simulate(input, o) {
    const dates = input.dates, nDays = dates.length, day0 = utcDay(dates[0]);
    const off = dates.map(d => (utcDay(d) - day0) / 60000);
    const sumSpan = ds => ds.reduce((s, [a, b]) => s + (b - a), 0);

    // --- machines for the chosen shift option
    const nightSp = new Set(cfg.nightSpreaders), nightCu = new Set(cfg.nightCutters);
    // the floor of this run: the chosen cutter count's groups and table length (the same expression
    // as A.SPREADING_TABLE_LENGTH, so today's floor is bit-identical)
    const cutGroups = cfg.cutGroupsByCount[o.cutters] || cfg.cutGroups;
    const tableLen = o.tableM * cfg.yardsPerMetre;
    const allSpreaders = [], allCutters = Object.keys(cutGroups);
    for (const c of allCutters) for (const m of cutGroups[c]) allSpreaders.push(m);
    const perDayMin = {}, cuDayMin = {};
    let spCap = 0, cuCap = 0, totSpread = 0, totCut = 0;
    for (const m of allSpreaders) { perDayMin[m] = sumSpan(daySpans(o.shift, nightSp.has(m))); spCap += perDayMin[m]; }
    for (const c of allCutters) { cuDayMin[c] = sumSpan(daySpans(o.shift, nightCu.has(c))); cuCap += cuDayMin[c]; }
    for (const d of dates) for (const t of input.tasks[d]) { totSpread += t.spread; totCut += t.cut; }
    const activeCutters = allCutters.filter(c => cuDayMin[c] > 0);
    const activeSet = new Set(activeCutters);
    const primary = {};
    for (const c of allCutters) for (const m of cutGroups[c]) primary[m] = c;
    const spreaders = allSpreaders.filter(m => perDayMin[m] > 0 && activeSet.has(primary[m]));
    if (!spreaders.length) throw new Error('no machine is staffed in this shift option');
    const groupMembers = {};
    for (const c of allCutters) groupMembers[c] = cutGroups[c].filter(m => spreaders.indexOf(m) >= 0);
    const flexOf = {};
    for (const m of spreaders) {
      flexOf[m] = (cfg.flex[m] || [primary[m]]).filter(c => activeSet.has(c));
      if (!flexOf[m].length) flexOf[m] = [primary[m]];
    }

    // Synthetic shift days after the last plan date, sized to the work, so even
    // a shift option that cannot clear the plan (night only) finishes on
    // staffed hours instead of spilling onto the raw clock.
    const extra = Math.min(3000, Math.ceil(2 * Math.max(totSpread / (spCap || 1), totCut / (cuCap || 1))) + 14);
    const contOffsets = off.slice();
    for (let k = 1; k <= extra; k++) contOffsets.push(off[nDays - 1] + k * 1440);
    const mkSpans = (night, offsets) => {
      const ds = daySpans(o.shift, night), out = [];
      if (ds.length) for (const x of offsets) for (const [a, b] of ds) out.push([x + a, x + b]);
      return out;
    };
    const contSp = {}, contCu = {};
    const spreaderSpans = m => contSp[m] || (contSp[m] = mkSpans(nightSp.has(m), contOffsets));
    const cutterSpans = c => contCu[c] || (contCu[c] = mkSpans(nightCu.has(c), contOffsets));

    // --- tasks and fabric readiness (absolute minutes from the first plan date's 07:15)
    const tasks = [];
    dates.forEach((d, di) => {
      for (const t of input.tasks[d]) tasks.push(Object.assign({}, t, { date: d, dayIdx: di, id: tasks.length }));
    });
    const firstSeen = {};
    for (const t of tasks) if (firstSeen[t.batch] === undefined) firstSeen[t.batch] = t.date;
    const spanMin = Math.round((o.relaxMaxH - o.relaxMinH) * 60);
    const readyOf = {};
    for (const t of tasks) {
      if (readyOf[t.batch] === undefined) {
        if (!o.relax) readyOf[t.batch] = -Infinity;
        else {
          const first = (utcDay((input.batchFirst && input.batchFirst[t.batch]) || firstSeen[t.batch]) - day0) / 60000;
          const lead = Math.round(o.relaxMinH * 60) + (fnv1a32('relax|' + t.batch) % (spanMin + 1));
          readyOf[t.batch] = first - lead + cfg.relaxHours * 60;
        }
      }
      t.readyAbs = readyOf[t.batch];
    }

    const seqMode = o.seqMode || (!o.ruleA ? 'today' : (o.mix ? 'cross_batch' : 'same_batch'));
    const staticLay = { cutGroups: {}, spreaders, minutes: perDayMin, cutMinutes: cuDayMin, primary };
    for (const c of allCutters) if (groupMembers[c].length) staticLay.cutGroups[c] = groupMembers[c];

    const cmpKey = (a, b) => { for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] - b[i]; return 0; };
    const sameMoBatch = (a, b) => !!a && a.mo === b.mo && a.batch === b.batch;
    const sameMoColor = (a, b) => !!a && a.mo === b.mo && a.color === b.color;

    // the end of each spreader's own staffed window on a plan date
    const lastEnd = {};
    for (const m of spreaders) { const ds = daySpans(o.shift, nightSp.has(m)); lastEnd[m] = ds[ds.length - 1][1]; }

    // One segment, the whole run (kept as a list so finish() sums segments).
    function runSegment(segTasks, base) {
      const spSp = {}, cuSp = {};
      for (const m of spreaders) spSp[m] = spreaderSpans(m);
      for (const c of activeCutters) cuSp[c] = cutterSpans(c);
      for (const t of segTasks) {
        t.relDay = off[Math.max(0, t.dayIdx - o.pullAhead)];
        t.rel = Math.max(t.relDay, t.readyAbs - base);
        // the live floor also waits for the marker (Marker Date, minutes after its plan date's 07:15)
        if (o.live && o.dispatch === 'static') t.rel = Math.max(t.rel, off[t.dayIdx] + t.mk);
      }
      const free = {}, spBusy = {}, spBlocked = {}, spStarved = {}, lays = {}, lastSpread = {}, seq = {};
      const starvedIv = {};
      for (const m of spreaders) {
        free[m] = 0; spBusy[m] = 0; spBlocked[m] = 0; spStarved[m] = 0;
        lays[m] = []; lastSpread[m] = null; seq[m] = []; starvedIv[m] = [];
      }
      const cutFree = {}, cuBusy = {}, cuSetup = {}, cuTravel = {}, lastCut = {};
      for (const c of activeCutters) { cutFree[c] = 0; cuBusy[c] = 0; cuSetup[c] = 0; cuTravel[c] = 0; lastCut[c] = null; }

      function dispatch(m, t) {
        const eff = advance(spSp[m], free[m]);
        lays[m] = lays[m].filter(l => l[2] > eff);
        const start = roomAt(lays[m], eff, t.len, tableLen);
        t.blockFrom = eff;
        t.blockedStaffed = staffedBetween(spSp[m], eff, start);
        spBlocked[m] += t.blockedStaffed;
        const [sb, se] = occupy(spSp[m], start, t.spread);
        spBusy[m] += t.spread;
        free[m] = se;
        // spreading still going after the machine's window on the plan date
        const winEnd = off[t.dayIdx] + lastEnd[m];
        t.pastWindow = se > winEnd;
        t.overrun = t.pastWindow ? staffedBetween(spSp[m], Math.max(sb, winEnd), se) : 0;
        const cutter = minBy(flexOf[m], c => cutFree[c]);
        t.cutWait = Math.max(0, se - cutFree[cutter]);
        const lc = lastCut[cutter];
        const setup = lc && (lc.mo !== t.mo || lc.color !== t.color) ? o.setupMin : 0;
        const travel = lc && lc.machine !== m ? o.travelMin : 0;
        const [cb, ce] = occupy(cuSp[cutter], Math.max(se, cutFree[cutter]), t.cut + setup + travel);
        cuBusy[cutter] += t.cut; cuSetup[cutter] += setup; cuTravel[cutter] += travel;
        cutFree[cutter] = ce;
        lastCut[cutter] = { mo: t.mo, color: t.color, machine: m };
        lays[m].push([t.len, Math.min(ce, cb + setup + travel), ce]);
        t.m = m; t.cutter = cutter; t.sb = sb; t.se = se; t.cb = cb; t.ce = ce; t.setup = setup; t.travel = travel;
        lastSpread[m] = t;
        seq[m].push(t);
      }

      // The live floor: tools/floor.js, the same timeline model.js runs (re-plan every
      // cfg.replanMin, tables start once ready, a free cutter takes the longest-waiting lay).
      const liveFloor = !!o.live && o.dispatch === 'static';
      if (liveFloor) {
        const res = Floor.run({
          spreaders, cutters: activeCutters, primary, flexOf, spSp, cuSp,
          tableLength: tableLen, setupMin: o.setupMin, travelMin: o.travelMin,
          tasks: segTasks, tickMin: cfg.replanMin, horizonMin: cfg.horizonMin,
          seqFn: (group, init, initCut) => sequenceDay(group, seqMode, staticLay, init, initCut, o.moOneGroup),
          isPair: seqMode === 'today' ? undefined
            : (a, b) => (seqMode === 'cross_batch' || a.batch === b.batch) && !!canCombine(a, b, true),
          get: { rel: t => t.rel, spread: t => t.spread, cut: t => t.cut, len: t => t.len,
            mo: t => t.mo, color: t => t.color, day: t => t.dayIdx },
          put: (t, r) => Object.assign(t, r),
        });
        for (const m of spreaders) {
          seq[m] = res.seq[m]; spBusy[m] = res.spBusy[m]; spBlocked[m] = res.spBlocked[m];
          spStarved[m] = res.spStarved[m]; starvedIv[m] = res.starvedIv[m];
        }
        for (const c of activeCutters) { cuBusy[c] = res.cuBusy[c]; cuSetup[c] = res.cuSetup[c]; cuTravel[c] = res.cuTravel[c]; }
        for (const t of segTasks) {
          const winEnd = off[t.dayIdx] + lastEnd[t.m];
          t.pastWindow = t.se > winEnd;
          t.overrun = t.pastWindow ? staffedBetween(spSp[t.m], Math.max(t.sb, winEnd), t.se) : 0;
        }
      } else {
      // plan 'backlog' (continuous, fixed queue): each plan date is sequenced on
      // the morning it starts, around the work every machine still has left from
      // the days before, and run before the next date is planned.
      const backlogPlan = o.plan === 'backlog' && o.dispatch === 'static';
      let queue = null, qPtr = null, qLeft = null, pool = null;
      const byDay = new Map();
      for (const t of segTasks) { if (!byDay.has(t.dayIdx)) byDay.set(t.dayIdx, []); byDay.get(t.dayIdx).push(t); }
      const dayOrder = Array.from(byDay.keys()).sort((a, b) => a - b);
      if (o.dispatch === 'static') {
        queue = {}; qPtr = {}; qLeft = {};
        for (const m of spreaders) { queue[m] = []; qPtr[m] = 0; qLeft[m] = 0; }
        if (!backlogPlan) {
          for (const di of dayOrder) {
            const plan = sequenceDay(byDay.get(di), seqMode, staticLay, undefined, undefined, o.moOneGroup);
            for (const m of spreaders) for (const t of plan[m]) { queue[m].push(t); qLeft[m] += 1; }
          }
        }
      } else pool = segTasks.slice();

      function pickDynamic(m, tm) {
        const last = lastSpread[m];
        let recent = null;
        if (o.colorGroup) {
          recent = new Set();
          for (const g of groupMembers[primary[m]]) { const lt = lastSpread[g]; if (lt) recent.add(lt.mo + KEYSEP + lt.color); }
          const lc = lastCut[primary[m]]; if (lc) recent.add(lc.mo + KEYSEP + lc.color);
        }
        let best = -1, bestKey = null;
        for (let j = 0; j < pool.length; j++) {
          const x = pool[j];
          if (x.relDay > tm) break;
          if (x.rel > tm) continue;
          const key = [
            x.dayIdx,
            o.ruleA ? (sameMoBatch(last, x) ? 0 : 1) : 0,
            (o.ruleA && o.mix) ? (sameMoColor(last, x) ? 0 : 1) : 0,
            recent ? (recent.has(x.mo + KEYSEP + x.color) ? 0 : 1) : 0,
            -x.spread, x.id,
          ];
          if (best < 0 || cmpKey(key, bestKey) < 0) { best = j; bestKey = key; }
        }
        return best;
      }
      // Rule (a), dynamic: once a table is chosen, its partner (same MO + batch
      // first, then same MO + colour if mixing) is spread right after it on the
      // same spreader, but only if the partner is already released.
      function pickPartner(x, tm) {
        if (!x.needs) return -1;
        let best = -1, bestKey = null;
        for (let j = 0; j < pool.length; j++) {
          const y = pool[j];
          if (y.relDay > tm) break;
          if (y.rel > tm || !y.needs) continue;
          if (y.mo !== x.mo || y.color !== x.color) continue;
          if (y.batch !== x.batch && !o.mix) continue;
          if (!canCombine(x, y, o.mix)) continue;
          const key = [y.batch === x.batch ? 0 : 1, y.dayIdx, y.id];
          if (best < 0 || cmpKey(key, bestKey) < 0) { best = j; bestKey = key; }
        }
        return best;
      }

      let remaining = segTasks.length, guard = 0;
      const done = new Set();
      function drain(){
      while (remaining > 0) {
        if (++guard > segTasks.length * 40 + 1000) throw new Error('lab engine did not converge');
        const cands = o.dispatch === 'static' ? spreaders.filter(m => qLeft[m] > 0) : spreaders;
        // The spreader is picked by the next instant it is actually staffed.
        const m = minBy(cands, mm => advance(spSp[mm], free[mm]));
        const tm = advance(spSp[m], free[m]);

        if (o.dispatch === 'static') {
          const q = queue[m];
          let pick = -1, nextRel = Infinity;
          for (let j = qPtr[m]; j < q.length; j++) {
            if (done.has(q[j].id)) { if (j === qPtr[m]) qPtr[m] += 1; continue; }
            if (q[j].rel <= tm) { pick = j; break; }
            if (q[j].rel < nextRel) nextRel = q[j].rel;
          }
          if (pick < 0) {
            for (let j = qPtr[m]; j < q.length; j++) if (!done.has(q[j].id) && q[j].rel < nextRel) nextRel = q[j].rel;
            spStarved[m] += staffedBetween(spSp[m], tm, nextRel);
            starvedIv[m].push([tm, nextRel]);
            free[m] = nextRel;
            continue;
          }
          const t = q[pick];
          done.add(t.id); qLeft[m] -= 1; remaining -= 1;
          dispatch(m, t);
        } else {
          const j = pickDynamic(m, tm);
          if (j < 0) {
            let nextRel = Infinity;
            for (const x of pool) if (x.rel < nextRel) nextRel = x.rel;
            spStarved[m] += staffedBetween(spSp[m], tm, nextRel);
            starvedIv[m].push([tm, nextRel]);
            free[m] = nextRel;
            continue;
          }
          const t = pool.splice(j, 1)[0];
          remaining -= 1;
          dispatch(m, t);
          if (o.ruleA) {
            const pj = pickPartner(t, tm);
            if (pj >= 0) { const y = pool.splice(pj, 1)[0]; remaining -= 1; dispatch(m, y); }
          }
        }
      }
      }
      if (backlogPlan) {
        for (const di of dayOrder) {
          const t0 = off[di];
          const init = {};
          for (const m of spreaders) init[m] = staffedBetween(spSp[m], t0, free[m]);
          const initCut = {};
          for (const c of Object.keys(staticLay.cutGroups)) initCut[c] = staffedBetween(cuSp[c], t0, cutFree[c]);
          const plan = sequenceDay(byDay.get(di), seqMode, staticLay, init, initCut, o.moOneGroup);
          for (const m of spreaders) { queue[m] = []; qPtr[m] = 0; qLeft[m] = 0; }
          for (const m of spreaders) for (const t of plan[m]) { queue[m].push(t); qLeft[m] += 1; }
          remaining = byDay.get(di).length;
          drain();
        }
      } else drain();
      }

      // --- segment results
      let F = 0;
      for (const t of segTasks) if (t.ce > F) F = t.ce;
      const spM = spreaders.map(m => {
        const staffed = staffedBetween(spSp[m], 0, F);
        return { m, staffed, busy: spBusy[m], blocked: spBlocked[m], starved: spStarved[m],
          idle: Math.max(0, staffed - spBusy[m] - spBlocked[m] - spStarved[m]) };
      });
      const cuM = activeCutters.map(c => {
        const staffed = staffedBetween(cuSp[c], 0, F);
        return { c, staffed, cut: cuBusy[c], setup: cuSetup[c], travel: cuTravel[c],
          idle: Math.max(0, staffed - cuBusy[c] - cuSetup[c] - cuTravel[c]) };
      });
      return { tasks: segTasks, base, seq, F, spM, cuM, starvedIv };
    }

    const segs = [runSegment(tasks, 0)];

    // absolute stamps, so every later step (and the page) can use one clock
    for (const sg of segs) for (const t of sg.tasks) {
      t.sbA = t.sb + sg.base; t.seA = t.se + sg.base; t.cbA = t.cb + sg.base; t.ceA = t.ce + sg.base;
      t.blockFromA = t.blockFrom + sg.base;
    }
    return { segs, tasks, off, dates, nDays, spreaders, activeCutters, groupMembers, primary,
      winOff: contOffsets };
  }

  // ------------------------------------------------------------- loading
  function srcOf(ev, film, idx) {
    // which batch and tables a compartment of this event came from
    if (!ev.pair) return { batch: ev.single.batch, tasks: [ev.single.id] };
    const [a, b] = ev.pair;
    if (a.batch === b.batch) return { batch: a.batch, tasks: [a.id, b.id] };
    const na = (compartmentsFor(a.pieces).get(film) || []).length;
    return idx < na ? { batch: a.batch, tasks: [a.id] } : { batch: b.batch, tasks: [b.id] };
  }
  function loadingEvents(seq, cross) {
    const events = [];
    for (const m of Object.keys(seq)) {
      const q = seq[m]; let i = 0;
      while (i < q.length) {
        if (!q[i].needs) { i++; continue; }
        const pair = (i + 1 < q.length && q[i + 1].date === q[i].date) ? canCombine(q[i], q[i + 1], cross) : null;
        if (pair) {
          events.push({ when: Math.max(q[i].ce, q[i + 1].ce), comps: pair, batches: new Set([q[i].batch, q[i + 1].batch]),
            mo: q[i].mo, color: q[i].color, machine: m, pair: [q[i], q[i + 1]] });
          i += 2;
        } else {
          events.push({ when: q[i].ce, comps: compartmentsFor(q[i].pieces), batches: new Set([q[i].batch]),
            mo: q[i].mo, color: q[i].color, machine: m, single: q[i] });
          i += 1;
        }
      }
    }
    events.sort((a, b) => a.when - b.when);
    return events;
  }
  function intersects(a, b) { for (const x of a) if (b.has(x)) return true; return false; }

  // Rule (c). recall 'model': the published order (any batch, 2-batch cap).
  // 'sameFirst': a parked trolley already holding one of the event's batches is
  // recalled first, other-batch trolleys after it. 'sameOnly': same batch only.
  function loadTrolleys(seq, o, base) {
    const events = loadingEvents(seq, o.mix);
    const hold = o.holdMin;
    const parked = new Map();
    const parkedNow = () => { let n = 0; for (const v of parked.values()) n += v.length; return n; };
    let compartments = 0, trolleys = 0, pieces = 0, combines = 0, recallsSame = 0, recallsCross = 0, blockedBySpace = 0;
    const waits = [], records = [], pairs = [];

    for (const ev of events) {
      if (ev.batches.size > 1) combines += 1;
      if (ev.pair) pairs.push([ev.pair[0].id, ev.pair[1].id]);
      for (const key of Array.from(parked.keys())) {
        const keep = [];
        for (const tr of parked.get(key)) {
          if (ev.when - tr.at <= hold) keep.push(tr);
          else { waits.push(ev.when - tr.at); tr.rec.leftAt = tr.at + hold + base; }
        }
        parked.set(key, keep);
      }
      for (const [film, list] of ev.comps) {
        if (!list.length) continue;
        compartments += list.length;
        for (const q of list) pieces += q;
        let key = ev.mo + KEYSEP + ev.color + KEYSEP + film;
        if (!o.anyWs) key += KEYSEP + ev.machine;
        const items = list.map((q, i) => Object.assign({ qty: q, recalled: null }, srcOf(ev, film, i)));
        let cursor = 0, need = list.length;
        const arr = parked.get(key) || [];
        let cands = arr;
        if (o.recall !== 'model') {
          const same = arr.filter(tr => intersects(tr.batches, ev.batches));
          cands = o.recall === 'sameOnly' ? same : same.concat(arr.filter(tr => !intersects(tr.batches, ev.batches)));
        }
        for (const tr of cands) {
          if (need === 0) break;
          const would = new Set([...tr.batches, ...ev.batches]);
          if (would.size > cfg.maxBatches) continue;
          const take = Math.min(tr.free, need);
          if (take === 0) continue;
          const kind = intersects(tr.batches, ev.batches) ? 'same' : 'cross';
          if (kind === 'same') recallsSame += 1; else recallsCross += 1;
          for (const it of items.slice(cursor, cursor + take)) { it.recalled = kind; tr.rec.comps.push(it); }
          cursor += take;
          tr.free -= take; tr.batches = would; need -= take;
          tr.rec.batches = Array.from(would);
          if (tr.free === 0) tr.rec.leftAt = ev.when + base;
        }
        parked.set(key, arr.filter(t => t.free > 0));
        while (need > 0) {
          const take = Math.min(cfg.comps, need);
          need -= take; trolleys += 1;
          const rec = { film, mo: ev.mo, color: ev.color, openedAt: ev.when + base, leftAt: ev.when + base,
            batches: Array.from(ev.batches), comps: items.slice(cursor, cursor + take) };
          cursor += take;
          records.push(rec);
          const spare = cfg.comps - take;
          if (spare && hold > 0) {
            if (parkedNow() < cfg.bays) {
              const cur = parked.get(key) || [];
              rec.leftAt = null;
              cur.push({ free: spare, at: ev.when, batches: new Set(ev.batches), rec });
              parked.set(key, cur);
            } else blockedBySpace += 1;
          }
        }
      }
    }
    for (const v of parked.values()) for (const tr of v) if (tr.rec.leftAt === null) tr.rec.leftAt = tr.at + hold + base;
    return { compartments, trolleys, pieces, combines, recallsSame, recallsCross, blockedBySpace,
      avgWaitH: waits.length ? meanOf(waits) / 60 : 0, records, pairs };
  }

  // ------------------------------------------------------------- results
  function finish(sim, o) {
    const nDays = sim.nDays, off = sim.off, dates = sim.dates;
    const win = windowOf(o.shift);
    // Loading is per plan date, as in the published model: a date's tables are
    // loaded in the order they finish cutting, and parked trolleys do not carry
    // into the next plan date's loading.
    const per = [];
    for (const sg of sim.segs) {
      const byDay = new Map();
      for (const m of sim.spreaders) for (const t of sg.seq[m]) {
        if (!byDay.has(t.dayIdx)) { const s = {}; for (const mm of sim.spreaders) s[mm] = []; byDay.set(t.dayIdx, s); }
        byDay.get(t.dayIdx)[m].push(t);
      }
      for (const di of Array.from(byDay.keys()).sort((a, b) => a - b)) per.push(loadTrolleys(byDay.get(di), o, sg.base));
    }
    const sum = (arr, k) => arr.reduce((s, x) => s + x[k], 0);
    const comps = sum(per, 'compartments'), trolleys = sum(per, 'trolleys'), pieces = sum(per, 'pieces');

    // machine time: summed over segments
    const spMap = {}, cuMap = {};
    for (const sg of sim.segs) {
      for (const x of sg.spM) { const a = spMap[x.m] || (spMap[x.m] = { m: x.m, staffed: 0, busy: 0, blocked: 0, starved: 0, idle: 0 });
        for (const k of ['staffed', 'busy', 'blocked', 'starved', 'idle']) a[k] += x[k]; }
      for (const x of sg.cuM) { const a = cuMap[x.c] || (cuMap[x.c] = { c: x.c, staffed: 0, cut: 0, setup: 0, travel: 0, idle: 0 });
        for (const k of ['staffed', 'cut', 'setup', 'travel', 'idle']) a[k] += x[k]; }
    }
    const spM = sim.spreaders.map(m => spMap[m]), cuM = sim.activeCutters.map(c => cuMap[c]);

    let F = 0;
    for (const t of sim.tasks) if (t.ceA > F) F = t.ceA;
    let shiftMin = 0;
    for (const x of sim.winOff) shiftMin += Math.max(0, Math.min(x + win[1], F) - Math.max(x + win[0], 0));

    const perDay = dates.map(d => ({ date: d, planned: 0, cut: 0, onTime: 0, doneMin: 0, plannedPieces: 0, cutPieces: 0 }));
    let onTime = 0, early = 0, backlog = 0, backlogPieces = 0, totalPieces = 0, cutInPeriod = 0;
    const lastEnd = off[nDays - 1] + win[1];
    for (const t of sim.tasks) {
      const pd = perDay[t.dayIdx];
      pd.planned += 1;
      pd.plannedPieces += t.pt; totalPieces += t.pt;
      pd.doneMin = Math.max(pd.doneMin, t.ceA - off[t.dayIdx]);
      if (t.ceA <= off[t.dayIdx] + win[1]) { pd.onTime += 1; onTime += 1; }
      if (t.sbA < off[t.dayIdx]) early += 1;
      let di = 0;
      for (let k = nDays - 1; k >= 0; k--) if (off[k] <= t.ceA) { di = k; break; }
      perDay[di].cut += 1;
      if (t.ceA > lastEnd) { backlog += 1; backlogPieces += t.pt; }
      else { perDay[di].cutPieces += t.pt; cutInPeriod += t.pt; }
    }
    let daysMeeting = 0;
    for (const x of perDay) if (x.cutPieces >= cfg.required) daysMeeting += 1;

    const starved = {};
    for (const sg of sim.segs) for (const m of Object.keys(sg.starvedIv)) {
      for (const [a, b] of sg.starvedIv[m]) (starved[m] || (starved[m] = [])).push([a + sg.base, b + sg.base]);
    }
    const trolleyRecs = [];
    per.forEach((p, k) => { for (const r of p.records) trolleyRecs.push(r); });
    const pairs = [];
    for (const p of per) for (const x of p.pairs) pairs.push(x);

    // Idle-time figures as the published model reports them: means of daily
    // values, from the tables each plan date planned.
    const byD = dates.map(() => []);
    for (const t of sim.tasks) byD[t.dayIdx].push(t);
    const rows = byD.map((ts, di) => {
      let sB = 0, sBl = 0, cB = 0, cW = 0, last = 0, ov = 0; const over = new Set();
      for (const t of ts) {
        sB += t.spread; sBl += t.blockedStaffed; cB += t.cut; cW += t.cutWait;
        last = Math.max(last, t.se); ov += t.overrun; if (t.pastWindow) over.add(t.m);
      }
      return { sPct: (sB + sBl) ? 100 * sBl / (sB + sBl) : 0, cPct: (cB + cW) ? 100 * cW / (cB + cW) : 0,
        make: ts.length ? (last - off[di]) / 60 : 0, blocked: sBl, overrun: ov, over: over.size };
    });
    const idleM = {
      spreadingBlockedPct: meanOf(rows.map(r => r.sPct)), cuttingBlockedPct: meanOf(rows.map(r => r.cPct)),
      spreadingMakespanH: meanOf(rows.map(r => r.make)), spreadingBlockedMin: meanOf(rows.map(r => r.blocked)),
      spreadingOverrunMin: meanOf(rows.map(r => r.overrun)), machinesOverWindow: meanOf(rows.map(r => r.over)),
    };
    const res = {
      tasks: sim.tasks.length, days: nDays,
      // published-model fields (means of daily values, as model.run() / runCarry() report them)
      model: Object.assign(idleM, { avgWaitH: meanOf(per.map(p => p.avgWaitH)), peak: Math.max(...per.map(p => p.trolleys)) }),
      finishMin: F, finishHours: shiftMin / 60, dayWindowHours: (win[1] - win[0]) / 60,
      tablesPerShiftHour: shiftMin ? sim.tasks.length / (shiftMin / 60) : 0,
      onTimePct: 100 * onTime / sim.tasks.length, earlyPct: 100 * early / sim.tasks.length,
      backlogTables: backlog, backlogHours: Math.max(0, F - lastEnd) / 60,
      dayDoneMeanMin: perDay.reduce((s, x) => s + x.doneMin, 0) / nDays,
      // Output in pieces (every piece cut, ratio x layers): planned and actually cut
      // inside the plan period, against cfg.required a day.
      output: {
        required: cfg.required, totalPieces, plannedPerDay: totalPieces / nDays,
        cutPerDay: cutInPeriod / nDays, backlogPieces, daysMeeting,
        piecesPerShiftHour: shiftMin ? totalPieces / (shiftMin / 60) : 0,
        hoursPer100k: totalPieces ? (shiftMin / 60) / (totalPieces / cfg.required) : 0,
      },
      trolleys, compartments: comps, pieces,
      utilizationPct: 100 * comps / (cfg.comps * trolleys),
      trolleysPerDay: trolleys / nDays, compartmentsPerDay: comps / nDays,
      fillPct: 100 * pieces / (CAP * comps),
      garmentsCapacity: CAP * comps / trolleys, piecesPerTrolley: pieces / trolleys,
      combines: sum(per, 'combines'), recallsSame: sum(per, 'recallsSame'), recallsCross: sum(per, 'recallsCross'),
      avgWaitH: meanOf(per.map(p => p.avgWaitH)), blockedBySpace: sum(per, 'blockedBySpace'),
      sp: { staffed: sum(spM, 'staffed'), busy: sum(spM, 'busy'), blocked: sum(spM, 'blocked'),
            starved: sum(spM, 'starved'), idle: sum(spM, 'idle') },
      cu: { staffed: sum(cuM, 'staffed'), cut: sum(cuM, 'cut'), setup: sum(cuM, 'setup'),
            travel: sum(cuM, 'travel'), idle: sum(cuM, 'idle') },
      spM, cuM, perDay,
      cutMinutes: sim.tasks.reduce((s, t) => s + t.cut, 0),
      // the arrangement, for the page's Gantt and Panel Loading
      detail: { tasks: sim.tasks, starved, pairs, trolleys: trolleyRecs, off, dates, win,
        spreaders: sim.spreaders, cutters: sim.activeCutters, groupMembers: sim.groupMembers },
    };
    return res;
  }

  function run(input, optIn) {
    const o = Object.assign({}, cfg.defaults, optIn || {});
    let byKey = simCache.get(input);
    if (!byKey) { byKey = new Map(); simCache.set(input, byKey); }
    const k = simKey(o);
    let sim = byKey.get(k);
    if (!sim) { sim = simulate(input, o); byKey.set(k, sim); }
    return finish(sim, o);
  }

  // The 100k-a-day plan: the real tables, in plan order, dealt into plan dates
  // that each close once they hold cfg.required pieces. Dates reuse the real
  // calendar in order. The tail that cannot fill a last date is left out, so
  // every date holds at least the requirement. Each batch's first plan date is
  // recomputed from the new dates, so fabric relaxing stays meaningful.
  const plan100Cache = new WeakMap();
  function rebucket(input) {
    let r = plan100Cache.get(input);
    if (r) return r;
    const buckets = [[]]; let sum = 0, dropped = 0;
    for (const d of input.dates) for (const t of input.tasks[d]) {
      buckets[buckets.length - 1].push(t); sum += t.pt;
      if (sum >= cfg.required) { buckets.push([]); sum = 0; }
    }
    const tail = buckets.pop();
    dropped = tail.length;
    const dates = [], tasks = {}, batchFirst = {};
    let last = input.dates[input.dates.length - 1];
    buckets.forEach((b, k) => {
      let date;
      if (k < input.dates.length) date = input.dates[k];
      else { const u = new Date(utcDay(last) + 86400000); date = u.toISOString().slice(0, 10); last = date; }
      dates.push(date);
      tasks[date] = b.map((t, i) => Object.assign({}, t, { i }));
      for (const t of b) if (batchFirst[t.batch] === undefined) batchFirst[t.batch] = date;
    });
    r = { dates, tasks, batchFirst, droppedTables: dropped };
    plan100Cache.set(input, r);
    return r;
  }
  function run100k(input, optIn) { return run(rebucket(input), optIn); }

  return { run, run100k, rebucket, fnv1a32, sequenceDay, canCombine, compartmentsFor, daySpans, windowOf };
}

// The ladder: the four published scenarios, then each new rule the user has
// switched on, added on top of the one before. Every row runs on the SAME floor:
// shift, fabric relaxing, cutter setup and travel come from the
// selection (they are facts about the floor, not logic), so S0 has them too and
// the steps differ only by the rule they add.
function ladder(sel, vals) {
  const base = { plan: 'backlog', shift: sel.shift, dispatch: 'static', seqMode: 'today', moOneGroup: !!sel.moOneGroup,
    ruleA: false, mix: false, holdMin: 0, anyWs: true, recall: 'model', colorGroup: false, relax: !!sel.relax,
    relaxMinH: sel.relaxMinH, relaxMaxH: sel.relaxMaxH, setupMin: sel.setupMin || 0, travelMin: sel.travelMin || 0, pullAhead: 0 };
  const steps = [
    ['S0 Today', {}],
    ['S1 + same-MO sequencing', { seqMode: 'same_batch', ruleA: true }],
    ['S2 + 2 batches per trolley', { seqMode: 'cross_batch', mix: true }],
    ['S3 + WIP hold', { holdMin: sel.holdMin || vals.holdMin, anyWs: true }],
  ];
  if (sel.recall !== 'model') steps.push(['+ same-batch recall', { recall: sel.recall }]);
  if (sel.pullAhead > 0) steps.push(['+ pull-ahead', { pullAhead: sel.pullAhead }]);
  // (the Dynamic spreader pick and Keep same colour close were removed from the Lab, user, 2026-11-10;
  // the engine's dormant paths for them are reachable only by passing dispatch: 'dynamic' directly)
  let acc = base;
  return steps.map(([name, patch]) => { acc = Object.assign({}, acc, patch); return { name, opt: acc }; });
}

// Rebuild the engine's task input from daytrace.js labData()'s columnar form.
// Spread and cut minutes are recomputed with model.js's exact operation order
// (layers * rate * len + setup), so the result equals model.js's raw tasks.
function decode(d, cfg) {
  const tasks = {};
  for (const date of d.dates) tasks[date] = [];
  const n = d.t.d.length;
  for (let k = 0; k < n; k++) {
    const list = tasks[d.dates[d.t.d[k]]];
    const layers = d.t.ly[k], len = d.t.ml[k], setup = d.t.cs[k], needs = d.t.nd[k] === 1;
    const ratio = d.ratio[d.t.ra[k]], pieces = {};
    if (needs) for (const s of Object.keys(ratio)) pieces[s] = ratio[s] * layers;
    list.push({ i: list.length, tableNo: d.t.no[k], mo: d.mo[d.t.mo[k]], color: d.co[d.t.co[k]], batch: d.ba[d.t.ba[k]],
      spread: layers * cfg.spreadRate * len + setup, cut: layers * cfg.cutRate * len, len, pieces, needs, pt: d.t.pt[k],
      ot: d.ot[d.t.ot[k]], mk: d.t.mk[k] });
  }
  const batchFirst = {};
  for (const bi of Object.keys(d.bf)) batchFirst[d.ba[bi]] = d.bf[bi];
  return { dates: d.dates.slice(), tasks, batchFirst };
}

// The few numbers the page re-computes and compares against what Node built
// (the parity check) — same engine, two runtimes.
function summary(r) {
  return {
    tasks: r.tasks, trolleys: r.trolleys, compartments: r.compartments,
    utilizationPct: r.utilizationPct, tablesPerShiftHour: r.tablesPerShiftHour,
    onTimePct: r.onTimePct, finishMin: r.finishMin,
    spBusy: r.sp.busy, spBlocked: r.sp.blocked, spStarved: r.sp.starved,
    cuCut: r.cu.cut, cuSetup: r.cu.setup, cuTravel: r.cu.travel, recallsSame: r.recallsSame,
    spreadingBlockedPct: r.model.spreadingBlockedPct,
    totalPieces: r.output.totalPieces, cutPerDay: r.output.cutPerDay, backlogPieces: r.output.backlogPieces,
    daysMeeting: r.output.daysMeeting, hoursPer100k: r.output.hoursPer100k,
  };
}

exports.makeConfig = makeConfig;
exports.createEngine = createEngine;
exports.ladder = ladder;
exports.summary = summary;
exports.decode = decode;
exports.optFromSweepKey = optFromSweepKey;

})(typeof module !== 'undefined' && module.exports ? module.exports : (window.Lab = {}));
