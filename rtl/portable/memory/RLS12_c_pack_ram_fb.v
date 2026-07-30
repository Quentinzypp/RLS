`timescale 1ns / 1ps

module RLS12_c_pack_ram_fb (
    input  wire         clka,
    input  wire [0:0]   wea,
    input  wire [3:0]   addra,
    input  wire [47:0]  dina,
    input  wire         clkb,
    input  wire [3:0]   addrb,
    output wire [47:0]  doutb
);

    // Active callers tie clka and clkb together. The portable contract is
    // deliberately single-clock so same-address behavior is deterministic.
    wire unused_clkb = clkb;
    wire [47:0] storage_read_data;

`ifdef PHASE2_VENDOR_MIXED_SIM
    // The frozen Block Memory Generator exposes clock-to-Q after 100 ps.
    // Keep this delay out of the default synthesizable portable contract.
    assign #0.1 doutb = storage_read_data;
`else
    assign doutb = storage_read_data;
`endif

    asic_sdp_sram #(
        .WIDTH(48),
        .DEPTH(16),
        .ADDR_WIDTH(4),
        .READ_DURING_WRITE_MODE(1)
    ) u_pack_storage (
        .clk     (clka),
        .wr_en   (wea[0]),
        .rd_en   (1'b1),
        .wr_addr (addra),
        .wr_data (dina),
        .rd_addr (addrb),
        .rd_data (storage_read_data)
    );

endmodule
