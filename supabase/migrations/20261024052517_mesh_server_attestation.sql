-- Issuer seed is generated inside PostgreSQL, never shipped to mobile clients.
create table private.mesh_issuer_keys (
  key_id text primary key,
  seed text not null,
  created_at timestamptz not null default now()
);
alter table private.mesh_issuer_keys enable row level security;
revoke all on private.mesh_issuer_keys from public, anon, authenticated;
insert into private.mesh_issuer_keys(key_id,seed)
values ('mesh-2026-10',encode(extensions.gen_random_bytes(32),'base64'));

create function private.mesh_issuer_seed()
returns jsonb language sql stable security definer set search_path=''
as $$ select jsonb_build_object('key_id',key_id,'seed',seed)
      from private.mesh_issuer_keys where key_id='mesh-2026-10' $$;
revoke all on function private.mesh_issuer_seed() from public,anon,authenticated;
grant usage on schema private to service_role;
grant execute on function private.mesh_issuer_seed() to service_role;

-- Service-only PostgREST wrapper. No mobile/anonymous role can execute it.
create function public.mesh_issuer_seed()
returns jsonb language sql stable security invoker set search_path=''
as $$ select private.mesh_issuer_seed() $$;
revoke all on function public.mesh_issuer_seed() from public,anon,authenticated;
grant execute on function public.mesh_issuer_seed() to service_role;
