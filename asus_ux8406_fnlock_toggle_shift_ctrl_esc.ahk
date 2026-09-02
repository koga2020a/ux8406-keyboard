#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; =====================================================================
; ASUS UX8406 Bluetooth Keyboard - Fn Lock Toggle
; AutoHotkey v2 only / external DLL不要
;
; Hotkey:
;   Shift + Ctrl + Esc  -> Fn Lock ON/OFF toggle
;     (ホットキーは FNLOCK_HOTKEY 変数で変更可能)
;
; キーリマップ:
;   CapsLock            -> Ctrl (CapsLock+C = Ctrl+C など組み合わせも可)
;   Win + CapsLock      -> 本来のCapsLock ON/OFF トグル
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
;   (見つからない場合はMsgBoxを出さずバックグラウンドでリトライ)
;
; Bluetooth再接続 / スリープ復帰:
;   WM_DEVICECHANGE / WM_POWERBROADCAST を受けて自動で再適用
;
; ズレ検知:
;   周期的にFeature Reportを読み戻し、期待値 5A D0 4E xx と一致しなければ
;   他ソフトの書き込み / デバイスリセットによる「ズレ」とみなし、
;   初期化ハンドシェイク込みで再適用してツールチップで通知する
;   (トレイメニュー「今すぐ再同期」で手動実行も可能)
;
;   DRIFT_CHECK_INTERVAL_MS : 読み戻しによるズレ検知の周期(ms) / 0で無効
;   NOTIFY_ON_AUTOFIX       : 自動修正時にツールチップで通知するか
; =====================================================================

; ---------------------------------------------------------------------
; 設定
; ---------------------------------------------------------------------
global FNLOCK_HOTKEY     := "^+Esc"

global ASUS_VID          := 0x0B05
global UX8406_BT_PID     := 0x1B2D
global TARGET_USAGEPAGE  := 0xFF31
global TARGET_USAGE      := 0x0076
global TARGET_REPORT_ID  := 0x5A
global TARGET_FEATURELEN := 16

; ズレ検知: 実機のFeature Reportを読み戻し、期待値と違えば再適用する周期(ms)。0で無効
global DRIFT_CHECK_INTERVAL_MS := 10000
; ズレを自動修正したときにツールチップで通知するか
global NOTIFY_ON_AUTOFIX := true

; ---------------------------------------------------------------------
; 状態
; ---------------------------------------------------------------------
global TargetPath := ""

; 接続ごとに1回だけ初期化ハンドシェイクを送るための記録
global InitializedPath := ""

global FnLocked := true
global DeviceReady := false
global FirstApplyDone := false

global LinkDown := false        ; 直近のズレ検知でデバイスに到達できなかった
global AutoFixCount := 0        ; ズレを検知して自動修正した回数
global LastAutoFixTime := ""    ; 最後に自動修正した時刻 (HH:mm:ss)

; ---------------------------------------------------------------------
; トレイメニュー
; ---------------------------------------------------------------------
A_TrayMenu.Insert("1&", "Fn Lock切り替え", ToggleFnLock)
A_TrayMenu.Insert("2&", "今すぐ再同期", ManualResync)
A_TrayMenu.Default := "Fn Lock切り替え"
UpdateTrayTip()

; ---------------------------------------------------------------------
; ホットキー登録
; ---------------------------------------------------------------------
Hotkey(FNLOCK_HOTKEY, ToggleFnLock)

; ---------------------------------------------------------------------
; Bluetooth再接続 / スリープ復帰の検知
; ---------------------------------------------------------------------
OnMessage(0x219, OnDeviceChange)     ; WM_DEVICECHANGE
OnMessage(0x218, OnPowerBroadcast)   ; WM_POWERBROADCAST

; ---------------------------------------------------------------------
; 起動時にONへ揃える(失敗時はMsgBoxを出さずリトライ)
; ---------------------------------------------------------------------
FnLocked := true
ReapplyFnLock()

; ---------------------------------------------------------------------
; ズレ検知の周期チェック開始
; ---------------------------------------------------------------------
if (DRIFT_CHECK_INTERVAL_MS > 0)
    SetTimer(CheckFnLockDrift, DRIFT_CHECK_INTERVAL_MS)


; =====================================================================
; Fn Lockトグル (ホットキー / トレイメニュー共通)
; =====================================================================

ToggleFnLock(*)
{
    global FnLocked
    global DeviceReady

    ; ズレ検知タイマー等とのHID送受信の交錯を防ぐ
    Critical

    newState := !FnLocked

    try {
        if InitializeAndSetFnLock(newState) {
            FnLocked := newState
            DeviceReady := true
            UpdateTrayTip()
            ShowFnTooltip(FnLocked)
        } else {
            DeviceReady := false
            UpdateTrayTip()
            ShowErrorTooltip("Fn Lock送信失敗")
        }
    }
    catch as e {
        DeviceReady := false
        UpdateTrayTip()
        ShowErrorTooltip("Fn Lock送信失敗: " e.Message)
    }
}


; =====================================================================
; 自動再適用 (Bluetooth再接続 / スリープ復帰 / 起動時リトライ)
; =====================================================================

OnDeviceChange(wParam, lParam, msg, hwnd)
{
    static DBT_DEVNODES_CHANGED := 0x0007

    if (wParam = DBT_DEVNODES_CHANGED)
        SetTimer(ReapplyFnLock, -1500)
}


OnPowerBroadcast(wParam, lParam, msg, hwnd)
{
    static PBT_APMRESUMESUSPEND := 0x7
    static PBT_APMRESUMEAUTOMATIC := 0x12

    if (wParam = PBT_APMRESUMEAUTOMATIC || wParam = PBT_APMRESUMESUSPEND)
        SetTimer(ReapplyFnLock, -3000)
}


ReapplyFnLock()
{
    global FnLocked
    global DeviceReady
    global InitializedPath
    global FirstApplyDone
    global DRIFT_CHECK_INTERVAL_MS

    ; ズレ検知タイマー等とのHID送受信の交錯を防ぐ
    Critical

    ; 再接続後はデバイス側がリセットされている可能性があるため、
    ; このパスでは必ず初期化ハンドシェイクを再送する
    InitializedPath := ""

    ok := false

    try {
        ok := InitializeAndSetFnLock(FnLocked)
    }
    catch {
        ok := false
    }

    DeviceReady := ok
    UpdateTrayTip()

    ; 自動再適用ではツールチップを出さない(初回成功時のみ通知)
    if (ok) {
        ; 再接続直後に他ソフトが上書きしてくるケースを早期に拾う
        if (DRIFT_CHECK_INTERVAL_MS > 0)
            SetTimer(CheckFnLockDriftSoon, -3000)

        if !FirstApplyDone {
            FirstApplyDone := true
            ShowFnTooltip(FnLocked)
        }
        return
    }

    ; -付き一発タイマーなので多重スケジュールにならない
    SetTimer(ReapplyFnLock, FirstApplyDone ? -5000 : -3000)
}


; =====================================================================
; トレイ表示
; =====================================================================

UpdateTrayTip()
{
    global FnLocked
    global DeviceReady
    global AutoFixCount
    global LastAutoFixTime

    A_IconTip := "UX8406 Fn Lock: "
        . (FnLocked ? "ON" : "OFF")
        . (DeviceReady ? "" : " (未接続)")
        . (AutoFixCount > 0 ? " / 自動修正 " AutoFixCount "回 (最終 " LastAutoFixTime ")" : "")
}


; =====================================================================
; Fn Lock送信
; =====================================================================

InitializeAndSetFnLock(enabled)
{
    h := OpenTargetHandle()

    if (h = -1)
        return false

    try {
        return SendSequence(h, enabled)
    }
    finally {
        DllCall("kernel32\CloseHandle", "Ptr", h)
    }
}


; 対象HIDのハンドルを取得する (失敗時は -1)
;   既知のTargetPathをまず試し、駄目なら再検出してから開く
;   成功時のCloseHandleは呼び出し側の責任 (try/finally)
OpenTargetHandle()
{
    global TargetPath
    global InitializedPath

    ; Bluetooth再接続等でPathが無効になった場合に備え、まず現在Pathを試す
    if (TargetPath != "") {
        h := OpenForFeature(TargetPath)
        if (h != -1)
            return h

        ; オープン失敗 = 切断された可能性。ハンドシェイク状態を無効化
        InitializedPath := ""
    }

    ; 再検出
    TargetPath := FindTargetPath()
    InitializedPath := ""

    if (TargetPath = "")
        return -1

    h := OpenForFeature(TargetPath)

    if (h = -1) {
        InitializedPath := ""
        return -1
    }

    return h
}


SendSequence(h, enabled)
{
    global TARGET_FEATURELEN
    global TargetPath
    global InitializedPath

    ; -------------------------------------------------------------
    ; 1) ASUS HID初期化 (接続ごとに1回だけ)
    ;    5A + ASCII "ASUS Tech.Inc."
    ; -------------------------------------------------------------
    if (TargetPath != InitializedPath) {
        init := Buffer(TARGET_FEATURELEN, 0)
        NumPut("UChar", 0x5A, init, 0)

        ascii := "ASUS Tech.Inc."
        Loop Parse ascii
            NumPut("UChar", Ord(A_LoopField), init, A_Index)

        if !SetFeature(h, init)
            return false

        Sleep 50

        InitializedPath := TargetPath
    }

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

    if !SetFeature(h, report)
        return false

    ; -------------------------------------------------------------
    ; 3) 読み戻して検証
    ;    対象コレクションは最後にSetFeatureされた16バイトをそのまま返す
    ;    GetFeature自体が失敗する環境では検証不能とみなして成功扱い
    ; -------------------------------------------------------------
    Sleep 50

    rb := ReadFnLockReport(h)

    if !IsObject(rb)
        return true

    if ReportIsFnLock(rb, enabled)
        return true

    ; 不一致なら1回だけ再送
    if !SetFeature(h, report)
        return false

    Sleep 50

    rb := ReadFnLockReport(h)

    if !IsObject(rb)
        return true

    return ReportIsFnLock(rb, enabled)
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


; SetFeature()と対になる薄いラッパ
;   呼び出し前にreportの先頭バイトへReport ID (0x5A) を入れておくこと
GetFeature(h, report)
{
    DllCall("kernel32\SetLastError", "UInt", 0)

    ok := DllCall(
        "hid\HidD_GetFeature",
        "Ptr", h,
        "Ptr", report.Ptr,
        "UInt", report.Size,
        "UChar"
    )

    return !!ok
}


; =====================================================================
; Feature Report読み戻し / ズレ判定
; =====================================================================

; 現在のFeature Reportを読み戻す
;   成功時はBuffer、失敗時は "" を返す
ReadFnLockReport(h)
{
    global TARGET_FEATURELEN
    global TARGET_REPORT_ID

    buf := Buffer(TARGET_FEATURELEN, 0)
    NumPut("UChar", TARGET_REPORT_ID, buf, 0)

    if !GetFeature(h, buf)
        return ""

    return buf
}


; 読み戻したレポートからFn Lock状態を取り出す
;   先頭3バイトが 5A D0 4E なら4バイト目 (0/1) を返す
;   それ以外は -1 (= Fn Lockレポートではない:
;   ハンドシェイクのエコー / 他ソフトの書き込み / 初期値など)
FnLockStateFromReport(buf)
{
    if !IsObject(buf)
        return -1

    if (NumGet(buf, 0, "UChar") != 0x5A)
        return -1

    if (NumGet(buf, 1, "UChar") != 0xD0)
        return -1

    if (NumGet(buf, 2, "UChar") != 0x4E)
        return -1

    return NumGet(buf, 3, "UChar")
}


ReportIsFnLock(buf, enabled)
{
    return FnLockStateFromReport(buf) = (enabled ? 1 : 0)
}


; =====================================================================
; ズレ検知 (周期チェック / 手動再同期)
; =====================================================================

CheckFnLockDrift()
{
    global FnLocked
    global DeviceReady
    global InitializedPath
    global LinkDown
    global AutoFixCount
    global LastAutoFixTime
    global NOTIFY_ON_AUTOFIX

    ; ホットキーや他タイマーとのHID送受信の交錯を防ぐ
    Critical

    h := OpenTargetHandle()

    ; 未接続。再検出は次回の周期に任せる
    if (h = -1) {
        LinkDown := true
        DeviceReady := false
        InitializedPath := ""
        UpdateTrayTip()
        return
    }

    rb := ""

    try {
        rb := ReadFnLockReport(h)
    }
    finally {
        DllCall("kernel32\CloseHandle", "Ptr", h)
    }

    ; ノードはあるがリンク断などでGetFeatureに失敗 = 未接続扱い
    if !IsObject(rb) {
        LinkDown := true
        DeviceReady := false
        InitializedPath := ""
        UpdateTrayTip()
        return
    }

    wasDown := LinkDown
    LinkDown := false

    ; -------------------------------------------------------------
    ; 期待値と一致
    ; -------------------------------------------------------------
    if ReportIsFnLock(rb, FnLocked) {
        if (wasDown) {
            ; 再接続直後。レジスタが残っていても念のため
            ; ハンドシェイク込みで再適用する (通知なし)
            InitializedPath := ""

            ok := false

            try {
                ok := InitializeAndSetFnLock(FnLocked)
            }
            catch {
                ok := false
            }

            DeviceReady := ok
        } else {
            DeviceReady := true
        }

        UpdateTrayTip()
        return
    }

    ; -------------------------------------------------------------
    ; 不一致 = 他者の書き込み / デバイスリセットによるズレ
    ; -------------------------------------------------------------
    InitializedPath := ""

    ok := false

    try {
        ok := InitializeAndSetFnLock(FnLocked)
    }
    catch {
        ok := false
    }

    DeviceReady := ok

    if (ok) {
        AutoFixCount++
        LastAutoFixTime := FormatTime(, "HH:mm:ss")

        if NOTIFY_ON_AUTOFIX
            ShowAutoFixTooltip(FnLocked, rb)
    }

    UpdateTrayTip()
}


; 単発の遅延チェック用ラッパ
;   SetTimer(CheckFnLockDrift, -3000) と書くと同名タイマーの周期設定が
;   上書きされて周期チェックが止まるため、別関数として登録する
CheckFnLockDriftSoon()
{
    CheckFnLockDrift()
}


; トレイメニュー「今すぐ再同期」
ManualResync(*)
{
    global FnLocked
    global DeviceReady
    global InitializedPath

    ; ズレ検知タイマー等とのHID送受信の交錯を防ぐ
    Critical

    InitializedPath := ""

    ok := false

    try {
        ok := InitializeAndSetFnLock(FnLocked)
    }
    catch {
        ok := false
    }

    if (ok) {
        DeviceReady := true
        UpdateTrayTip()
        ShowFnTooltip(FnLocked)
    } else {
        DeviceReady := false
        UpdateTrayTip()
        ShowErrorTooltip("Fn Lock送信失敗")
    }
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


ShowAutoFixTooltip(enabled, rb)
{
    state := FnLockStateFromReport(rb)

    ; 0/1 = Fn Lockレポートだが値が反対 / -1 = Fn Lockレポートではない
    if (state = 0 || state = 1)
        ToolTip("Fn Lock ズレ検知: " (enabled ? "OFF → ON" : "ON → OFF") " に修正")
    else
        ToolTip("Fn Lock リセット検知: " (enabled ? "ON" : "OFF") " を再適用")

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

            ; 列挙終了(ERROR_NO_MORE_ITEMS)も想定外エラーも打ち切る
            ; (idx++ で継続すると無限ループになり得るため)
            if !ok
                break


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


HidInfoInvalid(vid := 0, pid := 0)
{
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


QueryHid(path)
{
    h := OpenMetadata(path)

    if (h = -1)
        return HidInfoInvalid()

    try {
        attrs := Buffer(12, 0)
        NumPut("UInt", attrs.Size, attrs, 0)

        if !DllCall(
            "hid\HidD_GetAttributes",
            "Ptr", h,
            "Ptr", attrs.Ptr,
            "UChar"
        )
            return HidInfoInvalid()

        vid := NumGet(attrs, 4, "UShort")
        pid := NumGet(attrs, 6, "UShort")

        ppd := 0

        if !DllCall(
            "hid\HidD_GetPreparsedData",
            "Ptr", h,
            "Ptr*", &ppd,
            "UChar"
        )
            return HidInfoInvalid(vid, pid)

        try {
            caps := Buffer(64, 0)

            status := DllCall(
                "hid\HidP_GetCaps",
                "Ptr", ppd,
                "Ptr", caps.Ptr,
                "UInt"
            )

            if (status != 0x00110000)
                return HidInfoInvalid(vid, pid)

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


; =====================================================================
; CapsLock -> Ctrl (組み合わせ対応: CapsLock+C = Ctrl+C など)
; =====================================================================
CapsLock::Ctrl

; Win+CapsLock で本来のCapsLockをトグル
#CapsLock::SetCapsLockState(!GetKeyState("CapsLock", "T"))
