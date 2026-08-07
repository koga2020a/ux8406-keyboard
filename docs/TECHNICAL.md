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

送信 API は **`HidD_SetFeature`**(`hid.dll`)。バッファ長は常に 16 バイト、先頭バイトが Report ID `0x5A` です。

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
  ├─ TargetPath が既知なら、まずそのパスを OpenForFeature で開く
  │    └─ 成功 → SendSequence() して終了
  │    └─ 失敗 → 切断された可能性 → InitializedPath をクリアして再検出へ
  ├─ FindTargetPath() で再検出、InitializedPath をクリア
  ├─ 見つからなければ false
  └─ 開けたら SendSequence()、開けなければ false
```

`SendSequence()` は、`TargetPath != InitializedPath` のときだけ初期化ハンドシェイクを送り(送信後 50 ms スリープし `InitializedPath := TargetPath`)、続けて Fn Lock の Feature Report を送信します。ハンドシェイクに失敗した時点で `false` を返し、Fn Lock コマンドは送りません。

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
5. 失敗時: 再度リトライを予約。初回成功前は **3 秒間隔**、成功済みなら **5 秒間隔**。

起動時も同じ `ReapplyFnLock()` を呼ぶだけなので、キーボード未接続で起動しても MsgBox は出ず、接続されるまで静かにリトライし続けます。

### 3.5 状態変数

| 変数 | 役割 |
| --- | --- |
| `FnLocked` | スクリプトが把握している Fn Lock の論理状態(初期値 `true`)。トグルとリトライはこの値を基準にする |
| `DeviceReady` | 直近の送信が成功したか。false のときトレイツールチップに ` (未接続)` を表示 |
| `TargetPath` | 検出済みの HID デバイスインターフェースパス。空なら未検出 |
| `InitializedPath` | ハンドシェイク済みのデバイスパス。`TargetPath` と一致する間はハンドシェイクを省略する |
| `FirstApplyDone` | 起動後に一度でも適用に成功したか。初回通知の抑制とリトライ間隔の切り替えに使う |

`ToggleFnLock()` は「反転した状態を送信し、成功したら `FnLocked` を更新する」順序になっているため、送信に失敗した場合は内部状態を変更しません(実機と乖離しない)。

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

- **キーボード側の Fn+Esc との同期**: キーボード本体の Fn+Esc(ハードウェアの Fn Lock 切り替え)は、機種によっては ASUS サービス経由で処理されるとの報告がある。ユーザーが Fn+Esc を直接押した場合、本スクリプトの内部状態(`FnLocked`)と実機の状態がズレる可能性がある(**未検証**)。
- 同期を実装するなら、制御用と同じ COL05 の Input Report(InputLen = 6 バイト)を Raw Input(`WM_INPUT`)で監視し、Fn+Esc 押下時に届くバイト列を特定して内部状態を追従させる案がある(未実装。AutoHotkey v2 のみで実現可能な見込み)。

## 6. 開発メモ

構文チェックは AutoHotkey v2 本体の `/validate` で行えます。

```
AutoHotkey64.exe /ErrorStdOut /validate asus_ux8406_fnlock_toggle_shift_ctrl_esc.ahk
```

エラーがなければ何も出力されません。実機なしで DllCall のシグネチャの妥当性までは検証できない点に注意してください。
