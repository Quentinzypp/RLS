`timescale 1ns / 1ps

module RLS12_delay_coe_pluse (
    input  wire [12:0] D,
    input  wire        CLK,
    input  wire        SCLR,
    output wire [12:0] Q
);

    wire [12:0] shifted_data;

    asic_shift_delay #(
        .WIDTH(13),
        .DEPTH(16),
        .CLEAR_STORAGE_ON_SCLR(1)
    ) u_shift_delay (
        .clk(CLK),
        .sclr(SCLR),
        .data_in(D),
        .data_out(shifted_data)
    );

`ifdef PHASE2_VENDOR_MIXED_SIM
    assign #0.1 Q = shifted_data;
`else
    assign Q = shifted_data;
`endif

endmodule
