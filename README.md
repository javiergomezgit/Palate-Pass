# Palate Pass

A personal food, coffee and drink journal for iOS. Log a place, rate it to half-star
precision, attach photos and a location, and decide who sees it — just you, specific
friends, or everyone.

---

## Features

- **Entries** — place, category (food · coffee · drink · dessert · entertainment · other),
  half-star rating, comment, and up to 5 photos
- **Places** — business search via Apple Maps, with location attached automatically
- **Privacy per entry** — private, shared, or public
- **List** — search, filter by category or minimum rating, pin up to 3 entries to the top
- **Map** — entries pinned by category, with callouts and directions
- **Share extension** — create an entry straight from Photos, picking up the photo's own
  date and location
- **Works offline** — entries save locally and upload themselves once you're back online
- **Auth** — Sign in with Apple, phone (SMS), or email/password

---

## Tech stack

| Layer | Technology |
|---|---|
| UI | UIKit — fully programmatic, no storyboards |
| Architecture | MVVM |
| Local store | `UserDefaults` + Documents directory for images |
| Cloud | Firebase Auth · Cloud Firestore · Firebase Storage |
| Maps | MapKit · CoreLocation |

---

## Getting started

```bash
git clone <repo-url>
open "Palate Pass.xcodeproj"
```

Xcode resolves the Firebase packages on first open.

> **The repo will not build until you restore `Security/GoogleService-Info.plist`.**
> It's gitignored on purpose. Download it from the Firebase console
> (Project settings → Your apps → iOS) and put it at `Security/GoogleService-Info.plist`.
> Don't commit it.

Schemes are **`Palate Pass`** and **`PalatePassShareExtension`**.

Firestore and Storage rules live in the repo and deploy with:

```bash
firebase deploy --only firestore:rules,storage
```
