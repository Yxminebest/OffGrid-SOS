-- NEW PROJECT ONLY. Existing projects: apply migrations/ only after schema review.
-- Supabase provides auth.*, storage.* and the authenticated/anon roles.
begin;
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  first_name text not null default '', last_name text not null default '', photo_path text
);
create table public.user_private (
  user_id uuid primary key references auth.users on delete cascade, phone text
);
create table public.user_roles (
  user_id uuid primary key references auth.users on delete cascade,
  role text not null default 'user' check(role in ('user','rescuer','admin'))
);
create function public.is_admin() returns boolean language sql stable security definer
set search_path=public as $$ select exists(select 1 from user_roles where user_id=auth.uid() and role='admin') $$;
create function public.create_member() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id,first_name,last_name) values(new.id,coalesce(new.raw_user_meta_data->>'first_name',''),coalesce(new.raw_user_meta_data->>'last_name',''));
  insert into user_private(user_id,phone) values(new.id,new.raw_user_meta_data->>'phone');
  insert into user_roles(user_id) values(new.id);
  return new;
end $$;
create trigger on_auth_member after insert on auth.users for each row execute function public.create_member();
create table public.rescue_verification_requests (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade,
  organization_name text not null, personnel_id text not null, document_path text, note text,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  submitted_at timestamptz not null default now(), reviewed_at timestamptz,
  reviewed_by uuid references auth.users on delete set null, rejection_reason text
);
create unique index one_pending_rescue_request on public.rescue_verification_requests(user_id) where status='pending';
create table public.sos_events (
  id uuid primary key, owner_id uuid not null references auth.users on delete cascade,
  message text not null, latitude double precision, longitude double precision, accuracy double precision,
  is_active boolean not null default true, ended_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.conversations (
  id uuid primary key default gen_random_uuid(), direct_key text unique,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.conversation_members (
  conversation_id uuid references public.conversations on delete cascade,
  user_id uuid references auth.users on delete cascade, last_read_at timestamptz,
  primary key(conversation_id,user_id)
);
create function public.in_chat(room uuid) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from conversation_members where conversation_id=room and user_id=auth.uid())
$$;
create table public.messages (
  id uuid primary key, conversation_id uuid not null references public.conversations on delete cascade,
  sender_id uuid not null references auth.users on delete cascade,
  type text not null check(type in ('text','image','video','location')), content text not null default '',
  reply_to_id uuid references public.messages on delete set null,
  latitude double precision, longitude double precision, accuracy double precision,
  media_path text, media_name text, media_mime text, media_size bigint,
  status text not null default 'synced', is_deleted boolean not null default false, edited_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index messages_room_time on public.messages(conversation_id,created_at);
create table public.message_reactions (
  conversation_id uuid not null references public.conversations on delete cascade,
  message_id uuid references public.messages on delete cascade,
  user_id uuid references auth.users on delete cascade, emoji text check(length(emoji)<=32),
  primary key(conversation_id,message_id,user_id,emoji)
);
create table public.chat_typing (
  conversation_id uuid references public.conversations on delete cascade,
  user_id uuid references auth.users on delete cascade, updated_at timestamptz not null default now(),
  primary key(conversation_id,user_id)
);
create function public.touch_chat() returns trigger language plpgsql security definer set search_path=public as $$
begin update conversations set updated_at=now() where id=coalesce(new.conversation_id,old.conversation_id); return coalesce(new,old); end $$;
create trigger message_touched after insert or update or delete on public.messages for each row execute function public.touch_chat();

alter table public.profiles enable row level security;
alter table public.user_private enable row level security;
alter table public.user_roles enable row level security;
alter table public.rescue_verification_requests enable row level security;
alter table public.sos_events enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.chat_typing enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(true);
create policy profiles_edit on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy private_owner on public.user_private for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy roles_read on public.user_roles for select to authenticated using(user_id=auth.uid() or public.is_admin());
-- Roles are only written by trusted SQL / checked admin RPCs.
create policy rescue_read on public.rescue_verification_requests for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy rescue_apply on public.rescue_verification_requests for insert to authenticated with check(user_id=auth.uid() and status='pending' and reviewed_at is null and reviewed_by is null and rejection_reason is null);
create policy sos_owner on public.sos_events for all to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy rooms_read on public.conversations for select to authenticated using(public.in_chat(id));
create policy members_read on public.conversation_members for select to authenticated using(public.in_chat(conversation_id));
create policy messages_read on public.messages for select to authenticated using(public.in_chat(conversation_id));
create policy messages_insert on public.messages for insert to authenticated with check(sender_id=auth.uid() and public.in_chat(conversation_id));
create policy messages_update on public.messages for update to authenticated using(sender_id=auth.uid() and public.in_chat(conversation_id)) with check(sender_id=auth.uid() and public.in_chat(conversation_id));
create policy messages_delete on public.messages for delete to authenticated using(sender_id=auth.uid() and public.in_chat(conversation_id));
create policy reactions_read on public.message_reactions for select to authenticated using(public.in_chat(conversation_id));
create policy reactions_insert on public.message_reactions for insert to authenticated with check(user_id=auth.uid() and public.in_chat(conversation_id) and exists(select 1 from messages m where m.id=message_id and m.conversation_id=message_reactions.conversation_id));
create policy reactions_delete on public.message_reactions for delete to authenticated using(user_id=auth.uid());
create policy typing_read on public.chat_typing for select to authenticated using(public.in_chat(conversation_id));
create policy typing_owner on public.chat_typing for all to authenticated using(user_id=auth.uid() and public.in_chat(conversation_id)) with check(user_id=auth.uid() and public.in_chat(conversation_id));

create function public.chat_get_or_create_direct(p_other_user uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare room uuid; pair text;
begin
  if auth.uid() is null or p_other_user=auth.uid() or not exists(select 1 from profiles where id=p_other_user) then raise exception 'Invalid recipient'; end if;
  pair:=least(auth.uid()::text,p_other_user::text)||':'||greatest(auth.uid()::text,p_other_user::text);
  insert into conversations(direct_key) values(pair) on conflict(direct_key) do update set direct_key=excluded.direct_key returning id into room;
  insert into conversation_members(conversation_id,user_id) values(room,auth.uid()),(room,p_other_user) on conflict do nothing;
  return room;
end $$;
create function public.chat_mark_read(p_conversation_id uuid) returns void language sql security definer set search_path=public as $$
  update conversation_members set last_read_at=now() where conversation_id=p_conversation_id and user_id=auth.uid()
$$;
create function public.chat_search_users(p_query text) returns table(id uuid, first_name text,last_name text,photo_path text,role text)
language sql stable security definer set search_path=public as $$
  select p.id,p.first_name,p.last_name,p.photo_path,r.role from profiles p join user_roles r on r.user_id=p.id
  where auth.uid() is not null and p.id<>auth.uid() and length(trim(p_query))>=2
  and (p.first_name||' '||p.last_name) ilike '%'||left(p_query,100)||'%' limit 40
$$;
create function public.chat_list_conversations() returns table(conversation_id uuid,other_user_id uuid,display_name text,photo_path text,last_message text,last_message_at timestamptz,unread_count bigint,peer_last_read_at timestamptz,updated_at timestamptz)
language sql stable security definer set search_path=public as $$
 select c.id,p.id,trim(p.first_name||' '||p.last_name),p.photo_path,
   latest.content,latest.created_at,
   (select count(*) from messages m where m.conversation_id=c.id and m.sender_id<>auth.uid() and not m.is_deleted and m.created_at>coalesce(mine.last_read_at,'epoch'::timestamptz)),
   peer.last_read_at,c.updated_at
 from conversations c join conversation_members mine on mine.conversation_id=c.id and mine.user_id=auth.uid()
 join conversation_members peer on peer.conversation_id=c.id and peer.user_id<>auth.uid()
 join profiles p on p.id=peer.user_id
 left join lateral(select content,created_at from messages where conversation_id=c.id and not is_deleted order by created_at desc limit 1) latest on true
 order by c.updated_at desc
$$;
create function public.review_rescue_request(p_request_id uuid,p_approve boolean,p_rejection_reason text default null) returns void
language plpgsql security definer set search_path=public as $$
declare who uuid;
begin
 if not public.is_admin() then raise exception 'Admin required'; end if;
 if not p_approve and nullif(trim(p_rejection_reason),'') is null then raise exception 'Reason required'; end if;
 update rescue_verification_requests set status=case when p_approve then 'approved' else 'rejected' end,
   reviewed_at=now(),reviewed_by=auth.uid(),rejection_reason=case when p_approve then null else p_rejection_reason end
   where id=p_request_id and status='pending' returning user_id into who;
 if who is null then raise exception 'No pending request'; end if;
 if p_approve then update user_roles set role='rescuer' where user_id=who and role<>'admin'; end if;
end $$;
create function public.revoke_rescuer(p_user_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_admin() then raise exception 'Admin required'; end if; update user_roles set role='user' where user_id=p_user_id and role='rescuer'; end $$;

insert into storage.buckets(id,name,public,file_size_limit) values
 ('chat-media','chat-media',false,26214400),('avatars','avatars',false,5242880),('rescue-verification','rescue-verification',false,10485760);
create policy app_file_write on storage.objects for insert to authenticated with check(bucket_id in ('chat-media','avatars','rescue-verification') and (storage.foldername(name))[1]=auth.uid()::text);
create policy app_file_update on storage.objects for update to authenticated using(bucket_id in ('chat-media','avatars','rescue-verification') and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id in ('chat-media','avatars','rescue-verification') and (storage.foldername(name))[1]=auth.uid()::text);
create policy app_file_delete on storage.objects for delete to authenticated using(bucket_id in ('chat-media','avatars','rescue-verification') and (storage.foldername(name))[1]=auth.uid()::text);
create policy app_file_read on storage.objects for select to authenticated using(
 (bucket_id='avatars') or
 (bucket_id='rescue-verification' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin())) or
 (bucket_id='chat-media' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from messages m where m.media_path=name and public.in_chat(m.conversation_id))))
);
-- Explicit grants: no anonymous table access, no role/request self-approval.
revoke all on all tables in schema public from anon;
grant select on public.profiles,public.user_roles,public.rescue_verification_requests,public.conversations,public.conversation_members to authenticated;
grant update(first_name,last_name,photo_path) on public.profiles to authenticated;
grant select,insert,update,delete on public.user_private,public.sos_events,public.messages,public.message_reactions,public.chat_typing to authenticated;
grant insert(user_id,organization_name,personnel_id,document_path,note) on public.rescue_verification_requests to authenticated;
revoke execute on all functions in schema public from public,anon;
grant execute on function public.is_admin(),public.in_chat(uuid),public.chat_get_or_create_direct(uuid),public.chat_mark_read(uuid),public.chat_search_users(text),public.chat_list_conversations(),public.review_rescue_request(uuid,boolean,text),public.revoke_rescuer(uuid) to authenticated;
alter publication supabase_realtime add table public.messages,public.conversations,public.conversation_members,public.message_reactions,public.chat_typing;
commit;
