#!/usr/bin/env bash
set -euo pipefail
umask 077
SIGNING_DIR=$(mktemp -d "$RUNNER_TEMP/dailymint-signing.XXXXXX")
KEYCHAIN="$SIGNING_DIR/signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
PROFILE_DEST=""
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  if [ -n "$PROFILE_DEST" ]; then rm -f "$PROFILE_DEST"; fi
  rm -rf "$SIGNING_DIR"
}
trap cleanup EXIT
export SIGNING_DIR
printf '%s' "$IOS_CERTIFICATE_BASE64" | base64 --decode > "$SIGNING_DIR/certificate.p12"
printf '%s' "$IOS_PROFILE_BASE64" | base64 --decode > "$SIGNING_DIR/profile.mobileprovision"
security cms -D -i "$SIGNING_DIR/profile.mobileprovision" > "$SIGNING_DIR/profile.plist"

# Validate the profile before importing credentials or signing the wrong app.
python3 - <<'PY'
import datetime, os, pathlib, plistlib
directory = pathlib.Path(os.environ['SIGNING_DIR'])
with (directory / 'profile.plist').open('rb') as stream:
    profile = plistlib.load(stream)
bundle = 'com.ankit.dailymint.prototype'
team = profile['TeamIdentifier'][0]
entitlements = profile['Entitlements']
assert entitlements['application-identifier'].endswith('.' + bundle), 'Profile must belong to DailyMint Prototype'
assert not entitlements.get('get-task-allow'), 'Use an App Store distribution profile, not development'
assert not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'), 'Use an App Store profile, not Ad Hoc or Enterprise'
assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Profile expired'
options = dict(method='app-store-connect', signingStyle='manual', teamID=team,
               signingCertificate='Apple Distribution',
               provisioningProfiles={bundle: profile['UUID']},
               manageAppVersionAndBuildNumber=False, uploadSymbols=True)
with (directory / 'ExportOptions.plist').open('wb') as stream:
    plistlib.dump(options, stream)
PY
TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$SIGNING_DIR/profile.plist")
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$SIGNING_DIR/profile.plist")
PROFILE_DEST="$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"
mkdir -p "$(dirname "$PROFILE_DEST")"
cp "$SIGNING_DIR/profile.mobileprovision" "$PROFILE_DEST"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$SIGNING_DIR/certificate.p12" -P "$IOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"

mkdir -p iosApp/build
BUILD_NUMBER="${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}"
xcodebuild archive -project iosApp/DailyMintNative.xcodeproj -scheme DailyMintNative \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath iosApp/build/DailyMintNative.xcarchive \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Apple Distribution' PROVISIONING_PROFILE_SPECIFIER="$PROFILE_UUID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
xcodebuild -exportArchive -archivePath iosApp/build/DailyMintNative.xcarchive \
  -exportOptionsPlist "$SIGNING_DIR/ExportOptions.plist" -exportPath iosApp/build/export

mkdir -p "$SIGNING_DIR/private_keys"
printf '%s' "$ASC_PRIVATE_KEY" > "$SIGNING_DIR/private_keys/AuthKey_$ASC_KEY_ID.p8"
export API_PRIVATE_KEYS_DIR="$SIGNING_DIR/private_keys"
shopt -s nullglob
ipas=(iosApp/build/export/*.ipa)
test "${#ipas[@]}" -eq 1 || { echo 'Expected exactly one exported IPA'; exit 1; }
xcrun altool --upload-app --type ios --file "${ipas[0]}" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
