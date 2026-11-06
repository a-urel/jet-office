-- Reads Excel for Mac's automatic value axis of every chart of the axis oracle
-- workbook and writes a CSV (test/fixtures/owner/axis/README.md).
--
--   osascript run_excel.applescript <workbook> <csv>
--
-- Paths are POSIX, absolute or relative to the current folder. The workbook
-- opens read-only and closes without saving. A chart Excel cannot answer for
-- gets no row: the rest are still written, and the script then stops with the
-- failures named and exit code 1. Numbers use "." whatever the system's decimal
-- separator; the CSV is UTF-8 with LF line ends.

on run argv
	if (count of argv) is not 2 then error "usage: osascript run_excel.applescript <workbook> <csv>" number 2
	set workbookPath to my absolutePath(item 1 of argv)
	set csvPath to my absolutePath(item 2 of argv)
	set csvRows to {"case,height,font,min,max,major"}
	set failures to {}
	set unseen to {}
	tell application "Microsoft Excel"
		activate
		-- Excel may wait for its file access prompt, so allow the owner time.
		set theBook to missing value
		with timeout of 600 seconds
			try
				set theBook to open workbook workbook file name workbookPath read only true
			end try
			if theBook is missing value then set theBook to open workbook workbook file name (my hfsPath(workbookPath)) read only true
		end timeout
		if theBook is missing value then set theBook to active workbook
		if name of theBook is not my baseName(workbookPath) then error "Excel did not open " & workbookPath number 1
		repeat with sheetIndex from 1 to (count of worksheets of theBook)
			set place to "sheet " & sheetIndex
			try
				set theSheet to worksheet sheetIndex of theBook
				set place to name of theSheet
				-- Excel may lay a chart out only when its sheet is shown.
				try
					activate object theSheet
				end try
				set chartCount to count of chart objects of theSheet
			on error errorText number errorNumber
				set end of failures to place & ": " & errorText & " (" & errorNumber & ")"
				set chartCount to 0
			end try
			repeat with chartIndex from 1 to chartCount
				set caseId to place & " chart " & chartIndex
				try
					set theObject to chart object chartIndex of theSheet
					set caseId to name of theObject
					-- The dictionary has no select for a chart object: goto scrolls
					-- its top left cell into view. A read works without it, so a
					-- failure here only goes in the summary.
					try
						goto reference (top left cell of theObject) with scroll
					on error
						set end of unseen to caseId
					end try
					set theAxis to get axis (chart of theObject) axis type value axis which axis primary axis
					set theHeight to height of theObject
					set theFont to font size of font object of tick labels of theAxis
					set theMin to minimum scale of theAxis
					set theMax to maximum scale of theAxis
					set theMajor to major unit of theAxis
					set end of csvRows to my csvRow(caseId, {theHeight, theFont, theMin, theMax, theMajor})
				on error errorText number errorNumber
					set end of failures to caseId & ": " & errorText & " (" & errorNumber & ")"
				end try
			end repeat
		end repeat
		try
			close theBook saving no
		on error errorText number errorNumber
			set end of failures to "closing the workbook: " & errorText & " (" & errorNumber & ")"
		end try
	end tell
	my writeUtf8(csvPath, my joined(csvRows, linefeed) & linefeed)
	set summary to (((count of csvRows) - 1) as text) & " rows written to " & csvPath
	if (count of unseen) > 0 then set summary to summary & linefeed & "not brought into view: " & my joined(unseen, ", ")
	if (count of failures) > 0 then
		error summary & linefeed & ((count of failures) as text) & " failed:" & linefeed & my joined(failures, linefeed) number 1
	end if
	return summary
end run

-- pure handlers: no Excel below this line

on absolutePath(thePath)
	if thePath starts with "/" then return thePath
	return (do shell script "pwd") & "/" & thePath
end absolutePath

on baseName(thePath)
	return last item of my pieces(thePath, "/")
end baseName

on hfsPath(thePath)
	return (POSIX file thePath) as text
end hfsPath

on csvRow(caseId, theValues)
	set fields to {caseId}
	repeat with theNumber in theValues
		set end of fields to my numberText(contents of theNumber)
	end repeat
	return my joined(fields, ",")
end csvRow

-- A real as text follows the system's decimal separator, and may be in
-- exponent form (1.0E-7), which the CSV's reader accepts.
on numberText(theNumber)
	if class of theNumber is not in {real, integer} then error "not a number: " & (theNumber as text)
	return my joined(my pieces(theNumber as text, ","), ".")
end numberText

on pieces(theText, separator)
	set saved to AppleScript's text item delimiters
	set AppleScript's text item delimiters to separator
	set result_ to text items of theText
	set AppleScript's text item delimiters to saved
	return result_
end pieces

on joined(theList, separator)
	set saved to AppleScript's text item delimiters
	set AppleScript's text item delimiters to separator
	set result_ to theList as text
	set AppleScript's text item delimiters to saved
	return result_
end joined

on writeUtf8(thePath, theText)
	set theFile to open for access (POSIX file thePath) with write permission
	try
		set eof of theFile to 0
		write theText to theFile as «class utf8»
	on error errorText number errorNumber
		close access theFile
		error errorText number errorNumber
	end try
	close access theFile
end writeUtf8
