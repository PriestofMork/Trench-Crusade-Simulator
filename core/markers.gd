class_name Markers
extends RefCounted
## Marker kinds and the per-kind cap (docs/rules/markers.md). Kinds are plain
## ids so later rules (sin markers, faction markers) add a kind as data.

const BLOOD: StringName = &"blood"
const BLESSING: StringName = &"blessing"
const INFECTION: StringName = &"infection"
## Every kind a model tracks, in display order.
const KINDS: Array[StringName] = [BLOOD, BLESSING, INFECTION]
## At most this many markers of each kind on one model.
const CAP: int = 6


static func label(kind: StringName) -> String:
	return String(kind).capitalize()
