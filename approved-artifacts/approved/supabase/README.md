# Academi Supabase SQL package

This folder contains the LMS database foundation and local-only verification materials. The migrations are ordered forward changes: the original schema is `20261025015300_academi_lms_schema.sql`; staged course revisions are added by `20261101190000_course_revisions.sql`; lock-order plus initial-review hardening is added by `20261102192800_course_lock_order_and_review_freeze.sql`; and assessment deletion protection is added by `20261103000000_restrict_assessment_deletes.sql`. Earlier migrations remain unchanged. No hosted Supabase project is configured or linked by these files. Do not apply a migration to a hosted project until the target environment and migration have been reviewed and explicitly approved.

## Migration provenance warning

The historical file `20261102001600_course_revision_audit_hardening.sql` is missing from the available repository history. Its original contents cannot be reconstructed or assumed. The current four-migration chain was validated on a fresh disposable PostgreSQL 16 database; before applying migrations to any existing or hosted database, inspect that database's migration history and actual schema, reconcile any differences, and do not blindly apply the current chain.

## Registration profile provisioning

The original migration installs an `AFTER INSERT` trigger on `auth.users`. It creates the matching `public.profiles` row in the same transaction as Auth user creation. The display label is selected from user-provided `display_name`, then `full_name`, then the email local part, and finally `Learner`; it is trimmed and capped at 100 characters to satisfy the profile constraint. These metadata fields are only display text. They are never used to decide roles or permissions.

This trigger creates a profile only. It does not assign an instructor or administrator role, and it does not automatically assign a student role. Role provisioning beyond the first admin remains a separately reviewed trusted workflow.

## First administrator bootstrap

After the migration has been installed in a database, first create or invite the intended initial operator as an Auth user. Verify the account in Supabase Auth and copy its UUID. Then, as the trusted database object owner (for example, the database-owner context in the SQL Editor), run the following once, replacing the UUID with the verified user ID:

```sql
BEGIN;
SELECT private.bootstrap_first_admin('00000000-0000-4000-8000-000000000000'::uuid);
COMMIT;
```

The placeholder is deliberately not a real user and must be replaced. The function takes the same transaction advisory lock used by admin-role changes, verifies the Auth user exists, refuses to run if any admin already exists, creates a fallback profile only if needed, and assigns the first admin role. It records a null `granted_by` because no prior administrator exists. The migration revokes function execution from `PUBLIC`, `anon`, `authenticated`, and `service_role`; do not grant it to an application role or expose it through the Data API. If the transaction fails, roll it back and investigate before retrying.

This procedure is not a hosted setup step for the current review: no external project should be created or modified yet. When a target project is later approved, verify the executing database role and the Auth user ID before using the procedure.

## Staged course revisions

The forward migration adds `course_revisions` plus isolated staged outcomes, sections, and lessons. A partial unique index permits only one draft or pending revision per course; completed decisions remain in history. Revision creation records the live course content version and snapshots the course and curriculum while retaining existing section and lesson IDs.

The currently published course and curriculum remain the public approved version while an instructor prepares a revision or while an administrator reviews it. Instructors can edit only their own draft revisions. Once submitted, the revision and its staged rows are immutable to instructors. RLS, column/table grants, triggers, and security-definer RPC checks enforce these boundaries in the database. Only an administrator can approve or reject a submitted revision; a frontend check is not the authorization boundary. Staged revision content is not readable by anonymous users or ordinary students.

For an initial course submission, instructors create and edit while status is `draft`, then call `public.submit_course_for_review(course_id)`. The RPC verifies the authenticated instructor owns the unpublished draft and locks the course before changing only its status to `pending_review`. While pending, instructors cannot change metadata, outcomes, sections, lessons, assessments, questions, options, or answer keys. If the instructor needs to revise the submission, the owner-only `public.withdraw_course_submission(course_id)` returns an unpublished pending course to `draft`; it cannot withdraw a published course or publish anything. The instructor can edit and resubmit, and an administrator must still approve before publication. The content triggers re-read owner/status while holding the course lock, preventing a write that began under an older RLS snapshot from slipping through after submission.

Each live content change advances the course content version. Revision approval locks the revision, then the affected live lessons, sections, and outcomes in a stable table/ID order, then takes the per-course row lock and rechecks ownership/version before promotion. Answer-key updates lock question, assessment, then course, matching their row-trigger hierarchy. These narrower per-course locks address the two identified inversions; they are not global locks. PostgreSQL can still detect deadlocks in arbitrary multi-row or cross-table transactions, including cycles involving foreign-key locks. The affected SQL transaction is atomic; callers must retry the entire operation after SQLSTATE `40P01` rather than assuming every lock order is deadlock-free. Approval promotion remains one database function/transaction: metadata and curriculum changes either all succeed or all roll back. Existing IDs are updated in place where possible. A revision that would remove a lesson with learner progress or an associated assessment is rejected with a safe reason; it never silently deletes that lesson or its historical references.

The revision tables do not replace the live catalog tables. Public catalog/search/filter and course-detail reads continue to see the current published course, not staged content. No payment, certificate, dashboard, or unrelated feature was added.

## Preserve assessments on direct deletes

The forward-only migration `20261103000000_restrict_assessment_deletes.sql` changes only the existing `assessments.course_id` and `assessments(lesson_id, course_id)` foreign-key delete actions from `CASCADE` to `RESTRICT`. It preserves their columns, referenced keys, names, and all existing rows; PostgreSQL validates existing references while recreating the constraints. A lesson with an attached assessment and a course with an assessment can no longer be removed by cascading away the assessment. Existing `RESTRICT` references already prevent course deletion while enrollments exist, lesson deletion while learner progress exists, and deletion of assessment/enrollment history with attempts or responses. Authenticated course deletion remains disallowed by the existing grants and RLS policy; this migration grants no new privileges and does not change RLS. It does not add a global delete prohibition for an otherwise-unreferenced course. Recreating constraints takes a table lock and validates existing references; check for schema drift or invalid legacy data before any hosted application of this migration. There is no automatic down migration: restoring `CASCADE` requires a separate, reviewed change and could make later deletes destructive, so do not reverse these constraints automatically after dependent records have accumulated.

## Keep `private` out of the Data API

`config.toml` sets `[api].schemas` to `public` and `graphql_public`; it intentionally does not list `private`. The migration also revokes direct table privileges on the private answer-key table from client roles and enables RLS without a client policy. The `private` schema must remain excluded from the Supabase Data API exposed schemas.

The local `supabase/config.toml` controls the local CLI stack. Do not assume that committing it changes an already-hosted project's API configuration: before any future deployment, independently verify that the hosted project's API exposed-schema setting also omits `private`. Supabase documents `api.schemas` as the list of schemas exposed through its API; see the [CLI configuration reference](https://supabase.com/docs/guides/local-development/cli/config).

## Run pgTAP locally

Install the Supabase CLI and a Docker-compatible container runtime on your development computer. Supabase lists Docker Desktop, OrbStack, Rancher Desktop, and Podman among supported local-development options. See the [local development guide](https://supabase.com/docs/guides/local-development).

From the Academi repository root, run:

```sh
chmod +x supabase/test-local.sh
./supabase/test-local.sh
```

The script starts the local Supabase stack, runs `supabase db reset --local` to recreate the local database and apply files in `supabase/migrations`, and then runs `supabase test db`. **The reset deletes data in the local Supabase database.** The script contains no `supabase link`, `--linked`, or remote database URL command, and should not be changed to target hosted data. Stop the local stack afterward with `supabase stop`.

The pgTAP files insert fixture users into local `auth.users`, which exercises profile provisioning, role restrictions, ownership/publication, learner-data isolation, progress and answer-key protection. The course-revision suite additionally tests staged-content isolation, owner/admin authorization, immutable submitted revisions, stale detection, safe ID preservation and removal, all-or-nothing promotion, and the original submission/publication flow. The review-freeze suite tests role boundaries, metadata/curriculum/assessment/answer-key writes while pending, owner-only withdrawal, editing after withdrawal, resubmission, and admin-only publication. The deletion suite tests missing course DELETE privilege, privileged course deletes blocked by enrollments or assessments, lesson deletes blocked by learner progress or assessments, and preservation of related records after failed deletes. Fixture rows are rolled back at the end of each file. The runner reports actual assertion counts. Supabase’s [database testing guide](https://supabase.com/docs/guides/database/testing) documents `supabase test db` and pgTAP SQL tests.

Run the two-session lock-race checks **only against a disposable local PostgreSQL database** with all migrations applied. The script fails before connecting unless `ACADEMI_DISPOSABLE_DB_CONFIRM` is set exactly to `I_CONFIRM_THIS_DATABASE_IS_DISPOSABLE`. For the default local Supabase database, after verifying that it is disposable, use:

If password authentication is required, configure it through a protected `.pgpass` file or `PGPASSFILE`; do not place a database password in the command or script.

```sh
ACADEMI_DISPOSABLE_DB_CONFIRM=I_CONFIRM_THIS_DATABASE_IS_DISPOSABLE \
PGHOST=127.0.0.1 PGPORT=54322 PGUSER=postgres PGDATABASE=postgres \
./supabase/test-concurrency.sh
```

The script prints the connected database name, role, server address, and port before fixture setup. It still refuses non-loopback connections, requires a local superuser, uses UUID-isolated fixtures and bounded timeouts, and does not reset the database. For every expected wait, it verifies the blocker through `pg_blocking_pids()`; an active query alone is not proof. It runs four two-session races: an owning instructor's content edit waiting behind initial submission (then rejected after the course becomes pending); two owner calls creating a revision for the same course (the second is observed blocked, then fails because the first created the single active revision); live lesson editing waiting against revision approval (then stale-revision rejection); and question editing waiting against the answer-key RPC. Per-run UUIDs scope the temporary pause function/triggers, and cleanup errors are reported. Never use a hosted database, a tunnel, or a local database with data that must be retained.

## Verification results and limits

On 2026-11-03, all four migrations were applied in timestamp order to a fresh disposable PostgreSQL 16 database using local compatibility fixtures for `anon`, `authenticated`, `service_role`, `auth.users`, `auth.uid()`, and the `extensions` schema. All four pgTAP files passed: **293/293 assertions** (57 core LMS, 121 staged revisions, 88 initial-review freeze, 27 delete restrictions). The loopback-only concurrency driver passed all four two-session races and explicitly observed each expected blocker through `pg_blocking_pids()`: (1) the owner's lesson edit waited on initial submission, was rejected after submission committed, and left the course pending with unchanged lesson content; (2) two calls to `create_course_revision` for the same course ran as the owning instructor, the second was observed blocked behind the first, then failed with the expected active-revision error, and exactly one active revision remained; (3) the concurrent lesson edit committed and revision approval recorded a stale-revision rejection; and (4) the question edit and answer-key RPC both committed, with the requested key and increased course content version. All expected lock waits were observed and sessions completed within their timeouts. The test driver reported successful per-run fixture and trigger cleanup; the temporary PostgreSQL listener and cluster directory were verified removed. `bash -n` and `git diff --check` passed.

Supabase CLI/Docker were unavailable, so `supabase/test-local.sh` and a complete local Supabase/PostgREST stack were not run. The disposable PostgreSQL compatibility fixture tests SQL DDL, functions, triggers, grants, RLS, pgTAP assertions, and transaction-level lock behavior, but does not establish full Auth/PostgREST behavior or hosted project configuration. The local `config.toml` exposed-schema list is set to `public` and `graphql_public`, excluding `private`. No external project was connected, no hosted credentials were requested, and no migration was applied remotely.
