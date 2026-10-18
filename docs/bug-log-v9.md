# บันทึกแก้ไขรุ่น 9

| ปัญหา | การแก้ | หลักฐาน |
|---|---|---|
| private Nearby ส่งได้เพียงเครื่องติดกัน | signed route discovery, encrypted routed frames, ACK กลับตาม logical device | test A–B–C text/image/video |
| เส้นทางค้างเมื่อเครื่องตัวกลางหลุด | route withdrawal และหมดอายุ 40 วินาที + heartbeat ลิงก์ | protocol test |
| Rescue ไม่เห็นสีน้ำเงินบนอีกเครื่อง | remote active card, replay/heartbeat/revision และเปลี่ยนเป็น inactive ตอนหยุด | protocol + UI tests |
| SOS ต้องเปิดรายละเอียดก่อนคุย | แตะการ์ด/ชื่อ SOS เข้าแชท ปุ่มพิกัดแยก | UI test |
| ก่อนจับคู่มองไม่เห็น SOS/Rescue | discovery name มีสถานะสี; ไม่ประกาศข้อความ/พิกัดก่อนจับคู่ | protocol test; รอ Android จริง |
| Nearby ไม่สำรอง cloud | owner-private archive + private media + backoff + restore | HTTP integration + SQL RLS |
| อัปโหลดสำรองสื่อซ้ำเมื่อ metadata ไม่สำเร็จ | เก็บ archiveMediaPath และตรวจ schema ก่อนส่งไฟล์ | HTTP retry test |
| Wi-Fi ไม่มี Internet แต่แสดงออนไลน์ | ตรวจ health endpoint ของ cloud แทนสถานะ interface อย่างเดียว | network test |
| กล้องกู้คืนอาจสร้างข้อความซ้ำ | สร้าง ID ก่อนเปิดกล้อง และตรวจ ID ซ้ำแบบ transaction | camera/repository/media tests |
| ลบบัญชีเหลือไฟล์ media | หยุดงานเก่าแล้วล้าง owner-scoped files/keys/pending capture; Edge Function ล้าง bucket ใหม่ | file isolation + DB cascade tests |
| ลบหรือเปลี่ยนบัญชีระหว่าง restore | รอ restore จบ/ตรวจ owner ก่อนเขียน | session guards; รอ server จริง |

ผลรวม automated ปัจจุบัน 91 ผ่าน; analyzer ไม่มี issues; SQL QA 15 ผ่าน
ยังไม่อ้างว่าปิดบั๊กวิทยุจริง/Doze หรือ server production จนกว่าจะมีผลทดสอบ
