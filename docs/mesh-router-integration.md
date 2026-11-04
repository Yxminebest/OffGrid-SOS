# แกน offline mesh และการเชื่อมกับแชทเดิม

## ไฟล์ที่เพิ่ม

- `lib/models/mesh_packet.dart`: UUID, senderId, destinationId (`*` คือ broadcast),
  payload, timestamp UTC, ttl และ hopCount พร้อม JSON และ adapter envelope เดิม
- `lib/services/mesh/mesh_transport.dart`: interface และ MeshReception
- `lib/services/mesh/callback_mesh_transport.dart`: ต่อ callback radio ที่มีอยู่
- `lib/services/mesh/mesh_router.dart`: relay/คิว/การส่งให้ปลายทาง โดยไม่ import plugin radio
- `lib/services/mesh/mesh_dedup_cache.dart`: cache จำกัด 4096 ID อายุ 15 นาที
- `lib/services/mesh/mesh_router_store.dart`: memory store และคิว Sembast แยกบัญชี/โหนด
- `test/support/fake_mesh_transport.dart`: จำลองการเชื่อมต่อและ packet loss
- `test/mesh_router_test.dart`: topology, TTL, duplicate, retry, restart และ model/cache

ไฟล์เดิมที่ต่อยอด: `nearby_mesh_service.dart`, `mesh_crypto.dart`, `mesh_room.dart`,
`sync_service.dart`, `unified_chat_service.dart`, `sync_service_test.dart` และ
`mesh_room_ui_test.dart` ไม่เพิ่ม dependency และไม่เปลี่ยน schema ของ Supabase

## UI เดิม

ห้องส่วนกลางใช้ `NearbyMeshService.sendRoom(text)` และอ่าน
`mesh.room.watch(ownerId)` เหมือนเดิม จึงไม่ต้องแก้หน้าห้องแชท
ตอน initialize บัญชีจะสร้าง MeshRouter โดยใช้ CallbackMeshTransport
ที่ส่งผ่าน `_direct` ของ Nearby/Bluetooth เดิม peer เปลี่ยนจะเรียก updatePeers
และปลุกคิวโดยอัตโนมัติ รับ `kind: room` แล้วแปลง envelope เป็น MeshPacket
เพื่อให้ router รับผิดชอบ forwarding เพียงจุดเดียว

แชทส่วนตัวยังใช้ `UnifiedChatService.send(...)` และ routing แบบเข้ารหัสที่มีอยู่
เพื่อรักษา ACK, media chunks, route certificates และการยืนยันสมาชิก
ไม่ได้เปลี่ยนข้อความส่วนตัวให้เป็น broadcast ที่ทุกคนอ่านได้
หากจะใช้ router กลางกับ payload ส่วนตัว ต้องเข้ารหัสก่อนและติดตั้ง validate
ที่ตรวจผู้ส่ง/ปลายทางตามระบบกุญแจเดิม ห้ามต่อข้อความล้วนเข้ากับ radio โดยตรง

ตัวอย่างใช้แกน router กับ transport ที่แอปเตรียมไว้:

```dart
final router = MeshRouter(
  nodeId: myDeviceId,
  transport: transport, // implements MeshTransport
  store: LocalMeshRouterStore(localDatabase, '$ownerId:$myDeviceId'),
  validate: verifyPacket,
  onDeliver: saveToLocalInbox, // บันทึก UUID แบบ idempotent แล้ว UI watch DB
);
await router.start();
await router.send(MeshPacket.create(
  senderId: myDeviceId,
  destinationId: destinationDeviceId, // หรือ MeshPacket.broadcast
  payload: payload,
  timestamp: timeWhenUserPressedSend,
));
// ออกจากบัญชี: await router.close(); แล้วปิด transport
```

## กติกา TTL และคิว

ลด TTL และเพิ่ม hopCount ทุกครั้งที่ข้ามลิงก์ รวมการส่งครั้งแรก
TTL=0 ทิ้งก่อนส่งให้ UI, TTL=1 ส่งให้ปลายทางปัจจุบันได้แต่ไม่ relay ต่อ
ดังนั้น A→C→B ใช้ TTL เริ่มต้นอย่างน้อย 3 (ค่าเริ่มต้น model คือ 8)
การ retry สร้าง forwarded packet จากต้นฉบับเดิม ไม่ลดซ้ำหรือเติม TTL
inventory/history replay ก็ไม่ reset TTL

คิวเก็บทั้งข้อความที่ส่งแล้วและยังไม่ได้ส่ง เพื่อส่งไปยัง peer ใหม่เมื่อ topology
เปลี่ยน จดลิงก์ที่ส่งสำเร็จแล้ว ป้องกันส่งทุกเฟรมซ้ำทุก timer tick
ค่าเริ่มต้นเก็บ 1024 records อายุ 24 ชั่วโมงตามเวลารับของเครื่อง
คิวเต็มแจ้ง error ไม่ทิ้งข้อมูลเงียบ ๆ ปรับผ่าน constructor ได้
คิว persistent ยังกันซ้ำหลัง cache memory หมดอายุหรือ restart ภายใน retention
DB ประวัติของห้องส่วนกลางยังกันซ้ำด้วย UUID อีกชั้น
`onDeliver` ต้อง idempotent เพราะการปิด process ระหว่างบันทึก inbox และบันทึก
delivery marker อาจทำให้ callback ถูกเรียกใหม่หลังเปิดแอป

## Supabase และเวลาส่ง

แชทส่วนตัวยัง upsert `messages.created_at` ด้วยเวลาตอนส่งออฟไลน์เดิม
เพิ่ม createdAt ใน sendDirect/sendAttachment เพื่อไม่สร้างเวลาใหม่ตอน
UnifiedChatService นำคิว cloud/local ไปส่งผ่าน radio

ห้องส่วนกลางสำรองลงตาราง `nearby_archive` ที่มีอยู่ ใช้ unique key
`owner_id,message_id` และ RLS เดิม เวลาออฟไลน์อยู่ใน `envelope.at`
ไม่ใช้ `updated_at` ซึ่งเป็นเวลาอัปโหลดแทนเวลาส่ง การ retry ใช้ UUID เดิม
และทำเครื่องหมาย synced หลัง upsert สำเร็จเท่านั้น
การสำรองนี้แยกตามบัญชี ไม่ใช่ห้องทั่วโลกที่อ่านประวัติข้ามผู้ใช้จาก cloud

เทสต์ sync ใช้ SupabaseClient กับ HTTP server บน loopback ตรวจ offline→online,
HTTP 503→retry, timestamp เดิม และไม่อัปโหลดซ้ำหลังสำเร็จ
ไม่ได้เชื่อมฐานข้อมูล production หรือ deploy migration ในงานนี้

## ขอบเขต Android

ใช้ transport Nearby/Bluetooth ของโปรเจกต์เดิม Router ไม่ผูก plugin
Android/Google Play services เป็นผู้เลือก radio ของ Nearby;
ไม่ได้เพิ่ม native Wi-Fi Direct adapter แยก หรือรับประกัน Wi-Fi-only/IBSS
เปลี่ยน radio ได้ด้วย implementation ของ MeshTransport โดยไม่แก้ router
ยังต้องทดสอบ A—C—B บนอุปกรณ์จริงโดยตัดเส้นทาง A—B ก่อนยืนยันความเสถียร
เวลาส่งอ้างอิงนาฬิกาโทรศัพท์ของผู้ส่ง หากนาฬิกาคลาดเคลื่อน app ไม่สามารถ
อนุมานเวลามาตรฐานที่ถูกต้องได้เมื่อทุกเครื่องไม่มีอินเทอร์เน็ต
