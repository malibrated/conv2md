#!/usr/bin/env bash
#
# config.sh - Configuration settings for conv2md
#
# This file contains all configuration settings, constants,
# and default values for the conversion process.

# Version information
VERSION="1.0.0"

# System limits
# Limit maximum system load to avoid overwhelming the system
MAX_LOAD=10.0

# Memory limits (in KB)
# This prevents memory exhaustion - conservative for unified memory
MAX_RAM_PER_PROCESS=6000000  # 6GB per process
PDF_MEMORY_LIMIT=5120        # 5GB default for PDF processing

# Timeout values in seconds
WORD_TIMEOUT=900       # 15 minutes
POWERPOINT_TIMEOUT=900 # 15 minutes
PDF_TIMEOUT=2700       # 45 minutes

# File type flags (will be set via command line options)
skip_pdf=false
skip_word=false
skip_powerpoint=false
force_conversion=false
resume_from_checkpoint=false

# Path settings (will be set during initialization)
input_dir=""
output_dir=""
log_dir=""
temp_dir=""
conversion_log=""
error_log=""
output_log=""
checkpoint_file=""

# Maximum log size in bytes before rotation (default: 10MB)
max_log_size=10485760

# Parallel processing settings
max_workers=4  # Default, will be updated based on CPU count

# Progress tracking variables
total_files=0
processed_files=0
failed_files=0
skipped_files=0
start_time=0
progress_displayed=false
progress_reader_pid=""

# Script instance identifier to prevent conflicts
instance_id="$$_$(date +%s)"

# Define the timeout command based on OS
if [[ "$(uname)" == "Darwin" ]]; then
  # Check if gtimeout exists (requires coreutils)
  if command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
  else
    echo "Warning: gtimeout not found. Install coreutils with 'brew install coreutils'"
    echo "Continuing without timeout protection. Long-running processes will not be terminated."
    TIMEOUT_CMD="cat"  # Use a dummy command that passes through
  fi
else
  TIMEOUT_CMD="timeout"
fi

# Set marker related variables
marker_cmd="stdout"  # Default, will be updated after testing

# Setup colored output if terminal supports it
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  PURPLE='\033[0;35m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  PURPLE=""
  CYAN=""
  BOLD=""
  RESET=""
fi

# Array to store information about failed files for summary
declare -a failed_file_list=()

# Initialize pids array
declare -a pids=() 