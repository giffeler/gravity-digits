# Technical Notes

## Collision Mask

`DigitMask` renders the current `HH:mm` string into a Core Graphics bitmap using Core Text. The alpha channel is copied into a compact byte buffer where solid text pixels are obstacles and transparent pixels are free space.

The alpha buffer is stored in SpriteKit scene coordinates with `(0, 0)` at the lower-left corner. Core Graphics bitmap rows are copied bottom-up into the mask so collision sampling and the visible `SKTexture` use the same on-screen digit position.

The particle engine uses:

- `isObstacle(point:)` to test mask occupancy in scene coordinates.
- `contactPoint(around:radius:)` to find the nearest solid mask pixel inside a particle disk.
- `approximateNormal(point:)` to read a precomputed local surface normal.

The mask also precomputes a conservative contact broad-phase map dilated by the largest supported particle radius. Points outside that map cannot touch any glyph pixel and skip the exact disk scan; points inside the map still use the exact pixel-level test, so collision coverage is unchanged.

On collision, a particle is pushed outward along the estimated normal. Velocity into the glyph is reflected with low restitution, then tangential velocity is damped so particles slide and settle around the digit contours instead of bouncing aggressively.

The visible time is an `SKSpriteNode` built from the same bitmap render, so the collision source and foreground digits stay aligned. The mask is rebuilt only when the minute changes or the SpriteKit scene size changes.

## Particle Simulation

Particles are plain Swift structs with position, velocity, radius, and alpha. The app does not create SpriteKit physics bodies per particle. `ParticleSystem` performs manual integration with a fixed 30 Hz timestep, display-boundary collision, glyph collision, and light velocity damping.

Each frame's movement is split into bounded substeps before boundary and glyph resolution. Glyph checks also sweep between the previous and current particle positions and refine the first contact point, reducing tunneling when particles accelerate quickly across thin digit strokes or the colon.

The display boundary is modeled as a rounded rectangle with a small inset, so particles avoid the rounded Apple Watch screen corners instead of treating the scene as a full rectangular canvas. The corner radius is tuned separately from the edge inset: the inset keeps the top, bottom, left, and right bounds aligned, while the larger corner radius better matches the visible rounded display corners. The same boundary is used when spawning particles and after collision correction, which keeps particles from getting stranded outside the visible field.

Rendering uses reusable `SKSpriteNode` instances with a small circular texture. Nodes are created once and updated in place each frame; they are not created or destroyed inside `update()`.

## Motion

`MotionManager` uses `CMMotionManager` accelerometer updates on physical Apple Watch hardware. The accelerometer vector is low-pass filtered, clamped, and scaled into SpriteKit screen-space acceleration.

Simulator builds use an animated fallback vector because real watch accelerometer data is unavailable there.

## Performance Limits

The default active count is 800 particles. Constants are provided for 400, 800, 1200, and 2000 particles in `PerformanceConfig`.

The scene targets 30 fps to keep CPU and battery use conservative. A simple adaptive check reduces active particles in 100-particle steps if observed frame timing exceeds the budget. Real battery and thermal behavior should be checked on physical Apple Watch hardware before increasing the default particle count.
