-- Refresh visible poll counts through the existing posts Realtime subscription.
-- Raw poll_votes remain private; clients continue to read only aggregate results.
CREATE OR REPLACE FUNCTION private.notify_poll_vote_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  UPDATE public.posts
  SET updated_at = pg_catalog.now()
  WHERE id = NEW.post_id
    AND deleted_at IS NULL;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.notify_poll_vote_change() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER poll_votes_notify_post_change
AFTER INSERT ON public.poll_votes
FOR EACH ROW
EXECUTE FUNCTION private.notify_poll_vote_change();

-- Post counter updates (likes, reposts, replies, views) do not affect trends.
-- Avoid rescanning every post unless a trend-relevant field actually changes.
CREATE OR REPLACE FUNCTION private.sync_trend_post_counts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF TG_TABLE_NAME = 'trends' THEN
    NEW.post_count := (
      SELECT pg_catalog.count(*)::bigint
      FROM public.posts AS p
      WHERE p.visibility = 'public'
        AND p.deleted_at IS NULL
        AND (p.scheduled_at IS NULL OR p.scheduled_at <= pg_catalog.now())
        AND pg_catalog.strpos(
          pg_catalog.lower(COALESCE(p.body, '')),
          pg_catalog.lower(NEW.keyword)
        ) > 0
    );
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF OLD.body IS NOT DISTINCT FROM NEW.body
      AND OLD.visibility IS NOT DISTINCT FROM NEW.visibility
      AND OLD.deleted_at IS NOT DISTINCT FROM NEW.deleted_at
      AND OLD.scheduled_at IS NOT DISTINCT FROM NEW.scheduled_at
    THEN
      RETURN NEW;
    END IF;
  END IF;

  WITH counts AS (
    SELECT
      t.id,
      pg_catalog.count(p.id)::bigint AS post_count
    FROM public.trends AS t
    LEFT JOIN public.posts AS p
      ON p.visibility = 'public'
     AND p.deleted_at IS NULL
     AND (p.scheduled_at IS NULL OR p.scheduled_at <= pg_catalog.now())
     AND pg_catalog.strpos(
       pg_catalog.lower(COALESCE(p.body, '')),
       pg_catalog.lower(t.keyword)
     ) > 0
    GROUP BY t.id
  )
  UPDATE public.trends AS t
  SET post_count = counts.post_count,
      updated_at = pg_catalog.now()
  FROM counts
  WHERE t.id = counts.id
    AND t.post_count IS DISTINCT FROM counts.post_count;

  RETURN NULL;
END;
$function$;
