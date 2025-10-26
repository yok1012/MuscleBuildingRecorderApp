# Heart Rate Monitoring Testing Instructions

## Debug Logging
The app now includes extensive debug logging to trace heart rate data flow. When running the app, check the console for the following messages:

### iOS App
1. **Connection Flow:**
   - `HeartRateManager: Connecting to healthKit...`
   - `HealthKit: Starting connection...`
   - `HealthKit: Authorization granted`
   - `HealthKit: Workout session started`
   - `HealthKit: Heart rate query started`
   - `HeartRateManager: Successfully connected to healthKit`

2. **Data Flow:**
   - `HealthKit: Initial query returned X samples`
   - `HealthKit: Processed heart rate: XX.X bpm at [timestamp]`
   - `HeartRateManager: Received heart rate: XX.X bpm`

### Apple Watch App
1. **Authorization:**
   - `Watch: Requesting HealthKit authorization...`
   - `Watch: HealthKit authorization granted`

2. **Workout Session:**
   - `Watch: Starting workout...`
   - `Watch: Workout session started`
   - `Watch: Data collection started successfully`

3. **Heart Rate Data:**
   - `Watch: Heart rate received: XX.X bpm`

## Testing Steps

### For iOS App:
1. Launch the app on your iPhone
2. Open the Console app on your Mac
3. Filter by your app name "MuscleBuildingRecorder"
4. Start a session by tapping "スタート"
5. Watch the console for debug messages
6. Verify that heart rate values appear in the UI

### For Apple Watch App:
1. Launch the app on your Apple Watch
2. Tap "開始" to start a workout
3. The heart rate should start appearing at the top of the screen
4. Check Xcode console for debug messages

## Troubleshooting

### If no heart rate data appears:
1. **Check HealthKit permissions:**
   - Go to Settings → Privacy & Security → Health → MuscleBuildingRecorder
   - Ensure "Heart Rate" is enabled for both Read and Write

2. **For Apple Watch:**
   - Ensure the watch is worn snugly
   - Wait 10-15 seconds after starting the workout for readings to stabilize

3. **Check Console Logs:**
   - Look for any error messages in the format:
     - `HealthKit: Initial query error: ...`
     - `HealthKit: Update handler error: ...`
     - `HeartRateManager: Failed to connect to ...`

### Expected Behavior:
- Heart rate values should update every few seconds
- The UI should display both current heart rate (bpm) and heart rate slope (bpm/分)
- Data should be saved with each set record in the session

## Important Notes:
- The app now looks for heart rate samples from the past 60 seconds when starting a query
- Debug logging is extensive to help identify any remaining issues
- The app supports HealthKit, Bluetooth LE, and AirPods Pro heart rate sources (though AirPods Pro heart rate may not be available on all devices)