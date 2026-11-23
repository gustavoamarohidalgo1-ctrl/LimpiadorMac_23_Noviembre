import Foundation
import zlib

/// Compilaciones y entregas que no están donde las busca «Compilaciones» (las salidas de .NET escritas fuera de su
/// proyecto, las versiones anteriores de lo que publicaste, la carpeta que ya está dentro de su zip), las copias de
/// respaldo de un proyecto que son casi iguales a su original y las copias idénticas que son parte de un programa.
extension Escaner {

    // MARK: - Ganchos por categoría

    /// Lo que se añade a «Compilaciones». Cada regla no repite lo que ya ofrece la anterior.
    func compilacionesAmpliado(_ c: Contexto) -> [Elemento] {
        let dotnet = salidasDeDotnetFuera(c)
        var tomadas = Set(dotnet.flatMap { $0.rutas.map(\.path) })
        let entregas = entregasAnteriores(c, tomadas: tomadas)
        tomadas.formUnion(entregas.flatMap { $0.rutas.map(\.path) })
        let descomprimidas = copiasDescomprimidas(c, tomadas: tomadas)
        tomadas.formUnion(descomprimidas.flatMap { $0.rutas.map(\.path) })
        return dotnet + entregas + descomprimidas + archivosDeRuntimeDescomprimidos(c, tomadas: tomadas)
    }

    // MARK: - Paquetes de .runtime ya descomprimidos (jdk.tar.gz, maven.tar.gz…)

    /// Dentro de carpetas `.runtime` de tus proyectos, archivos comprimidos (.tar.gz/.tgz/.zip >= 5 MB) que ya tienen su
    /// carpeta descomprimida al lado (por ejemplo jdk.tar.gz junto a jdk-21… o maven.tar.gz junto a apache-maven-…).
    private func archivosDeRuntimeDescomprimidos(_ c: Contexto, tomadas: Set<String>) -> [Elemento] {
        let home = Rutas.home.path
        var r: [Elemento] = []
        for ruta in c.indice.carpetas.keys.sorted() where Rutas.nombre(ruta) == ".runtime" {
            guard ruta.hasPrefix(home + "/"), !AyudaDeEntregas.enNube(ruta),
                  !tomadas.contains(ruta), !Totales.dentroDe(ruta, tomadas) else { continue }
            let hijos = AyudaDeEntregas.nombres(ruta)
            let carpetas = hijos.filter { n in
                var st = stat()
                return lstat(ruta + "/" + n, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
            }
            guard !carpetas.isEmpty else { continue }
            var sobrantes: [URL] = []
            var tamanos: [Int64] = []
            var fechas: [Date] = []
            for n in hijos {
                let low = n.lowercased()
                let base: String
                if low.hasSuffix(".tar.gz") { base = String(low.dropLast(7)) }
                else if low.hasSuffix(".tgz") { base = String(low.dropLast(4)) }
                else if low.hasSuffix(".zip") { base = String(low.dropLast(4)) }
                else { continue }
                guard base.count >= 3 else { continue }
                // Existe una subcarpeta descomprimida cuyo nombre contiene el nombre base (jdk → jdk-21…, maven → apache-maven-…).
                guard carpetas.contains(where: { $0.lowercased().contains(base) }) else { continue }
                let p = ruta + "/" + n
                var st = stat()
                guard lstat(p, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }
                let bytes = Int64(st.st_blocks) * 512
                let fecha = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                guard bytes >= 5_000_000, Date().timeIntervalSince(fecha) >= 3 * 86400 else { continue }
                sobrantes.append(URL(fileURLWithPath: p))
                tamanos.append(bytes)
                fechas.append(fecha)
            }
            guard !sobrantes.isEmpty else { continue }
            let proyecto = Rutas.nombre(Rutas.padre(ruta))
            r.append(Elemento(
                nombre: "Instaladores ya descomprimidos en .runtime (\(proyecto))",
                detalle: "Archivos comprimidos (\(Formato.listaCorta(sobrantes.map(\.lastPathComponent), maximo: 4))) dentro de \(Formato.rutaCorta(ruta)) que ya tienen su carpeta descomprimida al lado.",
                consecuencia: "Se borran solo los archivos comprimidos (.tar.gz/.zip); las carpetas descomprimidas (JDK, Maven…) no se tocan.",
                rutas: sobrantes, tamanosRutas: tamanos, ultimoUso: fechas.max(),
                categoria: .proyectos, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("archivebox", "Ya descomprimido",
                                "La carpeta extraída está al lado en la misma .runtime; el archivo comprimido suele ser solo la descarga inicial. Entra en «Liberar al máximo».")],
                nivel: .maximo, costes: [.descarga(bytes: tamanos.reduce(0, +))]))
        }
        return r
    }

    /// Lo que se añade a «Archivos olvidados» (va con lo de la categoría: «Orden en tu carpeta» no lo repite) y la nota de
    /// las bibliotecas de vídeo de una app que ya no está.
    func olvidadosAmpliado(_ c: Contexto, ofrecidas: [String]) -> [Elemento] {
        notaDeBibliotecasSinApp(c)
        return copiasDeRespaldoDeProyectos(c, ofrecidas: ofrecidas)
    }

    // MARK: - Salidas de .NET fuera de su proyecto

    /// Un obj/ o bin/ de .NET escrito fuera de su proyecto (`Indice.restauracionDeNuGet`: sin ningún .csproj al lado) y
    /// fuera de un repositorio. Los de dentro de un repositorio van con él en `proyectos`, que sabe cuándo se trabajó.
    /// Un bin/ sin su .csproj al lado va siempre aquí (Revisar, nunca marcado), haya solución o repositorio o no.
    static func esDotnetFuera(_ a: Artefacto, _ c: Contexto) -> Bool {
        guard a.tipo == .dotnet else { return false }
        let nombre = Rutas.nombre(a.ruta)
        guard nombre == "obj" || nombre == "bin" else { return false }
        let extensiones = AyudaDeEntregas.nombres(Rutas.padre(a.ruta)).map { ($0 as NSString).pathExtension.lowercased() }
        let deProyecto: Set<String> = ["csproj", "fsproj", "vbproj"]
        // Un bin/ que es de .NET solo por la restauración de NuGet de su obj/ hermano: no se sabe qué guardaste en él
        // (scripts, herramientas…), así que no va con el proyecto, donde un proyecto inactivo lo daría por Seguro.
        if nombre == "bin" { return !extensiones.contains(where: deProyecto.contains) }
        // Con el proyecto o la solución al lado, obj/ va con él.
        guard !extensiones.contains(where: { deProyecto.contains($0) || $0 == "sln" || $0 == "slnx" }) else { return false }
        return AyudaDeEntregas.repoPorEncima(a.ruta, c) == nil
    }

    /// Las salidas de MSBuild que un script escribió fuera del proyecto (--output, --artifacts-path,
    /// BaseIntermediateOutputPath): «build-2.1.0/{bin,obj}/<Proyecto>», «cache-compilacion/src/<Proyecto>/{bin,obj}»… Su
    /// proyecto se sabe por la restauración de NuGet (<Proyecto>.csproj.nuget.dgspec.json dice dónde está el .csproj).
    /// Por proyecto:
    /// - obj/ (intermedios y restauración): Seguro y marcado, si lleva 24 h sin cambios y nada trabaja en el proyecto;
    /// - bin/ (lo que se compiló): Revisar, nunca marcado. Si es de una versión anterior (la carpeta se llama
    ///   «<algo>-<versión>» y al lado hay una versión mayor) y lleva 7 días quieta, aparte y diciéndolo.
    /// Lo que cambió en las últimas 24 h no se ofrece: es una compilación en curso.
    func salidasDeDotnetFuera(_ c: Contexto) -> [Elemento] {
        let fuera = c.indice.artefactos.filter { Self.esDotnetFuera($0, c) }
        guard !fuera.isEmpty else { return [] }
        let salidas = Set(fuera.map(\.ruta))
        var soloSalidas: [String: Bool] = [:]
        var porContenedor: [String: (entero: Bool, rutas: [String])] = [:]
        for a in fuera {
            let k = AyudaDeEntregas.contenedor(de: a.ruta, salidas: salidas, &soloSalidas)
            porContenedor[k.ruta, default: (k.entero, [])].rutas.append(a.ruta)
        }

        // Cada contenedor, con el proyecto que lo compiló.
        struct Contenedor {
            let ruta: String
            let entero: Bool
            let objs: [String]
            let bins: [String]
            /// Los .csproj que restauró (según NuGet), estén o no.
            let proyectos: [String]
        }
        var porDueno: [String: [Contenedor]] = [:]
        var raicesDe: [String: [String]] = [:]
        for (ruta, k) in porContenedor {
            let objs = k.rutas.filter { Rutas.nombre($0) == "obj" }.sorted()
            let bins = k.rutas.filter { Rutas.nombre($0) == "bin" }.sorted()
            // Con el obj/ hermano de cada bin/ (que puede haberse quedado con su proyecto, junto a una solución o en un repo).
            let conHermanos = Set(objs + bins.map { Rutas.padre($0) + "/obj" })
            let proyectos = Array(Set(conHermanos.flatMap { AyudaDeEntregas.proyectosRestaurados($0) })).sorted()
            let raices = Array(Set(proyectos.filter { AyudaDeEntregas.tipo($0) == S_IFREG }.map { AyudaDeEntregas.raizDelProyecto($0) })).sorted()
            // Sin saber de qué proyecto es (no se pudo leer la restauración), cada contenedor va solo.
            let clave = !raices.isEmpty ? raices.joined(separator: "\n") : (proyectos.isEmpty ? "?" + ruta : "×" + proyectos.joined(separator: "\n"))
            porDueno[clave, default: []].append(Contenedor(ruta: ruta, entero: k.entero, objs: objs, bins: bins, proyectos: proyectos))
            raicesDe[clave] = raices
        }

        let ahora = Date()
        var r: [Elemento] = []
        for (clave, contenedores) in porDueno.sorted(by: { $0.key < $1.key }) {
            let raices = raicesDe[clave] ?? []
            let proyectos = Array(Set(contenedores.flatMap(\.proyectos))).sorted()
            let yaNoEsta = raices.isEmpty && !proyectos.isEmpty
            let nombresProyectos = proyectos.map { (Rutas.nombre($0) as NSString).deletingPathExtension }
            let dueno: String
            if !raices.isEmpty { dueno = Formato.listaCorta(raices.map { Rutas.nombre($0) }) }
            else if yaNoEsta { dueno = Formato.listaCorta(nombresProyectos) }
            else { dueno = Rutas.nombre(contenedores[0].ruta) }
            let uso: EnUso = raices.count == 1 ? .proyecto(nombre: dueno, raiz: raices[0])
                : .rutas(nombre: dueno, raiz: contenedores.count == 1 ? contenedores[0].ruta : Rutas.padre(contenedores[0].ruta))
            let actividad = raices.compactMap { AyudaDeEntregas.actividad(de: $0, c) }.max()
            var deActividad: [Motivo] = []
            if let actividad {
                let dias = ahora.timeIntervalSince(actividad) / 86400
                deActividad.append(dias > 30
                    ? .bien("moon.zzz.fill", "Proyecto inactivo", "No cambias el código de \(dueno) desde \(Formato.haceCuanto(actividad).lowercased()).")
                    : .info("pencil", "Proyecto activo", "Cambiaste el código de \(dueno) \(Formato.haceCuanto(actividad).lowercased())."))
            }
            if yaNoEsta {
                deActividad.append(.info("questionmark.folder.fill", "Su proyecto ya no está",
                    "Lo compiló \(Formato.listaCorta(proyectos.map { Formato.rutaCorta($0) })), que ya no existe."))
            }
            func horasSinCambios(_ rutas: [String]) -> (Date?, Double) {
                let cambio = rutas.compactMap { Self.ultimoCambioDentro($0, c) }.max()
                return (cambio, cambio.map { ahora.timeIntervalSince($0) / 3600 } ?? .infinity)
            }
            func donde(_ lista: [Contenedor]) -> String { Formato.listaCorta(lista.map { Formato.rutaCorta($0.ruta) }, maximo: 3) }

            // 1. Los intermedios (obj): con 24 h sin cambios, de cada contenedor.
            let conObj = contenedores.filter { !$0.objs.isEmpty && horasSinCambios($0.objs).1 >= 24 }
            let objs = conObj.flatMap(\.objs).map { URL(fileURLWithPath: $0) }
            if !objs.isEmpty {
                let (cambio, _) = horasSinCambios(conObj.flatMap(\.objs))
                let perdidos = AyudaDeEntregas.noSeRegenera(objs, c)
                var motivos: [Motivo] = [
                    .bien("arrow.triangle.2.circlepath", "Se regenera",
                          "Son intermedios de compilación de .NET (obj/): lo que dejó la restauración de NuGet (project.assets.json) y lo compilado a medias. Lo que entregas no está aquí."),
                    .bien("moon.zzz.fill", "Sin compilar desde \(Formato.haceCuanto(cambio).lowercased())",
                          "Nada cambió dentro desde \(Formato.haceCuanto(cambio).lowercased()): no se está compilando."),
                ] + deActividad
                if !perdidos.isEmpty { motivos.insert(AyudaDeEntregas.avisoDeNoRegenerables(perdidos), at: 0) }
                r.append(Elemento(
                    nombre: "Intermedios de .NET de \(dueno) fuera del proyecto",
                    detalle: ".NET · obj/ de \(Formato.listaCorta(nombresProyectos.isEmpty ? [dueno] : nombresProyectos, maximo: 4)), escritos fuera del proyecto en \(donde(conObj)).",
                    consecuencia: "Tu código no se toca. La próxima compilación que escriba ahí vuelve a restaurar los paquetes (de ~/.nuget/packages, sin internet si siguen ahí) y compila desde cero."
                        + (yaNoEsta ? " El proyecto que los creó ya no está, así que no le sirven a nadie." : "")
                        + (perdidos.isEmpty ? "" : " Ojo: dentro hay archivos que la compilación no crea (\(Formato.listaCorta(perdidos.map { Rutas.nombre($0) }))), que se perderían."),
                    rutas: objs, tamanosRutas: objs.map { Self.medida($0.path, c) }, ultimoUso: cambio, categoria: .proyectos,
                    riesgo: perdidos.isEmpty ? .seguro : .cuidado, seleccionado: perdidos.isEmpty, motivos: motivos, enUso: uso,
                    dueno: dueno, nivel: .normal, costes: [.recompilacion(proyecto: dueno)], cambioAnalizado: cambio))
            }

            // 2. Lo que se compiló (bin): de las versiones anteriores, aparte.
            var actuales: [Contenedor] = []
            var anteriores: [(contenedor: Contenedor, nueva: AyudaDeEntregas.MasNueva)] = []
            for k in contenedores where !k.bins.isEmpty {
                let (_, horas) = horasSinCambios(k.bins)
                guard horas >= 24 else { continue }
                // Una versión anterior: el contenedor entero se llama «<algo>-<versión>», al lado hay una mayor y nada
                // cambió dentro en 7 días.
                // La nueva no puede estar vacía (una carpeta creada para la siguiente versión no hace «anterior» a esta).
                if k.entero, let nueva = AyudaDeEntregas.versionMasNueva(que: k.ruta, admite: { !AyudaDeEntregas.nombres($0).filter { !$0.hasPrefix(".") }.isEmpty }),
                   let cambio = Self.ultimoCambioDentro(k.ruta, c), ahora.timeIntervalSince(cambio) >= 7 * 86400 {
                    anteriores.append((k, nueva))
                } else {
                    actuales.append(k)
                }
            }
            let consecuencia = yaNoEsta
                ? "Se borran los programas compilados (van a la Papelera). Su proyecto ya no está, así que no se pueden volver a compilar."
                : "Se borran los programas compilados (van a la Papelera). Se vuelven a crear compilando \(dueno), pero con el código de ahora: si eran de otra versión, esa no vuelve."
            if !actuales.isEmpty {
                let bins = actuales.flatMap(\.bins).map { URL(fileURLWithPath: $0) }
                let (cambio, _) = horasSinCambios(actuales.flatMap(\.bins))
                let perdidos = AyudaDeEntregas.noSeRegenera(bins, c)
                var motivos: [Motivo] = deActividad + [.info("shippingbox.fill", "Lo que compilaste",
                    "No son intermedios: son los programas y librerías que salieron de la compilación (bin/). Por eso no los marco, ni con «Liberar al máximo»: bórralos tú si ya no los necesitas.")]
                // Un bin/ dentro de la carpeta del proyecto, pero sin su .csproj al lado (junto a la solución, en artifacts/…):
                // solo lo delata el obj/ de al lado, así que puede tener cosas tuyas.
                let enElProyecto = actuales.allSatisfy { k in raices.contains { k.ruta == $0 || k.ruta.hasPrefix($0 + "/") } }
                if enElProyecto {
                    motivos.append(.info("questionmark.folder.fill", "Sin su .csproj al lado",
                        "Lo reconozco como compilación de .NET por la restauración de NuGet del obj/ de al lado, no por su proyecto: mira qué hay dentro antes de borrarlo (puede tener scripts o herramientas tuyas)."))
                }
                if !perdidos.isEmpty { motivos.insert(AyudaDeEntregas.avisoDeNoRegenerables(perdidos), at: 0) }
                r.append(Elemento(
                    nombre: enElProyecto ? "Salidas de .NET de \(dueno) (bin/ sin su .csproj al lado)" : "Salidas de .NET de \(dueno) fuera del proyecto",
                    detalle: ".NET · bin/ de \(Formato.listaCorta(nombresProyectos.isEmpty ? [dueno] : nombresProyectos, maximo: 4)) en \(donde(actuales)).",
                    consecuencia: consecuencia, rutas: bins, tamanosRutas: bins.map { Self.medida($0.path, c) }, ultimoUso: cambio,
                    categoria: .proyectos, riesgo: perdidos.isEmpty ? .revisar : .cuidado, motivos: motivos, enUso: uso, dueno: dueno,
                    nivel: .nunca, costes: [.recompilacion(proyecto: dueno), .borraSalidas(proyecto: dueno)], cambioAnalizado: cambio))
            }
            if !anteriores.isEmpty {
                let bins = anteriores.flatMap(\.contenedor.bins).map { URL(fileURLWithPath: $0) }
                let (cambio, _) = horasSinCambios(anteriores.flatMap(\.contenedor.bins))
                let perdidos = AyudaDeEntregas.noSeRegenera(bins, c)
                let lista = anteriores.map { "\(Rutas.nombre($0.contenedor.ruta)) (ya está \(Rutas.nombre($0.nueva.ruta)))" }
                var motivos: [Motivo] = [.info("clock.arrow.circlepath", "Hay una versión más nueva",
                    "\(Formato.listaCorta(lista, maximo: 4)). Lo compilado de una versión anterior solo sirve si aún la pruebas o la comparas con la nueva.")]
                    + deActividad
                    + [.info("calendar", "Sin cambios", "Nada cambió dentro desde \(Formato.haceCuanto(cambio).lowercased()).")]
                if !perdidos.isEmpty { motivos.insert(AyudaDeEntregas.avisoDeNoRegenerables(perdidos), at: 0) }
                r.append(Elemento(
                    nombre: anteriores.count == 1 ? "Versión anterior de lo que compilaste: \(Rutas.nombre(anteriores[0].contenedor.ruta))"
                                                  : "Versiones anteriores de lo que compilaste de \(dueno) (\(anteriores.count))",
                    detalle: ".NET · bin/ de \(Formato.listaCorta(anteriores.map { "\(Rutas.nombre($0.contenedor.ruta)) (\($0.nueva.esta))" }, maximo: 4)) en \(Formato.rutaCorta(Rutas.padre(anteriores[0].contenedor.ruta))).",
                    consecuencia: consecuencia, rutas: bins, tamanosRutas: bins.map { Self.medida($0.path, c) }, ultimoUso: cambio,
                    categoria: .proyectos, riesgo: perdidos.isEmpty ? .revisar : .cuidado, motivos: motivos, enUso: uso, dueno: dueno,
                    nivel: .nunca, costes: [.borraSalidas(proyecto: dueno)], cambioAnalizado: cambio))
            }
        }
        return r
    }

    // MARK: - Versiones anteriores de lo que publicaste

    /// Las carpetas de entrega de una versión anterior: «entrega-2.0.0», «release-1.3», «dist-1.2.0-win-x64»… (el nombre
    /// de una entrega o publicación, más una versión), con una versión mayor de la misma serie al lado («entrega-2.1.0»; las
    /// de prueba, como «-staging» o «-rc1», no cuentan como más nuevas) y 7 días sin cambios. Solo con lo que se distribuye
    /// (programas, paquetes, zips, carpetas por plataforma) y nada de código. Se ofrecen sus paquetes, y se quedan el zip del
    /// código fuente, las notas y las verificaciones. Revisar, nunca marcado: si ya publicaste esa versión, sobra.
    func entregasAnteriores(_ c: Contexto, tomadas: Set<String>) -> [Elemento] {
        let home = Rutas.home.path
        // Las carpetas que contienen una compilación ya van con su proyecto (o con las salidas de .NET de fuera).
        var conCompilacion = Set<String>()
        for a in c.indice.artefactos {
            var p = Rutas.padre(a.ruta)
            while p.count > home.count, conCompilacion.insert(p).inserted { p = Rutas.padre(p) }
        }
        let artefactos = Set(c.indice.artefactos.map(\.ruta))
        // La versión más nueva tiene que ser una entrega de verdad: con algo que se distribuye y 24 h sin cambios (una
        // carpeta vacía o a medias para la siguiente no hace «anterior» a la de ahora, que puede ser lo único entregado).
        let entregaHecha = { (n: String) -> Bool in
            AyudaDeEntregas.tieneDistribuibles(n) && !AyudaDeEntregas.partesDeEntrega(n).van.isEmpty
                && (Self.ultimoCambioDentro(n, c).map { Date().timeIntervalSince($0) >= 86400 } ?? false)
        }
        var ofrecidas: [String] = []
        var r: [Elemento] = []
        for ruta in c.indice.carpetas.keys.sorted() where AyudaDeEntregas.enTusCarpetas(ruta) {
            let nombre = Rutas.nombre(ruta)
            guard nombre.contains("."), let v = VersionDeCarpeta(nombre), v.esDeEntrega else { continue }
            let u = URL(fileURLWithPath: ruta)
            let contenido = c.indice.contenido(de: [u])
            guard !conCompilacion.contains(ruta), !artefactos.contains(ruta), !Totales.dentroDe(ruta, artefactos),
                  !tomadas.contains(ruta), !Totales.dentroDe(ruta, tomadas), !ofrecidas.contains(where: { ruta.hasPrefix($0 + "/") }),
                  let nueva = AyudaDeEntregas.versionMasNueva(que: ruta, admite: entregaHecha),
                  AyudaDeEntregas.repoPorEncima(ruta, c) == nil, !AyudaDeEntregas.enNube(ruta),
                  c.indice.repos(dentro: [u]).isEmpty,
                  // Sin código, ni documentos, fotos, bases de datos o llaves: una entrega a un cliente o un trabajo
                  // entregado (el informe, los datos, el acta) puede ser la única copia.
                  contenido.codigo == 0, contenido.documentos == 0, contenido.fotos == 0, contenido.bases == 0, !contenido.esPersonal,
                  c.indice.sensibles(dentro: [u]).isEmpty, c.indice.noRegenerables(dentro: [u]).isEmpty,
                  let cambio = Self.ultimoCambioDentro(ruta, c), Date().timeIntervalSince(cambio) >= 7 * 86400 else { continue }
            let partes = AyudaDeEntregas.partesDeEntrega(ruta)
            guard !partes.van.isEmpty, AyudaDeEntregas.tieneDistribuibles(ruta) else { continue }
            ofrecidas.append(ruta)
            let rutas = partes.van.map { URL(fileURLWithPath: ruta + "/" + $0) }
            let deFuente = partes.quedan.filter(AyudaDeEntregas.esDelCodigoFuente)
            var queda = ""
            if !partes.quedan.isEmpty {
                queda = " Se \(partes.quedan.count == 1 ? "queda" : "quedan") \(Formato.listaCorta(partes.quedan, maximo: 4))"
                    + (deFuente.isEmpty ? "." : ": el código de esa versión no se pierde.")
            }
            r.append(Elemento(
                nombre: "Versión anterior de lo que publicaste: \(nombre)",
                detalle: "Los paquetes de la versión \(v.texto) (\(Formato.listaCorta(partes.van, maximo: 4))) en \(Formato.rutaCorta(ruta)). Al lado está \(Rutas.nombre(nueva.ruta)), \(nueva.esta).",
                consecuencia: "Se borran los programas y paquetes de la versión \(v.texto) (van a la Papelera).\(queda) Si alguien todavía usa esa versión o la necesitas para comparar, guárdala.",
                rutas: rutas, tamanosRutas: rutas.map { Self.medida($0.path, c) }, ultimoUso: cambio, categoria: .proyectos,
                riesgo: .revisar,
                motivos: [.info("clock.arrow.circlepath", "Hay una versión más nueva",
                                "Al lado está \(Rutas.nombre(nueva.ruta)) (\(nueva.version)). Si ya entregaste o publicaste la \(v.texto), sus paquetes sobran; si no, guárdala."),
                          .info("calendar", "Sin cambios", "Nada cambió dentro desde \(Formato.haceCuanto(cambio).lowercased()).")],
                enUso: .rutas(nombre: nombre, raiz: ruta), nivel: .nunca, cambioAnalizado: cambio))
        }
        return r
    }

    // MARK: - Carpeta que ya está en su zip

    /// En una carpeta de entregas (dist/, out/, release/, «entrega-2.0.0»…), una carpeta que es lo mismo que el zip de al
    /// lado («win-x64» y «MiApp-win-x64.zip»): los mismos archivos, con el mismo nombre, tamaño y CRC-32, según la lista del
    /// zip (su directorio central, sin descomprimirlo). Se ofrece la carpeta (el zip es lo que se entrega), en Revisar y
    /// nunca marcada, con 7 días sin cambios, fuera de repositorios y de las carpetas de compilación de un proyecto
    /// (dist/ de una web ya va con su proyecto). Si el zip se borra en la misma limpieza, la carpeta no se toca.
    func copiasDescomprimidas(_ c: Contexto, tomadas: Set<String>) -> [Elemento] {
        let artefactos = Set(c.indice.artefactos.map(\.ruta))
        let nombresDeEntrega: Set<String> = ["dist", "out", "release", "releases", "deliverables", "entrega", "entregas", "publicar",
                                             "publish", "salida", "paquetes", "installers", "instaladores"]
        let semana = Date().addingTimeInterval(-7 * 86400)
        var r: [Elemento] = []
        for carpeta in c.indice.carpetas.keys.sorted() where AyudaDeEntregas.enTusCarpetas(carpeta) {
            let nombre = Rutas.nombre(carpeta)
            guard nombresDeEntrega.contains(nombre.lowercased()) || (nombre.contains(".") && VersionDeCarpeta(nombre)?.esDeEntrega == true)
            else { continue }
            guard !artefactos.contains(carpeta), !Totales.dentroDe(carpeta, artefactos), !tomadas.contains(carpeta),
                  !Totales.dentroDe(carpeta, tomadas), AyudaDeEntregas.repoPorEncima(carpeta, c) == nil, !AyudaDeEntregas.enNube(carpeta)
            else { continue }
            let hijos = AyudaDeEntregas.nombres(carpeta).filter { !$0.hasPrefix(".") }
            let carpetas = hijos.filter { AyudaDeEntregas.tipo(carpeta + "/" + $0) == S_IFDIR }
            var usadas = Set<String>()
            for zip in hijos where zip.lowercased().hasSuffix(".zip") {
                let rutaZip = carpeta + "/" + zip
                var st = stat()
                guard lstat(rutaZip, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size >= 1_000_000,
                      Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)) <= semana else { continue }
                let base = String(zip.dropLast(4))
                for d in carpetas where !usadas.contains(d) && (base == d || base.hasSuffix("-" + d) || base.hasSuffix("_" + d) || base.hasSuffix(" " + d)) {
                    let rutaD = carpeta + "/" + d
                    guard !tomadas.contains(rutaD), let cambio = Self.ultimoCambioDentro(rutaD, c), cambio <= semana,
                          let n = AyudaDeEntregas.mismosArchivos(carpeta: rutaD, zip: rutaZip),
                          let huella = Huella.parcial(URL(fileURLWithPath: rutaZip), tamano: Int64(st.st_size)) else { continue }
                    let u = URL(fileURLWithPath: rutaD)
                    r.append(Elemento(
                        nombre: "Copia descomprimida de \(zip)",
                        detalle: "La carpeta \(d) de \(Formato.rutaCorta(carpeta)) tiene los mismos \(Formato.numero(n)) archivos, con el mismo nombre, tamaño y contenido (CRC-32), que \(zip), que está al lado.",
                        consecuencia: "Se borra la carpeta \(d) (va a la Papelera); \(zip) se queda y, si la necesitas, la recuperas descomprimiéndolo. Si pruebas el programa directamente desde esa carpeta, guárdala.",
                        rutas: [u], tamanosRutas: [Self.medida(rutaD, c)], ultimoUso: cambio, categoria: .proyectos, riesgo: .revisar,
                        motivos: [.info("archivebox.fill", "Ya está en el zip",
                                        "Comparé la lista de \(zip) (el nombre, el tamaño y el CRC-32 del contenido de cada uno de sus \(Formato.numero(n)) archivos) con la carpeta: coinciden todos. Antes de borrarla, el zip tiene que seguir ahí y sin cambios."),
                                  .info("calendar", "Sin cambios", "Nada cambió en la carpeta desde \(Formato.haceCuanto(cambio).lowercased()).")],
                        enUso: .rutas(nombre: d, raiz: rutaD), nivel: .nunca, cambioAnalizado: cambio,
                        copiasExigidas: [CopiaExigida(ruta: rutaZip, de: rutaD, tamano: Int64(st.st_size), huella: huella)]))
                    usadas.insert(d)
                    break
                }
            }
        }
        return r
    }

    // MARK: - Copias de respaldo de un proyecto

    /// Copias de un proyecto hechas a mano o con el Finder («web-respaldo-2026-09-01», «web copia», «web backup»,
    /// «respaldo-web»…) cuyo original sigue al lado: una carpeta hermana con la misma marca de proyecto (Package.swift,
    /// package.json, un .csproj…) en la que está al menos el 80 % de los archivos de la copia con el mismo nombre, tamaño y
    /// fecha de modificación (sin contar lo que se regenera, como .build o node_modules). Con 14 días sin cambios. Revisar,
    /// nunca marcada, diciendo qué tiene la copia que el original no: eso es lo que se perdería.
    func copiasDeRespaldoDeProyectos(_ c: Contexto, ofrecidas: [String]) -> [Elemento] {
        let tomadas = Set(ofrecidas)
        let artefactos = Set(c.indice.artefactos.map(\.ruta))
        var vistas: [String] = []
        var r: [Elemento] = []
        for ruta in c.indice.carpetas.keys.sorted() where AyudaDeEntregas.enTusCarpetas(ruta) {
            let nombre = Rutas.nombre(ruta)
            guard AyudaDeEntregas.pareceRespaldo(nombre), !tomadas.contains(ruta), !Totales.dentroDe(ruta, tomadas),
                  !artefactos.contains(ruta), !Totales.dentroDe(ruta, artefactos), !vistas.contains(where: { ruta.hasPrefix($0 + "/") }),
                  AyudaDeEntregas.tipo(ruta) == S_IFDIR, AyudaDeEntregas.repoPorEncima(ruta, c) == nil, !AyudaDeEntregas.enNube(ruta),
                  // Una copia con un repositorio dentro puede tener commits, ramas o un stash que el original no tiene.
                  c.indice.repos(dentro: [URL(fileURLWithPath: ruta)]).isEmpty,
                  let cambio = Self.ultimoCambioDentro(ruta, c), Date().timeIntervalSince(cambio) >= 14 * 86400 else { continue }
            let marcas = AyudaDeEntregas.marcasDeProyecto(ruta)
            guard !marcas.isEmpty else { continue }
            let padre = Rutas.padre(ruta)
            var mejor: (ruta: String, comparacion: AyudaDeEntregas.Comparacion)?
            for n in AyudaDeEntregas.nombres(padre) where n != nombre && !n.hasPrefix(".") && !AyudaDeEntregas.pareceRespaldo(n) {
                let otra = padre + "/" + n
                guard AyudaDeEntregas.tipo(otra) == S_IFDIR, !AyudaDeEntregas.marcasDeProyecto(otra).isDisjoint(with: marcas),
                      let comp = AyudaDeEntregas.comparar(copia: ruta, original: otra, artefactos: artefactos),
                      comp.iguales >= 3, comp.parecido >= 0.8 else { continue }
                if mejor == nil || comp.parecido > mejor!.comparacion.parecido { mejor = (otra, comp) }
            }
            guard let elegido = mejor else { continue }
            let (original, comp) = (elegido.ruta, elegido.comparacion)
            vistas.append(ruta)
            let nombreOriginal = Rutas.nombre(original)
            let diferencias = comp.soloEnCopia + comp.distintos
            func conTamano(_ d: (ruta: String, bytes: Int64, enlace: Bool)) -> String {
                d.enlace ? "\(d.ruta) (un enlace: lo que señala no se toca)" : d.bytes >= 1_000_000 ? "\(d.ruta) (\(Formato.bytes(d.bytes)))" : d.ruta
            }
            // Lo que no se comparó (dependencias y compilaciones de la copia): se dice, porque se va con ella.
            let sinComparar = comp.sinComparar.isEmpty ? "" : Formato.listaCorta(comp.sinComparar.map { $0 + "/" }, maximo: 4)
            let variasSin = comp.sinComparar.count > 1
            var motivos: [Motivo] = [.info("doc.on.doc.fill", "Copia de \(nombreOriginal)",
                "\(Formato.numero(comp.iguales)) de \(Formato.numero(comp.total)) archivos son iguales que en \(Formato.rutaCorta(original)): mismo nombre, tamaño y fecha de modificación"
                    + (sinComparar.isEmpty ? "." : " (sin contar \(sinComparar), que \(variasSin ? "se regeneran" : "se regenera") al instalar o compilar)."))]
            if !diferencias.isEmpty {
                var partes: [String] = []
                if !comp.soloEnCopia.isEmpty { partes.append("Solo están en la copia: \(Formato.listaCorta(comp.soloEnCopia.map(conTamano), maximo: 5)).") }
                if !comp.distintos.isEmpty { partes.append("Distintos del original: \(Formato.listaCorta(comp.distintos.map(conTamano), maximo: 5)).") }
                motivos.append(.aviso("exclamationmark.bubble.fill", "Lo que solo tiene la copia",
                    partes.joined(separator: " ") + " Si lo quieres, sácalo antes de borrarla."))
            }
            if !comp.faltan.isEmpty {
                motivos.append(.info("arrow.uturn.forward", "El original va por delante",
                    "\(nombreOriginal) tiene \(Formato.numero(comp.faltan.count)) \(comp.faltan.count == 1 ? "archivo" : "archivos") que la copia no tiene (\(Formato.listaCorta(comp.faltan, maximo: 3))): siguen ahí."))
            }
            motivos.append(.info("calendar", "Sin cambios", "Nada cambió dentro de la copia desde \(Formato.haceCuanto(cambio).lowercased())."))
            let n = diferencias.count
            // El original tiene que seguir ahí al limpiar (y no irse en la misma limpieza): se vigila su marca de proyecto.
            let exigida: [CopiaExigida] = AyudaDeEntregas.archivoDeMarca(original).flatMap { m in
                var st = stat()
                guard lstat(m, &st) == 0, let h = Huella.parcial(URL(fileURLWithPath: m), tamano: Int64(st.st_size)) else { return nil }
                return [CopiaExigida(ruta: m, de: ruta, tamano: Int64(st.st_size), huella: h)]
            } ?? []
            r.append(Elemento(
                nombre: "Copia de respaldo de \(nombreOriginal): \(nombre)",
                detalle: (n == 0 ? "Copia idéntica de \(nombreOriginal), que está al lado: sus \(Formato.numero(comp.total)) archivos son iguales"
                                 : "Copia de \(nombreOriginal), que está al lado: igual salvo \(n) \(n == 1 ? "archivo" : "archivos") (\(Formato.listaCorta(diferencias.map(\.ruta), maximo: 3)))")
                    + (sinComparar.isEmpty ? "." : ", sin contar \(sinComparar) (\(variasSin ? "se regeneran" : "se regenera"))."),
                consecuencia: "Se borra la copia entera (va a la Papelera). \(nombreOriginal) no se toca."
                    + (n == 0 ? "" : " Lo que solo está en la copia (\(Formato.listaCorta(diferencias.map(\.ruta), maximo: 3))) se va con ella: sácalo antes si lo quieres.")
                    + (sinComparar.isEmpty ? "" : " También \(variasSin ? "se van" : "se va") \(sinComparar) de la copia, que no comparé."),
                rutas: [URL(fileURLWithPath: ruta)], tamanosRutas: [Self.medida(ruta, c)], ultimoUso: cambio, categoria: .olvidados,
                riesgo: .revisar, motivos: motivos, enUso: .rutas(nombre: nombre, raiz: ruta), dueno: "Tus carpetas", nivel: .nunca,
                cambioAnalizado: cambio, copiasExigidas: exigida))
        }
        return r
    }

    /// Está dentro de una carpeta que se llama como una copia («web-respaldo-2026-09-01», «web copia», «web-backup»…), por
    /// debajo de tu carpeta personal: de un grupo de copias idénticas, la de ahí es la que sobra (`puntaje`).
    static func enCarpetaDeRespaldo(_ ruta: String) -> Bool {
        let home = Rutas.home.path
        guard ruta.hasPrefix(home + "/") else { return false }
        return ruta.dropFirst(home.count + 1).split(separator: "/").dropLast().contains { AyudaDeEntregas.pareceRespaldo(String($0)) }
    }

    // MARK: - Bibliotecas de vídeo sin su app

    /// Una biblioteca de iMovie o de Final Cut Pro en tus carpetas sin la app instalada: no se puede abrir, y su vídeo
    /// original (Original Media) puede ser la única copia. Solo se informa (nota en «Archivos olvidados»); sus renders ya
    /// se ofrecen en «Cachés de aplicaciones». Nunca se ofrece borrarla.
    func notaDeBibliotecasSinApp(_ c: Contexto) {
        let apps: [(ext: String, app: String, ids: [String], tienda: String)] = [
            ("imovielibrary", "iMovie", ["com.apple.imovieapp"], "es gratis en la App Store"),
            ("fcpbundle", "Final Cut Pro", ["com.apple.finalcut", "com.apple.finalcutapp"], "está en la App Store"),
        ]
        for ruta in c.indice.carpetas.keys.sorted() where AyudaDeEntregas.enTusCarpetas(ruta) {
            let ext = (ruta as NSString).pathExtension.lowercased()
            guard let a = apps.first(where: { $0.ext == ext }), !a.ids.contains(where: c.apps.bundleIDs.contains),
                  !c.indice.notas.contains(where: { $0.ruta == ruta }) else { continue }
            let eventos = AyudaDeEntregas.nombres(ruta).map { ruta + "/" + $0 }.filter { AyudaDeEntregas.tipo($0) == S_IFDIR }
            let originales = eventos.map { $0 + "/Original Media" }.filter { AyudaDeEntregas.tipo($0) == S_IFDIR }
            let renders = eventos.map { $0 + "/Render Files" }.filter { AyudaDeEntregas.tipo($0) == S_IFDIR }
            let bytes = Self.medida(ruta, c)
            let deOriginales = originales.reduce(Int64(0)) { $0 + Tamanos.recorriendo($1) }
            let deRenders = renders.reduce(Int64(0)) { $0 + Tamanos.recorriendo($1) }
            guard bytes >= minimo else { continue }
            let biblioteca = (Rutas.nombre(ruta) as NSString).deletingPathExtension
            var texto = "«\(biblioteca)» está en \(Formato.rutaCorta(Rutas.padre(ruta))) y ocupa \(Formato.bytes(bytes))"
            if deOriginales > 0 {
                texto += ": \(Formato.bytes(deOriginales)) son el vídeo que importaste (Original Media), que puede ser tu única copia"
                if deRenders > 0 { texto += ", y \(Formato.bytes(deRenders)) son renders, que ya te ofrezco en «Cachés de aplicaciones»" }
            }
            texto += ". \(a.app) no está instalado, así que no se puede abrir: para ver o editar el proyecto, vuelve a instalarlo (\(a.tienda)); si solo quieres los vídeos, cópialos de Original Media. No la ofrezco para borrar."
            c.indice.notas.append(NotaGrande(categoria: .olvidados, titulo: "Biblioteca de \(a.app) sin \(a.app)", texto: texto,
                                             ruta: ruta, bytes: bytes))
        }
    }

    // MARK: - Copias idénticas que son parte de un programa

    /// Junta en un elemento las uniones de copias idénticas que están dentro de un mismo programa, SDK o runtime
    /// (`RaicesDeProgramas`): borrar una de esas copias rompería el programa, así que solo se unen (Seguro, solo con
    /// «Liberar al máximo»). Cada grupo se comprueba y se une como si fuera solo (`Clonador.unir`).
    func unionesPorPrograma(_ grupos: [String: [Elemento]], _ programas: RaicesDeProgramas) -> [Elemento] {
        var r: [Elemento] = []
        for (raiz, lista) in grupos.sorted(by: { $0.key < $1.key }) {
            let uniones = lista.compactMap { el -> Clonacion? in
                if case .clonar(let u) = el.accion { return u }
                return nil
            }
            guard let primera = uniones.first, uniones.count == lista.count else { r += lista; continue }
            let que = programas.queEs(raiz)
            guard lista.count > 1 else {
                var el = lista[0]
                el.motivos.append(.info("gearshape.2.fill", "Parte de \(que)",
                    "Está dentro de \(Formato.rutaCorta(raiz)), que es \(que): borrar una copia lo rompería, así que solo te ofrezco unirlas."))
                r.append(el)
                continue
            }
            let ahorro = lista.reduce(Int64(0)) { $0 + ($1.tamanoFijo ?? 0) }
            let archivos = lista.flatMap { $0.prevision?.archivos ?? [] }
            let ocupan = lista.reduce(Int64(0)) { $0 + ($1.prevision?.ocupan ?? 0) }
            let total = uniones.reduce(0) { $0 + $1.copias.count + 1 }
            r.append(Elemento(
                nombre: "Unir copias idénticas dentro de \(Rutas.nombre(raiz)) (\(Formato.numero(lista.count)) grupos)",
                detalle: "\(Formato.numero(total)) archivos idénticos, en \(Formato.numero(lista.count)) grupos, dentro de \(Formato.rutaCorta(raiz)), que es \(que).",
                consecuencia: "No se borra nada ni cambia ninguna ruta: cada archivo sigue en su sitio, con su contenido byte a byte, así que \(que) funciona igual; el disco guarda el contenido de cada grupo una sola vez y ahorras unos \(Formato.bytes(ahorro)). Si después se actualiza y cambia uno, macOS copia solo lo que cambia. Comparar las copias tarda un poco, y si haces copias de seguridad con Time Machine, se vuelven a copiar una vez.",
                rutas: lista.flatMap(\.rutas), tamanoFijo: ahorro, ultimoUso: lista.compactMap(\.ultimoUso).max(),
                categoria: .duplicados, riesgo: .seguro, seleccionado: true,
                accion: .clonar(Clonacion(original: primera.original, copias: primera.copias, otros: Array(uniones.dropFirst()))),
                motivos: [
                    .bien("square.on.square", "Sin borrar nada",
                          "Los \(Formato.numero(total)) archivos siguen en su sitio, con su nombre, sus permisos y sus fechas; solo dejan de ocupar el disco por separado (un clon de APFS, lo mismo que hace «Duplicar» en el Finder)."),
                    .info("gearshape.2.fill", "Parte de \(que)",
                          "Son archivos de \(que): el programa los busca justo ahí y borrar una copia lo rompería, así que no te ofrezco borrar ninguna, solo unirlas."),
                    .info("checkmark.seal.fill", "Idénticas",
                          "Comparé el contenido completo de cada grupo (SHA-256). Antes de cambiar cada copia la vuelvo a comparar byte a byte, y si algo cambió desde ahora, no la toco."),
                ],
                dueno: Rutas.nombre(raiz), nivel: .maximo, costes: [.tiempoCPU],
                prevision: PrevisionCompresion(archivos, ocupan: ocupan, requiere: raiz)))
        }
        return r
    }
}

/// Las carpetas de programas, SDK y runtimes que hay en tu carpeta, reconocidos por lo que tienen dentro (un .NET de
/// «dotnet-install.sh»: el ejecutable dotnet con host/fxr y sdk/ o shared/Microsoft.NETCore.App; un JDK; un Node; un
/// Python; un Go), y las partes de un programa por su ruta (dentro de una .app o un .framework, o de una carpeta sdk/,
/// packs/, runtimes/ o toolchains/). Un archivo de ahí dentro lo busca su programa justo en ese sitio. Guarda lo que ya
/// miró, carpeta por carpeta.
final class RaicesDeProgramas {
    private var firmas: [String: String?] = [:]
    private var descripciones: [String: String] = [:]
    private static let paquetes: Set<String> = ["app", "framework", "xcframework", "bundle", "plugin", "appex", "xpc", "kext",
                                                "systemextension"]
    private static let partes: Set<String> = ["sdk", "sdks", "packs", "runtimes", "toolchains"]

    /// Qué es (para los textos): «un SDK de .NET», «una app»…
    func queEs(_ raiz: String) -> String { descripciones[raiz] ?? "un programa" }

    /// La carpeta del programa del que es parte esa ruta, o nil.
    func raiz(de ruta: String) -> String? {
        let home = Rutas.home.path
        guard ruta.hasPrefix(home + "/") else { return nil }
        let componentes = Array(ruta.dropFirst(home.count + 1).split(separator: "/").dropLast())
        var prefijo = home
        for (i, parte) in componentes.enumerated() {
            prefijo += "/" + parte
            let ext = (String(parte) as NSString).pathExtension.lowercased()
            // Una .app de verdad tiene Contents/ (o, la de iOS, su Info.plist): «shared/Microsoft.NETCore.App» no lo es.
            if ext == "app" && !(i + 1 < componentes.count && componentes[i + 1] == "Contents")
                && AyudaDeEntregas.tipo(prefijo + "/Info.plist") != S_IFREG { continue }
            if Self.paquetes.contains(ext) {
                descripciones[prefijo] = ext == "app" ? "una app" : "un componente de un programa (.\(ext))"
                return prefijo
            }
        }
        var actual = Rutas.padre(ruta)
        while actual.count > home.count && actual.hasPrefix(home + "/") {
            if let que = firma(actual) {
                descripciones[actual] = que
                return actual
            }
            actual = Rutas.padre(actual)
        }
        prefijo = home
        for parte in componentes {
            prefijo += "/" + parte
            if Self.partes.contains(parte.lowercased()) {
                descripciones[prefijo] = "parte de un SDK o de un runtime"
                return prefijo
            }
        }
        return nil
    }

    /// La raíz de todas esas rutas si es la misma (y la tienen todas), o nil.
    func raizComun(_ rutas: [String]) -> String? {
        guard let primera = rutas.first.flatMap(raiz(de:)) else { return nil }
        return rutas.dropFirst().allSatisfy { raiz(de: $0) == primera } ? primera : nil
    }

    private func firma(_ d: String) -> String? {
        if let ya = firmas[d] { return ya }
        let t = AyudaDeEntregas.tipo
        var r: String?
        // Las carpetas de tu casa en las que pip --user o uv dejan comandos (~/.local) no son un programa.
        if Rutas.nombre(d) == ".local" {
            r = nil
        } else if t(d + "/dotnet") == S_IFREG && t(d + "/host/fxr") == S_IFDIR
                    && (t(d + "/sdk") == S_IFDIR || t(d + "/shared/Microsoft.NETCore.App") == S_IFDIR) {
            r = "un SDK de .NET"
        } else if t(d + "/bin/java") == S_IFREG && (t(d + "/lib/modules") == S_IFREG || t(d + "/jre") == S_IFDIR) {
            r = "un JDK de Java"
        } else if t(d + "/bin/node") == S_IFREG && t(d + "/lib/node_modules") == S_IFDIR {
            r = "un Node.js"
        } else if t(d + "/bin/go") == S_IFREG && t(d + "/pkg/tool") == S_IFDIR {
            r = "un Go"
        } else if let p = t(d + "/bin/python3"), p == S_IFREG || p == S_IFLNK,
                  AyudaDeEntregas.nombres(d + "/lib").contains(where: { $0.hasPrefix("python3.") }) {
            r = "un Python"
        }
        firmas[d] = .some(r)
        return r
    }
}

/// «entrega-2.1.0», «publish-2.2.0-win-x64», «build-core-2.2.0», «entrega-2.2.1-staging»: el nombre, la versión y la
/// serie a la que pertenece (el nombre sin la versión; un «-win-x64» es otra serie, un «-staging» o «-rc1» no).
fileprivate struct VersionDeCarpeta {
    let prefijo: String
    let numeros: [Int]
    let texto: String
    /// «staging», «rc1», «ci»…: una versión de prueba de esa versión.
    let calificador: String?
    let serie: String

    private static let patron = try? NSRegularExpression(pattern: #"^(.+?)[-_ ]v?(\d+(?:\.\d+){1,3})(?:[-_ .](.+))?$"#,
                                                         options: [.caseInsensitive])
    private static let deprueba = try? NSRegularExpression(
        pattern: #"^(staging|ci|rc\d*|beta\d*|alpha\d*|preview\d*|tmp|temp|draft|wip|nightly|dev|snapshot|prueba|pruebas|test)$"#,
        options: [.caseInsensitive])
    /// Lo que dice que una carpeta es lo que se compila, se publica o se entrega (una palabra del nombre, sin la versión).
    private static let palabras: Set<String> = [
        "build", "builds", "publish", "publicacion", "publicación", "entrega", "entregas", "release", "releases", "dist",
        "out", "output", "artifacts", "artefactos", "paquete", "paquetes", "package", "packages", "delivery", "deliverables",
        "deploy", "compilacion", "compilación", "compilado", "cache", "salida", "salidas", "installer", "installers",
        "instalador", "instaladores", "setup", "distribucion", "distribución",
    ]

    init?(_ nombre: String) {
        let ns = nombre as NSString
        guard let m = Self.patron?.firstMatch(in: nombre, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func grupo(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        guard let prefijo = grupo(1), let version = grupo(2) else { return nil }
        self.prefijo = prefijo
        texto = version
        numeros = version.split(separator: ".").compactMap { Int($0) }
        let resto = grupo(3)
        if let resto, let p = Self.deprueba, p.firstMatch(in: resto, range: NSRange(location: 0, length: (resto as NSString).length)) != nil {
            calificador = resto.lowercased()
            serie = prefijo.lowercased() + "|"
        } else {
            calificador = nil
            serie = prefijo.lowercased() + "|" + (resto?.lowercased() ?? "")
        }
    }

    var esDeEntrega: Bool {
        prefijo.lowercased().split(whereSeparator: { "-_ .".contains($0) }).contains { Self.palabras.contains(String($0)) }
    }

    /// a > b, comparando cada número (lo que falta cuenta como 0).
    static func mayor(_ a: [Int], _ b: [Int]) -> Bool {
        for i in 0..<max(a.count, b.count) {
            let (x, y) = (i < a.count ? a[i] : 0, i < b.count ? b[i] : 0)
            if x != y { return x > y }
        }
        return false
    }
}

/// Lo que comparten estas reglas: mirar sin seguir enlaces ni abrir nada que no haga falta.
fileprivate enum AyudaDeEntregas {
    static func tipo(_ ruta: String) -> mode_t? {
        var st = stat()
        return lstat(ruta, &st) == 0 ? (st.st_mode & S_IFMT) : nil
    }

    static func nombres(_ carpeta: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? []).sorted()
    }

    /// En tus carpetas (Descargas, Documentos…), fuera de Library y de las carpetas ocultas.
    static func enTusCarpetas(_ ruta: String) -> Bool {
        let home = Rutas.home.path
        guard ruta.hasPrefix(home + "/") else { return false }
        let rel = ruta.dropFirst(home.count + 1)
        return !rel.hasPrefix("Library/") && rel != "Library" && !rel.hasPrefix(".") && !rel.contains("/.")
    }

    /// Dentro de una carpeta que sincroniza otra nube (Dropbox, OneDrive…): borrar ahí lo borra en todos tus equipos.
    static func enNube(_ ruta: String) -> Bool {
        ruta.dropFirst(Rutas.home.path.count).split(separator: "/").contains { Escaner.esCarpetaDeNube(String($0)) }
    }

    /// El repositorio de git que contiene esa ruta (sin contarla a ella), si el índice conoce alguno por encima.
    static func repoPorEncima(_ ruta: String, _ c: Contexto) -> String? {
        var actual = Rutas.padre(ruta)
        let home = Rutas.home.path
        while actual.count > home.count {
            if c.indice.repos.contains(actual) { return actual }
            actual = Rutas.padre(actual)
        }
        return nil
    }

    static func leerTexto(_ ruta: String, maximo: Int64) -> String? {
        var st = stat()
        guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, Int64(st.st_size) <= maximo else { return nil }
        return try? String(contentsOfFile: ruta, encoding: .utf8)
    }

    // MARK: .NET

    /// El contenedor de unas salidas de .NET: la carpeta más alta (por debajo de Descargas, Documentos…) que solo tiene
    /// salidas de .NET dentro («build-2.1.0» con bin/ y obj/, «cache-compilacion» con src/<P>/{bin,obj}), o su carpeta si
    /// tiene más cosas (`entero` false).
    static func contenedor(de ruta: String, salidas: Set<String>, _ vistas: inout [String: Bool]) -> (ruta: String, entero: Bool) {
        let home = Rutas.home.path
        var actual = Rutas.padre(ruta)
        var mejor: String?
        while actual.hasPrefix(home + "/"), Rutas.padre(actual) != home, soloSalidas(actual, salidas, 0, &vistas) {
            mejor = actual
            actual = Rutas.padre(actual)
        }
        return mejor.map { ($0, true) } ?? (Rutas.padre(ruta), false)
    }

    private static func soloSalidas(_ carpeta: String, _ salidas: Set<String>, _ nivel: Int, _ vistas: inout [String: Bool]) -> Bool {
        if let ya = vistas[carpeta] { return ya }
        guard nivel < 6 else { return false }
        var alguna = false
        var es = true
        for n in nombres(carpeta) where n != ".DS_Store" {
            let r = carpeta + "/" + n
            if salidas.contains(r) { alguna = true; continue }
            guard tipo(r) == S_IFDIR, soloSalidas(r, salidas, nivel + 1, &vistas) else { es = false; break }
            alguna = true
        }
        vistas[carpeta] = es && alguna
        return es && alguna
    }

    /// Los .csproj (o .fsproj…) que restauró NuGet en esa carpeta obj/, según <Proyecto>.csproj.nuget.dgspec.json (en ella
    /// o en obj/<Proyecto>/): sus claves «restore» son las rutas de los proyectos.
    static func proyectosRestaurados(_ obj: String) -> [String] {
        var carpetas = [obj]
        for n in nombres(obj).prefix(200) where !n.hasPrefix(".") && tipo(obj + "/" + n) == S_IFDIR { carpetas.append(obj + "/" + n) }
        var r: [String] = []
        for d in carpetas {
            for n in nombres(d) where n.hasSuffix(".nuget.dgspec.json") {
                guard let texto = leerTexto(d + "/" + n, maximo: 4_000_000), let datos = texto.data(using: .utf8),
                      let json = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any],
                      let restaurados = json["restore"] as? [String: Any] else { continue }
                r += restaurados.keys.filter { $0.hasPrefix("/") }
            }
        }
        return r
    }

    /// La carpeta del proyecto de un .csproj: la más alta, hasta 4 niveles por encima, que tiene la solución (.sln, .slnx),
    /// global.json, Directory.Build.props o un .git; si no, la del .csproj.
    static func raizDelProyecto(_ csproj: String) -> String {
        let home = Rutas.home.path
        var actual = Rutas.padre(csproj)
        var raiz = actual
        for _ in 0..<5 {
            guard actual.hasPrefix(home + "/"), Rutas.padre(actual) != home else { break }
            let n = nombres(actual)
            if n.contains(where: { ["sln", "slnx"].contains(($0 as NSString).pathExtension.lowercased()) })
                || n.contains("global.json") || n.contains("Directory.Build.props") || n.contains(".git") {
                raiz = actual
            }
            actual = Rutas.padre(actual)
        }
        return raiz
    }

    /// Lo último que cambió en el código de un proyecto: lo que anotó el índice (sin sus compilaciones, .git ni lo que
    /// escriben los editores) o, si no lo registró, recorriéndolo sin bin/, obj/ y compañía (hasta 20.000 entradas).
    static func actividad(de raiz: String, _ c: Contexto) -> Date? {
        if let f = c.indice.masRecientePropio(de: raiz) { return f }
        let saltar: Set<String> = ["bin", "obj", "artifacts", ".git", "node_modules", "dist", ".vs", ".idea", ".vscode", "packages",
                                   "TestResults", ".build", ".DS_Store"]
        var mejor = 0
        var vistos = 0
        var pendientes = [raiz]
        while let d = pendientes.popLast(), vistos < 20_000 {
            for n in nombres(d) where !saltar.contains(n) {
                vistos += 1
                var st = stat()
                let p = d + "/" + n
                guard lstat(p, &st) == 0 else { continue }
                if (st.st_mode & S_IFMT) == S_IFDIR { pendientes.append(p) }
                else if (st.st_mode & S_IFMT) == S_IFREG { mejor = max(mejor, Int(st.st_mtimespec.tv_sec)) }
            }
        }
        return mejor > 0 ? Date(timeIntervalSince1970: TimeInterval(mejor)) : nil
    }

    /// Lo que hay dentro de esas carpetas de compilación que la compilación no crea (bases de datos, documentos, llaves).
    static func noSeRegenera(_ urls: [URL], _ c: Contexto) -> [String] {
        Array(Set(c.indice.noRegenerables(dentro: urls) + c.indice.sensibles(dentro: urls).map(\.ruta))).sorted()
    }

    static func avisoDeNoRegenerables(_ perdidos: [String]) -> Motivo {
        .peligro("exclamationmark.triangle.fill", "No todo se regenera",
                 "Dentro hay \(perdidos.count == 1 ? "un archivo" : "\(perdidos.count) archivos") que la compilación no crea (bases de datos, documentos, llaves…): \(Formato.listaCorta(perdidos.map { Rutas.nombre($0) })). \(perdidos.count == 1 ? "Sácalo" : "Sácalos") de ahí antes de limpiar.")
    }

    // MARK: Versiones

    struct MasNueva {
        let ruta: String
        let version: String
        /// «la 2.2.0»: para los textos.
        var esta: String { "la \(version)" }
    }

    /// La versión más nueva de la misma serie que hay al lado (solo las definitivas: «-staging» o «-rc1» no cuentan), si
    /// es mayor que la de esa carpeta (o igual, si esa es de prueba: «2.2.1-staging» junto a «2.2.1»). Solo cuentan las
    /// que `admite` (una carpeta vacía o a medias para la siguiente versión no hace «anterior» a la de ahora).
    static func versionMasNueva(que carpeta: String, admite: (String) -> Bool = { _ in true }) -> MasNueva? {
        let nombre = Rutas.nombre(carpeta)
        guard let v = VersionDeCarpeta(nombre), v.esDeEntrega else { return nil }
        let padre = Rutas.padre(carpeta)
        var mejor: (ruta: String, v: VersionDeCarpeta)?
        for n in nombres(padre) where n != nombre && n.contains(".") {
            guard let o = VersionDeCarpeta(n), o.serie == v.serie, o.calificador == nil, tipo(padre + "/" + n) == S_IFDIR else { continue }
            let masNueva = VersionDeCarpeta.mayor(o.numeros, v.numeros) || (v.calificador != nil && o.numeros == v.numeros)
            // `admite` solo se pregunta a la que podría ser la elegida (más nueva que esta y que la mejor hasta ahora).
            guard masNueva, mejor == nil || VersionDeCarpeta.mayor(o.numeros, mejor!.v.numeros), admite(padre + "/" + n) else { continue }
            mejor = (padre + "/" + n, o)
        }
        return mejor.map { MasNueva(ruta: $0.ruta, version: $0.v.texto) }
    }

    // MARK: Entregas

    private static let distribuibles: Set<String> = [
        "exe", "msi", "msix", "appx", "appxbundle", "zip", "7z", "rar", "tar", "gz", "tgz", "xz", "zst", "bz2", "dmg", "pkg",
        "apk", "aab", "ipa", "deb", "rpm", "appimage", "nupkg", "jar", "war", "pdb", "dll", "so", "dylib",
    ]
    private static let sumas = [".sha256", ".sha512", ".sha1", ".md5", ".sig", ".asc"]

    /// El zip del código fuente (o su carpeta): lo único que queda del código de esa versión si no hay git.
    static func esDelCodigoFuente(_ nombre: String) -> Bool {
        let n = nombre.lowercased()
        let palabras = n.split(whereSeparator: { "-_ .".contains($0) }).map(String.init)
        return n.contains("codigo-fuente") || n.contains("código-fuente") || n.contains("codigo_fuente") || n.contains("source")
            || palabras.contains { ["src", "fuente", "fuentes", "codigo", "código", "code"].contains($0) }
    }

    /// De una carpeta de entrega, lo que se va (carpetas por plataforma, programas, paquetes y sus sumas) y lo que se queda
    /// (el código fuente, notas, verificaciones, cualquier otra carpeta y lo que no se reconoce).
    static func partesDeEntrega(_ carpeta: String) -> (van: [String], quedan: [String]) {
        var van: [String] = []
        var quedan: [String] = []
        for n in nombres(carpeta) where !n.hasPrefix(".") {
            if esDelCodigoFuente(n) { quedan.append(n); continue }
            switch tipo(carpeta + "/" + n) {
            // Una subcarpeta solo si es de una plataforma («win-x64», «MiApp-osx-arm64», «mac») o solo tiene programas y
            // paquetes: «datos», «manual» o «fotos» se quedan.
            case S_IFDIR where esDePlataforma(n) || soloDistribuibles(carpeta + "/" + n): van.append(n)
            case S_IFREG where distribuibles.contains((n as NSString).pathExtension.lowercased()): van.append(n)
            default: quedan.append(n)
            }
        }
        // La suma de un paquete que se va (MiApp.zip.sha256), con él.
        let deSumas = quedan.filter { n in sumas.contains { s in n.lowercased().hasSuffix(s) && van.contains(String(n.dropLast(s.count))) } }
        return (van + deSumas, quedan.filter { !deSumas.contains($0) })
    }

    /// Las plataformas de .NET, Electron y compañía: «win-x64», «osx-arm64», «linux-musl-x64», «mac», «win-unpacked»… o,
    /// con el nombre del programa delante, «MiApp-win-x64» (con la arquitectura: «fotos-mac» no es una plataforma).
    private static let plataformas = [
        #"^(win|windows|osx|macos|mac|linux|linux-musl|android|ios|iossimulator|maccatalyst|tvos|browser|freebsd)([-_](x86|x64|arm|arm64|armv7|aarch64|amd64|universal|wasm|unpacked))?$"#,
        #"^.+[-_ ](win|windows|osx|macos|mac|linux|linux-musl|android|ios|maccatalyst|browser|freebsd)[-_](x86|x64|arm|arm64|armv7|aarch64|amd64|universal|wasm)$"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func esDePlataforma(_ nombre: String) -> Bool {
        let rango = NSRange(location: 0, length: (nombre as NSString).length)
        return plataformas.contains { $0.firstMatch(in: nombre, range: rango) != nil }
    }

    /// La carpeta solo tiene programas y paquetes (por extensión), sin enlaces y con algún archivo. Se miran 2.000 entradas
    /// como mucho: si hay más, no se sabe y se queda.
    static func soloDistribuibles(_ carpeta: String) -> Bool {
        var pendientes = [carpeta]
        var vistos = 0
        var alguno = false
        while let d = pendientes.popLast() {
            for n in nombres(d) where n != ".DS_Store" {
                vistos += 1
                guard vistos <= 2_000 else { return false }
                switch tipo(d + "/" + n) {
                case S_IFDIR: pendientes.append(d + "/" + n)
                case S_IFREG where distribuibles.contains((n as NSString).pathExtension.lowercased())
                    || sumas.contains(where: { n.lowercased().hasSuffix($0) }): alguno = true
                default: return false
                }
            }
        }
        return alguno
    }

    /// Hay algo que se distribuye (un programa, un paquete, un zip) en la carpeta o un nivel más abajo.
    static func tieneDistribuibles(_ carpeta: String) -> Bool {
        for n in nombres(carpeta) where !n.hasPrefix(".") {
            let p = carpeta + "/" + n
            if tipo(p) == S_IFREG && distribuibles.contains((n as NSString).pathExtension.lowercased()) { return true }
            if tipo(p) == S_IFDIR && nombres(p).contains(where: { distribuibles.contains(($0 as NSString).pathExtension.lowercased()) }) { return true }
        }
        return false
    }

    /// Cuántos archivos tiene la carpeta si son exactamente los del zip (misma ruta relativa, mismo tamaño y mismo
    /// contenido: el CRC-32 que guarda el zip de cada uno), o nil. El zip puede guardarlos dentro de una carpeta
    /// («win-x64/…»). Si en la carpeta hay enlaces, el zip no se entiende o habría que leer más de 2 GB, nil.
    static func mismosArchivos(carpeta: String, zip: String) -> Int? {
        guard var delZip = entradasDeZip(zip), !delZip.isEmpty else { return nil }
        delZip = delZip.filter { k, _ in !k.hasSuffix("/") && !k.hasPrefix("__MACOSX/") && Rutas.nombre(k) != ".DS_Store" }
        // Todos dentro de una misma carpeta: se quita.
        let primeras = Set(delZip.keys.map { $0.split(separator: "/", maxSplits: 1).first.map(String.init) ?? $0 })
        if primeras.count == 1, let p = primeras.first, delZip.keys.allSatisfy({ $0.hasPrefix(p + "/") }) {
            delZip = Dictionary(uniqueKeysWithValues: delZip.map { (String($0.key.dropFirst(p.count + 1)), $0.value) })
        }
        guard let deCarpeta = archivos(de: carpeta), !deCarpeta.isEmpty, deCarpeta.count == delZip.count else { return nil }
        let normalizado = Dictionary(delZip.map { ($0.key.precomposedStringWithCanonicalMapping, $0.value) }, uniquingKeysWith: { a, _ in a })
        var crcs: [(rel: String, crc: UInt32)] = []
        for (rel, tamano) in deCarpeta {
            guard let e = normalizado[rel.precomposedStringWithCanonicalMapping], e.tamano == tamano else { return nil }
            crcs.append((rel, e.crc))
        }
        // El nombre y el tamaño coinciden en todos: ahora el contenido (un archivo editado puede medir lo mismo, y al
        // descomprimir volvería el del zip, no el tuyo).
        var presupuesto: Int64 = 2_000_000_000
        for e in crcs where crcDeArchivo(carpeta + "/" + e.rel, presupuesto: &presupuesto) != e.crc { return nil }
        return deCarpeta.count
    }

    /// El CRC-32 del contenido de un archivo (el mismo que guarda el zip), leído de 1 MiB en 1 MiB sin seguir enlaces.
    /// nil si no se puede leer o si se acaba el presupuesto de bytes.
    private static func crcDeArchivo(_ ruta: String, presupuesto: inout Int64) -> UInt32? {
        let fd = open(ruta, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var crc = zlib.crc32(0, nil, 0)
        var bufer = [UInt8](repeating: 0, count: 1 << 20)
        while true {
            let n = bufer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { return nil }
            if n == 0 { break }
            presupuesto -= Int64(n)
            guard presupuesto >= 0 else { return nil }
            crc = bufer.withUnsafeBytes { zlib.crc32(crc, $0.bindMemory(to: Bytef.self).baseAddress, uInt(n)) }
        }
        return UInt32(truncatingIfNeeded: crc)
    }

    /// Los archivos de una carpeta (ruta relativa → tamaño), sin .DS_Store. nil si hay enlaces o más de 50.000.
    private static func archivos(de carpeta: String) -> [String: Int64]? {
        var r: [String: Int64] = [:]
        var pendientes = [""]
        while let rel = pendientes.popLast() {
            let base = rel.isEmpty ? carpeta : carpeta + "/" + rel
            for n in nombres(base) where n != ".DS_Store" {
                let r2 = rel.isEmpty ? n : rel + "/" + n
                var st = stat()
                guard lstat(carpeta + "/" + r2, &st) == 0 else { return nil }
                switch st.st_mode & S_IFMT {
                case S_IFDIR: pendientes.append(r2)
                case S_IFREG: r[r2] = Int64(st.st_size)
                default: return nil
                }
                if r.count > 50_000 { return nil }
            }
        }
        return r
    }

    /// Los archivos que guarda un zip (nombre → tamaño sin comprimir y CRC-32), leídos de su directorio central (el índice
    /// que va al final), sin descomprimir nada. Entiende ZIP64. nil si no es un zip que se entienda: los valores salen del
    /// archivo tal cual (puede estar dañado o manipulado), así que nada se suma ni se convierte sin comprobar antes que cabe.
    static func entradasDeZip(_ ruta: String, maximo: Int = 50_000) -> [String: (tamano: Int64, crc: UInt32)]? {
        guard let f = FileHandle(forReadingAtPath: ruta) else { return nil }
        defer { try? f.close() }
        guard let tamano = try? f.seekToEnd(), tamano >= 22 else { return nil }
        let cola = min(tamano, 65_557)   // el final del directorio (22 bytes) más un comentario de hasta 65.535
        guard (try? f.seek(toOffset: tamano - cola)) != nil, let datos = try? f.read(upToCount: Int(cola)), datos.count == Int(cola)
        else { return nil }
        let b = [UInt8](datos)
        func u16(_ a: [UInt8], _ p: Int) -> UInt64 { UInt64(a[p]) | UInt64(a[p + 1]) << 8 }
        func u32(_ a: [UInt8], _ p: Int) -> UInt64 { u16(a, p) | u16(a, p + 2) << 16 }
        func u64(_ a: [UInt8], _ p: Int) -> UInt64 { u32(a, p) | u32(a, p + 4) << 32 }
        var i = b.count - 22
        while i >= 0 && !(b[i] == 0x50 && b[i + 1] == 0x4B && b[i + 2] == 0x05 && b[i + 3] == 0x06) { i -= 1 }
        guard i >= 0 else { return nil }
        var entradas = u16(b, i + 10)
        var largoDirectorio = u32(b, i + 12)
        var inicio = u32(b, i + 16)
        if entradas == 0xFFFF || largoDirectorio == 0xFFFF_FFFF || inicio == 0xFFFF_FFFF {
            // ZIP64: 20 bytes antes está el localizador, que dice dónde está el final del directorio de 64 bits.
            guard i >= 20, Array(b[(i - 20)..<(i - 16)]) == [0x50, 0x4B, 0x06, 0x07] else { return nil }
            let donde = u64(b, i - 20 + 8)
            guard donde <= tamano, tamano - donde >= 56, (try? f.seek(toOffset: donde)) != nil, let z = try? f.read(upToCount: 56).map({ [UInt8]($0) }),
                  z.count == 56, Array(z[0..<4]) == [0x50, 0x4B, 0x06, 0x06] else { return nil }
            entradas = u64(z, 32)
            largoDirectorio = u64(z, 40)
            inicio = u64(z, 48)
        }
        guard entradas <= UInt64(maximo), largoDirectorio <= 64_000_000, inicio <= tamano, largoDirectorio <= tamano - inicio,
              (try? f.seek(toOffset: inicio)) != nil, let directorio = try? f.read(upToCount: Int(largoDirectorio)).map({ [UInt8]($0) }),
              directorio.count == Int(largoDirectorio) else { return nil }
        var r: [String: (tamano: Int64, crc: UInt32)] = [:]
        var p = 0
        for _ in 0..<entradas {
            guard p + 46 <= directorio.count, directorio[p] == 0x50, directorio[p + 1] == 0x4B, directorio[p + 2] == 0x01,
                  directorio[p + 3] == 0x02 else { return nil }
            let crc = UInt32(truncatingIfNeeded: u32(directorio, p + 16))
            var sinComprimir = u32(directorio, p + 24)
            let largoNombre = Int(u16(directorio, p + 28)), largoExtra = Int(u16(directorio, p + 30))
            let largoComentario = Int(u16(directorio, p + 32))
            guard p + 46 + largoNombre + largoExtra + largoComentario <= directorio.count else { return nil }
            let nombre = String(decoding: directorio[(p + 46)..<(p + 46 + largoNombre)], as: UTF8.self)
            if sinComprimir == 0xFFFF_FFFF {
                // El tamaño de verdad va en el campo extra de ZIP64 (0x0001), el primero de sus valores.
                var q = p + 46 + largoNombre
                let fin = q + largoExtra
                while q + 4 <= fin {
                    let id = u16(directorio, q), largo = Int(u16(directorio, q + 2))
                    if id == 1 && q + 12 <= fin { sinComprimir = u64(directorio, q + 4); break }
                    q += 4 + largo
                }
            }
            guard let bytes = Int64(exactly: sinComprimir) else { return nil }
            r[nombre] = (bytes, crc)
            p += 46 + largoNombre + largoExtra + largoComentario
        }
        return r
    }

    // MARK: Copias de respaldo

    private static let palabrasDeCopia: Set<String> = ["respaldo", "respaldos", "backup", "backups", "bak", "bkp", "copia", "copy",
                                                       "old", "viejo", "vieja", "anterior", "resguardo", "original", "orig"]

    /// «web-respaldo-2026-09-01», «web copia 2», «web backup», «respaldo-web», «web-old»: el nombre de una copia (una de
    /// las palabras, y algo más).
    static func pareceRespaldo(_ nombre: String) -> Bool {
        let palabras = nombre.lowercased().split(whereSeparator: { "-_ .()".contains($0) }).map(String.init)
        return palabras.count >= 2 && palabras.contains(where: palabrasDeCopia.contains)
    }

    private static let marcasPorNombre: Set<String> = [
        "Package.swift", "package.json", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
        "pyproject.toml", "setup.py", "requirements.txt", "Cargo.toml", "go.mod", "pubspec.yaml", "composer.json", "Gemfile",
        "pom.xml", "CMakeLists.txt", "Makefile", "global.json", "Directory.Build.props", "mix.exs", "Podfile",
    ]
    private static let marcasPorExtension: Set<String> = ["csproj", "fsproj", "vbproj", "sln", "slnx", "xcodeproj", "xcworkspace"]

    /// Lo que delata un proyecto de código en el primer nivel de una carpeta: «Package.swift», «.csproj»…
    static func marcasDeProyecto(_ carpeta: String) -> Set<String> {
        var r = Set<String>()
        for n in nombres(carpeta) {
            if marcasPorNombre.contains(n) { r.insert(n) }
            let ext = (n as NSString).pathExtension.lowercased()
            if marcasPorExtension.contains(ext) { r.insert("." + ext) }
        }
        return r
    }

    /// Un archivo de marca del proyecto (Package.swift, package.json, el .csproj…), para comprobar al limpiar que sigue ahí.
    static func archivoDeMarca(_ carpeta: String) -> String? {
        nombres(carpeta).first { marcasPorNombre.contains($0) && tipo(carpeta + "/" + $0) == S_IFREG }.map { carpeta + "/" + $0 }
            ?? nombres(carpeta).first { ["csproj", "fsproj", "vbproj", "sln", "slnx"].contains(($0 as NSString).pathExtension.lowercased())
                && tipo(carpeta + "/" + $0) == S_IFREG }.map { carpeta + "/" + $0 }
    }

    struct Comparacion {
        var iguales = 0
        /// Lo que tiene la copia y el original tiene distinto (otro tamaño u otra fecha): ruta relativa, tamaño y si es un
        /// enlace.
        var distintos: [(ruta: String, bytes: Int64, enlace: Bool)] = []
        /// Lo que solo tiene la copia.
        var soloEnCopia: [(ruta: String, bytes: Int64, enlace: Bool)] = []
        /// Lo que tiene el original y la copia no (no se pierde).
        var faltan: [String] = []
        /// Lo de la copia que no se comparó porque se regenera (sus compilaciones y dependencias): se va con ella.
        var sinComparar: [String] = []
        var total: Int { iguales + distintos.count + soloEnCopia.count }
        var parecido: Double { total == 0 ? 0 : Double(iguales) / Double(total) }
    }

    /// Las carpetas que siempre se regeneran (dependencias y cachés): no cuentan al comparar una copia con su original. Las
    /// de nombre ambiguo (build, dist, bin, obj, target: en Node, Go o un script ahí está tu código) solo se saltan si el
    /// índice las reconoce como compilación (`artefactos`) y, en la copia, si el original tiene la suya en el mismo sitio.
    private static let sinComparar: Set<String> = [".build", "node_modules", "DerivedData", ".gradle", "Pods", ".next", ".nuxt",
                                                   ".turbo", "__pycache__", ".venv", "venv", ".dart_tool", "xcuserdata", ".swiftpm"]
    private static let extensionesDePaquete: Set<String> = ["app", "framework", "bundle", "xcarchive", "dsym", "plugin", "xcframework"]

    /// Compara una copia con su posible original, archivo por archivo (ruta relativa, tamaño y fecha de modificación, sin
    /// seguir enlaces). Una .app o un .framework cuenta como un solo archivo (su tamaño y su fecha más reciente). nil si la
    /// copia tiene más de 20.000 archivos o un repositorio de git dentro (sus commits, ramas o stash no se comparan).
    static func comparar(copia: String, original: String, artefactos: Set<String>) -> Comparacion? {
        guard let elOriginal = huellas(original, artefactos: artefactos, delOriginal: nil) else { return nil }
        // En la copia, una compilación solo se salta si el original también la tiene (si no, es algo que solo está ahí).
        guard let laCopia = huellas(copia, artefactos: artefactos, delOriginal: Set(elOriginal.saltadas)), !laCopia.archivos.isEmpty
        else { return nil }
        var r = Comparacion()
        r.sinComparar = laCopia.saltadas.sorted()
        let (deCopia, delOriginal) = (laCopia.archivos, elOriginal.archivos)
        for (rel, h) in deCopia.sorted(by: { $0.key < $1.key }) {
            if let o = delOriginal[rel] {
                if o == h { r.iguales += 1 } else { r.distintos.append((rel, h.bytes, h.enlace != nil)) }
            } else {
                r.soloEnCopia.append((rel, h.bytes, h.enlace != nil))
            }
        }
        r.faltan = delOriginal.keys.filter { deCopia[$0] == nil }.sorted()
        return r
    }

    private struct HuellaDeArchivo: Equatable {
        let bytes: Int64
        let fecha: Int
        let enlace: String?
    }

    /// Las huellas de los archivos de una carpeta y lo que se saltó por regenerarse (rutas relativas). Para la copia,
    /// `delOriginal` es lo que se saltó en el original: una compilación de la copia solo se salta si el original tiene la
    /// suya en el mismo sitio, y un .git a cualquier profundidad da nil (su historial no se puede comparar así). En el
    /// original (`delOriginal` nil), su .git no cuenta.
    private static func huellas(_ raiz: String, artefactos: Set<String>, delOriginal: Set<String>?)
        -> (archivos: [String: HuellaDeArchivo], saltadas: [String])? {
        let esCopia = delOriginal != nil
        var r: [String: HuellaDeArchivo] = [:]
        var saltadas: [String] = []
        var pendientes = [""]
        while let rel = pendientes.popLast() {
            for n in nombres(rel.isEmpty ? raiz : raiz + "/" + rel) {
                let r2 = rel.isEmpty ? n : rel + "/" + n
                let p = raiz + "/" + r2
                if n == ".git" {
                    if esCopia { return nil }
                    continue
                }
                var st = stat()
                guard lstat(p, &st) == 0 else { continue }
                let clase = st.st_mode & S_IFMT
                if clase == S_IFREG && n == ".DS_Store" { continue }
                // Lo que se regenera: las dependencias y cachés de siempre (carpetas) y lo que el índice reconoce como
                // compilación. Se dice en el texto, porque se va con la copia.
                if (clase == S_IFDIR && sinComparar.contains(n)) || (artefactos.contains(p) && delOriginal?.contains(r2) != false) {
                    saltadas.append(r2)
                    continue
                }
                switch clase {
                case S_IFDIR:
                    if extensionesDePaquete.contains((n as NSString).pathExtension.lowercased()) {
                        let (bytes, fecha) = sumaDe(p)
                        r[r2] = HuellaDeArchivo(bytes: bytes, fecha: fecha, enlace: nil)
                    } else {
                        pendientes.append(r2)
                    }
                case S_IFREG: r[r2] = HuellaDeArchivo(bytes: Int64(st.st_size), fecha: Int(st.st_mtimespec.tv_sec), enlace: nil)
                case S_IFLNK:
                    r[r2] = HuellaDeArchivo(bytes: 0, fecha: 0, enlace: (try? FileManager.default.destinationOfSymbolicLink(atPath: p)) ?? "?")
                default: break
                }
                if r.count > 20_000 { return nil }
            }
        }
        return (r, saltadas)
    }

    /// Lo que suman los archivos de una carpeta y su fecha más reciente (sin seguir enlaces).
    private static func sumaDe(_ carpeta: String) -> (Int64, Int) {
        var bytes: Int64 = 0
        var fecha = 0
        var pendientes = [carpeta]
        var vistos = 0
        while let d = pendientes.popLast(), vistos < 20_000 {
            for n in nombres(d) {
                vistos += 1
                var st = stat()
                guard lstat(d + "/" + n, &st) == 0 else { continue }
                if (st.st_mode & S_IFMT) == S_IFDIR { pendientes.append(d + "/" + n) }
                else if (st.st_mode & S_IFMT) == S_IFREG {
                    bytes += Int64(st.st_size)
                    fecha = max(fecha, Int(st.st_mtimespec.tv_sec))
                }
            }
        }
        return (bytes, fecha)
    }
}
