import geopandas as gpd
import osmnx as ox

# 1. Cargar el Shapefile del límite del polígono
limits_path = "../includes/shp/environment/scenario_limits.shp"
limits_gdf = gpd.read_file(limits_path)

# Asegurar que la geometría esté en coordenadas WGS84 (EPSG:4326) para la API de OSM
if limits_gdf.crs is not None and limits_gdf.crs.to_epsg() != 4326:
    limits_gdf = limits_gdf.to_crs(epsg=4326)

# Unificar las geometrías por si el shapefile contiene múltiples polígonos
polygon = limits_gdf.geometry.unary_union

print("Descargando red peatonal de OpenStreetMap...")

# 2. Descargar la red usando el polígono como máscara
# network_type='walk' incluye banquetas, andadores, cruces peatonales y calles transitables a pie
G = ox.graph_from_polygon(polygon, network_type="walk", simplify=True)

# 3. Proyectar el grafo a coordenadas métricas (UTM local)
# OSMnx detecta e impone automáticamente la zona UTM adecuada en metros
G_projected = ox.project_graph(G)

# 4. Extraer el GeoDataFrame de las aristas (líneas de la red)
nodes, edges = ox.graph_to_gdfs(G_projected)

# 5. Limpiar atributos y exportar a Shapefile
# Se conservan sólo las columnas críticas para evitar limitaciones del formato .dbf
edges_clean = edges[["geometry", "length"]].reset_index(drop=True)

output_shp = "pedestrian_network.shp"
edges_clean.to_file(output_shp, driver="ESRI Shapefile")

print(
    f"¡Proceso completado! Se guardó '{output_shp}' con {len(edges_clean)} líneas conectadas."
)