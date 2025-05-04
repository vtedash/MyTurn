# res://Scripts/Managers/ContentLoader.gd
class_name ContentLoader extends Node

var characters: Dictionary = {} # String(id): CharacterData
var abilities: Dictionary = {}  # String(id): AbilityData
var stages: Dictionary = {}     # String(id): StageData
var status_effects: Dictionary = {} # String(id): StatusEffectData

const BASE_CONTENT_PATH = "res://Content/Base/"
const WORKSHOP_CONTENT_PATH = "user://WorkshopContent/"

signal content_loaded
signal content_load_finished # Señal después de cargar todo

func _ready():
	var dir_access = DirAccess.open("user://")
	if not dir_access or not dir_access.dir_exists(WORKSHOP_CONTENT_PATH):
		if dir_access:
			var err = dir_access.make_dir_recursive(WORKSHOP_CONTENT_PATH)
			if err != OK:
				push_error("Failed to create Workshop content directory: %s. Error code: %s" % [WORKSHOP_CONTENT_PATH, err])
		else:
			 push_error("Could not access user:// directory.")


	# Cargar contenido inicial (puedes diferirlo si prefieres)
	# Usar call_deferred para asegurar que otros Autoloads estén listos si dependen de él
	call_deferred("load_all_content")


func load_all_content():
	print("Loading all content...")
	characters.clear()
	abilities.clear()
	stages.clear()
	status_effects.clear()

	# Cargar contenido base
	_load_resources_from_directory(BASE_CONTENT_PATH + "Characters/", CharacterData, characters)
	_load_resources_from_directory(BASE_CONTENT_PATH + "Abilities/", AbilityData, abilities)
	_load_resources_from_directory(BASE_CONTENT_PATH + "Stages/", StageData, stages)
	_load_resources_from_directory(BASE_CONTENT_PATH + "StatusEffects/", StatusEffectData, status_effects)


	# Cargar contenido del Workshop (asume subcarpetas por mod)
	var workshop_dir = DirAccess.open(WORKSHOP_CONTENT_PATH)
	if workshop_dir:
		workshop_dir.list_dir_begin()
		var item_name = workshop_dir.get_next()
		while item_name != "":
			if workshop_dir.current_is_dir() and not item_name.begins_with("."): # Ignorar ocultos
				var mod_path = WORKSHOP_CONTENT_PATH.path_join(item_name) + "/"
				print("Scanning Workshop mod: %s" % mod_path)
				_load_resources_from_directory(mod_path + "Characters/", CharacterData, characters)
				_load_resources_from_directory(mod_path + "Abilities/", AbilityData, abilities)
				_load_resources_from_directory(mod_path + "Stages/", StageData, stages)
				_load_resources_from_directory(mod_path + "StatusEffects/", StatusEffectData, status_effects)
			item_name = workshop_dir.get_next()
	else:
		push_warning("Could not open Workshop content directory: %s" % WORKSHOP_CONTENT_PATH)


	print("Content loading complete. Loaded: %d Chars, %d Abilities, %d Stages, %d StatusFx" % [characters.size(), abilities.size(), stages.size(), status_effects.size()])
	emit_signal("content_load_finished") # Usar una señal diferente al terminar


func _load_resources_from_directory(path: String, resource_type: Script, storage: Dictionary):
	#print("Scanning directory: %s for type %s" % [path, resource_type])
	var dir = DirAccess.open(path)
	if not dir:
		# print("Directory not found or cannot be opened: %s" % path)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var file_path = path.path_join(file_name)
			# Usar load en lugar de ResourceLoader.load para evitar errores si el script base no está listo
			# Aunque ResourceLoader debería funcionar bien en Godot 4 con class_name
			# var resource = load(file_path)
			var resource = ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_IGNORE) # Intentar sin caché por si acaso

			if resource:
				 # Comprobar tipo de forma más robusta en Godot 4
				if resource is resource_type:
					if resource.has_method("get") and resource.has("id") and resource.get("id") != StringName(""): # Validación básica
						var id_str = String(resource.id)
						if storage.has(id_str):
							push_warning("Duplicate ID found: '%s' at path '%s'. Overwriting previous entry from '%s'." % [id_str, file_path, storage[id_str].resource_path])
						storage[id_str] = resource
						# print("Loaded %s: %s" % [resource_type.resource_path.get_file(), id_str])
					else:
						push_warning("Resource at '%s' is missing a valid 'id' property or is empty." % file_path)
				else:
					push_warning("Resource at '%s' is not of expected type '%s' (it is '%s')." % [file_path, resource_type, resource.get_class()])
			else:
				push_error("Failed to load resource at '%s'." % file_path)

		file_name = dir.get_next()


# --- Getters Públicos ---
func get_character(id: StringName) -> CharacterData:
	return characters.get(String(id), null)

func get_ability(id: StringName) -> AbilityData:
	return abilities.get(String(id), null)

func get_stage(id: StringName) -> StageData:
	return stages.get(String(id), null)

func get_status_effect(id: StringName) -> StatusEffectData:
	return status_effects.get(String(id), null)

func get_all_characters() -> Array[CharacterData]:
	return characters.values()

func get_all_abilities() -> Array[AbilityData]:
	return abilities.values()

func get_all_stages() -> Array[StageData]:
	return stages.values()

func get_all_status_effects() -> Array[StatusEffectData]:
	return status_effects.values()

# --- Funciones de Validación para Online ---
func get_content_ids_and_hashes(char_ids: Array[StringName], ability_ids: Array[StringName], stage_id: StringName) -> Dictionary:
	# Esta función es un placeholder. Necesitarías calcular hashes reales.
	# Para el MVP, solo devolver los IDs podría ser suficiente si confías en que los nombres son únicos.
	var validation_data = {
		"characters": {}, # id: hash
		"abilities": {},  # id: hash
		"stage": {}       # id: hash
	}
	var file_access = FileAccess # Usa el estático [18]

	for id in char_ids:
		var data = get_character(id)
		if data:
			# Placeholder hash - ¡USA UNO REAL (MD5, SHA256)!
			var hash = FileAccess.get_md5(data.resource_path) if FileAccess.file_exists(data.resource_path) else "INVALID_PATH"
			validation_data.characters[String(id)] = hash
	for id in ability_ids:
		 var data = get_ability(id)
		 if data:
			var hash = FileAccess.get_md5(data.resource_path) if FileAccess.file_exists(data.resource_path) else "INVALID_PATH"
			validation_data.abilities[String(id)] = hash
	var stage_data = get_stage(stage_id)
	if stage_data:
		 var hash = FileAccess.get_md5(stage_data.resource_path) if FileAccess.file_exists(stage_data.resource_path) else "INVALID_PATH"
		 validation_data.stage[String(stage_id)] = hash

	return validation_data

func verify_content(required_data: Dictionary) -> bool:
	# Comprueba si el contenido local coincide con los hashes requeridos por el host
	var local_data = get_content_ids_and_hashes(
		required_data.characters.keys().map(func(id_str): return StringName(id_str)),
		required_data.abilities.keys().map(func(id_str): return StringName(id_str)),
		StringName(required_data.stage.keys()[0]) # Asume un solo stage
	)

	if local_data.characters.hash() != required_data.characters.hash() or \
	   local_data.abilities.hash() != required_data.abilities.hash() or \
	   local_data.stage.hash() != required_data.stage.hash():
		push_warning("Content mismatch detected!")
		print("Required: ", required_data)
		print("Local:    ", local_data)
		# Aquí podrías implementar una comparación más detallada para saber QUÉ falla.
		return false
	print("Content verification successful.")
	return true
