# BeaverClone

A note-taking app with AI-powered transcription and iCloud sync.

## Features
- Record and transcribe notes using speech recognition
- AI-powered summarization and action item extraction
- iCloud sync via CloudKit
- Available on iOS and macOS

## Building
This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`.

To generate the project:
```bash
xcodegen generate
```

## Installing via AltStore / SideStore / Feather
Add this source URL in AltStore, SideStore, or Feather to install Beaver and get notified of updates:

```
https://raw.githubusercontent.com/mwelford2/BeaverClone/main/apps.json
```

New versions are published as GitHub Releases with the IPA attached; `apps.json` on `main` is updated to point at each new release.

## License
MIT