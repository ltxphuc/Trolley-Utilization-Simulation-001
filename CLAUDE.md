# CLAUDE.md

Behavioural guidelines to reduce common LLM coding mistakes, merged with the rules of
this project. They bias toward caution over speed. For trivial tasks, use judgement.

The project lives in `cct-trolley-model/`: a simulation of Central Cutting's Job
Sequence and Panel Loading, run on real `HaveCut` data, used to size the trolley fleet
and study machine idle time.

---

## 1. Think before coding

Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them. Don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity first

Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical changes

Touch only what you must. Clean up only your own mess.

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match the existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it. Don't delete it.

When your changes create orphans:
- Remove imports, variables and functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: every changed line should trace directly to the user's request.

## 4. Goal-driven execution

Define success criteria. Loop until verified.

Turn tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work")
require constant clarification.

---

## 5. Project rules

### Read first

1. `cct-trolley-model/SIM_SPEC.md`: exactly what the simulation computes. It holds
   inputs, constants, algorithms, quirks Q1–Q19 (Q5–Q7 and Q16 retired with the cold start), validation targets (§14), open
   decisions (§15) and the codebase map (§16).
2. `cct-trolley-model/RULES.md`: why each rule exists (H1–H9, F2–F8, G2–G6, J2–J3, L6).
3. `cct-trolley-model/README.md`: history and published findings. **Partly stale.**
   Check any number in it against the code before quoting it.

**The code wins** over every document. If a document disagrees with the code, the
document is stale. Say so; don't silently follow it.

### Numbers

- `assumptions.py` (mirrored in `tools/assumptions.js`) is the **only** place a number
  may live. Nothing is hard-coded in the model. Every value cites its rule.
- An estimate is marked `ESTIMATE` in capitals. Never present an estimate as measured.
  The biggest one is `CYCLE_DAYS_ESTIMATED = 7`, which has never been timed.
- Any change that moves a published number is reported with a **before/after table**,
  never absorbed silently into a new baseline.
- Every published table must be reproducible by a script in this repo. No numbers
  from throwaway scratch scripts.
- Idle time and the trolley shortage are **independent findings**. Never claim a
  saving in one for the other.
- When a number depends on an assumption you made (for example a setup time or a trip
  time), say so next to the number.

### Code

- **Python is not installed on this machine.** `python.exe` is a Microsoft Store stub.
  The Node port in `cct-trolley-model/tools/` is what actually runs, and it produced
  everything in `out/`.
- **Mirror, don't improve.** `tools/model.js` must match `model.py` exactly, quirks
  included. Fixing a quirk is a separate, announced change with a before/after table.
  A model change goes into both languages.
- Results must be **deterministic**. Never use `Math.random()`. Hashes in JS use
  `Math.imul`.
- Never sort `pieces_by_size`, and never round `cut_end`. Film-keyed structures in JS
  are `Map`s (insertion order matters).
- Read Excel dates as raw serials (`cellDates: false`). SheetJS's date conversion is
  one day off on this UTC+7 machine.
- New what-if analysis goes in a **measurement script** in `tools/` (like
  `tc_table.js`, `idle_variants.js`). These scripts never feed
  the build. Move logic into the model only when the user asks, and then with a
  before/after table.

### Files you must not touch

- Never hand-write anything in `out/`. It is all build output.
- **Never edit or delete `out/*.bak`.** They are the last genuine Python output. No
  gate has read them since 2026-11-09 (the pin was retired with the cold start).
- Don't modify the source data in `data/`.

### Running things (from `cct-trolley-model/`)

| Command | What it does |
|---|---|
| `npm run build` | rebuilds `out/` (needs the 6 GB heap; already in the script) |
| `npm run lab` | **gate:** Rules Lab checks (vs model.js `runCarry()`) and comparison tables; the same `tools/lab.js` is inlined into the page |
| `npm run regress` | **gate:** 18 shared dates × 117 scenarios, old file against new, on `runCarry()` (a reader check, not published numbers; the two subsets are copied and re-stamped from their own dates, because the live floor reads each batch's first plan date) |
| `npm run parity` | **gate:** the page's loader against the model, in Edge |
| Edge check | **gate:** open the Utilization, Simulation and Lab tabs in Edge: no console errors, badge green on the defaults |
| `npm run idle`, `tc` | measurement tables (carry-over; the old cold-start figures are printed beside, marked historical) |
| `npm run beforeafter` | the staged before/after, April–June: (0) as published 2026-11-06 → (i) pairs rule → (ii) cutter changeover and moving → (iii) no speed factor → (iv) S0 = the real Job Sequence → (v) the live floor (= the published model). Asserts that stage (0) reproduces the 2026-11-06 headline, stage (iii) the 2026-11-09 headline, stage (iv) the 2026-11-10 headline, that stage (v) equals `out/results.json`, and that S1–S3, the hold variants and the 78 non-`today` sweep keys do not move from (iii) to (iv). The cold start → carry-over comparison is retired (history in SIM_SPEC.md §18) |
| `npm run carryprobe` | validation, not calibration: the model's lateness against the real Pull Date (nothing is tuned to it) |

Run any script that reads the 23 MB workbook with `node --max-old-space-size=6144`.

**Nothing is published if lab, regress or parity fails.** `npm run build` rebuilds `out/`;
run lab, build, regress and parity, then the Edge check, after any change to the model,
scenarios, trace or page, and report the result as it is.

### Scope

- The published site and headline cover **April–June 2026** only (`WEBSITE_MONTHS`,
  79 plan dates). `load_days()`, the gates and the measurement scripts see the full
  199-date file. Always say which scope a number comes from.
- **The published model is the carry-over floor** (user rule, 2026-11-06: no cold start,
  work is always left from the day before): `runCarry()` in `tools/model.js`, `run_carry()` in
  `model.py`, machines at the G2 standard pace. **There is no speed factor** (removed 2026-11-09,
  user: "If it doesn't related to anything, then remove it"), and no cold start (the closed-day
  `run()` was removed the same day). Cutter changeover 5 min (MO or colour change) and moving
  1.5 min (different spreader) are in the published model, cutters only; **both are ESTIMATES**
  (quirk Q19). S1–S3 pair first and assign each pair over the whole floor (rule (a), below).
  **S0 is the real Job Sequence since 2026-11-10** (user data `data/SQL Job Sequence Logic.sql`,
  `P_Task_Calculate`, core loop only: every table gets a cutter, then the least-loaded spreader takes
  the shortest waiting table; `sequenceJobSeq`, SIM_SPEC.md §5, quirks Q20–Q23). Its priority by order
  type (SQR, QR, Normal) is an ESTIMATE (the live priority table was not supplied).
  **The floor is live since 2026-11-10** (`tools/floor.js`, shared by `model.js` and the Lab; SIM_SPEC.md
  §6b, quirks Q24–Q28; user rules): the Job Sequence **re-plans every 30 minutes**, around the clock,
  every ready table not yet started, for the next 24 h; a table starts only once it is **ready**
  (its plan date's 07:15, its `Marker Date`, and its fabric: the relaxing ESTIMATE); a partner of a
  started pair stays next on its spreader (rule (a)); and **a free cutter takes the lay that has waited
  longest** (ESTIMATE, a stand-in for the operator's free choice). `A.LIVE_FLOOR = false` is the floor
  of 2026-11-09 (plan once at 07:15, every table ready, the cutter cutting in spread order), kept only
  for `npm run beforeafter`.
  Headline to reproduce (April–June, 79 plan dates, live floor, G2 pace, changeover 5 / moving 1.5
  ESTIMATES, fleet at the 7-day trip ESTIMATE): S0 51.85% / 203.8 trolleys a day / 1,426 fleet
  (peak 317); S1 58.19% / 175.8 / 1,231; S2 61.17% / 167.3 / 1,171; S3 67.45% / 151.7 / 1,062.
  Cutter output (pieces the cutters cut a day): real plan S0 80,216, S1 80,222, S3 80,211; 100k plan
  S0 96,700, S1 96,576, S3 97,119. **The trolley rules do not change cutter output** (all within
  0.5%); the floor is held back by readiness (marker and fabric), not by the rules.
  **S0 → S1 still changes the dispatcher and adds pairing (two changes).**
  How it got here, stage by stage (the 2026-11-10 build before the live floor was S0 51.92% / 203.5 /
  1,424 and S3 68.77% / 148.4 / 1,039; the 2026-11-09 build S0 53.49% / 195.9 / 1,371; the 2026-11-06
  build S0 52.49% / 201.1 / 1,408, at an ESTIMATED speed 0.80): `npm run beforeafter`, SIM_SPEC.md §18.
  Known gap: the live S0 is less late than the real floor (25.98% of tables late against 51.25% real,
  6.85% more than a day late against 15.44%, `npm run carryprobe`). Accepted and reported, not tuned away.
  **Python mirror gap:** `tools/floor.js` and the live floor in `model.js` have no `model.py` /
  `floor.py` port yet (Python is not installed, so it could not be run); the Node port is what runs.
  Night shift starts at 18:00 (user, 2026-11-09; it moves no published number).

### Comparison standard

S0 is the current situation (the real Job Sequence, see Scope). S1, S2 and S3 add one rule at a time on **exactly the same floor**
and are compared back to S0. Shift, machine pace, fabric relaxing, cutter setup and travel are
floor facts and sit in every row, S0 included; only the rules differ. Pull-ahead, dynamic
dispatch, recall and colour grouping are new rules, never in S0. Cutter setup, travel and waiting
are all lost time; more setup must never show more output. Every number quoted names its run:
plan (real or 100k), scenario and floor settings.

**Rule (a), in the user's words (2026-11-09):** tables of the same MO are paired and spread
back-to-back; the tasks and takt time are counted **by pairs**, not by single tables. The system
pairs first, then assigns the pairs to maximise cutting-machine output. Keeping a whole MO on one
cut group is a **separate option**, not rule (a). At the G2 standard pace the two ways differ by
under 0.3% of cutter output (cutters are no longer the bottleneck, the spreaders are); the trolley
findings differ more (S3 68.77% pairs vs 70.37% MO on one cut group). Independent findings, never
traded (`npm run beforeafter`, SIM_SPEC.md §18).

### Agent chain

**Paused 2026-11-10 (user: "Now just ignore the agents. That costs me too much token. Use Sonnet to
code based on your plan."):** the main session plans, codes and runs the gates itself, without the
planner / coder / tester agents, until the user asks for them again. Never report success without
the gates (lab, build, regress, parity, Edge) having been run. The description below is the chain
as it stands when switched back on.

Agents live in `cct-trolley-model/.claude/agents/`. **The main session is the Logic Thinker**
(`logic-thinker.md`): it is the one talking to the user, it keeps all the rules together and
makes sure no coding or planning bends them. It drafts the plan, argues it back and forth with
the Planner, and only then brings the agreed plan to the user. It relays between the agents,
passing each block verbatim:

```
logic thinker drafts the plan
  <-> planner  REVIEW   PLANNER REVIEW -> LOGIC THINKER RESPONSE -> re-review   (at most 3 rounds)
  -> agreed plan -> user approves
  -> coder     BUILD    returns CODER REPORT
  -> tester    VERIFY   returns TESTER REPORT: PASS, or FAIL + smallest repro
       FAIL -> coder fixes -> tester re-verifies   (at most 3 rounds, then stop and tell the user)
  -> main session reports to the user
  -> compacter RECORD   only when the user asks to save
```

**Models (user, 2026-11-09):** planning and logic thinking (`planner`, `logic-thinker`) use
Opus 5.5; coding and testing (`coder`, `tester`) use Sonnet 5.5. The `model:` line in each agent
file says so. The main session is the Logic Thinker, so it should be on Opus 5.5 when planning.

**Once the user confirms a plan, every step of it is executed by agents** (coder builds, tester
verifies). The main session relays and reports; it does not edit code or run the build itself.

Never report success without a `TESTER REPORT` PASS.