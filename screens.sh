#!/bin/bash
# Build cho máy ảo iPhone màn hình 6.9", mở app ở nhiều trang và chụp ảnh màn hình cho App Store.
set -euo pipefail
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys,re
d=json.load(sys.stdin)["devices"]; best=None
for rt,devs in d.items():
    if "iOS" not in rt: continue
    v=tuple(int(x) for x in re.findall(r"\d+", rt.split("iOS")[-1])[:2])
    for x in devs:
        if "Pro Max" in x["name"]:
            k=(v, x["name"])
            if best is None or k>best[0]: best=(k,x["udid"],x["name"],rt)
print(best[1]); print(best[2], best[3], file=sys.stderr)')
echo "Simulator: $UDID"
xcodebuild -project VietPickleball.xcodeproj -scheme VietPickleball -configuration Debug \
  -sdk iphonesimulator -destination "id=$UDID" -derivedDataPath build/sim CODE_SIGNING_ALLOWED=NO build | tail -5
APP=build/sim/Build/Products/Debug-iphonesimulator/VietPickleball.app
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"
mkdir -p shots
i=1
for p in "" "?bxh=1" "?nangtrinh=1" "?sanchoi=1" "?chusan=1" "?huongdan=1"; do
  xcrun simctl terminate "$UDID" vn.vietpickleball.app 2>/dev/null || true
  xcrun simctl launch "$UDID" vn.vietpickleball.app -startPath "$p" -AppleLanguages "(vi)" -AppleLocale vi_VN
  sleep 18
  xcrun simctl io "$UDID" screenshot "shots/iphone69-$i.png"
  echo "shot $i: $p"; i=$((i+1))
done
ls -la shots
