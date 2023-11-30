#define DEBUG

#include <iostream>
#include "../devices/SimplePC.hpp"
#include "../SimpleDebug.hpp"
#include "../SimpleConnection.hpp"

using namespace Simple;

struct TestConnection : public SimpleConnection{
    TestConnection* s;

    void Write(IOBuffer* io) override{
        IOBuffer randomJunk;
        randomJunk.Write(3);
        randomJunk.Write(4);
        s->Receive(&randomJunk);

        s->Receive((IOBuffer*) io);
    }

    void ReceivedMessage(IOBuffer* io, int size) override {
        println("Rx Msg: %u", io->Read<uint16_t>());
    }
};

void test_connection(){
    TestConnection c1;
    TestConnection c2;
    c1.s = &c2;
    c2.s = &c1;

    IOBuffer io;
    io.Write<uint16_t>(31313);
    io.SeekStart();

    for(int i = 0; i < 10; i++){
        c1.Send(&io);
        io.SeekStart();
    }
}

void create_timer(int &var) {
    auto lam = make_global_lambda([&], void, (Timer& t), {
        println("Timer Fire Value: %i", var);
        var += 1;
        if (var == 10) {
            println("Stopping Timer");
            t.Stop();
            delete &t;
            println("End Timer!");
        }
    });
    auto t = new Timer(true, 1000, lam);
    t->Start();
}

void test_async() {
    async([], println("My Async Task!"));
    println("Post Async Init, Pre Async Print!");
}

void test_io() {
    int iiV = 123;
    long iV = 1234578910;
    double dV = .345345;
    float fV = .342344;
    auto tup = make_tuple(iiV, iiV, fV);
    auto v = vector<int>{2, 3, 4};
    auto arr = array<int, 3>{5, 6, 7};

    println("Enter A Number From 1-5");

    char c;
    Out.Read(&c);
    println("Read Value: %c", c);

    IOBuffer io, rio;
    io.WriteStd(iV);
    io.WriteStd(dV);
    io.WriteStd(fV);
    io.WriteStd(tup);
    io.WriteStd(v);
    io.WriteStd(arr);
    io.WriteStd(2.5f, 3.5, 5L);
    io.WriteStd(fV, dV, iV);
    io.Printf("Test %i\n\r", 2);

    io.SeekStart();
    assert(io.ReadStd<long>() == iV, "Long Serialization Fail!");
    assert(io.ReadStd<double>() == dV, "Double Serialization Fail!");
    assert(io.ReadStd<float>() == fV, "Float Serialization Fail!");
    assert((io.ReadStd<tuple<int, int, float>>() == tup), "Tuple Serialization Fail!");
    assert((io.ReadStd<vector<int>>() == v), "Vector Serialization Fail!");
    assert((io.ReadStd<array<int, 3>>() == arr), "Array Serialization Fail!");

    make_local_lambda(lam_1, [], void, (float f, double d, long l), {
        println("IO Lambda");
        assert(f == 2.5f, "Float Arg Fail!");
        assert(d == 3.5, "Float Arg Fail!");
        assert(l == 5L, "Long Arg Fail!");
    });
    io.ReadStd(lam_1);

    make_local_lambda(lam_2, [=], void, (float cF, double cD, long cL), {
        println("IO Lambda");
        assert(cF == fV, "Args 0 Serialization Fail!");
        assert(cD == dV, "Args 1 Serialization Fail!");
        assert(cL == iV, "Args 2 Serialization Fail!");
    });
    io.ReadStd(lam_2);

    assert(strcmp(rio.Interpret<char>(io.ReadLine(rio)), "Test 2") == 0, "Print Serialization Fail!");

    println("Finished IO Testing!");
}

int main() {
    int local_var = 7;

    if (!InitializeIO())
        printf("Wrong Endian Type!");

    println("%s", "Initializing Test Suite!");
    test_io();
    create_timer(local_var);
    test_async();
    test_connection();
}