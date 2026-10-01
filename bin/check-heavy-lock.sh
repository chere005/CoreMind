#!/bin/sh
# Does the heavy-build lock still do what canon/tools/heavy-lock.sh says?
#
#   sh bin/check-heavy-lock.sh
#
# Every case runs the REAL helper, under each shell the lanes might be run
# with (`sh`, which is bash here, and dash when it is installed — the helper
# claims POSIX), against a lock in a scratch directory. Never the machine's
# own: a real build may be holding it, and a proof that queued behind one, or
# made one queue behind it, would be a test with a side effect.
#
# Then each guarantee is BROKEN out of a copy and its case run again, and that
# run must FAIL. A lock that has never been seen letting two holders in looks
# exactly like one that works — the baseline's "break it before you trust it",
# and the reason CalMind's tools/check-deploy-guards.sh breaks copies too.
#
# About a minute and a half, most of it the holds the cases have to wait out.
# Run it after any change to the helper; nothing in a lane runs it.
set -e
cd "$(dirname "$0")/.."
HELPER="$(pwd)/canon/tools/heavy-lock.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/heavylock.XXXXXX")
KIDS=""
# Holders a case left running (it failed half-way, or a broken copy never let
# go) are killed on the way out, so no proof outlives this script.
cleanup() {
  exec 2>/dev/null
  for p in $KIDS; do kill -9 "$p" 2>/dev/null || true; done
  rm -rf "$TMP"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
ms()  { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }
why() { printf '%s\n' "$*" >"$W/why"; return 1; }
# Wait up to $2 seconds (default 10) for file $1 to appear.
waitfor() {
  _i=0
  while [ ! -s "$1" ]; do
    sleep 0.1; _i=$((_i + 1))
    [ "$_i" -lt $((${2:-10} * 10)) ] || return 1
  done
}
# Wait up to $2 seconds for pid $1 to finish, and give back its exit status;
# 124 (and the pid killed) when it does not finish in time — a broken copy
# that waits for ever must still let this script end.
waitpid() {
  _i=0
  while kill -0 "$1" 2>/dev/null; do
    sleep 0.1; _i=$((_i + 1))
    if [ "$_i" -ge $(($2 * 10)) ]; then kill -9 "$1" 2>/dev/null || true; wait "$1" 2>/dev/null || true; return 124; fi
  done
  _wrc=0; wait "$1" 2>/dev/null || _wrc=$?
  return "$_wrc"
}

# --------------------------------------------------------------- the cases
# Each takes <helper> <shell>, works in $W with the lock at $W/lock, and
# returns 0 when the helper behaved — or writes the reason to $W/why.

# Three holders asked for at once take turns, and none overlaps another.
case_serialize() {
  P=""
  for n in 1 2 3; do
    MIND_HEAVY_LOCK="$W/lock" "$2" -c '
      . "$1"
      heavy_lock "probe $2" || exit 9
      s=$(perl -MTime::HiRes=time -e "printf q{%d}, time * 1000")
      sleep 1.5
      e=$(perl -MTime::HiRes=time -e "printf q{%d}, time * 1000")
      echo "$s $e $2" >>"$3"
      heavy_unlock' _ "$1" "$n" "$W/iv" 2>>"$W/err" &
    P="$P $!"; KIDS="$KIDS $!"
  done
  for p in $P; do waitpid "$p" 20 || why "a holder ended $? — $(tail -1 "$W/err")" || return 1; done
  [ "$(wc -l <"$W/iv" | tr -d ' ')" = 3 ] || why "not all three got the lock" || return 1
  sort -n "$W/iv" | awk 'NR > 1 && $1 < e { bad = 1 } { e = $2 } END { exit bad }' \
    || why "two holders overlapped: $(sort -n "$W/iv" | tr '\n' ';')" || return 1
  grep -q 'waiting for the heavy-build lock — held by [^ ]*: probe' "$W/err" \
    || why "no waiter said who held it" || return 1
  [ ! -d "$W/lock" ] || why "the lock outlived its holders"
}

# A holder killed -9 runs no trap; its waiter takes over anyway, promptly.
case_kill9() {
  MIND_HEAVY_LOCK="$W/lock" "$2" -c '
    . "$1"
    heavy_lock holder || exit 9
    sleep 60 & echo $! >"$2.sleep"
    echo held >"$2"
    wait' _ "$1" "$W/held" 2>/dev/null &
  HP=$!; KIDS="$KIDS $HP"
  waitfor "$W/held" || why "the holder never took the lock" || return 1
  KIDS="$KIDS $(cat "$W/held.sleep")"
  MIND_HEAVY_LOCK="$W/lock" MIND_HEAVY_WAIT=12 "$2" -c '
    . "$1"
    heavy_lock waiter || exit 9
    perl -MTime::HiRes=time -e "printf q{%d}, time * 1000" >"$2"
    heavy_unlock' _ "$1" "$W/got" 2>"$W/err" &
  WP=$!; KIDS="$KIDS $WP"
  sleep 2.5
  [ ! -f "$W/got" ] || why "the waiter took the lock while its holder was alive" || return 1
  K=$(ms)
  kill -9 "$HP"
  waitpid "$WP" 20 || why "the waiter never got the lock — $(tail -1 "$W/err")" || return 1
  G=$(cat "$W/got")
  [ $((G - K)) -lt 5000 ] || why "the takeover took $((G - K)) ms" || return 1
  grep -q 'no longer running — taking it over' "$W/err" || why "the takeover said nothing"
}

# A pid that is running but is not the process that took the lock (pids are
# reused) is a gone holder too.
case_reuse() {
  sleep 30 & SP=$!; KIDS="$KIDS $SP"
  mkdir "$W/lock"
  printf '%s\tMon Jan 1 00:00:00 2001\t0\t00:00:00\tSomeRepo\tlong ago\n' "$SP" >"$W/lock/owner"
  MIND_HEAVY_LOCK="$W/lock" MIND_HEAVY_WAIT=6 "$2" -c '. "$1"; heavy_lock reuse && heavy_unlock' _ "$1" 2>"$W/err" &
  WP=$!; KIDS="$KIDS $WP"
  waitpid "$WP" 10 || why "it waited on a recycled pid — $(tail -1 "$W/err")" || return 1
  grep -q 'no longer running' "$W/err" || why "the takeover said nothing"
}

# Ctrl-C, typed at a real terminal: the INT reaches the whole foreground
# group, and the script ends exactly as it would have with no lock at all —
# the caller's own EXIT trap included, with the $? it would have seen. Run
# twice: with no INT trap of the caller's (the shell dies, and the trap — not a
# takeover later — lets the lock go), and with one that carries on past the
# interrupt (still in its block, so still holding the lock until it unlocks).
case_ctrlc() {
  for v in plain own; do
    case $v in
      plain) PRE='trap "echo caller-exit \$?" EXIT' ;;
      own)   PRE='trap "echo caller-int" INT; trap "echo caller-exit \$?" EXIT' ;;
    esac
    # HELD is the one line that differs: with the lock, a run that carried on
    # past its Ctrl-C must still hold it (it prints nothing when it does).
    BODY='echo held; sleep 20; echo after-sleep; HELD; UNLOCK; echo end'
    S_LOCK=". \"\$1\"; $PRE; heavy_lock ctrlc || exit 9; $(echo "$BODY" | sed 's/UNLOCK/heavy_unlock/; s/HELD/[ -d "$MIND_HEAVY_LOCK" ] || echo lost-the-lock/')"
    S_BARE=". \"\$1\"; $PRE; $(echo "$BODY" | sed 's/UNLOCK/:/; s/HELD/:/')"
    MIND_HEAVY_LOCK="$W/lock" python3 "$TMP/ctrlc.py" "$2" "$S_BARE" "$1" >"$W/bare.$v" 2>&1 \
      || why "the pty driver failed: $(tail -1 "$W/bare.$v")" || return 1
    MIND_HEAVY_LOCK="$W/lock" python3 "$TMP/ctrlc.py" "$2" "$S_LOCK" "$1" >"$W/lock.$v" 2>&1 \
      || why "the pty driver failed: $(tail -1 "$W/lock.$v")" || return 1
    [ ! -d "$W/lock" ] || why "($v) Ctrl-C left the lock behind" || return 1
    grep -q 'released' "$W/lock.log" 2>/dev/null || why "($v) the lock was not released by its trap" || return 1
    rm -f "$W/lock.log"
    cmp -s "$W/bare.$v" "$W/lock.$v" \
      || why "($v) the run ended differently with the lock: $(tr '\n' '|' <"$W/lock.$v") vs $(tr '\n' '|' <"$W/bare.$v")" || return 1
  done
}

# kill -TERM: released by the trap, and the script dies as it would have —
# its EXIT trap run or not, as the shell itself would. ($? is left out: bash
# reports the interrupted `wait`'s status to a trap, and the status before it
# when it dies untrapped, and no trap can see the second.)
case_term() {
  for k in bare lock; do
    case $k in bare) L=':' ;; lock) L='heavy_lock term || exit 9' ;; esac
    MIND_HEAVY_LOCK="$W/lock" "$2" -c ". \"\$1\"; trap 'echo caller-exit' EXIT; $L
      sleep 20 & echo \$! >\"\$2.sleep\"; echo held >\"\$2\"; wait \$!; echo after" _ "$1" "$W/held.$k" >"$W/out.$k" 2>&1 &
    HP=$!; KIDS="$KIDS $HP"
    waitfor "$W/held.$k" || why "the $k holder never started" || return 1
    KIDS="$KIDS $(cat "$W/held.$k.sleep")"
    kill -TERM "$HP"
    _rc=0; waitpid "$HP" 10 || _rc=$?
    echo "status $_rc" >>"$W/out.$k"
  done
  [ ! -d "$W/lock" ] || why "TERM left the lock behind" || return 1
  grep -q 'released' "$W/lock.log" 2>/dev/null || why "the lock was not released by its trap" || return 1
  cmp -s "$W/out.bare" "$W/out.lock" \
    || why "the run ended differently with the lock: $(tr '\n' '|' <"$W/out.lock") vs $(tr '\n' '|' <"$W/out.bare")"
}

# The caller's traps survive: put back exactly after an unlock; one the caller
# set INSIDE a block left standing (CalMind's iOS step does that); an ignored
# signal still ignored; and an `exit 3` inside a block runs the caller's EXIT
# trap with $? = 3, exits 3, and lets the lock go.
case_traps() {
  MIND_HEAVY_LOCK="$W/lock" "$2" -c '
    . "$1"; T=$2
    trap "echo \"caller exit \$?\"" EXIT
    trap "echo it'"'"'s
two lines" TERM
    trap "" HUP
    trap >"$T.0"
    heavy_lock one || exit 9
    heavy_unlock
    trap >"$T.1"
    heavy_lock two || exit 9
    trap "echo \"in-block exit \$?\"" EXIT
    heavy_unlock
    trap >"$T.2"
    trap "" INT
    heavy_lock three || exit 9
    trap >"$T.3"
    exit 3' _ "$1" "$W/t" >"$W/out" 2>&1 && _rc=0 || _rc=$?
  cmp -s "$W/t.0" "$W/t.1" || why "an unlock did not put the caller's traps back: $(tr '\n' '|' <"$W/t.1")" || return 1
  grep -q 'in-block exit' "$W/t.2" || why "the unlock removed a trap the caller set inside the block" || return 1
  grep -q "^trap -- '' INT" "$W/t.3" || why "an ignored INT was un-ignored by the lock" || return 1
  [ "$_rc" = 3 ] || why "exit 3 inside the block exited $_rc" || return 1
  [ "$(cat "$W/out")" = "in-block exit 3" ] || why "the caller's EXIT trap printed: $(cat "$W/out")" || return 1
  [ ! -d "$W/lock" ] || why "exit inside the block left the lock behind"
}

# A wait that runs out fails the step, and leaves the holder's lock alone.
case_timeout() {
  MIND_HEAVY_LOCK="$W/lock" "$2" -c '. "$1"; heavy_lock holder || exit 9; echo held >"$2"; sleep 20' _ "$1" "$W/held" 2>/dev/null &
  HP=$!; KIDS="$KIDS $HP"
  waitfor "$W/held" || why "the holder never took the lock" || return 1
  MIND_HEAVY_LOCK="$W/lock" MIND_HEAVY_WAIT=2 "$2" -c '. "$1"; heavy_lock waiter && echo GOT' _ "$1" >"$W/out" 2>&1 &
  WP=$!; KIDS="$KIDS $WP"
  _rc=0; waitpid "$WP" 9 || _rc=$?
  [ "$_rc" != 0 ] && [ "$_rc" != 124 ] || why "the wait did not give up (status $_rc)" || return 1
  grep -q 'gave up after' "$W/out" || why "the give-up said nothing" || return 1
  grep -q "holder" "$W/lock/owner" || why "giving up disturbed the holder's lock"
}

# A heavy block inside another fails at once instead of waiting for itself.
case_nested() {
  MIND_HEAVY_LOCK="$W/lock" MIND_HEAVY_WAIT=5 "$2" -c '
    . "$1"
    heavy_lock outer || exit 9
    "$2" -c ". \"\$1\"; heavy_lock inner" _ "$1"; echo "inner $?"
    heavy_unlock' _ "$1" "$2" >"$W/out" 2>&1 &
  WP=$!; KIDS="$KIDS $WP"
  T0=$(ms); waitpid "$WP" 10 || why "the outer block never finished" || return 1
  grep -q 'inner 1' "$W/out" || why "the nested lock did not fail: $(tail -1 "$W/out")" || return 1
  grep -q "own parent" "$W/out" || why "the nested lock did not say why" || return 1
  [ $(($(ms) - T0)) -lt 3000 ] || why "the nested lock waited before failing"
}

# A background job shares $$ with its script; the script asking again while
# the job holds the lock is refused, not waved through and not left waiting.
case_shared_pid() {
  MIND_HEAVY_LOCK="$W/lock" MIND_HEAVY_WAIT=5 "$2" -c '
    . "$1"
    ( heavy_lock bg || exit 9; echo in >"$2"; sleep 3 ) &
    while [ ! -s "$2" ]; do sleep 0.1; done
    heavy_lock fg; echo "fg $?"
    wait' _ "$1" "$W/in" >"$W/out" 2>&1 &
  WP=$!; KIDS="$KIDS $WP"
  waitpid "$WP" 10 || why "it never finished" || return 1
  grep -q 'fg 1' "$W/out" || why "the second ask was not refused: $(tail -1 "$W/out")" || return 1
  grep -q "in this shell's name" "$W/out" || why "the refusal did not say why"
}

# Asking twice without letting go is refused rather than deadlocking.
case_twice() {
  MIND_HEAVY_LOCK="$W/lock" MIND_HEAVY_WAIT=5 "$2" -c '. "$1"; heavy_lock a || exit 9; heavy_lock b; echo "second $?"' _ "$1" >"$W/out" 2>&1 &
  WP=$!; KIDS="$KIDS $WP"
  waitpid "$WP" 4 || why "it hung" || return 1
  grep -q 'second 1' "$W/out" || why "the second ask was not refused"
}

# No /tmp to write (a sandbox), or a file in the way: a loud failure within
# seconds, not 30 minutes of waiting for a holder that does not exist.
case_blind() {
  : >"$W/afile"
  for L in "$W/no/such/dir/lock" "$W/afile"; do
    MIND_HEAVY_LOCK="$L" "$2" -c '. "$1"; heavy_lock blind && echo GOT' _ "$1" >"$W/out" 2>&1 &
    WP=$!; KIDS="$KIDS $WP"
    _rc=0; waitpid "$WP" 6 || _rc=$?
    [ "$_rc" != 0 ] && [ "$_rc" != 124 ] || why "$L: not a prompt failure (status $_rc)" || return 1
    grep -q 'cannot create' "$W/out" || why "$L: the failure did not say why" || return 1
  done
}

# Under bin/dtp.sh the status card shows the wait, and gets its phase back.
case_phase() {
  printf 'lane X' >"$W/phase"
  MIND_HEAVY_LOCK="$W/lock" "$2" -c '. "$1"; heavy_lock holder || exit 9; echo held >"$2"; sleep 3; heavy_unlock' _ "$1" "$W/held" 2>/dev/null &
  HP=$!; KIDS="$KIDS $HP"
  waitfor "$W/held" || why "the holder never took the lock" || return 1
  MIND_PHASE_FILE="$W/phase" MIND_HEAVY_LOCK="$W/lock" "$2" -c '. "$1"; heavy_lock waiter || exit 9; cat "$MIND_PHASE_FILE" >"$2"; heavy_unlock' _ "$1" "$W/after" 2>/dev/null &
  WP=$!; KIDS="$KIDS $WP"
  sleep 1
  grep -q 'waiting for the heavy-build lock, held by .*holder' "$W/phase" \
    || why "the phase did not show the wait: $(cat "$W/phase")" || return 1
  waitpid "$WP" 10 || why "the waiter never got the lock" || return 1
  [ "$(cat "$W/after")" = "lane X" ] || why "the phase was not put back: $(cat "$W/after")"
}

# A lock whose taker died between its mkdir and its owner file is taken over
# after ten seconds of nobody writing one.
case_ownerless() {
  mkdir "$W/lock"
  MIND_HEAVY_LOCK="$W/lock" MIND_HEAVY_WAIT=30 "$2" -c '. "$1"; heavy_lock lone && heavy_unlock' _ "$1" 2>"$W/err" &
  WP=$!; KIDS="$KIDS $WP"
  waitpid "$WP" 16 || why "it never took the ownerless lock — $(tail -1 "$W/err")" || return 1
  grep -q 'no owner for 10s' "$W/err" || why "the takeover said nothing"
}

# ---------------------------------------------------------- the Ctrl-C driver
# Ctrl-C has to be TYPED to be the real thing: a script's background job has
# INT ignored from birth, so `kill -INT` from here proves nothing about a
# terminal. This puts the script on a pseudo-terminal and types ^C into it.
cat >"$TMP/ctrlc.py" <<'PY'
import os, pty, select, sys, time
sh, script, helper = sys.argv[1:4]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sh, [sh, '-c', script, '_', helper])
out = b''
def pump(until, secs):
    global out
    end = time.time() + secs
    while time.time() < end:
        if select.select([fd], [], [], 0.1)[0]:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                return
            if not chunk:
                return
            out += chunk
            if until and until in out:
                return
pump(b'held', 10)
time.sleep(0.5)
os.write(fd, b'\x03')
pump(None, 10)
_, st = os.waitpid(pid, 0)
text = out.decode(errors='replace').replace('\r', '').replace('^C', '')
sys.stdout.write(text if text.endswith('\n') else text + '\n')
print('status', 'signal %d' % os.WTERMSIG(st) if os.WIFSIGNALED(st) else 'exit %d' % os.WEXITSTATUS(st))
PY

N=0
run() { # run <expect: pass|fail> <label> <case> <helper> <shell>
  N=$((N + 1)); W="$TMP/w$N"; mkdir -p "$W"; rm -f "$W/why"
  # The case's stderr is the shell's own chatter about the holders it killed
  # ("Killed: 9"), which is the point of those cases rather than news.
  _res=0; "$3" "$4" "$5" 2>>"$W/chatter" || _res=$?
  if [ "$1" = pass ]; then
    if [ "$_res" = 0 ]; then ok "$2"; else bad "$2 — $(cat "$W/why" 2>/dev/null)"; fi
  else
    if [ "$_res" != 0 ]; then ok "$2 — caught: $(cat "$W/why" 2>/dev/null)"; else bad "$2 — the broken copy PASSED; this case cannot fail"; fi
  fi
}

SHELLS="sh"; command -v dash >/dev/null 2>&1 && SHELLS="sh dash"
for SH in $SHELLS; do
  echo "the helper, under $SH"
  run pass "three holders take turns, none overlapping"         case_serialize   "$HELPER" "$SH"
  run pass "kill -9 the holder: the waiter takes over, promptly" case_kill9      "$HELPER" "$SH"
  run pass "a recycled pid does not hold a dead build's lock"    case_reuse       "$HELPER" "$SH"
  run pass "Ctrl-C releases, and ends the run as it would have" case_ctrlc       "$HELPER" "$SH"
  run pass "TERM releases, and ends the run as it would have"   case_term        "$HELPER" "$SH"
  run pass "the caller's traps survive, and exit 3 is exit 3"   case_traps       "$HELPER" "$SH"
  run pass "a wait that runs out fails, leaving the holder be"  case_timeout     "$HELPER" "$SH"
  run pass "a heavy block nested in another fails at once"      case_nested      "$HELPER" "$SH"
  run pass "a background job holding it is not waved through"  case_shared_pid  "$HELPER" "$SH"
  run pass "asking twice without letting go is refused"        case_twice       "$HELPER" "$SH"
  run pass "no lock to create is a loud failure, not a wait"   case_blind       "$HELPER" "$SH"
  run pass "the status card shows the wait, then gets it back" case_phase       "$HELPER" "$SH"
done
run pass "an ownerless lock is taken after 10s (sh)"           case_ownerless   "$HELPER" sh

# ------------------------------------------------------- broken copies
# Each sed must actually change the copy; a break that matched nothing would
# "pass" its case by testing the real thing.
broken() { # broken <name> <sed expr>
  sed -e "$2" "$HELPER" >"$TMP/$1.sh"
  if cmp -s "$HELPER" "$TMP/$1.sh"; then
    bad "the '$1' break matched nothing — fix this script"; return 1
  fi
}
echo "broken copies (each must be caught)"
broken mkdir-p 's/_hl_err=$(mkdir "$HEAVY_LOCK"/_hl_err=$(mkdir -p "$HEAVY_LOCK"/' \
  && run fail "a lock taken with mkdir -p lets holders overlap"   case_serialize "$TMP/mkdir-p.sh" sh
broken no-stale '/^_hl_alive() {$/a\
  return 0' \
  && run fail "a lock that never sees its holder gone waits on a corpse" case_kill9 "$TMP/no-stale.sh" sh \
  && run fail "…and on a recycled pid"                              case_reuse "$TMP/no-stale.sh" sh
broken no-trap 's/^    trap "_hl_on $_hl_sig" "$_hl_sig"$/    :/' \
  && run fail "with no trap, Ctrl-C leaves the lock behind"         case_ctrlc "$TMP/no-trap.sh" sh \
  && run fail "…and so does TERM"                                   case_term  "$TMP/no-trap.sh" sh
broken blind-traps '/^_hl_rec() {$/a\
  return 0' \
  && run fail "not reading the caller's traps clobbers them"        case_traps "$TMP/blind-traps.sh" sh
broken no-timeout 's/if \[ "$_hl_waited" -ge "$HEAVY_WAIT" \]; then/if false; then/' \
  && run fail "with no bound, a wait never gives up"                case_timeout "$TMP/no-timeout.sh" sh
broken no-nesting '/^_hl_ancestor() {$/a\
  return 1' \
  && run fail "with no ancestor check, a nested block waits for itself" case_nested "$TMP/no-nesting.sh" sh

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
