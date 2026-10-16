-- Northstar in-app notification events and optional web push subscriptions.
-- Requires the existing profiles, departments, auth.users, notifications,
-- user_preferences, employee_registration_snapshots, conversations,
-- conversation_members, and messages objects used by the frontend.

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS link_to text,
  ADD COLUMN IF NOT EXISTS dedupe_key text,
  ADD COLUMN IF NOT EXISTS read_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS notifications_dedupe_key_uidx
  ON public.notifications (dedupe_key);

-- Notifications are recipient-private. Creation is performed only by trusted
-- database triggers; authenticated clients may read/update/delete only their rows.
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notifications FROM PUBLIC, anon, authenticated;
REVOKE UPDATE (user_id, title, message, notification_type, is_read, read_at, created_at, link_to, dedupe_key)
  ON public.notifications FROM authenticated;
GRANT SELECT, DELETE ON public.notifications TO authenticated;
GRANT UPDATE (is_read, read_at) ON public.notifications TO authenticated;
GRANT SELECT ON public.notifications TO service_role;

DROP POLICY IF EXISTS northstar_notifications_owner_guard ON public.notifications;
DROP POLICY IF EXISTS northstar_notifications_select_own ON public.notifications;
DROP POLICY IF EXISTS northstar_notifications_update_own ON public.notifications;
DROP POLICY IF EXISTS northstar_notifications_delete_own ON public.notifications;

CREATE POLICY northstar_notifications_owner_guard
ON public.notifications AS RESTRICTIVE FOR ALL TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY northstar_notifications_select_own
ON public.notifications FOR SELECT TO authenticated
USING (user_id = (SELECT auth.uid()));
CREATE POLICY northstar_notifications_update_own
ON public.notifications FOR UPDATE TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY northstar_notifications_delete_own
ON public.notifications FOR DELETE TO authenticated
USING (user_id = (SELECT auth.uid()));

CREATE TABLE IF NOT EXISTS public.northstar_push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint text NOT NULL UNIQUE,
  subscription jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.northstar_push_subscriptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.northstar_push_subscriptions FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.northstar_push_subscriptions TO authenticated;
GRANT ALL ON public.northstar_push_subscriptions TO service_role;
DROP POLICY IF EXISTS northstar_push_subscription_owner_guard ON public.northstar_push_subscriptions;
DROP POLICY IF EXISTS northstar_push_subscription_owner ON public.northstar_push_subscriptions;
CREATE POLICY northstar_push_subscription_owner_guard
ON public.northstar_push_subscriptions AS RESTRICTIVE FOR ALL TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY northstar_push_subscription_owner
ON public.northstar_push_subscriptions FOR ALL TO authenticated
USING (user_id = (SELECT auth.uid()))
WITH CHECK (user_id = (SELECT auth.uid()));

-- A webhook may be retried. This private delivery ledger limits delivery to
-- once per notification/device endpoint.
CREATE TABLE IF NOT EXISTS public.northstar_push_deliveries (
  notification_id uuid NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
  endpoint text NOT NULL,
  status text NOT NULL DEFAULT 'claimed' CHECK (status IN ('claimed', 'sent', 'failed')),
  attempted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (notification_id, endpoint)
);
ALTER TABLE public.northstar_push_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.northstar_push_deliveries FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.northstar_push_deliveries TO service_role;

CREATE OR REPLACE FUNCTION public.northstar_notify_profile_events()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  admin_user_id uuid;
  submission_id uuid;
  submission_time timestamptz;
  recipient record;
  department_name text;
  employee_name text;
  notification_message text;
BEGIN
  IF NEW.registration_completed IS TRUE
     AND EXISTS (
       SELECT 1 FROM auth.users AS account
       WHERE account.id = NEW.id AND account.email_confirmed_at IS NOT NULL
     )
     AND (
       OLD.registration_completed IS DISTINCT FROM TRUE
       OR (OLD.approval_status = 'rejected' AND NEW.approval_status = 'pending')
     ) THEN
    SELECT snapshot.id, snapshot.submitted_at
    INTO submission_id, submission_time
    FROM public.employee_registration_snapshots AS snapshot
    WHERE snapshot.user_id = NEW.id
    ORDER BY snapshot.submitted_at DESC, snapshot.id DESC
    LIMIT 1;

    SELECT account.id INTO admin_user_id
    FROM auth.users AS account
    WHERE lower(account.email) = 'northstaradmin34@gmail.com'
      AND account.email_confirmed_at IS NOT NULL
    LIMIT 1;

    IF admin_user_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, title, message, notification_type, link_to, dedupe_key)
      VALUES (
        admin_user_id,
        'Employee Registration Awaiting Review',
        concat_ws(' ', NEW.first_name, NEW.last_name, 'submitted an employee registration for review.'),
        'people',
        '/admin?registration=' || NEW.id::text,
        'registration-submitted:' || NEW.id::text || ':' || COALESCE(submission_id::text, COALESCE(submission_time::text, statement_timestamp()::text))
      ) ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
  END IF;

  IF NEW.registration_completed IS TRUE
     AND (
       (NEW.approval_status = 'approved'
        AND NEW.employment_status = 'active'
        AND (OLD.approval_status IS DISTINCT FROM 'approved'
          OR OLD.employment_status IS DISTINCT FROM 'active'))
       OR (
         NEW.approval_status = 'rejected'
         AND NULLIF(btrim(NEW.rejection_reason), '') IS NOT NULL
         AND (OLD.approval_status IS DISTINCT FROM 'rejected' OR OLD.rejection_reason IS DISTINCT FROM NEW.rejection_reason)
       )
     )
     AND EXISTS (
       SELECT 1 FROM auth.users AS account
       WHERE account.id = NEW.id AND account.email_confirmed_at IS NOT NULL
     ) THEN
    SELECT snapshot.id INTO submission_id
    FROM public.employee_registration_snapshots AS snapshot
    WHERE snapshot.user_id = NEW.id
    ORDER BY snapshot.submitted_at DESC, snapshot.id DESC
    LIMIT 1;

    IF NEW.approval_status = 'approved' AND NEW.employment_status = 'active' THEN
      notification_message := 'Your Northstar employee registration has been approved. You can now access the Northstar workspace.';
      INSERT INTO public.notifications (user_id, title, message, notification_type, link_to, dedupe_key)
      VALUES (NEW.id, 'Registration Approved', notification_message, 'people', '/overview',
        'registration-decision:' || NEW.id::text || ':' || COALESCE(submission_id::text, statement_timestamp()::text) || ':approved')
      ON CONFLICT (dedupe_key) DO NOTHING;
    ELSE
      notification_message := 'Your Northstar employee registration was not approved. Please review the reason and follow the instructions provided.'
        || CASE WHEN NULLIF(btrim(NEW.rejection_reason), '') IS NULL THEN '' ELSE ' Reason: ' || btrim(NEW.rejection_reason) END;
      INSERT INTO public.notifications (user_id, title, message, notification_type, link_to, dedupe_key)
      VALUES (NEW.id, 'Registration Update', notification_message, 'people', '/pending-approval',
        'registration-decision:' || NEW.id::text || ':' || COALESCE(submission_id::text, statement_timestamp()::text) || ':rejected')
      ON CONFLICT (dedupe_key) DO NOTHING;
    END IF;
  END IF;

  IF NEW.registration_completed IS TRUE
     AND NEW.approval_status = 'approved'
     AND NEW.employment_status = 'active'
     AND (OLD.approval_status IS DISTINCT FROM 'approved' OR OLD.employment_status IS DISTINCT FROM 'active')
     AND EXISTS (
       SELECT 1 FROM auth.users AS account
       WHERE account.id = NEW.id AND account.email_confirmed_at IS NOT NULL
     ) THEN
    SELECT snapshot.id INTO submission_id
    FROM public.employee_registration_snapshots AS snapshot
    WHERE snapshot.user_id = NEW.id
    ORDER BY snapshot.submitted_at DESC, snapshot.id DESC
    LIMIT 1;

    SELECT department.name INTO department_name
    FROM public.departments AS department WHERE department.id = NEW.department_id;
    employee_name := COALESCE(NULLIF(btrim(concat_ws(' ', NEW.first_name, NEW.last_name)), ''), 'A new colleague');
    FOR recipient IN
      SELECT profile.id AS user_id
      FROM public.profiles AS profile
      JOIN auth.users AS account ON account.id = profile.id
      WHERE profile.id <> NEW.id
        AND profile.role IN ('employee', 'manager')
        AND profile.registration_completed IS TRUE
        AND profile.approval_status = 'approved'
        AND profile.employment_status = 'active'
        AND account.email_confirmed_at IS NOT NULL
        AND lower(account.email) <> 'northstaradmin34@gmail.com'
    LOOP
      INSERT INTO public.notifications (user_id, title, message, notification_type, link_to, dedupe_key)
      VALUES (
        recipient.user_id,
        'New Employee Joined',
        employee_name || ' joined ' || COALESCE(department_name, 'Northstar') || '.',
        'people',
        '/employees?employee=' || NEW.id::text,
        'new-employee:' || COALESCE(submission_id::text, NEW.id::text) || ':' || recipient.user_id::text
      ) ON CONFLICT (dedupe_key) DO NOTHING;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS northstar_notify_profile_events ON public.profiles;
CREATE TRIGGER northstar_notify_profile_events
AFTER UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.northstar_notify_profile_events();
REVOKE ALL ON FUNCTION public.northstar_notify_profile_events() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.northstar_notify_direct_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  recipient record;
  sender_name text;
  preference jsonb;
BEGIN
  SELECT NULLIF(btrim(concat_ws(' ', profile.first_name, profile.last_name)), '')
  INTO sender_name
  FROM public.profiles AS profile WHERE profile.id = NEW.sender_id;
  sender_name := COALESCE(sender_name, 'A colleague');

  FOR recipient IN
    SELECT member.user_id
    FROM public.conversation_members AS member
    JOIN public.profiles AS profile ON profile.id = member.user_id
    JOIN auth.users AS account ON account.id = member.user_id
    LEFT JOIN public.user_preferences AS prefs ON prefs.user_id = member.user_id
    WHERE member.conversation_id = NEW.conversation_id
      AND member.user_id <> NEW.sender_id
      AND profile.approval_status = 'approved'
      AND profile.employment_status = 'active'
      AND account.email_confirmed_at IS NOT NULL
      AND COALESCE(prefs.preferences -> 'messages' <> 'false'::jsonb, true)
  LOOP
    INSERT INTO public.notifications (user_id, title, message, notification_type, link_to, dedupe_key)
    VALUES (
      recipient.user_id,
      'New message from ' || sender_name,
      left(NEW.content, 180),
      'message',
      '/messages?conversation=' || NEW.conversation_id::text,
      'message:' || NEW.id::text || ':' || recipient.user_id::text
    ) ON CONFLICT (dedupe_key) DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS northstar_notify_direct_message ON public.messages;
CREATE TRIGGER northstar_notify_direct_message
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.northstar_notify_direct_message();
REVOKE ALL ON FUNCTION public.northstar_notify_direct_message() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
