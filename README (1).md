# RISCV Assembly Instruction Testing

To change what test is being tested, change line 95 of riscv_pipelined.sv:
memfilename = {"(chosen test.memfile)"};

To test riscv_pipelined.sv for instructions, change directory to the directory that riscv_pipelined.sv is in. Then type 
"vsim -do riscv_pipelined"

We were unable to get sb and sh to work properly, though every other instruction asked for in the lab has been tested thoroughly. We felt that we were close with some attempts though and have left them commented out in riscv_pipelined_board.sv.

We didn't make any other testing files because we were able to test whether the instructions worked using the waveform of the
test files in the "testing" folder.

# Implementing onto the FPGA Board

To implement the code onto the FPGA board:
1. Make sure that Dr. Stine's github for lab 2 is copied onto whatever system you are testing on. Our .xpr file in the directory was out of
   date, so we used Dr. Stine's for a more up-to-date version.
2. Save "riscv_pipelined_ board.sv" and "setup.tcl" together into a differnt area of your files. (setup.tcl can be found in
   Dr. Stine's github)
4. Open a terminal. Change directory into "../ecen4243S25/lab2/lab2".
5. Type "vivado" into the terminal to open vivado.
6. Open a new project.
7. Go to a the Tcl Console.
8. Change directory to where "riscv_pipelined_board.sv" and "setup.tcl" are stored.
9. Type "source setup.tcl" and let vivado load the project.
10. Once it is finished, open hardware manager.
11. Make sure the fpga board is turned on and connected to vivado. Then, while holding BTN0, use Program Device in vivado.
12. Once it loads the waveform, let go of BTN0 to show the given waveform.

The waveform given should look like waveform.jpg from the other given files. For a closer look at the waveforms, waveform_zoom.jpg is provided.
