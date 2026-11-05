import re
from html.parser import HTMLParser

CSS = r'''
:root {
  --bg: #f4f4f2; --fg: #16181a; --muted: #5d6366; --line: #d9dbd9;
  --sans: "Geist", "Helvetica Neue", Arial, sans-serif;
  --mono: "Geist Mono", ui-monospace, Menlo, monospace;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) { --bg: #101213; --fg: #e9ebec; --muted: #9aa1a5; --line: #2b2f31; color-scheme: dark; }
}
:root[data-theme="dark"] { --bg: #101213; --fg: #e9ebec; --muted: #9aa1a5; --line: #2b2f31; color-scheme: dark; }
* { box-sizing: border-box; }
body { background: var(--bg); color: var(--fg); font-family: var(--sans); font-size: 16px; line-height: 1.5;
  padding-block: 32px 80px; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
.wrap { max-width: 1240px; margin: 0 auto; }
h1 { font-size: 28px; line-height: 1.2; margin: 0 0 8px; font-weight: 600; text-wrap: balance; }
h2 { font-size: 22px; margin: 0 0 6px; font-weight: 600; letter-spacing: -0.01em; }
h3.sub { font-size: 15px; margin: 28px 0 10px; font-weight: 600; }
.lede { max-width: 70ch; color: var(--muted); margin: 0 0 6px; }
.note { font-family: var(--mono); font-size: 12px; color: var(--muted); margin: 0 0 20px; max-width: 90ch; }
.top { position: sticky; top: env(safe-area-inset-top, 0px); z-index: 20; background: var(--bg); padding: 10px 0; margin: 0 0 24px; border-bottom: 1px solid var(--line); display: flex; flex-wrap: wrap; gap: 12px 20px; align-items: center; }
.top nav { display: flex; flex-wrap: wrap; gap: 4px 14px; font-size: 13px; }
.top nav a { color: var(--muted); text-decoration: none; }
.top nav a:hover { color: var(--fg); }
.ctl { display: flex; align-items: center; gap: 10px; margin-left: auto; font-size: 12px; color: var(--muted); }
.top .seg { display: inline-flex; gap: 2px; padding: 2px; border: 1px solid var(--line); border-radius: 10px; }
.top .seg button { padding: 5px 10px; border-radius: 8px; font-size: 12.5px; color: var(--muted); font-weight: 500; }
.top .seg button[aria-pressed="true"] { background: var(--fg); color: var(--bg); }
section.block { margin-top: 56px; scroll-margin-top: 90px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 340px)); gap: 36px 28px; margin-top: 20px; }
.shot { min-width: 0; display: flex; flex-direction: column; gap: 8px; }
.n { font-family: var(--mono); font-size: 12px; color: var(--muted); }
.tbl-wrap { overflow-x: auto; }
.tbl { width: 100%; border-collapse: collapse; font-size: 14px; }
.tbl th, .tbl td { text-align: left; padding: 10px 12px 10px 0; border-top: 1px solid var(--line); vertical-align: top; }
.tbl th { font-weight: 500; color: var(--muted); font-size: 12px; border-top: 0; }
.tbl td:first-child { font-weight: 500; width: 26%; }
ul.plain { margin: 0; padding-left: 20px; display: grid; gap: 6px; color: var(--muted); max-width: 80ch; }
ul.plain b { color: var(--fg); font-weight: 500; }
a.ref { color: inherit; }

/* Live tokens: every phone and the foundation boards use these */
.live {
  --bg: #f5f5f6; --card: #ffffff; --ink: #111213; --muted: #6b6f76; --line: #e4e5e8; --fill: #f5f5f6;
  --accent: #1a1b1e; --accent-ink: #ffffff; --warn: #b45309; --danger: #c2362f; --glass: rgba(245,245,246,.68);
}
.live[data-theme="dark"] { --bg: #0d0e10; --card: #17181b; --ink: #f2f3f4; --muted: #8d9199; --line: #26282c; --fill: #0d0e10; --warn: #f0a23b; --danger: #f06a62; --glass: rgba(13,14,16,.62); }
.live[data-accent="graphite"] { --accent: #1a1b1e; --accent-ink: #ffffff; }
.live[data-accent="blue"] { --accent: #2f6fed; --accent-ink: #ffffff; }
.live[data-accent="green"] { --accent: #1f8a5b; --accent-ink: #ffffff; }
.live[data-accent="orange"] { --accent: #d9702a; --accent-ink: #ffffff; }
.live[data-accent="teal"] { --accent: #17858f; --accent-ink: #ffffff; }
.live[data-accent="rose"] { --accent: #c6475f; --accent-ink: #ffffff; }
.live[data-theme="dark"][data-accent="graphite"] { --accent: #eceef0; --accent-ink: #111213; }
.live[data-theme="dark"][data-accent="blue"] { --accent: #6b95ff; --accent-ink: #0a1020; }
.live[data-theme="dark"][data-accent="green"] { --accent: #45b887; --accent-ink: #06150f; }
.live[data-theme="dark"][data-accent="orange"] { --accent: #f08a46; --accent-ink: #1a0d03; }
.live[data-theme="dark"][data-accent="teal"] { --accent: #3fb3be; --accent-ink: #04161a; }
.live[data-theme="dark"][data-accent="rose"] { --accent: #ee7289; --accent-ink: #1c060b; }

.phone { position: relative; width: 340px; max-width: 100%; height: 700px; border-radius: 36px; border: 1px solid var(--line); background: var(--bg); color: var(--ink);
  font-family: var(--sans); font-size: 14px; line-height: 1.4; display: flex; flex-direction: column; overflow: hidden; }
.status { display: flex; justify-content: space-between; padding: 14px 24px 6px; font-size: 13px; font-weight: 600; flex: none; }
.body { flex: 1; min-height: 0; overflow: hidden; padding: 6px 16px 0; display: flex; flex-direction: column; gap: 14px; }
.spacer { flex: 1; }
button { font: inherit; color: inherit; background: none; border: 0; padding: 0; cursor: pointer; }
svg { stroke: currentColor; fill: none; stroke-width: 1.7; stroke-linecap: round; stroke-linejoin: round; }
:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }

/* Header, same place on every screen */
.head { display: flex; align-items: center; justify-content: space-between; height: 40px; flex: none; }
.head .t { display: flex; align-items: center; gap: 6px; min-width: 0; }
.head h3 { margin: 0; font-size: 24px; font-weight: 600; letter-spacing: -0.01em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.back { width: 32px; height: 32px; margin-left: -8px; display: grid; place-items: center; flex: none; }
.back svg { width: 20px; height: 20px; stroke-width: 2; }
.links { display: flex; gap: 2px; margin-left: auto; margin-right: -8px; }
.ic { width: 40px; height: 40px; display: grid; place-items: center; position: relative; }
.ic svg { width: 22px; height: 22px; }
.dot { position: absolute; top: 8px; right: 8px; width: 10px; height: 10px; border-radius: 50%; background: var(--warn); border: 2px solid var(--bg); }
.tray { display: flex; gap: 6px; }
.chip { display: inline-flex; align-items: center; gap: 6px; height: 34px; padding: 0 11px; border-radius: 17px; border: 1px solid var(--line); background: var(--card); color: var(--muted); font-weight: 600; font-size: 13px; }
.chip svg { width: 16px; height: 16px; }
.chip.on { background: var(--accent); border-color: var(--accent); color: var(--accent-ink); }

/* Drop-down list from a chip */
.panel { background: var(--card); border: 1px solid var(--line); border-radius: 14px; overflow: hidden; margin-top: -4px; flex: none; }
.ptitle { margin: 0; padding: 11px 12px 9px; font-size: 13px; font-weight: 600; }
.pr { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 10px 12px; border-top: 1px solid var(--line); }
.pr b { font-weight: 600; display: block; }
.pr small { color: var(--muted); font-size: 12.5px; display: block; }
.pr .thumb { width: 36px; height: 36px; border-radius: 9px; flex: none; }
.bar { height: 2px; background: var(--line); border-radius: 1px; overflow: hidden; margin-top: 6px; width: 120px; }
.bar i { display: block; height: 100%; background: var(--accent); }

/* Buttons */
.btn { display: flex; align-items: center; justify-content: center; gap: 8px; height: 46px; width: 100%; border-radius: 12px; font-weight: 600; font-size: 15px; background: var(--accent); color: var(--accent-ink); border: 1px solid var(--accent); }
.btn.sec { background: var(--card); color: var(--ink); border-color: var(--line); }
.btn.txt { background: none; border-color: transparent; color: var(--muted); font-weight: 500; height: 40px; }
.btn.dis { opacity: .4; }
.btn.danger { background: var(--danger); border-color: var(--danger); color: #fff; }
.btn.mid { width: auto; height: 36px; padding: 0 14px; font-size: 13px; border-radius: 10px; }
.btn.sm { width: auto; height: 30px; padding: 0 12px; font-size: 12.5px; border-radius: 9px; }
.acts { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }

/* Fields */
.fld { display: grid; gap: 6px; }
.fld label { font-size: 12px; font-weight: 500; color: var(--muted); }
.input { height: 48px; border-radius: 12px; border: 1px solid var(--line); background: var(--card); padding: 0 14px; display: flex; align-items: center; justify-content: space-between; color: var(--muted); }
.input.filled { color: var(--ink); }
.input.focus { border-color: var(--accent); box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 18%, transparent); }
.hint { font-size: 12.5px; color: var(--muted); margin: 0; }
.hint.err { color: var(--danger); }

/* Onboarding layout */
.ob { flex: 1; display: flex; flex-direction: column; gap: 14px; padding-bottom: 22px; }
.ob h2 { font-size: 28px; line-height: 1.15; letter-spacing: -0.02em; margin: 6px 0 0; font-weight: 600; }
.ob p { margin: 0; color: var(--muted); }
.ob .stack { display: grid; gap: 8px; }
.center { flex: 1; display: grid; place-items: center; text-align: center; }
.mark { width: 64px; height: 64px; border-radius: 18px; background: var(--accent); color: var(--accent-ink); display: grid; place-items: center; }
.mark svg { width: 34px; height: 34px; stroke-width: 2.2; }
.big-ic { width: 72px; height: 72px; border-radius: 50%; border: 1px solid var(--line); background: var(--card); display: grid; place-items: center; }
.big-ic svg { width: 30px; height: 30px; }
.ring { width: 44px; height: 44px; border-radius: 50%; border: 3px solid var(--line); border-top-color: var(--accent); }
.step { font-family: var(--mono); font-size: 12px; color: var(--muted); }

/* Nested cards: group card, item cards inside */
.gcard { background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 12px 6px 6px; flex: none; }
.gcard .label { margin: 0 0 8px 8px; font-size: 15px; font-weight: 600; letter-spacing: -0.01em; }
.items { display: grid; gap: 6px; }
.item { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 40px; padding: 0 12px 0 14px; border-radius: 12px; background: var(--fill); border: 1px solid var(--line); }
.item .k { font-size: 14px; }
.item .k small { display: block; color: var(--muted); font-size: 12px; }
.item .v { color: var(--muted); font-size: 13.5px; text-align: right; }
.item.go .v::after { content: "\203A"; margin-left: 8px; }
.item.tall { min-height: 52px; }
.time { font-family: var(--sans); font-variant-numeric: tabular-nums; font-size: 12.5px; color: var(--muted); }
.state { margin: 0; font-size: 26px; line-height: 1.2; font-weight: 600; letter-spacing: -0.015em; }
.state.warn { color: var(--warn); }
.sub-time { display: block; margin-top: 4px; color: var(--muted); font-size: 13px; }

/* Controls inside a row (no box of their own) */
.seg { display: inline-flex; gap: 2px; }
.seg button { padding: 5px 9px; border-radius: 8px; font-size: 12.5px; color: var(--muted); font-weight: 500; }
.seg button[aria-pressed="true"] { background: var(--accent); color: var(--accent-ink); }
.swatches { display: flex; gap: 6px; }
.sw { width: 22px; height: 22px; border-radius: 50%; border: 2px solid var(--fill); }
.sw[aria-pressed="true"] { box-shadow: 0 0 0 2px var(--ink); }
.switch { width: 44px; height: 26px; border-radius: 13px; background: var(--line); position: relative; flex: none; }
.switch::after { content: ""; position: absolute; top: 3px; left: 3px; width: 20px; height: 20px; border-radius: 50%; background: #fff; box-shadow: 0 1px 2px rgba(0,0,0,.25); }
.switch[aria-pressed="true"] { background: var(--accent); }
.switch[aria-pressed="true"]::after { transform: translateX(18px); }
.slider { position: relative; width: 130px; height: 4px; border-radius: 2px; background: var(--line); }
.slider i { display: block; height: 100%; border-radius: 2px; background: var(--accent); }
.slider::after { content: ""; position: absolute; top: -8px; left: var(--p, 70%); width: 20px; height: 20px; margin-left: -10px; border-radius: 50%; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,.3); }
.radio { width: 20px; height: 20px; border-radius: 50%; border: 1.5px solid var(--line); flex: none; }
.radio.on { border: 6px solid var(--accent); }

/* Banner, sheet, skeleton */
.banner { display: flex; align-items: center; gap: 10px; border: 1px solid var(--line); background: var(--card); border-radius: 12px; padding: 10px 12px; flex: none; }
.banner svg { width: 18px; height: 18px; color: var(--warn); flex: none; }
.banner p { margin: 0; flex: 1; font-size: 13px; }
.banner b { font-weight: 600; }
.scrim { position: absolute; inset: 0; background: rgba(0,0,0,.38); z-index: 5; }
.sheet { position: absolute; left: 0; right: 0; bottom: 0; z-index: 6; background: var(--card); border-radius: 22px 22px 0 0; padding: 8px 16px 24px; display: grid; gap: 10px; box-shadow: 0 -8px 30px rgba(0,0,0,.18); }
.grab { width: 36px; height: 4px; border-radius: 2px; background: var(--line); margin: 0 auto 6px; }
.sheet h4 { margin: 0; font-size: 17px; font-weight: 600; }
.sheet p { margin: 0; color: var(--muted); font-size: 13.5px; }
.sk { background: var(--line); border-radius: 8px; height: 14px; }
.sk.chip { width: 56px; height: 34px; border-radius: 17px; border: 0; }
.opt { display: flex; align-items: center; gap: 12px; height: 52px; border-radius: 12px; border: 1px solid var(--line); background: var(--fill); padding: 0 14px; }
.opt svg { width: 20px; height: 20px; }
.opt.pick { border-color: var(--accent); }
.opt span { flex: 1; }
.opt small { display: block; color: var(--muted); font-size: 12px; font-weight: 400; }
.opt b.amt { font-weight: 600; }
.wheelbox { position: relative; height: 144px; border-radius: 12px; background: var(--fill); border: 1px solid var(--line); overflow: hidden; margin: -2px 0; }
.wheel { height: 100%; overflow-y: scroll; scroll-snap-type: y mandatory; padding: 54px 0; scrollbar-width: none; -webkit-overflow-scrolling: touch;
  -webkit-mask-image: linear-gradient(transparent, #000 32%, #000 68%, transparent); mask-image: linear-gradient(transparent, #000 32%, #000 68%, transparent); }
.wheel::-webkit-scrollbar { display: none; }
.wheel div { height: 36px; line-height: 36px; text-align: center; scroll-snap-align: center; font-size: 20px; font-variant-numeric: tabular-nums; color: var(--muted); }
.wheel div.cur { color: var(--ink); font-weight: 600; }
.band { position: absolute; left: 8px; right: 8px; top: 54px; height: 36px; border-radius: 10px; background: color-mix(in srgb, var(--ink) 9%, transparent); pointer-events: none; }
.wheelbox.two { display: grid; grid-template-columns: 1fr 1fr; }
.body.fade { -webkit-mask-image: linear-gradient(#000 88%, transparent); mask-image: linear-gradient(#000 88%, transparent); }
.item.dng .k { color: var(--danger); }
.who { display: flex; align-items: center; gap: 10px; min-width: 0; }
.avatar { width: 32px; height: 32px; border-radius: 50%; background: color-mix(in srgb, var(--muted) 25%, var(--card)); display: grid; place-items: center; font-size: 13px; font-weight: 600; flex: none; }
.tag2 { font-size: 11.5px; font-weight: 500; color: var(--muted); border: 1px solid var(--line); border-radius: 6px; padding: 1px 7px; white-space: nowrap; }
.tag2.on { color: var(--accent); border-color: var(--accent); }
.map { position: relative; height: 150px; border-radius: 12px; border: 1px solid var(--line); background: var(--card); overflow: hidden; flex: none; }
.map i { position: absolute; border: 1px solid var(--line); border-radius: 8px; font-style: normal; font-size: 11px; color: var(--muted); padding: 4px 7px; }
.pin { position: absolute; width: 14px; height: 14px; border-radius: 50%; background: var(--accent); box-shadow: 0 0 0 6px color-mix(in srgb, var(--accent) 22%, transparent); }
.zone { position: absolute; border: 1.5px dashed var(--accent); border-radius: 8px; background: color-mix(in srgb, var(--accent) 8%, transparent); }
.webpg { display: grid; gap: 10px; padding-top: 4px; flex: none; }

/* Composer and conversation */
.composer { display: flex; gap: 8px; align-items: center; padding: 10px 12px 18px; flex: none; }
.field { flex: 1; min-width: 0; border: 1px solid var(--line); border-radius: 22px; padding: 11px 14px; color: var(--muted); background: var(--card); }
.field.typed { color: var(--ink); }
.round { width: 40px; height: 40px; border-radius: 50%; border: 1px solid var(--line); background: var(--card); display: grid; place-items: center; flex: none; }
.round.fill { background: var(--accent); border-color: var(--accent); color: var(--accent-ink); }
.round svg { width: 18px; height: 18px; }
.attached { display: flex; gap: 6px; padding: 0 12px; flex: none; }
.att { display: inline-flex; align-items: center; gap: 8px; height: 40px; padding: 0 8px 0 4px; border-radius: 12px; border: 1px solid var(--line); background: var(--card); font-size: 12.5px; }
.att .thumb { width: 32px; height: 32px; border-radius: 8px; }
.att svg { width: 14px; height: 14px; color: var(--muted); }
.listen { display: flex; align-items: center; gap: 12px; padding: 10px 12px 18px; flex: none; }
.listen .wave { flex: 1; height: 44px; border-radius: 22px; border: 1px solid var(--line); background: var(--card); display: flex; align-items: center; justify-content: center; gap: 4px; }
.listen .wave i { display: block; width: 3px; border-radius: 2px; background: var(--accent); }
.msg { max-width: 86%; padding: 10px 12px; border-radius: 16px; display: grid; gap: 8px; }
.msg p { margin: 0; }
.msg.me { align-self: flex-end; background: var(--accent); color: var(--accent-ink); border-bottom-right-radius: 4px; }
.msg.ad { align-self: flex-start; background: var(--card); border: 1px solid var(--line); border-bottom-left-radius: 4px; }
.file { display: flex; gap: 8px; font-size: 13px; align-items: center; }
.file small { opacity: .7; }
.thumb { background: var(--line); }
.t1 { background: color-mix(in srgb, var(--muted) 30%, var(--card)); }
.t2 { background: color-mix(in srgb, var(--muted) 20%, var(--card)); }
.t3 { background: color-mix(in srgb, var(--muted) 40%, var(--card)); }
.stage { flex: 1; min-height: 0; position: relative; overflow: hidden; }
.stage .scroll { position: absolute; inset: 0; padding: 60px 16px 84px; display: flex; flex-direction: column; justify-content: flex-end; gap: 12px; overflow: hidden; }
.glass { position: absolute; left: 0; right: 0; z-index: 2; background: var(--glass); -webkit-backdrop-filter: blur(18px) saturate(1.4); backdrop-filter: blur(18px) saturate(1.4); }
.gtop { top: 0; padding: 4px 16px 0; border-bottom: 1px solid var(--line); }
.gbot { bottom: 0; border-top: 1px solid var(--line); }
.tiles { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.tile { border: 1px solid var(--line); background: var(--card); border-radius: 12px; padding: 8px; display: grid; gap: 6px; }
.tile .thumb { height: 64px; border-radius: 8px; }
.tile b { font-weight: 600; font-size: 13px; display: block; }
.tile small { color: var(--muted); font-size: 12.5px; }
.receipt { display: flex; justify-content: space-between; font-size: 13px; padding: 6px 0; border-top: 1px solid var(--line); }
.receipt:first-child { border-top: 0; }

/* Lock screen */
.phone.lockscreen { background: #0c0d10; color: #fff; --line: rgba(255,255,255,.16); --muted: rgba(255,255,255,.62); }
.lockscreen .clock { text-align: center; padding-top: 34px; }
.lockscreen .clock b { display: block; font-size: 72px; line-height: 1; font-weight: 500; letter-spacing: -0.03em; }
.lockscreen .clock span { display: block; margin-top: 8px; font-size: 16px; color: var(--muted); }
.notif { background: rgba(255,255,255,.12); -webkit-backdrop-filter: blur(20px); backdrop-filter: blur(20px); border-radius: 22px; padding: 12px; display: grid; gap: 10px; }
.notif .row1 { display: flex; gap: 10px; align-items: flex-start; }
.notif .ai { width: 36px; height: 36px; border-radius: 10px; background: #eceef0; color: #111213; display: grid; place-items: center; flex: none; }
.notif .ai svg { width: 20px; height: 20px; stroke-width: 2.2; }
.notif b { display: block; font-weight: 600; font-size: 14.5px; }
.notif p { margin: 2px 0 0; font-size: 14px; color: rgba(255,255,255,.82); }
.notif .na { display: flex; gap: 8px; }
.notif .na span { flex: 1; text-align: center; padding: 9px 0; border-radius: 12px; background: rgba(255,255,255,.14); font-size: 14px; font-weight: 500; }

/* Foundations */
.board { border: 1px solid var(--line); border-radius: 22px; background: var(--bg); color: var(--ink); padding: 22px; font-family: var(--sans); }
.board h4 { margin: 0 0 12px; font-size: 13px; font-weight: 600; color: var(--muted); }
.swrow { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 10px; }
.swc { border: 1px solid var(--line); border-radius: 12px; overflow: hidden; background: var(--card); font-size: 12.5px; }
.swc i { display: block; height: 44px; border-bottom: 1px solid var(--line); }
.swc div { padding: 8px 10px; display: grid; gap: 2px; }
.swc b { font-weight: 600; }
.swc span { color: var(--muted); font-family: var(--mono); font-size: 11px; }
.ty { display: grid; gap: 10px; }
.ty div { display: flex; align-items: baseline; gap: 16px; border-top: 1px solid var(--line); padding-top: 10px; }
.ty div:first-child { border-top: 0; padding-top: 0; }
.ty small { width: 150px; flex: none; color: var(--muted); font-family: var(--mono); font-size: 11.5px; }
.comp { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 22px; }
.comp > div { display: grid; gap: 10px; align-content: start; }
'''

JS = r'''
(function () {
  var state = { theme: 'system', accent: 'graphite', haptics: true };
  var mq = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  function resolved() { return state.theme === 'system' ? (mq && mq.matches ? 'dark' : 'light') : state.theme; }
  function apply() {
    document.querySelectorAll('.live').forEach(function (el) { el.dataset.theme = resolved(); el.dataset.accent = state.accent; });
    document.querySelectorAll('[data-key]').forEach(function (g) {
      g.querySelectorAll('button').forEach(function (b) { b.setAttribute('aria-pressed', String(state[g.dataset.key] === b.dataset.val)); });
    });
    document.querySelectorAll('.hapsw').forEach(function (b) { b.setAttribute('aria-pressed', String(state.haptics)); });
  }
  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-key] button');
    if (b) { var g = b.closest('[data-key]'); state[g.dataset.key] = b.dataset.val; apply(); return; }
    var h = e.target.closest('.hapsw');
    if (h) { state.haptics = !state.haptics; apply(); }
  });
  if (mq && mq.addEventListener) mq.addEventListener('change', apply);
  apply();
})();
(function () {
  var H = 36;
  document.querySelectorAll('.wheel').forEach(function (w) {
    var rows = w.children, last = -1, raf = 0, start = +w.dataset.start || 0, fmt = w.dataset.fmt || '{v}';
    var host = w.closest('.sheet') || w.closest('.phone');
    var out = w.dataset.target && host ? host.querySelector(w.dataset.target) : null;
    function sync() {
      raf = 0;
      var i = Math.max(0, Math.min(rows.length - 1, Math.round(w.scrollTop / H)));
      if (i === last) return;
      if (last >= 0) rows[last].classList.remove('cur');
      rows[i].classList.add('cur'); last = i;
      if (out) out.textContent = fmt.replace('{v}', rows[i].dataset.v);
    }
    w.addEventListener('scroll', function () { if (!raf) raf = requestAnimationFrame(sync); });
    w.scrollTop = start * H; sync();
  });
})();
'''

I = {
 'back': '<svg viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7"/></svg>',
 'house': '<svg viewBox="0 0 24 24"><path d="M4 11l8-7 8 7M6 10v10h12V10"/></svg>',
 'sliders': '<svg viewBox="0 0 24 24"><path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/></svg>',
 'bell': '<svg viewBox="0 0 24 24"><path d="M6 16v-5a6 6 0 0112 0v5l1.5 2H4.5z"/><path d="M10 20.5a2 2 0 004 0"/></svg>',
 'clock': '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7.5V12l3 2"/></svg>',
 'check': '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M8 12.5l3 3 5-6"/></svg>',
 'clip': '<svg viewBox="0 0 24 24"><path d="M20 11.5l-8 8a5 5 0 01-7-7l8.5-8.5a3.3 3.3 0 014.7 4.7l-8.5 8.5a1.7 1.7 0 01-2.4-2.4l7.5-7.5"/></svg>',
 'mic': '<svg viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0014 0M12 18v3"/></svg>',
 'send': '<svg viewBox="0 0 24 24"><path d="M12 19V5M6 11l6-6 6 6"/></svg>',
 'x': '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>',
 'warn': '<svg viewBox="0 0 24 24"><path d="M12 4l9 16H3z"/><path d="M12 10v4M12 17v.5"/></svg>',
 'stop': '<svg viewBox="0 0 24 24"><rect x="7" y="7" width="10" height="10" rx="2"/></svg>',
 'photo': '<svg viewBox="0 0 24 24"><rect x="4" y="5" width="16" height="14" rx="2"/><circle cx="9" cy="10" r="1.5"/><path d="M4 16l5-4 4 3 3-2 4 3"/></svg>',
 'doc': '<svg viewBox="0 0 24 24"><path d="M7 3h7l5 5v13H7z"/><path d="M14 3v5h5"/></svg>',
 'link': '<svg viewBox="0 0 24 24"><path d="M10 14a4 4 0 005.7 0l3-3a4 4 0 00-5.7-5.7l-1 1M14 10a4 4 0 00-5.7 0l-3 3a4 4 0 005.7 5.7l1-1"/></svg>',
 'camera': '<svg viewBox="0 0 24 24"><rect x="3" y="7" width="18" height="13" rx="2"/><circle cx="12" cy="13" r="3.5"/><path d="M8 7l1.5-3h5L16 7"/></svg>',
 'lock': '<svg viewBox="0 0 24 24"><rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 018 0v3"/></svg>',
 'speaker': '<svg viewBox="0 0 24 24"><rect x="6" y="3" width="12" height="18" rx="4"/><circle cx="12" cy="14" r="3"/><circle cx="12" cy="7.5" r="1"/></svg>',
 'mark': '<svg viewBox="0 0 24 24"><path d="M6 19L12 5l6 14"/><circle cx="12" cy="15" r="1.2"/></svg>',
}

def esc(t): return t

def status(t='9:41'): return f'<div class="status"><span>{t}</span></div>'

def chips(spec):
    out = ''
    for kind, n, on in spec:
        icon = {'need': I['bell'], 'work': I['clock'], 'done': I['check']}[kind]
        label = {'need': 'need you', 'work': 'working', 'done': 'done'}[kind]
        out += f'<span class="chip{" on" if on else ""}" aria-label="{n} {label}">{icon}<b>{n}</b></span>'
    return f'<div class="tray">{out}</div>'

def head_main(spec=None, dot=False):
    left = chips(spec) if spec else '<span></span>'
    d = '<span class="dot"></span>' if dot else ''
    return (f'<div class="head">{left}<span class="links"><span class="ic">{I["house"]}{d}</span><span class="ic">{I["sliders"]}</span></span></div>')

def head_sub(title, right=''):
    return f'<div class="head"><div class="t"><span class="back">{I["back"]}</span><h3>{title}</h3></div>{right}</div>'

def head_plain(): return f'<div class="head"><span class="t"><span class="back">{I["back"]}</span></span></div>'

def composer(text=None, send=False, placeholder='Message'):
    f = f'<span class="field typed">{text}</span>' if text else f'<span class="field">{placeholder}</span>'
    right = f'<span class="round fill">{I["send"]}</span>' if send else f'<span class="round fill">{I["mic"]}</span>'
    return f'<div class="composer"><span class="round">{I["clip"]}</span>{f}{right}</div>'

def panel(title, rows):
    h = f'<div class="panel"><p class="ptitle">{title}</p>'
    for r in rows:
        left = f'<span><b>{r["t"]}</b>'
        if r.get('s'): left += f'<small>{r["s"]}</small>'
        if r.get('bar') is not None: left += f'<span class="bar" style="display:block"><i style="width:{r["bar"]}%"></i></span>'
        left += '</span>'
        right = f'<span class="btn sm">{r["a"]}</span>' if r.get('a') else ''
        h += f'<div class="pr">{left}{right}</div>'
    return h + '</div>'

def gcard(title, items):
    h = f'<div class="gcard"><p class="label">{title}</p><div class="items">'
    for it in items: h += it
    return h + '</div></div>'

def item(k, v='', go=True, sub=None, tall=False, raw_v=None):
    k2 = f'<span class="k">{k}' + (f'<small>{sub}</small>' if sub else '') + '</span>'
    v2 = raw_v if raw_v is not None else (f'<span class="v">{v}</span>' if v != '' else '')
    cls = 'item' + (' go' if go and raw_v is None else '') + (' tall' if tall or sub else '')
    return f'<div class="{cls}">{k2}{v2}</div>'

def phone(label, body, comp='', cls='', st='9:41', extra='', bodycls=''):
    return (f'<section class="shot"><span class="n">{label}</span><div class="phone live {cls}" role="img" aria-label="{label}">'
            f'{status(st)}<div class="body {bodycls}">{body}</div>{comp}{extra}</div></section>')

def sheet(inner): return f'<div class="scrim"></div><div class="sheet"><div class="grab"></div>{inner}</div>'

def block(id_, title, intro, screens, note=''):
    n = f'<p class="note">{note}</p>' if note else ''
    return (f'<section class="block" id="{id_}"><h2>{title}</h2><p class="lede">{intro}</p>{n}<div class="grid">{"".join(screens)}</div></section>')

def ob(step, title, body='', content='', buttons='', back=True):
    s = f'<span class="step">{step}</span>' if step else ''
    b = f'<p>{body}</p>' if body else ''
    return (f'{head_plain() if back else ""}<div class="ob">{s}<h2>{title}</h2>{b}{content}<div class="spacer"></div>'
            f'<div class="stack">{buttons}</div></div>')

# ---------------- screens ----------------
def launch():
    return phone('Launch', f'<div class="center"><span class="mark">{I["mark"]}</span></div>')

def welcome():
    return phone('Welcome', f'<div class="ob"><div class="spacer"></div><span class="mark">{I["mark"]}</span><h2>Sign in</h2><div class="spacer"></div>'
                 '<div class="stack"><span class="btn">Continue with Apple</span><span class="btn sec">Continue with email</span>'
                 '<span class="btn txt">New here? Create account</span></div></div>')

def signin():
    return phone('Sign in with email', ob('', 'Sign in', '',
        '<div class="fld"><label>Email</label><div class="input filled">sam@example.com</div></div>'
        '<div class="fld"><label>Password</label><div class="input filled focus">••••••••••<span class="time">Show</span></div></div>'
        '<span class="btn txt" style="justify-content:flex-start;height:28px;padding:0">Forgot password?</span>',
        '<span class="btn">Sign in</span>'))

def signin_error():
    return phone('Sign in, wrong password', ob('', 'Sign in', '',
        '<div class="fld"><label>Email</label><div class="input filled">sam@example.com</div></div>'
        '<div class="fld"><label>Password</label><div class="input filled" style="border-color:var(--danger)">••••••</div><p class="hint err">That password is wrong. Try again or reset it.</p></div>'
        '<span class="btn txt" style="justify-content:flex-start;height:28px;padding:0">Forgot password?</span>',
        '<span class="btn">Sign in</span>'))

def create():
    return phone('Create account', ob('', 'Create account', '',
        '<div class="fld"><label>Email</label><div class="input filled">sam@example.com</div></div>'
        '<div class="fld"><label>Password</label><div class="input focus"><span>Choose a password</span></div><p class="hint">At least 8 characters.</p></div>',
        '<p class="hint" style="text-align:center">By continuing you agree to the Terms and Privacy Policy.</p><span class="btn dis">Create account</span>'))

def notif_perm():
    return phone('Notifications', ob('Step 1 of 3', 'Turn on notifications', 'You will hear about things that need you, even when the app is closed.',
        f'<div class="big-ic" style="margin-top:12px">{I["bell"]}</div>',
        '<span class="btn">Allow notifications</span><span class="btn txt">Not now</span>'))

def find_speaker():
    return phone('Looking for the speaker', ob('Step 2 of 3', 'Looking for your speaker', 'Plug it in and wait for the light to pulse.',
        '<div style="display:grid;place-items:center;padding:40px 0"><span class="ring"></span></div>',
        '<span class="btn txt">I can\'t find it</span>'))

def found_speaker():
    return phone('Speaker found', ob('Step 2 of 3', 'Speaker found', '',
        gcard('Nearby', [item('Speaker', 'Ready to connect', go=False, sub='Signal strong')]),
        '<span class="btn">Connect</span>'))

def name_speaker():
    return phone('Name the speaker', ob('Step 2 of 3', 'Where is it?', '',
        '<div class="tray" style="flex-wrap:wrap"><span class="chip on">Living room</span><span class="chip">Kitchen</span><span class="chip">Bedroom</span><span class="chip">Other</span></div>'
        '<div class="fld"><label>Name</label><div class="input filled focus">Living room</div></div>',
        '<span class="btn">Continue</span>'))

def speaker_ok():
    return phone('Speaker connected', ob('Step 2 of 3', 'Speaker connected', 'It is ready. Say something to it.',
        f'<div class="big-ic" style="margin-top:12px">{I["check"]}</div>', '<span class="btn">Continue</span>'))

def connect_accounts():
    def row(name, sub): return f'<div class="item tall"><span class="k">{name}<small>{sub}</small></span><span class="btn sm">Connect</span></div>'
    return phone('Connect accounts', ob('Step 3 of 3', 'Connect your accounts', 'Optional. You can do this later in Settings.',
        gcard('Accounts', [row('Gmail', 'Read and send email'), row('Calendar', 'Read and add events'), row('Smart home', 'Lights, heating, doors')]),
        '<span class="btn">Done</span><span class="btn txt">Skip for now</span>'))

def main_first():
    return phone('First screen after setup', head_main() + '<div class="spacer"></div><p class="hint" style="text-align:center;padding-bottom:8px">Ask for anything, or talk to the speaker.</p>', composer())

def main_closed():
    return phone('Main, lists closed', head_main([('need', 2, False), ('work', 1, False), ('done', 5, False)]) + '<div class="spacer"></div>', composer())

def main_need():
    rows = [dict(t='Order groceries', s='12 items, £48.20', a='Order'), dict(t='Council bill', s='£84.00, due 3 Nov', a='Pay')]
    return phone('Main, needs you', head_main([('need', 2, True), ('work', 1, False), ('done', 5, False)]) + panel('Needs you', rows) + '<div class="spacer"></div>', composer())

def main_work():
    rows = [dict(t='Standing desks', bar=50, s='3 of 6 shops checked'), dict(t='Flights to Istanbul', bar=100, s='Checks every Friday')]
    return phone('Main, working', head_main([('need', 2, False), ('work', 1, True), ('done', 5, False)]) + panel('Working', rows) + '<div class="spacer"></div>', composer())

def main_done():
    rows = [dict(t='Train added to calendar', s='Yesterday'), dict(t='Bin day reminder', s='08:40'), dict(t='Focus mode at your desk', s='09:15')]
    return phone('Main, done', head_main([('need', 2, False), ('work', 1, False), ('done', 5, True)]) + panel('Done', rows) + '<div class="spacer"></div>', composer())

def main_alert():
    rows = [dict(t='Back door opened', s='02:14, nobody was expected', a='It was me'), dict(t='Order groceries', s='12 items, £48.20', a='Order')]
    return phone('Main, something at home needs a look', head_main([('need', 2, True), ('done', 5, False)], dot=True) + panel('Needs you', rows) + '<div class="spacer"></div>', composer(), st='2:16')

def main_offline():
    ban = f'<div class="banner">{I["warn"]}<p><b>Speaker offline.</b> Last seen 14:20.</p><span class="btn sm sec">Fix</span></div>'
    return phone('Main, speaker offline', head_main([('need', 1, False), ('done', 5, False)]) + ban + '<div class="spacer"></div>', composer())

def main_loading():
    sk = '<div class="tray"><span class="sk chip"></span><span class="sk chip"></span><span class="sk chip"></span></div>'
    return phone('Main, loading', f'<div class="head">{sk}<span class="links"><span class="ic">{I["house"]}</span><span class="ic">{I["sliders"]}</span></span></div><div class="spacer"></div>', composer())

def main_typing():
    return phone('Typing a message', head_main([('need', 2, False), ('work', 1, False), ('done', 5, False)]) + '<div class="spacer"></div>', composer('Book a table for two on Friday', send=True))

def main_listening():
    wave = ''.join(f'<i style="height:{h}px"></i>' for h in (10, 22, 14, 30, 18, 26, 12, 20, 8, 16, 24, 12))
    lst = f'<div class="listen"><div class="wave">{wave}</div><span class="round fill">{I["stop"]}</span></div>'
    return phone('Listening', head_main([('need', 2, False), ('work', 1, False), ('done', 5, False)]) + '<div class="spacer"></div><p class="hint" style="text-align:center">Listening</p>', lst)

def main_attach():
    opts = (f'<div class="opt">{I["camera"]}<span>Camera</span></div><div class="opt">{I["photo"]}<span>Photos</span></div>'
            f'<div class="opt">{I["doc"]}<span>File</span></div><div class="opt">{I["link"]}<span>Paste a link</span></div>')
    return phone('Attach sheet', head_main([('need', 2, False), ('work', 1, False), ('done', 5, False)]) + '<div class="spacer"></div>', composer(), extra=sheet(opts))

def main_attached():
    att = f'<div class="attached"><span class="att"><span class="thumb t1"></span>Photo<span>{I["x"]}</span></span><span class="att">{I["doc"]}Lease.pdf<span>{I["x"]}</span></span></div>'
    comp = att + composer('Is this the right document?', send=True)
    return phone('Attachments before sending', head_main([('need', 2, False), ('work', 1, False), ('done', 5, False)]) + '<div class="spacer"></div>', comp)

def task_screen(label, msgs, title, dark_note=''):
    return (f'<section class="shot"><span class="n">{label}</span><div class="phone live" role="img" aria-label="{label}">{status()}'
            f'<div class="stage"><div class="scroll">{msgs}</div>'
            f'<div class="glass gtop"><div class="head"><div class="t"><span class="back">{I["back"]}</span><h3>{title}</h3></div></div></div>'
            f'<div class="glass gbot">{composer(placeholder="Reply")}</div></div></div></section>')

def task_approval():
    m = ('<div class="msg me"><p>Can you check delivery slots for Thursday?</p></div><div class="msg ad"><p>Thursday, 6 to 8 pm is free.</p></div>'
         '<div class="msg me"><p>We\'ve run out of groceries</p></div>'
         '<div class="msg ad"><p>I\'ve put together a basket: 12 items, £48.20.</p><div class="acts"><span class="btn mid">Order £48.20</span><span class="btn mid sec">Change</span></div></div>')
    return task_screen('Task, needs your approval', m, 'Order groceries')

def task_results():
    tiles = ('<div class="tiles"><div class="tile"><span class="thumb t1"></span><span><b>Oak 140</b><small>£329</small></span></div>'
             '<div class="tile"><span class="thumb t2"></span><span><b>Frame 120</b><small>£249</small></span></div>'
             '<div class="tile"><span class="thumb t3"></span><span><b>Lift 160</b><small>£399</small></span></div>'
             '<div class="tile"><span class="thumb t1"></span><span><b>Basic 120</b><small>£199</small></span></div></div>')
    m = ('<div class="msg me"><p>Find me a standing desk under £400</p></div>'
         f'<div class="msg ad"><p>Four options. The Frame 120 has the best reviews.</p>{tiles}<div class="acts"><span class="btn mid">Order Frame 120</span><span class="btn mid sec">Compare</span></div></div>')
    return task_screen('Task, results with pictures', m, 'Standing desks')

def task_declined():
    m = ('<div class="msg me"><p>Order it</p></div><div class="msg ad"><p>The card was declined.</p>'
         '<div class="banner" style="border-color:var(--warn)">' + I['warn'] + '<p>Visa 4242 was declined by the bank.</p></div>'
         '<div class="acts"><span class="btn mid">Try another card</span><span class="btn mid sec">Retry</span></div></div>')
    return task_screen('Task, something failed', m, 'Standing desks')

def task_done():
    m = ('<div class="msg me"><p>Order it</p></div><div class="msg ad"><p>Ordered. Arrives Thursday, 6 to 8 pm.</p>'
         '<div><div class="receipt"><span>Frame 120</span><span>£249.00</span></div><div class="receipt"><span>Delivery</span><span>Free</span></div>'
         '<div class="receipt"><b>Total, Visa 4242</b><b>£249.00</b></div></div></div>')
    return task_screen('Task, completed', m, 'Standing desks')

def task_listening():
    wave = ''.join(f'<i style="height:{h}px"></i>' for h in (10, 22, 14, 30, 18, 26, 12, 20, 8, 16, 24, 12))
    m = '<div class="msg me"><p>Can you check delivery slots for Thursday?</p></div><div class="msg ad"><p>Thursday, 6 to 8 pm is free.</p></div>'
    return (f'<section class="shot"><span class="n">Task, listening</span><div class="phone live" role="img" aria-label="Task, listening">{status()}'
            f'<div class="stage"><div class="scroll">{m}</div><div class="glass gtop"><div class="head"><div class="t"><span class="back">{I["back"]}</span><h3>Order groceries</h3></div></div></div>'
            f'<div class="glass gbot"><div class="listen"><div class="wave">{wave}</div><span class="round fill">{I["stop"]}</span></div></div></div></div></section>')

def home_quiet():
    b = (head_sub('Home') + f'<div><p class="state">Nothing unusual</p><span class="sub-time">Last event 14:02, front door opened</span></div>'
         + gcard('Devices', [item('Speaker, living room', 'Online'), item('Lights, kitchen', 'On'), item('Heating, hallway', '19°'), item('Front door', 'Closed')])
         + gcard('Today', [item('Front door opened', '14:02', go=False), item('Focus mode at your desk', '09:15', go=False)]))
    return phone('Home, quiet', b)

def home_alert():
    b = (head_sub('Home') + f'<div><p class="state warn">Back door opened at 02:14</p><span class="sub-time">Nobody was expected. Closed again at 02:15.</span></div>'
         '<div class="acts"><span class="btn mid">It was me</span><span class="btn mid sec">Show me</span></div>'
         + gcard('Devices', [item('Back door', 'Opened 02:14', go=True), item('Hallway light', 'On since 02:14'), item('Speaker, living room', 'Online')]))
    return phone('Home, something needs a look', b, st='2:16')

def home_device():
    b = (head_sub('Lights, kitchen') +
         gcard('Controls', [item('Power', go=False, raw_v='<span class="switch" aria-pressed="true"></span>'),
                            item('Brightness', go=False, raw_v='<span class="slider" style="--p:70%"><i style="width:70%"></i></span>'),
                            item('Warmth', go=False, raw_v='<span class="seg"><button aria-pressed="false">Cool</button><button aria-pressed="true">Warm</button></span>')])
         + gcard('Today', [item('Turned on', '07:02', go=False), item('Turned off', '23:40 yesterday', go=False)]))
    return phone('Home, one device', b)

def home_empty():
    b = (head_sub('Home') + '<div class="center" style="text-align:center"><div style="display:grid;gap:14px;justify-items:center">'
         f'<span class="big-ic">{I["house"]}</span><div><p class="state" style="font-size:20px">No smart home devices</p><span class="sub-time">Connect your lights, heating and doors to see them here.</span></div>'
         '<span class="btn mid">Connect</span></div></div>')
    return phone('Home, nothing connected', b)

def settings_top():
    b = (head_sub('Settings') +
         gcard('Connections', [item('Accounts', 'Gmail, Calendar'), item('Smart home', '5 devices'), item('Cards', 'Visa 4242'), item('Saved logins', '3 sites')]) +
         gcard('Permissions', [item('Spending', 'Ask above £25'), item('Messages', 'Ask first'), item('Smart home', 'Act, then tell me')]) +
         gcard('You', [item('Appearance', 'System'), item('Export my data', ''), item('Sign out', '')]))
    return phone('Settings', b)

def settings_accounts():
    b = (head_sub('Accounts') + gcard('Connected', [item('Gmail', go=True, sub='sam@example.com', raw_v='<span class="v">Connected</span>'), item('Calendar', go=True, sub='sam@example.com', raw_v='<span class="v">Connected</span>')])
         + gcard('Add', [item('Outlook', 'Connect'), item('Notion', 'Connect'), item('Slack', 'Connect')]))
    return phone('Accounts', b)

def settings_smart():
    b = (head_sub('Smart home') + gcard('Connected', [item('Home hub', '5 devices'), item('Heating', '1 device')])
         + gcard('Add', [item('Connect a hub', ''), item('Scan for devices', '')]))
    return phone('Smart home', b)

def settings_cards():
    b = (head_sub('Cards') + gcard('Saved', [item('Visa 4242', 'Expires 12/28', go=False)]) + '<span class="btn sec">Add a card</span>'
         + '<p class="hint">You are asked before anything is bought.</p>')
    return phone('Cards', b)

def settings_addcard():
    b = (head_sub('Add a card') +
         '<div class="fld"><label>Card number</label><div class="input filled focus">4242 4242 4242 4242</div></div>'
         '<div style="display:grid;grid-template-columns:1fr 1fr;gap:10px"><div class="fld"><label>Expiry</label><div class="input filled">12 / 28</div></div><div class="fld"><label>CVC</label><div class="input filled">•••</div></div></div>'
         '<div class="fld"><label>Name on card</label><div class="input filled">Sam Taylor</div></div>'
         '<div class="spacer"></div><div class="stack" style="display:grid;gap:8px;padding-bottom:22px"><span class="btn">Save card</span><span class="btn sec">Use Apple Pay</span></div>')
    return phone('Add a card', b)

def settings_logins_locked():
    b = (head_sub('Saved logins') + '<div class="center" style="text-align:center"><div style="display:grid;gap:14px;justify-items:center">'
         f'<span class="big-ic">{I["lock"]}</span><p class="state" style="font-size:20px">Locked</p><span class="btn mid">Unlock</span></div></div>')
    return phone('Saved logins, locked', b)

def settings_logins():
    b = (head_sub('Saved logins') + gcard('Sites', [item('Tesco', 'sam@example.com'), item('Sainsbury\'s', 'sam@example.com'), item('Trainline', 'sam@example.com')])
         + '<span class="btn sec">Add a login</span>')
    return phone('Saved logins', b)

def settings_perm():
    b = (head_sub('Permissions') + gcard('Ask first or just do it', [item('Spending', 'Ask above £25'), item('Messages', 'Ask first'), item('Smart home', 'Act, then tell me'), item('Browsing sites', 'Act, then tell me')]))
    return phone('Permissions', b)

def settings_perm_sheet():
    b = head_sub('Permissions') + gcard('Ask first or just do it', [item('Spending', 'Ask above £25'), item('Messages', 'Ask first')])
    wheel = ''.join(f'<div data-v="{n}">£{n}</div>' for n in range(1, 501))
    inner = ('<h4>Spending</h4><p>Anything that costs money.</p>'
             '<div class="opt"><span>Always ask</span><i class="radio"></i></div>'
             '<div class="opt pick"><span>Ask above <b class="amt">£25</b></span><i class="radio on"></i></div>'
             f'<div class="wheelbox"><div class="wheel" id="wheel" data-start="24" data-target=".amt" data-fmt="£{{v}}">{wheel}</div><div class="band"></div></div>'
             '<div class="opt"><span>Never ask<small>Purchases go through without asking.</small></span><i class="radio"></i></div>'
             '<span class="btn">Done</span>')
    return phone('Permission options (scroll the amount)', b, extra=sheet(inner))

def settings_appearance():
    def seg(key, vals, cur):
        return f'<span class="seg" data-key="{key}">' + ''.join(f'<button data-val="{v}" aria-pressed="{str(v == cur).lower()}">{n}</button>' for v, n in vals) + '</span>'
    sw = ''.join(f'<button class="sw" data-val="{v}" style="background:{c}" aria-label="{v}" aria-pressed="{str(v == "graphite").lower()}"></button>'
                 for v, c in [('graphite', '#1a1b1e'), ('blue', '#2f6fed'), ('green', '#1f8a5b'), ('orange', '#d9702a'), ('teal', '#17858f'), ('rose', '#c6475f')])
    b = (head_sub('Appearance') +
         gcard('Look', [item('Theme', go=False, raw_v=seg('theme', [('system', 'System'), ('light', 'Light'), ('dark', 'Dark')], 'system')),
                        item('Accent', go=False, raw_v=f'<span class="swatches" data-key="accent">{sw}</span>')]) +
         gcard('Feel', [item('Haptics', go=False, raw_v='<button class="switch hapsw" role="switch" aria-label="Haptics" aria-pressed="true"></button>')]))
    return phone('Appearance (works)', b)

def settings_signout():
    b = head_sub('Settings') + gcard('You', [item('Appearance', 'System'), item('Export my data', ''), item('Sign out', '')])
    inner = '<h4>Sign out?</h4><p>You will need to sign in again on this phone.</p><span class="btn">Sign out</span><span class="btn sec">Cancel</span>'
    return phone('Sign out', b, extra=sheet(inner))

def settings_delete():
    b = head_sub('Settings') + gcard('You', [item('Appearance', 'System'), item('Export my data', ''), item('Delete account', '')])
    inner = '<h4>Delete account?</h4><p>This removes your data, saved cards and connected accounts. It can\'t be undone.</p><span class="btn danger">Delete account</span><span class="btn sec">Cancel</span>'
    return phone('Delete account', b, extra=sheet(inner))

def lock_screen(label, notifs):
    n = ''.join(notifs)
    return (f'<section class="shot"><span class="n">{label}</span><div class="phone live lockscreen" role="img" aria-label="{label}">{status("")}'
            f'<div class="clock"><span style="margin:0 0 4px">Thursday 5 November</span><b>9:41</b></div><div class="spacer"></div>'
            f'<div style="padding:0 12px 28px;display:grid;gap:8px">{n}</div></div></section>')

def notif(title, text, a1, a2):
    return (f'<div class="notif"><div class="row1"><span class="ai">{I["mark"]}</span><span><b>{title}</b><p>{text}</p></span></div>'
            f'<div class="na"><span>{a1}</span><span>{a2}</span></div></div>')

# ---------------- foundations ----------------
def foundations():
    sw = [('Background', '--bg', '#f5f5f6', '#0d0e10'), ('Card', '--card', '#ffffff', '#17181b'), ('Item', '--fill', '#f5f5f6', '#0d0e10'),
          ('Text', '--ink', '#111213', '#f2f3f4'), ('Secondary text', '--muted', '#6b6f76', '#8d9199'), ('Line', '--line', '#e4e5e8', '#26282c'),
          ('Accent, graphite', '--accent', '#1a1b1e', '#eceef0'), ('Warning', '--warn', '#b45309', '#f0a23b'), ('Danger', '--danger', '#c2362f', '#f06a62')]
    swh = ''.join(f'<div class="swc"><i style="background:var({v})"></i><div><b>{n}</b><span>light {l}</span><span>dark {d}</span></div></div>' for n, v, l, d in sw)
    ty = ('<div class="ty">'
          '<div><small>Title 28 / 600</small><span style="font-size:28px;font-weight:600;letter-spacing:-0.02em">Speaker connected</span></div>'
          '<div><small>Screen title 24 / 600</small><span style="font-size:24px;font-weight:600;letter-spacing:-0.01em">Settings</span></div>'
          '<div><small>Card title 15 / 600</small><span style="font-size:15px;font-weight:600">Connections</span></div>'
          '<div><small>Body 14 / 400</small><span style="font-size:14px">Order groceries, 12 items</span></div>'
          '<div><small>Secondary 13 / 400</small><span style="font-size:13px;color:var(--muted)">£48.20, delivery Thursday</span></div>'
          '<div><small>Caption 12 / 500</small><span style="font-size:12px;font-weight:500;color:var(--muted)">Last event 14:02</span></div></div>')
    comps = ('<div class="comp">'
      '<div><h4>Buttons</h4><span class="btn">Order £48.20</span><span class="btn sec">Change</span><span class="btn txt">Not now</span><span class="btn danger">Delete account</span><span class="btn dis">Disabled</span>'
      '<div class="acts"><span class="btn mid">Pay</span><span class="btn mid sec">Change</span><span class="btn sm">Order</span></div></div>'
      f'<div><h4>Chips and status</h4><div class="tray">{chips([("need", 2, True), ("work", 1, False), ("done", 5, False)])}</div>'
      f'<div class="banner">{I["warn"]}<p><b>Speaker offline.</b> Last seen 14:20.</p><span class="btn sm sec">Fix</span></div>'
      '<div class="bar" style="width:100%"><i style="width:50%"></i></div><span class="ring" style="width:28px;height:28px;border-width:2.5px"></span></div>'
      '<div><h4>Fields</h4><div class="fld"><label>Email</label><div class="input filled">sam@example.com</div></div>'
      '<div class="fld"><label>Password</label><div class="input focus">Choose a password</div><p class="hint">At least 8 characters.</p></div>'
      '<div class="fld"><label>Card number</label><div class="input" style="border-color:var(--danger)">4242</div><p class="hint err">Enter all 16 digits.</p></div></div>'
      '<div><h4>Cards and rows</h4>' + gcard('Devices', [item('Lights, kitchen', 'On'), item('Heating, hallway', '19°')]) +
      '<div class="gcard"><p class="label">Controls</p><div class="items">' + item('Power', go=False, raw_v='<span class="switch" aria-pressed="true"></span>')
      + item('Brightness', go=False, raw_v='<span class="slider" style="--p:70%"><i style="width:70%"></i></span>') + '</div></div></div></div>')
    rules = ('<ul class="plain"><li><b>Radii</b> follow each other: card 18, item 12 (card padding 6), button 12, small button 9, chip and message box fully round.</li>'
             '<li><b>Spacing</b> steps are 4, 8, 12, 16, 24. Screen edge padding is 16. Rows inside a card are 6 apart.</li>'
             '<li><b>One level</b> of nesting only: group card, then item rows. Controls inside a row have no box of their own.</li>'
             '<li><b>Frosted</b> only on the header and message box when a conversation scrolls under them. Cards are plain.</li>'
             '<li><b>One accent</b> for buttons and the selected chip. Warning and danger are used for state only.</li>'
             '<li><b>Font</b> is Geist everywhere. Times use tabular figures.</li></ul>')
    return ('<section class="block" id="foundations"><h2>Foundations</h2><p class="lede">The tokens and parts every screen below is built from. Use the switch at the top to see them in light or dark.</p>'
            f'<div class="board live" data-theme="light" data-accent="graphite" style="margin-top:20px"><h4>Colour</h4><div class="swrow">{swh}</div></div>'
            f'<div class="board live" style="margin-top:16px"><h4>Type</h4>{ty}</div>'
            f'<div class="board live" style="margin-top:16px"><h4>Parts</h4>{comps}</div>'
            f'<h3 class="sub">Rules</h3>{rules}</section>')

# ---------------- people, things, speaker, routines, more ----------------
def sw(on=True): return f'<span class="switch" aria-pressed="{str(on).lower()}"></span>'
def avatar(n): return f'<span class="avatar">{n}</span>'
def person(name, role, status=''):
    v = f'<span class="v">{status}</span>' if status else ''
    return f'<div class="item tall go"><span class="who">{avatar(name[0])}<span class="k">{name}<small>{role}</small></span></span>{v}</div>'
def tog(label, on=True, sub=None): return item(label, go=False, sub=sub, raw_v=sw(on))
def danger_item(label): return f'<div class="item dng"><span class="k">{label}</span></div>'
def thing(name, sub, tag):
    return f'<div class="item tall"><span class="k">{name}<small>{sub}</small></span><span class="tag2{" on" if tag == "Exact" else ""}">{tag}</span></div>'
def mapbox(kind):
    rooms = ('<i style="left:6%;top:10%;width:36%;height:48%">Hallway</i><i style="left:46%;top:10%;width:48%;height:48%">Kitchen</i>'
             '<i style="left:6%;top:62%;width:88%;height:30%">Living room</i>')
    mark = '<b class="pin" style="left:20%;top:34%"></b>' if kind == 'pin' else '<b class="zone" style="left:6%;top:10%;width:36%;height:48%"></b>'
    return f'<div class="map">{rooms}{mark}</div>'
def bottom_btns(a, b=None, cls='txt'):
    second = f'<span class="btn {cls}">{b}</span>' if b else ''
    return f'<div class="spacer"></div><div style="display:grid;gap:8px;padding-bottom:22px"><span class="btn">{a}</span>{second}</div>'

def home_quiet():
    b = (head_sub('Home') + '<div><p class="state">Nothing unusual</p><span class="sub-time">Last event 14:02, front door opened</span></div>'
         + gcard('People', [person('Sam', 'You', 'At home'), person('Alex', 'Resident', 'Away')])
         + gcard('Devices', [item('Speaker, living room', 'Online'), item('Lights, kitchen', 'On'), item('Heating, hallway', '19°'), item('Front door', 'Closed')])
         + gcard('Things', [item('Keys', 'Hallway, 08:12')]))
    return phone('Home, quiet', b, bodycls='fade')

def home_scrolled():
    b = ('<div style="height:8px"></div>' + gcard('Things', [thing('Keys', 'Hallway, 08:12', 'Exact'), thing('Wallet', 'Probably in the hallway', 'Estimate')])
         + gcard('Today', [item('Front door opened', '14:02', go=False), item('Focus mode at your desk', '09:15', go=False), item('Bin day reminder', '08:40', go=False)]))
    return phone('Home, scrolled down', b)

def settings_top():
    b = (head_sub('Settings')
         + gcard('Connections', [item('Accounts', 'Gmail, Calendar'), item('Smart home', '5 devices'), item('Cards', 'Visa 4242'), item('Saved logins', '3 sites')])
         + gcard('Home', [item('People', '3'), item('Routines', '2 on'), item('Things', '3')])
         + gcard('Permissions', [item('Spending', 'Ask above £25'), item('Messages', 'Ask first'), item('Smart home', 'Act, then tell me')])
         + gcard('You', [item('Notifications', 'On'), item('Privacy', ''), item('Appearance', 'System'), item('Export my data', ''), item('Sign out', '')]))
    return phone('Settings', b, bodycls='fade')

# People
def settings_people():
    b = (head_sub('People') + gcard('Home', [person('Sam', 'Owner, you'), person('Alex', 'Resident'), person('Jo', 'Guest, until Friday')]) + '<span class="btn sec">Invite someone</span>'
         + '<p class="hint">Residents can use everything you allow. Guests get limited access for set days and hours.</p>')
    return phone('People', b)

def invite_sheet():
    b = head_sub('People') + gcard('Home', [person('Sam', 'Owner, you'), person('Alex', 'Resident')])
    inner = ('<h4>Invite someone</h4><div class="fld"><label>Email or phone</label><div class="input filled focus">alex@example.com</div></div>'
             '<div class="opt pick"><span>Resident<small>Uses everything you allow</small></span><i class="radio on"></i></div>'
             '<div class="opt"><span>Guest<small>Limited access for set days and hours</small></span><i class="radio"></i></div>'
             '<span class="btn">Send invite</span>')
    return phone('Invite someone', b, extra=sheet(inner))

def person_detail():
    b = (head_sub('Alex') + gcard('Can', [tog('Control devices from anywhere'), tog('Add and edit devices', False), tog('Approve spending', False), tog('Use the speaker')])
         + gcard('Presence', [tog('Show when Alex is home', True)]) + gcard('Home', [item('Role', 'Resident'), danger_item('Remove from home')]))
    return phone('A resident', b)

def guest_detail():
    b = (head_sub('Jo') + gcard('Access', [item('Role', 'Guest'), item('Days and hours', 'Weekdays, 9 to 17'), item('Until', 'Friday')])
         + gcard('Can', [tog('Control devices'), tog('Use the speaker')]) + gcard('Home', [danger_item('Remove from home')]))
    return phone('A guest', b)

def invite_accept():
    return phone('Invitation, on the other person\'s phone',
        f'<div class="ob"><div class="spacer"></div><span class="mark">{I["mark"]}</span><h2>Sam invited you to their home</h2><p>You will be able to use the speaker and control devices.</p>'
        '<div class="spacer"></div><div class="stack"><span class="btn">Accept</span><span class="btn txt">Decline</span></div></div>')

def main_member_request():
    rows = [dict(t='Alex wants to order groceries', s='12 items, £48.20', a='Review'), dict(t='Council bill', s='£84.00, due 3 Nov', a='Pay')]
    return phone('Main, a request from another person', head_main([('need', 2, True), ('done', 5, False)]) + panel('Needs you', rows) + '<div class="spacer"></div>', composer())

# Things
def things_list():
    b = (head_sub('Things') + gcard('Tracked', [thing('Keys', 'Hallway, 08:12', 'Exact'), thing('Wallet', 'Probably in the hallway', 'Estimate'), thing('Bike lock', 'Garage, now', 'Exact')])
         + '<span class="btn sec">Add a thing</span>')
    return phone('Things', b)

def thing_tag():
    b = (head_sub('Keys') + '<div><p class="state">Hallway</p><span class="sub-time">Near the hallway speaker. Updated just now.</span></div>' + mapbox('pin')
         + '<div class="acts"><span class="btn mid">Play sound</span><span class="btn mid sec">Mark as found</span></div>'
         + gcard('Tag', [item('Type', 'Find My tag'), item('Battery', 'Good')]))
    return phone('A thing with a tag: exact', b)

def thing_notag():
    b = (head_sub('Wallet') + '<div><p class="state">Probably in the hallway</p><span class="sub-time">You came in at 18:42 through the front door and have not been in other rooms since.</span></div>'
         + mapbox('zone') + '<p class="hint"><span class="tag2">Estimate</span> Without a tag this is a guess from what the home noticed.</p>'
         + '<span class="btn sec">Add a tag for the exact spot</span>')
    return phone('A thing without a tag: estimate', b)

def add_thing():
    b = head_sub('Things') + gcard('Tracked', [thing('Keys', 'Hallway, 08:12', 'Exact')])
    inner = ('<h4>Add a thing</h4><p>Pick how to find it.</p>'
             '<div class="opt pick"><span>Use a tag<small>Find My or a Bluetooth tag. Gives the exact spot.</small></span><i class="radio on"></i></div>'
             '<div class="opt"><span>No tag<small>A best guess from what the home noticed.</small></span><i class="radio"></i></div>'
             '<span class="btn">Continue</span>')
    return phone('Add a thing', b, extra=sheet(inner))

def chat_keys_tag():
    m = ('<div class="msg me"><p>Where are my keys?</p></div>'
         '<div class="msg ad"><p>In the hallway, near the speaker. Seen a minute ago.</p><div class="acts"><span class="btn mid">Play sound</span></div></div>')
    return task_screen('Asking, with a tag', m, 'Where are my keys')

def chat_keys_est():
    m = ('<div class="msg me"><p>Where\'s my wallet?</p></div>'
         '<div class="msg ad"><p>I can\'t see it directly. You came in at 18:42 and have not been past the hallway since, so it is probably there.</p>'
         '<div class="acts"><span class="tag2">Estimate</span><span class="btn mid sec">Add a tag</span></div></div>')
    return task_screen('Asking, without a tag', m, 'Where\'s my wallet')

# Speaker
def home_speaker():
    b = (head_sub('Speaker, living room') +
         gcard('Controls', [item('Volume', go=False, raw_v='<span class="slider" style="--p:60%"><i style="width:60%"></i></span>'), tog('Microphone'), item('Play a test sound', '')])
         + gcard('Speaker', [item('Name and room', 'Living room'), item('Wi-Fi', 'HomeNet'), item('Software', 'Up to date'), danger_item('Remove speaker')]))
    return phone('Speaker', b)

def speaker_update():
    b = head_sub('Speaker, living room') + gcard('Speaker', [item('Name and room', 'Living room'), item('Software', 'Update available')])
    inner = '<h4>Update available</h4><p>Takes about 3 minutes. The speaker can\'t hear you while it updates.</p><span class="btn">Update now</span><span class="btn sec">Later</span>'
    return phone('Speaker, update', b, extra=sheet(inner))

def speaker_remove():
    b = head_sub('Speaker, living room') + gcard('Speaker', [item('Software', 'Up to date'), danger_item('Remove speaker')])
    inner = '<h4>Remove speaker?</h4><p>It stops working until you set it up again.</p><span class="btn danger">Remove</span><span class="btn sec">Cancel</span>'
    return phone('Speaker, remove', b, extra=sheet(inner))

def fix_offline():
    b = (head_sub('Speaker offline') + '<div><p class="state warn">Can\'t reach the speaker</p><span class="sub-time">Last seen 14:20</span></div>'
         + gcard('Check these', [item('Is it plugged in?', go=False, sub='The light should be on'), item('Is the light pulsing?', go=False, sub='Hold the button for 5 seconds if not'),
                                 item('Is your Wi-Fi working?', go=False, sub='Try another device')])
         + bottom_btns('Try again', 'Set up again'))
    return phone('Fix, speaker offline', b)

def fix_ok():
    return phone('Fix, back online', f'{head_plain()}<div class="ob"><div class="spacer"></div><span class="big-ic">{I["check"]}</span><h2>Speaker is back online</h2><div class="spacer"></div><div class="stack"><span class="btn">Done</span></div></div>')

# Routines
def routines_list():
    b = (head_sub('Routines') + gcard('On', [item('At your desk', go=False, sub='Focus mode on', raw_v=sw(True)), item('Leaving home', go=False, sub='Lights off, heating down', raw_v=sw(True)),
                                             item('Bedtime', go=False, sub='Lights down at 22:00', raw_v=sw(False))])
         + gcard('Suggested', ['<div class="item tall"><span class="k">Lights down at 22:00<small>You do this most nights</small></span><span class="btn sm">Add</span></div>'])
         + '<p class="hint">To make one, say it. For example: when I sit at my desk, turn on focus mode.</p>')
    return phone('Routines', b)

def routine_detail():
    b = (head_sub('At your desk') + gcard('When', [item('Trigger', 'You sit at your desk')]) + gcard('Then', [item('Focus mode', 'On'), item('Desk lights', 'Bright')])
         + gcard('Settings', [tog('Ask before doing it', False), danger_item('Delete routine')]))
    return phone('A routine', b)

# Notifications and privacy
def notif_settings():
    b = (head_sub('Notifications') + gcard('Tell me when', [tog('Something needs me'), tog('Something at home'), tog('A task is done', False), tog('Something fails')])
         + gcard('Quiet hours', [tog('Quiet hours'), item('From', '22:00'), item('To', '07:00')]) + '<p class="hint">Alerts about the home still come through.</p>')
    return phone('Notification settings', b)

def quiet_picker():
    hours = ''.join(f'<div data-v="{h:02d}">{h:02d}</div>' for h in range(24))
    mins = ''.join(f'<div data-v="{m:02d}">{m:02d}</div>' for m in range(0, 60, 5))
    b = head_sub('Notifications') + gcard('Quiet hours', [tog('Quiet hours'), item('From', '22:00'), item('To', '07:00')])
    inner = ('<h4>Quiet from</h4><p>Notifications wait until quiet hours end.</p>'
             '<div style="text-align:center;font-size:26px;font-weight:600;font-variant-numeric:tabular-nums"><span class="hh">22</span>:<span class="mm">00</span></div>'
             f'<div class="wheelbox two"><div class="wheel" data-start="22" data-target=".hh">{hours}</div><div class="wheel" data-start="0" data-target=".mm">{mins}</div><div class="band"></div></div>'
             '<span class="btn">Done</span>')
    return phone('Quiet hours, scroll the time', b, extra=sheet(inner))

def privacy():
    b = (head_sub('Privacy') + gcard('Speaker', [tog('Microphone'), item('Keep voice recordings', 'Off')])
         + gcard('History', [item('Keep history for', '1 year'), danger_item('Delete history')]) + gcard('Your data', [item('Export my data', ''), danger_item('Delete account')]))
    return phone('Privacy', b)

# Share and states
def share_ext():
    page = ('<div class="webpg"><div class="input" style="height:36px;border-radius:18px;justify-content:center">shop.example.com</div>'
            '<div class="thumb t2" style="height:150px;border-radius:12px"></div><div class="sk" style="width:60%;height:18px"></div><div class="sk"></div><div class="sk" style="width:80%"></div></div>')
    inner = ('<h4>Send</h4><div class="item tall"><span class="who"><span class="thumb t1" style="width:44px;height:44px;border-radius:10px;flex:none"></span>'
             '<span class="k">Frame 120 standing desk<small>shop.example.com</small></span></span></div>'
             '<div class="fld"><label>Note (optional)</label><div class="input filled">Is this a good price?</div></div><span class="btn">Send</span><span class="btn txt">Cancel</span>')
    return phone('Share from another app', page, extra=sheet(inner))

def no_connection():
    ban = f'<div class="banner">{I["warn"]}<p><b>No connection.</b> Messages send when you are back online.</p></div>'
    return phone('No internet', head_main([('need', 2, False), ('work', 1, False), ('done', 5, False)]) + ban + '<div class="spacer"></div>', composer('Is this a good price?', send=True))

def session_expired():
    inner = '<h4>You have been signed out</h4><p>Sign in again to keep going.</p><span class="btn">Sign in</span>'
    return phone('Signed out', head_main([('need', 2, False), ('done', 5, False)]) + '<div class="spacer"></div>', composer(), extra=sheet(inner))

# ---------------- assemble ----------------
first_run = block('first-run', 'First run', 'What a new person sees: the app opening, signing in, and setting up the speaker. Setup is three steps, and the last one can be skipped.',
    [launch(), welcome(), signin(), signin_error(), create(), notif_perm(), find_speaker(), found_speaker(), name_speaker(), speaker_ok(), connect_accounts(), main_first()],
    note='The app name is not shown anywhere in the app. The launch screen and notifications use the A mark only.')
main = block('main', 'Main screen', 'A near-empty screen with the message box. Open items sit behind three chips at the top left. Home and Settings are the two icons at the top right.',
    [main_closed(), main_need(), main_work(), main_done(), main_alert(), main_offline(), main_loading(), main_typing(), main_listening(), main_attach(), main_attached()])
tasks = block('tasks', 'A task', 'Each thing you ask for has its own conversation. The header and message box are frosted over the thread.',
    [task_approval(), task_results(), task_declined(), task_done(), task_listening()])
home = block('home', 'Home', 'Who is home, the state of the home, devices, things, then recent events. The screen scrolls.', [home_quiet(), home_scrolled(), home_alert(), home_device(), home_empty()])
people = block('people', 'People', 'Modelled on Apple Home: invite someone as a Resident or a Guest, set what each person can do, remove them any time. Guests get limited access for set days and hours.',
    [settings_people(), invite_sheet(), person_detail(), guest_detail(), invite_accept(), main_member_request()],
    note='Spending can only be approved by the owner unless that is switched on for a person.')
things = block('things', 'Things, like keys', 'Asking where something is works with or without a tag. A tag gives the exact spot. Without one you get a best guess, clearly marked as an estimate.',
    [things_list(), thing_tag(), thing_notag(), add_thing(), chat_keys_tag(), chat_keys_est()])
speaker = block('speaker', 'The speaker', 'Everything about the speaker itself, and what to do when it goes offline.',
    [home_speaker(), speaker_update(), speaker_remove(), fix_offline(), fix_ok()])
routines = block('routines', 'Routines', 'Things the home does on its own. Each can be switched off, edited or deleted. Suggestions appear when a pattern shows up.',
    [routines_list(), routine_detail()])
share = block('share', 'Share and bad connections', 'Sending something from another app, and what shows with no internet or when signed out.',
    [share_ext(), no_connection(), session_expired()])
settings = block('settings', 'Settings', 'Three cards: Connections, Permissions, You. Each setting appears once.',
    [settings_top(), settings_accounts(), settings_smart(), settings_cards(), settings_addcard(), settings_logins_locked(), settings_logins(), settings_perm(), settings_perm_sheet(), notif_settings(), quiet_picker(), privacy(), settings_appearance(), settings_signout(), settings_delete()],
    note='Appearance on this page works. Changing theme or accent there changes every screen.')
system = block('system', 'Notifications', 'What shows on the lock screen. Buttons act without opening the app.',
    [lock_screen('Needs you', [notif('Needs you', 'Order groceries? 12 items, £48.20.', 'Order', 'Not now')]),
     lock_screen('Something at home', [notif('Check', 'Back door opened at 02:14. Nobody was expected.', 'It was me', 'Show me')]),
     lock_screen('Done and failed', [notif('Done', 'Ordered. Arrives Thursday, 6 to 8 pm.', 'View', 'Dismiss'), notif('Couldn\'t finish', 'Visa 4242 was declined.', 'Try another card', 'Later')])])

rows = [
 ('Tap a chip', 'The list slides down from the top row in 260ms. Its items fade in 40ms apart.', 'None'),
 ('Close the list', 'Slides back up in 200ms.', 'None'),
 ('Open a task, Home or Settings', 'Slides in from the right in 300ms. Swiping from the left edge goes back.', 'None'),
 ('Press Order or Pay', 'Spinner, then a ring pings out from the button, then the row shrinks away in 250ms.', 'Success, two quick taps, only after it is confirmed'),
 ('Order or Pay fails', 'The button shakes once. The row says why and what to do. The button becomes Retry.', 'Error, three quick taps'),
 ('Something at home needs a look', 'The dot on the house icon fades in.', 'Warning, with the notification'),
 ('Switch, option, slider', 'The thumb moves in 180ms.', 'Selection tick, the system default'),
 ('Hold the microphone', 'The message box turns into the listening bar. The button grows slightly.', 'Light tap on start'),
 ('Attach a file', 'The sheet slides up in 280ms with a dimmed background.', 'None'),
 ('Speaker found during setup', 'The ring becomes a check.', 'Success'),
 ('Everything', 'When the phone\'s Reduce Motion is on, every slide becomes a 120ms fade.', 'Unchanged'),
]
tb = ''.join(f'<tr><td>{a}</td><td>{b}</td><td>{c}</td></tr>' for a, b, c in rows)
motion = (f'<section class="block" id="motion"><h2>Motion and haptics</h2><p class="lede">Haptics are kept for results that matter and for controls, because Apple advises against overusing them. Animations follow the phone\'s Reduce Motion setting. Both can be tried on the earlier appearance page.</p>'
          f'<div class="tbl-wrap" style="margin-top:16px"><table class="tbl"><thead><tr><th>Action</th><th>Animation</th><th>Haptic</th></tr></thead><tbody>{tb}</tbody></table></div></section>')

dropped = ('<section class="block" id="dropped"><h2>Dropped, and what stays</h2><p class="lede">These parts of the old app are not in this design.</p>'
           '<ul class="plain" style="margin-top:14px">'
           '<li><b>Memory page.</b> It wasn\'t part of what the app is for.</li>'
           '<li><b>Full history page.</b> The Done list covers it.</li>'
           '<li><b>Paired displays.</b> Not needed with a speaker and a phone app.</li>'
           '<li><b>Import from ChatGPT or Claude.</b></li>'
           '<li><b>Private mode.</b> It only opened Settings.</li>'
           '<li><b>Four colour themes and the opening-style option.</b> Replaced by theme and accent.</li>'
           '<li><b>The round logo menu, the wheel and any app name in the interface.</b></li></ul>'
           '<p class="note" style="margin-top:14px">The two plugs have no screen. They appear in Home as devices if they report anything.</p></section>')

sources = ('<section class="block" id="sources"><h2>Sources</h2><ul class="plain" style="margin-top:14px">'
 '<li><a class="ref" href="https://developer.apple.com/design/human-interface-guidelines/materials">Apple, Materials</a>: frosted glass on the control layer only, never glass on glass.</li>'
 '<li><a class="ref" href="https://useyourloaf.com/blog/swiftui-sensory-feedback/">Use Your Loaf, SwiftUI Sensory Feedback</a>: built-in haptic styles.</li>'
 '<li><a class="ref" href="https://github.com/EmergeTools/Pow">Pow</a>: ping and shake effects for the real app.</li>'
 '<li><a class="ref" href="https://www.nngroup.com/articles/smart-device-best-practices/">Nielsen Norman Group, smart device best practices</a>: clear status, visible progress, feedback that explains failures, devices named by room.</li>'
 '</ul></section>')

nav = ''.join(f'<a href="#{i}">{t}</a>' for i, t in [('foundations', 'Foundations'), ('first-run', 'First run'), ('main', 'Main'), ('tasks', 'Task'), ('home', 'Home'), ('people', 'People'), ('things', 'Things'), ('speaker', 'Speaker'), ('routines', 'Routines'), ('settings', 'Settings'), ('share', 'Share'), ('system', 'Notifications'), ('motion', 'Motion'), ('dropped', 'Dropped')])
topbar = ('<div class="top"><nav>' + nav + '</nav><div class="ctl"><span>Theme</span><span class="seg" data-key="theme">'
          '<button data-val="system" aria-pressed="true">System</button><button data-val="light" aria-pressed="false">Light</button><button data-val="dark" aria-pressed="false">Dark</button></span></div></div>')

page = ('<meta charset="utf-8"><title>Adam App Design</title><meta name="claude:viewport-fit-sides" content="cover">'
        '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&family=Geist+Mono:wght@400;500&display=swap">'
        f'<style>{CSS}</style><div class="wrap"><h1>One design for the whole app</h1>'
        '<p class="lede">Every screen from opening the app for the first time to Settings, in one set of tokens. The Theme switch at the top flips every screen between light and dark.</p>'
        '<p class="note">All names, numbers and times are examples, not real data. Nothing here has been checked on a real phone.</p>'
        + topbar + foundations() + first_run + main + tasks + home + people + things + speaker + routines + settings + share + system + motion + dropped + sources +
        f'</div><script>{JS}</script>')

# structure check
class P(HTMLParser):
    VOID = {'meta', 'link', 'br', 'input', 'img', 'path', 'circle', 'rect'}
    def __init__(self): super().__init__(); self.st = []; self.err = []
    def handle_starttag(self, t, a):
        if t not in self.VOID: self.st.append(t)
    def handle_startendtag(self, t, a): pass
    def handle_endtag(self, t):
        if t in self.VOID: return
        if not self.st or self.st[-1] != t: self.err.append((t, self.st[-3:]))
        else: self.st.pop()
p = P(); p.feed(page.replace('<script>', '<!--').replace('</script>', '-->'))
print('unclosed', p.st[:5], 'errors', p.err[:5])
open('adam-app-design.html', 'w').write(page)
print(len(page), 'chars;', page.count('class="phone live'), 'phones')
