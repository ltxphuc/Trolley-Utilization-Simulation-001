'use strict';
/*
UTILIZATION CEILINGS — measurement only, never feeds the build.

    npm run ceiling        (node --max-old-space-size=6144 tools/util_ceiling.js)

Why does 2 batches per trolley stop at about 67%, not 70%? This prints how high trolley
utilization (compartments opened / (5 x trolleys)) could go in April-June if a part-filled trolley
could wait as long as it likes, so the rules and the WIP hold length can be told apart from the
data. It is NOT the simulation: no timing, no 52-bay limit, no hold, perfect packing.

A trolley holds one film width (rule H3), so compartments are grouped by film. A compartment holds
one size of one batch (H4); sizes of one batch merge (the remainder of a size is shared).
The published model only lets two batches share a trolley when MO, colour and film width match.
Only universal-size tables count (the same ones the trolley accounting sees).

  A  each table alone                                   no combining at all
  B  one batch per trolley, waits all plan date          packed within (plan date, batch)
  C  any batches of one MO + colour + film, waits all plan date
  D  as C, but waits for the whole period                (a trolley held for months: not real)
  E  as C, at most 2 batches per trolley                 (rule: MAX_BATCHES_PER_TROLLEY = 2)

Reading it: the model with a 60 min hold sits near B; the published sweep shows how fast the hold
length closes the gap to E (npm run build, out/sweep.json).
*/
const path = require('path');
const A = require('./assumptions');
const M = require('./model');

const REPO = path.join(__dirname, '..');
const [all] = M.loadDays(path.join(REPO, A.DATA_FILE), true);
const tasks = [];
for (const d of Object.keys(all)) {
  if (!A.WEBSITE_MONTHS.includes(d.slice(0, 7))) continue;
  for (const t of all[d]) if (t.needs_trolleys) tasks.push(Object.assign({ date: d }, t));
}
const TROLLEY = A.TROLLEY_COMPARTMENTS;
const pct = (comps, trolleys) => (100 * comps / (TROLLEY * trolleys)).toFixed(1) + '%';

// each batch's compartments per film, within one group (sizes of the batch merged)
function batchComps(groupKey) {
  const byBatch = new Map();
  for (const t of tasks) {
    const k = groupKey(t) + '\u0001' + t.batch;
    if (!byBatch.has(k)) byBatch.set(k, { g: groupKey(t), pieces: {} });
    const e = byBatch.get(k);
    for (const [s, q] of Object.entries(t.pieces_by_size)) e.pieces[s] = (e.pieces[s] || 0) + q;
  }
  const out = [];
  for (const e of byBatch.values()) for (const [film, list] of M.compartmentsFor(e.pieces)) out.push({ g: e.g, film, n: list.length });
  return out;
}
const packed = (list, keyOf) => {
  const pool = new Map();
  let comps = 0;
  for (const x of list) { const k = keyOf(x); pool.set(k, (pool.get(k) || 0) + x.n); comps += x.n; }
  let trolleys = 0;
  for (const n of pool.values()) trolleys += Math.ceil(n / TROLLEY);
  return [comps, trolleys];
};

// A: every table alone
let cA = 0, tA = 0;
for (const t of tasks) for (const [, list] of M.compartmentsFor(t.pieces_by_size)) { cA += list.length; tA += Math.ceil(list.length / TROLLEY); }

const byDateBatch = batchComps(t => t.date + '|' + t.batch);
const byDateMoColour = batchComps(t => t.date + '|' + t.mo + '|' + t.color);
const byMoColour = batchComps(t => t.mo + '|' + t.color);
const [cB, tB] = packed(byDateBatch, x => x.g + '|' + x.film);
const [cC, tC] = packed(byDateMoColour, x => x.g + '|' + x.film);
const [cD, tD] = packed(byMoColour, x => x.g + '|' + x.film);

// E: at most 2 batches per trolley. Each batch fills whole trolleys itself; the leftover compartments
// of two batches share a trolley when they fit in 5 (sorted, largest with smallest).
let cE = 0, tE = 0;
const left = new Map();
for (const x of byDateMoColour) {
  cE += x.n; tE += Math.floor(x.n / TROLLEY);
  const r = x.n % TROLLEY;
  if (r) { const k = x.g + '|' + x.film; if (!left.has(k)) left.set(k, []); left.get(k).push(r); }
}
for (const rs of left.values()) {
  rs.sort((a, b) => a - b);
  let i = 0, j = rs.length - 1;
  while (i <= j) { if (i < j && rs[i] + rs[j] <= TROLLEY) i += 1; j -= 1; tE += 1; }
}

// how many (plan date, MO, colour, film) groups are too small to fill even one trolley
const small = new Map();
for (const x of byDateMoColour) { const k = x.g + '|' + x.film; small.set(k, (small.get(k) || 0) + x.n); }
const tooSmall = [...small.values()].filter(n => n < TROLLEY).length;

console.log(`Utilization ceilings, April-June (${A.WEBSITE_MONTHS.join(', ')}), ${tasks.length} universal-size tables, ideal packing, no timing:\n`);
console.log(`  A  each table alone                                           ${pct(cA, tA)}`);
console.log(`  B  one batch per trolley, waiting all plan date               ${pct(cB, tB)}`);
console.log(`  E  MO + colour + film, at most 2 batches, waiting all date    ${pct(cE, tE)}`);
console.log(`  C  MO + colour + film, any number of batches, waiting a date  ${pct(cC, tC)}`);
console.log(`  D  as C, waiting for the whole period (not real)              ${pct(cD, tD)}`);
console.log(`\n  (plan date, MO, colour, film) groups under ${TROLLEY} compartments in total: ${tooSmall} of ${small.size} (${(100 * tooSmall / small.size).toFixed(0)}%)`);
