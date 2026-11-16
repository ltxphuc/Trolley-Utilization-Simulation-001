'use strict';
/* DATA MODEL — the register of entities, attributes, parameters, formulas and data statistics.
 * ==========================================================================================
 * User, 2026-11-16: "somewhere to show the attribute and current number using for calculation, which
 * later if we build a bigger data model, we can base on that."
 *
 *   npm run datamodel              # writes docs/DATA_MODEL.md and docs/data_model/*.csv
 *   npm run datamodel -- --check   # exits 1 if those files are not what the code gives now
 *
 * This file holds WORDS only (descriptions, units, formula text, sources). Every value it prints is read
 * from tools/assumptions.js, the machine layout (tools/model.js machineLayout) or the workbook (loadDays),
 * so the register cannot drift from the code. It never feeds the build. Output is deterministic (no dates,
 * no timestamps) so --check can compare byte for byte.
 *
 * Asserts (exit 1): every constant exported by assumptions.js has a parameter row; every RULES.md ID cited
 * exists in RULES.md; every formula input is a known attribute, parameter or formula.
 */
const fs = require('fs');
const path = require('path');
const A = require('./assumptions');
const M = require('./model');
const S = require('./scenarios');
const { bankersRound } = require('./round');

const REPO = path.join(__dirname, '..');
const CHECK = process.argv.includes('--check');
const OUT_MD = path.join(REPO, 'docs', 'DATA_MODEL.md');
const OUT_DIR = path.join(REPO, 'docs', 'data_model');

// ------------------------------------------------------------------ parameters (words only)
// [name, unit, status, RULES.md ID(s), description]. The value is always A[name].
const PARAMS = [
  ['TROLLEY_COMPARTMENTS', 'compartments per trolley', 'rule', 'H3', 'Compartments on one trolley.'],
  ['COMPARTMENT_CAP', 'garments per compartment', 'rule', 'H1', 'Most garments one compartment holds.'],
  ['MAX_BATCHES_PER_TROLLEY', 'batches per trolley', 'proposed rule', 'C2.1', 'Most fabric batches one trolley may carry (Change 2); never 3.'],
  ['TOPUP_BATCH_CAP_FROM_SCENARIO', 'flag', 'rule', 'C2.3', 'true: a waiting trolley is topped up only up to the scenario\'s own batch limit, so 1 batch never mixes (Q1 fixed).'],
  ['MAX_TROLLEYS_PER_COMBINE', 'trolleys', 'rule', 'H8', 'Most trolleys one combine may need.'],
  ['TROLLEY_BAYS', 'trolleys', 'rule', 'H7', 'Most part-filled trolleys waiting at once (13 workstations x 4 positions).'],
  ['FLEET_SIZE', 'trolleys', 'fact', 'B4', 'Trolleys owned.'],
  ['CYCLE_DAYS_ALLOWED', 'days', 'allowance', 'B5', 'Round-trip allowance (1 + 3 + 1 days).'],
  ['CYCLE_DAYS_ESTIMATED', 'days', 'ESTIMATE', 'B6, E1', 'Round trip used for the fleet figures. Never timed.'],
  ['WIP_HOLD_MINUTES', 'min', 'proposed', 'C3.2', 'How long a part-filled trolley waits in CCT WIP (Change 3, S3).'],
  ['WIP_HOLD_ANY_WORKSTATION', 'flag', 'proposed', 'C3.4', 'true: a waiting trolley may be recalled to any workstation.'],
  ['WIP_HOLD_MATCH_ON', 'key fields', 'proposed', 'C3.3', 'What a waiting trolley must share with a new table to be topped up.'],
  ['FILM_SIZE_BY_GARMENT_SIZE', 'film width (cm) by size', 'ESTIMATE', 'H5, E8', 'Film width each garment size is cut on; stands in for the real Net_Rate.'],
  ['UNIVERSAL_SIZES', 'sizes', 'derived', 'J3', 'Sizes in the film map. A table with any other size loads no compartments.'],
  ['TASK_STATUS_COLORS', 'colour by status', 'display', '—', 'Colours of the eight task-readiness statuses (display only).'],
  ['TASK_STATUS_NOT_SIMULATED', 'text', 'display', '—', 'Statuses that can never appear in the model, and why.'],
  ['RELAX_HOURS', 'h', 'rule', 'R3', 'Time fabric must relax before it is spread.'],
  ['CUT_GROUPS_BY_CUTTER_COUNT', 'spreaders by cutter', 'floor fact / what-if', 'F2', 'Which spreaders each cutter serves, at 5 (today) to 8 cutters. 6 to 8 are engine-only what-ifs.'],
  ['CUTTER_COUNT', 'cutters', 'floor fact', 'F2', 'Cutting machines today.'],
  ['SIM_CUTTER_COUNTS', 'cutters', 'what-if', 'F2', 'Cutter counts the engine and measurement scripts can run.'],
  ['CUT_GROUPS', 'spreaders by cutter', 'floor fact', 'F2', 'Today\'s cut groups.'],
  ['FLEXIBLE_CUT', 'cutters by spreader', 'rule', 'F8', 'Spreaders that may call a second cutter.'],
  ['NIGHT_SHIFT_SPREADERS', 'machines', 'rule', 'F5–F7', 'Spreaders that also work the night shift.'],
  ['NIGHT_SHIFT_CUTTERS', 'machines', 'rule', 'F5–F7', 'Cutters that also work the night shift.'],
  ['SHIFT_START_MINUTE', 'min after midnight', 'measured', 'B1', 'Start of the day shift (07:15). The model clock is minutes after it.'],
  ['DAY_SHIFT', '[start, end] min after 07:15', 'measured', 'B1', 'Day shift window (07:15–20:00).'],
  ['NIGHT_SHIFT', '[start, end] min after 07:15', 'measured', 'B2', 'Night shift window (18:00–05:00).'],
  ['DAY_BREAKS', '[[start, end]] min after 07:15', 'measured', 'B1', 'Day-shift breaks (11:45–12:45, 17:15–17:45).'],
  ['NIGHT_BREAKS', '[[start, end]] min after 07:15', 'measured', 'B2', 'Night-shift breaks (22:00–22:30, 02:00–02:30).'],
  ['BREAKS_STOP_MACHINES', 'flag', 'ESTIMATE', 'T2, E9', 'true: machines stop during breaks. Unconfirmed.'],
  ['SPREADING_TABLE_LENGTH_M', 'm', 'measured', 'B3', 'Spreading table length, the same on all 13 spreaders.'],
  ['YARDS_PER_METRE', 'yd per m', 'constant', '—', 'Unit conversion; marker lengths are in yards.'],
  ['SPREADING_TABLE_LENGTH', 'yd', 'derived', 'B3, G6', 'Table length in yards (EQ10).'],
  ['LAB_TABLE_LENGTHS_M', 'm', 'what-if', '—', 'Table lengths the engine can run (24 and 27 m are hypothetical); no page control.'],
  ['LAY_NEEDS_FULL_LENGTH', 'flag', 'conservative', 'G6', 'true: a lay starts only when its whole length is free.'],
  ['MACHINE_FILL_TARGET', 'share of staffed time', 'heuristic', 'C1.4, E10', 'Queued spreading kept under this share of a spreader\'s staffed time (S1–S3 planner).'],
  ['SPREAD_MIN_PER_LAYER_PER_YARD', 'min per layer per yd', 'rule', 'G2', 'Spreading rate (0.80 / 8.5).'],
  ['CUT_MIN_PER_LAYER_PER_YARD', 'min per layer per yd', 'rule', 'G2', 'Cutting rate (0.40 / 8.5).'],
  ['REQUIRED_PIECES_PER_DAY', 'pieces per day', 'requirement', 'B7', 'Pieces Central Cutting must cut a day.'],
  ['ORDER_TYPE_PRIORITY', 'rank (lower first)', 'ESTIMATE', 'JS3, E6', 'Today\'s Job Sequence priority by order type; the live table was not supplied.'],
  ['ORDER_TYPE_PRIORITY_DEFAULT', 'rank', 'ESTIMATE', 'JS3', 'Rank of any other or empty order type.'],
  ['LIVE_FLOOR', 'flag', 'published floor', 'LF1', 'true: the live floor (re-plan, readiness). false = the floor of 2026-11-09, before/after only.'],
  ['REPLAN_MINUTES', 'min', 'rule', 'LF1', 'The Job Sequence re-plans this often, around the clock.'],
  ['PLAN_HORIZON_HOURS', 'h', 'rule', 'LF2', 'Each re-plan fills the spreaders\' staffed time this far ahead.'],
  ['C_SETUP_MINUTES_MIN_TENTHS', 'tenths of a min', 'ESTIMATE', 'G3, E7', 'Shortest Type C setup.'],
  ['C_SETUP_MINUTES_MAX_TENTHS', 'tenths of a min', 'ESTIMATE', 'G3, E7', 'Longest Type C setup.'],
  ['C_SETUP_HASH_OFFSET', '—', 'algorithm', '—', 'FNV-1a 32-bit offset basis (deterministic hash).'],
  ['C_SETUP_HASH_PRIME', '—', 'algorithm', '—', 'FNV-1a 32-bit prime.'],
  ['C_SETUP_PER_C_ROW', 'flag', 'decision', 'G3', 'false: one setup per B table, however many Type C rows it has.'],
  ['PULL_AHEAD_DAYS', 'plan dates', 'Lab add-on', 'C4.1', 'Plan dates a spreader may reach ahead (the add-on\'s value).'],
  ['RELAX_ARRIVAL_LEAD_MIN_H', 'h before first plan date', 'ESTIMATE', 'R4, E4', 'Latest fabric arrival before the batch\'s first plan date.'],
  ['RELAX_ARRIVAL_LEAD_MAX_H', 'h before first plan date', 'ESTIMATE', 'R4, E4', 'Earliest fabric arrival before the batch\'s first plan date.'],
  ['CUT_SETUP_MO_COLOR_MINUTES', 'min', 'ESTIMATE', 'T3, E2', 'Cutter changeover on an MO or colour change.'],
  ['CUT_TRAVEL_MINUTES', 'min', 'ESTIMATE', 'T4, E3', 'Cutter moving to a different spreader.'],
  ['LAB_SHIFT_OPTIONS', 'options', 'Lab option', 'C4.2', 'Shift choices on the page.'],
  ['DATA_FILE', 'path', 'input', '—', 'The source workbook.'],
  ['DATA_SHEET', 'sheet', 'input', '—', 'The sheet read.'],
  ['PIN_DATA_FILE', 'path', 'input', '—', 'The 20-date fixture, read only by npm run regress.'],
  ['WEBSITE_MONTHS', 'months', 'scope', 'SIM10', 'The published scope.'],
];

// derived values: computed here from A and the layout, never typed. [name, unit, formula ID, description, fn]
const LAYOUT = M.machineLayout(A.CUT_GROUPS);
const uniq = xs => [...new Set(xs)];
const DERIVED = [
  ['SPREADERS', 'machines', 'EQ9', 'Spreading machines on the floor.', () => LAYOUT.spreaders.length],
  ['CUTTERS', 'machines', 'EQ9', 'Cutting machines on the floor.', () => Object.keys(LAYOUT.cut_groups).length],
  ['STAFFED_MIN_DAY_MACHINE', 'min per day', 'EQ9', 'Staffed minutes of a day-only machine, net of breaks.',
    () => uniq(LAYOUT.spreaders.filter(m => !A.NIGHT_SHIFT_SPREADERS.has(m)).map(m => LAYOUT.machine_minutes[m])).join(' / ')],
  ['STAFFED_MIN_NIGHT_MACHINE', 'min per day', 'EQ9', 'Staffed minutes of a machine that also works nights, net of breaks.',
    () => uniq(LAYOUT.spreaders.filter(m => A.NIGHT_SHIFT_SPREADERS.has(m)).map(m => LAYOUT.machine_minutes[m])).join(' / ')],
  ['C_SETUP_RANGE', 'min', 'EQ5', 'Type C setup range.', () => `${A.C_SETUP_MINUTES_MIN_TENTHS / 10}–${A.C_SETUP_MINUTES_MAX_TENTHS / 10}`],
];

// ------------------------------------------------------------------ entities and attributes
// [entity, attribute, type, unit, source, formula ID, description]
const ENTITIES = [
  ['Table', 'table_no', 'text', '—', 'HaveCut: Table No', '', 'Spreading table number; joins Type C rows to their B table.'],
  ['Table', 'mo', 'text', '—', 'HaveCut: MO', '', 'Manufacturing order. Key for pairing, combine and recall.'],
  ['Table', 'style', 'text', '—', 'HaveCut: STYLE', '', 'Carried, not used in any decision.'],
  ['Table', 'color', 'text', '—', 'HaveCut: Color', '', 'Colour. Key for pairing, combine and recall.'],
  ['Table', 'batch', 'text', '—', 'HaveCut: Batch No', '', 'Fabric batch.'],
  ['Table', 'lot', 'text', '—', 'HaveCut: Lot', '', 'Always 1 in the data; status test only.'],
  ['Table', 'plan_date', 'date', '—', 'HaveCut: Plan Date', '', 'Plan date (Excel serial, read raw).'],
  ['Table', 'marker_ratio', 'text', 'size/count list', 'HaveCut: Marker Ratio', '', 'Pieces per layer by size, e.g. "XS/1,S/1,M/4".'],
  ['Table', 'layers', 'integer', 'layers', 'HaveCut: Act LayerQty', '', 'Layers spread.'],
  ['Table', 'marker_length', 'number', 'yd', 'HaveCut: Marker Length', '', 'Marker length; table length the lay takes.'],
  ['Table', 'order_type', 'text', '—', 'HaveCut: 订单类型', '', 'QR / Normal / SQR: today\'s Job Sequence priority.'],
  ['Table', 'marker_date', 'datetime', '—', 'HaveCut: Marker Date', '', 'When the marker is ready.'],
  ['Table', 'pull_date', 'datetime', '—', 'HaveCut: Pull Date', '', 'Actual end of spreading on the real floor; validation only.'],
  ['Table', 'needs_trolleys', 'boolean', '—', 'derived', '', 'Every size is in the film map (J3).'],
  ['Table', 'pieces_by_size', 'map', 'pieces', 'derived', 'EQ1', 'Pieces of each size; empty for tables outside the film map.'],
  ['Table', 'pieces_total', 'integer', 'pieces', 'derived', 'EQ2', 'Every piece the table cuts (equals Cut Qty).'],
  ['Table', 'c_setup_minutes', 'number', 'min', 'derived', 'EQ5', 'Type C setup added to spreading.'],
  ['Table', 'spread_minutes', 'number', 'min', 'derived', 'EQ3', 'Spreading time.'],
  ['Table', 'cut_minutes', 'number', 'min', 'derived', 'EQ4', 'Cutting time, before changeover and moving.'],
  ['Table', 'marker_rel', 'number', 'min after the plan date\'s 07:15', 'derived', 'EQ6', 'When the marker is ready, on the model clock.'],
  ['Table', 'ready_time', 'number', 'min on the model clock', 'derived', 'EQ8', 'Earliest start.'],
  ['Table', 'has_pattern', 'boolean', '—', 'derived', '', 'Marker Date is filled (status display).'],
  ['Table', 'has_fabric', 'boolean', '—', 'derived', '', 'Lot and Batch No are filled (status display).'],
  ['Table', 'is_batch_last', 'boolean', '—', 'derived', '', 'Last table of its batch by Pull Date, over the whole file (status display).'],
  ['Table', 'machine', 'text', '—', 'simulated', '', 'Spreader the table is spread on.'],
  ['Table', 'cutter', 'text', '—', 'simulated', '', 'Cutter that cuts it.'],
  ['Table', 'spread_start', 'number', 'min on the model clock', 'simulated', 'EQ12', 'Start of spreading.'],
  ['Table', 'spread_end', 'number', 'min on the model clock', 'simulated', 'EQ3', 'End of spreading.'],
  ['Table', 'cut_start', 'number', 'min on the model clock', 'simulated', 'EQ15', 'Start of cutting (after changeover and moving).'],
  ['Table', 'cut_end', 'number', 'min on the model clock', 'simulated', 'EQ15', 'End of cutting. Never rounded.'],
  ['Table', 'blocked_minutes', 'number', 'min', 'simulated', 'EQ12', 'Staffed time the spreader waited for table length.'],
  ['Table', 'cut_setup_minutes', 'number', 'min', 'simulated', 'EQ13', 'Cutter changeover before this cut.'],
  ['Table', 'cut_travel_minutes', 'number', 'min', 'simulated', 'EQ14', 'Cutter moving before this cut.'],
  ['Batch', 'batch_no', 'text', '—', 'HaveCut: Batch No', '', 'Fabric batch.'],
  ['Batch', 'first_plan_date', 'date', '—', 'derived', '', 'Earliest plan date of the batch over the whole file.'],
  ['Batch', 'fabric_arrival', 'number', 'min on the model clock', 'derived', 'EQ7', 'Fabric arrival (ESTIMATE).'],
  ['Batch', 'fabric_ready', 'number', 'min on the model clock', 'derived', 'EQ7', 'Fabric relaxed and ready to spread.'],
  ['Garment size', 'size', 'text', '—', 'HaveCut: Marker Ratio', '', 'Garment size.'],
  ['Garment size', 'film_width', 'number', 'cm', 'parameter: FILM_SIZE_BY_GARMENT_SIZE', '', 'Film the size is cut on (H5).'],
  ['Pair', 'tables', 'list', 'tables', 'simulated', 'EQ18', 'One or two tables placed as one unit (S1–S3).'],
  ['Pair', 'spread_work', 'number', 'min', 'derived', 'EQ3', 'Σ spread_minutes of its tables.'],
  ['Pair', 'cut_work', 'number', 'min', 'derived', 'EQ4', 'Σ cut_minutes of its tables.'],
  ['Compartment', 'film', 'number', 'cm', 'derived', 'EQ16', 'Film width of its size.'],
  ['Compartment', 'size', 'text', '—', 'derived', 'EQ16', 'One size per compartment (H4).'],
  ['Compartment', 'batch', 'text', '—', 'derived', 'EQ16', 'One batch per compartment (H4).'],
  ['Compartment', 'quantity', 'integer', 'garments', 'derived', 'EQ16', 'At most COMPARTMENT_CAP.'],
  ['Trolley', 'film', 'number', 'cm', 'simulated', 'EQ17', 'One film per trolley (H4).'],
  ['Trolley', 'compartments', 'integer', 'compartments', 'simulated', 'EQ17', 'Opened compartments, at most TROLLEY_COMPARTMENTS.'],
  ['Trolley', 'batches', 'set', 'batches', 'simulated', 'EQ20', 'Batches carried, at most the batch cap.'],
  ['Trolley', 'tables', 'list', 'tables', 'simulated', '', 'Tables whose panels it carries.'],
  ['Trolley', 'parked_at', 'number', 'min on the model clock', 'simulated', 'EQ21', 'When it started waiting in CCT WIP.'],
  ['Trolley', 'recalled', 'text', '—', 'simulated', '', 'Recalled for the same batch or another batch.'],
  ['Spreader', 'id', 'text', '—', 'parameter: CUT_GROUPS', '', '24-01 … 24-13.'],
  ['Spreader', 'cut_group', 'text', '—', 'parameter: CUT_GROUPS', '', 'Its primary cutter (F2).'],
  ['Spreader', 'second_cutter', 'text', '—', 'parameter: FLEXIBLE_CUT', '', '24-03 and 24-05 only (F8).'],
  ['Spreader', 'night', 'boolean', '—', 'parameter: NIGHT_SHIFT_SPREADERS', '', 'Also works nights.'],
  ['Spreader', 'staffed_minutes', 'number', 'min per day', 'derived', 'EQ9', 'Staffed time net of breaks.'],
  ['Spreader', 'table_length', 'number', 'yd', 'parameter: SPREADING_TABLE_LENGTH', 'EQ10', 'Length of its spreading table.'],
  ['Spreader', 'lays', 'list', '[length, free from, cut end]', 'simulated', 'EQ11', 'Lays on the table.'],
  ['Cutter', 'id', 'text', '—', 'parameter: CUT_GROUPS', '', '24MC1 … 24MC5.'],
  ['Cutter', 'spreaders_served', 'list', '—', 'parameters: CUT_GROUPS, FLEXIBLE_CUT', '', 'Its own group plus F8 spreaders.'],
  ['Cutter', 'night', 'boolean', '—', 'parameter: NIGHT_SHIFT_CUTTERS', '', 'Also works nights.'],
  ['Cutter', 'staffed_minutes', 'number', 'min per day', 'derived', 'EQ9', 'Staffed time net of breaks.'],
  ['Cutter', 'last_cut', 'tuple', '(MO, colour, spreader)', 'simulated', 'EQ13', 'Drives changeover and moving.'],
  ['Shift', 'window', 'interval', 'min after 07:15', 'parameters: DAY_SHIFT, NIGHT_SHIFT', '', 'Start and end.'],
  ['Shift', 'breaks', 'intervals', 'min after 07:15', 'parameters: DAY_BREAKS, NIGHT_BREAKS', '', 'Breaks inside the window.'],
  ['Plan date', 'date', 'date', '—', 'HaveCut: Plan Date', '', 'One plan date.'],
  ['Plan date', 'offset', 'number', 'min from the first date\'s 07:15', 'derived', '', 'Calendar minutes to this date\'s 07:15.'],
  ['Scenario', 'sequencing_mode', 'text', '—', 'scenario', '', 'today (S0) / same_batch / cross_batch.'],
  ['Scenario', 'max_batches', 'integer', 'batches', 'scenario', 'EQ20', '1, 2 or 3 (2 and 3 behave the same).'],
  ['Scenario', 'wip_hold_minutes', 'integer', 'min', 'scenario', 'EQ21', 'WIP hold length.'],
  ['Scenario', 'hold_any_workstation', 'boolean', '—', 'scenario', '', 'Recall to any workstation.'],
  ['Scenario', 'mo_one_group', 'boolean', '—', 'scenario', '', 'Option: keep an MO on one cut group (C1.5).'],
];

// ------------------------------------------------------------------ formulas
// [ID, quantity, level, formula, inputs (attributes Entity.attr, PARAMETERS, EQn), unit, code, RULES.md ID(s)]
const FORMULAS = [
  ['EQ1', 'Pieces by size', 'table', 'pieces[size] = ratio[size] × layers, for tables whose sizes are all in the film map; insertion order kept', ['Table.marker_ratio', 'Table.layers', 'UNIVERSAL_SIZES'], 'pieces', 'model.js loadDays', 'J3'],
  ['EQ2', 'Pieces total', 'table', 'Σ over sizes of ratio[size] × layers (all sizes)', ['Table.marker_ratio', 'Table.layers'], 'pieces', 'model.js loadDays', 'M6'],
  ['EQ3', 'Spread minutes', 'table', 'layers × marker_length × SPREAD_MIN_PER_LAYER_PER_YARD + c_setup_minutes', ['Table.layers', 'Table.marker_length', 'SPREAD_MIN_PER_LAYER_PER_YARD', 'EQ5'], 'min', 'model.js loadDays', 'G2'],
  ['EQ4', 'Cut minutes', 'table', 'layers × marker_length × CUT_MIN_PER_LAYER_PER_YARD', ['Table.layers', 'Table.marker_length', 'CUT_MIN_PER_LAYER_PER_YARD'], 'min', 'model.js loadDays', 'G2'],
  ['EQ5', 'Type C setup', 'table', '(C_SETUP_MINUTES_MIN_TENTHS + FNV1a32("plan date|table_no") mod (C_SETUP_MINUTES_MAX_TENTHS − C_SETUP_MINUTES_MIN_TENTHS + 1)) ÷ 10 if the B table has a Type C row, else 0; × the C-row count only if C_SETUP_PER_C_ROW', ['Table.plan_date', 'Table.table_no', 'C_SETUP_MINUTES_MIN_TENTHS', 'C_SETUP_MINUTES_MAX_TENTHS', 'C_SETUP_HASH_OFFSET', 'C_SETUP_HASH_PRIME', 'C_SETUP_PER_C_ROW'], 'min', 'model.js cSetupMinutes', 'G3'],
  ['EQ6', 'Marker ready', 'table', 'marker_rel = Marker Date − (plan date 00:00 + SHIFT_START_MINUTE), in minutes (negative = before 07:15)', ['Table.marker_date', 'Table.plan_date', 'SHIFT_START_MINUTE'], 'min', 'model.js loadDays', 'R2'],
  ['EQ7', 'Fabric ready', 'batch', 'lead = RELAX_ARRIVAL_LEAD_MIN_H × 60 + FNV1a32("relax|" + batch) mod ((RELAX_ARRIVAL_LEAD_MAX_H − RELAX_ARRIVAL_LEAD_MIN_H) × 60 + 1); arrival = first plan date\'s 07:15 − lead; fabric_ready = arrival + RELAX_HOURS × 60', ['Batch.batch_no', 'Batch.first_plan_date', 'RELAX_ARRIVAL_LEAD_MIN_H', 'RELAX_ARRIVAL_LEAD_MAX_H', 'RELAX_HOURS'], 'min', 'model.js carryTimeline; lab.js run', 'R3, R4'],
  ['EQ8', 'Ready time', 'table', 'max(plan date\'s 07:15, plan date\'s 07:15 + marker_rel, fabric_ready); with pull-ahead the first term is the 07:15 of the plan date PULL_AHEAD_DAYS earlier', ['Plan date.offset', 'EQ6', 'EQ7', 'PULL_AHEAD_DAYS'], 'min', 'model.js carryTimeline; lab.js run', 'R1, R2, R3'],
  ['EQ9', 'Staffed minutes', 'machine', 'Σ over working spans of (end − start); the window runs from DAY_SHIFT start to DAY_SHIFT end (night machines: to NIGHT_SHIFT end), minus the breaks inside it when BREAKS_STOP_MACHINES', ['DAY_SHIFT', 'NIGHT_SHIFT', 'DAY_BREAKS', 'NIGHT_BREAKS', 'BREAKS_STOP_MACHINES', 'NIGHT_SHIFT_SPREADERS', 'NIGHT_SHIFT_CUTTERS'], 'min per day', 'model.js workingIntervals, machineLayout', 'B1, B2'],
  ['EQ10', 'Table length in yards', 'machine', 'SPREADING_TABLE_LENGTH_M × YARDS_PER_METRE', ['SPREADING_TABLE_LENGTH_M', 'YARDS_PER_METRE'], 'yd', 'assumptions.js', 'B3'],
  ['EQ11', 'Free table length at time t', 'machine', 'table length − Σ used(lay); used = length if t ≤ free_from; 0 if t ≥ cut_end; else length × (cut_end − t) ÷ (cut_end − free_from). The cutter gives length back linearly', ['Spreader.table_length', 'Spreader.lays'], 'yd', 'model.js / floor.js freeLength', 'G6'],
  ['EQ12', 'Lay start and blocking', 'table', 'start = earliest t at or after the spreader is free where free length ≥ marker_length (LAY_NEEDS_FULL_LENGTH); blocked_minutes = staffed minutes between the two', ['EQ11', 'Table.marker_length', 'LAY_NEEDS_FULL_LENGTH'], 'min', 'model.js / floor.js roomAt', 'G6'],
  ['EQ13', 'Cutter changeover', 'table', 'CUT_SETUP_MO_COLOR_MINUTES if the cutter\'s last cut differs in MO or colour, else 0', ['Cutter.last_cut', 'Table.mo', 'Table.color', 'CUT_SETUP_MO_COLOR_MINUTES'], 'min', 'model.js carryTimeline; floor.js run', 'T3'],
  ['EQ14', 'Cutter moving', 'table', 'CUT_TRAVEL_MINUTES if the cutter\'s last cut was on a different spreader, else 0', ['Cutter.last_cut', 'Table.machine', 'CUT_TRAVEL_MINUTES'], 'min', 'model.js carryTimeline; floor.js run', 'T4'],
  ['EQ15', 'Cut start and end', 'table', 'occupy the cutter\'s staffed spans from max(spread_end, cutter free) for cut_minutes + changeover + moving; the table stays occupied through changeover and moving', ['EQ4', 'EQ13', 'EQ14', 'Table.spread_end', 'Cutter.staffed_minutes'], 'min', 'model.js occupy; floor.js run', 'T5'],
  ['EQ16', 'Compartments of a table', 'table', 'for each size in order: floor(qty ÷ COMPARTMENT_CAP) full compartments, plus one with the remainder if any; grouped by film (FILM_SIZE_BY_GARMENT_SIZE); sizes never merge', ['EQ1', 'COMPARTMENT_CAP', 'FILM_SIZE_BY_GARMENT_SIZE'], 'compartments', 'model.js compartmentsFor', 'H1, H4, H5'],
  ['EQ17', 'Trolleys for a set of compartments', 'table', 'Σ over films of ceil(compartments of that film ÷ TROLLEY_COMPARTMENTS)', ['EQ16', 'TROLLEY_COMPARTMENTS'], 'trolleys', 'model.js trolleysFor', 'H3, H4'],
  ['EQ18', 'Two tables may share a trolley', 'table pair', 'both in the film map AND same MO AND same colour AND (same batch OR cross-batch) AND trolleys(combined) ≤ MAX_TROLLEYS_PER_COMBINE', ['Table.needs_trolleys', 'Table.mo', 'Table.color', 'Table.batch', 'EQ19', 'MAX_TROLLEYS_PER_COMBINE'], 'yes / no', 'model.js canCombine', 'H8, H9'],
  ['EQ19', 'Combined compartments', 'table pair', 'same batch: compartments of the merged pieces (same-size remainders merge up to COMPARTMENT_CAP); different batches: each table\'s compartments side by side', ['EQ1', 'EQ16', 'Table.batch', 'COMPARTMENT_CAP'], 'compartments', 'model.js combinedCompartments', 'C2.4'],
  ['EQ20', 'Batch cap of a trolley', 'trolley', 'min(scenario max_batches, MAX_BATCHES_PER_TROLLEY) when TOPUP_BATCH_CAP_FROM_SCENARIO', ['Scenario.max_batches', 'MAX_BATCHES_PER_TROLLEY', 'TOPUP_BATCH_CAP_FROM_SCENARIO'], 'batches', 'model.js loadTrolleys', 'C2.1, C2.3'],
  ['EQ21', 'WIP hold expiry', 'trolley', 'a waiting trolley is sent on once now − parked_at > hold (WIP_HOLD_MINUTES in S3)', ['Trolley.parked_at', 'Scenario.wip_hold_minutes', 'WIP_HOLD_MINUTES'], 'min', 'model.js loadTrolleys', 'C3.2'],
  ['EQ22', 'Room to park', 'plan date', 'park a part-filled trolley only while fewer than TROLLEY_BAYS are waiting; otherwise send it on', ['TROLLEY_BAYS'], 'trolleys', 'model.js loadTrolleys', 'H7, C3.6'],
  ['EQ23', 'S0 cutter choice', 'plan date', 'score(c) = committed spread minutes of c\'s spreaders ÷ spreadCount(c), spreadCount(c) = Σ over spreaders mapped to c of 1 ÷ (cutters that spreader maps to); lowest wins, preferring a cutter already holding the same MO + batch', ['CUT_GROUPS', 'FLEXIBLE_CUT', 'EQ3'], 'min per spreader', 'model.js sequenceJobSeq', 'JS1'],
  ['EQ24', 'S0 spreader and table choice', 'plan date', 'the spreader with the fewest committed spread minutes takes, among its cutter\'s waiting tables, the lowest (ORDER_TYPE_PRIORITY, spread_minutes, plan order)', ['ORDER_TYPE_PRIORITY', 'ORDER_TYPE_PRIORITY_DEFAULT', 'Table.order_type', 'EQ3'], '—', 'model.js sequenceJobSeq', 'JS2, JS3, JS4'],
  ['EQ25', 'S1–S3 cut group choice', 'plan date', 'max((group spread load + unit spread) ÷ group spreader staffed minutes, (group cut load + unit cut) ÷ cutter staffed minutes); lowest wins', ['Pair.spread_work', 'Pair.cut_work', 'EQ9'], 'share of staffed time', 'model.js sequencePairs', 'C1.3'],
  ['EQ26', 'S1–S3 spreader choice', 'plan date', 'least-loaded spreader of the group with queued spread minutes + work ≤ staffed minutes × MACHINE_FILL_TARGET; else any spreader that fits; else the lowest load ÷ staffed minutes', ['Pair.spread_work', 'EQ9', 'MACHINE_FILL_TARGET'], '—', 'model.js pickMachine', 'C1.4'],
  ['EQ27', 'Re-plan window', 'floor', 'every REPLAN_MINUTES, ready tables not yet started are taken, oldest plan date first, until their spread minutes fill the spreaders\' staffed time in the next PLAN_HORIZON_HOURS', ['REPLAN_MINUTES', 'PLAN_HORIZON_HOURS', 'EQ8', 'EQ3', 'EQ9'], '—', 'floor.js run', 'LF1, LF2'],
  ['EQ28', 'Trolley utilization', 'pooled', '100 × Σ compartments ÷ (TROLLEY_COMPARTMENTS × Σ trolleys), over all plan dates', ['EQ16', 'EQ17', 'TROLLEY_COMPARTMENTS'], '%', 'model.js pool', 'M1, H6'],
  ['EQ29', 'Compartment fill', 'pooled', '100 × Σ pieces loaded ÷ (COMPARTMENT_CAP × Σ compartments)', ['EQ1', 'EQ16', 'COMPARTMENT_CAP'], '%', 'model.js pool', 'M2'],
  ['EQ30', 'Trolleys a day', 'pooled', 'Σ trolleys ÷ plan dates', ['EQ17'], 'trolleys per day', 'model.js pool', 'M3'],
  ['EQ31', 'Pieces per trolley', 'pooled', 'Σ pieces loaded ÷ Σ trolleys', ['EQ1', 'EQ17'], 'pieces', 'model.js pool', 'M1'],
  ['EQ32', 'Garments per trolley capacity', 'pooled', 'COMPARTMENT_CAP × Σ compartments ÷ Σ trolleys', ['COMPARTMENT_CAP', 'EQ16', 'EQ17'], 'garments', 'model.js pool', 'M1'],
  ['EQ33', 'Fleet needed', 'pooled', 'trolleys a day × CYCLE_DAYS_ESTIMATED (or the page\'s round trip; CYCLE_DAYS_ALLOWED for the allowance)', ['EQ30', 'CYCLE_DAYS_ESTIMATED', 'CYCLE_DAYS_ALLOWED'], 'trolleys', 'model.js fleetRequired', 'M4'],
  ['EQ34', 'Longest round trip covered', 'pooled', 'FLEET_SIZE ÷ trolleys a day', ['FLEET_SIZE', 'EQ30'], 'days', 'model.js longestSustainableCycle', 'M5'],
  ['EQ35', 'Fleet gap', 'pooled', 'FLEET_SIZE − fleet needed (negative = short)', ['FLEET_SIZE', 'EQ33'], 'trolleys', 'tools/build.js', 'B4'],
  ['EQ36', 'Pieces cut a day', 'pooled', 'pieces of tables finished by the last plan date\'s window end ÷ plan dates', ['EQ2', 'EQ15'], 'pieces per day', 'lab.js finish', 'M6'],
  ['EQ37', 'Backlog', 'pooled', 'Σ pieces_total − pieces cut a day × plan dates', ['EQ2', 'EQ36'], 'pieces', 'lab.js finish', 'M6'],
  ['EQ38', 'Hours per 100k pieces', 'pooled', 'staffed shift-window hours to the last cut ÷ (Σ pieces ÷ REQUIRED_PIECES_PER_DAY)', ['EQ2', 'REQUIRED_PIECES_PER_DAY'], 'h', 'lab.js finish', 'B7'],
  ['EQ39', '100k plan', 'plan', 'the real tables in plan order, dealt into plan dates that close once they hold ≥ REQUIRED_PIECES_PER_DAY pieces; the tail that cannot fill a date is left out', ['EQ2', 'REQUIRED_PIECES_PER_DAY'], 'plan dates', 'lab.js rebucket', 'B7'],
  ['EQ40', 'Spreading blocked %', 'plan date', '100 × Σ staffed G6 wait ÷ Σ (spread + wait) over the date\'s tables; mean of the dates', ['EQ12', 'EQ3'], '%', 'model.js runCarry', 'G6'],
  ['EQ41', 'Overrun minutes', 'plan date', 'staffed spreading minutes of the date\'s tables after their machine\'s own window closed', ['EQ9', 'Table.spread_end'], 'min', 'model.js runCarry', '—'],
  ['EQ42', 'Cutter lost time', 'pooled', 'setup + travel + waiting; waiting = staffed − cutting − setup − travel', ['EQ9', 'EQ13', 'EQ14', 'EQ4'], 'h per working day', 'lab.js finish', 'T3, T4'],
];

// ------------------------------------------------------------------ data statistics (computed)
const r2 = x => bankersRound(x, 2), r1 = x => bankersRound(x, 1), r0 = x => bankersRound(x, 0);
const mean = xs => xs.reduce((a, b) => a + b, 0) / xs.length;
const pct = (xs, p) => { const s = xs.slice().sort((a, b) => a - b); return s[Math.floor(p * (s.length - 1))]; };
const share = (n, d) => r1(100 * n / d);

function statistics(scope, days) {
  const dates = Object.keys(days).sort();
  const ts = dates.flatMap(d => days[d]);
  const n = ts.length;
  const uni = ts.filter(t => t.needs_trolleys);
  const loaded = uni.reduce((s, t) => s + Object.values(t.pieces_by_size).reduce((a, b) => a + b, 0), 0);
  const total = ts.reduce((s, t) => s + t.pieces_total, 0);
  const layers = ts.map(t => t.layers), len = ts.map(t => t.marker_length);
  const spread = ts.map(t => t.spread_minutes), cut = ts.map(t => t.cut_minutes);
  const batches = new Map(); for (const t of ts) batches.set(String(t.batch), (batches.get(String(t.batch)) || 0) + 1);
  const withC = ts.filter(t => t.c_setup_minutes > 0);
  const withMk = ts.filter(t => t.has_pattern);
  const ot = {}; for (const t of ts) { const k = t.order_type || '(empty)'; ot[k] = (ot[k] || 0) + 1; }
  const rows = [
    ['plan dates', dates.length, 'dates'],
    ['tables (Type B, modelled)', n, 'tables'],
    ['tables a plan date', r1(n / dates.length), 'tables'],
    ['pieces cut, total (all sizes)', total, 'pieces'],
    ['pieces a plan date (all sizes)', r0(total / dates.length), 'pieces'],
    ['pieces a plan date reaching trolleys (film-map sizes)', r0(loaded / dates.length), 'pieces'],
    ['tables with every size in the film map', share(uni.length, n), '%'],
    ['layers a table: mean', r1(mean(layers)), 'layers'],
    ['layers a table: p10 / median / p90', `${pct(layers, 0.1)} / ${pct(layers, 0.5)} / ${pct(layers, 0.9)}`, 'layers'],
    ['marker length: mean', r2(mean(len)), 'yd'],
    ['marker length: p10 / median / p90', `${r2(pct(len, 0.1))} / ${r2(pct(len, 0.5))} / ${r2(pct(len, 0.9))}`, 'yd'],
    ['marker length: longest', r2(Math.max(...len)), 'yd'],
    ['spread minutes a table: mean / median', `${r1(mean(spread))} / ${r1(pct(spread, 0.5))}`, 'min'],
    ['cut minutes a table: mean / median', `${r1(mean(cut))} / ${r1(pct(cut, 0.5))}`, 'min'],
    ['MOs', uniq(ts.map(t => String(t.mo))).length, 'MOs'],
    ['MO + colour combinations', uniq(ts.map(t => `${t.mo}\x01${t.color}`)).length, 'combinations'],
    ['batches', batches.size, 'batches'],
    ['tables a batch: mean', r2(n / batches.size), 'tables'],
    ['tables with a Type C setup', `${withC.length} (${share(withC.length, n)}%)`, 'tables'],
    ['Type C setup: mean of those', withC.length ? r2(mean(withC.map(t => t.c_setup_minutes))) : 0, 'min'],
    ['tables with a Marker Date', share(withMk.length, n), '%'],
    ['Marker Date after the plan date\'s 07:15', share(withMk.filter(t => t.marker_rel > 0).length, withMk.length), '% of tables with one'],
    ['Marker Date after the next day\'s 07:15', share(withMk.filter(t => t.marker_rel > 1440).length, withMk.length), '% of tables with one'],
    ['last table of its batch (stretch status)', share(ts.filter(t => t.is_batch_last).length, n), '%'],
    ['order types', Object.keys(ot).sort().map(k => `${k} ${ot[k]}`).join(', '), 'tables'],
  ];
  return rows.map(([stat, value, unit]) => [scope, stat, String(value), unit]);
}

// ------------------------------------------------------------------ helpers
function show(v) {
  if (v instanceof Set) return [...v].join(', ');
  if (typeof v === 'object' && v !== null) return JSON.stringify(v);
  return String(v);
}
const esc = s => String(s).replace(/\|/g, '\\|');
const mdTable = (head, rows) => [`| ${head.join(' | ')} |`, `|${head.map(() => '---').join('|')}|`,
  ...rows.map(r => `| ${r.map(esc).join(' | ')} |`)].join('\n');
const csv = (head, rows) => '﻿' + [head, ...rows].map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n') + '\n';

function ruleIds() {
  const ids = new Set();
  for (const line of fs.readFileSync(path.join(REPO, 'RULES.md'), 'utf8').split('\n')) {
    const m = /^\| ([^|]+?) \|/.exec(line);
    if (m && !/^-+$/.test(m[1])) for (const id of m[1].split(', ')) ids.add(id.trim());
  }
  return ids;
}

// ------------------------------------------------------------------ build
function build() {
  const errors = [];
  // asserts
  const documented = new Set(PARAMS.map(p => p[0]));
  for (const k of Object.keys(A)) if (!documented.has(k)) errors.push(`assumptions.js exports ${k} but it has no parameter row`);
  for (const p of PARAMS) if (!(p[0] in A)) errors.push(`parameter row ${p[0]} is not in assumptions.js`);
  const ids = ruleIds();
  const cite = (where, s) => { if (s && s !== '—') for (const id of s.split(', ')) if (!ids.has(id)) errors.push(`${where} cites ${id}, not in RULES.md`); };
  PARAMS.forEach(p => cite(p[0], p[3]));
  FORMULAS.forEach(f => cite(f[0], f[7]));
  const attrs = new Set(ENTITIES.map(e => `${e[0]}.${e[1]}`));
  const eqs = new Set(FORMULAS.map(f => f[0]));
  const derived = new Set(DERIVED.map(d => d[0]));
  for (const f of FORMULAS) for (const i of f[4]) if (!attrs.has(i) && !(i in A) && !eqs.has(i) && !derived.has(i)) errors.push(`${f[0]} input ${i} is not a known attribute, parameter or formula`);
  for (const e of ENTITIES) if (e[5] && !eqs.has(e[5])) errors.push(`${e[0]}.${e[1]} cites ${e[5]}, not a formula`);

  // used-by index
  const usedBy = {};
  for (const f of FORMULAS) for (const i of f[4]) (usedBy[i] = usedBy[i] || []).push(f[0]);

  const paramRows = PARAMS.map(([name, unit, status, rule, desc]) => [name, show(A[name]), unit, status, rule, (usedBy[name] || []).join(' '), desc]);
  const derivedRows = DERIVED.map(([name, unit, eq, desc, fn]) => [name, show(fn()), unit, 'derived', '—', '', `${desc} Computed by ${eq}.`]);
  const scenRows = S.HEADLINE.map(sc => [sc.name.replace(/\s+/g, ' ').trim(),
    `${sc.sequencing_mode} | ${sc.max_batches} batch(es) | hold ${sc.wip_hold_minutes} min | ${sc.wip_hold_minutes ? (sc.hold_any_workstation ? 'any workstation' : 'same workstation') : '—'}`]);
  const entityRows = ENTITIES.map(e => e.slice());
  const formulaRows = FORMULAS.map(([id, q, lvl, f, inputs, unit, code, rule]) => [id, q, lvl, f, inputs.join(', '), unit, code, rule]);

  const [allDays] = M.loadDays(path.join(REPO, A.DATA_FILE), true);
  const scoped = {}; for (const d of Object.keys(allDays)) if (A.WEBSITE_MONTHS.includes(d.slice(0, 7))) scoped[d] = allDays[d];
  const statRows = [...statistics('April–June (published scope)', scoped), ...statistics('full file', allDays)];

  // Markdown
  const H = {
    ent: ['Entity', 'Attribute', 'Type', 'Unit', 'Source', 'Formula', 'Description'],
    par: ['Name', 'Current value', 'Unit', 'Status', 'RULES.md', 'Used by', 'Description'],
    frm: ['ID', 'Quantity', 'Level', 'Formula', 'Inputs', 'Unit', 'Code', 'RULES.md'],
    sta: ['Scope', 'Statistic', 'Value', 'Unit'],
  };
  const entityMap = uniq(ENTITIES.map(e => e[0])).map(en => `- **${en}**: ${ENTITIES.filter(e => e[0] === en).map(e => e[1]).join(', ')}`).join('\n');
  const md = `<!-- GENERATED by tools/data_model.js. Do not edit: change the code or tools/assumptions.js, then run npm run datamodel. -->

# Data model

The register of what the simulation calculates with: the **entities and their attributes**, the
**parameters** with their **current values**, every **formula**, and **statistics** of the current data.
It is generated from the code (\`npm run datamodel\`), so the values are always the ones the model uses.
The same content is in CSV files for import into a larger data model or Excel:
[entities.csv](data_model/entities.csv), [parameters.csv](data_model/parameters.csv),
[formulas.csv](data_model/formulas.csv), [statistics.csv](data_model/statistics.csv).

The rules behind each value are in [RULES.md](../RULES.md) (IDs in the "RULES.md" column); how each step
runs is in [SIM_SPEC.md](../SIM_SPEC.md). **ESTIMATE** marks a value that has not been measured.

- [Entity map](#entity-map)
- [Attributes](#attributes)
- [Parameters](#parameters)
- [Formulas](#formulas)
- [Data statistics](#data-statistics)

## Entity map

${entityMap}

Relations: a **plan date** holds **tables**; a table belongs to one **batch**, **MO** and colour, and has
pieces of one or more **garment sizes**. The Job Sequence puts each table (alone or in a **pair**) on one
**spreader**; the spreader's **cutter** cuts it. Its pieces go into **compartments** (one size, one batch,
up to the compartment cap), and compartments go onto **trolleys** (one film, up to the trolley's
compartments). Machines work in **shifts**. A **scenario** sets the rules.

## Attributes

Source: \`HaveCut: <column>\` = read from the workbook; \`derived\` = computed when the data is read;
\`simulated\` = set by the simulation; \`parameter\` = from tools/assumptions.js.

${mdTable(H.ent, entityRows)}

## Parameters

Current values, read from \`tools/assumptions.js\` when this file was generated. "Used by" lists the
formulas that read the parameter.

${mdTable(H.par, paramRows)}

**Derived values** (computed from the parameters above and the machine layout):

${mdTable(H.par, derivedRows)}

**The published scenarios** (\`tools/scenarios.js\`):

${mdTable(['Scenario', 'Sequencing | batches | WIP hold | recall'], scenRows)}

## Formulas

Level: table, table pair, batch, trolley, machine, plan date, floor, plan, or pooled over all plan dates.
Inputs name attributes (\`Entity.attribute\`), parameters (CAPITALS) or other formulas (\`EQn\`).

${mdTable(H.frm, formulaRows)}

## Data statistics

From the workbook (\`${A.DATA_FILE}\`, sheet \`${A.DATA_SHEET}\`), Type B tables as modelled (rule J2).
Percentiles are nearest-rank (the value at position floor(p × (n − 1)) of the sorted list).

${mdTable(H.sta, statRows)}
`;
  const files = {
    [OUT_MD]: md,
    [path.join(OUT_DIR, 'entities.csv')]: csv(H.ent, entityRows),
    [path.join(OUT_DIR, 'parameters.csv')]: csv(H.par, [...paramRows, ...derivedRows]),
    [path.join(OUT_DIR, 'formulas.csv')]: csv(H.frm, formulaRows),
    [path.join(OUT_DIR, 'statistics.csv')]: csv(H.sta, statRows),
  };
  return { errors, files };
}

const { errors, files } = build();
if (errors.length) { console.error('DATA MODEL ASSERTS FAILED:\n  ' + errors.join('\n  ')); process.exit(1); }
const rel = f => path.relative(REPO, f).replace(/\\/g, '/');
if (CHECK) {
  const stale = Object.keys(files).filter(f => !fs.existsSync(f) || fs.readFileSync(f, 'utf8') !== files[f]);
  if (stale.length) { console.error('Out of date (run npm run datamodel): ' + stale.map(rel).join(', ')); process.exit(1); }
  console.log(`=> data model is current (${Object.keys(files).length} files)`);
} else {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  for (const f of Object.keys(files)) { fs.writeFileSync(f, files[f], 'utf8'); console.log('wrote ' + rel(f)); }
  console.log(`=> ${PARAMS.length} parameters, ${DERIVED.length} derived values, ${ENTITIES.length} attributes, ${FORMULAS.length} formulas; all asserts pass`);
}
