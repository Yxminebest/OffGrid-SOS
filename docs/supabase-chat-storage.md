# ข้อมูลรูป วิดีโอ และตำแหน่งใน Supabase

ตำแหน่งต่อไปนี้ตรวจจากโค้ดของแอป ไม่ใช่การตรวจไฟล์จริงหรือสถานะการอัปโหลดใน live project รอบนี้

## แชทที่ซิงก์เข้าห้องสมาชิก

- Dashboard → Storage → chat-media: ไฟล์รูปและวิดีโอ เส้นทาง `<sender-user-id>/<conversation-id>/<message-id>/<ชื่อไฟล์ที่ปรับให้ปลอดภัย>`
- Dashboard → Table Editor → public.messages: metadata ได้แก่ `id`, `conversation_id`, `sender_id`, `type`, `content`, `media_path`, `media_name`, `media_mime`, `media_size` และเวลา (`message_type` เป็นชื่อฟิลด์ local DB; cloud ใช้ `type`)
- พิกัดแชทอยู่ใน `public.messages.latitude`, `longitude`, `accuracy` เมื่อ `type = location` ไม่ใช่ไฟล์ภาพแผนที่ ภาพแผนที่ตัวอย่างในแชทวาดจากแผนที่ภายในแอป
- อ้างอิงการเขียนจริง: lib/services/sync_service.dart → _syncMessage; การเปิดไฟล์: lib/services/chat_service.dart → signedMediaUrl

## สำรองประวัติ Nearby ส่วนตัว

- Storage → nearby-archive: ไฟล์รูป/วิดีโอที่สำรองจากประวัติ Nearby เส้นทาง `<owner-user-id>/<message-id>` อาจไม่มีนามสกุล
- Table Editor → public.nearby_archive: `owner_id`, `message_id`, `peer`, `incoming`, `delivery`, `envelope`, `media_path`, `revision`
- พิกัดอยู่ใน JSON `envelope.data.lat`, `lng`, `accuracy`, `recordedAt` ของข้อความชนิด location
- เป็นสำเนาประวัติของเจ้าของบัญชี ไม่ใช่ inbox ที่ทุกคนอ่านได้ สมาชิกห้องอ่าน chat-media ตาม RLS ส่วน nearby-archive จำกัดเฉพาะเจ้าของ

## SOS และโปรไฟล์

- พิกัด SOS ที่ซิงก์อยู่ใน public.sos_events: latitude, longitude, accuracy พร้อมข้อความและสถานะเหตุ
- รูปโปรไฟล์อยู่ใน Storage → avatars เอกสารขอสิทธิ์กู้ภัยอยู่ใน rescue-verification
- Guest/ข้อมูลที่ยังไม่ซิงก์จะอยู่ใน local DB และไฟล์ของแอปบนโทรศัพท์ จึงยังไม่ปรากฏใน Supabase การมีรูปบนหน้าจอไม่ได้ยืนยันว่าอัปโหลดสำเร็จ
- buckets ใช้สิทธิ์และ signed URL ตามโค้ด/SQL ใน repo ไม่ได้เปิด public URL ถาวร

## ตอบกลับ/แก้ไข/ยกเลิกในรุ่น 33

คำสั่งเป็น content แบบ versioned (`OFFGRID_CHAT_V1`) ในข้อความ text ที่มี ID ของตัวเอง เก็บในคิวเดิมทั้ง radio และ cloud เพื่อ retry และประมวลผลซ้ำได้ การตอบกลับเก็บ ID อ้างอิงและแสดงข้อความล่าสุดจากประวัติ ไม่คัดลอกข้อความเก่าลง quote อีกชุด คำสั่งไม่ปรากฏเป็น JSON บนหน้าจอรุ่นใหม่

การยกเลิกซ่อนเนื้อหาในแชทของรุ่นใหม่และยุติคิวเดิม เมื่อมี cloud message ของผู้ส่งแล้วจะเข้าคิวลบ messages/chat-media ตามระบบเดิม ไม่ใช่การรับรอง secure erase ของสำเนา Nearby archive, ไฟล์ที่ผู้รับบันทึกไว้, notification เก่า หรือ backup ของบริการ

## เมนู 4 รายการในรุ่น 41

ยกเลิกส่งข้อความ / ลบข้อความ / แก้ไขข้อความ / ตอบกลับ ใช้การเก็บคำสั่งใน `public.messages.content` เดียวกับวิทยุออฟไลน์ คำสั่งแต่ละรายการเป็นแถว `type = text` มี ID และ sender_id ของผู้เขียนเอง: `retract`, `delete`, `edit` และ `message` พร้อม target ID สำหรับการตอบกลับ แอปนำแถวเหล่านี้มาประกอบเป็นประวัติที่แสดงผล จึงไม่ควรตีความว่า edited_at/reply_to_id ของแถวต้นฉบับจะเปลี่ยนทุกครั้งที่ใช้คำสั่งจากหน้ารวมแชท

ลบข้อความหมายถึงนำกล่องข้อความที่ส่งเองออกจากแชททั้งสองฝั่ง ยกเลิกส่งคงกล่องยกเลิกไว้ ทั้งสองอย่างส่งคำสั่งควบคุมก่อนยุติคิวต้นฉบับ หากมี cloud record ของต้นฉบับแล้ว SyncService จะ DELETE แถวผู้ส่งใน public.messages และเรียก Storage remove ของ chat-media เดิมเมื่อมี media_path การลบไฟล์ที่ล้มเหลวอาจเหลือ orphan ตามกลไกเดิม ไม่ใช่การรับรองล้าง archive หรือสำเนาที่ส่งออกทั้งหมด

ตรวจ schema ใน repo: public.messages ใช้ type/content และ RLS จำกัด insert/update/delete ให้ sender_id = auth.uid() ภายในห้องที่เป็นสมาชิก คำสั่งทั้งหมดเป็น content text ที่ schema เดิมรับได้ ไม่จำเป็นต้องเพิ่มคอลัมน์หรือ role ใหม่ แอปยังตรวจ author ของข้อความเป้าหมายเมื่อประกอบประวัติ การตรวจนี้ไม่ใช่การยืนยัน RLS/schema ที่กำลังใช้บน live project ซึ่งต้องตรวจผ่านสิทธิ์เชื่อมต่อ Supabase จริงเพิ่มเติม
