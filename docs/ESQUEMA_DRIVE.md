# Esquema de carpetas en Google Drive

Lo crea la app automáticamente (`DriveSyncService.ensurePersonFolders`). Alcance OAuth `drive.file`: la app solo ve lo que ella misma creó.

```
Mi unidad/
└── Ergos/
    ├── _meta/
    │   └── salt.json                  sal pública de Argon2id (permite abrir en otro equipo)
    ├── feligreses/
    │   └── <uuid-persona>/            UUID, nunca el nombre (privacidad aunque alguien vea Drive)
    │       ├── perfil.erg             ficha completa, JSON cifrado AES-256-GCM
    │       ├── memorias/
    │       │   └── <uuid-memoria>.erg una memoria = un archivo (sincroniza solo lo que cambió)
    │       └── consentimiento/
    │           ├── consentimiento_v1.pdf.erg   PDF con texto, firma, fecha y hash SHA-256
    │           ├── firma_v1.png.erg
    │           └── video_v1.ergv       video cifrado por fragmentos de 1 MiB
    └── respaldos/                      instantáneas completas cifradas (futuro)
```

Cada archivo guarda en `appProperties` solo `updatedAt` (ms) para decidir qué bajar sin descargar.
El AAD de cada blob (`ergos/v1/<tipo>/<id>`) impide intercambiar archivos entre registros.

## Sincronización bidireccional

1. **Subir**: filas con `dirty=1` → JSON → cifrar → crear/actualizar archivo → `dirty=0`.
2. **Bajar**: lista `feligreses/*`; por cada archivo con `updatedAt` mayor al conocido, descargar, descifrar, aplicar si `updated_at` remoto > local.
3. **Conflictos**: gana el último en escribir por registro (last-writer-wins). Dos registros distintos nunca chocan porque son archivos distintos.
4. **Borrado**: tombstone (`deleted=1`) que también se sincroniza; la eliminación física de la carpeta se hace desde "Derecho de supresión" (pendiente de implementar: borrar carpeta Drive + filas locales).
5. Un archivo que no descifra (llave errónea o manipulado) se ignora; nunca se aplica.
