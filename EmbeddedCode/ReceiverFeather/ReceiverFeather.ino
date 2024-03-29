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
#define printrx(fmt, ...) print("[Rx]:" fmt, ##__VA_ARGS__)
#define printrxln(fmt, ...) println("[Rx]:" fmt, ##__VA_ARGS__)

#include <SimpleConnection.hpp>
#include <SimpleTimer.hpp>
#include <devices/SimpleFeather.hpp>

#define RFM95_Slave 8
#define RFM95_Reset 4
#define RFM95_Interrupt 3
#define RF95_FREQ 933.0
#define RF95_POWER 21

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

struct SimpleComputerPacket : public Packet{
  uint8_t id;

  SimpleComputerPacket(int capacity) : Packet(capacity){}

  void config(uint8_t type, bool reset=true){
    id = type;
    if(reset)
      Clear();
  }
};

struct RxCompConnection;

struct RxSimpleCompConnection : public SimpleConnection{
    RxCompConnection* rxc;
    RxSimpleCompConnection(RxCompConnection* c) : rxc(c){}

    void ReceivedMessage(Packet* io) final;

    protected:
    void Write(IO* io) final;
};

//Extension of a serial connection for the computer to handle the packets
struct RxCompConnection : public SerialConnection{
  friend RxSimpleCompConnection;
  
  RxSimpleCompConnection sc;

  RxCompConnection() : sc(this), SerialConnection(256) {}

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

Timer heartBeat(true, 2000);    //Used to prevent motor from turning off from losing connection

//Implementation of a feather radio connection
struct RxRxRadioConnection : public RadioConnection{
  RxRxRadioConnection() : RadioConnection(RFM95_Slave, RFM95_Interrupt, RFM95_Reset, 256) { SetAddress(Rxer); }

  void SendPacket(RadioPacket* p){
    if(p->to == Ctrlr)
      heartBeat.Reset();

    p->SeekStart();
    Send(p);
  }

  void Receive(RadioPacket* io) final;
};

RxCompConnection computer;
RxRxRadioConnection rx;
SimpleComputerPacket scp1 = SimpleComputerPacket(256);
RadioPacket rp1 = RadioPacket(256);

void serial_print(const char* fmt, ...){
  va_list args;
  va_start(args, fmt);
  
  scp1.config(PacketType::ComputerPrint);
  scp1.vPrintf((char*) fmt, args);
  computer.SendPacket(&scp1);

  va_end(args);
}

void setup() {
  Serial.begin(115200);
  while (!Serial) { delay(5); }
  printrxln("Connected!");

  if(rx.Initialize(RF95_FREQ, RF95_POWER, Range::Medium))
    printrxln("LoRa Radio Init Ok!");
  else 
    printrxln("LoRa Radio Init Failed!");

 heartBeat.callback = make_static_lambda(void, (Timer& t), {
    rp1.config(Ctrlr, PacketType::Heartbeat);
    rx.SendPacket(&rp1);
    printrxln("Heartbeat");
  });

//Listen to the ports
  rx.Start(); 
  computer.Start(); 
  heartBeat.Start();	//Start the timer

  printrxln("Setup Okay!");
}

void loop() { 
  Yield();            //Update connections & timers	
}

void RxSimpleCompConnection::Write(IO* io){ rxc->Write(io); }

//Method called when a packet from the computer is received
void RxSimpleCompConnection::ReceivedMessage(Packet* p){
  auto id = p->ReadByte();
  switch(id){
    case PacketType::CntrlSetMotorSpeed:{
	    rp1.config(Ctrlr, PacketType::CntrlSetMotorSpeed);
		  rp1.ReadFrom(*p);
		  rx.SendPacket(&rp1);
		  printrxln("Set Motor Speed!");
      break;
    }
  } 
}

//Method called when a packet from the Feather Connection Pool is received
void RxRxRadioConnection::Receive(RadioPacket* p) {
  switch(p->id){
    case PacketType::ComputerPrint:     //Forward to the computer
    case PacketType::AccelerationPacket:
        scp1.config(p->id);
        scp1.ReadFrom(*p);
        computer.SendPacket(&scp1);
      break;  
  }
}