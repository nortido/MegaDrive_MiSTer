// equivalence bench for the cheat code lookup: the rewrite has to answer the
// same as the original for every code set and every bus word, or a game genie
// code silently changes what a game reads.
`timescale 1ns/1ps
module tb_codes;
	reg clk = 0; always #5 clk = ~clk;
	reg reset = 1;
	reg enable = 1;
	reg [128:0] code = 0;

	reg  [23:0] a16 = 0;
	reg  [15:0] d16 = 0;
	wire [15:0] q16_ref, q16_new;
	reg  [15:0] a8 = 0;
	reg   [7:0] d8 = 0;
	wire  [7:0] q8_ref, q8_new;

	CODES_ref #(.ADDR_WIDTH(24), .DATA_WIDTH(16), .BIG_ENDIAN(1)) ref16
		(.clk(clk), .reset(reset), .enable(enable), .code(code), .available(),
		 .addr_in(a16), .data_in(d16), .data_out(q16_ref));
	CODES     #(.ADDR_WIDTH(24), .DATA_WIDTH(16), .BIG_ENDIAN(1)) new16
		(.clk(clk), .reset(reset), .enable(enable), .code(code), .available(),
		 .addr_in(a16), .data_in(d16), .data_out(q16_new));

	CODES_ref #(.ADDR_WIDTH(16), .DATA_WIDTH(8)) ref8
		(.clk(clk), .reset(reset), .enable(enable), .code(code), .available(),
		 .addr_in(a8), .data_in(d8), .data_out(q8_ref));
	CODES     #(.ADDR_WIDTH(16), .DATA_WIDTH(8)) new8
		(.clk(clk), .reset(reset), .enable(enable), .code(code), .available(),
		 .addr_in(a8), .data_in(d8), .data_out(q8_new));

	integer i, j, bad, checks;
	reg [23:0] addrs [0:15];

	task load_code(input [23:0] ad, input [15:0] cmp, input [15:0] rep,
	               input comp_f, input wide);
	begin
		code = 0;
		code[95:64]  = {8'd0, ad};
		code[63:32]  = {16'd0, cmp};
		code[31:0]   = {16'd0, rep};
		code[96]     = comp_f;
		code[97]     = wide;
		@(negedge clk);
		code[128] = 1;
		@(negedge clk);
		@(negedge clk);
		code[128] = 0;
		@(negedge clk);
	end
	endtask

	initial begin
		bad = 0; checks = 0;
		repeat (4) @(negedge clk);
		reset = 0;
		repeat (4) @(negedge clk);

		// a spread of codes: byte and word width, with and without the compare
		// flag. the loader replaces a code that repeats an address, so a collision
		// needs two different addresses landing on one byte: for sixteen bit reads
		// the low address bit is dropped, so a word code at an even address and a
		// byte code at the odd one above it both write the same half. the later
		// code has to win, which is what the ordered walk used to guarantee.
		for (i = 0; i < 8; i = i + 1) begin
			addrs[i] = 24'h100000 + i * 24'h10;
			load_code(addrs[i], 16'h1234 + i, 16'hA000 + i, i[0], i[1]);
		end
		for (i = 8; i < 12; i = i + 1) begin
			addrs[i] = addrs[i-8] + 24'd1;
			load_code(addrs[i], 16'h1234 + i, 16'hB000 + i, 1'b0, 1'b1);
		end

		for (i = 0; i < 4000; i = i + 1) begin
			a16 = (i % 3 == 0) ? addrs[i % 12] : $random;
			d16 = (i % 4 == 0) ? 16'h1234 + (i % 12) : $random;
			a8  = a16[15:0];
			d8  = d16[7:0];
			enable = (i % 97 != 0);
			#1;
			checks = checks + 2;
			if (q16_ref !== q16_new) begin
				if (bad < 5) $display("  16-bit addr %h data %h: ref %h new %h", a16, d16, q16_ref, q16_new);
				bad = bad + 1;
			end
			if (q8_ref !== q8_new) begin
				if (bad < 5) $display("  8-bit addr %h data %h: ref %h new %h", a8, d8, q8_ref, q8_new);
				bad = bad + 1;
			end
			@(negedge clk);
		end

		$display("comparisons: %0d, mismatches: %0d", checks, bad);
		if (bad == 0) $display("RESULT: PASS - the rewritten lookup answers exactly as the original");
		else          $display("RESULT: FAIL - the rewritten lookup differs");
		$finish;
	end
endmodule
