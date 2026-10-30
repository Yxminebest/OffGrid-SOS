# 0.8.2+20 — แก้ APK ขาด Supabase Publishable Key

## สาเหตุและการแก้ไข

รุ่น 19 ประกอบ APK โดยไม่ได้ส่ง SUPABASE_PUBLISHABLE_KEY ผ่าน dart-define ทำให้ main() เปิดหน้าขาดการตั้งค่าแทนแอป แม้ติดตั้งสำเร็จและ versionCode ถูกต้อง

- เพิ่มค่าเริ่มต้น public client key ที่ผู้ใช้ให้ สำหรับ URL โปรเจกต์เดิมใน SupabaseConfig
- ยังคง override ด้วย dart-define ได้ หากเปลี่ยน URL เป็นโปรเจกต์อื่นจะไม่ใช้ key เดิมโดยอัตโนมัติ
- ไม่เพิ่ม service-role key หรือ secret key และไม่แก้ schema/สิทธิ์บนเซิร์ฟเวอร์
- รวมการแก้หน้าหลักและจัดการบัญชีจากรุ่น 19 ทั้งหมด
- ตรวจ key กับ Auth health ของโปรเจกต์จริง: HTTP 200

การติดตั้งด้วย install -r เก็บข้อมูลเดิม ไม่ถอนการติดตั้งและไม่ล้างข้อมูล ผู้ใช้ขอแก้/ติดตั้งที่ OPPO ก่อน; ยังไม่อัปเดต Galaxy ในรอบนี้

## ผลตรวจรอบนี้

- Flutter analyzer: No issues found
- Release APK: `build/app/outputs/flutter-apk/Offgrid-SOS-v20-configured.apk`
- SHA-256: `2a636925764980b5fcea094d25f04cfb8a9569fe973c6fa0323668006731f0e4`
- ติดตั้ง OPPO A3s (efcf8833): Success และ dumpsys ยืนยัน versionName 0.8.2 / versionCode 20
- ส่งคำสั่งเปิด MainActivity แล้ว แต่ UIAutomator เก็บหน้าจอไม่ได้ (could not get idle state) จากนั้น USB หลุดก่อนเก็บภาพ จึงยังไม่มีหลักฐานภาพยืนยันหน้าเปิดแอป
- ภายหลังผู้ใช้ขออัปเดต Galaxy A03s (R9YR90PHTKZ): install -r Success และ dumpsys ยืนยัน versionName 0.8.2 / versionCode 20 แล้ว ส่งคำสั่งเปิดแอปได้ แต่เครื่องล็อกหน้าจอ (mDreamingLockscreen=true) จึงยังไม่ยืนยันภาพภายในแอป
- ไม่ได้ทดสอบฟังก์ชันทั้งหมด
