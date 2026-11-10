"""
IDLE-TIME VARIANTS
==================
Regenerates the tables in `README.md` Part 7 — the per-cut-group breakdown in
section 3, the options list in section 4, and the cutting-machine-count ladder
in section 4b — and prints them as markdown, ready to paste. The bold on the
emphasised cells is emitted too, so a paste does not need it re-applied by hand.

They exist here because they used to come from throwaway scripts, so the two
numbers the idle-time case actually turns on could not be reproduced from the
repo. Everything below reads `model.py` and `assumptions.py` directly; nothing
is re-derived by hand.

    python idle_variants.py

A Node mirror, `tools/idle_variants.js`, produces the same tables without
Python (mirror, do not improve). As of 2026-09-08 the Node mirror has run and
`idle_variants.py` has not — see `README.md` Part 8 §5 #4.

Measured on the S0 sequencing (today's planner) across every plan date in the
data, so it lines up with the rest of the model. This script only prints —
it writes nothing to `out/`.

Since 2026-11-09 it measures the published carry-over model (carry_timeline():
one running timeline over all plan dates, machines at the G2 standard pace,
blocked minutes = the staffed wait for table length). The cold-start
model it used to measure (every plan date a closed day,
raw-clock wait) was removed, so those numbers cannot be re-run: they are kept
as OLD below from the saved `npm run idle` output of 2026-11-09 and printed
beside the new ones. The two are NOT like for like (different floor
model). Mirrors tools/idle_variants.js; NOT EXECUTED here (no Python).
"""
import contextlib

import assumptions as A
import model

SEQUENCING_MODE = 'today'   # S0 — today's planner. README.md Part 7 quotes S0 throughout.

# A cut group's row is bolded once its cutter is saturated — that is the point
# section 3 makes, and at 90% it picks out 24MC4 and 24MC5 and nothing else
# (the next busiest is 24MC2 at 82%). Emitted as markdown so the printed table
# really is ready to paste, emphasis and all.
SATURATED_CUTTER_PCT = 90


# =====================================================================
# The routing what-ifs
#
# These are WHAT-IFS FOR THIS ANALYSIS ONLY. Rule F8 as written gives two
# spreading machines a second cutting machine; the variants below widen that
# and are switched in around a single call, then switched back. Nothing else
# in the repo runs with them.
# =====================================================================
FLEX_TODAY = dict(A.FLEXIBLE_CUT)

# Rule F8's own pattern, extended: the LAST spreading machine of a cut group may
# also be served by the NEXT group's cutter. F8 already does exactly that for
# 24-03 (last of 24MC1 -> 24MC2) and 24-05 (last of 24MC2 -> 24MC3). Applying
# the same shape to the two saturated groups gives 24-10 (last of 24MC4) a call
# on 24MC5, and 24-13 (last of 24MC5) a call on 24MC1 — the numbering wraps,
# because there is no 24MC6.
#
# A previous version of the idle-time write-up quoted a "24-10 and 24-13 borrow a
# neighbour" row but never recorded which cutter they borrowed, so its figures
# cannot be checked. These are the ones that stand.
FLEX_NEIGHBOUR = dict(FLEX_TODAY)
FLEX_NEIGHBOUR['24-10'] = ['24MC4', '24MC5']
FLEX_NEIGHBOUR['24-13'] = ['24MC5', '24MC1']

# Any cutting machine may serve any spreading machine.
FLEX_ANY = {m: list(A.CUT_GROUPS) for m in model.SPREADERS}

# The cutting-machine-count ladder (README Part 7 §4 recommendation 4 — "a
# sixth cutting machine, only if volume grows"). assumptions.py carries the
# 5/6/7/8-cutter partitions; §4b below measures each. This is the idle-time
# half of table T-C (README Part 8 §4) — the trolley half is tools/tc_table.js.
CUTTER_LADDER = A.SIM_CUTTER_COUNTS

# HISTORICAL cold-start results (closed-day model, full G2 speed, raw-clock
# blocked wait), from the `npm run idle` output saved on 2026-11-09 before the
# cold start was removed. Not re-runnable.
OLD = {
    'sec2': {'work': 5273, 'blocked': 1563, 'over': 16, 'last_cut': '21:15'},
    'sec3': {
        '24MC1': {'busy': '43%', 'lost': 237, 'did': 1413, 'ratio': '17%'},
        '24MC2': {'busy': '68%', 'lost': 138, 'did': 776, 'ratio': '18%'},
        '24MC3': {'busy': '66%', 'lost': 213, 'did': 775, 'ratio': '28%'},
        '24MC4': {'busy': '81%', 'lost': 484, 'did': 1155, 'ratio': '42%'},
        '24MC5': {'busy': '81%', 'lost': 491, 'did': 1155, 'ratio': '43%'},
    },
    # blocked/day, over window %, in the order of section_4()'s variants
    'sec4': [(1563, 16), (1452, 12), (1373, 10), (1104, 9), (1006, 7), (953, 6), (559, 3)],
    'sec4b': {5: (1563, 16, '21:15'), 6: (900, 4, '20:00'), 7: (825, 5, '19:59'), 8: (724, 4, '19:52')},
}


@contextlib.contextmanager
def routing(flexible_cut):
    """Run the block with a different F8 routing, then put F8 back.

    `model.carry_timeline` reads `A.FLEXIBLE_CUT` at call time, so swapping the
    module attribute is enough. PRIMARY_CUT is built from CUT_GROUPS and does
    not move. carry_timeline's cache key does NOT include the routing, so every
    measurement passes it a fresh shallow copy of `days` (a new cache key) or it
    would return the first routing's result for all of them.
    """
    original = A.FLEXIBLE_CUT
    A.FLEXIBLE_CUT = flexible_cut
    try:
        yield
    finally:
        A.FLEXIBLE_CUT = original


# =====================================================================
# One measurement: a table length and a routing, over every plan date
# =====================================================================
def measure(days: dict, metres: float, flexible_cut: dict) -> dict:
    """-> per-day averages plus the per-cut-group breakdown.

    Blocked and spreading minutes are attributed to the cut group the SPREADING
    machine belongs to — those are the machines named in the "Spreaders" column.
    Cutter-busy minutes are attributed to the cutter that actually ran the
    table, which under a flexible routing need not be its own group's.
    """
    groups = list(A.CUT_GROUPS)
    cutter_busy = {c: 0.0 for c in groups}
    blocked_by_group = {c: 0.0 for c in groups}
    spread_by_group = {c: 0.0 for c in groups}
    work = blocked = last_cut = 0.0
    machines_over = machine_days = 0

    with routing(flexible_cut):
        # fresh copy of `days`: carry_timeline's cache key ignores the routing
        sim = model.carry_timeline(dict(days), SEQUENCING_MODE, None,
                                   metres * A.YARDS_PER_METRE)
        for di, date in enumerate(sim['dates']):
            tasks = sim['by_date'][date]
            mt = sim['metrics_by_date'][date]

            work += sum(t['spread_minutes'] for t in tasks)
            blocked += mt['spreading_blocked_minutes']
            machines_over += mt['machines_over_window']
            machine_days += len(model.SPREADERS)
            last_cut += max(t['cut_end'] - sim['off'][di] for t in tasks)

            for t in tasks:
                group = model.PRIMARY_CUT[t['machine']]
                cutter_busy[t['cutter']] += t['cut_minutes']
                blocked_by_group[group] += t['blocked_minutes']
                spread_by_group[group] += t['spread_minutes']

    n = len(days)
    return {
        'days': n,
        'work': work / n,
        'blocked': blocked / n,
        'over_pct': 100 * machines_over / machine_days,
        'last_cut': last_cut / n,
        'cutter_busy': {c: v / n for c, v in cutter_busy.items()},
        'blocked_by_group': {c: v / n for c, v in blocked_by_group.items()},
        'spread_by_group': {c: v / n for c, v in spread_by_group.items()},
    }


def measure_cutters(days: dict, cutters: int) -> dict:
    """Blocked minutes and over-window share at one cutting-machine count.

    S0 sequencing, today's table length, rule F8 routing as written — ONLY the
    cutter count changes. Threads the layout through carry_timeline();
    measure() above uses the 5-cutter default and is left untouched.
    """
    layout = model.machine_layout(A.CUT_GROUPS_BY_CUTTER_COUNT[cutters])
    yards = A.SPREADING_TABLE_LENGTH_M * A.YARDS_PER_METRE
    blocked = last_cut = 0.0
    machines_over = machine_days = 0
    sim = model.carry_timeline(dict(days), SEQUENCING_MODE, layout, yards)
    for di, date in enumerate(sim['dates']):
        tasks = sim['by_date'][date]
        mt = sim['metrics_by_date'][date]
        blocked += mt['spreading_blocked_minutes']
        machines_over += mt['machines_over_window']
        machine_days += len(layout['spreaders'])
        last_cut += max(t['cut_end'] - sim['off'][di] for t in tasks)
    n = len(days)
    return {
        'cutters': cutters,
        'blocked': blocked / n,
        'over_pct': 100 * machines_over / machine_days,
        'last_cut': last_cut / n,
    }


def bold(cell: str) -> str:
    return '**%s**' % cell


def clock(minutes_from_shift_start: float) -> str:
    """The model's clock starts at 07:15, the floor's at midnight.

    Round to the whole minute BEFORE splitting, so a value like 1419.7 carries
    into the hour instead of printing 23:60. `dashboard.py`'s `hhmm` still
    rounds after the split and has the same latent bug; it is left alone on
    purpose, so the two are only out of step on inputs neither one sees today.
    """
    absolute = round(minutes_from_shift_start + A.SHIFT_START_MINUTE) % 1440
    return '%02d:%02d' % (absolute // 60, absolute % 60)


# =====================================================================
# The two tables
# =====================================================================
def section_2(base: dict):
    o = OLD['sec2']
    print('## 2. What it costs\n')
    print('| | Per day, across %d spreading machines (carry-over) '
          '| Cold start (HISTORICAL) |' % len(model.SPREADERS))
    print('|---|---|---|')
    print('| Actual spreading work | %s min | %s min |'
          % (f'{base["work"]:,.0f}', f'{o["work"]:,.0f}'))
    print('| Lost to blocking | **%s min** — %.0f machine-hours | %s min — %.0f machine-hours |'
          % (f'{base["blocked"]:,.0f}', base['blocked'] / 60, f'{o["blocked"]:,.0f}', o['blocked'] / 60))
    print('| Machine-days over their staffed window | **%.0f%%** | %d%% |' % (base['over_pct'], o['over']))
    print('| Last cut of the day finishes | %s | %s |' % (clock(base['last_cut']), o['last_cut']))


def section_3(base: dict):
    print('\n## 3. Where it concentrates — and why\n')
    print('| Cut group | Spreaders | Cutter busy | Blocked / day | Spreading / day | Blocked / work '
          '| Cold start (HISTORICAL): busy, blocked, spreading, ratio |')
    print('|---|---|---|---|---|---|---|')
    for group, spreaders in A.CUT_GROUPS.items():
        old = OLD['sec3'][group]
        busy = 100 * base['cutter_busy'][group] / model.CUTTER_MINUTES[group]
        lost = base['blocked_by_group'][group]
        did = base['spread_by_group'][group]
        nights = ' *(runs nights)*' if group in A.NIGHT_SHIFT_CUTTERS else ''
        # the *(runs nights)* aside sits outside the bold, or the italics nest
        b = bold if busy >= SATURATED_CUTTER_PCT else str
        print('| %s | %s | %s%s | %s | %s | %s | %s, %s min, %s min, %s |'
              % (b(group), b('%d' % len(spreaders)), b('%.0f%%' % busy), nights,
                 b(f'{lost:,.0f} min'), b(f'{did:,.0f} min'),
                 b('%.0f%%' % (100 * lost / did)),
                 old['busy'], f'{old["lost"]:,}', f'{old["did"]:,}', old['ratio']))


def section_4(days: dict):
    metres = A.SPREADING_TABLE_LENGTH_M
    # The last column is the emphasis the document gives the row: the two
    # recommendations carry bold on their figures as well as their label.
    # It is an editorial choice, so it is stated here rather than derived.
    variants = [
        ('**Today** — %.1f m' % metres,           metres, FLEX_TODAY,     '—',                False),
        ('24-10 and 24-13 borrow a neighbour',    metres, FLEX_NEIGHBOUR, 'a routing rule',   False),
        ('**Any cutter may serve any spreader**', metres, FLEX_ANY,       'a routing rule',   True),
        ('Table to 24 m',                         24,     FLEX_TODAY,     'floor space',      False),
        ('Table to 24 m + neighbour routing',     24,     FLEX_NEIGHBOUR, 'both',             False),
        ('**Table to 24 m + any cutter**',        24,     FLEX_ANY,       'both',             True),
        ('Table to 27 m + any cutter',            27,     FLEX_ANY,       'both, more space', False),
    ]
    print('\n## 4. What fixes it\n')
    print('| Change | Blocked/day | Over window | Cost '
          '| Cold start (HISTORICAL): blocked/day, over window |')
    print('|---|---|---|---|---|')
    for i, (label, length, flex, cost, emphasised) in enumerate(variants):
        r = measure(days, length, flex)
        b = bold if emphasised else str
        print('| %s | %s | %s | %s | %s, %d%% |'
              % (label, b(f'{r["blocked"]:,.0f}'), b('%.0f%%' % r['over_pct']), cost,
                 f'{OLD["sec4"][i][0]:,}', OLD['sec4'][i][1]))


def section_4b(days: dict):
    print('\n## 4b. The cutting-machine-count ladder\n')
    print('Rule F2 fixes **5** cutting machines against the 13 spreaders today; '
          'Part 7 §4 recommendation 4 names a sixth as the "only if volume '
          'grows" option. S0 sequencing, %.1f m table, F8 routing as written — '
          'only the cutter count moves. `24MC1` keeps 24-01/02/03 at every '
          'count, so the night shift is unchanged throughout; only the ten '
          'day-only spreaders re-partition.\n' % A.SPREADING_TABLE_LENGTH_M)
    print('| Cutters | Spreaders/cutter | Blocked/day | Over window | Last cut '
          '| Cold start (HISTORICAL): blocked/day, over window, last cut |')
    print('|---|---|---|---|---|---|')
    for n in CUTTER_LADDER:
        r = measure_cutters(days, n)
        old = OLD['sec4b'][n]
        print('| %d | %.2f | %s min | %.0f%% | %s | %s min, %d%%, %s |'
              % (n, len(model.SPREADERS) / n, f'{r["blocked"]:,.0f}',
                 r['over_pct'], clock(r['last_cut']), f'{old[0]:,}', old[1], old[2]))
    print('\nThe trolley-number half of this ladder is table T-C '
          '(`tools/tc_table.js`, README Part 8 §4): the cutter count moves '
          'trolley utilization by ~1 point on S0 and not at all on S1–S3.')


def main():
    days = model.load_days()
    base = measure(days, A.SPREADING_TABLE_LENGTH_M, FLEX_TODAY)
    print('# README.md Part 7 — regenerated (carry-over model) from %d plan dates, %d tables, S0 sequencing\n'
          % (base['days'], sum(len(t) for t in days.values())))
    section_2(base)
    section_3(base)
    section_4(days)
    section_4b(days)


if __name__ == '__main__':
    main()
