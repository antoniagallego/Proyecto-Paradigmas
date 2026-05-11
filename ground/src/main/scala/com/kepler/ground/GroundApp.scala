package com.kepler.ground

// ============================================================
//  GROUND — Sistema de Persistencia MySQL
//  Sistema Distribuido Kepler | Paradigmas de Lenguajes
//  Puerto: 8003
// ============================================================

import akka.actor.typed.ActorSystem
import akka.actor.typed.scaladsl.Behaviors
import akka.http.scaladsl.Http
import akka.http.scaladsl.model._
import akka.http.scaladsl.server.Directives._
import akka.http.scaladsl.marshallers.sprayjson.SprayJsonSupport._
import spray.json._
import JsonFormats._

import scala.concurrent.{Await, ExecutionContext, Future}
import scala.concurrent.duration.Duration
import scala.util.{Failure, Success, Try}
import java.time.Instant

object GroundApp {

    def main(args: Array[String]): Unit = {

        println()
        println("  ╔══════════════════════════════════════════╗")
        println("  ║         G R O U N D                     ║")
        println("  ║   Sistema de Persistencia MySQL         ║")
        println("  ║   Trazabilidad Completa                 ║")
        println("  ║   Puerto: 8003                          ║")
        println("  ╚══════════════════════════════════════════╝")
        println()

        implicit val system: ActorSystem[Nothing] =
            ActorSystem(Behaviors.empty, "ground-system")
        implicit val ec: ExecutionContext = system.executionContext

        val db = new DatabaseService(
            host   = sys.env.getOrElse("DB_HOST", "localhost"),
            port   = sys.env.getOrElse("DB_PORT", "3306"),
            dbName = sys.env.getOrElse("DB_NAME", "kepler"),
            user   = sys.env.getOrElse("DB_USER", "kepler"),
            pass   = sys.env.getOrElse("DB_PASS", "kepler123")
        )

        db.initialize()

        val routes = buildRoutes(db)

        Http().newServerAt("0.0.0.0", 8003).bind(routes).onComplete {
            case Success(_) =>
                println("[GROUND] Activo en http://localhost:8003")
                println("[GROUND] Endpoints: POST /api/recibir | GET /api/historial/:mision | GET /api/status")
            case Failure(ex) =>
                println(s"[GROUND] ERROR al iniciar servidor: ${ex.getMessage}")
                system.terminate()
        }

        Await.ready(system.whenTerminated, Duration.Inf)
    }

    // ============================================================
    // RUTAS
    // ============================================================

    def buildRoutes(db: DatabaseService)(implicit ec: ExecutionContext) = {

        val corsHeaders = List(
            headers.RawHeader("Access-Control-Allow-Origin", "*"),
            headers.RawHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
            headers.RawHeader("Access-Control-Allow-Headers", "Content-Type")
        )

        def withCors(route: akka.http.scaladsl.server.Route) =
            respondWithHeaders(corsHeaders)(route)

        withCors(concat(

            // --------------------------------------------------
            // GET /api/status
            // --------------------------------------------------
            path("api" / "status") {
                get {
                    complete(HttpEntity(
                        ContentTypes.`application/json`,
                        """{"status":"ok","nodo":"GROUND","descripcion":"Sistema de Persistencia MySQL","puerto":8003}"""
                    ))
                }
            },

            // --------------------------------------------------
            // GET / — Info del nodo
            // --------------------------------------------------
            pathSingleSlash {
                get {
                    complete(HttpEntity(
                        ContentTypes.`application/json`,
                        """{
                          |"nodo":"GROUND",
                          |"descripcion":"Sistema de Persistencia MySQL — Trazabilidad Completa",
                          |"lenguaje":"Scala + Akka HTTP",
                          |"puerto":8003,
                          |"endpoints":["POST /api/recibir","GET /api/historial/<mision>","GET /api/status"]
                          |}""".stripMargin
                    ))
                }
            },

            // --------------------------------------------------
            // POST /api/recibir — Recibe de ATLAS y persiste
            // --------------------------------------------------
            path("api" / "recibir") {
                options { complete(StatusCodes.OK) } ~
                post {
                    entity(as[AtlasPayload]) { atlas =>
                        val result = Future {
                            persistirTransmision(db, atlas)
                        }

                        onComplete(result) {
                            case Success(resp) =>
                                complete(StatusCodes.OK,
                                    HttpEntity(ContentTypes.`application/json`,
                                        resp.toJson.prettyPrint))
                            case Failure(ex) =>
                                complete(StatusCodes.InternalServerError,
                                    HttpEntity(ContentTypes.`application/json`,
                                        s"""{"success":false,"error":"${ex.getMessage}"}"""))
                        }
                    }
                }
            },

            // --------------------------------------------------
            // GET /api/historial/<mision>
            // FLUJO INVERSO: consulta historial desde MySQL
            // --------------------------------------------------
            path("api" / "historial" / Segment) { misionId =>
                get {
                    val result = Future {
                        db.consultarHistorial(misionId)
                    }

                    onComplete(result) {
                        case Success(rows) if rows.nonEmpty =>
                            val jsonRows = rows.map(row =>
                                JsObject(row.map { case (k, v) =>
                                    k -> anyToJson(v)
                                })
                            )
                            complete(HttpEntity(
                                ContentTypes.`application/json`,
                                JsObject(
                                    "success"        -> JsBoolean(true),
                                    "mision"         -> JsString(misionId),
                                    "total_registros"-> JsNumber(rows.size),
                                    "trazabilidad"   -> JsString("GROUND ← ATLAS ← HERMES ← VOYAGER-IX"),
                                    "historial"      -> JsArray(jsonRows.toVector)
                                ).prettyPrint
                            ))
                        case Success(_) =>
                            complete(StatusCodes.NotFound,
                                HttpEntity(ContentTypes.`application/json`,
                                    s"""{"success":false,"error":"Mision no encontrada: $misionId"}"""))
                        case Failure(ex) =>
                            complete(StatusCodes.InternalServerError,
                                HttpEntity(ContentTypes.`application/json`,
                                    s"""{"success":false,"error":"${ex.getMessage}"}"""))
                    }
                }
            },

            // --------------------------------------------------
            // GET /api/historial — Todas las misiones
            // --------------------------------------------------
            path("api" / "historial") {
                get {
                    // Retorna lista de misiones disponibles
                    complete(HttpEntity(
                        ContentTypes.`application/json`,
                        """{"info":"Usa GET /api/historial/<nombre_mision> para consultar una mision especifica"}"""
                    ))
                }
            }
        ))
    }

    // ============================================================
    // LOGICA DE PERSISTENCIA
    // ============================================================

    def persistirTransmision(db: DatabaseService, atlas: AtlasPayload): GroundResponse = {
        val v = atlas.payload_voyager

        // 1. Obtener/crear sonda y misión
        val sondaId  = db.getOrCreateSonda("VOYAGER-IX")
        val misionId = db.getOrCreateMision(sondaId, v.id_mision)

        // 2. Contar historial previo para el resumen
        val obsAnteriores = db.contarObservaciones(v.id_mision)

        // 3. Insertar observación
        val obsId = db.insertarObservacion(misionId, atlas)

        // 4. Insertar transmisión
        val transId = db.insertarTransmision(obsId, atlas)

        // 5. Generar resumen consolidado
        val trazabilidadFinal = atlas.trazabilidad + " -> GROUND"
        val resumenTexto = generarResumen(atlas, obsAnteriores, trazabilidadFinal)

        // 6. Insertar resumen
        val resId = db.insertarResumen(misionId, transId, atlas, resumenTexto)

        println(s"[GROUND] Transmision persistida — Obs:$obsId Trans:$transId Res:$resId")

        GroundResponse(
            success             = true,
            observacion_id      = obsId,
            transmision_id      = transId,
            resumen_id          = resId,
            resumen_consolidado = resumenTexto,
            trazabilidad_final  = trazabilidadFinal
        )
    }

    // Genera el resumen consolidado cruzando el hallazgo con el historial
    def generarResumen(atlas: AtlasPayload, obsAnteriores: Int, trazabilidad: String): String = {
        val v = atlas.payload_voyager
        val nivelAlerta = if (v.clasificacion == "anomalia_no_natural") "ALERTA MAXIMA" else "OBSERVACION RUTINARIA"

        s"""[$nivelAlerta] Anomalia detectada por ${v.nodo_origen} en mision ${v.id_mision}.
           |Coordenadas: RA=${v.ascension_recta}°, Dec=${v.declinacion}°.
           |Lectura espectral: ${v.lectura_espectral}.
           |Clasificacion: ${v.clasificacion} (confianza: ${v.confianza}).
           |${v.cadena_reglas.size} reglas geologicas evaluadas; ${v.reglas_coincidentes.size} coincidieron.
           |Hash SHA-256 verificado por HERMES: ${atlas.hash_sha256.take(16)}...
           |Nivel de prioridad ATLAS: ${atlas.nivel_prioridad}.
           |Agencia responsable: ${atlas.agencia_responsable}.
           |Misiones activas al momento: ${atlas.misiones_activas}.
           |Historial previo de la mision: $obsAnteriores observaciones registradas.
           |Trazabilidad completa: $trazabilidad.
           |Timestamp GROUND: ${Instant.now()}.""".stripMargin
    }

    // Convierte Any a JsValue para la respuesta JSON
    def anyToJson(v: Any): JsValue = v match {
        case s: String  => JsString(s)
        case n: Number  => JsNumber(n.doubleValue())
        case b: Boolean => JsBoolean(b)
        case null       => JsNull
        case other      => JsString(other.toString)
    }
}
