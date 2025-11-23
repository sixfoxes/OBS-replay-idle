Purpose
This script automatically disables OBS Replay Buffer when your PC is idle so the system can enter sleep/idle states, and re-enables the buffer when you return. It solves a common race where a single toggle hotkey and delayed state detection cause the buffer to flip back on unexpectedly. Intended use: reduce unnecessary sleep-blocking by OBS Replay Buffer.

Requirements
AutoHotkey v2.0 or later

OBS Studio (obs64.exe) configured with two Replay Buffer hotkeys:

Start Replay Buffer: Shift+F9

Stop Replay Buffer: Shift+F8

Windows (uses powercfg /requests to detect whether obs64.exe is blocking sleep)

Quick setup
Install AutoHotkey v2 and OBS Studio.

In OBS Settings → Hotkeys, assign:

Start Replay Buffer: Shift+F9

Stop Replay Buffer: Shift+F8

Download the script file (obs-auto-idle.ahk) and edit configuration at the top if you want different keys or timings.

Recommended: run the script with admin privileges (either let it auto-elevate on start or run it elevated via Task Scheduler — see next section).

Run the script. The script will auto-elevate if not started as admin, but using Task Scheduler removes prompts (recommended for a seamless experience).

Run silently at logon with full privileges (recommended)
To avoid UAC prompts and ensure the script can read system state and send hotkeys reliably, create a Scheduled Task that runs the script with highest privileges:

Open Task Scheduler → Create Task.

General:

Name: OBS Auto-Idle

Check “Run with highest privileges”

Configure for your Windows version

Triggers:

New → “At log on” → choose your account

Actions:

New → Program/script: full path to AutoHotkey.exe

Add arguments: full quoted path to obs-auto-idle.ahk

Start in: folder containing the script

Settings:

Optional: allow task to be run on demand

Save. The script will run elevated at logon without UAC prompts.

If you prefer manual start without UAC, create the task without a trigger and run it on demand with: schtasks /run /tn "OBS Auto-Idle" (or create a shortcut that runs that schtasks command).

Configuration (top of script)
replayHotkeyOn := "+{F9}" ; Start Replay Buffer (Shift+F9)

replayHotkeyOff := "+{F8}" ; Stop Replay Buffer (Shift+F8)

idleThreshold := 4 * 60 * 1000 ; 4 minutes in ms (change for debugging)

checkInterval := 5000 ; interval between checks in ms

activityDebounce := 2000 ; require continuous activity for this long before turning ON

idleDebounce := 2000 ; require continuous idle for this long before turning OFF

postToggleSettle := 5000 ; ignore readings right after requests

cooldownAfterOff := 12000 ; prevent immediate re-ON after OFF

cooldownAfterOn := 5000 ; prevent immediate re-OFF after ON

showPopups, popupDuration — popup behavior

Change idleThreshold to 4 * 60 * 1000 for production use.

How it works (expanded)
Separate hotkeys for Start and Stop eliminate toggle ambiguity. The script sends Start or Stop explicitly rather than a single toggle.

Observed state detection: the script runs powercfg /requests and checks for occurance of obs64.exe to infer whether OBS is blocking sleep (Replay Buffer or other OBS features may cause this).

Desired state tracking: whenever the script requests a change it records the desiredState ("ON" or "OFF") so it knows what it asked OBS to do.

Settle window: after sending a Start/Stop request the script waits a short settle period (postToggleSettle) and suppresses reaction to transient readings while OBS and powercfg settle.

Verification loop: after sending a Start/Stop the script polls for up to ~5 seconds to confirm the observed state matches the requested state; it retries once if necessary.

Cooldowns: after toggles the script enforces cooldowns (different for ON and OFF) to avoid immediate flip-flops caused by quick user activity or detection lag.

Accumulators and debouncing: idle and activity accumulators require continuous idle/activity for configured debounce intervals to avoid jitter from short events.

Enforcement mode: when you use “Force OFF” or “Force ON” debug hotkeys, the script will actively reconcile any mismatch between desired and observed state until the observed state matches the desired state.

Non-blocking popups: optional GUI popups inform you of actions but extend a brief suppress window while visible to avoid false triggers.

Together these measures remove the race condition between a toggle hotkey and delayed powercfg detection and make the script authoritative about the desired Replay Buffer state.

Debug hotkeys (in-script)
Ctrl + Alt + R → Show current replay buffer status (ON/OFF)

Ctrl + Alt + T → Manual toggle replay buffer (disables enforcement)

Ctrl + Alt + O → Force replay buffer OFF (enforces desired OFF)

Ctrl + Alt + I → Force replay buffer ON (enforces desired ON)

Ctrl + Alt + S → Toggle persistent idle time display (shows desired vs observed)

Ctrl + Alt + P → Pause / Resume script

Ctrl + Alt + M → Show test popup

Known limitations
Detection is based on powercfg /requests; other OBS features (streaming, virtual camera, plugins) or extensions may also cause obs64.exe to appear in powercfg even when Replay Buffer is off.

If OBS is controlled manually or by other software concurrently, the script may need enforcement mode engaged to maintain desired state.

For bulletproof control and precise state queries, consider using OBS WebSocket (StartReplayBuffer/StopReplayBuffer and state feedback) instead of powercfg-based detection.

Running as admin or via Task Scheduler is recommended for reliable behavior and to avoid permission-related issues.

Troubleshooting
If the script flip-flops, confirm your OBS hotkeys are set to different Start/Stop mappings (not a single toggle).

If powercfg constantly reports obs64.exe even with Replay Buffer off, check for streaming, virtual camera, or plugins that may keep OBS active.

For testing, reduce idleThreshold to a small value (10s) in the config and enable popups to watch behavior.

If you get parse errors after editing, check for matching quotes and parentheses around ShowPopup lines and hotkey blocks.

License
This project is provided under the MIT License. Include a LICENSE file with the MIT text and add your copyright notice.
