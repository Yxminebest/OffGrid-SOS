# ก่อนเผยแพร่ Offgrid SOS รุ่น 31

รายการนี้แยกสิ่งที่ทำในโค้ดแล้วจากงานที่ต้องใช้เจ้าของแอป/ระบบจริง

## เตรียมในโค้ดแล้ว

- แชทข้อความ/รูป/วิดีโอ/พิกัดและ SOS ผ่าน radio ก่อนคลาวด์ พร้อม local queue
- ยืนยันรับ SOS และสถานะรับเคสที่ตรวจบทบาทได้ออฟไลน์ พร้อม replay/ACK/retry
- จัดลำดับ SOS ก่อนไฟล์ แยกคิวแต่ละ endpoint และ broadcast พร้อมกัน
- หน้าตรวจความพร้อมออฟไลน์และทางเข้า settings/จับคู่อุปกรณ์
- คอนฟิก private signing และ guard ที่ไม่ให้สร้าง AAB release ด้วย debug key
- 201 tests และ static analysis ผ่าน

## งานที่ต้องใช้ข้อมูล/บัญชีจริงก่อน public release

1. เจ้าของกำหนดชื่อผู้พัฒนา อีเมลสนับสนุน โดเมนนโยบายความเป็นส่วนตัว/ลบบัญชี และ package ID ถาวร อย่าเปลี่ยน package ID ของเครื่องทดสอบโดยไม่มีแผนย้ายข้อมูล
2. สร้างและเก็บ private upload key นอก Git; นำ android/key.properties.example ไปตั้งค่า android/key.properties จริง ห้าม commit secret จากนั้นสร้าง AAB ด้วย flutter build appbundle --release และตั้ง Play App Signing ใน Play Console ปัจจุบัน AAB จะตั้งใจถูกบล็อกหากไม่มี key ส่วน APK ทดสอบไม่ใช่ production-signed APK
3. เว็บไซต์นโยบาย/ลบบัญชีต้องเป็นช่องทางที่ใช้งานจริง มีผู้รับผิดชอบและข้อความตรงพฤติกรรมการส่ง SOS แชร์พิกัด relay สำรอง cloud และอายุเก็บข้อมูล มี privacy dialog ในแอปแล้วแต่ยังไม่ใช่การเปิดเว็บสาธารณะ กรอก Play Data safety ให้ตรง SDK/พฤติกรรม ไม่โฆษณาว่า local DB/cloud เป็น E2EE
4. ตรวจ Supabase live ด้วยผู้ใช้สองบัญชี: RLS/private storage, delete-account/mesh-attestation, expiration/revocation และกู้ประวัติ คงชุด SQL/Edge Functions ใน repository แต่รอบนี้ไม่ได้ deploy หรือทดสอบ production sessions
5. ติดตั้งรุ่นเดียวกันทุกเครื่องแล้วทดลองไม่มี data/ไม่มี router: ส่งข้อความ รูป วิดีโอ พิกัด SOS และรับเคส ทั้งสองเครื่องและ A-B-C ที่ A ติดต่อ C ตรงไม่ได้ ทดสอบ relay หายกลับมา/จอดับ/GPS ยังไม่ fix/storage เต็ม/สลับบัญชี/คลาวด์กลับมา
6. วัด latency, memory และแบตเตอรี่บน Samsung/OPPO/vivo กับ Android เก่า/ใหม่ รวม Doze/ผู้ผลิตจำกัดเบื้องหลัง ก่อนอ้างว่าใช้งานตลอดเวลา Android force-stop ยังหยุดรับได้ตามข้อจำกัดระบบ
7. โครงสร้าง zip/ELF 16 KB alignment ของ APK ทดสอบตรวจผ่านแล้ว (build/native-alignment-v31.log) ยังต้องทดลองรันในสภาพแวดล้อม 16 KB ทวน permissions/foreground-service declaration และ Play pre-launch report ภายใต้ build ที่เซ็นเผยแพร่จริง; ทวน attribution/licences แผนที่และ SDK
8. ซ้อมกับหน่วยกู้ภัย/อาสาในพื้นที่ กำหนดผู้รับผิดชอบเวรและขอบเขตพื้นที่ ก่อนเปิด beta เป็นเครือข่ายขอความช่วยเหลือใกล้เคียงที่มีคนรับจริง ไม่อ้างว่ามีศูนย์รับ SOS 24 ชั่วโมงหากยังไม่มี

ไฟล์และ logs: docs/release-v31.md, build/tests-v31.log, build/analyze-v31.log, build/signing-guard-v31.log, build/apk-v31.log
