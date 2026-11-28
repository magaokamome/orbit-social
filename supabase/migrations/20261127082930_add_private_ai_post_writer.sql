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
  if p_body is null or length(btrim(p_body)) = 0 or length(p_body) > 5000 then
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
      and (parent.scheduled_at is null or parent.scheduled_at <= now())
  ) then
    raise exception '返信先の公開ポストが存在しません';
  end if;

  insert into public.posts (author_id, body, reply_to, visibility)
  values (p_author_id, btrim(p_body), p_reply_to, 'public')
  returning id into v_post_id;

  return v_post_id;
end;
$function$;

revoke all on function private.ai_create_post(text, text, text) from public;
revoke all on function private.ai_create_post(text, text, text) from anon;
revoke all on function private.ai_create_post(text, text, text) from authenticated;
grant execute on function private.ai_create_post(text, text, text) to service_role;