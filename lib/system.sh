#!/usr/bin/env bash
#
# system.sh - System resource monitoring
#
# This file contains functions for monitoring system resources

# Function to check system load
check_system_load() {
  # Skip check if load_timeout is 0
  # load_timeout is defined in the main script
  [[ ${load_timeout:-300} -eq 0 ]] && return 0
  
  # Get number of CPU cores
  local cpu_count
  if command -v nproc &>/dev/null; then
    cpu_count=$(nproc)
  elif [[ -f /proc/cpuinfo ]]; then
    cpu_count=$(grep -c processor /proc/cpuinfo)
  elif command -v sysctl &>/dev/null; then
    cpu_count=$(sysctl -n hw.ncpu)
  else
    # Default to 2 if we can't determine
    cpu_count=2
  fi
  
  # Set thresholds based on conservative mode
  local threshold
  if [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
    # More conservative threshold (60% of CPU cores)
    threshold=$(awk "BEGIN {print int($cpu_count * 0.6)}")
  else
    # Standard threshold (70% of CPU cores)
    threshold=$(awk "BEGIN {print int($cpu_count * 0.7)}")
  fi
  [[ $threshold -lt 1 ]] && threshold=1
  
  # Get current load
  local current_load
  if [[ -f /proc/loadavg ]]; then
    current_load=$(awk '{print $1}' /proc/loadavg)
  elif command -v uptime &>/dev/null; then
    current_load=$(uptime | awk -F'[a-z]:' '{ print $2 }' | awk -F',' '{ print $1 }' | sed 's/ //g')
  else
    # If we can't determine load, assume it's fine
    return 0
  fi
  
  # Log current load if in debug mode
  log_debug "System load: $current_load (threshold: $threshold)"
  
  # Check if load is too high
  if awk "BEGIN {exit !($current_load > $threshold)}"; then
    log_warning "System load is too high: $current_load (threshold: $threshold)"
    
    # Check if load has been high for too long
    local load_flag_file="${temp_dir:-/tmp}/.high_load_since"
    
    if [[ -f "$load_flag_file" ]]; then
      local high_load_since
      high_load_since=$(cat "$load_flag_file")
      
      local now
      now=$(date +%s)
      
      local load_high_duration=$((now - high_load_since))
      
      log_debug "Load has been high for $load_high_duration seconds (timeout: ${load_timeout:-300})"
      
      # Dynamically reduce max_workers if load is high
      if [[ $load_high_duration -gt 30 && ${max_workers:-4} -gt 1 ]]; then
        local new_max_workers=$((max_workers - 1))
        log_warning "Reducing max_workers from $max_workers to $new_max_workers due to high system load"
        max_workers=$new_max_workers
        export max_workers
      fi
      
      if [[ $load_high_duration -gt ${load_timeout:-300} ]]; then
        log_error "System load has been too high for over ${load_timeout:-300} seconds. Stopping conversions."
        # Create interrupt flag to stop all processing
        touch "${log_dir:-/tmp}/.interrupt_flag"
        return 1
      fi
      
      # Force a pause to let system recover
      log_info "Pausing for 5 seconds to let system load decrease..."
      sleep 5
      return 1
    else
      # Create flag file with current timestamp
      date +%s > "$load_flag_file"
    fi
  else
    # Remove the flag file if load is acceptable
    rm -f "${temp_dir:-/tmp}/.high_load_since" 2>/dev/null || true
    
    # If load is very low and we previously reduced workers, consider increasing them
    if awk "BEGIN {exit !($current_load < ($threshold * 0.5))}"; then
      if [[ -f "${temp_dir:-/tmp}/.reduced_workers" ]]; then
        local original_workers
        original_workers=$(cat "${temp_dir:-/tmp}/.reduced_workers")
        
        if [[ ${max_workers:-4} -lt $original_workers ]]; then
          local new_max_workers=$((max_workers + 1))
          if [[ $new_max_workers -le $original_workers ]]; then
            log_info "Increasing max_workers from $max_workers to $new_max_workers due to low system load"
            max_workers=$new_max_workers
            export max_workers
          fi
        fi
      else
        # Store original max_workers value
        echo "${max_workers:-4}" > "${temp_dir:-/tmp}/.reduced_workers"
      fi
    fi
  fi
  
  return 0
}

# Function to check available memory
check_memory() {
  # Skip check if memory_timeout is 0
  [[ ${memory_timeout:-300} -eq 0 ]] && return 0
  
  # Minimum free memory threshold (MB) - adjusted based on conservative mode
  local min_free_mb
  if [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
    min_free_mb=1536  # More conservative: 1.5GB
  else
    min_free_mb=1024  # Standard: 1GB
  fi
  
  # Get available memory
  local available_memory
  
  if [[ -f /proc/meminfo ]]; then
    # Linux
    if grep -q "MemAvailable" /proc/meminfo; then
      # Modern Linux with MemAvailable
      available_memory=$(($(grep "MemAvailable" /proc/meminfo | awk '{print $2}') / 1024))
    else
      # Older Linux, use free + buffers/cache
      local mem_free
      mem_free=$(grep "MemFree" /proc/meminfo | awk '{print $2}')
      
      local buffers
      buffers=$(grep "Buffers" /proc/meminfo | awk '{print $2}')
      
      local cached
      cached=$(grep "Cached" /proc/meminfo | awk '{print $2}')
      
      available_memory=$(((mem_free + buffers + cached) / 1024))
    fi
  elif command -v vm_stat &>/dev/null; then
    # macOS
    local page_size
    page_size=$(vm_stat | grep "page size" | awk '{print $8}')
    
    local free_pages
    free_pages=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
    
    available_memory=$(((page_size * free_pages) / 1048576))
  elif command -v sysctl &>/dev/null && sysctl -n hw.memsize &>/dev/null; then
    # BSD-like systems
    local total_mem
    total_mem=$(sysctl -n hw.memsize)
    
    local used_mem
    used_mem=$(ps -caxm -orss= | awk '{sum+=$1} END {print sum * 1024}')
    
    available_memory=$(((total_mem - used_mem) / 1048576))
  else
    # If we can't determine memory, assume it's fine
    return 0
  fi
  
  # Log available memory if in debug mode
  log_debug "Available memory: $available_memory MB (minimum: $min_free_mb MB)"
  
  # Check if memory is too low
  if [[ $available_memory -lt $min_free_mb ]]; then
    log_warning "Available memory is too low: $available_memory MB"
    
    # Check if memory has been low for too long
    local memory_flag_file="${temp_dir:-/tmp}/.low_memory_since"
    
    if [[ -f "$memory_flag_file" ]]; then
      local low_memory_since
      low_memory_since=$(cat "$memory_flag_file")
      
      local now
      now=$(date +%s)
      
      local memory_low_duration=$((now - low_memory_since))
      
      log_debug "Memory has been low for $memory_low_duration seconds (timeout: ${memory_timeout:-300})"
      
      # Dynamically reduce max_workers if memory is low
      if [[ $memory_low_duration -gt 20 && ${max_workers:-4} -gt 1 ]]; then
        local new_max_workers=$((max_workers - 1))
        log_warning "Reducing max_workers from $max_workers to $new_max_workers due to low memory"
        max_workers=$new_max_workers
        export max_workers
      fi
      
      if [[ $memory_low_duration -gt ${memory_timeout:-300} ]]; then
        log_error "Available memory has been too low for over ${memory_timeout:-300} seconds. Stopping conversions."
        # Create interrupt flag to stop all processing
        touch "${log_dir:-/tmp}/.interrupt_flag"
        return 1
      fi
      
      # Force a pause to let memory recover
      log_info "Pausing for 10 seconds to let memory recover..."
      sleep 10
      return 1
    else
      # Create flag file with current timestamp
      date +%s > "$memory_flag_file"
    fi
  else
    # Remove the flag file if memory is acceptable
    rm -f "${temp_dir:-/tmp}/.low_memory_since" 2>/dev/null || true
  fi
  
  return 0
}

# Function to set process resource limits
set_process_limits() {
  # Try to set ulimit values if possible
  if command -v ulimit &>/dev/null; then
    # Increase file descriptors
    ulimit -n 4096 2>/dev/null || true
    
    # Set maximum file size (1GB)
    ulimit -f 1048576 2>/dev/null || true
    
    # Set CPU time limit (10 minutes)
    ulimit -t 600 2>/dev/null || true
    
    # Set virtual memory limit based on conservative mode
    if [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
      # More conservative memory limit (3GB)
      ulimit -v 3145728 2>/dev/null || true
      log_debug "Process limits set: fd=4096, filesize=1GB, cputime=10m, vmem=3GB (conservative mode)"
    else
      # Standard memory limit (4GB)
      ulimit -v 4194304 2>/dev/null || true
      log_debug "Process limits set: fd=4096, filesize=1GB, cputime=10m, vmem=4GB"
    fi
  fi
}

# Function to get optimal number of workers based on system resources
get_optimal_workers() {
  local cpu_count
  
  # Get number of CPU cores
  if command -v nproc &>/dev/null; then
    cpu_count=$(nproc)
  elif [[ -f /proc/cpuinfo ]]; then
    cpu_count=$(grep -c processor /proc/cpuinfo)
  elif command -v sysctl &>/dev/null; then
    cpu_count=$(sysctl -n hw.ncpu)
  else
    # Default to 2 if we can't determine
    cpu_count=2
  fi
  
  # Get available memory in MB
  local available_memory=0
  
  if [[ -f /proc/meminfo ]]; then
    # Linux
    if grep -q "MemAvailable" /proc/meminfo; then
      # Modern Linux with MemAvailable
      available_memory=$(($(grep "MemAvailable" /proc/meminfo | awk '{print $2}') / 1024))
    else
      # Older Linux, use free + buffers/cache
      local mem_free
      mem_free=$(grep "MemFree" /proc/meminfo | awk '{print $2}')
      
      local buffers
      buffers=$(grep "Buffers" /proc/meminfo | awk '{print $2}')
      
      local cached
      cached=$(grep "Cached" /proc/meminfo | awk '{print $2}')
      
      available_memory=$(((mem_free + buffers + cached) / 1024))
    fi
  elif command -v vm_stat &>/dev/null; then
    # macOS
    local page_size
    page_size=$(vm_stat | grep "page size" | awk '{print $8}')
    
    local free_pages
    free_pages=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
    
    available_memory=$(((page_size * free_pages) / 1048576))
  fi
  
  # Calculate optimal workers based on CPU and memory
  # Memory requirements per worker depend on file type being processed
  local memory_per_worker
  if [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
    # More conservative memory allocation in conservative mode
    memory_per_worker=2560  # 2.5GB per worker
  else
    # Standard memory allocation
    memory_per_worker=2048  # 2GB per worker
  fi
  
  local memory_based_workers=$((available_memory / memory_per_worker))
  
  # Use the smaller of CPU-based or memory-based worker count
  local optimal_workers
  if [[ $memory_based_workers -lt $cpu_count ]]; then
    optimal_workers=$memory_based_workers
  else
    # Use percentage of CPU cores based on conservative mode
    if [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
      # More conservative CPU usage (60% of cores)
      optimal_workers=$(awk "BEGIN {print int($cpu_count * 0.6)}")
    else
      # Standard CPU usage (75% of cores)
      optimal_workers=$(awk "BEGIN {print int($cpu_count * 0.75)}")
    fi
  fi
  
  # Ensure at least 1 worker and at most 8 workers (or 6 in conservative mode)
  [[ $optimal_workers -lt 1 ]] && optimal_workers=1
  if [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
    [[ $optimal_workers -gt 6 ]] && optimal_workers=6
  else
    [[ $optimal_workers -gt 8 ]] && optimal_workers=8
  fi
  
  echo "$optimal_workers"
}

# Function to check if we should throttle processing
should_throttle() {
  # Check both system load and memory
  if ! check_system_load || ! check_memory; then
    return 0  # Should throttle
  fi
  return 1  # No need to throttle
}

# Function to clean up stale processes
cleanup_stale_processes() {
  local semaphore_dir="$1"
  local max_age="${2:-300}"  # Default to 5 minutes (300 seconds)
  
  log_debug "Checking for stale processes in $semaphore_dir"
  
  # Check if semaphore directory exists
  if [[ ! -d "$semaphore_dir" ]]; then
    log_debug "Semaphore directory does not exist: $semaphore_dir"
    return 0
  fi
  
  # Get current time
  local now
  now=$(date +%s)
  
  # Check each semaphore file
  shopt -s nullglob
  for sem_file in "$semaphore_dir"/*.sem; do
    [[ -f "$sem_file" ]] || continue
    
    # Get file modification time
    local file_time
    if [[ "$(uname)" == "Darwin" ]]; then
      # macOS
      file_time=$(stat -f %m "$sem_file" 2>/dev/null || echo "$now")
    else
      # Linux
      file_time=$(stat -c %Y "$sem_file" 2>/dev/null || echo "$now")
    fi
    
    # Calculate age
    local age=$((now - file_time))
    
    # Check if file is too old
    if [[ $age -gt $max_age ]]; then
      # Get PID from semaphore file
      local pid
      pid=$(cat "$sem_file" 2>/dev/null || echo "")
      
      if [[ -n "$pid" ]]; then
        log_warning "Found stale process with PID $pid (age: ${age}s). Attempting to terminate."
        
        # Try to kill the process
        kill -15 "$pid" 2>/dev/null || true
        
        # Wait a moment and check if it's still running
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
          log_warning "Process $pid did not terminate. Sending SIGKILL."
          kill -9 "$pid" 2>/dev/null || true
        fi
      fi
      
      # Remove the stale semaphore file
      log_debug "Removing stale semaphore file: $sem_file"
      rm -f "$sem_file" 2>/dev/null || true
    fi
  done
  shopt -u nullglob
  
  return 0
}

# Function to monitor and kill processes that exceed memory limits
monitor_process_memory() {
  local pid="$1"
  local max_memory_mb="${2:-4096}"  # Default to 4GB
  local check_interval="${3:-5}"    # Check every 5 seconds
  
  log_debug "Starting memory monitor for PID $pid (limit: $max_memory_mb MB)"
  
  while kill -0 "$pid" 2>/dev/null; do
    # Get process memory usage
    local memory_usage_kb
    if [[ "$(uname)" == "Darwin" ]]; then
      # macOS - use ps
      memory_usage_kb=$(ps -o rss= -p "$pid" 2>/dev/null || echo "0")
    else
      # Linux - use /proc
      if [[ -f "/proc/$pid/status" ]]; then
        memory_usage_kb=$(grep VmRSS "/proc/$pid/status" 2>/dev/null | awk '{print $2}' || echo "0")
      else
        memory_usage_kb=$(ps -o rss= -p "$pid" 2>/dev/null || echo "0")
      fi
    fi
    
    # Convert to MB
    local memory_usage_mb=$((memory_usage_kb / 1024))
    
    # Check if memory usage exceeds limit
    if [[ $memory_usage_mb -gt $max_memory_mb ]]; then
      log_warning "Process $pid exceeded memory limit ($memory_usage_mb MB > $max_memory_mb MB). Terminating."
      kill -15 "$pid" 2>/dev/null || true
      
      # Wait a moment and check if it's still running
      sleep 1
      if kill -0 "$pid" 2>/dev/null; then
        log_warning "Process $pid did not terminate. Sending SIGKILL."
        kill -9 "$pid" 2>/dev/null || true
      fi
      
      break
    fi
    
    # Sleep before next check
    sleep "$check_interval"
  done
  
  log_debug "Memory monitor for PID $pid exited"
} 