"""
ASSUMPTIONS
===========
Every number the model depends on lives here. Change a value, re-run
`python run.py`, and every output updates.

Each entry cites the rule it comes from (RULES.docx section, or the Job
Sequence flowchart). Where a value is an ESTIMATE rather than a measurement,
it says so — those are the ones worth challenging first.
"""

# ---------------------------------------------------------------- the trolley
TROLLEY_COMPARTMENTS = 5      # H3 — compartments on one trolley
COMPARTMENT_CAP = 150         # H1 — max garments in one compartment
MAX_BATCHES_PER_TROLLEY = 2   # floor rule — a trolley may carry 2 fabric
                              # batches in separate compartments, NEVER 3.
                              # Set to 1 to model today's same-batch-only rule.

MAX_TROLLEYS_PER_COMBINE = 4  # H8 — two combined tables may not need >4 trolleys
TROLLEY_BAYS = 52             # H7 — 13 workstations x 4 trolley positions.
                              # Caps how many part-filled trolleys can be
                              # parked and waiting at any one moment.

# --------------------------------------------------------------- the fleet
FLEET_SIZE = 1200             # trolleys the factory owns, total, across every
                              # process from Cutting through to Sewing.

CYCLE_DAYS_ALLOWED = 5        # the lead-time allowance: Relaxing -> Sewing
                              # (1+3+1 days per the process breakdown).

CYCLE_DAYS_ESTIMATED = 7      # <-- ESTIMATE, NOT MEASURED. The requester's own
                              # figure for how long a trolley really takes to
                              # come back to Panel Loading. This single number
                              # decides whether the fleet is short. Measuring it
                              # for one week is the highest-value thing on the
                              # open-items list.

# --------------------------------------------------------------- WIP hold
WIP_HOLD_MINUTES = 60         # how long a part-filled trolley may wait in CCT
                              # WIP for a later matching table. 0 = off
                              # (dispatch immediately, which is today's rule).

WIP_HOLD_ANY_WORKSTATION = True
                              # True  = a parked trolley can be called to
                              #         WHICHEVER workstation next cuts a
                              #         matching table.
                              # False = it may only be topped up by a later
                              #         table at the SAME workstation it left.
                              # This flag is worth ~6 points on its own. The
                              # operational question of HOW the trolley travels
                              # (labour / AGV / manual push) is NOT modelled.

# The match key for topping up a parked trolley. All three must be equal.
# Batches may differ — that is the whole point — but colour and film size
# may not, so a trolley is never mixed across dye lots or film widths.
WIP_HOLD_MATCH_ON = ('mo', 'color', 'film_size')

# ------------------------------------------------------------ film sizes (H5)
# Which film width each garment size is cut on. Sizes on different films
# cannot share a compartment.
FILM_SIZE_BY_GARMENT_SIZE = {
    'XXS':  90, 'XS':  90, 'S':  90,
    'M':   100, 'L':  100,
    'XL':  110, 'XXL': 110, '3XL': 110, '4XL': 110,
}
UNIVERSAL_SIZES = list(FILM_SIZE_BY_GARMENT_SIZE)

# Net_Rate is universal here, so the H5 mapping above is the whole story —
# there is nothing to switch between.

# ------------------------------------------------------- task readiness (S)
# The status a task carries in the Auto Planning System when the day is
# sequenced. Colours are the floor's own convention and must not be changed.
#
# Only four of these are simulated — see "Task readiness statuses" in README.md
# for where each one comes from and why two of them never fire here.
TASK_STATUS_COLORS = {
    'normal':          '#9bc2e6',   # 1 fabric relaxed 24h AND pattern in system
    'cut_queue':       '#833c0c',   # 2 queued by hand, not by the system
    'stretch':         '#ffd966',   # 3 last table of the batch, spreads the last yards
    'no_pattern':      '#a9d08e',   # 4 fabric relaxed, no pattern
    'no_fabric_time':  '#f4b084',   # 5 pattern in system, fabric not relaxed long enough
    'neither':         '#7030a0',   # 6 no pattern AND fabric not relaxed
    'no_fabric':       '#305496',   # 7 no fabric information at all
    'completed':       '#d9d9d9',   # 8 spreading and cutting finished
}

# Statuses the simulation does NOT produce, and why. Shown in the legend so the
# floor's full colour set is visible, but they will always read zero.
TASK_STATUS_NOT_SIMULATED = {
    'cut_queue': 'manual intervention — not a system arrangement, so not modelled',
    'no_fabric': 'Lot and Batch No are filled on every row, so this can never fire',
}

RELAX_HOURS = 24              # fabric must relax this long before it may be
                              # spread. This is a hard precondition, not a
                              # variable — a table is not released to the floor
                              # until its fabric has had its 24 hours. The
                              # simulation therefore treats every planned table
                              # as relaxed, and the two "not enough fabric"
                              # statuses stay in the legend reading zero.

# --------------------------------------------------------------- the machines
# F2 — the 13 spreading machines grouped under their cutting machines.
# The 5-cutter entry is the floor as it is today. The 6/7/8-cutter entries are
# the "add cutting machines" what-if named in README.md Part 7 section 4,
# recommendation 4 — NOT the floor as it stands.
#
# 24MC1 keeps 24-01/02/03 at EVERY count, so NIGHT_SHIFT_SPREADERS,
# NIGHT_SHIFT_CUTTERS and FLEXIBLE_CUT below all stay valid unmodified.
# Only the ten day-only spreaders are re-partitioned, splitting the two
# saturated groups (24MC4, 24MC5 — Part 7 section 3) first.
CUT_GROUPS_BY_CUTTER_COUNT = {
    5: {'24MC1': ['24-01', '24-02', '24-03'], '24MC2': ['24-04', '24-05'],
        '24MC3': ['24-06', '24-07'], '24MC4': ['24-08', '24-09', '24-10'],
        '24MC5': ['24-11', '24-12', '24-13']},
    6: {'24MC1': ['24-01', '24-02', '24-03'], '24MC2': ['24-04', '24-05'],
        '24MC3': ['24-06', '24-07'], '24MC4': ['24-08', '24-09'],
        '24MC5': ['24-10', '24-11'], '24MC6': ['24-12', '24-13']},
    7: {'24MC1': ['24-01', '24-02', '24-03'], '24MC2': ['24-04', '24-05'],
        '24MC3': ['24-06', '24-07'], '24MC4': ['24-08', '24-09'],
        '24MC5': ['24-10', '24-11'], '24MC6': ['24-12'], '24MC7': ['24-13']},
    8: {'24MC1': ['24-01', '24-02', '24-03'], '24MC2': ['24-04', '24-05'],
        '24MC3': ['24-06', '24-07'], '24MC4': ['24-08', '24-09'],
        '24MC5': ['24-10'], '24MC6': ['24-11'], '24MC7': ['24-12'],
        '24MC8': ['24-13']},
}

CUTTER_COUNT = 5              # the floor today. 13 / 5 = 2.60 spreaders per
                              # cutting machine. Everything published in
                              # README.md is this value.
CUT_GROUPS = CUT_GROUPS_BY_CUTTER_COUNT[CUTTER_COUNT]

SIM_CUTTER_COUNTS = (5, 6, 7, 8)   # what the Simulation tab's control offers.

# F8 — two spreading machines can be served by a second cutting machine.
FLEXIBLE_CUT = {
    '24-03': ['24MC1', '24MC2'],
    '24-05': ['24MC2', '24MC3'],
}

# F5-F7 — night shift runs only these; everything else is day shift only.
NIGHT_SHIFT_SPREADERS = {'24-01', '24-02', '24-03'}
NIGHT_SHIFT_CUTTERS = {'24MC1'}

# ------------------------------------------------------------------ the shifts
# Every time in the model is minutes from the start of the day shift, so
# t = 0 is 07:15 and the Gantt reads in real clock time.
SHIFT_START_MINUTE = 7 * 60 + 15        # 07:15

# Day shift 07:15-20:00, all 13 spreaders and all 5 cutters.
# Night shift 18:00-05:00, only NIGHT_SHIFT_SPREADERS and NIGHT_SHIFT_CUTTERS.
# The two overlap 18:00-20:00 — that adds no capacity, it is the same machine
# running on, so a night-capable machine is simply available 07:15 -> 05:00.
DAY_SHIFT = (0, 765)                    # 07:15 - 20:00
NIGHT_SHIFT = (645, 1305)               # 18:00 - 05:00 (user, 2026-11-09; joins the day shift)

DAY_BREAKS = [(270, 330), (600, 630)]       # 11:45-12:45, 17:15-17:45
NIGHT_BREAKS = [(885, 915), (1125, 1155)]   # 22:00-22:30, 02:00-02:30

BREAKS_STOP_MACHINES = True   # spreading and cutting stop for breaks. Set False
                              # if relief staffing keeps the machines running —
                              # it is worth ~150 minutes a machine a day.

# ------------------------------------------------------ the spreading table
# G6 says a spreading machine blocks once two tables are sitting at its cutting
# end. That "two" is not a rule in itself — it is what a 21.2 m table gives you
# when the median marker is 8.8 yd. The model works in length, not in slots.
#
# A lay occupies its marker length on the table from the moment it is spread.
# Cutting then consumes that length PROGRESSIVELY between cut start and cut end
# — the lay is fed toward the cutting machine as it is cut — so space comes back
# gradually and the spreader can restart part way through the cut in front of
# it. Modelling it as a slot that frees only at cut_end overstates blocking by
# about two thirds.
SPREADING_TABLE_LENGTH_M = 21.2   # MEASURED. The usable length of one table.
YARDS_PER_METRE = 1.0936133
SPREADING_TABLE_LENGTH = SPREADING_TABLE_LENGTH_M * YARDS_PER_METRE

# Whether a new lay needs its full length free before it may start. True is
# conservative: in reality the spreader lays progressively and only needs the
# space to arrive as it goes.
LAY_NEEDS_FULL_LENGTH = True

# Fraction of a machine's staffed window that may be filled with spreading
# work when planning. The remainder absorbs blocking. Planning heuristic,
# not a written rule.
MACHINE_FILL_TARGET = 0.70

# ------------------------------------------------------------------ the times
# G2 — spreading and cutting time from layer count and marker length.
SPREAD_MIN_PER_LAYER_PER_YARD = 0.80 / 8.5
CUT_MIN_PER_LAYER_PER_YARD = 0.40 / 8.5

# No machine speed factor (removed 2026-11-09, user decision): spreading and
# cutting run at the G2 standard pace; a 0.80 factor calibrated to Pull Date
# lateness was an unmeasured catch-all; with cutter changeover and moving time
# in the model a one-off sweep of the speed found none that reproduced the real
# lateness (SIM_SPEC.md §18). tools/carryover_probe.js now only validates.

# User requirement (2026-11-06, not an estimate): Central Cutting must cut at
# least this many pieces a day. The Rules Lab's Output panel tests the floor
# against it.
REQUIRED_PIECES_PER_DAY = 100000

# S0, the real Job Sequence (data/SQL Job Sequence Logic.sql, P_Task_Calculate):
# within one plan date a table's priority comes from its order type (HaveCut
# column 订单类型): SQR first, then QR, then Normal. Anything else, including an
# empty order type, ranks with Normal. From the commented-out older rule at
# L1016-1076; the live Job_Seq_Schedule_Priority table was NOT supplied, so this
# is an ESTIMATE, NOT MEASURED.
ORDER_TYPE_PRIORITY = {'SQR': 0, 'QR': 1, 'Normal': 2}
ORDER_TYPE_PRIORITY_DEFAULT = 2

# The LIVE FLOOR (user rules, 2026-11-10; tools/floor.js). The Job Sequence re-plans every
# REPLAN_MINUTES, around the clock, every ready table not yet started, for the next
# PLAN_HORIZON_HOURS (all shifts); a table is ready from its plan date's 07:15 (earlier with
# pull-ahead), its Marker Date and its fabric (the relaxing ESTIMATE); and a free cutter takes
# the lay that has waited longest. That cutter rule is a stand-in for the operator's free
# choice: ESTIMATE, NOT MEASURED. LIVE_FLOOR = False is the floor of 2026-11-09 (each plan
# date planned once at 07:15, every table ready, the cutter cutting in spread order), kept only
# so that npm run beforeafter can reproduce the earlier stages.
LIVE_FLOOR = True
REPLAN_MINUTES = 30
PLAN_HORIZON_HOURS = 24

# G3 / I3 — a C table adds setup time to the B table on the same physical
# table. ESTIMATE, NOT MEASURED, and now a RANGE rather than one figure: the
# user's instruction, 2026-09-08, is 8-10 minutes per spreading task that has a
# directly connected C task.
#
# The value is chosen DETERMINISTICALLY from the table's own identity, never at
# random. A random draw would make every rebuild disagree with the last one and
# would permanently fail the parity gate.
C_SETUP_MINUTES_MIN_TENTHS = 80    # 8.0 min.  ESTIMATE.
C_SETUP_MINUTES_MAX_TENTHS = 100   # 10.0 min. ESTIMATE.
                                   # Tenths, not floats, so the Python and the
                                   # Node mirror do integer arithmetic and one
                                   # correctly-rounded division each.

# FNV-1a, 32-bit. Named here because assumptions.py is the only place a number
# may live; the algorithm itself is in model.py's _fnv1a32().
C_SETUP_HASH_OFFSET = 2166136261   # FNV-1a 32-bit offset basis
C_SETUP_HASH_PRIME = 16777619      # FNV-1a 32-bit prime

C_SETUP_PER_C_ROW = False          # False = one setup per B table that has ANY
                                   # C row — today's shape (the C keys are a
                                   # set), and the recommendation: the setup is
                                   # a property of the physical table, and two
                                   # C records against one table are two
                                   # paperwork rows, not two setups. True = one
                                   # setup per C row (92 of 6,271 matched keys
                                   # have two).

# ------------------------------------------------------------ pull-ahead
# User rule, 2026-11-05: once a spreading machine has finished its own queue
# for today's plan, it may continue into the next plan date's tables. This is
# how many plan dates ahead a machine may reach. 0 = off (today's behaviour).
# Read ONLY by tools/lab.js (the pull-ahead add-on value); the build, the
# headline and every gate ignore it. (The standalone measurement script
# tools/pullahead_table.js was retired 2026-11-09.) ASSUMES the next day's
# fabric is already relaxed and released when the machine reaches it.
PULL_AHEAD_DAYS = 1

# ------------------------------------------------------------ Rules Lab
# User decisions, 2026-11-05. The fabric arrival window is read ONLY by
# tools/lab.js, the Rules Lab engine (Node-only: the page runs the same file,
# so there is no Python mirror and no second port to drift). The build, the
# headline and every gate ignore it. The cutter setup and travel below are
# also read by the model (carry_timeline).
#
# Fabric arrival time is NOT in the data. Each batch is given a deterministic
# arrival (FNV-1a hash of the batch id) this many hours BEFORE its first plan
# date's 07:15; it is then ready RELAX_HOURS later. ESTIMATE, NOT MEASURED.
RELAX_ARRIVAL_LEAD_MIN_H = 12
RELAX_ARRIVAL_LEAD_MAX_H = 48

# Cutter changeover when the next table's MO or colour differs from the
# cutter's last one: clean-up of the area plus cutting-speed adjustment.
# ESTIMATE, NOT MEASURED. 0 when MO and colour are both unchanged. Part of
# the PUBLISHED model since 2026-11-09 (user: "make it default for every
# machine that change overtime is 5 mins"; cutters only, spreaders keep their
# C-table setup). Read by carry_timeline() / carryTimeline() and by the Lab.
# Added on top of the G2 pace.
CUT_SETUP_MO_COLOR_MINUTES = 5

# Cutter moving to a different spreading workstation than its last one
# (1-2 min back and forth per the user; 1.5 min is the user's default of
# 2026-11-09). ESTIMATE, NOT MEASURED. Same readers as the setup above.
CUT_TRAVEL_MINUTES = 1.5

LAB_SHIFT_OPTIONS = ('both', 'day', 'night')   # night = 24-01/02/03 + 24MC1 only

# ---------------------------------------------------------- the website scope
# User decision, 2026-09-08: the full 199-date/8-month trace (all 3 sequencing
# modes x all 4 cutter counts, fully chartable, every month) does not fit the
# page's size budget — even after cutting cutter-count fidelity, EVERY month
# was still over budget with the 3-way sequencing split added. Rather than
# thin every month, the website's SCOPE narrows to these three: the entire
# built dataset — headline S0-S3, the sweep, results.json, and every month
# file — covers only these months, not all 8. This is a deliberate reduction,
# not a bug: it replaces the 199-date/23-trolleys-short headline with a
# smaller, Apr-Jun-only one. Model.py's load_days() itself is untouched and
# still reads every date in DATA_FILE — regress.js and idle_variants.py
# still operate on the full file or the original 20-date fixture,
# independent of this. Only run.py/tools/build.js's own aggregate and month-
# file construction is scoped here.
WEBSITE_MONTHS = ('2026-04', '2026-05', '2026-06')

# ------------------------------------------------------------------ the data
DATA_FILE = 'data/PPC Planning - Old Data.xlsx'
                              # 199 plan dates, 2026-01-02 -> 2026-08-26.
                              # 22,638 HaveCut rows; 15,928 are Type B and
                              # 15,923 of those survive rule J2's First
                              # Table = Y test; 15,920 carry a usable marker
                              # ratio, layer count and marker length and so
                              # reach the model. A strict superset of
                              # PIN_DATA_FILE below (same sheet, 68 columns
                              # against 66 — the two extra are size columns
                              # the model does not read).
DATA_SHEET = 'HaveCut'

PIN_DATA_FILE = 'data/planppc.xlsx'
                              # The 20-date export out/*.bak was built from.
                              # RETAINED SOLELY as the regression fixture for
                              # tools/regress.js (the pin against out/*.bak
                              # was retired 2026-11-09). run.py and
                              # tools/build.js never read it.

# J2 — only Type B tables enter the model; First Table = Y is excluded.
# J3 — non-universal markers (kids sizes, number sizes) still occupy machines
#      in the timeline but carry no compartment maths.
