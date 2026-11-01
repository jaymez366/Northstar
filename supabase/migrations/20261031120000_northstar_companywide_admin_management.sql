-- Give designated administrators organization-wide oversight while keeping
-- department-specific writes with each department's assigned head.
-- Apply after the three NorthStar migrations dated October 28-30, 2026.
BEGIN;

DO $preflight$
DECLARE
  missing_columns text;
BEGIN
  SELECT string_agg(required.table_name || '.' || required.column_name, ', ' ORDER BY required.table_name, required.column_name)
  INTO missing_columns
  FROM (VALUES
    ('announcements', 'author_id'), ('announcements', 'department_id'), ('announcements', 'priority'),
    ('events', 'organizer_id'), ('events', 'department_id'),
    ('resources', 'uploaded_by'), ('resources', 'department_id'), ('resources', 'storage_path'),
    ('northstar_incidents', 'reported_by'), ('northstar_incidents', 'department_id'), ('northstar_incidents', 'deleted_at'),
    ('northstar_incident_updates', 'incident_id'), ('northstar_incident_updates', 'actor_id'),
    ('northstar_incident_updates', 'event_type'), ('northstar_incident_updates', 'visibility')
  ) AS required(table_name, column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns AS actual
    WHERE actual.table_schema = 'public' AND actual.table_name = required.table_name
      AND actual.column_name = required.column_name
  );
  IF missing_columns IS NOT NULL THEN
    RAISE EXCEPTION 'NorthStar company-wide management preflight failed; missing columns: %', missing_columns;
  END IF;

  IF to_regprocedure('public.northstar_is_designated_admin()') IS NULL
     OR to_regprocedure('northstar_private.is_department_head(uuid)') IS NULL
     OR to_regprocedure('northstar_private.resource_object_managed_by_department_head(text)') IS NULL
     OR to_regprocedure('public.northstar_department_list_incidents()') IS NULL THEN
    RAISE EXCEPTION 'NorthStar company-wide management requires the applied department, incident, and resource authorization functions.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid IN ('public.announcements'::regclass, 'public.events'::regclass,
      'public.resources'::regclass, 'public.northstar_incidents'::regclass)
      AND relrowsecurity IS FALSE
  ) THEN
    RAISE EXCEPTION 'NorthStar company-wide management requires RLS to remain enabled on announcements, events, resources, and incidents.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('announcements', 'northstar_department_announcements_guard', 'r'::char, false),
      ('announcements', 'northstar_department_announcements_select', 'r'::char, true),
      ('announcements', 'northstar_department_announcements_insert_guard', 'a'::char, false),
      ('announcements', 'northstar_department_announcements_insert_policy', 'a'::char, true),
      ('announcements', 'northstar_department_announcements_update_guard', 'w'::char, false),
      ('announcements', 'northstar_department_announcements_update_policy', 'w'::char, true),
      ('announcements', 'northstar_department_announcements_delete_guard', 'd'::char, false),
      ('announcements', 'northstar_department_announcements_delete_policy', 'd'::char, true),
      ('events', 'northstar_department_events_guard', 'r'::char, false),
      ('events', 'northstar_department_events_select_policy', 'r'::char, true),
      ('events', 'northstar_department_events_insert_guard', 'a'::char, false),
      ('events', 'northstar_department_events_insert_policy', 'a'::char, true),
      ('events', 'northstar_department_events_update_guard', 'w'::char, false),
      ('events', 'northstar_department_events_update_policy', 'w'::char, true),
      ('events', 'northstar_department_events_delete_guard', 'd'::char, false),
      ('events', 'northstar_department_events_delete_policy', 'd'::char, true),
      ('resources', 'northstar_department_resources_guard', 'r'::char, false),
      ('resources', 'northstar_department_resources_select_policy', 'r'::char, true),
      ('resources', 'northstar_department_resources_insert_guard', 'a'::char, false),
      ('resources', 'northstar_department_resources_insert_policy', 'a'::char, true),
      ('resources', 'northstar_department_resources_update_guard', 'w'::char, false),
      ('resources', 'northstar_department_resources_update_policy', 'w'::char, true),
      ('resources', 'northstar_department_resources_delete_guard', 'd'::char, false),
      ('resources', 'northstar_department_resources_delete_policy', 'd'::char, true),
      ('storage.objects', 'northstar_company_resources_department_guard', 'r'::char, false),
      ('storage.objects', 'northstar_company_resources_insert_guard', 'a'::char, false),
      ('storage.objects', 'northstar_company_resources_update_guard', 'w'::char, false),
      ('storage.objects', 'northstar_company_resources_delete_guard', 'd'::char, false),
      ('storage.objects', 'northstar_company_resources_department_insert_guard', 'a'::char, false),
      ('storage.objects', 'northstar_company_resources_department_update_guard', 'w'::char, false),
      ('storage.objects', 'northstar_company_resources_department_delete_guard', 'd'::char, false),
      ('storage.objects', 'northstar_company_resources_anon_select_guard', 'r'::char, false),
      ('storage.objects', 'northstar_company_resources_anon_insert_guard', 'a'::char, false),
      ('storage.objects', 'northstar_company_resources_anon_update_guard', 'w'::char, false),
      ('storage.objects', 'northstar_company_resources_anon_delete_guard', 'd'::char, false)
    ) AS expected(table_name, policy_name, command, permissive)
    LEFT JOIN pg_class AS relation ON relation.oid = to_regclass(expected.table_name)
    LEFT JOIN pg_policy AS policy ON policy.polrelid = relation.oid AND policy.polname = expected.policy_name
    WHERE policy.oid IS NULL OR policy.polcmd <> expected.command
      OR policy.polpermissive IS DISTINCT FROM expected.permissive
      OR policy.polroles <> CASE
        WHEN expected.policy_name = ANY(ARRAY[
          'northstar_company_resources_anon_select_guard',
          'northstar_company_resources_anon_insert_guard',
          'northstar_company_resources_anon_update_guard',
          'northstar_company_resources_anon_delete_guard'
        ]) THEN ARRAY['anon'::regrole::oid]
        ELSE ARRAY['authenticated'::regrole::oid]
      END
  ) THEN
    RAISE EXCEPTION 'A required NorthStar content or Storage policy is missing or differs from its expected command, role, or restrictive status.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policy AS policy
    WHERE policy.polrelid IN (
      'public.announcements'::regclass, 'public.events'::regclass, 'public.resources'::regclass
    )
      AND policy.polpermissive IS FALSE
      AND EXISTS (
        SELECT 1 FROM unnest(policy.polroles) AS target_role(role_oid)
        WHERE target_role.role_oid = 0 OR pg_has_role('authenticated', target_role.role_oid, 'USAGE')
      )
      AND NOT (
        (policy.polrelid = 'public.announcements'::regclass AND policy.polname = ANY(ARRAY[
          'northstar_department_announcements_guard',
          'northstar_department_announcements_insert_guard',
          'northstar_department_announcements_update_guard',
          'northstar_department_announcements_delete_guard'
        ]))
        OR (policy.polrelid = 'public.events'::regclass AND policy.polname = ANY(ARRAY[
          'northstar_events_designated_admin_insert_guard',
          'northstar_events_designated_admin_update_guard',
          'northstar_events_designated_admin_delete_guard',
          'northstar_department_events_guard',
          'northstar_department_events_insert_guard',
          'northstar_department_events_update_guard',
          'northstar_department_events_delete_guard'
        ]))
        OR (policy.polrelid = 'public.resources'::regclass AND policy.polname = ANY(ARRAY[
          'northstar_resources_designated_admin_insert_guard',
          'northstar_resources_designated_admin_update_guard',
          'northstar_resources_designated_admin_delete_guard',
          'northstar_department_resources_guard',
          'northstar_department_resources_insert_guard',
          'northstar_department_resources_update_guard',
          'northstar_department_resources_delete_guard'
        ]))
      )
  ) THEN
    RAISE EXCEPTION 'NorthStar company-wide management found an unreviewed restrictive content policy; inspect RLS policies before continuing.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policy AS policy
    WHERE policy.polrelid = 'storage.objects'::regclass AND policy.polpermissive IS FALSE
      AND EXISTS (
        SELECT 1 FROM unnest(policy.polroles) AS target_role(role_oid)
        WHERE target_role.role_oid = 0
          OR pg_has_role('authenticated', target_role.role_oid, 'USAGE')
          OR pg_has_role('anon', target_role.role_oid, 'USAGE')
      )
      AND policy.polname <> ALL(ARRAY[
        'northstar_company_resources_insert_guard',
        'northstar_company_resources_update_guard',
        'northstar_company_resources_delete_guard',
        'northstar_company_resources_department_guard',
        'northstar_company_resources_department_insert_guard',
        'northstar_company_resources_department_update_guard',
        'northstar_company_resources_department_delete_guard',
        'northstar_company_resources_anon_select_guard',
        'northstar_company_resources_anon_insert_guard',
        'northstar_company_resources_anon_update_guard',
        'northstar_company_resources_anon_delete_guard',
        'northstar_message_attachments_upload_guard',
        'northstar_message_attachments_read_guard',
        'northstar_message_attachments_anon_read_guard',
        'northstar_message_attachments_anon_upload_guard',
        'northstar_message_attachments_no_update_guard',
        'northstar_message_attachments_no_delete_guard',
        'northstar_message_attachments_anon_no_update_guard',
        'northstar_message_attachments_anon_no_delete_guard',
        'northstar_profile_avatars_select_guard',
        'northstar_profile_avatars_anon_select_guard',
        'northstar_profile_avatars_insert_guard',
        'northstar_profile_avatars_anon_insert_guard'
      ])
  ) THEN
    RAISE EXCEPTION 'NorthStar company-wide management found an unreviewed restrictive Storage policy; inspect storage.objects policies before continuing.';
  END IF;
END;
$preflight$;

-- Department heads own department content; admins create and manage only the
-- company-wide content rows through the organization-wide interfaces.
ALTER POLICY northstar_department_announcements_insert_guard ON public.announcements
WITH CHECK (
  (public.northstar_is_designated_admin() AND department_id IS NULL AND author_id = (SELECT auth.uid()))
  OR (department_id IS NOT NULL AND author_id = (SELECT auth.uid())
    AND northstar_private.is_department_head(department_id))
);
ALTER POLICY northstar_department_announcements_insert_policy ON public.announcements
WITH CHECK (
  (public.northstar_is_designated_admin() AND department_id IS NULL AND author_id = (SELECT auth.uid()))
  OR (department_id IS NOT NULL AND author_id = (SELECT auth.uid())
    AND northstar_private.is_department_head(department_id))
);
ALTER POLICY northstar_department_announcements_update_policy ON public.announcements
USING (
  (public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id)
)
WITH CHECK (
  (public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id)
);
ALTER POLICY northstar_department_announcements_update_guard ON public.announcements
USING (
  (public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id)
)
WITH CHECK (
  (public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id)
);
ALTER POLICY northstar_department_announcements_delete_policy ON public.announcements
USING ((public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id));
ALTER POLICY northstar_department_announcements_delete_guard ON public.announcements
USING ((public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id));

-- Keep announcement updates column-scoped while allowing the admin and
-- department-head roles authorized above to edit announcement content.
REVOKE UPDATE ON public.announcements FROM authenticated;
GRANT UPDATE (title, content, priority, is_pinned) ON public.announcements TO authenticated;

ALTER POLICY northstar_department_events_insert_policy ON public.events
WITH CHECK (
  (public.northstar_is_designated_admin() AND department_id IS NULL AND organizer_id = (SELECT auth.uid()))
  OR (organizer_id = (SELECT auth.uid()) AND northstar_private.is_department_head(department_id))
);
ALTER POLICY northstar_department_events_insert_guard ON public.events
WITH CHECK (
  (public.northstar_is_designated_admin() AND department_id IS NULL AND organizer_id = (SELECT auth.uid()))
  OR (organizer_id = (SELECT auth.uid()) AND northstar_private.is_department_head(department_id))
);
ALTER POLICY northstar_department_events_update_policy ON public.events
USING ((public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id))
WITH CHECK ((public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id));
ALTER POLICY northstar_department_events_update_guard ON public.events
USING ((public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id))
WITH CHECK ((public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id));
ALTER POLICY northstar_department_events_delete_policy ON public.events
USING ((public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id));
ALTER POLICY northstar_department_events_delete_guard ON public.events
USING ((public.northstar_is_designated_admin() AND department_id IS NULL)
  OR northstar_private.is_department_head(department_id));

ALTER POLICY northstar_department_resources_insert_policy ON public.resources
WITH CHECK (
  (public.northstar_is_designated_admin() AND department_id IS NULL
    AND uploaded_by = (SELECT auth.uid()) AND storage_path NOT LIKE 'departments/%')
  OR (uploaded_by = (SELECT auth.uid()) AND northstar_private.is_department_head(department_id)
    AND storage_path LIKE ('departments/' || department_id::text || '/resources/%'))
);
ALTER POLICY northstar_department_resources_insert_guard ON public.resources
WITH CHECK (
  (public.northstar_is_designated_admin() AND department_id IS NULL
    AND uploaded_by = (SELECT auth.uid()) AND storage_path NOT LIKE 'departments/%')
  OR (uploaded_by = (SELECT auth.uid()) AND northstar_private.is_department_head(department_id)
    AND storage_path LIKE ('departments/' || department_id::text || '/resources/%'))
);
ALTER POLICY northstar_department_resources_update_policy ON public.resources
USING ((public.northstar_is_designated_admin() AND department_id IS NULL
    AND storage_path NOT LIKE 'departments/%')
  OR northstar_private.is_department_head(department_id))
WITH CHECK ((public.northstar_is_designated_admin() AND department_id IS NULL
    AND storage_path NOT LIKE 'departments/%')
  OR northstar_private.is_department_head(department_id));
ALTER POLICY northstar_department_resources_update_guard ON public.resources
USING ((public.northstar_is_designated_admin() AND department_id IS NULL
    AND storage_path NOT LIKE 'departments/%')
  OR northstar_private.is_department_head(department_id))
WITH CHECK ((public.northstar_is_designated_admin() AND department_id IS NULL
    AND storage_path NOT LIKE 'departments/%')
  OR northstar_private.is_department_head(department_id));
ALTER POLICY northstar_department_resources_delete_policy ON public.resources
USING ((public.northstar_is_designated_admin() AND department_id IS NULL
    AND storage_path NOT LIKE 'departments/%')
  OR northstar_private.is_department_head(department_id));
ALTER POLICY northstar_department_resources_delete_guard ON public.resources
USING ((public.northstar_is_designated_admin() AND department_id IS NULL
    AND storage_path NOT LIKE 'departments/%')
  OR northstar_private.is_department_head(department_id));

-- Keep department resource file operations with the matching active head.
-- Admins retain upload, update, and delete access for organization-wide paths.
CREATE OR REPLACE FUNCTION northstar_private.resource_object_managed_by_department_head(p_object_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $function$
  SELECT EXISTS (
      SELECT 1 FROM public.resources AS resource_row
      WHERE resource_row.storage_path = p_object_name
        AND northstar_private.is_department_head(resource_row.department_id)
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles AS profile
      WHERE profile.id = auth.uid()
        AND northstar_private.is_department_head(profile.department_id)
        AND p_object_name LIKE ('departments/' || profile.department_id::text || '/resources/%')
    );
$function$;
ALTER FUNCTION northstar_private.resource_object_managed_by_department_head(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION northstar_private.resource_object_managed_by_department_head(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION northstar_private.resource_object_managed_by_department_head(text) TO authenticated;

ALTER POLICY northstar_company_resources_insert_guard ON storage.objects
WITH CHECK (bucket_id <> 'company-resources' OR (
  (public.northstar_is_designated_admin() AND name NOT LIKE 'departments/%')
  OR EXISTS (
    SELECT 1 FROM public.profiles AS profile
    WHERE profile.id = auth.uid()
      AND northstar_private.is_department_head(profile.department_id)
      AND name LIKE ('departments/' || profile.department_id::text || '/resources/%')
  )
));
ALTER POLICY northstar_company_resources_department_insert_guard ON storage.objects
WITH CHECK (bucket_id <> 'company-resources' OR (
  (public.northstar_is_designated_admin() AND name NOT LIKE 'departments/%')
  OR EXISTS (
    SELECT 1 FROM public.profiles AS profile
    WHERE profile.id = auth.uid()
      AND northstar_private.is_department_head(profile.department_id)
      AND name LIKE ('departments/' || profile.department_id::text || '/resources/%')
  )
));
ALTER POLICY northstar_company_resources_update_guard ON storage.objects
USING (bucket_id <> 'company-resources' OR (
  (public.northstar_is_designated_admin() AND name NOT LIKE 'departments/%')
  OR northstar_private.resource_object_managed_by_department_head(name)
))
WITH CHECK (bucket_id <> 'company-resources' OR (
  (public.northstar_is_designated_admin() AND name NOT LIKE 'departments/%')
  OR northstar_private.resource_object_managed_by_department_head(name)
));
ALTER POLICY northstar_company_resources_department_update_guard ON storage.objects
USING (bucket_id <> 'company-resources' OR (
  (public.northstar_is_designated_admin() AND name NOT LIKE 'departments/%')
  OR northstar_private.resource_object_managed_by_department_head(name)
))
WITH CHECK (bucket_id <> 'company-resources' OR (
  (public.northstar_is_designated_admin() AND name NOT LIKE 'departments/%')
  OR northstar_private.resource_object_managed_by_department_head(name)
));
ALTER POLICY northstar_company_resources_delete_guard ON storage.objects
USING (bucket_id <> 'company-resources' OR (
  (public.northstar_is_designated_admin() AND name NOT LIKE 'departments/%')
  OR northstar_private.resource_object_managed_by_department_head(name)
));
ALTER POLICY northstar_company_resources_department_delete_guard ON storage.objects
USING (bucket_id <> 'company-resources' OR (
  (public.northstar_is_designated_admin() AND name NOT LIKE 'departments/%')
  OR northstar_private.resource_object_managed_by_department_head(name)
));

-- Admins may create only null-department incidents. The existing incident
-- updater now also targets null-department rows only, leaving department
-- incident updates to northstar_department_head_update_incident.
CREATE OR REPLACE FUNCTION public.northstar_admin_report_company_incident(
  p_title text, p_description text, p_category text, p_severity text, p_location text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET row_security = off
AS $function$
DECLARE
  incident_id uuid;
  admin_id uuid := auth.uid();
BEGIN
  IF admin_id IS NULL OR NOT public.northstar_is_designated_admin() THEN
    RAISE EXCEPTION 'Only the confirmed designated NorthStar administrator may create organization-wide incidents.' USING ERRCODE = '42501';
  END IF;
  IF p_title IS NULL OR length(btrim(p_title)) NOT BETWEEN 5 AND 180
     OR p_description IS NULL OR length(btrim(p_description)) NOT BETWEEN 10 AND 10000
     OR p_location IS NULL OR length(btrim(p_location)) NOT BETWEEN 2 AND 500
     OR p_category IS NULL OR p_category NOT IN ('fire', 'medical', 'security', 'natural_disaster', 'hazardous_material', 'infrastructure', 'other')
     OR p_severity IS NULL OR p_severity NOT IN ('low', 'medium', 'high', 'critical') THEN
    RAISE EXCEPTION 'Incident fields are invalid or incomplete.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.northstar_incidents (
    title, description, category, severity, location, reported_by, department_id
  ) VALUES (
    btrim(p_title), btrim(p_description), p_category, p_severity, btrim(p_location), admin_id, NULL
  ) RETURNING id INTO incident_id;

  INSERT INTO public.northstar_incident_updates (
    incident_id, actor_id, event_type, visibility, new_status, new_severity, details
  ) VALUES (
    incident_id, admin_id, 'reported', 'reporter', 'open', p_severity, 'Organization-wide incident created by the designated administrator.'
  );
  RETURN incident_id;
END;
$function$;
ALTER FUNCTION public.northstar_admin_report_company_incident(text, text, text, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_admin_report_company_incident(text, text, text, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.northstar_admin_report_company_incident(text, text, text, text, text) TO authenticated;

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
    RAISE EXCEPTION 'Only the confirmed designated NorthStar administrator may manage incidents.' USING ERRCODE = '42501';
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
  WHERE target.id = p_incident_id AND target.department_id IS NULL FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization-wide incident was not found.' USING ERRCODE = 'P0002';
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
  WHERE target.id = incident.id AND target.department_id IS NULL;

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
ALTER FUNCTION public.northstar_admin_update_incident(uuid, text, text, uuid, text, text, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.northstar_admin_update_incident(uuid, text, text, uuid, text, text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.northstar_admin_update_incident(uuid, text, text, uuid, text, text, text) TO authenticated;

DO $acl_verify$
BEGIN
  IF has_function_privilege('anon', 'public.northstar_admin_report_company_incident(text,text,text,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.northstar_admin_update_incident(uuid,text,text,uuid,text,text,text)', 'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM pg_proc AS procedure_row
       CROSS JOIN LATERAL aclexplode(coalesce(procedure_row.proacl, acldefault('f', procedure_row.proowner))) AS privilege_row
       WHERE procedure_row.oid IN (
         'public.northstar_admin_report_company_incident(text,text,text,text,text)'::regprocedure,
         'public.northstar_admin_update_incident(uuid,text,text,uuid,text,text,text)'::regprocedure
       ) AND privilege_row.grantee = 0 AND privilege_row.privilege_type = 'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'Company-wide incident RPCs must not be executable by anon or PUBLIC.';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.northstar_admin_report_company_incident(text,text,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.northstar_admin_update_incident(uuid,text,text,uuid,text,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated callers must be able to invoke the designated-administrator-guarded company-wide incident RPCs.';
  END IF;
END;
$acl_verify$;

COMMIT;
