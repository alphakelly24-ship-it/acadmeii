# Academi — Project Plan and Staged Implementation

## Scope and architecture

Milestone 1 established a real, runnable web application foundation and a small working learner-facing experience. The approved work now also includes review-only database migrations, Supabase sign-in/sign-up UI, an auth-aware header, and read-only live course discovery. This is not the full LMS: payments, payouts, enrollment, lesson progress persistence, certificates, course authoring, and marketplace operations remain staged for later review.

The workspace was initialized as a flexible WebDev project with no application framework or dependencies installed. The managed server runtime is enabled for a Next.js application; the managed WebDev database is disabled. No external hosting, Supabase project, credential, or paid third-party integration is assumed or configured. This project's preview and future production costs depend on the user's Manus/WebDev plan; check that plan before production. No third-party paid service is required for local Milestone 1 use.

Use Next.js App Router with TypeScript and Tailwind CSS. Keep course examples in a typed, clearly identified demo-data module so search and category selection work before a database exists. Use server-rendered routes where practical and small client components only for interactive controls. The currently approved authentication UI uses Supabase SSR browser/server clients and request middleware; the shared layout checks the user when public Supabase settings are present, and the client header handles auth events and sign-out. The currently approved catalog data layer performs read-only queries for published courses, categories, and public instructor-profile display fields under RLS when configured; otherwise it shows labeled samples. No project credentials are currently configured, no hosted schema has been applied, and no service-role key belongs in browser code.

### Future marketplace readiness

The later relational model will give each course an `instructor_id` owner and use separate profile and role records. Sections and lessons belong to a course; enrollments and progress belong to a student. This supports multiple independent instructors and future regional availability without introducing marketplace transactions now. No regional pricing, checkout, commissions, taxes, or payouts are implemented in Milestone 1.

## Project structure

- `src/app/`: App Router pages, root layout, and global styles.
- `src/components/`: reusable responsive navigation, brand mark, course cards, catalog filters, and page-level UI pieces.
- `src/components/site-header.tsx`: client navigation/menu, live auth-state updates, responsive account actions, and sign-out.
- `src/app/layout.tsx`: request-scoped Supabase user lookup when configured; pass only the display name/email to the header. This makes shared routes request-aware when Auth is configured and reduces static caching, but avoids a stale guest header.
- `src/components/auth-form.tsx`: shared accessible sign-in/sign-up form behavior, validation feedback, and Supabase Auth calls.
- `src/app/auth/signin/` and `src/app/auth/signup/`: learner sign-in and account registration pages.
- `src/lib/demo-courses.ts`: typed, explicitly demo-only catalog data retained as the no-credentials fallback.
- `src/lib/catalog-data.ts`: server-side read-only queries for published courses and categories, mapping only public instructor-profile fields; a query error has a clear error state, and a successful empty database has a clear empty state.
- `src/lib/course-filter.ts`: shared pure search/category filtering over demo or live catalog records, including title, description, instructor, category, level, outcomes, and curriculum text.
- `src/app/courses/page.tsx` and `src/app/courses/[slug]/page.tsx`: load live catalog/details when configured while preserving the demo fallback and route behavior.
- `src/lib/supabase/`: approved Milestone 3 browser and server client utilities; auth UI uses the browser client.
- `middleware.ts`: cookie/session refresh boundary; it remains inactive without Supabase environment variables.
- `public/`: favicon, local visual assets, and `/manus-routes.json` route manifest.
- `docs/`: setup notes and asset source notes where useful.
- `supabase/config.toml`: local Data API schema exposure; keep `private` excluded.
- `supabase/migrations/`: reviewed database schema, registration provisioning, role controls, and RLS policies.
- `supabase/tests/` and `supabase/test-local.sh`: local pgTAP coverage and the non-linked local test command.
- `supabase/README.md`: trusted first-admin bootstrap and local setup instructions.
- `plan.md` and `TODO.md`: agreed technical/design plan and staged outcome tracking.
- `.env.example`: blank Supabase URL and anon-key template to copy to the ignored `.env.local`; no real credentials.

## Design direction

Three uncommon style options considered: **Editorial learning studio** (0.07): generous paper-like space, confident type, and an evergreen identity; **Quiet scholarly notebook** (0.05): restrained ink tones and fine rules; **Contemporary campus journal** (0.03): modular editorial blocks with warm accents. Choose **Editorial learning studio**.

- **Design Movement:** Contemporary editorial publishing, applied to a practical digital learning product.
- **Core Principles:** Calm confidence; clear reading hierarchy; useful content before decoration; consistent, accessible interaction states.
- **Color Philosophy:** Warm off-white backgrounds reduce visual glare; deep evergreen gives the brand a grounded, trustworthy anchor; muted sage provides quiet supporting surfaces; a restrained warm ochre marks emphasis without turning the experience into a sale banner.
- **Layout Paradigm:** Left-aligned editorial landing page with a split hero, a narrow section index on wider screens, and a naturally stacked flow on mobile. Course content uses flexible cards rather than a centered, uniform marketing grid.
- **Signature Elements:** An open-book “A” brand mark; a slim evergreen rule for section anchors; small rounded lesson markers that echo tabs in a notebook.
- **Interaction Philosophy:** Obvious, keyboard-accessible controls; search and category filters update results immediately; navigation collapses cleanly on small screens; never imply an enrollment or saved change succeeded when it has not.
- **Animation:** Minimal and purposeful. Use short opacity/position transitions for mobile navigation and filter result changes; honor `prefers-reduced-motion`; no autoplay or scroll-jacking.
- **Typography System:** Use a readable sans-serif stack for interface and body copy with a contrasting editorial display serif for major headings. Keep body text comfortable on small screens and reserve display type for short headlines.
- **Brand Essence:** A clear, steady place to build practical skills through structured learning; **thoughtful, capable, welcoming**.
- **Brand Voice:** Direct, encouraging, and specific. Example lines: “Build a skill one lesson at a time.” “Find a course that fits the way you learn.”
- **Wordmark & Logo:** A custom open-book “A” symbol paired with the lowercase Academi wordmark; keep the symbol recognizable at favicon size and use the full lockup in the site header.
- **Signature Brand Color:** Academi Evergreen, `#1F6B5B`.

## Milestone roadmap

1. **Project foundation (current):** initialize the Next.js/TypeScript/Tailwind application, reusable responsive shell, route manifest, basic accessible visual system, working demo catalog discovery interactions, project setup documentation, and environment boundary. No database, auth, payment, or payout work.
2. **Database and access rules (SQL files under review):** prepare reviewable migrations, RLS policies, an `auth.users` profile-provisioning trigger, an owner-only first-admin bootstrap, local API schema configuration, and local pgTAP tests. Do not create or connect a hosted Supabase project or choose its region until the initial target market is decided. Do not implement application authentication or data integration in this stage. Keep payments, subscriptions, commissions, payouts, certificates, and advanced marketplace features out of scope.
3. **Supabase SSR and authentication UI (current approved slices):** use `@supabase/ssr` browser/server clients and middleware; add learner sign-in and sign-up pages using `supabase.auth.signInWithPassword` and `supabase.auth.signUp`; handle invalid credentials, likely duplicate registration, and confirmation-email responses; redirect authenticated users to the existing `/courses` route. The shared layout checks the active user with the server client when Supabase is configured; the client header reflects auth events and signs users out, redirecting to `/`. This request-specific header lookup reduces static caching when configured, but does not run without URL/key values. Keep sessions in cross-site Preview-capable cookies (`SameSite=None; Secure`); keep any plain-HTTP local testing choice explicit rather than deriving it from `NODE_ENV` or internal request security. The `.env.example` contains blank URL/anon-key entries for copying to `.env.local`. Do not put service-role keys in browser code. This UI can compile without credentials, but end-to-end authentication requires a configured Supabase project and the reviewed profile-trigger migration. Supabase's current Next.js guide uses the same client/cookie pattern and identifies `getClaims()` for token refresh [Supabase SSR setup](https://supabase.com/docs/guides/auth/server-side/creating-a-client). Next.js 16 deprecates the `middleware.ts` convention in favor of `proxy.ts`, but the existing file remains as explicitly requested [Next.js Proxy convention](https://nextjs.org/docs/app/api-reference/file-conventions/proxy).
4. **Read-only live catalog (current approved slice):** when Supabase URL/anon key are configured, query published `courses` and `categories`, map the public `instructor_profiles.public_name` relation, and preserve existing live search/category filtering and course details. Do not query `public.profiles` for other users: its reviewed RLS permits only self/admin access. Without credentials retain sample data; with successful queries but no published rows show a clear empty state; query failures show a clear unavailable state rather than silently substituting samples. This is read-only and uses anon/authenticated access under RLS, never a service-role key. No Supabase project, schema migration, region, or credentials are created/configured by this slice.
5. **Free enrollment and learning progress:** free-course enrollment, lesson view, completion, and resume position backed by the database.
6. **Basic quizzes:** multiple-choice questions, server-side scoring, attempts, and results.
7. **Quality and launch preparation:** access-control review, responsive/accessibility checks, production service and video cost review, logging, backup plan, and deployment documentation.

Do not create or connect a hosted Supabase project, choose a region, or apply the SQL until the user has reviewed and explicitly approved the database configuration and migration. Current approval covers auth UI and read-only live catalog queries only; it does not authorize project provisioning, schema application, profile/role administration, access-guard implementation, course authoring, or deployment.
