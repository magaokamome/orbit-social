-- Keep the exposed RPC SECURITY INVOKER.
-- The implementation remains in the non-exposed private schema and applies caller visibility rules.
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

GRANT USAGE ON SCHEMA private TO anon, authenticated;
GRANT EXECUTE ON FUNCTION private.get_poll_results_impl(text[]) TO anon, authenticated;
