# SOSBROO 0.10.11+42

## CSS เป็นแหล่งข้อมูลสไตล์จริง

เพิ่ม styles/app.css และตัวแปลง tool/generate_styles.dart เพื่ออ่านสี ฟอนต์ และขนาดร่วมจาก CSS variables สร้าง app_palette.dart/style_tokens.dart แล้วผูกกับ ThemeData และ widgets ที่ใช้งานจริง รวมสีซ้ำของโลโก้ หมุดแผนที่ สีเน้นกู้ภัย และค่ารูปร่างการ์ด/ปุ่ม/ช่องกรอก

Flutter ยังวาด UI ด้วย Widgets ไม่ใช่ browser CSS engine ขอบเขต CSS ที่รองรับและวิธีอธิบายให้อาจารย์ตรวจอยู่ใน docs/css-styling-guide.md ไม่ได้อ้างว่าทั้ง layout/selector/media query ทุกแบบใช้ CSS ได้

เพิ่ม tool/build_android.ps1 ให้เรียก generator ก่อนวิเคราะห์โค้ด ทดสอบ และสร้าง APK คำสั่ง --check กับเทสตรวจว่า CSS/ไฟล์ generated ตรงกัน เพื่อไม่ให้แก้ CSS แล้วหลงใช้ Dart ที่ค้างอยู่ การประมวลผล CSS เกิดก่อน build เท่านั้น ไม่เพิ่มการโหลดสไตล์จากอินเทอร์เน็ตและไม่มี runtime parser บนโทรศัพท์

## การตรวจ

- สคริปต์ tool/build_android.ps1 -SkipTests ทำงานจริง: generator → analyze ไม่พบปัญหา → APK release สำเร็จ — build/build-v42.log (ชุดเทสเต็มรันแยกก่อนแล้ว)
- flutter test --no-pub: 256 เคสผ่าน — build/tests-v42.log
- หลังเก็บรูปแบบโค้ดใน generator: เทส CSS เฉพาะส่วน 4 เคสผ่าน — build/css-v42.log
- ตรวจการแก้สีและ control radius ใน CSS แล้วค่า Dart เปลี่ยนจริง ตรวจ alias/cycle ตัวแปร การสะกดผิด/ค่าที่ไม่รองรับ และไฟล์ generated ตรง CSS
- เทส UI สว่าง/มืด หน้าจอเล็ก ตัวอักษรใหญ่ สี SOS/กู้ภัย และเทสแชท/SOS ออฟไลน์เดิมผ่านในชุดเต็ม
- รอบนี้ไม่แก้พฤติกรรมแชท SOS ข้อมูล Supabase หรือโปรโตคอลวิทยุ และยังไม่ได้ติดตั้งบนโทรศัพท์

## ไฟล์สำหรับส่งตรวจ

เริ่มจาก styles/app.css → tool/generate_styles.dart → lib/app/theme.dart และอ่าน docs/css-styling-guide.md ส่วนไฟล์ app_palette.dart/style_tokens.dart มีข้อความ GENERATED ระบุที่มาชัดเจน ควรส่ง CSS, generator, templates และ Dart ที่สร้างแล้วไปพร้อม source code ทั้งชุด

## APK

build/app/outputs/flutter-apk/SOSBROO-v42.apk — versionName 0.10.11, versionCode 42 คง package ID และข้อมูลเดิมสำหรับอัปเดตทับ

ตรวจ manifest ชื่อ/เวอร์ชันตรง และ zipalign -c -P 16 4 ผ่าน

SHA-256: 6764CE8C9788CD8876564FD313C7734853A906590580BF9C0C38A550DBAEFC6B
