# Recursive Document Processing in conv2md

## Overview

The `conv2md` script now uses a recursive directory traversal approach to process all compatible files in a directory structure. This approach simplifies the code and ensures that all files are processed in a consistent manner, while preserving the original directory structure in the output.

## How It Works

1. The script starts at the input directory and recursively traverses all subdirectories.
2. For each file encountered, it:
   - Determines the file type based on the extension
   - Creates the corresponding output directory structure
   - Converts the file to Markdown using the appropriate converter
   - Saves the Markdown file in the corresponding output directory

## Special Case Handling

### Legacy .doc Files

For legacy `.doc` files, the script uses a two-step conversion process:

1. First, macOS's built-in `textutil` command is used to convert the `.doc` file to `.docx` format
2. Then, MarkItDown is used to convert the `.docx` file to Markdown

### PDF Files

PDF files are processed based on whether they have extractable text:

1. If the `--force-pdf-ocr` option is specified, all PDFs are processed using Marker with OCR
2. Otherwise:
   - PDFs with extractable text are converted using MarkItDown
   - PDFs without extractable text are converted using Marker with OCR

## Directory Structure Preservation

The script preserves the original directory structure in the output. For example, if the input directory has the following structure:

```
input/
  ├── doc1.docx
  ├── subdir1/
  │   ├── doc2.pdf
  │   └── subdir2/
  │       └── doc3.pptx
  └── subdir3/
      └── doc4.doc
```

The output directory will have the following structure:

```
output/
  ├── doc1.md
  ├── subdir1/
  │   ├── doc2.md
  │   └── subdir2/
  │       └── doc3.md
  └── subdir3/
      └── doc4.md
```

## Implementation Details

The recursive processing is implemented in the `process_directory_recursive` function in `converters.sh`. This function:

1. Processes all files in the current directory
2. Recursively processes all subdirectories
3. Maintains the relative path information to preserve the directory structure

The main script calls this function through the `process_all_files` function, which sets up the initial processing.

## Benefits

- Simplified code structure
- Consistent processing of all file types
- Preservation of directory structure
- Improved error handling and logging
- Better support for mixed document types in the same directory

## Command Line Options

The script supports the following command line options related to recursive processing:

- `--force-pdf-ocr`: Force OCR for all PDF files, even those with embedded text
- `--force`: Force conversion even if output file exists
- `--resume`: Resume from last checkpoint

## Example Usage

```bash
# Process all files in the input directory, preserving directory structure
./conv2md.sh -i /path/to/input -o /path/to/output

# Process all files, forcing OCR for all PDFs
./conv2md.sh -i /path/to/input -o /path/to/output --force-pdf-ocr

# Process all files, forcing conversion even if output exists
./conv2md.sh -i /path/to/input -o /path/to/output --force
``` 