/**********************************************************************
   NAME: DrivingFeather.ino

   PURPOSE: Spin Table - Monitoring Angular Speed.

   DEVELOPMENT HISTORY:
     Date    Author  Version            Description Of Change
   --------  ------  -------  ---------------------------------------
   04/12/23   KOO      1.0     Code for basic radio communication of IMU data
   04/24/23   KOO      1.1     Reformatted to allow external Matlab interaction
   06/12/23   JCB      2.0     New Packet Protocol, 3 Feather Communication & Control, Julia Interface
 *********************************************************************/

#include <SimpleConnection.h>
#include <SimpleTimer.h>

/*Override std print to divert to Computer
  Put this before the feather lib so that we can read errors from device */
void serial_print(const char* fmt, ...);
#undef print
#define print(fmt, ...) serial_print("[Rx]:" fmt, ##__VA_ARGS__)

#include <devices/SimpleFeather.h>

#define DeviceID 0
#define NodeTimeOut 10

#include <SPI.h>
#include <RH_RF95.h>
#define RFM95_Slave 8
#define RFM95_Reset 4
#define RFM95_Interrupt 3
#define RF95_FREQ 915.0  //Must match to Txer

enum PacketType{
  AccelerationPacket = 1,
  ComputerPrint = 2,
  SetTxState = 3,
  ControllerWrite = 4,
  ControllerRead = 5,
  Cut = 6
};

struct RxCompConnection : public SerialConnection{
  void onPacketReceived(PacketHeader header, IOBuffer& io) final;
  void onPacketCorrupted(PacketHeader header) final{}
};

struct TxRxRadioConnection : public RadioConnection{
  TxRxRadioConnection() : RadioConnection(DeviceID, NodeTimeOut, RFM95_Slave, RFM95_Interrupt, RFM95_Reset){}
  void onPacketReceived(MultiPacketHeader header, IOBuffer& io) final;
  void onPacketCorrupted(MultiPacketHeader header) final{}
};

RxCompConnection computer;
TxRxRadioConnection rx;

void serial_print(const char* fmt, ...){
  va_list args;
  va_start(args, fmt);
  computer.SendData(PacketType::ComputerPrint, lambda(void, (IOBuffer& io, char* fmt, va_list v), io.vPrintf(fmt, v)), (char*) fmt, args);
  va_end(args);
}

void setup() {
  Serial.begin(115200);
  while (!Serial) { delay(5); }
  
  if(rx.Initialize(RF95_FREQ, 23))
    println("LoRa Radio Init Ok!");
  else 
    println("LoRa Radio Init Failed!");

  computer.Start();  
}

void loop() {
  Yield();
}

void RxCompConnection::onPacketReceived(PacketHeader header, IOBuffer& io){
  switch(header.type){
    case PacketType::SetTxState:
      rx.SendData(PacketType::SetTxState, &io, header.size);
      break;
    case PacketType::ControllerWrite:
      rx.SendData(PacketType::ControllerWrite, &io, header.size); //Have to send over same frequency, its lightweight though
      break;
  } 
}

void TxRxRadioConnection::onPacketReceived(MultiPacketHeader header, IOBuffer &io){
  switch(header.type){
    case PacketType::ComputerPrint:     //Forward to the computer
    case PacketType::AccelerationPacket:
    case PacketType::ControllerRead:
      computer.SendData(header.type, &io, header.size);   
      break;
  }
}