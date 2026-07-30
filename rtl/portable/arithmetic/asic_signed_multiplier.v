`timescale 1ns / 1ps

module asic_signed_multiplier #(
    parameter integer A_WIDTH = 25,
    parameter integer B_WIDTH = 25
) (
    input  wire                              clk,
    input  wire signed [A_WIDTH-1:0]         a,
    input  wire signed [B_WIDTH-1:0]         b,
    output wire signed [A_WIDTH+B_WIDTH-1:0] product
);

    wire signed [A_WIDTH+B_WIDTH-1:0] full_product = $signed(a) * $signed(b);
    reg  signed [A_WIDTH+B_WIDTH-1:0] product_stage;

    always @(posedge clk) begin
        product_stage <= full_product;
    end

    assign product = product_stage;

endmodule
