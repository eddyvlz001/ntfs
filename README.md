# NTFSMate

Utilidad de barra de menú para macOS (Intel) que detecta USBs al instante,
formatea como NTFS y monta con lectura/escritura a la máxima velocidad que
permite el stack open-source disponible en macOS.

**Target declarado: macOS Sequoia (15.0+).** La arquitectura (FUSE/kext +
`SMAppService`) no usa ninguna API exclusiva de Sequoia — en principio corre
igual en Ventura/Sonoma — pero el deployment target y `LSMinimumSystemVersion`
están fijados en 15.0 porque es el único macOS que este proyecto garantiza y
prueba por ahora. Si más adelante se necesita Ventura de nuevo, basta con bajar
`MACOSX_DEPLOYMENT_TARGET` en `project.yml` y `LSMinimumSystemVersion` en el
Info.plist de la app — no hay refactor de código de por medio.

## Arquitectura

```
┌─────────────────────────┐        XPC (mach service)        ┌───────────────────────────┐
│   NTFSMate.app           │ ───────────────────────────────▶ │  NTFSHelper (root daemon)  │
│   - DiskArbitration      │                                   │  - diskutil unmountDisk    │
│     (detección USB)      │ ◀─────────────────────────────── │  - mkntfs (formatear)      │
│   - SwiftUI menú         │        resultado / error          │  - ntfs-3g (montar)        │
└─────────────────────────┘                                   └───────────────────────────┘
                                                                         │
                                                                         ▼
                                                        macFUSE (kext clásico, Intel)
                                                        + ntfs-3g como motor NTFS R/W
```

**Por qué este stack:**

- **Detección instantánea de USB** → `DiskArbitration` (`DARegisterDiskAppearedCallback`).
  Es push-based: no hay polling de `/Volumes`, así que una unidad nueva se reporta
  en el mismo tick de runloop en que el kernel la anuncia.
- **Motor NTFS (lectura/escritura)** → `macFUSE` + `ntfs-3g`. En Intel, macFUSE todavía
  puede cargar como **kernel extension clásica** (no como System Extension), que es
  la ruta rápida: evita el overhead adicional de IPC que tiene el modelo de extensión
  de sistema que Apple fuerza en Apple Silicon. Por eso este proyecto fija
  `ARCHS: x86_64` — en Apple Silicon perderías la ventaja de velocidad que es la
  razón de ser de esta elección.
- **Operaciones privilegiadas** (formatear, montar con `allow_other`) → un daemon
  separado (`NTFSHelper`) registrado vía `SMAppService` (disponible desde macOS 13,
  sin usar la API legacy `SMJobBless`). La app nunca ejecuta comandos de disco
  directamente; todo pasa por XPC al helper que corre como root.

## Rendimiento de transferencia

Las opciones de montaje en `HelperDelegate.mountNTFS` (`kernel_cache,auto_cache,
big_writes,blksize=1048576,noatime`) son la parte que más impacta la velocidad real:

- `kernel_cache` + `auto_cache`: deja que el kernel cachee páginas en vez de
  hacer un round-trip al daemon FUSE en cada lectura.
- `big_writes`: eleva el buffer de escritura muy por encima del límite viejo de
  4K de FUSE.
- `blksize=1048576`: bloques de 1 MB reducen drásticamente la cantidad de
  syscalls en transferencias secuenciales grandes (el caso típico de backups/medios).

Aun con esto, FUSE+ntfs-3g no va a igualar a un driver nativo en el kernel (que es
lo que realmente vende Paragon). Si en el futuro se necesita más velocidad, las
opciones son: (a) un driver NTFS comercial con licencia (Tuxera), o (b) escribir un
driver propio — ambas son inversiones de ingeniería serias, no algo incremental.

## Licenciamiento — importante

`ntfs-3g` es **GPLv2**. Este proyecto no lo empaqueta dentro del `.app` — el
usuario lo instala por separado vía Homebrew (`Scripts/install-dependencies.sh`)
y NTFSMate simplemente invoca los binarios ya instalados en el sistema. Esto evita
convertir NTFSMate en una obra derivada de GPL. **No cambies esto a "bundlear
ntfs-3g dentro del .app"** sin antes resolver el cumplimiento de la licencia
(distribución del código fuente correspondiente, etc.) con un abogado.

## Compilar

Requiere macOS Intel + Xcode. Este scaffold no se puede compilar ni probar desde
este contenedor Linux — fue escrito aquí, pero el build real debe hacerse en el Mac.

```sh
brew install xcodegen
./Scripts/install-dependencies.sh   # macFUSE + ntfs-3g
xcodegen generate
open NTFSMate.xcodeproj
```

Al compilar y correr por primera vez, macOS pedirá aprobar el daemon
`NTFSHelper` en Ajustes del Sistema > Privacidad y Seguridad.

## Qué falta para producción (no cubierto en este scaffold)

- Firma de código + notarización (obligatorio para que macFUSE y el helper
  carguen sin Gatekeeper bloqueando todo).
- UI de progreso real durante el formateo (`mkntfs` por ahora corre sin parseo
  de progreso).
- Manejo de desconexión abrupta durante escritura (unmount forzado / fsck).
- Tests. No hay ninguno todavía.
