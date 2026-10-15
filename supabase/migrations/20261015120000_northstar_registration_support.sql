-- Northstar employee registration history and private expert support.
-- Review this migration against the deployed schema before applying it.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS rejection_reason text;

-- Central database-side identity check used by admin RPCs and RLS.
CREATE OR REPLACE FUNCTION public.northstar_is_designated_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM auth.users AS u
    WHERE u.id = auth.uid()
      AND lower(u.email) = 'northstaradmin34@gmail.com'
      AND u.email_confirmed_at IS NOT NULL
  );
$$;

REVOKE ALL ON FUNCTION public.northstar_is_designated_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_is_designated_admin() TO authenticated;

-- Do not allow direct employee updates to approval/security fields. The existing
-- security-definer registration and admin RPCs continue to perform authorized updates.
CREATE OR REPLACE FUNCTION public.northstar_protect_profile_approval_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  registration_changed boolean;
BEGIN
  registration_changed :=
    NEW.first_name IS DISTINCT FROM OLD.first_name OR
    NEW.last_name IS DISTINCT FROM OLD.last_name OR
    NEW.phone_number IS DISTINCT FROM OLD.phone_number OR
    NEW.department_id IS DISTINCT FROM OLD.department_id OR
    NEW.job_title IS DISTINCT FROM OLD.job_title OR
    NEW.employee_id IS DISTINCT FROM OLD.employee_id OR
    NEW.employment_type IS DISTINCT FROM OLD.employment_type OR
    NEW.office_location IS DISTINCT FROM OLD.office_location OR
    NEW.date_of_joining IS DISTINCT FROM OLD.date_of_joining OR
    NEW.manager_name IS DISTINCT FROM OLD.manager_name OR
    NEW.bio IS DISTINCT FROM OLD.bio;

  IF current_user IN ('authenticated', 'anon')
     AND NOT public.northstar_is_designated_admin() THEN
    IF OLD.approval_status = 'rejected' AND registration_changed THEN
      NEW.approval_status := 'pending';
      NEW.employment_status := 'inactive';
      NEW.rejection_reason := NULL;
    ELSIF NEW.approval_status IS DISTINCT FROM OLD.approval_status
       OR NEW.employment_status IS DISTINCT FROM OLD.employment_status
       OR (
         NEW.registration_completed IS DISTINCT FROM OLD.registration_completed
         AND NOT (
           OLD.registration_completed IS FALSE
           AND NEW.registration_completed IS TRUE
           AND NEW.approval_status = 'pending'
           AND NEW.employment_status = 'inactive'
         )
       )
       OR NEW.role IS DISTINCT FROM OLD.role
       OR NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason THEN
      RAISE EXCEPTION 'Registration approval fields can only be changed by Northstar registration functions.'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS northstar_protect_profile_approval_fields ON public.profiles;
CREATE TRIGGER northstar_protect_profile_approval_fields
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.northstar_protect_profile_approval_fields();

CREATE TABLE IF NOT EXISTS public.employee_registration_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  first_name text NOT NULL,
  last_name text NOT NULL,
  email text NOT NULL,
  phone_number text,
  department text,
  job_title text,
  employee_id text,
  employment_type text,
  office_location text,
  date_of_joining text,
  manager_name text,
  bio text,
  registration_completed boolean NOT NULL,
  approval_status text NOT NULL,
  employment_status text NOT NULL,
  is_original boolean NOT NULL DEFAULT true
);

CREATE INDEX IF NOT EXISTS employee_registration_snapshots_user_submitted_idx
  ON public.employee_registration_snapshots (user_id, submitted_at DESC);

-- Existing completed registrations receive a clearly marked current-state snapshot;
-- historical submission values cannot be reconstructed from the supplied schema.
INSERT INTO public.employee_registration_snapshots (
  user_id, submitted_at, first_name, last_name, email, phone_number, department,
  job_title, employee_id, employment_type, office_location, date_of_joining,
  manager_name, bio, registration_completed, approval_status, employment_status,
  is_original
)
SELECT p.id, COALESCE(p.updated_at, p.created_at, now()), p.first_name::text, p.last_name::text, COALESCE(p.email::text, u.email, ''),
       p.phone_number::text, d.name, p.job_title::text, p.employee_id::text, p.employment_type::text,
       p.office_location::text, p.date_of_joining::text, p.manager_name::text, p.bio::text,
       p.registration_completed, p.approval_status::text, p.employment_status::text, false
FROM public.profiles AS p
LEFT JOIN public.departments AS d ON d.id = p.department_id
LEFT JOIN auth.users AS u ON u.id = p.id
WHERE p.registration_completed IS TRUE
  AND NOT EXISTS (
    SELECT 1 FROM public.employee_registration_snapshots AS s WHERE s.user_id = p.id
  );

CREATE OR REPLACE FUNCTION public.northstar_capture_registration_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  department_label text;
BEGIN
  IF NEW.registration_completed IS TRUE
     AND (
       OLD.registration_completed IS DISTINCT FROM TRUE OR
       (OLD.approval_status = 'rejected' AND (
         NEW.first_name IS DISTINCT FROM OLD.first_name OR
         NEW.last_name IS DISTINCT FROM OLD.last_name OR
         NEW.phone_number IS DISTINCT FROM OLD.phone_number OR
         NEW.department_id IS DISTINCT FROM OLD.department_id OR
         NEW.job_title IS DISTINCT FROM OLD.job_title OR
         NEW.employee_id IS DISTINCT FROM OLD.employee_id OR
         NEW.employment_type IS DISTINCT FROM OLD.employment_type OR
         NEW.office_location IS DISTINCT FROM OLD.office_location OR
         NEW.date_of_joining IS DISTINCT FROM OLD.date_of_joining OR
         NEW.manager_name IS DISTINCT FROM OLD.manager_name OR
         NEW.bio IS DISTINCT FROM OLD.bio
       ))
     ) THEN
    SELECT d.name INTO department_label
    FROM public.departments AS d
    WHERE d.id = NEW.department_id;

    INSERT INTO public.employee_registration_snapshots (
      user_id, first_name, last_name, email, phone_number, department, job_title,
      employee_id, employment_type, office_location, date_of_joining,
      manager_name, bio, registration_completed, approval_status, employment_status,
      is_original
    ) VALUES (
      NEW.id, NEW.first_name::text, NEW.last_name::text, NEW.email::text, NEW.phone_number::text,
      department_label, NEW.job_title::text, NEW.employee_id::text, NEW.employment_type::text,
      NEW.office_location::text, NEW.date_of_joining::text, NEW.manager_name::text, NEW.bio::text,
      NEW.registration_completed, NEW.approval_status::text, NEW.employment_status::text, true
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS northstar_capture_registration_snapshot ON public.profiles;
CREATE TRIGGER northstar_capture_registration_snapshot
AFTER UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.northstar_capture_registration_snapshot();

REVOKE ALL ON public.employee_registration_snapshots FROM PUBLIC, anon, authenticated;
ALTER TABLE public.employee_registration_snapshots ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.northstar_admin_list_employee_registrations()
RETURNS TABLE (
  user_id uuid, first_name text, last_name text, email text, phone_number text,
  department text, job_title text, employee_id text, employment_type text,
  office_location text, date_of_joining text, manager_name text, bio text,
  registration_completed boolean, approval_status text, employment_status text,
  email_verification_status text, email_verified_at timestamptz,
  account_created_at timestamptz, registration_submitted_at timestamptz,
  registration_snapshot_is_original boolean, rejection_reason text,
  current_email text, current_first_name text, current_last_name text,
  current_avatar_url text, current_phone_number text, current_department text,
  current_job_title text, current_employee_id text, current_employment_type text,
  current_office_location text, current_date_of_joining text,
  current_manager_name text, current_bio text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated Northstar administrator may list employee registrations.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT p.id,
         COALESCE(s.first_name, p.first_name::text, ''), COALESCE(s.last_name, p.last_name::text, ''),
         COALESCE(s.email, p.email, u.email, ''), COALESCE(s.phone_number, p.phone_number),
         COALESCE(s.department, d.name), COALESCE(s.job_title, p.job_title::text),
         COALESCE(s.employee_id, p.employee_id::text), COALESCE(s.employment_type, p.employment_type::text),
         COALESCE(s.office_location, p.office_location::text), COALESCE(s.date_of_joining, p.date_of_joining::text),
         COALESCE(s.manager_name, p.manager_name::text), COALESCE(s.bio, p.bio::text),
         p.registration_completed, COALESCE(p.approval_status::text, 'pending'), COALESCE(p.employment_status::text, 'inactive'),
         CASE WHEN u.email_confirmed_at IS NOT NULL THEN 'Verified' ELSE 'Not Verified' END,
         u.email_confirmed_at, u.created_at, s.submitted_at, COALESCE(s.is_original, false),
         p.rejection_reason, COALESCE(p.email::text, u.email, ''), COALESCE(p.first_name::text, ''), COALESCE(p.last_name::text, ''),
         p.avatar_url::text, p.phone_number::text, d.name, p.job_title::text, p.employee_id::text,
         p.employment_type::text, p.office_location::text, p.date_of_joining::text, p.manager_name::text, p.bio::text
  FROM public.profiles AS p
  LEFT JOIN auth.users AS u ON u.id = p.id
  LEFT JOIN public.departments AS d ON d.id = p.department_id
  LEFT JOIN LATERAL (
    SELECT snap.* FROM public.employee_registration_snapshots AS snap
    WHERE snap.user_id = p.id ORDER BY snap.submitted_at DESC, snap.id DESC LIMIT 1
  ) AS s ON true
  WHERE p.registration_completed IS TRUE
  ORDER BY p.approval_status, s.submitted_at DESC NULLS LAST, p.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.northstar_admin_list_email_verification_status()
RETURNS TABLE (
  user_id uuid, first_name text, last_name text, email text,
  email_verification_status text, email_verified_at timestamptz,
  account_created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated Northstar administrator may list verification status.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT u.id, COALESCE(p.first_name, ''), COALESCE(p.last_name, ''), u.email,
         CASE WHEN u.email_confirmed_at IS NOT NULL THEN 'Verified' ELSE 'Not Verified' END,
         u.email_confirmed_at, u.created_at
  FROM auth.users AS u LEFT JOIN public.profiles AS p ON p.id = u.id
  ORDER BY u.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.northstar_admin_update_employee_registration_status(
  p_user_id uuid, p_approval_status text, p_rejection_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated Northstar administrator may update registrations.' USING ERRCODE = '42501';
  END IF;
  IF p_approval_status NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Approval status must be approved or rejected.' USING ERRCODE = '22023';
  END IF;
  IF p_approval_status = 'rejected' AND NULLIF(btrim(p_rejection_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A rejection reason is required.' USING ERRCODE = '22023';
  END IF;

  -- Reuse the existing function to preserve its established admin authorization
  -- and active/inactive status behavior; the new field update is atomic with it.
  PERFORM public.admin_set_employee_approval(p_user_id, p_approval_status);
  UPDATE public.profiles
  SET rejection_reason = CASE WHEN p_approval_status = 'rejected' THEN btrim(p_rejection_reason) ELSE NULL END
  WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employee profile was not found.' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.northstar_admin_list_employee_registrations() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.northstar_admin_list_email_verification_status() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.northstar_admin_update_employee_registration_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_admin_list_employee_registrations() TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_admin_list_email_verification_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_admin_update_employee_registration_status(uuid, text, text) TO authenticated;

-- Add a private support inbox without changing membership or RLS for direct chats.
CREATE TABLE IF NOT EXISTS public.support_inquiries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  full_name text NOT NULL,
  topic text NOT NULL CHECK (topic IN ('Employee communication', 'Disaster management', 'Both')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'waiting_on_support', 'waiting_on_employee', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.support_inquiry_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inquiry_id uuid NOT NULL REFERENCES public.support_inquiries(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  content text NOT NULL CHECK (length(btrim(content)) > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS support_inquiries_user_updated_idx
  ON public.support_inquiries (user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS support_inquiry_messages_thread_idx
  ON public.support_inquiry_messages (inquiry_id, created_at);

ALTER TABLE public.support_inquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_inquiry_messages ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.support_inquiries, public.support_inquiry_messages FROM PUBLIC, anon;
GRANT SELECT ON public.support_inquiries, public.support_inquiry_messages TO authenticated;

CREATE POLICY northstar_support_inquiries_read_owner_or_admin
ON public.support_inquiries FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.northstar_is_designated_admin());

CREATE POLICY northstar_support_messages_read_owner_or_admin
ON public.support_inquiry_messages FOR SELECT TO authenticated
USING (
  public.northstar_is_designated_admin()
  OR EXISTS (
    SELECT 1 FROM public.support_inquiries AS i
    WHERE i.id = inquiry_id AND i.user_id = auth.uid()
  )
);

CREATE OR REPLACE FUNCTION public.northstar_submit_support_inquiry(
  p_email text, p_name text, p_topic text, p_message text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  inquiry_id uuid;
  account_email text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in to contact Northstar support.' USING ERRCODE = '42501'; END IF;
  SELECT u.email INTO account_email FROM auth.users AS u WHERE u.id = auth.uid() AND u.email_confirmed_at IS NOT NULL;
  IF account_email IS NULL OR lower(account_email) <> lower(btrim(p_email)) THEN
    RAISE EXCEPTION 'Use the confirmed email address for your Northstar account.' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(btrim(p_name), '') IS NULL OR NULLIF(btrim(p_message), '') IS NULL
     OR p_topic NOT IN ('Employee communication', 'Disaster management', 'Both') THEN
    RAISE EXCEPTION 'Complete the required support inquiry fields.' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.support_inquiries (user_id, email, full_name, topic)
  VALUES (auth.uid(), account_email, btrim(p_name), p_topic)
  RETURNING id INTO inquiry_id;
  INSERT INTO public.support_inquiry_messages (inquiry_id, sender_id, content)
  VALUES (inquiry_id, auth.uid(), btrim(p_message));
  RETURN inquiry_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.northstar_list_my_support_inquiries()
RETURNS TABLE (id uuid, topic text, status text, created_at timestamptz, updated_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required.' USING ERRCODE = '42501'; END IF;
  RETURN QUERY
  SELECT i.id, i.topic, i.status, i.created_at, i.updated_at
  FROM public.support_inquiries AS i WHERE i.user_id = auth.uid()
  ORDER BY i.updated_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.northstar_get_support_inquiry_messages(p_inquiry_id uuid)
RETURNS TABLE (id uuid, sender_id uuid, sender_name text, content text, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.northstar_is_designated_admin() AND NOT EXISTS (
    SELECT 1 FROM public.support_inquiries AS i WHERE i.id = p_inquiry_id AND i.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'This support inquiry is not available to your account.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT m.id, m.sender_id,
         CASE WHEN public.northstar_is_designated_admin() AND m.sender_id = auth.uid() THEN 'Northstar Support'
              ELSE COALESCE(NULLIF(btrim(concat_ws(' ', p.first_name, p.last_name)), ''), u.email) END,
         m.content, m.created_at
  FROM public.support_inquiry_messages AS m
  JOIN auth.users AS u ON u.id = m.sender_id
  LEFT JOIN public.profiles AS p ON p.id = m.sender_id
  WHERE m.inquiry_id = p_inquiry_id
  ORDER BY m.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.northstar_reply_support_inquiry(p_inquiry_id uuid, p_message text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  owner_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NULLIF(btrim(p_message), '') IS NULL THEN
    RAISE EXCEPTION 'A signed-in user and non-empty reply are required.' USING ERRCODE = '22023';
  END IF;
  SELECT i.user_id INTO owner_id FROM public.support_inquiries AS i WHERE i.id = p_inquiry_id;
  IF owner_id IS NULL OR owner_id <> auth.uid() OR public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'This reply action is not available to your account.' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.support_inquiry_messages (inquiry_id, sender_id, content)
  VALUES (p_inquiry_id, auth.uid(), btrim(p_message));
  UPDATE public.support_inquiries SET status = 'waiting_on_support', updated_at = now() WHERE id = p_inquiry_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.northstar_admin_list_support_inquiries()
RETURNS TABLE (id uuid, user_id uuid, email text, full_name text, topic text, status text, created_at timestamptz, updated_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated Northstar administrator may list support inquiries.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT i.id, i.user_id, i.email, i.full_name, i.topic, i.status, i.created_at, i.updated_at
  FROM public.support_inquiries AS i ORDER BY i.updated_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.northstar_admin_reply_support_inquiry(p_inquiry_id uuid, p_message text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated Northstar administrator may reply to support inquiries.' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(btrim(p_message), '') IS NULL THEN RAISE EXCEPTION 'Reply cannot be empty.' USING ERRCODE = '22023'; END IF;
  INSERT INTO public.support_inquiry_messages (inquiry_id, sender_id, content)
  SELECT i.id, auth.uid(), btrim(p_message) FROM public.support_inquiries AS i WHERE i.id = p_inquiry_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Support inquiry was not found.' USING ERRCODE = 'P0002'; END IF;
  UPDATE public.support_inquiries SET status = 'waiting_on_employee', updated_at = now() WHERE id = p_inquiry_id;
END;
$$;

REVOKE ALL ON FUNCTION public.northstar_submit_support_inquiry(text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.northstar_list_my_support_inquiries() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.northstar_get_support_inquiry_messages(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.northstar_reply_support_inquiry(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.northstar_admin_list_support_inquiries() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.northstar_admin_reply_support_inquiry(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_submit_support_inquiry(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_list_my_support_inquiries() TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_get_support_inquiry_messages(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_reply_support_inquiry(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_admin_list_support_inquiries() TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_admin_reply_support_inquiry(uuid, text) TO authenticated;

-- Grant the designated admin signed-URL access to profile photos without making
-- the profile-avatars bucket public or adding access for ordinary employees.
CREATE POLICY northstar_admin_read_profile_avatars
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'profile-avatars' AND public.northstar_is_designated_admin());

NOTIFY pgrst, 'reload schema';
