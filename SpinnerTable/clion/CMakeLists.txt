cmake_minimum_required(VERSION 3.23)
project(SpinnerTable C)

set(CMAKE_C_STANDARD 11)

include_directories(.)
include_directories(../driverlib/MSP430FR5xx_6xx)
include_directories(../driverlib/MSP430FR5xx_6xx/inc)

add_library(Test ../main.c)
