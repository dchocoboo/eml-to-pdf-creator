property repoPath : "/Users/david/git/eml-to-pdf-creator"
property pythonPath : "/opt/homebrew/opt/python@3.14/bin/python3.14"
property notesFolderName : "Purchases"

on run {input, parameters}
    if input is {} then
        tell application "Mail"
            set input to selection
        end tell
    end if

    if input is {} then
        display alert "No Mail messages selected" message "Select one or more messages in Apple Mail, then run this Quick Action again."
        return input
    end if

    set inputDir to repoPath & "/input"
    set outputDir to repoPath & "/output"
    do shell script "mkdir -p " & quoted form of inputDir & " " & quoted form of outputDir

    repeat with mailMessage in input
        tell application "Mail"
            set messageSubject to subject of mailMessage
            set messageSender to sender of mailMessage
            set messageDate to date received of mailMessage
            set messageSource to source of mailMessage
            try
                set messageId to message id of mailMessage
            on error
                set messageId to ""
            end try
        end tell

        set fileBase to my uniqueFileBase(messageDate, messageSubject, messageId)
        set emlPath to inputDir & "/" & fileBase & ".eml"
        set pdfPath to outputDir & "/" & fileBase & ".pdf"

        my writeTextFile(messageSource, emlPath)

        do shell script quoted form of pythonPath & " " & quoted form of (repoPath & "/eml_to_image.py") & " " & quoted form of emlPath & " -o " & quoted form of outputDir

        my createPurchaseNote(messageSubject, messageSender, messageDate, pdfPath)
    end repeat

    display notification "Converted " & (count of input) & " Mail message(s) to Apple Notes" with title "Mail to Notes"
    return input
end run

on createPurchaseNote(messageSubject, messageSender, messageDate, pdfPath)
    set noteTitle to "Purchase - " & messageSubject
    set pdfUrl to "file://" & my replaceText(pdfPath, " ", "%20")
    set noteBody to "<html><body>" & ¬
        "<h1>" & my escapeHtml(messageSubject) & "</h1>" & ¬
        "<p><strong>From:</strong> " & my escapeHtml(messageSender) & "</p>" & ¬
        "<p><strong>Date:</strong> " & my escapeHtml(messageDate as string) & "</p>" & ¬
        "<p><strong>PDF:</strong> <a href=\"" & pdfUrl & "\">" & my escapeHtml(pdfPath) & "</a></p>" & ¬
        "</body></html>"

    tell application "Notes"
        if not (exists folder notesFolderName of default account) then
            make new folder at default account with properties {name:notesFolderName}
        end if

        set targetFolder to folder notesFolderName of default account
        set newNote to make new note at targetFolder with properties {name:noteTitle, body:noteBody}

        try
            set pdfAlias to POSIX file pdfPath as alias
            make new attachment at end of attachments of newNote with data pdfAlias
        end try
    end tell
end createPurchaseNote

on uniqueFileBase(messageDate, messageSubject, messageId)
    set dateStamp to my formatDateStamp(messageDate)

    if messageId is not "" then
        set idPart to do shell script "printf %s " & quoted form of messageId & " | shasum -a 1 | cut -c 1-10"
    else
        set idPart to do shell script "uuidgen | tr '[:upper:]' '[:lower:]' | cut -c 1-10"
    end if

    return dateStamp & "-" & idPart & "-" & my cleanFileName(messageSubject)
end uniqueFileBase

on formatDateStamp(theDate)
    set dateYear to year of theDate as string
    set dateMonth to my twoDigits(month of theDate as integer)
    set dateDay to my twoDigits(day of theDate)
    set dateHour to my twoDigits(hours of theDate)
    set dateMinute to my twoDigits(minutes of theDate)
    set dateSecond to my twoDigits(seconds of theDate)
    return dateYear & dateMonth & dateDay & "-" & dateHour & dateMinute & dateSecond
end formatDateStamp

on twoDigits(theNumber)
    set numberText to theNumber as string
    if theNumber < 10 then set numberText to "0" & numberText
    return numberText
end twoDigits

on writeTextFile(fileText, posixPath)
    set fileRef to open for access POSIX file posixPath with write permission
    try
        set eof of fileRef to 0
        write fileText to fileRef as «class utf8»
        close access fileRef
    on error errMessage
        try
            close access fileRef
        end try
        error errMessage
    end try
end writeTextFile

on cleanFileName(fileName)
    set cleanedName to fileName as string
    set badChars to {":", "/", "\\", "*", "?", "\"", "<", ">", "|", return, linefeed, tab}
    repeat with badChar in badChars
        set cleanedName to my replaceText(cleanedName, badChar as string, "-")
    end repeat
    set cleanedName to do shell script "printf %s " & quoted form of cleanedName & " | tr -s ' ' '-' | tr -s '-' '-' | cut -c 1-80"
    if cleanedName is "" then set cleanedName to "mail-message"
    return cleanedName
end cleanFileName

on escapeHtml(theText)
    set escapedText to theText as string
    set escapedText to my replaceText(escapedText, "&", "&amp;")
    set escapedText to my replaceText(escapedText, "<", "&lt;")
    set escapedText to my replaceText(escapedText, ">", "&gt;")
    set escapedText to my replaceText(escapedText, "\"", "&quot;")
    return escapedText
end escapeHtml

on replaceText(theText, searchString, replacementString)
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to searchString
    set textItems to text items of theText
    set AppleScript's text item delimiters to replacementString
    set replacedText to textItems as text
    set AppleScript's text item delimiters to oldDelimiters
    return replacedText
end replaceText
