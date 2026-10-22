import os
import json
import requests
import argparse
import pandas as pd
from datetime import datetime, timezone

# --- CATALOGO DE NODOS GEORREFERENCIADOS DEL POLÍGONO CIUDAD UDG ---
NODES = {
    "ORIGIN_ESTADIO": {"lat": 20.7380, "lng": -103.3800},
    "ORIGIN_TELMEX": {"lat": 20.7335, "lng": -103.3822},
    "ORIGIN_CUCEA": {"lat": 20.7420, "lng": -103.3805},
    
    "DEST_BRT_CCU": {"lat": 20.7360, "lng": -103.3810},
    "DEST_BRT_CONST": {"lat": 20.7375, "lng": -103.3765},
    "DEST_L3_MMAR": {"lat": 20.7255, "lng": -103.3860},
    "DEST_PERI_PONIENTE": {"lat": 20.7390, "lng": -103.3880},
    "DEST_PERI_ORIENTE": {"lat": 20.7365, "lng": -103.3700},
    "DEST_PARRES_ARIAS": {"lat": 20.7310, "lng": -103.3850}
}

# --- CONFIGURACIÓN DE ESCENARIOS (0, 1 Y 1e) ---
SCENARIOS = {
    "sc0_peak_driving": {
        "scenario_group": "Escenario 0",
        "description": "Línea Base: Hora pico cotidiana (Jueves 18:30 hrs) - Vehicular",
        "origins": ["ORIGIN_CUCEA", "ORIGIN_TELMEX"],
        "destinations": ["DEST_PERI_PONIENTE", "DEST_PERI_ORIENTE", "DEST_PARRES_ARIAS"],
        "mode": "DRIVE",
        "routing_pref": "TRAFFIC_AWARE",
        "datetime_utc": datetime(2026, 10, 23, 0, 30, 0, tzinfo=timezone.utc)
    },
    "sc0_night_driving": {
        "scenario_group": "Escenario 0",
        "description": "Línea Base: Tráfico base nocturno sin evento (Viernes 23:00 hrs) - Vehicular",
        "origins": ["ORIGIN_ESTADIO", "ORIGIN_CUCEA"],
        "destinations": ["DEST_BRT_CCU", "DEST_PERI_PONIENTE", "DEST_PERI_ORIENTE"],
        "mode": "DRIVE",
        "routing_pref": "TRAFFIC_AWARE",
        "datetime_utc": datetime(2026, 10, 24, 5, 0, 0, tzinfo=timezone.utc)
    },
    "sc1_stress_driving": {
        "scenario_group": "Escenario 1",
        "description": "Prueba de Estrés: Evacuación Estadio (30k) Vehicular - Viernes 23:00 hrs",
        "origins": ["ORIGIN_ESTADIO"],
        "destinations": ["DEST_BRT_CCU", "DEST_BRT_CONST", "DEST_L3_MMAR", "DEST_PERI_PONIENTE", "DEST_PERI_ORIENTE", "DEST_PARRES_ARIAS"],
        "mode": "DRIVE",
        "routing_pref": "TRAFFIC_AWARE_OPTIMAL",
        "datetime_utc": datetime(2026, 10, 24, 5, 0, 0, tzinfo=timezone.utc)
    },
    "sc1_stress_walking": {
        "scenario_group": "Escenario 1",
        "description": "Prueba de Estrés: Caminata hacia BRT/L3 (10.8k peatonas) - Viernes 23:00 hrs",
        "origins": ["ORIGIN_ESTADIO"],
        "destinations": ["DEST_BRT_CCU", "DEST_BRT_CONST", "DEST_L3_MMAR"],
        "mode": "WALK",
        "routing_pref": "ROUTING_PREFERENCE_UNSPECIFIED",
        "datetime_utc": None
    },
    "sc1e_compound_driving": {
        "scenario_group": "Escenario 1e",
        "description": "Crisis Extrema: Desalojo Simultáneo Estadio (30k) + Telmex (11.5k) Vehicular",
        "origins": ["ORIGIN_ESTADIO", "ORIGIN_TELMEX"],
        "destinations": ["DEST_BRT_CCU", "DEST_BRT_CONST", "DEST_L3_MMAR", "DEST_PERI_PONIENTE", "DEST_PERI_ORIENTE", "DEST_PARRES_ARIAS"],
        "mode": "DRIVE",
        "routing_pref": "TRAFFIC_AWARE_OPTIMAL",
        "datetime_utc": datetime(2026, 10, 24, 5, 0, 0, tzinfo=timezone.utc)
    },
    "sc1e_compound_walking": {
        "scenario_group": "Escenario 1e",
        "description": "Crisis Extrema: Desalojo Peatonal Cruzado Estadio + Telmex hacia Transporte",
        "origins": ["ORIGIN_ESTADIO", "ORIGIN_TELMEX"],
        "destinations": ["DEST_BRT_CCU", "DEST_BRT_CONST", "DEST_L3_MMAR"],
        "mode": "WALK",
        "routing_pref": "ROUTING_PREFERENCE_UNSPECIFIED",
        "datetime_utc": None
    }
}

def compute_single_route(origin_id: str, dest_id: str, mode: str, routing_pref: str, dt_utc: datetime, api_key: str):
    """Consulta el endpoint REST oficial de Google Routes API (computeRoutes)."""
    url = "https://routes.googleapis.com/directions/v2:computeRoutes"
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": "routes.duration,routes.distanceMeters"
    }

    body = {
        "origin": {"location": {"latLng": {"latitude": NODES[origin_id]["lat"], "longitude": NODES[origin_id]["lng"]}}},
        "destination": {"location": {"latLng": {"latitude": NODES[dest_id]["lat"], "longitude": NODES[dest_id]["lng"]}}},
        "travelMode": mode
    }

    if mode == "DRIVE":
        body["routingPreference"] = routing_pref
        if dt_utc:
            body["departureTime"] = dt_utc.strftime("%Y-%m-%dT%H:%M:%SZ")

    resp = requests.post(url, headers=headers, json=body)
    
    if resp.status_code != 200:
        print(f"   ⚠️ Error {resp.status_code} al consultar {origin_id} -> {dest_id}: {resp.text}")
        return None

    data = resp.json()
    if "routes" in data and len(data["routes"]) > 0:
        route = data["routes"][0]
        dist_m = route.get("distanceMeters", 0)
        dur_str = route.get("duration", "0s").replace("s", "")
        dur_sec = float(dur_str) if dur_str else 0.0
        return {
            "distance_m": dist_m,
            "duration_sec": dur_sec
        }
    return None

def fetch_scenario_matrix(scenario_key: str, api_key: str, cache_dir: str = "includes/data/traffic/"):
    os.makedirs(cache_dir, exist_ok=True)
    cache_path = os.path.join(cache_dir, f"{scenario_key}.json")

    # Sistema de Caché Local ($0.00 USD en corridas subsecuentes)
    if os.path.exists(cache_path):
        print(f"   📁 [Caché local] '{scenario_key}' cargado desde disco ($0.00 USD)")
        with open(cache_path, "r", encoding="utf-8") as f:
            return json.load(f)

    config = SCENARIOS[scenario_key]
    print(f" 🌐 [Routes API v2] Procesando '{config['description']}'...")

    matrix_results = []
    for origin_id in config["origins"]:
        for dest_id in config["destinations"]:
            res = compute_single_route(
                origin_id=origin_id,
                dest_id=dest_id,
                mode=config["mode"],
                routing_pref=config["routing_pref"],
                dt_utc=config["datetime_utc"],
                api_key=api_key
            )
            if res:
                matrix_results.append({
                    "origin_id": origin_id,
                    "dest_id": dest_id,
                    "distance_m": res["distance_m"],
                    "duration_sec": res["duration_sec"]
                })

    payload = {
        "scenario_metadata": {
            "scenario_group": config["scenario_group"],
            "description": config["description"],
            "mode": config["mode"],
            "timestamp_str": config["datetime_utc"].strftime("%Y-%m-%dT%H:%M:%SZ") if config["datetime_utc"] else "N/A"
        },
        "results": matrix_results
    }

    with open(cache_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
    print(f"   💾 Guardado exitoso en caché: '{cache_path}'")
    return payload

def parse_to_dataframe(payload):
    meta = payload["scenario_metadata"]
    results = payload["results"]
    
    records = []
    for item in results:
        dist_m = item["distance_m"]
        dur_sec = item["duration_sec"]
        
        records.append({
            "scenario_group": meta["scenario_group"],
            "scenario_description": meta["description"],
            "mode": meta["mode"],
            "origin_id": item["origin_id"],
            "dest_id": item["dest_id"],
            "distance_m": dist_m,
            "distance_km": round(dist_m / 1000.0, 2),
            "traffic_min": round(dur_sec / 60.0, 1)
        })
    return pd.DataFrame(records)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Ejecutor Routes API REST computeRoutes (Escenarios 0, 1 y 1e)")
    parser.add_argument("--api-key", "-k", required=True, help="Google Cloud API Key")
    args = parser.parse_args()

    print("=========================================================================")
    print("🚀 INICIANDO RECOLECCIÓN VÍA GOOGLE ROUTES API (computeRoutes)")
    print("=========================================================================\n")

    all_dfs = []
    for sc_key in SCENARIOS:
        payload = fetch_scenario_matrix(sc_key, api_key=args.api_key)
        df_sc = parse_to_dataframe(payload)
        all_dfs.append(df_sc)

    df_final = pd.concat(all_dfs, ignore_index=True)
    out_csv = "includes/data/traffic/matrix_summary_sc0_sc1_sc1e.csv"
    os.makedirs("includes/data/traffic/", exist_ok=True)
    df_final.to_csv(out_csv, index=False)

    print("\n=========================================================================")
    print(f" RESUMEN COMPLETO GUARDADO EN '{out_csv}'")
    print("=========================================================================")
    print(df_final[["scenario_group", "mode", "origin_id", "dest_id", "distance_km", "traffic_min"]].to_string(index=False))