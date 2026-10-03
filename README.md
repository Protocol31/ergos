# Ergos · memorias vivas

App de acompañamiento pastoral para Windows y móvil. Memorias cifradas de extremo a extremo, repositorio en Google Drive, doble factor, consentimiento firmado con video y animación de apertura con luz y vitral.

- Arquitectura y decisiones: [docs/ARQUITECTURA.md](docs/ARQUITECTURA.md)
- Carpetas en Drive y sincronización: [docs/ESQUEMA_DRIVE.md](docs/ESQUEMA_DRIVE.md)
- Contrato y consentimiento (plantilla, **requiere revisión de un abogado**): [legal/consentimiento_es.md](legal/consentimiento_es.md)
- Código Flutter: [app/](app/)

## Arrancar

```bash
cd app
flutter create . --platforms=windows,android,ios   # genera carpetas de plataforma sin tocar lib/
flutter pub get
flutter analyze
flutter run -d windows --dart-define=ERGOS_DESKTOP_CLIENT_ID=... --dart-define=ERGOS_DESKTOP_CLIENT_SECRET=...
```

Pon tu arte en `app/assets/intro/figura.png` (fondo transparente) para la animación.
Permisos: Android `CAMERA`, `RECORD_AUDIO`, `USE_BIOMETRIC`; iOS `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSFaceIDUsageDescription`.

## APK automático

Cada push a `main` (o "Run workflow" en la pestaña Actions) compila un APK de prueba. Descárgalo en Actions → última ejecución → Artifacts → `ergos-apk`. Es una versión de prueba firmada con la llave de depuración; no es para publicar.
