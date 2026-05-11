package com.kepler.atlas.model;

import com.fasterxml.jackson.annotation.JsonProperty;

public class HermesPayload {

    @JsonProperty("payload_voyager")
    private VoyagerReport payloadVoyager;

    @JsonProperty("hash_sha256")
    private String hashSha256;

    @JsonProperty("hermes_id")
    private String hermesId;

    @JsonProperty("timestamp_hermes")
    private String timestampHermes;

    @JsonProperty("verificado")
    private boolean verificado;

    @JsonProperty("trazabilidad")
    private String trazabilidad;

    @JsonProperty("error_correction")
    private String errorCorrection;

    // Getters y setters

    public VoyagerReport getPayloadVoyager()           { return payloadVoyager; }
    public void          setPayloadVoyager(VoyagerReport v){ this.payloadVoyager = v; }

    public String getHashSha256()              { return hashSha256; }
    public void   setHashSha256(String v)      { this.hashSha256 = v; }

    public String getHermesId()                { return hermesId; }
    public void   setHermesId(String v)        { this.hermesId = v; }

    public String getTimestampHermes()         { return timestampHermes; }
    public void   setTimestampHermes(String v) { this.timestampHermes = v; }

    public boolean isVerificado()              { return verificado; }
    public void    setVerificado(boolean v)    { this.verificado = v; }

    public String getTrazabilidad()            { return trazabilidad; }
    public void   setTrazabilidad(String v)    { this.trazabilidad = v; }

    public String getErrorCorrection()         { return errorCorrection; }
    public void   setErrorCorrection(String v) { this.errorCorrection = v; }
}
