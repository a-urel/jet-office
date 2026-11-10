# Owner charts

This folder holds `chart_reference.xlsx`, the workbook the owner saves in Excel
for Mac from the steps in `TALIMATLAR.md`. The Excel version is recorded in
`docs/excel-checks.md` when the file arrives.

`test/drawingml/chart/excel_reference_test.dart` (VM) reads it. It also reads
the owner's `chart_defaults.xlsx`, which is committed under
`packages/jet_charts_core/test/fixtures/owner/axis_full/`. Nobody edits a
committed owner file; a change needs a new file from the owner.

The sheet `Veri` holds A1 empty, B1 `Kuzey`, C1 `Güney`, A2:A5 `Ç1` to `Ç4` and
B2:C5 `10 20; 25 15; 30 35; 18 22`. Each chart is made from A1:C5. The charts,
in order:

1. Clustered column. Tests the kind and the grouping.
2. Stacked column.
3. 100% stacked column.
4. Clustered bar.
5. Stacked bar.
6. 100% stacked bar.
7. Line with markers.
8. Stacked line with markers.
9. 100% stacked line with markers.
10. Area.
11. Stacked area.
12. 100% stacked area.

Charts 1 to 12 also test what Excel writes by default for each kind: title,
legend, axes and gap values.

13. Clustered column with the title `Satışlar`. Tests the title.
14. Legend at the top.
15. Legend on the right.
16. No legend.
17. Both axis titles, `Çeyrek` and `Tutar`.
18. Value axis minimum 0, maximum 50, major unit 10.
19. Value axis number format `#,##0.00`.
20. Data labels on.
21. Data labels on with the format `0.0`.
22. Value axis and gridlines deleted.
23. The name `Tutarlar` (`Veri!$B$2:$B$5`) used as the first series' values.
    Tests how Excel writes a defined name in a series reference, in particular
    whether it writes `[0]!Tutarlar`.

Only the owner's run counts; no result is invented.

## J4: `chart_reference_j4.xlsx`

The owner's E1 workbook for milestone J4, saved on 2026-11-10 in Microsoft
Excel for Mac 16.114.4 (26110224), Microsoft 365, from the steps in
`TALIMATLAR_J4.md`. The Claude Excel add-in typed the sheet `Veri` (A1 empty,
B1 `Satış`, C1 `Adet`, A2:A5 `Kuzey`, `Güney`, `Doğu`, `Batı`, B2:C5
`12 120; 18 95; -4 140; 9 80`) and left its task pane parts
(`xl/webextensions/`) in the file; the owner added the seven charts by hand
from the Insert menu:

1. Pie of A1:B5.
2. Doughnut of A1:B5.
3. Doughnut of A1:C5 (two rings).
4. Scatter with markers only. The selection took the text A2:A5 as x values
   and `Satış` and `Adet` as two series, not B2:C5 as one series.
5. Combination "Clustered Column - Line", both series on one axis: not the
   secondary axis variant of the steps.
6. Line with markers of A1:A5 and C1:C5, smoothed.
7. Pie of A1:B5 with best fit data labels.

`test/drawingml/chart/excel_reference_j4_test.dart` (VM) pins what Excel
wrote; `packages/jet_charts_core/docs/excel-checks.md`, "J4 values", says what
each value confirmed or changed. A secondary axis and a scatter of numeric x
values need a new file from the owner: the steps are `TALIMATLAR_E3.md`
(`chart_reference_e3.xlsx`, later).
