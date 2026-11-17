-- Academi LMS schema and access-control foundation.
-- Review only: do not apply to a hosted project until the user approves the
-- target market/region and the SQL. No credentials, project ref, or external
-- connection are used by this migration.
--
-- The private schema must remain absent from Supabase's exposed Data API
-- schemas. The service_role key is intentionally not granted direct access to
-- these tables. User-facing privileged operations use narrowly scoped
-- SECURITY DEFINER functions that validate auth.uid() and database roles;
-- first-admin bootstrap is a separate owner-only operation with no client grant.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA private TO anon, authenticated;

CREATE TYPE public.app_role AS ENUM ('student', 'instructor', 'admin');
CREATE TYPE public.course_status AS ENUM (
  'draft',
  'pending_review',
  'published',
  'rejected',
  'archived'
);
CREATE TYPE public.enrollment_status AS ENUM ('active', 'completed', 'cancelled');
CREATE TYPE public.lesson_content_type AS ENUM ('video', 'reading', 'quiz');
CREATE TYPE public.assessment_status AS ENUM ('draft', 'published', 'archived');
CREATE TYPE public.attempt_status AS ENUM ('in_progress', 'submitted');

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  display_name text NOT NULL
    CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 100),
  avatar_storage_key text,
  locale text NOT NULL DEFAULT 'en'
    CHECK (char_length(locale) BETWEEN 2 AND 35),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Auth metadata is user-controlled and is used only as a display label, never
-- as an authorization source. The function owner writes the matching profile.
CREATE FUNCTION private.provision_profile_for_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_display_name text;
BEGIN
  v_display_name := NULLIF(
    pg_catalog.btrim(NEW.raw_user_meta_data ->> 'display_name'), ''
  );

  IF v_display_name IS NULL THEN
    v_display_name := NULLIF(
      pg_catalog.btrim(NEW.raw_user_meta_data ->> 'full_name'), ''
    );
  END IF;

  IF v_display_name IS NULL THEN
    v_display_name := NULLIF(
      pg_catalog.btrim(pg_catalog.split_part(COALESCE(NEW.email, ''), '@', 1)),
      ''
    );
  END IF;

  INSERT INTO public.profiles (id, display_name)
  VALUES (
    NEW.id,
    pg_catalog.left(COALESCE(v_display_name, 'Learner'), 100)
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created_provision_profile
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION private.provision_profile_for_auth_user();

CREATE TABLE public.user_roles (
  user_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  granted_by uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  granted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role),
  CONSTRAINT user_roles_no_self_grant CHECK (granted_by IS NULL OR granted_by <> user_id)
);

-- One-time bootstrap for the first admin. EXECUTE is revoked from all client
-- roles below; only the trusted database object owner can invoke this function.
CREATE FUNCTION private.bootstrap_first_admin(_target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF _target_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'A target Auth user is required.';
  END IF;

  -- Share the role-management lock so bootstrap cannot race another admin grant.
  PERFORM pg_catalog.pg_advisory_xact_lock(731915, 1);

  IF NOT EXISTS (
    SELECT 1 FROM auth.users AS u WHERE u.id = _target_user_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'The target Auth user does not exist.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_roles AS ur
    WHERE ur.role = 'admin'::public.app_role
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'An administrator is already provisioned.';
  END IF;

  -- Normally created by the auth.users trigger. This also covers an Auth user
  -- that existed before the trigger was installed, without changing a profile.
  INSERT INTO public.profiles (id, display_name)
  VALUES (_target_user_id, 'Academi Administrator')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.user_roles (user_id, role, granted_by)
  VALUES (_target_user_id, 'admin'::public.app_role, NULL);
END;
$$;

CREATE TABLE public.instructor_profiles (
  user_id uuid PRIMARY KEY REFERENCES public.profiles (id) ON DELETE CASCADE,
  public_name text NOT NULL
    CHECK (char_length(btrim(public_name)) BETWEEN 1 AND 100),
  biography text NOT NULL DEFAULT '',
  country_code text
    CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id uuid REFERENCES public.categories (id) ON DELETE RESTRICT,
  name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 100),
  slug text NOT NULL UNIQUE
    CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.courses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  instructor_id uuid NOT NULL
    REFERENCES public.instructor_profiles (user_id) ON DELETE RESTRICT,
  category_id uuid NOT NULL
    REFERENCES public.categories (id) ON DELETE RESTRICT,
  slug text NOT NULL UNIQUE
    CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 180),
  subtitle text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  level text NOT NULL DEFAULT 'beginner'
    CHECK (level IN ('beginner', 'intermediate', 'advanced', 'all_levels')),
  language_code text NOT NULL DEFAULT 'en'
    CHECK (language_code ~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  status public.course_status NOT NULL DEFAULT 'draft',
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.course_outcomes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL REFERENCES public.courses (id) ON DELETE CASCADE,
  position integer NOT NULL CHECK (position > 0),
  outcome text NOT NULL CHECK (char_length(btrim(outcome)) BETWEEN 1 AND 500),
  UNIQUE (course_id, position)
);

CREATE TABLE public.course_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL REFERENCES public.courses (id) ON DELETE CASCADE,
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 180),
  position integer NOT NULL CHECK (position > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (course_id, position),
  UNIQUE (id, course_id)
);

CREATE TABLE public.lessons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL,
  section_id uuid NOT NULL,
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 180),
  summary text NOT NULL DEFAULT '',
  content_type public.lesson_content_type NOT NULL DEFAULT 'video',
  position integer NOT NULL CHECK (position > 0),
  duration_seconds integer CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
  is_preview boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT lessons_section_course_fk
    FOREIGN KEY (section_id, course_id)
    REFERENCES public.course_sections (id, course_id) ON DELETE CASCADE,
  UNIQUE (section_id, position),
  UNIQUE (id, course_id)
);

CREATE TABLE public.enrollments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  course_id uuid NOT NULL REFERENCES public.courses (id) ON DELETE RESTRICT,
  status public.enrollment_status NOT NULL DEFAULT 'active',
  enrolled_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  CONSTRAINT enrollments_completed_timestamp_check
    CHECK (status <> 'completed' OR completed_at IS NOT NULL),
  UNIQUE (student_id, course_id),
  UNIQUE (id, course_id),
  UNIQUE (id, student_id, course_id)
);

CREATE TABLE public.lesson_progress (
  enrollment_id uuid NOT NULL,
  course_id uuid NOT NULL,
  lesson_id uuid NOT NULL,
  last_position_seconds integer NOT NULL DEFAULT 0
    CHECK (last_position_seconds >= 0),
  completed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (enrollment_id, lesson_id),
  CONSTRAINT lesson_progress_enrollment_course_fk
    FOREIGN KEY (enrollment_id, course_id)
    REFERENCES public.enrollments (id, course_id) ON DELETE CASCADE,
  CONSTRAINT lesson_progress_lesson_course_fk
    FOREIGN KEY (lesson_id, course_id)
    REFERENCES public.lessons (id, course_id) ON DELETE RESTRICT
);

CREATE TABLE public.assessments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL REFERENCES public.courses (id) ON DELETE CASCADE,
  lesson_id uuid,
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 180),
  status public.assessment_status NOT NULL DEFAULT 'draft',
  passing_score_percent numeric(5, 2) NOT NULL DEFAULT 70.00
    CHECK (passing_score_percent BETWEEN 0 AND 100),
  max_attempts integer CHECK (max_attempts IS NULL OR max_attempts > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT assessments_lesson_course_fk
    FOREIGN KEY (lesson_id, course_id)
    REFERENCES public.lessons (id, course_id) ON DELETE CASCADE,
  UNIQUE (id, course_id)
);

CREATE TABLE public.assessment_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assessment_id uuid NOT NULL REFERENCES public.assessments (id) ON DELETE CASCADE,
  position integer NOT NULL CHECK (position > 0),
  question_type text NOT NULL DEFAULT 'single_choice'
    CHECK (question_type = 'single_choice'),
  prompt text NOT NULL CHECK (char_length(btrim(prompt)) BETWEEN 1 AND 4000),
  points numeric(7, 2) NOT NULL DEFAULT 1.00 CHECK (points > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (assessment_id, position),
  UNIQUE (id, assessment_id)
);

CREATE TABLE public.assessment_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id uuid NOT NULL
    REFERENCES public.assessment_questions (id) ON DELETE CASCADE,
  position integer NOT NULL CHECK (position > 0),
  option_text text NOT NULL CHECK (char_length(btrim(option_text)) BETWEEN 1 AND 2000),
  UNIQUE (question_id, position),
  UNIQUE (id, question_id)
);

-- Deliberately outside the exposed public schema. Learner-readable options do
-- not contain an is_correct flag. Only trusted functions can access answer keys.
CREATE TABLE private.assessment_answer_keys (
  question_id uuid PRIMARY KEY
    REFERENCES public.assessment_questions (id) ON DELETE CASCADE,
  correct_option_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT assessment_answer_keys_option_question_fk
    FOREIGN KEY (correct_option_id, question_id)
    REFERENCES public.assessment_options (id, question_id) ON DELETE CASCADE
);

CREATE TABLE public.assessment_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assessment_id uuid NOT NULL,
  student_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  enrollment_id uuid NOT NULL,
  course_id uuid NOT NULL,
  attempt_number integer NOT NULL CHECK (attempt_number > 0),
  status public.attempt_status NOT NULL DEFAULT 'in_progress',
  started_at timestamptz NOT NULL DEFAULT now(),
  submitted_at timestamptz,
  score_percent numeric(5, 2) CHECK (score_percent IS NULL OR score_percent BETWEEN 0 AND 100),
  passed boolean,
  CONSTRAINT assessment_attempts_assessment_course_fk
    FOREIGN KEY (assessment_id, course_id)
    REFERENCES public.assessments (id, course_id) ON DELETE RESTRICT,
  CONSTRAINT assessment_attempts_enrollment_fk
    FOREIGN KEY (enrollment_id, student_id, course_id)
    REFERENCES public.enrollments (id, student_id, course_id) ON DELETE RESTRICT,
  CONSTRAINT assessment_attempts_result_check CHECK (
    (status = 'in_progress' AND submitted_at IS NULL AND score_percent IS NULL AND passed IS NULL)
    OR
    (status = 'submitted' AND submitted_at IS NOT NULL AND score_percent IS NOT NULL AND passed IS NOT NULL)
  ),
  UNIQUE (student_id, assessment_id, attempt_number),
  UNIQUE (id, assessment_id)
);

CREATE TABLE public.assessment_responses (
  attempt_id uuid NOT NULL,
  assessment_id uuid NOT NULL,
  question_id uuid NOT NULL,
  selected_option_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (attempt_id, question_id),
  CONSTRAINT assessment_responses_attempt_fk
    FOREIGN KEY (attempt_id, assessment_id)
    REFERENCES public.assessment_attempts (id, assessment_id) ON DELETE CASCADE,
  CONSTRAINT assessment_responses_question_fk
    FOREIGN KEY (question_id, assessment_id)
    REFERENCES public.assessment_questions (id, assessment_id) ON DELETE RESTRICT,
  CONSTRAINT assessment_responses_option_fk
    FOREIGN KEY (selected_option_id, question_id)
    REFERENCES public.assessment_options (id, question_id) ON DELETE RESTRICT
);

-- Useful lookup indexes. Unique constraints above also create indexes for
-- slugs, parent/position pairs, enrollment uniqueness, and response keys.
CREATE INDEX courses_catalog_filters_idx
  ON public.courses (status, category_id, level, language_code);
CREATE INDEX courses_instructor_status_idx
  ON public.courses (instructor_id, status);
CREATE INDEX courses_category_status_idx
  ON public.courses (category_id, status);
CREATE INDEX categories_parent_idx
  ON public.categories (parent_id);
CREATE INDEX course_outcomes_course_idx
  ON public.course_outcomes (course_id);
CREATE INDEX lessons_course_idx
  ON public.lessons (course_id, section_id, position);
CREATE INDEX instructor_profiles_public_name_idx
  ON public.instructor_profiles (lower(public_name));
CREATE INDEX enrollments_student_status_idx
  ON public.enrollments (student_id, status);
CREATE INDEX enrollments_course_status_idx
  ON public.enrollments (course_id, status);
CREATE INDEX lesson_progress_course_idx
  ON public.lesson_progress (course_id, enrollment_id);
CREATE INDEX assessments_course_status_idx
  ON public.assessments (course_id, status);
CREATE INDEX assessment_attempts_student_assessment_idx
  ON public.assessment_attempts (student_id, assessment_id, started_at DESC);
CREATE INDEX assessment_attempts_assessment_idx
  ON public.assessment_attempts (assessment_id, submitted_at DESC);
CREATE INDEX assessment_responses_question_idx
  ON public.assessment_responses (question_id, assessment_id);
CREATE INDEX assessment_responses_option_idx
  ON public.assessment_responses (selected_option_id, question_id);
CREATE INDEX assessment_answer_keys_option_idx
  ON private.assessment_answer_keys (correct_option_id, question_id);

-- RLS helpers only answer questions about the current JWT user. They do not
-- accept another user's ID as an authorization subject.
CREATE FUNCTION private.has_role(_role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles AS ur
    WHERE ur.user_id = (SELECT auth.uid())
      AND ur.role = _role
  );
$$;

CREATE FUNCTION private.can_manage_course(_course_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.has_role('admin'::public.app_role)
    OR EXISTS (
      SELECT 1
      FROM public.courses AS c
      WHERE c.id = _course_id
        AND c.instructor_id = (SELECT auth.uid())
        AND private.has_role('instructor'::public.app_role)
    );
$$;

CREATE FUNCTION private.can_view_course(_course_id uuid)
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
        c.status = 'published'::public.course_status
        OR private.can_manage_course(c.id)
      )
  );
$$;

CREATE FUNCTION private.can_manage_assessment(_assessment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.assessments AS a
    WHERE a.id = _assessment_id
      AND private.can_manage_course(a.course_id)
  );
$$;

CREATE FUNCTION private.can_edit_assessment(_assessment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.assessments AS a
    WHERE a.id = _assessment_id
      AND (
        private.has_role('admin'::public.app_role)
        OR (
          a.status = 'draft'::public.assessment_status
          AND private.can_manage_course(a.course_id)
        )
      )
  );
$$;

CREATE FUNCTION private.can_view_assessment(_assessment_id uuid)
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
        private.can_manage_course(c.id)
        OR (
          a.status = 'published'::public.assessment_status
          AND c.status = 'published'::public.course_status
          AND EXISTS (
            SELECT 1
            FROM public.enrollments AS e
            WHERE e.course_id = c.id
              AND e.student_id = (SELECT auth.uid())
              AND e.status IN (
                'active'::public.enrollment_status,
                'completed'::public.enrollment_status
              )
          )
        )
      )
  );
$$;

CREATE FUNCTION private.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

-- Publication is a database rule, not a button-state rule: only an admin can
-- approve a course, and approval must follow an explicit pending_review state.
CREATE FUNCTION private.guard_course_publication()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'published'::public.course_status THEN
      RAISE EXCEPTION USING
        ERRCODE = '42501',
        MESSAGE = 'A course must be submitted for review before publication.';
    END IF;

    IF NOT private.has_role('admin'::public.app_role) THEN
      NEW.published_at := NULL;
    END IF;
  ELSE
    IF NEW.status = 'published'::public.course_status
       AND OLD.status IS DISTINCT FROM 'published'::public.course_status THEN
      IF OLD.status <> 'pending_review'::public.course_status THEN
        RAISE EXCEPTION USING
          ERRCODE = '42501',
          MESSAGE = 'Only a course pending review can be published.';
      END IF;

      IF NOT private.has_role('admin'::public.app_role) THEN
        RAISE EXCEPTION USING
          ERRCODE = '42501',
          MESSAGE = 'Only an administrator can approve and publish a course.';
      END IF;
    END IF;

    IF NOT private.has_role('admin'::public.app_role) THEN
      NEW.published_at := OLD.published_at;
    END IF;
  END IF;

  IF NEW.status = 'published'::public.course_status AND NEW.published_at IS NULL THEN
    NEW.published_at := pg_catalog.now();
  END IF;

  RETURN NEW;
END;
$$;

-- Role changes are never direct table writes. Existing admins may manage
-- another user's roles through these guarded database operations, but cannot
-- grant or remove their own roles. The first admin must be bootstrapped by a
-- trusted database operator after a project is deliberately created.
CREATE FUNCTION public.grant_role_to_user(
  _target_user_id uuid,
  _role public.app_role
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
BEGIN
  IF v_actor_id IS NULL OR NOT private.has_role('admin'::public.app_role) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Administrator permission is required.';
  END IF;

  IF _target_user_id IS NULL OR _target_user_id = v_actor_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'You cannot grant a role to yourself.';
  END IF;

  IF _role = 'admin'::public.app_role THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(731915, 1);
  END IF;

  INSERT INTO public.user_roles (user_id, role, granted_by)
  VALUES (_target_user_id, _role, v_actor_id)
  ON CONFLICT (user_id, role) DO NOTHING;
END;
$$;

CREATE FUNCTION public.revoke_role_from_user(
  _target_user_id uuid,
  _role public.app_role
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_admin_count bigint;
BEGIN
  IF v_actor_id IS NULL OR NOT private.has_role('admin'::public.app_role) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Administrator permission is required.';
  END IF;

  IF _target_user_id IS NULL OR _target_user_id = v_actor_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'You cannot change your own roles.';
  END IF;

  IF _role = 'admin'::public.app_role THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(731915, 1);

    IF EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = _target_user_id AND role = 'admin'::public.app_role
    ) THEN
      SELECT count(*) INTO v_admin_count
      FROM public.user_roles
      WHERE role = 'admin'::public.app_role;

      IF v_admin_count <= 1 THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'The last administrator cannot be removed.';
      END IF;
    END IF;
  END IF;

  DELETE FROM public.user_roles
  WHERE user_id = _target_user_id AND role = _role;
END;
$$;

-- Instructors can set an answer key only for their own draft assessment.
-- Published or archived answer keys may be changed only by an administrator.
-- This function never returns the key and the table is not Data-API exposed.
CREATE FUNCTION public.set_assessment_answer_key(
  _question_id uuid,
  _correct_option_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_course_id uuid;
  v_assessment_status public.assessment_status;
BEGIN
  SELECT a.course_id, a.status
    INTO v_course_id, v_assessment_status
  FROM public.assessments AS a
  JOIN public.assessment_questions AS q ON q.assessment_id = a.id
  WHERE q.id = _question_id;

  IF NOT FOUND OR NOT private.can_manage_course(v_course_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'You cannot manage this assessment.';
  END IF;

  IF v_assessment_status <> 'draft'::public.assessment_status
     AND NOT private.has_role('admin'::public.app_role) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Only an administrator can change a non-draft answer key.';
  END IF;

  INSERT INTO private.assessment_answer_keys (question_id, correct_option_id)
  VALUES (_question_id, _correct_option_id)
  ON CONFLICT (question_id) DO UPDATE
    SET correct_option_id = EXCLUDED.correct_option_id,
        updated_at = pg_catalog.now();
END;
$$;

CREATE TRIGGER profiles_set_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER instructor_profiles_set_updated_at
BEFORE UPDATE ON public.instructor_profiles
FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER categories_set_updated_at
BEFORE UPDATE ON public.categories
FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER courses_set_updated_at
BEFORE UPDATE ON public.courses
FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER course_sections_set_updated_at
BEFORE UPDATE ON public.course_sections
FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER lessons_set_updated_at
BEFORE UPDATE ON public.lessons
FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER lesson_progress_set_updated_at
BEFORE UPDATE ON public.lesson_progress
FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER assessments_set_updated_at
BEFORE UPDATE ON public.assessments
FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER answer_keys_set_updated_at
BEFORE UPDATE ON private.assessment_answer_keys
FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER courses_guard_publication
BEFORE INSERT OR UPDATE OF status, published_at ON public.courses
FOR EACH ROW EXECUTE FUNCTION private.guard_course_publication();

-- Enable RLS on every table. The private answer-key table has no client policy.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.instructor_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_outcomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.course_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lessons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lesson_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.assessment_answer_keys ENABLE ROW LEVEL SECURITY;

-- Public profile rows are not exposed. Learners see their own profile; admins
-- may administer profiles. Only non-role profile columns are client-editable.
CREATE POLICY profiles_select_self_or_admin
ON public.profiles FOR SELECT TO authenticated
USING (id = (SELECT auth.uid()) OR private.has_role('admin'::public.app_role));

CREATE POLICY profiles_update_self_or_admin
ON public.profiles FOR UPDATE TO authenticated
USING (id = (SELECT auth.uid()) OR private.has_role('admin'::public.app_role))
WITH CHECK (id = (SELECT auth.uid()) OR private.has_role('admin'::public.app_role));

CREATE POLICY user_roles_select_self_or_admin
ON public.user_roles FOR SELECT TO authenticated
USING (user_id = (SELECT auth.uid()) OR private.has_role('admin'::public.app_role));
-- No INSERT/UPDATE/DELETE policy: role changes go through the guarded functions.

CREATE POLICY instructor_profiles_public_read
ON public.instructor_profiles FOR SELECT TO anon
USING (
  EXISTS (
    SELECT 1 FROM public.courses AS c
    WHERE c.instructor_id = instructor_profiles.user_id
      AND c.status = 'published'::public.course_status
  )
);

CREATE POLICY instructor_profiles_authenticated_read
ON public.instructor_profiles FOR SELECT TO authenticated
USING (
  user_id = (SELECT auth.uid())
  OR private.has_role('admin'::public.app_role)
  OR EXISTS (
    SELECT 1 FROM public.courses AS c
    WHERE c.instructor_id = instructor_profiles.user_id
      AND c.status = 'published'::public.course_status
  )
);

CREATE POLICY instructor_profiles_insert_self
ON public.instructor_profiles FOR INSERT TO authenticated
WITH CHECK (
  user_id = (SELECT auth.uid())
  AND private.has_role('instructor'::public.app_role)
);

CREATE POLICY instructor_profiles_update_self_or_admin
ON public.instructor_profiles FOR UPDATE TO authenticated
USING (
  user_id = (SELECT auth.uid())
  AND private.has_role('instructor'::public.app_role)
  OR private.has_role('admin'::public.app_role)
)
WITH CHECK (
  user_id = (SELECT auth.uid())
  AND private.has_role('instructor'::public.app_role)
  OR private.has_role('admin'::public.app_role)
);

CREATE POLICY categories_public_read
ON public.categories FOR SELECT TO anon, authenticated
USING (true);

CREATE POLICY categories_admin_manage
ON public.categories FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));

CREATE POLICY courses_public_read
ON public.courses FOR SELECT TO anon, authenticated
USING (status = 'published'::public.course_status);

CREATE POLICY courses_owner_or_admin_read
ON public.courses FOR SELECT TO authenticated
USING (private.can_manage_course(id));

CREATE POLICY courses_instructor_insert_draft
ON public.courses FOR INSERT TO authenticated
WITH CHECK (
  instructor_id = (SELECT auth.uid())
  AND private.has_role('instructor'::public.app_role)
  AND status = 'draft'::public.course_status
);

CREATE POLICY courses_owner_or_admin_update
ON public.courses FOR UPDATE TO authenticated
USING (private.can_manage_course(id))
WITH CHECK (private.can_manage_course(id));
-- There is deliberately no course DELETE policy; archive rows to preserve history.

CREATE POLICY course_outcomes_public_or_owner_read
ON public.course_outcomes FOR SELECT TO anon, authenticated
USING (private.can_view_course(course_id));

CREATE POLICY course_outcomes_owner_manage
ON public.course_outcomes FOR ALL TO authenticated
USING (private.can_manage_course(course_id))
WITH CHECK (private.can_manage_course(course_id));

CREATE POLICY course_sections_public_or_owner_read
ON public.course_sections FOR SELECT TO anon, authenticated
USING (private.can_view_course(course_id));

CREATE POLICY course_sections_owner_manage
ON public.course_sections FOR ALL TO authenticated
USING (private.can_manage_course(course_id))
WITH CHECK (private.can_manage_course(course_id));

CREATE POLICY lessons_public_metadata_or_owner_read
ON public.lessons FOR SELECT TO anon, authenticated
USING (private.can_view_course(course_id));

CREATE POLICY lessons_owner_manage
ON public.lessons FOR ALL TO authenticated
USING (private.can_manage_course(course_id))
WITH CHECK (private.can_manage_course(course_id));

CREATE POLICY enrollments_student_owner_or_course_owner_read
ON public.enrollments FOR SELECT TO authenticated
USING (
  student_id = (SELECT auth.uid())
  OR private.can_manage_course(course_id)
);

CREATE POLICY enrollments_admin_manage
ON public.enrollments FOR ALL TO authenticated
USING (private.has_role('admin'::public.app_role))
WITH CHECK (private.has_role('admin'::public.app_role));
-- Students and instructors cannot create or alter enrollments. Automated
-- learner enrollment remains a separately reviewed trusted operation; this
-- milestone deliberately includes no student self-enrollment RPC.

CREATE POLICY lesson_progress_student_or_course_owner_read
ON public.lesson_progress FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.enrollments AS e
    WHERE e.id = lesson_progress.enrollment_id
      AND e.student_id = (SELECT auth.uid())
  )
  OR private.can_manage_course(course_id)
);

CREATE POLICY lesson_progress_student_insert_position
ON public.lesson_progress FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.enrollments AS e
    WHERE e.id = lesson_progress.enrollment_id
      AND e.course_id = lesson_progress.course_id
      AND e.student_id = (SELECT auth.uid())
      AND e.status = 'active'::public.enrollment_status
  )
);

CREATE POLICY lesson_progress_student_update_position
ON public.lesson_progress FOR UPDATE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.enrollments AS e
    WHERE e.id = lesson_progress.enrollment_id
      AND e.course_id = lesson_progress.course_id
      AND e.student_id = (SELECT auth.uid())
      AND e.status = 'active'::public.enrollment_status
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.enrollments AS e
    WHERE e.id = lesson_progress.enrollment_id
      AND e.course_id = lesson_progress.course_id
      AND e.student_id = (SELECT auth.uid())
      AND e.status = 'active'::public.enrollment_status
  )
);
-- Client column grants below allow resume position only. Completion is withheld.

CREATE POLICY assessments_enrolled_or_owner_read
ON public.assessments FOR SELECT TO authenticated
USING (private.can_view_assessment(id));

CREATE POLICY assessments_owner_manage
ON public.assessments FOR ALL TO authenticated
USING (
  private.has_role('admin'::public.app_role)
  OR (
    status = 'draft'::public.assessment_status
    AND private.can_manage_course(course_id)
  )
)
WITH CHECK (
  private.has_role('admin'::public.app_role)
  OR (
    status = 'draft'::public.assessment_status
    AND private.can_manage_course(course_id)
  )
);

CREATE POLICY assessment_questions_enrolled_or_owner_read
ON public.assessment_questions FOR SELECT TO authenticated
USING (private.can_view_assessment(assessment_id));

CREATE POLICY assessment_questions_owner_manage
ON public.assessment_questions FOR ALL TO authenticated
USING (private.can_edit_assessment(assessment_id))
WITH CHECK (private.can_edit_assessment(assessment_id));

CREATE POLICY assessment_options_enrolled_or_owner_read
ON public.assessment_options FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.assessment_questions AS q
    WHERE q.id = assessment_options.question_id
      AND private.can_view_assessment(q.assessment_id)
  )
);

CREATE POLICY assessment_options_owner_manage
ON public.assessment_options FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.assessment_questions AS q
    WHERE q.id = assessment_options.question_id
      AND private.can_edit_assessment(q.assessment_id)
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.assessment_questions AS q
    WHERE q.id = assessment_options.question_id
      AND private.can_edit_assessment(q.assessment_id)
  )
);

CREATE POLICY assessment_attempts_student_or_owner_read
ON public.assessment_attempts FOR SELECT TO authenticated
USING (
  student_id = (SELECT auth.uid())
  OR private.can_manage_assessment(assessment_id)
);
-- No client write grants or policies for attempts: the server/database must
-- validate and record scores, pass results, and submission timestamps. The
-- student-facing attempt/submission/scoring workflow is deferred to a later,
-- explicitly approved assessment milestone.

CREATE POLICY assessment_responses_student_or_owner_read
ON public.assessment_responses FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.assessment_attempts AS a
    WHERE a.id = assessment_responses.attempt_id
      AND a.student_id = (SELECT auth.uid())
  )
  OR private.can_manage_assessment(assessment_id)
);
-- No client write grants or policies for responses.

-- Explicit grants: revoke any default privileges on these new tables first.
REVOKE ALL ON TABLE
  public.profiles,
  public.user_roles,
  public.instructor_profiles,
  public.categories,
  public.courses,
  public.course_outcomes,
  public.course_sections,
  public.lessons,
  public.enrollments,
  public.lesson_progress,
  public.assessments,
  public.assessment_questions,
  public.assessment_options,
  public.assessment_attempts,
  public.assessment_responses
FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE private.assessment_answer_keys
FROM PUBLIC, anon, authenticated, service_role;

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT USAGE ON TYPE public.app_role TO authenticated;

GRANT SELECT ON public.categories TO anon, authenticated;
GRANT SELECT ON public.instructor_profiles TO anon, authenticated;
GRANT SELECT ON public.courses TO anon, authenticated;
GRANT SELECT ON public.course_outcomes, public.course_sections, public.lessons
  TO anon, authenticated;

GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (display_name, avatar_storage_key, locale)
  ON public.profiles TO authenticated;
GRANT SELECT ON public.user_roles TO authenticated;
GRANT INSERT, UPDATE ON public.instructor_profiles TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.categories TO authenticated;
GRANT INSERT (
  instructor_id, category_id, slug, title, subtitle, description,
  level, language_code, status
) ON public.courses TO authenticated;
GRANT UPDATE (
  category_id, slug, title, subtitle, description,
  level, language_code, status
) ON public.courses TO authenticated;
GRANT INSERT, UPDATE, DELETE ON
  public.course_outcomes, public.course_sections, public.lessons
  TO authenticated;
GRANT SELECT ON public.enrollments TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.enrollments TO authenticated;
GRANT SELECT ON public.lesson_progress TO authenticated;
GRANT INSERT (enrollment_id, course_id, lesson_id, last_position_seconds)
  ON public.lesson_progress TO authenticated;
GRANT UPDATE (last_position_seconds)
  ON public.lesson_progress TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON
  public.assessments, public.assessment_questions, public.assessment_options
  TO authenticated;
GRANT SELECT ON public.assessment_attempts, public.assessment_responses
  TO authenticated;

-- Privileged RPC functions are callable only through authenticated requests.
-- The public-safe course visibility helper is the one anonymous exception;
-- security-definer functions still verify the current role/ownership themselves.
REVOKE ALL ON FUNCTION private.has_role(public.app_role)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION private.provision_profile_for_auth_user()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.bootstrap_first_admin(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.can_manage_course(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION private.can_view_course(uuid)
  FROM PUBLIC, service_role;
REVOKE ALL ON FUNCTION private.can_manage_assessment(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION private.can_edit_assessment(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION private.can_view_assessment(uuid)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION private.set_updated_at()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.guard_course_publication()
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION private.has_role(public.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_manage_course(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_view_course(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION private.can_manage_assessment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_edit_assessment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_view_assessment(uuid) TO authenticated;
-- PostgreSQL invokes these only as triggers; granting execute to authenticated
-- table writers does not make their trigger bodies callable as ordinary RPCs.
GRANT EXECUTE ON FUNCTION private.set_updated_at() TO authenticated;
GRANT EXECUTE ON FUNCTION private.guard_course_publication() TO authenticated;

REVOKE ALL ON FUNCTION public.grant_role_to_user(uuid, public.app_role)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.revoke_role_from_user(uuid, public.app_role)
  FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.set_assessment_answer_key(uuid, uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.grant_role_to_user(uuid, public.app_role)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_role_from_user(uuid, public.app_role)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_assessment_answer_key(uuid, uuid)
  TO authenticated;
