import SwiftUI

// Lo que la interfaz dice de cada elemento y de lo encontrado: qué marca «Seleccionar lo recomendado», quién lo usa (y si
// se puede cerrar), por qué algo Seguro se queda fuera y cómo se reparte lo encontrado según lo que hace falta para
// liberarlo. Aquí no se marca ni se borra nada.

extension Elemento {
    /// Lo que «Seleccionar lo recomendado» marca ahora: Seguro (`marcable`), de nivel normal, sin ningún aviso y que nada
    /// usa en este momento.
    var recomendable: Bool { nivel == .normal && marcable && avisos.isEmpty && !abiertoAhora }

    /// Sería lo recomendado, pero ahora algo lo usa o cambió hace poco: se marca en cuanto se libere (al pulsar
    /// «Seleccionar lo recomendado» o «Comprobar otra vez»).
    var recomendadoEnEspera: Bool { nivel == .normal && marcable && soloAvisosDeUso && !recomendable }

    /// Cambió hace poco (regla 6 del Evaluador): espera a llevar 30 minutos quieto (`comprobarUso`).
    var esperaQuieto: Bool { motivos.contains { $0.icono == Evaluador.iconoReciente } }

    /// Lo usa un servicio de macOS sin ventana (geod, parsecd, el agente de los fondos…): no se cierra, ni hace falta.
    var usadoPorServicio: Bool {
        motivos.contains { Evaluador.iconosDeUso.contains($0.icono) && $0.etiqueta.hasSuffix(Evaluador.sufijoServicio) }
    }

    /// Al volver a mirar qué está en uso para volver a marcar (al terminar el análisis y con «Comprobar otra vez»): se marca
    /// si ahora es lo recomendado y, o no lo era antes de mirar (algo lo usaba o cambió hace poco), o el análisis no lo
    /// recomendó; nunca si ya está marcado, lo desmarcaste tú o no se ve. `antes` es como estaba antes de mirar. Es la
    /// regla de `Almacen.comprobarAppsAbiertas` y la de `--diagnostico` (`alTerminarAnalisis`).
    func vuelveAMarcarse(antes: Elemento, visible: Bool) -> Bool {
        !seleccionado && !desmarcadoAMano && visible && recomendable && (!antes.recomendable || !recomendado)
    }

    /// Lo que hace la app al terminar el análisis (`Almacen.comprobarAppsAbiertas(volverAMarcar: true)`), para que
    /// `--diagnostico` enseñe la selección con la que pulsarías «Limpiar»: vuelve a mirar el uso de cada elemento con la
    /// captura `p` (quita «Cambió hace poco» a lo que lleva 30 min quieto) y marca lo que `vuelveAMarcarse`. Sin una captura
    /// fiable no cambia nada, como en la app.
    static func alTerminarAnalisis(_ elementos: [Elemento], _ p: Procesos, visible: (Elemento) -> Bool) -> [Elemento] {
        guard p.fiable else { return elementos }
        return elementos.map { antes in
            var el = antes
            el.comprobarUso(p)
            if el.vuelveAMarcarse(antes: antes, visible: visible(el)) { el.seleccionado = true }
            return el
        }
    }
}

extension Procesos {
    /// Lo que coincide con esas claves (`quien`, como lo da `quienUsa`) es de macOS y no es una app que se cierre con ⌘Q:
    /// un servicio sin ventana. Si hay una app con ventana con ese nombre, o algo de lo que coincide es de una app que se
    /// puede cerrar, no lo es.
    func esServicioDeMacOS(_ claves: [String], quien: String) -> Bool {
        guard appsQueCierran(claves) == nil, !apps.contains(where: { $0.normal && $0.nombre == quien }) else { return false }
        if claves.contains(where: { $0.lowercased().hasPrefix("com.apple.") }) { return true }
        // Sin identificador de Apple: por dónde está el programa (lo de macOS va en /System, /usr —no /usr/local, que es de
        // Homebrew y otros— o /Library/Apple).
        let deMacOS = ["/System/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/", "/Library/Apple/"]
        let rutas = apps.filter { $0.nombre == quien }.compactMap { $0.url?.path } + programas.filter { $0.visible == quien }.map(\.ruta)
        return !rutas.isEmpty && rutas.allSatisfy { r in deMacOS.contains { r.hasPrefix($0) } }
    }

    /// `quien` es una app (Safari, Música…) que no está abierta, pero algún ayudante suyo sí: un programa que se ejecuta
    /// desde dentro de ella. Las de /System/Library (Siri, el agente de los fondos…) son servicios, no apps que se abran.
    func esDeUnaApp(_ quien: String) -> Bool {
        programas.contains { $0.visible == quien && $0.ruta.contains("/\(quien).app/") && !$0.ruta.hasPrefix("/System/Library/") }
    }

    /// Los nombres de las apps con ventana que están abiertas con esos identificadores (los de `appsQueCierran`).
    func nombresDeApps(_ ids: Set<String>) -> [String] {
        ids.compactMap { id in apps.first { $0.bundleID == id && $0.normal }?.nombre }.sorted()
    }

    /// Para lo que Limpiador se salta porque algo lo usa: quién (con su número de proceso, si se sabe) y qué ruta, y qué
    /// hacer. Sin el nombre del elemento delante. nil si nada lo usa.
    func porQueSeSalta(_ el: Elemento) -> String? {
        let donde = Formato.rutaCorta(el.rutaPrincipal) + (el.rutas.count > 1 ? " (y \(el.rutas.count - 1) \(el.rutas.count == 2 ? "ruta más" : "rutas más"))" : "")
        func numero(_ pid: pid_t?) -> String { pid.map { " (proceso \($0))" } ?? "" }
        if let uso = el.enUso, let quien = quienUsa(uso) {
            let pid = apps.first { $0.nombre == quien }?.pid ?? programas.first { $0.visible == quien }?.pid
            switch uso {
            case .app(_, let claves):
                if let ids = appsQueCierran(claves) {
                    // Un ayudante (ServiceExtension, de WhatsApp): lo que hay que cerrar es la app que lo contiene.
                    let nombres = nombresDeApps(ids)
                    guard !nombres.isEmpty, nombres != [quien] else {
                        return "\(quien)\(numero(pid)) estaba abierta y \(donde) es suyo. Ciérrala y vuelve a limpiar."
                    }
                    return "\(quien)\(numero(pid)), de \(Formato.lista(nombres)), estaba funcionando y \(donde) es suyo. Cierra \(Formato.lista(nombres)) y vuelve a limpiar."
                }
                if apps.contains(where: { $0.normal && $0.nombre == quien }) {
                    return "\(quien)\(numero(pid)) estaba abierta (o algo suyo que no se cierra con ella) y \(donde) es suyo. Ciérrala y vuelve a limpiar."
                }
                if esServicioDeMacOS(claves, quien: quien) {
                    return "lo usa \(quien)\(numero(pid)), un servicio de macOS que siempre está en marcha, y \(donde) es suyo, así que no lo toqué. No hace falta que lo cierres."
                }
                return "\(quien)\(numero(pid)) estaba funcionando en segundo plano, sin ventana, y \(donde) es suyo. Cuando termine, vuelve a limpiar."
            case .rutas(_, let raiz), .proyecto(_, let raiz), .carpetaTemporal(_, let raiz), .appInstalada(_, _, let raiz):
                // El que se ejecuta desde ahí o, si no, el que tiene algo abierto dentro.
                let quienDentro = programas.first { $0.visible == quien && ($0.ruta == raiz || $0.ruta.hasPrefix(raiz + "/")) }?.pid
                    ?? abiertos.proceso(dentroDe: raiz) ?? pid
                return "\(quien)\(numero(quienDentro)) estaba usando \(Formato.rutaCorta(raiz)) (se ejecuta desde ahí, tiene archivos abiertos dentro o trabaja en esa carpeta). Ciérralo y vuelve a limpiar."
            case .proceso(let nombre, let patron):
                let i = lineas.firstIndex { $0.contains(patron) }
                let suyo = i.flatMap { $0 < pidsDeLineas.count ? pidsDeLineas[$0] : nil }
                return "\(nombre)\(numero(suyo)) se estaba ejecutando y puede necesitar \(donde). Ciérralo y vuelve a limpiar."
            case .programas(_, let ejecutables):
                let buscados = Set(ejecutables.map { $0.lowercased() })
                let programa = programas.first { buscados.contains(Rutas.nombre($0.ruta).lowercased()) }
                let cual = programa.map { " (proceso \($0.pid): \(Formato.rutaCorta($0.ruta)))" } ?? ""
                return "\(quien)\(cual) estaba en marcha y puede necesitar \(donde). Espera a que termine y vuelve a limpiar."
            case .gradle, .gradleVersion:
                return "\(quien) estaba trabajando (un daemon de Gradle, Android Studio o una compilación) y puede necesitar \(donde). Ciérralo y vuelve a limpiar."
            case .emulador, .simulador:
                return "\(quien) estaba encendido. Apágalo y vuelve a limpiar."
            }
        }
        // Los archivos quietos de la caché de un servicio que ahora usa una app con ventana (`Elemento.sinVentana`).
        for s in el.sinVentana {
            guard let quien = conVentana(s) else { continue }
            let cache = s.raices.first.map { Formato.rutaCorta($0) } ?? donde
            return "\(quien) estaba abierta y usa la caché de estos archivos (\(cache)). Ciérrala y vuelve a limpiar."
        }
        guard let u = el.rutasVigiladas.first(where: { abiertos.hayAbierto(dentroDe: $0.path) != nil }),
              let quien = abiertos.hayAbierto(dentroDe: u.path) else { return nil }
        return "\(quien)\(numero(abiertos.proceso(dentroDe: u.path))) tenía abierto algo de \(Formato.rutaCorta(u)). Ciérralo y vuelve a limpiar."
    }
}

extension CierreDeApps {
    /// Las apps que se ofrece cerrar con «Cerrar y limpiar», sin lo que cambió hace poco (regla 6 del Evaluador): si la
    /// app lo toca antes de cerrarse, Limpiador se lo saltaría igual (`cambioAnalizado`). Entra en cuanto lleve 30 minutos
    /// quieto.
    static func bloqueosAhora(_ elementos: [Elemento], _ p: Procesos) -> [BloqueoDeApp] {
        bloqueos(elementos.filter { !$0.esperaQuieto }, p)
    }
}

extension PlanMaximo {
    /// Por qué algo Seguro se queda fuera de «Liberar al máximo», con la razón de verdad. Lo que quien lo encontró no marca
    /// solo sigue fuera aunque nada lo use: eso se dice antes que «en uso». La razón que da quien lo encontró va en su
    /// última nota (sin las del Evaluador sobre clones y bases de datos, que no lo son).
    static func porQueFuera(_ el: Elemento) -> String {
        if el.desmarcadoAMano { return "Lo desmarcaste tú" }
        let quien = el.usadoPor ?? el.dueno ?? "un programa"
        let notasDelEvaluador: Set<String> = ["square.on.square.dashed", "cylinder.split.1x2.fill"]
        let nota = el.motivos.last { $0.nivel == .info && !notasDelEvaluador.contains($0.icono) }?.etiqueta
        if !el.marcable {
            let razon = el.avisos.first { !Evaluador.iconosDeUso.contains($0.icono) }?.etiqueta ?? nota
            let uso = el.abiertoAhora ? " (y ahora lo usa \(quien))" : ""
            return razon.map { "No lo marco solo: \($0)\(uso)" } ?? "No lo marco solo: míralo y márcalo tú si lo quieres\(uso)"
        }
        if el.abiertoAhora && el.usadoPorServicio { return "Lo usa un servicio de macOS que no se cierra (\(quien))" }
        if el.esperaQuieto {
            return "Cambió hace poco: espero a que lleve 30 min quieto" + (el.abiertoAhora ? " (y lo usa \(quien))" : "")
        }
        if el.abiertoAhora { return "En uso por \(quien)" }
        if let aviso = el.avisos.first { return aviso.etiqueta }
        if el.accion == .vaciarPapelera { return "La Papelera se vacía aparte: con «Limpiar» o con su botón" }
        if el.nivel > .maximo { return "No se marca solo en ningún modo" + (nota.map { ": \($0)" } ?? "") }
        return nota ?? "Seguro, pero ahora no se marca"
    }
}

/// Lo encontrado, repartido según lo que hace falta para liberarlo, de lo más fácil a lo que nunca marco solo. Cada parte
/// suma lo que añade a las anteriores (sin contar dos veces lo que está dentro de algo ya contado), así que juntas dan lo
/// encontrado.
struct RepartoEncontrado: Equatable {
    /// Lo recomendado: lo que marca «Seleccionar lo recomendado» (Seguro, nivel normal, sin avisos y que nada usa ahora),
    /// menos lo que desmarcaste tú (que va a `fuera`, como en «Liberar al máximo»).
    var ya: Int64 = 0
    /// Lo que añade «Liberar al máximo» sin cerrar nada: comprimir, unir copias y lo que cuesta volver a descargar o
    /// recompilar.
    var maximo: Int64 = 0
    /// Lo Seguro que bloquea una app abierta con ventana: se libera con «Cerrar y limpiar».
    var cerrandoApps: Int64 = 0
    /// Lo Seguro que hoy se queda fuera: lo usa un servicio de macOS o un programa, cambió hace poco, quien lo encontró no
    /// lo marca solo o lo desmarcaste tú.
    var fuera: Int64 = 0
    var revisar: Int64 = 0
    /// Cuidado: normalmente datos tuyos.
    var cuidado: Int64 = 0
    /// De lo recomendado, lo que ahora espera (`recomendadoEnEspera`): para la ayuda de «Seleccionar lo recomendado».
    var enEspera: Int64 = 0
    /// De eso, lo que bloquea una app abierta con ventana (está en `bloqueos`): se libera cerrándola o con «Cerrar y
    /// limpiar».
    var enEsperaApps: Int64 = 0
    /// El resto de lo que espera: lo usa un servicio de macOS, un programa sin ventana o varias apps, o cambió hace poco.
    /// Cerrar una app o «Cerrar y limpiar» no lo libera.
    var enEsperaOtros: Int64 { max(0, enEspera - enEsperaApps) }

    var total: Int64 { ya + maximo + cerrandoApps + fuera + revisar + cuidado }

    /// Para la ayuda de «Seleccionar lo recomendado»: lo recomendado que se queda fuera porque espera, y qué hacer con cada
    /// parte (vacío si nada espera).
    var ayudaEnEspera: String {
        var r = ""
        if enEsperaApps > 0 {
            r += " Lo que usan apps abiertas ahora (\(Formato.bytes(enEsperaApps))) se queda fuera: ciérralas y vuelve a pulsar, o usa «Liberar al máximo › Cerrar y limpiar»."
        }
        if enEsperaOtros > 0 {
            r += (enEsperaApps > 0 ? " Otros \(Formato.bytes(enEsperaOtros)) no se liberan así" : " Lo recomendado que espera ahora (\(Formato.bytes(enEsperaOtros))) no se libera cerrando apps ni con «Cerrar y limpiar»")
                + ": lo usa un servicio de macOS (no hace falta cerrarlo), un programa sin ventana o varias apps, o cambió hace poco y espero a que lleve 30 min quieto. Vuelve a pulsar más tarde."
        }
        return r
    }

    static func calcular(_ elementos: [Elemento], bloqueos: [BloqueoDeApp]) -> RepartoEncontrado {
        let plan = PlanMaximo.calcular(elementos, bloqueos: bloqueos)
        let enPlan = Set((plan.regenera + plan.sinBorrar + plan.cuesta).map(\.id))
        let bloqueados = Set(bloqueos.flatMap(\.elementos))
        var capas = [[Elemento]](repeating: [], count: 6)
        for el in elementos {
            // Lo recomendado que desmarcaste tú no se libera con «Limpiar»: cae en «Seguro, pero hoy no» (PlanMaximo lo
            // deja en `fuera` con «Lo desmarcaste tú»).
            let capa = el.recomendable && !el.desmarcadoAMano ? 0
                : enPlan.contains(el.id) ? 1
                : bloqueados.contains(el.id) ? 2
                : el.riesgo == .seguro ? 3
                : el.riesgo == .revisar ? 4 : 5
            capas[capa].append(el)
        }
        // Por capas, en orden: cada una suma lo que añade a las anteriores.
        var juntas: [Elemento] = []
        var antes: Int64 = 0
        var partes: [Int64] = []
        for capa in capas {
            juntas += capa
            let ahora = capa.isEmpty ? antes : Totales.sumaSinRepetir(juntas)
            partes.append(max(0, ahora - antes))
            antes = max(antes, ahora)
        }
        let esperan = elementos.filter { $0.recomendadoEnEspera && !$0.desmarcadoAMano }
        return RepartoEncontrado(ya: partes[0], maximo: partes[1], cerrandoApps: partes[2], fuera: partes[3],
                                 revisar: partes[4], cuidado: partes[5],
                                 enEspera: Totales.sumaSinRepetir(esperan),
                                 enEsperaApps: Totales.sumaSinRepetir(esperan.filter { bloqueados.contains($0.id) }))
    }

    /// Para `--diagnostico`: el reparto como lo ve el resumen al terminar el análisis. `todos` ya lleva el uso mirado con
    /// la captura `p` (`Elemento.alTerminarAnalisis`), la misma que el resto del diagnóstico.
    static func lineaDeDiagnostico(_ todos: [Elemento], _ p: Procesos) -> String {
        let r = calcular(todos, bloqueos: p.fiable ? CierreDeApps.bloqueosAhora(todos, p) : [])
        return "Reparto: se libera ya \(Formato.bytes(r.ya)) · con «Liberar al máximo» +\(Formato.bytes(r.maximo)) · cerrando apps («Cerrar y limpiar») +\(Formato.bytes(r.cerrandoApps)) · Seguro que hoy se queda fuera \(Formato.bytes(r.fuera)) · Revisar \(Formato.bytes(r.revisar)) · Cuidado \(Formato.bytes(r.cuidado)) (suma \(Formato.bytes(r.total)); lo recomendado que espera a que nada lo use: \(Formato.bytes(r.enEspera)): cerrando apps \(Formato.bytes(r.enEsperaApps)), servicios de macOS, programas sin ventana o cambios recientes \(Formato.bytes(r.enEsperaOtros)))\(p.fiable ? "" : " · NO se pudo ver qué está en uso")"
    }

    /// Las partes que se enseñan, en orden (sin las vacías).
    struct Parte: Identifiable {
        var id: String { titulo }
        let titulo: String
        let bytes: Int64
        let color: Color
        let ayuda: String
    }

    @MainActor var partes: [Parte] {
        [Parte(titulo: "Se libera ya", bytes: ya, color: .green,
               ayuda: "Lo recomendado: Seguro, se regenera y nada lo usa ahora, menos lo que desmarcaste tú. Es lo que marca «Seleccionar lo recomendado»."),
         Parte(titulo: "Con «Liberar al máximo»", bytes: maximo, color: .teal,
               ayuda: "Seguro, pero cuesta algo (volver a descargar, recompilar) o no borra nada (comprimir, unir copias). «Liberar al máximo» te dice lo que cuesta antes de hacerlo."),
         Parte(titulo: "Cerrando apps", bytes: cerrandoApps, color: .indigo,
               ayuda: "Lo Seguro que usan apps que tienes abiertas (cachés, bases que se compactan). Se libera con «Liberar al máximo › Cerrar y limpiar», app por app, o cerrándolas tú: lo que se regenera lo marca entonces «Seleccionar lo recomendado»; lo de Modo máximo (compactar bases, cachés que cuesta volver a llenar), solo «Liberar al máximo»."),
         Parte(titulo: "Seguro, pero hoy no", bytes: fuera, color: .gray,
               ayuda: "Es Seguro, pero hoy no lo marco: lo usa un servicio de macOS o un programa, cambió hace poco, no lo marco solo o lo desmarcaste tú. En «Liberar al máximo › Se queda fuera por ahora» está la razón de cada uno."),
         Parte(titulo: "Revisar", bytes: revisar, color: EtiquetaRiesgo.color(.revisar),
               ayuda: "Probablemente no lo necesitas, pero confírmalo antes. Nunca lo marco solo."),
         Parte(titulo: "Tus datos (Cuidado)", bytes: cuidado, color: EtiquetaRiesgo.color(.cuidado),
               ayuda: "Puede contener datos que quieras conservar (historiales, configuración, tus archivos). Nunca lo marco solo.")]
            .filter { $0.bytes > 0 }
    }
}

/// En el resumen, bajo «Lo que encontré»: cuánto de lo encontrado se libera ya, cuánto con «Liberar al máximo», cuánto
/// cerrando apps, lo Seguro que hoy se queda fuera, lo que conviene revisar y tus datos. Una barra y sus cifras.
struct TarjetaReparto: View {
    @EnvironmentObject var almacen: Almacen

    var body: some View {
        let r = almacen.reparto
        let partes = r.partes
        if r.total > 0 {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(partes) { p in
                            Rectangle().fill(p.color.gradient)
                                .frame(width: max(2, (g.size.width - CGFloat(partes.count - 1) * 2) * CGFloat(p.bytes) / CGFloat(r.total)))
                                .help("\(p.titulo): \(Formato.bytes(p.bytes))")
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(partes) { p in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle().fill(p.color).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Formato.bytes(p.bytes)).font(.callout.weight(.semibold).monospacedDigit())
                                Text(p.titulo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .help(p.ayuda)
                    }
                }
                Text("Solo marco solo lo que se libera ya. Lo demás te lo enseño para que decidas; Revisar y Cuidado nunca los marco solo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
