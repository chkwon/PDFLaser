# PDF Laser

PDF Laser is a universal SwiftUI app for presenting PDF slide decks with a temporary laser pointer and simple in-session pen markup.

## What It Does

- Opens a user-selected PDF.
- Presents exactly one fitted page at a time.
- Supports macOS keyboard navigation: right, down, and space for next; left, up, and backspace for previous.
- Supports iPadOS touch navigation, on-screen previous/next controls, and best-effort external keyboard arrows.
- Provides five tools: None, Dot Laser, Trail Laser, Pen, and Erase.
- Keeps laser effects temporary.
- Keeps pen markup in memory per page for the current app session, with stroke-based erase.
- Supports clearing or undoing markup on the current page.
- Exports a new flattened PDF copy with pen markup when the user explicitly chooses Save Marked PDF.

## Privacy And Storage

PDF Laser does not use iCloud, cloud sync, a document browser, autosave, or app-managed document storage. It reads the PDF selected by the user and never modifies that original file. Laser effects remain temporary. Pen markup is session-only unless the user explicitly exports a new flattened PDF copy with Save Marked PDF.

## Architecture

- SwiftUI owns the application shell and toolbar.
- PDFKit loads PDF data and draws the current page.
- AppKit and UIKit wrappers provide page rendering and input capture.
- Shared model code stores navigation state, tool selection, laser settings, and pen strokes.
- All laser and pen points use normalized page-relative coordinates in the `0...1` range, so overlays stay aligned when the window or screen size changes.

## External Display

The iPadOS target includes an `ExternalDisplayManager` stub. The intended follow-up architecture is to attach a presentation-only window to the external `UIScreen`, render the same `PDFSlideView` without the toolbar there, and keep controls on the iPad display. The MVP keeps the iPad app fully usable without an external display.

## Build

This repo uses XcodeGen:

```sh
xcodegen generate
open PDFLaser.xcodeproj
```

Build the `PDFLaser-macOS` or `PDFLaser-iPadOS` scheme from Xcode.

## macOS Binary Release

The `macos-release` GitHub Actions workflow builds the macOS app, signs it with a Developer ID Application certificate, notarizes it with Apple, staples the notarization ticket, and uploads a zip artifact named like `PDF-Laser-v0.1-macOS-universal.zip`.

Required GitHub repository secrets:

- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12`.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`: password for the exported `.p12`.
- `KEYCHAIN_PASSWORD`: temporary CI keychain password.
- `ASC_KEY_ID`: App Store Connect API key ID.
- `ASC_ISSUER_ID`: App Store Connect issuer ID.
- `ASC_PRIVATE_KEY`: contents of the App Store Connect `AuthKey_*.p8` private key.

To create the certificate secret from an exported `.p12` on macOS:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Run the workflow manually with version `v0.1`, or push a `v0.1` tag. The workflow overrides the app marketing version from the tag/input, so `v0.1` produces app version `0.1`. The app remains outside the Mac App Store and does not add cloud storage or automatic document saving.
