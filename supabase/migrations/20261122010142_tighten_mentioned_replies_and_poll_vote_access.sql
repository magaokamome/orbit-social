-- Match mentioned-only replies to complete usernames, not prefixes.
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
      AND (parent.scheduled_at IS NULL OR parent.scheduled_at <= pg_catalog.now())
      AND (
        coalesce(parent.visibility, 'public') = 'public'
        OR parent.author_id = (SELECT auth.uid())::text
        OR (
          parent.visibility = 'followers'
          AND EXISTS (
            SELECT 1
            FROM public.follows f
            WHERE f.follower_id = (SELECT auth.uid())::text
              AND f.following_id = parent.author_id
          )
        )
      )
      AND (
        parent.author_id = (SELECT auth.uid())::text
        OR coalesce(parent.reply_permission, 'everyone') = 'everyone'
        OR (
          parent.reply_permission = 'following'
          AND EXISTS (
            SELECT 1
            FROM public.follows f
            WHERE f.follower_id = parent.author_id
              AND f.following_id = (SELECT auth.uid())::text
          )
        )
        OR (
          parent.reply_permission = 'mentioned'
          AND EXISTS (
            SELECT 1
            FROM public.profiles p
            CROSS JOIN LATERAL pg_catalog.regexp_matches(
              pg_catalog.lower(coalesce(parent.body, '')),
              '(^|[^a-z0-9_])@([a-z0-9_-]+)',
              'g'
            ) AS m(parts)
            WHERE p.id = (SELECT auth.uid())::text
              AND m.parts[2] = pg_catalog.lower(p.username)
          )
        )
      )
  );
$function$;

-- Poll results are visible only when the referenced poll itself is visible.
ALTER POLICY "Poll results are public"
ON public.poll_votes
USING (
  EXISTS (
    SELECT 1
    FROM public.posts p
    WHERE p.id = poll_votes.post_id
      AND p.poll_options IS NOT NULL
      AND pg_catalog.cardinality(p.poll_options) >= 2
  )
);

-- Only allow a vote on a visible poll and on an existing option.
ALTER POLICY "Users vote once"
ON public.poll_votes
WITH CHECK (
  user_id = (SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1
    FROM public.posts p
    WHERE p.id = poll_votes.post_id
      AND p.poll_options IS NOT NULL
      AND pg_catalog.cardinality(p.poll_options) >= 2
      AND poll_votes.option_index < pg_catalog.cardinality(p.poll_options)
  )
);