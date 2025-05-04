# res://Scripts/UI/FloatingText.gd
extends Node2D

@onready var label: Label = $Label

const DURATION = 1.0
const FADE_DELAY = 0.6
const LIFT_SPEED = -50.0 # Pixels por segundo

func _ready():
	# Asegurar que no esté visible inicialmente si se instancia desde código
	label.modulate.a = 0.0

func show_text(text: String, color: Color = Color.WHITE):
	label.text = text
	label.modulate = color # Aplicar color completo
	label.modulate.a = 1.0 # Hacer visible

	var tween = create_tween().set_parallel(true)
	# Movimiento hacia arriba
	tween.tween_property(self, "position:y", global_position.y + (LIFT_SPEED * DURATION), DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Fade out (después de un delay)
	tween.tween_property(label, "modulate:a", 0.0, DURATION - FADE_DELAY).set_delay(FADE_DELAY).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Autodestrucción
	tween.chain().tween_callback(queue_free)
