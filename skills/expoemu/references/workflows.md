# expoemu workflows

Recipes for common testing tasks. Each one assumes `npx expoemu status`
exits 0 (run `npx expoemu up --no-animations` first if it doesn't).

## Contents

- [Verify a code change](#verify-a-code-change)
- [Test a form or login flow](#test-a-form-or-login-flow)
- [Navigate long screens and lists](#navigate-long-screens-and-lists)
- [Debug a red screen or crash](#debug-a-red-screen-or-crash)
- [Start from a fresh install](#start-from-a-fresh-install)
- [Offline and flaky network](#offline-and-flaky-network)
- [Dark mode, large text, rotation, RTL](#dark-mode-large-text-rotation-rtl)
- [Permissions](#permissions)
- [Deep links](#deep-links)
- [Performance check](#performance-check)
- [Phone and tablet side by side](#phone-and-tablet-side-by-side)
- [Two users at once (chat, multiplayer)](#two-users-at-once-chat-multiplayer)
- [Record a bug for a report](#record-a-bug-for-a-report)

## Verify a code change

```bash
# after editing the code; Fast Refresh applies it in a few seconds
npx expoemu wait-for "New button label" --timeout 15
npx expoemu logcat --errors -n 30
npx expoemu screenshot after-change      # Read the printed PNG
```

If the screen still shows old code: `npx expoemu open` (fresh bundle), then wait again.
If Metro failed to bundle: `npx expoemu expo --logs`.

## Test a form or login flow

```bash
npx expoemu fill "Email" "ada@example.com"
npx expoemu fill "Password" "correct horse"
npx expoemu tap-text "Sign in"
npx expoemu wait-for "Welcome" --timeout 20
npx expoemu assert-no-text "Invalid"
npx expoemu screenshot logged-in
```

Negative case: fill a wrong password, tap, then
`npx expoemu wait-for "Invalid password"`.

## Navigate long screens and lists

```bash
npx expoemu scroll-to "Settings"          # scrolls down until visible
npx expoemu tap-text "Settings"
npx expoemu scroll-to "Account" --up      # back up
npx expoemu back                          # Android back
```

`scroll` works inside the largest scroll view. For horizontal carousels use
`scroll left|right`.

## Debug a red screen or crash

```bash
npx expoemu screenshot red-screen
npx expoemu logcat -n 100                 # JS stack under ReactNativeJS
npx expoemu crash                         # native crashes
npx expoemu expo --logs                   # bundling errors
```

Fix the code, then `npx expoemu reload` or `npx expoemu open`.

## Start from a fresh install

```bash
npx expoemu app clear      # wipes AsyncStorage, SecureStore, permissions; reopens the project
npx expoemu wait-for "Get started" --timeout 30
```

## Offline and flaky network

```bash
npx expoemu network off                   # app offline; Metro still works over adb
npx expoemu tap-text "Refresh"
npx expoemu wait-for "No connection"
npx expoemu network on                    # always restore
npx expoemu wait-for "Latest posts" --timeout 20
```

`npx expoemu airplane on|off` tests the airplane-mode path.

## Dark mode, large text, rotation, RTL

```bash
npx expoemu dark-mode on && npx expoemu screenshot dark && npx expoemu dark-mode off
npx expoemu font-scale 1.3 && npx expoemu screenshot large-text && npx expoemu font-scale reset
npx expoemu rotate landscape && npx expoemu screenshot landscape && npx expoemu rotate portrait
npx expoemu locale ar && npx expoemu open && npx expoemu screenshot rtl
npx expoemu locale reset && npx expoemu open
```

Rotation does nothing if `app.json` sets `"orientation": "portrait"`.

## Permissions

```bash
npx expoemu permission revoke CAMERA      # test the "denied" path
npx expoemu tap-text "Scan"
npx expoemu wait-for "Camera access needed"
npx expoemu permission grant CAMERA       # test the "granted" path
npx expoemu permission list
```

## Deep links

```bash
npx expoemu open-url "myapp://profile/42"
npx expoemu wait-for "Profile" --timeout 15
```

In Expo Go, links use the `exp://127.0.0.1:8081/--/path` form:
`npx expoemu open-url "exp://127.0.0.1:8081/--/profile/42"`.

## Performance check

```bash
npx expoemu animations on                 # measure with real animations
npx expoemu perf --reset
npx expoemu scroll down && npx expoemu scroll down && npx expoemu scroll up
npx expoemu perf                          # jank %, frame-time percentiles
npx expoemu memory
```

Emulator numbers are relative. Compare before and after a change rather than
reading absolute values.

## Phone and tablet side by side

```bash
npx expoemu device create tablet --profile tablet      # once
npx expoemu emulator start --device tablet
npx expoemu open --all
npx expoemu screenshot --all layout                    # one PNG per device
npx expoemu ui --device tablet                         # tablet coordinates differ
npx expoemu emulator stop --device tablet
```

## Two users at once (chat, multiplayer)

```bash
npx expoemu device create user2 --profile phone        # once
npx expoemu emulator start --device user2
npx expoemu open --all
npx expoemu fill "Message" "Hi from A" --device default
npx expoemu tap-text "Send" --device default
npx expoemu wait-for "Hi from A" --timeout 20 --device user2
```

## Record a bug for a report

```bash
npx expoemu record 20 bug-repro &         # records for 20 s in the background
npx expoemu tap-text "Checkout"
npx expoemu tap-text "Pay"
wait                                      # prints the MP4 path when done
```
