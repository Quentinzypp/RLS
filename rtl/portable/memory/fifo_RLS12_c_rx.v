`timescale 1ns / 1ps

module fifo_RLS12_c_rx (
    input  wire        clk,
    input  wire        srst,
    input  wire [47:0] din,
    input  wire        wr_en,
    input  wire        rd_en,
    output wire [47:0] dout,
    output wire        full,
    output wire        empty,
    output wire        valid,
    output wire        wr_rst_busy,
    output wire        rd_rst_busy
);

    wire overflow_unused;
    wire underflow_unused;

    asic_sync_fifo #(
        .WIDTH(48),
        .DEPTH(16384)
    ) u_fifo (
        .clk(clk),
        .srst(srst),
        .din(din),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .dout(dout),
        .full(full),
        .empty(empty),
        .valid(valid),
        .overflow(overflow_unused),
        .underflow(underflow_unused),
        .wr_rst_busy(wr_rst_busy),
        .rd_rst_busy(rd_rst_busy)
    );

endmodule
