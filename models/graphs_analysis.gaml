/**
* Name: basemodel
* Based on the internal empty template. 
* Author: Gamaliel Palomo
* Tags: 
*/


model basemodel
global{
	int logLevel <- 0;
	string scenario <- "lomas";
	float dist <- 200;
	float h <- 50;
	int nb_people <- 500;
	field cell <- field(30,30);
	list<rgb> pal <- palette([ #black, #green, #yellow, #orange, #orange, #red, #red, #red]);
	graph roads_network;
	graph raw_network;
	string raw_path <- "../includes/shp/scenario1/roads.shp";//"../includes/shp/"+scenario+"/roads.shp";
	string clean_path <- "../includes/shp/scenario1/roads_clean.shp";//"../includes/shp/"+scenario+"/roads_clean.shp";
	shape_file roads_file <- shape_file(file_exists(clean_path) ? clean_path : raw_path);
	geometry shape <- envelope(roads_file);
	//do printLog("Importing GIS data: done." );
	list<geometry> failed_routes <- [];
	init{
	
		if (file_exists(clean_path)) {
			do printLog("Cached clean network found: " + clean_path);
			do printLog("Loading road agents directly from clean file...");
			create road from: shape_file(clean_path);
			do printLog("Road agents loaded: " + length(road));
		}
		else{
			do printLog("Clean network NOT found. Processing raw file...");
			shape_file raw_file <- shape_file(raw_path);
			raw_network <- as_edge_graph(raw_file);
			
			int graph_ok <- analyze_graph(raw_network);
			
			if (graph_ok > 1) {
				do printLog("Cleaning network...");
				list<geometry> clean_geoms <- clean_network(raw_file.contents, 3.0, true, true);
				create road from: clean_geoms;
				clean_geoms <- nil;
			} else {
				create road from: raw_file;
			}
			
			// Exporta la red limpia a un nuevo Shapefile para futuras ejecuciones
			do printLog("Saving processed network to: " + clean_path);
			save road to: clean_path format:"shp" crs:"EPSG:4326";
			do printLog("Clean Shapefile saved successfully.");
		}
		
		// Construir el grafo final a partir de los agentes road cargados
		roads_network <- as_edge_graph(road);
		do color_graph_components(roads_network);
		do analyze_graph(roads_network);
		do test_pathfinding(500);
		do printLog("Creating people agents");
		create people number:nb_people with:[location::any_location_in(world)];
		do printLog("Creating people agents: done. People agents: "+length(people));		
	}
	reflex evolution {
		//ask all cells to decrease their level of pollution
		cell <- cell * 0.8;
	
		//diffuse the pollutions to neighbor cells
		diffuse var: hazard on: cell proportion: 0.5;
	}
	bool is_valid_point(point p) {
		if (p = nil) { return false; }
		// En GAML, convertir a string es la forma más fiable de detectar NaN
		if (string(p.x) = "NaN" or string(p.y) = "NaN") { return false; }
		return true;
	}
	action test_pathfinding(int num_tests) {
		do printLog("--- Testing Network Reachability (" + num_tests + " tests) ---");
		
		int success_count <- 0;
		int fail_count <- 0;
		int invalid_points_count <- 0;
		failed_routes <- [];
		
		// 1. Filtrar solo las calles que tienen una geometría válida (longitud > 0)
		list<road> valid_roads <- road where(each.shape != nil and each.shape.perimeter > 0);
		
		if (empty(valid_roads)) {
			do printLog("Error: No valid road geometries found in the network.");
			return;
		}

		loop i from: 1 to: num_tests {
			point origin <- any_location_in(one_of(valid_roads));
			point destination <- any_location_in(one_of(valid_roads));
			
			// 2. Comprobar validez de las coordenadas obtenidas
			if (!is_valid_point(origin) or !is_valid_point(destination)) {
				invalid_points_count <- invalid_points_count + 1;
				continue; // Descarta este par e ignora la prueba
			}
			
			// 3. Evaluar el camino
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
		do printLog("Rutas fallidas (aisladas): " + fail_count);
		do printLog("Tasa de navegabilidad real: " + success_rate + "%");
		do printLog("-------------------------------------------------");
	}
	action printLog(string msg){
		if(logLevel=1){
			write(string(#now)+":"+msg);
		}	
	}
	action analyze_graph(graph g){
		if g!=nil and length(g)>0{
			do printLog("--- Graph analysis [starting] ---");
			string graph_connected <- connected(g)?"connected":"not connected";
			do printLog("Graph "+graph_connected);
			int nb_components <- length(connected_components_of(g));
			do printLog("Nb of components: "+nb_components);
			do printLog("--- Graph analysis [ended] ---");
			return nb_components;	
		}
		else{
			return -1;
		}
			
	}
	
	action color_graph_components (graph g) {
		// Obtener la lista de listas de nodos por componente
		list<list> components <- connected_components_of(g);
		do printLog("Connected components: " + length(components));
		
		// Identificar el componente principal (el que tiene más nodos)
		int max_size <- 0;
		int main_comp_index <- 0;
		
		loop i from: 0 to: length(components) - 1 {
			if (length(components[i]) > max_size) {
				max_size <- length(components[i]);
				main_comp_index <- i;
			}
		}
		
		// Paleta de colores resaltados para tramos aislados
		list<rgb> warning_colors <- [#red, #magenta, #orange, #cyan, #yellow, #blue, #green];
		
		// Asignar color y grosor a los agentes 'road' según su componente
		loop i from: 0 to: length(components) - 1 {
			list comp_nodes <- components[i];
			rgb comp_color;
			int width_val;
			
			if (i = main_comp_index) {
				comp_color <- #gray; // Red principal
				width_val <- 2;
			} else {
				// Tramos desconectados: color llamativo y línea gruesa
				comp_color <- warning_colors[i mod length(warning_colors)];
				width_val <- 5;
			}
			
			ask road {
				// Evalúa si el nodo origen de la calle pertenece a este componente
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
	// Parámetros de movilidad
	float max_speed <- (30 + rnd(20)) #km/#h; // Velocidad máxima variable por agente (30 - 50 km/h)
	float current_speed <- 0.0 #km/#h;
	float accel <- 1.5 #m/#s;                 // Tasa de aceleración
	float decel <- 3.0 #m/#s;                 // Tasa de desaceleración/frenado
	float safety_distance <- 15.0;            // Distancia mínima con el auto de adelante
	
	point target_point <- nil;

	init {
		// Ubicar inicialmente al agente sobre alguna calle válida
		location <- any_location_in(one_of(road));
		do select_new_target();
	}
	
	action select_new_target {
		// Seleccionar un punto aleatorio en la red para el siguiente viaje
		target_point <- any_location_in(one_of(road));
	}

	reflex drive_along_network {
		if (target_point = nil or (location distance_to target_point)<5.0) {
			do select_new_target();
		}
		
		if (target_point != nil) {
	        // 1. Filtrar solo vehículos dentro del cono frontal de visión (ángulo < 35°)
	        list<people> vehicles_ahead <- (people at_distance safety_distance) select (
	            each != self and 
	            abs(self.heading - (self.location direction_to each.location)) < 35.0
	        );
	        
	        // 2. Ajuste de velocidad (manteniendo una velocidad mínima para evitar parálisis permanente)
	        if (!empty(vehicles_ahead)) {
	            current_speed <- max(2.0 #km/#h, current_speed - (decel * step));
	        } else {
	            current_speed <- min(max_speed, current_speed + (accel * step));
	        }
	        
	        // 3. Moverse sobre la red
	        if (current_speed > 0) {
	            do goto target: target_point on: roads_network speed: current_speed;
	        }
	    }
	}

	aspect default {
		// Dibujar el agente orientado según su dirección de movimiento
		draw triangle(8) color: (current_speed < 5 #km/#h) ? #red : #yellow border: #black rotate: heading + 90;
	}
}
species graphnode mirrors:people{
	float size_ref <- 10;
	point location <- target.location update: {target.location.x,target.location.y,target.location.z+h};
	list<graphnode> my_contacts update:graphnode at_distance(dist);
	float size_current <-10 update: size_ref + length(my_contacts);
	init{
		my_contacts <- [];
	}
	action updateContacts{//when:every(10#cycles){
		my_contacts <- [];
		ask graphnode at_distance(dist){
			add myself to: my_contacts;
		}
	}
	aspect default{
		draw circle(size_current) color:#blue at:location;
		draw string(length(my_contacts)) at:[location.x+10,location.y+10,location.z] color:#black;
		loop other over:my_contacts{
			geometry the_edge <- line(other.location,self.location);
			cell[the_edge.location] <- cell[the_edge.location] + 1;					
			draw the_edge color:#red;
		}
	}
}

species road {
	int component_id <- 0;
	rgb color_component <- #black;
	int line_width <- 2;
	
	// Contar vehículos a menos de 2.0 metros de la calle
	int traffic_count -> { length(people at_distance 2.0) };

	aspect default {
		// Cambiar color si hay congestión
		rgb road_color <- traffic_count > 5 ? #orange : color_component;
		draw shape color: road_color width: line_width;
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

experiment graph_analysis type:gui {
	parameter nb_people var:nb_people <- 0;
	parameter logLevel var:logLevel <- 1;
	parameter scenario var:scenario <- "lomas" among:["lomas","gdl"];
	output{
		display analysis type:opengl{
			species road aspect:default;
			// Capa para resaltar en rojo las rutas inaccesibles
			graphics "Failed Routes" {
				loop line_geom over: failed_routes {
					draw line_geom color: #red width: 3;
					draw circle(100) at: line_geom.points[0] color: #orange; // Origen
					draw circle(100) at: line_geom.points[1] color: #purple; // Destino
				}
			}
		}
	}
}