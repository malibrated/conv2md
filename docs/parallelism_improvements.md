# Parallelism Improvements in conv2md

This document outlines the parallelism improvements made to the `conv2md` script to enhance performance and efficiency when processing large numbers of documents.

## Overview

The script now processes all document types (Word, PowerPoint, and PDF) in parallel by default, which significantly improves conversion speed on multi-core systems. The parallelism implementation includes:

1. Intelligent worker allocation based on document type
2. Semaphore-based job control to prevent system overload
3. Stalled job detection and cleanup
4. Graceful handling of interruptions
5. Automatic fallback to sequential processing for small batches

## Parallelism Implementation Details

### Worker Allocation

The script dynamically allocates workers based on document type:

- **Word Documents**: Maximum of 4 parallel workers (or user-specified value if lower)
- **PowerPoint Documents**: Maximum of 4 parallel workers (or user-specified value if lower)
- **PDF Documents**: Uses the full number of workers specified by the user (default: 4)

This allocation strategy recognizes that different document types have different resource requirements and ensures system stability during conversion.

### Semaphore-Based Job Control

For each document type, the script:

1. Creates a dedicated semaphore directory to track active jobs
2. Limits the number of concurrent conversions based on the worker allocation
3. Waits for jobs to complete when the maximum number of workers is reached
4. Cleans up semaphore files when jobs complete

Example of semaphore implementation:
```bash
# Create a unique semaphore file for this process
local sem_file="${semaphore_dir}/$$.sem"
echo $$ > "$sem_file"

# Set up trap to ensure semaphore is removed on exit
trap 'rm -f "$sem_file" 2>/dev/null || true' EXIT INT TERM
```

### Stalled Job Detection

The script includes a mechanism to detect and clean up stalled jobs:

1. If jobs don't complete within a reasonable time (30 seconds), the script checks for stale semaphores
2. Semaphores without corresponding active processes are removed
3. This prevents the script from hanging indefinitely if a conversion process fails unexpectedly

### PDF Directory Processing

PDF files are processed using a directory-based approach:

1. The script finds all directories containing PDF files
2. Each directory is processed in parallel (limited to 2 concurrent directories)
3. Within each directory, PDF files are processed in parallel based on the worker allocation
4. This two-level parallelism maximizes throughput while maintaining system stability

### Smart Processing Decisions

The script makes intelligent decisions about when to use parallelism:

1. For very small batches (3 or fewer files), sequential processing is used to avoid overhead
2. If only 1 worker is specified, sequential processing is used
3. The script automatically adjusts worker counts based on system capabilities

## Benefits

The parallelism improvements provide several key benefits:

1. **Faster Processing**: Significantly reduced total conversion time, especially for large document collections
2. **Better Resource Utilization**: More efficient use of multi-core CPUs
3. **Improved Scalability**: Performance scales with the number of available CPU cores
4. **Robust Error Handling**: Failed conversions don't block the entire process
5. **System Stability**: Controlled resource usage prevents system overload

## Usage

To take advantage of the parallelism improvements, use the `-w` option to specify the maximum number of workers:

```bash
./conv2md.sh -i ~/Documents -o ~/Converted -w 8
```

For optimal performance:
- On systems with 4 cores: use `-w 4`
- On systems with 8 cores: use `-w 6` to `-w 8`
- On systems with 16+ cores: use `-w 8` to `-w 12`

## Limitations

While parallelism significantly improves performance, be aware of these limitations:

1. Memory usage increases with the number of parallel workers
2. Very large documents may benefit from sequential processing
3. Some document types (especially PDFs requiring OCR) are inherently CPU and memory intensive

## Conclusion

The parallelism improvements make `conv2md` significantly more efficient for processing large document collections. By intelligently allocating resources and implementing robust job control, the script maximizes throughput while maintaining system stability. 