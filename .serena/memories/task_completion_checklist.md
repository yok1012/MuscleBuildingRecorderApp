# Task Completion Checklist for MuscleBuildingRecorder

When completing a task, ensure the following steps are performed:

## 1. Code Quality Checks
- [ ] Verify code follows project naming conventions (camelCase for methods/properties, PascalCase for types)
- [ ] Ensure proper access control (private for internal implementation)
- [ ] Add appropriate debug print statements with context identifiers
- [ ] Check for force unwrapping - use guard/if-let instead
- [ ] Verify @Published properties are properly declared for SwiftUI updates

## 2. Build Verification
- [ ] Run iOS simulator build:
  ```bash
  xcodebuild -project MuscleBuildingRecorder.xcodeproj \
    -scheme MuscleBuildingRecorder \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    build
  ```

- [ ] Run Watch simulator build (if Watch app affected):
  ```bash
  xcodebuild -project MuscleBuildingRecorder.xcodeproj \
    -scheme "MuscleBuildingRecorderWatchTrue Watch App" \
    -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
    build
  ```

- [ ] Check for build warnings and resolve if possible

## 3. Testing
- [ ] Run existing tests:
  ```bash
  xcodebuild test -project MuscleBuildingRecorder.xcodeproj \
    -scheme MuscleBuildingRecorder \
    -destination 'platform=iOS Simulator,name=iPhone 16'
  ```

- [ ] Add new tests for significant functionality (if applicable)
- [ ] Manually test the feature in simulator/device

## 4. Core Data Changes (if applicable)
- [ ] Create new version in WorkoutModel.xcdatamodeld
- [ ] Never modify existing version
- [ ] Verify DataController handles migration
- [ ] Test with existing data

## 5. Watch Connectivity (if applicable)
- [ ] Verify bidirectional communication works
- [ ] Check fallback to updateApplicationContext when unreachable
- [ ] Test with Watch app in foreground and background
- [ ] Ensure timestamp-based sync for state consistency

## 6. Documentation Updates
- [ ] Update CLAUDE.md if architectural changes made
- [ ] Update inline comments for complex logic
- [ ] Add MARK comments for new sections
- [ ] Document any new build commands or requirements

## 7. Git Commit
- [ ] Stage relevant files (avoid committing .DS_Store, xcuserdata, etc.)
- [ ] Write descriptive commit message following format:
  ```
  feat/fix/chore: Brief description
  
  Detailed explanation if needed
  
  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  Co-Authored-By: Claude <noreply@anthropic.com>
  ```

## 8. Clean Up
- [ ] Remove debug/temporary code
- [ ] Clean up excessive print statements
- [ ] Remove commented-out code blocks
- [ ] Delete temporary test files

## 9. Performance Considerations
- [ ] Check for memory leaks (weak self in closures)
- [ ] Verify no unnecessary timer/publisher retains
- [ ] Ensure proper cleanup in deinit (if needed)
- [ ] Monitor battery impact for sensor/heart rate features

## 10. Final Verification
- [ ] Clean build folder and rebuild:
  ```bash
  xcodebuild clean -project MuscleBuildingRecorder.xcodeproj -scheme MuscleBuildingRecorder
  ```
- [ ] Verify app launches without crashes
- [ ] Check Dynamic Island/Live Activity updates (if affected)
- [ ] Confirm sensor data logging works (if affected)

## Notes
- If SwiftLint/SwiftFormat are added in future, run them before committing
- For App Store releases, also validate archive and check for missing icons
- Consider impact on battery life for Watch app changes
- Test on both simulator and physical device when possible