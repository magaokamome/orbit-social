-- Keep the internal AI writer aligned with the same reply rules used by authenticated users.
-- The service_role is the only caller; no browser role receives EXECUTE.
create or replace function private.ai_create_post(
  p_author_id text,
  p_body text,
  p_reply_to text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_post_id text;
begin
  if p_body is null
    or pg_catalog.length(pg_catalog.btrim(p_body)) = 0
    or pg_catalog.length(p_body) > 5000
  then
    raise exception '投稿本文が空、または文字数制限を超えています';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_author_id
      and p.is_ai_generated = true
  ) then
    raise exception '投稿者はAI生成プロフィールに限られます';
  end if;

  if p_reply_to is not null and not exists (
    select 1
    from public.posts parent
    where parent.id = p_reply_to
      and parent.deleted_at is null
      and parent.visibility = 'public'
      and (parent.scheduled_at is null or parent.scheduled_at <= pg_catalog.now())
      and (
        parent.author_id = p_author_id
        or pg_catalog.coalesce(parent.reply_permission, 'everyone') = 'everyone'
        or (
          parent.reply_permission = 'following'
          and exists (
            select 1
            from public.follows f
            where f.follower_id = parent.author_id
              and f.following_id = p_author_id
          )
        )
        or (
          parent.reply_permission = 'mentioned'
          and exists (
            select 1
            from public.profiles ai_profile
            cross join lateral pg_catalog.regexp_matches(
              pg_catalog.lower(pg_catalog.coalesce(parent.body, '')),
              '(^|[^a-z0-9_])@([a-z0-9_-]+)',
              'g'
            ) as mention(parts)
            where ai_profile.id = p_author_id
              and mention.parts[2] = pg_catalog.lower(ai_profile.username)
          )
        )
      )
  ) then
    raise exception '返信先の公開ポストが存在しないか、返信が許可されていません';
  end if;

  insert into public.posts (author_id, body, reply_to, visibility)
  values (p_author_id, pg_catalog.btrim(p_body), p_reply_to, 'public')
  returning id into v_post_id;

  return v_post_id;
end;
$function$;

revoke all on function private.ai_create_post(text, text, text) from public;
revoke all on function private.ai_create_post(text, text, text) from anon;
revoke all on function private.ai_create_post(text, text, text) from authenticated;
grant usage on schema private to service_role;
grant execute on function private.ai_create_post(text, text, text) to service_role;
