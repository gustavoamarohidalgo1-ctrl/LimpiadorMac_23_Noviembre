import Foundation

// Lo que usan las apps y los servicios que están funcionando, sin esperar a que se cierren. De la caché de un servicio de
// macOS que siempre está en marcha (geod, parsecd, tipsd, el agente de los fondos de pantalla…) y de los registros de una
// app abierta, solo los archivos que llevan un día sin cambios y que nadie tiene abiertos, nunca una base de datos; al
// limpiar se vuelven a mirar uno por uno (`Elemento.horasQuieto`). Y lo que se cierra además al cerrar una app con
// «Cerrar y limpiar» (las sesiones de Claude Code que lanzó Claude, por ejemplo).

/// Un archivo que lleva tiempo sin cambios y que nadie tiene abierto.
struct ArchivoQuieto {
    let url: URL
    let bytes: Int64
    /// Su último cambio (de contenido o de estado).
    let fecha: Date
}

/// Lo que usaba la caché de un servicio cuando se ofrecieron sus archivos quietos: algo sin ventana
/// (`Escaner.enMarchaSinVentana`). Al limpiar se vuelve a mirar (`Procesos.conVentana`): si alguna app que casa con sus
/// `claves` tiene ventana, o una app con ventana tiene algo abierto en sus `raices`, el elemento está en uso.
struct UsoSinVentana: Hashable {
    var claves: [String] = []
    var raices: [URL] = []

    init(_ uso: EnUso?, raices: [URL]) {
        if case .app(_, let claves) = uso { self.claves = claves }
        self.raices = raices
    }
}

/// Archivos quietos de una caché o de unos registros: archivos normales tuyos (no carpetas, enlaces ni archivos con varios
/// nombres) que llevan `horas` sin cambios (ni de contenido ni de estado), que ningún programa tiene abiertos y que no son de
/// una base de datos ni un candado. Se buscan al analizar (`listar`) y se vuelven a mirar justo antes de borrar cada uno
/// (`sigueQuieto`).
enum Quietos {
    /// Lo que se encontró: los quietos y cuántos se dejaron por recientes, por estar abiertos o por ser de una base.
    struct Lista {
        var quietos: [ArchivoQuieto] = []
        var recientes = 0
        var abiertos = 0
        var bases = 0
        var bytes: Int64 { quietos.reduce(0) { $0 + $1.bytes } }
        var ultimo: Date? { quietos.map(\.fecha).max() }
    }

    /// Extensiones de bases de datos (SQLite y sus diarios, LevelDB, LMDB, Realm…) y de candados: borrar uno con su programa
    /// en marcha puede corromper la base o dejar que dos procesos la escriban a la vez.
    private static let extensionesDeBase: Set<String> = ["sqlite", "sqlite3", "sqlitedb", "db", "db3", "sdb", "realm", "mdb",
                                                         "ldb", "wal", "shm", "journal", "lock", "lck", "pid"]
    private static let finalesDeBase = ["-wal", "-shm", "-journal", "-lock", "-lck"]
    /// Los archivos sueltos de LevelDB (CURRENT, LOCK, LOG…; MANIFEST-000001 se mira aparte), los candados de Chromium, la
    /// clave con la que WebKit lee el resto de su caché («salt»: sin ella, lo que queda no sirve) y su lista HSTS (qué sitios
    /// solo se abren con https).
    private static let nombresDeBase: Set<String> = ["current", "lock", "log", "log.old", "lockfile", "singletonlock", "salt",
                                                     "hsts.plist"]

    /// ¿Es (o puede ser) parte de una base de datos o un candado? Por su nombre, por tener al lado su diario o su -wal
    /// («Cache.db-wal» junto a «Cache.db»), o porque empieza como una base SQLite. Si no se puede leer, ante la duda, sí.
    static func esDeBase(_ ruta: String) -> Bool {
        let n = Rutas.nombre(ruta).lowercased()
        if extensionesDeBase.contains((n as NSString).pathExtension) || finalesDeBase.contains(where: { n.hasSuffix($0) })
            || nombresDeBase.contains(n) || n.hasPrefix("manifest-") { return true }
        for diario in ["-wal", "-shm", "-journal"] {
            var st = stat()
            if lstat(ruta + diario, &st) == 0 { return true }
        }
        return pareceSQLite(ruta)
    }

    /// Empieza como una base SQLite («SQLite format 3» y un cero), o no se pudo leer.
    private static func pareceSQLite(_ ruta: String) -> Bool {
        let fd = open(ruta, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return true }
        defer { close(fd) }
        var cabecera = [UInt8](repeating: 0, count: 16)
        let leidos = read(fd, &cabecera, 16)
        guard leidos >= 0 else { return true }
        return leidos == 16 && cabecera == Array("SQLite format 3".utf8) + [0]
    }

    /// Una carpeta que es una base de datos entera: LevelDB (CURRENT y algún MANIFEST-…), los datos externos de Core Data
    /// («.<base>_SUPPORT») o los de Realm. No se toca nada de dentro.
    static func esCarpetaDeBase(_ carpeta: String) -> Bool {
        let n = Rutas.nombre(carpeta).lowercased()
        if n.hasSuffix("_support") || n.hasSuffix(".leveldb") || n.hasSuffix(".realm.management") { return true }
        guard access(carpeta + "/CURRENT", F_OK) == 0 else { return false }
        return ((try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? []).contains { $0.hasPrefix("MANIFEST-") }
    }

    /// Lo último que cambió de un archivo: su contenido (mtime) o su estado (ctime, que también cambia al renombrarlo o al
    /// cambiarle los permisos; en las pruebas con LIMPIADOR_SIN_CTIME no se mira, porque no se puede envejecer).
    private static func ultimoCambio(_ st: stat) -> Int {
        max(Int(st.st_mtimespec.tv_sec), Compresor.mirarCtime ? Int(st.st_ctimespec.tv_sec) : 0)
    }

    /// Los archivos quietos de esas rutas (carpetas o archivos), recorridas sin seguir enlaces, sin salir del disco y con tope
    /// (`maximo` entradas: lo que no se mira no se ofrece). Las rutas que son enlaces no se miran. Lo de dentro de una
    /// carpeta que es una base de datos entera (`esCarpetaDeBase`) se salta.
    static func listar(_ rutas: [URL], horas: Double, abiertos: ArchivosAbiertos, maximo: Int = 20_000) -> Lista {
        var r = Lista()
        let limite = Int(Date().timeIntervalSince1970 - horas * 3600)
        var vistos = 0
        for u in rutas {
            var st = stat()
            guard lstat(u.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR || (st.st_mode & S_IFMT) == S_IFREG else { continue }
            // Con su carpeta sin enlaces (/var → /private/var), como da el sistema lo que está abierto; el último nombre no
            // se resuelve (no es un enlace: se acaba de mirar).
            guard let rutaC = strdup(ArchivosAbiertos.formas(u.path).last ?? u.path) else { continue }
            defer { free(rutaC) }
            var argumentos: [UnsafeMutablePointer<CChar>?] = [rutaC, nil]
            guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { continue }
            defer { fts_close(fts) }
            while let e = fts_read(fts), vistos < maximo {
                vistos += 1
                let ruta = String(cString: e.pointee.fts_path)
                switch Int32(e.pointee.fts_info) {
                case FTS_D:
                    if esCarpetaDeBase(ruta) {
                        r.bases += 1
                        fts_set(fts, e, FTS_SKIP)
                    }
                case FTS_F:
                    let st = e.pointee.fts_statp.pointee
                    // Un archivo con varios nombres no libera nada al borrar uno, y el otro puede ser importante.
                    guard st.st_uid == getuid(), st.st_nlink == 1, st.st_blocks > 0 else { continue }
                    let cambio = ultimoCambio(st)
                    if abiertos.hayAbierto(rutaReal: ruta) != nil {
                        r.abiertos += 1
                    } else if cambio > limite {
                        r.recientes += 1
                    } else if esDeBase(ruta) {
                        r.bases += 1
                    } else {
                        r.quietos.append(ArchivoQuieto(url: URL(fileURLWithPath: ruta), bytes: Int64(st.st_blocks) * 512,
                                                       fecha: Date(timeIntervalSince1970: TimeInterval(cambio))))
                    }
                default: break
                }
            }
        }
        return r
    }

    /// Justo antes de borrarlo: sigue siendo un archivo normal tuyo con un solo nombre, en la misma carpeta de verdad (nadie
    /// cambió una carpeta de por medio por un enlace), sin cambios desde el análisis (`hasta`) ni en las últimas `horas`,
    /// que no es de una base de datos y que nadie tiene abierto según `abiertos` (una captura de hace unos segundos:
    /// Limpiador la renueva cada 3 s mientras limpia).
    static func sigueQuieto(_ ruta: String, horas: Double, hasta: Date?, abiertos: ArchivosAbiertos) -> Bool {
        var st = stat()
        guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid(), st.st_nlink == 1 else { return false }
        let carpeta = Rutas.padre(ruta)
        guard Rutas.real(URL(fileURLWithPath: carpeta)) == carpeta else { return false }
        let cambio = ultimoCambio(st)
        guard Double(cambio) <= Date().timeIntervalSince1970 - horas * 3600 else { return false }
        if let hasta, cambio > Int(hasta.timeIntervalSince1970) { return false }
        guard abiertos.hayAbierto(rutaReal: ruta) == nil else { return false }
        return !esDeBase(ruta) && !esCarpetaDeBase(carpeta)
    }

    /// Lo que se dejó y por qué, para el motivo: «Dejo 12 archivos recientes o abiertos y 3 de bases de datos».
    static func dejados(_ l: Lista) -> String {
        var partes: [String] = []
        let usados = l.recientes + l.abiertos
        if usados > 0 { partes.append("\(Formato.numero(usados)) \(usados == 1 ? "archivo reciente o abierto" : "archivos recientes o abiertos")") }
        if l.bases > 0 { partes.append("\(Formato.numero(l.bases)) de bases de datos o candados") }
        return partes.isEmpty ? "" : " Dejo \(Formato.lista(partes))."
    }
}

extension Escaner {
    // MARK: - Servicios de macOS siempre en marcha

    /// Quién lo usa ahora, si es algo que no se cierra desde aquí: un servicio de macOS o un programa sin ventana (lo que
    /// dice su `uso`, o alguno de los que tienen abierto algo de esas rutas) y ninguna app con ventana. Entonces no se espera
    /// a que se cierre (no se puede): solo se ofrecen sus archivos quietos. nil si nada lo usa o si algo de lo que lo usa es
    /// (o va dentro de) una app con ventana: entonces se sigue como siempre y se ofrece «Cerrar y limpiar».
    static func enMarchaSinVentana(_ uso: EnUso?, rutas: [URL], _ c: Contexto) -> String? {
        guard c.procesos.fiable else { return nil }
        var quien: String?
        if let uso, let q = c.procesos.quienUsa(uso) {
            guard case .app(_, let claves) = uso, !c.procesos.algunaConVentana(claves) else { return nil }
            quien = q
        }
        for u in rutas {
            // Todos los que tienen algo abierto ahí, no solo el primero que se vio: una app con ventana y un servicio
            // pueden usar a la vez la misma carpeta.
            let pids = c.procesos.abiertos.procesos(dentroDe: u.path)
            guard !pids.isEmpty else { continue }
            if pids.contains(where: { c.procesos.appConVentana(pid: $0) != nil }) { return nil }
            quien = quien ?? c.procesos.abiertos.hayAbierto(dentroDe: u.path)
        }
        return quien
    }

    /// La caché de un servicio de macOS que está funcionando y no tiene ventana (`enMarchaSinVentana`): sus archivos que
    /// llevan 24 h quietos, que nadie tiene abiertos y que no son de una base de datos. Seguro y marcado; sin `enUso` (no se
    /// espera a nada), con lo último que cambió y vueltos a mirar uno por uno al limpiar. Si al limpiar la usa una app con
    /// ventana (la del servicio, por sus claves de `uso`, o una que tenga algo abierto en sus rutas), no se toca
    /// (`sinVentana`). Si no llega al mínimo, va con las de los demás servicios en marcha (`cachesPequenasEnMarcha`).
    func cacheDeServicioEnMarcha(_ nombre: String, quien: String, uso: EnUso?, rutas: [URL], _ c: Contexto, donde: String,
                                 conTmp: Bool = false) -> Elemento? {
        let lista = Quietos.listar(rutas, horas: 24, abiertos: c.procesos.abiertos)
        guard !lista.quietos.isEmpty else { return nil }
        let sinVentana = UsoSinVentana(uso, raices: rutas)
        guard lista.bytes >= minimo else {
            c.memoria.quietosDeServicios.append((nombre, lista.quietos, sinVentana))
            return nil
        }
        let que = conTmp ? "Archivos de la caché y descargas temporales" : "Archivos de la caché"
        return Elemento(
            nombre: "Caché de \(nombre)",
            detalle: "\(que) que \(nombre) guarda \(donde) y que llevan más de 1 día sin cambios (\(Formato.numero(lista.quietos.count)) archivos).",
            consecuencia: "\(nombre) vuelve a crear o a descargar lo que le haga falta. Lo que está usando (lo abierto o cambiado en el último día) y sus bases de datos se quedan.",
            rutas: lista.quietos.map(\.url), tamanosRutas: lista.quietos.map(\.bytes), ultimoUso: lista.ultimo,
            categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
            motivos: [.bien("arrow.triangle.2.circlepath", "Se regenera", "Es una caché: \(nombre) la reconstruye sola."),
                      Self.motivoEnMarcha(quien, lista)],
            dueno: nombre, cambioAnalizado: lista.ultimo, horasQuieto: 24, sinVentana: [sinVentana])
    }

    /// Las cachés de servicios en marcha que no llegan al mínimo, juntas (ver `cacheDeServicioEnMarcha`).
    func cachesPequenasEnMarcha(_ c: Contexto) -> Elemento? {
        let grupos = c.memoria.quietosDeServicios
        guard !grupos.isEmpty else { return nil }
        let archivos = grupos.flatMap(\.archivos)
        let ultimo = archivos.map(\.fecha).max()
        let nombres = Array(Set(grupos.map(\.nombre))).sorted()
        return Elemento(
            nombre: "Cachés pequeñas de servicios de macOS en marcha",
            detalle: "\(Formato.numero(archivos.count)) archivos de más de 1 día de las cachés de \(Formato.listaCorta(nombres, maximo: 4)), que usan servicios de macOS siempre en marcha.",
            consecuencia: "Cada servicio vuelve a crear lo que le haga falta. Lo que están usando y sus bases de datos se quedan.",
            rutas: archivos.map(\.url), tamanosRutas: archivos.map(\.bytes), ultimoUso: ultimo, categoria: .cachesApps,
            riesgo: .seguro, seleccionado: true,
            motivos: [.bien("arrow.triangle.2.circlepath", "Se regeneran", "Son cachés que cada servicio reconstruye solo."),
                      .info("gearshape.2.fill", "Siempre en marcha",
                            "Son servicios de macOS sin ventana: no hace falta cerrarlos. Solo cuento los archivos que nadie tiene abiertos y llevan más de 1 día sin cambios, nunca sus bases de datos; al limpiar los vuelvo a mirar uno por uno y me salto los que se hayan abierto o cambiado.")],
            dueno: "macOS", cambioAnalizado: ultimo, horasQuieto: 24, sinVentana: grupos.map(\.uso))
    }

    private static func motivoEnMarcha(_ quien: String, _ l: Quietos.Lista) -> Motivo {
        .info("gearshape.2.fill", "Siempre en marcha",
              "Lo usa \(quien), que funciona sin ventana (un servicio o un ayudante de macOS): no hace falta cerrarlo. Solo cuento los archivos que nadie tiene abiertos y llevan más de 1 día sin cambios, nunca sus bases de datos; al limpiar los vuelvo a mirar uno por uno y me salto los que se hayan abierto o cambiado.\(Quietos.dejados(l))")
    }

    // MARK: - Registros de apps abiertas

    /// Los registros de las apps que están abiertas o que algo tiene abiertos (`lugares`: la app, quién los usa, sus carpetas
    /// de registros, si son los de dentro de sus datos y si la app está abierta o solo tiene algún registro abierto por otro
    /// programa): no se espera a que se cierren, pero solo van los archivos de más de 1 día que nadie tiene abiertos (los
    /// recientes los puede estar escribiendo), nunca una base de datos, y al limpiar se vuelven a mirar uno por uno. Los que
    /// no llegan al mínimo, juntos.
    func registrosDeAppsAbiertas(_ lugares: [(app: String, quien: String, carpetas: [URL], internos: Bool, abierta: Bool)],
                                 _ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        var pequenos: [(app: String, abierta: Bool, archivos: [ArchivoQuieto])] = []
        for l in lugares {
            let lista = Quietos.listar(l.carpetas, horas: 24, abiertos: c.procesos.abiertos)
            guard !lista.quietos.isEmpty else { continue }
            guard lista.bytes >= minimo else {
                pequenos.append((l.app, l.abierta, lista.quietos))
                continue
            }
            r.append(Elemento(
                nombre: l.internos ? "Registros internos de \(l.app)" : "Registros de \(l.app)",
                detalle: "\(Formato.numero(lista.quietos.count)) archivos de registro de \(l.app)\(l.internos ? ", guardados junto a sus datos," : "") que llevan más de 1 día sin cambios.",
                consecuencia: "Nada importante: solo se pierden registros y errores antiguos. "
                    + (l.abierta ? "Los que \(l.app) está escribiendo se quedan." : "Los que algún programa tiene abiertos o cambiaron en el último día se quedan."),
                rutas: lista.quietos.map(\.url), tamanosRutas: lista.quietos.map(\.bytes), ultimoUso: lista.ultimo,
                categoria: .registros, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("doc.text.magnifyingglass", "Solo registros", "Sirven para diagnosticar errores; se crean nuevos cuando hace falta."),
                          .info("clock.fill", "\(l.quien) está en marcha",
                                "No hace falta cerrar nada: solo cuento los que llevan más de 1 día sin cambios y que nadie tiene abiertos (los recientes los puede estar escribiendo). Al limpiar los vuelvo a mirar uno por uno.\(Quietos.dejados(lista))")],
                dueno: l.app, cambioAnalizado: lista.ultimo, horasQuieto: 24))
        }
        if !pequenos.isEmpty {
            let archivos = pequenos.flatMap(\.archivos)
            let ultimo = archivos.map(\.fecha).max()
            // Las apps abiertas, y aparte las cerradas que solo tienen algún registro abierto por otro programa.
            let abiertas = Set(pequenos.filter(\.abierta).map(\.app))
            let conAbiertos = Array(Set(pequenos.map(\.app)).subtracting(abiertas)).sorted()
            var de: [String] = []
            if !abiertas.isEmpty {
                de.append("de \(Formato.listaCorta(abiertas.sorted(), maximo: 4)), que \(abiertas.count == 1 ? "está abierta" : "están abiertas")")
            }
            if !conAbiertos.isEmpty {
                de.append("de \(Formato.listaCorta(conAbiertos, maximo: 4)), que \(conAbiertos.count == 1 ? "tiene" : "tienen") algún registro abierto por otro programa")
            }
            r.append(Elemento(
                nombre: conAbiertos.isEmpty ? "Registros antiguos de apps abiertas" : "Registros antiguos de apps en uso",
                detalle: "\(Formato.numero(archivos.count)) archivos de registro de más de 1 día \(de.joined(separator: ", y ")).",
                consecuencia: "Nada importante: solo se pierden registros y errores antiguos.",
                rutas: archivos.map(\.url), tamanosRutas: archivos.map(\.bytes), ultimoUso: ultimo, categoria: .registros,
                riesgo: .seguro, seleccionado: true,
                motivos: [.bien("doc.text.magnifyingglass", "Solo registros",
                                "Solo archivos de registro de más de 1 día que ningún programa tiene abiertos; al limpiar los vuelvo a mirar uno por uno.")],
                dueno: conAbiertos.isEmpty ? "Apps abiertas" : "Apps en uso", cambioAnalizado: ultimo, horasQuieto: 24))
        }
        return r
    }
}

extension CierreDeApps {
    /// Lo que también se termina al cerrar esa app: lo que lanzó y sigue en marcha fuera de su .app. Claude, por ejemplo,
    /// lanza sus sesiones de Claude Code (claude.app, que guarda en su carpeta de datos), y al cerrarse las termina con
    /// todo lo que estuvieran haciendo. nil si no lanzó nada así.
    static func avisoAlCerrar(_ bundleID: String, nombre: String, _ p: Procesos) -> String? {
        let suyas = p.apps.filter { $0.bundleID == bundleID }
        let raices = Set(suyas.map(\.pid)).subtracting([0])
        let paquetes = suyas.compactMap { $0.url?.path }
        guard !raices.isEmpty else { return nil }
        /// ¿Lo lanzó la app (directamente o algo que ella lanzó)?
        func lanzadoPorElla(_ pid: pid_t) -> Bool {
            var actual = pid
            for _ in 0..<64 {
                guard let padre = p.padres[actual], padre > 1 else { return false }
                if raices.contains(padre) { return true }
                actual = padre
            }
            return false
        }
        let propio = getpid()
        let fuera = p.programas.filter { prog in
            prog.pid != propio && !raices.contains(prog.pid) && !paquetes.contains { prog.ruta.hasPrefix($0 + "/") }
                && !prog.ruta.hasPrefix("/System/") && !prog.ruta.hasPrefix("/usr/libexec/") && lanzadoPorElla(prog.pid)
        }
        guard !fuera.isEmpty else { return nil }
        // Las sesiones de Claude Code: cada claude.app que no lanzó otro (lo que lanza una sesión va dentro de ella).
        let codigo = Set(fuera.filter { $0.ids.contains("com.anthropic.claude-code") }.map(\.pid))
        let sesiones = codigo.filter { p.padres[$0].map { !codigo.contains($0) } ?? true }.count
        if sesiones > 0 {
            return "Cerrar \(nombre) también termina \(sesiones == 1 ? "la sesión de Claude Code que lanzó" : "las \(sesiones) sesiones de Claude Code que lanzó") y lo que \(sesiones == 1 ? "esté" : "estén") haciendo. Si \(sesiones == 1 ? "está" : "alguna está") trabajando, espera a que termine."
        }
        let nombres = Array(Set(fuera.map(\.visible))).sorted()
        return "Cerrar \(nombre) puede terminar también lo que lanzó y sigue en marcha: \(Formato.listaCorta(nombres, maximo: 3)). Si alguno está trabajando, espera a que termine."
    }
}
