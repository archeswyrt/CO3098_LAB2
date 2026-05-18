`timescale 1ns / 1ps

module spi_communication (
    // Hệ thống
    input  wire       sys_clk,     // clock chung cho cả master và slave
    input  wire       rst_n,       // reset active LOW

    // Điều khiển master (từ testbench)
    input  wire [1:0] master_cntl,
    input  wire [7:0] master_input,
    output wire [7:0] master_output,
    output wire       master_ready,

    // Điều khiển slave (từ testbench)
    input  wire [7:0] slave_input,
    input  wire       slave_load,
    output wire [7:0] slave_output,
    output wire       slave_ready
);

    // Dây nội bộ kết nối master và slave (SPI bus)
    wire        w_sclk;
    wire        w_mosi;
    wire        w_miso;
    wire [7:0]  w_ss;          // master xuất 8 dây slave select

    // Instantiate SPI Master (code của bạn 1)
    spi_master u_master (
        .refclk      (sys_clk),
        .rst_n       (rst_n),
        .cntl        (master_cntl),
        .input_data  (master_input),
        .output_data (master_output),
        .ready       (master_ready),
        .sclk        (w_sclk),
        .mosi        (w_mosi),
        .miso        (w_miso),
        .ss          (w_ss)
    );

    // Instantiate SPI Slave (code của bạn 2)
    // Lưu ý: slave chỉ dùng 1 chân CS, nối với bit thấp nhất của SS master
    spi_slave u_slave (
        .clk         (sys_clk),
        .rst_n       (rst_n),
        .input_data  (slave_input),
        .load        (slave_load),
        .output_data (slave_output),
        .ready       (slave_ready),
        .sclk        (w_sclk),
        .mosi        (w_mosi),
        .miso        (w_miso),
        .cs          (w_ss[0])     // chọn slave số 0
    );

endmodule