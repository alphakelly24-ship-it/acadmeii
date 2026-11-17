-- Local-only pgTAP tests for 20261025015300_academi_lms_schema.sql.
-- Requires an initialized local Supabase CLI/Docker stack. Run `supabase start`
-- then `supabase test db`; never link this test run to hosted project data.
-- All fixture rows are rolled back at the end of this test file.

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
BEGIN;
SET LOCAL search_path = public, extensions;
SELECT no_plan();

-- Stable test identities. These are local fixtures, not real users.
INSERT INTO auth.users (
  id, aud, "role", email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('11111111-1111-4111-8111-111111111111', 'authenticated', 'authenticated', 'student-one@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Student One"}'::jsonb, now(), now()),
  ('22222222-2222-4222-8222-222222222222', 'authenticated', 'authenticated', 'student-two@academi.test', '', now(), '{}'::jsonb, '{"full_name":"Student Two"}'::jsonb, now(), now()),
  ('33333333-3333-4333-8333-333333333333', 'authenticated', 'authenticated', 'instructor-one@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Instructor One"}'::jsonb, now(), now()),
  ('44444444-4444-4444-8444-444444444444', 'authenticated', 'authenticated', 'instructor-two@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Instructor Two"}'::jsonb, now(), now()),
  ('55555555-5555-4555-8555-555555555555', 'authenticated', 'authenticated', 'admin-one@academi.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

SELECT is((SELECT count(*)::integer FROM public.profiles), 5, 'auth.users inserts automatically create matching profile rows');
SELECT is((SELECT display_name FROM public.profiles WHERE id = '11111111-1111-4111-8111-111111111111'), 'Student One', 'profile uses the supplied display_name metadata');
SELECT is((SELECT display_name FROM public.profiles WHERE id = '22222222-2222-4222-8222-222222222222'), 'Student Two', 'profile falls back to full_name metadata');
SELECT is((SELECT display_name FROM public.profiles WHERE id = '55555555-5555-4555-8555-555555555555'), 'admin-one', 'profile falls back to the email local part');
SELECT lives_ok(
  $$SELECT private.bootstrap_first_admin('55555555-5555-4555-8555-555555555555')$$,
  'trusted database owner can bootstrap the first administrator'
);
SELECT is((SELECT count(*)::integer FROM public.user_roles WHERE role = 'admin'::public.app_role), 1, 'bootstrap assigns exactly one initial admin role');
SELECT throws_ok(
  $$SELECT private.bootstrap_first_admin('44444444-4444-4444-8444-444444444444')$$,
  '42501', NULL, 'bootstrap refuses to create a second initial administrator'
);
SELECT ok(NOT has_function_privilege('anon', 'private.bootstrap_first_admin(uuid)', 'EXECUTE'), 'anonymous API role cannot execute first-admin bootstrap');
SELECT ok(NOT has_function_privilege('authenticated', 'private.bootstrap_first_admin(uuid)', 'EXECUTE'), 'authenticated users cannot execute first-admin bootstrap');
SELECT ok(NOT has_function_privilege('service_role', 'private.bootstrap_first_admin(uuid)', 'EXECUTE'), 'service role cannot execute first-admin bootstrap');

-- The instructor also has the student role, proving that roles can coexist.
INSERT INTO public.user_roles (user_id, role) VALUES
  ('11111111-1111-4111-8111-111111111111', 'student'),
  ('22222222-2222-4222-8222-222222222222', 'student'),
  ('33333333-3333-4333-8333-333333333333', 'student'),
  ('33333333-3333-4333-8333-333333333333', 'instructor'),
  ('44444444-4444-4444-8444-444444444444', 'instructor');

INSERT INTO public.instructor_profiles (user_id, public_name) VALUES
  ('33333333-3333-4333-8333-333333333333', 'Instructor One'),
  ('44444444-4444-4444-8444-444444444444', 'Instructor Two');

INSERT INTO public.categories (id, name, slug) VALUES
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Product Design', 'product-design');

-- The fixtures below include admin-created pending submissions. Set the
-- simulated authenticated actor before course INSERT triggers run.
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);

-- Course A is first submitted for review and then published by the test admin.
INSERT INTO public.courses (
  id, instructor_id, category_id, slug, title, description, status
) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'published-course', 'Published Course', 'Public catalog content', 'pending_review'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'instructor-draft', 'Instructor Draft', 'Private draft content', 'draft'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '44444444-4444-4444-8444-444444444444', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'other-instructor-draft', 'Other Instructor Draft', 'Other private draft', 'draft'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'awaiting-review', 'Awaiting Review', 'Pending publication', 'pending_review');

SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
UPDATE public.courses
SET status = 'published', published_at = now()
WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
-- Seed fixtures as the trusted test admin so the later trigger backstop sees
-- an authorized actor even though the SQL connection is the database owner.
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);

INSERT INTO public.course_sections (id, course_id, title, position) VALUES
  ('f1111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Published Section', 1),
  ('f2222222-2222-4222-8222-222222222222', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Draft Section', 1);

INSERT INTO public.lessons (id, course_id, section_id, title, content_type, position, duration_seconds)
VALUES
  ('f3111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f1111111-1111-4111-8111-111111111111', 'Published Lesson', 'video', 1, 120),
  ('f3222222-2222-4222-8222-222222222222', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'f2222222-2222-4222-8222-222222222222', 'Draft Lesson', 'reading', 1, NULL);

INSERT INTO public.enrollments (id, student_id, course_id, status) VALUES
  ('a1111111-1111-4111-8111-111111111111', '11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'active'),
  ('a2222222-2222-4222-8222-222222222222', '22222222-2222-4222-8222-222222222222', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'active');

INSERT INTO public.lesson_progress (enrollment_id, course_id, lesson_id, last_position_seconds)
VALUES ('a2222222-2222-4222-8222-222222222222', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f3111111-1111-4111-8111-111111111111', 15);

INSERT INTO public.assessments (id, course_id, lesson_id, title, status) VALUES
  ('a3333333-3333-4333-8333-333333333333', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f3111111-1111-4111-8111-111111111111', 'Published Quiz', 'published'),
  ('a4444444-4444-4444-8444-444444444444', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'f3222222-2222-4222-8222-222222222222', 'Draft Quiz', 'draft');

INSERT INTO public.assessment_questions (id, assessment_id, position, prompt) VALUES
  ('b1111111-1111-4111-8111-111111111111', 'a3333333-3333-4333-8333-333333333333', 1, 'Published quiz question'),
  ('b2222222-2222-4222-8222-222222222222', 'a4444444-4444-4444-8444-444444444444', 1, 'Draft quiz question');

INSERT INTO public.assessment_options (id, question_id, position, option_text) VALUES
  ('c1111111-1111-4111-8111-111111111111', 'b1111111-1111-4111-8111-111111111111', 1, 'Correct public option'),
  ('c1222222-2222-4222-8222-222222222222', 'b1111111-1111-4111-8111-111111111111', 2, 'Incorrect public option'),
  ('c2111111-1111-4111-8111-111111111111', 'b2222222-2222-4222-8222-222222222222', 1, 'Draft correct option'),
  ('c2222222-2222-4222-8222-222222222222', 'b2222222-2222-4222-8222-222222222222', 2, 'Draft incorrect option');

INSERT INTO private.assessment_answer_keys (question_id, correct_option_id) VALUES
  ('b1111111-1111-4111-8111-111111111111', 'c1111111-1111-4111-8111-111111111111'),
  ('b2222222-2222-4222-8222-222222222222', 'c2111111-1111-4111-8111-111111111111');

INSERT INTO public.assessment_attempts (
  id, assessment_id, student_id, enrollment_id, course_id,
  attempt_number, status, submitted_at, score_percent, passed
) VALUES
  ('d1111111-1111-4111-8111-111111111111', 'a3333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'a1111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 1, 'submitted', now(), 90.00, true),
  ('d2222222-2222-4222-8222-222222222222', 'a3333333-3333-4333-8333-333333333333', '22222222-2222-4222-8222-222222222222', 'a2222222-2222-4222-8222-222222222222', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 1, 'submitted', now(), 40.00, false);

INSERT INTO public.assessment_responses (
  attempt_id, assessment_id, question_id, selected_option_id
) VALUES
  ('d1111111-1111-4111-8111-111111111111', 'a3333333-3333-4333-8333-333333333333', 'b1111111-1111-4111-8111-111111111111', 'c1111111-1111-4111-8111-111111111111'),
  ('d2222222-2222-4222-8222-222222222222', 'a3333333-3333-4333-8333-333333333333', 'b1111111-1111-4111-8111-111111111111', 'c1222222-2222-4222-8222-222222222222');

-- Anonymous users: published catalog metadata is readable, private data is not.
SET LOCAL ROLE anon;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT is((SELECT count(*)::integer FROM public.categories), 1, 'anonymous visitors can read categories');
SELECT is((SELECT count(*)::integer FROM public.courses), 1, 'anonymous visitors see only published courses');
SELECT throws_ok($$SELECT * FROM public.profiles$$, '42501', NULL, 'anonymous visitors cannot read learner profiles');
SELECT throws_ok(
  $$INSERT INTO public.courses (instructor_id, category_id, slug, title) VALUES ('33333333-3333-4333-8333-333333333333', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'anon-course', 'Unauthorized')$$,
  '42501', NULL, 'anonymous visitors cannot create courses'
);
RESET ROLE;

-- Instructors: owners can manage their courses, but cannot see another
-- instructor's drafts or publish a course themselves.
SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
SELECT is((SELECT count(*)::integer FROM public.user_roles WHERE user_id = auth.uid()), 2, 'one account may hold both student and instructor roles');
SELECT is((SELECT count(*)::integer FROM public.courses WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 1, 'instructor can read their own draft');
SELECT is((SELECT count(*)::integer FROM public.courses WHERE id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'), 0, 'instructor cannot read another instructor draft');
SELECT lives_ok(
  $$UPDATE public.courses SET title = 'Updated Draft' WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$$,
  'instructor can update their own course'
);
SELECT throws_ok(
  $$UPDATE public.courses SET instructor_id = '44444444-4444-4444-8444-444444444444' WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$$,
  '42501', NULL, 'instructor cannot transfer primary course ownership directly'
);
SELECT throws_ok(
  $$UPDATE public.courses SET status = 'published' WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$$,
  '42501', NULL, 'instructor cannot publish a course'
);
SELECT is((SELECT status::text FROM public.courses WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 'draft', 'failed publication leaves the course unpublished');
SELECT lives_ok(
  $$UPDATE public.courses SET status = 'published' WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  'instructor cannot approve a pending course; RLS filters the update'
);
SELECT is((SELECT status::text FROM public.courses WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'), 'pending_review', 'non-admin publication attempt leaves course pending review');
SELECT throws_ok(
  $$INSERT INTO public.user_roles (user_id, role) VALUES ('33333333-3333-4333-8333-333333333333', 'admin')$$,
  '42501', NULL, 'instructor cannot write role rows directly'
);
SELECT throws_ok(
  $$SELECT public.grant_role_to_user('22222222-2222-4222-8222-222222222222', 'instructor'::public.app_role)$$,
  '42501', NULL, 'instructor cannot grant roles to another account'
);
SELECT throws_ok(
  $$SELECT public.grant_role_to_user('33333333-3333-4333-8333-333333333333', 'admin'::public.app_role)$$,
  '42501', NULL, 'instructor cannot grant an administrator role to themselves'
);
SELECT lives_ok(
  $$SELECT public.set_assessment_answer_key('b2222222-2222-4222-8222-222222222222', 'c2111111-1111-4111-8111-111111111111')$$,
  'instructor may set an answer key for their own draft assessment through the guarded function'
);
SELECT throws_ok(
  $$SELECT question_id FROM private.assessment_answer_keys$$,
  '42501', NULL, 'instructor cannot read answer keys directly'
);
UPDATE public.assessment_questions
SET prompt = 'Unauthorized question change'
WHERE id = 'b1111111-1111-4111-8111-111111111111';
SELECT is((SELECT prompt FROM public.assessment_questions WHERE id = 'b1111111-1111-4111-8111-111111111111'), 'Published quiz question', 'instructor cannot change a published question');
DELETE FROM public.assessment_options
WHERE id = 'c1111111-1111-4111-8111-111111111111';
SELECT is((SELECT count(*)::integer FROM public.assessment_options WHERE question_id = 'b1111111-1111-4111-8111-111111111111'), 2, 'instructor cannot delete an option from a published assessment');
UPDATE public.assessments
SET status = 'draft'
WHERE id = 'a3333333-3333-4333-8333-333333333333';
SELECT is((SELECT status::text FROM public.assessments WHERE id = 'a3333333-3333-4333-8333-333333333333'), 'published', 'instructor cannot reopen a published assessment');
SELECT throws_ok(
  $$SELECT public.set_assessment_answer_key('b1111111-1111-4111-8111-111111111111', 'c1222222-2222-4222-8222-222222222222')$$,
  '42501', NULL, 'instructor cannot replace a published assessment answer key'
);
SELECT is((SELECT count(*)::integer FROM public.assessment_attempts), 2, 'course owner can review attempts for their course');
RESET ROLE;

-- Administrator: can approve a course only after it is pending review and can
-- assign another account a role, but cannot grant themselves a new role.
SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT set_config('request.jwt.claims', '{"sub":"55555555-5555-4555-8555-555555555555","role":"authenticated"}', true);
SELECT lives_ok(
  $$UPDATE public.courses SET status = 'published' WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  'administrator can approve a course that is pending review'
);
SELECT is((SELECT status::text FROM public.courses WHERE id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'), 'published', 'approved course is published');
SELECT throws_ok(
  $$UPDATE public.courses SET status = 'published' WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$$,
  '42501', NULL, 'administrator cannot publish a draft that was not submitted for review'
);
SELECT lives_ok(
  $$UPDATE public.assessment_questions SET prompt = 'Admin-reviewed question' WHERE id = 'b1111111-1111-4111-8111-111111111111'$$,
  'administrator can manage published assessment content'
);
SELECT is((SELECT prompt FROM public.assessment_questions WHERE id = 'b1111111-1111-4111-8111-111111111111'), 'Admin-reviewed question', 'administrator update is recorded');
SELECT lives_ok(
  $$SELECT public.grant_role_to_user('22222222-2222-4222-8222-222222222222', 'instructor'::public.app_role)$$,
  'administrator can grant an instructor role to another account'
);
SELECT throws_ok(
  $$SELECT public.grant_role_to_user('55555555-5555-4555-8555-555555555555', 'instructor'::public.app_role)$$,
  '42501', NULL, 'administrator cannot grant a role to themselves'
);
SELECT throws_ok(
  $$SELECT public.revoke_role_from_user('55555555-5555-4555-8555-555555555555', 'admin'::public.app_role)$$,
  '42501', NULL, 'administrator cannot revoke their own role'
);
SELECT lives_ok(
  $$INSERT INTO public.enrollments (student_id, course_id, status) VALUES ('22222222-2222-4222-8222-222222222222', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'active')$$,
  'administrator can create an enrollment for a learner'
);
SELECT lives_ok(
  $$UPDATE public.enrollments SET status = 'completed', completed_at = now() WHERE student_id = '22222222-2222-4222-8222-222222222222' AND course_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  'administrator can correct enrollment status'
);
RESET ROLE;

-- Student: can see only their own learning rows, may save a resume position,
-- but cannot enroll themselves, mark completion, write quiz scores, or set keys.
SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
SELECT is((SELECT count(*)::integer FROM public.enrollments), 1, 'student can read only their own enrollment');
SELECT throws_ok(
  $$INSERT INTO public.enrollments (student_id, course_id) VALUES ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$,
  '42501', NULL, 'student cannot create an enrollment directly'
);
SELECT lives_ok(
  $$UPDATE public.enrollments SET status = 'completed', completed_at = now() WHERE id = 'a1111111-1111-4111-8111-111111111111'$$,
  'student enrollment update is filtered by RLS'
);
SELECT is((SELECT status::text FROM public.enrollments WHERE id = 'a1111111-1111-4111-8111-111111111111'), 'active', 'student cannot change enrollment status');
SELECT lives_ok(
  $$INSERT INTO public.lesson_progress (enrollment_id, course_id, lesson_id, last_position_seconds) VALUES ('a1111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'f3111111-1111-4111-8111-111111111111', 30)$$,
  'student can save resume position for their active enrollment'
);
SELECT throws_ok(
  $$UPDATE public.lesson_progress SET completed_at = now() WHERE enrollment_id = 'a1111111-1111-4111-8111-111111111111' AND lesson_id = 'f3111111-1111-4111-8111-111111111111'$$,
  '42501', NULL, 'student cannot mark a lesson complete directly'
);
SELECT is((SELECT count(*)::integer FROM public.lesson_progress), 1, 'student cannot read another learner progress row');
SELECT is((SELECT count(*)::integer FROM public.assessment_attempts), 1, 'student can read only their own quiz attempt');
SELECT is((SELECT count(*)::integer FROM public.assessment_responses), 1, 'student can read only their own response');
SELECT throws_ok(
  $$INSERT INTO public.assessment_attempts (assessment_id, student_id, enrollment_id, course_id, attempt_number) VALUES ('a3333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'a1111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 2)$$,
  '42501', NULL, 'student cannot create quiz attempts directly'
);
SELECT throws_ok(
  $$UPDATE public.assessment_attempts SET score_percent = 100, passed = true WHERE id = 'd1111111-1111-4111-8111-111111111111'$$,
  '42501', NULL, 'student cannot change quiz score or pass result'
);
SELECT throws_ok(
  $$INSERT INTO public.assessment_responses (attempt_id, assessment_id, question_id, selected_option_id) VALUES ('d1111111-1111-4111-8111-111111111111', 'a3333333-3333-4333-8333-333333333333', 'b1111111-1111-4111-8111-111111111111', 'c1222222-2222-4222-8222-222222222222')$$,
  '42501', NULL, 'student cannot write quiz responses directly'
);
SELECT throws_ok(
  $$SELECT question_id FROM private.assessment_answer_keys$$,
  '42501', NULL, 'student cannot read answer keys directly'
);
SELECT throws_ok(
  $$SELECT public.set_assessment_answer_key('b1111111-1111-4111-8111-111111111111', 'c1222222-2222-4222-8222-222222222222')$$,
  '42501', NULL, 'student cannot change an answer key'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
