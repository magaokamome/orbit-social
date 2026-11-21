-- Improve RLS query planning, foreign-key lookup performance, and column-level write access.
-- Keep the conversation membership helper outside the API-exposed public schema.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.is_conversation_member(target_conversation_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.conversation_members cm
    WHERE cm.conversation_id = target_conversation_id
      AND cm.user_id = (SELECT auth.uid())::text
  );
$function$;
GRANT EXECUTE ON FUNCTION private.is_conversation_member(text) TO authenticated;

ALTER POLICY "Members view conversation membership"
  ON public.conversation_members
  USING (private.is_conversation_member(conversation_id));
ALTER POLICY "Conversation members view conversations"
  ON public.conversations
  USING (private.is_conversation_member(id));
ALTER POLICY "Conversation creators add initial members"
  ON public.conversation_members
  WITH CHECK (
    user_id = (SELECT auth.uid())::text
    OR EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.id = conversation_members.conversation_id
        AND c.created_by = (SELECT auth.uid())::text
    )
    OR private.is_conversation_member(conversation_id)
  );
ALTER POLICY "Members send messages"
  ON public.messages
  WITH CHECK (
    sender_id = (SELECT auth.uid())::text
    AND private.is_conversation_member(conversation_id)
  );
ALTER POLICY "Members view messages"
  ON public.messages
  USING (private.is_conversation_member(conversation_id));
ALTER POLICY "Members update read status"
  ON public.messages
  USING (private.is_conversation_member(conversation_id))
  WITH CHECK (private.is_conversation_member(conversation_id));

REVOKE ALL ON FUNCTION public.is_conversation_member(text) FROM PUBLIC, anon, authenticated;
DROP FUNCTION public.is_conversation_member(text);

-- Evaluate auth.uid() once per statement instead of once per scanned row.
DO $$
DECLARE
  p record;
  using_clause text;
  check_clause text;
BEGIN
  FOR p IN
    SELECT schemaname, tablename, policyname, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (
        (coalesce(qual, '') ILIKE '%auth.uid()%' AND coalesce(qual, '') NOT ILIKE '%SELECT auth.uid()%')
        OR
        (coalesce(with_check, '') ILIKE '%auth.uid()%' AND coalesce(with_check, '') NOT ILIKE '%SELECT auth.uid()%')
      )
  LOOP
    using_clause := CASE
      WHEN p.qual IS NULL THEN ''
      ELSE format(' USING (%s)', replace(p.qual, 'auth.uid()', '(select auth.uid())'))
    END;
    check_clause := CASE
      WHEN p.with_check IS NULL THEN ''
      ELSE format(' WITH CHECK (%s)', replace(p.with_check, 'auth.uid()', '(select auth.uid())'))
    END;
    EXECUTE format(
      'ALTER POLICY %I ON %I.%I%s%s',
      p.policyname, p.schemaname, p.tablename, using_clause, check_clause
    );
  END LOOP;
END
$$;

-- Separate list read policies from write policies to avoid redundant permissive SELECT checks.
DROP POLICY "Users manage their lists" ON public.lists;
CREATE POLICY "Users create their lists"
  ON public.lists FOR INSERT TO authenticated
  WITH CHECK (owner_id = (SELECT auth.uid())::text);
CREATE POLICY "Users update their lists"
  ON public.lists FOR UPDATE TO authenticated
  USING (owner_id = (SELECT auth.uid())::text)
  WITH CHECK (owner_id = (SELECT auth.uid())::text);
CREATE POLICY "Users delete their lists"
  ON public.lists FOR DELETE TO authenticated
  USING (owner_id = (SELECT auth.uid())::text);

DROP POLICY "List owners manage members" ON public.list_members;
CREATE POLICY "List owners add members"
  ON public.list_members FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.lists l
      WHERE l.id = list_members.list_id
        AND l.owner_id = (SELECT auth.uid())::text
    )
  );
CREATE POLICY "List owners remove members"
  ON public.list_members FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.lists l
      WHERE l.id = list_members.list_id
        AND l.owner_id = (SELECT auth.uid())::text
    )
  );

-- Cover foreign keys that were missing supporting indexes.
CREATE INDEX IF NOT EXISTS bookmarks_post_id_idx ON public.bookmarks (post_id);
CREATE INDEX IF NOT EXISTS conversation_members_user_id_idx ON public.conversation_members (user_id);
CREATE INDEX IF NOT EXISTS conversations_created_by_idx ON public.conversations (created_by);
CREATE INDEX IF NOT EXISTS lists_owner_id_idx ON public.lists (owner_id);
CREATE INDEX IF NOT EXISTS messages_sender_id_idx ON public.messages (sender_id);
CREATE INDEX IF NOT EXISTS muted_users_muted_user_id_idx ON public.muted_users (muted_user_id);
CREATE INDEX IF NOT EXISTS notifications_actor_id_idx ON public.notifications (actor_id);
CREATE INDEX IF NOT EXISTS notifications_post_id_idx ON public.notifications (post_id);
CREATE INDEX IF NOT EXISTS poll_votes_user_id_idx ON public.poll_votes (user_id);
CREATE INDEX IF NOT EXISTS reports_post_id_idx ON public.reports (post_id);
CREATE INDEX IF NOT EXISTS reports_reported_user_id_idx ON public.reports (reported_user_id);
CREATE INDEX IF NOT EXISTS reports_reporter_id_idx ON public.reports (reporter_id);

-- Prevent users from changing counters, verification flags, message contents, or notification metadata.
REVOKE UPDATE ON TABLE public.profiles FROM authenticated;
GRANT UPDATE (username, display_name, bio, location, website)
  ON TABLE public.profiles TO authenticated;

REVOKE UPDATE ON TABLE public.posts FROM authenticated;
GRANT UPDATE (body, updated_at) ON TABLE public.posts TO authenticated;

REVOKE UPDATE ON TABLE public.messages FROM authenticated;
GRANT UPDATE (read_at) ON TABLE public.messages TO authenticated;

REVOKE UPDATE ON TABLE public.notifications FROM authenticated;
GRANT UPDATE (read_at) ON TABLE public.notifications TO authenticated;

-- The view counter remains an authenticated RPC, but it must not count private posts for non-followers.
CREATE OR REPLACE FUNCTION public.increment_post_view(target_post_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING errcode = '42501';
  END IF;

  UPDATE public.posts AS p
  SET views_count = p.views_count + 1
  WHERE p.id = target_post_id
    AND p.deleted_at IS NULL
    AND (p.scheduled_at IS NULL OR p.scheduled_at <= now())
    AND (
      p.visibility = 'public'
      OR p.author_id = auth.uid()::text
      OR (
        p.visibility = 'followers'
        AND EXISTS (
          SELECT 1
          FROM public.follows f
          WHERE f.follower_id = auth.uid()::text
            AND f.following_id = p.author_id
        )
      )
    );
END;
$function$;
REVOKE ALL ON FUNCTION public.increment_post_view(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_post_view(text) TO authenticated;
