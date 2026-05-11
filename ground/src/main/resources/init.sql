-- ============================================================
--  GROUND — Esquema MySQL
--  Sistema Distribuido Kepler | Paradigmas de Lenguajes
-- ============================================================

CREATE DATABASE IF NOT EXISTS kepler CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE kepler;

-- ------------------------------------------------------------
-- 1. sondas
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sondas (
    id                 INT AUTO_INCREMENT PRIMARY KEY,
    nombre             VARCHAR(100) NOT NULL UNIQUE,
    estado_sensores    VARCHAR(50)  NOT NULL DEFAULT 'OPERATIVO',
    fecha_lanzamiento  DATE         NOT NULL
);

-- Sonda predefinida del sistema
INSERT IGNORE INTO sondas (nombre, estado_sensores, fecha_lanzamiento)
VALUES ('VOYAGER-IX', 'OPERATIVO', '2024-03-15');

-- ------------------------------------------------------------
-- 2. misiones
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS misiones (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    sonda_id     INT          NOT NULL,
    nombre       VARCHAR(100) NOT NULL UNIQUE,
    descripcion  TEXT,
    fecha_inicio DATE         NOT NULL,
    FOREIGN KEY (sonda_id) REFERENCES sondas(id)
);

-- Mision predefinida
INSERT IGNORE INTO misiones (sonda_id, nombre, descripcion, fecha_inicio)
SELECT s.id, 'M-KEPLER-001',
       'Mision de exploracion de anomalias en Kepler-442b',
       '2026-01-01'
FROM sondas s WHERE s.nombre = 'VOYAGER-IX';

-- ------------------------------------------------------------
-- 3. observaciones
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS observaciones (
    id                    INT AUTO_INCREMENT PRIMARY KEY,
    mision_id             INT            NOT NULL,
    ascension_recta       DECIMAL(12, 6) NOT NULL,
    declinacion           DECIMAL(12, 6) NOT NULL,
    lecturas_espectrales  TEXT           NOT NULL,
    intensidad_senal      DECIMAL(5, 4)  NOT NULL,
    regularidad           VARCHAR(50)    NOT NULL,
    clasificacion         VARCHAR(100)   NOT NULL,
    confianza             DECIMAL(5, 4)  NOT NULL,
    timestamp_utc         DATETIME       NOT NULL,
    FOREIGN KEY (mision_id) REFERENCES misiones(id)
);

-- ------------------------------------------------------------
-- 4. transmisiones
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transmisiones (
    id                   INT AUTO_INCREMENT PRIMARY KEY,
    observacion_id       INT          NOT NULL,
    cadena_trazabilidad  TEXT         NOT NULL,
    hash_sha256          VARCHAR(64)  NOT NULL,
    nivel_alerta         VARCHAR(20)  NOT NULL,
    justificacion_alerta TEXT         NOT NULL,
    timestamp_hermes     DATETIME     NOT NULL,
    timestamp_atlas      DATETIME     NOT NULL,
    timestamp_ground     DATETIME     NOT NULL,
    FOREIGN KEY (observacion_id) REFERENCES observaciones(id)
);

-- ------------------------------------------------------------
-- 5. resumenes
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS resumenes (
    id                   INT AUTO_INCREMENT PRIMARY KEY,
    mision_id            INT          NOT NULL,
    transmision_id       INT          NOT NULL,
    resumen_consolidado  TEXT         NOT NULL,
    misiones_activas     INT          NOT NULL DEFAULT 0,
    prioridad            VARCHAR(20)  NOT NULL,
    agencia_responsable  VARCHAR(100) NOT NULL,
    creado_en            DATETIME     NOT NULL,
    FOREIGN KEY (mision_id)      REFERENCES misiones(id),
    FOREIGN KEY (transmision_id) REFERENCES transmisiones(id)
);
