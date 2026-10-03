# Ergos · Arquitectura (Flutter, Windows + Android/iOS)

## 1. Decisiones

| Tema | Decisión | Por qué |
|---|---|---|
| Framework | **Flutter** | Un solo código para Windows y móvil; renderizado propio (Skia/Impeller) ideal para el vitral y la luz; shaders GLSL nativos. |
| Base de datos | **SQLite cifrada (SQLCipher)** local + **FTS5** | Búsqueda en milisegundos y sin internet. Drive es respaldo/sincronía, no la base. |
| Nube | **Google Drive** (`drive.file`), blobs cifrados por registro | Drive nunca ve contenido, nombres ni videos. |
| Llaves | **Frase maestra → Argon2id (64 MiB, 3 it.) → HKDF** → llave de BD y llave de blobs | La llave nunca se guarda ni sube. Si Google o el PC son comprometidos, los datos siguen ilegibles. |
| 2FA | **TOTP (RFC 6238)** + biometría local (huella/rostro/Windows Hello) | Biometría reemplaza *escribir* la frase, no el TOTP. |
| Estado | Riverpod | Sesión solo en memoria; bloquear la destruye. |

## 2. Modelo de amenazas (qué sí y qué no protege)

- Protege contra: robo del PC/celular apagado, acceso a Drive por terceros o por Google, manipulación de archivos (GCM autentica), fuerza bruta local (espera exponencial tras 5 fallos).
- **No** protege contra: malware con la app desbloqueada, o que la frase maestra esté escrita junto al equipo.
- El TOTP es una puerta de la app; la barrera criptográfica real es la frase. Honestamente: si pierdes la frase, **no hay recuperación**. Imprime la hoja de recuperación.
- El video grabado pasa primero por un archivo temporal en claro; se cifra y se sobrescribe/borra al sellar (en SSD el borrado físico no está garantizado: usar disco con cifrado de sistema, BitLocker/FileVault/cifrado Android).

## 3. Estructura

```
app/
├─ pubspec.yaml
├─ shaders/ergos_light.frag        shader de la luz (GLSL)
├─ assets/intro/figura.png         (tú la pones) figura con fondo transparente
├─ assets/legal/consentimiento_es.md
└─ lib/
   ├─ main.dart · app.dart · providers.dart
   ├─ core/{theme, crypto, auth}
   ├─ data/{db, models, repository, sync}
   ├─ features/{intro, auth, dashboard, people, memories, consent, settings}
   └─ widgets/{stained_glass, aura_background, form_bits}
```

## 4. Interfaz del dashboard

- **Inicio**: buscador grande (FTS5 con prefijos, sin acentos, ranking BM25, fragmentos resaltados), 4 cifras, seguimientos a 14 días, memorias recientes.
- **Feligreses**: lista filtrable; cada ficha con consentimiento visible (sin consentimiento firmado no se pueden crear memorias).
- **Ficha**: relación con Dios, vida espiritual, batallas, entorno, variables emocionales, fortalezas; línea de tiempo de memorias.
- **Memoria**: título, tipo (sesión, discipulado, liderazgo, ministerio, evento, oración), resumen, texto, variables, oración, acuerdos, próximos pasos, seguimiento, etiquetas.
- Escritorio: barra lateral; móvil: barra inferior. Máx. 1180 px de ancho.
- Consultas ejemplo: `ansiedad trabajo`, `duelo padre`, `batalla pornografía` → memorias y personas ordenadas por relevancia.

## 5. Configurar Google Drive (una vez)

1. Google Cloud Console → proyecto nuevo → habilitar **Google Drive API**.
2. Pantalla de consentimiento OAuth (externa, en prueba; añade el correo del pastor como usuario de prueba). Alcance: `.../auth/drive.file`.
3. Credenciales: **ID de cliente de escritorio** (Windows) y **Android/iOS** (móvil, con SHA-1 / bundle id).
4. Windows: `flutter run -d windows --dart-define=ERGOS_DESKTOP_CLIENT_ID=... --dart-define=ERGOS_DESKTOP_CLIENT_SECRET=...`
   (el "secret" de apps de escritorio no es confidencial por diseño de Google).

## 6. Animación de apertura: la mejor forma de hacerla

Evaluadas: Lottie (vectorial, sin luz volumétrica real), WebGL en WebView (peso y latencia), canvas 2D (sin plasma). **Elegido: pipeline GPU de Flutter con tres capas:**

1. **Fragment shader GLSL** (`ergos_light.frag`): núcleo incandescente, plasma con ruido fractal (fbm deformado), rayos que respiran y onda de sanidad. Corre en GPU a 60/120 fps en Windows y móvil, resolución nativa.
2. **CustomPainter**: polvo cósmico con parallax, destellos en cruz y el **vitral procedural** (celdas Voronoi con emplomado que se dibuja en ondas desde la mano).
3. **Figura**: PNG/WebP con fondo transparente (tu arte, o ilustración de encargo) entrando desde la niebla con máscara de degradado. La luz del shader se ancla en la mano (`_hand` en `intro_screen.dart`).

Guion de 7 s: polvo cósmico (0–1.4) → figura y encendido de la luz con pulso háptico (1.2–3.6) → la luz enciende el vitral (3.2–5.4) → ERGOS con tracking que se cierra (5.2–6.4) → fundido al acceso. Toque o "Omitir" salta. Si el shader no carga, hay degradado de respaldo. Respeta "reducir animaciones" en el fondo.

Para subir aún más la calidad: render previo de la figura con *volumetric light* en Blender y usarlo como secuencia de video (`video_player`) bajo el shader; o añadir bloom con un segundo pase de shader.

## 7. Pendientes conocidos (honestos)

- **No pude compilar en este entorno (no hay Flutter instalado).** El código está escrito con las APIs de los paquetes, pero ejecuta `flutter pub get && flutter analyze` y corrige versiones/firmas menores (en especial `sqlcipher_flutter_libs` y `local_auth`, que cambian de API).
- Hoja de recuperación imprimible, derecho de supresión (borrado físico en Drive), respaldos completos, pruebas unitarias del cifrado y de la sincronización.
- Pantalla de vínculos familiares/liderazgo (la tabla `person_link` ya existe).
- Revisión legal del contrato y, si el pastor ejerce como psicólogo, cumplir la normativa de historia clínica de su país.
