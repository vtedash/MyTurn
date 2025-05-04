# res://Scripts/Data/AbilityData.gd
class_name AbilityData extends Resource

@export_group("Identification")
@export var id: StringName = &"DEFAULT_ABILITY"
@export var ability_name: String = "Default Ability" # Potencialmente TR_KEY
@export_multiline var description: String = "Default ability description." # Potencialmente TR_KEY

@export_group("Mechanics")
@export var cost: float = 5.0 # Costo de MP/SP/etc.
@export var power: float = 10.0 # Potencia base (usada en cálculos de daño/curación)
@export_enum("Physical", "Magical", "Healing", "Support", "Status") var damage_type: String = "Physical"
# @export var element: String = "Neutral" # Opcional: Elemento (Fuego, Hielo, etc.)

@export_group("Targeting")
@export_enum("SingleEnemy", "AllEnemies", "SingleAlly", "AllAllies", "Self", "AnySingle", "RandomEnemy", "RandomAlly") var target_type: String = "SingleEnemy"
# @export var range: int = 1 # Opcional: Para sistemas basados en grid/posición

@export_group("Effects")
@export var status_effects_to_apply: Array[StatusEffectData] = [] # Estados alterados que aplica
@export var chance_to_apply_status: float = 100.0 # Probabilidad (0-100) de aplicar los estados

@export_group("Presentation")
@export var animation_scene: PackedScene # Escena (.tscn) para la animación/VFX de la habilidad
@export var sfx: AudioStream # Sonido de la habilidad

func _init():
	if not id:
		push_error("AbilityData created without an ID!")
		id = &"ERROR_ID_%s" % ResourceLoader.get_resource_uid(resource_path)
	if cost < 0: cost = 0
	if power < 0: power = 0
	chance_to_apply_status = clamp(chance_to_apply_status, 0.0, 100.0)
	for i in range(status_effects_to_apply.size() - 1, -1, -1):
		if not status_effects_to_apply[i] is StatusEffectData:
			push_warning("Invalid StatusEffectData found in AbilityData '%s'. Removing." % ability_name)
			status_effects_to_apply.remove_at(i)
