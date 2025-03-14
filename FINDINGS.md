# Conv2md Implementation Review Findings

This document provides a detailed analysis of the discrepancies between the documented features in README.md and the actual implementation in the conv2md script.

## 1. Bash Version Requirement Mismatch

**README Statement:**
```
Requirements:
- Bash 5.2.37 or higher (explicitly installed via Homebrew at /opt/homebrew/bin/bash)
```

**Actual Implementation:**
The script uses a hardcoded path in the shebang:
```bash
#!/opt/homebrew/bin/bash
```

However, it doesn't perform any version checking to ensure the Bash version meets the requirements. This could lead to compatibility issues if users have an older version of Bash.

## 2. PowerPoint Conversion Implementation

**README Statement:**
```
- pptx2md: For PowerPoint conversion
```

**Actual Implementation:**
The script checks for pptx2md in the dependency check:
```bash
# Check for pptx2md (used for PowerPoint conversion)
if [[ "$skip_powerpoint" != "true" ]]; then
  if ! command -v pptx2md &>/dev/null; then
    log_warning "pptx2md command not found. PowerPoint conversion will be skipped."
    log_warning "Please install pptx2md: pip install pptx2md"
    skip_powerpoint=true
  fi
fi
```

But the actual conversion uses MarkItDown instead:
```bash
# Presentation formats
ppt|pptx)
  log_info "Converting PowerPoint presentation: $file"
  convert_with_markitdown "$file" "$output_path" "PowerPoint presentation"
  conversion_status=$?
  ;;
```

This inconsistency could confuse users who install pptx2md as instructed but find it's not actually being used.

## 3. Word Document Conversion (.doc files)

**README Statement:**
```
- Legacy Word documents (.doc) using textutil + MarkItDown conversion
```

**Actual Implementation:**
The script uses textutil for .doc conversion, which is macOS-specific:
```bash
# First convert .doc to .docx using textutil
log_debug "Converting .doc to .docx using textutil: $input_file -> $temp_docx"
textutil -convert docx "$input_file" -output "$temp_docx" 2>"${temp_dir}/textutil_error.log"
```

However, the README doesn't clearly state that textutil is macOS-specific, which could cause issues for users on other platforms.

## 4. Marker/marker_single Usage

**README Statement:**
```
- marker/marker_single: For PDF OCR conversion
```

**Actual Implementation:**
The script checks for "marker" command:
```bash
# Check for marker command (used for PDF conversion)
local marker_found=false
if command -v "marker" &>/dev/null; then
  marker_found=true
fi
```

But the README mentions both "marker" and "marker_single". The actual OCR conversion should be using marker_single specifically, but the implementation is inconsistent.

## 5. Timeout Protection

**README Statement:**
```
- Timeout protection to prevent hanging on problematic files
```

**Actual Implementation:**
The script defines timeout constants:
```bash
# Timeout values in seconds
WORD_TIMEOUT=900       # 15 minutes
POWERPOINT_TIMEOUT=900 # 15 minutes
PDF_TIMEOUT=2700       # 45 minutes
```

But in many places, hardcoded timeout values are used instead:
```bash
# Set timeout for conversion (5 minutes)
local timeout_cmd=""
if command -v timeout &>/dev/null; then
  timeout_cmd="timeout 300"
elif command -v gtimeout &>/dev/null; then
  timeout_cmd="gtimeout 300"
fi
```

This inconsistency means the defined timeout constants aren't being used effectively.

## 6. Log Rotation

**README Statement:**
```
Log files are automatically rotated when they reach a certain size (10MB by default) to prevent them from growing too large.
```

**Actual Implementation:**
The script defines a log_max_size variable:
```bash
# Used by logging.sh for log rotation
export log_max_size=10240  # 10MB in KB
```

But log rotation isn't consistently implemented across all log files, and there's no mechanism to limit the number of rotated logs.

## 7. Maximum File Size Handling

**README Statement:**
```
--max-file-size <MB>: Maximum file size to process in MB (0 = no limit)
```

**Actual Implementation:**
The file size check uses platform-specific stat commands:
```bash
# Get file size in MB (divide by 1048576)
local file_size_bytes=$(stat -f %z "$input_file" 2>/dev/null || stat --format=%s "$input_file" 2>/dev/null)
```

This approach may not work consistently across all platforms, and there's no robust fallback mechanism.

## 8. Title File Support for PowerPoint

**README Statement:**
```
--title-file <file>: File containing titles for PowerPoint slides
```

**Actual Implementation:**
The script accepts the --title-file parameter:
```bash
--title-file)
  title_file="$2"
  shift 2
  ;;
```

But there's no clear implementation of how this file is used in the PowerPoint conversion process, especially since the conversion now uses MarkItDown instead of pptx2md.

## 9. Batch Size Limitation

**README Statement:**
```
-b, --batch-size <num>: Batch size for PDF processing (default: 20, max: 100)
```

**Actual Implementation:**
The script accepts and validates the batch_size parameter:
```bash
-b|--batch-size)
  batch_size="$2"
  # Validate batch size
  if ! [[ "$batch_size" =~ ^[0-9]+$ ]] || [[ "$batch_size" -lt 1 ]]; then
    log_warning "Invalid batch size: $batch_size. Using default value: 20"
    batch_size=20
  fi
  # Limit batch_size to a reasonable value
  if [[ "$batch_size" -gt 100 ]]; then
    log_warning "Batch size too large: $batch_size. Limiting to 100"
    batch_size=100
  fi
  shift 2
  ;;
```

However, it's not clear how this batch_size affects the actual PDF processing, especially since GNU Parallel is used for parallelization.

## 10. Directory Structure Preservation

**README Statement:**
```
The script creates a mirrored directory structure in the output directory, preserving the exact hierarchy of your input files.
```

**Actual Implementation:**
There are inconsistencies in how relative paths are calculated across different conversion functions:
```bash
# In one function:
if [[ "$input_file" == "$input_dir"* ]]; then
  # Remove input_dir prefix to get relative path
  rel_path="${input_file#$input_dir}"
  # Remove leading slash if present
  rel_path="${rel_path#/}"
  # Get the directory part of the relative path
  rel_path=$(dirname "$rel_path")
}

# In another function:
if [[ "$rel_path" == "$input_dir"* ]]; then
  # Remove input_dir prefix to get relative path
  rel_path="${rel_path#$input_dir}"
  # Remove leading slash if present
  rel_path="${rel_path#/}"
}
```

These inconsistencies could lead to problems with directory structure preservation.

## 11. Progress Display

**README Statement:**
```
- Progress tracking with detailed statistics
```

**Actual Implementation:**
The progress display implementation has issues with terminal detection and formatting:
```bash
# Check if we're in a terminal
local in_terminal=false
if [[ -t 1 ]] || [[ -t 2 ]]; then
  in_terminal=true
  echo "DEBUG: Running in an interactive terminal" >> "${log_dir}/debug.log"
else
  echo "DEBUG: Not running in an interactive terminal" >> "${log_dir}/debug.log"
fi
```

The progress display code is complex and has potential issues with different terminal types and environments.

## Conclusion

These findings highlight the areas where the conv2md script implementation doesn't fully match the documented features in README.md. Addressing these issues will improve the script's reliability, usability, and consistency with its documentation. 