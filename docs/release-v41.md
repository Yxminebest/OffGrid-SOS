# SOSBROO 0.10.10+41

## เมนู

ยกเลิกส่งข้อความ / ลบข้อความ / แก้ไขข้อความ / ตอบกลับ เท่านั้น เปลี่ยนชื่อเมนูลบข้อความทุกเครื่องเป็นลบข้อความ โดยยังลบกล่องข้อความที่ส่งเองจากแชททั้งสองฝั่งตามรุ่น 39–40 ฟังก์ชันออนไลน์/ออฟไลน์และสิทธิ์ผู้เขียนคงเดิม

## Supabase

ตรวจ schema และ RLS ที่เก็บใน repo แล้ว public.messages มี type/content สำหรับคำสั่ง text และสิทธิ์เขียน/ลบจำกัดผู้ส่งในห้องสมาชิก ใช้ schema เดิมได้ ไม่จำเป็นต้องเพิ่มคอลัมน์หรือ migration เพื่อเปลี่ยนชื่อเมนู

เพิ่มเทสผ่าน SupabaseClient จริงกับ HTTP server บน loopback:

- บันทึกต้นฉบับและคำสั่ง reply/edit/retract/delete ลงคิว ส่งผ่าน /rest/v1/messages ตรวจว่า type/content/sender_id/conversation_id ไม่เปลี่ยนระหว่างส่ง และประกอบประวัติฝั่งรับจากข้อมูล cloud แล้วการลบ/ตอบกลับยังตรงกัน
- เมื่อเข้าคิวลบข้อความคลาวด์ที่มี media_path ตรวจว่า client เรียก DELETE /rest/v1/messages และ DELETE /storage/v1/object/chat-media พร้อม prefixes ของไฟล์เดิม
- แก้ docs/supabase-chat-storage.md ให้แยกชื่อคอลัมน์ local message_type จาก cloud type และอธิบายว่าคำสั่งของหน้ารวมแชทเก็บใน content ไม่ได้รับรองว่า edited_at/reply_to_id ของแถวต้นฉบับเปลี่ยนตามคำสั่งทุกครั้ง

ไม่มี Supabase connector ที่ใช้ได้ในรอบนี้ จึงไม่ได้อ่านหรือแก้ schema/RLS/ข้อมูลของ live project เทส loopback ตรวจรูปแบบการสื่อสารของ client และการประมวลผลข้อมูล ไม่ได้รัน PostgreSQL/RLS จริง ไม่ควรตีความว่า deploy หรือยืนยันฐานข้อมูลจริงแล้ว

## ผลตรวจและ APK

- flutter analyze --no-pub: No issues found — build/analyze-v41.log
- flutter test --no-pub: 252 เคสผ่าน — build/tests-v41.log
- เทส Supabase REST และเมนูเฉพาะส่วน: 18 เคสผ่าน — build/targeted-v41.log

ไฟล์: build/app/outputs/flutter-apk/SOSBROO-v41.apk — versionName 0.10.10, versionCode 41 คง package ID และข้อมูลเดิมสำหรับอัปเดตทับ

ประกอบ release สำเร็จ (build/apk-v41.log) ตรวจ manifest ชื่อ/เวอร์ชันตรง และ zipalign -c -P 16 4 ผ่าน

SHA-256: C5506985F2E26AC476BB97BAC1FF1F09047A3D1C371103D2130FC37CD9F0285F

ยังไม่ได้ติดตั้งบนโทรศัพท์ในรอบนี้
