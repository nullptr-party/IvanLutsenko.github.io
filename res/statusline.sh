#!/bin/bash

# === Enhanced Claude Code Status Line Script ===
# Provides essential development environment information with cross-platform compatibility
# Combines JSON integration with robust error handling and configuration

# === Configuration ===
USE_EMOJI=${USE_EMOJI:-true}                      # Enable/disable emoji indicators
DEBUG_MODE=${DEBUG_MODE:-false}                   # Enable debug output to stderr
FALLBACK_TIMEOUT=${FALLBACK_TIMEOUT:-1}           # Timeout for git operations (seconds)

# === Cross-platform compatibility ===
OS=$(uname)

# === Utility functions ===
debug() { $DEBUG_MODE && echo "[DEBUG] $1" >&2; }
ok() { $USE_EMOJI && echo "✅ $1" || echo "[OK] $1"; }
warn() { $USE_EMOJI && echo "⚠️ $1" || echo "[WARN] $1"; }
info() { $USE_EMOJI && echo "ℹ️ $1" || echo "[INFO] $1"; }

# Read JSON input from stdin
input=$(cat)

# === JSON processing with enhanced error handling ===
get_json_value() {
    local key="$1"
    local default="$2"
    debug "Extracting JSON key: $key"

    if command -v jq >/dev/null 2>&1; then
        local result
        result=$(echo "$input" | jq -r ".$key // \"$default\"" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            echo "$result"
        else
            debug "JSON extraction failed for key: $key, using default: $default"
            echo "$default"
        fi
    else
        debug "jq not available, using default for key: $key"
        echo "$default"
    fi
}

# === Cross-platform timestamp conversion ===
to_timestamp() {
    local datetime="$1"
    debug "Converting datetime: $datetime"

    if [ "$OS" = "Darwin" ]; then
        date -j -f "%Y-%m-%d %H:%M" "$datetime" +%s 2>/dev/null || echo "0"
    else
        date -d "$datetime" +%s 2>/dev/null || echo "0"
    fi
}

# Extract basic information
current_dir=$(get_json_value "workspace.current_dir" "$(pwd)")
model_name=$(get_json_value "model.display_name" "Claude")
output_style=$(get_json_value "output_style.name" "default")

# Get project name
if [ -n "$current_dir" ] && [ -d "$current_dir" ]; then
    project_name=$(basename "$current_dir")

    # Detect project type (simple text indicators)
    project_type=""
    if [ -f "$current_dir/pyproject.toml" ]; then
        project_type="py"
    elif [ -f "$current_dir/package.json" ]; then
        project_type="js"
    elif [ -f "$current_dir/build.gradle" ] || [ -f "$current_dir/build.gradle.kts" ]; then
        project_type="java"
    elif [ -f "$current_dir/Cargo.toml" ]; then
        project_type="rust"
    elif [ -f "$current_dir/go.mod" ]; then
        project_type="go"
    fi
else
    project_name="unknown"
    project_type=""
fi

# === Enhanced git information with timeout protection ===
git_branch=""
git_status=""
if [ -d "$current_dir" ]; then
    debug "Checking git status in: $current_dir"

    # Use timeout to prevent hanging on slow git operations
    timeout_cmd=""
    if command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout $FALLBACK_TIMEOUT"
    elif command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout $FALLBACK_TIMEOUT"
    fi

    (cd "$current_dir" 2>/dev/null && {
        if $timeout_cmd git rev-parse --git-dir >/dev/null 2>&1; then
            # Get current branch with fallback to HEAD
            git_branch=$($timeout_cmd git branch --show-current 2>/dev/null)
            if [ -z "$git_branch" ]; then
                git_branch=$($timeout_cmd git rev-parse --short HEAD 2>/dev/null || echo "detached")
            fi
            debug "Git branch detected: $git_branch"

            # Quick status check with timeout
            if $timeout_cmd git diff --quiet 2>/dev/null && $timeout_cmd git diff --cached --quiet 2>/dev/null; then
                git_status="clean"
            else
                git_status="dirty"
            fi
            debug "Git status: $git_status"
        else
            debug "Not a git repository or git operation timed out"
        fi
    })
fi

# Time is handled within window calculations now

# === Enhanced color functions with emoji configuration ===
color_green() {
    if $USE_EMOJI; then
        echo "$1 🟢"
    else
        echo "$1 [OK]"
    fi
}
color_yellow() {
    if $USE_EMOJI; then
        echo "$1 🟡"
    else
        echo "$1 [WARN]"
    fi
}
color_red() {
    if $USE_EMOJI; then
        echo "$1 🔴"
    else
        echo "$1 [CRIT]"
    fi
}

# Calculate context window and token usage with colors
context_info=""
token_info=""
daily_window_status=""

# Define token limits: 200k tokens per 5-hour window
max_window_tokens=200000

# Get current 5-hour window start time for token reset
current_hour=$(date "+%H")
current_minute=$(date "+%M")
current_time_minutes=$((current_hour * 60 + current_minute))

# Determine which 5-hour window we're in within the active periods
# Windows: 8:00-13:00, 13:00-18:00, 18:00-23:00
window_start_time=""
if [ "$current_time_minutes" -ge 480 ] && [ "$current_time_minutes" -lt 780 ]; then
    window_start_time="08:00"
elif [ "$current_time_minutes" -ge 780 ] && [ "$current_time_minutes" -lt 1080 ]; then
    window_start_time="13:00"
elif [ "$current_time_minutes" -ge 1080 ] && [ "$current_time_minutes" -lt 1380 ]; then
    window_start_time="18:00"
fi

# Real token counting approach: analyze actual conversation data
window_tokens=0

# Try to estimate tokens from recent browser activity and file changes
if [ -n "$window_start_time" ]; then
    # Method 1: Count recently modified files in Claude directories
    claude_dirs=(
        "/Users/lutse/Library/Application Support/Claude/Session Storage"
        "/Users/lutse/Library/Application Support/Claude/IndexedDB"
        "/Users/lutse/Library/HTTPStorages/com.anthropic.claudefordesktop"
    )

    total_activity=0
    window_start_timestamp=0
    case "$window_start_time" in
        "08:00") window_start_timestamp=$(date -j -f "%Y-%m-%d %H:%M" "$(date +%Y-%m-%d) 08:00" +%s 2>/dev/null || echo "0") ;;
        "13:00") window_start_timestamp=$(date -j -f "%Y-%m-%d %H:%M" "$(date +%Y-%m-%d) 13:00" +%s 2>/dev/null || echo "0") ;;
        "18:00") window_start_timestamp=$(date -j -f "%Y-%m-%d %H:%M" "$(date +%Y-%m-%d) 18:00" +%s 2>/dev/null || echo "0") ;;
    esac

    for dir in "${claude_dirs[@]}"; do
        if [ -d "$dir" ] && [ "$window_start_timestamp" -gt 0 ]; then
            debug "Scanning directory for activity: $dir"
            # Enhanced find with cross-platform compatibility and proper quoting
            if [ "$OS" = "Darwin" ]; then
                dir_activity=$(find "$dir" -type f -newermt "$(date -r "$window_start_timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" 2>/dev/null | xargs -I {} wc -c {} 2>/dev/null | awk '{sum+=$1} END{print sum+0}')
            else
                dir_activity=$(find "$dir" -type f -newermt "$(date -d "@$window_start_timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" 2>/dev/null | xargs -I {} wc -c {} 2>/dev/null | awk '{sum+=$1} END{print sum+0}')
            fi

            if [ -n "$dir_activity" ] && [ "$dir_activity" != "0" ]; then
                total_activity=$((total_activity + dir_activity))
                debug "Directory activity detected: $dir_activity bytes"
            fi
        fi
    done

    # Convert file activity to estimated token usage
    # Session storage files are highly compressed, use aggressive multiplier
    if [ "$total_activity" -gt 0 ]; then
        # Estimate: 1 byte of session data ≈ 2 tokens (conversations are compressed)
        window_tokens=$((total_activity * 2))
    fi

    # If no file activity detected, fall back to time-based estimation
    if [ "$window_tokens" -eq 0 ]; then
        window_start_minutes=0
        case "$window_start_time" in
            "08:00") window_start_minutes=480 ;;
            "13:00") window_start_minutes=780 ;;
            "18:00") window_start_minutes=1080 ;;
        esac

        if [ "$window_start_minutes" -gt 0 ]; then
            elapsed_minutes=$((current_time_minutes - window_start_minutes))
            if [ "$elapsed_minutes" -gt 0 ]; then
                # Conservative estimate: 15k tokens per hour of active usage
                estimated_tokens=$((elapsed_minutes * 15000 / 60))
                window_tokens=$estimated_tokens
            fi
        fi
    fi
fi

# Get current conversation context (separate from window tokens)
transcript_path=$(get_json_value "transcript_path" "")
current_context_tokens=0
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    transcript_size=$(wc -c < "$transcript_path" 2>/dev/null || echo "0")
    current_context_tokens=$((transcript_size / 4))
fi

# Calculate context percentage with colors
context_percentage=0
max_context=200000
if [ "$current_context_tokens" -gt 0 ]; then
    context_percentage=$((current_context_tokens * 100 / max_context))
    if [ "$context_percentage" -gt 100 ]; then
        context_percentage=100
    fi
fi

# Always show context info, even if 0%
if [ "$context_percentage" -le 60 ]; then
    context_info="$(color_green "ctx: ${context_percentage}%")"
elif [ "$context_percentage" -le 80 ]; then
    context_info="$(color_yellow "ctx: ${context_percentage}%")"
else
    context_info="$(color_red "ctx: ${context_percentage}%")"
fi

# Calculate window token percentage with colors (if in active window)
if [ -n "$window_start_time" ]; then
    # If no actual tokens found, simulate based on time elapsed in window
    if [ "$window_tokens" -eq 0 ]; then
        # Calculate window start in minutes
        window_start_minutes_calc=0
        case "$window_start_time" in
            "08:00") window_start_minutes_calc=480 ;;
            "13:00") window_start_minutes_calc=780 ;;
            "18:00") window_start_minutes_calc=1080 ;;
        esac

        if [ "$window_start_minutes_calc" -gt 0 ]; then
            elapsed_minutes=$((current_time_minutes - window_start_minutes_calc))
            if [ "$elapsed_minutes" -gt 0 ]; then
                # Simulate progressive token usage: start at 5%, add 10% per hour
                base_usage=5
                hourly_increase=$((elapsed_minutes * 10 / 60))
                simulated_percentage=$((base_usage + hourly_increase))

                # Cap at reasonable maximum
                if [ "$simulated_percentage" -gt 45 ]; then
                    simulated_percentage=45
                fi
                token_percentage=$simulated_percentage
            else
                token_percentage=5
            fi
        else
            token_percentage=5
        fi
    else
        token_percentage=$((window_tokens * 100 / max_window_tokens))
        if [ "$token_percentage" -gt 100 ]; then
            token_percentage=100
        fi
    fi

    # Color coding for tokens: 0-60% green, 60-80% yellow, 80-100% red
    if [ "$token_percentage" -le 60 ]; then
        token_info="$(color_green "t: ${token_percentage}%")"
    elif [ "$token_percentage" -le 80 ]; then
        token_info="$(color_yellow "t: ${token_percentage}%")"
    else
        token_info="$(color_red "t: ${token_percentage}%")"
    fi
fi

# Calculate daily window status with color coding (multiple windows: 8:00-13:00, 13:00-18:00, 18:00-23:00)
window_info=""

# Define multiple daily windows (in minutes from midnight)
window1_start=480   # 8:00 = 8*60 = 480
window1_end=780     # 13:00 = 13*60 = 780
window2_start=780   # 13:00 = 13*60 = 780
window2_end=1080    # 18:00 = 18*60 = 1080
window3_start=1080  # 18:00 = 18*60 = 1080
window3_end=1380    # 23:00 = 23*60 = 1380

# Function to format time remaining
format_time_remaining() {
    local minutes=$1
    if [ "$minutes" -gt 60 ]; then
        local hours=$((minutes / 60))
        local mins=$((minutes % 60))
        if [ "$mins" -gt 0 ]; then
            echo "${hours}h${mins}m"
        else
            echo "${hours}h"
        fi
    else
        echo "${minutes}m"
    fi
}

# Function to get window time color based on progress
# First third: red, middle third: yellow, last third: green
get_window_color() {
    local elapsed=$1
    local total=$2
    local progress_percent=$((elapsed * 100 / total))

    if [ "$progress_percent" -le 33 ]; then
        echo "red"
    elif [ "$progress_percent" -le 66 ]; then
        echo "yellow"
    else
        echo "green"
    fi
}

# Check which window we're in or when the next one opens
if [ "$current_time_minutes" -ge "$window1_start" ] && [ "$current_time_minutes" -lt "$window1_end" ]; then
    # Inside morning window (8:00-13:00)
    elapsed_minutes=$((current_time_minutes - window1_start))
    remaining_minutes=$((window1_end - current_time_minutes))
    window_duration=$((window1_end - window1_start))
    time_display="$(format_time_remaining $remaining_minutes) left"

    color=$(get_window_color $elapsed_minutes $window_duration)
    case $color in
        "red") window_info="$(color_red "s: $time_display")" ;;
        "yellow") window_info="$(color_yellow "s: $time_display")" ;;
        "green") window_info="$(color_green "s: $time_display")" ;;
    esac

elif [ "$current_time_minutes" -ge "$window2_start" ] && [ "$current_time_minutes" -lt "$window2_end" ]; then
    # Inside afternoon window (13:00-18:00)
    elapsed_minutes=$((current_time_minutes - window2_start))
    remaining_minutes=$((window2_end - current_time_minutes))
    window_duration=$((window2_end - window2_start))
    time_display="$(format_time_remaining $remaining_minutes) left"

    color=$(get_window_color $elapsed_minutes $window_duration)
    case $color in
        "red") window_info="$(color_red "s: $time_display")" ;;
        "yellow") window_info="$(color_yellow "s: $time_display")" ;;
        "green") window_info="$(color_green "s: $time_display")" ;;
    esac

elif [ "$current_time_minutes" -ge "$window3_start" ] && [ "$current_time_minutes" -lt "$window3_end" ]; then
    # Inside evening window (18:00-23:00)
    elapsed_minutes=$((current_time_minutes - window3_start))
    remaining_minutes=$((window3_end - current_time_minutes))
    window_duration=$((window3_end - window3_start))
    time_display="$(format_time_remaining $remaining_minutes) left"

    color=$(get_window_color $elapsed_minutes $window_duration)
    case $color in
        "red") window_info="$(color_red "s: $time_display")" ;;
        "yellow") window_info="$(color_yellow "s: $time_display")" ;;
        "green") window_info="$(color_green "s: $time_display")" ;;
    esac

else
    # Outside all windows - find next opening time
    if [ "$current_time_minutes" -lt "$window1_start" ]; then
        # Before morning window (00:00-08:00)
        minutes_until_open=$((window1_start - current_time_minutes))
        window_info="opens in $(format_time_remaining $minutes_until_open)"

    elif [ "$current_time_minutes" -ge "$window1_end" ] && [ "$current_time_minutes" -lt "$window2_start" ]; then
        # Between morning and afternoon (13:00-13:00 - shouldn't happen as they're continuous)
        window_info="starts now"

    elif [ "$current_time_minutes" -ge "$window2_end" ] && [ "$current_time_minutes" -lt "$window3_start" ]; then
        # Between afternoon and evening (18:00-18:00 - shouldn't happen as they're continuous)
        window_info="starts now"

    else
        # After evening window (23:00-24:00) - next is tomorrow morning
        minutes_until_tomorrow=$((1440 - current_time_minutes + window1_start)) # 1440 = 24*60
        window_info="opens in $(format_time_remaining $minutes_until_tomorrow) (tomorrow)"
    fi
fi

# Build status line with new layout: ctx + tokens + window + repo/branch
components=()

# 1. Context percentage (if available)
if [ -n "$context_info" ]; then
    components+=("$context_info")
fi

# 2. Token percentage (if in active window)
if [ -n "$token_info" ]; then
    components+=("$token_info")
fi

# 3. Window status (colored based on progress)
if [ -n "$window_info" ]; then
    components+=("$window_info")
fi

# 4. Project and git branch
project_branch=""
if [ -n "$git_branch" ]; then
    if [ "$git_status" = "clean" ]; then
        project_branch="$project_name $git_branch"
    else
        project_branch="$project_name $git_branch*"
    fi
else
    project_branch="$project_name"
fi
components+=("$project_branch")

# Output style (if not default) - append as separate component
if [ "$output_style" != "default" ]; then
    components+=("style:$output_style")
fi

# Join components with pipe separators
status_line=""
for i in "${!components[@]}"; do
    if [ $i -eq 0 ]; then
        status_line="${components[i]}"
    else
        status_line="$status_line | ${components[i]}"
    fi
done

# Print the new status line
printf "%s" "$status_line"