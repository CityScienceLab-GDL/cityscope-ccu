/**
* Name: Pedestrian_Network_Generator
* Description: Script de preprocesamiento para derivar un grafo peatonal continuo
*              a partir de polígonos de manzanas, avenidas y obstáculos, y exportarlo a .shp
*/

model Pedestrian_Network_Generator

global {
    // 1. Cargar Shapefiles de entrada
    file blocks_shp <- file("../includes/shp/scenario1/blocks.shp");
    file roads_shp <- file("../includes/shp/scenario1/roads_clean.shp");
    file parking_shp <- file("../includes/shp/events/parking.shp");
    file obstacles_shp <- file("../includes/shp/events/obstacles.shp");

    geometry shape <- envelope(blocks_shp);

    init {
        write "=== INICIANDO GENERACIÓN DE RED PEATONAL ===";

        // Instanciar objetos espaciales
        create block_geom from: blocks_shp;
        create road_geom from: roads_shp;
        create parking_geom from: parking_shp;
        create obstacle_geom from: obstacles_shp;

        // 2. Extracción de Banquetas a partir del perímetro de manzanas y obstáculos
        list<geometry> sidewalk_lines <- [];
        
        ask block_geom {
            // Se toma el contorno exterior de la manzana y se expande ligeramente (0.5m) para simular la banqueta
            geometry sidewalk_poly <- shape buffer (0.5 #m);
            sidewalk_lines <- sidewalk_lines + (sidewalk_poly.contour.geometries);
        }

        ask obstacle_geom {
            geometry obs_contour <- shape.contour;
            if (obs_contour != nil) {
                sidewalk_lines <- sidewalk_lines + (obs_contour.geometries);
            }
        }

        // Crear especies temporales para las banquetas
        loop line_geom over: sidewalk_lines {
            if (line_geom != nil) {
                create temp_pedestrian_path {
                    shape <- line_geom;
                }
            }
        }

 // 3. Generación de Cruces Peatonales sobre las Avenidas
        ask road_geom {
            geometry road_border <- shape.contour;
            list<point> pts <- road_border.points;
            
            loop i from: 0 to: length(pts) - 1 step: 5 {
                point p1 <- pts[i];
                point p2 <- (pts where (each distance_to p1 > 8#m)) with_min_of (each distance_to p1);
                
                if (p2 != nil and (p1 distance_to p2) < 30#m) {
                    create temp_pedestrian_path {
                        // Uso del operador nativo 'line'
                        shape <- line([p1, p2]); 
                    }
                }
            }
        }

        // 4. Conectar Puntos de Estacionamiento a la Red Peatonal
        ask parking_geom {
            point center_p <- location;
            temp_pedestrian_path nearest_path <- temp_pedestrian_path with_min_of (each distance_to center_p);
            
            if (nearest_path != nil) {
                // CORRECCIÓN: 'closest_points_with' calcula el segmento más corto.
                // .points[0] toma el punto proyectado sobre la línea 'nearest_path.shape'.
                geometry shortest_segment <- nearest_path.shape closest_points_with center_p;
                point proj_p <- shortest_segment.points[0];
                
                create temp_pedestrian_path {
                    shape <- line([center_p, proj_p]);
                }
            }
        }

        // 5. Limpieza Topológica (CRÍTICO): Cortar líneas en cada intersección
        // Si las líneas no se dividen en las intersecciones, el grafo no conectará las rutas.
        write "Limpiando topología y dividiendo líneas en cruces...";
        
        list<geometry> all_geoms <- temp_pedestrian_path collect each.shape;
        list<geometry> split_geoms <- split_lines(all_geoms);

        // Recrear las rutas limpias y unificadas
        ask temp_pedestrian_path { do die; }

        loop g over: split_geoms {
            create final_pedestrian_path {
                shape <- g;
            }
        }

        // 6. Validar que el Grafo sea continuo
        graph test_graph <- as_edge_graph(final_pedestrian_path);
        write "Red Peatonal Generada Exitosamente:";
        write "  - Segmentos de red: " + length(final_pedestrian_path);
        write "  - Nodos/Intersecciones: " + length(test_graph.vertices);
        write "  - Componentes conexas: " + length(connected_components_of(test_graph));

        // 7. EXPORTAR A SHAPEFILE
        save final_pedestrian_path to: "../includes/shp/pedestrian_network.shp" format: "shp";
        write "=== ARCHIVO 'pedestrian_network.shp' GUARDADO EN /includes/shp/ ===";
    }
}

species block_geom { aspect default { draw shape color: #lightgray border: #gray; } }
species road_geom { aspect default { draw shape color: #darkgray; } }
species parking_geom { aspect default { draw shape color: #blue; } }
species obstacle_geom { aspect default { draw shape color: #dimgray; } }

species temp_pedestrian_path;

species final_pedestrian_path {
    aspect default {
        draw shape color: #lime width: 1.5;
    }
}

experiment Generate_Network type: gui {
    output {
        display "Vista Previa de la Red Peatonal Generada" type: opengl background: #black {
            species block_geom aspect: default;
            species road_geom aspect: default;
            species obstacle_geom aspect: default;
            species parking_geom aspect: default;
            species final_pedestrian_path aspect: default;
        }
    }
}