-- Keep the public RPC invoker-only; move privileged counter updates into the non-exposed private schema.
CREATE OR REPLACE FUNCTION private.increment_post_view_impl(target_post_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING errcode = '42501';
  END IF;

  UPDATE public.posts AS p
  SET views_count = p.views_count + 1
  WHERE p.id = target_post_id
    AND p.deleted_at IS NULL
    AND (p.scheduled_at IS NULL OR p.scheduled_at <= pg_catalog.now())
    AND (
      coalesce(p.visibility,'public') = 'public'
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
    );
END;
$function$;
REVOKE ALL ON FUNCTION private.increment_post_view_impl(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.increment_post_view_impl(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.increment_post_view(target_post_id text)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT private.increment_post_view_impl(target_post_id);
$function$;
REVOKE ALL ON FUNCTION public.increment_post_view(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_post_view(text) TO authenticated;
