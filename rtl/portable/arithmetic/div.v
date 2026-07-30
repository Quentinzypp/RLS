`timescale 1ns / 1ps

module div (
    input  wire        aclk,
    input  wire        s_axis_divisor_tvalid,
    output wire        s_axis_divisor_tready,
    input  wire [39:0] s_axis_divisor_tdata,
    input  wire        s_axis_dividend_tvalid,
    output wire        s_axis_dividend_tready,
    input  wire [39:0] s_axis_dividend_tdata,
    output wire        m_axis_dout_tvalid,
    output wire [71:0] m_axis_dout_tdata
);

    wire result_valid;
    wire signed [71:0] result_data;
    wire divide_by_zero_unused;

    asic_signed_fractional_divider #(
        .INPUT_WIDTH(40),
        .FRACTIONAL_WIDTH(32),
        .OUTPUT_WIDTH(72),
        .LATENCY(41)
    ) u_signed_fractional_divider (
        .clk            (aclk),
        .divisor_valid  (s_axis_divisor_tvalid),
        .divisor_ready  (s_axis_divisor_tready),
        .divisor_data   ($signed(s_axis_divisor_tdata)),
        .dividend_valid (s_axis_dividend_tvalid),
        .dividend_ready (s_axis_dividend_tready),
        .dividend_data  ($signed(s_axis_dividend_tdata)),
        .result_valid   (result_valid),
        .result_data    (result_data),
        .divide_by_zero (divide_by_zero_unused)
    );

`ifdef PHASE2_VENDOR_MIXED_SIM
    assign #0.1 m_axis_dout_tvalid = result_valid;
    assign #0.1 m_axis_dout_tdata = result_data;
`else
    assign m_axis_dout_tvalid = result_valid;
    assign m_axis_dout_tdata = result_data;
`endif

endmodule
