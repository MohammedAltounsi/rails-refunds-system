# Design system — "The Desk"

A dark payments terminal. Money is data on a trading desk: monospace figures in
ruled columns on a near-black console, one live green for credit, amber for
in-flight, red for what reverses. The look refuses the dashboard-of-cards and the
metric-tile hero; it reads as an instrument an operator watches, not a report.

Recorded from the built UI (`app/assets/tailwind/application.css`, `app/views/**`).

## Palette (dark, fixed)

Tokens are Tailwind v4 `@theme` variables; utilities follow (`bg-bg`, `text-ink`, `border-line`).

| Token | Value | Role |
|---|---|---|
| `bg` | `#0a0c10` | the console (page ground) |
| `bg-raise` | `#0e1117` | header, inputs |
| `panel` | `#12161d` | cards / panels |
| `panel-raise` | `#171d25` | row hover |
| `line` | `#222a34` | hairline rules (elevation is the border) |
| `line-bright` | `#2f3a46` | input borders |
| `ink` | `#e8ecf2` | primary readout |
| `ink-dim` | `#97a2b2` | secondary (cool-tinted, never gray) |
| `ink-faint` | `#616c7c` | labels, timestamps |
| `credit` | `#34d99b` | settled, paid, positive, in balance, primary action |
| `pending` | `#f2b23c` | processing, in-flight |
| `debit` | `#ff6058` | failed, reversal, drift, negative |

Money is colored by sign: positive `credit`, negative `debit`, zero `ink`
(`ApplicationHelper#amount`). Color strategy: Restrained — a near-black ground
with one live accent that owns the money semantics.

## Type

- **JetBrains Mono** carries every figure, id, account name, status chip, nav
  tab, column header, and page title. This is data and measurement, not a
  costume: the terminal's whole chrome is monospace.
- **Archivo** carries descriptive sentences and form inputs.
- Figures use `font-variant-numeric: tabular-nums` so columns align.
- Page titles: `.desk-title` (mono, 500, lowercase, slight positive tracking).

## Components

- `.panel` — the card. 1px `line` border, 12px radius, **no shadow**; elevation
  is declared once, as the border.
- `.chip` — status with a leading state dot; `chip-requested|processing|settled|failed`.
- `.btn-primary` — filled `credit` on dark ink text; `.btn-ghost` — 1px border,
  hovers to `credit`.
- `.field` — dark input, `credit` focus ring.
- `.ledger-table` — mono uppercase headers, hairline rows, `panel-raise` hover.
- `.readout` — a right-aligned mono value against a dim label; replaces
  metric-tile cards for summaries (charge totals, reconciliation counts).
- `.meta` — a mono micro-label for fields and section titles. **Not** a kicker:
  there are no eyebrow labels above page headings.

## Motion

One authored moment: rows **stream** onto the desk once on load (`.rise`,
staggered exponential ease-out from an already-legible default), plus the
masthead's blinking terminal **caret**. Both respect `prefers-reduced-motion`.

## Rules honored

- No eyebrow kickers, no gradient text, no glass decoration, no colored
  `border-left`, no metric-tile hero, no hard offset shadows.
- Dark chosen from the use scene (an operator watching money move on a console),
  not from category habit.
- Fonts self-served from Google Fonts; CSP allowlists `fonts.googleapis.com` /
  `fonts.gstatic.com`.

## Note on finish

The impeccable finish-reviewer subagent runs on screenshots; the browser pane in
this environment could not be displayed for capture, so verification was done
against the direction contract via computed styles (ground, fonts, chip and
amount colors), the mechanical detector (`detect.mjs`, clean), and a mobile
overflow / contrast check. Screenshot review is the one substituted step.
