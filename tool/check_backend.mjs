// Local PostgreSQL/WASM QA, no production credentials or network calls.
// npm install --prefix build/backend-qa @electric-sql/pglite@0.3.14
// node tool/check_backend.mjs
import { PGlite } from '../build/backend-qa/node_modules/@electric-sql/pglite/dist/index.js';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const db = new PGlite();
const a='00000000-0000-4000-8000-000000000001';
const b='00000000-0000-4000-8000-000000000002';
const c='00000000-0000-4000-8000-000000000003';
const id='00000000-0000-4000-8000-000000000004';
await db.exec(`
 create role anon; create role authenticated;
 create schema auth; create schema storage;
 create table auth.users(id uuid primary key,raw_user_meta_data jsonb default '{}');
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth,storage to authenticated,anon;
 grant execute on function auth.uid() to authenticated,anon;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
 alter table storage.objects enable row level security;
 grant select,insert,update,delete on storage.objects to authenticated;
 create function storage.foldername(text) returns text[] language sql immutable as $$select string_to_array($1,'/')$$;
 create publication supabase_realtime;
`);
await db.exec(await readFile(new URL('../supabase/bootstrap.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../supabase/migrations/20261018104150_offgrid_v9_nearby_archive.sql',import.meta.url),'utf8'));
// Migration must be repeatable on an already configured archive.
await db.exec(await readFile(new URL('../supabase/migrations/20261018104150_offgrid_v9_nearby_archive.sql',import.meta.url),'utf8'));
await db.exec(`insert into auth.users(id) values('${a}'),('${b}'),('${c}');`);
let checks=0;
async function asUser(user,fn) {
  await db.exec(`set role authenticated; select set_config('request.jwt.claim.sub','${user}',false);`);
  try { return await fn(); } finally { await db.exec('reset role;'); }
}
async function rejected(sql) {
  await assert.rejects(db.exec(sql)); checks++;
}
await asUser(a,async()=>{
  await db.query(`insert into nearby_archive(owner_id,message_id,peer,incoming,delivery,envelope,revision)
    values($1,$2,'peer',false,'pending',$3,1)`,[a,id,JSON.stringify({id,kind:'direct',data:{text:'private'}})]);
  await db.query(`insert into storage.objects(bucket_id,name) values('nearby-archive',$1)`,[`${a}/${id}`]);
  assert.equal((await db.query('select * from nearby_archive')).rows.length,1); checks++;
  await rejected(`update user_roles set role='admin' where user_id='${a}'`);
  await rejected(`select review_rescue_request('${id}',true,null)`);
});
await asUser(b,async()=>{
  assert.equal((await db.query('select * from nearby_archive')).rows.length,0); checks++;
  assert.equal((await db.query("select * from storage.objects where bucket_id='nearby-archive'")).rows.length,0); checks++;
  await rejected(`insert into nearby_archive(owner_id,message_id,peer,incoming,delivery,envelope) values('${a}','${id}','peer',false,'pending','{"id":"${id}"}')`);
  assert.equal((await db.query(`update nearby_archive set delivery='delivered' where owner_id='${a}' returning *`)).rows.length,0); checks++;
});
await db.exec('set role anon;');
await rejected('select * from nearby_archive');
await db.exec('reset role;');
let room;
await asUser(a,async()=>{
  room=(await db.query('select chat_get_or_create_direct($1) as id',[b])).rows[0].id;
  await db.query(`insert into messages(id,conversation_id,sender_id,type,content) values($1,$2,$3,'text','hello')`,[id,room,a]);
});
await asUser(b,async()=>{
  assert.equal((await db.query('select * from messages')).rows.length,1); checks++;
  assert.equal((await db.query('select * from chat_list_conversations()')).rows.length,1); checks++;
  await db.query('select chat_mark_read($1)',[room]);
  assert.equal((await db.query(`delete from messages where id=$1 returning *`,[id])).rows.length,0); checks++;
});
await asUser(c,async()=>{
  assert.equal((await db.query('select * from messages')).rows.length,0); checks++;
  await rejected(`insert into messages(id,conversation_id,sender_id,type) values(gen_random_uuid(),'${room}','${c}','text')`);
});
await db.exec(`update user_roles set role='admin' where user_id='${c}'`);
let request;
await asUser(a,async()=>{
  await db.exec(`insert into rescue_verification_requests(user_id,organization_name,personnel_id) values('${a}','Rescue','R1')`);
});
request=(await db.query(`select id from rescue_verification_requests where user_id=$1`,[a])).rows[0].id;
await asUser(c,async()=>{ await db.query('select review_rescue_request($1,true,null)',[request]); });
assert.equal((await db.query('select role from user_roles where user_id=$1',[a])).rows[0].role,'rescuer'); checks++;
await db.exec(`delete from auth.users where id='${a}'`);
assert.equal((await db.query('select * from nearby_archive')).rows.length,0); checks++;
console.log(`Backend bootstrap + migration passed; ${checks} access/role/cascade checks passed (local PostgreSQL, storage/auth stubs).`);
await db.close();
