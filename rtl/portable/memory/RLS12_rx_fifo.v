`timescale 1ns / 1ps

module RLS12_rx_fifo (
    input  wire        clk,
    input  wire        srst,
    input  wire [47:0] din,
    input  wire        wr_en,
    input  wire        rd_en,
    output reg  [47:0] dout,
    output wire        full,
    output wire        empty,
    output reg         valid,
    output reg         wr_rst_busy,
    output reg         rd_rst_busy
);

    reg [47:0] storage [0:31];
    reg [4:0] write_pointer;
    reg [4:0] read_pointer;
    reg [5:0] occupancy;
    reg overflow;
    reg underflow;

    wire write_accept = wr_en && !full;
    wire read_accept = rd_en && !empty;

    assign full = (occupancy == 6'd32);
    assign empty = (occupancy == 6'd0);

    always @(posedge clk) begin
        if (srst) begin
            write_pointer <= 5'd0;
            read_pointer <= 5'd0;
            occupancy <= 6'd0;
            dout <= 48'd0;
            valid <= 1'b0;
            overflow <= 1'b0;
            underflow <= 1'b0;
            wr_rst_busy <= 1'b1;
            rd_rst_busy <= 1'b1;
        end
        else begin
            valid <= read_accept;
            overflow <= wr_en && full;
            underflow <= rd_en && empty;
            wr_rst_busy <= 1'b0;
            rd_rst_busy <= 1'b0;

            if (write_accept) begin
                storage[write_pointer] <= din;
                write_pointer <= write_pointer + 1'b1;
            end
            if (read_accept) begin
                dout <= storage[read_pointer];
                read_pointer <= read_pointer + 1'b1;
            end

            case ({write_accept, read_accept})
                2'b10: occupancy <= occupancy + 1'b1;
                2'b01: occupancy <= occupancy - 1'b1;
                default: occupancy <= occupancy;
            endcase
        end
    end

endmodule
