# Technical Notes

## Collision Mask

`DigitMask` renders the current `HH:mm` string into a Core Graphics bitmap using Core Text. The alpha channel is copied into a compact byte buffer where solid text pixels are obstacles and transparent pixels are free space.

The particle engine uses:

- `isObstacle(point:)` to test mask occupancy in scene coordinates.
- `approximateNormal(point:)` to estimate a local surface normal from finite differences.

On collision, a particle is pushed outward along the estimated normal. Velocity into the glyph is reflected with low restitution, then tangential velocity is damped so particles slide and settle around the digit contours instead of bouncing aggressively.

The visible time is an `SKSpriteNode` built from the same bitmap render, so the collision source and foreground digits stay aligned. The mask is rebuilt only when the minute changes or the SpriteKit scene size changes.

## Particle Simulation

Particles are plain Swift structs with position, velocity, radius, and alpha. The app does not create SpriteKit physics bodies per particle. `ParticleSystem` performs manual integration with a fixed 30 Hz timestep, edge collision, glyph collision, and light velocity damping.

Rendering uses reusable `SKSpriteNode` instances with a small circular texture. Nodes are created once and updated in place each frame; they are not created or destroyed inside `update()`.

## Motion

`MotionManager` uses `CMMotionManager` accelerometer updates on physical Apple Watch hardware. The accelerometer vector is low-pass filtered, clamped, and scaled into SpriteKit screen-space acceleration.

Simulator builds use an animated fallback vector because real watch accelerometer data is unavailable there.

## Performance Limits

The default active count is 800 particles. Constants are provided for 400, 800, 1200, and 2000 particles in `PerformanceConfig`.

The scene targets 30 fps to keep CPU and battery use conservative. A simple adaptive check reduces active particles in 100-particle steps if observed frame timing exceeds the budget. Real battery and thermal behavior should be checked on physical Apple Watch hardware before increasing the default particle count.
