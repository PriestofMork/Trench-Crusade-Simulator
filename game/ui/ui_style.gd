class_name UiStyle
extends RefCounted
## Shared look for the 2D panels: player names and colours, panel and text styles.

const PLAYER_NAMES: Array[String] = ["Player 1 (red)", "Player 2 (blue)"]
const PLAYER_TEXT_COLOURS: Array[Color] = [Color(1.0, 0.55, 0.5), Color(0.55, 0.72, 1.0)]
const PANEL_COLOUR: Color = Color(0.07, 0.07, 0.09, 0.9)
const TEXT_COLOUR: Color = Color(0.92, 0.92, 0.9)
const DIM_COLOUR: Color = Color(0.6, 0.6, 0.62)
const GOOD_COLOUR: Color = Color(0.55, 0.9, 0.55)
const BAD_COLOUR: Color = Color(1.0, 0.5, 0.42)
const GOLD_COLOUR: Color = Color(1.0, 0.85, 0.4)


static func player_name(player: int) -> String:
	if player < 0:
		return "Either player"
	return PLAYER_NAMES[player]


static func player_colour(player: int) -> Color:
	if player < 0:
		return GOLD_COLOUR
	return PLAYER_TEXT_COLOURS[player]


## BBCode for a player's name in their colour.
static func player_bb(player: int) -> String:
	return "[color=#%s]%s[/color]" % [player_colour(player).to_html(false), player_name(player)]


static func panel(border: Color = Color(0.3, 0.3, 0.34)) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PANEL_COLOUR
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(12)
	return box


static func label(text: String = "", size: int = 16, colour: Color = TEXT_COLOUR) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", colour)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


static func rich(size: int = 16) -> RichTextLabel:
	var result: RichTextLabel = RichTextLabel.new()
	result.bbcode_enabled = true
	result.fit_content = true
	result.scroll_active = false
	result.add_theme_font_size_override("normal_font_size", size)
	result.add_theme_font_size_override("bold_font_size", size)
	result.add_theme_color_override("default_color", TEXT_COLOUR)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func button(text: String, node_name: String) -> Button:
	var result: Button = Button.new()
	result.text = text
	result.name = node_name
	result.add_theme_font_size_override("font_size", 16)
	result.custom_minimum_size = Vector2(0, 34)
	result.focus_mode = Control.FOCUS_NONE
	return result
