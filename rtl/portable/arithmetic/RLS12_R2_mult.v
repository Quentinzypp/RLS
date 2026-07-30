`timescale 1ns / 1ps

module RLS12_R2_mult (
    input  wire        aclk,
    input  wire        s_axis_a_tvalid,
    input  wire [47:0] s_axis_a_tdata,
    input  wire        s_axis_b_tvalid,
    input  wire [47:0] s_axis_b_tdata,
    output wire        m_axis_dout_tvalid,
    output wire [95:0] m_axis_dout_tdata
);

    wire signed [23:0] a_re = $signed(s_axis_a_tdata[23:0]);
    wire signed [23:0] a_im = $signed(s_axis_a_tdata[47:24]);
    wire signed [17:0] b_re = $signed(s_axis_b_tdata[17:0]);
    wire signed [17:0] b_im = $signed(s_axis_b_tdata[41:24]);
    wire signed [42:0] result_re;
    wire signed [42:0] result_im;
    wire                result_valid;
    wire [95:0] packed_result = {
        {5{result_im[42]}}, result_im,
        {5{result_re[42]}}, result_re
    };

    asic_complex_multiplier #(
        .A_WIDTH(24),
        .B_WIDTH(18),
        .LATENCY(4)
    ) u_complex_multiplier (
        .clk          (aclk),
        .a_valid      (s_axis_a_tvalid),
        .a_re         (a_re),
        .a_im         (a_im),
        .b_valid      (s_axis_b_tvalid),
        .b_re         (b_re),
        .b_im         (b_im),
        .result_valid (result_valid),
        .result_re    (result_re),
        .result_im    (result_im)
    );

`ifdef PHASE2_VENDOR_MIXED_SIM
    assign #0.1 m_axis_dout_tvalid = result_valid;
    assign #0.1 m_axis_dout_tdata = packed_result;
`else
    assign m_axis_dout_tvalid = result_valid;
    assign m_axis_dout_tdata = packed_result;
`endif

endmodule
