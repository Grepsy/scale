# How the Mi Body Composition Scale 2 talks

The Mi Body Composition Scale 2 (model **XMTZC05HM**, Bluetooth name `MIBFS`) doesn't need
to be connected to anything to share a measurement. While someone is standing on it, it
**broadcasts every reading in its Bluetooth LE advertisements**, several times a second.
Zepp Life just listens to these broadcasts. It connects to the scale only for setup
(clock, units, user sync), which this app doesn't need.

This layout comes from community reverse engineering (openScale,
`lolouk44/xiaomi_mi_scale`, Home Assistant `xiaomi-ble`). `tools/miscale_sniff.py` lets you
check it against your own scale.

## Advertisement

The data is in the advertisement's **Service Data** field (AD type `0x16`) under the
16-bit UUID **`0x181B`** (Bluetooth SIG "Body Composition"). After the UUID come 13
bytes, little-endian:

| Byte | Field | Notes |
|-----:|-------|-------|
| 0 | control 0 | bit 0: unit is **lb** · bit 4: unit is **jin** · neither: **kg** |
| 1 | control 1 | bit 1: **impedance present** · bit 5: **stabilized** · bit 6: date invalid · bit 7: **weight removed** (stepped off) |
| 2–3 | year | uint16 |
| 4 | month | |
| 5 | day | |
| 6 | hour | |
| 7 | minute | |
| 8 | second | from the scale's clock, which Zepp Life sets |
| 9–10 | impedance | uint16, ohms. Valid only when bit 1 is set. Values ≥ 3000 are placeholders. |
| 11–12 | weight | uint16. **kg: value / 200** · lb and jin: value / 100 |

Example: `02 22 EA 07 09 1E 07 0F 00 F4 01 B0 36`
→ kg, stabilized, impedance present, 2026‑09‑30 07:15:00, 500 Ω, 0x36B0 / 200 = **70.00 kg**.

## A weigh-in, packet by packet

1. You step on. The scale sends packets with a changing weight and `stabilized = 0`.
2. The weight settles and `stabilized = 1`. The display stops moving.
3. If you're barefoot, a few seconds later the scale sends the same weight with
   `impedance present = 1` and the impedance in ohms. The measurement is done here.
4. You step off. For roughly 10–30 s the scale keeps repeating the final packet with
   `weight removed = 1`, then goes to sleep.

The app counts a weigh-in as complete at step 3. If you step off without an impedance
reading (socks or shoes), it counts step 4 instead and saves the weight only.
Repeats are ignored (`MeasurementTracker`).

## Body composition

The scale only measures **weight** and **impedance**. Zepp Life works out body fat, water,
muscle, bone, visceral fat and BMR on the phone from those two values plus your height, age
and sex. `BodyComposition.swift` ports the formulas the community reverse engineered from
Mi Fit / Zepp Life, the same ones openScale and the Home Assistant integration use. They
should come close to Zepp Life, but won't always match it to the decimal.

One oddity has been kept on purpose: the reverse-engineered visceral-fat formula clamps to 1
for women below roughly `0.5 × height − 13` kg. The app doesn't write visceral fat to Health.

## What goes into Apple Health

| Health type | Source |
|---|---|
| Weight (`bodyMass`) | every weigh-in |
| Body Mass Index | weight + profile height |
| Body Fat Percentage | needs impedance + profile |
| Lean Body Mass | weight × (1 − body fat) |

Health has no types for water %, muscle, bone or visceral fat, so the app keeps those
in its own history only. Each sample carries a `HKMetadataKeySyncIdentifier`, so saving
the same weigh-in twice replaces it instead of adding a duplicate.

The older **Mi Smart Scale 2** (XMTZC04HM, weight only) broadcasts on `0x181D` with a
different layout. It isn't supported.
