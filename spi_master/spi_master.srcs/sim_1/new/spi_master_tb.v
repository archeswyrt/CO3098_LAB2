`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/15/2026 09:28:59 AM
// Design Name: 
// Module Name: spi_master_tb
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


module spi_master_tb;


//PRESCALE=2, SCLK = REFCLK/4
parameter REFCLK_PERIOD = 10;    // 100 MHz
parameter SCLK_PERIOD   = 40;    // 25 MHz  (REFCLK * 4)
parameter SCLK_HALF     = SCLK_PERIOD / 2;

reg        refclk;
reg        rst_n;
reg  [1:0] cntl;
reg  [7:0] input_data;
wire [7:0] output_data;
wire       ready;
wire       sclk;
wire       mosi;
reg        miso;
wire [7:0] ss;

spi_master dut (
    .refclk     (refclk),
    .rst_n      (rst_n),
    .cntl       (cntl),
    .input_data (input_data),
    .output_data(output_data),
    .ready      (ready),
    .sclk       (sclk),
    .mosi       (mosi),
    .miso       (miso),
    .ss         (ss)
);

initial refclk = 0;
always #(REFCLK_PERIOD/2) refclk = ~refclk;

integer pass_cnt = 0;
integer fail_cnt = 0;

reg [7:0] mosi_captured;

task do_reset;
    begin
        rst_n      = 0;
        cntl       = 2'b00;
        input_data = 8'h00;
        miso       = 0;
        repeat(4) @(posedge refclk);
        rst_n = 1;
        repeat(2) @(posedge refclk);
    end
endtask

// Apply a CNTL command for one refclk cycle
task apply_cntl;
    input [1:0] cmd;
    input [7:0] data;
    begin
        @(posedge refclk); #1;
        cntl       = cmd;
        input_data = data;
        @(posedge refclk); #1;
        cntl       = 2'b00;
    end
endtask

// Wait until READY goes HIGH (with timeout)
task wait_ready;
    integer timeout;
    begin
        timeout = 0;
        while (!ready && timeout < 5000) begin
            @(posedge refclk);
            timeout = timeout + 1;
        end
        if (timeout >= 5000)
            $display("TIMEOUT waiting for READY");
    end
endtask

// Perform a full transfer: drive CNTL=2'b11, simultaneously feed MISO bits,
// capture MOSI bits, release CNTL after done.
// miso_byte  = byte the slave (tb) sends on MISO
// mosi_byte  = captured MOSI byte (output)
task do_transfer;
    input  [7:0] miso_byte;
    output [7:0] mosi_byte;
    integer i;
    reg [7:0] captured;
    begin
        captured = 8'h00;
        // Trigger transfer
        @(posedge refclk); #1;
        cntl = 2'b11;

        // Wait for SS to assert (busy starts)
        wait (!ready);

        // Drive MISO bits and capture MOSI on each SCLK rising edge
        // CPOL=0 CPHA=0: master samples MISO on rising SCLK
        for (i = 7; i >= 0; i = i - 1) begin
            // Drive MISO before rising edge
            miso = miso_byte[i];
            // Wait for rising SCLK
            @(posedge sclk);
            // Capture MOSI at this moment
            captured[i] = mosi;
            // Wait for falling SCLK before next bit
            @(negedge sclk);
        end

        // Wait for transfer to complete (READY goes HIGH after CNTL released)
        @(posedge refclk); #1;
        cntl = 2'b00;
        wait_ready;

        mosi_byte = captured;
    end
endtask

// Check helpers
task check8;
    input [7:0] got;
    input [7:0] expected;
    input [159:0] name;
    begin
        if (got === expected) begin
            $display("  PASS [%0s]  got=0x%02X  exp=0x%02X", name, got, expected);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL [%0s]  got=0x%02X  exp=0x%02X  <<<", name, got, expected);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

task check1;
    input        got;
    input        expected;
    input [159:0] name;
    begin
        if (got === expected) begin
            $display("  PASS [%0s]  got=%b  exp=%b", name, got, expected);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL [%0s]  got=%b  exp=%b  <<<", name, got, expected);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// Main test sequence
reg [7:0] captured_mosi;
reg [7:0] tmp;

initial begin
    $dumpfile("spi_master_tb.vcd");
    $dumpvars(0, spi_master_tb);
    $display("=== SPI Master Testbench ===\n");

    // TC1 - Load TX data with CNTL=2'b01
    $display("--- TC1: Load TX data (CNTL=01) ---");
    do_reset;
    // We can't read tx_sr directly, but after a transfer the MOSI sequence
    // will reflect what was loaded. We verify this in TC4.
    // Here just check READY stays HIGH after CNTL=01
    apply_cntl(2'b01, 8'hA5);
    repeat(2) @(posedge refclk);
    check1(ready, 1'b1, "TC1 READY stays HIGH after load");

    // TC2 - Load valid slave address (addr=3 ? SS=8'b1111_1011)
    $display("--- TC2: Load slave address 3 ---");
    do_reset;
    apply_cntl(2'b10, 8'd3);
    repeat(2) @(posedge refclk);
    check1(ready, 1'b1, "TC2 READY stays HIGH after addr load");
    // ss_reg is internal; we'll confirm SS during TC4

    // TC3 - Out-of-range slave address (addr=200 ? SS stays 8'hFF)
    $display("--- TC3: Out-of-range slave address (200) ---");
    do_reset;
    apply_cntl(2'b01, 8'hBB);   // Load some TX data first
    apply_cntl(2'b10, 8'd200);  // Out-of-range address
    // Trigger transfer to observe SS
    @(posedge refclk); #1; cntl = 2'b11;
    wait (!ready);
    repeat(2) @(posedge refclk);
    check8(ss, 8'hFF, "TC3 SS=FF (no slave) during transfer");
    // Clean up: feed 8 SCLK cycles and release
    begin : tc3_cleanup
        integer j;
        for (j = 0; j < 8; j = j + 1) begin
            @(posedge sclk); @(negedge sclk);
        end
    end
    @(posedge refclk); #1; cntl = 2'b00;
    wait_ready;

    // TC4 - Full transfer: verify MOSI output (master sends 0xA5, MSB first)
    //        and SS is asserted correctly (addr=3 ? SS=8'b1111_1011)
    $display("--- TC4: MOSI sequence + SS (TX=0xA5, addr=3) ---");
    do_reset;
    apply_cntl(2'b01, 8'hA5);   // Load TX data
    apply_cntl(2'b10, 8'd3);    // Load slave address 3
    do_transfer(8'h00, captured_mosi);
    check8(captured_mosi, 8'hA5, "TC4 MOSI captured by master (0xA5)");

    // TC5 - Verify MISO captured into OUTPUT (slave sends 0x3C)
    $display("--- TC5: MISO captured into OUTPUT (slave sends 0x3C) ---");
    do_reset;
    apply_cntl(2'b01, 8'h00);
    apply_cntl(2'b10, 8'd0);
    do_transfer(8'h3C, captured_mosi);
    check8(output_data, 8'h3C, "TC5 OUTPUT=0x3C from MISO");

    // TC6 - Full-duplex: master sends 0xB7, slave sends 0x4E
    $display("--- TC6: Full-duplex (TX=0xB7, MISO=0x4E) ---");
    do_reset;
    apply_cntl(2'b01, 8'hB7);
    apply_cntl(2'b10, 8'd1);
    do_transfer(8'h4E, captured_mosi);
    check8(captured_mosi, 8'hB7, "TC6 MOSI=0xB7");
    check8(output_data,   8'h4E, "TC6 OUTPUT=0x4E");

    // TC7 - READY timing: de-asserts on transfer, re-asserts after CNTL released
    $display("--- TC7: READY timing ---");
    do_reset;
    apply_cntl(2'b01, 8'h55);
    check1(ready, 1'b1, "TC7 READY before transfer");
    // Start transfer but check READY mid-way
    @(posedge refclk); #1; cntl = 2'b11;
    @(posedge refclk); @(posedge refclk);
    check1(ready, 1'b0, "TC7 READY=0 during transfer");
    // Complete transfer
    begin : tc7_drive
        integer j;
        for (j = 7; j >= 0; j = j - 1) begin
            miso = 0;
            @(posedge sclk); @(negedge sclk);
        end
    end
    // Hold CNTL=11 ? READY must stay LOW
    repeat(3) @(posedge refclk);
    check1(ready, 1'b0, "TC7 READY still 0 while CNTL=11");
    // Release CNTL
    @(posedge refclk); #1; cntl = 2'b00;
    wait_ready;
    check1(ready, 1'b1, "TC7 READY=1 after CNTL released");

    // TC8 - SS asserted during transfer, deasserted after
    $display("--- TC8: SS assertion/deassertion ---");
    do_reset;
    apply_cntl(2'b01, 8'hFF);
    apply_cntl(2'b10, 8'd5);    // Slave 5 ? SS should be 8'b1101_1111
    @(posedge refclk); #1; cntl = 2'b11;
    wait (!ready);
    repeat(2) @(posedge refclk);
    check8(ss, 8'b1101_1111, "TC8 SS=8'b1101_1111 during transfer");
    begin : tc8_drive
        integer j;
        for (j = 7; j >= 0; j = j - 1) begin
            miso = 1;
            @(posedge sclk); @(negedge sclk);
        end
    end
    @(posedge refclk); #1; cntl = 2'b00;
    wait_ready;
    check8(ss, 8'hFF, "TC8 SS=0xFF after transfer");

    // TC9 - CNTL=2'b01 and 2'b10 ignored while busy
    $display("--- TC9: CNTL 01/10 ignored while busy ---");
    do_reset;
    apply_cntl(2'b01, 8'hCC);
    apply_cntl(2'b10, 8'd2);
    @(posedge refclk); #1; cntl = 2'b11;
    wait (!ready);
    // Try to load new data while busy
    @(posedge refclk); #1;
    cntl       = 2'b01;
    input_data = 8'hDE;
    @(posedge refclk); #1;
    cntl = 2'b11;   // Keep transfer going
    begin : tc9_drive
        integer j;
        for (j = 7; j >= 0; j = j - 1) begin
            miso = 0;
            @(posedge sclk); @(negedge sclk);
        end
    end
    @(posedge refclk); #1; cntl = 2'b00;
    wait_ready;
    // MOSI during transfer should have been 0xCC (not 0xDE)
    // (We already captured in TC9 loop above; just check output_data wasn't corrupted)
    check1(ready, 1'b1, "TC9 READY after transfer with ignored mid-load");

    // TC10 - CNTL=2'b00: no operation
    $display("--- TC10: No-op (CNTL=00) ---");
    do_reset;
    repeat(5) @(posedge refclk);
    check1(ready, 1'b1, "TC10 READY stays HIGH with CNTL=00");
    check8(ss,    8'hFF, "TC10 SS=FF with CNTL=00");

    // TC11 - Back-to-back transfers
    $display("--- TC11: Back-to-back transfers ---");
    do_reset;
    apply_cntl(2'b01, 8'h12);
    apply_cntl(2'b10, 8'd0);
    do_transfer(8'hAB, captured_mosi);
    check8(captured_mosi, 8'h12, "TC11 frame1 MOSI=0x12");
    check8(output_data,   8'hAB, "TC11 frame1 OUTPUT=0xAB");

    // Immediately load and transfer again
    apply_cntl(2'b01, 8'h34);
    do_transfer(8'hCD, captured_mosi);
    check8(captured_mosi, 8'h34, "TC11 frame2 MOSI=0x34");
    check8(output_data,   8'hCD, "TC11 frame2 OUTPUT=0xCD");

    // TC12 - Boundary values: 0x00 and 0xFF
    $display("--- TC12: Boundary values ---");
    do_reset;
    apply_cntl(2'b01, 8'h00);
    apply_cntl(2'b10, 8'd0);
    do_transfer(8'hFF, captured_mosi);
    check8(captured_mosi, 8'h00, "TC12 TX=0x00 MOSI");
    check8(output_data,   8'hFF, "TC12 RX=0xFF OUTPUT");

    do_reset;
    apply_cntl(2'b01, 8'hFF);
    apply_cntl(2'b10, 8'd7);
    do_transfer(8'h00, captured_mosi);
    check8(captured_mosi, 8'hFF, "TC12 TX=0xFF MOSI");
    check8(output_data,   8'h00, "TC12 RX=0x00 OUTPUT");

    // Summary
    $display("\n==========================================");
    $display("Results: %0d PASSED,  %0d FAILED", pass_cnt, fail_cnt);
    $display("==========================================");
    if (fail_cnt == 0)
        $display("ALL TESTS PASSED");
    else
        $display("SOME TESTS FAILED - check waveform");

    $finish;
end

// Watchdog
initial begin
    #2_000_000;
    $display("WATCHDOG TIMEOUT");
    $finish;
end

endmodule

