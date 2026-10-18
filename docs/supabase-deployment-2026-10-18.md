# ผลติดตั้ง Supabase จริง — 18 ต.ค. 2569

โปรเจกต์ `OffGrid-SOS` / `evfopzvqsngrunopxgvl` สถานะ ACTIVE_HEALTHY
ผู้ใช้อนุญาตให้จัดการ Backend แล้ว ส่วนติดตั้ง/ทดสอบโทรศัพท์พักไว้ตามคำขอ

## ติดตั้งสำเร็จ

| Migration บน server และไฟล์ใน repo | สิ่งที่ทำ |
|---|---|
| `20261018104117_offgrid_v9_existing_project_hardening.sql` | ปิดสิทธิ์ self-join ห้องผู้อื่นและแก้ routing key, แก้ reaction ข้ามห้อง, สิทธิ์ Storage, helper RPC, รองรับ Android และเพิ่ม indexes |
| `20261018104150_offgrid_v9_nearby_archive.sql` | ตาราง nearby_archive, private bucket 25 MB, owner RLS และ grants ที่จำกัด |
| `20261018121814_offgrid_v9_private_rpc_wrappers.sql` | ย้าย privileged implementations ไป private, public API เป็น invoker wrapper โดยคงชื่อ/พารามิเตอร์เดิม; รวม policies กู้ภัยที่ซ้ำกัน |

Edge Function `delete-account` อัปเดตจาก v4 เป็น **v5 ACTIVE**
เพิ่มล้างไฟล์ `nearby-archive` คงการตรวจ JWT และ recent-authentication เดิม
อ่าน source ที่ deploy กลับมาตรวจว่ามี bucket ใหม่และ `verify_jwt=true` แล้ว
ไม่ได้เรียกคำสั่งลบบัญชีจริงเพื่อทดสอบ

## สิทธิ์ที่แก้จากของเดิม

- เดิม `conversation_members_insert_self_or_member` อนุญาต INSERT ตัวเองในห้องที่รู้ UUID
  ตอนนี้ client เพิ่มสมาชิกโดยตรงไม่ได้ ใช้ RPC ที่ตรวจผู้ใช้และคู่สนทนาเท่านั้น
- เดิมสมาชิกแก้ routing/creator ของห้องได้ ตอนนี้เฉพาะ checked RPC จัดการ
- เดิม reaction ตรวจ `m.conversation_id = m.conversation_id` ซึ่งไม่ตรวจห้องของ reaction จริง
  ตอนนี้บังคับ message และ reaction อยู่ห้องเดียวกัน แม้ผู้ใช้จะเป็นสมาชิกทั้งสองห้อง
- เพื่อนในห้องอ่านไฟล์ได้ แต่เขียนทับไฟล์ผู้ส่งไม่ได้ รองรับ path แบบเก่าและใหม่
- ตัดสิทธิ์ TRUNCATE ที่หลงเหลือจาก default grants และไม่เปิด internal triggers เป็น public RPC
- ลบ policies ซ้ำโดยเก็บเงื่อนไข owner/member/admin ตามที่แอปใช้

## ผลทดสอบ

1. **Production SQL regression 32 assertions ผ่าน** (`supabase/tests/production_v9_regression.sql`)
   ใช้ role authenticated/anon และ UID ของบัญชี QA ชั่วคราวบนฐานข้อมูลจริง
   ทดสอบ archive/Storage RLS, ห้องแชท, self-join, role escalation, rescue approval,
   reaction, typing, mark-read, inbox RPC, Android และ private buckets
   ทุก fixture อยู่ใน transaction ที่ rollback ไม่เหลือบัญชีหรือข้อความทดสอบ
2. **HTTP จริง 4 checks ผ่าน** (`tool/check_supabase_http.py`)
   Auth health 200; anon อ่าน archive ถูกปฏิเสธ 401;
   schema private ไม่เปิดใน REST 406; ลบบัญชีโดยไม่ล็อกอินถูกปฏิเสธ 401
3. PostgreSQL/WASM เดิม **15 checks ผ่าน** หลังจัดไฟล์ migration ให้ตรง server
4. Security advisors หลังแก้: ไม่เหลือรายการเตือนฟังก์ชัน SECURITY DEFINER ใน exposed API
   เหลือ **Leaked Password Protection Disabled** ซึ่งเป็นตัวเลือก Auth ที่ต้องใช้ Pro ขึ้นไป
   ไม่ได้เปลี่ยนแผนหรือสร้างค่าใช้จ่ายให้ผู้ใช้
5. Performance advisors: ไม่มีคำเตือน RLS initplan / multiple permissive policies / missing FK indexes
   เหลือ INFO เรื่อง indexes ยังไม่ถูกใช้ ซึ่งเก็บไว้รองรับ joins/cascade เมื่อข้อมูลเพิ่ม

## ยืนยันข้อมูลเดิม

| ข้อมูล | ก่อนแก้ | หลังแก้และ rollback tests |
|---|---:|---:|
| Auth users | 3 | 3 |
| Messages | 16 | 16 |
| SOS events | 5 | 5 |
| Storage objects | 8 | 8 |
| Nearby archive | ไม่มีตาราง | 0 (ตารางใหม่พร้อมใช้งาน) |

Snapshot นิยามก่อนแก้: `supabase-schema-before-2026-10-18.json`
Source ฟังก์ชันก่อน deploy: `delete-account-before-2026-10-18.json`
ผลตรวจจากเครื่องมือ: `supabase-verification-2026-10-18.json`
Snapshot เหล่านี้เป็น metadata/source ไม่ใช่ full database backup

## ขอบเขตที่ยังไม่ได้ทดสอบ

- ไม่ได้ติดตั้งหรือทดสอบโทรศัพท์ตามคำขอพักงานส่วนนั้น
- ยังไม่ได้ทำ Auth signup/email delivery หรือ Storage upload/download ผ่าน session ผู้ใช้จากแอปจริง
  SQL tests ใช้ role/claims ภายใน transaction ไม่ใช่ JWT login จากมือถือ
- ไม่ได้ลบบัญชีจริงหรือทดสอบการลบสื่อผู้ใช้จริง
- ไม่เปลี่ยน Auth redirects/providers/แพ็กเกจ และไม่ push GitHub ในรอบนี้
- APK v9 เดิมยังใช้กับ backend นี้ได้ เพราะคง API/ชื่อ RPC เดิมและไม่แก้โค้ด Flutter รอบนี้

อ้างอิง: [RLS และ grants](https://supabase.com/docs/guides/database/postgres/row-level-security),
[Leaked password protection และ Pro](https://supabase.com/docs/guides/auth/password-security)
