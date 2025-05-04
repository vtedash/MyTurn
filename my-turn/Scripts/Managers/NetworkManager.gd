# res://Scripts/Managers/NetworkManager.gd
class_name NetworkManager extends Node

signal player_list_changed
signal connection_success
signal connection_failed
signal server_disconnected

const DEFAULT_PORT = 7777 # Elige un puerto

var peer: MultiplayerPeer

func _ready():
	# Conectar señales de la API multijugador
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_host() -> bool:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT)
	if error != OK:
		push_error("Failed to create host: %s" % error)
		peer = null
		return false

	multiplayer.multiplayer_peer = peer
	print("Server created successfully on port %d. Player ID: %d" % [DEFAULT_PORT, multiplayer.get_unique_id()])
	emit_signal("player_list_changed") # Host se añade a la lista
	emit_signal("connection_success")
	return true

func join_game(ip_address: String) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip_address, DEFAULT_PORT)
	if error != OK:
		push_error("Failed to create client: %s" % error)
		peer = null
		return false

	multiplayer.multiplayer_peer = peer
	print("Attempting to connect to %s:%d..." % [ip_address, DEFAULT_PORT])
	return true # La conexión real se confirma con señales

func disconnect_peer():
	if multiplayer.multiplayer_peer:
		# Forzar cierre de conexión activa
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null # Resetear peer
		print("Disconnected from network.")
	if peer:
		peer = null # Limpiar referencia

# --- Getters ---
func is_network_active() -> bool:
	return multiplayer.multiplayer_peer != null and \
		   multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func is_network_host() -> bool:
	return is_network_active() and multiplayer.is_server()

func get_player_id() -> int:
	return multiplayer.get_unique_id() if is_network_active() else 0

func get_connected_peer_ids() -> Array[int]:
	if not is_network_active(): return []
	return multiplayer.get_peers()

func get_all_player_ids() -> Array[int]:
	if not is_network_active(): return []
	var ids = get_connected_peer_ids()
	if multiplayer.is_server() or multiplayer.has_multiplayer_peer():
		 ids.push_front(multiplayer.get_unique_id()) # Añadir el propio ID
	return ids


# --- Signal Handlers ---
func _on_player_connected(id: int):
	print("Player connected: %d" % id)
	emit_signal("player_list_changed")

func _on_player_disconnected(id: int):
	print("Player disconnected: %d" % id)
	emit_signal("player_list_changed")
	# Aquí podrías necesitar lógica adicional si un jugador se desconecta durante la batalla

func _on_connected_to_server():
	print("Successfully connected to server! Player ID: %d" % multiplayer.get_unique_id())
	emit_signal("connection_success")
	emit_signal("player_list_changed") # Propio ID + Host

func _on_connection_failed():
	push_error("Connection failed.")
	disconnect_peer() # Limpiar peer fallido
	emit_signal("connection_failed")

func _on_server_disconnected():
	push_warning("Disconnected from server.")
	disconnect_peer() # Limpiar peer
	emit_signal("server_disconnected")
	emit_signal("player_list_changed") # Vaciar lista
