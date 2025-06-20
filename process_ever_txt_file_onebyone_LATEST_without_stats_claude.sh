#!/bin/bash

# Check for required commands
if ! command -v stdbuf &>/dev/null; then
  echo "Error: stdbuf command not found. Install coreutils package."
  exit 1
fi
# tput is still useful for cursor control and screen clearing at the very beginning/end
if ! command -v tput &>/dev/null; then
  echo "Error: tput command not found. Install ncurses-bin package."
  exit 1
fi

# Configuration variables at the top
readonly MAX_RETRIES=3
readonly INACTIVITY_TIMEOUT=300    # 5 minutes
readonly MONITOR_INTERVAL=30       # 30 seconds
readonly PYTHON_CONFIG_THREADS=100 # This is the configured number of threads for Python script
readonly CHECKED_DIR="!checked"    # Define the checked directory for processed files

# Global variables for process tracking
current_pid=""
monitor_pid=""
python_main_pid=""
declare -a all_child_pids=()
terminate_requested=0
VERBOSE_MODE=""                 # New global variable for verbose mode (passed to Python)
CURRENT_FILE_BEING_PROCESSED="" # Global variable to hold the name of the file currently being processed

# --- SIMPLIFIED DISPLAY FUNCTIONS (Bash no longer manages split screen) ---
# Display messages directly to stdout. Python handles the fancy stuff.
display_message() {
  echo "[$(date '+%H:%M:%S')] $1"
}

# Function to kill process tree
kill_process_tree() {
  local pid=$1
  local sig=${2:-TERM}

  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    # Get all child processes
    local children=$(pgrep -P "$pid" 2>/dev/null || true)

    # Kill children first
    for child in $children; do
      kill_process_tree "$child" "$sig"
    done

    # Kill the parent
    kill -"$sig" "$pid" 2>/dev/null || true
  fi
}

# Enhanced cleanup function
cleanup_resources() {
  # Only show cleanup message if we're actually terminating
  if [[ $terminate_requested -eq 1 ]]; then
    display_message "Performing cleanup..."
  fi

  # Kill all tracked processes and their children
  for pid in "${all_child_pids[@]}" "$current_pid" "$monitor_pid" "$python_main_pid"; do
    if [[ -n "$pid" ]]; then
      kill_process_tree "$pid" "TERM"
    fi
  done

  # Give processes time to terminate gracefully
  if [[ $terminate_requested -eq 1 ]]; then
    sleep 1

    # Force kill if still running
    for pid in "${all_child_pids[@]}" "$current_pid" "$monitor_pid" "$python_main_pid"; do
      if [[ -n "$pid" ]]; then
        kill_process_tree "$pid" "KILL"
      fi
    done

    # Kill any remaining python processes from this script (as a fallback)
    pkill -f "LATEST-TO_USE_ssh25_09-06-25_MultipleProtocolFancyStats_w0rking.py" 2>/dev/null || true
  fi

  # Reset terminal to normal state
  tput cnorm # Ensure cursor is visible
  # Clear from cursor to end of screen (if still in a weird state)
  tput cup $(tput lines) 0 2>/dev/null || true
  tput ed 2>/dev/null || true
  clear # Clear the entire screen at the very end

  if [[ $terminate_requested -eq 1 ]]; then
    echo "Cleanup completed."
  fi
}

# Enhanced signal handler with immediate response
handle_sigint() {
  echo -e "\n\n*** SIGINT received - Terminating immediately ***"
  terminate_requested=1
  cleanup_resources
  exit 130
}

# No longer need handle_winch as bash isn't managing screen layout

# Set up signal handling with immediate response
trap handle_sigint SIGINT SIGTERM
trap cleanup_resources EXIT

# Parse command-line arguments for the bash script
while getopts "v" opt; do
  case $opt in
  v)
    VERBOSE_MODE="-v"
    echo "Verbose mode enabled for Python script."
    ;;
  \?)
    echo "Invalid option: -$OPTARG" >&2
    exit 1
    ;;
  esac
done
shift $((OPTIND - 1))

# Function to process a single file with timeout monitoring
process_file() {
  local file="$1"
  local max_retries=$MAX_RETRIES
  local retry_count=0
  local success=0

  # Create the !checked directory if it doesn't exist
  mkdir -p "$CHECKED_DIR"

  # Get total hosts for the current file (this is still useful for initial check)
  local TOTAL_HOSTS=$(wc -l <"$file" | awk '{print $1}')

  if [ "$TOTAL_HOSTS" -eq 0 ]; then
    display_message "Skipping empty file: $file"
    mv "$file" "$CHECKED_DIR/"
    return 0
  fi

  # Set the global variable for the file being processed
  CURRENT_FILE_BEING_PROCESSED="$file"

  # Clear screen and hide cursor before Python starts its display
  clear
  tput civis # Hide cursor

  while [[ $retry_count -lt $max_retries && $terminate_requested -eq 0 ]]; do
    display_message "Processing attempt $((retry_count + 1)) of $max_retries for file: $file"
    display_message "Total hosts in file: $TOTAL_HOSTS"

    # Create temporary files for status and timestamp for inactivity monitoring for this attempt
    local status_file=$(mktemp)
    local timestamp_file=$(mktemp)
    touch "$timestamp_file"

    # Start Python script with proper process tracking
    # NO LONGER PIPING PYTHON OUTPUT TO A WHILE LOOP FOR PARSING
    # Python will manage its own output directly to the terminal.
    stdbuf -oL python3 "LATEST-TO_USE_ssh25_09-06-25.py" \
      -f "$file" \
      -p ssh \
      -t "$PYTHON_CONFIG_THREADS" \
      $VERBOSE_MODE & # Run in background

    current_pid=$!
    python_main_pid=$current_pid
    all_child_pids+=("$current_pid")

    # Start inactivity monitor (still relevant)
    (
      while [[ $terminate_requested -eq 0 ]]; do
        sleep $MONITOR_INTERVAL

        # Check if main process is still running
        if ! kill -0 "$current_pid" 2>/dev/null; then
          break
        fi

        # Check for inactivity
        local current_time=$(date +%s)
        local last_modified=$(stat -c %Y "$timestamp_file" 2>/dev/null || echo $current_time)

        if ((current_time - last_modified > INACTIVITY_TIMEOUT)); then
          display_message "Process inactive for $((INACTIVITY_TIMEOUT / 60)) minutes. Killing..."
          kill_process_tree "$current_pid" "KILL"
          break
        fi
      done
    ) &

    monitor_pid=$!
    all_child_pids+=("$monitor_pid")

    # Wait for Python process to complete
    wait "$current_pid" 2>/dev/null
    local python_exit_code=$(cat "$status_file" 2>/dev/null || echo 1)

    # Clean up monitor
    if [[ -n "$monitor_pid" ]] && kill -0 "$monitor_pid" 2>/dev/null; then
      kill "$monitor_pid" 2>/dev/null
      wait "$monitor_pid" 2>/dev/null
    fi

    # Clean up temporary files
    rm -f "$status_file" "$timestamp_file" 2>/dev/null

    # Reset PIDs
    current_pid=""
    monitor_pid=""
    python_main_pid=""

    # Check results
    if [[ $python_exit_code -eq 0 ]]; then
      display_message "Successfully processed: $file"
      mv "$file" "$CHECKED_DIR/"
      if [[ $? -eq 0 ]]; then
        display_message "Moved '$file' to '$CHECKED_DIR/'"
      else
        display_message "Warning: Failed to move '$file' to '$CHECKED_DIR/'"
      fi
      success=1
      break
    elif [[ $terminate_requested -eq 1 ]]; then
      display_message "Processing interrupted for: $file"
      break
    else
      display_message "Processing failed for: $file (Exit code: $python_exit_code)"
      ((retry_count++))
      if [[ $retry_count -lt $max_retries ]]; then
        display_message "Retrying in 5 seconds..."
        sleep 5
      fi
    fi
  done

  # Restore cursor visibility and clear screen after Python finishes for this file
  tput cnorm 2>/dev/null || true
  tput cup $(tput lines) 0 2>/dev/null || true
  tput ed 2>/dev/null || true
  clear # Clear the screen before processing the next file or exiting

  if [[ $success -eq 0 && $terminate_requested -eq 0 ]]; then
    display_message "Giving up on: $file after $max_retries attempts"
  fi

  display_message "Scanning complete for $file!"
  display_message "---------------------------------"

  # No need for a sleep after the file is done, as Python already shows final stats.
  return 0
}

# --- Main Script Execution ---

# Create the !checked directory if it doesn't exist
mkdir -p "$CHECKED_DIR"

if [[ -n "$VERBOSE_MODE" ]]; then
  echo "Starting file processing with Python's verbose mode..."
else
  echo "Starting file processing..."
fi
echo "Press Ctrl+C to interrupt at any time."

# Brief pause to let user read the message
sleep 2

# Main processing loop
for txt_file in *.txt; do
  # If no files match the glob, txt_file will be the literal "*.txt"
  # This check handles the case where no files match the glob
  if [[ ! -f "$txt_file" ]]; then
    if [[ "$txt_file" == "*.txt" ]]; then # Only echo if the glob didn't expand
      clear
      tput cnorm # Ensure cursor is visible
      echo "No .txt files found to process. Exiting."
    fi
    exit 0
  fi

  # Skip excluded file patterns and directories
  [[ "$txt_file" == "output.txt" ]] && continue
  [[ "$txt_file" == "debug_log.txt" ]] && continue
  [[ "$txt_file" == "root_sudo.txt" ]] && continue
  [[ "$txt_file" == "root_access.txt" ]] && continue
  [[ "$txt_file" == checked_*.txt ]] && continue
  [[ "$txt_file" == "$CHECKED_DIR" ]] && continue # Skip the !checked directory itself

  # Check for termination request before processing each file
  if [[ $terminate_requested -eq 1 ]]; then
    clear
    tput cnorm # Ensure cursor is visible
    echo "Termination requested, exiting..."
    exit 130
  fi

  display_message "Processing file: $txt_file"
  process_file "$txt_file"

  # Brief pause between files
  sleep 1
done

# Final cleanup and message
clear
tput cnorm # Ensure cursor is visible
echo "All files processed!"
