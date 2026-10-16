-- Persist the registration photo separately from the active profile avatar.
-- Depends on northstar_is_designated_admin() and the designated-admin
-- profile-avatars Storage SELECT policy from the registration support migration.
-- The frontend completes complete_my_employee_registration() first; that RPC
-- marks the profile complete/pending before northstar_save_registration_photo().

CREATE TABLE IF NOT EXISTS public.employee_registration_photos (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  storage_path text NOT NULL,
  use_as_profile_photo boolean NOT NULL,
  submitted_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.employee_registration_photos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.employee_registration_photos FROM PUBLIC, anon, authenticated;

-- Profile images are served with signed URLs by the frontend. Keep the bucket
-- private and constrain Storage access even if older permissive policies exist.
DO $$
BEGIN
  UPDATE storage.buckets SET public = false WHERE id = 'profile-avatars';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The required profile-avatars Storage bucket does not exist.';
  END IF;
END;
$$;

DROP POLICY IF EXISTS northstar_profile_avatars_select_guard ON storage.objects;
CREATE POLICY northstar_profile_avatars_select_guard
ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated
USING (
  bucket_id <> 'profile-avatars'
  OR owner_id = (SELECT auth.uid()::text)
  OR public.northstar_is_designated_admin()
  OR EXISTS (
    SELECT 1 FROM public.profiles AS profile
    WHERE profile.avatar_url::text = name
      AND profile.registration_completed IS TRUE
      AND profile.approval_status = 'approved'
      AND profile.employment_status = 'active'
  )
);

DROP POLICY IF EXISTS northstar_profile_avatars_anon_select_guard ON storage.objects;
CREATE POLICY northstar_profile_avatars_anon_select_guard
ON storage.objects AS RESTRICTIVE FOR SELECT TO anon
USING (bucket_id <> 'profile-avatars');

DROP POLICY IF EXISTS northstar_profile_avatars_insert_guard ON storage.objects;
CREATE POLICY northstar_profile_avatars_insert_guard
ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK (
  bucket_id <> 'profile-avatars'
  OR (
    split_part(name, '/', 1) = (SELECT auth.uid()::text)
    AND owner_id = (SELECT auth.uid()::text)
  )
);

DROP POLICY IF EXISTS northstar_profile_avatars_anon_insert_guard ON storage.objects;
CREATE POLICY northstar_profile_avatars_anon_insert_guard
ON storage.objects AS RESTRICTIVE FOR INSERT TO anon
WITH CHECK (bucket_id <> 'profile-avatars');

DROP POLICY IF EXISTS northstar_profile_avatars_select_scoped ON storage.objects;
CREATE POLICY northstar_profile_avatars_select_scoped
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'profile-avatars'
  AND (
    owner_id = (SELECT auth.uid()::text)
    OR public.northstar_is_designated_admin()
    OR EXISTS (
      SELECT 1 FROM public.profiles AS profile
      WHERE profile.avatar_url::text = name
        AND profile.registration_completed IS TRUE
        AND profile.approval_status = 'approved'
        AND profile.employment_status = 'active'
    )
  )
);

DROP POLICY IF EXISTS northstar_profile_avatars_insert_scoped ON storage.objects;
CREATE POLICY northstar_profile_avatars_insert_scoped
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'profile-avatars'
  AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  AND owner_id = (SELECT auth.uid()::text)
);

CREATE OR REPLACE FUNCTION public.northstar_save_registration_photo(
  p_storage_path text,
  p_use_as_profile_photo boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in to save a registration photo.' USING ERRCODE = '42501';
  END IF;
  IF p_storage_path IS NULL
     OR split_part(p_storage_path, '/', 1) <> auth.uid()::text
     OR p_use_as_profile_photo IS NULL THEN
    RAISE EXCEPTION 'The registration photo path or choice is invalid.' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles AS p
    WHERE p.id = auth.uid()
      AND p.registration_completed IS TRUE
      AND p.approval_status IN ('pending', 'rejected')
  ) THEN
    RAISE EXCEPTION 'A registration photo can only be saved while registration is pending or rejected.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM storage.objects AS object
    WHERE object.bucket_id = 'profile-avatars'
      AND object.name = p_storage_path
      AND object.owner_id = auth.uid()::text
  ) THEN
    RAISE EXCEPTION 'The uploaded photo must exist in profile-avatars and belong to the signed-in user.'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.employee_registration_photos (user_id, storage_path, use_as_profile_photo, submitted_at)
  VALUES (auth.uid(), p_storage_path, p_use_as_profile_photo, now())
  ON CONFLICT (user_id) DO UPDATE
  SET storage_path = EXCLUDED.storage_path,
      use_as_profile_photo = EXCLUDED.use_as_profile_photo,
      submitted_at = EXCLUDED.submitted_at;

  IF p_use_as_profile_photo THEN
    UPDATE public.profiles SET avatar_url = p_storage_path WHERE id = auth.uid();
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.northstar_admin_get_registration_photo(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  photo_path text;
BEGIN
  IF NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated Northstar administrator may view registration photos.' USING ERRCODE = '42501';
  END IF;
  SELECT photo.storage_path INTO photo_path
  FROM public.employee_registration_photos AS photo
  WHERE photo.user_id = p_user_id
    AND split_part(photo.storage_path, '/', 1) = p_user_id::text;
  RETURN photo_path;
END;
$$;

-- Clear inherited/default ACLs before granting the intended caller role.
REVOKE ALL ON FUNCTION public.northstar_save_registration_photo(text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.northstar_admin_get_registration_photo(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_save_registration_photo(text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_admin_get_registration_photo(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
