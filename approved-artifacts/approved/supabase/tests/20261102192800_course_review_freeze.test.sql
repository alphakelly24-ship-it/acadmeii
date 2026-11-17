-- Local-only pgTAP coverage for the lock-order/review-freeze migration.
-- All fixtures are transaction-scoped and rolled back at the end of this file.

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
BEGIN;
SET LOCAL search_path = public, extensions;
SELECT no_plan();

INSERT INTO auth.users (
  id, aud, "role", email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('12111111-1111-4111-8111-111111111111', 'authenticated', 'authenticated', 'review-owner@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Review Owner"}'::jsonb, now(), now()),
  ('12222222-2222-4222-8222-222222222222', 'authenticated', 'authenticated', 'review-other-instructor@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Other Instructor"}'::jsonb, now(), now()),
  ('12333333-3333-4333-8333-333333333333', 'authenticated', 'authenticated', 'review-student@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Review Student"}'::jsonb, now(), now()),
  ('12444444-4444-4444-8444-444444444444', 'authenticated', 'authenticated', 'review-admin@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Review Admin"}'::jsonb, now(), now());

SELECT lives_ok(
  $$SELECT private.bootstrap_first_admin('12444444-4444-4444-8444-444444444444')$$,
  'trusted local fixture provisions the test administrator'
);
INSERT INTO public.user_roles (user_id, role) VALUES
  ('12111111-1111-4111-8111-111111111111', 'student'),
  ('12111111-1111-4111-8111-111111111111', 'instructor'),
  ('12222222-2222-4222-8222-222222222222', 'student'),
  ('12222222-2222-4222-8222-222222222222', 'instructor'),
  ('12333333-3333-4333-8333-333333333333', 'student');
INSERT INTO public.instructor_profiles (user_id, public_name) VALUES
  ('12111111-1111-4111-8111-111111111111', 'Review Owner'),
  ('12222222-2222-4222-8222-222222222222', 'Other Instructor');

SELECT set_config('request.jwt.claim.sub', '12444444-4444-4444-8444-444444444444', true);
SELECT set_config('request.jwt.claims', '{"sub":"12444444-4444-4444-8444-444444444444","role":"authenticated"}', true);
INSERT INTO public.categories (id, name, slug)
VALUES ('12eeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'Review Test', 'review-test');
INSERT INTO public.courses (
  id, instructor_id, category_id, slug, title, description, status
) VALUES (
  '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '12111111-1111-4111-8111-111111111111',
  '12eeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  'review-freeze-test', 'Original draft title', 'Original description', 'draft'
);
INSERT INTO public.course_outcomes (id, course_id, position, outcome)
VALUES ('12bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 1, 'Original outcome');
INSERT INTO public.course_sections (id, course_id, title, position)
VALUES ('12cccccc-cccc-4ccc-8ccc-cccccccccccc', '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Original section', 1);
INSERT INTO public.lessons (id, course_id, section_id, title, content_type, position, duration_seconds)
VALUES ('12dddddd-dddd-4ddd-8ddd-dddddddddddd', '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '12cccccc-cccc-4ccc-8ccc-cccccccccccc', 'Original lesson', 'reading', 1, NULL);
INSERT INTO public.assessments (id, course_id, lesson_id, title, status)
VALUES ('12eeeeee-eeee-4eee-9eee-eeeeeeeeeeee', '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '12dddddd-dddd-4ddd-8ddd-dddddddddddd', 'Original assessment', 'draft');
INSERT INTO public.assessment_questions (id, assessment_id, position, prompt)
VALUES ('12ffffff-ffff-4fff-8fff-ffffffffffff', '12eeeeee-eeee-4eee-9eee-eeeeeeeeeeee', 1, 'Original question');
INSERT INTO public.assessment_options (id, question_id, position, option_text) VALUES
  ('13aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '12ffffff-ffff-4fff-8fff-ffffffffffff', 1, 'Original answer'),
  ('13bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '12ffffff-ffff-4fff-8fff-ffffffffffff', 2, 'Alternative answer');
INSERT INTO private.assessment_answer_keys (question_id, correct_option_id)
VALUES ('12ffffff-ffff-4fff-8fff-ffffffffffff', '13aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '12111111-1111-4111-8111-111111111111', true);
SELECT set_config('request.jwt.claims', '{"sub":"12111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
SELECT throws_ok(
  $$INSERT INTO public.courses (instructor_id, category_id, slug, title, status) VALUES ('12111111-1111-4111-8111-111111111111', '12eeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'direct-pending-insert', 'Direct pending insert', 'pending_review')$$,
  '42501', NULL, 'owner cannot create a pending course directly instead of submitting a draft'
);
SELECT throws_ok(
  $$UPDATE public.courses SET status = 'pending_review' WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  '42501', NULL, 'owner must use the submission RPC rather than directly changing draft status'
);
SELECT lives_ok(
  $$SELECT public.submit_course_for_review('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  'owning instructor can submit a draft for initial review'
);
SELECT is(
  (SELECT status::text FROM public.courses WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  'pending_review',
  'submission moves the course into pending review'
);
SELECT throws_ok(
  $$SELECT public.submit_course_for_review('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$,
  '42501', NULL, 'owner cannot submit an already-pending course again'
);
SELECT lives_ok(
  $$UPDATE public.courses SET status = 'draft' WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  'owner direct withdrawal update is silently filtered by RLS'
);

SELECT lives_ok(
  $$UPDATE public.courses SET title = 'Changed while pending' WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  'pending course metadata update is safely filtered by RLS'
);
SELECT lives_ok(
  $$UPDATE public.courses SET status = 'published' WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  'instructor publication attempt is safely filtered by RLS'
);
SELECT lives_ok(
  $$UPDATE public.course_outcomes SET outcome = 'Changed outcome' WHERE id = '12bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$$,
  'pending course outcome update is filtered'
);
SELECT lives_ok(
  $$DELETE FROM public.course_outcomes WHERE id = '12bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$$,
  'pending course outcome deletion is filtered'
);
SELECT throws_ok(
  $$INSERT INTO public.course_outcomes (course_id, position, outcome) VALUES ('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 2, 'Inserted while pending')$$,
  '42501', NULL, 'pending course outcome insertion is denied'
);
SELECT lives_ok(
  $$UPDATE public.course_sections SET title = 'Changed section' WHERE id = '12cccccc-cccc-4ccc-8ccc-cccccccccccc'$$,
  'pending section update is filtered'
);
SELECT lives_ok(
  $$DELETE FROM public.course_sections WHERE id = '12cccccc-cccc-4ccc-8ccc-cccccccccccc'$$,
  'pending section deletion is filtered'
);
SELECT throws_ok(
  $$INSERT INTO public.course_sections (course_id, title, position) VALUES ('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Inserted while pending', 2)$$,
  '42501', NULL, 'pending section insertion is denied'
);
SELECT lives_ok(
  $$UPDATE public.lessons SET title = 'Changed lesson' WHERE id = '12dddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  'pending lesson update is filtered'
);
SELECT lives_ok(
  $$DELETE FROM public.lessons WHERE id = '12dddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  'pending lesson deletion is filtered'
);
SELECT throws_ok(
  $$INSERT INTO public.lessons (course_id, section_id, title, content_type, position) VALUES ('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '12cccccc-cccc-4ccc-8ccc-cccccccccccc', 'Inserted while pending', 'reading', 2)$$,
  '42501', NULL, 'pending lesson insertion is denied'
);
SELECT lives_ok(
  $$UPDATE public.assessments SET title = 'Changed assessment' WHERE id = '12eeeeee-eeee-4eee-9eee-eeeeeeeeeeee'$$,
  'pending assessment update is filtered'
);
SELECT lives_ok(
  $$DELETE FROM public.assessments WHERE id = '12eeeeee-eeee-4eee-9eee-eeeeeeeeeeee'$$,
  'pending assessment deletion is filtered'
);
SELECT throws_ok(
  $$INSERT INTO public.assessments (course_id, title, status) VALUES ('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Inserted while pending', 'draft')$$,
  '42501', NULL, 'pending assessment insertion is denied'
);
SELECT lives_ok(
  $$UPDATE public.assessment_questions SET prompt = 'Changed question' WHERE id = '12ffffff-ffff-4fff-8fff-ffffffffffff'$$,
  'pending question update is filtered'
);
SELECT lives_ok(
  $$DELETE FROM public.assessment_questions WHERE id = '12ffffff-ffff-4fff-8fff-ffffffffffff'$$,
  'pending question deletion is filtered'
);
SELECT throws_ok(
  $$INSERT INTO public.assessment_questions (assessment_id, position, prompt) VALUES ('12eeeeee-eeee-4eee-9eee-eeeeeeeeeeee', 2, 'Inserted while pending')$$,
  '42501', NULL, 'pending question insertion is denied'
);
SELECT lives_ok(
  $$UPDATE public.assessment_options SET option_text = 'Changed option' WHERE id = '13aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  'pending option update is filtered'
);
SELECT lives_ok(
  $$DELETE FROM public.assessment_options WHERE id = '13aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  'pending option deletion is filtered'
);
SELECT throws_ok(
  $$INSERT INTO public.assessment_options (question_id, position, option_text) VALUES ('12ffffff-ffff-4fff-8fff-ffffffffffff', 3, 'Inserted while pending')$$,
  '42501', NULL, 'pending option insertion is denied'
);
SELECT throws_ok(
  $$SELECT public.set_assessment_answer_key('12ffffff-ffff-4fff-8fff-ffffffffffff', '13bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$,
  '42501', NULL, 'answer-key RPC rejects instructor edits while course is pending'
);

RESET ROLE;
SELECT is((SELECT title FROM public.courses WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'Original draft title', 'pending metadata remained unchanged');
SELECT is((SELECT outcome FROM public.course_outcomes WHERE id = '12bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 'Original outcome', 'pending outcome remained unchanged');
SELECT is((SELECT title FROM public.course_sections WHERE id = '12cccccc-cccc-4ccc-8ccc-cccccccccccc'), 'Original section', 'pending section remained unchanged');
SELECT is((SELECT title FROM public.lessons WHERE id = '12dddddd-dddd-4ddd-8ddd-dddddddddddd'), 'Original lesson', 'pending lesson remained unchanged');
SELECT is((SELECT title FROM public.assessments WHERE id = '12eeeeee-eeee-4eee-9eee-eeeeeeeeeeee'), 'Original assessment', 'pending assessment remained unchanged');
SELECT is((SELECT prompt FROM public.assessment_questions WHERE id = '12ffffff-ffff-4fff-8fff-ffffffffffff'), 'Original question', 'pending question remained unchanged');
SELECT is((SELECT option_text FROM public.assessment_options WHERE id = '13aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'Original answer', 'pending option remained unchanged');
SELECT is((SELECT count(*)::integer FROM public.course_outcomes WHERE course_id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 1, 'denied inserts left outcomes unchanged');
SELECT is((SELECT count(*)::integer FROM public.course_sections WHERE course_id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 1, 'denied inserts left sections unchanged');
SELECT is((SELECT count(*)::integer FROM public.lessons WHERE course_id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 1, 'denied inserts left lessons unchanged');
SELECT is((SELECT count(*)::integer FROM public.assessments WHERE course_id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 1, 'denied inserts left assessments unchanged');
SELECT is((SELECT count(*)::integer FROM public.assessment_questions WHERE assessment_id = '12eeeeee-eeee-4eee-9eee-eeeeeeeeeeee'), 1, 'denied inserts left questions unchanged');
SELECT is((SELECT count(*)::integer FROM public.assessment_options WHERE question_id = '12ffffff-ffff-4fff-8fff-ffffffffffff'), 2, 'denied inserts left options unchanged');

-- Other instructors, students, and a non-owning administrator cannot submit or withdraw this course.
SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '12222222-2222-4222-8222-222222222222', true);
SELECT set_config('request.jwt.claims', '{"sub":"12222222-2222-4222-8222-222222222222","role":"authenticated"}', true);
SELECT lives_ok($$UPDATE public.courses SET title = 'Other instructor changed it' WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$, 'other instructor course update is filtered');
SELECT lives_ok($$UPDATE public.lessons SET title = 'Other instructor lesson change' WHERE id = '12dddddd-dddd-4ddd-8ddd-dddddddddddd'$$, 'other instructor lesson update is filtered');
SELECT throws_ok($$SELECT public.set_assessment_answer_key('12ffffff-ffff-4fff-8fff-ffffffffffff', '13bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$, '42501', NULL, 'other instructor cannot use the answer-key RPC');
SELECT throws_ok($$SELECT public.submit_course_for_review('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$, '42501', NULL, 'other instructor cannot submit this course');
SELECT throws_ok($$SELECT public.withdraw_course_submission('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$, '42501', NULL, 'other instructor cannot withdraw this course');

SELECT set_config('request.jwt.claim.sub', '12333333-3333-4333-8333-333333333333', true);
SELECT set_config('request.jwt.claims', '{"sub":"12333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
SELECT lives_ok($$UPDATE public.courses SET title = 'Student changed it' WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$, 'student course update is filtered');
SELECT lives_ok($$UPDATE public.lessons SET title = 'Student lesson change' WHERE id = '12dddddd-dddd-4ddd-8ddd-dddddddddddd'$$, 'student lesson update is filtered');
SELECT throws_ok($$SELECT public.set_assessment_answer_key('12ffffff-ffff-4fff-8fff-ffffffffffff', '13bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$, '42501', NULL, 'student cannot use the answer-key RPC');
SELECT throws_ok($$SELECT public.submit_course_for_review('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$, '42501', NULL, 'student cannot submit this course');
SELECT throws_ok($$SELECT public.withdraw_course_submission('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$, '42501', NULL, 'student cannot withdraw this course');

SELECT set_config('request.jwt.claim.sub', '12444444-4444-4444-8444-444444444444', true);
SELECT set_config('request.jwt.claims', '{"sub":"12444444-4444-4444-8444-444444444444","role":"authenticated"}', true);
SELECT throws_ok($$SELECT public.withdraw_course_submission('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$, '42501', NULL, 'administrator who is not the course owner cannot use owner withdrawal');
SELECT ok(NOT has_function_privilege('anon', 'public.submit_course_for_review(uuid)', 'EXECUTE'), 'anonymous users cannot submit courses');
SELECT ok(NOT has_function_privilege('service_role', 'public.submit_course_for_review(uuid)', 'EXECUTE'), 'service role has no direct submit RPC grant');
SELECT ok(NOT has_function_privilege('anon', 'public.withdraw_course_submission(uuid)', 'EXECUTE'), 'anonymous users cannot withdraw courses');
SELECT ok(NOT has_function_privilege('service_role', 'public.withdraw_course_submission(uuid)', 'EXECUTE'), 'service role has no direct withdrawal RPC grant');
RESET ROLE;
SELECT is((SELECT title FROM public.lessons WHERE id = '12dddddd-dddd-4ddd-8ddd-dddddddddddd'), 'Original lesson', 'non-owner lesson edits left pending content unchanged');
SELECT is((SELECT correct_option_id FROM private.assessment_answer_keys WHERE question_id = '12ffffff-ffff-4fff-8fff-ffffffffffff'), '13aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid, 'non-owner answer-key attempts left the answer key unchanged');

-- The owner may withdraw, edit all submitted content classes while draft, and resubmit.
SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '12111111-1111-4111-8111-111111111111', true);
SELECT set_config('request.jwt.claims', '{"sub":"12111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
SELECT lives_ok($$SELECT public.withdraw_course_submission('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$, 'owning instructor can withdraw pending submission');
RESET ROLE;
SELECT is((SELECT status::text FROM public.courses WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'draft', 'withdrawal returns only the pending course to draft');

SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '12111111-1111-4111-8111-111111111111', true);
SELECT set_config('request.jwt.claims', '{"sub":"12111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
SELECT throws_ok($$SELECT public.withdraw_course_submission('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$, '42501', NULL, 'owner cannot withdraw a draft course');

SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '12111111-1111-4111-8111-111111111111', true);
SELECT set_config('request.jwt.claims', '{"sub":"12111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
SELECT lives_ok($$UPDATE public.courses SET title = 'Edited after withdrawal' WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$, 'owner may edit course metadata after withdrawal');
SELECT lives_ok($$UPDATE public.course_outcomes SET outcome = 'Edited outcome' WHERE id = '12bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$$, 'owner may edit outcomes after withdrawal');
SELECT lives_ok($$UPDATE public.course_sections SET title = 'Edited section' WHERE id = '12cccccc-cccc-4ccc-8ccc-cccccccccccc'$$, 'owner may edit sections after withdrawal');
SELECT lives_ok($$UPDATE public.lessons SET title = 'Edited lesson' WHERE id = '12dddddd-dddd-4ddd-8ddd-dddddddddddd'$$, 'owner may edit lessons after withdrawal');
SELECT lives_ok($$UPDATE public.assessments SET title = 'Edited assessment' WHERE id = '12eeeeee-eeee-4eee-9eee-eeeeeeeeeeee'$$, 'owner may edit assessments after withdrawal');
SELECT lives_ok($$UPDATE public.assessment_questions SET prompt = 'Edited question' WHERE id = '12ffffff-ffff-4fff-8fff-ffffffffffff'$$, 'owner may edit questions after withdrawal');
SELECT lives_ok($$UPDATE public.assessment_options SET option_text = 'Edited answer' WHERE id = '13aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$, 'owner may edit options after withdrawal');
SELECT lives_ok($$SELECT public.set_assessment_answer_key('12ffffff-ffff-4fff-8fff-ffffffffffff', '13bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$, 'owner may use answer-key RPC after withdrawal while draft');
SELECT lives_ok($$SELECT public.submit_course_for_review('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$, 'owner may resubmit after editing withdrawn course');
RESET ROLE;
SELECT is((SELECT status::text FROM public.courses WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'pending_review', 'resubmission returns course to pending review');
SELECT is((SELECT title FROM public.courses WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'Edited after withdrawal', 'resubmitted metadata contains the owner edit');
SELECT is((SELECT outcome FROM public.course_outcomes WHERE id = '12bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 'Edited outcome', 'resubmitted outcome contains the owner edit');
SELECT is((SELECT title FROM public.course_sections WHERE id = '12cccccc-cccc-4ccc-8ccc-cccccccccccc'), 'Edited section', 'resubmitted section contains the owner edit');
SELECT is((SELECT title FROM public.lessons WHERE id = '12dddddd-dddd-4ddd-8ddd-dddddddddddd'), 'Edited lesson', 'resubmitted lesson contains the owner edit');
SELECT is((SELECT title FROM public.assessments WHERE id = '12eeeeee-eeee-4eee-9eee-eeeeeeeeeeee'), 'Edited assessment', 'resubmitted assessment contains the owner edit');
SELECT is((SELECT prompt FROM public.assessment_questions WHERE id = '12ffffff-ffff-4fff-8fff-ffffffffffff'), 'Edited question', 'resubmitted question contains the owner edit');
SELECT is((SELECT option_text FROM public.assessment_options WHERE id = '13aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'Edited answer', 'resubmitted option contains the owner edit');
SELECT is((SELECT correct_option_id FROM private.assessment_answer_keys WHERE question_id = '12ffffff-ffff-4fff-8fff-ffffffffffff'), '13bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid, 'answer-key RPC persists the draft edit');

SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '12111111-1111-4111-8111-111111111111', true);
SELECT set_config('request.jwt.claims', '{"sub":"12111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
SELECT lives_ok($$UPDATE public.lessons SET title = 'Changed after resubmit' WHERE id = '12dddddd-dddd-4ddd-8ddd-dddddddddddd'$$, 'owner lesson edit is filtered again after resubmission');
SELECT lives_ok($$UPDATE public.courses SET status = 'published' WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$, 'owner cannot publish a resubmitted course');
RESET ROLE;
SELECT is((SELECT title FROM public.lessons WHERE id = '12dddddd-dddd-4ddd-8ddd-dddddddddddd'), 'Edited lesson', 'resubmitted lesson remains frozen');
SELECT is((SELECT status::text FROM public.courses WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'pending_review', 'resubmitted course remains pending until administrator approval');

SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '12444444-4444-4444-8444-444444444444', true);
SELECT set_config('request.jwt.claims', '{"sub":"12444444-4444-4444-8444-444444444444","role":"authenticated"}', true);
SELECT lives_ok($$UPDATE public.courses SET status = 'published' WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$, 'administrator can publish after resubmission');
RESET ROLE;
SELECT is((SELECT status::text FROM public.courses WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'published', 'administrator publication remains effective');
SELECT ok((SELECT published_at IS NOT NULL FROM public.courses WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'successful publication records published_at');
SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '12111111-1111-4111-8111-111111111111', true);
SELECT set_config('request.jwt.claims', '{"sub":"12111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
SELECT throws_ok($$SELECT public.withdraw_course_submission('12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')$$, '42501', NULL, 'owner cannot withdraw a published course');
RESET ROLE;
SELECT is((SELECT status::text FROM public.courses WHERE id = '12aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'published', 'withdrawal attempt leaves published course intact');

SELECT * FROM finish();
ROLLBACK;
