-- Academi staged course revisions.
-- Forward-only migration: keep the existing published course and curriculum as
-- the public version until an administrator promotes a complete revision.
-- All revision snapshots and promotion decisions are enforced in PostgreSQL;
-- no hosted project is connected or modified by this migration.

CREATE TYPE public.course_revision_status AS ENUM (
  'draft',
  'pending_review',
  'approved',
  'rejected',
  'cancelled'
);

-- A monotonic version detects any live-course or curriculum change made after
-- a revision snapshot was created. The column is not client-writable.
ALTER TABLE public.courses
  ADD COLUMN content_version bigint NOT NULL DEFAULT 1,
  ADD CONSTRAINT courses_content_version_positive CHECK (content_version > 0);

-- Promotion may reorder rows while preserving their IDs. Deferrable uniqueness
-- lets the transaction apply a full reorder without exposing intermediate data.
ALTER TABLE public.course_outcomes
  DROP CONSTRAINT course_outcomes_course_id_position_key,
  ADD CONSTRAINT course_outcomes_course_id_position_key
    UNIQUE (course_id, position) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE public.course_sections
  DROP CONSTRAINT course_sections_course_id_position_key,
  ADD CONSTRAINT course_sections_course_id_position_key
    UNIQUE (course_id, position) DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE public.lessons
  DROP CONSTRAINT lessons_section_id_position_key,
  ADD CONSTRAINT lessons_section_id_position_key
    UNIQUE (section_id, position) DEFERRABLE INITIALLY IMMEDIATE;

CREATE TABLE public.course_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL REFERENCES public.courses (id) ON DELETE RESTRICT,
  instructor_id uuid NOT NULL
    REFERENCES public.instructor_profiles (user_id) ON DELETE RESTRICT,
  base_content_version bigint NOT NULL CHECK (base_content_version > 0),
  category_id uuid NOT NULL REFERENCES public.categories (id) ON DELETE RESTRICT,
  slug text NOT NULL CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 180),
  subtitle text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  level text NOT NULL DEFAULT 'beginner'
    CHECK (level IN ('beginner', 'intermediate', 'advanced', 'all_levels')),
  language_code text NOT NULL DEFAULT 'en'
    CHECK (language_code ~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  status public.course_revision_status NOT NULL DEFAULT 'draft',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES public.profiles (id) ON DELETE RESTRICT,
  review_reason text CHECK (review_reason IS NULL OR char_length(review_reason) <= 2000),
  CONSTRAINT course_revisions_state_check CHECK (
    (
      status = 'draft'::public.course_revision_status
      AND submitted_at IS NULL AND reviewed_at IS NULL
      AND reviewed_by IS NULL AND review_reason IS NULL
    ) OR (
      status = 'pending_review'::public.course_revision_status
      AND submitted_at IS NOT NULL AND reviewed_at IS NULL
      AND reviewed_by IS NULL AND review_reason IS NULL
    ) OR (
      status = 'approved'::public.course_revision_status
      AND submitted_at IS NOT NULL AND reviewed_at IS NOT NULL
      AND reviewed_by IS NOT NULL AND review_reason IS NULL
    ) OR (
      status = 'rejected'::public.course_revision_status
      AND submitted_at IS NOT NULL AND reviewed_at IS NOT NULL
      AND reviewed_by IS NOT NULL AND review_reason IS NOT NULL
      AND char_length(btrim(review_reason)) BETWEEN 1 AND 2000
    ) OR (
      status = 'cancelled'::public.course_revision_status
      AND submitted_at IS NULL AND reviewed_at IS NULL
      AND reviewed_by IS NULL AND review_reason IS NULL
    )
  )
);

-- Only one editable or submitted revision may exist for a course at a time.
-- Historical approved/rejected/cancelled rows remain available to their owner
-- and administrators, but do not block a new revision.
CREATE UNIQUE INDEX course_revisions_one_active_per_course_idx
  ON public.course_revisions (course_id)
  WHERE status IN (
    'draft'::public.course_revision_status,
    'pending_review'::public.course_revision_status
  );
CREATE INDEX course_revisions_owner_status_idx
  ON public.course_revisions (instructor_id, status, created_at DESC);

CREATE TABLE public.course_revision_outcomes (
  revision_id uuid NOT NULL
    REFERENCES public.course_revisions (id) ON DELETE CASCADE,
  outcome_id uuid NOT NULL DEFAULT gen_random_uuid(),
  position integer NOT NULL CHECK (position > 0),
  outcome text NOT NULL CHECK (char_length(btrim(outcome)) BETWEEN 1 AND 500),
  PRIMARY KEY (revision_id, outcome_id),
  CONSTRAINT course_revision_outcomes_position_key
    UNIQUE (revision_id, position) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE TABLE public.course_revision_sections (
  revision_id uuid NOT NULL
    REFERENCES public.course_revisions (id) ON DELETE CASCADE,
  section_id uuid NOT NULL DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 180),
  position integer NOT NULL CHECK (position > 0),
  PRIMARY KEY (revision_id, section_id),
  CONSTRAINT course_revision_sections_position_key
    UNIQUE (revision_id, position) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE TABLE public.course_revision_lessons (
  revision_id uuid NOT NULL,
  lesson_id uuid NOT NULL DEFAULT gen_random_uuid(),
  section_id uuid NOT NULL,
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 180),
  summary text NOT NULL DEFAULT '',
  content_type public.lesson_content_type NOT NULL DEFAULT 'video',
  position integer NOT NULL CHECK (position > 0),
  duration_seconds integer CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
  is_preview boolean NOT NULL DEFAULT false,
  PRIMARY KEY (revision_id, lesson_id),
  CONSTRAINT course_revision_lessons_section_fk
    FOREIGN KEY (revision_id, section_id)
    REFERENCES public.course_revision_sections (revision_id, section_id)
    ON DELETE RESTRICT,
  CONSTRAINT course_revision_lessons_position_key
    UNIQUE (revision_id, section_id, position) DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX course_revision_lessons_section_idx
  ON public.course_revision_lessons (revision_id, section_id, position);

-- Helpers used by RLS and trigger guards. SECURITY DEFINER helpers have a
-- fixed search_path and accept only the current authenticated subject.
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
          AND c.status <> 'published'::public.course_status
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION private.can_view_course_revision(_revision_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.course_revisions AS r
    WHERE r.id = _revision_id
      AND (
        private.has_role('admin'::public.app_role)
        OR (
          r.instructor_id = (SELECT auth.uid())
          AND private.has_role('instructor'::public.app_role)
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION private.can_edit_course_revision(_revision_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.course_revisions AS r
    JOIN public.courses AS c ON c.id = r.course_id
    WHERE r.id = _revision_id
      AND r.status = 'draft'::public.course_revision_status
      AND r.instructor_id = (SELECT auth.uid())
      AND c.instructor_id = r.instructor_id
      AND c.status = 'published'::public.course_status
      AND private.has_role('instructor'::public.app_role)
  );
$$;

-- Every update to a course row advances its version. Child-table triggers below
-- lock the owning course before changing live data, then update this counter;
-- this serializes edits against revision approval and closes stale-check races.
CREATE FUNCTION private.bump_course_content_version()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.content_version := OLD.content_version + 1;
  RETURN NEW;
END;
$$;

CREATE FUNCTION private.lock_course_content_for_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_old_course_id uuid;
  v_new_course_id uuid;
  v_course_id uuid;
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
    PERFORM 1
    FROM public.courses AS c
    WHERE c.id = v_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'The live course for this content row does not exist.';
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

-- Assessment descendants do not carry course_id directly. Resolve the parent,
-- lock parent rows in stable order, then lock/version the course before the row
-- change. Parent locks prevent a concurrent assessment/question move from
-- changing which course receives the version bump. Missing parents are possible
-- only during a cascade; the parent trigger already locks and versions the course.
CREATE FUNCTION private.lock_assessment_content_for_change()
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
    PERFORM 1
    FROM public.courses AS c
    WHERE c.id = v_course_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = 'The live course for this assessment content row does not exist.';
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

CREATE TRIGGER courses_bump_content_version
BEFORE UPDATE ON public.courses
FOR EACH ROW EXECUTE FUNCTION private.bump_course_content_version();

CREATE TRIGGER course_outcomes_lock_and_version
BEFORE INSERT OR UPDATE OR DELETE ON public.course_outcomes
FOR EACH ROW EXECUTE FUNCTION private.lock_course_content_for_change();
CREATE TRIGGER course_sections_lock_and_version
BEFORE INSERT OR UPDATE OR DELETE ON public.course_sections
FOR EACH ROW EXECUTE FUNCTION private.lock_course_content_for_change();
CREATE TRIGGER lessons_lock_and_version
BEFORE INSERT OR UPDATE OR DELETE ON public.lessons
FOR EACH ROW EXECUTE FUNCTION private.lock_course_content_for_change();
CREATE TRIGGER assessments_lock_and_version
BEFORE INSERT OR UPDATE OR DELETE ON public.assessments
FOR EACH ROW EXECUTE FUNCTION private.lock_course_content_for_change();

CREATE TRIGGER assessment_questions_lock_and_version
BEFORE INSERT OR UPDATE OR DELETE ON public.assessment_questions
FOR EACH ROW EXECUTE FUNCTION private.lock_assessment_content_for_change();
CREATE TRIGGER assessment_options_lock_and_version
BEFORE INSERT OR UPDATE OR DELETE ON public.assessment_options
FOR EACH ROW EXECUTE FUNCTION private.lock_assessment_content_for_change();
CREATE TRIGGER assessment_answer_keys_lock_and_version
BEFORE INSERT OR UPDATE OR DELETE ON private.assessment_answer_keys
FOR EACH ROW EXECUTE FUNCTION private.lock_assessment_content_for_change();

-- This trigger is a second line of defense behind RLS and column grants. It
-- prevents edits to submitted snapshots, validates state transitions, binds
-- every revision to its instructor owner, and reserves decisions to admins.
CREATE FUNCTION private.guard_course_revision_header()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_course_owner uuid;
  v_course_status public.course_status;
  v_course_version bigint;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF v_actor_id IS NULL
       OR NEW.instructor_id <> v_actor_id
       OR NOT private.has_role('instructor'::public.app_role)
       OR NEW.status <> 'draft'::public.course_revision_status
       OR NEW.submitted_at IS NOT NULL
       OR NEW.reviewed_at IS NOT NULL
       OR NEW.reviewed_by IS NOT NULL
       OR NEW.review_reason IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owning instructor can create a draft course revision.';
    END IF;

    SELECT c.instructor_id, c.status, c.content_version
      INTO v_course_owner, v_course_status, v_course_version
    FROM public.courses AS c
    WHERE c.id = NEW.course_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_course_owner <> v_actor_id
       OR v_course_status <> 'published'::public.course_status
       OR NEW.base_content_version <> v_course_version THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'A revision can only snapshot the instructor-owned published course.';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.course_id IS DISTINCT FROM OLD.course_id
     OR NEW.instructor_id IS DISTINCT FROM OLD.instructor_id
     OR NEW.base_content_version IS DISTINCT FROM OLD.base_content_version
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Course revision identity and base version are immutable.';
  END IF;

  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    IF OLD.status <> 'draft'::public.course_revision_status
       OR NOT private.can_edit_course_revision(OLD.id)
       OR NEW.submitted_at IS DISTINCT FROM OLD.submitted_at
       OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at
       OR NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
       OR NEW.review_reason IS DISTINCT FROM OLD.review_reason THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owning instructor may edit a draft course revision.';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'draft'::public.course_revision_status
     AND NEW.status = 'pending_review'::public.course_revision_status THEN
    IF NOT private.can_edit_course_revision(OLD.id)
       OR NEW.submitted_at IS NULL
       OR NEW.reviewed_at IS NOT NULL
       OR NEW.reviewed_by IS NOT NULL
       OR NEW.review_reason IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owning instructor can submit a draft revision.';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'draft'::public.course_revision_status
     AND NEW.status = 'cancelled'::public.course_revision_status THEN
    IF NOT private.can_edit_course_revision(OLD.id)
       OR NEW.submitted_at IS NOT NULL
       OR NEW.reviewed_at IS NOT NULL
       OR NEW.reviewed_by IS NOT NULL
       OR NEW.review_reason IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owning instructor can cancel a draft revision.';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'pending_review'::public.course_revision_status
     AND NEW.status IN (
       'approved'::public.course_revision_status,
       'rejected'::public.course_revision_status
     ) THEN
    IF v_actor_id IS NULL
       OR NOT private.has_role('admin'::public.app_role)
       OR NEW.reviewed_at IS NULL
       OR NEW.reviewed_by IS DISTINCT FROM v_actor_id
       OR (NEW.status = 'approved'::public.course_revision_status AND NEW.review_reason IS NOT NULL)
       OR (NEW.status = 'rejected'::public.course_revision_status
           AND (NEW.review_reason IS NULL OR char_length(btrim(NEW.review_reason)) NOT BETWEEN 1 AND 2000)) THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only an administrator can approve or reject a submitted revision.';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'This course revision state transition is not allowed.';
END;
$$;

CREATE FUNCTION private.guard_course_revision_content()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_revision_id uuid;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.revision_id IS DISTINCT FROM OLD.revision_id THEN
      RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'A staged row cannot be moved to another revision.';
    END IF;
    IF TG_TABLE_NAME = 'course_revision_outcomes' THEN
      IF NEW.outcome_id IS DISTINCT FROM OLD.outcome_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'A staged outcome ID is immutable.';
      END IF;
    ELSIF TG_TABLE_NAME = 'course_revision_sections' THEN
      IF NEW.section_id IS DISTINCT FROM OLD.section_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'A staged section ID is immutable.';
      END IF;
    ELSIF TG_TABLE_NAME = 'course_revision_lessons' THEN
      IF NEW.lesson_id IS DISTINCT FROM OLD.lesson_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'A staged lesson ID is immutable.';
      END IF;
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_revision_id := OLD.revision_id;
  ELSE
    v_revision_id := NEW.revision_id;
  END IF;

  -- Serialize staged edits with submit/decision transitions. Once submitted,
  -- the instructor cannot mutate any staged row, even through direct SQL/API.
  PERFORM 1
  FROM public.course_revisions AS r
  WHERE r.id = v_revision_id
  FOR UPDATE;

  IF NOT FOUND OR NOT private.can_edit_course_revision(v_revision_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owning instructor may edit staged content while the revision is a draft.';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER course_revisions_guard
BEFORE INSERT OR UPDATE ON public.course_revisions
FOR EACH ROW EXECUTE FUNCTION private.guard_course_revision_header();
CREATE TRIGGER course_revision_outcomes_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.course_revision_outcomes
FOR EACH ROW EXECUTE FUNCTION private.guard_course_revision_content();
CREATE TRIGGER course_revision_sections_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.course_revision_sections
FOR EACH ROW EXECUTE FUNCTION private.guard_course_revision_content();
CREATE TRIGGER course_revision_lessons_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.course_revision_lessons
FOR EACH ROW EXECUTE FUNCTION private.guard_course_revision_content();

-- Instructors can edit a published course only through a revision snapshot.
-- Administrators retain direct management access, and the original draft ->
-- pending_review -> admin-published workflow remains unchanged.
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
          AND c.status <> 'published'::public.course_status
          AND c.instructor_id = (SELECT auth.uid())
          AND private.has_role('instructor'::public.app_role)
        )
      )
  );
$$;

DROP POLICY courses_owner_or_admin_update ON public.courses;
CREATE POLICY courses_owner_or_admin_update
ON public.courses FOR UPDATE TO authenticated
USING (private.can_edit_course_content(id))
WITH CHECK (private.can_edit_course_content(id));

DROP POLICY course_outcomes_owner_manage ON public.course_outcomes;
CREATE POLICY course_outcomes_owner_manage
ON public.course_outcomes FOR ALL TO authenticated
USING (private.can_edit_course_content(course_id))
WITH CHECK (private.can_edit_course_content(course_id));

DROP POLICY course_sections_owner_manage ON public.course_sections;
CREATE POLICY course_sections_owner_manage
ON public.course_sections FOR ALL TO authenticated
USING (private.can_edit_course_content(course_id))
WITH CHECK (private.can_edit_course_content(course_id));

DROP POLICY lessons_owner_manage ON public.lessons;
CREATE POLICY lessons_owner_manage
ON public.lessons FOR ALL TO authenticated
USING (private.can_edit_course_content(course_id))
WITH CHECK (private.can_edit_course_content(course_id));

DROP POLICY assessments_owner_manage ON public.assessments;
CREATE POLICY assessments_owner_manage
ON public.assessments FOR ALL TO authenticated
USING (
  private.has_role('admin'::public.app_role)
  OR (
    status = 'draft'::public.assessment_status
    AND private.can_edit_course_content(course_id)
  )
)
WITH CHECK (
  private.has_role('admin'::public.app_role)
  OR (
    status = 'draft'::public.assessment_status
    AND private.can_edit_course_content(course_id)
  )
);

DROP POLICY IF EXISTS course_revisions_owner_admin_read ON public.course_revisions;
CREATE POLICY course_revisions_owner_admin_read
ON public.course_revisions FOR SELECT TO authenticated
USING (private.can_view_course_revision(id));

CREATE POLICY course_revisions_owner_draft_update
ON public.course_revisions FOR UPDATE TO authenticated
USING (private.can_edit_course_revision(id))
WITH CHECK (private.can_edit_course_revision(id));

CREATE POLICY course_revision_outcomes_owner_admin_read
ON public.course_revision_outcomes FOR SELECT TO authenticated
USING (private.can_view_course_revision(revision_id));
CREATE POLICY course_revision_outcomes_owner_draft_insert
ON public.course_revision_outcomes FOR INSERT TO authenticated
WITH CHECK (private.can_edit_course_revision(revision_id));
CREATE POLICY course_revision_outcomes_owner_draft_update
ON public.course_revision_outcomes FOR UPDATE TO authenticated
USING (private.can_edit_course_revision(revision_id))
WITH CHECK (private.can_edit_course_revision(revision_id));
CREATE POLICY course_revision_outcomes_owner_draft_delete
ON public.course_revision_outcomes FOR DELETE TO authenticated
USING (private.can_edit_course_revision(revision_id));

CREATE POLICY course_revision_sections_owner_admin_read
ON public.course_revision_sections FOR SELECT TO authenticated
USING (private.can_view_course_revision(revision_id));
CREATE POLICY course_revision_sections_owner_draft_insert
ON public.course_revision_sections FOR INSERT TO authenticated
WITH CHECK (private.can_edit_course_revision(revision_id));
CREATE POLICY course_revision_sections_owner_draft_update
ON public.course_revision_sections FOR UPDATE TO authenticated
USING (private.can_edit_course_revision(revision_id))
WITH CHECK (private.can_edit_course_revision(revision_id));
CREATE POLICY course_revision_sections_owner_draft_delete
ON public.course_revision_sections FOR DELETE TO authenticated
USING (private.can_edit_course_revision(revision_id));

CREATE POLICY course_revision_lessons_owner_admin_read
ON public.course_revision_lessons FOR SELECT TO authenticated
USING (private.can_view_course_revision(revision_id));
CREATE POLICY course_revision_lessons_owner_draft_insert
ON public.course_revision_lessons FOR INSERT TO authenticated
WITH CHECK (private.can_edit_course_revision(revision_id));
CREATE POLICY course_revision_lessons_owner_draft_update
ON public.course_revision_lessons FOR UPDATE TO authenticated
USING (private.can_edit_course_revision(revision_id))
WITH CHECK (private.can_edit_course_revision(revision_id));
CREATE POLICY course_revision_lessons_owner_draft_delete
ON public.course_revision_lessons FOR DELETE TO authenticated
USING (private.can_edit_course_revision(revision_id));

-- Snapshot the currently published course and curriculum. The course row lock
-- serializes this read with every live-content write before base version capture.
CREATE FUNCTION public.create_course_revision(_course_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_course public.courses%ROWTYPE;
  v_revision_id uuid;
BEGIN
  IF v_actor_id IS NULL OR NOT private.has_role('instructor'::public.app_role) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Instructor permission is required to create a course revision.';
  END IF;

  SELECT * INTO v_course
  FROM public.courses AS c
  WHERE c.id = _course_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_course.instructor_id <> v_actor_id
     OR v_course.status <> 'published'::public.course_status THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only the owning instructor can revise a published course.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.course_revisions AS r
    WHERE r.course_id = v_course.id
      AND r.status IN (
        'draft'::public.course_revision_status,
        'pending_review'::public.course_revision_status
      )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'This course already has an active revision.';
  END IF;

  INSERT INTO public.course_revisions (
    course_id, instructor_id, base_content_version, category_id,
    slug, title, subtitle, description, level, language_code
  ) VALUES (
    v_course.id, v_actor_id, v_course.content_version, v_course.category_id,
    v_course.slug, v_course.title, v_course.subtitle, v_course.description,
    v_course.level, v_course.language_code
  ) RETURNING id INTO v_revision_id;

  INSERT INTO public.course_revision_outcomes (revision_id, outcome_id, position, outcome)
  SELECT v_revision_id, o.id, o.position, o.outcome
  FROM public.course_outcomes AS o
  WHERE o.course_id = v_course.id;

  INSERT INTO public.course_revision_sections (revision_id, section_id, title, position)
  SELECT v_revision_id, s.id, s.title, s.position
  FROM public.course_sections AS s
  WHERE s.course_id = v_course.id;

  INSERT INTO public.course_revision_lessons (
    revision_id, lesson_id, section_id, title, summary, content_type,
    position, duration_seconds, is_preview
  )
  SELECT v_revision_id, l.id, l.section_id, l.title, l.summary, l.content_type,
         l.position, l.duration_seconds, l.is_preview
  FROM public.lessons AS l
  WHERE l.course_id = v_course.id;

  RETURN v_revision_id;
END;
$$;

CREATE FUNCTION public.submit_course_revision(_revision_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_revision public.course_revisions%ROWTYPE;
BEGIN
  IF v_actor_id IS NULL OR NOT private.has_role('instructor'::public.app_role) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Instructor permission is required to submit a course revision.';
  END IF;

  SELECT * INTO v_revision
  FROM public.course_revisions AS r
  WHERE r.id = _revision_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_revision.instructor_id <> v_actor_id
     OR NOT private.can_edit_course_revision(v_revision.id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'You cannot submit this course revision.';
  END IF;
  IF v_revision.status <> 'draft'::public.course_revision_status THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'Only a draft course revision can be submitted.';
  END IF;

  UPDATE public.course_revisions
  SET status = 'pending_review'::public.course_revision_status,
      submitted_at = pg_catalog.clock_timestamp()
  WHERE id = v_revision.id;
END;
$$;

CREATE FUNCTION public.cancel_course_revision(_revision_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_revision public.course_revisions%ROWTYPE;
BEGIN
  IF v_actor_id IS NULL OR NOT private.has_role('instructor'::public.app_role) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Instructor permission is required to cancel a course revision.';
  END IF;

  SELECT * INTO v_revision
  FROM public.course_revisions AS r
  WHERE r.id = _revision_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_revision.instructor_id <> v_actor_id
     OR NOT private.can_edit_course_revision(v_revision.id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'You cannot cancel this course revision.';
  END IF;
  IF v_revision.status <> 'draft'::public.course_revision_status THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'Only a draft course revision can be cancelled.';
  END IF;

  UPDATE public.course_revisions
  SET status = 'cancelled'::public.course_revision_status
  WHERE id = v_revision.id;
END;
$$;

-- An unsafe or stale decision is recorded as a rejection and returns its reason
-- before any live rows are written. Any unexpected SQL/constraint error aborts
-- the function statement, rolling back all course, curriculum, and status work.
CREATE FUNCTION public.approve_course_revision(_revision_id uuid)
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

  -- Lock lessons the proposal removes. This serializes the safety check with
  -- learner progress FK inserts; an insert that wins first is seen below, and
  -- one that loses the lock cannot create a dangling progress row.
  PERFORM 1
  FROM public.lessons AS live
  WHERE live.course_id = v_course.id
    AND NOT EXISTS (
      SELECT 1 FROM public.course_revision_lessons AS staged
      WHERE staged.revision_id = v_revision.id
        AND staged.lesson_id = live.id
    )
  ORDER BY live.id
  FOR UPDATE;

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

CREATE FUNCTION public.reject_course_revision(_revision_id uuid, _reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_revision public.course_revisions%ROWTYPE;
  v_reason text := pg_catalog.btrim(_reason);
BEGIN
  IF v_actor_id IS NULL OR NOT private.has_role('admin'::public.app_role) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Administrator permission is required to reject a course revision.';
  END IF;
  IF v_reason IS NULL OR char_length(v_reason) NOT BETWEEN 1 AND 2000 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'A rejection reason of 1 to 2000 characters is required.';
  END IF;

  SELECT * INTO v_revision
  FROM public.course_revisions AS r
  WHERE r.id = _revision_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Course revision not found.';
  END IF;
  IF v_revision.status <> 'pending_review'::public.course_revision_status THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'Only a submitted revision can be rejected.';
  END IF;

  UPDATE public.course_revisions
  SET status = 'rejected'::public.course_revision_status,
      reviewed_at = pg_catalog.clock_timestamp(),
      reviewed_by = v_actor_id,
      review_reason = v_reason
  WHERE id = v_revision.id;
END;
$$;

CREATE TRIGGER course_revisions_set_updated_at
BEFORE UPDATE ON public.course_revisions
FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

ALTER TABLE public.course_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_revision_outcomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_revision_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_revision_lessons ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
  public.course_revisions,
  public.course_revision_outcomes,
  public.course_revision_sections,
  public.course_revision_lessons
FROM PUBLIC, anon, authenticated, service_role;
REVOKE UPDATE (content_version) ON public.courses
FROM PUBLIC, anon, authenticated, service_role;

GRANT USAGE ON TYPE public.course_revision_status TO authenticated;
GRANT SELECT ON
  public.course_revisions,
  public.course_revision_outcomes,
  public.course_revision_sections,
  public.course_revision_lessons
TO authenticated;
GRANT UPDATE (
  category_id, slug, title, subtitle, description, level, language_code
) ON public.course_revisions TO authenticated;
GRANT INSERT (revision_id, outcome_id, position, outcome),
      UPDATE (position, outcome),
      DELETE ON public.course_revision_outcomes TO authenticated;
GRANT INSERT (revision_id, section_id, title, position),
      UPDATE (title, position),
      DELETE ON public.course_revision_sections TO authenticated;
GRANT INSERT (
  revision_id, lesson_id, section_id, title, summary, content_type,
  position, duration_seconds, is_preview
),
      UPDATE (
        section_id, title, summary, content_type, position,
        duration_seconds, is_preview
      ),
      DELETE ON public.course_revision_lessons TO authenticated;

-- Keep SECURITY DEFINER entry points non-public and explicitly grant only the
-- intended authenticated actor class. Every function still rechecks auth.uid().
REVOKE ALL ON FUNCTION private.can_edit_course_content(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION private.can_view_course_revision(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION private.can_edit_course_revision(uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.can_edit_course_content(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_view_course_revision(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_edit_course_revision(uuid) TO authenticated;

REVOKE ALL ON FUNCTION private.bump_course_content_version()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL
 ON FUNCTION private.lock_course_content_for_change()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.lock_assessment_content_for_change()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.guard_course_revision_header()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.guard_course_revision_content()
  FROM PUBLIC, anon, authenticated, service_role;

-- A draft assessment on a published course is no longer a side door for
-- instructor edits. The answer-key RPC takes the course lock before checking
-- permissions, so an admin publication/revision decision cannot race it.
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
  v_assessment_id uuid;
  v_course_id uuid;
  v_course_status public.course_status;
BEGIN
  SELECT a.id, a.course_id, c.status
    INTO v_assessment_id, v_course_id, v_course_status
  FROM public.assessments AS a
  JOIN public.assessment_questions AS q ON q.assessment_id = a.id
  JOIN public.courses AS c ON c.id = a.course_id
  WHERE q.id = _question_id
  FOR UPDATE OF c;

  IF NOT FOUND OR NOT private.can_edit_assessment(v_assessment_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'You cannot manage this assessment.';
  END IF;

  INSERT INTO private.assessment_answer_keys (question_id, correct_option_id)
  VALUES (_question_id, _correct_option_id)
  ON CONFLICT (question_id) DO UPDATE
    SET correct_option_id = EXCLUDED.correct_option_id,
        updated_at = pg_catalog.now();
END;
$$;

REVOKE ALL ON FUNCTION public.create_course_revision(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.submit_course_revision(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.cancel_course_revision(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.approve_course_revision(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.reject_course_revision(uuid, text)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.set_assessment_answer_key(uuid, uuid)
  FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.create_course_revision(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_course_revision(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_course_revision(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_course_revision(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_course_revision(uuid, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_assessment_answer_key(uuid, uuid)
  TO authenticated;
