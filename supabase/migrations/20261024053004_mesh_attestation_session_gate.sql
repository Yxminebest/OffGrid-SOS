-- A valid but signed-out JWT must not mint a fresh 30-day offline identity.
create function private.mesh_attestation_role(p_user uuid,p_session uuid)
returns text language sql stable security definer set search_path=''
as $$ select r.role::text from public.user_roles r
      where r.user_id=p_user and exists (
        select 1 from auth.sessions s where s.id=p_session and s.user_id=p_user
        and (s.not_after is null or s.not_after>now())) $$;
revoke all on function private.mesh_attestation_role(uuid,uuid) from public,anon,authenticated;
grant execute on function private.mesh_attestation_role(uuid,uuid) to service_role;
create function public.mesh_attestation_role(p_user uuid,p_session uuid)
returns text language sql stable security invoker set search_path=''
as $$ select private.mesh_attestation_role(p_user,p_session) $$;
revoke all on function public.mesh_attestation_role(uuid,uuid) from public,anon,authenticated;
grant execute on function public.mesh_attestation_role(uuid,uuid) to service_role;
