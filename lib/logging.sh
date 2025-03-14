#!/usr/bin/env bash
#
# logging.sh - Logging functions
#
# This file contains functions for logging, log rotation, and formatting

# Disable shellcheck warnings for variables defined in the main script
# shellcheck disable=SC2154
# Variables from main script: date_format, error_log, output_log, debug_log, conversion_log, debug, verbose_debug, max_log_size

# Function to log error messages
log_error() {
  local message="$1"
  # Separate declaration and assignment to avoid masking return values (SC2155)
  local timestamp
  timestamp=$(date +"$date_format")
  echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" | tee -a "$error_log"
  
  # Check if log rotation is needed
  rotate_log "$error_log"
}

# Function to log warning messages
log_warning() {
  local message="$1"
  # Separate declaration and assignment to avoid masking return values (SC2155)
  local timestamp
  timestamp=$(date +"$date_format")
  echo -e "${YELLOW}[WARNING]${NC} ${timestamp} - $message" | tee -a "$output_log"
  
  # Check if log rotation is needed
  rotate_log "$output_log"
}

# Function to log information messages
log_info() {
  local message="$1"
  # Separate declaration and assignment to avoid masking return values (SC2155)
  local timestamp
  timestamp=$(date +"$date_format")
  echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message" | tee -a "$output_log"
  
  # Check if log rotation is needed
  rotate_log "$output_log"
}

# Function to log success messages
log_success() {
  local message="$1"
  # Separate declaration and assignment to avoid masking return values (SC2155)
  local timestamp
  timestamp=$(date +"$date_format")
  echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message" | tee -a "$output_log"
  
  # Check if log rotation is needed
  rotate_log "$output_log"
}

# Function to log debug messages
log_debug() {
  if [[ "$debug" == true ]]; then
    # Separate declaration and assignment to avoid masking return values (SC2155)
    local timestamp
    timestamp=$(date +"$date_format")
    echo -e "${GRAY}[DEBUG] $timestamp: $*${NC}" | tee -a "$debug_log"
    
    # Add more detailed logging in verbose debug mode
    if [[ "$verbose_debug" == true ]]; then
      # Log current process info
      local pid=$$
      local ppid
      ppid=$(ps -o ppid= -p $$ 2>/dev/null || echo "unknown")
      local cmd
      cmd=$(ps -o command= -p $$ 2>/dev/null || echo "unknown")
      echo -e "${GRAY}[VERBOSE] Process: PID=$pid, PPID=$ppid, CMD=$cmd${NC}" | tee -a "$debug_log"
      
      # Log system resource usage
      local load
      load=$(uptime | sed 's/.*load average: //' 2>/dev/null || echo "unknown")
      local mem
      mem=$(vm_stat 2>/dev/null | grep "Pages free" | awk '{print $3}' | sed 's/\.//' || echo "unknown")
      echo -e "${GRAY}[VERBOSE] System: Load=$load, Free Memory Pages=$mem${NC}" | tee -a "$debug_log"
    fi
    
    # Check if log rotation is needed
    rotate_log "$debug_log"
  fi
}

# Function to log conversion details
log_conversion() {
  local input_file="$1"
  local output_file="$2"
  local status="${3:-SUCCESS}"
  local duration="${4:-0}"
  local output_size="${5:-0}"
  
  # Add debug output to help diagnose issues
  if [[ "$debug" == true ]]; then
    echo -e "${GRAY}[DEBUG] log_conversion called with: input=$input_file, output=$output_file, status=$status, duration=$duration, size=$output_size${NC}" | tee -a "$debug_log"
    echo -e "${GRAY}[DEBUG] log_dir=$log_dir, conversion_log=$conversion_log${NC}" | tee -a "$debug_log"
  fi
  
  # Separate declaration and assignment to avoid masking return values (SC2155)
  local sanitized_input
  sanitized_input=$(sanitize_for_log "$input_file")
  local sanitized_output
  sanitized_output=$(sanitize_for_log "$output_file")
  
  # Separate declaration and assignment to avoid masking return values (SC2155)
  local timestamp
  timestamp=$(date +"$date_format")
  local log_message="$timestamp | $status | ${duration}s | $output_size | $sanitized_input | $sanitized_output"
  
  # Check if conversion_log is set and log_dir exists
  if [[ -z "$conversion_log" ]]; then
    echo -e "${RED}[ERROR] conversion_log is not set${NC}" | tee -a "$debug_log"
    return 1
  fi
  
  if [[ -z "$log_dir" ]]; then
    echo -e "${RED}[ERROR] log_dir is not set${NC}" | tee -a "$debug_log"
    return 1
  fi
  
  if [[ ! -d "$log_dir" ]]; then
    echo -e "${RED}[ERROR] log_dir does not exist: $log_dir${NC}" | tee -a "$debug_log"
    return 1
  fi
  
  # Create lock file directory if it doesn't exist
  if [[ ! -d "$(dirname "${log_dir}/.conversion_log.lock")" ]]; then
    mkdir -p "$(dirname "${log_dir}/.conversion_log.lock")" 2>/dev/null || true
  fi
  
  # Use flock for thread safety when writing to the log file
  {
    flock -w 2 200
    echo "$log_message" >> "$conversion_log"
  } 200>"${log_dir}/.conversion_log.lock" 2>/dev/null || {
    # If flock fails, log the error and try direct write
    echo -e "${RED}[ERROR] flock failed, trying direct write${NC}" | tee -a "$debug_log"
    echo "$log_message" >> "$conversion_log"
  }
  
  # Also log to console if verbose mode is enabled
  if [[ "${verbose:-false}" == "true" ]]; then
    if [[ "$status" == "SUCCESS" ]]; then
      echo -e "${GREEN}[SUCCESS]${RESET} Converted: $sanitized_input -> $sanitized_output (${duration}s, $output_size bytes)"
    elif [[ "$status" == "FAILED" ]]; then
      echo -e "${RED}[FAILED]${RESET} Failed to convert: $sanitized_input (${duration}s)"
    else
      echo -e "${BLUE}[INFO]${RESET} $status: $sanitized_input -> $sanitized_output (${duration}s, $output_size bytes)"
    fi
  fi
  
  # Check if log rotation is needed
  rotate_log "$conversion_log"
}

# Function to rotate log files
rotate_log() {
  local log_file="$1"
  local max_rotated_logs=5  # Limit number of rotated logs
  
  if [[ -f "$log_file" ]]; then
    local file_size
    file_size=$(get_file_size_bytes "$log_file")
    
    if [[ $file_size -gt ${max_log_size:-10485760} ]]; then
      local timestamp
      timestamp=$(date +"%Y%m%d%H%M%S")
      local rotated_log="${log_file}.${timestamp}"
      
      log_debug "Rotating log file: $log_file (size: $(format_file_size "$file_size"))"
      
      # Move current log to rotated log
      mv "$log_file" "$rotated_log"
      
      # Create new empty log file with proper permissions
      touch "$log_file"
      chmod 600 "$log_file"
      
      # Remove old rotated logs if there are too many
      find "$(dirname "$log_file")" -name "$(basename "$log_file").*" -type f | sort -r | tail -n +$((max_rotated_logs + 1)) | while read -r old_log; do
        rm -f "$old_log"
      done
    fi
  fi
}

# Function to get file size in bytes

# Function to format file size for human readability
format_file_size() {
  local size="$1"
  
  if [[ $size -ge 1073741824 ]]; then  # >= 1 GB
    awk "BEGIN {printf \"%.2f GB\", $size/1073741824}"
  elif [[ $size -ge 1048576 ]]; then   # >= 1 MB
    awk "BEGIN {printf \"%.2f MB\", $size/1048576}"
  elif [[ $size -ge 1024 ]]; then      # >= 1 KB
    awk "BEGIN {printf \"%.2f KB\", $size/1024}"
  else                                 # < 1 KB
    echo "${size} bytes"
  fi
}

# Function to sanitize strings for log output
sanitize_for_log() {
  local string="$1"
  
  # Remove control characters
  # Separate declaration and assignment to avoid masking return values (SC2155)
  local sanitized
  sanitized=$(echo "$string" | tr -d $'\001'-$'\037')
  
  # If string is too long, truncate with ellipsis
  local max_length=100
  if [[ ${#sanitized} -gt $max_length ]]; then
    sanitized="${sanitized:0:$((max_length - 3))}..."
  fi
  
  echo "$sanitized"
}

# Function to print a banner
print_banner() {
  echo -e "${GREEN}"
  echo "======================================================================"
  echo "  Document to Markdown Converter - conv2md"
  echo "  Version: 1.5.0"
  echo "  $(date +"$date_format")"
  echo "======================================================================"
  echo -e "${NC}"
}

# Function to print a help message
print_help() {
  cat << EOF
Usage: conv2md.sh [OPTIONS]

Convert documents (Word, PowerPoint, PDF) to Markdown.

Options:
  -i, --input DIR       Input directory containing documents (required)
  -o, --output DIR      Output directory for converted files (required)
  -w, --workers NUM     Maximum number of parallel workers (default: 4)
  -l, --log DIR         Directory for logs (default: ./logs)
  -t, --temp DIR        Directory for temporary files (default: /tmp/conv2md)
  -f, --force           Force conversion even if output file exists
  -r, --resume          Resume from previous checkpoint
  -d, --debug           Enable debug logging
  --skip-word           Skip Word documents (.doc, .docx)
  --skip-powerpoint     Skip PowerPoint documents (.ppt, .pptx)
  --skip-pdf            Skip PDF documents (.pdf)
  -v, --version         Show version information
  -h, --help            Show this help message

Examples:
  conv2md.sh -i ~/Documents -o ~/Documents/markdown -w 8
  conv2md.sh -i ./docs -o ./markdown --skip-pdf -f
  conv2md.sh -i ./sources -o ./output -r -d

EOF
}

# Function to print version information
print_version() {
  echo "conv2md - Document to Markdown Converter"
  echo "Version: 1.5.0"
  echo "Author: Patrick Park"
  echo "License: MIT"
  echo ""
  
  # Show version information for dependencies
  echo "Dependencies:"
  
  # Check for Pandoc
  if command -v pandoc &>/dev/null; then
    echo "  - Pandoc: $(pandoc --version | head -n 1)"
  else
    echo "  - Pandoc: Not installed"
  fi
  
  # Check for MarkItDown
  if command -v markitdown &>/dev/null; then
    echo "  - MarkItDown: $(markitdown --version 2>&1 | head -n 1)"
  else
    echo "  - MarkItDown: Not installed"
  fi
  
  # Check for marker_single
  if command -v marker_single &>/dev/null; then
    echo "  - marker_single: Installed"
  else
    echo "  - marker_single: Not installed"
  fi
  
  # Check for GNU Parallel
  if command -v parallel &>/dev/null; then
    echo "  - GNU Parallel: $(parallel --version | head -n 1)"
  else
    echo "  - GNU Parallel: Not installed"
  fi
}

# NOTE: get_file_size function has been moved to utils.sh for centralization
# Use the format_file_size function from utils.sh instead

# Function to get file modification time in a cross-platform way
get_file_modification_time() {
  local file="$1"
  
  if is_macos; then
    # macOS
    stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null
  else
    # Linux and others
    stat -c "%y" "$file" 2>/dev/null | cut -d. -f1
  fi
} 