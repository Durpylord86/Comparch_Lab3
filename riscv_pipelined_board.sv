// riscvpipelined.sv

// RISC-V pipelined processor
// From Section 7.6 of Digital Design & Computer Architecture: RISC-V Edition
// 27 April 2020
// David_Harris@hmc.edu 
// Sarah.Harris@unlv.edu

// run 210
// Expect simulator to print "Simulation succeeded"
// when the value 25 (0x19) is written to address 100 (0x64)

// Pipelined implementation of RISC-V (RV32I)
// User-level Instruction Set Architecture V2.2 (May 7, 2017)
// Implements a subset of the base integer instructions:
//    lw, sw
//    add, sub, and, or, slt, 
//    addi, andi, ori, slti
//    beq
//    jal
// Exceptions, traps, and interrupts not implemented
// little-endian memory

// 31 32-bit registers x1-x31, x0 hardwired to 0
// R-Type instructions
//   add, sub, and, or, slt
//   INSTR rd, rs1, rs2
//   Instr[31:25] = funct7 (funct7b5 & opb5 = 1 for sub, 0 for others)
//   Instr[24:20] = rs2
//   Instr[19:15] = rs1
//   Instr[14:12] = funct3
//   Instr[11:7]  = rd
//   Instr[6:0]   = opcode
// I-Type Instructions
//   lw, I-type ALU (addi, andi, ori, slti)
//   lw:         INSTR rd, imm(rs1)
//   I-type ALU: INSTR rd, rs1, imm (12-bit signed)
//   Instr[31:20] = imm[11:0]
//   Instr[24:20] = rs2
//   Instr[19:15] = rs1
//   Instr[14:12] = funct3
//   Instr[11:7]  = rd
//   Instr[6:0]   = opcode
// S-Type Instruction
//   sw rs2, imm(rs1) (store rs2 into address specified by rs1 + immm)
//   Instr[31:25] = imm[11:5] (offset[11:5])
//   Instr[24:20] = rs2 (src)
//   Instr[19:15] = rs1 (base)
//   Instr[14:12] = funct3
//   Instr[11:7]  = imm[4:0]  (offset[4:0])
//   Instr[6:0]   = opcode
// B-Type Instruction
//   beq rs1, rs2, imm (PCTarget = PC + (signed imm x 2))
//   Instr[31:25] = imm[12], imm[10:5]
//   Instr[24:20] = rs2
//   Instr[19:15] = rs1
//   Instr[14:12] = funct3
//   Instr[11:7]  = imm[4:1], imm[11]
//   Instr[6:0]   = opcode
// J-Type Instruction
//   jal rd, imm  (signed imm is multiplied by 2 and added to PC, rd = PC+4)
//   Instr[31:12] = imm[20], imm[10:1], imm[11], imm[19:12]
//   Instr[11:7]  = rd
//   Instr[6:0]   = opcode

//   Instruction  opcode    funct3    funct7
//   add          0110011   000       0000000
//   sub          0110011   000       0100000
//   and          0110011   111       0000000
//   or           0110011   110       0000000
//   slt          0110011   010       0000000
//   addi         0010011   000       immediate
//   andi         0010011   111       immediate
//   ori          0010011   110       immediate
//   slti         0010011   010       immediate
//   beq          1100011   000       immediate
//   lw	          0000011   010       immediate
//   sw           0100011   010       immediate
//   jal          1101111   immediate immediate

module riscv(input  logic        clk, reset,
             output logic [31:0] PCF,
             input logic [31:0]  InstrF,
             output logic 	 MemWriteM,
             output logic [31:0] ALUResultM, WriteDataM,
             input logic [31:0]  ReadDataM,
             input logic         PCReady,
             output logic        MemStrobeM);

   logic [6:0] 			 opD;
   logic [2:0] 			 funct3D;
   logic 			 funct7b5D;
   logic [2:0] 			 ImmSrcD;
   logic       CarryE;
   logic       Res31E;
   logic 			 ZeroE;
   logic 			 PCSrcE;
   logic [3:0] 			 ALUControlE;
   logic 			 ALUSrcAE;   
   logic 			 ALUSrcBE;
   logic       PCTargetSrcE;
   logic 			 ResultSrcEb0;
   logic 			 RegWriteM;
   logic [1:0] 			 ResultSrcW;
   logic 			 RegWriteW;

   logic [1:0] 			 ForwardAE, ForwardBE;
   logic 			 StallF, StallD, FlushD, FlushE;

   logic [4:0] 			 Rs1D, Rs2D, Rs1E, Rs2E, RdE, RdM, RdW;
   
   controller c(clk, reset,
		opD, funct3D, funct7b5D, ImmSrcD,
		FlushE, CarryE, Res31E, ZeroE, PCSrcE, ALUControlE, ALUSrcAE, ALUSrcBE, ResultSrcEb0, PCTargetSrcE,
		MemWriteM, RegWriteM, 
		RegWriteW, ResultSrcW, MemStrobeM);

   datapath dp(clk, reset,
               StallF, PCF, InstrF,
	       opD, funct3D, funct7b5D, StallD, FlushD, ImmSrcD,
	       FlushE, ForwardAE, ForwardBE, PCSrcE, ALUControlE, ALUSrcAE, ALUSrcBE, PCTargetSrcE, CarryE, Res31E, ZeroE,
               MemWriteM, WriteDataM, ALUResultM, ReadDataM,
               RegWriteW, ResultSrcW,
               Rs1D, Rs2D, Rs1E, Rs2E, RdE, RdM, RdW, PCReady);

   hazard  hu(Rs1D, Rs2D, Rs1E, Rs2E, RdE, RdM, RdW,
              PCSrcE, ResultSrcEb0, RegWriteM, RegWriteW,
              ForwardAE, ForwardBE, StallF, StallD, FlushD, FlushE);			 
endmodule


module controller(input  logic		 clk, reset,
                  // Decode stage control signals
                  input logic [6:0]  opD,
                  input logic [2:0]  funct3D,
                  input logic 	     funct7b5D,
                  output logic [2:0] ImmSrcD,
                  // Execute stage control signals
                  input logic 	     FlushE, 
                  input logic        CarryE,
                  input logic        Res31E,
                  input logic 	     ZeroE, 
                  output logic 	     PCSrcE, // for datapath and Hazard Unit
                  output logic [3:0] ALUControlE,
		  output logic 	     ALUSrcAE,
                  output logic 	     ALUSrcBE,
                  output logic 	     ResultSrcEb0, // for Hazard Unit
                  output logic       PCTargetSrcE,
                  // Memory stage control signals
                  output logic 	     MemWriteM,
                  output logic 	     RegWriteM, // for Hazard Unit				  
                  // Writeback stage control signals
                  output logic 	     RegWriteW, // for datapath and Hazard Unit
                  output logic [1:0] ResultSrcW,
                  output logic       MemStrobeM);

   // pipelined control signals
   logic 			     RegWriteD, RegWriteE;
   logic [1:0] 			     ResultSrcD, ResultSrcE, ResultSrcM;
   logic 			     MemWriteD, MemWriteE;
   logic 			     JumpD, JumpE;
   logic 			     BranchD, BranchE;
   logic [1:0] 			     ALUOpD;
   logic [3:0] 			     ALUControlD;
   logic 			     ALUSrcAD;   
   logic 			     ALUSrcBD;
   logic           PCTargetSrcD;
   logic [2:0] 			     funct3E;
   logic 			     MemStrobeD, MemStrobeE;
   
   // Decode stage logic
   maindec md(opD, ResultSrcD, MemWriteD, BranchD,
              ALUSrcAD, ALUSrcBD, PCTargetSrcD, RegWriteD, JumpD, ImmSrcD, ALUOpD, MemStrobeD);
	aludec  ad(opD[5], funct3D, funct7b5D, ALUOpD, ALUControlD);
   
   // Execute stage pipeline control register and logic
   floprc #(16) controlregE(clk, reset, FlushE,
			    {RegWriteD, ResultSrcD, MemWriteD, JumpD, BranchD, ALUControlD, ALUSrcAD, ALUSrcBD, PCTargetSrcD, funct3D, MemStrobeD},
			    {RegWriteE, ResultSrcE, MemWriteE, JumpE, BranchE, ALUControlE, ALUSrcAE, ALUSrcBE, PCTargetSrcE, funct3E, MemStrobeE});

   logic            BranchControl;

   assign BranchControl = (ZeroE & ~funct3E[0]&~funct3E[1]&~funct3E[2]) |
			                    (~ZeroE & funct3E[0]&~funct3E[1]&~funct3E[2]) |
			                    (Res31E & ~funct3E[0]&~funct3E[1]&funct3E[2]) |
			                    ((~Res31E | ZeroE) & funct3E[0]&~funct3E[1]&funct3E[2]) |
			                    (~CarryE & ~funct3E[0]&funct3E[1]&funct3E[2]) |
			                    (CarryE & funct3E[0]&funct3E[1]&funct3E[2]);
   assign PCSrcE = (BranchE & BranchControl) | JumpE;
   assign ResultSrcEb0 = ResultSrcE[0];
   
   // Memory stage pipeline control register
   flopr #(4) controlregM(clk, reset,
			  {RegWriteE, ResultSrcE, MemWriteE, MemStrobeE},
			  {RegWriteM, ResultSrcM, MemWriteM, MemStrobeM});
   
   // Writeback stage pipeline control register
   flopr #(3) controlregW(clk, reset,
                          {RegWriteM, ResultSrcM},
                          {RegWriteW, ResultSrcW});     
endmodule

module maindec(input  logic [6:0] op,
               output logic [1:0] ResultSrc,
               output logic 	  MemWrite,
               output logic 	  Branch, ALUSrcA, ALUSrcB, PCTargetSrc,
               output logic 	  RegWrite, Jump,
               output logic [2:0] ImmSrc,
               output logic [1:0] ALUOp,
               output logic       MemStrobe);

  logic [14:0] 		  controls;

   assign {RegWrite, ImmSrc, ALUSrcA, ALUSrcB, MemWrite,
           ResultSrc, Branch, ALUOp, Jump, PCTargetSrc, MemStrobe} = controls;

   always_comb
     case(op)
       // RegWrite_ImmSrc_ALUSrcA_ALUSrcB_MemWrite_ResultSrc_Branch_ALUOp_Jump_PCTargetSrc_MemStrobe
       7'b0000011: controls = 15'b1_000_0_1_0_01_0_00_0_0_1; // lw
       7'b0100011: controls = 15'b0_001_0_1_1_00_0_00_0_0_1; // sw
       7'b0110011: controls = 15'b1_xxx_0_0_0_00_0_10_0_0_0; // R-type 
       7'b1100011: controls = 15'b0_010_0_0_0_00_1_01_0_0_0; // B-Type
       7'b0010011: controls = 15'b1_000_0_1_0_00_0_10_0_0_0; // I-type ALU
       7'b1101111: controls = 15'b1_011_0_0_0_10_0_00_1_0_0; // jal
       7'b0110111: controls = 15'b1_100_1_1_0_00_0_00_0_0_0; // lui       
       7'b1100111: controls = 15'b1_000_0_1_0_10_0_xx_1_1_0; // jalr
       7'b0010111: controls = 15'b1_100_x_x_0_11_0_xx_0_0_0; // auipc
       7'b0000000: controls = 15'b0_000_0_0_0_00_0_00_0_0_0; // need valid values at reset
       default:    controls = 15'bx_xxx_x_x_x_xx_x_xx_x_x_x; // non-implemented instruction
     endcase
endmodule

module aludec(input  logic       opb5,
              input logic [2:0]  funct3,
              input logic 	 funct7b5, 
              input logic [1:0]  ALUOp,
              output logic [3:0] ALUControl);

   logic 			 RtypeSub;
   assign RtypeSub = funct7b5 & opb5;  // TRUE for R-type subtract instruction

   always_comb
     case(ALUOp)
       2'b00:                ALUControl = 4'b0000; // addition
       2'b01:                ALUControl = 4'b0001; // subtraction
       default: case(funct3) // R-type or I-type ALU
                  3'b000:  if (RtypeSub) 
                    ALUControl = 4'b0001; // sub
                  else          
                    ALUControl = 4'b0000; // add, addi
                  3'b010:    ALUControl = 4'b0101; // slt, slti
                  3'b110:    ALUControl = 4'b0011; // or, ori
                  3'b111:    ALUControl = 4'b0010; // and, andi
                  3'b100:    ALUControl = 4'b0100; // xor, xori
                  3'b001:    ALUControl = 4'b0110; // sll, slli
                  3'b101:    if (funct7b5)
                    ALUControl = 4'b1000; // sra, srai
                  else
                    ALUControl = 4'b0111; // srl, srli
                  3'b011:    ALUControl = 4'b1001; // sltu, sltiu
                  default:   ALUControl = 4'bxxxx; // ???
		endcase
     endcase
endmodule

module datapath(input logic clk, reset,
                // Fetch stage signals
                input logic 	    StallF,
                output logic [31:0] PCF,
                input logic [31:0]  InstrF,
                // Decode stage signals
                output logic [6:0]  opD,
                output logic [2:0]  funct3D, 
                output logic 	    funct7b5D,
                input logic 	    StallD, FlushD,
                input logic [2:0]   ImmSrcD,
                // Execute stage signals
                input logic 	    FlushE,
                input logic [1:0]   ForwardAE, ForwardBE,
                input logic 	    PCSrcE,
                input logic [3:0]   ALUControlE,
		input logic 	    ALUSrcAE,
                input logic 	    ALUSrcBE,
                input logic       PCTargetSrcE,
                output logic      CarryE,
                output logic      Res31E,
                output logic 	    ZeroE,
                // Memory stage signals
                input logic 	    MemWriteM, 
                output logic [31:0] WriteDataM, ALUResultM,
                input logic [31:0]  ReadDataM,
                // Writeback stage signals
                input logic 	    RegWriteW, 
                input logic [1:0]   ResultSrcW,
                // Hazard Unit signals 
                output logic [4:0]  Rs1D, Rs2D, Rs1E, Rs2E,
                output logic [4:0]  RdE, RdM, RdW,
                input logic         PCReady);

   // Fetch stage signals
   logic [31:0] 		    PCNextF, PCPlus4F;
   // Decode stage signals
   logic [31:0] 		    InstrD;
   logic [31:0] 		    PCD, PCPlus4D;
   logic [31:0] 		    RD1D, RD2D;
   logic [31:0] 		    ImmExtD;
   logic [4:0] 			    RdD;
   // Execute stage signals
   logic [31:0] 		    RD1E, RD2E;
   logic [31:0] 		    PCE, ImmExtE;
   logic [31:0] 		    SrcAE, SrcBE;
   logic [31:0] 		    SrcAEforward;   
   logic [31:0] 		    ALUResultE;
   logic [31:0] 		    WriteDataE;
   logic [31:0] 		    PCPlus4E;
   logic [31:0] 		    PCTargetE, PCTargetNewE;
   logic [2:0] 		      funct3E;
   // Memory stage signals
   logic [31:0] 		    PCPlus4M;
   logic [31:0]         PCTargetNewM;
   logic [2:0] 		      funct3M;
   // Writeback stage signals
   logic [31:0] 		    ALUResultW;
   logic [31:0] 		    ReadDataW;
   logic [31:0] 		    PCPlus4W;
   logic [31:0]         PCTargetNewW;
   logic [31:0] 		    ResultW;
   logic [2:0]          funct3W;
   logic [31:0] 		    loadResW;

   // Fetch stage pipeline register and logic
   mux2    #(32) pcmux(PCPlus4F, PCTargetNewE, PCSrcE, PCNextF);
   flopenr #(32) pcreg(clk, reset, ~StallF | PCReady, PCNextF, PCF);
   adder         pcadd(PCF, 32'h4, PCPlus4F);

   // Decode stage pipeline register and logic
   flopenrc #(96) regD(clk, reset, FlushD, ~StallD, 
                       {InstrF, PCF, PCPlus4F},
                       {InstrD, PCD, PCPlus4D});
   assign opD       = InstrD[6:0];
   assign funct3D   = InstrD[14:12];
   assign funct7b5D = InstrD[30];
   assign Rs1D      = InstrD[19:15];
   assign Rs2D      = InstrD[24:20];
   assign RdD       = InstrD[11:7];
   
   regfile        rf(clk, RegWriteW, Rs1D, Rs2D, RdW, ResultW, RD1D, RD2D);
   extend         ext(InstrD[31:7], ImmSrcD, ImmExtD);
   
   // Execute stage pipeline register and logic
   floprc #(178) regE(clk, reset, FlushE, 
                      {RD1D, RD2D, PCD, Rs1D, Rs2D, RdD, ImmExtD, PCPlus4D, funct3D}, 
                      {RD1E, RD2E, PCE, Rs1E, Rs2E, RdE, ImmExtE, PCPlus4E, funct3E});
   
   mux3   #(32)  faemux(RD1E, ResultW, ALUResultM, ForwardAE, SrcAEforward);
   mux3   #(32)  fbemux(RD2E, ResultW, ALUResultM, ForwardBE, WriteDataE);
   mux2   #(32)  srcamux(SrcAEforward, 32'h0, ALUSrcAE, SrcAE);   
   mux2   #(32)  srcbmux(WriteDataE, ImmExtE, ALUSrcBE, SrcBE);
   alu           alu(SrcAE, SrcBE, ALUControlE, ALUResultE, CarryE, Res31E, ZeroE);
   adder         branchadd(ImmExtE, PCE, PCTargetE);
   mux2   #(32)  jalrmux(PCTargetE, ALUResultE, PCTargetSrcE, PCTargetNewE);

   // Memory stage pipeline register
   flopr  #(136) regM(clk, reset, 
                      {ALUResultE, WriteDataE, RdE, PCPlus4E, PCTargetNewE, funct3E},
                      {ALUResultM, WriteDataM, RdM, PCPlus4M, PCTargetNewM, funct3M});
   
   // Writeback stage pipeline register and logic
   flopr  #(136) regW(clk, reset, 
                      {ALUResultM, ReadDataM, RdM, PCPlus4M, PCTargetNewM, funct3M},
                      {ALUResultW, ReadDataW, RdW, PCPlus4W, PCTargetNewW, funct3W});
   loadext       load(ALUResultW, ReadDataW, funct3W, loadResW);
   mux4   #(32)  resultmux(ALUResultW, loadResW, PCPlus4W, PCTargetNewW, ResultSrcW, ResultW);	
endmodule

// Hazard Unit: forward, stall, and flush
module hazard(input  logic [4:0] Rs1D, Rs2D, Rs1E, Rs2E, RdE, RdM, RdW,
              input logic 	 PCSrcE, ResultSrcEb0, 
              input logic 	 RegWriteM, RegWriteW,
              output logic [1:0] ForwardAE, ForwardBE,
              output logic 	 StallF, StallD, FlushD, FlushE);

   logic 			 lwStallD;
   
   // forwarding logic
   always_comb begin
      ForwardAE = 2'b00;
      ForwardBE = 2'b00;
      if (Rs1E != 5'b0)
	if      ((Rs1E == RdM) & RegWriteM) ForwardAE = 2'b10;
	else if ((Rs1E == RdW) & RegWriteW) ForwardAE = 2'b01;
      
      if (Rs2E != 5'b0)
	if      ((Rs2E == RdM) & RegWriteM) ForwardBE = 2'b10;
	else if ((Rs2E == RdW) & RegWriteW) ForwardBE = 2'b01;
   end
   
   // stalls and flushes
   assign lwStallD = ResultSrcEb0 & ((Rs1D == RdE) | (Rs2D == RdE));  
   assign StallD = lwStallD;
   assign StallF = lwStallD;
   assign FlushD = PCSrcE;
   assign FlushE = lwStallD | PCSrcE;
endmodule

module regfile(input  logic        clk, 
               input logic 	   we3, 
               input logic [ 4:0]  a1, a2, a3, 
               input logic [31:0]  wd3, 
               output logic [31:0] rd1, rd2);

   logic [31:0] 		   rf[31:0];

   // three ported register file
   // read two ports combinationally (A1/RD1, A2/RD2)
   // write third port on rising edge of clock (A3/WD3/WE3)
   // write occurs on falling edge of clock
   // register 0 hardwired to 0

   always_ff @(negedge clk)
     if (we3) rf[a3] <= wd3;	

   assign rd1 = (a1 != 0) ? rf[a1] : 0;
   assign rd2 = (a2 != 0) ? rf[a2] : 0;
endmodule

module adder(input  [31:0] a, b,
             output [31:0] y);

   assign y = a + b;
endmodule

module extend(input  logic [31:7] instr,
              input logic [2:0]   immsrc,
              output logic [31:0] immext);
   
   always_comb
     case(immsrc) 
       // I-type 
       3'b000:   immext = {{20{instr[31]}}, instr[31:20]};  
       // S-type (stores)
       3'b001:   immext = {{20{instr[31]}}, instr[31:25], instr[11:7]}; 
       // B-type (branches)
       3'b010:   immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; 
       // J-type (jal)
       3'b011:   immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
       // U−type (lui/auipc) 
       3'b100:  immext = {instr[31:12], 12'h0};         
       default: immext = 32'bx; // undefined
     endcase             
endmodule

module loadext (input logic  [31:0] ALUResult, ReadData,
                input logic  [2:0]  funct3,
                output logic [31:0] loadResult);

    logic [1:0]     loadbits;

    assign loadbits = ALUResult[1:0];

    always_comb
      case(funct3)
        3'b000: case(loadbits) // lb
          2'b00: loadResult = {{24{ReadData[7]}}, ReadData[7:0]};
          2'b01: loadResult = {{24{ReadData[15]}}, ReadData[15:8]};
          2'b10: loadResult = {{24{ReadData[23]}}, ReadData[23:16]};
          2'b11: loadResult = {{24{ReadData[31]}}, ReadData[31:24]};
          default: loadResult = 32'bx;
        endcase
        3'b001: case(loadbits[1]) // lh
          1'b0: loadResult = {{16{ReadData[15]}}, ReadData[15:0]};
          1'b1: loadResult = {{16{ReadData[31]}}, ReadData[31:16]};
          default: loadResult = 32'bx;
        endcase
        3'b010: loadResult = ReadData; // lw
        3'b100: case(loadbits) // lbu
          2'b00: loadResult = {{24'b0}, ReadData[7:0]};
          2'b01: loadResult = {{24'b0}, ReadData[15:8]};
          2'b10: loadResult = {{24'b0}, ReadData[23:16]};
          2'b11: loadResult = {{24'b0}, ReadData[31:24]};
          default: loadResult = 32'bx;
        endcase
        3'b101: case(loadbits[1]) // lhu
          1'b0: loadResult = {{16'b0}, ReadData[15:0]};
          1'b1: loadResult = {{16'b0}, ReadData[31:16]};
          default: loadResult = 32'bx;
        endcase
        default: loadResult = 32'bx;
      endcase

endmodule // loadext

/*module storeext (input  logic [31:0] ALUResult, Result,
                 input  logic        Memwrite,
                 input  logic [2:0]  funct3,
                 output logic [31:0] storeResult);

      logic [1:0]     storebits;

      assign storebits = ALUResult[1:0];

      if (Memwrite) {
        always_comb
          case(funct3)
            3'b000: case(storebits) // sb
              2'b00: storeResult = {{24{Result[7]}}, Result[7:0]};
              2'b01: storeResult = {{{Result[31:16]}}, Result[7:0], Result[7:0]};
              2'b10: storeResult = {{{Result[31:24]}}, Result[7:0], Result[15:0]};
              2'b11: storeResult = {{{Result[7:0]}}, Result[23:0]};
              default: storeResult = 32'bx;
            endcase
            3'b001: case(storebits[1]) // sh
              1'b0: storeResult = {{{Result[31:16]}}, Result[15:0]};
              1'b1: storeResult = {{{Result[15:0]}}, Result[15:0]};
              default: storeResult = 32'bx;
            endcase
            3'b010: storeResult = Result; // sw
            default: storeResult = 32'bx;
          endcase
      }

endmodule*/

module flopr #(parameter WIDTH = 8)
   (input  logic             clk, reset,
    input logic [WIDTH-1:0]  d, 
    output logic [WIDTH-1:0] q);

   always_ff @(posedge clk, posedge reset)
     if (reset) q <= 0;
     else       q <= d;
endmodule

module flopenr #(parameter WIDTH = 8)
   (input  logic             clk, reset, en,
    input logic [WIDTH-1:0]  d, 
    output logic [WIDTH-1:0] q);

   always_ff @(posedge clk, posedge reset)
     if (reset)   q <= 0;
     else if (en) q <= d;
endmodule

module flopenrc #(parameter WIDTH = 8)
   (input  logic             clk, reset, clear, en,
    input logic [WIDTH-1:0]  d, 
    output logic [WIDTH-1:0] q);

   always_ff @(posedge clk, posedge reset)
     if (reset)   q <= 0;
     else if (en) 
       if (clear) q <= 0;
       else       q <= d;
endmodule

module floprc #(parameter WIDTH = 8)
   (input  logic clk,
    input logic 	     reset,
    input logic 	     clear,
    input logic [WIDTH-1:0]  d, 
    output logic [WIDTH-1:0] q);

   always_ff @(posedge clk, posedge reset)
     if (reset) q <= 0;
     else       
       if (clear) q <= 0;
       else       q <= d;
endmodule

module mux2 #(parameter WIDTH = 8)
   (input  logic [WIDTH-1:0] d0, d1, 
    input logic 	     s, 
    output logic [WIDTH-1:0] y);

   assign y = s ? d1 : d0; 
endmodule

module mux3 #(parameter WIDTH = 8)
   (input  logic [WIDTH-1:0] d0, d1, d2,
    input logic [1:0] 	     s, 
    output logic [WIDTH-1:0] y);

   assign y = s[1] ? d2 : (s[0] ? d1 : d0); 
endmodule

module mux4 #(parameter WIDTH = 8)
   (input logic [WIDTH-1:0] d0, d1, d2, d3,
    input logic [1:0] s,
    output logic [WIDTH-1:0] y);

 assign y = s[1] ? (s[0] ? d3 : d2) : (s[0] ? d1 : d0);

endmodule // mux4

module alu(input  logic [31:0] a, b,
           input logic [3:0]   alucontrol,
           output logic [31:0] result,
           output logic        carry,
           output logic        res31,
           output logic        zero);

   logic [31:0] 	       condinvb, sum;
   logic 		       v;              // overflow
   logic 		       isAddSub;       // true when is add or sub

   assign condinvb = alucontrol[0] ? ~b : b;
   assign sum = a + condinvb + alucontrol[0];
   assign isAddSub = ~alucontrol[2] & ~alucontrol[1] |
                     ~alucontrol[1] &  alucontrol[0];

   always_comb
     case (alucontrol)
       4'b0000:  result = sum;         // add
       4'b0001:  result = sum;         // subtract
       4'b0010:  result = a & b;       // and
       4'b0011:  result = a | b;       // or
       4'b0100:  result = a ^ b;       // xor
       4'b0101:  result = sum[31] ^ v; // slt
       4'b0110:  result = a << b[4:0]; // sll
       4'b0111:  result = a >> b[4:0]; // srl
       4'b1000:  result = $signed(a) >>> b[4:0]; // sra
       4'b1001:  result = {31'b0, (b < a)}; // sltu
       default: result = 32'bx;
     endcase

   assign carry = ~(a < b);
   assign res31 = result[31];
   assign zero = (result == 32'b0);
   assign v = ~(alucontrol[0] ^ a[31] ^ b[31]) & (a[31] ^ sum[31]) & isAddSub;
   
endmodule
