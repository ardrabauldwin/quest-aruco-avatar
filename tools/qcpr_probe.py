"""Probe a Laerdal QCPR manikin from the PC and log its CPR data to CSV.

Uses the protocol in scripts/qcpr (qcpr_constants.gd, qcpr_packet.gd): finds the
manikin, lists its GATT services, authenticates on the CPRM channel and subscribes
to every notifying characteristic. Two files are written next to --out:
  <stem>_compressions.csv  one row per compression (opens in Excel)
  <stem>_raw.csv           every notification, decoded where known, plus raw hex

Run (manikin on, QCPR app disconnected):
  pip install bleak
  python tools/qcpr_probe.py                 # scan, pick the manikin, log until Ctrl+C
  python tools/qcpr_probe.py --list-only     # only print services
  python tools/qcpr_probe.py --address AA:BB:CC:DD:EE:FF
"""
import argparse
import asyncio
import csv
import struct
import time
from datetime import datetime
from pathlib import Path

from bleak import BleakClient, BleakScanner

EXT = "-d746-4092-84e7-dad34863fe4a"  # Laerdal vendor UUID suffix
SERVICE_CPRM_COMMAND = "00001001" + EXT
CHAR_CPRM_COMMAND = "00001002" + EXT
CHAR_CPRM_RESPONSE = "00001003" + EXT
CHAR_AUTH_COMMAND = "00001032" + EXT
CHAR_AUTH_RESPONSE = "00001033" + EXT
CPRM_AUTH_KEY = bytes([104, 0, 167, 241, 39, 91, 2, 145, 44, 237, 225, 53, 255, 154, 59, 202, 80, 98])
GET_BATTERY_LEVEL = 12
NAME_HINTS = ("anne", "qcpr", "laerdal", "cpr", "resusci", "manikin")

NAMES = {129: "LG_EPISODE_LIST", 140: "BATTERY", 176: "FIRMWARE", 177: "SERIAL", 178: "MODEL",
         192: "CP_WAVE", 193: "CP_EVENT", 194: "CP_RATE", 195: "CP_INACTIVITY", 208: "QS_DATA",
         224: "QF_INACTIVITY", 225: "QF_INCOMP_RELEASE", 226: "QF_COMP_SHALLOW",
         227: "QF_COMP_SLOW", 228: "QF_COMP_FAST", 232: "SC_SECURITY_CODE"}


def decode(frame: bytes) -> dict:
    """CPRM frame: [0] msg id, [1] sequence, [2..] little-endian parameters."""
    if len(frame) < 2:
        return {}
    msg, p = frame[0], frame[2:]
    out = {"msg_id": msg, "msg": NAMES.get(msg, "")}
    if msg == 192 and len(p) >= 5:
        out.update(session_ms=struct.unpack_from("<I", p)[0], depth_mm=p[4])
    elif msg == 193 and len(p) >= 10:
        start, peak, depth, stop, incomplete = struct.unpack_from("<IHBHB", p)
        out.update(session_ms=start, time_to_peak_ms=peak, depth_mm=depth,
                   time_to_stop_ms=stop, full_release=not incomplete)
    elif msg == 194 and len(p) >= 2:
        out.update(rate_bpm=struct.unpack_from("<H", p)[0])
    elif msg == 195 and len(p) >= 3:
        out.update(inactivity_ms=struct.unpack_from("<H", p)[0], level=p[2])
    elif msg == 140 and p:
        out.update(battery_percent=p[0])
    elif msg == 232 and p:
        out.update(authenticated=p[0] == 1)
    elif 224 <= msg <= 228 and len(p) >= 3:
        out.update(level=p[2] if msg == 224 else p[0])
    return out


async def find_manikin(seconds: float):
    print(f"Scanning {seconds:.0f} s ...")
    found = await BleakScanner.discover(timeout=seconds, return_adv=True)
    hits = []
    for dev, adv in found.values():
        name = (adv.local_name or dev.name or "")
        laerdal = any(u.lower().endswith(EXT) for u in adv.service_uuids)
        if laerdal or any(h in name.lower() for h in NAME_HINTS):
            hits.append((adv.rssi, dev, name, laerdal))
    for rssi, dev, name, laerdal in sorted(hits, key=lambda h: -h[0]):
        print(f"  {dev.address}  rssi={rssi}  name={name!r}  laerdal_service={laerdal}")
    return max(hits, key=lambda h: h[0])[1] if hits else None


async def run(args) -> None:
    address = args.address
    if not address:
        device = await find_manikin(args.scan)
        if device is None:
            print("No manikin found. Is it switched on and disconnected from the QCPR app?")
            return
        address = device.address
    print(f"Connecting to {address} ...")
    async with BleakClient(address, timeout=20.0) as client:
        notifying = []
        for service in client.services:
            print(f"service {service.uuid}  {service.description}")
            for char in service.characteristics:
                print(f"    char {char.uuid}  [{', '.join(char.properties)}]  {char.description}")
                if "notify" in char.properties or "indicate" in char.properties:
                    notifying.append(char.uuid)
        if args.list_only:
            return

        stem = Path(args.out or f"qcpr_{datetime.now():%Y%m%d_%H%M%S}")
        raw_file = open(f"{stem}_raw.csv", "w", newline="")
        comp_file = open(f"{stem}_compressions.csv", "w", newline="")
        raw = csv.writer(raw_file)
        raw.writerow(["pc_time_s", "characteristic", "msg_id", "msg", "decoded", "raw_hex"])
        comp = csv.writer(comp_file)
        comp.writerow(["pc_time_s", "session_ms", "depth_mm", "rate_bpm", "full_release",
                       "time_to_peak_ms", "time_to_stop_ms"])
        t0 = time.monotonic()
        last_rate = {"bpm": ""}

        def on_notify(char, data: bytearray) -> None:
            now = round(time.monotonic() - t0, 3)
            info = decode(bytes(data)) if char.uuid.lower().endswith(EXT) else {}
            fields = {k: v for k, v in info.items() if k not in ("msg_id", "msg")}
            raw.writerow([now, char.uuid, info.get("msg_id", ""), info.get("msg", ""), fields, data.hex()])
            if info.get("msg") == "CP_RATE":
                last_rate["bpm"] = info["rate_bpm"]
            if info.get("msg") == "CP_EVENT":
                comp.writerow([now, info["session_ms"], info["depth_mm"], last_rate["bpm"],
                               info["full_release"], info["time_to_peak_ms"], info["time_to_stop_ms"]])
                print(f"compression depth={info['depth_mm']} mm rate={last_rate['bpm']} "
                      f"full_release={info['full_release']}")
            elif info.get("msg") not in (None, "CP_WAVE"):
                print(f"{info.get('msg') or info.get('msg_id', '?')} {fields or data.hex()}")
            elif not info:
                print(f"{char.uuid} {data.hex()}")
            raw_file.flush()
            comp_file.flush()

        for uuid in notifying:
            try:
                await client.start_notify(uuid, on_notify)
            except Exception as error:  # some characteristics refuse without bonding
                print(f"cannot subscribe {uuid}: {error}")
        chars = {c.uuid.lower() for s in client.services for c in s.characteristics}
        if CHAR_AUTH_COMMAND in chars:
            print("Sending CPRM auth key ...")
            await client.write_gatt_char(CHAR_AUTH_COMMAND, CPRM_AUTH_KEY, response=True)
            await asyncio.sleep(1.0)
            if CHAR_CPRM_COMMAND in chars:
                await client.write_gatt_char(CHAR_CPRM_COMMAND, bytes([GET_BATTERY_LEVEL, 0]), response=True)
        else:
            print("No CPRM auth characteristic: logging raw notifications only.")
        print(f"Logging to {stem}_compressions.csv and {stem}_raw.csv - do CPR, Ctrl+C to stop.")
        try:
            while client.is_connected:
                await asyncio.sleep(0.5)
        finally:
            raw_file.close()
            comp_file.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--address", help="BLE address; default: scan and pick the strongest manikin")
    parser.add_argument("--scan", type=float, default=15.0, help="scan seconds")
    parser.add_argument("--list-only", action="store_true", help="print services and exit")
    parser.add_argument("--out", help="output file stem (default qcpr_<timestamp>)")
    try:
        asyncio.run(run(parser.parse_args()))
    except KeyboardInterrupt:
        print("Stopped.")


if __name__ == "__main__":
    main()
