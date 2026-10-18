-- Additive migration for the existing project. Run as the database owner.
create table if not exists public.nearby_archive (
  owner_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid not null,
  peer text not null check (length(peer) <= 128),
  incoming boolean not null,
  delivery text not null check (delivery in ('pending','sent','delivered')),
  envelope jsonb not null check (jsonb_typeof(envelope) = 'object'),
  revision bigint,
  media_path text,
  updated_at timestamptz not null default now(),
  primary key (owner_id, message_id),
  check (media_path is null or media_path = owner_id::text || '/' || message_id::text),
  check (envelope ? 'id' and envelope->>'id' = message_id::text)
);
alter table public.nearby_archive enable row level security;
revoke all on public.nearby_archive from anon;
revoke all on public.nearby_archive from authenticated;
grant select,insert,update,delete on public.nearby_archive to authenticated;
drop policy if exists nearby_archive_owner on public.nearby_archive;
create policy nearby_archive_owner on public.nearby_archive for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
insert into storage.buckets(id,name,public,file_size_limit)
  values ('nearby-archive','nearby-archive',false,26214400)
  on conflict(id) do update set public=false, file_size_limit=26214400;
drop policy if exists nearby_archive_files_owner on storage.objects;
create policy nearby_archive_files_owner on storage.objects for all to authenticated
  using (bucket_id='nearby-archive' and (storage.foldername(name))[1]=(select auth.uid())::text)
  with check (bucket_id='nearby-archive' and (storage.foldername(name))[1]=(select auth.uid())::text);
