# รายงานความคืบหน้า Week 5: Unit Test

**รายวิชา:** Advanced Programming  
**วันที่รันทดสอบ:** 28 ตุลาคม 2569  
**โปรเจกต์:** Offgrid SOS `0.8.2+20` (Flutter/Dart)

## วิธีรัน

```powershell
flutter test --concurrency=1 --reporter expanded `
  test/mesh_attestation_test.dart `
  test/mesh_crypto_test.dart `
  test/home_return_policy_test.dart `
  test/location_quality_test.dart `
  test/network_service_test.dart
```

ใช้ `--concurrency=1` เพื่อให้ผลทดสอบชุดที่เลือกอ่านได้ทีละเคส คำสั่งรันซ้ำได้จากโฟลเดอร์หลักของโปรเจกต์

## ผลทดสอบชุดที่เลือก

**ผ่าน 18 เคส, ไม่ผ่าน 0 เคส** (`All tests passed!`)

โค้ดทดสอบจริงอยู่ในไฟล์ที่ระบุ; เลขหลัง `:` คือตำแหน่งเริ่มของแต่ละเคส

| # | กรณีทดสอบ | โค้ดทดสอบ |
|---:|---|---|
| 1 | ตรวจใบรับรองบัญชีและบทบาทกู้ภัยแบบออฟไลน์ | [`mesh_attestation_test.dart:20`](../test/mesh_attestation_test.dart#L20) |
| 2 | trust anchor จริงปฏิเสธ issuer สำหรับทดสอบ | [`mesh_attestation_test.dart:26`](../test/mesh_attestation_test.dart#L26) |
| 3 | แก้บทบาทที่เซ็นไว้ไม่ทำให้เป็นหน่วยกู้ภัย | [`mesh_attestation_test.dart:32`](../test/mesh_attestation_test.dart#L32) |
| 4 | ใช้หลักฐานต่างอุปกรณ์/บัญชีไม่ผ่าน | [`mesh_attestation_test.dart:40`](../test/mesh_attestation_test.dart#L40) |
| 5 | ลายเซ็นที่หมดอายุไม่คงสิทธิ์กู้ภัย | [`mesh_attestation_test.dart:55`](../test/mesh_attestation_test.dart#L55) |
| 6 | หลักฐานจากอนาคตหรือมีอายุนานเกินกำหนดถูกปฏิเสธ | [`mesh_attestation_test.dart:65`](../test/mesh_attestation_test.dart#L65) |
| 7 | กุญแจคงอยู่หลังเปิดใหม่, TOFU ปฏิเสธกุญแจแทน, ciphertext ผูกกับผู้รับ | [`mesh_crypto_test.dart:5`](../test/mesh_crypto_test.dart#L5) |
| 8 | เปิดแอป/กล่องขอสิทธิ์ไม่ทำให้เปลี่ยนหน้าเกินหนึ่งครั้ง | [`home_return_policy_test.dart:6`](../test/home_return_policy_test.dart#L6) |
| 9 | กลับจากพักแอปแล้วกลับหน้าหลักครั้งเดียว | [`home_return_policy_test.dart:15`](../test/home_return_policy_test.dart#L15) |
| 10 | กล้องและตัวเลือกไฟล์กลับหน้าต้นทาง | [`home_return_policy_test.dart:25`](../test/home_return_policy_test.dart#L25) |
| 11 | เปิดกิจกรรมภายนอกไม่สำเร็จแล้วปลดล็อกสถานะ | [`home_return_policy_test.dart:36`](../test/home_return_policy_test.dart#L36) |
| 12 | ค่าพิกัดแกว่งไม่แทนที่ค่าจริงที่แม่นกว่า | [`location_quality_test.dart:13`](../test/location_quality_test.dart#L13) |
| 13 | การเคลื่อนที่จริงและข้อมูลเก่าไม่ตรึงตำแหน่งเดิม | [`location_quality_test.dart:25`](../test/location_quality_test.dart#L25) |
| 14 | เลือกพิกัดที่ดีที่สุดและยกเลิก stream เมื่อหมดเวลา | [`location_quality_test.dart:35`](../test/location_quality_test.dart#L35) |
| 15 | ไม่มีข้อมูลคืนค่า null; stream ผิดพลาดยังรักษาค่าคลาดเคลื่อนจริง | [`location_quality_test.dart:52`](../test/location_quality_test.dart#L52) |
| 16 | พิกัดดีสามค่าที่ต่างกันทำให้จบก่อนเวลา โดยไม่ลดค่าคลาดเคลื่อน | [`location_quality_test.dart:65`](../test/location_quality_test.dart#L65) |
| 17 | Wi-Fi ที่ไม่มีอินเทอร์เน็ตยังออฟไลน์ และตรวจพบเมื่อคลาวด์กลับมา | [`network_service_test.dart:7`](../test/network_service_test.dart#L7) |
| 18 | ไม่มีเครือข่ายไม่ probe คลาวด์ และยังใช้งานออฟไลน์เมื่อเกิด exception | [`network_service_test.dart:23`](../test/network_service_test.dart#L23) |

## ผลทดสอบชุดเต็ม

การรันชุดเต็มครั้งแรกพบ 12 เคสไม่ผ่าน จึงแก้การคืนค่า identity ตอนยังไม่ initialize Supabase และปรับ test harness ให้ถอดรหัส/ตรวจแพ็กเก็ตตามโปรโตคอล Nearby ที่เข้ารหัสแล้ว รวมถึงรอผล asynchronous cloud lookup ใน test ให้แน่นอน

ผลรันชุดเต็มล่าสุด: **ผ่าน 171 เคส, ไม่ผ่าน 0 เคส** (`All tests passed!`)

## หลักฐานผลจาก Terminal

- [ผลคำสั่งชุดที่เลือก (18 เคส)](week5-selected-test-output.txt)
- [ผลคำสั่งชุดเต็มล่าสุด (171 ผ่าน)](week5-final-test-output.txt)
- [ผลรันชุดเต็มครั้งแรกก่อนแก้ (ใช้ดูประวัติข้อผิดพลาด)](week5-unit-test-output.txt)
