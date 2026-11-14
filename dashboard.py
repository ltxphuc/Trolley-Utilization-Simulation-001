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
/* The verdict charts are drawn at 700 wide; on a wide page let them breathe a
   little but never balloon. */
#fleetChart svg,#ladder svg{max-width:820px}

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

.warn{margin-top:10px;background:var(--badBg);border:1px solid var(--bad);border-radius:4px;
  padding:9px 11px;font-size:11.5px;color:var(--ink);line-height:1.45}
.warn strong{color:var(--bad)}

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

/* ------------------------------------------------------------------ tabs */
.tabs{display:flex;gap:2px;margin-top:-1px;border-bottom:1px solid var(--rule)}
.tab{background:none;border:0;border-bottom:2px solid transparent;padding:11px 2px;
  margin-right:22px;font:600 13.5px/1 Archivo,"IBM Plex Sans",sans-serif;
  color:var(--muted);cursor:pointer;letter-spacing:-.01em}
.tab:hover{color:var(--ink)}
.tab[aria-selected=true]{color:var(--s1);border-bottom-color:var(--s1)}
.tab:focus-visible{outline:2px solid var(--s1);outline-offset:2px;border-radius:2px}

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

/* idle-time comparison table — replaces the old idleNote prose. One row per
   cut group of the SELECTED variant, against the fixed baseline (today / 21.2 m
   / 5 cutters). Delta colour follows the tiles: green = an improvement (less
   blocking / lower cutter load / fewer machines over their window). */
.idlewrap{margin-top:14px}
.idlewrap .lead{font-size:11.5px;color:var(--muted);line-height:1.45;margin-bottom:9px}
.idlewrap .lead b{color:var(--ink)}
table.idlecmp{width:100%;border-collapse:collapse;font-size:11.5px}
table.idlecmp th{text-align:right;font-family:"IBM Plex Mono",monospace;font-size:9px;
  letter-spacing:.05em;text-transform:uppercase;color:var(--muted);font-weight:400;
  padding:0 0 5px 14px;white-space:nowrap}
table.idlecmp th:first-child{text-align:left}
table.idlecmp td{text-align:right;padding:5px 0 5px 14px;border-bottom:1px solid var(--rule);
  font-variant-numeric:tabular-nums;white-space:nowrap}
table.idlecmp td:first-child{text-align:left;font-family:"IBM Plex Mono",monospace}
table.idlecmp tr.tot td{border-top:1px solid var(--rule2);border-bottom:0;font-weight:600;
  padding-top:7px}
table.idlecmp .d{font-size:9.5px;font-family:"IBM Plex Mono",monospace;margin-left:5px;color:var(--muted)}
table.idlecmp .d.up{color:var(--s2)} table.idlecmp .d.down{color:var(--bad)}
table.idlecmp td.new{color:var(--muted);font-style:italic}

/* "What these columns mean" — lighter than the Simulation tab's big
   details.panel blocks; a plain disclosure triangle, muted mono summary. */
details.idledefs{margin-top:8px}
details.idledefs>summary{cursor:pointer;list-style:none;font-family:"IBM Plex Mono",monospace;
  font-size:9px;letter-spacing:.05em;text-transform:uppercase;color:var(--muted)}
details.idledefs>summary::-webkit-details-marker{display:none}
details.idledefs>summary::before{content:"\25B8";display:inline-block;margin-right:6px;
  transition:transform .15s}
details.idledefs[open]>summary::before{transform:rotate(90deg)}
details.idledefs>summary:focus-visible{outline:2px solid var(--s1);outline-offset:3px;border-radius:3px}
details.idledefs .defs{font-size:11px;color:var(--muted);line-height:1.5;margin-top:8px}
details.idledefs .defs p{margin:0 0 7px}
details.idledefs .defs b{color:var(--ink);font-family:"IBM Plex Mono",monospace;font-size:10.5px}

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
table.tasks .dot{display:inline-block;width:9px;height:9px;border-radius:2px;margin-right:7px;
  vertical-align:-1px;border:1px solid rgba(128,128,128,.55)}
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

<div class="tabs" role="tablist" aria-label="Views">
  <button class="tab" type="button" role="tab" id="tabBtnUtil"
          aria-controls="tabUtil" aria-selected="true">Utilization</button>
  <button class="tab" type="button" role="tab" id="tabBtnSim"
          aria-controls="tabSim" aria-selected="false" tabindex="-1">Simulation</button>
  <button class="tab" type="button" role="tab" id="tabBtnLab" hidden
          aria-controls="tabLab" aria-selected="false" tabindex="-1">Rules Lab</button>
</div>

<section id="tabUtil" role="tabpanel" aria-labelledby="tabBtnUtil">
<div class="cols">

  <!-- ============================ CONTROLS ============================ -->
  <div class="rail">
    <div class="ctl">
      <h3>Start from</h3>
      <div class="presets">
        <button type="button" data-preset="today">Today</button>
        <button type="button" data-preset="proposal">The proposal</button>
      </div>
    </div>

    <div class="ctl">
      <h3>The three changes</h3>

      <div class="field">
        <label for="mo"><span><span class="chg">1</span>Same-MO sequencing</span>
          <span class="val" id="moVal">off</span></label>
        <div class="seg" role="group" aria-label="Same-MO sequencing">
          <button type="button" data-mo="today" aria-pressed="true">Off</button>
          <button type="button" data-mo="same_batch" aria-pressed="false">Same batch only</button>
          <button type="button" data-mo="cross_batch" aria-pressed="false">Cross-batch</button>
        </div>
        <div class="hint">Off is the Job Sequence as it runs today: every table gets a cutter (one
          already holding the same MO and batch if there is one, else the least loaded), then the
          least-loaded spreader takes the shortest waiting table of its cutters (SQR before QR before
          Normal). No pairing. Same batch only pairs tables of the same MO and batch back-to-back
          at one workstation, and never pairs across batches — the sequencer never
          creates adjacency a max-1-batch trolley could not use anyway. Cross-batch
          does that, then also pairs whatever is left across different batches of
          the same MO — worth it once a trolley can carry 2 batches (change 2).</div>
      </div>

      <div class="field">
        <label for="batches"><span><span class="chg">2</span>Batches per trolley</span>
          <span class="val" id="batchVal">1</span></label>
        <div class="seg" role="group" aria-label="Max batches per trolley">
          <button type="button" data-batch="1" aria-pressed="true">1</button>
          <button type="button" data-batch="2" aria-pressed="false">2</button>
          <button type="button" data-batch="3" aria-pressed="false">3</button>
        </div>
        <div class="hint">Separate compartments, same MO and colour. 1 = today's rule.</div>
        <div class="warn" id="batchWarn" hidden>
          <strong>3 is not allowed on the floor.</strong> A trolley may carry at most
          two fabric batches. Shown for comparison only.</div>
      </div>

      <div class="field">
        <label for="hold"><span><span class="chg">3</span>WIP hold</span>
          <span class="val" id="holdVal">off</span></label>
        <input type="range" id="hold" min="0" max="6" step="1" value="0"
               aria-label="WIP hold minutes">
        <div class="hint">How long a part-filled trolley waits in CCT WIP for a later
          table of the same MO, colour and film size.</div>
      </div>

      <div class="field" id="wsField">
        <label><span>It comes back to</span><span class="val" id="wsVal">any workstation</span></label>
        <div class="seg" role="group" aria-label="Which workstation the trolley returns to">
          <button type="button" data-ws="0" aria-pressed="false">Same only</button>
          <button type="button" data-ws="1" aria-pressed="true">Any</button>
        </div>
        <div class="hint">Whether a parked trolley may travel to a different
          workstation. Nobody has costed how it physically gets there.</div>
      </div>
    </div>

    <div class="ctl">
      <h3>The fleet</h3>
      <div class="field">
        <label for="cycle"><span>Trolley round trip</span>
          <span class="val" id="cycleVal">7 days</span></label>
        <input type="range" id="cycle" min="3" max="10" step="0.5" value="7"
               aria-label="Cycle days">
        <div class="hint">5 days is the lead-time allowance. ~7 is the estimate of
          what really happens — and it has never been measured.</div>
      </div>
      <div class="field">
        <label for="fleet"><span>Trolleys owned</span>
          <span class="val" id="fleetVal">1,200</span></label>
        <input type="range" id="fleet" min="600" max="2200" step="50" value="1200"
               aria-label="Fleet size">
      </div>
    </div>
  </div>

  <!-- ============================= OUTPUT ============================= -->
  <div>
    <div class="verdict" id="verdict">
      <div>
        <div class="vlabel" id="vlabel">—</div>
        <div class="vbig" id="vbig">—</div>
        <div class="vsub" id="vsub"></div>
      </div>
      <div id="fleetDial"></div>
    </div>

    <div class="tiles">
      <div class="tile"><div class="k">Compartments opened</div>
        <div class="v" id="tUtil">—</div><div class="d" id="dUtil"></div></div>
      <div class="tile"><div class="k">Compartment fill</div>
        <div class="v" id="tFill">—</div><div class="d" id="dFill"></div></div>
      <div class="tile"><div class="k">Garments loaded per trolley</div>
        <div class="v" id="tPpt">—</div><div class="d" id="dPpt"></div></div>
      <div class="tile"><div class="k">Trolleys out per day</div>
        <div class="v" id="tTpd">—</div><div class="d" id="dTpd"></div></div>
      <div class="tile"><div class="k">Cycle the fleet covers</div>
        <div class="v" id="tCycle">—</div><div class="d" id="dCycle"></div></div>
      <div class="tile"><div class="k">Avg wait in WIP</div>
        <div class="v" id="tWait">—</div><div class="d" id="dWait"></div></div>
    </div>

    <div class="panel">
      <h2>What one trolley looks like</h2>
      <p class="sub">Utilization is compartments opened &divide; <span id="capDiv">5</span>.
        This is that number drawn as the trolley it describes — filled compartments
        at the bottom, empty space travelling for free at the top.</p>
      <div class="split">
        <div id="trolley"></div>
        <div>
          <div id="trolleyText" style="font-size:14px;line-height:1.65"></div>
          <div class="legend">
            <span><i style="background:var(--s2)"></i>Loaded</span>
            <span><i style="background:var(--rule2)"></i>Empty — travelling for nothing</span>
          </div>
        </div>
      </div>
    </div>

    <div class="panel">
      <h2>Fleet needed against fleet owned</h2>
      <p class="sub">A trolley dispatched today is gone for the whole round trip, so
        the fleet has to cover that many days of dispatches at once.</p>
      <div id="fleetChart"></div>
    </div>

    <div class="panel">
      <h2>Where these settings sit</h2>
      <p class="sub">The four approval steps, each one the previous plus a single
        change. Your current settings are marked if they match one.</p>
      <div id="ladder"></div>
    </div>

    <footer id="footer"></footer>
  </div>
</div>
</section>

<!-- =========================== SIMULATION =========================== -->
<section id="tabSim" role="tabpanel" aria-labelledby="tabBtnSim" hidden>
<div class="cols">

  <div class="rail">
    <div class="ctl">
      <h3>Month</h3>
      <div class="seg" id="monthSeg" role="group" aria-label="Month" style="flex-wrap:wrap"></div>
      <div class="hint">Each month is its own file — the trace for all 8 months
        does not fit in one page. Your settings carry over when you switch.</div>
    </div>

    <div class="ctl">
      <h3>Plan date</h3>
      <div class="calmonth" id="calMonth"></div>
      <div class="calendar" id="calendar"></div>
      <div class="hint" id="dayMeta"></div>
    </div>

    <div class="ctl">
      <h3>The three changes</h3>

      <div class="field">
        <label><span><span class="chg">1</span>Same-MO sequencing</span>
          <span class="val" id="seqVal">off</span></label>
        <div class="seg" role="group" aria-label="Same-MO sequencing">
          <button type="button" data-seq="today" aria-pressed="true">Off</button>
          <button type="button" data-seq="same_batch" aria-pressed="false">Same batch only</button>
          <button type="button" data-seq="cross_batch" aria-pressed="false">Cross-batch</button>
        </div>
        <div class="hint">Off is the Job Sequence as it runs today: every table gets a cutter (one
          already holding the same MO and batch if there is one, else the least loaded), then the
          least-loaded spreader takes the shortest waiting table of its cutters. No pairing.
          Same batch only pairs same-MO, same-batch tables first and keeps
          each pair on one machine, back-to-back &mdash; watch the brackets appear.
          Cross-batch also pairs whatever is left across different batches of the
          same MO, which only pays off once a trolley can carry 2 batches
          (change 2) &mdash; at 1 batch/trolley those extra pairs can never
          actually combine.</div>
      </div>

      <div class="field">
        <label><span><span class="chg">2</span>Batches per trolley</span>
          <span class="val" id="simBatchVal">1</span></label>
        <div class="seg" role="group" aria-label="Max batches per trolley">
          <button type="button" data-simbatch="1" aria-pressed="true">1</button>
          <button type="button" data-simbatch="2" aria-pressed="false">2</button>
          <button type="button" data-simbatch="3" aria-pressed="false">3</button>
        </div>
        <div class="hint">Separate compartments, same MO and colour. 1 = today's rule.</div>
      </div>

      <div class="field">
        <label for="simHold"><span><span class="chg">3</span>WIP hold</span>
          <span class="val" id="simHoldVal">off</span></label>
        <input type="range" id="simHold" min="0" max="6" step="1" value="0"
               aria-label="WIP hold minutes">
        <div class="hint">How long a part-filled trolley waits for a later table of
          the same MO, colour and film size.</div>
      </div>

      <div class="field" id="simWsField">
        <label><span>It comes back to</span>
          <span class="val" id="simWsVal">any workstation</span></label>
        <div class="seg" role="group" aria-label="Which workstation the trolley returns to">
          <button type="button" data-simws="0" aria-pressed="false">Same only</button>
          <button type="button" data-simws="1" aria-pressed="true">Any</button>
        </div>
      </div>
    </div>

    <div class="ctl">
      <h3>Cutting machines</h3>
      <div class="field">
        <label><span>Cutters against 13 spreaders</span>
          <span class="val" id="cuttersVal"></span></label>
        <div class="seg" id="cutterSeg" role="group" aria-label="Number of cutting machines"></div>
        <div class="hint" id="cutterHint"></div>
      </div>
    </div>

    <div class="ctl">
      <h3>Idle time</h3>
      <div class="field">
        <label><span>Spreading table length</span>
          <span class="val" id="bufVal"></span></label>
        <div class="seg" id="tableSeg" role="group" aria-label="Spreading table length"></div>
        <div class="hint">Rule G6 &mdash; the spreader stops when there is not enough
          table free for the next lay. The lay in front gives its length back
          gradually as the cutter eats it, so this is the hatching on the chart.
          See <code>README.md</code> Part 7.</div>
      </div>
    </div>
  </div>

  <div>
    <div class="panel">
      <h2>1 &middot; Job Sequence &mdash; <span id="ganttDate"></span></h2>
      <p class="sub">Every table of the day placed on a spreading machine, with its
        estimated spreading time, and the cutting that follows it on the cut machine
        serving that group. Colour is the task's readiness when the day was planned.</p>
      <div class="cursorhead">
        <label for="cursor">Spreading and cutting finished by</label>
        <span class="num" id="cursorVal"></span>
      </div>
      <div class="scrollx">
        <div class="ganttinner">
          <div class="cursorrow">
            <input type="range" id="cursor" min="0" max="1" step="1" value="0"
                   aria-label="Time cursor along the chart's own timeline">
          </div>
          <div id="gantt"></div>
        </div>
      </div>
      <div class="swatches" id="statusLegend"></div>
      <div class="idlewrap" id="idleNote"></div>
      <div class="hint" id="slipNote"></div>
    </div>

    <details class="panel" id="taskPanel">
      <summary>
        <h2>Tasks prepared for <span id="listDate"></span></h2>
        <span class="sum" id="taskSummary"></span>
      </summary>
      <p class="sub">The day as the planner receives it. Click a column to sort.</p>
      <div class="scrollx"><table class="tasks" id="taskTable"></table></div>
      <div class="hint" id="taskNote"></div>
    </details>

    <details class="panel" id="loadPanel">
      <summary>
        <h2>2 &middot; Panel Loading &mdash; onto trolleys at the end of cutting</h2>
        <span class="sum" id="loadSummary"></span>
      </summary>
      <p class="sub">The same day's cut panels, loaded compartment by compartment.
        A compartment holds one size of one batch, up to 150 pieces (H1); a trolley
        holds five compartments of one film width only (H3, H4).</p>
      <div id="parity" class="parity"></div>
      <div class="scrollx"><table class="tasks" id="trolleyTable"></table></div>
      <h3 class="sechead">Every trolley of the day</h3>
      <div id="trolleys"></div>
    </details>
  </div>
</div>
</section>

<!-- ============================== RULES LAB ============================== -->
<section id="tabLab" role="tabpanel" aria-labelledby="tabBtnLab" hidden>
<div class="cols">

  <div class="rail">
    <div class="ctl">
      <h3>The floor</h3>
      <div class="hint">There is no cold start. Work a machine did not finish carries into the next
        shift, and each plan date is planned on its morning around what every spreader still has left. Machines run
        at the G2 standard pace. Cutter changeover and moving time are the only lost time added on top
        <span class="est">ESTIMATES</span>. With every add-on off, this tab shows the same numbers as the
        Utilization tab and the same arrangement as the Simulation tab.</div>
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
      <div class="hint" style="margin-top:12px">vs today = S0, the real Job Sequence, on the same floor as your selection.
        Round trip and fleet follow the Utilization tab (the 7-day trip is an ESTIMATE).</div>
      <div class="labstatus" id="labStatus"></div>
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
        <p><b>Same numbers as the other tabs.</b> With Published model and every add-on off, the tiles equal the
          Utilization tab for the same three changes, and the Job Sequence equals the Simulation tab's. The badge
          above turns green when that holds for the current selection.</p>
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

const state = {
  mo: 'today', batches: 1, holdIdx: 0, anyWs: 1,
  cycle: A.cycle_days_estimated, fleet: A.fleet_size,
};

const PRESETS = {
  today:    {mo:'today', batches:1, holdIdx:0, anyWs:1},
  proposal: {mo:'cross_batch', batches:2, holdIdx:HOLDS.indexOf(A.wip_hold_minutes), anyWs:A.wip_hold_any_workstation?1:0},
};

const $ = id => document.getElementById(id);
const fmt = (n,d=0) => n.toLocaleString('en-US',{minimumFractionDigits:d,maximumFractionDigits:d});

function key(mo, batches, hold, anyWs){
  if (hold === 0) anyWs = 1;
  return `${mo}|${batches}|${hold}|${anyWs}`;
}
function lookup(s){
  return DATA.sweep[key(s.mo, s.batches, HOLDS[s.holdIdx], s.anyWs)];
}
const BASELINE = DATA.sweep[key('today',1,0,1)];

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

function fleetChart(tpd, baseTpd, cycle, fleet){
  const mine = tpd*cycle, base = baseTpd*cycle;
  const col = mine > fleet ? 'bad' : 's2';
  // When the sliders sit on today's rules the two bars are the same number —
  // draw one row rather than two identical ones.
  const rows = Math.abs(mine - base) < 1
    ? [['Today — these settings', mine, col]]
    : [['Today', base, 's1'], ['These settings', mine, col]];
  const W=700, L=150, R=68, rowH=52, H=rows.length*rowH+30;
  const vmax = Math.max(fleet, ...rows.map(r=>r[1]))*1.1;
  const x = v => L + (W-L-R)*v/vmax;
  let s = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Trolleys required versus fleet owned">`;
  rows.forEach((row,i)=>{
    const y = 14+i*rowH;
    s += `<text x="0" y="${y+18}" font-size="12.5" font-weight="500" fill="var(--ink)">${row[0]}</text>`;
    s += `<text x="0" y="${y+33}" font-size="10.5" class="num" fill="var(--muted)">${fmt(row[1]/cycle,0)}/day &#215; ${cycle}d</text>`;
    s += `<rect x="${L}" y="${y}" width="${W-L-R}" height="24" rx="3" fill="var(--panel2)" stroke="var(--rule2)"/>`;
    s += `<rect class="barfill" x="${L}" y="${y}" width="${Math.max(0,x(row[1])-L)}" height="24" rx="3" fill="var(--${row[2]})"/>`;
    s += `<text x="${x(row[1])+8}" y="${y+17}" class="num" font-size="13" font-weight="600" fill="var(--ink)">${fmt(row[1])}</text>`;
  });
  s += `<line x1="${x(fleet)}" x2="${x(fleet)}" y1="4" y2="${H-22}" stroke="var(--ink)"
         stroke-width="1.5" stroke-dasharray="4 3" opacity=".5"/>`;
  s += `<text x="${x(fleet)}" y="${H-8}" text-anchor="middle" class="num" font-size="10.5"
         fill="var(--ink)" opacity=".75">owned: ${fmt(fleet)}</text>`;
  return s+'</svg>';
}
const over = (a,b)=>a>b;

function ladder(cur){
  const steps = Object.values(DATA.headline);
  const W=700, BX=214, VW=68, H=steps.length*46+8;
  const bw = W - BX - VW;
  let s = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Utilization by approval step">`;
  steps.forEach((st,i)=>{
    const y = i*46+6;
    const isCur = st.settings.sequencing_mode===cur.mo
      && st.settings.max_batches===cur.batches
      && st.settings.wip_hold_minutes===HOLDS[cur.holdIdx]
      && (HOLDS[cur.holdIdx]===0 || st.settings.hold_any_workstation===!!cur.anyWs);
    const col = isCur ? 'var(--s3)' : 'var(--s1)';
    s += `<text x="0" y="${y+18}" font-size="12.5" font-weight="${isCur?600:400}"
           fill="var(--ink)">${st.name.replace(/^S\d+\s+/,'')}</text>`;
    // "you are here" lives in the label column, where it can never be clipped
    s += `<text x="0" y="${y+32}" font-size="10" class="num"
           fill="${isCur?'var(--s3)':'var(--muted)'}" font-weight="${isCur?600:400}">`
       + `${st.name.split(' ')[0]}${isCur?' &#183; you are here':''}</text>`;
    s += `<rect x="${BX}" y="${y+2}" width="${bw}" height="22" rx="3"
           fill="var(--panel2)" stroke="var(--rule2)"/>`;
    s += `<rect x="${BX}" y="${y+2}" width="${bw*st.util/100}" height="22" rx="3" fill="${col}"/>`;
    // direct label on every bar — required relief for the amber's contrast
    s += `<text x="${BX+bw+8}" y="${y+18}" class="num" font-size="12.5"
           font-weight="600" fill="var(--ink)">${st.util.toFixed(1)}%</text>`;
  });
  return s+'</svg>';
}

/* ------------------------------------------------------------------ render */
function render(){
  const r = lookup(state);
  const cycle = state.cycle, fleet = state.fleet;
  const required = r.trolleys_per_day * cycle;
  const spare = fleet - required;
  const short = spare < 0;

  // verdict
  const v = $('verdict');
  v.className = 'verdict ' + (short ? 'short' : 'ok');
  $('vlabel').textContent = short ? 'The fleet does not cover this' : 'The fleet covers this';
  $('vbig').textContent = fmt(required) + ' trolleys needed';
  $('vsub').innerHTML = short
    ? `At <b>${fmt(r.trolleys_per_day,0)} trolleys a day</b> and a <b>${cycle}-day</b> round trip,
       Central Cutting needs ${fmt(required)} trolleys in circulation. You own
       ${fmt(fleet)} — <b>${fmt(-spare)} short</b>.`
    : `At <b>${fmt(r.trolleys_per_day,0)} trolleys a day</b> and a <b>${cycle}-day</b> round trip,
       ${fmt(required)} trolleys stay in circulation — <b>${fmt(spare)} spare</b> inside the
       ${fmt(fleet)} you own.`;
  $('fleetDial').innerHTML = fleetDial(required, fleet);

  // tiles
  const d = (now, was, better, unit='', dec=1) => {
    const diff = now - was;
    if (Math.abs(diff) < 0.05) return ['vs today: no change',''];
    const good = better === 'up' ? diff > 0 : diff < 0;
    return [`vs today: ${diff>0?'+':''}${fmt(diff,dec)}${unit}`, good?'up':'down'];
  };
  const set = (tid, did, val, tuple) => {
    $(tid).innerHTML = val;
    $(did).textContent = tuple[0];
    $(did).className = 'd ' + tuple[1];
  };
  set('tUtil','dUtil', r.utilization_pct.toFixed(1)+'<em>%</em>',
      d(r.utilization_pct, BASELINE.utilization_pct, 'up', ' pt'));
  set('tFill','dFill', r.compartment_fill_pct.toFixed(1)+'<em>%</em>',
      d(r.compartment_fill_pct, BASELINE.compartment_fill_pct, 'up', ' pt'));
  set('tPpt','dPpt', fmt(r.pieces_per_trolley,0),
      d(r.pieces_per_trolley, BASELINE.pieces_per_trolley, 'up', '', 0));
  set('tTpd','dTpd', fmt(r.trolleys_per_day,0),
      d(r.trolleys_per_day, BASELINE.trolleys_per_day, 'down', '', 0));
  const cyc = fleet / r.trolleys_per_day, baseCyc = fleet / BASELINE.trolleys_per_day;
  set('tCycle','dCycle', cyc.toFixed(1)+'<em> days</em>',
      d(cyc, baseCyc, 'up', ' d'));
  set('tWait','dWait',
      r.avg_wait_hours > 0 ? r.avg_wait_hours.toFixed(1)+'<em> h</em>' : '<em>none</em>',
      ['trolleys are not held', '']);
  if (r.avg_wait_hours > 0){
    $('dWait').textContent = `${fmt(HOLDS[state.holdIdx])} min allowed`;
  }

  // trolley
  $('trolley').innerHTML = trolleySvg(r.utilization_pct);
  const usedComp = r.utilization_pct/100*A.trolley_compartments;
  const ceiling = A.trolley_compartments*A.compartment_cap;
  $('trolleyText').innerHTML =
    `<b>${usedComp.toFixed(2)} of ${A.trolley_compartments} compartments</b> get opened, on
     average, on every trolley that leaves Central Cutting &rarr; opened, they could hold
     <b>${fmt(r.garments_per_trolley_capacity,0)} garments</b> (${A.compartment_cap} each,
     rule H1) &rarr; they actually carry <b>${fmt(r.pieces_per_trolley,0)} garments</b>,
     because a compartment holds one size of one batch and the last compartment of each
     size takes the remainder &rarr; that is <b>${r.compartment_fill_pct.toFixed(1)}%</b>
     fill. The remaining <b>${(A.trolley_compartments-usedComp).toFixed(2)} compartments</b>
     travel the full ${cycle}-day round trip empty.<br><br>
     <b>${fmt(ceiling)}</b> is what a trolley could hold if every compartment opened full;
     <b>${fmt(r.garments_per_trolley_capacity,0)}</b> is what the compartments we opened
     could hold; <b>${fmt(r.pieces_per_trolley,0)}</b> is what is on board.`;

  $('capDiv').textContent = A.trolley_compartments;
  $('fleetChart').innerHTML = fleetChart(r.trolleys_per_day, BASELINE.trolleys_per_day, cycle, fleet);
  $('ladder').innerHTML = ladder(state);

  // control labels
  $('moVal').textContent = state.mo === 'today' ? 'off'
    : state.mo === 'same_batch' ? 'same batch only' : 'cross-batch';
  $('batchVal').textContent = state.batches;
  $('holdVal').textContent = HOLDS[state.holdIdx] === 0 ? 'off' : HOLDS[state.holdIdx] + ' min';
  $('wsVal').textContent = state.anyWs ? 'any workstation' : 'same only';
  $('cycleVal').textContent = cycle + ' days';
  $('fleetVal').textContent = fmt(fleet);
  $('batchWarn').hidden = state.batches !== 3;
  $('wsField').style.opacity = HOLDS[state.holdIdx] === 0 ? .4 : 1;
  $('wsField').querySelectorAll('button').forEach(b => b.disabled = HOLDS[state.holdIdx] === 0);

  document.querySelectorAll('[data-mo]').forEach(b =>
    b.setAttribute('aria-pressed', String(b.dataset.mo === state.mo)));
  document.querySelectorAll('[data-batch]').forEach(b =>
    b.setAttribute('aria-pressed', String(+b.dataset.batch === state.batches)));
  document.querySelectorAll('[data-ws]').forEach(b =>
    b.setAttribute('aria-pressed', String(+b.dataset.ws === state.anyWs)));

  $('footer').innerHTML =
    `${DATA.planDates} plan dates &middot; ${fmt(DATA.tables)} tables &middot;
     ${fmt(DATA.tables/DATA.planDates,0)} a day. Trolley utilization is compartments
     opened &divide; ${A.trolley_compartments} (rule H6), pooled across all days —
     it counts how many of the ${A.trolley_compartments} slots got opened, not how
     full each one is. Compartment fill is pieces on board &divide; what the opened
     compartments could hold (${A.compartment_cap} each, rule H1) — a compartment
     holds one size of one batch, so the last compartment of a size carries only
     the remainder, which is why fill runs below 100% even on a full trolley.
     A trolley may carry at most ${A.max_batches_per_trolley} fabric batches, and no
     more than ${A.trolley_bays} may be parked and waiting at once (rule H7).
     The ${A.cycle_days_estimated}-day round trip is an <b>estimate, not a measurement</b> —
     it is the number this whole page is most sensitive to.<br><br>
     Every value here comes from <code>assumptions.py</code>. Change one, re-run
     <code>python run.py</code>, and this page updates.`;
}

/* ------------------------------------------------------------------ wiring */
$('hold').addEventListener('input', e => { state.holdIdx = +e.target.value; render(); });
$('cycle').addEventListener('input', e => { state.cycle = +e.target.value; render(); });
$('fleet').addEventListener('input', e => { state.fleet = +e.target.value; render(); });

document.querySelectorAll('[data-mo]').forEach(b =>
  b.addEventListener('click', () => { state.mo = b.dataset.mo; render(); }));
document.querySelectorAll('[data-batch]').forEach(b =>
  b.addEventListener('click', () => { state.batches = +b.dataset.batch; render(); }));
document.querySelectorAll('[data-ws]').forEach(b =>
  b.addEventListener('click', () => { state.anyWs = +b.dataset.ws; render(); }));

document.querySelectorAll('[data-preset]').forEach(b =>
  b.addEventListener('click', () => {
    Object.assign(state, PRESETS[b.dataset.preset]);
    $('hold').value = state.holdIdx;
    render();
  }));

$('themeBtn').addEventListener('click', () => {
  const dark = document.documentElement.getAttribute('data-theme') === 'dark'
    || (!document.documentElement.getAttribute('data-theme')
        && matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.setAttribute('data-theme', dark ? 'light' : 'dark');
  $('themeBtn').textContent = dark ? 'Dark mode' : 'Light mode';
});

render();

/* ==================================================================== tabs */
const TABS = [['tabBtnUtil','tabUtil'], ['tabBtnSim','tabSim']];
let simDrawn = false;

function showTab(which){
  TABS.forEach(([btn, panel]) => {
    const on = btn === which;
    $(btn).setAttribute('aria-selected', String(on));
    $(btn).tabIndex = on ? 0 : -1;
    $(panel).hidden = !on;
  });
  if (which === 'tabBtnSim'){
    // the chart is sized to the panel, so it must be (re)drawn while visible
    if (!simDrawn){ simDrawn = true; SIM.init(); } else SIM.redraw();
  }
  if (which === 'tabBtnLab' && window.__LAB) window.__LAB.show();
  try { localStorage.setItem('cct.tab', which); } catch (e) {}
}
TABS.forEach(([btn]) => $(btn).addEventListener('click', () => showTab(btn)));
$('tabBtnUtil').parentElement.addEventListener('keydown', e => {
  if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
  const i = TABS.findIndex(([b]) => $(b).getAttribute('aria-selected') === 'true');
  const next = TABS[(i + (e.key === 'ArrowRight' ? 1 : TABS.length - 1)) % TABS.length][0];
  showTab(next); $(next).focus(); e.preventDefault();
});

/* ============================================================= SIMULATION
   One plan date, drawn twice: the Job Sequence that produced it, and the
   trolleys it filled. Stage 4 is recomputed here rather than looked up,
   because the Net_Rate scheme has to be switchable — so it must mirror
   model.py exactly. The parity badge is what proves it still does.
   ====================================================================== */
const SIM = (() => {
const T = DATA.trace, SCOL = DATA.statusColors;
const CAP = A.compartment_cap, SLOTS = A.trolley_compartments;
const MAXB = A.max_batches_per_trolley, BAYS = A.trolley_bays;
const MAXCOMB = A.max_trolleys_per_combine;

// In the order the floor numbers them.
const STATUSES = [
  ['normal',         'Normal condition'],
  ['cut_queue',      'Normal · cut queue'],
  ['stretch',        'Normal · stretch spreading'],
  ['no_pattern',     'No pattern, enough fabric'],
  ['no_fabric_time', 'Have pattern, not enough fabric'],
  ['neither',        'No pattern, not enough fabric'],
  ['no_fabric',      'No fabric'],
  ['completed',      'Completed'],
];
const LABEL = Object.fromEntries(STATUSES);

// DATA.baselineVariant is '21.2/5'. The trace is keyed by BOTH table length
// and cutter count, so sim carries both; the sidebar's "Cutting machines"
// control (#cutterSeg) drives sim.cutters, the "Idle time" control drives
// sim.table.
const [BASELINE_TABLE, BASELINE_CUTTERS] = DATA.baselineVariant.split('/');

const sim = {
  date: T.dates[0], mode: 'today', table: BASELINE_TABLE, cutters: +BASELINE_CUTTERS,
  batches: 1, holdIdx: 0, anyWs: 1, cursor: 0, showAll: false,
  sortBy: 'seq', sortDir: 1,
};

function variantKeyFor(table, cutters){ return `${table}/${cutters}`; }
// A (table length, cutter count) pair only means something if run.py actually
// precomputed it — DATA.simVariants is the authoritative list. At 24 m / 27 m
// only 5 cutters ships; at 21.2 m all four counts do, but 6 and 8 are
// aggregate-only (`full` false — no per-task timeline, the Gantt stays at the
// baseline sequence, exactly as 24 m / 27 m already behave for table length).
function variantMeta(table, cutters){
  return DATA.simVariants.find(v => v.key === variantKeyFor(table, cutters)) || null;
}
function variantExists(table, cutters){ return !!variantMeta(table, cutters); }
function variantFull(table, cutters){ const v = variantMeta(table, cutters); return !!(v && v.full); }

/* ------------------------------------------------------------- the tasks */
// Field 14 used to be batch_first_offset_minutes (dropped — daytrace.py never
// shipped it to anything that read it); is_batch_last and spread_done_minutes
// each moved down one index. See daytrace.py's TASK_FIELDS.
function tasksFor(date){
  return T.days[date].tasks.map((r, i) => ({
    i, tableNo: r[0], mo: r[1], style: r[2], color: r[3], batch: r[4], lot: r[5],
    layers: r[6], markerLen: r[7], spreadMin: r[8], cutMin: r[9],
    pieces: r[10], needsTrolleys: !!r[11],
    hasPattern: !!r[12], hasFabric: !!r[13], batchLast: !!r[14],
    // Pull Date is recorded from midnight; everything else on this page is
    // measured from 07:15, so shift it onto the chart's own clock.
    doneAt: r[15] === null ? null : r[15] - A.shift_start_minute,
  }));
}

/* How far the floor ran behind the plan, over EVERY plan date — computed by
   run.py/build.js once, over all 199 dates, and shipped as DATA.slip. This
   page used to count it itself from T.dates, which was every date the trace
   carried; now that each file only carries one month's trace, counting
   locally would silently understate "across all N dates" in the prose below.
   See run.py's compute_slip(). */
const SLIP = DATA.slip;

/* Fabric relaxing is a hard precondition, not a variable: a table is not
   released to the floor until its fabric has had its 24 hours. So every planned
   table is relaxed, and the two "not enough fabric" statuses stay in the legend
   reading zero. Same for the pattern — the marker ratio is in within 1.5 h of
   the plan being uploaded, so it is never the constraint either.

   Priority matters: finished work is grey whatever else was true of it, and
   "stretch" only qualifies a task that is otherwise normal.

   Completed compares against the SIMULATED cut_end (t._ce, set in draw()'s
   decoration pass from run.time.ce), not the actual Pull Date. The bars on
   the chart are drawn from the simulated schedule, so greying them against a
   different, real-world clock meant the cursor could drag clean across a bar
   and never grey it out — that was the bug. The actual Pull Date (doneAt)
   stays in the data for slipNote below the chart, which reports the
   plan-vs-reality slip as dataset-level prose, not as a chart colour. */
function statusOf(t, cursor){
  if (t._ce !== undefined && t._ce !== null && t._ce <= cursor) return 'completed';
  if (!t.hasFabric)  return 'no_fabric';
  if (!t.hasPattern) return 'no_pattern';
  return t.batchLast ? 'stretch' : 'normal';
}

/* ------------------------------------------- compartments and trolleys
   Ports of compartments_for / combined_compartments / can_combine /
   _loading_events / load_trolleys in model.py. Maps, not objects, so film
   widths keep Python's insertion order rather than JS's numeric-key order. */
const FILM = A.film_size_by_garment_size;

function compartmentsFor(pieces, film){
  film = film || FILM;
  const out = new Map();
  for (const size of Object.keys(pieces)){
    const qty = pieces[size], f = film[size];
    if (!out.has(f)) out.set(f, []);
    const list = out.get(f);
    for (let k = Math.floor(qty / CAP); k > 0; k--) list.push(CAP);
    const rem = qty % CAP;
    if (rem) list.push(rem);
  }
  return out;
}

function combinedCompartments(a, b, film){
  if (a.batch === b.batch){                       // merge — Panel Loading rule 2
    const merged = {};
    for (const s of Object.keys(a.pieces)) merged[s] = a.pieces[s];
    for (const s of Object.keys(b.pieces)) merged[s] = (merged[s] || 0) + b.pieces[s];
    return compartmentsFor(merged, film);
  }
  const out = new Map();                          // side by side — H1/H4
  for (const t of [a, b])
    for (const [f, list] of compartmentsFor(t.pieces, film))
      out.set(f, (out.get(f) || []).concat(list));
  return out;
}

function trolleysFor(comps){
  let n = 0;
  for (const list of comps.values()) if (list.length) n += Math.ceil(list.length / SLOTS);
  return n;
}

function canCombine(a, b, crossBatch, film){
  if (!a.needsTrolleys || !b.needsTrolleys) return null;
  if (a.mo !== b.mo || a.color !== b.color) return null;
  if (a.batch !== b.batch && !crossBatch)   return null;
  const comps = combinedCompartments(a, b, film);
  if (trolleysFor(comps) > MAXCOMB)         return null;   // H8
  return comps;
}

function loadingEvents(order, time, tasks, crossBatch, film){
  const events = [], pairs = [];
  for (const machine of Object.keys(order)){
    const queue = order[machine];
    let i = 0;
    while (i < queue.length){
      const a = tasks[queue[i]];
      if (!a.needsTrolleys){ i += 1; continue; }
      const b = i + 1 < queue.length ? tasks[queue[i + 1]] : null;
      const paired = b ? canCombine(a, b, crossBatch, film) : null;
      if (paired){
        events.push({when: Math.max(time.ce[a.i], time.ce[b.i]), task: a, comps: paired,
                     batches: new Set([a.batch, b.batch]), machine, members: [a, b]});
        pairs.push([a.i, b.i]);
        i += 2;
      } else {
        events.push({when: time.ce[a.i], task: a, comps: compartmentsFor(a.pieces, film),
                     batches: new Set([a.batch]), machine, members: [a]});
        i += 1;
      }
    }
  }
  events.sort((x, y) => x.when - y.when);          // stable, as Python's is
  return {events, pairs};
}

function loadTrolleys(events, hold, anyWs){
  const parked = new Map();                        // key -> [trolley, ...]
  const trolleys = [];
  let compsUsed = 0, pieces = 0, combines = 0, blockedBySpace = 0;
  const waits = [];
  const parkedNow = () => { let n = 0; for (const v of parked.values()) n += v.length; return n; };

  for (const ev of events){
    if (ev.batches.size > 1) combines++;

    for (const [k, arr] of parked){                // send away what has waited
      const keep = [];
      for (const tr of arr){
        if (ev.when - tr.at <= hold) keep.push(tr);
        else { waits.push(ev.when - tr.at); tr.left = ev.when; }
      }
      parked.set(k, keep);
    }

    for (const [f, list] of ev.comps){
      if (!list.length) continue;
      compsUsed += list.length;
      for (const q of list) pieces += q;

      // MO + colour + film size (H4). Batch is deliberately NOT in the key -
      // that is the whole point of change 2.
      const key = [ev.task.mo, ev.task.color, f].join(' ')
                + (anyWs ? '' : ' ' + ev.machine);
      let need = list.length;
      const waiting = list.slice();                // for drawing only
      const arr = parked.get(key) || [];

      for (const tr of arr){                       // (a) top up what is parked
        if (need === 0) break;
        const would = new Set([...tr.batches, ...ev.batches]);
        if (would.size > MAXB) continue;           // would be a third batch
        const take = Math.min(tr.free, need);
        if (take === 0) continue;
        tr.free -= take; tr.batches = would; need -= take;
        for (const q of waiting.splice(0, take))
          tr.comps.push({qty: q, batch: ev.task.batch, table: ev.task.tableNo,
                         recalled: true});
      }
      parked.set(key, arr.filter(tr => tr.free > 0));

      while (need > 0){                            // (b) open fresh trolleys
        const take = Math.min(SLOTS, need);
        need -= take;
        const tr = {film: f, free: SLOTS - take, at: ev.when, comps: [],
                    batches: new Set(ev.batches), mo: ev.task.mo, color: ev.task.color,
                    parked: false, left: null};
        for (const q of waiting.splice(0, take))
          tr.comps.push({qty: q, batch: ev.task.batch, table: ev.task.tableNo,
                         recalled: false});
        trolleys.push(tr);
        if (tr.free > 0 && hold > 0){
          if (parkedNow() < BAYS){
            tr.parked = true;
            if (!parked.has(key)) parked.set(key, []);
            parked.get(key).push(tr);
          } else blockedBySpace++;
        }
      }
    }
  }

  const util = trolleys.length ? 100 * compsUsed / (SLOTS * trolleys.length) : 0;
  return {trolleys, compartments: compsUsed, pieces, combines, blockedBySpace,
          util, avgWaitHours: waits.length ? waits.reduce((a, b) => a + b, 0) / waits.length / 60 : 0};
}

/* ---------------------------------------------------------- run one day
   `order` moved inside the per-variant dict in this phase — a different
   cutter count re-partitions the cut groups, which changes the sequence, so
   the queue can no longer be shared across variants the way it could when
   table length was the only axis (see daytrace.py's build_trace comment).

   Two of the six shipped variants (24 m and 27 m, both at 5 cutters) are
   aggregate-only: they carry 'blocked'/'groups'/'over' but no 'time'/'order'/
   'expected' — the full timeline for every (length, cutter) combination does
   not fit the page's size budget. Selecting one of those keeps drawing the
   baseline (21.2 m) sequence — the Gantt does not redraw for them — while
   'blocked'/'groups' still reflect the TRUE selected variant, so the idle-time
   numbers stay honest even though the chart is a stand-in. `run.full` tells
   the caller which situation it is in. */
function simulate(){
  const seq = T.days[sim.date].seq[sim.mode];
  // clamps in the control handlers and applyHash keep sim.table/sim.cutters on
  // a real variant, but fall back to the baseline rather than throw if a stale
  // hash ever slips a nonexistent pairing through.
  const trueBuf = seq.table[variantKeyFor(sim.table, sim.cutters)]
                || seq.table[DATA.baselineVariant];
  const full = !!(trueBuf && trueBuf.time);
  const buf = full ? trueBuf : seq.table[DATA.baselineVariant];
  const tasks = tasksFor(sim.date);
  const {events, pairs} = loadingEvents(buf.order, buf.time, tasks,
                                        sim.batches >= 2, FILM);
  const result = loadTrolleys(events, HOLDS[sim.holdIdx], sim.anyWs);
  // buf.cutters is the cutter-name list of the sequence actually drawn: the
  // selected variant's when it ships in full, the baseline's (5) when the
  // selection is aggregate-only. ganttRows()/gantt() key every row off this,
  // NOT sim.cutters — otherwise an aggregate selection at 6/8 cutters would
  // draw 6/8 cut rows over a 5-cutter timeline (trap 13's failure mode).
  return {tasks, seq, order: buf.order, time: buf.time, cutters: buf.cutters,
          full, expected: full ? trueBuf.expected : null,
          blocked: trueBuf.blocked, groups: trueBuf.groups, over: trueBuf.over,
          events, pairs, ...result};
}

/* ------------------------------------------------------------- the Gantt */
// Rows follow sim.cutters — DATA.cutGroupsByCutterCount is keyed by the
// cutter count (JSON turns the Python int keys into strings, but plain
// object property access coerces sim.cutters the same way), so the row list
// re-partitions itself the moment the cutter-count control changes it.
function ganttRows(cutterCount){
  const rows = [], groups = DATA.cutGroupsByCutterCount[cutterCount];
  for (const cut of Object.keys(groups)){
    for (const m of groups[cut])
      rows.push({key: 'S' + m, label: 'SPD ' + m, kind: 'spd', name: m});
    rows.push({key: 'C' + cut, label: 'CUT ' + cut.replace('24', ''), kind: 'cut', name: cut});
    rows.push({kind: 'gap'});
  }
  rows.pop();
  return rows;
}

/* Minutes on the timeline are measured from the start of the day shift, so
   t = 0 is 07:15 and the axis reads in real clock time. The Pull Date arrives
   measured from midnight, so tasksFor() shifts it onto this clock. */
const SHIFT_START = A.shift_start_minute;

function hhmm(minutesFromMidnight){
  // Round to the whole minute BEFORE splitting into hours/minutes — rounding
  // each half separately lets a value like 1419.7 print '23:60' (rounds the
  // minute up without carrying into the hour). Mirrors idle_variants.py's
  // own clock().
  const whole = Math.round(minutesFromMidnight);
  const m = ((whole % 1440) + 1440) % 1440;
  return String(Math.floor(m / 60)).padStart(2, '0') + ':'
       + String(m % 60).padStart(2, '0');
}
// t is minutes from 07:15
const clock = t => {
  const abs = t + SHIFT_START, d = Math.floor(abs / 1440);
  return (d > 0 ? `+${d}d ` : '') + hhmm(abs);
};
// Staffed minutes between two instants — so a gap on the chart can be split
// into "starved" (G6) and "nobody here" (break, or shift over).
function workingBetween(spans, a, b){
  let n = 0;
  for (const [s, e] of spans || []) n += Math.max(0, Math.min(b, e) - Math.max(a, s));
  return n;
}

// The eight status colours are a mix of pale and dark, so pick the label
// colour from the swatch's luminance rather than assuming.
function inkOn(hex){
  const n = parseInt(hex.slice(1), 16);
  const lum = (0.299 * (n >> 16) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255;
  return lum > 0.6 ? '#101720' : '#FFFFFF';
}

/* How wide to draw. The panel decides; 1120 is the floor, below which the
   chart scrolls inside its container rather than becoming unreadable. */
const GANTT_MIN_WIDTH = 1120;
function ganttWidth(){
  const box = $('gantt').parentElement;      // .ganttinner
  return Math.max(GANTT_MIN_WIDTH, Math.round(box.clientWidth) || GANTT_MIN_WIDTH);
}

/* Where the chart stops. Floors at DATA.shiftEnd (1,305 min — 05:00, the end
   of the full two-shift window: model.py's SHIFT_END, the later of the day
   and night machines' own last staffed instant), not just the day shift's own
   end — the axis used to floor at DATA.dayShiftEnd (765 min, 20:00), which
   put the whole second shift for 24-01/02/03 and 24MC1 off the right edge of
   the chart. Genuine overrun past 05:00 still extends it further. */
function ganttEnd(run){
  let last = 0;
  for (const v of run.time.ce) if (v !== null) last = Math.max(last, v);
  return Math.max(DATA.shiftEnd, Math.ceil(last / 60) * 60);
}

function staffEnd(spans){
  return spans && spans.length ? spans[spans.length - 1][1] : Infinity;
}

function gantt(run){
  const drawnCutters = run.cutters.length;
  const rows = ganttRows(drawnCutters), time = run.time, order = run.order;
  const cutterShift = DATA.cutterShiftByCutterCount[drawnCutters];
  // Drawn at the panel's own width — no scaling, so the rows keep their height
  // and the labels their size however wide the window is.
  const W = ganttWidth(), L = 96, R = 14, H_ROW = 23, H_GAP = 9;
  const xmax = ganttEnd(run);
  const x = v => L + (W - L - R) * v / xmax;

  // The shift ribbon sits between the hour labels and the machine rows.
  const RIBBON_Y = 20, RIBBON_H = 8, RIBBON_GAP = 3;
  const RIBBON_BOTTOM = RIBBON_Y + 2 * RIBBON_H + RIBBON_GAP;

  let y = RIBBON_BOTTOM + 10, top = {};
  for (const r of rows){ if (r.kind !== 'gap') top[r.key] = y; y += r.kind === 'gap' ? H_GAP : H_ROW; }
  const H = y + 8;

  const paired = new Map();
  run.pairs.forEach(([a, b]) => { paired.set(a, b); });

  let s = `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img"
    aria-label="Job sequence for ${sim.date}: ${run.tasks.length} tables across 13 spreading machines">
    <defs><pattern id="blk" width="5" height="5" patternUnits="userSpaceOnUse"
      patternTransform="rotate(45)">
      <line x1="0" y1="0" x2="0" y2="5" stroke="var(--bad)" stroke-width="1.6" opacity=".45"/>
    </pattern>
    <pattern id="ovl" width="5" height="5" patternUnits="userSpaceOnUse"
      patternTransform="rotate(45)">
      <line x1="0" y1="0" x2="0" y2="5" stroke="var(--muted)" stroke-width="1.4" opacity=".55"/>
    </pattern></defs>`;

  // hour grid, in real clock time from 07:15
  for (let t = (60 - SHIFT_START % 60) % 60; t <= xmax; t += 60){
    const onHour = (t + SHIFT_START) % 120 === 0;
    s += `<line x1="${x(t)}" x2="${x(t)}" y1="${RIBBON_BOTTOM + 2}" y2="${H - 6}" stroke="var(--rule)"
           stroke-width="1"/>`;
    if (onHour)
      s += `<text x="${x(t)}" y="14" text-anchor="middle" class="num" font-size="9.5"
             fill="var(--muted)">${clock(t)}</text>`;
  }

  // The day/night shift ribbon — D4. The night-capable machines
  // (24-01/02/03, 24MC1) are staffed continuously from the day shift's own
  // start (model.py's working_intervals(): "night machines work the day
  // too"), so the part of the night band before dayShiftEnd adds no extra
  // capacity over the day band — it is the SAME machines, already counted.
  // Only what runs past dayShiftEnd, out to shiftEnd (05:00), is additional.
  {
    const dayEnd = Math.min(DATA.dayShiftEnd, xmax), nightEnd = Math.min(DATA.shiftEnd, xmax);
    const nightY = RIBBON_Y + RIBBON_H + RIBBON_GAP;
    s += `<rect x="${x(0)}" y="${RIBBON_Y}" width="${Math.max(0, x(dayEnd) - x(0))}" height="${RIBBON_H}"
           rx="1.5" fill="var(--s1)" opacity=".28"><title>DAY ${clock(0)}–${clock(DATA.dayShiftEnd)} · 13 spreading machines · ${drawnCutters} cutting machines</title></rect>`;
    s += `<text x="${x(0) + 3}" y="${RIBBON_Y + RIBBON_H - 1.5}" font-size="7" class="num"
           fill="var(--s1)" pointer-events="none">DAY</text>`;
    s += `<rect x="${x(0)}" y="${nightY}" width="${Math.max(0, x(dayEnd) - x(0))}" height="${RIBBON_H}"
           rx="1.5" fill="url(#ovl)"><title>Overlaps the day shift — same machines running on, adds no extra capacity here</title></rect>`;
    if (nightEnd > dayEnd)
      s += `<rect x="${x(dayEnd)}" y="${nightY}" width="${Math.max(0, x(nightEnd) - x(dayEnd))}" height="${RIBBON_H}"
             rx="1.5" fill="var(--s3)" opacity=".38"><title>NIGHT ${clock(DATA.dayShiftEnd)}–${clock(DATA.shiftEnd)} · ${DATA.nightSpreaders.join('/')} · ${DATA.nightShiftCutters.join('/')}</title></rect>`;
    s += `<text x="${x(0) + 3}" y="${nightY + RIBBON_H - 1.5}" font-size="7" class="num"
           fill="var(--s3)" pointer-events="none">NIGHT · ${DATA.nightSpreaders.join('/')} + ${DATA.nightShiftCutters.join('/')}</text>`;
  }

  // when each machine is actually staffed — outside it, and through breaks,
  // the row is dead. Day-only machines stop at 20:00; 24-01/02/03 run to 05:00.
  for (const r of rows){
    if (r.kind === 'gap') continue;
    const spans = (r.kind === 'spd' ? DATA.spreaderShift : cutterShift)[r.name] || [];
    const ry = top[r.key];
    let cursor = 0;
    for (const [from, to] of spans){
      if (from > cursor)
        s += `<rect x="${x(cursor)}" y="${ry}" width="${x(from) - x(cursor)}"
               height="${H_ROW - 3}" fill="var(--rule2)" opacity=".28"><title>Break</title></rect>`;
      cursor = to;
    }
    if (cursor < xmax)
      s += `<rect x="${x(cursor)}" y="${ry}" width="${x(xmax) - x(cursor)}"
             height="${H_ROW - 3}" fill="var(--rule2)" opacity=".28"><title>Not staffed — this machine's shift ended at ${clock(cursor)}</title></rect>`;
    s += `<text x="0" y="${ry + 13}" font-size="10" class="num"
           fill="var(--${r.kind === 'cut' ? 'ink' : 'muted'})"
           font-weight="${r.kind === 'cut' ? 600 : 400}">${r.label}</text>`;
    s += `<line x1="${L}" x2="${W - R}" y1="${ry + H_ROW - 3}"
           y2="${ry + H_ROW - 3}" stroke="var(--rule)" stroke-width="1"
           opacity="${r.kind === 'cut' ? 1 : .45}"/>`;
  }

  // bars
  for (const machine of Object.keys(order)){
    const queue = order[machine];
    let prevEnd = null;
    for (const idx of queue){
      const t = run.tasks[idx];
      const ss = time.ss[idx], se = time.se[idx], cs = time.cs[idx], ce = time.ce[idx];
      const cutter = run.cutters[time.cut[idx]];
      const st = t._st, col = SCOL[st];
      const rowY = top['S' + machine];

      // G6 blocking — but only the part of the gap the machine was actually
      // staffed for. Time lost to a break or to the shift ending is drawn by
      // the shift bands, and is not the machine being starved.
      if (prevEnd !== null && ss - prevEnd > 0.5){
        const idle = workingBetween(DATA.spreaderShift[machine], prevEnd, ss);
        if (idle > 0.5)
          s += `<rect x="${x(prevEnd)}" y="${rowY + 3}" width="${Math.max(1, x(ss) - x(prevEnd))}"
                 height="${H_ROW - 9}" fill="url(#blk)"><title>Blocked ${Math.round(idle)} min — not enough table free for the next lay (G6)</title></rect>`;
      } else if (prevEnd === null && ss > 0.5){
        // carry-over: before this date's first table here the machine is still
        // working through earlier plan dates' tables (or waiting for table length)
        const carried = workingBetween(DATA.spreaderShift[machine], 0, ss);
        if (carried > 0.5)
          s += `<rect x="${x(0)}" y="${rowY + 3}" width="${Math.max(1, x(ss) - x(0))}"
                 height="${H_ROW - 9}" fill="url(#ovl)"><title>${Math.round(carried)} min before this plan date's first table here: still working through earlier plan dates' tables, or waiting for table length</title></rect>`;
      }
      prevEnd = se;

      const tip = `${t.tableNo} · ${t.mo} · ${t.color} · batch ${t.batch}`
        + ` · ${t.layers} layers · spread ${Math.round(t.spreadMin)} min`
        + ` · cut ${Math.round(t.cutMin)} min · ${clock(ss)}–${clock(se)} · ${LABEL[st]}`;

      const w = Math.max(1, x(se) - x(ss));
      s += `<rect data-task="${idx}" x="${x(ss)}" y="${rowY + 2}" width="${w}"
             height="${H_ROW - 7}" rx="1.5" fill="${col}" stroke="rgba(16,23,32,.35)"
             stroke-width=".6"><title>SPD ${machine} — ${tip}</title></rect>`;
      // work that ran past this spreading machine's own staffed window
      // (occupy() in model.py lets it — the day simply overruns) — draw it
      // distinct, or it blends into the grey "not staffed" band and reads as
      // ordinary night work.
      const spdStaffEnd = staffEnd(DATA.spreaderShift[machine]);
      if (se - spdStaffEnd > 0.5)
        s += `<rect x="${x(ss)}" y="${rowY + 2}" width="${w}" height="${H_ROW - 7}" rx="1.5"
               fill="none" stroke="var(--bad)" stroke-width="1.3" stroke-dasharray="3 2">
               <title>Ran ${Math.round(se - spdStaffEnd)} min past this machine's staffed window</title></rect>`;
      // the table number, when the bar is wide enough to hold it
      const name = String(t.tableNo == null ? '' : t.tableNo);
      if (w >= name.length * 5.6 + 6)
        s += `<text data-tasklabel="${idx}" x="${x(ss) + w / 2}" y="${rowY + H_ROW / 2 + 1}" text-anchor="middle"
               class="num" font-size="8.5" font-weight="600" fill="${inkOn(col)}"
               pointer-events="none">${name}</text>`;

      const cutY = top['C' + cutter];
      const cw = Math.max(1, x(ce) - x(cs));
      s += `<rect data-task="${idx}" x="${x(cs)}" y="${cutY + 4}" width="${cw}"
             height="${H_ROW - 11}" rx="1.5" fill="${col}" opacity=".62"
             stroke="rgba(16,23,32,.3)" stroke-width=".6"><title>CUT ${cutter} — ${tip}</title></rect>`;
      const cutStaffEnd = staffEnd(cutterShift[cutter]);
      if (ce - cutStaffEnd > 0.5)
        s += `<rect x="${x(cs)}" y="${cutY + 4}" width="${cw}" height="${H_ROW - 11}" rx="1.5"
               fill="none" stroke="var(--bad)" stroke-width="1.3" stroke-dasharray="3 2">
               <title>Ran ${Math.round(ce - cutStaffEnd)} min past this cutter's staffed window</title></rect>`;

      // the pair bracket — this is what change 1 creates
      if (paired.has(idx)){
        const otherSe = time.se[paired.get(idx)];
        if (otherSe !== null && otherSe !== undefined){
          const x1 = x(ss), x2 = x(Math.max(se, otherSe)), by = rowY - 1;
          s += `<path d="M${x1} ${by + 3} L${x1} ${by} L${x2} ${by} L${x2} ${by + 3}"
                 fill="none" stroke="var(--ink)" stroke-width="1.2" opacity=".8"/>`;
        }
      }
    }
  }

  // The time cursor, on the chart's own axis — the SAME xmax resetCursor()
  // clamps the slider to, so sim.cursor can never exceed it and the line can
  // never vanish the way it could when the slider had its own, longer range.
  // >= 0, not > 0 — the line must be visible at the very left edge too
  // (cursor 0), not just once the slider has moved off it. Carries id
  // attributes so paintCursor() can move it without rebuilding this string.
  if (sim.cursor >= 0 && sim.cursor <= xmax){
    s += `<line id="cursorLine" x1="${x(sim.cursor)}" x2="${x(sim.cursor)}" y1="18" y2="${H - 4}"
           stroke="var(--s1)" stroke-width="1.5"/>`;
    s += `<text id="cursorLabel" x="${x(sim.cursor)}" y="${H - 6}" text-anchor="middle" class="num"
           font-size="9" fill="var(--s1)" font-weight="600">${clock(sim.cursor)}</text>`;
  }
  return s + '</svg>';
}

/* Which table went onto which trolley, and how full each one left. */
function trolleyTable(run){
  let h = `<thead><tr><th>Trolley</th><th>Film</th><th class="n">Compartments</th>
    <th class="n">Fill</th><th class="n">Pieces</th><th>Batches</th><th>Tables it carries</th>
    <th>Left at</th></tr></thead><tbody>`;
  run.trolleys.forEach((tr, i) => {
    const used = tr.comps.length;
    const pieces = tr.comps.reduce((n, c) => n + c.qty, 0);
    const tables = [...new Set(tr.comps.map(c => c.table))];
    const fill = 100 * used / SLOTS;
    h += `<tr><td class="num">#${String(i + 1).padStart(3, '0')}</td>`
      + `<td class="num">${tr.film}</td>`
      + `<td class="n">${used} of ${SLOTS}</td>`
      + `<td class="n" style="color:${fill >= 80 ? 'var(--s2)' : fill <= 40 ? 'var(--bad)' : 'inherit'}">`
      + `${fill.toFixed(0)}%</td>`
      + `<td class="n">${pieces}</td>`
      + `<td class="num">${[...tr.batches].join(', ')}</td>`
      + `<td class="num">${tables.join(', ')}</td>`
      + `<td class="num">${tr.parked ? 'held in WIP' : clock(tr.at)}</td></tr>`;
  });
  return h + '</tbody>';
}

/* ----------------------------------------------------------- the trolleys */
function trolleyCards(run){
  const byFilm = new Map();
  run.trolleys.forEach(tr => {
    if (!byFilm.has(tr.film)) byFilm.set(tr.film, []);
    byFilm.get(tr.film).push(tr);
  });
  const films = [...byFilm.keys()].sort((a, b) => a - b);
  const LIMIT = 60;
  let html = '';

  for (const f of films){
    const list = byFilm.get(f);
    const shown = sim.showAll ? list : list.slice(0, LIMIT);
    const full = list.filter(t => t.free === 0).length;
    html += `<div class="filmhead">FILM ${f} &mdash; ${list.length} trolleys,
             ${full} of them full`
          + (shown.length < list.length ? `, showing ${shown.length}` : '') + `</div>`;
    html += '<div class="trolleyrow">';
    for (const tr of shown){
      const tints = [...tr.batches];
      html += `<div class="tcard"><div class="h"><span>${tr.mo ? String(tr.mo).slice(-5) : ''}</span>`
            + `<span>${tr.comps.length}/${SLOTS}</span></div>`;
      for (let k = SLOTS - 1; k >= 0; k--){
        const c = tr.comps[k];
        if (!c){ html += '<div class="c empty"></div>'; continue; }
        const tint = tints.indexOf(c.batch) === 0 ? 'var(--s2)' : 'var(--s3)';
        html += `<div class="c" style="background:${tint}" title="batch ${c.batch}`
              + `${c.recalled ? ' — loaded after recall from WIP' : ''}">`
              + `<span>${c.qty}</span><span>${tints.length > 1 ? (tints.indexOf(c.batch) + 1) : ''}</span></div>`;
      }
      html += `<div class="h" style="margin:5px 0 0"><span>${tr.batches.size} batch`
            + `${tr.batches.size > 1 ? 'es' : ''}</span>`
            + `<span>${tr.parked ? 'held' : ''}</span></div></div>`;
    }
    html += '</div>';
  }
  const total = run.trolleys.length;
  if (!sim.showAll && total > LIMIT)
    html += `<p class="hint" style="margin-top:14px">Showing the first ${LIMIT} trolleys per
             film width, of ${total} for the day.
             <button type="button" id="showAll" class="theme" style="padding:4px 9px">Show all</button></p>`;
  return html;
}

/* ------------------------------------------------------------ the table */
const COLS = [
  ['seq',    'Status',   t => `<span class="dot" style="background:${SCOL[t._st]}"></span>${LABEL[t._st]}`, false],
  ['table',  'Table',    t => t.tableNo, false],
  ['mo',     'MO',       t => t.mo, false],
  ['style',  'Style',    t => t.style || '', false],
  ['color',  'Colour',   t => t.color, false],
  ['batch',  'Batch',    t => t.batch, false],
  ['machine','Machine',  t => t._machine || '—', false],
  ['start',  'Spread',   t => t._ss === undefined ? '' : clock(t._ss) + '–' + clock(t._se), true],
  ['lot',    'Lot',      t => t.lot == null ? '' : t.lot, false],
  ['layers', 'Layers',   t => t.layers, true],
  ['len',    'Marker m', t => t.markerLen.toFixed(1), true],
  ['smin',   'Spd min',  t => Math.round(t.spreadMin), true],
  ['cmin',   'Cut min',  t => Math.round(t.cutMin), true],
  ['pieces', 'Pieces',   t => t._pieces || '—', true],
  ['comps',  'Comps',    t => t.needsTrolleys ? t._comps : '—', true],
];
const SORTVAL = {
  seq: t => STATUSES.findIndex(s => s[0] === t._st),
  table: t => String(t.tableNo), mo: t => String(t.mo), style: t => String(t.style || ''),
  color: t => String(t.color), batch: t => String(t.batch),
  machine: t => String(t._machine || ''), start: t => (t._ss === undefined ? 1e9 : t._ss),
  lot: t => String(t.lot == null ? '' : t.lot),
  layers: t => t.layers, len: t => t.markerLen, smin: t => t.spreadMin, cmin: t => t.cutMin,
  pieces: t => t._pieces || 0, comps: t => t._comps || 0,
};

function taskTable(run){
  const rows = run.tasks.slice();
  rows.sort((a, b) => {
    const va = SORTVAL[sim.sortBy](a), vb = SORTVAL[sim.sortBy](b);
    if (va < vb) return -sim.sortDir;
    if (va > vb) return sim.sortDir;
    return a.i - b.i;
  });
  let h = '<thead><tr>' + COLS.map(([k, label,, num]) =>
    `<th data-sort="${k}" class="${num ? 'n' : ''}">${label}`
    + (sim.sortBy === k ? (sim.sortDir > 0 ? ' ↑' : ' ↓') : '') + '</th>').join('') + '</tr></thead><tbody>';
  for (const t of rows)
    // data-task lets paintCursor()'s rAF follow-up (D1) find this row and
    // refresh just its Status cell (COLS[0]) without a full table rebuild —
    // it does not re-sort, so a status change never reorders rows mid-drag.
    h += `<tr data-task="${t.i}">` + COLS.map(([, , fn, num]) =>
      `<td class="${num ? 'n' : ''}">${fn(t)}</td>`).join('') + '</tr>';
  return h + '</tbody>';
}

/* ------------------------------------------------ idle-time comparison
   Replaces the old idleNote prose (Phase 5B item 2). One row per cut group of
   the SELECTED variant, against the baseline that is FIXED at today / 21.2 m /
   5 cutters — "today's floor", so the sequencing toggle does not move it.

   Every number is read straight off the trace's per-variant `groups` block,
   whose attribution (blocked/spread credited to the spreading machine's own
   group; cutter-busy to whichever cutter actually ran the task, F8 included)
   is copied verbatim from idle_variants.py in daytrace.py's _groups_block —
   so this table and README Part 7 §3 agree by construction. groups[c] is
   [cutter_busy_min, blocked_min, spread_min, n_spreaders]; over is
   [machines_over_window, total_spreaders]. `run.groups`/`run.over` are always
   the TRUE selected variant's, even when it ships aggregate-only and the Gantt
   above is still drawing the baseline sequence. */
function idleComparison(run){
  const baseVar = T.days[sim.date].seq.today.table[DATA.baselineVariant];
  const bg = baseVar.groups, sg = run.groups;
  const bMin = DATA.cutterMinutesByCutterCount[BASELINE_CUTTERS];
  const sMin = DATA.cutterMinutesByCutterCount[sim.cutters] || bMin;
  const busyPct = (busy, mins) => mins ? 100 * busy / mins : 0;
  const bwPct = (blk, spr) => spr ? 100 * blk / spr : 0;

  // The selection IS the baseline when nothing is off-default. At the baseline
  // every delta would read ±0 — a column of nothing — so cell() renders the
  // bare value instead. Every non-baseline path is unchanged.
  const isBase = sim.mode === 'today' && sim.table === BASELINE_TABLE && sim.cutters === +BASELINE_CUTTERS;

  // sel value, then the signed delta vs baseline. For every metric here a
  // DECREASE is the improvement (green), so `plain` opts a column out of
  // colouring (spreading minutes — re-partitioning moves them either way and
  // neither direction is "better").
  const cell = (sel, base, {pp = false, plain = false} = {}) => {
    const s = pp ? sel.toFixed(0) + '%' : String(Math.round(sel));
    if (isBase || base === null || base === undefined) return s;
    const d = sel - base;
    if (Math.abs(d) < 0.5) return `${s} <span class="d">±0</span>`;
    const cls = plain ? '' : (d < 0 ? 'up' : 'down');
    const mag = pp ? Math.abs(d).toFixed(0) + 'pp' : String(Math.abs(Math.round(d)));
    return `${s} <span class="d ${cls}">${d > 0 ? '+' : '−'}${mag}</span>`;
  };

  // title= carries the unrounded arithmetic behind each rounded cell; cs is
  // this group's cutter's own staffed minutes (1155 for the night-capable
  // 24MC1, 675 for the rest — the default in `sMin[c] || 675`).
  let body = '';
  for (const c of Object.keys(sg)){
    const v = sg[c], b = bg[c];
    const cs = sMin[c] || 675;
    body += `<tr><td>${c}${b ? '' : ' <span class="d">new</span>'}</td><td>${v[3]}</td>`
      + `<td title="${v[0].toFixed(1)} min of cutting / ${cs} staffed min">`
        + `${cell(busyPct(v[0], cs), b ? busyPct(b[0], bMin[c]) : null, {pp: true})}</td>`
      + `<td title="${v[1].toFixed(1)} min staffed G6 wait">${cell(v[1], b ? b[1] : null)}</td>`
      + `<td title="${v[2].toFixed(1)} min laying fabric">${cell(v[2], b ? b[2] : null, {plain: true})}</td>`
      + `<td title="${v[1].toFixed(1)} blocked / ${v[2].toFixed(1)} spreading">`
        + `${cell(bwPct(v[1], v[2]), b ? bwPct(b[1], b[2]) : null, {pp: true})}</td></tr>`;
  }

  const sum = g => Object.values(g).reduce((a, v) =>
    ({busy: a.busy + v[0], blk: a.blk + v[1], spr: a.spr + v[2]}), {busy: 0, blk: 0, spr: 0});
  const S = sum(sg), B = sum(bg);
  const sMinTot = Object.keys(sg).reduce((a, c) => a + (sMin[c] || 675), 0);
  const bMinTot = Object.keys(bg).reduce((a, c) => a + (bMin[c] || 675), 0);
  body += `<tr class="tot"><td>All ${run.over[1]}</td><td>${run.over[1]}</td>`
    + `<td title="${S.busy.toFixed(1)} min of cutting / ${sMinTot} staffed min">`
      + `${cell(busyPct(S.busy, sMinTot), busyPct(B.busy, bMinTot), {pp: true})}</td>`
    + `<td title="${S.blk.toFixed(1)} min staffed G6 wait">${cell(S.blk, B.blk)}</td>`
    + `<td title="${S.spr.toFixed(1)} min laying fabric">${cell(S.spr, B.spr, {plain: true})}</td>`
    + `<td title="${S.blk.toFixed(1)} blocked / ${S.spr.toFixed(1)} spreading">`
      + `${cell(bwPct(S.blk, S.spr), bwPct(B.blk, B.spr), {pp: true})}</td></tr>`;

  const modeLabel = {today: 'today', same_batch: 'same-batch', cross_batch: 'cross-batch'}[sim.mode];
  const lead = isBase
    ? `This <b>is</b> the baseline &mdash; today's sequencing, ${BASELINE_TABLE} m table,
       ${BASELINE_CUTTERS} cutters. Blocking (rule G6) costs
       <b>${Math.round(run.blocked)} min/day</b> across the ${run.over[1]} spreading machines &mdash;
       the staffed wait for table length, which is what the chart above hatches &mdash; and
       <b>${run.over[0]}</b> of them were still spreading this date's tables after their staffed window. Change a setting to
       compare against this floor.`
    : `Selected <b>${modeLabel} &middot; ${sim.table} m &middot; ${sim.cutters} cutters</b>
       against the fixed baseline (<b>today &middot; ${BASELINE_TABLE} m &middot; ${BASELINE_CUTTERS} cutters</b>).
       Total blocking <b>${Math.round(run.blocked)} min/day</b> vs
       <b>${Math.round(baseVar.blocked)}</b>; machines over their window
       <b>${run.over[0]}</b> vs <b>${baseVar.over[0]}</b>.${run.full ? ''
        : ` The Gantt above stays on the ${BASELINE_TABLE} m / ${BASELINE_CUTTERS}-cutter sequence &mdash;
           this variant ships as numbers only (README Part 7 §7).`}`;

  return `<p class="lead">${lead}</p>`
    + `<table class="idlecmp"><thead><tr>`
    + `<th>Cut group</th><th>Spreaders</th><th>Cutter load</th><th>Blocked min</th>`
    + `<th>Spreading min</th><th>Blocked/work</th></tr></thead><tbody>${body}</tbody></table>`
    + `<p class="lead" style="margin-top:8px">Minutes are this plan date's totals for the group's own
       spreading machines. Cutter load is the cutting this day's tables need against that cutter's
       staffed day &mdash; 1,155 for 24MC1 (it runs nights), 675 for every other cutter.
       Green is an improvement over the baseline &mdash; less blocking, lower cutter load, fewer
       machines past their window. Attribution matches <code>idle_variants.py</code> and README Part 7 §3.</p>`
    + `<p class="lead" style="margin-top:8px">There is no cold start: every plan date is timed on one running
       timeline, so the machines open the day still working through the earlier plan dates' tables
       (the hatched band before a machine's first table), and what this date does not finish carries
       into the next shift. Each plan date is sequenced on its own morning around the work every
       spreader still has left. Machines run at the G2 standard pace. Blocked minutes are the
       staffed wait for table length; machines past their window are those still spreading this
       date's tables after their own shift ended.</p>`
    + `<details class="idledefs"><summary>What these columns mean</summary><div class="defs">`
    + `<p><b>Spreaders</b> &mdash; the number of spreading machines in that cut group. 24MC1 and
       24MC4 / 24MC5 have 3; 24MC2 / 24MC3 have 2 at 5 cutters.</p>`
    + `<p><b>Cutter load</b> &mdash; the minutes of cutting this day's tables need, as a share of that
       cutter's staffed day. The denominator differs by row: 1,155 min for 24MC1 (it runs nights),
       675 for the rest. A workload ratio, not a clock reading &mdash; it does not track <i>when</i>
       in the day the cutting happens, and it can exceed 100% on a day whose tables need more cutting
       than the shift holds (the model lets that work run past shift end). Credited to the cutter that
       <i>actually</i> ran each table &mdash; under rule F8, 24-03 can call 24MC2 and 24-05 can call
       24MC3 &mdash; so a row's cutter load is not the same set of tables as its Blocked or Spreading.</p>`
    + `<p><b>Blocked min</b> &mdash; minutes the group's spreading machines stood still waiting for
       enough table to come free for the next lay (rule G6). This is the <i>staffed</i> wait only: a
       break or the end of a shift is not counted, and it is exactly what the Gantt above hatches.</p>`
    + `<p><b>Spreading min</b> &mdash; minutes those machines spent actually laying fabric, including
       the 8&ndash;10 min Type C setup (rule G3).</p>`
    + `<p><b>Blocked/work</b> &mdash; Blocked &divide; Spreading, i.e. minutes lost per 100 minutes
       spread. A pure ratio, so the changing Cutter-load denominator does not affect it.</p>`
    + `</div></details>`;
}

/* ---------------------------------------------------------------- render */
// The run the cursor is currently painting against (D1) — set at the top of
// every full draw() and read by paintCursor()'s 1-minute-granularity ticks,
// so a slider drag never has to call simulate() or rebuild the SVG itself.
let lastRun = null;

function draw(run){
  run = run || simulate();
  lastRun = run;
  const day = T.days[sim.date];

  // decorate tasks for the table
  const time = run.time;
  for (const machine of Object.keys(run.order))
    for (const idx of run.order[machine]){
      const t = run.tasks[idx];
      t._machine = machine; t._ss = time.ss[idx]; t._se = time.se[idx]; t._ce = time.ce[idx];
    }
  for (const t of run.tasks){
    t._st = statusOf(t, sim.cursor);
    t._pieces = Object.values(t.pieces).reduce((a, b) => a + b, 0);
    t._comps = t.needsTrolleys ? [...compartmentsFor(t.pieces).values()]
                                   .reduce((n, l) => n + l.length, 0) : 0;
  }

  $('ganttDate').textContent = sim.date;
  $('listDate').textContent = sim.date;
  $('gantt').innerHTML = gantt(run);
  $('taskTable').innerHTML = taskTable(run);
  $('trolleyTable').innerHTML = trolleyTable(run);
  $('trolleys').innerHTML = trolleyCards(run);
  const showAllBtn = $('showAll');
  if (showAllBtn) showAllBtn.addEventListener('click', () => { sim.showAll = true; draw(); });

  $('loadSummary').textContent =
    `${run.trolleys.length} trolleys · ${run.util.toFixed(1)}% full · ${run.combines} combines`;
  $('taskSummary').textContent =
    `${run.tasks.length} tables · ${Math.round(run.tasks.reduce((n, t) => n + t.spreadMin, 0))} spreading minutes`;

  // status legend, with the two that cannot fire called out
  const counts = {};
  for (const t of run.tasks) counts[t._st] = (counts[t._st] || 0) + 1;
  $('statusLegend').innerHTML = STATUSES.map(([k, label]) => {
    const why = DATA.statusNotSimulated[k];
    return `<span class="${counts[k] ? '' : 'off'}" ${why ? `title="not simulated — ${why}"` : ''}>`
      + `<i style="background:${SCOL[k]}"></i>${label} <b>${counts[k] || 0}</b>`
      + (why ? ' <span class="muted">(not simulated)</span>' : '') + '</span>';
  }).join('');

  $('dayMeta').innerHTML = `<b>${run.tasks.length}</b> tables modelled`
    + (day.skipped ? `, ${day.skipped} skipped as Type C or first table (J2)` : '')
    + `. ${run.tasks.filter(t => !t.needsTrolleys).length} carry no compartments (J3).`;

  $('taskNote').innerHTML = `Compartments are what the table needs on its own.
    Tables that combine share fewer &mdash; that is what Panel Loading below shows.`;

  // ---- idle time — a real baseline-vs-selected comparison per cut group
  $('idleNote').innerHTML = idleComparison(run);

  /* ---- how far the floor ran behind the plan. `doneAt` is on the chart's
     clock, which starts at 07:15, so midnight at the end of the plan date is
     1440 − shift_start_minute. The dataset-wide shares come from SLIP
     (DATA.slip), which counts the same thing across all 199 plan dates, not
     just this month's — see run.py's compute_slip(). */
  const midnight = 1440 - SHIFT_START;
  const late = run.tasks.filter(t => t.doneAt !== null && t.doneAt > midnight).length;
  $('slipNote').innerHTML = `<b>${late}</b> of ${run.tasks.length} tables were not
    actually spread until after ${sim.date}. Across all ${DATA.planDates} plan dates,
    <b>${SLIP.latePct}%</b> of ${SLIP.dated} tables finish after their plan date and
    <b>${SLIP.veryLatePct}%</b> more than a day late.`;

  // ---- does this page still agree with the model?
  // Aggregate-only variants (24 m/27 m) carry no 'expected' — there is
  // nothing in the trace to check against, so the parity check is reported
  // as not applicable rather than compared against the wrong variant's data.
  const p = $('parity');
  if (!run.full){
    p.className = 'parity na';
    p.innerHTML = `No parity check for ${sim.table} m &mdash; this length ships as an
      aggregate only (no per-table timeline), so there is nothing in the page's
      own data to check itself against. Switch to ${DATA.baselineVariant.split('/')[0]} m
      to see the check.`;
  } else {
    const k = key(sim.mode, sim.batches, HOLDS[sim.holdIdx], sim.anyWs);
    const exp = run.expected[k];
    if (exp && Math.abs(exp[0] - run.util) < 0.011 && exp[1] === run.trolleys.length){
      p.className = 'parity ok';
      p.innerHTML = `&#10003; Matches the model &mdash; <span class="num">${run.trolleys.length}</span>
        trolleys, <span class="num">${run.util.toFixed(1)}%</span> full, same as
        <code>run.py</code> for this day and these settings.`;
    } else {
      p.className = 'parity bad';
      p.innerHTML = `&#9888; This page and <code>run.py</code> disagree for this day: page says
        <span class="num">${run.trolleys.length}</span> trolleys / <span class="num">${run.util.toFixed(1)}%</span>,
        the model says <span class="num">${exp ? exp[1] : '?'}</span> /
        <span class="num">${exp ? exp[0].toFixed(1) : '?'}%</span>. Trust the model.`;
    }
  }

  // ---- control labels
  $('seqVal').textContent = sim.mode === 'today' ? 'off'
    : sim.mode === 'same_batch' ? 'same batch only' : 'cross-batch';
  $('simBatchVal').textContent = sim.batches;
  $('bufVal').textContent = sim.table + ' m';
  $('simHoldVal').textContent = HOLDS[sim.holdIdx] === 0 ? 'off' : HOLDS[sim.holdIdx] + ' min';
  $('simWsVal').textContent = sim.anyWs ? 'any workstation' : 'same only';
  $('cursorVal').textContent = clock(sim.cursor);
  $('simWsField').style.opacity = HOLDS[sim.holdIdx] === 0 ? .4 : 1;
  $('simWsField').querySelectorAll('button').forEach(b => b.disabled = HOLDS[sim.holdIdx] === 0);
  document.querySelectorAll('[data-seq]').forEach(b =>
    b.setAttribute('aria-pressed', String(b.dataset.seq === sim.mode)));
  document.querySelectorAll('[data-simbatch]').forEach(b =>
    b.setAttribute('aria-pressed', String(+b.dataset.simbatch === sim.batches)));
  document.querySelectorAll('[data-table]').forEach(b =>
    b.setAttribute('aria-pressed', String(b.dataset.table === sim.table)));
  // cutting-machine count — disable pairings run.py did not precompute, and
  // say plainly which counts redraw the Gantt and which ship as numbers only.
  $('cuttersVal').textContent = sim.cutters + (run.full ? '' : ' · number only');
  $('cutterSeg').querySelectorAll('[data-cutters]').forEach(b => {
    const c = +b.dataset.cutters, meta = variantMeta(sim.table, c);
    b.disabled = !meta;
    b.setAttribute('aria-pressed', String(c === sim.cutters));
    b.title = !meta
      ? `Not precomputed at ${sim.table} m — only ${BASELINE_CUTTERS} cutters ships for 24 m and 27 m`
      : meta.full ? `${c} cutters — full timeline, the Gantt redraws`
                  : `${c} cutters — idle-time numbers only, the Gantt stays at the ${BASELINE_CUTTERS}-cutter sequence`;
  });
  {
    const fullC = DATA.cutterCounts.filter(c => variantFull(sim.table, c));
    const aggC = DATA.cutterCounts.filter(c => variantExists(sim.table, c) && !variantFull(sim.table, c));
    $('cutterHint').innerHTML = fullC.length
      ? `Rule F2 fixes 5 today (README Part 7 §4, recommendation 4). `
        + `${fullC.join(' and ')} redraw the whole Gantt`
        + (aggC.length ? `; ${aggC.join(' and ')} report their idle-time numbers with the chart left at ${fullC[0]}.` : '.')
      : `At ${sim.table} m only ${aggC.join('/')} cutters is precomputed, and it ships as a
         number only &mdash; the Gantt stays at ${BASELINE_TABLE} m / ${BASELINE_CUTTERS}.`;
  }
  document.querySelectorAll('[data-simws]').forEach(b =>
    b.setAttribute('aria-pressed', String(+b.dataset.simws === sim.anyWs)));
  // month links carry the CURRENT settings, so refresh their hrefs on every
  // draw (not just at init()) — a control change should not go stale on them.
  $('monthSeg').querySelectorAll('a').forEach(a => {
    const monthKey = a.getAttribute('href').replace(/^sim-/, '').replace(/\.html.*$/, '');
    a.setAttribute('href', `sim-${monthKey}.html#${hashState()}`);
  });
  document.querySelectorAll('[data-day]').forEach(b =>
    b.setAttribute('aria-pressed', String(b.dataset.day === sim.date)));
}

/* D1 — the cursor slider is now step="1" over a ~1,305-minute axis, so its
   `input` event can fire once a pixel. Calling the full draw() on every tick
   rebuilds the whole Gantt SVG string, the task table (up to 149 rows), the
   trolley table and the trolley cards — far too heavy at that rate. So the
   cursor's own `input` handler calls ONLY paintCursor(): it moves the
   existing #cursorLine/#cursorLabel elements' attributes and recolours bars
   already carrying data-task="<i>" (set in gantt()) by writing their `fill`
   directly — no string rebuild, no innerHTML. Every other control still goes
   through rerun()/draw(), which fully re-renders because that IS a change of
   settings, not just a clock tick.

   The task table's Status column is refreshed too, but on a
   requestAnimationFrame debounce, not per input event — dragging fires many
   times a frame, and a table with up to 149 rows does not need to be touched
   that often to look continuous. It updates cell text only (COLS[0]); it
   never re-sorts, so a status flip mid-drag cannot reorder rows under the
   reader's cursor. */
let taskTableRAF = null;
function scheduleTaskTableRefresh(run){
  if (taskTableRAF !== null) return;
  taskTableRAF = requestAnimationFrame(() => {
    taskTableRAF = null;
    const tbody = $('taskTable').querySelector('tbody');
    if (!tbody) return;
    tbody.querySelectorAll('tr[data-task]').forEach(tr => {
      const t = run.tasks[+tr.dataset.task];
      const td = tr.children[0];
      if (t && td) td.innerHTML = `<span class="dot" style="background:${SCOL[t._st]}"></span>${LABEL[t._st]}`;
    });
  });
}

function paintCursor(){
  const run = lastRun;
  if (!run) return;
  sim.cursor = +$('cursor').value;
  const svg = $('gantt').querySelector('svg');
  if (!svg) return;
  const xmax = ganttEnd(run);
  const W = ganttWidth(), L = 96, R = 14;
  const x = v => L + (W - L - R) * v / xmax;

  const line = svg.querySelector('#cursorLine'), label = svg.querySelector('#cursorLabel');
  if (line){ line.setAttribute('x1', x(sim.cursor)); line.setAttribute('x2', x(sim.cursor)); }
  if (label){ label.setAttribute('x', x(sim.cursor)); label.textContent = clock(sim.cursor); }

  for (const t of run.tasks){
    const st = statusOf(t, sim.cursor);
    if (st === t._st) continue;
    t._st = st;
    const col = SCOL[st];
    svg.querySelectorAll(`[data-task="${t.i}"]`).forEach(el => el.setAttribute('fill', col));
    const lbl = svg.querySelector(`[data-tasklabel="${t.i}"]`);
    if (lbl) lbl.setAttribute('fill', inkOn(col));
  }
  $('cursorVal').textContent = clock(sim.cursor);
  scheduleTaskTableRefresh(run);
}

/* ------------------------------------------------------------ the wiring */
function monthLabel(key){
  const [y, m] = key.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString('en-US', {month: 'short'});
}

// The 5 settings that make sense to carry to another month's file — NOT the
// date, since this month's selected date almost certainly is not in the next
// file's own dates (applyHash() below falls back gracefully if it is asked
// to anyway, but the common case of switching months should not print a
// console error on every click).
function hashState(){
  return [sim.mode, sim.batches, HOLDS[sim.holdIdx], sim.anyWs,
          variantKeyFor(sim.table, sim.cutters)].join(',');
}
function hashWithDate(){
  return hashState() + ',' + sim.date;
}

// Parses '#cross_batch,2,60,1,21.2/6,2026-06-14' (mode, batches, hold minutes,
// any-workstation, variant key, date) — built once, on load, and refreshed
// into location.hash after every control change that goes through rerun()
// (see rerun() below), so a reader can bookmark or share a specific view.
function applyHash(raw){
  if (!raw) return;
  const parts = raw.replace(/^#/, '').split(',');
  if (parts.length < 5) return;
  const [mode, batches, hold, anyWs, variant, date] = parts;
  if (['today', 'same_batch', 'cross_batch'].includes(mode)) sim.mode = mode;
  const b = +batches; if ([1, 2, 3].includes(b)) sim.batches = b;
  const hi = HOLDS.indexOf(+hold); if (hi !== -1) sim.holdIdx = hi;
  const aw = +anyWs; if (aw === 0 || aw === 1) sim.anyWs = aw;
  if (variant && variant.includes('/')){
    const [tbl, cutStr] = variant.split('/'), cut = +cutStr;
    if (DATA.tableLengths.includes(tbl)) sim.table = tbl;
    if (DATA.cutterCounts.includes(cut)) sim.cutters = cut;
    // a hash can name a (length, cutter) pair that was never precomputed
    // (e.g. 24/7) — keep the length, drop the cutter count to the floor.
    if (!variantExists(sim.table, sim.cutters)) sim.cutters = +BASELINE_CUTTERS;
  }
  if (date){
    // Fail loudly rather than silently misbehave: a hash built for one
    // month's file is not guaranteed to name a date that exists in another.
    if (date.slice(0, 7) !== DATA.month)
      console.error(`Simulation: hash date ${date} is outside this file's `
        + `month (${DATA.month}) — ignoring it, staying on ${sim.date}.`);
    else if (T.dates.includes(date))
      sim.date = date;
  }
}

function buildCalendar(){
  const dates = T.dates, first = new Date(dates[0] + 'T00:00:00');
  if (DATA.month && dates[0].slice(0, 7) !== DATA.month)
    console.error(`Simulation: this file's trace dates (starting ${dates[0]}) `
      + `do not match its own month (${DATA.month}).`);
  const year = first.getFullYear(), month = first.getMonth();
  $('calMonth').textContent = first.toLocaleDateString('en-US', {month: 'long', year: 'numeric'});
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const lead = (new Date(year, month, 1).getDay() + 6) % 7;      // Monday first
  let h = ['Mo','Tu','We','Th','Fr','Sa','Su'].map(d => `<div class="dow">${d}</div>`).join('');
  for (let i = 0; i < lead; i++) h += '<span></span>';
  for (let d = 1; d <= daysInMonth; d++){
    const iso = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
    h += dates.includes(iso)
      ? `<button type="button" data-day="${iso}" aria-pressed="${iso === sim.date}"
          title="${iso}">${d}</button>`
      : `<span title="not in the data">${d}</span>`;
  }
  $('calendar').innerHTML = h;
  $('calendar').querySelectorAll('[data-day]').forEach(b =>
    b.addEventListener('click', () => {
      sim.date = b.dataset.day; sim.showAll = false;
      sim.cursor = 0;      // a new date is a fresh timeline
      rerun();
    }));
}

/* The cursor's range is exactly the chart's own axis — the same ganttEnd(run)
   call gantt() uses for xmax (dashboard.py's B1 fix) — so a fraction f on the
   slider and fraction f on the drawn axis are the same instant by
   construction; there is no second, longer scale for them to drift apart on.

   ganttEnd(run) now floors at DATA.shiftEnd, the full two-shift window
   (05:00), and statusOf() compares against the SIMULATED cut_end, not the
   actual Pull Date — so every completion this chart can show already lives
   inside this one range. There used to be a separate day stepper to reach
   the actual Pull Date's late-finishing tail; it is gone (D5) because that
   tail is no longer what the chart is drawing against. */
function resetCursor(run){
  const el = $('cursor');
  const max = ganttEnd(run);
  el.min = 0;
  el.max = max;             // set min/max before value, so the browser does
  el.step = 1;              // not clamp value against a stale range
  sim.cursor = Math.min(sim.cursor, max);
  el.value = sim.cursor;
}

// The single place that re-simulates the day. Every control that can move
// ganttEnd(run) — sequencing, batches, table length, workstation, WIP hold,
// as well as the date buttons above — calls this, so the slider's range and
// the chart's own axis can never go stale against each other (the old code
// called resetCursor only from date changes and init()). Simulating once and
// handing the SAME run to both resetCursor and draw() also removes the
// second, redundant simulate() the old code ran on every date click.
function rerun(){
  const run = simulate();
  resetCursor(run);
  draw(run);
  // Keep the URL in step with what is actually on screen, so a reader can
  // bookmark or share this exact view, and so the month links (built fresh
  // in draw()) carry the settings forward when clicked.
  try { history.replaceState(null, '', '#' + hashWithDate()); } catch (e) {}
}

function init(){
  applyHash(location.hash);
  $('monthSeg').innerHTML = DATA.months.map(m =>
    `<a href="sim-${m.key}.html#${hashState()}" title="${m.key} — ${m.count} plan dates"
       aria-current="${m.key === DATA.month ? 'page' : 'false'}">${monthLabel(m.key)}</a>`
  ).join('');
  buildCalendar();
  document.querySelectorAll('[data-seq]').forEach(b =>
    b.addEventListener('click', () => { sim.mode = b.dataset.seq; rerun(); }));
  document.querySelectorAll('[data-simbatch]').forEach(b =>
    b.addEventListener('click', () => { sim.batches = +b.dataset.simbatch; rerun(); }));
  $('tableSeg').innerHTML = DATA.tableLengths.map(m =>
    `<button type="button" data-table="${m}" aria-pressed="${m === sim.table}">${m} m</button>`).join('');
  $('tableSeg').querySelectorAll('[data-table]').forEach(b =>
    b.addEventListener('click', () => {
      sim.table = b.dataset.table;
      // 24 m / 27 m only ship at 5 cutters — carry the cutter count over only
      // if the new pairing was precomputed, else drop back to the floor.
      if (!variantExists(sim.table, sim.cutters)) sim.cutters = +BASELINE_CUTTERS;
      rerun();
    }));
  $('cutterSeg').innerHTML = DATA.cutterCounts.map(c =>
    `<button type="button" data-cutters="${c}" aria-pressed="${c === sim.cutters}">${c}</button>`).join('');
  $('cutterSeg').querySelectorAll('[data-cutters]').forEach(b =>
    b.addEventListener('click', () => {
      if (b.disabled) return;
      sim.cutters = +b.dataset.cutters; rerun();
    }));
  document.querySelectorAll('[data-simws]').forEach(b =>
    b.addEventListener('click', () => { sim.anyWs = +b.dataset.simws; rerun(); }));
  $('simHold').addEventListener('input', e => { sim.holdIdx = +e.target.value; rerun(); });

  // the chart is drawn at the panel's width, so it has to be redrawn when that
  // changes — but only when it is on screen, and not on every resize frame
  let resizeTimer = null, lastWidth = 0;
  addEventListener('resize', () => {
    if ($('tabSim').hidden) return;
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      const w = ganttWidth();
      if (w !== lastWidth){ lastWidth = w; draw(); }
    }, 120);
  });
  $('cursor').addEventListener('input', () => paintCursor());
  $('taskTable').addEventListener('click', e => {
    const th = e.target.closest('th[data-sort]');
    if (!th) return;
    if (sim.sortBy === th.dataset.sort) sim.sortDir *= -1;
    else { sim.sortBy = th.dataset.sort; sim.sortDir = 1; }
    draw();
  });

  rerun();
}

/* ------------------------------------------------------ the parity gate
   The on-screen #parity badge checks ONE (date, variant, settings) cell —
   whatever the UI is currently showing. __check() runs the whole matrix for
   this file: every plan date x every `full` variant (21.2 m at 5 and 7
   cutters) x every reachable (mode, batches, hold, any-workstation)
   combination, comparing this page's own loadTrolleys() port against the
   trace's `expected` block — which tools/daytrace.js computed from
   tools/model.js's load_trolleys(). Two independent reimplementations of the
   loading stage, so a match is real, not circular (README Part 8 trap 8).

   `tools/parity_check.js` drives this across all three month files in a real
   browser. It replaces the stale "4,680 / 4,680" figure, which was 20 dates x
   2 sequencing modes x 3 table lengths and predates the 3-mode / cutter-count
   axes. Compartments and combines are checked alongside utilization and
   trolley count — the `expected` block carries all four. */
function __check(opts){
  opts = opts || {};
  const save = {date: sim.date, mode: sim.mode, table: sim.table, cutters: sim.cutters,
                batches: sim.batches, holdIdx: sim.holdIdx, anyWs: sim.anyWs};
  const modes = ['today', 'same_batch', 'cross_batch'];
  const fulls = DATA.simVariants.filter(v => v.full);
  let checks = 0, pass = 0;
  const fails = [];
  try {
    for (const date of T.dates){
      sim.date = date;
      for (const v of fulls){
        const [tbl, cutStr] = v.key.split('/');
        sim.table = tbl; sim.cutters = +cutStr;
        for (const mode of modes){
          sim.mode = mode;
          const expAll = T.days[date].seq[mode].table[v.key].expected || {};
          for (const batches of [1, 2, 3]){
            sim.batches = batches;
            for (let hi = 0; hi < HOLDS.length; hi++){
              for (const anyWs of [0, 1]){
                if (HOLDS[hi] === 0 && anyWs === 0) continue;   // key() folds this
                const k = key(mode, batches, HOLDS[hi], anyWs);
                const exp = expAll[k];
                checks++;
                if (!exp){ fails.push({date, variant: v.key, k, why: 'no expected entry'}); continue; }
                sim.holdIdx = hi; sim.anyWs = anyWs;
                const r = simulate();
                const ok = Math.abs(exp[0] - r.util) < 0.011
                        && exp[1] === r.trolleys.length
                        && exp[2] === r.compartments
                        && exp[3] === r.combines;
                if (ok) pass++;
                else fails.push({date, variant: v.key, k,
                  page: [+r.util.toFixed(2), r.trolleys.length, r.compartments, r.combines],
                  model: [exp[0], exp[1], exp[2], exp[3]]});
              }
            }
          }
        }
      }
    }
  } finally {
    Object.assign(sim, save);
  }
  return {file: DATA.month, dates: T.dates.length,
          checks, pass, fail: checks - pass,
          fails: fails.slice(0, opts.maxFails || 25)};
}

// `sim`, `rerun` and `__check` are exposed so the simulation state is reachable
// from the console for verification and for the headless parity driver.
return {init, redraw: () => { if (typeof draw === 'function') draw(); }, sim, rerun, __check};
})();

// A top-level `const` is not a property of `window`, so expose the handle the
// parity driver (tools/parity_check.js) reaches for. Debug-only — nothing on
// the page reads it back.
try { window.__SIM = SIM; } catch (e) {}

/* ================================================================ RULES LAB
   The engine is tools/lab.js, inlined above as `Lab` — the very file Node runs,
   so there is no second port. This block is the controls and the drawing.
   On its defaults it IS the published model: the tiles equal the Utilization tab
   and the Job Sequence equals the Simulation tab's (tools/lab_table.js and
   __labCheck prove it). If the build did not inline the engine (a Python
   build), or the browser cannot unzip, the tab stays hidden.
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
}

/* ------------------------------------------------------------------ tiles */
// The same fleet card and six tiles as the Utilization tab, for your selection. "vs today" is S0 on the same floor.
// Round trip and fleet come from the Utilization tab's sliders (state.cycle, state.fleet).
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
    && (!lab.moOneGroup || lab.seqMode === 'today');
  if (published){
    const s = DATA.sweep[key(lab.seqMode, lab.batches, lab.holdMin, lab.anyWs ? 1 : 0)];
    const ok = !!s && Math.abs(sel.utilizationPct - s.utilization_pct) <= 0.0051 && Math.abs(sel.trolleysPerDay - s.trolleys_per_day) <= 0.051;
    el.className = 'parity ' + (ok ? 'ok' : 'bad');
    el.innerHTML = ok
      ? `<span class="num">Same as the Utilization tab</span> ${f2(s.utilization_pct)}% &middot; ${f1(s.trolleys_per_day)} trolleys a day`
      : `<span class="num">Differs from the Utilization tab</span> this tab ${f2(sel.utilizationPct)}% / ${f1(sel.trolleysPerDay)}, that tab ${s ? f2(s.utilization_pct) + '% / ' + f1(s.trolleys_per_day) : 'no entry'}`;
    return;
  }
  const on = [];
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

/* ------------------------------------------------- machine-time tables */
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

function sumTable(id, parts, n, kind, a, b, dA, dB){
  const rows = [['Staffed', o => o.staffed, 0, null]]
    .concat(parts.map(([k, name, col], i) => [name, o => o[k], i === 0 ? 1 : -1, col]), [['Lost total', o => lostMin(o, parts), -1, null]]);
  const cols = '<th>S0</th><th>Yours</th><th>Change</th>';
  let h = '<tr><th></th><th class="grp" colspan="3">Per ' + kind + ', h a day</th><th class="grp" colspan="3">All ' + n + ' ' + kind + 's, h a day</th></tr>'
    + '<tr><th></th>' + cols + cols + '</tr>';
  for (const [name, get, dir, col] of rows) {
    const va = hd(get(a), dA), vb = hd(get(b), dB), t = tone(vb, va, dir);
    h += '<tr' + (name === 'Lost total' ? ' class="sel"' : '') + '><td>' + (col ? '<i class="chip" style="background:' + col + '"></i>' : '') + name + '</td>'
      + '<td>' + f2(va / n) + '</td><td>' + f2(vb / n) + '</td><td class="' + t + '">' + dsign((vb - va) / n, 2) + '</td>'
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
  const spNames = [].concat(...Object.keys(CFG.cutGroups).map(c => CFG.cutGroups[c])), cuNames = Object.keys(CFG.cutGroups);
  sumTable('labSpreadSum', SP_PARTS, s0.spM.length, 'spreader', s0.sp, sel.sp, dA, dB);
  sumTable('labCutSum', CU_PARTS, s0.cuM.length, 'cutter', s0.cu, sel.cu, dA, dB);
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
const ROWS = (() => {
  const rows = [], g = CFG.cutGroups;
  for (const c of Object.keys(g)){
    for (const m of g[c]) rows.push({key: 'S' + m, label: 'SPD ' + m, kind: 'spd', name: m});
    rows.push({key: 'C' + c, label: 'CUT ' + c.replace('24', ''), kind: 'cut', name: c});
    rows.push({kind: 'gap'});
  }
  rows.pop();
  return rows;
})();
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
  let y = RIBBON_BOTTOM + 10; const top = {};
  for (const rw of ROWS){ if (rw.kind !== 'gap') top[rw.key] = y; y += rw.kind === 'gap' ? H_GAP : H_ROW; }
  const H = y + 8;
  const opt = view.kind === 'sel' ? lab : Lab.ladder(lab, V)[0].opt;

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
    aria-label="Job sequence for ${view.date}: ${drawn.length} tables across 13 spreading machines">
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
  tiles(sel, s0); badge(sel); outputs(sel, s0, sel100, s0100); machineTables(sel, s0); dayChart(sel, s0);
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
  $('labReset').addEventListener('click', () => { lab = Object.assign({}, DEF); syncControls(); schedule(); });
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
  syncControls(); buildCalendar();
  if (!wired) wire();
  $('labStatus').textContent = 'Loading task data...';
  load().then(schedule, e => { $('labStatus').textContent = 'Could not unpack the task data: ' + e.message; });
}

/* Parity, async (the page unzips its data first). Three things:
   1. option sets Node ran with the same lab.js, re-run here;
   2. every published scenario against the Utilization tab's own numbers
      (DATA.sweep, at their published rounding);
   3. this month's Job Sequence against the Simulation tab's trace. */
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
  $('tabBtnLab').hidden = false;
  TABS.push(['tabBtnLab', 'tabLab']);
  $('tabBtnLab').addEventListener('click', () => showTab('tabBtnLab'));
}
</script>
</body>
</html>
"""
