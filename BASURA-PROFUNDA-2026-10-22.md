# Basura a fondo — 22 de octubre de 2026 (tarde)

Segunda ronda de la búsqueda de basura en este Mac (MacBook Air M2, 245 GB). Tras la ronda de la mañana (versión 3.1) el
usuario solo había liberado unos 3 GB. Ahora se investigó todo el disco, zona por zona, y LimpiadorMac pasa a la **versión
3.2 (6)**.

## En pocas palabras

- **«Datos del sistema» (unos 50 GB en Ajustes) ya se explica dentro de la app**, en una vista nueva. De esos 50 GB,
  **13,25 GB se liberan con tres ajustes**, y quizá 2,27 GB más:
  - Apple Intelligence: 6,32 GB;
  - modelo de finalización predictiva de Xcode: 5,2 GB, del que hay **dos generaciones bajadas** y que está sin usar,
    porque las predicciones en el Mac están apagadas;
  - documentación de Xcode: 1,73 GB, que macOS no borra nunca solo.

  La app no borra nada de esto: cada partida trae un botón que abre su ajuste.
- **Lo que los botones liberan de verdad se ha duplicado.** Por la mañana, con todos los botones, se llegaba como mucho a
  unos 5 GB de los 22 GB encontrados, y «Seleccionar lo recomendado» marcaba 40 MB. Ahora, en el diagnóstico de la versión
  final:

  | Qué | Cuánto |
  |---|---|
  | Se libera ya (lo recomendado) | 3,12 GB |
  | Con «Liberar al máximo» | 6,92 GB en total |
  | Cerrando además las apps («Cerrar y limpiar») | 10,99 GB en total |
  | Para revisar | 6,14 GB |
  | Datos tuyos (Cuidado) | 0,95 GB |

- La causa principal era la app, no la falta de basura:
  - basura Segura que nunca se podía limpiar porque la «usaba» una app o un servicio que no se cierra;
  - elementos Seguros creados sin poder marcarse;
  - una base de 1,5 GB vacía contada dos veces.

## Dónde está el espacio

| Zona | Tamaño | Qué es |
|---|---|---|
| Volumen de datos | ~96 GB | Tus archivos, las apps y casi todo «Datos del sistema» |
| macOS (Sistema + Arranque + Recuperación) | ~26 GB | El sistema sellado, su arranque (con Rosetta, 7,72 GB) y la recuperación |
| Recursos de Apple (AssetsV2) | 17,8 GB reales | Modelos y datos que baja macOS; 11,5 GB solo se pueden medir por sus descriptores |
| Lo que solo ve root | ~22 GB | Spotlight, el historial de eventos (.fseventsd, 18.800 archivos), versiones de documentos y bases de /var/db |
| Registros unificados | 2,1–2,5 GB | Persist solo cubre ~27 h: algo escribe demasiado |
| Imagen de hibernación | 2,15 GB | La necesita el portátil para dormir; no es basura |
| Purgable | 5,1 GB | macOS lo suelta solo cuando hace falta |

En recursos de Apple, además de lo de arriba, hay cosas que quizá sobran: un segundo español de dictado (569 MB), dictado
en inglés (721 MB, si no dictas en inglés), una voz de Siri que no usas (Luisa, 234 MB) y los datos de chino y japonés
(92 MB). **Rosetta** ocupa 7,72 GB y ninguna app tuya la necesita (la trajo «4uKey for Android», ya desinstalada), pero macOS
no deja quitarla.

## Qué hace nuevo la app

**Desbloqueos** (basura Segura que antes nunca se liberaba):
- **Copias de Codex**: la copia sobrante (2,03 GB) y la instalación fallida (302 MB) se marcan aunque ChatGPT esté abierta.
  Solo se vigila quién trabaja dentro de ellas, y se ignoran las cachés .pyc que el entorno activo genera al usarse.
- **Base de Codex** (`thread_history_1.sqlite`): tiene 1,53 GB vacíos y se compacta con «Cerrar ChatGPT y limpiar».
  Antes de compactar guarda un clon de respaldo y después comprueba la base con `integrity_check`. Solo se hace con bases
  de apps conocidas.
- **Cachés de servicios de macOS** que siempre están en marcha (Mapas, fondos, Siri, App Store…): se ofrecen sus archivos
  de más de 24 h que nadie tiene abiertos, nunca sus bases de datos, y se vuelven a mirar uno por uno justo antes de borrar.
- **Claude Code ya no se confunde con Claude**: la caché interna de Claude (329 MB) entra en «Cerrar Claude y limpiar», que
  avisa de que cerrar Claude cierra también las sesiones de Claude Code que lanzó.
- **NuGet (771 MB), Cargo, Ivy y Firebase**: entran en «Liberar al máximo», con el coste de volver a descargarlos.
- **Regla de «cambio reciente»**: ya no pasa a Revisar lo Seguro; espera a que lleve 30 minutos sin cambios.
  «Seleccionar lo recomendado» y «Comprobar otra vez» vuelven a mirar qué está en uso.
- **Resumen y hoja Limpiar**:
  - el resumen reparte el total en *se libera ya / con máximo / cerrando apps / Seguro pero hoy no / Revisar / Cuidado*;
  - cada elemento que se queda fuera dice su razón real;
  - la hoja Limpiar propone «Eliminar definitivamente» solo si todo se regenera de verdad.

**Detecciones nuevas** (las de este Mac, con su tamaño):
- **Brave**:
  - la actualización descargada esperando a que se reinicie (669 MB);
  - los datos de un sitio visitado una sola vez (648 MB) y los de otro sitio sin cambios en 45 días (434 MB), para
    revisar;
  - Screen AI y componentes (136 MB), solo con «Liberar al máximo»;
  - versiones viejas de extensiones y otras cachés pequeñas.
- **Restos**: los de Google Chrome desinstalado (51 MB; su perfil va aparte, como Cuidado), Microsoft Teams y MainStage, y
  los sonidos de GarageBand en /Library.
- **Herramientas de IA, para revisar**: Cline instalado con npm y sin configurar (260 MB), muse (101 MB), Cursor Agent sin
  sesión (92 MB), dependencias de plugins de opencode (64 MB) y puntos de control de Claude Code de proyectos borrados.
- **Codex**: el servidor en segundo plano de la terminal, parado (146 MB, para revisar), y unir la copia del codex-cli con
  la de ChatGPT.app (334 MB, sin tocar la app).
- **Compilaciones**: salidas de .NET escritas fuera del proyecto y versiones anteriores de lo que publicaste. Las carpetas de
  respaldo de un proyecto se comparan con su original. Una carpeta que ya está entera en su zip se compara por contenido
  (CRC).
- **Android, Gradle y Homebrew**:
  - dependencias de Gradle de proyectos que ya no existen;
  - extras obsoletos del SDK;
  - CocoaPods sin ningún Podfile;
  - adb repetido entre Homebrew y el SDK;
  - casks sin su app;
  - toolchains de Swift y .xip de Xcode.
- **Registros y temporales**:
  - registros e informes de cierre de WhatsApp, diagnósticos de Word y catálogo de plantillas de Office repetido;
  - sombreadores de Metal de 85 programas;
  - informes de fallos de todo el Mac (/Library/Logs/DiagnosticReports);
  - caché de imágenes remotas de Mail (nunca correos ni adjuntos).
- **Vista «Datos del sistema»**:
  - todo lo de la tabla de arriba, con el ajuste que libera cada cosa;
  - «Vaciar las miniaturas» (`qlmanage -r cache`) y «Medir con contraseña» (un `du` de solo lectura);
  - los restos de root con el comando exacto para copiarlo: Muse Hub funcionando como root sin su app, los servicios de
    OneDrive, la cámara virtual de OBS y 11 recibos de apps que ya no están. La app nunca ejecuta `sudo`.

**Arreglo transversal**: el análisis ya no cambia la fecha de último acceso de lo que lee (`IOPOL_ATIME_UPDATES_OFF`). Antes,
analizar estropeaba la señal de uso que la propia app usa para «Sin uso».

## Lo que no se puede o no se debe hacer desde la app

- **Ajustes** (te toca a ti, desde los botones de la vista):
  - Apple Intelligence: Ajustes › Apple Intelligence y Siri;
  - modelo y documentación de Xcode: Xcode › Ajustes › Components;
  - idiomas de dictado: Ajustes › Teclado › Dictado.
- **Rosetta**: 7,72 GB que no se pueden desinstalar.
- **Lo de root**: Spotlight, registros, recibos y helpers huérfanos. Se enseñan los comandos, que exigen tu contraseña.
- **Microsoft Excel** (2,6 GB): no lo has abierto nunca. Hoy no sale en «Sin uso» porque Microsoft AutoUpdate lo actualizó
  esta mañana; volverá a salir dentro de 7 días. Si no lo usas, puedes llevarlo a la Papelera tú.
- **Módulos de Go**: Go los deja de solo lectura, así que la app no los marca (borrarlos fallaría a medias).
- **Pythons de uv sin entornos**: siguen para revisar, porque hay gestores de entornos que la app no ve.

## Cómo se hizo y cómo se comprobó

1. **Investigación de solo lectura**: 12 agentes, uno por zona. Usaron solo metadatos, sin abrir ningún archivo tuyo.
   Hallazgos en el scratchpad de la sesión (`inv/*.md`).
2. **Implementación**: 9 paquetes, cada uno en su copia del proyecto, con una carpeta personal sintética y casos trampa.
   Después se unieron.
3. **Revisión adversarial**:
   - 7 revisores y 35 verificadores independientes confirmaron 35 defectos (1 grave);
   - 3 agentes revisaron y arreglaron los 3 últimos paquetes;
   - en total se arreglaron **53 defectos**, cada uno con su prueba antes y después.
4. **Regresión final**: 3 agentes volvieron a pasar las pruebas de los 9 paquetes con el binario final. No hubo ninguna
   regresión.
5. **Compilación**: release limpia. El diagnóstico real (`--diagnostico --maximo`, solo lectura) termina en ~28 s sin errores.

Copia del proyecto anterior a esta ronda: `antes-ronda3/` en el scratchpad de la sesión.
