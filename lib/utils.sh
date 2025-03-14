#!/usr/bin/env bash
#
# utils.sh - Utility functions for conv2md
#
# This file contains common utility functions used throughout
# the conversion process.

# Platform detection helper functions
# These functions help avoid repeating platform detection logic throughout the codebase

# Check if running on macOS
is_macos() {
  [[ "$(uname)" == "Darwin" ]]
}

# Check if running on Linux
is_linux() {
  [[ "$(uname)" == "Linux" ]]
}

# Print a banner with the app name
print_banner() {
  local app_name="$1"
  local term_width
  term_width=$(tput cols 2>/dev/null || echo 80)
  local banner_width=$((term_width - 4))
  local pad_len=$(( (banner_width - ${#app_name}) / 2 ))
  
  printf "\n%s\n" "${BOLD}${CYAN}$(printf '=%.0s' $(seq 1 "$term_width"))${RESET}"
  printf "%s%s%s\n" "${BOLD}${CYAN}||${RESET}" "$(printf ' %.0s' $(seq 1 "$pad_len"))${BOLD}${app_name}$(printf ' %.0s' $(seq 1 "$pad_len"))" "${BOLD}${CYAN}||${RESET}"
  printf "%s\n\n" "${BOLD}${CYAN}$(printf '=%.0s' $(seq 1 "$term_width"))${RESET}"
}

# Format date in a cross-platform way
format_date() {
  if is_macos; then
    date "+%Y-%m-%d %H:%M:%S"  # macOS/BSD format
  else
    date "+%Y-%m-%d %H:%M:%S"  # Linux/GNU format
  fi
}

# Function to get file size in a cross-platform way
get_file_size() {
  local file="$1"
  if is_macos; then
    stat -f%z "$file" 2>/dev/null
  else
    stat -c%s "$file" 2>/dev/null
  fi
}

# Function to get file size in bytes with fallback mechanisms
get_file_size_bytes() {
  local file="$1"
  local size=0
  
  if [[ ! -f "$file" ]]; then
    echo "0"
    return
  fi
  
  if is_macos; then
    # macOS
    size=$(stat -f%z "$file" 2>/dev/null)
  elif is_linux; then
    # Linux
    size=$(stat -c%s "$file" 2>/dev/null)
  else
    # Fallback using wc -c
    size=$(wc -c < "$file" 2>/dev/null | tr -d ' ')
  fi
  
  echo "${size:-0}"
}

# Function to convert bytes to KB with decimal precision
bytes_to_kb() {
  local bytes="$1"
  local kb
  
  # Use awk for floating point calculation
  kb=$(awk "BEGIN {printf \"%.2f\", $bytes/1024}")
  
  echo "$kb"
}

# Function to convert bytes to MB with decimal precision
bytes_to_mb() {
  local bytes="$1"
  local mb
  
  # Use awk for floating point calculation
  mb=$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}")
  
  echo "$mb"
}

# Function to convert bytes to GB with decimal precision
bytes_to_gb() {
  local bytes="$1"
  local gb
  
  # Use awk for floating point calculation
  gb=$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}")
  
  echo "$gb"
}

# Function to format file size for human readability
format_file_size() {
  local size_bytes="$1"
  
  if [[ $size_bytes -lt 1024 ]]; then
    echo "${size_bytes} B"
  elif [[ $size_bytes -lt 1048576 ]]; then
    echo "$(bytes_to_kb "$size_bytes") KB"
  elif [[ $size_bytes -lt 1073741824 ]]; then
    echo "$(bytes_to_mb "$size_bytes") MB"
  else
    echo "$(bytes_to_gb "$size_bytes") GB"
  fi
}

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${RESET} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${RESET} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${RESET} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${RESET} $1"
}

# Log a debug message
log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo -e "${PURPLE}[DEBUG]${RESET} $1" >&2
  fi
}

# Function to sanitize a string for safe logging
sanitize_for_log() {
  local string="$1"
  # Replace control characters with their escaped representations
  echo "$string" | tr -d '\000-\011\013-\037'
}

# Function to sanitize a filename for safe file operations
sanitize_filename() {
  local name="$1"
  
  # Escape special characters
  local escaped_name
  escaped_name="${name//&/\\&}"
  
  # Replace non-alphanumeric characters with underscores
  local with_underscores
  with_underscores="${escaped_name//[^a-zA-Z0-9_.-]/_}"
  
  echo "$with_underscores"
}

# Log rotation is now handled by the rotate_log function in logging.sh
# This ensures consistent log rotation across the codebase

# Function to log successful conversions
# DEPRECATED: This function is now defined in logging.sh with more parameters
# log_conversion() {
#   local input_file="$1"
#   local output_file="$2"
#   {
#     flock -w 2 200
#     local sanitized_input=$(sanitize_for_log "$input_file")
#     local sanitized_output=$(sanitize_for_log "$output_file")
#     echo "$(format_date) | $sanitized_input -> $sanitized_output" >> "$conversion_log"
#     
#     # Rotate the log if necessary
#     rotate_log "$conversion_log"
#   } 200>"${log_dir}/.log.lock"
# }

# Function to limit process resource usage with ulimit
set_process_limits() {
  # Set maximum memory usage (in KB)
  ulimit -v "$MAX_RAM_PER_PROCESS" 2>/dev/null || true
  
  # Set maximum CPU time (in seconds) - prevent infinite loops
  ulimit -t 7200 2>/dev/null || true  # 2 hour max CPU time
  
  # Set maximum file size (prevent massive temporary files)
  ulimit -f 1048576 2>/dev/null || true  # 1GB max file size
}

# Function to check system load and wait if necessary
check_system_load() {
  if command -v uptime >/dev/null 2>&1 && command -v bc >/dev/null 2>&1; then
    local load
    # Extract the 1-minute load average (different format on macOS vs Linux)
    if [[ "$(uname)" == "Darwin" ]]; then
      load=$(uptime | sed 's/.*load averages: \([0-9.]*\).*/\1/g')
    else
      load=$(uptime | awk -F'[, :]' '{print $(NF-2)}')
    fi
    
    # Check if load is numerically greater than MAX_LOAD
    if (( $(echo "$load > $MAX_LOAD" | bc -l) )); then
      log_info "System load is high ($load). Pausing for 5 seconds..."
      rotate_log "$output_log"
      sleep 5
      return 1  # Return non-zero to indicate we had to wait
    fi
  fi
  return 0  # Return zero if load is acceptable or can't be checked
}

# Function to check memory usage and wait if necessary
check_memory() {
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS memory check
    local free_mem=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
    local page_size=$(sysctl -n hw.pagesize)
    local free_mem_kb=$((free_mem * page_size / 1024))
    
    if [[ $free_mem_kb -lt 4194304 ]]; then  # Less than 4GB free
      log_info "System memory is low ($free_mem_kb KB free). Pausing for 3 seconds..."
      rotate_log "$output_log"
      sleep 3
      return 1
    fi
  else
    # Linux memory check
    if command -v free >/dev/null 2>&1; then
      local free_mem=$(free -k | grep "Mem:" | awk '{print $7}')
      
      if [[ $free_mem -lt 4194304 ]]; then  # Less than 4GB free
        log_info "System memory is low ($free_mem KB free). Pausing for 3 seconds..."
        rotate_log "$output_log"
        sleep 3
        return 1
      fi
    fi
  fi
  return 0
}

# Function to get user yes/no response
ask_yes_no() {
  local prompt="$1"
  local response
  
  echo -n "$prompt (y/n): "
  read -r response
  
  if [[ "$response" == "y" || "$response" == "Y" ]]; then
    return 0  # True
  else
    return 1  # False
  fi
}

# Function to handle signals
handle_signal() {
  local signal=$1
  echo -e "\nReceived signal: $signal"
  echo "Initiating graceful shutdown..."
  
  # Create interrupt flag to signal processes to stop
  touch "${log_dir}/.interrupt_flag"
  
  # Call cleanup
  cleanup
  
  # Exit with appropriate code
  exit 1
}

# Function to clean up zombie processes
cleanup_zombies() {
  log_debug "Checking for zombie processes..."
  
  # Find zombie processes related to conv2md
  # Use pgrep instead of grepping ps output
  local zombies
  if command -v pgrep >/dev/null 2>&1; then
    zombies=$(pgrep -f "conv2md" | xargs -I{} ps -o pid,state -p {} | grep "Z" | awk '{print $1}')
  else
    zombies=$(ps -o pid,state,command | grep "[Z].*conv2md" | awk '{print $1}')
  fi
  
  if [[ -z "$zombies" ]]; then
    log_debug "No zombie processes found"
    return 0
  fi
  
  log_warning "Found zombie processes: $zombies"
  
  # Try to kill parent processes of zombies
  for pid in $zombies; do
    local ppid
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null)
    
    if [[ -n "$ppid" ]]; then
      kill -TERM "$ppid" 2>/dev/null || true
      log_debug "Sent TERM signal to parent process $ppid of zombie $pid"
    fi
  done
  
  return 0
}

# Function to parse command line arguments
parse_arguments() {
  # First argument is the input directory, rest are options
  input_dir="${1:-.}"  # Default to current directory if not provided
  shift 1 || true     # Shift past the first argument
  
  # Convert to absolute path
  input_dir=$(cd "$input_dir" && pwd)
  
  # Process remaining options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -force)
        force_conversion=true
        shift
        ;;
      -skip_pdf)
        skip_pdf=true
        shift
        ;;
      -skip_word)
        skip_word=true
        shift
        ;;
      -skip_powerpoint)
        skip_powerpoint=true
        shift
        ;;
      -resume)
        resume_from_checkpoint=true
        shift
        ;;
      -workers)
        max_workers="$2"
        # Validate and cap the worker count
        if ! [[ "$max_workers" =~ ^[0-9]+$ ]]; then
          log_error "Worker count must be a number"
          exit 1
        fi
        # More conservative cap for unified memory
        [ "$max_workers" -gt 12 ] && max_workers=10
        shift 2
        ;;
      -memory)
        memory_limit="$2"
        shift 2
        ;;
      -pdf_memory)
        PDF_MEMORY_LIMIT="$2"
        shift 2
        ;;
      -word_timeout)
        WORD_TIMEOUT="$2"
        shift 2
        ;;
      -powerpoint_timeout)
        POWERPOINT_TIMEOUT="$2"
        shift 2
        ;;
      -pdf_timeout)
        PDF_TIMEOUT="$2"
        shift 2
        ;;
      -max_log_size)
        max_log_size="$2"
        shift 2
        ;;
      -debug)
        DEBUG=true
        shift
        ;;
      -*)
        log_error "Unknown parameter passed: $1"
        echo "Usage: $0 [dir] [-force] [-skip_pdf] [-skip_word] [-skip_powerpoint] [-resume] [-workers N]"
        echo "       [-memory MB] [-pdf_memory MB] [-word_timeout SEC] [-powerpoint_timeout SEC] [-pdf_timeout SEC] [-max_log_size BYTES] [-debug]"
        exit 1
        ;;
      *)
        log_error "Unknown parameter passed: $1"
        echo "Usage: $0 [dir] [-force] [-skip_pdf] [-skip_word] [-skip_powerpoint] [-resume] [-workers N]"
        echo "       [-memory MB] [-pdf_memory MB] [-word_timeout SEC] [-powerpoint_timeout SEC] [-pdf_timeout SEC] [-max_log_size BYTES] [-debug]"
        exit 1
        ;;
    esac
  done
}

# Initialize the environment
initialize_environment() {
  # Only set output directory if it's not already set
  if [[ -z "$output_dir" ]]; then
    # Create output directory with proper structure
    # First, get the base name of the input directory
    local input_dir_basename=$(basename "$input_dir")
    
    # Set the output directory to "converted_markdown" at the same level as input_dir
    output_dir="$(dirname "$input_dir")/converted_markdown"
    mkdir -p "$output_dir"
    
    # Create a subdirectory with the same name as the input directory
    output_dir="${output_dir}/${input_dir_basename}"
    mkdir -p "$output_dir"
    
    log_debug "Input directory: $input_dir"
    log_debug "Output directory structure: $output_dir"
  else
    log_debug "Using existing output directory: $output_dir"
    mkdir -p "$output_dir"
  fi
  
  # Create log directory with secure permissions
  log_dir="${output_dir}/logs"
  mkdir -p "$log_dir"
  chmod 700 "$log_dir"  # Restrict permissions for security
  
  # Set log files
  conversion_log="${log_dir}/conversion_log.txt"
  error_log="${log_dir}/errors.log"
  output_log="${log_dir}/output.log"
  
  # Initialize log files
  touch "$conversion_log" "$error_log" "$output_log"
  chmod 600 "$conversion_log" "$error_log" "$output_log"  # Secure the log files
  
  # Set checkpoint file
  checkpoint_file="${log_dir}/.checkpoint"
  touch "$checkpoint_file"
  chmod 600 "$checkpoint_file"
  
  # Set progress pipe path
  progress_pipe="${log_dir}/${PROGRESS_PIPE_NAME}"
  
  # Set temp directory
  temp_dir="${log_dir}/temp"
  mkdir -p "$temp_dir"
  chmod 700 "$temp_dir"
  export TMPDIR="$temp_dir"  # Make temp dir available to child processes
  
  # Set number of workers based on CPU count
  available_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
  max_workers=$((available_cores - 2))  # Leave 2 cores free for system
  [ "$max_workers" -lt 1 ] && max_workers=1
  [ "$max_workers" -gt 12 ] && max_workers=10  # Cap at 10 for unified memory system
  
  # Add marker path to PATH if needed
  if [[ -d "/opt/homebrew/Caskroom/miniconda/base/bin" ]]; then
    export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
  fi
  
  # Set up signal handlers
  trap 'handle_signal INT' INT
  trap 'handle_signal TERM' TERM
  trap 'cleanup' EXIT
  
  # Start a background process to periodically clean up zombies
  (
    while true; do
      # Exit if interrupt flag is set
      if [[ -f "${log_dir}/.interrupt_flag" ]]; then
        exit 0
      fi
      
      # Clean up zombies every 30 seconds
      cleanup_zombies
      sleep 30
    done
  ) &
  zombie_cleaner_pid=$!
  
  # Initialize checkpoint file
  if [[ "$resume_from_checkpoint" != true ]]; then
    # Clear checkpoint file if not resuming
    true > "$checkpoint_file"
  fi
  
  # Print debugging information
  log_debug "Input directory: $input_dir"
  log_debug "Skip Word: $skip_word, Skip PowerPoint: $skip_powerpoint, Skip PDF: $skip_pdf"
}

# Function to process a list of files in parallel using semaphores
# This is a utility function to centralize parallel processing logic
process_files_in_parallel() {
  local file_list="$1"
  local job_type="$2"             # Type of job (e.g., "Word", "PDF") for logging
  local max_workers="$3"          # Maximum parallel workers
  local semaphore_dir="$4"        # Directory for semaphore files
  local process_function="$5"     # Function name to call for each file
  shift 5                         # Shift parameters to pass any additional args to process_function

  # Ensure semaphore directory exists
  if [[ ! -d "$semaphore_dir" ]]; then
    rm -rf "$semaphore_dir" 2>/dev/null || true
    mkdir -p "$semaphore_dir" || { 
      log_error "Failed to create semaphore directory: $semaphore_dir"
      return 1
    }
    log_debug "Semaphore directory created: $semaphore_dir"
  fi

  # Track all background PIDs
  declare -a bg_pids=()

  # Count files to process
  local file_count
  file_count=$(wc -l < "$file_list")
  log_info "Processing $file_count $job_type files in parallel with $max_workers workers"

  # Initialize counter and resource tracking variables
  local processed=0
  local last_resource_check
  last_resource_check=$(date +%s)
  
  # Track batch processing times for adaptive sizing
  local last_batch_start_time
  local last_batch_end_time
  local last_batch_duration=0
  local optimal_batch_duration=30  # Target 30 seconds per batch
  
  local batch_start=1
  # Use a smaller batch size for PDF files or in conservative mode
  local current_batch_size
  if [[ "$job_type" == "PDF" ]]; then
    current_batch_size=${batch_size:-3}  # Smaller default for PDFs
  elif [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
    current_batch_size=${batch_size:-3}  # Smaller default in conservative mode
  else
    current_batch_size=${batch_size:-5}  # Default batch size
  fi
  
  # Process files in batches to better control resource usage
  while [[ $batch_start -le $file_count ]]; do
    # Record batch start time for adaptive sizing
    last_batch_start_time=$(date +%s)
    
    # Calculate batch end
    local batch_end=$((batch_start + current_batch_size - 1))
    [[ $batch_end -gt $file_count ]] && batch_end=$file_count
    
    log_debug "Processing batch from $batch_start to $batch_end (total files: $file_count)"
    
    # Extract current batch of files
    local batch_files=()
    local i=1
    while read -r file; do
      if [[ $i -ge $batch_start && $i -le $batch_end ]]; then
        batch_files+=("$file")
      fi
      i=$((i + 1))
      [[ $i -gt $batch_end ]] && break
    done < "$file_list"
    
    # Check system resources before starting a new batch
    if type -t should_throttle &>/dev/null && [[ "${throttle_enabled:-true}" == "true" ]]; then
      if should_throttle; then
        log_warning "System resources constrained before batch. Throttling processing."
        # Reduce batch size temporarily
        current_batch_size=$((current_batch_size / 2))
        [[ $current_batch_size -lt 1 ]] && current_batch_size=1
        log_info "Reduced batch size to $current_batch_size due to resource constraints"
        sleep 10  # Pause to let system recover
        
        # Recalculate batch end with new batch size
        batch_end=$((batch_start + current_batch_size - 1))
        [[ $batch_end -gt $file_count ]] && batch_end=$file_count
        
        # Re-extract batch files with new batch size
        batch_files=()
        i=1
        while read -r file; do
          if [[ $i -ge $batch_start && $i -le $batch_end ]]; then
            batch_files+=("$file")
          fi
          i=$((i + 1))
          [[ $i -gt $batch_end ]] && break
        done < "$file_list"
      fi
    fi
    
    # Process each file in the current batch
    for file in "${batch_files[@]}"; do
      [ -z "$file" ] && continue

      # Check for interrupt flag
      if [[ -f "${log_dir:-/tmp}/.interrupt_flag" ]]; then
        log_debug "Interrupt flag detected, breaking processing of $job_type files"
        break 2  # Break out of both loops
      fi

      # Update progress
      processed=$((processed + 1))
      log_info "Processing $job_type file $processed of $file_count: $(basename "$file")"

      # Check system resources periodically
      local current_time
      current_time=$(date +%s)
      if [[ $((current_time - last_resource_check)) -ge ${resource_check_interval:-30} ]]; then
        log_debug "Performing periodic resource check"
        last_resource_check=$current_time
        
        # Clean up any stale processes
        if type -t cleanup_stale_processes &>/dev/null; then
          cleanup_stale_processes "$semaphore_dir" "${stale_process_timeout:-300}"
        fi
        
        # Check if we should throttle based on system resources
        if type -t should_throttle &>/dev/null && [[ "${throttle_enabled:-true}" == "true" ]]; then
          if should_throttle; then
            log_warning "System resources constrained. Throttling processing."
            # Reduce batch size temporarily
            current_batch_size=$((current_batch_size / 2))
            [[ $current_batch_size -lt 1 ]] && current_batch_size=1
            log_info "Reduced batch size to $current_batch_size due to resource constraints"
            sleep 10  # Pause to let system recover
          else
            # If resources are good, gradually increase batch size back to normal
            if [[ "$job_type" == "PDF" ]]; then
              # For PDFs, be more conservative with batch size increases
              if [[ $current_batch_size -lt ${batch_size:-3} ]]; then
                current_batch_size=$((current_batch_size + 1))
                log_info "Increased batch size to $current_batch_size as resources improved"
              fi
            elif [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
              # In conservative mode, be more cautious with batch size increases
              if [[ $current_batch_size -lt ${batch_size:-3} ]]; then
                current_batch_size=$((current_batch_size + 1))
                log_info "Increased batch size to $current_batch_size as resources improved"
              fi
            else
              # Standard mode
              if [[ $current_batch_size -lt ${batch_size:-5} ]]; then
                current_batch_size=$((current_batch_size + 1))
                log_info "Increased batch size to $current_batch_size as resources improved"
              fi
            fi
          fi
        fi
      fi

      # Wait if we've reached the maximum number of workers
      local active_jobs
      active_jobs=$(find "$semaphore_dir" -type f 2>/dev/null | wc -l)
      log_debug "Current active jobs: $active_jobs (max allowed: $max_workers)"

      # Wait loop with timeout for active jobs to complete
      local wait_attempts=0
      while [[ $active_jobs -ge $max_workers ]]; do
        log_debug "Waiting for a job to complete (active: $active_jobs, max: $max_workers)"

        # Wait for any job to complete with a timeout
        if wait -n 2>/dev/null; then
          log_debug "A background job completed"
        else
          # If wait -n fails or times out, sleep briefly
          sleep 2
        fi

        # Recount active jobs
        active_jobs=$(find "$semaphore_dir" -type f 2>/dev/null | wc -l)
        log_debug "Updated active jobs count: $active_jobs"

        # Check for stalled jobs and clean up if necessary
        wait_attempts=$((wait_attempts + 1))
        if [[ $wait_attempts -ge 15 ]]; then  # 30 seconds (15 * 2 seconds)
          log_warning "Waiting for jobs to complete for 30 seconds. Checking for stalled jobs..."

          # Use the cleanup function if available
          if type -t cleanup_stale_processes &>/dev/null; then
            cleanup_stale_processes "$semaphore_dir" 120  # Use shorter timeout for stalled jobs
          else
            # Check for stale semaphores (files without corresponding processes)
            shopt -s nullglob  # Set nullglob to handle empty glob patterns
            for sem_file in "$semaphore_dir"/*.sem; do
              [[ -f "$sem_file" ]] || continue

              local sem_pid
              sem_pid=$(cat "$sem_file" 2>/dev/null || echo "")
              if [[ -n "$sem_pid" ]] && ! kill -0 "$sem_pid" 2>/dev/null; then
                log_warning "Found stale semaphore for PID $sem_pid. Removing..."
                rm -f "$sem_file" 2>/dev/null || true
              fi
            done
            shopt -u nullglob  # Unset nullglob after the loop
          fi

          # Recount active jobs after cleanup
          active_jobs=$(find "$semaphore_dir" -type f 2>/dev/null | wc -l)
          log_debug "Active jobs after stale semaphore cleanup: $active_jobs"
          wait_attempts=0
        fi
      done

      # Start a new subprocess for this file
      (
        log_debug "Starting subprocess for file: $file (PID: $$)"

        # Create a unique semaphore file for this process
        local sem_file="${semaphore_dir}/$$.sem"
        log_debug "Creating semaphore file: $sem_file"
        echo $$ > "$sem_file"

        # Set up trap to ensure semaphore is removed on exit
        trap 'rm -f "${sem_file:-}" 2>/dev/null || true; log_debug "Semaphore removed: ${sem_file:-}"' EXIT INT TERM

        # Set resource limits for this process if the function exists
        if type -t set_process_limits &>/dev/null; then
          set_process_limits
        fi

        # Start memory monitor in background if the function exists
        local memory_monitor_pid=""
        if type -t monitor_process_memory &>/dev/null; then
          # Set memory limit based on file type and conservative mode
          local memory_limit_mb
          if [[ "$job_type" == "PDF" ]]; then
            # PDFs need more memory
            memory_limit_mb=4096  # 4GB for PDFs
          elif [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
            # More conservative memory limit in conservative mode
            memory_limit_mb=3072  # 3GB in conservative mode
          else
            # Standard memory limit
            memory_limit_mb=4096  # 4GB standard
          fi
          
          # Start memory monitor in background
          monitor_process_memory $$ "$memory_limit_mb" 5 &
          memory_monitor_pid=$!
          log_debug "Started memory monitor with PID $memory_monitor_pid"
        fi

        # Call the process function with the file and any additional arguments
        if ! "$process_function" "$file" "$@"; then
          log_warning "Failed to process $job_type file: $file"
        fi

        # Kill memory monitor if it's running
        if [[ -n "$memory_monitor_pid" ]]; then
          kill -15 "$memory_monitor_pid" 2>/dev/null || true
          log_debug "Terminated memory monitor with PID $memory_monitor_pid"
        fi

        log_debug "Subprocess completed for file: $file (PID: $$)"
        # Explicitly remove semaphore file
        rm -f "$sem_file" 2>/dev/null || true
      ) &

      # Store the background PID
      bg_pids+=($!)
      log_debug "Started background job with PID: ${bg_pids[-1]} for file: $file"

      # Brief pause between job starts to prevent overwhelming the system
      sleep 0.5
    done
    
    # Record batch end time and calculate duration
    last_batch_end_time=$(date +%s)
    last_batch_duration=$((last_batch_end_time - last_batch_start_time))
    
    # Adaptive batch sizing based on previous batch duration
    if [[ $last_batch_duration -gt 0 ]]; then
      log_debug "Last batch took $last_batch_duration seconds to process"
      
      # If batch took too long, reduce batch size
      if [[ $last_batch_duration -gt $((optimal_batch_duration * 2)) ]]; then
        # Batch took more than 2x the optimal time, reduce size significantly
        current_batch_size=$((current_batch_size * 2 / 3))
        [[ $current_batch_size -lt 1 ]] && current_batch_size=1
        log_info "Batch took too long ($last_batch_duration seconds), reducing batch size to $current_batch_size"
      # If batch was too quick, increase batch size
      elif [[ $last_batch_duration -lt $((optimal_batch_duration / 2)) && $current_batch_size -lt 20 ]]; then
        # Batch was less than half the optimal time, increase size
        current_batch_size=$((current_batch_size * 3 / 2))
        
        # Cap batch size based on file type
        local max_batch_size
        if [[ "$job_type" == "PDF" ]]; then
          max_batch_size=10  # Cap PDF batches at 10
        elif [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
          max_batch_size=15  # Cap at 15 in conservative mode
        else
          max_batch_size=20  # Cap at 20 in standard mode
        fi
        
        [[ $current_batch_size -gt $max_batch_size ]] && current_batch_size=$max_batch_size
        log_info "Batch completed quickly ($last_batch_duration seconds), increasing batch size to $current_batch_size"
      fi
    fi
    
    # Move to the next batch
    batch_start=$((batch_end + 1))
    
    # Wait for the current batch to complete if we're processing large files
    # This helps prevent memory exhaustion with large files
    if [[ "$job_type" == "PDF" || "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
      log_info "Waiting for current batch of $job_type files to complete before starting next batch"
      for pid in "${bg_pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
          wait "$pid" 2>/dev/null || true
        fi
      done
      # Clear the PIDs array for the next batch
      bg_pids=()
    fi
  done

  # Wait for all remaining jobs to complete
  log_debug "Waiting for all background jobs to complete for $job_type files..."
  for pid in "${bg_pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      log_debug "Waiting for PID $pid to complete"
      wait "$pid" 2>/dev/null || true
    fi
  done

  # Clean up semaphore directory
  rm -rf "$semaphore_dir" 2>/dev/null || true
  
  log_info "Completed processing $file_count $job_type files"
  return 0
}

# Function to process file batches in parallel (for optimized processing)
process_batches_in_parallel() {
  local batches_array_var="$1"    # Name of the array variable containing batches
  local job_type="$2"             # Type of job (e.g., "PDF") for logging
  local max_workers="$3"          # Maximum parallel workers
  local semaphore_dir="$4"        # Directory for semaphore files
  local process_function="$5"     # Function name to call for each batch
  shift 5                         # Shift parameters to pass any additional args to process_function

  # Reference to the array (indirect reference)
  # This creates a local array that references the array passed by name
  declare -n batches="$batches_array_var"
  
  # Ensure semaphore directory exists
  if [[ ! -d "$semaphore_dir" ]]; then
    rm -rf "$semaphore_dir" 2>/dev/null || true
    mkdir -p "$semaphore_dir" || { 
      log_error "Failed to create semaphore directory: $semaphore_dir"
      return 1
    }
    log_debug "Semaphore directory created: $semaphore_dir"
  fi

  # Track all background PIDs
  declare -a bg_pids=()

  # Number of batches
  local batch_count=${#batches[@]}
  log_info "Processing $batch_count $job_type batches in parallel with $max_workers workers"

  # Process each batch
  for ((i=0; i<batch_count; i++)); do
    # Check for interrupt flag
    if [[ -f "${log_dir}/.interrupt_flag" ]]; then
      log_debug "Interrupt flag detected, breaking batch processing of $job_type files"
      break
    fi

    log_info "Processing $job_type batch $((i+1)) of $batch_count"

    # Wait if we've reached the maximum number of workers
    local active_jobs
    active_jobs=$(find "$semaphore_dir" -type f 2>/dev/null | wc -l)
    log_debug "Current active jobs: $active_jobs (max allowed: $max_workers)"

    # Wait loop for active jobs to complete
    while [[ $active_jobs -ge $max_workers ]]; do
      log_debug "Waiting for a job to complete (active: $active_jobs, max: $max_workers)"

      # Wait for any job to complete
      if wait -n 2>/dev/null; then
        log_debug "A background job completed"
      else
        sleep 2
      fi

      # Recount active jobs
      active_jobs=$(find "$semaphore_dir" -type f 2>/dev/null | wc -l)
    done

    # Start a new subprocess for this batch
    (
      log_debug "Starting subprocess for batch $((i+1)) (PID: $$)"

      # Create a unique semaphore file for this process
      local sem_file="${semaphore_dir}/$$.sem"
      log_debug "Creating semaphore file: $sem_file"
      echo $$ > "$sem_file"

      # Set up trap to ensure semaphore is removed on exit
      trap 'rm -f "${sem_file:-}" 2>/dev/null || true; log_debug "Semaphore removed: ${sem_file:-}"' EXIT INT TERM

      # Call the process function with the batch and any additional arguments
      if ! "$process_function" "${batches[$i]}" "$@"; then
        log_warning "Failed to process $job_type batch $((i+1))"
      fi

      log_debug "Subprocess completed for batch $((i+1)) (PID: $$)"
      # Explicitly remove semaphore file
      rm -f "$sem_file" 2>/dev/null || true
    ) &

    # Store the background PID
    bg_pids+=($!)
    log_debug "Started background job with PID: ${bg_pids[-1]} for batch $((i+1))"
  done

  # Wait for all jobs to complete
  log_debug "Waiting for all background jobs to complete for $job_type batches..."
  for pid in "${bg_pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      log_debug "Waiting for PID $pid to complete"
      wait "$pid" 2>/dev/null || true
    fi
  done

  # Clean up semaphore directory
  rm -rf "$semaphore_dir" 2>/dev/null || true
  
  log_info "Completed processing $batch_count $job_type batches"
  return 0
}

# Check if a file is in the checkpoint file
is_in_checkpoint() {
  local file="$1"
  
  if [[ ! -f "$checkpoint_file" ]]; then
    return 1
  fi
  
  if grep -q "^$file$" "$checkpoint_file" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Check if a file needs conversion
needs_conversion() {
  local file="$1"
  
  # If resume_from_checkpoint is not enabled, always convert
  if [[ "$resume_from_checkpoint" != true ]]; then
    return 0
  fi
  
  # If the file is in the checkpoint, it doesn't need conversion
  if is_in_checkpoint "$file"; then
    return 1
  fi
  
  # If the output file exists and is newer than the input file, it doesn't need conversion
  local base_name
  base_name=$(basename "$file")
  # shellcheck disable=SC2034
  # extension is used indirectly in determining the output path
  local extension="${base_name##*.}"
  local name_no_ext="${base_name%.*}"
  
  # Replace spaces with underscores in the base name
  local sanitized_name
  sanitized_name=$(echo "$name_no_ext" | tr ' ' '_')
  
  # Calculate relative path from input_dir
  local rel_path=""
  if [[ "$file" == "$input_dir"* ]]; then
    rel_path="${file#"$input_dir"}"
    rel_path="${rel_path#/}"
  fi
  
  # Construct the output file path
  local rel_dir=""
  if [[ -n "$rel_path" ]]; then
    rel_dir=$(dirname "$rel_path")
    if [[ "$rel_dir" == "." ]]; then
      rel_dir=""
    else
      rel_dir="$rel_dir/"
    fi
  fi
  
  local output_file="$output_dir/${rel_dir}${sanitized_name}.md"
  
  if [[ -f "$output_file" ]]; then
    # Check if output file is newer than input file
    if [[ "$output_file" -nt "$file" ]]; then
      # If using SQLite, add to database
      if [[ -n "$checkpoint_db" && -f "$checkpoint_db" ]]; then
        add_to_checkpoint_db "$file" 0
      # Otherwise, if using text-based checkpoint, add to file
      elif [[ -n "$checkpoint_file" ]]; then
        echo "$file" >> "$checkpoint_file"
      fi
      return 1
    fi
  fi
  
  return 0
}

# Determine optimal batch size based on system resources
determine_batch_size() {
  local remaining_files="$1"
  local max_batch_size=20  # Default maximum batch size
  
  # Get number of CPU cores
  local cpu_cores
  if is_macos; then
    cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
  else
    cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
  fi
  
  # Check system load
  local load_avg
  if is_macos; then
    load_avg=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || echo 1.0)
  else
    # Use awk directly on the file instead of cat
    load_avg=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 1.0)
  fi
  
  # Convert load_avg to integer (multiply by 100)
  local load_int
  load_int=$(printf "%.0f" "$(echo "$load_avg * 100" | bc)")
  
  # Calculate CPU utilization percentage
  local cpu_util=$((load_int / cpu_cores))
  
  # Adjust batch size based on CPU utilization
  local adjusted_batch_size
  if [[ $cpu_util -lt 50 ]]; then
    # Low utilization, use more cores
    adjusted_batch_size=$((cpu_cores * 2))
  elif [[ $cpu_util -lt 80 ]]; then
    # Medium utilization, use available cores
    adjusted_batch_size=$cpu_cores
  else
    # High utilization, use fewer cores
    adjusted_batch_size=$((cpu_cores / 2))
  fi
  
  # Ensure batch size is at least 1
  if [[ $adjusted_batch_size -lt 1 ]]; then
    adjusted_batch_size=1
  fi
  
  # Cap at max_batch_size
  if [[ $adjusted_batch_size -gt $max_batch_size ]]; then
    adjusted_batch_size=$max_batch_size
  fi
  
  # Ensure batch size doesn't exceed remaining files
  if [[ $adjusted_batch_size -gt $remaining_files ]]; then
    adjusted_batch_size=$remaining_files
  fi
  
  echo "$adjusted_batch_size"
}

# Reset the checkpoint file
reset_checkpoint() {
  if [[ -f "$checkpoint_file" ]]; then
    log_info "Resetting checkpoint file: $checkpoint_file"
    # Use true command for redirection
    true > "$checkpoint_file"
    
    # Also set force_conversion to true to ensure all files are processed
    export force_conversion=true
  fi
}

# Initialize the progress pipe
init_progress_pipe() {
  # Export the progress pipe name
  export PROGRESS_PIPE_NAME="conv2md_progress.$$"
  export progress_pipe="${log_dir}/${PROGRESS_PIPE_NAME}"
  
  # Create the named pipe if it doesn't exist
  if [[ ! -p "$progress_pipe" ]]; then
    mkfifo "$progress_pipe" 2>/dev/null || true
    chmod 600 "$progress_pipe" 2>/dev/null || true
  fi
}

# Start the zombie process cleaner in the background
start_zombie_cleaner() {
  if [[ "${ENABLE_ZOMBIE_CLEANER:-true}" != "true" ]]; then
    return 0
  fi
  
  log_debug "Starting zombie process cleaner"
  
  # Run the zombie cleaner in the background
  (
    while true; do
      sleep 60
      cleanup_zombies
    done
  ) &
  
  export zombie_cleaner_pid=$!
  log_debug "Zombie cleaner started with PID: $zombie_cleaner_pid"
}

# Reset the checkpoint file if requested
maybe_reset_checkpoint() {
  # reset_checkpoint is expected to be set by the main script
  if [[ "${reset_checkpoint:-false}" == "true" ]]; then
    log_info "Resetting checkpoint as requested"
    
    # Get the count of processed files
    local count=0
    if [[ -f "$checkpoint_file" ]]; then
      count=$(wc -l < "$checkpoint_file" 2>/dev/null || echo 0)
    fi
    
    # Store the count for reporting
    export processed_files=$count
    
    # Reset the checkpoint file
    true > "$checkpoint_file"
  fi
}

# Print a header with the given text
print_header() {
  local text="$1"
  local term_width
  term_width=$(tput cols 2>/dev/null || echo 80)
  
  printf "\n%s\n" "${BOLD}${CYAN}$(printf '=%.0s' $(seq 1 "$term_width"))${RESET}"
  printf "%s\n" "${BOLD}${CYAN}${text}${RESET}"
  printf "%s\n\n" "${BOLD}${CYAN}$(printf '=%.0s' $(seq 1 "$term_width"))${RESET}"
}

# Check if the system is running low on memory
is_low_memory() {
  local threshold_mb="${1:-512}"  # Default threshold: 512MB
  local free_mb=0
  
  if is_macos; then
    # macOS memory check
    # shellcheck disable=SC2155
    local free_mem=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
    # shellcheck disable=SC2155
    local page_size=$(sysctl -n hw.pagesize)
    
    # Convert pages to MB
    free_mb=$((free_mem * page_size / 1024 / 1024))
  else
    # Linux memory check
    if command -v free >/dev/null 2>&1; then
      # shellcheck disable=SC2155
      local free_mem=$(free -k | grep "Mem:" | awk '{print $7}')
      free_mb=$((free_mem / 1024))
    fi
  fi
  
  if [[ $free_mb -lt $threshold_mb ]]; then
    return 0  # True, memory is low
  else
    return 1  # False, memory is not low
  fi
}

# Set a configuration option
set_config() {
  local option="$1"
  local value="$2"
  
  case "$option" in
    "memory_limit")
      # Export memory_limit for use in other functions
      export memory_limit="$value"
      ;;
    "pdf_memory_limit")
      # Export PDF_MEMORY_LIMIT for use in other functions
      export PDF_MEMORY_LIMIT="$value"
      ;;
    "word_timeout")
      # Export WORD_TIMEOUT for use in other functions
      export WORD_TIMEOUT="$value"
      ;;
    "powerpoint_timeout")
      # Export POWERPOINT_TIMEOUT for use in other functions
      export POWERPOINT_TIMEOUT="$value"
      ;;
    "pdf_timeout")
      # Export PDF_TIMEOUT for use in other functions
      export PDF_TIMEOUT="$value"
      ;;
    "max_log_size")
      # Export max_log_size for use in other functions
      export max_log_size="$value"
      ;;
    *)
      log_error "Unknown configuration option: $option"
      return 1
      ;;
  esac
  
  return 0
}

# Get the base name of the input directory
get_input_dir_basename() {
  # shellcheck disable=SC2155
  local input_dir_basename=$(basename "$input_dir")
  echo "$input_dir_basename"
} 