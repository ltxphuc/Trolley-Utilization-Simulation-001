'use strict';
/* SCENARIOS — mirrors scenarios.py exactly. */
const A = require('./assumptions');
const { makeScenario } = require('./model');

// S1 is same_batch (fixed 2026-09-08 — see scenarios.py's matching comment
// for why); S2/S3/HOLD_VARIANTS stay cross_batch, unchanged from before.
const HEADLINE = [
  makeScenario({ name: 'S0  Today', sequencing_mode: 'today', max_batches: 1, wip_hold_minutes: 0 }),
  makeScenario({ name: 'S1  + same-MO sequencing', sequencing_mode: 'same_batch', max_batches: 1, wip_hold_minutes: 0 }),
  makeScenario({ name: 'S2  + 2 batches per trolley', sequencing_mode: 'cross_batch', max_batches: 2, wip_hold_minutes: 0 }),
  makeScenario({
    name: 'S3  + WIP hold', sequencing_mode: 'cross_batch', max_batches: 2,
    wip_hold_minutes: A.WIP_HOLD_MINUTES, hold_any_workstation: A.WIP_HOLD_ANY_WORKSTATION,
  }),
];

const HOLD_VARIANTS = [
  makeScenario({ name: 'No hold', sequencing_mode: 'cross_batch', max_batches: 2, wip_hold_minutes: 0 }),
  makeScenario({ name: '1 h · same workstation only', sequencing_mode: 'cross_batch', max_batches: 2, wip_hold_minutes: 60, hold_any_workstation: false }),
  makeScenario({ name: '1 h · any workstation', sequencing_mode: 'cross_batch', max_batches: 2, wip_hold_minutes: 60, hold_any_workstation: true }),
  makeScenario({ name: '2 h · same workstation only', sequencing_mode: 'cross_batch', max_batches: 2, wip_hold_minutes: 120, hold_any_workstation: false }),
  makeScenario({ name: '2 h · any workstation', sequencing_mode: 'cross_batch', max_batches: 2, wip_hold_minutes: 120, hold_any_workstation: true }),
];

const SWEEP_HOLD_MINUTES = [0, 30, 60, 90, 120, 180, 240];
const SWEEP_MAX_BATCHES = [1, 2, 3];
const SWEEP_SEQUENCING_MODE = ['today', 'same_batch', 'cross_batch'];
const SWEEP_ANY_WORKSTATION = [false, true];

function sweepKey(sequencingMode, maxBatches, holdMinutes, anyWorkstation) {
  if (holdMinutes === 0) anyWorkstation = true;
  return `${sequencingMode}|${maxBatches}|${holdMinutes}|${anyWorkstation ? 1 : 0}`;
}

function sweepScenarios() {
  const out = new Map();
  for (const sequencingMode of SWEEP_SEQUENCING_MODE) {
    for (const maxBatches of SWEEP_MAX_BATCHES) {
      for (const hold of SWEEP_HOLD_MINUTES) {
        for (const anyWs of SWEEP_ANY_WORKSTATION) {
          const key = sweepKey(sequencingMode, maxBatches, hold, anyWs);
          if (out.has(key)) continue;
          out.set(key, makeScenario({
            name: key, sequencing_mode: sequencingMode, max_batches: maxBatches,
            wip_hold_minutes: hold, hold_any_workstation: anyWs,
          }));
        }
      }
    }
  }
  return out;   // Map, insertion order = same iteration order as Python's dict
}

module.exports = {
  HEADLINE, HOLD_VARIANTS,
  SWEEP_HOLD_MINUTES, SWEEP_MAX_BATCHES, SWEEP_SEQUENCING_MODE, SWEEP_ANY_WORKSTATION,
  sweepKey, sweepScenarios,
};
