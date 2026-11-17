# What's My Share

A simple iPhone app for splitting group expenses with friends and family.

- **No sign-up, no bank accounts, no SMS.** Everything stays on your iPhone.
- **Add people from your Contacts** with Apple's contact picker. The app sees only the people you tap, so iOS never asks for Contacts permission.
- **Groups** for trips, households and nights out, each with its own currency.
- **Split any way you like:** equally, exact amounts, percentages or shares (for example, 2 shares for a couple and 1 for a single person).
- **Balances & settle up:** see who owes whom, get the fewest payments that settle everyone, and record repayments.
- **Share a summary** of balances to Messages, WhatsApp or email using the iOS share sheet.

Built with SwiftUI and SwiftData. Requires iOS 17 or later and Xcode 16 or later.

## Project layout

```
WhatsMyShare.xcodeproj      Open this in Xcode
WhatsMyShare/
  WhatsMyShareApp.swift     App entry point + onboarding gate
  Core/SplitCalculator.swift  Pure split/balance/settle-up math (unit tested)
  Models/Models.swift       SwiftData models: Person, ExpenseGroup, Expense, ExpenseShare, Settlement
  Support/                  Money formatting, Contacts picker
  Views/                    Screens
  Assets.xcassets           App icon + accent colour
  PrivacyInfo.xcprivacy     App Store privacy manifest (no tracking, no data collected)
Tests/ShareCoreTests/       Unit tests for the money logic
Package.swift               Lets `swift test` run those tests
```

Money is stored as whole minor units (cents), so splits always add up exactly. Leftover cents go to the people whose shares were closest to rounding up.

## Run it

1. On a Mac, install Xcode from the Mac App Store.
2. Open `WhatsMyShare.xcodeproj`.
3. Pick an iPhone simulator and press **⌘R**.

Run the unit tests with `swift test` from the repository folder.

GitHub Actions (`.github/workflows/ios.yml`) runs the tests and builds the app on every push.

## Put it on the App Store

1. **Join the Apple Developer Program** ($99/year) at developer.apple.com.
2. In Xcode, select the **WhatsMyShare** target. Under **Signing & Capabilities**, choose your **Team**. If `com.vijaygpatil82.whatsmyshare` is already taken, change the **Bundle Identifier**.
3. Test on your own iPhone: plug it in, select it as the run destination and press **⌘R**.
4. In **App Store Connect** (appstoreconnect.apple.com), go to **Apps → + → New App** and use the same bundle ID.
5. In Xcode, set the run destination to **Any iOS Device**, then choose **Product → Archive → Distribute App → App Store Connect → Upload**.
6. In App Store Connect, fill in the listing:
   - **Screenshots** for 6.9" and 6.5" iPhones. Take them in the simulator with ⌘S.
   - **Description, keywords and support URL.**
   - **Privacy policy URL.** A short page saying "all data stays on your device; nothing is collected" is enough.
   - **App Privacy → Data Not Collected.**
   - **Export compliance:** the app uses no encryption beyond Apple's own, so answer "None of the algorithms mentioned above".
7. Optionally add the build to **TestFlight** to try it with family first, then **Submit for Review**.

## Ideas for later

- iCloud sync and live shared groups through CloudKit sharing. The models already follow CloudKit's rules (optional relationships, default values).
- Receipt photos, recurring expenses, CSV export, and an iPad layout.
