package com.kepler.atlas;

// ============================================================
//  ATLAS — Estacion de Coordinacion
//  Sistema Distribuido Kepler | Paradigmas de Lenguajes
//  Puerto: 8002
// ============================================================

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class AtlasApplication {
    public static void main(String[] args) {
        System.out.println();
        System.out.println("  ╔══════════════════════════════════════════╗");
        System.out.println("  ║         A T L A S                       ║");
        System.out.println("  ║   Estacion de Coordinacion              ║");
        System.out.println("  ║   Gestion de Misiones y Trazabilidad    ║");
        System.out.println("  ║   Puerto: 8002                          ║");
        System.out.println("  ╚══════════════════════════════════════════╝");
        System.out.println();
        SpringApplication.run(AtlasApplication.class, args);
    }
}
