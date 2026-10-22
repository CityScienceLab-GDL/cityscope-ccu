/**
* Name: Pedestrian_PoC_Continuous
* Description: Prototipo de movilidad peatonal con evasión de obstáculos mediante red espacial de navegación.
* Author: Equipo de Investigación
*/

model Pedestrian_PoC_Continuous

global {
    // Definición del entorno (500m x 500m)
    geometry shape <- square(500 #m);
    
    // Parámetros del Escenario
    string scenario <- "S1_MassiveEvent" among: ["S0_Normal", "S1_MassiveEvent"];
    int initial_pedestrians <- 150;
    int massive_evacuation_size <- 600;
    
    // Indicadores clave (KPIs)
    int total_evacuated <- 0;
    int total_active_pedestrians <- 0;
    float current_avg_speed <- 0.0 #m/#s;
    
    // Grafo de navegación para evitar obstáculos
    graph free_graph;

    init {
        // 1. Crear Recinto de Eventos Masivos (Arena/Estadio)
        create arena number: 1 {
            shape <- polygon([{180, 50}, {320, 50}, {320, 130}, {180, 130}]);
        }

        // 2. Crear Edificios / Facultades
        create building number: 1 { shape <- polygon([{50, 50}, {140, 50}, {140, 180}, {50, 180}]); }
        create building number: 1 { shape <- polygon([{360, 50}, {450, 50}, {450, 180}, {360, 180}]); }
        create building number: 1 { shape <- polygon([{60, 320}, {180, 320}, {180, 420}, {60, 420}]); }
        create building number: 1 { shape <- polygon([{320, 320}, {440, 320}, {440, 420}, {320, 420}]); }

        // 3. Crear Barrera/Muro Central (Avenida sin paso a desnivel del Escenario 0)
        create obstacle_wall number: 1 { shape <- polygon([{0, 245}, {180, 245}, {180, 255}, {0, 255}]); }
        create obstacle_wall number: 1 { shape <- polygon([{220, 245}, {280, 245}, {280, 255}, {220, 255}]); }
        create obstacle_wall number: 1 { shape <- polygon([{320, 245}, {500, 245}, {500, 255}, {320, 255}]); }

        // 4. Crear Puertas de Salida / Paradas de Transporte
        create exit_gate number: 1 { location <- {250, 485}; name <- "Sur_Estacion"; }
        create exit_gate number: 1 { location <- {20, 250}; name <- "Oeste_Av"; }
        create exit_gate number: 1 { location <- {480, 250}; name <- "Este_Av"; }

        // 5. Construcción del Grafo de Espacio Libre
        geometry obstacles_union <- union(building as list) + union(obstacle_wall as list);
        ask cell {
            if (self overlaps obstacles_union) {
                is_wall <- true;
            }
        }
        free_graph <- as_distance_graph(cell where (!each.is_wall), 12.0 #m);

        // 6. Instanciar Peatones
        if (scenario = "S0_Normal") {
            create pedestrian number: initial_pedestrians {
                location <- any_location_in(one_of(cell where (!each.is_wall)));
                target_gate <- one_of(exit_gate);
            }
        } else if (scenario = "S1_MassiveEvent") {
            create pedestrian number: initial_pedestrians {
                location <- any_location_in(one_of(cell where (!each.is_wall)));
                target_gate <- one_of(exit_gate);
            }
            create pedestrian number: massive_evacuation_size {
                location <- any_location_in(one_of(arena));
                target_gate <- one_of(exit_gate);
            }
        }
    }

    reflex update_kpis {
        total_active_pedestrians <- length(pedestrian);
        if (total_active_pedestrians > 0) {
            current_avg_speed <- mean(pedestrian collect each.current_speed);
        } else {
            current_avg_speed <- 0.0;
        }
    }
}

// Malla espacial para cálculo de rutas navegables
grid cell width: 50 height: 50 neighbors: 8 {
    bool is_wall <- false;
}

// -------------------------------------------------------------------
// ESPECIES Y COMPORTAMIENTO FÍSICO
// -------------------------------------------------------------------

species building {
    aspect default {
        draw shape color: rgb(85, 85, 85) border: rgb(51, 51, 51);
        draw "Facultad / Edificio" at: location + {-30, 0} color: #white font: font("SansSerif", 10, #bold);
    }
}

species obstacle_wall {
    aspect default {
        draw shape color: rgb(139, 0, 0) border: #black;
    }
}

species arena {
    aspect default {
        draw shape color: rgb(75, 0, 130) border: rgb(51, 51, 51);
        draw "Foro / Arena Masiva" at: location + {-45, 0} color: #white font: font("SansSerif", 11, #bold);
    }
}

species exit_gate {
    string name;
    aspect default {
        draw circle(12 #m) color: rgb(0, 136, 255) border: #white;
        draw name at: location + {-20, -15} color: rgb(0, 136, 255) font: font("SansSerif", 10, #bold);
    }
}

species pedestrian skills: [moving] {
    exit_gate target_gate;
    float free_speed <- rnd(1.1, 1.4) #m/#s;
    float current_speed <- free_speed;
    int nearby_density <- 0;
    rgb p_color <- #green;

    reflex walk_and_evade {
        if (target_gate != nil) {
            nearby_density <- length(pedestrian at_distance 2.5 #m);
            
            if (nearby_density > 8) {
                current_speed <- free_speed * 0.25;
                p_color <- #red;
            } else if (nearby_density > 4) {
                current_speed <- free_speed * 0.6;
                p_color <- #orange;
            } else {
                current_speed <- free_speed;
                p_color <- #green;
            }

            // Movimiento utilizando el grafo de navegación libre
            do goto target: target_gate.location 
                    speed: current_speed 
                    on: free_graph;

            if (self distance_to target_gate.location <= 12.0 #m) {
                total_evacuated <- total_evacuated + 1;
                do die;
            }
        }
    }

    aspect default {
        draw circle(1.8 #m) color: p_color border: #black;
    }
}

// -------------------------------------------------------------------
// EXPERIMENTO Y VISUALIZACIÓN
// -------------------------------------------------------------------

experiment PoC_Pedestrian_Simulation type: gui {
    parameter "Escenario:" var: scenario category: "Configuración";
    parameter "Población Inicial:" var: initial_pedestrians category: "Configuración";
    parameter "Aforo Evacuación (S1):" var: massive_evacuation_size category: "Configuración";

    output {
    	layout #split;
        display main_map type: opengl {
            species building aspect: default;
            species obstacle_wall aspect: default;
            species arena aspect: default;
            species exit_gate aspect: default;
            species pedestrian aspect: default;
        }

        display Dashboard {
            chart "Avance de Evacuación (Personas)" type: series position: {0, 0} size: {1, 0.5} {
                data "Peatones en Campus" value: total_active_pedestrians color: #orange;
                data "Evacuados" value: total_evacuated color: #green;
            }
            chart "Velocidad Promedio de Caminata (m/s)" type: series position: {0, 0.5} size: {1, 0.5} {
                data "Velocidad m/s" value: current_avg_speed color: #blue;
            }
        }
    }
}