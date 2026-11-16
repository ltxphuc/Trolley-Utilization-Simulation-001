# Rules

Every rule the simulation obeys, one line each. Read this to know **what** the model assumes about the
floor. [SIM_SPEC.md](SIM_SPEC.md) says **how** each rule is computed; [README.md](README.md) explains the
website.

**How to read a rule:** `ID | Rule | Value | Source`.

| Source | Meaning |
|---|---|
| Rulebook H1, F2, G6… | the factory rulebook (`RULES.docx`) and the Job Sequence flowchart (not in this repo) |
| Panel Loading 1a-n, 1b-n | the current Job Sequence / Panel Loading Suggest Logic |
| SQL | `data/SQL Job Sequence Logic.sql`, procedure `P_Task_Calculate` |
| user, date | a decision or measurement given by the project owner on that date |
| ESTIMATE | a stand-in value that has **not** been measured |

IDs without a rulebook code (R, LF, JS, T, M, B, C, E, SIM) are this repo's own labels.

Every number lives in [`tools/assumptions.js`](tools/assumptions.js). If this file and the code disagree,
the code is right and this file is out of date.

**Split for other factories:** Part A is the **common rules**, which a simulation of another cutting floor
keeps. Part B is **this factory's floor facts** (machines, shifts, table length, fleet), which another
factory replaces with its own.

## Contents

- [A. Common rules](#a-common-rules)
  - [A1. Trolley and compartment](#a1-trolley-and-compartment)
  - [A2. When two tables may share a trolley (today's logic)](#a2-when-two-tables-may-share-a-trolley-todays-logic)
  - [A3. Which tables are modelled](#a3-which-tables-are-modelled)
  - [A4. Machine time](#a4-machine-time)
  - [A5. When a table may start](#a5-when-a-table-may-start)
  - [A6. The live floor](#a6-the-live-floor)
  - [A7. S0: today's Job Sequence](#a7-s0-todays-job-sequence)
  - [A8. What is measured](#a8-what-is-measured)
- [B. This factory's floor facts (Central Cutting)](#b-this-factorys-floor-facts-central-cutting)
- [C. The three proposed changes (S1–S3)](#c-the-three-proposed-changes-s1s3)
- [D. Estimates](#d-estimates)
- [E. Rules of the simulation itself](#e-rules-of-the-simulation-itself)
- [F. Ideas tested and ruled out](#f-ideas-tested-and-ruled-out)

---

## A. Common rules

### A1. Trolley and compartment

| ID | Rule | Value | Source |
|---|---|---|---|
| H3 | A trolley has a fixed number of compartments. | 5 | Rulebook H3 |
| H1 | A compartment holds a limited number of garments. | 150 | Rulebook H1 |
| H4 | A compartment holds one batch and one garment size. A trolley holds one film size in all its compartments. | — | Rulebook H4 |
| H5 | Each garment size is cut on a fixed film width. | XXS, XS, S → 90 cm · M, L → 100 cm · XL, XXL, 3XL, 4XL → 110 cm | Rulebook H5 (stands in for Net_Rate, which the data does not have) |
| H6 | Trolley utilization = compartments opened ÷ compartments available. It counts slots used, not garments. | — | Rulebook H6 |
| H8 | A combine may not need more than a set number of trolleys. | 4 | Rulebook H8 |
| H9 | Two tables share a trolley only if they belong to the same MO. | — | Rulebook H9 |
| L2, L3 | Recut and CPI work compartment by compartment, so the system shows information per compartment. | — | Rulebook L2, L3 |
| L6 | One component is normally printed per style, and front and back pieces usually share a Net_Rate. | — | Rulebook L6 |

### A2. When two tables may share a trolley (today's logic)

**Combine:** the trolleys of a later table wait for an earlier table, only if every condition holds.

| ID | Condition | Change 1–3 (Part C) |
|---|---|---|
| 1a-1 | The tables are spread continuously at one workstation. | kept |
| 1a-2 | Same MO. | kept |
| 1a-3 | Same batch. | **relaxed** by Change 2 |
| 1a-4 | Same component. | kept |
| 1a-5 | Same film code. | kept |
| 1a-6 | The trolleys still have empty compartments. | kept |
| 1a-7 | The current table needs no more than 4 trolleys (H8). | kept |
| 1a-8 | The trolleys still have empty compartments (repeats 1a-6). | kept |
| 1a-9 | A trolley may wait only if both tables are spread and cut at one workstation without the cutter leaving it. | **removed** by Change 3 |

**Come back:** a trolley returns from CCT WIP for a later table, only if every condition holds.

| ID | Condition | Change 1–3 (Part C) |
|---|---|---|
| 1b-1 | Same MO. | kept |
| 1b-2 | Same batch. | **relaxed** by Change 2 |
| 1b-3 | Same colour. | kept |
| 1b-4 | Same component. | kept |
| 1b-5 | Same film code. | kept |
| 1b-6 | The trolley still has empty compartments. | kept |

The model checks MO, colour, batch and the 4-trolley limit. Film is handled per compartment, and component
is not in the data ([SIM_SPEC.md](SIM_SPEC.md) quirk Q2).

### A3. Which tables are modelled

| ID | Rule | Value | Source |
|---|---|---|---|
| J2 | Only Type B tables are modelled. Rows marked First Table = Y are left out, and so are the other row types (T1, P, T, R, L, W). | — | Rulebook J2 |
| J3 | Tables with kids or number sizes take machine time but load no compartments, because their sizes are not in the H5 film map. | — | Rulebook J3 |
| G3 | A Type C row adds setup time to its B table on the same physical table: one setup per B table that has any C row. | 8–10 min, **ESTIMATE** | Rulebook G3 (also I3, N) |

### A4. Machine time

| ID | Rule | Value | Source |
|---|---|---|---|
| G2 | Spreading time = layers × marker length (yd) × the spreading rate. Cutting time = layers × marker length × the cutting rate. | 0.80/8.5 and 0.40/8.5 min per layer per yard | Rulebook G2 |
| T1 | Machines run at the G2 standard pace. There is no speed factor. | — | user, 2026-11-09 |
| G6 | A spreader can start a lay only when the table has free length for the whole lay. The cutter gives the length back gradually as it cuts. | full lay length, no end allowance | Rulebook G6 |
| T2 | A break stops the machines. A task cut off by a break resumes after it. | — | assumption, **unconfirmed** |
| T3 | A cutter loses changeover time when the next table's MO or colour differs from its last cut. | 5 min, **ESTIMATE** | user, 2026-11-09 |
| T4 | A cutter loses moving time when the next table is on a different spreader from its last cut. | 1.5 min, **ESTIMATE** | user, 2026-11-09 |
| T5 | The spreading table stays occupied while the cutter changes over and moves. | — | this model ([SIM_SPEC.md](SIM_SPEC.md) Q19) |
| T6 | Spreaders lose no changeover or moving time beyond the Type C setup (G3). | — | user, 2026-11-09 |
| T7 | A cutter always moves between the spreaders it serves. It does not stay at one spreader to cut both tables of a pair. | — | user, 2026-11-09 |

### A5. When a table may start

A table is **ready** at the latest of R1, R2 and R3.

| ID | Rule | Value | Source |
|---|---|---|---|
| R1 | A table may start no earlier than the start of its plan date. | 07:15 | user, 2026-11-10 |
| R2 | A table may start no earlier than its Marker Date (when its marker is ready). | from the data | user, 2026-11-10 |
| R3 | Fabric must relax before it is spread, so a table may start only once its batch's fabric has relaxed. | 24 h | factory rule |
| R4 | Each batch's fabric arrives a fixed time before the batch's first plan date. The data has no arrival time. | 12–48 h before, **ESTIMATE** | user, 2026-11-10 |
| R5 | There is no cold start: work a machine did not finish carries into the next shift, and every plan date is planned around what the machines still have. | — | user, 2026-11-06 |

### A6. The live floor

| ID | Rule | Value | Source |
|---|---|---|---|
| LF1 | The Job Sequence re-plans at a fixed interval, around the clock, in every shift. | every 30 min | user, 2026-11-10 |
| LF2 | Each re-plan takes every ready table not yet started, oldest plan date first, until the spreaders' capacity for the next window is full. | 24 h | user, 2026-11-10 |
| LF3 | Once the first table of a pair starts, its partner stays next on that spreader and is not re-planned. | — | rule (a), user, 2026-11-10 |
| LF4 | A free cutter takes the waiting lay that has waited longest, among the spreaders it serves. | **ESTIMATE** (stands in for the operator's own choice) | user, 2026-11-10 |

### A7. S0: today's Job Sequence

S0 is the current situation. It follows the core loop of the stored procedure.

| ID | Rule | Value | Source |
|---|---|---|---|
| JS1 | Every table first gets a cutter: one that already has a table of the same MO and batch that day, otherwise the one with the lowest load per spreader it serves. | — | SQL |
| JS2 | Then, again and again, the spreader with the fewest committed spreading minutes takes, among the tables for its cutter, the one with the shortest spreading time. | — | SQL |
| JS3 | Tables are taken in order of order type: SQR first, then QR, then Normal (anything else counts as Normal). | **ESTIMATE**: the live priority table was not supplied | SQL (commented-out older rule) |
| JS4 | Ties go by plan order for tables and by spreader number for spreaders. | — | this model (the SQL leaves ties open) |

### A8. What is measured

| ID | Measure | Definition | Source |
|---|---|---|---|
| M1 | Trolley utilization | compartments opened ÷ (5 × trolleys), pooled over all plan dates (H6) | Rulebook H6 |
| M2 | Compartment fill | garments ÷ (150 × compartments opened): how full the opened compartments are | this project |
| M3 | Trolleys a day | trolleys sent ÷ plan dates | this project |
| M4 | Fleet needed | trolleys a day × round-trip days | this project |
| M5 | Longest round trip the fleet covers | trolleys owned ÷ trolleys a day | this project |
| M6 | Pieces cut a day | every piece the cutters finish inside the plan period ÷ plan dates (all sizes, J3 included) | this project |

---

## B. This factory's floor facts (Central Cutting)

Another factory replaces this part with its own.

| ID | Fact | Value | Source |
|---|---|---|---|
| F2 | Spreaders and the cutter that serves each group. | 13 spreaders, 5 cutters: 24MC1 → 24-01, 02, 03 · 24MC2 → 24-04, 05 · 24MC3 → 24-06, 07 · 24MC4 → 24-08, 09, 10 · 24MC5 → 24-11, 12, 13 | Rulebook F2 |
| F8 | Two spreaders may call a second cutter; the cutter that is free first takes the table. | 24-03 → 24MC1 or 24MC2 · 24-05 → 24MC2 or 24MC3 | Rulebook F8 |
| F5–F7 | Only these machines work the night shift. | 24-01, 24-02, 24-03 and 24MC1 | Rulebook F5–F7 |
| B1 | Day shift and its breaks. | 07:15–20:00; breaks 11:45–12:45 and 17:15–17:45; 675 staffed min | measured, user, 2026-08-26 |
| B2 | Night shift and its breaks. A night machine runs on from the day shift. | 18:00–05:00; breaks 22:00–22:30 and 02:00–02:30; 1,155 staffed min a day | user, 2026-11-09 |
| B3 | Spreading table length, the same on all 13 spreaders. | 21.2 m (23.18 yd) | measured, user, 2026-08-26 |
| H7 | Part-filled trolleys that may wait at once (workstations × positions). | 52 (13 × 4) | Rulebook H7 |
| B4 | Trolleys owned. | 1,200 | fact |
| B5 | Round-trip allowance for a trolley (1 + 3 + 1 days). | 5 days | allowance |
| B6 | Round trip actually assumed for the fleet figures. | 7 days, **ESTIMATE, never timed** | — |
| B7 | Pieces Central Cutting must cut a day. | 100,000 | user, 2026-11-06 |

---

## C. The three proposed changes (S1–S3)

Each change adds one rule to the floor of S0. Nothing else differs between S0 and S1–S3 (SIM5).

| Scenario | Same-MO sequencing | Batches per trolley | WIP hold |
|---|---|---|---|
| S0 Today | off (A7) | 1 | none |
| S1 | Same batch only | 1 | none |
| S2 | Cross-batch | 2 | none |
| S3 | Cross-batch | 2 | 60 min, any workstation |

### Change 1: same-MO sequencing (rule (a))

| ID | Rule | Value | Source |
|---|---|---|---|
| C1.1 | Tables of the same MO and colour that can share a trolley are paired before they go to a machine: same-batch pairs first, then (Cross-batch only) different-batch pairs. | — | user, 2026-11-09 |
| C1.2 | Both tables of a pair are spread back-to-back on one spreader. A pair is never split. | — | user, 2026-11-09 |
| C1.3 | Work and takt time are counted by pairs. Each pair or lone table goes to the cut group whose busier side (its spreaders or its cutter) stays least loaded, over the whole floor. | — | user, 2026-11-09 |
| C1.4 | Within the cut group, a pair goes to the least-loaded spreader that stays under the fill target. If none does, it goes to any spreader on the floor that does, and if none at all, to the one with the lowest load for its staffed time. | 70% of the staffed window (planning heuristic) | this project |
| C1.5 | Option, not part of rule (a): keep every pair of one MO and colour on one cut group. | off | user, 2026-11-09 |

### Change 2: two batches per trolley

| ID | Rule | Value | Source |
|---|---|---|---|
| C2.1 | A trolley may carry 2 batches of the same MO and colour in separate compartments, never 3. | 2 | floor rule |
| C2.2 | Two batches may share a trolley only with Cross-batch sequencing. | — | user, 2026-11-14 |
| C2.3 | With 1 batch per trolley, a trolley never takes a second batch, also not when a waiting trolley is topped up. | — | user, 2026-11-14 |
| C2.4 | Tables of the same batch merge same-size pieces into one compartment, up to 150. Tables of different batches keep their own compartments. | 150 | Panel Loading rule 2 |
| C2.5 | The operator, CPI and recut must see which batch is in which compartment. | — | Rulebook L3 |

The user kept S2 and S3 in the published table as reference scenarios rather than as a rule to adopt
(user, 2026-11-09).

### Change 3: WIP hold and recall

| ID | Rule | Value | Source |
|---|---|---|---|
| C3.1 | A trolley that leaves with empty compartments waits in CCT WIP instead of being sent on. | — | this project |
| C3.2 | A waiting trolley is sent on as it is once it has waited the hold time. | 60 min | this project |
| C3.3 | A newly cut table first tops up a waiting trolley of the same MO, colour and film, within the batch limit. Batch is not part of the match. | — | this project |
| C3.4 | A waiting trolley may be recalled to any workstation, or only to the one it left. | any workstation | this project (open question: how a trolley moves between workstations) |
| C3.5 | When several waiting trolleys match, the order is one of three: any match (published), same batch first, same batch only. | any match | user, 2026-11-05 |
| C3.6 | A trolley that cannot park, because all H7 positions are taken, is sent on. | 52 | Rulebook H7 |

### Other what-ifs in the Rules Lab (new rules, never in S0)

| ID | Rule | Value | Source |
|---|---|---|---|
| C4.1 | Pull-ahead: a spreader that has finished the released plan may start tables of the next plan dates, if their fabric has relaxed. | 0 (off); 1, 2, 3 or all plan dates | user, 2026-11-05 |
| C4.2 | Shift: both shifts, day only, or night only. | both | user, 2026-11-05 |

---

## D. Estimates

These values stand in for measurements nobody has taken yet. Every result that depends on them says so.

| ID | Estimate | Value | What it stands in for |
|---|---|---|---|
| E1 | Trolley round trip (B6) | 7 days | the real dispatch-to-return time. The whole fleet case turns on it |
| E2 | Cutter changeover (T3) | 5 min | the real clean-up and speed change on an MO or colour change |
| E3 | Cutter moving (T4) | 1.5 min | the real time to move to another spreader |
| E4 | Fabric arrival (R4) | 12–48 h before the batch's first plan date | the real arrival time, not in the data |
| E5 | Cutter pick (LF4) | the longest-waiting lay first | the operator's own choice |
| E6 | Order-type priority (JS3) | SQR, QR, Normal | the live priority table |
| E7 | Type C setup (G3) | 8–10 min | the real setup, because C rows carry placeholder layers and lengths |
| E8 | Film map (H5) | 90 / 100 / 110 cm by size | the real Net_Rate. The real mapping puts more sizes on one film, so utilization here is on the low side |
| E9 | Breaks stop the machines (T2) | yes | unconfirmed; about 150 min per machine a day if they don't |
| E10 | Spreader fill target (C1.4) | 70% | a planning heuristic with no written source |

---

## E. Rules of the simulation itself

| ID | Rule |
|---|---|
| SIM1 | The code wins. If a document disagrees with the code, the document is out of date. |
| SIM2 | Every number lives in `tools/assumptions.js` and cites its rule. An estimate is marked ESTIMATE. |
| SIM3 | Results are deterministic: no random numbers; every run on the same data gives the same result. |
| SIM4 | A change that moves a published number is reported with a before/after table. |
| SIM5 | S1–S3 run on exactly the same floor as S0; only the rules differ. Shifts, pace, fabric relaxing, cutter changeover and moving are floor facts in every scenario. |
| SIM6 | Idle time (cutter output) and the trolley shortage are separate findings. A saving in one is never claimed for the other. |
| SIM7 | Every published table can be reproduced by a script in this repo. |
| SIM8 | Lost time (setup, moving, waiting) can never show more output. |
| SIM9 | Every number names its run: the plan (real or 100k), the scenario and the floor settings. |
| SIM10 | The published scope is April–June 2026 (79 plan dates, 6,501 tables). |
| SIM11 | Nothing is published unless the gates pass (lab, regress, parity, and the page check in Edge). |

---

## F. Ideas tested and ruled out

Not to be proposed again without new information. Details are in [docs/HISTORY.md](docs/HISTORY.md).

| Idea | Why it was ruled out |
|---|---|
| A cold start (every plan date empty at 07:15) | user, 2026-11-06 and 2026-11-09: there is always work left from the day before (R5) |
| A machine speed factor | user, 2026-11-09: removed, because it was not tied to anything measured (T1) |
| Raising the 4-trolley combine limit (H8) | +0.7 points only; the limit is not what holds utilization down |
| Chaining more than two tables per trolley set | +0.5 points only (an earlier model, not reproducible now) |
| Change 2 without Change 1 | +0.6 points: two tables can only share a trolley if they are spread back-to-back |
| Tuning the 70% fill target | 0.60 and 0.85 both scored worse |
| Balancing cut groups by capacity instead of spreader count | fewer overruns but a longer day; work moves onto the night machines |
| Treating the table as fixed slots that empty at cut end | overstated blocking by 63%; the table frees gradually (G6) |
| The cutter staying at one spreader to cut both tables of a pair | user, 2026-11-09: the cutter always moves (T7) |
| A dynamic spreader pick in the Lab | user, 2026-11-10: removed; the live floor is used in every scenario |
| Keeping the same colour close | user, 2026-11-10: tables are arranged in pairs instead |
| Cutter count and table length as page controls | user, 2026-11-16: more cutters change little when the plan cannot keep up; table length is kept in the engine for other factories |
