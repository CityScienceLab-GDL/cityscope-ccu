/**
* Name: Pedestrian_Graph_Simulation
* Description: Modelo de simulación de movilidad urbana basado en grafos peatonales (O(N) Complexity)
*              soporte para 5 escenarios interactivos (0, 1, 1e, 2, 2b).
*/

model Pedestrian_Graph_Simulation

global {
    float step <- 1.0 #s;
    
    // -------------------------------------------------------------------
    // PARAMETROS DEL EXPERIMENTO Y ESCENARIOS
    // -------------------------------------------------------------------
    string scenario_mode <- "Escenario 1 (Desalojo 30k)" among: [
        "Escenario 0 (Línea Base)", 
        "Escenario 1 (Desalojo 30k)", 
        "Escenario 1e (Crisis Extrema)", 
        "Escenario 2 (Avenida Subterránea)", 
        "Escenario 2b (Polígono Vivo)"
    ];
    
    int scaling_factor <- 10; // 1 agente representa a 10 personas reales
    
    // Archivos GIS
    file net_shp <- file("../includes/shp/events/pedestrian_network_clean.shp");
    file arena_shp <- file("../includes/shp/events/estadio.shp");
    file parking_shp <- file("../includes/shp/events/parking.shp");
    
    geometry shape <- envelope(net_shp);
    
    // Grafo Peatonal y Mapa de Pesos
    graph pedestrian_network;
    map<pedestrian_edge, float> edge_weights;
    
    // Métricas del Sistema
    int simulated_capacity;
    float base_speed;
    int total_spawned <- 0;
    int total_evacuated <- 0;
    int active_agents <- 0;
    int critical_congested_edges <- 0;

    init {
        // 1. Cargar geometrías GIS
        create pedestrian_edge from: net_shp;
        if (file_exists("../includes/shp/arena.shp")) { create arena from: arena_shp; }
        if (file_exists("../includes/shp/parking.shp")) { create parking_lot from: parking_shp; }
        
        // 2. Configurar el escenario inicial
        do setup_scenario;
        
        // 3. Construir el Grafo Peatonal
        pedestrian_network <- as_edge_graph(pedestrian_edge);
    }

    action setup_scenario {
        // Parámetros dinámicos según el escenario
        if (scenario_mode = "Escenario 0 (Línea Base)") {
            simulated_capacity <- int(3000 / scaling_factor); // 300 agentes
            base_speed <- 1.3 #m/#s;
        } else if (scenario_mode = "Escenario 1 (Desalojo 30k)") {
            simulated_capacity <- int(30000 / scaling_factor); // 3,000 agentes
            base_speed <- 1.3 #m/#s;
        } else if (scenario_mode = "Escenario 1e (Crisis Extrema)") {
            simulated_capacity <- int(30000 / scaling_factor); // 3,000 agentes
            base_speed <- 0.8 #m/#s; // Velocidad reducida por lluvia
        } else if (scenario_mode = "Escenario 2 (Avenida Subterránea)") {
            simulated_capacity <- int(30000 / scaling_factor); // 3,000 agentes
            base_speed <- 1.3 #m/#s;
        } else if (scenario_mode = "Escenario 2b (Polígono Vivo)") {
            simulated_capacity <- int(15000 / scaling_factor); // 1,500 agentes
            base_speed <- 1.1 #m/#s;
        }

        // Configuración de penalizaciones en la red
        ask pedestrian_edge {
            is_disabled <- false;
            // En Escenario 1e, simulamos tramos anegados/bloqueados aleatorios (15% de la red)
            if (scenario_mode = "Escenario 1e (Crisis Extrema)" and flip(0.15)) {
                is_disabled <- true;
            }
        }
    }

    // Actualización de Pesos del Grafo por Congestión (Macroscópico O(N))
    reflex update_network_weights {
        critical_congested_edges <- 0;
        
        ask pedestrian_edge {
            if (is_disabled) {
                // Arista bloqueada por inundación (peso infinito)
                edge_weights[self] <- 999999.0;
                congestion_level <- 1.0;
            } else {
                // Conteo de agentes transitando por el tramo
                int occupants <- length(pedestrian at_distance (2.0 #m));
                float max_capacity <- max([1.0, shape.perimeter * 0.8]); // Capacidad estimada
                
                // Nivel de saturación (0.0 a 1.0)
                congestion_level <- min([1.0, occupants / max_capacity]);
                
                if (congestion_level > 0.7) {
                    critical_congested_edges <- critical_congested_edges + 1;
                }
                
                // El peso incrementa exponencialmente si el tramo está saturado (efecto embotellamiento)
                float weight_factor <- max([0.05, 1.0 - congestion_level]);
                edge_weights[self] <- shape.perimeter / weight_factor;
            }
        }
        
        // Actualizar el grafo con la matriz de pesos recalculada
        pedestrian_network <- pedestrian_network with_weights edge_weights;
    }

    // Inyección progresiva de peatones
    reflex spawn_pedestrians {
        if (total_spawned < simulated_capacity) {
            int spawn_rate <- int(800 / scaling_factor);
            int to_spawn <- min([spawn_rate, simulated_capacity - total_spawned]);
            
            point spawn_pt;
            if (!empty(arena as list)) {
                spawn_pt <- any_location_in(first(arena).shape);
            } else {
                spawn_pt <- any(pedestrian_network.vertices);
            }

            create pedestrian number: to_spawn {
                location <- spawn_pt;
                speed <- base_speed * rnd(0.85, 1.15);
                
                // Definir nodo de destino (Estacionamiento o punto aleatorio en la red)
                if (scenario_mode = "Escenario 2b (Polígono Vivo)") {
                    target_point <- any(pedestrian_network.vertices);
                } else if (!empty(parking_lot as list)) {
                    target_point <- (any(parking_lot)).location;
                } else {
                    target_point <- any(pedestrian_network.vertices);
                }
            }
            total_spawned <- total_spawned + to_spawn;
        }
        active_agents <- length(pedestrian);
    }
}

// -------------------------------------------------------------------
// ESPECIES DE LA RED Y AGENTES
// -------------------------------------------------------------------

species pedestrian_edge {
    bool is_disabled <- false;
    float congestion_level <- 0.0;

    aspect default {
        rgb edge_color <- #green;
        if (is_disabled) {
            edge_color <- #blue; // Azul = Tramo anegado/bloqueado
        } else if (congestion_level > 0.7) {
            edge_color <- #red; // Rojo = Embotellamiento crítico
        } else if (congestion_level > 0.3) {
            edge_color <- #orange; // Naranja = Tránsito denso
        }
        
        draw shape color: edge_color width: (1.0 + (congestion_level * 3.0)) #m;
    }
}

species arena { aspect default { draw shape color: rgb(75, 0, 130, 150) border: #white; } }
species parking_lot { aspect default { draw shape color: rgb(0, 120, 255, 150) border: #white; } }

species pedestrian skills:[moving]{
    float speed;
    point target_point;

    reflex move_along_graph {
        // Enrutamiento Dijkstra/A* ultra rápido sobre la red
        do goto target: target_point on: pedestrian_network speed: speed;
        
        // Criterio de llegada al destino
        if (location distance_to target_point < 5.0 #m) {
            total_evacuated <- total_evacuated + 1;
            do die;
        }
    }

    aspect default {
        draw circle(1.2 #m) color: #white border: #black;
    }
}

// -------------------------------------------------------------------
// INTERFAZ DE PRESENTACIÓN DIRECTIVA
// -------------------------------------------------------------------

experiment Presentation_Simulation type: gui {
    parameter "Escenario Activo:" var: scenario_mode category: "Control Directivo";

    output {
        layout #split;

        display "Dashboard de Métricas" {
            chart "Avance de la Evacuación (Personas Reales x10)" type: series {
                data "En Tránsito por la Red" value: active_agents * scaling_factor color: #orange;
                data "Evacuados Completos" value: total_evacuated * scaling_factor color: #green;
            }
            chart "Tramos de Calle con Embotellamiento Crítico" type: series {
                data "Calles en Rojo (Nivel de Servicio F)" value: critical_congested_edges color: #red;
            }
        }

        display "Vista de la Red Peatonal (GIS)" type: opengl background: #black {
            species arena aspect: default;
            species parking_lot aspect: default;
            species pedestrian_edge aspect: default;
            species pedestrian aspect: default;
        }
    }
}