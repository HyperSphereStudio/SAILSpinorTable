/**********************************************************************
   NAME: TransmittingFeather.ino

   PURPOSE: Spin Table - Monitoring Angular Speed.

   DEVELOPMENT HISTORY:
     Date    Author  Version            Description Of Change
   --------  ------  -------  ---------------------------------------
   04/12/23   KOO      1.0     Code for basic radio communication of IMU data
   04/24/23   KOO      1.1     Updated to transmit measured IMU data
   06/12/23   JCB      2.0     3Feather with Medium Level Network Library (Simple) Implementation.
   12/06/23   JCB      3.0     Upgraded System, Stripped Complexity and Decreased Lag
 *********************************************************************/

/*Override std print to divert to Computer
  Put this before the feather lib so that we can read errors from device */

//#define DEBUG

void radio_print(const char* fmt, ...);
#define print(fmt, ...) radio_print(fmt, ##__VA_ARGS__)
#define printtx(fmt, ...) print("[Tx]:" fmt, ##__VA_ARGS__)
#define printtxln(fmt, ...) println("[Tx]:" fmt, ##__VA_ARGS__)

#include <SimpleConnection.hpp>
#include <SimpleTimer.hpp>
#include <devices/SimpleFeather.hpp>

// The SFE_LSM9DS1 library requires both Wire and SPI to be
// included BEFORE including the SparkFunLSM9DS1 library.
#include <Wire.h>
#include <SPI.h>
#include <SparkFunLSM9DS1.h>

#define RFM95_Slave 8
#define RFM95_Reset 4
#define RFM95_Interrupt 3
#define RF95_FREQ 933.0
#define RF95_POWER 21
#define TxFreq 50 //ms
#define CutPin 5

enum PacketType : uint8_t{
  AccelerationPacket = 1,
  ComputerPrint,
  SetMotorSpeed,
  Cut
};

enum Device : uint8_t{
/*  Rxer = 0,
  Txer,
  Ctrlr
*/
  Master = 0,
  Txer  
};

//Implementation of a feather radio connection
struct TxRxRadioConnection : public RadioConnection{
  TxRxRadioConnection() : RadioConnection(RFM95_Slave, RFM95_Interrupt, RFM95_Reset, 256) { SetAddress(Txer); }

  void SendPacket(RadioPacket* p){
    p->SeekStart();
    Send(p);
  }

  void Receive(RadioPacket* io) final;
};

LSM9DS1 imu;
TxRxRadioConnection tx;
Timer packetTimer(true, 500), cutTimer(false, 1000);
RadioPacket rp1 = RadioPacket(256);

//Simple::Printf implementation stream to Rx
void radio_print(const char* fmt, ...){
  va_list args;
  va_start(args, fmt);

  rp1.config(Master, PacketType::ComputerPrint);
  rp1.vPrintf((char*) fmt, args);
  tx.SendPacket(&rp1);

  debugOnly( Out.vPrintf((char*) fmt, args); )

  va_end(args);
}

void setup() {
  Serial.begin(9600);
 // debugOnly(while (!Serial) { delay(5); })

  pinMode(CutPin, OUTPUT);
  digitalWrite(CutPin, LOW);

  if(!tx.Initialize(RF95_FREQ, RF95_POWER, Range::Medium)){
    Serial.printf("LoRa Radio Initialization Failed!");
    return;
  }
  delay(100);
  printtxln("LoRa Radio Okay!");

  cutTimer.callback = make_static_lambda(void, (Timer& t), digitalWrite(CutPin, LOW));

  packetTimer.callback = make_static_lambda(void, (Timer& t), {
    float Gz = imu.calcGyro(imu.gz);
/*  
    float Gx = imu.calcGyro(imu.gx);
    float Gy = imu.calcGyro(imu.gy);  
    float Ax = imu.calcAccel(imu.ax);
    float Ay = imu.calcAccel(imu.ay);
    float Az = imu.calcAccel(imu.az);
    float Mx = imu.calcMag(imu.mx);
    float My = imu.calcMag(imu.my);
    float Mz = imu.calcMag(imu.mz);
*/
    rp1.config(Master, PacketType::AccelerationPacket);
    rp1.WriteStd(Gz);
    tx.SendPacket(&rp1);

    Serial.printf("Sent Packet! \n");
  });

  Wire.begin();      //With no arguments, this uses default addresses (AG:0x6B, M:0x1E) and i2c port (Wire).
  if (!imu.begin()){
    printtxln("LSM9DS1 Init Fail!");
  }else{
    imu.setGyroScale(2000);
    printtxln("Starting Packet Transmission");

    packetTimer.Start();
    tx.Start();
  }
}

void loop() { 
    // Update the sensor values whenever new data is available
    if (imu.gyroAvailable())
      imu.readGyro();

    if (imu.accelAvailable())
      imu.readAccel();

    if (imu.magAvailable())
      imu.readMag();

  //Update connections & timers	
  Yield();
}

//Method called when a packet from the Feather Connection Pool is received
void TxRxRadioConnection::Receive(RadioPacket* p) {
  switch(p->id){
      case Cut:
        digitalWrite(CutPin, HIGH);
        cutTimer.Start();
        break;
  }
}
