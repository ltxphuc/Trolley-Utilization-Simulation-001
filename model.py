"""
THE MODEL
=========
One day of Central Cutting, simulated end to end, in four stages:

    1. READ      each Plan Date in the HaveCut sheet becomes one day of tasks
    2. SEQUENCE  the planner assigns tasks to spreading machines, in an order
    3. TIME      spreading and cutting run; blocking and idle time fall out
    4. LOAD      cut panels go into trolley compartments; trolleys are counted

Stages 2 and 4 are deliberately separate, and that separation IS the finding:
the current planner (flowchart 3.3a) spreads one fabric batch across the three
machines of a cut group, so two tables that COULD share a trolley almost never
end up next to each other at one workstation — and the loading step can only
combine tables that are already adjacent.

Every tunable lives in assumptions.py. Nothing is hard-coded here.
"""
from __future__ import annotations

import collections
import datetime
import json
import math
import statistics
from dataclasses import dataclass
from typing import Literal

import openpyxl

import assumptions as A


# =====================================================================
# THE SHIFTS
# Every time is minutes from 07:15. A machine can only work inside its
# shift, and not through a break, so the timeline has to step over those
# windows rather than run continuously.
# =====================================================================
def working_intervals(nights: bool) -> list:
    """-> [(start, end), ...] the machine can actually work in, in order."""
    start, end = A.NIGHT_SHIFT if nights else A.DAY_SHIFT
    start = min(start, A.DAY_SHIFT[0])          # night machines work the day too
    breaks = list(A.DAY_BREAKS) + (list(A.NIGHT_BREAKS) if nights else [])
    if not A.BREAKS_STOP_MACHINES:
        breaks = []

    spans, cursor = [], start
    for b_start, b_end in sorted(breaks):
        if b_end <= cursor or b_start >= end:
            continue
        if b_start > cursor:
            spans.append((cursor, min(b_start, end)))
        cursor = max(cursor, b_end)
    if cursor < end:
        spans.append((cursor, end))
    return spans


# =====================================================================
# THE MACHINE LAYOUT
# One grouping of spreaders under cutters decides everything the sequencer
# and the timeline need to know about the machines. It used to be five
# module-level constants read straight off A.CUT_GROUPS; it is a function of
# a grouping now, so a run can be given a different cutter count without
# mutating module state (which would make two layouts in one build interleave
# unsafely — see idle_variants.py's routing() for the pattern NOT used here).
# =====================================================================
def machine_layout(cut_groups: dict) -> dict:
    """Everything the sequencer and the timeline need to know about the
    machines, derived from one grouping. F8 and the night-shift sets are
    read from assumptions and are the same at every cutter count."""
    primary_cut = {m: c for c, ms in cut_groups.items() for m in ms}
    spreaders = list(primary_cut)
    spreader_shift = {m: working_intervals(m in A.NIGHT_SHIFT_SPREADERS) for m in spreaders}
    cutter_shift = {c: working_intervals(c in A.NIGHT_SHIFT_CUTTERS) for c in cut_groups}
    return {
        'cut_groups': cut_groups,
        'primary_cut': primary_cut,
        'spreaders': spreaders,
        'spreader_shift': spreader_shift,
        'cutter_shift': cutter_shift,
        # Staffed minutes, net of breaks — derived, never hard-coded, so the
        # planning heuristic and the Gantt can never disagree about how long a
        # machine runs.
        'machine_minutes': {m: sum(e - s for s, e in spreader_shift[m]) for m in spreaders},
        'cutter_minutes': {c: sum(e - s for s, e in cutter_shift[c]) for c in cut_groups},
        'shift_end': max(max(e for _, e in spans) for spans in spreader_shift.values()),
    }


LAYOUT = machine_layout(A.CUT_GROUPS)

# The old module-level names, kept as aliases into the default layout so
# run.py, daytrace.py and idle_variants.py read exactly as they did.
PRIMARY_CUT = LAYOUT['primary_cut']
SPREADERS = LAYOUT['spreaders']
SPREADER_SHIFT = LAYOUT['spreader_shift']
CUTTER_SHIFT = LAYOUT['cutter_shift']
MACHINE_MINUTES = LAYOUT['machine_minutes']
CUTTER_MINUTES = LAYOUT['cutter_minutes']
SHIFT_END = LAYOUT['shift_end']


def _advance(spans: list, t: float) -> float:
    """The first working instant at or after t."""
    for s, e in spans:
        if t < s:
            return s
        if t < e:
            return t
    return t                                    # past the end of the shift


def occupy(spans: list, start: float, minutes: float) -> tuple:
    """Run `minutes` of work from `start`, pausing for anything non-working.

    -> (actually started, finished). Work past the end of the shift runs on
    rather than being lost — the day simply overruns, which is the thing the
    idle-time analysis is about.
    """
    t = _advance(spans, start)
    began, left = t, minutes
    for s, e in spans:
        if left <= 0:
            break
        if e <= t:
            continue
        t = max(t, s)
        room = e - t
        if room >= left:
            return began, t + left
        left -= room
        t = e
    return began, t + left                      # overran the shift


# =====================================================================
# A scenario is just the three changes, switched on or off.
# =====================================================================
@dataclass(frozen=True)
class Scenario:
    name: str
    # CHANGE 1 — 'today' is no pairing at all; the other two both cluster by
    # MO+colour and pair same-batch tables first (pass 0), but only
    # 'cross_batch' goes on to pair whatever's left across different batches
    # (pass 1) — see _sequence_mo_aware. Not derived from max_batches: a
    # scenario can ask for same-batch-only pairing at max_batches=2, or for
    # cross-batch pairing at max_batches=1 (the sequencer will pair toward a
    # combine the loader can never actually make — see README Part 8 §3, the
    # 2026-09-08 T-D fix, for why S1 stopped doing that by default).
    sequencing_mode: Literal['today', 'today_grouped', 'same_batch', 'cross_batch'] = 'today'
    max_batches: int = 1                # CHANGE 2  (1 = today, 2 = proposed)
    wip_hold_minutes: int = 0           # CHANGE 3  (0 = off)
    hold_any_workstation: bool = True
    # The OLD S1-S3 rule: a whole MO + colour kept on one cut group
    # (_sequence_mo_aware). False = the pairs rule (_sequence_pairs). Only has an
    # effect when sequencing_mode is not 'today'.
    mo_one_group: bool = False

    @property
    def cross_batch(self) -> bool:
        return self.max_batches >= 2


# =====================================================================
# 1. READ
# =====================================================================
def parse_marker_ratio(raw) -> dict:
    """'S/2,M/3,L/2' -> {'S': 2, 'M': 3, 'L': 2}"""
    out = {}
    for part in str(raw or '').split(','):
        if '/' not in part:
            continue
        size, count = part.rsplit('/', 1)
        try:
            out[size.strip()] = int(float(count))
        except ValueError:
            pass
    return out


def _as_datetime(value):
    """Excel gives datetimes; anything else is treated as missing."""
    return value if isinstance(value, datetime.datetime) else None


# ---------------------------------------------------------------- C setup (G3)
# The setup a C table adds to its B table is a RANGE now, and it is drawn from
# the table's own identity rather than at random: a random draw would make every
# rebuild disagree with the last one, which would permanently fail the parity
# gate. Python and the Node port must agree bit for bit, so the
# hash is integer-only and the mapping is one correctly-rounded division.
def _table_key(value) -> str:
    """The Table No as one string both languages spell the same way.

    openpyxl returns int for an integer-valued cell and SheetJS returns a JS
    number; str(123.0) is '123.0' in Python but String(123) is '123' in JS, so
    the two would seed different hashes for the same table without this.
    """
    if value is None:
        return ''
    if isinstance(value, float):
        if not value.is_integer():
            raise ValueError(
                'Table No %r is a non-integer number: Python and JS do not '
                'agree on its decimal spelling, so the C-setup seed would '
                'differ between the model and its port.' % (value,))
        return str(int(value))
    if isinstance(value, int):
        return str(value)
    return str(value).strip()


def _fnv1a32(s: str) -> int:
    """FNV-1a, 32 bit. Small, well defined, and expressible in both languages
    with integer arithmetic only — no float, so no rounding to disagree on."""
    h = A.C_SETUP_HASH_OFFSET
    for b in s.encode('utf-8'):
        h ^= b
        h = (h * A.C_SETUP_HASH_PRIME) & 0xFFFFFFFF
    return h


def _c_setup_minutes(day, table_no) -> float:
    """G3/I3 — 8.0 to 10.0 minutes, the same value every run for the same
    (plan date, table). Tenths keep the arithmetic exact until the one
    division, which is correctly rounded and therefore identical in Python 3
    and JS."""
    steps = A.C_SETUP_MINUTES_MAX_TENTHS - A.C_SETUP_MINUTES_MIN_TENTHS + 1
    h = _fnv1a32('%s|%s' % (day.isoformat(), _table_key(table_no)))
    tenths = A.C_SETUP_MINUTES_MIN_TENTHS + (h % steps)
    return tenths / 10.0


def load_days(path: str | None = None, with_stats: bool = False):
    """-> {date: [task, ...]} — one entry per Plan Date.

    With `with_stats`, also returns {date: rows skipped} so the dashboard can
    say how many of the day's planned tables the model actually carries.
    """
    wb = openpyxl.load_workbook(path or A.DATA_FILE, read_only=True, data_only=True)
    rows_iter = wb[A.DATA_SHEET].iter_rows(min_row=1, values_only=True)
    header = next(rows_iter)
    col = {name: i for i, name in enumerate(header)}
    rows = [r for r in rows_iter if r[0]]

    # C tables share a physical table with a B table and add setup time (G3/I3).
    # Counted, not just collected: C_SETUP_PER_C_ROW switches between one setup
    # per physical table (today's shape — the count is ignored) and one per C
    # row. 92 of 6,271 matched keys carry two rows.
    c_tables = collections.Counter(
        (r[col['Plan Date']].date(), r[col['Table No']])
        for r in rows
        if r[col['Type']] == 'C' and r[col['Plan Date']]
    )

    days = collections.defaultdict(list)
    skipped = collections.Counter()
    for r in rows:
        plan_date = _as_datetime(r[col['Plan Date']])
        if r[col['Type']] != 'B' or r[col['First Table']] == 'Y':
            if plan_date:
                skipped[plan_date.date()] += 1                     # J2
            continue
        if not plan_date:
            continue
        ratio = parse_marker_ratio(r[col['Marker Ratio']])
        layers = r[col['Act LayerQty']] or 0
        marker_len = r[col['Marker Length']] or 0
        if not ratio or layers <= 0 or marker_len <= 0:
            skipped[plan_date.date()] += 1
            continue

        day = plan_date.date()
        # J3 — only universal-size markers get trolley accounting. Kids and
        # number-size markers still occupy machines, so they stay in the
        # timeline; they simply carry no compartments.
        universal = all(s in A.FILM_SIZE_BY_GARMENT_SIZE for s in ratio)
        c_rows = c_tables[(day, r[col['Table No']])]
        setup = (_c_setup_minutes(day, r[col['Table No']])
                 * (c_rows if A.C_SETUP_PER_C_ROW else 1)) if c_rows else 0

        days[day].append({
            'table_no': r[col['Table No']],
            'mo': r[col['MO']],
            'style': r[col['STYLE']],
            'color': r[col['Color']],
            'lot': r[col['Lot']],
            'batch': r[col['Batch No']],
            'layers': layers,
            'marker_length': float(marker_len),
            'needs_trolleys': universal,
            'pieces_by_size': {s: n * layers for s, n in ratio.items()} if universal else {},
            # every piece the table cuts (equals Cut Qty), universal sizes or not
            'pieces_total': sum(ratio.values()) * layers,
            'spread_minutes': layers * A.SPREAD_MIN_PER_LAYER_PER_YARD * float(marker_len) + setup,
            'cut_minutes': layers * A.CUT_MIN_PER_LAYER_PER_YARD * float(marker_len),
            # Carried separately as well as inside spread_minutes: it is the
            # only way the build can report the C-setup distribution and write
            # the cross-language fixture without reading the workbook twice.
            # Nothing in stages 2-4 reads it.
            'c_setup_minutes': setup,
            # ---- readiness inputs (see "Task readiness statuses" in README) ----
            'plan_date': day,
            'has_pattern': _as_datetime(r[col['Marker Date']]) is not None,
            'has_fabric': bool(r[col['Lot']]) and bool(r[col['Batch No']]),
            # Pull Date is the ACTUAL finished-spreading timestamp, not a plan.
            'spread_done_at': _as_datetime(r[col['Pull Date']]),
            # order type (订单类型: QR / Normal / SQR): S0's Job Sequence priority. Last field on purpose.
            'order_type': '' if r[col['订单类型']] is None else str(r[col['订单类型']]).strip(),
        })

    days = dict(days)
    _stamp_batch_readiness(days)
    return (days, dict(skipped)) if with_stats else days


def _stamp_batch_readiness(days: dict):
    """Derive the two batch-level readiness flags, in place.

    Neither has a source column, so both are inferred:

    `batch_first_planned`  the earliest Plan Date any table of this batch
                      appears on. Fabric arrival is not in the export, so this
                      anchors the relax simulation: the fabric is taken to be
                      issued FABRIC_ISSUE_LEAD_HOURS before this, and a table is
                      ready once its scheduled spread start is RELAX_HOURS past
                      that. Whether a table is relaxed therefore depends on the
                      sequence, and is worked out per scenario — not here.

    `is_batch_last`   the table that spreads the last yards of a batch — the
                      one that may stretch-spread. Taken as the batch's final
                      table by actual finished-spreading time.
    """
    first_plan, last_table = {}, {}
    for date, tasks in days.items():
        for t in tasks:
            batch = t['batch']
            if batch not in first_plan or date < first_plan[batch]:
                first_plan[batch] = date
            done = t['spread_done_at']
            if done is not None:
                previous = last_table.get(batch)
                if previous is None or done > previous[0]:
                    last_table[batch] = (done, t)

    for tasks in days.values():
        for t in tasks:
            arrived = first_plan[t['batch']]
            t['batch_first_planned'] = arrived
            # minutes from midnight of THIS table's plan date back to midnight of
            # the day its batch first appeared. Zero or negative.
            t['batch_first_offset_minutes'] = (
                datetime.datetime.combine(arrived, datetime.time.min)
                - datetime.datetime.combine(t['plan_date'], datetime.time.min)
            ).total_seconds() / 60
            t['is_batch_last'] = last_table.get(t['batch'], (None, None))[1] is t


# =====================================================================
# COMPARTMENT MATHS  (H1, H3, H4, H5)
# =====================================================================
def compartments_for(pieces_by_size: dict) -> dict:
    """-> {film_size: [pieces in each compartment]}

    A compartment holds one size on one film, up to COMPARTMENT_CAP.
    Sizes on the same film may not share a compartment unless the tables
    are combined (see combined_compartments)."""
    out = collections.defaultdict(list)
    for size, qty in pieces_by_size.items():
        film = A.FILM_SIZE_BY_GARMENT_SIZE[size]
        full, remainder = divmod(qty, A.COMPARTMENT_CAP)
        out[film].extend([A.COMPARTMENT_CAP] * full)
        if remainder:
            out[film].append(remainder)
    return out


def trolleys_for(comps: dict) -> int:
    """Compartments of different film sizes may not share a trolley (H4)."""
    return sum(math.ceil(len(v) / A.TROLLEY_COMPARTMENTS) for v in comps.values() if v)


def combined_compartments(a: dict, b: dict) -> dict:
    """Compartments when two tables are loaded together.

    SAME batch      -> their pieces merge, so two part-full compartments of the
                       same size become one (Panel Loading Logic rule 2).
    DIFFERENT batch -> compartments stay separate (H1/H4) because a compartment
                       may only hold one batch — but they share the trolley.
    """
    if a['batch'] == b['batch']:
        merged = collections.Counter(a['pieces_by_size'])
        merged.update(b['pieces_by_size'])
        return compartments_for(merged)

    out = collections.defaultdict(list)
    for table in (a, b):
        for film, comps in compartments_for(table['pieces_by_size']).items():
            out[film].extend(comps)
    return out


def can_combine(a: dict, b: dict, cross_batch: bool):
    """The combine rule. Returns the compartment layout, or None if forbidden.

    Conditions checked here:
      - both tables actually need trolleys                    (J3)
      - same MO                                               (H9)
      - same colour
      - same batch, UNLESS cross_batch is on   <-- CHANGE 2 relaxes this
      - the pair does not need more than 4 trolleys           (H8)
    Adjacency (the tables must be back-to-back at one workstation) is enforced
    by the caller, because it is a property of the sequence, not the pair.
    """
    if not a['needs_trolleys'] or not b['needs_trolleys']:
        return None
    if a['mo'] != b['mo'] or a['color'] != b['color']:
        return None
    if a['batch'] != b['batch'] and not cross_batch:
        return None
    comps = combined_compartments(a, b)
    if trolleys_for(comps) > A.MAX_TROLLEYS_PER_COMBINE:
        return None
    return comps


# =====================================================================
# 2. SEQUENCE
# =====================================================================
def _pick_machine(candidates, load, work, layout):
    """Least-loaded machine that still has staffed room; else least-loaded."""
    spreaders = layout['spreaders']
    machine_minutes = layout['machine_minutes']
    room = [m for m in candidates if load[m] + work <= machine_minutes[m] * A.MACHINE_FILL_TARGET]
    if room:
        return min(room, key=load.get)
    room = [m for m in spreaders if load[m] + work <= machine_minutes[m] * A.MACHINE_FILL_TARGET]
    if room:
        return min(room, key=load.get)
    return min(spreaders, key=lambda m: load[m] / machine_minutes[m])


def sequence(tasks: list, sequencing_mode: str, layout: dict = None, init_load: dict = None,
             init_cut: dict = None, mo_one_group: bool = False) -> dict:
    """-> {machine: [task, ...]} in the order they will be spread.

    `sequencing_mode` is one of Scenario.sequencing_mode's three values.
    `layout` overrides the machine grouping — machine_layout() of any entry in
    A.CUT_GROUPS_BY_CUTTER_COUNT. Default is the 5-cutter floor.
    `init_load` (carry-over floor only): minutes of work each spreader already
    has committed when the day is planned, so the planner balances around it.
    `init_cut` (carry-over floor only): staffed minutes each cutter still has to
    cut at the day's start; the pairs rule balances the cutters on it.
    `mo_one_group`: keep a whole MO + colour on one cut group (the old S1-S3).
    """
    layout = LAYOUT if layout is None else layout
    group_load = {c: 0.0 for c in layout['cut_groups']}
    machine_load = {m: 0.0 for m in layout['spreaders']}
    plan = {m: [] for m in layout['spreaders']}
    if init_load:
        for m in layout['spreaders']:
            machine_load[m] = init_load[m]
        for c in layout['cut_groups']:
            for m in layout['cut_groups'][c]:
                group_load[c] += machine_load[m]

    # 'today' is S0, the real Job Sequence (_sequence_job_seq). 'today_grouped' is the
    # model's S0 before 2026-11-10 (kept only so npm run beforeafter can reproduce it).
    # Both ignore mo_one_group.
    if sequencing_mode == 'today':
        return _sequence_job_seq(tasks, plan, machine_load, layout)
    if sequencing_mode == 'today_grouped':
        return _sequence_today(tasks, plan, machine_load, group_load, layout)
    cross_batch = sequencing_mode == 'cross_batch'
    if mo_one_group:
        return _sequence_mo_aware(tasks, plan, machine_load, group_load, layout, cross_batch)
    return _sequence_pairs(tasks, plan, machine_load, group_load, layout, cross_batch, init_cut)


def _sequence_job_seq(tasks, plan, machine_load, layout):
    """S0, the real Job Sequence: data/SQL Job Sequence Logic.sql, P_Task_Calculate
    (core loop only). Mirrors tools/model.js sequenceJobSeq, which has the full comment.

    Pass 1 (L2105-2344): every table is given a CUTTER. Tables go in order of priority
    (order type SQR < QR < Normal, A.ORDER_TYPE_PRIORITY), then plan order. A table goes
    to a cutter that already holds a table of the same MO + batch this date, if any, else
    to any cutter; among those, the one with the least load = spreading minutes /
    spread_count. spread_count counts each spreader against its FIXED cutter as
    1/(cutters it maps to). The load starts at the spreading minutes already committed
    (init_load) on the cutter's fixed spreaders, unweighted.
    Pass 2 (L3693-): the spreader with the least spreading minutes (NOT divided by its
    shift minutes) takes the next table, from the tables whose cutter it feeds (primary or
    flexible), or from all tables if none: by priority, then the SHORTEST spreading time,
    then plan order. The SQL's "closest to the cutter's gap" term never runs (L3715,
    L3773-3777): mirrored as written. No fill target, no changeover."""
    spreaders = layout['spreaders']
    primary = layout['primary_cut']
    cutters = list(layout['cut_groups'])

    def map_of(m):
        return A.FLEXIBLE_CUT.get(m) or [primary[m]]

    def prio_of(t):
        return A.ORDER_TYPE_PRIORITY.get(t['order_type'], A.ORDER_TYPE_PRIORITY_DEFAULT)

    spread_count = {c: 0.0 for c in cutters}
    raw = {c: 0.0 for c in cutters}
    for m in spreaders:
        spread_count[primary[m]] += 1 / len(map_of(m))
        raw[primary[m]] += machine_load[m]

    n = len(tasks)
    prio = [prio_of(t) for t in tasks]
    order = sorted(range(n), key=lambda i: (prio[i], i))

    cutter_of = [None] * n
    held = {}                                   # MO + batch -> cutters holding one this date
    for i in order:
        t = tasks[i]
        key = (str(t['mo']), str(t['batch']))
        has = held.get(key)
        cands = [c for c in cutters if c in has] if has else cutters
        c = min(cands, key=lambda x: raw[x] / spread_count[x])
        raw[c] += t['spread_minutes']
        cutter_of[i] = c
        if has is None:
            held[key] = {c}
        else:
            has.add(c)

    placed = [False] * n
    remaining = n
    while remaining > 0:
        m = min(spreaders, key=lambda x: machine_load[x])
        feeds = map_of(m)
        pool = [i for i in range(n) if not placed[i] and cutter_of[i] in feeds]
        if not pool:
            pool = [i for i in range(n) if not placed[i]]
        best = min(pool, key=lambda i: (prio[i], tasks[i]['spread_minutes'], i))
        placed[best] = True
        remaining -= 1
        plan[m].append(tasks[best])
        machine_load[m] += tasks[best]['spread_minutes']
    return plan


def _sequence_today(tasks, plan, machine_load, group_load, layout):
    """The model's S0 until 2026-11-10 (mode 'today_grouped'): not the real Job Sequence
    (user, 2026-11-09). TODAY (flowchart 3.3a): cluster by MO + colour + batch, then scatter that
    batch across the three machines of one cut group, one table at a time to
    whichever machine is least loaded. Two tables that could share a trolley
    therefore land back-to-back only by accident.

    Assignment used to be a fixed round robin restarting at machines[0] for
    every cluster. Tables are sorted longest-first, so the biggest table of
    every cluster landed on the group's first machine: 24-01 carried 811
    spread-min/day against 24-03's 503 on near-identical table counts."""
    clusters = collections.defaultdict(list)
    for t in tasks:
        clusters[(t['mo'], t['color'], t['batch'])].append(t)

    cut_groups = layout['cut_groups']
    for group_tasks in sorted(clusters.values(),
                              key=lambda ts: -sum(t['spread_minutes'] for t in ts)):
        cut_group = min(group_load, key=lambda c: group_load[c] / len(cut_groups[c]))
        machines = cut_groups[cut_group]
        for task in sorted(group_tasks, key=lambda t: -t['spread_minutes']):
            machine = _pick_machine(machines, machine_load, task['spread_minutes'], layout)
            plan[machine].append(task)
            machine_load[machine] += task['spread_minutes']
            group_load[cut_group] += task['spread_minutes']
    return plan


def _sequence_mo_aware(tasks, plan, machine_load, group_load, layout, cross_batch):
    """CHANGE 1: cluster by MO + colour, pair tables up BEFORE assigning, and
    put each pair on ONE machine back-to-back.

    Priority order, as specified:
        pass 0 — pair same MO + same batch first
        pass 1 — then pair same MO + different batch, ONLY if cross_batch —
                 this is the 2026-09-08 fix. Pass 1 used to run unconditionally,
                 which for S1 (same-batch-only intent, max_batches=1) paired
                 the sequence toward combines the loader could never make
                 (can_combine(cross_batch=True) was called regardless of
                 whether the scenario's own settings made that reachable).
                 The pairing wasn't inert even though the combine never fired
                 — it still decided which machine the pair's unit landed on.
    """
    clusters = collections.defaultdict(list)
    for t in tasks:
        clusters[(t['mo'], t['color'])].append(t)

    passes = (True, False) if cross_batch else (True,)

    for group_tasks in sorted(clusters.values(),
                              key=lambda ts: -sum(t['spread_minutes'] for t in ts)):
        ordered = sorted(group_tasks, key=lambda t: (str(t['batch']), -t['spread_minutes']))
        taken = [False] * len(ordered)
        units = []

        for same_batch_pass in passes:
            for i in range(len(ordered)):
                if taken[i]:
                    continue
                for j in range(i + 1, len(ordered)):
                    if taken[j]:
                        continue
                    is_same_batch = ordered[i]['batch'] == ordered[j]['batch']
                    if is_same_batch != same_batch_pass:
                        continue
                    if can_combine(ordered[i], ordered[j], cross_batch=True):
                        units.append([ordered[i], ordered[j]])
                        taken[i] = taken[j] = True
                        break
        units += [[t] for i, t in enumerate(ordered) if not taken[i]]

        cut_groups = layout['cut_groups']
        cut_group = min(group_load, key=lambda c: group_load[c] / len(cut_groups[c]))
        for unit in sorted(units, key=lambda u: -sum(t['spread_minutes'] for t in u)):
            work = sum(t['spread_minutes'] for t in unit)
            machine = _pick_machine(cut_groups[cut_group], machine_load, work, layout)
            plan[machine].extend(unit)          # the pair stays adjacent HERE
            machine_load[machine] += work
            group_load[cut_group] += work
    return plan


def _sequence_pairs(tasks, plan, machine_load, group_load, layout, cross_batch, init_cut=None):
    """The pairs rule (S1-S3 default): pair first, exactly as _sequence_mo_aware
    pairs, then put every unit (a pair or a lone table) of the whole day, largest
    first, on whichever cut group is least busy on its busier side: spreading
    load over its spreader minutes, or cutting load over its cutter minutes. The
    user's aim is cutter output, so the cutter backlog (init_cut) counts, not
    only the spreaders'. Pairs from one MO + colour are therefore spread over
    the floor instead of all landing on one cut group. Mirrors
    tools/model.js sequencePairs() line for line."""
    clusters = collections.defaultdict(list)
    for t in tasks:
        clusters[(t['mo'], t['color'])].append(t)

    passes = (True, False) if cross_batch else (True,)
    all_units = []

    # the cluster order sets the tie order of the units
    for group_tasks in sorted(clusters.values(),
                              key=lambda ts: -sum(t['spread_minutes'] for t in ts)):
        ordered = sorted(group_tasks, key=lambda t: (str(t['batch']), -t['spread_minutes']))
        taken = [False] * len(ordered)
        units = []

        for same_batch_pass in passes:
            for i in range(len(ordered)):
                if taken[i]:
                    continue
                for j in range(i + 1, len(ordered)):
                    if taken[j]:
                        continue
                    is_same_batch = ordered[i]['batch'] == ordered[j]['batch']
                    if is_same_batch != same_batch_pass:
                        continue
                    if can_combine(ordered[i], ordered[j], cross_batch=True):
                        units.append([ordered[i], ordered[j]])
                        taken[i] = taken[j] = True
                        break
        units += [[t] for i, t in enumerate(ordered) if not taken[i]]
        all_units += units

    cut_groups = layout['cut_groups']
    cutters = list(cut_groups)
    sp_cap, cut_load = {}, {}
    for c in cutters:
        sp_cap[c] = 0
        for m in cut_groups[c]:
            sp_cap[c] += layout['machine_minutes'][m]
        cut_load[c] = init_cut[c] if init_cut else 0

    for unit in sorted(all_units, key=lambda u: -sum(t['spread_minutes'] for t in u)):
        work = sum(t['spread_minutes'] for t in unit)
        cw = sum(t['cut_minutes'] for t in unit)
        cut_group = min(cutters, key=lambda c: max((group_load[c] + work) / sp_cap[c],
                                                   (cut_load[c] + cw) / layout['cutter_minutes'][c]))
        machine = _pick_machine(cut_groups[cut_group], machine_load, work, layout)
        # _pick_machine can fall outside the chosen group when it is full (Q8), so
        # the loads go to the machine's real group or the next unit would be
        # balanced on a lie. The cut side is credited to that group although
        # FLEXIBLE_CUT lets a few tables be cut by another cutter: an
        # approximation, kept on purpose.
        g = layout['primary_cut'][machine]
        plan[machine].extend(unit)              # the pair stays adjacent HERE
        machine_load[machine] += work
        group_load[g] += work
        cut_load[g] += cw
    return plan


# =====================================================================
# 3. TIME  — run the plan, record blocking, stamp each table's cut-finish
# =====================================================================
def _free_length(lays: list, table_length: float, when: float) -> float:
    """Table length free at `when`.

    Each lay holds its marker length until cutting starts, then gives it back
    linearly as the lay is fed into the cutting machine (G6).
    """
    used = 0.0
    for length, cut_start, cut_end in lays:
        if when >= cut_end:
            continue
        if when <= cut_start or cut_end <= cut_start:
            used += length
        else:
            used += length * (cut_end - when) / (cut_end - cut_start)
    return table_length - used


def _room_at(lays: list, table_length: float, earliest: float, need: float) -> float:
    """When `need` yards of table first come free, at or after `earliest`.

    Free length only rises between lays being added, so it is enough to walk
    the cut start/end boundaries and bisect inside the span that crosses.
    """
    if _free_length(lays, table_length, earliest) >= need:
        return earliest
    marks = sorted(t for _, cs, ce in lays for t in (cs, ce) if t > earliest)
    low = earliest
    for mark in marks:
        if _free_length(lays, table_length, mark) >= need:
            high = mark
            for _ in range(40):
                mid = (low + high) / 2
                if _free_length(lays, table_length, mid) >= need:
                    high = mid
                else:
                    low = mid
            return high
        low = mark
    # A lay longer than the table cannot fit beside anything — wait for a clear
    # table. Markers are ~9 yd against 23 yd of table, so this is a safety net.
    return max([earliest] + [ce for _, _, ce in lays])


# =====================================================================
# 4. LOAD
# =====================================================================
def _loading_events(plan: dict, cross_batch: bool) -> list:
    """Walk each workstation's sequence and combine adjacent tables where the
    rule allows. -> [(cut_end, table, compartments, batches, machine)] in the
    order panels actually arrive at the loading area."""
    events = []
    for machine, seq in plan.items():
        i = 0
        while i < len(seq):
            if not seq[i]['needs_trolleys']:
                i += 1
                continue
            pair = i + 1 < len(seq) and can_combine(seq[i], seq[i + 1], cross_batch)
            if pair:
                comps = combined_compartments(seq[i], seq[i + 1])
                batches = {seq[i]['batch'], seq[i + 1]['batch']}
                when = max(seq[i]['cut_end'], seq[i + 1]['cut_end'])
                table = seq[i]
                i += 2
            else:
                comps = compartments_for(seq[i]['pieces_by_size'])
                batches = {seq[i]['batch']}
                when, table = seq[i]['cut_end'], seq[i]
                i += 1
            events.append((when, table, comps, batches, machine))
    events.sort(key=lambda e: e[0])
    return events


def load_trolleys(plan: dict, scenario: Scenario) -> dict:
    """Fill trolleys. With WIP hold on, a part-filled trolley is parked and may
    be topped up by a later matching table instead of leaving half empty."""
    events = _loading_events(plan, scenario.cross_batch)
    hold = scenario.wip_hold_minutes

    # parked[key] = [[free_compartments, parked_at, {batches on board}], ...]
    parked = collections.defaultdict(list)
    parked_now = lambda: sum(len(v) for v in parked.values())

    compartments_used = trolleys_opened = pieces = 0
    combines = 0
    waits, blocked_by_space = [], 0

    for when, table, comps, batches, machine in events:
        if len(batches) > 1:
            combines += 1

        # Send away anything that has waited its allowance.
        for key in list(parked):
            still_waiting = []
            for trolley in parked[key]:
                if when - trolley[1] <= hold:
                    still_waiting.append(trolley)
                else:
                    waits.append(when - trolley[1])
            parked[key] = still_waiting

        for film, compartment_list in comps.items():
            if not compartment_list:
                continue
            compartments_used += len(compartment_list)
            pieces += sum(compartment_list)

            key = (table['mo'], table['color'], film)
            if not scenario.hold_any_workstation:
                key += (machine,)               # may only return to its own WS

            need = len(compartment_list)

            # (a) top up trolleys already parked and waiting
            for trolley in parked[key]:
                if need == 0:
                    break
                would_carry = trolley[2] | batches
                if len(would_carry) > A.MAX_BATCHES_PER_TROLLEY:
                    continue                    # would put a 3rd batch on board
                take = min(trolley[0], need)
                if take == 0:
                    continue
                trolley[0] -= take
                trolley[2] = would_carry
                need -= take
            parked[key] = [t for t in parked[key] if t[0] > 0]

            # (b) open fresh trolleys for whatever is left
            while need > 0:
                take = min(A.TROLLEY_COMPARTMENTS, need)
                need -= take
                trolleys_opened += 1
                spare = A.TROLLEY_COMPARTMENTS - take
                if spare and hold > 0:
                    if parked_now() < A.TROLLEY_BAYS:
                        parked[key].append([spare, when, set(batches)])
                    else:
                        blocked_by_space += 1

    return {
        'compartments': compartments_used,
        'trolleys': trolleys_opened,
        'pieces': pieces,
        'combines': combines,
        'avg_wait_hours': statistics.mean(waits) / 60 if waits else 0.0,
        'blocked_by_space': blocked_by_space,
    }


# =====================================================================
# RUN
# =====================================================================
def _pool(scenario: Scenario, per_day: dict) -> dict:
    """Pools per-plan-date results into the published aggregate, for
    run_carry()."""
    avg = lambda k: statistics.mean(d[k] for d in per_day.values())
    total_comps = sum(d['compartments'] for d in per_day.values())
    total_trolleys = sum(d['trolleys'] for d in per_day.values())
    total_pieces = sum(d['pieces'] for d in per_day.values())

    return {
        'scenario': scenario.name,
        'settings': {
            'sequencing_mode': scenario.sequencing_mode,
            'max_batches': scenario.max_batches,
            'wip_hold_minutes': scenario.wip_hold_minutes,
            'hold_any_workstation': scenario.hold_any_workstation,
        },
        # utilization is pooled over all days, not a mean of daily percentages
        'utilization_pct': 100 * total_comps / (A.TROLLEY_COMPARTMENTS * total_trolleys),
        'trolleys_per_day': total_trolleys / len(per_day),
        'peak_trolleys_in_a_day': max(d['trolleys'] for d in per_day.values()),
        'compartments_per_day': total_comps / len(per_day),
        # how full the compartments that got OPENED actually are — the number
        # utilization_pct does not carry. utilization_pct counts compartments
        # opened (H6); this is pieces on board vs what those same compartments
        # could hold (COMPARTMENT_CAP each). Pooled, matching utilization_pct's
        # own basis, not a mean of daily percentages.
        'compartment_fill_pct': 100 * total_pieces / (A.COMPARTMENT_CAP * total_comps),
        # what the compartments actually opened could hold, if every one of
        # them were full — the number 750 (ceiling) and 306ish (pieces on
        # board) both need a bridge to reconcile against; this is it.
        'garments_per_trolley_capacity': A.COMPARTMENT_CAP * total_comps / total_trolleys,
        # Option A: pooled (total_pieces / total_trolleys), matching
        # utilization_pct's basis — was avg('pieces_per_trolley'), a mean of
        # 20 daily ratios, which does not equal capacity x fill even once
        # compartment_fill_pct exists (~1% residual). See README Part 8.
        'pieces_per_trolley': total_pieces / total_trolleys,
        'spreading_blocked_pct': avg('spreading_blocked_pct'),
        'cutting_blocked_pct': avg('cutting_blocked_pct'),
        'spreading_makespan_hours': avg('spreading_makespan_hours'),
        'spreading_blocked_minutes': avg('spreading_blocked_minutes'),
        'spreading_overrun_minutes': avg('spreading_overrun_minutes'),
        'machines_over_window': avg('machines_over_window'),
        'avg_wait_hours': avg('avg_wait_hours'),
        'blocked_by_space': sum(d['blocked_by_space'] for d in per_day.values()),
        'per_day': per_day,
    }


# =====================================================================
# CARRY-OVER FLOOR — the published model (user rule, 2026-11-06: no cold
# start, work is always left from the day before). One timeline runs over
# every plan date, in staffed hours only, so work a machine did not finish
# carries into the next shift, and each plan date's Job Sequence is planned on
# its own morning around what every spreader still has committed. Machines run
# at the G2 standard pace (no speed factor). The closed-day cold-start model
# was removed on 2026-11-09. Mirrors tools/model.js
# carryTimeline() / runCarry() line for line. NOT EXECUTED here (no Python).
# =====================================================================
def _staffed_between(spans: list, a: float, b: float) -> float:
    if b <= a:
        return 0.0
    s = 0.0
    for x, y in spans:
        if x >= b:
            break
        s += max(0.0, min(y, b) - max(x, a))
    return s


_CARRY_CACHE: dict = {}


def carry_timeline(days: dict, sequencing_mode: str, layout: dict = None,
                   table_length: float = None,
                   mo_one_group: bool = False) -> dict:
    """Stages 2+3 for the whole run. Depends on the sequencing mode, layout,
    table length and mo_one_group, not on the loading settings, so it is
    cached per `days` object. -> {dates, off, by_date, plan_by_date, metrics_by_date}."""
    layout = LAYOUT if layout is None else layout
    table_length = A.SPREADING_TABLE_LENGTH if table_length is None else table_length
    key = (id(days), sequencing_mode, bool(mo_one_group), json.dumps(layout['cut_groups']), table_length,
           A.CUT_SETUP_MO_COLOR_MINUTES, A.CUT_TRAVEL_MINUTES)
    hit = _CARRY_CACHE.get(key)
    if hit is not None and hit[0] is days:
        return hit[1]

    dates = sorted(days)
    n_days = len(dates)
    off = [(d - dates[0]).days * 1440.0 for d in dates]
    spreaders = layout['spreaders']
    cutters = list(layout['cut_groups'])
    primary_cut = layout['primary_cut']

    # every task of every date, copied (sequence() / the timeline stamp them)
    tot_spread = tot_cut = 0.0
    by_date = {}
    for di, d in enumerate(dates):
        copies = []
        for i, t in enumerate(days[d]):
            c = dict(t, _i=i, date=d, day_idx=di)
            tot_spread += c['spread_minutes']
            tot_cut += c['cut_minutes']
            copies.append(c)
        by_date[d] = copies

    # staffed spans over every plan date, plus synthetic days after the last,
    # sized to the work so the last tables also finish on staffed hours
    sp_cap = sum(layout['machine_minutes'][m] for m in spreaders)
    cu_cap = sum(layout['cutter_minutes'][c] for c in cutters)
    extra = min(3000, math.ceil(2 * max(tot_spread / sp_cap, tot_cut / cu_cap)) + 14)
    offsets = list(off) + [off[n_days - 1] + k * 1440.0 for k in range(1, extra + 1)]

    def repeat(spans):
        return [(x + a, x + b) for x in offsets for a, b in spans]

    sp_spans = {m: repeat(layout['spreader_shift'][m]) for m in spreaders}
    cu_spans = {c: repeat(layout['cutter_shift'][c]) for c in cutters}

    free = {m: 0.0 for m in spreaders}
    lays = {m: [] for m in spreaders}
    cut_free = {c: 0.0 for c in cutters}
    # what each cutter cut last: it carries across plan dates, like cut_free
    last_cut = {c: None for c in cutters}
    plan_by_date = {}

    for di, date in enumerate(dates):
        # the planner sees what each machine still has committed at the day's start
        init = {m: _staffed_between(sp_spans[m], off[di], free[m]) for m in spreaders}
        # and what each cutter still has to cut, in staffed minutes
        init_cut = {c: _staffed_between(cu_spans[c], off[di], cut_free[c]) for c in cutters}
        plan = sequence(by_date[date], sequencing_mode, layout, init, init_cut, mo_one_group)
        plan_by_date[date] = plan
        ptr = {m: 0 for m in spreaders}
        remaining = len(by_date[date])
        while remaining > 0:
            cands = [m for m in spreaders if ptr[m] < len(plan[m])]
            machine = min(cands, key=lambda m: _advance(sp_spans[m], free[m]))
            eff = _advance(sp_spans[machine], free[machine])
            if eff < off[di]:                       # the plan date has not begun
                free[machine] = off[di]
                continue
            task = plan[machine][ptr[machine]]
            ptr[machine] += 1
            remaining -= 1

            lays[machine] = [l for l in lays[machine] if l[2] > eff]
            start = _room_at(lays[machine], table_length, eff, task['marker_length'])
            task['blocked_minutes'] = _staffed_between(sp_spans[machine], eff, start)
            spread_start, spread_end = occupy(sp_spans[machine], start, task['spread_minutes'])
            free[machine] = spread_end

            flex = A.FLEXIBLE_CUT.get(machine, [primary_cut[machine]])
            cutter = min(flex, key=lambda c: cut_free[c])
            task['cut_wait'] = max(0.0, spread_end - cut_free[cutter])
            # Cutter changeover (user rule, 2026-11-09, ESTIMATES): an MO or colour change
            # against the cutter's last cut costs CUT_SETUP_MO_COLOR_MINUTES; moving to a
            # different spreader than its last cut costs CUT_TRAVEL_MINUTES. Both are
            # added on top of the G2 pace (they are walking and cleaning, not machine rate), and
            # tools/lab.js dispatch() is the same rule, added left to right for exact equality.
            # Strings are compared because the Lab's tasks hold String(mo)/String(color).
            lc = last_cut[cutter]
            setup = (A.CUT_SETUP_MO_COLOR_MINUTES
                     if lc is not None and (str(lc[0]) != str(task['mo']) or str(lc[1]) != str(task['color']))
                     else 0)
            travel = A.CUT_TRAVEL_MINUTES if lc is not None and lc[2] != machine else 0
            cut_start, cut_end = occupy(cu_spans[cutter], max(spread_end, cut_free[cutter]),
                                        task['cut_minutes'] + setup + travel)
            cut_free[cutter] = cut_end
            last_cut[cutter] = (task['mo'], task['color'], machine)
            # Q19: the spreading table stays occupied through the changeover and the move
            # (the fabric is still on it until it is cut). The table frees from
            # cut_start + setup + travel on the RAW clock, so a break inside the setup
            # starts the freeing early (capped at cut_end). Mirrored from the Lab, not fixed.
            lays[machine].append((task['marker_length'], min(cut_end, cut_start + setup + travel), cut_end))

            task['cut_setup_minutes'] = setup
            task['cut_travel_minutes'] = travel
            task['machine'] = machine
            task['cutter'] = cutter
            task['spread_start'] = spread_start
            task['spread_end'] = spread_end
            task['cut_start'] = cut_start
            task['cut_end'] = cut_end

    # per-plan-date idle-time figures, from the tables that date planned
    metrics_by_date = {}
    for di, date in enumerate(dates):
        ts = by_date[date]
        s_busy = s_blocked = c_busy = c_wait = last = overrun = 0.0
        over = set()
        for t in ts:
            s_busy += t['spread_minutes']
            s_blocked += t['blocked_minutes']
            c_busy += t['cut_minutes']
            c_wait += t['cut_wait']
            last = max(last, t['spread_end'])
            shift = layout['spreader_shift'][t['machine']]
            win_end = off[di] + shift[-1][1]
            if t['spread_end'] > win_end:
                over.add(t['machine'])
                overrun += _staffed_between(sp_spans[t['machine']], max(t['spread_start'], win_end), t['spread_end'])
        metrics_by_date[date] = {
            'spreading_blocked_pct': 100 * s_blocked / (s_busy + s_blocked) if (s_busy + s_blocked) else 0.0,
            'cutting_blocked_pct': 100 * c_wait / (c_busy + c_wait) if (c_busy + c_wait) else 0.0,
            'spreading_makespan_hours': (last - off[di]) / 60 if ts else 0.0,
            'spreading_blocked_minutes': s_blocked,
            'spreading_overrun_minutes': overrun,
            'machines_over_window': len(over),
        }

    sim = {'dates': dates, 'off': off, 'by_date': by_date,
           'plan_by_date': plan_by_date, 'metrics_by_date': metrics_by_date}
    _CARRY_CACHE[key] = (days, sim)
    return sim


def run_carry(scenario: Scenario, days: dict, layout: dict = None,
              table_length: float = None) -> dict:
    """The published run: one scenario over every plan date on the carry-over floor."""
    sim = carry_timeline(days, scenario.sequencing_mode, layout, table_length,
                         scenario.mo_one_group)
    per_day = {}
    for date in sim['dates']:
        loading = load_trolleys(sim['plan_by_date'][date], scenario)
        comps, trolleys = loading['compartments'], loading['trolleys']
        mt = sim['metrics_by_date'][date]
        per_day[str(date)] = {
            'tasks': len(sim['by_date'][date]),
            'combines': loading['combines'],
            'compartments': comps,
            'trolleys': trolleys,
            'pieces': loading['pieces'],
            'trolley_utilization_pct': 100 * comps / (A.TROLLEY_COMPARTMENTS * trolleys) if trolleys else 0.0,
            'compartment_fill_pct': 100 * loading['pieces'] / (A.COMPARTMENT_CAP * comps) if comps else 0.0,
            'pieces_per_trolley': loading['pieces'] / trolleys if trolleys else 0.0,
            'spreading_blocked_pct': mt['spreading_blocked_pct'],
            'cutting_blocked_pct': mt['cutting_blocked_pct'],
            'spreading_makespan_hours': mt['spreading_makespan_hours'],
            'spreading_blocked_minutes': mt['spreading_blocked_minutes'],
            'spreading_overrun_minutes': mt['spreading_overrun_minutes'],
            'machines_over_window': mt['machines_over_window'],
            'avg_wait_hours': loading['avg_wait_hours'],
            'blocked_by_space': loading['blocked_by_space'],
        }
    return _pool(scenario, per_day)


# =====================================================================
# FLEET ARITHMETIC — no simulation, just multiplication. Kept here so the
# one place that defines "how many trolleys do we need" is in the model.
# =====================================================================
def fleet_required(trolleys_per_day: float, cycle_days: float) -> float:
    """A trolley dispatched today is unavailable for `cycle_days`. So the fleet
    has to cover that many days of dispatches at once."""
    return trolleys_per_day * cycle_days


def longest_sustainable_cycle(trolleys_per_day: float, fleet: int = None) -> float:
    """How slow the round trip can get before the fleet runs dry."""
    return (fleet or A.FLEET_SIZE) / trolleys_per_day
