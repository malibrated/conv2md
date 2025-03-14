#!/usr/bin/env bash
#
# conv2md.sh - Convert documents to Markdown
#
# Usage: conv2md.sh -i <input_dir> -o <output_dir> [options]
#
# A script to convert Word, PowerPoint, and PDF documents to Markdown.

# Set up colors for terminal output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export BOLD='\033[1m'
export RESET='\033[0m'
export GRAY='\033[0;90m'
export NC='\033[0m'  # No Color - for compatibility with logging.sh

# Check Bash version
if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  echo "Error: This script requires Bash 5.2.37 or higher"
  echo "Current version: $BASH_VERSION"
  exit 1
fi

# Enable strict error checking
set -euo pipefail

# Ensure Homebrew paths are in PATH
for brew_path in "/opt/homebrew/bin" "/opt/homebrew/opt/sqlite/bin" "/usr/local/bin"; do
  if [[ -d "$brew_path" && ! "$PATH" =~ $brew_path ]]; then
    export PATH="$brew_path:$PATH"
  fi
done

# Script home directory
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Load library files
for lib_file in "${script_dir}/lib"/*.sh; do
  if [[ -f "$lib_file" ]]; then
    # Source libraries
    # shellcheck disable=SC1090
    source "$lib_file"
  fi
done

# Script version
VERSION="1.5.0"

# Generate a unique instance ID for this run
instance_id=$(date +%s)_$$

# Default values
log_dir=""
temp_dir="/tmp/conv2md_${instance_id}"
max_workers=4
max_file_size=0  # 0 means no limit, otherwise in MB
debug=false
verbose_debug=false  # New verbose debug option
force_conversion=false
resume_from_checkpoint=false
skip_word=false
skip_powerpoint=false
skip_pdf=false
export skip_checks=false  # Used by dependency checking functions
total_files=0
checkpoint_file=""
checkpoint_db=""  # New variable for SQLite checkpoint database
# Log file paths used by logging.sh
export output_log=""
export error_log=""
export debug_log=""
export conversion_log=""
# Date format for logging
export date_format="%Y-%m-%d %H:%M:%S"
# Used by logging.sh for log rotation
export log_max_size=10240  # 10MB in KB
# Used by system.sh for resource monitoring
export load_timeout=300    # 5 minutes
export memory_timeout=300  # 5 minutes
export conversion_timeout=600  # 10 minutes
force_pdf_ocr=false  # Use markitdown by default, marker_single as fallback
export no_fallback=false    # Flag to disable fallback to marker_single
# Resource management variables
export resource_check_interval=30  # Check resources every 30 seconds
export throttle_enabled=true       # Enable throttling by default
export batch_size=5                # Process files in smaller batches
export stale_process_timeout=300   # 5 minutes before considering a process stale
memory_monitor_enabled=false
memory_limit_mb=4096

# Function to parse command line arguments
parse_args() {
  # Default values
  input_dir=""
  output_dir=""
  force_conversion=false
  skip_word=false
  skip_powerpoint=false
  skip_pdf=false
  resume_from_checkpoint=false
  max_workers=""
  memory_limit_mb=4096
  verbose=false
  debug=false
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--input)
        input_dir="$2"
        shift 2
        ;;
      -o|--output)
        output_dir="$2"
        shift 2
        ;;
      --force)
        force_conversion=true
        shift
        ;;
      --skip-word)
        skip_word=true
        shift
        ;;
      --skip-powerpoint)
        skip_powerpoint=true
        shift
        ;;
      --skip-pdf)
        skip_pdf=true
        shift
        ;;
      -r|--resume)
        resume_from_checkpoint=true
        shift
        ;;
      -w|--workers)
        max_workers="$2"
        shift 2
        ;;
      -m|--memory-limit)
        memory_limit_mb="$2"
        shift 2
        ;;
      -v|--verbose)
        verbose=true
        shift
        ;;
      -d|--debug|--verbose-debug)
        debug=true
        verbose=true
        shift
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        print_help
        exit 1
        ;;
    esac
  done
}

# Function to check dependencies
check_dependencies() {
  log_debug "Checking for required dependencies"

  # Check for find command
  if ! command -v find &>/dev/null; then
    log_error "find command not found. This is required for the script to work."
    exit 1
  fi

  # Check for awk command
  if ! command -v awk &>/dev/null; then
    log_error "awk command not found. This is required for the script to work."
    exit 1
  fi

  # Check for mkfifo command (used for progress pipe)
  if ! command -v mkfifo &>/dev/null; then
    log_warning "mkfifo command not found. Progress updates will use a less efficient method."
  fi

  # Check for SQLite3 command (used for checkpoint database)
  if ! command -v sqlite3 &>/dev/null; then
    log_warning "sqlite3 command not found. Will use text-based checkpoint file instead."
    log_warning "For improved performance with large checkpoints, install SQLite: brew install sqlite"
  else
    log_debug "Found sqlite3 in PATH: $(which sqlite3)"
  fi

  # Check for marker_single command (used for PDF OCR conversion)
  local marker_single_found=false
  if command -v "marker_single" &>/dev/null; then
    marker_single_found=true
  fi

  if [[ "$marker_single_found" != "true" && "$skip_pdf" != "true" ]]; then
    log_warning "marker_single command not found. PDF conversion will be skipped."
    log_warning "Please install marker from https://github.com/VikParuchuri/marker"
    log_warning "Ensure marker_single is in your PATH after installation."
    log_warning "The script uses marker_single with the --force_ocr flag for PDF OCR processing."
    skip_pdf=true
  fi

  # Check for GNU Parallel (optional, used for improved PDF processing)
  local parallel_found=false
  for path in "/opt/homebrew/bin/parallel" "parallel"; do
    if command -v "$path" &>/dev/null; then
      parallel_found=true
      log_info "GNU Parallel found at $path. Will use for improved PDF processing."
      break
    fi
  done

  if [[ "$parallel_found" != "true" && "$skip_pdf" != "true" ]]; then
    log_info "GNU Parallel not found. Will use standard PDF processing method."
    log_info "For improved performance, consider installing GNU Parallel: brew install parallel"
  fi

  # Check for pandoc (used for Word conversion)
  if [[ "$skip_word" != "true" ]]; then
    if ! command -v pandoc &>/dev/null; then
      log_warning "pandoc command not found. Word document conversion will be skipped."
      log_warning "Please install pandoc: brew install pandoc"
      skip_word=true
    fi
    
    # Check for textutil on macOS (used for .doc conversion)
    if [[ "$(uname)" == "Darwin" ]]; then
      if ! command -v textutil &>/dev/null; then
        log_warning "textutil command not found on macOS. Legacy .doc file conversion will not work properly."
        log_warning "textutil should be included with macOS by default. Please check your system."
      else
        log_debug "Found textutil for .doc conversion on macOS: $(which textutil)"
      fi
    else
      log_warning "Running on non-macOS system ($(uname)). Legacy .doc file conversion will not be supported."
      log_warning "Only .docx files will be converted. Please convert .doc files to .docx format manually."
    fi
  fi

  # Check for MarkItDown (primary conversion tool for most file types)
  if check_markitdown; then
    log_info "MarkItDown found. Will use as primary conversion tool for most file types."
  else
    log_warning "MarkItDown not found. This will significantly limit conversion capabilities."
    log_warning "Please install MarkItDown using pip:"
    log_warning "pip install 'markitdown[all]~=0.1.0a1'"
    log_warning "For more information, visit: https://github.com/microsoft/markitdown"
    
    # Set appropriate flags based on MarkItDown availability
    if [[ "$skip_powerpoint" != "true" ]]; then
      log_warning "PowerPoint (.ppt, .pptx) conversion will be skipped without MarkItDown."
      skip_powerpoint=true
    fi
    
    # Word documents can still be processed with pandoc if available
    if [[ "$skip_word" != "true" ]]; then
      if ! command -v pandoc &>/dev/null; then
        log_warning "Word (.docx) conversion will be skipped without MarkItDown or pandoc."
        skip_word=true
      else
        log_warning "Word (.docx) conversion will use pandoc with limited capabilities."
      fi
    fi
    
    # PDF conversion will be limited to marker_single OCR
    if [[ "$skip_pdf" != "true" ]]; then
      if ! command -v marker_single &>/dev/null; then
        log_warning "PDF conversion will be skipped without MarkItDown or marker_single."
        skip_pdf=true
      else
        log_warning "PDF conversion will be limited to OCR processing with marker_single."
      fi
    fi
    
    # Warn about other file types
    log_warning "Conversion of other file types (spreadsheets, images, etc.) will be limited."
  fi
}

# Function to validate arguments
validate_args() {
  # Check if input directory is provided
  if [[ -z "$input_dir" ]]; then
    echo "Error: Input directory is required"
    show_help
    exit 1
  fi
  
  # Check if input directory exists
  if [[ ! -d "$input_dir" ]]; then
    echo "Error: Input directory does not exist: $input_dir"
    exit 1
  fi
  
  # variable to save the output_dir_root if provided by the user
  output_dir_root=""

  # Convert input directory to absolute path
  input_dir=$(cd "$input_dir" && pwd)
  
  # Create output directory if it doesn't exist
  if [[ -n "$output_dir" ]]; then
    # Convert output directory to absolute path if it exists
    if [[ -d "$output_dir" ]]; then
      output_dir=$(cd "$output_dir" && pwd)
    fi
    #save the output_dir_root if provided by the user
    output_dir_root="$output_dir"
    
    # Get the base name of the input directory
    input_dir_basename=$(basename "$input_dir")
    
    # Create a subdirectory in the output directory with the same name as the input directory
    echo -e "${BLUE}[INFO]${RESET} Creating subdirectory in output directory with input directory name: $output_dir/$input_dir_basename"
    output_dir="$output_dir/$input_dir_basename"
    
    echo -e "${BLUE}[INFO]${RESET} Ensuring output directory exists: $output_dir"
    mkdir -p "$output_dir" || {
      echo "Error: Failed to create output directory: $output_dir"
      exit 1
    }
  else
    # If output directory is not provided, create one next to the input directory
    output_dir="${input_dir}_md"
    # If Output directory is not provided the default one is the output_dir_root
    output_dir_root="$output_dir"
  fi
  
  # Set up log directory - MODIFIED: Use hidden .logs directory in output directory
  log_dir="${output_dir_root}/.logs"
  echo -e "${BLUE}[INFO]${RESET} Log directory: $log_dir"
  
  # Set up temp directory
  if [[ -z "$temp_dir" ]]; then
    temp_dir="${log_dir}/temp_${instance_id}"
  fi
  
  # Ensure output directory is absolute
  if [[ ! "$output_dir" = /* ]]; then
    output_dir="$(pwd)/$output_dir"
  fi
  echo -e "${BLUE}[INFO]${RESET} Using absolute output directory path: $output_dir"
  
  # Validate max_workers
  if [[ -z "$max_workers" ]]; then
    # Determine optimal number of workers based on CPU count
    if command -v nproc &>/dev/null; then
      max_workers=$(nproc)
    elif command -v sysctl &>/dev/null && sysctl -n hw.ncpu &>/dev/null; then
      max_workers=$(sysctl -n hw.ncpu)
    else
      max_workers=4  # Default to 4 workers
    fi
    
    # Adjust max_workers based on available CPUs
    max_workers=$((max_workers - 1))  # Leave one CPU free
    [[ $max_workers -lt 1 ]] && max_workers=1
    [[ $max_workers -gt 8 ]] && max_workers=8  # Cap at 8 workers
  elif ! [[ "$max_workers" =~ ^[0-9]+$ ]]; then
    echo -e "${YELLOW}[WARNING]${RESET} Invalid number of workers: $max_workers. Using default value: 4"
    max_workers=4
  fi
  
  # Set up checkpoint file
  if [[ "$resume_from_checkpoint" == true ]]; then
    # Check if SQLite is available
    if command -v sqlite3 &>/dev/null; then
      log_debug "SQLite available, will use database for checkpoint tracking"
      checkpoint_db="${log_dir}/.checkpoint.db"
      # We don't need to set checkpoint_file as we'll use the database exclusively
    else
      log_debug "SQLite not available, will use text-based checkpoint file"
      checkpoint_file="${log_dir}/.checkpoint"
    fi
  fi
  
  # Generate a unique instance ID for this run
  if [[ -z "$instance_id" ]]; then
    instance_id=$(date +%s)_$$
  fi
  
  # Print configuration
  echo -e "${BLUE}[INFO]${RESET} Input directory: $input_dir"
  echo -e "${BLUE}[INFO]${RESET} Output directory: $output_dir"
  echo -e "${BLUE}[INFO]${RESET} Log directory: $log_dir"
  echo -e "${BLUE}[INFO]${RESET} Maximum workers for PDF processing: $max_workers"
  echo -e "${BLUE}[INFO]${RESET} Maximum file size: ${max_file_size:-No limit}"
  echo -e "${BLUE}[INFO]${RESET} Skipping Word: $skip_word"
  echo -e "${BLUE}[INFO]${RESET} Skipping PowerPoint: $skip_powerpoint"
  echo -e "${BLUE}[INFO]${RESET} Skipping PDF: $skip_pdf"
  echo -e "${BLUE}[INFO]${RESET} Force conversion: $force_conversion"
  echo -e "${BLUE}[INFO]${RESET} Force PDF OCR: ${force_pdf_ocr:-false}"
  echo -e "${BLUE}[INFO]${RESET} No Fallback to marker_single: ${no_fallback:-false}"
  echo -e "${BLUE}[INFO]${RESET} Resume from checkpoint: $resume_from_checkpoint"
  echo -e "${BLUE}[INFO]${RESET} Debug mode: $debug"
  echo -e "${BLUE}[INFO]${RESET} Verbose debug: ${verbose_debug:-false}"
}

# Function to process files of a specific type
process_files_of_type() {
  local file_type="$1"
  local file_list="$2"
  local type_max_workers="$3"
  
  if [[ ! -f "$file_list" ]]; then
    log_error "File list not found: $file_list"
    return 1
  fi
  
  local file_count
  file_count=$(wc -l < "$file_list")
  
  if [[ $file_count -eq 0 ]]; then
    log_info "No $file_type files to process"
    return 0
  fi
  
  log_info "Processing $file_count $file_type files"
  
  # If resuming from checkpoint and SQLite is available, batch check files against checkpoint
  if [[ "$resume_from_checkpoint" == true && -n "$checkpoint_db" && -f "$checkpoint_db" && "$force_conversion" != true ]]; then
    local already_processed_list="${temp_dir}/already_processed_${file_type}.txt"
    local files_to_process_list="${temp_dir}/to_process_${file_type}.txt"
    
    # Batch check files against checkpoint database
    batch_check_checkpoint_db "$file_list" "$already_processed_list"
    
    # Create a list of files that need processing (not in checkpoint)
    if [[ -f "$already_processed_list" ]]; then
      # Use grep to filter out already processed files
      grep -v -F -f "$already_processed_list" "$file_list" > "$files_to_process_list" || true
      
      local to_process_count
      to_process_count=$(wc -l < "$files_to_process_list")
      
      local skipped_count=$((file_count - to_process_count))
      log_info "Skipping $skipped_count already processed $file_type files"
      
      # If all files are already processed, return early
      if [[ $to_process_count -eq 0 ]]; then
        log_info "All $file_type files have already been processed"
        return 0
      fi
      
      # Use the filtered list for processing
      file_list="$files_to_process_list"
      file_count=$to_process_count
      log_info "Processing $file_count $file_type files that need conversion"
    fi
  fi
  
  # Set up semaphore directory for parallel processing
  local semaphore_dir="${temp_dir}/.semaphore_${file_type}_${instance_id}"
  mkdir -p "$semaphore_dir"
  
  # Process files in parallel
  if ! process_files_in_parallel "$file_list" "$file_type" "$type_max_workers" "$semaphore_dir" "process_single_file"; then
    log_error "Error processing $file_type files"
    return 1
  fi
  
  return 0
}

# Function to print version
print_version() {
  echo "conv2md.sh version $VERSION"
}

# Function to safely sanitize path for logs
sanitize_path_for_logs() {
  local path="$1"
  # If path is empty, return empty string
  if [[ -z "$path" ]]; then
    echo ""
    return
  fi
  # Replace HOME directory with ~
  path="${path/#"$HOME"/~}"
  # Sanitize for logging (e.g., remove sensitive info, if needed more than just home dir)
  echo "$path"
}

# Function to count total files to process
count_total_files() {
  total_files=0

  # Count Word files if not skipped
  if [[ "$skip_word" == false ]]; then
    local word_count
    word_count=$(eval "$(create_file_find_command "Word" --count=true)")
    total_files=$((total_files + word_count))
  fi

  # Count PowerPoint files if not skipped
  if [[ "$skip_powerpoint" == false ]]; then
    local ppt_count
    ppt_count=$(eval "$(create_file_find_command "PowerPoint" --count=true)")
    total_files=$((total_files + ppt_count))
  fi

  # Count PDF files if not skipped
  if [[ "$skip_pdf" == false ]]; then
    local pdf_count
    pdf_count=$(eval "$(create_file_find_command "PDF" --count=true)")
    total_files=$((total_files + pdf_count))
  fi
}

# Function to process a specific file type using optimized methods
process_file_type() {
  local file_type="$1"
  
  log_info "Processing $file_type files..."
  
  # Skip processing based on file type
  if [[ "$file_type" == "Word" && "$skip_word" == true ]]; then
    log_debug "Word processing is disabled, skipping"
    return 0
  elif [[ "$file_type" == "PowerPoint" && "$skip_powerpoint" == true ]]; then
    log_debug "PowerPoint processing is disabled, skipping"
    return 0
  elif [[ "$file_type" == "PDF" && "$skip_pdf" == true ]]; then
    log_debug "PDF processing is disabled, skipping"
    return 0
  fi
  
  # Create a temporary file to store the list of files
  local file_list="${temp_dir}/${file_type}_files.txt"
  log_debug "Creating file list at: $file_list"
  
  # Ensure temp directory exists
  if [[ ! -d "$temp_dir" ]]; then
    log_debug "Creating temporary directory: $temp_dir"
    mkdir -p "$temp_dir" || {
      log_error "Failed to create temporary directory: $temp_dir"
      return 1
    }
  fi
  
  # Find all files of the specified type and save them to the file list
  log_debug "Running find command for $file_type files..."
  if ! eval "$(create_file_find_command "$file_type")" > "$file_list"; then
    log_error "Failed to find $file_type files in directory: $input_dir"
    return 1
  fi
  log_debug "Find command completed for $file_type files"
  
  # Count the number of files
  local file_count
  if ! file_count=$(wc -l < "$file_list"); then
    log_error "Failed to count $file_type files"
    rm -f "$file_list" 2>/dev/null || true
    return 1
  fi
  log_info "Found $file_count $file_type files to process"
  
  # If no files found, return
  if [[ $file_count -eq 0 ]]; then
    log_debug "No $file_type files found, skipping processing"
    rm -f "$file_list" 2>/dev/null || true
    return 0
  fi
  
  # Sort files by size to process smaller files first (optimization)
  if type -t sort_files_by_size &>/dev/null; then
    log_debug "Sorting $file_type files by size"
    sort_files_by_size "$file_list"
  fi
  
  # Adjust max_workers based on file type and resource mode
  local type_max_workers=$max_workers
  if [[ "$file_type" == "Word" ]]; then
    if [[ "${ULTRA_CONSERVATIVE:-false}" == "true" ]]; then
      type_max_workers=1  # Ultra-conservative: sequential processing
    elif [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
      type_max_workers=$((max_workers > 3 ? 3 : max_workers))  # Conservative: max 3 workers
    fi
  elif [[ "$file_type" == "PowerPoint" ]]; then
    if [[ "${ULTRA_CONSERVATIVE:-false}" == "true" ]]; then
      type_max_workers=1  # Ultra-conservative: sequential processing
    elif [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
      type_max_workers=$((max_workers > 2 ? 2 : max_workers))  # Conservative: max 2 workers
    else
      type_max_workers=$((max_workers > 4 ? 4 : max_workers))  # Standard: max 4 workers for PowerPoint
    fi
  elif [[ "$file_type" == "PDF" ]]; then
    if [[ "${ULTRA_CONSERVATIVE:-false}" == "true" ]]; then
      type_max_workers=1  # Ultra-conservative: sequential processing
    elif [[ "${CONSERVATIVE_MODE:-false}" == "true" ]]; then
      type_max_workers=$((max_workers > 2 ? 2 : max_workers))  # Conservative: max 2 workers
    else
      type_max_workers=$((max_workers > 4 ? 4 : max_workers))  # Standard: max 4 workers for PDFs
    fi
  fi
  
  # Use our optimized process_files_of_type function which includes batch checkpoint checking
  local processing_status=0
  if ! process_files_of_type "$file_type" "$file_list" "$type_max_workers"; then
    log_warning "$file_type processing encountered errors"
    processing_status=1
  fi
  
  # Clean up
  rm -f "$file_list" 2>/dev/null || true
  
  return $processing_status
}

# Create find command based on file type
create_file_find_command() {
  local file_type="$1"
  local count_only="${2:-false}"  # Provide default value of "false" if not specified

  local file_pattern=""
  case "$file_type" in
    "Word")
      file_pattern="-name '*.doc' -o -name '*.docx'"
      ;;
    "PowerPoint")
      file_pattern="-name '*.ppt' -o -name '*.pptx'"
      ;;
    "PDF")
      file_pattern="-name '*.pdf'"
      ;;
    *)
      log_error "Unknown file type: $file_type"
      return 1
      ;;
  esac

  local find_command="find '$input_dir' -depth -type f \( $file_pattern \) -not -path '*/\.*'"
  # Check if count_only is either "--count=true" or "true"
  if [[ "$count_only" == "--count=true" || "$count_only" == "true" ]]; then
    find_command="$find_command | wc -l"
  else
    find_command="$find_command -print"  # Use -print instead of -print0 for better compatibility
  fi

  echo "$find_command"
}

# Function to print help
print_help() {
  echo "Usage: conv2md.sh -i <input_dir> -o <output_dir> [options]"
  echo ""
  echo "Options:"
  echo "  -i, --input <dir>              Input directory containing documents to convert"
  echo "  -o, --output <dir>             Output directory for converted Markdown files"
  echo "  -w, --workers <num>            Maximum number of parallel workers (default: 4)"
  echo "  -l, --log <dir>                Log directory (default: <output_dir>/.logs)"
  echo "  -t, --temp <dir>               Temporary directory (default: /tmp/conv2md_<instance_id>)"
  echo "  -f, --force                    Force conversion of already converted files"
  echo "  -r, --resume                   Resume from checkpoint (skip already converted files)"
  echo "  -d, --debug                    Enable debug logging"
  echo "  --verbose-debug                Enable verbose debug logging"
  echo ""
  echo "File Type Options:"
  echo "  --skip-word                    Skip Word document conversion"
  echo "  --skip-powerpoint              Skip PowerPoint document conversion"
  echo "  --skip-pdf                     Skip PDF document conversion"
  echo "  --force-pdf-ocr                Force OCR for PDF files"
  echo "  --no-fallback                  Disable fallback to marker_single for PDF conversion"
  echo "  --max-file-size <size>         Maximum file size in MB (0 = no limit)"
  echo ""
  echo "Resource Management Options:"
  echo "  --batch-size <size>            Number of files to process in each batch (default: 5)"
  echo "  --resource-check-interval <s>  Seconds between resource checks (default: 30)"
  echo "  --disable-throttling           Disable automatic throttling based on system resources"
  echo "  --memory-monitor               Enable per-process memory monitoring"
  echo "  -m, --memory-limit <mb>        Maximum memory per process in MB (default: 4096)"
  echo "  --conservative-resources       Enable conservative resource usage mode"
  echo "  --ultra-conservative           Enable ultra-conservative mode for limited systems"
  echo ""
  echo "Other Options:"
  echo "  --skip-checks                  Skip dependency checks"
  echo "  -v, --version                  Print version information"
  echo "  -h, --help                     Print this help message"
  echo ""
  echo "Examples:"
  echo "  conv2md.sh -i ~/Documents/MyDocs -o ~/Documents/MyDocs_markdown"
  echo "  conv2md.sh -i ~/Documents/MyDocs -o ~/Documents/MyDocs_markdown -w 2 --skip-pdf"
  echo "  conv2md.sh -i ~/Documents/MyDocs -o ~/Documents/MyDocs_markdown --conservative-resources"
  echo "  conv2md.sh -i ~/Documents/MyDocs -o ~/Documents/MyDocs_markdown --ultra-conservative"
}

# Show help message
show_help() {
  echo "Usage: conv2md.sh [options]"
  echo ""
  echo "Options:"
  echo "  -i, --input DIR           Input directory containing documents to convert"
  echo "  -o, --output DIR          Output directory for converted markdown files"
  echo "  --force                   Force conversion of all files, even if they already exist"
  echo "  --skip-word               Skip Word document processing"
  echo "  --skip-powerpoint         Skip PowerPoint document processing"
  echo "  --skip-pdf                Skip PDF document processing"
  echo "  --resume                  Resume from checkpoint (continue where left off)"
  echo "  --workers N               Number of parallel workers (default: auto-detected)"
  echo "  --memory-limit N          Memory limit per process in MB (default: 4096)"
  echo "  -v, --verbose             Enable verbose output"
  echo "  -d, --debug               Enable debug output"
  echo "  --verbose-debug           Enable verbose debug output"
  echo "  -h, --help                Show this help message"
  echo ""
  echo "Examples:"
  echo "  conv2md.sh -i ~/Documents/MyDocs -o ~/Documents/MyDocs_markdown"
  echo "  conv2md.sh -i ~/Documents/MyDocs -o ~/Documents/MyDocs_markdown --skip-pdf"
  echo "  conv2md.sh -i ~/Documents/MyDocs -o ~/Documents/MyDocs_markdown --workers 4"
}

# Set up signal handlers for graceful shutdown
setup_signal_handlers() {
  log_debug "Setting up signal handlers"
  
  # Create a flag file to indicate normal operation
  touch "${temp_dir}/.normal_operation"
  
  # Set up trap for INT, TERM, and EXIT signals
  trap 'handle_signal INT' INT
  trap 'handle_signal TERM' TERM
  trap 'handle_signal EXIT' EXIT
  
  log_debug "Signal handlers set up successfully"
}

# Handle signals for graceful shutdown
handle_signal() {
  local signal="$1"
  
  # If we're already in cleanup, don't do anything
  if [[ -f "${temp_dir}/.cleanup_in_progress" ]]; then
    return
  fi
  
  # Create a flag file to indicate cleanup is in progress
  if [[ -d "${temp_dir}" ]]; then
    touch "${temp_dir}/.cleanup_in_progress"
  else
    # If temp_dir doesn't exist, create it
    mkdir -p "${temp_dir}" 2>/dev/null
    touch "${temp_dir}/.cleanup_in_progress" 2>/dev/null
  fi
  
  # Remove the normal operation flag
  if [[ -d "${temp_dir}" ]]; then
    rm -f "${temp_dir}/.normal_operation" 2>/dev/null || true
  fi
  
  if [[ "$signal" == "INT" || "$signal" == "TERM" ]]; then
    log_warning "Received $signal signal. Cleaning up and exiting..."
    # Create an interrupt flag for child processes to check
    if [[ -d "${temp_dir}" ]]; then
      touch "${temp_dir}/.interrupt_flag" 2>/dev/null || true
    fi
    # Perform cleanup
    cleanup
    exit 1
  elif [[ "$signal" == "EXIT" ]]; then
    # Only perform cleanup if we're not already in an interrupt handler
    if [[ ! -f "${temp_dir}/.interrupt_flag" ]]; then
      log_debug "Performing cleanup on exit"
      cleanup
    fi
  fi
}

# Function to initialize SQLite checkpoint database
initialize_checkpoint_db() {
  # Skip if SQLite is not available
  if ! command -v sqlite3 &>/dev/null; then
    log_debug "SQLite not available, using text-based checkpoint file"
    return 1
  fi

  local db_path="${log_dir}/.checkpoint.db"
  
  # Create the database if it doesn't exist
  if [[ ! -f "$db_path" ]]; then
    log_debug "Creating SQLite checkpoint database at $db_path"
    sqlite3 "$db_path" <<EOF
CREATE TABLE processed_files (
  file_path TEXT PRIMARY KEY,
  timestamp INTEGER,
  status INTEGER
);
CREATE INDEX idx_file_path ON processed_files(file_path);
EOF
  fi
  
  # Import existing checkpoint file if it exists and the database is empty
  # This is for backward compatibility with previous versions that used text files
  if [[ -f "$checkpoint_file" && -s "$checkpoint_file" ]]; then
    local count
    count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM processed_files;")
    
    if [[ "$count" -eq 0 ]]; then
      log_info "Importing existing checkpoint file to database (this may take a moment for large files)"
      
      # Create a temporary file with SQL commands
      local temp_sql="${temp_dir}/import_checkpoint.sql"
      echo "BEGIN TRANSACTION;" > "$temp_sql"
      
      # Process the checkpoint file in chunks to avoid memory issues
      local chunk_size=1000
      local line_count=0
      local total_lines
      total_lines=$(wc -l < "$checkpoint_file")
      
      log_debug "Importing $total_lines entries from checkpoint file"
      
      while IFS= read -r file_path; do
        # Escape single quotes in the file path
        local escaped_file="${file_path//\'/\'\'}"
        echo "INSERT OR IGNORE INTO processed_files VALUES ('$escaped_file', $(date +%s), 0);" >> "$temp_sql"
        
        line_count=$((line_count + 1))
        
        # Execute in chunks
        if [[ $((line_count % chunk_size)) -eq 0 || $line_count -eq $total_lines ]]; then
          echo "COMMIT;" >> "$temp_sql"
          sqlite3 "$db_path" < "$temp_sql"
          echo "BEGIN TRANSACTION;" > "$temp_sql"
          log_debug "Imported $line_count of $total_lines entries ($(( (line_count * 100) / total_lines ))%)"
        fi
      done < "$checkpoint_file"
      
      # Ensure final commit
      if [[ -s "$temp_sql" && $(tail -n 1 "$temp_sql") != "COMMIT;" ]]; then
        echo "COMMIT;" >> "$temp_sql"
        sqlite3 "$db_path" < "$temp_sql"
      fi
      
      rm -f "$temp_sql"
      
      # Backup the original checkpoint file
      mv "$checkpoint_file" "${checkpoint_file}.imported"
      log_info "Checkpoint file imported to database and backed up to ${checkpoint_file}.imported"
    else
      log_debug "Checkpoint database already contains $count entries, skipping import"
    fi
  fi
  
  checkpoint_db="$db_path"
  log_debug "Using SQLite checkpoint database: $checkpoint_db"
  return 0
}

# Function to check if a file is in the checkpoint database
is_in_checkpoint_db() {
  local file="$1"
  local db_path="$checkpoint_db"
  
  # Skip if SQLite is not available or database not initialized
  if [[ ! -f "$db_path" ]]; then
    return 1
  fi
  
  # Escape single quotes in the file path
  local escaped_file="${file//\'/\'\'}"
  
  # Query the database
  local result
  result=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM processed_files WHERE file_path='$escaped_file';")
  
  [[ "$result" -gt 0 ]]
}

# Function to add a file to the checkpoint database
add_to_checkpoint_db() {
  local file="$1"
  local status="${2:-0}"
  local db_path="$checkpoint_db"
  
  # Skip if SQLite is not available or database not initialized
  if [[ ! -f "$db_path" ]]; then
    return 1
  fi
  
  # Escape single quotes in the file path
  local escaped_file="${file//\'/\'\'}"
  
  # Insert into the database
  sqlite3 "$db_path" "INSERT OR REPLACE INTO processed_files VALUES ('$escaped_file', $(date +%s), $status);"
}

# Function to flush temporary checkpoint entries to the database
flush_checkpoint_db() {
  local temp_file="$1"
  local db_path="$checkpoint_db"
  
  # Skip if SQLite is not available or database not initialized
  if [[ ! -f "$db_path" || ! -f "$temp_file" ]]; then
    return 1
  fi
  
  # Create a temporary SQL file
  local temp_sql="${temp_dir}/flush_checkpoint.sql"
  echo "BEGIN TRANSACTION;" > "$temp_sql"
  
  # Process the temporary checkpoint file
  while IFS= read -r file_path; do
    # Escape single quotes in the file path
    local escaped_file="${file_path//\'/\'\'}"
    echo "INSERT OR REPLACE INTO processed_files VALUES ('$escaped_file', $(date +%s), 0);" >> "$temp_sql"
  done < "$temp_file"
  
  echo "COMMIT;" >> "$temp_sql"
  
  # Execute the SQL file
  sqlite3 "$db_path" < "$temp_sql"
  
  # Clean up
  rm -f "$temp_sql"
  true > "$temp_file"  # Empty the temporary file
}

# Function to flush temporary checkpoint files to the main checkpoint file
flush_temp_checkpoints() {
  # Find all temporary checkpoint files
  local temp_checkpoints=()
  if [[ -d "$temp_dir" ]]; then
    # shellcheck disable=SC2207
    temp_checkpoints=($(find "$temp_dir" -name "temp_checkpoint.*" -type f 2>/dev/null))
  fi
  
  # If no temporary checkpoints found, return
  if [[ ${#temp_checkpoints[@]} -eq 0 ]]; then
    return 0
  fi
  
  log_debug "Flushing ${#temp_checkpoints[@]} temporary checkpoint files"
  
  # If using SQLite database
  if [[ -n "$checkpoint_db" && -f "$checkpoint_db" ]]; then
    for temp_file in "${temp_checkpoints[@]}"; do
      if [[ -f "$temp_file" ]]; then
        flush_checkpoint_db "$temp_file"
        rm -f "$temp_file" 2>/dev/null || true
      fi
    done
  else
    # Only use text-based checkpoint file if SQLite is not available
    if [[ -n "$checkpoint_file" ]]; then
      # Merge all temporary checkpoints with the main checkpoint file (original method)
      {
        flock -w 5 200
        for temp_file in "${temp_checkpoints[@]}"; do
          if [[ -f "$temp_file" ]]; then
            cat "$temp_file" >> "$checkpoint_file" 2>/dev/null || true
            rm -f "$temp_file" 2>/dev/null || true
          fi
        done
      } 200>"${log_dir}/.checkpoint.lock"
    else
      log_warning "No checkpoint mechanism available. Temporary checkpoints will be lost."
      # Clean up temporary files anyway
      for temp_file in "${temp_checkpoints[@]}"; do
        rm -f "$temp_file" 2>/dev/null || true
      done
    fi
  fi
  
  log_debug "Temporary checkpoint files flushed"
}

# Function to clean up resources
cleanup() {
  log_debug "Cleaning up resources..."
  
  # Flush any temporary checkpoint files
  flush_temp_checkpoints
  
  # Clean up RAM disk if we're using one
  if type -t cleanup_ram_disk &>/dev/null; then
    cleanup_ram_disk
  else
    # Remove temporary directory if it exists and we're not using RAM disk
    if [[ -d "$temp_dir" ]]; then
      log_debug "Removing temporary directory: $temp_dir"
      rm -rf "$temp_dir" 2>/dev/null || true
    fi
  fi
  
  # Remove interrupt flag if it exists
  if [[ -f "${log_dir}/.interrupt_flag" ]]; then
    log_debug "Removing interrupt flag"
    rm -f "${log_dir}/.interrupt_flag" 2>/dev/null || true
  fi
  
  # Rotate log files if they're too large
  log_debug "Rotating log files if needed"
  
  if [[ -n "$output_log" ]]; then
    rotate_log_file "$output_log"
  fi
  
  if [[ -n "$error_log" ]]; then
    rotate_log_file "$error_log"
  fi
  
  if [[ -n "$debug_log" ]]; then
    rotate_log_file "$debug_log"
  fi
  
  if [[ -n "$conversion_log" ]]; then
    rotate_log_file "$conversion_log"
  fi
  
  log_debug "Log rotation completed"
}

# Rotate log files to prevent them from growing too large
rotate_logs() {
  log_debug "Starting log rotation"
  
  # Rotate each log file
  if [[ -n "$output_log" ]]; then
    rotate_log_file "$output_log"
  fi
  
  if [[ -n "$error_log" ]]; then
    rotate_log_file "$error_log"
  fi
  
  if [[ -n "$debug_log" ]]; then
    rotate_log_file "$debug_log"
  fi
  
  if [[ -n "$conversion_log" ]]; then
    rotate_log_file "$conversion_log"
  fi
  
  log_debug "Log rotation completed"
}

# Function to rotate a specific log file
rotate_log_file() {
  local log_file="$1"
  
  # Define the maximum number of log files to keep
  local max_logs=5
  
  # Skip if the log file doesn't exist
  if [[ ! -f "$log_file" ]]; then
    log_debug "Log file does not exist, skipping rotation: $log_file"
    return 0
  fi
  
  # Get the log file size
  local file_size
  file_size=$(du -k "$log_file" 2>/dev/null | cut -f1)
  
  # Skip if the file is empty or very small
  if [[ -z "$file_size" || "$file_size" -lt 5 ]]; then
    log_debug "Log file is empty or very small, skipping rotation: $log_file"
    return 0
  fi
  
  log_debug "Rotating log file: $log_file (size: ${file_size}KB)"
  
  # Remove the oldest log file if it exists
  if [[ -f "${log_file}.${max_logs}" ]]; then
    rm -f "${log_file}.${max_logs}" 2>/dev/null || log_warning "Failed to remove old log file: ${log_file}.${max_logs}"
  fi
  
  # Shift all existing log files
  for (( i=max_logs-1; i>=1; i-- )); do
    local j=$((i+1))
    if [[ -f "${log_file}.${i}" ]]; then
      mv "${log_file}.${i}" "${log_file}.${j}" 2>/dev/null || log_warning "Failed to rotate log file: ${log_file}.${i} to ${log_file}.${j}"
    fi
  done
  
  # Move the current log file
  mv "$log_file" "${log_file}.1" 2>/dev/null || log_warning "Failed to rotate current log file: $log_file to ${log_file}.1"
  
  # Create a new empty log file
  touch "$log_file" 2>/dev/null || log_warning "Failed to create new log file: $log_file"
  
  log_debug "Log rotation completed for: $log_file"
}

# Set up logging
setup_logging() {
  # Create logs directory if it doesn't exist
  if [[ ! -d "$log_dir" ]]; then
    mkdir -p "$log_dir" || {
      echo "Failed to create log directory: $log_dir"
      exit 1
    }
  fi
  
  # Set up log files
  output_log="${log_dir}/output.log"
  error_log="${log_dir}/error.log"
  debug_log="${log_dir}/debug.log"
  conversion_log="${log_dir}/conversion.log"
  
  # Export log variables for subprocesses
  export log_dir
  export output_log
  export error_log
  export debug_log
  export conversion_log
  
  # Create log files if they don't exist
  touch "$output_log" "$error_log" "$debug_log" "$conversion_log" || {
    echo "Failed to create log files"
    exit 1
  }
  
  # Set proper permissions for log files
  chmod 644 "$output_log" "$error_log" "$debug_log" "$conversion_log" 2>/dev/null || true
  
  # Write initial entries to log files
  echo "[$(date +"$date_format")] Logging initialized for conv2md session: $instance_id" >> "$output_log"
  echo "[$(date +"$date_format")] Logging initialized for conv2md session: $instance_id" >> "$error_log"
  echo "[$(date +"$date_format")] Logging initialized for conv2md session: $instance_id" >> "$debug_log"
  echo "[$(date +"$date_format")] Logging initialized for conv2md session: $instance_id" >> "$conversion_log"
  
  # Set up debug logging
  if [[ "$debug" == true ]]; then
    export DEBUG=true
  fi
  
  # Log setup completion
  log_debug "Logging setup completed. Log files are in: $log_dir"
}

# Main function
main() {
  # Parse command line arguments
  parse_args "$@"
  
  # Validate arguments
  validate_args
  
  # Set up logging
  setup_logging
  
  # Log script start
  log_info "Starting conversion process with instance ID: $instance_id"
  log_info "Input directory: $input_dir"
  log_info "Output directory: $output_dir"
  log_debug "Verbose mode: $verbose"
  log_debug "Debug mode: $debug"
  log_debug "Force conversion: $force_conversion"
  
  # Create output directory if it doesn't exist
  if [[ ! -d "$output_dir" ]]; then
    log_debug "Creating output directory: $output_dir"
    mkdir -p "$output_dir" || {
      log_error "Failed to create output directory: $output_dir"
      exit 1
    }
  fi
  
  # Create temp directory if it doesn't exist
  if [[ ! -d "$temp_dir" ]]; then
    log_debug "Creating temporary directory: $temp_dir"
    mkdir -p "$temp_dir" || {
      log_error "Failed to create temporary directory: $temp_dir"
      exit 1
    }
  fi
  
  # Initialize SQLite checkpoint database if resuming
  if [[ "$resume_from_checkpoint" == true ]]; then
    if command -v sqlite3 &>/dev/null; then
      initialize_checkpoint_db
      log_info "Using SQLite for checkpoint tracking (faster lookups)"
      # If we're using SQLite, we don't need the text-based checkpoint file
      checkpoint_file=""
    else
      log_info "SQLite not available, using text-based checkpoint file"
      # Create the checkpoint file if it doesn't exist
      if [[ ! -f "$checkpoint_file" ]]; then
        touch "$checkpoint_file" || {
          log_error "Failed to create checkpoint file: $checkpoint_file"
          exit 1
        }
      fi
    fi
  fi
  
  # Set up signal handlers
  setup_signal_handlers
  
  # Try to set up RAM disk for temporary files (optimization)
  if type -t setup_ram_disk &>/dev/null; then
    if setup_ram_disk; then
      log_info "Using RAM disk for temporary files"
    else
      log_debug "RAM disk setup failed, using regular disk for temporary files"
      # Create temp directory if it doesn't exist and we're not using RAM disk
      if [[ ! -d "$temp_dir" ]]; then
        log_debug "Creating temporary directory: $temp_dir"
        mkdir -p "$temp_dir" || {
          log_error "Failed to create temporary directory: $temp_dir"
          exit 1
        }
      fi
    fi
  else
    # Create temp directory if it doesn't exist
    if [[ ! -d "$temp_dir" ]]; then
      log_debug "Creating temporary directory: $temp_dir"
      mkdir -p "$temp_dir" || {
        log_error "Failed to create temporary directory: $temp_dir"
        exit 1
      }
    fi
  fi
  
  # Create or check timestamp file for optimized file finding
  local timestamp_file="${log_dir}/.last_run_timestamp"
  if [[ ! -f "$timestamp_file" ]]; then
    log_debug "Creating timestamp file for tracking last run"
    touch -t 197001010000 "$timestamp_file" 2>/dev/null || touch "$timestamp_file"
  else
    log_debug "Found existing timestamp file from previous run"
  fi
  
  # Start memory monitor if enabled
  if [[ "${memory_monitor_enabled:-false}" == "true" ]]; then
    log_info "Memory monitoring is enabled with limit: ${memory_limit_mb:-4096} MB"
  fi
  
  # Process files by type
  local overall_status=0
  
  # Process Word files if not skipped
  if [[ "$skip_word" != true ]]; then
    log_info "Processing Word files..."
    if ! process_file_type "Word"; then
      log_warning "Word file processing encountered errors"
      overall_status=1
    fi
  else
    log_info "Skipping Word files as requested"
  fi
  
  # Process PowerPoint files if not skipped
  if [[ "$skip_powerpoint" != true ]]; then
    log_info "Processing PowerPoint files..."
    if ! process_file_type "PowerPoint"; then
      log_warning "PowerPoint file processing encountered errors"
      overall_status=1
    fi
  else
    log_info "Skipping PowerPoint files as requested"
  fi
  
  # Process PDF files if not skipped
  if [[ "$skip_pdf" != true ]]; then
    log_info "Processing PDF files..."
    if ! process_file_type "PDF"; then
      log_warning "PDF file processing encountered errors"
      overall_status=1
    fi
  else
    log_info "Skipping PDF files as requested"
  fi
  
  # Update timestamp file after successful processing
  if [[ $overall_status -eq 0 ]]; then
    log_debug "Updating timestamp file after successful run"
    touch "$timestamp_file"
  fi
  
  # Clean up
  cleanup
  
  # Log completion
  if [[ $overall_status -eq 0 ]]; then
    log_info "Conversion process completed successfully"
  else
    log_warning "Conversion process completed with errors"
  fi
  
  return $overall_status
}

# Process a single file
process_single_file() {
  local file="$1"
  
  # Set resource limits for this process
  if type -t set_process_limits &>/dev/null; then
    set_process_limits
  fi
  
  if needs_conversion "$file" || [[ "$force_conversion" == true ]]; then
    log_debug "Converting file: $file"
    convert_file "$file" "$input_dir" "$output_dir"
    local conversion_status=$?
    log_debug "Conversion completed for file: $file with status: $conversion_status"
    
    # Add to checkpoint if conversion was successful
    if [[ "$resume_from_checkpoint" == true && $conversion_status -eq 0 ]]; then
      # If using SQLite database
      if [[ -n "$checkpoint_db" && -f "$checkpoint_db" ]]; then
        # Add directly to database for every 10th file to reduce I/O
        local random_num=$((RANDOM % 10))
        if [[ $random_num -eq 0 ]]; then
          add_to_checkpoint_db "$file" "$conversion_status"
        else
          # Otherwise add to temporary file
          echo "$file" >> "${temp_dir}/temp_checkpoint.$$"
          
          # Periodically flush the temporary checkpoint
          local temp_count
          temp_count=$(wc -l < "${temp_dir}/temp_checkpoint.$$" 2>/dev/null || echo "0")
          if [[ $temp_count -ge 10 ]]; then
            flush_checkpoint_db "${temp_dir}/temp_checkpoint.$$"
          fi
        fi
      elif [[ -n "$checkpoint_file" ]]; then
        # Only use text-based checkpoint file if SQLite is not available
        # Original method: add to temporary checkpoint file
        echo "$file" >> "${temp_dir}/temp_checkpoint.$$"
        
        # Periodically merge the temporary checkpoint with the main one
        local temp_count
        temp_count=$(wc -l < "${temp_dir}/temp_checkpoint.$$" 2>/dev/null || echo "0")
        if [[ $temp_count -ge 10 ]]; then
          {
            flock -w 2 200
            cat "${temp_dir}/temp_checkpoint.$$" >> "$checkpoint_file"
            true > "${temp_dir}/temp_checkpoint.$$"
          } 200>"${log_dir}/.checkpoint.lock"
        fi
      else
        log_debug "No checkpoint mechanism available, skipping checkpoint update"
      fi
    fi
    
    return $conversion_status
  else
    log_debug "File already converted, skipping: $file"
    return 0
  fi
}

# Main function execution
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

# Function to check if a file needs conversion
needs_conversion() {
  local file="$1"
  
  # If force conversion is enabled, always return true
  if [[ "$force_conversion" == true ]]; then
    return 0
  fi
  
  # If we're resuming from a checkpoint, check if the file is in the checkpoint
  if [[ "$resume_from_checkpoint" == true ]]; then
    # First try SQLite database if available
    if [[ -n "$checkpoint_db" && -f "$checkpoint_db" ]]; then
      if is_in_checkpoint_db "$file"; then
        # File is in the checkpoint database, so it's already been processed
        log_debug "File found in checkpoint database, skipping: $file"
        return 1
      fi
    # Fall back to text file if SQLite not available and checkpoint_file is set
    elif [[ -n "$checkpoint_file" && -f "$checkpoint_file" ]]; then
      if grep -q "^$file$" "$checkpoint_file"; then
        # File is in the checkpoint file, so it's already been processed
        log_debug "File found in checkpoint file, skipping: $file"
        return 1
      fi
    fi
  fi
  
  # Get the base name of the file without extension
  local base_name
  base_name=$(basename "$file")
  base_name="${base_name%.*}"
  
  # Construct the output file path
  local output_file="${output_dir}/${base_name}.md"
  
  # For PDF files, check for marker_single output directory structure
  local file_ext="${file##*.}"
  file_ext=$(echo "$file_ext" | tr '[:upper:]' '[:lower:]')
  
  if [[ "$file_ext" == "pdf" ]]; then
    # Check for marker_single output directory
    local marker_output_dir="${output_dir}/${base_name}"
    local marker_md_file="${marker_output_dir}/${base_name}.md"
    
    # If marker output directory exists with the markdown file, consider it already converted
    if [[ -d "$marker_output_dir" && -f "$marker_md_file" ]]; then
      log_debug "Found marker_single output directory structure for: $file"
      
      # If the output file doesn't exist but should be a symlink to the marker file, create it
      if [[ ! -f "$output_file" ]]; then
        log_debug "Creating symlink from $marker_md_file to $output_file"
        mkdir -p "$(dirname "$output_file")"
        ln -sf "$marker_md_file" "$output_file" || cp "$marker_md_file" "$output_file"
      fi
      
      return 1  # Skip conversion
    fi
  fi
  
  # Check if the output file exists
  if [[ -f "$output_file" ]]; then
    # If the output file exists, check if the input file is newer
    local input_mtime
    local output_mtime
    
    if [[ "$(uname)" == "Darwin" ]]; then
      # macOS
      input_mtime=$(stat -f %m "$file")
      output_mtime=$(stat -f %m "$output_file")
    else
      # Linux
      input_mtime=$(stat -c %Y "$file")
      output_mtime=$(stat -c %Y "$output_file")
    fi
    
    # If the input file is newer, return true
    if [[ $input_mtime -gt $output_mtime ]]; then
      return 0
    fi
    
    # Output file exists and is not older than the input file
    return 1
  fi
  
  # Output file doesn't exist, so conversion is needed
  return 0
}

# Convert a file to markdown
convert_file() {
  local file="$1"
  local start_time
  start_time=$(date +%s)
  
  # Export log_dir and conversion_log for subprocesses
  export log_dir
  export conversion_log
  
  # Calculate relative path from input_dir
  local rel_path=""
  if [[ "$file" == "$input_dir"* ]]; then
    rel_path="${file#"$input_dir"}"
    rel_path="${rel_path#/}"
  fi
  
  # Get the directory and base name
  local base_name
  base_name=$(basename "$file")
  local extension="${base_name##*.}"
  local name_no_ext="${base_name%.*}"
  
  # Replace spaces with underscores in the base name
  local sanitized_name
  sanitized_name=$(echo "$name_no_ext" | tr ' ' '_')
  
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
  
  # Create the output directory if it doesn't exist
  mkdir -p "$(dirname "$output_file")"
  
  # Initialize conversion status
  local conversion_status=0
  
  # Convert the file based on its extension
  case "${extension,,}" in
    pdf)
      if [[ "$skip_pdf" -eq 1 ]]; then
        log_debug "Skipping PDF file: $file"
        return 0
      fi
      convert_pdf_to_md "$file" "$output_file" || conversion_status=$?
      ;;
    docx|doc)
      if [[ "$skip_word" -eq 1 ]]; then
        log_debug "Skipping Word file: $file"
        return 0
      fi
      convert_word_to_md "$file" "$output_file" || conversion_status=$?
      ;;
    pptx|ppt)
      if [[ "$skip_powerpoint" -eq 1 ]]; then
        log_debug "Skipping PowerPoint file: $file"
        return 0
      fi
      convert_powerpoint_to_md "$file" "$output_file" || conversion_status=$?
      ;;
    *)
      log_error "Unsupported file type: $extension"
      return 1
      ;;
  esac
  
  # Calculate duration
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  # Get output file size if it exists
  local output_size=0
  if [[ -f "$output_file" ]]; then
    output_size=$(stat -f%z "$output_file" 2>/dev/null || stat --format=%s "$output_file" 2>/dev/null)
  fi
  
  # Skip logging if the conversion was done by convert_pdf_to_md, which already logs
  if [[ "${extension,,}" != "pdf" ]]; then
    # Log the conversion result
    if [[ $conversion_status -eq 0 ]]; then
      log_conversion "$file" "$output_file" "SUCCESS" "$duration" "$output_size"
      if [[ "$verbose" -eq 1 ]]; then
        log_info "Converted: $file -> $output_file (${duration}s, ${output_size} bytes)"
      fi
    else
      log_conversion "$file" "$output_file" "FAILED" "$duration" "0"
      if [[ "$verbose" -eq 1 ]]; then
        log_error "Failed to convert: $file -> $output_file (${duration}s)"
      fi
    fi
  else
    # For PDF files, just log to console if verbose is enabled
    if [[ "$verbose" -eq 1 ]]; then
      if [[ $conversion_status -eq 0 ]]; then
        log_info "Completed conversion of: $file"
      else
        log_error "Failed to convert: $file"
      fi
    fi
  fi
  
  return $conversion_status
}

# Function to create a RAM disk for temporary files
setup_ram_disk() {
  # Check if we're already using a RAM disk
  if [[ "${using_ram_disk:-false}" == "true" ]]; then
    return 0
  fi
  
  # Default RAM disk size (in MB)
  local ram_disk_size=512
  
  # Check if we have enough free memory (at least 2x the RAM disk size)
  local free_memory=0
  if is_macos; then
    # macOS memory check
    local page_size
    page_size=$(sysctl -n hw.pagesize)
    local free_pages
    free_pages=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
    free_memory=$((page_size * free_pages / 1024 / 1024))
  else
    # Linux memory check
    if command -v free >/dev/null 2>&1; then
      free_memory=$(free -m | grep "Mem:" | awk '{print $7}')
    fi
  fi
  
  # If we can't determine free memory or it's less than 2x RAM disk size, don't use RAM disk
  if [[ $free_memory -lt $((ram_disk_size * 2)) ]]; then
    log_debug "Not enough free memory for RAM disk (need at least $((ram_disk_size * 2))MB, have ${free_memory}MB)"
    return 1
  fi
  
  # Create RAM disk
  local ram_disk_path=""
  if is_macos; then
    # macOS RAM disk creation
    ram_disk_path="/Volumes/conv2md_ram_${instance_id}"
    local sectors=$((ram_disk_size * 2048))  # 512 bytes per sector
    
    # Create RAM disk
    local disk_id
    disk_id=$(hdiutil attach -nomount ram://$sectors 2>/dev/null)
    if [[ -n "$disk_id" ]]; then
      # Format RAM disk
      if ! diskutil erasevolume HFS+ "conv2md_ram_${instance_id}" "$disk_id" >/dev/null 2>&1; then
        log_warning "Failed to format RAM disk"
        hdiutil detach "$disk_id" >/dev/null 2>&1 || true
        return 1
      fi
      
      log_info "Created RAM disk at $ram_disk_path ($ram_disk_size MB)"
      export ram_disk_id="$disk_id"
      export ram_disk_path="$ram_disk_path"
      export using_ram_disk=true
    else
      log_warning "Failed to create RAM disk"
      return 1
    fi
  else
    # Linux RAM disk creation
    ram_disk_path="/tmp/conv2md_ram_${instance_id}"
    mkdir -p "$ram_disk_path"
    
    # Mount RAM disk
    if ! mount -t tmpfs -o size=${ram_disk_size}m tmpfs "$ram_disk_path" 2>/dev/null; then
      log_warning "Failed to create RAM disk (requires root privileges)"
      rmdir "$ram_disk_path" 2>/dev/null || true
      return 1
    fi
    
    log_info "Created RAM disk at $ram_disk_path ($ram_disk_size MB)"
    export ram_disk_path="$ram_disk_path"
    export using_ram_disk=true
  fi
  
  # Set temp directory to RAM disk
  if [[ -n "$ram_disk_path" && -d "$ram_disk_path" ]]; then
    temp_dir="${ram_disk_path}/temp"
    mkdir -p "$temp_dir"
    chmod 700 "$temp_dir"
    export TMPDIR="$temp_dir"
    log_info "Using RAM disk for temporary files: $temp_dir"
    return 0
  fi
  
  return 1
}

# Function to clean up RAM disk
cleanup_ram_disk() {
  if [[ "${using_ram_disk:-false}" != "true" ]]; then
    return 0
  fi
  
  log_debug "Cleaning up RAM disk"
  
  if is_macos; then
    # macOS RAM disk cleanup
    if [[ -n "${ram_disk_id:-}" ]]; then
      hdiutil detach "$ram_disk_id" >/dev/null 2>&1 || {
        log_warning "Failed to detach RAM disk: $ram_disk_id"
        # Force detach
        hdiutil detach "$ram_disk_id" -force >/dev/null 2>&1 || true
      }
    fi
  else
    # Linux RAM disk cleanup
    if [[ -n "${ram_disk_path:-}" && -d "$ram_disk_path" ]]; then
      umount "$ram_disk_path" 2>/dev/null || {
        log_warning "Failed to unmount RAM disk: $ram_disk_path"
        # Force unmount
        umount -f "$ram_disk_path" 2>/dev/null || true
      }
      rmdir "$ram_disk_path" 2>/dev/null || true
    fi
  fi
  
  export using_ram_disk=false
  log_debug "RAM disk cleanup completed"
}

# Function to check multiple files against the checkpoint database in a single query
batch_check_checkpoint_db() {
  local file_list="$1"
  local output_file="$2"
  local db_path="$checkpoint_db"
  
  # Skip if SQLite is not available or database not initialized
  if [[ ! -f "$db_path" || ! -f "$file_list" ]]; then
    return 1
  fi
  
  log_debug "Batch checking files against checkpoint database"
  
  # Create a temporary SQL file
  local temp_sql="${temp_dir}/batch_check.sql"
  echo "CREATE TEMPORARY TABLE files_to_check (path TEXT PRIMARY KEY);" > "$temp_sql"
  
  # Process the file list and create SQL to insert into temporary table
  echo "BEGIN TRANSACTION;" >> "$temp_sql"
  while IFS= read -r file_path; do
    # Escape single quotes in the file path
    local escaped_file="${file_path//\'/\'\'}"
    echo "INSERT OR IGNORE INTO files_to_check VALUES ('$escaped_file');" >> "$temp_sql"
  done < "$file_list"
  echo "COMMIT;" >> "$temp_sql"
  
  # Query to find which files are already in the checkpoint database
  echo "SELECT f.path FROM files_to_check f 
        INNER JOIN processed_files p ON f.path = p.file_path;" >> "$temp_sql"
  
  # Execute the query and save results to output file
  sqlite3 "$db_path" < "$temp_sql" > "$output_file"
  
  # Clean up
  rm -f "$temp_sql"
  
  return 0
}