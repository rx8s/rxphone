# RxPhone

แอป iOS สำหรับจัดการรูปภาพและวีดีโอในเครื่อง: ดู เลือก ลบ และทำความสะอาดคลังรูป
เขียนด้วย SwiftUI และ PhotoKit ไม่มีไลบรารีภายนอก

*An iOS app for browsing, sorting and cleaning up the photo library, built with SwiftUI and PhotoKit.
The UI is in Thai. [English summary below](#english).*

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

## ความเป็นส่วนตัว

- แอปไม่เชื่อมต่ออินเทอร์เน็ต ไม่มี analytics และไม่ส่งรูปหรือข้อมูลใดออกจากเครื่อง
- ใช้สิทธิ์เดียวคือคลังรูปภาพ รองรับทั้งให้สิทธิ์ทั้งหมดและให้สิทธิ์บางรูป
- ข้อมูลที่เก็บในเครื่องมีแค่ค่าตัวกรองและการเรียงลำดับ (UserDefaults) กับลายนิ้วมือภาพขนาด 64×64
  สำหรับหารูปซ้ำ (โฟลเดอร์ Caches ของแอป ระบบลบได้เมื่อพื้นที่เต็ม)

## ความต้องการ

- Xcode 26 ขึ้นไป, iOS 18 ขึ้นไป (iPhone)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — ถ้าจะแก้ `project.yml`
  ส่วน `RxPhone.xcodeproj` ที่อยู่ใน repo เปิดใช้ได้เลย

## เริ่มใช้งาน

```bash
git clone https://github.com/rx8s/rxphone.git
cd rxphone
open RxPhone.xcodeproj
```

รันบน Simulator ได้ทันที ถ้าจะรันบน iPhone จริง ให้ใส่ Apple Team ID ของคุณเอง:

```bash
cp Local.xcconfig.example Local.xcconfig
# แก้ DEVELOPMENT_TEAM ใน Local.xcconfig (git ไม่เก็บไฟล์นี้)
```

ถ้าจะใช้ Bundle ID ของตัวเอง ให้แก้ `bundleIdPrefix` และ `PRODUCT_BUNDLE_IDENTIFIER` ใน `project.yml`
แล้วรัน `xcodegen generate` ใหม่ (แก้ `project.yml` แทนการแก้ใน Xcode เพราะไฟล์โปรเจกต์จะถูกสร้างทับ)

## โครงสร้างโปรเจกต์

| ไฟล์ | หน้าที่ |
| --- | --- |
| `PhotoLibrary.swift` | สิทธิ์เข้าถึง โหลดรายการ ติดตามการเปลี่ยนแปลง และลบผ่าน PhotoKit |
| `LibraryView.swift`, `GridSelection.swift` | grid ที่ใช้ร่วมกันทั้งแท็บคลังและหมวดหมู่ การเลือกและลากเลือก |
| `AssetViewer.swift`, `ViewerMath.swift` | หน้าดูรูปเต็มจอ ซูม ปัด และเล่นวีดีโอ |
| `CategoriesView.swift`, `MediaCategory.swift` | แท็บหมวดหมู่จาก smart album |
| `CleanupView.swift`, `CleanupScanner.swift`, `CleanupRules.swift` | หน้าทำความสะอาด การสแกน และเกณฑ์ต่างๆ |
| `DuplicateMatcher.swift`, `FingerprintStore.swift` | หารูปซ้ำ และจำลายนิ้วมือภาพไว้ใน Caches |
| `tools/IconRender.swift` | วาดไอคอนแอปใหม่ด้วย SwiftUI |

ตรรกะที่ไม่ผูกกับหน้าจอแยกไว้ในไฟล์ของตัวเอง (`*Rules`, `*Math`, `*Matcher`, `*Store`) เพื่อให้เขียน unit test ได้

## เทสต์

```bash
xcodebuild test -project RxPhone.xcodeproj -scheme RxPhone \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

เปลี่ยน `name=` เป็น Simulator ที่มีในเครื่อง (`xcrun simctl list devices available`)

- **Unit test** (Swift Testing, `RxPhoneTests`) — ตรรกะที่ไม่ผูกกับหน้าจอ เช่น การหารูปซ้ำ การเลือกช่วง
  เกณฑ์ทำความสะอาด และการจำค่าต่างๆ
- **UI test** (XCUITest, `RxPhoneUITests`) — ควบคุมแอปจริงใน Simulator ต้องให้สิทธิ์เข้าถึงรูปภาพ
  และมีรูปอย่างน้อย 3 รูป รวมถึงรูปซ้ำ 1 คู่ และวีดีโอ 1 ไฟล์ ทุกเทสต์กด "ไม่อนุญาต" ตอนระบบถามยืนยันลบ
  คลังรูปจึงไม่ถูกแก้ไข

## ข้อจำกัด

- iOS ไม่ให้แอปเข้าถึงไฟล์ของแอปอื่น RxPhone จึงจัดการได้เฉพาะคลังรูปภาพ ล้างแคชหรือไฟล์ขยะของแอปอื่นไม่ได้
- ล้างอัลบั้ม "ลบล่าสุด" แบบถาวรต้องทำเองในแอปรูปภาพ PhotoKit ไม่มี API ให้
- หารูปซ้ำได้เฉพาะรูปที่เหมือนกันเป๊ะ รูปที่ภาพย่ออยู่ใน iCloud อย่างเดียวจะถูกข้าม (แอปแจ้งจำนวนให้)
- ขนาดไฟล์อ่านจากคีย์ `fileSize` ของ `PHAssetResource` ซึ่งไม่ใช่ API ทางการของ Apple
  ใช้งานได้ตามปกติ แต่อาจไม่ผ่านการตรวจถ้าส่งขึ้น App Store

## ร่วมพัฒนา

ยินดีรับ issue และ pull request ขอบเขตของแอปคือการจัดการรูปภาพและวีดีโอ

- เปิด issue คุยกันก่อนถ้าเป็นความสามารถใหม่
- เพิ่มหรือแก้เทสต์ให้ครอบคลุมตรรกะที่เปลี่ยน และให้ `xcodebuild test` ผ่าน
- บันทึกการเปลี่ยนแปลงไว้ใน [changelog.md](changelog.md)

## English

RxPhone is a small, offline iOS photo-library cleaner. Its features:

- **Library:** a grid of every photo and video, filterable by type and sortable by date or file size.
  You can tap to multi-select, drag-select a range (with auto-scroll) or select by date range.
- **Viewer:** a full-screen viewer with paging, pinch zoom and video scrubbing. You can favorite or delete
  from it, and swipe down to dismiss.
- **Categories:** iOS smart albums such as Live Photos, Selfies, Screenshots, Screen Recordings,
  Slo-mo and Cinematic.
- **Cleanup:** finds exact-duplicate photos (always keeping at least one per group), videos of 20 MB
  or more, and screenshots. Scans are incremental, using cached 64×64 fingerprints, and never download
  from iCloud.
- **Safe deletion:** every delete goes through the iOS confirmation sheet into Recently Deleted.

**Privacy:** the app makes no network calls and has no analytics. The only permission it needs is
Photos. **Build:** open `RxPhone.xcodeproj` in Xcode 26+ and run it on a simulator. To run on a device,
copy `Local.xcconfig.example` to `Local.xcconfig` and set your Team ID. The project file is generated
from `project.yml` with XcodeGen.

## License

[MIT](LICENSE)
