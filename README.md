# ASUS Zenbook Duo UX8406 Fn Lock Toggle

ASUS Zenbook Duo UX8406 付属の Bluetooth キーボードの **Fn Lock** を、Windows 上のホットキーから切り替える AutoHotkey v2 常駐スクリプトです。

## 何を解決するか

UX8406 の付属キーボードは、Bluetooth 接続時に Windows 標準の機能では Fn Lock の状態を制御できません(ファンクションキー行がメディアキーのままになる/意図しない状態で固定される)。

本スクリプトは対象キーボードの HID デバイスを自動検出し、**HID Feature Report を直接送信**することで Fn Lock を任意に切り替えます。実機で動作確認済みです。

- スクリプト本体: [`asus_ux8406_fnlock_toggle_shift_ctrl_esc.ahk`](asus_ux8406_fnlock_toggle_shift_ctrl_esc.ahk)

## 機能

| 機能 | 説明 |
| --- | --- |
| Fn Lock トグル | `Ctrl+Shift+Esc` で ON/OFF を切り替え。トレイアイコンのダブルクリック、またはトレイメニューの「Fn Lock切り替え」でも同じ動作 |
| 起動時の自動設定 | 起動時に Fn Lock を **ON** にして既知の状態へ揃える。キーボード未接続でもエラーダイアログは出さず、バックグラウンドで接続されるまでリトライ |
| 自動再適用 | Bluetooth 再接続・スリープ復帰を検知して、現在の Fn Lock 状態を自動的に再送信(`WM_DEVICECHANGE` / `WM_POWERBROADCAST` を監視) |
| CapsLock → Ctrl | CapsLock キーを Ctrl として扱う。`CapsLock+C` = `Ctrl+C` のような組み合わせにも対応 |
| Win+CapsLock | 本来の CapsLock(大文字ロック)の ON/OFF トグル |
| 状態表示 | トレイアイコンのツールチップに現在状態を表示(`UX8406 Fn Lock: ON` / `OFF`、キーボード未検出時は ` (未接続)` を付加) |

Fn Lock を切り替えた際は、画面上に `Fn Lock: ON` / `Fn Lock: OFF` のツールチップが約 1 秒表示されます。送信に失敗した場合は `Fn Lock送信失敗` が表示されます(自動再適用時は成功しても失敗してもツールチップは出ません。起動後の初回成功時のみ通知します)。

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

## 注意事項

- **`Ctrl+Shift+Esc` は Windows のタスクマネージャー標準ショートカットと競合します。**
  本スクリプトが動作している間、`Ctrl+Shift+Esc` ではタスクマネージャーが開かなくなります。タスクマネージャーは `Ctrl+Alt+Del` の画面や右クリックメニューから起動できますが、どうしても標準ショートカットを維持したい場合は `FNLOCK_HOTKEY` を別のキーに変更してください。
- **CapsLock キーは Ctrl になります。**
  通常の大文字ロックは `Win+CapsLock` で行ってください。この挙動が不要な場合は、スクリプト末尾の `CapsLock::Ctrl` の行をコメントアウト(行頭に `;` を追加)してください。
- 同一スクリプトの多重起動は `#SingleInstance Force` により、後から起動したものが既存のプロセスを置き換えます。

## FAQ: タッチパッドの ON/OFF はできますか?

本スクリプトでは扱いません。**Windows の標準機能で切り替えられる**ためです。

- 「設定 > Bluetooth とデバイス > タッチパッド」のトグルで ON/OFF を切り替えられます。
- 同じ画面の「マウスの接続時にタッチパッドをオンのままにする」のチェックを外すと、外付けマウス接続時に自動でタッチパッドが無効になります。

スクリプト化を検討した際の調査メモは [docs/TECHNICAL.md](docs/TECHNICAL.md) に残してあります。

## 技術詳細

HID プロトコル、デバイス検出の実装、再適用ロジックなどは [docs/TECHNICAL.md](docs/TECHNICAL.md) を参照してください。
