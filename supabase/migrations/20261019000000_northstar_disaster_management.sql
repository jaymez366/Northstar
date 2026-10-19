-- Northstar Disaster Management: incident reporting, restricted administration,
-- append-only history, private notifications, and optional Realtime support.
-- Review the preflight requirements against the deployed database before applying.

BEGIN;

-- Fail before creating objects if the deployed profile/notification schema differs
-- from the schema this migration is designed to use. NULL registration/approval
-- fields are deliberately accepted; employee eligibility checks fail closed.
DO $preflight$
DECLARE
  missing_columns text;
  profile_id_type text;
  profile_id_nullable text;
  approval_nullable text;
  registration_type text;
  registration_nullable text;
  notification_type_type text;
  notification_type_nullable text;
  notification_type_default text;
  extra_required_columns text;
  notifications_owner name;
  notifications_rls boolean;
  notifications_force_rls boolean;
BEGIN
  SELECT string_agg(required.table_name || '.' || required.column_name, ', ' ORDER BY required.table_name, required.column_name)
    INTO missing_columns
  FROM (VALUES
    ('profiles', 'id'), ('profiles', 'first_name'), ('profiles', 'last_name'),
    ('profiles', 'email'), ('profiles', 'role'), ('profiles', 'employment_status'),
    ('profiles', 'approval_status'), ('profiles', 'registration_completed'),
    ('notifications', 'user_id'), ('notifications', 'title'), ('notifications', 'message'),
    ('notifications', 'notification_type'), ('notifications', 'related_entity_id'), ('notifications', 'link_to')
  ) AS required(table_name, column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns AS c
    WHERE c.table_schema = 'public'
      AND c.table_name = required.table_name
      AND c.column_name = required.column_name
  );

  IF missing_columns IS NOT NULL THEN
    RAISE EXCEPTION 'Northstar Disaster Management preflight failed; missing public columns: %', missing_columns;
  END IF;

  SELECT c.data_type, c.is_nullable INTO profile_id_type, profile_id_nullable
  FROM information_schema.columns AS c
  WHERE c.table_schema = 'public' AND c.table_name = 'profiles' AND c.column_name = 'id';
  IF profile_id_type <> 'uuid' OR profile_id_nullable <> 'NO' THEN
    RAISE EXCEPTION 'Preflight expected public.profiles.id to be a non-null uuid.';
  END IF;

  SELECT c.is_nullable INTO approval_nullable
  FROM information_schema.columns AS c
  WHERE c.table_schema = 'public' AND c.table_name = 'profiles' AND c.column_name = 'approval_status';
  SELECT c.data_type, c.is_nullable INTO registration_type, registration_nullable
  FROM information_schema.columns AS c
  WHERE c.table_schema = 'public' AND c.table_name = 'profiles' AND c.column_name = 'registration_completed';
  IF approval_nullable <> 'YES' OR registration_type <> 'boolean' OR registration_nullable <> 'YES' THEN
    RAISE EXCEPTION 'Preflight expects nullable profiles.approval_status and nullable boolean profiles.registration_completed; existing columns will not be altered.';
  END IF;

  SELECT c.data_type, c.is_nullable, c.column_default
    INTO notification_type_type, notification_type_nullable, notification_type_default
  FROM information_schema.columns AS c
  WHERE c.table_schema = 'public' AND c.table_name = 'notifications' AND c.column_name = 'notification_type';
  notification_type_default := btrim(
    regexp_replace(COALESCE(notification_type_default, ''), '::[[:alpha:]_ ]+', '', 'g'),
    '() '
  );
  IF notification_type_type <> 'text'
     OR notification_type_nullable <> 'NO'
     OR notification_type_default <> '''system''' THEN
    RAISE EXCEPTION 'Preflight expects notifications.notification_type to be NOT NULL text DEFAULT ''system''::text; found type %, nullable %, default %.',
      notification_type_type, notification_type_nullable, notification_type_default;
  END IF;

  -- Check the notification FK and the exact existing identity/target column types.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns AS c
    WHERE c.table_schema = 'public' AND c.table_name = 'notifications'
      AND c.column_name = 'user_id' AND c.data_type = 'uuid' AND c.is_nullable = 'NO'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns AS c
    WHERE c.table_schema = 'public' AND c.table_name = 'notifications'
      AND c.column_name = 'title' AND c.data_type = 'text' AND c.is_nullable = 'NO'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns AS c
    WHERE c.table_schema = 'public' AND c.table_name = 'notifications'
      AND c.column_name = 'message' AND c.data_type = 'text' AND c.is_nullable = 'NO'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns AS c
    WHERE c.table_schema = 'public' AND c.table_name = 'notifications'
      AND c.column_name = 'related_entity_id' AND c.data_type = 'uuid'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns AS c
    WHERE c.table_schema = 'public' AND c.table_name = 'notifications'
      AND c.column_name = 'link_to' AND c.data_type = 'text'
  ) THEN
    RAISE EXCEPTION 'Preflight found incompatible notification column types or nullability.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint AS fk
    JOIN pg_class AS source ON source.oid = fk.conrelid
    JOIN pg_namespace AS source_ns ON source_ns.oid = source.relnamespace
    JOIN pg_class AS target ON target.oid = fk.confrelid
    JOIN pg_namespace AS target_ns ON target_ns.oid = target.relnamespace
    JOIN pg_attribute AS source_column
      ON source_column.attrelid = source.oid
     AND source_column.attname = 'user_id'
     AND source_column.attnum > 0
     AND NOT source_column.attisdropped
    JOIN pg_attribute AS target_column
      ON target_column.attrelid = target.oid
     AND target_column.attname = 'id'
     AND target_column.attnum > 0
     AND NOT target_column.attisdropped
    WHERE fk.contype = 'f' AND source_ns.nspname = 'public' AND source.relname = 'notifications'
      AND target_ns.nspname = 'public' AND target.relname = 'profiles'
      AND fk.conkey = ARRAY[source_column.attnum]::smallint[]
      AND fk.confkey = ARRAY[target_column.attnum]::smallint[]
  ) THEN
    RAISE EXCEPTION 'Preflight expected notifications.user_id to reference public.profiles(id).';
  END IF;

  -- Any other required notification column must be insertable by the trigger
  -- using its default, identity, or generated value.
  SELECT string_agg(c.column_name, ', ' ORDER BY c.column_name)
    INTO extra_required_columns
  FROM information_schema.columns AS c
  WHERE c.table_schema = 'public' AND c.table_name = 'notifications'
    AND c.is_nullable = 'NO'
    AND c.column_name NOT IN ('user_id', 'title', 'message', 'notification_type', 'related_entity_id', 'link_to')
    AND c.column_default IS NULL
    AND c.is_identity = 'NO'
    AND c.is_generated = 'NEVER';
  IF extra_required_columns IS NOT NULL THEN
    RAISE EXCEPTION 'Preflight found additional required notification columns without defaults: %', extra_required_columns;
  END IF;

  SELECT owner.rolname INTO notifications_owner
  FROM pg_class AS relation
  JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
  JOIN pg_roles AS owner ON owner.oid = relation.relowner
  WHERE namespace.nspname = 'public' AND relation.relname = 'notifications' AND relation.relkind = 'r';
  IF notifications_owner IS NULL THEN
    RAISE EXCEPTION 'Preflight expected public.notifications to be an ordinary table.';
  END IF;
  SELECT c.relrowsecurity, c.relforcerowsecurity INTO notifications_rls, notifications_force_rls
  FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'notifications';
  IF NOT notifications_rls THEN
    RAISE EXCEPTION 'Preflight expected RLS to remain enabled on public.notifications.';
  END IF;
  IF notifications_force_rls AND NOT (SELECT r.rolsuper FROM pg_roles AS r WHERE r.rolname = current_user) THEN
    RAISE EXCEPTION 'Preflight cannot guarantee notification trigger inserts under FORCE ROW LEVEL SECURITY for migration role %.', current_user;
  END IF;
  IF current_user <> notifications_owner
     AND NOT (SELECT r.rolsuper FROM pg_roles AS r WHERE r.rolname = current_user) THEN
    RAISE EXCEPTION 'Migration role % must own public.notifications or be a superuser so its SECURITY DEFINER notification trigger can insert without changing notification grants or policies.', current_user;
  END IF;
  IF NOT has_table_privilege(current_user, 'public.notifications', 'INSERT') THEN
    RAISE EXCEPTION 'Migration role % lacks INSERT on public.notifications, required by the SECURITY DEFINER notification trigger.', current_user;
  END IF;

  IF to_regprocedure('public.northstar_is_designated_admin()') IS NULL THEN
    RAISE EXCEPTION 'Preflight expected public.northstar_is_designated_admin().';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM auth.users AS account
    JOIN public.profiles AS profile ON profile.id = account.id
    WHERE lower(account.email) = 'northstaradmin34@gmail.com'
      AND account.email_confirmed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Preflight requires a confirmed designated-admin auth user with a matching public.profiles row, because notifications.user_id references profiles(id).';
  END IF;
END;
$preflight$;

CREATE TABLE public.northstar_incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 5 AND 180),
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 10 AND 10000),
  category text NOT NULL CHECK (category IN ('fire', 'medical', 'security', 'natural_disaster', 'hazardous_material', 'infrastructure', 'other')),
  severity text NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  location text NOT NULL CHECK (length(btrim(location)) BETWEEN 2 AND 500),
  reported_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  reported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'investigating', 'resolved', 'closed')),
  assigned_responder uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  resolution_details text CHECK (resolution_details IS NULL OR length(btrim(resolution_details)) <= 10000),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (status NOT IN ('resolved', 'closed') OR NULLIF(btrim(resolution_details), '') IS NOT NULL)
);

CREATE INDEX northstar_incidents_reporter_time_idx
  ON public.northstar_incidents (reported_by, reported_at DESC);
CREATE INDEX northstar_incidents_status_time_idx
  ON public.northstar_incidents (status, reported_at DESC);
CREATE INDEX northstar_incidents_responder_time_idx
  ON public.northstar_incidents (assigned_responder, updated_at DESC)
  WHERE assigned_responder IS NOT NULL;

CREATE TABLE public.northstar_incident_updates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id uuid NOT NULL REFERENCES public.northstar_incidents(id) ON DELETE RESTRICT,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  event_type text NOT NULL CHECK (event_type IN ('reported', 'status_changed', 'severity_changed', 'responder_changed', 'resolution_changed', 'reporter_update', 'admin_update')),
  visibility text NOT NULL CHECK (visibility IN ('reporter', 'response_team', 'admin')),
  old_status text CHECK (old_status IS NULL OR old_status IN ('open', 'investigating', 'resolved', 'closed')),
  new_status text CHECK (new_status IS NULL OR new_status IN ('open', 'investigating', 'resolved', 'closed')),
  old_severity text CHECK (old_severity IS NULL OR old_severity IN ('low', 'medium', 'high', 'critical')),
  new_severity text CHECK (new_severity IS NULL OR new_severity IN ('low', 'medium', 'high', 'critical')),
  old_assigned_responder uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  new_assigned_responder uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  old_resolution_details text,
  new_resolution_details text,
  details text CHECK (details IS NULL OR length(btrim(details)) <= 10000),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX northstar_incident_updates_thread_idx
  ON public.northstar_incident_updates (incident_id, created_at, id);
CREATE INDEX northstar_incident_updates_visibility_idx
  ON public.northstar_incident_updates (incident_id, visibility, created_at);

ALTER TABLE public.northstar_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.northstar_incident_updates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.northstar_incidents, public.northstar_incident_updates FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.northstar_incidents, public.northstar_incident_updates TO authenticated;

CREATE POLICY northstar_incidents_read_participants_or_admin
ON public.northstar_incidents FOR SELECT TO authenticated
USING (
  public.northstar_is_designated_admin()
  OR reported_by = (SELECT auth.uid())
  OR assigned_responder = (SELECT auth.uid())
);

CREATE POLICY northstar_incident_updates_read_by_visibility
ON public.northstar_incident_updates FOR SELECT TO authenticated
USING (
  public.northstar_is_designated_admin()
  OR (
    visibility = 'reporter'
    AND EXISTS (
      SELECT 1 FROM public.northstar_incidents AS incident
      WHERE incident.id = incident_id AND incident.reported_by = (SELECT auth.uid())
    )
  )
  OR (
    visibility IN ('reporter', 'response_team')
    AND EXISTS (
      SELECT 1 FROM public.northstar_incidents AS incident
      WHERE incident.id = incident_id AND incident.assigned_responder = (SELECT auth.uid())
    )
  )
);

CREATE OR REPLACE FUNCTION public.northstar_report_incident(
  p_title text,
  p_description text,
  p_category text,
  p_severity text,
  p_location text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  incident_id uuid;
  actor_id uuid := auth.uid();
BEGIN
  IF actor_id IS NULL THEN
    RAISE EXCEPTION 'Sign in to report an incident.' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles AS profile
    JOIN auth.users AS account ON account.id = profile.id
    WHERE profile.id = actor_id
      AND profile.role::text IN ('employee', 'manager')
      AND profile.registration_completed IS TRUE
      AND profile.approval_status::text = 'approved'
      AND profile.employment_status::text = 'active'
      AND account.email_confirmed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Only confirmed, approved, active Northstar employees may report incidents.' USING ERRCODE = '42501';
  END IF;
  IF p_title IS NULL OR length(btrim(p_title)) NOT BETWEEN 5 AND 180
     OR p_description IS NULL OR length(btrim(p_description)) NOT BETWEEN 10 AND 10000
     OR p_location IS NULL OR length(btrim(p_location)) NOT BETWEEN 2 AND 500
     OR p_category IS NULL OR p_category NOT IN ('fire', 'medical', 'security', 'natural_disaster', 'hazardous_material', 'infrastructure', 'other')
     OR p_severity IS NULL OR p_severity NOT IN ('low', 'medium', 'high', 'critical') THEN
    RAISE EXCEPTION 'Incident fields are invalid or incomplete.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.northstar_incidents (title, description, category, severity, location, reported_by)
  VALUES (btrim(p_title), btrim(p_description), p_category, p_severity, btrim(p_location), actor_id)
  RETURNING id INTO incident_id;

  INSERT INTO public.northstar_incident_updates (
    incident_id, actor_id, event_type, visibility, new_status, new_severity, details
  ) VALUES (
    incident_id, actor_id, 'reported', 'reporter', 'open', p_severity, 'Incident reported.'
  );
  RETURN incident_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.northstar_admin_update_incident(
  p_incident_id uuid,
  p_status text,
  p_severity text,
  p_assigned_responder uuid,
  p_resolution_details text,
  p_update text,
  p_visibility text DEFAULT 'reporter'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  incident public.northstar_incidents%ROWTYPE;
  admin_id uuid := auth.uid();
  event_name text;
BEGIN
  IF admin_id IS NULL OR NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the confirmed designated Northstar administrator may manage incidents.' USING ERRCODE = '42501';
  END IF;
  IF p_incident_id IS NULL
     OR p_status IS NULL OR p_status NOT IN ('open', 'investigating', 'resolved', 'closed')
     OR p_severity IS NULL OR p_severity NOT IN ('low', 'medium', 'high', 'critical')
     OR p_visibility IS NULL OR p_visibility NOT IN ('reporter', 'response_team', 'admin')
     OR p_update IS NULL OR length(btrim(p_update)) NOT BETWEEN 1 AND 10000
     OR (p_resolution_details IS NOT NULL AND length(btrim(p_resolution_details)) > 10000)
     OR (p_status IN ('resolved', 'closed') AND NULLIF(btrim(p_resolution_details), '') IS NULL) THEN
    RAISE EXCEPTION 'Incident update fields are invalid or incomplete.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO incident FROM public.northstar_incidents AS target
  WHERE target.id = p_incident_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Incident was not found.' USING ERRCODE = 'P0002';
  END IF;

  IF p_assigned_responder IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.profiles AS profile
    JOIN auth.users AS account ON account.id = profile.id
    WHERE profile.id = p_assigned_responder
      AND profile.role::text IN ('employee', 'manager')
      AND profile.registration_completed IS TRUE
      AND profile.approval_status::text = 'approved'
      AND profile.employment_status::text = 'active'
      AND account.email_confirmed_at IS NOT NULL
      AND lower(account.email) <> 'northstaradmin34@gmail.com'
  ) THEN
    RAISE EXCEPTION 'Assigned responder must be a confirmed, approved, active employee.' USING ERRCODE = '22023';
  END IF;

  -- Private admin notes are stored only in the admin-visible audit trail. They
  -- cannot alter incident fields, updated_at, or cause employee notifications.
  IF p_visibility = 'admin' THEN
    IF p_status IS DISTINCT FROM incident.status
       OR p_severity IS DISTINCT FROM incident.severity
       OR p_assigned_responder IS DISTINCT FROM incident.assigned_responder
       OR p_resolution_details IS DISTINCT FROM incident.resolution_details THEN
      RAISE EXCEPTION 'An admin-only note cannot change employee-visible incident fields.' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.northstar_incident_updates (
      incident_id, actor_id, event_type, visibility,
      old_status, new_status, old_severity, new_severity,
      old_assigned_responder, new_assigned_responder,
      old_resolution_details, new_resolution_details, details
    ) VALUES (
      incident.id, admin_id, 'admin_update', 'admin',
      incident.status, incident.status, incident.severity, incident.severity,
      incident.assigned_responder, incident.assigned_responder,
      incident.resolution_details, incident.resolution_details, btrim(p_update)
    );
    RETURN;
  END IF;

  event_name := CASE
    WHEN incident.status IS DISTINCT FROM p_status THEN 'status_changed'
    WHEN incident.severity IS DISTINCT FROM p_severity THEN 'severity_changed'
    WHEN incident.assigned_responder IS DISTINCT FROM p_assigned_responder THEN 'responder_changed'
    WHEN incident.resolution_details IS DISTINCT FROM NULLIF(btrim(p_resolution_details), '') THEN 'resolution_changed'
    ELSE 'reporter_update'
  END;

  UPDATE public.northstar_incidents AS target
  SET status = p_status,
      severity = p_severity,
      assigned_responder = p_assigned_responder,
      resolution_details = NULLIF(btrim(p_resolution_details), ''),
      updated_at = clock_timestamp()
  WHERE target.id = incident.id;

  INSERT INTO public.northstar_incident_updates (
    incident_id, actor_id, event_type, visibility,
    old_status, new_status, old_severity, new_severity,
    old_assigned_responder, new_assigned_responder,
    old_resolution_details, new_resolution_details, details
  ) VALUES (
    incident.id, admin_id, event_name, p_visibility,
    incident.status, p_status, incident.severity, p_severity,
    incident.assigned_responder, p_assigned_responder,
    incident.resolution_details, NULLIF(btrim(p_resolution_details), ''), btrim(p_update)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.northstar_notify_incident_reported()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  admin_id uuid;
BEGIN
  SELECT account.id INTO admin_id
  FROM auth.users AS account
  JOIN public.profiles AS profile ON profile.id = account.id
  WHERE lower(account.email) = 'northstaradmin34@gmail.com'
    AND account.email_confirmed_at IS NOT NULL
  LIMIT 1;

  IF admin_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, title, message, related_entity_id, link_to)
    VALUES (
      admin_id,
      'New Incident Report',
      'A Northstar employee submitted a ' || NEW.severity || ' severity incident report.',
      NEW.id,
      '/disaster-management?incident=' || NEW.id::text
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.northstar_notify_incident_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  incident public.northstar_incidents%ROWTYPE;
BEGIN
  -- No employee notification is emitted for admin-only notes or any event
  -- written under a non-admin execution context.
  IF NEW.visibility = 'admin'
     OR NEW.event_type = 'admin_update'
     OR NOT public.northstar_is_designated_admin() THEN
    RETURN NEW;
  END IF;

  SELECT * INTO incident FROM public.northstar_incidents AS target WHERE target.id = NEW.incident_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  IF NEW.visibility = 'reporter' THEN
    INSERT INTO public.notifications (user_id, title, message, related_entity_id, link_to)
    VALUES (
      incident.reported_by,
      'Incident Report Update',
      'An administrator updated the status of your incident report.',
      incident.id,
      '/disaster-management?incident=' || incident.id::text
    );
  END IF;

  IF NEW.visibility = 'response_team'
     AND incident.assigned_responder IS NOT NULL
     AND incident.assigned_responder <> incident.reported_by THEN
    INSERT INTO public.notifications (user_id, title, message, related_entity_id, link_to)
    VALUES (
      incident.assigned_responder,
      'Incident Response Update',
      'An administrator updated an incident assigned to you.',
      incident.id,
      '/disaster-management?incident=' || incident.id::text
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER northstar_incident_report_notification
AFTER INSERT ON public.northstar_incidents
FOR EACH ROW EXECUTE FUNCTION public.northstar_notify_incident_reported();

CREATE TRIGGER northstar_incident_update_notification
AFTER INSERT ON public.northstar_incident_updates
FOR EACH ROW EXECUTE FUNCTION public.northstar_notify_incident_update();

REVOKE ALL ON FUNCTION public.northstar_report_incident(text, text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.northstar_admin_update_incident(uuid, text, text, uuid, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.northstar_notify_incident_reported() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.northstar_notify_incident_update() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_report_incident(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.northstar_admin_update_incident(uuid, text, text, uuid, text, text, text) TO authenticated;

-- Keep changes to the existing notifications object limited to inserts performed
-- by these SECURITY DEFINER trigger functions. The migration owner must own that
-- table (checked above); its existing authenticated grants and RLS policies stay intact.

-- Realtime is optional: add only the new tables when the publication is present,
-- and skip tables already published. This does not alter existing publication members.
DO $realtime$
DECLARE
  table_name text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH table_name IN ARRAY ARRAY['northstar_incidents', 'northstar_incident_updates'] LOOP
      IF NOT EXISTS (
        SELECT 1
        FROM pg_publication_tables AS member
        WHERE member.pubname = 'supabase_realtime'
          AND member.schemaname = 'public'
          AND member.tablename = table_name
      ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', table_name);
      END IF;
    END LOOP;
  END IF;
END;
$realtime$;

NOTIFY pgrst, 'reload schema';

COMMIT;
