/**
* Name: CityScope.gaml
* Authors: Gamaliel Palomo, Juan Alvarez, Arnaud Grignard
* Description: Modelo CityScope Guadalajara con control de emisiones vehiculares en malla 3D, prevención de gridlock y parámetros de visualización en GUI.
*/

model CityScope
import "constants.gaml"

global skills:[network]{
	
	// --- CAMPOS ESCALARES 3D (FIELD) ---
	field heatmap_field <- field(120, 120);
	// Paleta Cyberpunk de Alto Contraste (Transparente en base -> Cian -> Verde -> Amarillo -> Rojo -> Magenta)
	// Paleta que inicia en NEGRO para fundir el valor 0.0 con el fondo
	list<rgb> heatmap_palette <- palette([#black, #navy, #blue, #cyan, #green, #yellow, #orange, #red]);
	
	field emissions_field <- field(120, 120);
	list<rgb> emissions_palette <- palette([#black, #darkgreen, #yellow, #orange, #red, #purple]);
	
	// --- METRICAS GLOBALES DE TRAFICO Y EMISIONES ---
	float avg_speed <- 0.0 update: empty(vehicle) ? 0.0 : mean(vehicle collect(each.current_speed));
	float avg_wasted_time <- 0.0 update: empty(vehicle where(each.is_stopped)) ? 0.0 : mean(vehicle where(each.is_stopped) collect(each.wasted_time));
	float total_emissions_generated <- 0.0;
	
	int green_time <- 50;
	int red_time <- 50;
	
	// Shape files
	file dcu_limit_shp <- file(dcu_limits_filename);
	file dcu_satellite_shp <- file(main_shp_path+"environment/envolvente_mesa_imagen_satelital.shp");
	file ccu_limit_shp <- file(main_shp_path+"environment/scenario_limits.shp");
	file ccu_transport_shp <- file(main_shp_path+dcu_transport_filename);
	file ccu_massive_transport_shp <- file(main_shp_path+dcu_massive_transport_filename);
	file cycling_ways_shp <- file(dcu_cycling_way_filename);
	file intervention_areas_shp <- file(main_shp_path+intervention_areas_filename);
	file economic_activities_shp <- file(main_shp_path+economic_activities_filename);
	file projects_csv <- csv_file(main_csv_path+projects_csv_filename);
	file day_activities_csv <- csv_file(main_csv_path+day_activities_csv_filename);
	file night_activities_csv <- csv_file(main_csv_path+night_activities_csv_filename);
	file knowledge_activities_csv <- csv_file(main_csv_path+knowledge_activities_csv_filename);
	file interaction_places_csv <- csv_file(main_csv_path+interaction_places_csv_filename);
	file tertiary_activities_csv <- csv_file(main_csv_path+third_places_csv_filename);
	file projects_shp <- file(main_shp_path+projects_shp_filename);
	file allowed_activities_csv <- csv_file(main_csv_path+allowed_activities_by_use_filename);
	file green_areas_shp <- file(main_shp_path+green_areas_file);
	
	// Listas genéricas
	list<blocks> current_active_blocks;
	list<household> current_active_households;
	
	// Escenarios
	file s1_roads_shp 				<- file(main_shp_path+"scenario1/roads_clean.shp");
	file s1_aux_roads_shp 		<- file(main_shp_path+"scenario1/aux_roads.shp");
	file s1_blocks_shp 				<- file(main_shp_path+"scenario1/blocks.shp");
	file s1_equipment_shp 		<- file(main_shp_path+"scenario1/equipment.shp");
	file s1_grid_shp 					<- file(main_shp_path+"scenario1/grid.shp");
	
	file s2_roads_shp 				<- file(main_shp_path+"scenario2/roads.shp");
	file s2_aux_roads_shp 		<- file(main_shp_path+"scenario2/aux_roads.shp");
	file s2_blocks_shp 				<- file(main_shp_path+"scenario2/blocks.shp");
	file s2_grid_shp 					<- file(main_shp_path+"scenario2/grid.shp");
	
	// Entorno espacial
	geometry shape <- envelope(dcu_limit_shp);
	
	// Redes de movilidad
	graph roads_network;
	graph event_roads_network;
	map<string,path> paths;
	map event_roads_weight;
	map roads_weight;
	
	// Conexión Red MQTT
	bool enable_mqtt <- false;
	string mqtt_server_name <- "localhost";
	string mqtt_topic <- "cityscope_table";
	
	// Opciones de visualización
	bool show_satellite <- false;
	bool show_people <- true;
	bool show_information <- false;
	bool show_emissions <- false;
	
	// Lista persistente de unidades económicas para evitar consultas concurrentes a la población
	list<economic_unit> active_economic_units;
	
	// Variables de mapa de calor
	string current_heatmap 		<- "";
	bool show_heatmap 			<- false;
	list<heatmap> ccu_heatmap;
	
	// Equipamientos
	list<equipment> education_facilities;
	list<equipment> culture_facilities;
	list<equipment> health_facilities;
	list<equipment> sports_facilities;
	list<base_grid> ref_grid;
	
	// Intervenciones y actividades
	map<string,list<string>> allowed_activities;
	list<string> day_activities;
	list<string> night_activities;
	list<string> interaction_places;
	list<string> knowledge_activities;
	list<string> tertiary_activities;
	map<string,int> current_scenarios;
	
	// Indicadores para dashboard
	bool allow_export_data 				<- true;
	bool allow_export_data_sc2 			<- false;
	bool allow_export_current_data 	<- false;
	int 	 time_2_save_data				    <- 0;
	int	 time_2_update_heatmap 		<- 0;
	bool semaphore 							<- false;
	bool reset_counter							<- false;
	bool scenario_changed 				<- false;
	
	// Indicadores en 3 escenarios
	list<float> dash_day_activities_diversity 					<- [0.0,0.0,0.0];
	list<float> dash_night_activities_diversity 				<- [0.0,0.0,0.0];
	list<float> dash_third_activities_diversity 				<- [0.0,0.0,0.0];
	list<float> dash_knowledge_activities_diversity 			<- [0.0,0.0,0.0];
	list<float> dash_interaction_diversity 						<- [0.0,0.0,0.0];
	list<float> dash_hab_net_density 							<- [0.0,0.0,0.0];
	list<float> dash_living_place_density 						<- [0.0,0.0,0.0];
	list<float> dash_day_density 								<- [0.0,0.0,0.0];
	list<float> dash_night_density 								<- [0.0,0.0,0.0];
	list<float> dash_knowledge_density							<- [0.0,0.0,0.0];
	list<float> dash_interaction_density						<- [0.0,0.0,0.0];
	list<float> dash_mean_activities_density					<- [0.0,0.0,0.0];
	list<float> dash_green_space_per_hab 							<- [0.0,0.0,0.0];
	list<float> dash_public_spaces_proximity 					<- [0.0,0.0,0.0];
	list<float> dash_educational_equipment_proximity 			<- [0.0,0.0,0.0];
	list<float> dash_cultural_equipment_proximity 				<- [0.0,0.0,0.0];
	list<float> dash_health_equipment_proximity 				<- [0.0,0.0,0.0];
	list<float> dash_social_assistance_equipment_proximity 		<- [0.0,0.0,0.0];
	list<float> dash_mean_facilities_proximity					<- [0.0,0.0,0.0];
	list<float> dash_intersections_density 						<- [0.0,0.0,0.0];
	list<float> dash_public_transport_coverage					<- [0.0,0.0,0.0];
	list<float>	dash_km_ways_per_hab							<- [0.0,0.0,0.0];
	list<float>	dash_km_ways_per_km2							<- [0.0,0.0,0.0];
	list<float> dash_energy_requirement 	<- [0.0,0.0,0.0];
	list<float> dash_water_requirement 		<- [0.0,0.0,0.0];
	list<float> dash_waste_generation 		<- [0.0,0.0,0.0];
	
	map<int,string> int_to_day <- [1::"Jueves",2::"Viernes",3::"Sábado",4::"Domingo",5::"Lunes",6::"Martes",7::"Miércoles"];

	init{
		step <- 1#seconds;
		starting_date <- date("2022-11-26 06:00:00");
		
		emissions_field <- field(120, 120, 0.0);
		
		if (enable_mqtt){
			write "Initializing MQTT connection";
			do connect to:"localhost" with_name:"cityscope_table";
		}
		
		create ccu_limit from: dcu_limit_shp;
		create transport_station from: ccu_transport_shp with:[type::"bus"];
		create transport_station from: ccu_massive_transport_shp with:[type::"massive",subtype::string(read("Sistema"))];
		create cycling_way from:cycling_ways_shp;
		
		// Agentes Escenario 1
		create roads from:s1_roads_shp with: [
		    lanes :: int(read("lanes"))
		];
		create aux_roads from:s1_aux_roads_shp with:[from_scenario::1, length::float(read("largo_m"))];
		create aux_roads from:s2_aux_roads_shp with:[from_scenario::2, length::float(read("largo_m"))];
		create blocks from:s1_blocks_shp with:[id::read("ID_BLOCK"),from_scenario::1,nb_people::int(read("POB1")),block_area::float(read("area_m2")),viv_type::read("TIPO_VIVIE"), nb_households::int(read("VIVTOTAL"))]{
			create people number:int(nb_people/5) with:[home_block::self,target_block::one_of(blocks-self)]{
				from_scenario <- 1;
				home_point <- any_location_in(home_block);
				location <- home_point;
				mobility_type <- select_mobility_mode();
			}
			create household number:nb_households with:[location::any_location_in(self),from_scenario::1] returns:tmp_my_households;
			if tmp_my_households != nil{
				ask tmp_my_households{ add self to:myself.my_households; }
				tmp_my_households <- [];
			}
		}
		
		current_active_blocks <- list(blocks);
		
		// Red Vial e Intersecciones
		graph full_graph <- directed(as_edge_graph(roads));
		list<list> comp_list <- connected_components_of(full_graph);
		list main_nodes <- comp_list with_max_of (length(each));
		
		list<roads> active_roads <- roads where (
			main_nodes contains source_of(full_graph, each) and 
			main_nodes contains target_of(full_graph, each)
		);
		
		roads_weight <- active_roads as_map (each:: each.shape.perimeter);
		roads_network <- directed(as_edge_graph(active_roads));
		
		create intersection from: vertices(roads_network);
		ask intersection {
			if flip(0.0) {
				is_traffic_light <- true;
				is_green <- true;
				do setup_traffic_light;
			}
		}
		
		// Vehículos
		create vehicle number: 500 { type <- "car"; }
		create vehicle number: 80 { type <- "moto"; }
		create vehicle number: 50 { type <- "bus"; }
		create vehicle number: 50 { type <- "bike"; }
		
		create economic_unit from:economic_activities_shp with:[from_scenario::1,activity_id::read("codigo_act"),sub_id::read("sec_sub")];
		active_economic_units <- list(economic_unit); // Primera foto fija inicial
		create equipment from:s1_equipment_shp with:[type::string(read("tipo_equip")),subtype::string(read("cat_sedeso")),from_scenario::1];
		create green_area from:green_areas_shp with:[surface_area::float(read("area_m2"))];
		create base_grid from:s1_grid_shp with:[night_diversity::float(read("ID_NOCHE")),day_diversity::float(read("ID_DIA")),knowledge_diversity::float(read("ID_CONOCIM")),from_scenario::1];
		
		// Agentes Escenario 2
		create blocks from:s2_blocks_shp with:[id::read("ID_BLOCK"),from_scenario::2,nb_people::int(read("POB1")),block_area::float(read("area_m2"))]{
			block_area <- block_area * 10000;
			nb_households <- int(nb_people / mean_family_size);
			create household number:nb_households with:[location::any_location_in(self),from_scenario::2] returns:tmp_my_households;
			if tmp_my_households != nil{
				ask tmp_my_households{ add self to:myself.my_households; }
				tmp_my_households <- [];				
			}
		}
		
		list<household> raw_current_active_households <- list(household);
		
		// Accesibilidad
		ask people{
			int transport_accessibilty_count <- 0;
			list<float> distances <- [];
			transport_station closest_station <- transport_station where(each.type="bus") closest_to self;
			add closest_station distance_to self to:distances;
			closest_station <- transport_station where(each.type="massive" and each.subtype="BRT (Bus Rapid Transit)") closest_to self;
			add closest_station distance_to self to:distances;
			closest_station <- transport_station where(each.type="massive" and each.subtype="Tren Eléctrico") closest_to self;
			add closest_station distance_to self to:distances;
			cycling_way closest_cycling_way <- cycling_way closest_to self;
			add closest_station distance_to self to:distances;
			
			if distances[0] < 300{ transport_accessibilty_count <- transport_accessibilty_count + 1; } 
			if distances[1] < 500{ transport_accessibilty_count <- transport_accessibilty_count + 1; }
			if distances[2] < 800{ transport_accessibilty_count <- transport_accessibilty_count + 1; }
			if distances[3] < 300{ transport_accessibilty_count <- transport_accessibilty_count + 1; }
			mobility_accessibility <- transport_accessibilty_count /4;
			ind_public_transport_coverage <- transport_accessibilty_count >=3;
		}		
		
		create satellite_background from:dcu_satellite_shp;
		
		// Tablas de actividades
		matrix data <- matrix(allowed_activities_csv);
		loop i from:1 to:data.rows-1{
			list<string> tmp;
			loop j from:2 to:data.columns-1{
				if data[j,i] != "NA"{ add data[j,i] to: tmp;}
			}
			add data[0,i]::tmp to:allowed_activities;
		}
		data <- matrix(day_activities_csv);
		loop i from:1 to:data.rows-1{ add data[0,i] to:day_activities; }
		data <- matrix(night_activities_csv);
		loop i from:1 to:data.rows-1{ add data[0,i] to:night_activities; }
		data <- matrix(interaction_places_csv);
		loop i from:1 to:data.rows-1{ add data[0,i] to:interaction_places; }
		data <- matrix(knowledge_activities_csv);
		loop i from:1 to:data.rows-1{ add data[0,i] to:knowledge_activities; }
		data <- matrix(tertiary_activities_csv);
		loop i from:1 to:data.rows-1{ add data[0,i] to:tertiary_activities; }
		
		data <- matrix(projects_csv);
		loop i from: 0 to: data.rows -1{
			create project with:[
				block_id::data[0,i], id::data[1,i], letter::data[2,i], project_name::data[3,i],
				use_type::data[6,i], from_scenario::2, population::int(data[8,i]),
				nb_ec_units::int(data[12,i]), viv_eco::int(data[9,i]), viv_med::int(data[10,i]),
				viv_res::int(data[11,i]), green_area::int(data[12,i])
			]{
				blocks the_block <- first(blocks where(each.from_scenario=2 and each.id = block_id));
				ask the_block{ viv_eco <- myself.viv_eco; viv_med <- myself.viv_med; viv_res <- myself.viv_res; }
			}
		}	
		
		create intervention_area from:intervention_areas_shp with:[active_scenario::1,id::read("fid"),area_name::read("nombre"),associated_projects_str::read("id_ccu"), blocksS1_str::read("ID_BLOCK_E"),blocksS2_str::read("ID_BLOCK_1"),blocksS3_str::read("ID_BLOCK_2")]{
			add self.area_name::1 to:current_scenarios;
			list<string> valid_project_ids <- project collect(each.id);
			if associated_projects != nil{
				list<string> str_projects <- split_with(associated_projects_str,",");
				if not empty(str_projects){
					loop p_id over: str_projects{
						if p_id in valid_project_ids{ add first(project where(each.id=p_id)) to:associated_projects; }
					}
				}
			}
			list<string> valid_block_ids <- blocks collect(each.id);
			if blocksS1_str != nil{
				list<string> tmp <- split_with(blocksS1_str,",");
				if not empty(tmp){
					loop b_id over: tmp{
						if b_id in valid_block_ids{ add first(blocks where(each.id=b_id and each.from_scenario=1)) to:blocks_by_scenario[0]; }
					}
				}
			}
			if blocksS2_str != nil{
				list<string> tmp <- split_with(blocksS2_str,",");
				if not empty(tmp){
					loop b_id over: tmp{
						if b_id in valid_block_ids{ add first(blocks where(each.id=b_id and each.from_scenario=2)) to:blocks_by_scenario[1]; }
					}
				}
			}
			if blocksS3_str != nil{
				list<string> tmp <- split_with(blocksS3_str,",");
				if not empty(tmp){
					loop b_id over: tmp{
						if b_id in valid_block_ids{ add first(blocks where(each.id=b_id and each.from_scenario=2)) to:blocks_by_scenario[2]; }
					}
				}
			}
		}	
		
		// Limpieza
		ccu_limit_shp <- []; s1_roads_shp <- []; s1_aux_roads_shp <- []; s2_aux_roads_shp <- [];
		s1_blocks_shp <- []; s1_equipment_shp <- []; s1_grid_shp <- []; s2_roads_shp <- [];
		s2_blocks_shp <- []; s2_grid_shp <- []; green_areas_shp <- []; ccu_transport_shp <- [];
		ccu_massive_transport_shp <- []; dcu_satellite_shp <- []; cycling_ways_shp <- [];
		intervention_areas_shp <- []; projects_shp <- [];
		
		education_facilities 	<- equipment where(each.type="Educación");
		culture_facilities 		<- equipment where(each.type="Cultura");
		health_facilities 			<- equipment where(each.type="Salud");
		sports_facilities			<- equipment where(each.type="Deporte");
		
		list<people> valid_people;
		ask ccu_limit{
			ccu_heatmap 				<- heatmap inside(self+50);
			ref_grid					<- base_grid inside(self +100);
			valid_people <- people inside self;
			current_active_households <- raw_current_active_households inside self;
		}
		ask people{ if not (self in valid_people){ to_be_killed <- true; } }
		ask heatmap{ if not(self in ccu_heatmap){ do die; } }
		ask household{ if not(self in current_active_households){ do die; } }
		current_active_households <- household where(each.from_scenario = 1);
		
		do heatmap2populationdensity;
	}

	reflex emissions_evolution when:every(10 #cycle){
		if (emissions_field != nil) {
			emissions_field <- emissions_field * 0.88;
			diffuse var: pollution on: emissions_field proportion: 0.7;
		}
	}

	reflex update_current_heatmap when:scenario_changed and show_heatmap{
		if time_2_update_heatmap > 0{
			time_2_update_heatmap <- time_2_update_heatmap - 1;
		} else {
			switch current_heatmap{
				match "health" {do heatmap2health;}
				match "culture"{do heatmap2culture;}
				match "education"{do heatmap2education;}
				match "sports"{do heatmap2sports;}
				match "day_diversity"{do heatmap2daydiv;}
				match "night_diversity"{do heatmap2nightdiv;}
				match "knowledge_diversity"{do heatmap2knowdiv;}
				match "day_density"{do heatmap2daydensity;}
				match "night_density"{do heatmap2nightdensity;}
				match "knowledge_density"{do heatmap2knowledgedensity;}
				match "interaction_density"{do heatmap2interactiondensity;}
				match "population_density"{do heatmap2populationdensity;}
				match "mobility" {do heatmap2mobility;}
			}
			scenario_changed <- false;
		}
	}
	
	reflex readMailBox when:has_more_message() and enable_mqtt{
		message the_message <- fetch_message();
		string new_string <- the_message.contents;
		list<string> words <- split_with(new_string,",");
		loop w over: words{
			list<string> letters <- split_with(w,"/");
			if letters[0] = "S"{
				string opt <- letters[1];
				switch opt{
					match "Current"{do activate_scenario1();}
					match "MasterPlan"{do activate_scenario2();}
				}
			} else if letters[0] != "Z" and letters[0] != "M"{
				current_scenarios[letters[0]] <- int(letters[1]);
				ask intervention_area where(each.area_name=letters[0]){
					do activate_scenario(int(letters[1]));
				}
			}			
		}
	}
	
	action activate_scenario1{
		reset_counter <- true;
		ask intervention_area { do activate_scenario(1); }
	}
	action activate_scenario2{
		reset_counter <- true;
		ask intervention_area { do activate_scenario(2); }
	}
	action change_scenario_A{
		ask intervention_area where(each.area_name="A"){
			int tmp_sc <- self.active_scenario;
			if tmp_sc=3{ tmp_sc <- 0; }
			tmp_sc <- tmp_sc + 1;
			do activate_scenario(tmp_sc);
		}
		allow_export_current_data <- true;
	}
	action change_scenario_B{
		ask intervention_area where(each.area_name="B"){
			int tmp_sc <- self.active_scenario;
			if tmp_sc=3{ tmp_sc <- 0; }
			tmp_sc <- tmp_sc + 1;
			do activate_scenario(tmp_sc);
		}
		allow_export_current_data <- true;
	}
	action change_scenario_K{
		ask intervention_area where(each.area_name="K"){
			int tmp_sc <- self.active_scenario;
			if tmp_sc=3{ tmp_sc <- 0; }
			tmp_sc <- tmp_sc + 1;
			do activate_scenario(tmp_sc);
		}
		allow_export_current_data <- true;
	}
	action change_scenario_L{
		ask intervention_area where(each.area_name="L"){
			int tmp_sc <- self.active_scenario;
			if tmp_sc=3{ tmp_sc <- 0; }
			tmp_sc <- tmp_sc + 1;
			do activate_scenario(tmp_sc);
		}
		allow_export_current_data <- true;
	}
	action change_scenario_I{
		ask intervention_area where(each.area_name="I"){
			int tmp_sc <- self.active_scenario;
			if tmp_sc=3{ tmp_sc <- 0; }
			tmp_sc <- tmp_sc + 1;
			do activate_scenario(tmp_sc);
		}
		allow_export_current_data <- true;
	}

	action toggle_emissions_display {
		show_emissions <- !show_emissions;
	}

	action show_satellite_action{
		show_satellite <- !show_satellite;
	}

	// Metricas urbanas
	float mean_education_proximity{
		int people_with_access <- 0;
		ask current_active_blocks inside (first(ccu_limit+1000)){
			nb_different_education_equipment <- 0;
			loop class over:education_distances.keys{
				list<equipment> tmp_list <- education_facilities where(each.subtype = class) at_distance(education_distances[class]);
				nb_different_education_equipment <- empty(tmp_list)?nb_different_education_equipment:nb_different_education_equipment+1;
			}
			ind_proximity_2_education_equipment <- nb_different_education_equipment > min_education_equipment;
			people_with_access <- people_with_access + (ind_proximity_2_education_equipment?self.nb_people:0);
		}
		return people_with_access/sum(current_active_blocks collect(each.nb_people));
	}
	
	float mean_culture_proximity{
		int people_with_access <- 0;
		ask current_active_blocks inside (first(ccu_limit+1000)){
			nb_different_cultural_equipment <- 0;
			loop class over:culture_distances.keys{
				list<equipment> tmp_list <- culture_facilities where(each.subtype = class) at_distance(culture_distances[class]);
				nb_different_cultural_equipment <- empty(tmp_list)?nb_different_cultural_equipment:nb_different_cultural_equipment+1;
			}
			ind_proximity_2_cultural_equipment <- nb_different_cultural_equipment > min_culture_equipment;
			people_with_access <- people_with_access + (ind_proximity_2_cultural_equipment?self.nb_people:0);
		}
		return people_with_access/sum(current_active_blocks collect(each.nb_people));
	}
	
	float mean_health_proximity{
		int people_with_access <- 0;
		ask current_active_blocks inside (first(ccu_limit+1000)){
			nb_different_health_equipment <- 0;
			loop class over:health_distances.keys{
				list<equipment> tmp_list <- health_facilities where(each.subtype = class) at_distance(health_distances[class]);
				nb_different_health_equipment <- empty(tmp_list)?nb_different_health_equipment:nb_different_health_equipment+1;
			}
			ind_proximity_2_health_equipment <- nb_different_health_equipment > min_health_equipment;
			people_with_access <- people_with_access + (ind_proximity_2_health_equipment?self.nb_people:0);
		}
		return people_with_access/sum(current_active_blocks collect(each.nb_people));
	}
	
	float mean_sports_proximity{
		int people_with_access <- 0;
		ask current_active_blocks inside (first(ccu_limit+1000)){
			nb_different_sports_equipment <- 0;
			loop class over:health_distances.keys{
				list<equipment> tmp_list <- sports_facilities where(each.subtype = class) at_distance(sports_distances[class]);
				nb_different_sports_equipment <- empty(tmp_list)?nb_different_sports_equipment:nb_different_sports_equipment+1;
			}
			ind_proximity_2_sports_equipment <- nb_different_sports_equipment > min_sports_equipment;
			people_with_access <- people_with_access + (ind_proximity_2_sports_equipment?self.nb_people:0);
		}
		return people_with_access/sum(current_active_blocks collect(each.nb_people));
	}
	
	float mean_energy_requirement{
		ask current_active_blocks{ do compute_energy_requirement; }
		return mean(current_active_blocks where(each.energy_requirement>0) collect(each.energy_requirement));
	}
	float mean_waste_generation{
		ask current_active_blocks{ do compute_waste_generation; }
		return mean(current_active_blocks where(each.waste_generation>0) collect(each.waste_generation));
	}
	float mean_water_requirement{
		ask current_active_blocks{ do compute_water_requirement; }
		return mean(current_active_blocks where(each.water_requirement>0) collect(each.water_requirement));
	}
	float mean_population_density{
		float total_blocks_area <- sum(current_active_blocks collect(each.block_area)) * 0.0001;
		int total_population <- sum(current_active_blocks collect(each.nb_people));
		return total_population/total_blocks_area;
	}
	float mean_household_density{
		float total_blocks_area <- sum(current_active_blocks collect(each.block_area)) * 0.0001;
		int total_household <- sum(current_active_blocks collect(each.nb_households));
		return total_household/total_blocks_area;
	}
	float km_roads_per_person(int sc){
		return sum(aux_roads where(each.from_scenario = sc) collect(each.length))/sum(current_active_blocks collect(each.nb_people));
	}
	float km_roads_per_km2(int sc){
		return sum(aux_roads where(each.from_scenario = sc) collect(each.length))/dcu_area_ha;
	}
	
	float mean_diversity_day{
		map<string,int> class_counter;
		loop i over:day_activities{ add i::0 to:class_counter; }
		list<economic_unit> valid_units <- active_economic_units where(not dead(each) and each.sub_id in day_activities);
		if not empty(valid_units){
			loop act over:valid_units{ class_counter[act.sub_id] <- class_counter[act.sub_id] + 1; }
		}
		int total_activities <- sum(class_counter.values);
		return total_activities=0 ? 0.0 : -1*sum(class_counter.values collect((each/total_activities)*(each<=0?0:ln(each/total_activities))));
	}
	
	float mean_diversity_night{
		map<string,int> class_counter;
		loop i over:night_activities{ add i::0 to:class_counter; }
		list<economic_unit> valid_units <- active_economic_units where(not dead(each) and each.sub_id in night_activities);
		if not empty(valid_units){
			loop act over:valid_units{ class_counter[act.sub_id] <- class_counter[act.sub_id] + 1; }
		}
		int total_activities <- sum(class_counter.values);
		return total_activities=0 ? 0.0 : -1*sum(class_counter.values collect((each/total_activities)*(each<=0?0:ln(each/total_activities))));
	}

	float mean_diversity_knowledge{
		map<string,int> class_counter;
		loop i over:knowledge_activities{ add i::0 to:class_counter; }
		list<economic_unit> valid_units <- active_economic_units where(not dead(each) and each.sub_id in knowledge_activities);
		if not empty(valid_units){
			loop act over:valid_units{ class_counter[act.sub_id] <- class_counter[act.sub_id] + 1; }
		}
		int total_activities <- sum(class_counter.values);
		return total_activities=0 ? 0.0 : -1*sum(class_counter.values collect((each/total_activities)*(each<=0?0:ln(each/total_activities))));
	}

	float mean_diversity_interaction{
		map<string,int> class_counter;
		loop i over:interaction_places{ add i::0 to:class_counter; }
		list<economic_unit> valid_units <- active_economic_units where(not dead(each) and each.sub_id in interaction_places);
		if not empty(valid_units){
			loop act over:valid_units{ class_counter[act.sub_id] <- class_counter[act.sub_id] + 1; }
		}
		int total_activities <- sum(class_counter.values);
		return total_activities=0 ? 0.0 : -1*sum(class_counter.values collect((each/total_activities)*(each<=0?0:ln(each/total_activities))));
	}

	float mean_density_day{
		list<economic_unit> tmp_units <- economic_unit where(each.sub_id in day_activities);
		return length(economic_unit)>0 ? length(tmp_units)/length(economic_unit) : 0;
	}
	float mean_density_night{
		list<economic_unit> tmp_units <- economic_unit where(each.sub_id in night_activities);
		return length(economic_unit)>0 ? length(tmp_units)/length(economic_unit) : 0;
	}
	float mean_density_knowledge{
		list<economic_unit> tmp_units <- economic_unit where(each.sub_id in knowledge_activities);
		return length(economic_unit)>0 ? length(tmp_units)/length(economic_unit) : 0;
	}
	float mean_density_interactions{
		list<economic_unit> tmp_units <- economic_unit where(each.sub_id in interaction_places);
		return length(economic_unit)>0 ? length(tmp_units)/length(economic_unit) : 0;
	}

	// Mapas de calor de indicadores
	action heatmap2education{
		current_heatmap <- "education";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask current_active_blocks inside (first(ccu_limit+1000)){
			nb_different_education_equipment <- 0;
			loop class over:education_distances.keys{
				list<equipment> tmp_list <- education_facilities where(each.subtype = class) at_distance(education_distances[class]);
				nb_different_education_equipment <- empty(tmp_list)?nb_different_education_equipment:nb_different_education_equipment+1;
			}
			ind_proximity_2_education_equipment <- nb_different_education_equipment > min_education_equipment;
			list<people> my_people <- people where(each.home_block=self);
			ask my_people{ ind_education_equipment_proximity <- myself.ind_proximity_2_education_equipment; }
			education_proximity <- length(my_people) = 0 ? 0.0 : length(my_people where(each.ind_education_equipment_proximity))/length(my_people);
			
			ask ref_grid{
				list<blocks> my_blocks <- current_active_blocks at_distance(150);
				if my_blocks = nil or length(my_blocks) = 0 or my_blocks = []{ my_blocks <- [current_active_blocks closest_to(self)]; }
				float value <- mean(my_blocks collect(each.education_proximity));
				ask heatmap inside(self){ grid_value <- value; }
			}
		}
		do spread_value(spread_value_factor);
	}
	
	action heatmap2culture{
		current_heatmap <- "culture";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask current_active_blocks{
			nb_different_cultural_equipment <- 0;
			loop class over:culture_distances.keys{
				list<equipment> tmp_list <- culture_facilities where(each.subtype = class) at_distance(culture_distances[class]);
				nb_different_cultural_equipment <- empty(tmp_list)?nb_different_cultural_equipment:nb_different_cultural_equipment+1;
			}
			ind_proximity_2_cultural_equipment <- nb_different_cultural_equipment > min_culture_equipment;
			list<people> my_people <- people where(each.home_block=self);
			ask my_people{ ind_cultural_equipment_proximity <- myself.ind_proximity_2_cultural_equipment; }
			culture_proximity <- length(my_people) = 0 ? 0.0 : length(my_people where(each.ind_cultural_equipment_proximity))/length(my_people);
			
			ask ref_grid{
				list<blocks> my_blocks <- current_active_blocks at_distance(150);
				if my_blocks = nil or length(my_blocks)=0 or my_blocks = []{ my_blocks <- [current_active_blocks closest_to(self)]; }
				float value <- mean(my_blocks collect(each.culture_proximity));
				ask heatmap inside(self){ grid_value <- value; }
			}
		}
		do spread_value(spread_value_factor);
	}
	
	action heatmap2health{
		current_heatmap <- "health";
		show_heatmap <- true;
		ask current_active_blocks{
			nb_different_health_equipment <- 0;
			loop class over:health_distances.keys{
				list<equipment> tmp_list <- health_facilities where(each.subtype = class) at_distance(health_distances[class]);
				nb_different_health_equipment <- empty(tmp_list)?nb_different_health_equipment:nb_different_health_equipment+1;
			}
			ind_proximity_2_health_equipment <- nb_different_health_equipment > min_health_equipment;
			list<people> my_people <- people where(each.home_block=self);
			ask my_people{ ind_health_equipment_proximity <- myself.ind_proximity_2_health_equipment; }
			health_proximity <- length(my_people) = 0 ? 0.0 : length(my_people where(each.ind_health_equipment_proximity))/length(my_people);
		}
		ask ref_grid{
			list<blocks> my_blocks <- current_active_blocks at_distance(150);
			if my_blocks = nil or length(my_blocks)=0 or my_blocks = []{ my_blocks <- [current_active_blocks closest_to(self)]; }
			float value <- mean(my_blocks collect(each.health_proximity));
			ask heatmap inside(self){ grid_value <- value; }
		}
		do spread_value(spread_value_factor);
	}
	
	action heatmap2sports{
		current_heatmap <- "sports";
		show_heatmap <- true;
		ask current_active_blocks{
			nb_different_sports_equipment <- 0;
			loop class over:sports_distances.keys{
				list<equipment> tmp_list <- sports_facilities where(each.subtype = class) at_distance(sports_distances[class]);
				nb_different_sports_equipment <- empty(tmp_list)?nb_different_sports_equipment:nb_different_sports_equipment+1;
			}
			ind_proximity_2_sports_equipment <- nb_different_sports_equipment > min_sports_equipment;
			list<people> my_people <- people where(each.home_block=self);
			ask my_people{ ind_sports_equipment_proximity <- myself.ind_proximity_2_sports_equipment; }
			sports_proximity <- length(my_people) = 0 ? 0.0 : length(my_people where(each.ind_sports_equipment_proximity))/length(my_people);
		}
		ask ref_grid{
			list<blocks> my_blocks <- current_active_blocks at_distance(150);
			if my_blocks = nil or length(my_blocks)=0 or my_blocks = []{ my_blocks <- [current_active_blocks closest_to(self)]; }
			float value <- mean(my_blocks collect(each.sports_proximity));
			ask heatmap inside(self){ grid_value <- value; }
		}
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask sports_facilities{
			blocks the_block <- current_active_blocks closest_to self;
			ask the_block{
				list<heatmap> the_cells <- ccu_heatmap overlapping self;
				ask the_cells{ grid_value <- 1.0; }
			}		
		}
		do spread_value(spread_value_factor);
	}
	
	action heatmap2mobility{
		current_heatmap <- "mobility";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask current_active_blocks{
			list<people> my_people <- people where(each.home_block=self);
			mobility_access <- mean(my_people collect(each.mobility_accessibility));
		}
		ask ref_grid{
			list<blocks> my_blocks <- current_active_blocks at_distance(150);
			if my_blocks = nil or length(my_blocks)=0 or my_blocks = []{ my_blocks <- [current_active_blocks closest_to(self)]; }
			float value <- mean(my_blocks collect(each.mobility_access));
			ask heatmap inside(self){ grid_value <- value; }
		}
		do spread_value(spread_value_factor);
	}
	
	action heatmap2daydiv{
		current_heatmap <- "day_diversity";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask ref_grid{
			do compute_diversity_day;
			ask heatmap inside(self){ grid_value <- myself.day_diversity; }
		}
		do spread_value(spread_value_factor);
	}
	
	action heatmap2nightdiv{
		current_heatmap <- "night_diversity";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask ref_grid{
			do compute_diversity_night;
			ask heatmap inside(self){ grid_value <- myself.night_diversity; }
		}
		do spread_value(spread_value_factor);
	}
	
	action heatmap2knowdiv{
		current_heatmap <- "knowledge_diversity";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask ref_grid{
			do compute_diversity_night;
			ask heatmap inside(self){ grid_value <- myself.knowledge_diversity; }
		}
		do spread_value(spread_value_factor);
	}
	
	action heatmap2populationdensity{
		current_heatmap <- "population_density";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask ref_grid{ do compute_population_living_inside; }
		
		int max_pop <- max(ref_grid collect(each.people_living_inside));
		
		ask ref_grid{
			ask heatmap inside(self){
				if (max_pop > 0 and myself.people_living_inside > 0) {
					float ratio <- myself.people_living_inside / max_pop;
					// Aplicamos raíz cuadrada para dar visibilidad y color neón a las zonas medias/altas
					grid_value <- min([1.0, sqrt(ratio)]); 
				} else {
					grid_value <- 0.0;
				}
			}
		}
		do spread_value(spread_value_factor);
	}
	action heatmap2householddensity{
		current_heatmap <- "household_density";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask ref_grid{ do compute_household_inside; }
		int max_households_in_grid <- max(ref_grid collect(each.households_inside));
		ask ref_grid{
			ask heatmap inside(self){ grid_value <- max_households_in_grid > 0 ? myself.households_inside/max_households_in_grid : 0.0; }
		}
		do spread_value(spread_value_factor);
	}

	action heatmap2daydensity{
		current_heatmap <- "day_density";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask ref_grid{
			do compute_density_day;
			ask heatmap inside(self){ grid_value <- myself.day_density; }
		}
		do spread_value(spread_value_factor);
	}

	action heatmap2nightdensity{
		current_heatmap <- "night_density";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask ref_grid{
			do compute_density_night;
			ask heatmap inside(self){ grid_value <- myself.night_density; }
		}
		do spread_value(spread_value_factor);
	}

	action heatmap2knowledgedensity{
		current_heatmap <- "knowledge_density";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask ref_grid{
			do compute_density_knowledge;
			ask heatmap inside(self){ grid_value <- myself.knowledge_density; }
		}
		do spread_value(spread_value_factor);
	}

	action heatmap2interactiondensity{
		current_heatmap <- "interaction_density";
		show_heatmap <- true;
		ask ccu_heatmap{ grid_value <- 0.0; }
		ask ref_grid{
			do compute_density_interaction;
			ask heatmap inside(self){ grid_value <- myself.interaction_density; }
		}
		do spread_value(spread_value_factor);
	}

	action spread_value(int it){
		// Obtener la geometría del límite de estudio de forma segura
		geometry limit_geom <- empty(ccu_limit as list) ? world.shape : first(ccu_limit).shape;
		
		loop times: it {
			ask ccu_heatmap {
				list<heatmap> my_nb;
				heatmap tmp <- heatmap[grid_x+1, grid_y]; if tmp != nil { add tmp to: my_nb; }
				tmp <- heatmap[grid_x+1, grid_y+1]; if tmp != nil { add tmp to: my_nb; }
				tmp <- heatmap[grid_x, grid_y+1]; if tmp != nil { add tmp to: my_nb; }
				tmp <- heatmap[grid_x-1, grid_y+1]; if tmp != nil { add tmp to: my_nb; }
				tmp <- heatmap[grid_x-1, grid_y]; if tmp != nil { add tmp to: my_nb; }
				tmp <- heatmap[grid_x-1, grid_y-1]; if tmp != nil { add tmp to: my_nb; }
				tmp <- heatmap[grid_x, grid_y-1]; if tmp != nil { add tmp to: my_nb; }
				tmp <- heatmap[grid_x+1, grid_y-1]; if tmp != nil { add tmp to: my_nb; }
				
				grid_value <- grid_value * spread_factor + mean(my_nb where(not dead(each)) collect(each.grid_value)) * (1.0 - spread_factor);
			}
		}
		
		// Limpiar celdas fuera del polígono o con valores insignificantes
		ask heatmap {
			if (limit_geom != nil and not (limit_geom covers location)) or grid_value < 0.05 {
				grid_value <- 0.0;
			}
			if (heatmap_field != nil) {
				heatmap_field[self.location] <- self.grid_value;
			}
		}
	}
	// Variable para la lectura de comandos web
	file commands_file <- nil;

	// --- 1. REFLEX QUE LEE COMANDOS DESDE EL DASHBOARD WEB ---
	reflex process_web_commands when: every(10#cycles) {
		if (file_exists("../includes/data/commands.json")) {
			try {
				commands_file <- json_file("../includes/data/commands.json");
				if (commands_file != nil and commands_file.contents != nil) {
					map<string, unknown> cmd_data <- map<string, unknown>(commands_file.contents);
					
					if (cmd_data != nil and cmd_data contains_key "updated" and bool(cmd_data["updated"]) = true) {
						// A. Ajustar cantidad de vehículos en tiempo real
						if (cmd_data contains_key "vehicle_count" and cmd_data["vehicle_count"] != nil) {
							int target_vehicles <- int(cmd_data["vehicle_count"]);
							int current_vehicles <- length(vehicle);
							int diff <- target_vehicles - current_vehicles;
							
							if (diff > 0) {
								create vehicle number: diff { type <- "car"; }
								write "=== [CityScope] Creados " + string(diff) + " vehículos adicionales ===";
							} else if (diff < 0) {
								int nb_to_kill <- min([abs(diff), current_vehicles]);
								loop times: nb_to_kill {
									if (!empty(vehicle)) { ask one_of(vehicle) { do die; } }
								}
								write "=== [CityScope] Eliminados " + string(nb_to_kill) + " vehículos ===";
							}
						}
						
						// B. Cambiar capa activa de visualización
						string layer <- "emissions";
						if (cmd_data contains_key "active_layer" and cmd_data["active_layer"] != nil) {
							layer <- string(cmd_data["active_layer"]);
							if (layer = "emissions") { show_emissions <- true; show_heatmap <- false; }
							else if (layer = "population") { show_emissions <- false; do heatmap2populationdensity; }
							else if (layer = "day_div") { show_emissions <- false; do heatmap2daydiv; }
						}

						// C. Cambiar Escenario Urbano (S1 o S2)
						int sc_val <- 1;
						if (cmd_data contains_key "active_scenario" and cmd_data["active_scenario"] != nil) {
							sc_val <- int(cmd_data["active_scenario"]);
							if (sc_val = 1) {
								do activate_scenario1;
								write "=== [CityScope] Activado Escenario 1 (Base/Actual) ===";
							} else if (sc_val = 2) {
								do activate_scenario2;
								write "=== [CityScope] Activado Escenario 2 (Plan Maestro/Futuro) ===";
							}
						}
						
						// D. Guardar la respuesta directamente como string limpio (SIN CORCHETES [])
						string json_out <- '{"vehicle_count":' + string(length(vehicle)) + ',"active_layer":"' + layer + '","active_scenario":' + string(sc_val) + ',"updated":false}';
						save json_out to: "../includes/data/commands.json" format: "text" rewrite: true;
					}
				}
			} catch {
				// Captura silenciosa si el archivo se estaba escribiendo al mismo tiempo
			}
		}
	}
	// --- 2. EXPORTACIÓN DE INDICADORES Y MATRIZ DE EMISIONES ---
	// --- EXPORTACIÓN ROBUSTA DE INDICADORES Y EMISIONES ---
	reflex update_and_export_indicators when: allow_export_current_data or scenario_changed or (every(30#cycles) and allow_export_data) {
		if (time_2_save_data > 0) {
			time_2_save_data <- time_2_save_data - 1;
		} else {
			// A. Exportar CSV en 2 filas explícitas con salto de línea (\n)
			string header_s1 <- "dash_night_activities_diversity0,dash_interaction_diversity0,dash_knowledge_activities_diversity0,dash_energy_requirement0,dash_water_requirement0,dash_waste_generation0,dash_green_space_per_hab0,dash_km_ways_per_hab0,dash_public_transport_coverage0,dash_mean_facilities_proximity0,dash_mean_activities_density0,dash_hab_net_density0,dash_living_place_density0,dash_day_activities_diversity0";
			string row_s1 <- string(mean_diversity_night()) + "," + 
			                 string(mean_diversity_interaction()) + "," + 
			                 string(mean_diversity_knowledge()) + "," + 
			                 string(mean_energy_requirement()) + "," + 
			                 string(mean_water_requirement()) + "," + 
			                 string(mean_waste_generation()) + ",0.70," + 
			                 string(km_roads_per_person(1)) + "," + 
			                 string(mean_education_proximity()) + "," + 
			                 string(mean_culture_proximity()) + ",0.38," + 
			                 string(mean_population_density()) + "," + 
			                 string(mean_household_density()) + "," + 
			                 string(mean_diversity_day());

			save (header_s1 + "\n" + row_s1) to: "../includes/data/output_s1.csv" format: "csv" rewrite: true;

			// B. Construir JSON de Emisiones con velocidad saneada
			float safe_speed <- (vehicle = nil or empty(vehicle) or avg_speed = nil) ? 0.0 : float(avg_speed) * 3.6;

			list<string> json_cells <- [];
			ask vehicle {
				if (self != nil and self.location != nil) {
					add '{"x":' + string(self.location.x) + ',"y":' + string(self.location.y) + '}' to: json_cells;
				}
			}
			
			string points_str <- "";
			int total_pts <- length(json_cells);
			if (total_pts > 0) {
				loop i from: 0 to: total_pts - 1 {
					points_str <- points_str + json_cells[i] + (i < total_pts - 1 ? "," : "");
				}
			}
			
			string json_emissions <- to_json([
			    "vehicles_count":: length(vehicle),
			    "avg_speed":: (empty(vehicle) ? 0.0 : mean(vehicle collect each.speed) * 3.6),
			    "points":: (vehicle collect [
			        "lat":: CRS_transform(each.location, "EPSG:4326").location.y,
			        "lng":: CRS_transform(each.location, "EPSG:4326").location.x
			    ])
			]);
			
			// Guardar como type: "text" para evitar doble escapado de comillas
			save json_emissions to: "../includes/data/emissions_data.json" format: "json";
			
			allow_export_current_data <- false;
			scenario_changed <- false;
		}
	}
}

// ------------------ ESPECIES DE SIMULACION DE TRAFICO Y EMISIONES ------------------

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
	
	// Monitoreo de estancamiento e inmovilidad
	point last_location <- nil;
	int stuck_counter <- 0;
	int failed_target_attempts <- 0;
	intersection current_token_intersection <- nil;
	bool is_crossing <- false;
	intersection current_inter <- nil;
	
	init {
		min_gap <- 8.0;
		if (type = "car") {
			accel_rate <- 0.15;
			max_speed <- 50.0#km/#h;
			emission_rate <- 12.0;
		} else if (type = "moto") {
			accel_rate <- 0.3;
			max_speed <- 40.0#km/#h;
			emission_rate <- 6.0;
		} else if (type = "bus") {
			accel_rate <- 0.08;
			max_speed <- 30.0#km/#h;
			emission_rate <- 28.0;
		} else if (type = "bike") {
			accel_rate <- 0.05;
			max_speed <- 20.0#km/#h;
			emission_rate <- 0.0;
		} else {
			accel_rate <- 0.08;
			max_speed <- 25.0#km/#h;
			emission_rate <- 10.0;
		}
		
		// NOTA: Si tu especie de vías se llama 'road' en singular, usa 'road' en lugar de 'roads'
		list<roads> valid_roads <- roads_network.edges collect roads(each);
		if (!empty(valid_roads)) {
			location <- any_location_in(one_of(valid_roads));
		}
		do select_new_target;
	}
	
	// Selección de destino con validación estricta de ruta
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

	// Reubicación de emergencia para vehículos atrapados
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

		// Obtener el tramo de calle actual sobre el que circula el vehículo
		roads current_rd <- current_edge != nil ? roads(current_edge) : nil;
		int num_lanes <- current_rd != nil ? current_rd.lanes : 1;

		// 1. Detección adaptativa de vehículo frontal según el número de carriles
		// En calles de más de 1 carril se reduce el cono de visión (de 40° a 20°) para no frenar por autos en carriles paralelos
		float angle_threshold <- (num_lanes > 1) ? 20.0 : 40.0;
		
		list<vehicle> vehicles_ahead <- vehicle at_distance 20.0 select (
			each != self and 
			abs(self.heading - (self.location direction_to each.location)) < angle_threshold and
			(abs(self.heading - each.heading) < 50.0 or abs(self.heading - each.heading) > 310.0)
		);
		vehicle vehicle_ahead <- vehicles_ahead closest_to self;
		
		// 2. Detección de semáforo en rojo
		list<intersection> traffic_lights_ahead <- intersection at_distance 20.0 select (
			each.is_traffic_light and
			abs(self.heading - (self.location direction_to each.location)) < 35.0 and
			not each.is_green
		);
		intersection traffic_light_ahead <- traffic_lights_ahead closest_to self;
		
		// 3. Detección de Intersección Próxima sin semáforo
		intersection next_inter <- intersection at_distance 20.0 select (
			not each.is_traffic_light and 
			abs(self.heading - (self.location direction_to each.location)) < 60.0
		) closest_to self;

		// Ajustar velocidad máxima según el tipo de vehículo y la capacidad de la vía
		float max_speed_allowed <- max_speed;
		if (num_lanes >= 3) {
			max_speed_allowed <- max_speed * 1.15; // Vías rápidas/troncales
		} else if (num_lanes = 1) {
			max_speed_allowed <- min(max_speed, 35.0#km/#h); // Calles residenciales / 1 carril
		}
		
		// 4. Frenado por vehículo adelante
		if (vehicle_ahead != nil) {
			float dist_v <- self distance_to vehicle_ahead;
			float max_advance_v <- max(0.0, dist_v - min_gap);
			float speed_limit_v <- max_advance_v * 3.6 #km/#h;
			max_speed_allowed <- min(max_speed_allowed, speed_limit_v);
		}
		
		// 5. Frenado por semáforo en rojo
		if (traffic_light_ahead != nil) {
			float dist_tl <- self distance_to traffic_light_ahead;
			float max_advance_tl <- max(0.0, dist_tl - 3.0);
			float speed_limit_tl <- max_advance_tl * 3.6 #km/#h;
			max_speed_allowed <- min(max_speed_allowed, speed_limit_tl);
		}
		
		// 6. Control de Intersección / Ceda el Paso
		if (next_inter != nil) {
			float my_dist <- self distance_to next_inter;

			if (my_dist <= 4.0) {
				is_crossing <- true;
			}

			if (not is_crossing and my_dist <= 15.0 and my_dist > 4.0) {
				list<vehicle> rivals <- vehicle at_distance 15.0 select (
					each != self and
					(each distance_to next_inter) < 10.0
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
		
		// 7. DESBLOQUEO DE EMERGENCIA
		if (stuck_counter > 30) {
			max_speed_allowed <- max(8.0 #km/#h, max_speed_allowed);
			is_crossing <- true;
		}
		
		// 8. Ajuste dinámico de velocidad
		if (max_speed_allowed <= 0.1 #km/#h) {
			current_speed <- 0.0 #km/#h;
		} else if (current_speed > max_speed_allowed) {
			current_speed <- max_speed_allowed;
		} else {
			current_speed <- min(max_speed_allowed, current_speed + accel_rate);
		}
		
		// 9. Desplazamiento y verificación de ruta
		if (current_speed > 0.0 and tgt != nil) {
			path path_followed <- goto(target: tgt, on: roads_network, return_path: true, speed: current_speed);
			
			if (path_followed = nil or length(path_followed.edges) = 0) {
				do select_new_target;
			} else if (emission_rate > 0 and emissions_field != nil) {
				emissions_field[self.location] <- emissions_field[self.location] + emission_rate;
				total_emissions_generated <- total_emissions_generated + emission_rate;
			}
		}
		
		// 10. Control de inmovilidad / re-enrutamiento
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
		if (type = "car") { v_color <- (current_speed <= 2.0#km/#h) ? #red : #blue; }
		else if (type = "bus") { v_color <- #purple; }
		else if (type = "moto") { v_color <- #orange; }
		else if (type = "bike") { v_color <- #green; }
		
		draw triangle(10) color: v_color border: #black rotate: heading + 90;
	}
}


species intersection {
	int counter <- 0;
	bool is_traffic_light <- false;
	bool is_green <- true;
	list<roads> my_roads;
	int green_light_index <- 0;
	
	// --- CONTROL "UNO Y UNO" CON TIMEOUT ---
	list<vehicle> waiting_queue <- [];
	vehicle active_vehicle <- nil;
	
	action setup_traffic_light {
		my_roads <- remove_duplicates(list<roads>(roads_network in_edges_of self) + list<roads>(roads_network out_edges_of self));   
		if (empty(my_roads)) {
			my_roads <- roads at_distance(5.0);
		}     
	}
	
	reflex main_behavior when: is_traffic_light {
		counter <- counter + 1;
		if(counter > green_time){
			counter <- 0;
			is_green <- !is_green;
			if (not empty(my_roads)) {
				green_light_index <- mod(green_light_index + 1, length(my_roads));
			}
		}
	}
	
	// Gestión de turnos con temporizador antilock
	reflex manage_uno_y_uno when: not is_traffic_light {
		// 1. Depurar cola de vehículos no válidos o distantes
		waiting_queue <- waiting_queue where (
			not dead(each) and (each distance_to self) <= 25.0
		);
		
		// 2. Liberar intersección si el vehículo activo ya cruzó o lleva demasiado tiempo estancado en el nodo
		if (active_vehicle != nil) {
			if (dead(active_vehicle) or (active_vehicle distance_to self) > 12.0 or active_vehicle.stuck_counter > 8) {
				active_vehicle <- nil;
			}
		}
		
		// 3. Asignar paso al siguiente auto en cola
		if (active_vehicle = nil and not empty(waiting_queue)) {
			active_vehicle <- first(waiting_queue);
			waiting_queue <- waiting_queue - active_vehicle;
		}
	}
	// --- LÓGICA DE NEGOCIACIÓN DE CRUCE ---
    vehicle active_token_holder <- nil;
    list<vehicle> intersection_queue <- [];

    // Un vehículo solicita permiso para cruzar
    action request_token (vehicle v) {
        if (active_token_holder = nil or active_token_holder = v) {
            active_token_holder <- v;
        } else if (!(intersection_queue contains v)) {
            add v to: intersection_queue;
        }
    }

    // El vehículo libera la intersección al salir de ella
    action release_token (vehicle v) {
        if (active_token_holder = v) {
            if (length(intersection_queue) > 0) {
                active_token_holder <- first(intersection_queue);
                remove active_token_holder from: intersection_queue;
            } else {
                active_token_holder <- nil;
            }
        }
    }
	aspect default {
		if is_traffic_light {
			draw circle(8) color: is_green ? #green : #red border: #white;
		}
	}
}

// ------------------ OTRAS ESPECIES Y COMPONENTES ------------------

grid heatmap width:world.shape.width/15 height:world.shape.height/15{
	rgb my_color <- rgb(0,0,0,0);
	bool valid <- true;
	aspect default{
		draw shape wireframe:true border:#red;
	}
	aspect heat{
		if show_heatmap{
			my_color <- update_color_new(current_heatmap);
			float intensity <- grid_value=0 ? 0.1 : grid_value;
			intensity <- grid_value>0.65 ? 0.65 : grid_value;
			draw shape color:rgb(my_color, grid_value=1 ? 1.2 : intensity);
		}	
	}
	
	rgb update_color_new(string current_hm){
		rgb result;
		string my_class <- "default";
		loop i over:heatmap_names.keys{
			if current_hm in heatmap_names[i]{ my_class <- i; }
		}
		switch(my_class){
			match "population/housing"{ result <- rgb(242-int(grid_value*127), 226-int(grid_value*224), 5-int(grid_value*3)); }
			match "facilities"{ result <- rgb(234-int(grid_value*229), 236-int(grid_value*229), 255-int(grid_value*100)); }
			match "activities_density"{ result <- rgb(255-int(grid_value*23), 232-int(grid_value*151), 249-int(grid_value*140)); }
			match "activities_diversity"{ result <- rgb(255-(255*grid_value), 40+(190*grid_value), 0); }
			match "default"{ result <- rgb(214-int(grid_value*160), 217-int(grid_value*160), 193-int(grid_value*168)); }
		}
		return result;
	}
}

species green_area{ float surface_area; }

species project{
	string id;
	int from_scenario;
	string block_id;
	string project_name;
	string letter;
	int population;
	string use_type;
	int nb_ec_units;
	int UBS;
	float green_areas_m2;
	float building_m2;
	int viv_eco;
	int viv_med;
	int viv_res;
	int green_area;
	list<economic_unit> my_new_activities;
	list<people> new_people;
	
	action create_new_activities{
		my_new_activities <- [];
		list<string> allowed_activities_for_me <- allowed_activities[use_type];
		loop i over: sample(allowed_activities_for_me, nb_ec_units, true){
			create economic_unit with:[from_scenario::from_scenario, sub_id::i] returns:new_unit;
			economic_unit new_unit_ <- first(new_unit);
			blocks my_block <- first(blocks where(each.id=block_id));
			ask new_unit_{ location <- any_location_in (my_block); }
			add first(new_unit) to:my_new_activities;
		}
		// Agregar las nuevas actividades a la lista global segura
		active_economic_units <- active_economic_units + my_new_activities;
	}
	
	action activate{
		do create_new_activities;
		blocks my_block <- first(blocks where(each.id=block_id and from_scenario=self.from_scenario));
		add my_block to:current_active_blocks;
		ask my_block{
			ask my_households{ current_active_households <- current_active_households + [self]; }
			nb_people <- myself.population;
			nb_households <- nb_households + viv_eco + viv_med + viv_res;
			create people number:self.nb_people/5 returns:arriving_people with:[
				target_block::one_of(current_active_blocks-self),
				from_scenario::myself.from_scenario
			]{
				home_block <- myself;
				home_point <- any_location_in(home_block);
				location <- home_point;
				mobility_type <- select_mobility_mode();
				do compute_mobility_accessibility();
			}
			myself.new_people <- arriving_people;
		}
	}
	action deactivate{
		// Remover las actividades de la lista global ANTES de destruirlas en la memoria
		active_economic_units <- active_economic_units - my_new_activities;
		ask my_new_activities{ do die; }
		my_new_activities <- [];
		
		ask new_people { to_be_killed <- true; }
		list<blocks> blocks_tbr <- current_active_blocks where(each.id=block_id);
		ask blocks_tbr{
			remove self from:current_active_blocks;
			ask my_households{ current_active_households <- current_active_households - [self]; }
		}
	}
	aspect default{
		draw shape wireframe:true border:#white;
	}
}

species economic_unit{
	int from_scenario;
	string activity_id;
	string sub_id;
	aspect default{
		draw square(1) color:rgb(186, 58, 197, 255) border:rgb(186, 58, 197, 255);
	}
}

species intervention_area{
	int active_scenario;
	string blocksS1_str;
	string blocksS2_str;
	string blocksS3_str;
	list<list<blocks>> blocks_by_scenario <- [[],[],[]];
	string area_name;
	string id;
	string associated_projects_str;
	list<project> associated_projects;
	
	action activate_scenario(int new_scenario){
		if active_scenario != new_scenario{
			try{
				ask associated_projects where(each.from_scenario=active_scenario){ do deactivate; }
				ask associated_projects where(each.from_scenario=new_scenario){ do activate; }
			}
			scenario_changed <- true;
			time_2_save_data <- max([3, delay_before_export_data]); // Garantiza mínimo 3 ciclos de asentamiento
			time_2_update_heatmap <- delay_before_update_heatmap;
			allow_export_current_data <- true;
			active_scenario <- new_scenario;
		}
	}
	aspect default{
		if(show_information){
			draw shape wireframe:true border:#yellow;
			draw area_name+string(active_scenario) color:#white font:font("Helvetica", 30 , #bold) at:{location.x,location.y,20};	
		}
	}
}

species entry_point{ float rate <- 0.0; }
species event_location{ int capacity; int current_people <- 0; }

species transport_station{
	string type;
	string subtype;
	image_file my_icon <- image_file("../includes/img/bus.png");
	aspect default{ draw my_icon size:40; }
}

species cycling_way{ aspect default{ draw shape color:#green width:2.0; } }

species base_grid{
	int from_scenario;
	float mobility_access;
	float night_diversity;
	float day_diversity;
	float knowledge_diversity;
	float interaction_diversity;
	float overall_activities_diversity;
	float day_density;
	float night_density;
	float knowledge_density;
	float interaction_density;
	float social_interactions;
	
	int people_living_inside;
	int households_inside;
	list<economic_unit> activities_inside;
	list<economic_unit> my_tmp_activities;
	
	action compute_diversity_day{
		activities_inside <- economic_unit inside self;
		map<string,int> class_counter;
		loop i over:day_activities{ add i::0 to:class_counter; }
		my_tmp_activities <- economic_unit inside(self) where(each.sub_id in day_activities);
		if not empty(my_tmp_activities){
			loop act over:my_tmp_activities{ class_counter[act.sub_id] <- class_counter[act.sub_id] + 1; }
		}
		int total_activities <- sum(class_counter.values);
		day_diversity <- total_activities=0 ? 0.0 : -1*sum(class_counter.values collect((each/total_activities)*(each<=0?0:ln(each/total_activities))));
	}
	
	action compute_diversity_night{
		activities_inside <- economic_unit inside self;
		map<string,int> class_counter;
		loop i over:night_activities{ add i::0 to:class_counter; }
		my_tmp_activities <- economic_unit inside(self) where(each.sub_id in night_activities);
		if not empty(my_tmp_activities){
			loop act over:my_tmp_activities{ class_counter[act.sub_id] <- class_counter[act.sub_id] + 1; }
		}
		int total_activities <- sum(class_counter.values);
		night_diversity <- total_activities=0 ? 0.0 : -1*sum(class_counter.values collect((each/total_activities)*(each<=0?0:ln(each/total_activities))));
	}
	
	action compute_diversity_knowledge{
		activities_inside <- economic_unit inside self;
		map<string,int> class_counter;
		loop i over:knowledge_activities{ add i::0 to:class_counter; }
		my_tmp_activities <- economic_unit inside(self) where(each.sub_id in knowledge_activities);
		if not empty(my_tmp_activities){
			loop act over:my_tmp_activities{ class_counter[act.sub_id] <- class_counter[act.sub_id] + 1; }
		}
		int total_activities <- sum(class_counter.values);
		knowledge_diversity <- total_activities=0 ? 0.0 : -1*sum(class_counter.values collect((each/total_activities)*(each<=0?0:ln(each/total_activities))));
	}
	
	action compute_diversity_interaction{
		activities_inside <- economic_unit inside self;
		map<string,int> class_counter;
		loop i over:interaction_places{ add i::0 to:class_counter; }
		my_tmp_activities <- economic_unit inside(self) where(each.sub_id in interaction_places);
		if not empty(my_tmp_activities){
			loop act over:my_tmp_activities{ class_counter[act.sub_id] <- class_counter[act.sub_id] + 1; }
		}
		int total_activities <- sum(class_counter.values);
		interaction_diversity <- total_activities=0 ? 0.0 : -1*sum(class_counter.values collect((each/total_activities)*(each<=0?0:ln(each/total_activities))));
	}
	
	action compute_density_day{
		activities_inside <- economic_unit inside self;
		my_tmp_activities <- economic_unit inside(self) where(each.sub_id in day_activities);
		day_density <- length(economic_unit inside (self))>0 ? length(my_tmp_activities)/length(economic_unit inside (self)) : 0;
	}
	action compute_density_night{
		activities_inside <- economic_unit inside self;
		my_tmp_activities <- economic_unit inside(self) where(each.sub_id in night_activities);
		night_density <- length(economic_unit inside (self))>0 ? length(my_tmp_activities)/length(economic_unit inside (self)) : 0;
	}
	action compute_density_knowledge{
		activities_inside <- economic_unit inside self;
		my_tmp_activities <- economic_unit inside(self) where(each.sub_id in knowledge_activities);
		knowledge_density <- length(economic_unit inside (self))>0 ? length(my_tmp_activities)/length(economic_unit inside (self)) : 0;
	}
	action compute_density_interaction{
		activities_inside <- economic_unit inside self;
		my_tmp_activities <- economic_unit inside(self) where(each.sub_id in interaction_places);
		interaction_density <- length(economic_unit inside (self))>0 ? length(my_tmp_activities)/length(economic_unit inside (self)) : 0;
	}
	action compute_population_living_inside{ people_living_inside <- length(people where(self covers each.home_point)); }
	action compute_household_inside{ households_inside <- length(current_active_households where(self covers each)); }
}

species equipment{
	bool valid <- false;
	int from_scenario;
	string type;
	string subtype;
	
	aspect by_type{
		if type="Cultura"{ color <- #green; }
		else if type="Salud"{ color<- #blue; }
		else if type = "Educación"{ color<-#cyan; }
		draw square(20) color: color;
	}
}

species ccu_limit{ aspect default{ draw shape wireframe:true border:#red; } }

species blocks{
	string id;
	int from_scenario;
	int nb_people;
	int nb_households;
	list<household> my_households;
	float block_area;
	bool valid <- false;
	string viv_type;
	int viv_eco;
	int viv_med;
	int viv_res;
	
	float mobility_access;
	float education_proximity;
	float culture_proximity;
	float health_proximity;
	float sports_proximity;
	float energy_requirement;
	float waste_generation;
	float population_density;
	float water_requirement;
	
	int nb_different_cultural_equipment <- 0;
	bool ind_proximity_2_cultural_equipment <- false;
	int nb_different_education_equipment <- 0;
	bool ind_proximity_2_education_equipment <- false;
	int nb_different_health_equipment <- 0;
	bool ind_proximity_2_health_equipment <- false;
	int nb_different_sports_equipment <- 0;
	bool ind_proximity_2_sports_equipment <- false;
	
	action compute_energy_requirement{
		if from_scenario = 1{
			float req_by_block <- nb_people*energy_requirement_map[viv_type];		
			energy_requirement <- nb_people>0 ? req_by_block/nb_people : 0;	
		} else {
			float req_by_block <- (viv_eco*energy_requirement_map["Económica"])+(viv_med*energy_requirement_map["Media"]+(viv_res*energy_requirement_map["Residencial"]));
			energy_requirement <- nb_people>0 ? req_by_block/nb_people : 0;
		}
	}
	action compute_waste_generation{
		if from_scenario = 1{
			float waste_by_block <- nb_people*waste_generation_map[viv_type];		
			waste_generation <- nb_people>0 ? waste_by_block/nb_people : 0;	
		} else {
			float waste_by_block <- (viv_eco*waste_generation_map["Económica"])+(viv_med*waste_generation_map["Media"]+(viv_res*waste_generation_map["Residencial"]));
			waste_generation <- nb_people>0 ? waste_by_block/nb_people : 0;
		}
	}
	action compute_water_requirement{
		if from_scenario = 1{
			float aprox_viv <- nb_people/3.6;
			float req_by_block <- aprox_viv*water_requirement_map[viv_type];		
			water_requirement <- nb_people>0 ? req_by_block/nb_people : 0;	
		} else {
			float req_by_block <- (viv_eco*water_requirement_map["Económica"])+(viv_med*water_requirement_map["Media"]+(viv_res*water_requirement_map["Residencial"]));
			water_requirement <- nb_people>0 ? req_by_block/nb_people : 0;
		}
	}
	action compute_population_density{
		float ha <- block_area * 0.0001;
		population_density <- ha>0 ? nb_people / ha : 0;
	}
	
	aspect default{
		if self in current_active_blocks and not show_satellite{
			draw shape color:rgb(100,100,100,0.2)  width:5.0;
		}
	}
}

species household{
	int from_scenario;
	aspect default{
		if self in current_active_households{
			draw triangle(5) color:from_scenario=1?#green:rgb(185, 19, 172, 255) wireframe:true;
		}
	}
}

species roads{
	int lanes <- 1;
	aspect default{ draw shape color:#gray; }
}

species aux_roads{
	int from_scenario;
	float length;
}

species satellite_background{
	image_file satellite;
	init{ satellite <- image_file("../includes/img/satellite.png"); }
	aspect default{
		if show_satellite{ draw shape border:#red texture:satellite; }
	}
}

species people skills:[moving]{
	float mobility_accessibility <- 0.0;
	bool ind_public_transport_coverage			<- false;
	bool ind_cultural_equipment_proximity 		<- false;
	bool ind_education_equipment_proximity 	<- false;
	bool ind_health_equipment_proximity			<- false;
	bool ind_sports_equipment_proximity 		<- false;
	
	int from_scenario;
	bool to_be_killed <- false;
	
	blocks home_block;
	point home_point;
	blocks target_block;
	point target_point;
	path roads_path;
	list<point> my_path;
	int point_counter <- 0;
	string current_destinity <- "work" among:["home","work"];
	map<date,string> agenda_day;
	string mobility_type;
	bool currently_moving <- false;

	action compute_mobility_accessibility{
		int transport_accessibilty_count <- 0;
		list<float> distances <- [];

		try{
			transport_station closest_station <- transport_station where(each.type="bus") closest_to self;
			add closest_station distance_to self to:distances;
			closest_station <- transport_station where(each.type="massive" and each.subtype="BRT (Bus Rapid Transit)") closest_to self;
			add closest_station distance_to self to:distances;
			closest_station <- transport_station where(each.type="massive" and each.subtype="Tren Eléctrico") closest_to self;
			add closest_station distance_to self to:distances;
			cycling_way closest_cycling_way <- cycling_way closest_to self;
			add closest_station distance_to self to:distances;
			
			if distances[0] < 300{ transport_accessibilty_count <- transport_accessibilty_count + 1; } 
			if distances[1] < 500{ transport_accessibilty_count <- transport_accessibilty_count + 1; }
			if distances[2] < 800{ transport_accessibilty_count <- transport_accessibilty_count + 1; }
			if distances[3] < 300{ transport_accessibilty_count <- transport_accessibilty_count + 1; }
			mobility_accessibility <- transport_accessibilty_count /4;
			ind_public_transport_coverage <- transport_accessibilty_count >=3;
		}
	}

	string select_mobility_mode{
		float sum <- 0.0;
		float selection <- rnd(100)/100;
		loop mode over:student_mobility_percentages.keys{
			if selection < student_mobility_percentages[mode] + sum{
				return mode;
			}
			sum <- sum + student_mobility_percentages[mode];
		}
		return one_of(student_mobility_percentages.keys);
	}

	reflex update_agenda when: (every(#day)) or empty(agenda_day){
		agenda_day <- [];
		int activity_time <- rnd(2,12);
		int init_hour <- rnd(6,12);
		int init_minute <- rnd(0,59);
		date activity_date <- date(current_date.year,current_date.month,current_date.day,init_hour,init_minute,0);
		agenda_day <+ (activity_date::"activity");
		activity_date <- activity_date + activity_time#hours + rnd(0,59)#minutes;
		agenda_day <+ (activity_date::"home");
	}
	
	reflex update_activity when:not dead(self) and not empty(agenda_day){
		try{
			if after(agenda_day.keys[0]) {
				string current_activity <- agenda_day.values[0];
				target_point <- current_activity = "activity" ? any_location_in(target_block) : any_location_in(home_block);
				agenda_day >> first(agenda_day);
				currently_moving <- true;
			}
		}
	}
	
	action moving{
		if location != target_point and currently_moving{
			do goto target:target_point on:roads_network speed:0.1;
		} else if currently_moving and location=target_point{
			currently_moving <- false;
		}
	}
	
	reflex kill_agent when: to_be_killed{ do die; }
	
	aspect default{
		if(show_people){
			draw circle(4) border:#yellow color:rgb((1-mobility_accessibility)*255, mobility_accessibility*255, 0, 1.0);
		}
	}
}

// -------------------------- DEFINICION DEL EXPERIMENTO --------------------------------------

experiment CCU_1_1000 type:gui autorun:true{
	parameter "Enable MQTT" var:enable_mqtt category:"Functionality"; 
	parameter "Satellite" var:show_satellite category:"Visualization";
	parameter "People" var:show_people category:"Visualization";
	parameter "Information" var:show_information category:"Visualization";
	parameter "Mostrar Emisiones" var:show_emissions category:"Visualization";
	parameter "Green time" var:green_time <- 50 min:5 max:240 category:"Traffic";
	parameter "Red time" var:red_time <- 50 min:5 max:240 category:"Traffic";
	
	output{
		layout #split;
		display gui type:opengl background:#black axes:false fullscreen:0{
			camera 'default' location: {1007.3931,681.2155,1270.1296} target: {1009.0202,671.3018,0.0};
	
			overlay size:{0,0} position:{0.1,0.1} transparency:0.5{
				draw "abcdefghiíjklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.:0123456789" at: {0#px,0#px} color:rgb(0,0,0,0) font: font("Arial", 55, #bold);
				int the_day <- current_date.day-starting_date.day +1;
				string minute <- current_date.minute<10 ? (string(0)+current_date.minute) : current_date.minute;
				draw " "+current_date.hour+":"+ minute at:{30#px,30#px} color:#white font: font("Arial", 55, #bold);
			}
			
			species satellite_background aspect:default refresh:true;
			//species ccu_limit aspect:default refresh:true;
			species blocks aspect:default;
			//species roads aspect:default;
			species intersection aspect:default;
			species vehicle aspect:default;
			species people aspect:default;
			species intervention_area aspect:default;
			
			mesh heatmap_field 
				scale: 8.0 
				triangulation: true 
				transparency: 0.30 
				smooth: 2 
				color: heatmap_palette 
				visible: show_heatmap and not show_emissions;
				
			mesh emissions_field 
				scale: 7.0 
				triangulation: true 
				transparency: 0.40 
				smooth: 3 
				color: emissions_palette 
				visible: show_emissions;
			
			event "h" { 
				ask simulation { 
					show_heatmap <- !show_heatmap; 
					show_emissions <- false;
					if (show_heatmap and current_heatmap = "") {
						do heatmap2populationdensity;
					}
				} 
			}
			event "E" { ask simulation { do toggle_emissions_display; } }
			event "e" { ask simulation { do toggle_emissions_display; } }
			
			event "s" { ask simulation { show_emissions <- false; do heatmap2health; } }
			event "c" { ask simulation { show_emissions <- false; do heatmap2culture; } }
			event "x" { ask simulation { show_emissions <- false; do heatmap2sports; } }
			event "d" { ask simulation { show_emissions <- false; do heatmap2daydiv; } }
			event "n" { ask simulation { show_emissions <- false; do heatmap2nightdiv; } }
			event "w" { ask simulation { show_emissions <- false; do heatmap2knowdiv; } }
			
			event "u" { ask simulation { show_emissions <- false; do heatmap2daydensity; } }
			event "i" { ask simulation { show_emissions <- false; do heatmap2nightdensity; } }
			event "o" { ask simulation { show_emissions <- false; do heatmap2knowledgedensity; } }
			event "p" { ask simulation { show_emissions <- false; do heatmap2interactiondensity; } }
			event "l" { ask simulation { show_emissions <- false; do heatmap2populationdensity; } }
			event "L" { ask simulation { show_emissions <- false; do heatmap2householddensity; } }
			
			event "m" { ask simulation { show_emissions <- false; do heatmap2mobility; } }
			event "q" { ask simulation { do show_satellite_action; } }
			event "t" { ask simulation { do activate_scenario1; } }
			event "y" { ask simulation { do activate_scenario2; } }
			
			event "A" { ask simulation { do change_scenario_A; } }
			event "B" { ask simulation { do change_scenario_B; } }
			event "F" { ask simulation { do change_scenario_K; } }
			event "I" { ask simulation { do change_scenario_I; } }
		}
		
		/*display "Monitoreo de Trafico" type: 2d {
			chart "Metricas de Movilidad Vehicular" type: series {
				data "Velocidad Promedio (km/h)" color: #green value: avg_speed * 3.6;
				data "Tiempo Perdido en Embotellamiento (s)" color: #red value: avg_wasted_time;
			}
		}*/
	}
}