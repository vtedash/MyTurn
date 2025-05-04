# res://Scripts/UI/CharacterStatusPanel.gd
extends PanelContainer

@onready var name_label: Label = %NameLabel # Usando Nombres Únicos (%)
@onready var hp_bar: ProgressBar = %HPBar
@onready var hp_label: Label = %HPLabel
@onready var mp_bar: ProgressBar = %MPBar
@onready var mp_label: Label = %MPLabel
@onready var status_icon_container: HBoxContainer = %StatusIconContainer

var tracked_character: Node = null

# Llama a esto para asignar un personaje a este panel
func track_character(character_node: Node):
	if not is_instance_valid(character_node) or not character_node is CharacterCombat:
		 push_warning("Invalid node passed to track_character.")
		 tracked_character = null
		 visible = false
		 return

	tracked_character = character_node
	name_label.text = tracked_character.get_display_name()

	# Conectar señales del personaje a los métodos de actualización de este panel
	if not tracked_character.is_connected("hp_changed", Callable(self, "_on_character_hp_changed")):
		 tracked_character.hp_changed.connect(_on_character_hp_changed)
	if not tracked_character.is_connected("mp_changed", Callable(self, "_on_character_mp_changed")):
		 tracked_character.mp_changed.connect(_on_character_mp_changed)
	if not tracked_character.is_connected("status_effect_added_visual", Callable(self, "_on_character_status_changed")):
		 tracked_character.status_effect_added_visual.connect(_on_character_status_changed)
	if not tracked_character.is_connected("status_effect_removed_visual", Callable(self, "_on_character_status_changed")):
		 tracked_character.status_effect_removed_visual.connect(_on_character_status_changed)
	if not tracked_character.is_connected("defeated_visually", Callable(self, "_on_character_defeated")):
		  tracked_character.defeated_visually.connect(_on_character_defeated)

	# Actualizar valores iniciales
	_on_character_hp_changed(tracked_character.get_current_hp(), tracked_character.get_stat(&"max_hp"))
	_on_character_mp_changed(tracked_character.get_current_mp(), tracked_character.get_stat(&"max_mp"))
	_on_character_status_changed(null) # Llama para actualizar iconos iniciales

	# Cambiar estilo si está derrotado inicialmente (poco probable pero posible)
	_set_defeated_style(not tracked_character.is_alive())

	visible = true


func _on_character_hp_changed(current_hp: float, max_hp: float):
	if not is_instance_valid(tracked_character): return # Seguridad
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	hp_label.text = "HP: %d / %d" % [floor(current_hp), floor(max_hp)]
	 # Aplicar tinte rojo si HP bajo?
	var hp_percent = current_hp / max_hp if max_hp > 0 else 0
	if hp_percent < 0.25:
		hp_bar.self_modulate = Color.DARK_RED # Tinte
	elif hp_percent < 0.5:
		 hp_bar.self_modulate = Color(1.0, 0.7, 0.7) # Tinte ligero
	else:
		 hp_bar.self_modulate = Color.WHITE # Sin tinte

func _on_character_mp_changed(current_mp: float, max_mp: float):
	 if not is_instance_valid(tracked_character): return
	 mp_bar.max_value = max_mp
	 mp_bar.value = current_mp
	 mp_label.text = "MP: %d / %d" % [floor(current_mp), floor(max_mp)]

func _on_character_status_changed(effect_data): # No necesitamos el data aquí
	if not is_instance_valid(tracked_character): return
	# Limpiar iconos actuales
	for child in status_icon_container.get_children():
		 child.queue_free()
	# Añadir nuevos iconos basados en el estado actual del tracked_character
	for effect_instance in tracked_character.status_effects: # Usa la lista local del personaje
		 if effect_instance.data.icon:
			  var icon = TextureRect.new()
			  icon.texture = effect_instance.data.icon
			  icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			  icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			  icon.custom_minimum_size = Vector2(18, 18) # Tamaño pequeño
			  var turns_text = "(%d)" % effect_instance.remaining_turns if effect_instance.remaining_turns > 0 else "(inf)"
			  icon.tooltip_text = "%s %s" % [tr(effect_instance.data.effect_name), turns_text]
			  status_icon_container.add_child(icon)

func _on_character_defeated():
	 _set_defeated_style(true)

func _set_defeated_style(is_defeated: bool):
	if is_defeated:
		self.modulate = Color(0.6, 0.6, 0.6, 0.8) # Atenuar panel
	else:
		 self.modulate = Color.WHITE # Color normal

# Limpiar conexiones al salir del árbol
func _exit_tree():
	 if is_instance_valid(tracked_character):
		 if tracked_character.is_connected("hp_changed", Callable(self, "_on_character_hp_changed")):
			  tracked_character.disconnect("hp_changed", Callable(self, "_on_character_hp_changed"))
		 # Desconectar las otras señales... (mp_changed, status_added, status_removed, defeated)
