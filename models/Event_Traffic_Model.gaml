/**
* Name: Event_Traffic_Model.gaml
* Description: Modelo con Métricas Ponderadas por Fase (Evita inflación al vaciar la red)
*/

model EventTrafficModel

import "constants.gaml"

global skills: [network] {
	
	int active_scenario <- 1;
	string phase_mode <- "arribo";
	
	int stadium_capacity <- 40000;
	int current_stadium_people <- 0;
	int total_spawned_people <- 0;
	
	int start_hour <- 19;
	int start_minute <- 0;
	int start_second <- 0;
	int start_cycle <- 0;
	string simulated_time_str <- "19:00:00";
	
	int arrived_car <- 0;
	int arrived_macro <- 0;
	int arrived_l3 <- 0;
	int arrived_bike <- 0;
	int arrived_walk <- 0;
	
	float avg_speed <- 40.0 update: empty(vehicle where(!each.parked and each.type = "car")) ? 40.0 : mean(vehicle where(!each.parked and each.type = "car") collect (each.current_speed)) * 3.6;
	float delay_factor <- 1.0;
	
	// ACUMULADORES PONDERADOS PARA EVITAR DISTORSIÓN AL FINALIZAR
	float sum_speed_phase <- 0.0;
	float sum_delay_phase <- 0.0;
	int active_eval_cycles <- 0;
	int peak_parking_occupied <- 0;
	
	int total_parking_capacity <- 6085;
	int current_parking_occupied <- 0;
	
	point pt_estadio;
	point pt_telmex;
	point pt_cucea;
	point pt_brt_ccu;
	point pt_l3_mmar;
	point pt_peri_poniente;
	point pt_secundaria_1;
	point pt_secundaria_2;

	file s1_roads_shp <- file(main_shp_path + "scenario1/roads_clean.shp");
	
	graph roads_network;
	graph pedestrian_network;
	
	geometry shape <- envelope(s1_roads_shp);
	file commands_file <- nil;

	init {
		step <- 5#seconds;
		
		create roads from: s1_roads_shp with: [lanes :: int(read("lanes"))];
		graph full_graph <- directed(as_edge_graph(roads));
		list<list> comp_list <- connected_components_of(full_graph);
		list main_nodes <- comp_list with_max_of (length(each));
		
		list<roads> active_roads <- roads where (
			main_nodes contains source_of(full_graph, each) and 
			main_nodes contains target_of(full_graph, each)
		);
		
		roads_network <- directed(as_edge_graph(active_roads));
		pedestrian_network <- undirected(as_edge_graph(active_roads));
		
		create intersection from: vertices(roads_network);
		
		pt_estadio <- to_GAMA_CRS({-103.375535, 20.733753}, "EPSG:4326").location;
		pt_telmex <- to_GAMA_CRS({-103.381626, 20.733777}, "EPSG:4326").location;
		pt_cucea <- to_GAMA_CRS({-103.380200, 20.742500}, "EPSG:4326").location;
		pt_brt_ccu <- to_GAMA_CRS({-103.381113, 20.738939}, "EPSG:4326").location;
		pt_l3_mmar <- to_GAMA_CRS({-103.389188, 20.728752}, "EPSG:4326").location;
		pt_peri_poniente <- to_GAMA_CRS({-103.391000, 20.740800}, "EPSG:4326").location;
		pt_secundaria_1 <- to_GAMA_CRS({-103.385000, 20.738000}, "EPSG:4326").location;
		pt_secundaria_2 <- to_GAMA_CRS({-103.372000, 20.730000}, "EPSG:4326").location;

		create event_location {
			location <- (active_roads closest_to pt_estadio).location;
			capacity <- stadium_capacity;
		}
		
		create transit_station with: [name::"Mi Macro CCU", station_type::"BRT", location::(active_roads closest_to pt_brt_ccu).location];
		create transit_station with: [name::"L3 Mercado del Mar", station_type::"L3", location::(active_roads closest_to pt_l3_mmar).location];
		
		create entry_point with: [location::(active_roads closest_to pt_peri_poniente).location, rate::30.0];
		create entry_point with: [location::(active_roads closest_to pt_cucea).location, rate::25.0];
		create entry_point with: [location::(active_roads closest_to pt_telmex).location, rate::20.0];
		create entry_point with: [location::(active_roads closest_to pt_l3_mmar).location, rate::15.0];
		create entry_point with: [location::(active_roads closest_to pt_secundaria_1).location, rate::5.0];
		create entry_point with: [location::(active_roads closest_to pt_secundaria_2).location, rate::5.0];

		// ESTACIONAMIENTOS
		do create_parking("Audit. Telmex 1,800", "CCU", 1800, {-103.3805, 20.7322}, false, active_roads);
		do create_parking("CCU Poniente 850", "CCU", 850, {-103.3850, 20.7352}, false, active_roads);
		do create_parking("CCU Subterráneo 854", "CCU", 854, {-103.3838, 20.7350}, false, active_roads);
		do create_parking("Museo de Ciencias 400", "CCU", 400, {-103.3830, 20.7330}, false, active_roads);
		do create_parking("CAE Santander 245", "CCU", 245, {-103.3828, 20.7342}, false, active_roads);

		do create_parking("Estadio Norte 700", "Estadio", 700, {-103.3762, 20.7345}, false, active_roads);
		do create_parking("Estadio Sur 490", "Estadio", 490, {-103.3760, 20.7318}, false, active_roads);
		do create_parking("Belenes Andador 315", "Estadio", 315, {-103.3782, 20.7340}, false, active_roads);
		do create_parking("Estadio Oriente 156", "Estadio", 156, {-103.3748, 20.7330}, false, active_roads);
		do create_parking("Estadio Subterráneo 96", "Estadio", 96, {-103.3768, 20.7332}, false, active_roads);

		do create_parking("Park & Ride CUCEA 680", "Park & Ride", 680, {-103.3810, 20.7415}, true, active_roads);
		do create_parking("Park & Ride CUCSH 528", "Park & Ride", 528, {-103.3770, 20.7418}, true, active_roads);
		do create_parking("Park & Ride CUCEA Sur 294", "Park & Ride", 294, {-103.3835, 20.7412}, true, active_roads);
		do create_parking("Park & Ride CUCEA Norte 300", "Park & Ride", 300, {-103.3813, 20.7438}, true, active_roads);

		do reset_simulation;
	}

	action create_parking(string p_name, string p_group, int p_cap, point p_lonlat, bool p_academic, list<roads> r_list) {
		point proj_loc <- to_GAMA_CRS(p_lonlat, "EPSG:4326").location;
		create parking_lot {
			name <- p_name;
			group_name <- p_group;
			capacity <- p_cap;
			occupied <- 0;
			is_academic <- p_academic;
			location <- (r_list closest_to proj_loc).location;
		}
	}

	action reset_simulation {
		ask vehicle { do die; }
		ask spectator { do die; }
		
		start_cycle <- cycle;
		arrived_car <- 0;
		arrived_macro <- 0;
		arrived_l3 <- 0;
		arrived_bike <- 0;
		arrived_walk <- 0;
		delay_factor <- 1.0;
		total_spawned_people <- 0;
		
		sum_speed_phase <- 0.0;
		sum_delay_phase <- 0.0;
		active_eval_cycles <- 0;
		peak_parking_occupied <- 0;
		
		list<parking_lot> valid_lots <- parking_lot where (active_scenario = 2 or !each.is_academic);
		total_parking_capacity <- sum(valid_lots collect each.capacity);

		if (phase_mode = "arribo") {
			start_hour <- 19;
			simulated_time_str <- "19:00:00";
			current_stadium_people <- 0;
			ask parking_lot { occupied <- 0; }
		} else {
			start_hour <- 23;
			simulated_time_str <- "23:00:00";
			current_stadium_people <- stadium_capacity;
			total_spawned_people <- stadium_capacity;
			ask valid_lots { occupied <- int(self.capacity * 0.90); }
			peak_parking_occupied <- sum(valid_lots collect each.occupied);
		}
	}

	reflex update_simulated_clock {
		int elapsed_cycles <- cycle - start_cycle;
		int total_sec <- (start_hour * 3600) + (start_minute * 60) + start_second + int(elapsed_cycles * step);
		int h <- (total_sec / 3600) mod 24;
		int m <- (total_sec / 60) mod 60;
		int s <- total_sec mod 60;
		
		string sh <- (h < 10) ? ("0" + h) : ("" + h);
		string sm <- (m < 10) ? ("0" + m) : ("" + m);
		string ss <- (s < 10) ? ("0" + s) : ("" + s);
		
		simulated_time_str <- sh + ":" + sm + ":" + ss;
	}

	reflex generate_traffic {
		list<parking_lot> valid_lots <- parking_lot where (active_scenario = 2 or !each.is_academic);
		
		if (phase_mode = "arribo") {
			if (total_spawned_people < stadium_capacity) {
				list<parking_lot> available_lots <- valid_lots where (each.occupied < each.capacity);
				int rem_people <- stadium_capacity - total_spawned_people;
				
				if (active_scenario = 1) {
					if (flip(0.70) and !empty(available_lots) and rem_people > 0) {
						int n_cars <- min([rnd(2, 5), int(rem_people / 2)]);
						if (n_cars > 0) {
							create vehicle number: n_cars {
								type <- "car";
								is_exiting <- false;
								location <- (one_of(entry_point)).location;
								target_stadium <- first(event_location);
								my_parking <- one_of(available_lots);
							}
							total_spawned_people <- total_spawned_people + (n_cars * 2);
						}
					}
					if (flip(0.35) and total_spawned_people < stadium_capacity) {
						transit_station st <- one_of(transit_station where (each.station_type = "BRT"));
						int n_p <- min([rnd(20, 40), stadium_capacity - total_spawned_people]);
						if (st != nil and n_p > 0) { 
							create spectator number: n_p { location <- st.location; target_stadium <- first(event_location); mode <- "macro"; is_exiting <- false; } 
							total_spawned_people <- total_spawned_people + n_p;
						}
					}
					if (flip(0.30) and total_spawned_people < stadium_capacity) {
						transit_station st <- one_of(transit_station where (each.station_type = "L3"));
						int n_p <- min([rnd(15, 30), stadium_capacity - total_spawned_people]);
						if (st != nil and n_p > 0) { 
							create spectator number: n_p { location <- st.location; target_stadium <- first(event_location); mode <- "l3"; is_exiting <- false; } 
							total_spawned_people <- total_spawned_people + n_p;
						}
					}
					if (flip(0.35) and total_spawned_people < stadium_capacity) {
						point p_start <- flip(0.65) ? (one_of(roads)).location : (flip(0.5) ? pt_secundaria_1 : pt_cucea);
						int n_p <- min([rnd(8, 18), stadium_capacity - total_spawned_people]);
						if (n_p > 0) {
							create spectator number: n_p { location <- p_start; target_stadium <- first(event_location); mode <- "walk"; is_exiting <- false; } 
							total_spawned_people <- total_spawned_people + n_p;
						}
					}
					if (flip(0.08) and total_spawned_people < stadium_capacity) {
						int n_p <- min([rnd(2, 4), stadium_capacity - total_spawned_people]);
						if (n_p > 0) {
							create vehicle number: n_p { type <- "bike"; is_exiting <- false; location <- (one_of(entry_point)).location; target_stadium <- first(event_location); }
							total_spawned_people <- total_spawned_people + n_p;
						}
					}
				} else {
					if (flip(0.45) and !empty(available_lots) and rem_people > 0) {
						int n_cars <- min([rnd(1, 3), int(rem_people / 2)]);
						if (n_cars > 0) {
							create vehicle number: n_cars {
								type <- "car";
								is_exiting <- false;
								location <- (one_of(entry_point)).location;
								target_stadium <- first(event_location);
								my_parking <- one_of(available_lots);
							}
							total_spawned_people <- total_spawned_people + (n_cars * 2);
						}
					}
					if (flip(0.50) and total_spawned_people < stadium_capacity) {
						transit_station st_brt <- first(transit_station where (each.station_type = "BRT"));
						int n_p <- min([rnd(30, 55), stadium_capacity - total_spawned_people]);
						if (st_brt != nil and n_p > 0) { 
							create spectator number: n_p { location <- st_brt.location; target_stadium <- first(event_location); mode <- "macro"; is_exiting <- false; } 
							total_spawned_people <- total_spawned_people + n_p;
						}
					}
					if (flip(0.45) and total_spawned_people < stadium_capacity) {
						transit_station st_l3 <- first(transit_station where (each.station_type = "L3"));
						int n_p <- min([rnd(25, 45), stadium_capacity - total_spawned_people]);
						if (st_l3 != nil and n_p > 0) { 
							create spectator number: n_p { location <- st_l3.location; target_stadium <- first(event_location); mode <- "l3"; is_exiting <- false; } 
							total_spawned_people <- total_spawned_people + n_p;
						}
					}
					if (flip(0.25) and total_spawned_people < stadium_capacity) {
						int n_p <- min([rnd(4, 8), stadium_capacity - total_spawned_people]);
						if (n_p > 0) {
							create vehicle number: n_p { type <- "bike"; is_exiting <- false; location <- (one_of(entry_point)).location; target_stadium <- first(event_location); }
							total_spawned_people <- total_spawned_people + n_p;
						}
					}
					if (flip(0.40) and total_spawned_people < stadium_capacity) {
						point p_start <- flip(0.70) ? (one_of(roads)).location : (flip(0.5) ? pt_secundaria_1 : pt_cucea);
						int n_p <- min([rnd(12, 24), stadium_capacity - total_spawned_people]);
						if (n_p > 0) {
							create spectator number: n_p { location <- p_start; target_stadium <- first(event_location); mode <- "walk"; is_exiting <- false; } 
							total_spawned_people <- total_spawned_people + n_p;
						}
					}
				}
			}
		} else {
			list<parking_lot> occupied_lots <- valid_lots where (each.occupied > 0);
			
			if (current_stadium_people > 0 or !empty(occupied_lots)) {
				if (!empty(occupied_lots) and flip(0.80)) {
					parking_lot lot <- one_of(occupied_lots);
					int leave_count <- min([lot.occupied, rnd(3, 8)]);
					lot.occupied <- lot.occupied - leave_count;
					
					create vehicle number: leave_count {
						type <- "car";
						is_exiting <- true;
						location <- lot.location;
						target_dest <- (one_of(entry_point)).location;
					}
				}
				
				if (current_stadium_people > 0) {
					int out_people <- min([current_stadium_people, rnd(40, 90)]);
					current_stadium_people <- current_stadium_people - out_people;
					
					if (active_scenario = 1) {
						create spectator number: int(out_people * 0.50) { location <- (first(event_location)).location; target_dest <- (first(transit_station where (each.station_type = "BRT"))).location; mode <- "macro"; is_exiting <- true; }
						create spectator number: int(out_people * 0.35) { location <- (first(event_location)).location; target_dest <- (first(transit_station where (each.station_type = "L3"))).location; mode <- "l3"; is_exiting <- true; }
						create spectator number: int(out_people * 0.15) { location <- (first(event_location)).location; target_dest <- (one_of(roads)).location; mode <- "walk"; is_exiting <- true; }
					} else {
						create spectator number: int(out_people * 0.40) { location <- (first(event_location)).location; target_dest <- (first(transit_station where (each.station_type = "BRT"))).location; mode <- "macro"; is_exiting <- true; }
						create spectator number: int(out_people * 0.35) { location <- (first(event_location)).location; target_dest <- (first(transit_station where (each.station_type = "L3"))).location; mode <- "l3"; is_exiting <- true; }
						create spectator number: int(out_people * 0.15) { location <- (first(event_location)).location; target_dest <- (one_of(roads)).location; mode <- "walk"; is_exiting <- true; }
						create spectator number: int(out_people * 0.10) { location <- (first(event_location)).location; target_dest <- (one_of(entry_point)).location; mode <- "bike"; is_exiting <- true; }
					}
				}
			}
		}
	}

	reflex process_web_commands when: every(2#cycles) {
		if (file_exists("../includes/data/commands.json")) {
			try {
				commands_file <- json_file("../includes/data/commands.json");
				if (commands_file != nil and commands_file.contents != nil) {
					map<string, unknown> cmd_data <- map<string, unknown>(commands_file.contents);
					if (cmd_data contains_key "updated" and bool(cmd_data["updated"]) = true) {
						bool need_reset <- false;
						if (cmd_data contains_key "reset" and bool(cmd_data["reset"]) = true) { need_reset <- true; }
						if (cmd_data contains_key "active_scenario") {
							int new_sc <- int(cmd_data["active_scenario"]);
							if (new_sc != active_scenario) { active_scenario <- new_sc; need_reset <- true; }
						}
						if (cmd_data contains_key "phase_mode") {
							string new_pm <- string(cmd_data["phase_mode"]);
							if (new_pm != phase_mode) { phase_mode <- new_pm; need_reset <- true; }
						}
						
						if (need_reset) { do reset_simulation; }
						
						string json_out <- to_json([
							"active_scenario":: active_scenario, 
							"phase_mode":: phase_mode,
							"stadium_capacity":: stadium_capacity, 
							"updated":: false
						]);
						save json_out to: "../includes/data/commands.json" format: "json";
					}
				}
			} catch {}
		}
	}

	reflex update_and_export_indicators when: every(1#cycle) {
		list<parking_lot> valid_lots <- parking_lot where (active_scenario = 2 or !each.is_academic);
		current_parking_occupied <- sum(valid_lots collect each.occupied);
		
		if (current_parking_occupied > peak_parking_occupied) {
			peak_parking_occupied <- current_parking_occupied;
		}

		delay_factor <- (40.0 / max([5.0, avg_speed]));

		// CONSERVAR EL PROMEDIO MIENTRAS HAYA MOVIMIENTO ACTIVO
		list<vehicle> active_v <- vehicle where(!each.parked);
		list<spectator> active_s <- spectator where(!each.arrived);

		if (!empty(active_v) or !empty(active_s)) {
			sum_speed_phase <- sum_speed_phase + avg_speed;
			sum_delay_phase <- sum_delay_phase + delay_factor;
			active_eval_cycles <- active_eval_cycles + 1;
		}

		// EVALUAR SOBRE LA MEDIA ACUMULADA DE LA FASE Y NO SOBRE EL PICO FINAL VACÍO
		float eval_speed <- (active_eval_cycles > 0) ? (sum_speed_phase / active_eval_cycles) : avg_speed;
		float eval_delay <- (active_eval_cycles > 0) ? (sum_delay_phase / active_eval_cycles) : delay_factor;
		
		// EN DESALOJO, EVALUAR EL MARGEN RESPECTO AL PICO DE OCUPACIÓN ALCANZADO
		int ref_parking_occ <- (phase_mode = "desalojo") ? peak_parking_occupied : current_parking_occupied;
		float parking_pct <- (total_parking_capacity > 0) ? (ref_parking_occ / total_parking_capacity) * 100 : 0.0;

		float spd_idx <- min([100.0, (eval_speed / 40.0) * 100.0]);
		float los_idx <- max([10.0, min([100.0, (1.0 / max([1.0, eval_delay])) * 100.0])]);
		
		int total_modal <- arrived_car + arrived_macro + arrived_l3 + arrived_bike + arrived_walk;
		int tot_m <- max([1, total_modal]);
		float tp_idx <- ((arrived_macro + arrived_l3) / tot_m) * 100.0;
		float act_idx <- min([100.0, ((arrived_bike + arrived_walk) / tot_m) * 200.0]);
		float park_margin <- max([0.0, 100.0 - parking_pct]);
		float eco_score <- (spd_idx * 0.6) + (park_margin * 0.4);

		string current_sc_key <- (active_scenario = 1 ? "A_" : "B_") + (phase_mode = "arribo" ? "Arribo" : "Desalojo");

		list<map<string, unknown>> parking_details <- [];
		ask valid_lots {
			point wgs84 <- CRS_transform(self.location, "EPSG:4326").location;
			add [
				"name":: self.name,
				"group":: self.group_name,
				"capacity":: self.capacity,
				"occupied":: self.occupied,
				"pct":: (self.capacity > 0) ? int((self.occupied / self.capacity) * 100) : 0,
				"lat":: wgs84.y,
				"lng":: wgs84.x
			] to: parking_details;
		}

		list<map<string, unknown>> active_agents <- [];
		list<map<string, unknown>> congestion_points <- [];

		int v_sample <- min([350, length(active_v)]);
		ask sample(active_v, v_sample, false) {
			point wgs84 <- CRS_transform(self.location, "EPSG:4326").location;
			add [ "lat":: wgs84.y, "lng":: wgs84.x, "type":: self.type ] to: active_agents;
			
			float speed_kmh <- self.current_speed * 3.6;
			float max_spd_kmh <- self.max_speed * 3.6;
			float congestion_level <- max([0.0, 1.0 - (speed_kmh / max_spd_kmh)]);
			
			bool is_at_entry <- false;
			ask entry_point {
				if (myself.location distance_to self.location < 35.0) { is_at_entry <- true; }
			}
			
			if (!is_at_entry and congestion_level > 0.25) {
				add [ "lat":: wgs84.y, "lng":: wgs84.x, "congestion":: min([1.0, congestion_level]) ] to: congestion_points;
			}
		}

		int s_sample <- min([350, length(active_s)]);
		ask sample(active_s, s_sample, false) {
			point wgs84 <- CRS_transform(self.location, "EPSG:4326").location;
			add [ "lat":: wgs84.y, "lng":: wgs84.x, "type":: self.mode ] to: active_agents;
		}

		string json_emissions <- to_json([
			"simulated_time":: simulated_time_str,
			"phase_mode":: phase_mode,
			"active_scenario":: active_scenario,
			"vehicles_count":: length(active_v),
			"avg_speed":: avg_speed,
			"delay_factor":: delay_factor,
			"parking_occupancy_pct":: (total_parking_capacity > 0) ? (current_parking_occupied / total_parking_capacity) * 100 : 0.0,
			"total_parking_capacity":: total_parking_capacity,
			"total_parking_occupied":: current_parking_occupied,
			"stadium_arrived":: current_stadium_people,
			"stadium_en_route":: max([0, total_spawned_people - current_stadium_people]),
			"total_spawned":: total_spawned_people,
			"stadium_capacity":: stadium_capacity,
			"active_metrics":: [
				"key":: current_sc_key,
				"data":: [spd_idx, los_idx, tp_idx, act_idx, park_margin, eco_score]
			],
			"modal_split":: [
				"car":: arrived_car,
				"macro":: arrived_macro,
				"l3":: arrived_l3,
				"bike":: arrived_bike,
				"walk":: arrived_walk
			],
			"parking_lots":: parking_details,
			"agents":: active_agents,
			"points":: congestion_points
		]);
		
		save json_emissions to: "../includes/data/emissions_data.json" format: "json";
	}
}

species vehicle skills: [moving] {
	string type <- "car";
	float max_speed <- 40.0#km/#h;
	float current_speed <- 0.0;
	event_location target_stadium;
	parking_lot my_parking;
	point target_dest;
	bool parked <- false;
	bool is_exiting <- false;

	reflex drive when: !parked {
		point dest <- is_exiting ? target_dest : ((type = "car" and my_parking != nil) ? my_parking.location : (target_stadium != nil ? target_stadium.location : location));
		
		if (location distance_to dest < 18.0) {
			if (is_exiting) {
				arrived_car <- arrived_car + 1;
				do die;
			} else if (type = "car" and my_parking != nil) {
				if (my_parking.occupied < my_parking.capacity) {
					my_parking.occupied <- my_parking.occupied + 1;
					parked <- true;
					
					create spectator number: 2 {
						location <- myself.location;
						target_stadium <- myself.target_stadium;
						mode <- "car";
					}
				} else {
					list<parking_lot> valid_lots <- parking_lot where (each.occupied < each.capacity);
					if (!empty(valid_lots)) { my_parking <- one_of(valid_lots); }
				}
			} else if (type = "bike") {
				parked <- true;
				current_stadium_people <- min([stadium_capacity, current_stadium_people + 1]); 
				arrived_bike <- arrived_bike + 1;
				do die;
			} else {
				parked <- true;
			}
		} else {
			do goto target: dest on: roads_network speed: max_speed;
			current_speed <- speed;
		}
	}
}

species spectator skills: [moving] {
	event_location target_stadium;
	point target_dest;
	string mode <- "walk";
	bool arrived <- false;
	bool is_exiting <- false;
	
	reflex walk when: !arrived {
		point dest <- is_exiting ? target_dest : (target_stadium != nil ? target_stadium.location : location);
		
		if (location distance_to dest < 15.0) {
			arrived <- true;
			if (!is_exiting) {
				current_stadium_people <- min([stadium_capacity, current_stadium_people + 1]); 
				if (mode = "car") { arrived_car <- arrived_car + 1; }
				else if (mode = "macro") { arrived_macro <- arrived_macro + 1; }
				else if (mode = "l3") { arrived_l3 <- arrived_l3 + 1; }
				else { arrived_walk <- arrived_walk + 1; }
			} else {
				if (mode = "macro") { arrived_macro <- arrived_macro + 1; }
				else if (mode = "l3") { arrived_l3 <- arrived_l3 + 1; }
				else if (mode = "bike") { arrived_bike <- arrived_bike + 1; }
				else { arrived_walk <- arrived_walk + 1; }
			}
			do die;
		} else {
			do goto target: dest on: pedestrian_network speed: 5.0#km/#h;
		}
	}
}

species transit_station { string name; string station_type; }
species entry_point { float rate <- 50.0; }
species event_location { int capacity <- 40000; }
species parking_lot { string name; string group_name; int capacity <- 1500; int occupied <- 0; bool is_academic <- false; }
species roads { int lanes <- 1; }
species intersection {}

experiment StadiumMobilityHeadless type: gui autorun: true {}