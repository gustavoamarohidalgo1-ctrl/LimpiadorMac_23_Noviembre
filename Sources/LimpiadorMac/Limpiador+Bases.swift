import Foundation
import SQLite3

// Compactar bases SQLite (VACUUM) con respaldo: antes, un clon de APFS de la base y de sus diarios; después, «PRAGMA
// integrity_check». Si SQLite no la da por buena, la base vuelve a como estaba. Lo usa `Limpiador.limpiar` en las
// acciones `.comando` de /usr/bin/sqlite3 (`AccionLimpieza.compactaBase`).

extension AccionLimpieza {
    /// Compacta una base de datos SQLite («sqlite3 … VACUUM»): no borra ningún dato, solo le quita el hueco vacío.
    var compactaBase: Bool {
        if case .comando(let programa, _, _, _) = self { return programa.hasSuffix("/sqlite3") }
        return false
    }
}

extension Limpiador {
    /// Dónde se guarda el clon de respaldo de un archivo de una base mientras se compacta: a su lado (un clon tiene que
    /// estar en el mismo disco), con un nombre que no usa ninguna app.
    static func rutaDeRespaldo(_ ruta: String) -> String { ruta + ".limpiadormac-respaldo" }
}

/// El respaldo de una base SQLite mientras se compacta: un clon de APFS de la base y de sus diarios (-wal, -journal), que
/// no ocupa nada mientras no cambian (al compactar solo cuesta lo que se reescribe, y la base libera su hueco cuando se
/// quita el clon). Solo se compacta con respaldo.
struct RespaldoDeBase {
    let base: String
    /// Los clones hechos: cada archivo de la base y su clon.
    let clones: [(original: String, clon: String)]

    /// Los diarios que van con la base: lo que tienen dentro puede no estar todavía en ella.
    static let diarios = ["-wal", "-journal"]

    enum Comprobacion {
        /// SQLite la da por buena: el respaldo ya se quitó.
        case bien
        /// No la daba por buena y se devolvió a como estaba (con sus diarios).
        case devuelta
        /// No se pudo comprobar ni devolver (algo la usa, o falló al devolverla): el respaldo se queda. Lo que hay que decir.
        case sinDevolver(String)
    }

    /// Prepara el respaldo de `base`. Si quedó uno de una compactación anterior que se cortó (con el clon de la propia
    /// base), se comprueba la base: si SQLite la da por buena, el viejo sobra (es la base de antes de compactar, con los
    /// mismos datos) y se quita; si no, no se toca nada. Si solo quedan clones de sus diarios, son los que no pude
    /// devolver junto a la base (`comprobar`): pueden tener cambios que no están en ella, así que no se quitan ni se
    /// compacta. `fallo` dice por qué no se pudo (entonces no se compacta).
    static func preparar(_ base: String) -> (respaldo: RespaldoDeBase?, fallo: String?) {
        let archivos = [base] + diarios.map { base + $0 }
        let viejos = archivos.map(Limpiador.rutaDeRespaldo).filter(Self.esArchivo)
        if let primero = viejos.first {
            guard viejos.contains(Limpiador.rutaDeRespaldo(base)) else {
                return (nil, "quedó el diario de antes de una compactación anterior en \(Formato.rutaCorta(primero)): ponlo junto a la base (sin «.limpiadormac-respaldo») o bórralo tú si la app funciona bien; mientras esté ahí, no la compacto")
            }
            guard integra(base) else {
                return (nil, "quedó un respaldo de una compactación anterior (\(Formato.rutaCorta(primero))) y la base no pasa la comprobación de SQLite, así que no toqué nada: revisa cuál de las dos conservar")
            }
            for v in viejos { unlink(v) }
        }
        guard Self.esArchivo(base) else { return (nil, "la base ya no está") }
        var clones: [(original: String, clon: String)] = []
        for a in archivos where Self.esArchivo(a) {
            let clon = Limpiador.rutaDeRespaldo(a)
            guard clonefile(a, clon, UInt32(CLONE_NOFOLLOW)) == 0 else {
                let motivo = String(cString: strerror(errno))
                for c in clones { unlink(c.clon) }
                return (nil, "no pude guardar un clon de respaldo de \(Rutas.nombre(a)) (\(motivo)), y sin respaldo no la compacto")
            }
            clones.append((a, clon))
        }
        return (RespaldoDeBase(base: base, clones: clones), nil)
    }

    /// Después de compactar: si SQLite la da por buena, se quita el respaldo; si no, la base y sus diarios vuelven a como
    /// estaban (sin el -shm, el índice del diario, que SQLite rehace). Solo se devuelve si nadie la tiene abierta:
    /// cambiarle los archivos a un programa que la está usando la rompería.
    func comprobar() -> Comprobacion {
        if Self.integra(base) {
            for c in clones { unlink(c.clon) }
            return .bien
        }
        let guardada = Formato.rutaCorta(Limpiador.rutaDeRespaldo(base))
        // Lo que pasa después con la base de antes: la próxima compactación la quita si SQLite da por buena la base, y
        // mientras tanto «Archivos grandes» la enseña para revisar.
        let despues = "La base de antes está en \(guardada): no la borres mientras no compruebes que la app funciona bien. Si la vuelvo a compactar y SQLite da la base por buena, la quito yo; mientras tanto te la enseño en «Archivos grandes» para revisar."
        let abiertos = ArchivosAbiertos.ahora()
        let archivos = [base, base + "-shm"] + Self.diarios.map { base + $0 }
        if !abiertos.leidos || archivos.contains(where: { abiertos.hayAbierto(dentroDe: $0) != nil }) {
            return .sinDevolver("después de compactarla no pude confirmar con SQLite que esté bien, y no la devolví a como estaba porque algo la está usando ahora. \(despues)")
        }
        // Primero la base: si no se puede devolver, sus diarios se quedan como están (los de antes no valen para la nueva).
        guard let deLaBase = clones.first(where: { $0.original == base }), rename(deLaBase.clon, base) == 0 else {
            return .sinDevolver("después de compactarla SQLite no la daba por buena, y no pude devolverla a como estaba (\(String(cString: strerror(errno)))). \(despues)")
        }
        var sinDevolver: [String] = []
        for d in Self.diarios {
            let actual = base + d
            unlink(actual)
            if let c = clones.first(where: { $0.original == actual }), rename(c.clon, actual) != 0 { sinDevolver.append(c.clon) }
        }
        unlink(base + "-shm")
        if let primero = sinDevolver.first {
            return .sinDevolver("después de compactarla SQLite no la daba por buena: devolví la base a como estaba, pero no su diario, que está en \(Formato.rutaCorta(primero)). Ponlo junto a la base (sin «.limpiadormac-respaldo») antes de abrir la app.")
        }
        return .devuelta
    }

    /// Un archivo normal (sin seguir enlaces).
    private static func esArchivo(_ ruta: String) -> Bool {
        var st = stat()
        return lstat(ruta, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG
    }

    /// «PRAGMA integrity_check» de la base: true solo si SQLite contesta exactamente «ok». Se abre con la librería del
    /// sistema, sin crearla si no está y sin pasar por la configuración de sqlite3 (~/.sqliterc).
    static func integra(_ base: String) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(base, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return false
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5000)
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &st, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(st) }
        var filas: [String] = []
        while true {
            let paso = sqlite3_step(st)
            if paso == SQLITE_DONE { break }
            guard paso == SQLITE_ROW, filas.count < 100 else { return false }
            filas.append(sqlite3_column_text(st, 0).map { String(cString: $0) } ?? "")
        }
        return filas == ["ok"]
    }
}
