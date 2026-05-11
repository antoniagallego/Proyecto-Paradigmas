# Proyecto Kepler — Sistema Distribuido
**Paradigmas de Lenguajes de Programación 2026-01**

Voyager IX detectó una anomalía geométrica en Kepler-442b. El sistema distribuye el análisis a través de 4 nodos REST, cada uno implementado en un paradigma distinto.

---

## Arquitectura y flujo

```
POST /api/observacion
        │
        ▼
┌─────────────────┐   reporte JSON    ┌────────────────┐   hash+enriquecido   ┌──────────────┐   prioridad+traz   ┌──────────────┐
│  VOYAGER IX     │ ──────────────►  │    HERMES      │ ──────────────────►  │    ATLAS     │ ─────────────────►  │    GROUND    │
│  Prolog :8000   │                  │  Haskell :8001 │                      │  Java :8002  │                     │  Scala :8003 │
│  Inferencia     │                  │  SHA-256 puro  │                      │  Prioridades │                     │  MySQL       │
│  por descarte   │                  │  Verificación  │                      │  Trazabilidad│                     │  5 entidades │
└─────────────────┘                  └────────────────┘                      └──────────────┘                     └──────────────┘
                                                                                                                         │
                                                                                                                         ▼
                                                                                                                    MySQL (kepler)
                                                                                                                    sondas
                                                                                                                    misiones
                                                                                                                    observaciones
                                                                                                                    transmisiones
                                                                                                                    resumenes

GET /api/historial/:mision ◄──────────────────────────────────────────────────────────── flujo inverso (MySQL → respuesta)
```

---

## Nodos

| Nodo | Lenguaje | Puerto | Paradigma | Responsabilidad |
|------|----------|--------|-----------|-----------------|
| Voyager IX | Prolog | 8000 | Lógico | Clasificación por descarte (KB geológica) |
| HERMES | Haskell | 8001 | Funcional puro | SHA-256, verificación, funciones sin efectos |
| ATLAS | Java | 8002 | OO/Imperativo | Gestión de misiones, prioridad, trazabilidad |
| GROUND | Scala | 8003 | Funcional/OO | Persistencia MySQL, resumen consolidado |

---

## Ejecutar con Docker

```bash
docker-compose up --build
```

---

## Flujo principal — ejemplo completo

### 1. Disparar el flujo desde Voyager IX

```bash
curl -X POST http://localhost:8000/api/observacion \
  -H "Content-Type: application/json" \
  -d '{
    "mision_id":        "M-KEPLER-001",
    "ascension_recta":  285.679,
    "declinacion":      -41.278,
    "lectura_espectral":"Fe:0.31,Si:0.58,Al:0.11",
    "intensidad_senal": 0.87,
    "regularidad":      "geometrica",
    "elementos":        ["Fe", "Si", "Al"]
  }'
```

Voyager IX ejecuta la inferencia lógica por descarte → ninguna regla geológica explica un
patrón `geometrica` + `Fe,Si,Al` → `clasificacion: anomalia_no_natural` con `confianza: 0.95`.
Luego auto-reenvía a HERMES, que lo envía a ATLAS, que lo envía a GROUND.

### 2. Flujo inverso — consultar historial desde GROUND

```bash
curl http://localhost:8003/api/historial/M-KEPLER-001
```

Responde con todos los datos almacenados en MySQL, incluyendo la cadena de trazabilidad
`VOYAGER-IX -> HERMES -> ATLAS -> GROUND`.

---

## Endpoints por nodo

### Voyager IX — Prolog :8000

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/api/observacion` | **Flujo principal** — inferencia + cadena completa |
| `POST` | `/api/clasificar` | Solo inferencia, sin reenvío (testing) |
| `GET`  | `/api/reglas` | Lista las 6 reglas geológicas |
| `GET`  | `/api/status` | Estado del nodo |

### HERMES — Haskell :8001

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/api/recibir` | Recibe reporte, calcula SHA-256, verifica, reenvía |
| `GET`  | `/api/status` | Estado del nodo |

### ATLAS — Java :8002

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/api/recibir` | Recibe de HERMES, asigna prioridad, reenvía a GROUND |
| `GET`  | `/api/status` | Estado del nodo |

### GROUND — Scala :8003

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/api/recibir` | Recibe de ATLAS, persiste en MySQL (5 tablas), genera resumen |
| `GET`  | `/api/historial/:mision` | **Flujo inverso** — historial completo desde MySQL |
| `GET`  | `/api/status` | Estado del nodo |

---

## Base de datos MySQL — 5 entidades

```sql
sondas        (id, nombre, estado_sensores, fecha_lanzamiento)
misiones      (id, sonda_id, nombre, descripcion, fecha_inicio)
observaciones (id, mision_id, ascension_recta, declinacion, lecturas_espectrales,
               intensidad_señal, regularidad, clasificacion, confianza, timestamp_utc)
transmisiones (id, observacion_id, cadena_trazabilidad, hash_sha256,
               nivel_alerta, justificacion_alerta,
               timestamp_hermes, timestamp_atlas, timestamp_ground)
resumenes     (id, mision_id, transmision_id, resumen_consolidado,
               misiones_activas, prioridad, agencia_responsable, creado_en)
```

---

## Reglas geológicas de Voyager IX

La KB tiene 6 reglas. Si **ninguna** aplica → `anomalia_no_natural` (confianza alta):

| Regla | Condiciones |
|-------|-------------|
| `vulcanico` | Fe+S presentes, `irregular`, intensidad > 0.70 |
| `impacto_meteorico` | Ir o Ni presentes, intensidad > 0.85 |
| `actividad_tectonica` | Si+Al presentes, patrón `lineal` o `laminar` |
| `erosion_quimica` | O+Ca presentes, intensidad < 0.40 |
| `interferencia_electromagnetica` | patrón `periodico` |
| `deposito_mineral` | intensidad 0.30–0.60, patrón `uniforme` |

El patrón `geometrica` **no coincide** con ninguna regla → clasificación por descarte.

---

## Desarrollo local (sin Docker)

```bash
# Voyager IX
cd voyager-ix && swipl server.pl

# HERMES
cd hermes && cabal run hermes

# ATLAS
cd atlas && mvn spring-boot:run

# GROUND (requiere MySQL en localhost:3306)
cd ground && sbt run
```
