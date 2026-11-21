-- Limit authenticated INSERT/UPDATE privileges to the exact columns used by the client.
-- Counters, timestamps, IDs, report status, and other server-managed fields keep their defaults.
REVOKE INSERT ON TABLE public.posts FROM authenticated;
GRANT INSERT (author_id, body, reply_to, media_urls, gif_label, poll_options, poll_duration, warning, location, reply_permission, scheduled_at)
  ON TABLE public.posts TO authenticated;

REVOKE INSERT ON TABLE public.follows FROM authenticated;
GRANT INSERT (follower_id, following_id) ON TABLE public.follows TO authenticated;

REVOKE INSERT ON TABLE public.post_likes FROM authenticated;
GRANT INSERT (user_id, post_id) ON TABLE public.post_likes TO authenticated;

REVOKE INSERT ON TABLE public.reposts FROM authenticated;
GRANT INSERT (user_id, post_id) ON TABLE public.reposts TO authenticated;

REVOKE INSERT ON TABLE public.bookmarks FROM authenticated;
GRANT INSERT (user_id, post_id) ON TABLE public.bookmarks TO authenticated;

REVOKE INSERT ON TABLE public.conversations FROM authenticated;
GRANT INSERT (created_by) ON TABLE public.conversations TO authenticated;

REVOKE INSERT ON TABLE public.conversation_members FROM authenticated;
GRANT INSERT (conversation_id, user_id) ON TABLE public.conversation_members TO authenticated;

REVOKE INSERT ON TABLE public.messages FROM authenticated;
GRANT INSERT (conversation_id, sender_id, body) ON TABLE public.messages TO authenticated;

REVOKE INSERT ON TABLE public.lists FROM authenticated;
GRANT INSERT (owner_id, name, description, is_public) ON TABLE public.lists TO authenticated;

REVOKE UPDATE ON TABLE public.lists FROM authenticated;
GRANT UPDATE (name, description, updated_at) ON TABLE public.lists TO authenticated;

REVOKE INSERT ON TABLE public.list_members FROM authenticated;
GRANT INSERT (list_id, user_id) ON TABLE public.list_members TO authenticated;

REVOKE INSERT ON TABLE public.muted_users FROM authenticated;
GRANT INSERT (user_id, muted_user_id) ON TABLE public.muted_users TO authenticated;

REVOKE INSERT ON TABLE public.reports FROM authenticated;
GRANT INSERT (reporter_id, post_id, reported_user_id, reason, details)
  ON TABLE public.reports TO authenticated;
