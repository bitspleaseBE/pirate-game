# Spikes

Throwaway experiments that exist to answer a question with evidence instead of an
argument. Nothing in `src/` imports anything here, and nothing here is meant to
survive the decision it was built to inform.

## `spike3d` — is the 2D game at its ceiling?

```bash
godot spike/spike3d.tscn -- --shot   # four camera pitches to user://shots
godot spike/spike3d.tscn             # or just look at it
```

The same eight-component wave table as `src/world/ocean/ocean.gdshader`, copied
verbatim so the two are comparable, applied to vertices instead of to pixels. A
box hull samples the surface at four points and takes its real pitch and roll
from the plane they describe, rather than the scale pulse and in-plane rotation
the 2D ship uses.

**Finding: the geometry is not the win — the camera angle is.** Rendered straight
down, at the angle the game actually uses, the 3D version looks no better than
the 2D one and currently looks worse, because at 90 degrees there is nothing to
occlude, no parallax and no horizon, so everything the 2D shader fakes it fakes
convincingly. Every advantage in these shots appears only once the camera tilts.

That reframes the question. It is not "2D or 3D", it is "does the camera tilt" —
and tilting is a gameplay change before it is a rendering one, because broadside
arcs, tap-to-sail and the minimap are all built on a plan view.
