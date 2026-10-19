-- Let an employee retrieve only the private registration photo path saved for
-- their own profile. The storage bucket remains private; the frontend uses the
-- returned path to create a short-lived signed URL under Storage RLS.
CREATE OR REPLACE FUNCTION public.northstar_get_my_registration_photo()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT photo.storage_path
  FROM public.employee_registration_photos AS photo
  WHERE photo.user_id = (SELECT auth.uid())
    AND split_part(photo.storage_path, '/', 1) = (SELECT auth.uid())::text
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.northstar_get_my_registration_photo() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_get_my_registration_photo() TO authenticated;

NOTIFY pgrst, 'reload schema';
