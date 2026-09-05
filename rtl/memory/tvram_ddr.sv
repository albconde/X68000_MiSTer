module tvram_ddr (
	input  logic        rclk,
	input  logic        vclk,
	input  logic        ram_ce,
	input  logic        rst_n,

	input  logic [17:0] cpu_addr,
	input  logic [15:0] cpu_wdat,
	input  logic        cpu_rd,
	input  logic [1:0]  cpu_wr,
	input  logic [1:0]  cpu_rmw,
	input  logic [15:0] cpu_rmwmask,
	output logic [15:0] cpu_rdat,
	output logic        cpu_ack,

	input  logic [16:0] cpy_src,
	input  logic [16:0] cpy_dst,
	input  logic [3:0]  cpy_plane,
	input  logic        cpy_req,
	output logic        cpy_ack,

	input  logic [21:0] t0_addr,
	input  logic        t0_rd,
	output logic [15:0] t0_rdat0,
	output logic [15:0] t0_rdat1,
	output logic [15:0] t0_rdat2,
	output logic [15:0] t0_rdat3,
	input  logic [21:0] t1_addr,
	input  logic        t1_rd,
	output logic [15:0] t1_rdat0,
	output logic [15:0] t1_rdat1,
	output logic [15:0] t1_rdat2,
	output logic [15:0] t1_rdat3,

	output logic        DDRAM_CLK,
	output logic [7:0]  DDRAM_BURSTCNT,
	output logic [28:0] DDRAM_ADDR,
	output logic [63:0] DDRAM_DIN,
	output logic [7:0]  DDRAM_BE,
	output logic        DDRAM_RD,
	output logic        DDRAM_WE,
	input  logic [63:0] DDRAM_DOUT,
	input  logic        DDRAM_DOUT_READY,
	input  logic        DDRAM_BUSY
);

	localparam logic [28:0] DDR_BASE = 29'h06000000;

	typedef enum logic [3:0] {
		S_RESET,
		S_IDLE,
		S_VID_CMD,
		S_VID_DATA,
		S_CPU_RD_CMD,
		S_CPU_RD_DATA,
		S_CPU_WR_CMD,
		S_CPU_RMW_RD_CMD,
		S_CPU_RMW_RD_DATA,
		S_CPU_RMW_WR_CMD,
		S_CPY_RD_CMD,
		S_CPY_RD_DATA,
		S_CPY_WR_CMD
	} state_t;

	state_t state = S_RESET;

	logic rst_s0 = 1'b0;
	logic rst_s  = 1'b0;
	logic [7:0] reset_drain = 8'd0;

	logic [15:0] t0_tag = 16'hffff;
	logic [15:0] t1_tag = 16'hffff;
	logic        t0_valid = 1'b0;
	logic        t1_valid = 1'b0;
	logic        fill_t0 = 1'b0;
	logic        fill_t1 = 1'b0;
	logic [5:0]  fill_count = 6'd0;

	wire t0_miss = t0_rd && (!t0_valid || t0_tag != t0_addr[21:6]);
	wire t1_miss = t1_rd && (!t1_valid || t1_tag != t1_addr[21:6]);

	wire fill_we0 = (state == S_VID_DATA) && DDRAM_DOUT_READY && fill_t0 && ram_ce;
	wire fill_we1 = (state == S_VID_DATA) && DDRAM_DOUT_READY && fill_t1 && ram_ce;

	CACHEMEMWN #(.awidth(6), .ramtype("MLAB")) T00Rcache (
		.data(DDRAM_DOUT[15:0]),  .rdaddress(t0_addr[5:0]), .rdclock(vclk),
		.wraddress(fill_count), .wrclock(rclk), .wren(fill_we0), .q(t0_rdat0));
	CACHEMEMWN #(.awidth(6), .ramtype("MLAB")) T01Rcache (
		.data(DDRAM_DOUT[31:16]), .rdaddress(t0_addr[5:0]), .rdclock(vclk),
		.wraddress(fill_count), .wrclock(rclk), .wren(fill_we0), .q(t0_rdat1));
	CACHEMEMWN #(.awidth(6), .ramtype("MLAB")) T02Rcache (
		.data(DDRAM_DOUT[47:32]), .rdaddress(t0_addr[5:0]), .rdclock(vclk),
		.wraddress(fill_count), .wrclock(rclk), .wren(fill_we0), .q(t0_rdat2));
	CACHEMEMWN #(.awidth(6), .ramtype("MLAB")) T03Rcache (
		.data(DDRAM_DOUT[63:48]), .rdaddress(t0_addr[5:0]), .rdclock(vclk),
		.wraddress(fill_count), .wrclock(rclk), .wren(fill_we0), .q(t0_rdat3));

	CACHEMEMWN #(.awidth(6), .ramtype("MLAB")) T10Rcache (
		.data(DDRAM_DOUT[15:0]),  .rdaddress(t1_addr[5:0]), .rdclock(vclk),
		.wraddress(fill_count), .wrclock(rclk), .wren(fill_we1), .q(t1_rdat0));
	CACHEMEMWN #(.awidth(6), .ramtype("MLAB")) T11Rcache (
		.data(DDRAM_DOUT[31:16]), .rdaddress(t1_addr[5:0]), .rdclock(vclk),
		.wraddress(fill_count), .wrclock(rclk), .wren(fill_we1), .q(t1_rdat1));
	CACHEMEMWN #(.awidth(6), .ramtype("MLAB")) T12Rcache (
		.data(DDRAM_DOUT[47:32]), .rdaddress(t1_addr[5:0]), .rdclock(vclk),
		.wraddress(fill_count), .wrclock(rclk), .wren(fill_we1), .q(t1_rdat2));
	CACHEMEMWN #(.awidth(6), .ramtype("MLAB")) T13Rcache (
		.data(DDRAM_DOUT[63:48]), .rdaddress(t1_addr[5:0]), .rdclock(vclk),
		.wraddress(fill_count), .wrclock(rclk), .wren(fill_we1), .q(t1_rdat3));

	logic        cpu_done = 1'b0;
	logic [1:0]  cpu_lane = 2'd0;
	logic [15:0] cpu_wdat_l = 16'd0;
	logic [15:0] cpu_mask_l = 16'd0;
	logic [1:0]  cpu_be_l = 2'd0;
	logic [15:0] rmw_result = 16'd0;

	wire cpu_req = cpu_rd || (|cpu_wr) || (|cpu_rmw);
	assign cpu_ack = cpu_done && cpu_req;

	function automatic logic [15:0] select_word(
		input logic [63:0] qword,
		input logic [1:0] lane
	);
		case (lane)
			2'd0: select_word = qword[15:0];
			2'd1: select_word = qword[31:16];
			2'd2: select_word = qword[47:32];
			default: select_word = qword[63:48];
		endcase
	endfunction

	function automatic logic [7:0] lane_be(
		input logic [1:0] lane,
		input logic [1:0] be
	);
		case (lane)
			2'd0: lane_be = {6'd0, be[1], be[0]};
			2'd1: lane_be = {4'd0, be[1], be[0], 2'd0};
			2'd2: lane_be = {2'd0, be[1], be[0], 4'd0};
			default: lane_be = {be[1], be[0], 6'd0};
		endcase
	endfunction

	logic cpy_seen = 1'b0;
	logic cpy_pending = 1'b0;
	logic [10:0] cpy_src_l = 11'd0;
	logic [10:0] cpy_dst_l = 11'd0;
	logic [3:0]  cpy_plane_l = 4'd0;
	logic [5:0]  cpy_count = 6'd0;

	(* ramstyle = "MLAB, no_rw_check" *) logic [63:0] cpy_buffer [0:31];

	function automatic logic [7:0] plane_be(input logic [3:0] plane);
		plane_be = {{2{plane[3]}}, {2{plane[2]}},
		            {2{plane[1]}}, {2{plane[0]}}};
	endfunction

	assign DDRAM_CLK = rclk;

	always_ff @(posedge rclk) begin
		rst_s0 <= rst_n;
		rst_s  <= rst_s0;

		if (!rst_s) begin
			state          <= S_RESET;
			reset_drain    <= 8'd0;
			DDRAM_BURSTCNT <= 8'd1;
			DDRAM_ADDR     <= DDR_BASE;
			DDRAM_DIN      <= 64'd0;
			DDRAM_BE       <= 8'd0;
			DDRAM_RD       <= 1'b0;
			DDRAM_WE       <= 1'b0;
			t0_valid       <= 1'b0;
			t1_valid       <= 1'b0;
			cpu_done       <= 1'b0;
			cpy_seen       <= 1'b0;
			cpy_pending    <= 1'b0;
			cpy_ack        <= 1'b0;
		end else begin
			if (!cpy_req)
				cpy_seen <= 1'b0;
			else if (!cpy_seen) begin
				cpy_seen    <= 1'b1;
				cpy_pending <= 1'b1;
				cpy_src_l   <= cpy_src[10:0];
				cpy_dst_l   <= cpy_dst[10:0];
				cpy_plane_l <= cpy_plane;
			end

			if (!cpu_req)
				cpu_done <= 1'b0;

			case (state)
			S_RESET: begin
				DDRAM_RD <= 1'b0;
				DDRAM_WE <= 1'b0;
				if (!DDRAM_BUSY) begin
					reset_drain <= reset_drain + 1'd1;
					if (reset_drain == 8'hff)
						state <= S_IDLE;
				end
			end

			S_IDLE: begin
				DDRAM_RD <= 1'b0;
				DDRAM_WE <= 1'b0;

				if (t0_miss) begin
					t0_tag         <= t0_addr[21:6];
					t0_valid       <= 1'b0;
					fill_t0        <= 1'b1;
					fill_t1        <= t1_miss && (t1_addr[21:6] == t0_addr[21:6]);
					if (t1_miss && (t1_addr[21:6] == t0_addr[21:6])) begin
						t1_tag   <= t0_addr[21:6];
						t1_valid <= 1'b0;
					end
					fill_count      <= 6'd0;
					DDRAM_ADDR      <= DDR_BASE | {13'd0, t0_addr[15:6], 6'd0};
					DDRAM_BURSTCNT  <= 8'd64;
					DDRAM_BE        <= 8'hff;
					DDRAM_RD        <= 1'b1;
					state            <= S_VID_CMD;
				end else if (t1_miss) begin
					t1_tag         <= t1_addr[21:6];
					t1_valid       <= 1'b0;
					fill_t0        <= 1'b0;
					fill_t1        <= 1'b1;
					fill_count     <= 6'd0;
					DDRAM_ADDR     <= DDR_BASE | {13'd0, t1_addr[15:6], 6'd0};
					DDRAM_BURSTCNT <= 8'd64;
					DDRAM_BE       <= 8'hff;
					DDRAM_RD       <= 1'b1;
					state           <= S_VID_CMD;
				end else if (cpy_pending) begin
					cpy_pending    <= 1'b0;
					cpy_count      <= 6'd0;
					DDRAM_ADDR     <= DDR_BASE | {13'd0, cpy_src_l, 5'd0};
					DDRAM_BURSTCNT <= 8'd32;
					DDRAM_BE       <= 8'hff;
					DDRAM_RD       <= 1'b1;
					state           <= S_CPY_RD_CMD;
					if (t0_valid && t0_tag[9:0] == cpy_dst_l[10:1]) t0_valid <= 1'b0;
					if (t1_valid && t1_tag[9:0] == cpy_dst_l[10:1]) t1_valid <= 1'b0;
				end else if (!cpu_done && (|cpu_rmw)) begin
					cpu_lane       <= cpu_addr[1:0];
					cpu_wdat_l     <= cpu_wdat;
					cpu_mask_l     <= cpu_rmwmask;
					cpu_be_l       <= cpu_rmw;
					DDRAM_ADDR     <= DDR_BASE | {13'd0, cpu_addr[17:2]};
					DDRAM_BURSTCNT <= 8'd1;
					DDRAM_BE       <= 8'hff;
					DDRAM_RD       <= 1'b1;
					state           <= S_CPU_RMW_RD_CMD;
				end else if (!cpu_done && cpu_rd) begin
					cpu_lane       <= cpu_addr[1:0];
					DDRAM_ADDR     <= DDR_BASE | {13'd0, cpu_addr[17:2]};
					DDRAM_BURSTCNT <= 8'd1;
					DDRAM_BE       <= 8'hff;
					DDRAM_RD       <= 1'b1;
					state           <= S_CPU_RD_CMD;
				end else if (!cpu_done && (|cpu_wr)) begin
					cpu_lane       <= cpu_addr[1:0];
					cpu_wdat_l     <= cpu_wdat;
					cpu_be_l       <= cpu_wr;
					DDRAM_ADDR     <= DDR_BASE | {13'd0, cpu_addr[17:2]};
					DDRAM_BURSTCNT <= 8'd1;
					state           <= S_CPU_WR_CMD;
					if (t0_valid && t0_tag[9:0] == cpu_addr[17:8]) t0_valid <= 1'b0;
					if (t1_valid && t1_tag[9:0] == cpu_addr[17:8]) t1_valid <= 1'b0;
				end
			end

			S_VID_CMD: begin
				if (!DDRAM_BUSY) begin
					DDRAM_RD <= 1'b0;
					state    <= S_VID_DATA;
				end
			end

			S_VID_DATA: begin
				if (DDRAM_DOUT_READY) begin
					fill_count <= fill_count + 1'd1;
					if (fill_count == 6'd63) begin
						if (fill_t0) t0_valid <= 1'b1;
						if (fill_t1) t1_valid <= 1'b1;
						state <= S_IDLE;
					end
				end
			end

			S_CPU_RD_CMD: begin
				if (!DDRAM_BUSY) begin
					DDRAM_RD <= 1'b0;
					state    <= S_CPU_RD_DATA;
				end
			end

			S_CPU_RD_DATA: begin
				if (DDRAM_DOUT_READY) begin
					cpu_rdat <= select_word(DDRAM_DOUT, cpu_lane);
					cpu_done <= 1'b1;
					state    <= S_IDLE;
				end
			end

			S_CPU_WR_CMD: begin
				if (!DDRAM_WE) begin
					DDRAM_DIN <= {4{cpu_wdat_l}};
					DDRAM_BE  <= lane_be(cpu_lane, cpu_be_l);
					DDRAM_WE  <= 1'b1;
				end else if (!DDRAM_BUSY) begin
					DDRAM_WE <= 1'b0;
					cpu_done <= 1'b1;
					state    <= S_IDLE;
				end
			end

			S_CPU_RMW_RD_CMD: begin
				if (!DDRAM_BUSY) begin
					DDRAM_RD <= 1'b0;
					state    <= S_CPU_RMW_RD_DATA;
				end
			end

			S_CPU_RMW_RD_DATA: begin
				if (DDRAM_DOUT_READY) begin
					rmw_result <= (select_word(DDRAM_DOUT, cpu_lane) & ~cpu_mask_l) |
					              (cpu_wdat_l & cpu_mask_l);
					state <= S_CPU_RMW_WR_CMD;
				end
			end

			S_CPU_RMW_WR_CMD: begin
				if (!DDRAM_WE) begin
					DDRAM_BURSTCNT <= 8'd1;
					DDRAM_DIN      <= {4{rmw_result}};
					DDRAM_BE       <= lane_be(cpu_lane, cpu_be_l);
					DDRAM_WE       <= 1'b1;
				end else if (!DDRAM_BUSY) begin
					DDRAM_WE <= 1'b0;
					cpu_done <= 1'b1;
					state    <= S_IDLE;
					if (t0_valid && t0_tag[9:0] == cpu_addr[17:8]) t0_valid <= 1'b0;
					if (t1_valid && t1_tag[9:0] == cpu_addr[17:8]) t1_valid <= 1'b0;
				end
			end

			S_CPY_RD_CMD: begin
				if (!DDRAM_BUSY) begin
					DDRAM_RD <= 1'b0;
					state    <= S_CPY_RD_DATA;
				end
			end

			S_CPY_RD_DATA: begin
				if (DDRAM_DOUT_READY) begin
					cpy_buffer[cpy_count[4:0]] <= DDRAM_DOUT;
					cpy_count <= cpy_count + 1'd1;
					if (cpy_count == 6'd31) begin
						cpy_count <= 6'd0;
						state <= S_CPY_WR_CMD;
					end
				end
			end

			S_CPY_WR_CMD: begin
				if (!DDRAM_WE) begin
					DDRAM_ADDR     <= DDR_BASE | {13'd0, cpy_dst_l, 5'd0} |
					                  {24'd0, cpy_count[4:0]};
					DDRAM_BURSTCNT <= 8'd1;
					DDRAM_DIN      <= cpy_buffer[cpy_count[4:0]];
					DDRAM_BE       <= plane_be(cpy_plane_l);
					DDRAM_WE       <= 1'b1;
				end else if (!DDRAM_BUSY) begin
					DDRAM_WE <= 1'b0;
					if (cpy_count == 6'd31) begin
						cpy_ack <= ~cpy_ack;
						state   <= S_IDLE;
					end else begin
						cpy_count <= cpy_count + 1'd1;
					end
				end
			end

			default: state <= S_RESET;
			endcase
		end
	end

endmodule
