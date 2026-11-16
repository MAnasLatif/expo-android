# expoemu workflows

Recipes for common testing tasks. Each one assumes `expoemu status`
exits 0 (run `expoemu up --no-animations` first if it doesn't).

## Contents

- [Verify a code change](#verify-a-code-change)
- [Test a form or login flow](#test-a-form-or-login-flow)
- [Navigate long screens and lists](#navigate-long-screens-and-lists)
- [Debug a red screen or crash](#debug-a-red-screen-or-crash)
- [Start from a fresh install](#start-from-a-fresh-install)
- [Offline and flaky network](#offline-and-flaky-network) (incl. slow 2G/3G)
- [Dark mode, large text, rotation, RTL](#dark-mode-large-text-rotation-rtl)
- [OTP codes, calls and fingerprint login](#otp-codes-calls-and-fingerprint-login)
- [Permissions](#permissions)
- [Deep links](#deep-links)
- [Accessibility check](#accessibility-check)
- [Performance check](#performance-check)
- [Phone and tablet side by side](#phone-and-tablet-side-by-side)
- [Two users at once (chat, multiplayer)](#two-users-at-once-chat-multiplayer)
- [Record a bug for a report](#record-a-bug-for-a-report)

## Verify a code change

```bash
# after editing the code; Fast Refresh applies it in a few seconds
expoemu wait-for "New button label" --timeout 15
expoemu logcat --errors -n 30
expoemu screenshot after-change      # Read the printed PNG
```

If the screen still shows old code: `expoemu open` (fresh bundle), then wait again.
If Metro failed to bundle: `expoemu expo --logs`.

## Test a form or login flow

```bash
expoemu fill "Email" "ada@example.com"
expoemu fill "Password" "correct horse"
expoemu tap-text "Sign in"
expoemu wait-for "Welcome" --timeout 20
expoemu assert-no-text "Invalid"
expoemu screenshot logged-in
```

Negative case: fill a wrong password, tap, then
`expoemu wait-for "Invalid password"`.

## Navigate long screens and lists

```bash
expoemu scroll-to "Settings"          # scrolls down until visible
expoemu tap-text "Settings"
expoemu scroll-to "Account" --up      # back up
expoemu back                          # Android back
```

`scroll` works inside the largest scroll view. For horizontal carousels use
`scroll left|right`.

## Debug a red screen or crash

```bash
expoemu screenshot red-screen
expoemu logcat -n 100                 # JS stack under ReactNativeJS
expoemu crash                         # native crashes
expoemu expo --logs                   # bundling errors
```

Fix the code, then `expoemu reload` or `expoemu open`.

## Start from a fresh install

```bash
expoemu app clear      # wipes AsyncStorage, SecureStore, permissions; reopens the project
expoemu wait-for "Get started" --timeout 30
```

## Offline and flaky network

```bash
expoemu network off                   # app offline; Metro still works over adb
expoemu tap-text "Refresh"
expoemu wait-for "No connection"
expoemu network on                    # always restore
expoemu wait-for "Latest posts" --timeout 20
```

`expoemu airplane on|off` tests the airplane-mode path.

Slow connections (loading states, timeouts, retries):

```bash
expoemu network edge                      # ~470 kbit/s, 80–400 ms latency (also: gprs, 3g, 4g)
expoemu tap-text "Refresh"
expoemu screenshot slow-loading           # spinner / skeleton visible?
expoemu wait-for "Latest posts" --timeout 60
expoemu network full                      # always restore
```

## Dark mode, large text, rotation, RTL

```bash
expoemu dark-mode on && expoemu screenshot dark && expoemu dark-mode off
expoemu font-scale 1.3 && expoemu screenshot large-text && expoemu font-scale reset
expoemu rotate landscape && expoemu screenshot landscape && expoemu rotate portrait
expoemu locale ar && expoemu open && expoemu screenshot rtl
expoemu locale reset && expoemu open
```

Rotation does nothing if `app.json` sets `"orientation": "portrait"`.

## OTP codes, calls and fingerprint login

```bash
# SMS one-time code
expoemu tap-text "Send code"
expoemu sms 5551234 "Your verification code is 482913"
expoemu fill "Code" "482913"              # or check the app auto-reads it

# Incoming call while the app is open (interruption handling)
expoemu call 5559876
expoemu screenshot during-call
expoemu call end 5559876

# Fingerprint (expo-local-authentication)
expoemu biometric enroll                  # once per device; sets test PIN 1234
expoemu tap-text "Log in with fingerprint"
expoemu biometric fail                    # wrong finger → error state
expoemu biometric touch                   # right finger → success
expoemu wait-for "Welcome"
expoemu biometric reset                   # remove PIN + fingerprint when done
```

These need an emulator; on a physical phone use the real SIM and sensor.

## Permissions

```bash
expoemu permission revoke CAMERA      # test the "denied" path
expoemu tap-text "Scan"
expoemu wait-for "Camera access needed"
expoemu permission grant CAMERA       # test the "granted" path
expoemu permission list
```

## Deep links

```bash
expoemu open-url "myapp://profile/42"
expoemu wait-for "Profile" --timeout 15
```

In Expo Go, links use the `exp://127.0.0.1:8081/--/path` form:
`expoemu open-url "exp://127.0.0.1:8081/--/profile/42"`.

## Accessibility check

```bash
expoemu a11y            # exit 1 if a button/input has no accessible name
expoemu a11y --all      # also list clickables without a testID
```

Fix `ERROR unlabeled` by adding `accessibilityLabel` (icons) or visible text.
For `WARN small`, raise the touch target to 48×48dp (`hitSlop` or padding).
Re-run after Fast Refresh, and check every screen of the flow.

## Performance check

```bash
expoemu animations on                 # measure with real animations
expoemu perf --reset
expoemu scroll down && expoemu scroll down && expoemu scroll up
expoemu perf                          # jank %, frame-time percentiles
expoemu memory
```

Emulator numbers are relative. Compare before and after a change rather than
reading absolute values.

## Phone and tablet side by side

```bash
expoemu device create tablet --profile tablet      # once
expoemu emulator start --device tablet
expoemu open --all
expoemu screenshot --all layout                    # one PNG per device
expoemu ui --device tablet                         # tablet coordinates differ
expoemu emulator stop --device tablet
```

## Two users at once (chat, multiplayer)

```bash
expoemu device create user2 --profile phone        # once
expoemu emulator start --device user2
expoemu open --all
expoemu fill "Message" "Hi from A" --device default
expoemu tap-text "Send" --device default
expoemu wait-for "Hi from A" --timeout 20 --device user2
```

## Record a bug for a report

```bash
expoemu record 20 bug-repro &         # records for 20 s in the background
expoemu tap-text "Checkout"
expoemu tap-text "Pay"
wait                                      # prints the MP4 path when done
```
