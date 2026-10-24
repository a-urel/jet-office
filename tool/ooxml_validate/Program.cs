// Validates every .xlsx file in a directory with the Open XML SDK.
//
//   dotnet run --project tool/ooxml_validate -- build/fixtures
//
// Each file is checked against the Microsoft 365 schemas
// (FileFormatVersions.Microsoft365). Every error is printed with its part and
// XPath. The exit code is 0 when no file has an error, 1 when any has, and 2
// for a usage error or a directory without .xlsx files. CI runs it on the
// fixtures tool/write_fixtures.dart writes (AGENTS.md, "Validation").
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;

if (args.Length != 1 || !Directory.Exists(args[0]))
{
    Console.Error.WriteLine("Usage: dotnet run --project tool/ooxml_validate -- <dir>");
    return 2;
}

string[] files = Directory.GetFiles(args[0], "*.xlsx");
Array.Sort(files, StringComparer.Ordinal);
if (files.Length == 0)
{
    Console.Error.WriteLine($"No .xlsx files in {args[0]}.");
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
        using SpreadsheetDocument document = SpreadsheetDocument.Open(file, false);
        errors = validator
            .Validate(document)
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
