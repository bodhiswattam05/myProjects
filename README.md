# Cue

An on-device teleprompter for iPhone and iPad. Scripts, recordings and speech recognition never leave the device.

- **Open `Cue.xcodeproj`**, set your bundle ID in `Config/Signing.xcconfig`, pick your team, and run. See [TESTING.md](TESTING.md).
- What's built, what isn't, and what still needs checking on hardware: [STATUS.md](STATUS.md).
- Pure-Swift logic (markup parser, read time, speech-to-script aligner, delivery coach) lives in `Packages/CueCore` and tests on any platform with `swift test --package-path Packages/CueCore`.
