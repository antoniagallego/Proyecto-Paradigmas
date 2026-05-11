package com.kepler.atlas.service;

// ============================================================
//  PARADIGMA OO: encapsulamiento de la lógica de negocio.
//  Los métodos son deterministas: dado el mismo input
//  producen el mismo output (equivalente funcional en OO).
// ============================================================

import com.kepler.atlas.model.AtlasPayload;
import com.kepler.atlas.model.HermesPayload;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.lang.NonNull;
import org.springframework.web.client.RestTemplate;

import java.time.Instant;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class AtlasService {

    @Value("${ground.url:http://localhost:8003}")
    private String groundUrl;

    private static final String AGENCIA_ID = "ESA-KEPLER-DIVISION-01";

    // Contador de misiones activas (estado compartido del nodo)
    private final AtomicInteger misionesActivas = new AtomicInteger(0);

    // --------------------------------------------------------
    // Asigna nivel de prioridad según confianza de Voyager IX
    // Método determinista: mismo input → mismo output
    // --------------------------------------------------------
    public String asignarPrioridad(double confianza) {
        if (confianza >= 0.90) return "CRITICA";
        if (confianza >= 0.70) return "ALTA";
        if (confianza >= 0.50) return "MEDIA";
        return "BAJA";
    }

    // --------------------------------------------------------
    // Construye la justificación del nivel de alerta
    // --------------------------------------------------------
    public String construirJustificacion(HermesPayload hermes, String prioridad) {
        String clasificacion = hermes.getPayloadVoyager().getClasificacion();
        double confianza = hermes.getPayloadVoyager().getConfianza();
        int numReglas = hermes.getPayloadVoyager().getCadenaReglas() != null
                      ? hermes.getPayloadVoyager().getCadenaReglas().size() : 0;
        int coincidentes = hermes.getPayloadVoyager().getReglasCoincidentes() != null
                         ? hermes.getPayloadVoyager().getReglasCoincidentes().size() : 0;

        return String.format(
            "Clasificacion VOYAGER-IX: %s. Confianza: %.2f. " +
            "Reglas evaluadas: %d, coincidentes: %d. " +
            "Hash SHA-256 verificado por HERMES: %s. Nivel asignado: %s.",
            clasificacion, confianza, numReglas, coincidentes,
            hermes.isVerificado() ? "SI" : "NO", prioridad
        );
    }

    // --------------------------------------------------------
    // Enriquece el payload con campos de ATLAS
    // --------------------------------------------------------
    public AtlasPayload enriquecer(HermesPayload hermes) {
        String prioridad     = asignarPrioridad(hermes.getPayloadVoyager().getConfianza());
        String justificacion = construirJustificacion(hermes, prioridad);
        int    activas       = misionesActivas.incrementAndGet();

        AtlasPayload payload = new AtlasPayload();
        payload.setPayloadVoyager(hermes.getPayloadVoyager());
        payload.setHashSha256(hermes.getHashSha256());
        payload.setHermesId(hermes.getHermesId());
        payload.setTimestampHermes(hermes.getTimestampHermes());
        payload.setTimestampAtlas(Instant.now().toString());
        payload.setVerificado(hermes.isVerificado());
        payload.setTrazabilidad(hermes.getTrazabilidad() + " -> ATLAS");
        payload.setNivelPrioridad(prioridad);
        payload.setAgenciaResponsable(AGENCIA_ID);
        payload.setMisionesActivas(activas);
        payload.setJustificacionAlerta(justificacion);
        payload.setErrorCorrection(hermes.getErrorCorrection());

        return payload;
    }

    // --------------------------------------------------------
    // Envía el payload enriquecido a GROUND
    // --------------------------------------------------------
    public Object enviarAGround(AtlasPayload payload) {
        try {
            RestTemplate restTemplate = new RestTemplate();

            // Evitar que RestTemplate lance excepción en respuestas 4xx/5xx
            restTemplate.setErrorHandler(new org.springframework.web.client.DefaultResponseErrorHandler() {
                @Override
                public boolean hasError(@NonNull org.springframework.http.client.ClientHttpResponse response) {
                    return false;
                }
            });

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<AtlasPayload> entity = new HttpEntity<>(payload, headers);

            ResponseEntity<Object> response = restTemplate.postForEntity(
                groundUrl + "/api/recibir", entity, Object.class
            );
            return response.getBody() != null ? response.getBody()
                : java.util.Map.of("status", "ground_ok_empty_body");
        } catch (Exception e) {
            return java.util.Map.of(
                "error", "GROUND no alcanzable: " + e.getMessage(),
                "status", "ground_unreachable"
            );
        }
    }
}
