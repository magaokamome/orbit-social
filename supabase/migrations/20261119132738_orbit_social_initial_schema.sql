
create table if not exists public.profiles (
  id text primary key,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  username text not null unique,
  display_name text not null,
  bio text not null default '',
  avatar_url text,
  cover_url text,
  location text,
  website text,
  is_verified boolean not null default false,
  followers_count integer not null default 0,
  following_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.posts (
  id text primary key default gen_random_uuid()::text,
  author_id text not null references public.profiles(id) on delete cascade,
  body text not null default '',
  reply_to text references public.posts(id) on delete cascade,
  media_urls text[] not null default '{}',
  gif_label text,
  poll_options text[],
  poll_duration text,
  warning text,
  location text,
  reply_permission text not null default 'everyone'
    check (reply_permission in ('everyone','following','mentioned')),
  visibility text not null default 'public'
    check (visibility in ('public','followers','private')),
  scheduled_at timestamptz,
  likes_count integer not null default 0,
  reposts_count integer not null default 0,
  replies_count integer not null default 0,
  views_count integer not null default 0,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.follows (
  follower_id text not null references public.profiles(id) on delete cascade,
  following_id text not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

create table if not exists public.post_likes (
  user_id text not null references public.profiles(id) on delete cascade,
  post_id text not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

create table if not exists public.reposts (
  user_id text not null references public.profiles(id) on delete cascade,
  post_id text not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

create table if not exists public.bookmarks (
  user_id text not null references public.profiles(id) on delete cascade,
  post_id text not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

create table if not exists public.notifications (
  id text primary key default gen_random_uuid()::text,
  recipient_id text not null references public.profiles(id) on delete cascade,
  actor_id text references public.profiles(id) on delete set null,
  type text not null,
  post_id text references public.posts(id) on delete cascade,
  body text not null default '',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id text primary key default gen_random_uuid()::text,
  created_by text not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id text not null references public.conversations(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table if not exists public.messages (
  id text primary key default gen_random_uuid()::text,
  conversation_id text not null references public.conversations(id) on delete cascade,
  sender_id text not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create table if not exists public.lists (
  id text primary key default gen_random_uuid()::text,
  owner_id text not null references public.profiles(id) on delete cascade,
  name text not null,
  description text not null default '',
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.list_members (
  list_id text not null references public.lists(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (list_id, user_id)
);

create table if not exists public.muted_users (
  user_id text not null references public.profiles(id) on delete cascade,
  muted_user_id text not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, muted_user_id),
  check (user_id <> muted_user_id)
);

create table if not exists public.reports (
  id text primary key default gen_random_uuid()::text,
  reporter_id text not null references public.profiles(id) on delete cascade,
  post_id text references public.posts(id) on delete cascade,
  reported_user_id text references public.profiles(id) on delete cascade,
  reason text not null,
  details text not null default '',
  status text not null default 'open' check (status in ('open','reviewing','closed')),
  created_at timestamptz not null default now()
);

create table if not exists public.poll_votes (
  post_id text not null references public.posts(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  option_index integer not null check (option_index >= 0),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists posts_created_at_idx on public.posts(created_at desc);
create index if not exists posts_reply_to_idx on public.posts(reply_to, created_at);
create index if not exists posts_author_created_idx on public.posts(author_id, created_at desc);
create index if not exists follows_following_idx on public.follows(following_id);
create index if not exists likes_post_idx on public.post_likes(post_id);
create index if not exists reposts_post_idx on public.reposts(post_id);
create index if not exists notifications_recipient_created_idx on public.notifications(recipient_id, created_at desc);
create index if not exists messages_conversation_created_idx on public.messages(conversation_id, created_at);
create index if not exists list_members_user_idx on public.list_members(user_id);

create or replace function public.is_conversation_member(target_conversation_id text)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = target_conversation_id
      and cm.user_id = auth.uid()::text
  );
$$;

create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  base_username text;
  candidate text;
begin
  base_username := lower(regexp_replace(
    coalesce(new.raw_user_meta_data->>'username', split_part(coalesce(new.email, 'user'), '@', 1)),
    '[^a-z0-9_]+', '_', 'g'
  ));
  base_username := trim(both '_' from base_username);
  if base_username = '' then base_username := 'user'; end if;
  candidate := left(base_username, 20) || '_' || substr(replace(new.id::text, '-', ''), 1, 6);

  insert into public.profiles (id, auth_user_id, username, display_name)
  values (
    new.id::text,
    new.id,
    candidate,
    coalesce(nullif(new.raw_user_meta_data->>'display_name',''), candidate)
  )
  on conflict (auth_user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_orbit on auth.users;
create trigger on_auth_user_created_orbit
after insert on auth.users
for each row execute procedure public.handle_new_auth_user();

create or replace function public.handle_follow_counts()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set following_count = following_count + 1 where id = new.follower_id;
    update public.profiles set followers_count = followers_count + 1 where id = new.following_id;
    if new.follower_id <> new.following_id then
      insert into public.notifications(recipient_id, actor_id, type, body)
      values(new.following_id, new.follower_id, 'follow', 'さんにフォローされました。');
    end if;
    return new;
  else
    update public.profiles set following_count = greatest(0, following_count - 1) where id = old.follower_id;
    update public.profiles set followers_count = greatest(0, followers_count - 1) where id = old.following_id;
    return old;
  end if;
end;
$$;
drop trigger if exists follows_count_trigger on public.follows;
create trigger follows_count_trigger after insert or delete on public.follows
for each row execute procedure public.handle_follow_counts();

create or replace function public.handle_post_like_counts()
returns trigger language plpgsql security definer set search_path = public
as $$
declare target_author text;
begin
  if tg_op = 'INSERT' then
    update public.posts set likes_count = likes_count + 1 where id = new.post_id returning author_id into target_author;
    if target_author is not null and target_author <> new.user_id then
      insert into public.notifications(recipient_id, actor_id, type, post_id, body)
      values(target_author, new.user_id, 'like', new.post_id, 'さんがあなたのポストにいいねしました。');
    end if;
    return new;
  else
    update public.posts set likes_count = greatest(0, likes_count - 1) where id = old.post_id;
    return old;
  end if;
end;
$$;
drop trigger if exists post_likes_count_trigger on public.post_likes;
create trigger post_likes_count_trigger after insert or delete on public.post_likes
for each row execute procedure public.handle_post_like_counts();

create or replace function public.handle_repost_counts()
returns trigger language plpgsql security definer set search_path = public
as $$
declare target_author text;
begin
  if tg_op = 'INSERT' then
    update public.posts set reposts_count = reposts_count + 1 where id = new.post_id returning author_id into target_author;
    if target_author is not null and target_author <> new.user_id then
      insert into public.notifications(recipient_id, actor_id, type, post_id, body)
      values(target_author, new.user_id, 'repost', new.post_id, 'さんがあなたのポストをリポストしました。');
    end if;
    return new;
  else
    update public.posts set reposts_count = greatest(0, reposts_count - 1) where id = old.post_id;
    return old;
  end if;
end;
$$;
drop trigger if exists reposts_count_trigger on public.reposts;
create trigger reposts_count_trigger after insert or delete on public.reposts
for each row execute procedure public.handle_repost_counts();

create or replace function public.handle_reply_counts()
returns trigger language plpgsql security definer set search_path = public
as $$
declare target_author text;
begin
  if tg_op = 'INSERT' and new.reply_to is not null then
    update public.posts set replies_count = replies_count + 1 where id = new.reply_to returning author_id into target_author;
    if target_author is not null and target_author <> new.author_id then
      insert into public.notifications(recipient_id, actor_id, type, post_id, body)
      values(target_author, new.author_id, 'reply', new.id, 'さんがあなたのポストに返信しました。');
    end if;
    return new;
  elsif tg_op = 'DELETE' and old.reply_to is not null then
    update public.posts set replies_count = greatest(0, replies_count - 1) where id = old.reply_to;
    return old;
  end if;
  return coalesce(new,old);
end;
$$;
drop trigger if exists post_reply_count_trigger on public.posts;
create trigger post_reply_count_trigger after insert or delete on public.posts
for each row execute procedure public.handle_reply_counts();

create or replace function public.increment_post_view(target_post_id text)
returns void language sql security definer set search_path = public
as $$
  update public.posts set views_count = views_count + 1
  where id = target_post_id and deleted_at is null;
$$;

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.follows enable row level security;
alter table public.post_likes enable row level security;
alter table public.reposts enable row level security;
alter table public.bookmarks enable row level security;
alter table public.notifications enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.lists enable row level security;
alter table public.list_members enable row level security;
alter table public.muted_users enable row level security;
alter table public.reports enable row level security;
alter table public.poll_votes enable row level security;

drop policy if exists "Public profiles are viewable" on public.profiles;
create policy "Public profiles are viewable" on public.profiles for select using (true);
drop policy if exists "Users create their own profile" on public.profiles;
create policy "Users create their own profile" on public.profiles for insert to authenticated
with check (auth_user_id = auth.uid() and id = auth.uid()::text);
drop policy if exists "Users update their own profile" on public.profiles;
create policy "Users update their own profile" on public.profiles for update to authenticated
using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());

drop policy if exists "Public posts are readable" on public.posts;
create policy "Public posts are readable" on public.posts for select using (
  deleted_at is null and (scheduled_at is null or scheduled_at <= now()) and (
    visibility = 'public'
    or author_id = auth.uid()::text
    or (visibility = 'followers' and exists (
      select 1 from public.follows f
      where f.follower_id = auth.uid()::text and f.following_id = author_id
    ))
  )
);
drop policy if exists "Authenticated users create posts" on public.posts;
create policy "Authenticated users create posts" on public.posts for insert to authenticated
with check (author_id = auth.uid()::text);
drop policy if exists "Authors update their posts" on public.posts;
create policy "Authors update their posts" on public.posts for update to authenticated
using (author_id = auth.uid()::text) with check (author_id = auth.uid()::text);
drop policy if exists "Authors delete their posts" on public.posts;
create policy "Authors delete their posts" on public.posts for delete to authenticated
using (author_id = auth.uid()::text);

drop policy if exists "Follows are public" on public.follows;
create policy "Follows are public" on public.follows for select using (true);
drop policy if exists "Users follow as themselves" on public.follows;
create policy "Users follow as themselves" on public.follows for insert to authenticated
with check (follower_id = auth.uid()::text and follower_id <> following_id);
drop policy if exists "Users unfollow as themselves" on public.follows;
create policy "Users unfollow as themselves" on public.follows for delete to authenticated
using (follower_id = auth.uid()::text);

drop policy if exists "Post likes are public" on public.post_likes;
create policy "Post likes are public" on public.post_likes for select using (true);
drop policy if exists "Users like as themselves" on public.post_likes;
create policy "Users like as themselves" on public.post_likes for insert to authenticated
with check (user_id = auth.uid()::text);
drop policy if exists "Users remove their likes" on public.post_likes;
create policy "Users remove their likes" on public.post_likes for delete to authenticated
using (user_id = auth.uid()::text);

drop policy if exists "Reposts are public" on public.reposts;
create policy "Reposts are public" on public.reposts for select using (true);
drop policy if exists "Users repost as themselves" on public.reposts;
create policy "Users repost as themselves" on public.reposts for insert to authenticated
with check (user_id = auth.uid()::text);
drop policy if exists "Users remove their reposts" on public.reposts;
create policy "Users remove their reposts" on public.reposts for delete to authenticated
using (user_id = auth.uid()::text);

drop policy if exists "Users view their bookmarks" on public.bookmarks;
create policy "Users view their bookmarks" on public.bookmarks for select to authenticated using (user_id = auth.uid()::text);
drop policy if exists "Users create their bookmarks" on public.bookmarks;
create policy "Users create their bookmarks" on public.bookmarks for insert to authenticated with check (user_id = auth.uid()::text);
drop policy if exists "Users delete their bookmarks" on public.bookmarks;
create policy "Users delete their bookmarks" on public.bookmarks for delete to authenticated using (user_id = auth.uid()::text);

drop policy if exists "Users view their notifications" on public.notifications;
create policy "Users view their notifications" on public.notifications for select to authenticated using (recipient_id = auth.uid()::text);
drop policy if exists "Users mark their notifications read" on public.notifications;
create policy "Users mark their notifications read" on public.notifications for update to authenticated using (recipient_id = auth.uid()::text) with check (recipient_id = auth.uid()::text);

drop policy if exists "Conversation members view conversations" on public.conversations;
create policy "Conversation members view conversations" on public.conversations for select to authenticated using (public.is_conversation_member(id));
drop policy if exists "Users create conversations" on public.conversations;
create policy "Users create conversations" on public.conversations for insert to authenticated with check (created_by = auth.uid()::text);

drop policy if exists "Members view conversation membership" on public.conversation_members;
create policy "Members view conversation membership" on public.conversation_members for select to authenticated using (public.is_conversation_member(conversation_id));
drop policy if exists "Users add themselves or existing members add others" on public.conversation_members;
create policy "Users add themselves or existing members add others" on public.conversation_members for insert to authenticated
with check (user_id = auth.uid()::text or public.is_conversation_member(conversation_id));

drop policy if exists "Members view messages" on public.messages;
create policy "Members view messages" on public.messages for select to authenticated using (public.is_conversation_member(conversation_id));
drop policy if exists "Members send messages" on public.messages;
create policy "Members send messages" on public.messages for insert to authenticated
with check (sender_id = auth.uid()::text and public.is_conversation_member(conversation_id));
drop policy if exists "Members update read status" on public.messages;
create policy "Members update read status" on public.messages for update to authenticated
using (public.is_conversation_member(conversation_id)) with check (public.is_conversation_member(conversation_id));

drop policy if exists "Public lists and owners view lists" on public.lists;
create policy "Public lists and owners view lists" on public.lists for select using (is_public or owner_id = auth.uid()::text);
drop policy if exists "Users manage their lists" on public.lists;
create policy "Users manage their lists" on public.lists for all to authenticated
using (owner_id = auth.uid()::text) with check (owner_id = auth.uid()::text);

drop policy if exists "List members view members" on public.list_members;
create policy "List members view members" on public.list_members for select using (
  exists (select 1 from public.lists l where l.id = list_id and (l.is_public or l.owner_id = auth.uid()::text))
);
drop policy if exists "List owners manage members" on public.list_members;
create policy "List owners manage members" on public.list_members for all to authenticated
using (exists (select 1 from public.lists l where l.id = list_id and l.owner_id = auth.uid()::text))
with check (exists (select 1 from public.lists l where l.id = list_id and l.owner_id = auth.uid()::text));

drop policy if exists "Users view their mutes" on public.muted_users;
create policy "Users view their mutes" on public.muted_users for select to authenticated using (user_id = auth.uid()::text);
drop policy if exists "Users manage their mutes" on public.muted_users;
create policy "Users manage their mutes" on public.muted_users for all to authenticated
using (user_id = auth.uid()::text) with check (user_id = auth.uid()::text);

drop policy if exists "Users create reports" on public.reports;
create policy "Users create reports" on public.reports for insert to authenticated with check (reporter_id = auth.uid()::text);
drop policy if exists "Users view their reports" on public.reports;
create policy "Users view their reports" on public.reports for select to authenticated using (reporter_id = auth.uid()::text);

drop policy if exists "Poll results are public" on public.poll_votes;
create policy "Poll results are public" on public.poll_votes for select using (true);
drop policy if exists "Users vote once" on public.poll_votes;
create policy "Users vote once" on public.poll_votes for insert to authenticated with check (user_id = auth.uid()::text);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('orbit-media','orbit-media',true,5242880,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do nothing;

drop policy if exists "Public read Orbit media" on storage.objects;
create policy "Public read Orbit media" on storage.objects for select using (bucket_id = 'orbit-media');
drop policy if exists "Users upload own Orbit media" on storage.objects;
create policy "Users upload own Orbit media" on storage.objects for insert to authenticated
with check (bucket_id = 'orbit-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Users update own Orbit media" on storage.objects;
create policy "Users update own Orbit media" on storage.objects for update to authenticated
using (bucket_id = 'orbit-media' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'orbit-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Users delete own Orbit media" on storage.objects;
create policy "Users delete own Orbit media" on storage.objects for delete to authenticated
using (bucket_id = 'orbit-media' and (storage.foldername(name))[1] = auth.uid()::text);

-- Demo profiles and sample posts are database seed rows, not runtime local files.
insert into public.profiles (id, username, display_name, bio, location, website, is_verified, followers_count, following_count, created_at)
values
 ('demo-me','neko','ねこ','日々のこと、Web制作、AIのことなど。気軽に話しかけてください。','埼玉県','neko.example',false,1280,356,now()),
 ('demo-sora','sora_design','そら｜デザインと暮らし','デザインと暮らしの記録。UI/UX・写真・喫茶店。','東京','sora.design',true,8240,512,now()),
 ('demo-tech','tech_mado','Techの窓','テクノロジーとAIのニュースをわかりやすく。','日本','techmado.jp',true,23400,203,now()),
 ('demo-mika','mikan_days','みかん','ごはんと散歩と猫が好き。','神奈川','',false,964,743,now()),
 ('demo-haru','haru_note','はるか','写真を撮ったり、本を読んだり。ゆっくり更新。','京都','',false,4180,680,now()),
 ('demo-dev','devlog_jp','DevLog','個人開発とフロントエンド。小さく作って公開する。','大阪','devlog.jp',true,3180,421,now()),
 ('demo-yui','yui_photo','ゆい','週末フォトグラファー。空と街の写真。','福岡','',false,5810,910,now())
on conflict (id) do nothing;

insert into public.posts (id, author_id, body, created_at, likes_count, reposts_count, replies_count, views_count, media_urls)
values
 ('p1','demo-sora','新しいデザインシステムを整理していて、余白と文字サイズのルールを少し見直しました。派手な装飾より、情報がすっと入ってくるUIがやっぱり好き。',now()-interval '1 hour',128,24,8,4210,'{}'),
 ('p2','demo-tech','生成AIの進化が速すぎる。モデルの性能だけでなく、日常のアプリやツールに自然に組み込まれるかどうかが、これからの大きな差になりそう。 #AI #テクノロジー',now()-interval '2 hours',342,88,31,18300,'{}'),
 ('p3','demo-mika','今日は少し遠回りして帰った。知らない道に入ると、近所でも新しい景色が見つかるね。',now()-interval '3 hours',45,3,4,980,array['https://images.unsplash.com/photo-1470770841072-f978cf4d019e?w=1000&auto=format&fit=crop&q=85']),
 ('p4','demo-dev','個人開発、最初から完璧を目指すより「まず動くものを作る → 使って直す」のループを回す方が続く。今日は検索まわりを実装した。',now()-interval '5 hours',91,18,12,3440,'{}'),
 ('p5','demo-haru','本屋で偶然見つけた一冊が、今の自分にぴったりだった。こういう出会いがあるから寄り道はやめられない。',now()-interval '8 hours',73,7,5,1620,'{}'),
 ('p6','demo-yui','夕方の空。ほんの数分だけ、街全体がやさしい色になる時間が好き。',now()-interval '12 hours',206,31,9,7910,array['https://images.unsplash.com/photo-1470252649378-9c29740c9fa8?w=1000&auto=format&fit=crop&q=85']),
 ('p7','demo-me','こんにちは、Orbitへようこそ！ここでは日々の出来事や好きなことを気軽に共有できます。まずは気になる人をフォローしてみてください。',now()-interval '18 hours',16,2,3,640,'{}'),
 ('r1','demo-dev','余白のルールが整うと、コンポーネント全体の一貫性も出ますよね。',now()-interval '42 minutes',12,1,1,190,'{}'),
 ('r2','demo-me','わかります。文字サイズと行間もセットで見直すとかなり変わります。',now()-interval '30 minutes',3,0,0,28,'{}'),
 ('r3','demo-mika','使う人の目線で考えるのが大事ですね。',now()-interval '16 hours',4,0,0,80,'{}')
on conflict (id) do nothing;

update public.posts set reply_to='p1' where id='r1' and reply_to is null;
update public.posts set reply_to='r1' where id='r2' and reply_to is null;
update public.posts set reply_to='p7' where id='r3' and reply_to is null;

insert into public.follows (follower_id, following_id) values
 ('demo-me','demo-sora'),('demo-me','demo-tech'),('demo-me','demo-dev'),
 ('demo-sora','demo-me'),('demo-sora','demo-tech'),('demo-dev','demo-me'),
 ('demo-dev','demo-sora'),('demo-mika','demo-haru'),('demo-yui','demo-sora'),
 ('demo-haru','demo-mika')
on conflict do nothing;

insert into public.post_likes(user_id,post_id) values
 ('demo-me','p1'),('demo-dev','p1'),('demo-mika','p1'),
 ('demo-sora','p2'),('demo-haru','p2'),('demo-yui','p2'),
 ('demo-me','p3'),('demo-yui','p3'),
 ('demo-sora','p4'),('demo-tech','p4'),
 ('demo-mika','p5'),
 ('demo-me','p6'),('demo-dev','p6'),
 ('demo-sora','p7'),('demo-dev','p7')
on conflict do nothing;

insert into public.reposts(user_id,post_id) values
 ('demo-dev','p1'),('demo-sora','p1'),('demo-mika','p2'),('demo-yui','p2'),
 ('demo-haru','p4'),('demo-sora','p6'),('demo-haru','p7')
on conflict do nothing;

insert into public.bookmarks(user_id,post_id) values ('demo-me','p5') on conflict do nothing;

insert into public.notifications(recipient_id,actor_id,type,post_id,body,created_at) values
 ('demo-me','demo-sora','like','p7','さんがあなたの投稿にいいねしました。',now()-interval '1 hour'),
 ('demo-me','demo-dev','follow',null,'さんにフォローされました。',now()-interval '3 hours'),
 ('demo-me','demo-mika','reply','p7','さんがあなたの投稿に返信しました。',now()-interval '6 hours'),
 ('demo-me','demo-haru','repost','p7','さんがあなたの投稿をリポストしました。',now()-interval '11 hours')
on conflict do nothing;

insert into public.conversations(id,created_by) values ('demo-chat-sora','demo-me'),('demo-chat-dev','demo-me'),('demo-chat-mika','demo-me') on conflict do nothing;
insert into public.conversation_members(conversation_id,user_id) values
 ('demo-chat-sora','demo-me'),('demo-chat-sora','demo-sora'),
 ('demo-chat-dev','demo-me'),('demo-chat-dev','demo-dev'),
 ('demo-chat-mika','demo-me'),('demo-chat-mika','demo-mika')
on conflict do nothing;
insert into public.messages(conversation_id,sender_id,body,created_at) values
 ('demo-chat-sora','demo-sora','こんにちは！投稿を見てフォローしました。よろしくお願いします。',now()-interval '30 hours'),
 ('demo-chat-sora','demo-me','ありがとうございます！こちらこそよろしくお願いします。',now()-interval '28 hours'),
 ('demo-chat-dev','demo-dev','個人開発の話、ぜひまた聞かせてください！',now()-interval '20 hours'),
 ('demo-chat-mika','demo-mika','おすすめのカフェがあれば教えてください ☕',now()-interval '12 hours');

insert into public.lists(id,owner_id,name,description,is_public) values
 ('demo-list-design','demo-me','デザインの人たち','UI・デザイン関連のアカウント',true),
 ('demo-list-days','demo-me','日々の記録','暮らしや写真の投稿',true)
on conflict (id) do nothing;
insert into public.list_members(list_id,user_id) values
 ('demo-list-design','demo-sora'),('demo-list-design','demo-dev'),
 ('demo-list-days','demo-mika'),('demo-list-days','demo-haru'),('demo-list-days','demo-yui')
on conflict do nothing;

-- Enable realtime for user-facing tables where the publication exists.
do $$
begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime') then
    begin alter publication supabase_realtime add table public.posts; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.post_likes; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.reposts; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.follows; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.messages; exception when duplicate_object then null; end;
  end if;
end $$;
