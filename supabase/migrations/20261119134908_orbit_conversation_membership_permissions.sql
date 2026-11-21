
 drop policy if exists "Users add themselves or existing members add others" on public.conversation_members;
 create policy "Conversation creators add initial members" on public.conversation_members
 for insert to authenticated with check (
   user_id = (select auth.uid())::text
   or exists (
     select 1 from public.conversations c
     where c.id = conversation_id and c.created_by = (select auth.uid())::text
   )
   or public.is_conversation_member(conversation_id)
 );
 drop policy if exists "Users leave their conversations" on public.conversation_members;
 create policy "Users leave their conversations" on public.conversation_members
 for delete to authenticated using (user_id = (select auth.uid())::text);
 grant delete on public.conversation_members to authenticated;
