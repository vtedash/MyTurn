# res://Scripts/Actors/CharacterCombat.gd
class_name CharacterCombat extends Node2D

# --- Señales Locales (para UI, VFX) ---
signal hp_changed(current_hp, max_hp)
signal mp_changed(current_mp, max_mp)
signal status_effect_added_visual(effect_data) # Para icono/vfx local
signal status_effect_removed_visual(effect_data)# Para icono/vfx local
signal defeated_visually # Cuando HP local llega a 0

# --- Señal para IA (Solo Host) ---
signal action_requested(action_data, targets)

# --- Datos y Estado ---
var character_data: CharacterData = null
var team_id: int = -1
var is_player: bool = true # ¿Controlado por el jugador local?

# Estado dinámico (Sincronizado por Host, actualizado localmente para UI)
var current_hp: float = 100.0:
	set(value):
		var previous_hp = current_hp
		# Clamp al valor base del CharacterData (no afectado por buffs/debuffs de max_hp)
		var base_max_hp = character_data.max_hp if character_data else 1.0
		current_hp = clamp(value, 0.0, base_max_hp)
		if current_hp != previous_hp:
			emit_signal("hp_changed", current_hp, get_stat(&"max_hp")) # Emitir con max_hp actual (con buffs)
			if current_hp <= 0 and previous_hp > 0 and not is_defeated:
				is_defeated = true # Marcar como derrotado VISUALMENTE
				emit_signal("defeated_visually")
				_play_death_visuals()
var current_mp: float = 50.0:
	set(value):
		 var previous_mp = current_mp
		 var base_max_mp = character_data.max_mp if character_data else 0.0
		 current_mp = clamp(value, 0.0, base_max_mp)
		 if current_mp != previous_mp:
			 emit_signal("mp_changed", current_mp, get_stat(&"max_mp"))

# Lista de instancias de efectos (solo Host modifica la duración real)
# Clientes la usan para mostrar iconos y calcular stats modificados localmente
var status_effects: Array[StatusEffectInstance] = []
var is_defeated: bool = false # Estado visual local

# --- Nodos Hijos (Asignar en Escena del Personaje) ---
@onready var sprite: Sprite2D = $Sprite2D # Asume nodo Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer # Asume nodo AnimationPlayer
@onready var status_icon_container: HBoxContainer = $StatusIcons # Asume HBoxContainer
@onready var float_text_spawner: Node = $FloatTextSpawner # Un Node2D donde instanciar texto

# --- Setup ---
# Llamado por BattleManager localmente en todos los peers
func setup(p_data: CharacterData, p_team_id: int, p_is_player: bool):
	character_data = p_data
	team_id = p_team_id
	is_player = p_is_player
	self.name = "T%d_%s_Player%s" % [team_id, character_data.id, multiplayer.get_unique_id()]

	if not character_data:
		push_error("CharacterCombat setup failed: No CharacterData provided for %s." % name)
		queue_free()
		return

	# Resetear estado
	is_defeated = false
	status_effects.clear()
	# Stats base (se sincronizarán si es necesario por el host más tarde)
	self.current_hp = get_stat(&"max_hp") # Usa setter para emitir señal inicial
	self.current_mp = get_stat(&"max_mp") # Usa setter

	_update_status_icons_visual() # Limpiar iconos iniciales

	# Configurar apariencia inicial si es necesario (ej. flip sprite)
	# La posición la establece BattleManager

# --- Acceso a Estadísticas (Local, con Modificadores) ---
# Utilizado localmente por UI, IA (en host), y cálculos (en host)
func get_stat(stat_name: StringName) -> float:
	if not character_data: return 0.0
	if not character_data.has(stat_name): return 0.0 # Stat no existe

	var base_value: float = character_data.get(stat_name)
	var modifier: float = 1.0

	# Aplicar modificadores de estado (multiplicativos)
	for effect_instance in status_effects:
		 var mod_key = str(stat_name) + "_mod"
		 if effect_instance.data.has(mod_key):
			  modifier *= effect_instance.data.get(mod_key)

	# Aplicar modificadores aditivos (si los implementas)
	# var additive_mod: float = 0.0
	# for effect_instance in status_effects: ...

	return (base_value * modifier) # + additive_mod

# Devuelve el HP actual (útil para IA/cálculos del host)
# No uses get_stat("hp") porque eso devolvería max_hp modificado
func get_current_hp() -> float:
	return current_hp

# Devuelve el MP actual
func get_current_mp() -> float:
	return current_mp

# --- Aplicación de Resultados Sincronizados (CLIENTE) ---
func apply_synchronized_damage(amount: float, is_crit: bool):
	if is_defeated: return # Ya está visualmente derrotado
	print("%s visually takes %.0f damage" % [name, amount])
	self.current_hp -= amount # Dispara el setter para actualizar UI y comprobar derrota visual

	# Mostrar efectos visuales locales
	show_floating_text(str(floor(amount)), Color.RED if not is_crit else Color.ORANGE_RED)
	if animation_player and animation_player.has_animation("hurt"):
		 animation_player.play("hurt")
	# Tocar SFX localmente
	# if character_data.hurt_sfx: _play_sfx(character_data.hurt_sfx)


func apply_synchronized_heal(amount: float, is_crit: bool):
	 if is_defeated: return
	 print("%s visually heals %.0f HP" % [name, amount])
	 self.current_hp += amount # Dispara el setter para actualizar UI

	 # Mostrar efectos visuales locales
	 show_floating_text(str(floor(amount)), Color.GREEN if not is_crit else Color.LIGHT_GREEN)
	 # Tocar SFX/VFX de curación localmente


# Añade visualmente el icono/efecto de estado (CLIENTE)
func client_add_status_effect_visual(effect_data: StatusEffectData):
	 if is_defeated: return
	 # Comprobar si ya existe visualmente (para evitar duplicados si hay lag)
	 if _find_status_effect_local(effect_data.id) != null:
		  # Ya existe, quizás refrescar UI? Por ahora no hacer nada.
		  return

	 # Crear instancia local SOLO para visualización/cálculo de stats
	 var new_effect = StatusEffectInstance.new()
	 new_effect.data = effect_data
	 new_effect.remaining_turns = effect_data.duration_turns # Duración inicial visual
	 status_effects.append(new_effect)
	 emit_signal("status_effect_added_visual", effect_data)
	 _update_status_icons_visual()
	 print("%s visually gets status %s" % [name, effect_data.effect_name])
	 # Aplicar VFX continuo si existe y no está ya activo
	 # ...


# Elimina visualmente el icono/efecto de estado (CLIENTE)
func client_remove_status_effect_visual(effect_id: StringName):
	 for i in range(status_effects.size() - 1, -1, -1):
		  if status_effects[i].data.id == effect_id:
			   var removed_data = status_effects[i].data
			   print("%s visually loses status %s" % [name, removed_data.effect_name])
			   # Quitar VFX asociado si lo hubiera
			   status_effects.remove_at(i)
			   emit_signal("status_effect_removed_visual", removed_data)
			   _update_status_icons_visual()
			   return


# Actualiza la duración visual de los estados (CLIENTE, al final del turno sincronizado)
func client_process_end_of_turn_visuals():
	if is_defeated: return
	var changed = false
	for i in range(status_effects.size() - 1, -1, -1):
		var effect = status_effects[i]
		if effect.remaining_turns > 0:
			effect.remaining_turns -= 1
			changed = true
			if effect.remaining_turns <= 0:
				 # El host decidirá si se quita, pero visualmente lo quitamos si llega a 0
				 client_remove_status_effect_visual(effect.data.id)

	if changed:
		_update_status_icons_visual() # Actualizar tooltips, etc.


# --- Modificación de Estado Real (HOST) ---
# Estos métodos son llamados por ActionExecutor/TurnManager en el HOST

func host_take_damage(amount: float):
	if is_defeated: return
	# No usamos el setter aquí para evitar emitir señales en el host innecesariamente
	current_hp = clamp(current_hp - amount, 0.0, character_data.max_hp)
	print("Host: %s HP reduced to %.1f" % [name, current_hp])
	if current_hp <= 0:
		 is_defeated = true # Marcar derrota real en host
		 # BattleManager del host comprobará la victoria

func host_heal(amount: float):
	 if is_defeated: return
	 current_hp = clamp(current_hp + amount, 0.0, character_data.max_hp)
	 print("Host: %s HP healed to %.1f" % [name, current_hp])

# Modifica MP/otros stats directamente en el HOST
func modify_stat(stat_name: StringName, amount: float):
	if not multiplayer.is_server():
		push_warning("Client tried to modify stat directly!")
		return

	match stat_name:
		&"hp": host_take_damage(-amount) if amount < 0 else host_heal(amount)
		&"mp": current_mp = clamp(current_mp + amount, 0.0, character_data.max_mp)
		_: push_warning("Host cannot modify unknown stat: %s" % stat_name)
	# Podrías necesitar sincronizar MP si cambia mucho o afecta la UI

# Añade estado REAL (HOST)
func host_add_status_effect(effect_data: StatusEffectData, caster: Node = null) -> bool:
	if is_defeated: return false
	# Comprobar resistencias/inmunidades del HOST aquí
	# ...

	var existing_effect = _find_status_effect_local(effect_data.id) # Buscar en la lista del host
	if existing_effect:
		if effect_data.stackable:
			# Lógica de apilamiento real
			existing_effect.remaining_turns = effect_data.duration_turns
			print("Host: %s's %s stacked/refreshed." % [name, effect_data.effect_name])
			# No necesita emitir señal visual, el cliente lo hará al recibir resultados
			return true
		else:
			# Refrescar duración si ya existe y no es stackable?
			existing_effect.remaining_turns = max(existing_effect.remaining_turns, effect_data.duration_turns)
			print("Host: %s already had %s (duration refreshed)." % [name, effect_data.effect_name])
			return false # O true si refrescar cuenta como aplicar para la lógica

	# Crear y añadir instancia REAL en el host
	var new_effect = StatusEffectInstance.new()
	new_effect.data = effect_data
	new_effect.remaining_turns = effect_data.duration_turns
	new_effect.caster = caster
	status_effects.append(new_effect)
	print("Host: %s affected by %s." % [name, effect_data.effect_name])
	return true


 # Elimina estado REAL (HOST)
func host_remove_status_effect(effect_id: StringName):
	 for i in range(status_effects.size() - 1, -1, -1):
		 if status_effects[i].data.id == effect_id:
			  print("Host: Removing status %s from %s." % [effect_id, name])
			  status_effects.remove_at(i)
			  return


# Procesa efectos de fin de turno REALES (HOST)
# Devuelve un diccionario de resultados para sincronizar (similar a una acción)
func host_process_end_of_turn_effects() -> Dictionary:
	if is_defeated: return {}

	var results = {
		 "actor_path": get_path(), # Quién sufrió los efectos
		 "dots": [], # {target_path: NodePath, damage: float, type: String, effect_id: StringName}
		 "hots": [], # {target_path: NodePath, amount: float, effect_id: StringName}
		 "expired": [] # [effect_id: StringName]
	}
	var effects_to_remove: Array[StringName] = []

	for effect_instance in status_effects:
		 var effect_data = effect_instance.data

		 # Aplicar Daño por Turno (DOT)
		 if effect_data.damage_per_turn_percent > 0 or effect_data.fixed_damage_per_turn > 0:
			  var base_hp_for_dot = character_data.max_hp # Usar max_hp base
			  var dot_damage = base_hp_for_dot * (effect_data.damage_per_turn_percent / 100.0) + effect_data.fixed_damage_per_turn
			  if dot_damage > 0:
				   host_take_damage(dot_damage) # Aplicar daño REAL
				   results.dots.append({
					   "target_path": get_path(), "damage": dot_damage,
					   "type": effect_data.dot_damage_type, "effect_id": effect_data.id
				   })

		 # Aplicar Curación por Turno (HOT)
		 # ... (lógica similar con host_heal y results.hots)

		 # Reducir duración
		 if effect_instance.remaining_turns > 0:
			  effect_instance.remaining_turns -= 1
			  if effect_instance.remaining_turns <= 0:
				   effects_to_remove.append(effect_data.id)
				   results.expired.append(effect_data.id)


	# Eliminar efectos expirados REALES en host
	for effect_id in effects_to_remove:
		 host_remove_status_effect(effect_id)

	# Devolver resultados para que BattleManager los distribuya
	return results


# --- Auxiliares y otros ---
func is_alive() -> bool:
	# En host, comprueba el estado real. En cliente, el visual.
	if multiplayer.is_server():
		 return current_hp > 0
	else:
		 return not is_defeated # Basado en estado visual

func can_act() -> bool:
	# Esta comprobación la hace el HOST antes de ejecutar la acción.
	# El cliente podría hacerla para desactivar botones, pero la decisión final es del host.
	if not is_alive(): return false
	for effect_instance in status_effects: # Usa lista local (debería estar sincronizada visualmente)
		 if effect_instance.data.prevents_action:
			  # Si estamos en el host, loguear. Si cliente, podría mostrar feedback.
			  if multiplayer.is_server():
				   print("Host: %s cannot act due to %s." % [name, effect_instance.data.effect_name])
			  return false
	return true


# --- Lógica de IA (Solo Host) ---
# Llamado por BattleManager del host si !is_player
func request_ai_action(allies: Array[Node], enemies: Array[Node]):
	if not multiplayer.is_server(): return # Solo el host ejecuta IA
	if not can_act(): # Comprobar si puede actuar (host check)
		 print("Host: AI %s cannot act, ending turn." % name)
		 await get_tree().create_timer(0.3).timeout # Pequeña pausa
		  # Informar a TurnManager para pasar turno
		 var bm = get_parent().get_parent() as BattleManager # Asumiendo BM es abuelo
		 if bm and bm.turn_manager: bm.turn_manager.host_end_current_turn()
		 return

	# Pausa artificial
	await get_tree().create_timer(randf_range(0.5, 1.0)).timeout

	# --- Lógica de Decisión IA (Muy Simplificada) ---
	var chosen_action: AbilityData = null
	var chosen_targets: Array[Node] = []

	# Prioridades de ejemplo:
	# 1. Curarse si HP < 40% y tiene habilidad de cura y MP
	if get_current_hp() / get_stat(&"max_hp") < 0.4:
		 var heal_ability = find_ability_by_type("Healing")
		 if heal_ability and get_current_mp() >= heal_ability.cost:
			  chosen_action = heal_ability
			  chosen_targets = [self] # Asume Self o SingleAlly

	# 2. Usar habilidad ofensiva si MP > 30%
	if not chosen_action and get_current_mp() / get_stat(&"max_mp") > 0.3:
		 var offensive_ability = find_best_offensive_ability(enemies)
		 if offensive_ability and get_current_mp() >= offensive_ability.cost:
			  chosen_action = offensive_ability
			  chosen_targets = choose_ai_target(enemies, offensive_ability.target_type)

	# 3. Ataque básico por defecto
	if not chosen_action:
		 var basic_attack = find_basic_attack()
		 if basic_attack: # Asume que siempre hay un ataque básico usable
			  chosen_action = basic_attack
			  chosen_targets = choose_ai_target(enemies, basic_attack.target_type)

	# 4. Esperar si no se eligió nada
	if not chosen_action:
		 print("Host: AI %s has no valid action, waiting." % name)
		 emit_signal("request_log_message", "%s espera." % get_display_name()) # Log local host
		  # Informar a TurnManager para pasar turno
		 var bm = get_parent().get_parent() as BattleManager
		 if bm and bm.turn_manager: bm.turn_manager.host_end_current_turn()
		 return

	# Emitir señal para que BattleManager del HOST procese la acción
	print("Host: AI %s chose %s on %s" % [name, chosen_action.ability_name, [t.name for t in chosen_targets]])
	emit_signal("action_requested", chosen_action, chosen_targets)


# --- Funciones Auxiliares IA (Ejecutadas en Host) ---
func find_ability_by_type(type: String) -> AbilityData:
	 for ability in character_data.known_abilities:
		  if ability.damage_type == type: return ability
	 return null

func find_best_offensive_ability(enemies: Array[Node]) -> AbilityData:
	 # Lógica simple: la habilidad ofensiva de mayor poder que pueda usar
	 var best_ability: AbilityData = null
	 var max_power = -1
	 for ability in character_data.known_abilities:
		  if (ability.damage_type == "Physical" or ability.damage_type == "Magical") \
			 and ability.power > max_power and get_current_mp() >= ability.cost:
			   best_ability = ability
			   max_power = ability.power
	 return best_ability

func find_basic_attack() -> AbilityData:
	 # Buscar por ID o la primera habilidad ofensiva sin coste (o bajo coste)
	 for ability in character_data.known_abilities:
		  if ability.id == &"BASIC_ATTACK" and get_current_mp() >= ability.cost: return ability
	 for ability in character_data.known_abilities:
		  if (ability.damage_type == "Physical" or ability.damage_type == "Magical") and ability.cost <= 5 and get_current_mp() >= ability.cost:
			   return ability # Fallback a una barata
	 return null # No debería pasar si diseñas bien

func choose_ai_target(potential_targets: Array[Node], target_type: String) -> Array[Node]:
	 if potential_targets.is_empty(): return []
	 # Lógica simple: enemigo con menos HP para single target
	 match target_type:
		  "SingleEnemy", "AnySingle":
			   potential_targets.sort_custom(func(a, b): return a.get_current_hp() < b.get_current_hp())
			   return [potential_targets[0]]
		  "AllEnemies": return potential_targets # ActionExecutor aplica a todos
		  "RandomEnemy": return [potential_targets.pick_random()]
		  "Self": return [self]
		  _: return [potential_targets[0]] # Fallback


# --- Presentación y UI Local ---
func get_display_name() -> String:
	 return tr(character_data.character_name) if character_data else "???"

func show_floating_text(text: String, color: Color = Color.WHITE):
	var FloatTextScene = load("res://Scenes/UI/FloatingText.tscn") # Asegúrate que la ruta es correcta
	if not FloatTextScene or not float_text_spawner: return

	var float_text_instance = FloatTextScene.instantiate()
	# Añadir como hijo del spawner local para que se mueva con el personaje
	float_text_spawner.add_child(float_text_instance)

	# Posición inicial relativa al spawner (ej. encima del sprite)
	float_text_instance.global_position = float_text_spawner.global_position + Vector2(randf_range(-15, 15), -40 + randf_range(-5, 5))

	if float_text_instance.has_method("show_text"):
		 float_text_instance.show_text(text, color)


func _update_status_icons_visual():
	if not status_icon_container: return
	# Limpiar iconos anteriores
	for child in status_icon_container.get_children():
		 child.queue_free()
	# Añadir iconos actuales (basado en lista local)
	for effect_instance in status_effects:
		 if effect_instance.data.icon:
			  var icon_rect = TextureRect.new()
			  icon_rect.texture = effect_instance.data.icon
			  icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			  icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			  icon_rect.custom_minimum_size = Vector2(24, 24) # Ajusta tamaño
			  # Tooltip muestra duración local (puede desfasarse un poco del host)
			  var turns_text = "(%d)" % effect_instance.remaining_turns if effect_instance.remaining_turns > 0 else "(inf)"
			  icon_rect.tooltip_text = "%s %s" % [tr(effect_instance.data.effect_name), turns_text]
			  status_icon_container.add_child(icon_rect)


func _play_death_visuals():
	# Lógica visual de muerte (animación, fade) - NO emite señal 'defeated'
	print("%s playing death visuals." % name)
	if animation_player and animation_player.has_animation("death"):
		 animation_player.play("death")
		 # No esperar aquí, la animación corre en paralelo
	elif sprite:
		 create_tween().tween_property(sprite, "modulate:a", 0, 0.5).set_trans(Tween.TRANS_QUAD)
	# Podrías desactivar colisiones visuales aquí si usas CharacterBody2D

func _find_status_effect_local(effect_id: StringName) -> StatusEffectInstance:
	 # Busca en la lista de estados local
	 for effect_instance in status_effects:
		  if effect_instance.data.id == effect_id:
			   return effect_instance
	 return null

# --- Helper Class (conveniente tenerla aquí) ---
class StatusEffectInstance extends RefCounted:
	var data: StatusEffectData
	var remaining_turns: int # Duración restante (en host es la real, en cliente la visual)
	var caster: Node = null # Quién lo aplicó (referencia en host)
	# var stacks: int = 1 # Si implementas stacks
