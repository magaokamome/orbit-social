-- Reconcile denormalized profile counters with the authoritative follows table.
UPDATE public.profiles AS p
SET followers_count = (
      SELECT count(*)::integer FROM public.follows AS f WHERE f.following_id = p.id
    ),
    following_count = (
      SELECT count(*)::integer FROM public.follows AS f WHERE f.follower_id = p.id
    );
