#!/usr/bin/env bash
#
# converters.sh - Document conversion functions
#
# This file contains functions for converting different document types to markdown

# Disable shellcheck warnings for variables defined in the main script
# shellcheck disable=SC2154
# Variables from main script: resume_from_checkpoint, checkpoint_file, log_dir, force_conversion

# Counter functions for progress tracking
increment_word_doc_count() {
  # Log the processing of a Word document
  log_debug "Processing Word document"
}

increment_powerpoint_count() {
  # Log the processing of a PowerPoint document
  log_debug "Processing PowerPoint document"
}

increment_pdf_count() {
  # Log the processing of a PDF document
  log_debug "Processing PDF document"
}

# Function to find a command in common locations
find_command() {
  local cmd="$1"
  local locations=(
    "/opt/homebrew/bin"
    "/usr/local/bin"
    "/usr/bin"
    "$HOME/.local/bin"
  )

  # First check if it's in PATH
  local cmd_path
  cmd_path=$(command -v "$cmd" 2>/dev/null)
  if [[ -n "$cmd_path" ]]; then
    log_debug "Found $cmd in PATH: $cmd_path"
    echo "$cmd_path"
    return 0
  fi

  # Then check common locations
  for location in "${locations[@]}"; do
    if [[ -x "$location/$cmd" ]]; then
      # Add location to PATH if found
      export PATH="$location:$PATH"
      log_debug "Added $location to PATH (found $cmd)"
      echo "$location/$cmd"
      return 0
    fi
  done

  # If not found, log debug message
  log_debug "Could not find $cmd in PATH or common locations"

  # Return empty string if not found
  echo ""
  return 1
}

# Function to check if MarkItDown is installed and provide installation instructions if not
check_markitdown() {
  local markitdown_cmd
  markitdown_cmd=$(find_command "markitdown")

  if [[ -z "$markitdown_cmd" ]]; then
    log_error "MarkItDown not found. Please install it using pip:"
    log_error "pip install 'markitdown[all]~=0.1.0a1'"
    log_error "For more information, visit: https://github.com/microsoft/markitdown"
    return 1
  fi

  log_debug "Found MarkItDown at: $markitdown_cmd"
  return 0
}

# Function to safely write to progress pipe
write_to_progress_pipe() {
  # Check if the function is defined in the main script
  if declare -f _write_to_progress_pipe >/dev/null; then
    _write_to_progress_pipe "$@"
  elif [[ -n "${PROGRESS_PIPE:-}" && -p "${PROGRESS_PIPE:-}" ]]; then
    # If PROGRESS_PIPE is defined and is a pipe, write directly to it
    echo "$1" > "${PROGRESS_PIPE}"
  else
    # If no progress pipe function or variable is available, just log the message
    log_debug "Progress: $1"
  fi
}

# Function to safely get file size
get_file_size() {
  local file="$1"
  if [[ -f "$file" ]]; then
    if command -v wc &>/dev/null; then
      wc -c < "$file" | tr -d ' '
    else
      # Fallback if wc is not available
      stat -f%z "$file" 2>/dev/null || stat --format="%s" "$file" 2>/dev/null || echo "0"
    fi
  else
    echo "0"
  fi
}

# Function to safely sanitize input for logging
sanitize_for_log() {
  local input="$1"
  # If input is not provided, return empty string
  if [[ -z "$input" ]]; then
    echo ""
    return
  fi

  # Return basename of the path to avoid exposing full paths in logs
  basename "$input" 2>/dev/null || echo "$input"
}

# --- Generic MarkItDown Conversion Function ---
_convert_with_markitdown() {
  local input_file="$1"
  local output_file="$2"
  local file_type="${3:-document}"
  local timeout_seconds=300  # Default timeout: 5 minutes
  
  # Set timeout based on file type
  case "$file_type" in
    "PDF document")
      timeout_seconds=600  # 10 minutes for PDF
      ;;
    "PowerPoint presentation")
      timeout_seconds=300  # 5 minutes for PowerPoint
      ;;
    "Word document")
      timeout_seconds=300  # 5 minutes for Word
      ;;
    *)
      timeout_seconds=300  # Default: 5 minutes
      ;;
  esac
  
  # Check if MarkItDown command exists
  if ! command -v markitdown &>/dev/null; then
    log_error "MarkItDown command not found"
    return 1
  fi
  
  # Create output directory if it doesn't exist
  mkdir -p "$(dirname "$output_file")"
  
  # Log the start of the conversion
  log_info "Converting $file_type: $input_file"
  log_debug "Processing file: $input_file"
  
  # Find markitdown in PATH
  local markitdown_cmd
  markitdown_cmd=$(command -v markitdown)
  log_debug "Found markitdown in PATH: $markitdown_cmd"
  
  # Start time for duration calculation
  local start_time
  start_time=$(date +%s)
  
  # Run MarkItDown with timeout
  log_debug "Running: $markitdown_cmd \"$input_file\" -o \"$output_file\""
  timeout "$timeout_seconds" "$markitdown_cmd" "$input_file" -o "$output_file"
  local status=$?
  
  # Calculate duration
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  # Check if the command timed out
  if [ $status -eq 124 ]; then
    log_error "MarkItDown conversion timed out after ${timeout_seconds}s for $file_type: $input_file"
    # Clean up partial output
    if [ -f "$output_file" ]; then
      rm -f "$output_file"
    fi
    # Write to progress pipe if it exists
    if [ -n "${PROGRESS_PIPE:-}" ] && [ -p "${PROGRESS_PIPE:-}" ]; then
      echo "FAILED:$input_file:Timeout" > "$PROGRESS_PIPE"
    fi
    
    # Directly write to conversion log
    if [ -n "$conversion_log" ] && [ -d "$(dirname "$conversion_log")" ]; then
      local timestamp=$(date +"$date_format")
      local sanitized_input=$(basename "$input_file")
      local sanitized_output=$(basename "$output_file")
      echo "$timestamp | FAILED | ${duration}s | 0 | $sanitized_input | $sanitized_output" >> "$conversion_log"
    fi
    
    return 1
  fi
  
  # Check if the command failed
  if [ $status -ne 0 ]; then
    log_error "MarkItDown conversion failed for $file_type: $input_file"
    # Clean up partial output
    if [ -f "$output_file" ]; then
      rm -f "$output_file"
    fi
    # Write to progress pipe if it exists
    if [ -n "${PROGRESS_PIPE:-}" ] && [ -p "${PROGRESS_PIPE:-}" ]; then
      echo "FAILED:$input_file:Error" > "$PROGRESS_PIPE"
    fi
    
    # Directly write to conversion log
    if [ -n "$conversion_log" ] && [ -d "$(dirname "$conversion_log")" ]; then
      local timestamp=$(date +"$date_format")
      local sanitized_input=$(basename "$input_file")
      local sanitized_output=$(basename "$output_file")
      echo "$timestamp | FAILED | ${duration}s | 0 | $sanitized_input | $sanitized_output" >> "$conversion_log"
    fi
    
    return 1
  fi
  
  # Check if output file exists and has content
  local output_size=0
  if [ -f "$output_file" ]; then
    output_size=$(stat -f%z "$output_file" 2>/dev/null || stat --format=%s "$output_file" 2>/dev/null)
    if [ "$output_size" -gt 0 ]; then
      log_debug "MarkItDown conversion status: $status"
      log_debug "Output file exists: Yes"
      log_debug "Output file has content: Yes"
      log_debug "MarkItDown conversion successful for $file_type: $input_file"
      log_success "Successfully converted $file_type: $input_file (${duration}s, $output_size)"
      log_success "Converted: $input_file -> $output_file (${duration}s, $output_size bytes)"
      # Write to progress pipe if it exists
      if [ -n "${PROGRESS_PIPE:-}" ] && [ -p "${PROGRESS_PIPE:-}" ]; then
        echo "SUCCESS:$input_file:$duration:$output_size" > "$PROGRESS_PIPE"
      fi
      
      # Directly write to conversion log
      if [ -n "$conversion_log" ] && [ -d "$(dirname "$conversion_log")" ]; then
        local timestamp=$(date +"$date_format")
        local sanitized_input=$(basename "$input_file")
        local sanitized_output=$(basename "$output_file")
        echo "$timestamp | SUCCESS | ${duration}s | $output_size | $sanitized_input | $sanitized_output" >> "$conversion_log"
      fi
      
      # Add debug statements for log_conversion
      log_debug "DEBUG: About to call log_conversion with parameters:"
      log_debug "DEBUG: input_file=$input_file"
      log_debug "DEBUG: output_file=$output_file"
      log_debug "DEBUG: status=SUCCESS"
      log_debug "DEBUG: duration=$duration"
      log_debug "DEBUG: output_size=$output_size"
      
      return 0
    else
      log_debug "MarkItDown conversion status: $status"
      log_debug "Output file exists: Yes"
      log_debug "Output file has content: No"
      log_error "MarkItDown conversion failed: Output file is empty for $file_type: $input_file"
      # Clean up empty output
      rm -f "$output_file"
      # Write to progress pipe if it exists
      if [ -n "${PROGRESS_PIPE:-}" ] && [ -p "${PROGRESS_PIPE:-}" ]; then
        echo "FAILED:$input_file:EmptyOutput" > "$PROGRESS_PIPE"
      fi
      
      # Directly write to conversion log
      if [ -n "$conversion_log" ] && [ -d "$(dirname "$conversion_log")" ]; then
        local timestamp=$(date +"$date_format")
        local sanitized_input=$(basename "$input_file")
        local sanitized_output=$(basename "$output_file")
        echo "$timestamp | FAILED | ${duration}s | 0 | $sanitized_input | $sanitized_output" >> "$conversion_log"
      fi
      
      # Add debug statements for log_conversion
      log_debug "DEBUG: About to call log_conversion with parameters:"
      log_debug "DEBUG: input_file=$input_file"
      log_debug "DEBUG: output_file=$output_file"
      log_debug "DEBUG: status=FAILED"
      log_debug "DEBUG: duration=$duration"
      log_debug "DEBUG: output_size=0"
      
      return 1
    fi
  else
    log_debug "MarkItDown conversion status: $status"
    log_debug "Output file exists: No"
    log_error "MarkItDown conversion failed: Output file not found for $file_type: $input_file"
    # Write to progress pipe if it exists
    if [ -n "${PROGRESS_PIPE:-}" ] && [ -p "${PROGRESS_PIPE:-}" ]; then
      echo "FAILED:$input_file:NoOutput" > "$PROGRESS_PIPE"
    fi
    
    # Directly write to conversion log
    if [ -n "$conversion_log" ] && [ -d "$(dirname "$conversion_log")" ]; then
      local timestamp=$(date +"$date_format")
      local sanitized_input=$(basename "$input_file")
      local sanitized_output=$(basename "$output_file")
      echo "$timestamp | FAILED | ${duration}s | 0 | $sanitized_input | $sanitized_output" >> "$conversion_log"
    fi
    
    # Add debug statements for log_conversion
    log_debug "DEBUG: About to call log_conversion with parameters:"
    log_debug "DEBUG: input_file=$input_file"
    log_debug "DEBUG: output_file=$output_file"
    log_debug "DEBUG: status=FAILED"
    log_debug "DEBUG: duration=$duration"
    log_debug "DEBUG: output_size=0"
    
    return 1
  fi
}
# --- End Generic MarkItDown Conversion Function ---


# Function to convert Word document to Markdown using MarkItDown
convert_word_to_md() {
  local input_file="$1"
  local output_file="$2"
  increment_word_doc_count # Increment counter
  _convert_with_markitdown "$input_file" "$output_file" "Word document"
}

# Function to convert PowerPoint to Markdown using MarkItDown
convert_powerpoint_to_md() {
  local input_file="$1"
  local output_file="$2"
  increment_powerpoint_count # Increment counter
  _convert_with_markitdown "$input_file" "$output_file" "PowerPoint document"
}

# Function to check if a PDF has embedded text
pdf_has_text() {
  local pdf_file="$1"
  local pdftotext_cmd

  # Try to find pdftotext command
  pdftotext_cmd=$(find_command "pdftotext")
  if [[ -z "$pdftotext_cmd" ]]; then
    # If pdftotext is not available, assume PDF has text to be safe
    log_debug "pdftotext not found, assuming PDF has text: $pdf_file"
    return 0
  fi

  # Extract text from the first page
  local text_content
  text_content=$($pdftotext_cmd -f 1 -l 1 "$pdf_file" - 2>/dev/null)

  # Check if extracted text is empty (after removing whitespace)
  if [[ -z "${text_content// /}" ]]; then
    log_debug "PDF appears to have no embedded text: $pdf_file"
    return 1
  else
    log_debug "PDF has embedded text: $pdf_file"
    return 0
  fi
}

# Function to convert PDF to Markdown
convert_pdf_to_md() {
  local input_file="$1"
  local output_file="$2"
  local sanitized_input
  local start_time
  local end_time
  local duration
  local output_size
  local conversion_status=0
  
  # Separate declaration and assignment to avoid masking return values (SC2155)
  sanitized_input=$(sanitize_for_log "$input_file")
  log_debug "Processing PDF document"
  log_debug "SPECIAL_DEBUG_MARKER: Using modified convert_pdf_to_md function with fallback"
  
  # Record start time
  start_time=$(date +%s)
  
  # Log the start of the conversion
  log_info "Converting PDF document: $sanitized_input"
  log_debug "Processing file: $sanitized_input"
  
  # Check if pdftotext is available
  local pdftotext_cmd
  pdftotext_cmd=$(find_command "pdftotext")
  if [[ -n "$pdftotext_cmd" ]]; then
    log_debug "Found pdftotext in PATH: $pdftotext_cmd"
    
    # Check if PDF has embedded text
    if "$pdftotext_cmd" -f 1 -l 1 "$input_file" - 2>/dev/null | grep -q '[a-zA-Z0-9]'; then
      log_debug "PDF has embedded text: $sanitized_input"
      
      # If PDF has text, try MarkItDown first
      log_debug "PDF has text, using MarkItDown first"
      if _convert_with_markitdown "$input_file" "$output_file" "PDF document"; then
        # MarkItDown succeeded
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        output_size=$(get_file_size "$output_file")
        log_debug "Conversion successful for file: $sanitized_input"
        log_debug "PDF conversion completed for file: $sanitized_input with status: 0"
        
        # Add debug statements for convert_pdf_to_md
        log_debug "DEBUG: convert_pdf_to_md - MarkItDown succeeded"
        log_debug "DEBUG: convert_pdf_to_md - Not calling log_conversion to avoid duplicate logging"
        
        return 0
      else
        # MarkItDown failed, try marker_single as fallback
        log_debug "MarkItDown failed, trying marker_single as fallback"
        
        # Create a temporary directory for marker_single
        local temp_dir
        temp_dir=$(mktemp -d)
        
        if convert_with_marker_single "$input_file" "$output_file" "$temp_dir"; then
          # marker_single succeeded
          end_time=$(date +%s)
          duration=$((end_time - start_time))
          output_size=$(get_file_size "$output_file")
          log_debug "Conversion successful for file: $sanitized_input"
          log_debug "PDF conversion completed for file: $sanitized_input with status: 0"
          
          # Clean up temporary directory
          rm -rf "$temp_dir" 2>/dev/null || true
          
          # Add debug statements for convert_pdf_to_md
          log_debug "DEBUG: convert_pdf_to_md - marker_single succeeded"
          log_debug "DEBUG: convert_pdf_to_md - Not calling log_conversion to avoid duplicate logging"
          
          return 0
        else
          # Both methods failed
          log_error "Both MarkItDown and marker_single failed for: $sanitized_input"
          end_time=$(date +%s)
          duration=$((end_time - start_time))
          log_debug "PDF conversion completed for file: $sanitized_input with status: 1"
          
          # Clean up temporary directory
          rm -rf "$temp_dir" 2>/dev/null || true
          
          # Add debug statements for convert_pdf_to_md
          log_debug "DEBUG: convert_pdf_to_md - Both methods failed"
          log_debug "DEBUG: convert_pdf_to_md - Not calling log_conversion to avoid duplicate logging"
          
          return 1
        fi
      fi
    else
      # PDF doesn't have extractable text, use marker_single directly
      log_debug "PDF doesn't have extractable text: $sanitized_input"
      log_debug "Using marker_single for OCR conversion"
      
      # Create a temporary directory for marker_single
      local temp_dir
      temp_dir=$(mktemp -d)
      
      if convert_with_marker_single "$input_file" "$output_file" "$temp_dir"; then
        # marker_single succeeded
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        output_size=$(get_file_size "$output_file")
        log_debug "Conversion successful for file: $sanitized_input"
        log_debug "PDF conversion completed for file: $sanitized_input with status: 0"
        
        # Clean up temporary directory
        rm -rf "$temp_dir" 2>/dev/null || true
        
        return 0
      else
        # marker_single failed
        log_error "marker_single failed for: $sanitized_input"
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_debug "PDF conversion completed for file: $sanitized_input with status: 1"
        
        # Clean up temporary directory
        rm -rf "$temp_dir" 2>/dev/null || true
        
        return 1
      fi
    fi
  else
    # pdftotext not available, try MarkItDown directly
    log_warning "pdftotext not found, cannot check if PDF has text. Using MarkItDown directly."
    if _convert_with_markitdown "$input_file" "$output_file" "PDF document"; then
      # MarkItDown succeeded
      end_time=$(date +%s)
      duration=$((end_time - start_time))
      output_size=$(get_file_size "$output_file")
      log_debug "Conversion successful for file: $sanitized_input"
      log_debug "PDF conversion completed for file: $sanitized_input with status: 0"
      return 0
    else
      # MarkItDown failed, try marker_single as fallback
      log_debug "MarkItDown failed, trying marker_single as fallback"
      
      # Create a temporary directory for marker_single
      local temp_dir
      temp_dir=$(mktemp -d)
      
      if convert_with_marker_single "$input_file" "$output_file" "$temp_dir"; then
        # marker_single succeeded
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        output_size=$(get_file_size "$output_file")
        log_debug "Conversion successful for file: $sanitized_input"
        log_debug "PDF conversion completed for file: $sanitized_input with status: 0"
        
        # Clean up temporary directory
        rm -rf "$temp_dir" 2>/dev/null || true
        
        return 0
      else
        # Both methods failed
        log_error "Both MarkItDown and marker_single failed for: $sanitized_input"
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log_debug "PDF conversion completed for file: $sanitized_input with status: 1"
        
        # Clean up temporary directory
        rm -rf "$temp_dir" 2>/dev/null || true
        
        return 1
      fi
    fi
  fi
}

# Function to convert PDF with marker_single
convert_with_marker_single() {
  local input_file="$1"
  local output_file="$2"
  local temp_dir="$3"
  local filename=$(basename "$input_file")
  local base_name="${filename%.*}"
  
  # Create temporary directories for marker_single
  mkdir -p "$temp_dir/input"
  mkdir -p "$temp_dir/output"
  
  # Copy the file to the temp directory
  cp "$input_file" "$temp_dir/input/"
  
  # Check if marker_single is available
  if ! command -v marker_single >/dev/null 2>&1; then
    echo "[ERROR] marker_single not found. Cannot convert PDF: $filename"
    log_error "marker_single not found. Cannot convert PDF: $filename"
    return 1
  fi
  
  # Set timeout for conversion (20 minutes for OCR which can be slow)
  local timeout_cmd=""
  local timeout_value=$PDF_TIMEOUT
  
  if command -v timeout &>/dev/null; then
    timeout_cmd="timeout $timeout_value"
  elif command -v gtimeout &>/dev/null; then
    timeout_cmd="gtimeout $timeout_value"
  fi
  
  # Run marker_single with appropriate timeout
  local status=0
  if [[ -n "$timeout_cmd" ]]; then
    $timeout_cmd marker_single "$temp_dir/input/$filename" --output_dir "$temp_dir/output" \
      --output_format markdown \
      --force_ocr \
      --disable_tqdm \
      --paginate_output 2>/dev/null || status=$?
  else
    marker_single "$temp_dir/input/$filename" --output_dir "$temp_dir/output" \
      --output_format markdown \
      --force_ocr \
      --disable_tqdm \
      --paginate_output 2>/dev/null || status=$?
  fi
  
  # Check if marker_single succeeded
  if [[ $status -ne 0 ]]; then
    echo "[ERROR] marker_single failed with status $status for file: $filename"
    log_error "marker_single failed with status $status for file: $filename"
    return $status
  fi
  
  # Find the marker_single output directory - it creates a directory with the same name as the input file
  local marker_output_dir=$(find "$temp_dir/output" -type d -name "$base_name" | head -n 1)
  
  if [[ -n "$marker_output_dir" && -d "$marker_output_dir" ]]; then
    # Find the markdown file in the output directory
    local output_md=$(find "$marker_output_dir" -name "*.md" -type f | head -n 1)
    
    if [[ -n "$output_md" && -f "$output_md" && -s "$output_md" ]]; then
      # Create the output directory structure
      local output_dir=$(dirname "$output_file")
      mkdir -p "$output_dir"
      
      # Copy the entire marker_single output directory to preserve images and structure
      log_debug "Copying marker_single output directory from $marker_output_dir to $output_dir"
      cp -R "$marker_output_dir" "$output_dir/"
      
      # Create a symlink or copy the markdown file to the expected output location if needed
      if [[ "$output_file" != "$output_dir/$base_name/$base_name.md" ]]; then
        log_debug "Creating symlink from $output_dir/$base_name/$base_name.md to $output_file"
        ln -sf "$output_dir/$base_name/$base_name.md" "$output_file" || cp "$output_dir/$base_name/$base_name.md" "$output_file"
      fi
      
      if [[ -f "$output_file" && -s "$output_file" ]]; then
        echo "[SUCCESS] Converted PDF with marker_single: $filename"
        return 0
      fi
    fi
  fi
  
  echo "[ERROR] marker_single conversion failed to produce output for: $filename"
  log_error "marker_single conversion failed to produce output for: $filename"
  return 1
}

# Function to convert .doc files with textutil and MarkItDown
convert_doc_with_textutil() {
  local input_file="$1"
  local output_file="$2"
  local sanitized_input
  local start_time
  local temp_dir
  local temp_docx
  
  # Separate declaration and assignment to avoid masking return values (SC2155)
  sanitized_input=$(basename "$input_file")
  start_time=$(date +%s)
  increment_word_doc_count # Increment counter

  log_debug "Converting .doc file with textutil and MarkItDown: $input_file -> $output_file"

  # Check if running on macOS for textutil
  if [[ "$(uname)" != "Darwin" ]]; then
    log_error "textutil is only available on macOS. Cannot convert .doc files on this system."
    log_error "Please convert .doc files to .docx format manually before processing."
    log_warning "Alternatives: Use LibreOffice (soffice --headless --convert-to docx) or MS Word on non-macOS systems."
    write_to_progress_pipe "failed:1:0:0:$input_file"
    return 1
  fi

  # Create a temporary directory for processing - separate declaration and assignment
  temp_dir=$(mktemp -d)
  temp_docx="${temp_dir}/$(basename "${input_file%.*}").docx"

  # First convert .doc to .docx using textutil
  log_debug "Converting .doc to .docx using textutil: $input_file -> $temp_docx"
  textutil -convert docx "$input_file" -output "$temp_docx" 2>"${temp_dir}/textutil_error.log"
  local textutil_status=$?

  if [[ $textutil_status -ne 0 || ! -f "$temp_docx" || ! -s "$temp_docx" ]]; then
    local error_output=""
    if [[ -f "${temp_dir}/textutil_error.log" ]]; then
      error_output=$(cat "${temp_dir}/textutil_error.log")
    fi

    log_error "textutil conversion failed with status $textutil_status for .doc file: $sanitized_input"
    if [[ -n "$error_output" ]]; then
      log_error "Error output: $error_output"
    fi

    # Clean up temporary files
    rm -rf "$temp_dir" 2>/dev/null || true

    write_to_progress_pipe "failed:1:0:0:$input_file"
    return 1
  fi

  log_debug "Successfully converted to .docx, now using MarkItDown to convert to Markdown"

  # Now convert the .docx to Markdown using the generic MarkItDown function
  _convert_with_markitdown "$temp_docx" "$output_file" "Word document (.docx from .doc)"

  # Clean up temporary files
  rm -rf "$temp_dir" 2>/dev/null || true
}

# Function to convert a document using MarkItDown
convert_with_markitdown() {
  local input_file="$1"
  local output_file="$2"
  local file_type="${3:-document}"  # Default to "document" if not specified
  
  # Call the internal implementation
  _convert_with_markitdown "$input_file" "$output_file" "$file_type"
  return $?
}

# Improved version of convert_file that uses standardized path handling
convert_file_improved() {
  local file="$1"
  local input_dir="${2:-}"
  local output_dir="${3:-}"

  # Skip files that don't exist
  if [[ ! -f "$file" ]]; then
    log_error "File not found: $file"
    return 1
  fi

  # Skip dot files
  if [[ $(basename "$file") == .* ]]; then
    log_debug "Skipping dot file: $file"
    return 0
  fi

  # Get file extension
  local ext="${file##*.}"
  ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

  # Skip if the file has no extension
  if [[ "$ext" == "$file" ]]; then
    log_debug "Skipping file with no extension: $file"
    return 0
  fi

  # Ensure output_dir is set
  if [[ -z "$output_dir" ]]; then
    # If output_dir is not provided, use current directory
    output_dir="."
    log_warning "Output directory not specified, using current directory"
  fi

  # Get the output path using the standardized function
  local output_path
  output_path=$(get_output_path "$file" "$input_dir" "$output_dir")
  
  log_debug "Converting file: $file to $output_path"

  # Temporarily disable error propagation to prevent script termination on conversion failures
  set +e

  # Handle different file types
  local conversion_status=0
  case "$ext" in
    # Document formats
    doc)
      # For .doc files, use textutil and MarkItDown
      log_info "Converting Word document (.doc): $file"
      convert_doc_with_textutil "$file" "$output_path"
      conversion_status=$?
      ;;
    docx)
      log_info "Converting Word document (.docx): $file"
      # Check if MarkItDown is available first
      if find_command "markitdown" &>/dev/null; then
        convert_with_markitdown "$file" "$output_path" "Word document"
        conversion_status=$?
      else
        # Fallback to pandoc if available
        if command -v pandoc &>/dev/null; then
          log_info "MarkItDown not available, falling back to pandoc for Word document conversion"
          convert_docx_with_pandoc "$file" "$output_path"
          conversion_status=$?
        else
          log_error "No available conversion tools for Word documents. Please install MarkItDown or pandoc."
          conversion_status=1
        fi
      fi
      ;;
    # Presentation formats
    ppt|pptx)
      log_info "Converting PowerPoint presentation: $file"
      # PowerPoint conversion requires MarkItDown
      if find_command "markitdown" &>/dev/null; then
        convert_with_markitdown "$file" "$output_path" "PowerPoint presentation"
        conversion_status=$?
      else
        log_error "PowerPoint conversion requires MarkItDown. Please install it using pip."
        conversion_status=1
      fi
      ;;
    # PDF formats
    pdf)
      log_info "Converting PDF document: $file"
      # Use convert_pdf_to_md which handles MarkItDown availability internally
      # and has fallback to marker_single if needed
      convert_pdf_to_md "$file" "$output_path"
      conversion_status=$?
      ;;
    # Spreadsheet formats
    xls|xlsx|csv)
      log_info "Converting spreadsheet: $file"
      if find_command "markitdown" &>/dev/null; then
        convert_with_markitdown "$file" "$output_path" "spreadsheet"
        conversion_status=$?
      else
        log_warning "Spreadsheet conversion requires MarkItDown. Creating simple metadata file instead."
        create_simple_metadata_file "$file" "$output_path" "spreadsheet"
        conversion_status=$?
      fi
      ;;
    # Image formats
    jpg|jpeg|png|gif|bmp|tiff|tif|webp)
      log_info "Converting image: $file"
      # Image conversion doesn't require MarkItDown
      convert_image_to_md "$file" "$output_path"
      conversion_status=$?
      ;;
    # Web formats
    html|htm|xml|json)
      log_info "Converting web document: $file"
      if find_command "markitdown" &>/dev/null; then
        convert_with_markitdown "$file" "$output_path" "web document"
        conversion_status=$?
      elif command -v pandoc &>/dev/null && [[ "$ext" == "html" || "$ext" == "htm" ]]; then
        log_info "MarkItDown not available, falling back to pandoc for HTML conversion"
        convert_html_with_pandoc "$file" "$output_path"
        conversion_status=$?
      else
        log_warning "Web document conversion requires MarkItDown. Creating simple metadata file instead."
        create_simple_metadata_file "$file" "$output_path" "web document"
        conversion_status=$?
      fi
      ;;
    # MHTML format
    mhtml|mht)
      log_info "Converting MHTML document: $file"
      # MHTML conversion uses pandoc directly
      convert_mhtml_with_pandoc "$file" "$output_path"
      conversion_status=$?
      ;;
    # Archive formats
    zip)
      log_info "Converting archive: $file"
      if find_command "markitdown" &>/dev/null; then
        convert_with_markitdown "$file" "$output_path" "archive"
        conversion_status=$?
      else
        log_warning "Archive conversion requires MarkItDown. Creating simple metadata file instead."
        create_simple_metadata_file "$file" "$output_path" "archive"
        conversion_status=$?
      fi
      ;;
    # Audio formats
    mp3|wav|ogg|flac|aac|m4a)
      log_info "Converting audio file: $file"
      if find_command "markitdown" &>/dev/null; then
        convert_with_markitdown "$file" "$output_path" "audio file"
        conversion_status=$?
      else
        log_warning "Audio file conversion requires MarkItDown. Creating simple metadata file instead."
        create_simple_metadata_file "$file" "$output_path" "audio file"
        conversion_status=$?
      fi
      ;;
    # Video formats
    mp4|avi|mov|wmv|mkv|flv|webm)
      log_info "Converting video file: $file"
      if find_command "markitdown" &>/dev/null; then
        convert_with_markitdown "$file" "$output_path" "video file"
        conversion_status=$?
      else
        log_warning "Video file conversion requires MarkItDown. Creating simple metadata file instead."
        create_simple_metadata_file "$file" "$output_path" "video file"
        conversion_status=$?
      fi
      ;;
    # Text formats
    txt|md|markdown|rst|rtf)
      log_info "Converting text document: $file"
      if find_command "markitdown" &>/dev/null; then
        convert_with_markitdown "$file" "$output_path" "text document"
        conversion_status=$?
      elif command -v pandoc &>/dev/null && [[ "$ext" == "rtf" ]]; then
        log_info "MarkItDown not available, falling back to pandoc for RTF conversion"
        convert_rtf_with_pandoc "$file" "$output_path"
        conversion_status=$?
      else
        # For plain text files, we can do a simple copy
        if [[ "$ext" == "txt" || "$ext" == "md" || "$ext" == "markdown" ]]; then
          log_info "MarkItDown not available, performing simple copy for text file"
          cp "$file" "$output_path"
          conversion_status=$?
        else
          log_warning "Text document conversion requires MarkItDown. Creating simple metadata file instead."
          create_simple_metadata_file "$file" "$output_path" "text document"
          conversion_status=$?
        fi
      fi
      ;;
    # Code formats
    py|js|java|c|cpp|h|hpp|cs|go|rb|php|pl|sh|bash|zsh|sql|r|swift)
      log_info "Converting code file: $file"
      if find_command "markitdown" &>/dev/null; then
        convert_with_markitdown "$file" "$output_path" "code file"
        conversion_status=$?
      else
        # For code files, we can create a markdown file with the code content
        log_info "MarkItDown not available, creating markdown with code content"
        create_code_markdown "$file" "$output_path"
        conversion_status=$?
      fi
      ;;
    # Other formats
    *)
      log_info "Converting unknown format: $file"
      if find_command "markitdown" &>/dev/null; then
        convert_with_markitdown "$file" "$output_path" "unknown format"
        conversion_status=$?
      else
        log_warning "Unknown format conversion requires MarkItDown. Creating simple metadata file instead."
        create_simple_metadata_file "$file" "$output_path" "unknown format"
        conversion_status=$?
      fi
      ;;
  esac

  # Re-enable error propagation
  set -e

  # Check if conversion was successful
  if [[ $conversion_status -eq 0 ]]; then
    log_debug "Conversion successful for file: $file"
    return 0
  else
    log_warning "Conversion failed for file: $file with status: $conversion_status"
    return $conversion_status
  fi
}

# Function to convert MHTML files using Pandoc
convert_mhtml_with_pandoc() {
  local input_file="$1"
  local output_file="$2"
  local sanitized_input
  local start_time
  
  sanitized_input=$(sanitize_filename "$(basename "$input_file")")
  start_time=$(date +%s)

  log_info "Converting MHTML document: $sanitized_input"

  # Check if pandoc is available
  local pandoc_path
  pandoc_path=$(find_command "pandoc")
  if [[ -z "$pandoc_path" ]]; then
    log_error "Pandoc not found. Please install Pandoc to convert MHTML files."
    write_to_progress_pipe "failed:1:0:0:$input_file"
    return 1
  fi

  log_debug "Found pandoc in PATH: $pandoc_path"

  # Create output directory if it doesn't exist
  mkdir -p "$(dirname "$output_file")"

  # First, create a temporary file to preprocess the MHTML file
  local temp_input_file
  temp_input_file=$(mktemp)

  # Extract the HTML content from the MHTML file using a more robust approach
  # This pattern looks for the HTML section between Content-Type: text/html and the next boundary
  awk '
    BEGIN { print_mode = 0; found_html = 0; }
    /Content-Type: text\/html/ {
      print_mode = 1;
      found_html = 1;
      # Skip headers until empty line
      while (getline && $0 != "") {}
      next;
    }
    /^------MultipartBoundary/ {
      if (print_mode == 1) print_mode = 0;
    }
    print_mode == 1 { print; }
    END { if (!found_html) exit 1; }
  ' "$input_file" > "$temp_input_file"

  # If HTML extraction failed, try a simpler approach
  if [[ ! -s "$temp_input_file" ]]; then
    log_debug "First HTML extraction attempt failed, trying alternative method"
    # Simple approach: extract everything after the first empty line following "Content-Type: text/html"
    awk '
      BEGIN { print_mode = 0; }
      /Content-Type: text\/html/ { print_mode = 1; next; }
      print_mode == 1 && $0 == "" { print_mode = 2; next; }
      print_mode == 2 { print; }
    ' "$input_file" > "$temp_input_file"
  fi

  # If still empty, try one more approach
  if [[ ! -s "$temp_input_file" ]]; then
    log_debug "Second HTML extraction attempt failed, trying final method"
    # Just extract anything that looks like HTML
    grep -A 10000 "<html" "$input_file" | grep -B 10000 "</html>" > "$temp_input_file"
  fi

  # Check if we extracted any content
  if [[ ! -s "$temp_input_file" ]]; then
    log_error "Failed to extract HTML content from MHTML file: $sanitized_input"
    rm -f "$temp_input_file"
    write_to_progress_pipe "failed:1:0:0:$input_file"
    return 1
  fi

  # Convert MHTML to Markdown using Pandoc with improved options
  # --wrap=none: Prevents line wrapping
  # --extract-media: Extracts embedded images to a directory
  # --standalone: Produces a complete document
  # --from=html: Specifies input format as HTML
  # --to=markdown_github: Uses GitHub-flavored Markdown for better compatibility

  local media_dir="${output_file%.md}_media"
  mkdir -p "$media_dir"

  log_debug "Running: $pandoc_path \"$temp_input_file\" -f html -t markdown_github --wrap=none --extract-media=\"$media_dir\" --standalone -o \"$output_file\""

  # Run pandoc with error handling
  local temp_error_file
  temp_error_file=$(mktemp)
  if ! "$pandoc_path" "$temp_input_file" -f html -t markdown_github --wrap=none --extract-media="$media_dir" --standalone -o "$output_file" 2>"$temp_error_file"; then
    local pandoc_status=$?
    local error_output
    error_output=$(cat "$temp_error_file")
    rm -f "$temp_error_file" "$temp_input_file"

    log_error "Pandoc conversion failed with status $pandoc_status for file: $sanitized_input"
    log_error "Error output: $error_output"
    write_to_progress_pipe "failed:1:0:0:$input_file"
    return 1
  fi

  rm -f "$temp_error_file" "$temp_input_file"

  # Post-process the markdown file to clean up any remaining artifacts
  if [[ -f "$output_file" && -s "$output_file" ]]; then
    # Create a temporary file for processing
    local temp_file
    temp_file=$(mktemp)

    # Clean up common MHTML artifacts
    sed -e 's/=20//g' \
        -e 's/=3D/=/g' \
        -e 's/3D"/"/g' \
        -e 's/3D"/"/g' \
        -e 's/"/"/g' \
        -e 's/&/\&/g' \
        -e 's/</</g' \
        -e 's/>/>/g' \
        -e 's/::::::::::::::::::::::::::::::::::::: [^"]*"//g' \
        -e 's/:::::::::::::: [^"]*"//g' \
        -e 's/::: {#[^}]*}//g' \
        -e 's/::: [^"]*"//g' \
        -e 's/<span [^>]*>//g' \
        -e 's/<\/span>//g' \
        -e 's/<a [^>]*>//g' \
        -e 's/<\/a>//g' \
        -e 's/\[<span [^]]*\]([^)]*)/\[\]/g' \
        -e '/^---$/d' \
        -e '/^\-\-\-\-\--MultipartBoundary/d' \
        -e '/^Content-Type:/d' \
        -e '/^Content-ID:/d' \
        -e '/^Content-Transfer-Encoding:/d' \
        -e '/^Content-Location:/d' \
        -e '/^MIME-Version:/d' \
        -e '/^Subject:/d' \
        -e '/^Date:/d' \
        -e '/^From:/d' \
        -e '/^Snapshot-Content-Location:/d' \
        -e '/^$/N;/^\n$/D' \
        "$output_file" > "$temp_file"

    # Replace the original file with the cleaned version
    mv "$temp_file" "$output_file"

    # Add a title and source information at the top of the file
    local title
    title=$(basename "$input_file" .mhtml | sed 's/_/ /g')
    local temp_title_file
    temp_title_file=$(mktemp)

    {
      echo "# $title"
      echo ""
      echo "*This document was converted from MHTML format using Pandoc.*"
      echo ""
      echo "---"
      echo ""
      cat "$output_file"
    } > "$temp_title_file"

    mv "$temp_title_file" "$output_file"
  fi

  local end_time
  local duration
  
  # Separate declaration and assignment to avoid masking return values (SC2155)
  end_time=$(date +%s)
  duration=$((end_time - start_time))

  # Check if output file was created and has content
  if [[ -f "$output_file" && -s "$output_file" ]]; then
    local output_size
    
    # Separate declaration and assignment to avoid masking return values (SC2155)
    output_size=$(get_file_size "$output_file")
    log_success "Successfully converted MHTML document: $sanitized_input (${duration}s, ${output_size})"
    write_to_progress_pipe "complete:1:${duration}:${output_size}:$input_file"
    return 0
  else
    # File doesn't exist or is empty
    log_error "Failed to convert MHTML document: $sanitized_input (output file is empty or not created)"
    write_to_progress_pipe "failed:1:${duration}:0:$input_file"
    return 1
  fi
}

# Function to convert a file based on its extension
convert_file() {
  local file="$1"
  local input_dir="${2:-}"
  local output_dir="${3:-}"
  
  # Call the improved version with the same parameters
  convert_file_improved "$file" "$input_dir" "$output_dir"
  return $?
}