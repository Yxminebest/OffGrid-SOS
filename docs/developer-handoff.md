# คู่มือส่งต่อผู้พัฒนา SOSBROO

เอกสารนี้อธิบายจุดสำคัญจากโค้ดรุ่น `0.10.15+46` เพื่อช่วยหาตำแหน่งแก้งานและรักษาพฤติกรรมออฟไลน์ คอมเมนต์ที่เพิ่มในรอบนี้อธิบายเงื่อนไขที่ต้องรักษา ไม่เปลี่ยนคำสั่งทำงานของแอป

## เริ่มอ่านจากเส้นทางใด

| งานที่จะทำต่อ | เส้นทางอ่าน | ชุดทดสอบที่เกี่ยวข้อง |
|---|---|---|
| เข้าสู่ระบบ/เปิดออฟไลน์ | `main.dart` → `AuthService.restoreIdentity` → `HomeShell._startServices` | `offline_regression_test.dart`, `sync_service_test.dart` |
| สร้าง/หยุด SOS | `SosRepository` → `SosLocationTracker` → `NearbyMeshService.publishSosRecord` | `offline_regression_test.dart`, `emergency_home_panel_test.dart`, `nearby_protocol_test.dart` |
| แชทช่องทางเดียว | `UnifiedChatService.send` → `_sendWire` → `_flushRadio` / `SyncService` | `unified_chat_test.dart`, `sync_service_test.dart` |
| จับคู่และเส้นทาง | `NearbyMeshService.start/startBluetooth` → `connect/approve` → `_receiveRoute/_sendTo` | `nearby_protocol_test.dart`, `mesh_router_test.dart` |
| ส่งรูป/วิดีโอ | `NearbyMediaTransfer` → `NearbyMediaFiles` → `NearbyChatRepository` | `nearby_media_test.dart` |
| ห้องส่วนกลาง | `sendRoom` → `MeshRouter` → `MeshRoom.save/project` | `mesh_router_test.dart`, `nearby_protocol_test.dart` |
| ยืนยันตัวตนออฟไลน์ | `MeshCrypto` → `MeshAttestation` → Edge Function `mesh-attestation` | `mesh_crypto_test.dart`, `nearby_protocol_test.dart` |
| แผนที่ | `BundledPathumMap` และ vector tile provider | `bundled_pathum_map_test.dart` |

ไฟล์ Dart ข้างต้นอยู่ใน `lib/` ตามโฟลเดอร์ features/services/data ส่วน tests อยู่ใน `test/`

## เงื่อนไขที่ต้องรักษา

### ข้อมูลในเครื่องและคิว

- `SosRepository._save` และ `MessageRepository._save` บันทึกข้อมูลกับคิวใน transaction เดียวกัน ห้ามแยกเป็นการเขียนคนละรอบ เพราะแอปอาจถูกปิดระหว่างสองขั้นตอน
- `SyncQueueRepository` ใช้ revision ตรวจว่างานที่ตอบกลับยังเป็นงานล่าสุด ถ้าผู้ใช้แก้ข้อความขณะ HTTP ค้าง ผลของ revision เก่าต้องไม่ลบหรือทำให้งานใหม่กลายเป็นสำเร็จ
- ใช้ ID ข้อความเดิมเมื่อข้าม Nearby/คลาวด์ เพื่อรวมประวัติและไม่ส่งซ้ำเป็นข้อความใหม่
- `MessageRepository.reconcileCloud` ใช้รายการที่ได้รับตรวจแถวที่หายไป จึงต้องส่ง snapshot ครบห้อง ห้ามเปลี่ยนผู้เรียกให้ส่งเพียงหนึ่งหน้าโดยไม่ปรับสัญญาการทำงานนี้
- `nearby_archive` เป็นสำเนาของเจ้าของบัญชี การกู้คืนตั้ง `historical: true` เพื่อไม่ส่งประวัติเดิมซ้ำถึงคู่สนทนา ส่วนประวัติห้องสาธารณะใช้ `MeshRoom` แยกจาก private chat

### บัญชีและงาน asynchronous

- `owner` ระบุบัญชีเจ้าของข้อมูล; device ID, endpoint และ cloud user ID เป็นคนละอย่าง ห้ามรวมผู้ติดต่อด้วยชื่อที่เหมือนกัน
- `_sessionGeneration` ยกเลิกผลของงานบัญชีเก่า ส่วน `_radioGeneration` ยกเลิก callback ของการเปิดวิทยุรอบเก่า ต้องคงการตรวจหลัง `await` ในเส้นทางที่มีอยู่
- การหมดอายุ session ออนไลน์ไม่เท่ากับผู้ใช้กดออกจากระบบ `AuthService.clear()` หยุดบริการก่อนล้างตัวตน ส่วนการคืนสมาชิกออฟไลน์ใช้ข้อมูลที่บันทึกไว้
- แชทที่ผูก cloud user แล้วเลือก peer ด้วยตัวตนที่ตรวจสอบได้ ไม่ใช้แค่ endpoint ที่เคยพบ

### การส่งและการตอบรับ

- `sent` หมายถึงส่งออกทาง transport แล้ว ส่วน `delivered` ต้องได้รับ ACK จากผู้รับ อย่าใช้สถานะซิงก์คลาวด์แทน ACK
- ข้อความส่วนตัวตอบ ACK หลังบันทึกลง DB และตอบซ้ำได้หาก ACK หาย ผู้ส่งจึง retry ได้โดยไม่สร้างข้อความซ้ำ
- ไฟล์แบ่งเป็นส่วนและจำกัดหน้าต่างรอ ACK ไว้ 4 ส่วน การรับส่วนที่มาถึงก่อนช่องว่างต้องยังไม่ ACK จนเขียนได้ต่อเนื่อง การจบไฟล์ต้องผ่านการตรวจ hash และบันทึกแถวก่อนยืนยัน
- `RadioSendQueue` เรียงงานแยก endpoint ให้ SOS/control แซงไฟล์ที่ยังรออยู่ แต่ไม่ตัดกลาง bytes ที่กำลังเขียน
- อย่ารอการส่งไฟล์จนจบใน receive loop ที่ต้องรับ ACK ของไฟล์นั้นเอง เพราะจะรอกันไม่สิ้นสุด
- Bluetooth native ใช้ JSON จบเฟรมด้วย LF และจำกัดเฟรม 32 KB ต้องคงให้ตรงกับ Dart handshake `SOSBROO_BT_APPROVAL_V1` ต้องตรงทั้งสองเครื่อง

### ลายเซ็นและประวัติแก้ไข

- `MeshCrypto.accept` ตรวจลายเซ็น certificate และ pin กุญแจอุปกรณ์ การรับ certificate ไม่เท่ากับตรวจว่าเป็นสมาชิกหรือกู้ภัย
- `MeshAttestation.verify` ตรวจ issuer ที่ฝังไว้ อายุใบรับรอง และการผูกบัญชี/อุปกรณ์/กุญแจ ก่อนใช้สิทธิ์กู้ภัยยังมีการพิสูจน์ possession ใน mesh service
- การจัดลำดับ key ที่ใช้เซ็น certificate ต้องสอดคล้องกับ Edge Function อย่าเปลี่ยน serialization โดยไม่วางแผนรองรับอุปกรณ์รุ่นเดิม
- `MeshRoom.save` ไม่ตรวจลายเซ็นเอง เส้นทางรับวิทยุตรวจใน callback `MeshRouter.validate` ส่วนการ restore archive เป็นอีกเส้นทางที่ต้องพิจารณาเมื่อแก้การรับข้อมูล
- การลบ/ยกเลิกเป็น event ที่เก็บไว้เพื่อให้เครื่องซึ่งกลับมาเชื่อมต่อภายหลังทราบการเปลี่ยนแปลง อย่าลบประวัติคำสั่งเพียงเพราะ UI ซ่อนข้อความแล้ว
- `MeshRouter` เก็บ packet ก่อนส่งให้ UI และ relay ใช้ TTL และ dedup จำกัดการวนซ้ำ อย่าสร้าง ID ใหม่ให้ packet เดิมทุกครั้งที่ retry

## สถานะที่ควรแจ้งผู้รับงาน

- รุ่นนี้ปิดการเชื่อมต่ออัตโนมัติ (`automaticConnections = false`) การเริ่มค้นหาไม่ใช่การอนุมัติลิงก์ ทั้ง Nearby และ Bluetooth ต้องมีขั้นตอนผู้ใช้ยอมรับ
- มี APK ในเครื่องรุ่น `0.10.15+46` แต่ผล GitHub Releases API วันที่ 11 พฤศจิกายน 2569 เป็นรายการว่าง ต้องเผยแพร่หรือแนบไฟล์ก่อนส่งลิงก์ติดตั้งสาธารณะ
- README รุ่นก่อนมีข้อมูล Guest/เส้นทางส่งเก่าปนอยู่ เอกสารบันทึกรุ่นใน `docs/` ยังใช้เป็นประวัติ ไม่ใช่ข้อกำหนดพฤติกรรมปัจจุบันทั้งหมด
- การอ่านและเพิ่มคอมเมนต์รอบนี้เน้นเส้นทางเริ่มแอป บัญชี คิว แชท วิทยุ ไฟล์ ใบรับรอง และ Android bridge ไม่ใช่การรับรองว่าอ่านครบทุกบรรทัดของทุกไฟล์ รวม UI ทั้งหมด tests และแพ็กเกจแผนที่ vendored
- ยังต้องเก็บผลทดสอบวิทยุจริงบนโทรศัพท์ 2–3 เครื่อง โดยเฉพาะพักหน้าจอ การเชื่อมต่อใหม่และการส่งต่อหลายทอด

## ตรวจงานก่อนเปลี่ยนพฤติกรรมในอนาคต

ผลตรวจการแก้เอกสาร/คอมเมนต์วันที่ 11 พฤศจิกายน 2569:

- เปรียบเทียบกับ Git HEAD: ซอร์ส 22 ไฟล์มีเฉพาะบรรทัด `//` เพิ่มเข้ามา บรรทัดเดิมทั้งหมดคงเดิม
- `git diff --check` ผ่าน และลิงก์ไฟล์ภายใน README ทั้ง 14 ลิงก์มีปลายทางอยู่จริง
- `flutter analyze --no-pub` ผ่าน: `No issues found!`
- ไม่ได้รัน unit/widget tests หรือ build APK ใหม่ในรอบเอกสารนี้ APK ที่ระบุเป็นไฟล์เดิมที่ตรวจ metadata และ SHA-256 แล้ว ไม่ใช่ผล build ใหม่

โฟลเดอร์ `test/` คงไว้ 10 ชุดทดสอบหลักตามตารางด้านบน; SQL checks ใน `supabase/tests/` ใช้ตรวจ backend แยกต่างหาก รัน `flutter analyze --no-pub` และชุดทดสอบที่ตรงกับเส้นทางที่แก้ หากเปลี่ยนโปรโตคอลให้ทดสอบทั้งสองฝั่งและระบุรุ่นที่เข้ากันได้ หากเปลี่ยน CSS ให้รัน `dart run tool/generate_styles.dart` แล้วตรวจ `--check` อีกครั้ง หากเปลี่ยนข้อมูลแผนที่ต้องสร้าง index/hash ให้ตรงกับ `tiles.pack` และรักษา license/attribution
