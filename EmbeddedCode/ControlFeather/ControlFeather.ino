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

//Uncomment to enter debug mode
//#define DEBUG

void radio_print(const char* fmt, ...);
#define print(fmt, ...) radio_print(fmt, ##__VA_ARGS__)
#define printct(fmt, ...) print("[Cntrl]:" fmt, ##__VA_ARGS__)
#define printctln(fmt, ...) println("[Cntrl]:" fmt, ##__VA_ARGS__)

#include <SimpleConnection.hpp>
#include <SimpleTimer.hpp>
#include <devices/SimpleFeather.hpp>

#include <SPI.h>
#include <RH_RF95.h>
#define RFM95_Slave 8
#define RFM95_Reset 4
#define RFM95_Interrupt 3
#define RF95_FREQ 933.0
#define RF95_POWER 21
#define TxFreq 50 //ms

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
struct CntrlRxRadioConnection : public RadioConnection{

  CntrlRxRadioConnection() : RadioConnection(RFM95_Slave, RFM95_Interrupt, RFM95_Reset, 256) { SetAddress(Ctrlr); }

    void SendPacket(RadioPacket* p){
      p->SeekStart();
      Send(p);
    }

  void Receive(RadioPacket* io) final;
};

CntrlRxRadioConnection cntrl;
StreamIO controller(Serial1);	//Stream Wrapper over the Controller UART

//Used to control the motor if the Rx loses connection. Itll automatically stop the motor after 5 s
Timer packetTimer(true, 5000);

RadioPacket rp1 = RadioPacket(256);

//Simple::Printf implementation stream to Rx
void radio_print(const char* fmt, ...){
  va_list args;
  va_start(args, fmt);

  rp1.config(Rxer, PacketType::ComputerPrint);
  rp1.vPrintf((char*) fmt, args);
  cntrl.SendPacket(&rp1);

  va_end(args);
}

void set_motor_speed(uint8_t speed){
  controller.Write((uint8_t) 0xC2, speed);
}

void stop_motor(){
  set_motor_speed(0);
}

void setup() {
  //The controller is connected to Serial1
  Serial1.begin(19200); //Controller baud

  debugOnly( while (!Serial) { delay(5); } )
   
  if(!cntrl.Initialize(RF95_FREQ, RF95_POWER, Range::Medium)){
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
void CntrlRxRadioConnection::Receive(RadioPacket* p) {
  packetTimer.Reset();
  switch(p->id){
    case CntrlSetMotorSpeed:
      set_motor_speed(p->Read<uint8_t>());
      break;
  }
}
