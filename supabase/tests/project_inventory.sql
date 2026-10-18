-- Read-only inventory before modifying the existing OffGrid-SOS project.
-- No user records, credentials, auth tokens, or document contents are selected.
select table_name,column_name,data_type,is_nullable,column_default
from information_schema.columns
where table_schema='public' and table_name in
 ('profiles','user_private','user_roles','rescue_verification_requests','sos_events',
  'conversations','conversation_members','messages','message_reactions','chat_typing','nearby_archive')
order by table_name,ordinal_position;

select c.relname as table_name,c.relrowsecurity,c.relforcerowsecurity
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' order by c.relname;

select schemaname,tablename,policyname,roles,cmd,qual,with_check
from pg_policies where schemaname in ('public','storage')
order by schemaname,tablename,policyname;

select id,name,public,file_size_limit,allowed_mime_types
from storage.buckets order by id;

select p.proname,pg_get_function_identity_arguments(p.oid) as arguments,
 pg_get_function_result(p.oid) as result_type,p.prosecdef as security_definer,
 p.proconfig as settings,p.proacl as execute_acl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in
 ('chat_list_conversations','chat_search_users','chat_get_or_create_direct',
  'chat_mark_read','review_rescue_request','revoke_rescuer','is_admin','in_chat')
order by p.proname;

select grantee,table_name,privilege_type
from information_schema.role_table_grants
where table_schema='public' and grantee in ('anon','authenticated')
order by table_name,grantee,privilege_type;

select tablename from pg_publication_tables
where pubname='supabase_realtime' and schemaname='public' order by tablename;
