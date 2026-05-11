`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/10/2026 04:13:19 PM
// Design Name: 
// Module Name: spi_slave
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

module spi_slave(
    // System
    input  wire       clk,          // System clock (must be >> 2x SCLK rate)
    input  wire       rst_n,        // Asynchronous reset, active-LOW

    // SPI bus inputs (asynchronous to clk)
    input  wire       sclk,
    input  wire       cs,           // Active-LOW chip select
    input  wire       mosi,

    // Control / data (left-side ports per spec)
    input  wire [7:0] input_data,   // INPUT
    input  wire       load,         // LOAD
    output reg  [7:0] output_data,  // OUTPUT
    output wire       ready,        // READY

    //SPI bus output
    output wire       miso
    );
    
    //dong bo hoa SPI
    reg [2:0] sclk_sync, cs_sync, mosi_sync;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync <= 3'b000;
            cs_sync   <= 3'b111;   //idle high
            mosi_sync <= 3'b000;
        end else begin
            sclk_sync <= {sclk_sync[1:0], sclk};
            cs_sync   <= {cs_sync  [1:0], cs  };
            mosi_sync <= {mosi_sync[1:0], mosi};
        end
    end
    
    //edge sclk
    wire sclk_rise = (sclk_sync[2:1] == 2'b01);
    wire sclk_fall = (sclk_sync[2:1] == 2'b10);
    wire cs_sel    = ~cs_sync[1];          // HIGH when slave is selected
    
    //internal registers
    reg [7:0] tx_sr;      // TX shift register (drives MISO)
    reg [7:0] rx_sr;      // RX shift register (accumulates MOSI)
    reg [2:0] bit_cnt;    // Counts received bits within current byte
    reg       busy;       // 1 = transaction in progress, 0 = idle
    reg       miso_r;     // Registered MISO bit
    
    //output
    assign ready = ~busy;
    assign miso  = cs_sel ? miso_r : 1'bz;   // Hi-Z when not selected
    
    //load and input tx
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_sr  <= 8'h00;
            miso_r <= 1'b0;
        end else if (load && ready) begin
            tx_sr  <= input_data;
            miso_r <= input_data[7];   // Pre-drive MSB before SCLK starts
        end
    end
    
    // FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sr       <= 8'h00;
            output_data <= 8'h00;
            bit_cnt     <= 3'd0;
            busy        <= 1'b0;
    
        end else begin
    
            // IDLE
            if (!cs_sel) begin
                bit_cnt <= 3'd0;
                busy    <= 1'b0;
                // tx_sr / miso_r intentionally preserved (LOAD block owns them)
    
            end else begin
    
                //rising sclk edge
                if (sclk_rise) begin
                    rx_sr <= {rx_sr[6:0], mosi_sync[1]};
                    busy  <= 1'b1;    // Mark as busy on first edge
    
                    if (bit_cnt == 3'd7) begin
                        // Last bit - byte complete
                        output_data <= {rx_sr[6:0], mosi_sync[1]};
                        bit_cnt     <= 3'd0;
                        busy        <= 1'b0;   // Ready again
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end
    
                //falling sclk edge, stable
                if (sclk_fall) begin
                    miso_r <= tx_sr[6];              // Present next bit
                    tx_sr  <= {tx_sr[6:0], 1'b0};   // Shift left
                end
    
            end
        end
    end
endmodule
