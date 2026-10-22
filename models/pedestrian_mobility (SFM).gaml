/**
* Name: SocialForceModel_Evacuation
* Description: Simulación de desalojo masivo mediante el Modelo de Fuerzas Sociales (SFM) en espacio continuo.
* Author: Equipo de Investigación
*/

model SocialForceModel_Evacuation

global {
    float step <- 0.2 #s; // Paso de integración continuo (5 FPS para alta precisión física)
    
    // Archivos GIS del escenario
    bool use_gis_data <- true;
    file buildings_shp <- file("../includes/shp/events/obstacles.shp");
    file arena_shp <- file("../includes/shp/events/estadio.shp");
    file parking_shp <- file("../includes/shp/events/parking.shp");

    geometry shape <- use_gis_data ? envelope(buildings_shp) : square(500 #m);
    
    int max_event_capacity <- 3000;      
    int spawn_rate_per_sec <- 25;        
    int total_spawned <- 0;              
    int total_evacuated <- 0;            
    int current_active_pedestrians <- 0;

    init {
        if (use_gis_data) {
            create obstacle from: buildings_shp;
            create arena from: arena_shp;
            create parking_lot from: parking_shp;
        } else {
            create obstacle number: 1 { shape <- polygon([{50, 50}, {140, 50}, {140, 180}, {50, 180}]); }
            create arena number: 1 { shape <- polygon([{200, 40}, {300, 40}, {300, 110}, {200, 110}]); }
            create parking_lot number: 1 { location <- {80, 470}; name <- "Estacionamiento_Oeste"; }
        }

        // Reparto equitativo de capacidad
        int num_parking <- length(parking_lot);
        if (num_parking > 0) {
            int default_cap <- ceil(max_event_capacity / num_parking);
            ask parking_lot {
                capacity <- default_cap;
            }
        }
    }

    reflex spawn_pedestrians {
        if (total_spawned < max_event_capacity) {
            // Ajustar tasa al tamaño del paso de integración
            int amount_to_spawn <- min([int(spawn_rate_per_sec * step), max_event_capacity - total_spawned]);
            arena source_event <- first(arena);
            
            if (source_event != nil and amount_to_spawn > 0) {
                list<parking_lot> available_lots <- parking_lot where (!each.is_full);
                
                if (!empty(available_lots)) {
                    create pedestrian number: amount_to_spawn {
                        location <- any_location_in(source_event);
                        // Reparto alternado de destinos
                        target_parking <- available_lots[(total_spawned + index) mod length(available_lots)];
                    }
                    total_spawned <- total_spawned + amount_to_spawn;
                }
            }
        }
        current_active_pedestrians <- length(pedestrian);
    }
}

// -------------------------------------------------------------------
// ESPECIES Y FÍSICA DE FUERZAS SOCIALES
// -------------------------------------------------------------------

species obstacle {
    aspect default { draw shape color: rgb(85, 85, 85) border: rgb(40, 40, 40); }
}

species arena {
    aspect default { 
        draw shape color: rgb(75, 0, 130) border: #black; 
        draw "Foro Masivo (Salida)" at: location color: #white font: font("SansSerif", 11, #bold);
    }
}

species parking_lot {
    string name <- "Estacionamiento";
    int capacity <- 1500;
    int current_count <- 0;
    bool is_full <- false;

    aspect default {
        rgb lot_color <- is_full ? rgb(220, 50, 50) : rgb(0, 120, 255);
        draw shape color: lot_color border: #white;
        draw name + "\n(" + current_count + " / " + capacity + ")" at: location color: #white font: font("SansSerif", 10, #bold);
    }
}

species pedestrian {
    // Parámetros dinámicos del peatón
    float preferred_speed <- rnd(1.2, 1.5);
    point velocity <- {0.0, 0.0};
    float tau <- 0.5; // Tiempo de relajación/reacción
    
    // Parámetros del Modelo de Fuerzas Sociales (Helbing)
    float A_ped <- 3.5;    // Magnitud de repulsión entre peatones
    float B_ped <- 0.6;    // Radio de influencia de repulsión peatonal
    float A_wall <- 6.0;   // Magnitud de repulsión respecto a bardas/edificios
    float B_wall <- 0.8;   // Radio de influencia de muros
    
    parking_lot target_parking <- nil;
    rgb p_color <- rgb(0, 200, 100);

    reflex update_social_forces {
        // Redireccionar si el estacionamiento objetivo se llena
        if (target_parking = nil or target_parking.is_full) {
            list<parking_lot> open_lots <- parking_lot where (!each.is_full);
            if (!empty(open_lots)) {
                target_parking <- open_lots with_min_of (each.location distance_to self.location);
            } else {
                target_parking <- first(parking_lot);
            }
        }

        if (target_parking != nil) {
            point target_pos <- target_parking.location;

            // 1. FUERZA DE ATRACCIÓN A LA META (Deseo de avanzar)
            point dir_to_target <- target_pos - location;
            float dist_to_target <- norm(dir_to_target);
            point desired_dir <- dist_to_target > 0 ? dir_to_target / dist_to_target : {0,0};
            point f_desired <- ((desired_dir * preferred_speed) - velocity) / tau;

            // 2. FUERZA DE REPULSIÓN PEATÓN - PEATÓN
            point f_ped <- {0.0, 0.0};
            list<pedestrian> nearby_peds <- pedestrian at_distance 3.0 #m;
            
            loop p over: nearby_peds {
                if (p != self) {
                    float d_ij <- location distance_to p.location;
                    if (d_ij > 0) {
                        point n_ij <- (location - p.location) / d_ij;
                        float mag <- A_ped * exp(-d_ij / B_ped);
                        f_ped <- f_ped + (n_ij * mag);
                    }
                }
            }

            // Cambiar color según densidad local
            if (length(nearby_peds) > 8) {
                p_color <- rgb(255, 50, 50);
            } else if (length(nearby_peds) > 4) {
                p_color <- rgb(255, 165, 0);
            } else {
                p_color <- rgb(0, 200, 100);
            }

            // 3. FUERZA DE REPULSIÓN DE MUROS Y BARDAS
            point f_wall <- {0.0, 0.0};
            list<obstacle> nearby_obs <- obstacle at_distance 2.5 #m;
            
            loop obs over: nearby_obs {
                point closest_p <- closest_points_with(self, obs)[1];
                float d_iw <- location distance_to closest_p;
                if (d_iw > 0) {
                    point n_iw <- (location - closest_p) / d_iw;
                    float mag_w <- A_wall * exp(-d_iw / B_wall);
                    f_wall <- f_wall + (n_iw * mag_w);
                }
            }

            // SUMA INTEGRAL DE FUERZAS
            point total_force <- f_desired + f_ped + f_wall;
            
            // Integración de Euler para velocidad y posición
            velocity <- velocity + (total_force * step);
            
            // Control de velocidad máxima
            if (norm(velocity) > (preferred_speed * 1.3)) {
                velocity <- (velocity / norm(velocity)) * (preferred_speed * 1.3);
            }

            // Avance en espacio continuo
            location <- location + (velocity * step);

            // Corrección de colisión dura con muro si la fuerza no fuera suficiente
            list<obstacle> colliding_obs <- obstacle overlapping self;
            if (!empty(colliding_obs)) {
                obstacle current_obs <- first(colliding_obs);
                point escape_p <- closest_points_with(self, current_obs)[1];
                location <- location + (norm(location - escape_p) * 0.3);
            }
        }

        // 4. LLEGADA AL ESTACIONAMIENTO
        if (target_parking != nil and (self overlaps target_parking or (location distance_to target_parking.location) < 10.0 #m)) {
            if (!target_parking.is_full) {
                target_parking.current_count <- target_parking.current_count + 1;
                if (target_parking.current_count >= target_parking.capacity) {
                    target_parking.is_full <- true;
                }
                total_evacuated <- total_evacuated + 1;
                do die;
            }
        }
    }

    aspect default {
        draw circle(1.2 #m) color: p_color;
    }
}

// -------------------------------------------------------------------
// EXPERIMENTO Y VISUALIZACIÓN
// -------------------------------------------------------------------

experiment Evacuation_Simulation type: gui {
    parameter "Aforo Total del Evento:" var: max_event_capacity category: "Configuración Masiva";
    parameter "Tasa de Salida (Personas/seg):" var: spawn_rate_per_sec category: "Configuración Masiva";

    output {
        layout #split;

        /*display Dashboard {
            chart "Dinámica de Desalojo (Personas)" type: series position: {0, 0} size: {1, 0.5} {
                data "En Tránsito por Campus" value: current_active_pedestrians color: #orange;
                data "Llegaron a Estacionamiento" value: total_evacuated color: #blue;
            }
            chart "Avance Total de Salida del Foro" type: series position: {0, 0.5} size: {1, 0.5} {
                data "Salieron del Foro" value: total_spawned color: #purple;
            }
        }*/

        display main_map type: opengl background: #black axes:false{
            species obstacle aspect: default;
            species arena aspect: default;
            species parking_lot aspect: default;
            species pedestrian aspect: default;
        }
    }
}