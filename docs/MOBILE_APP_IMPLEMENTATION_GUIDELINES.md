# Mobile App Implementation Guidelines

This document captures reusable product and engineering decisions for form-heavy
mobile applications. Treat these as default implementation rules unless a product
requirement explicitly calls for different behavior.

## 1. Input behavior

### Keep display and stored values separate

- Let the user edit a friendly display value, but validate and persist a canonical value.
- Remove presentation characters such as grouping commas before parsing.
- Never use a formatted string as the source of truth for arithmetic.
- For money, persist the smallest currency unit as an integer. Do not use floating-point
  values for storage, totals, comparisons, or split calculations.

For example, `10,00,000.25` should be handled as:

```text
Displayed input: 10,00,000.25
Canonical input: 1000000.25
Stored amount:   100000025 paise
```

### Format numeric input while the user types

- Add and remove grouping separators as digits are inserted or deleted.
- Preserve the caret position after reformatting, including edits in the middle.
- Preserve an in-progress decimal separator, such as `12.`.
- Apply validation to the canonical value after removing separators.
- Use the locale and numbering convention chosen by the product. Do not silently mix
  western and Indian grouping.

### Reject impossible edits before they appear

When a field has a hard product limit, reject the edit at the native input delegate or
formatter layer. This keeps the displayed value and bound state synchronized.

Examples:

- Transaction amount must not exceed `Rs 10,00,000`.
- A money field accepts no more than two decimal places.
- A name accepts no more than 120 characters.
- A personal share must be positive and must not exceed the original amount.

Whenever an edit is rejected, immediately explain why below that field. A keyboard that
appears to stop working without an explanation feels broken.

### Use contextual placeholders

Placeholder text should describe the expected value, not repeat the field label.

Examples:

| Context | Name placeholder | Amount placeholder |
| --- | --- | --- |
| Expense | Add restaurant or merchant name | Enter the value spent |
| Credit | Add sender or company name | Enter the value received |

Placeholders are hints, not validation messages, and should disappear normally when the
user enters text.

## 2. Validation behavior

### Validate each field independently

- Editing a date, time, category, or another unrelated control must not trigger an amount
  or name error.
- Validate a field after the user interacts with that field, when an edit is rejected, or
  when Save is attempted.
- Clear an error as soon as the current value becomes valid.
- On Save, validate all required fields and focus or scroll to the first invalid field.

### Put errors directly below their fields

- Show a short red message immediately below the relevant input.
- Do not collect field errors in a generic line near the Save button.
- Reserve a small, fixed-height validation line below each field, even when no error is
  visible. This prevents the form from jumping when a message appears.
- Hide empty validation lines from accessibility APIs.

Good messages describe the correction:

```text
Enter a name.
Name cannot exceed 120 characters.
Enter a positive amount with up to two decimal places.
Amount cannot exceed Rs 10,00,000.
Your share cannot exceed the original amount.
```

Avoid vague messages such as `Invalid value` or messages for a different field.

### Use one validation definition

- Keep domain rules in the shared or domain layer when multiple platforms use them.
- Keep edit-time constraints in a reusable field component.
- Do not let Save validation, live validation, and persistence parsing disagree.
- Test formatted and unformatted representations of the same value.

## 3. Keyboard and focus

- Tapping outside an input should dismiss the keyboard.
- Changing tabs or opening another primary screen should dismiss the keyboard.
- The bottom navigation must remain at the screen bottom and must not dock above the
  keyboard.
- Forms must scroll far enough that their final content and actions can sit fully above
  the keyboard and bottom safe area.
- A sticky Save action should remain compact and respect the safe area.
- Use the appropriate keyboard: decimal for money, numeric for counts, and text for names.
- Test focus, caret behavior, dismissal, and bottom geometry on a physical device. A unit
  test or simulator-only test cannot prove keyboard layout correctness.

## 4. Selection controls

- Use menus, sheets, or platform-native pickers for option sets.
- A selected value must remain visually anchored when the page scrolls.
- Do not implement a dropdown as a horizontal input accessory that follows the keyboard
  or scroll view.
- Dismiss an open picker predictably when an option is selected, the user taps outside,
  or navigation changes.
- Use compact, wrapping chips for categories. Keep spacing consistent and avoid a rigid,
  machine-generated grid when labels have different lengths.
- Group long category sets under small semantic headings when that improves scanning.

## 5. Actions and feedback

### Save actions

- Put the primary Save action in a consistent location across add and edit flows.
- Disable Save only when the reason is obvious; otherwise allow the tap and show precise
  field-level validation.
- Publish UI changes only after persistence succeeds.
- After a successful create action, show a bottom toast such as `Transaction Saved!` for
  approximately two to three seconds.

### Destructive actions

- Confirm destructive actions in a centered modal dialog.
- Tapping outside the dialog cancels it.
- `Cancel` closes the dialog without changing data.
- `Delete` performs the deletion and should use destructive styling.
- Keep destructive copy complete and specific about what will be removed.

### Explain intent, not only mechanics

Controls should communicate why they exist. A short supporting line can keep the feature
aligned with the product's purpose.

Example:

```text
Split this expense?
Track only the amount that belongs to you.
```

## 6. Navigation and layout

- Give bottom-navigation items equal horizontal space.
- Center the middle item geometrically, not by compensating with arbitrary padding.
- Highlight the active destination consistently in light and dark themes.
- Do not make one navigation item much larger or bolder unless it truly represents a
  different global action.
- Decide whether an Add experience is a destination or a modal form and apply that model
  consistently. The transition, dismissal, and Save placement should match the decision.
- Content must scroll beyond fixed bottom panels. The final line should be comfortably
  readable without holding the scroll view at its limit.
- Keep fixed bottom panels no taller than their content and touch targets require.
- Use stable dimensions for toolbars, chips, counters, charts, and navigation items so
  content changes do not shift the layout.

## 7. Themes and visual semantics

- Support Light, Dark, and System when theme choice is exposed.
- Apply theme changes at the app root immediately. Do not wait for a settings sheet to
  close.
- Store the user's explicit preference and continue observing system changes in System
  mode.
- Define semantic colors such as background, raised surface, primary text, secondary text,
  positive, destructive, and accent. Avoid scattered literal colors.
- Check contrast separately in light and dark themes. Secondary text and chart values must
  remain readable in light mode.
- Enabled toggles should use the product's positive or accent color consistently.
- Verify all supplied visual assets in both themes when separate variants exist.

## 8. Accessibility

- Give interactive elements stable accessibility identifiers that describe their role,
  not their screen coordinates.
- Keep visible labels human-readable. Use identifiers for automation rather than changing
  visible copy to satisfy a test.
- Disabled controls should expose both their disabled state and a visible reason.
- Ensure minimum platform touch-target sizes.
- Test larger text sizes and long localized strings for clipping and overlap.
- For XCTest, direct string subscripts are limited to identifiers of 128 characters. Query
  long visible text with a predicate on `label` instead.

## 9. Data and persistence

- Parse, validate, and normalize before creating a domain object.
- Persist exact values, not display strings.
- Use atomic writes and do not overwrite known storage with partially decoded or corrupt
  data.
- Make imports idempotent and assign stable identifiers to prevent duplicate transactions.
- Preserve original imported values separately when the user can record a personal share.
- Treat read-only imported fields as visibly read-only and explain why they cannot be
  edited.
- Refresh all affected screens after background, shortcut, or external imports.

## 10. Testing expectations

Cover rules at the lowest reliable layer and important workflows at the UI layer.

### Domain tests

- Canonical amount parsing with and without commas.
- Zero, negative, malformed, over-limit, and over-precision amounts.
- Exact integer arithmetic and totals.
- Personal shares equal to, below, and above the original amount.
- Name trimming and length boundaries.
- Persistence failures, corrupt data, duplicate imports, and date boundaries.

### UI tests

- Errors appear under the correct field and clear after correction.
- Rejected input never appears visually.
- Live formatting works while inserting and deleting digits.
- Keyboard dismissal and tab changes behave correctly.
- Fixed navigation and Save controls remain reachable.
- Dropdowns stay anchored after selection and scrolling.
- Theme changes apply while settings remains open.
- Dialog dismissal, deletion, and success toasts behave correctly.
- Accessibility identifiers and labels remain stable.

### Platform verification

- Run shared tests and each platform's native unit and interaction tests.
- Do not treat JVM tests as proof of iOS behavior or simulator tests as proof of physical
  keyboard geometry.
- Keep failed tests unless the behavior is intentionally removed. Update them when copy or
  requirements change.
- Report any platform that could not be executed as unverified.

## 11. Build and release safeguards

- Keep verification, TestFlight, and production workflows manual when automatic runs would
  waste limited CI capacity.
- A release job must preserve and report the real exit status of every build, signing, and
  upload command.
- Treat the marketing version and build number as separate values.
- Identify an approved beta by both its release version and build number when the store can
  contain repeated build numbers across versions.
- Rebuild a tested source commit with the intended production version. An uploaded binary
  cannot be renamed after upload.
- Verify that a requested build number is unused before signing and uploading.
- Upload artifacts and logs on failure, but never let artifact cleanup mask the original
  failure.

## Completion checklist

Before calling a form or workflow complete, confirm:

- Display formatting and canonical parsing agree.
- Hard limits reject edits before display and explain the rejection.
- Every field error appears directly below its field and clears live.
- Save validates all fields and persistence succeeds before UI confirmation.
- Keyboard, scrolling, safe areas, and bottom navigation work together.
- Pickers and dropdowns remain anchored after selection and scrolling.
- Light, dark, and system themes update immediately and remain readable.
- Accessibility labels, identifiers, touch targets, and large text are verified.
- Domain, native UI, persistence, and release-path tests cover the behavior.
- Any untested platform or physical-device behavior is explicitly recorded.
