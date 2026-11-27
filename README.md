# RxPhone

แอป iOS สำหรับจัดการรูปภาพและวีดีโอในเครื่อง: ดู เลือก ลบ และทำความสะอาดคลังรูป
เขียนด้วย SwiftUI และ PhotoKit

*An iOS app for browsing, sorting and cleaning up the photo library (SwiftUI + PhotoKit). The UI is in Thai.*

## ความสามารถ

- **คลัง** — grid รูปและวีดีโอทั้งหมด แยก ทั้งหมด / รูปภาพ / วีดีโอ เรียงใหม่สุด เก่าสุด หรือไฟล์ใหญ่สุดก่อน
  - แตะเพื่อเลือกหลายรายการ หรือลากนิ้วเลือกเป็นช่วง (เลื่อนหน้าอัตโนมัติเมื่อลากถึงขอบ)
  - เลือกตามช่วงวันที่เพื่อลบเป็นชุด
- **หน้าดูรูปเต็มจอ** — ปัดเปลี่ยนรูป ซูม เล่นวีดีโอพร้อมแถบเลื่อนเวลา ชื่นชอบ ลบ และปัดลงเพื่อปิด
- **หมวดหมู่** — Live Photo, เซลฟี่, ภาพถ่ายหน้าจอ, วิดีโอบันทึกหน้าจอ, พาโนรามา, ภาพบุคคล, ถ่ายรัว, RAW,
  ภาพเคลื่อนไหว, สโลว์โมชัน, ไทม์แลปส์ และ Cinematic จาก smart album ของ iOS
- **ทำความสะอาด** — หารูปซ้ำแบบเหมือนกันเป๊ะ (เก็บไว้อย่างน้อย 1 รูปต่อกลุ่ม), วีดีโอตั้งแต่ 20 MB และภาพหน้าจอ
  - สแกนเฉพาะรูปใหม่โดยจำผลของรูปเดิมไว้ในเครื่อง และไม่ดาวน์โหลดรูปจาก iCloud
  - อัปเดตเองเมื่อคลังรูปเปลี่ยน
- การลบทุกครั้งผ่านหน้าต่างยืนยันของ iOS และย้ายไปอัลบั้ม "ลบล่าสุด" (กู้คืนได้ภายใน 30 วัน)

## ความต้องการ

- Xcode 26 ขึ้นไป, iOS 18 ขึ้นไป
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — ไฟล์โปรเจกต์สร้างจาก `project.yml`

## เริ่มใช้งาน

```bash
xcodegen generate
open RxPhone.xcodeproj
```

รันบน Simulator ได้ทันที ถ้าจะรันบน iPhone จริง ให้ใส่ Apple Team ID ของคุณเอง:

```bash
cp Local.xcconfig.example Local.xcconfig
# แก้ DEVELOPMENT_TEAM ใน Local.xcconfig (git ไม่เก็บไฟล์นี้)
```

ถ้าจะใช้ Bundle ID ของตัวเอง ให้แก้ `bundleIdPrefix` และ `PRODUCT_BUNDLE_IDENTIFIER` ใน `project.yml`
แล้วรัน `xcodegen generate` ใหม่

## เทสต์

```bash
xcodebuild test -project RxPhone.xcodeproj -scheme RxPhone \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

- **Unit test** (Swift Testing, `RxPhoneTests`) — ตรรกะที่ไม่ผูกกับหน้าจอ เช่น การหารูปซ้ำ การเลือกช่วง
  เกณฑ์ทำความสะอาด และการจำค่าต่างๆ
- **UI test** (XCUITest, `RxPhoneUITests`) — ควบคุมแอปจริงใน Simulator ต้องให้สิทธิ์เข้าถึงรูปภาพ
  และมีรูปอย่างน้อย 3 รูป รวมถึงรูปซ้ำ 1 คู่ และวีดีโอ 1 ไฟล์ ทุกเทสต์กด "ไม่อนุญาต" ตอนระบบถามยืนยันลบ
  คลังรูปจึงไม่ถูกแก้ไข

## หมายเหตุ

ขนาดไฟล์อ่านจากคีย์ `fileSize` ของ `PHAssetResource` ซึ่งไม่ใช่ API ทางการของ Apple
ใช้งานได้ตามปกติ แต่อาจไม่ผ่านการตรวจถ้าส่งขึ้น App Store

ดูรายการเปลี่ยนแปลงทั้งหมดได้ที่ [changelog.md](changelog.md)

## License

[MIT](LICENSE)
