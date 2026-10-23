import AppKit
import SwiftUI

/// «Datos del sistema»: lo que macOS guarda fuera de tu carpeta y Ajustes cuenta como «Datos del sistema», por partes,
/// con lo que libera cada ajuste y el botón que lo abre. La app no borra nada de esto: los restos de root se explican
/// con el comando para copiar, y solo hay dos botones que hacen algo (vaciar las miniaturas y medir con contraseña).
struct VistaSistema: View {
    @EnvironmentObject var almacen: Almacen
    @ObservedObject private var sistema = EstadoSistema.compartido
    @State private var confirmarMiniaturas = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                encabezado
                if let i = sistema.informe {
                    resumen(i)
                    if !i.recursos.isEmpty { seccionRecursos(i) }
                    seccionDisco(i)
                    seccionRoot(i)
                    if !i.restos.isEmpty { seccionRestos(i) }
                    if i.hayMiniaturas { tarjetaMiniaturas(i) }
                } else {
                    cargando
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .defaultScrollAnchor(.top)
        .frame(minHeight: 0, maxHeight: .infinity)
        .navigationTitle("Datos del sistema")
        .task { sistema.medirSiHaceFalta(papelera: almacen.tamanoPapelera) }
    }

    /// Abre un panel de Ajustes del Sistema o una app (Xcode).
    static func abrir(_ d: DatosDelSistema.Destino) {
        switch d {
        case .ajustes(let u):
            if let url = URL(string: u) { NSWorkspace.shared.open(url) }
        case .app(let id):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    private var encabezado: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Datos del sistema").font(.largeTitle.weight(.bold))
                Text("Lo que Ajustes › General › Almacenamiento llama «Datos del sistema»: recursos que descarga macOS, registros, memoria virtual y lo que solo puede leer un administrador. No borro nada de esto: te explico qué es y qué ajuste lo quita.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if sistema.midiendo {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    sistema.medir(papelera: almacen.tamanoPapelera)
                } label: {
                    Label("Volver a medir", systemImage: "arrow.clockwise")
                }
                .help("Vuelve a leer los recursos, los volúmenes y los restos (solo lectura)")
            }
        }
    }

    private var cargando: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Leyendo los recursos de macOS, los volúmenes y los registros…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: Resumen

    private func partes(_ i: DatosDelSistema.Informe) -> [(nombre: String, bytes: Int64, color: Color)] {
        [("Recursos de Apple", i.recursosTotal, Color.accentColor),
         ("Registros", i.registros?.bytes ?? 0, Color.orange),
         ("Memoria virtual", (i.sleepimage ?? 0) + i.swap, Color.purple),
         ("Solo lo ve el administrador", i.soloRoot ?? 0, Color.gray)].filter { $0.bytes > 0 }
    }

    private func resumen(_ i: DatosDelSistema.Informe) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lo que reconocí").font(.headline).foregroundStyle(.secondary)
                    Text(Formato.bytes(i.total))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    if i.soloRoot == nil {
                        Text("Sin lo que solo ve el administrador: analiza a fondo para calcularlo.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Formato.bytes(i.conAjustes)) se liberan con ajustes")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(i.conAjustes > 0 ? .green : .secondary)
                    Text(i.quizaConAjustes > 0 ? "y quizá \(Formato.bytes(i.quizaConAjustes)) más, si no los usas" : "de macOS y de Xcode, sin borrar nada a mano")
                        .foregroundStyle(.secondary)
                }
            }
            BarraPartes(partes: partes(i)).frame(height: 14)
            HStack(spacing: 16) {
                ForEach(Array(partes(i).enumerated()), id: \.offset) { _, p in
                    Label {
                        Text("\(p.nombre) · \(Formato.bytes(p.bytes))")
                    } icon: {
                        Circle().fill(p.color).frame(width: 8, height: 8)
                    }
                    .font(.caption)
                }
            }
            if i.purgable >= 100_000_000 {
                Text("Además, \(Formato.bytes(i.purgable)) son purgables: macOS los cuenta como usados hasta que los suelta, cuando le hace falta espacio.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Recursos

    private func seccionRecursos(_ i: DatosDelSistema.Informe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lo que descarga macOS").font(.title2.weight(.semibold))
                Spacer()
                Text(Formato.bytes(i.recursosTotal)).foregroundStyle(.secondary)
            }
            Text("Modelos, voces, idiomas y documentación que macOS y Xcode bajan para sus funciones. No se borran a mano: se quitan con el ajuste de cada uno"
                 + (i.recursosIlegibles > 0 ? ". \(Formato.bytes(i.recursosIlegibles)) están en carpetas que macOS no deja leer ni con contraseña: lo que ocupan lo dicen sus descriptores." : ".")
                 + (i.pendientesDeRecoger > 0 ? " \(Formato.bytes(i.pendientesDeRecoger)) son versiones anteriores que macOS recogerá solo." : ""))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(i.recursos) { r in TarjetaRecurso(recurso: r) }
        }
    }

    // MARK: Volúmenes, registros y memoria virtual

    private func seccionDisco(_ i: DatosDelSistema.Informe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("El disco por dentro").font(.title2.weight(.semibold))
            Text("El disco de arranque tiene varios volúmenes que comparten el espacio. Ajustes cuenta unos como «macOS» y otros dentro de «Datos del sistema».")
                .font(.callout).foregroundStyle(.secondary)
            VStack(spacing: 2) {
                ForEach(Array(i.volumenes.enumerated()), id: \.element.id) { n, v in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: v.rol == "Datos" ? "internaldrive.fill" : "internaldrive").frame(width: 22).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(v.rol) · \(v.nombre)").lineLimit(1)
                            Text(v.cuentaComo + (v.nota.map { ". " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Formato.bytes(v.bytes)).monospacedDigit()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(n.isMultiple(of: 2) ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if let r = i.rosetta {
                    Label(r.appsIntel.isEmpty
                          ? "Rosetta está instalada\(r.bytes.map { " (\(Formato.bytes($0)) en el arranque)" } ?? ""), pero ninguna app tuya la necesita. macOS no deja desinstalarla y su espacio cuenta como «macOS», no como «Datos del sistema»."
                          : "Rosetta está instalada\(r.bytes.map { " (\(Formato.bytes($0)) en el arranque)" } ?? "") y la necesitan \(Formato.listaCorta(r.appsIntel.map { (Rutas.nombre($0) as NSString).deletingPathExtension }, maximo: 4)), que solo funcionan en Intel.",
                          systemImage: "cpu")
                }
                if let r = i.registros {
                    Label("Registros de macOS: \(Formato.bytes(r.bytes))\(r.masAntiguo.map { ", desde \(Formato.haceCuanto($0).lowercased())" } ?? ""). macOS los rota solo."
                          + ((r.horasPersist ?? 99) < 48 ? " Los normales solo cubren \(Int(r.horasPersist ?? 0)) horas: algo escribe muchos registros («log stats --overview» dice quién)." : "")
                          + (r.bytes > 2_000_000_000 ? " Si quieres vaciarlos, «sudo log erase --all» en la Terminal (pierdes el historial de diagnóstico)." : ""),
                          systemImage: "doc.text.magnifyingglass")
                } else if !i.registrosMedibles {
                    Label("Registros de macOS: no los puedo medir (hace falta ser administrador).", systemImage: "doc.text.magnifyingglass")
                }
                Label("Memoria virtual: imagen de hibernación \(i.sleepimage.map(Formato.bytes) ?? "no hay")"
                      + (i.sleepimage != nil ? " (la usa el Mac para dormir sin perder lo abierto si se agota la batería; macOS la vuelve a crear)" : "")
                      + " · memoria de intercambio \(Formato.bytes(i.swap))"
                      + (i.swap > 1_000_000_000 ? ": se vacía al reiniciar." : "."),
                      systemImage: "memorychip")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Lo que solo ve root

    private func seccionRoot(_ i: DatosDelSistema.Informe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lo que solo ve el administrador").font(.title2.weight(.semibold))
                Spacer()
                if let s = i.soloRoot { Text("unos \(Formato.bytes(s))").font(.title3.weight(.semibold)).monospacedDigit() }
            }
            Text(textoRoot(i))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let c = i.cuentasBorradas {
                Label("Las cuentas que se borraron guardando su carpeta en una imagen (/Users/Deleted Users) ocupan \(Formato.bytes(c)). No son de macOS y no cuentan aquí: si ya no las necesitas, puedes borrarlas tú desde el Finder (te pedirá tu contraseña).",
                      systemImage: "person.crop.circle.badge.xmark")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !i.ocultos.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(i.ocultos) { o in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: o.protegida ? "lock.shield" : "key").frame(width: 20).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(o.que).font(.callout)
                                Text(o.ruta).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(o.protegida ? "protegido por macOS" : "se mide con contraseña").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                Button {
                    sistema.medirConContrasena()
                } label: {
                    Label("Medir con contraseña", systemImage: "key.fill")
                }
                .disabled(sistema.midiendoRoot)
                .help("Ejecuta «du» como administrador para ver cuánto ocupa cada carpeta. Solo lee.")
                if sistema.midiendoRoot { ProgressView().controlSize(.small) }
                Text("Solo lee: ejecuta «du» como administrador con un comando fijo (también mide las carpetas de las otras cuentas, solo su tamaño), y macOS te pide la contraseña en su propia ventana. Lo protegido por macOS no se puede medir ni así.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let m = sistema.mensajeRoot { Text(m).font(.callout.weight(.medium)) }
            if let lista = sistema.medidaRoot, !lista.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(lista.prefix(15).enumerated()), id: \.element.id) { n, m in
                        HStack {
                            Text(m.ruta).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Formato.bytes(m.bytes)).monospacedDigit()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(n.isMultiple(of: 2) ? AnyShapeStyle(.background) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                if let s = lista.first(where: { $0.ruta.hasSuffix("/.Spotlight-V100") }), almacen.disco.total > 0, s.bytes * 20 > almacen.disco.total {
                    Label("El índice de Spotlight pasa del 5 % del disco. Si crees que está dañado, «sudo mdutil -E /» en la Terminal lo rehace (las búsquedas salen incompletas durante horas).",
                          systemImage: "magnifyingglass")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Qué es lo que solo ve el administrador o, si no se sabe, por qué.
    private func textoRoot(_ i: DatosDelSistema.Informe) -> String {
        guard i.soloRoot != nil else {
            return !i.accesoTotal
                ? "Sin «Acceso total al disco» no puedo separar lo que solo ve el administrador de tus datos protegidos (Fotos, Mail, los contenedores de las apps). Dale el permiso y analiza otra vez."
                : "Analiza a fondo para calcularlo: es lo que ocupa el volumen de datos menos todo lo que puedo medir, y hace falta un análisis reciente (después de limpiar, o si pasó un rato, analiza otra vez)."
        }
        var t = "Lo que ocupa el volumen de datos menos lo que pude medir (tu carpeta, las apps, /Library, /private…) y lo que macOS no deja leer pero cuyo tamaño dicen sus descriptores. Suele ser el índice de Spotlight, el historial de cambios de archivos, las versiones de tus documentos y las bases de datos de los servicios de macOS, y también lo que no recorro de tu Biblioteca (Mail, Mensajes…)."
        if !i.otrasCuentas.isEmpty {
            t += " Incluye además las carpetas de otras cuentas de este Mac (\(Formato.listaCorta(i.otrasCuentas, maximo: 4))), que no puedo leer: son de esas cuentas, no de macOS."
        }
        if almacen.instantaneas > 0 {
            t += " Cuenta también lo que retienen \(almacen.instantaneas == 1 ? "1 instantánea local" : "\(almacen.instantaneas) instantáneas locales") del disco"
                + (almacen.instantaneasTM > 0 ? ": las de Time Machine se pueden adelgazar desde el Resumen." : ".")
        }
        return t + " Lo de macOS no se borra a mano, y la app no toca nada de esto."
    }

    // MARK: Restos y miniaturas

    private func seccionRestos(_ i: DatosDelSistema.Informe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restos fuera de tu carpeta").font(.title2.weight(.semibold))
            Text("Son de root: se quitan con tu contraseña en la Terminal o desde Ajustes. LimpiadorMac nunca ejecuta estos comandos; te los dejo para copiar, por si quieres hacerlo tú.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(i.restos) { r in TarjetaResto(resto: r) }
        }
    }

    private func tarjetaMiniaturas(_ i: DatosDelSistema.Informe) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Miniaturas del Finder\(i.miniaturas.map { ": \(Formato.bytes($0))" } ?? "")").font(.headline)
                Text("Las vistas previas que el Finder y Quick Look hacen de tus archivos. macOS no deja leerlas, pero sí vaciarlas sin contraseña («qlmanage -r cache»). Se rehacen solas al abrir las carpetas.")
                    .font(.callout).foregroundStyle(.secondary)
                if let m = sistema.mensajeMiniaturas { Text(m).font(.callout.weight(.medium)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if sistema.vaciandoMiniaturas { ProgressView().controlSize(.small) }
            Button("Vaciar las miniaturas") { confirmarMiniaturas = true }
                .disabled(sistema.vaciandoMiniaturas)
                .confirmationDialog("¿Vaciar las miniaturas del Finder?", isPresented: $confirmarMiniaturas) {
                    Button("Vaciar las miniaturas") { sistema.vaciarMiniaturas() }
                } message: {
                    Text("macOS borra su caché de miniaturas y las vuelve a hacer cuando abras las carpetas (al principio, con algo de trabajo en las que tienen muchas fotos o PDF). No se toca ningún archivo tuyo.")
                }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Un recurso de macOS: qué es, cómo está, cuánto libera su ajuste y el botón que lo abre.
struct TarjetaRecurso: View {
    let recurso: DatosDelSistema.Recurso
    @State private var abierto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: recurso.icono).font(.title3).foregroundStyle(.tint).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recurso.titulo).font(.headline)
                    Text(recurso.que).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formato.bytes(recurso.bytes)).font(.title3.weight(.bold).monospacedDigit())
                    if recurso.liberable > 0 {
                        Text("libera \(Formato.bytes(recurso.liberable))").font(.caption.weight(.medium)).foregroundStyle(.green)
                    }
                    if recurso.quiza > 0 {
                        Text("quizá \(Formato.bytes(recurso.quiza))").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            ForEach(recurso.estado, id: \.self) { e in
                Label(e, systemImage: "info.circle").font(.callout)
            }
            if let a = recurso.ajuste, recurso.liberable + recurso.quiza > 0 {
                HStack(alignment: .top) {
                    Label(a, systemImage: "gearshape").font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if let d = recurso.destino, let b = recurso.boton {
                        Button(b) { VistaSistema.abrir(d) }
                    }
                }
                if let c = recurso.consecuencia {
                    Text("Si lo quitas: \(c)").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !recurso.detalles.isEmpty {
                DisclosureGroup(isExpanded: $abierto) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(recurso.detalles, id: \.self) { Text($0).font(.caption) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Detalles · medido \(recurso.medida)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Un resto de root: qué es y el comando para copiar (la app nunca lo ejecuta), o el ajuste que lo quita.
struct TarjetaResto: View {
    let resto: DatosDelSistema.Resto
    @State private var copiado = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: resto.enMarcha ? "bolt.fill" : "terminal")
                    .foregroundStyle(resto.enMarcha ? Color.orange : Color.secondary).frame(width: 20)
                Text(resto.titulo).font(.headline).lineLimit(2)
                Spacer()
                Text(resto.bytes.map(Formato.bytes) ?? "sin medir").monospacedDigit().foregroundStyle(.secondary)
            }
            Text(resto.detalle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let c = resto.comando {
                HStack(alignment: .top) {
                    Text(c).font(.caption.monospaced()).textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    Button(copiado ? "Copiado" : "Copiar") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(c, forType: .string)
                        copiado = true
                    }
                    .help("Copia los comandos para pegarlos en la Terminal")
                }
            }
            if let d = resto.destino {
                Button("Abrir Ajustes") { VistaSistema.abrir(d) }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Una barra con las partes de «Datos del sistema», cada una de su color y de su tamaño.
struct BarraPartes: View {
    let partes: [(nombre: String, bytes: Int64, color: Color)]

    var body: some View {
        GeometryReader { g in
            let total = max(1, partes.reduce(Int64(0)) { $0 + $1.bytes })
            let ancho = max(0, g.size.width - CGFloat(max(0, partes.count - 1) * 2))
            HStack(spacing: 2) {
                ForEach(Array(partes.enumerated()), id: \.offset) { _, p in
                    Rectangle().fill(p.color.gradient)
                        .frame(width: max(2, ancho * CGFloat(Double(p.bytes) / Double(total))))
                }
            }
            .clipShape(Capsule())
        }
    }
}
