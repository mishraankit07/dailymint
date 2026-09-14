# Native prototype to TestFlight from Windows

This workflow builds SwiftUI/Kotlin, not Expo. It is manual-only and uploads only
`com.ankit.dailymint.prototype` (version 0.1.0). Existing DailyMint data and its
TestFlight listing are not replaced. Apple signing/upload has not been validated
until a run with your credentials succeeds.

## One-time Apple setup

1. Register an explicit App ID `com.ankit.dailymint.prototype` in Apple Developer.
2. Create an iOS app in App Store Connect using that ID, name DailyMint Prototype
   (or an available variant), and a unique SKU such as dailymint-native-prototype.
3. Obtain your Apple Distribution certificate **with its private key**, exported
   as a password-protected `.p12`. An existing valid certificate from EAS can be
   reused on the same Apple team; a `.cer` download alone is insufficient.
   Use the Expo project's `npx eas-cli credentials -p ios` to inspect/download
   your existing distribution credentials, without revoking them. Keep downloaded
   credentials outside the repository.
4. Create and download an **App Store Connect distribution** provisioning profile
   for the prototype ID using that certificate. Do not reuse the Expo app profile.
5. In App Store Connect, Users and Access > Integrations, create a team API key
   with access sufficient to upload this app (Developer or App Manager as needed).
   Download the `.p8` and note the Key ID and Issuer ID. Never paste private keys
   or passwords into chat or commit them to git.

## GitHub secrets

Run in PowerShell after `gh auth login`. Replace the sample paths with actual
downloaded files. These commands send credentials to your private repository's
GitHub Actions Secrets, not to repository files.

```powershell
$repo = 'mishraankit07/dailymint'
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\secure\distribution.p12')) | gh secret set IOS_CERTIFICATE_BASE64 --repo $repo
gh secret set IOS_CERTIFICATE_PASSWORD --repo $repo
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\secure\prototype.mobileprovision')) | gh secret set IOS_PROFILE_BASE64 --repo $repo
Get-Content -Raw 'C:\secure\AuthKey_YOURKEYID.p8' | gh secret set ASC_PRIVATE_KEY --repo $repo
gh secret set ASC_KEY_ID --repo $repo
gh secret set ASC_ISSUER_ID --repo $repo
```

The commands without piped input prompt for the value. Restrict who can edit
workflows or run code in this repository: workflows can access these secrets.

## Every build

Commit and push the desired checkpoint first, then:

```powershell
gh workflow run native-testflight.yml --repo mishraankit07/dailymint --ref main
gh run list --repo mishraankit07/dailymint --workflow native-testflight.yml --limit 5
gh run watch RUN_ID --repo mishraankit07/dailymint --exit-status
```

Replace RUN_ID with the newly started run's ID. Build numbers use the workflow
run number and attempt, so rerunning a build does not reuse its number.
The workflow reruns iOS tests on a current Xcode (minimum 26), then signs and
uploads. It never submits to App Review or automatically adds external testers.
After Apple processing, open DailyMint Prototype > TestFlight, answer any export
compliance questions, and add the build to your internal tester group. External
testing may require beta review. TestFlight builds are not ad-hoc IPA installs.

## Troubleshooting

- Missing secret: add all six secrets above.
- Signing mismatch: profile and `.p12` must use the same certificate and team.
- Wrong profile: must be App Store distribution for the prototype bundle ID.
- Upload permission/app not found: verify the App Store Connect record and API
  key's team, role, and app access.
- The previous simulator job used Xcode 16.4. A green run there does not guarantee
  the new Xcode 26+ release gate passes; do not bypass failures to upload.

References:
- https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications
- https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
- https://developer.apple.com/news/upcoming-requirements/
