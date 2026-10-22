import http.server
import socketserver
import json
import os

PORT = 8000
COMMANDS_FILE = "includes/data/commands.json"

# Asegurar directorio de datos
os.makedirs("includes/data", exist_ok=True)
if not os.path.exists(COMMANDS_FILE):
    with open(COMMANDS_FILE, "w") as f:
        json.dump({"vehicle_count": 100, "active_layer": "emissions", "updated": True}, f)

class CityScopeHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Permitir CORS para peticiones locales
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        super().end_headers()

    def do_POST(self):
        if self.path == '/api/control':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            command = json.loads(post_data.decode('utf-8'))
            command['updated'] = True
            
            with open(COMMANDS_FILE, "w") as f:
                json.dump(command, f)
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "message": "Comando enviado a GAMA"}).encode('utf-8'))

print(f"🚀 Servidor CityScope activo en: http://localhost:{PORT}")
print(f"📂 Abre tu navegador en: http://localhost:{PORT}/output/dashboard.html")

with socketserver.TCPServer(("", PORT), CityScopeHandler) as httpd:
    httpd.serve_forever()