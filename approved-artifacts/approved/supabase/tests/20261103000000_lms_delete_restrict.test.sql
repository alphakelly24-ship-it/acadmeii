-- Local-only pgTAP coverage for RESTRICT behavior on course/lesson assessments.
-- Run only against a disposable local test database; all fixtures are rolled back.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
BEGIN;
SET LOCAL search_path = public, extensions;
SELECT no_plan();

INSERT INTO auth.users (
  id, aud, "role", email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('71000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'delete-admin@academi.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('71000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'delete-instructor@academi.test', '', now(), '{}'::jsonb, '{"display_name":"Delete Test Instructor"}'::jsonb, now(), now()),
  ('71000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'delete-student@academi.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

INSERT INTO public.user_roles (user_id, role) VALUES
  ('71000000-0000-4000-8000-000000000001', 'admin'),
  ('71000000-0000-4000-8000-000000000002', 'student'),
  ('71000000-0000-4000-8000-000000000002', 'instructor'),
  ('71000000-0000-4000-8000-000000000003', 'student');
INSERT INTO public.instructor_profiles (user_id, public_name)
VALUES ('71000000-0000-4000-8000-000000000002', 'Delete Test Instructor');
INSERT INTO public.categories (id, name, slug) VALUES
  ('71000000-0000-4000-8000-000000000010', 'Deletion Tests', 'deletion-tests');

-- Seed all dependent rows as the trusted database owner with an admin claim so
-- the course/content triggers see an authorized actor in the same transaction.
SELECT set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"71000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
INSERT INTO public.courses (id, instructor_id, category_id, slug, title, status) VALUES
  ('71000000-0000-4000-8000-000000000101', '71000000-0000-4000-8000-000000000002', '71000000-0000-4000-8000-000000000010', 'delete-with-enrollment', 'Course with enrollment', 'draft'),
  ('71000000-0000-4000-8000-000000000102', '71000000-0000-4000-8000-000000000002', '71000000-0000-4000-8000-000000000010', 'delete-with-assessment', 'Course with standalone assessment', 'draft'),
  ('71000000-0000-4000-8000-000000000103', '71000000-0000-4000-8000-000000000002', '71000000-0000-4000-8000-000000000010', 'lesson-with-assessment', 'Course with lesson assessment', 'draft');
INSERT INTO public.course_sections (id, course_id, title, position) VALUES
  ('71000000-0000-4000-8000-000000000201', '71000000-0000-4000-8000-000000000101', 'Enrollment section', 1),
  ('71000000-0000-4000-8000-000000000202', '71000000-0000-4000-8000-000000000102', 'Standalone quiz section', 1),
  ('71000000-0000-4000-8000-000000000203', '71000000-0000-4000-8000-000000000103', 'Lesson quiz section', 1);
INSERT INTO public.lessons (id, course_id, section_id, title, content_type, position) VALUES
  ('71000000-0000-4000-8000-000000000301', '71000000-0000-4000-8000-000000000101', '71000000-0000-4000-8000-000000000201', 'Progress lesson', 'reading', 1),
  ('71000000-0000-4000-8000-000000000302', '71000000-0000-4000-8000-000000000102', '71000000-0000-4000-8000-000000000202', 'Standalone quiz course lesson', 'reading', 1),
  ('71000000-0000-4000-8000-000000000303', '71000000-0000-4000-8000-000000000103', '71000000-0000-4000-8000-000000000203', 'Assessed lesson', 'reading', 1);
INSERT INTO public.enrollments (id, student_id, course_id, status) VALUES
  ('71000000-0000-4000-8000-000000000401', '71000000-0000-4000-8000-000000000003', '71000000-0000-4000-8000-000000000101', 'active');
INSERT INTO public.lesson_progress (enrollment_id, course_id, lesson_id, last_position_seconds) VALUES
  ('71000000-0000-4000-8000-000000000401', '71000000-0000-4000-8000-000000000101', '71000000-0000-4000-8000-000000000301', 37);
INSERT INTO public.assessments (id, course_id, lesson_id, title, status) VALUES
  ('71000000-0000-4000-8000-000000000501', '71000000-0000-4000-8000-000000000102', NULL, 'Standalone assessment', 'draft'),
  ('71000000-0000-4000-8000-000000000502', '71000000-0000-4000-8000-000000000103', '71000000-0000-4000-8000-000000000303', 'Lesson assessment', 'draft');
INSERT INTO public.assessment_questions (id, assessment_id, position, prompt) VALUES
  ('71000000-0000-4000-8000-000000000601', '71000000-0000-4000-8000-000000000501', 1, 'Standalone assessment question'),
  ('71000000-0000-4000-8000-000000000602', '71000000-0000-4000-8000-000000000502', 1, 'Lesson assessment question');
INSERT INTO public.assessment_options (id, question_id, position, option_text) VALUES
  ('71000000-0000-4000-8000-000000000701', '71000000-0000-4000-8000-000000000601', 1, 'Standalone option'),
  ('71000000-0000-4000-8000-000000000702', '71000000-0000-4000-8000-000000000602', 1, 'Lesson option');
INSERT INTO private.assessment_answer_keys (question_id, correct_option_id) VALUES
  ('71000000-0000-4000-8000-000000000601', '71000000-0000-4000-8000-000000000701'),
  ('71000000-0000-4000-8000-000000000602', '71000000-0000-4000-8000-000000000702');

-- The owner has no DELETE grant on courses: RLS alone is not the only barrier.
SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000002', true);
SELECT set_config('request.jwt.claims', '{"sub":"71000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
SELECT throws_ok(
  $$DELETE FROM public.courses WHERE id = '71000000-0000-4000-8000-000000000101'$$,
  '42501', NULL, 'authenticated instructor has no direct course DELETE permission'
);
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.courses WHERE id = '71000000-0000-4000-8000-000000000101'), 1, 'denied instructor course deletion leaves the course intact');
SELECT is((SELECT count(*)::integer FROM public.enrollments WHERE id = '71000000-0000-4000-8000-000000000401'), 1, 'denied instructor course deletion leaves enrollment intact');
SELECT is((SELECT count(*)::integer FROM public.lesson_progress WHERE enrollment_id = '71000000-0000-4000-8000-000000000401'), 1, 'denied instructor course deletion leaves learner progress intact');

-- Run as the local database owner (outside API RLS) to exercise the FK itself.
SELECT throws_ok(
  $$DELETE FROM public.courses WHERE id = '71000000-0000-4000-8000-000000000101'$$,
  '23503', NULL, 'database-level course deletion is restricted while enrollments exist'
);
SELECT is((SELECT count(*)::integer FROM public.courses WHERE id = '71000000-0000-4000-8000-000000000101'), 1, 'enrollment-blocked course deletion leaves the course intact');
SELECT is((SELECT count(*)::integer FROM public.course_sections WHERE id = '71000000-0000-4000-8000-000000000201'), 1, 'enrollment-blocked course deletion leaves its section intact');
SELECT is((SELECT count(*)::integer FROM public.lessons WHERE id = '71000000-0000-4000-8000-000000000301'), 1, 'enrollment-blocked course deletion leaves its lesson intact');
SELECT is((SELECT count(*)::integer FROM public.enrollments WHERE id = '71000000-0000-4000-8000-000000000401'), 1, 'enrollment-blocked course deletion leaves its enrollment intact');
SELECT is((SELECT count(*)::integer FROM public.lesson_progress WHERE enrollment_id = '71000000-0000-4000-8000-000000000401'), 1, 'enrollment-blocked course deletion leaves learner progress intact');

SELECT throws_ok(
  $$DELETE FROM public.courses WHERE id = '71000000-0000-4000-8000-000000000102'$$,
  '23503', NULL, 'course deletion is restricted even when its assessment is not attached to a lesson'
);
SELECT is((SELECT count(*)::integer FROM public.courses WHERE id = '71000000-0000-4000-8000-000000000102'), 1, 'assessment-blocked course deletion leaves the course intact');
SELECT is((SELECT count(*)::integer FROM public.course_sections WHERE id = '71000000-0000-4000-8000-000000000202'), 1, 'assessment-blocked course deletion leaves its section intact');
SELECT is((SELECT count(*)::integer FROM public.lessons WHERE id = '71000000-0000-4000-8000-000000000302'), 1, 'assessment-blocked course deletion leaves its lesson intact');
SELECT is((SELECT count(*)::integer FROM public.assessments WHERE id = '71000000-0000-4000-8000-000000000501'), 1, 'assessment-blocked course deletion leaves the assessment intact');
SELECT is((SELECT count(*)::integer FROM public.assessment_questions WHERE id = '71000000-0000-4000-8000-000000000601'), 1, 'assessment-blocked course deletion leaves its question intact');
SELECT is((SELECT count(*)::integer FROM public.assessment_options WHERE id = '71000000-0000-4000-8000-000000000701'), 1, 'assessment-blocked course deletion leaves its option intact');
SELECT is((SELECT count(*)::integer FROM private.assessment_answer_keys WHERE question_id = '71000000-0000-4000-8000-000000000601'), 1, 'assessment-blocked course deletion leaves its answer key intact');

-- The owning instructor can reach the lesson DELETE policy, but FKs preserve
-- progress and assessment-backed lessons at the database integrity boundary.
SET LOCAL ROLE authenticated;
SET LOCAL search_path = public, extensions;
SELECT set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000002', true);
SELECT set_config('request.jwt.claims', '{"sub":"71000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
SELECT throws_ok(
  $$DELETE FROM public.lessons WHERE id = '71000000-0000-4000-8000-000000000301'$$,
  '23503', NULL, 'lesson deletion is restricted while learner progress references it'
);
SELECT throws_ok(
  $$DELETE FROM public.lessons WHERE id = '71000000-0000-4000-8000-000000000303'$$,
  '23503', NULL, 'lesson deletion is restricted while an assessment references it'
);
RESET ROLE;
SELECT is((SELECT count(*)::integer FROM public.lessons WHERE id = '71000000-0000-4000-8000-000000000301'), 1, 'progress-blocked lesson deletion leaves the lesson intact');
SELECT is((SELECT count(*)::integer FROM public.lesson_progress WHERE lesson_id = '71000000-0000-4000-8000-000000000301'), 1, 'progress-blocked lesson deletion leaves learner progress intact');
SELECT is((SELECT count(*)::integer FROM public.lessons WHERE id = '71000000-0000-4000-8000-000000000303'), 1, 'assessment-blocked lesson deletion leaves the lesson intact');
SELECT is((SELECT count(*)::integer FROM public.assessments WHERE id = '71000000-0000-4000-8000-000000000502'), 1, 'assessment-blocked lesson deletion leaves the assessment intact');
SELECT is((SELECT count(*)::integer FROM public.assessment_questions WHERE id = '71000000-0000-4000-8000-000000000602'), 1, 'assessment-blocked lesson deletion leaves its question intact');
SELECT is((SELECT count(*)::integer FROM public.assessment_options WHERE id = '71000000-0000-4000-8000-000000000702'), 1, 'assessment-blocked lesson deletion leaves its option intact');
SELECT is((SELECT count(*)::integer FROM private.assessment_answer_keys WHERE question_id = '71000000-0000-4000-8000-000000000602'), 1, 'assessment-blocked lesson deletion leaves its answer key intact');

SELECT * FROM finish();
ROLLBACK;
