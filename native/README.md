# DailyMint Native Prototype

This is an in-progress migration, not a replacement for the Expo app.
It uses a separate identifier, com.ankit.dailymint.prototype, and separate storage.
It does not read or overwrite the existing DailyMint ledger.

## Implemented

- Kotlin Multiplatform core shared by Android and iOS: manual-entry validation,
  exact integer-paise amounts, categories, learned tagging, bank SMS parsing,
  import staging, deduplication, period analytics, and versioned JSON snapshots.
- Persistence: Android SharedPreferences and an atomically written iOS app-private file.
- Jetpack Compose and SwiftUI screens for Month, Growth, Manual, Plan, Import,
  and Settings; SwiftUI file import and staged review.
- Android foreground SMS reading with permission handling and inbox observation.
- iOS Shortcuts/App Intent action for sending a bank SMS directly to DailyMint.
- Capture-time-limited editing/deletion and category deletion with reassignment.
- Daily reminder settings and native reminder scheduling on both platforms.
- Raw SMS/debug details for parsed entries and recent unrecognized SMS diagnostics.
- Native Add Category dialogs; native input controls and keyboard handling.
- Shared tests for decimals, totals, invalid inputs, duplicate IDs, persistence,
  corrupt storage, failed writes, import idempotency, reminder settings,
  category remapping, custom tracking cycles, and edit/delete invariants.
- Android Compose and iOS XCTest flows for Save, Cancel, validation, decimal
  expenses, and income entries.

## Current verification results

- Shared engine: tests pass on JVM and on the Android unit-test target,
  including regression coverage for masked bank-message fixtures.
- Android UI/build: Compose interaction tests, app APK, and device-test APK compile
  locally on Windows with Java 17.
- Android app APK and device-test APK compiled successfully.
- iOS: source and XCTest suite are compiled and run through GitHub's macOS
  workflow. The latest green checkpoint before App Intent work was commit
  9cdba8c.
- Physical-device keyboard/geometry checks: pending on both platforms.

Robolectric tests validate state and simulated interactions. They do not prove that
the software keyboard and touch targets are correctly positioned on a real phone.

Month totals follow the configured cycle; Growth uses calendar periods.
The current Expo app remains the functional reference until the native app passes
TestFlight/device verification for the App Intent flow and any final release gates.

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
2. Compile the native iOS project and run iOS tests on the GitHub macOS runner.
3. Produce a signed archive on a cloud macOS runner and upload it to TestFlight.
   Native signing and upload configuration still need to be established.
4. Install the checkpoint through TestFlight and verify launch, category Save/Cancel,
   keyboard handling, file import, Shortcut/App Intent import, editing,
   persistence after relaunch, and chart totals.
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

## iOS Shortcut automation

The native iOS target exposes a Shortcuts action named `Import Bank SMS`.
For a message automation, pass the SMS body into the `Message` parameter and,
when available, pass the sender into `Sender`. The action writes through the
same shared KMP import pipeline as Android SMS ingestion.

## Next migration gates

1. Verify the iOS App Intent compiles on GitHub macOS and appears in Shortcuts
   after TestFlight install.
2. Validate Android SMS ingestion on a physical device with the direct-to-ledger
   flow.
3. Validate iOS file import and Shortcut import on a physical iPhone.
4. Run final device regression checks before replacing the Expo app.
5. Redesign the Android and iOS UI once functionality parity is stable.
