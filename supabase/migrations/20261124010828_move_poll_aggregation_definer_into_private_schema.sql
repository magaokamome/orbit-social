-- Keep the elevated poll aggregation implementation outside the exposed API schema.
CREATE OR REPLACE FUNCTION private.get_poll_results_impl(p_post_ids text[])
RETURNS TABLE (
  post_id text,
  option_index integer,
  vote_count bigint,
  viewer_option_index integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    p.id AS post_id,
    option.option_index,
    pg_catalog.count(v.user_id)::bigint AS vote_count,
    pg_catalog.max(v.option_index) FILTER (
      WHERE v.user_id = (SELECT auth.uid())::text
    ) AS viewer_option_index
  FROM public.posts p
  CROSS JOIN LATERAL pg_catalog.generate_series(
    0,
    pg_catalog.cardinality(p.poll_options) - 1
  ) AS option(option_index)
  LEFT JOIN public.poll_votes v ON v.post_id = p.id
  WHERE p.id = ANY (p_post_ids)
    AND COALESCE(pg_catalog.cardinality(p_post_ids), 0) BETWEEN 1 AND 500
    AND p.poll_options IS NOT NULL
    AND pg_catalog.cardinality(p.poll_options) >= 2
    AND p.deleted_at IS NULL
    AND (p.scheduled_at IS NULL OR p.scheduled_at <= pg_catalog.now())
    AND (
      p.visibility = 'public'
      OR p.author_id = (SELECT auth.uid())::text
      OR (
        p.visibility = 'followers'
        AND EXISTS (
          SELECT 1
          FROM public.follows f
          WHERE f.follower_id = (SELECT auth.uid())::text
            AND f.following_id = p.author_id
        )
      )
    )
  GROUP BY p.id, option.option_index
  ORDER BY p.id, option.option_index;
$function$;

REVOKE ALL ON FUNCTION private.get_poll_results_impl(text[]) FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO anon, authenticated;
GRANT EXECUTE ON FUNCTION private.get_poll_results_impl(text[]) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_poll_results(p_post_ids text[])
RETURNS TABLE (
  post_id text,
  option_index integer,
  vote_count bigint,
  viewer_option_index integer
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT *
  FROM private.get_poll_results_impl(p_post_ids);
$function$;

REVOKE ALL ON FUNCTION public.get_poll_results(text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_poll_results(text[]) TO anon, authenticated;
