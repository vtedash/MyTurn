# res://Scripts/Managers/BattleManager.gd
class_name BattleManager extends Node2D

# --- Señales ---
signal battle_started # Emitida localmente en todos los peers
signal battle_ended(winning_team_id) # Emitida localmente en todos los peers
signal turn_started(character_node) # Emitida localmente
signal action_selected_local(character_node, action_data, targets) # Emitida localmente por la UI
signal action_results_received(results_dict) # Emitida localmente al recibir resultados del host
signal combat_log_message(message) # Emitida localmente

# --- Referencias (Asignar en el Editor o _ready) ---
@export var turn_manager: TurnManager
@export var action_executor: ActionExecutor # ¡Ojo! Solo el host usa su lógica principal
@export var battle_hud_scene: PackedScene # Escena del HUD a instanciar
@export var team1_container: Node2D # Contenedor para nodos del equipo 1
@export var team2_container: Node2D # Contenedor para nodos del equipo 2
@export var music_player: AudioStreamPlayer
@export var effect_player: Node # Nodo para reproducir efectos globales (VFX/SFX)
@export var background_sprite: Sprite2D # O el nodo que uses para el fondo

var battle_hud_instance: CanvasLayer = null

# --- Estado de la Batalla ---
var team1_character_data: Array[CharacterData] = [] # Solo relevante en Host para setup inicial
var team2_character_data: Array[CharacterData] = [] # Solo relevante en Host para setup inicial
var stage_data: StageData # Relevante en todos para visuales/música

var team1_nodes: Array[Node] = [] # Instancias activas Equipo 1
var team2_nodes: Array[Node] = [] # Instancias activas Equipo 2
var all_combatants: Dictionary = {} # NodePath: Node (para fácil búsqueda por path)

var current_turn_character: Node = null # Quién tiene el turno actualmente (local)
var is_battle_active: bool = false
var local_player_id: int = 1 # ID de este jugador (se actualizará)


func _enter_tree():
	# Establecer autoridad de multijugador basada en si somos el servidor
	# Esto asegura que los RPCs se enruten correctamente
	var authority_id = 1 if NetworkManager.is_network_host() else multiplayer.get_unique_id()
	if authority_id == 0: authority_id = 1 # Fallback si no está conectado aún
	set_multiplayer_authority(authority_id)
	print("BattleManager authority set to: %d" % get_multiplayer_authority())


func _ready():
	local_player_id = multiplayer.get_unique_id()
	print("BattleManager ready. Local Player ID: %d, Is Host: %s" % [local_player_id, NetworkManager.is_network_host()])

	# Instanciar HUD
	if battle_hud_scene:
		battle_hud_instance = battle_hud_scene.instantiate()
		add_child(battle_hud_instance)
		# Conectar señales del HUD a este manager
		if battle_hud_instance.has_signal("action_selected"):
			battle_hud_instance.action_selected.connect(_on_hud_action_selected)

	# Conectar señales internas si no se hace en editor
	if turn_manager:
		# TurnManager solo emite turn_started localmente basado en RPC del host
		turn_manager.turn_started.connect(_on_local_turn_started)
	if action_executor:
		 # ActionExecutor emite resultados localmente después de procesar RPC del host
		action_executor.action_executed_locally.connect(_on_action_executed_locally)
		action_executor.request_log_message.connect(_log_message) # Log local

	# Conectar señales de este manager al HUD
	if battle_hud_instance:
		battle_started.connect(battle_hud_instance.on_battle_started)
		battle_ended.connect(battle_hud_instance.on_battle_ended)
		turn_started.connect(battle_hud_instance.on_turn_started)
		action_results_received.connect(battle_hud_instance.on_action_results_received)
		combat_log_message.connect(battle_hud_instance.on_combat_log_message)


# --- Lógica de Inicio de Batalla (SOLO HOST) ---
func host_setup_and_start_battle(p_team1_data: Array[CharacterData], p_team2_data: Array[CharacterData], p_stage_data: StageData):
	if not NetworkManager.is_network_host():
		push_error("Client attempted to start battle!")
		return
	if is_battle_active:
		push_warning("Battle already in progress.")
		return

	print("Host: Setting up battle...")
	_cleanup_battle() # Limpiar estado previo localmente

	# Guardar datos (solo host necesita los CharacterData para instanciar)
	self.team1_character_data = p_team1_data
	self.team2_character_data = p_team2_data
	self.stage_data = p_stage_data

	# Extraer IDs para sincronización
	var team1_ids = p_team1_data.map(func(data): return data.id)
	var team2_ids = p_team2_data.map(func(data): return data.id)
	var stage_id = p_stage_data.id

	# Sincronizar estado inicial con todos los clientes (incluido el host localmente)
	rpc("sync_initial_state", team1_ids, team2_ids, stage_id)


# --- RPC llamado por Host, ejecutado en TODOS ---
@rpc("authority", "call_local", "reliable") # call_local para que el host también ejecute
func sync_initial_state(team1_ids: Array[StringName], team2_ids: Array[StringName], stage_id: StringName):
	if is_battle_active: # Evitar doble inicialización
		print("Peer %d received sync_initial_state but battle already active." % multiplayer.get_unique_id())
		return

	print("Peer %d: Syncing initial battle state..." % multiplayer.get_unique_id())
	_cleanup_battle() # Limpiar localmente

	# Obtener datos completos desde ContentLoader usando los IDs
	var loaded_team1_data = team1_ids.map(func(id): return ContentLoader.get_character(id))
	var loaded_team2_data = team2_ids.map(func(id): return ContentLoader.get_character(id))
	self.stage_data = ContentLoader.get_stage(stage_id)

	if loaded_team1_data.any(func(d): return d == null) or \
	   loaded_team2_data.any(func(d): return d == null) or \
	   not self.stage_data:
		push_error("Peer %d failed to sync initial state: Missing content for received IDs!" % multiplayer.get_unique_id())
		# Aquí necesitarías manejar este error (ej. volver al lobby)
		return

	# Configurar escenario localmente
	_setup_stage_local()

	# Instanciar personajes localmente
	# ¡Importante! Asignar autoridad de multijugador a cada personaje
	var host_id = 1 # ID del host
	team1_nodes = _instantiate_team_local(loaded_team1_data, 1, team1_container, host_id) # Host controla Team 1
	team2_nodes = _instantiate_team_local(loaded_team2_data, 2, team2_container, host_id) # Host controla Team 2 por defecto
	# Si tienes jugadores controlando Team 2, necesitas asignar la autoridad correcta aquí
	# Ejemplo: if player 2 ID exists, assign authority of team 2 nodes to player 2 ID


	# Llenar diccionario de combatientes para fácil acceso
	all_combatants.clear()
	for node in team1_nodes + team2_nodes:
		all_combatants[node.get_path()] = node
		# Conectar señales locales del personaje al HUD o BattleManager si es necesario
		# node.hp_changed.connect(...) # Conectar al HUD para updates locales inmediatos

	if all_combatants.is_empty():
		push_error("Peer %d synced state resulted in no combatants." % multiplayer.get_unique_id())
		return

	# Marcar batalla como activa localmente
	is_battle_active = true
	print("Peer %d: Battle synced and active." % multiplayer.get_unique_id())
	emit_signal("battle_started") # Notificar a la UI local

	# Solo el host inicia el ciclo de turnos real
	if NetworkManager.is_network_host():
		if turn_manager:
			 # Pasar nodos reales al TurnManager del host
			turn_manager.host_start_turn_cycle(team1_nodes + team2_nodes)
		else:
			push_error("Host TurnManager not assigned!")
	else:
		# Los clientes esperan el primer sync_turn_start
		 print("Client waiting for first turn sync...")


func _setup_stage_local():
	if stage_data:
		if stage_data.battle_music and music_player:
			music_player.stream = stage_data.battle_music
			music_player.play()
		if background_sprite and stage_data.background_texture:
			background_sprite.texture = stage_data.background_texture
		# Configurar fondo basado en escena si se usa


func _instantiate_team_local(character_datas: Array[CharacterData], team_id: int, container: Node2D, authority_id: int) -> Array[Node]:
	var team_nodes_list: Array[Node] = []
	if not container:
		push_error("Container for team %d not assigned!" % team_id)
		return team_nodes_list

	var spawn_points = stage_data.team1_spawn_points if team_id == 1 else stage_data.team2_spawn_points

	for i in range(min(character_datas.size(), spawn_points.size())):
		var data: CharacterData = character_datas[i]
		if not data or not data.character_scene:
			push_warning("Invalid CharacterData or missing Scene for team %d, index %d." % [team_id, i])
			continue

		var character_instance = data.character_scene.instantiate()
		container.add_child(character_instance)
		team_nodes_list.append(character_instance)

		# Asignar autoridad de multijugador ANTES de llamar a setup
		character_instance.set_multiplayer_authority(authority_id)

		var is_player = (authority_id == local_player_id) # Es local si la autoridad es la nuestra
		if character_instance.has_method("setup"):
			 character_instance.call("setup", data, team_id, is_player) # Pasar si es jugador local
		else:
			push_warning("Character instance for %s missing setup()." % data.character_name)

		if character_instance is Node2D:
			character_instance.global_position = container.global_position + spawn_points[i] # Posición relativa al contenedor
			if team_id == 2 and character_instance.has_node("Sprite2D"): # Asume Sprite2D
				 character_instance.get_node("Sprite2D").flip_h = true

		character_instance.name = "T%d_%s_%d_Auth%d" % [team_id, data.id, i, authority_id]
		print("Instantiated %s with authority %d" % [character_instance.name, authority_id])

	return team_nodes_list


func _cleanup_battle():
	print("Cleaning up battle state...")
	is_battle_active = false
	current_turn_character = null
	if music_player: music_player.stop()

	for path in all_combatants:
		var node = all_combatants[path]
		if is_instance_valid(node):
			node.queue_free()

	all_combatants.clear()
	team1_nodes.clear()
	team2_nodes.clear()
	team1_character_data.clear() # Solo relevante en host, pero limpiar igual
	team2_character_data.clear()
	stage_data = null

	if turn_manager: turn_manager.reset()
	if action_executor: action_executor.reset()
	# No destruir HUD, solo resetearlo
	if battle_hud_instance and battle_hud_instance.has_method("reset_hud"):
		battle_hud_instance.call("reset_hud")


# --- Manejo de Acciones (Flujo Online) ---

# 1. UI Local llama a esto cuando el jugador selecciona una acción
func _on_hud_action_selected(actor_node: Node, action_data: AbilityData, target_nodes: Array[Node]):
	if not is_battle_active or actor_node != current_turn_character:
		push_warning("Local action selection ignored: Not player's turn or battle inactive.")
		return
	if actor_node.get_multiplayer_authority() != local_player_id:
		 push_warning("Local action selection ignored: Not controlling this character.")
		 return

	print("Local player selected action. Sending request to host...")
	# Enviar solicitud al Host (ID 1)
	var actor_path = actor_node.get_path()
	var ability_id = action_data.id
	var target_paths = target_nodes.map(func(n): return n.get_path())
	rpc_id(1, "client_requests_action", actor_path, ability_id, target_paths)

	# Desactivar UI local mientras se espera respuesta
	if battle_hud_instance and battle_hud_instance.has_method("show_waiting_indicator"):
		 battle_hud_instance.call("show_waiting_indicator")


# 2. RPC llamado por Cliente, EJECUTADO EN HOST
@rpc("any_peer", "call_local", "reliable")
func client_requests_action(character_path: NodePath, ability_id: StringName, target_paths: Array[NodePath]):
	if not multiplayer.is_server(): return # Ignorar si no soy el host

	var sender_id = multiplayer.get_remote_sender_id()
	var actor_node = get_node_or_null(character_path)
	var ability_data = ContentLoader.get_ability(ability_id)
	var target_nodes = target_paths.map(func(p): return get_node_or_null(p)).filter(func(n): return n != null)

	# --- VALIDACIONES EN HOST ---
	if not is_battle_active:
		push_warning("Host received action request but battle is inactive.")
		return # Podrías notificar al cliente
	if not actor_node or not ability_data:
		push_warning("Host received invalid action data from peer %d." % sender_id)
		return
	if not turn_manager.is_current_turn(actor_node):
		push_warning("Host received out-of-turn action request from peer %d for %s." % [sender_id, actor_node.name])
		return
	if actor_node.get_multiplayer_authority() != sender_id:
		push_warning("Host received action request from peer %d who does not own character %s (owner: %d)." % [sender_id, actor_node.name, actor_node.get_multiplayer_authority()])
		return
	# Validar coste MP, objetivos válidos, etc. ANTES de ejecutar
	if actor_node.get_current_stat(&"mp") < ability_data.cost:
		 push_warning("Host: Peer %d tried action %s without enough MP." % [sender_id, ability_id])
		 # Notificar fallo al cliente o simplemente no hacer nada / pasar turno?
		 _notify_action_failed(sender_id, actor_node, ability_data, "Not enough MP")
		 turn_manager.host_end_current_turn() # Pasar turno si falla por coste
		 return
	# Validar objetivos aquí si es necesario (ActionExecutor también puede hacerlo)


	print("Host received valid action from %d: %s uses %s on %s" % [sender_id, actor_node.name, ability_data.ability_name, target_paths])
	_log_message("%s usa %s." % [actor_node.get_display_name(), ability_data.ability_name]) # Log local en host

	# Ejecutar acción en el ActionExecutor del HOST
	if action_executor:
		 # ActionExecutor ahora necesita ser llamado explícitamente por el host
		 # y debe llamar a host_distribute_action_results al terminar.
		action_executor.host_execute_action(actor_node, ability_data, target_nodes)
	else:
		push_error("Host ActionExecutor not assigned!")
		turn_manager.host_end_current_turn() # Pasar turno si no se puede ejecutar


# 3. Llamado por ActionExecutor del HOST después de calcular resultados
func host_distribute_action_results(results: Dictionary):
	if not multiplayer.is_server(): return
	print("Host distributing action results: ", results)
	# Enviar resultados a todos los clientes (incluyendo host localmente)
	rpc("sync_action_results", results)

	# Comprobar condiciones de victoria DESPUÉS de distribuir resultados
	if not _host_check_victory_condition():
		# Si la batalla no ha terminado, el host avanza al siguiente turno
		if turn_manager:
			turn_manager.host_end_current_turn()


# 4. RPC llamado por Host, EJECUTADO EN TODOS los peers
@rpc("authority", "call_local", "reliable")
func sync_action_results(results: Dictionary):
	print("Peer %d received action results." % local_player_id)
	if not is_battle_active: return

	# Pasar resultados al ActionExecutor local para aplicar efectos VISUALES
	if action_executor:
		action_executor.client_apply_action_results(results)
	else:
		push_error("Local ActionExecutor not found to apply results!")

	# Emitir señal para que el HUD actualice barras, etc.
	emit_signal("action_results_received", results)


# --- Manejo de Turnos (Flujo Online) ---

# Llamado por TurnManager del HOST cuando empieza un nuevo turno
func host_notify_turn_started(character_node: Node):
	if not multiplayer.is_server(): return
	print("Host notifying turn start for: %s" % character_node.name)
	rpc("sync_turn_start", character_node.get_path())

# RPC llamado por Host, EJECUTADO EN TODOS
@rpc("authority", "call_local", "reliable")
func sync_turn_start(character_path: NodePath):
	if not is_battle_active: return
	var character_node = get_node_or_null(character_path)
	if not character_node:
		push_error("Peer %d received turn start for invalid path: %s" % [local_player_id, character_path])
		return

	print("Peer %d received turn start for: %s" % [local_player_id, character_node.name])
	current_turn_character = character_node
	# Pasar al TurnManager local SOLO para actualizar estado/UI si es necesario
	if turn_manager:
		turn_manager.client_set_current_turn(character_node)

	emit_signal("turn_started", character_node) # Notificar a UI local

	# Si es un personaje de IA y estamos en el HOST, la IA decide
	if multiplayer.is_server() and not character_node.is_player:
		 if character_node.has_method("request_ai_action"):
			 # Pasar copias de listas de nodos (o sus paths)
			 var allies = get_allies(character_node)
			 var enemies = get_enemies(character_node)
			 character_node.call_deferred("request_ai_action", allies, enemies) # Deferred por si acaso
		 else:
			push_warning("Host: AI character %s cannot request action. Ending turn." % character_node.name)
			await get_tree().create_timer(0.5).timeout # Pequeña pausa
			turn_manager.host_end_current_turn()


# --- Lógica de IA (Ejecutada en Host) ---
# Conectado a la señal 'action_requested' de CharacterCombat de IA
func _on_ai_action_requested(ai_actor_node, ability_data, target_nodes):
	 if not multiplayer.is_server(): return # Solo el host procesa IA

	 print("Host: AI %s requested action %s" % [ai_actor_node.name, ability_data.ability_name])
	 # Tratar la acción de IA como una acción de cliente
	 if action_executor:
		  action_executor.host_execute_action(ai_actor_node, ability_data, target_nodes)
	 else:
		  push_error("Host ActionExecutor not assigned for AI action!")
		  turn_manager.host_end_current_turn()


# --- Condiciones de Victoria (SOLO HOST) ---
func _host_check_victory_condition() -> bool:
	if not multiplayer.is_server() or not is_battle_active: return false

	# Usar los nodos directamente ya que el host los tiene
	var team1_alive = team1_nodes.any(func(node): return is_instance_valid(node) and node.is_alive())
	var team2_alive = team2_nodes.any(func(node): return is_instance_valid(node) and node.is_alive())
	var winner = 0 # 0 = Aún no, -1 = Empate, 1 = Equipo 1, 2 = Equipo 2

	if not team1_alive and not team2_alive: winner = -1
	elif not team2_alive: winner = 1
	elif not team1_alive: winner = 2

	if winner != 0:
		print("Host: Battle ended! Winner: Team %s" % ("Draw" if winner == -1 else str(winner)))
		rpc("sync_battle_end", winner) # Notificar a todos
		# Podrías poner is_battle_active = false aquí en el host,
		# pero sync_battle_end debería manejar la limpieza local en todos los peers.
		return true

	return false # La batalla continúa

# RPC llamado por Host, EJECUTADO EN TODOS
@rpc("authority", "call_local", "reliable")
func sync_battle_end(winning_team_id: int):
	if not is_battle_active: return # Evitar doble ejecución
	print("Peer %d received battle end. Winner: %d" % [local_player_id, winning_team_id])
	is_battle_active = false
	emit_signal("battle_ended", winning_team_id) # Notificar UI local
	# Aquí puedes mostrar pantalla de resultados
	# Limpiar después de un delay
	await get_tree().create_timer(3.0).timeout
	_cleanup_battle() # Limpieza local


# --- Notificación de Fallo (Opcional) ---
func _notify_action_failed(peer_id: int, actor: Node, action: AbilityData, reason: String):
	 if not multiplayer.is_server(): return
	 # Podrías enviar un RPC específico al cliente que falló
	 # rpc_id(peer_id, "sync_action_failed", actor.get_path(), action.id, reason)
	 push_warning("Host: Action failed for peer %d (%s): %s" % [peer_id, actor.name, reason])

# @rpc("authority", "call_remote", "reliable")
# func sync_action_failed(actor_path, ability_id, reason):
#     # Cliente recibe notificación de que su acción falló
#     print("My action failed: %s" % reason)
#     # Actualizar UI para permitir nueva acción o mostrar mensaje


# --- Auxiliares (Ejecutados localmente, basados en estado local) ---
func _log_message(message: String):
	#print("LOG: %s" % message) # Log local
	emit_signal("combat_log_message", message)

func get_node_by_path(nodepath: NodePath):
	return all_combatants.get(nodepath, null)

# Estas funciones ahora devuelven nodos locales basados en el estado sincronizado
func get_allies(character_node) -> Array[Node]:
	if not is_instance_valid(character_node): return []
	var team_id = character_node.team_id
	var allies = team1_nodes if team_id == 1 else team2_nodes
	return allies.filter(func(node): return is_instance_valid(node) and node.is_alive())

func get_enemies(character_node) -> Array[Node]:
	if not is_instance_valid(character_node): return []
	var team_id = character_node.team_id
	var enemies = team2_nodes if team_id == 1 else team1_nodes
	return enemies.filter(func(node): return is_instance_valid(node) and node.is_alive())

func get_all_living_combatants() -> Array[Node]:
	return all_combatants.values().filter(func(node): return is_instance_valid(node) and node.is_alive())

# Función para obtener objetivos válidos para la UI local
func get_valid_targets_for_action(actor: Node, action: AbilityData) -> Array[Node]:
	# Esta función opera sobre el estado local sincronizado
	var targets: Array[Node] = []
	var allies = get_allies(actor)
	var enemies = get_enemies(actor)

	match action.target_type:
		"SingleEnemy": targets = enemies
		"AllEnemies": targets = enemies
		"SingleAlly": targets = allies
		"AllAllies": targets = allies
		"Self": targets = [actor] if actor.is_alive() else []
		"AnySingle": targets = allies + enemies
		"RandomEnemy": targets = enemies # La UI podría no permitir seleccionar random
		"RandomAlly": targets = allies  # La UI podría no permitir seleccionar random

	return targets # Devuelve nodos válidos para resaltar en la UI

# --- Manejador de Derrota Local (Visual) ---
# Conectar a la señal 'defeated_visually' de CharacterCombat
func _on_character_defeated_visually(character_node):
	if not is_instance_valid(character_node): return
	print("Local visual: %s appears defeated." % character_node.name)
	# Podrías querer actualizar alguna lista local aquí si es necesario
	# ¡Pero la lógica de victoria/derrota REAL la maneja el host!


# --- Conectar señales de personajes instanciados ---
# Llamado desde _instantiate_team_local
func _connect_character_signals(character_node):
	if not character_node: return
	# Conectar señales que el BattleManager necesita escuchar LOCALMENTE
	# (Ej: para actualizar UI directamente o manejar animaciones visuales)
	if not character_node.is_connected("defeated_visually", Callable(self, "_on_character_defeated_visually")):
		 character_node.defeated_visually.connect(_on_character_defeated_visually.bind(character_node))

	# Si la IA emite la señal de acción requerida:
	if not character_node.is_player and not character_node.is_connected("action_requested", Callable(self, "_on_ai_action_requested")):
		character_node.action_requested.connect(_on_ai_action_requested.bind(character_node))

	# Conectar señales de HP/MP/Status al HUD (el HUD puede hacerlo él mismo también)
	# if battle_hud_instance:
	#     character_node.hp_changed.connect(battle_hud_instance.update_hp.bind(character_node))
	#     character_node.mp_changed.connect(battle_hud_instance.update_mp.bind(character_node))
	#     character_node.status_effect_added.connect(battle_hud_instance.update_status_icons.bind(character_node))
	#     character_node.status_effect_removed.connect(battle_hud_instance.update_status_icons.bind(character_node))
