package com.kepler.ground

import java.sql.{Connection, DriverManager, PreparedStatement, ResultSet, Statement, Timestamp}
import java.time.{Instant, LocalDateTime, ZoneOffset}
import java.time.format.DateTimeFormatter
import scala.util.{Try, Using}

// ============================================================
// SERVICIO DE BASE DE DATOS — MySQL con JDBC
// Patrón funcional: funciones que retornan Try[T] en lugar
// de lanzar excepciones directamente.
// ============================================================

class DatabaseService(host: String, port: String, dbName: String, user: String, pass: String) {

    private val jdbcUrl = s"jdbc:mysql://$host:$port/$dbName?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"

    private def connection(): Connection = {
        Class.forName("com.mysql.cj.jdbc.Driver")
        DriverManager.getConnection(jdbcUrl, user, pass)
    }

    // ----------------------------------------------------------
    // INICIALIZACION: ejecuta init.sql si las tablas no existen
    // ----------------------------------------------------------
    def initialize(): Unit = {
        val sql = scala.io.Source.fromResource("init.sql").mkString
        Using(connection()) { conn =>
            // Ejecutar sentencias separadas por ;
            sql.split(";").map(_.trim).filter(_.nonEmpty).foreach { stmt =>
                Try(conn.createStatement().execute(stmt))
            }
        } match {
            case scala.util.Success(_) =>
                println("[GROUND] Base de datos inicializada.")
            case scala.util.Failure(ex) =>
                println(s"[GROUND] ERROR al inicializar BD: ${ex.getMessage}")
                println("[GROUND] Verifica que MySQL este corriendo en el puerto configurado.")
                throw ex
        }
    }

    // ----------------------------------------------------------
    // Obtener o crear sonda por nombre
    // ----------------------------------------------------------
    def getOrCreateSonda(nombre: String): Long = {
        Using(connection()) { conn =>
            val sel = conn.prepareStatement("SELECT id FROM sondas WHERE nombre = ?")
            sel.setString(1, nombre)
            val rs = sel.executeQuery()
            if (rs.next()) {
                rs.getLong("id")
            } else {
                val ins = conn.prepareStatement(
                    "INSERT INTO sondas (nombre, estado_sensores, fecha_lanzamiento) VALUES (?, 'OPERATIVO', CURDATE())",
                    Statement.RETURN_GENERATED_KEYS
                )
                ins.setString(1, nombre)
                ins.executeUpdate()
                val keys = ins.getGeneratedKeys
                keys.next()
                keys.getLong(1)
            }
        }.getOrElse(throw new RuntimeException("No se pudo obtener/crear sonda"))
    }

    // ----------------------------------------------------------
    // Obtener o crear misión por nombre
    // ----------------------------------------------------------
    def getOrCreateMision(sondaId: Long, nombre: String): Long = {
        Using(connection()) { conn =>
            val sel = conn.prepareStatement("SELECT id FROM misiones WHERE nombre = ?")
            sel.setString(1, nombre)
            val rs = sel.executeQuery()
            if (rs.next()) {
                rs.getLong("id")
            } else {
                val ins = conn.prepareStatement(
                    "INSERT INTO misiones (sonda_id, nombre, descripcion, fecha_inicio) VALUES (?, ?, ?, CURDATE())",
                    Statement.RETURN_GENERATED_KEYS
                )
                ins.setLong(1, sondaId)
                ins.setString(2, nombre)
                ins.setString(3, s"Mision de observacion automatica: $nombre")
                ins.executeUpdate()
                val keys = ins.getGeneratedKeys
                keys.next()
                keys.getLong(1)
            }
        }.getOrElse(throw new RuntimeException("No se pudo obtener/crear mision"))
    }

    // ----------------------------------------------------------
    // Insertar observacion
    // ----------------------------------------------------------
    def insertarObservacion(misionId: Long, atlas: AtlasPayload): Long = {
        val v = atlas.payload_voyager
        val ts = parseTimestamp(v.timestamp_utc)

        Using(connection()) { conn =>
            val ps = conn.prepareStatement(
                """INSERT INTO observaciones
                  |(mision_id, ascension_recta, declinacion, lecturas_espectrales,
                  | intensidad_senal, regularidad, clasificacion, confianza, timestamp_utc)
                  |VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""".stripMargin,
                Statement.RETURN_GENERATED_KEYS
            )
            ps.setLong(1, misionId)
            ps.setDouble(2, v.ascension_recta)
            ps.setDouble(3, v.declinacion)
            ps.setString(4, v.lectura_espectral)
            ps.setDouble(5, v.intensidad_senal)
            ps.setString(6, v.regularidad)
            ps.setString(7, v.clasificacion)
            ps.setDouble(8, v.confianza)
            ps.setTimestamp(9, ts)
            ps.executeUpdate()
            val keys = ps.getGeneratedKeys
            keys.next()
            keys.getLong(1)
        }.getOrElse(throw new RuntimeException("No se pudo insertar observacion"))
    }

    // ----------------------------------------------------------
    // Insertar transmision
    // ----------------------------------------------------------
    def insertarTransmision(observacionId: Long, atlas: AtlasPayload): Long = {
        val now = Timestamp.from(Instant.now())

        Using(connection()) { conn =>
            val ps = conn.prepareStatement(
                """INSERT INTO transmisiones
                  |(observacion_id, cadena_trazabilidad, hash_sha256,
                  | nivel_alerta, justificacion_alerta,
                  | timestamp_hermes, timestamp_atlas, timestamp_ground)
                  |VALUES (?, ?, ?, ?, ?, ?, ?, ?)""".stripMargin,
                Statement.RETURN_GENERATED_KEYS
            )
            ps.setLong(1, observacionId)
            ps.setString(2, atlas.trazabilidad + " -> GROUND")
            ps.setString(3, atlas.hash_sha256)
            ps.setString(4, atlas.nivel_prioridad)
            ps.setString(5, atlas.justificacion_alerta)
            ps.setTimestamp(6, parseTimestamp(atlas.timestamp_hermes))
            ps.setTimestamp(7, parseTimestamp(atlas.timestamp_atlas))
            ps.setTimestamp(8, now)
            ps.executeUpdate()
            val keys = ps.getGeneratedKeys
            keys.next()
            keys.getLong(1)
        }.getOrElse(throw new RuntimeException("No se pudo insertar transmision"))
    }

    // ----------------------------------------------------------
    // Insertar resumen consolidado
    // ----------------------------------------------------------
    def insertarResumen(misionId: Long, transmisionId: Long,
                        atlas: AtlasPayload, resumenTexto: String): Long = {
        Using(connection()) { conn =>
            val ps = conn.prepareStatement(
                """INSERT INTO resumenes
                  |(mision_id, transmision_id, resumen_consolidado,
                  | misiones_activas, prioridad, agencia_responsable, creado_en)
                  |VALUES (?, ?, ?, ?, ?, ?, NOW())""".stripMargin,
                Statement.RETURN_GENERATED_KEYS
            )
            ps.setLong(1, misionId)
            ps.setLong(2, transmisionId)
            ps.setString(3, resumenTexto)
            ps.setInt(4, atlas.misiones_activas)
            ps.setString(5, atlas.nivel_prioridad)
            ps.setString(6, atlas.agencia_responsable)
            ps.executeUpdate()
            val keys = ps.getGeneratedKeys
            keys.next()
            keys.getLong(1)
        }.getOrElse(throw new RuntimeException("No se pudo insertar resumen"))
    }

    // ----------------------------------------------------------
    // FLUJO INVERSO: consultar historial completo de una mision
    // ----------------------------------------------------------
    def consultarHistorial(misionNombre: String): List[Map[String, Any]] = {
        Using(connection()) { conn =>
            val sql =
                """SELECT
                  |  m.nombre AS mision,
                  |  s.nombre AS sonda,
                  |  s.estado_sensores,
                  |  o.ascension_recta,
                  |  o.declinacion,
                  |  o.lecturas_espectrales,
                  |  o.intensidad_senal,
                  |  o.regularidad,
                  |  o.clasificacion,
                  |  o.confianza,
                  |  o.timestamp_utc,
                  |  t.cadena_trazabilidad,
                  |  t.hash_sha256,
                  |  t.nivel_alerta,
                  |  t.justificacion_alerta,
                  |  t.timestamp_hermes,
                  |  t.timestamp_atlas,
                  |  t.timestamp_ground,
                  |  r.resumen_consolidado,
                  |  r.misiones_activas,
                  |  r.prioridad,
                  |  r.agencia_responsable,
                  |  r.creado_en
                  |FROM misiones m
                  |JOIN sondas s       ON s.id = m.sonda_id
                  |JOIN observaciones o ON o.mision_id = m.id
                  |JOIN transmisiones t ON t.observacion_id = o.id
                  |JOIN resumenes r    ON r.transmision_id = t.id
                  |WHERE m.nombre = ?
                  |ORDER BY o.timestamp_utc DESC""".stripMargin

            val ps = conn.prepareStatement(sql)
            ps.setString(1, misionNombre)
            val rs = ps.executeQuery()
            val meta = rs.getMetaData
            val cols = (1 to meta.getColumnCount).map(meta.getColumnLabel)

            var rows: List[Map[String, Any]] = Nil
            while (rs.next()) {
                val row = cols.map(col => col -> Option(rs.getObject(col)).getOrElse("")).toMap
                rows = rows :+ row
            }
            rows
        }.getOrElse(Nil)
    }

    // ----------------------------------------------------------
    // Contar observaciones históricas de una misión
    // ----------------------------------------------------------
    def contarObservaciones(misionNombre: String): Int = {
        Using(connection()) { conn =>
            val ps = conn.prepareStatement(
                """SELECT COUNT(*) FROM observaciones o
                  |JOIN misiones m ON m.id = o.mision_id
                  |WHERE m.nombre = ?""".stripMargin
            )
            ps.setString(1, misionNombre)
            val rs = ps.executeQuery()
            if (rs.next()) rs.getInt(1) else 0
        }.getOrElse(0)
    }

    // ----------------------------------------------------------
    // Helper: parsear ISO 8601 o datetime a Timestamp SQL
    // ----------------------------------------------------------
    private def parseTimestamp(s: String): Timestamp = {
        Try {
            Timestamp.from(Instant.parse(s))
        }.orElse(Try {
            val ldt = LocalDateTime.parse(s, DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"))
            Timestamp.valueOf(ldt)
        }).getOrElse(Timestamp.from(Instant.now()))
    }
}
