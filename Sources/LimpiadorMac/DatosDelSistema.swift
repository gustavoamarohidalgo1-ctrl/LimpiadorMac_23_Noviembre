import Foundation

// «Datos del sistema»: lo que Ajustes del Sistema › General › Almacenamiento llama así y la app no puede ni debe borrar,
// explicado por partes. Todo se lee sin contraseña y sin escribir nada: los descriptores de los recursos que descarga
// macOS (AssetsV2), los volúmenes del disco (diskutil), los registros, la memoria virtual, los ajustes que deciden qué
// se descarga (CFPreferences) y los restos que dejan los instaladores fuera de tu carpeta. Solo dos botones de
// VistaSistema hacen algo, siempre tras un clic: «Vaciar las miniaturas del Finder» (qlmanage -r cache, como tu usuario)
// y «Medir con contraseña» (un du de solo lectura como administrador, con un comando fijo). Los restos que necesitan
// contraseña solo se explican, con el comando para copiar: la app nunca ejecuta sudo. Cada parte tolera que su ruta, su
// comando o su formato no existan en otro Mac o en otra versión de macOS: entonces no sale.

enum DatosDelSistema {
    // MARK: - Lo que se enseña

    /// A dónde lleva el botón de un recurso o de un resto.
    enum Destino: Sendable, Equatable {
        /// Un panel de Ajustes del Sistema (URL x-apple.systempreferences:…).
        case ajustes(String)
        /// Una app, por su identificador (Xcode).
        case app(String)
    }

    static let ajustesAppleIntelligence = "x-apple.systempreferences:com.apple.Siri-Settings.extension"
    static let ajustesTeclado = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
    static let ajustesIdioma = "x-apple.systempreferences:com.apple.Localization-Settings.extension"
    static let ajustesAccesibilidad = "x-apple.systempreferences:com.apple.Accessibility-Settings.extension"
    static let ajustesExtensiones = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

    /// Recursos que macOS bajó para una función, juntos por el ajuste que los quita.
    struct Recurso: Identifiable, Sendable {
        enum Clase: String, Sendable {
            case appleIntelligence, prediccionXcode, documentacionXcode, dictado, voces, idiomas, funciones,
                 simuladoresXcode, actualizacionMacOS, otros
        }
        var id: Clase
        var titulo: String
        var icono: String
        var bytes: Int64
        /// Lo que libera el ajuste, si no necesitas esa función.
        var liberable: Int64 = 0
        /// Lo que quizá libera (voces e idiomas que parece que no usas, lo que depende de Apple Intelligence…).
        var quiza: Int64 = 0
        var que: String
        var estado: [String] = []
        var detalles: [String] = []
        var ajuste: String?
        var consecuencia: String?
        var destino: Destino?
        var boton: String?
        /// Cómo se midió (macOS no deja leer algunas carpetas: sus descriptores dicen lo que ocupan).
        var medida: String
    }

    struct Volumen: Identifiable, Sendable {
        var id: String          // disk3s1
        var nombre: String      // «Macintosh HD - Data»
        var rol: String         // «Datos», «Sistema»…
        var bytes: Int64
        var cuentaComo: String
        var nota: String?
    }

    struct Rosetta: Sendable {
        /// Lo que ocupa su cryptex en el arranque (Preboot), si se puede leer.
        var bytes: Int64?
        /// Las apps que solo funcionan en Intel (las que la necesitan).
        var appsIntel: [String]
    }

    struct Registros: Sendable {
        var bytes: Int64
        /// El registro más antiguo que queda (lo que macOS aún guarda).
        var masAntiguo: Date?
        /// Cuántas horas cubre «Persist» (los registros normales): si son pocas, algo escribe demasiado.
        var horasPersist: Double?
    }

    /// Algo de fuera de tu carpeta que solo se quita con contraseña (o con un ajuste): se explica, nunca se ejecuta.
    struct Resto: Identifiable, Sendable {
        var id: String
        var titulo: String
        var detalle: String
        var bytes: Int64?
        /// Lo que se puede copiar a la Terminal (una orden por línea; las que empiezan por «#» son explicaciones).
        var comando: String?
        var destino: Destino?
        /// Está funcionando ahora (un servicio sin app que arranca con el Mac, por ejemplo).
        var enMarcha = false
    }

    /// Una carpeta que la app no puede leer y que cuenta en lo que «solo ve root».
    struct Oculto: Identifiable, Sendable {
        var id: String { ruta }
        var ruta: String
        var que: String
        /// La protege macOS (SIP): ni con contraseña se puede leer. Si no, un administrador la mide con «Medir con contraseña».
        var protegida: Bool
    }

    struct MedidaRoot: Identifiable, Sendable {
        var id: String { ruta }
        var ruta: String
        var bytes: Int64
    }

    struct Informe: Sendable {
        var recursos: [Recurso] = []
        /// Todo AssetsV2: lo legible con du (sin contar dos veces lo injertado) más lo ilegible medido por descriptores.
        var recursosTotal: Int64 = 0
        /// Lo que macOS no deja leer, medido por sus descriptores: se resta de lo que «solo ve root».
        var recursosIlegibles: Int64 = 0
        /// Versiones anteriores de un mismo recurso que siguen en el disco: macOS las recoge solo.
        var pendientesDeRecoger: Int64 = 0
        var volumenes: [Volumen] = []
        var rosetta: Rosetta?
        var registros: Registros?
        /// Se pudieron leer las carpetas de registros (hace falta ser administrador).
        var registrosMedibles = true
        var sleepimage: Int64?
        var hibernacion: Int?
        var swap: Int64 = 0
        var purgable: Int64 = 0
        var usadoDatos: Int64 = 0
        /// Lo que midió la app (índice y fuera de tu carpeta) y la Papelera; nil si no hay análisis.
        var visto: Int64?
        var papelera: Int64 = 0
        /// Usado del volumen de datos − lo visto − lo medido por descriptores − las cuentas borradas; nil si no se sabe.
        var soloRoot: Int64?
        /// Las carpetas de otras cuentas de este Mac (/Users/<otra>, y «Deleted Users» si no se pudo medir): ni el índice
        /// ni MedidaFuera las miran y no se pueden leer, así que caen en lo que solo ve root. No son de macOS.
        var otrasCuentas: [String] = []
        /// Lo que ocupa /Users/Deleted Users (cuentas que se borraron guardando su carpeta en una imagen), si se pudo medir:
        /// no es de macOS, así que no cuenta en lo que solo ve root ni en el total.
        var cuentasBorradas: Int64?
        var ocultos: [Oculto] = []
        var restos: [Resto] = []
        /// Existe la caché de miniaturas de Quick Look de tu usuario, y lo que ocupa si se sabe.
        var hayMiniaturas = false
        var miniaturas: Int64?
        var accesoTotal = true
        var fecha = Date()
        var duracion: TimeInterval = 0

        /// Lo que se libera con ajustes de macOS y de Xcode, si no necesitas esas funciones.
        var conAjustes: Int64 { recursos.reduce(0) { $0 + $1.liberable } }
        var quizaConAjustes: Int64 { recursos.reduce(0) { $0 + $1.quiza } }
        /// Lo reconocido como «Datos del sistema»: sin solaparse (lo de root no incluye lo medido por descriptores, y los
        /// registros y la imagen de hibernación están en lo visto).
        var total: Int64 { recursosTotal + (registros?.bytes ?? 0) + (sleepimage ?? 0) + swap + (soloRoot ?? 0) }
    }

    /// Lo más pequeño que se enseña como recurso.
    static let minimo: Int64 = 50_000_000

    // MARK: - Casa de prueba

    /// Solo en modo diagnóstico con una casa de prueba: LIMPIADOR_SISTEMA es una carpeta que hace de «/» para todo lo de
    /// aquí (AssetsV2, /Library, /private/var…), con las salidas de los comandos en «salidas/» y las preferencias en
    /// «Preferencias/<dominio>.plist». Sin ella, en una casa de prueba no se mira nada del sistema.
    static let raizDePrueba: String? = {
        guard Rutas.casaDePrueba, let valor = ProcessInfo.processInfo.environment["LIMPIADOR_SISTEMA"],
              let real = realpath(valor, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }()

    /// Se puede calcular: en el Mac de verdad o en una casa de prueba con su sistema de prueba.
    static var aplica: Bool { !Rutas.casaDePrueba || raizDePrueba != nil }

    /// Se mira el sistema de verdad (no el de prueba): solo entonces se usan diskutil, mdfind, sysctl y los procesos.
    static var deVerdad: Bool { raizDePrueba == nil && !Rutas.casaDePrueba }

    /// Una ruta del sistema: la de verdad o la de la casa de prueba.
    static func ruta(_ p: String) -> String { (raizDePrueba ?? "") + p }

    /// Una preferencia de otro dominio (com.apple.dt.Xcode…), como la lee macOS (cfprefsd), sin cambiar nada. En una casa
    /// de prueba, de Preferencias/<dominio>.plist.
    static func preferencia(_ clave: String, de dominio: String) -> Any? {
        if let raiz = raizDePrueba {
            return NSDictionary(contentsOfFile: raiz + "/Preferencias/\(dominio).plist")?[clave]
        }
        if dominio == "NSGlobalDomain" {
            return CFPreferencesCopyValue(clave as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        _ = CFPreferencesAppSynchronize(dominio as CFString)
        return CFPreferencesCopyAppValue(clave as CFString, dominio as CFString)
    }

    /// Todo un dominio de preferencias como texto, para buscar un nombre en él (las voces elegidas, por ejemplo).
    static func dominioComoTexto(_ dominio: String) -> String {
        if let raiz = raizDePrueba {
            return NSDictionary(contentsOfFile: raiz + "/Preferencias/\(dominio).plist").map { String(describing: $0) } ?? ""
        }
        let d = CFPreferencesCopyMultiple(nil, dominio as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return String(describing: d as NSDictionary)
    }

    static func numero(_ v: Any?) -> Bool? { (v as? NSNumber)?.boolValue }

    /// La salida de un comando de solo lectura; en una casa de prueba, el archivo salidas/<nombre> (o nada).
    static func salida(_ programa: String, _ argumentos: [String], prueba nombre: String, limite: TimeInterval = 15) -> String? {
        if let raiz = raizDePrueba { return try? String(contentsOfFile: raiz + "/salidas/" + nombre, encoding: .utf8) }
        guard deVerdad else { return nil }
        let r = Shell.ejecutar(programa, argumentos, limite: limite, prioridad: .utility)
        return r.estado == 0 ? r.salida : nil
    }

    // MARK: - Medir

    /// Calcula todo (unos segundos, en segundo plano). `visto` es lo que midió el análisis (índice + fuera de tu carpeta,
    /// con `MedidaFuera` ya corregida); sin él no se calcula lo que solo ve root. `appsExtra`: las apps que encontró el
    /// análisis fuera de Aplicaciones (como en Escaner), para no decir «sin app» de un servicio cuya app sigue ahí.
    static func medir(visto: Int64?, papelera: Int64, appsExtra: [String] = []) -> Informe {
        let inicio = Date()
        var i = Informe()
        guard aplica else { return i }
        i.accesoTotal = Seguridad.tieneAccesoTotal()
        let apps = AppsInstaladas.cargar(appsExtra: appsExtra)
        let programas = deVerdad ? programasEnMarcha() : []
        let xcodes = Self.xcodes()

        // Recursos de AssetsV2: los descriptores dicen lo que ocupa cada uno, aunque su carpeta no se pueda leer.
        let assets = ruta("/System/Library/AssetsV2")
        let descriptores = leerDescriptores(assets + "/persisted/AutoAssetDescriptors").filter(\.enDisco)
        var legibles: [String: Bool] = [:]
        var enDisco: [Descriptor] = []
        for d in descriptores {
            let carpeta = assets + "/" + d.tipo.replacingOccurrences(of: ".", with: "_")
            var st = stat()
            // Sin su carpeta no está en el disco (o en otro sitio que no sé medir): no se cuenta.
            guard lstat(carpeta, &st) == 0 else { continue }
            if legibles[carpeta] == nil { legibles[carpeta] = sePuedeLeer(carpeta) }
            if legibles[carpeta] == false { i.recursosIlegibles += d.bytes }
            enDisco.append(d)
        }
        i.pendientesDeRecoger = versionesAnteriores(enDisco).reduce(0) { $0 + $1.bytes }
        let legible = Rutas.existe(assets) ? MedidaFuera.recursos(assets) ?? 0 : 0
        i.recursosTotal = legible + i.recursosIlegibles
        i.recursos = recursos(enDisco, assets: assets, xcodes: xcodes, total: i.recursosTotal)

        i.volumenes = volumenes()
        i.rosetta = rosetta()
        (i.registros, i.registrosMedibles) = registros()
        var st = stat()
        if lstat(ruta("/private/var/vm/sleepimage"), &st) == 0 { i.sleepimage = Int64(st.st_blocks) * 512 }
        // La memoria de intercambio: lo que ocupan sus archivos (sysctl vm.swapusage) o, si no contesta, su volumen (VM).
        i.swap = (deVerdad ? swapEnDisco() : nil) ?? i.volumenes.first { $0.rol == "Memoria virtual" }?.bytes ?? 0
        if deVerdad {
            i.hibernacion = salida("/usr/bin/pmset", ["-g"], prueba: "", limite: 5).flatMap(Self.hibernacion)
            let d = InfoDisco.actual()
            i.purgable = d.purgable
            i.usadoDatos = d.usadoDatos
        }
        i.visto = visto
        i.papelera = papelera
        // Las otras cuentas de este Mac: ni el índice ni MedidaFuera las miran, así que caen en lo que solo ve root. Sus
        // carpetas no se pueden leer (ni con Acceso total), pero sí se ve que existen. «Deleted Users» guarda las cuentas
        // borradas en imágenes: si se puede medir, va aparte (no es de macOS).
        let usuarios = ruta("/Users")
        for n in nombres(en: usuarios).sorted() where !n.hasPrefix(".") && n != "Shared" {
            let p = usuarios + "/" + n
            guard lstat(p, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, n != NSUserName(), p != NSHomeDirectory() else { continue }
            if n == "Deleted Users" {
                // Si no se puede medir, cuenta como las demás (en lo que solo ve root); si está vacía, no sale.
                let b = MedidaFuera.du(p, limite: 30)
                if let b, b > 0 { i.cuentasBorradas = b } else if b == nil { i.otrasCuentas.append(n) }
            } else {
                i.otrasCuentas.append(n)
            }
        }
        // Sin Acceso total, lo que no se ve incluye tus datos protegidos (Fotos, Mail, contenedores): no es «de root».
        if let visto, deVerdad, i.accesoTotal, i.usadoDatos > 0 {
            i.soloRoot = max(0, i.usadoDatos - visto - papelera - i.recursosIlegibles - (i.cuentasBorradas ?? 0))
        }
        i.ocultos = ocultos(accesoTotal: i.accesoTotal)
        i.restos = servicios(apps: apps, programas: programas) + extensiones(apps: apps) + recibos()
            + clonesDeAutoUpdate(programas: programas) + cacheDeSimbolos() + capturasDeRed() + imagenesDeDesarrollo()
        if let c = Rutas.temporalesDelSistema.first(where: { $0.hasSuffix("/C") }) {
            i.hayMiniaturas = nombres(en: c).contains("com.apple.quicklook.ThumbnailsAgent")
            if i.hayMiniaturas && deVerdad { i.miniaturas = miniaturasAbiertas() }
        }
        i.duracion = Date().timeIntervalSince(inicio)
        return i
    }

    /// Los nombres de lo que hay en una carpeta, con readdir: basta con poder leerla (FileManager pide además poder
    /// entrar, y /Library/Caches/com.microsoft.autoupdate.helper, por ejemplo, deja leer pero no entrar).
    static func nombres(en carpeta: String) -> [String] {
        guard let d = opendir(carpeta) else { return [] }
        defer { closedir(d) }
        var r: [String] = []
        while let e = readdir(d) {
            var n = e.pointee.d_name
            let nombre = withUnsafePointer(to: &n) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
            if nombre != "." && nombre != ".." { r.append(nombre) }
        }
        return r
    }

    /// Se puede abrir la carpeta (si no, du no la cuenta).
    static func sePuedeLeer(_ carpeta: String) -> Bool {
        guard let d = opendir(carpeta) else { return false }
        closedir(d)
        return true
    }

    // MARK: - Descriptores de AssetsV2

    struct Descriptor: Sendable {
        let tipo: String            // com.apple.MobileAsset.UAF.FM.CodeLM
        let especificador: String   // com.apple.fm.code.generate_small_v2.base
        let version: String
        let bytes: Int64
        let enDisco: Bool
        /// La versión de macOS con la que se bajó («26.6.2»), si lo dice.
        let bajadoCon: String?
    }

    /// Los descriptores de los recursos automáticos (archivos .state, de root pero legibles por todos). Cada uno es un
    /// plist que lleva dentro otro (NSKeyedArchiver) con lo que ocupa el recurso (downloadedFilesystemBytes) y si está en
    /// el disco (isOnFilesystem). Los que no se entienden se saltan.
    static func leerDescriptores(_ carpeta: String) -> [Descriptor] {
        var r: [Descriptor] = []
        for n in (try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? []
        where n.hasPrefix("AutoAssetDescriptors_Entry_") && n.hasSuffix(".state") {
            let p = carpeta + "/" + n
            var st = stat()
            guard lstat(p, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size < 4_000_000,
                  let datos = FileManager.default.contents(atPath: p), let d = descriptor(datos, nombre: n) else { continue }
            r.append(d)
        }
        return r
    }

    static func descriptor(_ datos: Data, nombre: String) -> Descriptor? {
        guard let externo = try? PropertyListSerialization.propertyList(from: datos, format: nil) as? [String: Any],
              let campos = externo["SUCorePersistedStatePolicySecureCodedObjectsFields"] as? [String: Any],
              let interno = campos["assetDescriptor"] as? Data,
              let archivo = try? PropertyListSerialization.propertyList(from: interno, format: nil) as? [String: Any],
              let objetos = archivo["$objects"] as? [Any],
              let raiz = objetos.lazy.compactMap({ $0 as? [String: Any] }).first(where: { $0["downloadedFilesystemBytes"] != nil }),
              let bytes = (raiz["downloadedFilesystemBytes"] as? NSNumber)?.int64Value, bytes >= 0 else { return nil }
        let tipo = texto(raiz["assetType"], en: objetos)
        guard let partes = partes(de: nombre, tipo: tipo) else { return nil }
        return Descriptor(tipo: tipo ?? partes.tipo,
                          especificador: texto(raiz["AssetSpecifier"], en: objetos) ?? partes.especificador,
                          version: partes.version, bytes: bytes,
                          enDisco: (raiz["isOnFilesystem"] as? NSNumber)?.boolValue ?? false,
                          bajadoCon: texto(raiz["stagedFromOSVersion"], en: objetos))
    }

    /// Un texto de un archivo de NSKeyedArchiver: el valor si ya es texto o, si es una referencia (CFKeyedArchiverUID, que
    /// PropertyListSerialization deja sin resolver), el objeto al que apunta. La referencia solo deja ver su número en su
    /// descripción («<CFKeyedArchiverUID 0x…>{value = 4}»).
    static func texto(_ v: Any?, en objetos: [Any]) -> String? {
        if let s = v as? String { return s }
        guard let v else { return nil }
        let d = String(describing: v)
        guard d.contains("CFKeyedArchiverUID"), let r = d.range(of: "value = "),
              let n = Int(d[r.upperBound...].prefix { $0.isNumber }), n > 0, n < objetos.count else { return nil }
        return objetos[n] as? String
    }

    /// «AutoAssetDescriptors_Entry_<tipo>_<especificador>_<versión>_0.state» → sus partes. El tipo no lleva «_» y el
    /// especificador puede llevarlo («…asr.assistant.es_MX»); con el tipo del propio descriptor se corta mejor.
    static func partes(de nombre: String, tipo conocido: String?) -> (tipo: String, especificador: String, version: String)? {
        var s = Substring(nombre.dropFirst("AutoAssetDescriptors_Entry_".count).dropLast(".state".count))
        if let u = s.lastIndex(of: "_"), !s[s.index(after: u)...].isEmpty, s[s.index(after: u)...].allSatisfy(\.isNumber) {
            s = s[..<u]
        }
        guard let u = s.lastIndex(of: "_") else { return nil }
        let version = String(s[s.index(after: u)...])
        let resto = s[..<u]
        if let t = conocido, resto.hasPrefix(t + "_") { return (t, String(resto.dropFirst(t.count + 1)), version) }
        guard let p = resto.firstIndex(of: "_") else { return nil }
        return (String(resto[..<p]), String(resto[resto.index(after: p)...]), version)
    }

    /// De cada recurso con varias versiones en el disco, todas menos la más nueva: macOS las recoge cuando le hace falta
    /// espacio (o cuando nada las bloquea).
    static func versionesAnteriores(_ ds: [Descriptor]) -> [Descriptor] {
        Dictionary(grouping: ds) { $0.tipo + "|" + $0.especificador }.values.flatMap { grupo -> [Descriptor] in
            guard grupo.count > 1 else { return [] }
            let orden = grupo.sorted { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
            return Array(orden.dropLast())
        }
    }

    static func clase(de tipo: String) -> Recurso.Clase {
        let t = tipo.hasPrefix("com.apple.MobileAsset.") ? String(tipo.dropFirst("com.apple.MobileAsset.".count)) : tipo
        if t == "UAF.FM.CodeLM" { return .prediccionXcode }
        if t.hasPrefix("UAF.FM.") || t.hasPrefix("UAF.IF.") { return .appleIntelligence }
        if t.hasPrefix("UAF.Siri.Understanding") { return .dictado }
        if t == "UAF.Siri.TextToSpeech" { return .voces }
        if t == "UAF.LinguisticData" { return .idiomas }
        if ["UAF.Photos.", "UAF.Shortcuts.", "UAF.SearchQueryUnderstanding", "UAF.Translation.", "UAF.SummarizationKit",
            "UAF.TKModel"].contains(where: { t.hasPrefix($0) }) { return .funciones }
        return .otros
    }

    // MARK: - Recursos por función

    static func recursos(_ ds: [Descriptor], assets: String, xcodes: [(ruta: String, version: String)], total: Int64) -> [Recurso] {
        let porClase = Dictionary(grouping: ds) { clase(de: $0.tipo) }
        var r: [Recurso] = []
        if let x = appleIntelligence(porClase[.appleIntelligence] ?? []) { r.append(x) }
        if let x = prediccionXcode(porClase[.prediccionXcode] ?? [], xcodes: xcodes) { r.append(x) }
        if let x = documentacionXcode(assets: assets, xcodes: xcodes) { r.append(x) }
        if let x = dictado(porClase[.dictado] ?? []) { r.append(x) }
        if let x = voces(porClase[.voces] ?? []) { r.append(x) }
        if let x = idiomasExtra(porClase[.idiomas] ?? []) { r.append(x) }
        if let x = funciones(porClase[.funciones] ?? []) { r.append(x) }
        if let x = simuladoresXcode(assets: assets, xcodes: xcodes) { r.append(x) }
        if let x = actualizacionMacOS(assets: assets) { r.append(x) }
        r.sort { ($0.liberable + $0.quiza, $0.bytes) > ($1.liberable + $1.quiza, $1.bytes) }
        // Lo demás de AssetsV2: diccionarios, voces de accesibilidad, ContextKit, certificados… (de macOS).
        let otros = total - r.reduce(0) { $0 + $1.bytes }
        if otros >= minimo {
            r.append(Recurso(id: .otros, titulo: "Otros recursos de macOS", icono: "shippingbox", bytes: otros,
                             que: "Diccionarios, voces de accesibilidad, certificados, sugerencias, tipos de letra y demás recursos que macOS baja y usa.",
                             estado: ["Son de macOS: los baja y los quita él."], medida: "con du"))
        }
        return r
    }

    /// Los «.asset» de unas carpetas de AssetsV2, medidos como en el total (`MedidaFuera.recursos`: sin contar dos veces
    /// lo injertado), con las propiedades de su Info.plist. Los enlaces no se siguen.
    static func assetsMedidos(_ carpetas: [String]) -> [(bytes: Int64, props: [String: Any])] {
        carpetas.flatMap { carpeta in
            ((try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? []).sorted().compactMap { n -> (bytes: Int64, props: [String: Any])? in
                guard n.hasSuffix(".asset") else { return nil }
                let p = carpeta + "/" + n
                var st = stat()
                guard lstat(p, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, let bytes = MedidaFuera.recursos(p) else { return nil }
                return (bytes, NSDictionary(contentsOfFile: p + "/Info.plist")?["MobileAssetProperties"] as? [String: Any] ?? [:])
            }
        }
    }

    /// Los sistemas iOS para los simuladores que Xcode baja como recursos de macOS (iOSSimulatorRuntime): varios GB cada
    /// uno, y macOS no los borra nunca solo. Se quitan desde Xcode (o en Emuladores, con simctl); solo «quizá», porque
    /// quizá los usan tus simuladores (eso lo sabe Escaner, con simctl).
    static func simuladoresXcode(assets: String, xcodes: [(ruta: String, version: String)]) -> Recurso? {
        let lista = assetsMedidos([assets + "/com_apple_MobileAsset_iOSSimulatorRuntime"])
        let bytes = lista.reduce(0) { $0 + $1.bytes }
        guard bytes >= minimo else { return nil }
        var x = Recurso(id: .simuladoresXcode, titulo: "Sistemas iOS para simuladores", icono: "iphone", bytes: bytes, quiza: bytes,
                        que: "Los sistemas iOS que Xcode baja para sus simuladores. Ajustes los cuenta en «Datos del sistema».",
                        detalles: lista.map { a in
                            let version = a.props["SimulatorVersion"] as? String
                            let build = a.props["Build"] as? String
                            return "iOS \(version ?? "?")\(build.map { " (\($0))" } ?? ""): \(Formato.bytes(a.bytes))"
                        },
                        ajuste: "Xcode › Ajustes › Components › borra el sistema iOS que no uses (o en la categoría Emuladores de esta app).",
                        consecuencia: "Los simuladores de esa versión de iOS dejan de funcionar hasta que la vuelvas a bajar desde Xcode.",
                        medida: "con du")
        if lista.contains(where: { $0.props["__AssetDefaultGarbageCollectionBehavior"] as? String == "NeverCollected" }) {
            x.estado.append("macOS no los borra solo: se quedan hasta que los quites.")
        }
        if xcodes.isEmpty {
            x.estado.append("No tienes Xcode instalado: sin Xcode no hay ajuste que los quite.")
        } else {
            x.destino = .app("com.apple.dt.Xcode")
            x.boton = "Abrir Xcode"
        }
        return x
    }

    /// Una actualización de macOS bajada (o a medias) que espera a instalarse: no se quita a mano.
    static func actualizacionMacOS(assets: String) -> Recurso? {
        let lista = assetsMedidos([assets + "/com_apple_MobileAsset_MacSoftwareUpdate", assets + "/com_apple_MobileAsset_MacSplatSoftwareUpdate"])
        let bytes = lista.reduce(0) { $0 + $1.bytes }
        guard bytes >= minimo else { return nil }
        return Recurso(id: .actualizacionMacOS, titulo: "Actualización de macOS descargada", icono: "arrow.down.circle", bytes: bytes,
                       que: "Una actualización de macOS que se bajó (o se está bajando) y espera a instalarse.",
                       estado: ["macOS la quita al instalarla o cuando deja de servir. Para verla o instalarla: Ajustes del Sistema › General › Actualización de software."],
                       medida: "con du")
    }

    static func suma(_ ds: [Descriptor]) -> Int64 { ds.reduce(0) { $0 + $1.bytes } }

    /// Apple Intelligence: los modelos de lenguaje y de imagen (UAF.FM.*, salvo los de Xcode) y sus listas de seguridad.
    static func appleIntelligence(_ ds: [Descriptor]) -> Recurso? {
        let bytes = suma(ds)
        guard bytes >= minimo else { return nil }
        let dominio = "com.apple.gms.availability"
        let disponible = numero(preferencia("com.apple.gms.availability.wasAvailable", de: dominio))
        let razones = preferencia("com.apple.gms.availability.reasons", de: dominio) as? [Any]
        let activa = disponible == true && (razones?.isEmpty ?? true)
        var x = Recurso(id: .appleIntelligence, titulo: "Modelos de Apple Intelligence", icono: "apple.intelligence", bytes: bytes,
                        que: "Los modelos que Apple Intelligence usa en tu Mac: el de lenguaje, el de imagen, sus adaptadores (resúmenes, Mail, Mensajes, Image Playground…) y sus listas de seguridad.",
                        ajuste: "Ajustes del Sistema › Apple Intelligence y Siri › desactiva Apple Intelligence.",
                        consecuencia: "Dejas de tener las herramientas de escritura, los resúmenes, Image Playground y lo demás de Apple Intelligence. macOS deja de bloquear los modelos y los borra (enseguida o cuando le hace falta espacio). Si la vuelves a activar, los baja otra vez (unos \(Formato.bytes(bytes))).",
                        destino: .ajustes(ajustesAppleIntelligence), boton: "Abrir Apple Intelligence y Siri",
                        medida: "por sus descriptores: macOS no deja leer su carpeta, ni con contraseña")
        switch disponible {
        case true? where activa:
            x.estado.append("Apple Intelligence está activada: macOS mantiene estos modelos y no los borra aunque falte espacio.")
            x.liberable = bytes
        case true?:
            x.estado.append("Apple Intelligence está activada, pero macOS dice que ahora no está disponible: los modelos siguen bloqueados.")
            x.liberable = bytes
        case false?:
            x.estado.append("Apple Intelligence no está activa en este Mac: macOS ya no necesita estos modelos y los borrará solo cuando le haga falta espacio.")
        case nil:
            x.estado.append("No pude saber si Apple Intelligence está activada.")
            x.quiza = bytes
        }
        let viejas = versionesAnteriores(ds)
        let actuales = ds.filter { d in !viejas.contains { $0.especificador == d.especificador && $0.version == d.version } }
        x.detalles.append("\(actuales.count) \(actuales.count == 1 ? "modelo" : "modelos y adaptadores"); \(Formato.listaCorta(actuales.sorted { $0.bytes > $1.bytes }.prefix(3).map { "\(nombreCorto($0.especificador)) (\(Formato.bytes($0.bytes)))" }, maximo: 3)).")
        if !viejas.isEmpty {
            x.detalles.append("\(viejas.count) \(viejas.count == 1 ? "es una versión anterior" : "son versiones anteriores") (\(Formato.bytes(suma(viejas)))) que macOS recogerá solo.")
        }
        return x
    }

    /// «com.apple.fm.language.instruct_3b.base.generic» → «instruct_3b.base».
    static func nombreCorto(_ especificador: String) -> String {
        var partes = especificador.split(separator: ".").map(String.init)
        while let p = partes.first, ["com", "apple", "fm", "language", "visual", "code", "gm", "siri"].contains(p) { partes.removeFirst() }
        if partes.last == "generic" { partes.removeLast() }
        return partes.isEmpty ? especificador : partes.joined(separator: ".")
    }

    /// Las Xcode instaladas (ruta y versión): en Aplicaciones y, en el Mac de verdad, donde las encuentre Spotlight.
    static func xcodes() -> [(ruta: String, version: String)] {
        var candidatas = Set<String>()
        for carpeta in [ruta("/Applications"), Rutas.enHome("Applications").path] {
            for n in (try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? [] where n.hasPrefix("Xcode") && n.hasSuffix(".app") {
                candidatas.insert(carpeta + "/" + n)
            }
        }
        if deVerdad, let s = salida("/usr/bin/mdfind", ["kMDItemCFBundleIdentifier == \"com.apple.dt.Xcode\""], prueba: "", limite: 5) {
            for l in s.split(separator: "\n") where l.hasPrefix("/") && !l.contains("/.Trash/") { candidatas.insert(String(l)) }
        }
        return candidatas.sorted().compactMap { app in
            guard let info = NSDictionary(contentsOfFile: app + "/Contents/Info.plist"),
                  info["CFBundleIdentifier"] as? String == "com.apple.dt.Xcode" else { return nil }
            return (app, info["CFBundleShortVersionString"] as? String ?? "?")
        }
    }

    /// El modelo de finalización predictiva de Xcode (UAF.FM.CodeLM): pesa como dos apps y suele haber dos generaciones.
    static func prediccionXcode(_ ds: [Descriptor], xcodes: [(ruta: String, version: String)]) -> Recurso? {
        let bytes = suma(ds)
        guard bytes >= minimo else { return nil }
        var x = Recurso(id: .prediccionXcode, titulo: "Modelo de finalización predictiva de Xcode", icono: "hammer", bytes: bytes,
                        que: "Los modelos de lenguaje de código que Xcode baja para sugerirte código mientras escribes. Ajustes los cuenta en «Datos del sistema», no en «Desarrollador».",
                        ajuste: "Xcode › Ajustes › Components › «Predictive Code Completion Model» › borrar. O desactiva «Predictive code completion» en Xcode › Ajustes › Text Editing › Editing: macOS lo quita cuando ningún programa lo pide.",
                        consecuencia: "Xcode deja de sugerirte código con el modelo del Mac. Si lo quieres otra vez, se vuelve a bajar desde Xcode › Ajustes › Components (unos \(Formato.bytes(bytes))).",
                        medida: "por sus descriptores: macOS no deja leer su carpeta, ni con contraseña")
        if xcodes.isEmpty {
            x.estado.append("No tienes Xcode instalado: el modelo se quedó sin nadie que lo use. Sin Xcode no hay ajuste que lo quite; macOS lo recoge cuando nada lo pide.")
            x.quiza = bytes
        } else {
            x.estado.append("Tienes Xcode \(Formato.lista(xcodes.map { $0.version })) instalado.")
            x.liberable = bytes
            x.destino = .app("com.apple.dt.Xcode")
            x.boton = "Abrir Xcode"
            let dominio = "com.apple.dt.Xcode"
            if numero(preferencia("DVTTextEnablePredictiveCompletion", de: dominio)) == false {
                x.estado.append("Tienes apagada la finalización predictiva en Xcode: el modelo está bajado pero no se usa.")
            } else if numero(preferencia("DVTEnableOnDeviceCodePredictions", de: dominio)) == false {
                x.estado.append("Xcode tiene apagadas las predicciones en el Mac (su ajuste DVTEnableOnDeviceCodePredictions): parece que el modelo está bajado pero no se usa.")
            }
        }
        // Las generaciones del modelo base («generate_small_v2.base», «…_v3.base»).
        let bases = ds.filter { $0.especificador.contains("generate_small_v") && $0.especificador.hasSuffix(".base") }
            .sorted { $0.especificador.compare($1.especificador, options: .numeric) == .orderedAscending }
        if bases.count > 1 {
            let lista = bases.map { b -> String in
                let v = b.especificador.components(separatedBy: "generate_small_").last?.components(separatedBy: ".").first ?? "?"
                return "\(v) (\(Formato.bytes(b.bytes))\(b.bajadoCon.map { ", bajada con macOS \($0)" } ?? ""))"
            }
            x.estado.append("Hay \(bases.count) generaciones del modelo: \(Formato.lista(lista)).")
        }
        return x
    }

    /// La documentación de Xcode descargada: «Precious», macOS no la borra nunca sola.
    static func documentacionXcode(assets: String, xcodes: [(ruta: String, version: String)]) -> Recurso? {
        let carpeta = assets + "/com_apple_MobileAsset_AppleDeveloperDocumentation"
        var docs: [(version: String, bytes: Int64, precious: Bool)] = []
        for n in (try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? [] where n.hasSuffix(".asset") {
            let p = carpeta + "/" + n
            var st = stat()
            guard lstat(p, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, let bytes = MedidaFuera.du(p, ignorar: [".AssetData"], limite: 60) else { continue }
            let props = NSDictionary(contentsOfFile: p + "/Info.plist")?["MobileAssetProperties"] as? [String: Any]
            docs.append((props?["XcodeVersion"] as? String ?? "?", bytes,
                         props?["__AssetDefaultGarbageCollectionBehavior"] as? String == "Precious"))
        }
        let bytes = docs.reduce(0) { $0 + $1.bytes }
        guard bytes >= minimo else { return nil }
        docs.sort { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
        var x = Recurso(id: .documentacionXcode, titulo: "Documentación de Xcode descargada", icono: "book", bytes: bytes,
                        que: "La documentación de Apple para consultarla sin conexión en Xcode (y la base que usa su asistente para buscar en ella).",
                        detalles: docs.map { "Documentación de Xcode \($0.version): \(Formato.bytes($0.bytes))" },
                        ajuste: "Xcode › Ajustes › Components › Documentation › borrar.",
                        consecuencia: "Si abres la documentación en Xcode, la vuelve a bajar.", medida: "con du")
        if docs.contains(where: { $0.precious }) {
            x.estado.append("Es «Precious»: macOS no la borra nunca solo, aunque le falte espacio.")
        }
        if xcodes.isEmpty {
            x.estado.append("No tienes Xcode instalado: la documentación se quedó huérfana y solo se quita desde Xcode.")
            x.quiza = bytes
        } else {
            x.liberable = bytes
            x.destino = .app("com.apple.dt.Xcode")
            x.boton = "Abrir Xcode"
            if docs.count > 1, let nueva = docs.last {
                x.estado.append("Hay \(docs.count) versiones: con Xcode \(Formato.lista(xcodes.map { $0.version })), sobran las anteriores a la \(nueva.version).")
            }
        }
        return x
    }

    // MARK: Idiomas

    /// «es-PE» → «es_PE».
    static func normal(_ s: String) -> String { s.replacingOccurrences(of: "-", with: "_") }
    /// «es_PE» → «es».
    static func base(_ s: String) -> String { String(normal(s).split(separator: "_").first ?? "") }

    /// El nombre de un idioma en español: «en_US» → «inglés (Estados Unidos)».
    static func nombreIdioma(_ id: String) -> String {
        Locale(identifier: "es").localizedString(forIdentifier: id) ?? id
    }

    /// El primer trozo de un especificador que es un idioma con región («…asr.assistant.en_US» → «en_US»).
    static func localeEn(_ especificador: String) -> String? {
        especificador.split(separator: ".").map(String.init).first { p in
            let partes = p.split(separator: "_")
            guard partes.count >= 2, let l = partes.first, (2...3).contains(l.count), l.allSatisfy({ $0.isLowercase && $0.isASCII }) else { return false }
            return partes.dropFirst().allSatisfy { $0.count >= 2 && $0.count <= 4 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }
        }
    }

    /// Los idiomas de tu Mac (General › Idioma y región), normalizados («es_PE»).
    static func idiomasDelSistema() -> [String] {
        ((preferencia("AppleLanguages", de: "NSGlobalDomain") as? [String]) ?? []).map(normal)
    }

    /// Dictado sin conexión y reconocimiento de Siri, por idioma (UAF.Siri.Understanding): cada idioma pesa medio GB.
    static func dictado(_ ds: [Descriptor]) -> Recurso? {
        let bytes = suma(ds)
        guard bytes >= minimo else { return nil }
        var porIdioma: [String: Int64] = [:]
        for d in ds { if let l = localeEn(d.especificador) { porIdioma[l, default: 0] += d.bytes } }
        let soporte = "com.apple.assistant.support"
        let dictadoActivo = numero(preferencia("Dictation Enabled", de: soporte)) ?? true
        let siriActiva = numero(preferencia("Assistant Enabled", de: soporte)) ?? false
        let sesion = (preferencia("Session Language", de: "com.apple.assistant.backedup") as? String).map(normal)
        let estados = (preferencia("Offline Dictation Status", de: soporte) as? [String: Any]) ?? [:]
        let instalados = estados.compactMap { k, v in numero((v as? [String: Any])?["Installed"]) == true ? normal(k) : nil }.sorted()
        let preferidos = ((preferencia("DictationIMPreferredLanguageIdentifiers",
                                       de: "com.apple.speech.recognition.AppleSpeechRecognition.prefs") as? [String]) ?? []).map(normal)
        let sistema = idiomasDelSistema()
        let usados = Set((preferidos + sistema + (siriActiva ? [sesion].compactMap { $0 } : [])).map(base))
        func uso(_ l: String) -> String? {
            if preferidos.contains(l) { return "es tu idioma de dictado" }
            if siriActiva && sesion == l { return "es el idioma de Siri" }
            if sistema.contains(l) { return "es el idioma de tu Mac" }
            return nil
        }
        var x = Recurso(id: .dictado, titulo: "Dictado sin conexión y reconocimiento de voz", icono: "mic", bytes: bytes,
                        que: "Los modelos que reconocen tu voz sin conexión para el dictado (y para Siri), uno por idioma.",
                        ajuste: "Ajustes del Sistema › Teclado › Dictado › Idiomas: quita los que no uses.",
                        consecuencia: "Ya no podrás dictar sin conexión en esos idiomas. Si vuelves a añadir uno, macOS lo baja otra vez (medio GB, más o menos).",
                        destino: .ajustes(ajustesTeclado), boton: "Abrir Teclado", medida: "por sus descriptores")
        x.estado.append("Dictado \(dictadoActivo ? "activado" : "apagado"); Siri \(siriActiva ? "activada\(sesion.map { " (en \(nombreIdioma($0)))" } ?? "")" : "apagada").")
        if !preferidos.isEmpty { x.estado.append("Dictas en \(Formato.lista(preferidos.map(nombreIdioma))).") }
        if !instalados.isEmpty { x.estado.append("Dictado sin conexión instalado para \(Formato.lista(instalados.map(nombreIdioma))).") }
        for b in Set(porIdioma.keys.map(base)).sorted() {
            let grupo = porIdioma.keys.filter { base($0) == b }.sorted()
            if !dictadoActivo && !siriActiva {
                for l in grupo {
                    x.liberable += porIdioma[l] ?? 0
                    x.detalles.append("\(nombreIdioma(l)): \(Formato.bytes(porIdioma[l] ?? 0)), sobra: tienes apagados el dictado y Siri.")
                }
                continue
            }
            // Un idioma que no es de dictado, ni del Mac, ni de Siri no está en la lista de Idiomas del dictado: el ajuste no
            // lo quita (puede pedirlo otra cosa, o ser de una lista vieja). Solo «quizá».
            guard usados.contains(b) else {
                for l in grupo {
                    x.quiza += porIdioma[l] ?? 0
                    x.detalles.append("\(nombreIdioma(l)): \(Formato.bytes(porIdioma[l] ?? 0)), quizá no lo usas: no es tu idioma de dictado ni el de tu Mac, y no está en Teclado › Dictado › Idiomas. macOS lo quita solo cuando nada lo pide (si aparece en esa lista, quítalo allí).")
                }
                continue
            }
            // Del mismo idioma basta uno: el que usas o, si ninguno coincide del todo, el de Siri o el primero.
            let exactos = grupo.filter { uso($0) != nil }
            let quedan = exactos.isEmpty ? [grupo.first { $0 == sesion } ?? grupo[0]] : exactos
            for l in grupo {
                if quedan.contains(l) {
                    x.detalles.append("\(nombreIdioma(l)): \(Formato.bytes(porIdioma[l] ?? 0)), se queda: \(uso(l) ?? "es el que más se parece a tu idioma").")
                } else {
                    x.quiza += porIdioma[l] ?? 0
                    x.detalles.append("\(nombreIdioma(l)): \(Formato.bytes(porIdioma[l] ?? 0)), quizá sobra: ya tienes \(nombreIdioma(quedan[0])).")
                }
            }
        }
        return x
    }

    /// Voces de Siri descargadas (UAF.Siri.TextToSpeech): la que no es la de Siri ni la de Contenido leído, quizá sobra.
    static func voces(_ ds: [Descriptor]) -> Recurso? {
        let bytes = suma(ds)
        guard bytes >= minimo else { return nil }
        let salidaSiri = preferencia("Output Voice", de: "com.apple.assistant.backedup") as? [String: Any]
        let idiomaSiri = (salidaSiri?["Language"] as? String).map(normal)
        let nombreSiri = (salidaSiri?["Name"] as? String)?.lowercased()
        let contenidoLeido = dominioComoTexto("com.apple.speech.voice.prefs").lowercased()
        var x = Recurso(id: .voces, titulo: "Voces de Siri descargadas", icono: "waveform", bytes: bytes,
                        que: "Las voces neuronales con las que hablan Siri y, si las eliges, Contenido leído.",
                        ajuste: "Ajustes del Sistema › Apple Intelligence y Siri › Voz de Siri, y Accesibilidad › Contenido leído › Voz del sistema › Gestionar voces. macOS deja de guardar las voces que nadie usa.",
                        consecuencia: "Si eliges otra vez esa voz, macOS la baja de nuevo.",
                        destino: .ajustes(ajustesAccesibilidad), boton: "Abrir Accesibilidad", medida: "por sus descriptores")
        if let idiomaSiri, let nombreSiri { x.estado.append("La voz de Siri es \(nombreSiri.capitalized) (\(nombreIdioma(idiomaSiri))).") }
        for d in ds {
            guard let r = d.especificador.range(of: ".voice.") else { continue }
            let partes = d.especificador[r.upperBound...].split(separator: ".").map(String.init)
            guard partes.count >= 2 else { continue }
            let (loc, nombre) = (partes[0], partes[1].lowercased())
            if loc == idiomaSiri && nombre == nombreSiri || contenidoLeido.contains(nombre) {
                x.detalles.append("\(nombre.capitalized) (\(nombreIdioma(loc))): \(Formato.bytes(d.bytes)), en uso.")
            } else {
                x.quiza += d.bytes
                x.detalles.append("\(nombre.capitalized) (\(nombreIdioma(loc))): \(Formato.bytes(d.bytes)), quizá no la usas: no es la voz de Siri ni la de Contenido leído.")
            }
        }
        return x.quiza > 0 || bytes >= 200_000_000 ? x : nil
    }

    /// Datos lingüísticos opcionales (texto predictivo, análisis de lenguaje) de idiomas que no aparecen por ningún lado.
    static func idiomasExtra(_ ds: [Descriptor]) -> Recurso? {
        let bytes = suma(ds)
        guard bytes >= minimo else { return nil }
        // Lo que dice que usas un idioma: el sistema, el dictado, las fuentes de entrada y lo que macOS aprendió mientras
        // escribías en él (~/Library/LanguageModeling/<idioma>-dynamic.lm) en los últimos 30 días.
        var usados = Set(idiomasDelSistema().map(base) + (((preferencia("DictationIMPreferredLanguageIdentifiers",
            de: "com.apple.speech.recognition.AppleSpeechRecognition.prefs") as? [String]) ?? []).map(base)))
        usados.formUnion(["en", "mul_Latn"])   // el inglés y el alfabeto latino los usa macOS siempre
        let entradas = String(describing: preferencia("AppleEnabledInputSources", de: "com.apple.HIToolbox") ?? "").lowercased()
        let modelos = Rutas.enHome("Library/LanguageModeling").path
        let hace30 = Date().addingTimeInterval(-30 * 86400)
        for n in (try? FileManager.default.contentsOfDirectory(atPath: modelos)) ?? [] where n.hasSuffix("-dynamic.lm") {
            var st = stat()
            guard lstat(modelos + "/" + n, &st) == 0, Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)) > hace30 else { continue }
            usados.insert(String(n.dropLast("-dynamic.lm".count)).trimmingCharacters(in: .whitespaces))
        }
        var x = Recurso(id: .idiomas, titulo: "Datos de idiomas para escribir", icono: "character.bubble", bytes: bytes,
                        que: "Datos lingüísticos que macOS baja para el texto predictivo, la corrección y el análisis del lenguaje, uno por idioma.",
                        ajuste: "Ajustes del Sistema › General › Idioma y región, y Teclado › Fuentes de entrada: quita los idiomas que no uses. macOS no tiene un ajuste para borrar solo estos datos.",
                        consecuencia: "Si vuelves a escribir en ese idioma, macOS los baja otra vez.",
                        destino: .ajustes(ajustesIdioma), boton: "Abrir Idioma y región", medida: "por sus descriptores")
        for d in ds.sorted(by: { $0.bytes > $1.bytes }) {
            guard d.especificador.hasSuffix("-device"), let ultimo = d.especificador.split(separator: ".").last else { continue }
            let idioma = String(ultimo.dropLast("-device".count))
            // «mul_Hani» (chino y japonés): se usa si escribes en alguno de ellos.
            let hani = idioma == "mul_Hani" && !usados.isDisjoint(with: ["zh", "ja", "yue"])
            // Una fuente de entrada de ese idioma («German», «Russian - PC»…), por su nombre en inglés.
            let ingles = Locale(identifier: "en").localizedString(forLanguageCode: idioma)?.lowercased()
            if usados.contains(idioma) || hani || (ingles.map { $0.count >= 4 && entradas.contains($0) } ?? false) {
                x.detalles.append("\(nombreDeDatos(idioma)): \(Formato.bytes(d.bytes)), en uso.")
            } else {
                x.quiza += d.bytes
                x.detalles.append("\(nombreDeDatos(idioma)): \(Formato.bytes(d.bytes)), quizá no lo usas.")
            }
        }
        return x.quiza > 0 ? x : nil
    }

    static func nombreDeDatos(_ idioma: String) -> String {
        switch idioma {
        case "mul_Hani": return "chino y japonés (caracteres han)"
        case "mul_Latn": return "alfabeto latino"
        default: return Locale(identifier: "es").localizedString(forLanguageCode: idioma) ?? idioma
        }
    }

    /// Modelos de Fotos, Atajos, búsqueda y traducción que van con Apple Intelligence.
    static func funciones(_ ds: [Descriptor]) -> Recurso? {
        let bytes = suma(ds)
        guard bytes >= minimo else { return nil }
        return Recurso(id: .funciones, titulo: "Modelos de Fotos, Atajos, búsqueda y traducción", icono: "sparkles.rectangle.stack",
                       bytes: bytes, quiza: bytes,
                       que: "Modelos que usan las escenas espaciales de Fotos, el generador de Atajos, la búsqueda en lenguaje natural y la traducción.",
                       estado: ["Están en uso: macOS los quita si desactivas Apple Intelligence."],
                       detalles: ds.sorted { $0.bytes > $1.bytes }.prefix(4).map { "\(nombreCorto($0.especificador)): \(Formato.bytes($0.bytes))" },
                       ajuste: "Ajustes del Sistema › Apple Intelligence y Siri › desactiva Apple Intelligence.",
                       consecuencia: "Esas funciones dejan de estar disponibles hasta que la vuelvas a activar.",
                       destino: .ajustes(ajustesAppleIntelligence), boton: "Abrir Apple Intelligence y Siri", medida: "por sus descriptores")
    }

    // MARK: - Volúmenes y Rosetta

    /// Los volúmenes del contenedor de arranque (diskutil apfs list -plist): cuánto usa cada uno y cómo lo cuenta Ajustes.
    static func volumenes() -> [Volumen] {
        let datos: Data?
        if let raiz = raizDePrueba { datos = FileManager.default.contents(atPath: raiz + "/salidas/diskutil-apfs-list.plist") }
        else { datos = salida("/usr/sbin/diskutil", ["apfs", "list", "-plist"], prueba: "", limite: 15).map { Data($0.utf8) } }
        guard let datos, let plist = try? PropertyListSerialization.propertyList(from: datos, format: nil) as? [String: Any],
              let contenedores = plist["Containers"] as? [[String: Any]] else { return [] }
        // El del volumen de datos de este arranque (en una casa de prueba, el primero que tiene uno).
        let dispositivo = deVerdad ? dispositivoDeDatos() : nil
        let vols: ([String: Any]) -> [[String: Any]] = { ($0["Volumes"] as? [[String: Any]]) ?? [] }
        guard let c = contenedores.first(where: { c in vols(c).contains { v in
            dispositivo.map { v["DeviceIdentifier"] as? String == $0 } ?? ((v["Roles"] as? [String])?.contains("Data") ?? false)
        } }) else { return [] }
        let orden = ["Data", "System", "Preboot", "Recovery", "VM", "Update"]
        let ordenados = vols(c).sorted { a, b in
            let (ra, rb) = ((a["Roles"] as? [String])?.first ?? "", (b["Roles"] as? [String])?.first ?? "")
            return (orden.firstIndex(of: ra) ?? orden.count) < (orden.firstIndex(of: rb) ?? orden.count)
        }
        return ordenados.compactMap { v in
            guard let id = v["DeviceIdentifier"] as? String, let usado = (v["CapacityInUse"] as? NSNumber)?.int64Value else { return nil }
            let rol = (v["Roles"] as? [String])?.first ?? ""
            let nombre = v["Name"] as? String ?? id
            switch rol {
            case "Data":
                return Volumen(id: id, nombre: nombre, rol: "Datos", bytes: usado, cuentaComo: "Tus archivos, las apps y casi todos los «Datos del sistema»")
            case "System":
                return Volumen(id: id, nombre: nombre, rol: "Sistema", bytes: usado, cuentaComo: "macOS: el sistema sellado, de solo lectura")
            case "Preboot":
                return Volumen(id: id, nombre: nombre, rol: "Arranque", bytes: usado,
                               cuentaComo: "macOS: el arranque, la parte del sistema que se actualiza aparte (Safari, la caché del sistema) y Rosetta")
            case "Recovery":
                return Volumen(id: id, nombre: nombre, rol: "Recuperación", bytes: usado, cuentaComo: "macOS: la recuperación")
            case "VM":
                return Volumen(id: id, nombre: nombre, rol: "Memoria virtual", bytes: usado, cuentaComo: "Datos del sistema: la memoria de intercambio (swap)",
                               nota: usado > 1_000_000_000 ? "Se vacía al reiniciar el Mac." : nil)
            case "Update":
                return Volumen(id: id, nombre: nombre, rol: "Actualización", bytes: usado, cuentaComo: "macOS: lo que deja la última actualización",
                               nota: usado > 1_000_000_000 ? "Puede haber una actualización de macOS bajada o a medias: mira Ajustes › General › Actualización de software." : nil)
            default:
                return Volumen(id: id, nombre: nombre, rol: rol.isEmpty ? "Otro" : rol, bytes: usado, cuentaComo: "macOS")
            }
        }
    }

    /// «disk3s1»: el dispositivo del volumen de datos del arranque.
    static func dispositivoDeDatos() -> String? {
        var s = statfs()
        guard statfs("/System/Volumes/Data", &s) == 0 else { return nil }
        let desde = withUnsafePointer(to: &s.f_mntfromname) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
        return desde.hasPrefix("/dev/") ? String(desde.dropFirst(5)) : nil
    }

    /// Rosetta (para apps de Intel): si está instalada, lo que ocupa en el arranque y qué apps la necesitan.
    static func rosetta() -> Rosetta? {
        var st = stat()
        guard lstat(ruta("/Library/Apple/usr/libexec/oah/libRosettaRuntime"), &st) == 0 else { return nil }
        var bytes: Int64?
        let arranque = ruta("/System/Volumes/Preboot")
        for n in (try? FileManager.default.contentsOfDirectory(atPath: arranque)) ?? [] where n.count == 36 {
            if lstat(arranque + "/" + n + "/cryptex1/current/rosetta.dmg", &st) == 0 { bytes = Int64(st.st_blocks) * 512; break }
        }
        return Rosetta(bytes: bytes, appsIntel: appsSoloIntel())
    }

    /// Las apps que solo traen código de Intel: las de Aplicaciones (leyendo la cabecera de su ejecutable) y, en el Mac de
    /// verdad, las que Spotlight sabe que no tienen arm64.
    static func appsSoloIntel() -> [String] {
        var apps: [String] = []
        for carpeta in [ruta("/Applications"), Rutas.enHome("Applications").path] {
            for h in (try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? [] {
                let p = carpeta + "/" + h
                if h.hasSuffix(".app") { apps.append(p) } else if !h.hasPrefix(".") {
                    apps += ((try? FileManager.default.contentsOfDirectory(atPath: p)) ?? []).filter { $0.hasSuffix(".app") }.map { p + "/" + $0 }
                }
            }
        }
        var r = Set(apps.filter(necesitaRosetta))
        if deVerdad, let s = salida("/usr/bin/mdfind", ["kMDItemContentType == \"com.apple.application-bundle\" && kMDItemExecutableArchitectures == \"x86_64\" && kMDItemExecutableArchitectures != \"arm64\""], prueba: "", limite: 8) {
            for l in s.split(separator: "\n").prefix(50) where l.hasPrefix("/") && !l.hasPrefix("/System/") && !l.hasPrefix("/Library/Apple/") && !l.contains("/.Trash/") {
                r.insert(String(l))
            }
        }
        return r.sorted()
    }

    /// La app trae código de Intel y no de Apple Silicon (su ejecutable principal).
    static func necesitaRosetta(_ app: String) -> Bool {
        guard let info = NSDictionary(contentsOfFile: app + "/Contents/Info.plist"), let exe = info["CFBundleExecutable"] as? String,
              let tipos = arquitecturas(app + "/Contents/MacOS/" + exe) else { return false }
        return tipos.contains(0x0100_0007) && !tipos.contains(0x0100_000C)   // CPU_TYPE_X86_64, CPU_TYPE_ARM64
    }

    /// Los tipos de CPU de un ejecutable Mach-O (de la cabecera; uno o varios si es universal). nil si no es Mach-O.
    static func arquitecturas(_ ruta: String) -> Set<Int32>? {
        var st = stat()
        guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, let h = FileHandle(forReadingAtPath: ruta) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4096), d.count >= 8 else { return nil }
        let b = [UInt8](d)
        func be(_ o: Int) -> UInt32 { o + 4 <= b.count ? UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3]) : 0 }
        func le(_ o: Int) -> UInt32 { o + 4 <= b.count ? UInt32(b[o + 3]) << 24 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 1]) << 8 | UInt32(b[o]) : 0 }
        switch be(0) {
        case 0xCAFE_BABE, 0xCAFE_BABF:   // universal (FAT_MAGIC, FAT_MAGIC_64)
            let n = Int(be(4))
            let paso = be(0) == 0xCAFE_BABF ? 32 : 20
            guard (1...16).contains(n) else { return nil }   // las clases de Java también empiezan por CAFEBABE
            return Set((0..<n).map { Int32(bitPattern: be(8 + $0 * paso)) })
        case 0xCFFA_EDFE, 0xCEFA_EDFE:   // MH_MAGIC_64 y MH_MAGIC, guardados al revés (little endian)
            return [Int32(bitPattern: le(4))]
        default:
            return nil
        }
    }

    // MARK: - Registros y memoria virtual

    /// Los registros unificados (diagnostics y uuidtext): solo los lee un administrador. nil (y false) si no se pueden.
    static func registros() -> (Registros?, Bool) {
        let carpetas = [ruta("/private/var/db/diagnostics"), ruta("/private/var/db/uuidtext")].filter { Rutas.existe($0) }
        guard !carpetas.isEmpty else { return (nil, true) }
        guard carpetas.allSatisfy({ access($0, R_OK | X_OK) == 0 }) else { return (nil, false) }
        let bytes = carpetas.reduce(Int64(0)) { $0 + (MedidaFuera.du($1, limite: 60) ?? 0) }
        var masAntiguo: Date?
        var persist: Date?
        for sub in ["Persist", "Special", "Signpost", "HighVolume"] {
            let c = carpetas[0] + "/" + sub
            for n in (try? FileManager.default.contentsOfDirectory(atPath: c)) ?? [] where n.hasSuffix(".tracev3") {
                var st = stat()
                guard lstat(c + "/" + n, &st) == 0 else { continue }
                let f = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                masAntiguo = min(masAntiguo ?? f, f)
                if sub == "Persist" { persist = min(persist ?? f, f) }
            }
        }
        return (Registros(bytes: bytes, masAntiguo: masAntiguo, horasPersist: persist.map { Date().timeIntervalSince($0) / 3600 }), true)
    }

    /// «hibernatemode 3» de pmset -g.
    static func hibernacion(_ s: String) -> Int? {
        s.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("hibernatemode") }
            .flatMap { Int($0.split(separator: " ", omittingEmptySubsequences: true).last ?? "") }
    }

    /// Lo que ocupan en el disco los archivos de intercambio (sysctl vm.swapusage: su total, no lo que está en uso
    /// dentro). nil si sysctl no contesta.
    static func swapEnDisco() -> Int64? {
        var uso = xsw_usage()
        var tam = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &uso, &tam, nil, 0) == 0 ? Int64(uso.xsu_total) : nil
    }

    // MARK: - Lo que solo ve root

    static let candidatosOcultos: [(ruta: String, que: String)] = [
        ("/System/Volumes/Data/.Spotlight-V100", "El índice de Spotlight"),
        ("/System/Volumes/Data/.fseventsd", "El historial de cambios de archivos (lo usan Spotlight, Time Machine y las apps que vigilan carpetas)"),
        ("/System/Volumes/Data/.DocumentRevisions-V100", "Las versiones guardadas de tus documentos"),
        ("/private/var/folders/zz", "Cachés y temporales de los usuarios del sistema"),
        ("/private/var/root", "La carpeta del usuario root"),
        ("/Library/Caches/com.apple.iconservices.store", "La caché de iconos"),
        ("/System/Library/Caches/com.apple.coresymbolicationd", "La caché de símbolos de los informes de fallos y de Instruments"),
        ("/Library/Caches/com.microsoft.autoupdate.helper/Clones.noindex", "Las copias que deja Microsoft AutoUpdate al actualizar Office"),
        ("/Library/Caches/com.apple.aned", "Los modelos compilados para el Neural Engine"),
        ("/private/var/db/oah", "La caché de Rosetta"),
        ("/private/var/db/AppleIntelligencePlatform", "Datos de Apple Intelligence"),
        ("/private/var/db/Spotlight-V100", "Más índices de Spotlight"),
        ("/private/var/db/biome", "Lo que macOS aprende de cómo usas el Mac (Biome)"),
        ("/private/var/db/analyticsd", "Análisis y estadísticas de macOS"),
        ("/private/var/db/DifferentialPrivacy", "Estadísticas con privacidad diferencial"),
    ]

    /// Las carpetas que la app no puede leer y que suelen ocupar lo que «solo ve root». EPERM: la protege macOS (SIP), ni
    /// con contraseña se lee; EACCES: un administrador la puede medir.
    static func ocultos(accesoTotal: Bool) -> [Oculto] {
        candidatosOcultos.compactMap { c in
            let p = ruta(c.ruta)
            var st = stat()
            // Algunas no dejan ni mirarlas (stat): basta con que aparezcan en su carpeta.
            let enSuCarpeta = nombres(en: Rutas.padre(p)).contains(Rutas.nombre(p))
            guard lstat(p, &st) == 0 || enSuCarpeta else { return nil }
            if let d = opendir(p) { closedir(d); return nil }
            return Oculto(ruta: c.ruta, que: c.que, protegida: errno == EPERM && accesoTotal)
        }
    }

    /// Lo que mide «Medir con contraseña»: un du de solo lectura, siempre el mismo (no lleva nada de fuera). Al final, las
    /// carpetas de las otras cuentas de /Users (y Deleted Users), que cuentan en lo que solo ve root: las elige find como
    /// administrador, sin que la app meta ningún nombre en el comando. Quita /Users/Shared y la carpeta de quien tiene la
    /// sesión abierta (el dueño de /dev/console): ya las mide el índice, y recorrerlas tardaría mucho.
    static let comandoRoot = "/usr/bin/du -skx /System/Volumes/Data/.Spotlight-V100 /System/Volumes/Data/.fseventsd /System/Volumes/Data/.DocumentRevisions-V100 /private/var/db/* /private/var/folders/zz/* /private/var/root /Library/Caches/* /System/Library/Caches/* 2>/dev/null; /usr/bin/find /Users -mindepth 1 -maxdepth 1 -type d ! -name Shared ! -user $(/usr/bin/stat -f %u /dev/console) -exec /usr/bin/du -skx {} + 2>/dev/null; exit 0"

    /// Ejecuta `comandoRoot` como administrador (macOS pide la contraseña en su propia ventana). nil si se canceló o falló.
    static func medirComoAdministrador() -> [MedidaRoot]? {
        let guion = "do shell script \"\(comandoRoot)\" with prompt \"LimpiadorMac quiere medir, sin cambiar nada, lo que solo puede leer un administrador.\" with administrator privileges without altering line endings"
        let r = Shell.ejecutar("/usr/bin/osascript", ["-e", guion], limite: 600)
        guard r.estado == 0 else { return nil }
        // Tu carpeta y la compartida ya las mide el índice (si la sesión abierta es de otra cuenta, la tuya sale en el du).
        return medidasRoot(r.salida).filter { $0.ruta != NSHomeDirectory() && $0.ruta != "/Users/Shared" }
    }

    /// «12345\t/ruta» por línea → de mayor a menor (sin las de menos de 1 MB).
    static func medidasRoot(_ s: String) -> [MedidaRoot] {
        s.split(separator: "\n").compactMap { l -> MedidaRoot? in
            let partes = l.split(separator: "\t", maxSplits: 1)
            guard partes.count == 2, let kb = Int64(partes[0].trimmingCharacters(in: .whitespaces)), kb >= 1024 else { return nil }
            return MedidaRoot(ruta: String(partes[1]), bytes: kb * 1024)
        }.sorted { $0.bytes > $1.bytes }
    }

    // MARK: - Restos con contraseña

    /// Una palabra para la Terminal: tal cual si es segura, entre comillas simples si no.
    static func comillas(_ s: String) -> String {
        let seguros = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/+:@")
        if !s.isEmpty && s.unicodeScalars.allSatisfy(seguros.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func ocupa(_ p: String) -> Int64 {
        var st = stat()
        return lstat(p, &st) == 0 ? Int64(st.st_blocks) * 512 : 0
    }

    /// Los ejecutables de todos los procesos (proc_pidpath): para saber si un servicio está funcionando.
    static func programasEnMarcha() -> Set<String> {
        var r = Set<String>()
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in Procesos.todosLosPids() where proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
            r.insert(String(cString: buf))
        }
        return r
    }

    /// Hay una app instalada de ese fabricante («com.muse») o con alguno de esos identificadores.
    static func hayApp(fabricante: String, ids: [String], apps: AppsInstaladas) -> Bool {
        if apps.fabricantes.contains(fabricante) || apps.bundleIDs.contains(where: { $0.hasPrefix(fabricante + ".") }) { return true }
        if ids.contains(where: { apps.bundleIDs.contains($0.lowercased()) }) { return true }
        guard deVerdad else { return false }
        let limpio: (String) -> String = { $0.filter { $0 != "\"" && $0 != "*" && $0 != "\\" } }
        let consulta = (["kMDItemCFBundleIdentifier == \"\(limpio(fabricante)).*\"c"] + ids.map { "kMDItemCFBundleIdentifier == \"\(limpio($0))\"" })
            .joined(separator: " || ")
        // Si Spotlight no contesta, mejor no decir que no hay app (como en recibos()).
        guard let s = salida("/usr/bin/mdfind", [consulta], prueba: "", limite: 5) else { return true }
        return s.split(separator: "\n").contains { l in
            l.hasSuffix(".app") && !l.hasPrefix("/Library/SystemExtensions/") && !l.contains("/.Trash/")
        }
    }

    /// Servicios de /Library/LaunchDaemons y /Library/LaunchAgents cuyo programa ya no existe, o ayudantes con privilegios
    /// (/Library/PrivilegedHelperTools) de un fabricante del que no queda ninguna app. Los de Apple nunca.
    static func servicios(apps: AppsInstaladas, programas: Set<String>) -> [Resto] {
        var r: [Resto] = []
        for (carpeta, sistema) in [("/Library/LaunchDaemons", true), ("/Library/LaunchAgents", false)] {
            for n in ((try? FileManager.default.contentsOfDirectory(atPath: ruta(carpeta))) ?? []).sorted() where n.hasSuffix(".plist") {
                let plist = carpeta + "/" + n
                var st = stat()
                guard lstat(ruta(plist), &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size < 1_000_000,
                      let d = NSDictionary(contentsOfFile: ruta(plist)) as? [String: Any],
                      let etiqueta = d["Label"] as? String, !etiqueta.lowercased().hasPrefix("com.apple.") else { continue }
                guard let programa = (d["Program"] as? String) ?? (d["ProgramArguments"] as? [String])?.first, programa.hasPrefix("/") else { continue }
                let ids = (d["AssociatedBundleIdentifiers"] as? [String]) ?? (d["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []
                let fabricante = etiqueta.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
                // «Ya no existe» solo si macOS lo dice (ENOENT, ENOTDIR). Si no deja mirarlo (EACCES por una carpeta solo de
                // root, EPERM por TCC o un antimanipulación), no se puede comprobar: no se lista, salvo que esté funcionando
                // (entonces existe). Uno que funciona aunque su programa ya no esté (lo borraron con él en marcha) tampoco:
                // macOS aún lo tiene abierto.
                let funciona = programas.contains(programa)
                let fallo = lstat(ruta(programa), &st) == 0 ? 0 : errno
                let existe: Bool
                if fallo == 0 {
                    existe = true
                } else if fallo == ENOENT || fallo == ENOTDIR {
                    guard !funciona else { continue }
                    existe = false
                } else if funciona {
                    existe = true
                } else {
                    continue
                }
                let ayudante = programa.hasPrefix("/Library/PrivilegedHelperTools/")
                let motivo: String
                if !existe {
                    motivo = "Su programa ya no existe (\(Formato.rutaCorta(programa))): macOS lo intenta arrancar y falla."
                } else if ayudante && !hayApp(fabricante: fabricante, ids: ids, apps: apps) {
                    motivo = "Su programa sigue ahí (\(Formato.bytes(ocupa(ruta(programa))))), pero no queda ninguna app de \(fabricante): es el ayudante de una app que ya desinstalaste."
                } else {
                    continue
                }
                let enMarcha = existe && funciona
                var comando = sistema ? "sudo launchctl bootout \(comillas("system/" + etiqueta))"
                                      : "launchctl bootout gui/$(id -u)/\(comillas(etiqueta))"
                comando += "\nsudo rm \(comillas(plist))" + (existe && ayudante ? " \(comillas(programa))" : "")
                r.append(Resto(id: plist, titulo: "\(sistema ? "Servicio del sistema" : "Agente de inicio") sin app: \(etiqueta)",
                               detalle: motivo + (enMarcha ? " Ahora mismo está funcionando\(sistema ? " como root" : "")." : "")
                                   + " Se quita con tu contraseña (la app nunca lo hace por ti).",
                               bytes: ocupa(ruta(plist)) + (existe && ayudante ? ocupa(ruta(programa)) : 0),
                               comando: comando, enMarcha: enMarcha))
            }
        }
        return r
    }

    /// Extensiones del sistema activas (systemextensionsctl list, sin contraseña) de apps que ya no están. macOS no deja
    /// quitarlas por comando: solo desde Ajustes.
    static func extensiones(apps: AppsInstaladas) -> [Resto] {
        guard let s = salida("/usr/bin/systemextensionsctl", ["list"], prueba: "systemextensionsctl.txt", limite: 10) else { return [] }
        var r: [Resto] = []
        var categoria = ""
        for l in s.split(separator: "\n").map(String.init) {
            if l.hasPrefix("---") { categoria = l; continue }
            let c = l.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count >= 6, l.contains("[activated"), let id = c[3].split(separator: " ").first.map(String.init), id.contains(".") else { continue }
            let partes = id.lowercased().split(separator: ".")
            let fabricante = partes.prefix(2).joined(separator: ".")
            // La app que la trae: el identificador sin el final («…obs-studio.mac-camera-extension» → «…obs-studio»).
            let contenedoras = (2..<max(2, partes.count)).map { partes.prefix($0).joined(separator: ".") }
            guard !hayApp(fabricante: fabricante, ids: contenedoras.filter { $0 != fabricante }, apps: apps) else { continue }
            let tipo = categoria.contains("cmio") ? "Extensiones de cámara" : categoria.contains("driver") ? "Extensiones de controladores"
                : categoria.contains("network") ? "Extensiones de red" : categoria.contains("endpoint") ? "Extensiones de seguridad" : "Extensiones"
            r.append(Resto(id: "ext:" + id, titulo: "Extensión del sistema sin app: \(c[4].isEmpty ? id : c[4])",
                           detalle: "Sigue activada (\(id), de \(c[2])) aunque ya no tienes ninguna app de \(fabricante). macOS no deja quitarla por comando: desactívala en Ajustes del Sistema › General › Ítems de inicio y extensiones › \(tipo).",
                           destino: .ajustes(ajustesExtensiones)))
        }
        return r
    }

    /// Recibos de paquetes (/private/var/db/receipts) cuyas apps ya no están: pkgutil los sigue dando por instalados.
    static func recibos() -> [Resto] {
        let carpeta = ruta("/private/var/db/receipts")
        var candidatos: [(id: String, apps: [String], bytes: Int64)] = []
        for n in nombres(en: carpeta).sorted() where n.hasSuffix(".plist") {
            let id = String(n.dropLast(".plist".count))
            let bom = carpeta + "/" + id + ".bom"
            var st = stat()
            guard lstat(bom, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size < 100_000_000,
                  let info = NSDictionary(contentsOfFile: carpeta + "/" + n) else { continue }
            let prefijo = (info["InstallPrefixPath"] as? String ?? "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let lista = Shell.ejecutar("/usr/bin/lsbom", ["-s", "-d", bom], limite: 10, prioridad: .utility).salida
            // Las apps de primer nivel del paquete («./Applications/GarageBand.app», «./OneDrive.app»).
            let apps = lista.split(separator: "\n").compactMap { l -> String? in
                let rel = l.hasPrefix("./") ? String(l.dropFirst(2)) : String(l)
                return rel.hasSuffix(".app") && rel.split(separator: "/").count <= 2 ? rel : nil
            }
            guard !apps.isEmpty, !apps.contains(where: { appExiste($0, prefijo: prefijo) }) else { continue }
            candidatos.append((id, apps.map { Rutas.nombre($0) }, ocupa(bom) + ocupa(carpeta + "/" + n)))
        }
        // En el Mac de verdad, una sola consulta a Spotlight por si alguna está en otro sitio (Descargas, otro disco…).
        if deVerdad && !candidatos.isEmpty {
            let consulta = "kMDItemContentType == \"com.apple.application-bundle\" && ("
                + Set(candidatos.flatMap(\.apps)).sorted().map { "kMDItemFSName == \"\($0.replacingOccurrences(of: "\"", with: ""))\"" }.joined(separator: " || ") + ")"
            let s = salida("/usr/bin/mdfind", [consulta], prueba: "", limite: 8)
            // Si Spotlight no contesta, mejor no decir que falta nada.
            guard let s else { return [] }
            let halladas = Set(s.split(separator: "\n").filter { $0.hasPrefix("/") && !$0.contains("/.Trash/") }.map { Rutas.nombre(String($0)) })
            candidatos.removeAll { !halladas.isDisjoint(with: $0.apps) }
        }
        guard !candidatos.isEmpty else { return [] }
        let bytes = candidatos.reduce(Int64(0)) { $0 + $1.bytes }
        let nombres = Array(Set(candidatos.compactMap { $0.apps.first.map { ($0 as NSString).deletingPathExtension } })).sorted()
        return [Resto(id: "recibos", titulo: "Recibos de \(candidatos.count) \(candidatos.count == 1 ? "paquete" : "paquetes") que ya no están",
                      detalle: "macOS sigue apuntando como instalados \(Formato.listaCorta(nombres, maximo: 6)), aunque ya no están. Ocupan poco; quitarlos solo borra el recibo (pkgutil --forget), nunca archivos tuyos.",
                      bytes: bytes, comando: candidatos.map { "sudo pkgutil --forget \(comillas($0.id))" }.joined(separator: "\n"))]
    }

    /// La app de un paquete existe donde la instaló o en Aplicaciones (de la casa de prueba, en las pruebas).
    static func appExiste(_ rel: String, prefijo: String) -> Bool {
        let nombre = Rutas.nombre(rel)
        var st = stat()
        let sitios = [prefijo.isEmpty ? "/" + rel : "/" + prefijo + "/" + rel, "/Applications/" + nombre, "/Applications/Utilities/" + nombre]
        return sitios.contains { lstat(ruta($0), &st) == 0 } || lstat(Rutas.enHome("Applications/" + nombre).path, &st) == 0
    }

    /// Las copias que Microsoft AutoUpdate deja en Clones.noindex: solo root las ve.
    static func clonesDeAutoUpdate(programas: Set<String>) -> [Resto] {
        let carpeta = "/Library/Caches/com.microsoft.autoupdate.helper"
        guard nombres(en: ruta(carpeta)).contains("Clones.noindex") else { return [] }
        let actualizando = programas.contains { p in ["Microsoft AutoUpdate", "Microsoft Update Assistant", "com.microsoft.autoupdate.helper", "msupdate"].contains(Rutas.nombre(p)) }
        let clones = carpeta + "/Clones.noindex"
        return [Resto(id: clones, titulo: "Copias que dejó Microsoft AutoUpdate (sin medir)",
                      detalle: "Microsoft AutoUpdate copia la app de Office que va a actualizar, la parchea y la cambia por la original. Las copias que quedan pueden ocupar varios GB, pero solo root las ve."
                          + (actualizando ? " Ahora mismo está actualizando: no lo borres hasta que termine." : " Bórralas solo si no hay ninguna actualización de Office en curso; las vuelve a crear cuando las necesita."),
                      comando: "sudo du -sh \(comillas(clones))\n# Si pesa y Office no se está actualizando:\nsudo rm -rf \(comillas(clones))/*",
                      enMarcha: actualizando)]
    }

    /// La caché de símbolos del sistema: solo root la mide.
    static func cacheDeSimbolos() -> [Resto] {
        let carpeta = "/System/Library/Caches/com.apple.coresymbolicationd"
        var st = stat()
        guard lstat(ruta(carpeta), &st) == 0 else { return [] }
        return [Resto(id: carpeta, titulo: "Caché de símbolos del sistema (sin medir)",
                      detalle: "La usan los informes de fallos, spindump e Instruments para poner nombre a lo que falla. En Macs con Xcode suele crecer hasta 1 o 2 GB y se regenera. Bórrala solo si pesa más de 500 MB y no tienes abiertos Xcode ni Instruments.",
                      comando: "sudo du -sh \(carpeta)\n# Si pesa más de 500 MB:\nsudo rm -rf \(carpeta)/data")]
    }

    /// Capturas de diagnóstico del Wi-Fi y de otros chips (CoreCapture): macOS las guarda cuando algo falla.
    static func capturasDeRed() -> [Resto] {
        let carpeta = "/Library/Logs/CrashReporter/CoreCapture"
        var r: [Resto] = []
        for sub in ((try? FileManager.default.contentsOfDirectory(atPath: ruta(carpeta))) ?? []).sorted() where !sub.hasPrefix(".") {
            let p = carpeta + "/" + sub
            guard let bytes = MedidaFuera.du(ruta(p), limite: 30), bytes >= 50_000_000 else { continue }
            let capturas = ((try? FileManager.default.contentsOfDirectory(atPath: ruta(p))) ?? []).filter { !$0.hasPrefix(".") }
            // «[2026-10-15_09,33,31.047907]=Net Beacons Lost~Net Beacons Lost» → «Net Beacons Lost».
            let motivos = Dictionary(grouping: capturas.compactMap { n -> String? in
                guard let i = n.firstIndex(of: "=") else { return nil }
                return String(n[n.index(after: i)...].split(separator: "~").first ?? "")
            }, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
            r.append(Resto(id: p, titulo: "Capturas de diagnóstico de \(sub) (\(capturas.count))",
                           detalle: "macOS las guarda cada vez que falla el \(sub)\(motivos.isEmpty ? "" : ": " + Formato.listaCorta(motivos.map { "\($0.0) (\($0.1))" }, maximo: 3)). Las borra solo a los 7 días y vuelven si el problema sigue.",
                           bytes: bytes, comando: "sudo rm -rf \(comillas(p))/*"))
        }
        return r
    }

    /// Imágenes de disco de desarrollador (para depurar en un iPhone o un iPad): si no conectaste ninguno en 90 días.
    static func imagenesDeDesarrollo() -> [Resto] {
        let carpetas = ["/Library/Developer/DeveloperDiskImages", "/Library/Developer/CoreDevice/CandidateDDIs"].filter { Rutas.existe(ruta($0)) }
        guard !carpetas.isEmpty else { return [] }
        let hace90 = Date().addingTimeInterval(-90 * 86400)
        let dispositivos = ["iOS", "watchOS", "tvOS", "visionOS"].map { Rutas.enHome("Library/Developer/Xcode/\($0) DeviceSupport").path }
        if dispositivos.contains(where: { (Fechas.modificacion(URL(fileURLWithPath: $0)) ?? .distantPast) > hace90 }) { return [] }
        let bytes = carpetas.reduce(Int64(0)) { $0 + (MedidaFuera.du(ruta($1), limite: 30) ?? 0) }
        guard bytes >= 100_000_000 else { return [] }
        return [Resto(id: "ddi", titulo: "Imágenes de disco para depurar en dispositivos",
                      detalle: "Xcode las usa para instalar y depurar apps en un iPhone, un iPad o un Apple Watch, y no conectaste ninguno en 90 días. Xcode las vuelve a poner al actualizarse o al conectar un dispositivo: libera poco tiempo.",
                      bytes: bytes, comando: carpetas.map { "sudo rm -rf \(comillas($0))" }.joined(separator: "\n"))]
    }

    // MARK: - Miniaturas de Quick Look

    /// Lo que ocupa la caché de miniaturas, que macOS no deja leer ni con Acceso total: se mira en los archivos que tiene
    /// abiertos el agente de miniaturas de tu usuario, con lsof (el sistema no deja a la app preguntarlo directamente).
    /// nil si el agente no está funcionando o lsof no contesta.
    static func miniaturasAbiertas() -> Int64? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let uid = getuid()
        for pid in Procesos.todosLosPids() where proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
            guard String(cString: buf).hasSuffix("/com.apple.quicklook.ThumbnailsAgent") else { continue }
            var corta = proc_bsdshortinfo()
            let tam = Int32(MemoryLayout<proc_bsdshortinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &corta, tam) == tam, corta.pbsi_uid == uid else { continue }
            let r = Shell.ejecutar("/usr/sbin/lsof", ["-a", "-p", String(pid), "-Fsn"], limite: 5, prioridad: .utility)
            return miniaturas(deLsof: r.salida)
        }
        return nil
    }

    /// De la salida de «lsof -Fsn» («s<tamaño>» y «n<ruta>» por archivo), lo que suman los archivos distintos de la caché
    /// de miniaturas. nil si no hay ninguno.
    static func miniaturas(deLsof s: String) -> Int64? {
        var tamano: Int64?
        var porRuta: [String: Int64] = [:]
        for l in s.split(separator: "\n") {
            if l.hasPrefix("f") { tamano = nil }
            if l.hasPrefix("s") { tamano = Int64(l.dropFirst()) }
            if l.hasPrefix("n"), l.contains("/com.apple.QuickLook.thumbnailcache/"), let tamano { porRuta[String(l.dropFirst())] = tamano }
        }
        return porRuta.isEmpty ? nil : porRuta.values.reduce(0, +)
    }

    // MARK: - Diagnóstico

    /// La sección «Datos del sistema» del modo --diagnostico (solo lectura).
    static func imprimir(visto: Int64?, papelera: Int64, appsExtra: [String] = []) {
        print("\n▶︎ Datos del sistema (solo lectura: no se borra ni se cambia nada)")
        guard aplica else {
            print("  No aplica: casa de prueba sin LIMPIADOR_SISTEMA")
            return
        }
        let i = medir(visto: visto, papelera: papelera, appsExtra: appsExtra)
        func b(_ x: Int64) -> String { Formato.bytes(x) }
        print("  Lo que reconocí: \(b(i.total))\(i.soloRoot == nil ? " (sin lo que solo ve root)" : "") · se liberan con ajustes: \(b(i.conAjustes))\(i.quizaConAjustes > 0 ? " (y quizá \(b(i.quizaConAjustes)) más)" : "")")
        print("  Recursos de Apple (AssetsV2): \(b(i.recursosTotal)) = \(b(i.recursosTotal - i.recursosIlegibles)) legibles con du (sin lo injertado) + \(b(i.recursosIlegibles)) que macOS no deja leer, medidos por sus descriptores\(i.pendientesDeRecoger > 0 ? " · \(b(i.pendientesDeRecoger)) son versiones anteriores que macOS recogerá" : "")")
        for r in i.recursos {
            let libera = r.liberable > 0 ? " — libera \(b(r.liberable))" : ""
            let quiza = r.quiza > 0 ? "\(r.liberable > 0 ? " y" : " —") quizá \(b(r.quiza))" : ""
            print("    \(b(r.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(r.titulo)\(libera)\(quiza)  (\(r.medida))")
            for e in r.estado { print("         · \(e)") }
            for d in r.detalles { print("         → \(d)") }
            if let a = r.ajuste, r.liberable + r.quiza > 0 { print("         = \(a)") }
        }
        if !i.volumenes.isEmpty {
            print("  Volúmenes del disco de arranque:")
            for v in i.volumenes {
                print("    \(b(v.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(v.rol) (\(v.nombre), \(v.id)): \(v.cuentaComo)\(v.nota.map { ". \($0)" } ?? "")")
            }
        }
        if let r = i.rosetta {
            print("  Rosetta: instalada\(r.bytes.map { " (\(b($0)) en el arranque; cuenta como macOS)" } ?? "") · \(r.appsIntel.isEmpty ? "ninguna app tuya la necesita (macOS no deja desinstalarla)" : "la necesitan: \(Formato.listaCorta(r.appsIntel.map { Rutas.nombre($0) }, maximo: 5))")")
        }
        if let r = i.registros {
            let cubre = r.horasPersist.map { $0 < 48 ? " · los registros normales solo cubren \(Int($0)) h: algo escribe demasiado (log stats --overview)" : "" } ?? ""
            print("  Registros unificados: \(b(r.bytes))\(r.masAntiguo.map { " (el más antiguo, \(Formato.haceCuanto($0).lowercased()))" } ?? "")\(cubre)")
        } else if !i.registrosMedibles {
            print("  Registros unificados: no medibles (hace falta ser administrador)")
        }
        print("  Memoria virtual: imagen de hibernación \(i.sleepimage.map(b) ?? "no hay")\(i.hibernacion.map { " (hibernatemode \($0))" } ?? "") · swap \(b(i.swap))")
        if deVerdad { print("  Purgable: \(b(i.purgable)) (cuenta como usado hasta que macOS lo suelta)") }
        if let s = i.soloRoot, let v = i.visto {
            print("  Lo que solo ve root: \(b(s)) = usado \(b(i.usadoDatos)) − visto \(b(v)) − Papelera \(b(i.papelera)) − descriptores \(b(i.recursosIlegibles))\(i.cuentasBorradas.map { " − cuentas borradas \(b($0))" } ?? "")")
        } else {
            print("  Lo que solo ve root: no se sabe (\(!deVerdad ? "casa de prueba" : !i.accesoTotal ? "sin Acceso total al disco, lo que no veo incluye tus datos protegidos" : "hace falta el análisis y medir fuera de tu carpeta"))")
        }
        for o in i.ocultos { print("    \(o.protegida ? "protegido por macOS" : "con contraseña   ") \(o.ruta) — \(o.que)") }
        if !i.otrasCuentas.isEmpty {
            print("    otras cuentas de este Mac (no se pueden leer; cuentan en lo que solo ve root, pero no son de macOS): \(i.otrasCuentas.joined(separator: ", "))")
        }
        if let c = i.cuentasBorradas {
            print("  Cuentas borradas (/Users/Deleted Users): \(b(c)), aparte: no son de macOS (no cuentan en lo que reconocí)")
        }
        if !i.restos.isEmpty {
            print("  Restos del sistema que necesitan contraseña o un ajuste (la app nunca los ejecuta):")
            for r in i.restos {
                print("    \((r.bytes.map(b) ?? "sin medir").padding(toLength: 10, withPad: " ", startingAt: 0)) \(r.titulo)\(r.enMarcha ? " ⚡︎" : "")")
                print("         · \(r.detalle)")
                for l in (r.comando ?? "").split(separator: "\n") { print("         $ \(l)") }
            }
        }
        if i.hayMiniaturas {
            print("  Acción sin contraseña: «Vaciar las miniaturas del Finder» (\(i.miniaturas.map(b) ?? "sin medir")) → qlmanage -r cache")
        }
        print("  Tiempo: \(String(format: "%.1f", i.duracion)) s")
    }
}

/// El estado de «Datos del sistema» que ven VistaSistema y la tarjeta del resumen: se calcula en segundo plano al
/// terminar cada análisis (o al abrir la vista), y guarda lo que pasó con sus dos botones.
@MainActor
final class EstadoSistema: ObservableObject {
    static let compartido = EstadoSistema()

    @Published private(set) var informe: DatosDelSistema.Informe?
    @Published private(set) var midiendo = false
    /// Lo que midió root con «Medir con contraseña», de mayor a menor (nil hasta que se pida).
    @Published private(set) var medidaRoot: [DatosDelSistema.MedidaRoot]?
    @Published private(set) var midiendoRoot = false
    @Published private(set) var mensajeRoot: String?
    @Published private(set) var vaciandoMiniaturas = false
    @Published private(set) var mensajeMiniaturas: String?
    /// Lo que midió el último análisis (índice + fuera de tu carpeta) y la Papelera: se reutiliza al volver a medir,
    /// mientras siga valiendo (ver `vistoVigente`).
    private var visto: Int64?
    /// Ese análisis se hizo con Acceso total al disco (al empezar y al acabar): sin él, lo que no vio incluye tus datos.
    private var vistoConAcceso = false
    /// Cuándo terminó ese análisis.
    private var fechaVisto = Date.distantPast
    /// Cuántas veces se olvidó el `visto` porque algo cambió el disco o los permisos (limpiar, deshacer, vaciar la
    /// Papelera, el Acceso total…). Un análisis que empezó antes, o una medida que estaba en marcha, ya no valen.
    private(set) var olvidos = 0
    private var papelera: Int64 = 0
    /// Las apps que encontró el análisis fuera de Aplicaciones (como en Escaner): cuentan para los restos «sin app».
    private var appsExtra: [String] = []
    private var otraVez = false

    /// Lo que dura un `visto`: después, lo que cambió en el disco (descargas, apps…) se colaría en lo que solo ve root.
    static let vigencia: TimeInterval = 30 * 60

    /// Al terminar un análisis: guarda lo que midió (también nil, si falló MedidaFuera: así no se usa el de antes) y
    /// vuelve a medir. `olvidosAlEmpezar` es `olvidos` cuando empezó el análisis: si desde entonces se limpió algo, lo que
    /// midió ya no vale.
    func nuevoAnalisis(visto: Int64?, accesoTotal: Bool, olvidosAlEmpezar: Int, papelera: Int64, appsExtra: [String]) {
        self.visto = olvidosAlEmpezar == olvidos ? visto : nil
        vistoConAcceso = accesoTotal
        fechaVisto = Date()
        self.papelera = papelera
        self.appsExtra = appsExtra
        medir()
    }

    /// Algo cambió lo que midió el análisis (se limpió, se deshizo, se vació la Papelera, se descomprimió una app, cambió
    /// el Acceso total…): lo que solo ve root no se calcula hasta el próximo análisis. Vaciar las miniaturas y adelgazar
    /// las instantáneas no lo cambian: lo que liberan no estaba en lo visto (macOS no deja leerlo), así que lo que solo ve
    /// root baja justo eso.
    func olvidarVisto() {
        visto = nil
        olvidos += 1
    }

    /// El `visto` que vale ahora: el del último análisis, si se hizo con Acceso total, nada lo invalidó y es reciente.
    private var vistoVigente: Int64? {
        vistoConAcceso && Date().timeIntervalSince(fechaVisto) < Self.vigencia ? visto : nil
    }

    /// Vuelve a medir con lo que midió el último análisis (si aún vale) y esa Papelera (o la que se pase).
    func medir(papelera: Int64? = nil) {
        if let papelera { self.papelera = papelera }
        guard !midiendo else { otraVez = true; return }
        midiendo = true
        let (v, p, extra, olvidosAntes) = (vistoVigente, self.papelera, appsExtra, olvidos)
        Task.detached(priority: .utility) {
            let i = DatosDelSistema.medir(visto: v, papelera: p, appsExtra: extra)
            await MainActor.run {
                var informe = i
                // Si mientras medía se limpió algo (o cambió el Acceso total), lo que solo ve root ya no cuadra.
                if olvidosAntes != self.olvidos { informe.soloRoot = nil; informe.visto = nil }
                self.informe = informe
                self.midiendo = false
                if self.otraVez { self.otraVez = false; self.medir() }
            }
        }
    }

    /// Al abrir la vista sin haber medido aún: lo que se puede saber sin el análisis.
    func medirSiHaceFalta(papelera: Int64) {
        if informe == nil && !midiendo { medir(papelera: papelera) }
    }

    /// «Medir con contraseña»: un du de solo lectura como administrador (ver `DatosDelSistema.comandoRoot`).
    func medirConContrasena() {
        guard !midiendoRoot else { return }
        midiendoRoot = true
        mensajeRoot = nil
        Task.detached(priority: .userInitiated) {
            let r = DatosDelSistema.medirComoAdministrador()
            await MainActor.run {
                self.midiendoRoot = false
                if let r {
                    self.medidaRoot = r
                    self.mensajeRoot = r.isEmpty ? "No salió nada que medir." : nil
                } else {
                    self.mensajeRoot = "No se midió: cancelaste la contraseña o macOS no dejó ejecutarlo."
                }
            }
        }
    }

    /// «Vaciar las miniaturas del Finder»: qlmanage -r cache como tu usuario. Mide el disco antes y después.
    func vaciarMiniaturas() {
        guard !vaciandoMiniaturas else { return }
        vaciandoMiniaturas = true
        mensajeMiniaturas = nil
        Task.detached(priority: .userInitiated) {
            let antes = InfoDisco.libreAhora()
            let r = Shell.comando("/usr/bin/qlmanage", ["-r", "cache"], limite: 60)
            let despues = Medidor.estabilizar()
            let liberado = max(0, despues - antes)
            Historial.registrar(["miniaturas vaciadas\t\(liberado)\tqlmanage -r cache (estado \(r.estado))"])
            await MainActor.run {
                self.vaciandoMiniaturas = false
                self.mensajeMiniaturas = r.estado == 0
                    ? "Listo: el Finder rehará las miniaturas poco a poco. Se liberaron \(Formato.bytes(liberado)) (medido en el disco)."
                    : "qlmanage no pudo vaciarlas (estado \(r.estado))."
                self.medir()
            }
        }
    }
}
