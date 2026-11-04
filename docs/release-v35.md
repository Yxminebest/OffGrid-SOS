# SOSBROO 0.10.4+35

## สิ่งที่เปลี่ยนตามภาพ

- นำ GuestScreen, AuthService.createGuest, AppRole.guest และเส้นทาง restore Guest ออก ตัวตน Guest รุ่นเก่าจะไม่เปิด session ในแอปได้อีก ไม่ได้แปลง Guest ให้เป็นสมาชิกหรือให้สิทธิ์กู้ภัยอัตโนมัติ
- สมาชิกที่เคยลงชื่อเข้าใช้แล้วเปิดจากข้อมูลในเครื่องได้แม้ไม่มีอินเทอร์เน็ต การสมัคร/เข้าสู่ระบบครั้งแรกยังต้องใช้อินเทอร์เน็ต แชทและ SOS ผ่าน Bluetooth/Nearby ยังอยู่ครบ
- หน้าหลักเอาข้อความ “เชื่อมต่อผ่าน Bluetooth และ Wi-Fi” ออก โปรไฟล์เอาคำอธิบายใต้หัวข้อโปรไฟล์ รูปแบบการแสดงผล และจัดการบัญชีตามภาพออก
- หน้าเข้าสู่ระบบเอาปุ่มธีม คำโปรยและคำอธิบายที่วงไว้ รวม Guest entry และข้อความด้านล่างออก ลบคลาสปุ่มธีมเก่าที่ไม่มีผู้ใช้งานแล้ว ยังคงตัวเลือกสว่าง/มืดในโปรไฟล์
- คำขอ SOS หน้าแรกเป็นพื้นแดงและตัวหนังสือ/ไอคอนขาว รายชื่อเครื่องที่ประกาศ SOS หรือมีคำขอ SOS ปัจจุบันใช้สีแดง กู้ภัยที่มีสิทธิ์และเปิดปฏิบัติหน้าที่ยังคงสีน้ำเงิน ส่วนรายละเอียดเคสมีขอบแดงและพื้นแดงอ่อน
- เปลี่ยนชื่อแสดงผลเป็น SOSBROO ที่ Android launcher, iOS, web, macOS, ในแอป และแจ้งเตือนรับข้อความเบื้องหลัง
- คง package ID, deep link, database name และ radio protocol identifiers เดิม เพื่อไม่ให้การเปลี่ยนชื่อทำข้อมูลเดิมหรือการติดต่อกับรุ่นเดิมขาดหาย

## Supabase

ตรวจ implementation เดิมแล้ว createGuest เขียน FlutterSecureStorage ในเครื่องเท่านั้น ไม่เรียก Supabase signup หรือ anonymous signup ส่วน schema ที่อยู่ใน repo กำหนด user_roles.role เป็น user/rescuer/admin ไม่มี Guest และ mesh-attestation ปฏิเสธ anonymous Auth อยู่แล้ว จึงไม่มี migration สำหรับลบ Guest role จาก schema ชุดนี้

รอบนี้ไม่มี Supabase connector สำหรับตรวจฐานข้อมูลจริง และ browser tool แจ้งว่า Local browser use is disabled in Work settings จึงยังไม่ได้ยืนยัน anonymous users หรือข้อมูลที่อาจถูกสร้างจากภายนอกแอปในโปรเจกต์จริง และไม่ได้ลบข้อมูลจริงบน Supabase ห้ามตีความรายงานนี้ว่าได้ตรวจหรือลบบัญชีบนคลาวด์แล้ว

## ตรวจจริง

- flutter analyze --no-pub: No issues found — build/analyze-v35.log
- flutter test --no-pub: 229 เคสผ่าน — build/tests-v35.log
- แทนเทส Guest creation ด้วยการตรวจว่า Guest cache เดิมไม่ restore และตรวจหน้า login ไม่มี Guest entry/ปุ่มธีม มีชื่อ SOSBROO; เทสสมาชิก cached เปิดออฟไลน์ยังผ่าน
- เทส UI ตรวจพื้นสีแดงและตัวหนังสือขาวของผู้ส่ง SOS พร้อมสีฟ้าของหน่วยกู้ภัย และการแตะคำขอเพื่อเปิดแชท
- เก็บภาพ review ด้วย CAPTURE_UI: build/ui-previews/login_light.png, login_dark.png และภาพหน้าอื่นจาก appearance_ui_test; ตรวจภาพหน้า login แล้ว
- ยังไม่ได้ติดตั้งหรือทดสอบวิทยุจริงบนโทรศัพท์ในรอบนี้

## APK

- build/app/outputs/flutter-apk/SOSBROO-v35.apk ประกอบ release สำเร็จ — build/apk-v35.log
- ตรวจ manifest ใน APK: label SOSBROO, versionName 0.10.4, versionCode 35
- zipalign -c -P 16 4 ผ่าน
- SHA-256: 37D64322DAE9EEA3F0C5C7C330E1B1ADE7BFC96984AA1AF59511DD2E486397AC
