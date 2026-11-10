"""
RUN EVERYTHING
==============
    python run.py

Reads data/planppc.xlsx, runs every scenario, and writes into out/:

    dashboard.html   <- open this. Sliders, live numbers.
    results.xlsx     <- every scenario and every plan date, as a spreadsheet
    results.json     <- the same numbers, for anything that wants to read them
    sweep.json       <- what the dashboard's sliders read from

Nothing here decides anything. Every assumption is in assumptions.py.
"""
import datetime
import json
import os
import shutil
import time

import assumptions as A
import model as M
import scenarios as S
from dashboard import build_dashboard
import daytrace
from daytrace import build_trace
# run_carry is the published model (carry-over floor, no cold start).
from model import fleet_required, load_days, longest_sustainable_cycle, run_carry

OUT = 'out'


def compute_slip(days: dict) -> dict:
    """How far the floor ran behind the plan, over every plan date at once.

    Mirrors the test the dashboard's own SLIP const applies to the trace's
    spread_done_minutes field (dashboard.py), computed here straight from
    spread_done_at so it covers all plan dates without needing every month's
    trace loaded into memory at the same time (the whole point of building
    one month's trace at a time in main(), below)."""
    dated = late = very_late = 0
    for date, tasks in days.items():
        midnight = datetime.datetime.combine(date, datetime.time.min)
        for t in tasks:
            done = t['spread_done_at']
            if done is None:
                continue
            dated += 1
            minutes = (done - midnight).total_seconds() / 60
            if minutes > 1440:
                late += 1
            if minutes > 2 * 1440:
                very_late += 1
    return {
        'dated': dated, 'late': late, 'veryLate': very_late,
        'latePct': round(100 * late / dated) if dated else 0,
        'veryLatePct': round(100 * very_late / dated) if dated else 0,
    }


def summarise(result: dict) -> dict:
    """Strip the per-day detail and add the fleet arithmetic."""
    per_day = result.pop('per_day')
    tpd = result['trolleys_per_day']
    result['fleet_required_allowed_cycle'] = fleet_required(tpd, A.CYCLE_DAYS_ALLOWED)
    result['fleet_required_estimated_cycle'] = fleet_required(tpd, A.CYCLE_DAYS_ESTIMATED)
    result['fleet_gap_estimated_cycle'] = A.FLEET_SIZE - result['fleet_required_estimated_cycle']
    result['longest_sustainable_cycle_days'] = longest_sustainable_cycle(tpd)
    result['fits_in_fleet'] = result['fleet_required_estimated_cycle'] <= A.FLEET_SIZE
    return per_day


def main():
    os.makedirs(OUT, exist_ok=True)
    started = time.time()

    print('Reading', A.DATA_FILE)
    all_days, all_skipped = load_days(with_stats=True)
    print(f'  {len(all_days)} plan dates in the file, '
          f'{sum(len(v) for v in all_days.values())} tables')

    # WEBSITE SCOPE — user decision, 2026-09-08 (assumptions.py's matching
    # comment has the full reasoning). Everything from here on — the headline
    # table, the sweep, results.json/sweep.json, and every month file — sees
    # only these months. load_days() itself, above, still read the whole file;
    # this is the one place the scope actually narrows.
    days = {d: t for d, t in all_days.items() if d.strftime('%Y-%m') in A.WEBSITE_MONTHS}
    skipped = {d: n for d, n in all_skipped.items() if d.strftime('%Y-%m') in A.WEBSITE_MONTHS}
    print(f'  scoped to {A.WEBSITE_MONTHS}: {len(days)} plan dates, '
          f'{sum(len(v) for v in days.values())} tables, '
          f'{sum(len(v) for v in days.values()) / len(days):.0f} per day\n')

    # ------------------------------------------------ headline scenarios
    print('HEADLINE SCENARIOS')
    print(f"{'':<32}{'util':>8}{'trolleys/day':>14}{'peak':>7}"
          f"{'fleet @' + str(A.CYCLE_DAYS_ESTIMATED) + 'd':>12}{'vs fleet':>11}")
    headline, headline_days = {}, {}
    for scenario in S.HEADLINE:
        r = run_carry(scenario, days)
        headline_days[scenario.name] = summarise(r)
        headline[scenario.name] = r
        gap = r['fleet_gap_estimated_cycle']
        print(f"{scenario.name:<32}{r['utilization_pct']:>7.1f}%"
              f"{r['trolleys_per_day']:>14.0f}{r['peak_trolleys_in_a_day']:>7}"
              f"{r['fleet_required_estimated_cycle']:>12,.0f}"
              f"{gap:>+11,.0f}{'' if gap >= 0 else '  SHORT'}")

    base, best = S.HEADLINE[0].name, S.HEADLINE[-1].name
    print(f"\n  fleet = {A.FLEET_SIZE:,} trolleys · "
          f"cycle {A.CYCLE_DAYS_ALLOWED}d allowed, ~{A.CYCLE_DAYS_ESTIMATED}d estimated")
    print(f"  {base} sustains a "
          f"{headline[base]['longest_sustainable_cycle_days']:.1f}-day cycle; "
          f"{best} sustains "
          f"{headline[best]['longest_sustainable_cycle_days']:.1f} days.\n")

    # ------------------------------------------- same WS vs any WS
    print('WIP HOLD — WHERE MAY A PARKED TROLLEY GO?')
    print(f"{'':<32}{'util':>8}{'trolleys/day':>14}{'avg wait':>11}")
    variants = {}
    for scenario in S.HOLD_VARIANTS:
        r = run_carry(scenario, days)
        summarise(r)
        variants[scenario.name] = r
        print(f"{scenario.name:<32}{r['utilization_pct']:>7.1f}%"
              f"{r['trolleys_per_day']:>14.0f}{r['avg_wait_hours']:>10.1f}h")
    print()

    # ------------------------------------------------------- the sweep
    combos = S.sweep_scenarios()
    print(f'SWEEP — {len(combos)} combinations for the dashboard sliders')
    sweep = {}
    for i, (key, scenario) in enumerate(combos.items(), 1):
        r = run_carry(scenario, days)
        summarise(r)
        sweep[key] = {
            'utilization_pct': round(r['utilization_pct'], 2),
            'trolleys_per_day': round(r['trolleys_per_day'], 1),
            'peak': r['peak_trolleys_in_a_day'],
            'pieces_per_trolley': round(r['pieces_per_trolley'], 0),
            'compartment_fill_pct': round(r['compartment_fill_pct'], 1),
            'garments_per_trolley_capacity': round(r['garments_per_trolley_capacity'], 0),
            'avg_wait_hours': round(r['avg_wait_hours'], 2),
            'spreading_blocked_pct': round(r['spreading_blocked_pct'], 1),
            'cutting_blocked_pct': round(r['cutting_blocked_pct'], 1),
            'blocked_by_space': r['blocked_by_space'],
        }
        if i % 10 == 0 or i == len(combos):
            print(f'  {i}/{len(combos)}')
    print()

    # ---------------------------------------------------------- the slip
    # Over ALL plan dates, computed here rather than from a trace — the trace
    # is now built one month at a time (below), and the dashboard's own SLIP
    # prose says "across all N dates", which must stay true once each output
    # file only carries one month of trace.
    slip = compute_slip(days)
    print(f"SLIP — {slip['late']} of {slip['dated']} tables ({slip['latePct']}%) "
          f"finish after their plan date, {slip['veryLatePct']}% more than a day late\n")

    # what the Gantt draws its shift bands from, at every cutter count the
    # Simulation tab's control can reach — not just the 5-cutter default
    layouts_by_count = {n: M.machine_layout(A.CUT_GROUPS_BY_CUTTER_COUNT[n])
                         for n in A.SIM_CUTTER_COUNTS}

    payload = {
        'generated_seconds': round(time.time() - started, 1),
        'plan_dates': len(days),
        'tables': sum(len(v) for v in days.values()),
        'assumptions': {
            'fleet_size': A.FLEET_SIZE,
            'cycle_days_allowed': A.CYCLE_DAYS_ALLOWED,
            'cycle_days_estimated': A.CYCLE_DAYS_ESTIMATED,
            'trolley_compartments': A.TROLLEY_COMPARTMENTS,
            'compartment_cap': A.COMPARTMENT_CAP,
            'max_batches_per_trolley': A.MAX_BATCHES_PER_TROLLEY,
            'trolley_bays': A.TROLLEY_BAYS,
            'wip_hold_minutes': A.WIP_HOLD_MINUTES,
            'wip_hold_any_workstation': A.WIP_HOLD_ANY_WORKSTATION,
            'max_trolleys_per_combine': A.MAX_TROLLEYS_PER_COMBINE,
            'relax_hours': A.RELAX_HOURS,
            'spreading_table_length_m': A.SPREADING_TABLE_LENGTH_M,
            'shift_start_minute': A.SHIFT_START_MINUTE,
            'film_size_by_garment_size': A.FILM_SIZE_BY_GARMENT_SIZE,
        },
        'cut_groups': A.CUT_GROUPS,
        'night_shift_spreaders': sorted(A.NIGHT_SHIFT_SPREADERS),
        'night_shift_cutters': sorted(A.NIGHT_SHIFT_CUTTERS),
        # what the Gantt draws its shift bands and break gaps from
        'spreader_shift': {m: M.SPREADER_SHIFT[m] for m in M.SPREADERS},
        'cutter_shift': {c: M.CUTTER_SHIFT[c] for c in A.CUT_GROUPS},
        'machine_minutes': M.MACHINE_MINUTES,
        'shift_end': M.SHIFT_END,
        'day_shift_end': A.DAY_SHIFT[1],
        # unique table lengths across the variants, in variant order — still
        # just ['21.2', '24', '27'], the table-length control's own axis.
        'table_lengths_m': list(dict.fromkeys(
            daytrace._metres_key(m) for m, c, full in daytrace.SIM_VARIANTS)),
        'status_colors': A.TASK_STATUS_COLORS,
        'status_not_simulated': A.TASK_STATUS_NOT_SIMULATED,
        'headline': headline,
        'hold_variants': variants,
        'sweep': sweep,
        'sweep_axes': {
            'hold_minutes': S.SWEEP_HOLD_MINUTES,
            'max_batches': S.SWEEP_MAX_BATCHES,
        },
        'per_day': headline_days,
        # ---- the cutter axis (plan §6.5's new payload keys) ----
        'sim_variants': [
            {'key': daytrace._variant_key(m, c), 'metres': m, 'cutters': c,
             'full': full, 'label': f'{m:g} m / {c} cutters'}
            for m, c, full in daytrace.SIM_VARIANTS
        ],
        'cutter_counts': list(A.SIM_CUTTER_COUNTS),
        'cut_groups_by_cutter_count': A.CUT_GROUPS_BY_CUTTER_COUNT,
        'cutter_shift_by_cutter_count': {
            str(n): layouts_by_count[n]['cutter_shift'] for n in A.SIM_CUTTER_COUNTS},
        'cutter_minutes_by_cutter_count': {
            str(n): layouts_by_count[n]['cutter_minutes'] for n in A.SIM_CUTTER_COUNTS},
        'slip': slip,
        'baseline_variant': daytrace._variant_key(*daytrace.BASELINE_VARIANT),
    }

    with open(f'{OUT}/results.json', 'w') as fh:
        json.dump(payload, fh, indent=1, default=str)
    with open(f'{OUT}/sweep.json', 'w') as fh:
        json.dump({'sweep': sweep, 'assumptions': payload['assumptions']}, fh, indent=1)
    print(f'wrote {OUT}/results.json  {OUT}/sweep.json')

    write_excel(payload)

    # ------------------------------------------------------- the month files
    # What the Simulation tab draws: every table of every day, the sequence it
    # was given, and what Python makes of the loading — so the page can check
    # its own arithmetic against the model in front of the reader. Built one
    # calendar month at a time and freed before the next: the full 199-date
    # trace does not fit the page's size budget (plan §6.2/§6.3) and holding
    # all of it in memory at once was the dominant cost of this build.
    months = sorted({date.strftime('%Y-%m') for date in days})
    months_info = [
        {'key': m, 'count': sum(1 for d in days if d.strftime('%Y-%m') == m)}
        for m in months
    ]
    print(f'TRACE — {len(months)} month files')
    last_path = None
    for month in months:
        month_days = {d: days[d] for d in days if d.strftime('%Y-%m') == month}
        trace = build_trace(month_days, skipped, days)
        last_path = f'{OUT}/sim-{month}.html'
        build_dashboard(payload, trace, months_info, month, last_path)
        n_tables = sum(len(v) for v in month_days.values())
        print(f'  wrote {last_path}  ({len(month_days)} dates, {n_tables} tables)')
        del trace

    # out/index.html mirrors the most recent month, so the existing entry
    # point keeps working without every reader needing to know the month URLs.
    shutil.copyfile(last_path, f'{OUT}/index.html')
    print(f'wrote {OUT}/index.html (copy of {last_path})')

    print(f'\ndone in {time.time() - started:.0f}s — open {OUT}/index.html')


def write_excel(payload: dict):
    """One workbook: scenario summary, per-day detail, and the raw sweep."""
    try:
        import openpyxl
        from openpyxl.styles import Alignment, Font, PatternFill
    except ImportError:
        print('  (openpyxl missing — skipping Excel)')
        return

    wb = openpyxl.Workbook()
    head_font = Font(bold=True, color='FFFFFF')
    head_fill = PatternFill('solid', fgColor='1E2A38')

    def sheet(title, headers, rows, widths=None):
        ws = wb.create_sheet(title)
        ws.append(headers)
        for c in ws[1]:
            c.font, c.fill = head_font, head_fill
            c.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)
        for r in rows:
            ws.append(r)
        for i, w in enumerate(widths or [], start=1):
            ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width = w
        ws.freeze_panes = 'A2'
        return ws

    # -- summary
    rows = []
    for name, r in payload['headline'].items():
        rows.append([
            name, round(r['utilization_pct'], 1), round(r['trolleys_per_day'], 0),
            r['peak_trolleys_in_a_day'], round(r['pieces_per_trolley'], 0),
            round(r['fleet_required_allowed_cycle'], 0),
            round(r['fleet_required_estimated_cycle'], 0),
            round(r['fleet_gap_estimated_cycle'], 0),
            round(r['longest_sustainable_cycle_days'], 1),
            'yes' if r['fits_in_fleet'] else 'NO',
            round(r['spreading_blocked_pct'], 1), round(r['cutting_blocked_pct'], 1),
        ])
    sheet('Scenarios',
          ['Scenario', 'Utilization %', 'Trolleys/day', 'Peak day', 'Pieces/trolley',
           f"Fleet needed @{payload['assumptions']['cycle_days_allowed']}d",
           f"Fleet needed @{payload['assumptions']['cycle_days_estimated']}d",
           'Fleet spare', 'Cycle days the fleet covers', 'Fits in fleet?',
           'Spreading blocked %', 'Cutting blocked %'],
          rows, [30, 13, 12, 10, 13, 13, 13, 11, 14, 11, 13, 13])

    # -- hold variants
    sheet('WIP hold variants',
          ['Setting', 'Utilization %', 'Trolleys/day', 'Avg wait (h)',
           f"Fleet needed @{payload['assumptions']['cycle_days_estimated']}d", 'Fits?'],
          [[n, round(r['utilization_pct'], 1), round(r['trolleys_per_day'], 0),
            round(r['avg_wait_hours'], 1),
            round(r['fleet_required_estimated_cycle'], 0),
            'yes' if r['fits_in_fleet'] else 'NO']
           for n, r in payload['hold_variants'].items()],
          [32, 13, 12, 12, 14, 8])

    # -- per day
    rows = []
    for name, per_day in payload['per_day'].items():
        for date, d in sorted(per_day.items()):
            rows.append([name, date, d['tasks'], d['combines'], d['compartments'],
                         d['trolleys'], round(d['trolley_utilization_pct'], 1),
                         d['pieces'], round(d['spreading_blocked_pct'], 1),
                         round(d['cutting_blocked_pct'], 1),
                         round(d['spreading_makespan_hours'], 1)])
    sheet('Per plan date',
          ['Scenario', 'Plan date', 'Tables', 'Combines', 'Compartments', 'Trolleys',
           'Utilization %', 'Pieces', 'Spreading blocked %', 'Cutting blocked %',
           'Spreading makespan (h)'],
          rows, [30, 12, 8, 10, 13, 9, 13, 10, 17, 17, 19])

    # -- sweep
    rows = []
    for key, r in payload['sweep'].items():
        mo, batches, hold, any_ws = key.split('|')
        rows.append(['yes' if mo == '1' else 'no', int(batches), int(hold),
                     'any' if any_ws == '1' else 'same',
                     r['utilization_pct'], r['trolleys_per_day'], r['peak'],
                     r['avg_wait_hours']])
    sheet('Sweep (all settings)',
          ['Same-MO sequencing', 'Max batches/trolley', 'WIP hold (min)',
           'Return to workstation', 'Utilization %', 'Trolleys/day', 'Peak',
           'Avg wait (h)'],
          rows, [18, 18, 15, 19, 13, 12, 8, 12])

    # -- assumptions, so the workbook is self-describing
    sheet('Assumptions', ['Setting', 'Value'],
          [[k.replace('_', ' '), v] for k, v in payload['assumptions'].items()],
          [34, 14])

    wb.remove(wb['Sheet'])
    wb.save(f'{OUT}/results.xlsx')
    print(f'wrote {OUT}/results.xlsx')


if __name__ == '__main__':
    main()
