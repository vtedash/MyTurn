# res://Scripts/Managers/DamageCalculator.gd
class_name DamageCalculator extends Node # O 'extends Object' si prefieres sin nodo

# --- Constantes Configurables (Opcional) ---
const MIN_DAMAGE = 1.0
const CRIT_MULTIPLIER = 1.5
const VARIANCE_MIN = 0.9
const VARIANCE_MAX = 1.1

# --- Cálculo de Daño ---
# NOTA: Estos cálculos SOLO deben ejecutarse en el HOST en una partida online.
func calculate_damage(actor: Node, target: Node, action: AbilityData, is_crit: bool) -> float:
	if not actor or not target or not action:
		push_error("Invalid arguments for calculate_damage")
		return 0.0

	var damage = 0.0
	match action.damage_type:
		"Physical":
			damage = _calculate_physical_damage(actor, target, action, is_crit)
		"Magical":
			damage = _calculate_magic_damage(actor, target, action, is_crit)
		_:
			# Tipos no dañinos devuelven 0
			return 0.0

	# Asegurar daño mínimo
	return floor(max(MIN_DAMAGE, damage))


func _calculate_physical_damage(actor: Node, target: Node, action: AbilityData, is_crit: bool) -> float:
	# Asume que actor y target tienen el método get_current_stat
	var actor_atk = actor.get_current_stat(&"attack")
	var target_def = target.get_current_stat(&"defense")
	var ability_power = action.power

	# Fórmula base (ejemplo muy simple)
	var base_damage = (actor_atk * ability_power) / max(1.0, target_def) # Evitar división por cero

	# Variación aleatoria
	var random_variance = randf_range(VARIANCE_MIN, VARIANCE_MAX)
	var damage = base_damage * random_variance

	# Modificador crítico
	if is_crit:
		damage *= CRIT_MULTIPLIER

	# Aplicar resistencias/debilidades elementales (si las implementas)
	# var element_multiplier = get_element_multiplier(action.element, target.get_resistances())
	# damage *= element_multiplier

	return damage


func _calculate_magic_damage(actor: Node, target: Node, action: AbilityData, is_crit: bool) -> float:
	var actor_matk = actor.get_current_stat(&"magic_attack")
	var target_mdef = target.get_current_stat(&"magic_defense")
	var ability_power = action.power

	var base_damage = (actor_matk * ability_power) / max(1.0, target_mdef)
	var random_variance = randf_range(VARIANCE_MIN, VARIANCE_MAX)
	var damage = base_damage * random_variance

	if is_crit:
		damage *= CRIT_MULTIPLIER

	# Aplicar resistencias/debilidades elementales
	# ...

	return damage

# --- Cálculo de Curación ---
func calculate_healing(actor: Node, target: Node, action: AbilityData, is_crit: bool) -> float:
	if not actor or not target or not action:
		push_error("Invalid arguments for calculate_healing")
		return 0.0

	# La curación puede basarse en el poder de la habilidad, el ataque mágico del lanzador, etc.
	# Ejemplo basado en poder de habilidad y ataque mágico:
	var actor_matk = actor.get_current_stat(&"magic_attack")
	var ability_power = action.power

	# Fórmula de ejemplo (ajusta según tu diseño)
	var base_healing = (actor_matk * 0.5 + ability_power * 1.5)

	var random_variance = randf_range(VARIANCE_MIN, VARIANCE_MAX)
	var healing = base_healing * random_variance

	if is_crit:
		healing *= CRIT_MULTIPLIER

	# Limitar la curación a la vida máxima si no quieres sobrecuración
	# var max_hp = target.get_current_stat(&"max_hp")
	# var current_hp = target.get_current_stat(&"hp") # Necesitarías get_current_stat para HP también
	# healing = min(healing, max_hp - current_hp)

	return floor(max(1.0, healing)) # Curar al menos 1

# --- Cálculo de Probabilidades (Ejemplo Hit/Miss) ---
# ¡SOLO EJECUTAR EN HOST!
func check_hit(actor: Node, target: Node, action: AbilityData) -> bool:
	# Curas, bufos, etc., siempre aciertan (o podrías añadir flag en AbilityData)
	if action.damage_type == "Healing" or action.damage_type == "Support" or action.damage_type == "Status":
		 # A menos que el estado tenga su propia probabilidad de aplicación
		return true

	var actor_acc = actor.get_current_stat(&"accuracy")
	var target_eva = target.get_current_stat(&"evasion")

	# Fórmula simple Hit vs Evade
	var hit_chance = clamp(actor_acc - target_eva, 1.0, 100.0) # Asegurar al menos 1% y max 100%
	var random_roll = randf() * 100.0

	return random_roll <= hit_chance

# ¡SOLO EJECUTAR EN HOST!
func check_status_apply(actor: Node, target: Node, ability: AbilityData, status_effect: StatusEffectData) -> bool:
	# Comprobación base de probabilidad de la habilidad
	var base_chance = ability.chance_to_apply_status
	if randf() * 100.0 > base_chance:
		return false

	# Aquí podrías añadir lógica de resistencia del objetivo al estado específico
	# if target.has_resistance_to(status_effect.id): return false

	return true

# ¡SOLO EJECUTAR EN HOST!
func check_crit(actor: Node, target: Node, action: AbilityData) -> bool:
	# Implementa tu lógica de crítico (basada en stats, suerte, etc.)
	# Ejemplo simple: 5% de probabilidad
	# var crit_chance = actor.get_current_stat(&"critical_chance") # Si tienes stat
	var crit_chance = 5.0
	return randf() * 100.0 <= crit_chance
