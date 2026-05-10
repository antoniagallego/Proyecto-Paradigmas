-- ============================================================
--  PROYECTO KEPLER — Base de datos GROUND
--  Sistema: Voyager IX → HERMES → ATLAS → GROUND
-- ============================================================

CREATE DATABASE IF NOT EXISTS kepler_ground
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE kepler_ground;

-- ============================================================
-- TABLA 1: misiones
-- Representa cada misión espacial registrada en el sistema.
-- Es la entidad raíz de la que dependen sondas y anomalías.
-- ============================================================
CREATE TABLE misiones (
    id                      INT             NOT NULL AUTO_INCREMENT,
    identificador_mision    VARCHAR(100)    NOT NULL UNIQUE,   -- ej: "VOYAGER-IX-KEPLER-2024"
    nombre_mision           VARCHAR(200)    NOT NULL,          -- ej: "Proyecto Kepler"
    planeta_destino         VARCHAR(100)    NOT NULL,          -- ej: "Kepler-442b"
    sistema_destino         VARCHAR(100)    NOT NULL,          -- ej: "Kepler-442"
    fecha_lanzamiento       DATETIME        NOT NULL,
    objetivo_principal      TEXT            NOT NULL,          -- descripción del objetivo original
    estado_mision           ENUM(
                                'ACTIVA',
                                'COMPLETADA',
                                'FALLIDA',
                                'EN_TRANSITO'
                            )               NOT NULL DEFAULT 'ACTIVA',
    agencia_responsable     VARCHAR(150)    NOT NULL,          -- agencia del consorcio a cargo
    total_misiones_activas  INT             NOT NULL DEFAULT 0, -- snapshot de misiones activas en ATLAS al momento
    created_at              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                                            ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id)
) ENGINE=InnoDB;


-- ============================================================
-- TABLA 2: sondas
-- Representa el estado físico y operativo de Voyager IX
-- en el momento exacto de la observación.
-- Vinculada a la misión que la controla.
-- ============================================================
CREATE TABLE sondas (
    id                          INT             NOT NULL AUTO_INCREMENT,
    mision_id                   INT             NOT NULL,          -- FK → misiones
    nombre_sonda                VARCHAR(100)    NOT NULL,          -- ej: "Voyager IX"
    distancia_tierra_km         BIGINT          NOT NULL,          -- distancia en km al momento de la obs.
    anios_en_viaje              DECIMAL(5,2)    NOT NULL,          -- años desde lanzamiento
    estado_sensor_camara        ENUM(
                                    'OPERATIVO',
                                    'DEGRADADO',
                                    'FALLO'
                                )               NOT NULL DEFAULT 'OPERATIVO',
    estado_sensor_espectral     ENUM(
                                    'OPERATIVO',
                                    'DEGRADADO',
                                    'FALLO'
                                )               NOT NULL DEFAULT 'OPERATIVO',
    estado_sensor_geometrico    ENUM(
                                    'OPERATIVO',
                                    'DEGRADADO',
                                    'FALLO'
                                )               NOT NULL DEFAULT 'OPERATIVO',
    nivel_bateria_porcentaje    DECIMAL(5,2)    NOT NULL,          -- 0.00 a 100.00
    temperatura_celsius         DECIMAL(8,2)    NOT NULL,          -- temperatura interna
    velocidad_km_s              DECIMAL(10,4)   NOT NULL,          -- velocidad en km/s
    timestamp_observacion_utc   DATETIME(3)     NOT NULL,          -- momento exacto UTC con ms
    cadena_reglas_inferencia    TEXT            NOT NULL,          -- reglas recorridas por el sistema lógico
    created_at                  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    CONSTRAINT fk_sondas_mision
        FOREIGN KEY (mision_id)
        REFERENCES misiones (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE=InnoDB;


-- ============================================================
-- TABLA 3: anomalias
-- Representa la anomalía detectada por Voyager IX.
-- Contiene coordenadas, datos espectrales y nivel de confianza.
-- Vinculada tanto a la sonda que la detectó como a la misión.
-- ============================================================
CREATE TABLE anomalias (
    id                      INT             NOT NULL AUTO_INCREMENT,
    sonda_id                INT             NOT NULL,          -- FK → sondas
    mision_id               INT             NOT NULL,          -- FK → misiones (acceso directo)
    ascension_recta_grados  DECIMAL(15,10)  NOT NULL,          -- en grados decimales (0 a 360)
    declinacion_grados      DECIMAL(15,10)  NOT NULL,          -- en grados decimales (-90 a 90)
    coordenadas_raw         VARCHAR(200)    NOT NULL,          -- string original tal como llega de Voyager
    lectura_espectral       LONGTEXT        NOT NULL,          -- lectura completa del sector observado
    nivel_confianza         DECIMAL(5,4)    NOT NULL,          -- valor entre 0.0000 y 1.0000
    tipo_anomalia           ENUM(
                                'ESTRUCTURA_GEOMETRICA',
                                'ANOMALIA_ESPECTRAL',
                                'INTERFERENCIA_SENSOR',
                                'ORIGEN_DESCONOCIDO',
                                'SIN_CLASIFICAR'
                            )               NOT NULL DEFAULT 'SIN_CLASIFICAR',
    descripcion_anomalia    TEXT            NOT NULL,          -- descripción generada por el sistema lógico
    es_origen_natural       TINYINT(1)      NOT NULL DEFAULT 0, -- 0 = no natural (conclusión por descarte)
    timestamp_deteccion_utc DATETIME(3)     NOT NULL,          -- mismo timestamp que viene de Voyager
    created_at              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    CONSTRAINT fk_anomalias_sonda
        FOREIGN KEY (sonda_id)
        REFERENCES sondas (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_anomalias_mision
        FOREIGN KEY (mision_id)
        REFERENCES misiones (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT chk_nivel_confianza
        CHECK (nivel_confianza >= 0 AND nivel_confianza <= 1)
) ENGINE=InnoDB;


-- ============================================================
-- TABLA 4: transmisiones
-- Representa el viaje completo del mensaje por los nodos:
-- Voyager IX → HERMES → ATLAS → GROUND.
-- Guarda toda la información de integridad y trazabilidad.
-- Vinculada a la anomalía que originó la transmisión.
-- ============================================================
CREATE TABLE transmisiones (
    id                          INT             NOT NULL AUTO_INCREMENT,
    anomalia_id                 INT             NOT NULL,          -- FK → anomalias
    mision_id                   INT             NOT NULL,          -- FK → misiones

    -- Datos de HERMES
    identificador_hermes        VARCHAR(100)    NOT NULL,          -- ID del satélite retransmisor
    hash_sha256_original        CHAR(64)        NOT NULL,          -- hash calculado por HERMES al recibir
    hash_sha256_verificado      CHAR(64)        NOT NULL,          -- hash recalculado para verificar
    integridad_verificada       TINYINT(1)      NOT NULL DEFAULT 0, -- 1 = hashes coinciden
    correccion_errores_aplicada TINYINT(1)      NOT NULL DEFAULT 0, -- 1 = se aplicó corrección
    timestamp_recepcion_hermes  DATETIME(3)     NOT NULL,          -- cuando HERMES recibió la señal
    timestamp_reenvio_hermes    DATETIME(3)     NOT NULL,          -- cuando HERMES reenvió a ATLAS

    -- Datos de ATLAS
    identificador_atlas         VARCHAR(100)    NOT NULL,          -- ID del nodo ATLAS
    nivel_prioridad             INT             NOT NULL,          -- nivel asignado por ATLAS (máximo = crítico)
    prioridad_descripcion       VARCHAR(200)    NOT NULL,          -- descripción del nivel de prioridad
    timestamp_recepcion_atlas   DATETIME(3)     NOT NULL,
    timestamp_reenvio_atlas     DATETIME(3)     NOT NULL,

    -- Trazabilidad completa (JSON con cada salto)
    -- Formato: [{"nodo":"VOYAGER_IX","ts":"..."},{"nodo":"HERMES","ts":"..."},...]
    cadena_trazabilidad         JSON            NOT NULL,

    -- Datos de llegada a GROUND
    timestamp_recepcion_ground  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    created_at                  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    CONSTRAINT fk_transmisiones_anomalia
        FOREIGN KEY (anomalia_id)
        REFERENCES anomalias (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_transmisiones_mision
        FOREIGN KEY (mision_id)
        REFERENCES misiones (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT chk_hashes_iguales
        CHECK (
            (integridad_verificada = 1 AND hash_sha256_original = hash_sha256_verificado)
            OR integridad_verificada = 0
        )
) ENGINE=InnoDB;


-- ============================================================
-- TABLA 5: resumenes
-- Resumen consolidado generado por GROUND.
-- Cruza el nuevo hallazgo con el historial previo de la misión.
-- Es lo que aparece en pantalla cuando llegan los científicos.
-- Vinculado a transmisión, anomalía y misión.
-- ============================================================
CREATE TABLE resumenes (
    id                          INT             NOT NULL AUTO_INCREMENT,
    transmision_id              INT             NOT NULL,          -- FK → transmisiones
    anomalia_id                 INT             NOT NULL,          -- FK → anomalias
    mision_id                   INT             NOT NULL,          -- FK → misiones

    -- Contenido del resumen
    titulo_resumen              VARCHAR(300)    NOT NULL,
    contenido_resumen           LONGTEXT        NOT NULL,          -- resumen narrativo completo
    hallazgos_previos_conteo    INT             NOT NULL DEFAULT 0, -- cuántas anomalías previas había
    hallazgos_previos_detalle   JSON            NOT NULL,          -- detalle de anomalías anteriores de la misión
    nivel_alerta                INT             NOT NULL,          -- nivel de alerta (mismo que ATLAS asignó)
    justificacion_alerta        TEXT            NOT NULL,          -- por qué se asignó ese nivel
    conclusion_sistema          TEXT            NOT NULL,          -- conclusión final de GROUND
    requiere_accion_humana      TINYINT(1)      NOT NULL DEFAULT 1, -- 1 = sí requiere revisión humana

    -- Metadatos de generación
    generado_en                 DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    nodos_en_cadena             INT             NOT NULL DEFAULT 4, -- cuántos nodos participaron
    created_at                  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    CONSTRAINT fk_resumenes_transmision
        FOREIGN KEY (transmision_id)
        REFERENCES transmisiones (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_resumenes_anomalia
        FOREIGN KEY (anomalia_id)
        REFERENCES anomalias (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT fk_resumenes_mision
        FOREIGN KEY (mision_id)
        REFERENCES misiones (id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
) ENGINE=InnoDB;


-- ============================================================
-- DATOS DE PRUEBA — simulan el flujo completo del enunciado
-- ============================================================

-- 1. Misión
INSERT INTO misiones (
    identificador_mision, nombre_mision, planeta_destino,
    sistema_destino, fecha_lanzamiento, objetivo_principal,
    estado_mision, agencia_responsable, total_misiones_activas
) VALUES (
    'VOYAGER-IX-KEPLER-2024',
    'Proyecto Kepler',
    'Kepler-442b',
    'Kepler-442',
    '2024-03-15 08:00:00',
    'Fotografiar el planeta Kepler-442b y retornar datos espectrales que confirmen o descarten la presencia de agua líquida en su superficie.',
    'ACTIVA',
    'Consorcio Agencias Espaciales Unidas',
    140
);

-- 2. Sonda
INSERT INTO sondas (
    mision_id, nombre_sonda, distancia_tierra_km, anios_en_viaje,
    estado_sensor_camara, estado_sensor_espectral, estado_sensor_geometrico,
    nivel_bateria_porcentaje, temperatura_celsius, velocidad_km_s,
    timestamp_observacion_utc, cadena_reglas_inferencia
) VALUES (
    1,
    'Voyager IX',
    1200000000,
    17.00,
    'OPERATIVO',
    'OPERATIVO',
    'OPERATIVO',
    73.40,
    -189.50,
    17.2340,
    '2041-07-21 14:32:10.000',
    'R001:verificar_origen_geologico -> FALLO | R002:verificar_formacion_natural -> FALLO | R003:verificar_interferencia_sensor -> FALLO | R004:verificar_simetria_geometrica -> VERDADERO | CONCLUSION: origen_no_natural_conocido'
);

-- 3. Anomalía
INSERT INTO anomalias (
    sonda_id, mision_id, ascension_recta_grados, declinacion_grados,
    coordenadas_raw, lectura_espectral, nivel_confianza,
    tipo_anomalia, descripcion_anomalia, es_origen_natural,
    timestamp_deteccion_utc
) VALUES (
    1, 1,
    285.4723810000,
    -12.3401290000,
    'RA=285.472381 DEC=-12.340129',
    'BANDA_UV: 0.023 | BANDA_VIS: 0.847 | BANDA_IR: 0.412 | BANDA_RADIO: 0.001 | SIMETRIA_DETECTADA: SI | PATRON_GEOMETRICO: HEXAGONAL_REGULAR | REPETICION_ANGULAR: 60deg | REFLECTIVIDAD: 0.73',
    0.9700,
    'ESTRUCTURA_GEOMETRICA',
    'Estructura geométrica regular detectada en la superficie de Kepler-442b. Simetría hexagonal con repetición angular de 60 grados. Ninguna regla de geología planetaria ni formación natural explica el patrón observado. Clasificada por descarte como de origen no natural conocido.',
    0,
    '2041-07-21 14:32:10.000'
);

-- 4. Transmisión
INSERT INTO transmisiones (
    anomalia_id, mision_id,
    identificador_hermes, hash_sha256_original, hash_sha256_verificado,
    integridad_verificada, correccion_errores_aplicada,
    timestamp_recepcion_hermes, timestamp_reenvio_hermes,
    identificador_atlas, nivel_prioridad, prioridad_descripcion,
    timestamp_recepcion_atlas, timestamp_reenvio_atlas,
    cadena_trazabilidad, timestamp_recepcion_ground
) VALUES (
    1, 1,
    'HERMES-SAT-001',
    'a3f8c2d1e4b7690f2a1c3d5e7f9b0a2c4d6e8f0a1b3c5d7e9f1a3b5c7d9e1f3',
    'a3f8c2d1e4b7690f2a1c3d5e7f9b0a2c4d6e8f0a1b3c5d7e9f1a3b5c7d9e1f3',
    1, 1,
    '2041-07-21 14:35:44.213',
    '2041-07-21 14:35:44.891',
    'ATLAS-GROUND-CTL',
    9,
    'ALERTA MÁXIMA — Nivel nunca activado en 17 años de operación. Posible hallazgo de estructura artificial extraterrestre.',
    '2041-07-21 14:39:12.004',
    '2041-07-21 14:39:12.774',
    '[{"nodo":"VOYAGER_IX","timestamp":"2041-07-21T14:32:10.000Z","accion":"GENERACION_REPORTE"},{"nodo":"HERMES_SAT_001","timestamp":"2041-07-21T14:35:44.213Z","accion":"RECEPCION_Y_VERIFICACION_SHA256"},{"nodo":"ATLAS_GROUND_CTL","timestamp":"2041-07-21T14:39:12.004Z","accion":"ENRIQUECIMIENTO_Y_PRIORIZACION"},{"nodo":"GROUND_BUNKER_CH","timestamp":"2041-07-21T14:42:08.001Z","accion":"PERSISTENCIA_Y_RESUMEN"}]',
    '2041-07-21 14:42:08.001'
);

-- 5. Resumen
INSERT INTO resumenes (
    transmision_id, anomalia_id, mision_id,
    titulo_resumen, contenido_resumen,
    hallazgos_previos_conteo, hallazgos_previos_detalle,
    nivel_alerta, justificacion_alerta,
    conclusion_sistema, requiere_accion_humana,
    nodos_en_cadena
) VALUES (
    1, 1, 1,
    'ALERTA MÁXIMA — Estructura geométrica no natural detectada en Kepler-442b [Misión: Proyecto Kepler]',
    'El sistema GROUND ha recibido y procesado un reporte de alerta de máxima prioridad proveniente de Voyager IX, después de 17 años de misión. La sonda detectó una estructura geométrica regular de patrón hexagonal en la superficie de Kepler-442b a las 14:32:10 UTC del 21 de julio de 2041, ubicada en las coordenadas RA=285.472381 DEC=-12.340129. El sistema de inteligencia a bordo recorrió su cadena completa de reglas de clasificación (geología planetaria, formaciones naturales, interferencias de sensor, criterios astronómicos) sin encontrar ninguna explicación natural. La conclusión fue por descarte: la anomalía no tiene origen natural conocido. El nivel de confianza de la inferencia es 0.97/1.00. La señal viajó 1.200 millones de kilómetros, fue verificada por HERMES sin pérdida de integridad (SHA-256 confirmado), y elevada por ATLAS al nivel de prioridad máximo (9/9), nivel nunca antes activado en los 17 años de operación del consorcio. No existen hallazgos previos de anomalías no naturales en esta misión. Este es el primer evento de esta categoría registrado en el sistema.',
    0,
    '[]',
    9,
    'Nivel máximo asignado por ATLAS debido a la naturaleza del hallazgo: estructura geométrica de simetría no explicable por ningún modelo natural conocido, con nivel de confianza de 0.97. Primera vez en 17 años que se activa este nivel de alerta en el sistema.',
    'GROUND no toma decisiones operativas. El hallazgo ha sido persistido en su totalidad con trazabilidad completa desde Voyager IX. La cadena de custodia de los datos es íntegra. Se requiere revisión inmediata por parte del equipo científico del consorcio. Todos los registros están disponibles para auditoría.',
    1,
    4
);


-- ============================================================
-- VISTA ÚTIL: reconstrucción completa de un evento para auditoría
-- ============================================================
CREATE VIEW vista_evento_completo AS
SELECT
    m.identificador_mision,
    m.nombre_mision,
    m.planeta_destino,
    m.agencia_responsable,
    s.nombre_sonda,
    s.distancia_tierra_km,
    s.anios_en_viaje,
    s.timestamp_observacion_utc,
    s.cadena_reglas_inferencia,
    a.ascension_recta_grados,
    a.declinacion_grados,
    a.coordenadas_raw,
    a.nivel_confianza,
    a.tipo_anomalia,
    a.es_origen_natural,
    t.identificador_hermes,
    t.hash_sha256_original,
    t.integridad_verificada,
    t.nivel_prioridad,
    t.cadena_trazabilidad,
    t.timestamp_recepcion_ground,
    r.titulo_resumen,
    r.nivel_alerta,
    r.justificacion_alerta,
    r.conclusion_sistema,
    r.requiere_accion_humana,
    r.generado_en
FROM resumenes r
JOIN transmisiones t  ON r.transmision_id = t.id
JOIN anomalias    a  ON r.anomalia_id    = a.id
JOIN sondas       s  ON a.sonda_id       = s.id
JOIN misiones     m  ON r.mision_id      = m.id;
