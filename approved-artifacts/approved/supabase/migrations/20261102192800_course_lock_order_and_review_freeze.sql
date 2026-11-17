-- Academi lock-order hardening and initial-review freeze.
-- Forward-only migration. Do not edit earlier migration files.
-- Locks remain per course; PostgreSQL may still detect deadlocks in arbitrary
-- multi-row/cross-table transactions, which must be retried as a whole.

-- RLS limits ordinary course edits to drafts. This trigger also prevents a
-- direct INSERT from creating an instructor-owned pending/published row and
-- ensures submit/withdraw transitions change status only. Admin publication
-- remains allowed only from pending_review by the original guard's rule.
CREATE OR REPLACE FUNCTION private.guard_course_publication()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_is_admin boolean := private.has_role('admin'::public.app_role);
  v_actor_id uuid := auth.uid();
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'published'::public.course_status THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'A course must be submitted for review before publication.';
    END IF;
    IF NOT v_is_admin AND NEW.status <> 'draft'::public.course_status THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Instructors must create courses as drafts.';
    END IF;
    IF NOT v_is_admin THEN
      IF v_actor_id IS NULL
         OR NEW.instructor_id IS DISTINCT FROM v_actor_id
         OR NOT private.has_role('instructor'::public.app_role) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only an instructor may create their own draft course.';
      END IF;
      NEW.published_at := NULL;
    END IF;
    IF NEW.status = 'published'::public.course_status AND NEW.published_at IS NULL THEN
      NEW.published_at := pg_catalog.now();
    END IF;
    RETURN NEW;
  END IF;

  IF NOT v_is_admin THEN
    IF v_actor_id IS NULL
       OR OLD.instructor_id IS DISTINCT FROM v_actor_id
       OR NEW.instructor_id IS DISTINCT FROM v_actor_id
       OR NOT private.has_role('instructor'::public.app_role) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owning instructor may manage this course.';
    END IF;

    IF OLD.status = 'draft'::public.course_status THEN
      IF NEW.status NOT IN ('draft'::public.course_status, 'pending_review'::public.course_status) THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Instructors cannot approve or publish their own courses.';
      END IF;
    ELSIF OLD.status = 'pending_review'::public.course_status
       AND NEW.status = 'draft'::public.course_status THEN
      NULL; -- Owner-only withdrawal RPC; RLS blocks the equivalent direct UPDATE.
    ELSE
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Submitted or published courses cannot be edited by instructors.';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status
       AND (
         NEW.instructor_id IS DISTINCT FROM OLD.instructor_id
         OR NEW.category_id IS DISTINCT FROM OLD.category_id
         OR NEW.slug IS DISTINCT FROM OLD.slug
         OR NEW.title IS DISTINCT FROM OLD.title
         OR NEW.subtitle IS DISTINCT FROM OLD.subtitle
         OR NEW.description IS DISTINCT FROM OLD.description
         OR NEW.level IS DISTINCT FROM OLD.level
         OR NEW.language_code IS DISTINCT FROM OLD.language_code
       ) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Submission and withdrawal may change course status only.';
    END IF;

    NEW.published_at := OLD.published_at;
  END IF;

  IF NEW.status = 'published'::public.course_status
     AND OLD.status IS DISTINCT FROM 'published'::public.course_status THEN
    IF OLD.status <> 'pending_review'::public.course_status THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only a course pending review can be published.';
    END IF;
    IF NOT v_is_admin THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only an administrator can approve and publish a course.';
    END IF;
  END IF;

  IF NEW.status = 'published'::public.course_status AND NEW.published_at IS NULL THEN
    NEW.published_at := pg_catalog.now();
  END IF;
  RETURN NEW;
END;
$$;

-- Instructors may directly edit course content only while the course is draft.
-- Administrators retain their explicit moderation/maintenance access.
CREATE OR REPLACE FUNCTION private.can_edit_course_content(_course_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.courses AS c
    WHERE c.id = _course_id
      AND (
        private.has_role('admin'::public.app_role)
        OR (
          c.instructor_id = (SELECT auth.uid())
          AND private.has_role('instructor'::public.app_role)
          AND c.status = 'draft'::public.course_status
        )
      )
  );
$$;

-- The previous owner/admin update policy used can_manage_course(), which also
-- allowed an owner to update a pending row's status. Rebind it to the draft-only
-- helper; trusted SECURITY DEFINER submit/withdraw RPCs perform the state change.
DROP POLICY courses_owner_or_admin_update ON public.courses;
CREATE POLICY courses_owner_or_admin_update
ON public.courses FOR UPDATE TO authenticated
USING (private.can_edit_course_content(id))
WITH CHECK (
  private.has_role('admin'::public.app_role)
  OR (
    instructor_id = (SELECT auth.uid())
    AND private.has_role('instructor'::public.app_role)
    AND status = 'draft'::public.course_status
  )
);

-- An instructor may write assessment content only when both the assessment
-- and its owning course are still drafts. Published-course edits continue to
-- use the staged course-revision workflow.
CREATE OR REPLACE FUNCTION private.can_edit_assessment(_assessment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.assessments AS a
    JOIN public.courses AS c ON c.id = a.course_id
    WHERE a.id = _assessment_id
      AND (
        private.has_role('admin'::public.app_role)
        OR (
          a.status = 'draft'::public.assessment_status
          AND c.status = 'draft'::public.course_status
          AND c.instructor_id = (SELECT auth.uid())
          AND private.has_role('instructor'::public.app_role)
        )
      )
  );
$$;

-- Existing-row UPDATE/DELETE obtains the target tuple lock before this
-- BEFORE ROW trigger runs. The trigger then locks affected course rows in UUID
-- order, re-reads state under FOR UPDATE, and rechecks owner/admin permission.
-- That post-lock check closes the RLS-snapshot race at initial submission.
CREATE OR REPLACE FUNCTION private.lock_course_content_for_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_old_course_id uuid;
  v_new_course_id uuid;
  v_course_id uuid;
  v_course_owner uuid;
  v_course_status public.course_status;
  v_actor_id uuid := auth.uid();
  v_is_admin boolean := private.has_role('admin'::public.app_role);
  v_is_instructor boolean := private.has_role('instructor'::public.app_role);
BEGIN
  IF TG_OP <> 'INSERT' THEN
    v_old_course_id := OLD.course_id;
  END IF;
  IF TG_OP <> 'DELETE' THEN
    v_new_course_id := NEW.course_id;
  END IF;

  FOR v_course_id IN
    SELECT DISTINCT ids.course_id
    FROM pg_catalog.unnest(ARRAY[v_old_course_id, v_new_course_id]) AS ids(course_id)
    WHERE ids.course_id IS NOT NULL
    ORDER BY ids.course_id
  LOOP
    SELECT c.instructor_id, c.status
      INTO v_course_owner, v_course_status
    FROM public.courses AS c
    WHERE c.id = v_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'The live course for this content row does not exist.';
    END IF;

    IF NOT v_is_admin
       AND (
         v_actor_id IS NULL
         OR v_course_owner IS DISTINCT FROM v_actor_id
         OR NOT v_is_instructor
         OR v_course_status IS DISTINCT FROM 'draft'::public.course_status
       ) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owning instructor may edit course content while the course is a draft.';
    END IF;

    UPDATE public.courses
    SET content_version = content_version + 1
    WHERE id = v_course_id;
  END LOOP;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

-- Assessment descendants use tuple -> parent assessment/question -> course
-- order. Re-read course state after acquiring each course lock so a write that
-- began before submission cannot slip through using an older RLS snapshot.
CREATE OR REPLACE FUNCTION private.lock_assessment_content_for_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_old_assessment_id uuid;
  v_new_assessment_id uuid;
  v_old_question_id uuid;
  v_new_question_id uuid;
  v_parent_id uuid;
  v_old_course_id uuid;
  v_new_course_id uuid;
  v_course_id uuid;
  v_course_owner uuid;
  v_course_status public.course_status;
  v_actor_id uuid := auth.uid();
  v_is_admin boolean := private.has_role('admin'::public.app_role);
  v_is_instructor boolean := private.has_role('instructor'::public.app_role);
BEGIN
  IF TG_TABLE_NAME = 'assessment_questions' THEN
    IF TG_OP <> 'INSERT' THEN
      v_old_assessment_id := OLD.assessment_id;
    END IF;
    IF TG_OP <> 'DELETE' THEN
      v_new_assessment_id := NEW.assessment_id;
    END IF;

    FOR v_parent_id IN
      SELECT DISTINCT ids.parent_id
      FROM pg_catalog.unnest(ARRAY[v_old_assessment_id, v_new_assessment_id]) AS ids(parent_id)
      WHERE ids.parent_id IS NOT NULL
      ORDER BY ids.parent_id
    LOOP
      PERFORM 1
      FROM public.assessments AS a
      WHERE a.id = v_parent_id
      FOR SHARE;
    END LOOP;

    IF TG_OP <> 'INSERT' THEN
      SELECT a.course_id INTO v_old_course_id
      FROM public.assessments AS a WHERE a.id = v_old_assessment_id;
    END IF;
    IF TG_OP <> 'DELETE' THEN
      SELECT a.course_id INTO v_new_course_id
      FROM public.assessments AS a WHERE a.id = v_new_assessment_id;
    END IF;
  ELSE
    IF TG_OP <> 'INSERT' THEN
      v_old_question_id := OLD.question_id;
    END IF;
    IF TG_OP <> 'DELETE' THEN
      v_new_question_id := NEW.question_id;
    END IF;

    FOR v_parent_id IN
      SELECT DISTINCT ids.parent_id
      FROM pg_catalog.unnest(ARRAY[v_old_question_id, v_new_question_id]) AS ids(parent_id)
      WHERE ids.parent_id IS NOT NULL
      ORDER BY ids.parent_id
    LOOP
      PERFORM 1
      FROM public.assessment_questions AS q
      WHERE q.id = v_parent_id
      FOR SHARE;
    END LOOP;

    FOR v_parent_id IN
      SELECT DISTINCT q.assessment_id
      FROM public.assessment_questions AS q
      WHERE q.id = ANY(ARRAY[v_old_question_id, v_new_question_id])
      ORDER BY q.assessment_id
    LOOP
      PERFORM 1
      FROM public.assessments AS a
      WHERE a.id = v_parent_id
      FOR SHARE;
    END LOOP;

    IF TG_OP <> 'INSERT' THEN
      SELECT a.course_id INTO v_old_course_id
      FROM public.assessment_questions AS q
      JOIN public.assessments AS a ON a.id = q.assessment_id
      WHERE q.id = v_old_question_id;
    END IF;
    IF TG_OP <> 'DELETE' THEN
      SELECT a.course_id INTO v_new_course_id
      FROM public.assessment_questions AS q
      JOIN public.assessments AS a ON a.id = q.assessment_id
      WHERE q.id = v_new_question_id;
    END IF;
  END IF;

  FOR v_course_id IN
    SELECT DISTINCT ids.course_id
    FROM pg_catalog.unnest(ARRAY[v_old_course_id, v_new_course_id]) AS ids(course_id)
    WHERE ids.course_id IS NOT NULL
    ORDER BY ids.course_id
  LOOP
    SELECT c.instructor_id, c.status
      INTO v_course_owner, v_course_status
    FROM public.courses AS c
    WHERE c.id = v_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'The live course for this assessment content row does not exist.';
    END IF;

    IF NOT v_is_admin
       AND (
         v_actor_id IS NULL
         OR v_course_owner IS DISTINCT FROM v_actor_id
         OR NOT v_is_instructor
         OR v_course_status IS DISTINCT FROM 'draft'::public.course_status
       ) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owning instructor may edit assessment content while the course is a draft.';
    END IF;

    UPDATE public.courses
    SET content_version = content_version + 1
    WHERE id = v_course_id;
  END LOOP;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

-- Submission and withdrawal are explicit state transitions. Direct instructor
-- UPDATE policies now accept only draft rows; these SECURITY DEFINER RPCs lock
-- the course and mutate status without granting a path to publication.
CREATE FUNCTION public.submit_course_for_review(_course_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_course public.courses%ROWTYPE;
BEGIN
  IF v_actor_id IS NULL OR NOT private.has_role('instructor'::public.app_role) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Instructor permission is required to submit a course.';
  END IF;

  SELECT * INTO v_course
  FROM public.courses AS c
  WHERE c.id = _course_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_course.instructor_id IS DISTINCT FROM v_actor_id
     OR v_course.status <> 'draft'::public.course_status
     OR v_course.published_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owning instructor can submit an unpublished draft course.';
  END IF;

  UPDATE public.courses
  SET status = 'pending_review'::public.course_status
  WHERE id = v_course.id;
END;
$$;

CREATE FUNCTION public.withdraw_course_submission(_course_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_course public.courses%ROWTYPE;
BEGIN
  IF v_actor_id IS NULL OR NOT private.has_role('instructor'::public.app_role) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Instructor permission is required to withdraw a course submission.';
  END IF;

  SELECT * INTO v_course
  FROM public.courses AS c
  WHERE c.id = _course_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_course.instructor_id IS DISTINCT FROM v_actor_id
     OR v_course.status <> 'pending_review'::public.course_status
     OR v_course.published_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owning instructor can withdraw an unpublished course pending review.';
  END IF;

  UPDATE public.courses
  SET status = 'draft'::public.course_status
  WHERE id = v_course.id;
END;
$$;

-- Approval acquires the target live tuples before the course row, matching the
-- implicit tuple -> course order of existing-row child edits. Lock in a stable
-- table/ID order; then lock the single course and recheck its version. FK locks,
-- multi-row statements, and transactions touching several content tables can
-- still deadlock; PostgreSQL aborts a victim and the caller must retry the whole
-- RPC/transaction. All promotion writes remain one atomic statement.
CREATE OR REPLACE FUNCTION public.approve_course_revision(_revision_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_revision public.course_revisions%ROWTYPE;
  v_course public.courses%ROWTYPE;
  v_unsafe_lesson_id uuid;
  v_reason text;
BEGIN
  IF v_actor_id IS NULL OR NOT private.has_role('admin'::public.app_role) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Administrator permission is required to approve a course revision.';
  END IF;

  SELECT * INTO v_revision
  FROM public.course_revisions AS r
  WHERE r.id = _revision_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Course revision not found.';
  END IF;
  IF v_revision.status <> 'pending_review'::public.course_revision_status THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'Only a submitted revision can be approved.';
  END IF;

  -- Tuple locks first; course lock follows. FK checks and independent multi-row
  -- transactions can still introduce other lock edges, so this is not a claim
  -- that arbitrary database workloads are deadlock-free.
  PERFORM 1 FROM public.lessons AS live
  WHERE live.course_id = v_revision.course_id
  ORDER BY live.id
  FOR UPDATE;

  PERFORM 1 FROM public.course_sections AS live
  WHERE live.course_id = v_revision.course_id
  ORDER BY live.id
  FOR UPDATE;

  PERFORM 1 FROM public.course_outcomes AS live
  WHERE live.course_id = v_revision.course_id
  ORDER BY live.id
  FOR UPDATE;

  SELECT * INTO v_course
  FROM public.courses AS c
  WHERE c.id = v_revision.course_id
  FOR UPDATE;

  IF NOT FOUND OR v_course.status <> 'published'::public.course_status THEN
    v_reason := 'Cannot approve this revision because the live course is no longer published.';
  ELSIF v_course.instructor_id <> v_revision.instructor_id
     OR v_course.content_version <> v_revision.base_content_version THEN
    v_reason := 'Cannot approve stale revision: the live course changed after this revision was created. Create a fresh revision.';
  ELSIF EXISTS (
    SELECT 1 FROM public.courses AS other_course
    WHERE other_course.slug = v_revision.slug
      AND other_course.id <> v_course.id
  ) THEN
    v_reason := 'Cannot approve this revision because its proposed course slug is already in use.';
  ELSIF EXISTS (
    SELECT 1
    FROM public.course_revision_sections AS staged
    JOIN public.course_sections AS live ON live.id = staged.section_id
    WHERE staged.revision_id = v_revision.id
      AND live.course_id <> v_course.id
  ) OR EXISTS (
    SELECT 1
    FROM public.course_revision_lessons AS staged
    JOIN public.lessons AS live ON live.id = staged.lesson_id
    WHERE staged.revision_id = v_revision.id
      AND live.course_id <> v_course.id
  ) OR EXISTS (
    SELECT 1
    FROM public.course_revision_outcomes AS staged
    JOIN public.course_outcomes AS live ON live.id = staged.outcome_id
    WHERE staged.revision_id = v_revision.id
      AND live.course_id <> v_course.id
  ) THEN
    v_reason := 'Cannot approve this revision because a staged content ID belongs to another course.';
  END IF;

  IF v_reason IS NOT NULL THEN
    UPDATE public.course_revisions
    SET status = 'rejected'::public.course_revision_status,
        reviewed_at = pg_catalog.clock_timestamp(),
        reviewed_by = v_actor_id,
        review_reason = v_reason
    WHERE id = v_revision.id;
    RETURN 'rejected: ' || v_reason;
  END IF;

  -- Lesson locks are held before this check so learner progress inserts either
  -- commit first and are visible here, or wait and fail their lesson FK safely.
  SELECT live.id INTO v_unsafe_lesson_id
  FROM public.lessons AS live
  WHERE live.course_id = v_course.id
    AND NOT EXISTS (
      SELECT 1 FROM public.course_revision_lessons AS staged
      WHERE staged.revision_id = v_revision.id
        AND staged.lesson_id = live.id
    )
    AND EXISTS (
      SELECT 1 FROM public.lesson_progress AS progress
      WHERE progress.course_id = v_course.id
        AND progress.lesson_id = live.id
    )
  ORDER BY live.id
  LIMIT 1;

  IF v_unsafe_lesson_id IS NOT NULL THEN
    v_reason := pg_catalog.format(
      'Cannot remove lesson %s because learner progress exists for it.',
      v_unsafe_lesson_id
    );
  ELSE
    SELECT live.id INTO v_unsafe_lesson_id
    FROM public.lessons AS live
    WHERE live.course_id = v_course.id
      AND NOT EXISTS (
        SELECT 1 FROM public.course_revision_lessons AS staged
        WHERE staged.revision_id = v_revision.id
          AND staged.lesson_id = live.id
      )
      AND EXISTS (
        SELECT 1 FROM public.assessments AS a
        WHERE a.course_id = v_course.id
          AND a.lesson_id = live.id
      )
    ORDER BY live.id
    LIMIT 1;

    IF v_unsafe_lesson_id IS NOT NULL THEN
      v_reason := pg_catalog.format(
        'Cannot remove lesson %s because an associated assessment exists.',
        v_unsafe_lesson_id
      );
    END IF;
  END IF;

  IF v_reason IS NOT NULL THEN
    UPDATE public.course_revisions
    SET status = 'rejected'::public.course_revision_status,
        reviewed_at = pg_catalog.clock_timestamp(),
        reviewed_by = v_actor_id,
        review_reason = v_reason
    WHERE id = v_revision.id;
    RETURN 'rejected: ' || v_reason;
  END IF;

  SET CONSTRAINTS
    public.course_outcomes_course_id_position_key,
    public.course_sections_course_id_position_key,
    public.lessons_section_id_position_key
  DEFERRED;

  UPDATE public.courses
  SET category_id = v_revision.category_id,
      slug = v_revision.slug,
      title = v_revision.title,
      subtitle = v_revision.subtitle,
      description = v_revision.description,
      level = v_revision.level,
      language_code = v_revision.language_code
  WHERE id = v_course.id;

  INSERT INTO public.course_outcomes (id, course_id, position, outcome)
  SELECT staged.outcome_id, v_course.id, staged.position, staged.outcome
  FROM public.course_revision_outcomes AS staged
  WHERE staged.revision_id = v_revision.id
  ON CONFLICT (id) DO UPDATE
    SET position = EXCLUDED.position,
        outcome = EXCLUDED.outcome;

  DELETE FROM public.course_outcomes AS live
  WHERE live.course_id = v_course.id
    AND NOT EXISTS (
      SELECT 1 FROM public.course_revision_outcomes AS staged
      WHERE staged.revision_id = v_revision.id
        AND staged.outcome_id = live.id
    );

  INSERT INTO public.course_sections (id, course_id, title, position)
  SELECT staged.section_id, v_course.id, staged.title, staged.position
  FROM public.course_revision_sections AS staged
  WHERE staged.revision_id = v_revision.id
  ON CONFLICT (id) DO UPDATE
    SET title = EXCLUDED.title,
        position = EXCLUDED.position,
        updated_at = pg_catalog.clock_timestamp();

  INSERT INTO public.lessons (
    id, course_id, section_id, title, summary, content_type,
    position, duration_seconds, is_preview
  )
  SELECT staged.lesson_id, v_course.id, staged.section_id, staged.title,
         staged.summary, staged.content_type, staged.position,
         staged.duration_seconds, staged.is_preview
  FROM public.course_revision_lessons AS staged
  WHERE staged.revision_id = v_revision.id
  ON CONFLICT (id) DO UPDATE
    SET section_id = EXCLUDED.section_id,
        title = EXCLUDED.title,
        summary = EXCLUDED.summary,
        content_type = EXCLUDED.content_type,
        position = EXCLUDED.position,
        duration_seconds = EXCLUDED.duration_seconds,
        is_preview = EXCLUDED.is_preview,
        updated_at = pg_catalog.clock_timestamp();

  DELETE FROM public.lessons AS live
  WHERE live.course_id = v_course.id
    AND NOT EXISTS (
      SELECT 1 FROM public.course_revision_lessons AS staged
      WHERE staged.revision_id = v_revision.id
        AND staged.lesson_id = live.id
    );

  DELETE FROM public.course_sections AS live
  WHERE live.course_id = v_course.id
    AND NOT EXISTS (
      SELECT 1 FROM public.course_revision_sections AS staged
      WHERE staged.revision_id = v_revision.id
        AND staged.section_id = live.id
    );

  SET CONSTRAINTS
    public.course_outcomes_course_id_position_key,
    public.course_sections_course_id_position_key,
    public.lessons_section_id_position_key
  IMMEDIATE;

  UPDATE public.course_revisions
  SET status = 'approved'::public.course_revision_status,
      reviewed_at = pg_catalog.clock_timestamp(),
      reviewed_by = v_actor_id,
      review_reason = NULL
  WHERE id = v_revision.id;

  RETURN 'approved';
END;
$$;

-- The answer-key RPC follows the trigger hierarchy: question -> assessment ->
-- course -> answer-key row. Its existing SECURITY DEFINER boundary and role
-- checks remain; instructors may set keys only for draft assessments/draft courses.
CREATE OR REPLACE FUNCTION public.set_assessment_answer_key(
  _question_id uuid,
  _correct_option_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_assessment_id uuid;
  v_course_id uuid;
  v_assessment_status public.assessment_status;
  v_course_status public.course_status;
  v_course_owner uuid;
  v_is_admin boolean := private.has_role('admin'::public.app_role);
  v_is_instructor boolean := private.has_role('instructor'::public.app_role);
BEGIN
  SELECT q.assessment_id INTO v_assessment_id
  FROM public.assessment_questions AS q
  WHERE q.id = _question_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'You cannot manage this assessment.';
  END IF;

  SELECT a.course_id, a.status INTO v_course_id, v_assessment_status
  FROM public.assessments AS a
  WHERE a.id = v_assessment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'You cannot manage this assessment.';
  END IF;

  SELECT c.instructor_id, c.status INTO v_course_owner, v_course_status
  FROM public.courses AS c
  WHERE c.id = v_course_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'You cannot manage this assessment.';
  END IF;

  IF NOT v_is_admin
     AND (
       v_actor_id IS NULL
       OR v_course_owner IS DISTINCT FROM v_actor_id
       OR NOT v_is_instructor
       OR v_assessment_status IS DISTINCT FROM 'draft'::public.assessment_status
       OR v_course_status IS DISTINCT FROM 'draft'::public.course_status
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'You cannot manage this assessment.';
  END IF;

  INSERT INTO private.assessment_answer_keys (question_id, correct_option_id)
  VALUES (_question_id, _correct_option_id)
  ON CONFLICT (question_id) DO UPDATE
    SET correct_option_id = EXCLUDED.correct_option_id,
        updated_at = pg_catalog.now();
END;
$$;

REVOKE ALL ON FUNCTION public.submit_course_for_review(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.withdraw_course_submission(uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.submit_course_for_review(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_course_submission(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.approve_course_revision(uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.approve_course_revision(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.set_assessment_answer_key(uuid, uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.set_assessment_answer_key(uuid, uuid)
  TO authenticated;
