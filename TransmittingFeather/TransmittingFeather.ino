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

#include <SimpleConnection.h>
#include <SimpleTimer.h>

/*Override std print to divert to Computer
  Put this before the feather lib so that we can read errors from device */
void radio_print(const char* fmt, ...);
#undef print
#define print(fmt, ...) radio_print("[Gyro]:" fmt, ##__VA_ARGS__)

#include <devices/SimpleFeather.h>

#define DeviceID 1
#define NodeTimeOut 10

// The SFE_LSM9DS1 library requires both Wire and SPI to be
// included BEFORE including the SparkFunLSM9DS1 library.
#include <Wire.h>
#include <SPI.h>
#include <SparkFunLSM9DS1.h>

#define RFM95_Slave 8
#define RFM95_Reset 4
#define RFM95_Interrupt 3
#define RF95_FREQ 915.0  //Must match to Txer
#define CutPin 5

enum PacketType{
  AccelerationPacket = 1,
  ComputerPrint = 2,
  SetTxState = 3,
  ControllerWrite = 4,
  ControllerRead = 5,
  Cut = 6
};

enum TransmitterState : byte{
  None = 0,
  ReadyIdle = 1,
  GetData = 2,
  LSM9DS1Error = 3
};

struct TxRxRadioConnection : public RadioConnection{
  TxRxRadioConnection() : RadioConnection(DeviceID, NodeTimeOut, RFM95_Slave, RFM95_Interrupt, RFM95_Reset){}
  void onPacketReceived(MultiPacketHeader header, IOBuffer& io) final;
  void onPacketCorrupted(MultiPacketHeader header) final{}
};

LSM9DS1 imu;
TxRxRadioConnection tx;
TransmitterState state = TransmitterState::None;
Timer packetTimer(true, 250), cutTimer(false, 1000);

void radio_print(const char* fmt, ...){
  va_list args;
  va_start(args, fmt);
  tx.SendData(PacketType::ComputerPrint, lambda(void, (IOBuffer& io, char* fmt, va_list v), io.vPrintf(fmt, v)), (char*) fmt, args);
  va_end(args);
}

void setup() {
  pinMode(CutPin, OUTPUT);

  if(!tx.Initialize(RF95_FREQ, 23)){
    while (!Serial) { delay(5); }
    Serial.printf("LoRa Radio Initialization Failed!");
    return;
  }

  //With no arguments, this uses default addresses (AG:0x6B, M:0x1E) and i2c port (Wire).
  Wire.begin();
  if (!imu.begin())
    state = TransmitterState::LSM9DS1Error;

  cutTimer.callback = make_lambda<void, Timer&>([](Timer& t, void* args){ digitalWrite(CutPin, LOW); }, (void*) nullptr);

  packetTimer.callback = make_lambda<void, Timer&>([](Timer& t, void* args){
    // Update the sensor values whenever new data is available
    if (imu.gyroAvailable())
      imu.readGyro();

    if (imu.accelAvailable())
      imu.readAccel();

    if (imu.magAvailable())
      imu.readMag();

    float Gx = imu.calcGyro(imu.gx);
    float Gy = imu.calcGyro(imu.gy);
    float Gz = imu.calcGyro(imu.gz);
    float Ax = imu.calcAccel(imu.ax);
    float Ay = imu.calcAccel(imu.ay);
    float Az = imu.calcAccel(imu.az);
    float Mx = imu.calcMag(imu.mx);
    float My = imu.calcMag(imu.my);
    float Mz = imu.calcMag(imu.mz);
    tx.Send(PacketType::AccelerationPacket, Gx, Gy, Gz, Ax, Ay, Az, Mx, My, Mz); 
  }, (void*) nullptr);
}

void loop() { Yield(); }

void TxRxRadioConnection::onPacketReceived(MultiPacketHeader header, IOBuffer &io){
    switch(header.type){
      case SetTxState: {
        auto new_state = io.ReadStd<TransmitterState>();
        if(new_state == TransmitterState::ReadyIdle){
          packetTimer.Stop();
          println("Stop Acc Packets");
          state = TransmitterState::ReadyIdle;
        }else if(new_state == TransmitterState::GetData){
            if(state == TransmitterState::LSM9DS1Error)
              println("Failed to communicate with LSM9DS1.\nDouble-check wiring.");
            else{
               println("Start Acc Packets");
               packetTimer.Start();
               state = TransmitterState::GetData;
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