# Gravity Digits

Gravity Digits is a native watchOS prototype that looks like a custom digital clock app for Apple Watch. It is not a third-party Apple Watch system face. Apple does not provide a public API for installing fully custom watch faces, so this project runs as a normal watchOS app.

## Requirements

- Xcode 26 or newer
- watchOS simulator or a paired Apple Watch
- Swift / SwiftUI / SpriteKit / Core Motion

No private APIs, network services, data collection, or background execution assumptions are used.

## Build

Open `GravityDigits.xcodeproj` in Xcode, select the `GravityDigits` scheme, then choose a watchOS simulator or paired Apple Watch destination.

From Terminal:

```sh
xcodebuild -project GravityDigits.xcodeproj -scheme GravityDigits -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/gravitydigits-dd build
```

The explicit `/tmp` DerivedData path avoids code-signing failures caused by File Provider extended attributes when this repository lives in a synced Documents folder.

## Run In Simulator

The simulator does not provide live Apple Watch accelerometer input. In simulator builds, `MotionManager` uses an animated fallback gravity vector so particles keep moving and settling around the digits.

## Run On Physical Apple Watch

1. Open the project in Xcode.
2. Select your own Apple Developer team in Signing & Capabilities.
3. Replace the placeholder bundle identifier with an identifier registered to your Apple Developer account.
4. Select a paired Apple Watch destination.
5. Build and run.

On device, `CMMotionManager` reads accelerometer updates while the app is active. Tilting the watch changes the screen-space gravity vector. The app stops accelerometer updates when inactive.

## Behavior

- Displays the current time in 24-hour `HH:mm` format.
- Renders the time into an offscreen bitmap mask once per minute or when layout changes.
- Uses that same rendered texture as the visible foreground time.
- Simulates particles manually with a fixed timestep.
- Treats white mask pixels as solid glyph obstacles.
- Treats screen edges as solid boundaries.
- Starts with 800 particles and can reduce the active count if frame timing is too high.

## Known Limitations

- The simulator gravity source is synthetic.
- Physical accelerometer behavior must be validated on real Apple Watch hardware.
- The app icon asset catalog is minimal for prototype builds.
- WidgetKit complication support is intentionally not included yet; a complication could launch the app and show a static preview, but it should not run the live SpriteKit simulation.

## Apple Platform Limitation

Gravity Digits is a watchOS app. It does not create, install, replace, or claim to be a real Apple Watch face.
