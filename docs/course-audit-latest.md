# สถานะล่าสุดเทียบโจทย์ Off-Grid SOS & Nearby Share

ตรวจและเพิ่มโค้ด 18 ตุลาคม 2569 รุ่น **0.4.0+9**
รายงานนี้แทนการตรวจรุ่น 0.3.3+8; เอกสารรุ่นก่อนเป็นประวัติ

## ผลตรวจ

| รายการ | ผล |
|---|---|
| Flutter analyzer | ไม่พบ issues |
| Automated app tests | 91 ผ่าน |
| PostgreSQL จำลอง | Bootstrap + migration ซ้ำได้; 15 access/role/cascade checks ผ่าน |
| Backend จริง | ติดตั้ง 3 migrations + delete-account v5; SQL regression 32 assertions และ HTTP 4 checks ผ่าน; รอ session/app E2E |
| วิทยุจริง | ผู้ใช้เคยส่งข้อความสองเครื่องในรุ่นก่อน; รุ่น 9 ยังรอทดสอบ Galaxy/Y33s และ 3 โหนด |
| GitHub | รวม source รุ่น 9, tests, migrations และเอกสารในสาขา main; ตรวจ commit history สำหรับ revision ล่าสุด |
| APK | บิลด์/ตรวจลายเซ็นผ่าน; รายละเอียด/hash ที่ `release-v9.md`; ยังไม่ได้ติดตั้งบนโทรศัพท์ |
| Android package | คง com.example.offgrid_sos, API 24+, signing เดิมสำหรับอัปเดตเครื่องทดสอบ |

## เทียบข้อกำหนด

| ข้อกำหนด | โค้ดล่าสุด | หลักฐาน/สิ่งที่ต้องทดสอบจริง |
|---|---|---|
| D2D ไม่มี cellular/hotspot | Nearby P2P_CLUSTER / secure Bluetooth RFCOMM | เปิดวิทยุที่ใช้งาน แต่ไม่ต้องเชื่อม AP; รอ radio จริง |
| แชทข้อความ/รูป/วิดีโอออฟไลน์ | มีคิว Sembast, chunks 12 KiB, SHA-256, resume, durable files ≤25 MB | tests ข้อความ/สื่อ/ขาดช่วง/ส่งซ้ำผ่าน |
| กล้องโทรศัพท์ | เลือกกล้อง, กู้คืน Android lost result, stable message ID | ผู้ใช้ยืนยันกล้องรุ่นก่อน; regression ผ่าน |
| สมาชิก/ข้อมูล cloud | Auth/profile/roles, cloud chat/media, SOS sync | ติดตั้งและตรวจฐานข้อมูลจริงแล้ว; รอทดสอบ signup/email และ sync ด้วย session จากแอป |
| SOS toggle สีแดงบนเครื่องอื่น | มีประกาศ discovery และส่ง payload พร้อม revision หลังจับคู่ | discovery/parser/replay tests; รอวัด latency วิทยุ |
| กดสถานะ SOS เข้าแชท | Nearby แตะชื่อ/ปุ่มแชท, Rescue แตะการ์ดเข้าแชทโดยตรง | UI test ผ่าน; ปุ่มพิกัดยังแยกใช้ได้ |
| Rescue toggle สีน้ำเงินบนเครื่องอื่น | remote active card, discovery marker, replay/heartbeat และ off revision | service/UI tests; ทั้งหน้าคงธีมเหลือง |
| SOS ข้อความ+พิกัดเมื่อไม่มี Internet | บันทึกพิกัดล่าสุดพร้อมเวลา ส่งผ่านลิงก์จับคู่และ relay | tests ผ่าน; ถ้า GPS หาไม่ได้ใช้ last-known หรือระบุไม่มีพิกัด |
| คิว local แล้ว sync เมื่อออนไลน์ | cloud queue เดิม + Nearby private archive/สื่อ/backoff | HTTP tests ผ่าน; migration ติดตั้งบนโปรเจกต์จริงแล้ว; รอ app E2E |
| สถานะค้างส่ง/ส่งแล้ว/ซิงก์แล้ว | ส่งผ่าน transport, ACK รับถึง DB และสำรอง cloud แยกกัน | ไม่ใช้ cloud success แทน ACK ผู้รับ |
| Offline-first ฟีเจอร์หลัก | local histories/SOS/messages/media/queue | การสมัครบัญชีใหม่/ยืนยันอีเมลต้อง Internet; บัญชีเดิม/Guest ใช้ออฟไลน์ |
| เครือข่ายเป็นทอดๆ | route path จำกัด 6 ทอด, encrypted private frames, dedup, ACK, withdrawal/expiry | A–B–C text/image/video ผ่านจำลอง; **รอ 3 เครื่องจริง** |
| ทดสอบอย่างน้อยสองเครื่อง | ชุดทดสอบรวมและแบบบันทึกผลพร้อม | ยังต้องเก็บผลรุ่น 9 จริงตาม docs/testing-v9.md |

## ขอบเขตของระบบหลายทอด

เครื่องกลางต้องเปิดและมีลิงก์ต่อกันอยู่ การส่งไม่อาศัย Internet
เส้นทางใช้ signed discovery identity และ pin กุญแจแบบ trust on first contact
private payload ที่ผ่านตัวกลางเข้ารหัส X25519/AES-GCM ตัวกลางไม่เก็บข้อความไว้ในประวัติส่วนตัว
SOS/Rescue เป็นประกาศสาธารณะในเครือข่าย ไม่ใช่แชทส่วนตัว
ลิงก์โดยตรงใช้ช่องทางที่จับคู่ไว้ การรับรอง role บนเครื่องอื่นยังไม่ใช่ระบบ PKI ต่อต้านแอปปลอม
ยังไม่ใช่ DTN ที่เครื่องกลางเก็บข้อความไปส่งขณะผู้ส่งและเส้นทางทั้งหมดหายไป
คิวอยู่กับผู้ส่งและลองใหม่เมื่อกลับมาเชื่อมต่อ

## Backend และข้อมูลส่วนตัว

โปรเจกต์เดิมติดตั้ง 3 migrations แล้ว: hardening, Nearby archive และ private RPC wrappers
ไฟล์ใน `supabase/migrations/` ตรงกับ migration history บน server
`supabase/bootstrap.sql` ใช้สำหรับโปรเจกต์ใหม่เท่านั้น มี schema, RLS, member trigger,
chat RPC, admin rescue RPC, private Storage policies และ Realtime publication
Edge Function เดิมคง recent-auth check และเพิ่มล้าง bucket nearby-archive
รอบถัดมาติดตั้งและตรวจฐานข้อมูลจริงแล้ว ดู `supabase-deployment-2026-10-18.md`
ผลท้องถิ่นเดิมใช้ stubs; ผลจริงแยกเป็น SQL role/claims และ HTTP ที่ไม่ล็อกอิน ยังรอ session/app E2E
อ่านวิธีติดตั้งและตรวจ JWT A/B/anon ที่ `backend-setup.md`

Nearby archive เป็นประวัติส่วนตัวของสมาชิก ไม่ส่ง online ไปหาผู้รับแทน D2D
Guest ไม่อัปโหลดไปบัญชีอื่น การกู้คืนไม่เขียนทับคิว local ที่ยังไม่ส่ง และไม่ย้าย private keys
ประวัติจากเครื่องเดิมที่กู้คืนไม่ถูกส่งซ้ำในนาม identity ใหม่

## งานรายสัปดาห์

| สัปดาห์ | งานที่มี | หลักฐานที่ยังต้องเพิ่ม |
|---|---|---|
| 2 UX/UI | ปัญหา/กลุ่มเป้าหมาย/โฟลว์/Wireframe 5 หน้า, themes/logo/project folders | เอกสารจัดทำรอบนี้ ไม่อ้างส่งย้อนหลัง |
| 3 Vertical slice | Auth, SOS CRUD/local→queue→cloud, schema/RLS/RPC sources, error handling | ฐานข้อมูลจริงผ่าน 32 assertions/HTTP 4 จุด; รอ Auth/Storage จากแอปจริง |
| 4 Integrations | ข้อความ/สื่อ/กล้อง, in-app/foreground notifications, ค้นหา/กรอง | radio, permissions, background จริง |
| 5 Polish/Test | 91 automated cases, 15 SQL checks, accessibility/UI, bug log, manual matrix 23 เคส | TalkBack/Doze, ผล 2–3 เครื่อง |
| 6 Delivery | README, source, SQL/setup, APK, สคริปต์ demo 9 นาที | Backend deploy และจัด source ใน Git แล้ว; เหลือทดสอบเครื่องจริงและบันทึก manual demo |

## สิ่งที่ยังไม่อ้างว่าสำเร็จ

- แจ้งเตือนหลัง force-stop/reboot: foreground service ไม่ใช่ FCM; ต้องเปิดแอปอีกครั้ง
- Google Maps แบบออฟไลน์: ขึ้นกับแผนที่ในเครื่อง แต่พิกัด/เวลา/คัดลอกในแอปใช้ได้
- อายุแบตเตอรี่ ความเร็วรับส่ง และเวลาที่ discovery เปลี่ยนสี: ต้องวัดฮาร์ดแวร์จริง
- การเผยแพร่ production: APK ยังใช้ key/package เดิมของชุดทดสอบ ไม่เปลี่ยนเพื่อรักษาการอัปเดตและข้อมูลเดิม
- เกรด/ความครบถ้วนภาคปฏิบัติ: ยังต้องมีผลตาม checklist และการประเมินอาจารย์


## ข้อสรุปสำหรับเทียบโจทย์อาจารย์

ตอนนี้อยู่ช่วง Week 5 (Polish & Test) และเตรียม Week 6 (Final Delivery)
มี implementation หลักตามรายการ แต่ยังไม่ยืนยันว่าจบโจทย์พิเศษจนกว่าจะมีผลวิทยุจริง
อย่างน้อยสองเครื่อง และพิสูจน์หลายทอดด้วยสามเครื่อง
การแสดงสถานะ SOS/Rescue ก่อนจับคู่ใช้ discovery marker; ข้อความและพิกัดส่งหลังจับคู่
ยังไม่ได้วัดการปรากฏสถานะว่าเร็วเพียงใดบน Galaxy/Y33s
ตรวจเอกสารรอบนี้พบข้อความค้างที่ยังบอกว่าไม่ได้ deploy backend จึงปรับให้ตรงผลติดตั้งจริงแล้ว
