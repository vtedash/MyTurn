# res://Scripts/Data/StageData.gd
class_name StageData extends Resource

@export var id: StringName = &"DEFAULT_STAGE"
@export var stage_name: String = "Default Stage" # Potencialmente TR_KEY
@export var background_texture: Texture2D
# O podrías usar: @export var background_scene: PackedScene para fondos más complejos (Parallax, etc.)
@export var battle_music: AudioStream

@export_group("Spawn Points (Max 8 per team example)")
# Define posiciones relativas para diferentes tamaños de equipo.
# Puedes usar Arrays de Vector2, o nombres de Marker2D dentro de una escena de fondo.
@export var team1_spawn_points: Array[Vector2] = [
	Vector2(-200, 0), Vector2(-250, 50), Vector2(-250, -50), Vector2(-300, 0),
	Vector2(-200, 100), Vector2(-200, -100), Vector2(-300, 50), Vector2(-300, -50)
]
@export var team2_spawn_points: Array[Vector2] = [
	Vector2(200, 0), Vector2(250, 50), Vector2(250, -50), Vector2(300, 0),
	Vector2(200, 100), Vector2(200, -100), Vector2(300, 50), Vector2(300, -50)
]

func _init():
	if not id:
		push_error("StageData created without an ID!")
		id = &"ERROR_ID_%s" % ResourceLoader.get_resource_uid(resource_path)
