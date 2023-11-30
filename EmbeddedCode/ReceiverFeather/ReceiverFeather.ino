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

#define Retries 5
#define NodeTimeout 50

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

//Extension of a serial connection for the computer to handle the packets
struct RxCompConnection : public SerialConnection{
  void onPacketReceived(PacketInfo& info, IOBuffer& io) final;
  void onPacketCorrupted(PacketInfo& info) final{}
};

// Implementation of a feather radio connection which provides Time Divison Multiplexor Access and other tools to minimize error & maximize transmission speed
struct TxRxRadioConnection : public RadioConnection{
  TxRxRadioConnection() : RadioConnection(Rxer, DeviceCount, NodeTimeout, Retries, RFM95_Slave, RFM95_Interrupt, RFM95_Reset){
    setSyncInterval(1000);	//This is important for packet time sync. ONLY THE RX SHOULD SEND SYNC PACKETS!!!!!!!!!!!!!!
  }
  void onPacketReceived(PacketInfo& info, IOBuffer& io) final;
  void onPacketCorrupted(PacketInfo& info) final{}
  bool HandlePacket(PacketInfo &info, IOBuffer &io) override{
    switch(info.Type){
      case ComputerPrint:
      case AccelerationPacket:	//This packet is sent way to often and tracking it could create a memory crash for the poor little feather memory :/
      case ControllerRead:
        return false;  //Bypass default handler that will generate a Rx Packet, but also dont mark handled
      default:
        return RadioConnection::HandlePacket(info, io);
    }
  }
};

RxCompConnection computer;
TxRxRadioConnection rx;

void serial_print(const char* fmt, ...){
  va_list args;
  va_start(args, fmt);
  define_local_lambda(lam, capture(=, &args), void, (IOBuffer& io), io.vPrintf((char*) fmt, args));
  computer.SendData(PacketType::ComputerPrint, lam);
  va_end(args);
}

void setup() {
  Serial.begin(115200);
  while (!Serial) { delay(5); }

  if(rx.Initialize(RF95_FREQ, RF95_POWER, Range::Short))
    printrxln("LoRa Radio Init Ok!");
  else 
    printrxln("LoRa Radio Init Failed!");

//Listen to the ports
  rx.Start(); 
  computer.Start();  
}

void loop() { 
  //Update connections & timers	
  Yield();
}

//Method called when a packet from the computer is received
void RxCompConnection::onPacketReceived(PacketInfo& info, IOBuffer& io){
  switch(info.Type){
    case PacketType::SetTxState:
      rx.SendData(Txer, PacketType::SetTxState, io, info.Size);
      break;
    case PacketType::ControllerWrite:
      rx.SendData(Ctrlr, PacketType::ControllerWrite, io, info.Size);
      break;
  } 
}

//Method called when a packet from the Feather Connection Pool is received
void TxRxRadioConnection::onPacketReceived(PacketInfo& info, IOBuffer &io){
  switch(info.Type){
    case PacketType::ComputerPrint:     //Forward to the computer
    case PacketType::AccelerationPacket:
    case PacketType::ControllerRead:
      computer.SendData(info.Type, io, info.Size);   
      break;  
    default:
      printrxln("Invalid Packet!");
      break;  
  }
}