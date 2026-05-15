# GamepadMapper

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-GPL%20v3-green" alt="License">
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#中文">中文</a> · <a href="#日本語">日本語</a> · <a href="#한국어">한국어</a> · <a href="#русский">Русский</a> · <a href="#español">Español</a>
</p>

---

## English

**GamepadMapper** is a macOS menu bar app that maps gamepad buttons and analog sticks to keyboard keys and mouse movements in real time.

### Features

- Map any gamepad button to a keyboard key, mouse button, or mouse movement
- Real-time HID-level input for reliable background operation
- Multi-profile support — switch between different mappings instantly
- Per-profile sensitivity and deadzone configuration
- Multi-language UI: English, 简体中文, 日本語, 한국어, Русский, Español
- Live controller status visualization
- Debug log for troubleshooting

### Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1+) or Intel Mac

### Build

```bash
git clone https://github.com/huangyebiaoke/GamepadMapper.git
cd GamepadMapper
swift build
```

### Usage

1. Launch the app — it appears as a gamepad icon in the menu bar
2. Connect your gamepad via Bluetooth or USB
3. Open Settings from the menu bar and click **Start Mapping**
4. Edit mappings to customize button-to-key assignments
5. Switch to any app — mapping works in the background

### Permissions

GamepadMapper requires **Accessibility** permission to send keyboard and mouse events system-wide. The app will guide you through granting permission on first launch.

---

## 中文

**GamepadMapper** 是一款 macOS 菜单栏应用，可将手柄按键和摇杆实时映射为键盘按键和鼠标操作。

### 功能特性

- 任意手柄按键映射为键盘键、鼠标按键或鼠标移动
- HID 底层输入，后台应用依然可靠响应
- 多方案管理，随时切换不同映射配置
- 每个方案独立配置灵敏度和死区
- 多语言界面：英文、简体中文、日文、韩文、俄文、西班牙文
- 实时手柄状态可视化
- 调试日志便于排查问题

### 系统要求

- macOS 14 (Sonoma) 或更高版本
- Apple Silicon (M1+) 或 Intel Mac

### 编译

```bash
git clone https://github.com/huangyebiaoke/GamepadMapper.git
cd GamepadMapper
swift build
```

### 使用方法

1. 启动应用 — 菜单栏会出现游戏手柄图标
2. 通过蓝牙或 USB 连接手柄
3. 从菜单栏打开设置，点击 **开始映射**
4. 编辑映射以自定义按键分配
5. 切换到任意应用 — 映射在后台持续生效

### 权限说明

GamepadMapper 需要 **辅助功能** 权限才能向系统发送键盘和鼠标事件。首次启动时应用会引导你完成授权。

---

## 日本語

**GamepadMapper** は、ゲームパッドのボタンやアナログスティックをキーボードキーやマウス操作にリアルタイムでマッピングする macOS メニューバーアプリです。

### 主な機能

- 任意のゲームパッドボタンをキーボードキー、マウスボタン、マウス移動にマッピング
- HID レベル入力でバックグラウンドでも安定動作
- 複数プロファイルの切り替え
- プロファイルごとの感度・デッドゾーン設定
- 多言語 UI：英語、中国語（簡体）、日本語、韓国語、ロシア語、スペイン語
- コントローラー状態のリアルタイム表示
- デバッグログ

### 動作環境

- macOS 14（Sonoma）以降
- Apple Silicon（M1+）または Intel Mac

### ビルド

```bash
git clone https://github.com/huangyebiaoke/GamepadMapper.git
cd GamepadMapper
swift build
```

### 使い方

1. アプリを起動 — メニューバーにゲームパッドアイコンが表示されます
2. Bluetooth または USB でコントローラーを接続
3. メニューバーから設定を開き、**マッピング開始** をクリック
4. マッピングを編集してボタン割当をカスタマイズ
5. 任意のアプリに切り替え — マッピングはバックグラウンドで動作します

---

## 한국어

**GamepadMapper** 는 게임패드 버튼과 아날로그 스틱을 키보드 키 및 마우스 동작으로 실시간 매핑하는 macOS 메뉴 표시줄 앱입니다.

### 주요 기능

- 게임패드 버튼을 키보드 키, 마우스 버튼, 마우스 이동으로 매핑
- HID 수준 입력으로 백그라운드에서도 안정적으로 동작
- 다중 프로필 지원 — 매핑 구성 간 즉시 전환
- 프로필별 감도 및 데드존 설정
- 다국어 UI: 영어, 중국어(간체), 일본어, 한국어, 러시아어, 스페인어
- 실시간 컨트롤러 상태 시각화
- 디버그 로그

### 시스템 요구 사항

- macOS 14(Sonoma) 이상
- Apple Silicon(M1+) 또는 Intel Mac

### 빌드

```bash
git clone https://github.com/huangyebiaoke/GamepadMapper.git
cd GamepadMapper
swift build
```

### 사용법

1. 앱 실행 — 메뉴 표시줄에 게임패드 아이콘이 표시됩니다
2. Bluetooth 또는 USB로 컨트롤러 연결
3. 메뉴 표시줄에서 설정을 열고 **매핑 시작** 클릭
4. 매핑을 편집하여 버튼 할당 사용자 지정
5. 다른 앱으로 전환 — 매핑은 백그라운드에서 계속 작동합니다

---

## Русский

**GamepadMapper** — приложение в строке меню macOS, которое в реальном времени сопоставляет кнопки геймпада и аналоговые стики с клавишами клавиатуры и движениями мыши.

### Возможности

- Сопоставление кнопок геймпада с клавишами клавиатуры, кнопками мыши или движением курсора
- Ввод на уровне HID — работает даже в фоновом режиме
- Поддержка нескольких профилей
- Настройка чувствительности и мёртвой зоны для каждого профиля
- Многоязычный интерфейс: английский, китайский (упр.), японский, корейский, русский, испанский
- Визуализация состояния контроллера в реальном времени
- Журнал отладки

### Требования

- macOS 14 (Sonoma) или новее
- Apple Silicon (M1+) или Intel Mac

### Сборка

```bash
git clone https://github.com/huangyebiaoke/GamepadMapper.git
cd GamepadMapper
swift build
```

### Использование

1. Запустите приложение — в строке меню появится значок геймпада
2. Подключите геймпад по Bluetooth или USB
3. Откройте настройки из строки меню и нажмите **Начать маппинг**
4. Настройте сопоставление кнопок
5. Переключитесь на любое приложение — маппинг работает в фоне

---

## Español

**GamepadMapper** es una aplicación de barra de menú para macOS que mapea los botones del gamepad y los sticks analógicos a teclas del teclado y movimientos del ratón en tiempo real.

### Características

- Mapear cualquier botón del gamepad a tecla, botón del ratón o movimiento del cursor
- Entrada a nivel HID — funciona incluso en segundo plano
- Soporte de múltiples perfiles
- Configuración de sensibilidad y zona muerta por perfil
- Interfaz multilingüe: inglés, chino simplificado, japonés, coreano, ruso, español
- Visualización del estado del controlador en tiempo real
- Registro de depuración

### Requisitos

- macOS 14 (Sonoma) o posterior
- Apple Silicon (M1+) o Intel Mac

### Compilación

```bash
git clone https://github.com/huangyebiaoke/GamepadMapper.git
cd GamepadMapper
swift build
```

### Uso

1. Inicia la app — aparecerá un ícono de gamepad en la barra de menú
2. Conecta tu gamepad por Bluetooth o USB
3. Abre Configuración desde la barra de menú y haz clic en **Iniciar mapeo**
4. Edita los mapeos para personalizar la asignación de botones
5. Cambia a cualquier aplicación — el mapeo funciona en segundo plano

---

## License

This project is licensed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE) for details.

## Contributing

Issues and pull requests are welcome! Feel free to open an issue to report bugs, suggest features, or ask questions.
