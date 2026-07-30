`timescale 1ns / 1ps

module RLS12_Pram (
    input  wire         clka,
    input  wire [0:0]   wea,
    input  wire [6:0]   addra,
    input  wire [71:0]  dina,
    input  wire         clkb,
    input  wire [6:0]   addrb,
    output wire [71:0]  doutb
);

    // All active banks tie clka and clkb to the algorithm clock.
    wire unused_clkb = clkb;
    wire [71:0] storage_read_data;
    reg  [71:0] output_stage;

    asic_sdp_sram #(
        .WIDTH(72),
        .DEPTH(128),
        .ADDR_WIDTH(7),
        .READ_DURING_WRITE_MODE(0)
    ) u_p_storage (
        .clk     (clka),
        .wr_en   (wea[0]),
        .rd_en   (1'b1),
        .wr_addr (addra),
        .wr_data (dina),
        .rd_addr (addrb),
        .rd_data (storage_read_data)
    );

    // The frozen core-output register makes address-to-Q latency two clocks.
    always @(posedge clka) begin
        output_stage <= storage_read_data;
    end

`ifdef PHASE2_VENDOR_MIXED_SIM
    assign #0.1 doutb = output_stage;
`else
    assign doutb = output_stage;
`endif

endmodule
