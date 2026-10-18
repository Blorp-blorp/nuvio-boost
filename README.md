<p align="center"><img src="assets/nuvio-boost-social-preview.png" alt="Nuvio Boost" width="640"></p>

# Nuvio Boost

**Make sideloaded Nuvio run as smoothly as the Play Store version, and keep it that way with one command after every update.**

Works on Android TV, Google TV, Nvidia Shield and Fire TV. Run it from a Mac, Windows or Linux computer.

---

## How it works

| | What you do | Time |
|---|---|---|
| **First time** | Paste one command, type your TV's IP address | About 2 minutes |
| **After every Nuvio update** | Type `nuvioboost` and press **Enter** | About a minute per TV |

That's it. On the first run, Nuvio Boost remembers your TVs and adds a `nuvioboost` shortcut to your computer. After that, one word re-applies the fix on every TV you have.

---

## The command

**Mac or Linux** (open Terminal):

```
curl -fsSL https://raw.githubusercontent.com/Blorp-blorp/nuvio-boost/main/run.sh | bash
```

**Windows** (open PowerShell):

```
irm https://raw.githubusercontent.com/Blorp-blorp/nuvio-boost/main/run.ps1 | iex
```

You only need to paste this once. After that, use the `nuvioboost` shortcut.

---

## Using it

### First time
1. Turn on debugging on your TV (steps below).
2. Paste the command into Terminal (Mac) or PowerShell (Windows).
3. Type your TV's IP address and press Enter. More than one TV? Type them all, separated by spaces.
4. Accept the popup on your TV.
5. Press Enter when it offers to create the `nuvioboost` shortcut.

### After every Nuvio update
Open Terminal (Mac) or PowerShell (Windows) and type:

```
nuvioboost
```

Done. Every TV you set up is boosted again.

---

## Before your first run (once per TV)

Turn on debugging on your TV and note its IP address. Your computer and TV must be on the same network.

<details>
<summary><b>Android TV / Nvidia Shield</b></summary>

1. Settings > Device Preferences > About > click **Build** 7 times.
2. Settings > Device Preferences > Developer options > turn on **Network debugging** (or USB debugging).
3. Find the IP address under Settings > Network & Internet.
</details>

<details>
<summary><b>Newer Google TV</b> (Chromecast with Google TV, recent Sony / TCL / Hisense)</summary>

1. Settings > System > About > click **Android TV OS build** 7 times.
2. Settings > System > Developer options > turn on **Wireless debugging**.
3. When the script asks, answer **y** to the Wireless debugging question. It walks you through a one-time pairing code.
</details>

<details>
<summary><b>Fire TV</b></summary>

1. Settings > My Fire TV > About > click your device name 7 times.
2. My Fire TV > Developer options > turn on **ADB debugging**.
3. Find the IP address under My Fire TV > About > Network.
</details>

The first time you connect, **look at your TV** and accept the "Allow debugging?" popup, ticking **Always allow from this computer**. You won't be asked again.

---

## Why sideloaded Nuvio feels slow

Play Store installs come with performance profiles that let Android compile the app ahead of time. Sideloaded APKs skip that, so you get slow starts, stuttery menus and laggy posters.

Nuvio Boost tells your TV to fully compile Nuvio up front. Settings, logins and trailers aren't touched, and it uses about 30–60 MB of extra storage. Each Nuvio update replaces the compiled code, which is why you re-run it after updating.

---

## Why use this instead of the manual steps?

- **Re-applying is one word:** `nuvioboost`. No IPs to look up, no commands to remember.
- **No setup needed.** If you don't have adb, it downloads Google's official tools into its own folder.
- **Mac, Windows and Linux.** Most guides only cover Windows.
- **All your TVs in one go.**
- **Plain-English errors** instead of cryptic adb messages.
- **Finds Nuvio automatically**, including beta builds.

Already happy with ATVTools? No need to switch.

---

<details>
<summary><b>Troubleshooting</b></summary>

| Message | Fix |
|---|---|
| `Operation not permitted` (Mac) | System Settings > Privacy & Security > Local Network > turn on your Terminal app. Quit and reopen Terminal, then run again. |
| `Connection refused` | Debugging is off on the TV, or the IP is wrong. Newer Google TVs: answer **y** to the Wireless debugging question. |
| Stuck waiting / not authorized | Accept the popup on the TV. If you missed it, run again. |
| `Nuvio isn't installed` | Make sure Nuvio is installed on that TV. |
| Windows Defender blocked `nuvioboost` | Fixed in the current version. Re-run the setup command once and it replaces the old shortcut. |
| `nuvioboost: command not found` | Open a new Terminal window; the shortcut only works in windows opened after it was created. |
| A saved TV stopped working | Its IP probably changed. Type the new IP instead of pressing Enter. To stop it happening, set a DHCP reservation for the TV in your router. |
| Windows: "running scripts is disabled" | Run `Set-ExecutionPolicy -Scope Process Bypass` in the same window, then the command again. |
</details>

<details>
<summary><b>What the script does, exactly</b></summary>

1. Uses `adb` if you already have it. Otherwise it downloads Google's official platform-tools into `~/.nuvio-boost` (Mac/Linux) or `%LOCALAPPDATA%\nuvio-boost` (Windows). Nothing is installed system-wide.
2. Connects to each TV and waits for you to approve the connection.
3. Finds every installed package containing "nuvio" and runs `pm compile -m speed -f` on it.
4. Saves your TV addresses for next time and disconnects.
5. Offers to add a `nuvioboost` shortcut: an alias in your shell profile on Mac/Linux, or a small `nuvioboost.cmd` in `%LOCALAPPDATA%\Microsoft\WindowsApps` on Windows. On Mac/Linux the shortcut runs the latest version from this repo. On Windows it runs a saved local copy; re-run the setup command to update it.

The scripts are short and readable. Have a look before running them if you like: [run.sh](run.sh), [run.ps1](run.ps1).
</details>

<details>
<summary><b>Doing it by hand</b></summary>

```
adb connect <TV-IP>:5555
adb shell pm list packages | grep -i nuvio      # Windows: findstr /i nuvio
adb shell pm compile -m speed -f com.nuvio.tv
```
</details>

<details>
<summary><b>Removing it</b></summary>

Delete `~/.nuvio-boost` (Mac/Linux) or `%LOCALAPPDATA%\nuvio-boost` (Windows). To remove the shortcut, delete the `nuvioboost` line from `~/.zshrc` or `~/.bash_profile` (Mac/Linux), or delete `%LOCALAPPDATA%\Microsoft\WindowsApps\nuvioboost.cmd` (Windows). To undo the compile on a TV, run `adb shell pm compile --reset com.nuvio.tv`, or just update Nuvio.
</details>

---

**Tested on:** a Mac with two Nvidia Shields. The Windows script and the Google TV pairing flow haven't been tested on real devices yet, so reports are very welcome.

**Found a problem?** [Open an issue](../../issues) with your device, operating system and the error message.

Not affiliated with Nuvio. Use at your own risk. This only changes how Android compiles the app, not the app itself. MIT licensed.
