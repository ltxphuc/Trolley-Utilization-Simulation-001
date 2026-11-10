# CCT rule set: current logic vs rules to change

Compiled 2026-11-09 from everything you have told me: this session, `RULES.md` (from
`RULES.docx` and the Job Sequence flowchart) and `CLAUDE.md`. Where an older document and what
you said later disagree, **what you said later wins**, and the conflict is listed in Part C.

Three parts, kept apart on purpose:

- **Part 0, Common ground.** The floor, the trolley and how results are judged. These are facts
  or standards, not rules being compared. They are identical in every scenario, and no rule
  changes them.
- **Part A, Current logic (S0).** How the floor runs today.
- **Part B, Rules to change.** What you want to be different from Part A, one rule at a time.

Source tags:
- **[You]**: you said it, with the date.
- **[Hx] / [Fx] / [Gx] / [Jx] / [L6]**: rule codes from `RULES.docx` and the flowchart.
- **[Measured]**: taken from the real floor or the data.
- **[ESTIMATE]**: a guess standing in for a measurement nobody has taken.

---

## Part 0: Common ground (the same in S0 and in every changed scenario)

### 0.1 Machines and shifts

| # | Fact | Source |
|---|---|---|
| 0.1.1 | **13 spreading machines and 5 cutting machines in five cut groups:**<br>24MC1 = 24-01/02/03<br>24MC2 = 24-04/05<br>24MC3 = 24-06/07<br>24MC4 = 24-08/09/10<br>24MC5 = 24-11/12/13<br>A cutter cuts only the spreaders in its own group. | [F2] |
| 0.1.2 | **Flexible cut:** 24-03 may also call 24MC2, and 24-05 may also call 24MC3, when their own cutter is busy. | [F8] |
| 0.1.3 | **Day shift** runs 07:15–20:00, with breaks at 11:45–12:45 and 17:15–17:45. A day-only machine is staffed for 675 minutes. | [F5–F7], [Measured] |
| 0.1.4 | **Night shift** runs 18:00–05:00, with breaks at 22:00–22:30 and 02:00–02:30. Only 24-01, 24-02, 24-03 and 24MC1 work nights. A night-capable machine is staffed for 1,155 minutes. | [F5–F7] |
| 0.1.5 | **Breaks stop the machines.** A task pauses and then resumes. Nobody has confirmed this on the floor. | [ESTIMATE] |
| 0.1.6 | **No cold start.** Work is always left from the day before. The floor is one continuous timeline over all plan dates, and each date is planned on its own morning around the work already committed. | [You, 2026-11-06 and 11-09] |

### 0.2 Time per table

| # | Fact | Source |
|---|---|---|
| 0.2.1 | **Spreading** takes 0.80 / 8.5 min per layer per yard. **Cutting** takes 0.40 / 8.5 min per layer per yard. | [G2] |
| 0.2.2 | **Machines run at the G2 standard pace.** There is no speed factor. | [You, 2026-11-09: "If it doesn't related to anything, then remove it"] |
| 0.2.3 | **C-table setup:** 8–10 minutes on a B table that has a C row. | [G3/I3/N], [ESTIMATE] |
| 0.2.4 | **The spreading table is 21.2 m.** A spreader blocks when the next lay has no room. Space frees gradually as the cutter cuts, and a new lay needs its full length free. | [G6], [Measured] |
| 0.2.5 | **Cutter changeover: 5 minutes** whenever the next table's MO or colour differs from the cutter's last cut. Cutters only. | [You, 2026-11-09], [ESTIMATE] |
| 0.2.6 | **Cutter moving: 1.5 minutes** whenever the next table is on a different spreader from the last cut. | [You, 2026-11-09], [ESTIMATE] |
| 0.2.7 | **Spreaders have setup too,** but it is not added here. | [You, 2026-11-09: "it's not necessarily need to be added here"] |
| 0.2.9 | **The floor is live (2026-11-10).** The Job Sequence re-plans every 30 minutes around the clock, for the next 24 h; a table starts only when its plan date, Marker Date and fabric (the relaxing ESTIMATE) are ready; a free cutter takes the lay that has waited longest (an ESTIMATE of the operator's free choice). The Lab's Dynamic spreader pick and Keep same colour close are removed. | [You, 2026-11-10], [ESTIMATE] |
| 0.2.8 | **The cutter always moves.** After a cut it goes to whichever spreader in its group has a table ready. It never stays at one spreader to cut two tables in a row, because the other workstations are waiting too. | [You, 2026-11-09] |

### 0.3 Readiness and data

| # | Fact | Source |
|---|---|---|
| 0.3.1 | **Fabric relaxes for 24 h before spreading.** A table is not released until then, so every planned table is already relaxed. | [RULES §5] |
| 0.3.2 | **The pattern or marker** is ready at most 1.5 h after the plan is uploaded, so it is not a constraint. | [RULES §5] |
| 0.3.3 | **Only `Type = B` tables are modelled,** and never a `First Table = Y` row. A C table rides on its B table. | [J2] |
| 0.3.4 | **Kids and number sizes** take machine time but load no compartments. | [J3] |
| 0.3.5 | **The data has no component column,** so one component is assumed per style. | [L6] |
| 0.3.6 | **Missing from the data:** Net_Rate, fabric arrival time and Cut Date. | [Measured: checked] |

### 0.4 The trolley

| # | Fact | Source |
|---|---|---|
| 0.4.1 | **A trolley has 5 compartments of up to 150 garments each,** so 750 at most. | [H1], [H3] |
| 0.4.2 | **A compartment holds one batch of one film size,** and a trolley holds one film size only. | [H4] |
| 0.4.3 | **Film by size:** XXS–S on 90 cm, M–L on 100 cm, XL–4XL on 110 cm. This stands in for the missing Net_Rate. | [H5] |
| 0.4.4 | **Utilization** = compartments opened ÷ 5. **Compartment fill** (garments ÷ 150) is reported separately. | [H6] |
| 0.4.5 | **At most 52 part-filled trolleys can wait at once** (13 workstations × 4 positions). | [H7] |
| 0.4.6 | **A combine may need no more than 4 trolleys.** | [H8] |
| 0.4.7 | **The fleet is 1,200 trolleys.** The round trip is allowed 5 days. The real trip is put at **7 days**, an ESTIMATE that has never been timed. | [ESTIMATE] |

### 0.5 How results are judged

| # | Standard | Source |
|---|---|---|
| 0.5.1 | **Output = pieces cut by the cutting machines,** not by the spreaders. | [You, 2026-11-09: "The final output are those cut by the cutting machine"] |
| 0.5.2 | **The requirement is at least 100,000 pieces a day.** Report whether it is covered and the working hours needed to finish. | [You] |
| 0.5.3 | **Machine time is shown in hours per working day,** not percentages. | [You] |
| 0.5.4 | **Cutter setup, moving and waiting are lost time.** More setup means more idle time, and more setup must never show more output. | [You: "More setup time means more idle time"] |
| 0.5.5 | **S0 is the current situation.** Each rule in Part B is added one at a time on exactly the Part 0 floor, and the result is compared back to S0. Only the rules differ. | [You: "S0 is the current situation…"] |
| 0.5.6 | **Trolley utilization and machine idle time / output are independent findings.** A gain in one is never claimed for the other. | [Project rule] |
| 0.5.7 | **Every number names its run:** plan (real or 100k), scenario and floor settings. | [Project rule] |

---

## Part A: Current logic (S0, the floor today)

### A1. Dispatch: which spreader gets a table

| # | Rule | Source |
|---|---|---|
| A1.1 | **S0 has one aim: maximise the cutting machines' output.** | [You, 2026-11-09] |
| A1.2 | **Superseded 2026-11-10 by the SQL:** "tables are thrown anywhere" is how you described it. The Job Sequence stored procedure (`data/SQL Job Sequence Logic.sql`, `P_Task_Calculate`) is the S0 logic now (A1.5–A1.9). | [You, 2026-11-09], [SQL] |
| A1.3 | **There is no arranging** by MO, colour or batch beyond the cutter preference in A1.6. Same-MO tables seldom end up next to each other. | [You, 2026-11-09], [SQL] |
| A1.4 | **Result:** very low trolley utilization. | [You, 2026-11-09] |
| A1.5 | **Priority** within a plan date: order type SQR, then QR, then Normal (anything else ranks as Normal). The live `Job_Seq_Schedule_Priority` was not supplied. | [SQL L1016-1076], [ESTIMATE] |
| A1.6 | **Pass 1: every table gets a cutter.** A cutter that already holds the same MO + batch this date if there is one, else any cutter; the least loaded of those, where load = spreading minutes ÷ the number of spreaders on it (each weighted 1 ÷ the cutters it maps to). | [SQL L2105-2344] |
| A1.7 | **Pass 2: the least-loaded spreader** (spreading minutes, not divided by its shift) **takes the shortest waiting table** of the tables whose cutter it feeds, or any table if none. | [SQL L3693-, L4151-5258] |
| A1.8 | **Not modelled:** material and roll readiness, pull-later / merged-pull / merged-batch links, PadPrint / small-order / abnormal / first-bed machine flags, rush inserts, table locks, marker width, the 2-lay limit per spreading table (21.2 m is kept), the same-MO same-batch pairing switch (off today). | [You, 2026-11-09: core loop only] |
| A1.9 | **The SQL's "closest to the cutter's gap" rule never runs as written** (it is dead code); the model mirrors the code. | [SQL L3715, L3773-3777] |

### A2. Loading: when tables may share a trolley

**A2.1 Combine.** A later table may load onto a trolley the earlier table opened only if all
nine conditions hold [RULES §6]:
1. The earlier table is spread continuously at one workstation.
2. Same MO [H9].
3. **Same batch.**
4. Same component.
5. Same film code.
6. The trolley has empty compartments.
7. No more than 4 trolleys for the task [H8].
8. The trolley has empty compartments (this repeats condition 6).
9. The trolley may wait only if both tables are spread and cut continuously at one workstation,
   with the cutter never leaving.

**A2.2 Come back.** A trolley may return to CCT WIP and be topped up only if all six hold
[RULES §6]:
1. Same MO.
2. **Same batch.**
3. Same colour.
4. Same component.
5. Same film code.
6. The trolley has empty compartments.

**A2.3 Why trolleys leave part-full.** Condition 9 almost never holds, because the cutter
always moves between spreaders (0.2.8). So a part-filled trolley leaves at once.

**A2.4 One batch per trolley.** Combine condition 3 and come-back condition 2 both require the
same batch.

---

## Part B: Rules to change (each one replaces a named part of Part A)

### B1. Rule (a): pair same-MO tables back-to-back. **Wanted.**

Replaces A1.2–A1.3 (no arranging).

| # | Rule | Source |
|---|---|---|
| B1.1 | **Same-MO tables are paired and spread back-to-back** on one spreader. A pair is never split across two spreaders. | [You, 2026-11-09] |
| B1.2 | **Tasks and takt time are counted by pairs,** not by single tables. | [You: "calculate the tasks and takt time by pairs, not by one tasks anymore"] |
| B1.3 | **The system pairs first, then assigns the pairs anywhere on the floor** to maximise cutter output. The aim of A1.1 is kept. | [You: "it will auto pairs first, then calculate to maximise cutting machine output base on that"] |
| B1.4 | **A pair must still pass A2.1:** same MO, colour, batch, component and film, and no more than 4 trolleys. | [H8], [H9] |
| B1.5 | **The cutter still moves between spreaders** (0.2.8). Pairing gives the cutter no saving in moving or changeover. It is a trolley rule: it creates adjacency for the combine. | [You, 2026-11-09] |

**B1-option. Keep an MO on one cut group.** A separate option, not rule (a). All pairs of one
MO + colour go to one cut group. [You: "Can add another option for this is arranging same MO
as 1 cut group"]

**B1-option. Same colour to one cut group.** An existing option. [You: "There's already an
option for arranging same color to the cut group"]

### B2. Two batches per trolley. **Dropped. Not part of the change.**

[You, 2026-11-09: "I don't want to put 2 batches on the same trolley anymore."]

- A2.1 condition 3 and A2.2 condition 2 (same batch) **stay as in Part A**: one batch per trolley.
- Old "Change 2" in `RULES.md` §8 and the published S2/S3 used two batches, so they no longer
  apply.

### B3. Rules tried in the Lab: new rules, never in S0. **Not chosen.**

| Rule | What it does | Status |
|---|---|---|
| WIP hold (old Change 3) | A part-filled trolley waits in CCT WIP up to 60 min instead of leaving. Removes A2.1 condition 9. | Not decided by you |
| Recall to any workstation | A parked trolley is brought to whichever workstation needs it. How it would move is unknown. | Not decided by you |
| Same-batch / different-batch recall | Recall preference. Different-batch needs B2, which is dropped. | Not chosen |
| Pull-ahead | Starts the next plan dates' tables early, once ready. | Kept as a Lab add-on (user, 2026-11-10) |
| Dynamic dispatch | A free spreader takes any released table live. | **Removed** from the Lab (user, 2026-11-10): the floor is live in every scenario instead (0.2.9) |
| Keep same colour close | Dynamic only; a spreader prefers the colour its cutter just cut. | **Removed** (user: "I never want to keep same color close") |

### B4. Rejected. Do not propose again.

| Rejected | Your words |
|---|---|
| Cold start (every day starts empty) | "There will never be a cold start." |
| Machine speed factor | "If it doesn't related to anything, then remove it." |
| The cutter stays at one spreader to cut both tables of a pair | "The cutting machine always move between spreading machine to cut. There's no way it stay." |
| Two batches per trolley | "I don't want to put 2 batches on the same trolley anymore." |

---

## Part C: Conflicts and open points to settle before the rebuild

1. **S0 was mis-described in the old documents and the model. Resolved 2026-11-10:** S0 is now the
   real Job Sequence (A1.5–A1.9, `sequenceJobSeq`). The old model S0 survives only as
   `today_grouped` for `npm run beforeafter`. `RULES.md` §8 carries a dated note.
2. **Resolved 2026-11-10:** the SQL has no 70% fill target and no spill to other groups, so S0 uses
   neither. S1–S3 keep `MACHINE_FILL_TARGET` in their own dispatcher (`sequencePairs`).
3. **Resolved (your answer, 2026-11-09):** with one batch per trolley, pairs in B1 are same MO +
   colour + batch only.
   - **New point:** S0 → S1 now changes the dispatcher as well as adding pairing. A one-rule S1 (S0 with
     the SQL's own pairing switch `SameBatchMoTogether` on) is possible as a later announced change.
   - **Still open:** the S0 backlog. The model's S0 builds a backlog the real floor does not (44%
     of tables more than a day late against 15%). The material, merge and lock rules, the machine
     staffing and overtime are the candidates; the live priority table is another.
4. **WIP hold and recall (B3).** Keep them, drop them, or test them later? Recall to another
   workstation needs a trolley move that nobody has described.
5. **The estimates still to be timed on the floor:**
   - cutter changeover (5 min);
   - cutter moving (1.5 min);
   - trolley round trip (7 days);
   - whether breaks stop machines;
   - C-table setup (8–10 min).
6. **Night shift start.** Resolved (user, 2026-11-09): 18:00. The code now says 645 (was 630).
