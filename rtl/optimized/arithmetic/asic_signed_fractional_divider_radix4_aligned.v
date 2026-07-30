`timescale 1ns / 1ps

module asic_signed_fractional_divider_radix4_aligned #(
    parameter integer ALIGN_STAGES = 4
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                start,
    input  wire signed [39:0]  dividend,
    input  wire signed [39:0]  divisor,
    output wire                busy,
    output wire                done,
    output wire                valid,
    output wire signed [71:0]  quotient,
    output wire                divide_by_zero
);

    wire native_done;
    wire native_valid;
    wire signed [71:0] native_quotient;
    wire native_divide_by_zero;
    reg [ALIGN_STAGES-1:0] valid_pipeline;
    reg [ALIGN_STAGES-1:0] zero_pipeline;
    reg [71:0] quotient_pipeline [0:ALIGN_STAGES-1];
    integer stage;

    asic_signed_fractional_divider_radix4_exact u_radix4 (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .dividend(dividend),
        .divisor(divisor),
        .busy(busy),
        .done(native_done),
        .valid(native_valid),
        .quotient(native_quotient),
        .divide_by_zero(native_divide_by_zero)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipeline <= {ALIGN_STAGES{1'b0}};
            zero_pipeline <= {ALIGN_STAGES{1'b0}};
            for (stage = 0; stage < ALIGN_STAGES; stage = stage + 1) begin
                quotient_pipeline[stage] <= 72'd0;
            end
        end
        else begin
            valid_pipeline[0] <= native_valid;
            zero_pipeline[0] <= native_divide_by_zero;
            quotient_pipeline[0] <= native_quotient;
            for (stage = 1; stage < ALIGN_STAGES; stage = stage + 1) begin
                valid_pipeline[stage] <= valid_pipeline[stage-1];
                zero_pipeline[stage] <= zero_pipeline[stage-1];
                quotient_pipeline[stage] <= quotient_pipeline[stage-1];
            end
        end
    end

    assign done = valid_pipeline[ALIGN_STAGES-1];
    assign valid = valid_pipeline[ALIGN_STAGES-1];
    assign quotient = quotient_pipeline[ALIGN_STAGES-1];
    assign divide_by_zero = zero_pipeline[ALIGN_STAGES-1];

endmodule
