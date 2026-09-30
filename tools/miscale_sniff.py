#!/usr/bin/env python3
"""Listen for Mi Body Composition Scale 2 broadcasts and decode them.

Reference implementation of the same decoding + body-composition math used by the
watch app (MiScaleKit). Handy for checking your scale from a Mac/PC:

    pip install bleak
    python3 tools/miscale_sniff.py --height 180 --age 35 --sex male

Step on the scale and watch the packets scroll by. Run with --selftest to check the
decoder without any Bluetooth hardware.
"""
import argparse
import asyncio
import struct

SERVICE_UUID = "0000181b-0000-1000-8000-00805f9b34fb"


def parse(data: bytes):
    if len(data) == 15 and data[:2] == b"\x1b\x18":
        data = data[2:]
    if len(data) != 13:
        return None
    c0, c1, year, month, day, hour, minute, second, imp, raw = struct.unpack("<BBHBBBBBHH", data)
    unit = "lb" if c0 & 0x01 else ("jin" if c0 & 0x10 else "kg")
    weight_kg = raw / 100 * 0.45359237 if unit == "lb" else raw / 200
    has_imp = bool(c1 & 0x02)
    return {
        "unit": unit,
        "raw": raw,
        "display_weight": raw / 200 if unit == "kg" else raw / 100,
        "weight_kg": weight_kg,
        "impedance": imp if has_imp and 0 < imp < 3000 else None,
        "stabilized": bool(c1 & 0x20),
        "removed": bool(c1 & 0x80),
        "timestamp": None if c1 & 0x40 else f"{year:04}-{month:02}-{day:02} {hour:02}:{minute:02}:{second:02}",
    }


def clamp(v, lo, hi):
    return min(max(v, lo), hi)


def composition(weight, height, age, sex, impedance):
    female = sex == "female"
    out = {"bmi": clamp(weight / (height / 100) ** 2, 10, 90)}
    if female:
        bmr = 864.6 + weight * 10.2036 - height * 0.39336 - age * 6.204
        bmr = 5000 if bmr > 2996 else bmr
    else:
        bmr = 877.8 + weight * 14.916 - height * 0.726 - age * 8.976
        bmr = 5000 if bmr > 2322 else bmr
    out["bmr"] = clamp(bmr, 500, 10000)
    if impedance is None:
        return out

    lbm = (height * 9.058 / 100) * (height / 100) + weight * 0.32 + 12.226
    lbm -= impedance * 0.0068 + age * 0.0542

    const = (9.25 if age <= 49 else 7.25) if female else 0.8
    coef = 1.0
    if not female and weight < 61:
        coef = 0.98
    elif female and weight > 60:
        coef = 0.96 * (1.03 if height > 160 else 1)
    elif female and weight < 50:
        coef = 1.02 * (1.03 if height > 160 else 1)
    fat = (1 - ((lbm - const) * coef) / weight) * 100
    fat = clamp(75 if fat > 63 else fat, 5, 75)

    water = (100 - fat) * 0.7
    wcoef = 1.02 if water <= 50 else 0.98
    if water * wcoef >= 65:
        water = 75
    water = clamp(water * wcoef, 35, 75)

    bone = ((0.245691014 if female else 0.18016894) - lbm * 0.05158) * -1
    bone += 0.1 if bone > 2.2 else -0.1
    if (female and bone > 5.1) or (not female and bone > 5.2):
        bone = 8
    bone = clamp(bone, 0.5, 8)

    muscle = weight - fat * 0.01 * weight - bone
    if (female and muscle >= 84) or (not female and muscle >= 93.5):
        muscle = 120
    muscle = clamp(muscle, 10, 120)

    if female:
        if weight > (13 - height * 0.5) * -1:
            sub = weight * 500 / ((height * 1.45 + height * 0.1158 * height) - 120)
            vfal = (sub - 6) + age * 0.07
        else:
            sub = 0.691 + height * -0.0024 + height * -0.0024
            vfal = ((height * 0.027 - sub * weight) * -1) + age * 0.07 - age
    else:
        if height < weight * 1.6:
            sub = ((height * 0.4) - (height * (height * 0.0826))) * -1
            vfal = ((weight * 305) / (sub + 48)) - 2.9 + age * 0.15
        else:
            sub = 0.765 + height * -0.0015
            vfal = ((height * 0.143 - weight * sub) * -1) + age * 0.15 - 5.0

    out.update(fat=fat, water=water, bone=bone, muscle=muscle, visceral=clamp(vfal, 1, 50),
               lean=weight * (1 - fat / 100))
    return out


def selftest():
    # kg, stabilized + impedance, 2026-09-30 07:15:00, 500 ohm, 70.00 kg
    r = parse(bytes.fromhex("0222ea07091e070f00f401b036"))
    assert r["weight_kg"] == 70.0 and r["impedance"] == 500 and r["stabilized"] and not r["removed"], r
    assert r["timestamp"] == "2026-09-30 07:15:00", r
    # same packet with the UUID prefix still attached
    assert parse(bytes.fromhex("1b180222ea07091e070f00f401b036")) == r
    # lb, not stabilized, 154.32 lb
    r = parse(bytes.fromhex("0300ea07091e070f000000483c"))
    assert r["unit"] == "lb" and abs(r["display_weight"] - 154.32) < 1e-9 and not r["stabilized"], r
    for args in [(80, 180, 35, "male", 500), (62, 165, 52, "female", 560), (70, 175, 30, "male", None)]:
        print(args, {k: round(v, 4) for k, v in composition(*args).items()})
    print("selftest ok")


async def sniff(args):
    from bleak import BleakScanner

    def on_adv(device, adv):
        data = adv.service_data.get(SERVICE_UUID)
        if not data:
            return
        r = parse(data)
        if not r:
            print(device.address, "unrecognised", data.hex())
            return
        line = f"{device.address} {data.hex()} {r['display_weight']:.2f}{r['unit']}"
        line += f" imp={r['impedance']} stable={r['stabilized']} removed={r['removed']} t={r['timestamp']}"
        print(line)
        if args.height and r["stabilized"] and r["impedance"]:
            c = composition(r["weight_kg"], args.height, args.age, args.sex, r["impedance"])
            print("   ", {k: round(v, 1) for k, v in c.items()})

    async with BleakScanner(on_adv):
        await asyncio.sleep(args.seconds)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--selftest", action="store_true")
    p.add_argument("--seconds", type=float, default=120)
    p.add_argument("--height", type=float, help="cm, enables body-composition output")
    p.add_argument("--age", type=int, default=35)
    p.add_argument("--sex", choices=["male", "female"], default="male")
    a = p.parse_args()
    selftest() if a.selftest else asyncio.run(sniff(a))
