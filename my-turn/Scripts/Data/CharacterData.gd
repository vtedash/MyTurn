# res://Scripts/Data/CharacterData.gd
class_name CharacterData extends Resource

@export_group("Identification")
@export var id: StringName = &"DEFAULT_ID" # ID único para referencia interna
@export var character_name: String = "Default Character" # Nombre mostrado (potencialmente clave de traducción TR_KEY)
@export_multiline var description: String = "Default description." # Descripción (potencialmente TR_KEY)
@export var character_scene: PackedScene # Escena (.tscn) que representa visualmente al personaje en combate

@export_group("Base Stats")
@export var max_hp: float = 100.0
@export var max_mp: float = 50.0 # O SP, AP, etc.
@export var attack: float = 10.0 # Ataque Físico base
@export var defense: float = 8.0  # Defensa Física base
@export var magic_attack: float = 10.0 # Ataque Mágico/Especial base
@export var magic_defense: float = 8.0 # Defensa Mágica/Especial base
@export var speed: float = 10.0 # Determina el orden de turno
@export var accuracy: float = 95.0 # Precisión base (0-100)
@export var evasion: float = 5.0  # Evasión base (0-100)
# Añade más stats según necesites (resistencia elemental, crítico, etc.)

@export_group("Abilities")
@export var known_abilities: Array[AbilityData] = [] # Lista de habilidades que conoce este personaje

@export_group("AI Behavior (Optional)")
@export_enum("Aggressive", "Defensive", "Supportive", "Balanced") var ai_personality: String = "Balanced"

@export_group("Audio")
@export var hurt_sfx: AudioStream # Sonido al recibir daño
@export var defeat_sfx: AudioStream # Sonido al ser derrotado

# @export_group("Visuals") # Podrías añadir aquí icono para UI, etc.
# @export var preview_icon: Texture2D

func _init():
	# Asegúrate de que las habilidades sean válidas (opcional pero bueno)
	for i in range(known_abilities.size() - 1, -1, -1):
		if not known_abilities[i] is AbilityData:
			push_warning("Invalid AbilityData found in CharacterData '%s'. Removing." % character_name)
			known_abilities.remove_at(i)
	if not id: # Asegura que haya un ID
		push_error("CharacterData created without an ID!")
		id = &"ERROR_ID_%s" % ResourceLoader.get_resource_uid(resource_path)
