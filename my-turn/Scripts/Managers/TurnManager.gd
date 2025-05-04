# res://Scripts/Managers/TurnManager.gd
class_name TurnManager extends Node

signal turn_started(character_node) # Emitida LOCALMENTE cuando se recibe sync_turn_start

# --- Estado (Local para todos, pero solo el Host lo modifica activamente) ---
var all_combatants_host_list: Array[Node] = [] # Solo usado por el host
var turn_order_host: Array[Node] = []       # Solo usado por el host
var current_turn_index_host: int = -1       # Solo usado por el host

var current_turn_character_local: Node = null # Personaje del turno actual (sincronizado)
var is_cycle_running_host: bool = false     # Solo usado por el host

# --- Métodos del HOST ---
func host_start_turn_cycle(initial_combatants: Array[Node]):
	if not multiplayer.is_server(): return
	if is_cycle_running_host:
		push_warning("Host: Turn cycle already running.")
		return

	print("Host: Starting turn cycle...")
	all_combatants_host_list = initial_combatants
	is_cycle_running_host = true
	current_turn_index_host = -1
	_host_calculate_turn_order()
	host_next_turn()

func host_end_current_turn():
	if not multiplayer.is_server() or not is_cycle_running_host: return

	if current_turn_index_host >= 0 and current_turn_index_host < turn_order_host.size():
		var current_char = turn_order_host[current_turn_index_host]
		if is_instance_valid(current_char):
			print("Host: Ending turn for %s" % current_char.name)
			# Procesar efectos de fin de turno (DOTs, duración estados) en el HOST
			if current_char.has_method("host_process_end_of_turn_effects"):
				var results = current_char.host_process_end_of_turn_effects()
				# Si los efectos causan daño/muerte, distribuirlo
				if not results.is_empty():
					 # Obtener referencia al BattleManager (padre)
					var bm = get_parent() as BattleManager
					if bm:
					   bm.host_distribute_action_results(results) # Reutilizar sistema de resultados
					   # Esperar un poco para que los resultados se apliquen antes de verificar victoria
					   await get_tree().create_timer(0.1).timeout
					   # Comprobar victoria después de efectos de fin de turno
					   if bm._host_check_victory_condition():
							return # Batalla terminó

	host_next_turn()


func host_next_turn():
	if not multiplayer.is_server() or not is_cycle_running_host: return

	current_turn_index_host += 1

	if current_turn_index_host >= turn_order_host.size():
		print("Host: Turn cycle completed.")
		_host_calculate_turn_order()
		current_turn_index_host = 0
		if turn_order_host.is_empty():
			push_warning("Host: No combatants left for next turn cycle.")
			is_cycle_running_host = false
			# BattleManager debería haber detectado la victoria/derrota
			return

	# Saltar personajes derrotados (basado en estado del host)
	while current_turn_index_host < turn_order_host.size():
		 var check_char = turn_order_host[current_turn_index_host]
		 if is_instance_valid(check_char) and check_char.is_alive():
			 break # Encontrado personaje vivo
		 current_turn_index_host += 1
		 # Si saltar nos lleva al final, empezar nueva ronda
		 if current_turn_index_host >= turn_order_host.size():
			 print("Host: Turn cycle completed (skipped defeated).")
			 _host_calculate_turn_order()
			 current_turn_index_host = 0
			 if turn_order_host.is_empty():
				 push_warning("Host: No combatants left after skipping defeated.")
				 is_cycle_running_host = false
				 return


	if current_turn_index_host >= turn_order_host.size() or turn_order_host.is_empty():
		 push_warning("Host: Could not find a valid next turn.")
		 is_cycle_running_host = false
		 return


	var next_character = turn_order_host[current_turn_index_host]
	# Notificar a BattleManager del host para que envíe RPC
	var bm = get_parent() as BattleManager
	if bm:
		bm.host_notify_turn_started(next_character)


func _host_calculate_turn_order():
	if not multiplayer.is_server(): return

	# Filtrar solo los vivos de la lista maestra del host
	var living_combatants = all_combatants_host_list.filter(
			func(node): return is_instance_valid(node) and node.is_alive()
	)

	# Ordenar por velocidad (descendente). Usar stats del host.
	living_combatants.sort_custom(
		func(a, b): return a.get_current_stat(&"speed") > b.get_current_stat(&"speed")
	)

	turn_order_host = living_combatants
	print("Host Calculated Turn Order: %s" % [node.name for node in turn_order_host])


# Llamado por BattleManager del host cuando un personaje es derrotado DEFINITIVAMENTE
func host_remove_combatant(character_node):
	if not multiplayer.is_server(): return
	print("Host removing %s from turn considerations." % character_node.name)
	all_combatants_host_list.erase(character_node)
	# No es necesario quitarlo de turn_order_host, el cálculo lo hará.


func is_current_turn(character_node) -> bool:
	# En host, comprueba el índice real
	if multiplayer.is_server():
		return is_cycle_running_host and \
			   current_turn_index_host >= 0 and \
			   current_turn_index_host < turn_order_host.size() and \
			   turn_order_host[current_turn_index_host] == character_node
	# En cliente, comprueba el personaje sincronizado
	else:
		return is_instance_valid(current_turn_character_local) and \
			   current_turn_character_local == character_node


# --- Métodos del CLIENTE ---
# Llamado por BattleManager local al recibir sync_turn_start
func client_set_current_turn(character_node):
	if multiplayer.is_server(): return # Host no necesita esto
	current_turn_character_local = character_node
	emit_signal("turn_started", character_node) # Emitir señal local para la UI


# --- Común / Reset ---
func reset():
	# Host state
	all_combatants_host_list.clear()
	turn_order_host.clear()
	current_turn_index_host = -1
	is_cycle_running_host = false
	# Client state
	current_turn_character_local = null
	print("TurnManager reset.")

ActionExecutor.gd (Se adjuntará a un nodo en BattleScene)

# res://Scripts/Managers/ActionExecutor.gd
class_name ActionExecutor extends Node

# Señales emitidas LOCALMENTE para efectos visuales/sonoros
signal action_started_visual(actor, action_data, targets)
signal action_completed_visual(actor, action_data, results)
signal damage_applied_visual(target, amount, is_crit, damage_type)
signal healing_applied_visual(target, amount, is_crit)
signal status_effect_applied_visual(target, status_data)
signal status_effect_resisted_visual(target, status_data)
signal effect_played_visual(vfx_scene, sfx_stream, target_position)
signal request_log_message(message) # Para log local

# Señal emitida LOCALMENTE después de aplicar los resultados del host
signal action_executed_locally(results_dict)

var bm: BattleManager # Referencia al BattleManager (padre)

func _ready():
	# Obtener referencia al BattleManager
	bm = get_parent() as BattleManager
	if not bm:
		 push_error("ActionExecutor requires BattleManager as parent!")

	# Conectar señales visuales al EffectPlayer del BattleManager (si existe)
	if bm and bm.effect_player:
		 effect_played_visual.connect(bm.effect_player.play_effect) # Asume que EffectPlayer tiene play_effect(scene, stream, pos)


# --- Ejecución en HOST ---
# Llamado por BattleManager del HOST
func host_execute_action(actor: Node, action: AbilityData, targets: Array[Node]):
	if not multiplayer.is_server(): return

	# Ejecutar la acción de forma asíncrona para no bloquear el host
	_host_process_action_async(actor, action, targets)


# Usamos una función async separada para la lógica principal del host
func _host_process_action_async(actor: Node, action: AbilityData, original_targets: Array[Node]):
	# --- INICIO LÓGICA HOST ---
	var results = {
		"actor_path": actor.get_path(),
		"action_id": action.id,
		"targets_original_paths": original_targets.map(func(n): return n.get_path()),
		"hits": [],     # {target_path: NodePath, damage: float, is_crit: bool, status_applied: Array[StringName], status_resisted: Array[StringName]}
		"misses": [],   # [target_path: NodePath]
		"heals": [],    # {target_path: NodePath, amount: float, is_crit: bool}
		"support": [],  # {target_path: NodePath, effects: Array} # Para bufos/etc sin daño/cura directa
		"cost_paid": 0.0,
		"failed_reason": "" # Si la acción falla antes de empezar
	}

	# 1. Pagar Coste (MP/SP) - Validado previamente por BattleManager, pero doble check
	if actor.get_current_stat(&"mp") < action.cost:
		results.failed_reason = "Not enough MP (checked again)"
		push_warning("Host ActionExecutor: Actor %s has insufficient MP for %s." % [actor.name, action.ability_name])
		bm.host_distribute_action_results(results) # Enviar fallo
		return

	actor.modify_stat(&"mp", -action.cost) # Modificar stat REAL en el host
	results.cost_paid = action.cost

	# 2. Determinar Objetivos Finales (Manejar All/Random) - ¡USA RNG DEL HOST!
	var final_target_nodes = _host_determine_final_targets(actor, action, original_targets)
	if final_target_nodes.is_empty():
		emit_signal("request_log_message", "No hay objetivos válidos para %s." % action.ability_name) # Log en host
		results.failed_reason = "No valid targets"
		bm.host_distribute_action_results(results) # Enviar fallo/resultado vacío
		return

	# 3. Procesar cada objetivo
	for target in final_target_nodes:
		if not is_instance_valid(target) or not target.is_alive():
			continue # Saltar muertos (estado del host)

		var target_path = target.get_path()

		# --- A. Comprobar Hit/Miss (Usa DamageCalculator del HOST) ---
		var does_hit = DamageCalculator.check_hit(actor, target, action)

		if not does_hit:
			results.misses.append(target_path)
			continue # Pasar al siguiente objetivo

		# --- B. Calcular Efectos (Daño, Curación, Estados) ---
		var is_crit = DamageCalculator.check_crit(actor, target, action)
		var target_hit_result = {
			 "target_path": target_path,
			 "damage": 0.0,
			 "healing": 0.0,
			 "is_crit": is_crit,
			 "status_applied": [],
			 "status_resisted": []
		}

		# Calcular y Aplicar Daño (en el host)
		if action.damage_type == "Physical" or action.damage_type == "Magical":
			var damage = DamageCalculator.calculate_damage(actor, target, action, is_crit)
			target.host_take_damage(damage) # Aplicar daño REAL al nodo del host
			target_hit_result.damage = damage
			results.hits.append(target_hit_result)

		# Calcular y Aplicar Curación (en el host)
		elif action.damage_type == "Healing":
			var healing = DamageCalculator.calculate_healing(actor, target, action, is_crit)
			target.host_heal(healing) # Aplicar cura REAL al nodo del host
			target_hit_result.healing = healing
			results.heals.append(target_hit_result) # Podríamos usar 'hits' o un array separado

		# Calcular y Aplicar Estados (en el host)
		if not action.status_effects_to_apply.is_empty():
			 for status_data in action.status_effects_to_apply:
				 if DamageCalculator.check_status_apply(actor, target, action, status_data):
					 var applied = target.host_add_status_effect(status_data, actor) # Aplicar REAL en host
					 if applied:
						 target_hit_result.status_applied.append(status_data.id)
					 else:
						 target_hit_result.status_resisted.append(status_data.id) # Resistido por inmunidad/stacking
				 else:
					  target_hit_result.status_resisted.append(status_data.id) # Falló el chequeo de probabilidad

		# Asegurarse de añadir el resultado del target si hubo algún efecto
		if target_hit_result.damage > 0 or target_hit_result.healing > 0 or \
		   not target_hit_result.status_applied.is_empty() or \
		   not target_hit_result.status_resisted.is_empty():
			 # Si no era daño/cura, añadir a hits o a support
			if target_hit_result.damage == 0 and target_hit_result.healing == 0:
				if not results.has("support"): results["support"] = []
				results.support.append(target_hit_result)
			elif not results.hits.has(target_hit_result) and not results.heals.has(target_hit_result):
				 # Si hubo estados pero no daño/cura, añadir a 'hits' para registrarlo
				 results.hits.append(target_hit_result)


	# 4. Distribuir Resultados a todos los clientes
	bm.host_distribute_action_results(results)
	# --- FIN LÓGICA HOST ---


func _host_determine_final_targets(actor: Node, action: AbilityData, original_targets: Array[Node]) -> Array[Node]:
	# ¡Usa RNG del HOST!
	var final_targets: Array[Node] = []
	# Obtener listas de aliados/enemigos VIVOS desde BattleManager (estado del host)
	var allies = bm.get_allies(actor)
	var enemies = bm.get_enemies(actor)

	match action.target_type:
		"SingleEnemy", "SingleAlly", "AnySingle":
			# Asume que original_targets ya fue validado (vivo) por BattleManager
			if not original_targets.is_empty() and is_instance_valid(original_targets[0]) and original_targets[0].is_alive():
				 final_targets.append(original_targets[0])
		"AllEnemies": final_targets = enemies
		"AllAllies": final_targets = allies
		"Self": final_targets = [actor] if actor.is_alive() else []
		"RandomEnemy":
			if not enemies.is_empty(): final_targets.append(enemies.pick_random())
		"RandomAlly":
			if not allies.is_empty(): final_targets.append(allies.pick_random())

	return final_targets


# --- Aplicación en CLIENTE ---
# Llamado por BattleManager local al recibir sync_action_results
func client_apply_action_results(results: Dictionary):
	if multiplayer.is_server(): return # Host ya aplicó los cambios reales

	print("Client applying visual results...")
	var actor = bm.get_node_by_path(results.get("actor_path", NodePath()))
	var action_data = ContentLoader.get_ability(results.get("action_id", &""))

	if not actor or not action_data:
		push_error("Client cannot apply results: Invalid actor or action data.")
		return

	# --- Mostrar Efectos Visuales/Sonoros basados en 'results' ---
	# Emitir señales para que otros sistemas (HUD, EffectPlayer) reaccionen

	# 1. Emitir inicio visual
	var original_targets = [] # Reconstruir lista de nodos target originales si es necesario
	# ... (podrías necesitar buscar los nodos por path desde results.targets_original_paths)
	emit_signal("action_started_visual", actor, action_data, original_targets)


	# 2. Procesar Fallos
	if results.has("failed_reason") and results.failed_reason != "":
		 emit_signal("request_log_message", "Acción fallida: %s" % results.failed_reason)
		 # Podrías tocar un sonido de error

	# 3. Procesar Fallos (Misses)
	for target_path in results.get("misses", []):
		var target_node = bm.get_node_by_path(target_path)
		if target_node:
			emit_signal("request_log_message", "%s esquiva!" % target_node.get_display_name())
			if target_node.has_method("show_floating_text"):
				target_node.show_floating_text("Miss", Color.GRAY)
			# Tocar sonido de "miss"

	# 4. Procesar Aciertos (Hits - Daño y Estados)
	for hit_info in results.get("hits", []):
		var target_node = bm.get_node_by_path(hit_info.get("target_path", NodePath()))
		if not target_node: continue

		var damage = hit_info.get("damage", 0.0)
		var is_crit = hit_info.get("is_crit", false)

		if damage > 0:
			# ¡Importante! Llamar a un método en CharacterCombat que SOLO actualice visuales/emitir señal local
			if target_node.has_method("apply_synchronized_damage"):
				 target_node.apply_synchronized_damage(damage, is_crit) # Este método actualiza HP local y muestra efectos
			emit_signal("damage_applied_visual", target_node, damage, is_crit, action_data.damage_type) # Señal extra por si acaso
			emit_signal("request_log_message", "%s recibe %.0f daño." % [target_node.get_display_name(), damage])

		# Aplicar estados visualmente
		for status_id in hit_info.get("status_applied", []):
			var status_data = ContentLoader.get_status_effect(status_id)
			if status_data:
				if target_node.has_method("client_add_status_effect_visual"):
					 target_node.client_add_status_effect_visual(status_data) # Solo añade icono/VFX
				emit_signal("status_effect_applied_visual", target_node, status_data)
				emit_signal("request_log_message", "%s sufre %s." % [target_node.get_display_name(), status_data.effect_name])

		for status_id in hit_info.get("status_resisted", []):
			 var status_data = ContentLoader.get_status_effect(status_id)
			 if status_data:
				emit_signal("status_effect_resisted_visual", target_node, status_data)
				emit_signal("request_log_message", "%s resiste %s." % [target_node.get_display_name(), status_data.effect_name])


	# 5. Procesar Curaciones
	for heal_info in results.get("heals", []):
		 var target_node = bm.get_node_by_path(heal_info.get("target_path", NodePath()))
		 if not target_node: continue
		 var amount = heal_info.get("amount", 0.0)
		 var is_crit = heal_info.get("is_crit", false)
		 if amount > 0:
			 if target_node.has_method("apply_synchronized_heal"):
				  target_node.apply_synchronized_heal(amount, is_crit) # Actualiza HP local y muestra efectos
			 emit_signal("healing_applied_visual", target_node, amount, is_crit)
			 emit_signal("request_log_message", "%s recupera %.0f PV." % [target_node.get_display_name(), amount])

	# 6. Procesar efectos de Soporte (si los tienes separados)
	# ...

	# 7. Reproducir Animación/VFX/SFX Principal de la habilidad (aquí o antes)
	# emit_signal("effect_played_visual", action_data.animation_scene, action_data.sfx, actor.global_position)
	# Podrías necesitar delays aquí para sincronizar visuales
	await get_tree().create_timer(0.5).timeout # Pausa simulada

	# 8. Emitir señal de finalización visual
	emit_signal("action_completed_visual", actor, action_data, results)
	emit_signal("action_executed_locally", results) # Señal para BM

# --- Reset ---
func reset():
	# Detener efectos en curso si es necesario
	pass
