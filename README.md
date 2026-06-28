# Cessna 172S G1000 Flight Simulator

A flight simulator for the **Cessna 172S Skyhawk** with a **Garmin G1000**
glass cockpit, built with the **Godot 4** engine. It aims to balance
*aerodynamic realism* (a physics-based, POH-tuned flight model) with
*playability* (forgiving controls, clear instruments, instant reset). It runs
on **macOS**, as well as Linux and Windows.

![icon](assets/icon.svg)

---

## Highlights

- **Physics-based flight model** — body-axis aerodynamics integrated through
  Godot's rigid-body solver at 120 Hz. Lift/drag from a real lift curve with a
  stall break, an induced-drag polar, and stability & control derivatives for
  pitch, roll and yaw (damping, static stability, weathercock, dihedral).
- **Real C172S numbers** — 1110 kg, 16.17 m² wing, Lycoming IO-360 (180 hp)
  with a fixed-pitch prop modelled via momentum theory + an efficiency curve.
  Stall ≈ 48 KIAS clean, cruise ≈ 120–124 KTAS, climb ≈ 700+ fpm.
- **ISA atmosphere** — density, pressure and temperature vary with altitude and
  feed both the aerodynamics and the airspeed/altitude instruments (TAS ↔ IAS).
- **G1000-style PFD** — procedurally drawn attitude indicator (pitch ladder,
  roll scale, slip/skid), airspeed tape with V-speed colour arcs, altitude
  tape, vertical-speed indicator, and an HSI compass rose. Plus an engine
  strip (RPM, MAP, fuel flow, oil temp, throttle).
- **Multiple camera views** — chase, cockpit, wing and tower.
- **Runway environment** — a paved runway with markings, ground plane and
  distant terrain to fly around.

---

## Requirements

- **Godot Engine 4.3** or newer — standard (GDScript) build, *not* the
  .NET/C# build. Download from <https://godotengine.org/download>.
- macOS 11+ (Apple Silicon or Intel), Linux, or Windows.

No external assets or plugins are required — all 3D models are primitives and
all instruments are drawn in code, so the project opens and runs as-is.

---

## Running on macOS

1. Install Godot 4.3+ (drag `Godot.app` to `/Applications`).
   - On first launch macOS Gatekeeper may block it: right-click the app →
     **Open**, or allow it under *System Settings → Privacy & Security*.
2. Launch Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **▶ (Run Project)** or hit `F5`.

### From the command line

```bash
# If the Godot binary is on your PATH (e.g. via `brew install godot`):
godot --path /path/to/this/repo

# Or point directly at the app bundle's binary:
/Applications/Godot.app/Contents/MacOS/Godot --path /path/to/this/repo
```

### Exporting a standalone macOS `.app`

In the editor: **Project → Export → Add… → macOS**, set a bundle identifier,
then **Export Project**. (Export templates download automatically the first
time.) For distribution outside your own machine you'll need to codesign and
notarize the bundle per Apple's requirements.

---

## Controls

| Action            | Key                         |
|-------------------|-----------------------------|
| Pitch             | ↑ / ↓ arrows                |
| Roll              | ← / → arrows                |
| Yaw (rudder)      | `Z` / `X`                   |
| Throttle          | `Page Up` / `Page Down`     |
| Elevator trim     | `,` / `.`                   |
| Flaps down / up   | `F` / `G`                   |
| Wheel brakes      | `B` (toggle)                |
| Cycle camera view | `C`                         |
| Reset on runway   | `R`                         |

A gamepad/joystick maps naturally to the pitch/roll/yaw axes.

### Suggested first flight

1. Press `Page Up` to bring the throttle to full. Hold the centreline with
   gentle rudder (`Z`/`X`).
2. Around **55 KIAS**, ease back (↑) to rotate. Climb at **~74 KIAS** (Vy).
3. Retract flaps with `G` if you used any. Trim (`,`/`.`) to hold the climb.
4. Level off, reduce throttle to ~75 % for a cruise around 110–120 KIAS.
5. For landing, slow below **85 KIAS**, add flaps (`F`), and aim for a
   ~65 KIAS approach. Flare gently and brake (`B`) after touchdown.

---

## Project layout

```
project.godot              Engine config, input map, autoloads
assets/icon.svg            Application icon
src/
  Main.tscn / Main.gd      Top-level scene: world + aircraft + camera + UI
  systems/
    Atmosphere.gd          ISA atmosphere model (autoload)
    FlightData.gd          Shared flight-state blackboard (autoload)
  aircraft/
    Aircraft.tscn          C172 model built from primitives
    Aircraft.gd            Flight-dynamics model (aero forces & moments)
    Engine.gd              Lycoming IO-360 + fixed-pitch prop model
  ui/
    PFD.gd                 G1000 Primary Flight Display (procedural)
    EngineStrip.gd         Engine indication strip
  world/
    World.tscn             Runway, ground, sky, lighting
    CameraController.gd    Chase / cockpit / wing / tower views
```

---

## Flight-model notes & limitations

The model is a *lumped-parameter* aerodynamic simulation: a single wing/tail
representation with constant stability derivatives, tuned to reproduce the
C172S POH performance rather than to be a blade-element or CFD simulation.
It captures stalls, trim, climb/cruise performance, adverse-yaw-free turns and
ground roll. It does **not** (yet) model: wind/turbulence (a hook exists),
ground-effect, P-factor/torque roll, spins, icing, or systems failures. These
are natural next steps and the code is structured to add them incrementally.

---

## License

See [LICENSE](LICENSE).
