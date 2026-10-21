-- Expose only the exact snapshot associated with a rejection event to the
-- designated administrator. The history and snapshot tables stay private.
BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.employee_registration_rejection_history') IS NULL
     OR to_regclass('public.employee_registration_snapshots') IS NULL THEN
    RAISE EXCEPTION 'Northstar rejection snapshot access requires the existing registration history and snapshot tables.';
  END IF;
  IF to_regprocedure('public.northstar_is_designated_admin()') IS NULL THEN
    RAISE EXCEPTION 'Northstar rejection snapshot access requires public.northstar_is_designated_admin().';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.northstar_admin_get_employee_rejection_snapshot(
  p_rejection_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  snapshot_record jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the designated Northstar administrator may view registration snapshots.'
      USING ERRCODE = '42501';
  END IF;
  IF p_rejection_id IS NULL THEN
    RAISE EXCEPTION 'A rejection event ID is required.' USING ERRCODE = '22023';
  END IF;

  SELECT pg_catalog.to_jsonb(snapshot_row)
    INTO snapshot_record
  FROM public.employee_registration_rejection_history AS rejection
  JOIN public.employee_registration_snapshots AS snapshot_row
    ON snapshot_row.id = rejection.registration_snapshot_id
   AND snapshot_row.user_id = rejection.employee_id
  WHERE rejection.id = p_rejection_id;

  IF snapshot_record IS NULL THEN
    RAISE EXCEPTION 'No registration snapshot is linked to that rejection event.' USING ERRCODE = 'P0002';
  END IF;
  RETURN snapshot_record;
END;
$function$;

ALTER FUNCTION public.northstar_admin_get_employee_rejection_snapshot(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_admin_get_employee_rejection_snapshot(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.northstar_admin_get_employee_rejection_snapshot(uuid) TO authenticated;

COMMIT;
