:- module(knowledge_base, [
    todas_las_reglas/1,
    es_fenomeno_natural/4,
    clasificar_anomalia/7,
    string_to_element/2
]).

% ======================================================
% REGLAS DE GEOLOGIA PLANETARIA - Kepler-442b
% Cada regla intenta explicar una observacion como
% fenomeno geologico natural conocido.
% Si ninguna aplica → origen no natural (por descarte).
% ======================================================

todas_las_reglas([
    vulcanico,
    impacto_meteorico,
    actividad_tectonica,
    erosion_quimica,
    interferencia_electromagnetica,
    deposito_mineral
]).

% ------------------------------------------------------
% REGLA 1: Actividad volcánica
% Requiere: hierro + azufre, señal irregular, alta intensidad
% ------------------------------------------------------
es_fenomeno_natural(vulcanico, Intensidad, Regularidad, Elementos) :-
    Intensidad > 0.70,
    (member(fe, Elementos) ; member(hierro, Elementos)),
    (member(s, Elementos) ; member(azufre, Elementos)),
    Regularidad = irregular.

% ------------------------------------------------------
% REGLA 2: Impacto meteorítico
% Requiere: iridio o níquel (marcadores de impacto), intensidad muy alta
% ------------------------------------------------------
es_fenomeno_natural(impacto_meteorico, Intensidad, _Regularidad, Elementos) :-
    Intensidad > 0.85,
    (member(ir, Elementos) ; member(ni, Elementos) ;
     member(iridio, Elementos) ; member(niquel, Elementos)).

% ------------------------------------------------------
% REGLA 3: Actividad tectónica
% Requiere: silicio + aluminio, patrón lineal o laminar
% ------------------------------------------------------
es_fenomeno_natural(actividad_tectonica, _Intensidad, Regularidad, Elementos) :-
    (member(si, Elementos) ; member(silicio, Elementos)),
    (member(al, Elementos) ; member(aluminio, Elementos)),
    (Regularidad = lineal ; Regularidad = laminar).

% ------------------------------------------------------
% REGLA 4: Erosión química
% Requiere: oxígeno + calcio, baja intensidad
% ------------------------------------------------------
es_fenomeno_natural(erosion_quimica, Intensidad, _Regularidad, Elementos) :-
    Intensidad < 0.40,
    (member(o, Elementos) ; member(oxigeno, Elementos)),
    (member(ca, Elementos) ; member(calcio, Elementos)).

% ------------------------------------------------------
% REGLA 5: Interferencia electromagnética
% Requiere: patrón estrictamente periódico
% No aplica a patrones "geometricos" sin periodicidad
% ------------------------------------------------------
es_fenomeno_natural(interferencia_electromagnetica, _Intensidad, Regularidad, _Elementos) :-
    Regularidad = periodico.

% ------------------------------------------------------
% REGLA 6: Depósito mineral
% Requiere: intensidad media-baja, distribución uniforme
% ------------------------------------------------------
es_fenomeno_natural(deposito_mineral, Intensidad, Regularidad, _Elementos) :-
    Intensidad >= 0.30,
    Intensidad =< 0.60,
    Regularidad = uniforme.

% ======================================================
% MOTOR DE CLASIFICACION POR DESCARTE
% ======================================================

% clasificar_anomalia(+Intensidad, +Regularidad, +Elementos,
%                     -Clasificacion, -Confianza,
%                     -ReglasTodas, -ReglasCoincidentes)
clasificar_anomalia(Intensidad, Regularidad, Elementos,
                    Clasificacion, Confianza,
                    ReglasTodas, ReglasCoincidentes) :-
    todas_las_reglas(ReglasTodas),
    include(regla_aplica(Intensidad, Regularidad, Elementos),
            ReglasTodas,
            ReglasCoincidentes),
    length(ReglasCoincidentes, N),
    (   N =:= 0
    ->  Clasificacion = anomalia_no_natural,
        Confianza = 0.95
    ;   Clasificacion = fenomeno_natural,
        Confianza is max(0.05, 0.80 - N * 0.25)
    ).

regla_aplica(I, R, E, Regla) :-
    es_fenomeno_natural(Regla, I, R, E).

% Convierte string JSON "Fe" → átomo prolog fe
string_to_element(Str, Atom) :-
    string_lower(Str, Lower),
    atom_string(Atom, Lower).
