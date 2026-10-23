import Foundation

// Cachés, temporales, registros y restos de las apps y los servicios de Apple (también los aislados en Containers y
// Group Containers), de /var/folders (C, T y X), de Office y de Zoom. Nada de lo que ya ofrece otra regla (cachesDeApple,
// los adjuntos de Mail, las cachés de apps de terceros, los restos de apps borradas) se repite aquí.

extension Rutas {
    /// La carpeta X de /var/folders, junto a T y C. Los navegadores Chromium dejan ahí un clon de su app mientras funcionan
    /// («com.brave.Browser.code_sign_clone»). En las pruebas, la X de LIMPIADOR_TEMPORALES.
    static let clonesDeFirma: String? = temporalesDelSistema.first { $0.hasSuffix("/C") }.map { padre($0) + "/X" }

    /// Un clon de firma de esa carpeta X («<id>.code_sign_clone», con su ruta real): lo único de X que se puede borrar.
    static func esClonDeFirma(_ ruta: String) -> Bool {
        guard let x = clonesDeFirma, padre(ruta) == x else { return false }
        let n = nombre(ruta)
        return n.hasSuffix(".code_sign_clone") && n.count > ".code_sign_clone".count && !n.hasPrefix(".")
    }
}

extension Escaner {
    // MARK: - Ganchos de generar()

    /// «Cachés de aplicaciones»: lo de Apple aislado, en ~/Library/Caches y en sus grupos; los modelos compilados de
    /// builds viejos de macOS; Office y Zoom.
    func cachesDeAppleYOffice(_ c: Contexto) -> [Elemento] {
        let desinstaladas = Self.appsDeAppleDesinstaladas(c)
        var pequenas: [CachePequena] = []
        var r = cachesDeContenedoresDeApple(c, desinstaladas: desinstaladas, pequenas: &pequenas)
        r += cachesDeAppleEnLibrary(c, desinstaladas: desinstaladas, pequenas: &pequenas)
        r += cachesDeGruposDeApple(c, pequenas: &pequenas)
        if let el = cachesPequenasDeApple(pequenas) { r.append(el) }
        if let el = cachesPequenasEnMarcha(c) { r.append(el) }
        if let el = modelosDeBuildsAnteriores(c, desinstaladas: desinstaladas) { r.append(el) }
        r += cachesDeOffice(c)
        r += recursosDeZoom(c)
        return r
    }

    /// «Temporales del sistema»: cachés de Apple que se regeneran en C, librerías de Bun en T y clones de navegadores en X.
    func temporalesDeApple(_ c: Contexto) -> [Elemento] {
        cachesDeAppleEnC(c) + libreriasDeBun(c) + clonesDeNavegadores(c)
    }

    /// «Restos de apps borradas»: lo que dejan GarageBand, iMovie, Keynote… cuando ya no están.
    func restosDeAppsDeApple(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let contenedores = c.accesoTotal ? Rutas.hijos(Rutas.enHome("Library/Containers")) : []
        let scripts = Rutas.hijos(Rutas.enHome("Library/Application Scripts"))
        let preferencias = Rutas.hijos(Rutas.enHome("Library/Preferences")).filter { $0.pathExtension == "plist" }
        let estados = Rutas.hijos(Rutas.enHome("Library/Saved Application State"))
        let enC = Rutas.temporalesDelSistema.filter { $0.hasSuffix("/C") }
        let analiticasEnRegistros = analiticasLasOfreceRegistros(c)
        for app in Self.appsDeAppleDesinstaladas(c) {
            func suya(_ u: URL) -> Bool {
                let n = u.lastPathComponent.lowercased()
                return app.prefijos.contains { n.hasPrefix($0.lowercased()) }
            }
            let suyos = contenedores.filter { suya($0) && Self.esCarpetaPropia($0) }
            // Su caché: la de cada contenedor, la de ~/Library/Caches y la de /var/folders/…/C.
            var cache: [URL] = []
            for k in suyos {
                let u = k.appendingPathComponent("Data/Library/Caches")
                if Self.esCarpetaPropia(u), Self.estaDentro(u, de: k), !Rutas.hijos(u).isEmpty { cache.append(u) }
            }
            for n in app.caches {
                let u = Rutas.enHome("Library/Caches/\(n)")
                if Self.esCarpetaPropia(u) { cache.append(u) }
                cache += enC.map { URL(fileURLWithPath: $0 + "/" + n) }.filter(Self.esCarpetaPropia)
            }
            // Lo demás: sus contenedores enteros, sus ajustes y sus scripts. Application Support/<App> solo si «Restos»
            // no lo ofrece ya (lo hace cuando el nombre no casa con nada instalado).
            // Sus contenedores, sin la caché que va aparte (Seguro): si no, la caché saldría dos veces.
            var resto = suyos.flatMap { k -> [URL] in
                let suCache = k.appendingPathComponent("Data/Library/Caches")
                return cache.contains(suCache) ? Self.sinApartar(k, niveles: 3, apartar: { $0.path == suCache.path }) : [k]
            }
            for n in app.soporte {
                let u = Rutas.enHome("Library/Application Support/\(n)")
                if Self.esCarpetaPropia(u) && c.apps.estaInstalado(carpeta: n) { resto.append(u) }
            }
            resto += scripts.filter(suya) + preferencias.filter(suya) + estados.filter(suya)
                + Self.restosWebDeAppDeApple(app.prefijos, conAnaliticas: !analiticasEnRegistros)
            let uso = EnUso.app(nombre: app.nombre, claves: app.ids + [app.nombre])
            let tamanosCache = cache.map { Self.ocupa($0, c) }
            let noEsta = "No encontré \(app.buscada) en Aplicaciones, en ~/Applications ni entre los programas abiertos."
            if tamanosCache.reduce(0, +) > 0 {
                r.append(Elemento(
                    nombre: "Caché de \(app.nombre)",
                    detalle: app.varias == nil ? "Caché que dejó \(app.nombre), que ya no está instalada."
                                               : "Caché que dejaron \(app.nombre), que ya no están instaladas.",
                    consecuencia: app.varias == nil ? "Nada: \(app.nombre) ya no está. Si la vuelves a instalar, la crea de nuevo."
                                                    : "Nada: ya no están. Si vuelves a instalar alguna, la crea de nuevo.",
                    rutas: cache, tamanosRutas: tamanosCache, categoria: .restos, riesgo: .seguro, seleccionado: true,
                    motivos: [.bien("magnifyingglass", "No está instalada", noEsta)], enUso: uso, dueno: app.nombre))
            }
            guard !resto.isEmpty else { continue }
            // Un contenedor con documentos o autoguardados puede tener trabajo tuyo que no está en otra parte.
            let conDocumentos = suyos.contains { k in
                ["Data/Documents", "Data/Library/Autosave Information"].contains { rel in
                    Rutas.hijos(k.appendingPathComponent(rel)).contains { !$0.lastPathComponent.hasPrefix(".") }
                }
            }
            var motivos: [Motivo] = [.info("magnifyingglass", "No está instalada", noEsta)]
            if conDocumentos {
                motivos.append(.aviso("doc.richtext.fill", "Documentos dentro",
                                      "Su contenedor guarda documentos o autoguardados: puede ser trabajo tuyo que no está en otra parte."))
            }
            r.append(Elemento(
                nombre: app.varias == nil ? "\(app.nombre) (ya no está instalada)" : "Datos de \(app.nombre) (ya no están instaladas)",
                detalle: "Lo que \(app.varias == nil ? "dejó" : "dejaron") \(app.nombre): \(Formato.lista(Self.lugaresDeResto(resto))).",
                consecuencia: conDocumentos
                    ? "Se pierden los documentos y autoguardados que haya en su contenedor. Revísalos antes. Tus proyectos y bibliotecas de Películas o Música no se tocan."
                    : "Si vuelves a instalar \(app.varias == nil ? app.nombre : "alguna de ellas"), empezará sin tus ajustes. Tus proyectos y bibliotecas de Películas o Música no se tocan.",
                rutas: resto, tamanosRutas: resto.map { Self.ocupa($0, c) }, categoria: .restos,
                riesgo: conDocumentos ? .cuidado : .revisar, motivos: motivos, enUso: uso, dueno: app.nombre))
        }
        return r
    }

    /// «Registros y fallos»: los registros de las apps aisladas y de sus grupos, y la telemetría pendiente de Office.
    func registrosDeAppsAisladas(_ c: Contexto) -> [Elemento] {
        guard c.accesoTotal else { return [] }
        let desinstaladas = Self.appsDeAppleDesinstaladas(c)
        let deRestos = contenedoresDeProductosQueNoEstan(c)
        var lugares: [(nombre: String, uso: EnUso, carpetas: [URL], grupo: Bool)] = []
        for k in Rutas.hijos(Rutas.enHome("Library/Containers")) {
            let id = k.lastPathComponent
            // Lo de las apps desinstaladas lo ofrece entero «Restos de apps borradas».
            guard !id.hasPrefix("."), !Self.propios.contains(id), Self.esCarpetaPropia(k), !deRestos.contains(k.path),
                  !Self.esDeAppDesinstalada(id, desinstaladas), c.apps.estaInstalado(carpeta: id) else { continue }
            let logs = k.appendingPathComponent("Data/Library/Logs")
            guard Self.esCarpetaPropia(logs), Self.estaDentro(logs, de: k) else { continue }
            let deApple = id.lowercased().hasPrefix("com.apple.")
            let nombre = deApple ? Self.nombreDeServicio(id, c) : (c.apps.nombreApp(para: id) ?? Self.nombreCorto(id))
            lugares.append((nombre, deApple ? Self.usoDeServicio(id, nombre: nombre) : .app(nombre: nombre, claves: [id, nombre]),
                            [logs], false))
        }
        var deOffice: [URL] = []
        for g in Rutas.hijos(Rutas.enHome("Library/Group Containers")) {
            let id = g.lastPathComponent
            guard !id.hasPrefix("."), !Self.propios.contains(id), Self.esCarpetaPropia(g), !deRestos.contains(g.path),
                  c.apps.estaInstalado(carpeta: id) else { continue }
            let carpetas = ["Logs", "Library/Logs"].map { g.appendingPathComponent($0) }
                .filter { Self.esCarpetaPropia($0) && Self.estaDentro($0, de: g) }
            guard !carpetas.isEmpty else { continue }
            let base = Self.sinGrupo(id)
            let deApple = id.lowercased().contains("com.apple.")
            if AppsInstaladas.equipo(de: id) == Self.equipoDeOffice {
                deOffice += carpetas
            } else {
                let nombre = deApple ? Self.nombreDeServicio(id, c) : (c.apps.nombreApp(para: base) ?? Self.nombreCorto(base))
                lugares.append((nombre, deApple ? Self.usoDeServicio(id, nombre: nombre) : .app(nombre: nombre, claves: [base, nombre]),
                                carpetas, true))
            }
        }
        if !deOffice.isEmpty { lugares.append(("Microsoft Office", Self.usoDeOffice, deOffice, true)) }

        var r: [Elemento] = []
        // Lo que nadie tiene abierto y lleva 1 h sin cambios ya no se escribe: un registro rotado o de una sesión anterior.
        let haceUnaHora = Date().addingTimeInterval(-3600)
        var pequenos: [ArchivoDeRegistro] = []
        for l in lugares {
            let archivos = Self.archivosDeRegistro(l.carpetas)
            guard !archivos.isEmpty else { continue }
            // Con la app abierta, solo los de más de 1 h que nadie tiene abiertos: los recientes los puede estar escribiendo.
            let abierta = c.procesos.quienUsa(l.uso) != nil
            let viejos = archivos.filter { $0.fecha < haceUnaHora && c.procesos.abiertos.hayAbierto(dentroDe: $0.url.path) == nil }
            let elegidos = abierta ? viejos : archivos
            let total = elegidos.reduce(Int64(0)) { $0 + $1.bytes }
            guard total >= minimo else {
                pequenos += viejos
                continue
            }
            let ultimo = elegidos.map(\.fecha).max()
            var motivos: [Motivo] = [.bien("doc.text.magnifyingglass", "Solo registros",
                                           "Solo archivos de registro (.log, .ips, .diag, .crash y los .txt y .json que se llaman como un registro). Se crean nuevos cuando hace falta.")]
            if abierta {
                motivos.append(.info("clock.fill", "\(l.nombre) está abierta",
                                     "Solo cuento los que nadie tiene abiertos y llevan más de 1 h sin cambios (los ya rotados y los de sesiones anteriores): los recientes los puede estar escribiendo."))
            }
            if l.nombre.hasPrefix("Microsoft ") {
                motivos.append(.info("arrow.clockwise", "Vuelven a crecer",
                                     "Office escribe registros de diagnóstico mientras lo usas y guarda varios archivos de unos 20 MB por app: en uno o dos días de uso vuelven a ocupar lo mismo."))
            }
            r.append(Elemento(
                nombre: "Registros de \(l.nombre)",
                detalle: "\(Formato.numero(elegidos.count)) archivos de registro que \(l.nombre) guarda en su \(l.grupo ? "contenedor compartido" : "contenedor").",
                consecuencia: "Nada importante: solo se pierden registros y errores antiguos.",
                rutas: elegidos.map(\.url), tamanosRutas: elegidos.map(\.bytes), ultimoUso: ultimo, categoria: .registros,
                riesgo: .seguro, seleccionado: true, motivos: motivos,
                // Abierta: no se espera a cerrarla, pero si algo cambia después del análisis no se toca.
                enUso: abierta ? nil : l.uso, dueno: l.nombre, cambioAnalizado: abierta ? ultimo : nil))
        }
        // Lo pequeño de cada app, junto: solo lo de más de 1 h que nadie tiene abierto (no se puede esperar a que cierren
        // todas).
        if !pequenos.isEmpty {
            let ultimo = pequenos.map(\.fecha).max()
            r.append(Elemento(
                nombre: "Registros pequeños de apps aisladas",
                detalle: "\(Formato.numero(pequenos.count)) archivos de registro de más de 1 h sin cambios que guardan las apps en sus contenedores.",
                consecuencia: "Nada importante: solo se pierden registros y errores antiguos.",
                rutas: pequenos.map(\.url), tamanosRutas: pequenos.map(\.bytes), ultimoUso: ultimo, categoria: .registros,
                riesgo: .seguro, seleccionado: true,
                motivos: [.bien("doc.text.magnifyingglass", "Solo registros",
                                "Solo archivos de registro de más de 1 h sin cambios que ningún programa tiene abiertos.")],
                dueno: "Apps aisladas", cambioAnalizado: ultimo))
        }
        // Telemetría de Office: datos de uso que Office aún no envió a Microsoft.
        let otele = Self.carpetasDeOffice("Office/OTele", c)
        if !otele.isEmpty {
            r.append(Elemento(
                nombre: "Telemetría pendiente de Office",
                detalle: "Datos de uso y diagnóstico que Word, PowerPoint y las demás apps de Office guardan para enviarlos a Microsoft.",
                consecuencia: "Nada: no son documentos tuyos. Office crea nuevos cuando hace falta.",
                rutas: otele, tamanosRutas: otele.map { Self.ocupa($0, c) }, categoria: .registros, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("chart.bar.doc.horizontal", "Solo telemetría", "Office no los necesita para funcionar.")],
                enUso: Self.usoDeOffice, dueno: "Microsoft Office"))
        }
        return r
    }

    // MARK: - Cachés de Apple

    /// Una caché de menos de 1 MB: sola no se ofrece (el análisis descarta lo pequeño), pero se juntan todas en una.
    private struct CachePequena {
        let nombre: String
        let rutas: [URL]
        let tamanos: [Int64]
    }

    /// Los contenedores aislados de Apple (~/Library/Containers/com.apple.*): Data/Library/Caches y, de los que solo dejan
    /// descargas en Data/tmp (`tmpDeDescargas`), las de más de 7 días. Uno por app o servicio. Nunca se sigue nada de Data/
    /// (Desktop, Downloads… son enlaces a tus carpetas).
    private func cachesDeContenedoresDeApple(_ c: Contexto, desinstaladas: [AppDeApple],
                                             pequenas: inout [CachePequena]) -> [Elemento] {
        guard c.accesoTotal else { return [] }
        let limiteTmp = Date().addingTimeInterval(-7 * 86400)
        var r: [Elemento] = []
        for k in Rutas.hijos(Rutas.enHome("Library/Containers")) {
            let id = k.lastPathComponent
            guard id.lowercased().hasPrefix("com.apple."), !Self.esSensibleDeApple(id), !Self.esDeAppDesinstalada(id, desinstaladas),
                  Self.esCarpetaPropia(k) else { continue }
            var rutas = Self.contenidoDeCache(k.appendingPathComponent("Data/Library/Caches"), de: k)
            var conTmp = false
            // En Data/tmp también acaban capturas y grabaciones de pantalla sin mover, fotos importadas o la copia de un
            // documento que no se pudo guardar (TemporaryItems/NSIRD_*): solo se miran las descargas sueltas de los servicios
            // que no guardan ahí nada más.
            let tmp = k.appendingPathComponent("Data/tmp")
            if Self.tmpDeDescargas.contains(id.lowercased()), Self.esCarpetaPropia(tmp), Self.estaDentro(tmp, de: k) {
                for h in Rutas.hijos(tmp) where Self.esDescargaTemporal(h) {
                    guard let f = Self.ultimoCambio(h, c), f < limiteTmp,
                          c.procesos.abiertos.hayAbierto(dentroDe: h.path) == nil else { continue }
                    rutas.append(h)
                    conTmp = true
                }
            }
            let nombre = Self.nombreDeServicio(id, c)
            if let el = cacheDeServicio(nombre, id: id, rutas: rutas, c, donde: "en su contenedor", conTmp: conTmp, pequenas: &pequenas) {
                r.append(el)
            }
        }
        return r
    }

    /// ~/Library/Caches/com.apple.* que no ofrece ninguna otra regla (cachesDeApple, las de desarrollo, los restos de las
    /// apps opcionales que ya no están).
    private func cachesDeAppleEnLibrary(_ c: Contexto, desinstaladas: [AppDeApple], pequenas: inout [CachePequena]) -> [Elemento] {
        var r: [Elemento] = []
        let caches = Rutas.enHome("Library/Caches")
        for h in Rutas.hijos(caches) where Self.esCarpetaPropia(h) {
            let n = h.lastPathComponent
            let l = n.lowercased()
            guard l.hasPrefix("com.apple."), !l.hasPrefix("com.apple.dt."), Self.cachesDeApple[n] == nil,
                  !Self.cachesDeDesarrolloEnLibrary.contains(n), !Self.apartadoDeApple(h), !Self.esSensibleDeApple(n),
                  !Self.esDeAppDesinstalada(n, desinstaladas) else { continue }
            let rutas = Self.sinApartar(h, niveles: 3, apartar: Self.apartadoDeCacheDeApple)
            if let el = cacheDeServicio(Self.nombreDeServicio(n, c), id: n, rutas: rutas, c, donde: "en ~/Library/Caches", conTmp: false,
                                        pequenas: &pequenas) {
                r.append(el)
            }
        }
        return r
    }

    /// Los grupos de Apple (Group Containers con «com.apple.»): Library/Caches y Caches, menos los modelos compilados
    /// para el build actual (los de reconocimiento de voz, por ejemplo).
    private func cachesDeGruposDeApple(_ c: Contexto, pequenas: inout [CachePequena]) -> [Elemento] {
        guard c.accesoTotal else { return [] }
        var r: [Elemento] = []
        for g in Rutas.hijos(Rutas.enHome("Library/Group Containers")) {
            let id = g.lastPathComponent
            guard id.lowercased().contains("com.apple."), !Self.esSensibleDeApple(id), Self.esCarpetaPropia(g) else { continue }
            let rutas = ["Library/Caches", "Caches"].flatMap { Self.contenidoDeCache(g.appendingPathComponent($0), de: g) }
            if let el = cacheDeServicio(Self.nombreDeServicio(id, c), id: id, rutas: rutas, c, donde: "en su contenedor compartido",
                                        conTmp: false, pequenas: &pequenas) {
                r.append(el)
            }
        }
        return r
    }

    /// Lo que hay dentro de una carpeta de caché (sin la carpeta: la app no tiene que volver a crearla), sin enlaces y sin lo
    /// apartado (modelos compilados, que van aparte). Vacío si no es una carpeta de verdad dentro de `raiz`.
    private static func contenidoDeCache(_ cache: URL, de raiz: URL) -> [URL] {
        guard esCarpetaPropia(cache), estaDentro(cache, de: raiz) else { return [] }
        var r: [URL] = []
        for h in Rutas.hijos(cache) where !esEnlaceOSuelto(h) && !apartadoDeCacheDeApple(h) {
            r += esCarpetaPropia(h) ? sinApartar(h, niveles: 2, apartar: apartadoDeCacheDeApple) : [h]
        }
        return r
    }

    /// Los contenedores de Apple cuya Data/tmp solo guarda descargas que el servicio no limpió (Mapas: teselas y recursos).
    private static let tmpDeDescargas: Set<String> = ["com.apple.geod"]

    private static let patronDescarga = try! NSRegularExpression(
        pattern: #"^([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|CFNetworkDownload_[A-Za-z0-9]+\.tmp)$"#)

    /// Un archivo suelto (no una carpeta ni un enlace) con nombre de descarga de CFNetwork: «CFNetworkDownload_Ab12.tmp» o un
    /// UUID sin extensión. Nunca una foto, un vídeo o un documento con nombre.
    private static func esDescargaTemporal(_ u: URL) -> Bool {
        var st = stat()
        guard lstat(u.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid() else { return false }
        let n = u.lastPathComponent
        return patronDescarga.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
    }

    /// El elemento de la caché de una app o un servicio de Apple, o nil si es pequeña (entonces va a `pequenas`, si nada
    /// la usa) o está vacía. Seguro y marcado con el servicio cerrado; las que vuelven a analizar fotos o a compilar
    /// modelos, Revisar.
    private func cacheDeServicio(_ nombre: String, id: String, rutas todas: [URL], _ c: Contexto, donde: String, conTmp: Bool,
                                 pequenas: inout [CachePequena]) -> Elemento? {
        let medidas = todas.map { ($0, Self.ocupa($0, c)) }.filter { $0.1 > 0 }
        guard !medidas.isEmpty else { return nil }
        let rutas = medidas.map(\.0)
        let tamanos = medidas.map(\.1)
        let uso = Self.usoDeServicio(id, nombre: nombre)
        let porFotos = Self.analizaFotos(id)
        let porModelos = !porFotos && (Self.compilaModelos(id) || Self.tieneModelos(rutas))
        // Un servicio sin ventana que está funcionando (geod, parsecd, tipsd…) no se cierra nunca: de su caché, solo los
        // archivos quietos (ver `cacheDeServicioEnMarcha`), sin esperarlo.
        if !porFotos && !porModelos, let quien = Self.enMarchaSinVentana(uso, rutas: rutas, c) {
            return cacheDeServicioEnMarcha(nombre, quien: quien, uso: uso, rutas: rutas, c, donde: donde, conTmp: conTmp)
        }
        guard tamanos.reduce(0, +) >= minimo else {
            // Junto a las demás pequeñas solo si nada la usa ahora (el grupo no espera a ningún servicio en concreto), y sin
            // lo de Data/tmp: el grupo solo lleva cachés.
            let soloCache = medidas.filter { !$0.0.path.contains("/Data/tmp/") }
            if !soloCache.isEmpty && !porFotos && !porModelos && c.procesos.quienUsa(uso) == nil
                && c.procesos.abiertos.hayAbierto(dentroDe: soloCache.map(\.0)) == nil {
                pequenas.append(CachePequena(nombre: nombre, rutas: soloCache.map(\.0), tamanos: soloCache.map(\.1)))
            }
            return nil
        }
        let revisar = porFotos || porModelos
        let que = conTmp ? "Caché y descargas temporales de más de 7 días" : "Caché"
        let motivo: Motivo = porFotos
            ? .info("photo.on.rectangle.angled", "Vuelve a analizar", "Se regenera, pero vuelve a analizar tus fotos y gasta batería.")
            : porModelos
            ? .info("cpu", "Vuelve a compilar", "Se regenera, pero vuelve a compilar o a descargar sus modelos y gasta batería.")
            : .bien("arrow.triangle.2.circlepath", "Se regenera", "Es una caché: \(nombre) la reconstruye sola.")
        var motivos = [motivo]
        if conTmp {
            motivos.append(.bien("arrow.down.circle", "Descargas viejas",
                                 "De su carpeta temporal solo cuento descargas sueltas (CFNetworkDownload…, nombres UUID) de más de 7 días que nadie tiene abiertas."))
        }
        return Elemento(
            nombre: "Caché de \(nombre)",
            detalle: "\(que) que \(nombre) guarda \(donde).",
            consecuencia: porFotos
                ? "Se vuelve a crear, pero \(nombre) vuelve a analizar tus fotos y vídeos: gasta procesador y batería durante horas."
                : porModelos
                ? "Se vuelve a crear, pero \(nombre) vuelve a compilar o a descargar sus modelos: gasta procesador, batería o datos."
                : "\(nombre) la vuelve a crear cuando la necesita (al principio puede ir un poco más lenta).",
            rutas: rutas, tamanosRutas: tamanos, categoria: .cachesApps, riesgo: revisar ? .revisar : .seguro, seleccionado: !revisar,
            motivos: motivos, enUso: uso, dueno: nombre)
    }

    /// Las cachés pequeñas de Apple, juntas: cada una sola no llega al mínimo, pero son decenas.
    private func cachesPequenasDeApple(_ pequenas: [CachePequena]) -> Elemento? {
        guard !pequenas.isEmpty else { return nil }
        let nombres = Array(Set(pequenas.map(\.nombre))).sorted()
        return Elemento(
            nombre: "Cachés pequeñas de servicios de Apple",
            detalle: "\(Formato.numero(pequenas.count)) cachés de menos de 1 MB de apps y servicios de macOS: \(Formato.listaCorta(nombres, maximo: 4)).",
            consecuencia: "Cada app o servicio vuelve a crear la suya cuando la necesita.",
            rutas: pequenas.flatMap(\.rutas), tamanosRutas: pequenas.flatMap(\.tamanos), categoria: .cachesApps, riesgo: .seguro,
            seleccionado: true,
            motivos: [.bien("arrow.triangle.2.circlepath", "Se regeneran",
                            "Son cachés que cada servicio reconstruye solo. Me salto las de servicios que están funcionando y las que algún programa tiene abiertas.")],
            dueno: "macOS")
    }

    /// Los modelos de IA que macOS compila para el Neural Engine (…/com.apple.e5rt.e5bundlecache/<build>) de builds que
    /// ya no son el actual: tras actualizar, se compilan de nuevo en otra carpeta y los viejos se quedan. Nunca el build
    /// actual, ni lo que cambió en el último día.
    private func modelosDeBuildsAnteriores(_ c: Contexto, desinstaladas: [AppDeApple]) -> Elemento? {
        guard !Self.buildsActuales.isEmpty else { return nil }
        let e5 = "com.apple.e5rt.e5bundlecache"
        // Una caché y lo que tiene un nivel por debajo.
        func enCache(_ base: URL) -> [URL] {
            guard Self.esCarpetaPropia(base) else { return [] }
            return [base.appendingPathComponent(e5)] + Rutas.hijos(base).filter(Self.esCarpetaPropia).map { $0.appendingPathComponent(e5) }
        }
        let caches = Rutas.enHome("Library/Caches")
        var carpetas = [caches.appendingPathComponent(e5)]
        // Las cachés de terceros, cachesDeApple y las de desarrollo ya se ofrecen enteras.
        for h in Rutas.hijos(caches) where Self.esCarpetaPropia(h) {
            let n = h.lastPathComponent
            guard n.lowercased().hasPrefix("com.apple."), Self.cachesDeApple[n] == nil, !Self.cachesDeDesarrolloEnLibrary.contains(n),
                  !Self.esDeAppDesinstalada(n, desinstaladas) else { continue }
            carpetas.append(h.appendingPathComponent(e5))
        }
        if c.accesoTotal {
            for k in Rutas.hijos(Rutas.enHome("Library/Containers")) where k.lastPathComponent.lowercased().hasPrefix("com.apple.")
                && !Self.esDeAppDesinstalada(k.lastPathComponent, desinstaladas) {
                let base = k.appendingPathComponent("Data/Library/Caches")
                if Self.estaDentro(base, de: k) { carpetas += enCache(base) }
            }
            for g in Rutas.hijos(Rutas.enHome("Library/Group Containers")) where g.lastPathComponent.lowercased().contains("com.apple.") {
                for rel in ["Library/Caches", "Caches"] {
                    let base = g.appendingPathComponent(rel)
                    if Self.estaDentro(base, de: g) { carpetas += enCache(base) }
                }
            }
        }
        // Los de los servicios del sistema (Daemon Containers/<UUID>/Data/CompiledModels/<servicio>/<UUID>/…).
        for d in Rutas.hijos(Rutas.enHome("Library/Daemon Containers")) where Self.esCarpetaPropia(d) {
            for servicio in Rutas.hijos(d.appendingPathComponent("Data/CompiledModels")) where Self.esCarpetaPropia(servicio) {
                carpetas += Rutas.hijos(servicio).filter(Self.esCarpetaPropia).map { $0.appendingPathComponent(e5) }
            }
            let base = d.appendingPathComponent("Data/Library/Caches")
            if Self.estaDentro(base, de: d) { carpetas += enCache(base) }
        }
        let haceUnDia = Date().addingTimeInterval(-86400)
        var rutas: [URL] = []
        var builds = Set<String>()
        for e in carpetas where Self.esCarpetaPropia(e) {
            for b in Rutas.hijos(e) where Self.esCarpetaPropia(b) {
                let n = b.lastPathComponent
                guard Self.pareceBuild(n), !Self.esDelBuildActual(n), let f = Self.ultimoCambio(b, c), f < haceUnDia else { continue }
                rutas.append(b)
                builds.insert(n)
            }
        }
        guard !rutas.isEmpty else { return nil }
        let actual = Self.buildsActuales.sorted().joined(separator: " y ")
        return Elemento(
            nombre: "Modelos compilados de versiones anteriores de macOS",
            detalle: "Modelos de IA que macOS compiló para el Neural Engine con \(Formato.lista(builds.sorted())); ahora usas \(actual).",
            consecuencia: "Nada: son de una versión de macOS que ya no tienes. Los de la versión actual no se tocan.",
            rutas: rutas, tamanosRutas: rutas.map { Self.ocupa($0, c) }, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
            motivos: [.bien("cpu", "De otra versión de macOS",
                            "Cada versión de macOS compila los suyos en su propia carpeta: estos ya no los usa nada.")],
            dueno: "macOS")
    }

    // MARK: - Office y Zoom

    private static let equipoDeOffice = "UBF8T346G9"

    private static let appsDeOffice: [(id: String, nombre: String)] = [
        ("com.microsoft.Word", "Microsoft Word"), ("com.microsoft.Excel", "Microsoft Excel"),
        ("com.microsoft.Powerpoint", "Microsoft PowerPoint"), ("com.microsoft.Outlook", "Microsoft Outlook"),
        ("com.microsoft.onenote.mac", "Microsoft OneNote"),
    ]

    /// Lo que comparten las apps de Office: en uso si cualquiera está abierta.
    private static let usoDeOffice = EnUso.app(nombre: "Office", claves: appsDeOffice.map(\.id) + appsDeOffice.map(\.nombre))

    /// Las carpetas `rel` de Containers/<app de Office>/Data/Library/Application Support/Microsoft que existen de verdad
    /// (sin seguir enlaces), de las apps de Office que siguen instaladas.
    private static func carpetasDeOffice(_ rel: String, _ c: Contexto) -> [URL] {
        guard c.accesoTotal else { return [] }
        return appsDeOffice.compactMap { app in
            guard c.apps.estaInstalado(carpeta: app.id) else { return nil }
            let k = Rutas.enHome("Library/Containers/\(app.id)")
            let u = k.appendingPathComponent("Data/Library/Application Support/Microsoft/\(rel)")
            return esCarpetaPropia(u) && estaDentro(u, de: k) ? u : nil
        }
    }

    private func cachesDeOffice(_ c: Contexto) -> [Elemento] {
        guard c.accesoTotal else { return [] }
        var r: [Elemento] = []
        let grupo = Rutas.enHome("Library/Group Containers/\(Self.equipoDeOffice).Office")
        let conGrupo = Self.esCarpetaPropia(grupo) && c.apps.estaInstalado(carpeta: grupo.lastPathComponent)
        func delGrupo(_ rel: String) -> URL? {
            let u = grupo.appendingPathComponent(rel)
            return conGrupo && Self.esCarpetaPropia(u) && Self.estaDentro(u, de: grupo) ? u : nil
        }
        // Temas y plantillas de la galería de Office: se vuelven a descargar al abrirla. Sin las copias repetidas del catálogo,
        // que van aparte y en el modo normal (`catalogoDeOfficeRepetido`).
        let dts = Self.sinCatalogosRepetidos(Self.carpetasDeOffice("Office/16.0/DTS", c))
        let tamanosDTS = dts.map { Self.ocupa($0, c) }
        if !dts.isEmpty {
            r.append(Elemento(
                nombre: "Plantillas y temas descargados de Office",
                detalle: "Temas, plantillas y sus miniaturas que Word, PowerPoint y las demás apps de Office bajaron para su galería.",
                consecuencia: "Office los vuelve a descargar cuando abras la galería de plantillas o temas (necesita internet). Tus plantillas propias no se guardan aquí.",
                rutas: dts, tamanosRutas: tamanosDTS, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                motivos: [.info("arrow.down.circle.fill", "Se vuelve a descargar",
                                "No se pierde nada, pero volver a bajarlos necesita internet: solo lo marco en «Liberar al máximo».")],
                enUso: Self.usoDeOffice, dueno: "Microsoft Office", nivel: .maximo,
                costes: [.descarga(bytes: tamanosDTS.reduce(0, +))]))
        }
        // Sin las fuentes que Office bajó de internet (FontCache/<n>/CloudFonts): no salen de las instaladas, así que van
        // aparte y solo en «Liberar al máximo» (`fuentesEnLaNubeDeOffice`).
        let fuentes = (Self.carpetasDeOffice("FontPreviewCache", c) + Self.carpetasDeOffice("FontCache", c) + [delGrupo("FontCache")].compactMap { $0 })
            .flatMap { Self.sinApartar($0, niveles: 2, apartar: { $0.lastPathComponent == "CloudFonts" }) }
        if !fuentes.isEmpty {
            r.append(Elemento(
                nombre: "Cachés de fuentes de Office",
                detalle: "Las vistas previas de las fuentes y la caché de fuentes que comparten las apps de Office.",
                consecuencia: "Office las vuelve a crear con las fuentes que ya tienes (la primera vez que abras el menú de fuentes tarda un poco más).",
                rutas: fuentes, tamanosRutas: fuentes.map { Self.ocupa($0, c) }, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("textformat", "Se regenera", "Salen de las fuentes instaladas: no hace falta descargar nada.")],
                enUso: Self.usoDeOffice, dueno: "Microsoft Office"))
        }
        if let paquetes = delGrupo("SolutionPackages") {
            r.append(Elemento(
                nombre: "Complementos descargados de Office",
                detalle: "Paquetes de los complementos y funciones web de Office (SolutionPackages).",
                consecuencia: "Office vuelve a descargar los complementos que uses (necesita internet). Lo que alguno guarde sin conexión se pierde.",
                rutas: [paquetes], tamanosRutas: [Self.ocupa(paquetes, c)], categoria: .cachesApps, riesgo: .revisar,
                motivos: [.info("puzzlepiece.extension.fill", "Se vuelven a descargar", "Office baja de nuevo los complementos al usarlos.")],
                enUso: Self.usoDeOffice, dueno: "Microsoft Office"))
        }
        return r
    }

    /// Lo que Zoom descarga en ~/Library/Application Support/zoom.us: su navegador interno (CEF), una carpeta por versión,
    /// y recursos (Zoom Apps, fondos de serie, modelos de vídeo, gestos). Nunca tus fondos (VirtualBkgnd_Custom) ni sus bases.
    private func recursosDeZoom(_ c: Contexto) -> [Elemento] {
        let zoom = Rutas.enHome("Library/Application Support/zoom.us")
        // Sin Zoom instalado, la carpeta entera ya sale en «Restos de apps borradas».
        guard Self.esCarpetaPropia(zoom), c.apps.estaInstalado(carpeta: zoom.lastPathComponent) else { return [] }
        let uso = EnUso.app(nombre: "Zoom", claves: ["us.zoom.xos", "zoom.us", "Zoom"])
        // Lo que ya ofrece «Caché interna» y lo que puede ser tuyo o una base de datos se queda fuera.
        let internas = Set(c.indice.cachesInternas.map(\.ruta).filter { $0.hasPrefix(zoom.path + "/") })
        func apartar(_ u: URL) -> Bool {
            let n = u.lastPathComponent.lowercased()
            return internas.contains(u.path) || n.contains("custom")
                || [".db", ".db-wal", ".db-shm", ".sqlite", ".sqlite-wal", ".sqlite-shm"].contains { n.hasSuffix($0) }
        }
        // `sinApartar` solo baja 3 niveles: lo que tenga algo de eso más abajo se queda fuera entero.
        func sinNadaApartado(_ rutas: [URL]) -> [URL] {
            rutas.filter { u in !internas.contains { $0.hasPrefix(u.path + "/") } && !Self.contiene(u, apartar) }
        }
        var r: [Elemento] = []
        let framework = zoom.appendingPathComponent("CefPlugin/Framework")
        // Solo las carpetas con forma de versión («128.7.0.738_arm64»): una a medio bajar o con otro nombre no cuenta.
        let versiones = Self.estaDentro(framework, de: zoom)
            ? Rutas.hijos(framework).filter { Self.esCarpetaPropia($0) && Self.esVersionDeCef($0.lastPathComponent) }
                .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
            : []
        if let actual = versiones.last {
            // Las viejas solo si la más nueva está entera (tiene su .bundle o .framework), y nunca la que cambió más
            // recientemente: puede ser la que usa Zoom aunque haya bajado otra.
            let completa = Rutas.hijos(actual).contains { ["bundle", "framework"].contains($0.pathExtension) && Self.esCarpetaPropia($0) }
            let reciente = versiones.max { (Self.ultimoCambio($0, c) ?? .distantPast) < (Self.ultimoCambio($1, c) ?? .distantPast) }
            let viejas = completa
                ? sinNadaApartado(versiones.dropLast().filter { $0 != reciente }.flatMap { Self.sinApartar($0, niveles: 3, apartar: apartar) })
                : []
            if !viejas.isEmpty {
                r.append(Elemento(
                    nombre: "Versiones viejas del navegador interno de Zoom",
                    detalle: "Versiones anteriores del navegador (CEF) que Zoom descarga para sus vistas web: ahora usa la \(actual.lastPathComponent).",
                    consecuencia: "Nada: Zoom usa la versión más nueva.",
                    rutas: viejas, tamanosRutas: viejas.map { Self.ocupa($0, c) }, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                    motivos: [.bien("checkmark.circle.fill", "Versión anterior", "Hay una versión más nueva al lado.")],
                    enUso: uso, dueno: "Zoom"))
            }
            let enUsoRutas = sinNadaApartado(Self.sinApartar(actual, niveles: 3, apartar: apartar))
            let tamanosEnUso = enUsoRutas.map { Self.ocupa($0, c) }
            if !enUsoRutas.isEmpty {
                r.append(Elemento(
                    nombre: "Navegador interno de Zoom (\(actual.lastPathComponent))",
                    detalle: "El navegador (CEF) que Zoom descarga para sus vistas web.",
                    consecuencia: "Zoom lo vuelve a descargar la próxima vez que lo necesite (\(Formato.bytes(tamanosEnUso.reduce(0, +))); necesita internet), y hasta entonces algunas de sus pantallas no cargan.",
                    rutas: enUsoRutas, tamanosRutas: tamanosEnUso, categoria: .cachesApps, riesgo: .revisar,
                    motivos: [.info("arrow.down.circle.fill", "Se vuelve a descargar", "Es la versión que usa Zoom.")],
                    enUso: uso, dueno: "Zoom"))
            }
        }
        let nombres = ["ZoomAppResource", "VirtualBkgnd_Default", "VirtualBkgnd_Video", "PSWallpaper", "VideoModel", "HandGestureVideo"]
        let recursos = nombres.map { zoom.appendingPathComponent("data/\($0)") }
            .filter { Self.esCarpetaPropia($0) && Self.estaDentro($0, de: zoom) }
            .flatMap { Self.sinApartar($0, niveles: 3, apartar: apartar) }
        let recursosLimpios = sinNadaApartado(recursos)
        if !recursosLimpios.isEmpty {
            r.append(Elemento(
                nombre: "Recursos descargados de Zoom",
                detalle: "Zoom Apps, fondos virtuales de serie, modelos de vídeo y gestos que Zoom descargó.",
                consecuencia: "Zoom los vuelve a descargar cuando los uses (necesita internet). Tus fondos virtuales propios no se tocan.",
                rutas: recursosLimpios, tamanosRutas: recursosLimpios.map { Self.ocupa($0, c) }, categoria: .cachesApps, riesgo: .revisar,
                motivos: [.info("arrow.down.circle.fill", "Se vuelven a descargar", "Son recursos de Zoom, no tuyos; tus fondos (VirtualBkgnd_Custom) se quedan.")],
                enUso: uso, dueno: "Zoom"))
        }
        return r
    }

    private static let patronVersionDeCef = try! NSRegularExpression(pattern: #"^\d+(\.\d+)+(_[A-Za-z0-9]+)?$"#)

    /// «128.7.0.738_arm64»: una versión del navegador interno de Zoom.
    private static func esVersionDeCef(_ n: String) -> Bool {
        patronVersionDeCef.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
    }

    /// ¿Hay dentro de `u` (a cualquier profundidad, sin seguir enlaces) algo que `apartar` deja fuera? Si es demasiado
    /// grande para mirarlo entero o no se puede leer, se da por sí.
    private static func contiene(_ u: URL, _ apartar: (URL) -> Bool, maximo: Int = 20_000) -> Bool {
        guard esCarpetaPropia(u) else { return false }
        guard let rutaC = strdup(u.path) else { return true }
        defer { free(rutaC) }
        var argumentos: [UnsafeMutablePointer<CChar>?] = [rutaC, nil]
        guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return true }
        defer { fts_close(fts) }
        var vistos = 0
        while let e = fts_read(fts) {
            vistos += 1
            if vistos > maximo { return true }
            let tipo = Int32(e.pointee.fts_info)
            guard tipo != FTS_DP, e.pointee.fts_level > 0 else { continue }
            if tipo == FTS_DNR || tipo == FTS_ERR { return true }
            if apartar(URL(fileURLWithPath: String(cString: e.pointee.fts_path))) { return true }
        }
        return false
    }

    // MARK: - /var/folders

    /// Cachés de Apple en C que se regeneran como la de Metal: con 3 días sin cambios (2 h en «Liberar al máximo») y su app o
    /// servicio sin funcionar. Las que obligan a reiniciar el Dock o la sesión (iconservices, dock, FontRegistry) no se tocan.
    private func cachesDeAppleEnC(_ c: Contexto) -> [Elemento] {
        let apps = Self.appsDeAppleEnAplicaciones()
        var r: [Elemento] = []
        for raiz in Rutas.temporalesDelSistema where raiz.hasSuffix("/C") {
            for h in Rutas.hijos(URL(fileURLWithPath: raiz)) where Self.esCarpetaPropia(h) {
                guard let (nombre, uso) = Self.cacheDeAppleEnC(h, apps), c.indice.bytes(de: h) >= minimo else { continue }
                let actividad = c.indice.masReciente(de: [h])
                let dias = actividad.map { Date().timeIntervalSince($0) / 86400 } ?? 999
                let viejo = dias >= 3
                let enMaximo = !viejo && dias * 24 >= 2
                let cuando = Formato.haceCuanto(actividad).lowercased()
                r.append(Elemento(
                    nombre: "Caché de \(nombre)",
                    detalle: "Caché que \(nombre) guarda en la carpeta privada de macOS para tu usuario.",
                    consecuencia: h.lastPathComponent == "com.apple.metalfe"
                        ? "Las apps vuelven a compilar sus sombreadores cuando los necesitan (los primeros segundos pueden ir algo más lentas)."
                        : "\(nombre) la vuelve a crear cuando la necesita.",
                    rutas: [h], categoria: .sistema, riesgo: .seguro, seleccionado: viejo || enMaximo,
                    motivos: [viejo
                        ? .bien("arrow.triangle.2.circlepath", "Se regenera", "Nadie la toca desde \(cuando).")
                        : .info("clock.fill", "Usado hace poco", "Se usó \(cuando): mejor deja que \(nombre) termine con ella. Lo marco cuando lleve 3 días sin cambios"
                                + (enMaximo ? "; «Liberar al máximo» ya lo incluye, porque lleva más de 2 h sin cambios." : "."))],
                    enUso: uso, dueno: nombre, nivel: enMaximo ? .maximo : .normal, cambioAnalizado: actividad))
            }
        }
        return r
    }

    /// Qué es una carpeta de C de Apple que se puede regenerar (nombre y quién la usa), o nil si no está en la lista.
    private static func cacheDeAppleEnC(_ carpeta: URL, _ apps: [String: String]) -> (String, EnUso?)? {
        let n = carpeta.lastPathComponent
        let l = n.lowercased()
        guard l.hasPrefix("com.apple."), !l.hasSuffix(".sandbox"), !esSensibleDeApple(n) else { return nil }
        let ultima = String(n.split(separator: ".").last ?? Substring(n))
        switch l {
        // Como com.apple.metal: la usa cualquier app que dibuje con la GPU, así que basta con que nadie la tenga abierta.
        case "com.apple.metalfe": return ("Metal (compilador de sombreadores)", nil)
        case "com.apple.coresimulator.simrenderingservices.simmetalhost":
            return ("Simulador de iOS (gráficos)", .app(nombre: "Simulator", claves: ["com.apple.iphonesimulator", "Simulator", "SimMetalHost"]))
        case "com.apple.hydrarenderingservice":
            return ("Vistas 3D (HydraRenderingService)", .app(nombre: "HydraRenderingService", claves: [n, ultima]))
        case "com.apple.avconferenced":
            return ("FaceTime (avconferenced)", .app(nombre: "avconferenced", claves: [n, ultima, "com.apple.FaceTime", "FaceTime"]))
        default: break
        }
        if l.hasPrefix("com.apple.avatarui.") { return ("Memoji", .app(nombre: "Memoji", claves: [n, ultima])) }
        if l == "com.apple.webkit.gpu" || l.hasPrefix("com.apple.webkit.gpu+") { return ("WebKit (gráficos)", nil) }
        // La de una app de Apple solo si lo que guarda son sus sombreadores compilados (la App Store, por ejemplo, ha guardado
        // ahí descargas a medias).
        if let app = apps[l], !l.hasPrefix("com.apple.dt."), !l.hasPrefix("com.apple.appstore"), soloGraficos(carpeta, id: n) {
            let nombre = nombresDeApple[l] ?? app
            return (nombre, .app(nombre: nombre, claves: [n, app, nombre]))
        }
        return nil
    }

    /// Lo que macOS guarda en la C de una app: sus sombreadores compilados y la caché de AppleScript.
    private static let deGraficosEnC: Set<String> = ["com.apple.metal", "com.apple.metalfe", "com.apple.gpuarchiver",
                                                     "com.apple.scriptmanager2.le.cache"]

    /// ¿La carpeta de C de la app `id` solo tiene eso, suelto o dentro de una carpeta con su identificador?
    private static func soloGraficos(_ carpeta: URL, id: String) -> Bool {
        func deGraficos(_ u: URL) -> Bool { deGraficosEnC.contains(u.lastPathComponent.lowercased()) && !esEnlaceOSuelto(u) }
        let hijos = Rutas.hijos(carpeta)
        return !hijos.isEmpty && hijos.allSatisfy { h in
            deGraficos(h) || (h.lastPathComponent.lowercased() == id.lowercased() && esCarpetaPropia(h)
                              && Rutas.hijos(h).allSatisfy(deGraficos))
        }
    }

    /// Las apps de Apple de /Applications y /System/Applications (y sus Utilidades), por identificador en minúsculas.
    private static func appsDeAppleEnAplicaciones() -> [String: String] {
        var r: [String: String] = [:]
        for carpeta in ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities"] {
            for app in Rutas.hijos(URL(fileURLWithPath: carpeta)) where app.pathExtension == "app" {
                guard let id = Bundle(url: app)?.bundleIdentifier?.lowercased(), id.hasPrefix("com.apple.") else { continue }
                r[id] = app.deletingPathExtension().lastPathComponent
            }
        }
        return r
    }

    private static let patronBun = try! NSRegularExpression(pattern: #"^\.bun-(\d+)-[0-9a-f]{6,}\.(dylib|node|so)$"#)

    /// Las librerías nativas que extraen al arrancar los programas compilados con Bun («.bun-501-1d98d107b4c544c0.dylib» en
    /// T). El programa que las extrajo las usa mientras funciona: solo las de más de 1 día que nadie tiene abiertas ni
    /// cargadas.
    private func libreriasDeBun(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let haceUnDia = Date().addingTimeInterval(-86400)
        let uid = String(getuid())
        for raiz in Rutas.temporalesDelSistema where raiz.hasSuffix("/T") {
            let real = Rutas.real(URL(fileURLWithPath: raiz))
            var rutas: [URL] = []
            var tamanos: [Int64] = []
            var ultimo: Date?
            var quedan = 0
            for n in (try? FileManager.default.contentsOfDirectory(atPath: raiz)) ?? [] {
                guard let m = Self.patronBun.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)),
                      let suyo = Range(m.range(at: 1), in: n), n[suyo] == uid else { continue }
                let ruta = raiz + "/" + n
                var st = stat()
                guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid() else { continue }
                let fecha = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                guard fecha < haceUnDia, c.procesos.abiertos.hayAbierto(rutaReal: real + "/" + n) == nil else {
                    quedan += 1
                    continue
                }
                rutas.append(URL(fileURLWithPath: ruta))
                tamanos.append(Int64(st.st_blocks) * 512)
                ultimo = max(ultimo ?? fecha, fecha)
            }
            guard !rutas.isEmpty else { continue }
            var motivos: [Motivo] = [.bien("doc.badge.clock", "Se vuelven a extraer",
                "El programa las saca de sí mismo al arrancar. Solo cuentan las que llevan más de 1 día sin cambios y que ningún programa tiene abiertas ni cargadas.")]
            if quedan > 0 {
                motivos.append(.info("clock.fill", "Las recientes se quedan", "Hay otras \(Formato.numero(quedan)) más nuevas o en uso: no se tocan."))
            }
            r.append(Elemento(
                nombre: "Librerías extraídas por programas de Bun",
                detalle: "\(Formato.numero(rutas.count)) librerías nativas (.dylib, .node) que los programas compilados con Bun (opencode y otros) extraen en tu carpeta de temporales y no borran.",
                consecuencia: "Nada: el programa las vuelve a extraer la próxima vez que arranque.",
                rutas: rutas, tamanosRutas: tamanos, ultimoUso: ultimo, categoria: .sistema, riesgo: .seguro, seleccionado: true,
                motivos: motivos, dueno: "Bun", cambioAnalizado: ultimo))
        }
        return r
    }

    /// Los clones que Chrome, Brave, Edge y los demás navegadores Chromium hacen de su app al abrirse (X/<id>.code_sign_clone),
    /// para que su firma siga valiendo si se actualizan mientras funcionan. Cerrado el navegador no sirven. Casi todo lo
    /// comparten con la app instalada (son clones de APFS): se cuenta solo lo que se libera de verdad.
    private func clonesDeNavegadores(_ c: Contexto) -> [Elemento] {
        guard let x = Rutas.clonesDeFirma else { return [] }
        var r: [Elemento] = []
        for n in (try? FileManager.default.contentsOfDirectory(atPath: x)) ?? [] {
            let ruta = x + "/" + n
            var st = stat()
            guard Rutas.esClonDeFirma(ruta), lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == getuid() else { continue }
            let id = String(n.dropLast(".code_sign_clone".count))
            let app = c.apps.nombreApp(para: id) ?? Self.nombreCorto(id)
            let medida = Self.privadoDeClon(ruta)
            r.append(Elemento(
                nombre: "Clon de \(app) al abrirse",
                detalle: "Copia de \(app) que el navegador hace al abrirse para que su firma siga valiendo si se actualiza mientras funciona. Lo normal es que la borre al cerrarse.",
                consecuencia: "Nada: \(app) hace otra al volver a abrirse. Libera \(Formato.bytes(medida.privado)) de los \(Formato.bytes(medida.asignado)) que ocupa: lo demás lo comparte con la app instalada.",
                rutas: [URL(fileURLWithPath: ruta)], tamanoFijo: medida.privado, categoria: .sistema, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("square.on.square.dashed", "Clon de la app",
                                "Solo se borra con \(app) cerrado: abierto, lo necesita para comprobar su firma.")],
                enUso: .app(nombre: app, claves: [id, app]), dueno: app))
        }
        return r
    }

    /// Lo que se libera al borrar un clon: lo que sus archivos no comparten con otros (ATTR_CMNEXT_PRIVATESIZE), recorriendo
    /// como mucho `maximo` entradas. Los comprimidos por APFS no lo dicen y no se cuentan: mejor quedarse corto.
    private static func privadoDeClon(_ ruta: String, maximo: Int = 200_000) -> (privado: Int64, asignado: Int64) {
        guard let rutaC = strdup(ruta) else { return (0, 0) }
        defer { free(rutaC) }
        var argumentos: [UnsafeMutablePointer<CChar>?] = [rutaC, nil]
        guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return (0, 0) }
        defer { fts_close(fts) }
        var privado: Int64 = 0
        var asignado: Int64 = 0
        var vistos = 0
        while let e = fts_read(fts), vistos < maximo {
            vistos += 1
            switch Int32(e.pointee.fts_info) {
            case FTS_F:
                let st = e.pointee.fts_statp.pointee
                let bloques = Int64(st.st_blocks) * 512
                asignado += bloques
                guard st.st_flags & UInt32(UF_COMPRESSED) == 0 else { continue }
                privado += Privado.consultar(e.pointee.fts_path).map { min($0.privado, bloques) } ?? bloques
            case FTS_D, FTS_SL, FTS_SLNONE:
                let bloques = Int64(e.pointee.fts_statp.pointee.st_blocks) * 512
                asignado += bloques
                privado += bloques
            default:
                break
            }
        }
        return (privado, asignado)
    }

    // MARK: - Apps opcionales de Apple

    /// Una app de Apple que se puede borrar (GarageBand, iMovie…). `estaInstalado` da por instalado todo com.apple.*, así
    /// que sus restos se buscan aparte, por su identificador.
    private struct AppDeApple {
        let nombre: String
        /// Los identificadores que la dan por instalada.
        let ids: [String]
        /// Lo que empieza así en Containers, Application Scripts, Preferences y Saved Application State es suyo.
        let prefijos: [String]
        /// Sus carpetas en Application Support (solo nombres que no pueden ser de otra app).
        let soporte: [String]
        /// Sus cachés en ~/Library/Caches y en /var/folders/…/C.
        let caches: [String]
        /// Lo que comparten varias apps («las apps de música de Apple»): para decirlo en plural.
        var varias: String? = nil

        /// «No encontré <esto> en Aplicaciones…».
        var buscada: String { varias ?? nombre }
    }

    private static let appsOpcionalesDeApple: [AppDeApple] = [
        AppDeApple(nombre: "GarageBand", ids: ["com.apple.garageband10", "com.apple.garageband"],
                   prefijos: ["com.apple.garageband10", "com.apple.STMExtension.GarageBand"], soporte: ["GarageBand"],
                   caches: ["com.apple.garageband10"]),
        AppDeApple(nombre: "iMovie", ids: ["com.apple.iMovieApp"], prefijos: ["com.apple.iMovieApp"], soporte: ["iMovie"],
                   caches: ["com.apple.iMovieApp"]),
        // com.apple.MainStageApp: la de Creator Studio («MainStage Creator Studio.app»).
        AppDeApple(nombre: "MainStage", ids: ["com.apple.mainstage3", "com.apple.MainStageApp"], prefijos: ["com.apple.mainstage3", "com.apple.MainStageApp"],
                   soporte: ["MainStage"], caches: ["com.apple.MainStageApp", "com.apple.mainstage3"]),
        AppDeApple(nombre: "Logic Pro", ids: ["com.apple.logic10"], prefijos: ["com.apple.logic10"], soporte: [],
                   caches: ["com.apple.logic10"]),
        // Lo que comparten las tres apps de música: solo sobra sin ninguna de ellas.
        AppDeApple(nombre: "las apps de música de Apple", ids: ["com.apple.garageband10", "com.apple.logic10", "com.apple.mainstage3",
                                                                "com.apple.MainStageApp"],
                   prefijos: [], soporte: ["com.apple.musicapps.content"], caches: ["com.apple.musicapps"],
                   varias: "GarageBand, Logic Pro ni MainStage"),
        AppDeApple(nombre: "Keynote", ids: ["com.apple.iWork.Keynote", "com.apple.Keynote"], prefijos: ["com.apple.iWork.Keynote"],
                   soporte: [], caches: ["com.apple.iWork.Keynote"]),
        AppDeApple(nombre: "Pages", ids: ["com.apple.iWork.Pages", "com.apple.Pages"], prefijos: ["com.apple.iWork.Pages"],
                   soporte: [], caches: ["com.apple.iWork.Pages"]),
        AppDeApple(nombre: "Numbers", ids: ["com.apple.iWork.Numbers", "com.apple.Numbers"], prefijos: ["com.apple.iWork.Numbers"],
                   soporte: [], caches: ["com.apple.iWork.Numbers"]),
        AppDeApple(nombre: "Final Cut Pro", ids: ["com.apple.FinalCut", "com.apple.FinalCutTrial"], prefijos: ["com.apple.FinalCut"],
                   soporte: ["Final Cut Pro"], caches: ["com.apple.FinalCut"]),
    ]

    /// Las apps opcionales de Apple que no están: ni en Aplicaciones, ni en ~/Applications, ni en tus carpetas, ni abiertas.
    private static func appsDeAppleDesinstaladas(_ c: Contexto) -> [AppDeApple] {
        appsOpcionalesDeApple.filter { app in !app.ids.contains { c.apps.bundleIDs.contains($0.lowercased()) } }
    }

    /// Los de esos nombres (carpetas de /var/folders/…/C, por ejemplo) que son de una app opcional de Apple que ya no está:
    /// los ofrece `restosDeAppsDeApple`, así que las demás reglas no los repiten.
    static func deAppsDeAppleDesinstaladas(_ nombres: [String], _ c: Contexto) -> Set<String> {
        let desinstaladas = appsDeAppleDesinstaladas(c)
        return Set(nombres.filter { esDeAppDesinstalada($0, desinstaladas) })
    }

    /// ¿Es una carpeta (contenedor o caché) de una app opcional de Apple que ya no está? Entonces la ofrece
    /// `restosDeAppsDeApple`.
    private static func esDeAppDesinstalada(_ nombre: String, _ desinstaladas: [AppDeApple]) -> Bool {
        let l = nombre.lowercased()
        return desinstaladas.contains { app in
            app.prefijos.contains { l.hasPrefix($0.lowercased()) } || app.caches.contains { l == $0.lowercased() }
        }
    }

    /// «contenedor, ajustes y scripts»: qué hay en un resto, para el detalle.
    private static func lugaresDeResto(_ rutas: [URL]) -> [String] {
        var r: [String] = []
        func si(_ parte: String, _ texto: String) {
            if rutas.contains(where: { $0.path.contains(parte) }), !r.contains(texto) { r.append(texto) }
        }
        si("/Library/Containers/", "su contenedor")
        si("/Library/Application Support/", "sus datos")
        si("/Library/Preferences/", "sus ajustes")
        si("/Library/Application Scripts/", "sus scripts")
        si("/Library/Saved Application State/", "el estado de sus ventanas")
        si("/Library/HTTPStorages/", "sus datos web")
        si("/Library/WebKit/", "sus datos web")
        si("/Library/Cookies/", "sus cookies")
        si("/Library/Logs/", "sus registros de uso")
        return r
    }

    // MARK: - Utilidades

    /// Lo de Apple que no se toca aunque sea caché: correo, Mensajes, iCloud, la familia, Wallet, contraseñas, cuentas, lo
    /// que hace de proveedor de archivos y las descargas en segundo plano.
    private static let sensiblesDeApple = ["mobilesms", "messages", "imessage", "ichat", "imagent", "identityservices", "cloud", "family", "passkit", "passbook", "wallet",
                                           "keychain", "password", "account", "authkit", "authentication", "appsso", "platformsso",
                                           "findmy", "homekit", "fileprovider", "screentime", "nsurlsessiond", "containermanager",
                                           "feedbacklogger", "safebrowsing", "cachedelete", "cache_delete", "setupassistant",
                                           "dataaccess", "commerce", "xprotect", "devicecheck", "askpermission", "cryptotoken",
                                           "biometric", "configurationprofiles"]

    private static func esSensibleDeApple(_ id: String) -> Bool {
        let l = id.lowercased()
        if l.hasPrefix("com.apple.mail") || l.contains(".mail.") || l.hasSuffix(".mail") { return true }
        let partes = Set(l.split(separator: ".").map(String.init))
        if !partes.isDisjoint(with: ["bird", "akd", "passd", "homed", "cloudd", "sharingd", "securityd", "trustd"]) { return true }
        return sensiblesDeApple.contains { l.contains($0) }
    }

    /// Los servicios que, si pierden su caché, vuelven a analizar tus fotos.
    private static func analizaFotos(_ id: String) -> Bool {
        let l = id.lowercased()
        return ["mediaanalysisd", "photoanalysisd", "photolibraryd"].contains { l.contains($0) }
    }

    /// Por su nombre, servicios que compilan o descargan modelos (de IA, de voz, de traducción).
    private static func compilaModelos(_ id: String) -> Bool {
        let l = id.lowercased()
        return ["inference", "intelligence", "mlhost", "aiml", "priml", "generative", "textunderstanding", "visualgeneration",
                "translation", "speech", "texttospeech", "ttssupport", "siritts", "e5rt"].contains { l.contains($0) }
    }

    /// ¿Hay modelos compilados dentro (.mlmodelc, .bnnsir, e5-models…)? Solo por los nombres, sin abrir nada y hasta 3 niveles.
    /// Los de un build viejo de macOS no cuentan: ya no los usa nada.
    private static func tieneModelos(_ rutas: [URL], maximo: Int = 20_000) -> Bool {
        let finales = [".mlmodelc", ".mlpackage", ".espresso.net", ".espresso.weights", ".bnnsir"]
        var vistos = 0
        for u in rutas {
            guard let rutaC = strdup(u.path) else { continue }
            defer { free(rutaC) }
            var argumentos: [UnsafeMutablePointer<CChar>?] = [rutaC, nil]
            guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { continue }
            defer { fts_close(fts) }
            while let e = fts_read(fts) {
                vistos += 1
                // Demasiado grande para mirarlo entero: mejor suponer que sí (sale como Revisar).
                if vistos > maximo { return true }
                let tipo = Int32(e.pointee.fts_info)
                guard tipo == FTS_D || tipo == FTS_F else { continue }
                let largo = Int(e.pointee.fts_namelen)
                let n = String(cString: e.pointee.fts_path + (Int(e.pointee.fts_pathlen) - largo)).lowercased()
                if (finales.contains { n.hasSuffix($0) } || n == "e5-models" || n == "compiledmodels") && !esDeOtroBuild(n) { return true }
                if tipo == FTS_D && e.pointee.fts_level >= 3 { fts_set(fts, e, FTS_SKIP) }
            }
        }
        return false
    }

    /// Los builds de macOS que están funcionando: el del núcleo y el de SystemVersion.plist (con una actualización rápida de
    /// seguridad pueden no coincidir). Lo compilado para ellos nunca se toca.
    static let buildsActuales: Set<String> = {
        var r = Set<String>()
        var tam = 0
        if sysctlbyname("kern.osversion", nil, &tam, nil, 0) == 0, tam > 1 {
            var buf = [CChar](repeating: 0, count: tam)
            if sysctlbyname("kern.osversion", &buf, &tam, nil, 0) == 0 { r.insert(String(cString: buf)) }
        }
        if let v = NSDictionary(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist")?["ProductBuildVersion"] as? String {
            r.insert(v)
        }
        r.remove("")
        return r
    }()

    private static let patronBuild = try! NSRegularExpression(pattern: #"^\d{2}[A-Z]\d{1,5}[a-z]?$"#)
    private static let patronPrefijoDeBuild = try! NSRegularExpression(pattern: #"^(\d{2}[a-z]\d{1,5}[a-z]?)[-_]"#)

    /// «26A434», «25G83»: el nombre de un build de macOS.
    private static func pareceBuild(_ n: String) -> Bool {
        patronBuild.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
    }

    /// El build actual, o algo compilado para él («26A434-…bnnsir»).
    private static func esDelBuildActual(_ n: String) -> Bool {
        let l = n.lowercased()
        return buildsActuales.contains { b in
            let b = b.lowercased()
            return l == b || l.hasPrefix(b + "-") || l.hasPrefix(b + "_")
        }
    }

    /// Algo compilado para otro build («25G83-…»), en minúsculas.
    private static func esDeOtroBuild(_ n: String) -> Bool {
        guard let m = patronPrefijoDeBuild.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)),
              let r = Range(m.range(at: 1), in: n) else { return false }
        return !buildsActuales.contains { $0.lowercased() == n[r] }
    }

    /// Lo que se aparta de las cachés de Apple: los modelos compilados (los de builds viejos los ofrece
    /// `modelosDeBuildsAnteriores`; los del actual no se tocan).
    private static func apartadoDeApple(_ u: URL) -> Bool {
        let n = u.lastPathComponent
        return n == "com.apple.e5rt.e5bundlecache" || esDelBuildActual(n)
    }

    /// Lo que se aparta dentro de una caché de Apple: los modelos compilados y lo sensible aunque esté dentro de la caché de
    /// otra app (el estado de CloudKit, las descargas en segundo plano de nsurlsessiond, la lista de Safe Browsing).
    private static func apartadoDeCacheDeApple(_ u: URL) -> Bool {
        apartadoDeApple(u) || esSensibleDeApple(u.lastPathComponent)
    }

    /// Las rutas que cubren `carpeta` entera menos lo que `apartar` deja fuera (buscado hasta `niveles` por debajo): la
    /// carpeta misma si no hay nada que apartar; si no, sus hijos (sin enlaces), y así hacia abajo.
    private static func sinApartar(_ carpeta: URL, niveles: Int, apartar: (URL) -> Bool) -> [URL] {
        guard niveles > 0, contieneApartado(carpeta, niveles: niveles, apartar) else { return [carpeta] }
        var r: [URL] = []
        for h in Rutas.hijos(carpeta) where !esEnlaceOSuelto(h) && !apartar(h) {
            r += esCarpetaPropia(h) ? sinApartar(h, niveles: niveles - 1, apartar: apartar) : [h]
        }
        return r
    }

    private static func contieneApartado(_ carpeta: URL, niveles: Int, _ apartar: (URL) -> Bool) -> Bool {
        guard niveles > 0 else { return false }
        for h in Rutas.hijos(carpeta) where !esEnlaceOSuelto(h) {
            if apartar(h) { return true }
            if niveles > 1, esCarpetaPropia(h), contieneApartado(h, niveles: niveles - 1, apartar) { return true }
        }
        return false
    }

    /// Una carpeta de verdad (no un enlace): dentro de los contenedores, Desktop, Downloads… son enlaces a tus carpetas.
    private static func esCarpetaPropia(_ u: URL) -> Bool {
        var st = stat()
        return lstat(u.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// Un enlace, o algo que ya no está.
    private static func esEnlaceOSuelto(_ u: URL) -> Bool {
        var st = stat()
        return lstat(u.path, &st) != 0 || (st.st_mode & S_IFMT) == S_IFLNK
    }

    /// `u`, sin enlaces, sigue dentro de `raiz`: ninguna carpeta intermedia lleva fuera del contenedor.
    private static func estaDentro(_ u: URL, de raiz: URL) -> Bool {
        Rutas.real(u).hasPrefix(Rutas.real(raiz) + "/")
    }

    /// Lo que ocupa: lo que midió el índice o, si no la registró (menos de 1 MB, o fuera del índice), midiéndola aquí.
    private static func ocupa(_ u: URL, _ c: Contexto) -> Int64 {
        if let i = c.indice.info(u.path) { return i.bytes }
        var st = stat()
        guard lstat(u.path, &st) == 0 else { return 0 }
        guard (st.st_mode & S_IFMT) == S_IFDIR else { return Int64(st.st_blocks) * 512 }
        // Daemon Containers no se indexa: se mide con du.
        let fuera = u.path.hasPrefix(Rutas.enHome("Library/Daemon Containers").path + "/") || !c.indice.estaIndexada(u.path)
        return fuera ? Tamanos.de(u) : Tamanos.recorriendo(u.path)
    }

    /// Lo último que cambió dentro (del índice si la registró; si no, mirándola, con tope).
    private static func ultimoCambio(_ u: URL, _ c: Contexto) -> Date? {
        if let i = c.indice.info(u.path), i.masReciente > 0 { return Date(timeIntervalSince1970: TimeInterval(i.masReciente)) }
        var st = stat()
        guard lstat(u.path, &st) == 0 else { return nil }
        if (st.st_mode & S_IFMT) == S_IFDIR { return Fechas.masRecienteDentro(u, maximo: 5_000) }
        return Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
    }

    /// Un archivo de registro de un contenedor.
    private struct ArchivoDeRegistro {
        let url: URL
        let bytes: Int64
        let fecha: Date
    }

    /// Los archivos de registro de esas carpetas (.log, .txt, .ips, .diag…, los rotados y los .json con nombre de registro),
    /// sin seguir enlaces y con tope: nada de lo demás (bases, configuración) se toca.
    private static func archivosDeRegistro(_ carpetas: [URL], maximo: Int = 20_000) -> [ArchivoDeRegistro] {
        var r: [ArchivoDeRegistro] = []
        var vistos = 0
        for carpeta in carpetas {
            guard let rutaC = strdup(carpeta.path) else { continue }
            defer { free(rutaC) }
            var argumentos: [UnsafeMutablePointer<CChar>?] = [rutaC, nil]
            guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { continue }
            defer { fts_close(fts) }
            while let e = fts_read(fts), vistos < maximo {
                vistos += 1
                guard Int32(e.pointee.fts_info) == FTS_F else { continue }
                let st = e.pointee.fts_statp.pointee
                let largo = Int(e.pointee.fts_namelen)
                let n = String(cString: e.pointee.fts_path + (Int(e.pointee.fts_pathlen) - largo))
                guard st.st_uid == getuid(), esRegistro(n) else { continue }
                r.append(ArchivoDeRegistro(url: URL(fileURLWithPath: String(cString: e.pointee.fts_path)),
                                           bytes: Int64(st.st_blocks) * 512,
                                           fecha: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))))
            }
        }
        return r
    }

    private static func esRegistro(_ nombre: String) -> Bool {
        let l = nombre.lowercased()
        guard !l.hasPrefix(".") else { return false }
        let ext = (l as NSString).pathExtension
        if ["log", "ips", "diag", "crash", "spin", "hang"].contains(ext) { return true }
        // Un .txt puede ser una nota tuya: solo si se llama como un registro.
        if ext == "txt" { return ["log", "diag", "crash", "trace", "error", "debug", "console", "report"].contains { l.contains($0) } }
        if l.contains(".log.") { return true }   // rotados: app.log.1, app.log.gz
        if ext == "json" { return ["log", "diag", "crash", "report", "event", "trace", "metric", "telemetry"].contains { l.contains($0) } }
        return false
    }

    /// «UBF8T346G9.group.com.empresa.app» o «group.com.empresa.app» → «com.empresa.app».
    private static func sinGrupo(_ id: String) -> String {
        var r = Substring(id)
        if AppsInstaladas.equipo(de: id) != nil { r = r.dropFirst(11) }
        for p in ["group.", "groups."] where r.lowercased().hasPrefix(p) { r = r.dropFirst(p.count) }
        return String(r)
    }

    /// Nombres claros de los servicios y apps de Apple más comunes (por identificador, en minúsculas).
    private static let nombresDeApple: [String: String] = [
        "com.apple.safari": "Safari", "com.apple.geod": "Mapas (geod)", "com.apple.maps": "Mapas",
        "com.apple.mediaanalysisd": "Análisis de fotos y vídeos", "com.apple.photoanalysisd": "Análisis de Fotos",
        "com.apple.photolibraryd": "Biblioteca de Fotos", "com.apple.appstore": "App Store",
        "com.apple.wallpaper.agent": "Fondos de pantalla", "com.apple.avatarui.avatarpickermemojipicker": "Memoji",
        "com.apple.ax.mauittssupport.mauiausp": "Voces del sistema", "com.apple.notes": "Notas", "com.apple.preview": "Vista Previa",
        "com.apple.parsecd": "Sugerencias de Siri y Spotlight", "com.apple.visualintelligencecore": "Inteligencia visual",
        "com.apple.amplibraryagent": "Biblioteca de Música", "com.apple.ampartworkagent": "Carátulas de Música",
        "com.apple.spotlight": "Spotlight", "com.apple.tips": "Consejos", "com.apple.corespeech": "Reconocimiento de voz",
        "com.apple.storekit": "StoreKit", "com.apple.appstoreagent": "App Store", "com.apple.photobooth": "Photo Booth",
        "com.apple.music": "Música", "com.apple.tv": "Apple TV", "com.apple.podcasts": "Podcasts", "com.apple.news": "News",
        "com.apple.weather": "Tiempo", "com.apple.ibooksx": "Libros", "com.apple.home": "Casa",
        "com.apple.quicktimeplayerx": "QuickTime Player", "com.apple.helpviewer": "Ayuda",
        "com.apple.musicapps": "las apps de música de Apple",
    ]

    /// El nombre visible de una app o un servicio de Apple: «Safari», «Mapas (geod)», «Safari (WebApp)», «AMPArtworkAgent».
    private static func nombreDeServicio(_ id: String, _ c: Contexto) -> String {
        let base = sinGrupo(id)
        let l = base.lowercased()
        if let n = nombresDeApple[l] { return n }
        if c.apps.bundleIDs.contains(l), let n = c.apps.nombreApp(para: base) { return n }
        // Una extensión de una app conocida: «Safari (WebApp)».
        var partes = l.split(separator: ".").map(String.init)
        while partes.count > 3 {
            partes.removeLast()
            let padre = partes.joined(separator: ".")
            if let n = nombresDeApple[padre] ?? (c.apps.bundleIDs.contains(padre) ? c.apps.nombreApp(para: padre) : nil) {
                return "\(n) (\(nombreCorto(base)))"
            }
        }
        return nombreCorto(base)
    }

    /// «com.apple.AMPArtworkAgent» → «AMPArtworkAgent»; si la última parte es genérica, con la anterior
    /// («com.apple.wallpaper.agent» → «wallpaper agent»).
    private static func nombreCorto(_ id: String) -> String {
        let partes = id.split(separator: ".").map(String.init)
        guard let ultima = partes.last else { return id }
        let genericas: Set<String> = ["agent", "extension", "helper", "service", "xpc", "plugin", "widget", "daemon", "ui", "app", "mac"]
        if partes.count >= 2, genericas.contains(ultima.lowercased()) { return partes[partes.count - 2] + " " + ultima }
        return ultima
    }

    /// Quién usa la caché de un servicio de Apple: la app con ese identificador (o una extensión suya) y los programas que se
    /// llaman como su última parte («com.apple.geod» → geod; «com.apple.tips» → tipsd; «wallpaper.agent» → WallpaperAgent).
    private static func usoDeServicio(_ id: String, nombre: String) -> EnUso {
        let base = sinGrupo(id)
        let partes = base.split(separator: ".").map(String.init)
        var claves = [base, nombre]
        if partes.count >= 3, let ultima = partes.last {
            claves += [ultima, ultima + "d", ultima + "agent"]
            if partes.count >= 4 { claves.append(partes[partes.count - 2] + ultima) }
        }
        return .app(nombre: nombre, claves: claves)
    }
}
