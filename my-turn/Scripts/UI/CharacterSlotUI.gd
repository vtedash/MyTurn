# res://Scripts/UI/CharacterSlotUI.gd
extends PanelContainer

signal slot_clicked(team_id, slot_index) # Emitida cuando se hace click en este slot

@onready var preview_icon: TextureRect = %PreviewIcon
@onready var name_label: Label = %NameLabel
@onready var empty_label: Label = %EmptyLabel

var team_id: int = -1
var slot_index: int = -1
var assigned_character: CharacterData = null

func _ready():
	gui_input.connect(_on_gui_input)
	assign_character(null) # Empezar vacío

func setup_slot(p_team_id: int, p_index: int, initial_char: CharacterData = null):
	team_id = p_team_id
	slot_index = p_index
	assign_character(initial_char)

func assign_character(char_data: CharacterData):
	assigned_character = char_data
	if assigned_character:
		 name_label.text = tr(assigned_character.character_name)
		 # Asignar icono si existe en CharacterData (necesitarías añadir @export var preview_icon: Texture2D en CharacterData)
		 # if assigned_character.has("preview_icon") and assigned_character.preview_icon:
		 #    preview_icon.texture = assigned_character.preview_icon
		 #    preview_icon.visible = true
		 # else:
		 preview_icon.texture = null # O un icono por defecto
		 preview_icon.visible = true # O false si no hay icono
		 name_label.visible = true
		 empty_label.visible = false
		 modulate = Color.WHITE # Slot lleno
	else:
		 name_label.text = ""
		 preview_icon.texture = null
		 name_label.visible = false
		 preview_icon.visible = false
		 empty_label.visible = true
		 modulate = Color(0.8, 0.8, 0.8, 0.7) # Slot vacío atenuado

func get_assigned_character() -> CharacterData:
	return assigned_character

func _on_gui_input(event: InputEvent):
	 if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		  emit_signal("slot_clicked", team_id, slot_index)
