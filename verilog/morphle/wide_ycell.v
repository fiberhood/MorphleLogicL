// SPDX-FileCopyrightText: Copyright 2020 Jecel Mattos de Assumpcao Jr
// 
// SPDX-License-Identifier: Apache-2.0 
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     https://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


// These are the building blocks for Morphle Logic, an asynchronous
// runtime reconfigurable array (ARRA).
//
// This variation uses a 4 bit wide configuration path instead of 1 bit

// many signals are two bit busses
`define Vempty 0
`define V0     1
`define V1     2
// the combination 3 is not defined

// this asynchronous finite state machine is the basic building block
// of Morphle Logic. It explicitly defines 5 simple latches that
// directly change when their inputs do, so there is no clock anywhere

module ycfsm (
    input reset,
    input [1:0] in,
    input [1:0] match,
    output [1:0] out);
    
    wire [1:0] lin;
    wire [1:0] nlin;
    wire [1:0] lmatch;
    wire [1:0] nlmatch;
    wire lmempty;
    wire nlmempty;
        
    wire linval    =| lin; // lin != `Vempty;
    wire inval     =| in; // in != `Vempty;
    wire lmatchval =| lmatch; // lmatch != `Vempty;
    wire matchval  =| match; // match != `Vempty;

    wire clear;    
    assign #1 clear = reset | (lmempty & linval & ~inval);
    wire [1:0] clear2 = {clear,clear};
    
    // two bit latches
    assign #1 lin = ~(clear2 | nlin);
    assign #1 nlin = ~(in | lin);
    
    assign #1 lmatch = ~(clear2 | nlmatch);
    assign #1 nlmatch = ~((match & {nlmempty,nlmempty}) | lmatch);
    
    // one bit latch
    assign #1 lmempty = ~(~(linval | lmatchval) | nlmempty);
    assign #1 nlmempty = ~((lmatchval & ~matchval) | lmempty);
    
    // forward the result of combining match and in
    assign out[1] = lin[1] & lmatch[1];
    assign out[0] = (lmatch[1] & lin[0]) | (lmatch[0] & linval);
    
endmodule

// each "yellow cell" in Morphle Logic can be configured to one of eight
// different options. This circuit saves the 4 bits of the configuration
// and outputs the control circuit the rest of the cell needs
// cnfg[3:2] is the vertical and cnfg[1:0] horizontal configurations
// 0000 .
// 1111 +
// 0011 -
// 1100 |
// 1110 1
// 1101 0
// 1011 Y
// 0111 N

module ycconfig (
       input confclk,
       input [3:0] cbitin,
       output [3:0] cbitout,
       output empty,
       output hblock, hbypass, hmatch0, hmatch1,
       output vblock, vbypass, vmatch0, vmatch1);
              
       reg [3:0] cnfg;
       always @(posedge confclk) cnfg = cbitin;
       assign cbitout = cnfg;  // shifted to next cell
       
       assign empty = cnfg == 4'b000;

       assign hblock = cnfg[1:0] == 2'b00;
       assign hbypass = cnfg[1:0] == 2'b11;
       assign hmatch0 = cnfg[0];
       assign hmatch1 = cnfg[1];

       assign vblock = cnfg[3:2] == 2'b00;
       assign vbypass = cnfg[3:2] == 2'b11;
       assign vmatch0 = cnfg[2];
       assign vmatch1 = cnfg[3];
       
       
endmodule

// this is the heart of Morphle Logic. It is called the "yellow cell" because
// of the first few illustrations of how it would work, with "red cells" being
// where the inputs and outputs connect to the network. Each yellow cell
// connects to four neighbors, labelled U (up), D (down), L (left) and R (right)
//
// Each cell receives its configuration bits from U and passes them on to D
//
// Values are indicated by a pair of wires, where 00 indicates empty, 01 a
// 0 value and 10 indicates a 1 value. The combination 11 should never appear
//
// Vertical signals are implemented by a pair of pairs, one of which goes
// from U to D and the second goes D to U. The first pair is the accumulated
// partial results from several cells while the second is the final result
// Horizontal signals also have a L to R pair for partial results and a R to L
// pair for final results

module ycell(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif
  // control
  input reset,    // freezes the cell operations and clears everything
  output reseto,  // pass through to help routing
  input confclk,   // a strobe to enter one configuration bit
  output confclko,
  input [3:0] cbitin,   // new configuration bit from previous cell (U)
  output [3:0] cbitout, // configuration bit to next cell (D)
  output hempty,  // this cell interrupts horizontal signals
  output hempty2,
  output vempty,  // this cell interrupts vertical signals
  output vempty2,
  // UP
  input uempty,    // cell U is empty, so we are the topmost of a signal
  input [1:0] uin,
  output [1:0] uout,
  // DOWN
  input dempty,    // cell D is empty, so we are the bottommost of a signal
  input [1:0] din,
  output [1:0] dout,
  // LEFT
  input lempty,    // cell L is empty, so we are the leftmost of a signal
  input [1:0] lin,
  output [1:0] lout,
  // RIGHT
  input rempty,    // cell D is empty, so we are the rightmost of a signal
  input [1:0] rin,
  output [1:0] rout);
  
  // bypass to pins on opposite side of the circuit (could add buffers?)
  assign reseto = reset;
  assign confclko = confclk;
  assign hempty2 = hempty;
  assign vempty2 = vempty;
  
  // configuration signals decoded
  wire empty;
  wire hblock, hbypass, hmatch0, hmatch1;
  wire vblock, vbypass, vmatch0, vmatch1;
  ycconfig cfg (.confclk(confclk), .cbitin(cbitin), .cbitout(cbitout),
                 .empty(empty),
                 .hblock(hblock), .hbypass(hbypass), .hmatch0(hmatch0), .hmatch1(hmatch1),
                 .vblock(vblock), .vbypass(vbypass), .vmatch0(vmatch0), .vmatch1(vmatch1));
                 
  assign hempty = empty | hblock;
  wire hreset = reset | hblock; // perhaps "| hbypass" to save energy?
  wire [1:0] hin;
  wire [1:0] hout;
  wire [1:0] hback;

  assign vempty = empty | vblock;
  wire vreset = reset | vblock;
  wire [1:0] vin;
  wire [1:0] vout;
  wire [1:0] vback;

  wire [1:0] hmatch = {(vback[1]&vmatch1)|(vback[0]&vmatch0),(vback[1]&~vmatch1&vmatch0)|(vback[0]&~vmatch0&vmatch1)};
  ycfsm hfsm (.reset(hreset), .in(hin), .match(hmatch), .out(hout));
  wire [1:0] bhout = hbypass ? hin : hout;
  assign rout = bhout;
  assign #1 hin = lempty ? {~hreset&(~(hback[1]|hback[1'b0])),1'b0} : lin; // no oscillation on reset
  assign hback = (rempty | hempty) ? bhout : rin; // don't propagate when rightmost or empty
  assign lout = hback;
  
  wire [1:0] vmatch = {(hback[1]&hmatch1)|(hback[0]&hmatch0),(hback[1]&~hmatch1&hmatch0)|(hback[0]&~hmatch0&hmatch1)};
  ycfsm vfsm (.reset(vreset), .in(vin), .match(vmatch), .out(vout));
  wire [1:0] bvout = vbypass ? vin : vout;
  assign dout = bvout;
  assign #1 vin = uempty ? {~vreset&(~(vback[1]|vback[1'b0])),1'b0} : uin; // no oscillation on reset
  assign vback = (dempty | vempty) ? bvout : din; // don't propagate when bottommost or empty
  assign uout = vback;

endmodule

