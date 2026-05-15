# GamepadMapper — 日本語

**GamepadMapper** は、ゲームパッドのボタンやアナログスティックをキーボードキーやマウス操作にリアルタイムでマッピングする macOS メニューバーアプリです。

<p align="center">
  <img src="../Assets/screenshot.png" alt="GamepadMapper スクリーンショット" width="600">
</p>

## 主な機能

- 任意のゲームパッドボタンをキーボードキー、マウスボタン、マウス移動にマッピング
- HID レベル入力でバックグラウンドでも安定動作
- 複数プロファイルの切り替え
- プロファイルごとの感度・デッドゾーン設定
- 多言語 UI：英語、中国語（簡体）、日本語、韓国語、ロシア語、スペイン語
- コントローラー状態のリアルタイム表示
- デバッグログ

## 動作環境

- macOS 14（Sonoma）以降
- Apple Silicon（M1+）または Intel Mac

## ビルド

```bash
git clone https://github.com/huangyebiaoke/GamepadMapper.git
cd GamepadMapper
swift build
```

## 使い方

1. アプリを起動 — メニューバーにゲームパッドアイコンが表示されます
2. Bluetooth または USB でコントローラーを接続
3. メニューバーから設定を開き、**マッピング開始** をクリック
4. マッピングを編集してボタン割当をカスタマイズ
5. 任意のアプリに切り替え — マッピングはバックグラウンドで動作します

---

[← READMEに戻る](../README.md) · [ライセンス](../LICENSE)
