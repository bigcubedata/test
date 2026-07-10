# Third-party asset: c172.glb

`c172.glb` is a converted copy of the **FlightGear c172p project** exterior
model and is **not** covered by this repository's top-level MIT license.

- Source: <https://github.com/c172p-team/c172p> — `Models/c172-common.ac`
  plus the textures it references (`fuselage.png`, `wing.png`, `tail.png`,
  `glass-alpha.png`, `prop.png`), master branch.
- Copyright: the c172p-team contributors (see the source repository).
- License: **GNU General Public License v2.0** (see the `LICENSE` file in the
  source repository). This GLB is a derivative work (format conversion) and
  remains under GPL-2.0.

Conversion notes: the AC3D source was converted to glTF binary with a custom
script — interior/panel/hotspot objects removed, axes remapped to Godot's
convention (nose toward −Z), the model shifted 0.08 m forward so the
main-gear contact matches the simulator's gear position, and the animated
parts (control surfaces, propeller, spinner, nose gear) exported as separate
named nodes with origins on their FlightGear hinge lines.

The GLB is loaded at runtime and is optional: if this file is deleted, the
simulator falls back to its built-in procedural (MIT-licensed) model.
