"""Run a CPR session on a Laerdal QCPR manikin from the PC and log it to CSV.

Protocol taken from an iOS Bluetooth capture of the QCPR app (2026-11-02,
manikin serial 250318-0112) and checked against the manikin from Windows:

  login        write MANIKIN_AUTH_KEY (scripts/qcpr/qcpr_constants.gd) to 01b1;
               01b2 then reads 0x55
  subscribe    0127 (indicate), 0027 0028 0030 01a1 0131 005a (notify)
  prepare      012b = 01, 0254 = 01
  start        0127 = <session id> 1e 02   (the app used 03 and 04; 1e 02 = 30:2)
  stop         0127 = 00 00 00; 0131 then carries a summary, 0127 indicates ff 00 00

  0027  live depth:   u32 session ms, u8 depth mm               (~20 per second)
  0028  compression:  u32 session ms, u16 ms, u8 max depth mm, u16 ms, u8 rate/min, u16 flags
  0030  u16 counter, about once per second
  01a1  4 bytes state (04 02 00 00 while pressing, 04 00 00 00 after)
  0131  20 bytes session summary, not decoded yet
  005a  ventilation, no samples captured yet

Output next to --out:
  <stem>_compressions.csv  one row per compression (opens in Excel)
  <stem>_raw.csv           every notification as hex
Both carry unix_ms (PC wall clock) so they can be lined up with headset logs.

Run (manikin on, phone Bluetooth off so the QCPR app does not hold the manikin):
  pip install bleak
  python tools/qcpr_probe.py                       # scan, run a session until Ctrl+C
  python tools/qcpr_probe.py --seconds 120
  python tools/qcpr_probe.py --list-only           # only print services
  python tools/qcpr_probe.py --address ED:A2:2F:5E:4B:25
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
LAERDAL_COMPANY_ID = 458
MANIKIN_AUTH_KEY = bytes([92, 14, 185, 190, 3, 210, 96, 9, 109, 62, 31, 12, 128, 38, 200, 16, 115, 205, 46, 162])
AUTH_OK = 0x55
NOTIFY = ["00000127", "00000027", "00000028", "00000030", "000001a1", "00000131", "0050005a"]


def uuid(short: str) -> str:
    return short + EXT


def decode_compression(data: bytes) -> dict:
    """0028: one finished compression."""
    session_ms, first_ms, depth_mm, second_ms, rate = struct.unpack_from("<IHBHB", data)
    return {"session_ms": session_ms, "depth_mm": depth_mm, "rate_bpm": rate,
            "field_a_ms": first_ms, "field_b_ms": second_ms, "flags": data[10:12].hex()}


async def find_manikin(seconds: float):
    """The strongest Laerdal device that offers the session service is the manikin."""
    print(f"Scanning {seconds:.0f} s ...")
    found = await BleakScanner.discover(timeout=seconds, return_adv=True)
    laerdal = [(adv.rssi, dev, adv) for dev, adv in found.values() if LAERDAL_COMPANY_ID in adv.manufacturer_data]
    for rssi, dev, adv in sorted(laerdal, key=lambda h: -h[0]):
        serial = adv.manufacturer_data[LAERDAL_COMPANY_ID][2:].decode("ascii", "replace")
        print(f"  {dev.address}  rssi={rssi}  name={adv.local_name!r}  serial={serial}")
    for _, dev, _ in sorted(laerdal, key=lambda h: -h[0]):
        async with BleakClient(dev, timeout=20.0) as client:
            if any(s.uuid == uuid("00000126") for s in client.services):
                return dev
    return None


async def run(args) -> None:
    device = await BleakScanner.find_device_by_address(args.address, timeout=20.0) if args.address \
        else await find_manikin(args.scan)
    if device is None:
        print("No manikin found. Is the QCPR module on (blue blinking) and the phone's Bluetooth off?")
        return
    print(f"Connecting to {device.address} ...")
    async with BleakClient(device, timeout=20.0) as client:
        if args.list_only:
            for service in client.services:
                print(f"service {service.uuid}")
                for char in service.characteristics:
                    print(f"    char {char.uuid}  [{', '.join(char.properties)}]")
            return
        await client.write_gatt_char(uuid("000001b1"), MANIKIN_AUTH_KEY, response=True)
        auth = await client.read_gatt_char(uuid("000001b2"))
        if not auth or auth[0] != AUTH_OK:
            print(f"Login refused ({auth.hex()}).")
            return

        stem = Path(args.out or f"qcpr_{datetime.now():%Y%m%d_%H%M%S}")
        raw_file = open(f"{stem}_raw.csv", "w", newline="")
        comp_file = open(f"{stem}_compressions.csv", "w", newline="")
        raw = csv.writer(raw_file)
        raw.writerow(["unix_ms", "pc_time_s", "characteristic", "raw_hex"])
        comp = csv.writer(comp_file)
        comp.writerow(["number", "unix_ms", "local_time", "pc_time_s", "session_ms", "depth_mm", "rate_bpm", "depth_ok_50_60",
                       "rate_ok_100_120", "field_a_ms", "field_b_ms", "flags"])
        t0 = time.monotonic()
        count = [0]

        def on_notify(char, data: bytearray) -> None:
            now = round(time.monotonic() - t0, 3)
            unix_ms = int(time.time() * 1000)  # wall clock, to line up with other recordings
            short = char.uuid[4:8]
            raw.writerow([unix_ms, now, short, data.hex()])
            if short == "0028" and len(data) >= 10:
                c = decode_compression(bytes(data))
                count[0] += 1
                comp.writerow([count[0], unix_ms, datetime.fromtimestamp(unix_ms / 1000).strftime("%H:%M:%S.%f")[:-3],
                               now, c["session_ms"], c["depth_mm"], c["rate_bpm"],
                               50 <= c["depth_mm"] <= 60, 100 <= c["rate_bpm"] <= 120,
                               c["field_a_ms"], c["field_b_ms"], c["flags"]])
                print(f"compression {count[0]:3}  depth {c['depth_mm']:3} mm  rate {c['rate_bpm']:3}/min")
            elif short in ("0131", "005a", "0127"):
                print(f"{short} {data.hex()}")
            raw_file.flush()
            comp_file.flush()

        for short in NOTIFY:
            await client.start_notify(uuid(short), on_notify)
        await client.write_gatt_char(uuid("0000012b"), b"\x01", response=True)
        await client.write_gatt_char(uuid("00000254"), b"\x01", response=True)
        await client.write_gatt_char(uuid("00000127"), bytes([args.session_id, 0x1E, 0x02]), response=True)
        print(f"Session started. Logging to {stem}_compressions.csv - do CPR"
              + (f" ({args.seconds:.0f} s)." if args.seconds else ", Ctrl+C to stop."))
        try:
            end = time.monotonic() + args.seconds if args.seconds else None
            while client.is_connected and (end is None or time.monotonic() < end):
                await asyncio.sleep(0.2)
        finally:
            if client.is_connected:
                await client.write_gatt_char(uuid("00000127"), b"\x00\x00\x00", response=True)
                await asyncio.sleep(2.0)  # the summary (0131) follows the stop
            raw_file.close()
            comp_file.close()
            print(f"Session stopped after {count[0]} compressions.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--address", help="BLE address; default: scan for the manikin")
    parser.add_argument("--scan", type=float, default=15.0, help="scan seconds")
    parser.add_argument("--seconds", type=float, default=0.0, help="session length; 0 = until Ctrl+C")
    parser.add_argument("--session-id", type=int, default=3, help="first byte of the start command")
    parser.add_argument("--list-only", action="store_true", help="print services and exit")
    parser.add_argument("--out", help="output file stem (default qcpr_<timestamp>)")
    try:
        asyncio.run(run(parser.parse_args()))
    except KeyboardInterrupt:
        print("Stopped.")


if __name__ == "__main__":
    main()
