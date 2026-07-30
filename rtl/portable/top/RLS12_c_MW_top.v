`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/01/17 16:51:33
// Design Name: 
// Module Name: RLS12_c_MW_top
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

//有两路干扰端口。若只有一路干扰，则两个端口输入一样的数据即可。
`ifndef RLS12_C_MW_TOP_MODULE
`define RLS12_C_MW_TOP_MODULE RLS12_c_MW_top
`endif

module `RLS12_C_MW_TOP_MODULE(
    //input
	clk,            
	rst_n,	        	//低电平复位
	BUF_len,        	//迭代次数

	sel_en,
	sel_rx, 			//接收信号(低实高虚)
	sel_fb1,			//参考信号1		用于链路P矩阵迭代模块(低实高虚)
	sel_fb2,			//参考信号2		用于链路系数迭代模块(低实高虚)

	in_var_p,			//初始化参数的‘倒数’ (36Q29)

    //output
	RLS_out_rdy,  		//输出使能
	RLS_out,      	 	//输出结果
	
	coef_update_plus,	//系数更新脉冲
	coef_update_en,		//系数更新使能
	coef_update_data,	//系数 {36Q27,36Q27}

	update_cnt			//迭代次数
    );
	
	parameter width			=	48;     //(24Q13,24Q13)
	parameter coe_widthout	=	72;		//filter wt (36Q27,36Q27)
	parameter FIFO_depth    = 	14;     //缓存FIFO计数器位宽
	
	input 							clk;
	input 							rst_n;
    input  	[FIFO_depth-1:0] 		BUF_len;

	input							sel_en;
	input  	[width-1:0] 	    	sel_rx;
	input  	[width-1:0] 	    	sel_fb1;
	input  	[width-1:0] 	    	sel_fb2;

	input   [35:0]          		in_var_p;


	output reg [width-1:0] 			RLS_out;
	output reg						RLS_out_rdy;

	output reg 						coef_update_plus;
	output reg 						coef_update_en;
	output reg [coe_widthout-1:0] 	coef_update_data;
	
    output reg [19:0] 				update_cnt;


	reg								RLS_wt_update;
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n)	begin
			RLS_wt_update  <=1'b0;
		end
		else	begin
			RLS_wt_update	<=1'b1;
		end
	end
	

	wire [width-1:0] 	 	fb1_pack_out;
	wire					fb1_pack_out_rdy;

	//反馈信号1缓存，12个数据长度分为一组
	RLS12_c_data_pack_fb u_rls_data_pack_fb1 (
    .clk(clk),
    .rst_n(rst_n), 
    .pack_in_nd(sel_en), 
    .BUF_LEN(BUF_len), 
    .pack_in({(sel_fb1[23:0]),(sel_fb2[47:24])}), //换成高虚低实再计算
    .pack_out_rdy(fb1_pack_out_rdy), 
    .pack_out(fb1_pack_out)
);


	wire [width-1:0] 	 	fb2_pack_out;
	wire					fb2_pack_out_rdy;

	//反馈信号2缓存，12个数据长度分为一组
	RLS12_c_data_pack_fb2 u_rls_data_pack_fb2 (
    .clk(clk),
    .rst_n(rst_n), 
    .pack_in_nd(sel_en), 
    .BUF_LEN(BUF_len), 
    .pack_in({(sel_fb2[23:0]),(sel_fb2[47:24])}), //换成高虚低实再计算
    .pack_out_rdy(fb2_pack_out_rdy), 
    .pack_out(fb2_pack_out)
);


	wire [width-1:0] 	 	rx_pack_out ;
	wire					rx_pack_out_rdy;

	//接收信号缓存，12个数据长度分为一组
	RLS12_c_data_pack_rx u_rls_data_pack_rx (
	.clk(clk),
	.rst_n(rst_n), 
	.pack_in_nd(sel_en), 
	.BUF_LEN(BUF_len), 
	.pack_in({(sel_rx[23:0]),(sel_rx[47:24])}), //换成高虚低实再计算
	.pack_out_rdy(rx_pack_out_rdy), 
	.pack_out(rx_pack_out)
);



	wire                        wt_pulse;
	wire                        wt_update_en;
	wire    [coe_widthout-1:0]  wt_update;
	wire	[19:0]				cnt;


	//计算抽头系数w(n)
	RLS12_c_matrixP_update u_RLS_c_matrixP_update (
    .clk(clk), 
    .Rst_n(rst_n), 
    .RLS_wt_update(RLS_wt_update), 
    .pack_fb1_nd(fb1_pack_out_rdy), 
    .pack_fb1(fb1_pack_out),
	.pack_fb2_nd(fb2_pack_out_rdy), 
    .pack_fb2(fb2_pack_out),
	.rx_d_nd(rx_pack_out_rdy), 
    .rx_d(rx_pack_out), 
	.inv_var_p(in_var_p),
    .wt_pulse(wt_pulse), 
    .wt_update_en(wt_update_en), 
    .wt_update_I(wt_update),//高实低虚
	.cnt(cnt)
);



	wire                     rls_out_rdy;
	wire    [width-1:0]      rls_out;

	//滤波器
	RLS12_c_rls_fir3_out_new u_RLS12_c_rls_fir3_out_new(
    .clk(clk),
    .rst_n(rst_n),
    .i_rx_en(sel_en),
    .i_rx_data(sel_rx),
    .i_fb_en(sel_en),
    .i_fb_data(sel_fb2),   
    .i_coe_pulse(wt_pulse),    
    .i_coe_en(wt_update_en),
    .i_coe_data({wt_update[35:0],wt_update[71:36]}),//换成低实高虚输入到该模块
    .o_rls_en(rls_out_rdy),
    .o_rls_data(rls_out)
);



	always @(posedge clk or negedge rst_n)
	  if(!rst_n)	begin
			RLS_out_rdy		<=1'b0;
			RLS_out			<=0;
		end
		else	begin
			RLS_out				<=rls_out;//高实低虚
			if(RLS_out_rdy)	begin
				RLS_out_rdy		<=RLS_out_rdy;
			end
			else	begin
				RLS_out_rdy		<=rls_out_rdy;
			end
		end



	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			coef_update_plus	<= 'd0;
			coef_update_en		<= 'd0;
			coef_update_data	<= 72'd0;
		end
		else begin
			coef_update_plus	<= wt_pulse;
			coef_update_en		<= wt_update_en;
			coef_update_data	<= wt_update;//高实低虚
		end
	end

		always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			update_cnt	<= 20'd0;
		end
		else begin
			update_cnt	<= cnt;
		end
	end


endmodule

`undef RLS12_C_MW_TOP_MODULE
