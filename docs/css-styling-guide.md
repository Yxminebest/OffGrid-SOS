# การแก้สีและรูปแบบ UI ด้วย CSS สำหรับตรวจส่งงาน

## เทคโนโลยีที่ใช้จริง

SOSBROO เป็นแอป Flutter/Dart สำหรับ Android การจัดวางหน้าจอใช้ Widget และธีมใช้ ThemeData/ThemeExtension ตามแนวทาง [Flutter Themes](https://docs.flutter.dev/cookbook/design/themes) จึงไม่ได้ใช้ DOM หรือ CSS renderer แบบเว็บ

ตามข้อกำหนดให้มี CSS จริง โครงการนี้ใช้ **styles/app.css เป็นไฟล์ต้นทางจริง** ของสี ฟอนต์ และค่ารูปแบบร่วม แล้วแปลงเป็น Dart ตอนพัฒนา/สร้างแอป ไม่ได้เพิ่มไฟล์ CSS ที่ไม่มีผู้ใช้งาน และไม่ได้อ้างว่า Flutter อ่าน CSS ทุกคำสั่งได้โดยตรง

ลำดับการใช้งาน:

```text
styles/app.css
    ↓ dart run tool/generate_styles.dart
lib/app/app_palette.dart + lib/app/style_tokens.dart (generated)
    ↓
lib/app/theme.dart → MaterialApp theme/darkTheme → หน้าจอและ widgets ร่วม
```

ข้อมูลสไตล์ถูกคอมไพล์รวมใน APK ไม่โหลด CSS จากอินเทอร์เน็ตตอนเปิดแอป แชทและ SOS ออฟไลน์จึงไม่ต้องรอดาวน์โหลดสไตล์

## ไฟล์ที่อาจารย์ตรวจได้

| ไฟล์ | หน้าที่ |
| --- | --- |
| styles/app.css | สีแบรนด์/SOS/กู้ภัย/แผนที่ สีสว่าง/มืด ฟอนต์ และขนาดร่วม |
| tool/generate_styles.dart | อ่าน CSS variables ตรวจรูปแบบ/ตัวแปรที่สะกดผิด และสร้าง Dart |
| tool/style_templates/*.template | โครงสร้างคลาส Flutter และตำแหน่งผูกตัวแปร CSS ไม่มีค่าสี hex ของหน้าจอซ้ำ |
| lib/app/app_palette.dart | คลาสสีและ ThemeExtension ที่สร้างจาก CSS ห้ามแก้ตรงไฟล์นี้ |
| lib/app/style_tokens.dart | ขนาดร่วมที่สร้างจาก CSS ห้ามแก้ตรงไฟล์นี้ |
| lib/app/theme.dart | นำค่าที่สร้างแล้วไปตั้ง ThemeData ของปุ่ม ฟอร์ม การ์ด ฟอนต์ และ navigation |
| lib/widgets/app_card.dart | ตัวอย่างการ์ดที่ใช้สีและ radius/padding จากส่วนกลาง |
| lib/widgets/brand_mark.dart | ตัวอย่างโลโก้ที่ใช้สีจาก CSS ผ่าน AppColors |
| `dart run tool/generate_styles.dart --check` | ตรวจว่าไฟล์ generated ตรงกับ CSS/template ปัจจุบัน |
| tool/build_android.ps1 | สร้างสไตล์จาก CSS → analyze → test → สร้าง APK |

## วิธีแก้และสร้างแอป

หลังติดตั้ง Flutter และ dependencies ของโครงการตาม README ให้แก้ styles/app.css เช่น:

```css
:root {
  --color-brand: #F4C84B;
  --color-brand-ink: #30250D;
  --color-sos: #C93643;
  --color-error: var(--color-sos);
  --color-rescue-strong: #1859A9;
  --font-family: 'Roboto';
  --control-radius: 16px;
  --button-height: 54px;
}
```

ตัวอย่างนี้เป็นเพียงบางตัวแปร อย่าแทนไฟล์ต้นฉบับทั้งไฟล์ด้วยตัวอย่าง จากนั้นรัน:

```powershell
dart run tool/generate_styles.dart
flutter run
```

การสร้าง APK พร้อมตรวจ:

```powershell
powershell -File tool/build_android.ps1
```

หากใช้ flutter build apk โดยตรง ต้องสั่ง generator ก่อน เพราะ Flutter ไม่เรียกตัวแปลง CSS เอง ตรวจความตรงกันได้ด้วย:

```powershell
dart run tool/generate_styles.dart --check
```

คำสั่ง --check และ flutter test จะล้มเหลวเมื่อ CSS ไม่ตรงไฟล์ generated ไม่ควรแก้ app_palette.dart/style_tokens.dart ด้วยมือหรือปล่อยให้ไฟล์สองชุดต่างกัน

## ตัวแปรที่ใช้บ่อย

| CSS variable | ผลที่ใช้จริง |
| --- | --- |
| --color-brand / --color-brand-ink | สีปุ่มหลักและสีโลโก้/ตัวอักษรบนแบรนด์ |
| --color-sos | สัญลักษณ์และพื้น SOS ผ่าน AppColors.sos |
| --color-rescue-strong | พื้นเน้นของหน่วยกู้ภัยที่ยืนยันแล้ว |
| --color-map-pin | หมุดตำแหน่งบนแผนที่และ preview |
| --background / --surface / --surface-soft | พื้นหน้าจอ/การ์ด ตาม light หรือ dark |
| --text / --muted / --border | ตัวอักษรหลัก/รอง/เส้นขอบ ตาม light หรือ dark |
| --font-family | ฟอนต์ใน text theme; หากเพิ่มฟอนต์ใหม่ต้องมี asset/ประกาศใน pubspec.yaml |
| --control-radius | ความโค้งของปุ่มและช่องกรอกที่ใช้ธีมกลาง |
| --card-radius / --card-padding | รูปร่าง/ช่องว่างภายในการ์ดร่วม |
| --minimum-tap-size / --button-height | ขนาดขั้นต่ำของปุ่มร่วม |

## ขอบเขต CSS ที่รองรับ

รองรับ custom properties ใน :root, [data-theme="light"], [data-theme="dark"] ค่าเป็นสี #RRGGBB, ขนาด px, ชื่อฟอนต์หนึ่งชื่อในเครื่องหมายคำพูด และการอ้างตัวแปรด้วย var(--name) ขนาด px ในชุดนี้แปลงเป็น Flutter logical pixels ไม่ใช่จำนวน physical pixels บนจอ

นี่เป็นตัวแปลง **ชุดตัวแปรสไตล์** ไม่ใช่ CSS engine ครบมาตรฐาน จึงไม่รองรับ selector ของปุ่มแต่ละตัว, flex/grid, media queries, hover, animation หรือ cascade ทุกแบบ การจัดวาง/การโต้ตอบยังอยู่ใน Widget และ ThemeData ค่าความโปร่งใสที่เปลี่ยนตามสถานะยังคำนวณใน Dart การเพิ่ม CSS ที่ไม่รองรับจะ error เพื่อไม่ให้คิดว่ารูปแบบถูกนำไปใช้แล้วทั้งที่ถูกละเลย

หากเกณฑ์อาจารย์บังคับให้ layout ทุกหน้าและ selector ต่าง ๆ ถูกประมวลผลด้วย CSS engine โดยตรง วิธีแปลงตัวแปรนี้ยังไม่เท่ากับเว็บ/Hybrid ที่ render HTML/CSS ต้องตกลงเกณฑ์นั้นแยกก่อนเปลี่ยนเทคโนโลยีทั้งแอป ไม่ควรอธิบายว่าแอปปัจจุบัน render ด้วย CSS โดยตรง

## สิ่งที่ตรวจและปรับในรอบนี้

เดิมมี theme.dart กลางอยู่แล้ว แต่ค่าสีโลโก้ สีเน้นกู้ภัย สีหมุด และ radius ของการ์ดบางส่วนกระจายอยู่ในหน้าจอ รวมค่าเหล่านี้มาใช้ชื่อกลางแล้ว ค่าเริ่มต้นเดิมทั้งโหมดสว่าง/มืดถูกคงไว้ ไม่เปลี่ยนขั้นตอนแชท SOS หรือการจัดเก็บ Supabase

สีบางชนิดที่มีความหมายเฉพาะ เช่น ขาวบนพื้น SOS/ตัวเล่นสื่อ สีโปร่งใส และสีสถานะมาตรฐาน ยังเป็นค่าคงที่หรือการคำนวณใน Widget ตามบทบาท ไม่ได้อ้างว่าทุกค่าการจัดวางทุกหน้าถูกย้ายเข้า CSS ทั้งหมด
