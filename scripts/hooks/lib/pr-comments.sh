#!/usr/bin/env bash
#
# pr-comments.sh - Fetch and filter PR comments
#
# Uses GitHub's GraphQL API to check review thread status.
# A thread is "unresolved" if it has NOT been marked resolved AND
# the code it references has NOT been changed by a subsequent commit.
#
# Usage:
#   ./pr-comments.sh <pr-number> [--unresolved|--has-approval|--json]
#
# Options:
#   --unresolved   Show only unresolved comments on current code
#   --has-approval Exit 0 if PR has affirmative feedback and no blockers
#   --json         Output all data as JSON
#
# Exit codes for --has-approval:
#   0 = Approved (affirmative message, no unresolved comments)
#   1 = Not approved (has unresolved comments or no affirmative message)

set -o nounset 2>/dev/null || true

# Affirmative patterns (case-insensitive)
APPROVAL_PATTERNS=(
    "looks good"
    "lgtm"
    "approved"
    "ship it"
    "good to go"
    "nice work"
    "well done"
    ":+1:"
    "👍"
)

# Get repo owner and name
get_repo_owner() {
    gh repo view --json owner --jq '.owner.login' 2>/dev/null
}

get_repo_name() {
    gh repo view --json name --jq '.name' 2>/dev/null
}

# Fetch review threads via GraphQL.
# Returns threads that are NOT resolved and NOT outdated — i.e., active
# comments on current code that still need attention.
fetch_review_threads() {
    local pr_number="$1"
    local owner name
    owner=$(get_repo_owner)
    name=$(get_repo_name)

    gh api graphql -f query='
    query($owner: String!, $name: String!, $pr: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100) {
            nodes {
              isResolved
              isOutdated
              comments(first: 1) {
                nodes {
                  body
                  path
                  line: originalPosition
                  author { login }
                  createdAt
                  outdated
                }
              }
            }
          }
        }
      }
    }' -f owner="$owner" -f name="$name" -F pr="$pr_number" 2>/dev/null
}

# Extract unresolved, non-outdated threads from GraphQL response
get_unresolved_threads() {
    local pr_number="$1"

    fetch_review_threads "$pr_number" | jq '
        [.data.repository.pullRequest.reviewThreads.nodes[]
         | select(.isResolved == false and .isOutdated == false)
         | .comments.nodes[0]
         | {
             path: .path,
             line: .line,
             body: .body,
             author: .author.login,
             created_at: .createdAt
           }
        ]' 2>/dev/null
}

# Count unresolved threads
count_unresolved_comments() {
    local pr_number="$1"
    local count
    count=$(get_unresolved_threads "$pr_number" | jq 'length' 2>/dev/null)
    echo "${count:-0}"
}

# Fetch PR-level comments (not on specific code lines)
fetch_pr_comments() {
    local pr_number="$1"
    local owner name
    owner=$(get_repo_owner)
    name=$(get_repo_name)

    gh api "repos/${owner}/${name}/issues/${pr_number}/comments" \
        --jq '.[] | {
            id: .id,
            body: .body,
            author: .user.login,
            created_at: .created_at
        }' 2>/dev/null
}

# Fetch review summaries
fetch_reviews() {
    local pr_number="$1"

    gh pr view "$pr_number" --json reviews \
        --jq '.reviews[] | {
            id: .id,
            state: .state,
            body: .body,
            author: .author.login,
            submitted_at: .submittedAt
        }' 2>/dev/null
}

# Check if text contains an affirmative pattern
is_affirmative() {
    local text="$1"
    local lower_text
    lower_text=$(echo "$text" | tr '[:upper:]' '[:lower:]')

    for pattern in "${APPROVAL_PATTERNS[@]}"; do
        if [[ "$lower_text" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# Check for affirmative feedback in PR comments or reviews
has_affirmative_feedback() {
    local pr_number="$1"

    # Check PR-level comments
    while IFS= read -r comment; do
        if [[ -n "$comment" ]] && is_affirmative "$comment"; then
            return 0
        fi
    done < <(fetch_pr_comments "$pr_number" | grep '"body":' | sed 's/.*"body": "\([^"]*\)".*/\1/')

    # Check review bodies
    while IFS= read -r review; do
        if [[ -n "$review" ]] && is_affirmative "$review"; then
            return 0
        fi
    done < <(fetch_reviews "$pr_number" | grep '"body":' | sed 's/.*"body": "\([^"]*\)".*/\1/')

    # Check for formal APPROVED state
    if fetch_reviews "$pr_number" | grep -q '"state": "APPROVED"'; then
        return 0
    fi

    return 1
}

# Check if PR is effectively approved
# Approved = (formal approval OR affirmative comment) AND no unresolved comments
is_effectively_approved() {
    local pr_number="$1"
    local unresolved_count

    unresolved_count=$(count_unresolved_comments "$pr_number" | tr -d '[:space:]')
    unresolved_count="${unresolved_count:-0}"

    if [[ "$unresolved_count" -gt 0 ]]; then
        return 1  # Has unresolved comments
    fi

    if has_affirmative_feedback "$pr_number"; then
        return 0  # Approved
    fi

    return 1  # No approval signal
}

# Output unresolved comments
show_unresolved() {
    local pr_number="$1"

    echo "## Unresolved Comments on PR #${pr_number}"
    echo ""

    local threads
    threads=$(get_unresolved_threads "$pr_number")
    local count
    count=$(echo "$threads" | jq 'length' 2>/dev/null)
    count="${count:-0}"

    if [[ "$count" -eq 0 ]]; then
        echo "No unresolved comments on current code."
    else
        echo "$threads" | jq '.[]' 2>/dev/null
    fi
}

# Output as JSON
show_json() {
    local pr_number="$1"
    local unresolved_count is_approved has_affirmative

    unresolved_count=$(count_unresolved_comments "$pr_number" | tr -d '[:space:]')
    unresolved_count="${unresolved_count:-0}"
    [[ "$unresolved_count" =~ ^[0-9]+$ ]] || unresolved_count=0

    if is_effectively_approved "$pr_number"; then
        is_approved="true"
    else
        is_approved="false"
    fi

    if has_affirmative_feedback "$pr_number"; then
        has_affirmative="true"
    else
        has_affirmative="false"
    fi

    cat <<EOF
{
  "pr_number": $pr_number,
  "unresolved_comment_count": $unresolved_count,
  "has_affirmative_feedback": $has_affirmative,
  "is_effectively_approved": $is_approved
}
EOF
}

# Main
main() {
    local pr_number="${1:-}"
    local mode="${2:---unresolved}"

    if [[ -z "$pr_number" ]] || [[ "$pr_number" == "--help" ]] || [[ "$pr_number" == "-h" ]]; then
        echo "Usage: pr-comments.sh <pr-number> [--unresolved|--has-approval|--json]"
        echo ""
        echo "Options:"
        echo "  --unresolved   Show unresolved comments on current code"
        echo "  --has-approval Exit 0 if approved, 1 if not"
        echo "  --json         Output all data as JSON"
        exit 0
    fi

    case "$mode" in
        --unresolved)
            show_unresolved "$pr_number"
            ;;
        --has-approval)
            if is_effectively_approved "$pr_number"; then
                exit 0
            else
                exit 1
            fi
            ;;
        --json)
            show_json "$pr_number"
            ;;
        *)
            echo "Unknown option: $mode" >&2
            exit 1
            ;;
    esac
}

main "$@"
