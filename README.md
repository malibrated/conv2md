# Conv2MD

A powerful document conversion utility that transforms Word, PowerPoint, and PDF documents into Markdown format.

## Features

- Convert multiple document types to Markdown:
  - Word documents (.doc, .docx)
  - PowerPoint presentations (.ppt, .pptx)
  - PDF documents (.pdf)
- Batch processing with parallel execution for improved performance
- Checkpoint system to resume interrupted conversions
- Intelligent handling of PDF conversions with OCR capabilities
- Preserves document structure and images
- Comprehensive logging system

## Requirements

- Bash 5.2.37 or higher
- SQLite (optional, but recommended for improved checkpoint performance)
- MarkItDown (primary conversion tool)
- marker_single (for PDF OCR processing)
- pandoc (for Word document conversion)
- GNU Parallel (optional, for improved PDF processing)

## Installation

1. Clone this repository or download the source code:
   ```bash
   git clone https://github.com/malibrated/conv2md.git
   ```

2. Make the main script executable:
   ```bash
   chmod +x conv2md.sh
   ```

3. Ensure dependencies are installed:
   ```bash
   # Install Homebrew if not already installed
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   
   # Install required dependencies
   brew install bash sqlite pandoc parallel
   
   # Install MarkItDown
   pip install 'markitdown[all]~=0.1.0a1'
   
   # Install marker for PDF OCR
   # Follow instructions at https://github.com/VikParuchuri/marker
   ```

## Usage

```bash
./conv2md.sh -i <input_dir> -o <output_dir> [options]
```

### Options

- `-i, --input <dir>`: Input directory containing documents to convert
- `-o, --output <dir>`: Output directory for converted Markdown files
- `-w, --workers <num>`: Maximum number of parallel workers (default: auto-detected)
- `-m, --memory-limit <mb>`: Memory limit per process in MB (default: 4096)
- `--force`: Force conversion of already converted files
- `--resume`: Resume from checkpoint (skip already converted files)
- `--skip-word`: Skip Word document conversion
- `--skip-powerpoint`: Skip PowerPoint document conversion
- `--skip-pdf`: Skip PDF document conversion
- `-d, --debug`: Enable debug logging

### Examples

```bash
# Basic conversion
./conv2md.sh -i ~/Documents/MyDocs -o ~/Documents/MyDocs_markdown

# Skip PDF conversion
./conv2md.sh -i ~/Documents/MyDocs -o ~/Documents/MyDocs_markdown --skip-pdf

# Limit workers and memory
./conv2md.sh -i ~/Documents/MyDocs -o ~/Documents/MyDocs_markdown -w 2 -m 2048

# Resume an interrupted conversion
./conv2md.sh -i ~/Documents/MyDocs -o ~/Documents/MyDocs_markdown --resume
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [MarkItDown](https://github.com/microsoft/markitdown) for document conversion
- [marker](https://github.com/VikParuchuri/marker) for PDF OCR processing
- [pandoc](https://pandoc.org/) for document format conversion

## Features

- Converts multiple document types to Markdown:
  - Word documents (.docx)
  - Legacy Word documents (.doc) using textutil + MarkItDown conversion
  - PowerPoint presentations (.ppt, .pptx)
  - PDF documents (with text extraction or OCR)
  - Images, web documents, spreadsheets, and many other formats
- Preserves directory structure in the output
- Parallel processing for improved performance
- Robust error handling and logging
- Simplified progress logging
- Resume capability for interrupted conversions
- Force OCR option for all PDF files (--force-pdf-ocr)
- Recursive directory traversal for processing all files
- Intelligent fallback mechanisms for conversion failures
- Advanced resource management with memory monitoring
- Automatic output directory organization
- Batch processing to prevent system overload
- Signal handling for graceful shutdown
- **NEW: Performance optimizations for faster processing**
  - Timestamp-based file finding to skip unchanged files
  - Adaptive batch sizing based on processing time
  - RAM disk support for temporary files
  - File sorting by size for efficient processing
  - Batch checkpoint updates to reduce I/O operations

## Requirements

- **Bash 5.2.37 or higher** (the script will check your Bash version and exit if it's too old)
- **MarkItDown**: For general document conversion (including Word, PowerPoint, and many other formats)
- **marker/marker_single**: For PDF OCR conversion
- **pdftotext**: For extracting text from PDFs (part of poppler-utils)
- **GNU Parallel** (optional): For improved performance when processing multiple files
- **pandoc**: For Word document conversion when MarkItDown is not available
- **textutil** (macOS only): Required for converting legacy .doc files to .docx format
- Standard Unix utilities (awk, find, grep, etc.)

## Installation

1. Clone this repository or download the source code
2. Make the main script executable:

```bash
chmod +x conv2md.sh
```

### Installing Dependencies

#### MarkItDown

For most document conversions (Word, PowerPoint, and other formats):

```bash
pip install 'markitdown[all]~=0.1.0a1'
```

See [MarkItDown GitHub Repository](https://github.com/microsoft/markitdown) for more details.

#### Marker

For PDF conversion with OCR:

```bash
pip install marker-pdf
```

See [MARKER GitHub Repository](https://github.com/VikParuchuri/marker) for more details.

#### Other Dependencies

```bash
# On macOS with Homebrew
brew install poppler  # For pdftotext
brew install parallel # For GNU Parallel
brew install pandoc   # For Word document conversion when MarkItDown is not available
```

## Usage

```bash
./conv2md.sh -i <input_dir> [-o <output_dir>] [options]
```

If no output directory is specified, the script will create one at the same level as the input directory with "_md" appended to the input directory name.

### Command Line Options

| Option | Description |
|--------|-------------|
| `-i, --input <dir>` | Input directory containing documents to convert (required) |
| `-o, --output <dir>` | Output directory for converted Markdown files (default: `<input_dir>_md`) |
| `-w, --workers <num>` | Maximum number of parallel workers (default: auto-detected based on CPU cores) |
| `-l, --log <dir>` | Directory for log files (default: `<output_dir>/.logs`) |
| `-t, --temp <dir>` | Directory for temporary files (default: `/tmp/conv2md_<timestamp>`) |
| `-f, --force` | Force conversion even if output file exists |
| `-r, --resume` | Resume from checkpoint (continue interrupted conversion) |
| `-d, --debug` | Enable debug logging |
| `--verbose-debug` | Enable verbose debug logging |
| `--skip-word` | Skip Word document conversion |
| `--skip-powerpoint` | Skip PowerPoint presentation conversion |
| `--skip-pdf` | Skip PDF document conversion |
| `--skip-checks` | Skip dependency checks |
| `--force-pdf-ocr` | Force OCR for all PDFs (even those with embedded text) |
| `--no-fallback` | Disable fallback to marker_single if MarkItDown fails |
| `--max-file-size <size>` | Maximum file size in MB (0 = no limit, default: 0) |
| `--memory-monitor` | Enable per-process memory monitoring |
| `--memory-limit <mb>` | Maximum memory per process in MB (default: 4096) |
| `--batch-size <size>` | Number of files to process in each batch (default: 5) |
| `--resource-check-interval <s>` | Seconds between resource checks (default: 30) |
| `--disable-throttling` | Disable automatic throttling based on system resources |
| `--conservative-resources` | Enable conservative resource usage mode |
| `--ultra-conservative` | Enable ultra-conservative mode for limited systems |
| `-v, --version` | Display version information |
| `-h, --help` | Display help information |

### Examples

```bash
# Basic usage
./conv2md.sh -i ~/Documents

# Skip PDF conversion
./conv2md.sh -i ./docs -o ./markdown --skip-pdf

# Resume an interrupted conversion
./conv2md.sh -i ./sources -o ./output -r

# Optimize for PDF conversion with maximum workers
./conv2md.sh -i ./docs -w 8

# Process a very large directory with many files
./conv2md.sh -i ./large-dir -w 2

# Skip files larger than 10MB
./conv2md.sh -i ./docs --max-file-size 10

# Force OCR for all PDFs
./conv2md.sh -i ./docs --force-pdf-ocr

# Enable debug mode
./conv2md.sh -i ./docs -d

# Use conservative resource mode for limited systems
./conv2md.sh -i ./docs --conservative-resources

# Enable memory monitoring with custom limit
./conv2md.sh -i ./docs --memory-monitor --memory-limit 2048
```

## Performance Optimizations

The script includes several optimizations to improve performance while maintaining the ability to skip already-converted files:

### Timestamp-Based File Finding

- The script creates a timestamp file to track when it was last run
- When running again, it only processes files that are newer than the last run
- This significantly reduces the time spent scanning for files that don't need conversion

### Adaptive Batch Sizing

- The script dynamically adjusts batch size based on processing time
- If batches take too long, the size is reduced to prevent resource exhaustion
- If batches complete quickly, the size is increased to improve throughput
- This ensures optimal resource usage across different file types and system capabilities

### RAM Disk for Temporary Files

- On supported systems, the script can create a RAM disk for temporary files
- This significantly reduces disk I/O for temporary files
- Particularly helpful for PDF processing which can be I/O intensive
- The script automatically detects if there's enough memory available

### File Sorting by Size

- Files are sorted by size (smallest first) before processing
- This allows smaller files to be processed first, completing more files quickly
- Improves perceived performance and user experience
- Helps prevent resource exhaustion by distributing large files across batches

### Batch Checkpoint Updates

- Instead of writing to the checkpoint file after each successful conversion
- The script batches checkpoint updates to reduce I/O operations
- This improves performance, especially when processing many small files

## Directory Structure

The script creates a mirrored directory structure in the output directory, preserving the exact hierarchy of your input files:

```
Input Directory:
/path/to/input/
├── folder1/
│   ├── document1.pdf
│   └── document2.docx
└── folder2/
    └── presentation.pptx

Output Directory:
/path/to/output/input/  # Note: Creates a subdirectory with input directory name
├── logs/                  # Log files directory
│   ├── output.log         # Standard output log
│   ├── error.log          # Error messages
│   ├── debug.log          # Debug information
│   ├── conversion.log     # Detailed conversion info
│   └── checkpoint.txt     # For resuming conversions
├── folder1/
│   ├── document1.md
│   └── document2.md
└── folder2/
    └── presentation.md
```

The script handles relative paths carefully to ensure that the output directory structure exactly mirrors the input structure, even for deeply nested directories. It now creates a subdirectory in the output directory with the same name as the input directory, making it easier to organize multiple conversion jobs.

## Project Structure

```
conv2md/
├── conv2md.sh          # Main script
├── lib/
│   ├── converters.sh   # Document conversion functions
│   ├── file_ops.sh     # File operations
│   ├── logging.sh      # Logging functions
│   ├── progress.sh     # Simplified progress logging
│   ├── system.sh       # System monitoring
│   ├── config.sh       # Configuration settings
│   └── utils.sh        # Utility functions
├── logs/               # Log files directory
└── README.md           # This file
```

## Conversion Process

### PDF Conversion

1. The script first checks if the PDF has embedded text using `pdftotext`
2. If text is found, it attempts conversion with MarkItDown
3. If MarkItDown fails or the PDF has no text, it falls back to marker_single with OCR (unless `--no-fallback` is specified)
4. If `--force-pdf-ocr` is specified, it always uses marker_single with OCR
5. The script creates the appropriate output directory structure to mirror the input

The PDF conversion process includes:
- Intelligent text detection to determine the best conversion method
- Robust error handling with detailed logging
- Timeout protection to prevent hanging on problematic files
- Proper cleanup of temporary files and resources
- Memory monitoring to prevent excessive resource usage

### Word Document Conversion

1. For .docx files, the script uses MarkItDown for direct conversion to Markdown
2. For legacy .doc files:
   - On macOS: The script uses the built-in `textutil` command to convert .doc to .docx, then uses MarkItDown
   - On Linux/Windows: .doc conversion is not supported directly. Users must manually convert .doc files to .docx format before processing
3. The conversion preserves most formatting, including:
   - Headings and text styles
   - Lists and tables
   - Images and diagrams
   - Links and references

### PowerPoint Conversion

PowerPoint presentations (.ppt and .pptx) are converted using MarkItDown.

- Each slide is converted to a Markdown section
- Images and text are preserved
- Formatting is maintained as much as possible

### Other File Types

The script supports conversion of many other file types using MarkItDown:
- Spreadsheets (.xls, .xlsx, .csv)
- Images (.jpg, .jpeg, .png, .gif, .bmp, .tiff, .tif, .webp)
- Web documents (.html, .htm, .xml, .json)
- MHTML files (.mhtml, .mht)
- Archives (.zip)
- Audio files (.mp3, .wav, .ogg, .flac, .aac, .m4a)
- Video files (.mp4, .avi, .mov, .wmv, .mkv, .flv, .webm)
- Text documents (.txt, .md, .markdown, .rst, .rtf)
- Code files (.py, .js, .java, .c, .cpp, etc.)

For image files, the script creates a Markdown file with:
- An embedded image reference
- File metadata (dimensions, size, type)
- A standardized format for easy viewing

## Log Files

The script creates several log files in the log directory:

- `output.log`: Standard output log
- `error.log`: Error messages
- `debug.log`: Debug information (if debug mode is enabled)
- `conversion.log`: Detailed conversion information
- `checkpoint.txt`: Checkpoint file for resuming interrupted conversions

Log files are automatically rotated when they reach a certain size (10MB by default) to prevent them from growing too large.

## Advanced Features

### Parallel Processing

The script uses parallel processing to improve performance when converting multiple files:
- The number of parallel workers can be adjusted with the `-w, --workers` option
- The script automatically detects the optimal number of workers based on your CPU cores
- Different file types use different worker limits to optimize resource usage

### Resource Management

The script includes advanced resource management features:

- **Memory Monitoring**: Tracks memory usage of conversion processes and terminates them if they exceed limits
- **Batch Processing**: Processes files in smaller batches to prevent system overload
- **Dynamic Worker Adjustment**: Adjusts the number of parallel workers based on system load
- **Resource Modes**:
  - **Standard**: Balances performance and resource usage
  - **Conservative**: Reduces resource usage for systems with limited resources
  - **Ultra-Conservative**: Minimizes resource usage for very limited systems

### Signal Handling

The script implements proper signal handling for graceful shutdown:

- Catches interruption signals (Ctrl+C) and performs proper cleanup
- Ensures all temporary files are removed
- Terminates any running background processes
- Rotates log files before exiting

### Automatic Output Organization

The script now creates a subdirectory in the output directory with the same name as the input directory:

- Makes it easier to organize multiple conversion jobs
- Prevents file conflicts when converting multiple input directories
- Maintains a clean and organized output structure

## Troubleshooting

### Common Issues

1. **Script fails with "command not found" error**:
   - Ensure the script has execute permissions: `chmod +x conv2md.sh`
   - Check your Bash version: `bash --version` (must be 5.2.37 or higher)

2. **Conversion fails for specific file types**:
   - Check if required dependencies are installed
   - Enable debug mode (`-d`) to see detailed error messages
   - Check the error log file for specific errors

3. **Script runs out of memory**:
   - Reduce the number of parallel workers: `-w 2`
   - Enable conservative resource mode: `--conservative-resources`
   - Set a lower memory limit: `--memory-limit 2048`

4. **Conversion is too slow**:
   - Increase the number of parallel workers (if your system has enough resources)
   - Skip file types you don't need (e.g., `--skip-pdf`)
   - Process smaller batches of files at a time

### Getting Help

If you encounter issues not covered in this documentation:

1. Check the log files for detailed error messages
2. Enable debug mode (`-d`) to get more information
3. Report issues with detailed information about your system and the specific error
