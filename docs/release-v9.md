# APK รุ่น 0.4.0+9

สร้างจาก source ล่าสุดใน working tree วันที่ 18 ตุลาคม 2569

- ไฟล์: `build/app/outputs/flutter-apk/Offgrid-SOS-v9-complete.apk`
- ขนาด: 60,072,949 bytes
- SHA-256: `534B5EA4EC166C16CAA1B567E82263A4DD879427C993952D244207965A4E8AF1`
- Application ID: `com.example.offgrid_sos`
- Version code/name: `9` / `0.4.0`
- Android API 24 ขึ้นไป; target 36; ARM32/ARM64/x86_64
- `apksigner verify --print-certs` ผ่าน
- Certificate SHA-256 เดิม: `0bb719fdea76bebffcf87b1433ab5eb968e817337c0fb4816f8a845f3064142a`
- เป็น Release build ที่ใช้ signing เดิมของชุดทดสอบ เพื่ออัปเดตทับแอปเดิมโดยไม่ล้างข้อมูล

## ผลตรวจ source นี้

- `flutter analyze --no-pub`: No issues found
- `flutter test --no-pub --reporter expanded`: 91 tests passed
- `node tool/check_backend.mjs`: 15 checks passed
- `git diff --check`: ผ่าน (มีคำเตือน Windows LF/CRLF ตามปกติ)

ตรวจการเชื่อมต่อหลังบิลด์: ADB ไม่มีอุปกรณ์ และ Windows ไม่พบโทรศัพท์ในช่องทางโอนไฟล์
ดังนั้น **ยังไม่ได้ส่ง APK/ติดตั้งรุ่นนี้บนโทรศัพท์**
ติดตั้งแบบอัปเดตทั้งสองเครื่อง จากนั้นใช้ `docs/testing-v9.md`
Source และ SQL รวมใน Git แล้ว; Supabase ติดตั้งจริงในรอบถัดมา ดู `supabase-deployment-2026-10-18.md`
