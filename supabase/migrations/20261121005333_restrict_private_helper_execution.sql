-- Restrict the conversation membership helper to authenticated callers only.
REVOKE ALL ON SCHEMA private FROM anon;
GRANT USAGE ON SCHEMA private TO authenticated;
REVOKE ALL ON FUNCTION private.is_conversation_member(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_conversation_member(text) TO authenticated;
