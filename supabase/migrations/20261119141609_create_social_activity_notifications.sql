
create or replace function public.notify_post_like()
returns trigger language plpgsql security definer set search_path=public as $$
declare recipient text;
begin
  if auth.uid() is null or new.user_id <> auth.uid()::text then return new; end if;
  select author_id into recipient from public.posts where id=new.post_id and deleted_at is null;
  if recipient is not null and recipient <> new.user_id then
    insert into public.notifications(recipient_id,actor_id,type,post_id,body)
    values(recipient,new.user_id,'like',new.post_id,'さんがあなたのポストにいいねしました。');
  end if;
  return new;
end; $$;

create or replace function public.notify_repost()
returns trigger language plpgsql security definer set search_path=public as $$
declare recipient text;
begin
  if auth.uid() is null or new.user_id <> auth.uid()::text then return new; end if;
  select author_id into recipient from public.posts where id=new.post_id and deleted_at is null;
  if recipient is not null and recipient <> new.user_id then
    insert into public.notifications(recipient_id,actor_id,type,post_id,body)
    values(recipient,new.user_id,'repost',new.post_id,'さんがあなたのポストをリポストしました。');
  end if;
  return new;
end; $$;

create or replace function public.notify_follow()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or new.follower_id <> auth.uid()::text then return new; end if;
  if new.follower_id <> new.following_id then
    insert into public.notifications(recipient_id,actor_id,type,body)
    values(new.following_id,new.follower_id,'follow','さんにフォローされました。');
  end if;
  return new;
end; $$;

create or replace function public.notify_post_reply()
returns trigger language plpgsql security definer set search_path=public as $$
declare recipient text;
begin
  if auth.uid() is null or new.author_id <> auth.uid()::text or new.reply_to is null then return new; end if;
  select author_id into recipient from public.posts where id=new.reply_to and deleted_at is null;
  if recipient is not null and recipient <> new.author_id then
    insert into public.notifications(recipient_id,actor_id,type,post_id,body)
    values(recipient,new.author_id,'reply',new.id,'さんがあなたのポストに返信しました。');
  end if;
  return new;
end; $$;

create or replace function public.notify_new_message()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or new.sender_id <> auth.uid()::text then return new; end if;
  insert into public.notifications(recipient_id,actor_id,type,body)
  select cm.user_id,new.sender_id,'message','新しいメッセージが届きました。'
  from public.conversation_members cm
  where cm.conversation_id=new.conversation_id and cm.user_id <> new.sender_id;
  return new;
end; $$;

revoke all on function public.notify_post_like() from public, anon, authenticated;
revoke all on function public.notify_repost() from public, anon, authenticated;
revoke all on function public.notify_follow() from public, anon, authenticated;
revoke all on function public.notify_post_reply() from public, anon, authenticated;
revoke all on function public.notify_new_message() from public, anon, authenticated;

drop trigger if exists notify_post_like_trigger on public.post_likes;
create trigger notify_post_like_trigger after insert on public.post_likes for each row execute function public.notify_post_like();
drop trigger if exists notify_repost_trigger on public.reposts;
create trigger notify_repost_trigger after insert on public.reposts for each row execute function public.notify_repost();
drop trigger if exists notify_follow_trigger on public.follows;
create trigger notify_follow_trigger after insert on public.follows for each row execute function public.notify_follow();
drop trigger if exists notify_post_reply_trigger on public.posts;
create trigger notify_post_reply_trigger after insert on public.posts for each row execute function public.notify_post_reply();
drop trigger if exists notify_new_message_trigger on public.messages;
create trigger notify_new_message_trigger after insert on public.messages for each row execute function public.notify_new_message();
