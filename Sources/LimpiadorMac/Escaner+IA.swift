import Foundation

// Herramientas de IA de la terminal, Node y Python: agentes que se instalaron y nunca se configuraron (Cline con npm,
// Cursor Agent), programas que su instalador descargó y nunca se ejecutaron (muse), versiones anteriores de Claude Code
// con su instalador nativo (son archivos, no carpetas), los puntos de control de Claude Code que ya no sirven, las
// dependencias de plugins de opencode y la caché de gramáticas de OpenTUI, Node instalados a mano que nadie usa y, solo
// como nota, Ollama sin ningún modelo. (Los paquetes de pip --user con su Python instalado no: ver más abajo.)
//
// Sobre las fechas de lectura (atime): macOS (APFS) solo anota una lectura si la fecha de lectura que tiene el archivo es
// anterior a la de su última escritura; es decir, la primera lectura después de escribirlo, y ninguna más. Una lectura
// anotada demuestra un uso, pero no dice cuándo fue el último. Lo único seguro: si la lectura anotada es anterior a la
// escritura, nadie lo ha leído (ni ejecutado) desde entonces. Por eso aquí la señal fuerte es la que falta (ninguna
// configuración ni sesión, sus datos sin cambios), y la fecha de lectura solo la refuerza. Las lecturas de la propia app
// no se anotan (`noAnotarLecturasPropias`). En un disco montado con «noatime» no se anota ninguna: esas reglas no se
// aplican.

extension Escaner {

    // MARK: - Ganchos de generar()

    /// Lo que se añade a «Cachés de desarrollo». Deja también, como nota, Ollama instalado sin ningún modelo.
    func desarrolloDeIA(_ c: Contexto) -> [Elemento] {
        notaDeOllamaSinModelos(c)
        return agentesDeNpmSinConfigurar(c) + cursorAgentSinSesion(c) + programasSinEstrenar(c) + versionesDeClaudeCodeNativo(c)
            + nodesSinUsar(c) + restosDeAntigravityYOpencode(c)
    }

    /// Lo que se añade a «Carpetas ocultas».
    func herramientasDeIA(_ c: Contexto) -> [Elemento] {
        puntosDeControlDeClaude(c) + dependenciasDePluginsDeOpencode(c) + cacheDeOpenTUI(c)
    }

    // MARK: - Temporales de Antigravity/Gemini y snapshots de OpenCode

    /// Entornos temporales (.venv, node_modules) dentro de ~/.gemini/antigravity/brain/*/scratch y tempmediaStorage,
    /// más los snapshots git internos de ~/.local/share/opencode/snapshot. Nunca toca conversaciones ni artefactos.
    private func restosDeAntigravityYOpencode(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let brain = Rutas.enHome(".gemini/antigravity/brain")
        if Self.iaTipo(brain.path) == S_IFDIR {
            var rutas: [URL] = []
            for conv in Self.iaNombres(en: brain.path) where !conv.hasPrefix(".") {
                if conv == "tempmediaStorage" {
                    let u = brain.appendingPathComponent(conv)
                    if Self.iaTipo(u.path) == S_IFDIR,
                       let cam = Self.ultimoCambioDentro(u.path, c),
                       Date().timeIntervalSince(cam) >= 86400 {
                        rutas.append(u)
                    }
                    continue
                }
                let scratch = brain.appendingPathComponent(conv + "/scratch")
                guard Self.iaTipo(scratch.path) == S_IFDIR else { continue }
                for nombre in [".venv", "venv", "node_modules"] {
                    let u = scratch.appendingPathComponent(nombre)
                    if Self.iaTipo(u.path) == S_IFDIR { rutas.append(u) }
                }
            }
            let tamanos = rutas.map { Self.medida($0.path, c) }
            if tamanos.reduce(0, +) >= minimo {
                r.append(Elemento(
                    nombre: "Entornos temporales de Antigravity/Gemini",
                    detalle: "Entornos virtuales (.venv/node_modules) dentro de carpetas scratch o archivos en tempmediaStorage de sesiones anteriores de Antigravity.",
                    consecuencia: "Tus conversaciones, planes e informes de Antigravity no se tocan: solo se borran entornos temporales en scratch/ y medios temporales.",
                    rutas: rutas, tamanosRutas: tamanos,
                    ultimoUso: rutas.compactMap { Self.ultimoCambioDentro($0.path, c) }.max(),
                    categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                    motivos: [.info("sparkles", "Temporales de sesiones",
                                    "Solo entornos descargados en scratch/ y tempmediaStorage; las bases de conversaciones no se tocan. Entra en «Liberar al máximo».")],
                    enUso: .app(nombre: "Antigravity", claves: ["com.google.antigravity", "Antigravity"]), dueno: "Antigravity",
                    nivel: .maximo, costes: [.descarga(bytes: tamanos.reduce(0, +))]))
            }
        }

        let snap = Rutas.enHome(".local/share/opencode/snapshot")
        if Self.iaTipo(snap.path) == S_IFDIR {
            let tam = Self.medida(snap.path, c)
            if tam >= minimo {
                r.append(Elemento(
                    nombre: "Snapshots internos de OpenCode",
                    detalle: "Instantáneas git automáticas que OpenCode guarda en ~/.local/share/opencode/snapshot para deshacer cambios en sesiones pasadas.",
                    consecuencia: "Pierdes los puntos de restauración antiguos de OpenCode, pero tu base de conversaciones (opencode.db) y tu configuración siguen intactas. Va a la Papelera.",
                    rutas: [snap], tamanosRutas: [tam],
                    ultimoUso: Self.ultimoCambioDentro(snap.path, c),
                    categoria: .desarrollo, riesgo: .revisar,
                    motivos: [.info("clock.arrow.circlepath", "Instantáneas de sesiones",
                                    "Copias internas de estado para deshacer ediciones en OpenCode. Ciérralo antes de limpiar.")],
                    enUso: .programas(nombre: "opencode", ejecutables: ["opencode"]), dueno: "opencode"))
            }
        }
        return r
    }

    // MARK: - Utilidades de estas reglas

    private static func iaStat(_ ruta: String) -> stat? {
        var st = stat()
        return lstat(ruta, &st) == 0 ? st : nil
    }

    /// Qué hay en esa ruta (S_IFDIR, S_IFREG, S_IFLNK…), sin seguir enlaces. nil si no existe.
    private static func iaTipo(_ ruta: String) -> mode_t? { iaStat(ruta).map { $0.st_mode & S_IFMT } }

    private static func iaNombres(en carpeta: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? []).sorted()
    }

    private static func iaFecha(_ segundos: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(segundos)) }

    private static func iaDias(desde segundos: Int) -> Double { (Date().timeIntervalSince1970 - Double(segundos)) / 86400 }

    /// Cuándo llegó a este disco: su fecha de creación, o la de modificación si es más nueva (una carpeta que se rehízo).
    private static func iaLlegada(_ st: stat) -> Int { max(Int(st.st_birthtimespec.tv_sec), Int(st.st_mtimespec.tv_sec)) }

    /// No se ha leído (ni ejecutado) desde su última escritura: su fecha de lectura es anterior. La primera lectura
    /// después de escribirlo la habría anotado. (Con las dos fechas iguales no se sabe: macOS ya no anotaría ninguna.)
    private static func iaSinLeerDesdeQueSeEscribio(_ st: stat) -> Bool {
        let a = st.st_atimespec, m = st.st_mtimespec
        return a.tv_sec < m.tv_sec || (a.tv_sec == m.tv_sec && a.tv_nsec < m.tv_nsec)
    }

    /// La lectura que anotó macOS (la primera después de escribirlo), o nil si no anotó ninguna desde entonces.
    private static func iaLecturaAnotada(_ st: stat) -> Int? {
        iaSinLeerDesdeQueSeEscribio(st) ? nil : Int(st.st_atimespec.tv_sec)
    }

    /// Que las lecturas de la propia app (las muestras que lee el Compresor, las huellas de los duplicados, la
    /// configuración de las herramientas) no cuenten como un uso: macOS anotaría la primera y borraría la señal de que
    /// nadie lo había abierto, para esta regla y para «Sin uso». Vale para todo el proceso, y la heredan los programas que
    /// lanza la app (du, ditto, sqlite3, git, npm, brew…) y lo que estos lancen: en lo que termina enseguida es lo que se
    /// busca. Lo que puede dejar algo vivo (el zsh de la terminal) nace sin ella: `lanzarAnotandoLecturas`.
    static func noAnotarLecturasPropias() {
        politicaDeLecturas.lock(); defer { politicaDeLecturas.unlock() }
        _ = setiopolicy_np(IOPOL_TYPE_VFS_ATIME_UPDATES, IOPOL_SCOPE_PROCESS, IOPOL_ATIME_UPDATES_OFF)
    }

    /// Los cambios de esa política, de uno en uno: si no, un análisis que la pone mientras otro hilo la quita para lanzar
    /// algo podría quedarse sin ella.
    private static let politicaDeLecturas = NSLock()

    /// `lanzar` hace nacer un programa (solo eso: no lo espera) con las lecturas anotadas como siempre. El hijo se lleva
    /// una copia de la política al nacer y la deja a todo lo que lance, también a lo que siga vivo después: un
    /// `ollama serve &`, tmux o un daemon que arranque el .zshrc ya no anotaría ninguna lectura hasta reiniciar, y las
    /// reglas que se fían de ellas darían por no usado lo que se usa allí. Se quita solo mientras nace y se vuelve a poner.
    static func lanzarAnotandoLecturas(_ lanzar: () throws -> Void) rethrows {
        politicaDeLecturas.lock(); defer { politicaDeLecturas.unlock() }
        guard getiopolicy_np(IOPOL_TYPE_VFS_ATIME_UPDATES, IOPOL_SCOPE_PROCESS) == IOPOL_ATIME_UPDATES_OFF else { return try lanzar() }
        _ = setiopolicy_np(IOPOL_TYPE_VFS_ATIME_UPDATES, IOPOL_SCOPE_PROCESS, IOPOL_ATIME_UPDATES_DEFAULT)
        defer { _ = setiopolicy_np(IOPOL_TYPE_VFS_ATIME_UPDATES, IOPOL_SCOPE_PROCESS, IOPOL_ATIME_UPDATES_OFF) }
        try lanzar()
    }

    /// El disco donde está la ruta anota las lecturas (no está montado con «noatime»).
    private static func iaAnotaLecturas(_ ruta: String) -> Bool {
        var s = statfs()
        guard statfs(ruta, &s) == 0 else { return false }
        return (s.f_flags & UInt32(MNT_NOATIME)) == 0
    }

    /// La ruta está dentro de tu carpeta y sin ningún enlace por medio (ni ella ni las carpetas de encima): lo que se
    /// borraría es exactamente lo que se ve, no lo que hay al otro lado de un enlace (tus documentos, otra carpeta).
    private static func iaSinEnlaces(_ ruta: String) -> Bool {
        let casa = Rutas.home.path
        guard ruta.hasPrefix(casa + "/") else { return false }
        return Rutas.real(URL(fileURLWithPath: ruta)) == Rutas.real(Rutas.home) + String(ruta.dropFirst(casa.count))
    }

    /// Si un repositorio git que conoce el índice la contiene (tus dotfiles con git, por ejemplo).
    private static func iaEnRepo(_ ruta: String, _ c: Contexto) -> Bool {
        var actual = ruta
        let casa = Rutas.home.path
        while actual.count > casa.count {
            if c.indice.repos.contains(actual) { return true }
            actual = Rutas.padre(actual)
        }
        return false
    }

    /// El programa que abre la terminal al escribir ese comando (su ruta real): el primero del PATH que se puede ejecutar.
    private static func iaPrimeroEnElPath(_ comando: String, _ c: Contexto) -> String? {
        for d in c.apps.pathTerminal {
            let ruta = d + "/" + comando
            let real = Rutas.real(URL(fileURLWithPath: ruta))
            if access(ruta, X_OK) == 0 && iaTipo(real) == S_IFREG { return real }
        }
        return nil
    }

    /// Lo último que cambió dentro de una ruta (lo que anotó el índice o, si es pequeña, recorriéndola).
    private static func iaUltimoCambio(_ ruta: String, _ c: Contexto) -> Int {
        if let i = c.indice.info(ruta), i.masReciente > 0 { return i.masReciente }
        return Fechas.ultimoCambio([ruta])
    }

    private static let patronVersionIA = try! NSRegularExpression(pattern: #"^v?\d+\.\d+(\.\d+)*([-+._][0-9A-Za-z.]+)*$"#)

    private static func iaPareceVersion(_ n: String) -> Bool {
        patronVersionIA.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil
    }

    /// Los enlaces de las carpetas de comandos de tu carpeta (~/.local/bin, ~/bin y las del PATH que están en tu carpeta)
    /// que llevan a algo de dentro de `raiz`: se van con ella (si no, quedarían rotos).
    private static func iaEnlacesHacia(_ raiz: String, _ c: Contexto) -> [String] {
        let real = Rutas.real(URL(fileURLWithPath: raiz))
        var carpetas: [String] = []
        for d in [".local/bin", "bin"].map({ Rutas.enHome($0).path }) + c.apps.pathEnCasa where !carpetas.contains(d) { carpetas.append(d) }
        var r: [String] = []
        for d in carpetas where iaSinEnlaces(d) {
            for n in iaNombres(en: d) where iaTipo(d + "/" + n) == S_IFLNK && !r.contains(d + "/" + n) {
                let destino = Rutas.real(URL(fileURLWithPath: d + "/" + n))
                if destino == real || destino.hasPrefix(real + "/") { r.append(d + "/" + n) }
            }
        }
        return r
    }

    /// «a, b ni c».
    private static func iaListaNi(_ partes: [String]) -> String {
        guard let ultima = partes.last, partes.count > 1 else { return partes.first ?? "" }
        return partes.dropLast().joined(separator: ", ") + " ni " + ultima
    }

    // MARK: - Agentes de IA de npm que nunca se configuraron

    /// Agentes de IA para la terminal que se instalan con «npm install -g», con las carpetas donde guardan su
    /// configuración, su sesión y sus tareas desde la primera vez que se usan de verdad.
    private static let agentesDeNpm: [(paquete: String, nombre: String, datos: [String])] = [
        ("cline", "Cline", [".cline", "Documents/Cline"]), ("@google/gemini-cli", "Gemini CLI", [".gemini"]),
        ("@qwen-code/qwen-code", "Qwen Code", [".qwen"]), ("@anthropic-ai/claude-code", "Claude Code", [".claude", ".claude.json"]),
        ("@openai/codex", "Codex", [".codex"]), ("opencode-ai", "opencode", [".opencode", ".local/share/opencode", ".config/opencode"]),
        ("@sourcegraph/amp", "Amp", [".amp", ".config/amp", ".local/share/amp"]), ("@kilocode/cli", "Kilo Code", [".kilocode"]),
        ("@augmentcode/auggie", "Auggie", [".augment"]), ("@github/copilot", "GitHub Copilot CLI", [".copilot"]),
        ("@charmland/crush", "Crush", [".config/crush", ".local/share/crush"]), ("@vibe-kit/grok-cli", "Grok CLI", [".grok"]),
        ("@iflow-ai/iflow-cli", "iFlow CLI", [".iflow"]), ("@continuedev/cli", "Continue CLI", [".continue"]),
        ("@factory/cli", "Factory", [".factory"]), ("@letta-ai/letta-code", "Letta Code", [".letta"]),
        ("codebuff", "Codebuff", [".config/manicode"]), ("freebuff", "Freebuff", [".config/manicode"]),
    ]

    /// Dónde instala «npm install -g»: el Node de Homebrew, los de nvm, fnm y ~/.local/runtime, y los prefijos habituales
    /// que se configuran a mano (~/.npm-global…).
    private static func iaPrefijosDeNpm() -> [String] {
        var r = Rutas.homebrew
        for (base, sub) in [(".nvm/versions/node", ""), (".local/runtime", ""), (".local/share/fnm/node-versions", "/installation"),
                            ("Library/Application Support/fnm/node-versions", "/installation")] {
            let d = Rutas.enHome(base).path
            r += iaNombres(en: d).filter { !$0.hasPrefix(".") }.map { d + "/" + $0 + sub }
        }
        r += [".npm-global", ".npm-packages", ".local"].map { Rutas.enHome($0).path }
        return r.filter { iaTipo($0 + "/lib/node_modules") == S_IFDIR }
    }

    /// «…/lib/node_modules/cline/bin/cline» → «…/lib/node_modules/cline».
    private static func iaPaqueteNpm(de ruta: String) -> String? {
        guard let r = ruta.range(of: "/lib/node_modules/", options: .backwards) else { return nil }
        let partes = ruta[r.upperBound...].split(separator: "/")
        guard let primera = partes.first else { return nil }
        let paquete = primera.hasPrefix("@") && partes.count > 1 ? "\(primera)/\(partes[1])" : String(primera)
        return String(ruta[..<r.upperBound]) + paquete
    }

    /// Si un programa guarda algo con ese nombre en tu carpeta (configuración, sesiones, cachés).
    private static func iaTieneDatos(_ n: String) -> Bool {
        let n = n.hasPrefix(".") ? String(n.dropFirst()) : n
        guard !n.isEmpty else { return true }
        return [".\(n)", ".config/\(n)", ".local/share/\(n)", ".local/state/\(n)", ".cache/\(n)", "Library/Application Support/\(n)",
                ".config/configstore/\(n).json"].contains { Rutas.existe(Rutas.enHome($0)) }
    }

    /// Los programas nativos que trae un paquete de npm (el de Cline pesa 90 MB): los archivos de 1 MB o más de su bin/ y de
    /// los bin/ de sus paquetes por plataforma («node_modules/@cline/cli-darwin-arm64/bin/cline»).
    private static func iaBinariosNativos(en paquete: String) -> [String] {
        var bins = [paquete + "/bin"]
        let modulos = paquete + "/node_modules"
        for n in iaNombres(en: modulos) where !n.hasPrefix(".") {
            if n.hasPrefix("@") { bins += iaNombres(en: modulos + "/" + n).map { modulos + "/" + n + "/" + $0 + "/bin" } }
            else { bins.append(modulos + "/" + n + "/bin") }
        }
        return bins.flatMap { b in
            iaNombres(en: b).map { b + "/" + $0 }.filter { f in
                guard let st = iaStat(f), (st.st_mode & S_IFMT) == S_IFREG else { return false }
                return st.st_size >= 1_000_000
            }
        }
    }

    /// Agentes de IA instalados con «npm install -g» hace 21 días o más que nunca guardaron nada (ni su carpeta de
    /// configuración ni las de sus comandos) y cuyos programas (también el binario nativo que traen) solo se ejecutaron,
    /// si acaso, el día que se instalaron. Revisar. A los 60 días los ofrece también `paquetesGlobalesDeNpm` (entonces
    /// este no se repite).
    func agentesDeNpmSinConfigurar(_ c: Contexto) -> [Elemento] {
        let home = Rutas.real(Rutas.home) + "/"
        let ahora = Int(Date().timeIntervalSince1970)
        let conocidos = Dictionary(uniqueKeysWithValues: Self.agentesDeNpm.map { ($0.paquete, $0) })
        let path = c.apps.pathTerminal.map { Rutas.real(URL(fileURLWithPath: $0)) }
        var r: [Elemento] = []
        for prefijo in Self.iaPrefijosDeNpm() {
            let modulos = Rutas.real(URL(fileURLWithPath: prefijo + "/lib/node_modules"))
            let bin = prefijo + "/bin"
            let binEnPath = path.contains(Rutas.real(URL(fileURLWithPath: bin)))
            var porPaquete: [String: [String]] = [:]
            for n in Self.iaNombres(en: bin) where Self.iaTipo(bin + "/" + n) == S_IFLNK {
                let real = Rutas.real(URL(fileURLWithPath: bin + "/" + n))
                if let p = Self.iaPaqueteNpm(de: real), p.hasPrefix(modulos + "/") { porPaquete[p, default: []].append(bin + "/" + n) }
            }
            for (paquete, enlaces) in porPaquete.sorted(by: { $0.key < $1.key }) {
                let nombre = String(paquete[paquete.range(of: "/lib/node_modules/", options: .backwards)!.upperBound...])
                guard let agente = conocidos[nombre], let st = Self.iaStat(paquete), (st.st_mode & S_IFMT) == S_IFDIR,
                      Self.iaAnotaLecturas(paquete) else { continue }
                let comandos = enlaces.map { Rutas.nombre($0) }
                let corto = String(nombre.split(separator: "/").last ?? Substring(nombre))
                // Usarlo de verdad crea su carpeta (configuración, sesión, tareas): sin ella, nunca se configuró.
                if agente.datos.contains(where: { Rutas.existe(Rutas.enHome($0)) }) || (comandos + [corto]).contains(where: Self.iaTieneDatos) {
                    continue
                }
                // Si alguno de sus comandos queda detrás de otro en el PATH, ya lo ofrece «… que no se usa».
                if binEnPath && paquete.hasPrefix(home) && comandos.contains(where: { n in
                    Self.iaPrimeroEnElPath(n, c).map { !$0.hasPrefix(paquete + "/") } ?? false
                }) { continue }
                let instalado = Self.iaLlegada(st)
                guard ahora - instalado >= 21 * 86400 else { continue }
                // Lo que se ejecuta: sus comandos y los programas nativos que trae dentro. Solo la primera lectura después
                // de instalarlo queda anotada: si cayó el mismo día de la instalación, no hay ninguna señal de uso después.
                let programas = enlaces.map { Rutas.real(URL(fileURLWithPath: $0)) }.filter { Self.iaTipo($0) == S_IFREG }
                    + Self.iaBinariosNativos(en: paquete)
                let lecturas = programas.compactMap { Self.iaStat($0) }.compactMap(Self.iaLecturaAnotada)
                let leido = lecturas.max() ?? 0
                guard leido <= instalado + 86400 else { continue }
                // Funcionando ahora: se está usando.
                guard c.procesos.usando(paquete) == nil, !programas.contains(where: { c.procesos.usando($0) != nil }) else { continue }
                let sueltos = Self.iaEnlacesHacia(paquete, c).filter { !enlaces.contains($0) }
                // Primero los enlaces: borrado el paquete, quedarían rotos y la limpieza se los saltaría.
                let rutas = sueltos + enlaces + [paquete]
                let enCasa = paquete.hasPrefix(home)
                let npm = bin + "/npm"
                // Fuera de tu carpeta (Homebrew) no se borra a mano: lo desinstala su propio npm. A los 60 días sin uso
                // anotado ya lo ofrece `paquetesGlobalesDeNpm` con el mismo comando (conAnadidas solo quita lo repetido
                // que se borra por rutas, así que aquí se salta).
                guard enCasa || FileManager.default.isExecutableFile(atPath: npm) else { continue }
                if !enCasa && ahora - max(leido, instalado) >= 60 * 86400 { continue }
                let tamano = Tamanos.recorriendo(paquete)
                let datos = agente.datos.map { "~/" + $0 }
                let fechaInstalado = Self.iaFecha(instalado)
                r.append(Elemento(
                    nombre: "\(agente.nombre) instalado con npm y sin configurar",
                    detalle: "El agente de IA \(agente.nombre) para la terminal, instalado con «npm install -g \(nombre)» en \(Formato.rutaCorta(prefijo)) \(Formato.haceCuanto(fechaInstalado).lowercased()); su comando es \(Formato.lista(comandos.map { "«\($0)»" })). Trae su propio programa nativo y nunca guardó configuración ni sesión.",
                    consecuencia: enCasa
                        ? "\(comandos.count == 1 ? "El comando deja" : "Los comandos dejan") de existir. Si algún día lo quieres, se vuelve a instalar con «npm install -g \(nombre)» (necesita internet). Va a la Papelera: puedes devolverlo con «Deshacer»."
                        : "Lo desinstala npm con «npm uninstall -g \(nombre)» (no pasa por la Papelera). Si algún día lo quieres, se vuelve a instalar con «npm install -g \(nombre)» (necesita internet).",
                    rutas: rutas.map { URL(fileURLWithPath: $0) },
                    tamanosRutas: enCasa ? rutas.map { Self.medida($0, c) } : [],
                    tamanoFijo: enCasa ? nil : tamano,
                    ultimoUso: Self.iaFecha(max(leido, instalado)), categoria: .desarrollo, riesgo: .revisar,
                    accion: enCasa ? .borrar : .comando(programa: npm, argumentos: ["uninstall", "-g", nombre],
                                                        entorno: ["PATH": bin + ":/usr/bin:/bin:/usr/sbin:/sbin", "NPM_CONFIG_UPDATE_NOTIFIER": "false",
                                                                  "NPM_CONFIG_FUND": "false", "NPM_CONFIG_AUDIT": "false"], limite: 120),
                    motivos: [
                        .bien("folder.badge.questionmark", "Sin configurar",
                              "No hay \(Self.iaListaNi(datos)): ahí guarda \(agente.nombre) tu sesión, tus claves y tus tareas en cuanto lo usas de verdad. Tampoco hay ninguna carpeta de \(Self.iaListaNi(comandos))."),
                        .info("moon.zzz.fill", leido > 0 ? "Solo consta una ejecución, al instalarlo" : "Ninguna ejecución anotada",
                              leido > 0
                                ? "macOS solo anota la primera lectura de un programa después de instalarlo, y fue el mismo día (\(Formato.haceCuanto(Self.iaFecha(leido)).lowercased())): no se puede saber si lo abriste después. Lo que indica que no lo usas es que no tiene configuración."
                                : "macOS no anotó ninguna ejecución de sus programas desde que se instaló, \(Formato.haceCuanto(fechaInstalado).lowercased()): con una sola la habría anotado."),
                    ],
                    enUso: .rutas(nombre: comandos[0], raiz: paquete), dueno: agente.nombre,
                    costes: [.descarga(bytes: tamano)]))
            }
        }
        return r
    }

    // MARK: - Cursor Agent sin sesión iniciada

    /// ~/.local/share/cursor-agent (la CLI de Cursor, con su propio Node) cuando nunca se inició sesión (no existe ~/.cursor,
    /// donde guarda cli-config.json, sus chats y sus proyectos), Cursor no está instalado, lleva 30 días o más instalado, no hay ninguna ejecución anotada
    /// en los últimos 30 y nada lo usa. Revisar, con los enlaces de ~/.local/bin que llevan a él. Sus versiones viejas, si
    /// hay varias, ya las ofrece `versionesDeProgramas`.
    func cursorAgentSinSesion(_ c: Contexto) -> [Elemento] {
        let base = Rutas.enHome(".local/share/cursor-agent").path
        guard Self.iaTipo(base) == S_IFDIR, Self.iaSinEnlaces(base), !Self.iaEnRepo(base, c), Self.iaAnotaLecturas(base) else { return [] }
        let carpetaVersiones = base + "/versions"
        let versiones = Self.iaNombres(en: carpetaVersiones).filter { !$0.hasPrefix(".") && Self.iaTipo(carpetaVersiones + "/" + $0) == S_IFDIR }
        guard !versiones.isEmpty else { return [] }
        // Con la sesión iniciada o algo guardado (o Cursor instalado, que la comparte) se usa.
        if [".cursor", ".config/cursor", "Library/Application Support/Cursor", "Applications/Cursor.app"]
            .contains(where: { Rutas.existe(Rutas.enHome($0)) }) { return [] }
        if c.apps.bundleIDs.contains("com.todesktop.230313mzl4w4u92") || c.apps.comandos.contains("cursor")
            || (!Rutas.casaDePrueba && Rutas.existe("/Applications/Cursor.app")) { return [] }
        var instalado = 0
        var leido = 0
        for v in versiones {
            let d = carpetaVersiones + "/" + v
            if let st = Self.iaStat(d) { instalado = max(instalado, Self.iaLlegada(st)) }
            for f in ["cursor-agent", "index.js", "node"] {
                if let st = Self.iaStat(d + "/" + f), let a = Self.iaLecturaAnotada(st) { leido = max(leido, a) }
            }
        }
        let ultima = max(instalado, leido)
        guard Self.iaDias(desde: instalado) >= 30, Self.iaDias(desde: ultima) >= 30, c.procesos.usando(base) == nil else { return [] }
        let enlaces = Self.iaEnlacesHacia(base, c)
        let rutas = enlaces + [base]
        let tamano = Self.medida(base, c)
        return [Elemento(
            nombre: "Cursor Agent sin sesión iniciada",
            detalle: "La CLI de Cursor (cursor-agent \(Formato.lista(versiones))), con su propio Node, en ~/.local/share/cursor-agent. Nunca iniciaste sesión ni guardó nada (no existe ~/.cursor) y Cursor no está instalado.",
            consecuencia: "El comando cursor-agent deja de existir. Si algún día lo quieres, se reinstala con su instalador oficial («curl https://cursor.com/install -fsS | bash», necesita internet). Va a la Papelera: puedes devolverlo con «Deshacer».",
            rutas: rutas.map { URL(fileURLWithPath: $0) }, tamanosRutas: rutas.map { Self.medida($0, c) },
            ultimoUso: Self.iaFecha(ultima), categoria: .desarrollo, riesgo: .revisar,
            motivos: [.bien("person.crop.circle.badge.questionmark", "Sin sesión",
                            "Sin iniciar sesión, cursor-agent no puede hacer nada, y no existe ~/.cursor, donde guarda la sesión (cli-config.json), los chats y los proyectos. Cursor tampoco está instalado."),
                      .info("moon.zzz.fill", "Sin uso anotado desde \(Formato.haceCuanto(Self.iaFecha(ultima)).lowercased())",
                            "Se instaló \(Formato.haceCuanto(Self.iaFecha(instalado)).lowercased()). macOS solo anota la primera lectura de un programa después de instalarlo: no es una prueba, pero sin sesión tampoco hay con qué usarlo.")],
            enUso: .rutas(nombre: "Cursor Agent", raiz: base), dueno: "Cursor Agent", costes: [.descarga(bytes: tamano)])]
    }

    // MARK: - Programas de ~/.local/bin que no se usan desde que se descargaron

    /// «muse-bin-1.0.2-R2040.1» → «muse»: el programa de una herramienta que su propio instalador guarda con la versión.
    private static let patronBinConVersion = try! NSRegularExpression(pattern: #"^([A-Za-z0-9_.]+?)-bin-v?\d[0-9A-Za-z.+_-]*$"#)

    /// Herramientas de la terminal que se instalan con su propio instalador en ~/.local/bin o ~/bin (un programa de 50 MB
    /// o más que se reconoce por llamarse «<cmd>-bin-<versión>» o por tener al lado un «.<cmd>-version»), descargado hace
    /// 45 días o más, cuando nada de lo que escribe al usarse cambió en 45 días: sus carpetas de datos (~/.local/share/<cmd>,
    /// ~/.config/<cmd>, ~/.<cmd>…, al menos una) ni los archivos que deja junto al programa (la última comprobación de
    /// actualizaciones). Además, macOS no anotó ninguna lectura del programa después de descargarlo (más allá de los primeros
    /// minutos, la del propio instalador) ni de su lanzador, y nada lo está usando. Revisar: el programa, su lanzador y
    /// esos archivos. Los datos se quedan (van en «Carpetas ocultas»).
    func programasSinEstrenar(_ c: Contexto) -> [Elemento] {
        let ahora = Int(Date().timeIntervalSince1970)
        let soporte = Rutas.enHome("Library/Application Support").path
        let deSoporte = Self.iaNombres(en: soporte)
        var r: [Elemento] = []
        for d in [".local/bin", "bin"].map({ Rutas.enHome($0).path }) {
            guard Self.iaTipo(d) == S_IFDIR, Self.iaSinEnlaces(d), !Self.iaEnRepo(d, c), Self.iaAnotaLecturas(d) else { continue }
            let nombres = Self.iaNombres(en: d)
            var porHerramienta: [String: [String]] = [:]
            for n in nombres where !n.hasPrefix(".") {
                let ruta = d + "/" + n
                guard let st = Self.iaStat(ruta), (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid(), st.st_size >= 50_000_000,
                      access(ruta, X_OK) == 0 else { continue }
                if let m = Self.patronBinConVersion.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)),
                   let rango = Range(m.range(at: 1), in: n) {
                    porHerramienta[String(n[rango]), default: []].append(ruta)
                } else if nombres.contains("." + n + "-version") {
                    porHerramienta[n, default: []].append(ruta)
                }
            }
            for (h, programas) in porHerramienta.sorted(by: { $0.key < $1.key }) {
                let estados = programas.compactMap { Self.iaStat($0) }
                guard estados.count == programas.count else { continue }
                // Ninguna lectura anotada después de los primeros minutos tras descargarlo (la del propio instalador).
                guard estados.allSatisfy({ Int($0.st_atimespec.tv_sec) <= Int($0.st_mtimespec.tv_sec) + 600 }) else { continue }
                let nunca = estados.allSatisfy(Self.iaSinLeerDesdeQueSeEscribio)
                let descargado = estados.map { Int($0.st_mtimespec.tv_sec) }.max() ?? ahora
                guard ahora - descargado >= 45 * 86400 else { continue }
                // El lanzador (el comando que escribes): si consta una lectura después de la descarga, se usó.
                var lanzador: String?
                let posible = d + "/" + h
                if !programas.contains(posible), let st = Self.iaStat(posible) {
                    let tipo = st.st_mode & S_IFMT
                    if tipo == S_IFREG && st.st_size < 50_000_000 {
                        guard Int(st.st_atimespec.tv_sec) <= descargado + 600 else { continue }
                        lanzador = posible
                    } else if tipo == S_IFLNK, programas.contains(Rutas.real(URL(fileURLWithPath: posible))) {
                        lanzador = posible
                    }
                }
                // Lo que escribe al usarse: sus carpetas de datos (tiene que haber alguna) y los archivos de al lado.
                var datos = [".local/share/\(h)", ".config/\(h)", ".\(h)", ".local/state/\(h)", ".cache/\(h)"].map { Rutas.enHome($0).path }
                datos += deSoporte.filter { $0.lowercased() == h.lowercased() }.map { soporte + "/" + $0 }
                datos = datos.filter { Self.iaTipo($0) == S_IFDIR && Self.iaSinEnlaces($0) }
                guard !datos.isEmpty else { continue }
                let laterales = nombres.filter { $0.hasPrefix("." + h + "-") }.map { d + "/" + $0 }
                    .filter { Self.iaTipo($0) == S_IFREG && (Self.iaStat($0)?.st_size ?? .max) < 1_000_000 }
                let actividad = (datos.map { Self.iaUltimoCambio($0, c) }
                                 + laterales.compactMap { Self.iaStat($0).map { Int($0.st_mtimespec.tv_sec) } }).max() ?? ahora
                guard ahora - actividad >= 45 * 86400 else { continue }
                // Nada lo está usando.
                guard !(programas + [lanzador].compactMap { $0 } + datos).contains(where: { c.procesos.usando($0) != nil }) else { continue }
                let rutas = [lanzador].compactMap { $0 } + programas + laterales
                let versiones = programas.map { Rutas.nombre($0) }.map { n in n.hasPrefix(h + "-bin-") ? String(n.dropFirst(h.count + 5)) : n }
                let tamano = programas.reduce(Int64(0)) { $0 + Self.medida($1, c) }
                let fecha = Self.iaFecha(descargado)
                let carpetas = Formato.lista(datos.map { Formato.rutaCorta($0) })
                r.append(Elemento(
                    nombre: "Programa de «\(h)» sin usar (\(Formato.rutaCorta(d)))",
                    detalle: "El programa de la herramienta de terminal «\(h)» (\(Formato.lista(versiones))) que descargó su instalador en \(Formato.rutaCorta(d)) \(Formato.haceCuanto(fecha).lowercased()), \(lanzador == nil ? "" : "su lanzador ")y los archivos de versión que deja al lado. Desde entonces no hay ninguna señal de que se haya usado.",
                    consecuencia: "El comando \(h) deja de funcionar hasta que lo reinstales con su instalador (necesita internet). Tus sesiones, ajustes y la sesión iniciada (\(carpetas)) no se tocan. Va a la Papelera: puedes devolverlo con «Deshacer».",
                    rutas: rutas.map { URL(fileURLWithPath: $0) }, tamanosRutas: rutas.map { Self.medida($0, c) },
                    ultimoUso: Self.iaFecha(max(descargado, actividad)), categoria: .desarrollo, riesgo: .revisar,
                    motivos: [.bien("folder.fill", "Sus datos no cambian",
                                    "Usarlo escribe en \(carpetas)\(laterales.isEmpty ? "" : " o en sus archivos de al lado (como la última comprobación de actualizaciones)"), y nada cambió ahí desde \(Formato.haceCuanto(Self.iaFecha(actividad)).lowercased()). Esas carpetas no se tocan."),
                              nunca
                                ? .info("moon.zzz.fill", "Nunca se ha ejecutado",
                                        "macOS no anotó ninguna lectura de su programa desde que se descargó: con una sola ejecución la habría anotado.")
                                : .info("moon.zzz.fill", "Solo se leyó al descargarse",
                                        "La única lectura que anotó macOS fue al descargarlo (la del instalador). macOS solo anota la primera, así que lo que indica que no lo usas es que sus datos no cambian.")],
                    enUso: .rutas(nombre: h, raiz: programas[0]), dueno: h, costes: [.descarga(bytes: tamano)]))
            }
        }
        return r
    }

    // MARK: - Versiones anteriores de Claude Code (instalador nativo)

    /// Con «claude install», Claude Code guarda cada versión como un archivo ejecutable en ~/.local/share/claude/versions y
    /// ~/.local/bin/claude apunta a la que usa. Se conservan esa (o la del comando claude del PATH), la más nueva y las
    /// que esté ejecutando algún programa; las demás, con 1 día o más, son Seguro si se sabe cuál usa (si no, Revisar).
    /// Si se está actualizando (un candado de la última hora), no se ofrece nada. Las versiones que son carpetas ya las
    /// mira `versionesDeProgramas`.
    func versionesDeClaudeCodeNativo(_ c: Contexto) -> [Elemento] {
        let carpeta = Rutas.enHome(".local/share/claude/versions").path
        guard Self.iaTipo(carpeta) == S_IFDIR, Self.iaSinEnlaces(carpeta), !Self.iaEnRepo(carpeta, c) else { return [] }
        let ahora = Int(Date().timeIntervalSince1970)
        let versiones = Self.iaNombres(en: carpeta).filter { n in
            guard Self.iaPareceVersion(n), let st = Self.iaStat(carpeta + "/" + n) else { return false }
            return (st.st_mode & S_IFMT) == S_IFREG && st.st_uid == getuid()
        }.sorted { Self.compararVersion($0, $1) }
        guard versiones.count > 1, let nueva = versiones.last else { return [] }
        let candados = Rutas.enHome(".local/state/claude/locks").path
        let actualizando = ([candados] + Self.iaNombres(en: candados).map { candados + "/" + $0 }).contains { ruta in
            Self.iaStat(ruta).map { ahora - Int($0.st_mtimespec.tv_sec) < 3600 } ?? false
        }
        guard !actualizando else { return [] }
        var usadas: Set<String> = [nueva]
        var confirmada = false
        let real = Rutas.real(URL(fileURLWithPath: carpeta))
        for destino in [Rutas.real(Rutas.enHome(".local/bin/claude")), Self.iaPrimeroEnElPath("claude", c)].compactMap({ $0 })
        where Rutas.padre(destino) == real && versiones.contains(Rutas.nombre(destino)) {
            usadas.insert(Rutas.nombre(destino))
            confirmada = true
        }
        for v in versiones where c.procesos.usando(carpeta + "/" + v) != nil { usadas.insert(v) }
        var r: [Elemento] = []
        for v in versiones where !usadas.contains(v) {
            let ruta = carpeta + "/" + v
            guard let st = Self.iaStat(ruta), ahora - Self.iaLlegada(st) >= 86400 else { continue }
            let fecha = Self.iaFecha(Int(st.st_mtimespec.tv_sec))
            let enUso = usadas.subtracting([nueva]).sorted()
            r.append(Elemento(
                nombre: "Claude Code \(v) (versión anterior)",
                detalle: "Una versión anterior de Claude Code que su instalador nativo dejó en ~/.local/share/claude/versions al actualizarse. Ahora usa la \(Formato.lista((enUso.isEmpty ? [nueva] : enUso)))\(enUso.contains(nueva) || enUso.isEmpty ? "" : " (y está descargada la \(nueva))").",
                consecuencia: confirmada ? "Nada: el comando claude usa otra versión. Si algún día quisieras volver a esta, «claude install \(v)» la descarga otra vez."
                                         : "Si algo sigue usando esta versión exacta, tendrás que volver a instalarla («claude install \(v)»).",
                rutas: [URL(fileURLWithPath: ruta)], ultimoUso: fecha, categoria: .desarrollo, riesgo: confirmada ? .seguro : .revisar,
                seleccionado: confirmada,
                motivos: [confirmada
                    ? .bien("clock.arrow.circlepath", "Versión anterior", "~/.local/bin/claude apunta a otra versión y ningún programa ejecuta esta.")
                    : .info("clock.arrow.circlepath", "Versión anterior", "Hay una más nueva (\(nueva)), aunque no pude confirmar cuál usa el comando claude.")],
                enUso: .rutas(nombre: "Claude Code", raiz: ruta), dueno: "Claude Code", cambioAnalizado: fecha))
        }
        return r
    }

    // MARK: - Puntos de control de Claude Code que ya no sirven

    private static let patronUUID = try! NSRegularExpression(
        pattern: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#, options: [.caseInsensitive])

    private static func iaUUIDs(en texto: String) -> [String] {
        patronUUID.matches(in: texto, range: NSRange(texto.startIndex..., in: texto)).compactMap {
            Range($0.range, in: texto).map { texto[$0].lowercased() }
        }
    }

    /// Las sesiones de Claude Code que están abiertas: las de ~/.claude/sessions/<pid>.json con ese proceso vivo y las
    /// que nombra un proceso al arrancar («claude --resume <id>»).
    private static func sesionesDeClaudeAbiertas(_ c: Contexto) -> Set<String> {
        var r = Set<String>()
        let carpeta = Rutas.enHome(".claude/sessions").path
        for n in iaNombres(en: carpeta) where n.hasSuffix(".json") {
            guard let pid = pid_t(n.prefix { $0.isNumber }), pid > 0, kill(pid, 0) == 0 || errno == EPERM,
                  let st = iaStat(carpeta + "/" + n), (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= 65_536,
                  let texto = try? String(contentsOfFile: carpeta + "/" + n, encoding: .utf8) else { continue }
            r.formUnion(iaUUIDs(en: texto))
        }
        for linea in c.procesos.lineas where linea.contains("claude") { r.formUnion(iaUUIDs(en: linea)) }
        return r
    }

    /// Los puntos de control de Claude Code (~/.claude/file-history/<sesión>: las copias de tus archivos para poder
    /// deshacer sus cambios) y lo que guarda con el mismo nombre (session-env, todos, debug) de conversaciones que ya no
    /// sirven: las de proyectos cuya carpeta ya no existe (como `conversacionesDeProyectosBorrados`, con 1 día sin cambios)
    /// y las que ya no tienen su conversación en ningún proyecto (7 días sin cambios). Por nombre, sin abrir nada; nunca la
    /// de una sesión abierta. Revisar.
    func puntosDeControlDeClaude(_ c: Contexto) -> [Elemento] {
        let claude = Rutas.enHome(".claude").path
        guard Self.iaTipo(claude) == S_IFDIR, Self.iaSinEnlaces(claude), !Self.iaEnRepo(claude, c) else { return [] }
        let raiz = claude + "/projects"
        let ahora = Int(Date().timeIntervalSince1970)
        // Qué conversación (<id>.jsonl) hay en cada proyecto, y qué proyectos ya no existen.
        var deProyecto: [String: String] = [:]
        var huerfanos = Set<String>()
        let casa = Self.codificarComoClaude(Rutas.home.path) + "-"
        for n in Self.iaNombres(en: raiz) where Self.iaTipo(raiz + "/" + n) == S_IFDIR {
            let carpeta = raiz + "/" + n
            let ids = Self.iaNombres(en: carpeta).filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(6)).lowercased() }
            for id in ids { deProyecto[id] = n }
            guard n.hasPrefix("-"), !n.hasPrefix("-Volumes-"), !ids.isEmpty, ahora - Self.iaUltimoCambio(carpeta, c) >= 86400,
                  Self.existeCarpeta(codificadaComoClaude: n) == false else { continue }
            huerfanos.insert(n)
        }
        let abiertas = Self.sesionesDeClaudeAbiertas(c)
        let historial = claude + "/file-history"
        var rutas: [String] = []
        var deBorrados = Set<String>()
        var sinConversacion = 0
        var sesiones = Set<String>()
        // ~/.claude/todos (un <id>-agent-<id>.json por sesión y por subagente: pueden ser miles), listado una sola vez y
        // agrupado por la sesión con la que empieza su nombre. El id ya es un UUID de 36 caracteres en minúsculas.
        var todosDe: [String: [String]] = [:]
        for n in Self.iaNombres(en: claude + "/todos") where n.hasSuffix(".json") {
            todosDe[String(n.lowercased().prefix(36)), default: []].append(claude + "/todos/" + n)
        }
        // Cada sesión, una vez (puede estar en file-history y en session-env).
        var vistas = Set<String>()
        for id in Self.iaNombres(en: historial) + Self.iaNombres(en: claude + "/session-env") {
            let clave = id.lowercased()
            guard vistas.insert(clave).inserted, !abiertas.contains(clave), Self.iaUUIDs(en: clave) == [clave] else { continue }
            let proyecto = deProyecto[clave]
            let minimo: Int
            if let proyecto {
                guard huerfanos.contains(proyecto) else { continue }
                minimo = 86400
            } else {
                minimo = 7 * 86400
            }
            // Lo suyo: file-history/<id>, session-env/<id>, todos/<id>-*.json y debug/<id>.txt, sin enlaces.
            var suyas = ["file-history/\(id)", "session-env/\(id)"].map { claude + "/" + $0 }.filter { Self.iaTipo($0) == S_IFDIR }
            suyas += todosDe[clave] ?? []
            suyas += [claude + "/debug/\(id).txt"].filter { Self.iaTipo($0) == S_IFREG }
            guard !suyas.isEmpty, suyas.allSatisfy({ ahora - Self.iaUltimoCambio($0, c) >= minimo }) else { continue }
            sesiones.insert(clave)
            rutas += suyas
            if let proyecto { deBorrados.insert(proyecto) } else { sinConversacion += 1 }
        }
        guard !rutas.isEmpty else { return [] }
        let nombresProyectos = deBorrados.sorted().map { $0.hasPrefix(casa) ? String($0.dropFirst(casa.count)) : $0 }
        var partes: [String] = []
        if !deBorrados.isEmpty {
            partes.append("de proyectos que ya no están en el Mac (\(Formato.listaCorta(nombresProyectos, maximo: 5)))")
        }
        if sinConversacion > 0 {
            partes.append("\(sinConversacion == 1 ? "una conversación que" : "\(sinConversacion) conversaciones que") ya no \(sinConversacion == 1 ? "está" : "están") en ningún proyecto")
        }
        let cambio = rutas.map { Self.iaUltimoCambio($0, c) }.max() ?? 0
        return [Elemento(
            nombre: "Puntos de control de Claude Code que ya no sirven",
            detalle: "Las copias de tus archivos que Claude Code guarda en cada conversación para poder deshacer sus cambios (~/.claude/file-history) y lo que deja al lado con el mismo nombre (session-env, todos), de \(sesiones.count == 1 ? "una conversación" : "\(sesiones.count) conversaciones"): \(Formato.lista(partes)).",
            consecuencia: "Ya no podrás deshacer con Claude Code los cambios que hizo en esas conversaciones; sin la carpeta del proyecto o sin la conversación, de todos modos ya no los puede usar. Las conversaciones en sí no se tocan aquí. Va a la Papelera.",
            rutas: rutas.map { URL(fileURLWithPath: $0) }, tamanosRutas: rutas.map { Self.medida($0, c) },
            ultimoUso: cambio > 0 ? Self.iaFecha(cambio) : nil, categoria: .herramientas, riesgo: .revisar,
            motivos: [.info("arrow.uturn.backward.circle", "Ya no se pueden usar",
                            "Cada carpeta se llama como su conversación (<id>.jsonl en ~/.claude/projects): o su proyecto ya no existe o la conversación ya no está. Lo miré por los nombres, sin abrir nada, y ninguna es de una sesión abierta.")],
            enUso: .rutas(nombre: "Claude Code", raiz: historial), dueno: "Claude Code",
            cambioAnalizado: cambio > 0 ? Self.iaFecha(cambio) : nil)]
    }

    // MARK: - Dependencias de plugins de opencode

    /// ~/.config/<herramienta>/node_modules que opencode (o un derivado con la misma estructura) instaló para cargar
    /// plugins: su package.json solo pide el SDK de plugins (@opencode-ai/…), no hay plugins tuyos (plugin/ o plugins/ con
    /// .ts o .js), lleva 30 días o más sin cambios y no está en un repositorio. Revisar: se reinstala solo, con internet. La
    /// configuración (package.json, opencode.json…) no se toca. (~/.opencode no: «Carpetas ocultas» ya la ofrece entera, como
    /// Cuidado o Revisar, y `conAnadidas` quitaría lo de dentro.)
    func dependenciasDePluginsDeOpencode(_ c: Contexto) -> [Elemento] {
        let config = Rutas.enHome(".config").path
        let carpetas = Self.iaNombres(en: config).filter { !$0.hasPrefix(".") }.map { config + "/" + $0 }
        let ahora = Int(Date().timeIntervalSince1970)
        var r: [Elemento] = []
        for d in carpetas {
            let modulos = d + "/node_modules"
            let paquete = d + "/package.json"
            guard Self.iaTipo(d) == S_IFDIR, Self.iaTipo(modulos) == S_IFDIR, Self.iaSinEnlaces(modulos), !Self.iaEnRepo(d, c),
                  let st = Self.iaStat(paquete), (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= 65_536,
                  let datos = FileManager.default.contents(atPath: paquete),
                  let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any] else { continue }
            let dependencias = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"]
                .flatMap { ((json[$0] as? [String: Any]) ?? [:]).keys }.sorted()
            guard !dependencias.isEmpty, dependencias.allSatisfy({ $0.hasPrefix("@opencode-ai/") }) else { continue }
            // Con plugins tuyos, estas dependencias son las suyas: no se tocan.
            let extensiones: Set<String> = ["ts", "tsx", "js", "mjs", "cjs", "jsx"]
            let conPlugins = ["plugin", "plugins"].contains { sub in
                guard let e = FileManager.default.enumerator(atPath: d + "/" + sub) else { return false }
                for case let rel as String in e where extensiones.contains((rel as NSString).pathExtension.lowercased()) { return true }
                return false
            }
            guard !conPlugins else { continue }
            let cambio = Self.iaUltimoCambio(modulos, c)
            guard ahora - cambio >= 30 * 86400 else { continue }
            let herramienta = Rutas.nombre(d)
            let tamano = Self.medida(modulos, c)
            r.append(Elemento(
                nombre: "Dependencias de plugins de \(herramienta) (se reinstalan solas)",
                detalle: "Los paquetes de npm que \(herramienta) instaló en \(Formato.rutaCorta(d)) para poder cargar plugins (\(Formato.lista(dependencias)) y lo que necesitan). No tienes plugins propios ahí.",
                consecuencia: "Nada mientras no uses plugins: si algún día \(herramienta) los necesita, los vuelve a instalar desde su package.json (necesita internet). Tu configuración (package.json, opencode.json…) no se toca. Va a la Papelera.",
                rutas: [URL(fileURLWithPath: modulos)], ultimoUso: Self.iaFecha(cambio), categoria: .herramientas, riesgo: .revisar,
                motivos: [.info("puzzlepiece.extension", "Solo el SDK de plugins",
                                "Su package.json solo pide \(Formato.lista(dependencias)) y no hay ningún plugin tuyo (plugin/ o plugins/). Nada cambió dentro desde \(Formato.haceCuanto(Self.iaFecha(cambio)).lowercased()).")],
                enUso: .programas(nombre: herramienta, ejecutables: [herramienta, "opencode"]), dueno: herramienta,
                costes: [.descarga(bytes: tamano)], cambioAnalizado: Self.iaFecha(cambio)))
        }
        return r
    }

    // MARK: - Caché de OpenTUI

    /// ~/.local/share/opentui/tree-sitter: las gramáticas (.wasm) y consultas (.scm) que OpenTUI, la librería de la interfaz
    /// de opencode, descarga para colorear el código. Si solo hay eso, es caché: Seguro, solo con «Liberar al máximo» (se
    /// vuelve a descargar). Lo demás de ~/.local/share/opentui, Revisar. (`herramientas` no la mira como carpeta genérica.)
    func cacheDeOpenTUI(_ c: Contexto) -> [Elemento] {
        let base = Rutas.enHome(".local/share/opentui").path
        guard Self.iaTipo(base) == S_IFDIR, Self.iaSinEnlaces(base), !Self.iaEnRepo(base, c) else { return [] }
        let gramaticas = base + "/tree-sitter"
        var resto = Self.iaNombres(en: base).filter { $0 != "tree-sitter" && $0 != ".DS_Store" }.map { base + "/" + $0 }
        var r: [Elemento] = []
        if Self.iaTipo(gramaticas) == S_IFDIR {
            // Solo archivos .wasm y .scm (nada de enlaces ni de otros archivos), en languages/ y queries/.
            var lenguajes = Set<String>()
            var soloDescargas = true
            if let e = FileManager.default.enumerator(atPath: gramaticas) {
                for case let rel as String in e {
                    let ruta = gramaticas + "/" + rel
                    let tipo = Self.iaTipo(ruta)
                    if tipo == S_IFDIR { continue }
                    let ext = (rel as NSString).pathExtension.lowercased()
                    guard tipo == S_IFREG, ext == "wasm" || ext == "scm" || Rutas.nombre(rel) == ".DS_Store" else { soloDescargas = false; break }
                    let n = (Rutas.nombre(rel) as NSString).deletingPathExtension
                    if ext == "wasm" { lenguajes.insert(n.hasPrefix("tree-sitter-") ? String(n.dropFirst(12)) : n) }
                }
            }
            if soloDescargas {
                let cambio = Self.iaUltimoCambio(gramaticas, c)
                let tamano = Self.medida(gramaticas, c)
                r.append(Elemento(
                    nombre: "Caché de gramáticas de OpenTUI (opencode)",
                    detalle: "Las gramáticas de tree-sitter\(lenguajes.isEmpty ? "" : " (\(Formato.listaCorta(lenguajes.sorted(), maximo: 6)))") que OpenTUI, la librería de la interfaz de opencode, descarga para colorear el código en la terminal.",
                    consecuencia: "Nada: opencode las vuelve a descargar la próxima vez que enseñe código de ese lenguaje (necesita internet).",
                    rutas: [URL(fileURLWithPath: gramaticas)], ultimoUso: cambio > 0 ? Self.iaFecha(cambio) : nil,
                    categoria: .herramientas, riesgo: .seguro, seleccionado: true,
                    motivos: [.bien("arrow.down.circle", "Se vuelve a descargar",
                                    "Solo hay gramáticas (.wasm) y consultas (.scm) descargadas, con el nombre de su lenguaje: nada que escribieras tú.")],
                    enUso: .programas(nombre: "opencode", ejecutables: ["opencode"]), dueno: "opencode",
                    nivel: .maximo, costes: [.descarga(bytes: tamano)], cambioAnalizado: cambio > 0 ? Self.iaFecha(cambio) : nil))
            } else {
                resto.append(gramaticas)
            }
        }
        if !resto.isEmpty {
            r.append(Elemento(
                nombre: ".local/share/opentui",
                detalle: "Otros datos de OpenTUI, la librería de la interfaz de opencode y de otros programas de terminal: \(Formato.listaCorta(resto.map { Rutas.nombre($0) })).",
                consecuencia: "Si es de un programa que usas, puede perder lo que guardó ahí.",
                rutas: resto.map { URL(fileURLWithPath: $0) }, tamanosRutas: resto.map { Self.medida($0, c) },
                categoria: .herramientas, riesgo: .revisar,
                motivos: [.info("questionmark.folder", "No es solo caché", "No son solo gramáticas descargadas: revisa qué es antes de borrarlo.")],
                enUso: .rutas(nombre: "OpenTUI", raiz: base), dueno: "opencode"))
        }
        return r
    }

    // MARK: - Paquetes de pip --user con su Python instalado: no se ofrecen

    // No hay ninguna señal fiable de que un paquete de pip --user no se importe nunca. pip compila las copias .pyc al
    // instalar (también con PYTHONDONTWRITEBYTECODE), y cada import usa esa copia: no escribe otra ni vuelve a leer el .py,
    // cuya única lectura anotada es la de esa compilación. El Python de Apple (/usr/bin/python3) además las guarda en
    // ~/Library/Caches/com.apple.python, no en site-packages, y esa caché se puede vaciar. Que falten copias nuevas o
    // lecturas no prueba nada: un paquete que se importa a diario saldría como «nunca importado». Sin su Python ya está
    // `paquetesDePipDeUsuario`.

    // MARK: - Node instalados a mano que nadie usa

    private static let patronNode = try! NSRegularExpression(pattern: #"^node(js)?(-v?\d+(\.\d+)*)?(-darwin-(arm64|x64))?$"#,
                                                             options: [.caseInsensitive])

    /// Node descomprimidos a mano en ~/.local/runtime, ~/.local/lib/nodejs, ~/.local/opt o ~/.local (node-v20.11.0…) cuando
    /// la terminal usa otro Node: este no está en el PATH ni lleva a él ningún comando, nada lo ejecuta y nada cambió dentro
    /// (sus paquetes globales) en 60 días. Revisar, con los paquetes globales que lleva dentro. Los de nvm, fnm, Volta, asdf
    /// y mise ya los mira `versionesDeLenguajes`.
    func nodesSinUsar(_ c: Contexto) -> [Elemento] {
        guard let delPath = Self.iaPrimeroEnElPath("node", c) else { return [] }
        let ahora = Int(Date().timeIntervalSince1970)
        let path = Set(c.apps.pathTerminal.map { Rutas.real(URL(fileURLWithPath: $0)) })
        var candidatos: [String] = []
        for rel in [".local/runtime", ".local/lib/nodejs", ".local/opt", ".local"] {
            let d = Rutas.enHome(rel).path
            for n in Self.iaNombres(en: d) where Self.patronNode.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil {
                let ruta = d + "/" + n
                if Self.iaTipo(ruta) == S_IFDIR, Self.iaTipo(ruta + "/bin/node") == S_IFREG, !candidatos.contains(ruta) { candidatos.append(ruta) }
            }
        }
        var r: [Elemento] = []
        for ruta in candidatos where Self.iaSinEnlaces(ruta) && !Self.iaEnRepo(ruta, c) {
            // El del PATH, uno cuyo bin/ está en el PATH, uno al que lleva un comando o uno que algo ejecuta ahora: se usa.
            guard !delPath.hasPrefix(ruta + "/"), !path.contains(ruta + "/bin"), c.apps.comandoDentro(de: ruta) == nil,
                  c.procesos.usando(ruta) == nil, let st = Self.iaStat(ruta + "/bin/node") else { continue }
            let cambio = Self.iaUltimoCambio(ruta, c)
            guard ahora - cambio >= 60 * 86400 else { continue }
            let globales = Self.iaNombres(en: ruta + "/lib/node_modules").filter { !$0.hasPrefix(".") && !["npm", "corepack"].contains($0) }
                .flatMap { n in n.hasPrefix("@") ? Self.iaNombres(en: ruta + "/lib/node_modules/" + n).map { n + "/" + $0 } : [n] }
            var motivos: [Motivo] = [.info("arrow.triangle.branch", "No es el de la terminal",
                "Al escribir «node» se usa \(Formato.rutaCorta(delPath)); este no está en el PATH y ningún comando lleva a él. Nada cambió dentro desde \(Formato.haceCuanto(Self.iaFecha(cambio)).lowercased()).")]
            if Self.iaAnotaLecturas(ruta), Self.iaSinLeerDesdeQueSeEscribio(st) {
                motivos.append(.bien("moon.zzz.fill", "Su node no se ha ejecutado",
                                     "macOS no anotó ninguna ejecución de su node desde que se escribió: con una sola la habría anotado."))
            }
            r.append(Elemento(
                nombre: "Node \(Rutas.nombre(ruta)) que no usa la terminal (\(Formato.rutaCorta(Rutas.padre(ruta))))",
                detalle: "Un Node instalado a mano en \(Formato.rutaCorta(ruta)). La terminal usa otro (\(Formato.rutaCorta(delPath)))\(globales.isEmpty ? "" : ", y dentro lleva estos paquetes globales: \(Formato.listaCorta(globales, maximo: 5))").",
                consecuencia: "Si algún script, editor o servicio lo llama por su ruta completa, dejará de funcionar\(globales.isEmpty ? "" : ", y se van con él sus paquetes globales (se reinstalan con «npm install -g» en el otro Node)"). Va a la Papelera.",
                rutas: [URL(fileURLWithPath: ruta)], ultimoUso: Self.iaFecha(cambio), categoria: .desarrollo, riesgo: .revisar,
                motivos: motivos, enUso: .rutas(nombre: "Node", raiz: ruta), dueno: "Node"))
        }
        return r
    }

    // MARK: - Ollama sin ningún modelo (solo una nota)

    /// Las carpetas donde Ollama guarda sus modelos: ~/.ollama/models y la que diga OLLAMA_MODELS (en el entorno o en el
    /// plist de su servicio).
    private static func carpetasDeModelosDeOllama(plists: [String]) -> [String] {
        var r = [Rutas.enHome(".ollama/models").path]
        var valores = [ProcessInfo.processInfo.environment["OLLAMA_MODELS"]].compactMap { $0 }
        for p in plists {
            guard let datos = FileManager.default.contents(atPath: p),
                  let plist = try? PropertyListSerialization.propertyList(from: datos, format: nil) as? [String: Any],
                  let v = (plist["EnvironmentVariables"] as? [String: Any])?["OLLAMA_MODELS"] as? String else { continue }
            valores.append(v)
        }
        for v in valores where !v.isEmpty {
            let ruta = v.hasPrefix("~/") ? Rutas.enHome(String(v.dropFirst(2))).path : v
            if !r.contains(ruta) { r.append(ruta) }
        }
        return r
    }

    /// Si en alguna de esas carpetas hay algún modelo (un manifiesto) o no se pudo mirar entera.
    private static func hayModelosDeOllama(en carpetas: [String]) -> Bool {
        for m in carpetas {
            let manifiestos = m + "/manifests"
            guard Rutas.existe(manifiestos) else { continue }
            guard (try? FileManager.default.contentsOfDirectory(atPath: manifiestos)) != nil,
                  let e = FileManager.default.enumerator(atPath: manifiestos) else { return true }
            for case let rel as String in e {
                let tipo = iaTipo(manifiestos + "/" + rel)
                if tipo == S_IFDIR { if access(manifiestos + "/" + rel, R_OK | X_OK) != 0 { return true }; continue }
                if !Rutas.nombre(rel).hasPrefix(".") { return true }
            }
        }
        return false
    }

    /// Los nombres de las dependencias de una fórmula y si la pediste tú, según su INSTALL_RECEIPT.json.
    private static func reciboDeHomebrew(_ keg: String) -> (dependencias: [String], pedida: Bool)? {
        guard let st = iaStat(keg + "/INSTALL_RECEIPT.json"), st.st_size <= 1_000_000,
              let datos = FileManager.default.contents(atPath: keg + "/INSTALL_RECEIPT.json"),
              let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any] else { return nil }
        let deps = ((json["runtime_dependencies"] as? [[String: Any]]) ?? []).compactMap { $0["full_name"] as? String }
        return (deps, (json["installed_on_request"] as? Bool) ?? true)
    }

    /// Ollama instalado (con Homebrew o como app) hace 30 días o más sin ningún modelo y sin usar «ollama run» en 30 días
    /// (~/.ollama/history). No se ofrece borrar: es un programa tuyo y su servicio lo arranca Homebrew (o la app). Va
    /// como nota en «Cachés de desarrollo», con lo que ocupa (con las dependencias que solo usa él) y los comandos.
    func notaDeOllamaSinModelos(_ c: Contexto) {
        let ahora = Int(Date().timeIntervalSince1970)
        let historial = Rutas.enHome(".ollama/history").path
        if let st = Self.iaStat(historial), ahora - Int(st.st_mtimespec.tv_sec) < 30 * 86400 { return }
        let agente = Rutas.enHome("Library/LaunchAgents/homebrew.mxcl.ollama.plist").path
        let funcionando = c.procesos.programas.contains { AppsInstaladas.normalizar(Rutas.nombre($0.ruta)) == "ollama" }
        for prefijo in Rutas.homebrew {
            let opt = prefijo + "/opt/ollama"
            guard Self.iaTipo(opt) == S_IFLNK else { continue }
            let keg = Rutas.real(URL(fileURLWithPath: opt))
            guard keg.hasPrefix(Rutas.real(URL(fileURLWithPath: prefijo + "/Cellar/ollama")) + "/"), Self.iaTipo(keg) == S_IFDIR,
                  let recibo = Self.iaStat(keg + "/INSTALL_RECEIPT.json"), ahora - Int(recibo.st_mtimespec.tv_sec) >= 30 * 86400 else { continue }
            let modelos = Self.carpetasDeModelosDeOllama(plists: [agente, keg + "/homebrew.mxcl.ollama.plist"])
            guard !Self.hayModelosDeOllama(en: modelos) else { continue }
            // Las dependencias que solo usa Ollama (no las pediste tú y ninguna fórmula que se queda las necesita): las
            // quitaría «brew autoremove» después de desinstalarlo. Se van quitando de la lista las que necesita alguna otra.
            var exclusivas: [(nombre: String, keg: String)] = []
            if let propio = Self.reciboDeHomebrew(keg) {
                var dependencias: [String: [String]] = [:]
                for f in Self.iaNombres(en: prefijo + "/Cellar") where f != "ollama" && !f.hasPrefix(".") {
                    let k = Rutas.real(URL(fileURLWithPath: prefijo + "/opt/" + f))
                    dependencias[f] = Self.reciboDeHomebrew(k)?.dependencias ?? []
                }
                var candidatas: [String: String] = [:]
                for d in propio.dependencias {
                    let k = Rutas.real(URL(fileURLWithPath: prefijo + "/opt/" + d))
                    if let suyo = Self.reciboDeHomebrew(k), !suyo.pedida { candidatas[d] = k }
                }
                var cambia = true
                while cambia {
                    cambia = false
                    for d in candidatas.keys where dependencias.contains(where: { f, suyas in candidatas[f] == nil && suyas.contains(d) }) {
                        candidatas[d] = nil
                        cambia = true
                    }
                }
                exclusivas = candidatas.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
            }
            let bytes = ([keg] + exclusivas.map(\.keg)).reduce(Int64(0)) { $0 + Tamanos.recorriendo($1) }
            let version = Rutas.nombre(keg)
            let servicio = funcionando ? "Su servidor («ollama serve») está funcionando ahora"
                : Rutas.existe(agente) ? "Su servidor arranca solo con el Mac (brew services)" : "Su servidor no está funcionando"
            let deps = exclusivas.isEmpty ? "" : " (quita también \(Formato.lista(exclusivas.map(\.nombre))), que solo usa Ollama, y cualquier otra dependencia que ya no use nada)"
            c.indice.notas.append(NotaGrande(
                categoria: .desarrollo, titulo: "Ollama sin ningún modelo",
                texto: "Ollama \(version) está instalado con Homebrew desde hace \(Int(Self.iaDias(desde: Int(recibo.st_mtimespec.tv_sec)))) días, pero no tiene ningún modelo (\(Formato.lista(modelos.map { Formato.rutaCorta($0) })) no tiene manifiestos) y no veo uso de «ollama run» en 30 días. \(servicio). No lo ofrezco para borrar: es un programa tuyo. Si no lo usas, en la Terminal: «brew services stop ollama», «brew uninstall ollama» y «brew autoremove»\(deps). Tu identidad de ollama.com (~/.ollama/id_ed25519) se queda: bórrala tú si no la necesitas.",
                ruta: keg, bytes: bytes))
            return
        }
        // La app (Ollama.app): también arranca su servidor al abrirse.
        for app in (Rutas.casaDePrueba ? [] : ["/Applications/Ollama.app"]) + [Rutas.enHome("Applications/Ollama.app").path] {
            guard Self.iaTipo(app) == S_IFDIR, let st = Self.iaStat(app), ahora - Int(st.st_mtimespec.tv_sec) >= 30 * 86400 else { continue }
            guard !Self.hayModelosDeOllama(en: Self.carpetasDeModelosDeOllama(plists: [])) else { continue }
            c.indice.notas.append(NotaGrande(
                categoria: .desarrollo, titulo: "Ollama sin ningún modelo",
                texto: "Tienes Ollama.app desde hace \(Int(Self.iaDias(desde: Int(st.st_mtimespec.tv_sec)))) días, pero no tiene ningún modelo y no veo uso de «ollama run» en 30 días. No la ofrezco para borrar: es una app tuya. Si no la usas, ciérrala desde la barra de menús y arrástrala a la Papelera (se quitan también los ítems de inicio com.ollama* de Ajustes › General › Ítems de inicio). Tu identidad de ollama.com (~/.ollama/id_ed25519) se queda: bórrala tú si no la necesitas.",
                ruta: app, bytes: Tamanos.recorriendo(app)))
            return
        }
    }
}
