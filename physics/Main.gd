extends Node2D

const MAX_PORT = 65535
const CONNECT_ATTEMPTS = 20
const MODE_SERVER = "server"
const MODE_CLIENT = "client"
const ROOM_PLAYER_CNT = 2
const UPDATE_DELTATIME = 30  # every 30 milliseconds a frame

var mode = null
var is_started = false

var svr_peer = PacketPeerUDP.new()
var cli_peer = PacketPeerUDP.new()

var game_room : GameRoom = GameRoom.new()

# For server
var clients = []
var svr_tick = 0
var svr_history_frames = {}
var svr_game_start_time : int = -1

# For client
var cli_max_svr_tick = 0
var cli_game_start_time : int = -1
var cli_pre_send_input_cnt : int = 1
var cli_input_tick = 0
var cli_tick_since_game_start : int = 0
var cli_world_tick : int = 0
var cli_cur_svr_tick : int = -1
var cli_svr_frames = {}
var cli_has_recv_frame := false

# nodes
var ctrl_ip
var ctrl_port
var ctrl_start
var ctrl_connect


# Called when the node enters the scene tree for the first time.
func _ready():
	$help_msg.hide()
	ctrl_ip = get_node("controls/ip")
	ctrl_port = get_node("controls/port")
	ctrl_start = get_node("controls/start_button")
	ctrl_connect = get_node("controls/connect_button")


# warning-ignore:unused_argument
func _process(delta):
	if Input.is_action_pressed("ui_cancel"):
		$controls.show()
		$help_msg.hide()
		
	if is_started:
		# just do some recv
		if is_server():
			svr_do_recv()
		elif is_client():
			cli_do_recv()		
	
	
func _physics_process(delta):		
	if is_started:
		if is_server():
			svr_cycle(delta)
		elif is_client():
			cli_cycle(delta)


func reset_on_start():
	clients = []
	svr_tick = 0
	svr_history_frames = {}
	svr_game_start_time = -1	
	

func set_mode(_mode):
	assert(_mode == MODE_SERVER || _mode == MODE_CLIENT)
	mode = _mode
	
	
func reset_mode():
	mode = null
	
	
func is_server():
	return mode == MODE_SERVER
	
	
func is_client():
	return mode == MODE_CLIENT


func _on_start_button_pressed():
	if is_client():
		return
		
	if not is_started:
		svr_on_start()
	else:
		svr_on_stop()


func _on_connect_button_pressed():
	if is_server():
		return
		
	if not is_started:
		cli_on_start()
	else:
		cli_on_stop()


func svr_on_start():	
	var port = int(ctrl_port.get_value())
	if (svr_peer.listen(port) != OK):
		print("Error listening on port ", port)
		return
		
	print("Listening on port ", port)
	set_mode(MODE_SERVER)
	is_started = true
	
	ctrl_ip.set_editable(false)
	ctrl_port.set_editable(false)
	ctrl_start.set_text("StopServer")
	ctrl_connect.set_disabled(true)
	$controls.hide()
	$help_msg.show()
	
	
func svr_on_stop():
	print("Stop Listening on port ", ctrl_port.get_value())
	svr_peer.close()
	reset_mode()
	is_started = false
	
	ctrl_ip.set_editable(true)
	ctrl_port.set_editable(true)
	ctrl_start.set_text("StartServer")
	ctrl_connect.set_disabled(false)


func svr_broad_inputs(tick, inputs):
	var packet = {
		t = "g2c_frame",
		tick = tick,
		inputs = inputs,
	}
			
	svr_broad(packet)		
				
				
func svr_broad(packet):
	for client in clients:
		svr_peer.set_dest_address(client.ip, client.port)
		svr_peer.put_var(packet)	
		
				
				
# warning-ignore:unused_argument
func svr_cycle(delta):
	svr_do_recv()
	svr_do_update(delta)


# warning-ignore:unused_argument
func svr_do_update(delta):
	if svr_game_start_time <= 0:
		return

	while svr_tick < svr_get_tick_since_game_start():
		svr_chk_broad_inputs(true)


func svr_get_tick_since_game_start():
	if svr_game_start_time <= 0:
		return 0
	var tick = floor( (Time.get_ticks_msec() - svr_game_start_time) / UPDATE_DELTATIME )
	return tick

		
func svr_chk_broad_inputs(is_force = false):
	var frame = svr_get_or_create_frame(svr_tick)

	if not is_force:
		if frame["inputs"].size() < ROOM_PLAYER_CNT:
			return

	var inputs = frame["inputs"]
	svr_broad_inputs(svr_tick,  inputs)
	svr_tick += 1

	if svr_game_start_time <= 0:
		svr_game_start_time = Time.get_ticks_msec()


func svr_do_recv():
	while (svr_peer.get_available_packet_count() > 0):
		var packet = svr_peer.get_var()
		if packet == null:
			continue
		if packet.t == "c2g_connect":
			svr_on_c2g_connect(packet)
		elif packet.t == "c2g_input":
			svr_on_c2g_input(packet)		


# warning-ignore:unused_argument
func svr_on_c2g_connect(packet):
	var packet_ip = svr_peer.get_packet_ip()
	var packet_port = svr_peer.get_packet_port()
	if (not svr_has_cli(packet_ip, packet_port)):
		print("Client connected from ", packet_ip, ":", packet_port)
		clients.append({ ip = packet_ip, port = packet_port, seq = 0 })

	svr_peer.set_dest_address(packet_ip, packet_port)
	svr_peer.put_var({t = "g2c_connect"})
	
	if svr_get_player_cnt() == ROOM_PLAYER_CNT:
		svr_start_game()
	

func svr_on_c2g_input(packet):
	var packet_ip = svr_peer.get_packet_ip()
	var packet_port = svr_peer.get_packet_port()	
	if packet.tick < svr_tick:
		print("svr_on_c2g_input recv old packet, packet:", packet, ", svr_tick:", 
			svr_tick, ", packet_ip:", packet_ip, ", packet_port:", packet_port)
		return

	var frame = svr_get_or_create_frame(packet.tick)
	frame["inputs"].append(packet["input"])
	svr_chk_broad_inputs(false)

	
func svr_get_player_cnt():
	return clients.size()
	
	
func svr_start_game():
	print("svr_start_game")
	var packet = {
		t = "g2c_gamestart",
	}
	svr_broad(packet)		
	




func svr_get_or_create_frame(tick):
	var frame = svr_history_frames.get(tick)
	if not frame:
		frame = {
			inputs = []
		}
		svr_history_frames[tick] = frame
	return frame


# Check client is registered
func svr_has_cli(p_ip, p_port):
	for client in clients:
		if (client.ip == p_ip and client.port == p_port):
			return true
	return false


#####################################################################
# client code
#####################################################################

func cli_try_port():
	var client_port = int(ctrl_port.get_value()) + 1

	while (client_port <= MAX_PORT and cli_peer.listen(client_port) != OK):
		client_port += 1
		
	if client_port <= MAX_PORT:
		return client_port
	
	
func cli_on_start():
	var client_port = cli_try_port()
	if not client_port:
		print("cli_on_start fail, fail to get a proper client port")
		return
	
	# Set server address
	cli_peer.set_dest_address(ctrl_ip.get_text(), ctrl_port.get_value())

	# Try to connect to server
	var attempts = 0
	var connected = false

	while (not connected and attempts < CONNECT_ATTEMPTS):
		attempts += 1
		cli_peer.put_var({t = "c2g_connect"})
		OS.delay_msec(50)

		while (cli_peer.get_available_packet_count() > 0):
			var packet = cli_peer.get_var()
			if (packet != null and packet.t == "g2c_connect"):
				connected = true
				break

	if (not connected):
		print("cli_on_start fail, fail connecting to ", ctrl_ip.get_text(), ":", ctrl_port.get_value())
		return

	print("Connected to ", ctrl_ip.get_text(), ":", ctrl_port.get_value())
	is_started = true
	set_mode(MODE_CLIENT)
		
	ctrl_ip.set_editable(false)
	ctrl_port.set_editable(false)
	ctrl_start.set_disabled(true)	
	ctrl_connect.set_text("Disconnect")
	$controls.hide()
	$help_msg.show()
	
	
func cli_on_stop():
	reset_mode()
	is_started = false
	cli_peer.close()
	print("Disconnected from ", ctrl_ip.get_text(), ":", ctrl_port.get_value())
	
	ctrl_ip.set_editable(true)
	ctrl_port.set_editable(true)
	ctrl_connect.set_text("Connect")
	ctrl_start.set_disabled(false)


func cli_start_game():
	while cli_input_tick < cli_pre_send_input_cnt:
		cli_send_input(cli_input_tick)
		cli_input_tick += 1


# warning-ignore:unused_argument
func cli_cycle(delta):
	cli_do_recv()
	cli_do_update(delta)


# warning-ignore:unused_argument
func cli_do_update(delta):
	if cli_has_recv_frame and cli_game_start_time < 0:
		cli_game_start_time = Time.get_ticks_msec()

	# game not start yet
	if cli_game_start_time < 0:
		return

	cli_tick_since_game_start = floor( (Time.get_ticks_msec() - cli_game_start_time) / UPDATE_DELTATIME)

	# send inputs
	while cli_input_tick <= cli_get_input_target_tick():
		cli_send_input(cli_input_tick)
		cli_input_tick += 1

	# apply svr input
	while cli_world_tick < cli_cur_svr_tick:
		var inputs = cli_svr_frames.get(cli_world_tick)
		if not inputs:
			break
		cli_apply_inputs(inputs)
		cli_world_tick += 1



func cli_get_input_target_tick():
	return (cli_tick_since_game_start + cli_pre_send_input_cnt)


func cli_do_recv():
	while cli_peer.get_available_packet_count() > 0:
		var packet = cli_peer.get_var()
		print("cli_do_recv, p: ", packet)
		if (packet == null):
			continue
		if packet.t == "g2c_gamestart":
			cli_on_g2c_gamestart(packet)
		elif packet.t == "g2c_frame":
			cli_on_g2c_frame(packet)


# warning-ignore:unused_argument
func cli_on_g2c_gamestart(packet):
	print("cli_on_g2c_gamestart")
	cli_start_game()
	

func cli_on_g2c_frame(packet):
	cli_has_recv_frame = true
	if not cli_svr_frames.has(packet.tick):
		cli_svr_frames[packet.tick] = packet.inputs
		cli_cur_svr_tick = max(cli_cur_svr_tick, packet.tick)


func cli_send_input(tick):
	if is_client() and is_started:
		var dir = Vector2.ZERO
		if Input.is_action_pressed("move_right"):
			dir.x += 1
		if Input.is_action_pressed("move_left"):
			dir.x -= 1
		if Input.is_action_pressed("move_down"):
			dir.y += 1
		if Input.is_action_pressed("move_up"):
			dir.y -= 1
			
		if dir.length() > 0:
			dir = dir.normalized()
			
		var p = {
			t = "c2g_input",
			tick = tick,
			input = {
				dir = dir,
			}
		}
		cli_peer.put_var(p)		
		print("cli_send_input, p: ", p)		


# Event handler
func cli_apply_inputs(inputs):
	for input in inputs:
		if input.has("dir"):
			print("cli_apply_inputs:", input)
			$Player.apply_input(input.dir)
