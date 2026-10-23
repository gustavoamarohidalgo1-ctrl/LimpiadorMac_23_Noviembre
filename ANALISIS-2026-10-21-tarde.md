# Análisis profundo de LimpiadorMac (tarde)

- Fecha: 21 de octubre de 2026, tarde · Versión analizada: 3.0 (build 4), con los cambios de hoy · Análisis anterior: [ANALISIS-2026-10-21.md](ANALISIS-2026-10-21.md) (esta mañana)

## Resumen ejecutivo

Desde esta mañana has añadido unas 640 líneas en 8 archivos:

- la categoría **«Sin uso»**, que sustituye a «Apps que no usas» y ahora mira también carpetas, archivos y juegos de Steam;
- **compactar bases SQLite**;
- las **copias sobrantes del entorno de Codex**;
- cachés nuevas: Adobe, DaVinci, Lightroom, iMovie, Final Cut, Unreal, Steam, Whisper y tres de Chromium.

Lo nuevo está bien protegido en lo esencial:

- «Sin uso» nunca se marca sola. Siempre es Revisar o Cuidado y siempre va a la Papelera, también con «Eliminar definitivamente». Lo que el filtro de días oculta no se puede marcar ni entra en el plan.
- La compactación SQLite no pierde datos. VACUUM aguantó 20 cortes con SIGKILL sin dañar la base y conservó los números de fila en 15 variantes de tablas con índice. Cuando otro programa tenía la base abierta, se apartó sin tocar nada.
- Las copias sobrantes de Codex se comparan de verdad con el entorno activo: los 2,03 GB que salen en tu Mac son correctos. Además, no se marcan solas.

Los problemas de lo nuevo son de **precisión**, no de borrado directo:

- **La señal de uso es débil.**
  - macOS solo anota una lectura si el archivo cambió desde la anterior. Una carpeta que lees a diario sin cambiarla puede salir como «Hace 2 meses» (ME43).
  - El propio análisis «usa» lo que lee: las huellas de duplicados y las muestras de compresión ponen la fecha de acceso a hoy. En la pasada siguiente, eso desaparece (ME44).
  - Basta un `.DS_Store` reciente para que una carpeta entera no salga. Le pasa a tu `Documents/Codex` (ME45).
- **«Sin uso» puede ofrecer cosas delicadas con un motivo genérico:**
  - el catálogo de Lightroom suelto (AL17);
  - apps con extensiones de sistema dentro (ME49);
  - cosas dentro de carpetas sincronizadas con otra nube (ME52).
- **La compactación tiene tres fallos:**
  - no ve el archivo `-wal` (ME55);
  - su filtro de nombres se salta las tablas «sqlite…» (ME56);
  - su espacio se cuenta dos veces en el total. En tu Mac, **1,51 GB de los 17,25 GB «encontrados» están contados dos veces** (ME57).

La revisión fresca del código que no cambió hoy sí encontró riesgos de pérdida definitiva, porque «Liberar al máximo» sigue borrando todo lo Seguro sin Papelera:

- **Un `.log` de 20 MB o más dentro de una carpeta «logs» de tus carpetas sale Seguro y preseleccionado a los 7 días**, con «Nada importante». Un registro de un entrenamiento o de un experimento se borra para siempre (CR4).
- En /tmp, se salta la comprobación de resultados únicos una carpeta que empiece por `npm-`, `pip-` o `uv-`, o que solo tenga cuadernos, `.7z` o `.parquet` (AL13).
- El repositorio de Maven sale Seguro aunque guarde artefactos que instalaste tú (AL14).
- En «Liberar al máximo», los simuladores y los comandos (Docker) marcados a mano se borran sin Papelera, mientras la hoja dice que «lo que no es Seguro va a la Papelera» (AL15).

**En tu Mac, hoy:** el diagnóstico real, de solo lectura, encontró 17,25 GB y preseleccionó 41,6 MB: el `brew cleanup` de glib y la caché de Música, que sí se regeneran. «Sin uso» sale con 0. Es correcto salvo por `Documents/Codex`: casi todo lo viejo pesa menos de 1 MB y lo grande tiene uso reciente. No hay registros grandes en carpetas «logs», ni Maven, ni Steam, ni Lightroom, ni simuladores.

Dos avisos:

- Desde las 16:06 de hoy, una instalación fallida de Codex de 302 MB ya sale preseleccionada como Seguro, sin comprobar que Codex no la use (BA17).
- Hacia mañana, Microsoft Excel (2,6 GB) aparecerá en «Sin uso». Llegó hace casi una semana, Spotlight no tiene registro de que la hayas abierto y su contenedor no cambia desde hace unos 52 días.

Hasta que se arreglen:

- en «Sin uso», revisa uno a uno y no uses «Todo»;
- antes de «Liberar al máximo», desmarca lo de /tmp, Registros, Maven y los simuladores;
- no uses «Solo lo seguro» en las cachés, porque hoy marca más cosas que no deberían ir sin revisar (ME27 empeora);
- después de una limpieza grande, no mandes nada a la Papelera desde el Explorador hasta decidir si la deshaces (AL16).

**Nota global: 5,5/10**, igual que esta mañana. Lo nuevo de hoy, por separado: 6/10.

## Actualización: etapa 1 arreglada (CR4, AL13, AL14 y AL15)

Después de este informe se arreglaron los cuatro hallazgos de la etapa 1. De paso queda arreglado AL5 de esta mañana: las bases de datos y los modelos sueltos en /tmp ya cuentan como resultados. Los arreglos pasaron por cuatro rondas de verificación con 27 agentes (todos con Haiku 5.5). En cada ronda se intentaba romper lo arreglado en la anterior, y lo que encontraban se corregía antes de la siguiente. La última ronda ya no encontró nada crítico ni alto. En una casa sintética de desarrollador, ningún elemento pasó a estar marcado como Seguro (salvo `~/.npm/_logs`, que ya se borraba entero), y lo preseleccionado bajó de 234,5 a 101,3 MB.

Compila en release sin avisos. Con la concurrencia estricta de Swift 6 salen los mismos 7 avisos de siempre, ninguno nuevo.

**En tu Mac no cambia nada.** Comparé el diagnóstico real, de solo lectura, antes y después. No tienes registros grandes en carpetas «logs», ni resultados en /tmp, ni Maven. Lo preseleccionado subió de 41,6 MB a 413,2 MB por motivos ajenos a estos arreglos:
- 302,4 MB son la instalación fallida de Codex, que pasó las 24 horas a las 16:06 (BA17, pendiente);
- 47,9 MB son la caché de la Ayuda de macOS;
- 19,2 MB son la caché de npm.

| Hallazgo | Qué hace ahora |
|---|---|
| **CR4.** Registros en carpetas «logs» | Un `.log` de 20 MB o más solo es Seguro si está en la carpeta oculta de una herramienta que la app reconoce sin duda (o tiene un nombre conocido como `npm-debug.log`). Para reconocerla vale una de las conocidas, o un comando o una app con su mismo nombre. No basta tener `bin/`, parecerse al nombre de una app, ser un comando del sistema ni estar en `~/.config` o `~/.local`. En tus carpetas, o en una oculta que no reconoce, pasa a Revisar. Lo mismo en «Carpetas ocultas»: la carpeta «logs» o «cache» de una herramienta que no reconoce pasa a Revisar. Si tiene partes sin permiso, datos que no son registros (1 MB o más entre todos) o una tabla, un modelo o un comprimido de datos, también. Si cambió hace menos de 7 días, ya no se marca, y «Solo lo seguro» tampoco la selecciona. Dentro de un repositorio git es Cuidado. |
| **AL13.** /tmp | Todo pasa por la comprobación de resultados únicos, aunque se llame `npm-…` o `pip-…`. La lista de resultados creció mucho: cuadernos, datos, bases, modelos, RAW, 3D, `.7z`, `.rar`, `.dmg`, `.apk`… Una parte sin permiso o un disco montado (en la carpeta o más adentro) cuentan como «sin revisar». Los documentos de Pages o Keynote cuentan como resultado. La documentación y los metadatos de los paquetes y las licencias pequeñas no bloquean. |
| **AL14.** Maven | Pasa a Revisar. Sube a Cuidado si hay `maven-metadata-local.xml` (lo que deja `mvn install` o `install-file`, con el nombre del artefacto) o si no se pudo mirar entero. Solo mira nombres de archivo, sin leer ninguno. |
| **AL15.** Máximo y Papelera | `PlanMaximo.sinPapelera` deja fuera de «Liberar al máximo» lo que no es Seguro y se borraría sin Papelera: simuladores, comandos que borran, vaciar la Papelera. Aparece en «No lo marco» con el motivo. Limpiador lo omite también si llegara. Los textos de la hoja, del modo definitivo y del README ya dicen la verdad. Compactar SQLite (que no borra datos) sigue pudiendo entrar. |

**Residuos que quedan (anotados, sin arreglar):**
- un `.log` en /tmp sale Seguro a las 24 h;
- la lista de resultados de /tmp sigue siendo cerrada (`.bin`, `.dat`… no cuentan);
- `/var/folders/T` no mira resultados;
- en la caché de una herramienta reconocida, un `.bin` cuenta como caché;
- un `results.json` o un `metrics.jsonl` dentro de los registros de una herramienta reconocida cuenta como registro;
- «Todo» sigue marcando lo que tiene «Se sigue escribiendo» (ver ME48);
- el `.ivy2/local` de sbt y los paquetes de NuGet de un feed local no se detectan;
- en los demás sitios donde la app decide si algo está instalado, la comprobación sigue siendo permisiva;
- algunas herramientas sin comando ni app con su nombre (una extensión de VS Code, por ejemplo) ya no se reconocen y sus registros salen Revisar. Es más conservador, pero limpia menos.

## Lo más urgente

| # | Problema | Severidad | Dónde | Arreglo en una línea |
|---|---|---|---|---|
| 1 | Sigue de esta mañana: «Liberar al máximo» borra para siempre todo lo Seguro, así que cada error de clasificación es una pérdida definitiva | Raíz de CR4, AL13 y AL14 | [Limpiador.swift:28](Sources/LimpiadorMac/Limpiador.swift:28), [Limpiador.swift:130](Sources/LimpiadorMac/Limpiador.swift:130) | Sin Papelera solo para una lista cerrada de cachés conocidas; el resto, a la Papelera |
| 2 | Un `.log` de 20 MB o más en una carpeta «logs» de tus carpetas sale Seguro, preseleccionado y con «Nada importante» | Crítica (CR4) | [Escaner.swift:4997](Sources/LimpiadorMac/Escaner.swift:4997) | Seguro solo en Library, en carpetas ocultas de herramientas o para `*-debug.log`; el resto, Revisar |
| 3 | /tmp: los prefijos `npm-`, `pip-` y `uv-` y las extensiones que faltan (`.ipynb`, `.7z`, `.parquet`…) se saltan «Resultados únicos» | Alta (AL13) | [Escaner.swift:3051](Sources/LimpiadorMac/Escaner.swift:3051), [Indice.swift:1241](Sources/LimpiadorMac/Indice.swift:1241) | Todo /tmp pasa por `resultadosUnicos`; sin lista cerrada de extensiones |
| 4 | Simuladores y comandos Revisar o Cuidado se borran sin Papelera en el modo máximo y en el definitivo, y la hoja dice lo contrario | Alta (AL15) | [Limpiador.swift:203](Sources/LimpiadorMac/Limpiador.swift:203), [Hojas.swift:211](Sources/LimpiadorMac/Hojas.swift:211) | Dejarlos fuera de esos modos, o corregir los textos |
| 5 | El repositorio de Maven sale Seguro y «Se regenera» | Alta (AL14) | [Escaner.swift:867](Sources/LimpiadorMac/Escaner.swift:867) | Revisar hasta separar lo descargado de lo instalado en local |
| 6 | «Sin uso» ofrece el catálogo de Lightroom suelto, con un motivo genérico | Alta (AL17) | [Escaner.swift:3457](Sources/LimpiadorMac/Escaner.swift:3457) | Excluir `.lrcat` y `.lrdata`, o darles un aviso propio en Cuidado |
| 7 | Mover algo desde el Explorador borra el Deshacer de la limpieza anterior (A5 del 8 de octubre) | Alta (AL16) | [VistaExplorador.swift:207](Sources/LimpiadorMac/VistaExplorador.swift:207) | Guardar varias limpiezas, no una |
| 8 | Compactar no ve el `-wal`, y el filtro LIKE se salta las tablas «sqlite…» | Media (ME55, ME56) | [Escaner.swift:2622](Sources/LimpiadorMac/Escaner.swift:2622), [Escaner.swift:2640](Sources/LimpiadorMac/Escaner.swift:2640) | Comprobar después del checkpoint en la misma conexión; `substr(name,1,7)` |
| 9 | La compactación se cuenta dos veces en el total: 1,51 GB en tu Mac | Media (ME57) | [Models.swift:525](Sources/LimpiadorMac/Models.swift:525) | Restar lo que ya cuenta un borrado que contiene la base |
| 10 | Regresión de hoy: «Por seguridad, N elementos…» cuenta también los elementos saltados | Media (ME67) | [Limpiador.swift:131](Sources/LimpiadorMac/Limpiador.swift:131) | Contar después del `continue` |
| 11 | Señal de uso: lecturas que no se ven, el análisis la altera y un `.DS_Store` oculta carpetas | Media (ME43-ME45) | [Indice.swift:947](Sources/LimpiadorMac/Indice.swift:947) | Foto de fechas antes de leer nada, ignorar los ocultos y un texto honesto |

## Qué cambió desde esta mañana

### Código

No hay git, así que comparé con el zip de esta mañana: 1.159 líneas de diferencias en 8 archivos (Escaner +511, Indice +60, Almacen +38, VistaCategoria +36, Limpiador +22, Evaluador, Models y Hojas).

- **«Sin uso»**, que sustituye a «Apps que no usas»:
  - Apps: ya sin el mínimo de 20 MB.
  - Juegos de Steam: lee `appmanifest_*.acf` y `LastPlayed`.
  - Carpetas y archivos del primer nivel de Descargas, Escritorio, Documentos, Películas, Música e Imágenes, y de tu carpeta personal.
  - Lo de 50 MB o más que hay dentro de las carpetas que sí usas, hasta 3 niveles.
  - La señal de uso es la más reciente entre cambio (mtime), lectura (atime), llegada (ctime) y Spotlight.
  - Un selector de 7, 30, 90, 180 o 365 días (por defecto 7) que solo oculta.
- **Compactar bases SQLite** de 100 MB o más, dentro de «Comprimir sin borrar» y en Revisar, con `PRAGMA wal_checkpoint(TRUNCATE); VACUUM;`.
- **Copias sobrantes del entorno de Codex:** Seguro, sin marcar.
- **Cachés nuevas:**
  - Media Cache de Adobe, `shadercache` de Steam, `DerivedDataCache` de Unreal y `CacheClip` de DaVinci;
  - renders de iMovie y Final Cut y vistas previas de Lightroom;
  - Whisper y los registros de npm;
  - tres cachés internas de Chromium: `PnaclTranslationCache`, `Shared Dictionary` y `Webstore Downloads`.
- **Duplicados** guarda la copia que conserva (`copiasExigidas`) y Limpiador la vuelve a comprobar antes de borrar la otra.
- **Limpiador** salta lo que ya se fue con otro elemento, comprueba el espacio libre antes de compactar y mide lo que quita un comando.
- El orden cambió: «Sin uso» se calcula después de Duplicados.
- **Versión:** sigue en 3.0 (4). La app de /Applications es 3.0 (4), copiada hoy a las 12:40; según un revisor, antes era 3.0.2 (6) (BA89).

### Estado de los 116 hallazgos de esta mañana

Se comprobaron uno a uno contra el código actual. Los que cambiaron de estado pasaron además por un verificador. Resultado: **1 arreglado, 4 a medias, 13 empeoran y 98 siguen igual.** Ninguno de los críticos o altos de esta mañana se ha arreglado.

| Anterior | Estado hoy | Qué hay ahora |
|---|---|---|
| BA43. La copia sobrante de Codex no se ofrecía | **Arreglado** | Sale como «Copias sobrantes del entorno de Codex» si es copia exacta del entorno activo y lleva más de un día ([Escaner.swift:2042](Sources/LimpiadorMac/Escaner.swift:2042)). En tu Mac: 2,03 GB. |
| ME2. Duplicados no revalidaba la copia que se conserva | A medias | Ya la revalida ([Limpiador.swift:121-128](Sources/LimpiadorMac/Limpiador.swift:121)), pero con la huella parcial (64 KB al principio y al final), no con SHA-256: un cambio en medio del mismo tamaño pasa (probado). |
| BA17. Instalación de Codex sin extraer, Seguro y marcada | A medias | Solo se añadió el uso de ChatGPT. Siguen Seguro, la preselección y el texto «Nunca llegaron a instalarse». En tu Mac, la de 302 MB lo cumple desde las 16:06. |
| BA21. Olvidados promete «tendrás que descargarlo otra vez» | A medias | «Sin uso» se queda ahora con los archivos normales de Descargas. Los paquetes `.key` y `.rtfd` y las capturas siguen en Olvidados con esa frase. |
| BA29. «Sin usar +90 días» | A medias | En «Sin uso» lo sustituye el selector de días. En el resto de categorías sigue igual. |
| CR1. Llaves de una CA con nombre «rootca» o «cacert» | **Empeora** | La exención sigue. Además, «Sin uso» ofrece carpetas enteras con esas llaves sin el aviso «Claves» (probado). |
| CR2. Copia por nombre y tamaño | **Empeora** | Sigue igual. Y las copias sobrantes de Codex usan el mismo atajo fuera de sus 20 archivos más grandes (BA75). |
| ME4. Enlaces duros cuentan el tamaño completo | **Empeora** | «Sin uso» mide archivos sueltos con `bytes(de:)`: un enlace duro salió como dos entradas de 5,2 MB que liberan 5,2 MB en total. |
| ME27. «Solo lo seguro» no mira si es marcable | **Empeora** | Hoy selecciona también las copias de Codex, los renders de iMovie y las cachés de Adobe, Steam y DaVinci. |
| ME31. Revisar que no pasa por la Papelera | **Empeora** | Se suma la compactación SQLite. Ver también AL15. |
| ME36. Shell.comando no se puede cancelar | **Empeora** | VACUUM corre por ese camino con un límite de 900 s, y Detener solo actúa entre elementos. |
| BA24. Apps abiertas por prefijo del nombre | **Empeora** | La clave nueva «Steam» casa con «Steam Link». |
| BA34, BA35, BA37 | **Empeoran** | Escaner.swift pasa de 5.453 a 5.902 líneas; el registro de `sinLeer` solo existe en una de las 8 copias del recorrido FTS; hay más umbrales escritos a mano. |
| BA42. Totales que no cuadran | **Empeora** | La compactación se suma aparte sin descontar su base (ME57). |
| BA46. Clones con «libera 0 KB» | **Empeora** | «Sin uso» añade otra fila de 0 KB para un clon. |
| BA48. Vaciar la Papelera no se puede detener | **Empeora** | «Sin uso» manda carpetas enteras a la Papelera, así que el vaciado puede crecer mucho. |
| Punto 10 de esta mañana (Deshacer solo al final, A4) | Sigue | Confirmado otra vez: lo movido se guarda en el registro después del bucle ([Limpiador.swift:421](Sources/LimpiadorMac/Limpiador.swift:421)). |

Lista completa por grupo:

- **Arreglado (1):** BA43.
- **A medias (4):** ME2, BA17, BA21, BA29.
- **Empeoran (13):** CR1, CR2, ME4, ME27, ME31, ME36, BA24, BA34, BA35, BA37, BA42, BA46, BA48.
- **Siguen (98):** CR3, AL1-AL12, ME1, ME3, ME5-ME26, ME28-ME30, ME32-ME35, ME37-ME42, BA1-BA16, BA18-BA20, BA22, BA23, BA25-BA28, BA30-BA33, BA36, BA38-BA41, BA44, BA45, BA47 y BA49-BA59.

Hubo una discrepancia. En BA20, el revisor dijo «a medias» y el verificador lo dejó en «sigue»: lo que hoy excluye los repositorios de «Sin uso» es código nuevo, no un arreglo de la regla antigua.

## Notas por área

| Área | Nota | Resumen |
|---|---|---|
| «Sin uso»: señales de uso | **4** | Nunca se marca sola y va a la Papelera. La señal es débil: hay lecturas que no se ven, el análisis la altera y un `.DS_Store` oculta carpetas. |
| «Sin uso»: apps y Steam | 5 | Excluye bien agentes, apps de fondo, apps de Apple y apps abiertas. Sin Steam.app, la biblioteca entera sale como resto, y las apps con extensiones salen con un solo aviso. |
| «Sin uso»: filtro, selección e interfaz | 6 | Lo oculto no se marca ni entra en el plan. Pero tapa Grandes y Olvidados. |
| Compactar SQLite: código | 6 | Cabecera bien leída, apertura inmutable y VACUUM transaccional. Ignora el WAL y el filtro LIKE falla. |
| Compactar SQLite: pruebas | 6 | Datos, números de fila e integridad intactos; se aparta si la base está abierta. Cuenta doble cuando la base está dentro de otra carpeta ofrecida. |
| Cachés nuevas de apps de medios | 5 | Rutas de Adobe, Lightroom, Whisper, iMovie y Final Cut bien elegidas. Restos se come la carpeta de Steam, el catálogo de Lightroom sale suelto y DaVinci es Seguro sin mirar dentro. |
| Codex, Chromium y demás cambios | 6,5 | Copias de Codex exactas y fuera del máximo. Olvidados ofrece carpetas con una nube dentro, y las cachés nuevas de Chromium son Seguro sin confirmar. |
| Limpieza, Papelera, Deshacer e historial | 6 | «Vaciar solo lo de esta limpieza» compara inodos y Deshacer no sobrescribe. Pero vaciar la Papelera ignora lo abierto, Deshacer no compara inodos y hay falsos éxitos. |
| Comprimir, unir, iCloud y apps | **7** | Ejemplar: comprueba byte a byte, ACL, firma y cortes. Dos fallos menores con ACL «deny delete». |
| Índice y utilidades | 6 | Recorrido FTS correcto y Shell.comando robusto. `sePuedeBorrar` no usa la lista de zonas protegidas. |
| Escaner, de emuladores a restos | 5 | Resultados únicos y sesiones de agentes bien. Fallan el atajo de /tmp, Maven, Playwright, el DerivedData desconectado y Gradle rc. |
| Escaner, de compilaciones a comprimir | 6 | Duplicados con SHA-256 e intermedios escalonados. Pero el `.log` en «logs» es Seguro y preseleccionado (CR4). |
| Interfaz, textos y modo máximo | 6 | Confirmaciones bien separadas y cierre de apps con ⌘Q, nunca forzado. Textos que prometen Papelera o «todo» de más. |
| Diagnóstico real de tu Mac | 6 | Los tamaños cuadran con du (6 de 6) y lo preseleccionado es correcto. Hay 1,51 GB contados dos veces. |
| Compilación, distribución y README | 6 | Release sin avisos; los 7 avisos de Swift 6 son falsos positivos. Versión sin subir, README con promesas de más y sin pruebas. |
| Hueco: «Sin uso» = 0 en tu Mac | 6,5 | El 0 es correcto salvo `Documents/Codex` (`.DS_Store`). |
| Hueco: cruces entre categorías | 6 | No hay pérdida de datos por solape, pero sí totales inflados. |
| Hueco: primer arranque y sin Acceso total | 6 | Arranca bien sin estado. «Acceso total» sale «no» si falta `~/Library/Safari`. |
| Hueco: disco casi lleno | **7,5** | Comprimir se para a tiempo y unir copias funciona. El Deshacer se pierde si no cabe. |

## Hallazgos detallados

Los identificadores siguen la numeración de esta mañana: CR4, AL13-AL17, ME43-ME83 y BA60-BA97. Cuando un hallazgo continúa uno anterior, se indica.

Cada crítico y alto lo reprodujo su revisor con una casa sintética y pasó por dos verificadores independientes, uno con el código y otro reproduciéndolo. Además, yo comprobé en persona las líneas citadas. Los medios pasaron por un verificador y los bajos no tienen verificación adversarial. Cuando cambié la severidad que dieron los verificadores, lo explico.

### Crítica

#### CR4. Un `.log` grande en una carpeta «logs» de tus carpetas sale Seguro, preseleccionado y «Nada importante» (continúa A19-A26 del 8 de octubre)

- **Estado:** arreglado después del informe (ver «Actualización: etapa 1 arreglada»).
- **Ubicación:** [Escaner.swift:4993-5021](Sources/LimpiadorMac/Escaner.swift:4993), [Indice.swift:1054](Sources/LimpiadorMac/Indice.swift:1054)
- **Qué pasa:** «Registros enormes fuera de Library» toma cualquier `.log` de 20 MB o más que no esté en Library. Lo da por registro de herramienta solo porque su carpeta se llama `logs` o `log`:
  ```swift
  let deHerramienta = ["logs", "log"].contains(carpeta) || n.hasSuffix("-debug.log") || n.hasSuffix(".debug.log")
  ```
  Sale Seguro, se preselecciona a partir de 7 días y su consecuencia dice «Nada importante: solo se pierden mensajes antiguos». El comentario de dos líneas antes dice lo contrario: muchos `.log` son datos de verdad («el de un entrenamiento») y solo se marcan solos los que son claramente de una herramienta.
- **Escenario (reproducido):** `Documents/Experimento/logs/train.log`, de 25 MB, sin cambios desde hace 10 días y fuera de un repositorio git. Sale como «[x] 25 MB Seguro · Solo registros». En «Liberar al máximo» entra en el bloque «Se regenera solo o ya no se usa», que no tiene interruptor, y Limpiador lo borra sin Papelera.
- **Por qué importa:** el registro de un entrenamiento, de una simulación o de un servidor propio no se regenera. La app lo marca sola.
- **Arreglo:** dejar Seguro solo los `.log` de Library, de carpetas ocultas de herramientas (`~/.npm/_logs`, `~/.gradle/daemon`…) y los `*-debug.log`. El resto, Revisar, sin preseleccionar y con «Revisa qué es». Quitar «Nada importante» fuera de esas zonas.
- **Verificación:** 2 de 2 verificadores lo confirman como crítica. Yo comprobé las líneas 4993-5021.

### Alta

#### AL13. En /tmp, los prefijos de herramienta y las extensiones que faltan se saltan «Resultados únicos» (amplía AL5)

- **Estado:** arreglado después del informe, junto con AL5.
- **Ubicación:** [Escaner.swift:2984](Sources/LimpiadorMac/Escaner.swift:2984), [Escaner.swift:3051-3052](Sources/LimpiadorMac/Escaner.swift:3051), [Indice.swift:1241-1245](Sources/LimpiadorMac/Indice.swift:1241)
- **Qué pasa:** dos huecos en la misma protección.
  1. `efimerosEnTmp` casa por prefijo sin separador (`"npm-"`, `"pip-"`, `"uv-"`, `"yarn--"`). Si el nombre casa, no se llama a `resultadosUnicos`:
     ```swift
     let efimero = Self.efimerosEnTmp.contains { nombre.hasPrefix($0) }
     let unicos = efimero ? Unicos() : resultadosUnicos(en: ruta, c, leidos: &leidos)
     ```
  2. Un archivo solo cuenta como resultado si su extensión está en una lista cerrada: json, csv, pdf, docx, xlsx, png, mp4… Faltan `.ipynb`, `.parquet`, `.7z`, `.rar`, `.doc`, `.ppt`, `.psd`, `.key`, `.svg` y las bases de datos y modelos que ya señaló AL5 (`.sqlite`, `.h5`, `.pkl`).

  En los dos casos sale Seguro y se marca a las 24 h; en «Liberar al máximo», a las 2 h. El plan lo pone en «Se regenera solo».
- **Escenario (reproducido):**
  - `/tmp/npm-informe/resultados.csv`, de 1,5 MB y sin copia en tus carpetas, sale como «[x] Seguro · Temporal de una herramienta». El mismo archivo en `/tmp/informe-normal` sale como «[ ] Revisar · Resultados únicos».
  - `/tmp/analisis` con `cuaderno.ipynb`, `copia.7z` y `tabla.parquet` sale como «[x] Seguro» y sin ningún aviso.
- **Arreglo:** que todo /tmp pase por `resultadosUnicos` y que la lista de herramientas solo cambie el texto del motivo, nunca el riesgo, con prefijos exactos (`npm-cache-`, no `npm-`). En /tmp, que cuente como resultado cualquier archivo de cierto tamaño sin copia, salvo los tipos que genera una herramienta (caché, índice, objeto de compilación).
- **Verificación:** 4 de 4 verificadores lo dan como crítica. **Lo dejo en alta** por coherencia con AL5, que es el mismo mecanismo: /tmp es zona temporal y en el modo normal va a la Papelera. Un matiz: `tmux-` y `vscode-` no llegan aquí ([Utilidades.swift:419](Sources/LimpiadorMac/Utilidades.swift:419) los excluye antes). Yo comprobé las líneas 3040-3095 y la lista de extensiones.

#### AL14. El repositorio de Maven sale Seguro y «Se regenera» aunque guarda artefactos instalados a mano (continúa A19-A26 del 8 de octubre)

- **Estado:** arreglado después del informe.
- **Ubicación:** [Escaner.swift:867-868](Sources/LimpiadorMac/Escaner.swift:867), [VistaCategoria.swift:200](Sources/LimpiadorMac/VistaCategoria.swift:200), [Maximo.swift:158-159](Sources/LimpiadorMac/Maximo.swift:158)
- **Qué pasa:** `~/.m2/repository` es una caché Seguro con «Maven las vuelve a descargar al compilar». Ahí también están los artefactos de `mvn install` y de `mvn install:install-file`: tus librerías SNAPSHOT, o JAR de un proveedor que no está en ningún repositorio remoto. No viene marcado, pero «Solo lo seguro» lo selecciona (ME27), y entonces «Liberar al máximo» lo pone en «Lo que marcaste tú» y lo borra sin Papelera.
- **Escenario (reproducido con una casa sintética y un arnés):** con `~/.m2/repository/com/tuempresa/mi-lib/1.0-SNAPSHOT/mi-lib-1.0-SNAPSHOT.jar` instalado a mano, pulsas «Solo lo seguro» y luego «Liberar al máximo». El JAR se borra para siempre y los proyectos que dependen de él dejan de compilar.
- **Arreglo:** pasarlo a Revisar hasta separar lo descargado de lo instalado en local. Maven anota el origen de cada artefacto en `_remote.repositories` (hay que comprobar el formato). Lo local, en Cuidado y fuera de «Solo lo seguro».
- **Verificación:** 2 de 2 verificadores lo dan como crítica. **Lo dejo en alta** porque no se marca solo: hace falta pulsar «Solo lo seguro» o marcarlo a mano. En tu Mac no hay `~/.m2`.

#### AL15. «Liberar al máximo» y el borrado definitivo borran sin Papelera los simuladores y comandos Revisar o Cuidado, y la hoja dice que van a la Papelera (amplía ME31)

- **Estado:** arreglado después del informe.
- **Ubicación:** [Limpiador.swift:130](Sources/LimpiadorMac/Limpiador.swift:130), [Limpiador.swift:203-215](Sources/LimpiadorMac/Limpiador.swift:203), [Hojas.swift:211](Sources/LimpiadorMac/Hojas.swift:211), [Models.swift:722](Sources/LimpiadorMac/Models.swift:722)
- **Qué pasa:** la regla «lo que no es 100 % seguro nunca se elimina sin pasar por la Papelera» solo cambia el modo de los elementos que borran archivos. `simctl erase`, `simctl delete`, `simctl runtime delete` y los comandos como `docker image prune -a` se ejecutan igual en cualquier modo. Mientras, la hoja de máximo dice: «Lo que no es Seguro va a la Papelera (puedes deshacerlo)». Y la descripción del modo definitivo dice: «Por seguridad, lo marcado como Revisar o Cuidado va igual a la Papelera».
- **Escenario (reproducido con el código real y un arnés):** marcas a mano un simulador de iOS con apps (Cuidado), pulsas «Liberar al máximo», marcas la casilla de Cuidado y confirmas. Se ejecuta `xcrun simctl erase` y se pierden las apps y sus datos, mientras la hoja decía que se podía deshacer. En la confirmación normal sí sale la línea «no pasa por la Papelera» ([Hojas.swift:101-106](Sources/LimpiadorMac/Hojas.swift:101)); en la de máximo no hay nada parecido.
- **Arreglo:** dejar estas acciones fuera de «Liberar al máximo» y del modo definitivo cuando no son Seguro, o pedir una confirmación aparte. Mientras tanto, corregir los dos textos y poner en la hoja de máximo la misma línea de irreversibles que en la confirmación normal.
- **Verificación:** 2 de 2 verificadores lo confirman como alta. Yo comprobé Limpiador.swift:125-135 y 200-216, Hojas.swift:211 y Models.swift:722.

#### AL16. Mandar algo a la Papelera desde el Explorador borra el Deshacer de la limpieza anterior (sigue A5 del 8 de octubre)

- **Ubicación:** [VistaExplorador.swift:207](Sources/LimpiadorMac/VistaExplorador.swift:207), [Limpiador.swift:701-705](Sources/LimpiadorMac/Limpiador.swift:701)
- **Qué pasa:** `moverAPapelera` guarda la «última limpieza» con un solo movimiento, y `Historial.guardarUltima` reescribe el archivo entero. El registro de la limpieza anterior desaparece: ya no hay «Deshacer» ni «Vaciar solo lo de esta limpieza» para ella. La tarjeta pasa a decir «enviaste 1 cosa». El README promete devolver con un clic lo que va a la Papelera.
- **Escenario (reproducido):** limpias y mandas 5 GB a la Papelera. Después mandas un archivo suelto desde el Explorador. El Deshacer solo ofrece ese archivo, y los 5 GB siguen en la Papelera sin botón para devolverlos ni para vaciarlos aparte.
- **Arreglo:** guardar una lista de las últimas limpiezas, o el movimiento del Explorador aparte. Escribir con `.atomic` (ver ME68).
- **Verificación:** se juntan tres hallazgos con cinco votos: tres dan alta y dos, media. Lo dejo en alta porque rompe una promesa del README en un uso normal y sin aviso. Yo comprobé las dos funciones.

#### AL17. «Sin uso» ofrece el catálogo de Lightroom suelto, con el motivo genérico (nuevo)

- **Ubicación:** [Escaner.swift:3457](Sources/LimpiadorMac/Escaner.swift:3457), [Escaner.swift:5375](Sources/LimpiadorMac/Escaner.swift:5375), [Evaluador.swift:113](Sources/LimpiadorMac/Evaluador.swift:113)
- **Qué pasa:** si otra categoría ya ofrece algo de dentro de una carpeta (aquí, las vistas previas de Lightroom), «Sin uso» no la ofrece entera y baja a sus hijos. El `.lrcat` se ofrece solo si pesa 50 MB o más y lleva 7 días sin señales. `.lrcat` no está entre los paquetes personales y no tiene aviso de base de datos. Sale como Revisar con «Sin uso» y nada más, y «Todo» lo marca. Sin vistas previas, se ofrece la carpeta entera con el catálogo dentro.
- **Escenario (reproducido):** `Pictures/Lightroom` con `Lightroom Catalog.lrcat` de 55 MB y sus vistas previas, sin tocar en 2 meses. Sale «Lightroom Catalog.lrcat, 55 MB, Revisar». Si lo marcas con «Todo», limpias y vacías la Papelera, se pierden las ediciones y los metadatos de todo el catálogo.
- **Arreglo:** excluir de «Sin uso» los `.lrcat`, `.lrcat-data` y `.lrdata` (y las bibliotecas de Final Cut e iMovie si no lo están), o darles un aviso propio: «Catálogo de Lightroom: tus ediciones», en Cuidado y fuera de «Todo».
- **Verificación:** 2 de 2 verificadores lo confirman como alta. En tu Mac no hay Lightroom.

### Media

Formato breve: dónde, qué pasa, arreglo y verificación. Están agrupados por tema.

#### «Sin uso» y señales de uso

#### ME43. Las lecturas no se registran si el archivo no cambió, y el texto dice que sí se miran
- **Dónde:** [Indice.swift:952](Sources/LimpiadorMac/Indice.swift:952), [Escaner.swift:3481-3482](Sources/LimpiadorMac/Escaner.swift:3481), [VistaCategoria.swift:58](Sources/LimpiadorMac/VistaCategoria.swift:58)
- **Qué pasa:** en este macOS, una lectura normal solo pone la fecha de acceso a hoy si es anterior a la última modificación, es decir, la primera lectura después de un cambio. Leer un archivo que no cambió no deja rastro, se lea con `cat`, con `python3 x.py` o con `sh x.sh`. Ejecutar directamente un binario o un script (`./tool`) sí lo deja. Una carpeta de datos o de scripts que lees a diario sin cambiarla sale como «Revisar · Hace 2 meses». El motivo dice «No veo cambios, lecturas ni copias…» y la vista dice «sin abrirse ni cambiar», que no es lo que se mide.
- **Arreglo:** no presentar `atime` como prueba de no uso; decir «no veo cambios ni aperturas registradas» y avisar de que las lecturas de scripts no se ven. Dar más peso a `kMDItemLastUsedDate` y a `com.apple.lastuseddate#PS`.
- **Verificación:** cuatro votos, media o baja. Los verificadores corrigieron el ejemplo original: un binario ejecutado sí cuenta.

#### ME44. El análisis cambia su propia señal: lo que lee una pasada desaparece en la siguiente
- **Dónde:** [Indice.swift:952](Sources/LimpiadorMac/Indice.swift:952), [Compresor.swift:346](Sources/LimpiadorMac/Compresor.swift:346) (muestra con `pread`), `Huella.parcial` en Duplicados
- **Qué pasa:** las huellas de Duplicados y las muestras de «Comprimir» leen archivos antiguos y les ponen la fecha de acceso a hoy. «Sin uso» toma la fecha de acceso más reciente de cada carpeta, así que durante 7 días no salen. En una casa sintética, 4 de 7 elementos desaparecieron en la segunda pasada sin que nadie tocara nada.
- **Arreglo:** tomar las fechas en el índice antes de cualquier lectura del análisis y usar solo esa foto. También para los archivos sueltos de primer nivel, que hoy se miran con `lstat` en el momento de `sinUso` ([Escaner.swift:3454](Sources/LimpiadorMac/Escaner.swift:3454)). Si se lee, restaurar la fecha de acceso con `utimensat`.
- **Verificación:** 1 de 1, media. En tu Mac no se ven lecturas de hoy en tus carpetas salvo dentro de `.build` del proyecto.

#### ME45. Una sola señal, incluso un `.DS_Store`, saca una carpeta entera de «Sin uso» (caso real: `Documents/Codex`)
- **Dónde:** [Indice.swift:947](Sources/LimpiadorMac/Indice.swift:947), [Indice.swift:290-294](Sources/LimpiadorMac/Indice.swift:290)
- **Qué pasa:** la señal de una carpeta es el máximo de todo su árbol. La parte de lecturas ignora los archivos ocultos, pero la de cambios (`masReciente`) los cuenta, aunque el comentario diga que lo que escribe el Finder no es uso tuyo. Un `.DS_Store` que el Finder reescribió hace días mantiene «usada» la carpeta entera. En tu Mac, `Documents/Codex` (6 MB, 11,6 días sin cambios visibles) no sale por un `.DS_Store` de hace 5,7 días.
- **Arreglo:** ignorar los archivos ocultos también en `masReciente` cuando se usa como señal de uso. Valorar contar cuántos archivos aportan la señal en vez de tomar solo el máximo, y mostrarlo en la ficha.
- **Verificación:** 1 de 1, media. Reproducido en tu Mac solo con `stat`.

#### ME46. El plazo elegido no cambia lo que se calcula: con 30 días o más, lo de dentro no aparece, y lo oculto tapa a Grandes y Olvidados
- **Dónde:** [Escaner.swift:3461](Sources/LimpiadorMac/Escaner.swift:3461), [Escaner.swift:119](Sources/LimpiadorMac/Escaner.swift:119), [Almacen.swift:148-151](Sources/LimpiadorMac/Almacen.swift:148)
- **Qué pasa:** el análisis usa siempre 7 días y el plazo elegido solo oculta. Una carpeta con señal de hace 30 días se ofrece entera y no se mira dentro. Con un plazo de 90 días o más, la carpeta se oculta y el vídeo de 55 MB que lleva un año sin tocarse ahí dentro no aparece nunca. Además, lo oculto sigue contando como «ya ofrecido», así que Grandes y Olvidados tampoco lo muestran.
- **Arreglo:** si dentro de una carpeta ofrecida hay hijos de 50 MB o más más viejos que el plazo más largo, ofrecerlos aparte. Que Grandes y Olvidados excluyan solo lo visible, o volver a calcular al cambiar el plazo.
- **Verificación:** tres hallazgos fusionados, media.

#### ME47. Antes de borrar se comprueba poco: solo la fecha de modificación, y solo en algunos elementos
- **Dónde:** [Limpiador.swift:112-117](Sources/LimpiadorMac/Limpiador.swift:112), [Utilidades.swift:326-340](Sources/LimpiadorMac/Utilidades.swift:326), [Escaner.swift:3487](Sources/LimpiadorMac/Escaner.swift:3487)
- **Qué pasa:** la comprobación de «cambió desde el análisis» compara solo la fecha de modificación, y solo en los elementos que traen `cambioAnalizado`. «Sin uso» se basa en lecturas y llegadas, así que abrir algo después de analizar no lo protege. Además, `cambioAnalizado` es la hora en que se crea el elemento, no la hora en que se leyó el índice. Y un Seguro sin esa marca (una descarga a medias, ME78) se borra en «Liberar al máximo» aunque haya cambiado. El comentario de la línea 17 promete esa comprobación para todo.
- **Arreglo:** guardar en cada elemento la señal que lo hizo aparecer y comprobarla antes de borrar. Fijar `cambioAnalizado` en la hora de lectura del índice, y ponerlo también en lo Seguro que se borra sin Papelera.
- **Verificación:** dos hallazgos fusionados, media.

#### ME48. «Todo», «Nada» y «Solo lo seguro» actúan sobre toda la categoría, con buscador o sin él, y en «Sin uso» marcan carpetas personales de golpe
- **Dónde:** [VistaCategoria.swift:196-200](Sources/LimpiadorMac/VistaCategoria.swift:196), [Maximo.swift:159](Sources/LimpiadorMac/Maximo.swift:159), [Hojas.swift:181](Sources/LimpiadorMac/Hojas.swift:181)
- **Qué pasa:** con un texto en el buscador, «Todo» también marca lo que no se ve. En «Sin uso», «Todo» marca todas las carpetas y archivos personales Revisar, y «Liberar al máximo» los incluye por defecto en «Lo que marcaste tú» (todo a la Papelera). Los botones tampoco se desactivan mientras analiza.
- **Arreglo:** que actúen solo sobre lo visible y digan cuántos marcan. En «Sin uso», quitar «Todo» o pedir confirmación, y que en el máximo no entre por defecto.
- **Verificación:** dos hallazgos fusionados, media.

#### ME49. Las apps con componentes que funcionan sin abrirse salen con un solo aviso
- **Dónde:** [Escaner.swift:3372](Sources/LimpiadorMac/Escaner.swift:3372)
- **Qué pasa:** una app con ayudante en `Contents/Library/LaunchServices`, extensiones (`PlugIns/*.appex`, `SystemExtensions`) o un agente de inicio que apunta dentro sale con el único motivo «Sin usar». Borrarla quita esos componentes, y una extensión de sistema puede seguir activa.
- **Arreglo:** listar los componentes en los motivos, subir a Cuidado si hay extensión de sistema o agente, y avisar de que las extensiones se quitan desde Ajustes.
- **Verificación:** 1 de 1, media.

#### ME50. Restos no sabe lo que ofrecen otras categorías: la biblioteca de Steam sale entera y la carpeta de JetBrains también
- **Dónde:** [Escaner.swift:3628](Sources/LimpiadorMac/Escaner.swift:3628), [Escaner.swift:2518](Sources/LimpiadorMac/Escaner.swift:2518), [Escaner.swift:2695-2710](Sources/LimpiadorMac/Escaner.swift:2695)
- **Qué pasa:**
  - Sin Steam.app, «Restos de apps borradas» ofrece `~/Library/Application Support/Steam` entero (juegos, `userdata` con partidas locales y sombreadores) como Revisar, con «No afecta a ninguna app instalada». Los juegos dejan de salir en «Sin uso», porque esa ruta ya está ofrecida.
  - Lo mismo pasa con el padre «JetBrains»: sale como resto («No encontré JetBrains») mientras su caché sale aparte como Seguro y marcada. Las cachés de Google y JetBrains además no comprueban si la app está instalada.
- **Arreglo:** que `restos()` reciba lo ya ofrecido y no ofrezca un padre de algo ofrecido. Con `steamapps` dentro, desglosar y avisar de los juegos y las partidas.
- **Verificación:** tres hallazgos fusionados con cinco votos: cuatro dan media y uno, alta. Va a la Papelera y no se marca solo.

#### ME51. Textos de Steam que confunden
- **Dónde:** [Evaluador.swift:24](Sources/LimpiadorMac/Evaluador.swift:24), [Evaluador.swift:104-111](Sources/LimpiadorMac/Evaluador.swift:104), [Escaner.swift:2508](Sources/LimpiadorMac/Escaner.swift:2508), [Escaner.swift:2528](Sources/LimpiadorMac/Escaner.swift:2528)
- **Qué pasa:**
  - Desde hoy, «Sin uso» mira el contenido. Un juego con 5 audios o un PDF recibe «Archivos tuyos… puede ser lo único que tienes de eso», justo debajo de «Steam lo vuelve a descargar».
  - Si el manifiesto no trae `LastPlayed`, la fecha es la del manifiesto, que Steam reescribe al actualizar, y el aviso afirma «Steam no tiene registro de que lo hayas jugado».
- **Arreglo:** un texto de juego para lo que está en `steamapps`, y decir «según el manifiesto» cuando no hay `LastPlayed`.
- **Verificación:** media y baja.

#### ME52. Las nubes se detectan de tres formas distintas: Olvidados y parte de «Sin uso» no avisan de que el borrado llega a la nube
- **Dónde:** [Escaner.swift:5489-5490](Sources/LimpiadorMac/Escaner.swift:5489), [Escaner.swift:3465](Sources/LimpiadorMac/Escaner.swift:3465), [Evaluador.swift:225](Sources/LimpiadorMac/Evaluador.swift:225)
- **Qué pasa:**
  - Las reglas 4 y 5 de Olvidados no miran si dentro hay una carpeta de Dropbox (`contieneNube`) ni elementos de iCloud. Un «Archivo 2024» de 520 MB con `Dropbox/` dentro sale como «Olvidada» sin aviso.
  - «Sin uso» no ofrece entera una carpeta con marca de nube, pero baja a sus hijos y ofrece lo de 50 MB o más, sugiriendo «muévelo… a la nube».
  - El aviso «En la nube» solo mira las rutas de Mobile Documents y CloudStorage.
- **Arreglo:** una sola función «nube o iCloud» para «Sin uso», Olvidados, Duplicados y el Evaluador, que mire también hacia dentro y hacia arriba.
- **Verificación:** dos hallazgos; uno con votos alta y media, el otro media.

#### ME53. «Olvidada» solo mira los cambios, no las lecturas
- **Dónde:** [Escaner.swift:5465](Sources/LimpiadorMac/Escaner.swift:5465), [Escaner.swift:5495](Sources/LimpiadorMac/Escaner.swift:5495)
- **Qué pasa:** las reglas 4 y 5 usan `masReciente` (solo modificaciones), mientras que «Sin uso» y la regla 3 usan también lecturas y llegadas. Una carpeta que se lee a diario sale como «Olvidada».
- **Arreglo:** usar `ultimaSenal` y decirlo en el motivo.
- **Verificación:** 1 de 1, media.

#### ME54. Grandes y Olvidados ofrecen borrar el original que Duplicados conserva
- **Dónde:** [Escaner.swift:159](Sources/LimpiadorMac/Escaner.swift:159), [Escaner.swift:166-167](Sources/LimpiadorMac/Escaner.swift:166)
- **Qué pasa:** solo «Sin uso» recibe las copias que hay que conservar. Grandes ofrece el original como Cuidado mientras Duplicados ofrece la copia. El total suma los dos: 110 MB cuando solo se liberan 55. No se pierde nada, porque Limpiador omite la copia si se borran los dos.
- **Arreglo:** pasar `exigidas` a `olvidados()` y `grandes()`. Corregir el comentario de Duplicados (BA74).
- **Verificación:** 1 de 1, media.

#### Compactar bases SQLite

#### ME55. La comprobación previa no ve el `-wal`: una tabla que solo está ahí se renumera, y la cifra de espacio puede ser vieja
- **Dónde:** [Escaner.swift:2622](Sources/LimpiadorMac/Escaner.swift:2622), [Escaner.swift:2610-2611](Sources/LimpiadorMac/Escaner.swift:2610)
- **Qué pasa:** `vacuumSinRiesgo` abre la base con `immutable=1`, que ignora el `-wal`. Si una app se cerró de golpe y dejó una tabla nueva sin clave ni índice solo en el WAL, la base pasa la comprobación y `VACUUM` renumera sus filas: la tabla conserva sus 500 filas, pero la fila 501 pasa a ser la 1. Con el WAL pendiente, la cabecera también da libres y tamaño viejos.
- **En tu Mac:** el `-wal` de `~/.codex/thread_history_1.sqlite` está vacío (0 bytes), así que su cifra de 1,51 GB vacíos es real.
- **Arreglo:** hacer la comprobación y la medida en la misma conexión de solo lectura, sin `immutable`, después del checkpoint. Si hay `-wal` con contenido o un `-journal` caliente, no ofrecer la base.
- **Verificación:** cuatro hallazgos fusionados con seis votos: cinco dan media y uno, baja. No borra filas, nunca se marca solo y queda fuera del máximo.

#### ME56. El filtro `NOT LIKE 'sqlite_%'` salta tablas como «sqlitecache» o «SQLiteDatos»
- **Dónde:** [Escaner.swift:2640](Sources/LimpiadorMac/Escaner.swift:2640)
- **Qué pasa:** en LIKE, «_» vale cualquier carácter y no distingue mayúsculas. Toda tabla que empiece por «sqlite» seguido de una letra queda sin comprobar.
- **Arreglo:** `substr(name,1,7) <> 'sqlite_'` o `ESCAPE`, con una prueba de regresión.
- **Verificación:** dos hallazgos fusionados, media.

#### ME57. La compactación se suma aparte en el total: en tu Mac, 1,51 GB contados dos veces
- **Dónde:** [Models.swift:525](Sources/LimpiadorMac/Models.swift:525), [Escaner.swift:2557](Sources/LimpiadorMac/Escaner.swift:2557)
- **Qué pasa:** los elementos con `tamanoFijo` (la compactación) se suman sin mirar si su base ya cuenta dentro de otro elemento. En tu Mac, «Compactar thread_history_1.sqlite» (1,51 GB) y la base de `.codex` (1,56 GB) cuentan los dos en «Total encontrado». Pasa lo mismo con una base dentro de un resto: 60 MB de más en una casa sintética. Además, `basesCompactables` solo excluye las bases que están dentro de algo Seguro.
- **Arreglo:** en `sumaSinRepetir`, restar los comandos cuya ruta está dentro de un borrado (como ya hace `ahorro(sin:)`), y no ofrecer «Compactar» si su base ya está dentro de algo ofrecido.
- **Verificación:** tres hallazgos fusionados, media.

#### ME58. El margen de disco para VACUUM es menor que el que documenta SQLite
- **Dónde:** [Limpiador.swift:384](Sources/LimpiadorMac/Limpiador.swift:384)
- **Qué pasa:** exige libre > tamaño + 1 GB. SQLite documenta que puede hacer falta hasta el doble del tamaño del archivo.
- **Arreglo:** exigir el doble del tamaño más un margen, y repetir la comprobación justo antes.
- **Verificación:** 1 de 1, media.

#### ME59. El README y la hoja de máximo dicen que se compacta; el código no lo hace
- **Dónde:** [README.md:26](README.md:26), [Hojas.swift:201](Sources/LimpiadorMac/Hojas.swift:201)
- **Qué pasa:** la compactación es Revisar, así que en «Liberar al máximo» queda en «No lo marco». El bloque «Sin borrar nada: comprimir, unir copias y compactar» nunca la incluye. En tu Mac sale con 0 KB.
- **Arreglo:** corregir los textos o decidir en el código su nivel para el máximo.
- **Verificación:** 1 de 1, media.

#### Cachés nuevas

#### ME60. La caché de DaVinci es Seguro con «Tus clips y proyectos no se tocan», sin mirar lo que contiene
- **Dónde:** [Escaner.swift:798-800](Sources/LimpiadorMac/Escaner.swift:798)
- **Qué pasa:** `Movies/CacheClip` es Seguro. Una guía y un foro (SlashCam) indican que Resolve puede guardar ahí también los medios optimizados; otras fuentes solo hablan de archivos `.dvcc`. El aviso «Archivos tuyos» solo salta con 3 vídeos de 2 MB o más, así que con 1 o 2 clips sigue Seguro. Si lo seleccionas a mano o con «Solo lo seguro», «Liberar al máximo» lo borra sin Papelera.
- **Arreglo:** Revisar salvo que solo haya archivos de caché (`.dvcc`); leer las ubicaciones reales de las preferencias de Resolve; quitar «Tus clips no se tocan» hasta confirmarlo.
- **Verificación:** 2 de 2 verificadores lo dan como alta. **Lo bajo a media:** no se marca solo, no se pudo confirmar que guarde medios optimizados, y estos se recrean desde el original mientras exista.

#### ME61. «Shared Dictionary» y «Webstore Downloads» de Chromium salen como caché Seguro marcada (familia de AL10)
- **Dónde:** [Indice.swift:864-866](Sources/LimpiadorMac/Indice.swift:864), [Escaner.swift:2715-2731](Sources/LimpiadorMac/Escaner.swift:2715)
- **Qué pasa:** con un «Code Cache» al lado, se dan por caché interna: Seguro, preseleccionada y dentro de «Liberar al máximo» si el navegador está cerrado. No se comprueba qué contienen (instalaciones de extensiones a medias, diccionarios que usan respuestas guardadas).
- **Arreglo:** Revisar y sin marcar hasta confirmar su contenido; quitar «las vuelve a crear».
- **Verificación:** 1 de 1, media.

#### Limpieza, Papelera y Deshacer

#### ME62. «Vaciar Papelera» del resumen borra lo que un programa tiene abierto
- **Dónde:** [Limpiador.swift:570-580](Sources/LimpiadorMac/Limpiador.swift:570), [Almacen.swift:440-447](Sources/LimpiadorMac/Almacen.swift:440)
- **Qué pasa:** borra cada hijo de `~/.Trash` sin mirar quién lo usa. El mismo contenido limpiado como elemento de la categoría Papelera sí se comprueba y se omite. El README promete que lo que está en uso no se toca.
- **Arreglo:** saltar lo abierto (como hace `borrarSueltos`) y contarlo como omitido, o usar el mismo camino que el elemento de la categoría.
- **Verificación:** 2 de 2 verificadores lo dan como alta. **Lo bajo a media:** es la Papelera, el usuario confirma un borrado para siempre y el daño típico es que la app que lo tenía abierto pierde un archivo que ya habías desechado.

#### ME63. Deshacer devuelve otro archivo si en la Papelera hay uno con el mismo nombre
- **Dónde:** [Limpiador.swift:734](Sources/LimpiadorMac/Limpiador.swift:734)
- **Qué pasa:** solo mira que exista algo en la ruta guardada, sin comparar dispositivo e inodo, que sí se guardan y que «Vaciar solo lo de esta limpieza» sí compara.
- **Arreglo:** comparar dispositivo e inodo y, si no coinciden, dejarlo pendiente y avisar.
- **Verificación:** 1 de 1, media.

#### ME64. Con dos elementos que se solapan, Deshacer se queda a medias y «movidos a la Papelera» cuenta de más
- **Dónde:** [Almacen.swift:202-205](Sources/LimpiadorMac/Almacen.swift:202), [Limpiador.swift:168](Sources/LimpiadorMac/Limpiador.swift:168)
- **Qué pasa:** si un elemento con una ruta dentro de una carpeta seleccionada va antes que la carpeta, se mueve primero el archivo y luego la carpeta sin él. Deshacer recrea la carpeta con el archivo y después no puede devolver la original («ya existe algo con ese nombre»).
- **Arreglo:** ordenar de padres a hijos y quitar de cada elemento las rutas que estén dentro de otra de la misma limpieza.
- **Verificación:** 1 de 1, media.

#### ME65. Un elemento que no se puede borrar se da por limpiado
- **Dónde:** [Limpiador.swift:552-567](Sources/LimpiadorMac/Limpiador.swift:552), [Utilidades.swift:385-388](Sources/LimpiadorMac/Utilidades.swift:385)
- **Qué pasa:** si `removeItem` falla en una carpeta sin permiso de lectura, `Rutas.hijos` devuelve una lista vacía y el elemento cuenta como borrado, con su tamaño como liberado. Con un enlace simbólico pasa lo mismo.
- **Arreglo:** que un error al listar marque el borrado como incompleto, y comprobar que la ruta ya no existe antes de contarla.
- **Verificación:** 1 de 1, media (reproducido con una caché en modo 000).

#### ME66. Un comando que falla o se agota no cuenta lo que sí liberó
- **Dónde:** [Limpiador.swift:400-414](Sources/LimpiadorMac/Limpiador.swift:400)
- **Qué pasa:** si el comando sale con error o se agota el tiempo, lo que ya quitó no se suma. El resultado dice «Calculado: 0 bytes» y atribuye la diferencia a otros programas.
- **Arreglo:** separar «terminó bien» de «cuánto liberó».
- **Verificación:** 1 de 1, media.

#### ME67. Regresión de hoy: tras mover algo con el Explorador o el Finder, la selección sigue viva y «Por seguridad, N elementos…» cuenta de más
- **Dónde:** [Limpiador.swift:131-134](Sources/LimpiadorMac/Limpiador.swift:131)
- **Qué pasa:** el `continue` nuevo de hoy salta los elementos cuyas rutas ya no existen, pero va después de `forzados += 1`. El resultado dice «Por seguridad, 1 elemento… se movió a la Papelera» de algo que no se tocó. Además, «Limpiar X» sigue sumando los bytes de lo que ya se movió. `Rutas.existe` sigue los enlaces, así que un enlace roto se salta sin aviso.
- **Arreglo:** contar `forzados` después del `continue`; que el Explorador quite o recalcule el elemento que movió; comprobar la existencia con `lstat`.
- **Verificación:** dos hallazgos fusionados, media.

#### ME68. El registro del Deshacer es frágil: sin escritura atómica, y si no cabe o no se entiende se pierde en silencio
- **Dónde:** [Limpiador.swift:701-716](Sources/LimpiadorMac/Limpiador.swift:701)
- **Qué pasa:** `ultima-limpieza.json` se escribe sin `.atomic` y con `try?`. Con el disco casi lleno, el archivo queda truncado: se pierde el Deshacer nuevo y también el anterior (reproducido en un volumen APFS de 100 MB). Un registro que no se puede leer se descarta sin aviso, y la siguiente limpieza lo sobrescribe.
- **Arreglo:** `.atomic`, apartar el registro ilegible con otro nombre y avisar, y decir en el resumen si no se pudo guardar el Deshacer. Va con el punto 10 de esta mañana (diario por movimiento).
- **Verificación:** dos hallazgos fusionados, media.

#### ME69. «Deshacer» dice que devuelve «todo», pero solo devuelve lo que fue a la Papelera
- **Dónde:** [Hojas.swift:720-727](Sources/LimpiadorMac/Hojas.swift:720), [Almacen.swift:421](Sources/LimpiadorMac/Almacen.swift:421)
- **Arreglo:** «Devuelve las N cosas que se enviaron a la Papelera (X)» y avisar de lo que no vuelve.
- **Verificación:** 1 de 1, media.

#### ME70. El Explorador puede mandar a la Papelera iCloud Drive, otras nubes, el correo, `.gnupg` y el interior de `.git` (amplía ME25), y el README promete lo contrario
- **Dónde:** [Utilidades.swift:480-491](Sources/LimpiadorMac/Utilidades.swift:480), [VistaExplorador.swift:166](Sources/LimpiadorMac/VistaExplorador.swift:166), [README.md:53](README.md:53)
- **Qué pasa:** `sePuedeBorrar` solo protege los llaveros, `.ssh`, la carpeta `.git` en sí y los `.jks` y `.keystore`. No usa la lista que `sePuedeModificar` sí tiene (líneas 503-506): Mail, Messages, Mobile Documents, CloudStorage, Containers, Group Containers, Pictures y `.gnupg`. En iCloud Drive y en las nubes, el borrado se propaga a los demás equipos. El README dice que esas zonas no se tocan «aunque se seleccionen».
- **Arreglo:** una sola lista de zonas protegidas para borrar y modificar, que incluya también `.gnupg` y el interior de `.git`. Reescribir la viñeta del README.
- **Verificación:** votos media y alta. Lo dejo en media, como ME25: es manual, pide confirmación y va a la Papelera.

#### ME71. La tarjeta del disco promete espacio libre inmediato que el modo por defecto no da
- **Dónde:** [VistaResumen.swift:157](Sources/LimpiadorMac/VistaResumen.swift:157)
- **Qué pasa:** «tendrás unos X libres» supone borrado definitivo, pero la confirmación se abre en «Mover a la Papelera», que dice «ahora no se libera nada».
- **Arreglo:** calcularlo según el modo, con el mismo criterio que la hoja.
- **Verificación:** 1 de 1, media.

#### ME72. «Hace 0 años» para lo que tiene entre 360 y 364 días
- **Dónde:** [Models.swift:764-767](Sources/LimpiadorMac/Models.swift:764)
- **Qué pasa:** se ve en la lista de «Sin uso» y en «Último uso».
- **Arreglo:** años = max(1, días/365) cuando los meses son 12 o más.
- **Verificación:** 1 de 1, media.

#### Revisión fresca de Escaner y Compresor

#### ME73. Un proyecto de Xcode en un disco desconectado sale como «Proyecto borrado», Seguro y marcado
- **Dónde:** [Escaner.swift:1398](Sources/LimpiadorMac/Escaner.swift:1398)
- **Qué pasa:** no tiene la excepción de `/Volumes` que sí usa `estadoDeProyectosBorrados` ([Escaner.swift:2009](Sources/LimpiadorMac/Escaner.swift:2009)). Es una caché que se regenera, pero el texto miente.
- **Arreglo:** si la ruta está en un volumen sin montar, «no se sabe»: no marcar.
- **Verificación:** 1 de 1, media.

#### ME74. Las versiones antiguas de Playwright y Puppeteer salen Seguro, marcadas y con «Nada»
- **Dónde:** [Escaner.swift:1476](Sources/LimpiadorMac/Escaner.swift:1476)
- **Qué pasa:** un proyecto que fija una versión antigua la vuelve a descargar (cientos de MB). El propio código dice que lo que cuesta descargas no se marca en el modo normal.
- **Arreglo:** Revisar o solo en «Liberar al máximo», con el coste de descarga.
- **Verificación:** 1 de 1, media.

#### ME75. Los temporales sueltos de Apple salen Seguro y se borran sin Papelera
- **Dónde:** [Escaner.swift:2994-2996](Sources/LimpiadorMac/Escaner.swift:2994)
- **Qué pasa:** los `.com.apple.Safari.XXXXXX` se recogen antes del filtro `com.apple.*`, que solo mira los nombres sin punto inicial.
- **Arreglo:** aplicarles el mismo filtro.
- **Verificación:** 1 de 1, media.

#### ME76. Una versión de Gradle en prerrelease (rc) sale como «Ningún proyecto la usa»
- **Dónde:** [Escaner.swift:1257-1263](Sources/LimpiadorMac/Escaner.swift:1257)
- **Qué pasa:** `gradle-9.0.0-rc-1-bin` se corta en el primer guion y queda «9.0.0», mientras que la carpeta se llama «9.0.0-rc-1». No casan, y la caché de esa versión sale Seguro y marcada.
- **Arreglo:** tomar la versión entre `gradle-` y `-bin` o `-all`, con una sola función.
- **Verificación:** 1 de 1, media.

#### ME77. «Ya descomprimido» se afirma solo porque existe una carpeta con el mismo nombre
- **Dónde:** [Escaner.swift:5616](Sources/LimpiadorMac/Escaner.swift:5616), [Escaner.swift:5641-5645](Sources/LimpiadorMac/Escaner.swift:5641)
- **Arreglo:** comparar los nombres y tamaños del índice del zip con la carpeta; si no coinciden, no decir «con su contenido».
- **Verificación:** 1 de 1, media.

#### ME78. Una descarga interrumpida de hace 1 día sale Seguro, preseleccionada y con «Nada»
- **Dónde:** [Escaner.swift:5394-5399](Sources/LimpiadorMac/Escaner.swift:5394)
- **Qué pasa:** el navegador puede conservarla para reanudar. En «Liberar al máximo» se borra sin Papelera y sin comprobar si cambió (ME47).
- **Arreglo:** Revisar, o varios días sin preseleccionar, con «el navegador puede reanudarla».
- **Verificación:** 1 de 1, media.

#### ME79. Con una ACL «deny delete», ditto no copia el archivo y su resto nunca se recoge, aunque el aviso promete borrarlo
- **Dónde:** [Compresor.swift:674](Sources/LimpiadorMac/Compresor.swift:674), [Compresor.swift:1103](Sources/LimpiadorMac/Compresor.swift:1103)
- **Qué pasa:** queda un `.BC.T_…` en una carpeta oculta `.limpiador-<UUID>`, y cada pasada añade otra. El original queda intacto.
- **Arreglo:** dejar fuera esos archivos antes de copiar y recoger también los restos de ditto.
- **Verificación:** 1 de 1, media.

#### Índice y utilidades

#### ME80. Un volumen montado dos niveles dentro de tu carpeta personal se indexa como si fuera tuyo
- **Dónde:** [Indice.swift:378](Sources/LimpiadorMac/Indice.swift:378), [Indice.swift:402](Sources/LimpiadorMac/Indice.swift:402), [Indice.swift:640](Sources/LimpiadorMac/Indice.swift:640)
- **Qué pasa:** cada carpeta de nivel 2 se recorre como una unidad propia, y `FTS_XDEV` solo compara con la raíz de esa unidad. El volumen entero entra en el índice y en las cifras.
- **Arreglo:** comparar el dispositivo de la raíz de cada unidad con el de tu carpeta personal.
- **Verificación:** 1 de 1, media.

#### ME81. `bytes(de:)` devuelve 0 para carpetas pequeñas que el índice no registró
- **Dónde:** [Indice.swift:264-270](Sources/LimpiadorMac/Indice.swift:264), [Escaner.swift:189](Sources/LimpiadorMac/Escaner.swift:189)
- **Qué pasa:** el elemento sale con 0 bytes y el filtro de 1 MB lo descarta aunque en total ocupe más.
- **Arreglo:** medirlas aparte, como ya hace `Escaner.tamanos`.
- **Verificación:** 1 de 1, media.

#### ME82. Si un proceso del `.zshrc` hereda la salida, se pierde el PATH de la terminal (familia de ME41)
- **Dónde:** [Utilidades.swift:24-37](Sources/LimpiadorMac/Utilidades.swift:24), [Utilidades.swift:703-705](Sources/LimpiadorMac/Utilidades.swift:703)
- **Qué pasa:** `Shell.ejecutar` espera el final de la tubería, y un proceso nieto la mantiene abierta. El PATH queda vacío y las comprobaciones que dependen de él se apagan.
- **Arreglo:** cerrar la lectura 2 s después de que salga el proceso, como ya hace `Shell.comando`.
- **Verificación:** 1 de 1, media.

#### ME83. «Acceso total» sale «no» si no existe `~/Library/Safari`, aunque el permiso esté dado
- **Dónde:** [Utilidades.swift:551-553](Sources/LimpiadorMac/Utilidades.swift:551)
- **Qué pasa:** con «no», el índice omite iCloud Drive, MobileSync, Containers y Group Containers, y la app muestra el aviso de permiso. En tu Mac sí existe esa carpeta y el diagnóstico real dice «Acceso total: sí».
- **Arreglo:** distinguir «la carpeta no existe» de «permiso denegado», o comprobar varias rutas protegidas.
- **Verificación:** dos hallazgos fusionados, media.

### Baja

Sin verificación adversarial, salvo donde se indica.

- **BA60. La «Fototeca de Photo Booth» en español no está en la lista de bibliotecas** — [Escaner.swift:5378](Sources/LimpiadorMac/Escaner.swift:5378). Hoy la salva que macOS la marca como paquete (lo comprobé con `mdls`: `com.apple.photo-booth-library`). Si pierde esa marca, saldría en «Sin uso». *Arreglo:* detectar las bibliotecas por su tipo o estructura, no por el nombre en inglés.
- **BA61. Una subcarpeta ilegible deja fuera toda la carpeta sin aviso** — [Escaner.swift:3451](Sources/LimpiadorMac/Escaner.swift:3451). *Arreglo:* bajar igualmente, omitir solo esa rama y decirlo en la ficha.
- **BA62. Syncthing, Resilio y los paquetes de VM (`.vmwarevm`) no se reconocen** — [Escaner.swift:3382-3392](Sources/LimpiadorMac/Escaner.swift:3382). *Arreglo:* ampliar las marcas (`.stfolder`) y la lista de paquetes.
- **BA63. `valorDeSteam` busca texto sin estructura** — [Escaner.swift:2538](Sources/LimpiadorMac/Escaner.swift:2538). Corta los valores con comillas escapadas y casa claves anidadas. *Arreglo:* un lector mínimo de KeyValues.
- **BA64. Solo se lee la biblioteca principal de Steam** — [Escaner.swift:2500](Sources/LimpiadorMac/Escaner.swift:2500). Se ignora `libraryfolders.vdf`. *Arreglo:* recorrer cada biblioteca y decirlo en la ayuda.
- **BA65. La regla 3 de Olvidados (Descargas de 90 días o más) queda casi muerta** — [Escaner.swift:5441](Sources/LimpiadorMac/Escaner.swift:5441). «Sin uso» se lo lleva todo antes, y el README la sigue prometiendo. *Arreglo:* limitarla a lo que «Sin uso» excluye y corregir README.md:22. Verificador: baja.
- **BA66. El inspector muestra elementos ocultos por el filtro, y su interruptor no hace nada** — [VistaCategoria.swift:79](Sources/LimpiadorMac/VistaCategoria.swift:79).
- **BA67. Los totales de «Sin uso» no se recalculan cuando un elemento cruza el plazo con la app abierta** — [Almacen.swift:183](Sources/LimpiadorMac/Almacen.swift:183).
- **BA68. «Cerrar y limpiar» no filtra lo anidado: cuenta dos veces lo movido** — [Almacen.swift:332](Sources/LimpiadorMac/Almacen.swift:332).
- **BA69. Con una colación propia, VACUUM falla y la base se sigue ofreciendo** — [Escaner.swift:2646](Sources/LimpiadorMac/Escaner.swift:2646).
- **BA70. Las carpetas de Apple sin el prefijo `com.apple` pueden ofrecerse para compactar** — [Escaner.swift:2549](Sources/LimpiadorMac/Escaner.swift:2549). Por ejemplo: Music, iMovie, Xcode, IntelligenceFlow. *Arreglo:* invertir la regla y permitir solo apps conocidas.
- **BA71. La confirmación no dice que la compactación no tiene vuelta atrás** — [Models.swift:346](Sources/LimpiadorMac/Models.swift:346). `esIrreversible` reconoce `sqlite3` por el nombre del programa. *Arreglo:* un tipo de acción propio y un texto que diga «reescribe la base».
- **BA72. Una base suelta en Application Support toma el nombre del archivo como app** — [Escaner.swift:2575](Sources/LimpiadorMac/Escaner.swift:2575). El texto dice «Cierra x.sqlite».
- **BA73. Rutas de Unreal y de Steam sin verificar en macOS** — [Escaner.swift:789](Sources/LimpiadorMac/Escaner.swift:789). Unreal 5.4 y posteriores usan Zen.
- **BA74. El comentario de Duplicados sobre «Sin uso» es falso: «Sin uso» se calcula después** — [Escaner.swift:5047](Sources/LimpiadorMac/Escaner.swift:5047).
- **BA75. Copias sobrantes de Codex: el texto dice «contenido» y «Nada»** — [Escaner.swift:2059-2097](Sources/LimpiadorMac/Escaner.swift:2059). La comparación es por nombre y tamaño, más la huella de los 20 mayores. La carpeta se borra entera, con su instalador `node-runtime.tar.xz` (338 MB en tu Mac). *Arreglo:* «se va la copia y su instalador; el entorno que usa Codex no se toca».
- **BA76. «Vaciar solo lo de esta limpieza» no ve lo que fue a la Papelera de un disco externo** — [Limpiador.swift:608](Sources/LimpiadorMac/Limpiador.swift:608).
- **BA77. Unir copias con una ACL «deny delete» deja el clon en Application Support** — [Clonador.swift:364](Sources/LimpiadorMac/Clonador.swift:364).
- **BA78. `--diagnostico` escribe `bytesIndiceAnterior` en las preferencias, también con una casa de prueba** — [Escaner.swift:55](Sources/LimpiadorMac/Escaner.swift:55). Ver «Incidencias». *Arreglo:* no escribir preferencias en el diagnóstico.
- **BA79. Un instalador sin versión en el nombre se da por «ya instalado» y se preselecciona** — [Escaner.swift:4711](Sources/LimpiadorMac/Escaner.swift:4711).
- **BA80. Los reportes de fallos (DiagnosticReports) nunca se ofrecen** — [Escaner.swift:4934](Sources/LimpiadorMac/Escaner.swift:4934). El filtro de «instalada» salta antes de su rama.
- **BA81. «1 elementos», «1 fotos», «1 vídeos»** — [VistaPrincipal.swift:190](Sources/LimpiadorMac/VistaPrincipal.swift:190), [VistaDetalle.swift:211-214](Sources/LimpiadorMac/VistaDetalle.swift:211). Verificador: baja.
- **BA82. «Cerrar y limpiar» con la app ya cerrada dice que «no se cerró»** — [Almacen.swift:344](Sources/LimpiadorMac/Almacen.swift:344).
- **BA83. VoiceOver: casillas sin nombre y filas que solo responden al clic** — [VistaCategoria.swift:241](Sources/LimpiadorMac/VistaCategoria.swift:241), [Hojas.swift:346](Sources/LimpiadorMac/Hojas.swift:346).
- **BA84. El diagnóstico ignora el plazo de «Sin uso» que eliges** — [LimpiadorMacApp.swift:162](Sources/LimpiadorMac/LimpiadorMacApp.swift:162).
- **BA85. Los recuentos usan siempre `es_PE` y los bytes, la región del Mac** — [Models.swift:752](Sources/LimpiadorMac/Models.swift:752).
- **BA86. El mínimo de 1 MB oculta cosas sin decirlo, salvo cuando la lista queda vacía** — [Escaner.swift:115](Sources/LimpiadorMac/Escaner.swift:115). En tu Mac es la causa principal del 0 en «Sin uso». *Arreglo:* «N elementos de menos de 1 MB no se muestran», y citarlo en el README.
- **BA87. El bloque «Se vuelve a descargar o a recompilar» incluye temporales que no se descargan** — [Hojas.swift:204](Sources/LimpiadorMac/Hojas.swift:204). Por ejemplo, los 100,7 MB de temporales de ChatGPT de tu Mac, que se borran sin Papelera.
- **BA88. La versión sigue en 3.0 (4) pese a los cambios de hoy (amplía BA32)** — [Recursos/Info.plist:13](Recursos/Info.plist:13). Según un revisor, la app instalada bajó de 3.0.2 (6) a 3.0 (4).
- **BA89. Los 7 avisos de Swift 6 estricto son falsos positivos** — [Escaner.swift:4317](Sources/LimpiadorMac/Escaner.swift:4317), [Indice.swift:405](Sources/LimpiadorMac/Indice.swift:405), [Utilidades.swift:589](Sources/LimpiadorMac/Utilidades.swift:589). El punto frágil es el closure `trabajo` de `enParalelo` (ver BA1). *Arreglo:* hacerlo genérico con `@Sendable`.
- **BA90. «Sin uso» lee el /Applications real también en una casa de prueba (amplía BA38)** — [Escaner.swift:3320](Sources/LimpiadorMac/Escaner.swift:3320), [README.md:108](README.md:108).
- **BA91. Erratas y frases que ya no son ciertas en el README e Info.plist:**
  - «Todo ~/.cache» (README.md:14): Unreal y los registros de npm no están ahí.
  - «según Steam» (README.md:18): sin `LastPlayed`, la fecha es la del manifiesto.
  - Falta el punto antes de «También compacta» (README.md:26).
  - Los textos de permiso de Escritorio y Documentos no mencionan «Sin uso» ni Lightroom (Info.plist:19-21).
- **BA92. «Sin uso» nunca ofrece las apps de Apple que instalaste tú (Xcode, GarageBand, Pages)** — [Escaner.swift:3334](Sources/LimpiadorMac/Escaner.swift:3334). *Arreglo:* excluir solo las del sistema, o documentarlo.
- **BA93. Olvidados lista una carpeta y una subcarpeta suya** — [Escaner.swift:5489](Sources/LimpiadorMac/Escaner.swift:5489).
- **BA94. Un registro de apps comprimidas ilegible se sobrescribe** — [Apps.swift:145-162](Sources/LimpiadorMac/Apps.swift:145). Se pierde la lista de las compresiones anteriores.
- **BA95. Sin `lote.txt`, las copias sobrantes de una unión se quedan, y el aviso dice que «no coinciden»** — [Clonador.swift:361](Sources/LimpiadorMac/Clonador.swift:361).
- **BA96. Si el disco se llena al comprimir, el mensaje culpa a ditto y no dice que falta espacio** — [Compresor.swift:674](Sources/LimpiadorMac/Compresor.swift:674).
- **BA97. El modelo del Mac está escrito a mano en el resumen** — [VistaResumen.swift:32](Sources/LimpiadorMac/VistaResumen.swift:32). Dice «MacBook Air (M2) · 16 GB · SSD de 256 GB»; mejor leerlo con `sysctl hw.model` y `hw.memsize`.

## Por qué «Sin uso» sale con 0 en tu Mac

Lo investigó un agente aparte, solo con `stat`, `ls`, `du` y `mdls`, sin abrir ningún archivo tuyo. El 0 es correcto con los datos de hoy, salvo un caso:

1. **El mínimo de 1 MB.** Los 10 candidatos viejos del primer nivel pesan menos de 0,05 MB cada uno: Zoom, antigravity, MainStage, Logic, GarageBand y un `.docx` en Documentos, y SpaceWork, default.sfx, Apuestas y XiaomiMiMoProjects en tu carpeta personal.
2. **Lo grande tiene uso reciente:** `Lev.mp3` y `LimpiadorUltra-main` cambiaron hoy, `Innovacion` (70 MB) tiene una lectura de hoy a las 11:00, `Lanzamiento Vercel` una de las 14:08 y `Documents/ChatGPT` lecturas del 20 de octubre. Música, la biblioteca de iMovie y Fotos son bibliotecas y quedan fuera a propósito.
3. **En apps:** Mes de Septiembre (492 KB), ZoomLauncher (968 KB) y Claude Code URL Handler (4 KB) no llegan a 1 MB. Postgres está abierto y Xcode queda fuera por ser de Apple (BA92). 16 de tus 18 apps tienen fecha de uso en Spotlight.
4. **El fallo:** `Documents/Codex` (6 MB, 11,6 días sin cambios visibles) debería salir, pero un `.DS_Store` de hace 5,7 días lo oculta (ME45).

Steam no está instalado, así que no hay juegos. Hacia mañana entrará Microsoft Excel (2,6 GB): Spotlight no tiene registro de que la hayas abierto, llegó hace casi una semana y su contenedor no cambia desde hace unos 52 días.

## Mejoras recomendadas

1. **Una sola lista de zonas protegidas** para borrar y para modificar (ME70), y **una sola función «nube o iCloud»** para «Sin uso», Olvidados, Duplicados y el Evaluador (ME52).
2. **Tratar la señal de uso como un dato propio:**
   - tomar la foto de fechas en el índice antes de cualquier lectura del análisis;
   - ignorar los archivos ocultos;
   - guardar cuántos archivos aportan la señal;
   - mostrar en la ficha qué señal manda (cambio, apertura, llegada o Spotlight) y su fecha;
   - comprobar esa misma señal antes de borrar (ME43-ME47).
3. **Que todas las categorías reciban lo ya ofrecido y lo que hay que conservar** (`ofrecidas` y `exigidas`), no solo «Sin uso»: Restos, Grandes y Olvidados (ME50, ME54).
4. **Un tipo de acción «compactar base»** en vez de reconocer `sqlite3` por el nombre. Así tendría su propio texto de irreversibilidad y de tiempo agotado, porque un VACUUM cortado se deshace solo y el texto actual dice «lo que ya hizo se queda hecho».
5. **Historial de varias limpiezas,** escrito con `.atomic` y con un diario por movimiento (AL16, ME68 y el punto 10 de esta mañana).
6. **Un diagnóstico que explique los ceros:** por qué se descarta cada candidato de «Sin uso» (mínimo, abierta, biblioteca, nube, otra categoría, señal reciente). Además, que no escriba preferencias y que imprima el bloque «Lo que marcaste tú» del máximo.
7. **Pruebas automáticas.** Un revisor comprobó en una copia que un `testTarget` con `@testable import LimpiadorMac` funciona: tres pruebas puras (`nuncaAbierta`, `esCarpetaDeNube`, `Formato.bytes`) pasaron. Las casas sintéticas de hoy (el `.log` en «logs», `/tmp/npm-…`, Maven, Lightroom, el WAL, la tabla «sqlitecache», el `.DS_Store`) son la primera batería de regresión.
8. **`Umbrales.swift`** (BA37) y **partir `Escaner.swift`** (5.902 líneas, BA34).
9. **Rendimiento y accesibilidad:** las filas buscan su elemento con un recorrido lineal y piden el icono en cada redibujado. No hay navegación con teclado ni nombres para VoiceOver (BA83).

## Lo que está bien hecho

- **«Sin uso» nunca se marca sola:** nivel «nunca», sin preselección y sin aviso que la haga marcable. En las cinco pasadas de prueba, todas las filas salieron sin marcar. Todo lo que no es Seguro, y todas las apps, van a la Papelera también en «Eliminar definitivamente».
- **El filtro de días desmarca lo que oculta,** y lo oculto no se puede marcar ni entra en el plan de «Liberar al máximo».
- **«Sin uso» excluye bien** las nubes por nombre y por marca oculta, los paquetes, los enlaces, los repositorios git (que suben a Cuidado), las bibliotecas de Música, Fotos e iMovie, las apps de fondo y la propia LimpiadorMac.
- **VACUUM es seguro en lo que maneja:**
  - 20 cortes con SIGKILL y SIGTERM, en los modos DELETE y WAL, sin daño;
  - números de fila conservados en 15 variantes con índice o clave entera;
  - con otra app escribiendo, sale con «database is locked» en 0,04 s sin tocar nada;
  - FTS5, tablas sin clave y bases de Apple quedan fuera.
- **Las copias sobrantes de Codex** se comparan con el entorno activo: `runtime.json`, archivos, tamaños y huella. Ningún enlace del entorno activo apunta a la carpeta de instalación, así que borrarla no rompe Codex.
- **Lightroom:** las rutas de las vistas previas coinciden con la ayuda de Adobe, y con el candado `.lrcat.lock` no se toca nada.
- **Comprimir y unir siguen siendo ejemplares:** comprueban byte a byte y comparan permisos, ACL, atributos, fechas y firma. Se recuperan de un corte en dos puntos y la firma de una app comprimida sigue siendo válida. Con 15 MB libres, comprimir se para antes de tocar nada, y el ahorro declarado coincide con el disco.
- **«Vaciar solo lo de esta limpieza»** compara dispositivo e inodo, y Deshacer nunca sobrescribe.
- **El primer arranque sin estado funciona:** sin registros y sin Acceso total, el diagnóstico sale sin errores.
- **Las cifras del diagnóstico real cuadran:** 6 de 6 tamaños coinciden con `du`, y lo preseleccionado (41,6 MB) se regenera de verdad.

## Plan de trabajo sugerido

**Etapa 1 — Que nada se borre para siempre por error (2-4 días).**
- La raíz de esta mañana: en «Liberar al máximo», sin Papelera solo una lista cerrada de cachés.
- CR4 (`.log` en «logs»), AL13 con AL5 (/tmp), AL14 (Maven) y AL15 con ME31 (simuladores y comandos, y los textos).
- ME61 (Chromium), ME75 (temporales de Apple), ME78 (descargas a medias), ME74 (Playwright).
- Lo crítico de esta mañana que sigue: CR1, CR2 y CR3.

**Etapa 2 — «Sin uso» y compactar (3-5 días).**
- AL17 (Lightroom).
- La señal: ME43-ME47.
- Selección y textos: ME48-ME54.
- Compactar: ME55-ME59 y BA69-BA71.

**Etapa 3 — Deshacer, Papelera y cifras (3-4 días).**
- AL16 y ME62-ME69.
- El diario del Deshacer (punto 10 de esta mañana).
- ME57 y BA42 (totales).

**Etapa 4 — Pruebas (3-5 días).** El `testTarget` y las casas sintéticas de hoy como batería de regresión, ejecutada desde `crear-app.sh`.

**Etapa 5 — Mejoras (opcional).** Las listas únicas, partir Escaner.swift, `Umbrales.swift`, Swift 6, accesibilidad y git.

## Cómo se hizo este análisis

- **Base de comparación:** el zip de esta mañana (`~/Downloads/LimpiadorUltra-main.zip`), comparado con el código actual: 1.159 líneas de diferencias.
- **Compilación:** release limpia (0 avisos, 79,8 s) y compilación con concurrencia estricta de Swift 6 (los mismos 7 avisos de esta mañana).
- **Diagnóstico real de solo lectura** a las 14:27, con Acceso total: 286.543 archivos indexados (24,95 GB), 17,25 GB encontrados, 41,6 MB preseleccionados y 789 procesos.
- **15 revisores de área y 5 comprobadores del estado de los 116 hallazgos anteriores:**
  - La mitad, centrados en lo nuevo de hoy: «Sin uso» en tres partes, SQLite en dos, cachés de medios, Codex y Chromium.
  - La otra mitad, con ojos frescos sobre lo que no cambió: limpieza, compresión, índice, Escaner en dos mitades e interfaz.
  - Uno para el diagnóstico real y otro para la compilación y la documentación.
  - Usaron lectura de código, arneses con el código real, casas sintéticas con `LIMPIADOR_CASA` y `--diagnostico`, y volúmenes APFS de prueba.
- **Verificación adversarial:**
  - cada crítico y alto, con dos verificadores que intentaban refutarlo (uno con el código y otro reproduciendo);
  - cada medio, con uno;
  - cada cambio de estado de un hallazgo anterior, con uno.
- **Crítico de completitud:** propuso 4 huecos, que se revisaron y verificaron igual: por qué «Sin uso» da 0 en tu Mac, los cruces entre categorías, el primer arranque sin Acceso total y el disco casi lleno.
- **Síntesis:** comprobé en persona el código de todos los críticos y altos, ajusté severidades (de 4 críticos queda 1; DaVinci y «Vaciar Papelera» bajan de alta a media) y fusioné duplicados.
- **Modelos:** 142 agentes, todos con Haiku 5.5, según tu regla para más de 5 subagentes. Unas 2 h 45 min en paralelo, 4.802 llamadas a herramientas y 23,8 millones de tokens. La síntesis, con Opus 5.5.
- **Resultado:** 124 hallazgos en bruto. Tras fusionar quedan 85: **1 crítico, 5 altos, 41 medios y 38 bajos**. Hay además 4 refutados (ver el apéndice). Los bajos no pasaron por verificación adversarial.
- **Comprobación final:** el código del proyecto no cambió durante el análisis (huellas iguales al principio y al final).

### Incidencias

No se modificó nada de tu proyecto. Los agentes no leyeron el contenido de tus archivos personales, porque eso habría cambiado la fecha de acceso que usa «Sin uso»: solo usaron `stat`, `ls`, `du`, `find` y `mdls`. Hubo cuatro incidencias menores:

- **Preferencias del binario de terminal.** Las ejecuciones de `--diagnostico` con casas de prueba escribieron `bytesIndiceAnterior` en `~/Library/Preferences/LimpiadorMac.plist` (BA78). Es el dominio del binario suelto, no el de tu app instalada: `com.gustavo.LimpiadorMac` está intacto (25,58 GB, de tu propio uso). Solo afecta a la barra de progreso del próximo diagnóstico por terminal, y se corrige sola.
- **Archivos de preferencias sueltos.** Los arneses dejaron tres archivos con una sola clave (`LimpiadorDbg.plist`, `arnes.plist` y `arnes-dbg.plist`), que ya borré. Quedan `arnes_indice.plist` (de las 00:42, probablemente del análisis de esta mañana) y unos `LimpiadorMac-*.plist` y `limpiador-1mb.plist` del 9 de octubre. Esos no los toqué.
- **Datos de prueba.** Un agente llegó a unos 1,5 GB de datos de prueba, por encima del límite de 1 GB, antes de borrarlos.
- **Limpieza.** Todas las carpetas de trabajo y los volúmenes de prueba están borrados. La Papelera real no se tocó.

## Apéndice: hallazgos refutados o descartados

- **«La Fototeca de Photo Booth en español sale como Sin uso»:** no ocurre en tu Mac. macOS la marca como paquete (`com.apple.photo-booth-library`) y «Sin uso» salta los paquetes. Queda como hueco latente (BA60).
- **«Spotlight da como último uso la fecha de creación de la app»:** refutado. Solo le pasa a un paquete que Spotlight no indexa; en tu Mac, 0 de 65 apps indexadas.
- **«Una base dentro de una carpeta que también se borra infla lo liberado»:** refutado tal como estaba escrito. La carpeta va a la Papelera y lo calculado coincide con lo medido. Lo que sí es real, el total encontrado inflado, quedó en ME57.
- **«El Explorador se queda en "Midiendo…" para siempre»:** el defecto de código existe ([VistaExplorador.swift:180-193](Sources/LimpiadorMac/VistaExplorador.swift:180)), pero no se reproduce en macOS 27, porque `du` termina en 0,02 s (ver ME42). Se arregla con una línea.
- **Partes corregidas por los verificadores:**
  - Ejecutar un binario o un script directamente sí deja fecha de acceso; leerlo no (ME43).
  - `read()` sí actualiza la fecha de acceso cuando el archivo cambió desde la última lectura (ME43).
- **Hipótesis mías que no se sostienen:**
  - «VACUUM renumera las filas de las tablas con índice»: no, se conservan en las 15 variantes probadas con el SQLite 3.54 del sistema. Ojo: SQLite solo lo garantiza para INTEGER PRIMARY KEY, así que conviene una prueba de regresión.
  - «El diagnóstico real o los agentes refrescaron las fechas de acceso de tus archivos»: no se ven lecturas de hoy en tus carpetas, salvo dentro de `.build` del proyecto (11:40 y 12:39) y una de `Innovacion` a las 11:00, anterior al diagnóstico.
