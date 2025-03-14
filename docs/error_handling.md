# Improved Error Handling and Variable Management

This document explains the error handling and variable management improvements implemented in the conv2md script.

## Overview

Robust error handling and variable management are critical for shell scripts, especially those that process files and interact with external commands. The conv2md script has been enhanced with several features to improve reliability and prevent common issues like unbound variable errors.

## Key Improvements

### 1. Safe Variable Handling

The script now uses defensive programming techniques to handle variables safely:

- **Default Values**: Variables are assigned default values using the `${var:-default}` syntax to prevent unbound variable errors
- **Existence Checks**: Before using variables, the script checks if they are defined
- **Parameter Validation**: Function parameters are validated before use

Example:
```bash
# Before
local output_dir="${OUTPUT_DIR}"

# After
local output_dir="${3:-}"
if [[ -z "$output_dir" ]]; then
  output_dir="."
  log_warning "Output directory not specified, using current directory"
fi
```

### 2. Safe Command Execution

The script includes several improvements for safely executing external commands:

- **Command Availability Checks**: Before executing external commands, the script checks if they are available
- **Fallback Mechanisms**: Alternative commands or approaches are provided when primary commands are not available
- **Timeout Handling**: Commands that might hang are executed with timeouts

Example:
```bash
# Check if a command exists and find its path
local markitdown_cmd
markitdown_cmd=$(find_command "markitdown")
if [[ -z "$markitdown_cmd" ]]; then
  check_markitdown
  write_to_progress_pipe "failed:1:0:0:$input_file"
  return 1
fi
```

### 3. Robust Path Handling

Path handling has been improved to prevent errors when working with files and directories:

- **Path Existence Checks**: Before operating on paths, the script checks if they exist
- **Directory Creation**: Directories are created as needed before writing files
- **Relative Path Handling**: Relative paths are handled safely with fallbacks

Example:
```bash
# Only try to calculate relative path if input_dir is provided
if [[ -n "$input_dir" ]]; then
  # Use dirname to get the directory of the file
  local file_dir=$(dirname "$file")
  
  # Check if realpath is available
  if command -v realpath &>/dev/null; then
    # Try to get relative path using realpath
    rel_path=$(realpath --relative-to="$input_dir" "$file_dir" 2>/dev/null || echo "")
  else
    # Fallback if realpath is not available
    rel_path="${file_dir#$input_dir}"
    rel_path="${rel_path#/}"  # Remove leading slash if present
  fi
fi
```

### 4. Helper Functions for Common Operations

Several helper functions have been added to ensure consistent and safe handling of common operations:

- **`write_to_progress_pipe`**: Safely writes to the progress pipe, with fallbacks if the pipe is not available
- **`get_file_size`**: Safely gets the size of a file, with fallbacks for different systems
- **`sanitize_for_log`**: Safely sanitizes input for logging to avoid exposing sensitive information

Example:
```bash
# Function to safely write to progress pipe
write_to_progress_pipe() {
  # Check if the function is defined in the main script
  if declare -f _write_to_progress_pipe >/dev/null; then
    _write_to_progress_pipe "$@"
  elif [[ -n "${PROGRESS_PIPE:-}" && -p "${PROGRESS_PIPE}" ]]; then
    # If PROGRESS_PIPE is defined and is a pipe, write directly to it
    echo "$1" > "${PROGRESS_PIPE}"
  else
    # If no progress pipe function or variable is available, just log the message
    log_debug "Progress: $1"
  fi
}
```

### 5. Comprehensive Error Logging

Error logging has been improved to provide more useful information for troubleshooting:

- **Detailed Error Messages**: Error messages include specific information about what went wrong
- **Error Output Capture**: Error output from external commands is captured and logged
- **Status Code Logging**: Status codes from external commands are logged for troubleshooting

Example:
```bash
if [[ $markitdown_status -ne 0 ]]; then
  log_error "MarkItDown conversion failed with status $markitdown_status for file: $sanitized_input"
  log_error "Error output: $error_output"
  write_to_progress_pipe "failed:1:${waited}:0:$input_file"
  return 1
fi
```

### 6. Temporary File Management

Temporary file management has been improved to ensure cleanup even in error cases:

- **Automatic Cleanup**: Temporary files are cleaned up in all exit paths, including error cases
- **Secure Temporary Directories**: Temporary directories are created securely using `mktemp -d`
- **Process-Specific Directories**: Temporary directories include the process ID to avoid conflicts

Example:
```bash
# Create a temporary directory for processing
local temp_dir=$(mktemp -d)

# ... processing ...

# Clean up temporary files
rm -rf "$temp_dir" 2>/dev/null || true
```

## Benefits

These improvements provide several benefits:

1. **Increased Reliability**: The script is less likely to fail due to unbound variables or missing commands
2. **Better Error Messages**: When errors do occur, the messages are more helpful for troubleshooting
3. **Graceful Degradation**: The script can continue operating even when some components are missing
4. **Improved Security**: Temporary files are managed securely and cleaned up properly
5. **Cross-Platform Compatibility**: Fallback mechanisms improve compatibility across different systems

## Best Practices Implemented

The script follows these shell scripting best practices:

1. **Always quote variables**: Variables are quoted to prevent word splitting and globbing
2. **Use local variables**: Variables are declared local to prevent namespace pollution
3. **Check return codes**: Return codes from commands are checked to detect errors
4. **Provide meaningful error messages**: Error messages include specific information about what went wrong
5. **Clean up temporary files**: Temporary files are cleaned up in all exit paths
6. **Use safe commands**: Commands that might fail are executed with error handling
7. **Validate input**: Input is validated before use
8. **Use defensive programming**: Assume things will go wrong and handle them gracefully

## Conclusion

The improved error handling and variable management in the conv2md script make it more robust, reliable, and easier to troubleshoot. These improvements follow best practices for shell scripting and provide a better user experience, especially when dealing with complex document conversion tasks. 