#!/bin/sh
# 生成未签名的 IPA：Release、不签名，打包成 Payload/Voltane.app。安装前用自签工具签名。
set -eu
cd "$(dirname "$0")/.."
OUT=build/ipa
rm -rf "$OUT"
mkdir -p "$OUT/Payload"
xcodebuild -project Voltane.xcodeproj -scheme Voltane -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData-device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build -quiet
cp -R build/DerivedData-device/Build/Products/Release-iphoneos/Voltane.app "$OUT/Payload/"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$OUT/Payload/Voltane.app/Info.plist")
(cd "$OUT" && zip -qry "../Voltane-$VERSION-unsigned.ipa" Payload)
echo "已生成 build/Voltane-$VERSION-unsigned.ipa"
