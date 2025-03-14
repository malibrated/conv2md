# Converting Legacy .doc Files with textutil and MarkItDown

This document explains the process used by conv2md to convert legacy Microsoft Word (.doc) files to Markdown format.

## Overview

Legacy .doc files (Word 97-2003 format) are not directly supported by MarkItDown. To handle these files, conv2md uses a two-step conversion process:

1. First, macOS's built-in `textutil` command is used to convert the .doc file to .docx format
2. Then, MarkItDown is used to convert the resulting .docx file to Markdown

This approach provides better compatibility and more reliable conversion results than attempting to convert .doc files directly.

## macOS-Specific Limitation

**Important**: The .doc to .docx conversion using `textutil` is only available on macOS systems. This is because `textutil` is a macOS-specific command-line utility that comes pre-installed with the operating system.

If you are running conv2md on Linux or Windows:
- .doc files will not be converted automatically
- You will need to manually convert .doc files to .docx format before processing
- The script will detect non-macOS systems and provide a warning about this limitation

## The Conversion Process in Detail

### Step 1: .doc to .docx Conversion

The script uses macOS's built-in `textutil` command to convert the .doc file to .docx format:

```bash
textutil -convert docx "$input_file" -output "$temp_docx"
```

This command:
- Takes the original .doc file as input
- Converts it to .docx format
- Saves the result to a temporary file

The `textutil` command is a powerful document conversion utility that comes pre-installed on macOS. It provides high-quality conversion between various document formats, including .doc, .docx, .rtf, .html, and more.

### Step 2: .docx to Markdown Conversion

Once the .doc file has been converted to .docx format, the script uses MarkItDown to convert it to Markdown:

```bash
markitdown "$temp_docx" -o "$output_file"
```

This command:
- Takes the temporary .docx file as input
- Converts it to Markdown format
- Saves the result to the specified output file

### Error Handling

The script includes robust error handling at each step of the process:

1. If the `textutil` conversion fails, the script logs an error message and returns an error code
2. If MarkItDown is not installed or cannot be found, the script provides installation instructions
3. If the MarkItDown conversion fails, the script logs an error message and returns an error code
4. Timeouts are implemented to prevent the script from hanging if a conversion takes too long

### Temporary Files

The script creates a temporary directory to store the intermediate .docx file during the conversion process. This directory is automatically cleaned up after the conversion is complete, regardless of whether the conversion succeeded or failed.

## Requirements

- **macOS**: The `textutil` command is only available on macOS. This conversion method will not work on Linux or Windows.
- **MarkItDown**: Must be installed and available in the PATH.

## Limitations

- This conversion method is macOS-specific and will not work on other operating systems.
- Some complex formatting in legacy .doc files may not be preserved perfectly through the conversion process.
- Very large or complex .doc files may take longer to convert or may encounter issues during conversion.

## Troubleshooting

If you encounter issues with .doc conversion:

1. **Check if the file is corrupted**: Try opening the .doc file in Microsoft Word or LibreOffice to ensure it's not corrupted.
2. **Manual conversion**: If automatic conversion fails, try manually converting the .doc file to .docx using Microsoft Word or LibreOffice, then run conv2md on the resulting .docx file.
3. **Check for password protection**: Ensure the document is not password-protected.
4. **Enable debug logging**: Run conv2md with the `-d` or `--verbose-debug` option to see more detailed error messages.

## Alternative Approaches for Non-macOS Systems

If you're not using macOS, consider these alternatives for converting .doc files:

1. **Manual pre-conversion**: Convert .doc files to .docx manually before running conv2md.
2. **LibreOffice**: On Linux or Windows, you can use LibreOffice for the conversion:
   ```bash
   soffice --headless --convert-to docx:"Office Open XML Text" --outdir "$temp_dir" "$input_file"
   ```
3. **Pandoc**: Another alternative is to use Pandoc for direct conversion from .doc to Markdown, though results may vary:
   ```bash
   pandoc -f doc -t markdown "$input_file" -o "$output_file"
   ```
4. **Microsoft Word Automation**: On Windows, you could use PowerShell to automate Microsoft Word for conversion:
   ```powershell
   $word = New-Object -ComObject Word.Application
   $doc = $word.Documents.Open("$input_file")
   $doc.SaveAs("$output_file", 16) # 16 is the format code for .docx
   $doc.Close()
   $word.Quit()
   ```

## Implementation Details

The implementation of this conversion process can be found in the `convert_doc_with_textutil` function in the `converters.sh` file. The function includes platform detection to ensure it only attempts to use textutil on macOS systems. 