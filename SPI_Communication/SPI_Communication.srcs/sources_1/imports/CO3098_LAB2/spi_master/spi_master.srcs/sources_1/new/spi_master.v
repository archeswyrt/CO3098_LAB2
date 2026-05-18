`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/15/2026 09:26:57 AM
// Design Name: 
// Module Name: spi_master
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


module spi_master (
    // System
    input  wire       refclk,       // Reference clock (posedge-triggered)
    input  wire       rst_n,        // Async reset, active-LOW

    // Control / data (left-side ports per spec)
    input  wire [1:0] cntl,         // CNTL
    input  wire [7:0] input_data,   // INPUT
    output reg  [7:0] output_data,  // OUTPUT
    output wire       ready,        // READY (active-HIGH)

    // SPI bus
    output wire       sclk,         // SPI clock to slave
    output reg        mosi,         // Master to Slave
    input  wire       miso,         // Slave to Master
    output reg  [7:0] ss            // Slave select (active-LOW), idle=8'hFF
);


localparam PRESCALE = 4;   // SCLK = REFCLK / (2 * PRESCALE) = REFCLK/4

// SCLK generation: 2-bit counter, toggle internal SCLK every PRESCALE cycles
// SCLK is gated: only toggles during an active transfer (or stays LOW)
reg [1:0]  pre_cnt;        // Prescaler counter
reg        sclk_r;         // Internal SCLK register
reg        sclk_en;        // Gate: enable SCLK toggling during transfer

// SCLK output: only active during transfer, idle LOW (CPOL=0)
assign sclk = sclk_r & sclk_en;

// Rising / falling edge of internal SCLK (used for sample / shift timing)
reg sclk_prev;
wire sclk_rise = ( sclk_r & ~sclk_prev) & sclk_en;
wire sclk_fall = (~sclk_r &  sclk_prev) & sclk_en;

always @(posedge refclk or negedge rst_n) begin
    if (!rst_n) begin
        pre_cnt   <= 2'd0;
        sclk_r    <= 1'b0;
        sclk_prev <= 1'b0;
    end else begin
        sclk_prev <= sclk_r;
        if (sclk_en) begin
            if (pre_cnt == PRESCALE - 1) begin
                pre_cnt <= 2'd0;
                sclk_r  <= ~sclk_r;
            end else begin
                pre_cnt <= pre_cnt + 1'b1;
            end
        end else begin
            pre_cnt <= 2'd0;
            sclk_r  <= 1'b0;
        end
    end
end


// Internal registers
reg [7:0] tx_sr;       // TX shift register (MOSI path)
reg [7:0] rx_sr;       // RX shift register (MISO path)
reg [7:0] ss_reg;      // Pending SS value (set by CNTL=2'b10)
reg [2:0] bit_cnt;     // Counts bits transferred (0-7)
reg       busy;        // 1 = transfer in progress

assign ready = ~busy;


// FSM states
localparam IDLE    = 2'd0;
localparam PREPARE = 2'd1;   // Assert SS, wait half SCLK before first edge
localparam XFER    = 2'd2;   // Active 8-bit transfer
localparam DONE    = 2'd3;   // Deassert SS, wait for CNTL != 2'b11

reg [1:0] state;

// Main FSM - posedge REFCLK (per spec: "except SPI transmission")
always @(posedge refclk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= IDLE;
        busy        <= 1'b0;
        sclk_en     <= 1'b0;
        tx_sr       <= 8'h00;
        rx_sr       <= 8'h00;
        output_data <= 8'h00;
        bit_cnt     <= 3'd0;
        mosi        <= 1'b0;
        ss          <= 8'hFF;    // All slaves deselected
        ss_reg      <= 8'hFF;
    end else begin
        case (state)
            // IDLE: process CNTL commands, wait for 2'b11
            IDLE: begin
                busy    <= 1'b0;
                sclk_en <= 1'b0;

                case (cntl)
                    2'b00: begin
                        // No operation
                    end

                    2'b01: begin
                        // Load TX data
                        if (ready) begin
                            tx_sr <= input_data;
                        end
                    end

                    2'b10: begin
                        // Load slave select address
                        if (ready) begin
                            if (input_data <= 8'd7) begin
                                // Decode: set only the selected slave bit LOW
                                ss_reg <= ~(8'h01 << input_data[2:0]);
                            end else begin
                                ss_reg <= 8'hFF;   // Out of range ? no slave
                            end
                        end
                    end

                    2'b11: begin
                        // Begin transfer
                        if (ready) begin
                            state   <= PREPARE;
                            busy    <= 1'b1;
                            bit_cnt <= 3'd0;
                            rx_sr   <= 8'h00;
                        end
                    end
                endcase
            end

            // PREPARE: Assert SS and pre-drive MOSI MSB before first SCLK edge
            PREPARE: begin
                ss      <= ss_reg;          // Assert slave select
                mosi    <= tx_sr[7];        // Pre-drive MSB (CPHA=0)
                sclk_en <= 1'b1;            // Start SCLK toggling
                state   <= XFER;
            end

            // XFER: Shift data in/out on SCLK edges
            //   Rising  edge: sample MISO
            //   Falling edge: shift out next MOSI bit
            XFER: begin
                // Sample MISO on rising SCLK
                if (sclk_rise) begin
                    rx_sr   <= {rx_sr[6:0], miso};
                    bit_cnt <= bit_cnt + 1'b1;
                    if (bit_cnt == 3'd7) begin
                        output_data <= {rx_sr[6:0], miso};
                        sclk_en     <= 1'b0;
                        state       <= DONE;
                    end
                end
                // Shift next MOSI bit on falling SCLK
                if (sclk_fall) begin
                    tx_sr <= {tx_sr[6:0], 1'b0};
                    mosi  <= tx_sr[6];   // Next bit after current MSB
                end
            end

            // DONE: Deassert SS, wait until CNTL is no longer 2'b11
            //       Per spec: "READY only when transfer complete AND CNTL != 2'b11"
            DONE: begin
                ss   <= 8'hFF;    // Deassert all slaves
                mosi <= 1'b0;

                if (cntl != 2'b11) begin
                    busy  <= 1'b0;
                    state <= IDLE;
                end
            end

        endcase
    end
end

endmodule
