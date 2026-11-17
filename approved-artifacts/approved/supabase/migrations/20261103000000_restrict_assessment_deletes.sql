-- Preserve assessment records when their owning course or lesson is deleted.
-- These two foreign keys are otherwise unchanged; existing rows are retained
-- and PostgreSQL validates all existing references while adding the constraints.
ALTER TABLE public.assessments
  DROP CONSTRAINT assessments_course_id_fkey,
  ADD CONSTRAINT assessments_course_id_fkey
    FOREIGN KEY (course_id)
    REFERENCES public.courses (id)
    ON DELETE RESTRICT,
  DROP CONSTRAINT assessments_lesson_course_fk,
  ADD CONSTRAINT assessments_lesson_course_fk
    FOREIGN KEY (lesson_id, course_id)
    REFERENCES public.lessons (id, course_id)
    ON DELETE RESTRICT;
