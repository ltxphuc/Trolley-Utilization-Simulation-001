'use strict';
/*
 * PARITY GATE  —  the page against the model
 * ===========================================
 * (2026-11-14: the Utilization and Simulation tabs were removed; the page is the Rules Lab only.
 * The page's own loading port, SIM.__check(), went with the Simulation tab. The loading stage
 * is still proven by `npm run lab`: tools/lab.js equals model.js exactly.)
 *
 * For each built month file it opens the page in a real browser and calls
 * LAB.__labCheck(), which re-runs, in the page, what Node computed:
 *
 *   1. the option sets build.js precomputed with the same tools/lab.js (including a
 *      7/8-cutter floor and a 24 m table);
 *   2. all 117 published sweep keys against `DATA.sweep`;
 *   3. this month's Job Sequence, task by task, against the model's trace.
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
    await page.waitForFunction(() => window.__LAB && typeof window.__LAB.__labCheck === 'function', { timeout: 10000 });
    const lr = await page.evaluate(() => window.__LAB.__labCheck());
    const r = { checks: lr.checks, pass: lr.pass, fail: lr.fail, fails: lr.fails.map(x => ({ lab: true, ...x })) };
    await page.close();

    console.log(`${f.padEnd(18)} ${String(r.checks).padStart(6)} checks  ${r.fail === 0 ? 'PASSED' : 'FAILED (' + r.fail + ' mismatched)'}`
      + `   [option sets ${lr.part.addons} · vs published sweep ${lr.part.sweep} · vs model trace ${lr.part.trace}]`);
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
