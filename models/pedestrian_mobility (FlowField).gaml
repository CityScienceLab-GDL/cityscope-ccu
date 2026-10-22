/**
* Name: FlowField_Dynamic_Spawning_Perimeter
* Description: Simulación de desalojo masivo con salidas aleatorias en el perímetro del estadio (puertas) y tasa por minuto.
* Author: Equipo de Investigación
*/

model FlowField_Dynamic_Spawning_Perimeter

global {
    float step <- 1.0 #s;
    
    // Archivos GIS del escenario
    bool use_gis_data <- true;
    file buildings_shp <- file("../includes/shp/events/obstacles.shp");
    file arena_shp <- file("../includes/shp/events/estadio.shp");
    file parking_shp <- file("../includes/shp/events/parking.shp");

    geometry shape <- use_gis_data ? envelope(buildings_shp) : square(500 #m);
    
    int max_event_capacity <- 3000;      
    int spawn_rate_per_min <- 1500;  // Tasa de salida configurada en personas por minuto
    float spawn_accumulator <- 0.0;  // Acumulador para control continuo del flujo
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

        // Reparto proporcional de capacidad
        int num_parking <- length(parking_lot);
        if (num_parking > 0) {
            int default_cap <- ceil(max_event_capacity / num_parking);
            ask parking_lot {
                capacity <- default_cap;
            }
        }

        // Geometrías para delimitar paredes y zonas transitables
        geometry all_obstacles <- empty(obstacle as list) ? nil : union(obstacle as list);
        geometry all_targets <- empty(parking_lot as list) ? nil : union(parking_lot as list);
        geometry all_arenas <- empty(arena as list) ? nil : union(arena as list);

        ask flow_cell {
            if (all_obstacles != nil and (self overlaps all_obstacles)) {
                is_wall <- true;
            }
            // Garantizar que zonas de estacionamiento y foro nunca sean bloqueadas por bordes
            if ((all_targets != nil and self overlaps all_targets) or 
                (all_arenas != nil and self overlaps all_arenas)) {
                is_wall <- false;
            }
        }

        // Generar campos de flujo independientes
        do build_all_flow_fields;
    }

    action build_all_flow_fields {
        loop lot over: parking_lot {
            geometry lot_geom <- lot.shape;
            
            ask flow_cell where (!each.is_wall) {
                dist_map[lot] <- 999999.0;
                vector_map[lot] <- {0, 0};
            }

            list<flow_cell> process_list <- [];
            ask flow_cell where (!each.is_wall) {
                if (lot_geom != nil and self overlaps lot_geom) {
                    dist_map[lot] <- 0.0;
                    process_list <- process_list + self;
                }
            }

            // Wavefront
            loop while: !empty(process_list) {
                flow_cell current <- process_list[0];
                remove index: 0 from: process_list;

                loop n over: current.neighbors where (!each.is_wall) {
                    float d <- current.dist_map[lot] + (current.location distance_to n.location);
                    if (d < n.dist_map[lot]) {
                        n.dist_map[lot] <- d;
                        if (!(process_list contains n)) {
                            process_list <- process_list + self_or_n(n);
                        }
                    }
                }
            }

            // Asignación de vectores
            ask flow_cell where (!each.is_wall) {
                list<flow_cell> valid_n <- neighbors where (!each.is_wall);
                if (!empty(valid_n)) {
                    flow_cell best_n <- valid_n with_min_of (each.dist_map[lot]);
                    if (best_n != nil and best_n.dist_map[lot] < self.dist_map[lot]) {
                        vector_map[lot] <- best_n.location - location;
                    }
                }
            }
        }
    }

    flow_cell self_or_n(flow_cell target_n) {
        return target_n;
    }

    reflex spawn_pedestrians {
        if (total_spawned < max_event_capacity) {
            // Acumulación progresiva por segundo/step basada en la tasa por minuto
            spawn_accumulator <- spawn_accumulator + ((spawn_rate_per_min / 60.0) * step);
            int amount_to_spawn <- min([int(spawn_accumulator), max_event_capacity - total_spawned]);
            
            if (amount_to_spawn > 0) {
                spawn_accumulator <- spawn_accumulator - amount_to_spawn;
                arena source_event <- first(arena);
                
                if (source_event != nil) {
                    list<parking_lot> available_lots <- parking_lot where (!each.is_full);
                    
                    if (!empty(available_lots)) {
                        // Extraer el contorno exterior del estadio (simulación de múltiples puertas)
                        geometry arena_perimeter <- source_event.shape.contour;
                        
                        create pedestrian number: amount_to_spawn {
                            // Asignar ubicación aleatoria sobre el perímetro exterior
                            location <- any_location_in(arena_perimeter);
                            // Balanceo alternado entre estacionamientos con cupo
                            target_parking <- available_lots[(total_spawned + index) mod length(available_lots)];
                        }
                        total_spawned <- total_spawned + amount_to_spawn;
                    }
                }
            }
        }
        current_active_pedestrians <- length(pedestrian);
    }
}

// -------------------------------------------------------------------
// REJILLA Y ESPECIES
// -------------------------------------------------------------------

grid flow_cell width: 200 height: 200 neighbors: 8 {
    bool is_wall <- false;
    map<parking_lot, float> dist_map;
    map<parking_lot, point> vector_map;
}

species obstacle {
    aspect default { draw shape color: rgb(85, 85, 85) border: rgb(50, 50, 50); }
}

species arena {
    aspect default { 
        draw shape color: rgb(75, 0, 130) border: #black; 
        draw "Foro Masivo" at: location color: #white font: font("SansSerif", 11, #bold);
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
    float speed <- rnd(1.1, 1.4);
    rgb p_color <- rgb(0, 200, 100);
    parking_lot target_parking <- nil;

    reflex move_as_particle {
        // Verificación de disponibilidad del destino
        if (target_parking = nil or target_parking.is_full) {
            list<parking_lot> open_lots <- parking_lot where (!each.is_full);
            if (!empty(open_lots)) {
                target_parking <- open_lots with_min_of (each.location distance_to self.location);
            } else {
                target_parking <- first(parking_lot);
            }
        }

        flow_cell current_cell <- flow_cell(location);

        if (current_cell != nil and target_parking != nil) {
            // Liberación inmediata si pisa pared
            if (current_cell.is_wall) {
                list<flow_cell> free_n <- current_cell.neighbors where (!each.is_wall);
                if (!empty(free_n)) {
                    location <- (free_n with_min_of (each.dist_map[self.target_parking])).location;
                }
                return;
            }

            // A) Vector guía
            point main_dir <- current_cell.vector_map[target_parking];

            if (main_dir = {0,0} or current_cell.dist_map[target_parking] = 999999.0) {
                list<flow_cell> active_cells <- flow_cell where (!each.is_wall and each.dist_map[self.target_parking] < 999999.0);
                if (!empty(active_cells)) {
                    flow_cell nearest_active <- active_cells with_min_of (each.location distance_to self.location);
                    if (nearest_active != nil) {
                        main_dir <- nearest_active.location - location;
                    }
                }
            }

            // B) Repulsión moderada entre peatones
            point repulsion <- {0, 0};
            list<pedestrian> neighbors <- pedestrian at_distance 1.8 #m;
            
            loop p over: neighbors {
                if (p != self) {
                    point diff <- location - p.location;
                    repulsion <- repulsion + diff;
                }
            }

            // Color por densidad
            if (length(neighbors) > 6) {
                p_color <- rgb(255, 50, 50);
            } else if (length(neighbors) > 3) {
                p_color <- rgb(255, 165, 0);
            } else {
                p_color <- rgb(0, 200, 100);
            }

            // C) Movimiento con deslizamiento adaptativo
            point dir_norm <- norm(main_dir) > 0 ? main_dir / norm(main_dir) : {0,0};
            point rep_norm <- norm(repulsion) > 0 ? repulsion / norm(repulsion) : {0,0};
            
            point final_move <- dir_norm + (rep_norm * 0.35);
            float d <- norm(final_move);
            
            if (d > 0) {
                point step_vec <- (final_move / d) * speed;
                point target_pos <- location + step_vec;
                flow_cell target_c <- flow_cell(target_pos);
                
                // Intento de avance directo
                if (target_c != nil and !target_c.is_wall) {
                    location <- target_pos;
                } else {
                    // Deslizamiento en ejes para superar esquinas estrechas
                    point try_x <- location + {step_vec.x, 0.0};
                    flow_cell cell_x <- flow_cell(try_x);
                    
                    point try_y <- location + {0.0, step_vec.y};
                    flow_cell cell_y <- flow_cell(try_y);

                    if (cell_x != nil and !cell_x.is_wall and cell_y != nil and !cell_y.is_wall) {
                        if (cell_x.dist_map[target_parking] <= cell_y.dist_map[target_parking]) {
                            location <- try_x;
                        } else {
                            location <- try_y;
                        }
                    } else if (cell_x != nil and !cell_x.is_wall) {
                        location <- try_x;
                    } else if (cell_y != nil and !cell_y.is_wall) {
                        location <- try_y;
                    }
                }
            }
        }

        // D) Entrada al estacionamiento objetivo
        if (current_cell != nil and target_parking != nil and current_cell.dist_map[target_parking] = 0.0) {
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
        draw circle(1.5 #m) color: p_color;
    }
}

// -------------------------------------------------------------------
// EXPERIMENTO Y DASHBOARD
// -------------------------------------------------------------------

experiment Evacuation_Simulation type: gui {
    parameter "Aforo Total del Evento:" var: max_event_capacity category: "Configuración Masiva";
    parameter "Tasa de Salida (Personas/minuto):" var: spawn_rate_per_min category: "Configuración Masiva";

    output {
        layout #split;

        display Dashboard {
            chart "Dinámica de Desalojo (Personas)" type: series position: {0, 0} size: {1, 0.5} {
                data "En Tránsito por Campus" value: current_active_pedestrians color: #orange;
                data "Llegaron a Estacionamiento" value: total_evacuated color: #blue;
            }
            chart "Avance Total de Salida del Foro" type: series position: {0, 0.5} size: {1, 0.5} {
                data "Salieron del Foro" value: total_spawned color: #purple;
            }
        }

        display main_map type: opengl background: #black {
            species obstacle aspect: default;
            species arena aspect: default;
            species parking_lot aspect: default;
            species pedestrian aspect: default;
        }
    }
}