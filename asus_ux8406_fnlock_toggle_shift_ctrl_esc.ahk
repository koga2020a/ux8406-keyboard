#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; =====================================================================
; ASUS UX8406 Bluetooth Keyboard - Fn Lock Toggle
; AutoHotkey v2 only / external DLL不要
;
; Hotkey:
;   Shift + Ctrl + Esc  -> Fn Lock ON/OFF toggle
;
; 実機確認済み:
;   VID         = 0x0B05
;   PID         = 0x1B2D
;   UsagePage   = 0xFF31
;   Usage       = 0x0076
;   FeatureLen  = 16
;   Report ID   = 0x5A
;
; Fn Lock:
;   ON  = 5A D0 4E 01 ...
;   OFF = 5A D0 4E 00 ...
;
; 起動時:
;   1) 対象HIDを自動検出
;   2) "ASUS Tech.Inc." 初期化Feature Reportを送信
;   3) Fn LockをONにして既知状態へ揃える
; =====================================================================

global ASUS_VID          := 0x0B05
global UX8406_BT_PID     := 0x1B2D
global TARGET_USAGEPAGE  := 0xFF31
global TARGET_USAGE      := 0x0076
global TARGET_REPORT_ID  := 0x5A
global TARGET_FEATURELEN := 16

global TargetPath := ""
global FnLocked := true

; 起動時にONへ揃える
try {
    TargetPath := FindTargetPath()

    if (TargetPath = "")
        throw Error("UX8406 Bluetoothキーボードの制御用HIDが見つかりません。")

    if !InitializeAndSetFnLock(true)
        throw Error("起動時のFn Lock ON送信に失敗しました。")

    ShowFnTooltip(true)
}
catch as e {
    MsgBox(
        "ASUS Fn Lock初期化エラー:`n`n" e.Message,
        "ASUS UX8406 Fn Lock",
        "Iconx"
    )
}


; =====================================================================
; Shift + Ctrl + Esc
; =====================================================================

^+Esc::
{
    global FnLocked

    newState := !FnLocked

    try {
        if InitializeAndSetFnLock(newState) {
            FnLocked := newState
            ShowFnTooltip(FnLocked)
        } else {
            ShowErrorTooltip("Fn Lock送信失敗")
        }
    }
    catch as e {
        ShowErrorTooltip("Fn Lock送信失敗")
    }
}


; =====================================================================
; Fn Lock送信
; =====================================================================

InitializeAndSetFnLock(enabled)
{
    global TargetPath

    ; Bluetooth再接続等でPathが無効になった場合に備え、まず現在Pathを試す
    if (TargetPath != "") {
        h := OpenForFeature(TargetPath)
        if (h != -1) {
            try {
                return SendSequence(h, enabled)
            }
            finally {
                DllCall("kernel32\CloseHandle", "Ptr", h)
            }
        }
    }

    ; 再検出
    TargetPath := FindTargetPath()

    if (TargetPath = "")
        return false

    h := OpenForFeature(TargetPath)

    if (h = -1)
        return false

    try {
        return SendSequence(h, enabled)
    }
    finally {
        DllCall("kernel32\CloseHandle", "Ptr", h)
    }
}


SendSequence(h, enabled)
{
    global TARGET_FEATURELEN

    ; -------------------------------------------------------------
    ; 1) ASUS HID初期化
    ;    5A + ASCII "ASUS Tech.Inc."
    ; -------------------------------------------------------------
    init := Buffer(TARGET_FEATURELEN, 0)
    NumPut("UChar", 0x5A, init, 0)

    ascii := "ASUS Tech.Inc."
    Loop Parse ascii
        NumPut("UChar", Ord(A_LoopField), init, A_Index)

    if !SetFeature(h, init)
        return false

    Sleep 50

    ; -------------------------------------------------------------
    ; 2) Fn Lock
    ;    ON  = 5A D0 4E 01
    ;    OFF = 5A D0 4E 00
    ; -------------------------------------------------------------
    report := Buffer(TARGET_FEATURELEN, 0)

    NumPut("UChar", 0x5A, report, 0)
    NumPut("UChar", 0xD0, report, 1)
    NumPut("UChar", 0x4E, report, 2)
    NumPut("UChar", enabled ? 0x01 : 0x00, report, 3)

    return SetFeature(h, report)
}


SetFeature(h, report)
{
    DllCall("kernel32\SetLastError", "UInt", 0)

    ok := DllCall(
        "hid\HidD_SetFeature",
        "Ptr", h,
        "Ptr", report.Ptr,
        "UInt", report.Size,
        "UChar"
    )

    return !!ok
}


; =====================================================================
; Tooltip
; =====================================================================

ShowFnTooltip(enabled)
{
    ToolTip(enabled ? "Fn Lock: ON" : "Fn Lock: OFF")
    SetTimer(HideFnTooltip, -1000)
}


ShowErrorTooltip(text)
{
    ToolTip(text)
    SetTimer(HideFnTooltip, -1800)
}


HideFnTooltip()
{
    ToolTip()
}


; =====================================================================
; 対象HID自動検出
; =====================================================================

FindTargetPath()
{
    global ASUS_VID
    global UX8406_BT_PID
    global TARGET_USAGEPAGE
    global TARGET_USAGE
    global TARGET_REPORT_ID
    global TARGET_FEATURELEN

    static DIGCF_PRESENT := 0x00000002
    static DIGCF_DEVICEINTERFACE := 0x00000010
    static ERROR_NO_MORE_ITEMS := 259

    hidGuid := Buffer(16, 0)
    DllCall("hid\HidD_GetHidGuid", "Ptr", hidGuid.Ptr)

    hDevInfo := DllCall(
        "setupapi\SetupDiGetClassDevsW",
        "Ptr", hidGuid.Ptr,
        "Ptr", 0,
        "Ptr", 0,
        "UInt", DIGCF_PRESENT | DIGCF_DEVICEINTERFACE,
        "Ptr"
    )

    if (hDevInfo = -1)
        return ""

    foundPath := ""

    try {
        idx := 0

        loop {
            ifData := Buffer(A_PtrSize = 8 ? 32 : 28, 0)
            NumPut("UInt", ifData.Size, ifData, 0)

            ok := DllCall(
                "setupapi\SetupDiEnumDeviceInterfaces",
                "Ptr", hDevInfo,
                "Ptr", 0,
                "Ptr", hidGuid.Ptr,
                "UInt", idx,
                "Ptr", ifData.Ptr,
                "Int"
            )

            if !ok {
                if (A_LastError = ERROR_NO_MORE_ITEMS)
                    break
                idx++
                continue
            }

            required := 0

            DllCall(
                "setupapi\SetupDiGetDeviceInterfaceDetailW",
                "Ptr", hDevInfo,
                "Ptr", ifData.Ptr,
                "Ptr", 0,
                "UInt", 0,
                "UInt*", &required,
                "Ptr", 0,
                "Int"
            )

            if (required > 0) {
                detail := Buffer(required, 0)
                NumPut("UInt", A_PtrSize = 8 ? 8 : 6, detail, 0)

                ok := DllCall(
                    "setupapi\SetupDiGetDeviceInterfaceDetailW",
                    "Ptr", hDevInfo,
                    "Ptr", ifData.Ptr,
                    "Ptr", detail.Ptr,
                    "UInt", detail.Size,
                    "UInt*", &required,
                    "Ptr", 0,
                    "Int"
                )

                if ok {
                    path := StrGet(detail.Ptr + 4, "UTF-16")
                    d := QueryHid(path)

                    if (
                        d.Valid
                        && d.VID = ASUS_VID
                        && d.PID = UX8406_BT_PID
                        && d.UsagePage = TARGET_USAGEPAGE
                        && d.Usage = TARGET_USAGE
                        && d.FeatureLen = TARGET_FEATURELEN
                        && HasId(d.FeatureIDs, TARGET_REPORT_ID)
                    ) {
                        foundPath := path
                        break
                    }
                }
            }

            idx++
        }
    }
    finally {
        DllCall(
            "setupapi\SetupDiDestroyDeviceInfoList",
            "Ptr", hDevInfo
        )
    }

    return foundPath
}


QueryHid(path)
{
    h := OpenMetadata(path)

    if (h = -1) {
        return {
            Valid: false,
            VID: 0,
            PID: 0,
            UsagePage: 0,
            Usage: 0,
            FeatureLen: 0,
            FeatureIDs: []
        }
    }

    try {
        attrs := Buffer(12, 0)
        NumPut("UInt", attrs.Size, attrs, 0)

        if !DllCall(
            "hid\HidD_GetAttributes",
            "Ptr", h,
            "Ptr", attrs.Ptr,
            "UChar"
        ) {
            return {
                Valid: false,
                VID: 0,
                PID: 0,
                UsagePage: 0,
                Usage: 0,
                FeatureLen: 0,
                FeatureIDs: []
            }
        }

        vid := NumGet(attrs, 4, "UShort")
        pid := NumGet(attrs, 6, "UShort")

        ppd := 0

        if !DllCall(
            "hid\HidD_GetPreparsedData",
            "Ptr", h,
            "Ptr*", &ppd,
            "UChar"
        ) {
            return {
                Valid: false,
                VID: vid,
                PID: pid,
                UsagePage: 0,
                Usage: 0,
                FeatureLen: 0,
                FeatureIDs: []
            }
        }

        try {
            caps := Buffer(64, 0)

            status := DllCall(
                "hid\HidP_GetCaps",
                "Ptr", ppd,
                "Ptr", caps.Ptr,
                "UInt"
            )

            if (status != 0x00110000) {
                return {
                    Valid: false,
                    VID: vid,
                    PID: pid,
                    UsagePage: 0,
                    Usage: 0,
                    FeatureLen: 0,
                    FeatureIDs: []
                }
            }

            usage := NumGet(caps, 0, "UShort")
            usagePage := NumGet(caps, 2, "UShort")
            featureLen := NumGet(caps, 8, "UShort")
            nFeatureButtons := NumGet(caps, 58, "UShort")
            nFeatureValues := NumGet(caps, 60, "UShort")

            ids := GetFeatureIds(
                ppd,
                nFeatureButtons,
                nFeatureValues
            )

            return {
                Valid: true,
                VID: vid,
                PID: pid,
                UsagePage: usagePage,
                Usage: usage,
                FeatureLen: featureLen,
                FeatureIDs: ids
            }
        }
        finally {
            DllCall(
                "hid\HidD_FreePreparsedData",
                "Ptr", ppd,
                "UChar"
            )
        }
    }
    finally {
        DllCall("kernel32\CloseHandle", "Ptr", h)
    }
}


GetFeatureIds(ppd, buttonCount, valueCount)
{
    static HIDP_FEATURE := 2
    static HIDP_STATUS_SUCCESS := 0x00110000
    static CAPS_SIZE := 72

    ids := []

    if (buttonCount > 0) {
        count := buttonCount
        buf := Buffer(CAPS_SIZE * count, 0)

        status := DllCall(
            "hid\HidP_GetButtonCaps",
            "Int", HIDP_FEATURE,
            "Ptr", buf.Ptr,
            "UShort*", &count,
            "Ptr", ppd,
            "UInt"
        )

        if (status = HIDP_STATUS_SUCCESS) {
            Loop count
                AddUnique(
                    ids,
                    NumGet(
                        buf,
                        (A_Index - 1) * CAPS_SIZE + 2,
                        "UChar"
                    )
                )
        }
    }

    if (valueCount > 0) {
        count := valueCount
        buf := Buffer(CAPS_SIZE * count, 0)

        status := DllCall(
            "hid\HidP_GetValueCaps",
            "Int", HIDP_FEATURE,
            "Ptr", buf.Ptr,
            "UShort*", &count,
            "Ptr", ppd,
            "UInt"
        )

        if (status = HIDP_STATUS_SUCCESS) {
            Loop count
                AddUnique(
                    ids,
                    NumGet(
                        buf,
                        (A_Index - 1) * CAPS_SIZE + 2,
                        "UChar"
                    )
                )
        }
    }

    return ids
}


AddUnique(arr, value)
{
    for _, x in arr
        if (x = value)
            return

    arr.Push(value)
}


HasId(arr, wanted)
{
    for _, x in arr
        if (x = wanted)
            return true

    return false
}


; =====================================================================
; HID open helpers
; =====================================================================

OpenMetadata(path)
{
    static FILE_SHARE_READ := 0x00000001
    static FILE_SHARE_WRITE := 0x00000002
    static OPEN_EXISTING := 3

    return DllCall(
        "kernel32\CreateFileW",
        "Str", path,
        "UInt", 0,
        "UInt", FILE_SHARE_READ | FILE_SHARE_WRITE,
        "Ptr", 0,
        "UInt", OPEN_EXISTING,
        "UInt", 0,
        "Ptr", 0,
        "Ptr"
    )
}


OpenForFeature(path)
{
    static GENERIC_READ := 0x80000000
    static GENERIC_WRITE := 0x40000000
    static FILE_SHARE_READ := 0x00000001
    static FILE_SHARE_WRITE := 0x00000002
    static OPEN_EXISTING := 3

    h := DllCall(
        "kernel32\CreateFileW",
        "Str", path,
        "UInt", GENERIC_READ | GENERIC_WRITE,
        "UInt", FILE_SHARE_READ | FILE_SHARE_WRITE,
        "Ptr", 0,
        "UInt", OPEN_EXISTING,
        "UInt", 0,
        "Ptr", 0,
        "Ptr"
    )

    if (h != -1)
        return h

    return DllCall(
        "kernel32\CreateFileW",
        "Str", path,
        "UInt", GENERIC_WRITE,
        "UInt", FILE_SHARE_READ | FILE_SHARE_WRITE,
        "Ptr", 0,
        "UInt", OPEN_EXISTING,
        "UInt", 0,
        "Ptr", 0,
        "Ptr"
    )
}
