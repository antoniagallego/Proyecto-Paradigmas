% ============================================================
%  VOYAGER IX — Motor de Inferencia Logica
%  Sistema Distribuido Kepler | Paradigmas de Lenguajes
%  Puerto: 8000
% ============================================================

:- module(server, [start_server/0, start_server/1]).

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_cors)).

:- use_module(knowledge_base).
:- use_module(inference).
:- use_module(routes).

:- set_setting(http:cors, [*]).

start_server :-
    start_server(8000).

start_server(Port) :-
    format("~n  ╔══════════════════════════════════════════╗~n"),
    format("  ║         V O Y A G E R   I X            ║~n"),
    format("  ║   Motor de Inferencia Logica            ║~n"),
    format("  ║   Clasificacion por Descarte            ║~n"),
    format("  ║   Puerto: ~w                          ║~n", [Port]),
    format("  ╚══════════════════════════════════════════╝~n~n"),
    http_server(http_dispatch, [port(Port), workers(4)]),
    format("[VOYAGER-IX] Activo en http://localhost:~w~n", [Port]),
    format("[VOYAGER-IX] Flujo: POST /api/observacion → HERMES → ATLAS → GROUND~n~n").

:- initialization(main, main).

main :-
    start_server(8000),
    thread_get_message(_).
