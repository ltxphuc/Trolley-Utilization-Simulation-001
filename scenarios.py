"""
SCENARIOS
=========
The four headline scenarios are the three changes switched on one at a time,
in the order they would actually be approved. Each row is the previous row
plus one thing — so the table shows what each change is worth ON ITS OWN,
not just what they are worth together.

Also defined here: the sweeps that feed the interactive dashboard, and the
sensitivity tests that show which constraint is really binding.
"""
import assumptions as A
from model import Scenario

# ---------------------------------------------------------------- headline
HEADLINE = [
    Scenario(
        name='S0  Today',
        sequencing_mode='today',
        max_batches=1,
        wip_hold_minutes=0,
    ),
    Scenario(
        name='S1  + same-MO sequencing',
        # Same-batch-only, not cross-batch — CHANGE 1 as specified is "same-MO
        # adjacency", and at max_batches=1 there is no batch 2 to combine with
        # at loading, so pairing the SEQUENCE toward a cross-batch combine here
        # would pair machines against a combine that can never happen (see
        # model.py's Scenario.sequencing_mode comment). Fixed 2026-09-08 — see
        # README Part 8 §3's T-D table for the before/after this moved.
        sequencing_mode='same_batch',   # CHANGE 1
        max_batches=1,
        wip_hold_minutes=0,
    ),
    Scenario(
        name='S2  + 2 batches per trolley',
        # Cross-batch priority — max_batches=2 makes a cross-batch combine at
        # loading actually reachable, so pairing the sequence toward one is
        # meaningful here. Unchanged behaviour from before this session.
        sequencing_mode='cross_batch',
        max_batches=2,                  # CHANGE 2
        wip_hold_minutes=0,
    ),
    Scenario(
        name='S3  + WIP hold',
        sequencing_mode='cross_batch',
        max_batches=2,
        wip_hold_minutes=A.WIP_HOLD_MINUTES,          # CHANGE 3
        hold_any_workstation=A.WIP_HOLD_ANY_WORKSTATION,
    ),
]


# --------------------------------------------------- same WS vs any WS
# The single most important open question in change 3: when a parked trolley
# is called back, may it go to a DIFFERENT workstation, or only its own? These
# are all S2/S3-shaped (max_batches=2), so cross_batch — same as S2/S3 above.
HOLD_VARIANTS = [
    Scenario(name='No hold', sequencing_mode='cross_batch', max_batches=2,
             wip_hold_minutes=0),
    Scenario(name='1 h · same workstation only', sequencing_mode='cross_batch',
             max_batches=2, wip_hold_minutes=60, hold_any_workstation=False),
    Scenario(name='1 h · any workstation', sequencing_mode='cross_batch',
             max_batches=2, wip_hold_minutes=60, hold_any_workstation=True),
    Scenario(name='2 h · same workstation only', sequencing_mode='cross_batch',
             max_batches=2, wip_hold_minutes=120, hold_any_workstation=False),
    Scenario(name='2 h · any workstation', sequencing_mode='cross_batch',
             max_batches=2, wip_hold_minutes=120, hold_any_workstation=True),
]


# ------------------------------------------------------------- the sweep
# Every combination the dashboard sliders can land on. Fleet size and cycle
# days are NOT swept — they are pure arithmetic on trolleys-per-day, so the
# dashboard computes those live without needing a pre-computed result.
SWEEP_HOLD_MINUTES = [0, 30, 60, 90, 120, 180, 240]
SWEEP_MAX_BATCHES = [1, 2, 3]
SWEEP_SEQUENCING_MODE = ['today', 'same_batch', 'cross_batch']
SWEEP_ANY_WORKSTATION = [False, True]


def sweep_key(sequencing_mode, max_batches, hold_minutes, any_workstation) -> str:
    """Stable id shared between the Python sweep and the dashboard's lookup."""
    if hold_minutes == 0:
        any_workstation = True          # meaningless when nothing is held
    return f'{sequencing_mode}|{max_batches}|{hold_minutes}|{int(any_workstation)}'


def sweep_scenarios() -> dict:
    """-> {key: Scenario} for every reachable slider combination."""
    out = {}
    for sequencing_mode in SWEEP_SEQUENCING_MODE:
        for max_batches in SWEEP_MAX_BATCHES:
            for hold in SWEEP_HOLD_MINUTES:
                for any_ws in SWEEP_ANY_WORKSTATION:
                    key = sweep_key(sequencing_mode, max_batches, hold, any_ws)
                    if key in out:
                        continue
                    out[key] = Scenario(
                        name=key,
                        sequencing_mode=sequencing_mode,
                        max_batches=max_batches,
                        wip_hold_minutes=hold,
                        hold_any_workstation=any_ws,
                    )
    return out
