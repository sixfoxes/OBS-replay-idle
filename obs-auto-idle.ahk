#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ========================== CONFIG ==========================
replayHotkeyOn  := "+{F9}"                  ; OBS "Start Replay Buffer" hotkey (Shift+F9)
replayHotkeyOff := "+{F8}"                  ; OBS "Stop Replay Buffer" hotkey (Shift+F8)
idleThreshold   := 4 * 60 * 1000            ; 4 mins idle timer
checkInterval   := 5000                     ; 5-second checks — prevents race condition
showPopups      := false                    ; Set false to silence popups
popupDuration   := 3000                     ; Popup auto-close time in ms

; Debounce buffer (to avoid jitter)
activityDebounce := 2000                    ; must be continuously active for 2s before turning ON
idleDebounce     := 2000                    ; must be continuously idle for 2s before turning OFF

; Post-toggle settle and cooldowns
postToggleSettle := 5000                    ; ignore readings right after a toggle (settle window)
cooldownAfterOff := 12000                   ; prevent immediate re-ON after OFF
cooldownAfterOn  := 5000                    ; prevent immediate re-OFF after ON

; ========================== ADMIN ==========================
if (!A_IsAdmin) {
    try Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
    ExitApp
}

global suppressUntil := 0
global lastTick := A_TickCount
global idleAccum := 0
global activeAccum := 0

global desiredState := ""                   ; "ON" | "OFF" | "" — what we want OBS to be
global lastObservedState := ""              ; "ON" | "OFF" | "" — current read via powercfg
global lastStateAt := 0                     ; last time observed state changed
global lastToggleAt := 0                    ; last time we sent a start/stop request
global enforceDesired := false              ; when true, actively reconcile mismatches (Force ON/OFF)

SetTimer(CheckIdle, checkInterval)

; ======================= MAIN LOGIC =======================
CheckIdle() {
    global suppressUntil, lastTick, idleAccum, activeAccum
    global idleThreshold, activityDebounce, idleDebounce
    global desiredState, lastObservedState, lastStateAt, lastToggleAt
    global postToggleSettle, cooldownAfterOff, cooldownAfterOn, enforceDesired

    if (A_TickCount < suppressUntil)
        return

    delta := A_TickCount - lastTick
    lastTick := A_TickCount

    state := GetReplayState()
    if (state != lastObservedState) {
        lastObservedState := state
        lastStateAt := A_TickCount
    }

    userActive := A_TimeIdlePhysical < idleThreshold
    inSettle := (A_TickCount - lastToggleAt) < postToggleSettle

    ; Reconcile observed vs desired when enforcement is on (e.g., after Force ON/OFF)
    if (enforceDesired && desiredState != "" && !inSettle) {
        if (state != desiredState) {
            RequestReplay(desiredState)
            return  ; avoid double-processing in the same tick
        }
    }

    ; Cooldowns prevent immediate flip-flop after a change
    canTurnOn  := (A_TickCount - lastToggleAt) > cooldownAfterOff
    canTurnOff := (A_TickCount - lastToggleAt) > cooldownAfterOn

    if (state = "ON") {
        ; Buffer is ON → only check for idle
        if (!userActive && !inSettle && canTurnOff) {
            idleAccum += delta
            if (idleAccum >= idleDebounce) {
                RequestReplay("OFF")
                idleAccum := 0
                activeAccum := 0
            }
        } else {
            idleAccum := 0
        }
    } else {
        ; Buffer is OFF → only check for activity
        if (userActive && !inSettle && canTurnOn) {
            activeAccum += delta
            if (activeAccum >= activityDebounce) {
                RequestReplay("ON")
                activeAccum := 0
                idleAccum := 0
            }
        } else {
            activeAccum := 0
        }
    }
}

RequestReplay(target) {
    global desiredState, lastToggleAt, suppressUntil, postToggleSettle
    desiredState := target
    if (target = "ON") {
        TurnReplayOn()
    } else {
        TurnReplayOff()
    }
    lastToggleAt := A_TickCount
    ; Suppress reactive checks briefly while OBS updates and powercfg settles
    suppressUntil := A_TickCount + postToggleSettle
}

TurnReplayOn() {
    global replayHotkeyOn
    if WinExist("ahk_exe obs64.exe") {
        ControlSend(replayHotkeyOn, , "ahk_exe obs64.exe")
        VerifyState("ON")
        ShowPopup("Activity → Replay Buffer turned ON")
    } else {
        ShowPopup("OBS not found → cannot turn ON")
    }
}

TurnReplayOff() {
    global replayHotkeyOff
    if WinExist("ahk_exe obs64.exe") {
        ControlSend(replayHotkeyOff, , "ahk_exe obs64.exe")
        VerifyState("OFF")
        ShowPopup("Idle " . Round(idleThreshold/1000) . "s → Replay Buffer OFF")
    } else {
        ShowPopup("OBS not found → cannot turn OFF")
    }
}

VerifyState(target) {
    ; Poll up to ~5s; if mismatched, retry once.
    Loop 10 {
        Sleep(500)
        if (GetReplayState() = target)
            return
    }
    ; Single retry if still mismatched
    if WinExist("ahk_exe obs64.exe") {
        if (target = "ON")
            ControlSend(replayHotkeyOn, , "ahk_exe obs64.exe")
        else
            ControlSend(replayHotkeyOff, , "ahk_exe obs64.exe")
    }
}

; =================== NON-BLOCKING POPUPS ===================
ShowPopup(text) {
    if (!showPopups)
        return
    g := Gui("+AlwaysOnTop -Caption +ToolWindow")
    g.BackColor := "FFFFCC"  ; pale yellow background
    g.AddText("w300 h40 Center", text)
    g.Show("AutoSize Center")
    SetTimer(() => g.Destroy(), -popupDuration)

    ; Pause idle checks until popup closes + 5s buffer
    global suppressUntil
    suppressUntil := Max(suppressUntil, A_TickCount + popupDuration + (5 * 1000))
}

; =================== DETECT IF OBS BLOCKS SLEEP ===================
GetReplayState() {
    return IsOBSBlockingSleep() ? "ON" : "OFF"
}

IsOBSBlockingSleep() {
    tempFile := A_Temp "\obs_powercfg.tmp"
    RunWait('cmd /c powercfg /requests > "' tempFile '"', , "Hide")
    try {
        content := FileRead(tempFile)
        if !content
            return false
        ; Replay Buffer ON if obs64.exe is listed in powercfg /requests
        return InStr(content, "obs64.exe")
    } finally {
        try FileDelete(tempFile)
    }
    return false
}

; ==================== DEBUG HOTKEYS ====================
; Ctrl + Alt + R → Show current replay buffer status (ON/OFF)
^!r:: ShowPopup(GetReplayState() = "ON"
    ? "YES → Replay Buffer is ON (blocking sleep)"
    : "NO → Replay Buffer is OFF (sleep allowed)")

; Ctrl + Alt + T → Manual toggle replay buffer (disables enforcement)
^!t:: {
    state := GetReplayState()
    enforceDesired := false
    RequestReplay(state = "ON" ? "OFF" : "ON")
    Sleep(500)  ; small delay before checking status
    ShowPopup("Toggled → " GetReplayState())
}

; Ctrl + Alt + O → Force replay buffer OFF (enforces desired OFF)
^!o:: {
    idleAccum := 0
    activeAccum := 0
    enforceDesired := true
    RequestReplay("OFF")
    ShowPopup("Forced OFF")
}

; Ctrl + Alt + I → Force replay buffer ON (enforces desired ON)
^!i:: {
    idleAccum := 0
    activeAccum := 0
    enforceDesired := true
    RequestReplay("ON")
    ShowPopup("Forced ON")
}

; Ctrl + Alt + S → Toggle persistent idle time display
global idleDisplayOn := false
global idleGui

^!s:: {
    global idleDisplayOn, idleGui
    if (!idleDisplayOn) {
        idleDisplayOn := true
        idleGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
        idleGui.BackColor := "FFFFCC"
        idleGui.AddText("vIdleText w300 h60 Center")
        idleGui.Show("AutoSize Center")
        SetTimer(UpdateIdleDisplay, 1000)  ; update every second
    } else {
        idleDisplayOn := false
        SetTimer(UpdateIdleDisplay, 0)     ; stop updates
        try idleGui.Destroy()
    }
}

UpdateIdleDisplay() {
    global idleGui, idleAccum, activeAccum, desiredState, lastObservedState
    if !idleGui
        return
    idleSeconds := Round(A_TimeIdlePhysical/1000)
    idleGui["IdleText"].Text := "Physical idle time: " idleSeconds " seconds`n"
        . "IdleAccum: " Round(idleAccum/1000) "s, ActiveAccum: " Round(activeAccum/1000) "s`n"
        . "Desired: " desiredState ", Observed: " lastObservedState "`n"
        . "Press Ctrl+Alt+S to hide"
}

; Ctrl + Alt + P → Pause / Resume script
^!p:: {
    Pause -1
    ShowPopup(A_IsPaused ? "SCRIPT PAUSED" : "SCRIPT RESUMED")
}

; Ctrl + Alt + M → Send a test popup window
^!m:: ShowPopup("Test popup window triggered by hotkey")

; ====================== STARTUP ======================
ShowPopup("OBS Auto-Idle loaded")
