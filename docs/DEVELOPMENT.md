# Development setup: from clone to your iPhone

This guide takes you from nothing to MyNutritionPal running on **your own iPhone**, talking to the backend on **your own Mac**, with your own database, OpenAI key and Apple signing. You don't need any file from another developer. Follow it top to bottom.

The [README](../README.md) is the reference (configuration, API, design notes); this is the path.

Examples use a Mac named `Dans-MacBook-Air` and a bundle ID `com.dan.MyNutritionPal`. Replace them with your own.

## 1. Prerequisites

- **A Mac.** iOS apps are built with Xcode, which only runs on macOS.
- **Xcode**, from the Mac App Store. The app needs **iOS 18.5 or later**, so Xcode **16.4 or newer**. Your Xcode must also support the iOS version on your iPhone. If the phone runs a newer iOS than your Xcode knows, update Xcode (and macOS, if that Xcode requires it). Open Xcode once after installing and let it install any components it asks for.
- **Git.** It comes with Xcode's command line tools. If `git --version` asks you to install them, accept (or run `xcode-select --install`).
- **Python 3.11 or newer.** 3.11 is the project's baseline, and this guide uses it. 3.14 has also been tested. **macOS's built-in `python3` (3.9) is too old** and fails with a `TypeError`. The simplest install is [Homebrew](https://brew.sh): install it (follow the "Next steps" it prints to add it to your PATH), then:
  ```bash
  brew install python@3.11
  python3.11 --version        # Python 3.11.x
  ```
- **An Apple ID.** A free one is enough: Xcode gives it a free "Personal Team" for running apps on your own devices. You don't need the paid Apple Developer Program (see step 15 for the limits).
- **An iPhone** on iOS 18.5 or later, and a cable to connect it to the Mac.
- **An OpenAI API key** from [platform.openai.com](https://platform.openai.com/api-keys), with billing or credit set up. Meal estimates (text and photo) use it and are charged to your account. **A ChatGPT subscription is not API credit**: they're billed separately. Everything else (onboarding, Today, History, editing, deleting) works without a key.
- **GitHub access** to the repository. It's private: accept the collaborator invitation first (email, or github.com/notifications).

## 2. Clone

Use a normal folder such as `~/Developer`, **not** `~/Desktop` or `~/Documents` if iCloud Drive syncs them. iCloud can stall file reads for minutes, which freezes the server.

```bash
mkdir -p ~/Developer
cd ~/Developer
git clone git@github.com:erende3/Nutrition_App.git      # SSH, if your GitHub account has an SSH key
# or: git clone https://github.com/erende3/Nutrition_App.git
#     (HTTPS asks for your GitHub username and a personal access token, not your password)
cd Nutrition_App
```

## 3. Backend environment

```bash
cd backend
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
pip check                     # "No broken requirements found."
```

`requirements-dev.txt` installs the app's dependencies (`requirements.txt`) plus the development tools: pytest and httpx for the tests, pyflakes, and watchfiles, which lets `python app.py` auto-reload when code changes.

Every new terminal needs `cd ~/Developer/Nutrition_App/backend` and `source .venv/bin/activate` again before running backend commands. The `(.venv)` prefix in your prompt shows it's active.

## 4. Backend tests (optional)

```bash
python -m pytest
```

Everything should pass (545 tests at the time of writing). The tests use a temporary database and a fake estimator: they need no API key, no network and no simulator.

## 5. Your OpenAI key

```bash
cp .env.example .env
open -e .env                  # or any editor
```

Put **your own** key after `OPENAI_API_KEY=` on one line, with no quotes or spaces, and save. The other settings are optional and commented out; the defaults are fine.

- `.env` is git-ignored. **Never commit it**, and never paste your key into an issue, pull request or chat.
- A key **exported in your shell** wins over `.env`, so a stale key in your shell profile would be used instead of yours. Check without printing it:
  ```bash
  echo "${OPENAI_API_KEY:+a key is exported in this shell}"
  ```
  If that prints anything, run `unset OPENAI_API_KEY`, and remove the `export OPENAI_API_KEY=...` line from `~/.zshrc` or `~/.zprofile` if it's there (`grep -n OPENAI_API_KEY ~/.zshrc ~/.zprofile`).

## 6. Your database

You don't need anyone else's database. The first time the backend starts, it creates `backend/nutrition.db` and migrates it to the latest schema (`0007_meal_identity_and_edits`). It starts empty, and the app creates your user when it first connects. The file stays on your Mac: `*.db` is git-ignored.

## 7. Start the backend

From `backend/`, with the virtualenv active:

```bash
python app.py
```

This migrates the database, then serves on **`0.0.0.0:8000`**: every network interface, so the iPhone can reach it. **Leave this terminal open**; the server runs until you press Ctrl-C.

If macOS asks whether **Python** may accept incoming network connections, click **Allow**. Otherwise the iPhone can't connect.

## 8. Check the backend on the Mac

In a second terminal:

```bash
curl http://localhost:8000/
# {"message":"Nutrition estimator is running.","documentation":"/docs"}
curl http://localhost:8000/v1/users/profile
# {"id":1, ..., "onboarding_complete":false}
```

The interactive API docs are at <http://localhost:8000/v1/docs>.

## 9. Your Mac's network name

```bash
scutil --get LocalHostName    # e.g. Dans-MacBook-Air
curl http://Dans-MacBook-Air.local:8000/
```

The phone reaches the Mac at `<LocalHostName>.local`. That name stays the same when you change networks, so you won't need to rebuild the app.

**Fallback:** some networks block these `.local` names. Use the Mac's LAN IP instead (`ipconfig getifaddr en0`, e.g. `192.168.1.20`). An IP can change when you reconnect, and then you must update it and rebuild.

## 10. iOS local config

```bash
cd ~/Developer/Nutrition_App/frontend/MyNutritionPal/Config
cp Local.xcconfig.example Local.xcconfig
open -e Local.xcconfig
```

Set your Mac's address:

```
API_BASE_URL = http:/$()/Dans-MacBook-Air.local:8000
```

Write `http:/$()/` exactly, **not** `http://`. In an xcconfig file `//` starts a comment, and `$()` expands to nothing, so this becomes `http://Dans-MacBook-Air.local:8000`. With an IP: `http:/$()/192.168.1.20:8000`.

`Local.xcconfig` is git-ignored and yours alone. **Never commit it.** Only Debug builds (what Xcode's Run uses) read it.

## 11. Your signing

An app on a device must be signed by a development team, and its **bundle ID must be unique across all Apple teams**. The shared project defaults to the project owner's team and bundle ID (in `Config/Debug.xcconfig`). You can't use those: Apple won't let your team register a bundle ID that another team already owns. You override both in your `Local.xcconfig`, so the shared project file never changes. The project uses **automatic signing**: once the team and bundle ID are set, Xcode creates and renews your certificate and provisioning profile itself.

**a. Add your Apple ID to Xcode.** Xcode > Settings > Accounts > **+** > Apple ID, then sign in. It appears with a team named "*Your Name* (Personal Team)".

**b. Find your Team ID** (10 characters, like `ABCDE12345`). Create a development certificate: in Accounts, select your team > **Manage Certificates…** > **+** > **Apple Development**. Then, in Terminal:

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

Your Team ID is the `OU=` value. *(This command is verified on the project owner's Mac. For a free Personal Team, confirm it during your first setup. If you have several Apple Development certificates, it shows only the first one.)*

*Fallback, if that doesn't work:* choose your team in Xcode's **Signing & Capabilities** (step 12), then read the ID from the change it makes, and undo that change as described under **"If Xcode changed the project file"** below:

```bash
cd ~/Developer/Nutrition_App
git diff -- frontend/MyNutritionPal/MyNutritionPal.xcodeproj/project.pbxproj | grep DEVELOPMENT_TEAM
```

**c. Set both values** in `Config/Local.xcconfig`, by uncommenting the two lines at the bottom:

```
DEVELOPMENT_TEAM = ABCDE12345
PRODUCT_BUNDLE_IDENTIFIER = com.dan.MyNutritionPal
```

Use your Team ID, and a bundle ID of your own, in reverse-DNS style, e.g. `com.<yourname>.MyNutritionPal`. If Xcode says it's not available, make it more specific.

**Don't use the Team menu in Signing & Capabilities after this.** Choosing a team there writes it into the shared `project.pbxproj`, where it overrides `Local.xcconfig`, and `git status` shows the project file as modified.

**If Xcode changed the project file**, quit Xcode, then look at what changed:

```bash
cd ~/Developer/Nutrition_App
git diff -- frontend/MyNutritionPal/MyNutritionPal.xcodeproj/project.pbxproj
```

If the only changes are `DEVELOPMENT_TEAM` (or bundle ID) lines you didn't mean to make, discard them:

```bash
git restore frontend/MyNutritionPal/MyNutritionPal.xcodeproj/project.pbxproj
```

This discards **every** uncommitted change to that one file (nothing else). If the diff shows changes you want to keep, such as a file you added to the project, don't run it: remove just the signing lines in Xcode or an editor instead.

## 12. Open the project

```bash
open ~/Developer/Nutrition_App/frontend/MyNutritionPal/MyNutritionPal.xcodeproj
```

To check signing, select the **MyNutritionPal** project in the navigator > target **MyNutritionPal** > **Signing & Capabilities**. It should show *Automatically manage signing* checked, your team, your bundle ID, and no errors. If you edited `Local.xcconfig` while Xcode was open and it still shows the old values, close and reopen the project. Look, but don't change them here.

## 13. Connect your iPhone

1. Connect the iPhone to the Mac with the cable, and unlock it.
2. If the phone asks **Trust This Computer?**, tap **Trust** and enter your passcode.
3. In Xcode's toolbar, open the run destination menu (next to the scheme name **MyNutritionPal**) and choose your iPhone. The first time, Xcode may spend a few minutes preparing the device.

## 14. Developer Mode

iOS runs development builds only with Developer Mode on. The switch appears after the iPhone has been connected to Xcode (step 13):

1. On the iPhone: Settings > Privacy & Security > **Developer Mode** (near the bottom) > on.
2. Tap **Restart**. After the restart, unlock the phone, tap **Turn On** and enter your passcode.

## 15. Build and install

In Xcode, press **Cmd-R** (Product > Run). Xcode builds the Debug configuration, signs it with your team, installs it on the phone and launches it.

Free (Personal Team) signing is enough for this project, with Apple's limits:

- The app's provisioning profile **expires after 7 days**. After that the app won't open; connect the phone and press Cmd-R again.
- A free team can have only a few apps installed on a device at a time (3), and can create only a limited number of new bundle IDs per week. Pick your bundle ID once and keep it.

Only **Run** (the Debug configuration) uses your `Local.xcconfig`. Product > Profile and Archive use the Release configuration, which keeps the project owner's signing on purpose, so they won't sign for you; you don't need them. Run the unit tests on a simulator (see the README's *Tests*), not on your iPhone: the test targets aren't set up for your signing.

## 16. Trust your developer certificate

The first time you run an app signed by a free team, iOS may refuse to open it ("Untrusted Developer"). On the iPhone: Settings > General > **VPN & Device Management** > under *Developer App*, tap your Apple ID > **Trust**. Then press Cmd-R again.

## 17. Local Network permission

On first launch the app asks to find and connect to devices on your local network ("Connect to the nutrition server running on my Mac."). Tap **Allow**; without it, the app can't reach your Mac. If you denied it: Settings > Privacy & Security > **Local Network** > turn on MyNutritionPal.

## 18. Test the connection without the app

On the **iPhone**, open Safari and go to `http://Dans-MacBook-Air.local:8000/` (your address from step 10, written with `//`).

If you see `{"message":"Nutrition estimator is running."...}`, the phone can reach the Mac: the network, the name (or IP) and the Mac's firewall are all fine, and the server's terminal logs the request from the phone's IP. If it doesn't load, fix that first (see Troubleshooting); the app can't do better than Safari.

## 19. Onboarding

With a new database, the app opens on onboarding (**Welcome**). Step through age and sex, height and weight, activity level and goal, then tap **Calculate My Goal**. The app shows your daily calorie goal. **Continue to Today** opens the **Today** tab, with the goal and 0 consumed. Your profile is saved in your Mac's `nutrition.db`.

## 20. Check that everything works

Text and photo estimates call OpenAI and are charged to **your** API account.

- [ ] Onboarding completes, and Today shows your goal.
- [ ] Today loads; History loads (today's date).
- [ ] **Text meal:** on Today, under *Log a meal*, type what you ate in *What did you eat?* (e.g. "chicken and rice") and tap **Estimate Meal**. After a few seconds it shows as the last meal added, and the totals update.
- [ ] **Photo meal:** tap **Take Photo** (allow camera access when asked) or **Choose Photo**, then **Estimate Meal**. It's logged too.
- [ ] Both meals appear in History.
- [ ] Tap a meal in History: its details open.
- [ ] **Edit:** change the name or calories and save. The change shows in the details, History and Today.
- [ ] **Delete:** swipe a meal left in History and delete it. It disappears, and the totals update.

## Troubleshooting

**Python**

- **`python3.11: command not found`:** install it with `brew install python@3.11`. If Homebrew is installed but not found, run the "Next steps" commands its installer printed (they add it to your PATH).
- **`TypeError: unsupported operand type(s) for |`**, or `python --version` says 3.9: that's macOS's Python. Delete `backend/.venv` and recreate it with `python3.11` (step 3).

**Backend**

- **`[Errno 48] Address already in use`:** something already uses port 8000, usually an earlier `python app.py`. Find it with `lsof -nP -iTCP:8000 -sTCP:LISTEN`. If it's your old server, stop it with Ctrl-C in its terminal, or `kill <PID>`. To use another port instead, from `backend/` with the virtualenv active:
  ```bash
  alembic upgrade head
  uvicorn app:app --host 0.0.0.0 --port 8001
  ```
  Then put `:8001` in `API_BASE_URL` and rebuild.
- **Things break after `git pull`:** stop the server (Ctrl-C), run `pip install -r requirements-dev.txt` in case dependencies changed, start `python app.py` again (it migrates the database; auto-reload doesn't), and rebuild the app.

**Estimates (the server's terminal shows the underlying error)**

- **"Meal estimation is not available right now."** (503 `estimation_unavailable`): no key. `.env` is missing, `OPENAI_API_KEY` is blank, or you edited `.env` without restarting the server (auto-reload doesn't pick up `.env` changes; stop it with Ctrl-C and start `python app.py` again). The log says `The OPENAI_API_KEY environment variable is not set.`
- **"Meal estimation failed. Please try again."** (502 `estimation_failed`): OpenAI refused the request. The log shows `401 Incorrect API key` for a wrong or revoked key; a quota or billing error means no API credit. Also check that no stale shell key overrides `.env` (step 5).

**The app can't reach the Mac**

The app says *"Can't reach the server at …"*. (If it says *"No server address is set"*, `Local.xcconfig` is missing or `API_BASE_URL` is empty: step 10. If the address it names is `Your-Mac-Name.local`, you left the example value in.) Work through these in order:

1. **Is the server running?** `curl http://localhost:8000/` on the Mac (step 8).
2. **Is `API_BASE_URL` right?** Check the host, the port and the `http:/$()/` form in `Config/Local.xcconfig`, then rebuild (Cmd-R). The app reads the address at build time.
3. **Does Safari on the iPhone load it?** (step 18). If not:
   - **Same network:** both on the same Wi-Fi, and not one on Wi-Fi and the other on cellular or Ethernet on a different network.
   - **Guest Wi-Fi / AP or client isolation:** these block devices from reaching each other. So do many corporate, campus and hotel networks. Use a normal home network, or turn on the iPhone's **Personal Hotspot** and join it from the Mac (`.local` names work there).
   - **VPN:** turn off VPNs on both devices, or allow local-network access in them.
   - **Mac firewall:** System Settings > Network > Firewall > Options: allow incoming connections for Python, or turn the firewall off to test.
   - **`.local` name not resolving:** use the Mac's IP instead (step 9) and rebuild.
4. **Local Network permission** for MyNutritionPal is on (step 17).

The cable is only for installing the app. The app always talks to the backend over Wi-Fi, even while plugged in, so these network rules apply either way.

**Signing and installing**

- **Bundle identifier "not available" / "cannot be registered":** another team owns that bundle ID, usually because you're still on the project default. Set your own `PRODUCT_BUNDLE_IDENTIFIER` in `Local.xcconfig` (step 11), and make it more specific if needed.
- **Wrong team, or "No Account for Team":** set `DEVELOPMENT_TEAM` in `Local.xcconfig` to your Team ID, and check that your Apple ID is in Xcode > Settings > Accounts. If `git status` shows `project.pbxproj` modified, see "If Xcode changed the project file" (step 11).
- **"Developer Mode disabled":** step 14.
- **"Untrusted Developer" / the app won't open after installing:** step 16.
- **The app stopped opening after about a week:** your free provisioning profile expired. Connect the phone and press Cmd-R.
- **Xcode says the iPhone's iOS isn't supported, or keeps "preparing" it:** your Xcode is older than the phone's iOS. Update Xcode.
- **No Take Photo button, or the camera is blocked:** Take Photo only appears on a device with a camera. If you denied access, go to Settings > Apps > MyNutritionPal > Camera (on older iOS, Settings > MyNutritionPal).
