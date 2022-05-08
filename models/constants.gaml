/**
* Name: constants
*  
* Author: Gamaliel Palomo
* Tags: 
*/


model constants

global{
	string main_shp_path <- "../includes/shp/";
		
	
	string denue_filename <- "../includes/shp/denue_2021a.shp";
	string entry_points_filename <- "../includes/shp/entry_points.shp";
	string dcu_limits_filename <- "../includes/shp/environment/scenario_limits.shp";
	string inegi_blocks_filename <- "../includes/shp/dcu_manzanas_inegi_2020.shp";
	string dcu_transport_filename <- "../includes/shp/paradas_transporte_publico_dcu.shp";
	string dcu_massive_transport_filename <- "../includes/shp/estaciones_transporte_masivo_dcu.shp";
	string dcu_cycling_way_filename <- "../includes/shp/environment/ciclovias_dcu.shp";
	string satellite_file <- "../includes/img/ccu_satellite.png";
	string intervention_areas_filename  <- "environment/intervention_areas.shp";
	
	
	//map<string,float> mobility_speed <- ["pedestrian"::1.4,"bicycle"::3.0,"bus"::4.1,"car"::5.0];
	map<string,rgb> use_type_color <- ["Espacios verdes abiertos y recreativos"::#seagreen,
																	"Alojamiento temporal"::#yellow,
																	"Habitacional"::#yellow,
																	"Habitacional, Servicios a la industria y al comercio"::#yellow,
																	"Comercial y de servicios"::rgb (228, 58, 63,255),
																	"Comercial"::rgb (228, 58, 63,255),
																	"Servicios"::rgb (228, 58, 63,255),
																	"Mixto"::rgb (159, 0, 0,255),
																	"Industrial"::#slateblue,
																	"Servicios a la industria y al comercio"::#slateblue,
																	"Equipamiento"::#dodgerblue,
																	"Recreación y descanso"::#limegreen,
																	"Instalaciones especiales e infraestructura"::#gray,
																	"Vialidad"::#gray
																	];
		map<string,rgb> use_type_color_zonification <- ["Espacio verde"::#seagreen,
																	"Alojamiento temporal"::rgb (255, 0, 255,255),
																	"Habitacional"::#yellow,
																	"Habitacional, Servicios a la industria y al comercio"::#yellow,
																	"Comercial y de servicios"::rgb (228, 58, 63,255),
																	"Comercial"::rgb (228, 58, 63,255),
																	"Servicios"::rgb (228, 58, 63,255),
																	"Mixto"::rgb (159, 0, 0,255),
																	"Comercial"::#slateblue,
																	"Industrial"::#slateblue,
																	"Equipamiento"::#dodgerblue,
																	"Recreación y descanso"::#limegreen,
																	"Instalaciones especiales e infraestructura"::#gray,
																	"Vialidad"::#gray];
	
	list denue_activites <- [
		"611122",
		"611121",
		"611312",
		"611311"
	];
	list universities <- ["611311","611312"];
	//Students mobility data
	map<string,float> student_mobility_percentages<-[
		"Caminando"::0.4008,
		"Bicicleta"::0.0162,
		"Metro, tren ligero o tren suburbano"::0.0024,
		"Trolebus"::0.0,
		"Metrobús"::0.0028,
		"Camión, autobús, combi o colectivo"::0.2331,
		"Transporte escolar"::0.0334,
		"Taxi convencional"::0.0007,
		"Taxi de aplicación"::0.0017,
		"Motocicleta"::0.0116,
		"Automóvil propio"::0.2953,
		"Otro"::0.002
	];
	map<string,float> worker_mobility_percentages<-[
		"Caminando"::0.13001,
		"Bicicleta"::0.0424,
		"Metro, tren ligero o tren suburbano"::0.0021,
		"Trolebus"::0.0,
		"Metrobús"::0.0039,
		"Camión, autobús, combi o colectivo"::0.3527,
		"Transporte escolar"::0.0355,
		"Taxi convencional"::0.0028,
		"Taxi de aplicación"::0.0038,
		"Motocicleta"::0.034,
		"Automóvil propio"::0.3826,
		"Otro"::0.00101
	];
	map<string,rgb> mobility_colors<-[
		"Caminando"::#yellow,
		"Bicicleta"::#green,
		"Metro, tren ligero o tren suburbano"::#slateblue,
		"Trolebus"::#mediumorchid,
		"Metrobús"::#blue,
		"Camión, autobús, combi o colectivo"::rgb (188, 131, 44,255),
		"Transporte escolar"::rgb (239, 95, 236,255),
		"Transporte de personal"::rgb (239, 95, 236,255),
		"Taxi convencional"::rgb (51, 172, 154,255),
		"Taxi de aplicación"::#cornflowerblue,
		"Motocicleta"::rgb (241, 176, 160,255),
		"Automóvil propio"::#red,
		"Otro"::#white
	];
	map<string,float> mobility_speed<-[
		"Caminando"::4.5,
		"Bicicleta"::12.5,
		"Metro, tren ligero o tren suburbano"::9.72222,
		"Trolebus"::7.77778,
		"Metrobús"::7.77778,
		"Camión, autobús, combi o colectivo"::17.4,
		"Transporte escolar"::8.4,
		"Transporte de personal"::8.4,
		"Taxi convencional"::10.9,
		"Taxi de aplicación"::10.9,
		"Motocicleta"::32.5,
		"Automóvil propio"::16.3,
		"Otro"::5.0
	];
	
	
	float students_percentage <- 0.28;
	float workers_percentage <- 0.45;
	
	
	
	//Edge values
	
	float max_diversity <- 6.0;
	float max_transport_accessibility <- 1.0;
	float max_hab_emp_ratio <- 20.0;
	float max_density <- 20.0;
	int max_schools_near <- 4;
	int max_hospitals_near <-4;
	int max_culture_near <- 10;
	
	int min_culture_equipment 		<- 3;
	int min_education_equipment 	<- 4;
	int min_health_equipment 		<- 3;
	int min_sports_equipment 		<- 1;
	
	float distance2health 		<- 200#m;
	float distance2culture 		<- 200#m;
	float distance2education 	<- 200#m;
	
	
	//New version
	
	int spread_value <- 10;
	float spread_factor <- 0.2;
	map<string,int> education_distances <- ["Preescolar"::500,"Primaria"::750,"Secundaria"::1000,"Bachillerato"::5000,"Licenciatura"::10000];
	map<string,int> culture_distances <- ["Auditorio Estatal"::10000,"Auditorio Municipal"::2340,"Biblioteca Municipal"::1500,"Casa de la Cultura"::10000,"Escuela Integral de Artes"::10000,"Museo Local"::10000,"Teatro"::10000,"Biblioteca pública estatal"::10000];
	map<string,int> health_distances <- ["Centro de Sallud Urbano (SSA)"::1000,"Clínica Hospitall"::10000,"Consultorio Privadol"::1000,"Hospital Privado"::10000,"Hospital General"::10000,"Hospital General (SSA)l"::10000,"Laboratorio"::10000,"Unidad de Medicina Familiar"::5000,"Unidad de Medicina Familiar (IMSS)"::5000];
	map<string,int> sports_distances <- ["Equipamiento deportivo"::1000];
	
	
	//Variables related to events that happen within the polygon
	
}