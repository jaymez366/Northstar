-- PostgreSQL truncates identifiers longer than 63 bytes. The previous
-- admin RPC name was therefore stored as the singular ..._correction name.
-- Rename that existing function so its implementation, return type, owner,
-- SECURITY DEFINER setting, search_path, and ACL are preserved.
BEGIN;

DO $migration$
DECLARE
  v_truncated_function regprocedure :=
    to_regprocedure('public.northstar_admin_list_employee_rejection_history_with_correction()');
  v_target_function regprocedure :=
    to_regprocedure('public.northstar_admin_list_rejection_history()');
BEGIN
  IF v_truncated_function IS NOT NULL AND v_target_function IS NULL THEN
    ALTER FUNCTION public.northstar_admin_list_employee_rejection_history_with_correction()
      RENAME TO northstar_admin_list_rejection_history;
  ELSIF v_truncated_function IS NULL AND v_target_function IS NOT NULL THEN
    -- The corrected name is already present, as on a fresh install using the
    -- corrected registration-corrections migration source.
    NULL;
  ELSIF v_truncated_function IS NOT NULL AND v_target_function IS NOT NULL THEN
    RAISE EXCEPTION 'Both Northstar admin rejection-history RPC names exist; review them before renaming.';
  ELSE
    RAISE EXCEPTION 'Neither Northstar admin rejection-history RPC name exists; review migration state before renaming.';
  END IF;
END
$migration$;

NOTIFY pgrst, 'reload schema';

COMMIT;
