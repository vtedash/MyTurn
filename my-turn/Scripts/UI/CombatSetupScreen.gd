# res://Scripts/UI/CombatSetupScreen.gd
extends Control

# --- Referencias UI ---
@onready var team1_size_spinbox: SpinBox = %Team1SizeSpinBox
@onready var team2_size_spinbox: SpinBox = %Team2SizeSpinBox
@onready var stage_select_optionbutton: OptionButton = %StageSelectOptionButton
@onready var available_chars_list: ItemList = %AvailableCharsList
@onready var team1_slots_container: GridContainer = %Team1SlotsContainer
@onready var team2_slots_container: GridContainer = %Team2SlotsContainer
@onready var status_label: Label = %StatusLabel
@onready var ready_button: Button = %ReadyButton
@onready var start_battle_button: Button = %StartBattleButton
@onready var back_button: Button = %BackButton

# Exportar la escena del slot
@export var character_slot_scene: PackedScene

const BATTLE_SCENE_PATH = "res://Scenes/BattleScene.tscn"
const MAIN_MENU_SCENE_PATH = "res://Scenes/MainMenu.tscn"

# --- Estado del Lobby ---
var available_characters: Array[CharacterData] = []
var available_stages: Array[StageData] = []

# Selección actual (IDs para sincronizar)
var team1_selection_ids: Array = [] # Array de StringName o null
var team2_selection_ids: Array = [] # Array de StringName o null
var selected_stage_id: StringName = &""

# Estado de "Listo" de los jugadores (player_id: bool)
var player_ready_status: Dictionary = {}
var local_player_ready: bool = false

var selected_available_char_index: int = -1 # Índice del personaje seleccionado en la lista

# --- Inicialización ---
func _ready():
	# Ocultar/mostrar controles según si somos Host o Cliente
	var is_host = NetworkManager.is_network_host()
	team1_size_spinbox.visible = is_host
	team1_size_spinbox.editable = is_host
	team2_size_spinbox.visible = is_host
	team2_size_spinbox.editable = is_host
	stage_select_optionbutton.disabled = not is_host
	start_battle_button.visible = is_host
	start_battle_button.disabled = true # Deshabilitado hasta que todos estén listos

	# Conectar señales UI locales
	if is_host:
		 team1_size_spinbox.value_changed.connect(_on_host_team_size_changed.bind(1))
		 team2_size_spinbox.value_changed.connect(_on_host_team_size_changed.bind(2))
		 stage_select_optionbutton.item_selected.connect(_on_host_stage_selected)

	available_chars_list.item_selected.connect(_on_available_char_selected)
	ready_button.pressed.connect(_on_ready_pressed)
	start_battle_button.pressed.connect(_on_host_start_battle_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Conectar señales de Red
	NetworkManager.player_list_changed.connect(_update_player_list_and_ready_status)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	# Podrías necesitar conectar peer_disconnected para limpiar ready status

	# Configurar autoridad multijugador para sincronizar estado del lobby
	set_multiplayer_authority(1) # Host maneja el estado del lobby

	# Cargar contenido y poblar listas
	if ContentLoader: # Comprobar si Autoload existe
		 available_characters = ContentLoader.get_all_characters()
		 available_stages = ContentLoader.get_all_stages()
		 _populate_available_lists()
	else:
		 push_error("ContentLoader not found!")

	_update_player_list_and_ready_status() # Inicializar lista de jugadores
	_reset_local_selection()

	if is_host:
		 # Host inicializa los tamaños y el escenario por defecto
		 call_deferred("_host_initialize_defaults") # Deferred para asegurar que nodos estén listos
	else:
		 # Cliente espera sincronización del host
		 status_label.text = "Esperando datos del host..."


func _host_initialize_defaults():
	 if not NetworkManager.is_network_host(): return
	 # Disparar señales para tamaño inicial y escenario
	 _on_host_team_size_changed(team1_size_spinbox.value, 1)
	 _on_host_team_size_changed(team2_size_spinbox.value, 2)
	 if available_stages.size() > 0:
		  _on_host_stage_selected(0) # Seleccionar el primero por defecto
	 else:
		  push_warning("Host: No stages loaded!")


func _populate_available_lists():
	available_chars_list.clear()
	for char_data in available_characters:
		 available_chars_list.add_item(tr(char_data.character_name)) # Usar tr()
		 available_chars_list.set_item_metadata(available_chars_list.item_count - 1, char_data.id) # Guardar ID

	stage_select_optionbutton.clear()
	for stage_data in available_stages:
		 stage_select_optionbutton.add_item(tr(stage_data.stage_name))
		 stage_select_optionbutton.set_item_metadata(stage_select_optionbutton.item_count - 1, stage_data.id) # Guardar ID


func _reset_local_selection():
	 selected_available_char_index = -1
	 available_chars_list.deselect_all()


# --- Lógica del HOST ---
func _on_host_team_size_changed(value: float, team_id: int):
	if not NetworkManager.is_network_host(): return
	var size = int(value)
	# Enviar RPC para que todos actualicen el tamaño de los slots
	rpc("sync_lobby_team_size", team_id, size)

func _on_host_stage_selected(index: int):
	 if not NetworkManager.is_network_host(): return
	 var stage_id = stage_select_optionbutton.get_item_metadata(index)
	 rpc("sync_lobby_stage", stage_id)


func _on_host_start_battle_pressed():
	if not NetworkManager.is_network_host() or start_battle_button.disabled: return

	# --- Verificación Final de Contenido ---
	var all_selected_char_ids = team1_selection_ids + team2_selection_ids
	all_selected_char_ids = all_selected_char_ids.filter(func(id): return id != null) # Quitar nulos
	var required_content = ContentLoader.get_content_ids_and_hashes(all_selected_char_ids, [], selected_stage_id) # Asume que habilidades se cargan por personaje

	# Enviar petición de verificación a todos los clientes
	status_label.text = "Verificando contenido en clientes..."
	rpc("client_verify_content", required_content)
	# Necesitaríamos un mecanismo para esperar respuestas de los clientes (ej. contar respuestas OK)
	# Por simplicidad ahora, asumimos que funciona y procedemos. ¡IMPLEMENTAR VERIFICACIÓN REAL!

	print("Host starting battle (content verification skipped/assumed OK for now)")
	# Filtrar IDs nulos antes de iniciar
	var final_team1 = team1_selection_ids.filter(func(id): return id != null)
	var final_team2 = team2_selection_ids.filter(func(id): return id != null)

	# Obtener los CharacterData completos para el host
	var team1_data = final_team1.map(func(id): return ContentLoader.get_character(id))
	var team2_data = final_team2.map(func(id): return ContentLoader.get_character(id))
	var stage_data = ContentLoader.get_stage(selected_stage_id)

	if team1_data.any(func(d): return d == null) or \
	   team2_data.any(func(d): return d == null) or not stage_data:
		 push_error("Host: Failed to get full data for selected IDs before starting battle!")
		 status_label.text = "Error: No se pudo cargar el contenido seleccionado."
		 return

	# Cambiar a la escena de batalla y luego llamar a host_setup_and_start
	get_tree().change_scene_to_file(BATTLE_SCENE_PATH)
	# Esperar un frame para que la nueva escena esté lista
	await get_tree().process_frame
	var battle_manager = get_tree().root.find_child("BattleManager", true, false) # Asume nombre de nodo
	if battle_manager:
		  battle_manager.host_setup_and_start_battle(team1_data, team2_data, stage_data)
	else:
		  push_error("Failed to find BattleManager in the loaded scene!")
		  get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH) # Volver al menú


# --- Lógica Cliente/Común ---
func _on_ready_pressed():
	local_player_ready = not local_player_ready # Cambiar estado
	ready_button.text = "No Listo" if local_player_ready else "Listo"
	# Enviar estado al host
	rpc_id(1, "update_player_ready_status", NetworkManager.get_player_id(), local_player_ready)


func _on_back_pressed():
	 NetworkManager.disconnect_peer()
	 get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_server_disconnected():
	 status_label.text = "Desconectado del host."
	 # Podrías mostrar un popup y luego volver al menú
	 await get_tree().create_timer(2.0).timeout
	 get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


# Llamado localmente cuando se selecciona un personaje de la lista
func _on_available_char_selected(index: int):
	selected_available_char_index = index
	# Resaltar selección visualmente si quieres


# Llamado localmente cuando se hace click en un slot
func _on_character_slot_clicked(team_id: int, slot_index: int):
	var player_id = NetworkManager.get_player_id()

	# Lógica simple: jugador 1 controla equipo 1, jugador 2 equipo 2, etc.
	# ¡Necesitas una lógica más robusta para asignar control en NvsM!
	# Este ejemplo asume que el jugador controla el equipo con su ID (host=1, primer cliente=2?).
	 var can_control_team1 = (player_id == 1)
	 var can_control_team2 = (player_id != 1) # Asume que cualquier cliente controla equipo 2

	if (team_id == 1 and not can_control_team1) or (team_id == 2 and not can_control_team2):
		  print("Cannot modify opponent's team slot.")
		  return # No puede modificar slot de otro equipo (según esta lógica simple)

	var selection_array_ids = team1_selection_ids if team_id == 1 else team2_selection_ids

	if selected_available_char_index != -1:
		 # Asignar personaje seleccionado de la lista al slot
		 var char_id: StringName = available_chars_list.get_item_metadata(selected_available_char_index)

		 # Comprobar si el personaje ya está en algún slot DEL MISMO JUGADOR
		 _unassign_character_if_present(char_id, player_id)

		 # Enviar RPC al HOST para actualizar la selección
		 rpc_id(1, "update_slot_selection", team_id, slot_index, char_id)

		 _reset_local_selection()
	else:
		 # Si no hay selección, click en slot ocupado lo vacía (si es nuestro)
		 if selection_array_ids[slot_index] != null:
			  rpc_id(1, "update_slot_selection", team_id, slot_index, null) # Enviar null para vaciar

	# La actualización visual real ocurrirá cuando el host envíe sync_slot_selection


# Helper para quitar un personaje de otros slots del mismo jugador
func _unassign_character_if_present(char_id: StringName, player_id: int):
	var can_control_team1 = (player_id == 1)
	var can_control_team2 = (player_id != 1)

	if can_control_team1:
		for i in range(team1_selection_ids.size()):
			 if team1_selection_ids[i] == char_id:
				  rpc_id(1, "update_slot_selection", 1, i, null) # Pedir al host que lo quite
	if can_control_team2:
		for i in range(team2_selection_ids.size()):
			 if team2_selection_ids[i] == char_id:
				  rpc_id(1, "update_slot_selection", 2, i, null) # Pedir al host que lo quite


# --- Sincronización del Lobby (RPCs) ---

# HOST recibe la actualización de estado "Listo" de un cliente
@rpc("any_peer", "call_local", "reliable")
func update_player_ready_status(player_id: int, is_ready: bool):
	if not multiplayer.is_server(): return
	print("Host received ready status: Player %d is %s" % [player_id, "Ready" if is_ready else "Not Ready"])
	player_ready_status[player_id] = is_ready
	# Re-transmitir a todos para que actualicen UI (o solo enviar el cambio)
	rpc("sync_player_ready_status", player_ready_status)
	# Comprobar si todos están listos para habilitar botón Start
	_check_all_ready()


# TODOS reciben el diccionario completo de estados "Listo"
@rpc("authority", "call_local", "reliable")
func sync_player_ready_status(all_statuses: Dictionary):
	player_ready_status = all_statuses
	_update_ready_button_text() # Actualizar texto local
	_update_status_label()    # Actualizar label general
	if NetworkManager.is_network_host():
		 _check_all_ready() # Host comprueba si puede iniciar


# HOST recibe la selección de slot de un cliente
@rpc("any_peer", "call_local", "reliable")
func update_slot_selection(team_id: int, slot_index: int, char_id: StringName):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()

	# Validar que el sender puede modificar ese slot (¡IMPORTANTE!)
	var can_control_team1 = (sender_id == 1)
	var can_control_team2 = (sender_id != 1) # Lógica simple
	if (team_id == 1 and not can_control_team1) or (team_id == 2 and not can_control_team2):
		  push_warning("Host: Peer %d tried to modify slot they don't control!" % sender_id)
		  return

	var selection_array = team1_selection_ids if team_id == 1 else team2_selection_ids
	if slot_index < 0 or slot_index >= selection_array.size():
		 push_warning("Host: Invalid slot index %d from peer %d." % [slot_index, sender_id])
		 return

	 # Validar si el char_id existe (opcional)
	if char_id != null and ContentLoader.get_character(char_id) == null:
		push_warning("Host: Peer %d selected invalid character ID '%s'." % [sender_id, char_id])
		return

	 # Comprobar si char_id ya está usado por OTRO jugador (o en el otro equipo si NvsN)
	 # ... (Implementar lógica de unicidad si es necesaria)

	print("Host updating slot: Team %d, Index %d, Char %s by Peer %d" % [team_id, slot_index, char_id, sender_id])
	selection_array[slot_index] = char_id
	# Re-transmitir el estado de ESE slot a todos
	rpc("sync_slot_selection", team_id, slot_index, char_id)


# TODOS reciben la actualización de un slot específico
@rpc("authority", "call_local", "reliable")
func sync_slot_selection(team_id: int, slot_index: int, char_id: StringName):
	print("Peer %d received sync for slot T%d[%d] = %s" % [NetworkManager.get_player_id(), team_id, slot_index, char_id])
	var selection_array = team1_selection_ids if team_id == 1 else team2_selection_ids
	var container = team1_slots_container if team_id == 1 else team2_slots_container

	if slot_index < 0 or slot_index >= selection_array.size(): return # Índice inválido recibido

	selection_array[slot_index] = char_id
	if slot_index < container.get_child_count():
		 var slot_node = container.get_child(slot_index) as CharacterSlotUI
		 if slot_node:
			  var char_data = ContentLoader.get_character(char_id) if char_id != null else null
			  slot_node.assign_character(char_data)

	# Si soy host, comprobar si puedo iniciar batalla ahora
	if NetworkManager.is_network_host():
		 _check_all_ready()


# TODOS reciben la actualización del tamaño del equipo
@rpc("authority", "call_local", "reliable")
func sync_lobby_team_size(team_id: int, size: int):
	print("Peer %d received sync for team %d size = %d" % [NetworkManager.get_player_id(), team_id, size])
	var spinbox = team1_size_spinbox if team_id == 1 else team2_size_spinbox
	var container = team1_slots_container if team_id == 1 else team2_slots_container
	var selection_array = team1_selection_ids if team_id == 1 else team2_selection_ids

	if spinbox.value != size: spinbox.value = size # Actualizar spinbox local (visualmente)
	selection_array.resize(size) # Ajustar array de datos local

	# Limpiar y recrear slots visuales
	for child in container.get_children(): child.queue_free()
	container.columns = size # Si usas GridContainer

	for i in range(size):
		 var slot_instance = character_slot_scene.instantiate() as CharacterSlotUI
		 container.add_child(slot_instance)
		 slot_instance.setup_slot(team_id, i, null) # Vacío por defecto
		 slot_instance.slot_clicked.connect(_on_character_slot_clicked)
		 # Restaurar selección si existía en el array local
		 if selection_array[i] != null:
			  var char_data = ContentLoader.get_character(selection_array[i])
			  slot_instance.assign_character(char_data)

	if NetworkManager.is_network_host(): _check_all_ready()


# TODOS reciben la actualización del escenario seleccionado
@rpc("authority", "call_local", "reliable")
func sync_lobby_stage(stage_id: StringName):
	 print("Peer %d received sync for stage = %s" % [NetworkManager.get_player_id(), stage_id])
	 selected_stage_id = stage_id
	 # Actualizar OptionButton local
	 for i in range(stage_select_optionbutton.item_count):
		  if stage_select_optionbutton.get_item_metadata(i) == stage_id:
			   if stage_select_optionbutton.selected != i:
					stage_select_optionbutton.select(i)
			   break
	 if NetworkManager.is_network_host(): _check_all_ready()


# CLIENTE recibe petición de verificación del HOST
@rpc("authority", "call_remote", "reliable") # Solo clientes necesitan verificar
func client_verify_content(required_data: Dictionary):
	if NetworkManager.is_network_host(): return # Host no necesita verificar contra sí mismo
	print("Client received content verification request.")
	var success = ContentLoader.verify_content(required_data)
	# Enviar respuesta al host
	rpc_id(1, "report_content_verification_result", NetworkManager.get_player_id(), success)


# HOST recibe el resultado de la verificación de un CLIENTE
@rpc("any_peer", "call_local", "reliable")
func report_content_verification_result(player_id: int, success: bool):
	 if not multiplayer.is_server(): return
	 print("Host received verification result from Player %d: %s" % [player_id, "OK" if success else "FAILED"])
	 # Aquí necesitarías almacenar los resultados por jugador y actuar en consecuencia
	 # Si alguno falla, NO iniciar batalla y notificar a todos.


# --- Actualización de UI y Estado ---
func _update_player_list_and_ready_status():
	var current_players = NetworkManager.get_all_player_ids()
	var current_ready_status = player_ready_status.duplicate() # Copiar dict

	# Limpiar estados de jugadores que ya no están
	for player_id in current_ready_status:
		 if not player_id in current_players:
			  current_ready_status.erase(player_id)

	# Añadir nuevos jugadores con estado "no listo"
	for player_id in current_players:
		 if not player_id in current_ready_status:
			  current_ready_status[player_id] = false

	# Si somos host, actualizar estado y sincronizar si hubo cambios
	if NetworkManager.is_network_host():
		 if current_ready_status != player_ready_status:
			  player_ready_status = current_ready_status
			  rpc("sync_player_ready_status", player_ready_status)
		 _check_all_ready() # Comprobar si se puede iniciar
	else:
		 # Clientes solo actualizan su estado local (recibirán sync del host)
		 player_ready_status = current_ready_status


	# Actualizar UI local
	_update_ready_button_text()
	_update_status_label()


func _update_ready_button_text():
	 var my_id = NetworkManager.get_player_id()
	 local_player_ready = player_ready_status.get(my_id, false)
	 ready_button.text = "No Listo" if local_player_ready else "Listo"


func _update_status_label():
	var total_players = player_ready_status.size()
	var ready_count = 0
	for player_id in player_ready_status:
		 if player_ready_status[player_id]:
			  ready_count += 1
	status_label.text = "Jugadores: %d/%d Listos" % [ready_count, total_players]
	 # Podrías añadir nombres o indicadores visuales de quién está listo


# Llamado en HOST para comprobar si se puede iniciar
func _check_all_ready():
	if not NetworkManager.is_network_host(): return

	var all_ready = true
	if player_ready_status.is_empty(): # Nadie conectado?
		 all_ready = false
	else:
		 for player_id in player_ready_status:
			  if not player_ready_status[player_id]:
				   all_ready = false
				   break

	# Comprobar también si hay al menos un personaje por equipo y escenario
	var team1_valid = team1_selection_ids.any(func(id): return id != null)
	var team2_valid = team2_selection_ids.any(func(id): return id != null)
	var stage_valid = selected_stage_id != &""

	start_battle_button.disabled = not (all_ready and team1_valid and team2_valid and stage_valid)
	# print("Check All Ready: AllReady=%s, T1=%s, T2=%s, Stage=%s -> Button Disabled=%s" % [all_ready, team1_valid, team2_valid, stage_valid, start_battle_button.disabled])
