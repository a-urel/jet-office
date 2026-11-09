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
