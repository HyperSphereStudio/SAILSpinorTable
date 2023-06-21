/**********************************************************************
   NAME: TransmittingFeather.ino

   PURPOSE: Spin Table - Monitoring Angular Speed.

   DEVELOPMENT HISTORY:
     Date    Author  Version            Description Of Change
   --------  ------  -------  ---------------------------------------
   04/12/23   KOO      1.0     Code for basic radio communication of IMU data
   04/24/23   KOO      1.1     Updated to transmit measured IMU data
   06/13/23   JCB      2.0     New Packet Protocol, 3 Feather Communication & Control, Julia Interface
 *********************************************************************/

/*Override std print to divert to Computer
  Put this before the feather lib so that we can read errors from device */

void radio_print(const char* fmt, ...);
#define print(fmt, ...) radio_print(fmt, ##__VA_ARGS__)
#define printtx(fmt, ...) print("[Tx]:" fmt, ##__VA_ARGS__)
#define printtxln(fmt, ...) println("[Tx]:" fmt, ##__VA_ARGS__)

#include <SimpleConnection.h>
#include <SimpleTimer.h>
#include <devices/SimpleFeather.h>

#define Retries 3
#define RetryTimeOut 50
#define NodeTimeout 10

// The SFE_LSM9DS1 library requires both Wire and SPI to be
// included BEFORE including the SparkFunLSM9DS1 library.
#include <Wire.h>
#include <SPI.h>
#include <SparkFunLSM9DS1.h>

#define RFM95_Slave 8
#define RFM95_Reset 4
#define RFM95_Interrupt 3
#define RF95_FREQ 915.0
#define RF95_POWER 23
#define CutPin 5

enum PacketType : uint8_t{
  AccelerationPacket = 1,
  ComputerPrint,
  SetTxState,
  ControllerWrite,
  ControllerRead,
  Cut
};

enum Device : uint8_t{
  Rxer = 0,
  Txer,
  Ctrlr
};

enum TransmitterState : byte{
  None = 0,
  ReadyIdle = 1,
  GetData = 2,
  LSM9DS1Error = 3
};

struct TxRxRadioConnection : public RadioConnection{
  TxRxRadioConnection() : RadioConnection(Txer, Retries, RetryTimeOut, RFM95_Slave, RFM95_Interrupt, RFM95_Reset){}
  void onPacketReceived(PacketInfo& info, IOBuffer& io) final;
  void onPacketCorrupted(PacketInfo& info) final{}
  bool CanWritePacket(PacketInfo &pi, bool &dispose) override { 
    //Always throw away the data
    dispose = true;
    return true;
  }
};

LSM9DS1 imu;
TxRxRadioConnection tx;
TransmitterState state = TransmitterState::None;
Timer packetTimer(true, 250), cutTimer(false, 1000);

void radio_print(const char* fmt, ...){
  va_list args;
  va_start(args, fmt);
  define_local_lambda(lam, capture(=, &args), void, (IOBuffer& io), io.vPrintf((char*) fmt, args));
  tx.SendData(Rxer, PacketType::ComputerPrint, lam);
  va_end(args);
}

void setup() {
  pinMode(CutPin, OUTPUT);

  if(!tx.Initialize(RF95_FREQ, RF95_POWER, Range::Short)){
    while (!Serial) { delay(5); }
    Serial.printf("LoRa Radio Initialization Failed!");
    return;
  }
  delay(100);
  printtxln("LoRa Radio Okay!");

  tx.DeviceCount = 3;
  tx.NodeReadTimeOut = NodeTimeout;

  //With no arguments, this uses default addresses (AG:0x6B, M:0x1E) and i2c port (Wire).
  Wire.begin();
  if (!imu.begin())
    state = TransmitterState::LSM9DS1Error;
  imu.setGyroScale(2000);  

  cutTimer.callback = make_static_lambda(void, (Timer& t), digitalWrite(CutPin, LOW));

  packetTimer.callback = make_static_lambda(void, (Timer& t), {
    float Gx = imu.calcGyro(imu.gx);
    float Gy = imu.calcGyro(imu.gy);
    float Gz = imu.calcGyro(imu.gz);
    float Ax = imu.calcAccel(imu.ax);
    float Ay = imu.calcAccel(imu.ay);
    float Az = imu.calcAccel(imu.az);
    float Mx = imu.calcMag(imu.mx);
    float My = imu.calcMag(imu.my);
    float Mz = imu.calcMag(imu.mz);
    tx.Send(Rxer, PacketType::AccelerationPacket, Gx, Gy, Gz, Ax, Ay, Az, Mx, My, Mz); 
  });

  tx.Start();
}

void loop() { 
  // Update the sensor values whenever new data is available
  if (imu.gyroAvailable())
    imu.readGyro();

  if (imu.accelAvailable())
    imu.readAccel();

  if (imu.magAvailable())
    imu.readMag();
  Yield();
}

void TxRxRadioConnection::onPacketReceived(PacketInfo& info, IOBuffer &io){
    switch(info.Type){
      case SetTxState: {
        auto new_state = io.ReadStd<TransmitterState>();
        if(new_state == TransmitterState::ReadyIdle){
          packetTimer.Stop();
          state = TransmitterState::ReadyIdle;
          printtxln("Data Stop!");
        }else if(new_state == TransmitterState::GetData){
            if(state == TransmitterState::LSM9DS1Error)
              printtxln("Failed to communicate with LSM9DS1. Double-check wiring.");
            else{
               packetTimer.Start();
               state = TransmitterState::GetData;
               printtxln("Data Start");
            }
        }
        break;
      }
      case Cut:
        digitalWrite(CutPin, HIGH);
        cutTimer.Start();
        break;
  }
}