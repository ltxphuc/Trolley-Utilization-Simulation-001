# CCT Trolley Model

> **Update 2026-11-10 (later) — the floor is live.** The Job Sequence now re-plans every 30 minutes,
> around the clock; a table starts only when its plan date, its Marker Date and its fabric (the relaxing
> ESTIMATE) are ready; a partner of a started pair stays next on its spreader; and a free cutter takes
> the lay that has waited longest (an ESTIMATE of the operator's free choice). `tools/floor.js` is shared
> by the model and the Lab (`SIM_SPEC.md` §6b). **Every published number moved** (April–June, carry-over,
> G2 pace, changeover 5 / moving 1.5 ESTIMATES, fleet at the 7-day ESTIMATE):
>
> | | Utilization | Trolleys/day | Fleet @ 7 days | vs 1,200 | Pieces cut a day, real plan / 100k plan |
> |---|---|---|---|---|---|
> | S0 Today (real Job Sequence) | 51.85% | 203.8 | 1,426 | 226 short | 80,216 / 96,700 |
> | S1 + same-MO sequencing | 58.19% | 175.8 | 1,231 | 31 short | 80,222 / 96,576 |
> | S2 + 2 batches per trolley | 61.17% | 167.3 | 1,171 | 29 spare | 80,211 / 97,119 |
> | S3 + WIP hold | 67.45% | 151.7 | 1,062 | 138 spare | 80,211 / 97,119 |
>
> The trolley rules do not change cutter output; the floor is limited by when tables become ready.
> The model is less late than the real floor (25.98% of tables late against 51.25%). The Lab's Dynamic
> spreader pick and Keep same colour close were removed. There is no Python port of the live floor yet.
> The S0 table in the notes below is superseded.

> **Update 2026-11-10 — S0 is now the real Job Sequence.** S0 (today) was the model's own
> sequencer, which kept a whole MO + colour + batch on one cut group; the floor does not work
> that way (user, 2026-11-09). S0 now mirrors the core loop of the Job Sequence stored procedure
> (`data/SQL Job Sequence Logic.sql`): every table gets a cutter, then the least-loaded spreader
> takes the shortest waiting table (`SIM_SPEC.md` §5, quirks Q20–Q23). **Only S0 moved**; S1–S3 are
> bit-identical. The night shift starts at 18:00 (no published number moves). The S0 row of the
> table below is superseded by:
>
> | | Utilization | Trolleys/day | Fleet @ 7 days (ESTIMATE) | vs 1,200 | Pieces cut a day, real plan / 100k plan |
> |---|---|---|---|---|---|
> | S0 Today (real Job Sequence) | 51.92% | 203.5 | 1,424 | 224 short | 72,593 / 71,279 |
> | S1 + same-MO sequencing | 58.75% | 173.6 | 1,216 | 16 short | 80,671 / 94,867 |
> | S3 + WIP hold | 68.77% | 148.4 | 1,039 | 161 spare | 80,711 / 95,195 |
>
> S0 → S1 now changes the dispatcher **and** adds pairing, so the gain is not pairing alone. S0 is
> as often late as the real floor (52.02% against 51.25%) but its tail is much longer, so S0's
> absolute numbers are not yet trustworthy. Priority by order type (SQR, QR, Normal) is an
> ESTIMATE; the live priority table was not supplied.

> **Update 2026-11-09 — the published numbers moved again.** The published model is the
> **carry-over floor** (work is always left from the day before; since 2026-11-09 there is no
> cold-start model at all). Three things changed on 2026-11-09, one rule at a time
> (`npm run beforeafter`, `SIM_SPEC.md` §18):
> 1. S1–S3 **pair first and assign each pair over the whole floor** (rule (a), Part 6 Change 1);
>    keeping a whole MO on one cut group is now an option;
> 2. the **cutters lose time to a changeover (5 min) and to moving (1.5 min)**, both
>    ESTIMATES, in the published model;
> 3. the **machine speed factor (ESTIMATED 0.80) was removed**: the model runs at the G2
>    standard pace and is less late than the real floor (17.78% of tables late against
>    51.25% real, `npm run carryprobe`).
>
> Everything below this note — the headline table, Parts 1 to 8 — was written for the earlier
> cold-start model and is **stale** (marked HISTORICAL where it is kept). Current numbers
> (April–June, 79 plan dates, carry-over, G2 pace, changeover 5 / moving 1.5 ESTIMATES; the
> 7-day trip is an ESTIMATE, never timed):
>
> | | Utilization | Trolleys/day | Fleet @ 7 days (ESTIMATE) | vs 1,200 |
> |---|---|---|---|---|
> | S0 Today | 53.49% | 195.9 | 1,371 | 171 short |
> | S1 + same-MO sequencing | 58.75% | 173.6 | 1,216 | 16 short |
> | S2 + 2 batches per trolley | 64.67% | 157.8 | 1,104 | 96 spare |
> | S3 + WIP hold | 68.77% | 148.4 | 1,039 | 161 spare |
>
> The three changes still bring the requirement under the fleet owned. They raise trolley
> utilization, not cutter output (every difference is under 0.3% at the standard pace). The
> 2026-11-06 build (speed 0.80: S0 52.49% / 201.1 / 1,408, S3 69.77% / 146.2 / 1,024) is
> superseded. Idle-time figures changed a lot and are not comparable with the ones below.

A simulation of Central Cutting's Job Sequence and Panel Loading, run against
real HaveCut data for **April–June 2026** (79 plan dates, 6,501 tables, ~82 a
day). This is a **narrowed scope**, not the full dataset available — see the
note directly below the table before quoting these numbers as "the" answer.

It answers one question: **how many trolleys does Central Cutting actually need,
and can three rule changes bring that under the 1,200 we own?**

*(HISTORICAL cold-start numbers, retired 2026-11-09, superseded by the banner above; the next
paragraph and table are kept as the record of the original finding.)*

Trolleys leave Central Cutting with **2.69 of 5 compartments opened (53.8%)**
— "full" was the wrong word for that number: it counts compartments opened,
not how full each one is (see Part 8 §3). At ~194 trolley loads a day and an
estimated 7-day round trip, that means **~1,360
trolleys have to be in circulation**, against a fleet of **1,200**. The factory
is roughly **160 trolleys short** on this quarter's volume. Job Sequence
sequencing alone (change 1) narrows that to **16 short** — close, but not
closed; the second and third changes are what actually clear it, taking
utilization to **71.4%** and the requirement to **1,001** — **199 trolleys to
spare**, inside the existing fleet, with no capex.

| | Utilization | Trolleys/day | Fleet needed @7d | vs 1,200 |
|---|---|---|---|---|
| **S0** Today | 53.8% | 194 | 1,360 | **160 short** |
| **S1** + same-MO sequencing (same batch only) | 58.8% | 174 | 1,216 | 16 short |
| **S2** + 2 batches per trolley (cross-batch) | 64.7% | 158 | 1,104 | 96 spare |
| **S3** + WIP hold (1 h, any WS) | **71.4%** | **143** | **1,001** | **199 spare** |

> **Why April–June, not the full dataset.** A larger export covering
> **January–August 2026 (199 plan dates)** exists and was run — on that full
> 8-month shape, **S1 alone had 113 trolleys to spare**, not 16 short, because
> the year's lighter months (February especially) pull the average down. That
> number was real, measured, and then **deliberately narrowed away** — not
> because it was wrong, but because showing all 8 months on the Simulation
> tab's interactive page (with same-MO sequencing now offering two distinct
> modes and a cutting-machine-count control, both explorable per plan date)
> did not fit inside a page-size budget that keeps the tool fast and fully
> offline. The trade-off — and the fact that April–June is measurably a
> **heavier** quarter than the 8-month average, so this headline is more
> cautious than the full-year one would be — is recorded in full in
> [Part 8 §4](#4-shipped--session-2026-09-08-8-month-data-cutting-machine-count-same-mo-sequencing-split-and-a-page-size-retreat-to-3-months).
> The aggregate headline table above and every sweep number are real,
> pooled `run()` output on the 79 April–June dates — nothing here is
> extrapolated or estimated to fit a narrative.

## Contents

- [Part 1 — The finding](#part-1--the-finding)
- [Part 2 — Running it](#part-2--running-it)
- [Part 3 — Task readiness statuses](#part-3--task-readiness-statuses)
- [Part 4 — What to distrust](#part-4--what-to-distrust)
- [Part 5 — Sensitivity — what is *not* the constraint](#part-5--sensitivity--what-is-not-the-constraint)
- [Part 6 — Change spec for ISD](#part-6--change-spec-for-isd)
- [Part 7 — Idle time](#part-7--idle-time)
- [Part 8 — Working notes](#part-8--working-notes)

---

## Part 1 — The finding

### The two problems

| | Question | Where |
|---|---|---|
| **Trolleys** | Do three rule changes bring the fleet requirement under 1,200? | this part, and [Part 6](#part-6--change-spec-for-isd) |
| **Idle time** | Why do spreading machines stand idle, and what fixes it? | [Part 7](#part-7--idle-time) |

**They are independent.** Every idle-time variant tested leaves trolley utilization at
53.6% and 228 trolleys/day. Never claim an idle-time saving for the three trolley
changes, or vice versa.

### Idle time does not move

None of the three changes touches it. Idle time is the spreader running out of table
(rule G6): it costs 1,997 machine-minutes a day and pushes a quarter of the spreading
machines past the end of their shift. The cause is that 24MC4 and 24MC5 each drive
three spreading machines with one cutter at 95% utilisation — and it takes both cutter
routing and longer tables to fix, neither on its own. Separate problem, separate
business case, written up in [Part 7](#part-7--idle-time). Do not claim an idle-time
saving for the three trolley changes.

### The data behind it

**20 plan dates, 1,863 tables.** If either number moves, something upstream changed.

Idle time at the real 21.2 m table: **1,997 blocked min/day**, 25% of machine-days
overrun their shift, last cut finishes **23:40**, cutter utilisation **95%**.

The three changes are written as implementable logic in
[Part 6](#part-6--change-spec-for-isd). What not to trust in any of these numbers is in
[Part 4](#part-4--what-to-distrust).

---

## Part 2 — Running it

### Running the build

**Two build paths exist. Python remains unavailable on the machine this
session ran on, so the Node path is the one that actually produced everything
in `out/` right now.**

**Real build (Python 3.9+, once installed):**

```bash
pip install openpyxl
python run.py          # rewrites everything in out/
```

**Node build (what actually ran this session — `python.exe`/`python3.exe` on
PATH are 0-byte Microsoft Store stubs, no `py` launcher):**

```bash
npm install             # xlsx (SheetJS) + jsdom, build-only devDependencies —
                         # neither reaches the shipped HTML
npm run build            # = node --max-old-space-size=6144 tools/build.js
npm run lab               # node tools/lab_table.js — the Rules Lab = model gate
npm run regress            # node tools/regress.js — the data-switch gate (reader check, on runCarry)
npm run parity             # node tools/parity_check.js — the page's loader against the model, in Edge
npm run beforeafter        # the staged before/after (SIM_SPEC.md §18)
```
(`npm run pin`, `warmstart` and `pullahead` were retired on 2026-11-09 with the cold start.)

The `--max-old-space-size=6144` flag is not optional — the source workbook is
23 MB and a default Node heap runs out reading it. ~24 seconds end to end.
It writes into `out/`:

| File | What it is |
|------|-----------|
| **`index.html`** | **Open this.** Copy of the most recent month's Simulation tab; the Utilization tab inside it already pools every plan date. |
| `sim-2026-04.html`, `sim-2026-05.html`, `sim-2026-06.html` | One file per month — see [§ Why April–June](#cct-trolley-model) above and [Part 8 §4](#4-shipped--session-2026-09-08-8-month-data-cutting-machine-count-same-mo-sequencing-split-and-a-page-size-retreat-to-3-months) for why only these three. Same Utilization-tab numbers in all three; the Simulation tab's per-day detail differs. |
| `results.xlsx` | Every scenario and every plan date, as a spreadsheet — **stale**, Python has not run since the 2026-08-26 build; regenerating it is one real `python run.py` away |
| `results.json` | The same numbers as the pages, machine-readable |
| `sweep.json` | What the dashboard's sliders read from |

`python idle_variants.py` regenerates the tables in [Part 7](#part-7--idle-time)
§3 and §4; that script is their only source, and — like `run.py` — has never
actually executed on this machine (see [Part 8 §4 HARD CHANGES](#4-hard-changes-before-a-new-session)).

#### In Antigravity

Open the folder, then run `npm run build` in the terminal (or `python run.py`
once Python is installed). To see the dashboard, right-click `out/index.html`
→ **Open Preview** (or open the file in a browser). It is a single
self-contained page — no server, no internet.

### Gates that must pass before publishing

- **`npm run lab`** — the Rules Lab engine equals `model.runCarry()` exactly
  (`SIM_SPEC.md` §17).
- **`npm run pin` — RETIRED 2026-11-09** (HISTORICAL: it was the Tier 1 hard gate against
  `out/*.bak`, the last genuine Python output, and it needed the cold-start model, now removed).
  The `.bak` files stay on disk, untouched; **no gate reads them**, so the project has no
  independent check against Python any more. The Part 8 traps 8–9 below describe the retired pin.
- **`npm run regress`** — the 18 plan dates shared between the old 20-date
  export and the new 199-date one must reproduce identically across all
  117 sweep scenarios (33,696 checks) on `runCarry()` — proves the data switch didn't also
  change the model. A reader check, not a check against Python.
- **`npm run parity`** — `tools/parity_check.js` opens each built month file
  in a real browser (Edge, via `playwright-core`) and calls the page's own
  `window.__SIM.__check()`: every plan date × every `full` variant (21.2 m at
  5 and 7 cutters) × every reachable (sequencing mode, batches, WIP hold,
  any-workstation) combination, comparing the page's `loadTrolleys()` port
  against the trace's `expected` block (built from `tools/model.js`'s
  `load_trolleys()` — two independent reimplementations, so not circular). As
  of 2026-09-08: **18,486 / 18,486 checks pass** across the three April–June
  files. This replaces the stale **4,680 / 4,680** figure (20 dates × 2
  sequencing modes × 3 table lengths — from before the 3-mode split and the
  cutter-count axis).
- 23 loading-port tests, **18** status/shift/clock tests, layout assertions,
  tags balanced, no external URLs, no `fetch(`.

Nothing publishes if the lab, regress or parity gate (or the Edge check) fails. Never hand-write
any file in `out/` — every one of them is a build artifact.

### The repo outranks the deck

Every number in `CCT_Trolley_Solution.pptx` and in the published report comes
from `out/results.json`. If a figure in a slide and a figure here disagree, this
repo is right — it is the thing that was actually run.

### Changing an assumption

Everything the model depends on is a named value in **`assumptions.py`**, with a
comment saying which rule it came from. Change a number, re-run `python run.py`,
and every output updates.

The three worth playing with first:

```python
CYCLE_DAYS_ESTIMATED = 7        # the round trip. AN ESTIMATE, NOT MEASURED.
WIP_HOLD_MINUTES = 60           # how long a part-filled trolley waits
MAX_BATCHES_PER_TROLLEY = 2     # the floor rule. never 3.
```

You don't have to edit files to explore — the dashboard has sliders for all of
these. Editing `assumptions.py` changes what counts as the *default*.

### What's in here

```
assumptions.py       every tunable value, with its rule reference
model.py             the simulation — read, sequence, time, load
scenarios.py         the four headline scenarios and the slider sweep
daytrace.py          per-day, per-table detail for the Simulation tab
run.py               runs everything, writes out/
dashboard.py         builds the HTML dashboard (one page template, all months)
idle_variants.py     regenerates Part 7 §2/§3/§4 and §4b (the cutter ladder)
RULES.md             the rulebook — every named rule (H1, G6, J2...) explained
data/
  PPC Planning - Old Data.xlsx   the CURRENT source — 199 dates, Jan–Aug 2026
  planppc.xlsx                    the ORIGINAL 20-date export — kept solely as
                                   tools/regress.js's fixture (and, until 2026-11-09,
                                   the retired tools/pin.js's), never read by a real build
tools/               Node mirror of the above, for when Python is unavailable
                   — see Part 8 §3 and §4 #2. Not the real build; `python
                   run.py` is. Run with `npm run build`; verify with
                   `npm run lab`, `npm run regress` and `npm run parity`.
  regress.js          the 18-shared-date gate (new, 2026-09-08; rebuilt on runCarry 2026-11-09)
  lab_table.js        the Rules Lab = model gate and comparison tables (`npm run lab`)
  before_after.js     the staged before/after (`npm run beforeafter`)
  carryover_probe.js  the model's lateness against the real Pull Date (`npm run carryprobe`)
  parity_check.js     the parity gate — drives window.__SIM.__check() in a real
                   browser across every month file (new, 2026-09-08)
  idle_variants.js    Node mirror of idle_variants.py — Part 7 §2/§3/§4/§4b
  tc_table.js         table T-C — the cutter axis's effect on trolley numbers
  (warmstart_table.js, pullahead_table.js and pin.js were deleted 2026-11-09 with the
                   cold start; their tables T-E and T-F below are HISTORICAL)
  csetup_verify.js    Type C setup-minutes determinism check (new, 2026-09-08)
test_csetup.py       cross-language check for the Type C hash — written,
                   never executed (no Python), see Part 8 §4
README.md            this file — the finding, how to run it, the ISD spec,
                   the idle-time analysis and the working notes
```

`SPEC_FOR_ISD.md`, `IDLE_TIME.md` and `CODE.md` were separate documents until
2026-08-26. They are now Parts 6, 7 and 8 of this file and the originals have been
deleted, so there is one place for every fact and nothing can drift out of step.

### The shifts

Everything in the model is minutes from **07:15**, the start of the day shift, so the
Gantt reads in real clock time.

| | Hours | Machines | Breaks | Working minutes |
|---|---|---|---|---|
| Day | 07:15–20:00 | all 13 spreaders, all 5 cutters | 11:45–12:45, 17:15–17:45 | 675 |
| Night | 18:00–05:00 | 24-01/02/03 and 24MC1 only | 22:00–22:30, 02:00–02:30 | 600 |

The two overlap 18:00–20:00, which adds no capacity — it is the same machine running
on. So a night-capable machine works **1,155 minutes**, a day-only machine **675**.
A task that meets a break pauses and resumes after it: machines stop for breaks
(`BREAKS_STOP_MACHINES`). These 675/1,155 figures replaced the wrong 660/1,200
constants an earlier version carried.

### The two tabs

Every month file (`out/sim-2026-0{4,5,6}.html`, and `out/index.html` as a copy
of the most recent) has two views, and — as of 2026-09-08 — the **Utilization**
tab's numbers are byte-identical across all three files, since that tab pools
every one of the 79 April–June plan dates regardless of which file it's opened
from.

**Utilization** is the aggregate answer — sliders for every assumption, pooled
over all 79 plan dates. This is where the headline numbers come from.

**Simulation** is one plan date at a time (from *this file's own* month —
switching months means opening a different file), drawn twice:

1. **Job Sequence** as a Gantt. `SPD` rows for the spreading machines — always
   13 — and under each cut group a `CUT` row for the machine that serves it —
   5, 6, 7 or 8, driven by the **"Cutting machines" control** in the left rail
   (`sim.cutters`), which redraws the whole cut-group layout, not just the row
   count. 5 and 7 cutters redraw the Gantt in full; 6 and 8 (and the 24 m / 27 m
   table lengths) ship as idle-time numbers only, with the chart left on the
   5-cutter sequence — see [Part 8 §4](#4-shipped--session-2026-09-08-8-month-data-cutting-machine-count-same-mo-sequencing-split-and-a-page-size-retreat-to-3-months).
   Each table gets a bar for its estimated spreading time and a second bar for
   its cutting time. The **same-MO sequencing** control **is** live and is now
   a 3-way choice —
   *Off*, *Same batch only*, *Cross-batch* — not the Off/On toggle this page
   used to have; see the same §4 for why the middle option exists and what it
   fixed. Selecting anything but *Off* makes pairs appear as brackets —
   tables that were scattered across three machines land back-to-back on one.
   Hatching is blocking (rule G6). Bars are coloured by readiness — see
   [Part 3](#part-3--task-readiness-statuses) — and the axis now spans the
   full two-shift window (07:15 to the next day's 05:00) with a day/night
   staffing ribbon, so work that finishes on the second shift is visible on
   the chart instead of falling off the end of it.
2. **Panel Loading** — collapsed by default. The same day's panels going into
   compartments and trolleys, with a row per trolley showing how full it left and
   which tables it carries.

Between them sits the day's task list, and in the left rail the three changes,
the cutting-machine count, and the spreading-table length from
[Part 7](#part-7--idle-time). The rail scrolls on its own once every card is
open, without moving the page.

The Simulation tab recomputes the loading stage in the browser so the controls respond
instantly. To stop that port drifting from `model.py`, the page checks its own
arithmetic against Python's for the same day and settings and says so on screen. If
that badge ever goes red, believe `run.py`.

### How the model works

Four stages, in `model.py`:

1. **Read** — each Plan Date in `HaveCut` becomes one day of tables. Type B
   only, `First Table = Y` excluded (rule J2). Kids and number-size markers stay
   in the timeline because they occupy machines, but carry no compartment maths
   (rule J3).
2. **Sequence** — the planner assigns tables to the 13 spreading machines in an
   order. Today it scatters a batch across the 3 machines of a cut group;
   change 1 pairs same-MO tables and keeps each pair on one machine.
3. **Time** — spreading and cutting run against the real shifts and breaks. Blocking
   (rule G6: the spreader waits for table to come free, and the lay in front gives its
   length back gradually as the cutter eats it) and cutting-machine contention fall
   out of this. See [Part 7](#part-7--idle-time).
4. **Load** — cut panels go into compartments and trolleys. With WIP hold on, a
   part-filled trolley parks instead of leaving, and may be recalled.

**Stages 2 and 4 are deliberately separate, and that separation is the finding.**
The combine rule can only act on tables that are already back-to-back. Today's
sequencer rarely makes them back-to-back. That is why fixing the loading rule
alone was worth only +0.6 points in the July run — there was nothing for it to
act on.

---

## Part 3 — Task readiness statuses

The colour a task carries in the Auto Planning System when the day is sequenced.
These are the floor's own eight colours and their meanings; the Simulation tab
draws each table in the colour its condition earns.

| | Colour | Status | What it means | Where the model gets it |
|---|---|---|---|---|
| 1 | `#9bc2e6` pale blue | **Normal condition** | Fabric relaxed 24 h **and** pattern + cutting marker are in the planning module | everything below is satisfied |
| 2 | `#833c0c` brown | **Normal · cut queue** | A normal task that was queued **by hand**, not by the system | **not simulated** — manual intervention is outside the model |
| 3 | `#ffd966` amber | **Normal · stretch spreading** | The last task on a fabric batch, spreading the last few hundred yards. Always at the end of a batch, never in between | the batch's final table by `Pull Date` |
| 4 | `#a9d08e` green | **No pattern, enough fabric** | Fabric relaxed, but no pattern in the planning module | `Marker Date` is empty |
| 5 | `#f4b084` orange | **Have pattern, not enough fabric** | Pattern is in, but the fabric has not relaxed long enough | the relax simulation, below |
| 6 | `#7030a0` purple | **No pattern, not enough fabric** | Neither condition met. The planner normally holds these back until they qualify | both of the above |
| 7 | `#305496` navy | **No fabric** | No fabric information in the system at all. Should not happen | **never fires** — `Lot` and `Batch No` are filled on all 2,717 rows |
| 8 | `#d9d9d9` grey | **Completed** | Spreading and cutting finished | the **simulated** `cut_end` is at or before the tab's time cursor (was `Pull Date` before 2026-09-08 — see below) |

Priority runs bottom-up: finished work is grey whatever else was true of it, and
**stretch spreading only qualifies a task that is otherwise normal**.

### Where each one actually comes from

- **Pattern** — the marker ratio (`S/3,M/2,L/3`), which is filled in at latest 1.5 h
  after the plan is uploaded, so in practice it is never the constraint. Every one of
  the 1,863 modelled tables has one — the 852 rows with no `Marker Date` are all Type
  C or first-table rows that rule J2 already excludes — so statuses 4 and 6 do not
  fire here. Kept in the legend because the planning system still shows them.
- **Completed** — the **simulated `cut_end`**: a table greys once the model's own
  clock says its spreading *and* cutting have finished, so the bar and its grey
  agree on one timeline. This changed on **2026-09-08** (Part 8 §4 D3): the bar
  is drawn from the simulated schedule, but it used to grey against the *actual*
  `Pull Date` — two different clocks on one axis, which is why "tasks don't turn
  Completed" was the bug report. `Pull Date` (the **actual finished-spreading
  timestamp**, which sits after the Plan Date on 98.7% of rows) is deliberately
  kept *off* the chart now — no "actually finished" column or tick — but its
  dataset-wide slip statistic still appears under the Gantt (`DATA.slip`), and
  Part 4 still leans on it.
- **Stretch spreading** — the last table of each `Batch No`, ordered by `Pull Date`.
- **Fabric relaxing** — **a proxy, not a measurement.** See below.

### Relaxing is a precondition, not a variable

Fabric must relax **24 hours** before it may be spread. A table is not released to the
floor until that is satisfied, so the simulation treats every planned table as
relaxed and statuses 5 and 6 read zero. They stay in the legend because the planning
system still shows them. A "fabric issued ahead" slider was built and then removed for
this reason.

**Stretch spreading covers 823 of 1,863 tables (44%)** — batches average 2.26 tables,
so being the last table of a batch is common rather than exceptional.

---

## Part 4 — What to distrust

Read this before quoting any number from here.

### Measured vs assumed

The distinction the whole project turns on.

| Value | Status | Note |
|---|---|---|
| `SPREADING_TABLE_LENGTH_M = 21.2` | **measured** | user, 2026-08-26 |
| Shift hours and breaks | **measured** | user, 2026-08-26 |
| `Marker Date`, `Pull Date`, marker ratios, layers | **measured** | from `HaveCut` |
| `CYCLE_DAYS_ESTIMATED = 7` | **estimate** | never timed; the trolley case turns on it |
| `C_TABLE_EXTRA_MINUTES = 10` | **estimate** | rule N |
| `MACHINE_FILL_TARGET = 0.70` | planning heuristic | not a written rule; used by S1–S3's dispatcher only (the real Job Sequence has none) |
| Night shift starts 18:00 (`NIGHT_SHIFT = (645, 1305)`) | **measured** | user, 2026-11-09; moves no published number (the night machines' window runs on from 07:15) |
| `CUT_SETUP_MO_COLOR_MINUTES = 5`, `CUT_TRAVEL_MINUTES = 1.5` | **ESTIMATE** | cutter changeover and moving, in the published floor since 2026-11-09; never timed |
| Relaxing arrival window, 12–48 h before a batch's first plan date, then 24 h | **ESTIMATE** | in the live floor since 2026-11-10; the data has no arrival or relax-start time |
| `Marker Date` as a readiness gate | measured data, **assumed use** | always before `Pull Date`; the floor starts no table before it |
| `ORDER_TYPE_PRIORITY` (SQR, QR, Normal) | **ESTIMATE** | the SQL's commented-out older rule; the live `Job_Seq_Schedule_Priority` was not supplied |
| The cutter takes the lay that has waited longest | **ESTIMATE** | stand-in for the operator's free choice (user: "prioritise longest wait first") |
| `REPLAN_MINUTES = 30`, `PLAN_HORIZON_HOURS = 24` | user rules | the Job Sequence re-plans every 30 min for the next 24 h, all shifts |
| Machine speed factor | **removed** 2026-11-09 | was an ESTIMATED 0.80; the model runs at the G2 standard pace |
| Component, real Net_Rate | **absent** | see [Not in the data](#not-in-the-data) |

### The trolley case

- **The 7-day round trip is an estimate, not a measurement.** It is the single
  number the whole business case turns on, and nobody has timed it. At the
  5-day allowance today needs 1,138 trolleys and *does* fit. Measuring the real
  cycle for one week is the cheapest and highest-value thing on this list.
- **Nobody has costed how a parked trolley reaches a different workstation.**
  Change 3 assumes it can. If it can't, change 3 is worth +0.5 points instead of
  +5.9. See [Part 6 §4](#4-change-3--wip-hold-and-recall).
- **Half the tables do not finish spreading on the day they were planned for.**
  `Pull Date` is the actual finished-spreading timestamp. Across the 1,863 tables in
  the export, **49% finish after their plan date and 14% more than a day late** — but
  the median table finishes about **23 minutes before midnight** on its plan date, so
  the typical table is not late at all. "Median slip is a day" was an error; do not
  repeat it. The lateness is in the tail: of the **912 tables that do run late, half
  slip more than half a day** (median 0.53 days), and the mean slip among them is 0.90
  days. That is counted from the data, not inferred. Every day the model runs is a
  *planned* day; the sequence it produces is what the plan asks for, not what the floor
  did. The Simulation tab's time cursor runs for **up to three days** from 07:15 on the
  plan date, which covers most of that tail but not all of it — on 12 of the 20 dates
  some work still finishes past the end of the slider, and 2026-05-18's latest actual
  finish is **8.3 days** out. The cap is a deliberate trade: a slider long enough for
  the worst date would be too coarse to be useful on any of them.
- **Breaks are assumed to stop the machines.** If relief staffing keeps them running,
  `BREAKS_STOP_MACHINES = False` is worth about 150 minutes a machine a day.
- **C-table spreading time is estimated at 10 minutes** (rule N).
- **Shrinkage and shade-lot data are missing**, so batch merging *at spreading*
  is untested. This model only merges batches at *loading*.
- **Modelled volume is ~68,700 pieces/day on trolleys**, below the ~90,000 total,
  because non-universal markers are excluded from compartment maths.
  Utilization is a ratio and holds regardless; the absolute trolleys-per-day
  figures are therefore conservative.

### The idle-time case

- **Cutting-machine travel time is not modelled.** A cutter moves between the 2–3
  spreading machines it serves; the model charges only the cut itself. Real blocking is
  therefore likely to be **worse** than 1,997 minutes, and the case for fixing the
  routing is stronger, not weaker.
- **The lay is assumed to need its full length free before it starts**
  (`LAY_NEEDS_FULL_LENGTH`). In reality the spreader lays progressively and only needs
  the space to arrive as it goes, so this is conservative.
- **No end allowance per lay.** A lay is charged exactly its marker length; in practice
  there is a small gap at each end.
- **21.2 m is one number for all 13 tables.** If they differ, the machines with shorter
  tables carry more of the blocking than this shows.
- **Extending a table assumes the floor space exists.** Nobody has checked whether
  24-08 to 24-13 have room to grow. This is the open question the second recommendation
  in [Part 7 §4](#4-what-fixes-it) turns on.
- **HISTORICAL (cold-start model, retired 2026-11-09; no longer reproducible; the
  published model carries work over from the day before).** Every plan date was a
  closed simulation — all 13 spreaders and 5 cutters started
  empty at 07:15. So the ~2 h the cutters sit idle at the head of the Gantt is an
  artefact: 16% of the staffed cutter window pooled (S0), matched by ~14% of work
  dumped past shift end — a reshuffle, not lost time, and total cut-minutes are
  conserved. A warm start seeded from the model's own prior plan date moves headline
  numbers <0.5 pt (table T-E, `tools/warmstart_table.js`); a realistic one would need
  the actual `Pull Date` backlog, which the model does not carry. That same test
  showed the deferred-spreading backlog converges — the 51% `Pull Date` slip is **not**
  a spreading-capacity shortfall in the model's terms.

### Not in the data

Checked directly — do not plan around these.

- **No `Net_Rate` column.** All 66 `HaveCut` headers and 13,136 shared strings searched.
  Columns AY–BE (100–160) are kids number-sizes. The model uses the H5 mapping instead
  (90 = XXS–S, 100 = M/L, 110 = XL–4XL). Real Net_Rate varies by style and puts *more*
  sizes on one film, which would make these results **better**, not worse — so the
  numbers here are conservative on that axis. The real system should read Net_Rate, not
  the H5 mapping.
- **No component.** Not present in the HaveCut export, so the simulation treats each
  table as a single component set. Combine condition 1a-4 and come-back condition 1b-4
  must still be enforced in the real system. Rule L6 says one component is normally
  printed and front/back usually share Net_Rate, so the effect is probably small — but
  it is unverified.
- **No fabric arrival or relax-start time.** The model assumes the 24-hour relaxing
  rule is met, because a table is not released until it is. It cannot tell you how
  often that assumption fails in practice.
- **`Cut Date` is empty** (1 row of 2,717).
- **`Marker Date` missing on 852 rows — all excluded by rule J2 anyway.**
- `Pull Date` is the **actual finished-spreading timestamp**, not a plan.

---

## Part 5 — Sensitivity — what is *not* the constraint

Two obvious suspects were tested and neither is binding:

| Constraint | As written | Relaxed to | Gain |
|---|---|---|---|
| Trolleys per combine | ≤4 (H8) → 65.4% | no cap → 66.1% | +0.7 |
| Tables per trolley set † | pairs → 65.3% | any chain → 65.8% | +0.5 |
| Both together † | 65.3% | 68.4% | +3.1 |

† **These two rows come from an earlier variant of the model that no longer exists
in this repo, and cannot be regenerated from it.** `_loading_events` pairs on
`seq[i], seq[i+1]`, so a chain of arbitrary length would need a new `Scenario`
field and a loop to measure. Their 65.3% baseline is the pre-correction figure —
today's S2 is 65.4%. Read them as direction, not as current numbers. The
trolleys-per-combine row was regenerated today: `MAX_TROLLEYS_PER_COMBINE` is a
plain constant in `assumptions.py`, so removing the cap is a one-line change.

The binding constraint is **adjacency** — two tables can only share a trolley if
they are spread back-to-back at one workstation. That is why change 1 (which
creates adjacency) and change 3 (which removes the need for it) are worth far
more than raising any cap.

### Ruled out, with the numbers that killed it

Do not re-propose these without new information.

| Idea | Result |
|---|---|
| Raising the ≤4 trolleys-per-combine cap (H8) | +0.7 points — first row above |
| Chaining more than two tables per trolley set | +0.5 points — second row above |
| Change 2 without change 1 | +0.6 points — the combine rule needs adjacency to act on |
| Cutter flexibility alone (idle time) | Helps, but cannot create cutting capacity. Numbers in [Part 7 §4](#4-what-fixes-it) |
| Tuning `MACHINE_FILL_TARGET` | 0.60 and 0.85 both worse than 0.70 |
| Balancing cut groups by capacity not spreader count | fewer overruns but a longer day, because it pushes work onto the night machines |
| "Fabric issued ahead" slider | relaxing is a precondition; every planned table is already relaxed |
| Net_Rate scheme switcher | Net_Rate is universal, H5 only |
| Slot-count blocking model | overstates blocking by 63% — [Part 7 §1](#1-what-the-hatching-is) |
| A cold start (every plan date empty at 07:15) | user, 2026-11-06 and 11-09: "there will never be a cold start"; the closed-day model was removed |
| A machine speed factor | user, 2026-11-09: "if it doesn't related to anything, then remove it"; no script reproduces its calibration |
| The cutter stays at one spreader to cut both tables of a pair | user, 2026-11-09: the cutter always moves between spreaders, because the others are waiting too; rule (a) is a trolley rule, not an output rule |
| The Lab's Dynamic spreader pick | user, 2026-11-10: removed; the floor is live in every scenario instead |
| Keep same colour close | user, 2026-11-10: "I never want to keep same color close"; tables are arranged in pairs |
| 2 batches per trolley as a rule to adopt | user, 2026-11-09; the old S2/S3 stay in the published table as reference |
| Re-planning every 30 min without pinning a started pair's partner | S1 fell to 51.97% against 58.19% with the pin; **unsourced: a scratch run, no repo script reproduces it** |

**The binding constraint on trolleys is adjacency.** On idle time it is the
spreader-to-cutter ratio: cutting is 47% of spreading time, so one cutter sustains
~2.1 spreaders; 24MC4 and 24MC5 run three each at 95% cutter utilisation.

---

## Part 6 — Change spec for ISD

**For:** ISD, to implement in the Auto Planning System
**Scope:** Central Cutting only — Job Sequence, Cutting & Panel Loading
**Status:** simulated on 20 plan dates of real HaveCut data; not yet piloted

This part says what to build. The reasoning and the numbers are in
[Part 1](#part-1--the-finding) and `out/dashboard.html`.

### 0. Summary

Three changes, in the order they should be built. Each one is worth something on
its own, and each depends on the one before it. Fleet impact is in the headline
table at the top of this file.

| # | Change | Where | Utilization |
|---|--------|-------|-------------|
| — | Today | — | 53.6% |
| 1 | Job Sequence places same-MO tables back-to-back | Job Sequence | 59.4% |
| 2 | A trolley may carry 2 fabric batches | Panel Loading combine rule | 65.4% |
| 3 | A part-filled trolley waits in CCT WIP and is recalled | Panel Loading + WIP | 71.3% |

**Change 2 without change 1 is worth almost nothing** (+0.6 pt in the July run).
The combine rule can only act on tables that are already adjacent, and today's
Job Sequence rarely makes them adjacent. Do not ship 2 without 1.

### 1. The rules as they are today

From `Job Sequence / Panel Loading Suggest Logic`, current logic.

#### 1a. Combine requirements (trolleys of task X wait for task A)

| # | Condition | Change |
|---|-----------|--------|
| 1 | Continuously spread at 1 WS | **KEEP** — physical, the trolley must still be standing there |
| 2 | Same MO | KEEP |
| 3 | **Same batch** | **RELAX** → change 2 |
| 4 | Same component | KEEP |
| 5 | Same film code | KEEP |
| 6 | Trolleys still have empty compartments | KEEP |
| 7 | Current task needs ≤ 4 trolleys | KEEP (rule H8) |
| 8 | Trolleys still have empty compartments | KEEP (duplicate of 6) |
| 9 | **Trolley may wait only if tasks are spread and cut continuously at 1 WS without the cutting MC changing WS** | **REMOVE** → change 3 |

#### 1b. Come-back requirements (trolleys return from CCT WIP)

| # | Condition | Change |
|---|-----------|--------|
| 1 | Same MO | KEEP |
| 2 | **Same batch** | **RELAX** → change 2 |
| 3 | Same colour | KEEP |
| 4 | Same component | KEEP |
| 5 | Same film code | KEEP |
| 6 | Trolleys still have empty compartments | KEEP |

### 2. CHANGE 1 — Job Sequence: same-MO adjacency

#### What happens today

Job Sequence clusters by MO + colour + batch, then distributes that cluster
across the 3 spreading machines of one cut group (flowchart 3.3a). Two tables
that *could* share a trolley end up on different machines, so combine condition
1 is almost never satisfied.

#### What to build

Cluster by **MO + colour** (drop batch from the cluster key), **only to find the
pairs**. Pair tables up *before* assigning them to a machine, then take every pair
and lone table of the whole day as one list of units and assign each unit to a cut
group over the **whole floor**, and each pair to **one** machine as **consecutive**
entries in that machine's queue. The user's words (2026-11-09): "Pair first, count
tasks and takt time by pairs, then maximise cutting-machine output; distribute
back-to-back, not a whole MO to one cut group." This is what the model has done
since 2026-11-09 (`sequencePairs`); the earlier reading, where a whole MO + colour
cluster went to one cut group, is kept as the option **"keep an MO on one cut
group"** (`sequenceMoAware`, SIM_SPEC.md §5).

```
day_units = []
FOR each cluster of tables sharing (MO, colour):
    sort tables by (batch, descending spread_time)
    units = []
    taken = {}

    # PASS 1 — pair same-batch tables first  (stated priority)
    FOR i IN tables:
        IF taken[i]: CONTINUE
        FOR j IN tables AFTER i:
            IF taken[j]: CONTINUE
            IF batch[i] != batch[j]: CONTINUE
            IF NOT can_combine(i, j): CONTINUE
            units.APPEND([i, j]); taken[i] = taken[j] = TRUE; BREAK

    # PASS 2 — then pair different batches of the same MO
    FOR i IN tables:
        IF taken[i]: CONTINUE
        FOR j IN tables AFTER i:
            IF taken[j]: CONTINUE
            IF batch[i] == batch[j]: CONTINUE
            IF NOT can_combine(i, j): CONTINUE
            units.APPEND([i, j]); taken[i] = taken[j] = TRUE; BREAK

    units += [[t] for each unassigned table]
    day_units += units

# assign whole units over the whole floor, never splitting a pair across machines
FOR unit IN day_units SORTED BY total spread_time DESC:
    # the cut group whose BUSIER side (spreaders or cutter) stays least loaded;
    # the cutter side starts from what the cutter still has to cut at the day's start
    cut_group = ARGMIN over cut groups g of
                  MAX( (spread_load[g] + unit.spread) / spreader_minutes[g],
                       (cut_load[g]    + unit.cut)    / cutter_minutes[g] )
    machine = least_loaded_machine_with_room(cut_group, unit.spread_time)
    machine.queue.EXTEND(unit)        # <-- consecutive. this is the point.
    spread_load, cut_load of machine's real cut group += unit.spread, unit.cut
```

**The one thing that must not be lost:** `machine.queue.EXTEND(unit)` appends both
tables of a pair adjacently to the same machine. If a later load-balancing pass
splits pairs across machines, change 1 is undone and changes 2 and 3 lose most
of their value.

#### Guard rails

- Machine capacity: a machine's queued spreading minutes should not exceed
  ~70% of its staffed window; the remainder absorbs blocking (rule G6).
  If a pair does not fit, place it on another machine in the same cut group —
  do not split it.
- Batch relaxing (24h per batch) still gates whether a table is releasable at
  all. Change 1 reorders releasable tables; it does not release them early.

### 3. CHANGE 2 — Panel Loading: two batches per trolley

#### What to build

Drop **combine condition 3** and **come-back condition 2** ("same batch").
Add one new constraint in their place:

```
MAX_BATCHES_PER_TROLLEY = 2      # hard limit. never 3.
```

Compartment rules do not change:

- a compartment still holds **one batch only** (rule H4)
- a compartment still holds **one size only**
- a trolley still holds **one film size only** (rule H4)
- recut and CPI still work compartment by compartment (rules L2, L3)

So a trolley may carry batch A in compartments 1–3 and batch B in compartments
4–5, and **never** a third batch.

```
FUNCTION can_combine(a, b, allow_cross_batch):
    IF NOT a.needs_trolleys OR NOT b.needs_trolleys:  RETURN FALSE
    IF a.mo    != b.mo:        RETURN FALSE      # cond 2 — unchanged
    IF a.color != b.color:     RETURN FALSE      # cond 4 — unchanged
    IF a.component != b.component: RETURN FALSE  # cond 4 — unchanged
    IF a.film  != b.film:      RETURN FALSE      # cond 5 — unchanged
    IF a.batch != b.batch AND NOT allow_cross_batch:
        RETURN FALSE                             # cond 3 — RELAXED HERE
    IF trolleys_needed(combine(a, b)) > 4:
        RETURN FALSE                             # cond 7 — unchanged (H8)
    RETURN TRUE
```

#### Compartment merging

When the two tables share a batch, their pieces of the same size **merge** into
one compartment if the total is ≤ 150 (Panel Loading Logic rule 2). When the
batches differ, compartments stay separate — the saving comes from sharing the
*trolley*, not the compartment.

```
FUNCTION combine(a, b):
    IF a.batch == b.batch:
        RETURN compartments_for(a.pieces + b.pieces)     # merged
    ELSE:
        RETURN compartments_for(a.pieces)
             + compartments_for(b.pieces)                # side by side
```

#### Display requirement

Rule L3 already requires compartment-level information. With two batches on one
trolley this stops being optional: the operator, CPI and recut must all be able
to see **which batch is in which compartment**. If the system can only show
batch at trolley level, change 2 cannot ship.

### 4. CHANGE 3 — WIP hold and recall

This is the largest single gain and the one with a real open question attached.

#### What happens today

Condition 9: a trolley may only wait if the cutting machine never leaves the
workstation. In practice the cutting machine travels between 2–3 spreading
machines constantly, so the trolley almost never gets to wait. It leaves
part-filled and is gone for the whole round trip.

#### What to build

Remove condition 9. Replace it with a **hold-and-recall** cycle:

```
STATE: parked_trolleys — trolleys with free compartments, waiting in CCT WIP
       keyed by (MO, colour, component, film_size)

ON a table finishing cutting:
    # 1. expire anything that has waited too long
    FOR trolley IN parked_trolleys:
        IF now - trolley.parked_at > WIP_HOLD_MINUTES:
            DISPATCH trolley                     # give up, send it on

    # 2. try to fill from what is already parked
    key = (table.mo, table.colour, table.component, table.film_size)
    FOR trolley IN parked_trolleys[key]:
        IF trolley.batches ∪ table.batch has more than 2 batches: SKIP
        RECALL trolley to this workstation
        load as many compartments as fit
        IF trolley now full: DISPATCH it

    # 3. open new trolleys for whatever is left
    WHILE compartments remain unloaded:
        open a new trolley, load up to 5 compartments
        IF it leaves with free compartments AND WIP_HOLD_MINUTES > 0:
            IF count(parked_trolleys) < TROLLEY_BAYS:
                PARK it in CCT WIP, stamp parked_at = now
            ELSE:
                DISPATCH it                      # no room to park
```

#### Parameters

| Parameter | Value | Why |
|-----------|-------|-----|
| `WIP_HOLD_MINUTES` | **60** | 1 hour. 2 hours is worth more (75.4% vs 71.3%) but ties up trolleys longer. Start at 60. |
| `TROLLEY_BAYS` | **52** | 13 workstations × 4 positions (rule H7). Never exceeded in any simulated run — but enforce it anyway. |
| `MAX_BATCHES_PER_TROLLEY` | **2** | From change 2. |
| Match key | MO + colour + component + film size | Batch is deliberately **not** in the key. Everything else is. |

#### The open question ISD cannot answer alone

The recall in step 2 sends a parked trolley to **whichever workstation** next
cuts a matching table — not necessarily the one it came from. That distinction
is most of the value:

| Recall rule | Utilization | Trolleys/day |
|-------------|-------------|--------------|
| No hold | 65.4% | 182 |
| 1 h, **same workstation only** | 65.9% | 181 |
| 1 h, **any workstation** | **71.3%** | **167** |

Same-workstation-only recall is worth +0.5 points — effectively nothing, because
the same workstation rarely runs a second matching table within the hour.

**So before this is built, someone from Production has to answer: how does a
parked trolley physically get from CCT WIP to a different workstation?** Labour,
AGV, or manual push. If moving it is slow or expensive, the benefit collapses
toward the 65.9% figure and change 3 may not be worth building.

### 5. Data the model reads

Everything below comes from the `HaveCut` sheet of PlanPPC.

| Field | Used for |
|-------|----------|
| `Plan Date` | grouping tables into days |
| `Type` | only `B` tables are loaded; `C` adds 10 min setup to its B table |
| `First Table` | `Y` is excluded (rule J2) |
| `Table No` | matching C tables to their B table |
| `MO` | combine condition 2, recall key |
| `Color` | combine condition 4, recall key |
| `Batch No` | combine condition 3 — the one being relaxed |
| `Marker Ratio` | pieces per size → compartments |
| `Act LayerQty` | pieces per size, and spread/cut time |
| `Marker Length` | spread/cut time |

Two fields the model does **not** have — component and real Net_Rate — are covered in
[Part 4 § Not in the data](#not-in-the-data), together with what the real system must
do about them.

### 6. What to log once it is live

The simulation is only as good as its assumptions. Four numbers would replace
guesses with facts:

1. **Trolley round-trip time** — dispatch from Panel Loading to return. This is
   currently an *estimate* of ~7 days against a 5-day allowance, and it is the
   single number the whole business case turns on.
2. **Compartments loaded per trolley** at dispatch, and **garments per
   compartment** — the direct measurement of utilization and of fill, which
   today nobody records. The pair matters together: utilization alone cannot
   tell a reader whether a trolley left part-opened or opened-but-part-full,
   and this model has already had to explain that difference once (Part 8 §3).
3. **How often a recall is possible** but the trolley cannot be moved — this
   measures the cost of the open question in section 4.
4. **Combine fire rate** — how many combines actually fire per day, before and
   after. The July run predicted a jump from 37 to 370.

### 7. Reproducing the numbers

`python run.py` reads `data/planppc.xlsx` and writes everything in `out/`. The full
instructions and the gates that must pass are in
[Part 2 § Running the build](#running-the-build).

---

## Part 7 — Idle time

> **HISTORICAL (cold-start model, retired 2026-11-09; no longer reproducible).** The
> figures in this part were measured on the closed-day model and the 20-date export. They
> are kept as the record of the analysis. `npm run idle` now prints carry-over figures
> (199 dates) with the cold-start ones beside them, marked HISTORICAL.

**Question:** the Job Sequence Gantt is covered in hatching. What is it, what does it
cost, and what removes it?

**Answer in one line:** the spreader has run out of table. It costs **1,997
machine-minutes a day** and pushes a quarter of the spreading machines past the end of
their shift — and the root cause is a ratio, not a length: **24MC4 and 24MC5 each drive
three spreading machines with one cutter, at 95% utilisation.**

Measured on the same 20 plan dates as everything else, under the real shift model
(07:15–20:00 and 18:00–05:00; breaks are deducted from each machine's staffed
window and from the spreading-work figures — see
[Part 2 § The shifts](#the-shifts). Blocked minutes treat breaks differently; see
the blocked-minutes basis note below). The tables in sections 2, 3 and 4 are
regenerated by **`python idle_variants.py`** or its Node mirror
**`node tools/idle_variants.js`** — those two scripts are their only source.

> **Scope note (2026-09-08).** The §2–§4 figures below are still the **original
> 20-date** numbers. `idle_variants.py` has never run on this machine (no
> Python), and its new Node mirror `tools/idle_variants.js` reads the **full
> 199-date** file (unscoped, deliberately — see [Part 8 §5 #4](#4-idle_variantspy-and-test_csetuppy-have-never-run)),
> so its output is on a different basis: on 199 dates the "Today" row is
> **1,563 blocked min/day, 16% over window, last cut 21:15** (not 1,997 / 25% /
> 23:40), and §3's saturated cutters sit at ~81%, not 95%. Neither number is
> wrong — they are different date ranges. §2–§4 will move to the 199-date basis
> the next time either script is run against it; they are left as-is here so
> nothing is quietly restated without a before/after. §4b below is already on
> the 199-date basis.
>
> **Blocked-minutes basis.** The "blocked minutes" figures here and in §3/§4 are
> the **raw rule-G6 wait** on the wall clock. When a wait crosses a break or runs
> past a machine's shift end, those unstaffed minutes are banked into the number —
> it is not clamped to staffed time. The Simulation tab's Gantt hatches only the
> **staffed** part of the same wait, so the drawn hatching runs about **16% below
> the minutes total** on a typical plan date (10–22% depending on the date; 18%
> across the whole June month — 42,071 hatched vs 51,200 blocked min). The blocked
> *percentage* denominator is `busy + blocked`, never staffed time, so the
> percentage is unaffected.

### 1. What the hatching is

A spreading table is **21.2 m**. A lay occupies its marker length on that table — the
median marker is 8.8 yd, so roughly **2.4 lays fit**. When the next lay does not fit,
the spreader stops.

Crucially, **the space comes back gradually.** As the cutting machine works, the lay in
front is fed toward it and consumed, so table frees up continuously through the cut —
not in one step when the cut finishes. The model does it that way:

```python
SPREADING_TABLE_LENGTH_M = 21.2    # measured
```

This matters a lot. An earlier version of this model treated the table as two discrete
slots that emptied only at cut-end, and **it overstated blocking by 63%** — 3,259
minutes a day against the true 1,997. If you have seen the higher figure quoted, it is
wrong.

Both figures are today's sequencer, so the comparison is like for like. The number
published before this document was rewritten was 3,244, and that one came out of the
*old* round-robin sequencer — quoting it against today's 1,997 would straddle two
generations of the model.

### 2. What it costs

| | Per day, across 13 spreading machines |
|---|---|
| Actual spreading work | 6,382 min |
| Lost to blocking | **1,997 min** — 33 machine-hours |
| Machine-days over their staffed window | **25%** |
| Last cut of the day finishes | **23:40** |

Staffed windows are 675 min for a day-only machine and 1,155 min for 24-01/02/03,
which also run nights.

### 3. Where it concentrates — and why

| Cut group | Spreaders | Cutter busy | Blocked / day | Spreading / day | Blocked / work |
|---|---|---|---|---|---|
| 24MC1 | 3 | 55% *(runs nights)* | 348 min | 1,831 min | 19% |
| 24MC2 | 2 | 82% | 182 min | 912 min | 20% |
| 24MC3 | 2 | 77% | 299 min | 911 min | 33% |
| **24MC4** | **3** | **95%** | **590 min** | **1,365 min** | **43%** |
| **24MC5** | **3** | **95%** | **577 min** | **1,363 min** | **42%** |

Blocked and spreading minutes belong to the cut group's own spreading machines; the
cutter-load column belongs to the cutter that actually ran the table, which under rule
F8 is not always its own group's.

The table header above is generated by `idle_variants.py` / `tools/idle_variants.js` and
still reads **Cutter busy**; that is the same number the Simulation tab now labels
**Cutter load**.

The columns, once:

- **Spreaders** — spreading machines in the cut group.
- **Cutter load** (page) / **Cutter busy** (script header above) — the minutes of cutting
  the day's tables need, as a share of that cutter's staffed day (675 day-only, 1,155 for
  the night-capable 24MC1). A workload ratio, not a clock reading: it does not track *when*
  the cutting happens and can exceed 100% on a day whose tables need more cutting than the
  shift holds. Credited to the cutter that actually ran each table, F8 included.
- **Blocked / day** — minutes the group's spreading machines stood still with no free
  table (rule G6). Raw wall-clock wait — see the basis note at the top of Part 7.
- **Spreading / day** — minutes those machines spent laying fabric, including the 8–10 min
  Type C setup (rule G3).
- **Blocked / work** — blocked ÷ spreading, minutes lost per 100 minutes spread.

This table is an **average across the full 199-date file**; the Simulation tab's idle-time
table is a **single plan date**, so the two do not match cell-for-cell.

Blocking tracks **cutter utilisation**, not table length. The structural number:

> **Cutting takes 47% of spreading time.** One cutting machine can therefore sustain
> about **2.1 spreading machines.**

24MC4 and 24MC5 have three each. Their cutters sit at 95% of a day shift, and at 95%
utilisation queues are a mathematical certainty, not bad luck. 24MC1 also carries three
but runs nights, so the same work has 1,155 minutes to spread into instead of 675 —
and it sits at 55%. It spreads *more* than either saturated group, 1,831 min/day
against 1,365, and loses 19% of that to blocking where they lose 43%.

**A longer table cannot create cutting capacity.** It is a buffer: it absorbs
variation, and once it is full the queue simply sits somewhere else. That is a real
limit on what it can do — but section 4 measures how much variation there is to absorb,
and the answer is: enough that the table matters as much as the routing does. Neither
change on its own gets the over-window share below about 14%.

### 4. What fixes it

Blocking is per day across all 13 machines; "over window" is the share of machine-days
that overrun their shift. The neighbour-routing rows extend rule F8's own shape — the
last spreading machine of a group may also call the next group's cutter — to 24-10
(→ 24MC5) and 24-13 (→ 24MC1, because the numbering wraps). `idle_variants.py` states
that routing explicitly; an earlier version of this table quoted neighbour figures
without recording which cutter was borrowed, and those numbers do not stand.

| Change | Blocked/day | Over window | Cost |
|---|---|---|---|
| **Today** — 21.2 m | 1,997 | 25% | — |
| 24-10 and 24-13 borrow a neighbour | 1,888 | 21% | a routing rule |
| **Any cutter may serve any spreader** | **1,740** | **15%** | a routing rule |
| Table to 24 m | 1,461 | 14% | floor space |
| Table to 24 m + neighbour routing | 1,319 | 9% | both |
| **Table to 24 m + any cutter** | **1,242** | **9%** | both |
| Table to 27 m + any cutter | 724 | 4% | both, more space |

**Neither change is the answer on its own, and they are not alternatives.** Full
routing flexibility takes overruns from 25% to 15%. A 24 m table takes them to 14%, and
removes more blocked minutes doing it. Together they reach **9%** — not the sum of the
two, because they are fixing overlapping parts of the same queue, but well past what
either reaches alone. Routing spreads the cutting load; the longer table absorbs what
is left of it.

#### Recommended, in order

1. **Open up cutter routing first — because it is free.** Today only 24-03 and 24-05
   may call a second cutting machine (rule F8). Letting any cutter serve any spreader
   is a rule change with **no capex and no floor space**: it moves load off the two
   saturated cutters onto 24MC1, which has 45% slack. Overruns fall from 25% to 15%.
   If full flexibility is impractical, routing 24-10 and 24-13 alone captures 25% → 21%.
2. **Then extend the tables, if the floor allows.** 21.2 m → 24 m is worth as much as
   the routing change on its own — 14% over window and the largest single cut in
   blocked minutes — and it is second on this list only because **nobody has confirmed
   the floor space exists.** It is the change with the open question attached, not the
   weaker change.
3. **Do both.** 9%, from 25%. Neither one alone gets past about 14–15%, so if the
   target is "spreading finishes inside the shift", both are needed.
4. **A sixth cutting machine** only if volume grows. The ratio is the root cause, but
   the two changes above recover most of it without buying one.

Note that a 24 m table with **neighbour** routing also reaches 9%. If full flexibility
is hard to operate, that pairing is the cheap route to the same answer.

Two more ideas were ruled out by measurement — tuning the planner's fill target, and
balancing cut groups by capacity rather than spreader count. The numbers are in
[Part 5 § Ruled out](#ruled-out-with-the-numbers-that-killed-it).

#### Why this section changed

An earlier version of this document argued that routing halved the problem and a longer
table could not be the answer on its own. That was true of the model as it then stood,
and it is no longer true. The reason is the planner, not the table.

The old sequencer assigned each cluster by a fixed round robin that restarted at the
group's first machine. Tables are sorted longest-first, so the biggest table of every
cluster landed on 24-01 — which carried **811 spread-min/day** against 24-03's 503 on
near-identical table counts. 24-01 is a night machine with **1,155 staffed minutes**, so
it absorbed the overload quietly and the blocking showed up as a routing problem.
Levelling the load across each group pushes that work back onto **675-minute day
machines**, and those feed the already-saturated 24MC4 and 24MC5. The queue is now
where the capacity really is short, so buffer length buys more than it used to and
re-routing buys less.

### 4b. The cutting-machine-count ladder

Recommendation 4 above ("a sixth cutting machine, only if volume grows"),
measured. S0 sequencing, 21.2 m table, rule F8 routing as written — **only the
cutter count changes**. `24MC1` keeps 24-01/02/03 at every count, so the night
shift is untouched throughout; only the ten day-only spreaders re-partition
(24MC4 and 24MC5, the two saturated groups, split first). Full 199-date file,
from **`node tools/idle_variants.js`** §4b — Python has still never run here.

| Cutters | Spreaders/cutter | Blocked/day | Over window | Last cut |
|---|---|---|---|---|
| **5** (today) | 2.60 | 1,563 min | 16% | 21:15 |
| 6 | 2.17 | 900 min | 4% | 20:00 |
| 7 | 1.86 | 825 min | 5% | 19:59 |
| 8 | 1.63 | 724 min | 4% | 19:52 |

**A single sixth cutter does most of the work** the routing-plus-longer-table
pairing does in §4 — blocked minutes nearly halve (1,563 → 900) and the
over-window share drops from 16% to 4%, i.e. spreading almost always finishes
inside the shift. Going past six buys progressively less (7 and 8 barely move
off six). This is why §4 recommends the two free/cheap changes *first* — they
reach a comparable place without capex — and lists a sixth machine as the
"only if volume grows" fallback rather than the primary fix. The trolley-side
of this ladder is table T-C ([Part 8 §4](#4-shipped--session-2026-09-08-8-month-data-cutting-machine-count-same-mo-sequencing-split-and-a-page-size-retreat-to-3-months)):
the cutter count is worth ~1 utilization point on S0 and nothing on S1–S3.

### 5. This is not the trolley problem

**The variants in this section — spreading-table length (21.2 / 24 / 27 m) and
cutter routing (neighbour, any-cutter) — leave trolley utilization unmoved,
because none of them touches `CUT_GROUPS`, so none changes the sequence the
combine rule acts on.** That independence is what this claim covers, and it is
exact for those variants. Nothing here improves trolley utilization, and none
of the three changes in [Part 6](#part-6--change-spec-for-isd) improves idle
time. Treat this as a separate, additive win with a separate business case —
see [Part 1 § The two problems](#the-two-problems).

**The one axis that is *not* independent is cutting-machine count**, added in
the 2026-09-08 work: more cutters re-partition `CUT_GROUPS`, which changes
`_pick_machine`'s candidate list and therefore the sequence. Measured directly
(table T-C, [Part 8 §4](#4-shipped--session-2026-09-08-8-month-data-cutting-machine-count-same-mo-sequencing-split-and-a-page-size-retreat-to-3-months);
regenerate with `node tools/tc_table.js`): on **S0's scatter sequencer** the
cutter count moves utilization by about **+1.4 points** and the fleet
requirement by about **−40 trolleys** across 5 → 8 cutters. On **S1, S2 and S3
it moves nothing** — S1 and S2 are exact to 0.00, because at `wip_hold = 0`
the loader's output does not depend on the timeline at all and MO-aware
pairing fixes adjacency before the layout is consulted; S3 moves ±0.3 points,
inside the known greedy-parking tie-break artefact (trap 6). So the axis is a
minor confound on "today", and no confound at all on the three-change path
every recommendation rests on.

### 6. What to distrust

In [Part 4 § The idle-time case](#the-idle-time-case), with everything else worth
distrusting.

### 7. Seeing it

Open `out/dashboard.html` → **Simulation** tab. The hatching on the Job Sequence Gantt
is this blocking; hover any band for the minutes lost. The **Idle time** control in the
left rail switches the spreading table between 21.2, 24 and 27 m, and the chart and the
running total under it update.

Reproduce the tables above with `python idle_variants.py`, and everything else with
`python run.py`; every value is named in `assumptions.py`. See
[Part 2 § Running the build](#running-the-build).

---

## Part 8 — Working notes

Kept by the **compacter** agent. Read this part before changing anything: it holds the
rules, options already ruled out, the traps that have bitten, and the things that must
be done before this work is picked up again.

If this part and the code disagree, **the code wins** and this part is out of date.

> **2026-11-09:** the tables T-A to T-F, every mention of `npm run pin`, `pin.js`,
> `warmstart_table.js`, `pullahead_table.js`, `run()`, `run_day()` and `run_timeline()`, and
> the "closed day" description below are **HISTORICAL (cold-start model, retired
> 2026-11-09; no longer reproducible)**. The live state is in the banner at the top of this
> file, `SIM_SPEC.md` §18 and the workspace `CLAUDE.md`.

Last updated: **2026-11-10** (§6 below holds the 2026-11-09/10 decisions; §1–§5 and the traps
were written before them and stay as history where marked; §4 covers Phases 0–5C of
2026-09-08, Phase 5B/6 still open, see §4's opening note and §5 HARD CHANGES #7)

### 1. Rules

#### Factory rules

- **Shifts.** Day 07:15–20:00 all machines, night 18:00–05:00 for 24-01/02/03 and
  24MC1; **675 min** day-only, **1,155 min** night-capable. Full statement, including
  breaks and the overlap, in [Part 2 § The shifts](#the-shifts).
- **Fabric relaxing is a precondition, not a variable**, and **pattern is never the
  constraint**. Both in [Part 3](#part-3--task-readiness-statuses).
- **Net_Rate is universal — use the H5 mapping.** A scheme switcher was built and then
  removed at the user's instruction.
- **Blocking is a length problem, not a slot count.** A lay occupies its marker length;
  cutting consumes that length *progressively* as the lay is fed to the cutter, so space
  returns gradually. The user identified this. Modelling it as two slots emptying at
  `cut_end` overstates blocking by **63%** — the figures are in
  [Part 7 §1](#1-what-the-hatching-is).
- **The blocked _percentage_ excludes breaks and shift ends** — its denominator is
  `busy + blocked`, never staffed time. The blocked _minutes_ figure is not clamped
  that way: a G6 wait crossing a break or past shift end banks the unstaffed part
  (RULES.md §3, Part 7 scope note). The `occupy()` clamp wait is excluded entirely.
- **Neighbour routing is defined explicitly.** The last spreader of a group may call the
  next group's cutter: `24-10 → 24MC5`, `24-13 → 24MC1` (numbering wraps). Any
  neighbour figure that does not record which cutter was borrowed is void.

#### Project rules

- **`assumptions.py` is the only place a number may live.** Nothing hard-coded in
  `model.py`. Every value cites its rule; estimates say so IN CAPITALS.
- **The repo outranks the deck.** Any change that moves a published number is reported
  with a before/after table, never buried.
- **Mirror, do not improve.** If the Python model has a quirk, the JS port reproduces it
  exactly. Fixing a quirk is a separate, announced change.
- **Never hand-write `out/dashboard.html`.** It is a build artifact.
- **Nothing publishes if the parity gate fails.** The gates are listed in
  [Part 2 § Gates that must pass before publishing](#gates-that-must-pass-before-publishing).
- **Idle time and the trolley shortage are independent.** Never claim a saving from one
  for the other.
- **Every table in a published document must be regenerable by a script in the repo.**
  This was violated: two rows of the idle-time §4 table came from a throwaway script and
  had to be withdrawn.
- Agent chain is **planner → coder → tester**, compacter on request. Definitions in
  `.claude/agents/`. **Paused 2026-11-10** (user: it costs too many tokens): the main session
  plans, codes and runs the gates itself until the user asks for the agents again.
- **Comparison standard (user, 2026-11-09).** S0 is the current situation; S1–S3 add one rule at a
  time on exactly the same floor and are compared back to S0. Shift, pace, fabric relaxing, cutter
  setup and travel are floor facts and sit in every row. Setup, travel and waiting are lost time:
  more setup must never show more output. Output is what the **cutters** cut. Trolley findings
  and output / idle findings are independent.
- **S0 is the real Job Sequence** (`data/SQL Job Sequence Logic.sql`, `P_Task_Calculate`, core loop
  only), not a model-made sequencer. Rule (a): same-MO tables are paired and spread back-to-back,
  counted by pairs, then assigned to maximise cutter output; keeping a whole MO on one cut group is
  a separate option. The cutter always moves between spreaders.
- **The floor is live** (SIM_SPEC.md §6b): re-plan every 30 min, tables start once ready, a free
  cutter takes the longest-waiting lay.

### 2. Changes shipped as of 2026-08-26

Nothing below moved in the 2026-08-27 session — that session was diagnosis and
planning only, no file edited except this one. What it diagnosed was built and
shipped in the 2026-08-28 session — see [§3 below](#3-shipped--session-2026-08-28-garments-per-trolley-reconciliation--gantt-time-bar-fix).

| Change | Why |
|---|---|
| **Simulation tab** added to `out/dashboard.html` | Job Sequence Gantt (13 spreaders + 5 cutters, real clock from 07:15, breaks and shift ends drawn, table numbers on bars, pair brackets, G6 hatching), collapsible task list, collapsible Panel Loading with a per-trolley table. Calendar picks the plan date. "The three changes" controls plus a spreading-table-length control sit in the rail. |
| **Utilization tab left alone** | Original data, UI and calculations verified byte-identical apart from the two edits asked for: source line removed, renamed "Trolley Utilization Simulation". |
| **Real shift model** | 675/1,155 min replaced the wrong 660/1,200 constants; machines stop for breaks, tasks pause and resume. |
| **Blocking became a length model** | Slot counting overstated blocking by 63%. |
| **Spreading table measured at 21.2 m** | User measurement replaces the assumed length. |
| **Round-robin bias in `_sequence_today` fixed** | It assigned `machines[i % len]` restarting at zero per cluster; tables are sorted longest-first, so the biggest table of every cluster landed on the group's first machine — 24-01 carried 811 spread-min/day against 24-03's 503 on near-identical counts. Now assigns least-loaded within the cut group. Load spread **1.86x → 1.35x**, last cut **00:47 → 23:40**. **This is the only reason S0 moved. S1–S3 did not move at all.** |
| **Relaxing fixed as a precondition** | Slider built and removed; statuses 5 and 6 read zero. |
| **Net_Rate switcher removed** | Net_Rate is universal, H5 only. |
| **The idle-time analysis created, then rewritten** | The sequencing fix flipped its evidence. It used to argue routing halves the problem (25% → 13%); routing now reaches **15%**, a 24 m table reaches **14%**, together **9%**. The order "routing first, tables second" survives **on cost** — routing is free, floor space unconfirmed — not on effect size. |
| **`idle_variants.py` created** | Sole source of the [Part 7](#part-7--idle-time) §3 and §4 tables. **Never executed** (no Python); verified by reading it against `model.py` and by independent reproduction in Node. |
| **Neighbour routing defined** | Earlier published neighbour figures (1,858 · 23%, 1,387 · 15%) never recorded which cutter was borrowed and **do not stand**. Correct: **1,888 · 21%** and **1,319 · 9%**. |
| **Four agent definitions** written to `.claude/agents/` | planner, coder, tester, compacter. |
| **`CODE.md`, `IDLE_TIME.md` and `SPEC_FOR_ISD.md` merged into `README.md`** | Four documents that overlapped and in places disagreed became one, with stubs left behind. Documentation only — no code and no output changed. |

### 3. Shipped — session 2026-08-28: garments-per-trolley reconciliation + Gantt time-bar fix

#### The bug report and the diagnosis

User report: on the Utilization tab, 53.6% trolley utilization should imply 402
garments (53.6% x 750 max trolley capacity), but the "Garments per trolley" tile
showed 306.

**Not a bug — a missing metric.** There are three distinct ratios; the page showed
only two of them:

| term | S0 Today value | what it is |
|---|---|---|
| 750 | ceiling | 5 compartments x 150 (rules H3, H1) |
| 402 | was missing from the page | capacity of the compartments actually opened = 53.6% x 750 |
| 306 | was shown on page | garments actually on board |

`utilization_pct` (`model.py`) counts how many of the 5 compartment slots got
**opened**, not how full each one is (H6). A compartment holds one size of one
batch (H1/H4); `compartments_for()` splits each size with `divmod(qty, 150)`, so
the last compartment of any size gets only the remainder — compartments run
part-full, average ~75%. That per-day fill was already computed
(`compartment_fill_pct`, inside `run_day()`) and then discarded: it was never
aggregated into `run()`'s return dict, so it never reached the sweep or the
dashboard. The 402→306 gap **was** that missing metric.

#### Second defect, found while diagnosing the first

`pieces_per_trolley` was a **mean of 20 daily ratios** (`avg('pieces_per_trolley')`).
`utilization_pct` was **pooled** (summed over all days, then divided once).
Different basis — so `garments_per_trolley_capacity x compartment_fill_pct` would
not have equalled `pieces_per_trolley` even after the metric above was added; a
second, smaller confusion (~1%) that would have recreated the same complaint.

#### Decisions taken

1. **Option A — pool all three ratios.** `pieces_per_trolley` became
   `total_pieces / total_trolleys` (pooled), matching `utilization_pct`'s basis.
   This moved a published number — see the before/after table below.
2. **Rebuild path: Node, in `tools/`, targeting `out/index.html`.** Python remains
   unavailable on this machine. The prior session's scratchpad Node port was gone
   (as HARD CHANGE #2 warned it would be); it was rewritten into the repo at
   `tools/` rather than a temp directory, so it survives the next session. See
   HARD CHANGE #2 below, now updated.
3. **`xlsx` (SheetJS) as a build-only devDependency**, for reading
   `data/planppc.xlsx` in `tools/model.js`. Network access to the npm registry was
   confirmed live. It is listed in `package.json` `devDependencies` only, required
   solely from `tools/*.js`, and never reaches `out/index.html` — that file stays
   fully self-contained (no external URLs, no fetch, verified by grepping the
   built output).

#### What actually got built

- `tools/assumptions.js`, `tools/model.js`, `tools/scenarios.js`,
  `tools/daytrace.js`, `tools/round.js`, `tools/build.js`, `tools/pin.js` — a
  full Node mirror of `assumptions.py` / `model.py` / `scenarios.py` /
  `daytrace.py` / `run.py`, function for function, same names, so the two can be
  diffed side by side. `tools/build.js` reads `dashboard.py` as text, slices out
  the `TEMPLATE = r"""..."""` block, and performs the exact same
  `TEMPLATE.replace('/*__DATA__*/null', data)` `dashboard.py`'s own
  `build_dashboard()` does — the HTML/JS is never hand-copied into a `.js` file,
  so `dashboard.py` stays the single source of the page, including the Gantt fix
  below.
- `model.py` `run()` — `compartment_fill_pct` and `garments_per_trolley_capacity`
  added to the aggregate return, pooled like `utilization_pct`;
  `pieces_per_trolley` switched from `avg('pieces_per_trolley')` to
  `total_pieces / total_trolleys` (Option A). `run_day()` and its per-day keys
  untouched. Mirrored in `tools/model.js`.
- `run.py` sweep dict — the same two keys added, rounded. Mirrored in
  `tools/build.js`'s `sweepRow()`. Not added to `write_excel()` — out of scope,
  `results.xlsx`'s columns are unchanged.
- `dashboard.py` — tile markup and `render()` wiring landed together (Trolley
  utilization → **Compartments opened**; new **Compartment fill** tile between it
  and Garments; Garments per trolley → **Garments loaded per trolley**; final
  order `tUtil → tFill → tPpt → tTpd → tCycle → tWait`), the "what one trolley
  looks like" prose rewritten to state 750 → capacity → pieces → fill as a chain
  with no hard-coded numbers, the sub-caption's `÷ 5` bound to
  `A.trolley_compartments` via a `#capDiv` span, and a compartment-fill
  definition sentence added to the footer, bound to `A.*` constants. The
  Simulation tab's loading port and parity check were not touched.
- The Gantt time bar (Part B, see below).

#### Two bugs found while building `tools/`, not in the original diagnosis

Neither is a model.py issue — both are Node-port / build-tooling bugs, caught by
the pin (below) before they could reach `out/`.

1. **SheetJS's `cellDates:true` misdates on a non-UTC host.** Verified against
   this exact workbook: a plain-integer Excel serial (46167, the cell's own
   formatted display reads "25 May 2026") came back as a JS `Date` one calendar
   day earlier with a spurious ~7-hour time-of-day — this host is UTC+7. First
   surfaced as every plan date in the Node port's output being one day earlier
   than `out/*.bak`'s. Fixed by reading the raw numeric serial
   (`cellDates:false`) and converting it with the textbook formula
   (`(serial - 25569) * 86400000` ms from the Unix epoch) instead of trusting
   SheetJS's date objects — cross-checked against several cells' own formatted
   `.w` values. `tools/model.js`'s `excelSerialToDate()`.
2. **Naive banker's-rounding re-introduces the tie it is meant to avoid.**
   Scaling a float by `10^n` and comparing the fraction to `0.5` performs a
   *second* binary rounding step, which can manufacture an exact tie that was
   never in the original number. Caught on `totalTrolleys / 20` for one
   scenario: it prints as `200.35` and `× 10` is *exactly* `2003.5` in float64,
   but the double's true value is `200.349999999999994315...` (verified via
   `.toFixed(30)`) — strictly below the midpoint, so Python's `round()` (which
   works from the double's own exact decimal expansion) correctly gives `200.3`,
   not `200.4`. Fixed in `tools/round.js` by rounding from the double's exact
   decimal expansion (`toFixed()` at high precision, per spec a correctly-rounded
   decimal to the requested digit count) rather than a scaled comparison.

#### The pin — what it proved, reported both ways, nothing hidden

**HISTORICAL — `tools/pin.js` and `npm run pin` were retired on 2026-11-09 with the
cold-start model.** The `.bak` files stay on disk, untouched; no gate reads them.

The gate: build the Node port, then assert it reproduces `out/sweep.json.bak` /
`out/results.json.bak` — the last genuine Python output — **before** any Part A
model change is applied. Investigating this surfaced something the original plan
did not account for: `.bak` (2026-08-26 13:57) predates **two** fixes already
present in today's `model.py` — the least-loaded sequencing fix and the
length-based blocking model (both in the 2026-08-26 changelog above). A literal
byte-exact pin on every field is therefore not achievable by a *correct* port —
not a bug, a fact about what `.bak` is. `tools/pin.js` runs two tiers and reports
both honestly rather than asserting a clean pass it had not earned:

- **Tier 1 (hard gate) — mo_aware=1, hold=0 keys (order-independent: with no WIP
  hold, nothing ever parks, so every loading event is independent of every
  other).** **PASSED, exact to full float precision** — `1|1|0|1`, `S1`'s full
  headline entry, and (once the rounding bug above was fixed) every field on
  every such key. This exercises `_sequence_mo_aware`, the full timeline-to-
  `cut_end` chain, and the entire loading engine (compartments, combining, the
  52-bay cap) end to end, unmodified.
  - **Informational, not a hard gate:** hold>0 keys under mo_aware=1 (36 of 39)
    diverge from `.bak` — expected, because the blocking-model fix changes
    individual tasks' `cut_end`, which changes WIP-hold eviction/top-up timing
    even though sequencing itself is untouched. Not discovered until the pin was
    actually run.
  - **Informational, not a hard gate:** `max_batches≥2` (cross-batch combining)
    shows a small residual even at hold=0 — up to ~0.06% on `utilization_pct`/
    `trolleys_per_day`, traced to 2 of 20 plan dates where the greedy pairing
    loop has a tie among equally-valid candidate pairs (same total compartments
    and combine count, different specific pairing, so a different trolley
    bin-packing outcome). `max_batches=1` (today's actual rule, and what S0/S1
    and the headline 53.6% figure use) is unaffected and passed exactly.
- **Tier 2 — a from-scratch reimplementation of the pre-fix round-robin
  sequencing** (`machines[i % len]`, restarting per cluster — the one sentence
  the 2026-08-26 changelog gives for it), defined in `pin.js` only, never
  shipped. **Not achieved** — this reconstruction does not reproduce `.bak`,
  including on the order-independent mo_aware=0/hold=0 subset (S0's own key:
  legacy gives 53.72% utilization, `.bak` has 54.44%). Either the reading of
  that one sentence is incomplete, or the pre-fix code differed a second way it
  does not mention. The source no longer exists anywhere to check against.
  Reported here as not achieved rather than papered over — per the project rule
  above, "if Tier 2 does not reproduce `.bak` exactly, report the discrepancy,
  do not paper over it."
- **Supplementary, informal:** the length-based blocking model's own output
  (`spreading_blocked_minutes`, S0, avg/day) lands at **1,997** — an exact match
  to the independently-published Part 7 §2 figure, computed on a different code
  path (`idle_variants.py`, never run, vs. `tools/model.js`'s `run()`).

**Proceeded on this basis**: the hard gate itself, the mo_aware=1/hold=0 exact
match exercising nearly the entire model end to end, and the blocking-minutes
match against Part 7's independently-published figure. This is a disclosed,
reasoned judgement call given the pin's stated purpose was never achievable in
full — see the plan file this session worked from for the reasoning at the point
the two-tier design was proposed and approved before implementation began.

#### Part B — the Gantt time bar

Root cause: the slider's range (built to reach `doneAt` up to 3 days out) and the
chart's own axis (`ganttEnd(run)`, ~20:00) were different scales drawn over the
same pixels, so the handle and the drawn cursor line diverged and the line could
vanish once the cursor exceeded the chart's own end.

- **B1 — the slider's range is now exactly `ganttEnd(run)`**, the same call
  `gantt()` uses for `xmax`. The `lastDone`/`CURSOR_MAX_MINUTES` arithmetic is
  gone from the slider entirely. `step="15"` on both the static markup and
  `resetCursor()`; min/max set before value.
- **B2 — the late-finishing tail moved to its own control**: a `same day / +1d /
  +2d / +3d` segmented stepper (`sim.cursorDay`) beside the readout. The
  effective instant read by `statusOf()` and the readout is
  `sim.cursor + sim.cursorDay * 1440`; the **drawn line** stays on `sim.cursor`
  alone, so it is always on the chart's own axis and can never vanish. Day
  buttons beyond the date's actual latest `doneAt` are disabled, computed per
  date rather than always offering three.
- **B3 — a single `rerun()` helper** (simulate once → `resetCursor(run)` →
  `draw(run)`) replaces the old `draw(); resetCursor(simulate());` on the date
  handler (which painted from the *previous* date's cursor) and the separate,
  duplicate `simulate()` call at the end of `init()`. Every control that can
  move `ganttEnd(run)` — sequencing, batches, table length, workstation, WIP
  hold, in addition to the date buttons — now calls it, so the slider's range
  can no longer go stale against a scenario change. Date changes reset
  `sim.cursor`/`sim.cursorDay` to 0 (a new date is a new timeline); other
  controls let `resetCursor()` clamp the existing position to the new max
  instead of zeroing it.
- **B4 — the half-thumb inset.** The thumb's visual box is 20px (16px + 2px
  border × 2); a native range input moves the thumb's *centre*, not its edge,
  so the track needs to be that much narrower on each side for a fraction to
  land on the same pixel the SVG draws it at. `--thumb:20px` defined once at
  `:root` and referenced (via `calc()`) by both the thumb rules and
  `.cursorrow`'s padding, so the two cannot drift apart again.

Verified in a jsdom-rendered copy of the built `out/index.html`: all six
Utilization tiles show real values, the Simulation tab's Gantt renders an
`<svg>`, the cursor slider reports `min=0`/correct `max`/`step=15`, all four day
buttons are present, and the cursor line remains drawn (`<line>` present) after
moving the slider to its midpoint — with zero JS errors captured. Full
cross-browser/visual QA (thumb alignment at the pixel level, Firefox's
`-moz-range-thumb` box model, keyboard behaviour) was not performed and is
called out as unverified rather than assumed passing.

#### Before/after — the Option A move

Intentional and accepted, not a regression — `pieces_per_trolley` moves,
everything else does not:

| Scenario | `pieces_per_trolley` before | after | Everything else (util, tpd, peak, avg_wait, blocked_pct, blocked_by_space) |
|---|---|---|---|
| S0 Today | 306 | **302** | unchanged |
| S1 + same-MO sequencing | 346 | **343** | unchanged |
| S2 + 2 batches per trolley | 379 | **378** | unchanged |
| S3 + WIP hold | 413 | **412** | unchanged |

Verified across all 78 sweep entries, not just the four headline rows: every one
of `utilization_pct`, `trolleys_per_day`, `peak`, `avg_wait_hours`,
`spreading_blocked_pct`, `cutting_blocked_pct`, `blocked_by_space` is
byte-identical to the pre-session build; only `pieces_per_trolley` moves, plus
the two new keys (`compartment_fill_pct`, `garments_per_trolley_capacity`)
appearing. The reconciliation gate — `garments_per_trolley_capacity *
compartment_fill_pct / 100 == pieces_per_trolley`, to rounding — holds on all 78
entries, which it did not before Option A (that was the second defect). `results.xlsx`
was not regenerated (Python unavailable) — it is stale relative to this build in
the same way it already was stale relative to the 2026-08-26 sequencing/blocking
fixes; regenerating it is one `python run.py` run away once Python is installed.

### 4. Shipped — session 2026-09-08: 8-month data, cutting-machine-count, same-MO sequencing split, and a page-size retreat to 3 months

**Status: Phases 0–5C, Phase 5B and Phase 6 are all done and verified** (5B and
6 landed in follow-on work dated 2026-09-08 — see the "Phase 5B — shipped" and
"Phase 6 — shipped" subsections below). The one thing still genuinely pending
is a real `python run.py` / `python idle_variants.py` / `python -m pytest
test_csetup.py` pass once Python is installed (Part 8 §5), and the follow-on
move of Part 7 §2–§4 onto the 199-date basis that will produce (§4b is already
there). This section is extended, not rewritten, as each phase lands.

#### What was asked

A new, much larger export of `HaveCut` arrived
(`data/PPC Planning - Old Data.xlsx`), and six changes were requested
alongside it: a Job Sequence timeline that scrubs continuously with the mouse
and correctly greys finished work; acknowledgement that Central Cutting runs
**two** working shifts, not one; a control to vary the number of cutting
machines against the fixed 13 spreaders; a genuine before/after comparison for
idle time in place of explanatory prose; a sidebar that scrolls on its own;
and Type C tables contributing a real range of setup minutes instead of a flat
guess. Mid-session, a seventh finding surfaced from direct code reading: the
existing "Same-MO sequencing" toggle was silently conflating two different
rules, and one of its two passes was doing wasted work under the exact
scenario (S1) it was supposed to describe.

#### The new dataset, and a regression check it gave for free

The new workbook — same `HaveCut` shape, 68 columns vs. the old 66 — covers
**199 plan dates, 2026-01-02 → 2026-08-26**, and is a **strict superset** of
the original 20-date May export: all 20 old dates are present, 18 with
identical Type-B table counts (2026-05-25 and 2026-05-26 gained rows, evidence
the old export was cut mid-day). That gave a regression check with no extra
data collection needed: **`tools/regress.js`**, new this session, derives the
18 unchanged dates at run time and asserts `run_day()` on the new workbook
reproduces the old workbook's per-day results **exactly**, at full float
precision, across all 78 (later 117) sweep scenarios — **22,464 checks**,
all passing (R1). Two informational findings alongside the hard gate: row
order differs on 1,580 of 1,657 compared tables (R0 — the new export doesn't
preserve the old one's row order; `clusterBy`'s first-seen ordering and both
sequencers' stable sorts mean this *could* have mattered, and R1 passing on
every check is the proof, not an assumption, that it didn't); and
`is_batch_last` — which is computed file-globally by `_stamp_batch_readiness`,
not per-date — flips on 750 of 1,657 tables once 179 more dates exist to
compare a batch's tables against (R2, informational: it only touches bar
colour on the Simulation tab, no trolley or blocking number).

Profiled and then **deliberately left out**: 422 rows of types T1/P/T/R/L
carry real layer counts and marker lengths (real spreading work) but stay
excluded by rule J2 (Type B only), for continuity with every previously
published number rather than completeness. This under-counts real machine
load by that amount, on purpose — noted here so it isn't rediscovered as a
bug.

#### The cutting-machine-count axis (item 2a)

Rule F2 fixes 13 spreading machines under 5 cutting machines (2.60
spreaders/cutter); Part 7 §4 already named a 6th cutter as the "only if
volume grows" option. `assumptions.py` now carries
`CUT_GROUPS_BY_CUTTER_COUNT` for **5, 6, 7 and 8** cutters — `24MC1` keeps
24-01/02/03 at every count, so `NIGHT_SHIFT_SPREADERS`/`NIGHT_SHIFT_CUTTERS`
and `FLEXIBLE_CUT` (rule F8) stay valid unmodified at every count; only the
ten day-only spreaders are re-partitioned, splitting the two saturated groups
(24MC4, 24MC5 — Part 7 §3) first. `model.py` gained `machine_layout()`,
threading an optional `layout` through `_pick_machine`/`sequence`/
`run_timeline`, with `LAYOUT = machine_layout(A.CUT_GROUPS)` kept as the
untouched default — verified **byte-identical** to the pre-refactor build at
`CUTTER_COUNT = 5` (`results.json` and `sweep.json`, all 78 sweep rows, 0
differences). **The cutting-machine-count sidebar control itself has not
shipped** — the state (`sim.cutters`) and the Gantt/staffing-band rendering
that follows it exist, but there is no clickable UI yet (Phase 5B).

**Genuinely new finding, not assumed:** cutting-machine count changes
`CUT_GROUPS`, which changes the load-balance choice inside both sequencers —
i.e. it changes the *sequence*, and trolley utilization depends on the
sequence. README Part 7 §5's independence claim ("trolley utilization stays
at 53.6%/228 trolleys in every variant above") was established for table
length and routing, **neither of which touches `CUT_GROUPS`**. It does not
automatically extend to the cutting-machine-count axis, and that axis's
effect on trolley numbers has not yet been measured end to end (this is
table T-C, still open — see below).

#### Type C: a deterministic 8–10 minute range (item 2e)

Every one of the 6,269 Type C rows carries `Act LayerQty = 1` and
`Marker Length = 1` — placeholders, not measurements — and its `Marker Ratio`
does not reconcile with layers × ratio the way Type B's does (0/400 sampled
vs. 400/400 for B), so a duration could never be recovered from the data; the
flat `C_TABLE_EXTRA_MINUTES = 10` existed for exactly that reason. Per
instruction, this became a **seeded 8–10 minute range**, one setup per B table
that has any C row (matching the existing `c_tables` set semantics, not one
per C row — 92 of 6,271 matched keys have two). **Determinism was the hard
requirement**: `Math.random()` would permanently break `pin.js`, `regress.js`
and every reproducibility rule this project holds, so the value is a pure
function of `f'{plan_date_iso}|{table_key}'` through FNV-1a 32-bit
(`_fnv1a32`/`fnv1a32`, `assumptions.py`'s `C_SETUP_HASH_OFFSET`/`_PRIME`),
mapped onto 80–100 tenths of a minute. `Math.imul` is mandatory in the JS
hash — plain `*` loses precision above 2^53 and the two languages would
silently disagree. Verified: **6,269 of 15,920 tasks (39.4%) carry a C
setup**, against a profiled 6,271 (the 2-row gap is J2-surviving rows with
no usable ratio/layers); the tenths distribution is genuinely uniform (mean
**9.0088** against an ideal 9.00, all 21 values present, worst bucket
deviation 11.2%); two consecutive builds produced byte-identical output
except the build's own `generated_seconds` timer. `tools/csetup-fixture.json`
(40 verified triples) and `test_csetup.py` exist for the Python side to check
itself against once Python runs — **never executed here, no Python on this
machine**.

**Effect, measured (table T-B):** flat 10.0 → seeded 8–10 minutes, on the
199-date file, before the same-MO sequencing split existed. All 78 sweep
rows moved (490 of 780 compared fields), but the headline movement is small —
S0 utilization 52.93% → 52.99%, trolleys/day 174.7 → 174.5, pieces/trolley
299 → 300. Blocking moved a bit more (spreading blocked 21.2% → 21.6%). **Not
a conclusion-level change** — the data switch (T-A) was.

#### The month-file restructure (Phase 4)

`out/index.html` was, until this restructure, a single **8.4 MB** file
covering all 199 dates, whose calendar could only ever reach January
(`buildCalendar()` derives its one displayed month from the first date in the
file). 95%+ of that weight is the Simulation tab's per-day trace. The fix:
one HTML file per calendar month, each carrying the *same* full-dataset
Utilization-tab aggregate (byte-identical across every file — verified) and
its *own* month's Simulation-tab trace. `TABLE_LENGTHS_M` became
`SIM_VARIANTS`, a list of `(metres, cutters, full)` triples — `full` variants
carry the complete per-task `time`/`order`/`expected`; aggregate-only variants
(the 24 m/27 m table lengths) carry only `blocked`/`groups`, so the Gantt does
not redraw at them, only their numbers show. **The single most dangerous
step**, flagged in advance and confirmed necessary: `order[machine]` had to
move from mode-level to inside the per-variant dict, because a different
cutting-machine count produces a different sequence — verified directly by
building the trace for one date at 5 and at 7 cutters and confirming the
`order` objects are not JSON-identical. `time` was re-encoded from a
per-task array to parallel arrays (`ss`/`se`/`cs`/`ce`/`cut`) — `ce` stays
**unrounded**, everything else at 1 dp, exactly as before, just restructured.

#### The timeline defects (item 1, D1–D7)

Seven distinct bugs in the Simulation tab's time cursor, all page-only
(`dashboard.py`'s `TEMPLATE`, no model file touched):

- **D1** — the slider moved in 15-minute steps, which is what "doesn't flow
  with the mouse" actually was. Fixed to 1-minute steps, which required
  splitting the render path: a new `paintCursor()` moves only the cursor
  line and recolours already-drawn bars via `data-task` attributes, instead
  of the full `draw()` rebuilding the entire Gantt SVG and both tables on
  every tick.
- **D2** — the cursor line wasn't drawn at position 0 (`sim.cursor > 0` →
  `>= 0`).
- **D3** — **the actual root cause of "tasks don't turn Completed."** Bars
  were drawn from the *simulated* schedule but greyed against the *actual*
  `Pull Date` — two different clocks sharing one axis. Fixed: `statusOf()`
  now greys on the simulated `cut_end`. This changes what "Completed" means
  from the definition in [Part 3](#part-3--task-readiness-statuses) row 8
  (`Pull Date`-based) — **that row still needs updating, not yet done.** The
  real `Pull Date` was deliberately kept off the chart itself (no "actually
  finished" column, no tick marks — considered and rejected) but its
  dataset-level slip statistic stays, reading `DATA.slip`.
- **D4** — the axis floored at 20:00 (day-shift end), so the **second shift,
  to 05:00, was never on the chart** — this is what "acknowledge two working
  shifts" meant. Now floors at the full two-shift window (minute 1,305), with
  a day/night staffing ribbon and a dashed outline on work that overruns a
  machine's own staffed window.
- **D5** — the "+1d/+2d/+3d" day stepper added in the 2026-08-28 session is
  now removed: with D3 fixed, the simulated clock always fits inside D4's
  widened axis, so the stepper's original purpose no longer exists. This is a
  partial reversal of that session's own B2 fix.
- **D6** — `hhmm()` rounded after splitting hours/minutes, so a value near a
  boundary could print `23:60`. Fixed to round the whole minute first,
  matching `idle_variants.py`'s own `clock()`.
- **D7** — Gantt rows now read `DATA.cutGroupsByCutterCount[sim.cutters]`
  instead of a single fixed `DATA.cutGroups`.

Verified in a real Edge browser (`playwright-core`, `channel:'msedge'` — no
Chromium download needed; jsdom cannot compute layout and is why an earlier
attempt at this exact timeline shipped without catching D1–D4).

#### Same-MO sequencing: two rules, not one (item 5C — the "look for this" finding)

Direct code reading confirmed a genuine confusion the dashboard's own binary
Off/On toggle had been papering over. `_sequence_mo_aware`
(`model.py:470-512`, README §2 above) already does a two-pass pairing — same
batch first, then whatever's left across different batches — and that
**is** and always was Change 1's documented spec. But its cross-batch pass
called `can_combine(..., cross_batch=True)` **unconditionally**, never
checking whether the scenario's own `max_batches` made cross-batch combining
reachable at loading (`_loading_events`, further down, gates correctly).
Net effect on **S1** specifically (`max_batches=1` — Change 2 still off):
the sequencer paired different-batch tables toward combines that could
never actually happen.

**Both fixes were applied, per instruction:**
1. `Scenario.mo_aware_sequencing: bool` became
   `sequencing_mode: 'today' | 'same_batch' | 'cross_batch'`.
   `_sequence_mo_aware` gained a `cross_batch` parameter that skips the
   cross-batch pass entirely when `False` — not filters it, skips it.
   **S1 is redefined to `same_batch`**; S2 and S3 keep `cross_batch`
   (they already have `max_batches ≥ 2`, where it's meaningful). This
   is a genuine change to what S1 *means*, not a relabelling.
2. **Exposed as an explicit, independent 3-way control**, selectable
   regardless of `max_batches` — a real, previously-unreachable combination
   (e.g. cross-batch sequencing at `max_batches=1`) now exists and was
   verified live: on the Utilization tab, clicking Cross-batch at the
   default `max_batches=1` reads **58.8%**, sitting correctly between
   Same-batch-only's 58.75% and the full S2 (cross-batch + 2 batches)
   figure of 64.7%.

`SWEEP_MO_AWARE = [False, True]` became `SWEEP_SEQUENCING_MODE = ['today',
'same_batch', 'cross_batch']`; the sweep grew from 78 to **117** scenarios.
Both sidebar toggles (Utilization and Simulation tabs) now read *Off / Same
batch only / Cross-batch*; the sweep-key lookups, the URL-hash parser, and
the step-ladder's current-scenario highlight were all updated to match — and
one pre-existing crash was fixed in passing: the Utilization tab's `key()`
lookup and its step-ladder comparison were both still built for the old
boolean/numeric `mo` value and would have broken the instant this shipped had
they not been updated with it.

**Effect, measured on the real 79-date April–June scope (table T-D):**
utilization, trolleys/day, peak, and pieces/trolley are **exactly
unchanged** by the fix — only blocking percentages move (spreading 20.93% →
21.05%, cutting 23.84% → 23.77%). The fix removes genuinely wasted work in
the sequencer, and it does not retroactively change any previously reported
headline number in a material way. What *does* change the headline story is
the dataset scope, below — not this fix.

| Field | Old S1 (`cross_batch`, the pre-fix shape) | New S1 (`same_batch`, shipped) | Move |
|---|---|---|---|
| `utilization_pct` | 58.755 | 58.753 | −0.002% |
| `trolleys_per_day` | 173.646 | 173.646 | 0.000% |
| `peak_trolleys_in_a_day` | 272 | 272 | 0.000% |
| `pieces_per_trolley` | 346.817 | 346.817 | 0.000% |
| `spreading_blocked_pct` | 20.925 | 21.046 | +0.578% |
| `cutting_blocked_pct` | 23.836 | 23.772 | −0.267% |

**A pin-file consequence of the fix, disclosed rather than worked around:**
`out/*.bak` predates this fix, so `tools/pin.js`'s S1-headline hard gate was
comparing the *new* `same_batch` S1 against `.bak`'s *old* `cross_batch`-shaped
data — a mismatch, not a regression, and it failed for exactly that reason on
first rebuild. Fixed by constructing the comparison from a synthetic
`cross_batch, max_batches=1, hold=0` scenario under S1's old name (matching
what `.bak` actually contains — the same class of fix as the two already
documented in that file's header for the 2026-08-26 sequencing/blocking
changes), and adding the live-`same_batch`-vs-`.bak` comparison as its own
labelled, informational block — the table above is read directly off that
block's output on the small 20-date pin fixture, and independently
reconfirmed on the full 79-date production scope.

#### The page-size crisis, and the retreat to 3 months

Adding a third sequencing mode raised the trace's dominant cost by the
expected ~50%, and it did not fit: at 8 months, every month file exceeded the
1.7 MB budget (June: 1.60 MB → 2.22 MB; July, then the heaviest: → 2.30 MB).
Rough accounting (≈170 KB per mode×cutter-count combination) put the
affordable ceiling at 8–9 full combinations against the 12 the 3×4 matrix
demanded. **Escalated rather than decided unilaterally**, per the standing
instruction that a multi-variant cut needs sign-off. Two decisions followed,
in sequence:

1. **The dataset scope for the built pages narrows to April–June only**
   (`assumptions.py`'s `WEBSITE_MONTHS`) — not just the Simulation tab's
   trace, the *entire* aggregate: headline, sweep, `results.json`, every
   month file. `model.py`'s `load_days()` itself, `pin.js`, `regress.js` and
   `idle_variants.py` are unaffected and still see the full 199-date file;
   only `run.py`/`tools/build.js`'s own filtering (applied once, right after
   loading, before any other computation) narrows the built output. This
   was confirmed **twice** before being applied, because the first framing
   of it ("remove Jan–Mar and Aug") was ambiguous between narrowing only the
   Simulation tab's files and narrowing the entire headline — the user chose
   the latter explicitly, aware it would partly undo the 8-month finding (see
   the front-page callout at the top of this file).
2. **Cutting-machine counts 6 and 8 dropped to aggregate-only**
   (`SIM_VARIANTS`), leaving 5 and 7 as the two `full`, fully-chartable
   counts in every sequencing mode — 3 modes × 2 cutter counts = 6 full
   combinations, comfortably under budget with room to spare.

Narrowing the *scope* alone would **not** have solved the size problem on its
own — a month's file size depends on that month's own date count, not on how
many other months exist in the dataset; April/May/June were still
individually over budget (1.90/2.10/2.22 MB) even before the cutter-count
reduction. Both changes were needed together. Result, verified: June (the
heaviest of the three) **1.31 MB**; April 1.13 MB; May 1.25 MB — all well
inside budget. `pin.js` and `regress.js` both still pass; two consecutive
builds are byte-identical.

**A second real bug found and fixed while verifying this**, unrelated to the
scope decision itself: `out/index.html` was ending up a copy of **May**, not
June, after the narrowing — a pre-existing ordering bug from the original
8-month build (June was deliberately processed first, to run the size-gate
check before the other months were spent building; the code tracked
"whichever month the loop wrote last" as the index.html source rather than
"the chronologically most recent month," and those two had always coincided
by chance across 8 months until the scope narrowed to exactly Apr–Jun, where
June is chronologically last but processed first). Fixed by tracking each
month's output path explicitly and copying from the calendar-sorted last
entry, not the loop's own iteration order.

#### Before/after — data switch (T-A) and Type C (T-B)

**HISTORICAL (cold-start model, retired 2026-11-09; no longer reproducible).**

**T-A — 20 dates (May only) → 199 dates (Jan–Aug), before the scope
narrowed to April–June:**

| | Utilization | Trolleys/day | Fleet @7d | vs. 1,200 | Blocked min/day |
|---|---|---|---|---|---|
| S0 Today | 53.64% → 52.93% | 227.6 → 174.7 | 1,593 → 1,223 | −393 → −23 | 1,997 → 1,539 |
| S1 (old, cross-batch-shaped) | 59.39% → 57.95% | 200.3 → 155.2 | 1,402 → 1,087 | −202 → +113 | 1,910 → 1,447 |

**T-B — flat 10.0 min → seeded 8–10 min setup, same 199 dates:** see above —
S0 utilization 52.93% → 52.99%, trolleys/day 174.7 → 174.5; small, not
conclusion-level.

**T-D — the same-MO sequencing fix:** see the table above; also small, also
not conclusion-level.

**The number that actually moved the headline is neither T-B nor T-D — it is
the deliberate scope narrowing** from 199 dates to 79 (April–June), which
takes S1 from **+113 spare** (the full 8-month figure) to **16 short** (see
the front-page callout).

#### T-C — the cutting-machine-count ladder's effect on trolley numbers (Phase 6)

**HISTORICAL (cold-start model, retired 2026-11-09; no longer reproducible).** `npm run tc`
now prints the carry-over version of this table (SIM_SPEC.md §12) with the cold-start figures
beside it. The text below describes the original cold-start build.

Measured with **`node tools/tc_table.js`** — a measurement script, not part of
the build: it threads a layout through `sequence()`/`runTimeline()` (the
shipped `run()`/`runDay()` hardcode the 5-cutter default) and pools `run_day()`
output exactly as `model.run()` does. `loadTrolleys()` is layout-independent —
it works off the plan and the `cut_end` stamps `runTimeline()` writes — so it
needs no change. **Validation: the script's 5-cutter column reproduces the
shipped headline table exactly** (S0 53.80% / 194.4 / 1,360; S1 58.75% /
173.6 / 1,216; S2 64.69% / 157.8 / 1,104; S3 71.37% / 143.0 / 1,001), so the
4→8-cutter columns are the same code path with only the layout changed.
Never run in Python (no Python on this machine); `idle_variants.py` §4b is the
Python-side home for the same numbers.

**Website scope (April–June, 79 plan dates) — trolley numbers vs the 5-cutter floor:**

| Scenario | 5 cutters | 6 | 7 | 8 |
|---|---|---|---|---|
| **S0** util % | 53.80 | 54.89 (+1.1) | 55.04 (+1.2) | 55.19 (+1.4) |
| **S0** trolleys/day | 194.4 | 189.6 (−4.8) | 188.8 (−5.5) | 188.1 (−6.2) |
| **S0** fleet @7d | 1,360 | 1,327 (−33) | 1,322 (−38) | 1,317 (−43) |
| **S1** util % | 58.75 | 58.75 (0.00) | 58.75 (0.00) | 58.75 (0.00) |
| **S2** util % | 64.69 | 64.68 (−0.01) | 64.70 (+0.01) | 64.68 (−0.01) |
| **S3** util % | 71.37 | 71.51 (+0.14) | 71.05 (−0.32) | 71.03 (−0.34) |

(Full 199-date file: same shape — S0 52.99 → 54.47 (+1.5), S1/S2 flat to
±0.03, S3 ±0.25.)

**The finding.** The cutter-count axis moves trolley numbers **only under
S0's scatter sequencer**, and only a little — about **+1.4 points of
utilization and −40 trolleys of fleet** across the whole 5→8 ladder, in the
*helpful* direction (more cutters → less blocking → different accidental
adjacency in `_sequence_today` → slightly more combines). Under **S1 and S2
it is exactly flat (0.00)**: at `wip_hold_minutes = 0` "nothing ever parks, so
every loading event is independent of every other" (`pin.js`'s own note), so
the loader's output depends only on *which tables are paired* — and
`_sequence_mo_aware` fixes that pairing before it ever looks at the cut-group
layout. **S3 moves ±0.3 points**, within the greedy-parking tie-break
artefact already documented as trap 6. Idle-time numbers move as expected and
substantially (S0 spreading-blocked 21.7% → 11.5%, blocked min/day 1,714 →
804, machines over window 2.5 → 0.5) — that is the point of adding cutters,
and it is Part 7 §4 recommendation 4's territory, not the trolley case.

**Consequence for Part 7 §5:** its independence claim was re-scoped (done this
session) to state plainly that it covers table length and routing — neither of
which touches `CUT_GROUPS` — exactly, and that the cutter-count axis is a
~1-point confound on S0 and no confound at all on S1–S3.

#### Phase 5B — shipped (the sidebar cutter control, the idle-time table, the scrollable rail)

All three are `dashboard.py`-only (the `TEMPLATE` string — `tools/build.js`
slices it straight out, so there is no JS mirror to keep in step; no model
file was touched). `npm run pin` (Tier 1 hard gate, exact) and
`npm run regress` (R0/R1/R3, 33,696 checks) both still pass unchanged, and two
consecutive builds are byte-identical bar the build timer. Verified in a real
Edge browser (`playwright-core`, `channel:'msedge'`), zero console/page errors.

1. **Cutting-machine-count control** — a new `#cutterSeg` `.seg` button group
   in its own "Cutting machines" rail card, above "Idle time", offering the
   four counts in `DATA.cutterCounts` (5/6/7/8) wired to `sim.cutters` →
   `rerun()`. `DATA.simVariants` is the authority on which `(table, cutter)`
   pairs `run.py` precomputed: at 24 m / 27 m only 5 cutters ships, so 6/7/8
   are **disabled** with an explaining `title`; at 21.2 m all four exist but
   6 and 8 are `full:false` (aggregate-only — the "· number only" suffix, the
   Gantt stays on the 5-cutter sequence, exactly as 24 m / 27 m already
   behaved for table length). Switching table length to 24 m / 27 m clamps
   `sim.cutters` back to 5; `applyHash` rejects an impossible pair the same
   way. **Trap-13 fix carried further:** `ganttRows()`/`gantt()` now key every
   cut row and the cutter-shift lookup off `run.cutters.length` (the sequence
   actually drawn — the baseline's 5 when the selection is aggregate-only),
   never `sim.cutters`, or an aggregate selection at 6/8 cutters would draw
   6/8 cut rows over a 5-cutter timeline. `variantMeta`/`variantExists`/
   `variantFull` helpers added next to `variantKeyFor`.
   **Observed, not assumed:** trolley numbers do move with cutter count
   (2026-06-01, today mode: 5 cutters → 170 trolleys / 47.6%, 7 cutters →
   162 / 49.5%) — the same finding §4 flagged for T-C, now visible on the
   page's own parity-checked port.
2. **Idle-time comparison table** — `idleComparison(run)` replaces `idleNote`'s
   prose entirely. One row per cut group of the **selected** variant, plus an
   "All 13" total row, against a baseline **fixed at today / 21.2 m / 5
   cutters** regardless of the sequencing toggle ("today's floor"). Columns:
   cutter busy %, blocked min/day, spreading min/day, blocked/work %, each with
   a signed delta vs baseline (green = less blocking / lower cutter load /
   fewer machines over window). Cut groups the baseline does not have (24MC6/7
   at 7 cutters) are marked `new` and carry no delta; the total row is always
   comparable. Every number is read straight off the trace's per-variant
   `groups` block, whose attribution is `daytrace.py:_groups_block`, copied
   verbatim from `idle_variants.py` — so this table and Part 7 §3 agree by
   construction. Spot-checked live: cross-batch / 21.2 m / 5 cutters shows
   total blocked 1,543 vs 2,330 min/day (−787), machines over window 1 vs 3;
   cross-batch / 7 cutters shows 684 vs 2,330, 0 vs 3.
   **Follow-up (2026-09-10) — the table now explains itself.** The user's read
   was "no explanation means non-sense data." Three fixes, page-only
   (`dashboard.py` `TEMPLATE`, no model touched, numbers unchanged): (a) the
   five column definitions now ship on the page — an always-visible basis gloss
   under the table plus a collapsed `<details>` "What these columns mean";
   per-cell `title=` tooltips carry the unrounded arithmetic
   (`448.7 of 1155 staffed min`, `469.6 blocked / 1274.7 spreading`). (b) At the
   baseline the `±0` delta chips are suppressed — `cell()` renders the bare
   value when `isBase`; every non-baseline path is unchanged. (c) Headers
   renamed: `Spr` → `Spreaders`, `Blocked/day` → `Blocked min`,
   `Spreading/day` → `Spreading min` (the `/day` suffix read as a multi-date
   average, which is what Part 7 §3 is, not this one-date table).
   **Measured while doing it:** the Gantt's drawn hatching runs **about 16% below
   the table's `blocked_minutes`** on a typical plan date (10–22% by date; 18%
   across the whole June month — 42,071 hatched vs 51,200 blocked min).
   `blocked_minutes` is `_room_at(…) − spread_free_before` on the
   raw wall clock (`model.py` ~619) with no shift/break awareness, so a G6 wait
   that crosses a break or runs past a day-only machine's 20:00 shift end banks
   those unstaffed minutes; `gantt()` draws the same gap via
   `workingBetween(spreaderShift, …)` — staffed sub-intervals only. The gap
   concentrates in day-only saturated groups (24MC4), not the night group. The
   page and RULES.md §3 were reworded to stop equating the two.
   **Follow-up (2026-09-10) — the cold-start / closed-day finding.** Recorded in
   Part 4 and RULES §2/§12: every plan date is simulated as a closed day, all 13
   spreaders and 5 cutters empty at 07:15, so the ~2 h of head-of-day cutter idle
   on the Gantt is an artefact (16% of the staffed cutter window pooled at S0,
   matched by ~14% dumped past shift end; cut-minutes conserved). `tools/warmstart_table.js`
   created as the table T-E regenerator: W1 (rebase) reproduces the shipped
   headline to published precision, W2 (defer) moves headline numbers <0.5 pt and
   makes over-window worse; both self-checked against the shipped headline, W1
   conserves cut-minutes exactly. On the page, **"Cutter busy" was renamed
   "Cutter load"** with a timeline-independent definition (page-only, no model
   touched, every number unchanged). Decision (user, 2026-09-10): document, do not
   adopt a warm start — W1/W2 are not worth a HARD CHANGE for <0.5 pt, and a
   realistic warm start needs the actual `Pull Date` backlog, which the model
   does not carry.
3. **Scrollable rail** — `.rail` (both tabs, one rule) gets
   `max-height:calc(100vh - 32px)`, `overflow-y:auto`,
   `overscroll-behavior:contain`, a thin themed scrollbar
   (`scrollbar-color:var(--rule2) transparent` + `::-webkit-scrollbar-thumb`),
   and `padding-right:4px`; the `max-width:940px` breakpoint resets it to
   `static`/`max-height:none`/`overflow:visible`. Verified: on both tabs the
   rail's own `scrollHeight` exceeds its `clientHeight`, wheeling over it
   scrolls the rail (`scrollTop` 305 / 810) and `window.scrollY` stays 0,
   including after the rail scroll bottoms out.
4. **WIP hold confirmed untouched** — `loadTrolleys()`/`loadingEvents()`
   (`dashboard.py` ~1115–1210) are textually unchanged; none of the Phase 5B
   edits touched them. `MAXB` is still the global `A.max_batches_per_trolley`
   (trap 4). The page's loading port was re-checked against `run.py` in a real
   browser across 7 setting combinations (hold 0/30/60/90/120 min, both
   workstation modes, all three batch counts) and every one of the 28 dates in
   `sim-2026-06.html` at cross-batch / 2 batches / 60 min / any-workstation —
   `#parity` green on all, zero errors; `regress` R1 (every hold value in the
   117-scenario sweep) byte-identical.

#### Phase 6 — shipped (T-C, `idle_variants.js` + §4b, RULES.md, the parity gate, the doc corrections)

All verified: `npm run pin` (Tier 1 exact), `npm run regress` (R0/R1/R3),
`npm run parity` (18,486/18,486, new — below), two consecutive builds
byte-identical, all four built files clean in a real Edge browser.

1. **Table T-C** — measured, written up above; `tools/tc_table.js` kept as its
   regenerator (`npm run tc`). Part 7 §5's independence claim re-scoped to name
   table length and routing as what it covers exactly, and the cutter-count
   axis as a ~1-point confound on S0 / no confound on S1–S3.
2. **`tools/idle_variants.js`** — full Node mirror of `idle_variants.py`
   (`npm run idle`), same function names and markdown output. Both scripts
   gained **§4b, the cutting-machine-count ladder** (`measure_cutters()` /
   `measureCutters()`). The Node mirror has run (199-date file: "Today" 1,563
   blocked min/day, 16% over window; a sixth cutter → 900 / 4%); Python's
   `idle_variants.py` still has not (no Python) — §4b's table in Part 7 is
   flagged as Node-port output, and Part 7 §2's scope note now records that
   §2–§4's published figures are the old 20-date basis pending a run.
3. **The parity gate** — replaces the stale 4,680/4,680. `dashboard.py`'s
   `TEMPLATE` gained `SIM.__check()` (exposed as `window.__SIM`), which walks
   every plan date × every `full` variant (21.2 m at 5 and 7 cutters) × every
   reachable (mode, batches, hold, any-ws) combination and compares the page's
   `loadTrolleys()` port against the trace's `expected` block on utilization,
   trolley count, compartments **and** combines. `tools/parity_check.js`
   (`npm run parity`) drives it across all three month files in Edge:
   **18,486 / 18,486 pass**. Not circular — `expected` comes from
   `tools/model.js`, a separate reimplementation (trap 8). Added to the "gates
   that must pass" list in Part 2 and RULES.md §11.
4. **`RULES.md`** — §2 gained the 5–8 cutter axis (F8/night-shift valid
   unmodified at every count); §3 and §10 the deterministic 8–10 min C-setup;
   §4 the second J2 exclusion (422 T1/P/T/R/L rows); §5 the simulated-`cut_end`
   "Completed" definition; §11 the new parity gate; §12 a note on what this
   session's work moved (nothing closed). Provenance line bumped to 2026-09-08.
5. **README corrections** — Part 3 row 8 and its "Where each one comes from"
   bullet: "Completed" is the simulated `cut_end`, not `Pull Date` (D3).
   `package.json` description rewritten for the April–June scope.

### 6. Decisions of 2026-11-09/10 and why

Each is also in the code and `SIM_SPEC.md`; this records the reason.

| Decision | Why | Where |
|---|---|---|
| No cold start; the closed-day model, `pin.js` and the warm-start and pull-ahead tables were removed | user: "there will never be a cold start"; the cold start hid the leftover (1.9% of tables late against 51.3% real) | §18 |
| Machine speed factor removed (it was an ESTIMATED 0.80) | user: "if it doesn't related to anything, then remove it"; the model runs at the G2 standard pace | §18 |
| Cutter changeover 5 min (MO or colour change) and moving 1.5 min (another spreader), both ESTIMATES, in the published floor, cutters only | user; spreaders have setup too, "not necessarily need to be added here" | Q19 |
| Rule (a) = pair first, count by pairs, assign pairs over the whole floor; MO on one cut group is an option | user: "I just want the tasks to be distributed back-to-back" | §5 |
| S0 = the real Job Sequence (the SQL core loop) | user: the model's grouped S0 was not how the floor works | §5, Q20–Q23 |
| S0 → S1 is the dispatcher plus pairing, not pairing alone | S1's own dispatcher balances by staffed minutes; S0's SQL balancing does not | §18 stage (iv) |
| The floor is live: 30-min re-plan, ready = plan date + Marker Date + fabric, longest-wait cutter | user rules; "normally it will be dynamic"; operator picks freely | §6b, Q24–Q28 |
| A started pair's partner is pinned next on its spreader | the SQL locks tables processed together; without it the re-plan split pairs | §6b, Q27 |
| Night shift starts 18:00 | user | §4 |
| Lab: Dynamic and Keep same colour close removed; Pull-ahead kept | user | RULE_SET B3 |
| Lab page: Output panel moved down, "where the machine time goes" as four tables (sums and each machine, totals and per day, with a check column) | user: view the idle and working time by option | §17 |

What did **not** change the answer, and should not be re-argued: at the live floor the trolley rules do
not move cutter output (S0, S1, S3 within 0.5%); the cutters wait about 20 h a day, the limit is when
tables become ready (Q26).

### Traps

Each of these was silently wrong until a gate caught it.

1. **Never sort `pieces_by_size`.** `compartments_for` walks it in insertion order, and
   that decides which film width opens a trolley first — which changes the answer once
   the 52 bays are full.
2. **Never round `cut_end` in the trace.** The page sorts loading events by it and times
   the WIP hold against it; rounding reorders near-simultaneous tables.
3. **Python `round()` breaks ties to even, JS `toFixed()` rounds up.** 4,345 trolleys
   over 20 days is exactly 217.25.
4. **`max_batches` 2 and 3 are identical** — `load_trolleys` gates the parked-trolley
   top-up on the global `A.MAX_BATCHES_PER_TROLLEY`, not `scenario.max_batches`.
5. **Grid items default to `min-width: auto`**, so wide content stretches its column and
   scrolls the whole page. Use `minmax(0, 1fr)` and `min-width: 0`.
6. **More batches per trolley *reduces* utilization in 7 of 56 cells**, all at WIP hold
   ≥ 90 min. A greedy-parking artefact: cross-batch combining merges two loading events
   into one, changing which trolley parks first. Pre-existing; the sequencing fix
   improved it (8 dents → 7). Never touches the headline.
7. **`out/results.json` from the Node port used to be a REDUCED SHAPE** (pre
   2026-08-28) — it omitted `per_day`, `hold_variants`, `cut_groups`,
   `night_shift_*`, `sweep_axes`, `table_lengths_m`, `status_colors` and several
   headline fields. **Fixed as of the 2026-08-28 rebuild** — `tools/build.js`
   now writes the full payload shape `run.py` does. Still true of anything built
   before that date: compare shared keys only.
8. **A pin against `out/sweep.json` (no `.bak`) is circular** — it was written by
   the very port being checked. The only non-circular pin is against
   `out/sweep.json.bak` / `out/results.json.bak`, the last genuine Python
   output — but see trap 9: even that pin cannot be a clean, literal "reproduces
   exactly," because `.bak` predates two fixes already in `model.py`.
9. **`out/*.bak` predates the 2026-08-26 sequencing and blocking fixes.** A
   correct port of *today's* `model.py` will not, and should not, reproduce
   `.bak`'s `spreading_blocked_pct`/`cutting_blocked_pct` (every scenario) or
   its `utilization_pct`/`trolleys_per_day`/`peak`/`pieces_per_trolley`
   (`mo_aware=False` scenarios only) — verified by diffing `.bak` against the
   current build: every `mo_aware=True`, hold=0 key matches exactly; every
   `mo_aware=False` key and every blocked-pct field does not, in exactly the
   pattern the 2026-08-26 changelog predicts. `tools/pin.js`'s two-tier design
   (§3 above) exists because of this; do not build a pin that asserts literal
   equality against `.bak` on every field — it will fail forever, correct port
   or not.
10. **A composite dict key built by bare template-literal concatenation of
    variable-length string fields can collide** (`mo='AB'+color='C'` vs
    `mo='A'+color='BC'`) — Python's dict keys are real tuples, which cannot.
    `tools/model.js` joins `mo`/`color`/`batch`/`film`/`machine` with an
    explicit `KEYSEP` character (`String.fromCharCode(1)`), not raw
    concatenation.
11. **SheetJS's `cellDates:true` misdates Excel serials on a non-UTC host** —
    verified against `data/planppc.xlsx`: a plain-integer serial (whose own
    cell format displays "25 May 2026") came back one calendar day earlier with
    a spurious ~7-hour time, on this UTC+7 machine. Every plan date in an early
    build of the port was off by exactly one day because of this. Fixed by
    reading the raw numeric serial (`cellDates:false`) and converting it with
    the textbook formula ourselves; never trust SheetJS's date objects for this
    workbook without cross-checking against the cell's own `.w` formatted value.
12. **Scaling a float by `10^n` then comparing to 0.5 is not the same as
    banker's rounding the float's true value** — it performs a second binary
    rounding step that can manufacture an exact tie the original number never
    had. `totalTrolleys / 20` for one scenario prints as `200.35` and
    `× 10 === 2003.5` exactly in float64, but the double's true value is
    `200.349999999999994315...`, strictly below the midpoint; Python's `round()`
    (which works from that exact value) gives `200.3`. `tools/round.js` rounds
    from the double's exact decimal expansion (`toFixed()` at high precision)
    instead.
13. **`order[machine]` must live inside the per-variant dict, not at mode
    level, once more than one axis affects the sequence.** True for table
    length alone (the sequence didn't depend on it), false the moment
    cutting-machine count became a second axis — a different `CUT_GROUPS`
    layout produces a different assignment via `_pick_machine`'s candidate
    list. Left at mode level, the page silently draws one variant's machine
    queue on a Gantt built for another's timeline. Caught by explicitly
    diffing `order` between two cutting-machine-count variants for the same
    date before trusting the refactor (2026-09-08).
14. **A composite key built from two independent axes (mode, cutter count)
    that share a data structure with a THIRD, older axis (table length) can
    silently reuse a stale value from the older axis.** The Utilization
    tab's `key()`/step-ladder comparison were still built for the old
    boolean `mo_aware` value; the moment `Scenario.sequencing_mode` became a
    3-way string, both would have looked up nonexistent sweep keys and the
    entire tab would have gone blank. Caught only by rebuilding and checking
    a live tile's value, not by any type system — there wasn't one to catch
    it (2026-09-08).
15. **A `.bak` regression fixture predating a model fix cannot be compared
    against the fixed scenario under the SAME name without checking which
    shape the name actually refers to.** `out/*.bak`'s entry named "S1" is
    `cross_batch`-shaped (the pre-fix behaviour); comparing it against the
    live, fixed `same_batch`-shaped S1 fails for a reason that has nothing
    to do with port correctness — the same class of trap as #8/#9 below, now
    proven to recur whenever *what a name refers to* changes underneath a
    fixture that predates the change (2026-09-08).
16. **"Build the heaviest item first, for a size-gate check" and "the last
    item written is the canonical/default one" are two different claims
    that can silently share one variable.** `tools/build.js` reordered
    June to build-first (to check the page-size budget before spending time
    on the rest) and then also used "whichever path the loop wrote last" to
    decide what `out/index.html` copies. Those coincided by chance across 8
    months and broke the moment the month set narrowed to exactly
    April–June, where June is chronologically last but processed first.
    Track the two claims as separate variables (2026-09-08).
17. **`Math.imul` is mandatory for any hash ported from a language with
    arbitrary-precision integers to JS's float64 numbers.** Plain `*` in the
    Type C setup's FNV-1a hash silently loses precision once the running
    hash × the FNV prime (16,777,619) exceeds 2^53, and Python's `& 0xFFFFFFFF`
    on an arbitrary-precision int has no equivalent failure mode — the two
    languages would agree on small inputs and diverge unpredictably on
    larger ones with no error raised in either (2026-09-08).
18. **A minutes total and a chart drawn from "the same" quantity can sit on two
    different clocks.** The idle-time table's `blocked_minutes` is the raw
    wall-clock rule-G6 wait (`_room_at(…) − spread_free_before`, no shift or
    break awareness); the Gantt's red hatching is
    `workingBetween(spreaderShift, prevEnd, ss)` — staffed sub-intervals only.
    The drawn hatching runs about 16% below the minutes total on a typical plan
    date (10–22% by date; 18% across the whole June month, 42,071 vs 51,200 min)
    because the number banks the unstaffed part of any wait that crosses a break
    or runs past shift end, and the hatching does not. The table's lead text used
    to call the two "the chart's hatching" as if they were one figure (2026-09-10).
19. **Results depend on the export's row order** (2026-11-10, Q28). S0's plan order, its ties and the
    cutter's tie-break use row order, so `npm run regress` R1 compares the two workbooks in one row
    order and reports the as-loaded order beside it. Do not read the informational lines as failures.
20. **`regress` re-stamps each batch's first plan date** inside its 18-date subsets (2026-11-10): the live
    floor reads it for fabric readiness and it legitimately differs between the 20-date export and the
    199-date workbook. Without the re-stamp R1 failed on 21,074 of 33,696 cells.
21. **`tools/floor.js` is shared by `model.js` and the Lab**, so "Lab = model" no longer proves the timeline
    independently; it proves everything around it, and `lab_table.js` checks the timeline's own rules
    (a cut never starts before its spread ends, a table never starts before it is ready, a cutter never
    cuts two lays at once).
22. **Per-day machine hours divide by each run's own number of working days**, so a run that finishes
    sooner shows more hours a day for the same work. Compare the totals (the Lab shows both).
23. **`data/SQL Job Sequence Logic.sql` is GBK-encoded** (12,196 lines, Chinese comments): read it with code
    page 936. Its "closest to the cutter's gap" rule is dead code (`@IsFirst` is reset to 1 on every pass),
    and its priority rules live in a database table that is not in the file.
24. **A stray 36 MB PowerPoint sits in `data/`** (dated 2026-11-09 13:08, not ours); the model does not read it.

### Open questions

1. **The 7-day trolley cycle has never been measured.** The single number the business
   case turns on. At the 5-day allowance today already fits. Measuring it for one week
   is the cheapest, highest-value thing on the list.
2. **How does a parked trolley physically reach a different workstation?** Worth
   **+5.9** points if it can, **+0.5** if it cannot. Production must answer, not ISD.
3. **Can the planning system show batch at compartment level?** If not, change 2 cannot
   ship.
4. **Is there floor space to extend the spreading tables** beyond 21.2 m? Unconfirmed —
   this is why routing comes before tables.
5. **Cutting-machine travel time.** *Resolved 2026-11-09 as an ESTIMATE:* it is now in the published
   floor (1.5 min per move, with a 5 min changeover; Q19). Still never timed on the floor.
6. **The cutting-machine-count axis's effect on trolley numbers — measured
   (table T-C, `node tools/tc_table.js`, 2026-09-08).** It moves S0 by about
   +1.4 utilization points / −40 fleet across 5→8 cutters, and moves S1/S2
   nothing (exact 0.00, because at `wip_hold=0` the loader is timeline-
   independent) and S3 ±0.3 (trap 6 artefact). Part 7 §5 re-scoped accordingly.
   *Resolved* (measured on the pre-2026-11-09 floors; HISTORICAL for the live floor).
7. **The Python port of the live floor does not exist.** `tools/floor.js` and the live branch of
   `model.js` have no `model.py` / `floor.py` mirror; Python is not installed, so it could not be run.
   The "mirror, do not improve" rule is broken until it is written.
8. **The live `Job_Seq_Schedule_Priority` table** was not supplied; `ORDER_TYPE_PRIORITY` is an
   ESTIMATE, and 6,499 of 6,501 April–June tables are QR, so it hardly decides anything.
9. **What the operator really picks.** The cutter rule (longest wait first) is a stand-in; nobody has
   measured the real choice.
10. **Marker and fabric inputs as used.** `Marker Date` is a gate by assumption, and the fabric arrival
    window is an ESTIMATE; most of the live floor's waiting is for these (Q26).
11. **A one-rule S1.** S0 → S1 changes the dispatcher and adds pairing. S0 with the SQL's own
    `SameBatchMoTogether` switch on would separate them; not built.
12. **Why S1–S3 lose trolley utilization on the live floor** (S1 58.75 → 58.19, S2 64.67 → 61.17,
    S3 68.77 → 67.45): the script does not isolate it.
13. **The live model is less late than the real floor** (25.98% of tables late against 51.25%, 6.85% more
    than a day late against 15.44%, `npm run carryprobe`). The real floor has something the model does not.
14. **Two-batch trolleys.** The user dropped 2 batches per trolley as a rule to adopt; the old S2/S3 stay in
    the published table as reference. Whether they leave it is undecided.

### 5. HARD CHANGES BEFORE A NEW SESSION

**Read this before touching anything. Nothing in `out/` is a real Python build.**

#### 1. Run `python run.py`.

Python is **not installed on this machine** — `python.exe` on PATH is the Microsoft
Store stub. Everything in `out/` was built by the Node port in `tools/` (see #2):
validated (§3 above), but not the real build.

> Install Python 3.12, tick **Add to PATH**, and disable the Store aliases in
> Settings → Apps → Advanced app settings → App execution aliases.

Also: `run.py:169` still hands `build_dashboard` the path `f'{OUT}/dashboard.html'`,
not `index.html`. That line was deliberately left alone this session (it is a note
for whoever installs Python, not part of the garments-per-trolley/Gantt fix) — but
the first real `python run.py` run after Python is installed will write
`out/dashboard.html`, not update `out/index.html`, unless that line is changed
first.

#### 2. The Node port now lives in the repo, at `tools/`.

**Fixed as of 2026-08-28** — it used to live in session scratchpad and would not
survive between sessions; it has been rewritten into `tools/` (`assumptions.js`,
`model.js`, `scenarios.js`, `daytrace.js`, `round.js`, `build.js`, `pin.js`), plus
`xlsx` (SheetJS) added to `package.json` as a build-only devDependency (never
reaches `out/index.html`). Build with `node tools/build.js`; the pin
(`node tools/pin.js`, HISTORICAL, retired 2026-11-09; see §3 above for what it did and did not establish).
`jsdom` was also added as a dev-only dependency, used for one-off QA of the built
page (loading `out/index.html`, clicking tabs, moving the cursor, checking for
runtime errors) — not required by the build itself.

#### 3. Do not delete `out/*.bak`.

`results.json.bak`, `sweep.json.bak`, `dashboard.html.bak` are the last genuine Python
output and were the **only non-circular pin** on the port (HISTORICAL: no gate has read them since 2026-11-09).

#### 4. `idle_variants.py` and `test_csetup.py` have never run in Python.

`idle_variants.py` now has a **Node mirror, `tools/idle_variants.js`**, which
*has* run (2026-09-08) and prints §2/§3/§4/§4b as markdown on the full
199-date file — its "Today" row is 1,563 blocked min/day, 16% over window
(README Part 7 §2's scope note explains why that differs from the published
20-date 1,997 / 25%). `idle_variants.py` gained the same **§4b** (the
cutting-machine-count ladder, `measure_cutters()`) but has still never
executed — no Python. First thing after Python works: run `idle_variants.py`,
diff its output against `tools/idle_variants.js`'s (they should match the way
`model.py` and `tools/model.js` do — mirror, not improve), then update
[Part 7](#part-7--idle-time) §2–§4 to the 199-date basis with a before/after.
Also run `test_csetup.py` (`python -m pytest test_csetup.py -q`) to confirm
Python's FNV-1a hash and tenths mapping agree bit-for-bit with the Node port.
Note the deliberate asymmetry: `idle_variants.py` / `tools/idle_variants.js`
read the full 199-date file unscoped by `WEBSITE_MONTHS`, while the website is
April–June only — the two sets of idle-time figures come from different date
ranges on purpose. (`tools/tc_table.js`, table T-C, reports both scopes.)

#### 5. The agents only register at startup.

`.claude/agents/*.md` were written mid-session and needed a restart.

#### 6. The sensitivity table has two dead rows.

In [Part 5](#part-5--sensitivity--what-is-not-the-constraint), marked as coming from a
variant that no longer exists. Regenerating them needs a `max_chain` field on
`Scenario` and a loop replacing the `seq[i], seq[i+1]` pair test in `_loading_events`.

#### 7. Phases 5B and 6 of the 2026-09-08 session are done.

Both shipped and verified — see [§4's "Phase 5B — shipped" and "Phase 6 —
shipped"](#4-shipped--session-2026-09-08-8-month-data-cutting-machine-count-same-mo-sequencing-split-and-a-page-size-retreat-to-3-months).
The gate suite was then **`npm run pin` + `npm run regress` + `npm run parity`**
(HISTORICAL: since 2026-11-09 it is `lab` + `build` + `regress` + `parity` + an Edge check; the pin is retired). What remains is Python-only, covered by #1/#4 above: run
`run.py`, `idle_variants.py` (diff against `tools/idle_variants.js`) and
`test_csetup.py`, then move Part 7 §2–§4 onto the 199-date basis with a
before/after table.
