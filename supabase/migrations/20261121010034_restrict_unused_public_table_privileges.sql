-- Remove table privileges that are not used by the client API.
-- RLS does not apply to TRUNCATE; REFERENCES and TRIGGER are schema-management capabilities.
REVOKE TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA public
  FROM anon, authenticated, service_role;

-- list_members has no UPDATE policy and the client never updates membership rows.
REVOKE UPDATE ON TABLE public.list_members FROM authenticated;
