#!/usr/bin/env bash
#
# logs.sh - Factor 11: Logs
#
# Detects file-based logging patterns. 12-factor apps should treat
# logs as event streams and write to stdout, not files.
#
# Warning patterns:
# - Ruby: Logger.new('/path/to/file.log')
# - Python: logging.FileHandler, open('file.log', 'w')
# - Node: winston.transports.File, fs.createWriteStream for logs
# - Any: hardcoded log paths
#
# Returns: 0 always (advisory only by default)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Load config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../../config.sh"

TF_LOGS_BLOCKING="${TF_LOGS_BLOCKING:-false}"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

success() {
    echo -e "  ${GREEN}Logs:${NC} OK (stdout logging)"
}

# Track findings
LOG_WARNINGS=()

# Get staged files
get_staged_files() {
    git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true
}

# Check if file should be excluded
should_exclude() {
    local file="$1"

    # Test files
    case "$file" in
        *_test.go|*_spec.rb|*.test.ts|*.test.js|*.spec.ts|*.spec.js)
            return 0
            ;;
        spec/*|test/*|tests/*|__tests__/*)
            return 0
            ;;
    esac

    # Documentation
    case "$file" in
        *.md|*.rst|*.txt)
            return 0
            ;;
    esac

    # Config files where log paths are often legitimately specified
    case "$file" in
        *config/*|*settings/*|*.yml|*.yaml|*.json)
            return 0
            ;;
    esac

    return 1
}

# Scan file for file-based logging patterns
scan_for_file_logging() {
    local file="$1"
    local line_num=0
    local ext="${file##*.}"

    # Skip binary files
    if file "$file" 2>/dev/null | grep -q 'binary'; then
        return
    fi

    while IFS= read -r line; do
        ((line_num++))

        case "$ext" in
            rb)
                # Ruby Logger to file
                if echo "$line" | grep -qE 'Logger\.new\s*\(['\''"][^'\''"]+\.(log|txt)['\''"]'; then
                    LOG_WARNINGS+=("$file:$line_num - Logger writing to file")
                fi
                # Ruby File.open for logs
                if echo "$line" | grep -qE 'File\.(open|write)\s*\(['\''"][^'\''"]+\.log['\''"]'; then
                    LOG_WARNINGS+=("$file:$line_num - Writing logs to file")
                fi
                ;;

            py)
                # Python FileHandler
                if echo "$line" | grep -qE 'FileHandler\s*\(|RotatingFileHandler\s*\(|TimedRotatingFileHandler\s*\('; then
                    LOG_WARNINGS+=("$file:$line_num - logging.FileHandler (file-based logging)")
                fi
                # Python open() for log files
                if echo "$line" | grep -qE 'open\s*\(['\''"][^'\''"]+\.log['\''"]'; then
                    LOG_WARNINGS+=("$file:$line_num - Writing to .log file")
                fi
                ;;

            go)
                # Go file-based logging
                if echo "$line" | grep -qE 'os\.(Create|OpenFile)\s*\([^)]+\.log'; then
                    LOG_WARNINGS+=("$file:$line_num - Creating log file")
                fi
                # lumberjack logger (file-based)
                if echo "$line" | grep -qE 'lumberjack\.Logger\{'; then
                    LOG_WARNINGS+=("$file:$line_num - lumberjack file logger")
                fi
                ;;

            ts|tsx|js|jsx)
                # Winston file transport
                if echo "$line" | grep -qE 'transports\.File|new.*FileTransport'; then
                    LOG_WARNINGS+=("$file:$line_num - Winston file transport")
                fi
                # fs.createWriteStream for logs
                if echo "$line" | grep -qE 'createWriteStream\s*\([^)]+\.log'; then
                    LOG_WARNINGS+=("$file:$line_num - Writing to log file stream")
                fi
                # pino file transport
                if echo "$line" | grep -qE 'pino\.destination\s*\(['\''"]'; then
                    LOG_WARNINGS+=("$file:$line_num - Pino file destination")
                fi
                ;;
        esac

        # Generic: hardcoded log file paths (any language)
        if echo "$line" | grep -qE '['\''"]/(var/log|tmp|logs?)/[^'\''"]+\.log['\''"]'; then
            LOG_WARNINGS+=("$file:$line_num - Hardcoded log path")
        fi

    done < "$file"
}

# Main
main() {
    local staged_files
    local has_warnings=0

    # Get staged files and scan
    staged_files=$(get_staged_files)

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue

        # Skip excluded files
        if should_exclude "$file"; then
            continue
        fi

        scan_for_file_logging "$file"
    done <<< "$staged_files"

    # Report findings
    if [[ ${#LOG_WARNINGS[@]} -gt 0 ]]; then
        echo ""
        warn "File-based logging detected (Factor 11: Logs)"
        for msg in "${LOG_WARNINGS[@]}"; do
            echo "  - $msg"
        done
        echo ""
        echo "12-factor apps should treat logs as event streams."
        echo "Write to stdout/stderr and let the environment handle routing."
        echo ""
        echo "Use [file-logs] override to acknowledge this pattern."
        has_warnings=1
    fi

    if [[ $has_warnings -eq 0 ]]; then
        success
    fi

    # Return failure only if blocking is enabled
    if [[ "$TF_LOGS_BLOCKING" == "true" ]] && [[ $has_warnings -gt 0 ]]; then
        return 1
    fi

    return 0
}

main "$@"
