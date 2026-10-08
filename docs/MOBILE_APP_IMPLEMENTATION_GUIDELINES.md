# Mobile Product, Design, Validation, and Delivery Principles

This document captures reusable product, design, engineering, testing, and release
decisions learned while building a cross-platform, form-heavy mobile application. It is
project-agnostic: treat these as default rules for future apps unless a product requirement
explicitly calls for different behavior.

The goal is not to make every app look identical. The goal is to preserve the qualities
that repeatedly require the most care: predictable interaction, immediate and accurate
feedback, accessible light and dark themes, exact data handling, platform parity, and a
release pipeline that proves what it ships.

## Foundations

### Start from the user's mental model

- Name screens, metrics, categories, and actions in the language the user naturally uses.
- Explain the purpose of an unfamiliar control with one short supporting sentence.
- Do not expose storage, parser, pipeline, or debugging terminology in ordinary UI.
- Remove debug-only screens, controls, logs, and import paths before release.
- Prefer a small complete workflow over several partially implemented options.
- When requirements change, remove stale UI, assets, tests, documentation, and persisted
  diagnostics together. Dead surfaces create false expectations and privacy risk.

### Make the important state obvious

- A user should be able to tell which screen, filter, theme, category, or mode is active
  without relying on memory.
- Use hierarchy, color, weight, and spacing consistently; do not make every element compete
  for attention.
- Reserve strong emphasis for the current destination and the primary action.
- Use secondary text for context, not for essential values that need high contrast.

### Keep one source of truth

- Put business rules, accounting, parsing, limits, and date calculations in the domain
  layer shared by every presentation surface.
- Let platform UI own presentation, focus, keyboard, safe areas, accessibility, and native
  integration.
- Do not duplicate a rule in Add, Edit, import, and persistence code. Provide one domain
  definition and reusable UI adapters around it.
- Render only committed state after a write succeeds. Never show a successful result for a
  failed persistence operation.

### Prefer consistency over novelty

- Similar inputs should format, validate, and report errors in the same way everywhere.
- Add and Edit should share field components and validation semantics.
- Primary actions should occupy a consistent location across related forms.
- Native behavior is the baseline. Custom controls need a clear product benefit and the
  same accessibility and interaction quality as their platform equivalents.

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

### Respect presentation models

- A persistent destination belongs in bottom navigation and preserves destination state.
- A create flow may be a modal form when it represents a temporary task rather than a
  place. Its animation, close behavior, and accessibility should make that distinction
  clear.
- Do not accidentally mix the models, such as presenting Add modally but styling it as a
  permanently selected destination.
- A modal form must have an obvious cancel path, dismiss the keyboard correctly, and return
  to the previous destination after a successful save.

### Build for safe areas and real content

- Apply system insets once at the correct container. Avoid compensating with device-specific
  magic numbers.
- Test short and long screens, an open keyboard, validation errors, large text, and the
  smallest supported phone.
- Decorative images must not push labels, totals, or actions out of alignment.
- Align related labels and values to a shared visual axis. A value such as `Left` should
  align with the heading and date it summarizes, not float according to its text length.
- Bottom bars must distribute destinations evenly even when labels and icon shapes differ.

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

### Use a semantic design system

Define tokens by purpose rather than by raw appearance. At minimum, provide:

- App background, grouped background, raised surface, input surface, and divider.
- Primary, secondary, muted, and inverse text.
- Accent, selected, positive, warning, destructive, and disabled states.
- Border, focus, chart-grid, and scrim colors.
- Standard spacing, corner radii, icon sizes, touch targets, and typography roles.

Components should consume semantic tokens. A literal gray that works in dark mode can be
too faint in light mode, and a hard-coded green may fail against a different surface.

### Design light and dark themes independently

- Dark mode is not light mode with colors inverted.
- Check borders, disabled states, placeholders, chart labels, numeric values, destructive
  actions, and selection indicators in each theme.
- Keep hierarchy comparable across themes even when the actual colors differ.
- Prefer contrast and legibility over subtle styling. In light mode especially, body text
  and absolute values should not fade into the background.
- Test System mode while the app is open and while it resumes after the system appearance
  changes.

### Treat assets as part of the system

- Keep separate light and dark assets only when a semantic color cannot produce the right
  result at runtime.
- Name assets by screen and sequence so their order remains understandable after steps are
  inserted or removed.
- Delete superseded asset sets and verify no build configuration or documentation still
  references them.
- Preserve an asset's aspect ratio and transparent bounds. Size it by its visible content,
  not only by the dimensions of its canvas.
- Use the same source artwork for the app icon, splash identity, and in-app brand mark when
  they are intended to match. Account for platform masks and safe margins separately.
- Avoid scaling a splash mark during the transition to the first screen unless motion is an
  intentional part of the brand experience.

### Keep compact interfaces human

- Use content-sized, wrapping chips instead of rigid equal-width category grids.
- Keep gaps consistent but modest so related options read as a group.
- Do not over-emphasize a center navigation action solely because it is centered.
- Use familiar icons with accessible labels; add visible text only when the command would
  otherwise be ambiguous.
- Avoid cards inside cards. Group related controls with spacing, dividers, and typography
  before adding another container.

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
- Do not encode state using color alone. Pair active, error, success, and disabled colors
  with shape, text, symbols, or accessibility state.
- Respect Reduce Motion for decorative transitions and avoid animation that changes the
  hit target while a user is interacting with it.
- Announce saves, validation failures, toasts, and modal presentation changes where the
  platform does not do so automatically.
- Keep source order, focus order, and visual order aligned.

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

### Minimize private data

- Collect and retain only data required by a current user-facing feature.
- Process sensitive input on-device when server processing is unnecessary.
- Do not retain unrecognized raw input merely for possible future debugging.
- Keep privacy documentation synchronized with the actual shipping code, including data
  sources, retention, sharing, diagnostics, and deletion behavior.
- A removed feature must also be removed from privacy claims; a planned feature must not be
  described as already present.
- Never place signing keys, API keys, personal data, or raw customer content in source
  control or CI artifacts.

## 10. Content and onboarding

- Write instructions as short, numbered actions that correspond to visible annotations in
  the supplied image.
- Use the exact current platform labels so users can find the control.
- One screenshot may explain several tightly connected taps when annotations establish a
  clear order.
- Split a step when it requires a screen transition or when the next action is not visible.
- Keep light and dark screenshot sequences in lockstep.
- Remove redundant Next buttons when the pages are discoverably swipeable and have a clear
  page indicator and exit path.
- Supporting copy should answer a real concern. Remove text that merely restates the
  mechanism or makes an unsupported privacy claim.
- When a platform workflow changes, update step count, copy, assets, tests, and asset names
  in one change.

## 11. Testing strategy

### Use a test pyramid with explicit ownership

Each behavior should be tested at the lowest layer that can prove it, then covered by a
small number of end-to-end tests for critical workflows.

| Layer | Proves | Typical examples |
| --- | --- | --- |
| Pure/domain unit tests | Rules and edge cases | Money parsing, limits, splits, dates, categorization |
| Persistence/integration tests | Components work together | Migration, atomic writes, deduplication, parser-to-ledger flow |
| Native component tests | Presentation state | Error placement, enabled state, formatting, theme tokens |
| Native interaction tests | User workflow | Add, edit, delete, keyboard dismissal, navigation, settings |
| Physical-device smoke tests | Hardware and OS reality | Keyboard geometry, notifications, shortcuts, deep links, launch |

Avoid proving domain arithmetic repeatedly through slow UI tests. Avoid relying only on
unit tests for behavior that depends on native focus, scrolling, safe areas, or lifecycle.

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

### Keep interaction tests resilient

- Query stable accessibility identifiers, not coordinates, row indexes, or incidental copy.
- Wait for meaningful state, not arbitrary sleep durations.
- Reset or seed state explicitly so test ordering cannot affect results.
- Keep navigation elements outside scroll containers so accessibility actions can reach
  them reliably.
- A retry can identify platform flakiness, but a test that passes only on retry still needs
  investigation.
- When a test fails, preserve the result bundle, screenshots, logs, and exact source commit.
- Remove a test only when its product behavior has intentionally been removed. Record that
  decision in the same change.

### Maintain a focused regression suite

Every fixed regression should leave behind the cheapest reliable test that would have
caught it. High-value regression areas include:

- Formatting and validation disagreement.
- Picker overlays moving with scroll content.
- Keyboard-induced bottom-navigation movement.
- Theme changes that apply only after a sheet closes.
- Safe-area clipping and unreachable final content.
- Incorrect accounting labels or totals.
- Import parser confusion between transaction amounts and balances.
- Release jobs that report success after a failed command.

## 12. CI pipeline design

### Separate pipeline intent

Use distinct workflows for distinct questions:

1. **Verification:** Does this source commit pass shared, Android, and iOS checks?
2. **Beta distribution:** Can this verified source be signed and uploaded for internal or
   external testing?
3. **Production candidate:** Can a specifically approved beta source be rebuilt with the
   requested release version and an unused build number?

Do not combine these into a stack of dependent automatic runs when CI capacity is limited
or failures become difficult to diagnose. Manual dispatch makes cost and intent explicit.

### Verification pipeline

- Run shared/domain tests on every supported runtime, not only the easiest host.
- Compile each native app and its test target.
- Run Android unit and device interaction tests.
- Run iOS shared-runtime tests plus native Swift/SwiftUI interaction tests on macOS.
- Upload reports and result bundles even on failure.
- Name jobs by platform so one failure does not hide the status of another.
- Pin or explicitly select toolchain versions required by the stores and project.

### Beta pipeline

- Accept or derive a unique build number using a documented format.
- Validate all required secrets before spending time on a release build.
- Rerun release-relevant tests on the signing toolchain.
- Generate projects deterministically when generated native projects are not committed.
- Archive, export, validate, and upload in separate named steps.
- Record source SHA, marketing version, build number, toolchain version, and workflow run.
- Serialize uploads when the store or project should have only one in flight.

### Production pipeline

- Require both the approved beta version/build identity and the desired release version.
- Resolve the approved beta back to its exact source SHA; do not release whatever happens
  to be at the branch head.
- Check out that source and rerun the full release gate.
- Confirm the target build number is unused before starting the expensive archive.
- Changing a marketing version creates a new binary. Store metadata cannot rename an
  already uploaded binary.
- Keep beta and production numbering conventions distinguishable if that simplifies human
  review, while still satisfying store uniqueness rules.

### Pipeline safety

- Keep verification, beta, and production workflows manual when automatic runs would waste
  limited CI capacity.
- Use least-privilege repository or environment secrets and protect production environments
  with approval when available.
- Use a separate signing directory per app or project. A team distribution certificate and
  API key may be reused when policy permits, but provisioning profiles and repository
  secrets remain app-specific.
- Never echo secret contents. Use temporary keychains/files and clean them up after the job.
- Preserve the original exit code when collecting artifacts or running cleanup.
- Add workflow concurrency rules to avoid duplicate uploads and queued release runs.
- Set artifact retention deliberately, especially for signed binaries and verbose logs.

## 13. Build and release safeguards

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

### Versioning and release provenance

- Treat the customer-facing marketing version and monotonically unique build number as
  separate values.
- Start a public product at an intentional release version such as `1.0.0`; do not expose a
  prototype version by accident.
- Record which tested beta was approved, which source SHA produced it, and which production
  binary was rebuilt from that SHA.
- A release checklist should include privacy policy, support URL, screenshots, device
  family, export compliance, review notes, and a real-device smoke test.
- Enabling additional device families creates design, testing, and store screenshot
  obligations. Declare only the device families the product actually supports.

## 14. Documentation and maintenance

- Keep a product specification for app-specific behavior and a separate project-agnostic
  guide for reusable principles.
- Document the reason behind non-obvious limits and architecture boundaries.
- Link release/setup guides from the repository README so they are discoverable.
- Update documentation in the same commit as behavior whenever practical.
- Prefer current code and tests over memory when auditing features or privacy behavior.
- Mark platform behavior as verified, inferred, or untested. Do not imply parity without
  evidence.
- Keep folder and asset numbering sequential after adding or removing onboarding steps.
- Avoid documenting abandoned debug flows as supported product behavior.

## Completion checklist

Before calling a feature, form, or workflow complete, confirm:

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
- Light and dark assets, semantics, and contrast were reviewed independently.
- Debug-only UI, stale assets, obsolete tests, and outdated privacy claims were removed.
- The verification pipeline preserves enough evidence to diagnose a failure.
- A beta or production artifact can be traced back to its exact tested source commit.
