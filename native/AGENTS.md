# Native prototype

Keep shared transaction rules in shared/src/commonMain; do not duplicate them in UI code.
Amounts are integer paise. Do not use floating-point for persistence or totals.
Publish UI changes only after persistence succeeds. Do not overwrite corrupt storage.
Run shared tests, Android build and interaction tests, and iOS build and interaction tests
after each logical change. Report unavailable platforms explicitly; never equate a JVM
test with an iOS test. Preserve the Expo app and its user data during migration.
