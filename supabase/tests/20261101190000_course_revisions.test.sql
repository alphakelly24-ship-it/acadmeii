-- Local-only pgTAP coverage for the staged course revision migration.
-- Run through the complete local suite; never link this test to hosted data.
-- Fixtures are isolated in this test transaction and rolled back at the end.

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
BEGIN;
SET LOCAL search_path = public, extensions;
SELECT no_plan();

CREATE TEMP TABLE revision_test_ids (
  name text PRIMARY KEY,
  id uuid NOT NULL
) ON COMMIT DROP;
GRANT SELECT, INSERT, UPDATE, DELETE ON revision_test_ids TO authenticated;

INSERT INTO auth.users (
  id, aud, "role", email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('11111111-1111-4111-8111-111111111111', 'authenticated', 'authenticated', 'student-one@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Student One"}'::jsonb, now(), now()),
  ('22222222-2222-4222-8222-222222222222', 'authenticated', 'authenticated', 'student-two@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Student Two"}'::jsonb, now(), now()),
  ('33333333-3333-4333-8333-333333333333', 'authenticated', 'authenticated', 'instructor-one@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Instructor One"}'::jsonb, now(), now()),
  ('44444444-4444-4444-8444-444444444444', 'authenticated', 'authenticated', 'instructor-two@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Instructor Two"}'::jsonb, now(), now()),
  ('55555555-5555-4555-8555-555555555555', 'authenticated', 'authenticated', 'admin-one@academi.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

SELECT private.bootstrap_first_admin('55555555-5555-4555-8555-555555555555');
INSERT INTO public.user_roles (user_id, role) VALUES
  ('11111111-1111-4111-8111-111111111111', 'student'),
  ('22222222-2222-4222-8222-222222222222', 'student'),
  ('33333333-3333-4333-8333-333333333333', 'student'),
  ('33333333-3333-4333-8333-333333333333', 'instructor'),
  ('44444444-4444-4444-8444-444444444444', 'student'),
  ('44444444-4444-4444-8444-444444444444', 'instructor');
INSERT INTO public.instructor_profiles (user_id, public_name) VALUES
  ('33333333-3333-4333-8333-333333333333', 'Instructor One'),
  ('44444444-4444-4444-8444-444444444444', 'Instructor Two');

INSERT INTO public.categories (id, name, slug) VALUES
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Product Design', 'product-design');

-- Live courses start pending_review and are published only by the test admin.
INSERT INTO public.courses (
  id, instructor_id, category_id, slug, title, description, status
) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'success-course', 'Published Course', 'Public approved version', 'pending_review'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'stale-course', 'Stale Course', 'Public stale baseline', 'pending_review'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'progress-course', 'Progress Course', 'Public progress baseline', 'pending_review'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'assessment-course', 'Assessment Course', 'Public assessment baseline', 'pending_review'),
  ('eeeeeeee-eeee-4eee-9eee-eeeeeeeeeeee', '33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'atomic-course', 'Atomic Course', 'Public atomic baseline', 'pending_review'),
  ('ffffffff-ffff-4fff-8fff-ffffffffffff', '33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'taken-slug', 'Slug Owner Course', 'Existing slug owner', 'pending_review'),
  ('99999999-9999-4999-8999-999999999999', '44444444-4444-4444-8444-444444444444', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'other-owner-course', 'Other Owner Course', 'Private to the other instructor', 'pending_review'),
  ('77777777-7777-4777-8777-777777777777', '33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'draft-course', 'Unpublished Draft', 'Not eligible for revisions', 'draft');

INSERT INTO public.course_outcomes (id, course_id, position, outcome) VALUES
  ('c1111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 1, 'Existing learning outcome');

INSERT INTO public.course_sections (id, course_id, title, position) VALUES
  ('f1111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Success Section', 1),
  ('f2222222-2222-4222-8222-222222222222', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Stale Section', 1),
  ('f3333333-3333-4333-8333-333333333333', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Progress Section', 1),
  ('f4444444-4444-4444-8444-444444444444', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Assessment Section', 1),
  ('f5555555-5555-4555-8555-555555555555', 'eeeeeeee-eeee-4eee-9eee-eeeeeeeeeeee', 'Atomic Section', 1),
  ('f6666666-6666-4666-8666-666666666666', '99999999-9999-4999-8999-999999999999', 'Other Owner Section', 1);

INSERT INTO public.lessons (id, course_id, section_id, title, content_type, position, duration_seconds) VALUES
  ('f3111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f1111111-1111-4111-8111-111111111111', 'Lesson to preserve', 'video', 1, 120),
  ('f3122222-2222-4222-8222-222222222222', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f1111111-1111-4111-8111-111111111111', 'Safe lesson to remove', 'reading', 2, NULL),
  ('f3211111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'f2222222-2222-4222-8222-222222222222', 'Stale lesson', 'video', 1, 90),
  ('f3311111-1111-4111-8111-111111111111', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'f3333333-3333-4333-8333-333333333333', 'Progress lesson', 'video', 1, 180),
  ('f3411111-1111-4111-8111-111111111111', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'f4444444-4444-4444-8444-444444444444', 'Assessment lesson', 'quiz', 1, NULL),
  ('f3511111-1111-4111-8111-111111111111', 'eeeeeeee-eeee-4eee-9eee-eeeeeeeeeeee', 'f5555555-5555-4555-8555-555555555555', 'Atomic lesson', 'video', 1, 240),
  ('f3611111-1111-4111-8111-111111111111', '99999999-9999-4999-8999-999999999999', 'f6666666-6666-4666-8666-666666666666', 'Other instructor lesson', 'video', 1, 60);

INSERT INTO public.enrollments (id, student_id, course_id, status) VALUES
  ('a1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'active');
INSERT INTO public.lesson_progress (enrollment_id, course_id, lesson_id, last_position_seconds) VALUES
  ('a1111111-1111-4111-8111-111111111111', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'f3311111-1111-4111-8111-111111111111', 45);
INSERT INTO public.assessments (id, course_id, lesson_id, title, status) VALUES
  ('d1111111-1111-4111-8111-111111111111', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'f3411111-1111-4111-8111-111111111111', 'Assessment that must remain', 'published');
INSERT INTO public.assessment_questions (id, assessment_id, position, prompt)
VALUES ('b3333333-3333-4333-8333-333333333333', 'd1111111-1111-4111-8111-111111111111', 1, 'Initial assessment question');
INSERT INTO public.assessment_options (id, question_id, position, option_text) VALUES
  ('c3333333-3333-4333-8333-333333333333', 'b3333333-3333-4333-8333-333333333333', 1, 'Correct option'),
  ('c4444444-4444-4444-8444-444444444444', 'b3333333-3333-4333-8333-333333333333', 2, 'Alternative option');
INSERT INTO private.assessment_answer_keys (question_id, correct_option_id)
VALUES ('b3333333-3333-4333-8333-333333333333', 'c3333333-3333-4333-8333-333333333333');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
UPDATE public.courses
SET status = 'published'
WHERE status = 'pending_review';
RESET ROLE;

-- The original first-submission/publication path is still usable.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
SELECT lives_ok(
  $$INSERT INTO public.courses (instructor_id, category_id, slug, title, status)
    VALUES ('33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'initial-submission-flow', 'Initial Submission Flow', 'draft')$$,
  'instructor can still create a draft course'
);
SELECT lives_ok(
  $$UPDATE public.courses SET status = 'pending_review' WHERE slug = 'initial-submission-flow'$$,
  'instructor can still submit a new course for initial review'
);
SELECT is(
  (SELECT status::text FROM public.courses WHERE slug = 'initial-submission-flow'),
  'pending_review',
  'initial course submission remains pending until an administrator acts'
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
SELECT lives_ok(
  $$UPDATE public.courses SET status = 'published' WHERE slug = 'initial-submission-flow'$$,
  'administrator can still approve and publish an initially submitted course'
);
SELECT is(
  (SELECT status::text FROM public.courses WHERE slug = 'initial-submission-flow'),
  'published',
  'initial submission workflow still reaches published'
);
RESET ROLE;

SELECT ok(
  (SELECT count(*) = 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'courses' AND column_name = 'content_version'),
  'courses has the additive stale-detection version column'
);
SELECT ok(to_regclass('public.course_revisions') IS NOT NULL, 'course revision headers are present');
SELECT ok(to_regclass('public.course_revision_sections') IS NOT NULL, 'staged sections are present');
SELECT ok(to_regclass('public.course_revision_lessons') IS NOT NULL, 'staged lessons are present');
SELECT ok(NOT has_table_privilege('anon', 'public.course_revisions', 'SELECT'), 'anonymous role has no revision-header read grant');
SELECT ok(NOT has_table_privilege('service_role', 'public.course_revisions', 'SELECT'), 'service role has no direct revision-header read grant');
SELECT ok(
  NOT has_table_privilege('anon', 'public.course_revision_outcomes', 'SELECT')
  AND NOT has_table_privilege('anon', 'public.course_revision_sections', 'SELECT')
  AND NOT has_table_privilege('anon', 'public.course_revision_lessons', 'SELECT'),
  'anonymous role has no direct staged-content table grants'
);
SELECT ok(
  NOT has_table_privilege('service_role', 'public.course_revision_outcomes', 'SELECT')
  AND NOT has_table_privilege('service_role', 'public.course_revision_sections', 'SELECT')
  AND NOT has_table_privilege('service_role', 'public.course_revision_lessons', 'SELECT'),
  'service role has no direct staged-content table grants'
);
SELECT ok(NOT has_function_privilege('anon', 'public.approve_course_revision(uuid)', 'EXECUTE'), 'anonymous role cannot call revision approval');
SELECT ok(NOT has_function_privilege('service_role', 'public.approve_course_revision(uuid)', 'EXECUTE'), 'service role cannot call revision approval');
SELECT ok(NOT has_function_privilege('anon', 'public.reject_course_revision(uuid,text)', 'EXECUTE'), 'anonymous role cannot call revision rejection');
SELECT ok(NOT has_function_privilege('service_role', 'public.reject_course_revision(uuid,text)', 'EXECUTE'), 'service role cannot call revision rejection');

-- Revisions may be created only by the owning instructor for a published course.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
INSERT INTO revision_test_ids (name, id)
SELECT 'success', public.create_course_revision('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
SELECT is(
  (SELECT status::text FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'success')),
  'draft',
  'owner creates an editable draft revision'
);
SELECT is(
  (SELECT count(*)::integer FROM public.course_revision_sections WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'success')),
  1,
  'revision snapshots the published section'
);
SELECT is(
  (SELECT count(*)::integer FROM public.course_revision_lessons WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'success')),
  2,
  'revision snapshots the published lessons'
);
SELECT is(
  (SELECT lesson_id FROM public.course_revision_lessons WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'success') AND lesson_id = 'f3111111-1111-4111-8111-111111111111'),
  'f3111111-1111-4111-8111-111111111111'::uuid,
  'snapshot keeps the original lesson ID'
);
SELECT is(
  (SELECT title FROM public.courses WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'Published Course',
  'creating a revision leaves the public course unchanged'
);
SELECT is(
  (SELECT title FROM public.lessons WHERE id = 'f3111111-1111-4111-8111-111111111111'),
  'Lesson to preserve',
  'creating a revision leaves the public curriculum unchanged'
);
SELECT throws_ok(
  $$SELECT public.create_course_revision('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  '55000', NULL,
  'a course cannot have two simultaneous active revisions'
);
SELECT throws_ok(
  $$SELECT public.create_course_revision('99999999-9999-4999-8999-999999999999')$$,
  '42501', NULL,
  'instructor cannot create another instructor''s revision'
);
SELECT throws_ok(
  $$SELECT public.create_course_revision('77777777-7777-4777-8777-777777777777')$$,
  '42501', NULL,
  'instructor cannot create a staged revision for an unpublished draft'
);

-- The owner may edit staged content, but not the published live rows.
SELECT lives_ok(
  $$UPDATE public.course_revisions SET title = 'Revised Success Course', description = 'Staged description' WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'success')$$,
  'owner can update draft revision metadata'
);
SELECT lives_ok(
  $$UPDATE public.course_revision_sections SET title = 'Revised Success Section' WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'success') AND section_id = 'f1111111-1111-4111-8111-111111111111'$$,
  'owner can update a staged section while the revision is draft'
);
SELECT lives_ok(
  $$UPDATE public.course_revision_lessons SET title = 'Revised success lesson' WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'success') AND lesson_id = 'f3111111-1111-4111-8111-111111111111'$$,
  'owner can update a staged lesson while the revision is draft'
);
DELETE FROM public.course_revision_lessons
WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'success')
  AND lesson_id = 'f3122222-2222-4222-8222-222222222222';
INSERT INTO public.course_revision_lessons (
  revision_id, lesson_id, section_id, title, summary, content_type, position, duration_seconds, is_preview
) VALUES (
  (SELECT id FROM revision_test_ids WHERE name = 'success'),
  'f3199999-9999-4999-8999-999999999999',
  'f1111111-1111-4111-8111-111111111111',
  'New staged lesson', 'Added in revision', 'reading', 3, NULL, false
);
INSERT INTO public.course_revision_outcomes (revision_id, outcome_id, position, outcome)
VALUES (
  (SELECT id FROM revision_test_ids WHERE name = 'success'),
  'c9999999-9999-4999-8999-999999999999', 2, 'New staged outcome'
);
SELECT lives_ok(
  $$UPDATE public.courses SET title = 'Instructor must not change live title' WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  'instructor live-course update is filtered by published-course RLS'
);
SELECT is(
  (SELECT title FROM public.courses WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'Published Course',
  'published course remains the public approved version during revision preparation'
);
SELECT lives_ok(
  $$UPDATE public.lessons SET title = 'Instructor must not change live lesson' WHERE id = 'f3111111-1111-4111-8111-111111111111'$$,
  'instructor live-curriculum update is filtered by published-course RLS'
);
SELECT is(
  (SELECT title FROM public.lessons WHERE id = 'f3111111-1111-4111-8111-111111111111'),
  'Lesson to preserve',
  'published lesson remains unchanged during revision preparation'
);
SELECT throws_ok(
  $$INSERT INTO public.course_sections (course_id, title, position) VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Unapproved live section', 8)$$,
  '42501', NULL,
  'instructor cannot add live curriculum directly to a published course'
);

-- Ordinary students have no staged-content visibility; anonymous users have no
-- table grant. The instructor's own snapshot remains readable.
SELECT is(
  (SELECT count(*)::integer FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'success')),
  1,
  'owning instructor can read their revision'
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
SELECT is((SELECT count(*)::integer FROM public.course_revisions), 0, 'ordinary student cannot see revision headers');
SELECT is((
  (SELECT count(*) FROM public.course_revision_outcomes)
  + (SELECT count(*) FROM public.course_revision_sections)
  + (SELECT count(*) FROM public.course_revision_lessons)
)::integer, 0, 'ordinary student cannot see staged outcomes, sections, or lessons');
SELECT is((SELECT count(*)::integer FROM public.course_revision_lessons), 0, 'ordinary student cannot see staged lesson content');
SELECT throws_ok(
  $$SELECT public.approve_course_revision((SELECT id FROM revision_test_ids WHERE name = 'success'))$$,
  '42501', NULL, 'ordinary student cannot approve a revision through the database function'
);
SELECT throws_ok(
  $$SELECT public.reject_course_revision((SELECT id FROM revision_test_ids WHERE name = 'success'), 'student rejection')$$,
  '42501', NULL, 'ordinary student cannot reject a revision through the database function'
);
RESET ROLE;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT throws_ok($$SELECT * FROM public.course_revisions$$, '42501', NULL, 'anonymous user cannot read staged revision headers');
SELECT throws_ok($$SELECT * FROM public.course_revision_outcomes$$, '42501', NULL, 'anonymous user cannot read staged outcomes');
SELECT throws_ok($$SELECT * FROM public.course_revision_sections$$, '42501', NULL, 'anonymous user cannot read staged sections');
SELECT throws_ok($$SELECT * FROM public.course_revision_lessons$$, '42501', NULL, 'anonymous user cannot read staged lesson content');
RESET ROLE;

-- Submitted revisions are immutable to instructors. Only an admin may make a
-- decision, through the guarded approval/rejection functions.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
SELECT lives_ok(
  $$SELECT public.submit_course_revision((SELECT id FROM revision_test_ids WHERE name = 'success'))$$,
  'owning instructor can submit the revision for review'
);
SELECT is(
  (SELECT status::text FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'success')),
  'pending_review',
  'submission changes the revision state to pending review'
);
SELECT lives_ok(
  $$UPDATE public.course_revisions SET title = 'Unauthorized submitted edit' WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'success')$$,
  'submitted header update is filtered by revision RLS'
);
SELECT lives_ok(
  $$UPDATE public.course_revision_lessons SET title = 'Unauthorized submitted lesson edit' WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'success') AND lesson_id = 'f3111111-1111-4111-8111-111111111111'$$,
  'submitted lesson update is filtered by revision RLS'
);
SELECT is(
  (SELECT title FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'success')),
  'Revised Success Course',
  'submitted metadata is immutable to the instructor'
);
SELECT is(
  (SELECT title FROM public.course_revision_lessons WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'success') AND lesson_id = 'f3111111-1111-4111-8111-111111111111'),
  'Revised success lesson',
  'submitted curriculum is immutable to the instructor'
);
SELECT throws_ok(
  $$UPDATE public.course_revisions SET status = 'approved' WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'success')$$,
  '42501', NULL,
  'instructor cannot change review state directly'
);
SELECT throws_ok(
  $$SELECT public.approve_course_revision((SELECT id FROM revision_test_ids WHERE name = 'success'))$$,
  '42501', NULL,
  'instructor cannot approve their own revision'
);
SELECT throws_ok(
  $$SELECT public.reject_course_revision((SELECT id FROM revision_test_ids WHERE name = 'success'), 'not permitted')$$,
  '42501', NULL,
  'instructor cannot reject a submitted revision'
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
SELECT throws_ok(
  $$UPDATE public.course_revisions SET status = 'approved' WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'success')$$,
  '42501', NULL,
  'administrator cannot bypass review RPCs with a direct state update'
);
SELECT is(
  public.approve_course_revision((SELECT id FROM revision_test_ids WHERE name = 'success')),
  'approved',
  'administrator atomically approves a valid submitted revision'
);
SELECT is(
  (SELECT status::text FROM public.courses WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'published',
  'revision approval keeps the course published'
);
SELECT is(
  (SELECT title FROM public.courses WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'Revised Success Course',
  'approved metadata is promoted to the live course'
);
SELECT is(
  (SELECT instructor_id FROM public.courses WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  '33333333-3333-4333-8333-333333333333'::uuid,
  'approval preserves the original instructor owner'
);
SELECT ok(
  (SELECT published_at IS NOT NULL FROM public.courses WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'approval keeps the public publication timestamp present'
);
SELECT is(
  (SELECT title FROM public.course_sections WHERE id = 'f1111111-1111-4111-8111-111111111111'),
  'Revised Success Section',
  'approval updates the original section while preserving its ID'
);
SELECT is(
  (SELECT title FROM public.lessons WHERE id = 'f3111111-1111-4111-8111-111111111111'),
  'Revised success lesson',
  'approval updates the original lesson while preserving its ID'
);
SELECT is(
  (SELECT count(*)::integer FROM public.lessons WHERE id = 'f3122222-2222-4222-8222-222222222222'),
  0,
  'approval removes a lesson only when it has no learner progress or assessment'
);
SELECT is(
  (SELECT count(*)::integer FROM public.lessons WHERE id = 'f3199999-9999-4999-8999-999999999999'),
  1,
  'approval adds a new staged lesson'
);
SELECT is(
  (SELECT count(*)::integer FROM public.course_outcomes WHERE id = 'c9999999-9999-4999-8999-999999999999'),
  1,
  'approval adds staged course outcomes'
);
SELECT is(
  (SELECT status::text FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'success')),
  'approved',
  'approved revision is retained as history'
);
SELECT is(
  (SELECT reviewed_by FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'success')),
  '55555555-5555-4555-8555-555555555555'::uuid,
  'revision decision records the approving administrator'
);
SELECT is(
  (SELECT count(*)::integer FROM public.lessons WHERE id = 'f3111111-1111-4111-8111-111111111111'),
  1,
  'approval preserves the original lesson ID'
);
RESET ROLE;

-- Stale revisions must be rejected rather than overwrite a newer administrator
-- edit. An admin edit to live curriculum advances the course version too.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
INSERT INTO revision_test_ids (name, id)
SELECT 'stale', public.create_course_revision('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
UPDATE public.course_revisions SET title = 'Instructor stale proposal'
WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'stale');
UPDATE public.course_revision_sections SET title = 'Instructor stale section'
WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'stale');
SELECT lives_ok(
  $$SELECT public.submit_course_revision((SELECT id FROM revision_test_ids WHERE name = 'stale'))$$,
  'stale candidate can be submitted but will be checked again at decision time'
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
UPDATE public.courses SET title = 'Admin latest title'
WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
UPDATE public.course_sections SET title = 'Admin latest section'
WHERE id = 'f2222222-2222-4222-8222-222222222222';
SELECT ok(
  (SELECT content_version > (SELECT base_content_version FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'stale'))
   FROM public.courses WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'course and curriculum edits advance the stale-detection version'
);
SELECT ok(
  public.approve_course_revision((SELECT id FROM revision_test_ids WHERE name = 'stale')) LIKE 'rejected:%stale%',
  'administrator approval safely rejects a stale revision with an explanatory result'
);
SELECT is(
  (SELECT title FROM public.courses WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'Admin latest title',
  'stale approval does not overwrite the administrator course edit'
);
SELECT is(
  (SELECT title FROM public.course_sections WHERE id = 'f2222222-2222-4222-8222-222222222222'),
  'Admin latest section',
  'stale approval does not overwrite the administrator curriculum edit'
);
SELECT is(
  (SELECT status::text FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'stale')),
  'rejected',
  'stale revision is recorded as rejected'
);
SELECT ok(
  (SELECT review_reason LIKE '%live course changed%' FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'stale')),
  'stale rejection reason is stored for the owner and administrator'
);
RESET ROLE;

-- Assessment descendants are versioned too, so edits to questions, options, or
-- answer keys after submission cannot evade stale-snapshot rejection.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
INSERT INTO revision_test_ids (name, id)
SELECT 'stale-assessment', public.create_course_revision('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
UPDATE public.course_revisions SET title = 'Assessment revision proposal'
WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'stale-assessment');
SELECT lives_ok(
  $$SELECT public.submit_course_revision((SELECT id FROM revision_test_ids WHERE name = 'stale-assessment'))$$,
  'assessment-content revision can be submitted before live descendants change'
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
SELECT set_config('test.revision_version', (
  SELECT content_version::text FROM public.courses WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
), true);
UPDATE public.assessment_questions SET prompt = 'Administrator changed the question'
WHERE id = 'b3333333-3333-4333-8333-333333333333';
SELECT ok(
  (SELECT content_version > current_setting('test.revision_version')::bigint FROM public.courses WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
  'assessment-question edits advance the live course content version'
);
SELECT set_config('test.revision_version', (
  SELECT content_version::text FROM public.courses WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
), true);
UPDATE public.assessment_options SET option_text = 'Administrator changed an option'
WHERE id = 'c4444444-4444-4444-8444-444444444444';
SELECT ok(
  (SELECT content_version > current_setting('test.revision_version')::bigint FROM public.courses WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
  'assessment-option edits advance the live course content version'
);
SELECT set_config('test.revision_version', (
  SELECT content_version::text FROM public.courses WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
), true);
SELECT lives_ok(
  $$SELECT public.set_assessment_answer_key('b3333333-3333-4333-8333-333333333333', 'c4444444-4444-4444-8444-444444444444')$$,
  'administrator can update the protected assessment answer key through its guarded function'
);
SELECT ok(
  (SELECT content_version > current_setting('test.revision_version')::bigint FROM public.courses WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
  'assessment answer-key edits advance the live course content version'
);
SELECT ok(
  public.approve_course_revision((SELECT id FROM revision_test_ids WHERE name = 'stale-assessment')) LIKE 'rejected:%stale%',
  'administrator approval rejects a revision made stale by assessment-descendant edits'
);
SELECT is(
  (SELECT title FROM public.courses WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
  'Assessment Course',
  'assessment-stale approval preserves the administrator-edited live course'
);
RESET ROLE;

-- A removed lesson with learner progress is explicitly rejected and remains
-- intact. The same function rejects a lesson with an associated assessment.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
INSERT INTO revision_test_ids (name, id)
SELECT 'progress', public.create_course_revision('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
UPDATE public.course_revisions SET title = 'Must not promote over progress'
WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'progress');
DELETE FROM public.course_revision_lessons
WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'progress')
  AND lesson_id = 'f3311111-1111-4111-8111-111111111111';
SELECT lives_ok(
  $$SELECT public.submit_course_revision((SELECT id FROM revision_test_ids WHERE name = 'progress'))$$,
  'revision that proposes lesson removal can be submitted for administrative review'
);
INSERT INTO revision_test_ids (name, id)
SELECT 'assessment', public.create_course_revision('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
UPDATE public.course_revisions SET title = 'Must not promote over assessment'
WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'assessment');
DELETE FROM public.course_revision_lessons
WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'assessment')
  AND lesson_id = 'f3411111-1111-4111-8111-111111111111';
SELECT lives_ok(
  $$SELECT public.submit_course_revision((SELECT id FROM revision_test_ids WHERE name = 'assessment'))$$,
  'revision proposing removal of an assessed lesson can be submitted for review'
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
SELECT ok(
  public.approve_course_revision((SELECT id FROM revision_test_ids WHERE name = 'progress')) LIKE '%learner progress exists%',
  'approval rejects lesson removal when learner progress exists and reports why'
);
SELECT is(
  (SELECT title FROM public.courses WHERE id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
  'Progress Course',
  'unsafe progress revision makes no partial course changes'
);
SELECT is(
  (SELECT count(*)::integer FROM public.lessons WHERE id = 'f3311111-1111-4111-8111-111111111111'),
  1,
  'lesson with learner progress is never deleted'
);
SELECT is(
  (SELECT count(*)::integer FROM public.lesson_progress WHERE lesson_id = 'f3311111-1111-4111-8111-111111111111'),
  1,
  'learner progress remains attached to the original lesson ID'
);
SELECT ok(
  (SELECT review_reason LIKE '%f3311111-1111-4111-8111-111111111111%' FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'progress')),
  'unsafe-removal rejection reports the specific lesson ID'
);
SELECT ok(
  public.approve_course_revision((SELECT id FROM revision_test_ids WHERE name = 'assessment')) LIKE '%associated assessment exists%',
  'approval rejects lesson removal when an associated assessment exists and reports why'
);
SELECT is(
  (SELECT title FROM public.courses WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
  'Assessment Course',
  'assessment-protected revision makes no partial course changes'
);
SELECT is(
  (SELECT count(*)::integer FROM public.lessons WHERE id = 'f3411111-1111-4111-8111-111111111111'),
  1,
  'lesson associated with an assessment is never deleted'
);
SELECT is(
  (SELECT count(*)::integer FROM public.assessments WHERE id = 'd1111111-1111-4111-8111-111111111111'),
  1,
  'assessment remains attached when its lesson removal is rejected'
);
RESET ROLE;

-- Inject a test-only failure after course metadata, outcomes and section writes
-- have started. A raised SQL error must roll the entire approval statement back.
CREATE FUNCTION private.test_fail_atomic_revision_lesson()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.title = 'force atomic rollback' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'forced test failure after staged course changes';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER test_fail_atomic_revision_lesson
BEFORE INSERT ON public.lessons
FOR EACH ROW EXECUTE FUNCTION private.test_fail_atomic_revision_lesson();

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
INSERT INTO revision_test_ids (name, id)
SELECT 'atomic', public.create_course_revision('eeeeeeee-eeee-4eee-9eee-eeeeeeeeeeee');
UPDATE public.course_revisions SET title = 'Atomic promoted title'
WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'atomic');
UPDATE public.course_revision_sections SET title = 'Atomic promoted section'
WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'atomic');
INSERT INTO public.course_revision_outcomes (revision_id, outcome_id, position, outcome)
VALUES ((SELECT id FROM revision_test_ids WHERE name = 'atomic'), 'c8888888-8888-4888-8888-888888888888', 1, 'Atomic new outcome');
INSERT INTO public.course_revision_lessons (
  revision_id, lesson_id, section_id, title, content_type, position
) VALUES (
  (SELECT id FROM revision_test_ids WHERE name = 'atomic'),
  'f3599999-9999-4999-8999-999999999999',
  'f5555555-5555-4555-8555-555555555555',
  'force atomic rollback', 'reading', 2
);
SELECT lives_ok(
  $$SELECT public.submit_course_revision((SELECT id FROM revision_test_ids WHERE name = 'atomic'))$$,
  'atomicity-test revision is submitted'
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
SELECT throws_ok(
  $$SELECT public.approve_course_revision((SELECT id FROM revision_test_ids WHERE name = 'atomic'))$$,
  'P0001', NULL,
  'unexpected promotion error aborts the complete approval statement'
);
SELECT is(
  (SELECT title FROM public.courses WHERE id = 'eeeeeeee-eeee-4eee-9eee-eeeeeeeeeeee'),
  'Atomic Course',
  'failed approval rolls back course metadata changes'
);
SELECT is(
  (SELECT title FROM public.course_sections WHERE id = 'f5555555-5555-4555-8555-555555555555'),
  'Atomic Section',
  'failed approval rolls back section changes made earlier in the transaction'
);
SELECT is(
  (SELECT count(*)::integer FROM public.course_outcomes WHERE id = 'c8888888-8888-4888-8888-888888888888'),
  0,
  'failed approval rolls back outcome insertion made earlier in the transaction'
);
SELECT is(
  (SELECT count(*)::integer FROM public.lessons WHERE id = 'f3599999-9999-4999-8999-999999999999'),
  0,
  'failed approval does not leave a partial lesson insertion'
);
SELECT is(
  (SELECT status::text FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'atomic')),
  'pending_review',
  'failed approval leaves the revision pending for an administrator decision'
);
RESET ROLE;
DROP TRIGGER test_fail_atomic_revision_lesson ON public.lessons;
DROP FUNCTION private.test_fail_atomic_revision_lesson();
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
SELECT is(
  public.approve_course_revision((SELECT id FROM revision_test_ids WHERE name = 'atomic')),
  'approved',
  'administrator can retry after a transient promotion error is resolved'
);
SELECT is(
  (SELECT title FROM public.courses WHERE id = 'eeeeeeee-eeee-4eee-9eee-eeeeeeeeeeee'),
  'Atomic promoted title',
  'successful retry promotes all staged course metadata'
);
SELECT is(
  (SELECT title FROM public.course_sections WHERE id = 'f5555555-5555-4555-8555-555555555555'),
  'Atomic promoted section',
  'successful retry promotes the section snapshot'
);
SELECT is(
  (SELECT count(*)::integer FROM public.lessons WHERE id = 'f3511111-1111-4111-8111-111111111111'),
  1,
  'successful promotion preserves the existing lesson ID'
);
SELECT is(
  (SELECT count(*)::integer FROM public.lessons WHERE id = 'f3599999-9999-4999-8999-999999999999'),
  1,
  'successful promotion adds the staged lesson after the failed attempt'
);
SELECT is(
  (SELECT count(*)::integer FROM public.course_outcomes WHERE id = 'c8888888-8888-4888-8888-888888888888'),
  1,
  'successful promotion adds the staged outcome after the failed attempt'
);

-- Conflicting and forged IDs are rejected as domain failures. Admins may also
-- reject manually; a rejection releases the one-active-revision slot.
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
INSERT INTO revision_test_ids (name, id)
SELECT 'slug-conflict', public.create_course_revision('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
UPDATE public.course_revisions SET slug = 'taken-slug'
WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'slug-conflict');
SELECT lives_ok(
  $$SELECT public.submit_course_revision((SELECT id FROM revision_test_ids WHERE name = 'slug-conflict'))$$,
  'slug-conflicting revision can be submitted for admin review'
);
SELECT throws_ok(
  $$SELECT public.approve_course_revision((SELECT id FROM revision_test_ids WHERE name = 'slug-conflict'))$$,
  '42501', NULL,
  'instructor still cannot approve a conflicting revision'
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
SELECT ok(
  public.approve_course_revision((SELECT id FROM revision_test_ids WHERE name = 'slug-conflict')) LIKE '%slug is already in use%',
  'administrator rejects a slug conflict with an explanatory reason'
);
SELECT is(
  (SELECT slug FROM public.courses WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'success-course',
  'rejected slug conflict leaves the public slug unchanged'
);
SELECT throws_ok(
  $$SELECT public.reject_course_revision((SELECT id FROM revision_test_ids WHERE name = 'atomic'), 'manual rejection test')$$,
  '55000', NULL,
  'administrator cannot reject a revision that has already been approved'
);
RESET ROLE;

-- A separate pending revision exercises the explicit administrator rejection
-- transition and confirms that the reason and decision actor are stored.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
INSERT INTO revision_test_ids (name, id)
SELECT 'manual-reject', public.create_course_revision('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
SELECT lives_ok(
  $$SELECT public.submit_course_revision((SELECT id FROM revision_test_ids WHERE name = 'manual-reject'))$$,
  'instructor can submit a later revision after an earlier revision was rejected'
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
SELECT lives_ok(
  $$SELECT public.reject_course_revision((SELECT id FROM revision_test_ids WHERE name = 'manual-reject'), 'Please clarify the revised course outline.')$$,
  'administrator can explicitly reject a pending revision'
);
SELECT is(
  (SELECT status::text FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'manual-reject')),
  'rejected',
  'administrator rejection updates revision state'
);
SELECT is(
  (SELECT review_reason FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'manual-reject')),
  'Please clarify the revised course outline.',
  'administrator rejection stores the review reason'
);
SELECT is(
  (SELECT reviewed_by FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'manual-reject')),
  '55555555-5555-4555-8555-555555555555'::uuid,
  'administrator rejection records the decision maker'
);
RESET ROLE;

-- A second instructor may manage their own revisions but cannot read or alter
-- the first instructor's staged records.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
SELECT set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-8444-444444444444","role":"authenticated"}', true);
INSERT INTO revision_test_ids (name, id)
SELECT 'other-owner', public.create_course_revision('99999999-9999-4999-8999-999999999999');
SELECT is(
  (SELECT count(*)::integer FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'manual-reject')),
  0,
  'another instructor cannot see the first instructor''s revision'
);
SELECT throws_ok(
  $$SELECT public.submit_course_revision((SELECT id FROM revision_test_ids WHERE name = 'manual-reject'))$$,
  '42501', NULL,
  'another instructor cannot submit an owner''s revision'
);
UPDATE public.course_revision_lessons
SET title = 'Other instructor attempted edit'
WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'manual-reject')
  AND lesson_id = 'f3111111-1111-4111-8111-111111111111';
SELECT is(
  (SELECT count(*)::integer FROM public.course_revision_lessons WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'manual-reject')),
  0,
  'another instructor cannot read the owner''s staged lessons'
);
SELECT lives_ok(
  $$SELECT public.cancel_course_revision((SELECT id FROM revision_test_ids WHERE name = 'other-owner'))$$,
  'owner can cancel their own draft and release the active revision slot'
);
SELECT is(
  (SELECT status::text FROM public.course_revisions WHERE id = (SELECT id FROM revision_test_ids WHERE name = 'other-owner')),
  'cancelled',
  'cancelled draft remains in revision history'
);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
SELECT is(
  (SELECT title FROM public.course_revision_lessons WHERE revision_id = (SELECT id FROM revision_test_ids WHERE name = 'manual-reject') AND lesson_id = 'f3111111-1111-4111-8111-111111111111'),
  'Revised success lesson',
  'cross-instructor update attempt did not alter the staged lesson'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
