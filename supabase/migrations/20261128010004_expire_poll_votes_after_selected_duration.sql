-- Expire poll voting after the duration selected by the author.
-- The expiration starts when a scheduled post becomes public, not when it is drafted.
-- Existing poll votes remain available through the aggregate results function.
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
      and coalesce(p.scheduled_at, p.created_at)
        + case p.poll_duration
            when '3日' then interval '3 days'
            when '7日' then interval '7 days'
            else interval '1 day'
          end > pg_catalog.now()
  )
);
