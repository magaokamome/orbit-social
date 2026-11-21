
revoke all on function public.handle_follow_counts() from public, anon, authenticated;
revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
revoke all on function public.handle_post_like_counts() from public, anon, authenticated;
revoke all on function public.handle_reply_counts() from public, anon, authenticated;
revoke all on function public.handle_repost_counts() from public, anon, authenticated;
revoke all on function public.is_conversation_member(text) from public, anon;
grant execute on function public.is_conversation_member(text) to authenticated;
