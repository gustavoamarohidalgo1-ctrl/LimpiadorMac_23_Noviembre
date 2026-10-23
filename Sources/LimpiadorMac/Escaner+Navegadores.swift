import AppKit
import Foundation

// Navegadores Chromium, apps de Electron, Firefox y Tectonic: lo que no tiene nombre de caché y por eso no sale en
// `cachesInternas` (datos temporales y bases de datos de sitios, componentes que el navegador descarga solo, perfiles
// sin ventana que no se borraron, versiones viejas que quedan al actualizar). Las cachés con nombre conocido (Cache,
// Code Cache, Service Worker…, CachedData de los editores) y sus «logs» ya los ofrecen «Caché interna» y «Registros
// internos»; ~/Library/Caches/<navegador> entera, «Caché de <app>».

extension Escaner {
    /// Un navegador (o una app de Electron) basado en Chromium: dónde guarda sus datos y cómo saber si está abierto.
    fileprivate struct RaizChromium {
        let raiz: URL
        let nombre: String
        let claves: [String]
        /// Una app de Electron: sus perfiles extra están en Partitions/.
        let electron: Bool
        let brave: Bool
        /// El identificador del navegador (nil en las apps de Electron).
        var id: String? = nil
        var uso: EnUso { .app(nombre: nombre, claves: claves) }
    }

    /// (carpeta en Application Support, nombre, identificador).
    fileprivate static let navegadoresChromium: [(rel: String, nombre: String, id: String)] = [
        ("Google/Chrome", "Google Chrome", "com.google.Chrome"), ("Google/Chrome Beta", "Chrome Beta", "com.google.Chrome.beta"),
        ("Google/Chrome Canary", "Chrome Canary", "com.google.Chrome.canary"), ("Chromium", "Chromium", "org.chromium.Chromium"),
        ("Microsoft Edge", "Microsoft Edge", "com.microsoft.edgemac"), ("Microsoft Edge Beta", "Microsoft Edge Beta", "com.microsoft.edgemac.Beta"),
        ("Microsoft Edge Dev", "Microsoft Edge Dev", "com.microsoft.edgemac.Dev"),
        ("Microsoft Edge Canary", "Microsoft Edge Canary", "com.microsoft.edgemac.Canary"),
        ("BraveSoftware/Brave-Browser", "Brave Browser", "com.brave.Browser"),
        ("BraveSoftware/Brave-Browser-Beta", "Brave Browser Beta", "com.brave.Browser.beta"),
        ("BraveSoftware/Brave-Browser-Nightly", "Brave Browser Nightly", "com.brave.Browser.nightly"),
        ("Vivaldi", "Vivaldi", "com.vivaldi.Vivaldi"), ("com.operasoftware.Opera", "Opera", "com.operasoftware.Opera"),
        ("com.operasoftware.OperaGX", "Opera GX", "com.operasoftware.OperaGX"), ("Arc/User Data", "Arc", "company.thebrowser.Browser"),
    ]

    /// Componentes que Chromium (y Electron) descargan solos en la raíz de sus datos, con lo que dejan de funcionar
    /// mientras no vuelven a bajarse.
    fileprivate static let componentesQueVuelven: [(carpeta: String, que: String)] = [
        ("screen_ai", "Screen AI (leer el texto de PDF escaneados e imágenes)"), ("WasmTtsEngine", "el motor de lectura en voz alta"),
        ("OnDeviceHeadSuggestModel", "las sugerencias de la barra de direcciones sin conexión"),
        ("hyphen-data", "los diccionarios para partir palabras"), ("ZxcvbnData", "la comprobación de contraseñas débiles"),
        ("OptimizationHints", "las pistas de optimización de páginas"), ("Safe Browsing", "las listas de Navegación segura"),
        ("WidevineCdm", "Widevine, el módulo de vídeo protegido (Netflix, Disney+, Spotify web…)"),
    ]

    /// De esos, los que el navegador vuelve a bajar solo cuando le hacen falta y sin los que mientras tanto no pasa nada
    /// grave: van como Seguro, solo en «Liberar al máximo» (cuesta descargarlos). Safe Browsing (sin él no avisa de
    /// sitios peligrosos) y Widevine (sin él no se ve el vídeo protegido) siguen en Revisar.
    fileprivate static let componentesSinRiesgo: Set<String> = [
        "screen_ai", "WasmTtsEngine", "OnDeviceHeadSuggestModel", "hyphen-data", "ZxcvbnData", "OptimizationHints",
    ]

    /// Otros componentes pequeños con una carpeta por versión: de estos solo se ofrecen las versiones viejas.
    fileprivate static let componentesConVersiones: Set<String> = [
        "CertificateRevocation", "FirstPartySetsPreloaded", "MEIPreload", "SafetyTips", "TrustTokenKeyCommitments", "PKIMetadata",
        "OriginTrials", "AutofillStates", "Crowd Deny", "FileTypePolicies", "SSLErrorAssistant", "PrivacySandboxAttestationsPreloaded",
        "TpcdMetadata", "CookieReadinessList", "ProbabilisticRevealTokenRegistry", "AmountExtractionHeuristicRegexes",
    ]

    /// El programa Tor que descarga Brave («tor-0.4.8.13-darwin-brave-1»): su componente ya lo ofrece `clienteTorDeBrave`.
    fileprivate static let patronTorBrave = try! NSRegularExpression(pattern: #"^tor-\d+\.\d+\.\d+\.\d+-\w+(-\w+)?-brave-\d+$"#)

    // MARK: - Navegadores y apps de Electron

    /// Todo lo de los navegadores Chromium y las apps de Electron que va en «Cachés de aplicaciones».
    func navegadoresYElectron(_ c: Contexto) -> [Elemento] {
        let appSupport = Rutas.enHome("Library/Application Support")
        var raices: [RaizChromium] = []
        var deNavegadores = Set<String>()
        for (rel, nombre, id) in Self.navegadoresChromium {
            let raiz = appSupport.appendingPathComponent(rel)
            deNavegadores.insert(raiz.path)
            // Sin el navegador instalado, lo suyo es de «Restos de apps borradas» (o de nadie): aquí no se toca.
            guard Self.esCarpetaReal(raiz), c.apps.bundleIDs.contains(id.lowercased()),
                  let primera = rel.split(separator: "/").first.map(String.init), c.apps.estaInstalado(carpeta: primera) else { continue }
            raices.append(RaizChromium(raiz: raiz, nombre: nombre, claves: [id, nombre], electron: false, brave: rel.hasPrefix("BraveSoftware/"),
                                       id: id))
        }
        var sinCabeza: [(carpeta: URL, nombre: String)] = raices.map { (URL(fileURLWithPath: $0.raiz.path + "-headless"), $0.nombre) }
        // Apps de Electron: guardan sus datos como un perfil de Chromium (con su «Local State») en Application Support.
        for h in Rutas.hijos(appSupport) where Self.esCarpetaReal(h) {
            let n = h.lastPathComponent
            if n.hasSuffix("-headless") {
                // Uno suelto (Chromium-headless) solo si no es de una app que ya no está: entonces va con sus restos.
                if !sinCabeza.contains(where: { $0.carpeta.path == h.path }) && c.apps.estaInstalado(carpeta: n) {
                    sinCabeza.append((h, String(n.dropLast(9))))
                }
                continue
            }
            guard !deNavegadores.contains(h.path), !n.hasPrefix("com.apple."), !n.hasPrefix("."), !Self.propios.contains(n),
                  Rutas.existe(h.appendingPathComponent("Local State")), c.apps.estaInstalado(carpeta: n) else { continue }
            let app = c.apps.nombreApp(para: n) ?? n
            raices.append(RaizChromium(raiz: h, nombre: app, claves: [n, app], electron: true, brave: false))
        }

        var r: [Elemento] = []
        for raiz in raices {
            r += datosDeSitios(raiz, c)
            r += componentesDescargados(raiz, c)
            if raiz.brave { r += extrasDeBrave(raiz, c) }
            r += masDeNavegadores(raiz, c)
        }
        r += perfilesSinCabeza(sinCabeza, c)
        r += versionesViejasDeDiscord(c)
        r += tectonicDeApps(c)
        return r
    }

    /// Los perfiles de una raíz: Default, Profile N, Guest Profile y System Profile; en Electron, la propia raíz y sus
    /// particiones (Partitions/<nombre>). Opera también guarda su perfil en la raíz.
    fileprivate static func perfiles(de raiz: RaizChromium) -> [(url: URL, etiqueta: String)] {
        var r: [(url: URL, etiqueta: String)] = []
        if raiz.electron || ["IndexedDB", "File System"].contains(where: { Self.esCarpetaReal(raiz.raiz.appendingPathComponent($0)) }) {
            r.append((raiz.raiz, ""))
        }
        let nombres = nombresDePerfiles(raiz.raiz)
        for h in Rutas.hijos(raiz.raiz) where Self.esCarpetaReal(h) {
            let n = h.lastPathComponent
            let numerado = n.hasPrefix("Profile ") && n.count > 8 && n.dropFirst(8).allSatisfy(\.isNumber)
            guard n == "Default" || n == "Guest Profile" || n == "System Profile" || numerado else { continue }
            let visible = nombres[n] ?? (n == "Default" ? "principal" : n)
            r.append((h, " (perfil «\(visible)»)"))
        }
        if raiz.electron {
            for p in Rutas.hijos(raiz.raiz.appendingPathComponent("Partitions")) where Self.esCarpetaReal(p) {
                r.append((p, " (partición «\(p.lastPathComponent)»)"))
            }
        }
        return r
    }

    /// El nombre que le diste a cada perfil, de «Local State» (un JSON de configuración; solo si es pequeño).
    fileprivate static func nombresDePerfiles(_ raiz: URL) -> [String: String] {
        let estado = raiz.appendingPathComponent("Local State")
        guard let tamano = (try? FileManager.default.attributesOfItem(atPath: estado.path))?[.size] as? NSNumber,
              tamano.intValue < 262_144, let datos = try? Data(contentsOf: estado),
              let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return [:] }
        var r: [String: String] = [:]
        for (carpeta, valor) in cache {
            if let n = (valor as? [String: Any])?["name"] as? String, !n.isEmpty { r[carpeta] = n }
        }
        return r
    }

    /// Una carpeta de verdad, no un enlace: un enlace llamado como una versión o un perfil puede llevar a tus documentos.
    fileprivate static func esCarpetaReal(_ u: URL) -> Bool {
        var st = stat()
        return lstat(u.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// Un archivo de verdad, no un enlace ni una carpeta.
    fileprivate static func esArchivoReal(_ u: URL) -> Bool {
        var st = stat()
        return lstat(u.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG
    }

    /// Lo que ocupa una ruta: del índice, o recorriéndola si es una carpeta pequeña que el índice no registra (< 1 MB).
    fileprivate static func ocupa(_ u: URL, _ c: Contexto) -> Int64 {
        if let i = c.indice.info(u.path) { return i.bytes }
        var st = stat()
        guard lstat(u.path, &st) == 0 else { return 0 }
        return (st.st_mode & S_IFMT) == S_IFDIR ? Tamanos.recorriendo(u.path) : Int64(st.st_blocks) * 512
    }

    /// Lo último que cambió dentro: del índice, o mirando como mucho 2.000 entradas si es pequeña. Nil si no se pudo leer
    /// entera: entonces no se sabe.
    fileprivate static func cambioDentro(_ u: URL, _ c: Contexto) -> Date? {
        guard !c.indice.tieneSinLeer(u.path) else { return nil }
        if let i = c.indice.info(u.path), i.masReciente > 0 { return Date(timeIntervalSince1970: TimeInterval(i.masReciente)) }
        if esCarpetaReal(u) && access(u.path, R_OK | X_OK) != 0 { return nil }
        return Fechas.masRecienteDentro(u, maximo: 2_000)
    }

    /// «153.3», «4.10.2830.0», «0.0.309»: solo cifras y puntos.
    fileprivate static func esVersion(_ n: String) -> Bool {
        guard let primera = n.first, primera.isNumber, n.last?.isNumber == true, !n.contains("..") else { return false }
        return n.allSatisfy { $0.isNumber || $0 == "." }
    }

    fileprivate static func versiones(en carpeta: URL) -> [URL] {
        Rutas.hijos(carpeta).filter { esVersion($0.lastPathComponent) && Self.esCarpetaReal($0) }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
    }

    /// «https_mail.example.com_0» → «mail.example.com»; «http_localhost_5173» → «localhost:5173».
    fileprivate static func sitio(_ origen: String) -> String {
        var s = Substring(origen)
        for prefijo in ["https_", "http_"] where s.hasPrefix(prefijo) { s = s.dropFirst(prefijo.count) }
        guard let guion = s.lastIndex(of: "_"), s[s.index(after: guion)...].allSatisfy(\.isNumber) else { return String(s) }
        let puerto = s[s.index(after: guion)...]
        return String(s[..<guion]) + (puerto == "0" || puerto.isEmpty ? "" : ":\(puerto)")
    }

    // MARK: Datos de sitios

    /// En cada perfil: el almacenamiento temporal de la File System API (File System/<n>/t; el persistente, «p», nunca)
    /// y las bases IndexedDB de sitios que no cambian desde hace más de 60 días. Nada se marca solo.
    fileprivate func datosDeSitios(_ raiz: RaizChromium, _ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let ahora = Date()
        for (perfil, etiqueta) in Self.perfiles(de: raiz) {
            // File System/000/t, 001/t…: «t» es el tipo temporal. Ahí guarda también su sistema de archivos privado (OPFS)
            // cada app web (documentos, proyectos, bases de datos), y si el sitio pidió almacenamiento persistente el
            // navegador no lo vacía nunca: solo los que llevan más de 60 días sin cambios, y nunca marcados.
            let temporales = Rutas.hijos(perfil.appendingPathComponent("File System"))
                .filter { $0.lastPathComponent.allSatisfy(\.isNumber) && Self.esCarpetaReal($0) }
                .compactMap { n in Rutas.hijos(n).first { $0.lastPathComponent == "t" && Self.esCarpetaReal($0) } }
                .filter { t in Self.cambioDentro(t, c).map { ahora.timeIntervalSince($0) > 60 * 86400 } ?? false }
            if !temporales.isEmpty {
                r.append(Elemento(
                    nombre: "Datos temporales de sitios de \(raiz.nombre)\(etiqueta)",
                    detalle: "Archivos que \(temporales.count) \(temporales.count == 1 ? "sitio guardó" : "sitios guardaron") con la File System API (también el almacenamiento privado de las apps web) y que no cambian desde hace más de 60 días.",
                    consecuencia: "Esos sitios los vuelven a descargar o crear cuando los necesiten. Si alguno guardaba ahí algo que no está en otro sitio (un documento de una app web, un proyecto, un juego, trabajo sin subir), se pierde.",
                    rutas: temporales, tamanosRutas: temporales.map { Self.ocupa($0, c) }, categoria: .cachesApps, riesgo: .revisar,
                    motivos: [.aviso("externaldrive.badge.exclamationmark", "Archivos de apps web",
                                     "Aquí guardan sus archivos las apps web (documentos, proyectos, bases de datos). Si alguno es tuyo y no está en otro sitio, se pierde. No sé qué sitio es ni qué guarda.")],
                    enUso: raiz.uso, dueno: raiz.nombre))
            }

            // IndexedDB/<origen>.indexeddb.leveldb y .blob, juntos por sitio. Solo sitios web: lo de las extensiones
            // (chrome-extension_…) y de la propia app (vscode-file_…) es configuración, no de un sitio.
            var porOrigen: [String: [URL]] = [:]
            for h in Rutas.hijos(perfil.appendingPathComponent("IndexedDB")) {
                let n = h.lastPathComponent
                guard n.hasPrefix("https_") || n.hasPrefix("http_"), let punto = n.range(of: ".indexeddb."), Self.esCarpetaReal(h) else { continue }
                porOrigen[String(n[..<punto.lowerBound]), default: []].append(h)
            }
            var viejos: [(sitio: String, rutas: [URL], tamanos: [Int64], fecha: Date)] = []
            for (origen, rutas) in porOrigen {
                let fechas = rutas.map { Self.cambioDentro($0, c) }
                // Si no se pudo saber cuándo cambió alguna parte, no se ofrece.
                guard !fechas.contains(where: { $0 == nil }), let fecha = fechas.compactMap({ $0 }).max(),
                      ahora.timeIntervalSince(fecha) > 60 * 86400 else { continue }
                viejos.append((Self.sitio(origen), rutas, rutas.map { Self.ocupa($0, c) }, fecha))
            }
            guard !viejos.isEmpty else { continue }
            viejos.sort { $0.tamanos.reduce(0, +) > $1.tamanos.reduce(0, +) }
            let mayores = viejos.prefix(3).map { "\($0.sitio) (\(Formato.bytes($0.tamanos.reduce(0, +))))" }
            r.append(Elemento(
                nombre: "Datos de sitios sin usar en \(raiz.nombre)\(etiqueta)",
                detalle: "Bases de datos (IndexedDB) de \(viejos.count) \(viejos.count == 1 ? "sitio que no cambia" : "sitios que no cambian") desde hace más de 60 días. \(viejos.count == 1 ? "Es" : "Los que más ocupan:") \(Formato.lista(mayores)).",
                consecuencia: "Esos sitios pierden lo que guardaban en \(raiz.nombre): puede cerrarse tu sesión en ellos y perderse lo que tenían para funcionar sin conexión (correos, documentos, mensajes sin enviar). Si los vuelves a visitar, descargan lo que necesiten.",
                rutas: viejos.flatMap { $0.rutas }, tamanosRutas: viejos.flatMap { $0.tamanos }, ultimoUso: viejos.map { $0.fecha }.max(),
                categoria: .cachesApps, riesgo: .revisar,
                motivos: [.aviso("person.crop.circle.badge.exclamationmark", "Datos de sitios",
                                 "No es caché: son datos que esos sitios guardaron en \(raiz.nombre). Bórralos solo si ya no usas esos sitios.")],
                enUso: raiz.uso, dueno: raiz.nombre))
        }
        return r
    }

    // MARK: Componentes

    /// Los componentes que el navegador descarga solo: el actual de los que se pueden volver a bajar (Revisar; los que no
    /// hacen falta para nada importante, como Screen AI, Seguro en «Liberar al máximo») y las versiones viejas que se
    /// quedan al actualizar uno (Seguro), también las de los componentes de Brave (carpetas de 32 letras de la «a» a la
    /// «p») y las del cliente Tor (su versión actual la ofrece `clienteTorDeBrave`).
    fileprivate func componentesDescargados(_ raiz: RaizChromium, _ c: Contexto) -> [Elemento] {
        var actuales: [URL] = []
        var nombres: [String] = []
        var descargables: [URL] = []
        var nombresDescargables: [String] = []
        var viejas: [URL] = []
        var nombresViejas: [String] = []
        var widevine = false
        var navegacionSegura = false

        /// Las versiones que sobran: todas menos la más alta, si la más alta está completa (con su manifest.json).
        func sobrantes(_ carpeta: URL, conservar: Set<String> = []) -> (viejas: [URL], actual: URL?) {
            let lista = Self.versiones(en: carpeta)
            guard let nueva = lista.last else { return ([], nil) }
            guard lista.count > 1, Rutas.existe(nueva.appendingPathComponent("manifest.json")) else { return ([], nueva) }
            return (lista.dropLast().filter { !conservar.contains($0.lastPathComponent) }, nueva)
        }

        for (carpeta, que) in Self.componentesQueVuelven {
            let u = raiz.raiz.appendingPathComponent(carpeta)
            guard Self.esCarpetaReal(u) else { continue }
            var conservar = Set<String>()
            if carpeta == "WidevineCdm" {
                // La versión que el navegador anotó como la que usa (un JSON de pocos bytes) tampoco se toca.
                let nota = u.appendingPathComponent("latest-component-updated-widevine-cdm")
                if Self.esArchivoReal(nota), let tamano = (try? FileManager.default.attributesOfItem(atPath: nota.path))?[.size] as? NSNumber,
                   tamano.intValue < 65_536, let datos = FileManager.default.contents(atPath: nota.path),
                   let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any], let ruta = json["Path"] as? String {
                    conservar.insert(Rutas.nombre(ruta))
                }
            }
            let (sobran, actual) = sobrantes(u, conservar: conservar)
            viejas += sobran
            if !sobran.isEmpty { nombresViejas.append("\(carpeta) \(Formato.lista(sobran.map(\.lastPathComponent)))") }
            // Sin versiones (Safe Browsing), la carpeta entera; con versiones, las que se conservan.
            let quedan = actual == nil ? [u] : Self.versiones(en: u).filter { v in !sobran.contains { $0.path == v.path } }
            if Self.componentesSinRiesgo.contains(carpeta) {
                descargables += quedan
                nombresDescargables.append(que)
                continue
            }
            actuales += quedan
            nombres.append(que)
            if carpeta == "WidevineCdm" { widevine = true }
            if carpeta == "Safe Browsing" { navegacionSegura = true }
        }
        for carpeta in Self.componentesConVersiones {
            let u = raiz.raiz.appendingPathComponent(carpeta)
            guard Self.esCarpetaReal(u) else { continue }
            let sobran = sobrantes(u).viejas
            viejas += sobran
            if !sobran.isEmpty { nombresViejas.append("\(carpeta) \(Formato.lista(sobran.map(\.lastPathComponent)))") }
        }
        // Componentes con un identificador de 32 letras (los de Brave, y alguno de Chrome).
        for comp in Rutas.hijos(raiz.raiz) where comp.lastPathComponent.count == 32
            && comp.lastPathComponent.allSatisfy({ ("a"..."p").contains($0) }) && Self.esCarpetaReal(comp) {
            let lista = Self.versiones(en: comp)
            guard lista.count > 1 else { continue }
            let esTor = lista.contains { v in
                Rutas.hijos(v).contains { f in
                    let n = f.lastPathComponent
                    return Self.patronTorBrave.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
                }
            }
            guard !esTor else {
                // Del cliente Tor, solo las versiones de detrás de una nueva y completa que no esté funcionando.
                let sobran = Self.versionesViejasDeTor(comp, c)
                viejas += sobran
                if !sobran.isEmpty { nombresViejas.append("el cliente Tor \(Formato.lista(sobran.map(\.lastPathComponent)))") }
                continue
            }
            let sobran = sobrantes(comp).viejas
            viejas += sobran
            if !sobran.isEmpty { nombresViejas.append("\(comp.lastPathComponent.prefix(6))… \(Formato.lista(sobran.map(\.lastPathComponent)))") }
        }

        // Muchas apps de Electron no tienen actualizador de componentes: sin component_crx_cache, el actual no se ofrece
        // (no se sabe si lo vuelven a bajar).
        if raiz.electron && !Self.esCarpetaReal(raiz.raiz.appendingPathComponent("component_crx_cache")) {
            actuales = []
            descargables = []
        }
        var r: [Elemento] = []
        if !descargables.isEmpty {
            let tamanos = descargables.map { Self.ocupa($0, c) }
            let total = tamanos.reduce(0, +)
            let screenAI = descargables.contains { $0.path.contains("/screen_ai") }
            r.append(Elemento(
                nombre: screenAI ? "Screen AI y otros componentes de \(raiz.nombre)" : "Componentes que \(raiz.nombre) vuelve a descargar",
                detalle: "Partes que \(raiz.nombre) descarga por su cuenta y vuelve a bajar cuando le hacen falta: \(Formato.listaCorta(nombresDescargables, maximo: 4)).",
                consecuencia: "\(raiz.nombre) los vuelve a descargar (unos \(Formato.bytes(total)); necesita internet). Mientras tanto no funciona lo que depende de ellos\(screenAI ? ", como leer el texto de los PDF escaneados y de las imágenes" : ""). No se pierde nada tuyo.",
                rutas: descargables, tamanosRutas: tamanos, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                motivos: [.info("arrow.down.circle.fill", "Se vuelven a descargar",
                                "No guardan nada tuyo, pero cuesta volver a bajarlos: por eso no los marco solos, solo con «Liberar al máximo» o al cerrar \(raiz.nombre) para limpiar.")],
                enUso: raiz.uso, dueno: raiz.nombre, nivel: .maximo, costes: [.descarga(bytes: total)]))
        }
        if !viejas.isEmpty {
            r.append(Elemento(
                nombre: "Versiones viejas de componentes de \(raiz.nombre)",
                detalle: "Versiones anteriores de componentes que \(raiz.nombre) ya actualizó: \(Formato.listaCorta(nombresViejas, maximo: 4)).",
                consecuencia: "Nada: \(raiz.nombre) usa la versión más nueva de cada uno, que no se toca.",
                rutas: viejas, tamanosRutas: viejas.map { Self.ocupa($0, c) }, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("clock.arrow.circlepath", "Versión anterior",
                                "De cada uno hay una versión más nueva y completa al lado. Con \(raiz.nombre) cerrado, la vieja ya no la carga nadie.")],
                enUso: raiz.uso, dueno: raiz.nombre))
        }
        if !actuales.isEmpty {
            let tamanos = actuales.map { Self.ocupa($0, c) }
            var consecuencia = "\(raiz.nombre) los vuelve a descargar cuando los necesite (necesita internet). Hasta entonces no funciona lo que depende de ellos."
            if widevine { consecuencia += " Sin Widevine no se ven Netflix ni otros sitios de vídeo protegido hasta que se descargue otra vez." }
            if navegacionSegura { consecuencia += " Sin las listas de Navegación segura, no te avisa de sitios peligrosos hasta que las vuelve a bajar." }
            r.append(Elemento(
                nombre: "Componentes descargados de \(raiz.nombre)",
                detalle: "Partes que \(raiz.nombre) descarga por su cuenta: \(Formato.listaCorta(nombres, maximo: 4)).",
                consecuencia: consecuencia,
                rutas: actuales, tamanosRutas: tamanos, categoria: .cachesApps, riesgo: .revisar,
                motivos: [.info("arrow.down.circle.fill", "Se vuelven a descargar",
                                "No son datos tuyos, pero hacen falta para algunas funciones y vuelven a ocupar lo mismo en cuanto se descargan.")],
                enUso: raiz.uso, dueno: raiz.nombre, costes: [.descarga(bytes: tamanos.reduce(0, +))]))
        }
        return r
    }

    // MARK: Brave

    /// Brave: la caché del directorio de la red Tor (tor/data/cached-*, sin keys/ ni state) y el bloqueador de anuncios ya
    /// compilado de cada perfil (adblock_cache), que Brave rehace con las listas que ya tiene.
    fileprivate func extrasDeBrave(_ raiz: RaizChromium, _ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        // Con Tor funcionando (tor-…-darwin-brave-…), su caché se está usando.
        let torEnMarcha = c.procesos.lineas.contains { $0.contains("-darwin-brave-") }
        let datosTor = raiz.raiz.appendingPathComponent("tor/data")
        let cacheTor = Self.esCarpetaReal(datosTor)
            ? Rutas.hijos(datosTor).filter { $0.lastPathComponent.hasPrefix("cached-") && Self.esArchivoReal($0) }
            : []
        if !torEnMarcha && !cacheTor.isEmpty {
            let tamanos = cacheTor.map { Self.ocupa($0, c) }
            r.append(Elemento(
                nombre: "Caché de la red Tor de \(raiz.nombre)",
                detalle: "La lista de servidores de la red Tor que Brave descargó la última vez que abriste una ventana privada con Tor.",
                consecuencia: "La próxima ventana con Tor la vuelve a descargar (unos \(Formato.bytes(tamanos.reduce(0, +))), unos segundos). Tus ajustes y las claves de Tor no se tocan.",
                rutas: cacheTor, tamanosRutas: tamanos, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                motivos: [.info("arrow.down.circle.fill", "Se vuelve a descargar",
                                "Tor la descarga otra vez al conectarse: por eso no la marco sola, solo con «Liberar al máximo».")],
                enUso: raiz.uso, dueno: raiz.nombre, nivel: .maximo, costes: [.descarga(bytes: tamanos.reduce(0, +))]))
        }
        let adblock = Self.perfiles(de: raiz).map { $0.url.appendingPathComponent("adblock_cache") }.filter(Self.esCarpetaReal)
        if !adblock.isEmpty {
            r.append(Elemento(
                nombre: "Bloqueador de anuncios compilado de \(raiz.nombre)",
                detalle: "El bloqueador de anuncios de Brave ya preparado a partir de sus listas de filtros (adblock_cache\(adblock.count > 1 ? ", en \(adblock.count) perfiles" : "")).",
                consecuencia: "Brave lo vuelve a preparar al abrirse con las listas que ya tiene descargadas: el primer arranque tarda un poco más.",
                rutas: adblock, tamanosRutas: adblock.map { Self.ocupa($0, c) }, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("arrow.triangle.2.circlepath", "Se regenera", "Sale de las listas de filtros que Brave guarda aparte, sin descargar nada.")],
                enUso: raiz.uso, dueno: raiz.nombre))
        }
        return r
    }

    // MARK: Perfiles sin ventana

    /// <Navegador>-headless/scoped_dir*: el perfil temporal de un navegador abierto sin ventana (--headless, el de las
    /// pruebas y la automatización) que no se borró al terminar. Con cualquier navegador sin ventana funcionando, nada.
    /// (Caches/<…>-headless ya va entera en «Caché de <navegador>».)
    fileprivate func perfilesSinCabeza(_ carpetas: [(carpeta: URL, nombre: String)], _ c: Contexto) -> [Elemento] {
        let patron = "--headless"
        guard !c.procesos.lineas.contains(where: { $0.contains(patron) }) else { return [] }
        let ahora = Date()
        var r: [Elemento] = []
        for (carpeta, nombre) in carpetas {
            let temporales = Rutas.hijos(carpeta).filter { $0.lastPathComponent.hasPrefix("scoped_dir") && Self.esCarpetaReal($0) }
            // Uno de hace menos de una hora puede ser de un navegador que está arrancando.
            let fechas = temporales.map { Self.cambioDentro($0, c) }
            let quietos = zip(temporales, fechas).filter { _, f in f.map { ahora.timeIntervalSince($0) > 3600 } ?? false }
            guard !quietos.isEmpty else { continue }
            let ultimo = quietos.compactMap { $0.1 }.max()
            r.append(Elemento(
                nombre: "Perfiles temporales de \(nombre) sin ventana",
                detalle: "\(quietos.count) \(quietos.count == 1 ? "perfil temporal" : "perfiles temporales") que \(nombre) creó al abrirse sin ventana (--headless, lo que usan las pruebas y la automatización) y no borró al terminar.",
                consecuencia: "Nada: cada vez que se abre así crea uno nuevo.",
                rutas: quietos.map { $0.0 }, tamanosRutas: quietos.map { Self.ocupa($0.0, c) }, ultimoUso: ultimo,
                categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("checkmark.circle.fill", "Sin usar",
                                "Ningún navegador sin ventana está funcionando y nadie los toca desde \(Formato.haceCuanto(ultimo).lowercased()).")],
                enUso: .proceso(nombre: "\(nombre) sin ventana", patron: patron), dueno: nombre))
        }
        return r
    }

    // MARK: Electron

    /// Discord (Electron) guarda sus módulos en una carpeta por versión (Application Support/discord/0.0.309) y deja la
    /// anterior al actualizarse. Se conservan la más nueva y la de la app instalada.
    fileprivate func versionesViejasDeDiscord(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        for (carpeta, nombre, id) in [("discord", "Discord", "com.hnc.Discord"), ("discordptb", "Discord PTB", "com.hnc.DiscordPTB"),
                                      ("discordcanary", "Discord Canary", "com.hnc.DiscordCanary")] {
            guard c.apps.bundleIDs.contains(id.lowercased()) else { continue }
            let lista = Self.versiones(en: Rutas.enHome("Library/Application Support/\(carpeta)"))
            guard lista.count > 1, let nueva = lista.last, Self.esCarpetaReal(nueva.appendingPathComponent("modules")) else { continue }
            // La versión de la app instalada (en Aplicaciones o en tu carpeta de Aplicaciones) tampoco se toca.
            let apps = (c.apps.rutasEnAplicaciones[id.lowercased()] ?? []) + [Rutas.enHome("Applications/\(nombre).app").path]
            let instalada = apps.compactMap { ruta -> String? in
                guard Bundle(path: ruta)?.bundleIdentifier?.lowercased() == id.lowercased() else { return nil }
                return Bundle(path: ruta)?.infoDictionary?["CFBundleShortVersionString"] as? String
            }
            let viejas = lista.dropLast().filter { !instalada.contains($0.lastPathComponent) }
            guard !viejas.isEmpty else { continue }
            let conservadas = lista.filter { $0 == nueva || instalada.contains($0.lastPathComponent) }.map(\.lastPathComponent)
            let quedan = conservadas.count > 1
                ? "Se quedan la \(nueva.lastPathComponent) (la más nueva) y la \(Formato.lista(conservadas.filter { $0 != nueva.lastPathComponent })) (la de la app instalada)"
                : "Se queda la \(nueva.lastPathComponent), la más nueva"
            r.append(Elemento(
                nombre: "Versiones viejas de \(nombre)",
                detalle: "Módulos de versiones anteriores de \(nombre) (\(Formato.listaCorta(viejas.map(\.lastPathComponent)))) que se quedaron al actualizarse. \(quedan).",
                consecuencia: "Nada: \(quedan.prefix(1).lowercased() + quedan.dropFirst()), que no se tocan.",
                rutas: Array(viejas), tamanosRutas: viejas.map { Self.ocupa($0, c) }, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("clock.arrow.circlepath", "Versión anterior", "Hay una versión más nueva y completa al lado.")],
                enUso: .app(nombre: nombre, claves: [id, nombre]), dueno: nombre))
        }
        return r
    }

    // MARK: - Tectonic

    /// Tectonic (TeX) dentro de una app: */tectonic/{bundles,formats} en su Application Support (ChatGPT lo trae para
    /// mostrar fórmulas). Se buscan en el índice (solo registra las carpetas de 1 MB o más).
    fileprivate func tectonicDeApps(_ c: Contexto) -> [Elemento] {
        let appSupport = Rutas.enHome("Library/Application Support").path + "/"
        var porApp: [String: [URL]] = [:]
        for ruta in c.indice.carpetas.keys where ruta.hasPrefix(appSupport)
            && (ruta.hasSuffix("/tectonic/bundles") || ruta.hasSuffix("/tectonic/formats")) {
            guard let carpeta = ruta.dropFirst(appSupport.count).split(separator: "/").first.map(String.init) else { continue }
            porApp[carpeta, default: []].append(URL(fileURLWithPath: ruta))
        }
        var r: [Elemento] = []
        for (carpeta, rutas) in porApp.sorted(by: { $0.key < $1.key }) {
            // De una app que ya no está se encarga «Restos de apps borradas».
            guard !carpeta.hasPrefix("com.apple."), !Self.propios.contains(carpeta), c.apps.estaInstalado(carpeta: carpeta) else { continue }
            let app = c.apps.nombreApp(para: carpeta) ?? carpeta
            let ordenadas = rutas.sorted { $0.path < $1.path }
            let tamanos = ordenadas.map { Self.ocupa($0, c) }
            r.append(Elemento(
                nombre: "Paquetes TeX de \(app) (Tectonic)",
                detalle: "Paquetes y formatos de TeX que \(app) descargó con Tectonic para mostrar fórmulas.",
                consecuencia: "\(app) los vuelve a descargar la próxima vez que muestre una fórmula (unos \(Formato.bytes(tamanos.reduce(0, +))); necesita internet).",
                rutas: ordenadas, tamanosRutas: tamanos, categoria: .cachesApps, riesgo: .revisar,
                motivos: [.info("arrow.down.circle.fill", "Se vuelve a descargar", "Es una caché de Tectonic: no guarda nada tuyo, pero cuesta volver a bajarla.")],
                enUso: .app(nombre: app, claves: [carpeta, app]), dueno: app, costes: [.descarga(bytes: tamanos.reduce(0, +))]))
        }
        return r
    }

    /// ~/Library/Caches/TectonicProject.Tectonic: los paquetes y formatos de TeX que descarga Tectonic, si el comando sigue
    /// instalado (si no, es un resto y lo ofrece «Restos de apps borradas»).
    func cachesDeTectonic(_ c: Contexto) -> [Elemento] {
        let cache = Rutas.enHome("Library/Caches/TectonicProject.Tectonic")
        guard Self.esCarpetaReal(cache), c.apps.esDeUnComando(carpeta: cache.lastPathComponent) else { return [] }
        let bytes = c.indice.bytes(de: cache)
        return [Elemento(
            nombre: "Caché de Tectonic (TeX)",
            detalle: "Paquetes y formatos de TeX que Tectonic descargó para compilar tus documentos.",
            consecuencia: "Tectonic los vuelve a descargar la próxima vez que compiles un documento (necesita internet). Tus documentos no se tocan.",
            rutas: [cache], categoria: .desarrollo, riesgo: .revisar,
            motivos: [.info("arrow.down.circle.fill", "Se vuelve a descargar", "El comando tectonic sigue instalado: es su caché, no un resto.")],
            enUso: .programas(nombre: "Tectonic", ejecutables: ["tectonic"]), dueno: "Tectonic", costes: [.descarga(bytes: bytes)])]
    }

    // MARK: - Firefox

    /// Informes de fallos de Firefox y sus derivados: Crash Reports y, en cada perfil, crashes y minidumps. Sus cachés
    /// (~/Library/Caches/Firefox) ya van en «Caché de Firefox»; storage/ son datos de sitios y no se tocan.
    func fallosDeFirefox(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        for (carpeta, nombre, id) in [("Firefox", "Firefox", "org.mozilla.firefox"), ("Thunderbird", "Thunderbird", "org.mozilla.thunderbird"),
                                      ("librewolf", "LibreWolf", "org.mozilla.librewolf"), ("zen", "Zen", "app.zen-browser.zen"),
                                      ("Waterfox", "Waterfox", "net.waterfox.waterfox")] {
            let raiz = Rutas.enHome("Library/Application Support/\(carpeta)")
            guard Self.esCarpetaReal(raiz), c.apps.estaInstalado(carpeta: carpeta) else { continue }
            var rutas = [raiz.appendingPathComponent("Crash Reports")]
            for perfil in Rutas.hijos(raiz.appendingPathComponent("Profiles")) where Self.esCarpetaReal(perfil) {
                rutas += ["crashes", "minidumps"].map { perfil.appendingPathComponent($0) }
            }
            rutas = rutas.filter(Self.esCarpetaReal)
            guard !rutas.isEmpty else { continue }
            r.append(Elemento(
                nombre: "Informes de fallos de \(nombre)",
                detalle: "Informes que \(nombre) guarda cuando se cierra de golpe (Crash Reports y, en cada perfil, crashes y minidumps), enviados o pendientes de enviar.",
                consecuencia: "Nada importante: solo se pierden informes de fallos antiguos. Tus perfiles, marcadores y datos de sitios no se tocan.",
                rutas: rutas, tamanosRutas: rutas.map { Self.ocupa($0, c) }, categoria: .registros, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("doc.text.magnifyingglass", "Solo diagnóstico", "Sirven para diagnosticar fallos; \(nombre) crea nuevos cuando hace falta.")],
                enUso: .app(nombre: nombre, claves: [id, nombre]), dueno: nombre))
        }
        return r
    }

    // MARK: - Más de los navegadores

    /// Lo que se añadió después en cada navegador o app de Electron: lo que un sitio descargó en una sola visita, los
    /// sitios que guardan mucho y no cambian, los iconos, las versiones viejas de extensiones, las cachés pequeñas sin
    /// nombre de caché y las copias viejas del perfil. De paso, avisa (como nota) de la actualización que espera.
    fileprivate func masDeNavegadores(_ raiz: RaizChromium, _ c: Contexto) -> [Elemento] {
        if !raiz.electron, let id = raiz.id { anotarActualizacionPendiente(raiz, id: id, c) }
        return datosDeUnaVisita(raiz, c) + sitiosGrandesQuietos(raiz, c) + iconosDeSitios(raiz, c)
            + versionesViejasDeExtensiones(raiz, c) + cachesPequenas(raiz, c) + copiasDelPerfil(raiz, c)
    }

    /// Cuándo nació, cuándo cambió por última vez y cuándo se leyó por última vez (lstat: sin seguir enlaces).
    fileprivate static func fechas(_ u: URL) -> (nace: Date, cambia: Date, lee: Date)? {
        var st = stat()
        guard lstat(u.path, &st) == 0 else { return nil }
        func d(_ t: timespec) -> Date { Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1e9) }
        return (d(st.st_birthtimespec), d(st.st_mtimespec), d(st.st_atimespec))
    }

    /// Lo último que cambió de una lista de rutas (carpetas y archivos). Nil si de alguna no se pudo saber.
    fileprivate static func ultimoCambio(_ rutas: [URL], _ c: Contexto) -> Date? {
        var r = Date.distantPast
        for u in rutas {
            guard let f = esCarpetaReal(u) ? cambioDentro(u, c) : fechas(u)?.cambia else { return nil }
            r = max(r, f)
        }
        return r
    }

    /// Un JSON pequeño (la configuración del navegador), o nil si no es un archivo de verdad o pasa de `maximo`.
    fileprivate static func json(_ u: URL, maximo: Int = 16_000_000) -> [String: Any]? {
        var st = stat()
        guard lstat(u.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= maximo,
              let datos = FileManager.default.contents(atPath: u.path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any]
    }

    /// Un perfil de Chromium de verdad: su configuración (Preferences) y su red (Cookies, Network…) al lado. Para dar por
    /// caché carpetas de nombre genérico como «Shared Dictionary».
    fileprivate static func esPerfilChromium(_ u: URL) -> Bool {
        esArchivoReal(u.appendingPathComponent("Preferences"))
            && ["Cookies", "Network Persistent State", "Network"].contains { Rutas.existe(u.appendingPathComponent($0)) }
    }

    // MARK: Sitios

    /// Las claves y valores de una base LevelDB pequeña, leyendo solo sus registros (*.log, que no van comprimidos): las
    /// altas sobrescriben y las bajas quitan. Lo que ya pasó a sus tablas (*.ldb) no se ve; los navegadores reutilizan el
    /// registro, así que en las bases pequeñas suele estar todo ahí.
    fileprivate static func clavesDeLevelDB(_ carpeta: URL, maximo: Int = 4_000_000) -> [String: String] {
        var r: [String: String] = [:]
        let logs = Rutas.hijos(carpeta).filter { $0.pathExtension == "log" && esArchivoReal($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for log in logs {
            var st = stat()
            guard lstat(log.path, &st) == 0, st.st_size <= maximo, let datos = FileManager.default.contents(atPath: log.path) else { continue }
            let b = [UInt8](datos)
            // Bloques de 32 KB; cada trozo lleva 7 bytes delante (suma de control, longitud y tipo: 1 entero, 2 primero,
            // 3 en medio, 4 último). Lo que no cabe al final de un bloque es relleno.
            var lote: [UInt8] = []
            var bloque = 0
            while bloque < b.count {
                let fin = min(bloque + 32_768, b.count)
                var i = bloque
                while i + 7 <= fin {
                    let largo = Int(b[i + 4]) | Int(b[i + 5]) << 8
                    let tipo = b[i + 6]
                    guard (1...4).contains(tipo), i + 7 + largo <= fin else { break }
                    let trozo = b[(i + 7)..<(i + 7 + largo)]
                    switch tipo {
                    case 1: aplicarLote(Array(trozo), &r)
                    case 2: lote = Array(trozo)
                    case 3: lote += trozo
                    default:
                        lote += trozo
                        aplicarLote(lote, &r)
                        lote = []
                    }
                    i += 7 + largo
                }
                bloque += 32_768
            }
        }
        return r
    }

    /// Un lote de escritura de LevelDB: número de secuencia (8 bytes), cuántas operaciones (4) y cada una: su tipo (1 alta,
    /// 0 baja), la clave y, en las altas, el valor, cada uno con su longitud delante (varint). Si algo no cuadra, se para.
    fileprivate static func aplicarLote(_ b: [UInt8], _ r: inout [String: String]) {
        var i = 12
        func varint() -> Int? {
            var v = 0
            var desplazamiento = 0
            while i < b.count && desplazamiento <= 28 {
                let x = b[i]
                i += 1
                v |= Int(x & 0x7f) << desplazamiento
                if x & 0x80 == 0 { return v }
                desplazamiento += 7
            }
            return nil
        }
        func texto() -> String? {
            guard let n = varint(), i + n <= b.count else { return nil }
            let s = String(decoding: b[i..<(i + n)], as: UTF8.self)
            i += n
            return s
        }
        guard b.count >= 12 else { return }
        while i < b.count {
            let tipo = b[i]
            i += 1
            guard tipo <= 1, let clave = texto() else { return }
            if tipo == 1 {
                guard let valor = texto() else { return }
                r[clave] = valor
            } else {
                r[clave] = nil
            }
        }
    }

    /// File System/Origins: de qué sitio es cada carpeta File System/<n> (claves «ORIGIN:https_sitio.com_0», valor «022»).
    fileprivate static func origenesDeFileSystem(_ carpeta: URL) -> [String: String] {
        var r: [String: String] = [:]
        for (clave, valor) in clavesDeLevelDB(carpeta) where clave.hasPrefix("ORIGIN:") && !valor.isEmpty {
            r[valor] = String(clave.dropFirst(7))
        }
        return r
    }

    /// «https_mail.example.com_0» o «https://mail.example.com/» → «mail.example.com».
    fileprivate static func nombreDeOrigen(_ origen: String) -> String {
        guard let esquema = origen.range(of: "://") else { return sitio(origen) }
        var s = String(origen[esquema.upperBound...])
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Las carpetas IndexedDB de cada sitio web (leveldb y blob juntas), por su origen («https_sitio.com_0»).
    fileprivate static func indexedDBPorOrigen(_ perfil: URL) -> [String: [URL]] {
        var porOrigen: [String: [URL]] = [:]
        for h in Rutas.hijos(perfil.appendingPathComponent("IndexedDB")) {
            let n = h.lastPathComponent
            guard n.hasPrefix("https_") || n.hasPrefix("http_"), let punto = n.range(of: ".indexeddb."), esCarpetaReal(h) else { continue }
            porOrigen[String(n[..<punto.lowerBound]), default: []].append(h)
        }
        return porOrigen
    }

    /// Los archivos de datos de un File System/<n>/t (sin su índice Paths ni .usage): si todos nacieron y cambiaron por
    /// última vez en una misma tanda de 10 minutos y nadie los leyó después (APFS apunta la primera lectura tras un
    /// cambio: su último acceso no pasa de la tanda más un minuto), cuándo empezó y acabó. Nil si no, si hay un enlace o
    /// si hay demasiados archivos para mirarlos.
    fileprivate static func tandaUnica(_ t: URL) -> (inicio: Date, fin: Date, archivos: Int)? {
        guard let e = FileManager.default.enumerator(at: t, includingPropertiesForKeys: nil, options: []) else { return nil }
        var inicio = Date.distantFuture
        var fin = Date.distantPast
        var lectura = Date.distantPast
        var archivos = 0
        for case let u as URL in e {
            if e.level == 1 && u.lastPathComponent == "Paths" { e.skipDescendants(); continue }
            var st = stat()
            guard lstat(u.path, &st) == 0 else { return nil }
            let tipo = st.st_mode & S_IFMT
            if tipo == S_IFDIR { continue }
            guard tipo == S_IFREG, archivos < 5_000 else { return nil }
            if u.lastPathComponent == ".usage" { continue }
            guard let f = fechas(u) else { return nil }
            archivos += 1
            inicio = min(inicio, f.nace, f.cambia)
            fin = max(fin, f.cambia)
            lectura = max(lectura, f.lee)
        }
        guard archivos > 0, fin.timeIntervalSince(inicio) <= 600, lectura.timeIntervalSince(fin) <= 60 else { return nil }
        return (inicio, fin, archivos)
    }

    /// File System/<n>/t de un sitio que lo llenó de una vez y no volvió: ≥ 100 MB escritos en una sola tanda que nadie
    /// leyó después, sin cambios en 7 días o más (y hasta 60: lo más viejo ya va en «Datos temporales de sitios») ni en
    /// los demás datos de ese sitio (IndexedDB). Suele ser el paquete de datos de un juego o una app web. Uno por sitio,
    /// con su nombre si se sabe (File System/Origins o, si no, el único IndexedDB que nació a la vez). Revisar, sin marcar.
    fileprivate func datosDeUnaVisita(_ raiz: RaizChromium, _ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let ahora = Date()
        for (perfil, etiqueta) in Self.perfiles(de: raiz) {
            let fs = perfil.appendingPathComponent("File System")
            let numeradas = Rutas.hijos(fs).filter { $0.lastPathComponent.allSatisfy(\.isNumber) && Self.esCarpetaReal($0) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !numeradas.isEmpty else { continue }
            let origenes = Self.origenesDeFileSystem(fs.appendingPathComponent("Origins"))
            let idb = Self.indexedDBPorOrigen(perfil)
            for n in numeradas {
                let t = n.appendingPathComponent("t")
                guard Self.esCarpetaReal(t) else { continue }
                let bytes = Self.ocupa(t, c)
                guard bytes >= 100_000_000, let cambio = Self.cambioDentro(t, c) else { continue }
                let dias = ahora.timeIntervalSince(cambio) / 86400
                guard dias >= 7, dias <= 60, let tanda = Self.tandaUnica(t) else { continue }
                // De qué sitio es: lo que dice Origins o, si no, el único IndexedDB que nació a la vez (±10 s).
                var origen = origenes[n.lastPathComponent]
                let porFecha = origen == nil
                if origen == nil, let nace = Self.fechas(n)?.nace {
                    let aLaVez = idb.filter { _, rutas in
                        rutas.contains { u in Self.fechas(u).map { abs($0.nace.timeIntervalSince(nace)) <= 10 } ?? false }
                    }
                    if aLaVez.count == 1 { origen = aLaVez.first?.key }
                }
                // Si sus otros datos cambiaron después, el sitio volvió: no es de una sola visita.
                if let origen, let rutas = idb[origen] {
                    let fechas = rutas.map { Self.cambioDentro($0, c) }
                    guard !fechas.contains(where: { $0 == nil }),
                          (fechas.compactMap { $0 }.max() ?? .distantPast) <= cambio.addingTimeInterval(3600) else { continue }
                }
                let sitio = origen.map(Self.nombreDeOrigen)
                let quien = sitio.map { porFecha ? "un sitio (seguramente \($0))" : $0 } ?? "un sitio"
                let formato = DateFormatter()
                formato.locale = Locale(identifier: "es_PE")
                formato.dateFormat = "d 'de' MMMM 'a las' H:mm"
                let dia = formato.string(from: tanda.inicio)
                r.append(Elemento(
                    nombre: "Archivos de una sola visita a \(quien) en \(raiz.nombre)\(etiqueta)",
                    detalle: "\(Formato.bytes(bytes)) que \(quien) guardó con la File System API el \(dia), todo en unos minutos (\(tanda.archivos) \(tanda.archivos == 1 ? "archivo" : "archivos")), y que nadie ha vuelto a leer ni a cambiar desde hace \(Int(dias)) días. Suele ser el paquete de datos que descarga un juego o una app web para funcionar.",
                    consecuencia: "Si vuelves a \(sitio ?? "ese sitio"), lo descargará otra vez si lo necesita. Si guardaba ahí algo tuyo que no está en otra parte (una partida, un documento de una app web), se pierde.",
                    rutas: [t], tamanosRutas: [bytes], ultimoUso: cambio, categoria: .cachesApps, riesgo: .revisar,
                    motivos: [.aviso("externaldrive.badge.exclamationmark", "Archivos de una web",
                                     "No es caché: es lo que guardó \(quien) en \(raiz.nombre). Lo enseño porque se escribió de una vez y nadie lo ha vuelto a tocar, pero no puedo ver qué es. También se puede borrar desde los ajustes de datos de sitios de \(raiz.nombre).")],
                    enUso: raiz.uso, dueno: raiz.nombre))
            }
        }
        return r
    }

    /// Las bases IndexedDB de un sitio que guardan mucho (≥ 100 MB) y no cambian desde hace 45 días o más (lo de más de
    /// 60 días ya va en «Datos de sitios sin usar»): una por sitio, Revisar y sin marcar, porque son datos del sitio
    /// (proyectos, archivos para usarlo sin conexión), que a veces también están en tu cuenta y a veces no.
    fileprivate func sitiosGrandesQuietos(_ raiz: RaizChromium, _ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let ahora = Date()
        for (perfil, etiqueta) in Self.perfiles(de: raiz) {
            for (origen, rutas) in Self.indexedDBPorOrigen(perfil).sorted(by: { $0.key < $1.key }) {
                let fechas = rutas.map { Self.cambioDentro($0, c) }
                guard !fechas.contains(where: { $0 == nil }), let fecha = fechas.compactMap({ $0 }).max() else { continue }
                let dias = ahora.timeIntervalSince(fecha) / 86400
                let tamanos = rutas.map { Self.ocupa($0, c) }
                let bytes = tamanos.reduce(0, +)
                guard dias >= 45, dias <= 60, bytes >= 100_000_000 else { continue }
                let sitio = Self.nombreDeOrigen(origen)
                r.append(Elemento(
                    nombre: "Datos de \(sitio) en \(raiz.nombre)\(etiqueta)",
                    detalle: "\(Formato.bytes(bytes)) que \(sitio) guardó en \(raiz.nombre) (IndexedDB) y que no cambian desde hace \(Int(dias)) días.",
                    consecuencia: "\(sitio) pierde lo que guardaba en \(raiz.nombre): puede cerrarse tu sesión y perderse lo que tenía para funcionar sin conexión. Si también está en tu cuenta de \(sitio), lo vuelve a descargar al usarlo; si solo estaba aquí, se pierde.",
                    rutas: rutas, tamanosRutas: tamanos, ultimoUso: fecha, categoria: .cachesApps, riesgo: .revisar,
                    motivos: [.aviso("person.crop.circle.badge.exclamationmark", "Datos de un sitio",
                                     "No es caché: son datos que \(sitio) guardó en \(raiz.nombre) (proyectos, archivos, mensajes sin enviar…). Bórralos solo si ya no usas \(sitio) o sabes que lo tienes en su nube.")],
                    enUso: raiz.uso, dueno: raiz.nombre))
            }
        }
        return r
    }

    // MARK: Iconos, extensiones, cachés pequeñas y copias del perfil

    /// Favicons (con su -journal y su -wal) de un perfil cuando pasa de 20 MB: los iconos de las páginas de tu historial y
    /// de tus marcadores, que el navegador vuelve a bajar al visitarlas. Revisar, sin marcar, con el navegador cerrado.
    fileprivate func iconosDeSitios(_ raiz: RaizChromium, _ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        for (perfil, etiqueta) in Self.perfiles(de: raiz) {
            let base = perfil.appendingPathComponent("Favicons")
            guard Self.esArchivoReal(base) else { continue }
            let rutas = [base] + ["Favicons-journal", "Favicons-wal"].map { perfil.appendingPathComponent($0) }.filter(Self.esArchivoReal)
            let tamanos = rutas.map { Self.ocupa($0, c) }
            guard tamanos.reduce(0, +) >= 20_000_000 else { continue }
            r.append(Elemento(
                nombre: "Iconos de sitios de \(raiz.nombre)\(etiqueta)",
                detalle: "La base de datos con los iconos de las páginas de tu historial y de tus marcadores (Favicons).",
                consecuencia: "Los iconos del historial, de los marcadores y de la página de nueva pestaña salen en blanco hasta que vuelvas a visitar cada página. Tu historial y tus marcadores no se tocan.",
                rutas: rutas, tamanosRutas: tamanos, categoria: .cachesApps, riesgo: .revisar,
                motivos: [.info("photo.on.rectangle", "Se vuelven a descargar",
                                "\(raiz.nombre) la vuelve a crear vacía y baja cada icono al visitar la página. Los de marcadores que no visitas se quedan en blanco hasta que los abras.")],
                enUso: raiz.uso, dueno: raiz.nombre))
        }
        return r
    }

    /// «1.0.101_0» (la versión y un número que el navegador añade si ya existía la carpeta).
    fileprivate static func versionDeExtension(_ n: String) -> (version: String, n: Int)? {
        guard let guion = n.lastIndex(of: "_"), let numero = Int(n[n.index(after: guion)...]) else { return nil }
        let v = String(n[..<guion])
        return esVersion(v) ? (v, numero) : nil
    }

    /// Las versiones de cada extensión a las que apunta la configuración del perfil (Preferences y Secure Preferences:
    /// extensions.settings.<id> y lo que haya dentro con «path», también una instalación aplazada). Nil si no se pudo
    /// leer ninguna de las dos.
    fileprivate static func versionesEnUso(_ perfil: URL) -> (porID: [String: Set<String>], escrita: Date)? {
        var r: [String: Set<String>] = [:]
        var escrita = Date.distantPast
        var leida = false
        func rutas(_ v: Any, _ acumuladas: inout Set<String>) {
            if let d = v as? [String: Any] {
                for (k, x) in d {
                    if k == "path", let s = x as? String, !s.isEmpty { acumuladas.insert(Rutas.nombre(s)) } else { rutas(x, &acumuladas) }
                }
            } else if let a = v as? [Any] {
                for x in a { rutas(x, &acumuladas) }
            }
        }
        for nombre in ["Preferences", "Secure Preferences"] {
            let u = perfil.appendingPathComponent(nombre)
            guard let j = json(u), let f = fechas(u) else { continue }
            leida = true
            escrita = max(escrita, f.cambia)
            guard let ajustes = (j["extensions"] as? [String: Any])?["settings"] as? [String: Any] else { continue }
            for (id, v) in ajustes {
                var s = r[id] ?? []
                rutas(v, &s)
                r[id] = s
            }
        }
        return leida ? (r, escrita) : nil
    }

    /// Extensions/<id>/<versión>_<n>: al actualizar una extensión con el navegador abierto, la versión anterior se queda
    /// hasta que se vuelve a abrir. Se ofrecen las versiones más viejas que la que dice su configuración (que tiene que
    /// estar completa, con manifest.json), nunca una a la que apunte (tampoco una instalación aplazada), y solo si la
    /// configuración se escribió después de crearse todas (si no, puede no saber aún de la nueva) y llevan 1 h quietas.
    /// La vieja ya no la carga nadie: no hace falta cerrar el navegador (si algo la tiene abierta, me la salto).
    fileprivate func versionesViejasDeExtensiones(_ raiz: RaizChromium, _ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let ahora = Date()
        for (perfil, etiqueta) in Self.perfiles(de: raiz) {
            let carpeta = perfil.appendingPathComponent("Extensions")
            guard Self.esCarpetaReal(carpeta), let enUso = Self.versionesEnUso(perfil) else { continue }
            var viejas: [URL] = []
            var nombres: [String] = []
            for ext in Rutas.hijos(carpeta) where ext.lastPathComponent.count == 32
                && ext.lastPathComponent.allSatisfy({ ("a"..."p").contains($0) }) && Self.esCarpetaReal(ext) {
                let id = ext.lastPathComponent
                let lista = Rutas.hijos(ext).filter { Self.esCarpetaReal($0) && Self.versionDeExtension($0.lastPathComponent) != nil }
                guard lista.count > 1, let usadas = enUso.porID[id], !usadas.isEmpty else { continue }
                let actuales = lista.filter { usadas.contains($0.lastPathComponent) }
                guard !actuales.isEmpty, actuales.allSatisfy({ Self.esArchivoReal($0.appendingPathComponent("manifest.json")) }),
                      lista.allSatisfy({ Self.fechas($0).map { $0.nace < enUso.escrita } ?? false }) else { continue }
                func orden(_ u: URL) -> (String, Int) { Self.versionDeExtension(u.lastPathComponent) ?? ("0", 0) }
                func menor(_ a: URL, _ b: URL) -> Bool {
                    let (va, na) = orden(a), (vb, nb) = orden(b)
                    let comp = va.compare(vb, options: .numeric)
                    return comp == .orderedAscending || (comp == .orderedSame && na < nb)
                }
                guard let actual = actuales.max(by: menor) else { continue }
                let sobran = lista.filter { v in
                    !usadas.contains(v.lastPathComponent) && menor(v, actual)
                        && (Self.cambioDentro(v, c).map { ahora.timeIntervalSince($0) > 3600 } ?? false)
                }
                guard !sobran.isEmpty else { continue }
                viejas += sobran
                let nombre = Self.nombreDeExtension(actual) ?? "\(id.prefix(6))…"
                nombres.append("\(nombre) \(Formato.lista(sobran.map { orden($0).0 }))")
            }
            guard !viejas.isEmpty else { continue }
            let tamanos = viejas.map { Self.ocupa($0, c) }
            r.append(Elemento(
                nombre: "Versiones viejas de extensiones de \(raiz.nombre)\(etiqueta)",
                detalle: "Versiones anteriores de extensiones que \(raiz.nombre) ya actualizó y que borra la próxima vez que se abre: \(Formato.listaCorta(nombres, maximo: 4)).",
                consecuencia: "Nada: las extensiones siguen igual, con la versión nueva y con sus ajustes y datos, que están en otra carpeta.",
                rutas: viejas, tamanosRutas: tamanos, ultimoUso: Self.ultimoCambio(viejas, c),
                categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("clock.arrow.circlepath", "Versión anterior",
                                "La configuración de \(raiz.nombre) dice que usa una versión más nueva de cada una, que está completa al lado y no se toca. La vieja ya no la carga nadie.")],
                dueno: raiz.nombre, cambioAnalizado: Self.ultimoCambio(viejas, c)))
        }
        return r
    }

    /// El nombre de una extensión, de su manifest.json (si no es un «__MSG_…__» que haya que traducir).
    fileprivate static func nombreDeExtension(_ version: URL) -> String? {
        guard let n = json(version.appendingPathComponent("manifest.json"), maximo: 1_000_000)?["name"] as? String,
              !n.isEmpty, !n.hasPrefix("__MSG_") else { return nil }
        return n
    }

    /// Cachés de un perfil que no tienen el nombre de siempre y por eso no salen en «Caché interna»: los diccionarios de
    /// compresión (Shared Dictionary), las extensiones a medio descargar (Webstore Downloads) y la caché de los service
    /// workers del almacenamiento por sitio nuevo (WebStorage/<n>/CacheStorage). Solo en perfiles de Chromium de verdad.
    fileprivate func cachesPequenas(_ raiz: RaizChromium, _ c: Contexto) -> [Elemento] {
        let vistas = Set(c.indice.cachesInternas.map(\.ruta))
        var rutas: [URL] = []
        for (perfil, _) in Self.perfiles(de: raiz) where Self.esPerfilChromium(perfil) {
            rutas += ["Shared Dictionary", "Webstore Downloads"].map { perfil.appendingPathComponent($0) }
            for b in Rutas.hijos(perfil.appendingPathComponent("WebStorage"))
            where b.lastPathComponent.allSatisfy(\.isNumber) && Self.esCarpetaReal(b) {
                rutas.append(b.appendingPathComponent("CacheStorage"))
            }
        }
        rutas = rutas.filter { Self.esCarpetaReal($0) && !vistas.contains($0.path) && !Totales.dentroDe($0.path, vistas) }
        guard !rutas.isEmpty else { return [] }
        let tipos = Array(Set(rutas.map { $0.lastPathComponent })).sorted()
        return [Elemento(
            nombre: "Otras cachés de \(raiz.nombre)",
            detalle: "Cachés que \(raiz.nombre) guarda junto a tus datos con nombres poco claros (\(Formato.lista(tipos))): diccionarios para descomprimir páginas, extensiones a medio descargar y la caché de las webs que funcionan sin conexión.",
            consecuencia: "\(raiz.nombre) las vuelve a crear. Algunas webs tardan un poco más la primera vez. Tus datos, sesiones y ajustes no se tocan.",
            rutas: rutas, tamanosRutas: rutas.map { Self.ocupa($0, c) }, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
            motivos: [.bien("arrow.triangle.2.circlepath", "Solo cachés", "Son cachés con otro nombre: \(raiz.nombre) las rehace sola.")],
            enUso: raiz.uso, dueno: raiz.nombre)]
    }

    /// <raíz>/Snapshots/<versión>: copias del perfil (historial, marcadores, ajustes) que el navegador guarda al pasar a
    /// una versión grande, por si hubiera que volver atrás. Las de versiones anteriores a la que tienes («Last Version»)
    /// solo sirven para volver a esas versiones. Revisar, sin marcar: son copias de tus datos de entonces.
    fileprivate func copiasDelPerfil(_ raiz: RaizChromium, _ c: Contexto) -> [Elemento] {
        guard !raiz.electron else { return [] }
        let ultima = raiz.raiz.appendingPathComponent("Last Version")
        var st = stat()
        guard lstat(ultima.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size < 64,
              let datos = FileManager.default.contents(atPath: ultima.path),
              let actual = String(data: datos, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), Self.esVersion(actual) else { return [] }
        let viejas = Self.versiones(en: raiz.raiz.appendingPathComponent("Snapshots"))
            .filter { $0.lastPathComponent.compare(actual, options: .numeric) == .orderedAscending }
        guard !viejas.isEmpty else { return [] }
        return [Elemento(
            nombre: "Copias del perfil de versiones anteriores de \(raiz.nombre)",
            detalle: "Copias de tu perfil que \(raiz.nombre) guardó al actualizarse, por si había que volver a la versión \(Formato.lista(viejas.map(\.lastPathComponent))). Ahora tienes la \(actual).",
            consecuencia: "Ya no podrías volver a esas versiones con tus datos de entonces. Tu perfil de ahora no se toca.",
            rutas: viejas, tamanosRutas: viejas.map { Self.ocupa($0, c) }, categoria: .cachesApps, riesgo: .revisar,
            motivos: [.info("clock.arrow.circlepath", "Copias de seguridad viejas",
                            "Son copias de tus datos de antes de actualizar \(raiz.nombre). Si todo funciona bien con la versión de ahora, ya no hacen falta.")],
            enUso: raiz.uso, dueno: raiz.nombre)]
    }

    // MARK: Cliente Tor

    /// Las versiones del cliente Tor de Brave (componente con el programa «tor-…-darwin-brave-…») que tienen detrás una más
    /// nueva y completa (con manifest.json y su programa) y que no está funcionando: las ofrece «Versiones viejas de
    /// componentes»; `clienteTorDeBrave` ofrece solo la actual.
    static func versionesViejasDeTor(_ comp: URL, _ c: Contexto) -> [URL] {
        let lista = versiones(en: comp)
        guard lista.count > 1, let nueva = lista.last, esArchivoReal(nueva.appendingPathComponent("manifest.json")),
              Rutas.hijos(nueva).contains(where: { f in
                  let n = f.lastPathComponent
                  return esArchivoReal(f) && patronTorBrave.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
              }) else { return [] }
        return lista.dropLast().filter { v in !c.procesos.lineas.contains { $0.contains(v.path.lowercased() + "/") } }
    }

    // MARK: Actualización pendiente

    /// La app instalada de un navegador: en Aplicaciones, en tu carpeta de Aplicaciones o la que está abierta.
    fileprivate static func appDelNavegador(id: String, nombre: String, _ c: Contexto) -> URL? {
        let buscado = id.lowercased()
        let candidatas = (c.apps.rutasEnAplicaciones[buscado] ?? []).map { URL(fileURLWithPath: $0) }
            + [Rutas.enHome("Applications/\(nombre).app")]
            + c.procesos.apps.filter { $0.bundleID == buscado }.compactMap(\.url)
        return candidatas.first { Self.esCarpetaReal($0) && Bundle(url: $0)?.bundleIdentifier?.lowercased() == buscado }
    }

    /// Una app descargada entera (con Info.plist y su firma, _CodeSignature/CodeResources), hasta `nivel` carpetas dentro.
    fileprivate static func appCompleta(en u: URL, nivel: Int) -> URL? {
        guard esCarpetaReal(u) else { return nil }
        if u.pathExtension == "app" {
            let dentro = u.appendingPathComponent("Contents")
            return esArchivoReal(dentro.appendingPathComponent("Info.plist"))
                && esArchivoReal(dentro.appendingPathComponent("_CodeSignature/CodeResources")) ? u : nil
        }
        guard nivel > 0 else { return nil }
        for h in Rutas.hijos(u) { if let a = appCompleta(en: h, nivel: nivel - 1) { return a } }
        return nil
    }

    /// Una actualización del navegador que espera a que lo reinicies. No es basura (si se borra, la vuelve a descargar y
    /// sigues con la versión vieja): solo se informa, como nota, de lo que se libera al reiniciarlo.
    /// - Sparkle (Brave, Vivaldi, Arc): la descarga entera y quieta 10 minutos en Caches/<id>/org.sparkle-project.Sparkle,
    ///   más nueva que la instalada y sin su instalador funcionando. Al cerrar el navegador la instala y borra la descarga.
    /// - Chrome y Edge la instalan dentro de la app, al lado de la que está funcionando: si algo abierto sigue usando una
    ///   versión que no es la de la app, al reiniciar pasa a la nueva y la vieja la quita su actualizador.
    fileprivate func anotarActualizacionPendiente(_ raiz: RaizChromium, id: String, _ c: Contexto) {
        guard let app = Self.appDelNavegador(id: id, nombre: raiz.nombre, c), let info = Bundle(url: app)?.infoDictionary,
              let suVersion = info["CFBundleVersion"] as? String else { return }
        let suCorta = info["CFBundleShortVersionString"] as? String ?? suVersion
        let sparkle = Rutas.enHome("Library/Caches/\(id)/org.sparkle-project.Sparkle")
        let descargas = ["PersistentDownloads", "Installation"].flatMap { Rutas.hijos(sparkle.appendingPathComponent($0)) }
            .filter(Self.esCarpetaReal)
        if !descargas.isEmpty, c.procesos.actualizadorEnMarcha(id: id, ruta: app.path) == nil,
           let quieta = Fechas.masRecienteDentro(sparkle), Date().timeIntervalSince(quieta) > 600,
           let nueva = descargas.lazy.compactMap({ Self.appCompleta(en: $0, nivel: 3) }).first,
           let suya = Bundle(url: nueva)?.infoDictionary, Bundle(url: nueva)?.bundleIdentifier?.lowercased() == id.lowercased(),
           let version = suya["CFBundleVersion"] as? String, version.compare(suVersion, options: .numeric) == .orderedDescending {
            let corta = suya["CFBundleShortVersionString"] as? String ?? version
            let bytes = descargas.reduce(Int64(0)) { $0 + c.indice.bytes(de: $1) }
            c.indice.notas.append(NotaGrande(
                categoria: .cachesApps, titulo: "\(raiz.nombre) \(corta) espera a que lo reinicies",
                texto: "\(raiz.nombre) ya descargó la versión \(corta) (tienes la \(suCorta)) y la instala cuando lo cierras del todo (⌘Q). Al instalarla borra la descarga: cuando lo vuelvas a abrir habrás liberado unos \(Formato.bytes(bytes)). No hace falta borrarla a mano: si la borras, \(raiz.nombre) la vuelve a descargar y sigues con la versión vieja.",
                ruta: sparkle.path, bytes: bytes))
        }
        // La versión nueva ya está dentro de la app (Chrome, Edge…) y lo que tienes abierto sigue con la anterior.
        let marcos = Rutas.hijos(app.appendingPathComponent("Contents/Frameworks")).filter { $0.pathExtension == "framework" && Self.esCarpetaReal($0) }
        for marco in marcos {
            let lista = Self.versiones(en: marco.appendingPathComponent("Versions"))
            guard lista.count > 1, lista.contains(where: { $0.lastPathComponent == suCorta }) else { continue }
            let viejas = lista.filter { v in
                v.lastPathComponent != suCorta && c.procesos.programas.contains { $0.ruta.hasPrefix(v.path + "/") }
            }
            guard !viejas.isEmpty else { continue }
            let bytes = viejas.reduce(Int64(0)) { $0 + Tamanos.recorriendo($1.path) }
            c.indice.notas.append(NotaGrande(
                categoria: .cachesApps, titulo: "\(raiz.nombre) se actualizó a la \(suCorta) y sigue abierto con la anterior",
                texto: "La versión nueva ya está instalada, pero lo que tienes abierto sigue con la \(Formato.lista(viejas.map(\.lastPathComponent))), que ocupa \(Formato.bytes(bytes)) dentro de la app. Reinicia \(raiz.nombre) para pasar a la nueva; la anterior la quita su actualizador cuando ya no la usa nadie. No la ofrezco para borrar: está dentro de la app y en uso.",
                ruta: viejas[0].path, bytes: bytes))
        }
    }

    // MARK: - Navegadores desinstalados

    /// Navegadores que no se analizan instalados pero dejan restos igual.
    fileprivate static let otrosNavegadoresChromium: [(rel: String, nombre: String, id: String)] = [
        ("Google/Chrome Dev", "Chrome Dev", "com.google.Chrome.dev"),
        ("Google/Chrome for Testing", "Chrome for Testing", "com.google.chrome.for.testing"),
    ]

    /// En la raíz de un navegador, lo que descargó o creó por su cuenta y no es tuyo: componentes, listas, cachés de la
    /// GPU, informes de fallos y métricas. (Los componentes de `componentesQueVuelven` y `componentesConVersiones`, los
    /// de 32 letras y las carpetas que solo tienen versiones también cuentan.)
    fileprivate static let restosConocidos: Set<String> = [
        "Crashpad", "BrowserMetrics", "component_crx_cache", "extensions_crx_cache", "GrShaderCache", "ShaderCache",
        "GraphiteDawnCache", "GPUPersistentCache", "DawnGraphiteCache", "DawnWebGPUCache", "Subresource Filter",
        "OptimizationGuideModelsManifest", "optimization_guide_model_store", "SODA", "SODALanguagePacks", "RecoveryImproved",
        "CaptchaProviders", "ActorSafetyLists", "MaskedDomainListPreloaded", "Webstore Downloads",
    ]
    fileprivate static let archivosConocidos: Set<String> = [
        "Last Version", "Last Browser", "First Run", "Variations", "VariationsSeedV2", "VariationsSafeSeedV2",
        "ChromeFeatureState", "first_party_sets.db", "first_party_sets.db-journal", "Module Info Cache",
    ]

    /// Si el navegador sigue en este Mac: instalado (en cualquier carpeta que se mire), abierto o, Chrome for Testing y
    /// Chromium, descargados por Puppeteer, Playwright o Selenium. Fuera de las pruebas también se pregunta al sistema
    /// (LaunchServices), que conoce las apps de otros discos y carpetas.
    fileprivate static func navegadorPresente(id: String, nombre: String, _ c: Contexto) -> Bool {
        if c.apps.bundleIDs.contains(id.lowercased()) || appDelNavegador(id: id, nombre: nombre, c) != nil { return true }
        if c.procesos.quienUsa(.app(nombre: nombre, claves: [id, nombre])) != nil { return true }
        if c.procesos.lineas.contains(where: { $0.contains("/\(nombre.lowercased()).app/") || $0.contains("/google \(nombre.lowercased()).app/") }) { return true }
        let descargados: [String]
        switch id {
        // Playwright (desde la 1.57) y Selenium Manager también bajan Chrome for Testing, cada uno a su caché.
        case "com.google.chrome.for.testing":
            descargados = [".cache/puppeteer/chrome", ".cache/puppeteer/chrome-headless-shell", "Library/Caches/ms-playwright",
                           ".cache/ms-playwright", ".cache/selenium/chrome"]
        case "org.chromium.Chromium": descargados = ["Library/Caches/ms-playwright", ".cache/ms-playwright", ".cache/puppeteer/chromium"]
        default: descargados = []
        }
        if descargados.contains(where: { !Rutas.hijos(Rutas.enHome($0)).filter { !$0.lastPathComponent.hasPrefix(".") }.isEmpty }) { return true }
        return !Rutas.casaDePrueba && NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    /// La raíz de un navegador desinstalado, repartida: lo que no es tuyo (componentes, cachés, informes…) y el perfil
    /// (Default, Profile N, Guest Profile, System Profile, sus copias en Snapshots y Local State). Lo que no se reconoce
    /// no se toca, ni NativeMessagingHosts (lo instalan otras apps para hablar con el navegador) ni el modelo de IA
    /// (OptGuideOnDeviceModel, que ya ofrece `modelosIADeNavegadores`).
    /// Si la raíz es ella misma un perfil (Opera guarda ahí Preferences, Cookies, History…, junto a sus componentes),
    /// solo cuenta lo que tiene un nombre conocido: ahí una carpeta vacía, de 32 letras o con solo carpetas de cifras
    /// puede ser de datos de sitios (WebStorage/<n>, con su IndexedDB). Y el perfil no se ofrece: sus archivos van sueltos
    /// en la raíz, mezclados con lo demás, y solo saldría su Local State.
    fileprivate static func repartirRestos(_ raiz: URL) -> (componentes: [URL], perfil: [URL], perfiles: [String]) {
        let componentes = Set(componentesQueVuelven.map(\.carpeta)).union(componentesConVersiones).union(restosConocidos)
        let raizEsPerfil = esArchivoReal(raiz.appendingPathComponent("Preferences"))
        var r: (componentes: [URL], perfil: [URL], perfiles: [String]) = ([], [], [])
        for h in Rutas.hijos(raiz).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let n = h.lastPathComponent
            if esCarpetaReal(h) {
                let numerado = n.hasPrefix("Profile ") && n.count > 8 && n.dropFirst(8).allSatisfy(\.isNumber)
                if n == "Default" || n == "Guest Profile" || n == "System Profile" || numerado || n == "Snapshots" {
                    r.perfil.append(h)
                    if n != "Snapshots" && n != "System Profile" { r.perfiles.append(n) }
                    continue
                }
                if n == "NativeMessagingHosts" || n == "OptGuideOnDeviceModel" { continue }
                let hijos = Rutas.hijos(h).filter { $0.lastPathComponent != ".DS_Store" }
                let esComponente = componentes.contains(n) || (!raizEsPerfil && ((n.count == 32 && n.allSatisfy { ("a"..."p").contains($0) })
                    || hijos.isEmpty || hijos.allSatisfy { esVersion($0.lastPathComponent) && esCarpetaReal($0) }))
                if esComponente { r.componentes.append(h) }
            } else if esArchivoReal(h) {
                if n == "Local State" { r.perfil.append(h) }
                else if archivosConocidos.contains(n) || h.pathExtension == "pma" { r.componentes.append(h) }
            }
        }
        if raizEsPerfil { r.perfil = []; r.perfiles = [] }
        return r
    }

    /// Una ruta de ~/Library/<lugar>/<nombre> que «Restos de apps borradas» no ofrece porque la da por instalada (el
    /// mismo fabricante que otra app tuya, como com.google.Chrome con Android Studio): entonces va aquí.
    fileprivate static func protegidaPorFabricante(_ rel: String, _ c: Contexto) -> URL? {
        let u = Rutas.enHome(rel)
        var st = stat()
        guard lstat(u.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR || (st.st_mode & S_IFMT) == S_IFREG,
              c.apps.estaInstalado(carpeta: u.lastPathComponent) else { return nil }
        return u
    }

    /// El actualizador de Google (GoogleUpdater y el Keystone de antes) cuando ya no queda nada que lo use: ni Chrome en
    /// ningún canal, ni otra app de Google que se actualice con él (las que llevan KSProductID en su Info.plist, como
    /// Drive o Earth), ni nada instalado en su lista de productos (GoogleSoftwareUpdate/Actives), ni su programa (se
    /// desinstala solo al quedarse sin productos y deja sus registros), ni él funcionando.
    fileprivate static func restosDelActualizadorDeGoogle(_ c: Contexto) -> [URL] {
        let conActualizador = ["com.google.chrome", "com.google.drivefs", "com.google.googledrive", "com.google.googleearthpro",
                               "com.google.earthpro", "com.google.backupandsync", "com.google.chromeremotedesktop"]
        for id in c.apps.bundleIDs where id.hasPrefix("com.google.") && id != "com.google.chrome.for.testing" {
            if conActualizador.contains(where: { id == $0 || id.hasPrefix($0 + ".") }) { return [] }
            if (c.apps.rutasEnAplicaciones[id] ?? []).contains(where: { Bundle(path: $0)?.infoDictionary?["KSProductID"] != nil }) { return [] }
        }
        let updater = Rutas.enHome("Library/Application Support/Google/GoogleUpdater")
        let keystone = Rutas.enHome("Library/Google/GoogleSoftwareUpdate")
        let productos = Rutas.hijos(keystone.appendingPathComponent("Actives")).map { $0.lastPathComponent.lowercased() }
        if productos.contains(where: { c.apps.bundleIDs.contains($0) }) { return [] }
        if Rutas.hijos(updater).contains(where: { esCarpetaReal($0) && Rutas.existe($0.appendingPathComponent("GoogleUpdater.app")) })
            || Rutas.existe(keystone.appendingPathComponent("GoogleSoftwareUpdate.bundle")) { return [] }
        let programas: Set<String> = ["googleupdater", "googlesoftwareupdateagent", "googlesoftwareupdatedaemon", "ksinstall", "ksadmin"]
        if c.procesos.programas.contains(where: { programas.contains($0.nombre) }) { return [] }
        var r = [updater, Rutas.enHome("Library/Application Support/Google/RLZ"), keystone].filter(esCarpetaReal)
        // Sus cachés (Caches/com.google.GoogleUpdater y com.google.Keystone) no: con el fabricante instalado ya las ofrece
        // «Caché de …» (`cachesApps`), y saldrían dos veces.
        r += ["Library/HTTPStorages/com.google.GoogleUpdater",
              "Library/Preferences/com.google.Keystone.Agent.plist", "Library/Preferences/com.google.GoogleUpdater.plist"]
            .compactMap { protegidaPorFabricante($0, c) }
        return r
    }

    /// Lo que deja un navegador Chromium que ya no está (en ningún canal que se pueda reconocer), cuando lleva 14 días o
    /// más sin cambios: lo que descargó por su cuenta y, si es de Google, su actualizador (Seguro: no es nada tuyo) y,
    /// aparte, tu perfil (Cuidado: historial, marcadores, contraseñas). «Restos de apps borradas» no lo ve cuando la
    /// carpeta es de un fabricante con otras apps instaladas (Google con Android Studio, Microsoft con Office); si no, ya
    /// la ofrece entera y aquí no se repite. Tampoco lo que ya ofrecen «Caché interna» y «Registros internos» (las cachés y
    /// los registros con nombre de siempre de esa misma carpeta, que también la dan por instalada). Si algo cambia después
    /// del análisis (lo has vuelto a instalar), no se toca (`cambioAnalizado`).
    func restosDeNavegadores(_ c: Contexto) -> [Elemento] {
        let appSupport = Rutas.enHome("Library/Application Support")
        let ahora = Date()
        let internas = Set(c.indice.cachesInternas.map(\.ruta))
        var r: [Elemento] = []
        var conActualizador = false
        for (rel, nombre, id) in Self.navegadoresChromium + Self.otrosNavegadoresChromium {
            let raiz = appSupport.appendingPathComponent(rel)
            guard Self.esCarpetaReal(raiz), let primera = rel.split(separator: "/").first.map(String.init),
                  c.apps.estaInstalado(carpeta: primera), !Self.navegadorPresente(id: id, nombre: nombre, c) else { continue }
            let reparto = Self.repartirRestos(raiz)
            var componentes = reparto.componentes.filter { !internas.contains($0.path) && !Totales.dentroDe($0.path, internas) }
            if let plist = Self.protegidaPorFabricante("Library/Preferences/\(id).plist", c) { componentes.append(plist) }
            // De Google, su actualizador va con el primero de sus navegadores que se ofrezca.
            let actualizador = rel.hasPrefix("Google/") && !conActualizador ? Self.restosDelActualizadorDeGoogle(c) : []
            componentes += actualizador
            if !componentes.isEmpty, let fecha = Self.ultimoCambio(componentes, c), ahora.timeIntervalSince(fecha) >= 14 * 86400 {
                let carpetas = componentes.filter { $0.path.hasPrefix(raiz.path + "/") && Self.esCarpetaReal($0) }.map(\.lastPathComponent)
                r.append(Elemento(
                    nombre: "Restos de \(nombre)",
                    detalle: "Lo que \(nombre) descargó o creó por su cuenta y sigue aquí aunque ya no lo tienes\(carpetas.isEmpty ? "" : ": \(Formato.listaCorta(carpetas, maximo: 4))")\(actualizador.isEmpty ? "" : ", y lo que queda de su actualizador"). No es nada tuyo: tu perfil va aparte.",
                    consecuencia: "Nada: \(nombre) ya no está. Si lo vuelves a instalar, lo descarga otra vez.",
                    rutas: componentes, tamanosRutas: componentes.map { Self.ocupa($0, c) }, ultimoUso: fecha, categoria: .restos, riesgo: .seguro, seleccionado: true,
                    motivos: [.bien("questionmark.app.fill", "Navegador desinstalado",
                                    "No encontré \(nombre) en Aplicaciones ni abierto, y nada de esto cambia desde \(Formato.haceCuanto(fecha).lowercased()).")],
                    enUso: .app(nombre: nombre, claves: [id, nombre]), dueno: nombre, cambioAnalizado: fecha))
                if !actualizador.isEmpty { conActualizador = true }
            }
            if !reparto.perfil.isEmpty, let fecha = Self.ultimoCambio(reparto.perfil, c), ahora.timeIntervalSince(fecha) >= 14 * 86400 {
                let perfiles = reparto.perfiles.map { $0 == "Default" ? "el principal" : $0 }
                r.append(Elemento(
                    nombre: "Perfil de \(nombre) (ya no está instalado)",
                    detalle: "Tu perfil de \(nombre)\(perfiles.isEmpty ? "" : " (\(Formato.lista(perfiles)))"): historial, marcadores, contraseñas guardadas, cookies y ajustes.",
                    consecuencia: "Si vuelves a instalar \(nombre), empezará sin tu historial, tus marcadores ni tus contraseñas, salvo lo que tengas sincronizado con tu cuenta.",
                    rutas: reparto.perfil, tamanosRutas: reparto.perfil.map { Self.ocupa($0, c) }, ultimoUso: fecha, categoria: .restos, riesgo: .cuidado,
                    motivos: [.aviso("person.crop.circle.badge.exclamationmark", "Datos tuyos",
                                     "Puede ser la única copia de tus marcadores y contraseñas si no los sincronizaste con tu cuenta. Si quieres conservarlos, impórtalos antes desde otro navegador."),
                              .info("questionmark.app.fill", "Navegador desinstalado",
                                    "No encontré \(nombre) en Aplicaciones ni abierto. Se usó por última vez \(Formato.haceCuanto(fecha).lowercased()).")],
                    enUso: .app(nombre: nombre, claves: [id, nombre]), dueno: nombre, cambioAnalizado: fecha))
            }
        }
        return r
    }
}

extension AppsInstaladas {
    /// «TectonicProject.Tectonic»: un identificador cuyo último nombre es un comando que tienes instalado (una fórmula de
    /// Homebrew o un programa de tu PATH), como el «tectonic» de Homebrew. No valen los comandos del propio macOS ni los
    /// nombres cortos o genéricos. Para no tomar por resto la carpeta de una herramienta de la terminal.
    func esDeUnComando(carpeta: String) -> Bool {
        let partes = carpeta.split(separator: ".")
        guard partes.count >= 2, let ultima = partes.last else { return false }
        let n = Self.normalizar(String(ultima))
        let genericos: Set<String> = ["data", "cache", "caches", "logs", "plist", "savedstate", "binarycookies", "json", "sqlite",
                                      "backup", "helper", "agent", "daemon", "apps", "desktop", "browser", "client", "server",
                                      "service", "update", "updater", "installer", "shipit", "beta", "storage", "files"]
        guard n.count >= 4, !genericos.contains(n), comandos.contains(n) else { return false }
        return !["/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/libexec"].contains { FileManager.default.fileExists(atPath: "\($0)/\(n)") }
    }
}
