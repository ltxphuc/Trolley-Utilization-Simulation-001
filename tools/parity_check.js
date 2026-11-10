'use strict';
/*
 * PARITY GATE  —  the page's loading port vs the model's, every cell
 * ================================================================
 * Replaces the stale "4,680 / 4,680" figure (which was 20 dates x 2 sequencing
 * modes x 3 table lengths, and predates the 3-mode and cutter-count axes).
 *
 * For each built month file it opens the page in a real browser and calls
 * SIM.__check() (defined in dashboard.py's TEMPLATE), which walks:
 *
 *     every plan date in the file
 *   x every `full` variant  (21.2 m at 5 cutters, 21.2 m at 7 cutters)
 *   x every reachable (sequencing mode, batches, WIP hold, any-workstation)
 *
 * comparing the page's own loadTrolleys() output (utilization, trolleys,
 * compartments, combines) against the trace's `expected` block, which
 * tools/daytrace.js computed from tools/model.js's load_trolleys(). Those are
 * two independent reimplementations of the loading stage, so a match is a
 * real check, not a circular one (README Part 8 trap 8).
 *
 *   node tools/parity_check.js
 *
 * Real browser (playwright-core + Edge) — no layout is needed for this check,
 * but the page's own JS must actually execute, and jsdom has bitten this
 * project before. Exits non-zero on any mismatch.
 */
const path = require('path');
const { pathToFileURL } = require('url');

const OUT = path.join(__dirname, '..', 'out');
const FILES = ['sim-2026-04.html', 'sim-2026-05.html', 'sim-2026-06.html'];

(async () => {
  let chromium;
  try {
    ({ chromium } = require('playwright-core'));
  } catch (e) {
    console.error('playwright-core not found — run `npm install` first.');
    process.exit(2);
  }

  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  let totalChecks = 0, totalPass = 0, totalFail = 0;
  const allFails = [];

  for (const f of FILES) {
    const fp = path.join(OUT, f);
    const page = await browser.newPage();
    const errs = [];
    page.on('pageerror', e => errs.push('pageerror: ' + e.message));
    page.on('console', m => { if (m.type() === 'error') errs.push('console.error: ' + m.text()); });
    await page.goto(pathToFileURL(fp).href, { waitUntil: 'load' });
    await page.click('#tabBtnSim').catch(() => {});
    await page.waitForFunction(() => window.__SIM && typeof window.__SIM.__check === 'function', { timeout: 10000 });
    const r = await page.evaluate(() => window.__SIM.__check({ maxFails: 25 }));

    // Rules Lab: the page re-runs the option sets Node precomputed with the
    // same tools/lab.js (build.js labBlock) and compares them.
    await page.waitForFunction(() => window.__LAB && typeof window.__LAB.__labCheck === 'function', { timeout: 10000 });
    const lr = await page.evaluate(() => window.__LAB.__labCheck());
    console.log(`${f.padEnd(18)} rules lab: ${String(lr.checks).padStart(6)} checks  ${lr.fail === 0 ? 'PASSED' : 'FAILED (' + lr.fail + ' mismatched)'}`
      + `   [option sets ${lr.part.addons} · vs Utilization tab ${lr.part.sweep} · vs Simulation tab ${lr.part.trace}]`);
    r.checks += lr.checks; r.pass += lr.pass; r.fail += lr.fail;
    for (const x of lr.fails) r.fails.push({ lab: true, ...x });
    await page.close();

    const status = r.fail === 0 ? 'PASSED' : 'FAILED';
    console.log(`${f.padEnd(18)} ${String(r.dates).padStart(3)} dates  ` +
      `${String(r.checks).padStart(6)} checks  ${status}` +
      (r.fail ? `  (${r.fail} mismatched)` : ''));
    if (errs.length) console.log('   page errors:', errs.slice(0, 5));
    totalChecks += r.checks; totalPass += r.pass; totalFail += r.fail;
    for (const x of r.fails) allFails.push({ file: f, ...x });
    if (errs.length) totalFail += errs.length;
  }

  await browser.close();

  console.log('\n' + '='.repeat(60));
  console.log(`PARITY GATE — ${totalPass} / ${totalChecks} checks passed across ${FILES.length} month files`);
  if (totalFail === 0) {
    console.log('PASSED — the page and the model agree on every reachable cell.');
    console.log('='.repeat(60));
    process.exit(0);
  }
  console.log(`FAILED — ${totalFail} mismatch(es). First few:`);
  for (const x of allFails.slice(0, 25)) console.log('  ', JSON.stringify(x));
  console.log('='.repeat(60));
  process.exit(1);
})();
