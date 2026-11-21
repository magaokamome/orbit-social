-- Enforce each post's reply permission at the database boundary.
-- A reply must target a visible, non-deleted post and satisfy its author's reply rule.
ALTER POLICY "Authenticated users create posts"
ON public.posts
WITH CHECK (
  author_id = (SELECT auth.uid())::text
  AND (
    reply_to IS NULL
    OR EXISTS (
      SELECT 1
      FROM public.posts parent
      WHERE parent.id = posts.reply_to
        AND (
          parent.author_id = (SELECT auth.uid())::text
          OR parent.reply_permission = 'everyone'
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
              WHERE p.id = (SELECT auth.uid())::text
                AND strpos(lower(coalesce(parent.body,'')), '@' || lower(p.username)) > 0
            )
          )
        )
    )
  )
);
