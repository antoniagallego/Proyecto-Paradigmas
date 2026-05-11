package com.kepler.ground

import spray.json._

// ============================================================
// MODELOS DE DATOS — Case classes inmutables (paradigma funcional)
// ============================================================

case class VoyagerReport(
    id_mision:            String,
    ascension_recta:      Double,
    declinacion:          Double,
    lectura_espectral:    String,
    intensidad_senal:     Double,
    regularidad:          String,
    clasificacion:        String,
    confianza:            Double,
    timestamp_utc:        String,
    cadena_reglas:        List[String],
    reglas_coincidentes:  List[String],
    nodo_origen:          String
)

case class AtlasPayload(
    payload_voyager:      VoyagerReport,
    hash_sha256:          String,
    hermes_id:            String,
    timestamp_hermes:     String,
    timestamp_atlas:      String,
    verificado:           Boolean,
    trazabilidad:         String,
    nivel_prioridad:      String,
    agencia_responsable:  String,
    misiones_activas:     Int,
    justificacion_alerta: String,
    error_correction:     Option[String] = None
)

case class GroundResponse(
    success:             Boolean,
    observacion_id:      Long,
    transmision_id:      Long,
    resumen_id:          Long,
    resumen_consolidado: String,
    trazabilidad_final:  String
)

// ============================================================
// JSON FORMATS (spray-json)
// ============================================================

object JsonFormats extends DefaultJsonProtocol {

    implicit val voyagerFmt: RootJsonFormat[VoyagerReport] = jsonFormat12(VoyagerReport.apply)

    implicit object AtlasPayloadFormat extends RootJsonFormat[AtlasPayload] {
        def write(a: AtlasPayload): JsValue = JsObject(
            "payload_voyager"      -> a.payload_voyager.toJson,
            "hash_sha256"          -> a.hash_sha256.toJson,
            "hermes_id"            -> a.hermes_id.toJson,
            "timestamp_hermes"     -> a.timestamp_hermes.toJson,
            "timestamp_atlas"      -> a.timestamp_atlas.toJson,
            "verificado"           -> a.verificado.toJson,
            "trazabilidad"         -> a.trazabilidad.toJson,
            "nivel_prioridad"      -> a.nivel_prioridad.toJson,
            "agencia_responsable"  -> a.agencia_responsable.toJson,
            "misiones_activas"     -> a.misiones_activas.toJson,
            "justificacion_alerta" -> a.justificacion_alerta.toJson,
            "error_correction"     -> a.error_correction.getOrElse("").toJson
        )

        def read(json: JsValue): AtlasPayload = {
            val obj = json.asJsObject
            AtlasPayload(
                payload_voyager      = obj.fields("payload_voyager").convertTo[VoyagerReport],
                hash_sha256          = obj.fields("hash_sha256").convertTo[String],
                hermes_id            = obj.fields("hermes_id").convertTo[String],
                timestamp_hermes     = obj.fields("timestamp_hermes").convertTo[String],
                timestamp_atlas      = obj.fields("timestamp_atlas").convertTo[String],
                verificado           = obj.fields("verificado").convertTo[Boolean],
                trazabilidad         = obj.fields("trazabilidad").convertTo[String],
                nivel_prioridad      = obj.fields("nivel_prioridad").convertTo[String],
                agencia_responsable  = obj.fields("agencia_responsable").convertTo[String],
                misiones_activas     = obj.fields("misiones_activas").convertTo[Int],
                justificacion_alerta = obj.fields("justificacion_alerta").convertTo[String],
                error_correction     = obj.fields.get("error_correction").map(_.convertTo[String])
            )
        }
    }

    implicit val groundRespFmt: RootJsonFormat[GroundResponse] = jsonFormat6(GroundResponse.apply)
}
