# SOSBROO 0.10.13+44 — แตะแจ้งเตือนเข้าห้องแชท

## สาเหตุและการแก้

เดิม Flutter ส่ง thread ไปใน showMessage แต่ MainActivity ไม่ส่งต่อให้ Notifications.show และ PendingIntent มีเฉพาะข้อมูล SOS การแตะแจ้งเตือนข้อความทั่วไปจึงเปิดแอปโดยไม่มีห้องเป้าหมาย

- แนบ owner, thread และ transport ให้แจ้งเตือนข้อความ cloud / Nearby รวมแจ้งเตือนรูปและวิดีโอ
- PendingIntent ใช้ action ที่แยกตาม owner/message ID เพื่อไม่ให้เป้าหมายของแจ้งเตือนหลายห้องสลับกัน โดยไม่เพิ่ม data URI ที่อาจรบกวน auth deep link ของ Flutter
- MainActivity เก็บ pendingChatTap จาก onCreate/onNewIntent และ consume ผ่าน takeChatTap ครั้งเดียว เพิ่ม notificationTap event ให้ Flutter ตอบสนองตอนแอปอยู่หน้าจอแล้วโดยไม่ต้องรอ lifecycle resume
- HomeShell รอ mesh/local session พร้อมและรอขั้นตอนกลับหน้าหลักหลังพักจอก่อนนำทาง เก็บ payload ที่ consume แล้วไว้ระหว่างเปลี่ยน lifecycle ไม่เปิดห้องซ้ำเมื่อห้องนั้นเปิดอยู่แล้ว
- ค้นหาห้องจาก inbox ที่บันทึกในเครื่อง แยก device ID ของ Nearby จาก conversation ID ของ cloud ไม่ใช้อินเทอร์เน็ตเพื่อ resolve ห้องที่ cache แล้ว ตรวจ owner ก่อน/หลัง await ปฏิเสธเป้าหมายข้ามบัญชีหรือ ID ที่ไม่มีในประวัติ
- ถ้าเคยรวม radio identity เข้ากับ cloud contact ใช้ binding ที่ verified เพื่อหาห้องเดียวกัน ไม่รวมผู้ใช้จากชื่อแสดงผล
- หากห้อง/ผู้ติดต่อถูกลบหรือหาไม่พบ จะเปิดแท็บแชทแทนเปิดห้องที่ไม่รู้จัก
- ใช้ token ของ route เพื่อไม่ให้ dispose ของห้องเก่าล้าง activeThread/alias ของห้องใหม่ขณะนำทางจากแจ้งเตือน
- เส้นทางแจ้งเตือน SOS เดิมยังเปิดห้องผู้ขอความช่วยเหลือได้ และการเปิดเสียง/รับเบื้องหลังใช้การตั้งค่าเดิม

## ผลตรวจ

- สคริปต์ CSS generator → flutter analyze ไม่พบปัญหา → APK release สำเร็จ — build/build-v44.log
- flutter test --no-pub: 263 เคสผ่าน — build/tests-v44.log
- เทสเฉพาะ notification / inbox / radio: 70 เคสผ่าน — build/targeted-v44.log (ก่อนเพิ่ม regression การเปลี่ยน route ซึ่งผ่านในชุดเต็ม)
- ตรวจ payload owner/thread/transport, consume tap ครั้งเดียว และส่ง native notificationTap event ผ่าน platform channel ขณะ foreground
- ตรวจค้นหาห้อง cloud จาก cache เมื่อไม่มีอินเทอร์เน็ต และห้อง radio หลังลิงก์หลุด พร้อมปฏิเสธอีกบัญชี/namespace ผิด/ผู้ติดต่อไม่รู้จัก
- ตรวจ pushReplacement เปลี่ยนห้องแล้ว dispose ห้องเดิมไม่ล้างเป้าหมายแจ้งเตือนใหม่
- ไม่ได้แก้ schema หรือข้อมูล Supabase จริง การเพิ่ม metadata แจ้งเตือนเป็นการแก้ภายในแอป

## ทดสอบบนโทรศัพท์

รอบนี้ยังไม่ได้ทดลองแตะ Android notification จริงบนโทรศัพท์ ผลเทสครอบคลุม Dart/platform channel จำลองและการ compile native ผ่าน APK

หลังอัปเดตให้ส่งข้อความใหม่เพื่อสร้างแจ้งเตือนรุ่นนี้ แจ้งเตือนที่สร้างโดยรุ่นเก่าอาจไม่มีรหัสห้องและยังเปิดได้เพียงแอป ทดสอบทั้งข้อความ/รูป/วิดีโอ, สองห้องแจ้งเตือนพร้อมกัน, เปิดจากพักหน้าจอ, แตะขณะเปิดแอปหน้าอื่น และเปิดหลัง Activity ถูกสร้างใหม่ หากระบบปิดบริการจนข้อความยังไม่ถึงเครื่อง จะไม่มีแจ้งเตือนให้แตะจนกว่าจะรับข้อความได้

## APK

build/app/outputs/flutter-apk/SOSBROO-v44.apk — versionName 0.10.13, versionCode 44 คง package ID และข้อมูลเดิมสำหรับอัปเดตทับ ยังไม่ได้ติดตั้งลงโทรศัพท์ในรอบนี้

ตรวจ manifest ชื่อ/เวอร์ชันตรง และ zipalign -c -P 16 4 ผ่าน

SHA-256: 934AE6F1BE9A1EBC992AB2B820D9B30D8282547C1E7A2A33AAAF6CD44D2D285D
