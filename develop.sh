#!/usr/bin/env bash
set -euo pipefail

# ─── Hermit — Automated Development Loop ───
# Runs Claude Code in a loop, implementing one TODO story per iteration.
# Each iteration: read TODO → implement next unchecked story → test → commit → exit.
# Stops if no progress is made (no new commit = Claude got stuck).

LOG_DIR="./logs"
mkdir -p "$LOG_DIR"

MAX_TURNS="${MAX_TURNS:-50}"            # Max Claude turns per iteration
MAX_ITERATIONS="${MAX_ITERATIONS:-30}"  # Safety cap on total iterations
PAUSE_BETWEEN="${PAUSE_BETWEEN:-5}"     # Seconds between iterations
SIMULATOR="${SIMULATOR:-iPhone 17 Pro}" # iOS Simulator device name

PROMPT="Read CLAUDE.md for project context and conventions.
Read TODO.md and find the next unchecked story (a ### heading with unchecked - [ ] tasks beneath it).
Implement that entire story — all its subtasks. Follow PLANNING.md for architecture details.

After implementing:
1. Build the project: xcodebuild -scheme Hermit -destination 'platform=iOS Simulator,name=${SIMULATOR}' build 2>&1 | tail -20
2. If there are tests for this story, run them: xcodebuild -scheme Hermit -destination 'platform=iOS Simulator,name=${SIMULATOR}' test 2>&1 | tail -30
3. Fix any build errors or test failures before proceeding.
4. Check off all completed items in TODO.md by changing [ ] to [x].
5. Stage the changed files (specific files, not git add -A) and commit with a descriptive message.

Then stop — do not start the next story."

iteration=0
consecutive_failures=0

echo "═══════════════════════════════════════════"
echo "  Hermit — Automated Development Loop"
echo "  Max turns per iteration: $MAX_TURNS"
echo "  Max iterations: $MAX_ITERATIONS"
echo "  Simulator: $SIMULATOR"
echo "  Logs: $LOG_DIR/"
echo "═══════════════════════════════════════════"
echo ""

while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
    iteration=$((iteration + 1))
    timestamp=$(date '+%Y%m%d_%H%M%S')
    log_file="${LOG_DIR}/iteration_${iteration}_${timestamp}.log"
    last_commit=$(git rev-parse HEAD 2>/dev/null || echo "none")

    echo "──────────────────────────────────────"
    echo "  Iteration $iteration / $MAX_ITERATIONS"
    echo "  Started: $(date '+%H:%M:%S')"
    echo "  Log: $log_file"
    echo "──────────────────────────────────────"

    # Run Claude Code
    claude --dangerously-skip-permissions \
        --max-turns "$MAX_TURNS" \
        -p "$PROMPT" \
        2>&1 | tee "$log_file"

    exit_code=${PIPESTATUS[0]}

    # Check if a new commit was made
    new_commit=$(git rev-parse HEAD 2>/dev/null || echo "none")

    if [ "$new_commit" != "$last_commit" ]; then
        consecutive_failures=0
        commit_msg=$(git log -1 --pretty=format:'%s')
        echo ""
        echo "  ✓ Progress! New commit: $commit_msg"
        echo ""

        # Check if all TODO items are done
        remaining=$(grep -c '^\- \[ \]' TODO.md 2>/dev/null || true)
        if [ "$remaining" -eq 0 ]; then
            echo "═══════════════════════════════════════════"
            echo "  🎉 ALL TODO ITEMS COMPLETE!"
            echo "  Total iterations: $iteration"
            echo "═══════════════════════════════════════════"
            exit 0
        fi
        echo "  Remaining TODO items: $remaining"
    else
        consecutive_failures=$((consecutive_failures + 1))
        echo ""
        echo "  ✗ No new commit. Claude may be stuck."
        echo "    (consecutive failures: $consecutive_failures)"
        echo ""

        if [ "$consecutive_failures" -ge 3 ]; then
            echo "═══════════════════════════════════════════"
            echo "  STOPPED: 3 consecutive iterations with no progress."
            echo "  Check the logs and TODO.md to see what's blocking."
            echo "═══════════════════════════════════════════"
            exit 1
        fi
    fi

    if [ "$exit_code" -ne 0 ]; then
        echo "  ⚠ Claude exited with code $exit_code (see log)"
    fi

    echo "  Pausing ${PAUSE_BETWEEN}s before next iteration..."
    sleep "$PAUSE_BETWEEN"
done

echo "═══════════════════════════════════════════"
echo "  STOPPED: Reached max iterations ($MAX_ITERATIONS)"
echo "═══════════════════════════════════════════"
exit 1
