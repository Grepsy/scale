# Scale: Mi Body Composition Scale 2 → Apple Health, on your Apple Watch

A standalone watchOS app. Open it, step on the scale, and your weight, BMI, body fat % and
lean body mass are saved to Apple Health. You don't need Zepp Life or your phone.

It works because the scale broadcasts every reading over Bluetooth LE, and the app just
listens. [docs/PROTOCOL.md](docs/PROTOCOL.md) explains the reverse-engineered format.

## Using it

1. Open **Scale** on the watch and keep the screen awake. watchOS only allows Bluetooth
   scanning while the app is in the foreground.
2. Step on the scale **barefoot** and stay on until the display finishes its second pass
   (the body-composition measurement).
3. The watch taps when the weigh-in is complete. The result shows up and is saved to Health.

Swipe down for **History**, and again for **Settings**:
- **Profile:** height, birth year and sex. These are read from Health when you allow it, and
  body composition needs them. Until they're set, only weight is saved.
- **Save automatically:** turn off to get a *Save to Health* button instead.
- **Forget scale:** the app remembers the first scale it hears so a neighbour's scale can't
  log to your Health. Use this if you replace yours.

Several people can share the scale. Each person uses the app on their own watch with their
own profile.

## Building

You need a Mac with Xcode 15 or later, an Apple Watch on watchOS 10 or later, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen                 # creates MiScaleHealth.xcodeproj from project.yml
open MiScaleHealth.xcodeproj
```

In Xcode, pick your team under *Signing & Capabilities*. Change the bundle ID from
`com.example.MiScaleHealth` if needed. Then pick your watch as the run destination and run.
HealthKit and Bluetooth don't work in the simulator, so test on a real watch.

### Project layout

```
App/                 watchOS app (SwiftUI)
  ScaleScanner.swift    CoreBluetooth advertisement listener
  HealthKitManager.swift writes samples, reads height / birth date / sex
  AppModel.swift        state, profile, history, glue
  Views/                Weigh, History, Settings screens
MiScaleKit/          platform-independent Swift package
  ScaleAdvertisement    decodes the 0x181B service data
  MeasurementTracker    turns the packet stream into weigh-ins
  BodyComposition       Xiaomi body-composition formulas
tools/miscale_sniff.py   decode your scale's broadcasts from a Mac/PC (Python + bleak)
docs/PROTOCOL.md         how the scale works
```

### Tests

```sh
cd MiScaleKit && swift test          # Swift decoder, tracker and formula tests
python3 tools/miscale_sniff.py --selftest
```

### Check your own scale from a Mac

```sh
pip install bleak
python3 tools/miscale_sniff.py --height 180 --age 35 --sex male
```

Step on the scale and each broadcast is printed as it arrives. If the numbers don't match
your scale's display, the output shows the raw bytes to compare against the table in
PROTOCOL.md.
