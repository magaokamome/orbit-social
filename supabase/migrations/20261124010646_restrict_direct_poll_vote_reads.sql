-- Poll voters are private. The client reads only aggregate counts and its own choice
-- through public.get_poll_results(), never the underlying user_id column.
DROP POLICY IF EXISTS "Poll results are public" ON public.poll_votes;
REVOKE SELECT ON TABLE public.poll_votes FROM PUBLIC, anon, authenticated;
