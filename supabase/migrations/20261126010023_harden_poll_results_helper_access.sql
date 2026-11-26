-- Keep the public poll-results RPC as the only client entry point.
-- The wrapper executes with its owner so callers do not need access to the private schema.
CREATE OR REPLACE FUNCTION public.get_poll_results(p_post_ids text[])
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
  SELECT *
  FROM private.get_poll_results_impl(p_post_ids);
$function$;

REVOKE ALL ON FUNCTION public.get_poll_results(text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_poll_results(text[]) TO anon, authenticated;

-- Internal aggregation implementation is no longer directly executable by API roles.
REVOKE ALL ON FUNCTION private.get_poll_results_impl(text[]) FROM PUBLIC, anon, authenticated;
REVOKE USAGE ON SCHEMA private FROM anon;
