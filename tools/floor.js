'use strict';
/*
THE LIVE FLOOR — one event-driven timeline (user rules, 2026-11-10).

    node:  const Floor = require('./floor');
    page:  build.js inlines this file before tools/lab.js, so the page runs the SAME code.

Both tools/model.js (liveCarryTimeline) and tools/lab.js (the Lab engine) call run() below, so
the published model and the Lab share one timeline by construction. The sequencers
(model.js sequence() / lab.js sequenceDay()) are passed in as seqFn and are not changed.

What it does, in time order, over every plan date at once (staffed spans only):
 1. RE-PLAN every `tickMin` minutes (30), around the clock: every READY table not yet started
    is planned again by the scenario's Job Sequence (seqFn), plan date by plan date, around what
    each machine still has committed. The plan covers the next `horizonMin` (24 h, all shifts):
    ready tables are taken, oldest plan date first, until their spreading minutes fill the
    spreaders' staffed time of the next 24 h. A table that has started spreading is never planned
    again.
 2. A SPREADER starts the head of its queue at the earliest staffed instant where its lay fits
    on the table (G6): a lay holds its full length until its cut starts, then frees it linearly
    through the cut. A lay whose cut has not been chosen yet holds its full length.
 3. A CUTTER that is free takes, among the lays already spread by the spreaders it serves (its
    own group, plus the second cutter of 24-03 / 24-05), the one that has WAITED LONGEST (the
    earliest spread end). User rule, a stand-in for the operator's free choice: ESTIMATE.
    Changeover (MO or colour change) and moving (different spreader) are charged as before.

A table is READY from its release time `rel` (the caller: plan date, pull-ahead, marker, fabric).

Ties between simultaneous events: re-plan, then cutters (in order), then spreaders (in order).
Equal waiting time: the lay of the earlier spreader in order, then the earlier table.

Callbacks (so one core serves both engines):
  P.get  = { rel(t), spread(t), cut(t), len(t), mo(t), color(t), day(t) }
  P.put(t, fields)  fields use the Lab's names: m, sb, se, blockFrom, blockedStaffed,
                    cutter, cb, ce, setup, travel, cutWait
  P.seqFn(groupTasks, initLoad, initCut) -> { spreader: [task, ...] }   (one plan date)
  P.isPair(a, b) (optional): true when b is the partner of a, i.e. the two are loaded back-to-back
                    as a pair. Once a has started on a spreader, b is pinned as that spreader's next
                    table and is not re-planned.
*/
(function (exports) {

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

// G6 table length. A lay is [length, cutStart, cutEnd]; a lay not yet cut is [length, Infinity, Infinity]
// and holds its full length. Identical to model.js freeLength / roomAt for finished lays.
function freeLength(lays, L, when) {
  let used = 0;
  for (const [length, cs, ce] of lays) {
    if (when >= ce) continue;
    if (when <= cs || ce <= cs) used += length;
    else used += length * (ce - when) / (ce - cs);
  }
  return L - used;
}
// The earliest instant >= earliest with `need` free. Infinity when it waits for a cut not chosen yet.
function roomAt(lays, L, earliest, need) {
  if (freeLength(lays, L, earliest) >= need) return earliest;
  const marks = [];
  let open = false;
  for (const [, cs, ce] of lays) {
    if (cs === Infinity) { open = true; continue; }
    if (cs > earliest) marks.push(cs);
    if (ce > earliest) marks.push(ce);
  }
  marks.sort((a, b) => a - b);
  let low = earliest;
  for (const mark of marks) {
    if (freeLength(lays, L, mark) >= need) {
      let high = mark;
      for (let i = 0; i < 40; i++) {
        const mid = (low + high) / 2;
        if (freeLength(lays, L, mid) >= need) high = mid; else low = mid;
      }
      return high;
    }
    low = mark;
  }
  if (open) return Infinity;
  let m = earliest;
  for (const [, , ce] of lays) m = Math.max(m, ce);
  return m;
}

function run(P) {
  const { spreaders, cutters, primary, flexOf, spSp, cuSp, tableLength, setupMin, travelMin, tasks,
    tickMin, horizonMin, seqFn, get, put } = P;
  const N = tasks.length, INF = Infinity;
  const idxOf = new Map(); tasks.forEach((t, i) => idxOf.set(t, i));
  const rel = tasks.map(t => get.rel(t)), spreadOf = tasks.map(t => get.spread(t)),
    cutOf = tasks.map(t => get.cut(t)), lenOf = tasks.map(t => get.len(t));
  const spIdx = {}; spreaders.forEach((m, k) => { spIdx[m] = k; });

  const started = new Array(N).fill(false), asgM = new Array(N).fill(null), asgAt = new Array(N).fill(0);
  let startedCount = 0, pend = tasks.map((t, i) => i);

  // low[m]: a re-plan that changes a spreader's next table cannot start it before that re-plan
  const low = {};
  // pinned[m]: the partner of a pair whose first table has started on m. It is next on m and is not
  // re-planned (the SQL locks tables that are processed together; rule (a): a pair is spread back-to-back).
  const pinned = {};
  const free = {}, lays = {}, queue = {}, qh = {}, tsC = {}, seq = {};
  const spBusy = {}, spBlocked = {}, spStarved = {}, starvedIv = {};
  for (const m of spreaders) {
    free[m] = 0; low[m] = 0; lays[m] = []; queue[m] = []; qh[m] = 0; tsC[m] = undefined; seq[m] = [];
    spBusy[m] = 0; spBlocked[m] = 0; spStarved[m] = 0; starvedIv[m] = [];
  }
  const cutFree = {}, cuBusy = {}, cuSetup = {}, cuTravel = {}, lastCut = {}, wl = {};
  for (const c of cutters) { cutFree[c] = 0; cuBusy[c] = 0; cuSetup[c] = 0; cuTravel[c] = 0; lastCut[c] = null; wl[c] = []; }
  const waiting = new Set();        // lays spread but not yet cut: { i, m, se, arr }

  let tickT = 0, guard = 0;
  const maxEvents = N * 12 + 200000;

  function capacity(T) {
    let s = 0;
    for (const m of spreaders) s += staffedBetween(spSp[m], T, T + horizonMin);
    return s;
  }

  function replan(T) {
    pend = pend.filter(i => !started[i]);
    const cap = capacity(T);
    const ready = [];
    const pinSet = new Set();
    for (const m of spreaders) if (pinned[m] !== undefined) pinSet.add(pinned[m]);
    let acc = 0;
    for (const i of pend) {
      if (rel[i] > T || pinSet.has(i)) continue;
      ready.push(i); acc += spreadOf[i];
      if (acc >= cap) break;
    }
    const init = {}, initC = {};
    for (const m of spreaders) init[m] = staffedBetween(spSp[m], T, free[m]);
    for (const c of cutters) initC[c] = staffedBetween(cuSp[c], T, cutFree[c]);
    for (const lay of waiting) if (initC[primary[lay.m]] !== undefined) initC[primary[lay.m]] += cutOf[lay.i];
    const next = {}; for (const m of spreaders) next[m] = [];
    for (const m of spreaders) {
      if (pinned[m] === undefined) continue;
      const i = pinned[m];
      next[m].push(i); init[m] += spreadOf[i]; initC[primary[m]] += cutOf[i];
    }
    let g = 0;
    while (g < ready.length) {
      const day = get.day(tasks[ready[g]]);
      const group = [];
      while (g < ready.length && get.day(tasks[ready[g]]) === day) { group.push(tasks[ready[g]]); g++; }
      const plan = seqFn(group, Object.assign({}, init), Object.assign({}, initC));
      for (const m of spreaders) {
        for (const t of plan[m]) {
          const i = idxOf.get(t);
          next[m].push(i);
          init[m] += spreadOf[i]; initC[primary[m]] += cutOf[i];
        }
      }
    }
    const inPlan = new Set();
    for (const m of spreaders) {
      if (next[m][0] !== queue[m][qh[m]]) low[m] = T;
      queue[m] = next[m]; qh[m] = 0; tsC[m] = undefined;
      for (const i of next[m]) { inPlan.add(i); if (asgM[i] !== m) { asgM[i] = m; asgAt[i] = T; } }
    }
    for (const i of ready) if (!inPlan.has(i)) asgM[i] = null;
  }

  function startOf(m) {
    if (qh[m] >= queue[m].length) return INF;
    let r = tsC[m];
    if (r === undefined) {
      const i = queue[m][qh[m]];
      const avail = Math.max(rel[i], asgAt[i]);
      const tm0 = advance(spSp[m], free[m]);
      const eff = advance(spSp[m], Math.max(free[m], avail, low[m]));
      const start = roomAt(lays[m], tableLength, eff, lenOf[i]);
      r = tsC[m] = { i, avail, tm0, eff, start };
    }
    return r.start;
  }
  function cutterAt(c) {
    const list = wl[c];
    if (!list.length) return INF;
    let minSe = INF;
    for (const lay of list) if (lay.se < minSe) minSe = lay.se;
    return advance(cuSp[c], Math.max(cutFree[c], minSe));
  }

  while (startedCount < N || waiting.size > 0) {
    if (++guard > maxEvents) throw new Error('floor did not converge');
    let bestT = startedCount < N ? tickT : INF, kind = 0, who = null;      // 0 re-plan, 1 cutter, 2 spreader
    for (const c of cutters) { const t = cutterAt(c); if (t < bestT) { bestT = t; kind = 1; who = c; } }
    for (const m of spreaders) { const t = startOf(m); if (t < bestT) { bestT = t; kind = 2; who = m; } }
    if (bestT === INF) throw new Error('floor deadlock: nothing can start or be cut');

    if (kind === 0) {
      replan(tickT);
      tickT += tickMin;
    } else if (kind === 1) {
      const c = who, td = bestT;
      let pick = null;
      for (const lay of wl[c]) {
        if (lay.se > td) continue;
        if (pick === null || lay.se < pick.se || (lay.se === pick.se && (spIdx[lay.m] < spIdx[pick.m]
          || (spIdx[lay.m] === spIdx[pick.m] && lay.i < pick.i)))) pick = lay;
      }
      const i = pick.i, m = pick.m, t = tasks[i], se = pick.se;
      const lc = lastCut[c];
      const setup = lc && (String(get.mo(t)) !== String(lc.mo) || String(get.color(t)) !== String(lc.color)) ? setupMin : 0;
      const travel = lc && lc.machine !== m ? travelMin : 0;
      const cutWait = Math.max(0, se - cutFree[c]);
      const [cb, ce] = occupy(cuSp[c], Math.max(se, cutFree[c]), cutOf[i] + setup + travel);
      cuBusy[c] += cutOf[i]; cuSetup[c] += setup; cuTravel[c] += travel;
      cutFree[c] = ce;
      lastCut[c] = { mo: get.mo(t), color: get.color(t), machine: m };
      pick.arr[1] = Math.min(ce, cb + setup + travel); pick.arr[2] = ce;
      put(t, { cutter: c, cb, ce, setup, travel, cutWait });
      waiting.delete(pick);
      for (const cc of flexOf[m]) { const a = wl[cc], k = a.indexOf(pick); if (k >= 0) a.splice(k, 1); }
      tsC[m] = undefined;
    } else {
      const m = who, r = tsC[m], i = r.i, t = tasks[i];
      lays[m] = lays[m].filter(l => l[2] > r.eff);
      const blocked = staffedBetween(spSp[m], r.eff, r.start);
      if (r.avail > r.tm0) { spStarved[m] += staffedBetween(spSp[m], r.tm0, r.avail); starvedIv[m].push([r.tm0, r.avail]); }
      const [sb, se] = occupy(spSp[m], r.start, spreadOf[i]);
      spBusy[m] += spreadOf[i]; spBlocked[m] += blocked; free[m] = se;
      const arr = [lenOf[i], INF, INF]; lays[m].push(arr);
      const lay = { i, m, se, arr };
      waiting.add(lay);
      for (const c of flexOf[m]) wl[c].push(lay);
      started[i] = true; startedCount += 1; seq[m].push(t);
      if (pinned[m] === i) pinned[m] = undefined;
      qh[m] += 1; tsC[m] = undefined;
      if (P.isPair && qh[m] < queue[m].length && P.isPair(t, tasks[queue[m][qh[m]]])) pinned[m] = queue[m][qh[m]];
      put(t, { m, sb, se, blockFrom: r.eff, blockedStaffed: blocked });
    }
  }
  return { seq, spBusy, spBlocked, spStarved, starvedIv, cuBusy, cuSetup, cuTravel };
}

exports.run = run;
exports.advance = advance;
exports.occupy = occupy;
exports.staffedBetween = staffedBetween;
exports.roomAt = roomAt;
exports.freeLength = freeLength;

})(typeof module !== 'undefined' && module.exports ? module.exports : (window.Floor = {}));
