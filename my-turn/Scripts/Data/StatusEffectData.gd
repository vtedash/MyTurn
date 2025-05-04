# res://Scripts/Data/StatusEffectData.gd
class_name StatusEffectData extends Resource

@export_group("Identification")
@export var id: StringName = &"DEFAULT_STATUS"
@export var effect_name: String = "Default Status" # Potencialmente TR_KEY
@export_multiline var description: String = "Default status effect description." # Potencialmente TR_KEY
@export var icon: Texture2D # Icono para mostrar en la UI

@export_group("Mechanics")
@export var duration_turns: int = 3 # Duración en turnos (-1 para permanente hasta curar)
@export_enum("Buff", "Debuff", "DamageOverTime", "HealOverTime", "Control") var effect_type: String = "Debuff"
@export var stackable: bool = false # ¿Se puede aplicar múltiples veces?
# @export var max_stacks: int = 1 # Si es stackable

@export_group("Stat Modifiers (Multiplicative)")
# Multiplicadores: 1.0 = sin cambio, 1.2 = +20%, 0.8 = -20%
@export var attack_mod: float = 1.0
@export var defense_mod: float = 1.0
@export var magic_attack_mod: float = 1.0
@export var magic_defense_mod: float = 1.0
@export var speed_mod: float = 1.0
# Añade más modificadores según necesites

@export_group("Per-Turn Effects")
@export var damage_per_turn_percent: float = 0.0 # % de MaxHP como daño por turno
@export var fixed_damage_per_turn: float = 0.0 # Daño fijo por turno
@export_enum("Physical", "Magical", "Neutral") var dot_damage_type: String = "Neutral"
@export var heal_per_turn_percent: float = 0.0 # % de MaxHP como curación por turno
@export var fixed_heal_per_turn: float = 0.0 # Curación fija por turno

@export_group("Restrictions")
@export var prevents_action: bool = false # Ej: Parálisis, Sueño
@export var prevents_movement: bool = false # Si tu juego tuviera movimiento en batalla

@export_group("Presentation")
@export var effect_vfx: PackedScene # VFX continuo mientras el estado está activo (opcional)
@export var apply_sfx: AudioStream # Sonido al aplicar
@export var remove_sfx: AudioStream # Sonido al quitar/expirar

func _init():
	if not id:
		push_error("StatusEffectData created without an ID!")
		id = &"ERROR_ID_%s" % ResourceLoader.get_resource_uid(resource_path)
	if duration_turns == 0: duration_turns = 1 # Duración mínima de 1 si no es permanente
