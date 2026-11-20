-- The ALL policy already grants SELECT to authenticated users with the same owner predicate.
-- Remove the duplicate SELECT policy without changing effective access.
DROP POLICY IF EXISTS "Users view their mutes" ON public.muted_users;
