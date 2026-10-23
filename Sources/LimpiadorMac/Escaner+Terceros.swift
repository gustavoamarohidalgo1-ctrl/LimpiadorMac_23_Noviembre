import AppKit
import Foundation

// Apps de terceros (Office, WhatsApp, Zoom, Teams, Postgres.app…), datos de Apple que no son una caché simple (Mail,
// Podcasts, los vídeos de fondo, los temporales de sus contenedores, lo que dejan GarageBand, Logic y MainStage en
// /Library, los reportes de fallos de todo el Mac) y lo que queda en /var/folders/…/C de programas que solo guardan ahí
// sus sombreadores o que ya no están. Lo que ya ofrece otra regla no se repite aquí.

extension Rutas {
    /// La raíz de las carpetas del sistema que miran algunas reglas (/Library, /Applications): «» en tu Mac. En una casa de
    /// prueba, la carpeta de LIMPIADOR_RAIZ (con su ruta real) y, si no se da, ninguna: nunca las de verdad.
    static let raizDelSistema: String? = {
        guard casaDePrueba else { return "" }
        guard let valor = ProcessInfo.processInfo.environment["LIMPIADOR_RAIZ"], let real = realpath(valor, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }()
}

extension Seguridad {
    /// Lo único de fuera de tu carpeta (aparte de tus temporales y tus apps) que se puede borrar: lo que tu usuario puede
    /// borrar sin contraseña y una regla ofrece a propósito. Los reportes de fallos sueltos de /Library/Logs/DiagnosticReports
    /// (tu usuario es del grupo que los gestiona) y lo que hay dentro de las carpetas de sonidos y lecciones de GarageBand,
    /// Logic y MainStage de /Library (eres administrador y el grupo admin puede escribir en ellas). Nunca esas carpetas
    /// enteras ni nada que no puedas escribir. `p` es una ruta real.
    static func esDelSistemaBorrable(_ p: String) -> Bool {
        guard let raiz = Rutas.raizDelSistema else { return false }
        let padre = Rutas.padre(p)
        var st = stat()
        var delPadre = stat()
        guard lstat(p, &st) == 0, lstat(padre, &delPadre) == 0, access(padre, W_OK) == 0 else { return false }
        // En una carpeta con el bit «sticky» (como /tmp) solo su dueño puede mover algo.
        if delPadre.st_mode & S_ISVTX != 0 && st.st_uid != getuid() { return false }
        let tipo = st.st_mode & S_IFMT
        if padre == raiz + "/Library/Logs/DiagnosticReports" {
            return tipo == S_IFREG && Escaner.esReporteDeFallos(Rutas.nombre(p))
        }
        if Escaner.contenedoresDeSonidos(raiz).contains(padre) {
            return tipo == S_IFREG || (tipo == S_IFDIR && access(p, W_OK) == 0)
        }
        return tipo == S_IFDIR && access(p, W_OK) == 0 && Escaner.carpetasDeSonidos(raiz).contains(p)
    }
}

extension Escaner {
    // MARK: - Ganchos de generar()

    /// «Cachés de aplicaciones»: el catálogo de plantillas de Office repetido, sus fuentes en la nube, los avatares 3D de
    /// Zoom, la caché de imágenes de Mail, los episodios de Podcasts y los temporales viejos de los contenedores de Apple.
    /// Además deja las notas de lo que solo se informa (el servidor de PostgreSQL que no usas, los medios de WhatsApp).
    func cachesDeTercerosYApple(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        if let el = catalogoDeOfficeRepetido(c) { r.append(el) }
        if let el = fuentesEnLaNubeDeOffice(c) { r.append(el) }
        if let el = avataresDeZoom(c) { r.append(el) }
        if let el = imagenesDeMail(c) { r.append(el) }
        if let el = episodiosDePodcasts(c) { r.append(el) }
        r += temporalesDeContenedoresDeApple(c)
        notaDeServidoresQuietos(c)
        notaDeMediosDeWhatsApp(c)
        return r
    }

    /// «Temporales del sistema»: los sombreadores de los programas que solo guardan eso en /var/folders/…/C y las cachés de
    /// apps que ya no están. `ofrecidas` es lo que ya ofrecen las demás reglas de la categoría: no se repite.
    func temporalesDeTerceros(_ c: Contexto, ofrecidas: [Elemento]) -> [Elemento] {
        let tomadas = Set(ofrecidas.filter { $0.accion == .borrar }.flatMap { $0.rutas.map(\.path) })
        var r: [Elemento] = []
        for raiz in Rutas.temporalesDelSistema where raiz.hasSuffix("/C") {
            let todos = Rutas.hijos(URL(fileURLWithPath: raiz))
            // La caché de una app opcional de Apple que ya no está (GarageBand…) la ofrece «Restos de apps borradas».
            let deRestos = Self.deAppsDeAppleDesinstaladas(todos.map(\.lastPathComponent), c)
            let hijos = todos.filter { h in
                let n = h.lastPathComponent
                return !n.hasPrefix(".") && n != "TemporaryItems" && !Self.propios.contains(n) && !deRestos.contains(n) && Terceros.carpetaPropia(h)
                    && !tomadas.contains(h.path) && !Totales.dentroDe(h.path, tomadas) && !tomadas.contains { $0.hasPrefix(h.path + "/") }
            }
            let graficos = hijos.filter { !["com.apple.metal", "com.apple.metalfe"].contains($0.lastPathComponent.lowercased()) && Self.soloSombreadores($0) }
            r += sombreadoresDeProgramas(graficos, c)
            let deGraficos = Set(graficos.map(\.path))
            if let el = cachesDeAppsQueNoEstan(hijos.filter { !deGraficos.contains($0.path) }, c) { r.append(el) }
        }
        return r
    }

    /// «Restos de apps borradas»: lo que dejó Microsoft Teams y los sonidos y lecciones de GarageBand, Logic y MainStage
    /// en /Library.
    func restosDeTercerosYApple(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        for producto in Self.productosQueDejanRestos {
            if let el = restosDeProducto(producto, c) { r.append(el) }
        }
        if let el = sonidosDeAppsDeApple(c) { r.append(el) }
        return r
    }

    /// «Registros y fallos»: los reportes de fallos de todo el Mac (/Library/Logs/DiagnosticReports) y los informes de cierre
    /// que guardan algunas apps aisladas (AppExit).
    func registrosDeTerceros(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        if let el = reportesDeFallosDelSistema(c) { r.append(el) }
        r += informesDeCierre(c)
        return r
    }

    // MARK: - Office

    private static let idsDeAppsDeOffice = ["com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.microsoft.Outlook",
                                      "com.microsoft.onenote.mac"]
    private static let usoDeLasAppsDeOffice = EnUso.app(nombre: "Office", claves: idsDeAppsDeOffice + ["Microsoft Word", "Microsoft Excel",
                                                                                    "Microsoft PowerPoint", "Microsoft Outlook", "Microsoft OneNote"])

    /// Las carpetas DTS (el catálogo de plantillas y temas) de las apps de Office instaladas, sin seguir enlaces.
    private static func carpetasDTS(_ c: Contexto) -> [URL] {
        guard c.accesoTotal else { return [] }
        return idsDeAppsDeOffice.compactMap { id in
            guard c.apps.estaInstalado(carpeta: id) else { return nil }
            let k = Rutas.enHome("Library/Containers/\(id)")
            let u = k.appendingPathComponent("Data/Library/Application Support/Microsoft/Office/16.0/DTS")
            return Terceros.carpetaPropia(u) && Terceros.estaDentro(u, de: k) ? u : nil
        }
    }

    private static let patronPrefijoDeCatalogo = try! NSRegularExpression(pattern: #"^\{[0-9A-Fa-f-]{8,}\}"#)

    /// Las carpetas del catálogo de plantillas de Office (DTS/<idioma>{GUID}) que son copia de otra más nueva del mismo
    /// idioma: cada archivo suyo («{GUID}nombre») está en la nueva con el mismo nombre (sin el {GUID}) y el mismo tamaño.
    /// Office vuelve a bajar el catálogo entero en otra carpeta y deja la vieja. Nunca la más nueva (por fecha de creación),
    /// ni una con subcarpetas o enlaces, ni si la nueva cambió en la última hora (puede estar bajándose).
    static func catalogosDeOfficeRepetidos(en dts: URL) -> [URL] {
        var porIdioma: [String: [(url: URL, creada: Int)]] = [:]
        for h in Rutas.hijos(dts) {
            let n = h.lastPathComponent
            var st = stat()
            guard let llave = n.firstIndex(of: "{"), llave > n.startIndex, n.hasSuffix("}"),
                  lstat(h.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { continue }
            porIdioma[String(n[..<llave]), default: []].append((h, st.st_birthtimespec.tv_sec))
        }
        let haceUnaHora = Int(Date().timeIntervalSince1970) - 3600
        var r: [URL] = []
        for lista in porIdioma.values where lista.count >= 2 {
            let orden = lista.sorted { $0.creada < $1.creada }
            guard let nueva = orden.last, let deLaNueva = archivosDeCatalogo(nueva.url), !deLaNueva.archivos.isEmpty,
                  deLaNueva.ultimoCambio < haceUnaHora else { continue }
            for vieja in orden.dropLast() {
                guard let suyos = archivosDeCatalogo(vieja.url), !suyos.archivos.isEmpty,
                      suyos.archivos.allSatisfy({ deLaNueva.archivos[$0.key] == $0.value }) else { continue }
                r.append(vieja.url)
            }
        }
        return r.sorted { $0.path < $1.path }
    }

    /// Lo que hay en una carpeta del catálogo: nombre sin el {GUID} → tamaño, y su último cambio. nil si hay algo que no es
    /// un archivo normal (una carpeta, un enlace) o dos archivos que quedan con el mismo nombre y distinto tamaño.
    private static func archivosDeCatalogo(_ carpeta: URL) -> (archivos: [String: Int64], ultimoCambio: Int)? {
        var r: [String: Int64] = [:]
        var st = stat()
        guard lstat(carpeta.path, &st) == 0 else { return nil }
        var ultimo = st.st_mtimespec.tv_sec
        for n in (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? [] where !n.hasPrefix(".") {
            guard lstat(carpeta.path + "/" + n, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
            ultimo = max(ultimo, st.st_mtimespec.tv_sec)
            let rango = NSRange(n.startIndex..., in: n)
            let clave = patronPrefijoDeCatalogo.stringByReplacingMatches(in: n, range: rango, withTemplate: "")
            if let ya = r[clave], ya != Int64(st.st_size) { return nil }
            r[clave] = Int64(st.st_size)
        }
        return (r, ultimo)
    }

    /// Las carpetas DTS sin los catálogos repetidos (que ofrece `catalogoDeOfficeRepetido`): la carpeta entera si no hay
    /// ninguno; si no, sus carpetas de idioma menos esas.
    static func sinCatalogosRepetidos(_ carpetas: [URL]) -> [URL] {
        carpetas.flatMap { d -> [URL] in
            let repetidos = Set(catalogosDeOfficeRepetidos(en: d).map(\.path))
            guard !repetidos.isEmpty else { return [d] }
            return Rutas.hijos(d).filter { !repetidos.contains($0.path) && !Terceros.esEnlaceOSuelto($0) }
        }
    }

    /// El catálogo de plantillas de Office descargado dos veces: la copia vieja se ofrece en el modo normal, porque no hay
    /// que descargar nada (todo está en la nueva). Lo demás del catálogo sigue solo en «Liberar al máximo».
    private func catalogoDeOfficeRepetido(_ c: Contexto) -> Elemento? {
        let repetidos = Self.carpetasDTS(c).flatMap { Self.catalogosDeOfficeRepetidos(en: $0) }
        guard !repetidos.isEmpty else { return nil }
        let tamanos = repetidos.map { Terceros.ocupa($0, c) }
        let apps = Array(Set(repetidos.compactMap { u -> String? in
            Self.idsDeAppsDeOffice.first { u.path.contains("/Containers/\($0)/") }.map { c.apps.nombreApp(para: $0) ?? Rutas.nombre($0) }
        })).sorted()
        return Elemento(
            nombre: "Catálogo de plantillas de Office repetido",
            detalle: "Copias viejas del catálogo de plantillas y temas de \(Formato.lista(apps)): Office lo volvió a descargar en otra carpeta y dejó esta.",
            consecuencia: "Nada: Office usa la copia nueva, que tiene los mismos archivos. Si alguna vez buscara esta, la vuelve a descargar.",
            rutas: repetidos, tamanosRutas: tamanos, ultimoUso: repetidos.compactMap { Terceros.ultimoCambio($0, c) }.max(),
            categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
            motivos: [.bien("doc.on.doc", "Copia de otra más nueva",
                            "Cada archivo de esta carpeta está también en la carpeta nueva del mismo idioma, con el mismo nombre y el mismo tamaño: no hay que descargar nada.")],
            enUso: Self.usoDeLasAppsDeOffice, dueno: "Microsoft Office")
    }

    /// Las fuentes que Office descarga de internet cuando un documento las usa (FontCache/<n>/CloudFonts): no salen de las
    /// fuentes instaladas, así que no van con las demás cachés de fuentes y solo se marcan en «Liberar al máximo».
    private func fuentesEnLaNubeDeOffice(_ c: Contexto) -> Elemento? {
        guard c.accesoTotal else { return nil }
        var cachesDeFuentes: [(base: URL, fuentes: URL)] = []
        let grupo = Rutas.enHome("Library/Group Containers/UBF8T346G9.Office")
        if c.apps.estaInstalado(carpeta: grupo.lastPathComponent) { cachesDeFuentes.append((grupo, grupo.appendingPathComponent("FontCache"))) }
        for id in Self.idsDeAppsDeOffice where c.apps.estaInstalado(carpeta: id) {
            let k = Rutas.enHome("Library/Containers/\(id)")
            cachesDeFuentes.append((k, k.appendingPathComponent("Data/Library/Application Support/Microsoft/FontCache")))
        }
        var rutas: [URL] = []
        for (base, fuentes) in cachesDeFuentes where Terceros.carpetaPropia(fuentes) && Terceros.estaDentro(fuentes, de: base) {
            for v in Rutas.hijos(fuentes) where Terceros.carpetaPropia(v) {
                let nube = v.appendingPathComponent("CloudFonts")
                if Terceros.carpetaPropia(nube) && !Rutas.hijos(nube).isEmpty { rutas.append(nube) }
            }
        }
        guard !rutas.isEmpty else { return nil }
        let tamanos = rutas.map { Terceros.ocupa($0, c) }
        return Elemento(
            nombre: "Fuentes que Office descargó de internet",
            detalle: "Fuentes que Office bajó porque algún documento las usa y no las tienes instaladas (Aptos, Segoe UI…).",
            consecuencia: "Office las vuelve a descargar cuando abras un documento que las use (necesita internet); sin conexión, ese documento se ve con otra fuente hasta entonces.",
            rutas: rutas, tamanosRutas: tamanos, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
            motivos: [.info("arrow.down.circle.fill", "Se vuelven a descargar",
                            "No se pierde nada, pero volver a bajarlas necesita internet: solo las marco en «Liberar al máximo».")],
            enUso: Self.usoDeLasAppsDeOffice, dueno: "Microsoft Office", nivel: .maximo, costes: [.descarga(bytes: tamanos.reduce(0, +))])
    }

    // MARK: - Zoom

    private static let patronHash = try! NSRegularExpression(pattern: #"^[0-9a-fA-F]{64}$"#)

    /// Las piezas de los avatares 3D que Zoom descarga (data/Custom3DAvatarElementV2): cientos de archivos con nombre de
    /// hash. `recursosDeZoom` las deja fuera porque su nombre lleva «custom»: aquí se ofrecen solo si todo lo de dentro son
    /// archivos con nombre de hash (64 cifras hexadecimales), sin subcarpetas. Tu avatar (3dCustomAvatar.enc.db), tus
    /// fondos (VirtualBkgnd_Custom) y tu cuenta no se tocan.
    private func avataresDeZoom(_ c: Contexto) -> Elemento? {
        let zoom = Rutas.enHome("Library/Application Support/zoom.us")
        guard Terceros.carpetaPropia(zoom), c.apps.estaInstalado(carpeta: zoom.lastPathComponent) else { return nil }
        let piezas = zoom.appendingPathComponent("data/Custom3DAvatarElementV2")
        guard Terceros.carpetaPropia(piezas), Terceros.estaDentro(piezas, de: zoom) else { return nil }
        let nombres = (try? FileManager.default.contentsOfDirectory(atPath: piezas.path)) ?? []
        guard !nombres.isEmpty, nombres.allSatisfy({ n in
            Self.patronHash.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil && Terceros.archivoPropio(piezas.path + "/" + n) != nil
        }) else { return nil }
        return Elemento(
            nombre: "Piezas de avatares 3D de Zoom",
            detalle: "\(Formato.numero(nombres.count)) piezas (peinados, ropa, accesorios…) que Zoom descargó para sus avatares 3D.",
            consecuencia: "Zoom las vuelve a descargar cuando uses un avatar (necesita internet). Tu avatar, tus fondos y tus chats no se tocan.",
            rutas: [piezas], tamanosRutas: [Terceros.ocupa(piezas, c)], categoria: .cachesApps, riesgo: .revisar,
            motivos: [.info("arrow.down.circle.fill", "Se vuelven a descargar",
                            "Son recursos de Zoom, no tuyos: solo archivos con nombre de hash. Si usas avatares, Zoom los baja otra vez.")],
            enUso: .app(nombre: "Zoom", claves: ["us.zoom.xos", "zoom.us", "Zoom"]), dueno: "Zoom")
    }

    // MARK: - Datos de apps de Apple

    /// La caché de contenido remoto de Mail (~/Library/Mail/V*/MailData/RemoteContentURLCache): las imágenes de los correos
    /// que abres, guardadas por el sistema de descargas de macOS (Cache.db y fsCachedData). Es la única excepción a «nada
    /// de Mail»: ni los buzones, ni el índice, ni los adjuntos. Se espera a que Mail esté cerrada.
    private func imagenesDeMail(_ c: Contexto) -> Elemento? {
        guard c.accesoTotal else { return nil }
        let mail = Rutas.enHome("Library/Mail")
        var rutas: [URL] = []
        for v in Rutas.hijos(mail) where v.lastPathComponent.hasPrefix("V") && Int(v.lastPathComponent.dropFirst()) != nil {
            let cache = v.appendingPathComponent("MailData/RemoteContentURLCache")
            guard Terceros.carpetaPropia(cache), Terceros.estaDentro(cache, de: mail) else { continue }
            rutas += Rutas.hijos(cache).filter { !Terceros.esEnlaceOSuelto($0) }
        }
        guard !rutas.isEmpty else { return nil }
        return Elemento(
            nombre: "Caché de imágenes de Mail",
            detalle: "Las imágenes y el contenido remoto de los correos que abriste, que Mail guarda para no volver a bajarlos.",
            consecuencia: "Mail vuelve a descargar las imágenes de un correo cuando lo abras. Tus correos, sus adjuntos y tus buzones no se tocan.",
            rutas: rutas, tamanosRutas: rutas.map { Terceros.ocupa($0, c) }, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
            motivos: [.bien("photo.on.rectangle.angled", "Solo la caché de imágenes",
                            "Es la caché de descargas de Mail (la que usa macOS para todo lo que baja de internet). Del resto de Mail no se toca nada. Solo con Mail cerrada.")],
            enUso: .app(nombre: "Mail", claves: ["com.apple.mail", "Mail"]), dueno: "Mail")
    }

    private static let extensionesDeEpisodios: Set<String> = ["mp3", "m4a", "m4v", "mp4", "mov", "aac"]

    /// Los episodios que Podcasts descargó para escucharlos sin conexión: viven en «Library/Cache» (en singular) de su grupo,
    /// que `cachesDeGruposDeApple` no mira. Solo archivos de audio y vídeo, para revisar: son tuyos hasta que los escuches.
    private func episodiosDePodcasts(_ c: Contexto) -> Elemento? {
        guard c.accesoTotal else { return nil }
        var rutas: [URL] = []
        var tamanos: [Int64] = []
        for g in Rutas.hijos(Rutas.enHome("Library/Group Containers")) where g.lastPathComponent.lowercased().hasSuffix("groups.com.apple.podcasts") {
            let cache = g.appendingPathComponent("Library/Cache")
            guard Terceros.carpetaPropia(cache), Terceros.estaDentro(cache, de: g) else { continue }
            for (ruta, st) in Terceros.archivos(dentroDe: cache.path) where Self.extensionesDeEpisodios.contains((ruta as NSString).pathExtension.lowercased()) {
                rutas.append(URL(fileURLWithPath: ruta))
                tamanos.append(Int64(st.st_blocks) * 512)
            }
        }
        guard !rutas.isEmpty else { return nil }
        return Elemento(
            nombre: "Episodios descargados de Podcasts",
            detalle: "\(Formato.numero(rutas.count)) episodios que Podcasts descargó para escucharlos sin conexión.",
            consecuencia: "Dejarás de poder escucharlos sin conexión: Podcasts los vuelve a descargar si los pides (necesita internet).",
            rutas: rutas, tamanosRutas: tamanos, categoria: .cachesApps, riesgo: .revisar,
            motivos: [.info("headphones", "Para escuchar sin conexión",
                            "Se vuelven a descargar, pero los bajaste tú. En Podcasts › Ajustes, «Eliminar los episodios reproducidos» y el límite de descargas hacen esto solos.")],
            enUso: .app(nombre: "Podcasts", claves: ["com.apple.podcasts", "Podcasts"]), dueno: "Podcasts")
    }

    /// Temporales que dos tipos de servicios de Apple dejan en su Data/tmp y no borran. (a) Las extensiones de App Store
    /// (com.apple.AppleMediaServices…): descargas sueltas con nombre UUID y paquetes de interfaz (bundle/<UUID>.bundle) que
    /// solo tienen .js, .json y .css, con 7 días sin cambios. Seguro. (b) Los servicios que analizan tus fotos
    /// (mediaanalysisd, photoanalysisd): carpetas que solo tienen modelos extraídos (.espresso.*, model_info.json,
    /// index.json) y que nadie lee desde hace 30 días. Para revisar. Nunca TemporaryItems, .LINKS ni nada más.
    private func temporalesDeContenedoresDeApple(_ c: Contexto) -> [Elemento] {
        guard c.accesoTotal else { return [] }
        let hace7 = Date().addingTimeInterval(-7 * 86400)
        let hace30 = Date().addingTimeInterval(-30 * 86400)
        var ams: [(URL, Int64, Date)] = []
        var modelos: [(URL, Int64, Date)] = []
        for k in Rutas.hijos(Rutas.enHome("Library/Containers")) {
            let id = k.lastPathComponent.lowercased()
            let deAMS = id.hasPrefix("com.apple.applemediaservices")
            guard deAMS || ["com.apple.mediaanalysisd", "com.apple.photoanalysisd"].contains(id), Terceros.carpetaPropia(k) else { continue }
            let tmp = k.appendingPathComponent("Data/tmp")
            guard Terceros.carpetaPropia(tmp), Terceros.estaDentro(tmp, de: k) else { continue }
            if deAMS {
                for h in Rutas.hijos(tmp) {
                    var candidatos: [URL] = []
                    if Terceros.esUUID(h.lastPathComponent), Terceros.archivoPropio(h.path) != nil { candidatos = [h] }
                    else if h.lastPathComponent == "bundle", Terceros.carpetaPropia(h) {
                        candidatos = Rutas.hijos(h).filter { b in
                            b.pathExtension == "bundle" && Terceros.esUUID(b.deletingPathExtension().lastPathComponent) && Terceros.carpetaPropia(b)
                                && Terceros.soloArchivos(dentroDe: b.path) { ["js", "json", "css"].contains(($0 as NSString).pathExtension.lowercased()) }
                        }
                    }
                    for u in candidatos {
                        guard let f = Terceros.ultimoCambio(u, c), f < hace7, c.procesos.abiertos.hayAbierto(dentroDe: u.path) == nil else { continue }
                        ams.append((u, Terceros.ocupa(u, c), f))
                    }
                }
            } else {
                for h in Rutas.hijos(tmp) where !h.lastPathComponent.hasPrefix(".") && h.lastPathComponent != "TemporaryItems" && Terceros.carpetaPropia(h) {
                    var conModelo = false
                    let soloModelos = Terceros.soloArchivos(dentroDe: h.path) { n in
                        let l = n.lowercased()
                        if [".espresso.net", ".espresso.weights", ".espresso.shape"].contains(where: { l.hasSuffix($0) }) { conModelo = true; return true }
                        return l == "model_info.json" || l == "index.json"
                    }
                    guard soloModelos, conModelo, let leido = Terceros.ultimaLectura(dentroDe: h.path), leido < hace30,
                          c.procesos.abiertos.hayAbierto(dentroDe: h.path) == nil else { continue }
                    modelos.append((h, Terceros.ocupa(h, c), leido))
                }
            }
        }
        var r: [Elemento] = []
        if !ams.isEmpty {
            let ultimo = ams.map(\.2).max()
            r.append(Elemento(
                nombre: "Temporales de App Store",
                detalle: "Descargas sueltas y paquetes de interfaz (páginas en JavaScript y traducciones) que las extensiones de App Store dejaron en su carpeta temporal.",
                consecuencia: "Nada: la App Store los vuelve a descargar cuando los necesita.",
                rutas: ams.map(\.0), tamanosRutas: ams.map(\.1), ultimoUso: ultimo, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("arrow.down.circle", "Descargas viejas",
                                "Solo archivos con nombre UUID y paquetes que no tienen más que .js, .json y .css, con más de 7 días sin cambios y que nadie tiene abiertos. Nunca TemporaryItems ni nada con otro nombre.")],
                dueno: "App Store", cambioAnalizado: ultimo))
        }
        if !modelos.isEmpty {
            r.append(Elemento(
                nombre: "Modelos extraídos por el análisis de fotos",
                detalle: "Modelos de visión que el análisis de fotos de macOS sacó en su carpeta temporal y no ha vuelto a leer: \(Formato.listaCorta(modelos.map { $0.0.lastPathComponent })).",
                consecuencia: "Si el análisis los vuelve a necesitar, los saca otra vez de los recursos de macOS (gasta algo de procesador).",
                rutas: modelos.map(\.0), tamanosRutas: modelos.map(\.1), ultimoUso: modelos.map(\.2).max(), categoria: .cachesApps,
                riesgo: .revisar,
                // Sin `enUso`: esos servicios no paran nunca, pero no leen estos modelos. Lo que tengan abierto se mira archivo
                // a archivo.
                motivos: [.info("cpu", "Sin leer en 30 días",
                                "Solo carpetas que no tienen más que modelos (.espresso.net, .weights, .shape y su índice) y que nadie lee desde hace más de 30 días.")],
                dueno: "macOS"))
        }
        return r
    }

    /// Los vídeos de los fondos y salvapantallas en movimiento (Aerials) que macOS descargó, sin el que usas: el que nombran
    /// tus ajustes de fondo y salvapantallas (com.apple.wallpaper/Store/Index.plist), el que se reprodujo en los últimos 3
    /// días o el que tiene abierto algún programa. Ese solo se explica (una nota): borrarlo haría que macOS lo volviera a
    /// descargar enseguida. Los que no nombran tus ajustes (si nombran alguno de los vídeos) y nadie reproduce desde hace 14
    /// días, Seguro en «Liberar al máximo»; los demás, para revisar.
    func videosDeFondos(_ c: Contexto) -> [Elemento] {
        let carpeta = Rutas.enHome("Library/Application Support/com.apple.wallpaper/aerials/videos")
        let videos = Rutas.hijos(carpeta).compactMap { v -> (url: URL, st: stat)? in
            guard !v.lastPathComponent.hasPrefix("."), let st = Terceros.archivoPropio(v.path) else { return nil }
            return (v, st)
        }
        guard !videos.isEmpty else { return [] }
        let ajustes = AjustesDeFondo.leer()
        // Tus ajustes solo dicen cuál usas si nombran alguno de estos vídeos por su identificador. Si no nombran ninguno, no
        // sé cómo lo guarda macOS (otro identificador, una selección al azar): el que usas puede ser cualquiera.
        let concluyentes = ajustes.leidos && videos.contains { ajustes.nombran($0.url.deletingPathExtension().lastPathComponent) }
        var usados: [(url: URL, bytes: Int64, por: String)] = []
        var sobrantes: [(url: URL, bytes: Int64, fecha: Date)] = []
        var dudosos: [(url: URL, bytes: Int64, fecha: Date)] = []
        for (v, st) in videos {
            let bytes = Int64(st.st_blocks) * 512
            let fecha = Date(timeIntervalSince1970: TimeInterval(max(st.st_atimespec.tv_sec, st.st_mtimespec.tv_sec)))
            let dias = Date().timeIntervalSince(fecha) / 86400
            if ajustes.nombran(v.deletingPathExtension().lastPathComponent) {
                usados.append((v, bytes, "lo nombran tus ajustes de fondo de pantalla o salvapantallas"))
            } else if let quien = c.procesos.abiertos.hayAbierto(dentroDe: v.path) {
                usados.append((v, bytes, "\(quien) lo tiene abierto"))
            } else if dias < 3 {
                usados.append((v, bytes, "se reprodujo \(Formato.haceCuanto(fecha).lowercased())"))
            } else if concluyentes && dias >= 14 {
                sobrantes.append((v, bytes, fecha))
            } else {
                dudosos.append((v, bytes, fecha))
            }
        }
        if !usados.isEmpty {
            let bytes = usados.reduce(Int64(0)) { $0 + $1.bytes }
            let uno = usados.count == 1
            c.indice.notas.append(NotaGrande(
                categoria: .cachesApps, titulo: uno ? "Vídeo del fondo o salvapantallas que usas" : "Vídeos de los fondos o salvapantallas que usas",
                texto: "\(uno ? "Un vídeo" : "\(usados.count) vídeos") de fondo en movimiento que macOS descargó y que usas (\(Formato.lista(Array(Set(usados.map(\.por))).sorted()))). No \(uno ? "lo" : "los") ofrezco borrar: macOS \(uno ? "lo" : "los") volvería a descargar (unos \(Formato.bytes(bytes))) y mientras tanto se vería en negro. Para liberar este espacio de verdad, elige en Ajustes del Sistema › Fondo de pantalla y en › Salvapantallas uno que no sea en movimiento y vuelve a analizar.",
                ruta: usados[0].url.path, bytes: bytes))
        }
        // Sin `enUso`: el agente de fondos de pantalla no para nunca, pero un vídeo que no usas no lo tiene abierto (lo que
        // sí tenga abierto se mira archivo a archivo, ahora y al limpiar).
        var r: [Elemento] = []
        if !sobrantes.isEmpty {
            let bytes = sobrantes.map(\.bytes)
            r.append(Elemento(
                nombre: "Vídeos de fondos de pantalla que no usas",
                detalle: "\(sobrantes.count) \(sobrantes.count == 1 ? "vídeo" : "vídeos") de fondos y salvapantallas en movimiento que macOS descargó y que no son tu fondo ni tu salvapantallas.",
                consecuencia: "Nada mientras no los vuelvas a elegir: entonces macOS los descarga otra vez (necesita internet).",
                rutas: sobrantes.map(\.url), tamanosRutas: bytes, ultimoUso: sobrantes.map(\.fecha).max(), categoria: .cachesApps,
                riesgo: .seguro, seleccionado: true,
                motivos: [.bien("photo.on.rectangle.angled", "No los usas",
                                "No aparecen en tus ajustes de fondo de pantalla ni de salvapantallas y nadie los reproduce desde hace más de 14 días."),
                          .info("arrow.down.circle.fill", "Se vuelven a descargar",
                                "Si vuelves a elegir uno, macOS lo baja de nuevo: solo los marco en «Liberar al máximo».")],
                dueno: "macOS", nivel: .maximo, costes: [.descarga(bytes: bytes.reduce(0, +))]))
        }
        if !dudosos.isEmpty {
            r.append(Elemento(
                nombre: "Vídeos de fondos de pantalla",
                detalle: "\(dudosos.count) \(dudosos.count == 1 ? "vídeo" : "vídeos") de fondos de pantalla y salvapantallas en movimiento que macOS descargó.",
                consecuencia: "macOS vuelve a descargar el que tengas puesto (mientras tanto puede verse en negro).",
                rutas: dudosos.map(\.url), tamanosRutas: dudosos.map(\.bytes), ultimoUso: dudosos.map(\.fecha).max(), categoria: .cachesApps,
                riesgo: .revisar,
                motivos: [.info("photo.on.rectangle.angled", "Se vuelven a descargar", concluyentes
                                ? "Tus ajustes de fondo y salvapantallas no los nombran, pero se reprodujeron en las últimas dos semanas: puede que salgan en una selección al azar. macOS descarga de nuevo los que uses."
                                : ajustes.leidos
                                ? "Tus ajustes de fondo de pantalla y salvapantallas no nombran ninguno de estos vídeos, así que no sé cuál es el que usas (puede ser cualquiera, o una selección al azar): macOS descarga de nuevo los que uses."
                                : "No pude leer tus ajustes de fondo de pantalla, así que no sé si alguno es el que usas: macOS descarga de nuevo los que uses.")],
                dueno: "macOS"))
        }
        return r
    }

    // MARK: - Notas (solo se informa)

    /// Un servidor de PostgreSQL en marcha (el número de su postmaster.pid es de un postgres vivo) cuyas bases no cambian
    /// desde hace más de 14 días (sin contar pg_internal.init, pg_filenode.map ni las estadísticas, que reescribe al
    /// arrancar): arranca solo y no lo usas. Son datos tuyos: nunca se ofrece borrarlo, solo se explica cómo pararlo.
    private func notaDeServidoresQuietos(_ c: Contexto) {
        for (d, motor) in Self.basesDeDatos(c) where motor == "PostgreSQL" {
            guard let pid = Procesos.numeroVivo(enArchivo: d + "/postmaster.pid"),
                  c.procesos.programas.contains(where: { $0.pid == pid && $0.nombre.contains("postgres") }),
                  let cambio = Terceros.ultimoCambioDeDatos(d + "/base"), Date().timeIntervalSince(cambio) >= 14 * 86400 else { continue }
            let deApp = d.contains("/Library/Application Support/Postgres/")
            c.indice.notas.append(NotaGrande(
                categoria: .desarrollo, titulo: "PostgreSQL en marcha sin usar (\(Rutas.nombre(d)))",
                texto: "El servidor de PostgreSQL de \(Formato.rutaCorta(d)) está funcionando, pero nada de sus bases cambió desde \(Formato.haceCuanto(cambio).lowercased()). No lo ofrezco borrar: son datos tuyos. Si no lo usas, evita que arranque solo\(deApp ? " (Postgres.app › Settings › desmarca «Automatically start Postgres at login»)" : "") y, si ya no lo necesitas, guarda antes una copia con pg_dumpall con el servidor en marcha; después puedes quitar \(deApp ? "Postgres.app y " : "")esta carpeta.",
                ruta: d, bytes: Terceros.ocupa(URL(fileURLWithPath: d), c)))
        }
    }

    /// Los medios de los chats de WhatsApp (Message/Media): son tuyos y borrarlos del disco dejaría el chat con el archivo
    /// roto, así que solo se informa cuando pesan (más de 100 MB, un archivo de más de 50 MB o un instalador de Windows) y se
    /// manda a la opción de WhatsApp que los borra con su mensaje.
    private func notaDeMediosDeWhatsApp(_ c: Contexto) {
        guard c.accesoTotal else { return }
        for grupo in ["group.net.whatsapp.WhatsApp.shared", "group.net.whatsapp.WhatsAppSMB.shared"] {
            let g = Rutas.enHome("Library/Group Containers/\(grupo)")
            let medios = g.appendingPathComponent("Message/Media")
            guard Terceros.carpetaPropia(medios), Terceros.estaDentro(medios, de: g) else { continue }
            var total: Int64 = 0
            var mayor: Int64 = 0
            var cuantos = 0
            var windows = 0
            var chats = Set<String>()
            let base = medios.path + "/"
            for (ruta, st) in Terceros.archivos(dentroDe: medios.path, maximo: 200_000) {
                let b = Int64(st.st_blocks) * 512
                total += b
                mayor = max(mayor, b)
                cuantos += 1
                if ["exe", "msi"].contains((ruta as NSString).pathExtension.lowercased()) { windows += 1 }
                if let chat = ruta.dropFirst(base.count).split(separator: "/").first { chats.insert(String(chat)) }
            }
            guard total > 100_000_000 || mayor > 50_000_000 || windows > 0 else { continue }
            let grupos = chats.filter { $0.hasSuffix("@g.us") }.count
            let app = grupo.contains("SMB") ? "WhatsApp Business" : "WhatsApp"
            c.indice.notas.append(NotaGrande(
                categoria: .cachesApps, titulo: "Fotos, vídeos y archivos de tus chats de \(app)",
                texto: "\(Formato.numero(cuantos)) archivos de \(Formato.numero(chats.count)) chats (\(Formato.numero(grupos)) de grupo); el más grande ocupa \(Formato.bytes(mayor))\(windows > 0 ? ", y hay \(windows) \(windows == 1 ? "instalador" : "instaladores") de Windows (.exe, .msi), que en un Mac no sirven" : ""). Son tuyos: no los ofrezco borrar desde aquí, porque el chat se quedaría con el archivo roto. Para liberar este espacio: \(app) › Ajustes › Almacenamiento y datos › Administrar almacenamiento (puedes ordenar por tamaño), que borra cada archivo con su mensaje.",
                ruta: medios.path, bytes: total))
        }
    }

    // MARK: - /var/folders/…/C

    /// Lo que macOS guarda en la C de un programa cuando solo dibuja con la GPU: sus sombreadores compilados y la caché de
    /// AppleScript.
    private static let deSombreadores: Set<String> = ["com.apple.metal", "com.apple.metalfe", "com.apple.gpuarchiver",
                                                      "com.apple.scriptmanager2.le.cache"]

    /// ¿La carpeta de C de un programa solo tiene eso, suelto o dentro de una carpeta con su mismo nombre? (Como
    /// `soloGraficos`, para cualquier programa y no solo las apps de Apple.)
    static func soloSombreadores(_ carpeta: URL) -> Bool {
        func deSombreadores(_ u: URL) -> Bool { Self.deSombreadores.contains(u.lastPathComponent.lowercased()) && !Terceros.esEnlaceOSuelto(u) }
        let id = carpeta.lastPathComponent.lowercased()
        let hijos = Rutas.hijos(carpeta)
        return !hijos.isEmpty && hijos.allSatisfy { h in
            if deSombreadores(h) { return true }
            guard h.lastPathComponent.lowercased() == id, Terceros.carpetaPropia(h) else { return false }
            let dentro = Rutas.hijos(h)
            return !dentro.isEmpty && dentro.allSatisfy(deSombreadores)
        }
    }

    /// Los sombreadores de los programas que solo guardan eso en C y que ninguna otra regla ofrece (servicios de macOS como
    /// iconservicesagent o Spotlight, extensiones de Ajustes, apps pequeñas o borradas), juntos y sin mínimo por carpeta:
    /// con 3 días sin cambios en el modo normal, con 2 h solo en «Liberar al máximo», y nunca si un programa tiene algo
    /// abierto dentro. Da igual que el programa esté funcionando: los vuelve a compilar si le hacen falta.
    private func sombreadoresDeProgramas(_ carpetas: [URL], _ c: Contexto) -> [Elemento] {
        var viejos: [(URL, Int64, Date)] = []
        var recientes: [(URL, Int64, Date)] = []
        for h in carpetas {
            // Las vacías (solo carpetas) no liberan nada: no se enseñan.
            guard let f = Terceros.ultimoCambio(h, c), c.procesos.abiertos.hayAbierto(dentroDe: h.path) == nil else { continue }
            let bytes = Terceros.ocupa(h, c)
            let horas = Date().timeIntervalSince(f) / 3600
            guard bytes > 0 else { continue }
            if horas >= 72 { viejos.append((h, bytes, f)) } else if horas >= 2 { recientes.append((h, bytes, f)) }
        }
        func nombres(_ lista: [(URL, Int64, Date)]) -> String {
            Formato.listaCorta(lista.sorted { $0.1 > $1.1 }.map { Self.nombreDePrograma($0.0.lastPathComponent, c) }, maximo: 4)
        }
        var r: [Elemento] = []
        if !viejos.isEmpty {
            let ultimo = viejos.map(\.2).max()
            r.append(Elemento(
                nombre: "Sombreadores compilados de \(viejos.count) \(viejos.count == 1 ? "programa" : "programas")",
                detalle: "Sombreadores que macOS compiló para la tarjeta gráfica (Metal) de programas que no guardan nada más en su carpeta de cachés: \(nombres(viejos)).",
                consecuencia: "Cada programa vuelve a compilar los suyos la próxima vez que dibuje algo (los primeros segundos puede ir algo más lento).",
                rutas: viejos.map(\.0), tamanosRutas: viejos.map(\.1), ultimoUso: ultimo, categoria: .sistema, riesgo: .seguro,
                seleccionado: true,
                motivos: [.bien("cpu", "Se vuelven a compilar",
                                "Solo carpetas que no guardan más que sombreadores, sin cambios en 3 días y que ningún programa tiene abiertas.")],
                dueno: "macOS", cambioAnalizado: ultimo))
        }
        if !recientes.isEmpty {
            let ultimo = recientes.map(\.2).max()
            r.append(Elemento(
                nombre: "Sombreadores recientes de \(recientes.count) \(recientes.count == 1 ? "programa" : "programas")",
                detalle: "Sombreadores que macOS compiló para la tarjeta gráfica (Metal) en los últimos 3 días, de programas que no guardan nada más en su carpeta de cachés: \(nombres(recientes)).",
                consecuencia: "Cada programa vuelve a compilar los suyos la próxima vez que dibuje algo (los primeros segundos puede ir algo más lento).",
                rutas: recientes.map(\.0), tamanosRutas: recientes.map(\.1), ultimoUso: ultimo, categoria: .sistema, riesgo: .seguro,
                seleccionado: true,
                motivos: [.bien("cpu", "Se vuelven a compilar", "Llevan 2 h o más sin cambios y ningún programa los tiene abiertos."),
                          .info("bolt.fill", "Solo en «Liberar al máximo»", "Por prudencia, en el modo normal espero 3 días sin cambios.")],
                dueno: "macOS", nivel: .maximo, cambioAnalizado: ultimo))
        }
        return r
    }

    /// Las cachés que macOS guardó en C para apps que ya no están (com.empresa.app, sin «.helper»): ninguna app instalada ni
    /// conocida por macOS tiene ese identificador, nada suyo está funcionando y no cambian desde hace 7 días. Juntas y sin
    /// mínimo por carpeta: cada una suele pesar poco. Las de Apple no: son del sistema.
    private func cachesDeAppsQueNoEstan(_ carpetas: [URL], _ c: Contexto) -> Elemento? {
        let hace7 = Date().addingTimeInterval(-7 * 86400)
        var elegidas: [(URL, Int64, Date, String)] = []
        for h in carpetas {
            let n = h.lastPathComponent
            let l = n.lowercased()
            let clave = n.replacingOccurrences(of: #"\.(helper|ShipIt)(\..*)?$"#, with: "", options: [.regularExpression, .caseInsensitive])
            guard clave.split(separator: ".").count >= 3, !l.hasPrefix("com.apple."), !l.hasPrefix("org.llvm."),
                  !Terceros.hayApp(clave, c), c.procesos.appAbierta([clave, n]) == nil,
                  !c.procesos.lineas.contains(where: { $0.contains(clave.lowercased()) }),
                  let f = Terceros.ultimoCambio(h, c), f < hace7, c.procesos.abiertos.hayAbierto(dentroDe: h.path) == nil else { continue }
            let bytes = Terceros.ocupa(h, c)
            if bytes > 0 { elegidas.append((h, bytes, f, clave)) }
        }
        guard !elegidas.isEmpty else { return nil }
        let nombres = elegidas.sorted { $0.1 > $1.1 }.map { Self.nombreDePrograma($0.3, c) }
        let ultimo = elegidas.map(\.2).max()
        return Elemento(
            nombre: "Cachés de \(elegidas.count) \(elegidas.count == 1 ? "app que ya no tienes" : "apps que ya no tienes")",
            detalle: "Cachés que macOS guardó en su carpeta privada para apps que ya no están instaladas: \(Formato.listaCorta(nombres, maximo: 5)).",
            consecuencia: "Nada: son de apps que ya no tienes. Si vuelves a instalar alguna, las crea de nuevo.",
            rutas: elegidas.map(\.0), tamanosRutas: elegidas.map(\.1), ultimoUso: ultimo, categoria: .sistema, riesgo: .seguro,
            seleccionado: true,
            motivos: [.bien("magnifyingglass", "No están instaladas",
                            "No encontré ninguna app con esos identificadores (ni en Aplicaciones ni entre las que conoce macOS), nada de ellas está funcionando y no cambian desde hace más de 7 días.")],
            dueno: "macOS", cambioAnalizado: ultimo)
    }

    /// «com.gustavo.escaner» → el nombre de su app si está instalada con ese identificador; si no, la parte que no es
    /// genérica («escaner»). Nunca el de otra app que se le parezca.
    private static func nombreDePrograma(_ n: String, _ c: Contexto) -> String {
        if c.apps.bundleIDs.contains(n.lowercased()), let app = c.apps.nombreApp(para: n) { return app }
        let partes = n.split(separator: ".").map(String.init).filter { !["helper", "shipit", "app", "agent", "extension", "service"].contains($0.lowercased()) }
        guard partes.count >= 3 else { return partes.last ?? n }
        return partes.dropFirst(2).joined(separator: ".")
    }

    // MARK: - Restos de apps de terceros

    /// Un producto de una empresa que tiene otras apps instaladas (Teams junto a Word): `estaInstalado` da por instalado
    /// todo lo de «com.microsoft» y todo lo del equipo de Office, así que sus restos se buscan por su identificador exacto.
    fileprivate struct ProductoQueDejaRestos {
        let nombre: String
        /// Los identificadores que lo dan por instalado (también sus extensiones).
        let ids: [String]
        /// Lo que empieza así en Containers, Caches, HTTPStorages, WebKit, Preferences, Application Scripts y Saved
        /// Application State es suyo.
        let prefijos: [String]
        /// Sus contenedores compartidos (sin el código del equipo): solo si ninguna app instalada los declara en su firma.
        let grupos: [String]
        /// Sus carpetas en Application Support (solo nombres que no pueden ser de otra app).
        let soporte: [String]
        /// Qué guarda, para avisarlo.
        let aviso: String
    }

    fileprivate static let productosQueDejanRestos: [ProductoQueDejaRestos] = [
        ProductoQueDejaRestos(nombre: "Microsoft Teams", ids: ["com.microsoft.teams2", "com.microsoft.teams"],
                              prefijos: ["com.microsoft.teams"], grupos: ["com.microsoft.teams"],
                              soporte: ["Microsoft/MSTeams", "Microsoft/Teams"],
                              aviso: "Guarda tu sesión iniciada y la caché de su navegador interno (WebView2). Tus chats y archivos están en la nube de Microsoft; si vuelves a instalar Teams, tendrás que iniciar sesión otra vez."),
    ]

    /// ¿Ya no está ese producto (ni instalado, ni conocido por macOS, ni abierto)?
    private func noEsta(_ p: ProductoQueDejaRestos, _ c: Contexto) -> Bool {
        !p.ids.contains(where: { Terceros.hayApp($0, c) }) && c.procesos.appAbierta(p.ids + [p.nombre]) == nil
    }

    /// Sus contenedores (Containers y Group Containers), que `restosDeProducto` ofrece enteros. Los compartidos, solo si
    /// ninguna app instalada los declara en su firma (si no se pudo leer ninguna firma, no se sabe quién los usa: se quedan).
    private func contenedoresDe(_ p: ProductoQueDejaRestos, _ c: Contexto) -> [URL] {
        guard c.accesoTotal else { return [] }
        var rutas = Rutas.hijos(Rutas.enHome("Library/Containers")).filter { u in
            let n = u.lastPathComponent.lowercased()
            return p.prefijos.contains { n.hasPrefix($0.lowercased()) } && !Terceros.esEnlaceOSuelto(u)
        }
        let declarados = c.apps.gruposDeLasFirmas
        for g in Rutas.hijos(Rutas.enHome("Library/Group Containers")) where Terceros.carpetaPropia(g) {
            let n = g.lastPathComponent.lowercased()
            let sinEquipo = AppsInstaladas.equipo(de: g.lastPathComponent) != nil ? String(n.dropFirst(11)) : n
            guard !declarados.isEmpty, !declarados.contains(n), p.grupos.contains(where: { sinEquipo.hasPrefix($0.lowercased()) }) else { continue }
            rutas.append(g)
        }
        return rutas
    }

    /// Los contenedores de los productos que ya no están (Teams), por su ruta: los ofrece enteros «Restos de apps borradas»,
    /// así que las reglas que miran dentro de los contenedores (sus cachés, sus registros, sus informes de cierre) no los
    /// repiten.
    func contenedoresDeProductosQueNoEstan(_ c: Contexto) -> Set<String> {
        Set(Self.productosQueDejanRestos.filter { noEsta($0, c) }.flatMap { contenedoresDe($0, c) }.map(\.path))
    }

    private func restosDeProducto(_ p: ProductoQueDejaRestos, _ c: Contexto) -> Elemento? {
        guard noEsta(p, c) else { return nil }
        func suyo(_ u: URL) -> Bool {
            let n = u.lastPathComponent.lowercased()
            return p.prefijos.contains { n.hasPrefix($0.lowercased()) }
        }
        var rutas: [URL] = []
        for lugar in ["Caches", "HTTPStorages", "WebKit", "Preferences", "Application Scripts", "Saved Application State"] {
            rutas += Rutas.hijos(Rutas.enHome("Library/\(lugar)")).filter { suyo($0) && !Terceros.esEnlaceOSuelto($0) }
        }
        rutas += contenedoresDe(p, c)
        for s in p.soporte {
            let u = Rutas.enHome("Library/Application Support/\(s)")
            if Terceros.carpetaPropia(u) { rutas.append(u) }
        }
        guard !rutas.isEmpty else { return nil }
        return Elemento(
            nombre: "\(p.nombre) (ya no está instalada)",
            detalle: "Lo que dejó \(p.nombre) en \(rutas.count) \(rutas.count == 1 ? "lugar" : "lugares"): contenedores, datos, cachés y ajustes.",
            consecuencia: "Si vuelves a instalar \(p.nombre), empezará sin tus ajustes y tendrás que iniciar sesión. Va a la Papelera.",
            rutas: rutas, tamanosRutas: rutas.map { Terceros.ocupa($0, c) }, categoria: .restos, riesgo: .revisar,
            motivos: [.info("magnifyingglass", "No está instalada",
                            "No encontré \(p.nombre) en Aplicaciones, en ~/Applications ni entre las apps que conoce macOS, aunque tengas otras apps de la misma empresa."),
                      .info("person.badge.key.fill", "Sesión guardada", p.aviso)],
            enUso: .app(nombre: p.nombre, claves: p.ids + [p.nombre]), dueno: p.nombre)
    }

    /// Lo que una app opcional de Apple que ya no está (GarageBand, MainStage…) deja fuera de sus contenedores y que
    /// `restosDeAppsDeApple` no miraba: sus cookies y datos web (HTTPStorages, WebKit, Cookies) y, con `conAnaliticas`, sus
    /// registros de uso (Logs/AppAnalytics/<id>.<UUID>.json). Por los prefijos de su identificador, sin seguir enlaces.
    static func restosWebDeAppDeApple(_ prefijos: [String], conAnaliticas: Bool) -> [URL] {
        guard !prefijos.isEmpty else { return [] }
        let p = prefijos.map { $0.lowercased() }
        func suyo(_ n: String) -> Bool { p.contains { n.lowercased().hasPrefix($0) } }
        var r: [URL] = []
        for lugar in ["HTTPStorages", "WebKit"] {
            r += Rutas.hijos(Rutas.enHome("Library/\(lugar)")).filter { suyo($0.lastPathComponent) && !Terceros.esEnlaceOSuelto($0) }
        }
        r += Rutas.hijos(Rutas.enHome("Library/Cookies")).filter {
            suyo($0.lastPathComponent) && $0.pathExtension == "binarycookies" && Terceros.archivoPropio($0.path) != nil
        }
        guard conAnaliticas else { return r }
        r += Rutas.hijos(Rutas.enHome("Library/Logs/AppAnalytics")).filter { u in
            let n = u.lastPathComponent.lowercased()
            return u.pathExtension == "json" && p.contains { n.hasPrefix($0 + ".") } && Terceros.archivoPropio(u.path) != nil
        }
        return r
    }

    /// ¿Ofrece «Registros y fallos» la carpeta Logs/AppAnalytics? `registros` la mira cuando es de algo instalado (el marco
    /// AppAnalytics de macOS): entera si llega al mínimo o, si algo la usa, sus archivos quietos. Entonces los registros de
    /// uso de una app que ya no está no van también en sus restos: saldrían dos veces.
    func analiticasLasOfreceRegistros(_ c: Contexto) -> Bool {
        let carpeta = Rutas.enHome("Library/Logs/AppAnalytics")
        let n = carpeta.lastPathComponent
        guard Terceros.carpetaPropia(carpeta), c.apps.estaInstalado(carpeta: n) else { return false }
        let nombre = c.apps.nombreApp(para: n) ?? n
        let uso = EnUso.app(nombre: nombre, claves: [n, nombre] + c.apps.identificadores(deApp: n))
        return c.indice.bytes(de: carpeta) >= minimo || c.procesos.quienUsa(uso) != nil
            || c.procesos.abiertos.hayAbierto(dentroDe: carpeta.path) != nil
    }

    // MARK: - GarageBand, Logic y MainStage en /Library

    /// Las carpetas de /Library de GarageBand, Logic y MainStage: lo que hay dentro se puede ofrecer (ellas no: su carpeta
    /// padre es de root).
    static func contenedoresDeSonidos(_ raiz: String) -> [String] {
        ["GarageBand", "Logic", "MainStage"].map { raiz + "/Library/Application Support/" + $0 }
    }

    /// Las carpetas de sonidos de Apple de /Library/Audio que se ofrecen enteras. Nunca otras carpetas de Apple Loops: pueden
    /// ser loops que compraste a otros.
    static func carpetasDeSonidos(_ raiz: String) -> [String] {
        ["/Library/Audio/Apple Loops/Apple", "/Library/Audio/Apple Loops Index", "/Library/Audio/Impulse Responses/Apple"].map { raiz + $0 }
    }

    /// com.apple.MainStageApp es MainStage de Creator Studio («MainStage Creator Studio.app»).
    private static let idsDeAppsDeMusica = ["com.apple.garageband10", "com.apple.garageband", "com.apple.logic10", "com.apple.mainstage3",
                                            "com.apple.MainStageApp"]
    /// Las apps de vídeo de Apple también usan Apple Loops (sus efectos de sonido) y, Final Cut Pro, las respuestas de impulso
    /// (su Space Designer).
    private static let idsDeAppsDeVideo = ["com.apple.iMovieApp", "com.apple.FinalCut", "com.apple.FinalCutTrial"]
    /// Cualquier otra edición de esas apps (otra versión, la de Creator Studio…), por cómo empieza su identificador.
    private static let prefijosDeAppsDeMusica = ["com.apple.garageband", "com.apple.logic", "com.apple.mainstage"]
    private static let prefijosDeAppsDeVideo = ["com.apple.imovie", "com.apple.finalcut"]

    /// ¿Hay alguna de esas apps: con uno de esos identificadores (`hayApp`) o, entre las que conoce `AppsInstaladas`, con uno
    /// que empiece así?
    private static func hayAlguna(_ ids: [String], prefijos: [String], _ c: Contexto) -> Bool {
        ids.contains { Terceros.hayApp($0, c) } || c.apps.bundleIDs.contains { id in prefijos.contains { id.hasPrefix($0) } }
    }

    /// Los sonidos y lecciones que GarageBand, Logic y MainStage instalan para todo el Mac en /Library, cuando no queda
    /// ninguna de las tres (los de Apple Loops, además, sin iMovie ni Final Cut). Solo lo que tu usuario puede borrar sin
    /// contraseña (eres administrador y el grupo admin puede escribir en todo lo de dentro). Para revisar: si vuelves a
    /// instalar alguna, los descarga otra vez (en algunos Macs son decenas de GB).
    private func sonidosDeAppsDeApple(_ c: Contexto) -> Elemento? {
        guard let raiz = Rutas.raizDelSistema, !Self.hayAlguna(Self.idsDeAppsDeMusica, prefijos: Self.prefijosDeAppsDeMusica, c),
              c.procesos.appAbierta(Self.idsDeAppsDeMusica + ["GarageBand", "Logic Pro", "MainStage"]) == nil else { return nil }
        let sinVideo = !Self.hayAlguna(Self.idsDeAppsDeVideo, prefijos: Self.prefijosDeAppsDeVideo, c)
        var candidatas: [URL] = []
        for contenedor in Self.contenedoresDeSonidos(raiz) where Terceros.carpetaPropia(URL(fileURLWithPath: contenedor)) {
            candidatas += Rutas.hijos(URL(fileURLWithPath: contenedor))
        }
        for p in Self.carpetasDeSonidos(raiz) where sinVideo || !(p.contains("/Apple Loops") || p.contains("/Impulse Responses")) {
            candidatas.append(URL(fileURLWithPath: p))
        }
        let rutas = candidatas.filter { u in
            !Terceros.esEnlaceOSuelto(u) && Seguridad.esDelSistemaBorrable(Rutas.real(u)) && Terceros.todoEscribible(u.path)
        }
        guard !rutas.isEmpty else { return nil }
        let tamanos = rutas.map { Tamanos.recorriendo($0.path) }
        return Elemento(
            nombre: "Sonidos y lecciones de GarageBand, Logic y MainStage",
            detalle: "Lo que esas apps instalaron para todo el Mac en /Library: \(Formato.listaCorta(rutas.map(\.lastPathComponent), maximo: 4)).",
            consecuencia: "Si vuelves a instalar GarageBand, Logic Pro o MainStage, descargan otra vez sus sonidos y lecciones (necesita internet; pueden ser varios GB). Va a la Papelera.",
            rutas: rutas, tamanosRutas: tamanos, categoria: .restos, riesgo: .revisar,
            motivos: [.info("magnifyingglass", "No están instaladas",
                            "No encontré GarageBand, Logic Pro ni MainStage en Aplicaciones, en ~/Applications ni entre las apps que conoce macOS\(sinVideo ? "" : "; los Apple Loops y las respuestas de impulso se quedan porque los usan iMovie o Final Cut Pro"). Tu música y tus proyectos no están aquí."),
                      .info("lock.open.fill", "Sin contraseña",
                            "Están en /Library, para todo el Mac, pero tu usuario las puede borrar: eres administrador y el grupo admin puede escribir en ellas.")],
            enUso: .app(nombre: "GarageBand", claves: Self.idsDeAppsDeMusica + ["GarageBand", "Logic Pro", "MainStage"]),
            dueno: "GarageBand", costes: [.descarga(bytes: tamanos.reduce(0, +))])
    }

    // MARK: - Registros y fallos

    /// Un reporte de fallos de macOS: cierres inesperados (.ips, .crash), cuelgues (.hang, .spin), consumo excesivo (.diag),
    /// pánicos, apagados lentos (.shutdownStall) y falta de memoria (JetsamEvent-…).
    static func esReporteDeFallos(_ nombre: String) -> Bool {
        guard !nombre.hasPrefix(".") else { return false }
        if nombre.hasPrefix("JetsamEvent-") { return true }
        return ["ips", "diag", "crash", "spin", "hang", "panic", "shutdownstall"].contains((nombre as NSString).pathExtension.lowercased())
    }

    private static let patronAppDeReporte = try! NSRegularExpression(pattern: #"^(.+?)[_-]\d{4}-\d{2}-\d{2}"#)

    /// Los reportes de fallos de todo el Mac (/Library/Logs/DiagnosticReports, donde macOS 27 los guarda también para tus
    /// apps), si tu usuario puede borrarlos sin contraseña (es del grupo _analyticsusers). Solo los archivos sueltos con
    /// más de 3 días: nunca la carpeta ni Retired. Se enseña aunque pese poco: dice qué apps se cierran de golpe.
    private func reportesDeFallosDelSistema(_ c: Contexto) -> Elemento? {
        guard let raiz = Rutas.raizDelSistema else { return nil }
        let carpeta = raiz + "/Library/Logs/DiagnosticReports"
        guard access(carpeta, R_OK | W_OK | X_OK) == 0 else { return nil }
        let hace3 = Date().addingTimeInterval(-3 * 86400)
        var elegidos: [(URL, Int64, Date)] = []
        var porApp: [String: Int] = [:]
        for n in (try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? [] where Self.esReporteDeFallos(n) {
            let ruta = carpeta + "/" + n
            var st = stat()
            guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
            let fecha = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            guard fecha < hace3, Seguridad.esDelSistemaBorrable(ruta) else { continue }
            elegidos.append((URL(fileURLWithPath: ruta), Int64(st.st_blocks) * 512, fecha))
            let app: String
            if n.hasPrefix("JetsamEvent-") { app = "falta de memoria" }
            else if n.hasPrefix("shutdown_stall") { app = "apagados lentos" }
            else if let m = Self.patronAppDeReporte.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)),
                    let r = Range(m.range(at: 1), in: n) { app = String(n[r]) }
            else { app = (n as NSString).deletingPathExtension }
            porApp[app, default: 0] += 1
        }
        guard !elegidos.isEmpty else { return nil }
        let masFallan = porApp.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { "\($0.key) (\($0.value))" }
        return Elemento(
            nombre: "Reportes de fallos de todo el Mac",
            detalle: "\(Formato.numero(elegidos.count)) informes de cierres inesperados, cuelgues, consumo excesivo, falta de memoria y apagados lentos. Los que más se repiten: \(Formato.listaCorta(masFallan, maximo: 4)).",
            consecuencia: "Nada importante: solo sirven para diagnosticar esos fallos. macOS crea nuevos cuando hace falta.",
            rutas: elegidos.map(\.0), tamanosRutas: elegidos.map(\.1), ultimoUso: elegidos.map(\.2).max(), categoria: .registros,
            riesgo: .seguro, seleccionado: true,
            motivos: [.bien("doc.text.magnifyingglass", "Solo informes",
                            "Solo informes de fallos sueltos con más de 3 días. Están en /Library/Logs/DiagnosticReports, la carpeta de todo el Mac, pero tu usuario los puede borrar sin contraseña (es del grupo que los gestiona).")],
            dueno: "macOS", siempreVisible: true)
    }

    /// Los informes de cierre que guardan algunas apps aisladas (Data/Library/Application Support/AppExit/TerminationInfo,
    /// un archivo con nombre UUID por cada vez que la app se cerró: WhatsApp y otras): diagnóstico que la app rota sola a la
    /// semana. Los de más de 1 día que nadie tiene abiertos.
    private func informesDeCierre(_ c: Contexto) -> [Elemento] {
        guard c.accesoTotal else { return [] }
        let haceUnDia = Date().addingTimeInterval(-86400)
        let deRestos = contenedoresDeProductosQueNoEstan(c)
        var r: [Elemento] = []
        for k in Rutas.hijos(Rutas.enHome("Library/Containers")) {
            let id = k.lastPathComponent
            guard !id.hasPrefix("."), !Self.propios.contains(id), !deRestos.contains(k.path), Terceros.carpetaPropia(k),
                  c.apps.estaInstalado(carpeta: id) else { continue }
            let carpeta = k.appendingPathComponent("Data/Library/Application Support/AppExit/TerminationInfo")
            guard Terceros.carpetaPropia(carpeta), Terceros.estaDentro(carpeta, de: k) else { continue }
            var elegidos: [(URL, Int64, Date)] = []
            for n in (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? [] where Terceros.esUUID(n) {
                let ruta = carpeta.path + "/" + n
                guard let st = Terceros.archivoPropio(ruta) else { continue }
                let fecha = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                guard fecha < haceUnDia, c.procesos.abiertos.hayAbierto(dentroDe: ruta) == nil else { continue }
                elegidos.append((URL(fileURLWithPath: ruta), Int64(st.st_blocks) * 512, fecha))
            }
            guard !elegidos.isEmpty else { continue }
            let nombre = c.apps.nombreApp(para: id) ?? Self.nombreDePrograma(id, c)
            let uso = EnUso.app(nombre: nombre, claves: [id, nombre])
            let abierta = c.procesos.quienUsa(uso) != nil
            let ultimo = elegidos.map(\.2).max()
            r.append(Elemento(
                nombre: "Informes de cierre de \(nombre)",
                detalle: "\(Formato.numero(elegidos.count)) informes que \(nombre) guarda cada vez que se cierra, para diagnosticar cierres inesperados.",
                consecuencia: "Nada importante: solo sirven para diagnosticar fallos. \(nombre) los rota sola y crea uno nuevo cada vez que se cierra.",
                rutas: elegidos.map(\.0), tamanosRutas: elegidos.map(\.1), ultimoUso: ultimo, categoria: .registros, riesgo: .seguro,
                seleccionado: true,
                motivos: [.bien("doc.text.magnifyingglass", "Solo diagnóstico",
                                "Solo los archivos con nombre UUID de su carpeta AppExit/TerminationInfo, con más de 1 día y que nadie tiene abiertos.")],
                // Abierta: no se espera a cerrarla (son de cierres anteriores), pero si algo cambia después del análisis no se toca.
                enUso: abierta ? nil : uso, dueno: nombre, cambioAnalizado: ultimo))
        }
        return r
    }

    // MARK: - Copias de apps

    /// Apps de ~/Applications que repiten una de Aplicaciones (el mismo nombre de .app, el mismo tamaño de Info.plist y del
    /// programa) y que nunca se abrieron, mientras la de Aplicaciones sí: una copia que se quedó al instalarla. Solo las
    /// que no tienen identificador (applets de AppleScript, apps propias): las que lo tienen ya las compara `instaladores`
    /// por versión, compilación y firma. Para revisar.
    func copiasRepetidasDeApps(_ c: Contexto) -> [Elemento] {
        guard let raiz = Rutas.raizDelSistema else { return [] }
        let propias = Rutas.enHome("Applications")
        var candidatas: [URL] = []
        for h in Rutas.hijos(propias) {
            if h.pathExtension == "app" { candidatas.append(h) }
            else if Terceros.carpetaPropia(h) { candidatas += Rutas.hijos(h).filter { $0.pathExtension == "app" } }
        }
        var r: [Elemento] = []
        for copia in candidatas where Terceros.carpetaPropia(copia) {
            let relativa = String(copia.path.dropFirst(propias.path.count))
            let otra = URL(fileURLWithPath: raiz + "/Applications" + relativa)
            guard Terceros.carpetaPropia(otra), Rutas.real(otra) != Rutas.real(copia),
                  let suya = Terceros.identidadSinID(copia), let instalada = Terceros.identidadSinID(otra), suya == instalada,
                  Terceros.ultimoUso(copia) == nil, let usada = Terceros.ultimoUso(otra) else { continue }
            let nombre = copia.deletingPathExtension().lastPathComponent
            r.append(Elemento(
                nombre: "Copia sin abrir de \(nombre)",
                detalle: "Otra copia de \(nombre) en \(Formato.rutaCorta(copia.deletingLastPathComponent())); la que usas es la de Aplicaciones.",
                consecuencia: "Sigues teniendo la de Aplicaciones, que es la que abres. Va a la Papelera: puedes devolverla con «Deshacer».",
                rutas: [copia], tamanosRutas: [Tamanos.recorriendo(copia.path)], categoria: .instaladores, riesgo: .revisar,
                motivos: [.info("doc.on.doc", "Repetida y sin abrir",
                                "En Aplicaciones hay otra igual (el mismo Info.plist y el mismo programa) que abriste por última vez \(Formato.haceCuanto(usada).lowercased()). Esta no se ha abierto nunca según macOS.")],
                enUso: .rutas(nombre: nombre, raiz: copia.path), dueno: nombre))
        }
        return r
    }
}

/// Lo que dicen tus ajustes de fondo de pantalla y salvapantallas: com.apple.wallpaper/Store/Index.plist y las
/// preferencias del salvapantallas. Solo se buscan dentro los identificadores de los vídeos (sin interpretar nada más):
/// en el texto tal cual, en UTF-16 y en las listas de propiedades que llevan dentro.
private struct AjustesDeFondo {
    /// Se pudo leer Index.plist. Si nombra alguno de los vídeos, uno que no nombra no es el que usas; si no nombra ninguno, no
    /// se sabe (`videosDeFondos`).
    var leidos = false
    private var textos: [String] = []
    private var crudos: [Data] = []

    static func leer() -> AjustesDeFondo {
        var a = AjustesDeFondo()
        let indice = Rutas.enHome("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        var archivos = [indice]
        archivos += Rutas.hijos(Rutas.enHome("Library/Preferences/ByHost")).filter { $0.lastPathComponent.hasPrefix("com.apple.screensaver") }
        archivos.append(Rutas.enHome("Library/Preferences/com.apple.screensaver.plist"))
        for u in archivos {
            guard let st = Terceros.archivoPropio(u.path), st.st_size < 20_000_000, let datos = FileManager.default.contents(atPath: u.path) else { continue }
            if u == indice { a.leidos = true }
            a.crudos.append(datos)
            a.recoger(datos, nivel: 0)
        }
        return a
    }

    /// Los textos de una lista de propiedades (y de las que lleva dentro como datos), en minúsculas.
    private mutating func recoger(_ datos: Data, nivel: Int) {
        guard nivel < 4, let raiz = try? PropertyListSerialization.propertyList(from: datos, format: nil) else { return }
        var pendientes: [Any] = [raiz]
        var vistos = 0
        while let v = pendientes.popLast(), vistos < 200_000 {
            vistos += 1
            switch v {
            case let s as String: textos.append(s.lowercased())
            case let d as Data:
                crudos.append(d)
                recoger(d, nivel: nivel + 1)
            case let l as [Any]: pendientes += l
            case let d as [String: Any]:
                textos += d.keys.map { $0.lowercased() }
                pendientes += Array(d.values)
            default: break
            }
        }
    }

    /// ¿Nombran el vídeo de ese identificador (su UUID)? Como texto (ASCII o UTF-16) o como los 16 bytes de un NSUUID
    /// archivado.
    func nombran(_ uuid: String) -> Bool {
        let l = uuid.lowercased()
        if textos.contains(where: { $0.contains(l) }) { return true }
        var formas = [uuid.uppercased(), l].flatMap { [Data($0.utf8), $0.data(using: .utf16BigEndian) ?? Data(), $0.data(using: .utf16LittleEndian) ?? Data()] }
        if let u = UUID(uuidString: uuid) { formas.append(withUnsafeBytes(of: u.uuid) { Data($0) }) }
        return crudos.contains { d in formas.contains { !$0.isEmpty && d.range(of: $0) != nil } }
    }
}

/// Utilidades de estas reglas (sin seguir enlaces, con tope donde se recorre).
fileprivate enum Terceros {
    /// Una carpeta de verdad (no un enlace).
    static func carpetaPropia(_ u: URL) -> Bool {
        var st = stat()
        return lstat(u.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// Un enlace, o algo que ya no está.
    static func esEnlaceOSuelto(_ u: URL) -> Bool {
        var st = stat()
        return lstat(u.path, &st) != 0 || (st.st_mode & S_IFMT) == S_IFLNK
    }

    /// Un archivo normal tuyo (no un enlace ni una carpeta).
    static func archivoPropio(_ ruta: String) -> stat? {
        var st = stat()
        guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid() else { return nil }
        return st
    }

    /// `u`, sin enlaces, sigue dentro de `raiz`.
    static func estaDentro(_ u: URL, de raiz: URL) -> Bool {
        Rutas.real(u).hasPrefix(Rutas.real(raiz) + "/")
    }

    private static let patronUUID = try! NSRegularExpression(
        pattern: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#)

    static func esUUID(_ n: String) -> Bool {
        patronUUID.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
    }

    /// Lo que ocupa: lo que midió el índice o, si no la registró (pequeña o fuera del índice), recorriéndola aquí.
    static func ocupa(_ u: URL, _ c: Contexto) -> Int64 {
        if let i = c.indice.info(u.path) { return i.bytes }
        var st = stat()
        guard lstat(u.path, &st) == 0 else { return 0 }
        return (st.st_mode & S_IFMT) == S_IFDIR ? Tamanos.recorriendo(u.path) : Int64(st.st_blocks) * 512
    }

    /// Lo último que cambió dentro (archivos y carpetas): del índice si la registró; si no, recorriéndola.
    static func ultimoCambio(_ u: URL, _ c: Contexto) -> Date? {
        if let i = c.indice.info(u.path), i.masReciente > 0 { return Date(timeIntervalSince1970: TimeInterval(i.masReciente)) }
        var st = stat()
        guard lstat(u.path, &st) == 0 else { return nil }
        let s = (st.st_mode & S_IFMT) == S_IFDIR ? Fechas.ultimoCambio([u.path]) : Int(st.st_mtimespec.tv_sec)
        return s > 0 ? Date(timeIntervalSince1970: TimeInterval(s)) : nil
    }

    /// Los archivos normales que hay dentro (a cualquier profundidad, sin seguir enlaces), con su stat.
    static func archivos(dentroDe ruta: String, maximo: Int = 20_000) -> [(String, stat)] {
        guard let rutaC = strdup(ruta) else { return [] }
        defer { free(rutaC) }
        var argumentos: [UnsafeMutablePointer<CChar>?] = [rutaC, nil]
        guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return [] }
        defer { fts_close(fts) }
        var r: [(String, stat)] = []
        var vistos = 0
        while let e = fts_read(fts), vistos < maximo {
            vistos += 1
            guard Int32(e.pointee.fts_info) == FTS_F else { continue }
            let st = e.pointee.fts_statp.pointee
            guard st.st_uid == getuid() else { continue }
            r.append((String(cString: e.pointee.fts_path), st))
        }
        return r
    }

    /// ¿Dentro de esa carpeta solo hay carpetas y archivos normales tuyos cuyo nombre acepta `vale` (al menos uno), sin
    /// enlaces ni nada que no se pueda leer? Si es demasiado grande para mirarla entera, no.
    static func soloArchivos(dentroDe ruta: String, maximo: Int = 5_000, _ vale: (String) -> Bool) -> Bool {
        guard let rutaC = strdup(ruta) else { return false }
        defer { free(rutaC) }
        var argumentos: [UnsafeMutablePointer<CChar>?] = [rutaC, nil]
        guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return false }
        defer { fts_close(fts) }
        var vistos = 0
        var alguno = false
        while let e = fts_read(fts) {
            vistos += 1
            if vistos > maximo { return false }
            switch Int32(e.pointee.fts_info) {
            case FTS_D, FTS_DP: continue
            case FTS_F:
                let largo = Int(e.pointee.fts_namelen)
                let n = String(cString: e.pointee.fts_path + (Int(e.pointee.fts_pathlen) - largo))
                guard e.pointee.fts_statp.pointee.st_uid == getuid(), vale(n) else { return false }
                alguno = true
            default: return false
            }
        }
        return alguno
    }

    /// La última vez que se leyó o cambió algo de dentro (atime y mtime de sus archivos), o nil si no hay archivos.
    static func ultimaLectura(dentroDe ruta: String) -> Date? {
        let s = archivos(dentroDe: ruta).map { max($0.1.st_atimespec.tv_sec, $0.1.st_mtimespec.tv_sec) }.max()
        return s.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// Lo último que cambió en los datos de una base de PostgreSQL (base/), sin lo que reescribe al arrancar
    /// (pg_internal.init, pg_filenode.map) ni sus estadísticas y temporales.
    static func ultimoCambioDeDatos(_ base: String) -> Date? {
        let ignorar: Set<String> = ["pg_internal.init", "pg_filenode.map"]
        let s = archivos(dentroDe: base, maximo: 200_000).filter { ruta, _ in
            let n = Rutas.nombre(ruta)
            return !ignorar.contains(n) && !n.hasPrefix("pg_stat") && !ruta.contains("/pgsql_tmp")
        }.map { $0.1.st_mtimespec.tv_sec }.max()
        return s.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// ¿Hay alguna app con ese identificador (o una extensión suya, o la app de la que es extensión)? En Aplicaciones, en
    /// ~/Applications o abierta (lo que sabe `AppsInstaladas`) y, en tu Mac, en cualquier sitio que conozca macOS
    /// (LaunchServices). Sin el atajo del «mismo fabricante» de `estaInstalado`: Teams no está instalada porque lo esté Word.
    static func hayApp(_ id: String, _ c: Contexto) -> Bool {
        let l = id.lowercased()
        if c.apps.bundleIDs.contains(where: { $0 == l || $0.hasPrefix(l + ".") || l.hasPrefix($0 + ".") }) { return true }
        // En una casa de prueba solo cuentan sus apps, nunca las de verdad.
        guard !Rutas.casaDePrueba else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    /// ¿Tu usuario puede escribir en esa carpeta y en todas las de dentro (para moverla a la Papelera y vaciarla después sin
    /// contraseña)? No si alguna tiene el bit «sticky» y no es tuya (ahí solo el dueño de cada archivo lo puede borrar), ni
    /// si es demasiado grande para mirarla entera.
    static func todoEscribible(_ ruta: String, maximo: Int = 200_000) -> Bool {
        var st = stat()
        guard lstat(ruta, &st) == 0 else { return false }
        if (st.st_mode & S_IFMT) != S_IFDIR { return true }
        guard let rutaC = strdup(ruta) else { return false }
        defer { free(rutaC) }
        var argumentos: [UnsafeMutablePointer<CChar>?] = [rutaC, nil]
        guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return false }
        defer { fts_close(fts) }
        var vistos = 0
        while let e = fts_read(fts) {
            vistos += 1
            if vistos > maximo { return false }
            switch Int32(e.pointee.fts_info) {
            case FTS_D:
                let st = e.pointee.fts_statp.pointee
                if access(e.pointee.fts_path, W_OK | X_OK) != 0 || (st.st_mode & S_ISVTX != 0 && st.st_uid != getuid()) { return false }
            case FTS_DNR, FTS_ERR, FTS_NS: return false
            default: continue
            }
        }
        return true
    }

    /// Lo que identifica una app sin identificador: el tamaño de su Info.plist, el nombre y el tamaño de su programa y sus
    /// recursos (`huellaDeRecursos`): en los applets de AppleScript el programa es el mismo para todos y lo que cambia es el
    /// script (Contents/Resources/Scripts/main.scpt). nil si tiene identificador o le falta algo.
    static func identidadSinID(_ app: URL) -> String? {
        let info = app.path + "/Contents/Info.plist"
        var st = stat()
        guard lstat(info, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        let datos = NSDictionary(contentsOfFile: info)
        guard datos?["CFBundleIdentifier"] == nil else { return nil }
        let tamanoInfo = Int64(st.st_size)
        let programas = (try? FileManager.default.contentsOfDirectory(atPath: app.path + "/Contents/MacOS")) ?? []
        guard let programa = (datos?["CFBundleExecutable"] as? String) ?? (programas.count == 1 ? programas[0] : nil),
              lstat(app.path + "/Contents/MacOS/" + programa, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG,
              let recursos = huellaDeRecursos(app.path + "/Contents/Resources") else { return nil }
        return "\(tamanoInfo)|\(programa)|\(st.st_size)|\(recursos)"
    }

    /// Los archivos de Contents/Resources (a cualquier profundidad, sin seguir enlaces) con su tamaño, y a dónde apunta cada
    /// enlace, en orden. «» si no hay, nil si no se puede leer entera o tiene demasiados archivos para compararla.
    private static func huellaDeRecursos(_ ruta: String, maximo: Int = 5_000) -> String? {
        var st = stat()
        guard lstat(ruta, &st) == 0 else { return "" }
        guard (st.st_mode & S_IFMT) == S_IFDIR, let rutaC = strdup(ruta) else { return nil }
        defer { free(rutaC) }
        var argumentos: [UnsafeMutablePointer<CChar>?] = [rutaC, nil]
        guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return nil }
        defer { fts_close(fts) }
        var partes: [String] = []
        while let e = fts_read(fts) {
            if partes.count > maximo { return nil }
            let relativa = String(String(cString: e.pointee.fts_path).dropFirst(ruta.count))
            switch Int32(e.pointee.fts_info) {
            case FTS_D, FTS_DP: continue
            case FTS_F: partes.append("\(relativa):\(e.pointee.fts_statp.pointee.st_size)")
            case FTS_SL, FTS_SLNONE:
                var destino = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
                let n = readlink(e.pointee.fts_path, &destino, Int(PATH_MAX))
                guard n >= 0 else { return nil }
                partes.append("\(relativa)->\(String(decoding: destino[0..<n].map { UInt8(bitPattern: $0) }, as: UTF8.self))")
            default: return nil
            }
        }
        return partes.sorted().joined(separator: "\n")
    }

    /// La última vez que se abrió una app según macOS: el atributo que pone LaunchServices al abrirla
    /// (com.apple.lastuseddate#PS) o, si no lo tiene, Spotlight. En una casa de prueba, solo el atributo: fuera de lo que
    /// indexa, Spotlight se inventa la fecha (la de la última lectura del archivo).
    static func ultimoUso(_ app: URL) -> Date? {
        var tiempo = timespec()
        let leido = withUnsafeMutableBytes(of: &tiempo) { getxattr(app.path, "com.apple.lastuseddate#PS", $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }
        if leido >= MemoryLayout<Int>.size, tiempo.tv_sec > 0 { return Date(timeIntervalSince1970: TimeInterval(tiempo.tv_sec)) }
        return Rutas.casaDePrueba ? nil : Fechas.ultimoUsoSpotlight(app)
    }
}
