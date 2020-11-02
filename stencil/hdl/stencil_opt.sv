// Stencil Coprocessor, derived from the one submitted to the 2nd ARC/CPSY/RECONF
// High Performance Computer System Design Contest, held at FIT 2014.
// 2014.09.01 Naoki F., TUT -> 2020.03.13 Naoki F., AIT
// ライセンス条件は LICENSE.txt を参照してください

module stencil_coproc (
    input  logic        CLK, RST,
    input  logic        GO,
    output logic        DONE,
    input  logic [15:0] SIZE,
    input  logic [31:0] SRC, DST,
    // <-> AXI_FIFO
    output logic [31:0] READ_ADDR,
    output logic [15:0] READ_COUNT,
    output logic        READ_REQ,
    input  logic        READ_BUSY,
    input  logic [31:0] READ_DATA,
    input  logic        READ_VALID,
    output logic        READ_READY,
    output logic [31:0] WRITE_ADDR,
    output logic [15:0] WRITE_COUNT,
    output logic        WRITE_REQ,
    input  logic        WRITE_BUSY,
    output logic [31:0] WRITE_DATA,
    output logic        WRITE_VALID,
    input  logic        WRITE_READY);
    
    assign READ_READY = WRITE_READY;

    // 最大サイズの制限（FIFOのハードウェア量に影響）
    parameter  MAX_SIZE = 1024;
    logic [15:0] N;
    assign N = (SIZE >= MAX_SIZE) ? MAX_SIZE : SIZE;


    // 読み出しアドレスの設定
    logic        read_proceed;
    logic [31:0] n_read_addr;
    logic [15:0] read_y, n_read_y;
    logic        read_last;

    assign READ_COUNT = N;
    
    // for (y = 0; y <= N - 1; y++)
    //   &SRC[y][0] から N 要素読み出す
    always_comb begin
        read_last    = 1'b0;
        if (DONE) begin
            read_proceed = GO;
            n_read_addr  = SRC;
            n_read_y     = 16'd0;
        end else begin
            read_proceed = READ_REQ & ~ READ_BUSY;
            n_read_addr  = READ_ADDR + N * 4;
            n_read_y     = read_y + 1'b1;
            if (read_y == N - 1'b1) begin
                read_last    = 1'b1;
            end
        end
    end

    always_ff @ (posedge CLK) begin
        if (RST) begin
            READ_ADDR <= 0;
            READ_REQ  <= 1'b0;
            read_y    <= 16'd0;
        end else if (read_proceed) begin
            READ_ADDR <= n_read_addr;
            READ_REQ  <= ~ read_last;
            read_y    <= n_read_y;
        end
    end

    // 書き込みアドレスの設定
    logic        write_proceed;
    logic [31:0] n_write_addr;
    logic [15:0] write_y, n_write_y;
    logic        write_last;

    assign WRITE_COUNT = N - 2'd2;
    
    // for (y = 1; y <= N - 2; y++)
    //   &DST[y][1] に N - 2 要素書き込む
    always_comb begin
        write_last    = 1'b0;
        if (DONE) begin
            write_proceed = GO;
            n_write_addr  = DST + 3'd4 + N * 4;
            n_write_y     = 16'd1;
        end else begin
            write_proceed = WRITE_REQ & ~ WRITE_BUSY;
            n_write_addr  = WRITE_ADDR + N * 4;
            n_write_y     = write_y + 1'b1;
            if (write_y == N - 2'd2) begin
                write_last    = 1'b1;
            end
        end
    end

    always_ff @ (posedge CLK) begin
        if (RST) begin
            WRITE_ADDR  <= 0;
            WRITE_REQ   <= 1'b0;
            write_y     <= 16'd0;
        end else if (write_proceed) begin
            WRITE_ADDR  <= n_write_addr;
            WRITE_REQ   <= ~ write_last;
            write_y     <= n_write_y;
        end
    end

    // 【演算】
    // データパス関連信号
    logic [31:0] calc_reg_ul, calc_add_uc;
    logic [31:0] calc_reg_uc, calc_add_ur;
    logic [31:0] calc_add_c, calc_add_l, calc_reg_add;
    logic [64:0] calc_mult;
    logic [31:0] calc_reg_mult;

    // 制御関連信号
    logic        calc_proceed;
    logic        calc_done, n_calc_done;
    logic [15:0] add_x, add_y, n_add_x, n_add_y;
    logic [15:0] mult_x, mult_y, n_mult_x, n_mult_y;
    logic [15:0] out_x, out_y, n_out_x, n_out_y; // 注意: 書かれる箇所の添字より 1 大きい

    // FIFO 関連信号
    logic [31:0] fifo_u_data_w, fifo_u_data_r;
    logic        fifo_u_we, fifo_u_re;
    logic [31:0] fifo_c_data_w, fifo_c_data_r;
    logic        fifo_c_we, fifo_c_re;

    // 演算のデータパス（詳しくは付属のPPT参照）
    assign calc_add_uc   = calc_reg_ul + READ_DATA;
    assign calc_add_ur   = calc_reg_uc + READ_DATA;
    assign fifo_u_data_w = calc_add_ur;
    assign calc_add_c    = fifo_u_data_r + calc_add_ur;
    assign fifo_c_data_w = calc_add_c;
    assign calc_add_l    = fifo_c_data_r + calc_add_ur;
    assign calc_mult     = calc_reg_add * 32'h38e38e39; // 34'h2_00000000 / 9
    assign WRITE_DATA    = (out_x == 16'd5 && out_y == 16'd5) ? 32'h0fffffff : calc_reg_mult;

    always_ff @ (posedge CLK) begin
        if (RST) begin
            calc_reg_ul   <= 0;
            calc_reg_uc   <= 0;
            calc_reg_add  <= 0;
            calc_reg_mult <= 0;
        end else if (calc_proceed) begin
            calc_reg_ul   <= READ_DATA;
            calc_reg_uc   <= calc_add_uc;
            calc_reg_add  <= calc_add_l;
            calc_reg_mult <= calc_mult[64:33];
        end
    end

    // 演算の制御
    always_comb begin
        calc_proceed = 1'b0;
        WRITE_VALID  = 1'b0;
        n_calc_done  = calc_done;
        n_add_x      = add_x;
        n_add_y      = add_y;
        fifo_u_we    = 1'b0;
        fifo_u_re    = 1'b0;
        fifo_c_we    = 1'b0;
        fifo_c_re    = 1'b0;
        if (DONE) begin
            calc_proceed = GO;
            n_calc_done  = 1'b0;
            n_add_x      = 16'd0;
            n_add_y      = 16'd0;
            n_mult_x     = 16'd0;
            n_mult_y     = 16'd0;
            n_out_x      = 16'd0;
            n_out_y      = 16'd0;
        end else begin
            calc_proceed = (add_y < N) ? (READ_VALID & READ_READY) : WRITE_READY;
            WRITE_VALID  = (calc_proceed && out_x >= 16'd2 && out_y >= 16'd2);
            n_calc_done  = (out_x == N - 1'b1 && out_y == N - 1'b1);
            if (add_x != N - 1'b1) begin
                n_add_x      = add_x + 1'b1;
            end else begin
                n_add_x      = 16'd0;
                n_add_y      = add_y + 1'b1;
            end
            n_mult_x     = add_x;
            n_mult_y     = add_y;
            n_out_x      = mult_x;
            n_out_y      = mult_y;
            fifo_u_we    = (calc_proceed && (add_y >= 16'd1 || add_x >= 16'd2));
            fifo_u_re    = (calc_proceed && (add_y >= 16'd2 || (add_y == 16'd1 && add_x >= 16'd2)));
            fifo_c_we    = (calc_proceed && (add_y >= 16'd2 || (add_y == 16'd1 && add_x >= 16'd2)));
            fifo_c_re    = (calc_proceed && (add_y >= 16'd3 || (add_y == 16'd2 && add_x >= 16'd2)));
        end
    end
    
    always_ff @ (posedge CLK) begin
        if (RST) begin
            calc_done <= 1'b1;
            add_x     <= 16'd0;
            add_y     <= 16'd0;
            mult_x    <= 16'd0;
            mult_y    <= 16'd0;
            out_x     <= 16'd0;
            out_y     <= 16'd0;
        end else if (calc_proceed) begin
            calc_done <= n_calc_done;
            add_x     <= n_add_x;
            add_y     <= n_add_y;
            mult_x    <= n_mult_x;
            mult_y    <= n_mult_y;
            out_x     <= n_out_x;
            out_y     <= n_out_y;
        end
    end

    // 途中経過保存用の FIFO
    fifo # (
            .WIDTH(32),
            .SIZE(MAX_SIZE))
        fifo_u (
            .CLK(CLK),
            .RST(RST),
            .DATA_W(fifo_u_data_w),
            .DATA_R(fifo_u_data_r),
            .WE(fifo_u_we),
            .RE(fifo_u_re),
            .EMPTY(),
            .FULL(),
            .SOFT_RST(GO & DONE));

    fifo # (
            .WIDTH(32),
            .SIZE(MAX_SIZE))
        fifo_c (
            .CLK(CLK),
            .RST(RST),
            .DATA_W(fifo_c_data_w),
            .DATA_R(fifo_c_data_r),
            .WE(fifo_c_we),
            .RE(fifo_c_re),
            .EMPTY(),
            .FULL(),
            .SOFT_RST(GO & DONE));

    assign DONE = ~ READ_REQ && ~ WRITE_REQ && calc_done;
endmodule