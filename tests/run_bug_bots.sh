#!/usr/bin/env bash
# Runs several bug bots side by side (tests/bug_bot.tscn) and sums up what they found:
# their own findings (stuck screens, save/load mismatches) and every script error Godot
# printed, with how many bots hit it.
#   tests/run_bug_bots.sh [bots] [minutes] [extra bot options...]
#   GODOT=/path/to/godot tests/run_bug_bots.sh 6 10 --speed=30
# Half the bots start rich (--rich) so they reach the late game; every third of the others
# starts most mornings overdrawn (--broke) so the angel investor calls. Logs go to bug_bot_logs/.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
BOTS=${1:-4}
MINUTES=${2:-5}
shift $(( $# > 2 ? 2 : $# ))
mkdir -p bug_bot_logs
rm -f bug_bot_logs/bot_*.log
for n in $(seq 1 "$BOTS"); do
	extra=()
	if (( n % 2 == 0 )); then extra+=(--rich); elif (( n % 3 == 0 )); then extra+=(--broke); fi
	"$GODOT" --headless --path . res://tests/bug_bot.tscn -- --seed="$n" --minutes="$MINUTES" "${extra[@]}" "$@" \
		> "bug_bot_logs/bot_$n.log" 2>&1 &
done
wait
echo "== Bot summaries"
grep -h "BUG BOT done" bug_bot_logs/bot_*.log
echo
echo "== Findings"
grep -h "^BUG BOT [A-Z ]*:" bug_bot_logs/bot_*.log | sort | uniq -c | sort -rn
echo
echo "== Script and engine errors (count, first line, where)"
# Godot prints "SCRIPT ERROR: ..." or "ERROR: ..." and then "   at: ..." on the next line
cat bug_bot_logs/bot_*.log | grep -A1 -E "^(SCRIPT ERROR|ERROR|WARNING)" | grep -v "^--$" | paste - - \
	| grep -v "ObjectDB instances leaked" | sort | uniq -c | sort -rn
