#!/bin/bash

# Check for required commands
if ! command -v stdbuf &>/dev/null; then
  echo "Error: stdbuf command not found. Install coreutils package."
  exit 1
fi
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
live_stats_pid=""
python_main_pid=""
declare -a all_child_pids=()
terminate_requested=0
VERBOSE_MODE=""                 # New global variable for verbose mode
CURRENT_FILE_BEING_PROCESSED="" # Global variable to hold the name of the file currently being processed

# Temporary files for inter-process communication (for live stats)
TEMP_CURRENT_HOST_FILE=$(mktemp)
TEMP_TOTAL_HOSTS_FILE=$(mktemp)
TEMP_LOG_OUTPUT_FILE=$(mktemp) # Temporary file to store the Python script's relevant output for counting

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
  echo -e "\nPerforming cleanup..."

  # Set flag to stop all loops
  terminate_requested=1

  # Kill all tracked processes and their children
  for pid in "${all_child_pids[@]}" "$current_pid" "$monitor_pid" "$live_stats_pid" "$python_main_pid"; do
    if [[ -n "$pid" ]]; then
      kill_process_tree "$pid" "TERM"
    fi
  done

  # Give processes time to terminate gracefully
  sleep 1

  # Force kill if still running
  for pid in "${all_child_pids[@]}" "$current_pid" "$monitor_pid" "$live_stats_pid" "$python_main_pid"; do
    if [[ -n "$pid" ]]; then
      kill_process_tree "$pid" "KILL"
    fi
  done

  # Kill any remaining python processes from this script
  pkill -f "LATEST-TO_USE_ssh25_09-06-25.py" 2>/dev/null || true

  # Clean up temporary files
  rm -f "$TEMP_CURRENT_HOST_FILE" "$TEMP_TOTAL_HOSTS_FILE" "$TEMP_LOG_OUTPUT_FILE" 2>/dev/null

  # Reset terminal
  tput cnorm # Ensure cursor is visible
  tput cup $(tput lines) 0
  tput ed

  echo "Cleanup completed."
}

# Enhanced signal handler with immediate response
handle_sigint() {
  echo -e "\n\n*** SIGINT received - Terminating immediately ***"
  terminate_requested=1
  cleanup_resources
  exit 130
}

# Set up signal handling with immediate response
trap handle_sigint SIGINT SIGTERM
trap cleanup_resources EXIT

# Parse command-line arguments for the bash script
while getopts "v" opt; do
  case $opt in
  v)
    VERBOSE_MODE="-v"
    echo "Verbose mode enabled for bash script."
    ;;
  \?)
    echo "Invalid option: -$OPTARG" >&2
    exit 1
    ;;
  esac
done
shift $((OPTIND - 1))

# Function to display the dynamic stats
display_live_stats() {
  local start_time=$1

  # Hide cursor to prevent flicker during updates
  tput civis

  while [[ $terminate_requested -eq 0 ]]; do
    # Get terminal width for dynamic formatting
    local term_cols=$(tput cols)
    local banner_width=$((term_cols > 80 ? term_cols - 2 : 78)) # Ensure minimum width
    local padding_total=$((banner_width - 21))                  # 21 = "Scan Initialized" length + padding
    local left_padding=$((padding_total / 2))
    local right_padding=$((padding_total - left_padding))

    # Clear entire screen and move cursor to top-left for redraw
    tput clear
    tput cup 0 0

    local PROTOCOLS="SSH"                  # Assuming fixed for now, or extracted from Python script args
    local THREADS="$PYTHON_CONFIG_THREADS" # Display configured threads

    # Redraw the initial banner each time
    printf "╭%0.s─" $(seq 1 "$banner_width")"╮\n"
    printf "│%0.s " $(seq 1 "$banner_width")" │\n"
    printf "│ %-10s %-${banner_width}s │\n" "📝 File:" "$CURRENT_FILE_BEING_PROCESSED"
    printf "│ %-10s %-${banner_width}s │\n" "🌍 Protocols:" "$PROTOCOLS"
    printf "│ %-10s %-${banner_width}s │\n" "🚀 Threads:" "$THREADS"
    local total_hosts_val=$(cat "$TEMP_TOTAL_HOSTS_FILE" 2>/dev/null | tr -d '[:space:]' || echo 0)
    printf "│ %-10s %-${banner_width}s │\n" "🎯 Total Hosts:" "$total_hosts_val"
    printf "│%0.s " $(seq 1 "$banner_width")" │\n"
    printf "╰%0.s─" $(seq 1 "$banner_width")"╯\n"

    echo "Processing logins: "
    echo ""
    echo ""

    # Read and prepare live stats variables
    local total_hosts=$(cat "$TEMP_TOTAL_HOSTS_FILE" 2>/dev/null | tr -d '[:space:]' || echo 0)

    # Count unique hosts that have been processed - prioritize HOST_CHECKED or count logins
    local checked_hosts_count=0
    if [[ -f "$TEMP_LOG_OUTPUT_FILE" ]]; then
      # Option 1: Count explicit HOST_CHECKED lines (if Python outputs it)
      checked_hosts_count=$(grep -c "HOST_CHECKED:" "$TEMP_LOG_OUTPUT_FILE" 2>/dev/null | tr -d '[:space:]' || echo 0)
      # Option 2: Fallback to sum of correct/failed logins if HOST_CHECKED is not reliably used
      if [[ "$checked_hosts_count" -eq 0 ]]; then
        local correct_logins_temp=$(grep -c -E "(✔️|Correct login)" "$TEMP_LOG_OUTPUT_FILE" 2>/dev/null | tr -d '[:space:]' || echo 0)
        local failed_logins_temp=$(grep -c -E "(❌|Failed login)" "$TEMP_LOG_OUTPUT_FILE" 2>/dev/null | tr -d '[:space:]' || echo 0)
        checked_hosts_count=$((correct_logins_temp + failed_logins_temp))
      fi
    fi

    total_hosts=${total_hosts:-0}
    checked_hosts_count=${checked_hosts_count:-0}

    local current_time=$(date +%s)
    local runtime=$((current_time - start_time))
    local hosts_to_go=$((total_hosts - checked_hosts_count))
    if ((hosts_to_go < 0)); then hosts_to_go=0; fi

    local current_host=$(cat "$TEMP_CURRENT_HOST_FILE" 2>/dev/null || echo "N/A")
    # Truncate current_host if it's too long for display
    if [[ ${#current_host} -gt 14 ]]; then
      current_host="${current_host:0:11}..."
    fi

    # Active threads: Display configured max if main process is running, else 0
    local active_threads_count=0
    if [[ -n "$python_main_pid" ]] && kill -0 "$python_main_pid" 2>/dev/null; then
      active_threads_count=$PYTHON_CONFIG_THREADS
    fi

    # Count login results with more flexible patterns, ensure no extra whitespace
    local correct_logins=$(grep -c -E "(✔️|Correct login)" "$TEMP_LOG_OUTPUT_FILE" 2>/dev/null | tr -d '[:space:]' || echo 0)
    local failed_logins=$(grep -c -E "(❌|Failed login)" "$TEMP_LOG_OUTPUT_FILE" 2>/dev/null | tr -d '[:space:]' || echo 0)

    local percentage_complete=0
    if [ "$total_hosts" -gt 0 ]; then
      percentage_complete=$(((checked_hosts_count * 100) / total_hosts))
    fi

    # Display the live stats table
    echo "╭───────────── Progress Overview ──────────────╮"
    echo "│                                              │"
    echo "│ ┏━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━┓   │"
    echo "│ ┃ Statistic         ┃        Value ┃   │"
    echo "│ ┡━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━┩   │"
    echo "│ │ 🕒 Runtime        │ $(printf "%14s" "${runtime}s") │   │"
    echo "│ │ 📌 Current Host   │ $(printf "%14s" "$current_host") │   │"
    echo "│ │ ✅ Hosts Checked  │ $(printf "%14s" "$checked_hosts_count ($percentage_complete%%)") │   │"
    echo "│ │ ⏭️ Hosts Remaining │ $(printf "%14s" "$hosts_to_go") │   │"
    echo "│ │ 🚀 Active Threads │ $(printf "%14s" "$active_threads_count") │   │"
    echo "│ │ ✔️ Correct Logins │ $(printf "%14s" "$correct_logins") │   │"
    echo "│ │ ✖️ Failed Logins  │ $(printf "%14s" "$failed_logins") │   │"
    echo "│ └───────────────────┴────────────────┘   │"
    echo "│                                              │"
    echo "╰──────────────────────────────────────────────╯"

    # Position cursor for Python output - adjust based on new banner size
    tput cup $((11 + 14)) 0 # Banner (9 lines) + 2 empty lines + progress overview (14 lines) + 1 (for current position)

    # Check for termination every 2 seconds instead of sleeping for 60
    for i in {1..30}; do
      if [[ $terminate_requested -eq 1 ]]; then
        break
      fi
      sleep 2
    done
  done

  tput cnorm               # Ensure cursor is visible when stats loop exits
  tput cup $(tput lines) 0 # Move cursor to the bottom before exiting
  tput ed                  # Clear any remaining lines
}

# Function to process a single file with timeout monitoring and live stats
process_file() {
  local file="$1"
  local max_retries=$MAX_RETRIES
  local retry_count=0
  local success=0

  # Create the !checked directory if it doesn't exist
  mkdir -p "$CHECKED_DIR"

  # Get total hosts for the current file and store in temp file
  local TOTAL_HOSTS=$(wc -l <"$file" | awk '{print $1}')
  echo "$TOTAL_HOSTS" >"$TEMP_TOTAL_HOSTS_FILE"

  if [ "$TOTAL_HOSTS" -eq 0 ]; then
    echo "Skipping empty file: $file"
    mv "$file" "$CHECKED_DIR/"
    return 0
  fi

  # Set the global variable for the file being processed
  CURRENT_FILE_BEING_PROCESSED="$file"

  START_TIME=$(date +%s)

  # Start the live stats display in the background for this file
  display_live_stats "$START_TIME" &
  live_stats_pid=$!
  all_child_pids+=("$live_stats_pid")

  while [[ $retry_count -lt $max_retries && $terminate_requested -eq 0 ]]; do
    echo "Processing attempt $((retry_count + 1)) of $max_retries for file: $file"

    # Create temporary files for status and timestamp for inactivity monitoring for this attempt
    local status_file=$(mktemp)
    local timestamp_file=$(mktemp)
    touch "$timestamp_file"

    # Clear the log output file for new attempt
    >"$TEMP_LOG_OUTPUT_FILE"
    echo "Initializing..." >"$TEMP_CURRENT_HOST_FILE" # Reset current host display

    # Start Python script with proper process tracking
    (
      # Set process group for this subshell
      set -m

      # Direct execution with output capture
      stdbuf -oL python3 "LATEST-TO_USE_ssh25_09-06-25.py" \
        -f "$file" \
        -p ssh \
        -t "$PYTHON_CONFIG_THREADS" \
        $VERBOSE_MODE 2>&1 | while IFS= read -r line; do

        # Check for termination request
        if [[ $terminate_requested -eq 1 ]]; then
          exit 1
        fi

        # Update activity timestamp
        touch "$timestamp_file"

        # Extract current host - ensure Python prints "CURRENT_HOST: <IP>"
        if [[ "$line" =~ CURRENT_HOST:\ *([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}) ]]; then
          echo "${BASH_REMATCH[1]}" >"$TEMP_CURRENT_HOST_FILE"
        fi

        # Log relevant output for statistics
        # Ensure Python outputs "HOST_CHECKED:" for each processed host
        if [[ "$line" =~ (HOST_CHECKED:|✔️|❌|Correct\ login|Failed\ login) ]]; then
          echo "$line" >>"$TEMP_LOG_OUTPUT_FILE"
        fi

        # Display output
        echo "$line"
      done

      # Capture Python exit status
      echo $? >"$status_file"
    ) &

    current_pid=$!
    python_main_pid=$current_pid
    all_child_pids+=("$current_pid")

    # Start inactivity monitor
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
          echo "Process inactive for $((INACTIVITY_TIMEOUT / 60)) minutes. Killing..."
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
      echo "Successfully processed: $file"
      mv "$file" "$CHECKED_DIR/"
      if [[ $? -eq 0 ]]; then
        echo "Moved '$file' to '$CHECKED_DIR/'"
      else
        echo "Warning: Failed to move '$file' to '$CHECKED_DIR/'"
      fi
      success=1
      break
    elif [[ $terminate_requested -eq 1 ]]; then
      echo "Processing interrupted for: $file"
      break
    else
      echo "Processing failed for: $file (Exit code: $python_exit_code)"
      ((retry_count++))
      if [[ $retry_count -lt $max_retries ]]; then
        echo "Retrying in 5 seconds..."
        sleep 5
      fi
    fi
  done

  # Stop the live stats display
  if [[ -n "$live_stats_pid" ]] && kill -0 "$live_stats_pid" 2>/dev/null; then
    kill "$live_stats_pid" 2>/dev/null
    wait "$live_stats_pid" 2>/dev/null
  fi
  live_stats_pid=""

  # Clean terminal
  tput cnorm
  tput cup $(tput lines) 0
  tput ed

  if [[ $success -eq 0 && $terminate_requested -eq 0 ]]; then
    echo "Giving up on: $file after $max_retries attempts"
  fi

  echo "Scanning complete for $file!"
  echo "---------------------------------"
  return 0
}

# --- Main Script Execution ---

# Clean up any residual temporary files from previous runs
cleanup_resources

# ! IMPORTANT FIX: Reset terminate_requested after initial cleanup to allow the script to run
terminate_requested=0

# Create the !checked directory if it doesn't exist
mkdir -p "$CHECKED_DIR"

echo "Starting file processing..."
echo "Press Ctrl+C to interrupt at any time."

# Main processing loop
for txt_file in *.txt; do
  # If no files match the glob, txt_file will be the literal "*.txt"
  # This check handles the case where no files match the glob
  if [[ ! -f "$txt_file" ]]; then
    if [[ "$txt_file" == "*.txt" ]]; then # Only echo if the glob didn't expand
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
    echo "Termination requested, exiting..."
    exit 130
  fi

  echo "Processing file: $txt_file"
  process_file "$txt_file"

  # Brief pause between files
  sleep 1
done

echo "All files processed!"
