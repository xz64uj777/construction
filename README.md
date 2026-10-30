# WreckWorks 3D — Demolition Simulator

Standalone mobile-first browser prototype, kept separate from the user's other game repositories.

## Prototype features
- Three.js 3D worksite and masonry workshop
- Excavator with tracks, cab, boom, stick, and bucket
- Touch-friendly track, boom, swing, and smash controls
- Tap wall sections to break them into simulated falling debris
- Damage meter, contract payout, reset, and completion state

## Play
https://xz64uj777.github.io/construction/

## Controls
- Tracks: left/right to turn, forward to move
- Boom +/-: raise/lower the boom
- Swing: rotate the upper structure
- Smash!: impact with the bucket
- Tap a wall section to break it directly
- Reset Job: restore the building

## Prototype limitations
Destruction is section-based with lightweight debris physics, not full rigid-body structural simulation. Three.js is loaded from jsDelivr, so an internet connection is required.
