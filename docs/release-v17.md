# 0.7.1+17 — ตรวจโจทย์และแก้ความทนทานของแชท

ตรวจวันที่ 24 ตุลาคม 2569 ต่อจากรุ่น 16

## APK

- `build/app/outputs/flutter-apk/Offgrid-SOS-v17-audited.apk` ขนาด 71,307,675 bytes
- ตรวจ manifest จริง: versionName 0.7.1 / versionCode 17 / minSdk 24 / allowBackup=false
- SHA-256 `86d6ce2b174a87bd7ef0f8131ef65ba69880520fb4ee07d4a1616efe1e9c28f9`
- apksigner verify ผ่าน certificate เดิม `0bb719fdea76bebffcf87b1433ab5eb968e817337c0fb4816f8a845f3064142a`
- ADB ไม่พบอุปกรณ์ขณะจบรอบนี้ จึงไม่ได้ติดตั้งรุ่น 17 ลงโทรศัพท์

## สิ่งที่แก้ในรอบนี้

1. คิววิทยุของทุกผู้ติดต่อทำงานก่อน RPC/อัปโหลดคลาวด์ ปัญหา HTTP ของคนหนึ่งจึงไม่ขวางการเริ่มส่งผ่านวิทยุให้คนอื่น
2. คงคำเตือนพิกัดเก่าและค่าความคลาดเคลื่อนเมื่อส่งข้อความจากคิวคลาวด์ไป Nearby ไม่เปลี่ยนพิกัดเก่าให้ดูเป็นพิกัดสด
3. บันทึกเนื้อหาข้อความที่เข้าออนไลน์จากกล่องข้อความลง local DB แม้ยังไม่เคยเปิดห้องนั้น กลับมาอ่านออฟไลน์ได้ โดยไม่สั่ง mark-read แทนผู้ใช้
4. กล่องข้อความที่ส่งมาเพียงบางรายการไม่ถูกใช้ลบประวัติเก่า และไม่เขียนทับข้อความที่กำลังแก้/รอซิงก์
5. ตรวจบัญชีหลังค้นหาผู้ติดต่อ/อ่านไฟล์ ก่อนเข้าคิว และใน callback ข้อความคลาวด์ หยุด unified worker ตอนออกจากระบบ/ลบบัญชี
6. ตรวจ session หลังอัปโหลดไฟล์ก่อนแก้ metadata ในเครื่อง
7. ปฏิเสธข้อความว่างหรือเกิน 4,000 ตัวอักษรพร้อมแจ้งข้อผิดพลาด เดิมเส้นทางวิทยุอาจคืนค่าโดยไม่บันทึก แต่ UI ล้างช่องพิมพ์
8. เก็บข้อผิดพลาดของ worker ไว้สำหรับวิเคราะห์ แทนล้างทิ้งเมื่อจบรอบ
9. ปิด Android automatic backup ผ่าน allowBackup=false เพื่อลดการคัดลอกฐานข้อมูล/ตัวตนอุปกรณ์โดยระบบสำรองข้อมูล ไม่ใช่การเพิ่มการเข้ารหัส local DB

## หลักฐานตรวจ

- Flutter tests: 165 เคสผ่าน (เดิม 156 + regression ใหม่ 9)
- Flutter analyzer: ไม่พบ issues
- ชุดใหม่ครอบคลุมคลาวด์ค้าง/วิทยุสองผู้รับ, พิกัดเก่า, สลับบัญชีระหว่าง await, ข้อความยาว/ว่าง และ inbox cache 4 กรณี
- ทดสอบ SQL บน Supabase จริงจาก `supabase/tests/production_v9_regression.sql` ผ่าน ทั้งหมดอยู่ใน transaction ที่ rollback ไม่มีข้อมูลทดสอบค้าง
- ตรวจตาราง public 18 ตาราง เปิด RLS ครบ; avatars/rescue-verification/chat-media/nearby-archive เป็น private ทั้งหมด
- SQL ตรวจการอ่าน/เขียนห้องส่วนตัว ไฟล์ผู้อื่น การยกระดับสิทธิ์และ admin approval ผ่าน
- Security advisor พบคำเตือนเดียว: Leaked Password Protection Disabled
- Performance advisor พบ unused indexes 15 รายการระดับ INFO เก็บไว้ เพราะดัชนี FK/คำสั่งค้นหามีประโยชน์เมื่อเริ่มใช้งานจริง การยังไม่มีสถิติใช้งานไม่ใช่เหตุให้ลบทันที
- Logs ที่ตรวจพบ ERROR กลุ่ม PostgreSQL PARSE/SQLSTATE 57014 (ยกเลิก statement/timeout) ไม่ใช่หลักฐานว่าแอปทำงานครบทุกเส้นทาง
- ไม่มี migration หรือการเปลี่ยน RLS/role/Storage บน backend ในรุ่นนี้

## ส่วนที่ต้องตรวจยืนยันต่อ

- ติดตั้งรุ่นเดียวกันบน 2–3 เครื่อง ปิด mobile data/ไม่เชื่อม AP เปิด Wi-Fi radio + Bluetooth แล้วส่งข้อความ/ภาพ/วิดีโอ/ตำแหน่งจริง เปิด/ปิด SOS/Rescue และตัดเครื่องกลางเพื่อดูคิว
- ทดสอบ session จริงเมื่อกลับมาออนไลน์ รวมอัปโหลด Storage และยุบ ID ซ้ำระหว่างช่องทาง การทดสอบจำลองกับ SQL ไม่แทนการทดสอบนี้
- รูป/วิดีโอออนไลน์ที่ยังไม่ได้ดาวน์โหลดจะเปิดออฟไลน์ไม่ได้ รุ่นนี้เพิ่ม cache เนื้อหาข้อความ inbox; การเก็บไฟล์ยังทำเมื่อรับ D2D หรือดาวน์โหลดสำเร็จในห้อง
- เปิด [Leaked Password Protection ใน Auth settings](https://supabase.com/dashboard/project/evfopzvqsngrunopxgvl/auth/security-and-protection) หากแผนบริการรองรับ เครื่องมือเชื่อมต่อในรอบนี้ไม่มีคำสั่งแก้การตั้งค่านี้
- ตัวตนวิทยุใช้การจับคู่และ key pinning แบบ trust-on-first-contact ไม่ใช่ใบรับรองบัญชี/บทบาทจากเซิร์ฟเวอร์ที่ตรวจสอบออฟไลน์ได้ การโจมตีด้วย client ที่ดัดแปลงให้แจ้ง userId/บทบาทปลอมยังต้องเพิ่ม signed server attestation ก่อนอ้างว่าป้องกันการปลอมตัวได้สมบูรณ์
- การตรวจครั้งนี้ไม่ใช่ penetration test หรือหลักฐานรับรองความปลอดภัยสำหรับงานกู้ภัยจริง

อ้างอิง [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) และ [การตรวจรหัสผ่านรั่วไหล](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
