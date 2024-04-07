class_name GameRoom
extends Node

var time_since_start : float = 0


func _init():
	print("gameroom init")


# Called when the node enters the scene tree for the first time.
func _ready():
	print("gameroom ready")
	
	
func do_update(delta):
	time_since_start += delta

