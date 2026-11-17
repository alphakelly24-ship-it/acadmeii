#!/usr/bin/env bash
set -Eeuo pipefail

confirmation_value="${ACADEMI_DISPOSABLE_DB_CONFIRM:-}"
if [[ "$confirmation_value" != "I_CONFIRM_THIS_DATABASE_IS_DISPOSABLE" ]]; then
  echo "Refusing to run: confirm a disposable local database by setting ACADEMI_DISPOSABLE_DB_CONFIRM=I_CONFIRM_THIS_DATABASE_IS_DISPOSABLE." >&2
  exit 2
fi
unset confirmation_value

# Run only against a disposable local Academi test database with migrations applied.
# This driver refuses non-loopback database connections and never resets a database.
PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-54322}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-postgres}"
export PGHOST PGPORT PGUSER PGDATABASE

case "$PGHOST" in
  127.0.0.1|localhost|::1) ;;
  *) echo "Refusing non-loopback PostgreSQL host; use a disposable local database." >&2; exit 2 ;;
esac

POLL_TIMEOUT_SECONDS="${POLL_TIMEOUT_SECONDS:-15}"
SESSION_TIMEOUT_SECONDS="${SESSION_TIMEOUT_SECONDS:-25}"
QUERY_TIMEOUT_SECONDS="${QUERY_TIMEOUT_SECONDS:-5}"
PAUSE_SECONDS="${PAUSE_SECONDS:-3}"
for setting in POLL_TIMEOUT_SECONDS SESSION_TIMEOUT_SECONDS QUERY_TIMEOUT_SECONDS PAUSE_SECONDS; do
  value="${!setting}"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "$setting must be a positive integer number of seconds." >&2
    exit 2
  fi
done
if (( SESSION_TIMEOUT_SECONDS <= POLL_TIMEOUT_SECONDS )); then
  echo "SESSION_TIMEOUT_SECONDS must exceed POLL_TIMEOUT_SECONDS." >&2
  exit 2
fi
if (( SESSION_TIMEOUT_SECONDS <= PAUSE_SECONDS + 2 )); then
  echo "SESSION_TIMEOUT_SECONDS must exceed PAUSE_SECONDS by at least two seconds." >&2
  exit 2
fi

run_token="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
app_prefix="academi_${run_token}"
app_initial_submit="${app_prefix}_initial_submit"
app_initial_writer="${app_prefix}_initial_writer"
app_revision_creator_a="${app_prefix}_revision_creator_a"
app_revision_creator_b="${app_prefix}_revision_creator_b"
app_lesson_writer="${app_prefix}_lesson_writer"
app_revision_approver="${app_prefix}_revision_approver"
app_question_writer="${app_prefix}_question_writer"
app_answer_key_writer="${app_prefix}_answer_key_writer"
pause_function="academi_pause_${run_token}"
pause_course_trigger="aa_academi_${run_token}_course"
pause_lesson_trigger="aa_academi_${run_token}_lesson"
pause_question_trigger="aa_academi_${run_token}_question"
pause_revision_trigger="aa_academi_${run_token}_revision"

workdir="$(mktemp -d "${TMPDIR:-/tmp}/academi-lock-test.XXXXXX")"
fixtures_may_exist=0
pause_objects_may_exist=0
admin_id=""
owner_id=""
category_id=""
course_id=""
outcome_id=""
section_id=""
lesson_id=""
assessment_id=""
question_id=""
option_a_id=""
option_b_id=""
revision_id=""
initial_submit_pid=""
initial_writer_pid=""
revision_creator_a_pid=""
revision_creator_b_pid=""
lesson_writer_pid=""
revision_approver_pid=""
question_writer_pid=""
answer_key_writer_pid=""
cleanup_running=0

psql_local() {
  timeout --signal=TERM --kill-after=1s "${QUERY_TIMEOUT_SECONDS}s" \
    psql -X -v ON_ERROR_STOP=1 "$@"
}

print_diagnostics() {
  local heading="${1:-Concurrency-test diagnostics}"
  echo "=== $heading ===" >&2
  printf 'Driver PID: %s; application prefix: %s; database: %s@%s:%s/%s\n' \
    "$$" "$app_prefix" "$PGUSER" "$PGHOST" "$PGPORT" "$PGDATABASE" >&2
  printf 'Session process IDs: submit=%s initial_writer=%s revision_creator_a=%s revision_creator_b=%s lesson_writer=%s approver=%s question_writer=%s answer_key=%s\n' \
    "${initial_submit_pid:-none}" "${initial_writer_pid:-none}" \
    "${revision_creator_a_pid:-none}" "${revision_creator_b_pid:-none}" \
    "${lesson_writer_pid:-none}" "${revision_approver_pid:-none}" \
    "${question_writer_pid:-none}" "${answer_key_writer_pid:-none}" >&2
  if ! psql_local -P pager=off -c "
    SELECT pid, application_name, state,
           coalesce(wait_event_type, '') AS wait_event_type,
           coalesce(wait_event, '') AS wait_event,
           pg_blocking_pids(pid) AS blocker_pids,
           left(query, 240) AS query
    FROM pg_stat_activity
    WHERE position('$run_token' IN application_name) > 0
    ORDER BY pid;" >&2; then
    echo "Could not query pg_stat_activity while collecting diagnostics." >&2
  fi
  if ! psql_local -P pager=off -c "
    SELECT l.pid, a.application_name, l.locktype, l.mode, l.granted,
           coalesce(n.nspname || '.' || c.relname, '') AS relation
    FROM pg_locks AS l
    LEFT JOIN pg_stat_activity AS a ON a.pid = l.pid
    LEFT JOIN pg_class AS c ON c.oid = l.relation
    LEFT JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE position('$run_token' IN a.application_name) > 0
    ORDER BY l.pid, l.granted, l.locktype;" >&2; then
    echo "Could not query pg_locks while collecting diagnostics." >&2
  fi
}

print_session_logs() {
  local file
  for file in "$workdir"/*.out; do
    [[ -f "$file" ]] || continue
    echo "--- $(basename "$file") ---" >&2
    cat "$file" >&2
  done
}

fail_with_logs() {
  echo "Concurrency test failed: $1" >&2
  print_diagnostics "Failure diagnostics"
  print_session_logs
  exit 1
}

cleanup() {
  local result=$?
  local cleanup_failed=0
  local pid
  (( cleanup_running == 0 )) || return "$result"
  cleanup_running=1
  trap - EXIT INT TERM

  for pid in \
    "${initial_submit_pid:-}" "${initial_writer_pid:-}" \
    "${revision_creator_a_pid:-}" "${revision_creator_b_pid:-}" \
    "${lesson_writer_pid:-}" "${revision_approver_pid:-}" \
    "${question_writer_pid:-}" "${answer_key_writer_pid:-}"; do
    [[ -n "$pid" ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      # timeout runs each psql command in its own process group. Signal that group
      # first so an interrupt cannot leave a psql child behind.
      kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done

  if (( pause_objects_may_exist == 1 )); then
    if psql_local -q <<SQL
BEGIN;
DROP TRIGGER IF EXISTS ${pause_course_trigger} ON public.courses;
DROP TRIGGER IF EXISTS ${pause_lesson_trigger} ON public.lessons;
DROP TRIGGER IF EXISTS ${pause_question_trigger} ON public.assessment_questions;
DROP TRIGGER IF EXISTS ${pause_revision_trigger} ON public.course_revisions;
DROP FUNCTION IF EXISTS private.${pause_function}();
COMMIT;
SQL
    then
      pause_objects_may_exist=0
    else
      echo "ERROR: failed to remove this run's temporary pause triggers/function." >&2
      cleanup_failed=1
    fi
  fi

  if (( fixtures_may_exist == 1 )); then
    if psql_local -q <<SQL
BEGIN;
SET LOCAL session_replication_role = replica;
DELETE FROM public.course_revision_lessons
WHERE revision_id IN (SELECT id FROM public.course_revisions WHERE course_id = '$course_id'::uuid);
DELETE FROM public.course_revision_sections
WHERE revision_id IN (SELECT id FROM public.course_revisions WHERE course_id = '$course_id'::uuid);
DELETE FROM public.course_revision_outcomes
WHERE revision_id IN (SELECT id FROM public.course_revisions WHERE course_id = '$course_id'::uuid);
DELETE FROM public.course_revisions WHERE course_id = '$course_id'::uuid;
DELETE FROM private.assessment_answer_keys WHERE question_id = '$question_id'::uuid;
DELETE FROM public.assessment_options WHERE question_id = '$question_id'::uuid;
DELETE FROM public.assessment_questions WHERE id = '$question_id'::uuid;
DELETE FROM public.assessments WHERE id = '$assessment_id'::uuid;
DELETE FROM public.lessons WHERE id = '$lesson_id'::uuid;
DELETE FROM public.course_sections WHERE id = '$section_id'::uuid;
DELETE FROM public.course_outcomes WHERE id = '$outcome_id'::uuid;
DELETE FROM public.courses WHERE id = '$course_id'::uuid;
DELETE FROM public.categories WHERE id = '$category_id'::uuid;
DELETE FROM public.instructor_profiles WHERE user_id IN ('$owner_id'::uuid, '$admin_id'::uuid);
DELETE FROM public.user_roles WHERE user_id IN ('$owner_id'::uuid, '$admin_id'::uuid);
DELETE FROM public.profiles WHERE id IN ('$owner_id'::uuid, '$admin_id'::uuid);
DELETE FROM auth.users WHERE id IN ('$owner_id'::uuid, '$admin_id'::uuid);
COMMIT;
SQL
    then
      fixtures_may_exist=0
    else
      echo "ERROR: failed to remove this run's disposable fixture rows." >&2
      cleanup_failed=1
    fi
  fi

  if (( cleanup_failed == 1 )); then
    result=1
    echo "Cleanup was incomplete; inspect the disposable local database and logs below." >&2
    print_diagnostics "Cleanup diagnostics" || true
    print_session_logs
    echo "Logs preserved at: $workdir" >&2
  elif (( result == 0 )); then
    if rm -rf -- "$workdir"; then
      echo "Cleanup completed: per-run triggers, function, and fixture rows removed."
    else
      echo "ERROR: could not remove temporary logs at $workdir." >&2
      result=1
    fi
  else
    echo "Temporary logs preserved at: $workdir" >&2
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

wait_for_condition() {
  local description="$1"
  local sql="$2"
  local deadline=$((SECONDS + POLL_TIMEOUT_SECONDS))
  local value
  while (( SECONDS < deadline )); do
    if value="$(psql_local -qAt -c "$sql" 2>/dev/null)" && [[ "$value" == "t" ]]; then
      return 0
    fi
    sleep 0.05
  done
  print_diagnostics "Timeout waiting for: $description"
  print_session_logs
  return 1
}

wait_for_pause() {
  local app_name="$1"
  wait_for_condition \
    "session $app_name to enter the intentional trigger pause" \
    "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = '$app_name' AND state = 'active' AND wait_event = 'PgSleep');"
}

wait_for_blocking_relationship() {
  local waiting_app="$1"
  local blocking_app="$2"
  wait_for_condition \
    "session $waiting_app to be lock-blocked by $blocking_app" \
    "SELECT EXISTS (
       SELECT 1
       FROM pg_stat_activity AS waiting
       JOIN pg_stat_activity AS blocking
         ON blocking.pid = ANY(pg_blocking_pids(waiting.pid))
       WHERE waiting.application_name = '$waiting_app'
         AND blocking.application_name = '$blocking_app'
         AND waiting.wait_event_type = 'Lock'
     );"
}

wait_for_session() {
  local pid="$1"
  local label="$2"
  local expected="$3"
  local status
  if wait "$pid"; then
    status=0
  else
    status=$?
  fi
  if [[ "$expected" == "success" && "$status" -ne 0 ]]; then
    fail_with_logs "$label exited with status $status (expected success; session timeout is ${SESSION_TIMEOUT_SECONDS}s)"
  fi
  if [[ "$expected" == "failure" && "$status" -eq 0 ]]; then
    fail_with_logs "$label unexpectedly succeeded instead of rejecting the operation"
  fi
  LAST_SESSION_STATUS="$status"
}

new_uuid() { python3 -c 'import uuid; print(uuid.uuid4())'; }

# Require a loopback listener, a local database superuser, and the expected schema.
server_addr="$(psql_local -qAt -c "SELECT coalesce(inet_server_addr()::text, '')")"
case "$server_addr" in
  127.*|::1) ;;
  *) echo "Refusing database that is not reached through a loopback listener." >&2; exit 2 ;;
esac
printf 'Confirmed disposable test database identity:\n' >&2
psql_local -P pager=off -c "SELECT current_database() AS database, current_user AS role, inet_server_addr() AS server_address, inet_server_port() AS server_port;"
is_superuser="$(psql_local -qAt -c "SELECT rolsuper FROM pg_roles WHERE rolname = current_user")"
[[ "$is_superuser" == "t" ]] || { echo "A local disposable database superuser is required for isolated fixture setup/cleanup." >&2; exit 2; }
ready="$(psql_local -qAt -c "SELECT to_regprocedure('public.approve_course_revision(uuid)') IS NOT NULL AND to_regprocedure('public.set_assessment_answer_key(uuid,uuid)') IS NOT NULL AND to_regprocedure('public.create_course_revision(uuid)') IS NOT NULL AND to_regprocedure('public.submit_course_for_review(uuid)') IS NOT NULL")"
[[ "$ready" == "t" ]] || { echo "Apply the Academi migrations to the local test database before running this test." >&2; exit 2; }

admin_id="$(new_uuid)"
owner_id="$(new_uuid)"
category_id="$(new_uuid)"
course_id="$(new_uuid)"
outcome_id="$(new_uuid)"
section_id="$(new_uuid)"
lesson_id="$(new_uuid)"
assessment_id="$(new_uuid)"
question_id="$(new_uuid)"
option_a_id="$(new_uuid)"
option_b_id="$(new_uuid)"

# Collision preflight ensures fixture cleanup can only target identifiers that
# were absent before this run created them.
ids_absent="$(psql_local -qAt -c "
SELECT NOT EXISTS (SELECT 1 FROM auth.users WHERE id IN ('$admin_id'::uuid, '$owner_id'::uuid))
   AND NOT EXISTS (SELECT 1 FROM public.categories WHERE id = '$category_id'::uuid)
   AND NOT EXISTS (SELECT 1 FROM public.courses WHERE id = '$course_id'::uuid)
   AND NOT EXISTS (SELECT 1 FROM public.course_outcomes WHERE id = '$outcome_id'::uuid)
   AND NOT EXISTS (SELECT 1 FROM public.course_sections WHERE id = '$section_id'::uuid)
   AND NOT EXISTS (SELECT 1 FROM public.lessons WHERE id = '$lesson_id'::uuid)
   AND NOT EXISTS (SELECT 1 FROM public.assessments WHERE id = '$assessment_id'::uuid)
   AND NOT EXISTS (SELECT 1 FROM public.assessment_questions WHERE id = '$question_id'::uuid)
   AND NOT EXISTS (SELECT 1 FROM public.assessment_options WHERE id IN ('$option_a_id'::uuid, '$option_b_id'::uuid));")"
[[ "$ids_absent" == "t" ]] || { echo "Generated fixture-ID collision; refusing to change existing database rows." >&2; exit 2; }

# Check all generated object names before creating any. Names include a fresh
# UUID token, and cleanup only drops these exact per-run names.
object_collision="$(psql_local -qAt -c "
SELECT to_regprocedure('private.${pause_function}()') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = '${pause_course_trigger}' AND tgrelid = 'public.courses'::regclass AND NOT tgisinternal)
    OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = '${pause_lesson_trigger}' AND tgrelid = 'public.lessons'::regclass AND NOT tgisinternal)
    OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = '${pause_question_trigger}' AND tgrelid = 'public.assessment_questions'::regclass AND NOT tgisinternal)
    OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = '${pause_revision_trigger}' AND tgrelid = 'public.course_revisions'::regclass AND NOT tgisinternal);")"
[[ "$object_collision" == "f" ]] || { echo "Per-run temporary database object name collision; refusing to replace or drop an existing object." >&2; exit 2; }

fixtures_may_exist=1
# Create fixtures as the local database owner. Explicit JWT claims exercise the
# same database actor checks used for authenticated API requests.
psql_local -q <<SQL
BEGIN;
INSERT INTO auth.users (id, aud, "role", email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('$admin_id'::uuid, 'authenticated', 'authenticated', '$admin_id@lock-test.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('$owner_id'::uuid, 'authenticated', 'authenticated', '$owner_id@lock-test.invalid', '', now(), '{}'::jsonb, '{"display_name":"Lock Test Owner"}'::jsonb, now(), now());
INSERT INTO public.user_roles (user_id, role) VALUES
  ('$admin_id'::uuid, 'admin'),
  ('$owner_id'::uuid, 'student'),
  ('$owner_id'::uuid, 'instructor');
INSERT INTO public.instructor_profiles (user_id, public_name) VALUES ('$owner_id'::uuid, 'Lock Test Owner');
INSERT INTO public.categories (id, name, slug) VALUES ('$category_id'::uuid, 'Concurrency Test', 'concurrency-$run_token');
SELECT set_config('request.jwt.claim.sub', '$admin_id', true);
SELECT set_config('request.jwt.claims', '{"sub":"$admin_id","role":"authenticated"}', true);
INSERT INTO public.courses (id, instructor_id, category_id, slug, title, description, status)
VALUES ('$course_id'::uuid, '$owner_id'::uuid, '$category_id'::uuid, 'concurrency-$run_token', 'Concurrency course', 'Disposable test fixture', 'draft');
INSERT INTO public.course_outcomes (id, course_id, position, outcome) VALUES ('$outcome_id'::uuid, '$course_id'::uuid, 1, 'Outcome');
INSERT INTO public.course_sections (id, course_id, title, position) VALUES ('$section_id'::uuid, '$course_id'::uuid, 'Section', 1);
INSERT INTO public.lessons (id, course_id, section_id, title, content_type, position, duration_seconds)
VALUES ('$lesson_id'::uuid, '$course_id'::uuid, '$section_id'::uuid, 'Concurrency lesson', 'reading', 1, NULL);
INSERT INTO public.assessments (id, course_id, lesson_id, title, status)
VALUES ('$assessment_id'::uuid, '$course_id'::uuid, '$lesson_id'::uuid, 'Concurrency assessment', 'draft');
INSERT INTO public.assessment_questions (id, assessment_id, position, prompt)
VALUES ('$question_id'::uuid, '$assessment_id'::uuid, 1, 'Concurrency question');
INSERT INTO public.assessment_options (id, question_id, position, option_text) VALUES
  ('$option_a_id'::uuid, '$question_id'::uuid, 1, 'Option A'),
  ('$option_b_id'::uuid, '$question_id'::uuid, 2, 'Option B');
INSERT INTO private.assessment_answer_keys (question_id, correct_option_id)
VALUES ('$question_id'::uuid, '$option_a_id'::uuid);
COMMIT;
SQL

pause_objects_may_exist=1
# The aa_ trigger prefix runs before application row-lock triggers. Each test
# connection pauses only at the specified stage; object names are run-unique.
psql_local -q <<SQL
BEGIN;
CREATE FUNCTION private.${pause_function}()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS \$academi_pause\$
BEGIN
  IF pg_catalog.current_setting('application_name', true) IN (
    '$app_initial_submit', '$app_revision_creator_a',
    '$app_lesson_writer', '$app_question_writer'
  ) THEN
    PERFORM pg_catalog.pg_sleep($PAUSE_SECONDS);
  END IF;
  RETURN NEW;
END;
\$academi_pause\$;
CREATE TRIGGER ${pause_course_trigger}
BEFORE UPDATE ON public.courses
FOR EACH ROW EXECUTE FUNCTION private.${pause_function}();
CREATE TRIGGER ${pause_lesson_trigger}
BEFORE UPDATE ON public.lessons
FOR EACH ROW EXECUTE FUNCTION private.${pause_function}();
CREATE TRIGGER ${pause_question_trigger}
BEFORE UPDATE ON public.assessment_questions
FOR EACH ROW EXECUTE FUNCTION private.${pause_function}();
CREATE TRIGGER ${pause_revision_trigger}
BEFORE INSERT ON public.course_revisions
FOR EACH ROW EXECUTE FUNCTION private.${pause_function}();
COMMIT;
SQL

# RACE 1: The owner submits the draft while their lesson update is in flight.
# Submission owns the course row in the pause trigger; the owner update must be
# observed waiting on that exact submission session, then rejected after commit.
PGAPPNAME="$app_initial_submit" timeout --signal=TERM --kill-after=2s "${SESSION_TIMEOUT_SECONDS}s" \
  psql -X -v ON_ERROR_STOP=1 -q >"$workdir/initial-submit.out" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$owner_id', true);
SELECT set_config('request.jwt.claims', '{"sub":"$owner_id","role":"authenticated"}', true);
SELECT public.submit_course_for_review('$course_id'::uuid);
COMMIT;
SQL
initial_submit_pid=$!
wait_for_pause "$app_initial_submit" || fail_with_logs "owner initial submission did not enter its course-row pause"

PGAPPNAME="$app_initial_writer" timeout --signal=TERM --kill-after=2s "${SESSION_TIMEOUT_SECONDS}s" \
  psql -X -v ON_ERROR_STOP=1 -q >"$workdir/initial-writer.out" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$owner_id', true);
SELECT set_config('request.jwt.claims', '{"sub":"$owner_id","role":"authenticated"}', true);
UPDATE public.lessons SET title = 'Must be rejected after submission' WHERE id = '$lesson_id'::uuid;
COMMIT;
SQL
initial_writer_pid=$!
wait_for_blocking_relationship "$app_initial_writer" "$app_initial_submit" \
  || fail_with_logs "owner content edit was not observed lock-blocked by the initial submission"

echo "PASS: observed owner lesson writer blocked by the owner's initial submission via pg_blocking_pids()."
wait_for_session "$initial_submit_pid" "owner initial submission" success
initial_submit_pid=""
wait_for_session "$initial_writer_pid" "owner lesson edit after submission" failure
initial_writer_pid=""
grep -Fq "Only the owning instructor may edit course content while the course is a draft." "$workdir/initial-writer.out" \
  || fail_with_logs "blocked owner lesson edit did not fail at the post-lock draft-status check"
initial_status="$(psql_local -qAt -c "SELECT status::text FROM public.courses WHERE id = '$course_id'::uuid")"
initial_lesson="$(psql_local -qAt -c "SELECT title FROM public.lessons WHERE id = '$lesson_id'::uuid")"
[[ "$initial_status" == "pending_review" ]] || fail_with_logs "course status after the race is '$initial_status', expected pending_review"
[[ "$initial_lesson" == "Concurrency lesson" ]] || fail_with_logs "in-flight owner edit slipped through after the course became pending_review"
echo "PASS: submission committed as pending_review; the instructor's blocked lesson edit was rejected and content stayed unchanged."

# Publish as the trusted administrator, then prepare the staged revision used by
# the original approval-vs-live-edit race.
psql_local -q <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$admin_id', true);
SELECT set_config('request.jwt.claims', '{"sub":"$admin_id","role":"authenticated"}', true);
UPDATE public.courses SET status = 'published' WHERE id = '$course_id'::uuid;
COMMIT;
SQL
# RACE 2: Two owner sessions create a revision for the same published course.
# The first creator pauses in the header INSERT trigger after its RPC has taken
# the course FOR UPDATE lock; the second call must be observed waiting on it.
PGAPPNAME="$app_revision_creator_a" timeout --signal=TERM --kill-after=2s "${SESSION_TIMEOUT_SECONDS}s" \
  psql -X -v ON_ERROR_STOP=1 -qAt >"$workdir/revision-creator-a.out" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$owner_id', true);
SELECT set_config('request.jwt.claims', '{"sub":"$owner_id","role":"authenticated"}', true);
SELECT public.create_course_revision('$course_id'::uuid) AS created_revision_id \\gset
\\echo CREATED_REVISION_ID=:created_revision_id
COMMIT;
SQL
revision_creator_a_pid=$!
wait_for_pause "$app_revision_creator_a" \
  || fail_with_logs "first owner revision creator did not enter the intentional header-insert pause"

PGAPPNAME="$app_revision_creator_b" timeout --signal=TERM --kill-after=2s "${SESSION_TIMEOUT_SECONDS}s" \
  psql -X -v ON_ERROR_STOP=1 -qAt >"$workdir/revision-creator-b.out" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$owner_id', true);
SELECT set_config('request.jwt.claims', '{"sub":"$owner_id","role":"authenticated"}', true);
SELECT public.create_course_revision('$course_id'::uuid);
COMMIT;
SQL
revision_creator_b_pid=$!
wait_for_blocking_relationship "$app_revision_creator_b" "$app_revision_creator_a" \
  || fail_with_logs "second owner revision creator was not observed blocked by the first via pg_blocking_pids()"
echo "PASS: observed the second create_course_revision call blocked by the first via pg_blocking_pids()."
wait_for_session "$revision_creator_a_pid" "first concurrent revision creator" success
revision_creator_a_pid=""
wait_for_session "$revision_creator_b_pid" "second concurrent revision creator" failure
revision_creator_b_pid=""
grep -Fq 'This course already has an active revision.' "$workdir/revision-creator-b.out" \
  || fail_with_logs "losing revision creation call did not fail with the expected active-revision error"
revision_id="$(sed -n 's/^CREATED_REVISION_ID=//p' "$workdir/revision-creator-a.out" | tail -n 1)"
[[ "$revision_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
  || fail_with_logs "first revision creator did not return a valid revision UUID"
revision_counts="$(psql_local -qAt -F '|' -c "
  SELECT count(*)::text,
         count(*) FILTER (WHERE status IN ('draft'::public.course_revision_status, 'pending_review'::public.course_revision_status))::text,
         count(*) FILTER (WHERE id = '$revision_id'::uuid)::text
  FROM public.course_revisions
  WHERE course_id = '$course_id'::uuid")"
IFS='|' read -r revision_total active_revision_total winning_revision_total <<<"$revision_counts"
[[ "$revision_total" == "1" && "$active_revision_total" == "1" && "$winning_revision_total" == "1" ]] \
  || fail_with_logs "concurrent revision creation left unexpected rows (total=$revision_total active=$active_revision_total winner=$winning_revision_total)"
echo "PASS: one owner revision committed; the blocked call failed with the active-revision error; exactly one active revision exists."

psql_local -q <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$owner_id', true);
SELECT set_config('request.jwt.claims', '{"sub":"$owner_id","role":"authenticated"}', true);
SELECT public.submit_course_revision('$revision_id'::uuid);
COMMIT;
SQL

# RACE 3: An admin live lesson edit owns the lesson tuple while paused; revision
# approval must wait on that exact editor, then reject the stale snapshot.
PGAPPNAME="$app_lesson_writer" timeout --signal=TERM --kill-after=2s "${SESSION_TIMEOUT_SECONDS}s" \
  psql -X -v ON_ERROR_STOP=1 -q >"$workdir/lesson-writer.out" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$admin_id', true);
SELECT set_config('request.jwt.claims', '{"sub":"$admin_id","role":"authenticated"}', true);
UPDATE public.lessons SET title = 'Changed concurrently' WHERE id = '$lesson_id'::uuid;
COMMIT;
SQL
lesson_writer_pid=$!
wait_for_pause "$app_lesson_writer" || fail_with_logs "lesson writer did not enter its intentional tuple-lock pause"

PGAPPNAME="$app_revision_approver" timeout --signal=TERM --kill-after=2s "${SESSION_TIMEOUT_SECONDS}s" \
  psql -X -v ON_ERROR_STOP=1 -q >"$workdir/lesson-approval.out" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$admin_id', true);
SELECT set_config('request.jwt.claims', '{"sub":"$admin_id","role":"authenticated"}', true);
SELECT public.approve_course_revision('$revision_id'::uuid);
COMMIT;
SQL
revision_approver_pid=$!
wait_for_blocking_relationship "$app_revision_approver" "$app_lesson_writer" \
  || fail_with_logs "revision approval was not observed lock-blocked by the live lesson editor"
echo "PASS: observed revision approval blocked by lesson editor via pg_blocking_pids()."
wait_for_session "$lesson_writer_pid" "published-course lesson edit" success
lesson_writer_pid=""
wait_for_session "$revision_approver_pid" "revision approval after live edit" success
revision_approver_pid=""
grep -Fq 'rejected: Cannot approve stale revision:' "$workdir/lesson-approval.out" \
  || fail_with_logs "approval did not record stale-revision rejection after the concurrent lesson edit"
lesson_title="$(psql_local -qAt -c "SELECT title FROM public.lessons WHERE id = '$lesson_id'::uuid")"
[[ "$lesson_title" == "Changed concurrently" ]] || fail_with_logs "concurrent lesson edit did not commit"
echo "PASS: lesson edit committed; approval rejected the stale revision; both sessions completed."

# RACE 4: A question edit owns the question tuple while paused; the answer-key
# RPC must be observed waiting on that exact question editor before both commit.
PGAPPNAME="$app_question_writer" timeout --signal=TERM --kill-after=2s "${SESSION_TIMEOUT_SECONDS}s" \
  psql -X -v ON_ERROR_STOP=1 -q >"$workdir/question-writer.out" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$admin_id', true);
SELECT set_config('request.jwt.claims', '{"sub":"$admin_id","role":"authenticated"}', true);
UPDATE public.assessment_questions SET prompt = 'Changed concurrently' WHERE id = '$question_id'::uuid;
COMMIT;
SQL
question_writer_pid=$!
wait_for_pause "$app_question_writer" || fail_with_logs "question writer did not enter its intentional tuple-lock pause"
version_before="$(psql_local -qAt -c "SELECT content_version FROM public.courses WHERE id = '$course_id'::uuid")"

PGAPPNAME="$app_answer_key_writer" timeout --signal=TERM --kill-after=2s "${SESSION_TIMEOUT_SECONDS}s" \
  psql -X -v ON_ERROR_STOP=1 -q >"$workdir/answer-key-writer.out" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '$admin_id', true);
SELECT set_config('request.jwt.claims', '{"sub":"$admin_id","role":"authenticated"}', true);
SELECT public.set_assessment_answer_key('$question_id'::uuid, '$option_b_id'::uuid);
COMMIT;
SQL
answer_key_writer_pid=$!
wait_for_blocking_relationship "$app_answer_key_writer" "$app_question_writer" \
  || fail_with_logs "answer-key RPC was not observed lock-blocked by the question editor"
echo "PASS: observed answer-key RPC blocked by question editor via pg_blocking_pids()."
wait_for_session "$question_writer_pid" "question edit" success
question_writer_pid=""
wait_for_session "$answer_key_writer_pid" "answer-key RPC" success
answer_key_writer_pid=""
question_prompt="$(psql_local -qAt -c "SELECT prompt FROM public.assessment_questions WHERE id = '$question_id'::uuid")"
answer_key="$(psql_local -qAt -c "SELECT correct_option_id FROM private.assessment_answer_keys WHERE question_id = '$question_id'::uuid")"
version_after="$(psql_local -qAt -c "SELECT content_version FROM public.courses WHERE id = '$course_id'::uuid")"
[[ "$question_prompt" == "Changed concurrently" ]] || fail_with_logs "concurrent question edit did not commit"
[[ "$answer_key" == "$option_b_id" ]] || fail_with_logs "answer-key RPC did not persist the requested option"
(( version_after > version_before )) || fail_with_logs "answer-key/edit operations did not advance course content version"
echo "PASS: question edit and answer-key RPC both committed; key and content version persisted."
