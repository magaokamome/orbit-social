
grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.posts, public.follows, public.post_likes, public.reposts, public.poll_votes to anon, authenticated;
grant select on public.lists, public.list_members to anon, authenticated;
grant update on public.profiles to authenticated;
grant insert, update, delete on public.posts to authenticated;
grant insert, delete on public.follows, public.post_likes, public.reposts to authenticated;
grant select, insert, delete on public.bookmarks to authenticated;
grant select, update on public.notifications to authenticated;
grant select, insert on public.conversations, public.conversation_members, public.messages to authenticated;
grant update on public.messages to authenticated;
grant select, insert, update, delete on public.lists, public.list_members to authenticated;
grant select, insert, delete on public.muted_users to authenticated;
grant select, insert on public.reports to authenticated;
grant execute on function public.is_conversation_member(text) to authenticated;
grant execute on function public.increment_post_view(text) to authenticated;
