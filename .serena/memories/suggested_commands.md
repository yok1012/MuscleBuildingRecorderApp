# Suggested Commands for MuscleBuildingRecorder Development

## Build Commands

### iOS App Build
```bash
# Simulator build
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Physical device build
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  build
```

### Watch App Build
```bash
# Simulator build
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme "MuscleBuildingRecorderWatchTrue Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
  build

# Physical device build
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme "MuscleBuildingRecorderWatchTrue Watch App" \
  -destination 'generic/platform=watchOS' \
  -configuration Release \
  build
```

### Swift Package Manager Build (for shared components)
```bash
swift build --package-path . -c debug --target WorkoutTimerCore
```

## Testing Commands
```bash
# Run all tests
xcodebuild test -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Run specific test
xcodebuild test -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:MuscleBuildingRecorderTests/TestClassName/testMethodName
```

## Archive and Distribution
```bash
# Create archive for App Store/TestFlight
xcodebuild archive \
  -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -configuration Release \
  -archivePath ./build/MuscleBuildingRecorder.xcarchive \
  -destination 'generic/platform=iOS'
```

## Maintenance Commands
```bash
# Clean build
xcodebuild clean -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder

# Reset derived data (if build issues)
rm -rf ~/Library/Developer/Xcode/DerivedData

# List available simulators
xcrun simctl list devices available

# List project schemes
xcodebuild -project MuscleBuildingRecorder.xcodeproj -list
```

## Git Commands (Darwin/macOS)
```bash
# Check status
git status

# Stage changes
git add .
git add -A  # Stage all including deletions

# Commit with emoji support
git commit -m "feat: Add new feature 🤖 Generated with [Claude Code]"

# Current branch operations
git branch  # List branches
git checkout v2  # Switch to v2 branch
git push origin v2  # Push to remote
```

## Icon Generation Commands (Watch App)
```bash
# Generate Watch app icons from 1024x1024 source
cd "MuscleBuildingRecorderWatchTrue Watch App/Assets.xcassets/AppIcon.appiconset"
sips -Z 48 AppIcon1024x1024.png --out AppIcon-48.png
sips -Z 55 AppIcon1024x1024.png --out AppIcon-55.png
sips -Z 58 AppIcon1024x1024.png --out AppIcon-58.png
# Continue for all required sizes: 87, 80, 88, 92, 100, 102, 108, 172, 196, 216, 234, 258
```

## Utility Commands
```bash
# Check Swift version
swift --version

# View project structure
find . -name "*.swift" -type f | head -20

# Search for pattern in codebase
grep -r "SessionManager" --include="*.swift"

# Count lines of Swift code
find . -name "*.swift" -type f -exec wc -l {} + | sort -n
```

## Troubleshooting Commands
```bash
# Fix "Missing Icons" error
plutil -lint "MuscleBuildingRecorderWatchTrue Watch App/Info.plist"

# Check code signing
codesign -d --entitlements - ./build/MuscleBuildingRecorder.app

# Validate archive
xcrun altool --validate-app -f build/MuscleBuildingRecorder.xcarchive
```

## Note on Formatting/Linting
Currently, no SwiftLint or SwiftFormat configuration is present in the project. Consider adding these tools for consistent code style enforcement.