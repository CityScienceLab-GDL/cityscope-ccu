# CityScope@Guadalajara

This is the repository for the CityScope implementation for the University Cultural District in Guadalajara.

We describe each of the indicators in the following document (work in progress, in spanish):
https://docs.google.com/document/d/11-tBWJIrPP4n7MY_YY8PRk199f8zGyrLWelPygVYas0/edit


Instructions:

1. Download Gama platform 1.9 (https://gama-platform.org/download) and install it on your computer.
2. Clone this github repository (branch "master").
3. Open Gama Platform and select as a workspace the directory where you cloned the repository.
4. Open the model "CityScope.gaml".
5. In case you are using an external method to update the simulation, use mqtt. Download an MQTT server and keep it running (for example:https://mosquitto.org/download/ ). Change the variable enable_mqtt to true.
6. Clic on Run CityScope.