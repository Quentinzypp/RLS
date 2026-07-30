`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/11/22 15:08:33
// Design Name: 
// Module Name: packto12
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module packto121(
    //input
    clk,
    rst_n,
    din_nd,
	flag_nd,
	din_data,  
	//output
	dout_rdy,
	dout_data
    );

    parameter  	width		=	48;
	parameter	pack_len	=	12;

    
    input                           clk;
    input                           rst_n;
    input                           din_nd;
    input                           flag_nd;
    input           [width-1:0]     din_data;

    output  reg                     dout_rdy;
    output  reg     [width-1:0]     dout_data;

	reg                             din_nd_r;
    reg                             flag_nd_r;
	reg             [width-1:0]     din_data_r;

	reg                             flag_r1;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            flag_r1 <= 0;
        end
        else begin
            flag_r1 <= flag_nd_r;
        end
    end


    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            din_nd_r    <= 0;
            din_data_r  <= 0;
            flag_nd_r   <= 0;
        end
        else begin
            din_nd_r    <= din_nd;
            din_data_r  <= din_data;
            flag_nd_r   <= flag_nd;
        end
    end

    reg                     wr_en;
    reg     [3:0]           addra;
    reg     [width-1:0]     din_ram;
    reg     [3:0]           addrb;
    wire    [width-1:0]     dout_ram;

    reg     [3:0]           cnt_addr;

    RLS12_c_pack_ram_fb u_packto12_ram (
    .clka(clk),    // input wire clka
    .wea(wr_en),      // input wire [0 : 0] wea
    .addra(addra),  // input wire [3 : 0] addra
    .dina(din_ram),    // input wire [47 : 0] dina
    .clkb(clk),    // input wire clkb
    .addrb(addrb),  // input wire [3 : 0] addrb
    .doutb(dout_ram)  // output wire [47 : 0] doutb
    );



    reg     [1:0]           wr_ram_state = 2'b00;
    reg                     rd_from_ram_en;

    always @(posedge clk or negedge rst_n) begin
        case(wr_ram_state)
                    default: begin
                        wr_en           <= 0;
                        rd_from_ram_en  <= 0;
                        din_ram         <= 0;
                        addra           <= 0;
                        cnt_addr        <= 0;
                        if(!rst_n) begin
                            wr_ram_state <= 2'b01;
                        end
                        else begin
                            wr_ram_state <= 2'b10;
                        end
                    end
                    2'b01: begin
                          addra <= cnt_addr;
                          if(cnt_addr == pack_len-1) begin
                            cnt_addr <= 0;
                          end
                          else begin
                            cnt_addr <= cnt_addr + 1'b1;
                          end
                          if(addra == pack_len-1) begin
                            wr_ram_state    <= 2'b00;
                            wr_en           <= 1'b0;
                          end
                          else begin
                            wr_en <= 1'b1;
                          end
                          din_ram <= 'b0;
                    end
                    2'b10: begin
                          if(din_nd_r) begin
                            wr_en           <= 1'b1;
                            rd_from_ram_en  <= 1'b1;
                            din_ram         <= din_data_r;
                            addra           <= cnt_addr;
                            if(cnt_addr == pack_len-1) begin
                                cnt_addr <= 0;
                            end
                            else begin
                                cnt_addr <= cnt_addr + 1'b1;
                            end
                          end
                          else begin
                            wr_en           <= 1'b0;
                            rd_from_ram_en  <= 1'b0;
                          end

                          if(!rst_n) begin
                            wr_en           <= 0;
							din_ram	        <= 0;
							addra           <= 0;
							cnt_addr	    <= 0;
							rd_from_ram_en	<= 0;
							wr_ram_state	<= 2'b01;
                          end
                          else begin    end
                    end
        endcase
    end

    reg rd_en;
    reg rd_state;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rd_en <= 0;
        end
        else begin
            rd_en <= rd_from_ram_en&(!flag_r1);
        end
    end

    reg [5:0] cnt_out;
    reg out_rdy;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            addrb       <= 0;
            cnt_out     <= 0;
            rd_state    <= 0;
            out_rdy     <= 0;
        end
        else begin
            case(rd_state)
                    1'b0: begin
                        if(rd_en) begin
                            rd_state    <= 1'b1;
                            addrb       <= addra;
                            out_rdy     <= 1;
                            cnt_out     <= 1;
                        end
                        else begin
                            rd_state    <= 1'b0;
                        end
                    end
                    1'b1: begin
                        if(cnt_out == pack_len) begin
                            out_rdy     <= 0;
                            rd_state    <= 1'b0;
                            cnt_out     <= 0;
                            end
                        else begin
                                if(addrb == 0) begin
                                    addrb   <= pack_len - 1;
                                end
                                else begin
                                    addrb   <= addrb - 1'b1;
                                end
                                cnt_out <= cnt_out +1'b1;
                            end
                        end
            endcase
        end
    end


	reg out_rdy_r;
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            dout_rdy    <= 0;
            dout_data   <= 0;
            out_rdy_r	<= 0;
        end
        else begin
            out_rdy_r	<=out_rdy;
		    dout_rdy	<=out_rdy_r;
		    dout_data	<=dout_ram;
        end
    end

endmodule
