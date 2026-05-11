:- module(inference, [
    generar_reporte/8,
    enviar_a_hermes/2
]).

:- use_module(library(http/http_client)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_header)).
:- use_module(knowledge_base).

% ======================================================
% GENERACION DEL REPORTE DE ANOMALIA
% ======================================================

% generar_reporte(+MisionId, +RA, +Dec, +LectEsp,
%                 +Intensidad, +Regularidad, +Elementos,
%                 -Reporte)
generar_reporte(MisionId, RA, Dec, LectEsp,
                Intensidad, Regularidad, Elementos, Reporte) :-
    % 1. Clasificacion por descarte
    clasificar_anomalia(Intensidad, Regularidad, Elementos,
                        Clasificacion, Confianza,
                        ReglasTodas, ReglasCoincidentes),

    % 2. Timestamp UTC
    get_time(Stamp),
    format_time(atom(TsUTC), '%Y-%m-%dT%H:%M:%SZ', Stamp),

    % 3. Construir reporte
    maplist(atom_string, ReglasTodas, ReglasTTodasStr),
    maplist(atom_string, ReglasCoincidentes, ReglasCoinStr),
    atom_string(Clasificacion, ClasStr),

    Reporte = _{
        id_mision:            MisionId,
        ascension_recta:      RA,
        declinacion:          Dec,
        lectura_espectral:    LectEsp,
        intensidad_senal:     Intensidad,
        regularidad:          Regularidad,
        clasificacion:        ClasStr,
        confianza:            Confianza,
        timestamp_utc:        TsUTC,
        cadena_reglas:        ReglasTTodasStr,
        reglas_coincidentes:  ReglasCoinStr,
        nodo_origen:          "VOYAGER-IX"
    }.

% ======================================================
% ENVIO AUTOMATICO AL SIGUIENTE NODO (HERMES)
% ======================================================

hermes_url(URL) :-
    (   getenv('HERMES_URL', Base)
    ->  true
    ;   Base = 'http://127.0.0.1:8001'
    ),
    atomic_list_concat([Base, '/api/recibir'], URL).

enviar_a_hermes(Reporte, Respuesta) :-
    hermes_url(URL),
    catch(
        http_post(URL, json(Reporte), Respuesta,
                  [json_object(dict), timeout(60)]),
        Error,
        (   term_string(Error, ErrStr),
            Respuesta = _{
                error:  ErrStr,
                status: "hermes_unreachable",
                nota:   "Voyager IX genero el reporte pero no pudo contactar HERMES"
            }
        )
    ).
