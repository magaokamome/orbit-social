-- Keep public trend counts synchronized with currently visible public posts.
-- The curated category, rank, and active state remain operator-managed.
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

REVOKE ALL ON FUNCTION private.sync_trend_post_counts() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trends_sync_post_count_before_write ON public.trends;
CREATE TRIGGER trends_sync_post_count_before_write
BEFORE INSERT OR UPDATE OF keyword ON public.trends
FOR EACH ROW
EXECUTE FUNCTION private.sync_trend_post_counts();

DROP TRIGGER IF EXISTS posts_sync_trend_counts_after_write ON public.posts;
CREATE TRIGGER posts_sync_trend_counts_after_write
AFTER INSERT OR UPDATE OF body, visibility, deleted_at, scheduled_at OR DELETE
ON public.posts
FOR EACH STATEMENT
EXECUTE FUNCTION private.sync_trend_post_counts();

-- Reconcile existing aggregate values without changing categories, ranks, or visibility flags.
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

COMMENT ON FUNCTION private.sync_trend_post_counts() IS
  'Maintains public trend post_count from published, non-deleted public posts; trigger-only execution.';
