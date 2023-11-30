/**********************************************************************
   NAME: ControlFeather.ino
   PURPOSE: Spin Table - Control the spin table (flow commands through/from the Pololu).
   DEVELOPMENT HISTORY:
     Date    Author  Version            Description Of Change
   --------  ------  -------  ---------------------------------------
   06/12/23   JCB      2.0     3Feather with Medium Level Network Library (Simple) Implementation.
 *********************************************************************/

/*Override std print to divert to computer
  Put this before the feather lib so that we can read errors from device code*/
void radio_print(const char* fmt, ...);
#define print(fmt, ...) radio_print(fmt, ##__VA_ARGS__)
#define printct(fmt, ...) print("[Cntrl]:" fmt, ##__VA_ARGS__)
#define printctln(fmt, ...) println("[Cntrl]:" fmt, ##__VA_ARGS__)

#include <SimpleConnection.hpp>
#include <SimpleTimer.hpp>
#include <devices/SimpleFeather.hpp>

#define Retries 3
#define NodeTimeout 50

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
  Ctrlr,
  DeviceCount
};


// Implementation of a feather radio connection which provides Time Divison Multiplexor Access and other tools to minimize error & maximize transmission speed
struct CntrlRxRadioConnection : public RadioConnection{
  CntrlRxRadioConnection() : RadioConnection(Ctrlr, DeviceCount, NodeTimeout, Retries, RFM95_Slave, RFM95_Interrupt, RFM95_Reset){}
  void onPacketReceived(PacketInfo& info, IOBuffer& io) final;
  void onPacketCorrupted(PacketInfo& info) final{}
  bool HandlePacket(PacketInfo &info, IOBuffer &io) final;
};

CntrlRxRadioConnection cntrl;
StreamIO controller(Serial1);	//Stream Wrapper over the Controller UART

//Used to control the motor if the Rx loses connection. Itll automatically stop the motor after 2.5 s
Timer packetTimer(true, 2500);

//Simple::Printf implementation stream to Rx
void radio_print(const char* fmt, ...){
  va_list args;
  va_start(args, fmt);
  define_local_lambda(lam, capture(=, &args), void, (IOBuffer& io), io.vPrintf((char*) fmt, args));
  cntrl.SendData(Rxer, PacketType::ComputerPrint, lam);
  va_end(args);
}

void stop_motor(){
	controller.Write((int8_t) 0xC2, (int8_t) 0);
}

void setup() {
  //The controller is connected to Serial1
  Serial1.begin(19200); //Controller baud
   
  if(!cntrl.Initialize(RF95_FREQ, RF95_POWER, Range::Short)){
    while (!Serial) { delay(5); }
    Serial.printf("LoRa Radio Initialization Failed!");
    return;
  }

  packetTimer.callback = make_static_lambda(void, (Timer& t), {
    stop_motor();
    printctln("Motor Emergency Stop!");
  });
  
  //Listen to the port
  cntrl.Start();
  packetTimer.Start();	//Start the timer
  printctln("LoRa Radio Init Ok");
}

void loop() {
  //Update connections & timers	
  Yield();
  
  /*if(controller.BytesAvailable() > 0){
    cntrl.SendData(ControllerRead, lambda(void, (IOBuffer& io), {
      while(controller.BytesAvailable() > 0)
        controller.WriteTo(&io);    //Send the data to the Rx
    }));
  } */
}

//Method called when a packet from the Feather Connection Pool is received
void CntrlRxRadioConnection::onPacketReceived(PacketInfo& info, IOBuffer& io){
  switch(info.Type){
    case ControllerWrite:
      io.WriteTo(controller, info.Size);    //Forward commands from the Rx to the controller
      break;
  }
}

bool CntrlRxRadioConnection::HandlePacket(PacketInfo &info, IOBuffer &io){
  packetTimer.Reset();
  return RadioConnection::HandlePacket(info, io);	//Let the default packet handler figure out how to handle internal packets
}