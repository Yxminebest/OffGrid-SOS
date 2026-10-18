-- Keep public RPC names/signatures; privileged, guarded implementations live in private.
set local lock_timeout='5s';

CREATE OR REPLACE FUNCTION private.rpc_chat_get_or_create_direct(p_other_user uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_me uuid := auth.uid();
  v_key text;
  v_conversation uuid;
begin
  if v_me is null then
    raise exception 'Authentication required';
  end if;

  if p_other_user is null or p_other_user = v_me then
    raise exception 'Invalid chat recipient';
  end if;

  if not exists (select 1 from public.profiles where id = p_other_user) then
    raise exception 'Recipient not found';
  end if;

  v_key := case
    when v_me::text < p_other_user::text
      then v_me::text || ':' || p_other_user::text
    else p_other_user::text || ':' || v_me::text
  end;

  insert into public.conversations (
    id,
    created_by,
    kind,
    direct_key,
    created_at,
    updated_at
  )
  values (
    gen_random_uuid(),
    v_me,
    'direct',
    v_key,
    now(),
    now()
  )
  on conflict (direct_key) where direct_key is not null
  do update set updated_at = public.conversations.updated_at
  returning id into v_conversation;

  insert into public.conversation_members (conversation_id, user_id, joined_at)
  values
    (v_conversation, v_me, now()),
    (v_conversation, p_other_user, now())
  on conflict do nothing;

  return v_conversation;
end;
$function$
;
revoke all on function private.rpc_chat_get_or_create_direct(p_other_user uuid) from public,anon;
grant execute on function private.rpc_chat_get_or_create_direct(p_other_user uuid) to authenticated;
CREATE OR REPLACE FUNCTION public.chat_get_or_create_direct(p_other_user uuid) RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
 select private.rpc_chat_get_or_create_direct(p_other_user);
$$;
revoke all on function public.chat_get_or_create_direct(p_other_user uuid) from public,anon;
grant execute on function public.chat_get_or_create_direct(p_other_user uuid) to authenticated;

CREATE OR REPLACE FUNCTION private.rpc_chat_list_conversations()
 RETURNS TABLE(conversation_id uuid, other_user_id uuid, display_name text, photo_path text, last_message text, last_message_at timestamp with time zone, unread_count bigint, peer_last_read_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    c.id as conversation_id,
    peer.user_id as other_user_id,
    trim(concat_ws(' ', p.first_name, p.last_name)) as display_name,
    p.photo_path,
    c.last_message_preview as last_message,
    c.last_message_at,
    (
      select count(*)
      from public.messages m
      where m.conversation_id = c.id
        and coalesce(m.is_deleted, false) = false
        and m.sender_id <> auth.uid()
        and m.created_at > coalesce(me.last_read_at, 'epoch'::timestamptz)
    ) as unread_count,
    peer.last_read_at as peer_last_read_at,
    c.updated_at
  from public.conversation_members me
  join public.conversations c on c.id = me.conversation_id
  join public.conversation_members peer
    on peer.conversation_id = c.id
   and peer.user_id <> me.user_id
  join public.profiles p on p.id = peer.user_id
  where auth.uid() is not null and me.user_id = auth.uid()
    and c.kind = 'direct'
    and me.archived_at is null
  order by coalesce(c.last_message_at, c.updated_at) desc;
$function$
;
revoke all on function private.rpc_chat_list_conversations() from public,anon;
grant execute on function private.rpc_chat_list_conversations() to authenticated;
CREATE OR REPLACE FUNCTION public.chat_list_conversations() RETURNS TABLE(conversation_id uuid, other_user_id uuid, display_name text, photo_path text, last_message text, last_message_at timestamptz, unread_count bigint, peer_last_read_at timestamptz, updated_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 select * from private.rpc_chat_list_conversations();
$$;
revoke all on function public.chat_list_conversations() from public,anon;
grant execute on function public.chat_list_conversations() to authenticated;

CREATE OR REPLACE FUNCTION private.rpc_chat_search_users(p_query text DEFAULT ''::text)
 RETURNS TABLE(id uuid, first_name text, last_name text, photo_path text, role text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    p.id,
    p.first_name,
    p.last_name,
    p.photo_path,
    ur.role::text
  from public.profiles p
  left join public.user_roles ur on ur.user_id = p.id
  where auth.uid() is not null and p.id <> auth.uid()
    and (
      nullif(trim(p_query), '') is null
      or concat_ws(' ', p.first_name, p.last_name) ilike '%' || trim(p_query) || '%'
    )
  order by p.first_name, p.last_name
  limit 30;
$function$
;
revoke all on function private.rpc_chat_search_users(p_query text) from public,anon;
grant execute on function private.rpc_chat_search_users(p_query text) to authenticated;
CREATE OR REPLACE FUNCTION public.chat_search_users(p_query text DEFAULT ''::text) RETURNS TABLE(id uuid, first_name text, last_name text, photo_path text, role text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 select * from private.rpc_chat_search_users(p_query);
$$;
revoke all on function public.chat_search_users(p_query text) from public,anon;
grant execute on function public.chat_search_users(p_query text) to authenticated;

CREATE OR REPLACE FUNCTION private.rpc_chat_mark_read(p_conversation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.conversation_members
  set last_read_at = now()
  where conversation_id = p_conversation_id
    and user_id = auth.uid();

  if not found then
    raise exception 'Not a member of this conversation';
  end if;
end;
$function$
;
revoke all on function private.rpc_chat_mark_read(p_conversation_id uuid) from public,anon;
grant execute on function private.rpc_chat_mark_read(p_conversation_id uuid) to authenticated;
CREATE OR REPLACE FUNCTION public.chat_mark_read(p_conversation_id uuid) RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
 select private.rpc_chat_mark_read(p_conversation_id);
$$;
revoke all on function public.chat_mark_read(p_conversation_id uuid) from public,anon;
grant execute on function public.chat_mark_read(p_conversation_id uuid) to authenticated;

CREATE OR REPLACE FUNCTION private.rpc_review_rescue_request(p_request_id uuid, p_approve boolean, p_rejection_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target_user uuid;
begin

  if not private.is_admin() then
    raise exception 'admin role required';
  end if;

  select r.user_id
  into target_user
  from public.rescue_verification_requests r
  where r.id = p_request_id
    and r.status = 'pending'
  for update;

  if target_user is null then
    raise exception 'pending rescue verification request not found';
  end if;

  update public.rescue_verification_requests
  set
    status = case when p_approve then 'approved' else 'rejected' end,
    reviewed_at = now(),
    reviewed_by = (select auth.uid()),
    rejection_reason = case
      when p_approve then null
      else p_rejection_reason
    end
  where id = p_request_id;

  if p_approve then
    update public.user_roles
    set
      role = case
        when role = 'admin'::public.app_role then role
        else 'rescuer'::public.app_role
      end,
      assigned_at = now(),
      assigned_by = (select auth.uid())
    where user_id = target_user;
  end if;

end;
$function$
;
revoke all on function private.rpc_review_rescue_request(p_request_id uuid, p_approve boolean, p_rejection_reason text) from public,anon;
grant execute on function private.rpc_review_rescue_request(p_request_id uuid, p_approve boolean, p_rejection_reason text) to authenticated;
CREATE OR REPLACE FUNCTION public.review_rescue_request(p_request_id uuid, p_approve boolean, p_rejection_reason text DEFAULT NULL::text) RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
 select private.rpc_review_rescue_request(p_request_id,p_approve,p_rejection_reason);
$$;
revoke all on function public.review_rescue_request(p_request_id uuid, p_approve boolean, p_rejection_reason text) from public,anon;
grant execute on function public.review_rescue_request(p_request_id uuid, p_approve boolean, p_rejection_reason text) to authenticated;

CREATE OR REPLACE FUNCTION private.rpc_revoke_rescuer(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin

  if not private.is_admin() then
    raise exception 'admin role required';
  end if;

  update public.user_roles
  set
    role = 'user'::public.app_role,
    assigned_at = now(),
    assigned_by = (select auth.uid())
  where user_id = p_user_id
    and role = 'rescuer'::public.app_role;

end;
$function$
;
revoke all on function private.rpc_revoke_rescuer(p_user_id uuid) from public,anon;
grant execute on function private.rpc_revoke_rescuer(p_user_id uuid) to authenticated;
CREATE OR REPLACE FUNCTION public.revoke_rescuer(p_user_id uuid) RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
 select private.rpc_revoke_rescuer(p_user_id);
$$;
revoke all on function public.revoke_rescuer(p_user_id uuid) from public,anon;
grant execute on function public.revoke_rescuer(p_user_id uuid) to authenticated;

-- Merge equivalent admin/self policies without widening access.
drop policy if exists rescue_request_select_admin on public.rescue_verification_requests;
drop policy if exists rescue_request_select_own on public.rescue_verification_requests;
create policy rescue_request_select_own_or_admin on public.rescue_verification_requests for select to authenticated
 using(user_id=(select auth.uid()) or (select private.is_admin()));
drop policy if exists rescue_request_update_admin on public.rescue_verification_requests;
drop policy if exists rescue_request_update_own_pending on public.rescue_verification_requests;
create policy rescue_request_update_own_pending_or_admin on public.rescue_verification_requests for update to authenticated
 using((select private.is_admin()) or (user_id=(select auth.uid()) and status='pending'))
 with check((select private.is_admin()) or
   (user_id=(select auth.uid()) and status='pending' and reviewed_at is null and reviewed_by is null));
