-- Persist poll expiration independently of scheduled_at.
-- The scheduled-post cron clears scheduled_at when a post becomes public, so
-- the expiration timestamp must survive that publication transition.
alter table public.posts
  add column if not exists poll_expires_at timestamptz;

update public.posts
set poll_expires_at =
  coalesce(scheduled_at, created_at)
  + case poll_duration
      when '3日' then interval '3 days'
      when '7日' then interval '7 days'
      else interval '1 day'
    end
where poll_options is not null
  and poll_expires_at is null;

comment on column public.posts.poll_expires_at is
  'Server-calculated end time for poll voting; retained after scheduled_at is cleared.';

create or replace function private.set_poll_expiration()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.poll_options is null then
    new.poll_expires_at := null;
  else
    new.poll_expires_at :=
      coalesce(new.scheduled_at, new.created_at, pg_catalog.now())
      + case new.poll_duration
          when '3日' then interval '3 days'
          when '7日' then interval '7 days'
          else interval '1 day'
        end;
  end if;

  return new;
end;
$function$;

revoke all on function private.set_poll_expiration() from public, anon, authenticated, service_role;

drop trigger if exists posts_set_poll_expiration on public.posts;
create trigger posts_set_poll_expiration
before insert on public.posts
for each row
execute function private.set_poll_expiration();

drop policy if exists "Users vote once" on public.poll_votes;
create policy "Users vote once"
on public.poll_votes
for insert
to authenticated
with check (
  user_id = (select auth.uid())::text
  and exists (
    select 1
    from public.posts p
    where p.id = poll_votes.post_id
      and p.deleted_at is null
      and p.poll_options is not null
      and pg_catalog.cardinality(p.poll_options) >= 2
      and poll_votes.option_index >= 0
      and poll_votes.option_index < pg_catalog.cardinality(p.poll_options)
      and (p.scheduled_at is null or p.scheduled_at <= pg_catalog.now())
      and (
        p.visibility = 'public'
        or p.author_id = (select auth.uid())::text
        or (
          p.visibility = 'followers'
          and exists (
            select 1
            from public.follows f
            where f.follower_id = (select auth.uid())::text
              and f.following_id = p.author_id
          )
        )
      )
      and coalesce(
        p.poll_expires_at,
        coalesce(p.scheduled_at, p.created_at)
          + case p.poll_duration
              when '3日' then interval '3 days'
              when '7日' then interval '7 days'
              else interval '1 day'
            end
      ) > pg_catalog.now()
  )
);
