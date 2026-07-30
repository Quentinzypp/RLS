`timescale 1ns / 1ps

module mult_div (
    input  wire        CLK,
    input  wire [24:0] A,
    input  wire [24:0] B,
    output wire [49:0] P
);

    wire signed [24:0] signed_a = $signed(A);
    wire signed [24:0] signed_b = $signed(B);
    wire signed [49:0] portable_product;

    asic_signed_multiplier #(
        .A_WIDTH(25),
        .B_WIDTH(25)
    ) u_signed_multiplier (
        .clk     (CLK),
        .a       (signed_a),
        .b       (signed_b),
        .product (portable_product)
    );

`ifdef PHASE2_VENDOR_MIXED_SIM
    assign #0.1 P = portable_product;
`else
    assign P = portable_product;
`endif

endmodule
