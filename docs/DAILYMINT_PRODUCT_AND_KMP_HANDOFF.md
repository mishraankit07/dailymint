# DailyMint Product, Screen, Flow, and KMP Handoff Specification

Status: implementation handoff

Scope: platform-neutral product behavior and Kotlin Multiplatform shared-core contract

Audience: product designers, native-client engineers, KMP engineers, QA engineers, and future maintainers

## 1. Purpose

DailyMint is a personal expense tracker that turns transaction messages and manual entries into a private ledger. Its primary purpose is to answer:

- How much did I personally spend in my current tracking cycle?
- Where did that money go?
- How is spending changing across calendar months or years?
- What transactions were recorded, and how can I correct their classification?

DailyMint is not a bank-balance tracker, debt ledger, group-settlement service, or source of verified account balances. Imported messages describe money movement through an account. The amount that counts as the user's personal spending may be smaller than the original bank amount when the user paid for other people.

The product must preserve the original transaction evidence while allowing the user to correct how the transaction is presented and counted.

## 2. Product Decisions

The following decisions are authoritative:

1. The main navigation contains five destinations in this order: Home, Growth, Add, Ledger, Plan.
2. Add is a center action that opens a transaction form and is not a persistent content destination.
3. Settings is reached through a top-right action and is not a sixth navigation destination.
4. Home does not contain a `See all transactions` button. Ledger is always directly available from the navigation dock.
5. There is no transaction-file import, pending-file review, or file-picker flow in the product UI.
6. Automated message capture is the supported import path. Each platform supplies messages through its native acquisition adapter.
7. Raw message text, sender, bank reference identifiers, and other source evidence are never shown in ordinary transaction UI.
8. Plan remains an honest `Coming soon` screen until real budget and goal functionality is implemented.
9. All financial calculations and validation rules are owned by the KMP shared core. Native clients do not independently reproduce accounting logic.
10. All monetary values are stored as integer paise. Rupees are a display concern only.

## 3. Terminology

### Original amount

The immutable amount reported by the bank message or entered for a manual transaction. In the data model this is `paise`.

For imported transactions, the original amount must never be changed by classification editing.

### Personal spending

The portion of an expense that counts toward the user's spending totals. In the data model this is represented by `personalExpensePaise`.

- If `personalExpensePaise` is absent, the entire original expense counts.
- If it is present, its value must be between zero and the original amount.
- Investments and credits never contribute to personal spending.
- Ignored transactions contribute zero.

### Earned income

Credits classified as Salary or Other income. Earned income contributes to the Home `Income` value and Growth `Money in` bars.

### Neutral credit

A Reimbursement, Refund, or Own-account transfer. Neutral credits remain visible in Ledger and in gross daily credit totals, but do not increase earned income and do not reduce personal spending.

### Investment

An outflow assigned to the Investments category. Investments are tracked separately from personal spending.

### Tracking cycle

The configurable period used by Home. If the user selects day 27, the cycle runs from the 27th of one month through the 26th of the next month, inclusive.

### Calendar period

The fixed calendar month or year used by Growth. Growth never follows the custom tracking-cycle boundary.

## 4. Architecture

DailyMint uses a shared KMP core and separate native presentation layers.

```text
Platform message source       Manual form       Settings/UI actions
          |                       |                     |
          +-----------------------+---------------------+
                                  |
                         Native presentation layer
                                  |
                         KMP LedgerEngine commands
                                  |
                    Validation, parsing, deduplication,
                    accounting, analytics, migration
                                  |
                         Platform LedgerStore adapter
                                  |
                         Atomic local snapshot storage
```

### KMP owns

- The versioned ledger schema.
- Entry validation.
- Exact money parsing and formatting.
- Transaction-message parsing.
- Merchant/category suggestions.
- Duplicate prevention.
- Personal-share calculations.
- Credit classification semantics.
- Category deletion and transaction remapping.
- Tracking-cycle calculations.
- Calendar trend calculations.
- Atomic transaction mutations.
- Schema migration.
- Protection against publishing a failed save.

### Native UI owns

- Navigation and screen composition.
- Text fields, menus, dialogs, sheets, and focus behavior.
- Platform accessibility semantics.
- System insets, keyboard avoidance, orientation, and theme handling.
- Notification permission and scheduling integration.
- Platform-specific transaction-message acquisition.
- Presentation of KMP results and errors.
- Reloading observable state after successful mutations or external imports.

### Native UI must not own

- Independent spending calculations.
- Floating-point currency arithmetic.
- Separate equal-split formulas.
- Separate credit classification rules.
- Separate date-window calculations.
- Direct edits to serialized snapshots.
- A duplicate-detection implementation that differs from KMP.

## 5. Shared Data Model

The current snapshot schema version is 3.

### Entry

| Field | Meaning | Mutability |
| --- | --- | --- |
| `id` | Stable transaction and deduplication identity | Immutable |
| `name` | Current user-facing merchant or transaction name | Editable under the applicable rules |
| `paise` | Original amount in integer paise | Immutable for imported entries |
| `category` | Current expense category or credit label | Editable classification |
| `date` | Transaction/source date in ISO form | Immutable for imported entries |
| `type` | `expense`, `investment`, or `income` | Derived from classification |
| `source` | Origin such as `manual` or platform message import | Immutable |
| `capturedAtMillis` | Time at which DailyMint captured the record | Immutable |
| `rawSms` | Original transaction message | Protected evidence; never ordinary UI |
| `sender` | Source sender identifier | Protected evidence; never ordinary UI |
| `referenceId` | Bank reference identifier when available | Protected evidence; never ordinary UI |
| `bank` | Parsed bank name when available | Protected evidence |
| `personalExpensePaise` | Optional amount counted as personal spending | Editable for expenses within bounds |
| `creditKind` | Shared credit classification | Editable for credits |
| `ignored` | Whether analytics exclude the record | Editable for imported records |
| `originalName` | Initial parsed display name | Immutable audit value |
| `originalCategory` | Initial parsed category | Immutable audit value |
| `splitMethod` | `none`, `equal`, or `custom` | Editable through the split flow |
| `splitPeopleCount` | Number of people for equal split, including user | Present only for equal split |

### Snapshot

The snapshot contains:

- `schemaVersion`
- User categories
- Ledger entries
- Learned merchant-to-category rules
- Tracking-cycle start day
- Reminder enabled state and time
- Message-import watermark
- Up to 50 unrecognized transaction-message records for local diagnostics

The shared core still contains deprecated staging structures for historical compatibility in code. They are not a product surface and must not be connected to any screen or file picker.

### Default categories

- Home
- Groceries
- Food
- Fun
- Gym
- Self
- Investments
- Miscellaneous

Miscellaneous is mandatory and cannot be deleted.

### Credit kinds

| UI label | Shared value | Accounting effect |
| --- | --- | --- |
| Salary | `salary` | Earned income |
| Other income | `other_income` | Earned income |
| Reimbursement | `reimbursement` | Neutral credit |
| Refund | `refund` | Neutral credit |
| Own-account transfer | `own_transfer` | Neutral credit |

Legacy `Received` records retain their prior income meaning and are displayed as Other income.

## 6. Money and Validation Rules

### Amount parsing

- Ordinary transaction amounts must be greater than zero.
- Custom personal shares may be zero.
- At most two decimal places are accepted.
- Western and Indian comma grouping are accepted when correctly formed.
- Negative values, malformed separators, NaN, excessive precision, and overflow are rejected.
- The maximum stored value is `100,000,000,000` paise.
- Formatting omits `.00` and retains non-zero paise.

### Name validation

- Trim leading and trailing whitespace.
- Name must contain between 1 and 120 characters after trimming.

### Category-name validation

- Trim leading and trailing whitespace.
- Collapse internal runs of whitespace to one space.
- Length must be between 1 and 40 characters.
- Matching is case-insensitive for duplicate detection.
- A category cannot duplicate an existing category or a reserved credit label.

### Equal split

The number of people includes the user and must be an integer of at least 2.

The shared formula is:

```text
exactSharePaise = ceil(originalAmountPaise / people)
personalExpensePaise = min(
    originalAmountPaise,
    ceil(exactSharePaise / 100) * 100
)
```

This rounds the user's share upward to the next whole rupee and caps it at the original amount.

Examples:

- Rs 800 among 3 people becomes Rs 267 personal spending.
- Rs 300 among 3 people becomes Rs 100 personal spending.
- An original amount below Rs 1 never produces a personal share above the original amount.

### Custom split

- Accept Rs 0 through the original amount.
- Accept at most two decimal places.
- The excluded amount is not a debt, receivable, settlement, or goal contribution.

## 7. Global Navigation

The bottom dock is fixed, opaque, and ordered as follows:

1. Home
2. Growth
3. Add
4. Ledger
5. Plan

Each destination has an icon and one-word label. Add is visually prominent and opens a modal transaction form. Saving or cancelling Add returns to the previously selected destination.

The selected persistent destination remains alive when the user changes tabs. Screen-local state such as Ledger filters and search text must survive a round trip to another destination.

The dock must:

- Respect system navigation and safe-area insets.
- Never float over content.
- Never cover the keyboard.
- Use stable dimensions so selection does not shift layout.
- Expose selected state to assistive technology.
- React immediately to light/dark theme changes.

Settings is always available from a top-right gear action on persistent destinations.

## 8. Onboarding and Initial State

On first launch, the product introduces automatic transaction-message capture.

The onboarding must explain:

1. The platform automation or permission required to receive transaction messages.
2. That messages are processed on the device.
3. That DailyMint does not silently read unrelated content without the platform's supported permission or automation path.
4. How the user can verify whether a message reached DailyMint.
5. That setup can be deferred and reopened from Settings.

The user may continue without completing message automation. Manual Add and the rest of the app remain usable.

Onboarding completion is persisted independently of the ledger.

## 9. Home Screen

### Purpose

Answer: `What have I personally spent in my current tracking cycle?`

### Header

The greeting is based on local device time:

- 05:00 through 11:59: Good morning
- 12:00 through 16:59: Good afternoon
- All other times: Good evening

`Good night` is never used.

### Summary panel

The primary value is `Spent this cycle`.

It displays:

- Total personal spending for the active tracking cycle.
- Inclusive cycle dates in a human-readable format.
- Income, meaning earned income only.
- Invested, meaning investment outflows only.

The screen must not label any value as bank balance, remaining bank money, wealth, or cash on hand.

### Tracking-cycle calculation

The configured start day is clamped to the last valid day in shorter months.

Examples:

- Start day 1: normal calendar month.
- Start day 27: 27th through the 26th.
- Start day 31 in February: starts on February's final valid day.

The engine stores an exclusive cycle end internally. The UI displays the final included day.

### Empty state

When the cycle has no earned income, personal spending, or investments, show a clear empty state explaining that the user can add an entry or use automatic transaction-message capture.

Do not render misleading zero-filled charts.

### Category breakdown

Shown when personal spending is greater than zero.

- Includes expense records only.
- Excludes investments.
- Excludes all credits.
- Excludes ignored records.
- Excludes expenses whose personal share is zero.
- Uses personal spending, not original bank amount.
- Percentage denominator is total personal spending for the cycle.
- Miscellaneous sorts after named categories.

Each row shows category name, progress, and exact amount.

### Biggest spends

- Shows up to five expense records.
- Sorted by personal spending descending.
- Excludes investments, credits, ignored records, and zero-share expenses.
- Displays the personal amount.
- If the personal amount differs from the original amount, the row also shows the original bank amount.
- Tapping a row opens the same Transaction detail used by Ledger.
- There is no inline Edit button.

### Explicitly absent

- No `See all transactions` button.
- No detailed history embedded in Home.
- No budget remainder until Plan implements a real user-entered budget.

## 10. Growth Screen

### Purpose

Compare money movement over fixed calendar periods. Growth does not use the custom tracking cycle.

### Period controls

- Segmented mode: Months or Years.
- Month options: 3 months and 6 months.
- Year options: 1, 2, 3, and 5 years.
- Switching mode resets to 3 months or 1 year respectively.
- Supporting text states that periods are full calendar months or full calendar years.

### Money movement chart

Each calendar period is one x-axis group. Bars for the same period are adjacent within that group.

The group contains:

- Money in: earned income.
- Personal spent: personal spending.
- Invested: investment amount.

Adjacent calendar periods form separate groups. Period labels remain visible at compact widths and in dark mode.

The chart:

- Uses shared KMP trend buckets.
- Excludes ignored records.
- Uses personal share for expense bars.
- Uses full calendar boundaries.
- Shows a labeled no-data state when every bucket is zero.
- Never claims to show bank balance or wealth.

### Period details

Below the chart, selectable period chips expose exact amounts for the chosen period. If no chip is explicitly selected, the most recent period is shown.

The detail displays Money in, Personal spent, and Invested with both color and text.

## 11. Add Screen

### Presentation

Add opens a modal form over the previously selected destination.

The toolbar includes Cancel. The form contains one primary Save action.

### Expense/income selector

- Defaults to Expense.
- Switching to Income selects Other income by default.
- Switching to Expense selects Miscellaneous by default.

### Shared fields

- Name
- Amount
- Transaction date

Name changes request a KMP category suggestion. The suggestion must never turn a credit into an expense category.

### Expense fields

- User-managed category selector.
- Add category action inside the category selector.
- Optional `Split this bill with others` control, except for Investments.

### Income fields

The category selector becomes a fixed credit-kind selector:

- Salary
- Other income
- Reimbursement
- Refund
- Own-account transfer

Income does not show bill splitting.

### Manual split flow

When split is disabled, personal spending equals the entered amount.

When enabled, offer:

- Split equally
- Custom share

Equal split asks for the number of people including the user. Custom share asks for the user's amount. A live summary should read in the form:

`Rs 800 paid - Rs 267 counts as your spending`

The preview is informative. KMP remains authoritative at Save.

### Save behavior

1. Dismiss the keyboard or remove field focus.
2. Submit all fields to one KMP command.
3. Do not update any total before persistence succeeds.
4. On success, close Add and return to the prior destination.
5. The entry is immediately visible in Home, Ledger, and the appropriate Growth bucket.
6. On failure, keep the form open, preserve entered data, and show the KMP error.

### Cancel behavior

Cancel closes Add without saving anything and returns to the prior destination.

## 12. Ledger Screen

### Purpose

Provide all recorded transaction history and access to correction flows.

### Scope

- Shows all dates, not only the current tracking cycle.
- Newest date groups appear first.
- Transactions within a date group use deterministic newest/capture ordering.
- Ignored transactions remain discoverable for restoration.

### Search

Search matches the current transaction name case-insensitively.

### Type filters

- All
- Expense
- Investment
- Credit
- Neutral credit

### Category filters

- All categories
- Every current expense category
- Salary
- Other income
- Reimbursement
- Refund
- Own-account transfer

Legacy Received records match Other income.

### Date filter

The user may enable an inclusive From/To date range. Date comparison uses normalized `yyyy-MM-dd` values in the configured India timezone.

### Empty states

If the ledger is empty, explain that the user can add an entry or set up automatic message capture.

If filters yield no results, explain that no transaction matches and offer Clear filters.

### Date-group header

Each date group shows:

- Date
- Number of visible entries
- Gross incoming amount for the full day
- Gross outgoing amount for the full day

Gross day totals use original transaction amounts. Ignored transactions are retained in the group but excluded from gross totals.

### Transaction row

Each row shows:

- Category visual
- Merchant/name
- Display category and transaction date
- Signed amount
- `Bank: Rs ...` when an expense's personal amount differs from its original amount
- Ignored state when applicable

Credits use a positive sign. Expenses and investments use a negative sign. Text and signs accompany color so meaning does not depend on color alone.

### Pagination

- Initially show 30 date groups.
- `Load more transactions` reveals 30 more date groups.
- Changing search or filters resets the visible page to 30 groups.
- The containing list must use lazy rendering.

### Preserved state

Search text, filters, and date controls remain unchanged when the user visits another destination and returns.

### Explicitly absent

- No file import button.
- No file picker.
- No pending-file review entry point.
- No raw message viewer.

## 13. Transaction Detail

The navigation title is `Transaction`. Do not repeat the app name or use the merchant as a second screen title.

### Common read-only information

- Original amount, displayed prominently
- Transaction date
- Source type described in user-friendly terms
- Ignored status when applicable

Raw message text, sender, reference ID, and bank-message evidence are not displayed.

### Manual transaction detail

The detail shows:

- Name
- Category or credit kind
- Personal spending for an expense

An Edit manual entry action appears only when the record was captured within the preceding 24 hours.

### Manual edit

The user may update:

- Name
- Amount
- Category or credit kind

The current implementation retains the original transaction date during editing.

The user may delete the manual entry from the editor after confirmation. Edit and delete both obey the 24-hour capture window.

Any successful edit or deletion recalculates all totals through KMP. An expired entry cannot be edited or deleted.

### Imported transaction editor

Imported transactions use a local edit draft.

Editable fields:

- Merchant display name
- Expense category, or credit kind for a credit
- Split enabled state
- Split method
- Equal participant count or custom personal amount

The original amount is always read-only.

There are no field-level Save buttons. The top Done action validates and commits the complete draft in one KMP command.

### Done

- Commits merchant, category/credit kind, split metadata, and personal amount atomically.
- Dismisses only after persistence succeeds.
- Leaves the editor open with draft values and an inline error when validation or persistence fails.
- Never changes imported original amount, source date, raw evidence, bank reference, or transaction identity.

### Cancel and dismissal

- Cancel closes immediately when nothing changed.
- Cancel with unsaved draft changes asks whether to discard.
- Interactive dismissal is blocked while unsaved draft changes exist.

### Turning split off

Turning split off stages:

- Personal spending equal to original amount.
- `splitMethod = none`.
- No participant count.

Nothing changes in analytics until Done succeeds.

### Ignore

`Ignore this transaction` is a separate destructive action.

- It asks for confirmation.
- It explains that the record remains in local diagnostic history.
- If draft edits exist, the confirmation explains they will not be applied.
- On success, the transaction is excluded from Home, Growth, category totals, earned income, and investment totals.
- The record remains in Ledger and can be restored.
- Restoration returns the transaction to analytics exactly once.

## 14. Plan Screen

Plan currently contains:

- Heading: Plan
- State: Coming soon
- Explanation that budgets and savings goals are not yet available

It must not show fabricated budgets, fake goal progress, inferred savings, or bank-balance projections.

A future Plan release may add:

- Tracking-cycle spending budget
- Optional category budgets
- `Left in budget = budget - personal spending`
- Independent savings goals with explicit contributions

Those features require separate KMP models and tests before UI implementation.

## 15. Settings Screen

Settings is presented from the top-right gear action and contains the following sections.

### Daily check-in reminder

The user can turn the reminder on or off without a confirmation modal.

Time input uses:

- Two hour digit boxes
- Two minute digit boxes
- AM/PM segmented control

Behavior:

- Each digit field accepts one numeric character.
- Entering a digit advances focus to the next box.
- Hour must be 01 through 12.
- Minutes must be 00 through 59.
- Once both digits of an invalid unit exist, both related boxes turn red and an inline red error appears.
- A valid time converts to 24-hour `HH:mm` before KMP persistence.
- Reminder state and time survive relaunch.
- Native notification scheduling occurs only after KMP save succeeds.
- Turning the reminder off removes the scheduled request.

Current keyboard behavior automatically moves left to right. Reverse focus movement on backspace must be implemented and tested explicitly if required; it is not part of KMP.

### Tracking cycle

- Menu values: 1 through 31.
- Selection persists immediately through KMP.
- Home recalculates immediately.
- Growth remains calendar-based.
- Changing the cycle does not alter transaction dates or amounts.

### Categories

- Shows all user expense categories.
- Add category opens a focused native form.
- Save validates and persists.
- Cancel closes without saving.
- Miscellaneous has no delete control.
- Deleting any other category requires confirmation.
- Confirmed deletion remaps ledger entries in that category to Miscellaneous.
- Gross amounts, personal amounts, investments, income, and net accounting totals remain unchanged.
- Learned rules pointing to the deleted category are removed.

### Automatic message capture

Settings provides a route to set up or review the platform's automatic message-delivery integration.

The setup surface must explain how to pass the full transaction message into DailyMint and how to verify delivery.

### Recent import receipts

Recent platform-delivery receipts may be shown with:

- Timestamp
- Status

Do not show raw message text or sender. Receipt logging is diagnostic only and must not make an otherwise successful import fail.

### Unrecognized messages

When the parser receives a transaction-like message but cannot parse it, Settings may list a local diagnostic item and reason.

The ordinary UI shows only the reason/status, not raw message text, sender, or reference ID.

## 16. Automatic Transaction-Message Flow

Each platform implements a native message-source adapter. The adapter must call the shared import command with:

- Stable source delivery ID when available
- Full message body
- Sender identifier when available
- Capture timestamp in epoch milliseconds

The high-level flow is:

```text
Message reaches platform adapter
        |
Acquire exclusive ledger access
        |
Load current schema snapshot
        |
KMP parser classifies message
        |
Ignored non-transaction? -> receipt only
Unrecognized transaction? -> diagnostic queue
Recognized transaction? -> deterministic transaction identity
        |
Reject duplicate identity
        |
Atomically save updated snapshot
        |
Notify/reload visible native state
```

### Parser outcomes

The parser returns one of:

- Recognized transaction
- Ignored non-transaction
- Unrecognized transaction-like message
- Save/load failure

### Ignored message classes

The shared parser explicitly ignores:

- OTP/security-code messages
- Future debit notices such as `will be debited`
- Credit-card payment acknowledgements that would duplicate the actual bank debit
- Reward-point and promotional card offers
- Messages with no transaction keyword

Ignored messages do not create ledger entries and are not presented as unrecognized transactions.

### Transaction parsing

The parser:

1. Normalizes whitespace.
2. Applies skip rules first.
3. Requires a debit or credit keyword.
4. Finds currency-prefixed/suffixed or supported bare amount patterns.
5. Rejects amounts that occur only in balance/limit context.
6. Chooses debit or credit based on nearest transaction keyword.
7. Resolves bank from sender first and message text second.
8. Extracts account and counterparty when supported.
9. Extracts a supported RRN/reference ID when available.
10. Computes a confidence score and rejects low-confidence results.

### Merchant and category selection

- For debit, prefer the destination/counterparty.
- For credit, prefer the source/counterparty.
- Clean payment handles by removing the domain after `@` for display/tagging.
- Credits remain credits even when merchant words match an expense category.
- Salary/payroll words map a credit to Salary.
- Other generic credits initially map to the legacy Received/Other income meaning.
- Expense category rules are applied before learned merchant rules.
- Unknown expenses become Miscellaneous.

### Duplicate identity

The transaction ID is deterministic and independent of editable merchant/category values.

Identity uses:

- Bank name
- Relevant account-number tail when available
- Debit/credit direction
- Bank reference ID when available
- Otherwise source date plus normalized raw message

Reprocessing the same transaction must not create another entry or change totals.

### Unrecognized retention

- Retain at most the latest 50 unrecognized transaction-like messages in protected local storage.
- Do not add them to ledger totals.
- Repeated deliveries with the same source ID do not duplicate the diagnostic item.
- Promotional and OTP messages are ignored instead of retained as unrecognized.

## 17. Accounting and Analytics Contract

For every non-ignored entry:

```text
personalSpent =
    personalExpensePaise when type == expense and override exists
    original paise when type == expense and no override exists
    0 otherwise

earnedIncome =
    original paise when type == income and creditKind is salary/other_income
    0 otherwise

neutralCredit =
    original paise when type == income and creditKind is reimbursement/refund/own_transfer
    0 otherwise

invested =
    original paise when type == investment
    0 otherwise
```

### Home analytics

- Window: configured tracking cycle.
- Spent: sum of personal spending.
- Income: sum of earned income.
- Invested: sum of investment amounts.
- Neutral credits: retained separately and excluded from Income.
- Categories: personal spending only.
- Biggest spends: personal spending only.

### Growth analytics

- Window: full calendar months or years.
- Money in: earned income.
- Personal spent: personal spending.
- Invested: investment amounts.
- Neutral credits remain separate and are not charted as income.

### Ledger analytics

- Day gross in: original amounts of non-ignored credit entries, including neutral credits.
- Day gross out: original amounts of non-ignored expenses and investments.
- Rows retain personal amount differences for display.

### Invariants

- Editing category never changes original amount.
- Editing personal share never changes original amount.
- Ignoring a transaction never deletes source evidence.
- Deleting a category never changes financial amounts.
- A failed persistence operation publishes no state change.
- Duplicate delivery never changes totals.

## 18. Persistence, Concurrency, and Recovery

### Store contract

KMP depends on a platform `LedgerStore` with:

- `load(): LedgerRead`
- `save(snapshot: String)`

A null snapshot means no file exists. Read failures must throw and must not be treated as an empty ledger.

### Atomicity

- Native storage writes must be atomic.
- All read-modify-write mutations must use exclusive access.
- The engine updates its in-memory snapshot only after storage save succeeds.
- An external message import and an open app must not overwrite one another.

### Corruption behavior

If JSON cannot be decoded or fails schema validation:

- Preserve the existing stored data.
- Set a recoverable load error.
- Block writes that could replace the data with an empty snapshot.
- Show `Ledger unavailable` with an actionable error in relevant screens.

### Capacity

- Maximum ledger entries: 100,000.
- Imports and manual adds beyond capacity fail without mutation.

### Schema migration

- Accept schema versions 1 through 3.
- Migrate loaded data in memory to schema 3.
- Preserve IDs, dates, source evidence, watermark, categories, learned rules, and amounts.
- Schema-1 credits receive explicit credit-kind semantics.
- Imported records gain original parsed name/category audit values.
- A pre-schema-3 reduced personal amount migrates as a custom split.

## 19. Theme, Layout, and Accessibility

### Theme

Use semantic adaptive colors for:

- Base surface
- Raised surface
- Primary and secondary text
- Hairlines
- Flow/accent
- Income
- Spending
- Investment
- Navigation
- Primary action
- Category identity

No screen may hard-code a light-only background, black input field, or white title on a pale surface.

### Layout

- Respect system bars, cutouts, and navigation insets.
- Content scrolls behind neither the fixed dock nor the keyboard.
- Forms remain usable with the keyboard open.
- Support compact and large phones and both orientations.
- Avoid nested decorative cards.
- Keep one meaningful page heading per screen.
- Use stable control dimensions so dynamic content does not shift navigation.

### Touch and assistive technology

- Meet the platform's minimum touch target.
- Provide labels for icon-only controls.
- Expose selected navigation state.
- Use signs and text in addition to color for transaction direction.
- Support larger text without clipping critical actions.
- Focus invalid fields or expose inline errors in reading order.

## 20. Error and Empty-State Contract

### Persistence error

- Keep the current form/editor open.
- Preserve user input.
- Do not update totals.
- Show `Could not save. Please try again.` or the platform-access error.

### Invalid manual form

- Reject invalid amount, blank/long name, invalid date, or invalid category.
- Keep the user's values.
- Display an inline error.

### Invalid imported edit

- Reject malformed personal amount, amount above original, invalid category, invalid split method, or fewer than two equal-split participants.
- Commit none of the draft fields.

### Empty Home

Explain how to add or automatically capture a transaction.

### Empty Growth

Show a labeled no-data chart state.

### Empty Ledger

Explain Add and automatic capture.

### Empty filtered Ledger

Offer Clear filters.

## 21. Shared KMP Command Surface

Native clients should use `LedgerEngine` rather than mutating models.

Important read APIs:

- `categories()`
- `entries()`
- `monthStartDay()`
- `reminderEnabled()`
- `reminderTime()`
- `unrecognizedMessages()`
- `today()`
- `transactionDay(date)`
- `monthSummary(today)`
- `ledgerDays()`
- `trendBuckets(today, years, count)`
- `canEdit(id, platform, nowMillis)`
- `suggestCategory(name, income)`
- `formatAmount(paise)`
- `totals()`
- `equalShare(id, people)`
- `equalShareForAmount(amount, people)`
- `splitPeopleCount(id)`

Important mutation APIs:

- `addEntryWithSplit(...)`
- `editEntry(...)`
- `deleteEntry(...)`
- `updateImportedTransaction(...)`
- `setIgnored(...)`
- `addCategory(...)`
- `deleteCategory(...)`
- `setMonthStartDay(...)`
- `setReminder(...)`
- `importSingleMessage(...)`
- `importMessages(...)`

Deprecated file-staging APIs are not part of the supported product behavior and must not be called by new UI.

## 22. Required User Journeys

### Journey A: Add ordinary expense

1. Open Add.
2. Select Expense.
3. Enter Lunch, Rs 62.88, Food, and date.
4. Save.
5. Home Spent increases by Rs 62.88.
6. Food breakdown increases by Rs 62.88.
7. Ledger shows one matching row.
8. Growth includes Rs 62.88 in the correct calendar month.
9. Relaunch preserves exactly one record.

### Journey B: Add equal-split expense

1. Enter Dinner for Rs 800.
2. Enable split.
3. Choose Equal.
4. Enter 3 people including the user.
5. Preview shows Rs 267 personal spending.
6. Save.
7. Original remains Rs 800.
8. Home, category totals, biggest spends, and Growth use Rs 267.
9. Ledger communicates both personal and original amounts.

### Journey C: Add neutral credit

1. Open Add and select Income.
2. Enter Rs 200 as Reimbursement.
3. Save.
4. Ledger shows a positive Rs 200 credit.
5. Day gross incoming includes Rs 200.
6. Home Income remains unchanged.
7. Spending remains unchanged.

### Journey D: Correct imported expense atomically

1. Open an imported expense.
2. Change merchant and category.
3. Enable a custom Rs 100 share on an original Rs 300 debit.
4. Before Done, Home and Growth remain unchanged.
5. Tap Done.
6. All three draft changes persist together.
7. Original amount, source date, raw evidence, and identity remain unchanged.
8. Home, category totals, and Growth now use Rs 100.

### Journey E: Failed imported edit

1. Stage merchant, category, and personal-share changes.
2. Cause persistence to fail.
3. Tap Done.
4. Editor remains open with all draft values.
5. No field is committed.
6. All totals remain unchanged.

### Journey F: Ignore false positive

1. Open an imported promotional false positive.
2. Tap Ignore this transaction.
3. Cancel confirmation; nothing changes.
4. Confirm ignore.
5. The record remains in Ledger as ignored.
6. It disappears from Home and Growth analytics.
7. Restore it.
8. Analytics return exactly once.

### Journey G: Delete category safely

1. Create category Travel.
2. Record Travel expenses.
3. Delete Travel from Settings.
4. Confirm deletion.
5. Entries move to Miscellaneous.
6. Gross and personal amounts do not change.
7. Home and Growth totals remain identical.

### Journey H: Change tracking cycle

1. Record expenses on the 26th and 27th.
2. Change start day from 1 to 27.
3. Home recalculates to the new cycle.
4. Growth calendar-month buckets do not change.
5. No transaction date or amount changes.

### Journey I: Automatic message delivery

1. Platform adapter receives a recognized transaction message.
2. Submit it to KMP.
3. One ledger entry is atomically saved.
4. Deliver the same message again.
5. No duplicate appears.
6. If the app is open, visible state refreshes without requiring a relaunch.

### Journey J: Reminder

1. Enable reminder.
2. Enter four time digits and AM/PM.
3. Invalid hour/minute shows inline error and red fields.
4. Valid time persists.
5. Relaunch restores enabled state and time.
6. Disabling removes the scheduled notification without a success modal.

## 23. Test Contract

### Shared KMP tests

Must cover:

- Exact paise parsing and formatting.
- Invalid amount rejection.
- Category validation and duplicate detection.
- Category deletion remapping without total changes.
- Tracking-cycle boundaries and short-month clamping.
- Calendar month/year trends.
- Earned versus neutral credit behavior.
- Personal-share effects on categories, totals, and top-five ranking.
- Equal-split whole-rupee ceiling.
- Custom-share bounds and malformed input.
- Atomic imported editor success and failure.
- Immutable source evidence and identity.
- Ignore/restore behavior.
- Schema 1/2 to schema 3 migration.
- Corrupt-storage protection.
- Duplicate message delivery.
- Parser fixtures for every supported bank pattern.
- Promotional, OTP, future-debit, and card-payment acknowledgement skipping.

### Native UI tests on every platform

Must genuinely launch and interact with the app. Compile-only checks do not count.

Cover:

- All five navigation controls and Settings.
- Add Save and Cancel with keyboard visible.
- Category Add Save, Cancel, invalid state, and deletion.
- Time-based Home greeting.
- Manual decimal expense flow.
- Salary and neutral-credit flows.
- Equal and custom split flows.
- Imported transaction draft editor and relaunch persistence.
- Ledger search/filter state across navigation.
- Transaction detail privacy assertions.
- Automatic message appearing while app is open.
- Reminder digit validation and persistence.
- Light/dark themes.
- Compact and large screens.
- Larger accessibility text.
- Safe-area and keyboard overlap.

### Release validation

A release candidate requires:

- Shared tests on JVM and native runtime.
- Native app compilation.
- Native UI suite.
- Physical-device automatic-message test.
- Duplicate-delivery test.
- Upgrade test from a populated older snapshot.
- Manual verification of theme, keyboard, Settings, and background delivery.

## 24. Deferred and Out-of-Scope Features

Not part of the current product:

- File-based transaction import.
- Pending file review.
- Home `See all transactions` action.
- Bank-balance estimation.
- Wealth calculation from message history.
- Named people in split bills.
- Debts, receivables, settlements, or repayment matching.
- Automatic refund-to-expense linking.
- Automatic reimbursement-to-expense linking.
- Goal progress inferred from income minus spending.
- Plan budgets or savings goals before the separate Plan milestone.
- Cloud synchronization.
- Server-side transaction storage.

## 25. Handoff Rules for a New Native Client

1. Use this document for user-visible behavior.
2. Use KMP as the only accounting authority.
3. Implement the five-destination dock before screen-specific polish.
4. Keep Add modal and return to the previous destination.
5. Implement Home from `MonthSummary` without recalculating totals.
6. Implement Growth from `TrendBucket` without using the tracking cycle.
7. Implement Ledger from all-history `ledgerDays()` with native filtering and paging.
8. Route every Home/Ledger transaction row to the same detail screen.
9. Use `updateImportedTransaction` for one atomic imported edit.
10. Keep raw evidence out of all normal UI, logs, screenshots, and accessibility labels.
11. Send platform-acquired messages to `importSingleMessage` or `importMessages`.
12. Reload native observable state only after successful persistence or a detected external save.
13. Do not add a file-import UI or Home See All action.
14. Add native UI tests for each implemented flow before declaring parity.
