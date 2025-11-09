# Code Style and Conventions for MuscleBuildingRecorder

## Swift Language Version
- Swift 5.0
- iOS Deployment Target: 17.0
- watchOS Deployment Target: 10.0

## Naming Conventions

### Classes and Structs
- **PascalCase**: `SessionManager`, `WorkoutManager`, `HeartRateService`
- Suffix patterns:
  - `Manager` for singleton coordinators
  - `Service` for data providers
  - `Controller` for Core Data managers
  - `View` for SwiftUI views
  - `Sheet` for modal views

### Properties and Variables
- **camelCase**: `currentPhase`, `totalWorkTime`, `heartRateManager`
- Boolean properties typically start with `is`, `has`, `should`
- Published properties marked with `@Published` for SwiftUI observation

### Methods
- **camelCase**: `startSession()`, `togglePhase()`, `loadDefaultExerciseValues()`
- Verb-first naming: `save`, `load`, `update`, `calculate`, `reset`

## Code Organization

### File Structure
- One primary type per file
- File name matches the primary type name
- Related extensions in the same file

### Class/Struct Organization
1. Static properties
2. @Published properties (for ObservableObject)
3. Public/Internal properties
4. Private properties
5. Initializers
6. Public methods
7. Private methods
8. Extensions

### Access Control
- Explicit `private` for non-public members
- Singleton pattern using `static let shared` with `private init()`
- `internal` is default and typically not written explicitly

## SwiftUI Patterns
- Use `@StateObject` for owned objects
- Use `@ObservedObject` for injected objects
- Use `@Published` for observable properties
- Use `@State` for view-local state
- Use `@Binding` for two-way data flow

## Core Data Patterns
- Entity names: Singular (`Session`, `SetRecord`, `ExerciseMaster`)
- Relationships use descriptive names
- Use factory methods for entity creation
- Immediate saves after modifications

## Documentation
- Inline comments for complex logic (Japanese comments are acceptable)
- Use `// MARK: -` for section organization
- Debug prints include context: `print("SessionManager: Starting session...")`
- Emoji in debug prints for visual distinction: `🎬`, `✅`, `⚠️`

## Error Handling
- Guard statements for early returns
- Optional unwrapping with guard or if-let
- Meaningful print statements for debugging
- No force unwrapping except where absolutely safe

## Singleton Pattern
```swift
class Manager: ObservableObject {
    static let shared = Manager()
    private init() { 
        // initialization
    }
}
```

## Combine Integration
- Import Combine when using @Published
- Use `AnyCancellable` for subscription management
- PassthroughSubject for event streams
- sink pattern for subscriptions

## Thread Safety
- Main thread updates for UI properties
- DispatchQueue.main.async for UI updates from background
- Print current thread in debug statements when relevant

## Constants
- Hardcoded strings for Japanese UI text (no localization files currently)
- Time intervals in seconds (TimeInterval type)
- Default values defined in init() or property declarations

## Import Organization
Typical import order:
1. Foundation
2. System frameworks (SwiftUI, Combine, CoreData, etc.)
3. Third-party (none currently)
4. Local modules

## Testing Conventions
- Test files suffixed with `Tests`
- XCTest framework
- Test methods prefixed with `test`
- Limited test coverage currently

## No Current Enforcement
- No SwiftLint configuration
- No SwiftFormat configuration
- Manual code review for style compliance
- Consider adding linting tools for consistency