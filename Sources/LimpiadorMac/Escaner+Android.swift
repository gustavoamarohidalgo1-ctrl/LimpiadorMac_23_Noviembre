import Foundation

/// Android (el SDK y Gradle), Homebrew, Xcode y Swift: lo que las reglas de siempre ofrecen entero solo para «Liberar al
/// máximo» (las dependencias de Gradle, el Gradle que usa un proyecto) y lo que nadie miraba: las herramientas del SDK que
/// no usas, las fórmulas de Homebrew que no usa ningún proyecto, los casks sin su app, el adb repetido, los toolchains de
/// Swift y los instaladores de Xcode.
extension Escaner {

    // MARK: - Ganchos por categoría

    /// Lo que se añade a «Emuladores» (el SDK de Android).
    func sdkDeAndroidAmpliado(_ c: Contexto) -> [Elemento] {
        herramientasDeTerminalSinUso(c) + extrasObsoletosDelSDK(c) + nativoSinProyectos(c)
    }

    /// Lo que va junto a las reglas de siempre de «Cachés de desarrollo», no detrás: está dentro de lo que ellas ofrecen
    /// entero solo para «Liberar al máximo» (~/.gradle/caches/modules-2 y el Gradle que usa un proyecto), y `conAnadidas`
    /// lo quitaría por repetido. Lo de aquí se libera ya en el modo normal (y cuenta una vez: una carpeta y algo de dentro
    /// suman una vez, como el emulador entero y su «Restablecer»).
    func gradleAFondo(_ c: Contexto) -> [Elemento] {
        dependenciasDeGradleSinUso(c) + descargasDeGradleAMedias(c)
    }

    /// Lo que se añade a «Cachés de desarrollo»: fórmulas y casks de Homebrew, el adb repetido y los toolchains de Swift.
    /// También apunta la nota de lo que «brew cleanup» no quita.
    func homebrewYSwift(_ c: Contexto) -> [Elemento] {
        anotarLoQueCleanupNoQuita(c)
        return formulasSinUso(c) + adbRepetido(c) + casksSinApp(c) + toolchainsDeSwift(c)
    }

    /// Lo que se añade a «Instaladores olvidados».
    func instaladoresDeXcode(_ c: Contexto) -> [Elemento] {
        xipsDeXcodes(c)
    }

    // MARK: - Utilidades de estas reglas

    private static let unDia = 86_400

    /// Qué hay en esa ruta (S_IFDIR, S_IFREG, S_IFLNK…), sin seguir enlaces. nil si no existe.
    private static func claseDe(_ ruta: String) -> mode_t? {
        var st = stat()
        return lstat(ruta, &st) == 0 ? (st.st_mode & S_IFMT) : nil
    }

    /// Una carpeta de verdad (no un enlace a una).
    private static func esCarpetaReal(_ ruta: String) -> Bool { claseDe(ruta) == S_IFDIR }

    /// Lo que hay en una carpeta, sin lo oculto, ordenado.
    private static func visibles(en carpeta: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    /// Compara dos cadenas de versión de menor a mayor respetando pre-lanzamientos:
    /// «35.0.0-rc4» < «35.0.0» (una versión estable siempre es más nueva que su RC/beta).
    static func compararVersion(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: "-", maxSplits: 1)
        let pb = b.split(separator: "-", maxSplits: 1)
        let baseA = String(pa.first ?? "")
        let baseB = String(pb.first ?? "")
        let cmp = baseA.compare(baseB, options: .numeric)
        if cmp != .orderedSame { return cmp == .orderedAscending }
        let preA = pa.count > 1 ? String(pa[1]) : nil
        let preB = pb.count > 1 ? String(pb[1]) : nil
        switch (preA, preB) {
        case (nil, nil): return a.compare(b, options: .numeric) == .orderedAscending
        case (.some, nil): return true   // pre-release < estable
        case (nil, .some): return false  // estable > pre-release
        case let (.some(x), .some(y)): return x.compare(y, options: .numeric) == .orderedAscending
        }
    }

    /// Las versiones (subcarpetas de verdad) de una carpeta, de la más vieja a la más nueva.
    private static func versionesEn(_ carpeta: String) -> [String] {
        visibles(en: carpeta).filter { esCarpetaReal(carpeta + "/" + $0) }
            .sorted { compararVersion($0, $1) }
    }

    /// Las versiones de verdad de una carpeta del SDK de Android (build-tools, ndk, cmake), de la más vieja a la más nueva:
    /// sin los enlaces (un «latest» o un enlace a otra carpeta no es una versión, y lo que hay al otro lado puede ser tuyo),
    /// y los nombres de las versiones a las que apunta un enlace de al lado: se usan a través de él y no son antiguas.
    static func versionesDelSDK(_ carpeta: URL) -> (versiones: [URL], apuntadas: Set<String>) {
        let ruta = carpeta.path
        let apuntadas = visibles(en: ruta).compactMap { try? FileManager.default.destinationOfSymbolicLink(atPath: ruta + "/" + $0) }
        return (versionesEn(ruta).map { carpeta.appendingPathComponent($0) }, Set(apuntadas.map { Rutas.nombre($0) }))
    }

    /// La última lectura (atime) de un archivo, siguiendo su enlace (un programa se lee al ejecutarse), en segundos desde
    /// 1970. 0 si no existe.
    private static func ultimaLectura(_ ruta: String) -> Int {
        var st = stat()
        return stat(ruta, &st) == 0 ? Int(st.st_atimespec.tv_sec) : 0
    }

    /// La fecha de modificación de una ruta, sin seguir enlaces, en segundos desde 1970. 0 si no existe.
    private static func cambioDe(_ ruta: String) -> Int {
        var st = stat()
        return lstat(ruta, &st) == 0 ? Int(st.st_mtimespec.tv_sec) : 0
    }

    /// Un archivo pequeño (256 KB o menos) como texto, sin seguir enlaces.
    private static func textoCorto(_ ruta: String, maximo: Int64 = 262_144) -> String? {
        var st = stat()
        guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, Int64(st.st_size) <= maximo else { return nil }
        return try? String(contentsOfFile: ruta, encoding: .utf8)
    }

    /// Un JSON pequeño (como mucho `maximo` bytes), sin seguir enlaces.
    private static func jsonCorto(_ ruta: String, maximo: Int64 = 1_000_000) -> Any? {
        var st = stat()
        guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, Int64(st.st_size) <= maximo,
              let datos = FileManager.default.contents(atPath: ruta) else { return nil }
        return try? JSONSerialization.jsonObject(with: datos)
    }

    /// Lo que dicen las fechas de lo que hay dentro de una carpeta, recorrida sin seguir enlaces.
    private struct FechasDentro {
        /// La última lectura (atime) más reciente de sus archivos.
        var lectura = 0
        /// El último cambio más reciente (archivos y carpetas).
        var cambio = 0
        /// El nacimiento del archivo más antiguo.
        var nacimiento = Int.max
        var archivos = 0
        /// Lo que ocupa, contado como `Tamanos.recorriendo`.
        var bytes: Int64 = 0
    }

    /// Las fechas de lo de dentro de una carpeta. nil si tiene más de `maximo` entradas o algo no se pudo leer: entonces no
    /// se sabe y no se ofrece nada por ellas.
    private static func fechasDentro(_ ruta: String, maximo: Int = 50_000) -> FechasDentro? {
        guard let rutaC = strdup(ruta) else { return nil }
        defer { free(rutaC) }
        var argumentos: [UnsafeMutablePointer<CChar>?] = [rutaC, nil]
        guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return nil }
        defer { fts_close(fts) }
        var r = FechasDentro()
        var vistos = 0
        while let e = fts_read(fts) {
            vistos += 1
            let tipo = Int32(e.pointee.fts_info)
            if vistos > maximo || tipo == FTS_DNR || tipo == FTS_ERR || tipo == FTS_NS { return nil }
            guard tipo == FTS_F || tipo == FTS_D || tipo == FTS_SL else { continue }
            let st = e.pointee.fts_statp.pointee
            r.bytes += Int64(st.st_blocks) * 512 / (tipo == FTS_F ? max(1, Int64(st.st_nlink)) : 1)
            r.cambio = max(r.cambio, Int(st.st_mtimespec.tv_sec))
            guard tipo == FTS_F else { continue }
            r.archivos += 1
            r.lectura = max(r.lectura, Int(st.st_atimespec.tv_sec))
            r.nacimiento = min(r.nacimiento, Int(st.st_birthtimespec.tv_sec))
        }
        return r
    }

    private static func fecha(_ segundos: Int) -> Date? { segundos > 0 ? Date(timeIntervalSince1970: TimeInterval(segundos)) : nil }

    /// «hace 3 meses», «ayer»…, para ir dentro de una frase.
    private static func cuando(_ segundos: Int) -> String { Formato.haceCuanto(fecha(segundos)).lowercased() }

    /// Hay un SDK de Flutter: su comando en el PATH de la terminal o en las carpetas de siempre (también las de FVM).
    /// Flutter pide las cmdline-tools del SDK de Android y CocoaPods aunque no haya ningún proyecto a la vista.
    private func hayFlutter(_ c: Contexto) -> Bool {
        if c.apps.pathTerminal.contains(where: { FileManager.default.isExecutableFile(atPath: $0 + "/flutter") }) { return true }
        for rel in ["flutter", "development/flutter", "Developer/flutter", "src/flutter", "sdk/flutter", "sdks/flutter"]
        where Rutas.existe(Rutas.enHome(rel + "/bin/flutter")) { return true }
        for rel in ["fvm/versions", ".fvm/versions"] where !Self.visibles(en: Rutas.enHome(rel).path).isEmpty { return true }
        return false
    }

    // MARK: - Proyectos de Gradle

    /// Los proyectos de Gradle que conoce el índice (las carpetas con gradle/wrapper) y la versión de Gradle que pide cada
    /// uno en su gradle-wrapper.properties.
    private func proyectosConGradle(_ c: Contexto) -> [(raiz: String, version: String?)] {
        c.indice.wrappersGradle.map { w in
            let raiz = Rutas.padre(Rutas.padre(Rutas.padre(w)))
            guard let texto = Self.textoCorto(w),
                  let linea = texto.split(separator: "\n").first(where: { $0.hasPrefix("distributionUrl") }),
                  let rango = linea.range(of: "gradle-") else { return (raiz, nil) }
            return (raiz, linea[rango.upperBound...].split(separator: "-").first.map(String.init))
        }
    }

    /// Cuándo compiló (o se sincronizó con el editor) por última vez cada proyecto de Gradle: lo último que cambió en su
    /// carpeta .gradle, donde Gradle apunta cada compilación (fileChanges/last-build.bin, executionHistory, el candado de
    /// buildOutputCleanup…). 0 si no tiene .gradle: no ha compilado nunca en este Mac.
    private func ultimasCompilaciones(_ c: Contexto) -> [(nombre: String, fecha: Int)] {
        proyectosConGradle(c).map { p in
            let carpeta = p.raiz + "/.gradle"
            return (Rutas.nombre(p.raiz), Self.esCarpetaReal(carpeta) ? Fechas.ultimoCambio([carpeta]) : 0)
        }
    }

    /// La última vez que Gradle trabajó en este Mac, con cualquier proyecto: también con los que el índice no ve (en un disco
    /// externo, en la nube, sin gradle/wrapper). Lo último que cambió en el candado de sus dependencias, en los informes de
    /// compilación de Kotlin y en las cachés y los registros de cada versión (~/.gradle/caches/<versión> y
    /// ~/.gradle/daemon/<versión>, dos niveles: no se recorren). 0 si nunca.
    private static func ultimoUsoDeGradle() -> Int {
        let gradle = Rutas.enHome(".gradle").path
        var r = max(cambioDe(gradle + "/caches/modules-2/modules-2.lock"), cambioDe(gradle + "/kotlin-profile"))
        for base in [gradle + "/caches", gradle + "/daemon"] {
            for v in visibles(en: base) where v.first?.isNumber == true && esCarpetaReal(base + "/" + v) {
                r = max(r, cambioDe(base + "/" + v))
                for n in visibles(en: base + "/" + v) { r = max(r, cambioDe(base + "/" + v + "/" + n)) }
            }
        }
        return r
    }

    /// Hay algún proyecto de Gradle que no veo: ninguno en el índice, pero Gradle trabajó en los últimos 30 días. Entonces
    /// lo que «no usa ningún proyecto» puede ser de ese (`ultimoUsoDeGradle`, 0 si no).
    private func gradleSinProyectosAlaVista(_ c: Contexto) -> Int {
        guard proyectosConGradle(c).isEmpty else { return 0 }
        let uso = Self.ultimoUsoDeGradle()
        return uso > Int(Date().timeIntervalSince1970) - 30 * Self.unDia ? uso : 0
    }

    /// Si cambiaste la limpieza automática de Gradle (que borra lo que lleva 30 días sin usarse): un script de
    /// ~/.gradle/init.d que la configura o la propiedad antigua org.gradle.cache.cleanup. Ante la duda (un script que no se
    /// puede leer), como si la hubieras cambiado.
    private static func limpiezaDeGradleCambiada() -> Bool {
        let initD = Rutas.enHome(".gradle/init.d").path
        for n in visibles(en: initD) where n.hasSuffix(".gradle") || n.hasSuffix(".kts") {
            guard let texto = textoCorto(initD + "/" + n) else { return true }
            if ["cacheCleanup", "Cleanup.DISABLED", "removeUnused", "setRemoveUnused"].contains(where: texto.contains) { return true }
        }
        return textoCorto(Rutas.enHome(".gradle/gradle.properties").path)?.contains("org.gradle.cache.cleanup") ?? false
    }

    // MARK: - Dependencias de Gradle

    /// Las dependencias que descargó Gradle (~/.gradle/caches/modules-2/files-2.1/<grupo>/<librería>/<versión>) y que no
    /// necesita ningún proyecto de los que hay en el disco:
    /// - las que llegaron después de la última compilación de todos tus proyectos de Gradle y nadie lee desde hace 7 días:
    ///   las pidieron proyectos que ya no están, porque ninguno de los de ahora ha compilado desde entonces;
    /// - las demás que nadie lee desde hace 30 días, si ningún proyecto ha compilado en 30 días: lo mismo que borraría el
    ///   propio Gradle al compilar (si no cambiaste esa limpieza en ~/.gradle/init.d). Si alguno compiló, Gradle ya hace
    ///   esa limpieza él solo (y sabe mejor que la fecha de lectura qué usa: con sus cachés puede compilar sin leerlas).
    /// Seguro: Gradle vuelve a descargar lo que le falte. Las primeras se marcan solas si no queda ningún proyecto que las
    /// pueda pedir; las segundas, siempre. Nada si Gradle está funcionando o abrió su caché en las últimas 24 h.
    func dependenciasDeGradleSinUso(_ c: Contexto) -> [Elemento] {
        let modulos = Rutas.enHome(".gradle/caches/modules-2").path
        let archivos = modulos + "/files-2.1"
        guard Self.esCarpetaReal(archivos), !c.procesos.gradle else { return [] }
        let ahora = Int(Date().timeIntervalSince1970)
        // El candado de la caché cambia cada vez que Gradle la abre.
        if Self.cambioDe(modulos + "/modules-2.lock") > ahora - Self.unDia { return [] }
        let compilaciones = ultimasCompilaciones(c)
        let ultima = compilaciones.map(\.fecha).max() ?? 0
        let gradleLimpia = !Self.limpiezaDeGradleCambiada()
        var deBorrados: [(ruta: String, quieta: Int, bytes: Int64)] = []
        var olvidadas: [(ruta: String, quieta: Int, bytes: Int64)] = []
        for grupo in Self.visibles(en: archivos) where Self.esCarpetaReal(archivos + "/" + grupo) {
            let g = archivos + "/" + grupo
            for libreria in Self.visibles(en: g) where Self.esCarpetaReal(g + "/" + libreria) {
                let l = g + "/" + libreria
                for version in Self.visibles(en: l) {
                    let ruta = l + "/" + version
                    guard Self.esCarpetaReal(ruta), let f = Self.fechasDentro(ruta, maximo: 5_000), f.archivos > 0 else { continue }
                    let quieta = max(f.lectura, f.cambio)
                    let bytes = c.indice.info(ruta)?.bytes ?? f.bytes
                    if f.nacimiento > ultima && quieta < ahora - 7 * Self.unDia {
                        deBorrados.append((ruta, quieta, bytes))
                    } else if gradleLimpia && quieta < ahora - 30 * Self.unDia {
                        olvidadas.append((ruta, quieta, bytes))
                    }
                }
            }
        }
        let nombres = compilaciones.map(\.nombre)
        // Gradle trabajó en 30 días con un proyecto que no veo (disco externo, nube, sin wrapper): puede que las use él.
        let sinVer = gradleSinProyectosAlaVista(c)
        var r: [Elemento] = []
        if !deBorrados.isEmpty {
            let rutas = deBorrados.map { URL(fileURLWithPath: $0.ruta) }
            let tamanos = deBorrados.map(\.bytes)
            let total = tamanos.reduce(0, +)
            let lectura = deBorrados.map(\.quieta).max() ?? 0
            let marcar = compilaciones.isEmpty && sinVer == 0
            let porque = compilaciones.isEmpty
                ? (sinVer > 0
                    ? "No encontré ningún proyecto de Gradle en tus carpetas, pero Gradle trabajó \(Self.cuando(sinVer)): puede que tengas alguno en un disco externo, en la nube o sin gradle/wrapper, y que las use. Si no, las pidieron proyectos que ya no están."
                    : "No encontré ningún proyecto de Gradle en tus carpetas: las pidieron proyectos que ya no están. Si tienes alguno en un disco externo, no lo veo: al compilarlo, Gradle descargará lo que le falte.")
                : (ultima > 0 ? "Llegaron después de la última compilación de tus proyectos de Gradle (\(Formato.listaCorta(nombres)), \(Self.cuando(ultima))), así que no las pidió ninguno de ellos: las pidieron proyectos que ya no están."
                              : "Tus proyectos de Gradle (\(Formato.listaCorta(nombres))) no han compilado nunca en este Mac, así que no las pidió ninguno de ellos: las pidieron proyectos que ya no están.")
            var motivos: [Motivo] = [
                sinVer > 0 ? .info("questionmark.folder.fill", "Ningún proyecto a la vista", porque)
                           : .bien("questionmark.folder.fill", "De proyectos que ya no están", porque),
                .bien("moon.zzz.fill", "Sin leer desde \(Self.cuando(lectura))",
                      "Ningún archivo de estas versiones se ha leído en 7 días o más, y Gradle no está funcionando."),
            ]
            if !marcar {
                motivos.append(nombres.isEmpty
                    ? .info("arrow.down.circle.fill", "Puede que las pida un proyecto que no veo",
                            "Si un proyecto que no está en tus carpetas las usa, Gradle las vuelve a descargar al compilarlo (necesita internet). Por eso no las marco solas.")
                    : .info("arrow.down.circle.fill", "Puede que las pida \(nombres.count == 1 ? nombres[0] : "uno de tus proyectos")",
                            "Algunas librerías pueden ser las mismas que usa \(Formato.listaCorta(nombres)): si las necesita al compilar, Gradle las vuelve a descargar (necesita internet). Por eso no las marco solas."))
            }
            r.append(Elemento(
                nombre: "Dependencias de Gradle de proyectos que ya no están",
                detalle: "\(Formato.numero(deBorrados.count)) \(deBorrados.count == 1 ? "versión" : "versiones") de librerías que Gradle descargó en ~/.gradle/caches/modules-2 (\(Formato.listaCorta(Self.librerias(deBorrados.map(\.ruta)), maximo: 4))).",
                consecuencia: marcar
                    ? "Nada: ningún proyecto de los que tienes las usa. Si vuelves a abrir o crear un proyecto que las necesite, Gradle las descarga otra vez al compilar (necesita internet)."
                    : "Si \(nombres.isEmpty ? "un proyecto" : Formato.listaCorta(nombres)) necesita alguna en su próxima compilación, Gradle la descarga otra vez (necesita internet). No se pierde nada.",
                rutas: rutas, tamanosRutas: tamanos, ultimoUso: Self.fecha(lectura),
                categoria: .desarrollo, riesgo: .seguro, seleccionado: marcar, motivos: motivos,
                enUso: .gradle, dueno: "Gradle", costes: marcar ? [] : [.descarga(bytes: total)],
                cambioAnalizado: Self.fecha(lectura)))
        }
        // Un proyecto que compila a diario con sus cachés (la de configuración, las huellas de archivos) puede no leer sus
        // librerías en semanas: si alguno compiló en los últimos 30 días, la limpieza de Gradle ya funciona y se deja a ella.
        // También si el que compiló no está a la vista (en un disco externo, en la nube, sin wrapper): lo dice el propio
        // Gradle (`ultimoUsoDeGradle`).
        let activos = compilaciones.contains { $0.fecha > ahora - 30 * Self.unDia } || Self.ultimoUsoDeGradle() > ahora - 30 * Self.unDia
        if !olvidadas.isEmpty && !activos {
            let rutas = olvidadas.map { URL(fileURLWithPath: $0.ruta) }
            let tamanos = olvidadas.map(\.bytes)
            let lectura = olvidadas.map(\.quieta).max() ?? 0
            let motivos: [Motivo] = [
                .bien("arrow.triangle.2.circlepath", "Lo borraría Gradle",
                      "Gradle borra él mismo las dependencias que llevan 30 días sin usarse, pero solo cuando compila, y no ha compilado nada en 30 días. Ninguno de estos archivos se ha leído desde \(Self.cuando(lectura))."),
            ]
            r.append(Elemento(
                nombre: "Dependencias de Gradle sin usar en 30 días",
                detalle: "\(Formato.numero(olvidadas.count)) \(olvidadas.count == 1 ? "versión" : "versiones") de librerías de ~/.gradle/caches/modules-2 que nadie lee hace más de un mes (\(Formato.listaCorta(Self.librerias(olvidadas.map(\.ruta)), maximo: 4))).",
                consecuencia: "Si un proyecto vuelve a necesitar alguna, Gradle la descarga otra vez al compilar (necesita internet). No se pierde nada.",
                rutas: rutas, tamanosRutas: tamanos, ultimoUso: Self.fecha(lectura),
                categoria: .desarrollo, riesgo: .seguro, seleccionado: true, motivos: motivos,
                enUso: .gradle, dueno: "Gradle", cambioAnalizado: Self.fecha(lectura)))
        }
        return r
    }

    /// «…/files-2.1/androidx.core/core/1.16.0» → «core 1.16.0», sin repetir la librería.
    private static func librerias(_ rutas: [String]) -> [String] {
        var vistas = Set<String>()
        return rutas.compactMap { r in
            let libreria = Rutas.nombre(Rutas.padre(r))
            return vistas.insert(libreria).inserted ? "\(libreria) \(Rutas.nombre(r))" : nil
        }
    }

    // MARK: - Descargas del wrapper de Gradle

    /// Dentro de cada ~/.gradle/wrapper/dists/gradle-<v>-bin/<hash> de un Gradle que usa algún proyecto (los demás ya se
    /// ofrecen enteros y marcados en «Gradle <v>»):
    /// - el ZIP de una distribución ya descomprimida: el wrapper se fija en su marca «.ok» y en la carpeta gradle-<v>, no
    ///   en el ZIP;
    /// - las descargas que se cortaron (sin la marca «.ok»), con más de 1 día sin cambios: el wrapper las vuelve a empezar.
    /// Seguro y marcado. Nada si un programa tiene algo abierto ahí (el wrapper descargando tiene su .lck abierto).
    func descargasDeGradleAMedias(_ c: Contexto) -> [Elemento] {
        let usadas = proyectosConGradle(c).reduce(into: [String: [String]]()) { r, p in
            if let v = p.version { r[v, default: []].append(Rutas.nombre(p.raiz)) }
        }
        let dists = Rutas.enHome(".gradle/wrapper/dists").path
        let ahora = Int(Date().timeIntervalSince1970)
        var r: [Elemento] = []
        for dist in Self.visibles(en: dists) where dist.hasPrefix("gradle-") && Self.esCarpetaReal(dists + "/" + dist) {
            let v = dist.replacingOccurrences(of: "gradle-", with: "").replacingOccurrences(of: "-bin", with: "")
                .replacingOccurrences(of: "-all", with: "")
            guard let proyectos = usadas[v] else { continue }
            for hash in Self.visibles(en: dists + "/" + dist) {
                let carpeta = dists + "/" + dist + "/" + hash
                guard Self.esCarpetaReal(carpeta), c.procesos.abiertos.hayAbierto(dentroDe: carpeta) == nil else { continue }
                let zip = carpeta + "/" + dist + ".zip"
                let listo = Self.claseDe(zip + ".ok") == S_IFREG
                let extraida = Self.esCarpetaReal(carpeta + "/gradle-" + v)
                if listo && extraida && Self.claseDe(zip) == S_IFREG {
                    r.append(Elemento(
                        nombre: "ZIP de Gradle \(v) ya descomprimido",
                        detalle: "El archivo que descargó el wrapper de Gradle \(v) (el de \(Formato.listaCorta(proyectos))). Ya está descomprimido al lado y listo para usar.",
                        consecuencia: "Nada: el wrapper usa la carpeta descomprimida (gradle-\(v)) y su marca «.ok», que se quedan. \(Formato.listaCorta(proyectos)) sigue compilando igual.",
                        rutas: [URL(fileURLWithPath: zip)], categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                        motivos: [.bien("doc.zipper", "Ya descomprimido",
                                        "Junto al ZIP están la carpeta gradle-\(v) y la marca «.ok» con la que el wrapper sabe que la instalación terminó bien: no vuelve a mirar el ZIP.")],
                        enUso: .gradleVersion(v), dueno: "Gradle"))
                } else if !listo {
                    let quieta = Fechas.ultimoCambio([carpeta])
                    let algo = Self.claseDe(zip) == S_IFREG || Self.claseDe(zip + ".part") == S_IFREG || extraida
                    guard algo, quieta > 0, quieta < ahora - Self.unDia else { continue }
                    r.append(Elemento(
                        nombre: "Descarga a medias de Gradle \(v)",
                        detalle: "Una descarga o instalación del wrapper de Gradle \(v) que se cortó (\(Self.cuando(quieta))): no tiene la marca «.ok» de una instalación terminada.",
                        consecuencia: "Nada: el wrapper no la puede usar. La próxima vez que compiles \(Formato.listaCorta(proyectos)), descarga Gradle \(v) otra vez entero (necesita internet), igual que haría ahora.",
                        rutas: [URL(fileURLWithPath: carpeta)], ultimoUso: Self.fecha(quieta),
                        categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                        motivos: [.bien("arrow.down.circle.dotted", "A medias",
                                        "Sin la marca «.ok» el wrapper no la usa: la borra y empieza de cero. Lleva más de un día sin cambios y nadie tiene nada abierto dentro.")],
                        enUso: .gradleVersion(v), dueno: "Gradle", cambioAnalizado: Self.fecha(quieta)))
                }
            }
        }
        return r
    }

    // MARK: - Herramientas del SDK de Android

    /// Las cmdline-tools del SDK («latest»: sdkmanager, avdmanager, lint, apkanalyzer) cuando ninguno de sus archivos se ha
    /// leído en 30 días y no hay Flutter (que las pide para aceptar las licencias). Android Studio no las necesita: su SDK
    /// Manager y su Device Manager van dentro de la app. Revisar: un script tuyo puede llamar a sdkmanager.
    func herramientasDeTerminalSinUso(_ c: Contexto) -> [Elemento] {
        let latest = sdkAndroid(c).path + "/cmdline-tools/latest"
        guard Self.esCarpetaReal(latest), let f = Self.fechasDentro(latest, maximo: 5_000), f.archivos > 0 else { return [] }
        let ahora = Int(Date().timeIntervalSince1970)
        let quieta = max(f.lectura, f.cambio)
        guard quieta < ahora - 30 * Self.unDia, !hayFlutter(c) else { return [] }
        let version = (Self.textoCorto(latest + "/source.properties") ?? "").split(separator: "\n")
            .first { $0.hasPrefix("Pkg.Revision=") }.map { " " + $0.dropFirst(13).trimmingCharacters(in: .whitespaces) } ?? ""
        let url = URL(fileURLWithPath: latest)
        return [Elemento(
            nombre: "Herramientas de terminal del SDK de Android sin usar",
            detalle: "Las cmdline-tools\(version) del SDK de Android: sdkmanager, avdmanager, lint y apkanalyzer para usarlos desde la terminal.",
            consecuencia: "Android Studio sigue funcionando igual: su SDK Manager y su Device Manager no las usan. Si algún día usas sdkmanager o avdmanager en la terminal, se instalan otra vez desde Android Studio › Settings › SDK Tools › «Android SDK Command-line Tools».",
            rutas: [url], ultimoUso: Self.fecha(quieta), categoria: .emuladores, riesgo: .revisar,
            motivos: [.info("terminal.fill", "Sin usar desde \(Self.cuando(quieta))",
                            "Ninguno de sus archivos se ha leído desde \(Self.cuando(quieta)) (lo dice la fecha de la última lectura de cada uno): sdkmanager y avdmanager no se usan desde entonces."),
                      .info("questionmark.circle", "Si las usa un script",
                            "Flutter, fastlane o tus scripts de compilación pueden llamar a sdkmanager. No encontré Flutter; si tienes un script que las use, déjalas.")],
            enUso: .proceso(nombre: "sdkmanager", patron: "/cmdline-tools/"), dueno: "Android Studio",
            costes: [.descarga(bytes: c.indice.bytes(de: url))])]
    }

    /// Hay un Mac con Apple Silicon (aunque la app funcione con Rosetta).
    private static let esAppleSilicon: Bool = {
        var valor: Int32 = 0
        var tam = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &valor, &tam, nil, 0) == 0 && valor == 1
    }()

    /// Lo de sdk/extras que no sirve en este Mac: el acelerador HAXM de Intel en un Mac con Apple Silicon y el driver USB
    /// de Google, que es para Windows (Seguro y marcados); y los repositorios Maven locales (m2repository) que sustituyó
    /// maven.google.com en 2017, si ningún proyecto los nombra (Seguro; marcados si ningún proyecto usa un Gradle anterior
    /// al 4.1, cuyo plugin de Android los usaba sin nombrarlos).
    func extrasObsoletosDelSDK(_ c: Contexto) -> [Elemento] {
        let extras = sdkAndroid(c).path + "/extras"
        guard Self.esCarpetaReal(extras) else { return [] }
        let androidStudio = EnUso.app(nombre: "Android Studio", claves: ["com.google.android.studio"])
        var r: [Elemento] = []
        var sinUso: [String] = []
        var ques: [String] = []
        let intel = extras + "/intel"
        if Self.esAppleSilicon {
            let haxm = Self.visibles(en: intel).map { intel + "/" + $0 }.filter(Self.esCarpetaReal)
            if !haxm.isEmpty { sinUso += haxm; ques.append("el acelerador HAXM de Intel, que no funciona en un Mac con Apple Silicon") }
        }
        let usb = extras + "/google/usb_driver"
        if Self.esCarpetaReal(usb) { sinUso.append(usb); ques.append("el driver USB de Google, que es para Windows") }
        if !sinUso.isEmpty {
            r.append(Elemento(
                nombre: "Extras del SDK de Android que no sirven en este Mac",
                detalle: "De la carpeta extras del SDK: \(Formato.lista(ques)).",
                consecuencia: "Nada: en este Mac no se pueden usar. El emulador usa el Hypervisor de macOS.",
                rutas: sinUso.map { URL(fileURLWithPath: $0) }, categoria: .emuladores, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("xmark.circle.fill", "No sirven en macOS", "Son para otro sistema o para otro procesador: ningún programa de este Mac los usa.")],
                enUso: androidStudio, dueno: "Android Studio"))
        }
        let repos = ["google", "android"].map { extras + "/" + $0 + "/m2repository" }.filter(Self.esCarpetaReal)
        guard !repos.isEmpty else { return r }
        var nombran: [String] = []
        var antiguos: [String] = []
        for p in proyectosConGradle(c) {
            let nombre = Rutas.nombre(p.raiz)
            if let v = p.version, v.compare("4.1", options: .numeric) == .orderedAscending { antiguos.append(nombre) }
            let modulos = [p.raiz] + Self.visibles(en: p.raiz).map { p.raiz + "/" + $0 }.filter(Self.esCarpetaReal)
            let archivos = modulos.flatMap { [$0 + "/build.gradle", $0 + "/build.gradle.kts"] } + [p.raiz + "/settings.gradle", p.raiz + "/settings.gradle.kts"]
            if archivos.contains(where: { Self.textoCorto($0)?.contains("m2repository") ?? false }) { nombran.append(nombre) }
        }
        guard nombran.isEmpty else { return r }
        var motivos: [Motivo] = [.bien("arrow.triangle.2.circlepath", "Sustituidos por maven.google.com",
            "Desde 2017 las librerías de Google se descargan de maven.google.com. Ninguno de tus proyectos nombra estos repositorios.")]
        if !antiguos.isEmpty {
            motivos.append(.info("clock.arrow.circlepath", "Proyecto antiguo",
                "\(Formato.listaCorta(antiguos)) usa un Gradle anterior al 4.1, cuyo plugin de Android buscaba aquí sin nombrarlo. Por eso no lo marco solo."))
        }
        // Un proyecto que no veo (disco externo, nube, sin wrapper) puede usarlos: Gradle los lee aquí mismo, sin copiarlos.
        let sinVer = gradleSinProyectosAlaVista(c)
        if sinVer > 0 {
            motivos.append(.info("questionmark.folder.fill", "Puede que los use un proyecto que no veo",
                "No encontré ningún proyecto de Gradle en tus carpetas, pero Gradle trabajó \(Self.cuando(sinVer)). Si ese proyecto está en un disco externo o en la nube y usa estos repositorios, Gradle los lee de aquí (no guarda una copia). Por eso no los marco solos."))
        }
        r.append(Elemento(
            nombre: "Repositorios Maven antiguos del SDK de Android",
            detalle: "Copias locales de las librerías de soporte y de Google Play (extras/…/m2repository) de antes de 2017.",
            consecuencia: "Nada para un proyecto actual: descarga esas librerías de maven.google.com. Si abres uno muy antiguo que las necesite, se instalan otra vez desde el SDK Manager.",
            rutas: repos.map { URL(fileURLWithPath: $0) }, categoria: .emuladores, riesgo: .seguro, seleccionado: antiguos.isEmpty && sinVer == 0,
            // Quien los lee es Gradle (al compilar), no Android Studio.
            motivos: motivos, enUso: .gradle, dueno: "Android Studio"))
        return r
    }

    /// Lo que nombra el código nativo en un build.gradle, gradle.properties o local.properties.
    private static let palabrasDeNativo = ["externalNativeBuild", "ndkVersion", "ndkPath", "ndk.dir", "ndkBuild", "ndk {", "cmake {"]

    /// Los proyectos de Gradle que compilan código nativo (C/C++) o que lo pueden compilar sin nombrarlo: con src/main/cpp,
    /// jni, .cxx o un CMakeLists.txt en algún módulo (hasta dos niveles), con el NDK en su configuración, o que son la
    /// carpeta android/ de un proyecto de Flutter o de React Native.
    private func proyectosConNativo(_ c: Contexto) -> [String] {
        var r: [String] = []
        for p in proyectosConGradle(c) {
            let padre = Rutas.padre(p.raiz)
            let nombre = Rutas.nombre(p.raiz) == "android" ? Rutas.nombre(padre) : Rutas.nombre(p.raiz)
            if [padre, p.raiz].contains(where: { Rutas.existe($0 + "/pubspec.yaml") || Rutas.existe($0 + "/node_modules/react-native") }) {
                r.append(nombre)
                continue
            }
            var modulos = [p.raiz]
            for m in Self.visibles(en: p.raiz) where !["build", "node_modules", "gradle"].contains(m) && Self.esCarpetaReal(p.raiz + "/" + m) {
                modulos.append(p.raiz + "/" + m)
                for s in Self.visibles(en: p.raiz + "/" + m) where !["build", "src", "libs"].contains(s) && Self.esCarpetaReal(p.raiz + "/" + m + "/" + s) {
                    modulos.append(p.raiz + "/" + m + "/" + s)
                }
            }
            let marcas = ["src/main/cpp", "src/main/jni", "jni", ".cxx", "CMakeLists.txt"]
            let nativo = modulos.contains { m in
                marcas.contains { Rutas.existe(m + "/" + $0) }
                    || ["build.gradle", "build.gradle.kts"].contains { a in Self.palabrasDeNativo.contains { Self.textoCorto(m + "/" + a)?.contains($0) ?? false } }
            } || ["gradle.properties", "local.properties", "gradle/libs.versions.toml"].contains { a in
                Self.palabrasDeNativo.contains { Self.textoCorto(p.raiz + "/" + a)?.contains($0) ?? false }
            }
            if nativo { r.append(nombre) }
        }
        return r
    }

    /// La versión más nueva del NDK y de CMake del SDK (las anteriores ya las ofrece «Emuladores») cuando ningún proyecto
    /// compila código nativo y su compilador (clang o cmake) no se ha usado en 30 días. Revisar: los usan también otros
    /// programas (motores de juegos, cargo-ndk…) y volver a descargarlos cuesta (el NDK pesa de 1 a 3 GB).
    func nativoSinProyectos(_ c: Contexto) -> [Elemento] {
        let sdk = sdkAndroid(c).path
        let ahora = Int(Date().timeIntervalSince1970)
        var nativos: [String]?
        var r: [Elemento] = []
        for (carpeta, nombre, detalle) in [("ndk", "Android NDK", "El kit para compilar código nativo (C/C++) en apps de Android."),
                                           ("cmake", "CMake de Android", "La herramienta con la que el NDK compila el código nativo.")] {
            guard let ultima = Self.versionesEn(sdk + "/" + carpeta).last else { continue }
            let ruta = sdk + "/" + carpeta + "/" + ultima
            // Flutter usa el NDK en cada compilación de Android aunque el proyecto no lo nombre.
            let proyectos = nativos ?? (hayFlutter(c) ? ["Flutter"] : proyectosConNativo(c))
            nativos = proyectos
            guard proyectos.isEmpty else { return r }
            // El compilador de esa versión: su última lectura dice cuándo se usó.
            let ejecutable: String?
            if carpeta == "ndk" {
                let prebuilt = ruta + "/toolchains/llvm/prebuilt"
                ejecutable = Self.visibles(en: prebuilt).map { prebuilt + "/" + $0 + "/bin/clang" }.first { Self.ultimaLectura($0) > 0 }
            } else {
                ejecutable = ruta + "/bin/cmake"
            }
            guard let ejecutable, case let lectura = Self.ultimaLectura(ejecutable), lectura > 0,
                  lectura < ahora - 30 * Self.unDia else { continue }
            let url = URL(fileURLWithPath: ruta)
            r.append(Elemento(
                nombre: "\(nombre) \(ultima) sin proyectos con código nativo",
                detalle: "\(detalle) Es la versión más nueva que tienes.",
                consecuencia: "Si algún proyecto vuelve a compilar código nativo, Android Studio (o Gradle) la descarga otra vez (necesita internet).",
                rutas: [url], ultimoUso: Self.fecha(lectura), categoria: .emuladores, riesgo: .revisar,
                motivos: [.info("cpu", "Sin código nativo",
                                "Ninguno de tus proyectos de Android tiene código C/C++ (src/main/cpp, CMakeLists.txt, externalNativeBuild, ndkVersion) ni es de Flutter o React Native, que lo compilan sin nombrarlo. Su compilador no se usa desde \(Self.cuando(lectura))."),
                          .info("gamecontroller.fill", "Otros programas", "Los motores de juegos y algunas herramientas (cargo-ndk, Qt) también lo usan: si trabajas con alguno, déjalo.")],
                enUso: .rutas(nombre: nombre, raiz: ruta), dueno: "Android Studio",
                costes: [.descarga(bytes: c.indice.bytes(de: url))]))
        }
        return r
    }

    // MARK: - Restos que no son de apps borradas

    /// Kotlin (y Gradle, que usa su daemon) están en este Mac: hay ~/.gradle, un JDK o el comando kotlinc.
    private static func hayKotlin(_ c: Contexto) -> Bool {
        if esCarpetaReal(Rutas.enHome(".gradle").path) { return true }
        if [Rutas.enHome("Library/Java/JavaVirtualMachines").path, "/Library/Java/JavaVirtualMachines"]
            .contains(where: { !visibles(en: $0).isEmpty }) { return true }
        return c.apps.pathTerminal.contains { FileManager.default.isExecutableFile(atPath: $0 + "/kotlinc") }
    }

    /// Los registros de una carpeta de ~/Library/Logs que solo tiene registros del emulador de Android (emulator.log,
    /// emulator-1.log…), si hay datos de Android en este Mac (~/.android). nil si tiene algo más.
    private static func registrosDelEmulador(en carpeta: String) -> [String]? {
        guard esCarpetaReal(Rutas.enHome(".android").path) else { return nil }
        let dentro = visibles(en: carpeta)
        guard !dentro.isEmpty, dentro.allSatisfy({ $0.hasPrefix("emulator") && ($0.hasSuffix(".log") || $0.contains(".log.")) }),
              dentro.allSatisfy({ claseDe(carpeta + "/" + $0) == S_IFREG }) else { return nil }
        return dentro
    }

    /// Carpetas de ~/Library que parecen restos de una app borrada y no lo son (para `restos`): Application Support/kotlin,
    /// la del daemon de compilación de Kotlin (de Gradle y del plugin de Kotlin), y una de Logs con solo los registros de un
    /// emulador de Android (la crea el emulador con el nombre del dispositivo). Lo que sobra de ellas lo ofrece «Cachés
    /// sueltas de herramientas de desarrollo» (`restosSueltosDeAndroid`).
    func noEsRestoDeApp(_ lugar: String, _ carpeta: URL, _ c: Contexto) -> Bool {
        switch lugar {
        case "Library/Application Support": return carpeta.lastPathComponent == "kotlin" && Self.hayKotlin(c)
        case "Library/Logs": return Self.registrosDelEmulador(en: carpeta.path) != nil
        default: return false
        }
    }

    /// Para «Cachés sueltas de herramientas de desarrollo»: los registros y temporales del daemon de Kotlin de más de 7
    /// días (Application Support/kotlin/daemon) y las carpetas de ~/Library/Logs con solo registros del emulador, si su
    /// dispositivo ya no existe o llevan 7 días sin cambios.
    static func restosSueltosDeAndroid(_ c: Contexto) -> [(url: URL, que: String, uso: EnUso?)] {
        let ahora = Int(Date().timeIntervalSince1970)
        var r: [(url: URL, que: String, uso: EnUso?)] = []
        let daemon = Rutas.enHome("Library/Application Support/kotlin/daemon").path
        if hayKotlin(c) {
            let uso = EnUso.proceso(nombre: "El daemon de Kotlin", patron: "kotlincompiledaemon")
            for n in visibles(en: daemon) where (n.hasSuffix(".log") || n.hasSuffix(".tmp")) && claseDe(daemon + "/" + n) == S_IFREG
                && cambioDe(daemon + "/" + n) < ahora - 7 * unDia {
                r.append((URL(fileURLWithPath: daemon + "/" + n), "registros del daemon de Kotlin", uso))
            }
        }
        let emulador = EnUso.programas(nombre: "El emulador de Android", ejecutables: ["qemu-system-aarch64", "qemu-system-x86_64",
                                                                                      "qemu-system-aarch64-headless", "qemu-system-x86_64-headless",
                                                                                      "emulator"])
        let logs = Rutas.enHome("Library/Logs").path
        for n in visibles(en: logs) where esCarpetaReal(logs + "/" + n) {
            guard registrosDelEmulador(en: logs + "/" + n) != nil else { continue }
            let quieta = Fechas.ultimoCambio([logs + "/" + n])
            let existe = Rutas.existe(Rutas.enHome(".android/avd/\(n).avd")) || c.indice.avds.contains { Rutas.nombre($0) == n + ".avd" }
            guard !existe || quieta < ahora - 7 * unDia else { continue }
            r.append((URL(fileURLWithPath: logs + "/" + n), "registros del emulador de Android", emulador))
        }
        return r
    }

    // MARK: - Fórmulas de Homebrew

    /// Una fórmula instalada de Homebrew: la versión que se usa (a la que apunta opt/<fórmula>) y lo que dice su recibo de
    /// instalación (INSTALL_RECEIPT.json).
    struct FormulaInstalada {
        let nombre: String
        let version: String
        /// true si la pediste tú; false si llegó como dependencia de otra; nil si el recibo no lo dice.
        let pedida: Bool?
        /// Todas las fórmulas que necesita para funcionar (también las de sus dependencias).
        let necesita: Set<String>
        /// Se pudo leer su recibo con la lista de lo que necesita.
        let legible: Bool
    }

    /// Las fórmulas instaladas en un Homebrew (sin ejecutar brew), por nombre.
    static func formulasInstaladas(prefijo: String) -> [String: FormulaInstalada] {
        var r: [String: FormulaInstalada] = [:]
        for f in visibles(en: prefijo + "/Cellar") where esCarpetaReal(prefijo + "/Cellar/" + f) {
            guard let destino = try? FileManager.default.destinationOfSymbolicLink(atPath: prefijo + "/opt/" + f) else {
                // Sin opt/<fórmula> no se sabe qué versión se usa ni qué necesita.
                r[f] = FormulaInstalada(nombre: f, version: "", pedida: nil, necesita: [], legible: false)
                continue
            }
            let version = Rutas.nombre(destino)
            let recibo = jsonCorto(prefijo + "/Cellar/" + f + "/" + version + "/INSTALL_RECEIPT.json") as? [String: Any]
            let lista = recibo?["runtime_dependencies"] as? [[String: Any]]
            let pedida = (recibo?["installed_on_request"] as? Bool) ?? (recibo?["installed_as_dependency"] as? Bool).map { !$0 }
            r[f] = FormulaInstalada(nombre: f, version: version, pedida: pedida,
                                    necesita: Set((lista ?? []).compactMap { ($0["full_name"] as? String).map { Rutas.nombre($0) } }),
                                    legible: lista != nil)
        }
        return r
    }

    /// Las dependencias de `formula` que solo usa ella: llegaron como dependencia (no las pediste tú) y ninguna otra fórmula
    /// instalada las necesita (salvo otras de la misma lista). `conservar`, las que algo tuyo usa. Si algún recibo no se pudo
    /// leer, ninguna: no se sabe quién las necesita.
    static func dependenciasSoloDe(_ formula: String, _ formulas: [String: FormulaInstalada], conservar: Set<String> = []) -> [String] {
        guard let f = formulas[formula], formulas.values.allSatisfy(\.legible) else { return [] }
        var quitar = Set(f.necesita.filter { formulas[$0]?.pedida == false && !conservar.contains($0) })
        var cambio = true
        while cambio {
            cambio = false
            for d in quitar where formulas.values.contains(where: { o in o.nombre != formula && !quitar.contains(o.nombre) && o.necesita.contains(d) }) {
                quitar.remove(d)
                cambio = true
            }
        }
        return quitar.sorted()
    }

    /// Las fórmulas de herramientas que no usa nada de lo que tienes: CocoaPods sin ningún proyecto que lo pida, con las
    /// dependencias que solo usa él. Revisar, con el comando oficial «brew uninstall» (nunca a la fuerza: si otra fórmula
    /// necesita alguna, Homebrew se niega y no quita nada). Solo el Homebrew de tu usuario. Ollama sin modelos no se ofrece:
    /// es la nota «Ollama sin ningún modelo» (`notaDeOllamaSinModelos`), que mira también su uso y no lo ofrece para borrar.
    func formulasSinUso(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        for prefijo in Rutas.homebrew {
            let brew = prefijo + "/bin/brew"
            var st = stat()
            guard lstat(prefijo + "/Cellar", &st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid(),
                  FileManager.default.isExecutableFile(atPath: brew) else { continue }
            let formulas = Self.formulasInstaladas(prefijo: prefijo)
            guard let pods = formulas["cocoapods"] else { continue }
            // Las versiones viejas que ya ofrece «Versiones antiguas de Homebrew» (las que quitará «brew cleanup»): los dos
            // son comandos y, si no, esos bytes se contarían dos veces. Solo las de CocoaPods y lo que necesita.
            let suyas = pods.necesita.union(["cocoapods"])
            let restos = Self.restosDeHomebrew(prefijo: prefijo).filter { suyas.contains(Rutas.nombre(Rutas.padre($0.ruta))) }
            let saltadas = Self.cleanupNoQuita(prefijo: prefijo, restos).versiones
            let yaContadas = Set(restos.map(\.ruta).filter { saltadas[$0] == nil })
            if let e = cocoaPodsSinProyectos(prefijo, formulas, yaContadas, c) { r.append(e) }
        }
        return r
    }

    /// Lo que ocupan unas fórmulas en Cellar (todas sus versiones), sin lo de `yaContadas` (las versiones viejas que cuenta
    /// «Versiones antiguas de Homebrew»).
    private static func enCellar(_ formulas: [String], prefijo: String, sin yaContadas: Set<String>) -> (rutas: [URL], bytes: Int64) {
        let rutas = formulas.map { prefijo + "/Cellar/" + $0 }.filter(esCarpetaReal)
        let todo = rutas.reduce(Int64(0)) { $0 + Tamanos.recorriendo($1) }
        let contado = yaContadas.filter { v in rutas.contains { v.hasPrefix($0 + "/") } }.reduce(Int64(0)) { $0 + Tamanos.recorriendo($1) }
        return (rutas.map { URL(fileURLWithPath: $0) }, max(0, todo - contado))
    }

    /// CocoaPods de Homebrew cuando ningún proyecto tuyo tiene Podfile (ni carpeta Pods), no hay Flutter y «pod» no se usa
    /// desde hace 30 días. Con él, el Ruby y la libyaml que instaló solo para él (el Ruby se queda si tienes algún Gemfile o
    /// lo usaste en 30 días).
    private func cocoaPodsSinProyectos(_ prefijo: String, _ formulas: [String: FormulaInstalada], _ yaContadas: Set<String>,
                                       _ c: Contexto) -> Elemento? {
        guard let pods = formulas["cocoapods"], !pods.version.isEmpty else { return nil }
        let carpeta = prefijo + "/Cellar/cocoapods/" + pods.version
        let programas = ["bin", "libexec/bin"].flatMap { d in Self.visibles(en: carpeta + "/" + d).map { carpeta + "/" + d + "/" + $0 } }
        let ahora = Int(Date().timeIntervalSince1970)
        let lectura = (programas.map(Self.ultimaLectura) + [Self.cambioDe(carpeta)]).max() ?? 0
        guard lectura > 0, lectura < ahora - 30 * Self.unDia, !hayFlutter(c) else { return nil }
        let marcas = c.indice.marcasDeRuby
        guard !marcas.contains(where: { Rutas.nombre($0) == "Podfile" }), !c.indice.artefactos.contains(where: { $0.tipo == .pods }) else { return nil }
        var conservar = Set<String>()
        let gemfiles = marcas.filter { Rutas.nombre($0) == "Gemfile" }
        if let ruby = formulas["ruby"], !ruby.version.isEmpty {
            let usoRuby = Self.ultimaLectura(prefijo + "/Cellar/ruby/" + ruby.version + "/bin/ruby")
            if !gemfiles.isEmpty || usoRuby > ahora - 30 * Self.unDia { conservar.insert("ruby") }
        }
        let dependencias = Self.dependenciasSoloDe("cocoapods", formulas, conservar: conservar)
        let quitar = ["cocoapods"] + dependencias
        let (rutas, bytes) = Self.enCellar(quitar, prefijo: prefijo, sin: yaContadas)
        var motivos: [Motivo] = [
            .info("shippingbox", "Ningún proyecto lo usa",
                  "No encontré ningún Podfile ni carpeta Pods en tus carpetas, ni ningún SDK de Flutter (que lo usa para iOS)."),
            .info("moon.zzz.fill", "Sin usar desde \(Self.cuando(lectura))", "El comando pod no se ha ejecutado desde \(Self.cuando(lectura))."),
        ]
        if !dependencias.isEmpty {
            motivos.append(.info("link", "Con lo que instaló para él",
                "\(Formato.lista(dependencias)) \(dependencias.count == 1 ? "llegó" : "llegaron") como dependencia de CocoaPods y ninguna otra fórmula \(dependencias.count == 1 ? "la" : "las") necesita (lo dicen los recibos de instalación de Homebrew)."))
        }
        if conservar.contains("ruby") {
            motivos.append(.info("hand.raised.fill", "El Ruby se queda",
                gemfiles.isEmpty ? "Usaste el Ruby de Homebrew en los últimos 30 días." : "Tienes proyectos con Gemfile (\(Formato.listaCorta(gemfiles.map { Rutas.nombre(Rutas.padre($0)) }))): pueden usar el Ruby de Homebrew."))
        }
        return Elemento(
            nombre: "CocoaPods de Homebrew sin ningún proyecto que lo use",
            detalle: "El gestor de dependencias de iOS CocoaPods \(pods.version)\(dependencias.isEmpty ? "" : ", con \(Formato.lista(dependencias.map { "\($0) \(formulas[$0]?.version ?? "")" }))"), instalado con Homebrew.",
            consecuencia: "Lo quita Homebrew con su comando «brew uninstall \(quitar.joined(separator: " "))», sin forzar nada: si otra fórmula necesitara alguna, Homebrew no quitaría nada. No pasa por la Papelera. Tus proyectos no se tocan, y ~/.cocoapods (su índice de librerías) se queda. Si lo vuelves a necesitar: «brew install cocoapods».",
            rutas: rutas, tamanoFijo: bytes, ultimoUso: Self.fecha(lectura), categoria: .desarrollo, riesgo: .revisar,
            accion: .comando(programa: prefijo + "/bin/brew", argumentos: ["uninstall"] + quitar, entorno: Self.entornoDeBrew, limite: 300),
            motivos: motivos, enUso: .proceso(nombre: "CocoaPods", patron: "/cellar/cocoapods/"), dueno: "Homebrew")
    }

    // MARK: - adb repetido

    /// El cask android-platform-tools de Homebrew cuando el SDK de Android ya tiene sus platform-tools (adb, fastboot): dos
    /// copias. Se ofrece quitar el cask, nunca la del SDK, que usan Android Studio y el emulador. Revisar: la terminal puede
    /// estar usando la del cask.
    func adbRepetido(_ c: Contexto) -> [Elemento] {
        let delSDK = sdkAndroid(c).path + "/platform-tools"
        guard Self.claseDe(delSDK + "/adb") == S_IFREG else { return [] }
        let versionSDK = (Self.textoCorto(delSDK + "/source.properties") ?? "").split(separator: "\n")
            .first { $0.hasPrefix("Pkg.Revision=") }.map { $0.dropFirst(13).trimmingCharacters(in: .whitespaces) }
        var r: [Elemento] = []
        for prefijo in Rutas.homebrew {
            let brew = prefijo + "/bin/brew"
            let cask = prefijo + "/Caskroom/android-platform-tools"
            var st = stat()
            guard lstat(cask, &st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid(),
                  FileManager.default.isExecutableFile(atPath: brew), let suya = Self.versionesEn(cask).last,
                  // Si las del SDK son las del cask (sdk/platform-tools, o el SDK entero, es un enlace al cask), no hay dos
                  // copias: quitar el cask dejaría al SDK sin adb.
                  !Rutas.real(URL(fileURLWithPath: delSDK + "/adb")).hasPrefix(Rutas.real(URL(fileURLWithPath: cask)) + "/") else { continue }
            // «37.0.1» (a veces con más datos tras una coma).
            let version = String(suya.split(separator: ",").first ?? Substring(suya))
            let primero = c.apps.pathTerminal.first { FileManager.default.isExecutableFile(atPath: $0 + "/adb") }
            let laDelCask = primero.map { Rutas.real(URL(fileURLWithPath: $0 + "/adb")).hasPrefix(Rutas.real(URL(fileURLWithPath: cask)) + "/") } ?? false
            var motivos: [Motivo] = []
            if let versionSDK, versionSDK != version {
                let nueva = versionSDK.compare(version, options: .numeric) == .orderedDescending ? "la del SDK (\(versionSDK))" : "la de Homebrew (\(version))"
                motivos.append(.aviso("exclamationmark.arrow.triangle.2.circlepath", "Versiones distintas",
                    "La del SDK es la \(versionSDK) y la de Homebrew la \(version) (la más nueva es \(nueva)). Dos adb de versiones distintas se cierran el servidor el uno al otro («adb server version doesn't match»)."))
            } else {
                motivos.append(.info("square.on.square", "Dos copias iguales",
                    "Las dos son la versión \(version). En cuanto Android Studio actualice la del SDK dejarán de coincidir, y dos adb de versiones distintas se cierran el servidor el uno al otro."))
            }
            if laDelCask {
                motivos.append(.aviso("terminal.fill", "La terminal usa la de Homebrew",
                    "Al escribir «adb» la terminal usa la del cask. Sin ella, añade la del SDK a tu PATH (por ejemplo, en ~/.zprofile: export PATH=\"$HOME/Library/Android/sdk/platform-tools:$PATH\")."))
            }
            r.append(Elemento(
                nombre: "adb repetido: platform-tools de Homebrew y del SDK de Android",
                detalle: "El cask android-platform-tools \(version) de Homebrew (adb y fastboot) es una segunda copia de lo que ya trae el SDK de Android en \(Formato.rutaCorta(delSDK)).",
                consecuencia: "Lo quita Homebrew con su comando «brew uninstall --cask android-platform-tools»: se borran su adb y su fastboot (y sus enlaces en \(prefijo)/bin). Las platform-tools del SDK, las que usan Android Studio y el emulador, no se tocan. No pasa por la Papelera.",
                rutas: [URL(fileURLWithPath: cask)], tamanoFijo: Tamanos.recorriendo(cask),
                ultimoUso: Self.fecha(Self.ultimaLectura(cask + "/" + suya + "/platform-tools/adb")),
                categoria: .desarrollo, riesgo: .revisar,
                accion: .comando(programa: brew, argumentos: ["uninstall", "--cask", "android-platform-tools"], entorno: Self.entornoDeBrew, limite: 120),
                motivos: motivos, enUso: .rutas(nombre: "adb", raiz: cask), dueno: "Homebrew"))
        }
        return r
    }

    // MARK: - Casks sin su app

    /// Si un cask de Homebrew (Caskroom/<cask>) ya no tiene su app: en sus versiones solo hay apps (*.app) que son enlaces a
    /// una app que ya no existe (se borró a mano, sin brew). Homebrew lo sigue dando por instalado. Lo usa también
    /// `AppsInstaladas.cargar`, que no lo cuenta como instalado para que se vean sus restos.
    static func caskSinApp(_ carpeta: String) -> Bool {
        let versiones = visibles(en: carpeta).filter { esCarpetaReal(carpeta + "/" + $0) }
        guard !versiones.isEmpty else { return false }
        for v in versiones {
            let dentro = visibles(en: carpeta + "/" + v)
            guard !dentro.isEmpty, dentro.allSatisfy({ $0.hasSuffix(".app") }) else { return false }
            for app in dentro {
                let ruta = carpeta + "/" + v + "/" + app
                // Un enlace cuyo destino no existe (fileExists sigue el enlace), y no porque esté en un disco que ahora no
                // está conectado (/Volumes/…): ahí la app sigue existiendo.
                guard claseDe(ruta) == S_IFLNK, !FileManager.default.fileExists(atPath: ruta),
                      let destino = try? FileManager.default.destinationOfSymbolicLink(atPath: ruta),
                      !destino.hasPrefix("/Volumes/") else { return false }
            }
        }
        return true
    }

    /// Lo que haría «brew uninstall --cask» con un cask es solo quitar su app (que ya no está) y su registro: su recibo
    /// (.metadata/INSTALL_RECEIPT.json) no tiene más pasos de desinstalación (cerrar apps, quitar agentes de inicio, borrar
    /// archivos, ejecutar scripts, binarios…) que la app y el «zap», que solo se hace con --zap. Sin recibo, no se sabe.
    static func caskSoloConApp(_ carpeta: String) -> Bool {
        guard let recibo = jsonCorto(carpeta + "/.metadata/INSTALL_RECEIPT.json") as? [String: Any],
              (recibo["uninstall_flight_blocks"] as? Bool) == false,
              let artefactos = recibo["uninstall_artifacts"] as? [[String: Any]], !artefactos.isEmpty else { return false }
        return artefactos.allSatisfy { $0.keys.allSatisfy { $0 == "app" || $0 == "zap" } }
    }

    /// Para el Limpiador, justo antes de ejecutar «brew uninstall --cask»: la app de un cask (Caskroom/<cask>) que no
    /// estaba al analizar y ahora vuelve a estar (la reinstalaste a mano). brew la borraría con el cask. nil si no hay.
    static func appDeCaskQueVolvio(_ carpeta: String) -> String? {
        for v in visibles(en: carpeta) where esCarpetaReal(carpeta + "/" + v) {
            for app in visibles(en: carpeta + "/" + v) where app.hasSuffix(".app") {
                let ruta = carpeta + "/" + v + "/" + app
                if claseDe(ruta) == S_IFLNK, FileManager.default.fileExists(atPath: ruta) {
                    return (try? FileManager.default.destinationOfSymbolicLink(atPath: ruta)) ?? ruta
                }
            }
        }
        return nil
    }

    /// Los casks de Homebrew cuya app ya no está (`caskSinApp`) y no hay otra app con su nombre en este Mac: Revisar, con
    /// «brew uninstall --cask», que solo quita su registro. Se enseñan aunque no pesen: Homebrew los intenta actualizar.
    func casksSinApp(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        for prefijo in Rutas.homebrew {
            let brew = prefijo + "/bin/brew"
            let caskroom = prefijo + "/Caskroom"
            var st = stat()
            guard lstat(caskroom, &st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid(),
                  FileManager.default.isExecutableFile(atPath: brew) else { continue }
            var casks: [String] = []
            var apps: [String] = []
            // Solo los que brew desinstala sin hacer nada más que quitar su registro (`caskSoloConApp`).
            for token in Self.visibles(en: caskroom) where Self.caskSinApp(caskroom + "/" + token) && Self.caskSoloConApp(caskroom + "/" + token) {
                let suyas = Self.versionesEn(caskroom + "/" + token).flatMap { Self.visibles(en: caskroom + "/" + token + "/" + $0) }
                    .map { ($0 as NSString).deletingPathExtension }
                // Si hay una app con ese nombre en otro sitio (la moviste), no es un cask roto.
                guard !suyas.contains(where: { c.apps.nombreApp(para: $0) != nil }) else { continue }
                casks.append(token)
                apps += suyas
            }
            guard !casks.isEmpty else { continue }
            let rutas = casks.map { caskroom + "/" + $0 }
            r.append(Elemento(
                nombre: casks.count == 1 ? "Cask de Homebrew sin su app: \(casks[0])" : "Casks de Homebrew sin su app (\(casks.count))",
                detalle: "Homebrew sigue dando por \(casks.count == 1 ? "instalado" : "instalados") \(Formato.lista(casks)), pero \(apps.count == 1 ? "su app (\(apps[0]))" : "sus apps (\(Formato.lista(apps)))") ya no \(apps.count == 1 ? "está" : "están") donde \(apps.count == 1 ? "la puso" : "las puso"): se borró o se movió a mano, sin brew.",
                consecuencia: "Lo quita Homebrew con su comando «brew uninstall --cask \(casks.joined(separator: " "))»: solo borra su registro en Caskroom, porque la app ya no está (su recibo no tiene más pasos de desinstalación). Así Homebrew deja de intentar actualizarla, y lo que dejó la app en tu carpeta se ve en «Restos de apps borradas». Si la moviste a un sitio que no veo, se queda donde está, pero Homebrew ya no la actualiza. Si al limpiar la app vuelve a estar en su sitio, no lo hago (brew la borraría). No pasa por la Papelera.",
                rutas: rutas.map { URL(fileURLWithPath: $0) }, tamanoFijo: rutas.reduce(Int64(0)) { $0 + Tamanos.recorriendo($1) },
                categoria: .desarrollo, riesgo: .revisar,
                accion: .comando(programa: brew, argumentos: ["uninstall", "--cask"] + casks, entorno: Self.entornoDeBrew, limite: 120),
                motivos: [.info("app.dashed", apps.count == 1 ? "Sin su app" : "Sin sus apps",
                                apps.count == 1
                                    ? "En Caskroom solo queda el enlace a \(apps[0]).app, que ya no existe, y no encontré ninguna app con ese nombre en este Mac."
                                    : "En Caskroom solo quedan los enlaces a \(Formato.lista(apps.map { $0 + ".app" })), que ya no existen, y no encontré ninguna app con esos nombres en este Mac.")],
                enUso: .proceso(nombre: "Homebrew", patron: "/library/homebrew/brew."), dueno: "Homebrew",
                siempreVisible: true))
        }
        return r
    }

    // MARK: - Lo que «brew cleanup» no quita

    /// La versión más nueva de cada una de esas fórmulas según la caché de la API de Homebrew (la que usa brew sin
    /// actualizarse, como lo ejecuta esta app), con su revisión («1.17.0_1»). nil si no hay caché de la API.
    static func versionesDeLaAPI(_ formulas: Set<String>) -> [String: String]? {
        let cache = Rutas.casaDePrueba ? nil : ProcessInfo.processInfo.environment["HOMEBREW_CACHE"]
        let api = (cache ?? Rutas.enHome("Library/Caches/Homebrew").path) + "/api"
        // Homebrew de ahora: internal/packages.<plataforma>.jws.json, con su contenido aparte (.payload) y un índice.
        let interna = api + "/internal"
        let cargas = visibles(en: interna).filter { $0.hasPrefix("packages.") && $0.hasSuffix(".jws.json.payload") }
            .max { cambioDe(interna + "/" + $0) < cambioDe(interna + "/" + $1) }
        if let carga = cargas, let r = versionesConIndice(interna + "/" + carga, formulas) { return r }
        // Antes: formula.jws.json, un JWS con todas las fórmulas.
        guard let datos = FileManager.default.contents(atPath: api + "/formula.jws.json"),
              let jws = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let carga = (jws["payload"] as? String)?.data(using: .utf8),
              let lista = try? JSONSerialization.jsonObject(with: carga) as? [[String: Any]] else { return nil }
        var r: [String: String] = [:]
        for f in lista {
            guard let n = f["name"] as? String, formulas.contains(n),
                  let estable = (f["versions"] as? [String: Any])?["stable"] as? String else { continue }
            r[n] = conRevision(estable, f["revision"] as? Int ?? 0)
        }
        return r
    }

    private static func conRevision(_ version: String, _ revision: Int) -> String { revision > 0 ? "\(version)_\(revision)" : version }

    /// Lee del contenido de la API (packages.*.jws.json.payload: una línea con la firma y otra con el JSON) solo las fórmulas
    /// pedidas, con el índice que Homebrew deja al lado (.payload.index: dónde empieza y cuánto mide cada una).
    private static func versionesConIndice(_ carga: String, _ formulas: Set<String>) -> [String: String]? {
        guard let indice = jsonCorto(carga + ".index", maximo: 20_000_000) as? [String: Any],
              let posiciones = indice["formulae"] as? [String: [Int]],
              let archivo = FileHandle(forReadingAtPath: carga) else { return nil }
        defer { try? archivo.close() }
        guard let inicio = try? archivo.read(upToCount: 1 << 20), let salto = inicio.firstIndex(of: 10) else { return nil }
        let base = UInt64(salto - inicio.startIndex + 1)
        var tam = stat()
        guard lstat(carga, &tam) == 0, let total = indice["payload_bytesize"] as? Int, total >= 0,
              tam.st_size >= 0, UInt64(tam.st_size) == base + UInt64(total) else { return nil }
        var r: [String: String] = [:]
        for n in formulas {
            guard let p = posiciones[n], p.count == 2, p[0] >= 0, p[1] > 0, p[1] < 10_000_000,
                  (try? archivo.seek(toOffset: base + UInt64(p[0]))) != nil,
                  let trozo = try? archivo.read(upToCount: p[1]),
                  let f = try? JSONSerialization.jsonObject(with: trozo) as? [String: Any],
                  let estable = f["stable_version"] as? String else { continue }
            r[n] = conRevision(estable, f["revision"] as? Int ?? 0)
        }
        return r
    }

    /// De lo que quitaría «brew cleanup» (`restosDeHomebrew`), las versiones viejas que no quitará: las de una fórmula que
    /// tiene una versión más nueva sin instalar según la API («most recent version not installed»), con esa versión.
    /// `conAPI` es false si no hay caché de la API: entonces no se sabe.
    static func cleanupNoQuita(prefijo: String, _ restos: [RestoDeHomebrew]) -> (versiones: [String: String], conAPI: Bool) {
        let enCellar = restos.filter { $0.ruta.hasPrefix(prefijo + "/Cellar/") && !$0.ruta.hasSuffix(".reinstall") }
        let formulas = Set(enCellar.map { Rutas.nombre(Rutas.padre($0.ruta)) })
        guard !formulas.isEmpty else { return ([:], true) }
        guard let api = versionesDeLaAPI(formulas) else { return ([:], false) }
        var r: [String: String] = [:]
        for resto in enCellar {
            let f = Rutas.nombre(Rutas.padre(resto.ruta))
            guard let nueva = api[f], let usada = try? FileManager.default.destinationOfSymbolicLink(atPath: prefijo + "/opt/" + f),
                  Rutas.nombre(usada).compare(nueva, options: .numeric) == .orderedAscending else { continue }
            r[resto.ruta] = nueva
        }
        return (r, true)
    }

    /// Una nota con las versiones viejas que «brew cleanup» no quita (`cleanupNoQuita`): «Versiones antiguas de Homebrew»
    /// ya no las promete, y aquí se dice por qué y cómo liberarlas (actualizando esa fórmula, que es cosa tuya).
    func anotarLoQueCleanupNoQuita(_ c: Contexto) {
        for prefijo in Rutas.homebrew {
            var st = stat()
            guard lstat(prefijo + "/Cellar", &st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid(),
                  FileManager.default.isExecutableFile(atPath: prefijo + "/bin/brew") else { continue }
            let restos = Self.restosDeHomebrew(prefijo: prefijo)
            let saltadas = Self.cleanupNoQuita(prefijo: prefijo, restos).versiones
            guard !saltadas.isEmpty else { continue }
            let rutas = saltadas.keys.sorted()
            let bytes = rutas.reduce(Int64(0)) { $0 + Tamanos.recorriendo($1) }
            guard bytes >= minimo else { continue }
            var nuevas: [String: String] = [:]
            for ruta in rutas { nuevas[Rutas.nombre(Rutas.padre(ruta))] = saltadas[ruta] }
            let formulas = nuevas.keys.sorted()
            c.indice.notas.append(NotaGrande(
                categoria: .desarrollo, titulo: "Versiones antiguas de Homebrew que «brew cleanup» no quita",
                texto: "Ocupan sitio \(Formato.lista(rutas.map { "\(Rutas.nombre(Rutas.padre($0))) \(Rutas.nombre($0))" })), que ya no usas. Homebrew tiene una versión más nueva de \(Formato.lista(formulas.map { "\($0) (\(nuevas[$0] ?? ""))" })) sin instalar, y mientras no la instales «brew cleanup» deja sus versiones viejas como están: por eso no van en «Versiones antiguas de Homebrew». Se liberan al actualizar: «brew upgrade \(formulas.joined(separator: " "))» instala la nueva y, al terminar, Homebrew quita las viejas. No lo hago yo: actualizar cambia tus programas y necesita internet.",
                ruta: rutas[0], bytes: bytes))
        }
    }

    // MARK: - Command Line Tools

    /// El texto de la nota de las Command Line Tools (`notaDeLineaDeComandos`): cuándo se usaron por última vez (la última
    /// lectura de su clang, git, swift, ld y su Python 3), qué SDK de macOS llevan dentro y el comando completo para
    /// quitarlas, con todos sus recibos (si quedan, Actualización de software las puede volver a ofrecer).
    static func textoDeLineaDeComandos(_ clt: String, xcode: String) -> String {
        var uso = ["clang", "git", "swift-frontend", "ld", "python3"].map { ultimaLectura(clt + "/usr/bin/" + $0) }.max() ?? 0
        if let python = fechasDentro(clt + "/Library/Frameworks/Python3.framework", maximo: 200_000) { uso = max(uso, python.lectura) }
        let ahora = Int(Date().timeIntervalSince1970)
        let dias = uso > 0 ? (ahora - uso) / unDia : Int.max
        let cuandoSeUsaron = uso == 0 ? ""
            : dias < 30 ? " Aun así, algo las usó \(cuando(uso)) (lo dice la última lectura de sus programas o de su Python 3): si tienes scripts o entornos que las piden, déjalas."
            : " Nada las usa desde \(cuando(uso)) (la última lectura de sus programas y de su Python 3)."
        let sdks = visibles(en: clt + "/SDKs").filter { $0.hasSuffix(".sdk") && esCarpetaReal(clt + "/SDKs/" + $0) }
            .map { $0.replacingOccurrences(of: "MacOSX", with: "").replacingOccurrences(of: ".sdk", with: "") }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        let conSDK = sdks.isEmpty ? "" : " Dentro van \(sdks.count == 1 ? "el SDK de macOS \(sdks[0])" : "\(sdks.count) SDK de macOS (\(Formato.lista(sdks)))"); \((xcode as NSString).deletingPathExtension) trae el suyo."
        var recibos: [String] = []
        for carpeta in ["/Library/Apple/System/Library/Receipts", "/var/db/receipts"] {
            for n in visibles(en: carpeta) where n.hasPrefix("com.apple.pkg.CLTools_") && n.hasSuffix(".plist") {
                let id = String(n.dropLast(6))
                if !recibos.contains(id) { recibos.append(id) }
            }
        }
        let olvidar = recibos.isEmpty ? ""
            : " y, para que Actualización de software no las vuelva a instalar, olvida sus \(recibos.count == 1 ? "recibo" : "\(recibos.count) recibos") (\(Formato.listaCorta(recibos.map { $0.replacingOccurrences(of: "com.apple.pkg.", with: "") }, maximo: 6))): «for p in $(pkgutil --pkgs | grep CLTools); do sudo pkgutil --forget \"$p\"; done»"
        let homebrew = Rutas.homebrew.contains { FileManager.default.isExecutableFile(atPath: $0 + "/bin/brew") }
            ? " Homebrew funciona con las herramientas de Xcode; si algún día te las pide (brew doctor), «xcode-select --install» las vuelve a poner."
            : " Si algo las vuelve a pedir, se reinstalan con «xcode-select --install»."
        return "La terminal usa las herramientas de \(xcode) (xcode-select apunta ahí), así que las Command Line Tools de \(clt) probablemente sobran.\(cuandoSeUsaron)\(conSDK) No las ofrezco para borrar: son del sistema y hace falta tu contraseña de administrador. Si quieres quitarlas, en la Terminal: «sudo rm -rf \(clt)»\(olvidar).\(homebrew)"
    }

    // MARK: - Toolchains de Swift

    /// Los toolchains de Swift descargados aparte de Xcode (de swift.org o con swiftly, de 1 a 3 GB cada uno) que no son el
    /// elegido (el enlace swift-latest.xctoolchain, la variable TOOLCHAINS o el «inUse» de swiftly) ni el más nuevo, y cuyo
    /// compilador no se ha usado en 60 días. Revisar. Los de /Library necesitan tu contraseña: no se ofrecen.
    func toolchainsDeSwift(_ c: Contexto) -> [Elemento] {
        let xctoolchains = Rutas.enHome("Library/Developer/Toolchains").path
        var candidatos: [(ruta: String, version: String, id: String?)] = []
        for n in Self.visibles(en: xctoolchains) where n.hasSuffix(".xctoolchain") && Self.esCarpetaReal(xctoolchains + "/" + n) {
            let info = NSDictionary(contentsOfFile: xctoolchains + "/" + n + "/Info.plist")
            let version = (info?["Version"] as? String) ?? n.replacingOccurrences(of: ".xctoolchain", with: "")
            candidatos.append((xctoolchains + "/" + n, version, info?["CFBundleIdentifier"] as? String))
        }
        for base in [Rutas.enHome(".swiftly/toolchains").path, Rutas.enHome("Library/Application Support/swiftly/toolchains").path] {
            for n in Self.visibles(en: base) where Self.esCarpetaReal(base + "/" + n) { candidatos.append((base + "/" + n, n, nil)) }
        }
        guard candidatos.count >= 2 else { return [] }
        var elegidos = Set<String>()
        if Self.claseDe(xctoolchains + "/swift-latest.xctoolchain") == S_IFLNK {
            elegidos.insert(Rutas.real(URL(fileURLWithPath: xctoolchains + "/swift-latest.xctoolchain")))
        }
        let variable = Rutas.casaDePrueba ? nil : ProcessInfo.processInfo.environment["TOOLCHAINS"]
        var enUso: String?
        for config in [Rutas.enHome(".swiftly/config.json").path, Rutas.enHome("Library/Application Support/swiftly/config.json").path] {
            if let v = (Self.jsonCorto(config) as? [String: Any])?["inUse"] as? String { enUso = v }
        }
        for t in candidatos {
            let nombre = Rutas.nombre(t.ruta)
            if let variable, t.id == variable || nombre.contains(variable) { elegidos.insert(Rutas.real(URL(fileURLWithPath: t.ruta))) }
            if let enUso, nombre.contains(enUso) || t.version.hasPrefix(enUso) { elegidos.insert(Rutas.real(URL(fileURLWithPath: t.ruta))) }
        }
        let masNuevo = candidatos.max { $0.version.compare($1.version, options: .numeric) == .orderedAscending }?.ruta
        let ahora = Int(Date().timeIntervalSince1970)
        var r: [Elemento] = []
        for t in candidatos where t.ruta != masNuevo && !elegidos.contains(Rutas.real(URL(fileURLWithPath: t.ruta))) {
            let compilador = t.ruta + "/usr/bin/swift-frontend"
            let lectura = Self.ultimaLectura(compilador)
            guard lectura > 0, lectura < ahora - 60 * Self.unDia else { continue }
            let url = URL(fileURLWithPath: t.ruta)
            r.append(Elemento(
                nombre: "Toolchain de Swift \(t.version) sin usar",
                detalle: "Un compilador de Swift descargado aparte de Xcode (\(Formato.rutaCorta(t.ruta))). No es el que tienes elegido ni el más nuevo.",
                consecuencia: "Xcode y los demás toolchains no se tocan. Si un proyecto pide esta versión (con un .swift-version o eligiéndola en Xcode › Toolchains), vuelve a descargarla de swift.org o con «swiftly install \(t.version)».",
                rutas: [url], ultimoUso: Self.fecha(lectura), categoria: .desarrollo, riesgo: .revisar,
                motivos: [.info("swift", "Sin usar desde \(Self.cuando(lectura))",
                                "Su compilador (swift-frontend) no se ha usado desde \(Self.cuando(lectura)). Tienes otro más nuevo.")],
                enUso: .rutas(nombre: "Swift \(t.version)", raiz: t.ruta), dueno: "Swift",
                costes: [.descarga(bytes: c.indice.bytes(de: url))]))
        }
        return r
    }

    // MARK: - Instaladores de Xcode

    /// Las versiones de las Xcode instaladas en Aplicaciones (CFBundleShortVersionString, sin los «.0» del final) y sus
    /// compilaciones (ProductBuildVersion). En una casa de prueba, solo las de su Applications.
    static func xcodesInstaladas() -> (versiones: Set<String>, compilaciones: Set<String>) {
        let carpetas = Rutas.casaDePrueba ? [Rutas.enHome("Applications").path] : ["/Applications", Rutas.enHome("Applications").path]
        var versiones = Set<String>()
        var compilaciones = Set<String>()
        for carpeta in carpetas {
            for n in visibles(en: carpeta) where n.hasPrefix("Xcode") && n.hasSuffix(".app") {
                let app = carpeta + "/" + n
                guard (NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleIdentifier"] as? String) == "com.apple.dt.Xcode" else { continue }
                if let v = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleShortVersionString"] as? String { versiones.insert(sinCeros(v)) }
                if let b = NSDictionary(contentsOfFile: app + "/Contents/version.plist")?["ProductBuildVersion"] as? String { compilaciones.insert(b.lowercased()) }
            }
        }
        return (versiones, compilaciones)
    }

    /// «16.2.0» → «16.2»; «16.0» → «16».
    private static func sinCeros(_ v: String) -> String {
        var partes = v.split(separator: ".").map(String.init)
        while partes.count > 1, partes.last == "0" { partes.removeLast() }
        return partes.joined(separator: ".")
    }

    private static let patronXip = try! NSRegularExpression(pattern: #"^xcode[-_ ]?(\d+(?:\.\d+)*)(.*)\.xip$"#, options: .caseInsensitive)

    /// Lo que dice el nombre de un .xip de Xcode: «Xcode-16.2.0+16C5032a.xip» (Xcodes) → («16.2», «16c5032a», false);
    /// «Xcode_16.3_beta_2.xip» → («16.3», nil, true). nil si no es de Xcode.
    static func versionDeXip(_ nombre: String) -> (version: String, compilacion: String?, previa: Bool)? {
        guard let m = patronXip.firstMatch(in: nombre, range: NSRange(nombre.startIndex..., in: nombre)),
              let rv = Range(m.range(at: 1), in: nombre), let rr = Range(m.range(at: 2), in: nombre) else { return nil }
        let resto = nombre[rr].lowercased()
        let compilacion = resto.split(separator: "+").dropFirst().first.map { String($0.prefix { $0.isLetter || $0.isNumber }) }
        let previa = resto.contains("beta") || resto.contains("rc") || resto.contains("release_candidate")
        return (sinCeros(String(nombre[rv])), compilacion, previa)
    }

    /// Si un .xip es de una versión de Xcode que no está instalada (para «Instaladores»: un Xcode anterior guardado para
    /// instalarlo aparte no sobra solo por tener otro más nuevo), esa versión. nil si es de la instalada o no es de Xcode.
    static func xipDeOtraXcode(_ url: URL) -> String? {
        guard let xip = versionDeXip(url.lastPathComponent) else { return nil }
        let (versiones, compilaciones) = xcodesInstaladas()
        if let b = xip.compilacion { return compilaciones.contains(b) ? nil : xip.version }
        // Una beta sin compilación en el nombre no se puede comparar con la instalada.
        return !xip.previa && versiones.contains(xip.version) ? nil : xip.version + (xip.previa ? " (beta)" : "")
    }

    /// Los .xip que guardan Xcodes (la app y el comando xcodes) en su carpeta de ~/Library/Application Support: Seguro si ya
    /// tienes instalada esa misma Xcode (marcado con más de 3 días), Revisar si es otra versión. Las descargas a medias (con
    /// su control de aria2 al lado), para revisar.
    func xipsDeXcodes(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let ahora = Int(Date().timeIntervalSince1970)
        for carpeta in ["com.robotsandpencils.XcodesApp", "com.robotsandpencils.xcodes"].map({ Rutas.enHome("Library/Application Support/" + $0).path }) {
            for n in Self.visibles(en: carpeta) where n.lowercased().hasSuffix(".xip") {
                let ruta = carpeta + "/" + n
                guard Self.claseDe(ruta) == S_IFREG, let xip = Self.versionDeXip(n) else { continue }
                let cambio = Self.cambioDe(ruta)
                let aMedias = Rutas.existe(ruta + ".aria2")
                let otra = Self.xipDeOtraXcode(URL(fileURLWithPath: ruta))
                let instalada = !aMedias && otra == nil
                let motivo: Motivo = aMedias
                    ? .aviso("arrow.down.circle.dotted", "Descarga a medias", "Al lado está el control de la descarga (.aria2): no terminó. Si no la vas a continuar desde Xcodes, sobra.")
                    : instalada ? .bien("checkmark.circle.fill", "Ya está instalada", "Ya tienes instalada Xcode \(xip.version): este instalador ya no hace falta.")
                    : .info("hammer.fill", "Otra versión de Xcode", "Es Xcode \(otra ?? xip.version) y no la tienes instalada: sirve para instalar esa versión aparte. Si no la necesitas, sobra.")
                r.append(Elemento(
                    nombre: n,
                    detalle: "Instalador de Xcode \(xip.version) que descargó Xcodes en \(Formato.rutaCorta(carpeta)).",
                    consecuencia: "Si necesitas volver a instalar esa versión, Xcodes la descarga otra vez (pesa varios GB y pide tu cuenta de Apple).",
                    rutas: [URL(fileURLWithPath: ruta)], ultimoUso: Self.fecha(cambio), categoria: .instaladores,
                    riesgo: instalada ? .seguro : .revisar, seleccionado: instalada && cambio < ahora - 3 * Self.unDia,
                    motivos: [motivo], enUso: .app(nombre: "Xcodes", claves: ["com.robotsandpencils.XcodesApp"]), dueno: "Xcodes"))
            }
        }
        return r
    }
}

extension Procesos {
    /// Si merece la pena preguntar a Xcode por sus simuladores («xcrun simctl»): solo si hay simctl (una Xcode o
    /// CoreSimulator instalados; sin Xcode ni Command Line Tools, xcrun abriría el diálogo para instalarlas) y hay algo que
    /// ver: algún simulador creado o algún sistema para simuladores descargado. Si no hay nada, preguntar solo arrancaría
    /// CoreSimulatorService (que se queda en marcha y escribe en ~/Library/Logs/CoreSimulator) para contestar que no hay
    /// nada.
    static func hayAlgoParaSimctl() -> Bool {
        let fm = FileManager.default
        var desarrollo = ["/Applications/Xcode.app/Contents/Developer"]
        if let d = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] { desarrollo.insert(d, at: 0) }
        if let d = try? fm.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link") { desarrollo.insert(d, at: 0) }
        guard desarrollo.contains(where: { fm.isExecutableFile(atPath: $0 + "/usr/bin/simctl") })
                || fm.fileExists(atPath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework") else { return false }
        func algo(_ carpeta: String, salvo: (String) -> Bool = { _ in false }) -> Bool {
            ((try? fm.contentsOfDirectory(atPath: carpeta)) ?? []).contains { !$0.hasPrefix(".") && !salvo($0) }
        }
        // Simuladores: una carpeta con forma de UUID en Devices.
        let dispositivos = Rutas.enHome("Library/Developer/CoreSimulator/Devices").path
        if ((try? fm.contentsOfDirectory(atPath: dispositivos)) ?? []).contains(where: { $0.count == 36 && UUID(uuidString: $0) != nil }) { return true }
        // Sistemas para simuladores: montados, en imágenes, en cryptex, en el formato antiguo o descargados por MobileAsset.
        let sim = "/Library/Developer/CoreSimulator"
        if algo(sim + "/Volumes") || algo(sim + "/Profiles/Runtimes") || algo(Rutas.enHome("Library/Developer/CoreSimulator/Profiles/Runtimes").path) {
            return true
        }
        // Images tiene siempre Inbox, mnt (vacías si no hay nada) e images.plist (unos 80 bytes sin imágenes).
        if algo(sim + "/Images", salvo: { ["Inbox", "mnt", "images.plist"].contains($0) }) || algo(sim + "/Images/Inbox")
            || algo(sim + "/Images/mnt") { return true }
        var st = stat()
        if lstat(sim + "/Images/images.plist", &st) == 0, st.st_size > 200 { return true }
        for sub in ["Inbox", "bundle", "mnt"] where algo(sim + "/Cryptex/Images/" + sub) { return true }
        let assets = "/System/Library/AssetsV2"
        for n in (try? fm.contentsOfDirectory(atPath: assets)) ?? [] where n.contains("SimulatorRuntime") {
            if ((try? fm.contentsOfDirectory(atPath: assets + "/" + n)) ?? []).contains(where: { $0.hasSuffix(".asset") }) { return true }
        }
        return false
    }
}
