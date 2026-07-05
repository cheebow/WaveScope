#!/bin/bash
# WaveScope のリリースビルドを作成し、Developer ID 署名 → 公証 → GitHub Release 添付まで行う。
#
# 前提:
#   - キーチェーンに "Developer ID Application" 証明書があること
#   - notarytool の認証プロファイル "notarytool" が保存済みであること
#     (xcrun notarytool store-credentials notarytool --apple-id ... --team-id ...)
#   - gh CLI でログイン済みであること
#
# 使い方(リポジトリルートから):
#   ./Scripts/release.sh              # ビルド〜公証〜GitHub Release 作成まで
#   ./Scripts/release.sh --no-release # GitHub Release 作成をスキップ(zip 生成まで)
set -euo pipefail

cd "$(dirname "$0")/../WaveScope"

NOTARY_PROFILE="notarytool"
SCHEME="WaveScope"
OUT="build/release"
ARCHIVE="$OUT/WaveScope.xcarchive"
EXPORT_DIR="$OUT/export"
APP="$EXPORT_DIR/WaveScope.app"

VERSION=$(xcodebuild -project WaveScope.xcodeproj -scheme "$SCHEME" -showBuildSettings 2>/dev/null |
    awk '/MARKETING_VERSION/ { print $3; exit }')
TAG="v$VERSION"
ZIP="$OUT/WaveScope-$VERSION.zip"

echo "==> リリースビルド $TAG"
rm -rf "$OUT"

echo "==> アーカイブ"
xcodebuild archive \
    -project WaveScope.xcodeproj -scheme "$SCHEME" -configuration Release \
    -archivePath "$ARCHIVE" -quiet

echo "==> Developer ID でエクスポート"
cat > "$OUT/exportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$OUT/exportOptions.plist" -quiet

echo "==> 公証(notarization)"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

echo "==> 検証"
spctl -a -vv "$APP"

echo "==> 配布用 zip 作成"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "    $ZIP"

if [[ "${1:-}" == "--no-release" ]]; then
    echo "==> --no-release 指定のため GitHub Release はスキップ"
    exit 0
fi

echo "==> GitHub Release $TAG を作成"
gh release create "$TAG" "$ZIP" --title "$TAG" --generate-notes
echo "==> 完了"
