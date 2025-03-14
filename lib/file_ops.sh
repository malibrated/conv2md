#!/usr/bin/env bash
#
# file_ops.sh - File operations for conv2md
#
# This file contains functions for file operations,
# including file finding, checking, and path construction.

# Disable shellcheck warnings for variables defined in the main script
# shellcheck disable=SC2154
# Variables from main script: resume_from_checkpoint, checkpoint_file, log_dir, 
# error_log, max_file_size, force_conversion, input_dir, output_dir, skip_word,
# skip_powerpoint, skip_pdf, max_workers, temp_dir, instance_id, progress_pipe

# Function to check if a file is already in the checkpoint file
is_in_checkpoint() {
  local file="$1"
  
  if [[ "$resume_from_checkpoint" == false ]]; then
    return 1  # If not resuming, always return false
  fi
  
  if grep -Fq "$file" "$checkpoint_file" 2>/dev/null; then
    return 0  # File is in checkpoint file
  fi
  
  return 1  # File is not in checkpoint file
}

# NOTE: get_file_size_bytes function has been moved to utils.sh for centralization
# Use the function from utils.sh instead

# Function to convert bytes to MB with decimal precision
bytes_to_mb() {
  local bytes="$1"
  local mb
  
  # Use awk for floating point calculation
  mb=$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}")
  
  echo "$mb"
}

# Function to check if a file needs conversion
needs_conversion() {
  local input_file="$1"

  # Check if file is already in checkpoint (if resuming)
  if is_in_checkpoint "$input_file"; then
    log_info "Skipping (checkpoint): $input_file"
    return 1
  fi

  # Check if input file exists and is readable
  if [[ ! -f "$input_file" || ! -r "$input_file" ]]; then
    local sanitized_input
    sanitized_input=$(sanitize_for_log "$input_file")
    log_warning "Input file does not exist or is not readable: $sanitized_input"
    rotate_log "$error_log"
    return 1
  fi
  
  # Check file size if max_file_size is set
  if [[ $max_file_size -gt 0 ]]; then
    # Get file size in bytes
    local file_size_bytes
    file_size_bytes=$(get_file_size_bytes "$input_file")
    
    # Convert to MB for comparison
    local file_size_mb
    file_size_mb=$(bytes_to_mb "$file_size_bytes")
    
    # Compare with max_file_size using bc for floating point comparison
    if (( $(echo "$file_size_mb > $max_file_size" | bc -l) )); then
      local sanitized_input
      sanitized_input=$(sanitize_for_log "$input_file")
      log_warning "Skipping large file: $sanitized_input (${file_size_mb}MB > ${max_file_size}MB limit)"
      return 1
    fi
  fi

  # Get output path for this file
  local output_file
  output_file=$(get_output_path "$input_file")

  # If force conversion is enabled, always convert
  if [[ "$force_conversion" == true ]]; then
    return 0
  fi

  # If output file doesn't exist, needs conversion
  if [[ ! -f "$output_file" ]]; then
    return 0
  fi

  # Check if input file is newer than output file
  if [[ "$input_file" -nt "$output_file" ]]; then
    return 0
  fi

  local sanitized_input
  sanitized_input=$(sanitize_for_log "$input_file")
  log_info "Skipping: $sanitized_input (already converted and up-to-date)"
  return 1
}

# Function to get output file path with better handling of special characters
get_output_path() {
  local input_file="$1"
  local input_base_dir="${2:-$input_dir}"
  local output_base_dir="${3:-$output_dir}"
  
  # Get the filename without extension
  local filename
  filename=$(basename "$input_file")
  local basename="${filename%.*}"
  
  # Sanitize the basename
  local sanitized_basename
  sanitized_basename=$(sanitize_filename "$basename")
  
  # Get the relative path using the standardized function
  local rel_path
  rel_path=$(get_relative_path "$input_file" "$input_base_dir")
  
  # Construct the final output path
  local final_output_path
  if [[ -n "$rel_path" ]]; then
    # Create the output directory if it doesn't exist
    mkdir -p "${output_base_dir}/${rel_path}"
    final_output_path="${output_base_dir}/${rel_path}/${sanitized_basename}.md"
  else
    # If no relative path (file is directly in the input directory or outside it)
    final_output_path="${output_base_dir}/${sanitized_basename}.md"
  fi
  
  log_debug "Output path for $input_file: $final_output_path"
  echo "$final_output_path"
}

# Function to count total files to process
count_total_files() {
  # Initialize total count
  total_files=0
  
  log_info "Counting files to process..."
  
  # Count Word files
  if [[ "$skip_word" == false ]]; then
    # Count files sequentially to avoid command line length issues
    local word_count=0
    while read -r file; do
      word_count=$((word_count + 1))
    done < <(find "$input_dir" -type f \( -name "*.doc" -o -name "*.docx" \) 2>/dev/null)
    log_info "Found $word_count Word files"
    total_files=$((total_files + word_count))
  fi
  
  # Count PowerPoint files
  if [[ "$skip_powerpoint" == false ]]; then
    # Count files sequentially to avoid command line length issues
    local ppt_count=0
    while read -r file; do
      ppt_count=$((ppt_count + 1))
    done < <(find "$input_dir" -type f \( -name "*.ppt" -o -name "*.pptx" \) 2>/dev/null)
    log_info "Found $ppt_count PowerPoint files"
    total_files=$((total_files + ppt_count))
  fi
  
  # Count PDF files
  if [[ "$skip_pdf" == false ]]; then
    # Count files sequentially to avoid command line length issues
    local pdf_count=0
    while read -r file; do
      pdf_count=$((pdf_count + 1))
    done < <(find "$input_dir" -type f -name "*.pdf" 2>/dev/null)
    log_info "Found $pdf_count PDF files"
    total_files=$((total_files + pdf_count))
  fi
  
  log_info "Found $total_files files to process"
}

# Function to create a file find command based on the input directory and file types
create_file_find_command() {
  local input_dir="$1"
  local file_types="$2"
  local timestamp_file="$3"
  
  # Base find command
  local find_cmd="find \"$input_dir\" -type f"
  
  # Add file type filters
  if [[ -n "$file_types" ]]; then
    local extensions=""
    IFS=',' read -ra TYPES <<< "$file_types"
    for type in "${TYPES[@]}"; do
      if [[ -n "$extensions" ]]; then
        extensions="$extensions -o"
      fi
      extensions="$extensions -name \"*.${type,,}\""
    done
    
    if [[ -n "$extensions" ]]; then
      find_cmd="$find_cmd \\( $extensions \\)"
    fi
  fi
  
  # Add timestamp filter if timestamp file exists
  if [[ -n "$timestamp_file" && -f "$timestamp_file" ]]; then
    local timestamp
    timestamp=$(cat "$timestamp_file")
    if [[ -n "$timestamp" ]]; then
      # Use -newer for files modified after the timestamp file
      find_cmd="$find_cmd -newer \"$timestamp_file\""
    fi
  fi
  
  # Sort files by modification time (newest first)
  find_cmd="$find_cmd -print"
  
  echo "$find_cmd"
}

# Function to check if we have too many processes running
check_process_count() {
  local max_processes=$((max_workers * 3))  # Allow 3x max_workers processes
  
  # Get current process count for this script in a more compatible way
  local process_count=0
  # shellcheck disable=SC2009
  if is_macos; then
    # macOS specific approach
    process_count=$(ps -o command | grep -c "[c]onv2md")
  else
    # Linux approach
    # shellcheck disable=SC2009
    process_count=$(ps -o cmd | grep -c "[c]onv2md")
  fi
  
  # If ps command failed or returned 0, assume it's safe to continue
  if [[ $? -ne 0 || $process_count -eq 0 ]]; then
    return 0
  fi
  
  if [[ $process_count -gt $max_processes ]]; then
    log_warning "Too many processes ($process_count). Waiting for some to complete..."
    
    # Wait for processes to reduce
    local wait_count=0
    while [[ $process_count -gt $max_processes && $wait_count -lt 12 ]]; do  # Max 1 minute wait
      sleep 5
      
      # Recount processes
      # shellcheck disable=SC2009
      if is_macos; then
        process_count=$(ps -o command | grep -c "[c]onv2md")
      else
        # shellcheck disable=SC2009
        process_count=$(ps -o cmd | grep -c "[c]onv2md")
      fi
      
      wait_count=$((wait_count + 1))
      
      # Check if we should stop due to interruption
      if [[ -f "${log_dir}/.interrupt_flag" ]]; then
        return 1
      fi
    done
    
    # If we still have too many processes, log a warning but continue
    if [[ $process_count -gt $max_processes ]]; then
      log_warning "Still too many processes after waiting. Continuing anyway, but performance may be affected."
    else
      log_info "Process count now at acceptable level ($process_count)."
    fi
  fi
  
  return 0
}

# Function to manage a semaphore directory for concurrent process limitation
create_semaphore_dir() {
  local file_type="$1"
  local semaphore_dir="${temp_dir}/.semaphore_${file_type}_${instance_id}"
  mkdir -p "$semaphore_dir"
  echo "$semaphore_dir"
}

# Function to clean up old semaphore files
cleanup_stale_semaphores() {
  local semaphore_dir="$1"
  
  # Remove semaphore files older than 15 minutes
  find "$semaphore_dir" -type f -mmin +15 -delete 2>/dev/null || true
  
  # Check each semaphore file and remove if the process is gone
  find "$semaphore_dir" -type f 2>/dev/null | while read -r sem; do
    if [[ -f "$sem" ]]; then
      pid=$(cat "$sem" 2>/dev/null)
      if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$sem"
      fi
    fi
  done
}

# Function to clean up temporary files with a specific pattern
cleanup_temp_files() {
  local file_pattern="$1"
  local dir="${2:-$temp_dir}"
  
  if [[ -d "$dir" ]]; then
    find "$dir" -type f -name "$file_pattern" -mmin +60 -delete 2>/dev/null || true
  fi
}

# Comprehensive function to clean up resources and processes
cleanup_resources() {
  log_info "Cleaning up resources and processes..."
  
  # Create interrupt flag to signal processes to stop
  touch "${log_dir}/.interrupt_flag" 2>/dev/null || true
  
  # Kill the zombie cleaner if running
  if [[ -n "${zombie_cleaner_pid:-}" ]]; then
    kill "$zombie_cleaner_pid" 2>/dev/null || true
  fi
  
  # Clean up progress pipe and reader
  if [[ -n "${progress_reader_pid:-}" ]]; then
    kill "$progress_reader_pid" 2>/dev/null || true
  fi
  
  # Find and terminate all child processes
  local child_pids
  child_pids=$(ps -o pid,ppid | awk -v parent=$$ '$2 == parent {print $1}')
  if [[ -n "$child_pids" ]]; then
    log_info "Terminating child processes..."
    for pid in $child_pids; do
      if [[ -n "$pid" ]]; then
        # Try graceful termination first
        kill -TERM "$pid" 2>/dev/null || true
      fi
    done
    
    # Give processes a moment to terminate gracefully
    sleep 2
    
    # Force kill any remaining processes
    for pid in $child_pids; do
      if [[ -n "$pid" ]]; then
        if kill -0 "$pid" 2>/dev/null; then
          kill -9 "$pid" 2>/dev/null || true
        fi
      fi
    done
  fi
  
  # Clean up semaphore directories
  find "${log_dir}" -type d -name ".semaphore_*_${instance_id}" -exec rm -rf {} \; 2>/dev/null || true
  
  # Clean up progress pipe
  rm -f "$progress_pipe" 2>/dev/null || true
  
  # Clean up other temp files
  rm -f "${log_dir}/.interrupt_flag" 2>/dev/null || true
  rm -f "${log_dir}/.pipe_writer_pid" 2>/dev/null || true
  
  log_info "Cleaning up temporary files..."
  find "$temp_dir" -type d -mmin +60 -exec rm -rf {} \; 2>/dev/null || true
}

# Function to get a standardized relative path
get_relative_path() {
  local file_path="$1"
  local base_dir="$2"
  
  # Ensure paths are absolute
  local abs_file_path
  local abs_base_dir
  
  # Get absolute paths, handling errors gracefully
  if command -v realpath &>/dev/null; then
    # Use realpath if available (more reliable)
    abs_file_path=$(realpath "$file_path" 2>/dev/null || echo "$file_path")
    abs_base_dir=$(realpath "$base_dir" 2>/dev/null || echo "$base_dir")
  else
    # Fallback if realpath is not available
    if [[ "$file_path" = /* ]]; then
      abs_file_path="$file_path"
    else
      abs_file_path="$(cd "$(dirname "$file_path")" && pwd)/$(basename "$file_path")"
    fi
    
    if [[ "$base_dir" = /* ]]; then
      abs_base_dir="$base_dir"
    else
      abs_base_dir="$(cd "$base_dir" && pwd)"
    fi
  fi
  
  # Get the directory part of the file path
  local file_dir
  file_dir=$(dirname "$abs_file_path")
  
  # Remove base_dir prefix to get relative path
  local rel_path
  if [[ "$file_dir" == "$abs_base_dir"* ]]; then
    # File is under the base directory
    rel_path="${file_dir#"$abs_base_dir"}"
    # Remove leading slash if present
    rel_path="${rel_path#/}"
  else
    # File is not under base_dir, use just the filename
    rel_path=""
  fi
  
  # Log the path calculation for debugging
  log_debug "Calculated relative path: '$rel_path' for file: $file_path (base: $base_dir)"
  
  echo "$rel_path"
}

# Sort files by size (smallest first)
sort_files_by_size() {
  local files=("$@")
  local temp_file
  temp_file="${temp_dir}/files_with_size.$$"
  
  # Create a temporary file with file sizes
  true > "$temp_file"
  
  for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
      local size
      size=$(stat -f%z "$file" 2>/dev/null || stat --format=%s "$file" 2>/dev/null)
      echo "$size $file" >> "$temp_file"
    fi
  done
  
  # Sort by size and extract just the filenames
  local sorted_files
  sorted_files=$(sort -n < "$temp_file" | cut -d' ' -f2-)
  
  # Clean up
  rm -f "$temp_file"
  
  # Output the sorted files
  echo "$sorted_files"
} 