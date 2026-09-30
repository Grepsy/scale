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

### Smart Stack widget

Add the widget and you can open the app with one tap instead of hunting for it:
turn the Digital Crown to open the Smart Stack, touch and hold, tap **+**, and choose
**Scale**. It also works as a complication on watch faces with circular, corner,
inline or rectangular slots. It shows your last weight and body fat. After a few
weigh-ins, the watch also moves it up the stack around the time you usually weigh
yourself (unless you already have that day).

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

In Xcode, pick your team under *Signing & Capabilities* for both the **MiScaleHealth**
and **ScaleWidget** targets. To use your own bundle ID, change `APP_BUNDLE_ID` in
`project.yml` and re-run `xcodegen`. The widget ID and the shared app group follow it. Then pick your watch as the run destination and run.
HealthKit and Bluetooth don't work in the simulator, so test on a real watch.

### Project layout

```
App/                 watchOS app (SwiftUI)
  ScaleScanner.swift    CoreBluetooth advertisement listener
  HealthKitManager.swift writes samples, reads height / birth date / sex
  AppModel.swift        state, profile, history, glue
  Views/                Weigh, History, Settings screens
Widget/              Smart Stack / complication widget (WidgetKit)
MiScaleKit/          platform-independent Swift package
  ScaleAdvertisement    decodes the 0x181B service data
  MeasurementTracker    turns the packet stream into weigh-ins
  BodyComposition       Xiaomi body-composition formulas
  WidgetSnapshot        data shared with the widget, usual-weigh-in-time logic
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
