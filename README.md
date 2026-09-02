# ASUS Zenbook Duo UX8406 Fn Lock Toggle

ASUS Zenbook Duo UX8406 付属の Bluetooth キーボードの **Fn Lock** を、Windows 上のホットキーから切り替える AutoHotkey v2 常駐スクリプトです。

## 何を解決するか

UX8406 の付属キーボードは、Bluetooth 接続時に Windows 標準の機能では Fn Lock の状態を制御できません(ファンクションキー行がメディアキーのままになる/意図しない状態で固定される)。

本スクリプトは対象キーボードの HID デバイスを自動検出し、**HID Feature Report を直接送信**することで Fn Lock を任意に切り替えます。実機で動作確認済みです。

また、Bluetooth の再接続や ASUS 常駐サービスとの競合などが原因と見られますが(原因は未確定)、**たまに F キー行がメディアキーに戻ってしまう**(スクリプトが把握している状態と実機の状態がズレる)ことがあります。本スクリプトは実機の状態を定期的に読み戻して監視し、ズレを検知したら自動で元の状態へ戻します。

- スクリプト本体: [`asus_ux8406_fnlock_toggle_shift_ctrl_esc.ahk`](asus_ux8406_fnlock_toggle_shift_ctrl_esc.ahk)

## 機能

| 機能 | 説明 |
| --- | --- |
| Fn Lock トグル | `Ctrl+Shift+Esc` で ON/OFF を切り替え。トレイアイコンのダブルクリック、またはトレイメニューの「Fn Lock切り替え」でも同じ動作 |
| 起動時の自動設定 | 起動時に Fn Lock を **ON** にして既知の状態へ揃える。キーボード未接続でもエラーダイアログは出さず、バックグラウンドで接続されるまでリトライ |
| 自動再適用 | Bluetooth 再接続・スリープ復帰を検知して、現在の Fn Lock 状態を自動的に再送信(`WM_DEVICECHANGE` / `WM_POWERBROADCAST` を監視) |
| ズレ検知・自動修正 | 約 10 秒ごとに実機の Feature Report を読み戻し、スクリプトが把握している状態と食い違っていれば自動で再適用。修正時は `Fn Lock ズレ検知: OFF → ON に修正` 等のツールチップを約 1.8 秒表示。また、Fn Lock を送信した直後にも読み戻して検証し、一致しなければ 1 回だけ再送する |
| 今すぐ再同期 | トレイメニューの「今すぐ再同期」で、現在の Fn Lock 状態をその場で再送信(初期化ハンドシェイクから送り直す) |
| CapsLock → Ctrl | CapsLock キーを Ctrl として扱う。`CapsLock+C` = `Ctrl+C` のような組み合わせにも対応 |
| Win+CapsLock | 本来の CapsLock(大文字ロック)の ON/OFF トグル |
| 状態表示 | トレイアイコンのツールチップに現在状態を表示(`UX8406 Fn Lock: ON` / `OFF`、キーボード未検出時は ` (未接続)` を付加)。自動修正が発生した後は ` / 自動修正 2回 (最終 09:12:30)` のように回数と最終時刻を付加 |

Fn Lock を切り替えた際は、画面上に `Fn Lock: ON` / `Fn Lock: OFF` のツールチップが約 1 秒表示されます。送信に失敗した場合は `Fn Lock送信失敗` が表示されます(自動再適用時は成功しても失敗してもツールチップは出ません。起動後の初回成功時のみ通知します)。

ズレを検知して自動修正した際は、`Fn Lock ズレ検知: OFF → ON に修正`(実機が反対の状態になっていた場合)または `Fn Lock リセット検知: ON を再適用`(デバイス側がリセットされていた場合)のツールチップが約 1.8 秒表示されます。

## 動作要件

- Windows
- [AutoHotkey v2](https://www.autohotkey.com/)(v2.0 以上。スクリプト冒頭で `#Requires AutoHotkey v2.0` を指定)
- ASUS Zenbook Duo UX8406 付属 Bluetooth キーボード(Bluetooth 接続時: VID `0x0B05` / PID `0x1B2D`)

外部 DLL は不要です。Windows 標準の `hid.dll` / `setupapi.dll` / `kernel32.dll` を直接呼び出します。

> **補足**: 本体に装着した USB 接続状態(PID `0x1B2C`)は本スクリプトの対象外です。詳細は [docs/TECHNICAL.md](docs/TECHNICAL.md) を参照してください。

## インストール・使い方

1. [AutoHotkey v2](https://www.autohotkey.com/) をインストールします。
2. `asus_ux8406_fnlock_toggle_shift_ctrl_esc.ahk` をダブルクリックして実行します。
3. タスクトレイに AutoHotkey のアイコンが常駐します。キーボードが接続されていれば Fn Lock が ON になります。

管理者権限は不要です。

### Windows 起動時に自動実行する

1. `Win+R` で「ファイル名を指定して実行」を開き、`shell:startup` と入力して Enter。
2. 開いたスタートアップフォルダに、`asus_ux8406_fnlock_toggle_shift_ctrl_esc.ahk` の **ショートカット** を作成して置きます(スクリプトをコピーするのではなく、右ドラッグ →「ショートカットをここに作成」が簡単です)。

### 終了する

トレイアイコンを右クリック →「Exit」を選びます。

## 設定

ホットキーはスクリプト冒頭の変数で変更できます。

```ahk
global FNLOCK_HOTKEY := "^+Esc"
```

AutoHotkey のホットキー記法(修飾キーの記号):

| 記号 | 意味 |
| --- | --- |
| `^` | Ctrl |
| `+` | Shift |
| `!` | Alt |
| `#` | Win |

例:

```ahk
global FNLOCK_HOTKEY := "#F12"    ; Win + F12
global FNLOCK_HOTKEY := "!+F1"    ; Alt + Shift + F1
```

対象デバイスの VID/PID などの定数も冒頭に定義されていますが、通常は変更不要です。

### ズレ検知の設定

ズレ検知の振る舞いもスクリプト冒頭の変数で変更できます。

```ahk
global DRIFT_CHECK_INTERVAL_MS := 10000   ; ズレ検知の周期(ms)。0 で無効
global NOTIFY_ON_AUTOFIX := true          ; 自動修正時にツールチップ通知
```

| 変数 | 説明 |
| --- | --- |
| `DRIFT_CHECK_INTERVAL_MS` | 実機の Feature Report を読み戻してズレを検査する周期(ミリ秒)。既定は `10000`(約 10 秒)。**`0` にするとズレ検知を無効化**し、従来どおり再接続・スリープ復帰時の再適用だけになります。短くするほど復旧が早くなりますが、HID アクセスの頻度は上がります |
| `NOTIFY_ON_AUTOFIX` | 自動修正したときにツールチップで通知するか。`false` にすると通知だけを止められます(修正自体は引き続き行われ、回数はトレイのツールチップで確認できます) |

## 注意事項

- **`Ctrl+Shift+Esc` は Windows のタスクマネージャー標準ショートカットと競合します。**
  本スクリプトが動作している間、`Ctrl+Shift+Esc` ではタスクマネージャーが開かなくなります。タスクマネージャーは `Ctrl+Alt+Del` の画面や右クリックメニューから起動できますが、どうしても標準ショートカットを維持したい場合は `FNLOCK_HOTKEY` を別のキーに変更してください。
- **CapsLock キーは Ctrl になります。**
  通常の大文字ロックは `Win+CapsLock` で行ってください。この挙動が不要な場合は、スクリプト末尾の `CapsLock::Ctrl` の行をコメントアウト(行頭に `;` を追加)してください。
- **キーボード本体の Fn+Esc で切り替えても、最大約 10 秒以内に元に戻されます。**
  Fn+Esc は ASUS Optimization 等の ASUS 常駐サービスが処理していると見られますが、本スクリプトは自分が把握している状態を正としてズレを戻すため、Fn+Esc による変更は打ち消されます。**Fn Lock の切り替えは本スクリプトのホットキー(`Ctrl+Shift+Esc`)またはトレイメニューから行ってください。** どうしても Fn+Esc を使いたい場合は `DRIFT_CHECK_INTERVAL_MS := 0` でズレ検知を無効にしてください。
- 同一スクリプトの多重起動は `#SingleInstance Force` により、後から起動したものが既存のプロセスを置き換えます。

## FAQ: タッチパッドの ON/OFF はできますか?

本スクリプトでは扱いません。**Windows の標準機能で切り替えられる**ためです。

- 「設定 > Bluetooth とデバイス > タッチパッド」のトグルで ON/OFF を切り替えられます。
- 同じ画面の「マウスの接続時にタッチパッドをオンのままにする」のチェックを外すと、外付けマウス接続時に自動でタッチパッドが無効になります。

スクリプト化を検討した際の調査メモは [docs/TECHNICAL.md](docs/TECHNICAL.md) に残してあります。

## 技術詳細

HID プロトコル、デバイス検出の実装、再適用ロジック、ズレ検知の仕組みなどは [docs/TECHNICAL.md](docs/TECHNICAL.md) を参照してください。プロトコル特定に至るまでの試行錯誤や、ズレ検知を実装した経緯の生ログは [`経緯.txt`](経緯.txt) にあります。
