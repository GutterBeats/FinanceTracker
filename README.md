# Finance Tracker

A personal finance app for iOS and macOS built with SwiftUI, SwiftData, and Firebase.

## Features

- **Budget periods** — group income and expense categories into named budget periods with a start and end date. The app auto-selects whichever budget contains today's date.
- **Categories** — income and expense categories each belong to a budget period. One expense category can be marked as the "calculated remainder," which automatically receives whatever income is left after all other expense limits are accounted for.
- **Transactions** — manually log transactions, tag them with a category and payment account, and filter by budget period, date range, or account.
- **Payment accounts** — track credit cards, checking, and savings accounts. Credit card transactions show the running balance owed for the current month, and payments reduce that balance rather than counting against a category budget.
- **Firestore sync** — data syncs across devices via Cloud Firestore using a last-write-wins strategy keyed on `updatedAt`. Deletes are soft-tombstoned in Firestore so they propagate to other devices. Budgets are synced before categories to ensure relationship integrity on merge.
- **Firebase Auth** — sign-in is required; the app gates all content behind `AuthView` and starts/stops sync listeners around the signed-in session.

## Architecture

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Local persistence | SwiftData (`@Model`, `ModelContainer`) |
| Remote sync | Firebase Firestore (snapshot listeners) |
| Auth | Firebase Auth |

### Data model

```
Budget (start/end dates)
  └── Category[] (income or expense, optional monthly limit)
        └── Transaction[] (amount, date, note, optional payment account)

PaymentAccount (credit card / checking / savings)
  └── Transaction[] (tagged via optional relationship)
```

Deleting a `Budget` cascades to its `Category` records. Deleting a `Category` nullifies the `category` field on its transactions (they become uncategorized). Deleting a `PaymentAccount` nullifies the `paymentAccount` field on its transactions.

## Requirements

- Xcode 16+
- iOS 18+ / macOS 15+
- A Firebase project with Firestore and Authentication (Email/Password) enabled
- `GoogleService-Info.plist` placed at `Finance Tracker/Finance Tracker/GoogleService-Info.plist`

## Setup

1. Clone the repo.
2. Open `Finance Tracker/Finance Tracker.xcodeproj` in Xcode.
3. Add your `GoogleService-Info.plist` from the Firebase console.
4. Build and run.

Firestore security rules are not included in this repo — configure them in the Firebase console to restrict reads and writes to authenticated users.
