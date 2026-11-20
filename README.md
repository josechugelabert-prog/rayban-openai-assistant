# RayBan OpenAI Assistant

Prototipo iOS para iPhone y Ray-Ban Meta. En **Gafas**, la app reutiliza el flujo oficial CameraAccess para registrar las gafas, abrir una sesión, iniciar la vista previa y capturar fotos. En **Asistente**, puedes escribir o grabar una consulta de hasta 30 segundos. Tras capturar una foto, **Analizar foto** abre la consulta con la imagen adjunta. La app envía texto, audio e imagen únicamente cuando pulsas **Enviar a OpenAI**.

La app muestra qué micrófono ha seleccionado iOS. Puede usar el perfil manos libres Bluetooth si está disponible. Escucha la respuesta en la salida de audio que seleccione iOS. La disponibilidad de ambas rutas durante una sesión de cámara requiere una prueba en el dispositivo. Cada envío es una consulta independiente.

## Desarrollo

```sh
node --test server/server.test.mjs
python3 scripts/prepare-ios.py
```

El segundo comando genera `.build/rayban-ios/CameraAccess.xcodeproj` a partir de un commit fijo del ejemplo oficial de Meta. Usa el SDK DAT 1.1.0. Las modificaciones propias están en `ios/` y en el generador. Si vas a regenerar, guarda cualquier cambio local de firma que desees conservar. Puedes usar `META_SDK_CHECKOUT=/ruta/al/sdk` con un checkout limpio del mismo commit.

En macOS con Xcode 26.6:

```sh
xcodebuild build -project .build/rayban-ios/CameraAccess.xcodeproj -scheme CameraAccess \
  -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

El flujo manual de GitHub Actions compila la app, ejecuta las pruebas de CameraAccess con MockDeviceKit y, con la opción `device_ipa`, genera una IPA de dispositivo sin firma.

## Consultas a OpenAI

El servidor local usa Node.js 24 y no tiene dependencias externas. Inyecta `OPENAI_API_KEY` y un `ASSISTANT_TOKEN` aleatorio de al menos 32 caracteres desde el administrador de secretos de tu sistema. Genera un token distinto a tu clave de OpenAI. Ejecuta `node server/server.mjs`. Escucha en `127.0.0.1:8787` por defecto. Para uso desde el iPhone, ponlo detrás de un proxy HTTPS privado con un certificado de confianza en el dispositivo y configura en la app la URL terminada en `/v1/ask` y el token del servidor.

La clave de OpenAI reside en el servidor. iOS guarda el token del servidor en el llavero, ligado a la URL configurada. El servidor valida el token antes de procesar la consulta, limita los tamaños y admite hasta seis peticiones por minuto y una en curso para esta instalación personal. Envía el audio a la API de transcripción y el texto y la foto, si la hay, a Responses con `store: false`. La API tiene su propia política de retención y una consulta real puede generar cargos. Las pruebas usan un proveedor simulado.

[Instalación desde Windows y limitaciones de la cuenta gratuita](docs/instalacion-windows.md)
