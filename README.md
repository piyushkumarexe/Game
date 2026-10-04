# Dustbound RV — Android & iOS

An original physics road-trip game packaged as installable mobile apps. Guide a tired old RV across ravines, pine passes, boulder fields, and one final ridge before sunset.

**This repository now builds Android and iOS apps—not a GitHub Pages website or PWA.** The complete game renderer, fonts, art, sound system, and route are bundled inside each native package, so gameplay does not require a network connection.

> Dustbound RV has original branding, code, procedural art, generated mobile artwork, sounds, and level design. It is inspired by the chaotic road-trip genre without copying another game's protected textures, models, audio, or maps.

## Download a GitHub build

Open the latest **Android and iOS Builds** workflow run under the repository's **Actions** tab and download one of these artifacts:

- `dustbound-rv-android`
  - `dustbound-rv.apk` — install directly on an Android phone for testing
  - `dustbound-rv.aab` — Android App Bundle for build validation
- `dustbound-rv-ios`
  - `dustbound-rv-ios-simulator.zip` — compiled iPhone/iPad Simulator app

Apple requires an Apple Developer signing identity and provisioning profile before an iOS app can be installed on a physical device or submitted to TestFlight. The included Xcode project is ready to be signed under your Apple team.

## Controls

| Touch control | Keyboard during development | Action |
|---|---|---|
| **Drive** | `W` / `↑` | Accelerate |
| **Brake** | `S` / `↓` | Brake and reverse |
| **Tilt** | `A D` / `← →` | Balance the RV in the air |
| **Cable** | `Space` | Pull out of a bad climb |
| **Patch** | Touch button | Spend two parts to repair |
| Pause | `P` | Pause the run |

Collect fuel cans and spare parts, stop at both trail camps, and manage the rig's health. Hard landings and boulders damage the RV.

## Mobile features

- Android APK/AAB project targeting Android SDK 36, with Android 7.0 as the minimum
- iOS Xcode project targeting iOS 15 and newer
- Locked landscape orientation and immersive full-screen presentation
- Native haptic feedback, status-bar handling, and screen-orientation integration
- Original Android adaptive icon, iOS app icon, and native launch artwork
- Responsive multi-touch controls and safe-area support
- Locally bundled fonts, graphics, and synthesized Web Audio—no remote assets
- Offline save data for best-distance progress
- Automated Android and iOS builds on GitHub-hosted runners

## Gameplay systems

- Custom RV suspension, airborne rotation, traction, and terrain handling
- A 14.4 km route across multiple biomes with dynamic lighting
- Fuel, vehicle damage, field repairs, recovery cable, camps, and collectibles
- Parallax scenery, dust, screen shake, audio, and mobile haptics

## Technology

- Phaser 4.2.1
- Capacitor 8.5.2 with Android and iOS native projects
- Vite 8.3.2
- TypeScript 7.0.2 in strict mode
- Android Gradle Plugin 8.13 / Gradle 8.14.3
- Swift Package Manager for the iOS Capacitor runtime

Direct dependency versions are pinned in `package.json` and `package-lock.json` for reproducible builds.

## Development

Requirements:

- Node.js 22 or newer
- Android Studio/JDK 21 for Android development
- macOS with Xcode for iOS development

Install and synchronize both native projects:

```bash
npm ci
npm run sync:native
```

### Android

```bash
npm run android:sync
npm run android:open
```

Or build from the command line:

```bash
cd android
./gradlew assembleDebug bundleDebug
```

### iOS

```bash
npm run ios:sync
npm run ios:open
```

Choose your signing team in Xcode before running on an iPhone or creating a TestFlight archive.

## GitHub automation

`.github/workflows/ci.yml` builds both platforms on pushes, pull requests, and manual workflow runs. Android produces installable APK and AAB artifacts; macOS compiles and packages the iOS Simulator app.
