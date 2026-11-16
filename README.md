# Trolley Utilization Simulation — Central Cutting

A simulation of Central Cutting's **Job Sequence** (which spreading machine spreads which table, in what
order) and **Panel Loading** (how cut panels go into trolley compartments), run on the factory's real
planning data.

It answers one question: **how many trolleys does Central Cutting need, and can three rule changes bring
that under the 1,200 trolleys it owns?**

**Open the website:** <https://ltxphuc.github.io/Trolley-Utilization-Simulation-001/>. It is one
self-contained page: nothing to install, and it works offline once loaded.

## Contents

- [The answer](#the-answer)
- [How the website works](#how-the-website-works)
- [What is estimated](#what-is-estimated)
- [The documents](#the-documents)
- [For developers](#for-developers)

---

## The answer

April–June 2026: 79 plan dates, 6,501 spreading tables. The fleet figures assume a **7-day trolley round
trip, an ESTIMATE that has never been timed**. Cutter changeover (5 min) and moving (1.5 min) are ESTIMATES
too.

| Scenario | What it adds | Trolley utilization | Trolleys a day | Fleet needed @ 7 days | Against 1,200 owned |
|---|---|---|---|---|---|
| **S0 Today** | today's Job Sequence and loading rules | 51.85% | 203.8 | 1,426 | 226 short |
| **S1** | + same-MO tables spread back-to-back in pairs | 58.19% | 175.8 | 1,231 | 31 short |
| **S2** | + 2 fabric batches may share a trolley | 61.17% | 167.3 | 1,171 | 29 spare |
| **S3** | + a part-filled trolley waits up to 1 h for a matching table | 67.45% | 151.7 | 1,062 | 138 spare |

*Trolley utilization* = compartments opened ÷ compartments available (5 per trolley). At the 5-day
allowance instead of 7 days, today's floor would need 1,019 trolleys and fit.

**Two separate findings** (never traded against each other):

1. **Trolleys.** Today a trolley leaves with about half its compartments empty. The three changes together
   bring the fleet needed under the 1,200 owned, if the round trip is really about 7 days.
2. **Cutting output.** The three changes do not change how many pieces are cut (80,216 pieces a day today,
   all scenarios within 0.5%). Output is held back by when tables become ready (their marker and their
   relaxed fabric), not by the trolley rules.

The rules behind these numbers are in [RULES.md](RULES.md). How the changes would be built is in
[docs/CHANGE_SPEC.md](docs/CHANGE_SPEC.md).

## How the website works

The page is the **Rules Lab**. On the left you choose the rules; the right shows what they do. Every
number is computed in your browser by the same code that produced the published table, over all 79 plan
dates. A change takes a few seconds ("Calculating…").

**The badge** at the top of the results says whether your selection equals the published model:
- **green, "Same as the published model"**: the numbers match the published table exactly;
- **"Not the published model: …"**: you changed something outside the published set, and it lists what.

**"vs today"** everywhere means S0, today's Job Sequence, on the same floor and with the same settings as
your selection. Only the rules differ.

### The controls (left)

| Control | What it does |
|---|---|
| **The floor** | Explains the floor model. **Reset to the published model** puts every control back to its default. |
| **Plan date** | A calendar of the 79 plan dates. Picking a date changes the Job Sequence, Idle time and Panel Loading views; the headline numbers always pool all dates. |
| **Shift** | Both shifts (today), day only, or night only (only 24-01, 02, 03 and cutter 24MC1 work nights). |
| **Fleet** | **Round trip** (3–10 days, default 7, an ESTIMATE) and **trolleys owned** (default 1,200). These only change the fleet arithmetic. |
| **1 Same-MO sequencing** | Off (today), **Same batch only** (S1) or **Cross-batch** (S2, S3). Pairs tables of the same MO and colour and spreads each pair back-to-back on one spreader. |
| **Where the pairs go** | Pairs over the floor (the rule) or keep a whole MO on one cut group (an option). Only with same-MO sequencing on. |
| **2 Batches per trolley** | 1, 2 or 3 (2 and 3 behave the same: the limit is 2). **2 and 3 can only be chosen with Cross-batch sequencing**; with anything else a trolley carries one batch. |
| **3 WIP hold** | 0–240 minutes: how long a part-filled trolley waits for a later table of the same MO, colour and film. |
| **It comes back to** | A waiting trolley may return to any workstation, or only to the one it left. |
| **Which parked trolley is recalled** | Published (any matching trolley), same batch first, or same batch only. |
| **Add-ons** (ESTIMATES) | **Pull-ahead**: a spreader that has finished may start the next plan dates' tables. **Cutter setup** and **cutter travel**: the minutes a cutter loses on an MO or colour change and when it moves to another spreader. **Wait for fabric relaxing**: on by default; the earliest and latest fabric arrival before the plan date. |

The published scenarios are: S0 = Off / 1 / 0 min; S1 = Same batch only / 1 / 0; S2 = Cross-batch / 2 / 0;
S3 = Cross-batch / 2 / 60 min, any workstation.

### The results (right)

| Panel | What it shows |
|---|---|
| **Fleet card and tiles** | Trolleys needed at your round trip, and whether the fleet you own covers it (spare or short), then six tiles: compartments opened (utilization), compartment fill, garments per trolley, trolleys out per day, the round trip the fleet can cover, and the average wait in WIP. Each shows the change against today. |
| **What one trolley looks like** | The average trolley drawn to scale: loaded compartments at the bottom, empty space on top. |
| **Job Sequence** (for the chosen date) | Every table on its spreading machine, and the cut that follows on its cutter, against the clock. Switch between **your selection** and **S0 Today**. The **time cursor** greys out what has finished by then. Hatching = **blocked** (the spreading table is full); shading = **starved** (nothing ready to start: marker or fabric not ready, or the plan date not begun). Brackets mark pairs; small slices before a cut are cutter setup and travel; a dashed outline is a table from an earlier plan date. |
| **Idle time** (for the chosen date) | Hours per cut group, S0 against your selection. |
| **Panel Loading** (for the chosen date; click to open) | Every trolley of the day, compartment by compartment: size, batch, tables, and whether it was recalled. |
| **Output: pieces cut a day** | S0 against your selection, on the real plan and on a **100,000-a-day plan** (the same tables dealt into days of at least 100,000 pieces: a test of capacity, not a forecast). |
| **Where the machine time goes** | Hours per working day for the spreading and cutting machines, summed and machine by machine: working time, and lost time split into its parts (spreaders: waiting for table space, nothing released, idle; cutters: setup, travel, waiting for a table). |
| **Day by day** | For each plan date, the share of its tables fully cut inside its own shift window. |
| **How to read this** | Short notes on the terms used. |

## What is estimated

These numbers are not measured. Every result that depends on them is marked on the page.

| Estimate | Value | Why it matters |
|---|---|---|
| Trolley round trip | 7 days | the whole fleet case turns on it |
| Cutter changeover / moving | 5 / 1.5 min | cutter lost time and output |
| Fabric arrival | 12–48 h before the batch's first plan date, then 24 h relaxing | when tables can start |
| Cutter's choice of the next lay | the one that has waited longest | the order of cutting |
| Priority by order type in today's Job Sequence | SQR, then QR, then Normal | the live priority table was not supplied |

The model is also **less late than the real floor**: 26% of its tables finish after their plan date,
against 51% on the real floor. So its absolute output and idle times are optimistic; the comparisons
between S0 and S1–S3, on the same floor, are the findings. The full list is in
[RULES.md](RULES.md#d-estimates).

## The documents

| Document | For | What is in it |
|---|---|---|
| [RULES.md](RULES.md) | everyone | every rule the simulation obeys, one line each: common rules, this factory's floor facts, the three changes, the estimates |
| [SIM_SPEC.md](SIM_SPEC.md) | developers | exactly how each rule is computed: inputs, algorithms, quirks, validation targets, codebase map |
| [docs/DATA_MODEL.md](docs/DATA_MODEL.md) | anyone building on the model | generated register: every entity and attribute, every parameter with its current value, every formula, and statistics of the data; also as CSV files in [docs/data_model/](docs/data_model/) |
| [docs/CHANGE_SPEC.md](docs/CHANGE_SPEC.md) | ISD | the three changes as the floor system would build them |
| [docs/IDLE_TIME.md](docs/IDLE_TIME.md) | engineers | why spreading machines stop, and what would change it |
| [docs/HISTORY.md](docs/HISTORY.md) | anyone checking a number | every decision and every published number, stage by stage, and the archive of older documents |

---

## For developers

**Requirements:** Node.js. `npm install` fetches the two build-only packages (`xlsx`, `jsdom`). The parity
gate also needs Microsoft Edge (driven by `playwright-core`). No Python is needed.

Run everything from this folder. Scripts that read the 23 MB workbook need a 6 GB heap (already set in
`package.json`).

| Command | What it does |
|---|---|
| `npm run build` | rebuilds `out/` and the root `index.html` (the page GitHub Pages serves), about 30 s |
| `npm run lab` | **gate:** the website's engine equals the model exactly |
| `npm run regress` | **gate:** 18 shared plan dates × 117 scenarios, old data file against new |
| `npm run parity` | **gate:** the built page, run in Edge, reproduces what Node computed |
| `npm run beforeafter` | every published change stage by stage, with asserts ([docs/HISTORY.md](docs/HISTORY.md)) |
| `npm run carryprobe` | the model's lateness against the real floor (a validation, nothing is tuned to it) |
| `npm run idle`, `tc`, `ceiling` | measurement tables (idle time, cutter count, utilization ceiling) |
| `npm run datamodel` | regenerates [docs/DATA_MODEL.md](docs/DATA_MODEL.md) and its CSVs from the code; `-- --check` fails if they are out of date |

**Before publishing:** run lab, build, regress and parity, then open the page in Edge and check that there
are no console errors and that the badge is green on the defaults. Run `npm run datamodel -- --check` too.
Nothing is published if one fails.

**Changing a number:** every value lives in [`tools/assumptions.js`](tools/assumptions.js), with the rule it
comes from. A new constant also needs a row in `tools/data_model.js` (the script fails without one); then
run `npm run datamodel`. Never hand-edit anything in `out/` or `docs/DATA_MODEL.md`; they are generated. A
change that moves a published number is reported with a before/after table.

**Repo map**

```
README.md            this file: the project and the website
RULES.md             every rule
SIM_SPEC.md          how the model computes them
docs/                change spec, idle time, history, the generated data model (+ CSVs), archive
dashboard.py         the page template (HTML, CSS, browser JS); build.js reads it as text
index.html           copy of out/index.html, served by GitHub Pages
tools/
  assumptions.js     every number, with its rule
  model.js           the model: read, sequence, time, load, metrics
  floor.js           the live floor's timeline (shared by the model and the website)
  lab.js             the website's engine (run by Node and inlined into the page)
  scenarios.js       S0–S3, the hold variants and the 117-scenario sweep
  daytrace.js        per-day trace and the page's compact data
  build.js           writes out/
  lab_table.js, regress.js, parity_check.js      the gates
  before_after.js, carryover_probe.js, idle_variants.js, tc_table.js, util_ceiling.js   measurements
  data_model.js      writes docs/DATA_MODEL.md and docs/data_model/*.csv
data/                the source workbooks (HaveCut), the Job Sequence SQL and the factory rulebook (RULES.docx); never modified
out/                 build output; out/*.bak are the last output of the retired Python build (never edit)
```
