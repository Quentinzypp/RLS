`timescale 1ns / 1ps

module asic_complex_multiplier #(
    parameter integer A_WIDTH = 36,
    parameter integer B_WIDTH = 24,
    parameter integer LATENCY = 11
) (
    input  wire                                  clk,
    input  wire                                  a_valid,
    input  wire signed [A_WIDTH-1:0]             a_re,
    input  wire signed [A_WIDTH-1:0]             a_im,
    input  wire                                  b_valid,
    input  wire signed [B_WIDTH-1:0]             b_re,
    input  wire signed [B_WIDTH-1:0]             b_im,
    output wire                                  result_valid,
    output wire signed [A_WIDTH+B_WIDTH:0]       result_re,
    output wire signed [A_WIDTH+B_WIDTH:0]       result_im
);

    localparam integer PRODUCT_WIDTH = A_WIDTH + B_WIDTH;
    localparam integer RESULT_WIDTH = PRODUCT_WIDTH + 1;

    wire signed [PRODUCT_WIDTH-1:0] product_ac = $signed(a_re) * $signed(b_re);
    wire signed [PRODUCT_WIDTH-1:0] product_bd = $signed(a_im) * $signed(b_im);
    wire signed [PRODUCT_WIDTH-1:0] product_ad = $signed(a_re) * $signed(b_im);
    wire signed [PRODUCT_WIDTH-1:0] product_bc = $signed(a_im) * $signed(b_re);

    wire signed [RESULT_WIDTH-1:0] full_re =
        {product_ac[PRODUCT_WIDTH-1], product_ac} -
        {product_bd[PRODUCT_WIDTH-1], product_bd};
    wire signed [RESULT_WIDTH-1:0] full_im =
        {product_ad[PRODUCT_WIDTH-1], product_ad} +
        {product_bc[PRODUCT_WIDTH-1], product_bc};

    reg signed [RESULT_WIDTH-1:0] re_pipeline [0:LATENCY-1];
    reg signed [RESULT_WIDTH-1:0] im_pipeline [0:LATENCY-1];
    reg                           valid_pipeline [0:LATENCY-1];
    integer stage;

    always @(posedge clk) begin
        re_pipeline[0] <= full_re;
        im_pipeline[0] <= full_im;
        valid_pipeline[0] <= a_valid && b_valid;
        for (stage = 1; stage < LATENCY; stage = stage + 1) begin
            re_pipeline[stage] <= re_pipeline[stage-1];
            im_pipeline[stage] <= im_pipeline[stage-1];
            valid_pipeline[stage] <= valid_pipeline[stage-1];
        end
    end

    assign result_re = re_pipeline[LATENCY-1];
    assign result_im = im_pipeline[LATENCY-1];
    assign result_valid = valid_pipeline[LATENCY-1];

endmodule
