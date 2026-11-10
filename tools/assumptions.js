'use strict';
/*
ASSUMPTIONS — mirrors assumptions.py exactly, value for value, comment for
comment reference. This file has no logic of its own; see assumptions.py for
the rule citations. Change a number there, then here, never the other way.
*/

// ---------------------------------------------------------------- the trolley
const TROLLEY_COMPARTMENTS = 5;      // H3 — compartments on one trolley
const COMPARTMENT_CAP = 150;         // H1 — max garments in one compartment
const MAX_BATCHES_PER_TROLLEY = 2;   // floor rule — a trolley may carry 2 fabric
                                      // batches in separate compartments, NEVER 3.

const MAX_TROLLEYS_PER_COMBINE = 4;  // H8
const TROLLEY_BAYS = 52;             // H7 — 13 workstations x 4 trolley positions.

// --------------------------------------------------------------- the fleet
const FLEET_SIZE = 1200;
const CYCLE_DAYS_ALLOWED = 5;
const CYCLE_DAYS_ESTIMATED = 7;      // ESTIMATE, NOT MEASURED.

// --------------------------------------------------------------- WIP hold
const WIP_HOLD_MINUTES = 60;
const WIP_HOLD_ANY_WORKSTATION = true;
const WIP_HOLD_MATCH_ON = ['mo', 'color', 'film_size'];

// ------------------------------------------------------------ film sizes (H5)
const FILM_SIZE_BY_GARMENT_SIZE = {
  XXS: 90, XS: 90, S: 90,
  M: 100, L: 100,
  XL: 110, XXL: 110, '3XL': 110, '4XL': 110,
};
const UNIVERSAL_SIZES = Object.keys(FILM_SIZE_BY_GARMENT_SIZE);

// ------------------------------------------------------- task readiness (S)
const TASK_STATUS_COLORS = {
  normal: '#9bc2e6',
  cut_queue: '#833c0c',
  stretch: '#ffd966',
  no_pattern: '#a9d08e',
  no_fabric_time: '#f4b084',
  neither: '#7030a0',
  no_fabric: '#305496',
  completed: '#d9d9d9',
};

const TASK_STATUS_NOT_SIMULATED = {
  cut_queue: 'manual intervention — not a system arrangement, so not modelled',
  no_fabric: 'Lot and Batch No are filled on every row, so this can never fire',
};

const RELAX_HOURS = 24;

// --------------------------------------------------------------- the machines
// F2. 24MC1 keeps 24-01/02/03 at every count, so the night-shift sets and
// FLEXIBLE_CUT below stay valid unmodified — see assumptions.py.
const CUT_GROUPS_BY_CUTTER_COUNT = {
  5: {
    '24MC1': ['24-01', '24-02', '24-03'], '24MC2': ['24-04', '24-05'],
    '24MC3': ['24-06', '24-07'], '24MC4': ['24-08', '24-09', '24-10'],
    '24MC5': ['24-11', '24-12', '24-13'],
  },
  6: {
    '24MC1': ['24-01', '24-02', '24-03'], '24MC2': ['24-04', '24-05'],
    '24MC3': ['24-06', '24-07'], '24MC4': ['24-08', '24-09'],
    '24MC5': ['24-10', '24-11'], '24MC6': ['24-12', '24-13'],
  },
  7: {
    '24MC1': ['24-01', '24-02', '24-03'], '24MC2': ['24-04', '24-05'],
    '24MC3': ['24-06', '24-07'], '24MC4': ['24-08', '24-09'],
    '24MC5': ['24-10', '24-11'], '24MC6': ['24-12'], '24MC7': ['24-13'],
  },
  8: {
    '24MC1': ['24-01', '24-02', '24-03'], '24MC2': ['24-04', '24-05'],
    '24MC3': ['24-06', '24-07'], '24MC4': ['24-08', '24-09'],
    '24MC5': ['24-10'], '24MC6': ['24-11'], '24MC7': ['24-12'],
    '24MC8': ['24-13'],
  },
};

const CUTTER_COUNT = 5;       // the floor today — everything published is this.
const CUT_GROUPS = CUT_GROUPS_BY_CUTTER_COUNT[CUTTER_COUNT];

const SIM_CUTTER_COUNTS = [5, 6, 7, 8];

const FLEXIBLE_CUT = {
  '24-03': ['24MC1', '24MC2'],
  '24-05': ['24MC2', '24MC3'],
};

const NIGHT_SHIFT_SPREADERS = new Set(['24-01', '24-02', '24-03']);
const NIGHT_SHIFT_CUTTERS = new Set(['24MC1']);

// ------------------------------------------------------------------ the shifts
const SHIFT_START_MINUTE = 7 * 60 + 15;  // 07:15

const DAY_SHIFT = [0, 765];              // 07:15 - 20:00
const NIGHT_SHIFT = [645, 1305];         // 18:00 - 05:00 (user, 2026-11-09; joins the day shift)

const DAY_BREAKS = [[270, 330], [600, 630]];
const NIGHT_BREAKS = [[885, 915], [1125, 1155]];

const BREAKS_STOP_MACHINES = true;

// ------------------------------------------------------ the spreading table
const SPREADING_TABLE_LENGTH_M = 21.2;   // MEASURED.
const YARDS_PER_METRE = 1.0936133;
const SPREADING_TABLE_LENGTH = SPREADING_TABLE_LENGTH_M * YARDS_PER_METRE;

const LAY_NEEDS_FULL_LENGTH = true;
const MACHINE_FILL_TARGET = 0.70;

// ------------------------------------------------------------------ the times
const SPREAD_MIN_PER_LAYER_PER_YARD = 0.80 / 8.5;
const CUT_MIN_PER_LAYER_PER_YARD = 0.40 / 8.5;

// No machine speed factor (removed 2026-11-09, user decision): spreading and
// cutting run at the G2 standard pace; a 0.80 factor calibrated to Pull Date
// lateness was an unmeasured catch-all; with cutter changeover and moving time
// in the model a one-off sweep of the speed found none that reproduced the real
// lateness (SIM_SPEC.md §18). tools/carryover_probe.js now only validates.

// User requirement (2026-11-06, not an estimate): Central Cutting must cut at
// least this many pieces a day. The Rules Lab's Output panel tests the floor
// against it.
const REQUIRED_PIECES_PER_DAY = 100000;

// S0, the real Job Sequence (data/SQL Job Sequence Logic.sql, P_Task_Calculate):
// within one plan date a table's priority comes from its order type (HaveCut
// column 订单类型): SQR first, then QR, then Normal. Anything else, including an
// empty order type, ranks with Normal. From the commented-out older rule at
// L1016-1076; the live Job_Seq_Schedule_Priority table was NOT supplied, so this
// is an ESTIMATE, NOT MEASURED.
const ORDER_TYPE_PRIORITY = { SQR: 0, QR: 1, Normal: 2 };
const ORDER_TYPE_PRIORITY_DEFAULT = 2;

// The LIVE FLOOR (user rules, 2026-11-10; tools/floor.js). The Job Sequence re-plans every
// REPLAN_MINUTES, around the clock, every ready table not yet started, for the next
// PLAN_HORIZON_HOURS (all shifts); a table is ready from its plan date's 07:15 (earlier with
// pull-ahead), its Marker Date and its fabric (the relaxing ESTIMATE below); and a free cutter
// takes the lay that has waited longest. CUTTER_PICK is a stand-in for the operator's free
// choice: ESTIMATE, NOT MEASURED. LIVE_FLOOR = false is the floor of 2026-11-09 (each plan date
// planned once at 07:15, every table ready, the cutter cutting in spread order), kept only so
// that npm run beforeafter can reproduce the earlier stages.
const LIVE_FLOOR = true;
const REPLAN_MINUTES = 30;
const PLAN_HORIZON_HOURS = 24;

// G3 / I3 — a C table adds setup time to the B table on the same physical
// table. ESTIMATE, and a RANGE: 8-10 minutes, chosen DETERMINISTICALLY from the
// table's own identity (see assumptions.py and model.js's fnv1a32).
const C_SETUP_MINUTES_MIN_TENTHS = 80;    // 8.0 min.  ESTIMATE.
const C_SETUP_MINUTES_MAX_TENTHS = 100;   // 10.0 min. ESTIMATE.
const C_SETUP_HASH_OFFSET = 2166136261;   // FNV-1a 32-bit offset basis
const C_SETUP_HASH_PRIME = 16777619;      // FNV-1a 32-bit prime
const C_SETUP_PER_C_ROW = false;          // one setup per B table with ANY C row

// ------------------------------------------------------------ pull-ahead
// Mirrors assumptions.py — user rule, 2026-11-05. Plan dates a machine may
// reach ahead once its own queue for today is done. 0 = off. Read only by
// tools/lab.js (the pull-ahead add-on value; the standalone pullahead_table.js
// was retired 2026-11-09). ASSUMES next-day fabric is relaxed.
const PULL_AHEAD_DAYS = 1;

// ------------------------------------------------------------ Rules Lab
// Mirrors assumptions.py. The arrival window is read only by tools/lab.js
// (Node-only, shared with the page); the cutter setup and travel are also read
// by the model (carryTimeline) since 2026-11-09, cutters only, added on top of
// the G2 pace. Arrival, setup and travel are all ESTIMATES, NOT MEASURED.
const RELAX_ARRIVAL_LEAD_MIN_H = 12;
const RELAX_ARRIVAL_LEAD_MAX_H = 48;
const CUT_SETUP_MO_COLOR_MINUTES = 5;    // ESTIMATE, NOT MEASURED: cutter changeover on an MO or colour change
const CUT_TRAVEL_MINUTES = 1.5;          // ESTIMATE, NOT MEASURED: cutter moving to a different spreader
const LAB_SHIFT_OPTIONS = ['both', 'day', 'night'];

// ---------------------------------------------------------- the website scope
// Mirrors assumptions.py's matching comment — user decision, 2026-09-08.
// Narrows run.py/tools/build.js's aggregate + month files to these three
// months only; loadDays() itself, regress.js and idle_variants.js
// are unaffected and still see the full file.
const WEBSITE_MONTHS = ['2026-04', '2026-05', '2026-06'];

// ------------------------------------------------------------------ the data
const DATA_FILE = 'data/PPC Planning - Old Data.xlsx';   // 199 plan dates, 15,920 tables
const DATA_SHEET = 'HaveCut';

// The 20-date export out/*.bak was built from. RETAINED SOLELY as the
// regression fixture for tools/regress.js (the pin against out/*.bak was
// retired 2026-11-09) — the build never reads it.
const PIN_DATA_FILE = 'data/planppc.xlsx';

module.exports = {
  TROLLEY_COMPARTMENTS, COMPARTMENT_CAP, MAX_BATCHES_PER_TROLLEY,
  MAX_TROLLEYS_PER_COMBINE, TROLLEY_BAYS,
  FLEET_SIZE, CYCLE_DAYS_ALLOWED, CYCLE_DAYS_ESTIMATED,
  WIP_HOLD_MINUTES, WIP_HOLD_ANY_WORKSTATION, WIP_HOLD_MATCH_ON,
  FILM_SIZE_BY_GARMENT_SIZE, UNIVERSAL_SIZES,
  TASK_STATUS_COLORS, TASK_STATUS_NOT_SIMULATED, RELAX_HOURS,
  CUT_GROUPS_BY_CUTTER_COUNT, CUTTER_COUNT, SIM_CUTTER_COUNTS,
  CUT_GROUPS, FLEXIBLE_CUT, NIGHT_SHIFT_SPREADERS, NIGHT_SHIFT_CUTTERS,
  SHIFT_START_MINUTE, DAY_SHIFT, NIGHT_SHIFT, DAY_BREAKS, NIGHT_BREAKS,
  BREAKS_STOP_MACHINES,
  SPREADING_TABLE_LENGTH_M, YARDS_PER_METRE, SPREADING_TABLE_LENGTH,
  LAY_NEEDS_FULL_LENGTH, MACHINE_FILL_TARGET,
  SPREAD_MIN_PER_LAYER_PER_YARD, CUT_MIN_PER_LAYER_PER_YARD, REQUIRED_PIECES_PER_DAY,
  ORDER_TYPE_PRIORITY, ORDER_TYPE_PRIORITY_DEFAULT,
  LIVE_FLOOR, REPLAN_MINUTES, PLAN_HORIZON_HOURS,
  C_SETUP_MINUTES_MIN_TENTHS, C_SETUP_MINUTES_MAX_TENTHS,
  C_SETUP_HASH_OFFSET, C_SETUP_HASH_PRIME, C_SETUP_PER_C_ROW,
  PULL_AHEAD_DAYS,
  RELAX_ARRIVAL_LEAD_MIN_H, RELAX_ARRIVAL_LEAD_MAX_H,
  CUT_SETUP_MO_COLOR_MINUTES, CUT_TRAVEL_MINUTES, LAB_SHIFT_OPTIONS,
  DATA_FILE, DATA_SHEET, PIN_DATA_FILE, WEBSITE_MONTHS,
};
