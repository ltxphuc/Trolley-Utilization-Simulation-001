# Change spec: three changes to the Job Sequence and Panel Loading

**For:** ISD, to implement in the Auto Planning System.
**Scope:** Central Cutting only: Job Sequence, Cutting and Panel Loading.
**Status:** simulated on real HaveCut data (April–June 2026, 79 plan dates); not yet piloted.

The rules quoted here are defined in [RULES.md](../RULES.md) (IDs in brackets). The numbers come from the
published model (`out/results.json`, `out/sweep.json`; [SIM_SPEC.md](../SIM_SPEC.md) §14). Fleet figures
use the 7-day round trip, an **ESTIMATE** that has never been timed. Cutter changeover 5 min and moving
1.5 min are ESTIMATES too.

## Summary

Build the three changes in this order. Each depends on the one before it.

| # | Change | Where | Utilization | Trolleys a day | Fleet @ 7 days (1,200 owned) |
|---|---|---|---|---|---|
| — | Today (S0) | — | 51.85% | 203.8 | 1,426 (226 short) |
| 1 | Same-MO tables placed back-to-back, in pairs (S1) | Job Sequence | 58.19% | 175.8 | 1,231 (31 short) |
| 2 | A trolley may carry 2 fabric batches (S2) | Panel Loading combine rule | 61.17% | 167.3 | 1,171 (29 spare) |
| 3 | A part-filled trolley waits in CCT WIP and is recalled (S3) | Panel Loading + WIP | 67.45% | 151.7 | 1,062 (138 spare) |

**Change 2 without Change 1 is worth little:** 2 batches on today's Job Sequence gives 52.99% against
51.85% (`today|2|0|1` in the sweep). The combine rule can only act on tables that are spread back-to-back,
and today's Job Sequence rarely puts them there.

These changes raise trolley utilization. They do not change how many pieces the cutters cut (all within
0.5% of S0); that is a separate finding.

## 1. The rules as they are today

From the Job Sequence / Panel Loading Suggest Logic. The full lists are in [RULES.md](../RULES.md) A2.

| Condition | Change |
|---|---|
| Combine 1a-3 and come-back 1b-2: same batch | **relax** (Change 2) |
| Combine 1a-9: a trolley may wait only if both tables are spread and cut at one workstation without the cutter leaving it | **remove** (Change 3) |
| Every other combine and come-back condition | keep |

## 2. Change 1: Job Sequence, same-MO tables in pairs

**Today** (S0, [RULES.md](../RULES.md) A7): every table gets a cutter, then the least-loaded spreader takes
the shortest waiting table. Two tables that could share a trolley rarely end up next to each other on one
spreader, so combine condition 1a-1 is rarely met.

**Build** (C1.1–C1.4, rule (a)):

```
day_units = []
FOR each group of tables sharing (MO, colour):
    sort tables by (batch, longest spread time first)
    # pass 1: pair tables of the same batch
    # pass 2 (Cross-batch only): pair tables of different batches
    a pair = two tables that can share a trolley (same MO, colour; <= 4 trolleys; same batch unless cross-batch)
    every table left over is a unit of its own
    day_units += pairs and lone tables

FOR each unit in day_units, longest total spread time first:
    cut_group = the group whose busier side stays least loaded:
                MAX( (spread load + unit spread) / spreader minutes,
                     (cut load + unit cut) / cutter minutes )
    machine   = the least-loaded spreader of that group under 70% of its staffed window
                (else any spreader on the floor that is, else the lowest load for its staffed time)
    machine.queue.APPEND(both tables of the unit, one after the other)   # back-to-back: the point
```

**The one thing that must not be lost:** both tables of a pair go into the same spreader's queue, one
after the other (C1.2). If a later balancing or re-planning step splits a pair, Change 1 is undone and
Changes 2 and 3 lose most of their value. On a floor that re-plans every 30 minutes, the partner of a pair
whose first table has started must stay next on that spreader (LF3).

Readiness does not change: a table still waits for its plan date, its marker and its relaxed fabric (A5).
Change 1 only reorders tables that are ready.

## 3. Change 2: Panel Loading, two batches per trolley

**Build:** drop combine condition 1a-3 and come-back condition 1b-2 (same batch), and add one limit:

```
MAX_BATCHES_PER_TROLLEY = 2      # never 3 (C2.1)
```

- Two batches may share a trolley only when the Job Sequence pairs across batches (Cross-batch, C2.2).
- With a limit of 1, a trolley never takes a second batch, also not when a waiting trolley is topped up
  (C2.3).
- Compartments do not change: one batch and one size per compartment, one film size per trolley (H4).
- Same batch: same-size pieces merge into one compartment up to 150. Different batches: each table keeps
  its own compartments (C2.4).

```
FUNCTION can_share_trolley(a, b, cross_batch):
    IF a or b has a size outside the film map: RETURN FALSE      # J3
    IF a.mo        != b.mo:        RETURN FALSE                  # 1a-2
    IF a.colour    != b.colour:    RETURN FALSE
    IF a.component != b.component: RETURN FALSE                  # 1a-4
    IF a.film      != b.film:      RETURN FALSE                  # 1a-5
    IF a.batch != b.batch AND NOT cross_batch: RETURN FALSE      # 1a-3, relaxed here
    IF trolleys_needed(a + b) > 4: RETURN FALSE                  # 1a-7, H8
    RETURN TRUE
```

**Display requirement:** the operator, CPI and recut must see which batch is in which compartment (L3,
C2.5). If the system can only show batch per trolley, Change 2 cannot ship.

## 4. Change 3: WIP hold and recall

**Today:** condition 1a-9 lets a trolley wait only if the cutter never leaves the workstation. The cutter
moves between 2 or 3 spreaders all the time, so a part-filled trolley almost always leaves at once.

**Build:** remove condition 1a-9 and replace it with a hold-and-recall cycle (C3.1–C3.6):

```
STATE: waiting_trolleys: trolleys with free compartments, parked in CCT WIP,
       matched on (MO, colour, component, film size). Batch is not part of the match.

WHEN a table finishes cutting:
    1. send on every waiting trolley that has waited longer than WIP_HOLD_MINUTES
    2. FOR each waiting trolley that matches the table:
           skip it if it would carry more batches than allowed
           recall it to this workstation, load what fits, send it on if full
    3. WHILE compartments are left:
           open a new trolley, load up to 5 compartments
           IF it leaves with free compartments AND WIP_HOLD_MINUTES > 0:
               park it if fewer than 52 trolleys are waiting (H7), else send it on
```

| Parameter | Value | Note |
|---|---|---|
| `WIP_HOLD_MINUTES` | 60 | 2 h is worth more (70.47% against 67.45%) but ties trolleys up longer. Start at 60. |
| `TROLLEY_BAYS` | 52 | 13 workstations × 4 positions (H7). |
| `MAX_BATCHES_PER_TROLLEY` | 2 | from Change 2 |
| Match | MO + colour + component + film size | batch deliberately left out |

**The open question ISD cannot answer alone.** The recall sends a waiting trolley to whichever
workstation next cuts a matching table, not only the one it came from. That is almost all of the value:

| Recall (with 2 batches per trolley) | Utilization | Trolleys a day |
|---|---|---|
| No hold | 61.17% | 167.3 |
| 1 h, same workstation only | 61.42% | 166.6 |
| 1 h, any workstation | **67.45%** | **151.7** |
| 2 h, same workstation only | 61.55% | 166.3 |
| 2 h, any workstation | 70.47% | 145.2 |

**Before this is built, Production has to answer: how does a waiting trolley get from CCT WIP to a
different workstation?** By labour, AGV or manual push, and at what cost? If moving it is slow or
expensive, Change 3 is worth about the same-workstation figure, +0.25 points.

## 5. Data the model reads

From the `HaveCut` sheet of PlanPPC. The full list is in [SIM_SPEC.md](../SIM_SPEC.md) §1.

| Field | Used for |
|---|---|
| `Plan Date` | groups tables into plan dates; earliest start (R1) |
| `Type`, `First Table` | only Type B, First Table ≠ Y (J2); Type C adds setup to its B table (G3) |
| `Table No` | joins C rows to their B table |
| `MO`, `Color` | pairing, combine and recall |
| `Batch No` | the batch rule (relaxed by Change 2) and fabric relaxing per batch |
| `Marker Ratio`, `Act LayerQty` | pieces per size → compartments; spreading and cutting time (G2) |
| `Marker Length` | spreading and cutting time; table length used (G6) |
| `Marker Date` | earliest start (R2) |
| `订单类型` (order type) | today's Job Sequence priority (JS3) |

The real system must read two things the export does not carry: **component** (combine 1a-4, come-back
1b-4) and the real **Net_Rate** (the model uses the H5 film map instead).

## 6. What to log once it is live

Four measurements would replace estimates with facts:

1. **Trolley round trip**: dispatch from Panel Loading to return. The fleet case turns on it (E1).
2. **Compartments loaded per trolley and garments per compartment** at dispatch, measured together:
   utilization alone cannot tell a part-opened trolley from a fully opened but part-full one (H6, M2).
3. **How often a recall is possible but the trolley cannot be moved**: the cost of the open question in §4.
4. **Combines fired per day**, before and after Change 1.

Also worth timing: cutter changeover and moving (E2, E3) and when fabric really arrives (E4).

## 7. Reproducing the numbers

`npm run build` rebuilds every number from the workbook in `data/`; the gates are listed in the
[README](../README.md#for-developers).
