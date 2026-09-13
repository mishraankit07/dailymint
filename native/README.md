# DailyMint Native Prototype

This is an in-progress migration, not a replacement for the Expo app.
It uses a separate identifier, com.ankit.dailymint.prototype, and separate storage.
It does not read or overwrite the existing DailyMint ledger.

## Implemented

- Kotlin Multiplatform core shared by Android and iOS: manual-entry validation,
  exact integer-paise amounts, categories, learned tagging, bank SMS parsing,
  import staging, deduplication, period analytics, and versioned JSON snapshots.
- Persistence: Android SharedPreferences and an atomically written iOS app-private file.
- Jetpack Compose and SwiftUI screens for Month, Growth, Manual, Plan, and Settings;
  SwiftUI file import and staged review.
- Android foreground SMS reading with permission handling and inbox observation.
- Capture-time-limited editing/deletion and category deletion with reassignment.
- Native Add Category dialogs; native input controls and keyboard handling.
- Shared tests for decimals, totals, invalid inputs, duplicate IDs, persistence,
  corrupt storage, and failed writes.
- Android Compose and iOS XCTest flows for Save, Cancel, validation and decimal entries.

## Current verification results

- Shared engine: 18 tests passed on JVM and on the Android unit-test target,
  including a regression test covering 28 masked bank-message fixtures.
- Android UI: 4 Compose interaction tests passed locally using Robolectric (API 35).
- Android app APK and device-test APK compiled successfully.
- Existing Expo app: all 89 tests still pass.
- iOS: source and XCTest suite added, but not compiled or executed yet (Mac required).
- Physical-device keyboard/geometry checks: pending on both platforms.

Robolectric tests validate state and simulated interactions. They do not prove that
the software keyboard and touch targets are correctly positioned on a real phone.

Month totals follow the configured cycle; Growth uses calendar periods.
App Intents, native reminder scheduling, developer feedback, and migration of
the existing app's data remain incomplete. The current Expo app remains the
functional reference. Native iOS source has not yet passed a compiler or device gate.

## Verification policy

After each logical change, run shared tests and both platform build/UI gates.
A platform that could not be executed must be reported as unverified.
Do not distribute this prototype as a replacement until BOTH platforms pass.
The GitHub workflow is configured, but adding the workflow locally does not run it.
It must be pushed to a GitHub repository with Actions enabled. Required branch checks
also need to be configured there before they can enforce merging restrictions.

Windows can compile Android and run shared JVM/Android tests.
iOS compilation, shared tests on the iOS runtime, and SwiftUI UI tests require macOS/Xcode.
The user has Windows and an iPhone, but no local macOS runtime. Do not require
local Xcode or a local iOS simulator as their verification workflow.

## iOS verification from Windows

1. Run the shared and Android checks locally after each logical change.
2. Compile the native iOS project and run iOS tests on a cloud macOS runner.
   The existing GitHub workflow describes this gate, but has not run yet.
3. Produce a signed archive on a cloud macOS runner and upload it to TestFlight.
   Native signing and upload configuration still need to be established.
4. Install the checkpoint through TestFlight and verify launch, category Save/Cancel,
   keyboard handling, import, editing, persistence after relaunch, and chart totals.
5. Record device results and address failures before advancing the release checkpoint.

The existing Expo EAS production profile builds the Expo app, not this native
SwiftUI/KMP project. Do not present those commands as a native prototype build.
Keep the prototype bundle identifier and storage isolated during verification.
Passing JVM or Android tests does not establish iOS runtime correctness.

## Android on this Windows machine

Use Java 17, not the Java 25 bundled with the current Android Studio.
Gradle 8.14.3 is available locally; a wrapper is also included.

```powershell
powershell -ExecutionPolicy Bypass -File .\verify-android.ps1
# Once an emulator or USB device is available:
powershell -ExecutionPolicy Bypass -File .\verify-android.ps1 -DeviceTests
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r .\androidApp\build\outputs\apk\debug\androidApp-debug.apk
```

## iOS on a Mac

Requires Java 17, Xcode with an iOS simulator, and XcodeGen.
From this directory:

```sh
chmod +x gradlew
./gradlew :shared:iosSimulatorArm64Test
brew install xcodegen
xcodegen generate --spec iosApp/project.yml
xcodebuild -list -project iosApp/DailyMintNative.xcodeproj
xcodebuild test -project iosApp/DailyMintNative.xcodeproj -scheme DailyMintNative -destination 'platform=iOS Simulator,name=iPhone 16'
```

Use iosX64Test on an Intel Mac; select an installed simulator name.
Xcode's build phase compiles and links the shared Kotlin framework.
For a physical iPhone, open the generated Xcode project, select your signing team,
and run the app. This is a native Xcode project, not an Expo Go project.

## Next migration gates

1. Verify Add Category and manual saving with keyboards visible on both platforms.
2. Compile and test the existing SwiftUI implementation on cloud macOS.
3. Validate Android SMS ingestion on a physical device.
4. Add an iOS App Intent inbox using the shared ingestion contract.
5. Finish reminders, feedback and tested legacy-data migration, then run full
   device regression checks before replacing the Expo app.
