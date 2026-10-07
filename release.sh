#!/bin/bash
# Ký bằng khóa API App Store Connect (Xcode tự tạo chứng chỉ + hồ sơ), đóng gói và tải lên App Store Connect / TestFlight.
set -euo pipefail
: "${ASC_KEY_ID:?thiếu ASC_KEY_ID}" "${ASC_ISSUER_ID:?thiếu ASC_ISSUER_ID}" "${ASC_KEY_P8:?thiếu ASC_KEY_P8}"
KEYDIR="$HOME/.appstoreconnect/private_keys"; mkdir -p "$KEYDIR"
KEY="$KEYDIR/AuthKey_${ASC_KEY_ID}.p8"
printf '%s\n' "$ASC_KEY_P8" > "$KEY"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
BUILD=${BUILD_NUMBER:-$GITHUB_RUN_NUMBER}
xcodebuild -project VietPickleball.xcodeproj -scheme VietPickleball -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/VietPickleball.xcarchive \
  CURRENT_PROJECT_VERSION="$BUILD" "${AUTH[@]}" archive | tail -20
cat > build/ExportOptions.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>47U2Y457Q8</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PL
xcodebuild -exportArchive -archivePath build/VietPickleball.xcarchive -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export "${AUTH[@]}" | tail -30
rm -f "$KEY"
echo "Đã tải bản build $BUILD lên App Store Connect."
