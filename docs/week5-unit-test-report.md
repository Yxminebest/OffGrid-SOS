# รายงานผลการทดสอบ Unit Test — ความคืบหน้า Week 5

**รายวิชา:** Advanced Programming

**โครงงาน:** Off-Grid SOS & Nearby Share (`0.8.2+20`)

**วันที่ทดสอบ:** 30 ตุลาคม 2569

## วัตถุประสงค์

ทดสอบฟังก์ชันหลักของแอป Off-Grid SOS ได้แก่ การยืนยันตัวตนและสิทธิ์กู้ภัย การเข้ารหัสข้อความ การจัดการการกลับจากหน้าหรือแอปภายนอก ความถูกต้องของพิกัด และการทำงานเมื่อไม่มีอินเทอร์เน็ต

## สภาพแวดล้อมและวิธีรัน

รันจากโฟลเดอร์รากของโปรเจกต์ Flutter บน Windows โดยใช้ dependencies ที่ล็อกไว้ใน `pubspec.lock` คำสั่งชุดเต็ม:

```powershell
flutter test --no-pub --concurrency=1 --reporter expanded
```

คำสั่งชุดคัดเลือก 18 เคส:

```powershell
flutter test --no-pub --concurrency=1 --reporter expanded `
  test/mesh_attestation_test.dart `
  test/mesh_crypto_test.dart `
  test/home_return_policy_test.dart `
  test/location_quality_test.dart `
  test/network_service_test.dart
```

`--concurrency=1` ทำให้ output แสดงผลทีละเคส ส่วน `--reporter expanded` แสดงชื่อเคสและจำนวนผลสะสม ตัวเลือก `--no-pub` ใช้ dependencies จาก lockfile โดยไม่เปลี่ยนชุดแพ็กเกจ

## สรุปผล

- ผ่าน 18 เคส, ไม่ผ่าน 0 เคส (`All tests passed!`)
- เป็นผลจาก automated unit/widget tests

## รายการเคสและคำสั่งรันแยกรายเคส

แต่ละแถวมีคำสั่งรันเคสนั้นโดยตรง และลิงก์ไปยัง source code ของ `test()` ใน repository

| # | กรณีทดสอบ | โค้ดทดสอบ | คำสั่งรันเคส |
|---:|---|---|---|
| 1 | บัญชีที่ยืนยันแล้วและบทบาทกู้ภัยตรวจสอบได้แบบออฟไลน์ | [`mesh_attestation_test.dart:20`](../test/mesh_attestation_test.dart#L20) | `flutter test --no-pub --concurrency=1 --reporter expanded test/mesh_attestation_test.dart --plain-name "signed account and rescue role verify without network"` |
| 2 | trust anchor จริงปฏิเสธ issuer สำหรับทดสอบ | [`mesh_attestation_test.dart:26`](../test/mesh_attestation_test.dart#L26) | `flutter test --no-pub --concurrency=1 --reporter expanded test/mesh_attestation_test.dart --plain-name "production trust anchor rejects the test issuer"` |
| 3 | แก้บทบาทที่เซ็นไว้ไม่ทำให้ผู้ใช้ทั่วไปเป็นหน่วยกู้ภัย | [`mesh_attestation_test.dart:32`](../test/mesh_attestation_test.dart#L32) | `flutter test --no-pub --concurrency=1 --reporter expanded test/mesh_attestation_test.dart --plain-name "changing a signed role does not create a rescuer"` |
| 4 | นำหลักฐานไปใช้อีกอุปกรณ์หรือบัญชีหนึ่งไม่ได้ | [`mesh_attestation_test.dart:40`](../test/mesh_attestation_test.dart#L40) | `flutter test --no-pub --concurrency=1 --reporter expanded test/mesh_attestation_test.dart --plain-name "copying proof to a different device or account fails"` |
| 5 | ลายเซ็นที่หมดอายุไม่คงสิทธิ์กู้ภัย | [`mesh_attestation_test.dart:55`](../test/mesh_attestation_test.dart#L55) | `flutter test --no-pub --concurrency=1 --reporter expanded test/mesh_attestation_test.dart --plain-name "expired valid signature cannot retain rescue authorization"` |
| 6 | หลักฐานที่ออกในอนาคตหรือมีอายุนานเกินกำหนดถูกปฏิเสธ | [`mesh_attestation_test.dart:65`](../test/mesh_attestation_test.dart#L65) | `flutter test --no-pub --concurrency=1 --reporter expanded test/mesh_attestation_test.dart --plain-name "future-issued and excessive lifetime proofs fail closed"` |
| 7 | กุญแจคงอยู่หลังเปิดใหม่, ปฏิเสธกุญแจแทน และ ciphertext ผูกกับผู้รับ | [`mesh_crypto_test.dart:5`](../test/mesh_crypto_test.dart#L5) | `flutter test --no-pub --concurrency=1 --reporter expanded test/mesh_crypto_test.dart --plain-name "keys persist, TOFU rejects a replacement key, ciphertext binds recipient"` |
| 8 | เปิดแอป/หน้าขอสิทธิ์ไม่ทำให้เปลี่ยนหน้าเกินหนึ่งครั้ง | [`home_return_policy_test.dart:6`](../test/home_return_policy_test.dart#L6) | `flutter test --no-pub --concurrency=1 --reporter expanded test/home_return_policy_test.dart --plain-name "new launch and permission dialogs do not trigger duplicate navigation"` |
| 9 | กลับจากพักแอปแล้วกลับหน้าหลักครั้งเดียว | [`home_return_policy_test.dart:15`](../test/home_return_policy_test.dart#L15) | `flutter test --no-pub --concurrency=1 --reporter expanded test/home_return_policy_test.dart --plain-name "real background returns home once on resume"` |
| 10 | กล้องและตัวเลือกไฟล์กลับหน้าต้นทาง | [`home_return_policy_test.dart:25`](../test/home_return_policy_test.dart#L25) | `flutter test --no-pub --concurrency=1 --reporter expanded test/home_return_policy_test.dart --plain-name "camera and picker return to originating screen"` |
| 11 | เปิดกิจกรรมภายนอกไม่สำเร็จแล้วปลดล็อกสถานะ | [`home_return_policy_test.dart:36`](../test/home_return_policy_test.dart#L36) | `flutter test --no-pub --concurrency=1 --reporter expanded test/home_return_policy_test.dart --plain-name "failed external launch releases guard"` |
| 12 | ค่าพิกัดแกว่งไม่แทนที่ค่าจริงที่แม่นกว่า | [`location_quality_test.dart:13`](../test/location_quality_test.dart#L13) | `flutter test --no-pub --concurrency=1 --reporter expanded test/location_quality_test.dart --plain-name "poor jitter keeps recent real better fix without changing accuracy or time"` |
| 13 | การเคลื่อนที่จริงและข้อมูลเก่าไม่ตรึงตำแหน่งเดิม | [`location_quality_test.dart:25`](../test/location_quality_test.dart#L25) | `flutter test --no-pub --concurrency=1 --reporter expanded test/location_quality_test.dart --plain-name "real movement and expired window do not freeze old position"` |
| 14 | เลือกพิกัดที่ดีที่สุดและยกเลิก stream เมื่อหมดเวลา | [`location_quality_test.dart:35`](../test/location_quality_test.dart#L35) | `flutter test --no-pub --concurrency=1 --reporter expanded test/location_quality_test.dart --plain-name "collection selects best fix and cancels stream at deadline"` |
| 15 | ไม่มีข้อมูลคืนค่า null; เมื่อ stream ผิดพลาดยังรักษาค่าคลาดเคลื่อนจริง | [`location_quality_test.dart:52`](../test/location_quality_test.dart#L52) | `flutter test --no-pub --concurrency=1 --reporter expanded test/location_quality_test.dart --plain-name "no readings returns null, stream failure keeps real poor accuracy"` |
| 16 | พิกัดดีสามค่าที่ต่างกันทำให้จบก่อนเวลา โดยไม่ลดค่าคลาดเคลื่อน | [`location_quality_test.dart:65`](../test/location_quality_test.dart#L65) | `flutter test --no-pub --concurrency=1 --reporter expanded test/location_quality_test.dart --plain-name "three distinct good fixes settle early without lowering reported accuracy"` |
| 17 | Wi-Fi D2D ที่ไม่มีอินเทอร์เน็ตยังคงสถานะออฟไลน์ และกลับมาใช้คลาวด์ได้เมื่อออนไลน์ | [`network_service_test.dart:7`](../test/network_service_test.dart#L7) | `flutter test --no-pub --concurrency=1 --reporter expanded test/network_service_test.dart --plain-name "Wi-Fi D2D without Internet stays offline; cloud recovery needs no radio change"` |
| 18 | ไม่มีเครือข่ายไม่ probe คลาวด์ และ exception ไม่ทำให้การใช้งานออฟไลน์หยุด | [`network_service_test.dart:23`](../test/network_service_test.dart#L23) | `flutter test --no-pub --concurrency=1 --reporter expanded test/network_service_test.dart --plain-name "no interface does not probe cloud and exceptions leave offline mode usable"` |

## หลักฐาน output จาก Terminal

- [Output ชุดคัดเลือก 18 เคส — 18 ผ่าน](week5-selected-test-output.txt)

ผลทดสอบลงท้ายด้วย `+18: All tests passed!` แนบ output นี้เป็นหลักฐานการรันจาก terminal

## หมายเหตุ

ชุดทดสอบนี้ตรวจตรรกะและ UI ภายใต้ test environment ของ Flutter การสื่อสารผ่าน Bluetooth/Nearby ระหว่างโทรศัพท์จริงและการส่งต่อเครือข่ายสามเครื่องต้องรายงานเป็นการทดสอบอุปกรณ์จริงแยกต่างหาก
