extends "res://tests/suite.gd"
## The laptop bridge: the manikin's compressions arrive as UDP JSON datagrams from
## tools/qcpr_probe.py --udp, become compression events, and make the manikin "live" so
## hand-tracked strokes are not counted a second time (9 Nov 2026).
## The manager is driven by hand here (no scene tree), like tests/test_qcpr.gd does.

func run() -> Array[String]:
	failures.clear()
	var manager := NaretQcprManager.new()
	manager._setup_backends()
	var bridge: NaretQcprBridgeBackend = manager.bridge_backend
	check(bridge != null, "the manager creates the bridge backend")
	check(manager.active_backend == null, "without manikin data there is no active backend (the simulator is opt-in)")
	bridge.disconnect_device()
	var port := 48767
	check(bridge.start_listening(port), "the bridge listens on a UDP port")
	check(not manager.manikin_live(), "no manikin data yet: not live")
	var events: Array = []
	manager.compression_measured.connect(func(depth: float, rate: float, recoil: bool, quality: Dictionary):
		events.append({"depth": depth, "rate": rate, "recoil": recoil, "status": quality.get("depth_status", "")}))
	var sender := PacketPeerUDP.new()
	check(sender.set_dest_address("127.0.0.1", port) == OK, "test sender targets the bridge port")
	sender.put_packet(JSON.stringify({"type": "compression", "depth_mm": 28, "rate_bpm": 110, "full_release": true, "session_ms": 587654}).to_utf8_buffer())
	sender.put_packet("not json".to_utf8_buffer())
	sender.put_packet(JSON.stringify({"type": "compression", "depth_mm": 55, "rate_bpm": 105, "full_release": false}).to_utf8_buffer())
	var waited := 0
	while events.size() < 2 and waited < 100:
		OS.delay_msec(10)
		bridge.poll()
		waited += 1
	manager._process(0.0)
	check(manager.active_backend == bridge, "manikin packets make the bridge the active backend")
	check(manager.manikin_live(), "the manikin counts as live after a packet")
	check(events.size() == 2, "two compressions arrived, the malformed packet was ignored: " + str(events.size()))
	if events.size() == 2:
		check(is_equal_approx(events[0].depth, 28.0) and events[0].status == "shallow", "28 mm is shallow")
		check(is_equal_approx(events[1].depth, 55.0) and events[1].status == "good" and not events[1].recoil, "55 mm without full release keeps the recoil flag")
	check(bridge.get_backend_name().begins_with("QCPR via PC bridge"), "backend name says where the data comes from")
	bridge.disconnect_device()
	sender.close()
	for child in manager.get_children():
		child.free()
	manager.free()
	return failures
