`timescale 1ns / 1ps

module asic_sync_fifo #(
    parameter integer WIDTH = 48,
    parameter integer DEPTH = 32
) (
    input  wire                 clk,
    input  wire                 srst,
    input  wire [WIDTH-1:0]     din,
    input  wire                 wr_en,
    input  wire                 rd_en,
    output wire [WIDTH-1:0]     dout,
    output wire                 full,
    output wire                 empty,
    output reg                  valid,
    output reg                  overflow,
    output reg                  underflow,
    output reg                  wr_rst_busy,
    output reg                  rd_rst_busy
);

    function integer clog2;
        input integer value;
        integer remaining;
        begin
            remaining = value - 1;
            clog2 = 0;
            while (remaining > 0) begin
                remaining = remaining >> 1;
                clog2 = clog2 + 1;
            end
            if (clog2 == 0) begin
                clog2 = 1;
            end
        end
    endfunction

    localparam integer PTR_WIDTH = clog2(DEPTH);

    reg [PTR_WIDTH-1:0] write_pointer;
    reg [PTR_WIDTH-1:0] read_pointer;
    reg [PTR_WIDTH:0] occupancy;
    reg output_initialized;

    wire write_accept = wr_en && !full;
    wire read_accept = rd_en && !empty;
    wire [WIDTH-1:0] storage_read_data;

    assign full = (occupancy == DEPTH);
    assign empty = (occupancy == 0);
    assign dout = output_initialized ? storage_read_data : {WIDTH{1'b0}};

    asic_sdp_sram #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(PTR_WIDTH),
        .HAS_READ_ENABLE(1),
        .READ_DURING_WRITE_MODE(0)
    ) u_storage (
        .clk(clk),
        .wr_en(write_accept),
        .rd_en(read_accept),
        .wr_addr(write_pointer),
        .wr_data(din),
        .rd_addr(read_pointer),
        .rd_data(storage_read_data)
    );

    always @(posedge clk) begin
        if (srst) begin
            write_pointer <= {PTR_WIDTH{1'b0}};
            read_pointer <= {PTR_WIDTH{1'b0}};
            occupancy <= {(PTR_WIDTH+1){1'b0}};
            output_initialized <= 1'b0;
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

            if (read_accept) begin
                output_initialized <= 1'b1;
            end

            if (write_accept) begin
                if (write_pointer == DEPTH-1) begin
                    write_pointer <= {PTR_WIDTH{1'b0}};
                end
                else begin
                    write_pointer <= write_pointer + 1'b1;
                end
            end

            if (read_accept) begin
                if (read_pointer == DEPTH-1) begin
                    read_pointer <= {PTR_WIDTH{1'b0}};
                end
                else begin
                    read_pointer <= read_pointer + 1'b1;
                end
            end

            case ({write_accept, read_accept})
                2'b10: occupancy <= occupancy + 1'b1;
                2'b01: occupancy <= occupancy - 1'b1;
                default: occupancy <= occupancy;
            endcase
        end
    end

endmodule
