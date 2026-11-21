create or replace function public.increment_post_view(target_post_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update public.posts
  set views_count = views_count + 1
  where id = target_post_id
    and deleted_at is null
    and (scheduled_at is null or scheduled_at <= now());
end;
$$;
revoke all on function public.increment_post_view(text) from public, anon;
grant execute on function public.increment_post_view(text) to authenticated;
