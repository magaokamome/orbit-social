-- Keep the identity sequence ahead of manually seeded trend IDs.
SELECT setval(
  pg_get_serial_sequence('public.trends','id'),
  GREATEST((SELECT COALESCE(MAX(id),1) FROM public.trends),1),
  true
);
