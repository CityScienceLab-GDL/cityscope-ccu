import os
import sys
import time
import json
import requests
import argparse
import pandas as pd
from datetime import datetime, timezone

# --- CATÁLOGO DEFINITIVO DE NODOS GEORREFERENCIADOS Y AUDITADOS ---
NODES = {
    # Generadores Académicos y Culturales
    "ORIGIN_CUCEA":         {"lat": 20.742500, "lng": -103.380200},
    "ORIGIN_CUCSH":         {"lat": 20.739786, "lng": -103.377646},
    "ORIGIN_NUEVO_ESTADIO": {"lat": 20.733312, "lng": -103.375317},
    "ORIGIN_TELMEX":        {"lat": 20.733777, "lng": -103.381626},
    "ORIGIN_CHARROS":       {"lat": 20.727281, "lng": -103.381304},
    
    # Destinos / Dispersión Multimodal
    "DEST_BRT_CCU":       {"lat": 20.738939, "lng": -103.381113},
    "DEST_BRT_CONST":     {"lat": 20.736800, "lng": -103.373500},
    "DEST_L3_MMAR":       {"lat": 20.728752, "lng": -103.389188},
    "DEST_PARRES_ARIAS":  {"lat": 20.728752, "lng": -103.389188},
    "DEST_PERI_PONIENTE": {"lat": 20.740800, "lng": -103.391000},
    "DEST_PERI_ORIENTE":  {"lat": 20.735200, "lng": -103.367000}
}

# Matriz de Monitoreo Estratégico para Evento en Vivo
SAMPLING_PAIRS = [
    # Monitoreo Principal Auditorio Telmex
    ("ORIGIN_TELMEX", "DEST_PERI_PONIENTE", "DRIVE"),
    ("ORIGIN_TELMEX", "DEST_PERI_ORIENTE", "DRIVE"),
    ("ORIGIN_TELMEX", "DEST_PARRES_ARIAS", "DRIVE"),
    ("ORIGIN_TELMEX", "DEST_BRT_CCU", "DRIVE"),
    ("ORIGIN_TELMEX", "DEST_L3_MMAR", "WALK"),
    
    # Proyección / Referencia Nuevo Estadio
    ("ORIGIN_NUEVO_ESTADIO", "DEST_PERI_PONIENTE", "DRIVE"),
    ("ORIGIN_NUEVO_ESTADIO", "DEST_PERI_ORIENTE", "DRIVE"),
    ("ORIGIN_NUEVO_ESTADIO", "DEST_PARRES_ARIAS", "DRIVE"),
    ("ORIGIN_NUEVO_ESTADIO", "DEST_BRT_CONST", "DRIVE"),
    ("ORIGIN_NUEVO_ESTADIO", "DEST_BRT_CCU", "WALK"),
    
    # Campus Universitarios (Línea Base)
    ("ORIGIN_CUCEA", "DEST_PERI_PONIENTE", "DRIVE"),
    ("ORIGIN_CUCSH", "DEST_BRT_CCU", "WALK")
]

def parse_args():
    parser = argparse.ArgumentParser(description="Recolector Continuo de Telemetría en Vivo — Google Routes API v2")
    parser.add_argument("--api-key", "-k", required=True, help="Google Cloud API Key")
    parser.add_argument("--interval", "-i", type=int, default=10, help="Intervalo de consulta en minutos (por defecto: 10)")
    parser.add_argument("--event-tag", "-t", type=str, default="Bunbury_Telmex_20261021", help="Etiqueta del evento")
    parser.add_argument("--out-dir", "-o", type=str, default="includes/data/traffic/live_telemetry", help="Carpeta de salida")
    return parser.parse_args()

def fetch_single_route_raw(orig_id, dest_id, mode, api_key, event_tag, raw_log_file):
    """Consulta Google Routes API con timeout y manejo robusto de excepciones de red."""
    url = "https://routes.googleapis.com/directions/v2:computeRoutes"
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.staticDuration,routes.polyline,routes.legs,routes.travelAdvisory"
    }

    body = {
        "origin": {"location": {"latLng": {"latitude": NODES[orig_id]["lat"], "longitude": NODES[orig_id]["lng"]}}},
        "destination": {"location": {"latLng": {"latitude": NODES[dest_id]["lat"], "longitude": NODES[dest_id]["lng"]}}},
        "travelMode": mode
    }

    if mode == "DRIVE":
        body["routingPreference"] = "TRAFFIC_AWARE_OPTIMAL"

    timestamp_utc = datetime.now(timezone.utc).isoformat()

    try:
        resp = requests.post(url, headers=headers, json=body, timeout=12)
        status_code = resp.status_code
        
        try:
            resp_json = resp.json()
        except Exception:
            resp_json = {"raw_text": resp.text}

        # Guardar registro crudo con modo append (NUNCA SOBREESCRIBE)
        raw_record = {
            "metadata": {
                "timestamp_utc": timestamp_utc,
                "event_tag": event_tag,
                "origin_id": orig_id,
                "destination_id": dest_id,
                "mode": mode,
                "origin_coords": NODES[orig_id],
                "destination_coords": NODES[dest_id]
            },
            "google_response": {
                "status_code": status_code,
                "body_raw": resp_json
            }
        }

        with open(raw_log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(raw_record, ensure_ascii=False) + "\n")

        # Extraer métricas procesadas
        if status_code == 200 and "routes" in resp_json and len(resp_json["routes"]) > 0:
            route = resp_json["routes"][0]
            dist_m = route.get("distanceMeters", 0)
            dur_str = route.get("duration", "0s").replace("s", "")
            dur_sec = float(dur_str) if dur_str else 0.0
            
            return {
                "timestamp_utc": timestamp_utc,
                "origin_id": orig_id,
                "dest_id": dest_id,
                "mode": mode,
                "distance_km": round(dist_m / 1000.0, 2),
                "traffic_min": round(dur_sec / 60.0, 1),
                "speed_kmh": round((dist_m / 1000.0) / (dur_sec / 3600.0), 1) if dur_sec > 0 else 0
            }

    except requests.exceptions.RequestException as net_err:
        print(f"   ⚠️ [ERROR RED] {orig_id} ➔ {dest_id}: {net_err}")
    except Exception as err:
        print(f"   ⚠️ [ERROR GENÉRICO] {orig_id} ➔ {dest_id}: {err}")

    return None

def main():
    args = parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    
    date_str = datetime.now().strftime("%Y%m%d")
    raw_log_file = os.path.join(args.out_dir, f"raw_telemetry_{args.event_tag}_{date_str}.jsonl")
    csv_summary_file = os.path.join(args.out_dir, f"summary_{args.event_tag}_{date_str}.csv")

    print("=========================================================================")
    print(f"🚀 MONITOR DE TELEMETRÍA EN VIVO (EVENTO: {args.event_tag})")
    print(f"📁 Log Crudo (Raw JSON): {raw_log_file}")
    print(f"📊 Resumen CSV:         {csv_summary_file}")
    print(f"⏱️ Frecuencia Muestreo: Cada {args.interval} minutos")
    print("=========================================================================")

    summary_records = []

    # 🔄 RECUPERACIÓN AUTOMÁTICA EN CASO DE REINICIO DE LA COMPUTADORA
    if os.path.exists(csv_summary_file):
        try:
            existing_df = pd.read_csv(csv_summary_file)
            summary_records = existing_df.to_dict("records")
            print(f"🔄 [SESIÓN RECUPERADA] Se cargaron {len(summary_records)} lecturas previas registradas hoy.")
        except Exception as e:
            print(f"⚠️ No se pudo leer el CSV previo: {e}")

    try:
        while True:
            now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            print(f"\n[⏱️ {now_str}] Capturando nueva muestra de tráfico...")

            for orig, dest, mode in SAMPLING_PAIRS:
                res = fetch_single_route_raw(orig, dest, mode, args.api_key, args.event_tag, raw_log_file)
                if res:
                    summary_records.append(res)
                    print(f"   🟢 {orig} ➔ {dest} ({mode}): {res['traffic_min']} min | {res['speed_kmh']} km/h")

            # Guardado acumulativo inmediato
            if summary_records:
                df = pd.DataFrame(summary_records)
                df.to_csv(csv_summary_file, index=False)

            print(f"💤 Muestra completada. Esperando {args.interval} minutos para el siguiente ciclo...")
            time.sleep(args.interval * 60)

    except KeyboardInterrupt:
        print("\n🛑 Proceso detenido por el usuario. Todos los datos están a salvo.")
    except Exception as fatal_e:
        print(f"\n💥 Error fatal no esperado: {fatal_e}")

if __name__ == "__main__":
    main()