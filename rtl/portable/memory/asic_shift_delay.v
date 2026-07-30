`timescale 1ns / 1ps

module asic_shift_delay #(
    parameter integer WIDTH = 1,
    parameter integer DEPTH = 1,
    parameter integer CLEAR_STORAGE_ON_SCLR = 1
) (
    input  wire                 clk,
    input  wire                 sclr,
    input  wire [WIDTH-1:0]     data_in,
    output wire [WIDTH-1:0]     data_out
);

    generate
        if (DEPTH == 1) begin : gen_single_stage
            reg [WIDTH-1:0] output_register;

            always @(posedge clk) begin
                if (sclr) begin
                    output_register <= {WIDTH{1'b0}};
                end
                else begin
                    output_register <= data_in;
                end
            end

            assign data_out = output_register;
        end
        else begin : gen_multi_stage
            reg [WIDTH-1:0] shift_storage [0:DEPTH-2];
            reg [WIDTH-1:0] output_register;
            integer index;

            always @(posedge clk) begin
                if (sclr && CLEAR_STORAGE_ON_SCLR) begin
                    for (index = 0; index < DEPTH-1; index = index + 1) begin
                        shift_storage[index] <= {WIDTH{1'b0}};
                    end
                    output_register <= {WIDTH{1'b0}};
                end
                else begin
                    shift_storage[0] <= data_in;
                    for (index = 1; index < DEPTH-1; index = index + 1) begin
                        shift_storage[index] <= shift_storage[index-1];
                    end

                    if (sclr) begin
                        output_register <= {WIDTH{1'b0}};
                    end
                    else begin
                        output_register <= shift_storage[DEPTH-2];
                    end
                end
            end

            assign data_out = output_register;
        end
    endgenerate

endmodule
