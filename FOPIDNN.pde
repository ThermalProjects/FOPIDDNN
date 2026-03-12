import processing.serial.*;
import controlP5.*;
import java.util.ArrayList;
import java.net.Socket;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintWriter;

Serial myPort;
ControlP5 cp5;
Socket socket;
BufferedReader socketIn;
PrintWriter socketOut;

String PY_HOST = "127.0.0.1";
int PY_PORT = 5005;

// ================== Variables principales ==================
float prevPwmPeltier = 0;
float nextPwmPeltier = 0;
float pwmPeltier = 0;

float Tamb=0, Tsup=0, Tdew=0, RH=0, Tref=25;
float pwmFan=0;
boolean isLogging=false;
int startTime;
int ensayoNumero=0, ensayoDuracion=180;

// Nuevo parámetro FOPID
float Kff = 0;
float Kp=0, Ki=0, Kd=0;
float lambda = 0.67f, mu = 1.47f;

ArrayList<Float> histTsup = new ArrayList<Float>();
ArrayList<Float> histTdew = new ArrayList<Float>();
ArrayList<Float> histPeltier = new ArrayList<Float>();
ArrayList<Float> histFan = new ArrayList<Float>();
ArrayList<Float> histTime = new ArrayList<Float>();

// Interpolación
float prevTsup=0, prevTdew=0;
float nextTsup=0, nextTdew=0;
float interpTimer=0;
float Tsamp = 0.2f;
float interpStep = 0.05f;

Textfield txtTref, txtKp, txtKi, txtKd, txtLam, txtMu, txtKff, txtDuracion, txtEnsayoNombre;
Button btnStart, btnFanToggle, btnModeToggle;
boolean fanManual=false;
boolean showTdew=false;

PFont font14, font16, font24, fontButton;
PShape logo1, logo2;

boolean savedThisRun = false;

// ================== Setup ==================
void setup() {
  size(1200,780);
  surface.setTitle("FOPID + NN Thermal Management");

  try{ logo1 = loadShape("logo.svg"); } catch(Exception e){ logo1 = null; }
  try{ logo2 = loadShape("logo2.svg"); } catch(Exception e){ logo2 = null; }

  font14 = createFont("DialogInput", 14);
  font16 = createFont("DialogInput", 16);
  font24 = createFont("DialogInput", 24);
  fontButton = createFont("DialogInput", 18);
  textFont(font14);

  myPort = new processing.serial.Serial(this, "COM3", 115200);
  myPort.bufferUntil('\n');
  try {
    socket = new Socket(PY_HOST, PY_PORT);
    socketIn  = new BufferedReader(new InputStreamReader(socket.getInputStream()));
    socketOut = new PrintWriter(socket.getOutputStream(), true);
    println("Conectado a Python por TCP");
  } 
  catch(Exception e){
    println("Error TCP: " + e);
  }

  cp5 = new ControlP5(this);
  setupGUI();
}

// ================== GUI ==================
void setupGUI() {
  int x=20, yStart=60, gapY=60, wField=230, hField=28;
  int labelOffsetY=-2;

  txtTref = cp5.addTextfield("txtTref").setPosition(x,yStart+25).setSize(wField,hField).setText("15.0").setFont(font14)
    .setColorBackground(color(220)).setColorForeground(color(220)).setColorActive(color(200)).setColorValue(color(50));
  cp5.addTextlabel("lblTref").setText("T Consigna (°C)").setPosition(x,yStart+10+labelOffsetY).setColorValue(color(50)).setFont(font16);

  txtKp = cp5.addTextfield("txtKp").setPosition(x,yStart+gapY+25).setSize(wField,hField).setText("58.93").setFont(font14)
    .setColorBackground(color(220)).setColorForeground(color(220)).setColorActive(color(200)).setColorValue(color(50));
  cp5.addTextlabel("lblKp").setText("Kp").setPosition(x,yStart+gapY+10+labelOffsetY).setColorValue(color(50)).setFont(font16);

  txtKi = cp5.addTextfield("txtKi").setPosition(x,yStart+2*gapY+25).setSize(wField,hField).setText("3.91").setFont(font14)
    .setColorBackground(color(220)).setColorForeground(color(220)).setColorActive(color(200)).setColorValue(color(50));
  cp5.addTextlabel("lblKi").setText("Ki").setPosition(x,yStart+2*gapY+10+labelOffsetY).setColorValue(color(50)).setFont(font16);

  txtKd = cp5.addTextfield("txtKd").setPosition(x,yStart+3*gapY+25).setSize(wField,hField).setText("2.66").setFont(font14)
    .setColorBackground(color(220)).setColorForeground(color(220)).setColorActive(color(200)).setColorValue(color(50));
  cp5.addTextlabel("lblKd").setText("Kd").setPosition(x,yStart+3*gapY+10+labelOffsetY).setColorValue(color(50)).setFont(font16);

  txtLam = cp5.addTextfield("txtLam").setPosition(x,yStart+4*gapY+25).setSize(wField,hField).setText("0.67").setFont(font14)
    .setColorBackground(color(220)).setColorForeground(color(220)).setColorActive(color(200)).setColorValue(color(50));
  cp5.addTextlabel("lblLam").setText("λ").setPosition(x,yStart+4*gapY+10+labelOffsetY).setColorValue(color(50)).setFont(font16);

  txtMu = cp5.addTextfield("txtMu").setPosition(x,yStart+5*gapY+25).setSize(wField,hField).setText("1.47").setFont(font14)
    .setColorBackground(color(220)).setColorForeground(color(220)).setColorActive(color(200)).setColorValue(color(50));
  cp5.addTextlabel("lblMu").setText("μ").setPosition(x,yStart+5*gapY+10+labelOffsetY).setColorValue(color(50)).setFont(font16);

  txtKff = cp5.addTextfield("txtKff")
    .setPosition(x, yStart+6*gapY+25)
    .setSize(wField, hField)
    .setText("0.0")   // valor inicial neutro
    .setFont(font14)
    .setColorBackground(color(220)).setColorForeground(color(220)).setColorActive(color(200)).setColorValue(color(50));
  cp5.addTextlabel("lblKff").setText("Kff").setPosition(x,yStart+6*gapY+10+labelOffsetY).setColorValue(color(50)).setFont(font16);

  txtDuracion = cp5.addTextfield("txtDuracion").setPosition(x,yStart+7*gapY+25).setSize(wField,hField).setText("300")
    .setFont(font14).setColorBackground(color(220)).setColorForeground(color(220)).setColorActive(color(200)).setColorValue(color(50));
  cp5.addTextlabel("lblDuracion").setText("Duración ensayo [s]").setPosition(x,yStart+7*gapY+10+labelOffsetY).setColorValue(color(50)).setFont(font16);

  txtEnsayoNombre = cp5.addTextfield("txtEnsayoNombre").setPosition(x,yStart+8*gapY+25).setSize(wField,hField)
    .setText("Ensayo").setFont(font14).setColorBackground(color(220)).setColorForeground(color(220)).setColorActive(color(200)).setColorValue(color(50));
  cp5.addTextlabel("lblEnsayoNombre").setText("Nombre del ensayo").setPosition(x,yStart+8*gapY+10+labelOffsetY).setColorValue(color(50)).setFont(font16);

  color btnStartColor = color(135,206,235);
  color btnFanColor = color(230,120,130);
  color btnModeColor = color(100,149,237);

  btnStart = cp5.addButton("toggleStart").setPosition(x,yStart+9*gapY+25).setSize(wField,40)
    .setLabel("Iniciar ensayo").setColorBackground(btnStartColor).setFont(fontButton);
  btnFanToggle = cp5.addButton("toggleFan").setPosition(x,yStart+9*gapY+75).setSize(wField,40)
    .setLabel("Ventilador OFF").setColorBackground(btnFanColor).setFont(fontButton);
  btnModeToggle = cp5.addButton("toggleMode").setPosition(x,yStart+9*gapY+125).setSize(wField,40)
    .setLabel("Modo: Consigna").setColorBackground(btnModeColor).setFont(fontButton);
}

// ================== Draw ==================
void draw() {
  background(245);
  readPythonSocket();


  textFont(font24); textSize(24); fill(0,80,140); textAlign(LEFT,TOP);
  text("Control PID Fraccional con Redes Neuronales",20,20);

  // Logos
  float maxLogoWidth=60, maxLogoHeight=60, paddingRight=20;
  if(logo1!=null && logo2!=null){
    float scale1=min(maxLogoWidth/logo1.width, maxLogoHeight/logo1.height);
    float scale2=min(maxLogoWidth/logo2.width, maxLogoHeight/logo2.height);
    float logoGap=6;
    float x2=width-paddingRight-logo2.width*scale2;
    float x1=x2-logoGap-logo1.width*scale1;
    shape(logo1, x1, 20, logo1.width*scale1, logo1.height*scale1);
    shape(logo2, x2, 20, logo2.width*scale2, logo2.height*scale2);
  }

  // Interpolación
  interpTimer += interpStep;
  float ratio = interpTimer / Tsamp;
  ratio = constrain(ratio, 0, 1);
  Tsup = lerp(prevTsup, nextTsup, ratio);
  Tdew = lerp(prevTdew, nextTdew, ratio);
  pwmPeltier = lerp(prevPwmPeltier, nextPwmPeltier, ratio);

  // Información principal
  int infoY=80;
  textFont(font14); textSize(14); fill(0); textAlign(LEFT);
  text("Temperatura célula: "+nf(Tsup,1,2)+" °C",320,infoY);
  text("Temperatura ambiente: "+nf(Tamb,1,2)+" °C",320,infoY+20);
  text("Temperatura rocío: "+nf(Tdew,1,2)+" °C",320,infoY+40);
  text("Humedad: "+nf(RH,1,1)+" %",320,infoY+60);
  text("PWM Peltier: "+nf(pwmPeltier,1,0),320,infoY+80);
  text("PWM Fan:     "+nf(pwmFan,1,0),320,infoY+100);

  if(isLogging){
    int elapsed=(millis()-startTime)/1000;
    text("Ensayo nº: "+ensayoNumero,320,infoY+120);
    text("Tiempo de ensayo: "+elapsed+" s / "+ensayoDuracion+" s",320,infoY+140);
    text("Nombre ensayo: "+txtEnsayoNombre.getText().trim(),320,infoY+160);
    if(elapsed>=ensayoDuracion && !savedThisRun){
      savedThisRun = true;
      saveCSV();
      saveGraphImage();
      toggleStart();
    }
  }

  // ===== NUEVA COLUMNA: Parámetros seleccionados =====
  int paramX = 700; // posición X de la columna de parámetros
  int paramY = infoY;
  int gapY = 20;
  textAlign(LEFT);
  fill(50,0,120);

  // Mostrar primero la T Consigna
  text("T Consigna: "+txtTref.getText().trim(), paramX, paramY); 
  paramY += gapY;

  // Luego los demás parámetros
  text("Kp: "+nf(Kp,1,3), paramX, paramY); paramY += gapY;
  text("Ki: "+nf(Ki,1,3), paramX, paramY); paramY += gapY;
  text("Kd: "+nf(Kd,1,3), paramX, paramY); paramY += gapY;
  text("λ: "+txtLam.getText().trim(), paramX, paramY); paramY += gapY;
  text("μ: "+txtMu.getText().trim(), paramX, paramY); paramY += gapY;
  text("Kff: "+txtKff.getText().trim(), paramX, paramY); paramY += gapY;

  drawGraph();
}

// ================== Dibujar gráfica ==================
void drawGraph(){
  int gx=360, gy=280, gw=800, gh=400;
  fill(255); stroke(180); strokeWeight(1); rect(gx,gy,gw,gh,8);

  float tWindow = 60;
  float tEnd = histTime.size()>0 ? histTime.get(histTime.size()-1) : 0;
  float tStart = max(0, tEnd - tWindow);
  float tMax = 40;

  int legendX = gx + 15;
  int legendY = gy + 15;
  int legendH = 12;
  noStroke();

  fill(0,150,0); rect(legendX, legendY, legendH, legendH);
  fill(0); textSize(12); textAlign(LEFT, CENTER); text("Tsup", legendX + legendH + 4, legendY + legendH/2);

  if(showTdew){
    fill(255,0,255); rect(legendX + 70, legendY, legendH, legendH);
    fill(0); text("Tdew", legendX + 70 + legendH + 4, legendY + legendH/2);
  }

  if(!showTdew){
    fill(0,0,255); rect(legendX + 140, legendY, legendH, legendH);
    fill(0); text("Tref", legendX + 140 + legendH + 4, legendY + legendH/2);
  }

  stroke(200); strokeWeight(1);
  int yLines=8;
  for(int i=0;i<=yLines;i++){
    float y = gy + gh - i*gh/yLines;
    line(gx,y,gx+gw,y);
    fill(50); textAlign(RIGHT); textSize(12);
    text(nf(0 + i*(tMax-0)/yLines,1,0), gx-8, y+4);
  }

  int xLines=6;
  for(int i=0;i<=xLines;i++){
    float xVal = lerp(tStart,tEnd,i/(float)xLines);
    float x = map(xVal,tStart,tEnd,gx,gx+gw);
    line(x,gy,x,gy+gh);
    fill(50); textAlign(CENTER); text(nf(xVal,1,0),x,gy+gh+15);
  }

  textAlign(CENTER); fill(0); textSize(14);
  text("Tiempo [s]", gx+gw/2, gy+gh+40);
  pushMatrix(); translate(gx-50, gy+gh/2); rotate(-HALF_PI);
  text("Temperatura celda [°C]",0,0); popMatrix();

  stroke(0,150,0); noFill(); beginShape();
  for(int i=0;i<histTsup.size();i++){
    float x = map(histTime.get(i), tStart, tEnd, gx, gx+gw);
    float y = map(histTsup.get(i),0,tMax,gy+gh,gy);
    if(x>=gx && x<=gx+gw) vertex(constrain(x,gx,gx+gw), constrain(y,gy,gy+gh));
  }
  endShape();

  if(showTdew){
    stroke(255,0,255); noFill(); beginShape();
    for(int i=0;i<histTdew.size();i++){
      float x = map(histTime.get(i), tStart, tEnd, gx, gx+gw);
      float y = map(histTdew.get(i),0,tMax,gy+gh,gy);
      if(x>=gx && x<=gx+gw) vertex(constrain(x,gx,gx+gw), constrain(y,gy,gy+gh));
    }
    endShape();
  }

  if(!showTdew){
    stroke(0,0,255);
    float yRef = map(Tref,0,tMax,gy+gh,gy);
    line(gx, yRef, gx+gw, yRef);
  }
}

// ================== Botones ==================
void toggleStart(){ 
  if(!isLogging){
    sendSocket("RESET_ENSAYO"); // <-- envía a Python para reiniciar data_log y tiempo

    // ===== INICIO ENSAYO =====
    savedThisRun = false;

    // Leer parámetros desde la GUI
    try{ Tref=Float.parseFloat(txtTref.getText().trim()); }catch(Exception e){ Tref=25; }
    try{ Kff = Float.parseFloat(txtKff.getText().trim()); } catch(Exception e){ Kff = 0; }
    try{ Kp=Float.parseFloat(txtKp.getText().trim()); }catch(Exception e){ Kp=0; }
    try{ Ki=Float.parseFloat(txtKi.getText().trim()); }catch(Exception e){ Ki=0; }
    try{ Kd=Float.parseFloat(txtKd.getText().trim()); }catch(Exception e){ Kd=0; }
    try{ ensayoDuracion=Integer.parseInt(txtDuracion.getText().trim()); }catch(Exception e){ ensayoDuracion=180; }
    try{ lambda = Float.parseFloat(txtLam.getText().trim()); }catch(Exception e){ lambda = 0.67f; }
    try{ mu     = Float.parseFloat(txtMu.getText().trim()); }catch(Exception e){ mu = 1.47f; }

    isLogging=true;
    startTime=millis();
    ensayoNumero++;

    // Reset de listas y variables de interpolación
    histTsup.clear(); 
    histTdew.clear(); 
    histPeltier.clear(); 
    histFan.clear(); 
    histTime.clear();

    prevTsup = nextTsup = Tref;
    prevTdew = nextTdew = Tdew; 
    interpTimer=0;
    prevPwmPeltier = nextPwmPeltier = 0;
    pwmPeltier = 0;

    // Enviar parámetros al Arduino
    sendSerial("SET_TREF," + Tref);
    delay(25);
    sendSerial("SET_KP," + Kp);
    delay(25);
    sendSerial("SET_KI," + Ki);
    delay(25);
    sendSerial("SET_KD," + Kd);
    delay(25);
    sendSerial("SET_KFF," + Kff);
    delay(25);
    sendSerial("SET_LAMBDA," + lambda);
    delay(25);
    sendSerial("SET_MU," + mu);
    delay(25);
    sendSerial("SET_TS,0.2");
    delay(25);
    sendSerial("PWM_PELTIER,0");
    delay(25);

    if(fanManual){
      sendSerial("PWM_MANUAL_FAN,255");
      pwmFan=255;
    } else {
      sendSerial("FAN_MANUAL_OFF");
      pwmFan=0;
    }
    delay(25);

    sendSerial("FOPID_ON");
    if(showTdew) sendSerial("MODE_TDEW_ON");

    btnStart.setLabel("Detener ensayo").setColorBackground(color(205,92,92));
  } else {
    // ===== FIN ENSAYO =====
    isLogging=false;

    // Apagar Peltier gradualmente
    for(int pwm=(int)nextPwmPeltier; pwm>=0; pwm-=5){
      sendSerial("PWM_PELTIER,"+pwm);
      delay(50);
    }
    sendSerial("FOPID_OFF");

    // Reset de variables de estado e interpolación
    pwmPeltier = 0;
    prevPwmPeltier = nextPwmPeltier = 0;
    prevTsup = nextTsup = Tref;
    prevTdew = nextTdew = Tdew;
    interpTimer = 0;

    // Reset de listas de datos
    histTsup.clear(); 
    histTdew.clear(); 
    histPeltier.clear(); 
    histFan.clear(); 
    histTime.clear();

    // Reset de parámetros FOPID
    Kp = Ki = Kd = 0;
    lambda = 0.67f; 
    mu = 1.47f; 
    Kff = 0;

    // Actualizar GUI
    txtKp.setText(nf(Kp,1,3));
    txtKi.setText(nf(Ki,1,3));
    txtKd.setText(nf(Kd,1,3));
    txtLam.setText(nf(lambda,1,3));
    txtMu.setText(nf(mu,1,3));
    txtKff.setText(nf(Kff,1,3));

    btnStart.setLabel("Iniciar ensayo").setColorBackground(color(120,160,140));
  }
}


void toggleFan(){
  fanManual=!fanManual;
  if(fanManual){
    sendSerial("PWM_MANUAL_FAN,255");
    btnFanToggle.setLabel("Ventilador ON").setColorBackground(color(102,205,170));
    pwmFan=255;
  } else {
    sendSerial("FAN_MANUAL_OFF");
    btnFanToggle.setLabel("Ventilador OFF").setColorBackground(color(160,190,200));
    pwmFan=0;
  }
}

void toggleMode(){
  showTdew=!showTdew;
  btnModeToggle.setLabel(showTdew?"Modo: Rocío":"Modo: Consigna");
  if(showTdew) sendSerial("MODE_TDEW_ON");
  else sendSerial("MODE_TDEW_OFF");
}

// ================== Serial ==================
void serialEvent(Serial p){
  String line = p.readStringUntil('\n');
  if(line == null) return;
  line = trim(line);
  if(line.length() == 0) return;

  // ================== DATOS DESDE ARDUINO ==================
  if(Character.isDigit(line.charAt(0)) || line.charAt(0)=='-' || line.charAt(0)=='.'){
    String[] vals = split(line, ',');
    if(vals.length >= 6){
      try{
        prevTsup = Tsup;
        prevTdew = Tdew;
        prevPwmPeltier = pwmPeltier;

        Tamb           = Float.parseFloat(vals[0].trim());
        nextTsup       = Float.parseFloat(vals[1].trim());
        RH             = Float.parseFloat(vals[2].trim());
        nextTdew       = Float.parseFloat(vals[3].trim());
        nextPwmPeltier = Float.parseFloat(vals[4].trim());
        pwmFan         = Float.parseFloat(vals[5].trim());

        interpTimer = 0;

        if(isLogging){
          float t = (millis() - startTime)/1000.0f;
          histTsup.add(nextTsup);
          histTdew.add(nextTdew);
          histPeltier.add(nextPwmPeltier);
          histFan.add(pwmFan);
          histTime.add(t);
          if(histTime.size() > 2000){
            histTsup.remove(0);
            histTdew.remove(0);
            histPeltier.remove(0);
            histFan.remove(0);
            histTime.remove(0);
          }
        }

        // ================== ENVÍO A PYTHON ==================
        if(socketOut != null && isLogging){
          String msg =
            Tamb + "," +
            nextTsup + "," +
            RH + "," +
            nextTdew + "," +
            nextPwmPeltier + "," +
            pwmFan + "," +
            Kp + "," +
            Ki + "," +
            Kd + "," +
            Kff + "," +
            lambda + "," +
            mu + "," +
            Tref;

          socketOut.println(msg);
        }

      } catch(Exception e){
        println("Error parseando Arduino: "+e);
      }
    }
  }
}

void readPythonSocket() {
  if(socketIn != null) {
    try {
      while(socketIn.ready()) {
        String nnLine = socketIn.readLine();
        if(nnLine == null) break;
        nnLine = nnLine.trim();
        if(nnLine.length() == 0) continue;

        String[] tokens = split(nnLine, ',');
        if(tokens.length != 6) continue;

        Kp     = Float.parseFloat(tokens[0].trim());
        Ki     = Float.parseFloat(tokens[1].trim());
        Kd     = Float.parseFloat(tokens[2].trim());
        lambda = Float.parseFloat(tokens[3].trim());
        mu     = Float.parseFloat(tokens[4].trim());
        Kff    = Float.parseFloat(tokens[5].trim());

        sendSerial("SET_KP," + Kp);
        sendSerial("SET_KI," + Ki);
        sendSerial("SET_KD," + Kd);
        sendSerial("SET_LAMBDA," + lambda);
        sendSerial("SET_MU," + mu);
        sendSerial("SET_KFF," + Kff);

        txtKp.setText(nf(Kp,1,3));
        txtKi.setText(nf(Ki,1,3));
        txtKd.setText(nf(Kd,1,3));
        txtLam.setText(nf(lambda,1,3));
        txtMu.setText(nf(mu,1,3));
        txtKff.setText(nf(Kff,1,3));
      }
    } catch(Exception e){
      println("Error leyendo Python: " + e);
    }
  }
}

// ================== Enviar datos al Arduino ==================
void sendSerial(String msg){
  if(myPort != null){
    myPort.write(msg + "\n");
    println("Enviado: " + msg);
  } else {
    println("No puerto serie: " + msg);
  }
}

// ================== Guardado CSV ==================
void saveCSV(){
  String nombre = txtEnsayoNombre.getText().trim();
  if(nombre.equals("")) nombre = "ensayo_"+ensayoNumero;

  String filename = nombre + "_" + nf(ensayoNumero,3) + ".csv";
  PrintWriter output = createWriter(filename);

  // ✅ Agregado Tref en el encabezado
  output.println("Tiempo,Tamb,Tsup,Tdew,RH,Tref,PWM_Peltier,PWM_Fan,Kp,Ki,Kd,Lambda,Mu,Kff");

  for(int i=0;i<histTime.size();i++){
    output.println(
      histTime.get(i) + "," +
      Tamb + "," +
      histTsup.get(i) + "," +
      histTdew.get(i) + "," +
      RH + "," +
      Tref + "," + // ✅ Agregado Tref aquí
      histPeltier.get(i) + "," +
      histFan.get(i) + "," +
      Kp + "," +
      Ki + "," +
      Kd + "," +
      lambda + "," +
      mu + "," +
      Kff
    );
  }

  output.flush();
  output.close();
  println("CSV guardado: " + filename);
}


// ================== Guardado Imagen ==================
void saveGraphImage(){
  // Código de guardado de imagen
}

// ================== Cierre de sockets ==================
public void dispose(){
  try{
    if(socketOut != null) socketOut.close();
    if(socketIn != null) socketIn.close();
    if(socket != null) socket.close();
  }catch(Exception e){}
  super.dispose();
}

// ================== Enviar datos al Python ==================
void sendSocket(String msg){
  if(socketOut != null){
    socketOut.println(msg);
    println("Enviado a Python: " + msg);
  }
}

void controlEvent(ControlEvent e) {
  // Detecta cambios en txtTref
  if (e.isFrom(txtTref)) {
    try {
      float newTref = Float.parseFloat(txtTref.getText().trim());
      sendSerial("SET_TREF," + newTref);
      Tref = newTref;
      println("Nueva consigna enviada: " + newTref);
    } catch (Exception ex) {
      println("Error leyendo Tref");
    }
  }
}
