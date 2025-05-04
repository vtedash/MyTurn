# res://Scripts/UI/MainMenu.gd
extends Control

@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var ip_address_edit: LineEdit = %IPAddressEdit
@onready var quit_button: Button = %QuitButton

# Ruta a la escena de configuración/lobby
const COMBAT_SETUP_SCENE = "res://Scenes/UI/CombatSetupScreen.tscn"

func _ready():
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	quit_button.pressed.connect(get_tree().quit)

	# Conectar a señales de NetworkManager
	NetworkManager.connection_success.connect(_on_connection_success)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	# Asegurarse de desconectar al volver al menú (si vienes de una partida)
	NetworkManager.disconnect_peer()


func _on_host_pressed():
	print("Attempting to host...")
	disable_buttons()
	if NetworkManager.create_host():
		 # _on_connection_success se llamará si tiene éxito
		 pass
	else:
		 print("Failed to host.")
		 enable_buttons()


func _on_join_pressed():
	var ip = ip_address_edit.text.strip_edges()
	if ip.is_valid_ip_address() or ip == "localhost": # Permitir localhost
		 print("Attempting to join %s..." % ip)
		 disable_buttons()
		 if not NetworkManager.join_game(ip):
			  print("Failed to initiate connection.")
			  enable_buttons()
		 # Esperar señal _on_connection_success o _on_connection_failed
	else:
		 print("Invalid IP Address.")
		 # Podrías mostrar un mensaje de error en la UI


func _on_connection_success():
	print("Network connection established! Transitioning to Combat Setup...")
	# Cambiar a la escena de configuración/lobby
	var result = get_tree().change_scene_to_file(COMBAT_SETUP_SCENE)
	if result != OK:
		 push_error("Failed to change scene to Combat Setup: %s" % result)
		 enable_buttons() # Re-habilitar si falla el cambio de escena
		 NetworkManager.disconnect_peer() # Desconectar si no se pudo cambiar


func _on_connection_failed():
	 print("Connection failed.")
	 # Mostrar mensaje de error al usuario aquí
	 enable_buttons()


func disable_buttons():
	host_button.disabled = true
	join_button.disabled = true
	ip_address_edit.editable = false

func enable_buttons():
	 host_button.disabled = false
	 join_button.disabled = false
	 ip_address_edit.editable = true
