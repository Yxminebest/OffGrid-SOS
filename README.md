# SOSBROO — OffGrid SOS

แอป Flutter สำหรับแจ้งเหตุ SOS และสื่อสารกับอุปกรณ์ใกล้เคียงเมื่ออินเทอร์เน็ตไม่พร้อมใช้งาน บันทึกข้อมูลลงเครื่องก่อนส่งผ่าน Nearby/Bluetooth และใช้ Supabase สำหรับบัญชีผู้ใช้ แชทออนไลน์ และสำรองประวัติ

## ลิงก์และไฟล์ส่งงาน

| รายการ | ตำแหน่ง / สถานะ |
|---|---|
| GitHub | [Yxminebest/OffGrid-SOS](https://github.com/Yxminebest/OffGrid-SOS) |
| README | [เอกสารแนะนำโครงการ](https://github.com/Yxminebest/OffGrid-SOS#readme) |
| APK ล่าสุดในเครื่อง | `build/app/outputs/flutter-apk/app-release.apk` — ตรวจ metadata แล้วเป็น **0.10.15+46** |
| APK สาธารณะ | ยังไม่มี Release ใน [GitHub Releases](https://github.com/Yxminebest/OffGrid-SOS/releases) ณ วันที่ตรวจ 11 พฤศจิกายน 2569 ต้องแนบ APK หรืออัปโหลดก่อนส่งลิงก์ให้ผู้ตรวจ |
| TestFlight | ยังไม่มีลิงก์ที่ยืนยันได้ การสาธิต Nearby/Bluetooth ใช้ Android |

**รุ่นซอร์สโค้ด:** `0.10.15+46` ตาม [pubspec.yaml](pubspec.yaml) ชื่อแสดงผลคือ SOSBROO ส่วนชื่อ repository และ package Flutter ยังคงใช้ OffGrid SOS / `offgrid_sos`

ไฟล์ใน `build/` ไม่ติดไปกับการ clone GitHub จึงต้องส่ง APK แยกด้วย ค่า SHA-256 ของ APK ที่ตรวจครั้งนี้:

```text
41752ff82471ccb19d95ce9e6ea510f27ccb393a302729bf065dfe6e307bfa75
```

## วัตถุประสงค์และฟีเจอร์

ช่วยให้ผู้ประสบเหตุบันทึกคำขอความช่วยเหลือ ส่งข้อความและตำแหน่งให้ผู้ใช้ใกล้เคียง และให้บัญชีกู้ภัยที่ได้รับการตรวจสิทธิ์ติดตามเคสได้ โดยข้อมูลที่ยังส่งไม่สำเร็จจะอยู่ในเครื่องเพื่อรอส่งใหม่เมื่อมีเส้นทางติดต่อ

| ความสามารถ | การทำงานและเงื่อนไข |
|---|---|
| แจ้ง SOS | บันทึกเหตุและรายละเอียดในเครื่อง รองรับพิกัดพร้อมเวลาและความคลาดเคลื่อน ส่งสถานะเริ่ม/หยุดให้เครื่องที่เชื่อมถึงกัน |
| แชทส่วนตัว | ข้อความ รูป วิดีโอ และตำแหน่ง รวมประวัติ Nearby/คลาวด์ด้วย ID เดียวกัน รองรับตอบกลับ แก้ไข ยกเลิกส่ง และลบข้อความของตนเอง |
| ห้องสนทนาส่วนกลาง | ห้องข้อความสาธารณะในเครือข่ายใกล้เคียง ส่งต่อผ่านตัวกลางและแลกประวัติเมื่อเชื่อมต่อใหม่ รองรับแก้ไข/ลบ ยังไม่มีไฟล์แนบในห้องนี้ |
| Nearby / Bluetooth | Android ใช้ Nearby Connections แบบ P2P_CLUSTER หรือ Bluetooth RFCOMM โดยตรง ผู้ใช้กดขอเชื่อมต่อและอีกเครื่องอนุมัติ |
| ส่งต่อหลายทอด | ส่งผ่านอุปกรณ์ตัวกลางเมื่อมีเส้นทาง จำกัดจำนวนทอดและป้องกันข้อความซ้ำ ระยะและความเสถียรต้องทดสอบบนเครื่องจริง |
| กู้ภัย | ผู้ดูแลอนุมัติบทบาท รับเคสและรายงานความคืบหน้า การเปิดโหมดกู้ภัยออฟไลน์ต้องมีใบรับรองที่ยังไม่หมดอายุ |
| แผนที่ออฟไลน์ | ข้อมูลแผนที่ปทุมธานีและขอบเขตใกล้เคียงรวมใน APK แสดงหมุด ระยะเส้นตรง และทิศทางจาก GPS |
| บัญชี / หน้าตา | สมัคร ยืนยันอีเมล เข้าสู่ระบบ รีเซ็ตรหัสผ่าน จัดการโปรไฟล์ และธีมสว่าง/มืด |

รุ่นปัจจุบัน **ไม่มีโหมด Guest** ต้องสมัครและเข้าสู่ระบบขณะออนไลน์ก่อน เมื่อมีข้อมูลสมาชิกที่บันทึกไว้แล้วจึงเปิดใช้งานออฟไลน์ได้ การออกจากระบบล้างข้อมูลสำหรับคืนสถานะเข้าสู่ระบบ จึงไม่ควรออกจากระบบก่อนเดโมออฟไลน์

## ติดตั้ง APK เพื่อทดลอง

1. ใช้โทรศัพท์ Android อย่างน้อย 2 เครื่อง มี Google Play services สำหรับ Nearby; APK ที่ตรวจต้องการ Android API 24 ขึ้นไป
2. รับไฟล์ `app-release.apk` จากผู้ส่งงาน ติดตั้ง **รุ่นเดียวกันทุกเครื่อง** อนุญาตการติดตั้งจากแหล่งที่ใช้เปิด APK เมื่อระบบถาม
3. เปิดแอปขณะออนไลน์ สมัครสมาชิก ยืนยันอีเมล และเข้าสู่ระบบแยกบัญชีในแต่ละเครื่อง
4. อนุญาตตำแหน่ง Bluetooth/Wi-Fi อุปกรณ์ใกล้เคียง และแจ้งเตือนตามที่แอปขอ เปิดบริการตำแหน่งของ Android
5. เปิดหน้า Nearby เลือกอุปกรณ์ ขอเชื่อมต่อ ให้อีกเครื่องอนุมัติและตรวจรหัสเมื่อมีแสดง การพบชื่อยังไม่ถือว่าเชื่อมต่อสำเร็จ
6. สำหรับ Bluetooth โดยตรง ให้เปิดรับ Bluetooth ในแอปทั้งสองเครื่อง และยืนยันการจับคู่ของ Android หากมี

หากติดตั้งทับไม่ได้ ให้ตรวจ package และกุญแจเซ็นของ APK เดิมก่อน การถอนการติดตั้งอาจทำให้ประวัติและคิวที่อยู่เฉพาะในเครื่องสูญหาย

## ขั้นตอนสาธิตประมาณ 5–10 นาที

1. **เตรียม:** ติดตั้งรุ่นเดียวกันบน A/B และเข้าสู่ระบบไว้ก่อน หากสาธิตกู้ภัยให้เตรียมบัญชีที่อนุมัติแล้วและรับใบรับรองออนไลน์
2. **ออฟไลน์:** ปิด mobile data และตัด Wi-Fi ที่มีอินเทอร์เน็ต แต่เปิดวิทยุ Wi-Fi/Bluetooth และ Location ไว้สำหรับ Nearby จากนั้นขอเชื่อมต่อและอนุมัติทั้งสองฝั่ง
3. **แชท:** ส่งข้อความ รูป หรือพิกัดจาก A ไป B ตรวจข้อความและสถานะรับถึงเครื่อง ลองตอบกลับ/แก้ไขข้อความ
4. **SOS:** กดค้างปุ่ม SOS 1 วินาทีเพื่อบันทึกคำขอทันที แล้วเพิ่มรายละเอียดในหน้าที่เปิดขึ้น ให้ B ตรวจคำขอและเปิดแชทผู้แจ้ง จากนั้นหยุด SOS และตรวจอีกฝั่ง
5. **ห้องส่วนกลาง:** เปิดข้อความ → ห้องสนทนาส่วนกลาง ส่งข้อความ แก้ไข และลบ ตรวจผลทั้งสองเครื่อง
6. **หลายทอด (ถ้ามี C):** เชื่อม A–B–C โดยยืนยันว่า A/C ไม่มีลิงก์ตรง ส่งผ่าน B ตัดเส้นทางแล้วเชื่อมใหม่ ตรวจประวัติว่าไม่ซ้ำ
7. **กลับมาออนไลน์:** ตรวจการซิงก์และประวัติเดิม แยกสถานะสำรองขึ้นคลาวด์ออกจากการรับถึงเครื่องปลายทาง

## รันจากซอร์สโค้ด

ต้องมี Flutter ที่รองรับ Dart `^3.12.2`, Android SDK และ JDK 17 ตามการตั้งค่าโครงการ

```sh
git clone https://github.com/Yxminebest/OffGrid-SOS.git
cd OffGrid-SOS
flutter pub get
dart run tool/generate_styles.dart
flutter devices
flutter run -d <ANDROID_DEVICE_ID>
```

แทน `<ANDROID_DEVICE_ID>` ด้วย ID จาก `flutter devices` ค่า Supabase เดิมอยู่ใน [supabase_config.dart](lib/app/supabase_config.dart) และใช้ public client key หากใช้ backend ของตนเองให้กำหนดทั้ง URL/key:

```sh
flutter run -d <ANDROID_DEVICE_ID> --dart-define=SUPABASE_URL=YOUR_PROJECT_URL --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

ตั้ง Auth redirect เป็น `com.kittaporn.offgridsos://login-callback/` ดู [คู่มือ backend](docs/backend-setup.md), [SQL เริ่มต้น](supabase/bootstrap.sql) และ [migrations](supabase/migrations) ประกอบ เอกสาร backend เก่าบางส่วนอ้างรุ่นเดิม ให้ตรวจ schema/migrations ปัจจุบันก่อนใช้กับโปรเจกต์ใหม่

เมื่อย้าย Supabase ต้องเตรียม Edge Functions `delete-account` และ `mesh-attestation` รวมถึง issuer/trust anchor ใน [mesh_attestation.dart](lib/services/mesh_attestation.dart) ให้ตรงกัน การเปลี่ยน URL/key อย่างเดียวไม่ทำให้ใบรับรองออฟไลน์ของโปรเจกต์ใหม่ใช้งานได้ ห้ามใส่ service-role key หรือ issuer seed ในแอปหรือ Git

### ตรวจและสร้าง APK

```sh
dart run tool/generate_styles.dart --check
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
```

บน Windows หลัง `flutter pub get` ใช้สคริปต์รวมสร้าง styles → analyze → test → build ได้:

```powershell
.\tool\build_android.ps1
```

ผลลัพธ์คือ `build/app/outputs/flutter-apk/app-release.apk` สคริปต์ใช้ backend ค่าเริ่มต้น หากเปลี่ยน backend ให้ใส่ `--dart-define` ในคำสั่ง build เอง

หากไม่มี `android/key.properties` การตั้งค่าปัจจุบันจะเซ็น release APK ด้วย debug key สำหรับทดสอบ ส่วน AAB/การบังคับ release signing ต้องใช้กุญแจส่วนตัวตาม [ตัวอย่าง key.properties](android/key.properties.example) เก็บกุญแจและรหัสผ่านแยกจาก Git

## โครงสร้างและแนวทางพัฒนาต่อ

| ตำแหน่ง | หน้าที่ |
|---|---|
| `lib/main.dart`, `lib/features/home/` | เริ่มแอป คืนสถานะสมาชิก เริ่มบริการและจัดการ lifecycle |
| `lib/features/`, `lib/widgets/` | หน้าจอและองค์ประกอบ UI แยกฟีเจอร์ |
| `lib/data/local/`, `lib/data/repositories/` | ฐานข้อมูล Sembast ข้อมูลแยกบัญชีและคิวถาวร |
| `lib/services/unified_chat_service.dart` | รวมประวัติแชทและเลือกส่งวิทยุ/คลาวด์ |
| `lib/services/nearby_mesh_service.dart`, `lib/services/mesh/` | เชื่อมต่อ จับคู่ เส้นทางหลายทอด ACK และส่งซ้ำ |
| `lib/services/nearby_media_transfer.dart` | ส่งไฟล์เป็นส่วน รับต่อและยืนยันเมื่อครบ |
| `lib/services/mesh_crypto.dart`, `lib/services/mesh_attestation.dart` | ลายเซ็น การเข้ารหัสและใบรับรองบัญชี/กู้ภัย |
| `android/app/src/main/kotlin/` | Bluetooth โดยตรง แจ้งเตือนและ foreground service |
| `supabase/` | Schema, RLS, migrations และ Edge Functions |
| `styles/app.css`, `tool/style_templates/` | ต้นฉบับสี/ขนาดและ template สร้าง Dart styles |
| `assets/maps/pathum_thani/`, `packages/flutter_map_vector_tiles/` | แผนที่ในเครื่องและแพ็กเกจเวกเตอร์พร้อม patch ฟอนต์ไทย |
| `test/` | Unit/widget tests และ transport จำลอง |

เริ่มจาก [คู่มือส่งต่อผู้พัฒนา](docs/developer-handoff.md) แก้สี/ขนาดที่ CSS หรือ template แล้ว generate ใหม่ อย่าแก้ `app_palette.dart` และ `style_tokens.dart` ที่สร้างอัตโนมัติโดยตรง ดู [คู่มือสไตล์](docs/css-styling-guide.md)

## ขอบเขตและสถานะการทดสอบ

- Nearby/Bluetooth รองรับ Android; การมีโฟลเดอร์ iOS/web/desktop ไม่ได้ยืนยันว่าฟีเจอร์วิทยุรองรับแพลตฟอร์มเหล่านั้น
- Nearby เลือกวิทยุภายในเอง ไม่รับประกัน Wi-Fi-only และไม่ได้ใช้ Wi-Fi IBSS
- ห้องส่วนกลางอ่านได้โดยผู้เข้าร่วมเครือข่ายใกล้เคียง ลายเซ็นระบุอุปกรณ์ผู้ส่ง ไม่ได้ยืนยันบทบาทกู้ภัยแทนใบรับรองเซิร์ฟเวอร์
- แผนที่ไม่ครอบคลุมทั้งประเทศ ไม่มีนำทางเลี้ยวต่อเลี้ยว GPS อาจช้า/คลาดเคลื่อน แอปแสดงเวลาและความคลาดเคลื่อนที่ได้รับจริง
- สื่อคลาวด์ที่ยังไม่ดาวน์โหลดต้องใช้อินเทอร์เน็ต การสำรอง Nearby เป็นสำเนาของเจ้าของบัญชี ไม่ใช่หลักฐานว่าคู่สนทนาได้รับข้อความ
- foreground service ช่วยรับข้อความขณะแอปทำงาน แต่ไม่ใช่ push ที่ปลุกแอปหลัง force-stop ต้องเปิดแอปและเชื่อมต่อใหม่เมื่อโปรเซสถูกปิด
- โฟลเดอร์ `test/` คงไว้ 10 ชุดหลัก: `unified_chat_test`, `nearby_protocol_test`, `nearby_media_test`, `sync_service_test`, `offline_regression_test`, `emergency_home_panel_test`, `rescue_status_test`, `mesh_crypto_test`, `mesh_router_test` และ `bundled_pathum_map_test`; SQL checks ใน `supabase/tests/` แยกตรวจ backend ผลรุ่นเก่าใน `docs/` ไม่ใช่ผลของรุ่นปัจจุบัน
- ก่อนส่งสาธิตควรทดสอบบนโทรศัพท์จริง 2–3 เครื่อง โดยเฉพาะจับคู่ พักหน้าจอ ส่งไฟล์และส่งต่อหลายทอด ชุดทดสอบจำลองไม่ยืนยันระยะหรือความเสถียรของวิทยุจริง

## ข้อมูลแผนที่และสัญญาอนุญาต

ดู [ที่มาข้อมูลแผนที่](assets/maps/pathum_thani/README.md), [ODbL 1.0](assets/maps/pathum_thani/ODbL-1.0.txt) และ [สัญญาอนุญาตฟอนต์](assets/maps/pathum_thani/FONT-LICENSE.txt) แพ็กเกจเวกเตอร์มี [LICENSE](packages/flutter_map_vector_tiles/LICENSE) และ [รายละเอียด patch](packages/flutter_map_vector_tiles/OFFGRID-PATCH.md) แยกต่างหาก
