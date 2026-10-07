# VietPickleball cho iPhone

App iOS của [VietPickleball.vn](https://vietpickleball.vn) — nền tảng giải đấu, xếp hạng Trình VPB, đặt sân và quản lý sân pickleball.

- Mã nguồn Swift (WKWebView) trong `Sources/`, dự án Xcode tạo bằng XcodeGen (`project.yml`).
- GitHub Actions (`.github/workflows/ios.yml`) build trên máy macOS, chụp ảnh màn hình App Store từ máy ảo iPhone 6.9", ký bằng khóa API App Store Connect và tải lên TestFlight.
- Cần 3 secret của repo: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (nội dung tệp AuthKey_xxx.p8).
