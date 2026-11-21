# OpenVision en iPhone 16 Pro desde Windows

La guía original indica que OpenVision se distribuye como código fuente. La release oficial v2.14.0 muestra únicamente ZIP y TAR.GZ del código. Este repositorio prepara una compilación de prueba de OpenVision para iOS 18 o posterior.

- [Guía upstream](https://github.com/rayl15/OpenVision/blob/b1e2350d0b37b7ca273f6e3c505dec254bd78370/SETUP.md)
- [Archivos de v2.14.0](https://github.com/rayl15/OpenVision/releases/expanded_assets/v2.14.0)

## Descargar y firmar

1. Entra en **Actions**, selecciona la ejecución de `test/openvision-ios` y comprueba el resultado de **OpenVision (device)**. Si terminó correctamente, descarga **OpenVision-iOS-arm64-unsigned** en **Artifacts** mientras esté disponible. Extrae del ZIP `OpenVision-unsigned.ipa`.
2. Instala Sideloadly para Windows y los componentes de Apple que indica su guía. Conecta el iPhone por USB, desbloquéalo y acepta **Confiar**. Abre Sideloadly, selecciona el dispositivo y carga la IPA.
3. Usa la modalidad de firma con tu cuenta gratuita de Apple en Sideloadly. Introduce tus credenciales solo en el flujo de autenticación del instalador. Mantén el mismo identificador de app al volver a firmar. Una firma gratuita dura normalmente siete días. Esta IPA se compila para un dispositivo arm64 y necesita pasar por la firma y el aprovisionamiento antes de que iOS la pueda abrir.
4. Si iOS lo solicita, activa **Modo de desarrollador** en **Ajustes → Privacidad y seguridad**, reinicia y confirma. Si solicita confianza adicional, revisa **Ajustes → General → VPN y gestión de dispositivos**. Abre OpenVision.

- [Sideloadly](https://sideloadly.io/)
- [Apple — Membresías y aprovisionamiento gratuito](https://developer.apple.com/support/compare-memberships/)
- [Apple — Modo de desarrollador](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [Apple — Capacidades disponibles en iOS](https://developer.apple.com/help/account/reference/supported-capabilities-ios)

## Emparejar y probar cámara

1. Comprueba que las gafas están emparejadas y actualizadas en Meta AI y que su modo de desarrollador sigue activado.
2. En OpenVision, abre **Settings → Glasses → Register**. Completa el flujo de Meta AI y vuelve a la app. Autoriza Bluetooth en iOS y el permiso de cámara solicitado por Meta. Para el transporte Wi-Fi, acepta también el acceso a red local y la conexión a la red que ofrezcan las gafas. Para conversación, concede micrófono y reconocimiento de voz.
3. Comprueba que el dispositivo aparece conectado. Inicia la cámara desde los controles de **Glasses** y prueba una foto. Verifica que la imagen proviene realmente de las gafas, porque OpenVision también tiene una ruta de cámara del iPhone.
4. La IPA de CI conserva la configuración de ejemplo upstream, que permite compilar y carece de valores de registro válidos. Para registrar las gafas, el procedimiento de OpenVision es crear tu propia app en Wearables Developer Center, configurar **Camera access**, el Apple Team ID y el identificador de la app, e instalar o actualizar la app de gafas desde Settings. Para ese flujo el build debe corresponder a tu firma y llevar el Meta App ID y Client Token de tu proyecto. La IPA de CI usa los valores de pruebas.

OpenVision declara el SDK oficial DAT **0.9.0** y usa `DeviceSession → addCamera → camera.stream`. Su equipo reporta comprobaciones con Ray-Ban Meta Gen 1 y Gen 2. La compilación del simulador no puede confirmar el registro real, la cámara, el firmware ni la ruta de audio HFP. La generación exacta y el firmware de tus gafas se comprueban en Meta AI.

- [OpenVision — Compatibilidad reportada](https://github.com/rayl15/OpenVision/blob/b1e2350d0b37b7ca273f6e3c505dec254bd78370/CHANGELOG.md)
- [Meta DAT 0.9.0 — Cambios](https://github.com/facebook/meta-wearables-dat-ios/blob/0.9.0/CHANGELOG.md)
- [Meta — Configuración Wi-Fi en CameraAccess](https://github.com/facebook/meta-wearables-dat-ios/blob/41d79001da0dde6ab3eaccc5e2e60ff850241b60/plugins/mwdat-ios/skills/getting-started/SKILL.md)

## Cómo reconocer el límite de la cuenta gratuita

Una instalación exitosa solo confirma que iOS aceptó la firma. Para la ruta de cámara por Wi-Fi, el perfil y la firma final deben contener `com.apple.developer.networking.HotspotConfiguration`. El proyecto OpenVision original no declara ese entitlement. La ruta Wi-Fi documentada en CameraAccess también declara acceso a red local y Bonjour. OpenVision no garantiza esa misma ruta con su configuración upstream. Sideloadly firma a partir de las capacidades que admite el perfil Apple. Una IPA sin firma no puede transferir por sí sola esas capacidades al perfil gratuito.

Si el instalador devuelve un error de entitlement o el perfil omite Hotspot Configuration, la ruta Wi-Fi de las gafas queda bloqueada por el aprovisionamiento. Se puede comprobar el resultado en un Mac con `codesign -d --entitlements - OpenVision.app` sobre la app **ya firmada**. Una capacidad ausente tampoco permite dar por probada una ruta alternativa por Bluetooth. El entitlement **Increased Memory Limit** del proyecto upstream afecta a modelos locales grandes y es independiente de la cámara. La app puede instalarse sin ese permiso si el firmador lo retira y el resto de la firma es válido, pero esos modelos pueden quedarse sin memoria.

## Seleccionar ChatGPT

En **Settings → AI → OpenAI**, OpenVision ofrece **Sign in with ChatGPT**. Esa opción usa el flujo de Codex y un backend interno de ChatGPT desde una app de terceros. La disponibilidad con una cuenta gratuita y su funcionamiento actual requieren una prueba real. El login de la suscripción cubre texto y fotos según upstream. La función **Realtime** requiere una clave con acceso a la API y puede generar cargos. Para comprobar la app sin costes de API, se puede seleccionar un backend local compatible. Un backend local no es ChatGPT.

- [Implementación de ChatGPT en OpenVision](https://github.com/rayl15/OpenVision/blob/b1e2350d0b37b7ca273f6e3c505dec254bd78370/OpenVision/Services/AIBackend/ChatGPTSubscription.swift)
