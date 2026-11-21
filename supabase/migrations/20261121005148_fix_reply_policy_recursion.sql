-- Avoid recursive RLS evaluation by checking reply eligibility in a private SECURITY DEFINER helper.
CREATE OR REPLACE FUNCTION private.can_reply_to_post(target_post_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.posts parent
    WHERE parent.id = target_post_id
      AND parent.deleted_at IS NULL
      AND (parent.scheduled_at IS NULL OR parent.scheduled_at <= now())
      AND (
        coalesce(parent.visibility,'public') = 'public'
        OR parent.author_id = (SELECT auth.uid())::text
        OR (
          parent.visibility = 'followers'
          AND EXISTS (
            SELECT 1 FROM public.follows f
            WHERE f.follower_id = (SELECT auth.uid())::text
              AND f.following_id = parent.author_id
          )
        )
      )
      AND (
        parent.author_id = (SELECT auth.uid())::text
        OR coalesce(parent.reply_permission,'everyone') = 'everyone'
        OR (
          parent.reply_permission = 'following'
          AND EXISTS (
            SELECT 1 FROM public.follows f
            WHERE f.follower_id = parent.author_id
              AND f.following_id = (SELECT auth.uid())::text
          )
        )
        OR (
          parent.reply_permission = 'mentioned'
          AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = (SELECT auth.uid())::text
              AND strpos(lower(coalesce(parent.body,'')), '@' || lower(p.username)) > 0
          )
        )
      )
  );
$function$;
REVOKE ALL ON FUNCTION private.can_reply_to_post(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.can_reply_to_post(text) TO authenticated;

ALTER POLICY "Authenticated users create posts"
ON public.posts
WITH CHECK (
  author_id = (SELECT auth.uid())::text
  AND (reply_to IS NULL OR private.can_reply_to_post(reply_to))
);
