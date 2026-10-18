-- Run as project owner. Fixtures and every write are rolled back.
begin;
set local statement_timeout='30s';
create temporary table offgrid_checks(label text);
grant insert,select on offgrid_checks to authenticated,anon;
create function pg_temp.assert_ok(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Regression failed: %',label; end if;
 insert into offgrid_checks values(label); end $$;
do $$begin
 if exists(select 1 from auth.users where id in
 ('85000000-0000-4000-8000-000000000001','85000000-0000-4000-8000-000000000002','85000000-0000-4000-8000-000000000003')) then
 raise exception 'Fixture collision; choose unused fixture IDs'; end if;
end $$;
insert into auth.users(id,raw_user_meta_data) values
 ('85000000-0000-4000-8000-000000000001','{"first_name":"QA","last_name":"A"}'),
 ('85000000-0000-4000-8000-000000000002','{"first_name":"QA","last_name":"B"}'),
 ('85000000-0000-4000-8000-000000000003','{"first_name":"QA","last_name":"C"}');
set local role authenticated;
select set_config('request.jwt.claim.sub','85000000-0000-4000-8000-000000000001',true);
select set_config('offgrid_test.ab',public.chat_get_or_create_direct('85000000-0000-4000-8000-000000000002')::text,true);
select set_config('offgrid_test.ac',public.chat_get_or_create_direct('85000000-0000-4000-8000-000000000003')::text,true);
select pg_temp.assert_ok((select count(*)=2 from public.conversation_members where conversation_id=current_setting('offgrid_test.ab')::uuid),'RPC creates exactly two members');
insert into public.messages(id,conversation_id,sender_id,type,content,status) values
 ('85000000-0000-4000-8000-000000000004',current_setting('offgrid_test.ab')::uuid,auth.uid(),'text','QA rollback message','synced');
select pg_temp.assert_ok((select count(*)=1 from public.messages where id='85000000-0000-4000-8000-000000000004'),'sender inserts chat message');
insert into public.nearby_archive(owner_id,message_id,peer,incoming,delivery,envelope,revision) values
 (auth.uid(),'85000000-0000-4000-8000-000000000005','peer-b',false,'pending','{"id":"85000000-0000-4000-8000-000000000005","kind":"direct","data":{"text":"QA rollback archive"}}',1);
select pg_temp.assert_ok((select count(*)=1 from public.nearby_archive where message_id='85000000-0000-4000-8000-000000000005'),'owner reads archive');
update public.nearby_archive set delivery='delivered',revision=2 where message_id='85000000-0000-4000-8000-000000000005';
select pg_temp.assert_ok((select delivery='delivered' from public.nearby_archive where message_id='85000000-0000-4000-8000-000000000005'),'owner updates archive');
insert into storage.objects(bucket_id,name,owner_id) values
 ('nearby-archive','85000000-0000-4000-8000-000000000001/85000000-0000-4000-8000-000000000005',auth.uid()::text),
 ('chat-media','85000000-0000-4000-8000-000000000001/'||current_setting('offgrid_test.ab')||'/85000000-0000-4000-8000-000000000004/qa.jpg',auth.uid()::text);
select pg_temp.assert_ok((select count(*)=1 from storage.objects where bucket_id='nearby-archive' and name like '85000000-%'),'owner archive Storage insert/select');
-- Storage upsert is an INSERT followed by UPDATE; verify UPDATE remains permitted.
with changed as (update storage.objects set user_metadata='{"qa":true}' where bucket_id='nearby-archive' and name like '85000000-%' returning id)
select pg_temp.assert_ok((select count(*)=1 from changed),'owner archive Storage update');
insert into public.devices(id,user_id,platform) values('85000000-0000-4000-8000-000000000006',auth.uid(),'android');
select pg_temp.assert_ok((select platform='android' from public.devices where id='85000000-0000-4000-8000-000000000006'),'Android device accepted');
insert into public.rescue_verification_requests(id,user_id,organization_name,personnel_id) values
 ('85000000-0000-4000-8000-000000000007',auth.uid(),'QA rollback team','QA-1');
do $$declare denied boolean:=false; begin
 begin update public.user_roles set role='admin' where user_id=auth.uid(); exception when insufficient_privilege then denied:=true; end;
 perform pg_temp.assert_ok(denied,'user cannot promote own role');
 denied:=false;
 begin perform public.review_rescue_request('85000000-0000-4000-8000-000000000007',true,null);
 exception when raise_exception then if sqlerrm ilike '%admin%' then denied:=true; else raise; end if; end;
 perform pg_temp.assert_ok(denied,'non-admin cannot approve rescue');
 denied:=false;
 begin insert into public.message_reactions(conversation_id,message_id,user_id,emoji) values
 (current_setting('offgrid_test.ac')::uuid,'85000000-0000-4000-8000-000000000004',auth.uid(),'👍');
 exception when insufficient_privilege then denied:=true; end;
 perform pg_temp.assert_ok(denied,'cross-room reaction rejected even for member of both rooms');
end $$;

select set_config('request.jwt.claim.sub','85000000-0000-4000-8000-000000000002',true);
select pg_temp.assert_ok((select count(*)=1 from public.messages where id='85000000-0000-4000-8000-000000000004'),'recipient reads message');
select pg_temp.assert_ok((select count(*)=0 from public.nearby_archive where message_id='85000000-0000-4000-8000-000000000005'),'other account cannot read archive');
select pg_temp.assert_ok((select count(*)=0 from storage.objects where bucket_id='nearby-archive' and name like '85000000-%'),'other account cannot read archive file');
select pg_temp.assert_ok((select count(*)=1 from storage.objects where bucket_id='chat-media' and name like '85000000-%'),'room member reads chat file');
with changed as (update public.messages set content='forged' where id='85000000-0000-4000-8000-000000000004' returning id)
 select pg_temp.assert_ok((select count(*)=0 from changed),'recipient cannot edit sender message');
with changed as (update storage.objects set user_metadata='{"forged":true}' where bucket_id='chat-media' and name like '85000000-%' returning id)
 select pg_temp.assert_ok((select count(*)=0 from changed),'recipient cannot overwrite sender file');
with changed as (update public.nearby_archive set delivery='pending' where message_id='85000000-0000-4000-8000-000000000005' returning message_id)
 select pg_temp.assert_ok((select count(*)=0 from changed),'other account cannot update archive');
with removed as (delete from public.nearby_archive where message_id='85000000-0000-4000-8000-000000000005' returning message_id)
 select pg_temp.assert_ok((select count(*)=0 from removed),'other account cannot delete archive');
select public.chat_mark_read(current_setting('offgrid_test.ab')::uuid);
select pg_temp.assert_ok((select last_read_at is not null from public.conversation_members where conversation_id=current_setting('offgrid_test.ab')::uuid and user_id=auth.uid()),'mark-read RPC works');
insert into public.chat_typing(conversation_id,user_id) values(current_setting('offgrid_test.ab')::uuid,auth.uid());
insert into public.message_reactions(conversation_id,message_id,user_id,emoji) values
 (current_setting('offgrid_test.ab')::uuid,'85000000-0000-4000-8000-000000000004',auth.uid(),'👍');
select pg_temp.assert_ok((select count(*)=1 from public.message_reactions where message_id='85000000-0000-4000-8000-000000000004'),'valid reaction works');
select pg_temp.assert_ok((select count(*)>=1 from public.chat_list_conversations() where conversation_id=current_setting('offgrid_test.ab')::uuid),'inbox RPC still works');

select set_config('request.jwt.claim.sub','85000000-0000-4000-8000-000000000003',true);
select pg_temp.assert_ok((select count(*)=0 from public.messages where id='85000000-0000-4000-8000-000000000004'),'outsider cannot read message');
select pg_temp.assert_ok((select count(*)=0 from storage.objects where bucket_id='chat-media' and name like '85000000-%'),'outsider cannot read chat file');
do $$declare denied boolean:=false; begin
 begin insert into public.conversation_members(conversation_id,user_id) values(current_setting('offgrid_test.ab')::uuid,auth.uid());
 exception when insufficient_privilege then denied:=true; end;
 perform pg_temp.assert_ok(denied,'outsider cannot self-join private room');
 denied:=false;
 begin update public.conversations set direct_key='forged' where id=current_setting('offgrid_test.ac')::uuid;
 exception when insufficient_privilege then denied:=true; end;
 perform pg_temp.assert_ok(denied,'client cannot alter direct-room routing key');
 denied:=false;
 begin insert into public.nearby_archive(owner_id,message_id,peer,incoming,delivery,envelope) values
 ('85000000-0000-4000-8000-000000000001','85000000-0000-4000-8000-000000000008','peer',false,'pending','{"id":"85000000-0000-4000-8000-000000000008"}');
 exception when insufficient_privilege then denied:=true; end;
 perform pg_temp.assert_ok(denied,'outsider cannot insert owner archive');
end $$;
select pg_temp.assert_ok(not has_function_privilege('authenticated','public.notify_new_message()','execute'),'trigger helper not a client RPC');
reset role;
update public.user_roles set role='admin' where user_id='85000000-0000-4000-8000-000000000003';
set local role authenticated;
select public.review_rescue_request('85000000-0000-4000-8000-000000000007',true,null);
reset role;
select pg_temp.assert_ok((select role='rescuer' from public.user_roles where user_id='85000000-0000-4000-8000-000000000001'),'admin approval assigns rescue role');

set local role anon;
do $$declare denied boolean:=false; begin
 begin perform 1 from public.nearby_archive; exception when insufficient_privilege then denied:=true; end;
 perform pg_temp.assert_ok(denied,'anon archive read rejected');
end $$;
reset role;
select pg_temp.assert_ok((select count(*)=0 from storage.buckets where id in ('nearby-archive','chat-media','avatars','rescue-verification') and public),'all application buckets private');
select pg_temp.assert_ok(not has_table_privilege('authenticated','public.nearby_archive','truncate'),'authenticated cannot truncate archive');
select pg_temp.assert_ok((select count(*)=0 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity),'all public tables have RLS');
rollback;
select 'PASS: production SQL regression completed; all fixtures rolled back' as result;
