/**
* Name: mobility_analysis
* Author: Gamaliel Palomo
* Description: Modelo independiente para el análisis e integración de movilidad urbana multimodal con mapa de calor funcional.
*/

model mobility_analysis

global {
	// --- Parámetros de Simulación ---
	int nb_vehicles <- 500;
	float step <- 3.0#s;
	
	// --- Rutas y Grafo Vial ---
	graph roads_network;
	string raw_path <- "../includes/shp/scenario1/roads.shp";
	string clean_path <- "../includes/shp/scenario1/roads_clean.shp";
	shape_file roads_file <- shape_file(file_exists(clean_path) ? clean_path : raw_path);
	geometry shape <- envelope(roads_file);
	
	// --- Campo de Emisiones y Paleta (Tomado del ejemplo funcional) ---
	field emissions_field <- field(100, 100);
	list<rgb> pal <- palette([#black, #green, #yellow, #orange, #red, #red]); 
	float total_emissions_generated <- 0.0;
	int total_stopped_vehicles -> { length(vehicle where (each.current_speed <= 0.1#km/#h)) };
	
	init {
		// 1. Cargar o Procesar la Red Vial
		if (file_exists(clean_path)) {
			write "Cargando red limpia desde cache: " + clean_path;
			create roads from: shape_file(clean_path) with: [
				direccion :: string(read("direccion")),
				lanes :: int(read("lanes"))
			];
		} else {
			write "Procesando Shapefile original...";
			create roads from: shape_file(raw_path) with: [
				direccion :: string(read("direccion")),
				highway :: string(read("highway")),
				other_tags :: string(read("other_tags"))
			];
			
			ask roads { do calculate_lanes; }
			
			// Invertir sentidos opuestos y duplicar doble sentido
			ask roads where (each.direccion = "3" or each.direccion = "2" or each.direccion = "-1") {
				shape <- reverse(self.shape);
			}
			ask roads where (each.direccion = "1" or empty(each.direccion) or each.direccion = nil) {
				create roads {
					shape <- reverse(myself.shape);
					direccion <- myself.direccion;
					lanes <- myself.lanes;
					highway <- myself.highway;
				}
			}
			
			// Unificación topológica
			list<geometry> clean_geoms <- clean_network(roads collect each.shape, 12.0, true, true);
			list<roads> orig_roads <- copy(roads);
			create roads from: clean_geoms {
				roads orig <- orig_roads closest_to self;
				if (orig != nil) {
					self.direccion <- orig.direccion;
					self.lanes <- orig.lanes;
				}
			}
			ask orig_roads { do die; }
			save roads to: clean_path format: "shp" attributes: ["direccion"::direccion, "lanes"::lanes] crs: "EPSG:4326";
		}
		
		// 2. Construcción del Grafo Dirigido Navegable
		graph full_graph <- directed(as_edge_graph(roads));
		list valid_nodes <- full_graph.vertices select (in_degree_of(full_graph, each) > 0 and out_degree_of(full_graph, each) > 0);
		list<roads> navigable_roads <- roads where (valid_nodes contains source_of(full_graph, each) and valid_nodes contains target_of(full_graph, each));
		roads_network <- directed(as_edge_graph(navigable_roads));
		
		// 3. Creación de Intersecciones y Semáforos
		create intersection from: full_graph.vertices {
			if (length(roads where (each.shape.points contains self.location)) >= 3 and flip(0.25)) {
				is_traffic_light <- false;
			}
		}
		
		// 4. Generación Inicial de Flujo Vehicular
		create vehicle number: nb_vehicles {
			type <- one_of(["car", "car", "car", "moto", "bus", "bike"]);
			current_lane <- 1;
		}
	}
	
	// Reflex de contaminación idéntico al modelo funcional 'traffic.gaml'
	reflex pollution_evolution {
		// Decaimiento del 20% por ciclo
		emissions_field <- emissions_field * 0.9;
		
		// Difusión intensiva (0.9) a celdas adyacentes
		diffuse var: pollution on: emissions_field proportion: 0.9;
	}
	
}

/* =========================================================================
   ESPECIE: ROADS
========================================================================= */
species roads {
	string direccion <- "";
	string highway <- "";
	string other_tags <- "";
	int lanes <- 1;
	
	action calculate_lanes {
		if (lanes > 1) { return; }
		if (other_tags != nil and other_tags contains "lanes") {
			list<string> parts <- other_tags split_with "\"lanes\"=>\"";
			if (length(parts) > 1) {
				string lane_str <- (parts[1] split_with "\"") at 0;
				if (lane_str != nil and lane_str != "") {
					lanes <- int(lane_str);
					if (lanes > 0) { return; }
				}
			}
		}
		if (highway != nil and highway != "") {
			switch highway {
				match "motorway"      { lanes <- 3; }
				match "trunk"         { lanes <- 3; }
				match "primary"       { lanes <- 2; }
				match "secondary"     { lanes <- 2; }
				default               { lanes <- 1; }
			}
		} else {
			lanes <- 1;
		}
	}

	aspect default {
		draw shape color: #gray width: lanes * 1.8 end_arrow: 1.5;
	}
}

/* =========================================================================
   ESPECIE: INTERSECTION
========================================================================= */
species intersection {
	bool is_traffic_light <- false;
	bool is_green <- true;
	int cycle_timer <- 0;
	int green_duration <- 25;

	reflex update_traffic_light when: is_traffic_light {
		cycle_timer <- cycle_timer + 1;
		if (cycle_timer >= green_duration) {
			is_green <- !is_green;
			cycle_timer <- 0;
		}
	}

	aspect default {
		if (is_traffic_light) {
			draw circle(5.0) color: is_green ? #green : #red border: #white;
		}
	}
}

/* =========================================================================
   ESPECIE: VEHICLE
========================================================================= */
species vehicle skills: [moving] {
	point tgt;
	float current_speed;
	float accel_rate;
	float max_speed;
	string type;
	float min_gap;
	int wasted_time;
	bool is_stopped;
	float emission_rate;
	int current_lane <- 1;
	
	point last_location <- nil;
	int stuck_counter <- 0;
	int failed_target_attempts <- 0;
	bool is_crossing <- false;

	init {
		min_gap <- 8.0;
		if (type = "car") {
			accel_rate <- 0.15;
			max_speed <- 50.0#km/#h;
			emission_rate <- 10.0;
		} else if (type = "moto") {
			accel_rate <- 0.3;
			max_speed <- 40.0#km/#h;
			emission_rate <- 5.0;
		} else if (type = "bus") {
			accel_rate <- 0.08;
			max_speed <- 30.0#km/#h;
			emission_rate <- 15.0;
		} else if (type = "bike") {
			accel_rate <- 0.05;
			max_speed <- 20.0#km/#h;
			emission_rate <- 0.0;
		} else {
			accel_rate <- 0.08;
			max_speed <- 25.0#km/#h;
			emission_rate <- 0.0;
		}
		
		list<roads> valid_roads <- roads_network.edges collect roads(each);
		if (!empty(valid_roads)) {
			location <- any_location_in(one_of(valid_roads));
		}
		do select_new_target;
	}

	action select_new_target {
		tgt <- nil;
		int attempts <- 0;
		list<roads> valid_roads <- roads_network.edges collect roads(each);
		if (empty(valid_roads)) { return; }
		
		loop while: (tgt = nil and attempts < 15) {
			point candidate <- any_location_in(one_of(valid_roads));
			path test_path <- path_between(roads_network, location, candidate);
			if (test_path != nil and length(test_path.edges) > 0) {
				tgt <- candidate;
				failed_target_attempts <- 0;
			}
			attempts <- attempts + 1;
		}
		
		if (tgt = nil) {
			failed_target_attempts <- failed_target_attempts + 1;
			if (failed_target_attempts >= 2) {
				do handle_trapped_agent;
			}
		}
	}

	action handle_trapped_agent {
		list<roads> valid_roads <- roads_network.edges collect roads(each);
		if (!empty(valid_roads)) {
			location <- any_location_in(one_of(valid_roads));
			failed_target_attempts <- 0;
			stuck_counter <- 0;
			do select_new_target;
		}
	}

	reflex moving {
		if (tgt = nil or location distance_to tgt < 5.0) {
			do select_new_target;
			stuck_counter <- 0;
			is_crossing <- false;
		}

		roads current_rd <- current_edge != nil ? roads(current_edge) : nil;
		int num_lanes <- current_rd != nil ? current_rd.lanes : 1;
		
		if (current_rd != nil and current_lane > num_lanes) {
			current_lane <- rnd(1, num_lanes);
		}

		float angle_threshold <- (num_lanes > 1) ? 20.0 : 40.0;
		
		list<vehicle> vehicles_ahead <- vehicle at_distance 20.0 select (
			each != self and 
			abs(self.heading - (self.location direction_to each.location)) < angle_threshold and
			(abs(self.heading - each.heading) < 50.0 or abs(self.heading - each.heading) > 310.0)
		);
		vehicle vehicle_ahead <- vehicles_ahead closest_to self;
		
		list<intersection> traffic_lights_ahead <- intersection at_distance 20.0 select (
			each.is_traffic_light and
			abs(self.heading - (self.location direction_to each.location)) < 35.0 and
			not each.is_green
		);
		intersection traffic_light_ahead <- traffic_lights_ahead closest_to self;
		
		intersection next_inter <- intersection at_distance 20.0 select (
			not each.is_traffic_light and 
			abs(self.heading - (self.location direction_to each.location)) < 60.0
		) closest_to self;

		float max_speed_allowed <- max_speed;
		if (num_lanes >= 3) {
			max_speed_allowed <- max_speed * 1.15;
		} else if (num_lanes = 1) {
			max_speed_allowed <- min(max_speed, 35.0#km/#h);
		}
		
		if (vehicle_ahead != nil) {
			float dist_v <- self distance_to vehicle_ahead;
			float max_advance_v <- max(0.0, dist_v - min_gap);
			float speed_limit_v <- max_advance_v * 3.6 #km/#h;
			max_speed_allowed <- min(max_speed_allowed, speed_limit_v);
		}
		
		if (traffic_light_ahead != nil) {
			float dist_tl <- self distance_to traffic_light_ahead;
			float max_advance_tl <- max(0.0, dist_tl - 3.0);
			float speed_limit_tl <- max_advance_tl * 3.6 #km/#h;
			max_speed_allowed <- min(max_speed_allowed, speed_limit_tl);
		}
		
		if (next_inter != nil) {
			float my_dist <- self distance_to next_inter;
			if (my_dist <= 4.0) { is_crossing <- true; }

			if (not is_crossing and my_dist <= 15.0 and my_dist > 4.0) {
				list<vehicle> rivals <- vehicle at_distance 15.0 select (
					each != self and (each distance_to next_inter) < 10.0
				);

				bool should_yield <- false;
				loop r over: rivals {
					if (r.stuck_counter > 20) { continue; }
					float r_dist <- r distance_to next_inter;
					if (r.is_crossing or r_dist < (my_dist - 0.5) or (abs(r_dist - my_dist) <= 0.5 and int(r) < int(self))) {
						should_yield <- true;
						break;
					}
				}

				bool exit_blocked <- (vehicle_ahead != nil and (vehicle_ahead distance_to next_inter) < 7.0 and vehicle_ahead.current_speed < 1.0 #km/#h);

				if (should_yield or exit_blocked) {
					float max_advance_i <- max(0.0, my_dist - 3.5);
					float speed_limit_i <- max_advance_i * 3.6 #km/#h;
					max_speed_allowed <- min(max_speed_allowed, speed_limit_i);
				}
			}
		} else {
			is_crossing <- false;
		}
		
		if (stuck_counter > 30) {
			max_speed_allowed <- max(8.0 #km/#h, max_speed_allowed);
			is_crossing <- true;
		}
		
		if (max_speed_allowed <= 0.1 #km/#h) {
			current_speed <- 0.0 #km/#h;
		} else if (current_speed > max_speed_allowed) {
			current_speed <- max_speed_allowed;
		} else {
			current_speed <- min(max_speed_allowed, current_speed + accel_rate);
		}
		
		// Registro exacto de la emisión al avanzar (método funcional)
		if (current_speed > 0.0 and tgt != nil) {
			path path_followed <- goto(target: tgt, on: roads_network, return_path: true, speed: current_speed);
			/*if (path_followed = nil or length(path_followed.edges) = 0) {
				do select_new_target;
			} else if (path_followed.shape != nil and emission_rate > 0) {
				emissions_field[path_followed.shape.location] <- emissions_field[path_followed.shape.location] + emission_rate;
				total_emissions_generated <- total_emissions_generated + emission_rate;
			}*/
			if (path_followed != nil and path_followed.shape != nil) {
				emissions_field[path_followed.shape.location] <- emissions_field[path_followed.shape.location] + 10;					
			}
		}
		
		if (last_location != nil and location distance_to last_location < 0.2) {
			stuck_counter <- stuck_counter + 1;
		} else {
			stuck_counter <- 0;
		}
		last_location <- copy(location);
		
		if (stuck_counter > 50) {
			stuck_counter <- 0;
			is_crossing <- false;
			do select_new_target;
		}
	}
	
	reflex update_wasted_time {
		if (current_speed <= 0 and not is_stopped) {
			wasted_time <- 0;
			is_stopped <- true;
		} else if (current_speed <= 0 and is_stopped) {
			wasted_time <- wasted_time + int(step);
		} else {
			wasted_time <- 0;
			is_stopped <- false;
		}
	}

	aspect default {
		rgb v_color <- #gray;
		if (type = "car") { v_color <- (current_speed <= 2.0#km/#h) ? #red : #cyan; }
		else if (type = "bus") { v_color <- #magenta; }
		else if (type = "moto") { v_color <- #yellow; }
		else if (type = "bike") { v_color <- #green; }
		
		float offset_dist <- (current_lane - 1) * 2.0;
		point shifted_loc <- location + {offset_dist * cos(heading + 90), offset_dist * sin(heading + 90)};
		
		draw triangle(8) at: shifted_loc color: v_color border: #white rotate: heading + 90;
	}
}

/* =========================================================================
   EXPERIMENTO DE ANÁLISIS DE MOVILIDAD
========================================================================= */
experiment mobility_simulation type: gui autorun:true {
	parameter "Número de vehículos" var: nb_vehicles min: 500 max: 5000;
	
	output {
		layout #split;
		display main_display background: #black type: opengl axes:false {
			species roads aspect: default;
			species intersection aspect: default;
			species vehicle aspect: default;
			mesh emissions_field scale: 8.0 triangulation: true transparency: 0.4 smooth: 3 above: 0.1 color: pal;		
		}
		
		display dashboard {
			chart "Velocidad Promedio por Modo (km/h)" type: series {
				data "Autos" value: mean((vehicle where (each.type = "car")) collect (each.current_speed / #km/#h)) color: #blue;
				data "Autobuses" value: mean((vehicle where (each.type = "bus")) collect (each.current_speed / #km/#h)) color: #purple;
				data "Motos" value: mean((vehicle where (each.type = "moto")) collect (each.current_speed / #km/#h)) color: #orange;
			}
		}
	}
}