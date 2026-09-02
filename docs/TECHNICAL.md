# 技術詳細 / 解析メモ

`asus_ux8406_fnlock_toggle_shift_ctrl_esc.ahk` の実装と、ASUS Zenbook Duo UX8406 付属キーボードの HID プロトコル調査結果をまとめます。

利用方法は [../README.md](../README.md) を参照してください。プロトコル特定に至るまでの試行錯誤の生ログは [`../経緯.txt`](../経緯.txt) にあります。

## 1. 対象デバイスの HID 情報

いずれも実機で確認済みの値です。

| 項目 | 値 | 備考 |
| --- | --- | --- |
| VID | `0x0B05` | ASUSTek Computer |
| PID(Bluetooth 接続時) | `0x1B2D` | **本スクリプトの対象** |
| PID(USB / 本体装着時) | `0x1B2C` | 本スクリプトの対象外 |
| UsagePage | `0xFF31` | ベンダー定義ページ |
| Usage | `0x0076` | |
| FeatureReportByteLength | `16` | Report ID 1 バイトを含む |
| Report ID | `0x5A` | |

実機は UX8406**MA**(2024年モデル)。キーボードは複数の HID インターフェース(コレクション)を公開しており、制御用インターフェースは Bluetooth 側 PID `0x1B2D` の **COL05** です。スクリプトはコレクション番号ではなく、上記の UsagePage / Usage / FeatureLen / Report ID の組み合わせで一意に特定します。

USB 接続時(PID `0x1B2C`)については、制御用インターフェースの有無・挙動を確認していないため **未検証** です。スクリプトは Bluetooth 側の PID `0x1B2D` のみを検索対象としています。

## 2. プロトコル

送信 API は **`HidD_SetFeature`**(`hid.dll`)。バッファ長は常に 16 バイト、先頭バイトが Report ID `0x5A` です。読み戻しには同じく `hid.dll` の **`HidD_GetFeature`** を使います(2.4 参照)。

### 2.1 初期化ハンドシェイク

Fn Lock コマンドを受け付けさせる前に、以下の Feature Report を 1 回送信します。

| オフセット | 内容 |
| --- | --- |
| 0 | `0x5A`(Report ID) |
| 1..14 | ASCII 文字列 `"ASUS Tech.Inc."`(14 バイト) |
| 15 | `0x00` |

バイト列:

```
5A 41 53 55 53 20 54 65 63 68 2E 49 6E 63 2E 00
   A  S  U  S  _  T  e  c  h  .  I  n  c  .
```

送信後に **50 ms 待機** します。ハンドシェイクは接続(デバイスパス)ごとに 1 回で足ります。

### 2.2 Fn Lock コマンド

| 状態 | バイト列(残りは `0x00` 埋め、計 16 バイト) |
| --- | --- |
| Fn Lock ON | `5A D0 4E 01 00 ... 00` |
| Fn Lock OFF | `5A D0 4E 00 00 ... 00` |

### 2.3 出典・確定の経緯

コマンド `5A D0 4E xx` は独自に発見したものではなく、以下を参考にしています(詳細な試行錯誤は [`../経緯.txt`](../経緯.txt) 参照)。

- **Linux `hid-asus` ドライバ**: Fn Lock 有効化として `5A D0 4E 01` を送信する実装がある。
- **USB キャプチャの実機報告**: `01` = enable / `00` = disable。
- **G-Helper**(ASUS 製ユーティリティの OSS 代替): Fn Lock 切り替え時に **ACPI 設定 + 上記 HID 送信の両方** を行う。本スクリプトは HID 送信のみだが、UX8406MA の Bluetooth キーボードに対しては **HID 送信だけで Fn Lock が切り替わることを実機で確認済み**(初回の試行で `00` を送って「効かない」と誤認しかけたが、`01` で F1 が通常の F1 として動作し確定)。

なお G-Helper には「UX8406CA では ASUS サービス(ASUS Optimization 等)を止めると Fn キー自体が効かなくなる」という報告があり、機種・構成によっては ASUS サービスが Fn キー処理に介在する可能性があります。本環境では HID 直接送信のみで動作しています。

### 2.4 状態の読み戻し(`HidD_GetFeature`)

同じ COL05 に対する `HidD_GetFeature`(Report ID `0x5A`、16 バイト)は **成功します**。ただし返ってくるのは、**最後に `HidD_SetFeature` で書き込まれた 16 バイトそのもの** です(エコー / レジスタ的な挙動)。実機で確認した値は次のとおりです。

| 直前に書き込まれた内容 | 読み戻し値 |
| --- | --- |
| (本スクリプト未起動時のベースライン) | `5A D0 3D 64 30 00 ... 00` |
| 初期化ハンドシェイク直後 | `5A 41 53 55 53 20 54 65 63 68 2E 49 6E 63 2E 00` |
| `5A D0 4E 01` 送信直後 / 3 秒後 / 13 秒後 | `5A D0 4E 01 00 ... 00`(いずれも同じ値) |

- 読み戻しの所要時間は接続中で **0〜80 ms**。
- 時間が経っても値は変化しません(上記の 3 秒後・13 秒後がいずれも同じ値)。
- ベースライン `5A D0 3D 64 30 ...` は本スクリプトが書かない値であり、他ソフト(ASUS Optimization 等)の書き込みか電源投入時の初期値と考えられます。**意味は未解明** です。
- `HidD_GetInputReport`(InputLen = 6 バイト)も成功し、`5A 3D 2C 00 00 00` を返しました(参考情報。スクリプトでは未使用)。

つまり **読み戻し値は「最後に書かれたレポートのエコー」であり、Fn Lock の実状態を直接示すものではありません**。しかし、本スクリプト以外の書き込みやデバイスのリセットがあれば値が変わるため、**ズレの検知には使えます**。この性質を利用したのが 3.6 のズレ検知です。

確認環境: UX8406MA / Windows 11 26200 / ASUS Optimization・ScreenXpert 等の ASUS 常駐サービスが多数稼働(2026-09-02)。

## 3. スクリプトのアーキテクチャ

### 3.1 デバイス検出 — `FindTargetPath()` / `QueryHid()`

1. `HidD_GetHidGuid` で HID クラスの GUID を取得。
2. `SetupDiGetClassDevsW`(`DIGCF_PRESENT | DIGCF_DEVICEINTERFACE`)でデバイス情報セットを取得。
3. `SetupDiEnumDeviceInterfaces` をインデックス 0 から順に呼び出して列挙。**失敗した時点で必ずループを抜けます**(`ERROR_NO_MORE_ITEMS` も想定外エラーも区別せず打ち切る。インデックスを進め続けると無限ループになり得るため)。
4. `SetupDiGetDeviceInterfaceDetailW` を 2 回呼び(1 回目でサイズ取得、2 回目で本体取得)、デバイスパス文字列を得る。構造体先頭 4 バイトが `cbSize` なので、パスは `detail.Ptr + 4` から UTF-16 で読み出します。`cbSize` には 64bit なら 8、32bit なら 6 を書き込みます。
5. 各パスに対し `QueryHid()` でメタデータを取得し、以下 **すべて** に一致するものを対象とする:
   - `HidD_GetAttributes` の VID = `0x0B05` / PID = `0x1B2D`
   - `HidP_GetCaps` の Usage = `0x0076` / UsagePage = `0xFF31` / FeatureReportByteLength = `16`
   - Feature レポート ID の一覧に `0x5A` が含まれる
6. 最後に `SetupDiDestroyDeviceInfoList` で必ず解放(`finally`)。

Feature レポート ID の一覧は `GetFeatureIds()` が担当します。`HidP_GetCaps` から取得した `NumberFeatureButtonCaps`(オフセット 58)と `NumberFeatureValueCaps`(オフセット 60)を件数として、`HidP_GetButtonCaps` / `HidP_GetValueCaps` を `HIDP_FEATURE`(= 2)で呼び、各 caps 構造体(1 要素 72 バイト)のオフセット 2 にある `ReportID` を重複排除しながら収集します。成功判定は `HIDP_STATUS_SUCCESS` = `0x00110000`。

`HidD_GetPreparsedData` で取得した preparsed data は `HidD_FreePreparsedData` で、ハンドルは `CloseHandle` で、いずれも `finally` により確実に解放します。

### 3.2 オープン戦略

| 用途 | 関数 | `dwDesiredAccess` |
| --- | --- | --- |
| メタデータ取得(列挙時) | `OpenMetadata()` | **`0`**(アクセス権なし) |
| Feature 送信時 | `OpenForFeature()` | `GENERIC_READ \| GENERIC_WRITE` → 失敗したら `GENERIC_WRITE` にフォールバック |

共有モードはどちらも `FILE_SHARE_READ | FILE_SHARE_WRITE`、`dwCreationDisposition` は `OPEN_EXISTING`。

列挙時にアクセス権 0 で開くのは、他プロセスが排他的に使用しているデバイスや読み書き権限が得られないデバイスでも、属性・capabilities は取得できるためです。送信時は読み書き両方を試し、拒否された場合に書き込みのみで再試行します。

### 3.3 送信フロー — `InitializeAndSetFnLock()` / `SendSequence()`

```
InitializeAndSetFnLock(enabled)
  ├─ OpenTargetHandle() でハンドルを取得
  │    ├─ TargetPath が既知なら、まずそのパスを OpenForFeature で開く
  │    │    └─ 失敗 → 切断された可能性 → InitializedPath をクリアして再検出へ
  │    ├─ FindTargetPath() で再検出、InitializedPath をクリア
  │    └─ 見つからない / 開けなければ -1
  ├─ -1 なら false
  └─ SendSequence() を呼び、finally で CloseHandle
```

`SendSequence()` は、`TargetPath != InitializedPath` のときだけ初期化ハンドシェイクを送り(送信後 50 ms スリープし `InitializedPath := TargetPath`)、続けて Fn Lock の Feature Report を送信します。ハンドシェイクに失敗した時点で `false` を返し、Fn Lock コマンドは送りません。送信後は読み戻しによる検証も行います(3.6 参照)。

なお、ハンドルの取得(既知パスを開く → 失敗したら再検出して開く)は `OpenTargetHandle()` に切り出してあり、`InitializeAndSetFnLock()` とズレ検知の `CheckFnLockDrift()` の両方から使います。取得したハンドルの `CloseHandle` は呼び出し側の責任です(`try`/`finally`)。

### 3.4 再適用ロジック

| メッセージ | 条件 | 動作 |
| --- | --- | --- |
| `WM_DEVICECHANGE`(`0x219`) | `wParam = DBT_DEVNODES_CHANGED`(`0x0007`) | `SetTimer(ReapplyFnLock, -1500)` |
| `WM_POWERBROADCAST`(`0x218`) | `wParam = PBT_APMRESUMEAUTOMATIC`(`0x12`)または `PBT_APMRESUMESUSPEND`(`0x7`) | `SetTimer(ReapplyFnLock, -3000)` |

負の周期を指定した `SetTimer` は **ワンショットかつ再スケジュール** になるため、デバイス変更通知が連続しても多重実行されず、最後の通知から一定時間後に 1 回だけ実行されます(デバウンス)。

`ReapplyFnLock()` の挙動:

1. **`InitializedPath := ""` を無条件に実行** — 再接続後はデバイス側の状態がリセットされている可能性があるため、ハンドシェイクを強制的に再送する。
2. `InitializeAndSetFnLock(FnLocked)` で現在の状態を再送信(例外は握りつぶして失敗扱い)。
3. `DeviceReady` を結果で更新し、トレイのツールチップを更新。
4. 成功時: 起動後の初回成功(`FirstApplyDone` が false)のときだけツールチップを表示。以降の自動再適用では通知しない。
5. 成功時: `SetTimer(CheckFnLockDriftSoon, -3000)` で **3 秒後にワンショットのズレ検知を予約** する(`DRIFT_CHECK_INTERVAL_MS > 0` のときのみ)。再接続直後に他ソフトが Fn Lock 状態を上書きしてくるケースを、次の周期チェック(最大約 10 秒後)を待たずに拾うため。
6. 失敗時: 再度リトライを予約。初回成功前は **3 秒間隔**、成功済みなら **5 秒間隔**。

起動時も同じ `ReapplyFnLock()` を呼ぶだけなので、キーボード未接続で起動しても MsgBox は出ず、接続されるまで静かにリトライし続けます。

**BLE 再接続時のデバイスノードの挙動(実機確認)**: BLE の再接続のたびに HID の子ノード(`HID\{00001812-...}_DEV_VID&020B05_PID&1B2D...&COL05\9&AA06097&0&0004` 等)は作り直され、`DEVPKEY_Device_LastArrivalDate` が更新されます(親の `BTHLE\DEV_...` は起動時のまま)。一方でデバイスインターフェースのパス文字列は同一のため、再検出なしで送信を継続できます。裏を返すと **`DBT_DEVNODES_CHANGED` は再接続のたびに飛んでいるはず** であり、「再適用が走っていないからズレる」わけではありません。ズレの原因としては、

- 再接続直後の再適用の **後** に、他ソフト(ASUS Optimization 等)が自分の持つ Fn Lock 状態を書き戻している
- `HidD_SetFeature` は成功を返すが、実機に反映されていない

といった競合が推定されます(**原因は未確定**)。3.6 のズレ検知は、原因を特定せずに結果だけを是正するアプローチです。

### 3.5 状態変数

| 変数 | 役割 |
| --- | --- |
| `FnLocked` | スクリプトが把握している Fn Lock の論理状態(初期値 `true`)。トグルとリトライはこの値を基準にする |
| `DeviceReady` | 直近の送信が成功したか。false のときトレイツールチップに ` (未接続)` を表示 |
| `TargetPath` | 検出済みの HID デバイスインターフェースパス。空なら未検出 |
| `InitializedPath` | ハンドシェイク済みのデバイスパス。`TargetPath` と一致する間はハンドシェイクを省略する |
| `FirstApplyDone` | 起動後に一度でも適用に成功したか。初回通知の抑制とリトライ間隔の切り替えに使う |
| `LinkDown` | 直近のズレ検知でデバイスに到達できなかった。次回のズレ検知で「再接続直後」を判定するために使う |
| `AutoFixCount` | ズレを検知して自動修正した回数。トレイのツールチップに表示する |
| `LastAutoFixTime` | 最後に自動修正した時刻(`HH:mm:ss`)。トレイのツールチップに表示する |

`ToggleFnLock()` は「反転した状態を送信し、成功したら `FnLocked` を更新する」順序になっているため、送信に失敗した場合は内部状態を変更しません(実機と乖離しない)。

`AutoFixCount > 0` のとき、`UpdateTrayTip()` はツールチップに ` / 自動修正 N回 (最終 HH:mm:ss)` を付加します(例: `UX8406 Fn Lock: ON / 自動修正 2回 (最終 09:12:30)`)。

### 3.6 ズレ検知・自動修正 — `CheckFnLockDrift()`

2.4 のとおり、読み戻し値は「最後に書かれたレポートのエコー」です。本スクリプト以外がレポートを書いたり、デバイスがリセットされたりすると値が変わるため、**周期的に読み戻して期待値と比べれば実機側とのズレを検知できます**。

起動時に `DRIFT_CHECK_INTERVAL_MS > 0` であれば `SetTimer(CheckFnLockDrift, DRIFT_CHECK_INTERVAL_MS)` で周期タイマーを登録します(既定 10000 ms、`0` で無効)。

```
CheckFnLockDrift()
  ├─ Critical
  ├─ OpenTargetHandle()          ; 既知パス → 失敗なら再検出して開く
  │    └─ -1 → 未接続扱い(LinkDown / DeviceReady / InitializedPath を落として return)
  ├─ ReadFnLockReport(h)         ; Report ID 0x5A の 16 バイトを読み戻して CloseHandle
  │    └─ 失敗 → 未接続扱い(同上)
  ├─ wasDown := LinkDown / LinkDown := false
  ├─ ReportIsFnLock(rb, FnLocked)      ; 一致
  │    ├─ wasDown → ハンドシェイク込みで再適用(通知なし)
  │    └─ それ以外 → DeviceReady := true のみ
  └─ 不一致(ズレ)
       └─ InitializedPath := "" → InitializeAndSetFnLock(FnLocked)
            └─ 成功 → AutoFixCount++ / LastAutoFixTime 更新
                      / NOTIFY_ON_AUTOFIX ならツールチップ通知
```

判定と処理の対応:

| 読み戻し値 | 判定 | 処理 | 通知 |
| --- | --- | --- | --- |
| `5A D0 4E <期待値>` | 一致 | 直前まで `LinkDown` だった(= 再接続直後)ならハンドシェイク込みで再適用。そうでなければ `DeviceReady := true` のみ | なし |
| `5A D0 4E <反対値>` | ズレ(外部から切り替えられた) | `InitializedPath := ""` してハンドシェイク込みで再適用 | `Fn Lock ズレ検知: OFF → ON に修正`(OFF 運用時は `ON → OFF に修正`) |
| 上記以外(例: ベースライン `5A D0 3D 64 30 ...`) | ズレ(デバイスリセット / 他ソフトの書き込み) | 同上 | `Fn Lock リセット検知: ON を再適用` |
| 読み戻し失敗(`GetFeature` が false) | 到達不能 | `LinkDown := true` / `DeviceReady := false` / `InitializedPath := ""` | なし |
| ハンドルが開けない(再検出しても不可) | 未接続 | 同上。再検出は次回の周期に任せる | なし |

通知は約 1.8 秒表示され、`NOTIFY_ON_AUTOFIX := false` で抑制できます(抑制しても修正自体は行われ、`AutoFixCount` は増えます)。

補助関数:

| 関数 | 役割 |
| --- | --- |
| `GetFeature(h, report)` | `HidD_GetFeature` の薄いラッパ(`SetFeature()` と対) |
| `ReadFnLockReport(h)` | Report ID `0x5A` の 16 バイトを読み戻す。失敗時は `""` を返す |
| `FnLockStateFromReport(buf)` | 先頭 3 バイトが `5A D0 4E` なら 4 バイト目(`0` / `1`)を返す。それ以外は `-1` |
| `ReportIsFnLock(buf, enabled)` | 読み戻しが期待する Fn Lock 状態と一致するか |
| `OpenTargetHandle()` | 既知パスを開く → 失敗なら再検出して開く(3.3 参照) |
| `ShowAutoFixTooltip(enabled, rb)` | 自動修正時の通知。`FnLockStateFromReport()` の戻り値で「ズレ検知」と「リセット検知」を出し分ける |
| `ManualResync(*)` | トレイメニュー「今すぐ再同期」。ハンドシェイク込みで現在状態を再送し、通常の `Fn Lock: ON` / `OFF` ツールチップを表示する |

**`Critical` を付ける理由**: `CheckFnLockDrift()` / `ToggleFnLock()` / `ReapplyFnLock()` / `ManualResync()` は、いずれも `TargetPath` / `InitializedPath` / `FnLocked` を読み書きしながら 50 ms の `Sleep` を挟みます。AutoHotkey ではタイマーやホットキーが擬似スレッドとして割り込むため、`Critical` がないと「送信の途中で別のトグルが走り、ハンドシェイク状態や `FnLocked` が壊れる」おそれがあります。

**`CheckFnLockDriftSoon()` を別関数にしている理由**: `SetTimer` はタイマーを **関数オブジェクト単位** で管理します。ワンショット(負の周期)を `CheckFnLockDrift` そのものに掛けると、起動時に登録した周期タイマーの設定が上書きされ、周期チェックが止まってしまいます。そこで中身が `CheckFnLockDrift()` の呼び出しだけの別関数 `CheckFnLockDriftSoon()` を用意し、周期タイマーと独立させています。

**`SendSequence()` の送信後検証**: Fn Lock の Feature Report を送った後、**50 ms 待って読み戻し**、期待値と一致しなければ **1 回だけ再送して再検証** します。読み戻し自体が失敗した場合(`GetFeature` が false)は検証不能とみなし、**従来どおり送信成功として扱います**。読み戻しに対応しない環境でも動作が壊れないようにするためです。

**実機テスト(2026-09-02)**: スクリプトを起動した状態で、別プロセスから COL05 に `5A D0 4E 00`(反対値)と初期化ハンドシェイク(Fn Lock 以外のレポート)をそれぞれ書き込んだところ、いずれも約 8 秒後(次の周期チェック)に読み戻し値が `5A D0 4E 01` へ戻ることを確認しました。また、接続中に 10 秒間隔で 4 分間(24 回)読み戻しを続けても値は変化せず、ASUS 常駐サービスが接続中に周期的にレポートを書き換えることはありませんでした(誤検知による通知の連発は起きにくいと判断しています)。

## 4. タッチパッド ON/OFF の調査結果(スクリプト化は見送り)

将来スクリプト化したくなった場合のためのメモです。**現状スクリプトには実装していません。**

### 4.1 デバイスの見え方(確認済み)

UX8406 のタッチパッドは Windows 標準の Precision Touchpad として認識されます。

| 項目 | 値 |
| --- | --- |
| デバイス名 | `ASUS Precision Touchpad` |
| ハードウェア ID(USB 接続時) | `HID\VID_0B05&PID_1B2C&MI_05&COL02` |
| ハードウェア ID(Bluetooth 接続時) | `HID\{00001812-0000-1000-8000-00805F9B34FB}_DEV_VID&020B05_PID&1B2D...&COL02`(Bluetooth LE の HID over GATT 形式) |

### 4.2 方法A: レジストリ

設定アプリ「Bluetooth とデバイス > タッチパッド」のトグルの実体は次の値です。

| 項目 | 値 |
| --- | --- |
| キー | `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\Status` |
| 値名 | `Enabled` |
| 型 / 値 | `REG_DWORD` / `0` = 無効、`1` = 有効 |

トグル操作でこの値が変化することは確認済みですが、**レジストリを直接書き換えた場合に即時反映されるかは未検証** です(設定アプリ側からの通知が必要な可能性あり)。

### 4.3 方法B: `pnputil` によるデバイス無効化

```
pnputil /disable-device "HID\VID_0B05&PID_1B2C&MI_05&COL02\..."
pnputil /enable-device  "HID\VID_0B05&PID_1B2C&MI_05&COL02\..."
```

- **管理者権限が必要**
- デバイスレベルで無効化するため即時かつ確実
- インスタンス ID は接続形態(USB / Bluetooth)によって変わるため、都度取得が必要

### 4.4 結論

Windows 標準の設定(トグル + 「マウスの接続時にタッチパッドをオンのままにする」)で用途を満たせたため、スクリプト化は見送りました。

## 5. 既知の制限と今後のアイデア

- **キーボード側の Fn+Esc との同期**: 本環境では ASUS Optimization / ScreenXpert 等の ASUS 常駐サービスが稼働しており、キーボード本体の Fn+Esc(ハードウェアの Fn Lock 切り替え)はそれらが処理している可能性がある。3.6 のズレ検知が入ったことで、**外部から変更された Fn Lock は本スクリプトの状態(`FnLocked`)へ戻される** ようになった。逆に言えば **外部トグルに追従する動作は未実装** であり、Fn+Esc で切り替えても最大約 `DRIFT_CHECK_INTERVAL_MS` で打ち消される。
  - 追従させる実装案: 読み戻しが `5A D0 4E <反対値>`(= Fn Lock レポートで値だけが反対)のときに限り、再適用せず `FnLocked` を反転して追従する。Fn Lock レポート以外(ベースライン等)のときは従来どおりリセットとみなして再適用する、という切り分けができる。
- 追従をより確実にするなら、制御用と同じ COL05 の Input Report(InputLen = 6 バイト)を Raw Input(`WM_INPUT`)で監視し、Fn+Esc 押下時に届くバイト列を特定して内部状態を追従させる案もある(未実装。AutoHotkey v2 のみで実現可能な見込み)。
- 読み戻しのベースライン値 `5A D0 3D 64 30 ...` の意味は未解明(2.4)。この値を書いている主体を特定できれば、ズレの原因も確定できる可能性がある。

## 6. 開発メモ

構文チェックは AutoHotkey v2 本体の `/validate` で行えます。

```
AutoHotkey64.exe /ErrorStdOut /validate asus_ux8406_fnlock_toggle_shift_ctrl_esc.ahk
```

エラーがなければ何も出力されません。実機なしで DllCall のシグネチャの妥当性までは検証できない点に注意してください。

読み戻し(`HidD_GetFeature`)の実機確認のような、実際にデバイスへアクセスする検証も、WSL 側から Windows の `AutoHotkey64.exe` を起動して行えます(検証用スクリプトを走らせ、結果をファイルへ書き出して WSL 側から読む)。
