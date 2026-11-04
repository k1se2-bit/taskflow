# TaskFlow

Mobile task management app built with Flutter and Firebase.

## Setup

```bash
flutter create . --org com.example --project-name taskflow
dart pub global activate flutterfire_cli
flutterfire configure
flutter pub get
flutter run
```

Enable in Firebase Console:

- Authentication -> Email/Password
- Firestore Database

## Current features

- Email/password login screen
- Personal task list
- Create task with title, description and deadline
- Mark task as completed
- Firestore repository and security rules
- Flutter, Riverpod, go_router, Material 3
