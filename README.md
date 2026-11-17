# Academi

Academi is an early-stage online learning platform built with Next.js App Router, TypeScript, and Tailwind CSS. With no Supabase environment values configured, the site uses clearly labeled local demo courses. When the public Supabase URL and anonymous key are supplied, the catalog reads published courses and their details from Supabase; no hosted project was configured or contacted for this implementation.

## Run locally

Requirements: Node.js 22 or later and pnpm 11.25.0.

```sh
pnpm install --frozen-lockfile
pnpm dev
```

Open `http://localhost:3000`. Without Supabase environment values, the app uses its demo catalog. `pnpm typecheck`, `pnpm lint`, and `pnpm build` run the application checks. See `.env.example` for the optional public catalog/auth client configuration. Never put a service-role key in a browser-exposed variable or commit secrets.

## Current application scope

- Responsive homepage and course catalog with text search and topic/category filtering.
- Course cards and course detail routes backed by demo data by default, or published catalog content when a Supabase URL and anonymous key are configured.
- Sign-in and sign-up routes and Supabase client scaffolding; end-to-end hosted authentication was not verified in this database task.
- Route declarations at `/manus-routes.json`.

The existing catalog, search/filter controls, and course-detail pages were not changed by the revision-schema work. Enrollment checkout, lesson playback, learner progress, quiz submission/scoring, certificates, and payments are not implemented as end-to-end student workflows; this work adds no such features.

## Database foundation

`supabase/migrations/` contains the original LMS schema/access-control migration and a new forward migration, `20261101190000_course_revisions.sql`. The new migration adds a single-active staged course revision workflow. Until an administrator approves a current revision, the published course and curriculum remain live and public. Database functions, triggers, grants, and RLS enforce ownership, admin-only decisions, submitted-revision immutability, stale-version rejection, safe lesson-removal rejection, and atomic promotion. The original migration was not rewritten.

The isolated pgTAP tests are in `supabase/tests/`. For an official local Supabase CLI run, install the Supabase CLI and a compatible local container runtime, then use:

```sh
chmod +x supabase/test-local.sh
./supabase/test-local.sh
```

This resets the **local** Supabase database before applying migrations and running all database tests. It is not a hosted deployment command. No hosted Supabase project was connected or migrated for this task.

## Local verification record

On 2026-11-01, both migrations were applied to a fresh, disposable PostgreSQL 16.15 database with minimal local Supabase-compatible `auth.users`, `auth.uid()`, and API-role fixtures. Both repository pgTAP files passed via `pg_prove`: **178/178 assertions** (57 existing access tests and 121 course-revision tests). The new tests cover staged isolation, ownership and administrator authorization, immutable submissions, ID retention, progress/assessment-safe removals, stale revisions including assessment descendants, atomic rollback, and the original submission/publication flow.

`pnpm typecheck`, `pnpm lint`, and `pnpm build` passed. A local production HTTP smoke check returned 200 for the catalog, a sample course detail, and `/manus-routes.json`, and confirmed the catalog search/category controls and detail content render. Supabase CLI/Docker was unavailable, so `supabase/test-local.sh` and the full Supabase/PostgREST stack were not exercised. This local compatibility run does not establish hosted Supabase behavior. No remote credentials were requested, no hosted project was connected, and no migration was applied remotely.

## Next work

Pause for review of this database foundation before starting another milestone or adding unrelated platform features.
