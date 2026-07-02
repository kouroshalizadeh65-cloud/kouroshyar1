# Build fixes for v3.4.0

- Removed unused import from `lib/features/export/export_text_screen.dart`.
- Updated GitHub Actions build workflow to install Android SDK 36.
- Forced Android `compileSdk` and `targetSdk` to 36 before release build so `file_picker` and Android lifecycle dependencies can build successfully.
