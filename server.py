import socket 
import torch 
import torch.nn as nn 
import torch.optim as optim 
import os 
import csv 
from datetime import datetime 
import time 

# --- CONFIGURACIÓN --- 
PY_HOST = "127.0.0.1" 
PY_PORT = 5005 
MODEL_FILE = "modelo_peltier.pth" 

# Aumentamos el OFFSET para compensar la inercia térmica
# Si pedimos 15 y da 16.9, necesitamos que la IA "crea" que el objetivo es más bajo
OFFSET_CONSIGNA = 3.5  # Subimos de 1.8 a 3.5 para forzar la bajada

CSV_FILE = f"ensayo_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv" 

class EnergyOptimalNN(nn.Module): 
    def __init__(self): 
        super(EnergyOptimalNN, self).__init__() 
        self.net = nn.Sequential( 
            nn.Linear(6, 64), 
            nn.LeakyReLU(0.1), 
            nn.Linear(64, 32), 
            nn.LeakyReLU(0.1), 
            nn.Linear(32, 6)   
        ) 
        for m in self.modules(): 
            if isinstance(m, nn.Linear): 
                nn.init.orthogonal_(m.weight, gain=1.0) 
                nn.init.constant_(m.bias, 0.01) 

    def forward(self, x): return self.net(x) 

model = EnergyOptimalNN() 

if os.path.exists(MODEL_FILE): 
    try:
        model.load_state_dict(torch.load(MODEL_FILE))
        print(f">>> MEMORIA RECUPERADA: {MODEL_FILE}")
    except:
        print(">>> Iniciando nueva memoria.")

optimizer = optim.Adam(model.parameters(), lr=0.01) 

gains_nom = torch.tensor([58.93, 3.91, 2.66, 0.67, 1.47, 0.0], dtype=torch.float32) 
scales = torch.tensor([40.0, 15.0, 5.0, 0.5, 0.5, 0.2], dtype=torch.float32)  

header = ["Tiempo", "Tamb", "Tsup", "Tdew", "RH", "Tref", "PWM_Peltier", "PWM_Fan", "Kp", "Ki", "Kd", "Lambda", "Mu", "Kff"] 

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM) 
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1) 
server.bind((PY_HOST, PY_PORT)) 
server.listen(1) 

print(f">>> IA ONLINE - CORRIGIENDO OFFSET (Objetivo IA: Tref - {OFFSET_CONSIGNA})") 

try: 
    with open(CSV_FILE, mode='w', newline='') as f: 
        writer = csv.writer(f) 
        writer.writerow(header) 
        
        while True: 
            conn, addr = server.accept() 
            print(f"Conectado: {addr}") 
            error_acumulado = 0 
            start_time_ensayo = time.time() 
            step_count = 0 
            
            try: 
                while True: 
                    data = conn.recv(1024).decode('utf-8') 
                    if not data: break 
                    
                    parts = data.strip().split('\n')[-1].split(',') 
                    if len(parts) < 13: continue 
                    
                    d = [float(x) for x in parts] 
                    tiempo_actual = time.time() - start_time_ensayo 

                    # --- LÓGICA DE COMPENSACIÓN ---
                    t_ref_real = d[12]
                    t_ref_ia = t_ref_real - OFFSET_CONSIGNA 
                    
                    # El error ahora es respecto a la meta "agresiva"
                    error_val = d[1] - t_ref_ia 
                    
                    # Si el error es positivo (Tsup > Tref), aumentamos el peso del acumulado
                    # para que la Ki actúe con más fuerza.
                    factor_agresivo = 1.5 if error_val > 0 else 1.0
                    error_acumulado = error_acumulado * 0.95 + (error_val * factor_agresivo) * 0.05 
                    
                    state = torch.tensor([ 
                        error_val, 
                        error_acumulado * 2.5, # Aumentamos peso del acumulado
                        d[2]/100.0, 
                        d[0]/30.0, 
                        (d[1]-d[0]), 
                        t_ref_ia/20.0 
                    ], dtype=torch.float32, requires_grad=True) 
                    
                    optimizer.zero_grad() 
                    delta = model(state) 
                    new_gains = gains_nom + (delta * scales) 
                    
                    # Penalizamos más fuerte el error positivo (calor excesivo)
                    loss_error = torch.where(state[0] > 0, torch.pow(state[0], 2) * 40.0, torch.pow(state[0], 2) * 10.0)
                    loss_sparsity = 0.5 * torch.reciprocal(torch.sum(torch.abs(delta)) + 1e-5) 
                    loss_reg = 0.1 * torch.sum(delta**2) 
                    
                    loss = loss_error + loss_sparsity + loss_reg 
                    loss.backward() 
                    torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0) 
                    optimizer.step() 

                    # Guardado periódico
                    step_count += 1
                    if step_count % 20 == 0:
                        torch.save(model.state_dict(), MODEL_FILE)

                    msg = f"{new_gains[0].item():.4f},{new_gains[1].item():.4f},{new_gains[2].item():.4f},{new_gains[3].item():.4f},{new_gains[4].item():.4f},{new_gains[5].item():.4f}\n"
                    conn.send(msg.encode('utf-8')) 

                    row = [f"{tiempo_actual:.2f}", d[0], d[1], d[3], d[2], d[12], d[4], d[5], 
                           f"{new_gains[0].item():.4f}", f"{new_gains[1].item():.4f}", f"{new_gains[2].item():.4f}",  
                           f"{new_gains[3].item():.4f}", f"{new_gains[4].item():.4f}", f"{new_gains[5].item():.4f}"] 
                    writer.writerow(row) 
                    f.flush() 

            except Exception as e:  
                print(f"Error: {e}") 
            finally: 
                conn.close() 
                torch.save(model.state_dict(), MODEL_FILE) 
except KeyboardInterrupt: 
    pass
finally: 
    torch.save(model.state_dict(), MODEL_FILE)
    server.close()