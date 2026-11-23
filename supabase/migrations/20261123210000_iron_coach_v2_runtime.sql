-- IRONNOVA coach/student V2 runtime functions
-- Applied to Supabase project hcdcllknzxllyuptlwpy on 2026-11-23.
-- The V2 base tables and helper functions must already exist.

REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.iron_add_student_log(
  p_log_type text,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_log_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'ابتدا وارد حساب کاربری شوید';
  END IF;
  IF p_log_type IS NULL OR p_log_type NOT IN ('workout','sleep','nutrition','weight','note') THEN
    RAISE EXCEPTION 'نوع گزارش معتبر نیست';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.iron_account_roles_v2
    WHERE user_id = auth.uid() AND role = 'student' AND status = 'approved'
  ) THEN
    RAISE EXCEPTION 'فقط شاگرد تأییدشده می‌تواند گزارش ثبت کند';
  END IF;
  INSERT INTO public.iron_student_logs (student_id, log_type, payload)
  VALUES (auth.uid(), p_log_type, COALESCE(p_payload, '{}'::jsonb))
  RETURNING id INTO v_log_id;
  RETURN v_log_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.iron_create_coach_plan_v2(
  p_student_id uuid,
  p_title text,
  p_days jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_plan_id uuid;
  v_day_id uuid;
  v_day jsonb;
  v_exercise jsonb;
  v_day_number integer := 0;
  v_exercise_id bigint;
  v_order integer;
  v_name text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'ابتدا وارد حساب کاربری شوید'; END IF;
  IF p_title IS NULL OR length(trim(p_title)) = 0 THEN RAISE EXCEPTION 'عنوان برنامه الزامی است'; END IF;
  IF p_student_id IS NULL OR NOT COALESCE(public.iron_is_linked_coach(p_student_id), false) THEN
    RAISE EXCEPTION 'شاگرد متصل و تأییدشده پیدا نشد';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.iron_account_roles_v2
    WHERE user_id = auth.uid() AND role = 'coach' AND status = 'approved'
  ) THEN RAISE EXCEPTION 'حساب مربی تأییدشده لازم است'; END IF;
  IF p_days IS NULL OR jsonb_typeof(p_days) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'ساختار روزهای برنامه معتبر نیست';
  END IF;
  IF jsonb_array_length(p_days) < 1 OR jsonb_array_length(p_days) > 10 THEN
    RAISE EXCEPTION 'برنامه باید بین ۱ تا ۱۰ روز داشته باشد';
  END IF;

  INSERT INTO public.iron_workout_plans_v2 (coach_id, student_id, title, description, status)
  VALUES (auth.uid(), p_student_id, trim(p_title), 'برنامه ثبت‌شده توسط مربی', 'draft')
  RETURNING id INTO v_plan_id;

  FOR v_day IN SELECT value FROM jsonb_array_elements(p_days) LOOP
    v_day_number := v_day_number + 1;
    IF jsonb_typeof(v_day) IS DISTINCT FROM 'object'
       OR v_day->'exercises' IS NULL
       OR jsonb_typeof(v_day->'exercises') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'ساختار روز % معتبر نیست', v_day_number;
    END IF;
    IF jsonb_array_length(v_day->'exercises') < 1
       OR jsonb_array_length(v_day->'exercises') > 30 THEN
      RAISE EXCEPTION 'روز % باید حداقل یک و حداکثر ۳۰ حرکت داشته باشد', v_day_number;
    END IF;

    INSERT INTO public.iron_workout_days_v2(plan_id, day_number, title, notes)
    VALUES (
      v_plan_id, v_day_number,
      COALESCE(NULLIF(trim(v_day->>'title'), ''), 'روز ' || v_day_number),
      COALESCE(v_day->>'notes', '')
    ) RETURNING id INTO v_day_id;

    v_order := 0;
    FOR v_exercise IN SELECT value FROM jsonb_array_elements(v_day->'exercises') LOOP
      v_order := v_order + 1;
      v_name := trim(COALESCE(v_exercise->>'name',''));
      IF v_name = '' THEN RAISE EXCEPTION 'نام حرکت در روز % خالی است', v_day_number; END IF;

      SELECT id INTO v_exercise_id
      FROM public.iron_workout_exercises_v2
      WHERE is_active = true AND lower(name) = lower(v_name)
      ORDER BY id LIMIT 1;

      IF v_exercise_id IS NULL THEN
        RAISE EXCEPTION 'حرکت «%» در بانک حرکات فعال پیدا نشد', v_name;
      END IF;

      INSERT INTO public.iron_workout_day_exercises_v2
        (plan_day_id, exercise_id, order_number, sets, reps, rest_seconds)
      VALUES (
        v_day_id, v_exercise_id, v_order,
        LEAST(10, GREATEST(1, COALESCE(NULLIF(v_exercise->>'sets','')::integer, 3))),
        COALESCE(NULLIF(v_exercise->>'reps',''), '8 تا 12'),
        LEAST(600, GREATEST(0, COALESCE(NULLIF(v_exercise->>'rest_seconds','')::integer, 60)))
      );
      v_exercise_id := NULL;
    END LOOP;
  END LOOP;

  PERFORM public.iron_publish_plan(v_plan_id);
  RETURN v_plan_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.iron_create_coach_plan_v2(uuid,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.iron_create_coach_plan_v2(uuid,text,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.iron_admin_pending_coaches_v2()
RETURNS TABLE(user_id uuid, full_name text, specialty text, requested_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.iron_admins_v2
    WHERE iron_admins_v2.user_id = auth.uid() AND iron_admins_v2.is_main_admin = true
  ) THEN
    RAISE EXCEPTION 'فقط مدیر اصلی اجازه مشاهده درخواست‌ها را دارد';
  END IF;
  RETURN QUERY
  SELECT r.user_id, COALESCE(p.full_name, ''), COALESCE(p.specialty, ''), r.created_at
  FROM public.iron_account_roles_v2 r
  LEFT JOIN public.iron_coach_profiles_v2 p ON p.user_id = r.user_id
  WHERE r.role = 'coach' AND r.status = 'pending'
  ORDER BY r.created_at ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.iron_admin_pending_coaches_v2() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.iron_admin_pending_coaches_v2() TO authenticated;


-- Keep legacy and internal RPCs callable only by the database owner.
REVOKE ALL ON FUNCTION public.iron_respond_link(uuid,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.iron_publish_plan(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.iron_request_role_v2(text) FROM PUBLIC, anon, authenticated;

-- Query indexes for the V2 coach/student workflow.
CREATE INDEX IF NOT EXISTS idx_iron_invites_coach_v2 ON public.iron_coach_invites(coach_id);
CREATE INDEX IF NOT EXISTS idx_iron_invites_claimed_by_v2 ON public.iron_coach_invites(claimed_by);
CREATE INDEX IF NOT EXISTS idx_iron_links_student_status_v2 ON public.iron_coach_students_v2(student_id,status);
CREATE INDEX IF NOT EXISTS idx_iron_links_coach_status_v2 ON public.iron_coach_students_v2(coach_id,status);
CREATE INDEX IF NOT EXISTS idx_iron_logs_student ON public.iron_student_logs(student_id,logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_iron_plans_coach_student_status_v2 ON public.iron_workout_plans_v2(coach_id,student_id,status);
CREATE INDEX IF NOT EXISTS idx_iron_plans_student_status_v2 ON public.iron_workout_plans_v2(student_id,status);
CREATE INDEX IF NOT EXISTS idx_iron_day_exercises_plan_order_v2 ON public.iron_workout_day_exercises_v2(plan_day_id,order_number);
CREATE INDEX IF NOT EXISTS idx_iron_day_exercises_exercise_v2 ON public.iron_workout_day_exercises_v2(exercise_id);
CREATE INDEX IF NOT EXISTS idx_iron_exercises_active_name_v2 ON public.iron_workout_exercises_v2(lower(name)) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_iron_roles_role_status_v2 ON public.iron_account_roles_v2(role,status);

-- Active exercises are visible to signed-in users; only the main admin can
-- manage the catalog or inspect inactive exercises.
DROP POLICY IF EXISTS iron_exercises_active_select_v2 ON public.iron_workout_exercises_v2;
DROP POLICY IF EXISTS iron_workout_exercises_v2_admin_manage ON public.iron_workout_exercises_v2;
DROP POLICY IF EXISTS iron_workout_exercises_v2_read ON public.iron_workout_exercises_v2;
DROP POLICY IF EXISTS iron_workout_exercises_v2_select ON public.iron_workout_exercises_v2;
DROP POLICY IF EXISTS iron_workout_exercises_v2_insert_admin ON public.iron_workout_exercises_v2;
DROP POLICY IF EXISTS iron_workout_exercises_v2_update_admin ON public.iron_workout_exercises_v2;
DROP POLICY IF EXISTS iron_workout_exercises_v2_delete_admin ON public.iron_workout_exercises_v2;

CREATE POLICY iron_workout_exercises_v2_select
ON public.iron_workout_exercises_v2
FOR SELECT TO authenticated
USING (
  is_active = true
  OR EXISTS (
    SELECT 1 FROM public.iron_admins_v2
    WHERE user_id = (select auth.uid()) AND is_main_admin = true
  )
);
CREATE POLICY iron_workout_exercises_v2_insert_admin
ON public.iron_workout_exercises_v2
FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (SELECT 1 FROM public.iron_admins_v2
          WHERE user_id = (select auth.uid()) AND is_main_admin = true)
);
CREATE POLICY iron_workout_exercises_v2_update_admin
ON public.iron_workout_exercises_v2
FOR UPDATE TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.iron_admins_v2
          WHERE user_id = (select auth.uid()) AND is_main_admin = true)
)
WITH CHECK (
  EXISTS (SELECT 1 FROM public.iron_admins_v2
          WHERE user_id = (select auth.uid()) AND is_main_admin = true)
);
CREATE POLICY iron_workout_exercises_v2_delete_admin
ON public.iron_workout_exercises_v2
FOR DELETE TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.iron_admins_v2
          WHERE user_id = (select auth.uid()) AND is_main_admin = true)
);

DROP POLICY IF EXISTS iron_coach_profile_select_linked_students ON public.iron_coach_profiles_v2;
DROP POLICY IF EXISTS iron_coach_profile_select_own ON public.iron_coach_profiles_v2;
DROP POLICY IF EXISTS iron_coach_profile_select_v2 ON public.iron_coach_profiles_v2;
CREATE POLICY iron_coach_profile_select_v2
ON public.iron_coach_profiles_v2
FOR SELECT TO authenticated
USING (
  user_id = (select auth.uid())
  OR EXISTS (
    SELECT 1 FROM public.iron_coach_students_v2 cs
    WHERE cs.coach_id = iron_coach_profiles_v2.user_id
      AND cs.student_id = (select auth.uid())
      AND cs.status = 'approved'
  )
);
