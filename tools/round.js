'use strict';
/*
Python's round() breaks ties to even (banker's rounding); JS's Math.round()
and toFixed() both round half away from zero / half up. Trap 3 in
README.md Part 8: 4,345 trolleys over 20 days is exactly 217.25, and the two
rules disagree on it (Python: 217.2 — 2 is even; toFixed(1): "217.3").

The naive fix — multiply by 10^ndigits and compare the fraction to 0.5 — is
itself wrong: that reintroduces a SECOND binary-rounding step, which can
manufacture a false exact tie that was never there. Caught empirically while
pinning this port: totalTrolleys / 20 for one scenario prints as 200.35 and
`(200.35 * 10)` is *exactly* 2003.5 in float64 — but the double actually
bound to that division is 200.349999999999994315658113919199 (verified via
`.toFixed(30)`), strictly below the midpoint, and Python's round() (which
works from the double's true, exact, finite decimal expansion, not a
re-scaled approximation of it) correctly gives 200.3, not 200.4.

So this rounds from the double's own exact decimal expansion (via
`toFixed()` at high precision, which — per the ECMAScript spec — returns a
correctly-rounded decimal to the requested digit count, and every float64 has
a finite exact decimal expansion, so a large-enough digit count captures it
exactly) and does the half-to-even decision as string/BigInt arithmetic on
that expansion. Every number written to out/*.json goes through this once, at
build time — the browser JS must never re-round.
*/
function bankersRound(x, ndigits = 0) {
  if (!Number.isFinite(x)) return x;
  if (x === 0) return 0;
  const neg = x < 0;
  const ax = Math.abs(x);
  const n = Math.max(0, Math.trunc(ndigits));

  // Enough extra digits to reach the double's exact (finite) decimal
  // expansion for any magnitude this model produces (trolley counts,
  // percentages, hours — nowhere near the ~1074-digit worst case for
  // subnormals). toFixed caps at 100 total fractional digits.
  const exact = ax.toFixed(Math.min(100, n + 60));
  const dot = exact.indexOf('.');
  const intPart = dot === -1 ? exact : exact.slice(0, dot);
  const fracPart = dot === -1 ? '' : exact.slice(dot + 1);

  const keepFrac = fracPart.slice(0, n);
  const dropFrac = fracPart.slice(n);

  let keptDigits = BigInt(intPart + keepFrac || '0');

  const firstDrop = dropFrac.charAt(0) || '0';
  let roundUp;
  if (firstDrop < '5') roundUp = false;
  else if (firstDrop > '5') roundUp = true;
  else {
    const restIsZero = /^0*$/.test(dropFrac.slice(1));
    roundUp = restIsZero ? (keptDigits % 2n !== 0n) : true;   // exact tie -> even
  }
  if (roundUp) keptDigits += 1n;

  const keptStr = keptDigits.toString().padStart(n + 1, '0');
  const intOut = n === 0 ? keptStr : keptStr.slice(0, keptStr.length - n) || '0';
  const fracOut = n === 0 ? '' : keptStr.slice(keptStr.length - n);
  const result = Number(intOut + (n > 0 ? '.' + fracOut : ''));
  return neg ? -result : result;
}

module.exports = { bankersRound };
