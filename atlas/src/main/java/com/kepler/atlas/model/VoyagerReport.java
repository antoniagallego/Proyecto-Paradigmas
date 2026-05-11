package com.kepler.atlas.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;

public class VoyagerReport {

    @JsonProperty("id_mision")
    private String idMision;

    @JsonProperty("ascension_recta")
    private double ascensionRecta;

    @JsonProperty("declinacion")
    private double declinacion;

    @JsonProperty("lectura_espectral")
    private String lecturaEspectral;

    @JsonProperty("intensidad_senal")
    private double intensidadSenal;

    @JsonProperty("regularidad")
    private String regularidad;

    @JsonProperty("clasificacion")
    private String clasificacion;

    @JsonProperty("confianza")
    private double confianza;

    @JsonProperty("timestamp_utc")
    private String timestampUtc;

    @JsonProperty("cadena_reglas")
    private List<String> cadenaReglas;

    @JsonProperty("reglas_coincidentes")
    private List<String> reglasCoincidentes;

    @JsonProperty("nodo_origen")
    private String nodoOrigen;

    // Getters y setters

    public String getIdMision()               { return idMision; }
    public void   setIdMision(String v)       { this.idMision = v; }

    public double getAscensionRecta()             { return ascensionRecta; }
    public void   setAscensionRecta(double v)     { this.ascensionRecta = v; }

    public double getDeclinacion()            { return declinacion; }
    public void   setDeclinacion(double v)    { this.declinacion = v; }

    public String getLecturaEspectral()           { return lecturaEspectral; }
    public void   setLecturaEspectral(String v)   { this.lecturaEspectral = v; }

    public double getIntensidadSenal()        { return intensidadSenal; }
    public void   setIntensidadSenal(double v){ this.intensidadSenal = v; }

    public String getRegularidad()            { return regularidad; }
    public void   setRegularidad(String v)    { this.regularidad = v; }

    public String getClasificacion()          { return clasificacion; }
    public void   setClasificacion(String v)  { this.clasificacion = v; }

    public double getConfianza()              { return confianza; }
    public void   setConfianza(double v)      { this.confianza = v; }

    public String getTimestampUtc()           { return timestampUtc; }
    public void   setTimestampUtc(String v)   { this.timestampUtc = v; }

    public List<String> getCadenaReglas()          { return cadenaReglas; }
    public void         setCadenaReglas(List<String> v) { this.cadenaReglas = v; }

    public List<String> getReglasCoincidentes()          { return reglasCoincidentes; }
    public void         setReglasCoincidentes(List<String> v) { this.reglasCoincidentes = v; }

    public String getNodoOrigen()             { return nodoOrigen; }
    public void   setNodoOrigen(String v)     { this.nodoOrigen = v; }
}
