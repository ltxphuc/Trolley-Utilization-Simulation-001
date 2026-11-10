# -*- coding: utf-8 -*-
"""
THE CROSS-LANGUAGE C-SETUP TEST

`tools/csetup-fixture.json` records what the Node port actually computed for 40
real (Plan Date, Table No) pairs: the seed string, its FNV-1a 32-bit hash, and
the resulting setup in tenths of a minute. This file asserts that Python's
`model._fnv1a32` and `model._c_setup_minutes` produce exactly the same values.

WHY THIS MATTERS. The C-table setup is no longer a flat 10 minutes; it is a
value in 8.0-10.0 chosen deterministically from the table's own identity (the
user's instruction, 2026-09-08). "Deterministically" is only worth anything if
BOTH implementations agree — otherwise `python run.py` and `node tools/build.js`
would publish different numbers from the same workbook, silently, and the parity
gate would have no fixed point to stand on.

The two languages can disagree in three specific places, and each is asserted
here rather than assumed:

  1. The hash. JS numbers are IEEE-754 doubles, so `h * 16777619` loses
     precision above 2**53. tools/model.js MUST use Math.imul; Python's ints are
     arbitrary precision and need an explicit & 0xFFFFFFFF instead.
  2. The table key. openpyxl hands back a Python int for an integer-valued cell;
     SheetJS hands back a JS number. str(123.0) is '123.0' but String(123) is
     '123', so the seed string could differ for the same table.
  3. The mapping to minutes. Written as one correctly-rounded division of a
     small exact integer, so both languages land on the same double.

THIS HAS NEVER BEEN EXECUTED. Python is not installed on the machine where the
range was implemented (python.exe on PATH is the 0-byte Microsoft Store stub).
Run it FIRST, before trusting any Python-built output:

    python -m pytest test_csetup.py -q        # or: python test_csetup.py

If it fails, the Node-built numbers in out/ and the Python ones will not agree,
and the discrepancy is in one of the three places above.
"""
import datetime
import json
import os

import model

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE = os.path.join(HERE, 'tools', 'csetup-fixture.json')


def _load():
    with open(FIXTURE, encoding='utf-8') as fh:
        return json.load(fh)


def test_constants_match_the_fixture():
    """The fixture was generated under a specific range and hash. If assumptions.py
    has moved since, every other assertion here is meaningless — so check first."""
    fx = _load()
    import assumptions as A
    assert fx['min_tenths'] == A.C_SETUP_MINUTES_MIN_TENTHS
    assert fx['max_tenths'] == A.C_SETUP_MINUTES_MAX_TENTHS
    assert fx['hash_offset'] == A.C_SETUP_HASH_OFFSET
    assert fx['hash_prime'] == A.C_SETUP_HASH_PRIME


def test_fnv1a32_matches_the_node_port():
    fx = _load()
    assert fx['triples'], 'fixture carries no triples'
    for t in fx['triples']:
        got = model._fnv1a32(t['seed'])
        assert got == t['fnv32'], (
            "FNV-1a disagrees for seed %r: python=%d node=%d. "
            "Check Math.imul in tools/model.js's fnv1a32 and the "
            "& 0xFFFFFFFF in model.py's _fnv1a32." % (t['seed'], got, t['fnv32']))


def test_setup_minutes_match_the_node_port():
    fx = _load()
    for t in fx['triples']:
        date_str, table_key = t['seed'].split('|', 1)
        day = datetime.date.fromisoformat(date_str)
        got = model._c_setup_minutes(day, table_key)
        assert abs(got - t['minutes']) < 1e-12, (
            "setup minutes disagree for seed %r: python=%r node=%r"
            % (t['seed'], got, t['minutes']))


def test_seed_is_rebuilt_identically():
    """The seed itself is the thing most likely to drift, because it depends on
    how each language spells a number. Rebuild it from its parts and compare."""
    fx = _load()
    for t in fx['triples']:
        date_str, table_key = t['seed'].split('|', 1)
        day = datetime.date.fromisoformat(date_str)
        rebuilt = '%s|%s' % (day.isoformat(), model._table_key(table_key))
        assert rebuilt == t['seed'], (
            "seed rebuild differs: %r vs %r — _table_key normalisation has "
            "drifted from tools/model.js's tableKey" % (rebuilt, t['seed']))


def test_every_value_is_inside_the_declared_range():
    fx = _load()
    lo, hi = fx['min_tenths'] / 10.0, fx['max_tenths'] / 10.0
    for t in fx['triples']:
        assert lo <= t['minutes'] <= hi, (
            '%r is outside %s-%s' % (t['minutes'], lo, hi))


if __name__ == '__main__':
    fns = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    failed = 0
    for fn in fns:
        try:
            fn()
            print('PASS  %s' % fn.__name__)
        except AssertionError as exc:
            failed += 1
            print('FAIL  %s\n      %s' % (fn.__name__, exc))
    print('\n%d passed, %d failed' % (len(fns) - failed, failed))
    raise SystemExit(1 if failed else 0)
