-- Keep the internal Supabase Auth UUID out of client-readable profile fields.
REVOKE SELECT ON TABLE public.profiles FROM anon, authenticated;
GRANT SELECT (
  id,
  username,
  display_name,
  bio,
  avatar_url,
  cover_url,
  location,
  website,
  is_verified,
  followers_count,
  following_count,
  created_at,
  updated_at
) ON TABLE public.profiles TO anon, authenticated;

-- Publish scheduled posts without requiring a user to keep the browser open.
-- Supabase Cron uses the built-in pg_cron extension; one low-frequency job is sufficient.
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;

CREATE OR REPLACE FUNCTION private.publish_due_posts()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  published_count integer;
BEGIN
  UPDATE public.posts
  SET scheduled_at = NULL,
      updated_at = pg_catalog.now()
  WHERE scheduled_at IS NOT NULL
    AND scheduled_at <= pg_catalog.now()
    AND deleted_at IS NULL;

  GET DIAGNOSTICS published_count = ROW_COUNT;
  RETURN published_count;
END;
$function$;

REVOKE ALL ON FUNCTION private.publish_due_posts() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.publish_due_posts() TO postgres;

DO $schedule$
DECLARE
  existing_job_id bigint;
BEGIN
  FOR existing_job_id IN
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'lime2-publish-due-posts'
  LOOP
    PERFORM cron.unschedule(existing_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'lime2-publish-due-posts',
    '*/5 * * * *',
    'SELECT private.publish_due_posts();'
  );
END;
$schedule$;
