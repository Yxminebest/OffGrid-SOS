-- Read-only checks, run after installation as project owner.
select c.relname,c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in
 ('profiles','user_private','user_roles','rescue_verification_requests','sos_events','messages',
  'conversations','conversation_members','message_reactions','chat_typing','nearby_archive');
select schemaname,tablename,policyname,roles,cmd,qual,with_check from pg_policies
where (schemaname='public' and tablename='nearby_archive') or
 (schemaname='storage' and policyname like 'nearby_archive%');
select id,public,file_size_limit from storage.buckets
where id in ('nearby-archive','chat-media','avatars','rescue-verification');
-- Expected: all listed RLS flags true; nearby archive bucket public=false.
-- Also test with actual A/B/anon JWTs; inspect every existing permissive policy.
