// Validates every .xlsx and .docx file in a directory with the Open XML SDK.
//
//   dotnet run --project tool/ooxml_validate -- build/fixtures
//   dotnet run --project tool/ooxml_validate -- --libreoffice-resave <dir>
//
// Each file is checked against the Microsoft 365 schemas
// (FileFormatVersions.Microsoft365): a workbook opened as a
// SpreadsheetDocument, a document as a WordprocessingDocument. Every error is
// printed with its part and XPath. A Word lock file (~$name.docx, which Word
// leaves beside an open document) is skipped. The exit code is 0 when no
// file has an error, 1 when any has, and 2 for a usage error or a directory
// without .xlsx or .docx files. CI runs it on the fixtures
// tool/write_fixtures.dart writes (AGENTS.md, "Validation").
//
// --libreoffice-resave is for a directory whose files came from LibreOffice's
// re-save (or from the model's round trip or edit of one). LibreOffice writes
// a repeating header row as <w:tblHeader w:val="true"/>, which the SDK's
// schema refuses (it takes only on and off there) although ECMA-376's
// ST_OnOff and Word accept true. The model keeps the element as read, so the
// error is LibreOffice's, not the model's. w:cantSplit has the same type and
// the same fate: LibreOffice 26.8 writes it bare, but the flag covers it too,
// so a producer's true there fails no more than on its sibling. The flag
// ignores exactly that: a Sch_AttributeValueDataTypeDetailed error on a
// w:tblHeader or a w:cantSplit element whose w:val is exactly "true". Every
// other error, and every file without the flag, counts as before.
//
// The flag also covers LibreOffice's chart style parts
// (application/vnd.ms-office.chartstyle+xml), which LibreOffice 26.8 writes
// beside every chart it re-saves and the model keeps as read: their
// cs:dataPointMarkerLayout holds the four style references the schema keeps
// for other entries (Sch_InvalidChildinLeafElement), and the cs:fontRef of
// cs:dataPoint holds a cs:schemeClr where the schema takes a:schemeClr
// (Sch_InvalidElementContentExpectingComplex). The flag ignores exactly those
// two errors in a chart style part: the first on cs:dataPointMarkerLayout, the
// second on a cs:fontRef with a cs:schemeClr child.
//
// Without a flag one more pair of errors is ignored, in every run: the SDK
// 3.5.1 refuses the extension Excel for Mac writes in every chart part,
// <c:chart><c:extLst><c:ext uri="{56B9EC1D-385E-4148-901F-78D8002777C0}">
// holding <c16r3:dataDisplayOptions16><c16r3:dispNaAsBlank val="1"/>, with
// Sch_UndeclaredAttribute (the uri) and
// Sch_InvalidElementContentExpectingComplex (the dataDisplayOptions16 child,
// "expected: dispNaAsBlank"), as if the c:ext were the dataDisplayOptions16
// element itself. Excel's own chart parts get both errors (the owner's
// chart_defaults.xlsx, packages/jet_charts_core/test/fixtures/owner), so they
// are the SDK's, not a writer's. Only those two error ids are ignored, and only
// on the c:ext at /c:chartSpace[1]/c:chart[1]/c:extLst[1]/c:ext[1] of a chart
// part whose only attribute is uri, with exactly that value, whose only child
// is one c16r3:dataDisplayOptions16, whose only child is one
// c16r3:dispNaAsBlank, whose only attribute is an unqualified val of 1, 0,
// true or false (xsd:boolean; Excel writes 1). Any other content of the
// extension, a second or a missing dispNaAsBlank, another attribute or value,
// still counts. tool/write_fixtures.dart --corrupt writes c1_corrupt.xlsx, a
// chart whose extension holds two dispNaAsBlank, as the negative control.
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;

bool libreOfficeResave = args.Length == 2 && args[0] == "--libreoffice-resave";
string[] paths = libreOfficeResave ? args[1..] : args;
if (paths.Length != 1 || !Directory.Exists(paths[0]))
{
    Console.Error.WriteLine("Usage: dotnet run --project tool/ooxml_validate -- [--libreoffice-resave] <dir>");
    return 2;
}

// LibreOffice's w:tblHeader and w:cantSplit w:val="true", see the header
// comment.
static bool IsLibreOfficeRowOnOffTrue(ValidationErrorInfo e) =>
    e.Id == "Sch_AttributeValueDataTypeDetailed"
    && e.Node is DocumentFormat.OpenXml.Wordprocessing.TableHeader
        or DocumentFormat.OpenXml.Wordprocessing.CantSplit
    && e.Node.GetAttributes().Any(a => a.LocalName == "val" && a.Value == "true");

// LibreOffice's chart style part errors, see the header comment.
const string chartStyleContentType = "application/vnd.ms-office.chartstyle+xml";
const string chartStyle = "http://schemas.microsoft.com/office/drawing/2012/chartStyle";
static bool IsLibreOfficeChartStyle(ValidationErrorInfo e) =>
    e.Part?.ContentType == chartStyleContentType
    && (e.Id == "Sch_InvalidChildinLeafElement"
            && e.Node is { LocalName: "dataPointMarkerLayout", NamespaceUri: chartStyle }
        || e.Id == "Sch_InvalidElementContentExpectingComplex"
            && e.Node is { LocalName: "fontRef", NamespaceUri: chartStyle } fontRef
            && fontRef.ChildElements.Any(c => c.LocalName == "schemeClr" && c.NamespaceUri == chartStyle));

// Excel's chart display options extension, see the header comment.
const string chartContentType = "application/vnd.openxmlformats-officedocument.drawingml.chart+xml";
const string c16r3 = "http://schemas.microsoft.com/office/drawing/2017/03/chart";
static bool IsExcelDataDisplayOptions(ValidationErrorInfo e) =>
    e.Id is "Sch_UndeclaredAttribute" or "Sch_InvalidElementContentExpectingComplex"
    && e.Part?.ContentType == chartContentType
    && e.Path?.XPath == "/c:chartSpace[1]/c:chart[1]/c:extLst[1]/c:ext[1]"
    && e.Node is { LocalName: "ext" } ext
    && ext.GetAttributes() is [{ LocalName: "uri", NamespaceUri: "", Value: "{56B9EC1D-385E-4148-901F-78D8002777C0}" }]
    && ext.ChildElements.Count == 1
    && ext.ChildElements[0] is { LocalName: "dataDisplayOptions16", NamespaceUri: c16r3 } options
    && options.GetAttributes().Count == 0
    && options.ChildElements.Count == 1
    && options.ChildElements[0] is { LocalName: "dispNaAsBlank", NamespaceUri: c16r3 } blank
    && blank.ChildElements.Count == 0
    && blank.GetAttributes() is [{ LocalName: "val", NamespaceUri: "", Value: "1" or "0" or "true" or "false" }];

string[] files = Directory.GetFiles(paths[0], "*.xlsx")
    .Concat(Directory.GetFiles(paths[0], "*.docx"))
    .Where(f => !Path.GetFileName(f).StartsWith("~$", StringComparison.Ordinal))
    .ToArray();
Array.Sort(files, StringComparer.Ordinal);
if (files.Length == 0)
{
    Console.Error.WriteLine($"No .xlsx or .docx files in {paths[0]}.");
    return 2;
}

var validator = new OpenXmlValidator(FileFormatVersions.Microsoft365);
int total = 0;
foreach (string file in files)
{
    string name = Path.GetFileName(file);
    List<string> errors;
    try
    {
        using OpenXmlPackage document = file.EndsWith(".docx", StringComparison.Ordinal)
            ? WordprocessingDocument.Open(file, false)
            : SpreadsheetDocument.Open(file, false);
        errors = validator
            .Validate(document)
            .Where(e => !(libreOfficeResave && (IsLibreOfficeRowOnOffTrue(e) || IsLibreOfficeChartStyle(e))))
            .Where(e => !IsExcelDataDisplayOptions(e))
            .Select(e => $"{e.ErrorType} {e.Id} in {e.Part?.Uri} at {e.Path?.XPath}: {e.Description}")
            .ToList();
    }
    catch (Exception e) when (e is OpenXmlPackageException or InvalidDataException or System.Xml.XmlException)
    {
        errors = [$"cannot open the package: {e.Message}"];
    }

    total += errors.Count;
    Console.WriteLine(errors.Count == 0 ? $"ok    {name}" : $"FAIL  {name} ({errors.Count} error(s))");
    foreach (string error in errors)
    {
        Console.WriteLine($"      {error}");
    }
}

Console.WriteLine(total == 0
    ? $"{files.Length} file(s), no errors."
    : $"{files.Length} file(s), {total} error(s).");
return total == 0 ? 0 : 1;
