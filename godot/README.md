# WreckWorks: Wrecking Ball (Godot prototype)

A separate Godot 4 project for the mobile-friendly WreckWorks demolition game. This version is deliberately built in Godot rather than Three.js.

## Run locally
Open this `godot/` folder in Godot 4.4 or newer and run `scenes/main.tscn`.

## Controls
- Desktop: A/D rotate crane, W/S raise/lower the hoist, Space releases a swing, R resets.
- Mobile: use the on-screen crawler, winch and swing/release buttons.

## Web build
The GitHub Actions workflow builds a Web export and stores it as a workflow artifact. It is kept separate from the existing live site until the build can be verified.
