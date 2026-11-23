import Foundation

/// Desarrollo, herramientas, restos pequeños y orden en tu carpeta: lo que las demás reglas no ven porque está fuera de su
/// sitio (los taps de Homebrew, ~/.config, ~/Library/Java…) o porque, suelto, no llega a 1 MB.
extension Escaner {

    // MARK: - Utilidades de estas reglas

    /// Lo que ocupa una ruta, contado como el índice: lo que sumó él si la registró y, si no (archivos sueltos y carpetas
    /// de menos de 1 MB, que no registra), midiéndola aquí. Solo para carpetas pequeñas o acotadas.
    static func medida(_ ruta: String, _ c: Contexto) -> Int64 {
        if let i = c.indice.info(ruta) { return i.bytes }
        var st = stat()
        guard lstat(ruta, &st) == 0 else { return 0 }
        if (st.st_mode & S_IFMT) == S_IFDIR { return Tamanos.recorriendo(ruta) }
        return Int64(st.st_blocks) * 512
    }

    /// Lo último que cambió dentro de una ruta: lo que anotó el índice o, si no la registró por pequeña, recorriéndola.
    static func ultimoCambioDentro(_ ruta: String, _ c: Contexto) -> Date? {
        if let i = c.indice.info(ruta), i.masReciente > 0 { return Date(timeIntervalSince1970: TimeInterval(i.masReciente)) }
        let t = Fechas.ultimoCambio([ruta])
        return t > 0 ? Date(timeIntervalSince1970: TimeInterval(t)) : nil
    }

    private static func dias(desde fecha: Date?) -> Double? { fecha.map { Date().timeIntervalSince($0) / 86400 } }

    private static func nombres(en carpeta: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? []).sorted()
    }

    /// Qué es lo que hay en esa ruta (S_IFDIR, S_IFREG, S_IFLNK…), sin seguir enlaces. nil si no existe.
    private static func tipo(_ ruta: String) -> mode_t? {
        var st = stat()
        return lstat(ruta, &st) == 0 ? (st.st_mode & S_IFMT) : nil
    }

    /// La fecha de modificación (segundos desde 1970), sin seguir enlaces. 0 si no existe.
    private static func segundosDeCambio(_ ruta: String) -> Int {
        var st = stat()
        return lstat(ruta, &st) == 0 ? Int(st.st_mtimespec.tv_sec) : 0
    }

    /// Un archivo pequeño de configuración o de metadatos (256 KB o menos), como texto.
    private static func leerPequeno(_ ruta: String, maximo: Int64 = 262_144) -> String? {
        var st = stat()
        guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, Int64(st.st_size) <= maximo else { return nil }
        return try? String(contentsOfFile: ruta, encoding: .utf8)
    }

    /// El repositorio de git que contiene esa ruta, si el índice conoce alguno por encima (dentro de tu carpeta).
    private static func repoQueLaContiene(_ ruta: String, _ c: Contexto) -> String? {
        var actual = Rutas.padre(ruta)
        let home = Rutas.home.path
        while actual.count > home.count {
            if c.indice.repos.contains(actual) { return actual }
            actual = Rutas.padre(actual)
        }
        return nil
    }

    /// El programa que abre la terminal al escribir ese comando: el primero del PATH que se puede ejecutar.
    private static func primeroEnElPath(_ comando: String, _ c: Contexto) -> String? {
        for d in c.apps.pathTerminal {
            let ruta = d + "/" + comando
            if access(ruta, X_OK) == 0 && tipo(Rutas.real(URL(fileURLWithPath: ruta))) == S_IFREG { return ruta }
        }
        return nil
    }

    // MARK: - Ganchos por categoría

    /// Lo que se añade a «Cachés de desarrollo».
    func desarrolloAmpliado(_ c: Contexto) -> [Elemento] {
        restosDeGit(c) + contenedoresDeApple(c) + cachesSueltasDeDesarrollo(c) + paquetesDePipDeUsuario(c) + javasDelIDE(c)
            + paquetesGlobalesDeNpm(c) + basesDeDatosParadas(c) + preferenciasDePruebas(c) + enlacesRotosDeComandos(c)
    }

    // MARK: - Contenedores de Apple (CLI `container`)

    /// Imágenes, capas y snapshots que guarda el CLI `container` de Apple en ~/Library/Application Support/com.apple.container.
    /// Como empieza por «com.apple.», las reglas genéricas de restos y cachés lo ignoran; una sola imagen (como Playwright)
    /// puede ocupar 7+ GB aunque el servicio esté apagado. Revisar: las imágenes se vuelven a descargar si las necesitas.
    private func contenedoresDeApple(_ c: Contexto) -> [Elemento] {
        let base = Rutas.enHome("Library/Application Support/com.apple.container")
        guard Self.tipo(base.path) == S_IFDIR else { return [] }
        let snapshots = base.appendingPathComponent("snapshots")
        let content = base.appendingPathComponent("content")
        let rutas = [snapshots, content].filter { Self.tipo($0.path) == S_IFDIR && !Self.nombres(en: $0.path).isEmpty }
        guard !rutas.isEmpty else { return [] }
        let tamanos = rutas.map { Self.medida($0.path, c) }
        guard tamanos.reduce(0, +) >= minimo else { return [] }

        // Leer los nombres de las imágenes en state.json (JSON objeto { "imagen:tag": { ... } }).
        var imagenes: [String] = []
        if let texto = Self.leerPequeno(base.appendingPathComponent("state.json").path),
           let datos = texto.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: datos) as? [String: Any] {
            imagenes = dict.keys.sorted()
        }
        let contenedoresActivos = Self.nombres(en: base.appendingPathComponent("containers").path).filter { !$0.hasPrefix(".") }
        var rutasFinales = rutas
        var tamanosFinales = tamanos
        let stateFile = base.appendingPathComponent("state.json")
        if contenedoresActivos.isEmpty, Self.tipo(stateFile.path) == S_IFREG {
            rutasFinales.append(stateFile)
            tamanosFinales.append(Self.medida(stateFile.path, c))
        }
        let uso = EnUso.programas(nombre: "Apple container",
                                  ejecutables: ["container", "container-apiserver", "container-core-images", "vminit"])
        let cambio = rutas.compactMap { Self.ultimoCambioDentro($0.path, c) }.max()
        var motivos: [Motivo] = [.info("shippingbox.fill", "Imágenes de contenedores",
                                       imagenes.isEmpty
                                           ? "Imágenes y capas OCI guardadas por el CLI «container» de Apple."
                                           : "Guarda \(imagenes.count == 1 ? "la imagen" : "las imágenes") \(Formato.listaCorta(imagenes, maximo: 3)).")]
        if !contenedoresActivos.isEmpty {
            motivos.append(.aviso("exclamationmark.triangle.fill", "Hay contenedores creados",
                                  "Tienes \(contenedoresActivos.count) \(contenedoresActivos.count == 1 ? "contenedor" : "contenedores") en containers/. Revisa antes de borrar sus capas."))
        }
        let sinContenedores = contenedoresActivos.isEmpty
        return [Elemento(
            nombre: "Imágenes de Apple container",
            detalle: "Capas y snapshots descargados por el CLI «container» de Apple en ~/Library/Application Support/com.apple.container"
                + (imagenes.isEmpty ? "." : " (\(Formato.listaCorta(imagenes, maximo: 3)))."),
            consecuencia: "Se borran las imágenes y snapshots locales. Si vuelves a usar «container», las descarga otra vez (necesita internet).",
            rutas: rutasFinales, tamanosRutas: tamanosFinales, ultimoUso: cambio,
            categoria: .desarrollo, riesgo: sinContenedores ? .seguro : .cuidado, seleccionado: sinContenedores,
            motivos: motivos, enUso: uso, dueno: "Apple container",
            nivel: sinContenedores ? .maximo : .nunca,
            costes: [.descarga(bytes: tamanosFinales.reduce(0, +))])]
    }

    // MARK: - Enlaces simbólicos rotos en ~/.local/bin y ~/bin

    /// Enlaces simbólicos en ~/.local/bin y ~/bin cuyo destino ya no existe (apps desinstaladas como Postgres.app o CLI viejos).
    /// Excluye destinos en discos externos (/Volumes/).
    private func enlacesRotosDeComandos(_ c: Contexto) -> [Elemento] {
        let carpetas = [Rutas.enHome(".local/bin"), Rutas.enHome("bin")]
        var rotos: [(url: URL, destino: String)] = []
        for carpeta in carpetas where Self.tipo(carpeta.path) == S_IFDIR {
            for n in Self.nombres(en: carpeta.path) where !n.hasPrefix(".") {
                let u = carpeta.appendingPathComponent(n)
                guard Self.tipo(u.path) == S_IFLNK,
                      let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: u.path) else { continue }
                let resuelto = dest.hasPrefix("/") ? dest : carpeta.appendingPathComponent(dest).standardizedFileURL.path
                if resuelto.hasPrefix("/Volumes/") { continue }
                var st = stat()
                if stat(u.path, &st) != 0 {
                    rotos.append((u, dest))
                }
            }
        }
        guard !rotos.isEmpty else { return [] }
        let nombres = rotos.map { $0.url.lastPathComponent }
        return [Elemento(
            nombre: "Enlaces rotos en tu terminal (\(rotos.count))",
            detalle: "Comandos en ~/.local/bin o ~/bin que apuntan a programas que ya no existen: \(Formato.listaCorta(nombres, maximo: 6)).",
            consecuencia: "Solo se borran los enlaces simbólicos rotos (ya no funcionan). No ocupa espacio apreciable, pero limpia tu PATH.",
            rutas: rotos.map(\.url), tamanosRutas: Array(repeating: 0, count: rotos.count),
            categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
            motivos: [.bien("link.badge.plus", "Destino inexistente",
                            "Ninguno de los programas a los que apuntan sigue en este Mac (se ignoran los de discos externos).")],
            nivel: .maximo, siempreVisible: true)]
    }

    /// Lo que se añade a «Carpetas ocultas».
    func herramientasAmpliado(_ c: Contexto) -> [Elemento] {
        conversacionesDeProyectosBorrados(c) + restosDeHerramientasDesinstaladas(c)
    }

    /// Lo que se añade a «Archivos olvidados»: nada de lo que ya ofrece otra categoría (`ofrecidas`) ni de lo que ofrece
    /// la propia categoría (`propios`), si llega al mínimo para enseñarse (lo que no llega se descarta y no tapa nada).
    func ordenEnCasa(_ c: Contexto, ofrecidas: [String], propios: [Elemento]) -> [Elemento] {
        let tomadas = Set(ofrecidas + propios.filter { Self.llegaAlMinimo($0, minimo, c) }.flatMap { $0.rutas.map(\.path) })
        let cubierta: (String) -> Bool = { tomadas.contains($0) || Totales.dentroDe($0, tomadas) }
        return [restosSueltos(c, cubierta: cubierta), copiasHechasAMano(c, cubierta: cubierta),
                bibliotecasAnteriores(c, cubierta: cubierta)].compactMap { $0 }
    }

    /// `base` y, detrás, los de `anadidos` que no van enteros dentro de lo que ofrece ya un elemento de `base` que se
    /// enseñará (la misma carpeta dos veces en una categoría: un paquete de npm dentro de un Node viejo, por ejemplo).
    func conAnadidas(_ base: [Elemento], _ anadidos: [Elemento], _ c: Contexto) -> [Elemento] {
        let tomadas = Set(base.filter { $0.accion == .borrar && Self.llegaAlMinimo($0, minimo, c) }.flatMap { $0.rutas.map(\.path) })
        guard !tomadas.isEmpty else { return base + anadidos }
        return base + anadidos.filter { el in
            el.rutas.isEmpty || !el.rutas.allSatisfy { tomadas.contains($0.path) || Totales.dentroDe($0.path, tomadas) }
        }
    }

    /// Si un elemento se enseñará (lo que mide `medir` llega a `minimo`, o se enseña siempre).
    static func llegaAlMinimo(_ el: Elemento, _ minimo: Int64, _ c: Contexto) -> Bool {
        if el.siempreVisible { return true }
        if let fijo = el.tamanoFijo { return fijo >= minimo }
        let tamanos = el.tamanosRutas.count == el.rutas.count ? el.tamanosRutas : el.rutas.map { c.indice.bytes(de: $0) }
        return tamanos.reduce(0, +) >= minimo
    }

    /// Wrangler funcionando: su programa (node_modules/wrangler/bin/wrangler.js, que lanza wrangler-dist/cli.js) en los
    /// argumentos de algún proceso.
    private static func wranglerEnMarcha(_ c: Contexto) -> Bool {
        c.procesos.lineas.contains { $0.contains("wrangler-dist/") || $0.contains("/wrangler/bin/wrangler") || $0.contains("/bin/wrangler ") }
    }

    // MARK: - Emulador de Android sin dispositivos

    /// Las carpetas donde Android guarda los emuladores: ~/.android/avd y las que digan ANDROID_AVD_HOME, ANDROID_USER_HOME
    /// y ANDROID_EMULATOR_HOME.
    private static func carpetasDeEmuladores() -> [String] {
        let entorno = ProcessInfo.processInfo.environment
        var r = [Rutas.enHome(".android/avd").path]
        if let d = entorno["ANDROID_AVD_HOME"] { r.append(d) }
        for v in ["ANDROID_USER_HOME", "ANDROID_EMULATOR_HOME"] {
            if let d = entorno[v] { r.append(d + "/avd") }
        }
        return r
    }

    /// El paquete del emulador (sdk/emulator) y los marcos de dispositivo (sdk/skins) cuando no hay ningún emulador creado
    /// ni ninguna imagen del sistema con algo dentro: así no puede arrancar nada. Revisar: cuesta volver a descargarlo.
    func emuladorSinDispositivos(_ c: Contexto) -> [Elemento] {
        let sdk = sdkAndroid(c)
        let emulador = sdk.appendingPathComponent("emulator")
        // Un emulador en cualquier carpeta (también los de prueba que crean los scripts) necesita el programa.
        guard Self.tipo(emulador.path) == S_IFDIR, c.indice.avds.isEmpty else { return [] }
        if Self.carpetasDeEmuladores().contains(where: { carpeta in
            Self.nombres(en: carpeta).contains { $0.hasSuffix(".avd") || $0.hasSuffix(".ini") }
        }) { return [] }
        // Con una imagen del sistema que tenga algo dentro (system-images/<versión>/<tipo>/<abi>) se puede crear uno.
        let imagenes = sdk.appendingPathComponent("system-images").path
        for version in Self.nombres(en: imagenes) where Self.tipo(imagenes + "/" + version) == S_IFDIR {
            for variante in Self.nombres(en: imagenes + "/" + version) where Self.tipo(imagenes + "/\(version)/\(variante)") == S_IFDIR {
                for abi in Self.nombres(en: imagenes + "/\(version)/\(variante)") {
                    let ruta = imagenes + "/\(version)/\(variante)/\(abi)"
                    if Self.tipo(ruta) == S_IFDIR && Self.nombres(en: ruta).contains(where: { $0 != ".DS_Store" }) { return [] }
                }
            }
        }
        // Lo que solo usa el emulador: los marcos de dispositivo (skins), las fotos de fondo de sus escenas virtuales
        // (environments) y sus notas en ~/.android.
        let suyas = ["skins", "environments"].map { sdk.appendingPathComponent($0) }.filter { Self.tipo($0.path) == S_IFDIR }
            + ["emu-last-feature-flags.protobuf", "emu-update-last-check.ini"].map { Rutas.enHome(".android/" + $0) }
                .filter { Self.tipo($0.path) == S_IFREG }
        let skins = sdk.appendingPathComponent("skins")
        let rutas = [emulador] + suyas
        let tamanos = rutas.map { Self.medida($0.path, c) }
        let total = tamanos.reduce(0, +)
        // La versión sale de su source.properties («Pkg.Revision=37.1.11»).
        let version = (Self.leerPequeno(emulador.path + "/source.properties") ?? "").split(separator: "\n")
            .first { $0.hasPrefix("Pkg.Revision=") }.map { " " + $0.dropFirst(13).trimmingCharacters(in: .whitespaces) } ?? ""
        return [Elemento(
            nombre: "Emulador de Android sin dispositivos",
            detalle: "El programa del emulador\(version)\(suyas.contains(skins) ? " y los marcos de dispositivo (skins)" : ""). No tienes ningún emulador creado ni ninguna imagen del sistema descargada: ahora mismo no puede arrancar nada.",
            consecuencia: "Android Studio lo vuelve a descargar cuando crees un dispositivo en Device Manager (unos \(Formato.bytes(total)); necesita internet). El resto del SDK y tus proyectos no se tocan.",
            rutas: rutas, tamanosRutas: tamanos, categoria: .emuladores, riesgo: .revisar,
            motivos: [.info("iphone.gen3", "Sin dispositivos",
                            "No encontré ningún emulador (.avd) en ~/.android/avd ni en las carpetas que miré, y las imágenes del sistema (system-images) están vacías. Si guardas emuladores en un disco externo, revísalo.")],
            enUso: .rutas(nombre: "El emulador de Android", raiz: emulador.path), dueno: "Android Studio",
            costes: [.descarga(bytes: total)])]
    }

    // MARK: - Restos de git

    private static let prefijosDeGitAMedias = ["tmp_pack_", "tmp_idx_", "tmp_rev_"]
    private static let programasDeGit: Set<String> = ["git", "git-remote-https", "git-remote-http", "git-index-pack",
                                                      "git-upload-pack", "git-receive-pack", "git-lfs"]

    /// Los archivos a medio escribir de un objects/pack (tmp_pack_…, tmp_idx_…, tmp_rev_…) con más de 1 h sin cambios: los
    /// deja un fetch, un clone o un gc que se cortó, y git no los vuelve a usar ni los borra.
    private static func gitAMedias(en pack: String) -> [(ruta: String, bytes: Int64, fecha: Int)] {
        let limite = Int(Date().timeIntervalSince1970) - 3600
        return nombres(en: pack).compactMap { n in
            guard prefijosDeGitAMedias.contains(where: { n.hasPrefix($0) }) else { return nil }
            let ruta = pack + "/" + n
            var st = stat()
            guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, Int(st.st_mtimespec.tv_sec) < limite else { return nil }
            return (ruta: ruta, bytes: Int64(st.st_blocks) * 512, fecha: Int(st.st_mtimespec.tv_sec))
        }
    }

    /// ¿En ese .git solo hay restos de una descarga cortada (objects/pack/tmp_*, y la marca «pack-….keep» que git pone
    /// mientras la recibe) y carpetas vacías? Como mucho 5.000 entradas; un enlace o cualquier otro archivo (un .pack, un
    /// objeto, una ref, un .DS_Store) dice que no.
    private static func soloRestosDeDescarga(_ git: String) -> Bool {
        guard let e = FileManager.default.enumerator(atPath: git) else { return false }
        var vistos = 0
        var aMedias = 0
        while let rel = e.nextObject() as? String {
            vistos += 1
            if vistos > 5_000 { return false }
            let t = tipo(git + "/" + rel)
            if t == S_IFDIR { continue }
            let n = Rutas.nombre(rel)
            let enPack = rel.hasPrefix("objects/pack/") && !rel.dropFirst(13).contains("/")
            guard t == S_IFREG, enPack else { return false }
            if prefijosDeGitAMedias.contains(where: { n.hasPrefix($0) }) {
                aMedias += 1
            } else if !(n.hasPrefix("pack-") && n.hasSuffix(".keep")) {
                return false
            }
        }
        return aMedias > 0
    }

    /// Los restos de git a medias de tus repositorios (los que conoce el índice) y de los taps de Homebrew, y los taps
    /// que son un clon roto (sin HEAD ni config).
    func restosDeGit(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let usoGit = EnUso.programas(nombre: "git", ejecutables: Self.programasDeGit)
        var archivos: [(ruta: String, bytes: Int64, fecha: Int)] = []
        var proyectos: [String] = []
        for repo in c.indice.repos.sorted() where Self.tipo(repo + "/.git") == S_IFDIR {
            let suyos = Self.gitAMedias(en: repo + "/.git/objects/pack")
            guard !suyos.isEmpty else { continue }
            archivos += suyos
            proyectos.append(Rutas.nombre(repo))
        }
        if !archivos.isEmpty {
            r.append(Elemento(
                nombre: "Restos de git a medias",
                detalle: "Archivos que git escribe mientras descarga o empaqueta el historial (tmp_pack_…, tmp_idx_…, tmp_rev_…) en \(proyectos.count == 1 ? "el proyecto" : "\(proyectos.count) proyectos:") \(Formato.listaCorta(proyectos)). Si un fetch, un clone o un gc se corta, se quedan ahí para siempre.",
                consecuencia: "Nada: no son parte del historial y git no los vuelve a usar. Tus commits, ramas y cambios no se tocan.",
                rutas: archivos.map { URL(fileURLWithPath: $0.ruta) }, tamanosRutas: archivos.map(\.bytes),
                ultimoUso: archivos.map(\.fecha).max().map { Date(timeIntervalSince1970: TimeInterval($0)) },
                categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("arrow.triangle.2.circlepath", "Restos de git",
                                "Llevan más de 1 h sin cambios: el git que los escribía ya terminó o se cortó. Si hay un git en marcha al limpiar, me los salto.")],
                enUso: usoGit, dueno: "git"))
        }

        // Los taps de Homebrew son clones de git que brew mantiene: los restos se quitan con git y los taps rotos con brew
        // (no están en tu carpeta, así que no se borran a mano).
        let limite = Int(Date().timeIntervalSince1970) - 3600
        for prefijo in Rutas.homebrew {
            let brew = prefijo + "/bin/brew"
            let repositorio = Rutas.existe(prefijo + "/Library/Homebrew/brew.rb") ? prefijo : prefijo + "/Homebrew"
            let taps = repositorio + "/Library/Taps"
            for usuario in Self.nombres(en: taps) where !usuario.hasPrefix(".") && Self.tipo(taps + "/" + usuario) == S_IFDIR {
                for carpeta in Self.nombres(en: taps + "/" + usuario) where carpeta.hasPrefix("homebrew-") {
                    let tap = taps + "/" + usuario + "/" + carpeta
                    let git = tap + "/.git"
                    var st = stat()
                    guard lstat(tap, &st) == 0, st.st_uid == getuid(), Self.tipo(git) == S_IFDIR else { continue }
                    let nombreTap = usuario + "/" + carpeta.dropFirst(9)
                    // Roto: sin HEAD ni config, y en .git solo los restos de una descarga cortada. Un tap tuyo que perdió esos
                    // dos archivos puede tener todavía commits que no subiste.
                    let roto = !Rutas.existe(git + "/HEAD") && !Rutas.existe(git + "/config") && Self.soloRestosDeDescarga(git)
                    if !Rutas.existe(git + "/HEAD") && !Rutas.existe(git + "/config") && !roto { continue }
                    if roto {
                        // Solo el .git, sin ninguna fórmula descargada, y nada cambió en la última hora: no es un «brew tap»
                        // que esté descargando ahora.
                        let fuera = Self.nombres(en: tap).filter { $0 != ".git" && $0 != ".DS_Store" }
                        guard fuera.isEmpty, Fechas.ultimoCambio([tap], despuesDe: limite) <= limite,
                              FileManager.default.isExecutableFile(atPath: brew) else { continue }
                        let core = nombreTap == "homebrew/core" || nombreTap == "homebrew/cask"
                        r.append(Elemento(
                            nombre: "Tap de Homebrew roto: \(nombreTap)",
                            detalle: "Un clon de git de \(nombreTap) que se cortó a medias: en .git no hay HEAD ni config, ni ningún commit, solo los restos de la descarga (tmp_pack_…, tmp_idx_…).",
                            consecuencia: "Lo quita Homebrew con su comando «brew untap \(nombreTap)»: es lo mismo que borrar la carpeta. Roto no sirve para nada\(core ? ", y Homebrew ya saca sus fórmulas de su API" : ""). Si algún día lo necesitas, «brew tap \(nombreTap)» lo vuelve a descargar. No pasa por la Papelera.",
                            rutas: [URL(fileURLWithPath: tap)], tamanoFijo: Tamanos.recorriendo(tap),
                            ultimoUso: Date(timeIntervalSince1970: TimeInterval(Fechas.ultimoCambio([tap]))),
                            categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                            accion: .comando(programa: brew, argumentos: ["untap", nombreTap], entorno: Self.entornoDeBrew, limite: 120),
                            motivos: [.bien("wrench.and.screwdriver.fill", "Clon roto",
                                            "En su .git no hay HEAD ni config: git no lo reconoce como repositorio y Homebrew no puede usarlo."),
                                      .bien("shippingbox.fill", "Comando oficial",
                                            "Lo hace Homebrew con «brew untap», sin actualizarse (HOMEBREW_NO_AUTO_UPDATE).")],
                            enUso: .proceso(nombre: "Homebrew", patron: "/library/homebrew/brew."), dueno: "Homebrew"))
                    } else {
                        let suyos = Self.gitAMedias(en: git + "/objects/pack")
                        guard !suyos.isEmpty else { continue }
                        r.append(Elemento(
                            nombre: "Restos de git a medias en el tap \(nombreTap)",
                            detalle: "Archivos que dejó un «brew update» (un git fetch) que se cortó, en el tap \(nombreTap) de Homebrew.",
                            consecuencia: "Se borran solo esos archivos a medias (tmp_pack_…, tmp_idx_…, tmp_rev_… de más de 1 h) de su carpeta objects/pack. El historial y las fórmulas del tap no se tocan. No pasa por la Papelera.",
                            rutas: suyos.map { URL(fileURLWithPath: $0.ruta) }, tamanoFijo: suyos.reduce(Int64(0)) { $0 + $1.bytes },
                            ultimoUso: suyos.map(\.fecha).max().map { Date(timeIntervalSince1970: TimeInterval($0)) },
                            categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                            accion: .comando(programa: "/usr/bin/find",
                                             argumentos: [git + "/objects/pack", "-maxdepth", "1", "-type", "f", "(", "-name", "tmp_pack_*",
                                                          "-o", "-name", "tmp_idx_*", "-o", "-name", "tmp_rev_*", ")", "-mmin", "+60", "-delete"],
                                             entorno: [:], limite: 120),
                            motivos: [.bien("arrow.triangle.2.circlepath", "Restos de git",
                                            "Llevan más de 1 h sin cambios: el git que los escribía ya terminó o se cortó.")],
                            enUso: usoGit, dueno: "Homebrew"))
                    }
                }
            }
        }
        return r
    }

    // MARK: - Cachés sueltas de desarrollo

    private struct ParteSuelta {
        let url: URL
        let que: String
        var uso: EnUso? = nil
    }

    /// Cachés y restos de herramientas de desarrollo que se regeneran solos y que, sueltos, no llegan a 1 MB (o que nadie
    /// más ofrece): juntos en un elemento Seguro. Lo de una herramienta que está funcionando se queda fuera esta vez.
    func cachesSueltasDeDesarrollo(_ c: Contexto) -> [Elemento] {
        let ahora = Int(Date().timeIntervalSince1970)
        let home = Rutas.home.path
        let xcode = EnUso.programas(nombre: "Xcode", ejecutables: ["Xcode", "xcodebuild", "xctest", "swift-build", "swift-package",
                                                                  "swift-test", "swift-frontend", "sourcekit-lsp"])
        var partes: [ParteSuelta] = []
        // 1. Las de «Cachés de desarrollo» que no llegan a 1 MB: solas no se enseñan. Las de nivel máximo (cuesta volver a
        //    descargarlas: NuGet, Go, Cargo…) no van aquí, que es del modo normal.
        for d in Self.cachesDeDesarrollo where d.riesgo == .seguro && d.preseleccion && d.nivel == .normal && d.categoria == .desarrollo {
            let u = Rutas.enHome(d.rel)
            guard Rutas.existe(u), c.indice.bytes(de: u) < minimo else { continue }
            partes.append(ParteSuelta(url: u, que: d.nombre.lowercased(), uso: d.uso))
        }
        // 2. Los binarios que bajan los paquetes nativos de npm al instalarse (sharp y libvips, better-sqlite3…).
        for (rel, que) in [(".npm/_libvips", "binarios de libvips (sharp)"), (".npm/_prebuilds", "binarios precompilados de npm")] {
            let u = Rutas.enHome(rel)
            if Self.tipo(u.path) == S_IFDIR { partes.append(ParteSuelta(url: u, que: que)) }
        }
        // 3. Gradle: los informes de Kotlin de hace más de 7 días, las versiones viejas de native y la compilación sin
        //    proyecto (undefined-build). Gradle los vuelve a crear o a sacar de su distribución.
        let perfiles = Rutas.enHome(".gradle/kotlin-profile").path
        let todos = Self.nombres(en: perfiles).filter { $0 != ".DS_Store" }
        // Con cualquier extensión: Kotlin escribe .profile, .kotlin-profile y .finish-profile.
        let viejos = todos.filter { Self.tipo(perfiles + "/" + $0) == S_IFREG && Self.segundosDeCambio(perfiles + "/" + $0) < ahora - 7 * 86400 }
        if !viejos.isEmpty && viejos.count == todos.count {
            partes.append(ParteSuelta(url: URL(fileURLWithPath: perfiles), que: "informes de compilación de Kotlin", uso: .gradle))
        } else {
            partes += viejos.map { ParteSuelta(url: URL(fileURLWithPath: perfiles + "/" + $0), que: "informes de compilación de Kotlin", uso: .gradle) }
        }
        let native = Rutas.enHome(".gradle/native").path
        let versiones = Self.nombres(en: native).filter { Self.pareceVersionSuelta($0) && Self.tipo(native + "/" + $0) == S_IFDIR }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        partes += versiones.dropLast().map {
            ParteSuelta(url: URL(fileURLWithPath: native + "/" + $0), que: "native de Gradle \($0) (hay una más nueva)", uso: .gradle)
        }
        let sinProyecto = Rutas.enHome(".gradle/undefined-build")
        if Self.tipo(sinProyecto.path) == S_IFDIR { partes.append(ParteSuelta(url: sinProyecto, que: "compilación de Gradle sin proyecto", uso: .gradle)) }
        // 4. Lo que ~/.cache, ~/.thumbnails y ~/.matplotlib no enseñan por pequeño (con 1 MB o más ya los ofrecen «Caché de
        //    gh», «Caché de thumbnails» o la carpeta oculta entera).
        let gh = Rutas.enHome(".cache/gh")
        if c.indice.bytes(de: gh) < minimo {
            partes += Self.nombres(en: gh.path).filter { $0.hasPrefix("run-log-") && $0.hasSuffix(".zip") }.map {
                ParteSuelta(url: gh.appendingPathComponent($0), que: "registros de GitHub Actions (gh)",
                            uso: .programas(nombre: "gh", ejecutables: ["gh"]))
            }
        }
        for rel in [".thumbnails", ".cache/thumbnails"] {
            let u = Rutas.enHome(rel)
            if Self.tipo(u.path) == S_IFDIR && c.indice.bytes(de: u) < minimo { partes.append(ParteSuelta(url: u, que: "miniaturas (\(rel))")) }
        }
        let matplotlib = Rutas.enHome(".matplotlib")
        if c.indice.bytes(de: matplotlib) < minimo {
            partes += Self.nombres(en: matplotlib.path).filter { $0.hasPrefix("fontlist-") && $0.hasSuffix(".json") }.map {
                ParteSuelta(url: matplotlib.appendingPathComponent($0), que: "lista de fuentes de matplotlib")
            }
        }
        // 5. Archivos de caché sueltos en tu carpeta: el de PDFBox y el volcado del autocompletado de zsh (compinit lo
        //    vuelve a crear al abrir la terminal).
        for n in Self.nombres(en: home) where n == ".pdfbox.cache" || n.hasPrefix(".zcompdump") {
            let ruta = home + "/" + n
            guard Self.tipo(ruta) == S_IFREG, Self.segundosDeCambio(ruta) < ahora - 3600 else { continue }
            partes.append(ParteSuelta(url: URL(fileURLWithPath: ruta), que: n == ".pdfbox.cache" ? "caché de fuentes de PDFBox" : "autocompletado de zsh"))
        }
        // 6. ~/Library/Caches: las de las herramientas de Xcode (com.apple.*, que no ofrece nadie más) y las de Deno y Kotlin
        //    que no llegan a 1 MB (con más, ya salen en «Cachés de aplicaciones»; si no están instaladas, en «Restos»).
        let caches = Rutas.enHome("Library/Caches")
        for (n, que) in [("com.apple.dt.xctest.tool", "caché de XCTest"), ("com.apple.dt.xcodebuild", "caché de xcodebuild")] {
            let u = caches.appendingPathComponent(n)
            if Self.tipo(u.path) == S_IFDIR { partes.append(ParteSuelta(url: u, que: que, uso: xcode)) }
        }
        let deTerminal: [(String, String, EnUso?)] = [("deno", "caché de Deno", .programas(nombre: "Deno", ejecutables: ["deno"])),
                                                      ("kotlin", "caché de Kotlin", nil)]
        for (n, que, uso) in deTerminal {
            let u = caches.appendingPathComponent(n)
            guard Self.tipo(u.path) == S_IFDIR, c.apps.estaInstalado(carpeta: n), c.indice.bytes(de: u) < minimo else { continue }
            partes.append(ParteSuelta(url: u, que: que, uso: uso))
        }
        // 7. Lo que deja el emulador de Android en ~/.android cada vez que arranca (un archivo por puerto).
        let emulador = EnUso.programas(nombre: "El emulador de Android", ejecutables: ["qemu-system-aarch64", "qemu-system-x86_64",
                                                                                       "qemu-system-aarch64-headless", "qemu-system-x86_64-headless",
                                                                                       "qemu-system-armel", "qemu-system-i386", "emulator"])
        let android = Rutas.enHome(".android").path
        for n in Self.nombres(en: android) where n.hasPrefix("modem-nv-ram-") {
            let ruta = android + "/" + n
            guard Self.tipo(ruta) == S_IFREG, Self.segundosDeCambio(ruta) < ahora - 3600 else { continue }
            partes.append(ParteSuelta(url: URL(fileURLWithPath: ruta), que: "restos de arranques del emulador de Android", uso: emulador))
        }
        // 8. Lo que «Restos de apps borradas» no ofrece porque no es de una app: los registros del daemon de Kotlin y los
        //    del emulador de Android en ~/Library/Logs (`restosSueltosDeAndroid`).
        partes += Self.restosSueltosDeAndroid(c).map { ParteSuelta(url: $0.url, que: $0.que, uso: $0.uso) }

        // Lo de una herramienta que está funcionando ahora, o lo que cambió en la última hora, se queda fuera esta vez.
        var dejadas: [String] = []
        let hace1h = Date().addingTimeInterval(-3600)
        partes = partes.filter { p in
            let porque: String
            if let uso = p.uso, let quien = c.procesos.quienUsa(uso) {
                porque = "\(p.que) (\(quien) está funcionando)"
            } else if let cambio = Self.ultimoCambioDentro(p.url.path, c), cambio > hace1h {
                porque = "\(p.que) (cambió hace menos de 1 h)"
            } else {
                return true
            }
            if !dejadas.contains(porque) { dejadas.append(porque) }
            return false
        }
        let tamanos = partes.map { Self.medida($0.url.path, c) }
        let total = tamanos.reduce(0, +)
        guard !partes.isEmpty, total >= minimo else { return [] }
        // Al limpiar se vuelve a mirar que no esté funcionando ninguna de esas herramientas.
        var ejecutables = Set<String>()
        for p in partes {
            switch p.uso {
            case .programas(_, let e)?: ejecutables.formUnion(e)
            case .app(let nombre, _)?: ejecutables.insert(nombre)
            // El demonio de Gradle es un programa de Java.
            case .gradle?: ejecutables.formUnion(["java", "gradle"])
            default: break
            }
        }
        var vistas = Set<String>()
        let ques = partes.map(\.que).filter { vistas.insert($0).inserted }
        var motivos: [Motivo] = [.bien("arrow.triangle.2.circlepath", "Se regeneran",
            "Cada herramienta las vuelve a crear (o a descargar, los binarios de npm) cuando le hacen falta. Casi todas son pequeñas: por eso van juntas.")]
        if !dejadas.isEmpty {
            motivos.append(.info("pause.circle", "Dejé fuera lo que se está usando",
                                 "No incluí \(Formato.listaCorta(dejadas)): lo ofreceré cuando esté quieto."))
        }
        return [Elemento(
            nombre: "Cachés sueltas de herramientas de desarrollo",
            detalle: "\(Formato.numero(partes.count)) \(partes.count == 1 ? "caché o resto" : "cachés y restos") de herramientas de desarrollo: \(Formato.listaCorta(ques, maximo: 6)).",
            consecuencia: "Nada que necesites: cada herramienta los vuelve a crear cuando le hacen falta (zsh tarda un poco más en abrir la primera terminal, y los binarios de npm se vuelven a bajar si reinstalas ese paquete).",
            rutas: partes.map(\.url), tamanosRutas: tamanos, categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
            motivos: motivos,
            enUso: ejecutables.isEmpty ? nil : .programas(nombre: "Una herramienta de desarrollo", ejecutables: ejecutables),
            dueno: "Herramientas de desarrollo")]
    }

    private static let patronVersionSuelta = try! NSRegularExpression(pattern: #"^v?\d+(\.\d+)+$"#)

    private static func pareceVersionSuelta(_ n: String) -> Bool {
        patronVersionSuelta.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
    }

    // MARK: - Pythons de uv sin entornos

    private static let patronSerieUv = try! NSRegularExpression(pattern: #"^(cpython|pypy|graalpy)-(\d+)\.(\d+)\.(\d+)(.*)$"#)

    /// Los comandos que uv deja en ~/.local/bin para un Python (python3.12, pip3.12…): no dicen que algo lo use.
    private static func esComandoDePython(_ n: String) -> Bool {
        ["python", "pip", "idle", "pydoc", "2to3"].contains { n.hasPrefix($0) }
    }

    /// Amplía `pythonsDeUv`: las series enteras (3.10, 3.11…) que no usa ningún entorno que conozca (`usados`: los «home»
    /// de los pyvenv.cfg de tus proyectos, de ~/.local/share/uv/tools y de pipx). La serie más nueva de cada familia
    /// (implementación, sistema y arquitectura) se queda siempre, igual que la que fijaste con «uv python pin --global».
    /// Siempre Revisar y sin marcar, ni en «Liberar al máximo»: la búsqueda de entornos no es completa (no ve los de PDM,
    /// tox, nox, direnv, un venv con otro nombre ni los kernels de Jupyter) y un entorno que lo usa no escribe nada en él,
    /// así que «nada cambió dentro» no dice que no se use. Si nada cambió en 7 días se dice, solo como información. No
    /// repite lo que ya ofrece `pythonsDeUv` (`yaOfrecidos`).
    func pythonsDeUvSinEntornos(usados: [String], yaOfrecidos: Set<String>, _ c: Contexto) -> [Elemento] {
        struct Serie {
            var carpetas: [URL] = []
            var mayor = 0
            var menor = 0
            var familia = ""
        }
        let base = Rutas.enHome(".local/share/uv/python")
        var series: [String: Serie] = [:]
        for h in Rutas.hijos(base) where Self.tipo(h.path) == S_IFDIR {
            let n = h.lastPathComponent
            guard let m = Self.patronSerieUv.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) else { continue }
            func parte(_ i: Int) -> String { Range(m.range(at: i), in: n).map { String(n[$0]) } ?? "" }
            let clave = "\(parte(1))-\(parte(2)).\(parte(3))\(parte(5))"
            var s = series[clave] ?? Serie(mayor: Int(parte(2)) ?? 0, menor: Int(parte(3)) ?? 0, familia: parte(1) + parte(5))
            s.carpetas.append(h)
            series[clave] = s
        }
        var nueva: [String: (Int, Int)] = [:]
        for s in series.values where nueva[s.familia].map({ $0 < (s.mayor, s.menor) }) ?? true { nueva[s.familia] = (s.mayor, s.menor) }
        // La versión global que fijaste («3.11» o «cpython-3.11…»).
        let fijadas = [".python-version", ".config/uv/.python-version"].compactMap { Self.leerPequeno(Rutas.enHome($0).path) }
            .flatMap { $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) } }.filter { !$0.isEmpty }
        // Los enlaces que llevan a cada carpeta: los de ~/.local/bin (python3.11…) y los de la propia carpeta de uv
        // (cpython-3.12-macos-aarch64-none → cpython-3.12.4-…).
        let enlaces: [(ruta: String, real: String)] = [Rutas.enHome(".local/bin").path, base.path].flatMap { d in
            Self.nombres(en: d).map { d + "/" + $0 }.filter { Self.tipo($0) == S_IFLNK }.map { (ruta: $0, real: Rutas.real(URL(fileURLWithPath: $0))) }
        }
        var r: [Elemento] = []
        for (_, s) in series.sorted(by: { $0.key < $1.key }) where nueva[s.familia].map({ $0 != (s.mayor, s.menor) }) ?? false {
            let xy = "\(s.mayor).\(s.menor)"
            if fijadas.contains(where: { $0 == xy || $0.hasPrefix(xy + ".") || $0.contains("-" + xy + ".") || $0.hasSuffix("-" + xy) }) { continue }
            let reales = s.carpetas.map { Rutas.real($0) + "/" }
            func dentro(_ ruta: String) -> Bool { reales.contains { (ruta + "/").hasPrefix($0) } }
            if usados.contains(where: dentro) { continue }
            // Un comando que no es el propio Python (una herramienta instalada con él) lo usa; o algo que está funcionando.
            let suyos = enlaces.filter { dentro($0.real) }
            if suyos.contains(where: { $0.ruta.hasPrefix(Rutas.enHome(".local/bin").path + "/") && !Self.esComandoDePython(Rutas.nombre($0.ruta)) }) { continue }
            if s.carpetas.contains(where: { c.apps.comandoDentro(de: $0.path).map { !Self.esComandoDePython($0) } ?? false }) { continue }
            if s.carpetas.contains(where: { c.procesos.usando($0.path) != nil }) { continue }
            let quedan = s.carpetas.filter { !yaOfrecidos.contains($0.path) }
            guard !quedan.isEmpty else { continue }
            // Primero los enlaces: borrado el Python, quedarían rotos y la limpieza se los saltaría.
            let rutas = suyos.map { URL(fileURLWithPath: $0.ruta) } + quedan
            let tamanos = rutas.map { Self.medida($0.path, c) }
            let total = tamanos.reduce(0, +)
            let masNueva = nueva[s.familia].map { "\($0.0).\($0.1)" } ?? ""
            // Si nada cambió dentro en 7 días (al usarse, Python guarda ahí sus .pyc), se dice, pero sigue para revisar:
            // un entorno que no encontré puede usarlo sin escribir nada dentro. También cuándo se instaló (la carpeta se
            // crea al instalarlo): sus archivos pueden traer la fecha del paquete.
            let instalado = quedan.compactMap { u -> Date? in
                var st = stat()
                return lstat(u.path, &st) == 0 ? Date(timeIntervalSince1970: TimeInterval(st.st_birthtimespec.tv_sec)) : nil
            }.max()
            let cambio = [c.indice.masReciente(de: quedan), instalado].compactMap { $0 }.max()
            let quieto = cambio.map { Date().timeIntervalSince($0) >= 7 * 86400 } ?? false
            var motivos: [Motivo] = [.info("shippingbox", "Sin entornos",
                                           "Miré los pyvenv.cfg de tus proyectos (.venv), de ~/.local/share/uv/tools y de pipx: ninguno apunta a Python \(xy). Si tienes entornos en otro sitio, revísalo.")]
            motivos.append(quieto
                ? .info("arrow.down.circle.fill", "Se vuelve a descargar",
                        "Nada cambió dentro desde \(Formato.haceCuanto(cambio).lowercased()) y tienes uno más nuevo. uv lo vuelve a descargar solo si un proyecto lo pide (uv run, uv sync), pero un entorno que lo use no escribe nada en él: revísalo antes de borrarlo.")
                : .info("clock.fill", "Usado hace poco",
                        "Algo cambió dentro \(Formato.haceCuanto(cambio).lowercased()) (Python guarda ahí lo que compila al usarse): puede que algo lo siga usando."))
            r.append(Elemento(
                nombre: "Python \(xy) de uv sin entornos",
                detalle: "Python \(xy) instalado con uv (\(Formato.listaCorta(quedan.map(\.lastPathComponent)))). Ningún entorno virtual de los que encontré lo usa, y tienes uno más nuevo (\(masNueva)).",
                consecuencia: "Lo que use Python \(xy) de uv (el comando python\(xy) de ~/.local/bin o un entorno que no encontré) dejará de funcionar hasta que lo reinstales con «uv python install \(xy)» (unos \(Formato.bytes(total)); necesita internet). uv lo descarga solo si un proyecto lo pide.",
                rutas: rutas, tamanosRutas: tamanos, categoria: .desarrollo, riesgo: .revisar,
                motivos: motivos,
                enUso: .rutas(nombre: "Python \(xy)", raiz: quedan[0].path), dueno: "uv",
                costes: [.descarga(bytes: total)]))
        }
        return r
    }

    // MARK: - Paquetes de pip --user

    /// Si hay un Python X.Y que use ~/Library/Python/X.Y: los de tipo framework de macOS (python.org, Homebrew, el de las
    /// Command Line Tools o Xcode) o cualquier «pythonX.Y» del PATH de tu terminal. En una casa de prueba, solo el PATH y
    /// el Homebrew de prueba.
    private static func hayPython(_ xy: String, _ c: Contexto) -> Bool {
        var candidatos: [String] = []
        if !Rutas.casaDePrueba {
            candidatos += ["/Library/Frameworks/Python.framework/Versions/\(xy)",
                           "/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/\(xy)"]
            for app in nombres(en: "/Applications") where app.hasPrefix("Xcode") && app.hasSuffix(".app") {
                candidatos.append("/Applications/\(app)/Contents/Developer/Library/Frameworks/Python3.framework/Versions/\(xy)")
            }
        }
        for p in Rutas.homebrew {
            candidatos += [p + "/opt/python@\(xy)", p + "/Frameworks/Python.framework/Versions/\(xy)", p + "/bin/python\(xy)"]
        }
        return candidatos.contains(where: Rutas.existe) || primeroEnElPath("python\(xy)", c) != nil
    }

    /// ~/Library/Python/<X.Y>: lo que instalaste con «pip install --user» para un Python X.Y. Sobra cuando ya no está ese
    /// Python y lleva más de 30 días sin uso. Revisar. Con el Python instalado (casi siempre está el de las Command Line
    /// Tools) no: sus programas siguen importando estos paquetes aunque los comandos de bin/ no se usen por su nombre.
    func paquetesDePipDeUsuario(_ c: Contexto) -> [Elemento] {
        let base = Rutas.enHome("Library/Python").path
        var r: [Elemento] = []
        for xy in Self.nombres(en: base) where xy.split(separator: ".").count == 2 && xy.allSatisfy({ $0.isNumber || $0 == "." }) {
            let carpeta = base + "/" + xy
            guard Self.tipo(carpeta) == S_IFDIR else { continue }
            guard !Self.hayPython(xy, c) else { continue }
            let ultima = c.indice.ultimaSenal(de: [URL(fileURLWithPath: carpeta)])
            guard let d = Self.dias(desde: ultima), d >= 30 else { continue }
            // Qué paquetes hay, por sus carpetas *.dist-info (solo los nombres).
            var vistos = Set<String>()
            let paquetes = Self.nombres(en: carpeta + "/lib/python/site-packages").filter { $0.hasSuffix(".dist-info") }
                .compactMap { $0.split(separator: "-").first.map(String.init) }.filter { vistos.insert($0.lowercased()).inserted }
            let motivos: [Motivo] = [
                .bien("questionmark.app", "Sin Python \(xy)",
                      "No encontré ningún Python \(xy) que use esta carpeta (ni el de las Command Line Tools, ni el de python.org, ni el de Homebrew, ni en el PATH)."),
                .info("moon.zzz.fill", "Sin uso",
                      "No veo cambios ni lecturas desde \(Formato.haceCuanto(ultima).lowercased()). macOS no anota todas las lecturas: si algún script tuyo importa estos paquetes, revísalo."),
            ]
            r.append(Elemento(
                nombre: "Paquetes de pip para Python \(xy) (pip --user)",
                detalle: "Lo que instalaste con «pip install --user» para Python \(xy)\(paquetes.isEmpty ? "" : ": \(Formato.listaCorta(paquetes, maximo: 5))").",
                consecuencia: "Nada, si ya no usas Python \(xy). Si lo vuelves a instalar, tendrás que volver a instalar estos paquetes con pip (necesita internet).",
                rutas: [URL(fileURLWithPath: carpeta)], categoria: .desarrollo, riesgo: .revisar, motivos: motivos,
                enUso: .rutas(nombre: "Python \(xy)", raiz: carpeta), dueno: "Python"))
        }
        return r
    }

    // MARK: - Java descargado por el IDE

    /// Los nombres de Java que dicen tus proyectos de Gradle: «org.gradle.java.home» en gradle.properties (el tuyo de
    /// ~/.gradle y el de cada proyecto) y el «gradleJvm» y «project-jdk-name» de su .idea. Solo archivos pequeños.
    private static func javasDeProyectos(_ c: Contexto) -> [String] {
        let patrones = [try! NSRegularExpression(pattern: #"name="gradleJvm"\s+value="([^"]+)""#),
                        try! NSRegularExpression(pattern: #"project-jdk-name="([^"]+)""#)]
        var r: [String] = []
        let raices = c.indice.wrappersGradle.map { Rutas.padre(Rutas.padre(Rutas.padre($0))) }
        for propiedades in [Rutas.enHome(".gradle/gradle.properties").path] + raices.map({ $0 + "/gradle.properties" }) {
            for linea in (leerPequeno(propiedades) ?? "").split(separator: "\n") where linea.hasPrefix("org.gradle.java.home") {
                if let valor = linea.split(separator: "=", maxSplits: 1).last { r.append(valor.trimmingCharacters(in: .whitespaces)) }
            }
        }
        for raiz in raices {
            for archivo in ["/.idea/gradle.xml", "/.idea/misc.xml"] {
                guard let texto = leerPequeno(raiz + archivo) else { continue }
                for p in patrones {
                    for m in p.matches(in: texto, range: NSRange(texto.startIndex..., in: texto)) {
                        if let rango = Range(m.range(at: 1), in: texto) { r.append(String(texto[rango])) }
                    }
                }
            }
        }
        return r
    }

    /// ~/Library/Java/JavaVirtualMachines/<nombre> con un «.<nombre>.intellij» al lado (lo bajó Android Studio o IntelliJ
    /// con «Download JDK») que ningún proyecto nombra y sin ejecutarse en más de 60 días según macOS. Revisar.
    func javasDelIDE(_ c: Contexto) -> [Elemento] {
        let carpeta = Rutas.enHome("Library/Java/JavaVirtualMachines").path
        let nombrados = Self.javasDeProyectos(c)
        let delSistema = Rutas.casaDePrueba ? [] : Self.nombres(en: "/Library/Java/JavaVirtualMachines").filter { !$0.hasPrefix(".") }
        let todos = Self.nombres(en: carpeta).filter { !$0.hasPrefix(".") && Self.tipo(carpeta + "/" + $0) == S_IFDIR }
        var r: [Elemento] = []
        for n in todos {
            let jdk = carpeta + "/" + n
            let marca = carpeta + "/." + n + ".intellij"
            guard Self.tipo(marca) == S_IFREG else { continue }
            // Lo usa un proyecto: por su nombre («jbr-21» vale para jbr-21.0.11), por su ruta o por su versión («17»).
            if nombrados.contains(where: { v in
                !v.hasPrefix("#") && (n == v || n.hasPrefix(v + ".") || n.hasPrefix(v + "-") || v.contains("/JavaVirtualMachines/\(n)")
                                      || (v.allSatisfy(\.isNumber) && n.contains("-" + v)))
            }) { continue }
            // La última ejecución que anotó macOS (el atime de bin/java) o, si es posterior, cuándo se descargó (la marca).
            var java = jdk + "/Contents/Home/bin/java"
            if !Rutas.existe(java) { java = jdk + "/bin/java" }
            var st = stat()
            guard stat(java, &st) == 0 else { continue }
            let leido = Int(st.st_atimespec.tv_sec)
            let instalado = max(Self.segundosDeCambio(marca), Int(st.st_mtimespec.tv_sec), Compresor.mirarCtime ? Int(st.st_ctimespec.tv_sec) : 0)
            let ultima = Date(timeIntervalSince1970: TimeInterval(max(leido, instalado)))
            guard let d = Self.dias(desde: ultima), d >= 60 else { continue }
            let nunca = leido <= instalado + 600
            let unico = todos.count == 1 && delSistema.isEmpty
            var motivos: [Motivo] = [.info("arrow.down.circle.fill", "Lo descargó el IDE",
                "Al lado está «.\(n).intellij»: lo bajó Android Studio o IntelliJ con «Download JDK». Ningún proyecto de Gradle que encontré lo pide (gradle.properties, .idea).")]
            motivos.append(nunca
                ? .info("moon.zzz.fill", "Sin ejecuciones anotadas",
                        "Desde que se descargó, \(Formato.haceCuanto(ultima).lowercased()), macOS no anotó ninguna ejecución de su java. Ojo: macOS no las anota todas (solo la primera después de instalarlo), así que no es una prueba.")
                : .info("moon.zzz.fill", "Última ejecución anotada: \(Formato.haceCuanto(ultima).lowercased())",
                        "Es la última ejecución de su java que anotó macOS. macOS no anota cada ejecución (solo la primera después de instalarlo): puede que se haya usado después."))
            if unico {
                motivos.append(.aviso("cup.and.saucer.fill", "Es tu único Java",
                                      "No hay otro Java en ~/Library/Java ni en /Library/Java: el comando «java» de la terminal dejará de funcionar."))
            }
            r.append(Elemento(
                nombre: "Java \(n) descargado por el IDE",
                detalle: "Un JDK que descargó Android Studio o IntelliJ en ~/Library/Java/JavaVirtualMachines.",
                consecuencia: "Los proyectos que lo elijan como Gradle JDK no compilarán hasta que lo vuelvas a descargar desde el IDE (unos \(Formato.bytes(Self.medida(jdk, c))); necesita internet).\(unico ? " Y «java» en la terminal dejará de funcionar." : "") Va a la Papelera.",
                rutas: [URL(fileURLWithPath: jdk), URL(fileURLWithPath: marca)], ultimoUso: ultima, categoria: .desarrollo, riesgo: .revisar,
                motivos: motivos, enUso: .rutas(nombre: "Java \(n)", raiz: jdk), dueno: "Java",
                costes: [.descarga(bytes: Self.medida(jdk, c))]))
        }
        return r
    }

    // MARK: - Paquetes globales de npm sin uso

    /// Dónde instala «npm install -g»: el Node de Homebrew, los de nvm, fnm y ~/.local/runtime, y los prefijos habituales
    /// que se configuran a mano (~/.npm-global…).
    private static func prefijosDeNpm() -> [String] {
        var r = Rutas.homebrew
        for (base, sub) in [(".nvm/versions/node", ""), (".local/runtime", ""), (".local/share/fnm/node-versions", "/installation"),
                            ("Library/Application Support/fnm/node-versions", "/installation")] {
            let d = Rutas.enHome(base).path
            r += nombres(en: d).filter { !$0.hasPrefix(".") }.map { d + "/" + $0 + sub }
        }
        r += [".npm-global", ".npm-packages", ".local"].map { Rutas.enHome($0).path }
        return r.filter { tipo($0 + "/lib/node_modules") == S_IFDIR }
    }

    /// «…/lib/node_modules/@openai/codex/bin/codex.js» → «…/lib/node_modules/@openai/codex».
    private static func paqueteNpm(de ruta: String) -> String? {
        guard let r = ruta.range(of: "/lib/node_modules/", options: .backwards) else { return nil }
        let partes = ruta[r.upperBound...].split(separator: "/")
        guard let primera = partes.first else { return nil }
        let paquete = primera.hasPrefix("@") && partes.count > 1 ? "\(primera)/\(partes[1])" : String(primera)
        return String(ruta[..<r.upperBound]) + paquete
    }

    /// Si un programa guarda algo con ese nombre en tu carpeta (configuración, sesiones, cachés): entonces se ha usado.
    private static func tieneDatosPropios(_ n: String) -> Bool {
        let n = n.hasPrefix(".") ? String(n.dropFirst()) : n
        guard !n.isEmpty else { return true }
        return [".\(n)", ".config/\(n)", ".local/share/\(n)", ".local/state/\(n)", ".cache/\(n)", "Library/Application Support/\(n)",
                ".config/configstore/\(n).json"].contains { Rutas.existe(Rutas.enHome($0)) }
    }

    /// Paquetes globales de npm (con algún comando) instalados hace más de 60 días, sin ninguna carpeta de datos propia y
    /// sin ejecutarse en más de 60 días según lo que anotó macOS. Revisar. Los de detrás en el PATH ya los ofrece
    /// `comandosTapados`.
    func paquetesGlobalesDeNpm(_ c: Contexto) -> [Elemento] {
        let home = Rutas.real(Rutas.home) + "/"
        let ahora = Int(Date().timeIntervalSince1970)
        let path = c.apps.pathTerminal.map { Rutas.real(URL(fileURLWithPath: $0)) }
        // Los enlaces de ~/.local/bin y ~/bin: si llevan a un paquete, se van con él (si no, quedarían rotos).
        let enlacesSueltos = [".local/bin", "bin"].map { Rutas.enHome($0).path }.flatMap { d in
            Self.nombres(en: d).map { d + "/" + $0 }.filter { Self.tipo($0) == S_IFLNK }
        }
        var r: [Elemento] = []
        for prefijo in Self.prefijosDeNpm() {
            let modulos = prefijo + "/lib/node_modules"
            let bin = prefijo + "/bin"
            var porPaquete: [String: [String]] = [:]
            for n in Self.nombres(en: bin) where Self.tipo(bin + "/" + n) == S_IFLNK {
                let real = Rutas.real(URL(fileURLWithPath: bin + "/" + n))
                if let p = Self.paqueteNpm(de: real), p.hasPrefix(Rutas.real(URL(fileURLWithPath: modulos)) + "/") {
                    porPaquete[p, default: []].append(bin + "/" + n)
                }
            }
            let binEnPath = path.contains(Rutas.real(URL(fileURLWithPath: bin)))
            for (paquete, enlaces) in porPaquete.sorted(by: { $0.key < $1.key }) {
                let nombre = String(paquete[paquete.range(of: "/lib/node_modules/", options: .backwards)!.upperBound...])
                guard !["npm", "corepack"].contains(nombre) else { continue }
                let comandos = enlaces.map { Rutas.nombre($0) }
                let corto = String(nombre.split(separator: "/").last ?? Substring(nombre))
                if (comandos + [corto]).contains(where: Self.tieneDatosPropios) { continue }
                // Si alguno de sus comandos queda detrás de otro en el PATH, ya lo ofrece «… que no se usa».
                if binEnPath && paquete.hasPrefix(home) && comandos.contains(where: { n in
                    Self.primeroEnElPath(n, c).map { !Rutas.real(URL(fileURLWithPath: $0)).hasPrefix(paquete + "/") } ?? false
                }) { continue }
                // La última ejecución que anotó macOS (atime de cada programa) y cuándo se instaló (la carpeta y el programa).
                var leido = 0
                var instalado = Self.segundosDeCambio(paquete)
                for e in enlaces {
                    var st = stat()
                    guard stat(e, &st) == 0 else { continue }
                    leido = max(leido, Int(st.st_atimespec.tv_sec))
                    instalado = max(instalado, Int(st.st_mtimespec.tv_sec))
                }
                let ultima = max(leido, instalado)
                guard ahora - ultima >= 60 * 86400 else { continue }
                let nunca = leido <= instalado + 600
                let fechaUltima = Date(timeIntervalSince1970: TimeInterval(ultima))
                let fechaInstalado = Date(timeIntervalSince1970: TimeInterval(instalado))
                let sueltos = enlacesSueltos.filter { !enlaces.contains($0) && Rutas.real(URL(fileURLWithPath: $0)).hasPrefix(paquete + "/") }
                // Primero los enlaces: borrado el paquete, quedarían rotos y la limpieza se los saltaría.
                let rutas = sueltos + enlaces + [paquete]
                let enCasa = paquete.hasPrefix(home)
                let npm = bin + "/npm"
                // Fuera de tu carpeta (Homebrew) no se borra a mano: lo desinstala su propio npm.
                guard enCasa || FileManager.default.isExecutableFile(atPath: npm) else { continue }
                let motivos: [Motivo] = [
                    nunca ? .info("moon.zzz.fill", "Sin ejecuciones anotadas",
                                  "Desde que se instaló, \(Formato.haceCuanto(fechaInstalado).lowercased()), macOS no anotó ninguna ejecución de \(Formato.lista(comandos)). Ojo: macOS no las anota todas (solo la primera después de instalarlo o actualizarlo), así que no es una prueba de que no lo uses.")
                          : .info("moon.zzz.fill", "Última ejecución anotada: \(Formato.haceCuanto(fechaUltima).lowercased())",
                                  "Es la última ejecución de \(Formato.lista(comandos)) que anotó macOS. macOS no anota cada ejecución (solo la primera después de instalarlo o actualizarlo): puede que lo hayas usado después."),
                    .bien("folder.badge.questionmark", "Sin datos propios",
                          "No encontré ninguna carpeta suya (~/.\(corto), ~/.config/\(corto)…): no parece que guarde nada tuyo."),
                ]
                r.append(Elemento(
                    nombre: "Paquete global de npm «\(nombre)»",
                    detalle: "Instalado con «npm install -g» en \(Formato.rutaCorta(prefijo)); su comando es \(Formato.lista(comandos.map { "«\($0)»" })).",
                    consecuencia: enCasa
                        ? "\(comandos.count == 1 ? "El comando deja" : "Los comandos dejan") de existir. Si lo necesitas, se vuelve a instalar con «npm install -g \(nombre)» (necesita internet). Va a la Papelera: puedes devolverlo con «Deshacer»."
                        : "Lo desinstala npm con «npm uninstall -g \(nombre)» (no pasa por la Papelera). Si lo necesitas, se vuelve a instalar con «npm install -g \(nombre)» (necesita internet).",
                    rutas: rutas.map { URL(fileURLWithPath: $0) },
                    tamanosRutas: enCasa ? rutas.map { Self.medida($0, c) } : [],
                    tamanoFijo: enCasa ? nil : Tamanos.recorriendo(paquete),
                    ultimoUso: fechaUltima, categoria: .desarrollo, riesgo: .revisar,
                    accion: enCasa ? .borrar : .comando(programa: npm, argumentos: ["uninstall", "-g", nombre],
                                                        entorno: ["PATH": bin + ":/usr/bin:/bin:/usr/sbin:/sbin", "NPM_CONFIG_UPDATE_NOTIFIER": "false",
                                                                  "NPM_CONFIG_FUND": "false", "NPM_CONFIG_AUDIT": "false"], limite: 120),
                    motivos: motivos, enUso: .rutas(nombre: comandos[0], raiz: paquete), dueno: "npm"))
            }
        }
        return r
    }

    // MARK: - Bases de datos paradas

    /// Las carpetas de datos de PostgreSQL (PG_VERSION, base/ y global/), MySQL (ibdata1) y MongoDB (WiredTiger) de tu
    /// carpeta, encontradas en el índice por las subcarpetas que siempre tienen.
    static func basesDeDatos(_ c: Contexto) -> [(ruta: String, motor: String)] {
        let home = Rutas.home.path + "/"
        let marcas: Set<String> = ["base", "global", "pg_wal", "pg_xlog", "#innodb_redo", "#innodb_temp", "mysql", "journal", "diagnostic.data"]
        var vistas = Set<String>()
        var r: [(ruta: String, motor: String)] = []
        for ruta in c.indice.carpetas.keys where ruta.hasPrefix(home) && marcas.contains(Rutas.nombre(ruta)) {
            let d = Rutas.padre(ruta)
            guard vistas.insert(d).inserted else { continue }
            if tipo(d + "/PG_VERSION") == S_IFREG && tipo(d + "/base") == S_IFDIR && tipo(d + "/global") == S_IFDIR {
                r.append((d, "PostgreSQL"))
            } else if tipo(d + "/ibdata1") == S_IFREG {
                r.append((d, "MySQL"))
            } else if tipo(d + "/WiredTiger") == S_IFREG {
                r.append((d, "MongoDB"))
            }
        }
        return r.sorted { $0.ruta < $1.ruta }
    }

    /// Si la carpeta oculta (o la de ~/.local/share) que contiene esa ruta ya la ofrece entera «Carpetas ocultas».
    private static func laOfreceCarpetasOcultas(_ ruta: String) -> Bool {
        let home = Rutas.home.path + "/"
        guard ruta.hasPrefix(home) else { return false }
        let partes = ruta.dropFirst(home.count).split(separator: "/").map(String.init)
        guard let primera = partes.first, primera.hasPrefix(".") else { return false }
        if !ocultasConocidas.contains(primera) && !contenedoresOcultos.contains(primera) { return true }
        return primera == ".local" && partes.count >= 3 && partes[1] == "share" && !partes[2].hasPrefix(".")
            && !["fnm", "uv", "cursor-agent"].contains(partes[2])
    }

    /// Bases de datos que nadie usa desde hace más de 30 días y sin servidor en marcha (sin postmaster.pid, sin *.pid, con
    /// mongod.lock vacío y sin ningún programa dentro): Cuidado, nunca se marcan. Las de las apps que las gestionan
    /// (Postgres.app, DBngin…) y las que ya van dentro de una carpeta oculta entera no se repiten.
    func basesDeDatosParadas(_ c: Contexto) -> [Elemento] {
        let appSupport = Rutas.enHome("Library/Application Support").path + "/"
        var r: [Elemento] = []
        for (d, motor) in Self.basesDeDatos(c) {
            if d.contains("/Library/Containers/") || d.contains("/Library/Group Containers/") || Self.laOfreceCarpetasOcultas(d) { continue }
            // En Application Support: la gestiona su app o, si ya no está, «Restos» ofrece su carpeta entera.
            if d.hasPrefix(appSupport) { continue }
            let funcionando: Bool
            switch motor {
            case "PostgreSQL": funcionando = Rutas.existe(d + "/postmaster.pid")
            case "MySQL": funcionando = Self.nombres(en: d).contains { $0.hasSuffix(".pid") }
            default:
                var st = stat()
                funcionando = lstat(d + "/mongod.lock", &st) == 0 && st.st_size > 0
            }
            guard !funcionando, c.procesos.usando(d) == nil else { continue }
            let cambio = Self.ultimoCambioDentro(d, c)
            guard let dias = Self.dias(desde: cambio), dias >= 30 else { continue }
            let version = motor == "PostgreSQL"
                ? (Self.leerPequeno(d + "/PG_VERSION", maximo: 64)?.trimmingCharacters(in: .whitespacesAndNewlines)).map { " " + $0 } ?? ""
                : ""
            let registro = d + ".log"
            let rutas = [d] + (Self.tipo(registro) == S_IFREG ? [registro] : [])
            let copia = motor == "PostgreSQL" ? "pg_dump" : (motor == "MySQL" ? "mysqldump" : "mongodump")
            r.append(Elemento(
                nombre: "Base de datos \(motor)\(version) parada",
                detalle: "La carpeta de datos de un servidor \(motor) en \(Formato.rutaCorta(d)). No hay ningún servidor usándola y nada cambió dentro desde \(Formato.haceCuanto(cambio).lowercased()).",
                consecuencia: "Se pierden todas las bases de datos que guarda (tablas, usuarios y datos), y no se vuelven a crear. Si algo te sirve, guárdalo antes con \(copia) (arrancando el servidor con esta carpeta).",
                rutas: rutas.map { URL(fileURLWithPath: $0) }, ultimoUso: cambio, categoria: .desarrollo, riesgo: .cuidado,
                motivos: [.aviso("cylinder.split.1x2.fill", "Base de datos parada desde \(Formato.haceCuanto(cambio).lowercased())",
                                 "Son datos, no una caché: revisa qué hay antes de borrarla. No hay ningún servidor en marcha con esta carpeta.")],
                enUso: .rutas(nombre: motor, raiz: d), dueno: motor))
        }
        return r
    }

    // MARK: - Preferencias que dejan las pruebas

    private static let patronDominioDePrueba = try! NSRegularExpression(
        pattern: #"^(.+)\.[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.plist$"#)

    /// Los dominios de UserDefaults que crean las pruebas automáticas con un UUID en el nombre
    /// (`UserDefaults(suiteName: "<prefijo>.\(UUID())")`) en ~/Library/Preferences, por prefijo: los que tienen 5 o más
    /// con el mismo prefijo, o un prefijo que acaba en «Tests» o «Test». Los de Apple no. «Restos» no los repite.
    static func dominiosDePrueba() -> [String: [URL]] {
        var porPrefijo: [String: [URL]] = [:]
        for p in Rutas.hijos(Rutas.enHome("Library/Preferences")) {
            let n = p.lastPathComponent
            guard let m = patronDominioDePrueba.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)),
                  let rango = Range(m.range(at: 1), in: n), !n.lowercased().hasPrefix("com.apple.") else { continue }
            porPrefijo[String(n[rango]), default: []].append(p)
        }
        return porPrefijo.filter { prefijo, lista in lista.count >= 5 || prefijo.hasSuffix("Tests") || prefijo.hasSuffix("Test") }
    }

    func preferenciasDePruebas(_ c: Contexto) -> [Elemento] {
        let dominios = Self.dominiosDePrueba()
        guard !dominios.isEmpty else { return [] }
        let rutas = dominios.keys.sorted().flatMap { dominios[$0] ?? [] }
        let prefijos = dominios.sorted { $0.value.count > $1.value.count }.map { "\($0.key) (\($0.value.count))" }
        return [Elemento(
            nombre: "Preferencias que dejaron tus pruebas (\(Formato.numero(rutas.count)))",
            detalle: "Dominios de UserDefaults con un UUID en el nombre, como los que crean las pruebas automáticas y no borran: \(Formato.listaCorta(prefijos, maximo: 4)).",
            consecuencia: "Normalmente nada: cada prueba crea uno nuevo con otro UUID. Si alguna app tuya guarda así sus ajustes de verdad, los perdería. Van a la Papelera.",
            rutas: rutas, tamanosRutas: rutas.map { Self.medida($0.path, c) }, categoria: .desarrollo, riesgo: .revisar,
            motivos: [.info("testtube.2", "Dominios de pruebas",
                            "Tienen un UUID en el nombre y se repiten con el mismo prefijo (o el prefijo acaba en «Tests»): así los crean las pruebas con UserDefaults(suiteName:).")],
            enUso: .programas(nombre: "Las pruebas de Xcode", ejecutables: ["xctest", "xcodebuild", "swift-test"]), dueno: "Xcode")]
    }

    // MARK: - Conversaciones de proyectos que ya no existen

    /// Cómo nombra Claude Code la carpeta de un proyecto en ~/.claude/projects: todo lo que no es una letra o una cifra
    /// ASCII pasa a «-» («/Users/ana/Niños» → «-Users-ana-Ni-os»), contado en unidades UTF-16.
    static func codificarComoClaude(_ texto: String) -> String {
        String(texto.utf16.map { u -> Character in
            (u >= 48 && u <= 57) || (u >= 65 && u <= 90) || (u >= 97 && u <= 122) ? Character(UnicodeScalar(u)!) : "-"
        })
    }

    /// ¿Hay una carpeta cuya ruta, codificada así, da `codificada`? Se busca nivel a nivel, solo por las carpetas cuyo nombre
    /// encaja (con su forma compuesta y descompuesta), sin abrir ningún archivo. Nil si no se pudo saber: el nombre es tan
    /// largo que Claude Code lo recorta, hay demasiadas posibilidades o alguna carpeta no se pudo leer.
    static func existeCarpeta(codificadaComoClaude codificada: String, maximo: Int = 2_000) -> Bool? {
        guard codificada.count < 190, codificada.hasPrefix("-") else { return nil }
        if codificada == "-" { return true }
        var pendientes: [(ruta: String, resto: Substring)] = [("", Substring(codificada))]
        var mirados = 0
        var incompleto = false
        while let (ruta, resto) = pendientes.popLast() {
            if resto.isEmpty { return true }
            guard resto.first == "-" else { continue }
            let tras = resto.dropFirst()
            mirados += 1
            if mirados > maximo { return nil }
            guard let hijos = try? FileManager.default.contentsOfDirectory(atPath: ruta.isEmpty ? "/" : ruta) else {
                incompleto = true
                continue
            }
            for h in hijos {
                for forma in Set([h.precomposedStringWithCanonicalMapping, h.decomposedStringWithCanonicalMapping]) {
                    let e = codificarComoClaude(forma)
                    guard !e.isEmpty, tras.hasPrefix(e) else { continue }
                    let siguiente = tras.dropFirst(e.count)
                    guard siguiente.isEmpty || siguiente.first == "-", Rutas.esCarpeta(URL(fileURLWithPath: ruta + "/" + h)) else { continue }
                    pendientes.append((ruta + "/" + h, siguiente))
                }
            }
        }
        return incompleto ? nil : false
    }

    /// ~/.claude/projects/<carpeta>: las conversaciones de Claude Code de proyectos cuya carpeta (la que dice el nombre de
    /// la suya) ya no existe. Revisar, todas juntas. Las de las últimas 24 h no (puede que la sesión siga abierta), ni las de
    /// un disco externo. Las transcripciones no se abren: pueden tener tus mensajes.
    func conversacionesDeProyectosBorrados(_ c: Contexto) -> [Elemento] {
        let raiz = Rutas.enHome(".claude/projects").path
        var huerfanas: [String] = []
        var proyectos: [String] = []
        let casa = Self.codificarComoClaude(Rutas.home.path) + "-"
        for n in Self.nombres(en: raiz) where n.hasPrefix("-") && !n.hasPrefix("-Volumes-") {
            let carpeta = raiz + "/" + n
            guard Self.tipo(carpeta) == S_IFDIR, let d = Self.dias(desde: Self.ultimoCambioDentro(carpeta, c)), d >= 1,
                  Self.nombres(en: carpeta).contains(where: { $0.hasSuffix(".jsonl") }),
                  Self.existeCarpeta(codificadaComoClaude: n) == false else { continue }
            huerfanas.append(carpeta)
            proyectos.append(n.hasPrefix(casa) ? String(n.dropFirst(casa.count)) : n)
        }
        guard !huerfanas.isEmpty else { return [] }
        return [Elemento(
            nombre: "Conversaciones de Claude Code de proyectos que ya no existen",
            detalle: "Las transcripciones de \(huerfanas.count == 1 ? "un proyecto cuya carpeta" : "\(huerfanas.count) proyectos cuyas carpetas") ya no \(huerfanas.count == 1 ? "está" : "están") en el Mac: \(Formato.listaCorta(proyectos, maximo: 5)).",
            consecuencia: "Ya no podrás retomarlas con «claude --resume» ni volver a leerlas. Las de los proyectos que siguen existiendo no se tocan. Van a la Papelera.",
            rutas: huerfanas.map { URL(fileURLWithPath: $0) }, tamanosRutas: huerfanas.map { Self.medida($0, c) },
            categoria: .herramientas, riesgo: .revisar,
            motivos: [.info("folder.badge.questionmark", "Proyecto borrado",
                            "La carpeta en la que se abrió cada una (la que dice el nombre de su carpeta en ~/.claude/projects) ya no existe. No abrí ninguna conversación.")],
            dueno: "Claude Code")]
    }

    // MARK: - Restos de herramientas desinstaladas

    /// Carpetas de ~/.config que no son de una herramienta concreta (o que usan muchas).
    private static let configCompartidas: Set<String> = ["configstore", "git", "fontconfig", "autostart", "systemd", "menus",
                                                          "environment.d", "gtk-2.0", "gtk-3.0", "gtk-4.0", "dconf", "pulse",
                                                          "xdg-desktop-portal", "mimeapps.list", "user-dirs.dirs",
                                                          // De extensiones de editores (Copilot guarda aquí su sesión, también
                                                          // para JetBrains y Xcode) y de los complementos que comparten.
                                                          "github-copilot", "copilot", "jgit", "codeium", "windsurf", "tabnine",
                                                          "sourcegraph", "continue", "supermaven",
                                                          // La configuración que escribes tú (editores, terminales, shells).
                                                          "nvim", "vim", "emacs", "doom", "helix", "kakoune", "micro", "kitty",
                                                          "alacritty", "wezterm", "ghostty", "karabiner", "skhd", "yabai",
                                                          "aerospace", "sketchybar", "borders", "tmux", "zellij", "fish", "zsh",
                                                          "bash", "starship", "lazygit", "htop", "btop", "neofetch", "fastfetch"]

    /// ~/.config/<x> y ~/.local/state/<x> de una herramienta que ya no está (ni su comando, ni una app con su nombre, ni
    /// ~/.<x>/bin) y que llevan más de 30 días sin cambios. Revisar, una por herramienta. Las bases de datos van aparte.
    func restosDeHerramientasDesinstaladas(_ c: Contexto) -> [Elemento] {
        let bases = Self.basesDeDatos(c).map(\.ruta)
        var porHerramienta: [String: (nombre: String, rutas: [String])] = [:]
        for rel in [".config", ".local/state"] {
            let base = Rutas.enHome(rel).path
            for x in Self.nombres(en: base) where !x.hasPrefix(".") {
                let ruta = base + "/" + x
                let l = x.lowercased()
                // binariosDeAgentes ya mira las de manicode (Codebuff y Freebuff).
                guard Self.tipo(ruta) == S_IFDIR, !Self.configCompartidas.contains(l), !l.hasPrefix("manicode") else { continue }
                if c.apps.reconoce(carpetaOculta: x) || c.apps.estaInstalado(carpeta: x) || c.apps.comandoPara(carpetaOculta: "." + x) != nil
                    || Rutas.esCarpeta(Rutas.enHome("." + x + "/bin")) { continue }
                if bases.contains(where: { $0 == ruta || $0.hasPrefix(ruta + "/") }) { continue }
                guard let d = Self.dias(desde: Self.ultimoCambioDentro(ruta, c)), d >= 30 else { continue }
                porHerramienta[l, default: (x, [])].rutas.append(ruta)
            }
        }
        return porHerramienta.sorted { $0.key < $1.key }.map { par -> Elemento in
            let h = par.value
            let cambio = h.rutas.compactMap { Self.ultimoCambioDentro($0, c) }.max()
            return Elemento(
                nombre: "Restos de \(h.nombre)",
                detalle: "Configuración y estado de \(h.nombre), que no parece instalado: \(Formato.lista(h.rutas.map { Formato.rutaCorta($0) })).",
                consecuencia: "Si vuelves a instalar \(h.nombre), empezará sin tu configuración anterior. Va a la Papelera.",
                rutas: h.rutas.map { URL(fileURLWithPath: $0) }, tamanosRutas: h.rutas.map { Self.medida($0, c) }, ultimoUso: cambio,
                categoria: .herramientas, riesgo: .revisar,
                motivos: [.info("magnifyingglass", "No encontré su comando",
                                "No encontré el comando \(h.nombre) en tu terminal, ni ~/.\(h.nombre)/bin, ni una app con ese nombre. Puede ser de una extensión o un archivo de configuración que escribiste tú: revísalo."),
                          .info("moon.zzz.fill", "Sin cambios", "Nada cambió dentro desde \(Formato.haceCuanto(cambio).lowercased()).")],
                enUso: .rutas(nombre: h.nombre, raiz: h.rutas[0]), dueno: h.nombre)
        }
    }

    // MARK: - Restos pequeños de apps borradas

    /// Junta en «Restos pequeños de N apps» los restos de menos de 1 MB (que solos no se enseñarían), cuando entre todos
    /// llegan a 1 MB. Los que deben verse siempre (los que llevan un agente de inicio) y los de Cuidado van solos.
    static func juntarRestosPequenos(_ restos: [Elemento], minimo: Int64, _ c: Contexto) -> [Elemento] {
        var quedan: [Elemento] = []
        var pequenos: [(el: Elemento, tamanos: [Int64])] = []
        for el in restos {
            let tamanos = el.rutas.map { medida($0.path, c) }
            if el.siempreVisible || el.riesgo == .cuidado || el.accion != .borrar || tamanos.reduce(0, +) >= minimo {
                quedan.append(el)
            } else {
                // Lo que es de macOS o de una librería (y «Restos» toma por una app) no entra en el grupo: solo no se
                // enseñaba por pequeño, y junto a los demás tampoco.
                var el = el
                let buenas = el.rutas.indices.filter { !esRestoDeSistema(el.rutas[$0]) }
                guard !buenas.isEmpty else { continue }
                el.rutas = buenas.map { el.rutas[$0] }
                pequenos.append((el, buenas.map { tamanos[$0] }))
            }
        }
        let total = pequenos.reduce(Int64(0)) { $0 + $1.tamanos.reduce(0, +) }
        guard pequenos.count >= 2, total >= minimo else { return restos }
        var claves: [String] = []
        var apps = 0
        // Los avisos de cada uno (actividad reciente…) se quedan, con el nombre de su app delante.
        var avisos: [Motivo] = []
        for p in pequenos {
            if case .app(_, let k)? = p.el.enUso {
                claves += k
                apps += 1
            } else {
                apps += p.el.rutas.count   // «Preferencias de N apps desinstaladas»: una por app
            }
            for m in p.el.motivos where m.nivel >= .aviso {
                avisos.append(Motivo(nivel: m.nivel, icono: m.icono, etiqueta: m.etiqueta, texto: "\(p.el.nombre): \(m.texto)"))
            }
        }
        quedan.append(Elemento(
            nombre: "Restos pequeños de \(apps) apps",
            detalle: "Lo que dejaron apps que ya no están instaladas, cada una con menos de 1 MB: \(Formato.listaCorta(pequenos.map(\.el.nombre), maximo: 6)).",
            consecuencia: "No afecta a ninguna app instalada. Si reinstalas alguna, empezará sin su configuración anterior. Va a la Papelera.",
            rutas: pequenos.flatMap(\.el.rutas), tamanosRutas: pequenos.flatMap(\.tamanos), categoria: .restos, riesgo: .revisar,
            motivos: [.bien("magnifyingglass", "No están instaladas",
                            "No encontré ninguna de estas apps en Aplicaciones, ni en Homebrew, ni entre los programas abiertos."),
                      .info("square.stack.3d.down.right", "Juntos",
                            "Por separado no llegan a 1 MB y no se enseñarían: van juntos para que los revises de una vez.")] + avisos,
            enUso: claves.isEmpty ? nil : .app(nombre: "Una de esas apps", claves: claves)))
        return quedan
    }

    /// Carpetas y ajustes que no son de una app que borraste: de macOS (WebKit/Databases, Logs/Baseband…), de los
    /// lenguajes y las librerías (Python, Java, Electron, Sparkle) y los scripts de extensiones con nombre UUID.
    private static let restosDeSistema: Set<String> = ["databases", "baseband", "temporaryitems", "privacypreservingmeasurement",
                                                       "audiounitcache", "ssu", "amsdatamigratortool", "org.python.python.plist",
                                                       "com.jetbrains.jbr.java.plist", "net.java.openjdk.java.plist",
                                                       "com.github.electron.plist", "org.sparkle-project.sparkle.autoupdate.plist"]
    private static let patronUUID = try! NSRegularExpression(
        pattern: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#)

    private static func esRestoDeSistema(_ u: URL) -> Bool {
        let n = u.lastPathComponent
        return restosDeSistema.contains(n.lowercased()) || patronUUID.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
    }

    // MARK: - Registros de Wrangler

    /// Cloudflare Wrangler guarda en el Mac un registro por comando en ~/Library/Preferences/.wrangler/logs y no los borra.
    func registrosDeWrangler(_ c: Contexto) -> [Elemento] {
        let carpeta = Rutas.enHome("Library/Preferences/.wrangler/logs").path
        let limite = Int(Date().timeIntervalSince1970) - 86400
        let viejos = Self.nombres(en: carpeta).filter { $0.hasSuffix(".log") }.map { carpeta + "/" + $0 }
            .filter { Self.tipo($0) == S_IFREG && Self.segundosDeCambio($0) < limite }
        guard !viejos.isEmpty else { return [] }
        return [Elemento(
            nombre: "Registros de Wrangler (\(Formato.numero(viejos.count)))",
            detalle: "Un registro por cada comando de Cloudflare Wrangler (wrangler dev, deploy…), de hace más de un día. En el Mac los guarda en ~/Library/Preferences/.wrangler.",
            consecuencia: "Nada importante: solo se pierden registros de comandos que ya terminaron. Tu sesión y tu configuración de Wrangler no se tocan.",
            rutas: viejos.map { URL(fileURLWithPath: $0) }, tamanosRutas: viejos.map { Self.medida($0, c) },
            categoria: .registros, riesgo: .seguro, seleccionado: true,
            motivos: [.bien("doc.text.magnifyingglass", "Solo registros", "Nadie escribe en ellos desde hace más de un día.")],
            enUso: .proceso(nombre: "Wrangler", patron: "wrangler-dist/"), dueno: "Wrangler")]
    }

    // MARK: - Instaladores de Windows

    private static let extensionesDePaquete: Set<String> = ["app", "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary",
                                                            "fcpbundle", "logicx", "bundle", "framework", "pkg", "xcarchive"]

    /// .exe y .msi de más de 1 MB en Descargas y el Escritorio (y una carpeta más abajo) que no abres desde hace 7 días: en
    /// un Mac no se pueden ejecutar. Revisar: puede que lo guardes para un PC o una máquina virtual.
    func instaladoresDeWindows(_ c: Contexto) -> [Elemento] {
        let semana = Date().addingTimeInterval(-7 * 86400)
        let normalizados = c.apps.nombres
        let conWindows = [("parallelsdesktop", "Parallels Desktop"), ("vmwarefusion", "VMware Fusion"), ("crossover", "CrossOver"),
                          ("utm", "UTM"), ("whisky", "Whisky")].filter { normalizados.contains($0.0) }.map(\.1)
            + (c.apps.comandos.contains("wine") || c.apps.comandos.contains("wine64") ? ["Wine"] : [])
        var r: [Elemento] = []
        for base in ["Downloads", "Desktop"].map({ Rutas.enHome($0).path }) {
            var pendientes = [(base, 0)]
            var vistos = 0
            while let (carpeta, nivel) = pendientes.popLast(), vistos < 5000 {
                for n in Self.nombres(en: carpeta) where !n.hasPrefix(".") {
                    vistos += 1
                    let ruta = carpeta + "/" + n
                    var st = stat()
                    guard lstat(ruta, &st) == 0 else { continue }
                    let ext = (n as NSString).pathExtension.lowercased()
                    if (st.st_mode & S_IFMT) == S_IFDIR {
                        if nivel < 1 && !Self.extensionesDePaquete.contains(ext) { pendientes.append((ruta, nivel + 1)) }
                        continue
                    }
                    guard (st.st_mode & S_IFMT) == S_IFREG, ext == "exe" || ext == "msi", st.st_size > 1_000_000 else { continue }
                    let u = URL(fileURLWithPath: ruta)
                    let usado = Fechas.ultimoUsoArchivo(u)
                    guard (usado ?? .distantPast) < semana, Self.repoQueLaContiene(ruta, c) == nil else { continue }
                    var motivos: [Motivo] = [.info("pc", "Para Windows", "Es un \(ext == "msi" ? "instalador" : "programa") de Windows: macOS no puede abrirlo.")]
                    if !conWindows.isEmpty {
                        motivos.append(.info("macwindow", "Tienes \(Formato.lista(conWindows))",
                                             "Con \(Formato.lista(conWindows)) sí se puede usar: revisa si lo guardas para eso."))
                    }
                    r.append(Elemento(
                        nombre: n,
                        detalle: "Instalador de Windows (.\(ext)) en \(Formato.rutaCorta(carpeta)). No lo abres desde \(Formato.haceCuanto(usado).lowercased()).",
                        consecuencia: "Si lo guardabas para instalarlo en un PC o en una máquina virtual con Windows, tendrás que descargarlo otra vez. Va a la Papelera.",
                        rutas: [u], ultimoUso: usado, categoria: .instaladores, riesgo: .revisar, motivos: motivos))
                }
            }
        }
        return r
    }

    // MARK: - Orden en tu carpeta

    /// Lo que se borra de un zip hecho en un Mac que se descomprimió con otra herramienta: el disco del Mac guarda esos
    /// metadatos por su cuenta. En FAT, exFAT o SMB los «._» sí son los metadatos del archivo.
    private static func discoConAtributos(_ ruta: String) -> Bool {
        var s = statfs()
        guard statfs(ruta, &s) == 0 else { return false }
        let tipo = withUnsafeBytes(of: s.f_fstypename) { b in String(decoding: b.prefix { $0 != 0 }, as: UTF8.self) }
        return tipo == "apfs" || tipo == "hfs"
    }

    /// Un «._nombre» con la firma de AppleDouble (00 05 16 07) que solo guarda metadatos: se lee su cabecera (26 bytes y
    /// 12 por entrada). Si lleva resource fork (la entrada 2, con datos), no: en las fuentes clásicas, los iconos y los
    /// archivos antiguos de Mac ese es el contenido, y si el zip se descomprimió con otra herramienta es la única copia.
    private static func esAppleDoubleSinRecursos(_ ruta: String) -> Bool {
        guard tipo(ruta) == S_IFREG, let f = FileHandle(forReadingAtPath: ruta) else { return false }
        defer { try? f.close() }
        guard let cabecera = try? f.read(upToCount: 26).map(Array.init), cabecera.count == 26,
              Array(cabecera.prefix(4)) == [0x00, 0x05, 0x16, 0x07] else { return false }
        let n = Int(cabecera[24]) << 8 | Int(cabecera[25])
        guard n <= 64 else { return false }
        guard n > 0 else { return true }
        guard let entradas = try? f.read(upToCount: 12 * n).map(Array.init), entradas.count == 12 * n else { return false }
        func numero(_ i: Int) -> UInt32 { entradas[i...i + 3].reduce(0) { $0 << 8 | UInt32($1) } }
        return !(0..<n).contains { i in numero(i * 12) == 2 && numero(i * 12 + 8) > 0 }
    }

    /// Una carpeta __MACOSX con solo «._…» sin resource fork y .DS_Store dentro (lo que deja un zip): como mucho 10.000
    /// entradas.
    private static func soloAppleDouble(_ carpeta: String) -> Bool {
        guard let e = FileManager.default.enumerator(atPath: carpeta) else { return false }
        var vistos = 0
        while let rel = e.nextObject() as? String {
            vistos += 1
            if vistos > 10_000 { return false }
            let n = Rutas.nombre(rel)
            let t = tipo(carpeta + "/" + rel)
            if t == S_IFDIR { continue }
            if n == ".DS_Store" && t == S_IFREG { continue }
            if !n.hasPrefix("._") || !esAppleDoubleSinRecursos(carpeta + "/" + rel) { return false }
        }
        return true
    }

    /// Carpetas que sincroniza un cliente que no usa File Provider (Nextcloud, Dropbox clásico, Synology Drive…): borrar
    /// ahí se propaga al servidor, y en un NAS los «._» son los metadatos de verdad.
    private static let carpetasSincronizadas = ["dropbox", "nextcloud", "owncloud", "synologydrive", "synology drive", "pcloud",
                                                "mega", "google drive", "googledrive", "onedrive", "box", "box sync", "seafile",
                                                "sync", "resilio sync", "tresorit", "icedrive", "proton drive", "filen", "koofr"]

    /// La primera carpeta de la ruta, dentro de tu carpeta, es de una de esas.
    private static func enCarpetaSincronizada(_ ruta: String) -> Bool {
        let home = Rutas.home.path + "/"
        guard ruta.hasPrefix(home), let primera = ruta.dropFirst(home.count).split(separator: "/").first?.lowercased() else { return false }
        return carpetasSincronizadas.contains { primera == $0 || primera.hasPrefix($0 + " ") || primera.hasPrefix($0 + "-") }
    }

    /// Donde no se toca nada de esto: lo que sincroniza una nube y los datos de las apps (contenedores, correo, mensajes).
    private static let zonasSinOrden = ["/Library/Mobile Documents/", "/Library/CloudStorage/", "/Library/Containers/",
                                        "/Library/Group Containers/", "/Library/Mail/", "/Library/Messages/"]
    private static let extensionesLatex = [".synctex.gz", ".fdb_latexmk", ".aux", ".toc", ".lof", ".lot", ".out", ".bbl", ".blg", ".fls"]

    /// Seguro y en un solo elemento: «._nombre» (AppleDouble) junto a un «nombre» que existe y carpetas __MACOSX, enlaces
    /// rotos de ~/.local/bin y ~/bin, intermedios de LaTeX con su .tex al lado y la caché y los temporales de Wrangler de
    /// tus proyectos. Con más de 1 h sin cambios (puede que algo los esté escribiendo).
    func restosSueltos(_ c: Contexto, cubierta: @escaping (String) -> Bool) -> Elemento? {
        let home = Rutas.home.path
        let hace1h = Int(Date().timeIntervalSince1970) - 3600
        func fuera(_ r: String) -> Bool {
            cubierta(r) || Self.zonasSinOrden.contains { r.contains($0) } || Self.segundosDeCambio(r) >= hace1h
        }
        // Los «._» y __MACOSX solo en un disco que guarda los metadatos por su cuenta (mirado por carpeta), fuera de los
        // repositorios (pueden estar versionados, como datos de una prueba) y de las carpetas que sincroniza otro cliente.
        var conAtributos: [String: Bool] = [:]
        func sePuedeOrdenar(_ r: String) -> Bool {
            let carpeta = Rutas.padre(r)
            let disco = conAtributos[carpeta] ?? Self.discoConAtributos(carpeta)
            conAtributos[carpeta] = disco
            return disco && !Self.enCarpetaSincronizada(r) && Self.repoQueLaContiene(r, c) == nil
        }
        var dobles: [String] = []
        let macosx = c.indice.carpetasMacOSX.filter { !fuera($0) && sePuedeOrdenar($0) && Self.soloAppleDouble($0) }
        for r in c.indice.appleDouble where !fuera(r) && !r.contains("/__MACOSX/") && sePuedeOrdenar(r) {
            // Dentro de una biblioteca (Fotos, Música…) lo gestiona su app.
            if r.split(separator: "/").contains(where: { Self.extensionesDePaquete.contains(($0 as NSString).pathExtension.lowercased()) }) { continue }
            // Su archivo tiene que estar al lado y no vacío (si está vacío, el contenido puede estar en el «._»).
            let original = Rutas.padre(r) + "/" + Rutas.nombre(r).dropFirst(2)
            var st = stat()
            guard lstat(original, &st) == 0 else { continue }
            let tipoOriginal = st.st_mode & S_IFMT
            guard tipoOriginal == S_IFDIR || (tipoOriginal == S_IFREG && st.st_size > 0) else { continue }
            if Self.esAppleDoubleSinRecursos(r) { dobles.append(r) }
        }
        // (Los enlaces rotos de ~/.local/bin no se ofrecen: la limpieza se salta lo que no existe, y un enlace roto lo parece.)
        var latex: [String] = []
        var conBib: [String: Bool] = [:]
        for r in c.indice.intermediosLatex where !fuera(r) {
            let nombre = Rutas.nombre(r)
            guard let ext = Self.extensionesLatex.first(where: { nombre.lowercased().hasSuffix($0) }) else { continue }
            let base = String(nombre.dropLast(ext.count))
            let carpeta = Rutas.padre(r)
            guard !base.isEmpty, Self.tipo(carpeta + "/" + base + ".tex") == S_IFREG else { continue }
            // Sin el .bib, el .bbl es lo único que queda de la bibliografía: no se toca.
            if ext == ".bbl" {
                let hay = conBib[carpeta] ?? Self.nombres(en: carpeta).contains { $0.lowercased().hasSuffix(".bib") }
                conBib[carpeta] = hay
                if !hay { continue }
            }
            latex.append(r)
        }
        let latexEnMarcha = c.procesos.quienUsa(EnUso.programas(nombre: "LaTeX", ejecutables: ["latexmk", "pdflatex", "xelatex", "lualatex",
                                                                                               "tectonic", "bibtex", "biber"])) != nil
        if latexEnMarcha { latex = [] }
        var wrangler: [String] = []
        if !Self.wranglerEnMarcha(c) {
            for w in c.indice.carpetasWrangler where !w.hasPrefix(home + "/Library/") && !cubierta(w) {
                wrangler += ["cache", "tmp"].map { w + "/" + $0 }.filter { Self.tipo($0) == S_IFDIR && !fuera($0) }
            }
        }
        let rutas = dobles + macosx + latex + wrangler
        guard !rutas.isEmpty else { return nil }
        func cuantos(_ n: Int, _ uno: String, _ varios: String) -> String? { n == 0 ? nil : "\(Formato.numero(n)) \(n == 1 ? uno : varios)" }
        let partes = [cuantos(dobles.count, "archivo «._» de un zip", "archivos «._» de zips"),
                      cuantos(macosx.count, "carpeta __MACOSX", "carpetas __MACOSX"),
                      cuantos(latex.count, "intermedio de LaTeX", "intermedios de LaTeX"),
                      cuantos(wrangler.count, "caché de Wrangler", "cachés y temporales de Wrangler")].compactMap { $0 }
        return Elemento(
            nombre: "Restos sueltos en tus carpetas",
            detalle: "\(Formato.lista(partes)).",
            consecuencia: "Nada que necesites: los «._» y __MACOSX son los metadatos que dejó un zip junto a tus archivos (tus archivos siguen ahí; solo se pierden las etiquetas o comentarios del Finder que llevara el zip, si los tenía), y los intermedios de LaTeX y la caché de Wrangler se vuelven a crear al compilar.",
            rutas: rutas.map { URL(fileURLWithPath: $0) }, tamanosRutas: rutas.map { Self.medida($0, c) },
            categoria: .olvidados, riesgo: .seguro, seleccionado: true,
            motivos: [.bien("sparkles", "Se rehacen o sobran",
                            "Los «._» tienen la firma de AppleDouble, no guardan ningún resource fork (el contenido de las fuentes e iconos antiguos) y su archivo está al lado; cada intermedio de LaTeX tiene su .tex con el mismo nombre. Nada cambió en la última hora, y nada está en un repositorio ni en una carpeta que sincroniza otro programa.")],
            enUso: latex.isEmpty ? nil : .programas(nombre: "LaTeX", ejecutables: ["latexmk", "pdflatex", "xelatex", "lualatex", "tectonic", "bibtex", "biber"]),
            dueno: "Tus carpetas")
    }

    static let prefijosDeCopia = ["respaldo-", "respaldo_", "respaldo ", "backup-", "backup_", "backup ", "copia de "]
    static let sufijosDeCopia = ["-old", "_old", " old", "-original", "_original", " original"]

    /// «respaldo-web», «backup_2024», «Copia de informe», «sitio-old», «app-original»: el nombre de una copia hecha a mano.
    /// (El índice lo pregunta por cada carpeta de tus carpetas: solo mira el nombre.)
    static func pareceCopiaAMano(_ nombre: String) -> Bool {
        let n = nombre.lowercased()
        return prefijosDeCopia.contains { n.hasPrefix($0) && n.count > $0.count } || sufijosDeCopia.contains { n.hasSuffix($0) && n.count > $0.count }
    }

    /// El nombre del original de una copia hecha a mano: «respaldo-susan-original» → «susan».
    private static func originalDeCopia(_ nombre: String) -> String {
        var n = nombre
        if let p = prefijosDeCopia.first(where: { n.lowercased().hasPrefix($0) }) { n = String(n.dropFirst(p.count)) }
        while let s = sufijosDeCopia.first(where: { n.lowercased().hasSuffix($0) && n.count > $0.count }) { n = String(n.dropLast(s.count)) }
        return n
    }

    private static let marcasDeProyecto = [".git", "package.json", "Package.swift", "build.gradle", "build.gradle.kts", "settings.gradle",
                                           "settings.gradle.kts", "pyproject.toml", "Cargo.toml", "go.mod", "pubspec.yaml", "composer.json",
                                           "Gemfile", "pom.xml", "wrangler.toml", "wrangler.json", "wrangler.jsonc", "vercel.json", "index.html"]

    private static func esProyecto(_ carpeta: String) -> Bool { marcasDeProyecto.contains { Rutas.existe(carpeta + "/" + $0) } }

    /// Carpetas que llamaste como una copia («respaldo-…», «backup-…», «Copia de …», «…-old», «…-original») junto a un
    /// proyecto (al lado está el original y es un proyecto, o la copia lo es, o su carpeta lo es), sin cambios en 14 días
    /// o más. Revisar, todas juntas: pueden ser la única versión de algo.
    func copiasHechasAMano(_ c: Contexto, cubierta: (String) -> Bool) -> Elemento? {
        var copias: [String] = []
        var proyectos = Set<String>()
        var cambios: [Date] = []
        for ruta in c.indice.copiasAMano.sorted() where !cubierta(ruta) {
            let nombre = Rutas.nombre(ruta)
            guard !nombre.hasPrefix("."), Self.tipo(ruta) == S_IFDIR else { continue }
            // Nunca ofrecer subcarpetas dentro de un repositorio git activo ni en carpetas sincronizadas con la nube.
            guard Self.repoQueLaContiene(ruta, c) == nil, !Self.enCarpetaSincronizada(ruta),
                  Self.tipo(ruta + "/.git") == nil else { continue }
            // Una dentro de otra ya va con la de fuera.
            if copias.contains(where: { ruta.hasPrefix($0 + "/") }) { continue }
            let padre = Rutas.padre(ruta)
            let original = Self.originalDeCopia(nombre).lowercased()
            let hermano = Self.nombres(en: padre).first { $0.lowercased() == original && $0 != nombre }.map { padre + "/" + $0 }
            let junto: String?
            if let hermano, Self.tipo(hermano) == S_IFDIR, Self.esProyecto(hermano) || Self.esProyecto(ruta) {
                junto = Rutas.nombre(hermano)
            } else if Self.esProyecto(padre) {
                junto = Rutas.nombre(padre)
            } else {
                junto = nil
            }
            guard let junto, let cambio = Self.ultimoCambioDentro(ruta, c), Date().timeIntervalSince(cambio) >= 14 * 86400 else { continue }
            copias.append(ruta)
            proyectos.insert(junto)
            cambios.append(cambio)
        }
        guard !copias.isEmpty else { return nil }
        return Elemento(
            nombre: "Copias hechas a mano junto a tus proyectos (\(copias.count))",
            detalle: "Carpetas que llamaste como una copia de seguridad (\(Formato.listaCorta(copias.map { Rutas.nombre($0) }, maximo: 4))) al lado de \(Formato.listaCorta(proyectos.sorted())).",
            consecuencia: "Se borran esas copias. Si alguna es la única versión de algo (un cambio que deshiciste después), la pierdes: ábrelas antes de decidir. Van a la Papelera.",
            rutas: copias.map { URL(fileURLWithPath: $0) }, tamanosRutas: copias.map { Self.medida($0, c) }, ultimoUso: cambios.max(),
            categoria: .olvidados, riesgo: .revisar,
            motivos: [.info("externaldrive.badge.timemachine", "Copias antiguas",
                            "Nada cambió dentro desde \(Formato.haceCuanto(cambios.max()).lowercased()). Son tus archivos: decide tú si aún te sirven.")],
            enUso: .rutas(nombre: "Las copias", raiz: copias[0]))
    }

    /// Las copias de la biblioteca de Música y de TV que macOS guarda al actualizar o migrar (Previous Libraries), cuando la
    /// biblioteca que usas está al lado. Revisar.
    func bibliotecasAnteriores(_ c: Contexto, cubierta: (String) -> Bool) -> Elemento? {
        let pares = [("Music/Music/Previous Libraries.localized", "Music/Music/Music Library.musiclibrary", "Música"),
                     ("Movies/TV/Previous Libraries.localized", "Movies/TV/TV Library.tvlibrary", "TV")]
        var rutas: [URL] = []
        var apps: [String] = []
        for (anterior, actual, app) in pares {
            let a = Rutas.enHome(anterior)
            guard Self.tipo(a.path) == S_IFDIR, Rutas.existe(Rutas.enHome(actual)), !cubierta(a.path),
                  Self.nombres(en: a.path).contains(where: { !$0.hasPrefix(".") }) else { continue }
            rutas.append(a)
            apps.append(app)
        }
        guard !rutas.isEmpty else { return nil }
        return Elemento(
            nombre: "Bibliotecas anteriores de \(Formato.lista(apps))",
            detalle: "Copias de tu biblioteca que macOS guardó al actualizar o migrar (Previous Libraries). La biblioteca que usas está al lado.",
            consecuencia: "Pierdes la copia anterior: si a la biblioteca actual le faltara algo (listas, valoraciones, contadores), ya no podrías sacarlo de aquí. Tus canciones y vídeos están en su carpeta de medios y no se tocan.",
            rutas: rutas, tamanosRutas: rutas.map { Self.medida($0.path, c) }, categoria: .olvidados, riesgo: .revisar,
            motivos: [.info("music.note.list", "Copia de la biblioteca", "Al lado está la biblioteca que usa \(Formato.lista(apps)) ahora.")],
            enUso: .app(nombre: Formato.lista(apps), claves: ["com.apple.Music", "com.apple.TV"]), dueno: "macOS")
    }
}
