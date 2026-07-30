`timescale 1ns / 1ps

module RLS12_pack_fifo (
    input  wire        rst,
    input  wire        wr_clk,
    input  wire        rd_clk,
    input  wire [47:0] din,
    input  wire        wr_en,
    input  wire        rd_en,
    output wire [47:0] dout,
    output wire        full,
    output wire        empty,
    output wire [13:0] rd_data_count,
    output wire        wr_rst_busy,
    output wire        rd_rst_busy
);

    // Legacy port retained; every active caller ties rd_clk to wr_clk.
    asic_pack_sync_fifo #(
        .WIDTH(48),
        .DEPTH(16384),
        .RESET_HOLD_CYCLES(16),
        .WRITE_VISIBILITY_DELAY(5)
    ) u_fifo (
        .clk(wr_clk),
        .arst(rst),
        .din(din),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .dout(dout),
        .full(full),
        .empty(empty),
        .rd_data_count(rd_data_count),
        .wr_rst_busy(wr_rst_busy),
        .rd_rst_busy(rd_rst_busy)
    );

endmodule
