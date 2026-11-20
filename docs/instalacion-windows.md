# Instalar en un iPhone desde Windows

Windows puede servir para firmar e instalar una IPA ya compilada para dispositivo. La compilación necesita macOS con Xcode. La aplicación que se compila para el simulador no sirve para este paso.

## Ruta de prueba con una cuenta gratuita

1. Ejecuta el flujo de GitHub Actions desde la rama de desarrollo y activa `device_ipa`. Descarga el artefacto y extrae la IPA sin firma.
2. En Windows, instala AltServer con los requisitos de Apple indicados por AltStore Classic. Conecta por USB el iPhone, desbloquéalo y pulsa **Confiar**. Instala AltStore Classic siguiendo su guía. Usa tu cuenta de Apple únicamente en el instalador elegido. Sideloadly es otra opción de firma e instalación de una IPA desde Windows.
3. Si iOS lo solicita, activa **Modo de desarrollador** en **Ajustes → Privacidad y seguridad**, reinicia y confirma. Sigue las indicaciones de iOS para confiar en el desarrollador de la app, si aparecen.
4. Abre la IPA con AltStore Classic desde Archivos y mantén el identificador asignado estable entre reinstalaciones. Las aplicaciones de desarrollo firmadas con una cuenta gratuita caducan a los siete días. Renueva la firma según la guía de la herramienta.
5. Empareja las Ray-Ban en Meta AI, habilita el **modo de desarrollador de las gafas** en la app Meta AI y en la app iOS abre **Gafas**. Completa el registro y concede Bluetooth, red local y los permisos de cámara que se soliciten. Prueba en orden **Connect → Start Session → Preview → Capture**. Después abre **Analizar foto**. Prueba también texto y grabación desde **Asistente**. Observa la ruta de micrófono mostrada y verifica dónde se reproduce la respuesta.

## Qué puede impedir que funcione la cámara

El ejemplo oficial necesita el entitlement `com.apple.developer.networking.HotspotConfiguration` para que el iPhone se una a la red Wi-Fi de las gafas y reciba la vista previa. El proyecto conserva ese entitlement y `com.apple.developer.networking.wifi-info`. El perfil de firma y la herramienta de reinstalación deben permitirlos y conservarlos. La re-firma puede eliminarlos o rechazar la instalación. Una instalación que abra o registre las gafas tampoco confirma que la cámara funcione.

Si la re-firma gratuita elimina Hotspot Configuration o no permite aprovisionarlo, queda pendiente la cámara con esa cuenta. No hay una solución gratuita verificada para ese caso. Con acceso a un Mac, Xcode y **Personal Team** permiten diagnosticar directamente los entitlements admitidos y probar la instalación por USB. Si la capacidad exige un equipo con el Apple Developer Program, esa ruta es de pago y queda fuera de este prototipo. TestFlight requiere ese programa.

El SDK documenta Voice Invocations como una función experimental para abrir o poner en primer plano una app mediante «Hey Meta, start {app name}». Requiere registrar y aprobar la app en Wearables Developer Center. Esta versión inicia la grabación con un botón. El modo de desarrollador de Meta permite probar el registro de DAT sin registrar una app de producción.

- [Apple Developer — Comparar membresías](https://developer.apple.com/support/compare-memberships/)
- [Apple Developer — Activar el modo de desarrollador](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [AltStore Classic — Instalación](https://faq.altstore.io/altstore-classic/how-to-install-altstore-classic)
- [Sideloadly — Requisitos y preguntas frecuentes](https://sideloadly.io/)
- [Meta — Configurar el SDK y los permisos de cámara](https://github.com/facebook/meta-wearables-dat-ios/blob/41d79001da0dde6ab3eaccc5e2e60ff850241b60/plugins/mwdat-ios/skills/getting-started/SKILL.md)
- [Meta — Voice Invocations](https://github.com/facebook/meta-wearables-dat-ios/blob/41d79001da0dde6ab3eaccc5e2e60ff850241b60/plugins/mwdat-ios/skills/voice-invocations/SKILL.md)
