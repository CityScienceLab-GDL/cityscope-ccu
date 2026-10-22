/**
* Name: basemodel
* Author: Gamaliel Palomo
*/

model basemodel

global {
	int logLevel <- 1;
	string scenario <- "lomas";
	float dist <- 200.0;
	float h <- 50.0;
	int nb_people <- 500;
	field cell <- field(30, 30);
	list<rgb> pal <- palette([#black, #green, #yellow, #orange, #orange, #red, #red, #red]);
	
	graph roads_network;
	graph raw_network;
	
	string raw_path <- "../includes/shp/ccu/roads.shp";
	string clean_path <- "../includes/shp/ccu/roads_clean.shp";
	shape_file roads_file <- shape_file(file_exists(clean_path) ? clean_path : raw_path);
	geometry shape <- envelope(roads_file);
	
	list<geometry> failed_routes <- [];

	init {
		if (file_exists(clean_path)) {
			do printLog("Cached clean network found: " + clean_path);
			do printLog("Loading road agents directly from clean file...");
			
			// Cargar agentes 'road' manteniendo la dirección y el número de carriles guardados
			create road from: shape_file(clean_path) with: [
				direccion :: string(read("direccion")),
				lanes :: int(read("lanes"))
			];
			do printLog("Road agents loaded: " + length(road));
		} 
		else {
			do printLog("Clean network NOT found. Processing raw file...");
			shape_file raw_file <- shape_file(raw_path);
			
			// 1. Cargar agentes leyendo 'direccion', 'highway' y 'other_tags'
			create road from: raw_file with: [
				direccion :: string(read("direccion")),
				highway :: string(read("highway")),
				other_tags :: string(read("other_tags"))
			];
			
			// 2. Extraer y calcular los carriles para cada tramo
			ask road {
				do calculate_lanes;
			}
			
			// 3. BLOQUE DE INSPECCIÓN: Muestra frecuencias en consola
			list<string> valores_unicos <- remove_duplicates(road collect each.direccion);
			write "==================================================";
			write " INSPECCIÓN DEL CAMPO 'direccion' EN EL SHAPEFILE:";
			write " Valores únicos encontrados: " + string(valores_unicos);
			
			map<string, list<road>> conteo_por_valor <- road group_by (each.direccion);
			loop val over: conteo_por_valor.keys {
				write "  -> Valor '" + val + "': " + length(conteo_por_valor[val]) + " tramos";
			}
			
			map<int, list<road>> conteo_carriles <- road group_by (each.lanes);
			write " INSPECCIÓN DE CARRILES DETECTADOS:";
			loop l_val over: conteo_carriles.keys {
				write "  -> " + l_val + " carril(es): " + length(conteo_carriles[l_val]) + " tramos";
			}
			write "==================================================";
			
			// 4. Invertir geometrías de las calles de un solo sentido opuesto ('3', '2' o '-1')
			ask road where (each.direccion = "3" or each.direccion = "2" or each.direccion = "-1") {
				shape <- reverse(self.shape);
			}
			
			// 5. Duplicar aristas para calles de DOBLE SENTIDO ('1', '' o nil) conservando 'lanes'
			ask road where (each.direccion = "1" or empty(each.direccion) or each.direccion = nil) {
				create road {
					shape <- reverse(myself.shape);
					direccion <- myself.direccion;
					lanes <- myself.lanes;
					highway <- myself.highway;
				}
			}
			
			do printLog("Total de tramos tras orientación/duplicación: " + length(road));
			
			// 6. Unir nodos e intersecciones aumentando la tolerancia
			do printLog("Cleaning network topology and connecting intersections...");
			list<geometry> clean_geoms <- clean_network(road collect each.shape, 12.0, true, true);
			
			// Recrear los agentes road heredando atributos (direccion y lanes) de los tramos originales
			list<road> original_roads <- copy(road);
			create road from: clean_geoms {
				road closest_orig <- original_roads closest_to self;
				if (closest_orig != nil) {
					self.direccion <- closest_orig.direccion;
					self.lanes <- closest_orig.lanes;
				}
			}
			ask original_roads { do die; }
			
			// 7. Guardar el Shapefile procesado EXPLICITANDO LOS ATRIBUTOS 'direccion' Y 'lanes'
			do printLog("Saving processed network with lanes to: " + clean_path);
			save road to: clean_path format: "shp" attributes: ["direccion"::direccion, "lanes"::lanes] crs: "EPSG:4326";
			do printLog("Clean Shapefile saved successfully.");
		}
		
		// 8. Construir el Grafo Dirigido
		graph full_graph <- directed(as_edge_graph(road));
		
		// Podar nodos "sumidero" y "fuente"
		list valid_nodes <- full_graph.vertices select (
			in_degree_of(full_graph, each) > 0 and out_degree_of(full_graph, each) > 0
		);
		
		list<road> navigable_roads <- road where (
			valid_nodes contains source_of(full_graph, each) and 
			valid_nodes contains target_of(full_graph, each)
		);
		
		roads_network <- directed(as_edge_graph(navigable_roads));
		
		do color_graph_components(roads_network);
		do analyze_graph(roads_network);
		do test_pathfinding(500);
		
		if (nb_people > 0) {
			do printLog("Creating people agents...");
			create people number: nb_people with: [location :: any_location_in(world)];
			do printLog("Creating people agents: done. People agents: " + length(people));
		}
	}

	reflex evolution {
		cell <- cell * 0.8;
		diffuse var: hazard on: cell proportion: 0.5;
	}

	bool is_valid_point(point p) {
		if (p = nil) { return false; }
		if (string(p.x) = "NaN" or string(p.y) = "NaN") { return false; }
		return true;
	}

	action test_pathfinding(int num_tests) {
		do printLog("--- Testing Directed Network Reachability (" + num_tests + " tests) ---");
		
		int success_count <- 0;
		int fail_count <- 0;
		int invalid_points_count <- 0;
		failed_routes <- [];
		
		list<road> valid_roads <- (roads_network.edges collect road(each)) where (each != nil and each.shape != nil);		
		if (empty(valid_roads)) {
			do printLog("Error: No valid road geometries found in the network.");
			return;
		}

		loop i from: 1 to: num_tests {
			point origin <- any_location_in(one_of(valid_roads));
			point destination <- any_location_in(one_of(valid_roads));
			
			if (!is_valid_point(origin) or !is_valid_point(destination)) {
				invalid_points_count <- invalid_points_count + 1;
				continue;
			}
			
			path calculated_path <- path_between(roads_network, origin, destination);
			
			if (calculated_path != nil and length(calculated_path.edges) > 0) {
				success_count <- success_count + 1;
			} else {
				fail_count <- fail_count + 1;
				add line([origin, destination]) to: failed_routes;
			}
		}
		
		int total_valid_tests <- success_count + fail_count;
		float success_rate <- total_valid_tests > 0 ? (success_count / total_valid_tests) * 100.0 : 0.0;
		
		do printLog("Puntos inválidos (NaN) descartados: " + invalid_points_count);
		do printLog("Rutas válidas probadas: " + total_valid_tests);
		do printLog("Rutas exitosas: " + success_count);
		do printLog("Rutas fallidas (inaccesibles por sentido): " + fail_count);
		do printLog("Tasa de navegabilidad real: " + success_rate + "%");
		do printLog("-------------------------------------------------");
	}

	action printLog(string msg) {
		if (logLevel = 1) {
			write(string(#now) + ": " + msg);
		}	
	}

	action analyze_graph(graph g) {
		if (g != nil and length(g) > 0) {
			do printLog("--- Graph analysis [starting] ---");
			string graph_connected <- connected(g) ? "connected" : "not connected";
			do printLog("Graph " + graph_connected);
			int nb_components <- length(connected_components_of(g));
			do printLog("Nb of components: " + nb_components);
			do printLog("--- Graph analysis [ended] ---");
			return nb_components;	
		} else {
			return -1;
		}
	}
	
	action color_graph_components(graph g) {
		list<list> components <- connected_components_of(g);
		do printLog("Connected components: " + length(components));
		
		int max_size <- 0;
		int main_comp_index <- 0;
		
		loop i from: 0 to: length(components) - 1 {
			if (length(components[i]) > max_size) {
				max_size <- length(components[i]);
				main_comp_index <- i;
			}
		}
		
		list<rgb> warning_colors <- [#red, #magenta, #orange, #cyan, #yellow, #blue, #green];
		
		loop i from: 0 to: length(components) - 1 {
			list comp_nodes <- components[i];
			rgb comp_color <- (i = main_comp_index) ? #gray : warning_colors[i mod length(warning_colors)];
			int width_val <- (i = main_comp_index) ? 2 : 5;
			
			ask road {
				if (comp_nodes contains source_of(g, self)) {
					self.component_id <- i;
					self.color_component <- comp_color;
					self.line_width <- width_val;
				}
			}
		}
	}
}

species people skills: [moving] {
	float max_speed <- (30 + rnd(20)) #km/#h;
	float current_speed <- 0.0 #km/#h;
	float accel <- 1.5 #m/#s;
	float decel <- 3.0 #m/#s;
	float safety_distance <- 15.0;
	
	point target_point <- nil;

	init {
		location <- any_location_in(one_of(road));
		do select_new_target();
	}
	
	action select_new_target {
		target_point <- any_location_in(one_of(road));
	}

	reflex drive_along_network {
		if (target_point = nil or (location distance_to target_point) < 5.0) {
			do select_new_target();
		}
		
		if (target_point != nil) {
			list<people> vehicles_ahead <- (people at_distance safety_distance) select (
				each != self and 
				abs(self.heading - (self.location direction_to each.location)) < 35.0
			);
			
			if (!empty(vehicles_ahead)) {
				current_speed <- max(2.0 #km/#h, current_speed - (decel * step));
			} else {
				current_speed <- min(max_speed, current_speed + (accel * step));
			}
			
			if (current_speed > 0) {
				do goto target: target_point on: roads_network speed: current_speed;
			}
		}
	}

	aspect default {
		draw triangle(8) color: (current_speed < 5 #km/#h) ? #red : #yellow border: #black rotate: heading + 90;
	}
}

species graphnode mirrors: people {
	float size_ref <- 10.0;
	point location <- target.location update: {target.location.x, target.location.y, target.location.z + h};
	list<graphnode> my_contacts update: graphnode at_distance(dist);
	float size_current <- 10.0 update: size_ref + length(my_contacts);
	
	init {
		my_contacts <- [];
	}
	
	action updateContacts {
		my_contacts <- [];
		ask graphnode at_distance(dist) {
			add myself to: my_contacts;
		}
	}
	
	aspect default {
		draw circle(size_current) color: #blue at: location;
		draw string(length(my_contacts)) at: [location.x + 10, location.y + 10, location.z] color: #black;
		loop other over: my_contacts {
			geometry the_edge <- line(other.location, self.location);
			cell[the_edge.location] <- cell[the_edge.location] + 1;					
			draw the_edge color: #red;
		}
	}
}

species road {
	string direccion <- "";
	string highway <- "";
	string other_tags <- "";
	int lanes <- 1;
	
	int component_id <- 0;
	rgb color_component <- #black;
	int line_width <- 2;
	
	action calculate_lanes {
		if (lanes > 1) { return; }
		
		// 1. Extraer etiqueta 'lanes' de other_tags usando split_with
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
		
		// 2. Mapeo según la jerarquía 'highway'
		if (highway != nil and highway != "") {
			switch highway {
				match "motorway"      { lanes <- 3; }
				match "trunk"         { lanes <- 3; }
				match "motorway_link" { lanes <- 2; }
				match "primary"       { lanes <- 2; }
				match "primary_link"  { lanes <- 2; }
				match "secondary"     { lanes <- 2; }
				match "secondary_link"{ lanes <- 1; }
				match "tertiary"      { lanes <- 1; }
				match "residential"   { lanes <- 1; }
				match "service"       { lanes <- 1; }
				default               { lanes <- 1; }
			}
		} else {
			lanes <- 1;
		}
	}

	int traffic_count -> { length(people at_distance 2.0) };

	aspect default {
		rgb road_color <- traffic_count > 5 ? #orange : color_component;
		draw shape color: road_color width: lanes * 1.5 end_arrow: 2.0;
	}
}

experiment main type: gui {
	parameter "Distance" var: dist min: 1.0 max: 300.0;
	parameter "Height" var: h min: 0.0 max: 1000.0;
	parameter "Log Level" var: logLevel <- 1;
	
	output {
		display simulation type: opengl {
			species road aspect: default;
			species people aspect: default;
			species graphnode aspect: default;
			mesh cell scale: 5 triangulation: true transparency: 0.4 smooth: 3 above: 0.8 color: pal;
		}
	}
}

experiment graph_analysis type: gui {
	parameter nb_people var: nb_people <- 0;
	parameter logLevel var: logLevel <- 1;
	parameter scenario var: scenario <- "lomas" among: ["lomas", "gdl"];
	
	output {
		display analysis type: opengl {
			species road aspect: default;
			graphics "Failed Routes" {
				loop line_geom over: failed_routes {
					draw line_geom color: #red width: 3;
					draw circle(100) at: line_geom.points[0] color: #orange;
					draw circle(100) at: line_geom.points[1] color: #purple;
				}
			}
		}
	}
}