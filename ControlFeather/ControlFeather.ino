/**********************************************************************
   NAME: ControlFeather.ino
   PURPOSE: Spin Table - Control the spin table (flow commands through/from).
   DEVELOPMENT HISTORY:
     Date    Author  Version            Description Of Change
   --------  ------  -------  ---------------------------------------
   06/12/23   JCB      2.0     New Packet Protocol, 3 Feather Communication & Control, Julia Interface
 *********************************************************************/

#include <SimpleConnection.h>
#include <SimpleTimer.h>

/*Override std print to divert to Computer
  Put this before the feather lib so that we can read errors from device */
void radio_print(const char* fmt, ...);
#undef print
#define print(fmt, ...) radio_print("[Cntrl]:" fmt, ##__VA_ARGS__)

#include <devices/SimpleFeather.h>

#define DeviceID 2
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

struct ExternalSerialIO : public IO{
    int WriteByte(uint8_t b) final { return Serial1.write(b); }
    int WriteBytes(void *ptr, int nbytes) final { return Serial1.write((uint8_t*) ptr, nbytes); }
    int ReadByte() final { return Serial1.read(); }
    int ReadBytesUnlocked(void *ptr, int buffer_size) final { return Serial1.readBytes((char*) ptr, buffer_size); }
    int BytesAvailable() final { return Serial1.available(); }
};

struct CntrlRxRadioConnection : public RadioConnection{
  CntrlRxRadioConnection() : RadioConnection(DeviceID, NodeTimeOut, RFM95_Slave, RFM95_Interrupt, RFM95_Reset){}
  void onPacketReceived(MultiPacketHeader header, IOBuffer& io) final;
  void onPacketCorrupted(MultiPacketHeader header) final{}
};

CntrlRxRadioConnection cntrl;
ExternalSerialIO controller;

void radio_print(const char* fmt, ...){
  va_list args;
  va_start(args, fmt);
  cntrl.SendData(PacketType::ComputerPrint, lambda(void, (IOBuffer& io, char* fmt, va_list v), io.vPrintf(fmt, v)), (char*) fmt, args);
  va_end(args);
}

void setup() {
  Serial1.begin(19200); //Controller baud

  if(!cntrl.Initialize(RF95_FREQ, 23)){
    while (!Serial) { delay(5); }
    Serial.printf("LoRa Radio Initialization Failed!");
    return;
  }
}

void loop() { 
  Yield();
  if(controller.BytesAvailable() > 0){
     cntrl.SendData(ControllerRead, lambda(void, (IOBuffer& io), {
        while(controller.BytesAvailable() > 0)
          controller.WriteTo(&io);    //Send the data to the Rx
     }));
  } 
}

void CntrlRxRadioConnection::onPacketReceived(MultiPacketHeader header, IOBuffer& io){
  switch(header.type){
    case ControllerWrite:
      io.WriteTo(controller, header.size);    //Forward to the controller
      break;
  }
}