-- The legacy media bucket is empty and unused. Keep it private as a safety net.
UPDATE storage.buckets
SET public = false
WHERE id = 'orbit-media'
  AND NOT EXISTS (
    SELECT 1 FROM storage.objects WHERE bucket_id = 'orbit-media'
  );
