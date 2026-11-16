# Rules

Every rule the simulation obeys, and every rule in the factory rulebook, one line each. Read this to know
**what** the model assumes about the floor. [SIM_SPEC.md](SIM_SPEC.md) says **how** each rule is computed;
[README.md](README.md) explains the website; [docs/DATA_MODEL.md](docs/DATA_MODEL.md) lists every value and
formula.

**How to read a rule:** `ID | Rule | Value | Source | Model`. **Model** says whether the simulation
applies the rule: **yes**; **partly** (how it differs); **no** (why not).

| Source | Meaning |
|---|---|
| Rulebook A.1 … Q.1 | the factory rulebook, [`data/RULES.docx`](data/RULES.docx). Its coded rules (F1–P4) keep their codes; its uncoded first part gets dot IDs: A.1–A.6, B.1–B.3, C.a, C.b, C.c, C.4, D.a, D.b, E.1–E.3, Q.1 |
| Panel Loading 1a-n, 1b-n | the current Job Sequence / Panel Loading Suggest Logic |
| SQL | `data/SQL Job Sequence Logic.sql`, procedure `P_Task_Calculate` |
| user, date | a decision or measurement given by the project owner on that date |
| ESTIMATE | a stand-in value that has **not** been measured |

IDs that are not rulebook codes (R, T, LF, JS, KPI, B, C1.1 …, E, SIM) are this repo's own labels.
[Part G](#g-rulebook-coverage) lists every rulebook rule and where it is here.

Every number lives in [`tools/assumptions.js`](tools/assumptions.js). If this file and the code disagree,
the code is right and this file is out of date.

**Split for other factories:** Part A is the **common rules**, which a simulation of another cutting floor
keeps. Part B is **this factory's floor facts** (machines, shifts, table length, fleet), which another
factory replaces with its own.

## Contents

- [A. Common rules](#a-common-rules)
  - [A1. Trolley and compartment](#a1-trolley-and-compartment)
  - [A2. When two tables may share a trolley](#a2-when-two-tables-may-share-a-trolley)
  - [A3. Which tables are modelled](#a3-which-tables-are-modelled)
  - [A4. Machine time](#a4-machine-time)
  - [A5. When a table may start](#a5-when-a-table-may-start)
  - [A6. The live floor](#a6-the-live-floor)
  - [A7. S0: today's Job Sequence](#a7-s0-todays-job-sequence)
  - [A8. What is measured](#a8-what-is-measured)
  - [A9. Rules outside the trolley model](#a9-rules-outside-the-trolley-model)
- [B. This factory's floor facts (Central Cutting)](#b-this-factorys-floor-facts-central-cutting)
- [C. The three proposed changes (S1–S3)](#c-the-three-proposed-changes-s1s3)
- [D. Estimates](#d-estimates)
- [E. Rules of the simulation itself](#e-rules-of-the-simulation-itself)
- [F. Ideas tested and ruled out](#f-ideas-tested-and-ruled-out)
- [G. Rulebook coverage](#g-rulebook-coverage)

---

## A. Common rules

### A1. Trolley and compartment

| ID | Rule | Value | Source | Model |
|---|---|---|---|---|
| H1 | A compartment holds one size of one fabric batch, at most a set number of garments. A garment is one complete set: front, back and two sleeve panels. | 150 | Rulebook H1 | yes |
| H2 | Example: a marker with S/2 spread over 150 layers makes 300 S garments, so 2 compartments. | — | Rulebook H2 | yes |
| H3 | A trolley holds a set number of compartments, all of one film size (Net_Rate). One trolley serves one print-frame setup. | 5 | Rulebook H3 | yes |
| H4 | **Proposed:** different fabric batches may share a trolley, each batch in its own compartments. This is not what the system does today (O2). | — | Rulebook H4 | yes, as Change 2 (S2, S3) |
| H5 | Each garment size is printed on a fixed frame size (film size, Net_Rate). | 90: XXS, XS, S · 100: M, L · 110: XL, XXL, 3XL, 4XL | Rulebook H5 | partly: the normal ratio is used for every style, not the style's own Net_Rate (E8) |
| H10 | Net_Rate is the print-frame size (90%, 100%, 110%) used to print a size. It is not a panel count or a fabric ratio. Sizes on different frames must be kept apart, so a trolley carries one Net_Rate. | — | Rulebook H10 | yes |
| H11 | One marker mixes sizes across several Net_Rate groups, so one table alone may need several trolleys (XS/3,S/2,M/2,L/2,XL/2 needs at least 3). | — | Rulebook H11 | yes |
| H12 | Marker ratios vary: one MO can have 10–20 tables with 5–6 different ratios. Never assume one ratio per MO. | — | Rulebook H12 | yes: each table's own ratio is used |
| H6 | Trolley utilization = compartments used ÷ 5. A compartment counts as used even if it holds 10 garments. | — | Rulebook H6 | yes (KPI1) |
| H13 | Trolley capacity utilization = garments in each compartment ÷ 150, over the trolley's compartments. | 150 | Rulebook H13 | partly: reported as compartment fill over opened compartments (KPI2); over all 5 compartments it equals KPI1 × KPI2 |
| H8 | Two tables may share trolleys only if together they need no more than a set number of trolleys, counted by Net_Rate. | 4 | Rulebook H8 | yes |
| H9 | Today, combining is for the same MO **and** the same fabric batch only. Never across MOs. | — | Rulebook H9 | yes in S0 and S1; Change 2 relaxes the batch part |
| I1 | Type B is the main body task. It makes the panels that go on trolleys. | — | Rulebook I1 | yes |
| I2 | Type C is the trim task. It makes no garment panels and uses no compartments. | — | Rulebook I2 | yes |
| L2 | Because a compartment holds one batch, CPI works compartment by compartment and never faces two batches at once. Recut does not change. | — | Rulebook L2 | yes (H1) |
| L3 | The system holds and shows information per compartment, not per trolley. | — | Rulebook L3 | no: a system requirement (Change 2 depends on it, C2.5) |
| L6 | Normally only one component is printed. When front and back are both printed they share a Net_Rate, so they travel together. | — | Rulebook L6 | partly: component is not in the model's data; every table is treated as one component |

### A2. When two tables may share a trolley

**Today's combine rule** (Rulebook O1–O3): the automation already exists and works.

| ID | Rule | Model |
|---|---|---|
| O1 | The combine automation for cutting and loading already exists and works; nothing new has to be built there. | context |
| O2 | Today it fires only when the two tables are spread back-to-back on the same spreader **and** use the same fabric batch. | yes (S0) |
| O3 | Keep the back-to-back condition: the trolley must still be standing at that workstation. | yes |

**Combine:** the trolleys of a later table wait for an earlier table only if every condition holds
(Panel Loading 1a).

| ID | Condition | Change 1–3 (Part C) | Model |
|---|---|---|---|
| 1a-1 | The tables are spread continuously at one workstation. | kept | yes: only back-to-back tables on one spreader combine |
| 1a-2 | Same MO. | kept | yes |
| 1a-3 | Same batch. | **relaxed** by Change 2 | yes |
| 1a-4 | Same component. | kept | no: component is not in the data (L6) |
| 1a-5 | Same film code. | kept | partly: film is kept apart per trolley (H3), not checked per pair |
| 1a-6 | The trolleys still have empty compartments. | kept | yes |
| 1a-7 | The current table needs no more than 4 trolleys (H8). | kept | yes |
| 1a-8 | The trolleys still have empty compartments (repeats 1a-6). | kept | yes |
| 1a-9 | A trolley may wait only if both tables are spread and cut at one workstation without the cutter leaving it. | **removed** by Change 3 | yes: in S0–S2 trolleys never wait |

**Come back:** a trolley returns from CCT WIP for a later table only if every condition holds
(Panel Loading 1b).

| ID | Condition | Change 1–3 (Part C) | Model |
|---|---|---|---|
| 1b-1 | Same MO. | kept | yes |
| 1b-2 | Same batch. | **relaxed** by Change 2 | yes |
| 1b-3 | Same colour. | kept | yes |
| 1b-4 | Same component. | kept | no: component is not in the data |
| 1b-5 | Same film code. | kept | yes |
| 1b-6 | The trolley still has empty compartments. | kept | yes |

### A3. Which tables are modelled

| ID | Rule | Value | Source | Model |
|---|---|---|---|---|
| J1 | Use the HaveCut sheet as the main data: it has layers, marker length, marker ratio, batch, MO and colour together. | — | Rulebook J1 | yes |
| A.6 | Spreading types: B = main body; C = trim; T, T1, P = main fabric of a special type (few); L = no need to care. | — | Rulebook A.6 | partly: only B is modelled (J2); T, T1 and P are left out although they are real spreading work |
| J2 | Rows marked First Table = Y are first-batch tables, not real spreading tasks: skip them. | — | Rulebook J2 | yes |
| J3 | Use only universal sizes (XXS to 4XL); ignore number and kids sizes. | — | Rulebook J3 | partly: those tables still take machine time; they load no compartments |
| J4 | Cut Qty = (sum of the Marker Ratio) × layers. Use it to check that the ratio is read correctly. | — | Rulebook J4 | yes (KPI6; checked by `npm run lab`) |
| J5 | Type C rows are placeholders (layers 1, length 1, ratio = order quantity). Never use them for timing; use G3. | — | Rulebook J5 | yes |
| I3 | A C task with the same Table No as a B task is spread first, immediately before the B task, on the same spreader. | — | Rulebook I3, C.b | partly: the C time is added to the B table's spreading (G3), not drawn as a task of its own |
| G3 | A C (trim) task takes a set time to spread. | about 10 min, **ESTIMATE** | Rulebook G3 | partly: 8–10 min per table, from a fixed hash (E7); one setup per B table with any C row |

### A4. Machine time

| ID | Rule | Value | Source | Model |
|---|---|---|---|---|
| G1 | Base speed: 150 layers on an 8.5 yd marker take 2 hours to spread and 1 hour to cut. | 2 h / 1 h | Rulebook G1, A.4 | yes (sets G2) |
| G2 | Time grows linearly with layers and marker length: spreading = layers × 0.80 × (marker length ÷ 8.5); cutting = layers × 0.40 × (marker length ÷ 8.5). | 0.80/8.5 and 0.40/8.5 min per layer per yard | Rulebook G2 | yes |
| T1 | Machines run at the G2 standard pace. There is no speed factor. | — | user, 2026-11-09 | yes |
| G4 | Cutting is the bottleneck, not loading: cutting time follows layers and marker length, and one cutter is shared by 2–3 spreaders. | — | Rulebook G4 | partly: the model computes cutter time but does not assume the bottleneck; on the live floor tables waiting to become ready matter more ([docs/IDLE_TIME.md](docs/IDLE_TIME.md)) |
| G5 | Loading panels onto trolleys does not cause spreading idle time. Trolley changes will not improve idle time. | — | Rulebook G5 | yes (SIM6) |
| G6 | A spreader stops when its table is full. The table holds at most 2 lays of 8.5 yd waiting (maybe 3 if shorter); the cutter pulls the lay in as it cuts. | 21 m | Rulebook G6 | partly: the model uses the measured 21.2 m (B3) and each lay's own length, freed gradually as it is cut |
| T2 | A break stops the machines. A task cut off by a break resumes after it. | — | assumption, **unconfirmed** | yes |
| T3 | A cutter loses changeover time when the next table's MO or colour differs from its last cut. | 5 min, **ESTIMATE** | user, 2026-11-09 | yes |
| T4 | A cutter moves between the spreaders it serves and loses time when the next table is on a different spreader. | 1.5 min, **ESTIMATE** | Rulebook C.c, F2; user, 2026-11-09 | yes |
| T5 | The spreading table stays occupied while the cutter changes over and moves. | — | this model ([SIM_SPEC.md](SIM_SPEC.md) Q19) | yes |
| T6 | Spreaders lose no changeover or moving time beyond the Type C setup (G3). | — | user, 2026-11-09 | yes |
| T7 | A cutter always moves between the spreaders it serves. It does not stay at one spreader to cut both tables of a pair. | — | user, 2026-11-09 | yes |

### A5. When a table may start

A table is **ready** at the latest of R1, R2 and R3.

| ID | Rule | Value | Source | Model |
|---|---|---|---|---|
| R1 | A table may start no earlier than the start of its plan date. | 07:15 | user, 2026-11-10 | yes |
| R2 | A table may start no earlier than its Marker Date (when its marker is ready). | from the data | user, 2026-11-10 | yes |
| R3 | Fabric must relax before it is spread, so a table may start only once its batch's fabric has relaxed. | 24 h (measured 22–24 h) | Rulebook K1 | yes |
| R4 | Each batch's fabric arrives a fixed time before the batch's first plan date. The data read has no arrival time. | 12–48 h before, **ESTIMATE** | user, 2026-11-10 | yes |
| R5 | There is no cold start: work a machine did not finish carries into the next shift, and every plan date is planned around what the machines still have. | — | user, 2026-11-06 | yes |
| B.2 | Relaxing data (RelaxingInfo: per SO, batch and roll, release hours 24, relaxing start and end) is to be simulated together with spreading and cutting. | — | Rulebook B.2 | partly: no relaxing data is read; R4 stands in for it. The sample file exists (open decision, [SIM_SPEC.md](SIM_SPEC.md) §15) |
| J6 | To join fabric and relaxing data: So_No = the first 9 characters of MO. | 9 | Rulebook J6 | no: no relaxing data is read yet |
| C.a | A relaxing trolley holds at most 6 fabric rolls, of at most 2 colours. | 6 rolls | Rulebook C.a | no (Q.1) |
| C.b | Each spreader has 2 positions for relaxing trolleys. The operator spreads from position 1; when it is empty, the trolley in position 2 moves up. | 2 | Rulebook C.b | no (Q.1) |
| Q.1 | Model the relaxing trolleys and feed positions too: a batch that is only partly relaxed holds its tables back. | — | Rulebook Q.1 | no: open decision ([SIM_SPEC.md](SIM_SPEC.md) §15) |

### A6. The live floor

| ID | Rule | Value | Source | Model |
|---|---|---|---|---|
| LF1 | The Job Sequence re-plans at a fixed interval, around the clock, in every shift. | every 30 min | user, 2026-11-10 | yes |
| LF2 | Each re-plan takes every ready table not yet started, oldest plan date first, until the spreaders' capacity for the next window is full. | 24 h | user, 2026-11-10 | yes |
| LF3 | Once the first table of a pair starts, its partner stays next on that spreader and is not re-planned. | — | rule (a), user, 2026-11-10 | yes |
| LF4 | A free cutter takes the waiting lay that has waited longest, among the spreaders it serves. | **ESTIMATE** (stands in for the operator's own choice) | user, 2026-11-10 | yes |

### A7. S0: today's Job Sequence

| ID | Rule | Value | Source | Model |
|---|---|---|---|---|
| A.5 | The Job Sequence arranges all spreading tasks to keep the spreaders from waiting, which keeps the cutters from waiting. | — | Rulebook A.5, D.a | yes |
| JS1 | Every table first gets a cutter: one that already has a table of the same MO and batch that day, otherwise the one with the lowest load per spreader it serves. | — | SQL | yes |
| JS2 | Then, again and again, the spreader with the fewest committed spreading minutes takes, among the tables for its cutter, the one with the shortest spreading time. | — | SQL | yes |
| JS3 | Tables are taken in order of order type: SQR first, then QR, then Normal (anything else counts as Normal). | **ESTIMATE**: the live priority table was not supplied | SQL (commented-out older rule) | yes |
| JS4 | Ties go by plan order for tables and by spreader number for spreaders. | — | this model (the SQL leaves ties open) | yes |

### A8. What is measured

| ID | Measure | Definition | Source | Model |
|---|---|---|---|---|
| KPI1 | Trolley utilization | compartments opened ÷ (5 × trolleys), pooled over all plan dates | Rulebook H6, E.3 | yes |
| KPI2 | Compartment fill | garments ÷ (150 × compartments opened): how full the opened compartments are | Rulebook H13 | yes |
| KPI3 | Trolleys a day | trolleys sent ÷ plan dates | this project | yes |
| KPI4 | Fleet needed | trolleys a day × round-trip days | this project | yes |
| KPI5 | Longest round trip the fleet covers | trolleys owned ÷ trolleys a day | this project | yes |
| KPI6 | Pieces cut a day | every piece the cutters finish inside the plan period ÷ plan dates (all sizes, = Cut Qty, J4) | this project | yes |
| M2 | Report idle time (spreading and cutting separately), the Job Sequence across all machines, and trolley utilization (H6). | — | Rulebook M2, E.1, E.2 | yes: on the website |

### A9. Rules outside the trolley model

Rules about the process around Central Cutting, the data and the simulation request.

| ID | Rule | Value | Source | Model |
|---|---|---|---|---|
| A.3 | Table No and Batch No are set by PPC. | — | Rulebook A.3 | yes: taken from the data |
| B.1 | The planning data (PlanPPC) has a NotCut sheet (still to cut) and a HaveCut sheet (already cut, the one to use). | — | Rulebook B.1 | yes: HaveCut (J1) |
| B.3 | The printing data (PrintingInfo) gives Size_NO and Net_Rate (film size) per size. | — | Rulebook B.3 | partly: the normal ratio H5 is used, not PrintingInfo (the sample file exists) |
| C.c | Size numbering: pieces are numbered from the smallest size to the largest (S/2,M/3 → S001, S002, M003, M004, M005). | — | Rulebook C.c | no: the model counts pieces, not labels |
| C.4 | Two batches may be spread as one only if their shrinkage differs by no more than 0.5 and their shade lot is the same. | 0.5 | Rulebook C.4 | no: shrinkage and shade lot data were not provided (K2) |
| K2 | Shrinkage and shade lot data have not been provided, so batch merging at spreading (C.4) cannot be tested yet. | — | Rulebook K2 | no |
| I4 | Merge_Cut_Remark is a PPC instruction to spread the leftover fabric of two batches as one spread. It is not a trolley-combining mechanism. | — | Rulebook I4 | no: little effect on trolleys |
| L1 | A share of each batch's yardage is kept at spreading as a recut reserve, for that batch only. | 1–2% | Rulebook L1 | no |
| L4 | For printing, the trolley follows the work: panels move on a small table to the printing machine, and the trolley meets them at the exit to reload. | — | Rulebook L4 | no |
| L5 | Panel tags may not survive printing or heat transfer, so identity travels with the container, not the panel. | — | Rulebook L5 | no |
| J7 | Machine_No is corrupted in Excel exports (7-24 becomes a date): export as CSV or text. SPD01 = 24-01, SPD02 = 24-02, and so on. | — | Rulebook J7 | yes: spreaders are named 24-01 … 24-13 |
| E.1 | Calculate the idle time if tasks of different batches may combine at loading. | — | Rulebook E.1 | yes: S2 against S1 (idle time is a separate finding, G5) |
| E.2 | Simulate how the Job Sequence arranges the tasks on the 13 spreaders and 5 cutters. | — | Rulebook E.2 | yes: the Job Sequence chart |
| E.3 | Simulate the gain in trolley utilization, counted by compartments used per trolley. | — | Rulebook E.3 | yes (KPI1) |
| M1 | Simulate at least a set Cut Qty a day; below it the floor is not loaded enough to show its real behaviour. | 90,000 pieces | Rulebook M1 | partly: the real April–June plan has 80,833 a day; the 100k plan (B7) covers the load |
| M3 | Show results in a convincing format, not just a spreadsheet of numbers. | — | Rulebook M3 | yes: the website |
| M4 | Always say which numbers are measured from real data and which are assumptions. | — | Rulebook M4 | yes (SIM2, part D) |

---

## B. This factory's floor facts (Central Cutting)

Another factory replaces this part with its own.

| ID | Fact | Value | Source | Model |
|---|---|---|---|---|
| F1 | Spreading and cutting machines on the floor. | 13 spreaders SPD01–SPD13 (= 24-01 … 24-13), 5 cutters CUT01–CUT05 (= 24MC1 … 24MC5) | Rulebook F1, A.1, A.2 | yes |
| F2 | Each cutter serves only its own group of spreaders and travels between them. | CUT01 → SPD01, 02, 03 · CUT02 → SPD04, 05 · CUT03 → SPD06, 07 · CUT04 → SPD08, 09, 10 · CUT05 → SPD11, 12, 13 | Rulebook F2, C.c | yes |
| F8 | Some spreaders may call a second cutter. | CUT02 may also cut for SPD03; CUT03 for SPD05; CUT01 for SPD04, rarely | Rulebook F8 | partly: SPD03 → CUT01 or CUT02 and SPD05 → CUT02 or CUT03, the cutter free first; CUT01 for SPD04 is not modelled |
| F3 | Two shifts. | day 07:15–20:00; night 18:00–05:00 | Rulebook F3 | yes |
| F4 | Each shift gives a set number of productive hours; the rest is breaks. | 11 h | Rulebook F4 | partly: the model computes 675 staffed min (11.25 h) for the day shift from the break times (B1) |
| F5 | Only these machines work the night shift. | SPD01–03 and CUT01 | Rulebook F5 | yes |
| F6 | 18:00–20:00 is a crew handover, not a drop in capacity: all 13 spreaders run until 20:00, then only the 3 night machines. | — | Rulebook F6 | yes |
| F7 | Staffed time a day of the night machines and of the others. | about 20 h / 11 h | Rulebook F7 | partly: 1,155 and 675 staffed min (19.25 h / 11.25 h), computed from the shift and break times |
| B1 | Day shift breaks. | 11:45–12:45 and 17:15–17:45; 675 staffed min | measured, user, 2026-08-26 | yes |
| B2 | Night shift breaks. A night machine runs on from the day shift. | 22:00–22:30 and 02:00–02:30; 1,155 staffed min a day | user, 2026-11-09 | yes |
| B3 | Spreading table length, the same on all 13 spreaders. | 21.2 m (23.18 yd) | measured, user, 2026-08-26 (Rulebook G6: 21 m) | yes |
| H7 | Trolleys waiting at the cutting end of each spreader. | 4 | Rulebook H7, C.c | partly: the model uses 13 × 4 = 52 waiting positions for the whole floor (C3.6) |
| B4 | Trolleys owned. | 1,200 | fact | yes |
| B5 | Round-trip allowance for a trolley (1 + 3 + 1 days). | 5 days | allowance | yes |
| B6 | Round trip actually assumed for the fleet figures. | 7 days, **ESTIMATE, never timed** | — | yes |
| B7 | Pieces Central Cutting must cut a day. | 100,000 | user, 2026-11-06 | yes: the 100k plan |

---

## C. The three proposed changes (S1–S3)

Each change adds one rule to the floor of S0. Nothing else differs between S0 and S1–S3 (SIM5). Rulebook
D.b and O4 are the aligned proposal; O5 says Changes 1 and 2 only work together.

| Scenario | Same-MO sequencing | Batches per trolley | WIP hold |
|---|---|---|---|
| S0 Today | off (A7) | 1 | none |
| S1 | Same batch only | 1 | none |
| S2 | Cross-batch | 2 | none |
| S3 | Cross-batch | 2 | 60 min, any workstation |

| ID | Rule | Source | Model |
|---|---|---|---|
| O4 | The proposal relaxes only the batch condition: the same MO may combine with different batches in separate compartments (H4). | Rulebook O4, D.b | yes |
| O5 | Neither change works alone: the Job Sequence must put same-MO tables back-to-back, and the batch condition must be relaxed. Fixing only the loading rule leaves almost nothing to act on. | Rulebook O5, P4 | yes (S1 → S2) |

### Change 1: same-MO sequencing (rule (a))

| ID | Rule | Value | Source | Model |
|---|---|---|---|---|
| C1.1 | Tables of the same MO and colour that can share a trolley are paired before they go to a machine: same-batch pairs first, then (Cross-batch only) different-batch pairs. | — | user, 2026-11-09 | yes |
| C1.2 | Both tables of a pair are spread back-to-back on one spreader. A pair is never split. | — | user, 2026-11-09 | yes |
| C1.3 | Work and takt time are counted by pairs. Each pair or lone table goes to the cut group whose busier side (its spreaders or its cutter) stays least loaded, over the whole floor. | — | user, 2026-11-09 | yes |
| C1.4 | Within the cut group, a pair goes to the least-loaded spreader that stays under the fill target. If none does, it goes to any spreader on the floor that does, and if none at all, to the one with the lowest load for its staffed time. | 70% of the staffed window (planning heuristic) | this project | yes |
| C1.5 | Option, not part of rule (a): keep every pair of one MO and colour on one cut group. | off | user, 2026-11-09 | yes, as an option |

### Change 2: two batches per trolley

| ID | Rule | Value | Source | Model |
|---|---|---|---|---|
| C2.1 | A trolley may carry 2 batches of the same MO and colour in separate compartments, never 3. | 2 | Rulebook H4, O4; floor rule | yes |
| C2.2 | Two batches may share a trolley only with Cross-batch sequencing. | — | user, 2026-11-14 | yes |
| C2.3 | With 1 batch per trolley, a trolley never takes a second batch, also not when a waiting trolley is topped up. | — | user, 2026-11-14 | yes |
| C2.4 | Tables of the same batch merge same-size pieces into one compartment, up to 150. Tables of different batches keep their own compartments. | 150 | Panel Loading rule 2 | yes |
| C2.5 | The operator, CPI and recut must see which batch is in which compartment. | — | Rulebook L3 | no: a system requirement |

The user kept S2 and S3 in the published table as reference scenarios rather than as a rule to adopt
(user, 2026-11-09).

### Change 3: WIP hold and recall

| ID | Rule | Value | Source | Model |
|---|---|---|---|---|
| C3.1 | A trolley that leaves with empty compartments waits in CCT WIP instead of being sent on. | — | this project | yes |
| C3.2 | A waiting trolley is sent on as it is once it has waited the hold time. | 60 min | this project | yes |
| C3.3 | A newly cut table first tops up a waiting trolley of the same MO, colour and film, within the batch limit. Batch is not part of the match. | — | this project | yes |
| C3.4 | A waiting trolley may be recalled to any workstation, or only to the one it left. | any workstation | this project (open question: how a trolley moves between workstations) | yes |
| C3.5 | When several waiting trolleys match, the order is one of three: any match (published), same batch first, same batch only. | any match | user, 2026-11-05 | yes |
| C3.6 | A trolley that cannot park, because all waiting positions are taken, is sent on. | 52 | Rulebook H7 | yes |

### Other what-ifs in the Rules Lab (new rules, never in S0)

| ID | Rule | Value | Source | Model |
|---|---|---|---|---|
| C4.1 | Pull-ahead: a spreader that has finished the released plan may start tables of the next plan dates, if their fabric has relaxed. | 0 (off); 1, 2, 3 or all plan dates | user, 2026-11-05 | yes, as an option |
| C4.2 | Shift: both shifts, day only, or night only. | both | user, 2026-11-05 | yes, as an option |

---

## D. Estimates

These values stand in for measurements nobody has taken yet. Every result that depends on them says so.
The rulebook's own open items (part N) are marked.

| ID | Estimate | Value | What it stands in for |
|---|---|---|---|
| E1 | Trolley round trip (B6) | 7 days | the real dispatch-to-return time. The whole fleet case turns on it |
| E2 | Cutter changeover (T3) | 5 min | the real clean-up and speed change on an MO or colour change |
| E3 | Cutter moving (T4) | 1.5 min | the real travel time between spreaders (Rulebook N: "not costed") |
| E4 | Fabric arrival (R4) | 12–48 h before the batch's first plan date | the real arrival time; relaxing data exists as a sample (B.2) but is not read |
| E5 | Cutter pick (LF4) | the longest-waiting lay first | the operator's own choice |
| E6 | Order-type priority (JS3) | SQR, QR, Normal | the live priority table |
| E7 | Type C setup (G3) | 8–10 min | the real C-task spreading time (Rulebook N: "estimated at 10 min") |
| E8 | Film map (H5) | 90 / 100 / 110 by size | the real Net_Rate of each style. The real mapping puts more sizes on one film, so utilization here is on the low side |
| E9 | Breaks stop the machines (T2) | yes | unconfirmed; about 150 min per machine a day if they don't |
| E10 | Spreader fill target (C1.4) | 70% | a planning heuristic with no written source |
| E11 | Spreading and cutting rates (G2) | from one anchor point (G1) | a time study (Rulebook N: "one anchor point only") |

---

## E. Rules of the simulation itself

| ID | Rule |
|---|---|
| SIM1 | The code wins. If a document disagrees with the code, the document is out of date. |
| SIM2 | Every number lives in `tools/assumptions.js` and cites its rule. An estimate is marked ESTIMATE (Rulebook M4). |
| SIM3 | Results are deterministic: no random numbers; every run on the same data gives the same result. |
| SIM4 | A change that moves a published number is reported with a before/after table. |
| SIM5 | S1–S3 run on exactly the same floor as S0; only the rules differ. Shifts, pace, fabric relaxing, cutter changeover and moving are floor facts in every scenario. |
| SIM6 | Idle time (cutter output) and the trolley shortage are separate findings. A saving in one is never claimed for the other (Rulebook G5). |
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
| Change 2 without Change 1 | +0.6 points: two tables can only share a trolley if they are spread back-to-back (Rulebook P1, O5) |
| Tuning the 70% fill target | 0.60 and 0.85 both scored worse |
| Balancing cut groups by capacity instead of spreader count | fewer overruns but a longer day; work moves onto the night machines |
| Treating the table as fixed slots that empty at cut end | overstated blocking by 63%; the table frees gradually (G6) |
| The cutter staying at one spreader to cut both tables of a pair | user, 2026-11-09: the cutter always moves (T7) |
| A dynamic spreader pick in the Lab | user, 2026-11-10: removed; the live floor is used in every scenario |
| Keeping the same colour close | user, 2026-11-10: tables are arranged in pairs instead |
| Cutter count and table length as page controls | user, 2026-11-16: more cutters change little when the plan cannot keep up; table length is kept in the engine for other factories |

---

## G. Rulebook coverage

Every rule of [`data/RULES.docx`](data/RULES.docx), where it is in this file, and whether the model
applies it.

| Rulebook | Topic | In this file | Model |
|---|---|---|---|
| A.1 | 13 spreading machines | B (F1) | yes |
| A.2 | 5 cutting machines | B (F1) | yes |
| A.3 | Table No and Batch No set by PPC | A9 | yes |
| A.4 | 150 layers: 2 h spreading, 1 h cutting | A4 (G1) | yes |
| A.5 | What the Job Sequence is for | A7 | yes |
| A.6 | Spreading types B, C, T, T1, P, L | A3 | partly |
| B.1 | PlanPPC data (NotCut, HaveCut) | A9 | yes |
| B.2 | RelaxingInfo data, to be simulated | A5 | partly |
| B.3 | PrintingInfo data (Net_Rate) | A9 | partly |
| C.a | Relaxing trolley: 6 rolls, at most 2 colours | A5 | no |
| C.b | 2 feed positions per spreader; C before B; only C joins B; size numbering | A5, A3 (I3), A9 (C.c) | partly |
| C.c | Cut groups; cutter travel; 4 trolleys per spreader; trolley and compartment rules; combine same batch, ≤ 4 trolleys | B (F2, H7), A4 (T4), A1 (H1, H3, H8, H9), A9 | yes |
| C.4 | Batch merging at spreading (shrinkage, shade lot) | A9 | no |
| D.a | Minimise spreading and cutting idle time | A7 (A.5) | yes |
| D.b | Combine two batches of one MO, separate compartments | C (O4) | yes |
| E.1 | Idle time with cross-batch combining | A9 | yes |
| E.2 | Job Sequence on 13 + 5 machines | A9 | yes |
| E.3 | Trolley utilization gain | A9, A8 (KPI1) | yes |
| F1 | Machines on the floor | B | yes |
| F2 | Cut groups | B | yes |
| F3 | Shift times | B | yes |
| F4 | 11 productive hours a shift | B | partly |
| F5 | Night machines | B | yes |
| F6 | 18:00–20:00 handover | B | yes |
| F7 | About 20 h / 11 h staffed | B | partly |
| F8 | Second cutters | B | partly |
| G1 | Base speed | A4 | yes |
| G2 | Linear time formulas | A4 | yes |
| G3 | C task about 10 min | A3 | partly |
| G4 | Cutting is the bottleneck | A4 | partly |
| G5 | Loading does not cause idle time | A4 | yes |
| G6 | Table full stops spreading | A4 | partly |
| H1 | Compartment: one size, one batch, 150 | A1 | yes |
| H2 | Compartment example | A1 | yes |
| H3 | Trolley: 5 compartments, one film | A1 | yes |
| H4 | Proposed: batches share a trolley | A1, C (C2.1) | yes |
| H5 | Film size by garment size | A1 | partly |
| H6 | Utilization = compartments used ÷ 5 | A1, A8 (KPI1) | yes |
| H7 | 4 trolleys at each spreader | B | partly |
| H8 | Combine needs ≤ 4 trolleys | A1 | yes |
| H9 | Today: same MO and batch | A1 | yes |
| H10 | What Net_Rate is | A1 | yes |
| H11 | One marker splits across films | A1 | yes |
| H12 | Ratios vary within an MO | A1 | yes |
| H13 | Trolley capacity utilization | A1, A8 (KPI2) | partly |
| I1 | Type B | A1 | yes |
| I2 | Type C | A1 | yes |
| I3 | C spread right before its B | A3 | partly |
| I4 | Merge_Cut_Remark | A9 | no |
| J1 | Use HaveCut | A3 | yes |
| J2 | Skip First Table = Y | A3 | yes |
| J3 | Universal sizes only | A3 | partly |
| J4 | Cut Qty check | A3 | yes |
| J5 | C rows are placeholders | A3 | yes |
| J6 | So_No = first 9 characters of MO | A5 | no |
| J7 | Machine_No export; SPD01 = 24-01 | A9 | yes |
| K1 | 24 h relaxing (measured 22–24 h) | A5 (R3) | yes |
| K2 | No shrinkage or shade lot data | A9 | no |
| L1 | Recut reserve 1–2% | A9 | no |
| L2 | CPI per compartment | A1 | yes |
| L3 | Information per compartment | A1, C (C2.5) | no |
| L4 | Trolley follows the work at printing | A9 | no |
| L5 | Tags may not survive printing | A9 | no |
| L6 | One component; front and back share Net_Rate | A1 | partly |
| M1 | At least 90,000 pieces a day | A9 | partly |
| M2 | Report idle time, Job Sequence, utilization | A8 | yes |
| M3 | Convincing format | A9 | yes |
| M4 | Say what is measured and what is assumed | A9, E (SIM2) | yes |
| N | Open items: C task time, time study, shrinkage and shade lot, cutter travel, Machine_No export | D (E3, E7, E11), A9 (K2, J7) | — |
| O1 | Combine automation exists | A2 | context |
| O2 | Today: back-to-back and same batch | A2 | yes |
| O3 | Keep back-to-back | A2 | yes |
| O4 | Relax only the batch condition | C | yes |
| O5 | Both changes needed together | C | yes |
| P1 | Finding (July 2026): loading rule alone +0.6 points | finding, not a rule ([HISTORY](docs/HISTORY.md)) | — |
| P2 | Finding: both changes +8.4 points, combines 37 → 370 | finding, not a rule | — |
| P3 | Finding: idle time barely moves | finding, not a rule (G5) | — |
| P4 | Request and approve both changes as one item | C (O5) | — |
| Q.1 | Model relaxing trolleys and partly relaxed batches | A5 | no |
