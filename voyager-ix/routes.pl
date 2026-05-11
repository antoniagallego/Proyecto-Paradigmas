:- module(routes, []).

:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_cors)).

:- use_module(knowledge_base).
:- use_module(inference).

% ======================================================
% REGISTRO DE RUTAS
% ======================================================

:- http_handler(root(.),                 handle_root,        [methods([get])]).
:- http_handler(root(api/status),        handle_status,      [methods([get, options])]).
:- http_handler(root(api/observacion),   handle_observacion, [methods([post, options])]).
:- http_handler(root(api/reglas),        handle_reglas,      [methods([get, options])]).
:- http_handler(root(api/clasificar),    handle_clasificar,  [methods([post, options])]).

% ======================================================
% HELPERS
% ======================================================

set_cors :-
    format("Access-Control-Allow-Origin: *~n"),
    format("Access-Control-Allow-Methods: GET, POST, OPTIONS~n"),
    format("Access-Control-Allow-Headers: Content-Type~n").

ok_json(Data) :-
    set_cors,
    reply_json_dict(Data, [status(200)]).

error_json(Code, Msg) :-
    set_cors,
    reply_json_dict(_{success: false, error: Msg}, [status(Code)]).

read_body(Request, Body) :-
    catch(
        http_read_json_dict(Request, Body, []),
        _,
        Body = _{}
    ).

required(Body, Key, Value) :-
    (   get_dict(Key, Body, Value)
    ->  true
    ;   throw(error(missing_field(Key), routes))
    ).

optional(Body, Key, Default, Value) :-
    (   get_dict(Key, Body, Value)
    ->  true
    ;   Value = Default
    ).

% ======================================================
% GET / - Info del nodo
% ======================================================

handle_root(Request) :-
    cors_enable(Request, [methods([get])]),
    ok_json(_{
        nodo:        "VOYAGER-IX",
        descripcion: "Motor de Inferencia Logica - Clasificacion de Anomalias Geologicas",
        lenguaje:    "SWI-Prolog",
        puerto:      8000,
        endpoints: [
            "POST /api/observacion  — flujo principal: inferencia + reenvio a HERMES",
            "GET  /api/status       — estado del nodo",
            "GET  /api/reglas       — reglas geologicas disponibles",
            "POST /api/clasificar   — solo inferencia, sin reenvio"
        ]
    }).

% ======================================================
% GET /api/status
% ======================================================

handle_status(Request) :-
    cors_enable(Request, [methods([get])]),
    todas_las_reglas(Reglas),
    length(Reglas, N),
    ok_json(_{
        status:          "ok",
        nodo:            "VOYAGER-IX",
        descripcion:     "Motor de Inferencia Logica",
        puerto:          8000,
        reglas_cargadas: N
    }).

% ======================================================
% GET /api/reglas - Catalogo de reglas geologicas
% ======================================================

handle_reglas(Request) :-
    cors_enable(Request, [methods([get])]),
    todas_las_reglas(Reglas),
    maplist(describir_regla, Reglas, Descripciones),
    ok_json(_{
        success: true,
        total:   length(Reglas),
        reglas:  Descripciones
    }).

describir_regla(vulcanico, _{
    id:          "vulcanico",
    descripcion: "Actividad volcanica: Fe+S, patron irregular, intensidad > 0.70",
    requiere:    ["elemento:fe o hierro", "elemento:s o azufre", "regularidad:irregular", "intensidad > 0.70"]
}).
describir_regla(impacto_meteorico, _{
    id:          "impacto_meteorico",
    descripcion: "Impacto meteoritico: presencia de Ir o Ni, intensidad > 0.85",
    requiere:    ["elemento:ir/iridio o ni/niquel", "intensidad > 0.85"]
}).
describir_regla(actividad_tectonica, _{
    id:          "actividad_tectonica",
    descripcion: "Actividad tectonica: Si+Al, patron lineal o laminar",
    requiere:    ["elemento:si o silicio", "elemento:al o aluminio", "regularidad:lineal o laminar"]
}).
describir_regla(erosion_quimica, _{
    id:          "erosion_quimica",
    descripcion: "Erosion quimica: O+Ca, intensidad < 0.40",
    requiere:    ["elemento:o u oxigeno", "elemento:ca o calcio", "intensidad < 0.40"]
}).
describir_regla(interferencia_electromagnetica, _{
    id:          "interferencia_electromagnetica",
    descripcion: "Interferencia EM: patron estrictamente periodico",
    requiere:    ["regularidad:periodico"]
}).
describir_regla(deposito_mineral, _{
    id:          "deposito_mineral",
    descripcion: "Deposito mineral: intensidad 0.30-0.60, patron uniforme",
    requiere:    ["intensidad entre 0.30 y 0.60", "regularidad:uniforme"]
}).

% ======================================================
% POST /api/observacion  — ENDPOINT PRINCIPAL DEL FLUJO
%
% Recibe la observacion de la sonda, ejecuta inferencia
% logica, genera el reporte y lo reenvía automáticamente
% a HERMES para continuar el flujo distribuido.
%
% Body JSON:
%   mision_id         : string  (ej. "M-KEPLER-001")
%   ascension_recta   : float   (grados)
%   declinacion       : float   (grados)
%   lectura_espectral : string  (ej. "Fe:0.31,Si:0.58")
%   intensidad_senal  : float   0.0-1.0
%   regularidad       : string  (geometrica|irregular|lineal|...)
%   elementos         : array   (ej. ["Fe","Si","Al"])
% ======================================================

handle_observacion(Request) :-
    cors_enable(Request, [methods([post])]),
    read_body(Request, Body),
    catch(
        process_observacion(Body),
        error(missing_field(Field), _),
        (   atom_string(Field, FieldStr),
            string_concat("Campo requerido: ", FieldStr, Msg),
            error_json(400, Msg)
        )
    ).

process_observacion(Body) :-
    % --- Extraer campos ---
    required(Body, mision_id,       MisionId),
    required(Body, ascension_recta, RA),
    required(Body, declinacion,     Dec),
    required(Body, lectura_espectral, LectEsp),
    required(Body, intensidad_senal, Intensidad),
    required(Body, regularidad,     RegStr),
    optional(Body, elementos,       [], ElemStrs),

    % --- Convertir tipos ---
    atom_string(RegAtom, RegStr),
    maplist(string_to_element, ElemStrs, Elementos),

    % --- Validar rango de intensidad ---
    (   number(Intensidad), Intensidad >= 0.0, Intensidad =< 1.0
    ->  true
    ;   throw(error(missing_field('intensidad_senal debe ser 0.0-1.0'), routes))
    ),

    % --- Ejecutar inferencia ---
    catch(
        generar_reporte(MisionId, RA, Dec, LectEsp,
                        Intensidad, RegAtom, Elementos, Reporte),
        InfErr,
        (term_string(InfErr, IEStr),
         throw(error(inference_failed(IEStr), routes)))
    ),

    % --- Enviar a HERMES ---
    enviar_a_hermes(Reporte, HermesResp),

    % --- Responder ---
    ok_json(_{
        success:          true,
        reporte_voyager:  Reporte,
        hermes_response:  HermesResp
    }).

% ======================================================
% POST /api/clasificar - Solo inferencia, sin reenvio
% Util para testing del motor logico de forma aislada
% ======================================================

handle_clasificar(Request) :-
    cors_enable(Request, [methods([post])]),
    read_body(Request, Body),
    catch(
        (
            required(Body, intensidad_senal, Intensidad),
            required(Body, regularidad, RegStr),
            optional(Body, elementos, [], ElemStrs),
            atom_string(RegAtom, RegStr),
            maplist(string_to_element, ElemStrs, Elementos),
            clasificar_anomalia(Intensidad, RegAtom, Elementos,
                                Clasificacion, Confianza,
                                ReglasTodas, ReglasCoincidentes),
            maplist(atom_string, ReglasTodas, RT),
            maplist(atom_string, ReglasCoincidentes, RC),
            atom_string(Clasificacion, ClasStr),
            ok_json(_{
                success:              true,
                clasificacion:        ClasStr,
                confianza:            Confianza,
                cadena_reglas:        RT,
                reglas_coincidentes:  RC
            })
        ),
        error(missing_field(F), _),
        (atom_string(F, FS),
         string_concat("Campo requerido: ", FS, M),
         error_json(400, M))
    ).
