-- Keep the unintegrated AI writer dormant until a reviewed server-side caller exists.
-- Do not enable a SECURITY DEFINER write path through service_role while the app has no backend caller.
revoke execute on function private.ai_create_post(text, text, text) from service_role;
revoke usage on schema private from service_role;
