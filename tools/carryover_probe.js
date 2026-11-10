'use strict';
/* CARRY-OVER PROBE — the published model's lateness against the real Pull Date
 * ================================================================
 * A MEASUREMENT script (never feeds the build). A VALIDATION, not a calibration:
 * the model has no machine speed factor (removed 2026-11-09, user decision), so
 * nothing is tuned to these numbers. It runs the published model once (S0,
 * 'today', the real floor's own logic) and prints four lateness statistics beside
 * the real ones from Pull Date, the actual finished-spreading time. The model is
 * EXPECTED to be less late than the real floor: it runs at the G2 standard pace,
 * with cutter changeover and moving time as the only added loss, and has none of
 * the other things that slow the real floor.
 *
 * LATENESS, both sides: minutes after the plan date's midnight at which the
 * table's spreading finished. "late" = more than 1440 min, i.e. spread after the
 * plan date ended; "more than a day late" = more than 2880 min. Real = Pull Date
 * minus that midnight, for every table that has a Pull Date. Simulated = the
 * model's spread_end - the date's offset + SHIFT_START_MINUTE, for EVERY table of
 * the scope (all simulated tables against the Pull-Date tables).
 *
 * Relaxing is off (the model has none). April-June only.
 *
 *   node --max-old-space-size=6144 tools/carryover_probe.js
 */
const path = require('path');
const A = require('./assumptions');
const M = require('./model');

const REPO = path.join(__dirname, '..');

function scope(all) {
  const out = {};
  for (const d of Object.keys(all)) if (A.WEBSITE_MONTHS.includes(d.slice(0, 7))) out[d] = all[d];
  return out;
}
const median = a => { const s = a.slice().sort((x, y) => x - y); return s[Math.floor((s.length - 1) / 2)]; };
const mean = a => a.reduce((x, y) => x + y, 0) / a.length;
function stats(minutes) {                 // minutes after the plan date's midnight
  const late = minutes.filter(m => m > 1440), very = minutes.filter(m => m > 2880);
  return {
    n: minutes.length, nLate: late.length,
    latePct: 100 * late.length / minutes.length, veryLatePct: 100 * very.length / minutes.length,
    medianClock: median(minutes), meanSlipDays: late.length ? mean(late.map(m => (m - 1440) / 1440)) : 0,
  };
}
const clock = m => String(Math.floor((m % 1440) / 60)).padStart(2, '0') + ':' + String(Math.round(m % 60)).padStart(2, '0')
  + (m >= 1440 ? '+' + Math.floor(m / 1440) + 'd' : '');
const row = (label, s, mark) => console.log(`  ${label.padEnd(22)}│ ${s.latePct.toFixed(2).padStart(6)}% │ ${s.veryLatePct.toFixed(2).padStart(6)}% │ ${clock(s.medianClock).padStart(8)} │ ${s.meanSlipDays.toFixed(3).padStart(6)} d │ ${String(s.n).padStart(5)} │ ${mark || ''}`);
const header = () => {
  console.log(`  ${'run'.padEnd(22)}│   late │ >1 day │   median │ slip(late) │ tables │`);
  console.log(`  ${'─'.repeat(22)}┼────────┼────────┼──────────┼────────────┼────────┼──────`);
};

function main() {
  const [all] = M.loadDays(path.join(REPO, A.DATA_FILE), true);
  const days = scope(all);

  const real = [];
  for (const d of Object.keys(days)) for (const t of days[d]) {
    if (t.spread_done_at) real.push((t.spread_done_at.getTime() - M.midnightUTC(d)) / 60000);
  }
  const rs = stats(real);

  const sim = M.carryTimeline(days, 'today');
  const m = [];
  sim.dates.forEach((d, di) => { for (const t of sim.byDate[d]) m.push(t.spread_end - sim.off[di] + A.SHIFT_START_MINUTE); });
  const ss = stats(m);

  console.log(`\nCARRY-OVER PROBE  [${A.WEBSITE_MONTHS.join(', ')}]  ${Object.keys(days).length} plan dates, ${real.length} tables with a Pull Date`);
  console.log('The model has no machine speed factor: it runs at the G2 standard pace and is expected to be less late than the real floor.');
  console.log(`published floor: S0 ('today'), relaxing off, cutter changeover ${A.CUT_SETUP_MO_COLOR_MINUTES} min and moving ${A.CUT_TRAVEL_MINUTES} min (ESTIMATES)`);
  console.log('lateness = spreading finished after the plan date\'s midnight; "late" = more than 1 day after midnight, i.e. after the plan date; ">1 day" = more than 2 days after it; slip = days past the end of the plan date');
  console.log('real side: tables with a Pull Date; simulated side: every table of the scope');
  console.log('');
  header();
  row('REAL (Pull Date)', rs, `${rs.nLate} late of ${rs.n}`);
  row('MODEL (S0)', ss, `${ss.nLate} late of ${ss.n}`);
  console.log(`\n  gap model - real: late ${(ss.latePct - rs.latePct).toFixed(2)} points, more than a day late ${(ss.veryLatePct - rs.veryLatePct).toFixed(2)} points, mean slip ${(ss.meanSlipDays - rs.meanSlipDays).toFixed(3)} d`);
}

main();
