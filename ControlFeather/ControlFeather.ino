/**********************************************************************
   NAME: ControlFeather.ino
   PURPOSE: Spin Table - Control the spin table (flow commands through/from).
   DEVELOPMENT HISTORY:
     Date    Author  Version            Description Of Change
   --------  ------  -------  ---------------------------------------
   06/12/23   JCB      2.0     New Packet Protocol, 3 Feather Communication & Control, Julia Interface
 *********************************************************************/

/*Override std print to divert to Computer
  Put this before the feather lib so that we can read errors from device */
void radio_print(const char* fmt, ...);
#define print(fmt, ...) radio_print(fmt, ##__VA_ARGS__)
#define printct(fmt, ...) print("[Cntrl]:" fmt, ##__VA_ARGS__)
#define printctln(fmt, ...) println("[Cntrl]:" fmt, ##__VA_ARGS__)

#include <SimpleConnection.h>
#include <SimpleTimer.h>
#include <devices/SimpleFeather.h>

#define Retries 5
#define RetryTimeOut 50
#define NodeTimeout 10

#include <SPI.h>
#include <RH_RF95.h>
#define RFM95_Slave 8
#define RFM95_Reset 4
#define RFM95_Interrupt 3
#define RF95_FREQ 915.0
#define RF95_POWER 23

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

struct CntrlRxRadioConnection : public RadioConnection{
  CntrlRxRadioConnection() : RadioConnection(Ctrlr, Retries, RetryTimeOut, RFM95_Slave, RFM95_Interrupt, RFM95_Reset){}
    void onPacketReceived(PacketInfo& info, IOBuffer& io) final;
  void onPacketCorrupted(PacketInfo& info) final{}
};

CntrlRxRadioConnection cntrl;
StreamIO controller(Serial1);

void radio_print(const char* fmt, ...){
  va_list args;
  va_start(args, fmt);
  define_local_lambda(lam, capture(=, &args), void, (IOBuffer& io), io.vPrintf((char*) fmt, args));
  cntrl.SendData(Rxer, PacketType::ComputerPrint, lam);
  va_end(args);
}

void setup() {
  Serial1.begin(19200); //Controller baud

  if(!cntrl.Initialize(RF95_FREQ, RF95_POWER, Range::Short)){
    while (!Serial) { delay(5); }
    Serial.printf("LoRa Radio Initialization Failed!");
    return;
  }

  cntrl.Start();
  printctln("LoRa Radio Init Ok");
}

void loop() { 
  Yield();
  /*if(controller.BytesAvailable() > 0){
    cntrl.SendData(ControllerRead, lambda(void, (IOBuffer& io), {
      while(controller.BytesAvailable() > 0)
        controller.WriteTo(&io);    //Send the data to the Rx
    }));
  } */
}

void CntrlRxRadioConnection::onPacketReceived(PacketInfo& info, IOBuffer& io){
  switch(info.Type){
    case ControllerWrite:
      io.WriteTo(controller, info.Size);    //Forward to the controller
      printctln("Write!");
      break;
  }
}