`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/01/03 15:24:08
// Design Name: 
// Module Name: RLS12_c_matrixP_update
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

//该模块的的输入数据默认高位是虚部，低位是实部，因此接入该模块时注意是否需要调整！
module RLS12_c_matrixP_update(
    //input
    clk,
    Rst_n,
    RLS_wt_update,

    pack_fb1_nd,    //反馈支路信号1使能
    pack_fb1,       //反馈支路信号u(n)1  {24Q13,24Q13}

    pack_fb2_nd,    //反馈支路信号2使能
    pack_fb2,       //反馈支路信号u(n)2   {24Q13,24Q13}

    rx_d_nd,        //接收支路信号使能
    rx_d,           //接收支路信号d(n)   {24Q13,24Q13}

    inv_var_p,      //初始化参数的倒数 36Q29

    //output
    wt_pulse,       //滤波器抽头系数更新脉冲
    wt_update_en,   //w(n)使能
    wt_update_I,    //w(n) {36Q27,36Q27}

    cnt             //迭代次数

    );

    parameter width         =	48;		//输入位宽
    parameter mul_width		=	128;    //复数乘法器输出位宽({36Q,36Q} * {24Q,24Q})-->(60Q,60Q)

    parameter mulR2_width	=	96;     //R2 (24Q13,24Q13)*(18Q16,18Q16)-->(42Q29,42Q29)

	parameter pack_len		=	12;		//滤波器阶数与分组长度
    parameter p_width       =	72;

	parameter adder_width	=	80;     //内部加法器位宽
    parameter ram_width		=	72;
 
	parameter Over_clk		=	150;	//完成一次矩阵更新所需clk个数
    parameter coe_width		=	72;

	parameter coe_widthout	=	72;		//输出滤波器系数定标 (25Q20,25Q20)
	parameter div_width		=	68;		//除法器定标(34Q25,34Q25)

    input                           clk;
    input                           Rst_n;
    input                           RLS_wt_update;

    input                           pack_fb1_nd;
    input   [width-1:0]             pack_fb1;   //{24Q13,24Q13}高位虚部，低位实部

    input                           pack_fb2_nd;
    input   [width-1:0]             pack_fb2;   //{24Q13,24Q13}高位虚部，低位实部

    input                           rx_d_nd;
    input   [width-1:0]             rx_d;      //{24Q13,24Q13}高位虚部，低位实部

    input   [35:0]                  inv_var_p;
    
    output  reg                     wt_pulse;
    output  reg                     wt_update_en;
    output  reg [coe_widthout-1:0]  wt_update_I;


    reg                         rst_n;

    always @(posedge clk or negedge Rst_n) begin
        if(!Rst_n) begin
            rst_n <= 1'b0;
        end
        else begin
            rst_n <= Rst_n;
        end
    end

    reg                         nd_r;
    reg     [width-1:0]         din_I1_r,din_I1_r1,din_I1_r2;

    //输入缓存，反馈信号1打两拍
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            nd_r    <= 0;
            din_I1_r <= 0;
        end
        else begin
            nd_r    <= pack_fb1_nd;
            din_I1_r <= pack_fb1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            din_I1_r1 <= 0;
            din_I1_r2 <= 0;
        end
        else begin
            din_I1_r1 <= din_I1_r;
            din_I1_r2 <= din_I1_r1;
        end
    end

    //输入反馈信号控制
    reg     [width-1:0]         din1_r1,din1_r2,din1_r3,din1_r4;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            din1_r1 <= 0;    din1_r2 <= 0;
            din1_r3 <= 0;    din1_r4 <= 0;
        end
        else begin
            if(nd_r) begin
                din1_r1 <= din_I1_r;
            end
            else begin
                din1_r1 <= 0;
            end

            din1_r2 <= din1_r1;
            din1_r3 <= din1_r2;
            din1_r4 <= din1_r3;//给mult01_br
        end
    end


    reg     [width-1:0]         din_I2_r,din_I2_r1;

    //输入缓存，反馈信号2打一拍
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            din_I2_r <= 0;
        end
        else begin
            din_I2_r <= pack_fb2;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            din_I2_r1 <= 0;
        end
        else begin
            din_I2_r1 <= din_I2_r;
        end
    end


    //输入反馈使能缓存5级
    reg nd_r1,nd_r2,nd_r3,nd_r4,nd_r5,nd_r6,nd_r7;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            nd_r1 <= 0;
            nd_r2 <= 0;
            nd_r3 <= 0;
            nd_r4 <= 0;
            nd_r5 <= 0;
            nd_r6 <= 0;
        end
        else begin
            nd_r1 <= nd_r;
            nd_r2 <= nd_r1;
            nd_r3 <= nd_r2;
            nd_r4 <= nd_r3;
            nd_r5 <= nd_r4;
            nd_r6 <= nd_r5;
            nd_r7 <= nd_r6;
        end
    end


    //开始计算脉冲使能
    wire cal_en = nd_r3&(~nd_r4);//触发脉冲，触发时钟计数信号计数

    //P暂存P'[k]暂存  ram_width=72(36Q29,36Q29)  按列缓存,根据地址按列读写
    reg   [ram_width-1:0] din_ram00,din_ram01,din_ram02,din_ram03,din_ram04,din_ram05;
    reg   [ram_width-1:0] din_ram06,din_ram07,din_ram08,din_ram09,din_ram10,din_ram11;

    wire  [ram_width-1:0] dout_ram00,dout_ram01,dout_ram02,dout_ram03,dout_ram04,dout_ram05;  
	wire  [ram_width-1:0] dout_ram06,dout_ram07,dout_ram08,dout_ram09,dout_ram10,dout_ram11;
	
	reg   [ram_width-1:0] dout_ram00_r,dout_ram01_r,dout_ram02_r,dout_ram03_r,dout_ram04_r,dout_ram05_r;    
	reg   [ram_width-1:0] dout_ram06_r,dout_ram07_r,dout_ram08_r,dout_ram09_r,dout_ram10_r,dout_ram11_r;



    //ram缓存
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            dout_ram00_r<=0; dout_ram01_r<=0; dout_ram02_r<=0; dout_ram03_r<=0; dout_ram04_r<=0; dout_ram05_r<=0;
            dout_ram06_r<=0; dout_ram07_r<=0; dout_ram08_r<=0; dout_ram09_r<=0; dout_ram10_r<=0; dout_ram11_r<=0;
        end
        else begin
            dout_ram00_r<=dout_ram00; dout_ram01_r<=dout_ram01; dout_ram02_r<=dout_ram02; dout_ram03_r<=dout_ram03;
            dout_ram04_r<=dout_ram04; dout_ram05_r<=dout_ram05; dout_ram06_r<=dout_ram06; dout_ram07_r<=dout_ram07;
            dout_ram08_r<=dout_ram08; dout_ram09_r<=dout_ram09; dout_ram10_r<=dout_ram10; dout_ram11_r<=dout_ram11;
        end
    end

	//减法器输出寄存器组 (36Q29,36Q29)
    reg signed [p_width-1:0] dout_subI00,dout_subI01,dout_subI02,dout_subI03,dout_subI04,dout_subI05;
	reg signed [p_width-1:0] dout_subI06,dout_subI07,dout_subI08,dout_subI09,dout_subI10,dout_subI11;


    //乘法器输出 mul_width=128
	wire signed [mul_width-1:0] mult00_pr,mult01_pr,mult02_pr,mult03_pr,mult04_pr,mult05_pr;
	wire signed [mul_width-1:0] mult06_pr,mult07_pr,mult08_pr,mult09_pr,mult10_pr,mult11_pr;

	//P矩阵初始化、更新与P'[k]暂存
    reg [1:0] wr_ram_state;
    reg P_up_en;
    reg P_en;
    reg [5:0] cnt_addr,cnt_addr1;
    reg wr_en;
    reg [6:0] addra,addrb;
    reg ram_en;  //P[k]读触发脉冲

          
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_ram_state <= 2'b01;
            cnt_addr     <= 6'd0;
            wr_en        <= 1'b0;
            addra        <= 7'd0;
        end
        else begin
            case(wr_ram_state)
                    default:    begin
                        cnt_addr <= 6'd0;
                        if(P_up_en) begin    //P_up_en=1时，P矩阵更新，RAM地址最高位取0
                            wr_ram_state    <= 2'b10;
                        end
                        else begin  end
                        if(P_en) begin       //P_en=1时，P'矩阵更新，RAM地址最高位取1
                            wr_ram_state    <= 2'b11;
                        end
                        else begin  end
                    end
                    2'b01:  begin  //P矩阵初始化
                        if(cnt_addr == pack_len) begin
                            cnt_addr        <= 6'd0;
                            wr_ram_state    <= 2'b00;
                        end
                        else begin
                            cnt_addr        <= cnt_addr + 1'b1;
                        end

                        if(cnt_addr < pack_len) begin
                            wr_en           <= 1'b1;
                            addra           <= {1'b0,cnt_addr};
                        end
                        else begin
                            wr_en           <= 1'b0;
                        end

                        if(cnt_addr == 6'd0) begin
                            din_ram00 <= {36'sd0,inv_var_p};  //{0,inv_var_p即inv_var_p+0i}  36Q29 有符号十进制
                        end
                        else begin
                            din_ram00 <= 0;
                        end
                        if(cnt_addr == 6'd1) begin
                            din_ram01 <= {36'sd0,inv_var_p};
                        end
                        else begin
                            din_ram01 <= 0;
                        end
                        if(cnt_addr == 6'd2) begin
                            din_ram02 <= {36'sd0,inv_var_p};
                        end
                        else begin
                            din_ram02<= 0;
                        end
                        if(cnt_addr == 6'd3) begin
                            din_ram03 <= {36'sd0,inv_var_p};
                        end
                        else begin
                            din_ram03 <= 0;
                        end
                        if(cnt_addr == 6'd4) begin
                            din_ram04 <= {36'sd0,inv_var_p};
                        end
                        else begin
                            din_ram04 <= 0;
                        end
                        if(cnt_addr == 6'd5) begin
                            din_ram05 <= {36'sd0,inv_var_p};
                        end
                        else begin
                            din_ram05 <= 0;
                        end
                        if(cnt_addr == 6'd6) begin
                            din_ram06 <= {36'sd0,inv_var_p};
                        end
                        else begin
                            din_ram06 <= 0;
                        end
                        if(cnt_addr == 6'd7) begin
                            din_ram07 <= {36'sd0,inv_var_p};
                        end
                        else begin
                            din_ram07 <= 0;
                        end
                        if(cnt_addr == 6'd8) begin
                            din_ram08 <= {36'sd0,inv_var_p};
                        end
                        else begin
                            din_ram08 <= 0;
                        end
                        if(cnt_addr == 6'd9) begin
                            din_ram09 <= {36'sd0,inv_var_p};
                        end
                        else begin
                            din_ram09 <= 0;
                        end
                        if(cnt_addr == 6'd10) begin
                            din_ram10 <= {36'sd0,inv_var_p};
                        end
                        else begin
                            din_ram10 <= 0;
                        end
                        if(cnt_addr == 6'd11) begin
                            din_ram11 <= {36'sd0,inv_var_p};
                        end
                        else begin
                            din_ram11 <= 0;
                        end
                    end
                    2'b10:  begin       //P矩阵更新 P[k]=P'[K]-A'[K]B[K]
                        if(cnt_addr == pack_len) begin
                            wr_ram_state    <= 2'b00;
                            cnt_addr        <= 6'd0;
                        end
                        else begin
                            cnt_addr        <= cnt_addr + 1'b1;
                        end
                        if(cnt_addr < pack_len) begin
                            wr_en           <= 1'b1;
                            addra           <= {1'b0,cnt_addr};
                        end
                        else begin
                            wr_en           <= 1'b0;
                        end
                            din_ram00<=dout_subI00;din_ram01<=dout_subI01;din_ram02<=dout_subI02;din_ram03<=dout_subI03;
				            din_ram04<=dout_subI04;din_ram05<=dout_subI05;din_ram06<=dout_subI06;din_ram07<=dout_subI07;
				            din_ram08<=dout_subI08;din_ram09<=dout_subI09;din_ram10<=dout_subI10;din_ram11<=dout_subI11;
                    end
                    2'b11: begin        //P'[k]=P[k-1]/y=(1/y)*P[k-1] {24Q22*36Q29} 矩阵暂存 61Q51-->36Q29  [57:22]
                        if(cnt_addr == pack_len) begin
                            wr_ram_state    <= 2'b00;
                            cnt_addr        <= 6'd0;
                        end
                        else begin
                            cnt_addr        <= cnt_addr + 1'b1;
                        end
                        if(cnt_addr < pack_len) begin
                            wr_en           <= 1'b1;
                            addra           <= {1'b1,cnt_addr};//最高位为1
                        end
                        else begin
                            wr_en           <= 1'b0;
                        end
                            din_ram00<={mult00_pr[121:86],mult00_pr[57:22]};din_ram01<={mult01_pr[121:86],mult01_pr[57:22]};din_ram02<={mult02_pr[121:86],mult02_pr[57:22]};
                            din_ram03<={mult03_pr[121:86],mult03_pr[57:22]};din_ram04<={mult04_pr[121:86],mult04_pr[57:22]};din_ram05<={mult05_pr[121:86],mult05_pr[57:22]};
                            din_ram06<={mult06_pr[121:86],mult06_pr[57:22]};din_ram07<={mult07_pr[121:86],mult07_pr[57:22]};din_ram08<={mult08_pr[121:86],mult08_pr[57:22]};
				            din_ram09<={mult09_pr[121:86],mult09_pr[57:22]};din_ram10<={mult10_pr[121:86],mult10_pr[57:22]};din_ram11<={mult11_pr[121:86],mult11_pr[57:22]};
                    end
            endcase
        end
    end



    reg rd_P; //P'[k]存储器组读使能

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cnt_addr1   <= 0;
            addrb       <= 0;
        end
        else begin      
            if(nd_r || rd_P || ram_en) begin
                if(cnt_addr1 == pack_len-1) begin
                    cnt_addr1   <= 0;
                end
                else begin
                    cnt_addr1   <= cnt_addr1 + 1'b1;
                end
                if(rd_P) begin   //rd_P=1时读取P'矩阵
                    addrb       <= {1'b1,cnt_addr1};  //读取P'矩阵
                end
                else begin
                    addrb       <= {1'b0,cnt_addr1};  //读取P矩阵
                end
            end
            else begin
                cnt_addr1       <= 0;
            end
        end
    end




    //P矩阵存储器组
	RLS12_Pram u_rls_pram00 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram00),.clkb(clk),.addrb(addrb),.doutb(dout_ram00));
	RLS12_Pram u_rls_pram01 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram01),.clkb(clk),.addrb(addrb),.doutb(dout_ram01));
	RLS12_Pram u_rls_pram02 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram02),.clkb(clk),.addrb(addrb),.doutb(dout_ram02));
	RLS12_Pram u_rls_pram03 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram03),.clkb(clk),.addrb(addrb),.doutb(dout_ram03));
	RLS12_Pram u_rls_pram04 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram04),.clkb(clk),.addrb(addrb),.doutb(dout_ram04));
	RLS12_Pram u_rls_pram05 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram05),.clkb(clk),.addrb(addrb),.doutb(dout_ram05));
	RLS12_Pram u_rls_pram06 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram06),.clkb(clk),.addrb(addrb),.doutb(dout_ram06));
	RLS12_Pram u_rls_pram07 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram07),.clkb(clk),.addrb(addrb),.doutb(dout_ram07));
	RLS12_Pram u_rls_pram08 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram08),.clkb(clk),.addrb(addrb),.doutb(dout_ram08));
	RLS12_Pram u_rls_pram09 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram09),.clkb(clk),.addrb(addrb),.doutb(dout_ram09));
	RLS12_Pram u_rls_pram10 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram10),.clkb(clk),.addrb(addrb),.doutb(dout_ram10));
	RLS12_Pram u_rls_pram11 (.clka(clk),.wea(wr_en),.addra(addra),.dina(din_ram11),.clkb(clk),.addrb(addrb),.doutb(dout_ram11));

    //矩阵更新时序控制
    reg [7:0] cnt_clk;
    reg cnt_state;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cnt_clk     <= 0;
            cnt_state   <= 1'b0;
        end
        else begin
            case(cnt_state)
                    1'b0:   begin
                        if(cal_en) begin       //cal_en使能每段反馈输入使能上升沿的延时
                            cnt_clk     <= 1;  //cnt_clk是对cal_en使能有效之后进行计数，作用区分后面的状态
                            cnt_state   <= 1'b1;
                        end
                        else begin  end
                    end
                    1'b1:   begin
                        if(cnt_clk == Over_clk) begin
                            cnt_clk     <= 0;
                            cnt_state   <= 1'b0;
                        end
                        else begin
                            cnt_clk     <= cnt_clk + 1'b1;
                        end
                    end
            endcase
        end
    end


    //P矩阵更新使能
    reg A_en,C_en,D_en,B_en,A1_en,rls_out_en,Y_en,GN_en;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            A_en			<=0;  //A[k]计算使能
		    C_en			<=0;  //C计算使能
            D_en			<=0;  //D计算使能
            B_en			<=0;  //B[k]计算使能
            A1_en			<=0;  //A'[k]计算使能
            ram_en          <=0;  //P[k]读触发脉冲
            P_up_en         <=0;  //P[k]写触发脉冲
            P_en			<=0;  //P'[k]写触发脉冲
            rd_P			<=0;  //P'[k]读触发脉冲
            rls_out_en      <=0;  //y[k]计算使能
            Y_en			<=0;  //y[k]输出使能
            GN_en			<=0;  //A'[k]e[k]计算使能

        end
        else begin
            if(cnt_clk>=12 && cnt_clk<24) begin
                A_en		    <=1;
            end
            else begin
                A_en		    <=0;
            end

            if(cnt_clk == 35) begin
                rls_out_en		<=1;
            end
            else begin
                rls_out_en		<=0;
            end

            if(cnt_clk == 36) begin
                C_en            <= 1;
            end
            else begin
                C_en            <= 0;
            end

            if(cnt_clk == 41) begin
                Y_en            <= 1;
            end
            else begin
                Y_en            <= 0;
            end

            if(cnt_clk >= 42 && cnt_clk <89) begin
                D_en            <= 1;
            end
            else begin
                D_en            <= 0;
            end

            if(cnt_clk>=37 && cnt_clk<49) begin
                B_en            <= 1;
            end
            else begin
                B_en            <= 0;
            end

            if(cnt_clk == 103) begin
                A1_en           <= 1;
            end
            else begin
                A1_en           <= 0;
            end

            if(cnt_clk>=103 && cnt_clk<115) begin
                P_en            <= 1;
            end
            else begin
                P_en            <= 0;
            end

            if(cnt_clk>=88 && cnt_clk<100) begin
                ram_en          <= 1;
            end
            else begin
                ram_en          <= 0;
            end

            if(cnt_clk>=112 && cnt_clk<124) begin
                rd_P            <= 1;
            end
            else begin
                rd_P            <= 0;
            end

            if(cnt_clk>=117 && cnt_clk<129) begin
                P_up_en         <= 1;
            end
            else begin
                P_up_en         <= 0;
            end
            
            if(cnt_clk == 128) begin
                GN_en           <= 1;
            end
            else begin
                GN_en           <= 0;
            end
        end
    end



    //乘法器输入寄存器
    reg signed [p_width-1:0]    mult00_ar,mult01_ar,mult02_ar,mult03_ar,mult04_ar,mult05_ar;
	reg signed [p_width-1:0]    mult06_ar,mult07_ar,mult08_ar,mult09_ar,mult10_ar,mult11_ar;
	
	reg signed [width-1:0]      mult00_br,mult01_br,mult02_br,mult03_br,mult04_br,mult05_br;
	reg signed [width-1:0]      mult06_br,mult07_br,mult08_br,mult09_br,mult10_br,mult11_br;


    //乘法器:(36Qx)*(24Qy)=61Q(x+y)          输出实际124位,高位补4位
    RLS12_mult RLS12_mult_00 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult00_ar[71:36],4'b0,mult00_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult00_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult00_pr));
    RLS12_mult RLS12_mult_01 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult01_ar[71:36],4'b0,mult01_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult01_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult01_pr));
    RLS12_mult RLS12_mult_02 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult02_ar[71:36],4'b0,mult02_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult02_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult02_pr));
    RLS12_mult RLS12_mult_03 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult03_ar[71:36],4'b0,mult03_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult03_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult03_pr));
    RLS12_mult RLS12_mult_04 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult04_ar[71:36],4'b0,mult04_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult04_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult04_pr));
    RLS12_mult RLS12_mult_05 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult05_ar[71:36],4'b0,mult05_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult05_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult05_pr));
    RLS12_mult RLS12_mult_06 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult06_ar[71:36],4'b0,mult06_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult06_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult06_pr));
    RLS12_mult RLS12_mult_07 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult07_ar[71:36],4'b0,mult07_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult07_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult07_pr));
    RLS12_mult RLS12_mult_08 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult08_ar[71:36],4'b0,mult08_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult08_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult08_pr));
    RLS12_mult RLS12_mult_09 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult09_ar[71:36],4'b0,mult09_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult09_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult09_pr));
    RLS12_mult RLS12_mult_10 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult10_ar[71:36],4'b0,mult10_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult10_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult10_pr));
    RLS12_mult RLS12_mult_11 (.aclk(clk), .s_axis_a_tvalid(1'b1), .s_axis_a_tdata({4'b0,mult11_ar[71:36],4'b0,mult11_ar[35:0]}), .s_axis_b_tvalid(1'b1), .s_axis_b_tdata(mult11_br), .m_axis_dout_tvalid(), .m_axis_dout_tdata(mult11_pr));



    //输入反馈2信号 (虚部24Q13,实部24Q13) R0[k]
    reg signed [width-1:0] R0_2I00,	R0_2I01, R0_2I02,	R0_2I03,	R0_2I04,	R0_2I05;
	reg signed [width-1:0] R0_2I06, R0_2I07, R0_2I08,	R0_2I09,	R0_2I10,	R0_2I11;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            R0_2I00 <= 0;    R0_2I01 <= 0;    R0_2I02 <= 0;    R0_2I03 <= 0;    R0_2I04 <= 0;    R0_2I05 <= 0;
            R0_2I06 <= 0;    R0_2I07 <= 0;    R0_2I08 <= 0;    R0_2I09 <= 0;    R0_2I10 <= 0;    R0_2I11 <= 0;
        end
        else begin
            if(nd_r1)begin
                R0_2I00 <= din_I2_r1;     R0_2I01 <= R0_2I00;    R0_2I02 <= R0_2I01;    R0_2I03 <= R0_2I02;    R0_2I04 <= R0_2I03;    R0_2I05 <= R0_2I04;
                R0_2I06 <= R0_2I05;       R0_2I07 <= R0_2I06;    R0_2I08 <= R0_2I07;    R0_2I09 <= R0_2I08;    R0_2I10 <= R0_2I09;    R0_2I11 <= R0_2I10;
            end
            else begin  end
        end
    end


   
    //输入反馈信号 (虚部24Q13,实部24Q13) R0[k]
    reg signed [width-1:0] R0_I00,	R0_I01,	R0_I02,	R0_I03,	R0_I04,	R0_I05;
	reg signed [width-1:0] R0_I06,  R0_I07, R0_I08,	R0_I09,	R0_I10,	R0_I11;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            R0_I00 <= 0;    R0_I01 <= 0;    R0_I02 <= 0;    R0_I03 <= 0;    R0_I04 <= 0;    R0_I05 <= 0;
            R0_I06 <= 0;    R0_I07 <= 0;    R0_I08 <= 0;    R0_I09 <= 0;    R0_I10 <= 0;    R0_I11 <= 0;
        end
        else begin
            if(nd_r1)begin
                R0_I00 <= din_I1_r1;    R0_I01 <= R0_I00;    R0_I02 <= R0_I01;    R0_I03 <= R0_I02;    R0_I04 <= R0_I03;    R0_I05 <= R0_I04;
                R0_I06 <= R0_I05;       R0_I07 <= R0_I06;    R0_I08 <= R0_I07;    R0_I09 <= R0_I08;    R0_I10 <= R0_I09;    R0_I11 <= R0_I10;
            end
            else begin  end
        end
    end


    //输入反馈信号共轭转置 (虚部24Q13,实部24Q13) R1[k]
    reg signed [width-1:0] R1_I00,	R1_I01,	R1_I02,	R1_I03,	R1_I04,	R1_I05;
	reg signed [width-1:0] R1_I06,  R1_I07, R1_I08,	R1_I09,	R1_I10,	R1_I11;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            R1_I00 <= 0;    R1_I01 <= 0;    R1_I02 <= 0;    R1_I03 <= 0;    R1_I04 <= 0;    R1_I05 <= 0;
            R1_I06 <= 0;    R1_I07 <= 0;    R1_I08 <= 0;    R1_I09 <= 0;    R1_I10 <= 0;    R1_I11 <= 0;
        end
        else begin
            if(nd_r2) begin
                R1_I00 <= {(-din_I1_r2[47:24]),din_I1_r2[23:0]};     R1_I01 <= R1_I00;    R1_I02 <= R1_I01;    R1_I03 <= R1_I02;    R1_I04 <= R1_I03;    R1_I05 <= R1_I04;
                R1_I06 <= R1_I05;                                  R1_I07 <= R1_I06;    R1_I08 <= R1_I07;    R1_I09 <= R1_I08;    R1_I10 <= R1_I09;    R1_I11 <= R1_I10;
            end
            else begin  end
        end
    end


    //u(k)共轭转置 * (1/lamda),用于求B的一部分.B=(1/lamda)*u (n)共轭转置*P(n-1)     (24Q13,24Q13)*(18Q16,18Q16)-->(43Q29,43Q29)
    wire signed [mulR2_width-1:0] mult_R2_I;
    wire m_axis_dout_tvalid;

    RLS12_R2_mult u_R2_mult_I (
    .aclk(clk),                                                               // input wire aclk
    .s_axis_a_tvalid(1'b1),                                                   // input wire s_axis_a_tvalid
    .s_axis_a_tdata({(-din_I1_r2[47:24]),din_I1_r2[23:0]}),                     //24Q13                 // input wire [47 : 0] s_axis_a_tdata
    .s_axis_b_tvalid(1'b1),                                                   // input wire s_axis_b_tvalid
    .s_axis_b_tdata({6'b0,18'b0,6'b0,18'sd65543}),   //18Q16(18'sd65543-->1)  // input wire [47 : 0] s_axis_b_tdata
    .m_axis_dout_tvalid(m_axis_dout_tvalid),                                                    // output wire m_axis_dout_tvalid
    .m_axis_dout_tdata(mult_R2_I)                                             // output wire [95 : 0] m_axis_dout_tdata
    );//输出是(43Q29,43Q29)



    //{24Q13,24Q13} R2[k]       u(k)转置 * (1/lamda)
    reg signed [width-1:0] R2_I00,	R2_I01,	R2_I02,	R2_I03,	R2_I04,	R2_I05;
	reg signed [width-1:0] R2_I06,  R2_I07, R2_I08,	R2_I09,	R2_I10,	R2_I11;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            R2_I00 <= 0;    R2_I01 <= 0;    R2_I02 <= 0;    R2_I03 <= 0;    R2_I04 <= 0;    R2_I05 <= 0;
            R2_I06 <= 0;    R2_I07 <= 0;    R2_I08 <= 0;    R2_I09 <= 0;    R2_I10 <= 0;    R2_I11 <= 0;
        end
        else begin
            if(nd_r6) begin
                R2_I00 <= {mult_R2_I[87:64],mult_R2_I[39:16]};  //(43Q29,43Q29)-->{24Q13,24Q13}
                R2_I01 <= R2_I00;               R2_I02 <= R2_I01;   R2_I03 <= R2_I02;
                R2_I04 <= R2_I03;               R2_I05 <= R2_I04;   R2_I06 <= R2_I05;   R2_I07 <= R2_I06;
                R2_I08 <= R2_I07;               R2_I09 <= R2_I08;   R2_I10 <= R2_I09;   R2_I11 <= R2_I10;
            end
            else begin  end
        end
    end
   



    //P矩阵暂存
    reg signed [p_width-1:0] PI0000,PI0001,PI0002,PI0003,PI0004,PI0005,PI0006,PI0007,PI0008,PI0009,PI0010,PI0011;
		
	reg signed [p_width-1:0] PI0100,PI0101,PI0102,PI0103,PI0104,PI0105,PI0106,PI0107,PI0108,PI0109,PI0110,PI0111;
		
	reg signed [p_width-1:0] PI0200,PI0201,PI0202,PI0203,PI0204,PI0205,PI0206,PI0207,PI0208,PI0209,PI0210,PI0211;
		
	reg signed [p_width-1:0] PI0300,PI0301,PI0302,PI0303,PI0304,PI0305,PI0306,PI0307,PI0308,PI0309,PI0310,PI0311;
		
	reg signed [p_width-1:0] PI0400,PI0401,PI0402,PI0403,PI0404,PI0405,PI0406,PI0407,PI0408,PI0409,PI0410,PI0411;
		
	reg signed [p_width-1:0] PI0500,PI0501,PI0502,PI0503,PI0504,PI0505,PI0506,PI0507,PI0508,PI0509,PI0510,PI0511;
		
	reg signed [p_width-1:0] PI0600,PI0601,PI0602,PI0603,PI0604,PI0605,PI0606,PI0607,PI0608,PI0609,PI0610,PI0611;
		
	reg signed [p_width-1:0] PI0700,PI0701,PI0702,PI0703,PI0704,PI0705,PI0706,PI0707,PI0708,PI0709,PI0710,PI0711;
		
	reg signed [p_width-1:0] PI0800,PI0801,PI0802,PI0803,PI0804,PI0805,PI0806,PI0807,PI0808,PI0809,PI0810,PI0811;
		
	reg signed [p_width-1:0] PI0900,PI0901,PI0902,PI0903,PI0904,PI0905,PI0906,PI0907,PI0908,PI0909,PI0910,PI0911;
		
	reg signed [p_width-1:0] PI1000,PI1001,PI1002,PI1003,PI1004,PI1005,PI1006,PI1007,PI1008,PI1009,PI1010,PI1011;
		
	reg signed [p_width-1:0] PI1100,PI1101,PI1102,PI1103,PI1104,PI1105,PI1106,PI1107,PI1108,PI1109,PI1110,PI1111;


    reg             P_state;
    reg     [4:0]   Pcnt_state;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            P_state     <= 1'b0;
            Pcnt_state  <= 5'd0; 
        end
        else begin
            case(P_state)
                    1'b0:   begin
                        if(cal_en) begin
                            P_state <= 1'b1;
                        end
                        else begin  end
                    end
                    1'b1:   begin
                        case(Pcnt_state)
                                    5'd0:   begin
                                        Pcnt_state <= Pcnt_state + 1'b1;
                                        PI0000<=dout_ram00_r; PI0100<=dout_ram01_r; PI0200<=dout_ram02_r; PI0300<=dout_ram03_r;
										PI0400<=dout_ram04_r; PI0500<=dout_ram05_r; PI0600<=dout_ram06_r; PI0700<=dout_ram07_r;
										PI0800<=dout_ram08_r; PI0900<=dout_ram09_r; PI1000<=dout_ram10_r; PI1100<=dout_ram11_r;
                                    end
                                    5'd1:   begin
                                        Pcnt_state <= Pcnt_state+1'b1;
										PI0001<=dout_ram00_r; PI0101<=dout_ram01_r; PI0201<=dout_ram02_r; PI0301<=dout_ram03_r;
										PI0401<=dout_ram04_r; PI0501<=dout_ram05_r; PI0601<=dout_ram06_r; PI0701<=dout_ram07_r;
										PI0801<=dout_ram08_r; PI0901<=dout_ram09_r; PI1001<=dout_ram10_r; PI1101<=dout_ram11_r;
                                    end
                                    5'd2:   begin
                                        Pcnt_state <= Pcnt_state+1'b1;
										PI0002<=dout_ram00_r; PI0102<=dout_ram01_r; PI0202<=dout_ram02_r; PI0302<=dout_ram03_r;
										PI0402<=dout_ram04_r; PI0502<=dout_ram05_r; PI0602<=dout_ram06_r; PI0702<=dout_ram07_r;
										PI0802<=dout_ram08_r; PI0902<=dout_ram09_r; PI1002<=dout_ram10_r; PI1102<=dout_ram11_r;
                                    end
                                    5'd3:   begin
                                        Pcnt_state <= Pcnt_state+1'b1;
										PI0003<=dout_ram00_r; PI0103<=dout_ram01_r; PI0203<=dout_ram02_r; PI0303<=dout_ram03_r;
										PI0403<=dout_ram04_r; PI0503<=dout_ram05_r; PI0603<=dout_ram06_r; PI0703<=dout_ram07_r;
										PI0803<=dout_ram08_r; PI0903<=dout_ram09_r; PI1003<=dout_ram10_r; PI1103<=dout_ram11_r;
                                    end
                                    5'd4:   begin
                                        Pcnt_state <= Pcnt_state+1'b1;
										PI0004<=dout_ram00_r; PI0104<=dout_ram01_r; PI0204<=dout_ram02_r; PI0304<=dout_ram03_r;
										PI0404<=dout_ram04_r; PI0504<=dout_ram05_r; PI0604<=dout_ram06_r; PI0704<=dout_ram07_r;
										PI0804<=dout_ram08_r; PI0904<=dout_ram09_r; PI1004<=dout_ram10_r; PI1104<=dout_ram11_r;
                                    end
                                    5'd5:   begin
                                        Pcnt_state <= Pcnt_state+1'b1;
										PI0005<=dout_ram00_r; PI0105<=dout_ram01_r; PI0205<=dout_ram02_r; PI0305<=dout_ram03_r;
										PI0405<=dout_ram04_r; PI0505<=dout_ram05_r; PI0605<=dout_ram06_r; PI0705<=dout_ram07_r;
										PI0805<=dout_ram08_r; PI0905<=dout_ram09_r; PI1005<=dout_ram10_r; PI1105<=dout_ram11_r;
                                    end
                                    5'd6:   begin
                                        Pcnt_state <= Pcnt_state+1'b1;
										PI0006<=dout_ram00_r; PI0106<=dout_ram01_r; PI0206<=dout_ram02_r; PI0306<=dout_ram03_r;
										PI0406<=dout_ram04_r; PI0506<=dout_ram05_r; PI0606<=dout_ram06_r; PI0706<=dout_ram07_r;
										PI0806<=dout_ram08_r; PI0906<=dout_ram09_r; PI1006<=dout_ram10_r; PI1106<=dout_ram11_r;
                                    end
                                    5'd7:   begin
                                        Pcnt_state <= Pcnt_state+1'b1;
										PI0007<=dout_ram00_r; PI0107<=dout_ram01_r; PI0207<=dout_ram02_r; PI0307<=dout_ram03_r;
										PI0407<=dout_ram04_r; PI0507<=dout_ram05_r; PI0607<=dout_ram06_r; PI0707<=dout_ram07_r;
										PI0807<=dout_ram08_r; PI0907<=dout_ram09_r; PI1007<=dout_ram10_r; PI1107<=dout_ram11_r;
                                    end
                                    5'd8:   begin
                                        Pcnt_state <= Pcnt_state+1'b1;
										PI0008<=dout_ram00_r; PI0108<=dout_ram01_r; PI0208<=dout_ram02_r; PI0308<=dout_ram03_r; 
										PI0408<=dout_ram04_r; PI0508<=dout_ram05_r; PI0608<=dout_ram06_r; PI0708<=dout_ram07_r; 
										PI0808<=dout_ram08_r; PI0908<=dout_ram09_r; PI1008<=dout_ram10_r; PI1108<=dout_ram11_r;
                                    end
                                    5'd9:   begin
                                        Pcnt_state <= Pcnt_state+1'b1;
										PI0009<=dout_ram00_r; PI0109<=dout_ram01_r; PI0209<=dout_ram02_r; PI0309<=dout_ram03_r;
										PI0409<=dout_ram04_r; PI0509<=dout_ram05_r; PI0609<=dout_ram06_r; PI0709<=dout_ram07_r;
										PI0809<=dout_ram08_r; PI0909<=dout_ram09_r; PI1009<=dout_ram10_r; PI1109<=dout_ram11_r;
                                    end
                                    5'd10:  begin
                                        Pcnt_state <= Pcnt_state+1'b1;
										PI0010<=dout_ram00_r; PI0110<=dout_ram01_r; PI0210<=dout_ram02_r; PI0310<=dout_ram03_r; 
										PI0410<=dout_ram04_r; PI0510<=dout_ram05_r; PI0610<=dout_ram06_r; PI0710<=dout_ram07_r; 
										PI0810<=dout_ram08_r; PI0910<=dout_ram09_r; PI1010<=dout_ram10_r; PI1110<=dout_ram11_r; 
                                    end
                                    default:    begin
                                        P_state <= 1'b0;
										Pcnt_state <= 5'd0;
										PI0011<=dout_ram00_r; PI0111<=dout_ram01_r; PI0211<=dout_ram02_r; PI0311<=dout_ram03_r; 
										PI0411<=dout_ram04_r; PI0511<=dout_ram05_r; PI0611<=dout_ram06_r; PI0711<=dout_ram07_r; 
										PI0811<=dout_ram08_r; PI0911<=dout_ram09_r; PI1011<=dout_ram10_r; PI1111<=dout_ram11_r; 
                                    end
                        endcase
                    end
            endcase
        end
    end




    //A[k]信号赋值（计算） mult00_pr(61Q42,61Q42)-->(40Q29,40Q29)-->后面转换为(36Q28,36Q28)
    reg signed [adder_width-1:0] AI00,AI01,AI02,AI03,AI04,AI05,AI06,AI07,AI08,AI09,AI10,AI11;

    always @(posedge clk) begin
        if(!rst_n || cal_en) begin
            AI00<=0;	AI01<=0;	AI02<=0;	AI03<=0;	AI04<=0;	AI05<=0;	AI06<=0;	AI07<=0; 
			AI08<=0;	AI09<=0;	AI10<=0;	AI11<=0;
        end
        else begin
            if(A_en) begin
                AI00<={AI00[79:40]+mult00_pr[116:77],AI00[39:0]+mult00_pr[52:13]};	AI01<={AI01[79:40]+mult01_pr[116:77],AI01[39:0]+mult01_pr[52:13]};	
				AI02<={AI02[79:40]+mult02_pr[116:77],AI02[39:0]+mult02_pr[52:13]};	AI03<={AI03[79:40]+mult03_pr[116:77],AI03[39:0]+mult03_pr[52:13]};	
				AI04<={AI04[79:40]+mult04_pr[116:77],AI04[39:0]+mult04_pr[52:13]};	AI05<={AI05[79:40]+mult05_pr[116:77],AI05[39:0]+mult05_pr[52:13]};
				AI06<={AI06[79:40]+mult06_pr[116:77],AI06[39:0]+mult06_pr[52:13]};	AI07<={AI07[79:40]+mult07_pr[116:77],AI07[39:0]+mult07_pr[52:13]};
				AI08<={AI08[79:40]+mult08_pr[116:77],AI08[39:0]+mult08_pr[52:13]};  AI09<={AI09[79:40]+mult09_pr[116:77],AI09[39:0]+mult09_pr[52:13]};	
				AI10<={AI10[79:40]+mult10_pr[116:77],AI10[39:0]+mult10_pr[52:13]};	AI11<={AI11[79:40]+mult11_pr[116:77],AI11[39:0]+mult11_pr[52:13]};
            end
            else begin  end
        end
    end



    //C 计算   34Q25
	reg  	[2:0] 	C_state;
	reg  signed [div_width-1:0] C;
	reg  signed [adder_width-1:0] C_r11,C_r12,C_r13,C_r14,C_r15,C_r16;
	reg  signed [adder_width-1:0] C_r21,C_r22,C_r23;
	reg  signed [adder_width-1:0] C_r31,C_r32;
	reg  signed [adder_width-1:0] C_r41;
	reg  signed [adder_width-1:0] C_r51;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            C_r11<=0;	C_r12<=0;	C_r13<=0;	C_r14<=0;	C_r15<=0;	C_r16<=0;
			C_r21<=0;	C_r22<=0;	C_r23<=0;	
			C_r31<=0;	C_r32<=0;	
            C_r41<=0;	
            C_r51<=0;
			C	  <=0;	C_state<=0;
        end
        else begin
            case(C_state)
                    default:    begin
                            if(C_en) begin
                                C_state<=3'd1;//(61Q38,61Q38)-->(40Q29,40Q29)
								C_r11 <={(mult00_pr[112:73]+mult01_pr[112:73]),(mult00_pr[48:9]+mult01_pr[48:9])};	C_r12 <={(mult02_pr[112:73]+mult03_pr[112:73]),(mult02_pr[48:9]+mult03_pr[48:9])};
								C_r13 <={(mult04_pr[112:73]+mult05_pr[112:73]),(mult04_pr[48:9]+mult05_pr[48:9])};	C_r14 <={(mult06_pr[112:73]+mult07_pr[112:73]),(mult06_pr[48:9]+mult07_pr[48:9])};
								C_r15 <={(mult08_pr[112:73]+mult09_pr[112:73]),(mult08_pr[48:9]+mult09_pr[48:9])};	C_r16 <={(mult10_pr[112:73]+mult11_pr[112:73]),(mult10_pr[48:9]+mult11_pr[48:9])};
                            end
                            else begin
                                C_state<=3'd0;
                            end
                    end
                    3'd1:   begin
                            C_state<=C_state+1'b1;
						    C_r21<={(C_r11[79:40]+C_r12[79:40]),(C_r11[39:0]+C_r12[39:0])};		C_r22<={(C_r13[79:40]+C_r14[79:40]),(C_r13[39:0]+C_r14[39:0])};		C_r23<={(C_r15[79:40]+C_r16[79:40]),(C_r15[39:0]+C_r16[39:0])};
                    end
                    3'd2:   begin
                            C_state<=C_state+1'b1;
						    C_r31<={(C_r21[79:40]+C_r22[79:40]),(C_r21[39:0]+C_r22[39:0])};	C_r32<=C_r23;
                    end
                    3'd3:   begin
                            C_r41<={(C_r31[79:40]+C_r32[79:40]),(C_r31[39:0]+C_r32[39:0])};
						    C_state<=C_state+1'b1;
                    end
                    3'd4:   begin
                            C_state	<=C_state+1'b1;
						    C_r51		<=C_r41;  //u[k](共轭转置)*A[k]
                    end
                    3'd5:   begin
                            C_state	<=0;//(40Q29,40Q29)-->(34Q25,34Q25)
						    C			<={C_r51[77:44]+34'b0,C_r51[37:4]+34'sd33551077};  //C=lamada+u[k](转置)*A[k]
                    end
            endcase
        end
    end



    //D计算 24Q20
    reg 	[width-1:0] D_I;
	reg 	nd_div;
	wire 	div_rdy;
	reg     [div_width-1:0]     Divisor;  //34Q25
    wire    [39 : 0]            re_res,im_res;
    //m_axis_dout_tdata;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            D_I     <= 0;
            nd_div  <= 0;
        end
        else begin
            if(D_en) begin
                nd_div  <= 1;
                Divisor <= C;
            end
            else begin
                nd_div  <= 0;
            end
            if(div_rdy) begin
                D_I <= {im_res [30:7],re_res [30:7]};//40Q27-->24Q20
            end
            else begin
                D_I <= D_I;
            end
        end
    end

    
    float_complex_div u_float_complex_div(
        .clk(clk),
        .rst_n(rst_n), 
        .start(nd_div),
        .re_a({34'sd33554432}),//被除数a的实部    34Q25
        .im_a(34'd0),
        .re_b(Divisor[33:0]),//除数b的实部
        .im_b(Divisor[67:34]),//除数b的虚部
        .over(div_rdy),
        .re_res(re_res),
        .im_res(im_res)
    );

    
    

    //B[k]计算 (40Q30,40Q30)
    reg signed[adder_width-1:0] BI00,BI01,BI02,BI03,BI04,BI05,BI06,BI07,BI08,BI09,BI10,BI11;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            BI00<=0;BI01<=0;BI02<=0;BI03<=0;BI04<=0;BI05<=0;BI06<=0;BI07<=0;
			BI08<=0;BI09<=0;BI10<=0;BI11<=0;
        end
        else if(cal_en) begin
            BI00<=0;BI01<=0;BI02<=0;BI03<=0;BI04<=0;BI05<=0;BI06<=0;BI07<=0;
			BI08<=0;BI09<=0;BI10<=0;BI11<=0;
        end
        else if(B_en) begin      //(61Q42,61Q42)-->(40Q30,40Q30)
            BI00<={(BI00[79:40]+mult00_pr[115:76]),(BI00[39:0]+mult00_pr[51:12])};	BI01<={(BI01[79:40]+mult01_pr[115:76]),(BI01[39:0]+mult01_pr[51:12])};
			BI02<={(BI02[79:40]+mult02_pr[115:76]),(BI02[39:0]+mult02_pr[51:12])};	BI03<={(BI03[79:40]+mult03_pr[115:76]),(BI03[39:0]+mult03_pr[51:12])};
			BI04<={(BI04[79:40]+mult04_pr[115:76]),(BI04[39:0]+mult04_pr[51:12])};	BI05<={(BI05[79:40]+mult05_pr[115:76]),(BI05[39:0]+mult05_pr[51:12])};
			BI06<={(BI06[79:40]+mult06_pr[115:76]),(BI06[39:0]+mult06_pr[51:12])};	BI07<={(BI07[79:40]+mult07_pr[115:76]),(BI07[39:0]+mult07_pr[51:12])};
			BI08<={(BI08[79:40]+mult08_pr[115:76]),(BI08[39:0]+mult08_pr[51:12])};  BI09<={(BI09[79:40]+mult09_pr[115:76]),(BI09[39:0]+mult09_pr[51:12])};
			BI10<={(BI10[79:40]+mult10_pr[115:76]),(BI10[39:0]+mult10_pr[51:12])};	BI11<={(BI11[79:40]+mult11_pr[115:76]),(BI11[39:0]+mult11_pr[51:12])};
        end
    end




    //A1[k]计算 24Q20
    reg signed[width-1:0] A1I00,A1I01,A1I02,A1I03,A1I04,A1I05,A1I06,A1I07,A1I08,A1I09,A1I10,A1I11;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            A1I00<=0;A1I01<=0;A1I02<=0;A1I03<=0;A1I04<=0;A1I05<=0;
			A1I06<=0;A1I07<=0;A1I08<=0;A1I09<=0;A1I10<=0;A1I11<=0;
        end
        else begin
            if(A1_en) begin
                A1I00<={mult00_pr[115:92],mult00_pr[51:28]};A1I01<={mult01_pr[115:92],mult01_pr[51:28]};A1I02<={mult02_pr[115:92],mult02_pr[51:28]};
                A1I03<={mult03_pr[115:92],mult03_pr[51:28]};A1I04<={mult04_pr[115:92],mult04_pr[51:28]};A1I05<={mult05_pr[115:92],mult05_pr[51:28]};
                A1I06<={mult06_pr[115:92],mult06_pr[51:28]};A1I07<={mult07_pr[115:92],mult07_pr[51:28]};A1I08<={mult08_pr[115:92],mult08_pr[51:28]};
                A1I09<={mult09_pr[115:92],mult09_pr[51:28]};A1I10<={mult10_pr[115:92],mult10_pr[51:28]};A1I11<={mult11_pr[115:92],mult11_pr[51:28]};
            end
            else begin  end
        end
    end



	reg wt_update,GN_out_en;

    reg GN_out_en1;

	always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            GN_out_en	<=0;
		    wt_update	<=0;
            GN_out_en1   <=0;
        end
        else begin
            GN_out_en	<=GN_en;
            GN_out_en1  <=GN_out_en;
		    wt_update	<=GN_out_en;
        end
    end

	//Y(n)=w(n-1)共轭转置*u(n) 计算 36Q27  {36Q27  *24Q13}
	reg  [2:0] 	Y_state;
	reg 		fifo_rd;
	reg  signed [p_width-1:0]       YI;
	reg  signed [adder_width-1:0]   YI_r11,YI_r12,YI_r13,YI_r14,YI_r15,YI_r16;
	reg  signed [adder_width-1:0]   YI_r21,YI_r22,YI_r23;
	reg  signed [adder_width-1:0]   YI_r31,YI_r32;
	reg  signed [adder_width-1:0]   YI_r41;
	reg  signed [adder_width-1:0]   YI_r51;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            YI_r11<=0;	YI_r12<=0;	YI_r13<=0;	YI_r14<=0;	YI_r15<=0;	YI_r16<=0;
			YI_r21<=0;	YI_r22<=0;	YI_r23<=0;	
			YI_r31<=0;	YI_r32<=0;	
            YI_r41<=0;
            YI_r51<=0;
			YI	  <=0;	Y_state<=0; 
			fifo_rd<=0;
        end
        else begin
            case(Y_state)
                    default:    begin
                        if(rls_out_en) begin    //(61Q40,61Q40)-->(40Q28,40Q28)
                            Y_state<=3'd1;
							YI_r11 <={(mult00_pr[115:76]+mult01_pr[115:76]),(mult00_pr[51:12]+mult01_pr[51:12])};	YI_r12 <={(mult02_pr[115:76]+mult03_pr[115:76]),(mult02_pr[51:12]+mult03_pr[51:12])};
							YI_r13 <={(mult04_pr[115:76]+mult05_pr[115:76]),(mult04_pr[51:12]+mult05_pr[51:12])};	YI_r14 <={(mult06_pr[115:76]+mult07_pr[115:76]),(mult06_pr[51:12]+mult07_pr[51:12])};
							YI_r15 <={(mult08_pr[115:76]+mult09_pr[115:76]),(mult08_pr[51:12]+mult09_pr[51:12])};	YI_r16 <={(mult10_pr[115:76]+mult11_pr[115:76]),(mult10_pr[51:12]+mult11_pr[51:12])};
                        end
                        else begin
                            Y_state <= 3'd0;
                        end
                    end
                    3'd1:   begin
                        Y_state<=Y_state+1'b1;
						YI_r21<={(YI_r11[79:40]+YI_r12[79:40]),(YI_r11[39:0]+YI_r12[39:0])};		YI_r22<={(YI_r13[79:40]+YI_r14[79:40]),(YI_r13[39:0]+YI_r14[39:0])};		YI_r23<={(YI_r15[79:40]+YI_r16[79:40]),(YI_r15[39:0]+YI_r16[39:0])};
                    end
                    3'd2:   begin
                        Y_state<=Y_state+1'b1;
						YI_r31<={(YI_r21[79:40]+YI_r22[79:40]),(YI_r21[39:0]+YI_r22[39:0])};	YI_r32<=YI_r23;
                    end
                    3'd3:   begin
                        fifo_rd<=1'b1;
						YI_r41<={(YI_r31[79:40]+YI_r32[79:40]),(YI_r31[39:0]+YI_r32[39:0])};
						Y_state<=Y_state+1'b1;
                    end
                    3'd4:   begin
                        fifo_rd<=1'b0;
						Y_state	<=Y_state+1'b1;
						YI_r51	<=YI_r41;
                    end
                    3'd5:   begin
                        Y_state		<=0;
						YI				<={YI_r51[78:43],YI_r51[38:3]};//40Q28-->36Q25
                    end
            endcase
        end
    end



    wire [width-1:0] dout_fifo;
    wire rx_fifo_full;
    wire rx_fifo_empty;
    wire rx_fifo_valid;
    wire rx_fifo_wr_rst_busy;
    wire rx_fifo_rd_rst_busy;

	reg 	signed	[width-1:0]   rx_I_r;
	reg 	signed	[p_width-1:0] rx_I;
	reg				rx_nd_r;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rx_nd_r <= 0;
            rx_I_r <= 0;
            rx_I <= 0;
        end
        else begin
            rx_nd_r <= rx_d_nd;
            rx_I_r <= rx_d;
            rx_I <= {dout_fifo[47:24],12'b0,dout_fifo[23:0],12'b0};    //(24Q13,24Q13)-->(36Q25,36Q25)
        end
    end



    // RLS12_rx_fifo rls_rx_fifo_matrix_update (
    // .clk(clk),      // input wire clk
    // .rst(!rst_n),      // input wire rst
    // .din(rx_I_r),      // input wire [47 : 0] din
    // .wr_en(rx_nd_r),  // input wire wr_en
    // .rd_en(fifo_rd),  // input wire rd_en
    // .dout(dout_fifo),    // output wire [47 : 0] dout
    // .full(),    // output wire full
    // .empty()  // output wire empty
    // );

RLS12_rx_fifo your_instance_name (
  .clk(clk),      // input wire clk
  .srst(!rst_n),    // input wire srst
  .din(rx_I_r),      // input wire [47 : 0] din
  .wr_en(rx_nd_r),  // input wire wr_en
  .rd_en(fifo_rd),  // input wire rd_en
  .dout(dout_fifo),    // output wire [47 : 0] dout
  .full(rx_fifo_full),    // output wire full
  .empty(rx_fifo_empty),  // output wire empty
  .valid(rx_fifo_valid),  // output wire valid
  .wr_rst_busy(rx_fifo_wr_rst_busy),
  .rd_rst_busy(rx_fifo_rd_rst_busy)
);

    //残余自干扰信号 err[n]=y[n]-w[n-1](共轭转置)*u[n] 接收信号减去重建信号
    reg signed [p_width-1:0] Errsub_ar;
    reg signed [p_width-1:0] Errsub_br;
    reg signed [p_width-1:0] Err_I;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            Errsub_ar <= 0;
            Errsub_br <= 0;
        end
        else begin
            Errsub_ar <= rx_I;//(36Q25,36Q25)
            Errsub_br <= YI;//(36Q25,36Q25)
        end
    end

    reg Err_sub_en,Err_out_en;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            Err_sub_en <= 0;
            Err_out_en <= 0;
        end
        else begin
            Err_sub_en <= Y_en;
            Err_out_en <= Err_sub_en;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            Err_I <= 0;
        end
        else begin
            Err_I <= {(Errsub_ar[71:36]-Errsub_br[71:36]),(Errsub_ar[35:0]-Errsub_br[35:0])};//36Q25
        end
    end



    //G(n)=err(n)*A1(n)  {36Q25*24Q20-->61Q45-->36Q27}   (w(n)=w(n-1)+A1(n)*[err(n)(共轭)])
    reg signed [p_width-1:0] GnI00,GnI01,GnI02,GnI03,GnI04,GnI05,GnI06,GnI07,GnI08,GnI09,GnI10,GnI11;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            GnI00<=0; GnI01<=0; GnI02<=0; GnI03<=0; GnI04<=0; GnI05<=0;
			GnI06<=0; GnI07<=0; GnI08<=0; GnI09<=0; GnI10<=0; GnI11<=0;
        end
        else begin
            if(GN_en) begin
                GnI00<={mult00_pr[117:82],mult00_pr[53:18]}; GnI01<={mult01_pr[117:82],mult01_pr[53:18]}; GnI02<={mult02_pr[117:82],mult02_pr[53:18]};
                GnI03<={mult03_pr[117:82],mult03_pr[53:18]}; GnI04<={mult04_pr[117:82],mult04_pr[53:18]}; GnI05<={mult05_pr[117:82],mult05_pr[53:18]};
				GnI06<={mult06_pr[117:82],mult06_pr[53:18]}; GnI07<={mult07_pr[117:82],mult07_pr[53:18]}; GnI08<={mult08_pr[117:82],mult08_pr[53:18]};
				GnI09<={mult09_pr[117:82],mult09_pr[53:18]}; GnI10<={mult10_pr[117:82],mult10_pr[53:18]}; GnI11<={mult11_pr[117:82],mult11_pr[53:18]};
            end
            else begin  end
        end
    end




    //滤波器系数更新w[k]=w[k-1]+A'[k]*err[k]
    reg signed [coe_width-1:0] rls_wt00_I,rls_wt01_I,rls_wt02_I,rls_wt03_I,rls_wt04_I,rls_wt05_I;
	reg signed [coe_width-1:0] rls_wt06_I,rls_wt07_I,rls_wt08_I,rls_wt09_I,rls_wt10_I,rls_wt11_I;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rls_wt00_I<=0; rls_wt01_I<=0; rls_wt02_I<=0; rls_wt03_I<=0; rls_wt04_I<=0; rls_wt05_I<=0;       
		    rls_wt06_I<=0; rls_wt07_I<=0; rls_wt08_I<=0; rls_wt09_I<=0; rls_wt10_I<=0; rls_wt11_I<=0;
        end
        else begin
            if(GN_out_en) begin     //(36Q27,36Q27)
                rls_wt00_I<={(rls_wt00_I[71:36]+GnI00[71:36]),(rls_wt00_I[35:0]+GnI00[35:0])}; rls_wt01_I<={(rls_wt01_I[71:36]+GnI01[71:36]),(rls_wt01_I[35:0]+GnI01[35:0])}; rls_wt02_I<={(rls_wt02_I[71:36]+GnI02[71:36]),(rls_wt02_I[35:0]+GnI02[35:0])};
                rls_wt03_I<={(rls_wt03_I[71:36]+GnI03[71:36]),(rls_wt03_I[35:0]+GnI03[35:0])}; rls_wt04_I<={(rls_wt04_I[71:36]+GnI04[71:36]),(rls_wt04_I[35:0]+GnI04[35:0])}; rls_wt05_I<={(rls_wt05_I[71:36]+GnI05[71:36]),(rls_wt05_I[35:0]+GnI05[35:0])};
                rls_wt06_I<={(rls_wt06_I[71:36]+GnI06[71:36]),(rls_wt06_I[35:0]+GnI06[35:0])}; rls_wt07_I<={(rls_wt07_I[71:36]+GnI07[71:36]),(rls_wt07_I[35:0]+GnI07[35:0])}; rls_wt08_I<={(rls_wt08_I[71:36]+GnI08[71:36]),(rls_wt08_I[35:0]+GnI08[35:0])}; 
                rls_wt09_I<={(rls_wt09_I[71:36]+GnI09[71:36]),(rls_wt09_I[35:0]+GnI09[35:0])}; rls_wt10_I<={(rls_wt10_I[71:36]+GnI10[71:36]),(rls_wt10_I[35:0]+GnI10[35:0])}; rls_wt11_I<={(rls_wt11_I[71:36]+GnI11[71:36]),(rls_wt11_I[35:0]+GnI11[35:0])};
            end
            else begin  end
        end
    end




    //滤波器系数输出
    reg [4:0] 					update_state;
	reg  		 				update_rdy;
	reg		 					update_en;
	reg		 					RLS_wt_update_r;
	//reg [coe_widthout-1:0] 	    wt_out_re;//(25Q20,25Q20)
    reg [71:0] 	    wt_out_re;//(36Q27,36Q27)

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            RLS_wt_update_r <= 1'b0;
        end
        else begin
            RLS_wt_update_r <= RLS_wt_update;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wt_pulse		<=0;
		    wt_update_en	<=0;
		    wt_update_I		<=0;
        end
        else begin
            wt_pulse		<=update_rdy;
		    wt_update_en	<=update_en;
		    wt_update_I		<=wt_out_re;
        end
    end

    //系数倒着赋值，以便后面FIR滤波器系数重载
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            update_state	<=0;
		    wt_out_re		<=0;
		    update_en		<=0;
		    update_rdy		<=0;
        end
        else begin
            case(update_state)
                        default:        begin
                            update_en		<=1'b0;
                            if(RLS_wt_update_r&&wt_update) begin
                                update_rdy		<=1'b1;
					            update_state	<=5'd1;
                            end
                            else begin  end
                        end
                        5'd1:       begin
                            update_state	<=update_state+1'b1;
				            update_rdy		<=1'b0;						update_en		<=1'b1;
				            wt_out_re		<={rls_wt11_I[35:0],rls_wt11_I[71:36]};    //(36Q27,36Q27)  高实低虚
                        end
                        5'd2:       begin
                            update_state	<=update_state+1'b1;		wt_out_re		<={rls_wt10_I[35:0],rls_wt10_I[71:36]};
                        end
                        5'd3:       begin
                            update_state	<=update_state+1'b1;		wt_out_re		<={rls_wt09_I[35:0],rls_wt09_I[71:36]};
                        end
                        5'd4:           begin
                            update_state	<=update_state+1'b1;		wt_out_re		<={rls_wt08_I[35:0],rls_wt08_I[71:36]};
                        end
                        5'd5:       begin
                            update_state	<=update_state+1'b1;		wt_out_re		<={rls_wt07_I[35:0],rls_wt07_I[71:36]};
                        end
                        5'd6:       begin
                            update_state	<=update_state+1'b1;		wt_out_re		<={rls_wt06_I[35:0],rls_wt06_I[71:36]};
                        end
                        5'd7:		begin
                            update_state	<=update_state+1'b1;		wt_out_re		<={rls_wt05_I[35:0],rls_wt05_I[71:36]};	
                        end
                        5'd8:		begin
                            update_state	<=update_state+1'b1;		wt_out_re		<={rls_wt04_I[35:0],rls_wt04_I[71:36]};		
                        end
                        5'd9:		begin
                            update_state	<=update_state+1'b1;		wt_out_re		<={rls_wt03_I[35:0],rls_wt03_I[71:36]};		
                        end
                        5'd10:		begin
                            update_state	<=update_state+1'b1;		wt_out_re		<={rls_wt02_I[35:0],rls_wt02_I[71:36]};		
                        end
                        5'd11:		begin
                            update_state	<=update_state+1'b1;		wt_out_re		<={rls_wt01_I[35:0],rls_wt01_I[71:36]};		
                        end
                        5'd12:		begin
                            update_state	<=5'd0;						wt_out_re		<={rls_wt00_I[35:0],rls_wt00_I[71:36]};		
                        end
            endcase
        end
    end


    // //读取系数(高实低虚)
    // integer save_file20;//wt

    // initial begin
    //     save_file20 = $fopen("build/debug/RLS12_hf/dmcoe21.txt");
    // end

    // always @(posedge clk or negedge rst_n) begin
    //     if(update_en) begin
    //         $fdisplay(save_file20 ,"%b",wt_out_re);
    //     end
    // end




    //减法器组输入 dout_sub_ar00 = P'[K]；dout_sub_br00 = A'[K]B[K]；用于计算P
    reg signed [p_width-1:0] dout_sub_ar00,dout_sub_ar01,dout_sub_ar02,dout_sub_ar03;
	reg signed [p_width-1:0] dout_sub_ar04,dout_sub_ar05,dout_sub_ar06,dout_sub_ar07;
	reg signed [p_width-1:0] dout_sub_ar08,dout_sub_ar09,dout_sub_ar10,dout_sub_ar11;
	
	
	reg signed [p_width-1:0] dout_sub_br00,dout_sub_br01,dout_sub_br02,dout_sub_br03;
	reg signed [p_width-1:0] dout_sub_br04,dout_sub_br05,dout_sub_br06,dout_sub_br07;
	reg signed [p_width-1:0] dout_sub_br08,dout_sub_br09,dout_sub_br10,dout_sub_br11;


    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            dout_sub_ar00<=0; dout_sub_ar01<=0; dout_sub_ar02<=0; dout_sub_ar03<=0;
			dout_sub_ar04<=0; dout_sub_ar05<=0; dout_sub_ar06<=0; dout_sub_ar07<=0;
			dout_sub_ar08<=0; dout_sub_ar09<=0; dout_sub_ar10<=0; dout_sub_ar11<=0;
			
			
			dout_sub_br00<=0; dout_sub_br01<=0; dout_sub_br02<=0; dout_sub_br03<=0;
			dout_sub_br04<=0; dout_sub_br05<=0; dout_sub_br06<=0; dout_sub_br07<=0;
			dout_sub_br08<=0; dout_sub_br09<=0; dout_sub_br10<=0; dout_sub_br11<=0;
        end
        else begin
            dout_sub_ar00<=dout_ram00_r;    dout_sub_ar01<=dout_ram01_r;
			dout_sub_ar02<=dout_ram02_r;    dout_sub_ar03<=dout_ram03_r;
			dout_sub_ar04<=dout_ram04_r;    dout_sub_ar05<=dout_ram05_r;
			dout_sub_ar06<=dout_ram06_r;    dout_sub_ar07<=dout_ram07_r;
			dout_sub_ar08<=dout_ram08_r;    dout_sub_ar09<=dout_ram09_r;
			dout_sub_ar10<=dout_ram10_r;    dout_sub_ar11<=dout_ram11_r;//(36Q29,36Q29)
		
			//(61Q48,61Q48)-->(36Q29,36Q29)
			dout_sub_br00<={mult00_pr[118:83],mult00_pr[54:19]};    dout_sub_br01<={mult01_pr[118:83],mult01_pr[54:19]};
			dout_sub_br02<={mult02_pr[118:83],mult02_pr[54:19]};    dout_sub_br03<={mult03_pr[118:83],mult03_pr[54:19]};
			dout_sub_br04<={mult04_pr[118:83],mult04_pr[54:19]};    dout_sub_br05<={mult05_pr[118:83],mult05_pr[54:19]};
			dout_sub_br06<={mult06_pr[118:83],mult06_pr[54:19]};    dout_sub_br07<={mult07_pr[118:83],mult07_pr[54:19]};
			dout_sub_br08<={mult08_pr[118:83],mult08_pr[54:19]};    dout_sub_br09<={mult09_pr[118:83],mult09_pr[54:19]};
			dout_sub_br10<={mult10_pr[118:83],mult10_pr[54:19]};    dout_sub_br11<={mult11_pr[118:83],mult11_pr[54:19]};
        end
    end

    //P[k]=P'[k]-A'[k]B[k]
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            dout_subI00		<=0;dout_subI01		<=0;dout_subI02		<=0;dout_subI03		<=0;
		    dout_subI04		<=0;dout_subI05		<=0;dout_subI06		<=0;dout_subI07		<=0;
		    dout_subI08		<=0;dout_subI09		<=0;dout_subI10		<=0;dout_subI11		<=0;
        end
        else begin          //(30Q29,36Q29)
            dout_subI00		<= {(dout_sub_ar00[71:36]-dout_sub_br00[71:36]),(dout_sub_ar00[35:0]-dout_sub_br00[35:0])};
            dout_subI01		<= {(dout_sub_ar01[71:36]-dout_sub_br01[71:36]),(dout_sub_ar01[35:0]-dout_sub_br01[35:0])};
            dout_subI02		<= {(dout_sub_ar02[71:36]-dout_sub_br02[71:36]),(dout_sub_ar02[35:0]-dout_sub_br02[35:0])};
            dout_subI03		<= {(dout_sub_ar03[71:36]-dout_sub_br03[71:36]),(dout_sub_ar03[35:0]-dout_sub_br03[35:0])};
            dout_subI04		<= {(dout_sub_ar04[71:36]-dout_sub_br04[71:36]),(dout_sub_ar04[35:0]-dout_sub_br04[35:0])};
            dout_subI05		<= {(dout_sub_ar05[71:36]-dout_sub_br05[71:36]),(dout_sub_ar05[35:0]-dout_sub_br05[35:0])};
            dout_subI06		<= {(dout_sub_ar06[71:36]-dout_sub_br06[71:36]),(dout_sub_ar06[35:0]-dout_sub_br06[35:0])};
            dout_subI07		<= {(dout_sub_ar07[71:36]-dout_sub_br07[71:36]),(dout_sub_ar07[35:0]-dout_sub_br07[35:0])};
            dout_subI08		<= {(dout_sub_ar08[71:36]-dout_sub_br08[71:36]),(dout_sub_ar08[35:0]-dout_sub_br08[35:0])};
            dout_subI09		<= {(dout_sub_ar09[71:36]-dout_sub_br09[71:36]),(dout_sub_ar09[35:0]-dout_sub_br09[35:0])};
            dout_subI10		<= {(dout_sub_ar10[71:36]-dout_sub_br10[71:36]),(dout_sub_ar10[35:0]-dout_sub_br10[35:0])};
            dout_subI11		<= {(dout_sub_ar11[71:36]-dout_sub_br11[71:36]),(dout_sub_ar11[35:0]-dout_sub_br11[35:0])};
        end
    end


    
    
    //乘法器时分复用
    reg [5:0] mul_B,mul_P,mul_AB;		
	reg [3:0] mul_state;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            mul_B<=6'd0;
			mul_state<=4'd0;
			mul_P<=0;
			mul_AB<=0;
			mult00_ar<=0; mult00_br<=0; mult01_ar<=0; mult01_br<=0;
			mult02_ar<=0; mult02_br<=0; mult03_ar<=0; mult03_br<=0;
			mult04_ar<=0; mult04_br<=0; mult05_ar<=0; mult05_br<=0;
			mult06_ar<=0; mult06_br<=0; mult07_ar<=0; mult07_br<=0;
			mult08_ar<=0; mult08_br<=0; mult09_ar<=0; mult09_br<=0;
			mult10_ar<=0; mult10_br<=0; mult11_ar<=0; mult11_br<=0;
        end
        else begin
            case(mul_state)
                    default:        begin
                        if(cal_en) begin
                            mul_state <= 4'd1;
                        end
                        else begin
                            mul_state <= 4'd0;
                        end
                    end
                    4'd1:       begin//计算A=P*u
                        if(cnt_clk == 23) begin
                            mul_state <= 4'd2;
                        end
                        else begin  end         //(36Q29,36Q29)*(24Q13,24Q13)-->(61Q42,61Q42)
                        mult00_br<=din1_r4; mult00_ar<=dout_ram00_r; mult01_br<=din1_r4; mult01_ar<=dout_ram01_r;
                        mult02_br<=din1_r4; mult02_ar<=dout_ram02_r; mult03_br<=din1_r4; mult03_ar<=dout_ram03_r;
                        mult04_br<=din1_r4; mult04_ar<=dout_ram04_r; mult05_br<=din1_r4; mult05_ar<=dout_ram05_r;
                        mult06_br<=din1_r4; mult06_ar<=dout_ram06_r; mult07_br<=din1_r4; mult07_ar<=dout_ram07_r;
                        mult08_br<=din1_r4; mult08_ar<=dout_ram08_r; mult09_br<=din1_r4; mult09_ar<=dout_ram09_r;
                        mult10_br<=din1_r4; mult10_ar<=dout_ram10_r; mult11_br<=din1_r4; mult11_ar<=dout_ram11_r;
                    end
                    4'd2:       begin//计算u*w(共轭转置)   (36Q27,36Q27)*(24Q13,24Q13)-->(61Q40,61Q40)
                        mul_state<=mul_state+1'b1;
                        mult00_ar<={-(rls_wt00_I[71:36]),rls_wt00_I[35:0]}; mult00_br<=R0_2I11; mult01_ar<={-(rls_wt01_I[71:36]),rls_wt01_I[35:0]}; mult01_br<=R0_2I10;		
                        mult02_ar<={-(rls_wt02_I[71:36]),rls_wt02_I[35:0]}; mult02_br<=R0_2I09; mult03_ar<={-(rls_wt03_I[71:36]),rls_wt03_I[35:0]}; mult03_br<=R0_2I08;		
                        mult04_ar<={-(rls_wt04_I[71:36]),rls_wt04_I[35:0]}; mult04_br<=R0_2I07; mult05_ar<={-(rls_wt05_I[71:36]),rls_wt05_I[35:0]}; mult05_br<=R0_2I06;		 
                        mult06_ar<={-(rls_wt06_I[71:36]),rls_wt06_I[35:0]}; mult06_br<=R0_2I05; mult07_ar<={-(rls_wt07_I[71:36]),rls_wt07_I[35:0]}; mult07_br<=R0_2I04;		 
                        mult08_ar<={-(rls_wt08_I[71:36]),rls_wt08_I[35:0]}; mult08_br<=R0_2I03; mult09_ar<={-(rls_wt09_I[71:36]),rls_wt09_I[35:0]}; mult09_br<=R0_2I02;		 
                        mult10_ar<={-(rls_wt10_I[71:36]),rls_wt10_I[35:0]}; mult10_br<=R0_2I01; mult11_ar<={-(rls_wt11_I[71:36]),rls_wt11_I[35:0]}; mult11_br<=R0_2I00;
                    end
                    4'd3:       begin//计算A * u(共轭转置) 计算C的一部分     AI00:40Q29-->36Q25  (36Q25,36Q25)*(24Q13,24Q13)-->(61Q38,61Q38)
                        mul_state<=mul_state+1'b1;
                        mult00_ar<={AI00[79:44],AI00[39:4]}; mult00_br<=R1_I11; mult01_ar<={AI01[79:44],AI01[39:4]}; mult01_br<=R1_I10;		 
                        mult02_ar<={AI02[79:44],AI02[39:4]}; mult02_br<=R1_I09; mult03_ar<={AI03[79:44],AI03[39:4]}; mult03_br<=R1_I08;		
                        mult04_ar<={AI04[79:44],AI04[39:4]}; mult04_br<=R1_I07; mult05_ar<={AI05[79:44],AI05[39:4]}; mult05_br<=R1_I06;		 
                        mult06_ar<={AI06[79:44],AI06[39:4]}; mult06_br<=R1_I05; mult07_ar<={AI07[79:44],AI07[39:4]}; mult07_br<=R1_I04;		 
                        mult08_ar<={AI08[79:44],AI08[39:4]}; mult08_br<=R1_I03; mult09_ar<={AI09[79:44],AI09[39:4]}; mult09_br<=R1_I02;		 
                        mult10_ar<={AI10[79:44],AI10[39:4]}; mult10_br<=R1_I01; mult11_ar<={AI11[79:44],AI11[39:4]}; mult11_br<=R1_I00;
                    end
                    4'd4:       begin    //(1/lamda)*u(共轭转置)*P       (36Q29,36Q29)*(24Q13,24Q13)-->(61Q42,61Q42)
                        case(mul_B)
                            6'd0:       begin
                                mul_B<=mul_B+1'b1;
                                mult00_ar<=PI0000;			 mult00_br<=R2_I11;		  mult01_ar<=PI0001;		  	 mult01_br<=R2_I11;		  
                                mult02_ar<=PI0002;		   	 mult02_br<=R2_I11;		  mult03_ar<=PI0003;		   	 mult03_br<=R2_I11;		  
                                mult04_ar<=PI0004;		     mult04_br<=R2_I11;		  mult05_ar<=PI0005;		   	 mult05_br<=R2_I11;		  
                                mult06_ar<=PI0006;		   	 mult06_br<=R2_I11;		  mult07_ar<=PI0007;		   	 mult07_br<=R2_I11;		  
                                mult08_ar<=PI0008;		   	 mult08_br<=R2_I11;		  mult09_ar<=PI0009;		  	 mult09_br<=R2_I11;		  
                                mult10_ar<=PI0010;		   	 mult10_br<=R2_I11;		  mult11_ar<=PI0011;		  	 mult11_br<=R2_I11;
                            end
                            6'd1:       begin
                                mul_B<=mul_B+1'b1;
                                mult00_ar<=PI0100;		     mult00_br<=R2_I10;		  mult01_ar<=PI0101;		  	 mult01_br<=R2_I10;		  
                                mult02_ar<=PI0102;		   	 mult02_br<=R2_I10;		  mult03_ar<=PI0103;		   	 mult03_br<=R2_I10;		  
                                mult04_ar<=PI0104;		     mult04_br<=R2_I10;		  mult05_ar<=PI0105;		   	 mult05_br<=R2_I10;		  
                                mult06_ar<=PI0106;		   	 mult06_br<=R2_I10;		  mult07_ar<=PI0107;		   	 mult07_br<=R2_I10;		  
                                mult08_ar<=PI0108;		   	 mult08_br<=R2_I10;		  mult09_ar<=PI0109;		  	 mult09_br<=R2_I10;		  
                                mult10_ar<=PI0110;		   	 mult10_br<=R2_I10;		  mult11_ar<=PI0111;		  	 mult11_br<=R2_I10;	
                            end
                            6'd2:       begin
                                mul_B<=mul_B+1'b1;
                                mult00_ar<=PI0200;		  	 mult00_br<=R2_I09;		  	mult01_ar<=PI0201;		  	 mult01_br<=R2_I09;		  
                                mult02_ar<=PI0202;		   	 mult02_br<=R2_I09;		  	mult03_ar<=PI0203;		   	 mult03_br<=R2_I09;		  
                                mult04_ar<=PI0204;		     mult04_br<=R2_I09;		  	mult05_ar<=PI0205;		   	 mult05_br<=R2_I09;		  
                                mult06_ar<=PI0206;		   	 mult06_br<=R2_I09;		  	mult07_ar<=PI0207;		   	 mult07_br<=R2_I09;		  
                                mult08_ar<=PI0208;		   	 mult08_br<=R2_I09;		  	mult09_ar<=PI0209;		  	 mult09_br<=R2_I09;		  
                                mult10_ar<=PI0210;		   	 mult10_br<=R2_I09;		  	mult11_ar<=PI0211;		  	 mult11_br<=R2_I09;
                            end
                            6'd3:       begin
                                mul_B<=mul_B+1'b1;
                                mult00_ar<=PI0300;		  	 mult00_br<=R2_I08;		  mult01_ar<=PI0301;		  	 mult01_br<=R2_I08;		  
                                mult02_ar<=PI0302;		   	 mult02_br<=R2_I08;		  mult03_ar<=PI0303;		   	 mult03_br<=R2_I08;		  
                                mult04_ar<=PI0304;		     mult04_br<=R2_I08;		  mult05_ar<=PI0305;		   	 mult05_br<=R2_I08;		  
                                mult06_ar<=PI0306;		   	 mult06_br<=R2_I08;		  mult07_ar<=PI0307;		   	 mult07_br<=R2_I08;		  
                                mult08_ar<=PI0308;		   	 mult08_br<=R2_I08;		  mult09_ar<=PI0309;		  	 mult09_br<=R2_I08;		  
                                mult10_ar<=PI0310;		   	 mult10_br<=R2_I08;		  mult11_ar<=PI0311;		  	 mult11_br<=R2_I08;
                            end
                            6'd4:       begin
                                mul_B<=mul_B+1'b1;
                                mult00_ar<=PI0400;		  	 mult00_br<=R2_I07;		  mult01_ar<=PI0401;		  	 mult01_br<=R2_I07;		  
                                mult02_ar<=PI0402;		     mult02_br<=R2_I07;		  mult03_ar<=PI0403;		   	 mult03_br<=R2_I07;		  
                                mult04_ar<=PI0404;		     mult04_br<=R2_I07;		  mult05_ar<=PI0405;		   	 mult05_br<=R2_I07;		  
                                mult06_ar<=PI0406;		   	 mult06_br<=R2_I07;		  mult07_ar<=PI0407;		   	 mult07_br<=R2_I07;		  
                                mult08_ar<=PI0408;		   	 mult08_br<=R2_I07;		  mult09_ar<=PI0409;		  	 mult09_br<=R2_I07;		  
                                mult10_ar<=PI0410;		   	 mult10_br<=R2_I07;		  mult11_ar<=PI0411;		  	 mult11_br<=R2_I07;		  
							end
                            6'd5:       begin
                                mul_B<=mul_B+1'b1;
                                mult00_ar<=PI0500;		  	 mult00_br<=R2_I06;		  mult01_ar<=PI0501;		  	 mult01_br<=R2_I06;		  
                                mult02_ar<=PI0502;		   	 mult02_br<=R2_I06;		  mult03_ar<=PI0503;		   	 mult03_br<=R2_I06;		  
                                mult04_ar<=PI0504;		     mult04_br<=R2_I06;		  mult05_ar<=PI0505;		   	 mult05_br<=R2_I06;		  
                                mult06_ar<=PI0506;		   	 mult06_br<=R2_I06;	      mult07_ar<=PI0507;		   	 mult07_br<=R2_I06;		  
                                mult08_ar<=PI0508;		   	 mult08_br<=R2_I06;		  mult09_ar<=PI0509;		  	 mult09_br<=R2_I06;		  
                                mult10_ar<=PI0510;		   	 mult10_br<=R2_I06;		  mult11_ar<=PI0511;		  	 mult11_br<=R2_I06;		  
                            end
                            6'd6:       begin
                                mul_B<=mul_B+1'b1;
                                mult00_ar<=PI0600;		  	 mult00_br<=R2_I05;		  mult01_ar<=PI0601;		  	 mult01_br<=R2_I05;		  
                                mult02_ar<=PI0602;		   	 mult02_br<=R2_I05;		  mult03_ar<=PI0603;		   	 mult03_br<=R2_I05;		  
                                mult04_ar<=PI0604;		     mult04_br<=R2_I05;		  mult05_ar<=PI0605;		   	 mult05_br<=R2_I05;		  
                                mult06_ar<=PI0606;		   	 mult06_br<=R2_I05;		  mult07_ar<=PI0607;		   	 mult07_br<=R2_I05;		  
                                mult08_ar<=PI0608;		   	 mult08_br<=R2_I05;		  mult09_ar<=PI0609;		  	 mult09_br<=R2_I05;		  
                                mult10_ar<=PI0610;		   	 mult10_br<=R2_I05;		  mult11_ar<=PI0611;		  	 mult11_br<=R2_I05;		  		  
                            end
                            6'd7:       begin
                                mul_B<=mul_B+1'b1;
                                mult00_ar<=PI0700;			 mult00_br<=R2_I04;		  mult01_ar<=PI0701;			 mult01_br<=R2_I04;		  
                                mult02_ar<=PI0702;		 	 mult02_br<=R2_I04;		  mult03_ar<=PI0703;		 	 mult03_br<=R2_I04;		  
                                mult04_ar<=PI0704;		     mult04_br<=R2_I04;		  mult05_ar<=PI0705;		 	 mult05_br<=R2_I04;		  
                                mult06_ar<=PI0706;		 	 mult06_br<=R2_I04;		  mult07_ar<=PI0707;		 	 mult07_br<=R2_I04;		  
                                mult08_ar<=PI0708;		 	 mult08_br<=R2_I04;		  mult09_ar<=PI0709;			 mult09_br<=R2_I04;		  
                                mult10_ar<=PI0710;		 	 mult10_br<=R2_I04;		  mult11_ar<=PI0711;			 mult11_br<=R2_I04;		  
                            end
                            6'd8:       begin
                                mul_B<=mul_B+1'b1;
                                mult00_ar<=PI0800;			 mult00_br<=R2_I03;		  mult01_ar<=PI0801;			 mult01_br<=R2_I03;		  
                                mult02_ar<=PI0802;		 	 mult02_br<=R2_I03;		  mult03_ar<=PI0803;		 	 mult03_br<=R2_I03;		  
                                mult04_ar<=PI0804;		     mult04_br<=R2_I03;		  mult05_ar<=PI0805;		 	 mult05_br<=R2_I03;		  
                                mult06_ar<=PI0806;		 	 mult06_br<=R2_I03;		  mult07_ar<=PI0807;		 	 mult07_br<=R2_I03;		  
                                mult08_ar<=PI0808;		 	 mult08_br<=R2_I03;		  mult09_ar<=PI0809;			 mult09_br<=R2_I03;		  
                                mult10_ar<=PI0810;		 	 mult10_br<=R2_I03;		  mult11_ar<=PI0811;			 mult11_br<=R2_I03;		  
                            end
                            6'd9:       begin
                                mul_B<=mul_B+1'b1;
                                mult00_ar<=PI0900;			 mult00_br<=R2_I02;		  mult01_ar<=PI0901;			 mult01_br<=R2_I02;		  
                                mult02_ar<=PI0902;		 	 mult02_br<=R2_I02;		  mult03_ar<=PI0903;		 	 mult03_br<=R2_I02;		  
                                mult04_ar<=PI0904;		     mult04_br<=R2_I02;		  mult05_ar<=PI0905;		 	 mult05_br<=R2_I02;		  
                                mult06_ar<=PI0906;		 	 mult06_br<=R2_I02;		  mult07_ar<=PI0907;		 	 mult07_br<=R2_I02;		  
                                mult08_ar<=PI0908;		 	 mult08_br<=R2_I02;		  mult09_ar<=PI0909;			 mult09_br<=R2_I02;		  
                                mult10_ar<=PI0910;		 	 mult10_br<=R2_I02;		  mult11_ar<=PI0911;			 mult11_br<=R2_I02;		  		  	
                            end
                            6'd10:      begin
                                mul_B<=mul_B+1'b1;
                                mult00_ar<=PI1000;			 mult00_br<=R2_I01;		  mult01_ar<=PI1001;		     mult01_br<=R2_I01;		  
                                mult02_ar<=PI1002;		 	 mult02_br<=R2_I01;		  mult03_ar<=PI1003;		 	 mult03_br<=R2_I01;		  
                                mult04_ar<=PI1004;		     mult04_br<=R2_I01;		  mult05_ar<=PI1005;		 	 mult05_br<=R2_I01;		  
                                mult06_ar<=PI1006;		 	 mult06_br<=R2_I01;		  mult07_ar<=PI1007;		 	 mult07_br<=R2_I01;		  
                                mult08_ar<=PI1008;		   	 mult08_br<=R2_I01;		  mult09_ar<=PI1009;			 mult09_br<=R2_I01;		  
                                mult10_ar<=PI1010;		 	 mult10_br<=R2_I01;		  mult11_ar<=PI1011;			 mult11_br<=R2_I01;		  
                            end
                            default:    begin
                                    if(cnt_clk==91)	begin
                                        mul_B		<=0;
                                        mul_state   <=4'd5;
                                    end
                                    else	begin
                                    end
                                    mult00_ar<=PI1100;			 mult00_br<=R2_I00;		  mult01_ar<=PI1101;				 mult01_br<=R2_I00;		  
                                    mult02_ar<=PI1102;		 	 mult02_br<=R2_I00;		  mult03_ar<=PI1103;		 		 mult03_br<=R2_I00;		  
                                    mult04_ar<=PI1104;		     mult04_br<=R2_I00;		  mult05_ar<=PI1105;		 		 mult05_br<=R2_I00;		  
                                    mult06_ar<=PI1106;		 	 mult06_br<=R2_I00;		  mult07_ar<=PI1107;		 		 mult07_br<=R2_I00;		  
                                    mult08_ar<=PI1108;		 	 mult08_br<=R2_I00;		  mult09_ar<=PI1109;				 mult09_br<=R2_I00;		  
                                    mult10_ar<=PI1110;		 	 mult10_br<=R2_I00;		  mult11_ar<=PI1111;				 mult11_br<=R2_I00;		  	  	
                                end
                        endcase
                    end
                    4'd5:	begin //计算增益矢量A'      AI00:40Q29-->36Q28      (36Q28,36Q28)*(24Q20,24Q20)-->(61Q48,61Q48)
                        mul_state<=mul_state+1'b1;
                        mult00_br<=D_I;         mult00_ar<={AI00[76:41],AI00[36:1]};       mult01_br<=D_I;         mult01_ar<={AI01[76:41],AI01[36:1]};       	
                        mult02_br<=D_I;         mult02_ar<={AI02[76:41],AI02[36:1]};       mult03_br<=D_I;         mult03_ar<={AI03[76:41],AI03[36:1]};       
                        mult04_br<=D_I;         mult04_ar<={AI04[76:41],AI04[36:1]};       mult05_br<=D_I;         mult05_ar<={AI05[76:41],AI05[36:1]};        
                        mult06_br<=D_I;         mult06_ar<={AI06[76:41],AI06[36:1]};       mult07_br<=D_I;         mult07_ar<={AI07[76:41],AI07[36:1]};   
                        mult08_br<=D_I;         mult08_ar<={AI08[76:41],AI08[36:1]};       mult09_br<=D_I;         mult09_ar<={AI09[76:41],AI09[36:1]};         	
                        mult10_br<=D_I;         mult10_ar<={AI10[76:41],AI10[36:1]};       mult11_br<=D_I;         mult11_ar<={AI11[76:41],AI11[36:1]};     	        
			        end
                    4'd6:	begin   //P'=P * 1/lamda        (36Q29,36Q29)*(24Q22,24Q22)-->(61Q51,61Q51)
                            if(mul_P==pack_len-1)	begin
                                mul_P<=0;
                                mul_state<=4'd7;
                            end
                            else	begin
                                mul_P<=mul_P+1'b1;
                            end
                            mult00_br<={24'sd0,24'sd4194752}; mult00_ar<={dout_ram00_r[71:36],dout_ram00_r[35:0]}; mult01_br<={24'sd0,24'sd4194752}; mult01_ar<={dout_ram01_r[71:36],dout_ram01_r[35:0]};        	
                            mult02_br<={24'sd0,24'sd4194752}; mult02_ar<={dout_ram02_r[71:36],dout_ram02_r[35:0]}; mult03_br<={24'sd0,24'sd4194752}; mult03_ar<={dout_ram03_r[71:36],dout_ram03_r[35:0]};          
                            mult04_br<={24'sd0,24'sd4194752}; mult04_ar<={dout_ram04_r[71:36],dout_ram04_r[35:0]}; mult05_br<={24'sd0,24'sd4194752}; mult05_ar<={dout_ram05_r[71:36],dout_ram05_r[35:0]};          
                            mult06_br<={24'sd0,24'sd4194752}; mult06_ar<={dout_ram06_r[71:36],dout_ram06_r[35:0]}; mult07_br<={24'sd0,24'sd4194752}; mult07_ar<={dout_ram07_r[71:36],dout_ram07_r[35:0]};       
                            mult08_br<={24'sd0,24'sd4194752}; mult08_ar<={dout_ram08_r[71:36],dout_ram08_r[35:0]}; mult09_br<={24'sd0,24'sd4194752}; mult09_ar<={dout_ram09_r[71:36],dout_ram09_r[35:0]};          	
                            mult10_br<={24'sd0,24'sd4194752}; mult10_ar<={dout_ram10_r[71:36],dout_ram10_r[35:0]}; mult11_br<={24'sd0,24'sd4194752}; mult11_ar<={dout_ram11_r[71:36],dout_ram11_r[35:0]};         	         
                        end
                    4'd7: //用于求A' * B,用于计算p的中间变量        (36Q28,36Q28)*(24Q20,24Q20)-->(61Q48,61Q48)
                        begin                                       //B(40Q30,40Q30)-->(36Q28,36Q28)
                            case(mul_AB)
                                6'd0:
                                    begin
                                        mul_AB<=mul_AB+1'b1;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI00[77:42],BI00[37:2]};		 	mult01_br<=A1I01;		 	mult01_ar<={BI00[77:42],BI00[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI00[77:42],BI00[37:2]};		 	mult03_br<=A1I03;		  	mult03_ar<={BI00[77:42],BI00[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI00[77:42],BI00[37:2]};		 	mult05_br<=A1I05;		  	mult05_ar<={BI00[77:42],BI00[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI00[77:42],BI00[37:2]};		 	mult07_br<=A1I07;		  	mult07_ar<={BI00[77:42],BI00[37:2]};		 
                                        mult08_br<=A1I08;		       mult08_ar<={BI00[77:42],BI00[37:2]};		 	mult09_br<=A1I09;		 	mult09_ar<={BI00[77:42],BI00[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI00[77:42],BI00[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI00[77:42],BI00[37:2]};		 	 
                                    end
                                6'd1:
                                    begin
                                        mul_AB<=mul_AB+1'b1;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI01[77:42],BI01[37:2]};		    mult01_br<=A1I01;		 	mult01_ar<={BI01[77:42],BI01[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI01[77:42],BI01[37:2]};		    mult03_br<=A1I03;		  	mult03_ar<={BI01[77:42],BI01[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI01[77:42],BI01[37:2]};		    mult05_br<=A1I05;		  	mult05_ar<={BI01[77:42],BI01[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI01[77:42],BI01[37:2]};		    mult07_br<=A1I07;		  	mult07_ar<={BI01[77:42],BI01[37:2]};		 
                                        mult08_br<=A1I08;		  	   mult08_ar<={BI01[77:42],BI01[37:2]};		    mult09_br<=A1I09;		 	mult09_ar<={BI01[77:42],BI01[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI01[77:42],BI01[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI01[77:42],BI01[37:2]};		 
                                    end
                                6'd2:
                                    begin
                                        mul_AB<=mul_AB+1'b1;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI02[77:42],BI02[37:2]};		    mult01_br<=A1I01;		 	mult01_ar<={BI02[77:42],BI02[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI02[77:42],BI02[37:2]};		    mult03_br<=A1I03;		  	mult03_ar<={BI02[77:42],BI02[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI02[77:42],BI02[37:2]};		    mult05_br<=A1I05;		  	mult05_ar<={BI02[77:42],BI02[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI02[77:42],BI02[37:2]};		    mult07_br<=A1I07;		  	mult07_ar<={BI02[77:42],BI02[37:2]};		 
                                        mult08_br<=A1I08;		  	   mult08_ar<={BI02[77:42],BI02[37:2]};		    mult09_br<=A1I09;		 	mult09_ar<={BI02[77:42],BI02[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI02[77:42],BI02[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI02[77:42],BI02[37:2]};		 
                                    end
                                6'd3:
                                    begin
                                        mul_AB<=mul_AB+1'b1;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI03[77:42],BI03[37:2]};		    mult01_br<=A1I01;		 	mult01_ar<={BI03[77:42],BI03[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI03[77:42],BI03[37:2]};		    mult03_br<=A1I03;		  	mult03_ar<={BI03[77:42],BI03[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI03[77:42],BI03[37:2]};		    mult05_br<=A1I05;		  	mult05_ar<={BI03[77:42],BI03[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI03[77:42],BI03[37:2]};		    mult07_br<=A1I07;		  	mult07_ar<={BI03[77:42],BI03[37:2]};		 
                                        mult08_br<=A1I08;		  	   mult08_ar<={BI03[77:42],BI03[37:2]};		    mult09_br<=A1I09;		 	mult09_ar<={BI03[77:42],BI03[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI03[77:42],BI03[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI03[77:42],BI03[37:2]};		 	 
                                    end
                                6'd4:
                                    begin
                                        mul_AB<=mul_AB+1'b1;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI04[77:42],BI04[37:2]};		    mult01_br<=A1I01;		 	mult01_ar<={BI04[77:42],BI04[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI04[77:42],BI04[37:2]};		    mult03_br<=A1I03;		  	mult03_ar<={BI04[77:42],BI04[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI04[77:42],BI04[37:2]};		    mult05_br<=A1I05;		  	mult05_ar<={BI04[77:42],BI04[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI04[77:42],BI04[37:2]};		    mult07_br<=A1I07;		  	mult07_ar<={BI04[77:42],BI04[37:2]};		 
                                        mult08_br<=A1I08;		  	   mult08_ar<={BI04[77:42],BI04[37:2]};		    mult09_br<=A1I09;		 	mult09_ar<={BI04[77:42],BI04[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI04[77:42],BI04[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI04[77:42],BI04[37:2]};		 
                                    end
                                6'd5:
                                    begin
                                        mul_AB<=mul_AB+1'b1;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI05[77:42],BI05[37:2]};		    mult01_br<=A1I01;		 	mult01_ar<={BI05[77:42],BI05[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI05[77:42],BI05[37:2]};		    mult03_br<=A1I03;		  	mult03_ar<={BI05[77:42],BI05[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI05[77:42],BI05[37:2]};		    mult05_br<=A1I05;		  	mult05_ar<={BI05[77:42],BI05[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI05[77:42],BI05[37:2]};		    mult07_br<=A1I07;		  	mult07_ar<={BI05[77:42],BI05[37:2]};		 
                                        mult08_br<=A1I08;		  	   mult08_ar<={BI05[77:42],BI05[37:2]};		    mult09_br<=A1I09;		 	mult09_ar<={BI05[77:42],BI05[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI05[77:42],BI05[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI05[77:42],BI05[37:2]};		 		 
                                    end
                                6'd6:
                                    begin
                                        mul_AB<=mul_AB+1'b1;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI06[77:42],BI06[37:2]};		    mult01_br<=A1I01;		 	mult01_ar<={BI06[77:42],BI06[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI06[77:42],BI06[37:2]};		    mult03_br<=A1I03;		  	mult03_ar<={BI06[77:42],BI06[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI06[77:42],BI06[37:2]};		    mult05_br<=A1I05;		  	mult05_ar<={BI06[77:42],BI06[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI06[77:42],BI06[37:2]};		    mult07_br<=A1I07;		  	mult07_ar<={BI06[77:42],BI06[37:2]};		 
                                        mult08_br<=A1I08;		  	   mult08_ar<={BI06[77:42],BI06[37:2]};		    mult09_br<=A1I09;		 	mult09_ar<={BI06[77:42],BI06[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI06[77:42],BI06[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI06[77:42],BI06[37:2]};		 	 
                                    end
                                6'd7:
                                    begin
                                        mul_AB<=mul_AB+1'b1;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI07[77:42],BI07[37:2]};		    mult01_br<=A1I01;		 	mult01_ar<={BI07[77:42],BI07[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI07[77:42],BI07[37:2]};		    mult03_br<=A1I03;		  	mult03_ar<={BI07[77:42],BI07[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI07[77:42],BI07[37:2]};		    mult05_br<=A1I05;		  	mult05_ar<={BI07[77:42],BI07[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI07[77:42],BI07[37:2]};		    mult07_br<=A1I07;		  	mult07_ar<={BI07[77:42],BI07[37:2]};		 
                                        mult08_br<=A1I08;		  	   mult08_ar<={BI07[77:42],BI07[37:2]};		    mult09_br<=A1I09;		 	mult09_ar<={BI07[77:42],BI07[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI07[77:42],BI07[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI07[77:42],BI07[37:2]};		 
                                    end
                                6'd8:
                                    begin
                                        mul_AB<=mul_AB+1'b1;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI08[77:42],BI08[37:2]};		    mult01_br<=A1I01;		 	mult01_ar<={BI08[77:42],BI08[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI08[77:42],BI08[37:2]};		    mult03_br<=A1I03;		  	mult03_ar<={BI08[77:42],BI08[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI08[77:42],BI08[37:2]};		    mult05_br<=A1I05;		  	mult05_ar<={BI08[77:42],BI08[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI08[77:42],BI08[37:2]};		    mult07_br<=A1I07;		  	mult07_ar<={BI08[77:42],BI08[37:2]};		 
                                        mult08_br<=A1I08;		  	   mult08_ar<={BI08[77:42],BI08[37:2]};		    mult09_br<=A1I09;		 	mult09_ar<={BI08[77:42],BI08[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI08[77:42],BI08[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI08[77:42],BI08[37:2]};		 	 
                                    end
                                6'd9:
                                    begin
                                        mul_AB<=mul_AB+1'b1;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI09[77:42],BI09[37:2]};		    mult01_br<=A1I01;		 	mult01_ar<={BI09[77:42],BI09[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI09[77:42],BI09[37:2]};		    mult03_br<=A1I03;		  	mult03_ar<={BI09[77:42],BI09[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI09[77:42],BI09[37:2]};		    mult05_br<=A1I05;		  	mult05_ar<={BI09[77:42],BI09[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI09[77:42],BI09[37:2]};		    mult07_br<=A1I07;		  	mult07_ar<={BI09[77:42],BI09[37:2]};		 
                                        mult08_br<=A1I08;		  	   mult08_ar<={BI09[77:42],BI09[37:2]};		    mult09_br<=A1I09;		 	mult09_ar<={BI09[77:42],BI09[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI09[77:42],BI09[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI09[77:42],BI09[37:2]};		 
                                    end
                                6'd10:
                                    begin
                                        mul_AB<=mul_AB+1'b1;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI10[77:42],BI10[37:2]};		    mult01_br<=A1I01;		 	mult01_ar<={BI10[77:42],BI10[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI10[77:42],BI10[37:2]};		    mult03_br<=A1I03;		  	mult03_ar<={BI10[77:42],BI10[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI10[77:42],BI10[37:2]};		    mult05_br<=A1I05;		  	mult05_ar<={BI10[77:42],BI10[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI10[77:42],BI10[37:2]};		    mult07_br<=A1I07;		  	mult07_ar<={BI10[77:42],BI10[37:2]};		 
                                        mult08_br<=A1I08;		  	   mult08_ar<={BI10[77:42],BI10[37:2]};		    mult09_br<=A1I09;		 	mult09_ar<={BI10[77:42],BI10[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI10[77:42],BI10[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI10[77:42],BI10[37:2]};		 
                                    end
                                default:
                                    begin
                                        mul_AB<=0;
                                        mul_state<=4'd8;
                                        mult00_br<=A1I00;		 	   mult00_ar<={BI11[77:42],BI11[37:2]};		    mult01_br<=A1I01;		 	mult01_ar<={BI11[77:42],BI11[37:2]};		 
                                        mult02_br<=A1I02;		  	   mult02_ar<={BI11[77:42],BI11[37:2]};		    mult03_br<=A1I03;		  	mult03_ar<={BI11[77:42],BI11[37:2]};		 
                                        mult04_br<=A1I04;		       mult04_ar<={BI11[77:42],BI11[37:2]};		    mult05_br<=A1I05;		  	mult05_ar<={BI11[77:42],BI11[37:2]};		 
                                        mult06_br<=A1I06;		  	   mult06_ar<={BI11[77:42],BI11[37:2]};		    mult07_br<=A1I07;		  	mult07_ar<={BI11[77:42],BI11[37:2]};		 
                                        mult08_br<=A1I08;		  	   mult08_ar<={BI11[77:42],BI11[37:2]};		    mult09_br<=A1I09;		 	mult09_ar<={BI11[77:42],BI11[37:2]};		 
                                        mult10_br<=A1I10;		  	   mult10_ar<={BI11[77:42],BI11[37:2]};		    mult11_br<=A1I11;		 	mult11_ar<={BI11[77:42],BI11[37:2]};		 
                                    end
                            endcase
                        end
                    4'd8:		begin //计算 A'*(d-u*w(k-1)) 是计算w(k)的中间变量       (36Q25,36Q25)*(24Q20,24Q20)-->(61Q45,61Q45)
                            mul_state<=4'd0;
                            mult00_br<=A1I00;				mult00_ar<={-(Err_I[71:36]),Err_I[35:0]};		 mult01_br<=A1I01;		 		mult01_ar<={-(Err_I[71:36]),Err_I[35:0]};		 
                            mult02_br<=A1I02;		  	 	mult02_ar<={-(Err_I[71:36]),Err_I[35:0]};		 mult03_br<=A1I03;		 	 	mult03_ar<={-(Err_I[71:36]),Err_I[35:0]};		 
                            mult04_br<=A1I04;		     	mult04_ar<={-(Err_I[71:36]),Err_I[35:0]};		 mult05_br<=A1I05;		  	 	mult05_ar<={-(Err_I[71:36]),Err_I[35:0]};		 
                            mult06_br<=A1I06;		 	 	mult06_ar<={-(Err_I[71:36]),Err_I[35:0]};		 mult07_br<=A1I07;		  	 	mult07_ar<={-(Err_I[71:36]),Err_I[35:0]};		 
                            mult08_br<=A1I08;		  		mult08_ar<={-(Err_I[71:36]),Err_I[35:0]};		 mult09_br<=A1I09;				mult09_ar<={-(Err_I[71:36]),Err_I[35:0]};		 
                            mult10_br<=A1I10;			 	mult10_ar<={-(Err_I[71:36]),Err_I[35:0]};		 mult11_br<=A1I11;				mult11_ar<={-(Err_I[71:36]),Err_I[35:0]};		 
                            end
            endcase
        end
    end




    //test code迭代次数
	output  reg [19:0] cnt;
	always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cnt <= 20'b0;
        end
        else begin
            if(wt_pulse) begin
                cnt <= cnt + 1'b1;
            end
            else begin  end
        end
    end


endmodule
