/**********************************************************************
   NAME: SimpleConnection.h
   AUTHOR: Johnathan Bizzano
   DATE: 6/22/2023

    The Simple Project
		Medium Level (from Low) library that abstracts away from embedded device hardware

    Simple Connection
		Medium Level Network library that provides access to several different protocols with error minimization
*********************************************************************/

#ifndef SIMPLE_PACKET_PROTOCOL_C_H
#define SIMPLE_PACKET_PROTOCOL_C_H

#include "stdint.h"
#include "malloc.h"
#include "math.h"

#include "SimpleDebug.hpp"
#include "SimpleTimer.hpp"
#include "SimpleIO.hpp"
#include "SimpleLock.hpp"
#include <numeric>
#include <vector>

#define MIN(a, b) (a) > (b) ? (a) : (b)


//[222, 173, 190, 239]
const uint32_t MAGIC_NUMBER = 0xDEADBEEF; //PACK in bytes
//[238]
const uint8_t TAIL_MAGIC_NUMBER = 0xEE;

namespace Simple {
    class Connection{
    protected:
        virtual void Write(IOBuffer* io) = 0;
    public:
        virtual void Send(IOBuffer* io) = 0;
        virtual void Receive(IOBuffer* io) = 0;
    };

    class ConnectionWrapper : public Connection{
    protected:
        Connection* c;

        ConnectionWrapper(Connection* c) : c(c){}
        void Send(IOBuffer* p) override { c->Send(p); }
        void Receive(IOBuffer* io) override { c->Receive(io); }
    };

    class SimpleConnection : public Connection{
        IOBuffer write_buffer, read_buffer;
    public:

        void Send(IOBuffer* p) override {
            write_buffer.Clear();
            write_buffer.WriteStd(MAGIC_NUMBER);
            write_buffer.Write<uint8_t>(0);
            write_buffer.ReadFrom(*p);
            write_buffer.WriteStd(TAIL_MAGIC_NUMBER);
            *write_buffer.Interpret(4) = write_buffer.Position() - (sizeof(TAIL_MAGIC_NUMBER) + sizeof(MAGIC_NUMBER) + 1);
            write_buffer.SeekStart();
            Write(&write_buffer);
        }

        void Receive(IOBuffer* io) override {
            read_buffer.SeekEnd();
            read_buffer.ReadFrom(*io);
            read_buffer.SeekStart();
            printf("ReadBuffer Size:%zu Cap: %zu\n", read_buffer.Size(), read_buffer.Capacity());
            uint32_t maybe_number = 0;

            while(read_buffer.TryReadStd(&maybe_number) && maybe_number != MAGIC_NUMBER)
                read_buffer.SeekDelta(1);   //Read next byte

            uint8_t read_size = 0;
            read_buffer.Print(Out);
            if(maybe_number == MAGIC_NUMBER && read_buffer.TryReadStd(&read_size)){
                auto pos = read_buffer.Position();
                uint8_t tail = 0;

                if(!read_buffer.TryReadStd(&tail)) return;
                read_buffer.Seek(pos);

                if(tail == TAIL_MAGIC_NUMBER){
                    ReceivedMessage(&read_buffer, read_size);
                    read_buffer.Seek(pos + read_size + sizeof(TAIL_MAGIC_NUMBER));
                }

                read_buffer.ClearToPosition();
            }else{
                read_buffer.ClearToPosition();      //Junk Data
            }
        }

        virtual void ReceivedMessage(IOBuffer* io, int size) = 0;
    };

    class ConnectionIO : public Connection{
        IO* io;

    public:
        ConnectionIO(IO* io) : io(io){}

    protected:
        void Write(IOBuffer* in) override { io->ReadFrom(*in); }
    public:
        void Send(IOBuffer* in) override { io->ReadFrom(*in); }
    };
}

#endif