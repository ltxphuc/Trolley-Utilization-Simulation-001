"""
THE TRACE
=========
The headline numbers are pooled over every plan date. This module exports the
detail underneath them — one plan date at a time, table by table — so the
dashboard's Simulation tab can draw the day that produced them:

    the Job Sequence as a Gantt          (which table, which machine, when)
    the same day loaded onto trolleys    (which compartment, which film)

Two things are exported per day, once for each sequencing rule, once for each
(table length, cutter count) variant:

    order  {machine: [task index, ...]}   the queue, in spreading order.
                                          Adjacency lives here — it is what
                                          change 1 creates and what the
                                          combine rule can act on. This is
                                          PER VARIANT, not per mode: a
                                          different cutter count re-partitions
                                          the cut groups, which changes
                                          _pick_machine's candidate list and
                                          therefore the sequence itself — see
                                          SIM_VARIANTS below.
    time   {'ss': [...], 'se': [...], 'cs': [...], 'ce': [...], 'cut': [...]}
           parallel arrays, indexed by task index. cut is an index into that
           variant's own 'cutters' list.

The trolley maths is NOT exported. The dashboard recomputes stage 4 in the
browser, because the Net_Rate scheme has to be switchable and pre-computing
every scheme would multiply the payload. `expected` is the guard on that port:
it carries the utilization Python gets for the same day and settings, and the
page compares its own answer against it in view of the reader. It is only
computed for `full` variants — see SIM_VARIANTS.
"""
from __future__ import annotations

import datetime

import assumptions as A
import scenarios as S
from model import Scenario, carry_timeline, load_trolleys, machine_layout

# label == the sequencing_mode value itself, now that Scenario carries a
# 3-way mode instead of a boolean — kept as pairs (not a flat tuple) so the
# call sites below read the same as before this change.
MODES = (('today', 'today'), ('same_batch', 'same_batch'), ('cross_batch', 'cross_batch'))

# The spreading table and cutter count together decide the sequence AND the
# timeline (Phase 2's cutter-count refactor made the sequence depend on the
# layout, not just table length). Shipping every (length, cutter) combination
# at full fidelity does not fit the page's size budget (plan §6.2), so only
# the cutter axis at today's table length ships in full; the two extra table
# lengths ship as aggregates only — 'blocked'/'groups', no 'time'/'order'/
# 'expected'. The Gantt therefore does not redraw at 24 m / 27 m; see
# README.md Part 7 §7.
SIM_VARIANTS = (
    (A.SPREADING_TABLE_LENGTH_M, 5, True),    # 21.2/5 — the baseline
    (A.SPREADING_TABLE_LENGTH_M, 6, False),   # aggregate only — 2026-09-08:
                                               # 3 sequencing modes x 4 full
                                               # cutter counts blew the page's
                                               # size budget in every month,
                                               # even after WEBSITE_MONTHS
                                               # narrowed the date range (a
                                               # month's file size depends on
                                               # its own date count, not on
                                               # how many other months exist).
                                               # 5 and 7 stay full so every
                                               # sequencing mode is still
                                               # fully chartable at two
                                               # cutter counts; 6 and 8 still
                                               # report their numbers in the
                                               # idle-time comparison, same
                                               # treatment as 24/27 m below.
    (A.SPREADING_TABLE_LENGTH_M, 7, True),
    (A.SPREADING_TABLE_LENGTH_M, 8, False),
    (24.0, 5, False),                          # aggregate only — see plan §6.3
    (27.0, 5, False),
)
BASELINE_VARIANT = (A.SPREADING_TABLE_LENGTH_M, 5)


def _metres_key(metres: float) -> str:
    """'21.2' — the general format, trailing zeros stripped."""
    return f'{metres:g}'


def _variant_key(metres: float, cutters: int) -> str:
    """'21.2/5' — the key the dashboard looks a variant up by."""
    return f'{_metres_key(metres)}/{cutters}'


# Order of the fields in a task record. The dashboard reads by index, so this
# tuple and the JS `TASK_FIELDS` constant must stay in step. Field 14 used to
# be batch_first_offset_minutes — dropped, never read by the page's
# tasksFor() — so is_batch_last and spread_done_minutes each shifted down one.
TASK_FIELDS = (
    'table_no', 'mo', 'style', 'color', 'batch', 'lot',
    'layers', 'marker_length', 'spread_minutes', 'cut_minutes',
    'pieces_by_size', 'needs_trolleys',
    'has_pattern', 'has_fabric', 'is_batch_last',
    'spread_done_minutes',
)


def _minutes_into_day(when, day) -> float | None:
    """Pull Date (actual finished spreading) as minutes from midnight of the
    plan date. Negative means it finished before the day it was planned for;
    over 1440 means it ran late, which is the common case."""
    if when is None:
        return None
    midnight = datetime.datetime.combine(day, datetime.time.min)
    return round((when - midnight).total_seconds() / 60, 1)


def _record(task: dict, day) -> list:
    return [
        task['table_no'], task['mo'], task['style'], task['color'],
        task['batch'], task['lot'],
        task['layers'], round(task['marker_length'], 2),
        round(task['spread_minutes'], 1), round(task['cut_minutes'], 1),
        # NOT sorted. compartments_for() walks this dict in order, so the order
        # decides which film width opens a trolley first — which matters once
        # the 52 trolley bays (H7) are full. Sorting here silently changes the
        # answer on busy days.
        dict(task['pieces_by_size']),
        int(task['needs_trolleys']),
        int(task['has_pattern']), int(task['has_fabric']),
        int(task['is_batch_last']),
        _minutes_into_day(task['spread_done_at'], day),
    ]


def _expected(plan: dict, sequencing_mode: str) -> dict:
    """What Python gets for this day at every setting the tab can reach.

    The sequence and the timeline depend only on `sequencing_mode`, so the
    plan is built once and only the loading stage is re-run.
    """
    out = {}
    for max_batches in S.SWEEP_MAX_BATCHES:
        for hold in S.SWEEP_HOLD_MINUTES:
            for any_ws in S.SWEEP_ANY_WORKSTATION:
                key = S.sweep_key(sequencing_mode, max_batches, hold, any_ws)
                if key in out:
                    continue
                loading = load_trolleys(plan, Scenario(
                    name=key,
                    sequencing_mode=sequencing_mode,
                    max_batches=max_batches,
                    wip_hold_minutes=hold,
                    hold_any_workstation=any_ws,
                ))
                comps, trolleys = loading['compartments'], loading['trolleys']
                out[key] = [
                    round(100 * comps / (A.TROLLEY_COMPARTMENTS * trolleys), 2) if trolleys else 0.0,
                    trolleys,
                    comps,
                    loading['combines'],
                ]
    return out


def _groups_block(copies: list, layout: dict, spreading_agg: dict) -> dict:
    """Per-cut-group idle-time attribution, exactly as idle_variants.py's
    measure() does it (idle_variants.py:109-113): blocked_minutes and
    spread_minutes are credited to the SPREADING machine's own group; cutter
    busy minutes go to the cutter that actually ran the task, which under F8
    need not be its own group's. Reused here rather than re-derived so the
    dashboard's idle-time comparison (a later phase) and README Part 7 agree
    by construction.
    """
    primary_cut = layout['primary_cut']
    cut_groups = layout['cut_groups']
    cutter_busy = {c: 0.0 for c in cut_groups}
    blocked_by_group = {c: 0.0 for c in cut_groups}
    spread_by_group = {c: 0.0 for c in cut_groups}
    for t in copies:
        group = primary_cut[t['machine']]
        cutter_busy[t['cutter']] += t['cut_minutes']
        blocked_by_group[group] += t['blocked_minutes']
        spread_by_group[group] += t['spread_minutes']

    groups = {
        c: [round(cutter_busy[c], 1), round(blocked_by_group[c], 1),
            round(spread_by_group[c], 1), len(cut_groups[c])]
        for c in cut_groups
    }
    return {'groups': groups, 'over': [spreading_agg['machines_over'], len(layout['spreaders'])]}


def build_trace(days: dict, skipped: dict | None = None, all_days: dict | None = None) -> dict:
    """-> the whole payload the Simulation tab reads, for the plan dates in
    `days` only. Called once per calendar month by run.py, so the caller can
    free one month's trace before building the next — see run.py.

    `all_days` is every in-scope plan date. The published model has no cold
    start (model.carry_timeline): a date's tables are timed on one timeline with
    the dates before it, so the simulation runs over all of them and only this
    file's dates are kept. Times are shipped relative to each date's own 07:15."""
    skipped = skipped or {}
    all_days = days if all_days is None else all_days
    out = {
        'fields': list(TASK_FIELDS),
        'dates': [str(d) for d in sorted(days)],
        'days': {},
    }
    # the minutes the model actually ran (the G2 time of each table)
    sim0 = carry_timeline(all_days, 'today')

    for date in sorted(days):
        off = sim0['off'][sim0['dates'].index(date)]
        day = {
            'tasks': [_record(t, date) for t in sim0['by_date'][date]],
            'skipped': skipped.get(date, 0),
            'seq': {},
        }

        for mode, seq_mode in MODES:
            by_variant = {}

            for metres, cutters, full in SIM_VARIANTS:
                layout = machine_layout(A.CUT_GROUPS_BY_CUTTER_COUNT[cutters])

                # one carry-over run per (mode, layout, table length), cached
                # across dates and months; its task copies carry the stamps and `_i`
                sim = carry_timeline(all_days, seq_mode, layout, metres * A.YARDS_PER_METRE)
                copies = sim['by_date'][date]
                plan = sim['plan_by_date'][date]
                spreading_agg = {'machines_over': sim['metrics_by_date'][date]['machines_over_window']}

                variant = {'blocked': round(sum(t['blocked_minutes'] for t in copies), 1)}
                variant.update(_groups_block(copies, layout, spreading_agg))

                if full:
                    cutters_list = list(layout['cut_groups'])
                    cutter_index = {c: i for i, c in enumerate(cutters_list)}
                    n = len(copies)
                    ss = [None] * n
                    se = [None] * n
                    cs = [None] * n
                    ce = [None] * n
                    cut = [None] * n

                    # order[machine] MUST live inside this per-variant dict, not
                    # at mode level — a different cutter count re-partitions the
                    # cut groups, which changes _pick_machine's candidate list and
                    # therefore the sequence. Leaving it at mode level (true only
                    # when table length was the sole axis) would silently serve
                    # the wrong machine's queue for every non-baseline variant.
                    order = {}
                    for machine, queue in plan.items():
                        if not queue:
                            continue
                        order[machine] = [t['_i'] for t in queue]
                        for t in queue:
                            i = t['_i']
                            ss[i] = round(t['spread_start'] - off, 1)
                            se[i] = round(t['spread_end'] - off, 1)
                            cs[i] = round(t['cut_start'] - off, 1)
                            # cut_end is NOT rounded. The dashboard sorts loading
                            # events by it and measures the WIP hold against it,
                            # so rounding can reorder two near-simultaneous tables
                            # and cost a trolley. The rest is for drawing only.
                            ce[i] = t['cut_end'] - off
                            cut[i] = cutter_index[t['cutter']]

                    variant['order'] = order
                    variant['time'] = {'ss': ss, 'se': se, 'cs': cs, 'ce': ce, 'cut': cut}
                    variant['cutters'] = cutters_list
                    variant['expected'] = _expected(plan, seq_mode)

                by_variant[_variant_key(metres, cutters)] = variant

            day['seq'][mode] = {'table': by_variant}

        out['days'][str(date)] = day

    return out
