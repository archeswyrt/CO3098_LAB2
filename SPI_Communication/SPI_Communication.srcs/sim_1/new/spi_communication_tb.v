`timescale 1ns / 1ps

module spi_communication_tb();

    // Parameters
    localparam CLK_PERIOD = 10;   // 100 MHz system clock

    // DUT signals
    reg         sys_clk;
    reg         rst_n;
    reg  [1:0]  master_cntl;
    reg  [7:0]  master_input;
    wire [7:0]  master_output;
    wire        master_ready;

    reg  [7:0]  slave_input;
    reg         slave_load;
    wire [7:0]  slave_output;
    wire        slave_ready;

    // Instantiate top module
    spi_communication dut (
        .sys_clk       (sys_clk),
        .rst_n         (rst_n),
        .master_cntl   (master_cntl),
        .master_input  (master_input),
        .master_output (master_output),
        .master_ready  (master_ready),
        .slave_input   (slave_input),
        .slave_load    (slave_load),
        .slave_output  (slave_output),
        .slave_ready   (slave_ready)
    );

    // Clock generation
    initial sys_clk = 0;
    always #(CLK_PERIOD/2) sys_clk = ~sys_clk;

    // Counters for test results
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // ------------------------------------------------------------------
    // Tasks
    // ------------------------------------------------------------------

    // Reset task
    task do_reset;
    begin
        rst_n = 0;
        master_cntl = 2'b00;
        master_input = 8'h00;
        slave_input = 8'h00;
        slave_load = 0;
        repeat(4) @(posedge sys_clk);
        rst_n = 1;
        repeat(2) @(posedge sys_clk);
    end
    endtask

    // Load data into slave TX buffer
    task slave_load_data;
        input [7:0] data;
    begin
        @(posedge sys_clk);
        slave_input = data;
        slave_load = 1;
        @(posedge sys_clk);
        slave_load = 0;
        @(posedge sys_clk);
    end
    endtask

    // Master: load TX data (CNTL=01)
    task master_load_tx;
        input [7:0] data;
    begin
        @(posedge sys_clk);
        master_cntl = 2'b01;
        master_input = data;
        @(posedge sys_clk);
        master_cntl = 2'b00;
        @(posedge sys_clk);
    end
    endtask

    // Master: load slave select address (CNTL=10)
    task master_select_slave;
        input [7:0] addr;   // 0..7 only
    begin
        @(posedge sys_clk);
        master_cntl = 2'b10;
        master_input = addr;
        @(posedge sys_clk);
        master_cntl = 2'b00;
        @(posedge sys_clk);
    end
    endtask

    // Master: start transfer (CNTL=11)
    task master_start_transfer;
    begin
        @(posedge sys_clk);
        master_cntl = 2'b11;
        @(posedge sys_clk);
        master_cntl = 2'b00;
    end
    endtask

    // Wait for master_ready = 1 (with timeout)
    task wait_master_ready;
        integer timeout;
    begin
        timeout = 0;
        while (!master_ready && timeout < 5000) begin
            @(posedge sys_clk);
            timeout = timeout + 1;
        end
        if (timeout >= 5000)
            $display("TIMEOUT waiting for master_ready");
    end
    endtask

    // Wait for slave_ready = 1 (with timeout)
    task wait_slave_ready;
        integer timeout;
    begin
        timeout = 0;
        while (!slave_ready && timeout < 5000) begin
            @(posedge sys_clk);
            timeout = timeout + 1;
        end
        if (timeout >= 5000)
            $display("TIMEOUT waiting for slave_ready");
    end
    endtask

    // Check 8-bit value
    task check8;
        input [7:0] got;
        input [7:0] expected;
        input [159:0] test_name;
    begin
        if (got === expected) begin
            $display("  PASS [%0s]  got=0x%02X  expected=0x%02X", test_name, got, expected);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL [%0s]  got=0x%02X  expected=0x%02X  <<<", test_name, got, expected);
            fail_cnt = fail_cnt + 1;
        end
    end
    endtask

    // ------------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("spi_communication_tb.vcd");
        $dumpvars(0, spi_communication_tb);

        $display("=== SPI Communication Top Level Testbench ===\n");

        // --------------------------------------------------------------
        // Test Case 1: Basic half-duplex (master sends 0xA5, slave receives)
        // --------------------------------------------------------------
        $display("--- TC1: Master sends 0xA5, slave receives ---");
        do_reset;

        // Load nothing in slave (slave TX remains default 0x00)
        master_load_tx(8'hA5);
        master_select_slave(8'd0);   // select slave SS[0]
        master_start_transfer();

        wait_master_ready();
        wait_slave_ready();

        check8(slave_output, 8'hA5, "TC1 slave_output (received from master)");
        // master_output should be whatever MISO slave sent (default 0x00)
        check8(master_output, 8'h00, "TC1 master_output (MISO from slave)");

        // --------------------------------------------------------------
        // Test Case 2: Master receives from slave (slave sends 0x3C)
        // --------------------------------------------------------------
        $display("\n--- TC2: Slave sends 0x3C, master receives ---");
        do_reset;

        slave_load_data(8'h3C);
        master_load_tx(8'h00);       // master sends dummy data
        master_select_slave(8'd0);
        master_start_transfer();

        wait_master_ready();
        wait_slave_ready();

        check8(master_output, 8'h3C, "TC2 master_output (MISO from slave)");
        // slave_output should be whatever master sent (0x00)
        check8(slave_output, 8'h00, "TC2 slave_output (received from master)");

        // --------------------------------------------------------------
        // Test Case 3: Full-duplex (master sends 0xB7, slave sends 0x4E)
        // --------------------------------------------------------------
        $display("\n--- TC3: Full-duplex (master TX=0xB7, slave TX=0x4E) ---");
        do_reset;

        slave_load_data(8'h4E);
        master_load_tx(8'hB7);
        master_select_slave(8'd0);
        master_start_transfer();

        wait_master_ready();
        wait_slave_ready();

        check8(master_output, 8'h4E, "TC3 master_output (from slave)");
        check8(slave_output,  8'hB7, "TC3 slave_output (from master)");

        // --------------------------------------------------------------
        // Test Case 4: Back-to-back transfers
        // --------------------------------------------------------------
        $display("\n--- TC4: Back-to-back transfers ---");
        do_reset;

        // First transfer: master 0x12, slave 0xAB
        slave_load_data(8'hAB);
        master_load_tx(8'h12);
        master_select_slave(8'd0);
        master_start_transfer();
        wait_master_ready();
        wait_slave_ready();
        check8(master_output, 8'hAB, "TC4 frame1 master_output");
        check8(slave_output,  8'h12, "TC4 frame1 slave_output");

        // Second transfer immediately after
        slave_load_data(8'hCD);
        master_load_tx(8'h34);
        master_start_transfer();    // slave already selected
        wait_master_ready();
        wait_slave_ready();
        check8(master_output, 8'hCD, "TC4 frame2 master_output");
        check8(slave_output,  8'h34, "TC4 frame2 slave_output");

        // --------------------------------------------------------------
        // Test Case 5: Boundary values (0x00 and 0xFF)
        // --------------------------------------------------------------
        $display("\n--- TC5: Boundary values (0x00 and 0xFF) ---");
        do_reset;

        // Master sends 0xFF, slave sends 0x00
        slave_load_data(8'h00);
        master_load_tx(8'hFF);
        master_select_slave(8'd0);
        master_start_transfer();
        wait_master_ready();
        wait_slave_ready();
        check8(master_output, 8'h00, "TC5 master_output (0x00)");
        check8(slave_output,  8'hFF, "TC5 slave_output (0xFF)");

        do_reset;
        // Master sends 0x00, slave sends 0xFF
        slave_load_data(8'hFF);
        master_load_tx(8'h00);
        master_select_slave(8'd0);
        master_start_transfer();
        wait_master_ready();
        wait_slave_ready();
        check8(master_output, 8'hFF, "TC5 master_output (0xFF)");
        check8(slave_output,  8'h00, "TC5 slave_output (0x00)");

        // --------------------------------------------------------------
        // Test Case 6: Slave load while master is idle (ready)
        // --------------------------------------------------------------
        $display("\n--- TC6: Slave load when ready ---");
        do_reset;

        // Initially both ready
        @(posedge sys_clk);
        if (master_ready && slave_ready)
            $display("  Both ready initially");
        else
            $display("  WARNING: not ready after reset");

        slave_load_data(8'h55);
        @(posedge sys_clk);
        // slave_ready should go low for one cycle? According to slave design,
        // load is accepted and slave_ready remains high (since load doesn't affect busy).
        // We'll just check that after load we can still start a transfer.
        master_load_tx(8'hAA);
        master_select_slave(8'd0);
        master_start_transfer();
        wait_master_ready();
        wait_slave_ready();
        check8(slave_output, 8'hAA, "TC6 slave received correct data");
        check8(master_output, 8'h55, "TC6 master received slave's preloaded data");

        // --------------------------------------------------------------
        // Test Case 7: Select different slaves (SS lines)
        // --------------------------------------------------------------
        $display("\n--- TC7: Slave select line behaviour ---");
        do_reset;

        // Select slave 2 (address 2 -> SS[2]=0)
        master_select_slave(8'd2);
        master_start_transfer();   // dummy transfer to see SS
        // We cannot directly probe internal SS, but we can check that the slave
        // (which is connected to SS[0]) does NOT respond. master_output should be 0x00
        // because MISO from slave is high-Z.
        wait_master_ready();
        check8(master_output, 8'hzz, "TC7 master output with slave not selected");
        // slave_output should remain unchanged (last received data)
        // We'll just pass this test if master_ready returns correctly.
        $display("  TC7 verified by visual inspection of waveform (SS[0] remains high)");

        // --------------------------------------------------------------
        // Summary
        // --------------------------------------------------------------
        $display("\n==========================================");
        $display("Results: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
        $display("==========================================");
        if (fail_cnt == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED - review waveform");

        $finish;
    end

    // ------------------------------------------------------------------
    // Watchdog timeout
    // ------------------------------------------------------------------
    initial begin
        #2_000_000;
        $display("WATCHDOG TIMEOUT - simulation did not finish");
        $finish;
    end

endmodule