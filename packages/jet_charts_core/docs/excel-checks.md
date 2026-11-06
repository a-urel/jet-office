# Excel checks

What Excel for Mac has settled for `jet_charts_core`, and what it has not. The
axis oracle has its own page (`axis-scaling.md`).

## Unconfirmed Office theme values

`ChartTheme.office` holds these. Excel writes none of the defaults into a file
it did not save, so each is confirmed from a chart Excel made. The optional
`chart_defaults.xlsx` (`test/fixtures/owner/axis/TALIMATLAR.md`) settles them.

| Value | Status | What supports it so far |
|---|---|---|
| Accents 1 to 6, `dk`/`lt` colours | Verified | `Office Theme.thmx`, Excel for Mac 16.114.4 |
| Line width 2.25 pt | Unconfirmed | `w="28575"`, `cap="rnd"` is the most frequent series line among the chart styles in Excel's Chart.framework `chartstyles.bin` (87 of the 202 styles with a series line); the default style is not identified |
| Marker size 5 | Unconfirmed | 39 styles use 5 and 112 use 6; 5 is the schema default |
| Gap width 219 | Unconfirmed | Second-hand only (docx.js documentation); the bundled layouts mostly give 100 and 150 |
| Overlap -27 | Unconfirmed | Second-hand only, as gap width; not in the theme yet |
| Font Aptos Narrow | Unconfirmed | `Office Theme.thmx` names Aptos, not Aptos Narrow; the narrow face is recalled, no source |
| Font sizes 9 and 14 pt | Unconfirmed | Recalled, no source |
| Text colour `595959` | Unconfirmed | Recalled, no source |
| Line colour `D9D9D9` | Unconfirmed | Recalled, no source |
| Background `FFFFFF` | Unconfirmed | Recalled, no source |
| Legend at the bottom | Unconfirmed | Spec'd, recalled, no source |
| Value gridlines on | Unconfirmed | Recalled, no source |

## Excel's palette past six colours

Unconfirmed. `ChartTheme.seriesColor` derives colours past the sixth by lightening
and darkening the accents; the steps have not been compared with what Excel does
for a seventh series.

## Milestone checks

The owner records each milestone's check here.

| Milestone | Date | Excel | Result |
|---|---|---|---|
