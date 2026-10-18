-- Existing OffGrid-SOS schema only. Preserves all application rows and files.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Only checked RPCs may create direct rooms / membership.
revoke insert,update,delete,truncate,references,trigger on public.conversation_members from authenticated;
revoke insert,update,delete,truncate,references,trigger on public.conversations from authenticated;
drop policy if exists conversation_members_insert_self_or_member on public.conversation_members;
drop policy if exists conversation_members_delete_self on public.conversation_members;
drop policy if exists conversations_insert_creator on public.conversations;
drop policy if exists conversations_update_member on public.conversations;
drop policy if exists chat_members_select_members on public.conversation_members;
drop policy if exists chat_conversations_select_member on public.conversations;

-- Remove duplicate policies; retain the owner/member policies using private helpers.
drop policy if exists chat_messages_select_members on public.messages;
drop policy if exists chat_messages_insert_members on public.messages;
drop policy if exists chat_messages_update_sender on public.messages;
drop policy if exists chat_messages_delete_sender on public.messages;

-- Reactions must refer to a message in the SAME room, not m.room = m.room.
drop policy if exists chat_reactions_select_member on public.message_reactions;
drop policy if exists chat_reactions_insert_self on public.message_reactions;
drop policy if exists chat_reactions_delete_self on public.message_reactions;
create policy chat_reactions_select_member on public.message_reactions for select to authenticated
 using (private.is_conversation_member(conversation_id));
create policy chat_reactions_insert_self on public.message_reactions for insert to authenticated
 with check (user_id=(select auth.uid()) and private.is_conversation_member(conversation_id)
 and exists(select 1 from public.messages m where m.id=message_reactions.message_id
   and m.conversation_id=message_reactions.conversation_id));
create policy chat_reactions_delete_self on public.message_reactions for delete to authenticated
 using(user_id=(select auth.uid()) and private.is_conversation_member(conversation_id));

drop policy if exists chat_typing_select_member on public.chat_typing;
drop policy if exists chat_typing_insert_self on public.chat_typing;
drop policy if exists chat_typing_update_self on public.chat_typing;
drop policy if exists chat_typing_delete_self on public.chat_typing;
create policy chat_typing_select_member on public.chat_typing for select to authenticated
 using(private.is_conversation_member(conversation_id));
create policy chat_typing_insert_self on public.chat_typing for insert to authenticated
 with check(user_id=(select auth.uid()) and private.is_conversation_member(conversation_id));
create policy chat_typing_update_self on public.chat_typing for update to authenticated
 using(user_id=(select auth.uid()) and private.is_conversation_member(conversation_id))
 with check(user_id=(select auth.uid()) and private.is_conversation_member(conversation_id));
create policy chat_typing_delete_self on public.chat_typing for delete to authenticated
 using(user_id=(select auth.uid()) and private.is_conversation_member(conversation_id));
revoke all on public.chat_typing,public.message_reactions from anon;
revoke truncate,references,trigger on public.chat_typing,public.message_reactions from authenticated;
revoke update on public.message_reactions from authenticated;

-- Internal trigger helpers are not client RPC endpoints. Triggers keep working.
revoke execute on function public.chat_refresh_conversation_preview(),public.handle_new_user(),
 public.notify_new_message(),public.notify_new_sos(),public.notify_sos_response(),
 public.rls_auto_enable(),public.set_updated_at() from public,anon,authenticated;
-- Superseded week-3/demo and membership lookup APIs aren't used by the app.
revoke execute on function public.ensure_week3_conversation(uuid),public.chat_is_member(uuid,uuid)
 from public,anon,authenticated;

-- Android is supported; keep existing platforms and device rows.
alter table public.devices drop constraint devices_platform_check;
alter table public.devices add constraint devices_platform_check
 check(platform in ('android','ios','web','macos'));

-- Room-aware reads support existing room/... and current owner/room/message/... layouts.
create or replace function private.can_read_chat_object(object_path text) returns boolean
language plpgsql stable security invoker set search_path='' as $$
declare parts text[]:=storage.foldername(object_path); room uuid;
begin
 if (select auth.uid()) is null then return false; end if;
 if parts[1]=(select auth.uid())::text then return true; end if;
 if exists(select 1 from public.messages m where m.media_path=object_path
   and private.is_conversation_member(m.conversation_id)) then return true; end if;
 if parts[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
   room:=parts[2]::uuid;
   if private.is_conversation_member(room) then return true; end if;
 end if;
 if parts[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
   return private.is_conversation_member(parts[1]::uuid);
 end if;
 return false;
end $$;
create or replace function private.can_write_chat_object(object_path text) returns boolean
language plpgsql stable security invoker set search_path='' as $$
declare parts text[]:=storage.foldername(object_path);
begin
 if parts[1] is distinct from (select auth.uid())::text then return false; end if;
 if parts[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
   return private.is_conversation_member(parts[2]::uuid);
 end if;
 return false;
end $$;
revoke all on function private.can_read_chat_object(text),private.can_write_chat_object(text) from public,anon;
grant execute on function private.can_read_chat_object(text),private.can_write_chat_object(text) to authenticated;
drop policy if exists chat_media_delete_member on storage.objects;
drop policy if exists chat_media_delete_sender on storage.objects;
drop policy if exists chat_media_insert_member on storage.objects;
drop policy if exists chat_media_insert_sender on storage.objects;
drop policy if exists chat_media_read_members on storage.objects;
drop policy if exists chat_media_select_member on storage.objects;
drop policy if exists chat_media_update_member on storage.objects;
drop policy if exists chat_media_update_sender on storage.objects;
create policy chat_media_select_member on storage.objects for select to authenticated
 using(bucket_id='chat-media' and private.can_read_chat_object(name));
create policy chat_media_insert_sender on storage.objects for insert to authenticated
 with check(bucket_id='chat-media' and private.can_write_chat_object(name));
create policy chat_media_update_sender on storage.objects for update to authenticated
 using(bucket_id='chat-media' and (private.can_write_chat_object(name)
   or (owner_id=(select auth.uid())::text and private.can_read_chat_object(name))))
 with check(bucket_id='chat-media' and (private.can_write_chat_object(name)
   or (owner_id=(select auth.uid())::text and private.can_read_chat_object(name))));
create policy chat_media_delete_sender on storage.objects for delete to authenticated
 using(bucket_id='chat-media' and (private.can_write_chat_object(name)
   or (owner_id=(select auth.uid())::text and private.can_read_chat_object(name))));
drop policy if exists avatars_read_authenticated on storage.objects;

-- Add missing FK indexes identified by production advisors. No existing index removed.
create index if not exists chat_typing_user_idx on public.chat_typing(user_id);
create index if not exists conversations_creator_idx on public.conversations(created_by);
create index if not exists media_attachments_uploader_idx on public.media_attachments(uploader_id);
create index if not exists message_reactions_user_idx on public.message_reactions(user_id);
create index if not exists messages_reply_idx on public.messages(reply_to_id);
create index if not exists messages_source_device_idx on public.messages(source_device_id);
create index if not exists rescue_sessions_source_device_idx on public.rescue_sessions(source_device_id);
create index if not exists rescue_requests_reviewer_idx on public.rescue_verification_requests(reviewed_by);
create index if not exists sos_events_source_device_idx on public.sos_events(source_device_id);
create index if not exists user_roles_assigner_idx on public.user_roles(assigned_by);
create index if not exists messages_media_path_idx on public.messages(media_path) where media_path is not null;
