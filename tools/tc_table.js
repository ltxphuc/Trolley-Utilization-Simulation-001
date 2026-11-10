'use strict';
/* TABLE T-C — the cutting-machine-count axis's effect on trolley numbers.
 * ====================================================================
 * README Part 8 §4 flagged this as the one open measurement of the
 * 2026-09-08 work: cutter count changes CUT_GROUPS, which changes
 * _pick_machine's candidate list, which changes the sequence — and trolley
 * utilization depends on the sequence. Part 7 §5's "trolley utilization is
 * independent of the idle-time changes" claim was established for table
 * length and routing, NEITHER of which touches CUT_GROUPS, so it does not
 * automatically extend here. This script measures the axis directly.
 *
 * It is a MEASUREMENT script, not part of the build. Since 2026-11-09 it runs
 * the published carry-over model (M.runCarry), threading a layout through it
 * (runCarry's `layout` option). The cold-start model it used to run was
 * removed; the cold-start figures it printed (the saved `npm run tc` output of
 * 2026-11-09, before the removal) are kept below as COLD_START and printed
 * beside the carry-over figures. They are HISTORICAL: that run cannot be
 * reproduced any more. Machines run at the G2 standard pace in both, but the
 * cold-start columns are a closed-day model, so the two are not a
 * like-for-like pair; the gap is the floor model, not a rule.
 *
 * Run:  node --max-old-space-size=6144 tools/tc_table.js
 * Python has never run on this machine; there is no .py sibling for this
 * because idle_variants.py §4b (its own cutter table) is the Python-side
 * home for the same measurement — see README Part 8 §4.
 */
const path = require('path');
const A = require('./assumptions');
const M = require('./model');
const S = require('./scenarios');

const REPO = path.join(__dirname, '..');

// HISTORICAL cold-start (closed-day model, full G2 speed) results, from the
// `npm run tc` output saved on 2026-11-09 before the cold start was removed:
// [util%, trolleys/day, fleet@7d] by scope, scenario (S0..S3) and cutter count.
const COLD_START = {
  website: [
    { 5: [53.80, 194.4, 1360], 6: [54.89, 189.6, 1327], 7: [55.04, 188.8, 1322], 8: [55.19, 188.1, 1317] },
    { 5: [58.75, 173.6, 1216], 6: [58.75, 173.6, 1216], 7: [58.75, 173.6, 1216], 8: [58.75, 173.6, 1216] },
    { 5: [64.69, 157.8, 1104], 6: [64.68, 157.8, 1105], 7: [64.70, 157.8, 1104], 8: [64.68, 157.8, 1105] },
    { 5: [71.37, 143.0, 1001], 6: [71.51, 142.8, 999], 7: [71.05, 143.7, 1006], 8: [71.03, 143.7, 1006] },
  ],
  full: [
    { 5: [52.99, 174.5, 1221], 6: [54.03, 170.4, 1193], 7: [54.32, 169.2, 1184], 8: [54.47, 168.4, 1179] },
    { 5: [57.96, 155.2, 1087], 6: [57.96, 155.2, 1087], 7: [57.96, 155.2, 1087], 8: [57.96, 155.2, 1087] },
    { 5: [63.44, 141.9, 993], 6: [63.46, 141.9, 993], 7: [63.47, 141.8, 993], 8: [63.47, 141.8, 993] },
    { 5: [70.48, 127.7, 894], 6: [70.73, 127.3, 891], 7: [70.34, 128.0, 896], 8: [70.23, 128.2, 897] },
  ],
};

// The published carry-over model at one cutter layout. Its output carries every
// field printed below except the fleet, which is trolleys/day x the trip.
function pooledRun(scenario, days, layout) {
  const r = M.runCarry(scenario, days, { layout });
  return Object.assign({}, r, {
    fleet_at_7d: Math.round(r.trolleys_per_day * A.CYCLE_DAYS_ESTIMATED),
  });
}

function scopeDays(allDays, months) {
  if (!months) return allDays;
  const out = {};
  for (const d of Object.keys(allDays)) if (months.includes(d.slice(0, 7))) out[d] = allDays[d];
  return out;
}

function table(label, days, scope) {
  console.log(`\n\n================  ${label}  (${Object.keys(days).length} plan dates)  ================`);
  S.HEADLINE.forEach((sc, si) => {
    console.log(`\n${sc.name}   (carry-over; right-hand block: HISTORICAL cold start, saved 2026-11-09)`);
    console.log('  cutters │  util%  │ troll/day │ peak │ pc/troll │ spd blk% │ cut blk% │ blk min/day │ MC over │ fleet@7d │ cold: util% troll/day fleet');
    console.log('  ────────┼─────────┼───────────┼──────┼──────────┼──────────┼──────────┼─────────────┼─────────┼──────────┼────────────────────────────');
    const base = {};
    for (const n of A.SIM_CUTTER_COUNTS) {
      const layout = M.machineLayout(A.CUT_GROUPS_BY_CUTTER_COUNT[n]);
      const r = pooledRun(sc, days, layout);
      if (n === 5) Object.assign(base, r);
      const d = (v, b, dp = 1) => {
        const delta = v - b;
        const s = delta >= 0 ? '+' : '−';
        return `${v.toFixed(dp)} (${s}${Math.abs(delta).toFixed(dp)})`;
      };
      const cells = n === 5
        ? [`${r.utilization_pct.toFixed(2)}`, `${r.trolleys_per_day.toFixed(1)}`,
           `${r.peak_trolleys_in_a_day}`, `${r.pieces_per_trolley.toFixed(0)}`,
           `${r.spreading_blocked_pct.toFixed(1)}`, `${r.cutting_blocked_pct.toFixed(1)}`,
           `${r.spreading_blocked_minutes.toFixed(0)}`, `${r.machines_over_window.toFixed(2)}`,
           `${r.fleet_at_7d}`]
        : [d(r.utilization_pct, base.utilization_pct, 2), d(r.trolleys_per_day, base.trolleys_per_day),
           `${r.peak_trolleys_in_a_day}`, `${r.pieces_per_trolley.toFixed(0)}`,
           d(r.spreading_blocked_pct, base.spreading_blocked_pct), d(r.cutting_blocked_pct, base.cutting_blocked_pct),
           `${r.spreading_blocked_minutes.toFixed(0)}`, `${r.machines_over_window.toFixed(2)}`,
           `${r.fleet_at_7d} (${r.fleet_at_7d - base.fleet_at_7d >= 0 ? '+' : '−'}${Math.abs(r.fleet_at_7d - base.fleet_at_7d)})`];
      const cold = COLD_START[scope][si][n];
      console.log(`  ${String(n).padStart(7)} │ ${cells[0].padStart(7)} │ ${cells[1].padStart(9)} │ ${cells[2].padStart(4)} │ ${cells[3].padStart(8)} │ ${cells[4].padStart(8)} │ ${cells[5].padStart(8)} │ ${cells[6].padStart(11)} │ ${cells[7].padStart(7)} │ ${cells[8].padEnd(14)} │ ${cold[0].toFixed(2).padStart(10)} ${cold[1].toFixed(1).padStart(9)} ${String(cold[2]).padStart(5)}`);
    }
  });
}

function main() {
  console.log('Reading', A.DATA_FILE, '...');
  const [allDays] = M.loadDays(path.join(REPO, A.DATA_FILE), true);
  console.log(`  ${Object.keys(allDays).length} plan dates in the file`);

  // Primary: the website's own April–June scope — the scope the headline
  // table at the top of README rests on.
  table(`WEBSITE SCOPE  [${A.WEBSITE_MONTHS.join(', ')}]`, scopeDays(allDays, A.WEBSITE_MONTHS), 'website');

  // Secondary: the full 199-date file, for continuity with idle_variants.py
  // (which is unscoped) and Part 8 §4's T-A table.
  table('FULL FILE  [Jan–Aug, unscoped]', allDays, 'full');
}

main();
