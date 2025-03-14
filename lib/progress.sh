#!/usr/bin/env bash
#
# progress.sh - Simplified progress logging
#
# This file contains minimal functions for progress logging without complex display

# Function to write progress information to log
write_to_progress_pipe() {
  local message="$1"
  
  # Extract status and file information from the message
  if [[ "$message" =~ ^([^:]+):[^:]+:[^:]+:[^:]+:(.*)$ ]]; then
    local status="${BASH_REMATCH[1]}"
    local file="${BASH_REMATCH[2]}"
    
    # Log the progress information based on status
    case "$status" in
      "complete")
        log_info "Completed conversion of: $file"
        ;;
      "failed")
        log_warning "Failed to convert: $file"
        ;;
      "skipped")
        log_info "Skipped file: $file"
        ;;
      "processing")
        log_debug "Processing file: $file"
        ;;
      "count")
        # Ignore count messages
        ;;
      *)
        log_debug "Progress: $message"
        ;;
    esac
  else
    log_debug "Progress: $message"
  fi
}

# Function to format elapsed time (used for logging)
format_elapsed_time() {
  local seconds="$1"
  local hours=$((seconds / 3600))
  local minutes=$(((seconds % 3600) / 60))
  local secs=$((seconds % 60))
  
  if [[ $hours -gt 0 ]]; then
    printf "%02d:%02d:%02d" "$hours" "$minutes" "$secs"
  else
    printf "%02d:%02d" "$minutes" "$secs"
  fi
}

# NOTE: format_size function has been moved to utils.sh for centralization
# Use the format_file_size function from utils.sh instead 