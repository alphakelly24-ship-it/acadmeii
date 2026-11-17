# Academi Supabase SQL package

This folder contains the LMS database foundation and local-only verification materials. The migrations are ordered forward changes: the original schema is `20261025015300_academi_lms_schema.sql`; the staged course revision addition is `20261101190000_course_revisions.sql`. The original migration is unchanged. No hosted Supabase project is configured or linked by these files. Do not apply a migration to a hosted project until the target environment and migration have been reviewed and explicitly approved.

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

Each live content change advances the course content version. Approval rejects stale snapshots instead of overwriting newer live edits. Promotion is executed inside one database function/transaction: metadata and curriculum changes either all succeed or all roll back. Existing IDs are updated in place where possible. A revision that would remove a lesson with learner progress or an associated assessment is rejected with a safe reason; it never silently deletes that lesson or its historical references. The original initial course-submission and admin-publication flow remains in place.

The revision tables do not replace the live catalog tables. Public catalog/search/filter and course-detail reads continue to see the current published course, not staged content. No payment, certificate, dashboard, or unrelated feature was added.

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

The pgTAP files insert fixture users into local `auth.users`, which exercises profile provisioning, role restrictions, ownership/publication, learner-data isolation, progress and answer-key protection. The course-revision suite additionally tests staged-content isolation, owner/admin authorization, immutable submitted revisions, stale detection, safe ID preservation and removal, all-or-nothing promotion, and the original submission/publication flow. Fixture rows are rolled back at the end of each file. The runner reports actual assertion counts. Supabase’s [database testing guide](https://supabase.com/docs/guides/database/testing) documents `supabase test db` and pgTAP SQL tests.

## Verification results and limits

On 2026-11-01, both migrations were applied in timestamp order to a fresh disposable PostgreSQL 16.15 database using minimal local compatibility fixtures for `anon`, `authenticated`, `service_role`, `auth.users`, `auth.uid()`, and the `extensions` schema. The complete repository pgTAP suite was run with `pg_prove`: **178/178 assertions passed** across both files (**57** in `20261025015300_lms_access.test.sql`; **121** in `20261101190000_course_revisions.test.sql`).

Supabase CLI/Docker were unavailable, so `supabase/test-local.sh` and a complete local Supabase/PostgREST stack were not run. The compatibility fixture tests PostgreSQL DDL, functions, triggers, grants, RLS, and pgTAP assertions, but does not establish full Auth/PostgREST behavior or hosted project configuration. The local `config.toml` exposed-schema list is set to `public` and `graphql_public`, excluding `private`. No external project was connected, no hosted credentials were requested, and no migration was applied remotely.
