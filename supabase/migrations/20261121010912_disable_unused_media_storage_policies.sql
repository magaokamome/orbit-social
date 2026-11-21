-- Lime2 does not use Supabase Storage. Remove the unused public and authenticated
-- object policies so the empty legacy bucket cannot be used by the client.
DROP POLICY IF EXISTS "Public read Orbit media" ON storage.objects;
DROP POLICY IF EXISTS "Users upload own Orbit media" ON storage.objects;
DROP POLICY IF EXISTS "Users update own Orbit media" ON storage.objects;
DROP POLICY IF EXISTS "Users delete own Orbit media" ON storage.objects;
