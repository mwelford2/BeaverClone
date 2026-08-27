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

## Sidestore/AltStore Distribution
The IPA for distribution via Sidestore or AltStore can be found in the `releases` directory.

The `releases.json` file contains the metadata required for Sidestore/AltStore.

## License
MIT