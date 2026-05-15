# GamepadMapper — Español

**GamepadMapper** es una aplicación de barra de menú para macOS que mapea los botones del gamepad y los sticks analógicos a teclas del teclado y movimientos del ratón en tiempo real.

<p align="center">
  <img src="../Assets/screenshot.png" alt="Captura de GamepadMapper" width="600">
</p>

## Características

- Mapear cualquier botón del gamepad a tecla, botón del ratón o movimiento del cursor
- Entrada a nivel HID — funciona incluso en segundo plano
- Soporte de múltiples perfiles
- Configuración de sensibilidad y zona muerta por perfil
- Interfaz multilingüe: inglés, chino simplificado, japonés, coreano, ruso, español
- Visualización del estado del controlador en tiempo real
- Registro de depuración

## Requisitos

- macOS 14 (Sonoma) o posterior
- Apple Silicon (M1+) o Intel Mac

## Compilación

```bash
git clone https://github.com/huangyebiaoke/GamepadMapper.git
cd GamepadMapper
swift build
```

## Uso

1. Inicia la app — aparecerá un ícono de gamepad en la barra de menú
2. Conecta tu gamepad por Bluetooth o USB
3. Abre Configuración desde la barra de menú y haz clic en **Iniciar mapeo**
4. Edita los mapeos para personalizar la asignación de botones
5. Cambia a cualquier aplicación — el mapeo funciona en segundo plano

---

[← Volver al README](../README.md) · [Licencia](../LICENSE)
