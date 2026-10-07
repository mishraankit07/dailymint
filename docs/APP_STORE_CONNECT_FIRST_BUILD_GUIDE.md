# First iOS Build to App Store Connect from CI

This guide is intentionally project agnostic. It explains how to register an iOS
app, create signing credentials, store them as GitHub Actions secrets, and upload
the first signed build to App Store Connect.

The example uses:

- A native Xcode project or workspace.
- Manual distribution signing in CI.
- GitHub Actions with a hosted macOS runner.
- An App Store Connect team API key for authentication.
- `xcodebuild` for archive/export and `xcrun altool` for upload.

Adapt the non-secret placeholders to the project. Never commit the real values or
credential files described here.

## 1. Prerequisites

You need:

- An active Apple Developer Program membership.
- Access to Apple Developer and App Store Connect.
- An Account Holder or Admin for identifiers, certificates, and profiles.
- An Account Holder, Admin, or App Manager to create the app record.
- A GitHub repository with Actions enabled.
- A build that succeeds on a supported Xcode release.

Before continuing, ensure the Account Holder has accepted current agreements in
App Store Connect. Apple will not allow a new app record while required agreements
are pending.

As of October 2026, Apple requires iOS uploads to be built with Xcode 26 or later.
Requirements change, so check [Apple's supported Xcode versions](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
before pinning a runner or Xcode version.

## 2. Decide the permanent identifiers

Choose these values before creating anything in Apple portals:

| Placeholder | Example | Notes |
| --- | --- | --- |
| `APP_NAME` | `Example App` | Customer-facing App Store name. |
| `BUNDLE_ID` | `com.example.product` | Permanent, globally unique, and identical in Xcode, the App ID, profile, and App Store Connect record. |
| `SKU` | `example-product-ios` | Internal App Store Connect identifier; it is not shown to customers. |
| `TEAM_ID` | `ABCDE12345` | Apple Developer team identifier. |
| `SCHEME` | `ExampleApp` | Shared Xcode scheme used for archive. |
| `PROJECT_OR_WORKSPACE` | `ios/ExampleApp.xcodeproj` | Use either a project or workspace. |
| `MARKETING_VERSION` | `1.0.0` | User-facing version, stored as `CFBundleShortVersionString`. |
| `BUILD_NUMBER` | `1` | Unique build string for that app version, stored as `CFBundleVersion`. |

Do not use a wildcard bundle ID for an App Store app. Register an explicit App ID
that exactly matches `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode target.

## 3. Register the App ID

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list):

1. Open **Identifiers** and select **+**.
2. Choose **App IDs**, then **App**.
3. Enter a description.
4. Select **Explicit App ID**.
5. Enter `BUNDLE_ID` exactly.
6. Enable only the capabilities used by the Xcode target.
7. Review and register it.

If the target later adds capabilities such as Push Notifications, Associated
Domains, Sign in with Apple, or iCloud, update the App ID and regenerate the
provisioning profile. See Apple's [App ID instructions](https://developer.apple.com/help/account/identifiers/register-an-app-id/).

## 4. Create the App Store Connect app record

Create the record before the first binary upload:

1. Open **App Store Connect > Apps**.
2. Select **+ > New App**.
3. Select iOS.
4. Enter `APP_NAME`, primary language, `BUNDLE_ID`, and a unique `SKU`.
5. Choose full or limited user access.
6. Select **Create**.

The bundle ID in this record must be the same one embedded in the uploaded app.
Apple uses the bundle ID and marketing version to associate an upload with this
record. See [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).

## 5. Create an Apple Distribution certificate

The CI runner needs a distribution certificate **and its private key**. A `.cer`
file by itself is not sufficient.

Recommended process on a trusted Mac:

1. Open **Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority**.
2. Save the certificate signing request (`.certSigningRequest`) to disk.
3. In Apple Developer, open **Certificates** and select **+**.
4. Choose **Apple Distribution** and upload the signing request.
5. Download and install the resulting `.cer` in the same Mac keychain that created the request.
6. In Keychain Access, open **My Certificates** and confirm the certificate expands to show its private key.
7. Export the certificate and private key together as a password-protected `.p12`.

Choose a strong, unique export password. That password becomes the
`IOS_CERTIFICATE_PASSWORD` secret.

If a valid distribution `.p12` already exists for the same Apple team, it can be
reused. Do not revoke a certificate merely to create a new CI setup; revocation
can break other release pipelines using it.

Apple treats distribution certificates as sensitive identity material. Keep the
`.p12`, its password, and any unencrypted private key outside the repository.

## 6. Create the App Store Connect provisioning profile

In **Certificates, Identifiers & Profiles > Profiles**:

1. Select **+**.
2. Under Distribution, choose **App Store Connect** for iOS.
3. Select the explicit App ID matching `BUNDLE_ID`.
4. Select the Apple Distribution certificate exported in the previous section.
5. Name, generate, and download the `.mobileprovision` file.

An App Store Connect profile contains one distribution certificate. The profile,
certificate, team, bundle ID, and target entitlements must agree. See Apple's
[profile creation guide](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile).

Regenerate the profile when relevant App ID capabilities or distribution
certificates change.

## 7. Create an App Store Connect API key

Use a **Team API Key** for CI:

1. Open **App Store Connect > Users and Access > Integrations**.
2. Select **App Store Connect API > Team Keys**.
3. Generate a key with the least role that can perform the required upload. A
   Developer or App Manager role is normally appropriate; use app access limits
   where available.
4. Record the **Key ID**.
5. Record the team's **Issuer ID**.
6. Download `AuthKey_<KEY_ID>.p8` immediately.

Apple permits the private `.p8` key to be downloaded only once and does not retain
a recoverable copy. Store it securely. If it is lost or exposed, revoke it and
create a replacement. See [Creating API keys for App Store Connect](https://developer.apple.com/documentation/AppStoreConnectAPI/creating-api-keys-for-app-store-connect-api).

The three API-key values used by CI are:

- `ASC_PRIVATE_KEY`: complete text of the `.p8`, including the BEGIN/END lines.
- `ASC_KEY_ID`: Key ID displayed beside the key.
- `ASC_ISSUER_ID`: Issuer ID displayed on the Team Keys page.

Do not confuse the App Store Connect API key with an Apple Account password,
app-specific password, signing certificate, or provisioning profile. They solve
different parts of the release process.

## 8. Add the six GitHub Actions secrets

The reusable secret contract is:

| Secret | Value |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | Base64 encoding of the binary `.p12`. |
| `IOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12`. |
| `IOS_PROFILE_BASE64` | Base64 encoding of the binary `.mobileprovision`. |
| `ASC_PRIVATE_KEY` | Raw contents of `AuthKey_<KEY_ID>.p8`. |
| `ASC_KEY_ID` | App Store Connect API Key ID. |
| `ASC_ISSUER_ID` | App Store Connect team Issuer ID. |

Base64 is transport encoding, not encryption. The encoded files must still be
stored only in a secret manager.

### Recommended scope

For a production repository, create a GitHub Environment such as
`app-store-production`, add the secrets there, and configure required reviewers.
The upload job must declare that environment. Repository secrets are acceptable
for a small private repository when access to workflow edits and dispatch is
tightly controlled.

GitHub documents repository, organization, and environment secrets in
[Secrets](https://docs.github.com/en/actions/concepts/security/secrets).

### Set secrets from PowerShell

After installing GitHub CLI and running `gh auth login`:

```powershell
$repo = 'YOUR_ORG/YOUR_REPOSITORY'
$p12 = 'C:\secure\distribution.p12'
$profile = 'C:\secure\app-store.mobileprovision'
$apiKey = 'C:\secure\AuthKey_YOUR_KEY_ID.p8'

[Convert]::ToBase64String([IO.File]::ReadAllBytes($p12)) |
  gh secret set IOS_CERTIFICATE_BASE64 --repo $repo

gh secret set IOS_CERTIFICATE_PASSWORD --repo $repo

[Convert]::ToBase64String([IO.File]::ReadAllBytes($profile)) |
  gh secret set IOS_PROFILE_BASE64 --repo $repo

Get-Content -Raw -LiteralPath $apiKey |
  gh secret set ASC_PRIVATE_KEY --repo $repo

gh secret set ASC_KEY_ID --repo $repo
gh secret set ASC_ISSUER_ID --repo $repo
```

Commands without piped input prompt securely for the value. Add
`--env app-store-production` to each `gh secret set` command when using
environment secrets.

### Set secrets from macOS or Linux

```bash
repo='YOUR_ORG/YOUR_REPOSITORY'

base64 < /secure/distribution.p12 | tr -d '\n' |
  gh secret set IOS_CERTIFICATE_BASE64 --repo "$repo"

gh secret set IOS_CERTIFICATE_PASSWORD --repo "$repo"

base64 < /secure/app-store.mobileprovision | tr -d '\n' |
  gh secret set IOS_PROFILE_BASE64 --repo "$repo"

gh secret set ASC_PRIVATE_KEY --repo "$repo" < /secure/AuthKey_YOUR_KEY_ID.p8
gh secret set ASC_KEY_ID --repo "$repo"
gh secret set ASC_ISSUER_ID --repo "$repo"
```

GitHub does not reveal secret values after creation. Confirm the names with:

```bash
gh secret list --repo YOUR_ORG/YOUR_REPOSITORY
```

## 9. Prepare the Xcode project

Before running CI, confirm:

- `PRODUCT_BUNDLE_IDENTIFIER` equals `BUNDLE_ID`.
- The Release configuration uses the intended app target and shared scheme.
- `MARKETING_VERSION` is a valid version such as `1.0.0`.
- `CURRENT_PROJECT_VERSION` is a unique build string such as `1`.
- The deployment target and device families match the App Store listing.
- App icons and launch resources are complete.
- Target capabilities match the explicit App ID and profile entitlements.
- Export-compliance configuration is accurate.
- The archive does not depend on local, uncommitted files.

Every upload for a given marketing version needs a build string not previously
uploaded for that app. Apple does not rename an uploaded binary. Changing either
the version or build number requires creating and uploading another archive.

## 10. Minimal GitHub Actions workflow

This skeleton intentionally runs only when manually dispatched. Replace the
project values and build commands. If using environment secrets, keep the
`environment` line; otherwise remove it.

```yaml
name: Upload iOS build

on:
  workflow_dispatch:
    inputs:
      marketing_version:
        description: App version, for example 1.0.0
        required: true
        default: 1.0.0
      build_number:
        description: Unique App Store Connect build number
        required: true

permissions:
  contents: read

concurrency:
  group: ios-app-store-upload
  cancel-in-progress: false

jobs:
  upload:
    runs-on: macos-15
    environment: app-store-production
    timeout-minutes: 60
    env:
      IOS_PROJECT: ios/ExampleApp.xcodeproj
      IOS_SCHEME: ExampleApp
      IOS_BUNDLE_ID: com.example.product
      IOS_MARKETING_VERSION: ${{ inputs.marketing_version }}
      IOS_BUILD_NUMBER: ${{ inputs.build_number }}
      IOS_CERTIFICATE_BASE64: ${{ secrets.IOS_CERTIFICATE_BASE64 }}
      IOS_CERTIFICATE_PASSWORD: ${{ secrets.IOS_CERTIFICATE_PASSWORD }}
      IOS_PROFILE_BASE64: ${{ secrets.IOS_PROFILE_BASE64 }}
      ASC_PRIVATE_KEY: ${{ secrets.ASC_PRIVATE_KEY }}
      ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
      ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - name: Validate required secrets
        shell: bash
        run: |
          set -euo pipefail
          for name in IOS_CERTIFICATE_BASE64 IOS_CERTIFICATE_PASSWORD IOS_PROFILE_BASE64 ASC_PRIVATE_KEY ASC_KEY_ID ASC_ISSUER_ID; do
            test -n "${!name}" || { echo "Missing secret: $name"; exit 1; }
          done

      - name: Run project tests
        run: ./ci/test-ios.sh

      - name: Archive, export, and upload
        run: bash ./ci/upload-ios.sh
```

Pin third-party actions to a reviewed commit SHA when adopting this in a
high-assurance production repository.

## 11. What the upload script must do

Implement `ci/upload-ios.sh` using the following sequence:

1. Enable strict shell behavior with `set -euo pipefail` and `umask 077`.
2. Create a temporary directory and temporary keychain under `$RUNNER_TEMP`.
3. Decode `IOS_CERTIFICATE_BASE64` to `certificate.p12`.
4. Decode `IOS_PROFILE_BASE64` to `profile.mobileprovision`.
5. Decode the profile with `security cms -D` and validate:
   - It is not expired.
   - `get-task-allow` is false.
   - It has no `ProvisionedDevices` or `ProvisionsAllDevices` value.
   - Its application identifier ends with `IOS_BUNDLE_ID`.
   - Its team matches the certificate/project team.
6. Create and unlock a temporary keychain.
7. Import the `.p12` with `IOS_CERTIFICATE_PASSWORD`.
8. Run `security set-key-partition-list` so `codesign` can use the key without an interactive prompt.
9. Install the profile temporarily under `~/Library/MobileDevice/Provisioning Profiles/`.
10. Create `ExportOptions.plist` with:
    - `method` set to `app-store-connect`.
    - `signingStyle` set to `manual`.
    - The team ID, Apple Distribution certificate, and profile UUID.
    - `manageAppVersionAndBuildNumber` set to false.
11. Archive with `xcodebuild archive`, including:
    - Release configuration.
    - `generic/platform=iOS` destination.
    - `MARKETING_VERSION="$IOS_MARKETING_VERSION"`.
    - `CURRENT_PROJECT_VERSION="$IOS_BUILD_NUMBER"`.
    - Explicit distribution signing values.
12. Export the archive with `xcodebuild -exportArchive`.
13. Write `ASC_PRIVATE_KEY` to `AuthKey_$ASC_KEY_ID.p8` in a private temporary directory.
14. Point `API_PRIVATE_KEYS_DIR` at that directory.
15. Validate or upload the single exported IPA:

```bash
xcrun altool --validate-app \
  --type ios \
  --file path/to/App.ipa \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

xcrun altool --upload-app \
  --type ios \
  --file path/to/App.ipa \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"
```

16. Use an `EXIT` trap to delete the temporary keychain, provisioning profile,
    `.p12`, `.p8`, decoded profile, and exported signing metadata even when a step fails.

For a workspace, use `-workspace "$IOS_WORKSPACE"`; for a project, use
`-project "$IOS_PROJECT"`. Do not pass both.

## 12. Push the first build

1. Commit and push the exact source revision to build.
2. Verify all required tests pass before the signing step.
3. Manually dispatch the upload workflow.
4. Supply `MARKETING_VERSION` such as `1.0.0` and a unique `BUILD_NUMBER` such as `1`.
5. Watch the workflow and retain the commit SHA, version, build number, and run URL.
6. Wait for Apple to process the upload. A successful command-line upload does not
   mean processing has completed.
7. In App Store Connect, open the app's **TestFlight** page and inspect the build.
8. Resolve export-compliance questions or processing warnings.
9. Add the build to an internal testing group and complete a device smoke test.

Apple creates the initial beta version after the first upload, but processing can
take time. See [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds).

## 13. Move the tested build toward App Review

Uploading a build does not submit it for review. After testing:

1. Create or open the intended App Store version in App Store Connect.
2. Complete app metadata, category, age rating, pricing and availability, privacy
   disclosures, support URL, privacy-policy URL, screenshots, and review notes.
3. In the version's **Build** section, select the processed build.
4. Complete export-compliance information.
5. Save and use **Add for Review** or the current App Store Connect submission flow.

Only one build can be selected for an app version at a time, although it can be
changed before submission. See [Choose a build to submit](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit/).

For a production candidate rebuilt from a previously tested commit, record that
source SHA and rerun the complete test suite. A marketing-version change is a new
binary build, not a metadata-only rename of the TestFlight artifact.

## 14. Security rules

- Never commit `.p8`, `.p12`, `.cer`, `.mobileprovision`, decoded profiles, or passwords.
- Do not print secrets, decoded key material, or complete provisioning profiles in logs.
- Restrict who can edit workflows and dispatch production jobs.
- Prefer a protected GitHub Environment with required reviewers.
- Keep upload workflows manual unless automated releases are an explicit requirement.
- Give the API key the least role and app access required.
- Do not run credential-bearing workflows for untrusted fork pull requests.
- Rotate credentials when a team member leaves or compromise is suspected.
- Revoke an exposed App Store Connect API key immediately.
- Track certificate, profile, and API-key ownership and expiry dates outside source control.
- Keep build artifacts private and use short retention periods when they contain a signed IPA.

## 15. Troubleshooting

### Missing secret

Confirm all six names exist at the same GitHub scope used by the job. An
environment secret is unavailable unless the job declares that environment.

### No signing certificate found

The `.p12` may contain only the public certificate, have the wrong password, be
expired, or belong to another team. Re-export it from **My Certificates** with its
private key.

### Provisioning profile does not include signing certificate

Regenerate the App Store Connect profile using the same Apple Distribution
certificate contained in the `.p12`.

### Application identifier entitlement mismatch

Compare the target's `PRODUCT_BUNDLE_IDENTIFIER` with the profile's
`application-identifier` after the team prefix. They must match exactly.

### App record not found or API authorization failed

Confirm the app record exists on the same Apple team as the API key and profile.
Check the key role, app access, Key ID, Issuer ID, and whether the key was revoked.

### Build number already used

Increase `CURRENT_PROJECT_VERSION`. App Store Connect build strings cannot be
reused for the same app version, including builds that were uploaded and later
expired or removed from testing.

### Upload succeeded but no build appears

Wait for processing and check App Store Connect's build upload status and email.
Inspect processing errors, export compliance, and the version embedded in the IPA.

### Invalid entitlements

Ensure the Xcode target, explicit App ID, and provisioning profile enable the same
capabilities. Regenerate the profile after changing App ID capabilities.

### Unsupported SDK or Xcode

Move to an Apple-supported Xcode/SDK and rebuild. Do not bypass the release gate
by uploading an archive produced by an obsolete toolchain.

## 16. First-build checklist

- [ ] Apple Developer membership and agreements are active.
- [ ] Explicit App ID matches the Xcode bundle ID.
- [ ] App Store Connect app record exists.
- [ ] Apple Distribution `.p12` contains its private key.
- [ ] App Store Connect provisioning profile matches app, team, certificate, and capabilities.
- [ ] Team API key `.p8`, Key ID, and Issuer ID are available.
- [ ] All six CI secrets are configured at the intended scope.
- [ ] Production environment approvals and workflow permissions are configured.
- [ ] Release tests pass on a supported Xcode version.
- [ ] Marketing version and build number are correct and unused.
- [ ] Signed archive exports successfully.
- [ ] Upload succeeds and Apple processing completes.
- [ ] Internal TestFlight smoke test passes on a real device.
- [ ] App Store metadata, privacy, support, screenshots, and review details are complete.
- [ ] The processed build is selected before submission to App Review.

