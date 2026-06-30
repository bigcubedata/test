class_name UiFont
extends RefCounted
## Shared instrument fonts. Uses the host's system sans (Helvetica/Roboto/Arial)
## for crisp, professional readouts instead of the engine fallback font.

static var _regular: Font
static var _bold: Font

const NAMES := ["Helvetica Neue", "Roboto", "Arial", "DejaVu Sans", "sans-serif"]


static func regular() -> Font:
	if _regular == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(NAMES)
		_regular = f
	return _regular


static func bold() -> Font:
	if _bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(NAMES)
		f.font_weight = 700
		_bold = f
	return _bold
