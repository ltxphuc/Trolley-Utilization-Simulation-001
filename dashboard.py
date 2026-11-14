# -*- coding: utf-8 -*-
"""
THE DASHBOARD
=============
Writes out/dashboard.html — a single self-contained page. Every slider
combination was already simulated by run.py, so moving a slider is a lookup,
not a re-run: the page responds instantly and needs no Python behind it.

Fleet size and cycle days are NOT looked up — they are arithmetic on
trolleys-per-day, computed live in the browser.
"""
import json

PALETTE = {
    # validated with the dataviz palette checker, light and dark separately
    'light': {'s1': '#3A6FB0', 's2': '#1E9E8A', 's3': '#E8A33D', 'bad': '#B23B32'},
    'dark':  {'s1': '#4A82C4', 's2': '#22A891', 's3': '#BB8228', 'bad': '#E0796E'},
}


def build_dashboard(payload: dict, trace: dict, months: list, month: str, path: str):
    """Writes one month's dashboard file. `payload` is identical across every
    month file (asserted by G7 — the Utilization tab must not vary with which
    month you opened); `trace` and `month` are this file's own."""
    data = json.dumps({
        'sweep': payload['sweep'],
        'assumptions': payload['assumptions'],
        'headline': {k: {'name': k,
                         'util': round(v['utilization_pct'], 2),
                         'tpd': round(v['trolleys_per_day'], 1),
                         'settings': v['settings']}
                     for k, v in payload['headline'].items()},
        'holdMinutes': payload['sweep_axes']['hold_minutes'],
        'maxBatches': payload['sweep_axes']['max_batches'],
        'planDates': payload['plan_dates'],
        'tables': payload['tables'],
        'slip': payload['slip'],
        'baselineVariant': payload['baseline_variant'],
        'months': months,
        'month': month,
        # ---- everything below is read by the Simulation tab only ----
        'cutGroups': payload['cut_groups'],
        'simVariants': payload['sim_variants'],
        'cutterCounts': payload['cutter_counts'],
        'cutGroupsByCutterCount': payload['cut_groups_by_cutter_count'],
        'cutterShiftByCutterCount': payload['cutter_shift_by_cutter_count'],
        'cutterMinutesByCutterCount': payload['cutter_minutes_by_cutter_count'],
        'nightSpreaders': payload['night_shift_spreaders'],
        'nightShiftCutters': payload['night_shift_cutters'],
        'spreaderShift': payload['spreader_shift'],
        'cutterShift': payload['cutter_shift'],
        'shiftEnd': payload['shift_end'],
        'dayShiftEnd': payload['day_shift_end'],
        'tableLengths': payload['table_lengths_m'],
        'statusColors': payload['status_colors'],
        'statusNotSimulated': payload['status_not_simulated'],
        'trace': trace,
    }, separators=(',', ':'), default=str)

    html = TEMPLATE.replace('/*__DATA__*/null', data)
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(html)


TEMPLATE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Trolley Utilization Simulation</title>
<style>
:root{
  --bg:#FBFCFD; --panel:#FFFFFF; --panel2:#EEF3F8; --ink:#101720; --muted:#5C6B7A;
  --rule:#DCE4ED; --rule2:#C3D0DE;
  --s1:#3A6FB0; --s2:#1E9E8A; --s3:#E8A33D; --bad:#B23B32;
  --badBg:#FBEDEB; --goodBg:#E9F6F3; --shadow:0 1px 3px rgba(16,23,32,.07);
  /* full visual size of a range-input thumb: 16px content + 2px border x2.
     Used by the thumb rules AND by .cursorrow's padding below, so the two
     cannot drift apart the way they did before (Part B, the Gantt cursor). */
  --thumb:20px;
}
:root[data-theme="dark"]{
  --bg:#0D1117; --panel:#161C24; --panel2:#1E2630; --ink:#E8EEF5; --muted:#93A2B2;
  --rule:#242D38; --rule2:#36434F;
  --s1:#4A82C4; --s2:#22A891; --s3:#BB8228; --bad:#E0796E;
  --badBg:#2A1512; --goodBg:#11251F; --shadow:none;
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    --bg:#0D1117; --panel:#161C24; --panel2:#1E2630; --ink:#E8EEF5; --muted:#93A2B2;
    --rule:#242D38; --rule2:#36434F;
    --s1:#4A82C4; --s2:#22A891; --s3:#BB8228; --bad:#E0796E;
    --badBg:#2A1512; --goodBg:#11251F; --shadow:none;
  }
}
*{box-sizing:border-box}
html,body{margin:0}
body{
  background:var(--bg); color:var(--ink); padding:0 20px 64px;
  font:400 15px/1.55 "IBM Plex Sans",-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
  -webkit-font-smoothing:antialiased;
}
.mono,.num{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
  font-variant-numeric:tabular-nums}
h1,h2,h3{margin:0;font-family:Archivo,"IBM Plex Sans",system-ui,sans-serif;
  letter-spacing:-.015em;text-wrap:balance}
h1{font-size:26px;font-weight:700}
h2{font-size:17px;font-weight:700}
h3{font-size:12px;font-weight:600}
.wrap{max-width:1600px;margin:0 auto}

/* ---------------------------------------------------------------- header */
header{display:flex;align-items:flex-end;justify-content:space-between;gap:20px;
  flex-wrap:wrap;padding:26px 0 18px;border-bottom:1px solid var(--rule)}
.eyebrow{font-family:"IBM Plex Mono",monospace;font-size:10.5px;letter-spacing:.15em;
  text-transform:uppercase;color:var(--muted);margin-bottom:6px}
button.theme{background:var(--panel);color:var(--muted);border:1px solid var(--rule2);
  border-radius:4px;padding:7px 12px;font-size:12px;cursor:pointer;font-family:inherit}
button.theme:hover{color:var(--ink);border-color:var(--muted)}

/* ------------------------------------------------------------------ grid */
/* minmax(0,1fr), not 1fr: a grid item defaults to min-width:auto, so a wide
   chart would stretch the column and push the whole page sideways instead of
   scrolling inside its own panel. */
.cols{display:grid;grid-template-columns:290px minmax(0,1fr);gap:24px;margin-top:24px;
  align-items:start}
@media (max-width:940px){.cols{grid-template-columns:minmax(0,1fr)}}
.cols>*{min-width:0}
.panel,details.panel{min-width:0}
/* -------------------------------------------------------------- controls */
/* The rail is taller than the viewport on both tabs once every control is
   open. Sticky + a viewport-bounded max-height + its own scroll keeps the
   whole rail reachable without the page having to scroll past the chart;
   overscroll-behavior:contain stops a scroll that bottoms out in the rail
   from then moving the page. Below 940px the rail is static (stacked above
   the content), so it must not be height-clamped there. */
.rail{position:sticky;top:16px;display:flex;flex-direction:column;gap:14px;
  max-height:calc(100vh - 32px);overflow-y:auto;overscroll-behavior:contain;
  scrollbar-width:thin;scrollbar-color:var(--rule2) transparent;padding-right:4px}
.rail::-webkit-scrollbar{width:7px}
.rail::-webkit-scrollbar-thumb{background:var(--rule2);border-radius:4px}
.rail::-webkit-scrollbar-track{background:transparent}
@media (max-width:940px){.rail{position:static;max-height:none;overflow:visible;padding-right:0}}
.ctl{background:var(--panel);border:1px solid var(--rule);border-radius:6px;
  padding:15px 16px;box-shadow:var(--shadow)}
.ctl h3{color:var(--muted);text-transform:uppercase;letter-spacing:.09em;
  font-family:"IBM Plex Mono",monospace;font-size:10px;font-weight:400;margin-bottom:12px}
.field{margin-bottom:17px}
.field:last-child{margin-bottom:0}
.field>label{display:flex;justify-content:space-between;align-items:baseline;
  gap:8px;font-size:13px;font-weight:500;margin-bottom:7px}
.field .val{font-family:"IBM Plex Mono",monospace;font-size:12.5px;color:var(--s1);font-weight:500}
.hint{font-size:11.5px;color:var(--muted);line-height:1.45;margin-top:6px}
.chg{display:inline-block;font-family:"IBM Plex Mono",monospace;font-size:9.5px;
  letter-spacing:.06em;border:1px solid var(--rule2);border-radius:3px;
  padding:1px 5px;color:var(--muted);margin-right:6px;vertical-align:1px}

input[type=range]{width:100%;-webkit-appearance:none;appearance:none;background:transparent;
  margin:2px 0;cursor:pointer}
input[type=range]::-webkit-slider-runnable-track{height:4px;border-radius:2px;background:var(--rule2)}
input[type=range]::-moz-range-track{height:4px;border-radius:2px;background:var(--rule2)}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;
  width:calc(var(--thumb) - 4px);height:calc(var(--thumb) - 4px);
  border-radius:50%;background:var(--s1);border:2px solid var(--panel);margin-top:-6px;
  box-shadow:0 0 0 1px var(--rule2)}
input[type=range]::-moz-range-thumb{width:calc(var(--thumb) - 4px);height:calc(var(--thumb) - 4px);
  border-radius:50%;background:var(--s1);border:2px solid var(--panel);box-shadow:0 0 0 1px var(--rule2)}
input[type=range]:focus-visible{outline:2px solid var(--s1);outline-offset:4px;border-radius:3px}

.seg{display:flex;gap:0;border:1px solid var(--rule2);border-radius:5px;overflow:hidden}
.seg button{flex:1;background:var(--panel);border:0;border-right:1px solid var(--rule2);
  padding:7px 4px;font:500 12.5px/1 "IBM Plex Sans",sans-serif;color:var(--muted);cursor:pointer}
.seg button:last-child{border-right:0}
.seg button[aria-pressed=true]{background:var(--s1);color:#fff}
.seg button:focus-visible{outline:2px solid var(--s1);outline-offset:-2px}
.seg button:disabled{opacity:.38;cursor:not-allowed}
.seg button:disabled[aria-pressed=true]{background:var(--panel);color:var(--muted)}
/* Month selector is a row of <a> links (real navigation, file:// pages), not
   <button>s — same visual language as the rest of the .seg family. Wraps to
   more than one row at 8 items, unlike the fixed-count segs elsewhere. */
.seg a{flex:1 1 64px;min-width:56px;background:var(--panel);border:0;border-right:1px solid var(--rule2);
  border-bottom:1px solid var(--rule2);padding:7px 4px;font:500 12.5px/1 "IBM Plex Sans",sans-serif;
  color:var(--muted);text-decoration:none;text-align:center;cursor:pointer}
.seg a[aria-current=page]{background:var(--s1);color:#fff}
.seg a:focus-visible{outline:2px solid var(--s1);outline-offset:-2px}

.presets{display:flex;gap:8px}
.presets button{flex:1;background:var(--panel2);border:1px solid var(--rule2);border-radius:5px;
  padding:8px 6px;font:500 12px/1.3 "IBM Plex Sans",sans-serif;color:var(--ink);cursor:pointer}
.presets button:hover{border-color:var(--s1);color:var(--s1)}

/* --------------------------------------------------------------- verdict */
.verdict{border-radius:7px;border:1px solid var(--rule);background:var(--panel);
  padding:22px 24px;box-shadow:var(--shadow);
  display:grid;grid-template-columns:1fr auto;gap:24px;align-items:center}
@media (max-width:640px){.verdict{grid-template-columns:1fr}}
.verdict.short{border-color:var(--bad);background:var(--badBg)}
.verdict.ok{border-color:var(--s2);background:var(--goodBg)}
.vlabel{font-family:Archivo,sans-serif;font-weight:700;font-size:12px;letter-spacing:.11em;
  text-transform:uppercase}
.verdict.short .vlabel{color:var(--bad)}
.verdict.ok .vlabel{color:var(--s2)}
.vbig{font-family:Archivo,sans-serif;font-weight:700;font-size:40px;line-height:1.05;
  margin:9px 0 0;letter-spacing:-.025em}
.vsub{font-size:13.5px;color:var(--muted);margin-top:8px;max-width:52ch}
.vsub b{color:var(--ink)}

/* --------------------------------------------------------------- tiles */
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(158px,1fr));gap:12px;margin-top:16px}
.tile{background:var(--panel);border:1px solid var(--rule);border-radius:6px;
  padding:14px 15px;box-shadow:var(--shadow)}
.tile .k{font-family:"IBM Plex Mono",monospace;font-size:9.5px;letter-spacing:.1em;
  text-transform:uppercase;color:var(--muted);line-height:1.4;min-height:27px}
.tile .v{font-family:Archivo,sans-serif;font-weight:700;font-size:26px;margin:8px 0 0;
  letter-spacing:-.02em}
.tile .v em{font-style:normal;font-size:15px;color:var(--muted);font-weight:600}
.tile .d{font-family:"IBM Plex Mono",monospace;font-size:11.5px;margin-top:5px;color:var(--muted)}
.tile .d.up{color:var(--s2)} .tile .d.down{color:var(--bad)}

/* --------------------------------------------------------------- panels */
.panel{background:var(--panel);border:1px solid var(--rule);border-radius:6px;
  padding:18px 20px;box-shadow:var(--shadow);margin-top:16px}
.panel>h2{margin-bottom:3px}
.panel>.sub{font-size:12.5px;color:var(--muted);margin:0 0 15px;max-width:70ch}
.split{display:grid;grid-template-columns:190px 1fr;gap:26px;align-items:center}
@media (max-width:700px){.split{grid-template-columns:1fr}}
svg{display:block;max-width:100%;height:auto}
.legend{display:flex;flex-wrap:wrap;gap:14px;margin-top:12px;font-size:12px;color:var(--muted)}
.legend i{display:inline-block;width:9px;height:9px;border-radius:2px;margin-right:6px;
  vertical-align:0px}
footer{margin-top:34px;padding-top:18px;border-top:1px solid var(--rule);
  font-size:12px;color:var(--muted);line-height:1.6}
footer code{font-family:"IBM Plex Mono",monospace;font-size:11.5px;
  background:var(--panel2);padding:1px 5px;border-radius:3px}
@media (prefers-reduced-motion:no-preference){
  .barfill,.compfill,.vbig,.tile .v{transition:all .22s cubic-bezier(.4,0,.2,1)}
}

/* ------------------------------------------------------- simulation tab */
.scrollx{overflow-x:auto;overflow-y:hidden}
.calendar{display:grid;grid-template-columns:repeat(7,1fr);gap:3px}
.calendar .dow{font-family:"IBM Plex Mono",monospace;font-size:9px;color:var(--muted);
  text-align:center;padding-bottom:3px;letter-spacing:.04em}
.calendar button{aspect-ratio:1;background:var(--panel2);border:1px solid var(--rule2);
  border-radius:4px;font:500 11.5px/1 "IBM Plex Mono",monospace;color:var(--ink);cursor:pointer;
  display:flex;align-items:center;justify-content:center;padding:0}
.calendar button:hover{border-color:var(--s1);color:var(--s1)}
.calendar button[aria-pressed=true]{background:var(--s1);border-color:var(--s1);color:#fff}
.calendar button:focus-visible{outline:2px solid var(--s1);outline-offset:1px}
.calendar span{aspect-ratio:1;display:flex;align-items:center;justify-content:center;
  font:400 11.5px/1 "IBM Plex Mono",monospace;color:var(--rule2)}
.calmonth{font-family:"IBM Plex Mono",monospace;font-size:10.5px;color:var(--muted);
  letter-spacing:.08em;text-transform:uppercase;margin:2px 0 8px}

/* The slider's own range is clamped to ganttEnd(run) in resetCursor() — the
   exact same call the chart uses for xmax — so fraction f on the track and
   fraction f on the axis are the same instant by construction; there is no
   second scale to drift out of sync. ganttEnd(run) now floors at the full
   two-shift window (DATA.shiftEnd, 05:00), and the cursor reads the
   SIMULATED cut_end clock, not the actual Pull Date — so every completion
   this chart can ever show is inside the slider's own range and there is no
   late-finishing tail left to reach with a separate day stepper. */
.cursorhead{display:flex;justify-content:space-between;align-items:baseline;gap:12px;
  margin-bottom:6px;flex-wrap:wrap}
.cursorhead label{font-size:12px;color:var(--muted)}
.cursorhead .num{font-size:12.5px;font-weight:600}
/* The chart fills the panel, and only scrolls once the panel is narrower than
   the chart can usefully be drawn. The gutters are fixed pixels and match the
   SVG's own L and R MINUS half a thumb on each side — a native range input
   moves its thumb's CENTRE between track.left+thumb/2 and track.right-thumb/2,
   while the SVG puts t=0 at exactly x=L, so the track has to be that much
   narrower for the two to land on the same pixel at every fraction, not just
   the midpoint. */
.ganttinner{min-width:1120px}
.cursorrow{padding:0 calc(14px - var(--thumb)/2) 2px calc(96px - var(--thumb)/2);box-sizing:border-box}
.cursorrow input[type=range]{width:100%;margin:0;display:block}

.swatches{display:flex;flex-wrap:wrap;gap:5px 16px;margin-top:13px;font-size:11.5px;
  color:var(--muted);line-height:1.35}
.swatches span{display:flex;align-items:center;gap:6px}
.swatches i{width:11px;height:11px;border-radius:2px;flex:none;
  border:1px solid rgba(128,128,128,.55)}
.swatches b{color:var(--ink);font-family:"IBM Plex Mono",monospace;font-size:11px;font-weight:600}
.swatches .off{opacity:.45}

.parity{display:inline-flex;align-items:center;gap:8px;border-radius:4px;padding:6px 11px;
  font-size:12px;margin-bottom:14px;border:1px solid var(--rule2);background:var(--panel2)}
.parity.ok{border-color:var(--s2);background:var(--goodBg)}
.parity.bad{border-color:var(--bad);background:var(--badBg)}
.parity .num{font-weight:600}

details.panel>summary{cursor:pointer;list-style:none;display:flex;align-items:baseline;
  gap:12px;flex-wrap:wrap}
details.panel>summary::-webkit-details-marker{display:none}
details.panel>summary::before{content:"\25B8";color:var(--muted);font-size:12px;
  transition:transform .15s}
details.panel[open]>summary::before{transform:rotate(90deg)}
details.panel>summary:focus-visible{outline:2px solid var(--s1);outline-offset:3px;border-radius:3px}
details.panel>summary h2{display:inline}
details.panel>summary .sum{font-family:"IBM Plex Mono",monospace;font-size:11.5px;
  color:var(--muted);margin-left:auto}
details.panel>.sub{margin-top:12px}
h3.sechead{font-size:12px;color:var(--muted);text-transform:uppercase;
  letter-spacing:.09em;font-family:"IBM Plex Mono",monospace;font-weight:400;
  margin:22px 0 10px}

.trolleyrow{display:flex;flex-wrap:wrap;gap:10px}
.tcard{border:1px solid var(--rule2);border-radius:5px;padding:8px;background:var(--panel2);width:112px}
.tcard .h{font-family:"IBM Plex Mono",monospace;font-size:9.5px;color:var(--muted);
  display:flex;justify-content:space-between;margin-bottom:6px}
.tcard .c{height:19px;border-radius:2px;margin-bottom:3px;display:flex;align-items:center;
  justify-content:space-between;padding:0 5px;font-family:"IBM Plex Mono",monospace;
  font-size:9.5px;color:#101720}
.tcard .c.empty{background:transparent;border:1px dashed var(--rule2)}
.filmhead{font-family:"IBM Plex Mono",monospace;font-size:11px;color:var(--muted);
  margin:16px 0 8px;letter-spacing:.05em}
.filmhead:first-child{margin-top:0}

table.tasks{border-collapse:collapse;width:100%;font-size:12px}
table.tasks th{text-align:left;font-family:"IBM Plex Mono",monospace;font-size:9.5px;
  letter-spacing:.08em;text-transform:uppercase;color:var(--muted);font-weight:400;
  padding:0 10px 7px 0;border-bottom:1px solid var(--rule2);white-space:nowrap;
  cursor:pointer;user-select:none}
table.tasks th:hover{color:var(--ink)}
table.tasks td{padding:6px 10px 6px 0;border-bottom:1px solid var(--rule);white-space:nowrap}
table.tasks td.n{font-family:"IBM Plex Mono",monospace;font-variant-numeric:tabular-nums;
  text-align:right;padding-right:16px}
table.tasks tr:hover td{background:var(--panel2)}
.muted{color:var(--muted)}

/* ------------------------------------------------------------ rules lab tab */
.ctl .seg.wrap{flex-wrap:wrap}
.est{display:inline-block;font-family:"IBM Plex Mono",monospace;font-size:9px;letter-spacing:.06em;
  color:var(--s3);border:1px solid var(--s3);border-radius:3px;padding:0 4px;margin-left:6px;vertical-align:1px}
.labstatus{font-family:"IBM Plex Mono",monospace;font-size:11.5px;color:var(--muted);margin-top:16px;min-height:18px}
table.mt td,table.mt th{white-space:nowrap}
table.mt th.grp{text-align:center;border-bottom:1px solid var(--rule2)}
i.chip{display:inline-block;width:9px;height:9px;border-radius:2px;margin-right:7px;vertical-align:-1px}
table.out{border-collapse:collapse;width:100%;font-size:12px;margin:4px 0 14px}
table.out th{text-align:right;font-family:"IBM Plex Mono",monospace;font-size:9.5px;letter-spacing:.06em;
  text-transform:uppercase;color:var(--muted);font-weight:400;padding:0 0 7px 14px;border-bottom:1px solid var(--rule2)}
table.out th:first-child,table.out td:first-child{text-align:left;padding-left:0}
table.out td{text-align:right;padding:6px 0 6px 14px;border-bottom:1px solid var(--rule);
  font-family:"IBM Plex Mono",monospace;font-variant-numeric:tabular-nums}
table.out td:first-child{font-family:"IBM Plex Sans",sans-serif}
table.out tr.sel td{font-weight:700;background:var(--panel2)}
table.out .up{color:var(--s2)} table.out .down{color:var(--bad)}
.labnote{font-size:12px;color:var(--muted);line-height:1.55;max-width:80ch}
.labnote b{color:var(--ink)}
.labnote p{margin:0 0 9px}
#labDays svg{max-width:820px}
</style>
</head>
<body>
<div class="wrap">

<header>
  <div>
    <div class="eyebrow">Central Cutting &middot; Job Sequence &amp; Panel Loading</div>
    <h1>Trolley Utilization Simulation</h1>
  </div>
  <button class="theme" id="themeBtn" type="button">Dark mode</button>
</header>

<!-- ============================== RULES LAB ============================== -->
<section id="tabLab">
<div class="cols">

  <div class="rail">
    <div class="ctl">
      <h3>The floor</h3>
      <div class="hint">There is no cold start. Work a machine did not finish carries into the next
        shift, and each plan date is planned on its morning around what every spreader still has left. Machines run
        at the G2 standard pace. Cutter changeover and moving time are the only lost time added on top
        <span class="est">ESTIMATES</span>. With every option at its default this is the published model.</div>
      <div class="presets" style="margin-top:10px"><button type="button" id="labReset">Reset to the published model</button></div>
    </div>

    <div class="ctl">
      <h3>Plan date</h3>
      <div class="calmonth" id="labCalMonth"></div>
      <div class="calendar" id="labCalendar"></div>
      <div class="hint">Pick a date to see its arrangement. The numbers pool all <span id="labDates"></span> plan dates.</div>
    </div>

    <div class="ctl">
      <h3>Shift</h3>
      <div class="seg" role="group" aria-label="Shift option">
        <button type="button" data-k="shift" data-v="both" aria-pressed="true">Both</button>
        <button type="button" data-k="shift" data-v="day" aria-pressed="false">Day only</button>
        <button type="button" data-k="shift" data-v="night" aria-pressed="false">Night only</button>
      </div>
      <div class="hint">Day: all 13 spreaders and 5 cutters, 07:15&ndash;20:00. Night: 24-01/02/03 and 24MC1
        only, 18:00&ndash;05:00. Both is the floor today.</div>
    </div>

    <div class="ctl">
      <h3>Machines</h3>
      <div class="field">
        <label><span>Cutters against 13 spreaders</span></label>
        <div class="seg" id="labCutterSeg" role="group" aria-label="Number of cutting machines"></div>
      </div>
      <div class="field">
        <label><span>Spreading table length</span></label>
        <div class="seg" id="labTableSeg" role="group" aria-label="Spreading table length"></div>
        <div class="hint">What-ifs: more cutters, or a longer table (24 and 27 m are not tables you own). They are part of
          your selection only: S0 stays at today's 5 cutters and 21.2 m table.</div>
      </div>
    </div>

    <div class="ctl">
      <h3>Fleet</h3>
      <div class="field">
        <label for="labCycle"><span>Round trip, days</span><span class="val" id="labCycleVal"></span></label>
        <input type="range" id="labCycle" min="3" max="10" step="0.5" value="7" aria-label="Round trip days">
        <div class="hint">5 days is the lead-time allowance. About 7 is the estimate of what really happens: it has
          never been measured <span class="est">ESTIMATE</span></div>
      </div>
      <div class="field">
        <label for="labFleet"><span>Trolleys owned</span><span class="val" id="labFleetVal"></span></label>
        <input type="range" id="labFleet" min="600" max="2200" step="50" value="1200" aria-label="Fleet size">
      </div>
    </div>

    <div class="ctl">
      <h3>The three changes</h3>
      <div class="field">
        <label><span><span class="chg">1</span>Same-MO sequencing</span></label>
        <div class="seg" role="group" aria-label="Same-MO sequencing">
          <button type="button" data-k="seqMode" data-v="today" aria-pressed="true">Off</button>
          <button type="button" data-k="seqMode" data-v="same_batch" aria-pressed="false">Same batch only</button>
          <button type="button" data-k="seqMode" data-v="cross_batch" aria-pressed="false">Cross-batch</button>
        </div>
        <div class="hint">Tables of the same MO and colour are paired first, each pair spread back-to-back on one
          spreader. The Job Sequence then counts its tasks and takt time by pairs, and gives each pair to the
          cut group that keeps the cutters busiest. A partner must already be relaxed to pair, so with fabric
          relaxing on, different batches pair less often.</div>
      </div>
      <div class="field">
        <label><span>Where the pairs go</span></label>
        <div class="seg" role="group" aria-label="Where the pairs go">
          <button type="button" data-k="moOneGroup" data-v="0" aria-pressed="true">Pairs over the floor</button>
          <button type="button" data-k="moOneGroup" data-v="1" aria-pressed="false">Keep an MO on one cut group</button>
        </div>
        <div class="hint">Pairs over the floor is the published rule: pairs of one MO and colour are spread
          across the cut groups. Keep an MO on one cut group is the old behaviour: a whole MO and colour goes to
          one cut group. It only applies when same-MO sequencing is on.</div>
      </div>
      <div class="field">
        <label><span><span class="chg">2</span>Batches per trolley</span></label>
        <div class="seg" role="group" aria-label="Batches per trolley">
          <button type="button" data-k="batches" data-v="1" aria-pressed="true">1</button>
          <button type="button" data-k="batches" data-v="2" aria-pressed="false">2</button>
          <button type="button" data-k="batches" data-v="3" aria-pressed="false">3</button>
        </div>
        <div class="hint">2 or more lets two batches of one MO and colour share a trolley (2 and 3 behave the same).</div>
      </div>
      <div class="field">
        <label><span><span class="chg">3</span>WIP hold</span><span class="val" id="lv_holdMin"></span></label>
        <input type="range" data-k="holdMin" min="0" max="240" step="30" value="0" aria-label="WIP hold minutes">
        <div class="hint">How long a part-filled trolley waits for a later table of the same MO, colour and film.</div>
      </div>
      <div class="field">
        <label><span>It comes back to</span></label>
        <div class="seg" role="group" aria-label="Workstation a trolley returns to">
          <button type="button" data-k="anyWs" data-v="0" aria-pressed="false">Same only</button>
          <button type="button" data-k="anyWs" data-v="1" aria-pressed="true">Any</button>
        </div>
      </div>
      <div class="field">
        <label><span>Which parked trolley is recalled</span></label>
        <div class="seg" role="group" aria-label="Recall order">
          <button type="button" data-k="recall" data-v="model" aria-pressed="true">Published</button>
          <button type="button" data-k="recall" data-v="sameFirst" aria-pressed="false">Same batch first</button>
          <button type="button" data-k="recall" data-v="sameOnly" aria-pressed="false">Same batch only</button>
        </div>
        <div class="hint">Published takes any trolley of the same MO and colour (two batches at most). Same batch
          first recalls a trolley already holding the batch just cut, and uses another batch's trolley only if
          none is waiting. Same batch only never mixes at recall.</div>
      </div>
    </div>

    <div class="ctl">
      <h3>Add-ons <span class="est">ESTIMATES</span></h3>
      <div class="field">
        <label><span>Pull-ahead (plan dates)</span><span class="val" id="lv_pullAhead"></span></label>
        <div class="seg wrap" role="group" aria-label="Pull-ahead">
          <button type="button" data-k="pullAhead" data-v="0" aria-pressed="true">0</button>
          <button type="button" data-k="pullAhead" data-v="1" aria-pressed="false">1</button>
          <button type="button" data-k="pullAhead" data-v="2" aria-pressed="false">2</button>
          <button type="button" data-k="pullAhead" data-v="3" aria-pressed="false">3</button>
          <button type="button" data-k="pullAhead" data-v="99" aria-pressed="false">All</button>
        </div>
        <div class="hint">A spreader that has finished the released plan
          starts the next plan dates' tables if their fabric has relaxed.</div>
      </div>
      <div class="field">
        <label><span>Cutter setup, MO or colour change</span><span class="val" id="lv_setupMin"></span></label>
        <input type="range" data-k="setupMin" min="0" max="15" step="0.5" value="5" aria-label="Cutter setup minutes">
        <div class="hint">Clean-up of the area and cutting-speed adjustment. Not measured. The slider starts at
          the published model's value; move it to test a different one.</div>
      </div>
      <div class="field">
        <label><span>Cutter travel between workstations</span><span class="val" id="lv_travelMin"></span></label>
        <input type="range" data-k="travelMin" min="0" max="5" step="0.5" value="1.5" aria-label="Cutter travel minutes">
        <div class="hint">The slider starts at the published model's value. Not measured.</div>
      </div>
      <div class="field">
        <label><span>Wait for fabric relaxing</span></label>
        <div class="seg" role="group" aria-label="Fabric relaxing">
          <button type="button" data-k="relax" data-v="0" aria-pressed="false">Off</button>
          <button type="button" data-k="relax" data-v="1" aria-pressed="true">On</button>
        </div>
        <div class="hint">On in the published model. The data has no fabric arrival time (ESTIMATE): each batch gets a
          fixed pseudo-random arrival before its first plan date, then relaxes 24 h before it can be spread.</div>
      </div>
      <div class="field">
        <label><span>Earliest arrival, before plan date</span><span class="val" id="lv_relaxMaxH"></span></label>
        <input type="range" data-k="relaxMaxH" min="0" max="96" step="6" value="48" aria-label="Earliest fabric arrival hours">
      </div>
      <div class="field">
        <label><span>Latest arrival, before plan date</span><span class="val" id="lv_relaxMinH"></span></label>
        <input type="range" data-k="relaxMinH" min="0" max="96" step="6" value="12" aria-label="Latest fabric arrival hours">
      </div>
    </div>
  </div>

  <div>
    <div class="panel">
      <div class="parity" id="labBadge"></div>
      <div class="verdict" id="labFleetCard" style="margin-top:14px">
        <div>
          <div class="vlabel" id="labFleetLabel">&mdash;</div>
          <div class="vbig" id="labFleetBig">&mdash;</div>
          <div class="vsub" id="labFleetSub"></div>
        </div>
        <div id="labFleetDial"></div>
      </div>
      <div class="tiles" id="labTiles"></div>
      <div class="hint" style="margin-top:12px">vs today = S0, the real Job Sequence, on today's floor. Round trip and fleet are
        the Fleet settings on the left (the 7-day trip is an ESTIMATE).</div>
      <div class="labstatus" id="labStatus"></div>
    </div>

    <div class="panel">
      <h2>What one trolley looks like</h2>
      <p class="sub">Utilization is compartments opened &divide; <span id="capDiv">5</span>.
        This is that number drawn as the trolley it describes &mdash; filled compartments
        at the bottom, empty space travelling for free at the top.</p>
      <div class="split">
        <div id="labTrolley"></div>
        <div>
          <div id="labTrolleyText" style="font-size:14px;line-height:1.65"></div>
          <div class="legend">
            <span><i style="background:var(--s2)"></i>Loaded</span>
            <span><i style="background:var(--rule2)"></i>Empty &mdash; travelling for nothing</span>
          </div>
        </div>
      </div>
    </div>

    <div class="panel">
      <h2>Job Sequence &mdash; <span id="labGanttDate"></span></h2>
      <p class="sub">Every table placed on a spreading machine, and the cutting that follows on the cutter
        serving that group. Setup and travel are drawn before each cut.</p>
      <div class="seg" id="labViewSeg" role="group" aria-label="Arrangement shown" style="max-width:340px;margin-bottom:12px">
        <button type="button" data-view="sel" aria-pressed="true">Your selection</button>
        <button type="button" data-view="s0" aria-pressed="false">S0 Today</button>
      </div>
      <div class="cursorhead">
        <label for="labCursor">Spreading and cutting finished by</label>
        <span class="num" id="labCursorVal"></span>
      </div>
      <div class="scrollx">
        <div class="ganttinner">
          <div class="cursorrow"><input type="range" id="labCursor" min="0" max="1" step="1" value="0"
            aria-label="Time cursor along the chart's own timeline"></div>
          <div id="labGantt"></div>
        </div>
      </div>
      <div class="swatches" id="labLegend"></div>
      <div class="hint" id="labGanttNote"></div>
    </div>

    <div class="panel">
      <h2>Idle time on <span id="labIdleDate"></span></h2>
      <p class="sub">Per cut group, for the tables planned for this date. Hours; S0 at today's floor against your selection.</p>
      <div class="scrollx"><table class="out mt" id="labIdle"></table></div>
    </div>

    <details class="panel" id="labLoadPanel">
      <summary>
        <h2>Panel Loading &mdash; trolleys opened for <span id="labLoadDate"></span></h2>
        <span class="sum" id="labLoadSummary"></span>
      </summary>
      <p class="sub">The same day's cut panels, loaded compartment by compartment. A compartment holds one size
        of one batch, up to 150 pieces; a trolley holds five compartments of one film width. Recalled
        compartments are marked.</p>
      <div class="scrollx"><table class="tasks" id="labTrolleyTable"></table></div>
      <h3 class="sechead">Every trolley of the day</h3>
      <div id="labTrolleys"></div>
    </details>

    <div class="panel">
      <h2>Output &mdash; pieces cut a day</h2>
      <div class="scrollx"><table class="out" id="labOut"></table></div>
    </div>

    <div class="panel">
      <h2>Where the machine time goes</h2>
      <div class="hint">Hours per working day, real plan, S0 against your selection.
        <i class="chip" style="background:var(--s2)"></i><b>Working</b> = spreading or cutting. <b>Lost</b> = staffed time minus working (the other rows).
        Change: <b style="color:var(--s2)">green</b> = better, <b style="color:var(--bad)">red</b> = worse. Setup and travel are ESTIMATES.</div>
      <h3 class="sechead">Spreading machines</h3>
      <div class="scrollx"><table class="out mt" id="labSpreadSum"></table></div>
      <h3 class="sechead">Cutting machines</h3>
      <div class="scrollx"><table class="out mt" id="labCutSum"></table></div>
      <h3 class="sechead">Each spreading machine</h3>
      <div class="scrollx"><table class="out mt" id="labSpreadEach"></table></div>
      <h3 class="sechead">Each cutting machine</h3>
      <div class="scrollx"><table class="out mt" id="labCutEach"></table></div>
    </div>

    <div class="panel">
      <h2>Day by day</h2>
      <p class="sub">Share of each plan date's tables that were fully cut inside that date's own shift window.</p>
      <div id="labDays"></div>
    </div>

    <div class="panel">
      <h2>How to read this</h2>
      <div class="labnote">
        <p><b>The published model.</b> With every option at its default, the numbers equal the published model's for the same
          three changes. The badge above turns green when that holds for the current selection.</p>
        <p><b>Estimates.</b> Fabric arrival, cutter setup and cutter travel are not in the data. They are set by
          the sliders and every number moves with them. Cutter setup and travel start at the published model's
          values (they are part of it); fabric arrival is off until you switch it on.</p>
        <p><b>Starved</b> means a spreader had nothing it was allowed to start: its fabric had not relaxed, or the
          plan date had not begun. <b>Blocked</b> is the spreading table being full (rule G6).</p>
        <p><b>Leftover work.</b> On the carry-over floor every plan date is sequenced on its own morning, around the
          work each spreader still has committed from the days before. The model runs at the G2 standard pace,
          so it has spare capacity and the leftover drains faster than on the real floor, which finishes 51% of
          its tables after their plan date. The model is less late than the real floor.</p>
        <p><b>Output in the same working time.</b> Tables per shift-hour counts the staffed shift window up to the
          last cut. Set pull-ahead to All to see capacity rather than the calendar.</p>
      </div>
    </div>
  </div>
</div>
</section>

</div>

<script>/*__LAB__*/</script>
<script>
const DATA = /*__DATA__*/null;
const A = DATA.assumptions;
const HOLDS = DATA.holdMinutes;

const state = {cycle: A.cycle_days_estimated, fleet: A.fleet_size};   // set on the Lab's Fleet controls

const $ = id => document.getElementById(id);
const fmt = (n,d=0) => n.toLocaleString('en-US',{minimumFractionDigits:d,maximumFractionDigits:d});

function key(mo, batches, hold, anyWs){
  if (hold === 0) anyWs = 1;
  return `${mo}|${batches}|${hold}|${anyWs}`;
}
/* ---------------------------------------------------------------- visuals */
function trolleySvg(util){
  // 5 compartments, filled from the bottom, in proportion to utilization
  const used = util/100*5, W=170, H=210, x=26, w=118, top=16, ch=32, gap=4;
  let s = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Trolley with ${(util/100*5).toFixed(2)} of 5 compartments loaded">`;
  s += `<rect x="${x-8}" y="${top-8}" width="${w+16}" height="${5*(ch+gap)+12}" rx="5"
         fill="none" stroke="var(--rule2)" stroke-width="2"/>`;
  for (let i=0;i<5;i++){
    const slot = 4-i;                                   // fill bottom-up
    const y = top + slot*(ch+gap);
    const f = Math.max(0, Math.min(1, used - i));
    s += `<rect x="${x}" y="${y}" width="${w}" height="${ch}" rx="2"
           fill="var(--panel2)" stroke="var(--rule2)" stroke-width="1"/>`;
    if (f > 0.004){
      s += `<rect class="compfill" x="${x+2}" y="${y+2}" width="${(w-4)*f}" height="${ch-4}"
             rx="1.5" fill="var(--s2)"/>`;
    }
  }
  const by = top + 5*(ch+gap) + 8;
  s += `<rect x="${x-8}" y="${by}" width="${w+16}" height="4" rx="2" fill="var(--rule2)"/>`;
  s += `<circle cx="${x+6}" cy="${by+12}" r="6" fill="none" stroke="var(--rule2)" stroke-width="2"/>`;
  s += `<circle cx="${x+w-6}" cy="${by+12}" r="6" fill="none" stroke="var(--rule2)" stroke-width="2"/>`;
  return s + '</svg>';
}

function fleetDial(required, fleet){
  const r=52, c=2*Math.PI*r, pct=Math.min(1.35, required/fleet);
  const over = required > fleet;
  const col = over ? 'var(--bad)' : 'var(--s2)';
  return `<svg viewBox="0 0 130 130" width="126" height="126" role="img"
    aria-label="${fmt(required)} trolleys needed against ${fmt(fleet)} owned">
    <circle cx="65" cy="65" r="${r}" fill="none" stroke="var(--rule2)" stroke-width="11"/>
    <circle cx="65" cy="65" r="${r}" fill="none" stroke="${col}" stroke-width="11"
      stroke-linecap="butt" stroke-dasharray="${Math.min(pct,1)*c} ${c}"
      transform="rotate(-90 65 65)"/>
    <text x="65" y="60" text-anchor="middle" class="num" font-size="21" font-weight="700"
      fill="var(--ink)">${Math.round(required/fleet*100)}%</text>
    <text x="65" y="77" text-anchor="middle" font-size="10" fill="var(--muted)">of fleet</text>
  </svg>`;
}

$('themeBtn').addEventListener('click', () => {
  const dark = document.documentElement.getAttribute('data-theme') === 'dark'
    || (!document.documentElement.getAttribute('data-theme')
        && matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.setAttribute('data-theme', dark ? 'light' : 'dark');
  $('themeBtn').textContent = dark ? 'Dark mode' : 'Light mode';
});

/* ================================================================ RULES LAB
   The engine is tools/lab.js, inlined above as `Lab` — the very file Node runs,
   so there is no second port. This block is the controls and the drawing.
   On its defaults it IS the published model: the numbers equal the published
   sweep and the Job Sequence equals the model's trace (tools/lab_table.js and
   __labCheck prove it). The page is this block only; if the browser cannot
   unzip its data, it says so.
   ====================================================================== */
const LABUI = (() => {
if (typeof Lab === 'undefined' || !DATA.lab || typeof DecompressionStream === 'undefined') return null;
const T = DATA.trace, CFG = DATA.lab.cfg, V = CFG.addOnValues, SCOL = DATA.statusColors;
const E = Lab.createEngine(CFG);
const DEF = Object.assign({}, CFG.defaults, {batches: 1});
let lab = Object.assign({}, DEF);
const view = {kind: 'sel', date: T.dates[0], cursor: 0, showAll: false};
let INPUT = null, loadP = null, wired = false, timer = 0, frame = 0;
const $$ = sel => Array.from(document.querySelectorAll(sel));
const f1 = n => n.toFixed(1), f2 = n => n.toFixed(2);
const pct = (a, b) => b ? 100 * a / b : 0;
const SHIFT_START = A.shift_start_minute;
const NIGHT_SP = new Set(CFG.nightSpreaders), NIGHT_CU = new Set(CFG.nightCutters);

function load(){
  if (!loadP) loadP = (async () => {
    const bin = Uint8Array.from(atob(DATA.lab.data), c => c.charCodeAt(0));
    const text = await new Response(new Blob([bin]).stream().pipeThrough(new DecompressionStream('gzip'))).text();
    INPUT = Lab.decode(JSON.parse(text), CFG);
  })();
  return loadP;
}
const cache = new Map();
function runOpt(opt){
  const k = JSON.stringify(opt);
  if (!cache.has(k)) cache.set(k, E.run(INPUT, opt));
  return cache.get(k);
}

/* ----------------------------------------------------------------- clocks */
function hhmm(m){
  const whole = Math.round(m), x = ((whole % 1440) + 1440) % 1440;
  return String(Math.floor(x / 60)).padStart(2, '0') + ':' + String(x % 60).padStart(2, '0');
}
const clock = t => { const abs = t + SHIFT_START, d = Math.floor(abs / 1440); return (d > 0 ? '+' + d + 'd ' : '') + hhmm(abs); };
function workingBetween(spans, a, b){
  let n = 0;
  for (const [s, e] of spans) n += Math.max(0, Math.min(b, e) - Math.max(a, s));
  return n;
}
function inkOn(hex){
  const n = parseInt(hex.slice(1), 16);
  return (0.299 * (n >> 16) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255 > 0.6 ? '#101720' : '#FFFFFF';
}

/* --------------------------------------------------------------- controls */
const SLIDER_LABEL = {
  holdMin: v => v ? v + ' min' : 'off', setupMin: v => v ? f1(v) + ' min' : 'off', travelMin: v => v ? f1(v) + ' min' : 'off',
  relaxMinH: v => v + ' h', relaxMaxH: v => v + ' h',
  pullAhead: v => v >= 99 ? 'all' : (v ? v + (v === 1 ? ' day' : ' days') : 'off'),
};
function syncControls(){
  $$('#tabLab button[data-k]').forEach(b => {
    const cur = lab[b.dataset.k], v = typeof cur === 'boolean' ? (cur ? '1' : '0') : String(cur);
    b.setAttribute('aria-pressed', String(v === b.dataset.v));
    if (b.dataset.k === 'moOneGroup') b.disabled = lab.seqMode === 'today';
  });
  $$('#tabLab input[data-k]').forEach(el => { el.value = lab[el.dataset.k]; });
  for (const k of Object.keys(SLIDER_LABEL)){ const el = $('lv_' + k); if (el) el.textContent = SLIDER_LABEL[k](lab[k]); }
  $$('#labViewSeg button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.view === view.kind)));
  $('labCycle').value = state.cycle; $('labCycleVal').textContent = state.cycle + ' days';
  $('labFleet').value = state.fleet; $('labFleetVal').textContent = fmt(state.fleet);
}

/* ------------------------------------------------------------------ tiles */
// The fleet card and six tiles for your selection. "vs today" is S0, the real Job Sequence on today's floor.
// Round trip and fleet are the Fleet settings (state.cycle, state.fleet).
function tiles(sel, s0){
  const cycle = state.cycle, fleet = state.fleet;
  const required = sel.trolleysPerDay * cycle, spare = fleet - required, short = spare < 0;
  $('labFleetCard').className = 'verdict ' + (short ? 'short' : 'ok');
  $('labFleetLabel').textContent = short ? 'The fleet does not cover this' : 'The fleet covers this';
  $('labFleetBig').textContent = fmt(required) + ' trolleys needed';
  $('labFleetSub').innerHTML = short
    ? `At <b>${fmt(sel.trolleysPerDay, 0)} trolleys a day</b> and a <b>${cycle}-day</b> round trip, ${fmt(required)} trolleys stay in circulation. You own ${fmt(fleet)} &mdash; <b>${fmt(-spare)} short</b>.`
    : `At <b>${fmt(sel.trolleysPerDay, 0)} trolleys a day</b> and a <b>${cycle}-day</b> round trip, ${fmt(required)} trolleys stay in circulation &mdash; <b>${fmt(spare)} spare</b> inside the ${fmt(fleet)} you own.`;
  $('labFleetDial').innerHTML = fleetDial(required, fleet);
  const d = (now, was, better, unit, dec) => {
    const diff = now - was;
    if (Math.abs(diff) < 0.05) return ['vs today: no change', ''];
    return [`vs today: ${diff > 0 ? '+' : ''}${fmt(diff, dec)}${unit}`, (better === 'up' ? diff > 0 : diff < 0) ? 'up' : 'down'];
  };
  const tile = (label, val, [txt, cls]) => `<div class="tile"><div class="k">${label}</div><div class="v">${val}</div><div class="d ${cls}">${txt}</div></div>`;
  const cyc = fleet / sel.trolleysPerDay, cyc0 = fleet / s0.trolleysPerDay;
  $('labTiles').innerHTML =
      tile('Compartments opened', f1(sel.utilizationPct) + '<em>%</em>', d(sel.utilizationPct, s0.utilizationPct, 'up', ' pt', 1))
    + tile('Compartment fill', f1(sel.fillPct) + '<em>%</em>', d(sel.fillPct, s0.fillPct, 'up', ' pt', 1))
    + tile('Garments loaded per trolley', fmt(sel.piecesPerTrolley, 0), d(sel.piecesPerTrolley, s0.piecesPerTrolley, 'up', '', 0))
    + tile('Trolleys out per day', fmt(sel.trolleysPerDay, 0), d(sel.trolleysPerDay, s0.trolleysPerDay, 'down', '', 0))
    + tile('Cycle the fleet covers', f1(cyc) + '<em> days</em>', d(cyc, cyc0, 'up', ' d', 1))
    + tile('Avg wait in WIP', sel.avgWaitH > 0 ? f1(sel.avgWaitH) + '<em> h</em>' : '<em>none</em>',
        [sel.avgWaitH > 0 ? fmt(lab.holdMin) + ' min allowed' : 'trolleys are not held', '']);
}

function badge(sel){
  const el = $('labBadge');
  const published = lab.plan === 'backlog' && lab.pullAhead === 0
    && lab.shift === 'both' && lab.relax === CFG.defaults.relax
    && lab.setupMin === CFG.defaults.setupMin && lab.travelMin === CFG.defaults.travelMin && lab.recall === 'model' && HOLDS.includes(lab.holdMin)
    && (!lab.moOneGroup || lab.seqMode === 'today')
    && lab.cutters === CFG.defaults.cutters && lab.tableM === CFG.defaults.tableM;
  if (published){
    const s = DATA.sweep[key(lab.seqMode, lab.batches, lab.holdMin, lab.anyWs ? 1 : 0)];
    const ok = !!s && Math.abs(sel.utilizationPct - s.utilization_pct) <= 0.0051 && Math.abs(sel.trolleysPerDay - s.trolleys_per_day) <= 0.051;
    el.className = 'parity ' + (ok ? 'ok' : 'bad');
    el.innerHTML = ok
      ? `<span class="num">Same as the published model</span> ${f2(s.utilization_pct)}% &middot; ${f1(s.trolleys_per_day)} trolleys a day`
      : `<span class="num">Differs from the published model</span> here ${f2(sel.utilizationPct)}% / ${f1(sel.trolleysPerDay)}, published ${s ? f2(s.utilization_pct) + '% / ' + f1(s.trolleys_per_day) : 'no entry'}`;
    return;
  }
  const on = [];
  if (lab.cutters !== CFG.defaults.cutters) on.push(lab.cutters + ' cutters');
  if (lab.tableM !== CFG.defaults.tableM) on.push(lab.tableM + ' m table');
  if (lab.pullAhead) on.push('pull-ahead');
  if (lab.shift !== 'both') on.push(lab.shift + ' shift only');
  if (lab.relax !== CFG.defaults.relax) on.push(lab.relax ? 'fabric relaxing' : 'no fabric relaxing');
  if (lab.setupMin !== CFG.defaults.setupMin || lab.travelMin !== CFG.defaults.travelMin) on.push('cutter setup/travel differ from the published ' + f1(CFG.defaults.setupMin) + ' / ' + f1(CFG.defaults.travelMin) + ' min');
  if (lab.recall !== 'model') on.push('same-batch recall');
  if (lab.moOneGroup && lab.seqMode !== 'today') on.push('MO kept on one cut group');
  if (!HOLDS.includes(lab.holdMin)) on.push('a hold length outside the published sweep');
  el.className = 'parity';
  el.innerHTML = 'Not the published model: ' + on.join(', ');
}

/* ------------------------------------------------ what one trolley looks like */
function trolleyPanel(sel){
  const util = sel.utilizationPct, cycle = state.cycle;
  $('labTrolley').innerHTML = trolleySvg(util);
  $('capDiv').textContent = A.trolley_compartments;
  const usedComp = util / 100 * A.trolley_compartments;
  const ceiling = A.trolley_compartments * A.compartment_cap;
  $('labTrolleyText').innerHTML =
    `<b>${usedComp.toFixed(2)} of ${A.trolley_compartments} compartments</b> get opened, on
     average, on every trolley that leaves Central Cutting &rarr; opened, they could hold
     <b>${fmt(sel.garmentsCapacity, 0)} garments</b> (${A.compartment_cap} each,
     rule H1) &rarr; they actually carry <b>${fmt(sel.piecesPerTrolley, 0)} garments</b>,
     because a compartment holds one size of one batch and the last compartment of each
     size takes the remainder &rarr; that is <b>${f1(sel.fillPct)}%</b>
     fill. The remaining <b>${(A.trolley_compartments - usedComp).toFixed(2)} compartments</b>
     travel the full ${cycle}-day round trip empty.<br><br>
     <b>${fmt(ceiling)}</b> is what a trolley could hold if every compartment opened full;
     <b>${fmt(sel.garmentsCapacity, 0)}</b> is what the compartments we opened
     could hold; <b>${fmt(sel.piecesPerTrolley, 0)}</b> is what is on board.`;
}

/* ------------------------------------------------- machine-time tables */
// the cut groups of an option set: its cutter count's layout (S0 has no `cutters` and gets today's 5)
const groupsOf = opt => CFG.cutGroupsByCount[opt.cutters || CFG.defaults.cutters];
// [key in the run's machine record, column name, legend colour]. The first is the working part; every part after it is
// lost time (lost = staffed - working). A cutter's "waiting for a table" includes the wait at the end of the run when the
// cutter has no more tables, because it is what is left of the staffed time. All hours are per working day: each run's
// own hours divided by its own number of working days.
const SP_PARTS = [['busy', 'Spreading (working)', 'var(--s2)'], ['blocked', 'Waiting for table space', 'var(--bad)'],
  ['starved', 'Nothing released', 'var(--muted)'], ['idle', 'Idle', 'var(--rule2)']];
const CU_PARTS = [['cut', 'Cutting (working)', 'var(--s2)'], ['setup', 'Setup (ESTIMATE)', 'var(--bad)'],
  ['travel', 'Travel (ESTIMATE)', '#8B6BB5'], ['idle', 'Waiting for a table', 'var(--muted)']];
const lostMin = (o, parts) => parts.slice(1).reduce((a, [k]) => a + o[k], 0);
const hd = (min, days) => min / 60 / days;
// a signed change at the shown precision; a change that rounds to zero carries no sign
const dsign = (v, dec) => { const r = +v.toFixed(dec); return (r > 0 ? '+' : r < 0 ? '&minus;' : '') + Math.abs(r).toFixed(dec); };
// green = better, red = worse: dir +1 = more is better, -1 = less is better (lost time, setup and travel are never better when higher)
const tone = (b, a, dir) => !dir || Math.abs(b - a) < 0.05 ? '' : ((b - a) * dir > 0 ? 'up' : 'down');

// nA, nB = how many machines S0 and your selection have (they differ when you pick more cutters)
function sumTable(id, parts, nA, nB, kind, a, b, dA, dB){
  const rows = [['Staffed', o => o.staffed, 0, null]]
    .concat(parts.map(([k, name, col], i) => [name, o => o[k], i === 0 ? 1 : -1, col]), [['Lost total', o => lostMin(o, parts), -1, null]]);
  const cols = '<th>S0</th><th>Yours</th><th>Change</th>';
  const all = nA === nB ? 'All ' + nA + ' ' + kind + 's' : 'All ' + kind + 's (S0 ' + nA + ', yours ' + nB + ')';
  let h = '<tr><th></th><th class="grp" colspan="3">Per ' + kind + ', h a day</th><th class="grp" colspan="3">' + all + ', h a day</th></tr>'
    + '<tr><th></th>' + cols + cols + '</tr>';
  for (const [name, get, dir, col] of rows) {
    const va = hd(get(a), dA), vb = hd(get(b), dB), t = tone(vb, va, dir), tp = tone(vb / nB, va / nA, dir);
    h += '<tr' + (name === 'Lost total' ? ' class="sel"' : '') + '><td>' + (col ? '<i class="chip" style="background:' + col + '"></i>' : '') + name + '</td>'
      + '<td>' + f2(va / nA) + '</td><td>' + f2(vb / nB) + '</td><td class="' + tp + '">' + dsign(vb / nB - va / nA, 2) + '</td>'
      + '<td>' + f1(va) + '</td><td>' + f1(vb) + '</td><td class="' + t + '">' + dsign(vb - va, 1) + '</td></tr>';
  }
  $(id).innerHTML = h;
}

function eachTable(id, parts, names, aMap, bMap, dA, dB){
  let h = '<tr><th></th><th class="grp" colspan="2">Working, h a day</th><th class="grp" colspan="2">Lost, h a day</th><th></th></tr>'
    + '<tr><th>Machine</th><th>S0</th><th>Yours</th><th>S0</th><th>Yours</th><th>Change in lost</th></tr>';
  for (const name of names) {
    const a = aMap[name], b = bMap[name];
    if (!a || !b) { h += '<tr><td>' + name + '</td><td>&mdash;</td><td>&mdash;</td><td>&mdash;</td><td>&mdash;</td><td></td></tr>'; continue; }
    const k = parts[0][0], w0 = hd(a[k], dA), w1 = hd(b[k], dB), l0 = hd(lostMin(a, parts), dA), l1 = hd(lostMin(b, parts), dB);
    h += '<tr><td>' + name + '</td><td>' + f1(w0) + '</td><td>' + f1(w1) + '</td><td>' + f1(l0) + '</td><td>' + f1(l1) + '</td>'
      + '<td class="' + tone(l1, l0, -1) + '">' + dsign(l1 - l0, 1) + '</td></tr>';
  }
  $(id).innerHTML = h;
}

function machineTables(sel, s0){
  const dA = s0.finishHours / s0.dayWindowHours, dB = sel.finishHours / sel.dayWindowHours;
  const byName = (list, key) => { const m = {}; for (const x of list) m[x[key]] = x; return m; };
  const groups = groupsOf(lab);          // the selection's cut groups; S0's are the first five cutters, the same spreaders
  const spNames = [].concat(...Object.keys(groups).map(c => groups[c])), cuNames = Object.keys(groups);
  sumTable('labSpreadSum', SP_PARTS, s0.spM.length, sel.spM.length, 'spreader', s0.sp, sel.sp, dA, dB);
  sumTable('labCutSum', CU_PARTS, s0.cuM.length, sel.cuM.length, 'cutter', s0.cu, sel.cu, dA, dB);
  eachTable('labSpreadEach', SP_PARTS, spNames, byName(s0.spM, 'm'), byName(sel.spM, 'm'), dA, dB);
  eachTable('labCutEach', CU_PARTS, cuNames, byName(s0.cuM, 'c'), byName(sel.cuM, 'c'), dA, dB);
}

/* ----------------------------------------------------------------- output */
const reqN = () => fmt(CFG.required);
const cache100 = new Map();
function runOpt100(opt){
  const k = JSON.stringify(opt);
  if (!cache100.has(k)) cache100.set(k, E.run100k(INPUT, opt));
  return cache100.get(k);
}
function outputs(sel, s0, sel100, s0100){
  const row = (name, a, b) => {
    const x = a.output.cutPerDay, y = b.output.cutPerDay, d = y - x, same = Math.abs(d) < 0.5;
    const sign = d > 0 ? '+' : '&minus;';
    return '<tr><td>' + name + ' (' + b.days + ' plan dates)</td><td>' + fmt(Math.round(x)) + '</td><td>' + fmt(Math.round(y)) + '</td>'
      + '<td class="' + (same ? '' : d > 0 ? 'up' : 'down') + '">'
      + (same ? 'no change' : sign + fmt(Math.round(Math.abs(d))) + ' (' + sign + f2(100 * Math.abs(d) / x) + '%)') + '</td></tr>';
  };
  $('labOut').innerHTML = '<tr><th>Pieces cut a day</th><th>S0 Today</th><th>Your selection</th><th>Change</th></tr>'
    + row('Real plan', s0, sel) + row(reqN() + '-a-day plan', s0100, sel100);
}
function dayChart(sel, s0){
  const W = 760, H = 170, L = 34, R = 10, Tp = 10, B = 28, n = sel.perDay.length;
  const x = i => L + (n < 2 ? 0 : (W - L - R) * i / (n - 1)), y = p => Tp + (H - Tp - B) * (1 - p / 100);
  const line = (r, col, w) => '<polyline fill="none" stroke="' + col + '" stroke-width="' + w + '" points="'
    + r.perDay.map((d, i) => x(i).toFixed(1) + ',' + y(d.planned ? 100 * d.onTime / d.planned : 0).toFixed(1)).join(' ') + '"/>';
  let s = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Share of each plan date's tables cut inside its own window">`;
  for (const p of [0, 50, 100]) s += `<line x1="${L}" x2="${W - R}" y1="${y(p)}" y2="${y(p)}" stroke="var(--rule)"/>`
    + `<text x="${L - 6}" y="${y(p) + 3}" text-anchor="end" font-size="10" fill="var(--muted)">${p}%</text>`;
  s += line(s0, 'var(--muted)', 1.5) + line(sel, 'var(--s1)', 2);
  const step = Math.max(1, Math.round(n / 8));
  for (let i = 0; i < n; i += step) s += `<text x="${x(i)}" y="${H - 8}" text-anchor="middle" font-size="10" fill="var(--muted)">${sel.perDay[i].date.slice(5)}</text>`;
  $('labDays').innerHTML = '<div class="legend" style="margin:0 0 6px"><span><i style="background:var(--s1)"></i>Your selection</span>'
    + '<span><i style="background:var(--muted)"></i>S0 Today</span></div>' + s + '</svg>';
}

/* ------------------------------------------------- the arrangement (Gantt) */
// one block per cut group: its spreaders, then its cutter; the groups are those of the option set's cutter count
function rowsOf(opt){
  const rows = [], g = groupsOf(opt);
  for (const c of Object.keys(g)){
    for (const m of g[c]) rows.push({key: 'S' + m, label: 'SPD ' + m, kind: 'spd', name: m});
    rows.push({key: 'C' + c, label: 'CUT ' + c.replace('24', ''), kind: 'cut', name: c});
    rows.push({kind: 'gap'});
  }
  rows.pop();
  return rows;
}
const LABELS = {normal: 'Normal condition', stretch: 'Normal · stretch spreading',
  no_fabric_time: 'Have pattern, not enough fabric', completed: 'Completed'};
const GANTT_MIN_WIDTH = 1120;

function currentRun(){
  const opt = view.kind === 'sel' ? lab : Lab.ladder(lab, V)[0].opt;
  return runOpt(opt);
}
function batchLast(t){
  const d = T.days[t.date];
  return !!(d && d.tasks[t.i] && d.tasks[t.i][14]);
}
function ganttSvg(r, off0, xmax, drawn){
  const dt = r.detail, di = dt.dates.indexOf(view.date);
  const W = Math.max(GANTT_MIN_WIDTH, Math.round($('labGantt').parentElement.clientWidth) || GANTT_MIN_WIDTH);
  const L = 96, Rr = 14, H_ROW = 23, H_GAP = 9;
  const x = v => L + (W - L - Rr) * Math.max(0, Math.min(xmax, v)) / xmax;
  const RIBBON_Y = 20, RIBBON_H = 8, RIBBON_GAP = 3, RIBBON_BOTTOM = RIBBON_Y + 2 * RIBBON_H + RIBBON_GAP;
  const opt = view.kind === 'sel' ? lab : Lab.ladder(lab, V)[0].opt;
  const ROWS = rowsOf(opt);
  let y = RIBBON_BOTTOM + 10; const top = {};
  for (const rw of ROWS){ if (rw.kind !== 'gap') top[rw.key] = y; y += rw.kind === 'gap' ? H_GAP : H_ROW; }
  const H = y + 8;

  // staffed spans of the drawn window, one set per machine
  const spanCache = {};
  const spansOf = (name, kind) => {
    const k = kind + name;
    if (!spanCache[k]){
      const night = kind === 'spd' ? NIGHT_SP.has(name) : NIGHT_CU.has(name);
      const ds = E.daySpans(opt.shift, night), out = [];
      for (let j = di; j < dt.dates.length; j++){
        const o = dt.off[j] - off0;
        if (o >= xmax) break;
        for (const [a, b] of ds) out.push([o + a, o + b]);
      }
      spanCache[k] = out;
    }
    return spanCache[k];
  };

  let s = `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img"
    aria-label="Job sequence for ${view.date}: ${drawn.length} tables across ${ROWS.filter(rw => rw.kind === 'spd').length} spreading machines">
    <defs><pattern id="lblk" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <line x1="0" y1="0" x2="0" y2="5" stroke="var(--bad)" stroke-width="1.6" opacity=".45"/></pattern>
    <pattern id="lstv" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(-45)">
      <line x1="0" y1="0" x2="0" y2="5" stroke="var(--muted)" stroke-width="1.6" opacity=".6"/></pattern>
    <pattern id="lovl" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <line x1="0" y1="0" x2="0" y2="5" stroke="var(--muted)" stroke-width="1.4" opacity=".55"/></pattern></defs>`;

  for (let t = (60 - SHIFT_START % 60) % 60; t <= xmax; t += 60){
    s += `<line x1="${x(t)}" x2="${x(t)}" y1="${RIBBON_BOTTOM + 2}" y2="${H - 6}" stroke="var(--rule)" stroke-width="1"/>`;
    if ((t + SHIFT_START) % 120 === 0)
      s += `<text x="${x(t)}" y="14" text-anchor="middle" class="num" font-size="9.5" fill="var(--muted)">${clock(t)}</text>`;
  }
  // shift ribbon from the engine's own shift option
  {
    const dayEnd = CFG.dayShift[1], nStart = CFG.nightShift[0], nEnd = CFG.nightShift[1];
    const nightY = RIBBON_Y + RIBBON_H + RIBBON_GAP;
    if (opt.shift !== 'night'){
      s += `<rect x="${x(0)}" y="${RIBBON_Y}" width="${Math.max(0, x(dayEnd) - x(0))}" height="${RIBBON_H}" rx="1.5" fill="var(--s1)" opacity=".28"><title>DAY ${clock(0)}–${clock(dayEnd)}</title></rect>`;
      s += `<text x="${x(0) + 3}" y="${RIBBON_Y + RIBBON_H - 1.5}" font-size="7" class="num" fill="var(--s1)" pointer-events="none">DAY</text>`;
    }
    if (opt.shift !== 'day'){
      const from = opt.shift === 'night' ? nStart : dayEnd;
      s += `<rect x="${x(from)}" y="${nightY}" width="${Math.max(0, x(nEnd) - x(from))}" height="${RIBBON_H}" rx="1.5" fill="var(--s3)" opacity=".38"><title>NIGHT ${clock(from)}–${clock(nEnd)} · ${CFG.nightSpreaders.join('/')} · ${CFG.nightCutters.join('/')}</title></rect>`;
      s += `<text x="${x(from) + 3}" y="${nightY + RIBBON_H - 1.5}" font-size="7" class="num" fill="var(--s3)" pointer-events="none">NIGHT · ${CFG.nightSpreaders.join('/')} + ${CFG.nightCutters.join('/')}</text>`;
    }
  }
  // when each machine is staffed; outside it the row is dead
  for (const rw of ROWS){
    if (rw.kind === 'gap') continue;
    const spans = spansOf(rw.name, rw.kind), ry = top[rw.key];
    let cursor = 0;
    for (const [from, to] of spans){
      if (from > cursor) s += `<rect x="${x(cursor)}" y="${ry}" width="${x(from) - x(cursor)}" height="${H_ROW - 3}" fill="var(--rule2)" opacity=".28"><title>Break</title></rect>`;
      cursor = Math.max(cursor, to);
    }
    if (cursor < xmax) s += `<rect x="${x(cursor)}" y="${ry}" width="${x(xmax) - x(cursor)}" height="${H_ROW - 3}" fill="var(--rule2)" opacity=".28"><title>Not staffed${spans.length ? ' — this machine\'s shift ended at ' + clock(cursor) : ' in this shift option'}</title></rect>`;
    s += `<text x="0" y="${ry + 13}" font-size="10" class="num" fill="var(--${rw.kind === 'cut' ? 'ink' : 'muted'})" font-weight="${rw.kind === 'cut' ? 600 : 400}">${rw.label}</text>`;
    s += `<line x1="${L}" x2="${W - Rr}" y1="${ry + H_ROW - 3}" y2="${ry + H_ROW - 3}" stroke="var(--rule)" stroke-width="1" opacity="${rw.kind === 'cut' ? 1 : .45}"/>`;
  }
  // starved gaps (nothing released), staffed part only
  for (const m of Object.keys(dt.starved)){
    if (top['S' + m] === undefined) continue;
    const sp = spansOf(m, 'spd');
    for (const [a, b] of dt.starved[m]){
      const a0 = Math.max(0, a - off0), b0 = Math.min(xmax, b - off0);
      if (b0 <= a0) continue;
      const w = workingBetween(sp, a0, b0);
      if (w > 0.5) s += `<rect x="${x(a0)}" y="${top['S' + m] + 3}" width="${Math.max(1, x(b0) - x(a0))}" height="${H_ROW - 9}" fill="url(#lstv)"><title>Starved ${Math.round(w)} min — nothing released yet (fabric not relaxed, or the plan date had not begun)</title></rect>`;
    }
  }
  const byId = new Map(drawn.map(t => [t.id, t]));
  const pairOf = new Map();
  for (const [a, b] of dt.pairs) if (byId.has(a) && byId.has(b) && byId.get(a).m === byId.get(b).m) pairOf.set(a, b);

  for (const t of drawn){
    const sb = t.sbA - off0, se = t.seA - off0, cb = t.cbA - off0, ce = t.ceA - off0;
    const ready = t.readyAbs - off0, finite = isFinite(ready);
    const cursor = view.cursor;
    let st;
    if (ce <= cursor) st = 'completed';
    else if (finite && ready > cursor) st = 'no_fabric_time';
    else st = batchLast(t) ? 'stretch' : 'normal';
    const col = SCOL[st], rowY = top['S' + t.m], other = t.date !== view.date;
    const blockFrom = Math.max(0, t.blockFromA - off0);
    const sp = spansOf(t.m, 'spd');
    const blockedMin = workingBetween(sp, blockFrom, Math.max(blockFrom, sb));
    if (blockedMin > 0.5)
      s += `<rect x="${x(blockFrom)}" y="${rowY + 3}" width="${Math.max(1, x(sb) - x(blockFrom))}" height="${H_ROW - 9}" fill="url(#lblk)"><title>Blocked ${Math.round(blockedMin)} min — not enough table free for the next lay (G6)</title></rect>`;
    const tip = `${t.tableNo} · MO ${t.mo} · ${t.color} · batch ${t.batch}` + (other ? ' · plan date ' + t.date : '')
      + ` · spread ${Math.round(t.spread)} min · cut ${Math.round(t.cut)} min · spread ${clock(sb)}–${clock(se)} · cut ${clock(cb)}–${clock(ce)}`
      + (finite ? ' · fabric ready ' + clock(ready) : '') + (t.setup ? ' · setup ' + f1(t.setup) + ' min' : '')
      + (t.travel ? ' · travel ' + f1(t.travel) + ' min' : '') + (blockedMin > 0.5 ? ' · blocked ' + Math.round(blockedMin) + ' min' : '')
      + ' · ' + LABELS[st];
    const w = Math.max(1, x(se) - x(sb));
    s += `<rect x="${x(sb)}" y="${rowY + 2}" width="${w}" height="${H_ROW - 7}" rx="1.5" fill="${col}" stroke="rgba(16,23,32,.35)" stroke-width=".6"><title>SPD ${t.m} — ${tip}</title></rect>`;
    if (other) s += `<rect x="${x(sb)}" y="${rowY + 2}" width="${w}" height="${H_ROW - 7}" rx="1.5" fill="none" stroke="var(--s3)" stroke-width="1.4" stroke-dasharray="2 2"><title>Plan date ${t.date}</title></rect>`;
    const name = String(t.tableNo == null ? '' : t.tableNo);
    if (w >= name.length * 5.6 + 6) s += `<text x="${x(sb) + w / 2}" y="${rowY + H_ROW / 2 + 1}" text-anchor="middle" class="num" font-size="8.5" font-weight="600" fill="${inkOn(col)}" pointer-events="none">${name}</text>`;

    // cutter: setup, travel, then the cut
    const cutY = top['C' + t.cutter], cStart = Math.min(ce, cb + t.setup + t.travel);
    if (t.setup > 0) s += `<rect x="${x(cb)}" y="${cutY + 4}" width="${Math.max(1, x(cb + t.setup) - x(cb))}" height="${H_ROW - 11}" fill="var(--bad)" opacity=".85"><title>Setup ${f1(t.setup)} min — MO or colour changed (ESTIMATE) · table ${t.tableNo}</title></rect>`;
    if (t.travel > 0) s += `<rect x="${x(cb + t.setup)}" y="${cutY + 4}" width="${Math.max(1, x(cb + t.setup + t.travel) - x(cb + t.setup))}" height="${H_ROW - 11}" fill="#8B6BB5" opacity=".9"><title>Travel ${f1(t.travel)} min — to workstation ${t.m} (ESTIMATE) · table ${t.tableNo}</title></rect>`;
    const cw = Math.max(1, x(ce) - x(cStart));
    s += `<rect x="${x(cStart)}" y="${cutY + 4}" width="${cw}" height="${H_ROW - 11}" rx="1.5" fill="${col}" opacity=".62" stroke="rgba(16,23,32,.3)" stroke-width=".6"><title>CUT ${t.cutter} — ${tip}</title></rect>`;

    if (pairOf.has(t.id)){
      const o = byId.get(pairOf.get(t.id)), x1 = x(sb), x2 = x(Math.max(se, o.seA - off0)), by = rowY - 1;
      s += `<path d="M${x1} ${by + 3} L${x1} ${by} L${x2} ${by} L${x2} ${by + 3}" fill="none" stroke="var(--ink)" stroke-width="1.2" opacity=".8"${o.batch !== t.batch ? ' stroke-dasharray="3 2"' : ''}><title>${o.batch !== t.batch ? 'Two batches' : 'Same batch'}, back-to-back: tables ${t.tableNo} + ${o.tableNo}</title></path>`;
    }
  }
  if (view.cursor >= 0 && view.cursor <= xmax){
    s += `<line x1="${x(view.cursor)}" x2="${x(view.cursor)}" y1="18" y2="${H - 4}" stroke="var(--s1)" stroke-width="1.5"/>`
      + `<text x="${x(view.cursor)}" y="${H - 6}" text-anchor="middle" class="num" font-size="9" fill="var(--s1)" font-weight="600">${clock(view.cursor)}</text>`;
  }
  return s + '</svg>';
}

function arrangement(){
  if (!INPUT) return;
  const r = currentRun(), dt = r.detail, di = dt.dates.indexOf(view.date);
  if (di < 0) return;
  const off0 = dt.off[di], win = E.windowOf(view.kind === 'sel' ? lab.shift : lab.shift);
  let ownLast = 0;
  for (const t of dt.tasks) if (t.dayIdx === di) ownLast = Math.max(ownLast, t.ceA - off0);
  const xmax = Math.min(4320, Math.max(win[1], Math.ceil(ownLast / 60) * 60));
  const drawn = dt.tasks.filter(t => t.ceA > off0 && t.sbA - off0 < xmax);
  const cur = $('labCursor');
  cur.max = xmax;
  if (view.cursor > xmax) view.cursor = xmax;
  cur.value = view.cursor;
  $('labCursorVal').textContent = clock(view.cursor);
  $('labGanttDate').textContent = view.date + (view.kind === 'sel' ? '' : ' (S0 Today)');
  $('labGantt').innerHTML = ganttSvg(r, off0, xmax, drawn);
  const own = drawn.filter(t => t.date === view.date).length;
  $('labGanttNote').textContent = `${own} tables planned for ${view.date}` + (drawn.length > own ? `, ${drawn.length - own} more from other plan dates (dashed outline)` : '')
    + '. Carry-over: work the days before did not finish is still on the machines at 07:15 (dashed outline), and what this date does not finish carries into the next shift.';
  idleTable();
}

/* --------------------------------------------------------------- idle time */
// Per cut group, for the tables planned for the viewed plan date: hours of cutting, and hours the group's spreaders wait
// for table space (rule G6). S0 is today's floor; a group S0 does not have (an added cutter) shows a dash.
function idleTable(){
  if (!INPUT) return;
  const mine = runOpt(lab), base = runOpt(Lab.ladder(lab, V)[0].opt);
  const tally = r => {
    const gm = r.detail.groupMembers, grp = {}, out = {};
    for (const c of Object.keys(gm)){ out[c] = {n: gm[c].length, cut: 0, blk: 0}; for (const m of gm[c]) grp[m] = c; }
    for (const t of r.detail.tasks){
      if (t.date !== view.date) continue;
      if (out[t.cutter]) out[t.cutter].cut += t.cut / 60;
      if (out[grp[t.m]]) out[grp[t.m]].blk += t.blockedStaffed / 60;
    }
    return out;
  };
  const a = tally(base), b = tally(mine);
  $('labIdleDate').textContent = view.date;
  const trio = (x, y, dir) => x === null
    ? '<td>&mdash;</td><td>' + f1(y) + '</td><td></td>'
    : '<td>' + f1(x) + '</td><td>' + f1(y) + '</td><td class="' + tone(y, x, dir) + '">' + dsign(y - x, 1) + '</td>';
  let h = '<tr><th></th><th></th><th class="grp" colspan="3">Cutting, h</th><th class="grp" colspan="3">Waiting for table space, h</th></tr>'
    + '<tr><th>Cut group</th><th>Spreaders</th><th>S0</th><th>Yours</th><th>Change</th><th>S0</th><th>Yours</th><th>Change</th></tr>';
  const tot = {n: 0, cut0: 0, cut1: 0, blk0: 0, blk1: 0};
  for (const c of Object.keys(b)){
    if (!b[c].n && !(a[c] && a[c].n)) continue;
    const x = a[c] && a[c].n ? a[c] : null;
    tot.n += b[c].n; tot.cut1 += b[c].cut; tot.blk1 += b[c].blk;
    if (x) { tot.cut0 += x.cut; tot.blk0 += x.blk; }
    h += '<tr><td>' + c + (x ? '' : ' <span class="d">new</span>') + '</td><td>' + b[c].n + '</td>'
      + trio(x && x.cut, b[c].cut, 0) + trio(x && x.blk, b[c].blk, -1) + '</tr>';
  }
  h += '<tr class="sel"><td>All</td><td>' + tot.n + '</td>' + trio(tot.cut0, tot.cut1, 0) + trio(tot.blk0, tot.blk1, -1) + '</tr>';
  $('labIdle').innerHTML = h;
}
function legend(){
  const sw = (c, n, extra) => `<span><i style="background:${c}"${extra || ''}></i>${n}</span>`;
  $('labLegend').innerHTML = ['normal', 'stretch', 'no_fabric_time', 'completed'].map(k => sw(SCOL[k], LABELS[k])).join('')
    + sw('repeating-linear-gradient(45deg,var(--bad) 0 1.5px,transparent 1.5px 4px)', 'Blocked, table full (G6)')
    + sw('repeating-linear-gradient(-45deg,var(--muted) 0 1.5px,transparent 1.5px 4px)', 'Starved, nothing released')
    + sw('var(--bad)', 'Cutter setup') + sw('#8B6BB5', 'Cutter travel') + sw('transparent', 'Other plan date (dashed)', ' style="border:1.4px dashed var(--s3)"')
    + sw('transparent', 'Bracket: back-to-back pair (dashed = two batches)', ' style="border-top:2px solid var(--ink)"');
}

/* ---------------------------------------------------------- panel loading */
function loadPanel(){
  if (!INPUT) return;
  const r = currentRun(), dt = r.detail, di = dt.dates.indexOf(view.date), off0 = dt.off[di];
  $('labLoadDate').textContent = view.date;
  const list = dt.trolleys.filter(tr => dt.tasks[tr.comps[0].tasks[0]].dayIdx === di);
  const pieces = list.reduce((n, tr) => n + tr.comps.reduce((a, c) => a + c.qty, 0), 0);
  const comps = list.reduce((n, tr) => n + tr.comps.length, 0);
  $('labLoadSummary').textContent = `${list.length} trolleys · ${comps} compartments · ${fmt(pieces)} pieces · ${f1(pct(comps, 5 * list.length))}% opened`;
  let h = '<thead><tr><th>Trolley</th><th>Film</th><th class="n">Compartments</th><th class="n">Opened</th><th class="n">Pieces</th>'
    + '<th>Batches</th><th>Tables it carries</th><th>Recalled</th><th>Left at</th></tr></thead><tbody>';
  list.forEach((tr, i) => {
    const used = tr.comps.length, qty = tr.comps.reduce((n, c) => n + c.qty, 0);
    const tables = [...new Set(tr.comps.flatMap(c => c.tasks.map(id => dt.tasks[id].tableNo)))];
    const same = tr.comps.filter(c => c.recalled === 'same').length, cross = tr.comps.filter(c => c.recalled === 'cross').length;
    const fill = 100 * used / 5;
    h += `<tr><td class="num">#${String(i + 1).padStart(3, '0')}</td><td class="num">${tr.film}</td><td class="n">${used} of 5</td>`
      + `<td class="n" style="color:${fill >= 80 ? 'var(--s2)' : fill <= 40 ? 'var(--bad)' : 'inherit'}">${fill.toFixed(0)}%</td>`
      + `<td class="n">${qty}</td><td class="num">${tr.batches.join(', ')}</td><td class="num">${tables.join(', ')}</td>`
      + `<td class="num">${same || cross ? (same ? same + ' same batch' : '') + (same && cross ? ', ' : '') + (cross ? cross + ' other batch' : '') : '—'}</td>`
      + `<td class="num">${clock(tr.leftAt - off0)}</td></tr>`;
  });
  $('labTrolleyTable').innerHTML = h + '</tbody>';
  const byFilm = new Map();
  list.forEach(tr => { if (!byFilm.has(tr.film)) byFilm.set(tr.film, []); byFilm.get(tr.film).push(tr); });
  const LIMIT = 60;
  let html = '';
  for (const f of [...byFilm.keys()].sort((a, b) => a - b)){
    const l = byFilm.get(f), shown = view.showAll ? l : l.slice(0, LIMIT);
    html += `<div class="filmhead">FILM ${f} &mdash; ${l.length} trolleys, ${l.filter(t => t.comps.length === 5).length} of them full`
      + (shown.length < l.length ? `, showing ${shown.length}` : '') + '</div><div class="trolleyrow">';
    for (const tr of shown){
      html += `<div class="tcard"><div class="h"><span>${String(tr.mo).slice(-5)}</span><span>${tr.comps.length}/5</span></div>`;
      for (let k = 4; k >= 0; k--){
        const c = tr.comps[k];
        if (!c){ html += '<div class="c empty"></div>'; continue; }
        const tint = tr.batches.indexOf(c.batch) === 0 ? 'var(--s2)' : 'var(--s3)';
        html += `<div class="c" style="background:${tint}" title="batch ${c.batch}${c.recalled ? ' — loaded after recall from WIP (' + c.recalled + ' batch)' : ''}"><span>${c.qty}</span><span>${c.recalled ? '↺' : ''}${tr.batches.length > 1 ? tr.batches.indexOf(c.batch) + 1 : ''}</span></div>`;
      }
      html += `<div class="h" style="margin:5px 0 0"><span>${tr.batches.length} batch${tr.batches.length > 1 ? 'es' : ''}</span></div></div>`;
    }
    html += '</div>';
  }
  if (!view.showAll && [...byFilm.values()].some(l => l.length > LIMIT))
    html += '<div class="hint"><button type="button" class="theme" id="labShowAll">Show every trolley</button></div>';
  $('labTrolleys').innerHTML = html || '<div class="hint">No trolleys opened for this date.</div>';
  const b = $('labShowAll'); if (b) b.addEventListener('click', () => { view.showAll = true; loadPanel(); });
}

/* ------------------------------------------------------------- the render */
function render(){
  if (!INPUT) return;
  let sel, s0, sel100, s0100;
  try {
    sel = runOpt(lab);
    s0 = runOpt(Lab.ladder(lab, V)[0].opt);
    sel100 = runOpt100(lab); s0100 = runOpt100(Lab.ladder(lab, V)[0].opt);
  } catch (e) { $('labStatus').textContent = 'Cannot run this combination: ' + e.message; return; }
  tiles(sel, s0); trolleyPanel(sel); badge(sel); outputs(sel, s0, sel100, s0100); machineTables(sel, s0); dayChart(sel, s0);
  legend(); arrangement(); loadPanel();
  let msg = `${sel.tasks} tables over ${sel.days} plan dates, ${fmt(sel.trolleys)} trolleys, ${fmt(sel.combines)} combines, recalls ${fmt(sel.recallsSame)} same-batch / ${fmt(sel.recallsCross)} other-batch.`;
  if (lab.shift === 'night') msg += ` Night staffs 3 of 13 spreaders and one cutter: this plan needs about ${Math.ceil(sel.finishMin / 1440)} calendar days.`;
  else if (sel.backlogTables) msg += ` ${fmt(sel.backlogTables)} tables are still uncut when the last plan date's window closes.`;
  $('labStatus').textContent = msg;
}
function schedule(){ $('labStatus').textContent = 'Calculating...'; clearTimeout(timer); timer = setTimeout(render, 20); }

function buildCalendar(){
  const dates = T.dates, first = new Date(dates[0] + 'T00:00:00');
  const year = first.getFullYear(), month = first.getMonth();
  $('labCalMonth').textContent = first.toLocaleDateString('en-US', {month: 'long', year: 'numeric'});
  const days = new Date(year, month + 1, 0).getDate(), lead = (new Date(year, month, 1).getDay() + 6) % 7;
  let h = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map(d => `<div class="dow">${d}</div>`).join('');
  for (let i = 0; i < lead; i++) h += '<span></span>';
  for (let d = 1; d <= days; d++){
    const iso = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
    h += dates.includes(iso)
      ? `<button type="button" data-lday="${iso}" aria-pressed="${iso === view.date}" title="${iso}">${d}</button>`
      : `<span title="not in the data">${d}</span>`;
  }
  $('labCalendar').innerHTML = h;
  $$('#labCalendar [data-lday]').forEach(b => b.addEventListener('click', () => {
    view.date = b.dataset.lday; view.cursor = 0; view.showAll = false;
    $$('#labCalendar [data-lday]').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
    arrangement(); loadPanel();
  }));
}

function wire(){
  wired = true;
  $$('#tabLab button[data-k]').forEach(b => b.addEventListener('click', () => {
    const k = b.dataset.k, cur = lab[k], v = b.dataset.v;
    lab[k] = typeof cur === 'boolean' ? v === '1' : typeof cur === 'number' ? +v : v;
    if (k === 'seqMode') lab.ruleA = lab.seqMode !== 'today';
    if (k === 'batches') lab.mix = lab.batches >= 2;
    syncControls(); schedule();
  }));
  $$('#tabLab input[data-k]').forEach(el => el.addEventListener('input', () => {
    const k = el.dataset.k; lab[k] = +el.value;
    if (k === 'relaxMinH' && lab.relaxMinH > lab.relaxMaxH) lab.relaxMaxH = lab.relaxMinH;
    if (k === 'relaxMaxH' && lab.relaxMaxH < lab.relaxMinH) lab.relaxMinH = lab.relaxMaxH;
    syncControls(); schedule();
  }));
  $('labReset').addEventListener('click', () => {
    lab = Object.assign({}, DEF); state.cycle = A.cycle_days_estimated; state.fleet = A.fleet_size;
    syncControls(); schedule();
  });
  $('labCycle').addEventListener('input', e => { state.cycle = +e.target.value; syncControls(); schedule(); });
  $('labFleet').addEventListener('input', e => { state.fleet = +e.target.value; syncControls(); schedule(); });
  $$('#labViewSeg button').forEach(b => b.addEventListener('click', () => {
    view.kind = b.dataset.view; view.cursor = 0; syncControls(); arrangement(); loadPanel();
  }));
  $('labCursor').addEventListener('input', e => {
    view.cursor = +e.target.value;
    if (!frame) frame = requestAnimationFrame(() => { frame = 0; $('labCursorVal').textContent = clock(view.cursor); arrangement(); });
  });
}
function show(){
  $('labDates').textContent = DATA.planDates;
  if (!wired){
    $('labCutterSeg').innerHTML = CFG.cutterCounts.map(n => `<button type="button" data-k="cutters" data-v="${n}" aria-pressed="false">${n}</button>`).join('');
    $('labTableSeg').innerHTML = CFG.tableOptionsM.map(m => `<button type="button" data-k="tableM" data-v="${m}" aria-pressed="false">${m} m</button>`).join('');
  }
  syncControls(); buildCalendar();
  if (!wired) wire();
  $('labStatus').textContent = 'Loading task data...';
  load().then(schedule, e => { $('labStatus').textContent = 'Could not unpack the task data: ' + e.message; });
}

/* Parity, async (the page unzips its data first). Three things:
   1. option sets Node ran with the same lab.js, re-run here;
   2. every published scenario against the published sweep
      (DATA.sweep, at its published rounding);
   3. this month's Job Sequence against the model's trace. */
async function __labCheck(){
  await load();
  const fails = []; const part = {addons: 0, sweep: 0, trace: 0};
  const close = (a, b, tol) => Math.abs(a - b) <= tol;
  for (const e of DATA.lab.expected){
    const got = Lab.summary(E.run(INPUT, e.opt));
    for (const k of Object.keys(e.r)){
      part.addons++;
      if (!close(got[k], e.r[k], 1e-6 * Math.max(1, Math.abs(e.r[k])))) fails.push({part: 'addons', opt: e.opt, k, page: got[k], node: e.r[k]});
    }
  }
  for (const e of DATA.lab.expected100){
    const got = Lab.summary(E.run100k(INPUT, e.opt));
    for (const k of Object.keys(e.r)){
      part.addons++;
      if (!close(got[k], e.r[k], 1e-6 * Math.max(1, Math.abs(e.r[k])))) fails.push({part: 'addons', plan: '100k', opt: e.opt, k, page: got[k], node: e.r[k]});
    }
  }
  for (const k of Object.keys(DATA.sweep)){
    const r = E.run(INPUT, Lab.optFromSweepKey(k)), s = DATA.sweep[k];
    const pairs = [['utilization_pct', r.utilizationPct, 0.0051], ['trolleys_per_day', r.trolleysPerDay, 0.051],
      ['peak', r.model.peak, 0], ['pieces_per_trolley', r.piecesPerTrolley, 0.51], ['compartment_fill_pct', r.fillPct, 0.051],
      ['garments_per_trolley_capacity', r.garmentsCapacity, 0.51], ['avg_wait_hours', r.avgWaitH, 0.0051],
      ['spreading_blocked_pct', r.model.spreadingBlockedPct, 0.051], ['cutting_blocked_pct', r.model.cuttingBlockedPct, 0.051],
      ['blocked_by_space', r.blockedBySpace, 0]];
    for (const [f, got, tol] of pairs){
      part.sweep++;
      if (!close(got, s[f], tol)) fails.push({part: 'sweep', k, f, page: got, tab: s[f]});
    }
  }
  for (const mode of ['today', 'same_batch', 'cross_batch']){
    const dt = E.run(INPUT, Lab.optFromSweepKey(mode + '|1|0|1')).detail;
    const byDate = {};
    for (const t of dt.tasks) (byDate[t.date] || (byDate[t.date] = [])).push(t);
    for (const date of T.dates){
      const v = T.days[date].seq[mode].table[DATA.baselineVariant];
      const mach = {};
      for (const m of Object.keys(v.order)) for (const idx of v.order[m]) mach[idx] = m;
      const o0 = dt.off[dt.dates.indexOf(date)];     // the trace's times are from each plan date's own 07:15
      byDate[date].forEach((t, i) => {
        part.trace++;
        const ok = mach[i] === t.m && v.cutters[v.time.cut[i]] === t.cutter && close(v.time.ss[i], t.sbA - o0, 0.0501)
          && close(v.time.se[i], t.seA - o0, 0.0501) && close(v.time.cs[i], t.cbA - o0, 0.0501) && v.time.ce[i] === t.ceA - o0;
        if (!ok) fails.push({part: 'trace', mode, date, table: t.tableNo});
      });
    }
  }
  const checks = part.addons + part.sweep + part.trace;
  return {file: DATA.month, checks, part, pass: checks - fails.length, fail: fails.length, fails: fails.slice(0, 25)};
}
return {show, __labCheck, load, runOpt, lab: () => lab};
})();
if (LABUI){
  window.__LAB = LABUI;
  LABUI.show();
} else {
  $('tabLab').innerHTML = '<div class="panel"><h2>This browser cannot run the simulation</h2>'
    + '<p class="sub">The page unzips its data in the browser. Open it in a current Edge, Chrome, Firefox or Safari.</p></div>';
}
</script>
</body>
</html>
"""
