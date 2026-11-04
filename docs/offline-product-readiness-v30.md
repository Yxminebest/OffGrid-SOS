# เปรียบเทียบผลิตภัณฑ์และความพร้อมเผยแพร่ — Offgrid SOS 0.9.9+30

ตรวจวันที่ 2 พฤศจิกายน 2569 จากโค้ดใน repository และเอกสารผลิตภัณฑ์ทางการ ไม่ได้ติดตั้งคู่แข่งทดลอง และไม่ได้ทดสอบวิทยุจริงหรือ backend live เพิ่มในรอบนี้

## สิ่งที่ควรเรียนรู้จากผลิตภัณฑ์อื่น

| ผลิตภัณฑ์ | พฤติกรรมตามเอกสารทางการ | สิ่งที่นำมาใช้กับ Offgrid SOS |
|---|---|---|
| Briar | ซิงก์ระหว่างเครื่องผ่าน Bluetooth/Wi-Fi เมื่อไม่มีเน็ต มีการจัดการตัวตน/ผู้ติดต่อ; private messages ใน quick start ส่งตรงระหว่างต้นทางและปลายทาง | offline identity ที่ไม่พึ่ง cloud, การเตรียมเครื่องและ pairing ที่เข้าใจง่าย และอธิบายขอบเขต relay ตามชนิดข้อความ |
| Bridgefy | แอป Bluetooth mesh ส่งผ่านโทรศัพท์ผู้ใช้อื่นที่อยู่ระหว่างทาง; ระยะ 100m เป็นคำอธิบายผลิตภัณฑ์ของผู้ผลิต ไม่ใช่ค่ารับประกันของแอปเรา | ผู้ใช้เห็นคนใกล้เคียงและเริ่มสื่อสารได้ง่าย พร้อมระบุว่าต้องมีเครื่องกลางจึงขยายเครือข่ายได้ |
| Garmin inReach/Response | SOS มีการสื่อสารตอบกลับ ประสานหน่วยงานและอัปเดตต่อเนื่อง เป็นผลิตภัณฑ์ satellite ที่มีศูนย์ตอบรับ | นำ workflow รับทราบ/รับเคส/อัปเดตสถานะมาใช้กับผู้กู้ภัยในเครือข่ายของเรา ไม่อ้างว่าแอปเรามีดาวเทียมหรือศูนย์ 24 ชั่วโมง |

แหล่งข้อมูล: https://briarproject.org/how-it-works/ , https://briarproject.org/quick-start/ , https://bridgefy.me/ , https://support.garmin.com/en-AU/aviation/faq/dENvi0yoo51ib0Zh8L4El6/ , https://www.garmin.com/en-GB/satellite-communicators/interactive-sos-and-garmin-response/

## ข้อสรุปความพร้อม

แอปมี implementation และ automated tests สำหรับ offline chat/SOS แต่ยังเหมาะกับการทดลองภาคสนามแบบควบคุมมากกว่าประกาศเป็นระบบกู้ภัยที่พร้อมรับประกันบริการสาธารณะ 192 tests ผ่านไม่ใช่หลักฐานความเร็ว/แบตเตอรี่/codec/OEM background lifecycle และยังไม่มีผลรุ่นล่าสุดแบบ 3 เครื่องที่แยก A ออกจาก C จริง

## ต้องทำก่อนเผยแพร่สำหรับงานฉุกเฉิน

### 1. การยืนยัน SOS สองระดับ

ปัจจุบัน publishSosRecord ส่ง SOS ผ่าน _broadcast ซึ่งนับส่งสำเร็จระดับ transport แต่ยังไม่มี durable receipt รายเครื่องเหมือนแชท ต้องเพิ่ม signed sos_receipt ที่อ้าง caseId+revision และเก็บใน local DB ทั้งคู่ แยก “เครื่องปลายทางได้รับแล้ว” จาก “เจ้าหน้าที่รับเคส” โดยชัดเจน

เสนอ flow: ค้างส่ง → เครื่องใกล้เคียงได้รับ → หน่วยกู้ภัยรับเคส → กำลังช่วยเหลือ → ปิดเคส พร้อมผู้รับ เวลา และปุ่มคุยต่อ มี revision/ผู้มีสิทธิ์เปลี่ยนสถานะ ไม่ให้ ACK เก่าปิดเคสใหม่ และแสดงผู้รับหลายคนได้

### 2. คิว SOS มาก่อนไฟล์

แม้ frame มีขนาดจำกัดและ private media ทำงาน async แต่ยังไม่มี scheduler ระดับ transport ที่จัดลำดับความสำคัญชัดเจน ควรมีคิวควบคุม SOS/receipt/cancel ก่อนข้อความและก่อน media chunk, จำกัดจำนวนไฟล์พร้อมกันและหน่วยความจำ, แสดงขนาด/ยกเลิก/ส่งต่อ, เสนอส่งวิดีโอเป็นรูปเมื่อจำเป็น การแก้ล่าสุดลด sync storm แล้ว แต่ยังไม่มี latency profile ยืนยัน

### 3. ทนต่อการเคลื่อนที่และเครื่องกลางหาย

route ปัจจุบันเป็น mesh ที่อาศัยเส้นทางกำลังเชื่อมและ TTL/hop bounded ไม่ใช่ durable store-carry-forward สำหรับ private relay ทุกกรณี เมื่อ B รับไว้แล้ว A หายและ C มาในภายหลัง ต้องออกแบบ encrypted envelope queue บน B แบบมีวันหมดอายุ quota dedup acknowledgment และเงื่อนไขความยินยอม จึงจะอ้างการนำข้อความติดตัวไปส่งต่อเมื่อเคลื่อนที่ได้

### 4. เริ่มใช้ออฟไลน์ง่ายและรู้ว่าพร้อมหรือยัง

มี guest และ resume transport แล้ว แต่ RFCOMM fallback ใช้ bonded devices ยังต้องตั้งค่าจับคู่ใน Android ควรมีขั้นตอนเตรียมครั้งแรกในแอป แสดงสิทธิ์ Bluetooth/ตำแหน่ง/notification สั้น ๆ ตรวจวิทยุและทดสอบกับอีกเครื่อง โดยไม่บังคับล็อกอินหรือรอ backend ก่อนใช้ SOS คงหลักฐานตัวตนและไม่ auto-trust บทบาทจากชื่อ

### 5. พิกัดและแผนที่ใช้จริง

คงส่ง SOS ก่อนเมื่อไม่มี fix แล้วตามด้วยตำแหน่งเมื่อ GPS มา แสดงอายุ+accuracy และเปิดให้ผู้ใช้วางหมุดเองโดยระบุ “ผู้ใช้ระบุตำแหน่ง” เพิ่มชั้นที่อยู่/ชั้นอาคาร/จุดสังเกตในฟอร์มสั้น ไม่อ้างแม่นยำจากค่า GPS ที่ยังหยาบ ระยะที่คำนวณจากพิกัดต้องระบุระยะเส้นตรง ไม่ใช่ระยะเดินทางจริง แผนที่ออฟไลน์ปัจจุบันจำกัดปทุมธานี ต้องแจ้งขอบเขตและมีแผนที่พื้นที่อื่นก่อนขยายกลุ่มผู้ใช้

### 6. ความเชื่อถือและความเป็นส่วนตัว

มี crypto/private radio, TOFU pins, signed rescue role แล้ว แต่ควรทดสอบโดยผู้ตรวจอิสระ เพิ่ม block/mute และจำกัดอัตรา SOS/ขนาดคิว ป้องกันปลอม/สแปมและ replay เพิ่ม retention/ล้างตำแหน่งตามที่ผู้ใช้เลือก ข้อมูล private radio เข้ารหัสระหว่างต้นทางปลายทาง แต่ Sembast ใน database_factory_io ยังไม่ได้ตั้ง application-level encryption และ cloud sync ส่ง structured plaintext ไป Supabase จึงห้ามโฆษณาว่า local DB และ cloud เป็น E2EE ทั้งหมด

สิทธิ์กู้ภัย offline มีอายุใบรับรอง 30 วัน ควรเตือนล่วงหน้าและมีขั้นตอน renew ขณะออนไลน์ เมื่อหมดอายุให้ยังขอความช่วยเหลือ/แชททั่วไปได้ โดยไม่แสดงเครื่องหมายยืนยันปลอม

### 7. เบื้องหลังและแบตเตอรี่

มี foreground messaging service และ wake/Wi-Fi locks แล้ว ต้องวัดตอนล็อกจอ 30 นาที/หลายชั่วโมงบน Samsung OPPO vivo และ Android ต่างรุ่น จำกัด polling/scan เมื่อเงียบ ลดความถี่ GPS ตามสถานะเคสและแบตเตอรี่ แสดงชัดว่าเปิดรับข้อความอยู่ Android ระบุว่าลิงก์ Bluetooth ปิดได้เมื่อ process ถูกฆ่า จึงห้ามรับประกันรับได้ตลอดเมื่อ force-stop

อ้างอิง: https://developer.android.com/develop/connectivity/bluetooth/ble/background

### 8. กู้ภัยที่เป็นคนรับจริง

ก่อนเผยแพร่ในชุมชนควรมีหน่วยงานหรืออาสาสมัครที่ตกลงใช้ระบบจริง กำหนดผู้รับผิดชอบเวลาเข้าเวร/ขอบเขตพื้นที่/การยืนยันตัวตน และซ้อมเคสร่วมกัน แค่มีจำนวนแอปติดตั้งไม่ได้แปลว่าจะมีคนรับ SOS เสมอ รุ่นแรกควรกำหนดเป็น “เครือข่ายขอความช่วยเหลือใกล้เคียง” ตามความสามารถจริง

## สิ่งที่พบว่าขวางการเผยแพร่ Google Play

1. android/app/build.gradle.kts ยังใช้ signingConfigs.getByName("debug") สำหรับ release ต้องตั้ง upload/release signing และ Play App Signing เก็บ private key นอก repository ก่อนสร้าง AAB ส่ง Store ไม่เปลี่ยนกุญแจ APK ที่แจกไปโดยไม่วางแผนอัปเดต/ย้ายข้อมูล
2. applicationId ยังเป็น com.example.offgrid_sos ควรกำหนดชื่อถาวรก่อนเผยแพร่ครั้งแรก การเปลี่ยน package หลังแจกจะกลายเป็นคนละแอป ต้องวางแผนข้อมูลผู้ทดสอบ
3. มี privacy dialog ในแอป แต่ยังไม่พบหน้าเว็บนโยบายสาธารณะและช่องทางขอลบบัญชีจากเว็บใน repository ต้องมีเนื้อหาจริงและผู้ติดต่อ ข้อมูลการแชร์ตำแหน่ง cloud/relay retention รวม Data safety ที่ตรง SDK/พฤติกรรมจริง
4. ต้องตรวจ manifest/SDK permissions และ foreground-service declaration เท่าที่ใช้จริง ตรวจ native libraries ในสภาพแวดล้อม 16 KB pages และ Play pre-launch report โดยไม่สรุปจากแค่ build ผ่าน
5. ตรวจ live Supabase RLS/storage/account-deletion/restore และ access ด้วยคนละบัญชี ทดสอบ migration ของ local DB จากรุ่นที่แจกอยู่
6. มีช่องทางรายงานบั๊กที่ใช้ได้เมื่อออนไลน์ พร้อม export diagnostics ในเครื่องแบบผู้ใช้ยินยอม ตัด tokens ข้อความส่วนตัวและพิกัดที่ไม่จำเป็นออกจาก log
7. ตรวจใบอนุญาตโค้ด SDK และข้อมูลแผนที่ รวม attribution; เตรียมชื่อผู้พัฒนา support screenshots คำอธิบายขอบเขต offline และช่องทางอัปเดต

อ้างอิง Play/Android: https://developer.android.com/studio/publish/app-signing.html , https://support.google.com/googleplay/android-developer/answer/10144311 , https://support.google.com/googleplay/android-developer/answer/13327111 , https://developer.android.com/guide/practices/page-sizes

## เกณฑ์ทดลองที่เสนอ (เป้าหมายใหม่ ไม่ใช่ผลวัดปัจจุบัน)

- เริ่มจากติดตั้งใหม่ในพื้นที่ไม่มีอินเทอร์เน็ต สร้าง guest เปิดรับได้โดยไม่แตะ cloud
- ส่งข้อความ/ภาพ/วิดีโอ/ตำแหน่งซ้ำ 30 รอบต่อคู่เครื่อง ข้อความไม่หายและไม่ซ้ำ พร้อม log เวลา ACK
- SOS ระหว่างส่งวิดีโอ: วัดเทียบลิงก์ปกติและกำหนด latency budget จากผลเครื่องจริง
- A-B-C ซึ่ง A-C ไม่ได้ยินกัน: ทดสอบส่ง/ยกเลิก SOS รับเคส ACK และไฟล์ ทั้ง B หลุดและ process restart
- ล็อกจอและ Doze ทดสอบเวลาได้รับ การเชื่อมกลับ และแบตเตอรี่ต่อชั่วโมง
- GPS ไม่ได้ fix/permission denied/storage เต็ม/แบตต่ำ/ใบรับรองหมดอายุ ต้องยังมี UI อธิบายและไม่รายงานสำเร็จผิด
- สลับเน็ต 10 รอบระหว่างค้างส่ง ไม่ทำให้ cloud snapshot ลบหรือคืนข้อความเก่า และไม่ทำ SOS ที่หยุดแล้วกลับมาทำงาน
- ซ้อมกับผู้ใช้ที่ไม่เคยใช้แอปและหน่วยกู้ภัยจริง ก่อนเปิด beta แล้วค่อยทยอยเผยแพร่

งานเปลี่ยนโค้ดลำดับแรกที่แนะนำ: SOS receipt + rescue case lifecycle → priority queues → onboarding/diagnostics → field-test corrections → release signing/privacy/backend audit → beta เฉพาะพื้นที่
