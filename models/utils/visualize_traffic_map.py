import os
import json
import pandas as pd

# --- CATALOGO DE NODOS GEORREFERENCIADOS DEL POLÍGONO CIUDAD UDG ---
NODES = {
    "ORIGIN_ESTADIO": {"lat": 20.7380, "lng": -103.3800, "name": "Estadio (30k Capacidad)", "color": "#e74c3c", "type": "origin"},
    "ORIGIN_TELMEX": {"lat": 20.7335, "lng": -103.3822, "name": "Auditorio Telmex (11.5k Capacidad)", "color": "#e67e22", "type": "origin"},
    "ORIGIN_CUCEA": {"lat": 20.7420, "lng": -103.3805, "name": "CUCEA (Estacionamiento)", "color": "#8e44ad", "type": "origin"},
    
    "DEST_BRT_CCU": {"lat": 20.7360, "lng": -103.3810, "name": "Mi Macro CCU", "color": "#2980b9", "type": "transit"},
    "DEST_BRT_CONST": {"lat": 20.7375, "lng": -103.3765, "name": "Mi Macro Constitución", "color": "#2980b9", "type": "transit"},
    "DEST_L3_MMAR": {"lat": 20.7255, "lng": -103.3860, "name": "L3 Mercado del Mar", "color": "#27ae60", "type": "transit"},
    "DEST_PERI_PONIENTE": {"lat": 20.7390, "lng": -103.3880, "name": "Periférico Norte Poniente", "color": "#7f8c8d", "type": "road"},
    "DEST_PERI_ORIENTE": {"lat": 20.7365, "lng": -103.3700, "name": "Periférico Norte Oriente", "color": "#7f8c8d", "type": "road"},
    "DEST_PARRES_ARIAS": {"lat": 20.7310, "lng": -103.3850, "name": "Av. Parres Arias", "color": "#7f8c8d", "type": "road"}
}

def generate_interactive_map(csv_path: str, out_html: str = "mapa_movilidad_ciudad_udg.html"):
    if not os.path.exists(csv_path):
        print(f"❌ No se encontró el archivo CSV en: {csv_path}")
        return

    df = pd.read_csv(csv_path)
    print(f"📊 Cargando {len(df)} pares Origen-Destino desde '{csv_path}'...")

    # Consolidar datos únicos por O/D y Modo para evitar duplicados
    df_unique = df.groupby(['origin_id', 'dest_id', 'mode']).agg({
        'distance_km': 'first',
        'traffic_min': 'first'
    }).reset_index()

    # Preparar datos JSON para inyectar en Leaflet
    routes_json = []
    for _, row in df_unique.iterrows():
        orig_id = row['origin_id']
        dest_id = row['dest_id']
        
        if orig_id in NODES and dest_id in NODES:
            orig = NODES[orig_id]
            dest = NODES[dest_id]
            
            routes_json.append({
                "origin_id": orig_id,
                "origin_name": orig["name"],
                "dest_id": dest_id,
                "dest_name": dest["name"],
                "mode": row['mode'],
                "distance_km": float(row['distance_km']),
                "traffic_min": float(row['traffic_min']),
                "coords": [
                    [orig["lat"], orig["lng"]],
                    [dest["lat"], dest["lng"]]
                ]
            })

    # Plantilla HTML autónoma con Leaflet.js (OpenStreetMap)
    html_template = f"""<!DOCTYPE html>
<html>
<head>
    <title>Mapa de Movilidad - Ciudad UDG</title>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <style>
        body {{ margin:0; padding:0; font-family: Arial, sans-serif; }}
        #map {{ width: 100%; height: 100vh; }}
        .legend {{
            position: absolute; bottom: 30px; left: 10px; z-index: 1000;
            background: rgba(255, 255, 255, 0.95); padding: 15px; border-radius: 8px;
            box-shadow: 0 0 15px rgba(0,0,0,0.2); font-size: 13px; line-height: 1.8;
        }}
        .legend h4 {{ margin: 0 0 8px 0; font-size: 14px; font-weight: bold; }}
        .badge {{ display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-right: 6px; }}
        .line-sample {{ display: inline-block; width: 20px; height: 3px; margin-right: 6px; vertical-align: middle; }}
    </style>
</head>
<body>
    <div id="map"></div>
    <div class="legend">
        <h4>Polígono Ciudad UDG - Movilidad</h4>
        <div><span class="badge" style="background:#e74c3c;"></span> Estadio (30k)</div>
        <div><span class="badge" style="background:#e67e22;"></span> Auditorio Telmex (11.5k)</div>
        <div><span class="badge" style="background:#2980b9;"></span> BRT Mi Macro (CCU / Const)</div>
        <div><span class="badge" style="background:#27ae60;"></span> L3 Mercado del Mar</div>
        <div><span class="badge" style="background:#7f8c8d;"></span> Nodos Viales Periférico/Parres</div>
        <hr style="margin: 8px 0; border: 0; border-top: 1px solid #ccc;">
        <div><span class="line-sample" style="background:#2b5c8f;"></span> Vehicular (DRIVE - Sólida)</div>
        <div><span class="line-sample" style="border-bottom: 2px dashed #e74c3c; height:0;"></span> Peatonal (WALK - Punteada)</div>
    </div>

    <script>
        // Inicializar mapa centrado en el polígono Belenes (Ciudad UDG)
        var map = L.map('map').setView([20.7350, -103.3810], 15);

        // Capa base de OpenStreetMap
        L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{
            maxZoom: 19,
            attribution: '© OpenStreetMap contributors | Ciudad UDG'
        }}).addTo(map);

        var nodes = {json.dumps(NODES, ensure_ascii=False)};
        var routes = {json.dumps(routes_json, ensure_ascii=False)};

        // 1. Dibujar Marcadores de Nodos
        Object.keys(nodes).forEach(function(key) {{
            var node = nodes[key];
            var circle = L.circleMarker([node.lat, node.lng], {{
                radius: node.type === 'origin' ? 9 : 7,
                fillColor: node.color,
                color: '#ffffff',
                weight: 2,
                opacity: 1,
                fillOpacity: 0.9
            }}).addTo(map);

            circle.bindPopup("<b>" + node.name + "</b><br>Coordenadas: " + node.lat + ", " + node.lng);
            circle.bindTooltip(node.name, {{permanent: false, direction: 'top'}});
        }});

        // 2. Dibujar Rutas con Tiempos Recolectados
        routes.forEach(function(r) {{
            var isWalk = r.mode === 'WALK';
            var lineColor = isWalk ? '#e74c3c' : (r.traffic_min > 8.0 ? '#c0392b' : '#2980b9');
            var dashArray = isWalk ? '6, 8' : '1, 0';

            var polyline = L.polyline(r.coords, {{
                color: lineColor,
                weight: isWalk ? 3 : 2.5,
                opacity: 0.75,
                dashArray: dashArray
            }}).addTo(map);

            var popupContent = "<b>Ruta:</b> " + r.origin_name + " ➔ " + r.dest_name + "<br>" +
                               "<b>Modo:</b> " + (isWalk ? "🚶 Peatonal (WALK)" : "🚗 Vehicular (DRIVE)") + "<br>" +
                               "<b>Tiempo Calculado:</b> <b style='color:#c0392b;'>" + r.traffic_min + " min</b><br>" +
                               "<b>Distancia:</b> " + r.distance_km + " km";

            polyline.bindPopup(popupContent);
        }});
    </script>
</body>
</html>"""

    with open(out_html, "w", encoding="utf-8") as f:
        f.write(html_template)

    print(f"\n=========================================================================")
    print(f"🎉 MAPA INTERACTIVO GENERADO EXITOSAMENTE")
    print(f"📄 Archivo: '{os.path.abspath(out_html)}'")
    print(f"💡 Abre este archivo en cualquier navegador (Chrome, Edge, Firefox) para interactuar.")
    print(f"=========================================================================")

if __name__ == "__main__":
    # Rutas posibles del archivo CSV
    possible_paths = [
        "includes/data/traffic/matrix_summary_sc0_sc1_sc1e.csv",
        "matrix_summary_sc0_sc1_sc1e.csv",
        "../includes/data/traffic/matrix_summary_sc0_sc1_sc1e.csv"
    ]
    
    csv_file = None
    for path in possible_paths:
        if os.path.exists(path):
            csv_file = path
            break

    if csv_file:
        generate_interactive_map(csv_file)
    else:
        print("❌ No se encontró el archivo 'matrix_summary_sc0_sc1_sc1e.csv' en las rutas probables.")