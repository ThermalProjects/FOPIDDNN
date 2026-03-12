# FOPIDDNN
This repository implements an experimental thermal control system combining a Fractional-Order PID (FOPID) controller with a deep neural network (DNN) for real-time adaptive tuning. The system is intended for laboratory experimentation, advanced control research, and evaluation of intelligent control strategies in thermal systems.

Fractional-Order PID controller enhanced with a Deep Neural Network (DNN) for adaptive online tuning of control parameters to improve thermal regulation under varying conditions.

FOPID WITH DEEP NEURAL NETWORK THERMAL CONTROL SYSTEM
This repository contains an experimental thermal control system based on a Fractional-Order PID (FOPID) controller integrated with a Deep Neural Network (DNN) adaptive layer. The system is designed for laboratory experimentation, research in advanced control, and performance evaluation of learning-based fractional-order controllers applied to thermal systems.

The implementation distributes real-time control, supervision, and DNN-based adaptation across multiple software layers, enabling stable operation at the plant level while allowing intelligent online parameter adjustment.

The overall implementation combines Arduino for real-time control, Processing for supervision and visualization, and Python for the DNN-based adaptive tuning.

SYSTEM OVERVIEW
The project implements a closed-loop temperature control system for a thermal cell actuated by a Peltier device and assisted by a cooling fan.
Temperature regulation is performed using a fractional-order PID controller on the Arduino. A Deep Neural Network implemented in Python receives real-time system data, predicts optimal controller parameters, and updates them via TCP/IP socket to Processing, which forwards them to Arduino.

Data and control flow:
Python (DNN Adaptive Supervisor) <-> TCP/IP Socket Processing (Supervision and Middleware) <-> Serial Communication Arduino (Real-Time Control and Plant)
This architecture decouples real-time control from adaptive learning, enhancing robustness, experiment safety, and reproducibility.

ARDUINO FUNCTIONALITY
The Arduino firmware handles real-time sensing, FOPID computation, and actuator driving.

Main functions:
Reads the thermal cell temperature using a thermistor
Reads ambient temperature and relative humidity using an SCD4x sensor
Computes dew-point temperature from ambient measurements
Executes the fractional-order PID algorithm using Grünwald–Letnikov approximation
Maintains fractional-order integral and derivative buffers
Applies thermal bias compensation to the reference temperature
Limits and ramps PWM signals for Peltier and fan protection
Controls the Peltier module and the cooling fan
Sends measured variables and actuator states via serial communication
Integrates with parameters received from the Python DNN supervisor
Control loop includes:
Defensive low-pass filtering of temperature
Anti-windup for fractional integral term
Regularization of fractional derivative term
Optional feedforward contribution from DNN output
Safe shutdown when control is disabled

PROCESSING FUNCTIONALITY
Processing acts as the central GUI and middleware between Arduino and Python.

Main features:
Graphical user interface for experiment configuration and real-time monitoring
Real-time visualization of temperatures, PWM outputs, and reference
Online configuration of FOPID parameters (Kp, Ki, Kd, λ, μ, Kff)
Reference mode selection: temperature setpoint or dew-point tracking
Manual or automatic fan control
Experiment timing and state management
Bidirectional communication with Python DNN via TCP/IP
Real-time logging and export to CSV for post-processing

PYTHON DNN ADAPTIVE SUPERVISOR
The Python module implements a Deep Neural Network that predicts optimal FOPID parameters based on real-time measurements.

Responsibilities:
Receives system state from Processing
Evaluates temperature error and dynamics
Predicts FOPID gains and fractional orders online
Sends updated parameters back to Processing for immediate application
Operates at a slower timescale than Arduino loop to maintain stability

REPOSITORY STRUCTURE
arduino – Arduino source code for FOPID control and data acquisition
processing – GUI, middleware, supervision, and logging
python – DNN adaptive supervisor and post-processing scripts
README.md, LICENSE, .gitignore

CONTROL MODES
Temperature setpoint control
Dew-point control based on ambient conditions
Output converted to PWM signals for Peltier and fan
Reference mode selectable from Processing interface

COMMUNICATION ARCHITECTURE
Arduino ↔ Processing: Serial for real-time control and measurement
Processing ↔ Python: TCP/IP sockets for DNN parameter updates
Data sent from Arduino: ambient temperature, cell temperature, relative humidity, dew point, PWM Peltier, PWM fan
Data sent to Arduino: FOPID gains, fractional orders, feedforward gain, control enable/disable, fan commands, reference mode
Data exchanged with Python: real-time measurements and predicted FOPID parameters

EXPERIMENTAL WORKFLOW
Executed from the Processing GUI:
Set temperature reference and initial FOPID parameters
Select reference mode (setpoint or dew-point)
Define experiment duration and name
Start the experiment and monitor parameters
Stop manually or automatically at the end
Automatic CSV export for post-processing

POST-PROCESSING AND ANALYSIS
Python scripts provided for performance evaluation:
Transient metrics: overshoot, settling time, ITAE
Steady-state error and thermal ripple
Control effort and energy consumption
Comparative analysis: PID vs FOPID vs FOPID+DNN
Publication-quality plotting

INTENDED USE
Laboratory experimentation in fractional-order and learning-based control
Research on neural-network-enhanced adaptive control

Experimental benchmarking of thermal control strategies

Modular architecture enables extension to reinforcement learning or model-based adaptive supervision
