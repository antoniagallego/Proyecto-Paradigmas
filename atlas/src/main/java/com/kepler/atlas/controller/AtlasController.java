package com.kepler.atlas.controller;

import com.kepler.atlas.model.AtlasPayload;
import com.kepler.atlas.model.HermesPayload;
import com.kepler.atlas.service.AtlasService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class AtlasController {

    @Autowired
    private AtlasService atlasService;

    // --------------------------------------------------------
    // GET /api/status — Health check
    // --------------------------------------------------------
    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> status() {
        return ResponseEntity.ok(Map.of(
            "status",      "ok",
            "nodo",        "ATLAS",
            "descripcion", "Estacion de Coordinacion - Gestion de Misiones",
            "puerto",      8002
        ));
    }

    // --------------------------------------------------------
    // POST /api/recibir — Recibe payload de HERMES,
    // asigna prioridad y trazabilidad, reenvía a GROUND
    // --------------------------------------------------------
    @PostMapping("/recibir")
    public ResponseEntity<Map<String, Object>> recibir(@RequestBody HermesPayload hermesPayload) {

        // Validar que el payload de Voyager no sea nulo
        if (hermesPayload.getPayloadVoyager() == null) {
            return ResponseEntity.badRequest().body(Map.of(
                "success", false,
                "error",   "payload_voyager es requerido"
            ));
        }

        // Enriquecer con datos de ATLAS
        AtlasPayload atlasPayload = atlasService.enriquecer(hermesPayload);

        // Reenviar a GROUND
        Object groundResponse = atlasService.enviarAGround(atlasPayload);

        return ResponseEntity.ok(Map.of(
            "success",        true,
            "atlas_payload",  atlasPayload,
            "ground_response", groundResponse
        ));
    }

    // --------------------------------------------------------
    // GET / — Info del nodo
    // --------------------------------------------------------
    @GetMapping("/")
    public ResponseEntity<Map<String, Object>> info() {
        return ResponseEntity.ok(Map.of(
            "nodo",        "ATLAS",
            "descripcion", "Estacion de Coordinacion — Interoperabilidad Universal",
            "lenguaje",    "Java 17 + Spring Boot",
            "puerto",      8002,
            "endpoints",   new String[]{
                "POST /api/recibir  — recibe de HERMES, enriquece, reenvía a GROUND",
                "GET  /api/status   — estado del nodo"
            }
        ));
    }
}
