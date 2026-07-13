# Cessna 172S G1000 Flight Simulator

A flight simulator for the **Cessna 172S Skyhawk** with a **Garmin G1000**-style
glass cockpit, built with the **Godot 4** engine. It balances *aerodynamic
realism* (a physics-based flight model validated against the C172S POH) with
*playability* (forgiving controls, always-visible instruments, instant replay,
one-key reset). Runs on **macOS**, Linux and Windows.

![icon](assets/icon.svg)

---

## Highlights

- **POH-validated flight model** — body-axis aerodynamics with a custom
  integrator at 120 Hz. Validated headless against book numbers:
  takeoff roll ~240 m (rotate 55 KIAS), Vy climb ~790 fpm, full-throttle
  cruise ~122 KTAS, power-off stall ~49 KIAS.
- **Single-engine character** — propwash over the tail (elevator/rudder
  authority at low speed), spiral slipstream + P-factor + engine torque
  (takeoff needs right rudder), ground effect (it floats in the flare),
  pre-stall buffet, and fading aileron authority near the stall.
- **Three-point gear physics** — nose wheel, mains and a tail-strike skid are
  independent spring/damper contacts with tire cornering grip, brakes on the
  mains only, and rudder-pedal nosewheel steering that washes out with speed.
- **Wind, gusts and turbulence** — boundary-layer wind profile, gusts, and a
  spatio-temporal turbulence field sampled at the wingtips and tail so bumps
  come from gradients in the air. Five presets (calm → 18G30) cycled with `V`,
  including direct-crosswind setups for landing practice.
- **Glass cockpit** — G1000-style PFD (attitude, airspeed/altitude tapes with
  V-speed arcs, VSI, HSI, wind data box) and MFD (engine gauges in US units +
  heading-up moving map with runway, pattern and true ground track), shown as
  corner overlays in every view and on the 3D panel in the cockpit.
- **Instant replay** — the whole flight is recorded (~11 min ring buffer).
  `Tab` replays it with pause/scrub/speed control and a mouse-orbit camera;
  a floating tag shows glide angle, AGL and load factor.
- **Traffic-pattern instructor** — `src/training/PatternPilot.gd` flies a
  textbook left-hand pattern (takeoff → crosswind → downwind → base → final →
  full-stop landing) with bilingual lesson captions and camera direction.
- **Detailed exterior model** — the aircraft exterior is the FlightGear
  c172p project's model (`assets/models/c172.glb`, GPL-2.0 — see
  `assets/models/LICENSE.md`), converted with full livery textures and
  articulated flaps (they slide aft and down on their tracks), ailerons,
  elevator, rudder, spinning propeller with a blur disc, and a nose wheel
  that steers with the pedals. Delete the GLB and the sim falls back to the
  original all-procedural model.
- **Procedural world & instruments** — airport (runway markings, taxiway,
  hangar, tower), countryside, cockpit panel and all instruments are built
  in code.
- **Procedural sound** — no audio files: the Lycoming's exhaust pulses (with
  the classic idle lope), prop blade chop, airspeed-dependent wind rumble and
  hiss, sideslip hiss, pre-stall buffet, the electric stall horn, flap-motor
  whine, ground-roll rumble and touchdown thump are all synthesised live
  from the flight state — so the sound matches the physics, even in replay.

---

## Requirements

- **Godot Engine 4.3 or newer** — standard (GDScript) build, *not* the
  .NET/C# build. Download from <https://godotengine.org/download>.
- macOS 11+ (Apple Silicon or Intel), Linux, or Windows.

## Running on macOS

### Option A — prebuilt app (no Godot needed)

Every push builds a ready-to-run universal (Apple Silicon + Intel) app via
GitHub Actions: open the repo's **Actions → Build macOS app → latest run →
Artifacts** and download `C172-FlightSim-macOS`. Unzip it, drag the app to
`/Applications`, then on first launch **right-click → Open** (the app is
ad-hoc signed, not notarized, so Gatekeeper needs the explicit approval).
If macOS still refuses, clear the download quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/C172-FlightSim-macOS.app"
```

(Adjust the name to whatever the app inside the zip is called.)

You can also rebuild locally in one command (Godot + this repo):

```bash
godot --headless --path . --export-release "macOS" dist/C172-FlightSim-macOS.zip
```

### Option B — run from the Godot editor

1. Install Godot 4 (drag `Godot.app` to `/Applications`).
   - If Gatekeeper blocks the first launch: right-click → **Open**, or allow it
     under *System Settings → Privacy & Security*.
2. Launch Godot, choose **Import**, and select this folder's `project.godot`.
3. Press **▶ (Run Project)** / `F5`.

From the command line:

```bash
godot --path /path/to/this/repo                                  # brew install godot
/Applications/Godot.app/Contents/MacOS/Godot --path /path/to/this/repo
```

To export a standalone `.app`: **Project → Export → Add… → macOS**.

---

## Controls

| Action              | Keys                                   |
|---------------------|----------------------------------------|
| Pitch               | `↑` / `↓` (up = nose down, like a yoke)|
| Roll                | `←` / `→`                              |
| Yaw (rudder)        | `Z` / `X`                              |
| Throttle            | `=` / `-`  (also `W`/`S`, `PgUp`/`PgDn`)|
| Elevator trim       | `,` / `.`                              |
| Flaps down / up     | `F` / `G`                              |
| Wheel brakes        | `B` (toggle)                           |
| Cycle camera view   | `C` (cockpit → chase → wing → tower)   |
| Cockpit look around | hold **right mouse** and drag          |
| Wind preset         | `V` (shown in the PFD wind box)        |
| Reset on runway     | `R`                                    |
| **Replay**          | `Tab` enter/exit                       |
| — pause             | `Space`                                |
| — scrub             | `←` / `→`                              |
| — speed             | `↑` / `↓` (0.25×–4×)                   |
| — orbit camera      | drag **left mouse**, wheel to zoom     |

### Joystick: Thrustmaster TCA Airbus (and others)

Plug in before or after launch — devices are detected by name. With the
**TCA Sidestick Airbus Edition**: stick = pitch/roll (expo curve), twist =
rudder, the grey mini lever = throttle, trigger = wheel brakes, red button =
cycle view, hat = trim (forward = nose-down) and flaps (left/right). With the
**TCA Quadrant Airbus Edition**: the ENG levers drive the throttle absolutely
(either lever or both), and lifting them into the **reverse range brakes the
wheels**. Any other HID stick works the same way.

Press **`J`** in-game for a live device monitor (axes/buttons). If your twist
or levers land on different axis numbers, adjust the constants at the top of
`src/systems/JoystickInput.gd` (`STICK_AXIS_*`, `QUAD_*`).

**Joystick not detected on macOS?**

First make sure **macOS itself** sees the device: *System Information → USB*
(or `system_profiler SPUSBDataType`). If the stick is not listed there, the
problem is below the app:

- On Apple Silicon laptops check *System Settings → Privacy & Security →
  Allow accessories to connect* — new USB accessories must be approved
  (set "Ask for new accessories", replug while unlocked, accept the prompt).
- Plug directly into the machine with a known-good USB-A adapter/cable —
  skip unpowered hubs and charge-only cables; try the other USB-C port.
- Verify the hardware on another computer if possible.

Once the device shows up at the USB level, three things in the app:

1. Use a build exported with **Godot 4.5 or newer** — Godot 4.3/4.4 have a
   macOS regression where generic HID joysticks are not detected at all
   ([godotengine/godot#102927](https://github.com/godotengine/godot/issues/102927)).
   The CI-built app already uses 4.7. If you run from the editor, use a
   Godot 4.5+ editor too.
2. Unplug and replug the USB cable while the app is running (the game
   rescans every 2 seconds).
3. *System Settings → Privacy & Security → Input Monitoring*: allow the app,
   then restart it.

### Suggested first flight

1. Full throttle (`=`), keep the centreline with gentle rudder (`Z`/`X`).
2. At **55 KIAS** ease back (`↓`) to rotate; climb at **74 KIAS** (Vy).
3. Trim (`,`/`.`) for the climb, level off, ~75 % power to cruise.
4. To land: slow below **85 KIAS**, flaps in stages (`F`), fly final at
   **65 KIAS**, idle over the numbers, flare, brake (`B`).
5. Press `Tab` to review the whole flight in replay.

### Watching the pattern lesson

Add `src/training/PatternPilot.gd` as an autoload (Project Settings →
Globals → Autoload) and run: the aircraft flies a complete narrated traffic
pattern by itself, then remove the autoload to fly manually again.

---

## Project layout

```
project.godot                 Engine config, input map, autoloads
assets/
  models/c172.glb             FlightGear c172p exterior (GPL-2.0, see LICENSE.md)
src/
  Main.tscn / Main.gd         Top-level scene: world + aircraft + camera + UI
  systems/
    Atmosphere.gd             ISA atmosphere (autoload)
    FlightData.gd             Shared flight-state blackboard (autoload)
    Wind.gd                   Wind / gusts / turbulence field (autoload)
    Replay.gd                 Flight recorder + instant replay (autoload)
    AudioManager.gd           Procedural engine/wind/stall audio (autoload)
    InputSetup.gd             Key bindings, registered in code (autoload)
    TestPilot.gd              POH validation harness (opt-in autoload)
  aircraft/
    Aircraft.tscn/.gd         Flight dynamics, 3-point gear, propulsion coupling
    Engine.gd                 Lycoming IO-360 + fixed-pitch prop model
    Airframe.gd               Exterior: GLB loader + procedural fallback
    Cockpit.gd                3D panel with live G1000 screens (SubViewports)
    Propeller.gd              Spinning prop + blur disc
    ReplayAnnotation.gd       Floating glide/AGL/G tag during replay
  ui/
    PFD.gd / MFD.gd           G1000 displays (procedural, used 2D + on panel)
    StandbyGauges.gd          Backup steam gauges on the panel
    ReplayHUD.gd              REC dot + replay transport bar
    UiFont.gd                 Shared system-font helper
  world/
    World.tscn / World.gd     Runway, markings, airport, countryside, sky
    CameraController.gd       View cycling + replay orbit camera
  training/
    PatternPilot.gd           Instructional traffic-pattern autopilot
```

## Flight-model notes & limitations

A *lumped-parameter* model with constant stability derivatives, tuned to the
C172S POH — not blade-element or CFD. It captures stalls (with buffet and a
proper post-stall break), trim, climb/cruise/ground-roll performance,
left-turning tendencies, ground effect, wind/gusts/turbulence and three-point
ground handling. Not modelled (yet): spins, icing, mixture/leaning effects,
systems failures, and asymmetric stall/wing drop.

## License

See [LICENSE](LICENSE). The exterior aircraft model
(`assets/models/c172.glb`) is a converted copy of the
[FlightGear c172p](https://github.com/c172p-team/c172p) model and remains
under **GPL-2.0** — see [assets/models/LICENSE.md](assets/models/LICENSE.md).
