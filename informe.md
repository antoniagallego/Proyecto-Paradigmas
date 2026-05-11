# Informe Técnico — Sistema Distribuido Kepler
## Paradigmas de Lenguajes de Programación

**Integrantes:** Antonia Gallego Marín - Felipe Tarapues - Sergio Lancheros

---

## 1. Arquitectura del Sistema

El sistema Kepler es una red de cuatro nodos REST que procesan, verifican y persisten observaciones astronómicas de forma encadenada. Cada nodo fue implementado en un lenguaje distinto, eligiendo el paradigma de programación que mejor se adecúa a la responsabilidad específica de ese nodo en la cadena.

```
VOYAGER-IX (Prolog, :8000)
    ↓  POST /api/recibir
HERMES (Haskell, :8001)
    ↓  POST /api/recibir
ATLAS (Java/Spring Boot, :8002)
    ↓  POST /api/recibir
GROUND (Scala/Akka HTTP, :8003)
    ↓  JDBC
MySQL (kepler)
```

El flujo inverso permite reconstruir la trazabilidad completa desde GROUND hacia el origen mediante `GET /api/historial/:mision`.

---

### 1.1 Voyager IX — Prolog (Puerto 8000)

**Rol:** Motor de inferencia lógica. Recibe una observación astronómica en bruto (coordenadas, lectura espectral, intensidad de señal, regularidad, elementos detectados) y determina si el fenómeno tiene origen natural o no natural mediante clasificación por descarte.

**Justificación del paradigma lógico:**

La clasificación de anomalías es un problema de inferencia por descarte: se evalúa si la observación puede ser explicada por alguno de los seis fenómenos geológicos conocidos (volcánico, impacto meteorítico, actividad tectónica, erosión química, interferencia electromagnética, depósito mineral). Si ninguna regla aplica, la anomalía es clasificada como `anomalia_no_natural` con confianza `0.95`.

Este razonamiento es inherentemente declarativo: las reglas expresan qué debe ser verdad para que un fenómeno aplique, no cómo calcularlo. Prolog permite expresar exactamente eso:

```prolog
es_fenomeno_natural(vulcanico, Intensidad, Regularidad, Elementos) :-
    Intensidad > 0.70,
    (member(fe, Elementos) ; member(hierro, Elementos)),
    (member(s,  Elementos) ; member(azufre,  Elementos)),
    Regularidad = irregular.
```

La base de conocimiento es separable del motor de inferencia (`clasificar_anomalia/7`), lo que permite agregar o modificar reglas sin cambiar el código de despacho. Un enfoque imperativo habría requerido cadenas de `if-else` que mezclan lógica de dominio con flujo de control.

El nodo expone también `GET /api/clasificar` para inferencia aislada y `GET /api/reglas` para consultar el catálogo de reglas activas. El envío automático a HERMES ocurre en `enviar_a_hermes/2` usando `http_post` de la biblioteca estándar de SWI-Prolog.

---

### 1.2 HERMES — Haskell (Puerto 8001)

**Rol:** Satélite de retransmisión. Recibe el reporte de Voyager IX, computa y registra su hash SHA-256, verifica integridad mediante checksum XOR, enriquece el payload con metadatos propios y lo reenvía a ATLAS.

**Justificación del paradigma funcional puro:**

La responsabilidad central de HERMES es la verificación criptográfica y el enriquecimiento de datos. Estas operaciones son idealmente funciones puras: dado el mismo payload, producen siempre el mismo hash, el mismo checksum, el mismo reporte enriquecido. Haskell impone esta pureza en el sistema de tipos: las funciones que no tienen efectos de I/O no pueden tenerlos.

```haskell
computeSha256 :: BS.ByteString -> Text
computeSha256 bs = T.pack $ show (hash bs :: Digest SHA256)

computeXorChecksum :: BS.ByteString -> Word8
computeXorChecksum = BS.foldl' xor 0

enrichPayload :: VoyagerReport -> Text -> Text -> Text -> Text -> HermesReport
enrichPayload report sha256Hash hermesId timestamp correctionStatus = ...
```

Ninguna de estas funciones tiene acceso al I/O. Los efectos (leer del socket, enviar a ATLAS, registrar errores) ocurren exclusivamente en los bordes del sistema (`main`, `serveConnection`, `sendToAtlas`). Esto garantiza que la lógica de verificación es predecible y testeable en aislamiento.

El servidor HTTP fue implementado directamente sobre `Network.Socket` sin usar los frameworks `wai`/`warp`. Esta decisión se explica en la sección 2.

---

### 1.3 ATLAS — Java con Spring Boot (Puerto 8002)

**Rol:** Estación de coordinación. Recibe el reporte verificado de HERMES, asigna nivel de prioridad en función de la confianza reportada por Voyager IX, construye la justificación de alerta, mantiene el contador de misiones activas y reenvía el payload enriquecido a GROUND.

**Justificación del paradigma orientado a objetos:**

ATLAS administra estado compartido (el contador `misionesActivas` de tipo `AtomicInteger`) y coordina múltiples servicios. El paradigma orientado a objetos permite encapsular esta lógica en `AtlasService`, separando las responsabilidades de enriquecimiento y despacho del controlador HTTP:

```java
public String asignarPrioridad(double confianza) {
    if (confianza >= 0.90) return "CRITICA";
    if (confianza >= 0.70) return "ALTA";
    if (confianza >= 0.50) return "MEDIA";
    return "BAJA";
}
```

Los métodos de `AtlasService` son deterministas (mismo input → mismo output), siguiendo la disciplina funcional dentro del paradigma OO. El uso de Spring Boot se justifica por la interoperabilidad: el sistema requiere deserializar JSON de Haskell y serializar JSON para Scala, y Spring's `RestTemplate` con Jackson maneja la conversión sin configuración manual.

---

### 1.4 GROUND — Scala con Akka HTTP (Puerto 8003)

**Rol:** Sistema de persistencia. Recibe el payload enriquecido por ATLAS, lo persiste en cinco tablas MySQL relacionadas (sondas, misiones, observaciones, transmisiones, resúmenes), genera un resumen consolidado de texto, y expone el flujo inverso para consulta del historial completo de una misión.

**Justificación del paradigma funcional/OO híbrido:**

Scala permite combinar el paradigma funcional con el orientado a objetos. La capa de persistencia (`DatabaseService`) usa `scala.util.Try` y `scala.util.Using` para manejar recursos de base de datos sin excepciones desnudas:

```scala
def insertarObservacion(misionId: Long, atlas: AtlasPayload): Long = {
    Using(connection()) { conn =>
        val ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)
        // ...
        keys.getLong(1)
    }.getOrElse(throw new RuntimeException("No se pudo insertar observacion"))
}
```

`Using` garantiza que la conexión JDBC se cierra siempre, incluso ante excepciones. El servidor HTTP usa Akka HTTP, cuyo modelo de actores maneja la concurrencia de múltiples peticiones sin bloqueo. El flujo inverso (`consultarHistorial`) reconstruye la cadena completa mediante un JOIN de cinco tablas, devolviendo los registros como `List[Map[String, Any]]`.

---

## 2. Decisión Técnica con Alternativa Descartada

### Elegido: servidor HTTP raw sobre `Network.Socket` en HERMES

**Alternativa descartada:** usar `wai` + `warp`, el stack HTTP estándar de Haskell.

Al configurar el entorno de desarrollo en Windows, la dependencia transitiva de `warp` incluye `unix-compat`, un paquete que emula llamadas de sistema POSIX sobre Windows. En GHC 9.6.7 con el toolchain `clang`/`lld` usado en Windows, `unix-compat` no compila. El error se produce en la fase de linkado y no tiene solución directa sin modificar la cadena de herramientas del compilador.

La decisión fue reemplazar `wai`/`warp` por un servidor HTTP mínimo implementado directamente sobre `Network.Socket`:

```haskell
runServer :: Int -> Router -> IO ()
runServer port router = withSocketsDo $ do
    addrs <- getAddrInfo (Just hints) (Just "0.0.0.0") (Just (show port))
    sock  <- socket (addrFamily (head addrs)) Stream defaultProtocol
    bind sock (addrAddress (head addrs))
    listen sock 10
    forever $ do
        (conn, _) <- accept sock
        void $ forkIO $ try (serveConnection conn router) >>= ...
```

La implementación requirió manejar manualmente el parsing de headers HTTP (extracción de `Content-Length` para leer el cuerpo completo), la serialización de respuestas HTTP/1.1 y la lectura incremental del cuerpo con `recvN` para evitar truncamiento en TCP segmentado. Esto añadió complejidad, pero eliminó la dependencia problemática y mantuvo el control total sobre el servidor sin abstracciones intermedias.

---

## 3. Problemas Encontrados y Cómo Se Resolvieron

### 3.1 Truncamiento del cuerpo HTTP por TCP segmentado

**Problema:** Los primeros tests mostraban que HERMES devolvía `400 JSON invalido` cuando Voyager IX le enviaba el reporte. El payload de Voyager IX incluye seis nombres de reglas en `cadena_reglas`, produciendo un JSON de ~550 bytes. La implementación original de `serveConnection` leía el socket con una única llamada `recv sock 65536`, que en Windows puede devolver solo el primer segmento TCP (los headers HTTP), dejando el cuerpo sin leer.

**Resolución:** Se implementó `parseContentLength` para extraer el valor del header `Content-Length`, y `recvN` para leer exactamente los bytes del cuerpo en un loop:

```haskell
recvN :: Socket -> Int -> IO BS.ByteString
recvN sock 0 = return BS.empty
recvN sock n = do
    chunk <- recv sock (min n 65536)
    if BS.null chunk then return BS.empty
    else do
        let remaining = n - BS.length chunk
        if remaining <= 0 then return chunk
        else (chunk <>) <$> recvN sock remaining
```

---

### 3.2 Resolución IPv6 de `localhost` en Windows

**Problema:** En Windows, el nombre `localhost` se resuelve a `::1` (IPv6) por defecto desde Windows 10 v1703. El servidor de HERMES enlazaba en `0.0.0.0` (IPv4), por lo que las conexiones a `localhost:8001` no llegaban al socket correcto. El error en Voyager IX era `existence_error(http_reply, 'http://localhost:8001/api/recibir')`.

**Resolución:** Se reemplazó `localhost` por `127.0.0.1` en todas las URLs inter-servicio:
- `inference.pl`: URL de HERMES → `http://127.0.0.1:8001`
- `application.properties` de ATLAS: URL de GROUND → `http://127.0.0.1:8003`

---

### 3.3 Crash de HERMES por carácter em dash en stderr de Windows

**Problema:** Al agregar logs de diagnóstico, un string literal con `—` (em dash, U+2014) en una llamada `hPutStrLn stderr` causaba una excepción `hPutChar: invalid argument (cannot encode character '\8212')`. La consola de Windows usa por defecto la codificación OEM (CP437), que no incluye el em dash. La excepción se propagaba y cerraba el socket antes de enviar la respuesta HTTP, causando `existence_error` en Voyager IX.

**Resolución:** Se reemplazó el em dash por un guión ASCII (`-`) en todos los strings escritos a stderr. Todos los caracteres no-ASCII que van al cuerpo HTTP (respuestas JSON) no se ven afectados porque se envían como bytes raw sobre el socket.

---

### 3.4 `getColumnName` vs `getColumnLabel` en JDBC

**Problema:** El endpoint `GET /api/historial/:mision` de GROUND devolvía `"Mision no encontrada"` aunque la misión existía en MySQL con observaciones completas. La query SQL ejecutada directamente en MySQL devolvía los datos correctamente.

El error era en `DatabaseService.consultarHistorial`: el código usaba `ResultSetMetaData.getColumnName(i)` para construir el mapa de columnas. En MySQL Connector/J 8.x, `getColumnName` devuelve el nombre base de la columna (ej. `nombre` para `m.nombre AS mision`). Cuando el código luego llamaba `rs.getObject("nombre")`, el driver buscaba por label —no por nombre base— y no encontraba ninguna columna con ese label, lanzando `SQLException: Column 'nombre' not found`. `Using` capturaba la excepción silenciosamente y devolvía `Nil`, que el endpoint interpretaba como misión no encontrada.

**Resolución:**
```scala
// Antes (incorrecto):
val cols = (1 to meta.getColumnCount).map(meta.getColumnName)

// Después (correcto):
val cols = (1 to meta.getColumnCount).map(meta.getColumnLabel)
```

`getColumnLabel` devuelve el alias definido en el SELECT (`mision`, `sonda`, etc.), que coincide con lo que `getObject(String)` espera como label.

---

### 3.5 Timeout insuficiente de Voyager IX hacia HERMES

**Problema:** El pipeline completo (HERMES → ATLAS → GROUND → MySQL) tarda más de 10 segundos bajo carga inicial, especialmente en el primer request cuando ATLAS y GROUND inicializan sus conexiones. La llamada `http_post` en Voyager IX tenía `timeout(10)`, por lo que cancelaba la espera antes de recibir la respuesta, retornando `status: "hermes_unreachable"` aunque HERMES había procesado el request correctamente.

**Resolución:** Se aumentó el timeout a 60 segundos en `inference.pl`:
```prolog
http_post(URL, json(Reporte), Respuesta, [json_object(dict), timeout(60)])
```

---

*Fin del informe técnico.*
