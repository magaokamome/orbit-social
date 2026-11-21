-- Harden SECURITY DEFINER routines and close the DM self-join authorization gap.
-- Keep the authenticated view-counter RPC intentionally executable; it validates auth.uid()
-- and visibility in its implementation, while all object references remain schema-qualified.
ALTER FUNCTION public.handle_follow_counts() SET search_path = '';
ALTER FUNCTION public.handle_new_auth_user() SET search_path = '';
ALTER FUNCTION public.handle_post_like_counts() SET search_path = '';
ALTER FUNCTION public.handle_reply_counts() SET search_path = '';
ALTER FUNCTION public.handle_repost_counts() SET search_path = '';
ALTER FUNCTION public.increment_post_view(text) SET search_path = '';
ALTER FUNCTION public.notify_follow() SET search_path = '';
ALTER FUNCTION public.notify_new_message() SET search_path = '';
ALTER FUNCTION public.notify_post_like() SET search_path = '';
ALTER FUNCTION public.notify_post_reply() SET search_path = '';
ALTER FUNCTION public.notify_repost() SET search_path = '';

-- Remove the default PUBLIC EXECUTE grant from the private membership helper.
REVOKE ALL ON FUNCTION private.is_conversation_member(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_conversation_member(text) TO authenticated;

-- Only the conversation creator may add initial members. The former user_id = auth.uid()
-- branch allowed any authenticated user who knew a conversation ID to join a private DM.
CREATE OR REPLACE FUNCTION private.is_conversation_creator(target_conversation_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.conversations c
    WHERE c.id = target_conversation_id
      AND c.created_by = (SELECT auth.uid())::text
  );
$function$;
REVOKE ALL ON FUNCTION private.is_conversation_creator(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_conversation_creator(text) TO authenticated;

ALTER POLICY "Conversation creators add initial members"
  ON public.conversation_members
  WITH CHECK (private.is_conversation_creator(conversation_id));

-- The application already has an INSERT RLS policy for one-vote-per-user,
-- but authenticated lacked the corresponding column-level INSERT grant.
GRANT INSERT (post_id, user_id, option_index)
  ON TABLE public.poll_votes TO authenticated;
