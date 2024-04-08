extends Node2D

const MAX_PORT = 65535
const CONNECT_ATTEMPTS = 20
const MODE_SERVER = "server"
const MODE_CLIENT = "client"
const ROOM_PLAYER_CNT = 2
const UPDATE_DELTATIME = 30  # every 30 milliseconds a frame
const NETWORK_FPS = 40

const TT = {
	g2c_connect = "g2c_connect",
	g2c_gamestart = "g2c_gamestart",
	g2c_obj_update = "g2c_obj_update",
	g2c_cli_input = "g2c_cli_input",
	
	c2g_connect = "c2g_connect",
	c2g_input = "c2g_input",
}

var mode = null
var is_started = false

var svr_peer = PacketPeerUDP.new()
var cli_peer = PacketPeerUDP.new()


# For server
var svr_clients = []
var svr_cli_input_buffer := []
var svr_cli_id := 0


# For client
var cli_game_start_time : int = -1
var cli_seq := -1
var cli_recv_input_buffer := []
var cli_my_id = null


# For both server and client
var net_sync_timer : float = 0.0


# nodes
var ctrl_ip
var ctrl_port
var ctrl_start
var ctrl_connect
var ctrl_balls
var ctrl_player


# Called when the node enters the scene tree for the first time.
func _ready():
	$help_msg.hide()
	ctrl_ip = get_node("controls/ip")
	ctrl_port = get_node("controls/port")
	ctrl_start = get_node("controls/start_button")
	ctrl_connect = get_node("controls/connect_button")
	ctrl_balls = get_node("balls").get_children()
	ctrl_player = get_node("Player")


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
	svr_clients = []
	

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
				
				
func svr_broad(packet):
	for client in svr_clients:
		svr_peer.set_dest_address(client.ip, client.port)
		svr_peer.put_var(packet)	
						
				
# warning-ignore:unused_argument
func svr_cycle(delta):
	svr_do_recv()
	svr_do_update(delta)


# warning-ignore:unused_argument
func svr_do_update(delta):
	var duration = 1.0 / NETWORK_FPS
	if (net_sync_timer < duration):
		net_sync_timer += delta
		return
	net_sync_timer = 0

	# apply client inputs
	var tmp_buf = svr_cli_input_buffer
	svr_cli_input_buffer = []

	for buf in tmp_buf:
		var packet = buf.packet
		var input = packet.input
		if input.has("dir"):
			$Player.apply_input(input.dir)

	svr_broad({
		t = TT.g2c_cli_input,
		inputs = tmp_buf,		
	})


	# sync object state
	for client in svr_clients:
		var packet = {
			t = TT.g2c_obj_update,
			seq = client.seq,
			balls = [],
			player = {
				position = ctrl_player.get_position(), 
				rotation = ctrl_player.get_rotation(), 
				linear_velocity = ctrl_player.get_linear_velocity(), 
				angular_velocity = ctrl_player.get_angular_velocity(),					
			},
		}
		client.seq += 1
		for ball in ctrl_balls:
			packet.balls.append({
				name = ball.get_name(), 
				position = ball.get_position(), 
				rotation = ball.get_rotation(), 
				linear_velocity = ball.get_linear_velocity(), 
				angular_velocity = ball.get_angular_velocity(),
			})
		svr_peer.set_dest_address(client.ip, client.port)
		svr_peer.put_var(packet)


func svr_do_recv():
	while (svr_peer.get_available_packet_count() > 0):
		var packet = svr_peer.get_var()
		if packet == null:
			continue
		if packet.t == TT.c2g_connect:
			svr_on_c2g_connect(packet)
		elif packet.t == TT.c2g_input:
			svr_on_c2g_input(packet)		


# warning-ignore:unused_argument
func svr_on_c2g_connect(packet):
	var packet_ip = svr_peer.get_packet_ip()
	var packet_port = svr_peer.get_packet_port()
	var cli_id = svr_cli_id
	svr_cli_id = svr_cli_id+1
	if (not svr_has_cli(packet_ip, packet_port)):
		print("Client connected from ", packet_ip, ":", packet_port)
		svr_clients.append({ ip = packet_ip, port = packet_port, seq = 0, cli_id = cli_id})

	svr_peer.set_dest_address(packet_ip, packet_port)
	svr_peer.put_var({t = TT.g2c_connect, cli_id = cli_id})

	svr_peer.set_dest_address(packet_ip, packet_port)
	svr_peer.put_var({t = TT.g2c_gamestart})
	

func svr_on_c2g_input(packet):
	var packet_ip = svr_peer.get_packet_ip()
	var packet_port = svr_peer.get_packet_port()

	svr_cli_input_buffer.append({
		ip = packet_ip,
		port = packet_port,
		packet = packet
	})

	
func svr_get_player_cnt():
	return svr_clients.size()


# Check client is registered
func svr_has_cli(p_ip, p_port):
	for client in svr_clients:
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
		cli_peer.put_var({t = TT.c2g_connect})
		OS.delay_msec(50)

		while (cli_peer.get_available_packet_count() > 0):
			var packet = cli_peer.get_var()
			if (packet != null and packet.t == TT.g2c_connect):
				connected = true
				cli_my_id = packet.cli_id
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


# warning-ignore:unused_argument
func cli_cycle(delta):
	cli_do_recv()
	cli_do_update(delta)


# warning-ignore:unused_argument
func cli_do_update(delta):
	if cli_game_start_time < 0:
		return

	var duration = 1.0 / NETWORK_FPS
	if (net_sync_timer < duration):
		net_sync_timer += delta
		return
	net_sync_timer = 0

	# send inputs
	cli_send_input()

	# apply inputs
	var tmp_buf = cli_recv_input_buffer
	cli_recv_input_buffer = []

	for buf in tmp_buf:
		var packet = buf.packet
		if packet.cli_id != cli_my_id:
			var input = packet.input
			if input.has("dir"):
				$Player.apply_input(input.dir)	


func cli_do_recv():
	while cli_peer.get_available_packet_count() > 0:
		var packet = cli_peer.get_var()
		#print("cli_do_recv, p: ", packet)
		if (packet == null):
			continue
		if packet.t == TT.g2c_gamestart:
			cli_on_g2c_gamestart(packet)
		elif packet.t == TT.g2c_obj_update:
			cli_on_g2c_obj_update(packet)
		elif packet.t == TT.g2c_cli_input:
			cli_on_g2c_cli_input(packet)


# warning-ignore:unused_argument
func cli_on_g2c_gamestart(packet):
	print("cli_on_g2c_gamestart")
	cli_game_start_time = Time.get_ticks_msec()
	

func cli_on_g2c_obj_update(packet):
	if (packet.seq > cli_seq):
		cli_seq = packet.seq
		for b in packet.balls:
			var ball = get_node("balls/" + b.name)
			ball.set_state(b)
		ctrl_player.set_state(packet.player)


func cli_on_g2c_cli_input(packet):
	for input in packet.inputs:
		cli_recv_input_buffer.append(input)


func cli_send_input():
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
				t = TT.c2g_input,
				cli_id = cli_my_id,
				input = {
					dir = dir,
				}
			}
			cli_peer.put_var(p)		
			print("cli_send_input, p: ", p)		

			# apply self
			$Player.apply_input(dir)
