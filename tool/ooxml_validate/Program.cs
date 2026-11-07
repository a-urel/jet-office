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
            .Where(e => !(libreOfficeResave && IsLibreOfficeRowOnOffTrue(e)))
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
