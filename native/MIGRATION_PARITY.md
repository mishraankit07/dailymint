# DailyMint Native Migration Parity

Goal: migrate the current Expo app functionality into a Kotlin Multiplatform core with separate native Android and iOS UIs.

## Shared KMP core

- [x] Local ledger persistence contract and corruption guard
- [x] Manual expense/income entry with exact paise arithmetic
- [x] Investment-as-expense-category behavior
- [x] Custom categories with delete/remap to Miscellaneous
- [x] Learned merchant/category rules
- [x] Generic bank SMS/WAL parsing and regression fixtures
- [x] Import staging, duplicate detection, save/discard review
- [x] Android direct SMS import model
- [x] Month tracking cycle start day
- [x] Month summary, money split, top transactions, detailed day groups
- [x] Growth buckets for months/years
- [x] Edit/delete guard based on capture window
- [x] Reminder settings and shared notification copy

## Native Android

- [x] Persistent ledger store
- [x] Startup/read SMS permission flow
- [x] Automatic SMS scan on open/resume and inbox changes
- [x] Manual entry
- [x] Month/Growth/Plan/Settings surfaces
- [x] Edit/delete recent eligible ledger entries
- [x] Raw SMS debug details
- [x] Daily reminder scheduling from shared settings
- [ ] Polished DailyMint UI

## Native iOS

- [x] Persistent ledger store
- [x] Manual file import and review staging
- [x] Manual entry
- [x] Month/Growth/Plan/Settings surfaces
- [x] Edit/delete recent eligible ledger entries
- [x] Daily reminder scheduling from shared settings
- [x] App Intent / Shortcut action for automated transaction ingest
- [ ] Polished DailyMint UI

## Remaining Expo-only or weaker native areas

- [ ] Verify iOS App Intent automated import on device/TestFlight Shortcut automation
- [ ] Developer feedback flow for unrecognized SMS samples
- [ ] Android SMS diagnostics history parity
- [ ] Visual redesign across Android and iOS after functionality parity is stable
