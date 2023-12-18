/**********************************************************************
   NAME: DrivingFeather.ino

   PURPOSE: Spin Table - Monitoring Angular Speed.

   DEVELOPMENT HISTORY:
     Date    Author  Version            Description Of Change
   --------  ------  -------  ---------------------------------------
   04/12/23   KOO      1.0     Code for basic radio communication of IMU data
   04/24/23   KOO      1.1     Reformatted to allow external Matlab interaction
   06/12/23   JCB      2.0     3Feather with Medium Level Network Library (Simple) Implementation.
 *********************************************************************/

/*Override std print to divert to Computer
  Put this before the feather lib so that we can read errors from device */
void serial_print(const char* fmt, ...);
#define print(fmt, ...) serial_print(fmt, ##__VA_ARGS__)
#define printms(fmt, ...) print("[Master]:" fmt, ##__VA_ARGS__)
#define printmsln(fmt, ...) println("[Master]:" fmt, ##__VA_ARGS__)

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
  Cut,
  Heartbeat
};

enum Device : uint8_t{
  Master = 0,
  Txer
};

struct SimpleComputerPacket : public Packet{
  uint8_t id;

  SimpleComputerPacket(int capacity) : Packet(capacity){}

  void config(uint8_t type, bool reset=true){
    id = type;
    if(reset)
      Clear();
  }
};

struct MasterCompConnection;

struct MasterSimpleCompConnection : public SimpleConnection{
    MasterCompConnection* msc;
    MasterSimpleCompConnection(MasterCompConnection* c) : msc(c){}

    void ReceivedMessage(Packet* io) final;

    protected:
    void Write(IO* io) final;
};

//Extension of a serial connection for the computer to handle the packets
struct MasterCompConnection : public SerialConnection{
  friend MasterSimpleCompConnection;
  
  MasterSimpleCompConnection sc;

  MasterCompConnection() : sc(this), SerialConnection(256) {}

  void SendPacket(SimpleComputerPacket* p){
    p->InsertRange(0, 1);
    *p->Interpret(0) = p->id;    //Set first byte to be the id of the packet
    p->SeekStart();
    sc.Send(p);
  }

  void Receive(Packet* p) final { 
    sc.Receive(p); 
  }
};

//Implementation of a feather radio connection
struct MasterRadioConnection : public RadioConnection{

  MasterRadioConnection() : RadioConnection(RFM95_Slave, RFM95_Interrupt, RFM95_Reset, 256) { SetAddress(Master); }

    void SendPacket(RadioPacket* p){
      p->SeekStart();
      Send(p);
    }

  void Receive(RadioPacket* io) final;
};

MasterCompConnection computer;
MasterRadioConnection ms;
SimpleComputerPacket scp1 = SimpleComputerPacket(256);
MasterRadioConnection cntrl;
StreamIO controller(Serial1);	                          //Stream Wrapper over the Controller UART
RadioPacket rp1 = RadioPacket(256);

void setup() {
  Serial.begin(115200); //Serial baud
  Serial1.begin(19200); //Controller baud

  while (!Serial) { delay(5); }
  printmsln("Connected!");

  if(!ms.Initialize(RF95_FREQ, RF95_POWER, Range::Medium)){
    Serial.printf("LoRa Radio Initialization Failed!");
    return;
  }

  //Listen to the ports
  ms.Start(); 
  computer.Start(); 
  printmsln("Setup Okay!");
}

void loop() {
  Yield();            //Update connections & timers	
}

void serial_print(const char* fmt, ...){
  va_list args;
  va_start(args, fmt);
  
  scp1.config(PacketType::ComputerPrint);
  scp1.vPrintf((char*) fmt, args);
  computer.SendPacket(&scp1);

  va_end(args);
}

void MasterSimpleCompConnection::Write(IO* io){ msc->Write(io); }

void set_motor_speed(uint8_t speed){
  controller.Write((uint8_t) 0xC2, speed);
}

void stop_motor(){
  set_motor_speed(0);
}

//Method called when a packet from the computer is received
void MasterSimpleCompConnection::ReceivedMessage(Packet* p){
  auto id = p->ReadByte();
  switch(id){
    case PacketType::SetMotorSpeed:{
      set_motor_speed(p->Read<uint8_t>());
		  printmsln("Set Motor Speed!");
      break;
    }
  } 
}

//Method called when a packet from the Feather Connection Pool is received
void MasterRadioConnection::Receive(RadioPacket* p) {
  switch(p->id){
    case PacketType::ComputerPrint:     //Forward to the computer
    case PacketType::AccelerationPacket:
        scp1.config(p->id);
        scp1.ReadFrom(*p);
        computer.SendPacket(&scp1);
      break;  
  }
}