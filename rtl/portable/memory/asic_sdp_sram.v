`timescale 1ns / 1ps

module asic_sdp_sram #(
    parameter integer WIDTH = 48,
    parameter integer DEPTH = 16,
    parameter integer ADDR_WIDTH = 4,
    parameter integer HAS_READ_ENABLE = 0,
    // 0: old data, 1: new data, 2: hold previous read output.
    parameter integer READ_DURING_WRITE_MODE = 1
) (
    input  wire                  clk,
    input  wire                  wr_en,
    input  wire                  rd_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [WIDTH-1:0]      wr_data,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [WIDTH-1:0]      rd_data
);

`ifndef ASIC_SRAM_BLACKBOX
    localparam integer READ_OLD_DATA = 0;
    localparam integer READ_NEW_DATA = 1;
    localparam integer READ_HOLD = 2;

    reg [WIDTH-1:0] storage [0:DEPTH-1];
    wire same_address_write = wr_en && (wr_addr == rd_addr);
    wire read_active = HAS_READ_ENABLE ? rd_en : 1'b1;

    always @(posedge clk) begin
        if (wr_en) begin
            storage[wr_addr] <= wr_data;
        end

        if (read_active) begin
            if (same_address_write) begin
                case (READ_DURING_WRITE_MODE)
                    READ_NEW_DATA: rd_data <= wr_data;
                    READ_HOLD: rd_data <= rd_data;
                    default: rd_data <= storage[rd_addr];
                endcase
            end
            else begin
                rd_data <= storage[rd_addr];
            end
        end
    end
`endif

endmodule
