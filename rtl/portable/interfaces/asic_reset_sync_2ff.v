`timescale 1ns / 1ps

module asic_reset_sync_2ff (
    input  wire clk,
    input  wire arst_n,
    output wire srst_n
);

    (* async_reg = "true" *) reg sync_meta;
    (* async_reg = "true" *) reg sync_release;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            sync_meta <= 1'b0;
            sync_release <= 1'b0;
        end
        else begin
            sync_meta <= 1'b1;
            sync_release <= sync_meta;
        end
    end

    assign srst_n = sync_release;

endmodule
