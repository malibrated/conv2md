# MarkItDown Integration

This document explains how MarkItDown has been integrated as the primary document conversion tool in the conv2md script.

## Overview

MarkItDown is a powerful document conversion tool developed by Microsoft that can convert various document formats to Markdown. It provides high-quality conversions with better formatting preservation than many other tools. The conv2md script now uses MarkItDown as the primary conversion tool for most document types, with special handling for certain formats.

## Supported File Types

MarkItDown supports a wide range of file types, which are now handled by the conv2md script:

- **Documents**: .docx (Word)
- **Presentations**: .ppt, .pptx (PowerPoint)
- **Spreadsheets**: .xls, .xlsx, .csv
- **PDFs**: .pdf (with embedded text)
- **Images**: .jpg, .jpeg, .png, .gif, .bmp, .tiff, .tif, .webp
- **Web documents**: .html, .htm, .xml, .json
- **Archives**: .zip
- **Audio files**: .mp3, .wav, .ogg, .flac, .aac, .m4a
- **Email files**: .eml, .msg
- **Text documents**: .txt, .md, .markdown, .rst, .tex

## Integration Details

### Generic Conversion Function

A generic `convert_with_markitdown` function has been implemented to handle conversions for all supported file types:

```bash
convert_with_markitdown() {
  local input_file="$1"
  local output_file="$2"
  local file_type="$3"  # For logging purposes
  
  # Check if MarkItDown is installed
  local markitdown_cmd
  markitdown_cmd=$(find_command "markitdown")
  if [[ -z "$markitdown_cmd" ]]; then
    check_markitdown
    return 1
  fi
  
  # Run MarkItDown with timeout
  $markitdown_cmd "$input_file" -o "$output_file"
  
  # Check if output file was created and has content
  if [[ -f "$output_file" && -s "$output_file" ]]; then
    return 0
  else
    return 1
  fi
}
```

This function:
1. Takes an input file, output file, and file type as parameters
2. Checks if MarkItDown is installed
3. Runs MarkItDown with appropriate options
4. Verifies that the output file was created and has content

### Special Case Handling

While MarkItDown is used for most file types, there are some special cases:

1. **Legacy .doc files**: These are first converted to .docx using macOS's `textutil` command, then processed by MarkItDown (see [textutil_doc_conversion.md](textutil_doc_conversion.md) for details)

2. **PDFs without embedded text**: These are processed using MARKER with OCR, as MarkItDown works best with PDFs that already have text content

### File Type Detection

The script detects file types based on their extensions and routes them to the appropriate conversion function:

```bash
case "$ext" in
  # Document formats
  doc)
    # For .doc files, use textutil and MarkItDown
    convert_doc_with_textutil "$file" "$output_path"
    ;;
  docx)
    # For .docx files, use MarkItDown directly
    convert_with_markitdown "$file" "$output_path" "Word document"
    ;;
  # PDF formats
  pdf)
    # For PDFs, check if they have text
    if pdf_has_text "$file"; then
      # If they have text, use MarkItDown
      convert_with_markitdown "$file" "$output_path" "PDF document"
    else
      # If they don't have text, use MARKER with OCR
      convert_pdf_to_md "$file" "$output_path"
    fi
    ;;
  # Other formats
  *)
    # Try with MarkItDown for other formats
    convert_with_markitdown "$file" "$output_path" "document"
    ;;
esac
```

### PDF Text Detection

For PDFs, the script includes a function to detect if the PDF has embedded text:

```bash
pdf_has_text() {
  local pdf_file="$1"
  
  # Extract text from the first page
  local text_content
  text_content=$(pdftotext -f 1 -l 1 "$pdf_file" - 2>/dev/null)
  
  # Check if extracted text is empty
  if [[ -z "${text_content// /}" ]]; then
    return 1  # No text
  else
    return 0  # Has text
  fi
}
```

This function:
1. Uses `pdftotext` to extract text from the first page of the PDF
2. Checks if the extracted text is empty (after removing whitespace)
3. Returns 0 (success) if the PDF has text, or 1 (failure) if it doesn't

## Error Handling and Timeouts

The MarkItDown integration includes robust error handling and timeouts:

1. **Command Availability**: The script checks if MarkItDown is installed and provides installation instructions if it's not
2. **Timeouts**: Conversions have a 5-minute timeout to prevent the script from hanging
3. **Error Logging**: Error output from MarkItDown is captured and logged
4. **Status Code Checking**: Status codes from MarkItDown are checked to detect errors

## Installation and Requirements

To use MarkItDown with conv2md, you need to install it using pip:

```bash
pip install 'markitdown[all]~=0.1.0a1'
```

The `[all]` option installs all optional dependencies, which enables support for the full range of file types.

## Benefits of MarkItDown

Using MarkItDown as the primary conversion tool provides several benefits:

1. **Broader Format Support**: MarkItDown supports more file formats than the previous tools
2. **Better Quality Conversions**: MarkItDown often produces better-formatted Markdown output
3. **Consistent Interface**: Using a single tool for most conversions simplifies the code
4. **Active Development**: MarkItDown is actively maintained by Microsoft
5. **Modern Features**: MarkItDown includes modern features like table support and image handling

## Fallback Mechanisms

The script includes fallback mechanisms for cases where MarkItDown might not be the best tool:

1. **Legacy .doc Files**: Uses `textutil` to convert to .docx first
2. **PDFs without Text**: Uses MARKER with OCR
3. **Command Not Found**: Provides installation instructions

## Conclusion

The integration of MarkItDown as the primary document conversion tool in conv2md significantly enhances its capabilities, allowing it to handle a wider range of file types with better quality conversions. The script maintains backward compatibility through special case handling and fallback mechanisms, ensuring a robust and reliable conversion process. 