# การติดตั้ง Backend รุ่น 9

ติดตั้งบนโปรเจกต์ OffGrid-SOS จริงแล้ววันที่ 18 ต.ค. 2569: 3 migrations และ delete-account รุ่น 5
ดูผลตรวจและขอบเขตที่ `supabase-deployment-2026-10-18.md`
ขั้นตอนด้านล่างเก็บไว้สำหรับติดตั้งซ้ำ/โปรเจกต์ใหม่
แอปฝั่ง Android ใช้ publishable/anon key เท่านั้น ส่วน service-role อยู่ใน Edge Function

## โปรเจกต์ที่ใช้อยู่แล้ว

1. ตรวจ schema และ policies เดิมก่อน ไม่รัน `bootstrap.sql` ทับโปรเจกต์เดิม
   รอบนี้บันทึก snapshot นิยาม schema/policies/function ก่อนแก้ไว้แล้ว ไม่ใช่ backup ข้อมูลทั้งฐาน
2. เปิด SQL Editor ของโปรเจกต์ แล้วรัน `supabase/migrations/20261018104150_offgrid_v9_nearby_archive.sql`
3. ตาราง `nearby_archive` และ private bucket `nearby-archive` ต้องมี owner-only RLS
4. โปรเจกต์เดิมนี้มี hardening และ private RPC wrappers ตามไฟล์ migration ใน repo ติดตั้งแล้วด้วย
   ชื่อไฟล์ตรงกับ migration history บน server
5. Deploy `supabase/functions/delete-account/index.ts` ด้วย Supabase CLI: `supabase functions deploy delete-account --project-ref PROJECT_REF` โดยคงการตรวจ JWT
6. ตั้ง redirect `com.kittaporn.offgridsos://login-callback/` และทดสอบ signup/verify/reset password ด้วยอีเมลจริง

หากยังไม่ติดตั้ง migration แชท D2D และประวัติ local ใช้ได้ตามเดิม แต่หน้าซิงก์จะรายงานผิดพลาดและลองสำรองใหม่ ข้อมูล local ไม่ถูกลบ

## โปรเจกต์ใหม่

1. รัน `supabase/bootstrap.sql` **ครั้งเดียวบนโปรเจกต์ใหม่ที่ยังไม่มีตารางแอป**
2. รัน migration Nearby ตามด้านบน จากนั้น deploy Edge Function
3. สร้างผู้ใช้จริงผ่าน signup แล้วให้เจ้าของฐานข้อมูลกำหนด admin คนแรก:

```sql
update public.user_roles set role='admin' where user_id='USER_UUID';
```

อย่าเปิดให้แอปเขียน `user_roles` เอง ผู้ใช้ทั่วไปส่งคำขอตรวจเอกสาร แล้ว admin ใช้ RPC อนุมัติ

## ข้อมูลและขอบเขต

| ข้อมูล | ที่จัดเก็บ | สิทธิ์ |
|---|---|---|
| สมาชิก/ชื่อ | Auth, profiles | สมาชิกอ่านชื่อ; เจ้าของแก้ชื่อ/รูป |
| เบอร์โทร | user_private | เจ้าของ |
| Role | user_roles | เจ้าของ/admin อ่าน; admin RPC เปลี่ยน |
| เอกสารกู้ภัย | rescue_verification_requests, rescue-verification | เจ้าของ/admin |
| แชทออนไลน์ | conversations, conversation_members, messages | สมาชิกห้อง; ผู้ส่งแก้/ลบข้อความตัวเอง |
| รูป/วิดีโอออนไลน์ | chat-media | ผู้ส่งและสมาชิกห้องตามข้อความที่อ้างไฟล์ |
| SOS cloud | sos_events | เจ้าของ; การประกาศให้คนใกล้เคียงใช้ D2D |
| ประวัติ Nearby สำรอง | nearby_archive, nearby-archive | เจ้าของสำเนาเท่านั้น |

Nearby archive เป็นสำเนาประวัติของบัญชีที่ล็อกอิน ไม่ใช่การส่งข้อความออนไลน์ให้ผู้รับแทน Nearby
Guest เก็บในเครื่อง ไม่แอบนำประวัติ guest ไปผูกกับสมาชิกอีกบัญชี
สำรองทั้ง incoming/outgoing พร้อมไฟล์ และกู้คืนที่ **โปรไฟล์ → จัดการบัญชี → กู้คืนประวัติ Nearby จากคลาวด์**
สถานะรับถึงเครื่องและสถานะสำรองแยกกัน การสำรองไม่ทำให้ข้อความที่ยังค้างส่งกลายเป็นส่งถึงผู้รับ

## ตรวจสิทธิ์ก่อนใช้จริง

ใช้ JWT ของบัญชี A/B/C และ anon ทดสอบอย่างน้อย: A อ่าน archive A ได้, B/anon อ่าน archive A ไม่ได้;
B ดาวน์โหลด path ไฟล์ A ใน nearby-archive ไม่ได้; ผู้ไม่อยู่ในห้องอ่าน messages/media ไม่ได้;
user เปลี่ยน role/อนุมัติ rescue ไม่ได้; admin อนุมัติได้; user ลบได้เฉพาะบัญชีตนเอง
มี checklist SQL ที่ `supabase/tests/access_checks.sql` สำหรับตรวจ schema และ RLS ที่เปิดไว้
รอบนี้ทดสอบจริงด้วย role/claims ภายใน transaction (rollback) และ HTTP แบบไม่ล็อกอินแล้ว
ยังต้องทดสอบ Auth/Storage upload/download ด้วย session ผู้ใช้ผ่านแอปจริง

แหล่งอ้างอิง: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[Storage access control](https://supabase.com/docs/guides/storage/security/access-control)

## การตรวจอัตโนมัติในเครื่อง

รอบนี้รัน bootstrap, migration (รวมรันซ้ำ), และทดสอบสิทธิ์ด้วย PostgreSQL/WASM แล้วผ่าน 15 checks
ใช้ auth/storage stubs เพื่อแยกทดสอบ SQL/RLS/RPC โดยไม่แตะข้อมูล production

```sh
npm install --prefix build/backend-qa --no-audit --no-fund @electric-sql/pglite@0.3.14
node tool/check_backend.mjs
```

ผลนี้ยังไม่แทน Auth, Storage HTTP, JWT gateway และ Edge Function บน Supabase จริง
Private archive ที่กู้คืนเป็นประวัติของเครื่องเดิม ไม่สำรอง private key และไม่ส่งคิวเก่าในนามอุปกรณ์ใหม่
