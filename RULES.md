# RULES.md

## What this document is

This is the complete rulebook behind the CCT Trolley Model, written as one
continuous narrative rather than a scattered set of code comments. Every rule
the simulation obeys — where it comes from, what it means physically on the
floor, why it was written the way it was, what happens when it's relaxed, and
what is still just an estimate standing in for a measurement — is collected
here, in the order you'd actually need to understand them: what a trolley and
a compartment are, how tables move through the day, how they're allowed to
share a trolley, what's been tried and rejected, and what's still missing.

It exists for one reason beyond documentation: **the model in this repo is a
simplification, and if the next step is a higher-fidelity simulation, this is
the map of exactly where the simplifications are.** Every rule below either
comes straight from `RULES.docx` / the Job Sequence flowchart (cited by a
letter-number code like H6 or G6), or was established directly by you across
the sessions that built this model — a measurement, a decision, a correction
to something the model got wrong. Both kinds are rules in the sense that
matters here: the simulation's output depends on them, and a higher-level
model has to either keep them, replace them with something measured, or
consciously decide to relax them.

**Provenance rule for this document itself:** if anything here disagrees with
`assumptions.py` or `model.py`, the code is right and this file is stale —
`assumptions.py` remains the single place a number is allowed to live, and
this narrative exists to explain what those numbers mean, not to compete with
them as the source of truth. Last extracted from the code and the README on
**2026-09-11** (added: the 5–8 cutting-machine axis in §2, the deterministic
8–10 min C-table setup in §3 and §10, the second J2 exclusion in §4, the
simulated-`cut_end` "Completed" definition in §5, the §12 status note, the
closed-day / cold-start paragraph in §2, and the warm-start starting point
in §12). The cold-start and machine-speed text was updated on **2026-11-09**
(both removed, see §2); the rest of this file still reads as of 2026-09-11.

---

## 1. The trolley and the compartment — the physical unit everything is built on

The whole simulation is arithmetic on one physical object: a trolley with
five compartments, each able to hold up to 150 garments. That's rules **H3**
(five compartments per trolley) and **H1** (150-garment cap per compartment),
and together they set the absolute ceiling — 750 garments — that every
utilization number in this project is measured against.

A compartment is not a bin you can fill with anything convenient. **Rule H4**
says a compartment holds one batch of one film size only, and a trolley holds
one film size only across all five of its compartments — compartments of
different film widths may never share a trolley, full stop, and this has
never been relaxed by any of the proposed changes in this document. Before
Change 2 (below), it was tighter still: a compartment held one batch and
nothing else, meaning two tables from different batches could never load into
the same compartment even if there was room. `compartments_for()` in
`model.py` is where this is enforced — it walks each film size's pieces with
`divmod(qty, 150)`, which is also why compartments are almost never perfectly
full: the last compartment of any size carries only the remainder of that
division, and it is this fact — not a bug — that gives every trolley an
average compartment fill of roughly 75% instead of 100%.

Which film width a garment size is cut on is **rule H5**, the Net_Rate
mapping: sizes XXS through S are on a 90 cm film, M and L on 100 cm, XL
through 4XL on 110 cm. This project does not have the real Net_Rate column —
it was searched for across all 66 `HaveCut` headers and 13,136 shared
strings and confirmed absent — so H5 is a substitute. It matters that this
substitute is conservative in one specific direction: the real Net_Rate
scheme, whatever it is per style, tends to put *more* sizes onto one film,
which would only improve trolley utilization further. So wherever this model
under-states utilization, it is under-stating it safely, not the other way
around. A scheme switcher was actually built at one point to let a user pick
between mapping variants, and then removed — Net_Rate is universal here, H5
is the whole story, and there was nothing left to switch between.

**Rule H6** is the single rule most responsible for confusion in this
project, and it's worth being precise about it because it was the direct
subject of a defect report. H6 defines trolley utilization as **how many of
the five compartments got opened at all** — not how full each opened
compartment is. A trolley that opens all five compartments but has every one
sitting at 60% fill still reads 100% utilization under H6, because H6 is
counting slots used, not garments carried. This is exactly why a reader who
takes the utilization percentage and multiplies it by the 750-garment ceiling
gets a bigger number than the actual garment count on the trolley: the
percentage answers "how many compartments did we open," not "how full is the
trolley." The two questions have different answers — roughly 75% on the
second, pooled over 20 days — and until this was fixed, the second number
existed inside the per-day calculation (`run_day()`, removed with the cold start on 2026-11-09) and was silently discarded
before it ever reached the published aggregate. The fix (documented in full
in `README.md` Part 8 §3) was to carry that second ratio — **compartment
fill** — through to the published output as its own number, so the two
questions are both answered on the page instead of one masquerading as the
other.

**Rule H7** puts a hard ceiling on how many trolleys can be waiting,
part-filled, at once: 52 bays, which is 13 workstations times 4 positions
each. This cap has never actually been hit in any simulated run, but it is
enforced anyway rather than trusted to stay slack, because a WIP-hold policy
generous enough to fill it would silently start dispatching trolleys early
regardless of the intended hold time — the cap is a backstop, not a tuning
parameter.

**Rule H8** caps how many trolleys a single combine may need at 4 — if
merging two tables would require more than four trolleys between them, the
combine doesn't happen. This cap was tested directly: removing it entirely is
worth +0.7 percentage points of utilization (65.4% → 66.1%), which is real
but small, and it confirms the cap is not where the model's real limitation
lives (see §7 below on what actually is).

**Rule H9** is the requirement that two tables share the same MO (manufacturing
order) before they can combine onto one trolley. It sits alongside same-colour,
same-component and same-film-code requirements as one of the six-to-nine
conditions the current floor logic checks before allowing two tables to
share — the full list of those conditions, and which ones this project's
three proposed changes touch, is §5 below.

---

## 2. The machines, the shifts, and how a day is staffed

Central Cutting runs **13 spreading machines under 5 cutting machines** —
rule **F2** — grouped as `24MC1: 24-01/02/03`, `24MC2: 24-04/05`,
`24MC3: 24-06/07`, `24MC4: 24-08/09/10`, `24MC5: 24-11/12/13`. This grouping
is not cosmetic: it is the reason idle time concentrates where it does (§9
below), because a cutting machine can only serve the spreaders wired to it,
and three of the five groups have three spreaders sharing one cutter while
two have only two.

**The cutting-machine count is a what-if axis, not just the fixed 5.** As of
**2026-09-08** `assumptions.py` carries `CUT_GROUPS_BY_CUTTER_COUNT` for **5,
6, 7 and 8** cutters (`SIM_CUTTER_COUNTS`), and the Simulation tab has a
sidebar control that sweeps them — this is README Part 7 §4 recommendation 4
("a sixth cutting machine, only if volume grows") made explorable. **`24MC1`
keeps `24-01/02/03` at every count**, so `NIGHT_SHIFT_SPREADERS`,
`NIGHT_SHIFT_CUTTERS` and rule F8 (which names `24-03` and `24-05`, both in
groups that exist unchanged at every count) all stay valid *unmodified* — only
the ten day-only spreaders re-partition, and the two saturated groups (24MC4,
24MC5) split first. Measured effect: on today's sequencer a sixth cutter
nearly halves blocked minutes (1,563 → 900 min/day, over-window 16% → 4%) and
does most of what the routing-plus-longer-table pairing does for free;
trolley numbers move ~1 utilization point on S0 and not at all on S1–S3 (idle
ladder in Part 7 §4b, trolley ladder in table T-C, Part 8 §4).

Two exceptions loosen that rigid grouping. **Rule F8** lets two specific
spreading machines — 24-03 and 24-05 — call a *second* cutting machine when
their own group's cutter is busy: 24-03 can also use 24MC2, and 24-05 can
also use 24MC3. This flexible-cut rule is the seed of one of the two fixes
for idle time (§9) — if it were extended to every spreader instead of just
these two, overrun days fall from 25% to 15%.

The **night shift** is rules **F5 through F7**: only 24-01, 24-02, 24-03 and
their cutter 24MC1 run at night, from 18:00 to 05:00; everything else is
day-shift only, 07:15 to 20:00. The day and night windows overlap from 18:00
to 20:00, and that overlap adds no extra capacity — it is the same physical
machine running on into its night hours, not two separate machines. Net of
breaks (11:45–12:45 and 17:15–17:45 for the day shift; 22:00–22:30 and
02:00–02:30 for the night shift, both of which stop the machines under
`BREAKS_STOP_MACHINES = True`), a day-only machine is staffed for **675
minutes** and a night-capable machine for **1,155**. These two figures
replaced a pair of wrong constants — 660 and 1,200 — that an earlier version
of this model carried; getting the shift arithmetic right was itself a
correction made mid-project, not an assumption that was always this way.

A task that is mid-spread or mid-cut when a break starts pauses and resumes
afterward rather than being charged for time it wasn't actually running.
Whether breaks should stop the machines at all is flagged in §10 as one of
the estimate-not-measurement points: if relief staffing actually keeps
machines running through breaks, `BREAKS_STOP_MACHINES = False` recovers
roughly 150 minutes per machine per day, and nobody has confirmed which is
true on the real floor.

**Neighbour routing** extends the same idea as F8 outward by one more step:
the *last* spreading machine of a cut group may call the *next* group's
cutter when its own is saturated — 24-10 may call 24MC5, and 24-13 may call
24MC1 (the numbering wraps around). This rule only counts if the borrowed
cutter is explicitly recorded — an earlier published figure for
neighbour-routing gains had to be withdrawn because it never stated which
cutter was borrowed, and a number like that is unverifiable and therefore
void.

**There is no cold start (rule from the user, 2026-11-06): work is always left from
the day before.** The published model (`runCarry()` / `run_carry()`) runs one timeline
over every plan date, in staffed hours only, so what a machine did not finish carries
into the next shift, and each plan date is sequenced on its own morning around the work
every spreader still has committed. It replaced the earlier closed-day model, which
started every machine empty at 07:15 and so hid the leftover: it showed 1.9% of tables
finishing after their plan date where the real `Pull Date` shows 51.3%.

**Updated 2026-11-09.** The closed-day model (`run()` / `run_day()` / `run_timeline()`)
was **removed** (user: "there will never be a cold start"), together with `pin.js`, the
warm-start table T-E (`warmstart_table.js`) and the pull-ahead table T-F. The
**machine speed factor was removed too** (user: "If it doesn't related to anything, then
remove it"): between 2026-11-06 and 2026-11-09 the machines ran at an ESTIMATED
`SPEED_FACTOR = 0.80` of the G2 rates, calibrated to the Pull Date lateness; that factor
is gone and the model runs at the G2 standard pace, so it is less late than the real
floor (17.78% of tables late against 51.25%, `npm run carryprobe`). The cutters now also
lose time to a changeover (5 min, MO or colour change) and to moving (1.5 min, a
different spreader), both ESTIMATES (SIM_SPEC.md Q19). SIM_SPEC.md §18 has the algorithm
and the staged before/after (`npm run beforeafter`); the 2026-11-06 speed calibration
table is kept there as HISTORICAL.

---

## 3. How a table's time is measured, and why blocking is a length problem

**Rule G2** is the arithmetic that turns a table into minutes: spreading time
and cutting time both scale with layer count and marker length, at
`0.80/8.5` minutes per layer per yard for spreading and `0.40/8.5` for
cutting — cutting runs at roughly half the rate of spreading. **Rule G3**
(cross-referenced elsewhere as **I3**, and its estimate is separately labelled
**rule N**) adds setup time to a C-type table riding on the same physical
table as its paired B table. As of **2026-09-08** this is a **deterministic
8–10 minute range**, not the flat 10 minutes it used to be: one setup per B
table that has any C row, its value a pure function of
`f'{plan_date_iso}|{table_key}'` through an FNV-1a 32-bit hash
(`assumptions.py`'s `C_SETUP_HASH_OFFSET` / `_PRIME`, mapped onto 80–100 tenths
of a minute). Determinism is a hard requirement — `Math.random()` would break
`regress.js` (and the retired `pin.js`) and every reproducibility rule here — and `Math.imul`
is mandatory in the JS port's hash (plain `*` loses precision above 2^53 and
the two languages would silently disagree; README Part 8 trap 17). Every
C-table row still carries `Act LayerQty = 1` and `Marker Length = 1`
placeholders, so a real duration cannot be recovered from the data — the
8–10 minute band is still an **estimate**, just a distributed one rather than a
point value. On the 199-date file it lands a C setup on ~39% of tasks, mean
9.01 min. `tools/csetup-fixture.json` and `test_csetup.py` are the Python-side
cross-check, never executed here (no Python).

**Rule G6** is the most consequential timing rule in the whole model, because
getting it wrong once cost the project a 63% overstatement of a headline
number. G6 says a spreading machine blocks — stops, unable to start its next
lay — once enough lay is already queued at its cutting end that the next lay
has nowhere to go. The measured table length is **21.2 meters**, and the
median marker is 8.8 yards, so roughly 2.4 lays fit on a table at once.

The part of G6 that actually matters is *how* the occupied length clears.
**The table space returns gradually, not all at once.** As the cutting
machine works through a lay, it consumes that lay's length progressively —
feeding it toward the cutter as it cuts — so table space frees up
continuously through the duration of the cut, not in one step the instant
cutting finishes. An earlier version of this model treated each lay as
occupying a fixed slot that only cleared at `cut_end`, as if the whole lay
vanished from the table in one instant when cutting completed. That
simplification is wrong in a specific, quantifiable way: it overstated daily
blocking by **63%** — 3,259 minutes a day against the true, length-based
figure of 1,997. If a number near 3,244 or 3,259 minutes/day is ever seen
quoted for this project, it is the old, incorrect model and should not be
trusted or compared directly against anything computed since. (There is a
second trap layered on top of this one: 3,244 was also computed under the
*old* sequencer, described in §7 below, so a naive comparison against today's
1,997 would be straddling two separate corrections at once, and the size of
the gap would not mean what it appears to mean.)

Two further conservatism notes belong with G6. First, the model assumes a
new lay needs its **full length** free before it can start
(`LAY_NEEDS_FULL_LENGTH = True`) — in reality a spreader lays progressively
and may only need the space to arrive as it goes, which would mean real
blocking is somewhat *less* than modelled, not more. Second, the model
charges a lay exactly its marker length with **no end allowance** — real lays
almost certainly leave a small gap at each end that the model doesn't
account for. Both of these push in the direction of the model being
slightly pessimistic about how much table length is actually free at any
moment, which is the opposite direction from the fix that corrected the
63% overstatement — the two effects are not the same size and should not be
assumed to cancel out.

Idle time — the accounting built on top of G6 — is designed to keep two
different problems apart: a machine with nothing to do because its upstream
cutter is saturated, versus a machine with nothing to do because nobody is
there to run it. But be precise about how far that separation goes.

- The **blocked-percentage denominator** is `busy + blocked`, never staffed
  time (`model.py` `aggregate()`). So the percentage cannot be inflated by
  unstaffed hours — a break or a shift end does not enter it.
- The separate **`occupy()` clamp** — the wait when a lay's start is pushed
  forward out of a break or past shift start — is not added to `blocked` (or
  to anything). That wait is excluded entirely.
- The **`blocked_minutes` figure itself is not clamped to staffed time.** It is
  `_room_at(…) − spread_free_before` on the raw wall clock, and `_room_at` has
  no shift or break awareness, so a G6 wait that crosses a break or runs past a
  day-only machine's shift end banks those unstaffed minutes into the number.
  This is why the Gantt's staffed-only hatching runs about 16% below the minutes
  total on a typical plan date (10–22% by date; 18% across the whole June month —
  42,071 hatched vs 51,200 blocked min). See README Part 7 scope note and Trap 18.

---

## 4. What the model reads, and what it deliberately excludes

The model reads the `HaveCut` sheet of PlanPPC, and three rules govern what
counts as a modellable table in the first place. **Rule J2** admits only
`Type = B` tables and excludes any row where `First Table = Y` — a C-type
table is not modelled as its own entity, it rides on its paired B table via
the G3/I3/N setup-time addition described in §3. **Rule J3** says that
non-universal markers — kids sizes and number sizes — still occupy machine
time on the Gantt (they are real tables that really take real minutes to
spread and cut) but carry no compartment mathematics, because the model's
compartment logic is built entirely around the universal adult-size film
mapping in H5. This exclusion is why the model's own reported daily volume on
trolleys — about 68,700 pieces a day — sits below the roughly 90,000-piece
total in the data: the gap is exactly the non-universal-marker tables that
J3 lets occupy the timeline without contributing garments to a compartment.
Because utilization is a *ratio*, this exclusion doesn't distort the
utilization percentage itself, but it does mean the absolute trolleys-per-day
figures published anywhere in this project are conservative — the real fleet
almost certainly moves somewhat more volume than the model's own numbers
would suggest.

**A second J2 exclusion, profiled and deliberately kept (2026-09-08).** The
199-date file carries **422 rows of types `T1` / `P` / `T` / `R` / `L`** that
have real layer counts and marker lengths — genuine spreading work on real
machine time — but rule J2 (Type B only) excludes them, and they were left
excluded rather than admitted, for byte-continuity with every previously
published number. Like the J3 kids/number-size tables, this under-counts real
machine load; unlike J3 it also under-counts the timeline itself. Noted here
so it is not later rediscovered as a bug: it is a conscious choice to keep the
model's scope frozen while the data source changed underneath it.

**Rule L6** covers something the model cannot see at all: component.
`HaveCut` does not carry a component column, so every table is treated as a
single, undifferentiated component set. L6 itself is a statement about the
real floor, not the model — it says one component is normally printed per
style, and front and back pieces usually share the same Net_Rate — and the
practical consequence is that this project's combine and come-back
conditions that reference "same component" (condition 4 in both lists, §5
below) are enforced everywhere they appear in the logic but can never
actually be verified against real data, because the data to check them
against doesn't exist in this export. The working assumption, per L6, is
that the effect of this gap is probably small — but "probably small" is
explicitly flagged as unverified, not confirmed.

A short list of fields the model simply does not have, beyond component: real
`Net_Rate` (substituted by H5, discussed in §1); fabric arrival or
relax-start time (the model assumes the 24-hour relaxing rule is always
satisfied by the time a table is released, because a table is not released
otherwise — see §6); and shrinkage or shade-lot data, which means batch
*merging at spreading* is completely untested by this model even though
batch merging *at loading* (the subject of Change 2, §5) is fully modelled.

---

## 5. Task readiness — the eight statuses, and why four of them can never fire

Every table carries one of eight colours in the Auto Planning System,
reflecting whether its fabric has relaxed and whether a pattern is on file.
The model reproduces all eight in its legend, because the real system shows
all eight, but only four of them are actually capable of appearing in a
simulated run, and it's worth being explicit about which four never fire and
why — someone who only ever sees the four live colours could reasonably
wonder if the other four are a display bug. They are not; they are the
correct behaviour of a model that has already resolved the condition those
colours represent.

**Normal condition** (pale blue) is the default: fabric relaxed for 24 hours
and a pattern on file. **Normal · stretch spreading** (amber) is a special
case of normal — the last table of a batch by `Pull Date`, spreading the
final few hundred yards — and it is common, not exceptional: 823 of the
1,863 modelled tables (44%) qualify, because batches average only 2.26
tables each, so being the last one happens often. **Completed** (grey) is
driven, since **2026-09-08**, by the **simulated `cut_end`** — the model's own
clock for when a table's spreading *and* cutting finish — so the drawn bar and
its grey-out share one timeline. It used to grey against the *actual*
`Pull Date` (the real floor's finished-spreading timestamp) while the bar was
drawn from the simulated schedule; two clocks on one axis was the "tasks never
turn Completed" bug (README Part 8 §4 D3). `Pull Date` is now kept off the
chart entirely — no "actually finished" marker — though its dataset-wide slip
statistic still shows under the Gantt, and §10 and Part 4 still rely on it.

**Normal · cut queue** (brown) — a normal task queued by hand rather than
by the system — can never fire in this model, because manual intervention by
a planner is, by definition, outside anything a simulation of the automated
system can produce. **No fabric** (navy) can never fire either, for a
different reason: it requires missing `Lot` or `Batch No` data, and every
single one of the 2,717 rows in the export has both fields filled in.

The remaining two — **No pattern, enough fabric** (green) and **No pattern,
not enough fabric** (purple) — deserve the most explanation, because their
absence follows directly from a rule about *when* a table is allowed to
exist in the plan at all, not from a data quirk. **Fabric relaxing is a
precondition, not a variable.** Fabric must relax for 24 hours before a
table may be spread, and a table is simply not released to the floor until
that 24-hour clock has run out — so by the time any table shows up in
`HaveCut` for this model to read, its fabric has, by construction, already
relaxed. The simulation therefore treats every planned table as already
relaxed, which means the "not enough fabric" half of statuses 5 and 6 can
never be true, and both statuses read zero in every run. A slider that let a
user simulate "fabric issued ahead of the relax window" was actually built
at one point and then removed for exactly this reason — it was modelling a
condition the real process makes structurally impossible.

Separately, pattern is very rarely the actual constraint either: the marker
ratio is filled in at the latest 1.5 hours after a plan is uploaded, so in
practice it is available by the time anyone is looking at the day's plan.
Every one of the 1,863 modelled tables in this project's own data has a
marker; the 852 rows with no `Marker Date` are all rows that rule J2 already
excludes for being Type C or first-table rows, so they were never going to
enter the model regardless.

---

## 6. Today's combine and come-back logic

Before any of the three proposed changes below, this is what the real
Job Sequence / Panel Loading Suggest Logic actually enforces today, as nine
numbered combine conditions and six numbered come-back conditions.

A trolley may **combine** — that is, a later table's panels may load onto a
trolley a currently-spreading table already opened — only if: the earlier
table is continuously spread at one workstation (a physical requirement, the
trolley has to still be physically standing there); the two tables share the
same MO (rule H9); the same batch; the same component; the same film code;
the receiving trolley still has empty compartments (checked twice in the
current logic, conditions 6 and 8, which duplicate each other); the current
task needs no more than 4 trolleys total (rule H8); and — the condition that
turns out to matter more than any of the others — the trolley may only wait
if both tables are spread and cut continuously at one workstation, with the
cutting machine never leaving that workstation in between.

That last condition is, in practice, almost never satisfied, because a
cutting machine routinely serves two or three different spreading machines
in rotation rather than sitting still at one — it is described in more
detail in §8, where removing it becomes Change 3.

A trolley may **come back** — return to CCT WIP and be topped up by a later
table — only if the two tables share the same MO, the same batch, the same
colour, the same component, the same film code, and the trolley still has
empty compartments. Note that come-back checks colour where combine does
not, and combine checks continuous-spreading-at-one-workstation where
come-back does not — these are not the same nine-and-six conditions with
different names, they are genuinely different checklists for two different
physical events.

---

## 7. The binding constraint: adjacency, not any of the caps

Before describing what was actually changed, it's worth stating plainly what
the sensitivity testing in this project found the *real* constraint to be,
because it explains why the three changes below are ordered the way they
are, and why several superficially-plausible ideas were tried and abandoned.

**The binding constraint on trolley utilization is adjacency — whether two
tables that could combine ever end up spread back-to-back at the same
workstation — not any of the numeric caps in the rule set.** This was
confirmed by testing the caps directly rather than assuming it: removing the
H8 cap of 4 trolleys per combine entirely gains only +0.7 percentage points
(65.4% → 66.1%). Allowing trolley sets to chain more than two tables instead
of just pairing them gains +0.5 points, from an earlier model variant that no
longer exists in this repo and cannot be regenerated — its 65.3% baseline
predates the sequencing correction described in §9, so it should be read as
directional evidence, not as a number to publish today. Doing both at once
in that older variant reached +3.1 points combined, still well short of what
adjacency itself is worth.

A short list of other ideas were tested and specifically ruled out, and are
recorded here so they are not re-proposed without new information: tuning
`MACHINE_FILL_TARGET` away from 0.70 in either direction (0.60 and 0.85 were
both tried and both scored worse); balancing cut groups by capacity rather
than by spreader count (fewer overrun days, but a longer overall day, because
it pushes work onto the night machines instead of resolving the underlying
shortage); the fabric-issued-ahead slider (impossible under the relaxing
precondition, §5); a Net_Rate scheme switcher (Net_Rate is universal, H5 is
the whole story, §1); and the slot-count blocking model (overstates blocking
by 63%, §3).

Structurally, this is why **Change 1 below (which creates adjacency) and
Change 3 (which removes the need for adjacency entirely) are worth far more
than raising any cap** — the caps were never actually the thing holding
utilization down.

---

## 8. The three proposed changes — simulated, not yet built

These three changes are ISD's implementation spec: what to change in the real
Auto Planning System, in the order they should be built, each one dependent
on the one before it. They have been simulated against 20 real plan dates of
`HaveCut` data — 53.6% utilization today, rising through 59.4%, 65.4%, and
71.3% as each change is added — but as of this writing none has been piloted
on the real floor.

**Change 1 reorders the Job Sequence so same-MO tables land next to each
other.** *(2026-11-10 note: the sentence "Today, the planner clusters tables by MO, colour and batch
together, then spreads that cluster across all three spreading machines of a cut group" describes the
model's old S0, which the user said is not how the floor works. The real Job Sequence is the stored
procedure `data/SQL Job Sequence Logic.sql`: every table gets a cutter, then the least-loaded spreader
takes the shortest waiting table. See `SIM_SPEC.md` §5.)* Today, the planner clusters tables by MO, colour and batch together,
then spreads that cluster across all three spreading machines of a cut group
— so two tables that could combine almost never end up adjacent, because the
clustering logic itself scatters them. Change 1 drops batch from the
clustering key (clustering by MO and colour only), pairs tables up *before*
assigning them to a machine — same-batch pairs first, then same-MO
different-batch pairs — and then assigns each pair to one machine as two
consecutive entries in that machine's queue. The detail that must never be
lost in implementation is that a pair, once formed, is appended to a
machine's queue together; if a later load-balancing step is allowed to split
a pair across two different machines, Change 1 is silently undone and both
of the changes that depend on it lose most of their value. A machine's queued
spreading minutes should stay under roughly 70% of its staffed window
(`MACHINE_FILL_TARGET`, a planning heuristic rather than a written rule) so
the remainder can absorb blocking under G6; if a pair doesn't fit on its
assigned machine, it moves to another machine in the *same* cut group rather
than being split. None of this changes when a table is allowed to release —
the 24-hour batch relaxing precondition (§5) still governs that; Change 1
only reorders tables that are already releasable.

**Change 2 lets one trolley carry two fabric batches instead of one.** This
requires dropping combine condition 3 and come-back condition 2 — both of
which are "same batch," from §6 — and replacing them with a hard ceiling:
`MAX_BATCHES_PER_TROLLEY = 2`, and this cap is never to be 3. The compartment
rules from H4 do not change alongside this: a single compartment still holds
one batch only, and a trolley still holds one film size only across all five
of its compartments — Change 2 only lets two *different* batches occupy two
*different* compartments on the same trolley, it does not relax anything
about what a single compartment may contain. **Change 2 without Change 1 is
worth almost nothing** — measured directly at +0.6 percentage points in an
earlier run — because the combine rule this change loosens can only act on
tables that are already spread adjacently, and without Change 1, today's
sequencer essentially never makes that true. Do not ship Change 2 on its own.

**Change 3 lets a part-filled trolley wait in CCT WIP and be recalled,
instead of leaving immediately.** Today, combine condition 9 only allows a
trolley to wait if both tables are spread and cut continuously at one
workstation with the cutter never leaving — and in practice a cutting
machine routinely serves two or three spreading machines in rotation, so this
condition is almost never met and a part-filled trolley almost always leaves
immediately, carrying whatever fraction of its capacity it happened to
collect. Change 3 removes condition 9 outright and replaces it with an
explicit hold-and-recall cycle, detailed in full in §9. This is the largest
single gain of the three changes, and it carries the one open question this
project cannot resolve on its own — also detailed in §9.

---

## 9. Hold-and-recall in full, and the question it depends on

Change 3's logic keeps a running set of parked trolleys — trolleys that left
a workstation with free compartments and are waiting in CCT WIP rather than
being dispatched — keyed by the combination of MO, colour, component and
film size. Deliberately **not** part of that key: batch. Everything else
about a parked trolley must match a candidate table before it can be
topped up, but which batch it's carrying is not one of the matching
conditions, precisely because Change 2 already established that two
different batches are allowed to share a trolley.

The cycle runs every time a table finishes cutting, in three steps, in this
order. First, anything that has been parked longer than the configured hold
window — 60 minutes by default — is given up on and dispatched as-is, so a
trolley never waits indefinitely. Second, the newly-cut table's panels are
checked against whatever is already parked under its matching key; if a
parked trolley can absorb them without exceeding the 2-batch ceiling from
Change 2, it is recalled to the workstation, loaded, and dispatched
immediately if that fills it. Third, whatever panels are still unloaded after
that open new trolleys, filling up to five compartments each; a newly opened
trolley that leaves with compartments still free is parked (if a bay is
available under the 52-bay ceiling from H7) rather than dispatched
part-full, unless the bay ceiling is already full, in which case it has no
choice but to leave.

Sixty minutes was chosen as the default hold window specifically because it
is a starting point, not a proven optimum: doubling it to two hours scores
higher in simulation (75.4% vs 71.3%) but ties up trolleys — and therefore
fleet capacity — for longer while it does. Whether 60 minutes, 120, or some
other value is right on the real floor is itself something this model cannot
settle; it can only show the trade-off.

**The open question that sits underneath all of this:** step two above can
recall a parked trolley to *whichever* workstation next needs it, not
necessarily the workstation it originally left from — and this distinction,
on its own, is most of Change 3's simulated value. Restricting recall to the
same workstation only reaches 65.9% utilization, barely above the 65.4%
baseline with no hold at all; allowing recall to any workstation reaches
71.3%. The difference between those two numbers — roughly six points of
utilization — is entirely the value of being able to move a parked trolley
somewhere other than where it started, and **nobody has confirmed how, or
whether, that move actually happens on the real floor**: by labour, by AGV,
or by manual push, and at what cost. If moving a trolley between workstations
turns out to be slow or expensive in practice, Change 3's real value
collapses from roughly +5.9 points toward +0.5 — this is a question only
Production can answer, and it is the single largest unresolved dependency in
the entire change spec.

---

## 10. What's measured, what's estimated, and what's simply missing

Every number this project depends on falls into one of three categories, and
conflating them is the single easiest way to overstate confidence in a
result. This project has already made that mistake once and corrected it —
see §3 on the 63% blocking overstatement — so the distinction is kept
explicit here rather than left implicit in the code.

**Measured, from the real floor or the real data:** the spreading table
length of 21.2 meters; the shift hours and break windows (§2); and every
field pulled directly from `HaveCut` — marker dates, pull dates, marker
ratios, layer counts.

**Estimated — a number standing in for a measurement that hasn't been taken
yet, and flagged as such:** the trolley round-trip cycle time,
`CYCLE_DAYS_ESTIMATED = 7` days, is the single largest estimate in the
project and arguably the most consequential number here — the entire fleet
sizing question turns on whether the real cycle is closer to the 5-day
allowance or to 7 measured days, and as of this writing, nobody has actually
timed it. The C-table setup addition (rule G3/I3/N) is similarly an estimate
rather than a timed value — as of 2026-09-08 a deterministic **8–10 minute
range** (hash-seeded per table, mean ~9.0 min) rather than the flat 10 it was,
but still a guessed band, because every C row's `Act LayerQty` and
`Marker Length` are placeholder 1s (§3). `MACHINE_FILL_TARGET = 0.70`
is explicitly a planning heuristic rather than a rule with any documentary
source at all — it was arrived at by testing 0.60 and 0.85 against it and
finding both worse, which is evidence it is *a* reasonable value, not proof
it is *the* correct one.

**Simply missing from the data, and checked rather than assumed:** there is
no `Net_Rate` column anywhere in the export — all 66 headers and all 13,136
shared strings were searched directly rather than inferred from a sample —
so H5 substitutes for it (§1). There is no component field, so L6's
component-matching conditions are enforced in logic but unverifiable against
real data (§4). There is no fabric-arrival or relax-start timestamp, so the
model cannot measure how often the 24-hour relaxing precondition is actually
tight in practice, only that it is assumed always satisfied by the time a
table is released (§5). `Cut Date` is empty on all but one of 2,717 rows, and
`Marker Date` is missing on 852 rows — but every one of those 852 is already
excluded by rule J2 for being a Type C or first table, so the gap has no
effect on anything the model actually computes.

A related and easily-confused fact about the underlying data belongs here
too, because it looks like a data-quality problem and isn't one: `Pull Date`
is the table's *actual* finished-spreading timestamp, not a plan, and
across all 1,863 tables in the export, 49% finish after their nominal plan
date and 14% finish more than a full day late. That sounds alarming stated
as an average, but it is not representative of the typical table: the
*median* table actually finishes about 23 minutes before midnight on its own
plan date, so on net most tables are not late at all. The lateness that does
exist is concentrated in a tail — of the 912 tables that do run late, half of
those slip by more than half a day, and the mean slip among just that late
group is 0.9 days, with one outlier date's latest table finishing 8.3 days
after its plan date. A number stated once as "median slip is a day" was
wrong and should not be repeated; this paragraph is the corrected version.

Four measurements were identified as the highest-value things to actually go
and record on the real floor, precisely because each one would directly
replace one of the estimates or unknowns above with a fact: the true trolley
round-trip time (replaces `CYCLE_DAYS_ESTIMATED`); compartments loaded per
trolley *and* garments per compartment at the point of dispatch, measured
together rather than separately, since utilization alone cannot distinguish
a trolley that left part-opened from one that opened fully but loaded only
partly full (this is precisely the H6 distinction from §1, and this project
has already had to explain that difference once in public); how often a
Change-3 recall is geometrically possible but the trolley physically cannot
be moved to where it's needed (directly answers the open question in §9);
and the real combine fire rate, before and after Change 1, since an earlier
projection predicted a jump from 37 combines a day to 370 and nobody has
confirmed that against reality yet.

---

## 11. Rules about the simulation itself, not the factory

A smaller set of rules governs how this model must be built and kept
honest, and they matter just as much to trust in the output as the factory
rules do, because most of the factory-rule corrections recorded above (the
63% blocking fix, the H6 metric gap, the shift-hour correction) were only
caught *because* these rules were being followed.

**`assumptions.py` is the only place a number is allowed to live.** Nothing
is to be hard-coded inside `model.py` itself, and every value in
`assumptions.py` must cite the rule it came from — an estimate must say so
in capital letters rather than sit indistinguishable from a measured value.
**The repository outranks any deck or report built from it** — if a number in
a slide and a number in this repo ever disagree, the repo is correct, because
it is the thing that was actually run; and any change that moves a
previously-published number must be reported with an explicit before/after
table, never silently absorbed into a new baseline. **A Node or other
alternate-language port of the model must mirror the Python exactly, quirks
included** — if the Python has an odd behaviour, the port reproduces that
odd behaviour faithfully, and fixing it is a separate, explicitly announced
change rather than something that happens quietly during a port. **No build
artifact is ever hand-written** — `out/index.html`, `out/results.json`,
`out/sweep.json`, and their equivalents only ever come from actually running
the build, never from editing the output directly. **Nothing publishes if the
parity gate fails**: the page's own loading arithmetic must match the model's
independently, across all four of trolleys, utilization, compartments and
combines. That gate is now **`node tools/parity_check.js`** (`npm run parity`):
it opens each built month file in a real browser and calls the page's own
`window.__SIM.__check()`, which walks every plan date x every `full` variant
(21.2 m at 5 and 7 cutters) x every reachable (sequencing mode, batches, WIP
hold, any-workstation) combination — **18,486 checks across the three
April–June month files** as of 2026-09-08, all passing. It compares the page's
`loadTrolleys()` port against the trace's `expected` block, which
`tools/daytrace.js` built from `tools/model.js`'s `load_trolleys()` — two
independent reimplementations, so the match is not circular. This replaces the
old **4,680 / 4,680** figure, which was 20 dates x 2 sequencing modes x 3
table lengths and predates both the 3-mode sequencing split and the
cutter-count axis. Alongside it: 23 loading-port tests, 18 status/shift/clock
tests, and layout assertions confirming tags balance and no external URLs leak
into the page. **Idle time and the trolley shortage are two independent findings**,
and a saving from one must never be claimed against the other, because they
were tested against each other directly and neither variant moves the other
(§7, §9). **Every table published anywhere must be regenerable by a script
that actually lives in this repository** — this rule exists because it was
violated once, when two rows of a published table turned out to have come
from a throwaway script instead of the checked-in `idle_variants.py`, and
those two rows had to be publicly withdrawn as a result. And finally, the
`out/*.bak` files are never to be touched or deleted — they are the last
surviving output of a genuine Python run of this model, and they are the
only non-circular reference point anything written in another language (like
the Node port in `tools/`) can ever be validated against.

---

## 11b. The Rules Lab estimates (added 2026-11-05)

The Rules Lab tab (`tools/lab.js`, spec in `SIM_SPEC.md` §17) simulates what the model
deliberately ignores, using three **ESTIMATES, NOT MEASURED** values in `assumptions.py`:
the fabric arrival window (12–48 h before a batch's first plan date, then 24 h relaxing),
the cutter changeover on an MO or colour change (5 min), and the cutter move between
workstations (1.5 min). Every Lab number moves with them. It also adds, as options, a
same-batch-first WIP recall, a different-batch recall, pull-ahead across plan dates and a
day / night / both shift choice. None of it changes the headline or the gates.

## 12. Where a higher-fidelity simulation would actually start

Everything in §10 is, by construction, the list of what this model currently
gets by estimate or assumption rather than by measurement — and closing any
one of those gaps is what "more advanced than this" concretely means, rather
than a vague aspiration. In descending order of leverage on the model's
actual conclusions: **the trolley cycle time** is the single number the
entire fleet-sizing business case turns on, and it has never been timed;
**whether a parked trolley can actually move between workstations**, and at
what cost, decides whether Change 3 is worth six points of utilization or
effectively nothing; **cutting-machine travel time between the spreaders it
serves** is entirely absent from the idle-time model, and since it can only
ever add blocking, not remove it, the true idle-time picture is probably
somewhat worse than the 1,997 minutes/day this model currently reports;
**real Net_Rate and real component data**, if ever exported from the source
system, would let this model stop substituting H5 and L6 and start checking
its own combine and come-back logic against reality instead of assuming it
holds; and **direct floor measurement of compartments-loaded and
garments-per-compartment at dispatch** would let a future version verify the
H6 distinction (§1) empirically instead of only ever computing both halves of
it from the same upstream simulation.

**The warm start. HISTORICAL (cold-start model, retired 2026-11-09; no longer
reproducible): the carry-over floor (§2) now carries the backlog, and
`warmstart_table.js` is deleted.** Every plan date was a closed simulation (§2) — machines empty
at 07:15, no backlog carried. Seeding each date from the *actual* previous-day
late work is the version that would move blocking and cutter load in a
believable direction: a real backlogged cutter makes the day's first tables
wait, so the lay sits longer and G6 blocking rises. It needs `Pull Date` (the
finished-spreading timestamp, so the cutting backlog is inferred, not given) and
is untried. Note this is not the same as chaining the model's *own* earlier
schedule forward — that finishes ~22:15 with ~9 h of empty overnight to drain,
so it carries almost nothing (tested: W1/W2 in table T-E, <0.5 pt).

**What the 2026-09-08 work changed on this list.** Nothing was *closed* — every
gap above is still open — but two moved: the cutting-machine count is now a
modelled axis (5–8, §2), so the "add a cutter" question from Part 7 §4 can be
answered with numbers rather than argued, even though cutter *travel* time
between spreaders is still absent; and the C-table setup is now a distributed
8–10 min estimate rather than a point value (§3, §10), which narrows but does
not remove that guess. The trolley cycle time, trolley movement between
workstations, and the Net_Rate / component / floor-measurement gaps are
exactly where they were.
