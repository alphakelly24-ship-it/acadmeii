# Academi Milestone Tracker

## Completed — Milestone 1: Project Foundation

- [x] **Runnable application foundation and responsive learner-facing interface**
  - Build a real, functional web application rather than a static visual prototype.
  - Use Next.js, TypeScript, Tailwind CSS, and a Supabase-ready architecture where the available tools and environment support them.
  - Make the interface professional, modern, responsive, and easy to navigate on desktop and mobile.
  - Keep code organized and maintainable, avoid unnecessary dependencies, and preserve existing working functionality.
  - Make core Milestone 1 interactions work without requiring a configured database or external service, and clearly identify demo-only data or behavior.

- [x] **Affordable and secure project setup documentation**
  - Do not assume Supabase, hosting, or other external services are configured.
  - Do not expose API keys, database credentials, or other secrets in client-side code.
  - Identify any required paid services, costs or limitations, and required accounts, credentials, or setup steps before committing to them.
  - Explain what is implemented, what works, what remains incomplete, and how the user can test the application.

- [x] **Marketplace expansion boundary and review stop**
  - Prepare the architecture for a future regional, multi-instructor marketplace without implementing advanced marketplace features now.
  - Do not implement real payments or instructor payouts.
  - Do not proceed to Milestone 2 until the user has reviewed Milestone 1.

## Prepared for user review — Milestone 2 SQL design and local validation only

- [x] **Reviewable schema migration and access-control policies**
  - Retain the proposed tables for profiles, roles, instructor profiles, categories, courses, course sections, lessons, enrollments, lesson progress, assessments, quiz questions, answer keys, assessment attempts, and responses.
  - A user may have both student and instructor roles. Users must not be able to grant themselves instructor or administrator privileges.
  - Each course will initially have one primary instructor owner. Instructors may manage their own courses, but administrators must approve courses before publication.
  - Enforce access control through database permissions, row-level security, and trusted server-side operations. Do not rely solely on frontend restrictions.
  - Students must not be able to manipulate enrollment records, quiz scores, pass results, or other protected data.
  - Prepare reviewable SQL migration files, including appropriate constraints, indexes, grants, and row-level security policies. Where possible, include tests for both permitted and denied operations.

- [x] **Registration profile provisioning and first administrator bootstrap**
  - Add an `auth.users` `AFTER INSERT` trigger that automatically provisions a matching `public.profiles` row upon user registration.
  - Provide a documented, secure SQL bootstrap procedure or function to safely provision the very first administrator during initial setup.
  - Users must not be able to assign themselves instructor or administrator roles; the first-admin bootstrap must be restricted to a trusted database-owner context and unavailable to client/API roles.

- [x] **Local Data API configuration and pgTAP test instructions**
  - Exclude the `private` schema from Supabase Data API exposure through local `supabase/config.toml` configuration.
  - Provide instructions or a script to run the pgTAP test suite locally using Supabase CLI and a Docker-compatible runtime.
  - Do not claim the migration is fully tested until automated tests have actually run against a suitable PostgreSQL environment.

- [x] **Preservation, setup, and approval boundary**
  - Preserve the existing homepage, course catalog, search, category filters, and course-detail pages. Avoid unnecessary architectural changes.
  - Keep payments, subscriptions, commissions, instructor payouts, certificates, and advanced marketplace features outside this milestone.
  - Do not connect to an external Supabase project, request credentials, implement application authentication, or modify existing application code. SQL-side registration profile provisioning is in scope. Do not expose secrets or credentials in source files or chat.
  - Before proceeding beyond SQL design and local validation, show the migration files, explain the security policies in beginner-friendly language, identify unresolved issues, and wait for the user's approval.
  - Do not begin another milestone without the user's explicit approval.

### Launch-market planning

- [x] **Initial market: Yemen** — Yemen is the selected initial launch market. This decision does not authorize creating a hosted Supabase project or choosing/applying a database region; hosted configuration requires separate review and explicit approval.

### Validation boundary

The migration includes all requested tables with RLS enabled, profile provisioning, and owner-only first-admin bootstrap. On 2026-10-31, the migration and pgTAP suite were executed against a disposable PostgreSQL 16.15 cluster with minimal Supabase-compatible Auth/role fixtures: all 57/57 assertions passed. This is not a full Supabase-stack or PostgREST API exposure test; `supabase/test-local.sh` was not run because Supabase CLI and Docker are unavailable, and `config.toml` was only parsed and statically checked. The temporary cluster was removed. No hosted migration was applied, no external service was configured, and no application source files were changed.

## Completed — Milestone 3: Supabase client utilities (approved slice)

- [x] **Install requested Supabase SSR packages**
  - Install the required packages via pnpm: `pnpm add @supabase/ssr @supabase/supabase-js`.

- [x] **Create browser and server client utilities**
  - Create the browser Supabase client at `src/lib/supabase/client.ts` using `createBrowserClient` from `@supabase/ssr` with `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
  - Create the server Supabase client at `src/lib/supabase/server.ts` using `createServerClient` from `@supabase/ssr`, reading and writing cookies safely across Server Components, Server Actions, and Route Handlers.

- [x] **Add session-refresh middleware and verify the build**
  - Create the root `middleware.ts` file implementing session refreshing and cookie management using Supabase middleware utilities.
  - Verify that the project builds successfully with `pnpm build` after adding these utilities.
  - Do not connect to a remote database or modify existing components yet.

### Validation boundary

`pnpm typecheck`, `pnpm lint`, and `pnpm build` all passed after the utility changes. No Supabase URL/key was configured, no Supabase client was invoked, and no remote service was contacted. Existing application components were not changed. `pnpm peers check` still reports the pre-existing ESLint 10 installation is outside peer ranges declared by three existing ESLint plugins; that unrelated dependency configuration was left unchanged, and lint passed. Next.js 16 marks `middleware.ts` as deprecated in favor of `proxy.ts`; the requested `middleware.ts` was kept and the build recognized it as the Proxy/Middleware layer.

## Completed — Milestone 3: Authentication UI and flows

- [x] **Supabase environment template and auth routes**
  - Create an example `.env.local` template (if not already present) for Supabase URL and anon key.
  - Build the Sign In and Sign Up pages under `src/app/auth/signin/page.tsx` and `src/app/auth/signup/page.tsx`.

- [x] **Registration, login, and user-facing states**
  - Implement form handling using the Supabase browser client (`createClient()`) for user registration and login.
  - Ensure error handling (e.g., incorrect passwords, existing emails) and success states (e.g., redirecting to the catalog or dashboard) are handled gracefully.

- [x] **Build verification**
  - Verify that the project compiles and builds successfully with `pnpm build` after adding these pages.

### Validation boundary

`pnpm typecheck`, `pnpm lint`, and `pnpm build` passed. The build emitted `/auth/signin` and `/auth/signup`; local HTTP checks confirmed both pages and `/manus-routes.json` return 200 with the expected content and five declared routes. Supabase URL and anon key are unset, so no Auth request was made and actual registration, login, email delivery, and session persistence were not end-to-end tested. A configured Supabase project is required; the reviewed profile-provisioning migration must also be applied before new Auth users receive Academi profiles. No service-role key is used.

## Completed — Milestone 3: Auth-aware site header

- [x] **Resolve and display the active user**
  - Use the Supabase server/client utilities to check for an active user session.
  - For logged-out users/visitors, show the existing navigation links, plus "Sign In" and "Sign Up" action buttons.
  - For logged-in users, display the user's name/email or profile avatar in the navigation bar.

- [x] **Sign out and responsive behavior**
  - Provide a "Sign Out" action button that calls `supabase.auth.signOut()` and redirects cleanly to the homepage.
  - Ensure the layout remains clean, responsive, and mobile-friendly.

- [x] **Quality checks**
  - Verify that typecheck, lint, and build checks pass (`pnpm build`) after implementing these updates.

### Validation boundary

`pnpm typecheck`, `pnpm lint`, and `pnpm build` passed. With Supabase variables unset, a local HTTP request confirmed the homepage returns 200 and renders the existing navigation with Sign In and Sign Up actions; the server and browser clients make no Auth request in this state. The configured-user display, actual `signOut()` call, and post-sign-out redirect are implemented but could not be exercised end-to-end without a Supabase project/session. The header is presentation only and does not authorize protected data or routes.

## Completed — Milestone 4: Read-only live course catalog

- [x] **Database-backed catalog data with safe fallback**
  - Update the catalog data layer (in `src/lib/demo-courses.ts` or a new Supabase query module) to fetch live records from the `courses` and `categories` tables when Supabase environment variables are present, and resolve instructor display names through the schema-authorized public `instructor_profiles` relationship.
  - Fall back cleanly to sample data or present a clear empty state if no credentials are set or no courses exist in the database yet.
  - The reviewed schema restricts `public.profiles` to the user and administrators; for publicly visible instructor names, use `instructor_profiles.public_name`, not a direct query of private profiles.

- [x] **Live search, filters, and detail links**
  - Ensure search queries and category filtering work seamlessly against live database records.
  - Preserve existing sample course details when Supabase is not configured; live catalog cards must resolve to published live course details.

- [x] **Quality checks**
  - Verify that `pnpm typecheck`, `pnpm lint`, and `pnpm build` pass successfully.

### Validation boundary

`pnpm typecheck`, `pnpm lint`, and `pnpm build` passed. Eight assertions against live-shaped course records passed for title/description/instructor search, category selection, combined filters, zero matches, and reset. With Supabase variables unset, `/courses` returned HTTP 200 with four sample results and search/filter controls; a sample detail returned 200, an unknown slug returned 404, and `/manus-routes.json` returned valid JSON. No Supabase query was executed and the live path was not end-to-end verified because there is no configured project or credential. The migration remains unapplied. The approved schema intentionally does not expose other users' `public.profiles`; live instructor names come from `instructor_profiles.public_name`.

## Database hardening updates

### Completed locally — approved database lock/review hardening (awaiting user review)

- [x] **Course lock-order analysis and concurrency safety**
  - Before changing code, map the complete lock acquisition order for all affected operations, including implicit row locks acquired before triggers execute.
  - Verify that the ordering is consistent across approval, child-row edits/deletes, and answer-key updates.
  - Do not assume that explicitly locking rows in a deterministic order eliminates every deadlock.
  - If a fully consistent order cannot be guaranteed, implement safe transaction behavior and document which operations may require retry.
  - Keep locking narrow and avoid global serialization.
  - Test genuine two-session concurrency for both identified lock races and demonstrate the expected result, not merely that both SQL commands execute.

- [x] **Freeze pending initial submissions and provide owner-only withdrawal**
  - Instructors must not be able to edit course metadata, outcomes, sections, lessons, assessments, or other submitted content while the initial course submission is pending review.
  - Add a secure owner-only withdrawal operation that returns the course to draft.
  - Verify that withdrawal cannot bypass administrator approval or affect published courses.
  - After withdrawal, the instructor must be able to edit and submit again.
  - Preserve the existing staged-revision process for already-published courses.
  - Test unauthorized users, other instructors, and students as well as the owning instructor; test every relevant pending-review edit path, including direct database operations and RPCs.
  - Test instructor attempts to approve or publish courses.

- [x] **Forward-only changes and local-only verification boundary**
  - Use a new forward-only migration; do not edit or rewrite existing migrations.
  - Do not weaken RLS, ownership checks, admin approval, or deletion protections.
  - Keep all tests local and disposable. Do not connect to hosted Supabase, deploy, commit, or push.
  - Run relevant local tests and run typecheck, lint, and build if application files change.
  - Report exact files changed, full migration behavior and rollback considerations, pgTAP assertion count/results, two-session concurrency results, applicable code quality checks, and remaining risks. Stop for user review before commit or hosted work.

### Validation results and limits

All three migrations were applied in timestamp order to a fresh disposable PostgreSQL 16 cluster with local Supabase-compatible Auth/role fixtures. All pgTAP suites passed: 266/266 assertions (57 core LMS, 121 course revisions, 88 pending-review freeze). The concurrency driver passed three two-session races and observed each expected blocking relationship through `pg_blocking_pids()`: an owning instructor's lesson edit waited behind initial submission and was rejected after the course became pending; the live lesson edit committed and revision approval rejected the stale snapshot; and the question edit plus answer-key RPC both committed, the requested key persisted, and course content version advanced. All waits/sessions stayed within configured timeouts and cleanup removed the per-run objects and fixture rows. No deadlock occurred in these controlled races.

The Supabase CLI/Docker stack and hosted Supabase were not used, so actual PostgREST/Auth behavior and hosted configuration remain unverified. No application code changed; application typecheck/lint/build were not rerun. No remote migration, commit, push, or deployment occurred; the temporary database cluster was removed.

### Accepted concurrency-test follow-up (complete; awaiting user review)

- [x] **Verify real lock waits and bound every test wait**
  - When a test expects session B to wait on session A, verify the actual blocking relationship using `pg_blocking_pids()` or an equivalent PostgreSQL lock-wait check.
  - Do not treat an `active` query alone as proof of blocking.
  - Add bounded timeouts to all polling and session waits.
  - On timeout, print useful diagnostics including session PIDs, query states, wait events, and blockers.
  - Ensure the test fails if the intended lock wait never occurs.
- [x] **Race an owning instructor's draft content edit against initial submission**
  - Add a genuine two-session test using the owning instructor identity, not only an administrator.
  - Race a draft course content edit against the owner's initial submission for admin review.
  - Verify the intended serialization outcome and final course status/content.
  - Confirm that no instructor edit can slip through after the course becomes `pending_review`.
  - Ensure the test is deterministic, bounded by timeouts, and checks the actual blocking relationship where applicable.
- [x] **Make concurrency-test cleanup unique, ownership-safe, and visible**
  - Replace fixed temporary function and trigger names with unique per-run names, or safely refuse to start if collisions exist.
  - Cleanup must only remove objects created by the current run.
  - Do not suppress cleanup errors silently.
  - Ensure cleanup runs on success, failure, and interruption where shell behavior permits.
  - Keep the existing local-only database URL validation and safety checks intact.
- [x] Do not edit application files or any of the three migrations; run concurrency tests only against an explicitly disposable local PostgreSQL database; run the full pgTAP suite against a fresh disposable PostgreSQL 16 database after changes; run shell syntax checks and `git diff --check`; do not connect to hosted Supabase, deploy, commit, or push; report exact changed files, results, remaining concurrency limitations, and current Git status, then stop for user review.

### Completed locally — assessment-preserving deletes and concurrent revision creation (awaiting user review)

- [x] **Assessment-preserving deletes and concurrent revision creation**
  - Add a new forward-only migration changing only the two assessment foreign-key delete actions from CASCADE to RESTRICT; preserve all existing data, columns, relationships, other constraints, RLS policies, and permissions.
  - Prevent deleting a lesson if it has an attached assessment, and prevent deleting a course if it has assessments, enrollments, or learner progress. Do not weaken RLS or grant additional DELETE privileges.
  - Add direct-deletion pgTAP tests proving an authenticated instructor cannot directly delete a course; privileged database-level course deletion is blocked by enrollments and assessments; lesson deletion is blocked by learner progress and assessments; and failed deletes leave related records intact.
  - Add a genuine concurrent `create_course_revision` test using two independent PostgreSQL sessions as the owning instructor for the same course. Verify the expected blocking relationship with `pg_blocking_pids()`, bounded timeouts, safe per-run cleanup, exactly one active revision, and a clean losing-call failure without a duplicate.
  - Preserve the pending-review freeze and withdrawal workflow, course ownership, administrator approval, RLS, staged revisions, and existing migrations. Do not introduce global advisory locking or recreate the missing historical migration.
  - Apply migrations in timestamp order to a fresh disposable PostgreSQL 16 database; run the complete pgTAP and concurrency suites; run `bash -n` and `git diff --check`.
  - Do not connect to hosted Supabase, deploy, commit, or push. Report exact changed files, migration behavior, test counts/results, concurrency evidence, Git status, rollback considerations, and remaining limitations, then stop for user review.

### Validation results and limits

All four migrations were applied in timestamp order to a fresh disposable PostgreSQL 16 cluster. All four pgTAP files passed: **293/293 assertions** (57 core LMS, 121 staged revisions, 88 initial-review freeze, 27 deletion protection). The local concurrency driver passed all four two-session races and explicitly confirmed each expected wait through `pg_blocking_pids()`; for concurrent owner revision creation, the first call committed, the blocked second call failed with the expected active-revision error, and exactly one active revision remained. `bash -n` and `git diff --check` passed. The driver removed its per-run fixtures and trigger/function, and the temporary cluster listener and data directory were verified removed.

The run used a disposable local PostgreSQL 16 compatibility harness, not Supabase CLI/PostgREST or a hosted project. Hosted schema drift and existing hosted rows could not be inspected; the new migration validates references when applied and may fail if a hosted database differs from the reviewed schema. No application files, existing migrations, remote database, commit, push, or deployment were changed.

## Later outcomes — require separate approval

- [ ] **Role-based authorization and account lifecycle controls** — implement protected routes, trusted role flows, profile management, and password recovery only after explicit approval and service setup; the current UI does not implement these.
- [ ] **Course authoring, instructor management, and admin publication controls** — preserve current pages and live discovery behavior while adding write workflows only after approval.
- [ ] **Enrollment, lesson progress, and assessments** — add trusted operations for eligibility, validated completion, quiz scoring, and results only after approved access rules.
- [ ] **Marketplace, payment, certificate, and production work** — require separate requirements, regional/provider review, cost review, and explicit approval; none is authorized by the current approved authentication UI scope.
