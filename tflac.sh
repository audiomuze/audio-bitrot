#!/usr/bin/env bash
set -euo pipefail

FLAC_BIN=/usr/bin/flac

# Build a stable, filesystem-safe tag from the real working directory.
PWD_REAL=$(pwd -P)
PWD_TAG=$(printf '%s' "$PWD_REAL" | sed 's#^/##; s#/#__#g; s#[^A-Za-z0-9._-]#_#g')
if [[ -z "$PWD_TAG" ]]; then
    PWD_TAG=root
fi

SUCCESS_LOG="/tmp/FLAC_${PWD_TAG}_successful"
CORRUPTED_LOG="/tmp/FLAC_${PWD_TAG}_corrupted"
DECODE_ERROR_LOG="/tmp/FLAC_${PWD_TAG}_decode_errors"
QUEUE_FILE="/tmp/FLAC_${PWD_TAG}_queue"
RUN_LIST="/tmp/FLAC_${PWD_TAG}_run_list"
NEXT_QUEUE_FILE="/tmp/FLAC_${PWD_TAG}_next_queue"
FIND_ERR_LOG="/tmp/FLAC_${PWD_TAG}_find_errors"
COUNTER="/tmp/FLAC_${PWD_TAG}_processed_count"
PROCESSED_FILES="/tmp/FLAC_${PWD_TAG}_processed_files"
LOCKFILE="/tmp/FLAC_${PWD_TAG}_lock"  # For atomic counter updates
PROCESSED_DB="/tmp/FLAC_${PWD_TAG}_processed_db"
APPEND_LOCKFILE="/tmp/FLAC_${PWD_TAG}_append_lock"
INSTANCE_LOCKFILE="/tmp/FLAC_${PWD_TAG}_instance_lock"

# Default to one job (safe for spinning disks).
# If working dir is on tmpfs/ramdisk, auto-use all cores unless overridden.
JOBS=1
JOBS_EXPLICIT=0
RESUME=1
REFRESH=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --parallel)
            JOBS=$(nproc)
            JOBS_EXPLICIT=1
            shift
            ;;
        --jobs)
            if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "Usage: $0 [--fresh] [--refresh] [--parallel | --jobs N]"
                exit 1
            fi
            JOBS="$2"
            JOBS_EXPLICIT=1
            shift 2
            ;;
        --fresh)
            RESUME=0
            shift
            ;;
        --refresh)
            REFRESH=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--fresh] [--refresh] [--parallel | --jobs N]"
            echo "  default: --jobs 1"
            echo "  default behavior: resume using existing per-path state/log files"
            echo "  --fresh: clear per-path state/log files and start over"
            echo "  --refresh: rebuild queue from current filesystem before processing"
            echo "  --parallel: use all CPU cores"
            echo "  --jobs N: use exactly N parallel jobs"
            echo ""
            echo "Output logs (created in /tmp with directory-specific suffix):"
            echo "  *_successful: passed verification"
            echo "  *_corrupted: failed verification"
            echo "  *_decode_errors: detailed decode error messages"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--fresh] [--refresh] [--parallel | --jobs N]"
            exit 1
            ;;
    esac
done

if [[ "$JOBS_EXPLICIT" -eq 0 ]]; then
    FS_TYPE=$(stat -f -c %T . 2>/dev/null || true)
    if [[ "$FS_TYPE" == "tmpfs" || "$FS_TYPE" == "ramfs" ]]; then
        JOBS=$(nproc)
    fi
fi

# Prevent concurrent runs in the same working directory tag.
exec 202>"$INSTANCE_LOCKFILE"
if ! flock -n 202; then
    echo "Another instance is already running for: $PWD_REAL" >&2
    echo "Wait for it to finish before starting another run in the same directory." >&2
    exit 1
fi

# Temp cleanup (logs/state for resume are intentionally preserved).
cleanup() {
    if [[ -n "${MONITOR_PID:-}" ]]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
    fi
    rm -f "$RUN_LIST" "$NEXT_QUEUE_FILE" "$FIND_ERR_LOG" "$COUNTER" "$LOCKFILE" "$APPEND_LOCKFILE"
}
trap cleanup EXIT INT TERM

# Initialize files
if [[ "$RESUME" -eq 1 ]]; then
    touch "$SUCCESS_LOG" "$CORRUPTED_LOG" "$DECODE_ERROR_LOG" "$PROCESSED_FILES" "$PROCESSED_DB"

    # Bootstrap NUL-safe DB from legacy line-based tracker if needed.
    if [[ ! -s "$PROCESSED_DB" && -s "$PROCESSED_FILES" ]]; then
        awk '{ printf "%s\0", $0 }' "$PROCESSED_FILES" > "$PROCESSED_DB"
    fi
else
    > "$SUCCESS_LOG"
    > "$CORRUPTED_LOG"
    > "$DECODE_ERROR_LOG"
    > "$PROCESSED_FILES"
    > "$PROCESSED_DB"
    > "$QUEUE_FILE"
fi

# Counter tracks this run only.
echo 0 > "$COUNTER"

# Build or reuse persisted queue.
if [[ "$REFRESH" -eq 1 || ! -s "$QUEUE_FILE" ]]; then
    echo "Scanning for FLAC files..."
    if ! find . -type f -iname "*.flac" -print0 > "$QUEUE_FILE" 2> "$FIND_ERR_LOG"; then
        if [[ -s "$FIND_ERR_LOG" ]]; then
            echo "Warning: some paths could not be scanned (permission denied or inaccessible)." >&2
            echo "First few scan errors:" >&2
            sed -n '1,5p' "$FIND_ERR_LOG" >&2
        fi
    fi
    QUEUE_SOURCE="fresh-scan"
else
    QUEUE_SOURCE="persisted"
fi

# Count discovered queue population
TOTAL_FOUND=0
while IFS= read -r -d ''; do
    (( ++TOTAL_FOUND ))
done < "$QUEUE_FILE"

# Build this run's work list from queue minus processed DB.
if [[ "$RESUME" -eq 1 && -s "$PROCESSED_DB" ]]; then
    awk -v RS='\0' -v ORS='\0' -v pf="$PROCESSED_DB" '
        BEGIN {
            while ((getline line < pf) > 0) {
                seen[line] = 1
            }
            close(pf)
        }
        !seen[$0]
    ' "$QUEUE_FILE" > "$RUN_LIST"
else
    cp "$QUEUE_FILE" "$RUN_LIST"
fi

# Count queued files for this run
TOTAL=0
while IFS= read -r -d ''; do
    (( ++TOTAL ))
done < "$RUN_LIST"

if [[ "$RESUME" -eq 1 ]]; then
    RUN_MODE="resume"
else
    RUN_MODE="fresh"
fi

echo "Run mode: $RUN_MODE"
echo "Queue source: $QUEUE_SOURCE"
echo "Queue size: $TOTAL_FOUND"
echo "Files queued this run: $TOTAL"
echo "Filesystem type: ${FS_TYPE:-unknown}"
echo "Parallel jobs: $JOBS"
echo "Successful log: $SUCCESS_LOG"
echo "Corrupted log: $CORRUPTED_LOG"
echo "Decode errors log: $DECODE_ERROR_LOG"
echo "Processed tracker: $PROCESSED_FILES"
echo "Processed DB (NUL-safe): $PROCESSED_DB"
echo

# Function to atomically increment counter
increment_counter() {
    (
        flock 200
        n=$(<"$COUNTER")
        echo $((n + 1)) > "$COUNTER"
    ) 200>"$LOCKFILE"
}

append_line_locked() {
    local target="$1"
    local value="$2"
    (
        flock 201
        printf '%s\n' "$value" >> "$target"
    ) 201>"$APPEND_LOCKFILE"
}

append_nul_locked() {
    local target="$1"
    local value="$2"
    (
        flock 201
        printf '%s\0' "$value" >> "$target"
    ) 201>"$APPEND_LOCKFILE"
}

process_file() {
    local file="$1"

    # Validate FLAC file, capturing errors but not printing to screen
    if "$FLAC_BIN" -t --silent --warnings-as-errors "$file" 2>> "$DECODE_ERROR_LOG"; then
        append_line_locked "$SUCCESS_LOG" "$file"
    else
        append_line_locked "$CORRUPTED_LOG" "$file"
    fi

    # Mark file as processed in both human-readable and NUL-safe trackers.
    append_line_locked "$PROCESSED_FILES" "$file"
    append_nul_locked "$PROCESSED_DB" "$file"

    # Increment counter atomically
    increment_counter
}

export -f process_file
export FLAC_BIN SUCCESS_LOG CORRUPTED_LOG DECODE_ERROR_LOG COUNTER PROCESSED_FILES PROCESSED_DB LOCKFILE APPEND_LOCKFILE
export -f increment_counter append_line_locked append_nul_locked

# Progress monitor function
progress_monitor() {
    local processed percent
    while true; do
        if [ -f "$COUNTER" ]; then
            processed=$(<"$COUNTER")
            percent=$(( TOTAL > 0 ? processed * 100 / TOTAL : 0 ))
            printf "\rProgress: %d / %d (%d%%)" "$processed" "$TOTAL" "$percent"

            if [ "$processed" -ge "$TOTAL" ]; then
                break
            fi
        fi
        sleep 0.5
    done
    echo
}

# Start the progress monitor in the background
progress_monitor &
MONITOR_PID=$!

# Process files. For serial mode, avoid spawning one bash process per file.
if [[ "$JOBS" -eq 1 ]]; then
    while IFS= read -r -d '' file; do
        process_file "$file"
    done < "$RUN_LIST"
else
    xargs -0 -P "$JOBS" -I {} bash -c 'process_file "$@"' _ {} < "$RUN_LIST"
fi

# Whittle queue down for next run: keep only not-yet-processed files.
if [[ -s "$PROCESSED_DB" ]]; then
    awk -v RS='\0' -v ORS='\0' -v pf="$PROCESSED_DB" '
        BEGIN {
            while ((getline line < pf) > 0) {
                seen[line] = 1
            }
            close(pf)
        }
        !seen[$0]
    ' "$QUEUE_FILE" > "$NEXT_QUEUE_FILE"
    mv -f "$NEXT_QUEUE_FILE" "$QUEUE_FILE"
fi

remaining_count=0
while IFS= read -r -d ''; do
    (( ++remaining_count ))
done < "$QUEUE_FILE"

# Get final counts
success_count=$(wc -l < "$SUCCESS_LOG" 2>/dev/null || echo 0)
corrupted_count=$(wc -l < "$CORRUPTED_LOG" 2>/dev/null || echo 0)
processed_count=$(<"$COUNTER")

echo
echo "=== Processing Complete ==="
echo "Total files processed: $processed_count / $TOTAL"
echo "Remaining queued for future runs: $remaining_count"
echo "Successfully validated: $success_count"
echo "Corrupted files found: $corrupted_count"
echo
echo "Successful files logged to: $SUCCESS_LOG"
echo "Corrupted files logged to: $CORRUPTED_LOG"

error_count=$(wc -l < "$DECODE_ERROR_LOG" 2>/dev/null || echo 0)
if [[ $error_count -gt 0 ]]; then
    echo "Decode error details logged to: $DECODE_ERROR_LOG"
fi
