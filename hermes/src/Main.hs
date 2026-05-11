{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

-- ============================================================
--  HERMES — Satelite de Retransmision
--  Sistema Distribuido Kepler | Paradigmas de Lenguajes
--  Puerto: 8001
--
--  PARADIGMA FUNCIONAL PURO:
--  Todas las transformaciones son funciones puras
--  (mismo input → mismo output, sin efectos laterales).
--  Los efectos de I/O ocurren solo en los bordes (main, handlers).
--
--  Servidor HTTP implementado sobre Network.Socket (sin wai/warp)
--  para evitar la dependencia transitiva unix-compat en Windows.
-- ============================================================

module Main where

import           Control.Concurrent         (forkIO)
import           Control.Exception          (SomeException, finally, try)
import           Control.Monad              (forever, unless, void)
import           Crypto.Hash                (Digest, SHA256, hash)
import           Data.Aeson                 (FromJSON (..), ToJSON (..),
                                             Value, decode, eitherDecode,
                                             encode, object, (.=))
import qualified Data.ByteString            as BS
import qualified Data.ByteString.Char8      as C8
import qualified Data.ByteString.Lazy       as BL
import           Data.Maybe                 (fromMaybe)
import           Data.Text                  (Text)
import qualified Data.Text                  as T
import           Data.Time.Clock            (getCurrentTime)
import           Data.Time.Format           (defaultTimeLocale, formatTime)
import           Data.Bits                  (xor)
import           Data.Word                  (Word8)
import           GHC.Generics               (Generic)
import           Network.HTTP.Simple        (getResponseBody, httpLBS,
                                             parseRequest, setRequestBodyJSON,
                                             setRequestHeader, setRequestMethod)
import           Network.Socket             (AddrInfo (..), AddrInfoFlag (..),
                                             Socket, SocketOption (..),
                                             SocketType (..), accept, bind,
                                             close, defaultHints,
                                             defaultProtocol, getAddrInfo,
                                             listen, setSocketOption, socket,
                                             withSocketsDo)
import           Network.Socket.ByteString  (recv, sendAll)
import           System.Environment         (lookupEnv)
import           System.IO                  (hPutStrLn, stderr)

-- ============================================================
-- TIPOS DE DATOS
-- ============================================================

data VoyagerReport = VoyagerReport
    { id_mision           :: Text
    , ascension_recta     :: Double
    , declinacion         :: Double
    , lectura_espectral   :: Text
    , intensidad_senal    :: Double
    , regularidad         :: Text
    , clasificacion       :: Text
    , confianza           :: Double
    , timestamp_utc       :: Text
    , cadena_reglas       :: [Text]
    , reglas_coincidentes :: [Text]
    , nodo_origen         :: Text
    } deriving (Show, Generic)

instance FromJSON VoyagerReport
instance ToJSON   VoyagerReport

data HermesReport = HermesReport
    { payload_voyager  :: VoyagerReport
    , hash_sha256      :: Text
    , hermes_id        :: Text
    , timestamp_hermes :: Text
    , verificado       :: Bool
    , trazabilidad     :: Text
    , error_correction :: Text
    } deriving (Show, Generic)

instance ToJSON HermesReport

-- ============================================================
-- FUNCIONES PURAS (paradigma funcional: sin efectos laterales)
-- ============================================================

computeSha256 :: BS.ByteString -> Text
computeSha256 bs = T.pack $ show (hash bs :: Digest SHA256)

computeXorChecksum :: BS.ByteString -> Word8
computeXorChecksum = BS.foldl' xor 0

verifyIntegrity :: BS.ByteString -> Word8 -> Bool
verifyIntegrity payload expectedChecksum =
    computeXorChecksum payload == expectedChecksum

verifySha256 :: BS.ByteString -> Text -> Bool
verifySha256 payload expectedHash = computeSha256 payload == expectedHash

enrichPayload :: VoyagerReport -> Text -> Text -> Text -> Text -> HermesReport
enrichPayload report sha256Hash hermesId timestamp correctionStatus =
    HermesReport
        { payload_voyager  = report
        , hash_sha256      = sha256Hash
        , hermes_id        = hermesId
        , timestamp_hermes = timestamp
        , verificado       = True
        , trazabilidad     = "VOYAGER-IX -> HERMES"
        , error_correction = correctionStatus
        }

alertLevel :: Double -> Text
alertLevel c
    | c >= 0.90 = "CRITICA"
    | c >= 0.70 = "ALTA"
    | c >= 0.50 = "MEDIA"
    | otherwise = "BAJA"

-- ============================================================
-- SERVIDOR HTTP MINIMO (reemplaza wai/warp)
-- Usa Network.Socket directamente — sin unix-compat en Windows
-- ============================================================

type Router = BS.ByteString -> BS.ByteString -> BS.ByteString -> IO (Int, BS.ByteString)

runServer :: Int -> Router -> IO ()
runServer port router = withSocketsDo $ do
    let hints = defaultHints { addrSocketType = Stream }
    addrs <- getAddrInfo (Just hints) (Just "0.0.0.0") (Just (show port))
    let addr = head addrs
    sock <- socket (addrFamily addr) Stream defaultProtocol
    setSocketOption sock ReuseAddr 1
    bind sock (addrAddress addr)
    listen sock 10
    forever $ do
        (conn, _) <- accept sock
        void $ forkIO $
            try (serveConnection conn router) >>=
                either
                    (\e -> hPutStrLn stderr $ "[HERMES] Error conexion: " <> show (e :: SomeException))
                    return

-- Lee bytes hasta tener n bytes o EOF
recvN :: Socket -> Int -> IO BS.ByteString
recvN sock 0 = return BS.empty
recvN sock n = do
    chunk <- recv sock (min n 65536)
    if BS.null chunk
        then return BS.empty
        else do
            let remaining = n - BS.length chunk
            if remaining <= 0
                then return chunk
                else do
                    rest <- recvN sock remaining
                    return (chunk <> rest)

-- Extrae el valor de Content-Length de los headers
parseContentLength :: BS.ByteString -> Maybe Int
parseContentLength headers =
    let ls = C8.lines headers
        isContentLength l =
            let low = C8.map (\c -> if c >= 'A' && c <= 'Z' then toEnum (fromEnum c + 32) else c) l
            in "content-length:" `BS.isPrefixOf` low
        extractValue l = C8.dropWhile (== ' ') (C8.drop 1 (C8.dropWhile (/= ':') l))
    in case filter isContentLength ls of
        (l:_) -> case reads (C8.unpack (extractValue l)) of
            [(n, _)] -> Just n
            _        -> Nothing
        _     -> Nothing

serveConnection :: Socket -> Router -> IO ()
serveConnection sock router = (`finally` close sock) $ do
    -- Leer headers (hasta \r\n\r\n)
    headerBuf <- recv sock 65536
    unless (BS.null headerBuf) $ do
        let (headerSection, rest) = C8.breakSubstring "\r\n\r\n" headerBuf
            partialBody           = if BS.null rest then BS.empty else BS.drop 4 rest
        -- Leer el resto del body segun Content-Length
        fullBody <- case parseContentLength headerSection of
            Nothing -> return partialBody
            Just cl ->
                let already = BS.length partialBody
                    need    = cl - already
                in if need <= 0
                    then return (BS.take cl partialBody)
                    else do
                        extra <- recvN sock need
                        return (partialBody <> extra)
        let firstLine = case C8.lines headerSection of { (l:_) -> l; [] -> "" }
            ws     = C8.words firstLine
            method = if length ws > 0 then ws !! 0 else "GET"
            path   = if length ws > 1 then ws !! 1 else "/"
        (status, respBody) <- router method path fullBody
        let statusLine = case status of
                200 -> "200 OK"
                400 -> "400 Bad Request"
                422 -> "422 Unprocessable Entity"
                _   -> "500 Internal Server Error"
            response = BS.concat
                [ "HTTP/1.1 ", C8.pack statusLine, "\r\n"
                , "Content-Type: application/json; charset=utf-8\r\n"
                , "Access-Control-Allow-Origin: *\r\n"
                , "Connection: close\r\n"
                , "Content-Length: ", C8.pack (show (BS.length respBody)), "\r\n"
                , "\r\n"
                , respBody
                ]
        sendAll sock response

-- ============================================================
-- HANDLERS
-- ============================================================

handleStatus :: IO (Int, BS.ByteString)
handleStatus = return (200,
    "{\"status\":\"ok\",\"nodo\":\"HERMES\",\"descripcion\":\"Satelite de Retransmision SHA-256\",\"puerto\":8001}")

handleRecibir :: Text -> BS.ByteString -> IO (Int, BS.ByteString)
handleRecibir atlasUrl body
    | BS.null body =
        return (400, "{\"error\":\"Payload vacio — se solicita retransmision\"}")
    | otherwise =
        case eitherDecode (BL.fromStrict body) :: Either String VoyagerReport of
            Left err -> do
                hPutStrLn stderr $ "[HERMES] JSON invalido: " <> err
                return (400, "{\"error\":\"JSON invalido — se solicita retransmision\"}")
            Right voyagerReport -> do
                let sha256Hash    = computeSha256 body
                    xorChecksum   = computeXorChecksum body
                    integrityOk   = verifyIntegrity body xorChecksum
                    correctionMsg = if integrityOk
                                      then "XOR checksum OK: " <> T.pack (show xorChecksum)
                                      else "CORRUPCION DETECTADA"
                if not integrityOk
                    then return (422, "{\"error\":\"Corrupcion de datos detectada — se solicita retransmision\"}")
                    else do
                        now <- getCurrentTime
                        let tsHermes = T.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" now)
                            hermesReport = enrichPayload
                                voyagerReport sha256Hash
                                "HERMES-SAT-001" tsHermes correctionMsg
                        atlasResult <- sendToAtlas atlasUrl hermesReport
                        let respBody = BL.toStrict $ encode $ object
                                [ "success"        .= True
                                , "hermes_report"  .= hermesReport
                                , "atlas_response" .= atlasResult
                                ]
                        return (200, respBody)

routeRequest :: Text -> Router
routeRequest atlasUrl method path body
    | method == "GET"  && path == "/api/status"  = handleStatus
    | method == "POST" && path == "/api/recibir" = handleRecibir atlasUrl body
    | otherwise = do
        hPutStrLn stderr $ "[HERMES] Ruta no encontrada: " <> C8.unpack method <> " " <> C8.unpack path
        return (400, "{\"error\":\"Ruta no encontrada\"}")

-- ============================================================
-- CLIENTE HTTP — envia a ATLAS (I/O en el borde)
-- ============================================================

sendToAtlas :: Text -> HermesReport -> IO Value
sendToAtlas atlasUrl report = do
    let url = T.unpack atlasUrl <> "/api/recibir"
    result <- try (do
        initReq <- parseRequest url
        let req = setRequestMethod "POST"
                $ setRequestHeader "Content-Type" ["application/json"]
                $ setRequestBodyJSON report
                $ initReq
        response <- httpLBS req
        case decode (getResponseBody response) :: Maybe Value of
            Just v  -> return v
            Nothing -> return $ object ["status" .= ("atlas_sin_respuesta_valida" :: Text)]
        ) :: IO (Either SomeException Value)
    case result of
        Right v  -> return v
        Left err -> do
            hPutStrLn stderr $ "[HERMES] Error al contactar ATLAS: " <> show err
            return $ object
                [ "error"  .= ("ATLAS no alcanzable" :: Text)
                , "status" .= ("atlas_unreachable" :: Text)
                ]

-- ============================================================
-- MAIN
-- ============================================================

main :: IO ()
main = do
    putStrLn ""
    putStrLn "  ╔══════════════════════════════════════════╗"
    putStrLn "  ║           H E R M E S                  ║"
    putStrLn "  ║   Satelite de Retransmision             ║"
    putStrLn "  ║   SHA-256 + Funciones Puras             ║"
    putStrLn "  ║   Puerto: 8001                          ║"
    putStrLn "  ╚══════════════════════════════════════════╝"
    putStrLn ""

    atlasBase <- fromMaybe "http://127.0.0.1:8002" <$> lookupEnv "ATLAS_URL"
    let atlasUrl = T.pack atlasBase

    putStrLn $ "[HERMES] Activo en http://localhost:8001"
    putStrLn $ "[HERMES] Reenviando a ATLAS: " <> T.unpack atlasUrl
    putStrLn ""

    runServer 8001 (routeRequest atlasUrl)
