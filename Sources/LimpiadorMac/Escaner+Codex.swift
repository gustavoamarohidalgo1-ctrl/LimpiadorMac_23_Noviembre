import Foundation

/// Codex (la app de ChatGPT y el codex de la terminal) y las descargas que nunca se limpian solas: lo que ChatGPT deja
/// en ~/.codex y en tus temporales, los paquetes de NuGet y de quién es cada base de datos que se compacta.
extension Escaner {

    // MARK: - Utilidades de estas reglas

    /// Qué es lo que hay en esa ruta (S_IFDIR, S_IFREG, S_IFLNK…), sin seguir enlaces. nil si no existe.
    fileprivate static func tipoDe(_ ruta: String) -> mode_t? {
        var st = stat()
        return lstat(ruta, &st) == 0 ? (st.st_mode & S_IFMT) : nil
    }

    /// Un archivo pequeño (256 KB o menos), como texto, sin seguir enlaces.
    fileprivate static func textoPequeno(_ ruta: String, maximo: Int64 = 262_144) -> String? {
        var st = stat()
        guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, Int64(st.st_size) <= maximo else { return nil }
        return try? String(contentsOfFile: ruta, encoding: .utf8)
    }

    /// La lectura más reciente (atime) de los archivos de una carpeta, sin seguir enlaces. macOS la apunta, como mucho, una
    /// vez al día: sirve para saber si un programa se usa desde hace semanas, no desde hace horas. nil si tiene demasiados
    /// archivos para mirarlos todos (entonces no se sabe).
    fileprivate static func ultimaLectura(en carpeta: String, maximo: Int = 20_000) -> Date? {
        guard let e = FileManager.default.enumerator(atPath: carpeta) else { return nil }
        var ultima = 0
        var vistos = 0
        while let rel = e.nextObject() as? String {
            vistos += 1
            if vistos > maximo { return nil }
            var st = stat()
            guard lstat(carpeta + "/" + rel, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
            ultima = max(ultima, Int(st.st_atimespec.tv_sec), Int(st.st_mtimespec.tv_sec))
        }
        return ultima > 0 ? Date(timeIntervalSince1970: TimeInterval(ultima)) : nil
    }

    // MARK: - De quién es cada base de datos

    /// Carpetas cuyas bases de datos son de una app concreta: mientras esté abierta no se compacta ninguna, y «Cerrar y
    /// limpiar» ofrece cerrarla. ~/.codex es de ChatGPT (su Codex) y del codex de la terminal. Las demás bases se vigilan
    /// por quién trabaja en su carpeta.
    static let duenasDeBases: [(rel: String, nombre: String, texto: String, claves: [String])] = [
        (".codex", "ChatGPT", "ChatGPT (y el codex de la terminal)", ["com.openai.codex", "codex"]),
    ]

    /// La app dueña de la carpeta de una base de datos (`duenasDeBases`): cómo nombrarla y cuándo está en uso.
    static func appDuenaDeBase(_ ruta: String) -> (nombre: String, uso: EnUso)? {
        for d in duenasDeBases where ruta.hasPrefix(Rutas.enHome(d.rel).path + "/") {
            return (d.texto, .app(nombre: d.nombre, claves: d.claves))
        }
        return nil
    }

    // MARK: - Ganchos

    /// Lo que se añade a «Cachés de desarrollo» de Codex: su servidor de terminal parado. (Sus registros van en
    /// «Registros y fallos»: `registrosDeCodex`.)
    func codexAmpliado(_ c: Contexto) -> [Elemento] {
        servidorDeCodexParado(c)
    }

    // MARK: - Servidor en segundo plano del codex de la terminal

    /// ~/.codex/packages/app-server-daemon: el servidor en segundo plano que lanza el codex de la terminal (y que se
    /// actualiza solo). ChatGPT no lo usa: lleva su propio codex. Se ofrece si no está funcionando (ningún programa de
    /// dentro ni nada que trabaje en él, lo nombre o escuche en su carpeta de estado, ~/.codex/app-server-daemon), ningún
    /// comando de la terminal lleva a él y sus programas llevan 14 días o más sin leerse. Revisar: si vuelves a usar codex
    /// en la terminal, lo vuelve a descargar. Su carpeta de estado (pocos KB) se queda.
    func servidorDeCodexParado(_ c: Contexto) -> [Elemento] {
        let carpeta = Rutas.enHome(".codex/packages/app-server-daemon")
        let estado = Rutas.enHome(".codex/app-server-daemon")
        let versiones = Rutas.hijos(carpeta.appendingPathComponent("releases")).filter { Self.tipoDe($0.path) == S_IFDIR }
        guard Self.tipoDe(carpeta.path) == S_IFDIR, !versiones.isEmpty, c.apps.comandoDentro(de: carpeta.path) == nil,
              c.procesos.usando(carpeta.path) == nil, c.procesos.usando(estado.path) == nil,
              !c.procesos.lineas.contains(where: { $0.contains("app-server-daemon") }) else { return [] }
        let lecturas = versiones.map { Self.ultimaLectura(en: $0.path) }
        // Si alguna no se pudo mirar entera, no se sabe si se usa.
        guard !lecturas.contains(where: { $0 == nil }), let leido = lecturas.compactMap({ $0 }).max(),
              Date().timeIntervalSince(leido) >= 14 * 86400 else { return [] }
        let bytes = c.indice.bytes(de: carpeta)
        let nombres = versiones.map(\.lastPathComponent).sorted()
        return [Elemento(
            nombre: "Servidor en segundo plano del codex de la terminal",
            detalle: "El servidor que lanza el codex de la terminal y que se actualiza solo (\(Formato.listaCorta(nombres))). ChatGPT no lo usa: lleva su propio codex.",
            consecuencia: "Si vuelves a usar codex en la terminal, lo vuelve a descargar (unos \(Formato.bytes(bytes)); necesita internet). El comando codex de la terminal, tu configuración y tu historial no se tocan.",
            rutas: [carpeta], categoria: .desarrollo, riesgo: .revisar,
            motivos: [.info("moon.zzz.fill", "Parado",
                            "No está funcionando y sus programas no se usan desde \(Formato.haceCuanto(leido).lowercased()).")],
            enUso: .rutas(nombre: "codex", raiz: carpeta.path), dueno: "Codex", costes: [.descarga(bytes: bytes)])]
    }

    // MARK: - Registros de Codex

    private static let patronBaseDeCodex = try! NSRegularExpression(pattern: #"^(logs|state|thread_history)_(\d+)\.sqlite$"#)

    /// «logs_2.sqlite» (o su -wal, -shm o -journal): la base de registros de Codex. No la ofrece «Carpetas ocultas» como tu
    /// historial: la ofrece `registrosDeCodex`.
    static func esRegistroDeCodex(_ nombre: String) -> Bool {
        var n = nombre
        for s in ["-wal", "-shm", "-journal"] where n.hasSuffix(s) { n = String(n.dropLast(s.count)) }
        guard let (base, _) = baseDeCodex(n) else { return false }
        return base == "logs"
    }

    /// «logs_2.sqlite» → («logs», 2): las bases de Codex llevan detrás la versión de su formato.
    private static func baseDeCodex(_ nombre: String) -> (String, Int)? {
        guard let m = patronBaseDeCodex.firstMatch(in: nombre, range: NSRange(nombre.startIndex..., in: nombre)),
              let b = Range(m.range(at: 1), in: nombre), let v = Range(m.range(at: 2), in: nombre), let n = Int(nombre[v]) else { return nil }
        return (String(nombre[b]), n)
    }

    /// ~/.codex/logs_<n>.sqlite: los registros (trazas) de Codex, no tu historial (que va en thread_history_<n>.sqlite y
    /// en sessions). La más nueva, para revisar, con ChatGPT y codex cerrados. Las de una versión anterior (hay otra
    /// logs_<m> más nueva) son un resto de cuando Codex cambió de formato: Seguro si llevan 7 días sin cambios y nadie las
    /// tiene abiertas. Siempre con sus -wal, -shm y -journal (una base sin ellos queda rota).
    func registrosDeCodex(_ c: Contexto) -> [Elemento] {
        let carpeta = Rutas.enHome(".codex")
        var bases: [(url: URL, version: Int)] = []
        for h in Rutas.hijos(carpeta) where Self.tipoDe(h.path) == S_IFREG {
            guard let (base, v) = Self.baseDeCodex(h.lastPathComponent), base == "logs" else { continue }
            bases.append((h, v))
        }
        guard let nueva = bases.map(\.version).max() else { return [] }
        let duena = Self.appDuenaDeBase(carpeta.path + "/x")
        var r: [Elemento] = []
        for b in bases.sorted(by: { $0.version > $1.version }) {
            let rutas = [b.url] + ["-wal", "-shm", "-journal"].map { URL(fileURLWithPath: b.url.path + $0) }
                .filter { Self.tipoDe($0.path) == S_IFREG }
            let cambio = c.indice.masReciente(de: rutas)
            if b.version == nueva {
                r.append(Elemento(
                    nombre: "Registros de Codex (\(b.url.lastPathComponent))",
                    detalle: "La base de datos donde Codex (el de ChatGPT y el de la terminal) apunta lo que hace por dentro: sus trazas. Tus conversaciones están en otros archivos (thread_history, sessions).",
                    consecuencia: "Se pierden los registros de Codex: solo sirven para diagnosticar errores. Codex crea la base de nuevo al arrancar. Tus conversaciones e historial no se tocan.",
                    rutas: rutas, categoria: .registros, riesgo: .revisar,
                    motivos: [.info("doc.text.magnifyingglass", "Solo registros",
                                    "Por su nombre (logs_\(b.version)) es la base de registros de Codex, no tu historial. Ciérralo antes: con ChatGPT o codex abiertos no la toco.")],
                    enUso: duena?.uso, dueno: "Codex"))
            } else {
                let quieta = cambio.map { Date().timeIntervalSince($0) >= 7 * 86400 } ?? false
                r.append(Elemento(
                    nombre: "Registros antiguos de Codex (\(b.url.lastPathComponent))",
                    detalle: "Registros de Codex en un formato anterior: ahora los apunta en logs_\(nueva).sqlite.",
                    consecuencia: "Nada: Codex ya no escribe aquí (usa logs_\(nueva).sqlite) y solo son registros.",
                    rutas: rutas, categoria: .registros, riesgo: quieta ? .seguro : .revisar, seleccionado: quieta,
                    motivos: [quieta
                        ? .bien("clock.arrow.circlepath", "Formato anterior", "Hay una versión más nueva (logs_\(nueva)) y esta no cambia desde \(Formato.haceCuanto(cambio).lowercased()).")
                        : .info("clock.fill", "Cambió hace poco", "Cambió \(Formato.haceCuanto(cambio).lowercased()): puede que Codex aún la esté pasando al formato nuevo.")],
                    enUso: .rutas(nombre: "Codex", raiz: b.url.path), dueno: "Codex", cambioAnalizado: cambio))
            }
        }
        return r
    }

    // MARK: - Paquetes de NuGet que no vienen de un servidor

    /// Los paquetes de ~/.nuget/packages que no vinieron de un servidor: NuGet apunta en <id>/<versión>/.nupkg.metadata de
    /// dónde salió cada uno («source»). Si es una carpeta (un feed local) y no una dirección http(s), puede que no se pueda
    /// volver a descargar. `sinLeer`: los que no tienen ese archivo, no dicen de dónde vinieron o no se pudieron leer (no se
    /// sabe); si hay demasiados para mirarlos todos, también cuenta.
    static func paquetesLocalesDeNuGet(_ raiz: URL) -> (nombres: [String], sinLeer: Int) {
        var nombres: [String] = []
        var sinLeer = 0
        var vistos = 0
        for id in Rutas.hijos(raiz) where !id.lastPathComponent.hasPrefix(".") && tipoDe(id.path) == S_IFDIR {
            for version in Rutas.hijos(id) where !version.lastPathComponent.hasPrefix(".") && tipoDe(version.path) == S_IFDIR {
                vistos += 1
                if vistos > 20_000 { return (nombres, sinLeer + 1) }
                guard let texto = textoPequeno(version.appendingPathComponent(".nupkg.metadata").path),
                      let json = try? JSONSerialization.jsonObject(with: Data(texto.utf8)) as? [String: Any],
                      let fuente = json["source"] as? String else {
                    sinLeer += 1
                    continue
                }
                let f = fuente.lowercased()
                if !f.hasPrefix("https://") && !f.hasPrefix("http://") {
                    nombres.append("\(id.lastPathComponent) \(version.lastPathComponent)")
                }
            }
        }
        return (nombres, sinLeer)
    }

    // MARK: - Temporales sueltos de una sesión que ya terminó

    /// Desde cuántas horas sin cambios un temporal suelto de la app `id` es de una sesión que ya terminó, y cómo decirlo.
    /// Con la app abierta, lo de antes de que arrancara (su programa más antiguo en marcha), con 2 h como mínimo; con la app
    /// cerrada (es una app instalada y no hay nada suyo en marcha), lo de más de 2 h. Nunca más de 24 h, lo de siempre, que
    /// es lo que vale si no se puede saber (sin saber qué está funcionando, una app que no se conoce o sin su hora de
    /// arranque).
    func sesionTerminada(de id: String, _ c: Contexto) -> (horas: Double, cuales: String) {
        let siempre = (horas: 24.0, cuales: "llevan 24 h o más sin cambios")
        let clave = id.lowercased()
        guard c.procesos.fiable, c.apps.bundleIDs.contains(clave) else { return siempre }
        let minimo = Self.horasSueltosMaximo
        let suyos = c.procesos.programas.filter { p in p.ids.contains { $0 == clave || $0.hasPrefix(clave + ".") } }.map(\.pid)
            + c.procesos.apps.filter { $0.bundleID == clave || $0.bundleID.hasPrefix(clave + ".") }.map(\.pid)
        if suyos.isEmpty {
            return (minimo, "llevan \(Self.textoHoras(minimo)) o más sin cambios, con la app cerrada: son de una sesión que ya terminó")
        }
        guard let arranco = suyos.compactMap(Self.arranque(de:)).min() else { return siempre }
        let horas = min(24, max(minimo, Date().timeIntervalSince(arranco) / 3600))
        guard horas < 24 else { return siempre }
        return (horas, "son de antes de que la app se abriera por última vez (\(Formato.haceCuanto(arranco).lowercased())), de una sesión que ya terminó")
    }

    /// Cuándo arrancó un proceso. nil si el sistema no lo dice.
    private static func arranque(de pid: pid_t) -> Date? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let t = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, t) == t, info.pbi_start_tvsec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    /// «24 h», «2 h», «2,5 h».
    static func textoHoras(_ h: Double) -> String {
        let redondeadas = (h * 10).rounded() / 10
        return redondeadas == redondeadas.rounded()
            ? "\(Int(redondeadas)) h" : String(format: "%.1f h", redondeadas).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - La copia del codex-cli que ChatGPT deja fuera de la app

    /// ChatGPT copia su codex-cli (CodexCLI.app, codex-code-mode-host, rg, la voz…) fuera de la app, en
    /// ~/.codex/plugins/.plugin-appserver/codex-cli, para su servidor de plugins, y la vuelve a copiar en cada
    /// actualización: una copia entera, no un clon. Cada archivo de 1 MB o más que coincide con el de la app (misma ruta
    /// dentro, mismo tamaño y misma huella del principio y del final) se puede cambiar por un clon del original: sigue en su
    /// sitio, con sus permisos y sus fechas, y deja de ocupar aparte. La app no se toca (solo se lee) y la copia no se borra
    /// (puede que el plugin de Chrome la use con ChatGPT cerrada). Al unir se compara byte a byte (`Clonador`). No se
    /// espera a que lleve un día sin cambios, porque es copia de un archivo firmado de la app; sí a que ChatGPT no se esté
    /// actualizando, y nunca con la copia abierta. Seguro, solo en «Liberar al máximo», como las demás uniones.
    func copiaDelCodexDeChatGPT(_ c: Contexto) -> [Elemento] {
        let copia = Rutas.enHome(".codex/plugins/.plugin-appserver/codex-cli").path
        let id = "com.openai.codex"
        guard Self.tipoDe(copia) == S_IFDIR else { return [] }
        // La app: la de Aplicaciones (en una casa de prueba, solo las de su ~/Applications).
        let enCasa = Rutas.hijos(Rutas.enHome("Applications")).filter { $0.pathExtension == "app" }
            .filter { Bundle(url: $0)?.bundleIdentifier?.lowercased() == id }.map(\.path)
        let candidatas = (Rutas.casaDePrueba ? [] : c.apps.rutasEnAplicaciones[id] ?? []) + enCasa
        guard let app = candidatas.first(where: { Self.tipoDe($0 + "/Contents/Resources/codex-cli") == S_IFDIR }),
              c.procesos.actualizadorEnMarcha(id: id, ruta: app) == nil,
              let recorrido = FileManager.default.enumerator(atPath: copia) else { return [] }
        let original = app + "/Contents/Resources/codex-cli"
        let nombreApp = Rutas.nombre(app).replacingOccurrences(of: ".app", with: "")
        var r: [Elemento] = []
        var vistos = 0
        while let rel = recorrido.nextObject() as? String {
            vistos += 1
            if vistos > 5_000 { break }
            let a = copia + "/" + rel
            let o = original + "/" + rel
            // La copia: un archivo normal tuyo, con un solo nombre, sin banderas especiales, que se puede cambiar y que nadie
            // tiene abierto. El original: un archivo normal del mismo tamaño en el mismo disco.
            guard let e = Compresor.EstadoArchivo(ruta: a), e.esRegular, e.tamano >= minimo, e.dueno == getuid(), e.enlaces == 1,
                  e.banderas & Clonador.banderasProhibidas == 0, e.modo & S_IRUSR != 0, access(Rutas.padre(a), W_OK) == 0,
                  getxattr(a, "com.apple.ResourceFork", nil, 0, 0, XATTR_NOFOLLOW) <= 0,
                  c.procesos.abiertos.hayAbierto(dentroDe: a) == nil,
                  let eo = Compresor.EstadoArchivo(ruta: o), eo.esRegular, eo.tamano == e.tamano, eo.dispositivo == e.dispositivo,
                  let info = Privado.consultar(a) else { continue }
            // Ya es un clon del original: no hay nada que ganar.
            if let io = Privado.consultar(o), info.clon != 0, info.clon == io.clon { continue }
            let comprimida = e.banderas & UInt32(UF_COMPRESSED) != 0
            let ahorro = comprimida ? e.ocupa : min(info.privado, e.ocupa)
            guard ahorro >= minimo, let h = Huella.parcial(URL(fileURLWithPath: a), tamano: e.tamano),
                  h == Huella.parcial(URL(fileURLWithPath: o), tamano: eo.tamano) else { continue }
            r.append(Elemento(
                nombre: "Unir la copia de \(Rutas.nombre(rel)) con la de \(nombreApp)",
                detalle: "\(nombreApp) copió su codex-cli fuera de la app (\(Formato.rutaCorta(copia))) para su servidor de plugins: \(rel) es una copia entera, de \(Formato.bytes(e.tamano)), del archivo que trae la app.",
                consecuencia: "No se borra nada ni cambia ninguna ruta: la copia sigue en su sitio, con sus permisos y sus fechas, pero el disco guarda su contenido una sola vez, junto al de \(nombreApp), y ahorras unos \(Formato.bytes(ahorro)). \(nombreApp) no se toca. Cuando se actualice, la volverá a copiar entera.",
                rutas: [URL(fileURLWithPath: a)], tamanoFijo: ahorro, ultimoUso: Date(timeIntervalSince1970: TimeInterval(e.modificado.s)),
                categoria: .duplicados, riesgo: .seguro, seleccionado: true,
                accion: .clonar(Clonacion(original: .init(ruta: o, tamano: eo.tamano, modificado: eo.modificado),
                                          copias: [.init(ruta: a, tamano: e.tamano, modificado: e.modificado)])),
                motivos: [.bien("square.on.square", "Sin borrar nada",
                                "La copia se cambia por un clon del archivo de \(nombreApp) (lo mismo que hace «Duplicar» en el Finder): el contenido es el mismo, byte a byte, y la app solo se lee."),
                          .info("checkmark.seal.fill", "Idéntica",
                                "Tiene el mismo tamaño y el mismo principio y final que el de la app. Antes de cambiarla la comparo entera, y si algo cambió, no la toco.")],
                dueno: "Codex", nivel: .maximo, costes: [.tiempoCPU],
                prevision: PrevisionCompresion([.init(ruta: a, ahorro: ahorro)], ocupan: e.ocupa, requiere: o)))
        }
        return r
    }
}
