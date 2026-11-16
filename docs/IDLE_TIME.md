# Idle time: why spreading machines stop

**Question:** the Job Sequence chart shows hatched gaps on the spreading machines. What are they, what do
they cost, and what removes them?

Idle time is a **separate finding from the trolley shortage** ([RULES.md](../RULES.md) SIM6). Nothing here
saves trolleys, and no trolley change saves idle time.

**Source of every number below:** `npm run idle` (`tools/idle_variants.js`), on the **full workbook (199
plan dates, January–August 2026, 15,920 tables)**, not only the April–June website scope. It runs S0 (today's
Job Sequence) on the published live floor, with cutter changeover 5 min and moving 1.5 min (ESTIMATES).

## 1. Two kinds of waiting

A spreading machine that is staffed but not spreading is doing one of two things:

| | What it means | Rule |
|---|---|---|
| **Blocked** (hatched) | the table is full: the next lay does not fit until the cutter frees length | G6 |
| **Starved** (shaded) | nothing it is allowed to start: the table's plan date, marker or fabric is not ready yet | R1–R3 |

A spreading table is 21.2 m. A lay takes its marker length on the table; the cutter gives the length back
**gradually** as it cuts, not all at once when the cut ends (G6). An earlier version that treated the table
as slots emptying at cut end overstated blocking by 63%.

## 2. What blocking costs today

| Per day, across the 13 spreading machines | Value |
|---|---|
| Spreading work | 5,273 min |
| Lost to blocking | **222 min** (about 4 machine-hours) |
| Machine-days spreading past their own shift window | 67% |
| Last cut of a plan date's tables finishes (average) | 06:59 the next morning |

On the live floor, blocking is small: most of a spreader's lost time is **starved**, waiting for tables to
become ready (Marker Date, and the fabric-relaxing ESTIMATE), not waiting for table space. The carry-over
floor also lets a plan date's work run on past its own window into the next shift, which is why most
machine-days end past their window.

## 3. Where it falls

| Cut group | Spreaders | Cutter busy | Blocked a day | Spreading a day | Blocked ÷ spreading |
|---|---|---|---|---|---|
| 24MC1 | 3 | 65% (runs nights) | 101 min | 1,872 min | 5% |
| 24MC2 | 2 | 67% | 20 min | 864 min | 2% |
| 24MC3 | 2 | 68% | 25 min | 787 min | 3% |
| 24MC4 | 3 | 67% | 40 min | 953 min | 4% |
| 24MC5 | 3 | 56% | 36 min | 798 min | 4% |

No cutter is saturated: the busiest runs at 68% of its staffed time.

## 4. What changes it

| Change | Blocked a day | Over window | Cost |
|---|---|---|---|
| **Today**: 21.2 m table | 222 min | 67% | — |
| 24-10 and 24-13 may borrow a neighbour's cutter | 238 min | 68% | a routing rule |
| Any cutter may serve any spreader | 264 min | 69% | a routing rule |
| Table to 24 m | 165 min | 67% | floor space |
| Table to 24 m + neighbour routing | 178 min | 67% | both |
| Table to 24 m + any cutter | 210 min | 68% | both |
| Table to 27 m + any cutter | 166 min | 67% | both, more space |

**More cutters** (same S0, 21.2 m table; 24MC1 keeps 24-01/02/03 at every count):

| Cutters | Spreaders per cutter | Blocked a day | Over window | Last cut |
|---|---|---|---|---|
| 5 (today) | 2.60 | 222 min | 67% | 06:59 |
| 6 | 2.17 | 112 min | 65% | 05:40 |
| 7 | 1.86 | 102 min | 64% | 05:35 |
| 8 | 1.63 | 93 min | 64% | 05:45 |

What this shows, and no more:
- A longer table or a sixth cutter halves blocking, but blocking is only about 4 machine-hours a day to
  start with. Neither changes how many machine-days run past their window, because that comes from the
  carry-over of work that was not ready in time.
- Routing changes do not reduce blocking on the live floor (they raise it slightly). The script does not
  isolate why.
- More cutters barely move the trolley numbers (table T-C, `npm run tc`, [SIM_SPEC.md](../SIM_SPEC.md) §12).
- Longer tables are hypothetical: nobody has checked that the floor has room for them.

## 5. What to distrust

- **Cutter changeover and moving** are ESTIMATES (5 and 1.5 min). Neither has been timed.
- **The lay needs its full length free** before it starts, and there is **no end allowance** per lay. The
  first makes blocking look worse than reality, the second better.
- **21.2 m is one length for all 13 tables.** If they differ, the shorter ones carry more of the blocking.
- **Readiness inputs:** the Marker Date is used as the moment the marker is ready, and fabric arrival is an
  ESTIMATE. Both decide how much of the lost time is starved rather than blocked.
- **The model is less late than the real floor** (26% of tables finish after their plan date, against 51%
  in the real Pull Date, `npm run carryprobe`). The real floor loses time to something the model does not
  have, so these idle figures are optimistic.

The earlier idle-time study (cold-start model, 20-date export: 1,997 blocked minutes a day, 24MC4 and 24MC5
at 95%) is superseded. It is kept in the [archived README](archive/README_2026-11-14.md), Part 7.
