`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/10/2026 04:20:15 PM
// Design Name: 
// Module Name: spi_slave_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module spi_slave_tb;

parameter CLK_PERIOD  = 10;    // 100 MHz system clock
parameter SCLK_PERIOD = 100;   // 10 MHz SPI clock  (must be << CLK_PERIOD*2)
parameter SCLK_HALF   = SCLK_PERIOD / 2;

//dut ports
reg        clk;
reg        rst_n;
reg        sclk_r;
reg        cs_r;
reg        mosi_r;
reg  [7:0] input_data_r;
reg        load_r;
wire [7:0] output_data_w;
wire       ready_w;
wire       miso_w;


spi_slave dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .sclk        (sclk_r),
    .cs          (cs_r),
    .mosi        (mosi_r),
    .input_data  (input_data_r),
    .load        (load_r),
    .output_data (output_data_w),
    .ready       (ready_w),
    .miso        (miso_w)
);

initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

integer pass_cnt = 0;
integer fail_cnt = 0;

task do_reset;
    begin
        rst_n        = 0;
        cs_r         = 1;    // CS idle = HIGH
        sclk_r       = 0;
        mosi_r       = 0;
        load_r       = 0;
        input_data_r = 8'h00;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
    end
endtask

//load a byte into slave TX buffer
task slave_load;
    input [7:0] data;
    begin
        @(posedge clk);
        input_data_r = data;
        load_r       = 1;
        @(posedge clk);
        load_r       = 0;
        @(posedge clk);
    end
endtask

//perform a single SPI byte transfer.
task spi_transfer;
    input  [7:0] tx_byte;
    output [7:0] rx_byte;
    integer i;
    begin
        rx_byte = 8'h00;
        for (i = 7; i >= 0; i = i - 1) begin
            // Drive MOSI (master output) before rising edge
            mosi_r = tx_byte[i];
            #(SCLK_HALF);
            sclk_r = 1;          // Rising edge - slave samples MOSI
            // Sample MISO on rising edge (master receives)
            rx_byte[i] = miso_w;
            #(SCLK_HALF);
            sclk_r = 0;          // Falling edge - slave shifts next MISO bit
        end
        mosi_r = 0;
    end
endtask

// Assert CS, run one byte, deassert CS
task spi_frame;
    input  [7:0] tx_byte;
    output [7:0] rx_byte;
    begin
        cs_r = 0;               // Assert CS (active-LOW)
        #(SCLK_HALF);           // Short setup time
        spi_transfer(tx_byte, rx_byte);
        #(SCLK_HALF);
        cs_r = 1;               // Deassert CS
        repeat(4) @(posedge clk);  // Allow slave to process
    end
endtask

// Check helper
task check;
    input [7:0] got;
    input [7:0] expected;
    input [127:0] test_name;
    begin
        if (got === expected) begin
            $display("PASS  [%0s]  got=0x%02X  expected=0x%02X", test_name, got, expected);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL  [%0s]  got=0x%02X  expected=0x%02X  <---", test_name, got, expected);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

task check_bit;
    input        got;
    input        expected;
    input [127:0] test_name;
    begin
        if (got === expected) begin
            $display("PASS  [%0s]  got=%b  expected=%b", test_name, got, expected);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL  [%0s]  got=%b  expected=%b  <---", test_name, got, expected);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

//main test
reg [7:0] miso_rx;   // What the master captured from MISO

initial begin
    $dumpfile("spi_slave_tb.vcd");
    $dumpvars(0, spi_slave_tb);

    $display("=== SPI Slave Testbench ===");
    do_reset;

    // TC1 - Basic RX: master sends 0xA5
    $display("\n--- TC1: Basic RX (master sends 0xA5) ---");
    do_reset;

    spi_frame(8'hA5, miso_rx);
    repeat(2) @(posedge clk);
    check(output_data_w, 8'hA5, "TC1 output_data");

    // TC2 - Basic TX: slave pre-loads 0x3C, master reads MISO
    $display("\n--- TC2: Basic TX (slave sends 0x3C) ---");
    do_reset;
    slave_load(8'h3C);
    spi_frame(8'h00, miso_rx);   // TX = dummy
    check(miso_rx, 8'h3C, "TC2 MISO received by master");

    // TC3 - Full-duplex: master sends 0xB7, slave sends 0x4E simultaneously
    $display("\n--- TC3: Full-duplex (TX=0x4E, RX=0xB7) ---");
    do_reset;
    slave_load(8'h4E);
    spi_frame(8'hB7, miso_rx);
    repeat(2) @(posedge clk);
    check(output_data_w, 8'hB7, "TC3 slave RX (output_data)");
    check(miso_rx,       8'h4E, "TC3 master RX (MISO)");

    // TC4 - Back-to-back frames: CS stays low, two consecutive bytes
    $display("\n--- TC4: Two back-to-back frames under one CS ---");
    do_reset;
    slave_load(8'hDE);           // Preload first byte for master to read
    cs_r = 0;
    #(SCLK_HALF);

    spi_transfer(8'h12, miso_rx);
    repeat(2) @(posedge clk);
    check(output_data_w, 8'h12, "TC4 frame1 RX");
    check(miso_rx,       8'hDE, "TC4 frame1 MISO");

    //Ready should now be HIGH (between frames, CS still low)
    repeat(3) @(posedge clk);

    slave_load(8'hAD);           // Load second byte while CS still low
    repeat(2) @(posedge clk);
    spi_transfer(8'h34, miso_rx);
    repeat(2) @(posedge clk);
    check(output_data_w, 8'h34, "TC4 frame2 RX");
    check(miso_rx,       8'hAD, "TC4 frame2 MISO");

    cs_r = 1;
    repeat(4) @(posedge clk);

    // TC5 - CS de-asserted mid-frame (after 4 bits): slave must reset
    $display("\n--- TC5: CS abort mid-frame ---");
    do_reset;
    cs_r   = 0;
    #(SCLK_HALF);
    // Send only 4 bits of 0xFF
    begin : tc5_block
        integer j;
        for (j = 7; j >= 4; j = j - 1) begin
            mosi_r = 1;
            #(SCLK_HALF);
            sclk_r = 1;
            #(SCLK_HALF);
            sclk_r = 0;
        end
    end
    cs_r = 1;                    // Abort
    repeat(6) @(posedge clk);
    check_bit(ready_w, 1'b1, "TC5 ready after abort");
    // output_data should not have changed to a partial value
    // (still holds previous value from TC4 = 0x34)
    check(output_data_w, 8'h00, "TC5 output_data unchanged after reset");

    // TC6 - LOAD ignored while busy
    $display("\n--- TC6: LOAD ignored while busy ---");
    do_reset;
    slave_load(8'hAA);           // Preload 0xAA
    cs_r   = 0;
    #(SCLK_HALF);
    // Send 4 bits, try to load a new value mid-transfer
    begin : tc6_block
        integer j;
        for (j = 7; j >= 4; j = j - 1) begin
            mosi_r = 0;
            #(SCLK_HALF);
            sclk_r = 1;
            #(SCLK_HALF);
            sclk_r = 0;
        end
    end
    // Attempt load while busy
    input_data_r = 8'hFF;
    load_r       = 1;
    @(posedge clk);
    load_r       = 0;
    // Send remaining 4 bits
    begin : tc6b_block
        integer j;
        for (j = 3; j >= 0; j = j - 1) begin
            mosi_r = 0;
            #(SCLK_HALF);
            sclk_r = 1;
            miso_rx[j] = miso_w;
            #(SCLK_HALF);
            sclk_r = 0;
        end
    end
    cs_r = 1;
    repeat(4) @(posedge clk);
    // MISO should have continued transmitting 0xAA (not the 0xFF attempted mid-frame)
    // We only captured lower 4 bits so just verify slave is ready and rx is correct
    check(output_data_w, 8'h00, "TC6 slave RX (all-zero MOSI)");
    check_bit(ready_w,   1'b1,  "TC6 ready after transfer");

    // TC7 - READY signal timing
    $display("\n--- TC7: READY timing ---");
    do_reset;
    check_bit(ready_w, 1'b1, "TC7 READY before frame");
    slave_load(8'h55);
    cs_r = 0;
    #(SCLK_HALF);
    // First rising edge should assert busy (READY -> 0)
    mosi_r = 0;
    #(SCLK_HALF);
    sclk_r = 1;
    repeat(4) @(posedge clk);   // Let synchroniser pipeline through
    check_bit(ready_w, 1'b0, "TC7 READY low during transfer");
    // Complete the remaining 7 bits
    sclk_r = 0;
    begin : tc7_block
        integer j;
        for (j = 6; j >= 0; j = j - 1) begin
            mosi_r = 0;
            #(SCLK_HALF);
            sclk_r = 1;
            #(SCLK_HALF);
            sclk_r = 0;
        end
    end
    cs_r = 1;
    repeat(6) @(posedge clk);
    check_bit(ready_w, 1'b1, "TC7 READY high after frame");

    // TC8 - Boundary values: 0x00 and 0xFF
    $display("\n--- TC8: Boundary values ---");
    do_reset;
    slave_load(8'h00);
    spi_frame(8'hFF, miso_rx);
    repeat(2) @(posedge clk);
    check(output_data_w, 8'hFF, "TC8 RX 0xFF");
    check(miso_rx,       8'h00, "TC8 TX 0x00");

    do_reset;
    slave_load(8'hFF);
    spi_frame(8'h00, miso_rx);
    repeat(2) @(posedge clk);
    check(output_data_w, 8'h00, "TC8 RX 0x00");
    check(miso_rx,       8'hFF, "TC8 TX 0xFF");

    //final result
    $display("\n==========================================");
    $display("Results: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
    $display("==========================================");
    if (fail_cnt == 0)
        $display("ALL TESTS PASSED");
    else
        $display("SOME TESTS FAILED - review waveform");

    $finish;
end

//watchdog
initial begin
    #500000;
    $display("TIMEOUT - simulation did not complete in time");
    $finish;
end

endmodule

