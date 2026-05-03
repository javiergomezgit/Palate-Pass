# Palate Pass

A personal food, coffee, and drink journal for iOS. Log what you eat and drink, rate it, attach a photo and location, and decide who sees it — just you, friends, or everyone.

---

## Features

- **Log entries** — name, place, category (food / coffee / drink / dessert / snack), rating (½-star precision), comment, and photo
- **Map view** — see all your entries pinned on a map; drag the pin to adjust the location
- **Privacy per entry** — private, shared with friends, or public
- **Auth** — sign in with Apple, phone number (SMS OTP), or email/password
- **Friends & sharing** *(coming soon)* — share ratings with specific friends or make them discoverable

---

## Tech stack

| Layer | Technology |
|---|---|
| UI | UIKit — fully programmatic, no storyboards |
| Architecture | MVVM |
| Local persistence | `UserDefaults` + Documents directory (images) |
| Cloud backend | Firebase (Auth · Firestore · Storage · FCM) |
| Maps | MapKit |
| Location | CoreLocation |
| Auth providers | Apple Sign In · Phone (SMS) · Email/Password |

---

## Project structure

```
Palate Pass/
├── Controllers/
│   ├── Auth/               # Login & signup screens
│   │   ├── AuthLandingViewController.swift
│   │   ├── EmailAuthViewController.swift
│   │   ├── PhoneAuthViewController.swift
│   │   └── PhoneOTPViewController.swift
│   ├── Home/               # List + Map tab
│   ├── Detail/             # Entry detail view
│   ├── Add/                # New / edit entry form
│   └── Settings/
├── ViewModels/
├── Models/
│   └── FoodEntry.swift
├── Services/
│   └── DataManager.swift   # Local CRUD (will migrate to Firebase)
├── Views/
│   ├── Theme.swift         # Colors, card style, category colors
│   ├── StarRatingView.swift
│   └── EntryCell.swift
└── Extras/
    ├── AppDelegate.swift
    ├── SceneDelegate.swift  # Auth ↔ main app routing
    └── UIAlertController+Simple.swift
```

---

## Firebase setup

> **`GoogleService-Info.plist` is gitignored — never commit it.**

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add an iOS app with this bundle ID
3. Download `GoogleService-Info.plist` and add it to the Xcode project root
4. In Xcode: **File → Add Package Dependencies** → `https://github.com/firebase/firebase-ios-sdk`
   - Products to add: `FirebaseAuth`, `FirebaseCore`
5. Uncomment the two Firebase lines in `AppDelegate.swift` and `SceneDelegate.swift`

### Services used

| Service | Purpose |
|---|---|
| **Firebase Auth** | Phone SMS, email/password, Apple Sign In |
| **Cloud Firestore** | User profiles and entries |
| **Firebase Storage** | Profile photos and entry images |
| **Firebase Cloud Messaging** | Push notifications |

---

## Getting started

```bash
git clone <repo-url>
open "Palate Pass.xcodeproj"
```

Add `GoogleService-Info.plist` before building (see Firebase setup above).

---

## Roadmap

- [ ] Wire Firebase Auth (phone, email, Apple)
- [ ] Migrate DataManager to Firestore
- [ ] Upload images to Firebase Storage
- [ ] User profiles
- [ ] Friends & sharing
- [ ] Push notifications (FCM)
