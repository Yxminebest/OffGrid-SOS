# ตรวจงาน Off-Grid SOS & Nearby Share เทียบโจทย์

> รายงานนี้เป็นประวัติรุ่น 4 อ่านสถานะปัจจุบันรุ่น **0.3.3+8** ที่ [course-audit-latest.md](course-audit-latest.md)

> อัปเดตหลังรายงานนี้: รุ่น **0.3.0+5** เพิ่มกล้องและการรับส่งรูป/วิดีโอออฟไลน์แล้ว
> GAP-01 มีโค้ดและ automated tests แล้ว แต่ยังรอทดสอบวิทยุจริง ดู [testing-v5.md](testing-v5.md)
> ตารางด้านล่างเก็บผลตรวจรุ่น 4 ไว้เป็นประวัติ; GAP-02 ถึง GAP-05 ยังเป็นงานค้าง

ตรวจวันที่ 18 ตุลาคม 2026 จาก working tree รุ่น **0.2.0+4** บน branch `main`
เอกสารนี้เป็นสถานะปัจจุบันแทนข้อสรุปก่อนรุ่น 4 ใน `readiness-2026-10-18.md`
รอบนี้ตรวจและปรับเอกสาร ยังไม่ได้เพิ่มฟีเจอร์หรือเปลี่ยน APK

## ข้อสรุป

มีต้นแบบ Android ที่ประกอบด้วยสมาชิก, SOS, แชทออนไลน์, แชทข้อความ Nearby/Bluetooth,
ฐานข้อมูลและคิวในเครื่อง, ธีมสว่าง/มืด และการแจ้งเตือนแล้ว
กำลังทำ Integrations และ Polish/Test แต่ **ยังไม่ครบโจทย์พิเศษ**
งานสำคัญที่ขาดคือรูป/วิดีโอออฟไลน์, แชทผ่านโหนดหลายทอด, สถานะกู้ภัยบนเครื่องอื่น
และการซิงก์ประวัติ Nearby ขึ้น cloud พร้อมสถานะเดียวกัน
ไม่ใช้จำนวน tests หรือการบิลด์ผ่านสรุปว่าทำงานครบหรือรับประกันเกรด A

## สถานะตามข้อกำหนด

คำว่า “มีโค้ด” หมายถึงพบเส้นทางการทำงานใน repository ไม่เท่ากับผ่านบนเครื่องจริง

| ข้อกำหนด | สถานะล่าสุด | หลักฐาน / สิ่งที่ยังต้องทำ |
|---|---|---|
| Smartphone-to-smartphone โดยไม่มี cellular/hotspot | มีโค้ด; รอยืนยันรุ่น 4 บนอุปกรณ์ | Nearby Connections P2P_CLUSTER และ Bluetooth RFCOMM; ไม่ต้องต่อ Wi-Fi hotspot แต่ต้องเปิดวิทยุที่ transport ใช้ |
| แชทข้อความออฟไลน์ | มีโค้ดและ tests | เก็บข้อความก่อนส่ง, acknowledgment, retry, ประวัติและ unread ในเครื่อง; ต้องทดสอบส่งไปกลับจริง |
| แชทรูปภาพ/วิดีโอออฟไลน์ | **ยังขาด** | มีตัวเลือกไฟล์และ upload ในแชท cloud แต่ Nearby รับส่ง text envelopes ไม่มี file transfer |
| สมาชิกและเก็บข้อมูล cloud เมื่อมี Internet | มีโค้ด; backend ยังไม่ยืนยัน | Supabase Auth, profile, roles, Storage, chat RPC; ไม่มี SQL/RLS/RPC/Edge Function sources ใน repo สำหรับตรวจหรือสร้าง backend ใหม่ |
| เปิด/ปิด SOS พร้อมข้อความและพิกัดล่าสุด | มีโค้ดและ tests | Local SOS, revision, replay การยกเลิก, แสดงเวลาพิกัดและเปิดแอปแผนที่ |
| สถานะ SOS สีแดงบนเครื่องใกล้เคียงทันที | บางส่วน | หน้า Nearby มีการ์ด SOS สีแดงหลังรับผ่านลิงก์ที่เชื่อมแล้ว; ไม่ใช่การประกาศถึงทุกเครื่องที่ยังไม่จับคู่ ต้องวัดเวลารับจริง |
| แตะสถานะ SOS เข้าแชท | **ยังไม่ตรง flow** | การ์ด SOS ใน Nearby ไม่มี onTap เข้าแชท; Rescue เปิดรายละเอียดก่อนแล้วมีปุ่มแชทอีกครั้ง |
| เปิด/ปิดหน่วยกู้ภัยและสถานะสีน้ำเงินบนเครื่องอื่น | **ยังไม่ครบ** | มี toggle และส่ง `rescue` แต่ Nearby ไม่แสดง rescue cards; `_announce()` ไม่ replay rescueActive ให้เครื่องที่เชื่อมทีหลัง |
| คิวในเครื่องและ sync เมื่อกลับออนไลน์ | บางส่วน | `SyncService` ทำ SOS และ cloud messages; `nearby_messages` แยกจากคิวนี้ จึงยังไม่ sync ประวัติ D2D ขึ้น cloud |
| UI ค้างส่ง/ส่งแล้ว/ซิงก์แล้ว | บางส่วน | Nearby มี pending/sent/delivered; cloud มี pending/synced/error แต่ยังไม่มีวงจรเดียวจาก Nearby ไป cloud |
| Offline-first ทุกฟีเจอร์หลัก | บางส่วน | SOS และข้อความมี local DB; รูป/วิดีโอที่รับจาก cloud ยังพึ่ง signed URL/network ไม่ได้เก็บไฟล์ถาวรทั้งหมดเพื่ออ่านออฟไลน์ |
| ติดต่อกันเป็นทอด ๆ ผ่านโหนด | **ยังขาดสำหรับแชท** | public SOS/rescue มี TTL relay; direct/case_chat ตั้งใจส่งเฉพาะลิงก์ตรง ไม่ relay รูปหรือข้อความส่วนตัว |
| ทดสอบอย่างน้อย 2 เครื่อง | มีหลักฐานรุ่นเก่าบางส่วน; รุ่น 4 รอทดสอบ | ภาพของผู้ใช้แสดง Galaxy กับ Y33s จับคู่/รับข้อความ/SOS ได้พร้อมบั๊ก; ยังไม่ใช่ผลรับรองรุ่น 4 |

การตรวจ multi-hop ต้องเพิ่มอย่างน้อยเครื่องที่สามหรือโหนดทดสอบที่ทำหน้าที่เทียบเท่า:
จัด A ↔ B ↔ C โดย A กับ C ไม่มีลิงก์ตรง แล้วพิสูจน์การส่งและรับตอบผ่าน B
การทดสอบจำลองสามโหนดที่มีอยู่ตรวจการแยกผู้รับ/ปฏิเสธ ack ปลอม ไม่ใช่หลักฐานว่า chat relay ทำงาน

## ประเด็นที่ต้องแก้เรียงตามผลต่อโจทย์

| ID | ระดับ | ปัญหาและผลกระทบ | ตำแหน่งโค้ด / เกณฑ์ปิดงาน |
|---|---|---|---|
| GAP-01 | สูง | ไม่มีรูป/วิดีโอผ่าน Nearby หรือ Bluetooth | `nearby_mesh_service.dart`, `BluetoothLink.kt`, `nearby_conversation_screen.dart`; ต้องมีไฟล์ใน local storage, transfer/chunks, ตรวจความครบถ้วน, retry และเปิดไฟล์ที่รับเมื่อออฟไลน์ได้ |
| GAP-02 | สูง | A ติดต่อ C ผ่าน B ทางแชทไม่ได้ แม้ SOS จะ relay ได้ | `NearbyMeshService.handleEnvelope()` ปฏิเสธ origin ที่ไม่ตรง peer ของลิงก์สำหรับ direct/case_chat; ต้องออกแบบ routing, dedup/TTL, ack และการปกป้องข้อความก่อนส่งผ่านตัวกลาง |
| GAP-03 | สูง | ไม่เห็นหน่วยกู้ภัยสีน้ำเงินและพลาดสถานะเมื่อเชื่อมภายหลัง | `NearbyScreen`, `NearbyMeshService._announce()`/`setRescue()`; ต้องแสดงสถานะล่าสุดและทดสอบเปิด/ปิด/เชื่อมใหม่ |
| GAP-04 | สูง | ข้อความ Nearby ไม่ได้ไป cloud และไม่มีสถานะ synced | `NearbyChatRepository`, `SyncService._process()`; ต้องกำหนด identity/สิทธิ์ของห้อง, stable message ID และ sync ไม่ซ้ำ โดยไม่ส่งข้อมูลข้ามบัญชี |
| GAP-05 | กลาง | แตะ SOS ยังไม่เข้าสนทนาทันทีตามโจทย์ | `NearbyScreen`, `RescueScreen.showCase()`; แตะการ์ดต้องเข้าห้องผู้แจ้ง/เคสที่ถูกต้อง และเปิดแผนที่แยกได้ |
| BUG-01 | กลาง | ตัวตรวจ online วัดแค่ว่ามี interface จึงอาจบอก online ทั้งที่ Wi-Fi ไม่มี Internet | `NetworkService._isConnected()`; แยกสถานะวิทยุ/การเข้าถึง cloud และทดสอบ Wi-Fi ที่ไม่มีทางออก Internet |
| BUG-02 | ต่ำ | ข้อความในรายละเอียด Rescue ยังบอกว่าแชทไม่เก็บถาวร ทั้งที่ห้องจริงใช้ durable repository แล้ว | `RescueScreen.showCase()`; ปรับคำอธิบายให้ตรงกับพฤติกรรมและข้อจำกัดการ sync |
| VERIFY-01 | สูง | ยังไม่ยืนยัน notifications/วิทยุจริงของรุ่น 4 | native service/shared engine มีโค้ด แต่ต้องเก็บผล Home, จอดับ, swipe Activity, ปิดสิทธิ์ ทั้งสองรุ่น; ไม่มี FCM และรับต่อไม่ได้หลัง Force stop/โปรเซสถูกฆ่า |
| VERIFY-02 | สูง | ตรวจสิทธิ์ backend และความครบของข้อมูลบน Supabase ไม่ได้จากโค้ด client เพียงอย่างเดียว | ต้องเก็บ schema/migrations/RLS/RPC/Storage policies/Edge Functions และทดสอบข้ามบัญชีด้วยข้อมูลทดสอบ |

รายการนี้เป็นผลตรวจที่พบ ไม่ใช่การรับรองว่าไม่มีบั๊กอื่น
การส่ง SOS สาธารณะมีพิกัด จึงต้องอธิบายให้ผู้ใช้ทราบว่าข้อมูลจะถูกกระจายไปยังโหนดที่เกี่ยวข้อง
อย่าแก้ multi-hop โดยกระจายข้อความส่วนตัวแบบอ่านได้ให้ทุก peer

## สถานะรายสัปดาห์

| สัปดาห์ / กำหนด | มีแล้ว | สิ่งที่ยังขาดหลักฐานหรือยังต้องทำ |
|---|---|---|
| Week 2 — 30 ก.ย. 2569 | Flutter project, โครงสร้าง feature/service/data, UI จริง, ธีมเหลือง/ดำและครีม/เหลือง, โลโก้ SOS | ไม่พบเอกสารปัญหา/กลุ่มเป้าหมาย/flow และ wireframe 3–5 หน้าสำหรับส่งอย่างชัดเจน; screenshot UI ไม่เท่ากับ wireframe |
| Week 3 — 7 ต.ค. 2569 | Auth, SOS CRUD, local DB, queue, cloud sync, error handling และ tests ของ race/retry | schema อยู่ในรูป client model แต่ไม่มี migrations/backend definitions; ต้องยืนยัน CRUD ตั้งแต่ UI ถึง Supabase จริง |
| Week 4 — 14 ต.ค. 2569 | cloud chat/attachments, ค้นหาผู้ใช้, Nearby text, unread, notification implementation | ต้องปิด GAP-01 ถึง GAP-05 และทดสอบ integration จริง; โจทย์รายสัปดาห์ยอมรับ in-app หรือ push จึงไม่จำเป็นต้องเพิ่ม FCM เพียงเพื่อให้มีคำว่า push |
| Week 5 — 21 ต.ค. 2569 | tests อัตโนมัติ 51 รายการ, ธีม/ตัวอักษรใหญ่/จอเล็ก, bug list และคู่มือทดสอบ | เก็บผลทดสอบบน Galaxy/Y33s, TalkBack/การโฟกัส/พื้นที่กดจริง, network transitions และ retest บั๊กที่ผู้ใช้พบ |
| Week 6 — ภายใน 4 พ.ย. 2569 | README, Git remote, APK สำหรับทดสอบ | commit/push งานล่าสุด, source backend ที่สร้างซ้ำได้, release signing ที่เก็บกุญแจอย่างเหมาะสม, test evidence และบท demo สด 7–10 นาที |

## ผลตรวจและข้อจำกัดของหลักฐาน

- `flutter test --no-pub --reporter expanded`: **ผ่าน 51 รายการ** ในรอบตรวจนี้
- `flutter analyze --no-pub`: **ผ่าน ไม่พบ issues** ในรอบตรวจนี้
- `git diff --check`: ผ่าน ไม่มี whitespace errors; มีคำเตือน LF/CRLF ของ Git
- ไม่ได้บิลด์ใหม่ในรอบนี้ เพราะไม่มีการเปลี่ยนพฤติกรรมแอป; APK รุ่น 4 ที่มีอยู่ขนาด 58,941,889 bytes
- APK: `build/app/outputs/flutter-apk/Offgrid-SOS-v4-yellow.apk`, versionName 0.2.0 / versionCode 4
- `android/app/build.gradle.kts` ยังใช้ applicationId `com.example.offgrid_sos` และ release signing ด้วย debug key
- Tests ใช้ DB/transport/platform/server จำลองบางส่วน ไม่พิสูจน์ radio, battery policy หรือ backend จริง
- ภาพทดสอบรุ่นก่อนของผู้ใช้เป็นหลักฐานการใช้งานจริงบางเส้นทาง แต่ผลทดสอบรุ่น 4 ยังต้องบันทึกตาม `testing-v4.md`

## Git และไฟล์ส่งงาน

remote ที่ตั้งไว้: https://github.com/Yxminebest/OffGrid-SOS
HEAD ในคอมพิวเตอร์: `e3e67e8` — `Update Week 3 CRUD Auth Sync and Schema`
มีไฟล์แก้ไขและ untracked จำนวนมาก รวม `android/`, `assets/`, `test/`, `docs/`
และบริการ Nearby/Bluetooth/notifications ใหม่ จึงยังไม่ใช่งานที่รวมอยู่ใน commit นี้
ไม่ได้ fetch/push หรือยืนยันเนื้อหา remote ในรอบนี้; commit title ไม่ใช่หลักฐานว่า schema ครบ
ห้ามอ้างว่าเปิด GitHub แล้วจะได้โค้ดรุ่น 4 ครบจนกว่าจะตรวจและ commit/push งานเหล่านี้

## ลำดับงานถัดไปและเกณฑ์พร้อมส่ง

1. จัด flow สถานะ SOS/Rescue ให้ตรงโจทย์ รวม replay เมื่อเชื่อมใหม่และเข้าแชทจาก SOS
2. ทำไฟล์รูป/วิดีโอออฟไลน์พร้อม local storage และทดสอบส่งไฟล์จริงทั้งสองเครื่อง
3. ทำ chat routing ผ่านโหนดโดยปกป้องข้อความ และทดสอบ A ↔ B ↔ C ที่ไม่มีลิงก์ A ↔ C
4. เชื่อม Nearby history เข้าคิว cloud และรวมสถานะ pending/sent/synced พร้อมตรวจสิทธิ์ backend
5. บันทึกผลทดสอบจริงตามคู่มือ โดยเฉพาะปิด Internet, ปิด Wi-Fi ใช้ Bluetooth, หลุด/เชื่อมใหม่ และ notifications
6. รวบรวมเอกสาร Week 2/schema/test log, commit/push source และจัด demo 7–10 นาทีให้แสดงเส้นทางที่พิสูจน์แล้ว

เกณฑ์ปิดงาน: ทุกข้อในตารางข้อกำหนดมีหลักฐานทดสอบและเอกสารส่งงานครบ
หากรายการใดยังทำไม่ได้ ให้แสดงเป็นข้อจำกัดในการ demo และ README อย่างตรงไปตรงมา
