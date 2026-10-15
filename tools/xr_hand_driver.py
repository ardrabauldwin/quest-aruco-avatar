#!/usr/bin/env python3
"""Steers the Meta XR Simulator's simulated hands towards goals streamed by
tools/record_xr_scenario.gd (UDP JSON: hand "left"/"right"/"both", gesture,
effector position `at`, `goal`; `palm_y` with `palm_down` turns the palms to the
floor first; mode "pump" pushes both hands up and down at `rate` per minute).

The simulator has no "set hand pose" call; its gRPC input API moves a hand the
way a person does at the keyboard (W/S/A/D/R/F at a chosen speed) and switches
the hand gesture (Num1 default, Num2 poke, Num3 pinch, Num4 grab). This is a
proportional controller on top of that. The proto schema is not shipped as
files, so it is recovered once from SIMULATOR.so's embedded descriptors.
Needs grpcio + protobuf:  python tools/xr_hand_driver.py <sim-grpc-port>
"""
from __future__ import annotations

import json
import re
import socket
import sys
import time
from pathlib import Path

import grpc
from google.protobuf import descriptor_pb2, descriptor_pool, empty_pb2, message_factory

SIM = Path("/Applications/MetaXRSimulator.app/Contents/Resources/MetaXRSimulator/SIMULATOR.so")
CACHE = Path(__file__).resolve().parents[1] / "build/xrsim_proto"
P = "openxr_simulator.rpc.proto."
GESTURE_KEY = {"default": "Num1", "poke": "Num2", "pinch": "Num3", "grab": "Num4"}
# Hand motion in the simulator's frame with the headset facing -Z (never turned here).
AXIS_KEYS = [("D", "A"), ("R", "F"), ("S", "W")]


def descriptors() -> list[descriptor_pb2.FileDescriptorProto]:
    if not CACHE.exists():
        CACHE.mkdir(parents=True)
        data = SIM.read_bytes()
        for m in re.finditer(rb"\x0a([\x01-\x7f])(arvr/projects/openxr_simulator/protocol/[a-z_]+\.proto)", data):
            if len(m.group(2)) != m.group(1)[0]:
                continue
            best = None
            # The serialized FileDescriptorProto has no end marker: keep the longest parse.
            for end in range(m.start() + 40, min(len(data), m.start() + 60000)):
                fd = descriptor_pb2.FileDescriptorProto()
                try:
                    fd.ParseFromString(data[m.start():end])
                except Exception:
                    continue
                if fd.package and (fd.message_type or fd.service):
                    best = fd
            if best is not None:
                (CACHE / (best.name.rsplit("/", 1)[1] + ".pb")).write_bytes(best.SerializeToString())
    files = []
    for path in CACHE.glob("*.pb"):
        fd = descriptor_pb2.FileDescriptorProto()
        fd.ParseFromString(path.read_bytes())
        files.append(fd)
    return files


class Simulator:
    def __init__(self, address: str):
        self.pool = descriptor_pool.DescriptorPool()
        pending = {fd.name: fd for fd in descriptors()}
        empty = descriptor_pb2.FileDescriptorProto()
        empty_pb2.DESCRIPTOR.CopyToProto(empty)
        pending[empty.name] = empty
        added: set[str] = set()

        def add(name: str) -> None:
            if name in added:
                return
            for dep in pending[name].dependency:
                add(dep)
            self.pool.Add(pending[name])
            added.add(name)
        for name in list(pending):
            add(name)
        self.channel = grpc.insecure_channel(address)
        self.keys = self.pool.FindEnumTypeByName(P + "KeyboardKey").values_by_name

    def call(self, service: str, method: str, **fields):
        descriptor = self.pool.FindServiceByName(P + service).methods_by_name[method]
        request = message_factory.GetMessageClass(descriptor.input_type)(**fields)
        response = message_factory.GetMessageClass(descriptor.output_type)
        stub = self.channel.unary_unary(f"/{P}{service}/{method}", request_serializer=lambda m: m.SerializeToString(),
            response_deserializer=response.FromString)
        return stub(request, timeout=5)

    def press(self, keys: list[str]) -> None:
        self.call("Input", "SendKey", keys_down=[self.keys[k].number for k in keys])

    def control(self, hand: str, speed: float) -> None:
        self.call("Input", "SetInputPluginSettings", movement_speed=speed, left_controller_active=hand in ("left", "both"),
            right_controller_active=hand in ("right", "both"), headset_active=hand == "head", dolly_scroll_speed=10)


def pump(sim: Simulator, state: dict, udp: socket.socket) -> dict:
    """Chest compressions: open-loop strokes at the given rate, the top of each
    stroke pulled back to `top` so the hands do not drift. Returns the packet
    that ended the mode."""
    half = 30.0 / state.get("rate", 110)
    depth = state.get("depth", 0.055)
    sim.control("both", depth / half)
    up_extra = 0.0
    while True:
        sim.press(["F"])
        time.sleep(half)
        sim.press(["R"])
        time.sleep(max(0.05, half + up_extra))
        sim.press([])
        latest = newest(udp)
        if latest is None:
            continue
        if latest.get("mode") != "pump" or latest.get("done"):
            return latest
        if latest.get("at") is not None:
            # Positive: the hands ended the stroke below the chest surface.
            up_extra = max(-0.08, min(0.08, (latest["top"] - latest["at"][1]) / (depth / half)))


def newest(udp: socket.socket) -> dict | None:
    """Drain the socket; only the newest state matters."""
    latest = None
    udp.setblocking(False)
    while True:
        try:
            latest = json.loads(udp.recvfrom(65536)[0])
        except BlockingIOError:
            break
    udp.settimeout(0.5)
    return latest


def main() -> None:
    sim = Simulator(f"[::1]:{sys.argv[1]}")
    for hand in (0, 1):
        sim.call("Input", "SetInputSource", handType=hand, inputSource=1)  # simulated hands, not controllers
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind(("127.0.0.1", 47011))
    udp.settimeout(0.5)
    active, speed, gestures, tap = "", -1.0, {}, []
    while True:
        try:
            state = json.loads(udp.recvfrom(65536)[0])
        except socket.timeout:
            continue
        state = newest(udp) or state
        while state.get("mode") == "pump" and not state.get("done"):
            state = pump(sim, state, udp)
            active, speed = "both", -1.0
        if state.get("done"):
            sim.press([])
            print("DRIVER done", flush=True)
            return
        hand = state.get("hand", "")
        if not hand or state.get("at") is None:
            sim.press([])
            continue
        if state.get("palm_down") and state.get("palm_y", -1.0) > -0.88:
            # Turn the palm(s) towards the floor before moving (arrow down pitches the hand).
            if active != hand or speed != 0.6:
                active, speed = hand, 0.6
                sim.control(hand, speed)
            sim.press(["DownArrow"])
            time.sleep(0.02)
            continue
        error = [g - a for g, a in zip(state["goal"], state["at"])]
        distance = sum(e * e for e in error) ** 0.5
        wanted = max(0.03, min(0.55, distance * 2.2))
        if hand != active or abs(wanted - speed) > 0.2 * speed:
            sim.press([])
            active, speed = hand, wanted
            sim.control(hand, speed)
        keys = []
        for e, (plus, minus) in zip(error, AXIS_KEYS):
            if abs(e) > max(0.003, 0.3 * distance):
                keys.append(plus if e > 0 else minus)
        gesture = state.get("gesture", "default")
        if gestures.get(hand) != gesture:
            gestures[hand] = gesture
            tap = [GESTURE_KEY[gesture]] * 4
        if tap:
            keys = [tap.pop()]  # a gesture key alone, so it is not read as a move chord
        sim.press(keys)
        time.sleep(0.02)


if __name__ == "__main__":
    main()
