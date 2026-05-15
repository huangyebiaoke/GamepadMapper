# GamepadMapper

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-GPL%20v3-green" alt="License">
</p>

<p align="center">
  <img src="Assets/screenshot.png" alt="GamepadMapper 截图" width="600">
</p>

<p align="center">
  <b>macOS 菜单栏应用，可将手柄按键和摇杆实时映射为键盘按键和鼠标操作。</b>
</p>

---

## 功能特性

- 任意手柄按键映射为键盘键、鼠标按键或鼠标移动
- HID 底层输入，后台应用依然可靠响应
- 多方案管理，随时切换不同映射配置
- 每个方案独立配置灵敏度和死区
- 多语言界面：英文、简体中文、日文、韩文、俄文、西班牙文
- 实时手柄状态可视化
- 调试日志，便于排查问题

## 系统要求

- macOS 14 (Sonoma) 或更高版本
- Apple Silicon (M1+) 或 Intel Mac

## 编译

```bash
git clone https://github.com/huangyebiaoke/GamepadMapper.git
cd GamepadMapper
swift build
```

## 使用方法

1. 启动应用 — 菜单栏会出现游戏手柄图标
2. 通过蓝牙或 USB 连接手柄
3. 从菜单栏打开设置，点击 **开始映射**
4. 编辑映射以自定义按键分配
5. 切换到任意应用 — 映射在后台持续生效

## 权限说明

GamepadMapper 需要 **辅助功能** 权限才能向系统发送键盘和鼠标事件。首次启动时应用会引导你完成授权。

---

## 其他语言

- [English](docs/README.en.md)
- [日本語](docs/README.ja.md)
- [한국어](docs/README.ko.md)
- [Русский](docs/README.ru.md)
- [Español](docs/README.es.md)
