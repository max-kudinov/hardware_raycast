`include "fixp_pkg.svh"
`include "tex_pkg.svh"
`include "dvi_pkg.svh"

`default_nettype none

module render
    import fixp_pkg::*;
    import tex_pkg::*;
    import dvi_pkg::W_H_RES;
    import dvi_pkg::W_V_RES;
    import dvi_pkg::FRAME_WIDTH;
    import dvi_pkg::FRAME_HEIGHT;
    import dvi_pkg::W_COLOR;
(
    input  var logic                 clk,
    input  var logic                 rst,

    // DVI
    input  var logic [W_H_RES-1:0]   px_x_i,
    input  var logic [W_V_RES-1:0]   px_y_i,
    input  var logic                 in_range_i,
    input  var logic                 new_frame_i,
    output var logic [W_COLOR-1:0]   red_o,
    output var logic [W_COLOR-1:0]   green_o,
    output var logic [W_COLOR-1:0]   blue_o,

    // Map coordinates to check for a wall
    output var logic [POS_W_INT-1:0] lookup_map_x_o,
    output var logic [POS_W_INT-1:0] lookup_map_y_o,
    input  var logic [W_NUM_TEX-1:0] texture_i,

    // Camera coordinates
    input  var pos_fixp_t            pos_x_i,
    input  var pos_fixp_t            pos_y_i,
    // Camera direction
    input  var ray_fixp_t            dir_x_i,
    input  var ray_fixp_t            dir_y_i,
    // Camera plane
    input  var ray_fixp_t            plane_x_i,
    input  var ray_fixp_t            plane_y_i
);

// ----------------------------------------------------------------------------
// Local types declaration
// ----------------------------------------------------------------------------

typedef logic [-1:-signed'(TEX_STEP_W_FRAC)]         temp_fixp_t;
typedef logic [W_TEX_SIDE:-signed'(TEX_STEP_W_FRAC)] align_fixp_t;

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam int unsigned    W_BUF_DATA     = W_NUM_TEX                        +  // texture
                                            1                                +  // tex_shade
                                            W_TEX_SIDE                       +  // tex_x
                                            TEX_STEP_W_INT + TEX_STEP_W_FRAC +  // tex_step
                                            (W_V_RES - 1);                      // tex_height (LSB is not used)

localparam int unsigned     N_PIPE_STAGES = 4;                                  // 0 to 3
localparam int unsigned     W_VALIDS      = N_PIPE_STAGES - 1;                  // Don't need valid for the last stage

localparam int unsigned     BUF_DEPTH     = FRAME_WIDTH * 2;
localparam int unsigned     W_BUF_ADDR    = $clog2(BUF_DEPTH);

localparam int              ALIGN_SHIFT   = W_V_RES - (W_TEX_SIDE + 1);
localparam int unsigned     ALIGN_EXT_PAD = unsigned'($size(align_fixp_t)) - W_V_RES;
localparam [W_TEX_SIDE-1:0] TEX_Y_MAX     = 2**W_TEX_SIDE - 1;

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

// Buffer with data for each screen column
logic [W_BUF_DATA-1:0] frame_buffer [BUF_DEPTH];
logic                  buf_write;
logic                  buf_read;
logic                  buf_toggle;
logic [W_BUF_ADDR-1:0] buf_rd_addr;
logic [W_BUF_ADDR-1:0] buf_wr_addr;
logic [W_BUF_DATA-1:0] buf_wr_data;
logic [W_BUF_DATA-1:0] buf_rd_data;

// Calculated texture data to be written to the buffer
// verilator lint_off UNUSEDSIGNAL
logic [W_V_RES-1:0]    wr_tex_height;  // LSB is not used
// verilator lint_on UNUSEDSIGNAL
logic [W_NUM_TEX-1:0]  wr_texture;
logic                  wr_tex_shade;
logic [W_TEX_SIDE-1:0] wr_tex_x;
tex_step_fixp_t        wr_tex_step;

// Calculation control signals
logic                  calc_start;
logic                  calc_done;
logic [W_H_RES-1:0]    calc_px_x;
logic                  calc_active;

// Pipeline control path
logic [W_VALIDS-1:0]   valids;

// Stage 0
logic [W_V_RES-1:0]    px_y_p0;
// Texture data from the buffer
logic [W_V_RES-2:0]    rd_tex_height;
logic [W_NUM_TEX-1:0]  rd_texture;
logic                  rd_tex_shade;
logic [W_TEX_SIDE-1:0] rd_tex_x;
tex_step_fixp_t        rd_tex_step;

// Stage 1
logic [W_V_RES-1:0]    tex_align_next;
logic [W_V_RES-1:0]    tex_align_p1;

logic [W_V_RES-1:0]    tex_start;
logic [W_V_RES-1:0]    tex_end;
logic                  in_texture_next;
logic                  in_texture_p1;
logic                  bg_top_next;
logic                  bg_top_p1;

logic [W_NUM_TEX-1:0]  texture_p1;
logic                  tex_shade_p1;
logic [W_TEX_SIDE-1:0] tex_x_p1;
tex_step_fixp_t        tex_step_p1;

tex_zoom_fixp_t        tex_zoom_next;
tex_zoom_fixp_t        tex_zoom_p1;
temp_fixp_t            step_frac;
temp_fixp_t            height_ext;
temp_fixp_t            temp_mult;

// Stage 2
align_fixp_t           tex_align_ext;
align_fixp_t           tex_align_scaled;

logic [W_V_RES-1:0]    raw_tex_y;
logic [W_TEX_SIDE-1:0] tex_y_next;
logic [W_TEX_SIDE-1:0] tex_y_p2;

logic [W_NUM_TEX-1:0]  texture_p2;
logic                  in_texture_p2;
logic [W_TEX_SIDE-1:0] tex_x_p2;
logic                  tex_shade_p2;
logic                  bg_top_p2;

// Stage 3
logic [W_COLOR-1:0]    red_next;
logic [W_COLOR-1:0]    green_next;
logic [W_COLOR-1:0]    blue_next;

logic [TEX_SIDE-1:0][W_PX_CODE-1:0] texture [NUM_TEX] [TEX_SIDE];
logic [23:0] recode_lut [NUM_TEX] [15];

// ----------------------------------------------------------------------------
// Texture column calculation
// ----------------------------------------------------------------------------

always_ff @(posedge clk)
    if (rst)
        buf_toggle <= '0;
    else if (new_frame_i)
        buf_toggle <= !buf_toggle;

// Simple dual-port block RAM with read-first behavior
always_ff @(posedge clk) begin
    if (buf_write)
        frame_buffer[buf_wr_addr] <= buf_wr_data;

    if (buf_read)
        buf_rd_data <= frame_buffer[buf_rd_addr];
end

column_calc column_calc (
    .clk            (clk           ),
    .rst            (rst           ),

    .start_i        (calc_start    ),
    .px_x_i         (calc_px_x     ),

    .pos_x_i        (pos_x_i       ),
    .pos_y_i        (pos_y_i       ),
    .dir_x_i        (dir_x_i       ),
    .dir_y_i        (dir_y_i       ),
    .plane_x_i      (plane_x_i     ),
    .plane_y_i      (plane_y_i     ),

    .lookup_map_x_o (lookup_map_x_o),
    .lookup_map_y_o (lookup_map_y_o),
    .texture_i      (texture_i     ),

    .done_o         (calc_done     ),
    .texture_o      (wr_texture    ),
    .tex_shade_o    (wr_tex_shade  ),
    .tex_x_o        (wr_tex_x      ),
    .tex_step_o     (wr_tex_step   ),
    .tex_height_o   (wr_tex_height )
);

always_ff @(posedge clk) begin
    if (rst) begin
        calc_px_x  <= '0;
    end else if (calc_done) begin
        if (calc_px_x == (FRAME_WIDTH - 1)) begin
            calc_px_x <= '0;
        end else begin
            calc_px_x <= calc_px_x + 1'b1;
        end
    end
end

always_ff @(posedge clk) begin
    if (rst)
        calc_active <= '0;
    else if (new_frame_i)
        calc_active <= '1;
    else if (calc_start && (calc_px_x == (FRAME_WIDTH - 1)))
        calc_active <= '0;
end

always_ff @(posedge clk)
    if (rst)
        calc_start <= '0;
    else if (new_frame_i)
        calc_start <= '1;
    else
        calc_start <= calc_active && calc_done;

// Height divided in half is used for calculations, so we don't need LSB
assign buf_wr_data = { wr_texture, wr_tex_shade, wr_tex_x, wr_tex_step, wr_tex_height[W_V_RES-1:1] };
assign buf_write   = calc_done;
assign buf_wr_addr = W_BUF_ADDR'(calc_px_x) + W_BUF_ADDR'(FRAME_WIDTH & { W_H_RES { buf_toggle } });


// ----------------------------------------------------------------------------
// Pipeline that calculates pixel values based on coordinates and data that is
// read from the texture buffer
// ----------------------------------------------------------------------------

// ----------------------------------------------------------------------------
// Stage 0
// Send signal to read from buffer, save corresponding y coordinate for the
// next stage
// ----------------------------------------------------------------------------

assign buf_read    = in_range_i;
assign buf_rd_addr = W_BUF_ADDR'(px_x_i) + W_BUF_ADDR'(FRAME_WIDTH & { W_H_RES { !buf_toggle } });

always_ff @(posedge clk)
    px_y_p0 <= px_y_i;

// Valid data is available on the next clock cycle after read
// Every bit of valid shift register correspond to validity of data on each
// stage
always_ff @(posedge clk)
    if (rst) begin
        valids <= '0;
    end else begin
        valids <= { valids[W_VALIDS-2:0], buf_read };
    end

// ----------------------------------------------------------------------------
// Stage 1
// Get values from the buffer, calculate texture start and end coordinates
// based on height, calculate texture zoom offset (y_start) and intermediate
// value for y coordinate in the texture
// ----------------------------------------------------------------------------

assign { rd_texture, rd_tex_shade, rd_tex_x, rd_tex_step, rd_tex_height } = buf_rd_data;

always_comb begin
    bg_top_next     = px_y_p0 < (FRAME_HEIGHT >> 1);
    tex_start       = (FRAME_HEIGHT >> 1) - W_V_RES'(rd_tex_height);
    tex_end         = (FRAME_HEIGHT >> 1) + W_V_RES'(rd_tex_height);
    in_texture_next = (px_y_p0 >= tex_start) && (px_y_p0 < tex_end);
    tex_align_next  = px_y_p0 - tex_start;

    step_frac       = rd_tex_step[-1:$right(rd_tex_step)];
    height_ext      = { FRAME_HEIGHT[W_V_RES-1:1], { TEX_ZOOM_W_FRAC {1'b0} } };
    temp_mult       = `FIXP_MULT(height_ext, step_frac);

    if (rd_tex_step < TEX_SCALE)
        tex_zoom_next = { TEX_ZOOM_W_INT'(TEX_SIDE >> 1), { TEX_ZOOM_W_FRAC {1'b0} } } -
                        { temp_mult }[$size(tex_zoom_next)-1:0];
    else
        tex_zoom_next = '0;
end

always_ff @(posedge clk)
    if (valids[0]) begin
        bg_top_p1     <= bg_top_next;
        in_texture_p1 <= in_texture_next;
        tex_zoom_p1   <= tex_zoom_next;
        tex_align_p1  <= tex_align_next;
        texture_p1    <= rd_texture;
        tex_shade_p1  <= rd_tex_shade;
        tex_x_p1      <= rd_tex_x;
        tex_step_p1   <= rd_tex_step;
    end

// ----------------------------------------------------------------------------
// Stage 2
// Calculate texture y coordinate
// ----------------------------------------------------------------------------

always_comb begin
    // In order to make mult operands shorter, we represent lower bits of
    // integer number in a fractional part (same as left shift), the correct
    // value could be later restored by applying opposite right shift
    tex_align_ext    = { tex_align_p1, { ALIGN_EXT_PAD {1'b0} } };
    tex_align_scaled = `FIXP_MULT(tex_align_ext, tex_step_p1);

    // Shift y_zoom_offset to account for shifted tex_align_scaled, then take
    // the integer part of the sum (accounting for previous shift, so we take
    // a few bits from "fractional" part and represent it as lower bits of integer)
    raw_tex_y        = {
                        (`FIXP_CAST(tex_zoom_p1, align_fixp_t) >> ALIGN_SHIFT)
                        + tex_align_scaled
                       }[$size(align_fixp_t)-1 -: W_V_RES];

    // If raw_tex_y is greater than maximum texel coordinate
    // clip to max coordinate value
    if (raw_tex_y > W_V_RES'(TEX_Y_MAX))
        tex_y_next = TEX_Y_MAX;
    else
        tex_y_next = raw_tex_y[W_TEX_SIDE-1:0];
end

always_ff @(posedge clk)
    if (valids[1]) begin
        bg_top_p2     <= bg_top_p1;
        in_texture_p2 <= in_texture_p1;
        texture_p2    <= texture_p1;
        tex_shade_p2  <= tex_shade_p1;
        tex_x_p2      <= tex_x_p1;
        tex_y_p2      <= tex_y_next;
    end

// ----------------------------------------------------------------------------
// Stage 3
// Get texel from the texture and apply shade if necessary
// ----------------------------------------------------------------------------

always_comb begin
    if (bg_top_p2)
        { red_next, green_next, blue_next } = { 8'd20, 8'd20, 8'd20 };
    else
        { red_next, green_next, blue_next } = { 8'd48, 8'd48, 8'd48 };

    if (in_texture_p2)
        if (tex_shade_p2)
            { red_next, green_next, blue_next } = (recode_lut[texture_p2 - 1'b1][texture[texture_p2 - 1'b1][tex_y_p2][tex_x_p2]] >> 1) &
                                                  { { 8 {1'b1} }, 1'b0, { 7 {1'b1} }, 1'b0, {7 {1'b1} } };
        else
            { red_next, green_next, blue_next } = recode_lut[texture_p2 - 1'b1][texture[texture_p2 - 1'b1][tex_y_p2][tex_x_p2]];
end

always_ff @(posedge clk)
    if (valids[2]) begin
        red_o   <= red_next;
        green_o <= green_next;
        blue_o  <= blue_next;
    end

initial begin
    texture[0] = {
        { 4'd1, 4'd0, 4'd1, 4'd0, 4'd1, 4'd1, 4'd1, 4'd1, 4'd0, 4'd0, 4'd1, 4'd1, 4'd1, 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd1, 4'd1, 4'd0, 4'd1, 4'd1, 4'd1, 4'd0, 4'd1, 4'd1, 4'd1, 4'd1, 4'd0, 4'd0, 4'd0 },
        { 4'd0, 4'd4, 4'd3, 4'd3, 4'd3, 4'd3, 4'd2, 4'd3, 4'd3, 4'd2, 4'd3, 4'd2, 4'd2, 4'd5, 4'd2, 4'd2, 4'd1, 4'd4, 4'd3, 4'd3, 4'd3, 4'd3, 4'd3, 4'd3, 4'd3, 4'd3, 4'd2, 4'd2, 4'd2, 4'd3, 4'd2, 4'd2 },
        { 4'd1, 4'd10, 4'd4, 4'd4, 4'd7, 4'd4, 4'd7, 4'd4, 4'd4, 4'd7, 4'd7, 4'd6, 4'd11, 4'd11, 4'd5, 4'd3, 4'd0, 4'd10, 4'd4, 4'd4, 4'd9, 4'd6, 4'd8, 4'd4, 4'd4, 4'd4, 4'd4, 4'd7, 4'd7, 4'd6, 4'd6, 4'd3 },
        { 4'd0, 4'd12, 4'd13, 4'd4, 4'd4, 4'd4, 4'd13, 4'd4, 4'd7, 4'd4, 4'd4, 4'd7, 4'd9, 4'd8, 4'd11, 4'd2, 4'd1, 4'd12, 4'd4, 4'd4, 4'd11, 4'd9, 4'd11, 4'd11, 4'd7, 4'd7, 4'd7, 4'd6, 4'd7, 4'd7, 4'd4, 4'd2 },
        { 4'd1, 4'd10, 4'd13, 4'd4, 4'd13, 4'd13, 4'd4, 4'd4, 4'd4, 4'd7, 4'd7, 4'd4, 4'd11, 4'd8, 4'd7, 4'd2, 4'd1, 4'd10, 4'd7, 4'd7, 4'd7, 4'd8, 4'd4, 4'd7, 4'd4, 4'd5, 4'd7, 4'd4, 4'd6, 4'd4, 4'd7, 4'd2 },
        { 4'd0, 4'd12, 4'd13, 4'd13, 4'd13, 4'd13, 4'd13, 4'd4, 4'd4, 4'd4, 4'd7, 4'd7, 4'd4, 4'd9, 4'd11, 4'd2, 4'd1, 4'd12, 4'd4, 4'd4, 4'd4, 4'd11, 4'd4, 4'd5, 4'd11, 4'd4, 4'd4, 4'd4, 4'd7, 4'd4, 4'd6, 4'd3 },
        { 4'd1, 4'd12, 4'd13, 4'd13, 4'd4, 4'd4, 4'd13, 4'd13, 4'd4, 4'd13, 4'd13, 4'd4, 4'd9, 4'd7, 4'd4, 4'd3, 4'd1, 4'd12, 4'd4, 4'd4, 4'd4, 4'd4, 4'd4, 4'd11, 4'd7, 4'd4, 4'd7, 4'd7, 4'd7, 4'd4, 4'd4, 4'd3 },
        { 4'd0, 4'd12, 4'd12, 4'd12, 4'd12, 4'd10, 4'd12, 4'd10, 4'd12, 4'd10, 4'd12, 4'd12, 4'd10, 4'd14, 4'd10, 4'd4, 4'd0, 4'd12, 4'd12, 4'd12, 4'd10, 4'd12, 4'd14, 4'd12, 4'd10, 4'd12, 4'd12, 4'd10, 4'd12, 4'd10, 4'd10, 4'd4 },
        { 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd1, 4'd1, 4'd1, 4'd1, 4'd0, 4'd0, 4'd0, 4'd1, 4'd1, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd1, 4'd1, 4'd0, 4'd1, 4'd0 },
        { 4'd3, 4'd3, 4'd3, 4'd3, 4'd2, 4'd3, 4'd2, 4'd2, 4'd1, 4'd4, 4'd3, 4'd3, 4'd3, 4'd3, 4'd2, 4'd3, 4'd3, 4'd2, 4'd2, 4'd2, 4'd3, 4'd2, 4'd2, 4'd3, 4'd0, 4'd4, 4'd3, 4'd5, 4'd3, 4'd2, 4'd3, 4'd2 },
        { 4'd4, 4'd4, 4'd7, 4'd11, 4'd11, 4'd5, 4'd6, 4'd3, 4'd0, 4'd10, 4'd13, 4'd4, 4'd5, 4'd4, 4'd4, 4'd7, 4'd7, 4'd7, 4'd4, 4'd4, 4'd6, 4'd7, 4'd6, 4'd2, 4'd1, 4'd10, 4'd9, 4'd5, 4'd8, 4'd5, 4'd7, 4'd5 },
        { 4'd7, 4'd4, 4'd4, 4'd11, 4'd5, 4'd8, 4'd6, 4'd2, 4'd0, 4'd12, 4'd4, 4'd4, 4'd7, 4'd9, 4'd7, 4'd7, 4'd4, 4'd4, 4'd6, 4'd4, 4'd6, 4'd6, 4'd7, 4'd3, 4'd1, 4'd10, 4'd13, 4'd9, 4'd11, 4'd8, 4'd4, 4'd4 },
        { 4'd4, 4'd7, 4'd4, 4'd5, 4'd9, 4'd11, 4'd7, 4'd3, 4'd1, 4'd10, 4'd13, 4'd4, 4'd11, 4'd8, 4'd5, 4'd4, 4'd4, 4'd13, 4'd7, 4'd6, 4'd7, 4'd6, 4'd7, 4'd2, 4'd1, 4'd12, 4'd4, 4'd7, 4'd8, 4'd11, 4'd4, 4'd7 },
        { 4'd4, 4'd4, 4'd9, 4'd7, 4'd7, 4'd7, 4'd4, 4'd2, 4'd0, 4'd12, 4'd13, 4'd9, 4'd8, 4'd11, 4'd4, 4'd11, 4'd7, 4'd4, 4'd4, 4'd4, 4'd4, 4'd4, 4'd7, 4'd3, 4'd0, 4'd12, 4'd13, 4'd11, 4'd5, 4'd13, 4'd7, 4'd4 },
        { 4'd13, 4'd4, 4'd4, 4'd9, 4'd4, 4'd4, 4'd7, 4'd3, 4'd1, 4'd12, 4'd13, 4'd11, 4'd5, 4'd5, 4'd11, 4'd13, 4'd4, 4'd7, 4'd7, 4'd7, 4'd13, 4'd4, 4'd4, 4'd3, 4'd0, 4'd12, 4'd4, 4'd13, 4'd9, 4'd13, 4'd4, 4'd13 },
        { 4'd10, 4'd10, 4'd12, 4'd14, 4'd12, 4'd14, 4'd10, 4'd4, 4'd0, 4'd12, 4'd14, 4'd12, 4'd14, 4'd10, 4'd12, 4'd10, 4'd12, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd4, 4'd0, 4'd12, 4'd12, 4'd12, 4'd12, 4'd10, 4'd12, 4'd10 },
        { 4'd1, 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd1, 4'd1, 4'd1, 4'd0, 4'd0, 4'd1, 4'd1, 4'd0, 4'd1, 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd1, 4'd1, 4'd0, 4'd0 },
        { 4'd0, 4'd4, 4'd3, 4'd3, 4'd3, 4'd3, 4'd2, 4'd2, 4'd2, 4'd3, 4'd3, 4'd2, 4'd3, 4'd3, 4'd3, 4'd2, 4'd1, 4'd4, 4'd3, 4'd3, 4'd3, 4'd2, 4'd2, 4'd2, 4'd5, 4'd3, 4'd2, 4'd3, 4'd2, 4'd2, 4'd3, 4'd2 },
        { 4'd1, 4'd10, 4'd13, 4'd4, 4'd7, 4'd4, 4'd4, 4'd4, 4'd4, 4'd11, 4'd4, 4'd11, 4'd6, 4'd7, 4'd6, 4'd2, 4'd1, 4'd10, 4'd13, 4'd4, 4'd13, 4'd4, 4'd4, 4'd4, 4'd8, 4'd5, 4'd4, 4'd7, 4'd6, 4'd7, 4'd6, 4'd3 },
        { 4'd0, 4'd12, 4'd13, 4'd4, 4'd7, 4'd4, 4'd7, 4'd7, 4'd4, 4'd9, 4'd4, 4'd4, 4'd6, 4'd6, 4'd7, 4'd2, 4'd0, 4'd12, 4'd4, 4'd7, 4'd6, 4'd6, 4'd4, 4'd13, 4'd7, 4'd11, 4'd6, 4'd6, 4'd6, 4'd6, 4'd7, 4'd2 },
        { 4'd0, 4'd10, 4'd13, 4'd4, 4'd13, 4'd4, 4'd7, 4'd7, 4'd4, 4'd9, 4'd7, 4'd4, 4'd6, 4'd7, 4'd4, 4'd2, 4'd0, 4'd10, 4'd13, 4'd4, 4'd4, 4'd4, 4'd7, 4'd11, 4'd5, 4'd4, 4'd11, 4'd4, 4'd7, 4'd4, 4'd6, 4'd2 },
        { 4'd0, 4'd10, 4'd4, 4'd4, 4'd7, 4'd7, 4'd4, 4'd11, 4'd9, 4'd4, 4'd4, 4'd7, 4'd7, 4'd7, 4'd7, 4'd3, 4'd1, 4'd12, 4'd4, 4'd4, 4'd13, 4'd4, 4'd7, 4'd4, 4'd11, 4'd7, 4'd4, 4'd4, 4'd4, 4'd4, 4'd7, 4'd2 },
        { 4'd1, 4'd12, 4'd13, 4'd13, 4'd4, 4'd13, 4'd9, 4'd11, 4'd7, 4'd4, 4'd4, 4'd4, 4'd7, 4'd4, 4'd4, 4'd3, 4'd1, 4'd12, 4'd13, 4'd13, 4'd7, 4'd4, 4'd13, 4'd4, 4'd14, 4'd7, 4'd4, 4'd13, 4'd4, 4'd4, 4'd4, 4'd3 },
        { 4'd0, 4'd12, 4'd12, 4'd12, 4'd10, 4'd10, 4'd10, 4'd12, 4'd12, 4'd10, 4'd12, 4'd12, 4'd10, 4'd12, 4'd10, 4'd4, 4'd0, 4'd12, 4'd12, 4'd12, 4'd10, 4'd10, 4'd10, 4'd12, 4'd10, 4'd14, 4'd12, 4'd12, 4'd12, 4'd10, 4'd10, 4'd4 },
        { 4'd1, 4'd0, 4'd1, 4'd1, 4'd0, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd1, 4'd0, 4'd1, 4'd1, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd1, 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd0, 4'd0, 4'd1, 4'd0, 4'd1 },
        { 4'd3, 4'd3, 4'd2, 4'd2, 4'd2, 4'd2, 4'd2, 4'd2, 4'd0, 4'd4, 4'd3, 4'd3, 4'd2, 4'd3, 4'd2, 4'd2, 4'd2, 4'd2, 4'd2, 4'd2, 4'd2, 4'd3, 4'd3, 4'd2, 4'd1, 4'd4, 4'd3, 4'd3, 4'd5, 4'd11, 4'd11, 4'd2 },
        { 4'd4, 4'd4, 4'd7, 4'd4, 4'd7, 4'd7, 4'd6, 4'd2, 4'd1, 4'd10, 4'd4, 4'd4, 4'd4, 4'd4, 4'd7, 4'd4, 4'd4, 4'd7, 4'd4, 4'd4, 4'd7, 4'd7, 4'd7, 4'd2, 4'd0, 4'd12, 4'd4, 4'd11, 4'd8, 4'd9, 4'd5, 4'd6 },
        { 4'd4, 4'd4, 4'd11, 4'd6, 4'd5, 4'd4, 4'd5, 4'd2, 4'd0, 4'd12, 4'd13, 4'd13, 4'd7, 4'd7, 4'd6, 4'd4, 4'd7, 4'd4, 4'd11, 4'd5, 4'd11, 4'd7, 4'd4, 4'd2, 4'd1, 4'd10, 4'd13, 4'd7, 4'd9, 4'd11, 4'd4, 4'd7 },
        { 4'd7, 4'd4, 4'd4, 4'd11, 4'd5, 4'd9, 4'd6, 4'd3, 4'd1, 4'd10, 4'd13, 4'd4, 4'd4, 4'd7, 4'd7, 4'd7, 4'd4, 4'd7, 4'd5, 4'd11, 4'd8, 4'd4, 4'd7, 4'd3, 4'd0, 4'd12, 4'd13, 4'd4, 4'd11, 4'd9, 4'd11, 4'd4 },
        { 4'd4, 4'd7, 4'd4, 4'd9, 4'd5, 4'd4, 4'd7, 4'd3, 4'd0, 4'd12, 4'd4, 4'd4, 4'd7, 4'd4, 4'd4, 4'd13, 4'd4, 4'd6, 4'd5, 4'd8, 4'd7, 4'd4, 4'd7, 4'd2, 4'd1, 4'd12, 4'd4, 4'd13, 4'd11, 4'd7, 4'd11, 4'd13 },
        { 4'd4, 4'd13, 4'd4, 4'd13, 4'd11, 4'd7, 4'd4, 4'd3, 4'd0, 4'd12, 4'd13, 4'd13, 4'd13, 4'd13, 4'd7, 4'd13, 4'd13, 4'd11, 4'd11, 4'd11, 4'd4, 4'd4, 4'd4, 4'd3, 4'd0, 4'd12, 4'd11, 4'd9, 4'd13, 4'd4, 4'd4, 4'd4 },
        { 4'd10, 4'd12, 4'd12, 4'd14, 4'd10, 4'd10, 4'd10, 4'd4, 4'd0, 4'd12, 4'd12, 4'd12, 4'd12, 4'd12, 4'd12, 4'd10, 4'd10, 4'd14, 4'd12, 4'd12, 4'd12, 4'd10, 4'd10, 4'd4, 4'd0, 4'd12, 4'd12, 4'd14, 4'd10, 4'd10, 4'd12, 4'd10 } 
    };

    texture[1] = {
        { 4'd1, 4'd1, 4'd1, 4'd1, 4'd0, 4'd0, 4'd1, 4'd1, 4'd1, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd1, 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd0, 4'd0 },
        { 4'd5, 4'd3, 4'd8, 4'd6, 4'd1, 4'd1, 4'd6, 4'd3, 4'd3, 4'd4, 4'd3, 4'd5, 4'd7, 4'd1, 4'd0, 4'd0, 4'd0, 4'd1, 4'd0, 4'd0, 4'd6, 4'd5, 4'd3, 4'd4, 4'd3, 4'd3, 4'd4, 4'd4, 4'd3, 4'd2, 4'd0, 4'd1 },
        { 4'd6, 4'd6, 4'd2, 4'd8, 4'd8, 4'd3, 4'd3, 4'd7, 4'd7, 4'd5, 4'd2, 4'd4, 4'd1, 4'd0, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd7, 4'd6, 4'd2, 4'd5, 4'd2, 4'd6, 4'd6, 4'd5, 4'd2, 4'd5, 4'd3, 4'd2, 4'd1 },
        { 4'd0, 4'd7, 4'd6, 4'd2, 4'd2, 4'd5, 4'd3, 4'd6, 4'd7, 4'd6, 4'd2, 4'd4, 4'd7, 4'd7, 4'd1, 4'd0, 4'd7, 4'd7, 4'd1, 4'd7, 4'd6, 4'd5, 4'd2, 4'd4, 4'd7, 4'd7, 4'd6, 4'd2, 4'd2, 4'd5, 4'd3, 4'd0 },
        { 4'd0, 4'd0, 4'd7, 4'd6, 4'd5, 4'd2, 4'd5, 4'd3, 4'd3, 4'd6, 4'd5, 4'd5, 4'd3, 4'd6, 4'd7, 4'd7, 4'd1, 4'd7, 4'd7, 4'd6, 4'd5, 4'd5, 4'd3, 4'd4, 4'd6, 4'd7, 4'd6, 4'd5, 4'd5, 4'd3, 4'd7, 4'd0 },
        { 4'd7, 4'd0, 4'd0, 4'd6, 4'd5, 4'd5, 4'd5, 4'd2, 4'd3, 4'd5, 4'd5, 4'd2, 4'd2, 4'd8, 4'd8, 4'd6, 4'd7, 4'd3, 4'd3, 4'd5, 4'd2, 4'd5, 4'd5, 4'd5, 4'd4, 4'd3, 4'd5, 4'd5, 4'd3, 4'd7, 4'd7, 4'd0 },
        { 4'd1, 4'd0, 4'd7, 4'd6, 4'd5, 4'd3, 4'd5, 4'd5, 4'd5, 4'd2, 4'd2, 4'd6, 4'd5, 4'd2, 4'd5, 4'd8, 4'd3, 4'd5, 4'd5, 4'd2, 4'd5, 4'd2, 4'd2, 4'd5, 4'd6, 4'd6, 4'd2, 4'd2, 4'd5, 4'd3, 4'd7, 4'd0 },
        { 4'd7, 4'd0, 4'd3, 4'd5, 4'd3, 4'd2, 4'd2, 4'd3, 4'd3, 4'd2, 4'd5, 4'd6, 4'd5, 4'd2, 4'd6, 4'd6, 4'd7, 4'd5, 4'd2, 4'd5, 4'd5, 4'd2, 4'd5, 4'd3, 4'd0, 4'd7, 4'd6, 4'd2, 4'd5, 4'd5, 4'd3, 4'd0 },
        { 4'd5, 4'd4, 4'd5, 4'd5, 4'd5, 4'd5, 4'd5, 4'd5, 4'd5, 4'd6, 4'd6, 4'd6, 4'd2, 4'd5, 4'd5, 4'd7, 4'd6, 4'd2, 4'd5, 4'd2, 4'd5, 4'd2, 4'd4, 4'd1, 4'd0, 4'd0, 4'd0, 4'd5, 4'd2, 4'd5, 4'd4, 4'd1 },
        { 4'd6, 4'd5, 4'd2, 4'd5, 4'd7, 4'd7, 4'd2, 4'd5, 4'd5, 4'd7, 4'd0, 4'd7, 4'd6, 4'd2, 4'd6, 4'd5, 4'd5, 4'd5, 4'd2, 4'd2, 4'd5, 4'd5, 4'd4, 4'd1, 4'd1, 4'd0, 4'd7, 4'd2, 4'd5, 4'd2, 4'd4, 4'd1 },
        { 4'd7, 4'd2, 4'd5, 4'd2, 4'd6, 4'd6, 4'd5, 4'd3, 4'd7, 4'd0, 4'd0, 4'd0, 4'd7, 4'd6, 4'd5, 4'd2, 4'd2, 4'd2, 4'd5, 4'd5, 4'd3, 4'd5, 4'd5, 4'd4, 4'd1, 4'd1, 4'd3, 4'd5, 4'd2, 4'd5, 4'd4, 4'd1 },
        { 4'd7, 4'd6, 4'd2, 4'd5, 4'd3, 4'd5, 4'd5, 4'd4, 4'd7, 4'd1, 4'd0, 4'd0, 4'd0, 4'd6, 4'd5, 4'd5, 4'd5, 4'd3, 4'd4, 4'd6, 4'd5, 4'd2, 4'd5, 4'd5, 4'd3, 4'd4, 4'd5, 4'd2, 4'd6, 4'd4, 4'd1, 4'd1 },
        { 4'd7, 4'd6, 4'd2, 4'd2, 4'd5, 4'd5, 4'd5, 4'd4, 4'd7, 4'd1, 4'd0, 4'd7, 4'd1, 4'd6, 4'd5, 4'd2, 4'd5, 4'd2, 4'd4, 4'd6, 4'd7, 4'd7, 4'd6, 4'd5, 4'd5, 4'd5, 4'd2, 4'd5, 4'd2, 4'd4, 4'd1, 4'd1 },
        { 4'd7, 4'd2, 4'd5, 4'd2, 4'd2, 4'd2, 4'd5, 4'd5, 4'd8, 4'd7, 4'd7, 4'd0, 4'd6, 4'd5, 4'd2, 4'd5, 4'd2, 4'd2, 4'd5, 4'd4, 4'd6, 4'd7, 4'd6, 4'd3, 4'd5, 4'd3, 4'd5, 4'd6, 4'd6, 4'd5, 4'd4, 4'd1 },
        { 4'd6, 4'd5, 4'd2, 4'd5, 4'd3, 4'd2, 4'd3, 4'd3, 4'd5, 4'd8, 4'd8, 4'd3, 4'd5, 4'd2, 4'd5, 4'd5, 4'd6, 4'd6, 4'd6, 4'd2, 4'd3, 4'd3, 4'd5, 4'd2, 4'd5, 4'd5, 4'd3, 4'd7, 4'd6, 4'd5, 4'd2, 4'd0 },
        { 4'd7, 4'd2, 4'd5, 4'd4, 4'd7, 4'd6, 4'd3, 4'd5, 4'd3, 4'd5, 4'd3, 4'd3, 4'd5, 4'd5, 4'd5, 4'd3, 4'd7, 4'd0, 4'd7, 4'd6, 4'd2, 4'd5, 4'd5, 4'd2, 4'd5, 4'd4, 4'd7, 4'd1, 4'd1, 4'd6, 4'd5, 4'd0 },
        { 4'd6, 4'd5, 4'd3, 4'd4, 4'd6, 4'd7, 4'd5, 4'd3, 4'd5, 4'd5, 4'd2, 4'd2, 4'd5, 4'd5, 4'd3, 4'd7, 4'd1, 4'd0, 4'd0, 4'd7, 4'd6, 4'd2, 4'd2, 4'd5, 4'd3, 4'd4, 4'd0, 4'd0, 4'd0, 4'd6, 4'd5, 4'd0 },
        { 4'd7, 4'd2, 4'd5, 4'd2, 4'd4, 4'd3, 4'd2, 4'd5, 4'd5, 4'd5, 4'd2, 4'd5, 4'd5, 4'd3, 4'd7, 4'd0, 4'd0, 4'd0, 4'd0, 4'd1, 4'd0, 4'd6, 4'd5, 4'd5, 4'd2, 4'd5, 4'd4, 4'd7, 4'd4, 4'd5, 4'd3, 4'd1 },
        { 4'd6, 4'd3, 4'd6, 4'd7, 4'd6, 4'd2, 4'd2, 4'd2, 4'd2, 4'd5, 4'd6, 4'd5, 4'd5, 4'd4, 4'd7, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd1, 4'd6, 4'd5, 4'd2, 4'd6, 4'd2, 4'd5, 4'd4, 4'd5, 4'd2, 4'd3, 4'd1 },
        { 4'd7, 4'd4, 4'd7, 4'd7, 4'd7, 4'd3, 4'd5, 4'd2, 4'd5, 4'd6, 4'd2, 4'd2, 4'd5, 4'd4, 4'd7, 4'd1, 4'd0, 4'd1, 4'd0, 4'd1, 4'd7, 4'd6, 4'd5, 4'd3, 4'd7, 4'd6, 4'd5, 4'd5, 4'd6, 4'd2, 4'd4, 4'd1 },
        { 4'd6, 4'd4, 4'd2, 4'd6, 4'd5, 4'd5, 4'd2, 4'd5, 4'd3, 4'd7, 4'd6, 4'd2, 4'd5, 4'd5, 4'd4, 4'd7, 4'd1, 4'd0, 4'd1, 4'd7, 4'd6, 4'd2, 4'd5, 4'd4, 4'd6, 4'd6, 4'd5, 4'd6, 4'd6, 4'd5, 4'd4, 4'd1 },
        { 4'd7, 4'd5, 4'd4, 4'd3, 4'd5, 4'd2, 4'd5, 4'd3, 4'd7, 4'd0, 4'd1, 4'd6, 4'd5, 4'd3, 4'd5, 4'd8, 4'd7, 4'd1, 4'd7, 4'd6, 4'd5, 4'd2, 4'd5, 4'd3, 4'd4, 4'd3, 4'd2, 4'd6, 4'd2, 4'd5, 4'd3, 4'd1 },
        { 4'd6, 4'd6, 4'd6, 4'd2, 4'd2, 4'd5, 4'd5, 4'd5, 4'd4, 4'd7, 4'd6, 4'd5, 4'd2, 4'd3, 4'd5, 4'd2, 4'd8, 4'd4, 4'd3, 4'd2, 4'd2, 4'd5, 4'd2, 4'd5, 4'd3, 4'd5, 4'd5, 4'd2, 4'd5, 4'd2, 4'd4, 4'd1 },
        { 4'd6, 4'd7, 4'd7, 4'd6, 4'd5, 4'd3, 4'd5, 4'd5, 4'd3, 4'd4, 4'd5, 4'd2, 4'd5, 4'd5, 4'd5, 4'd2, 4'd5, 4'd5, 4'd5, 4'd3, 4'd5, 4'd5, 4'd5, 4'd5, 4'd5, 4'd5, 4'd3, 4'd5, 4'd2, 4'd4, 4'd5, 4'd1 },
        { 4'd7, 4'd0, 4'd1, 4'd7, 4'd6, 4'd5, 4'd3, 4'd2, 4'd5, 4'd5, 4'd5, 4'd5, 4'd2, 4'd2, 4'd2, 4'd5, 4'd3, 4'd3, 4'd5, 4'd3, 4'd5, 4'd6, 4'd2, 4'd5, 4'd2, 4'd2, 4'd5, 4'd5, 4'd5, 4'd4, 4'd0, 4'd0 },
        { 4'd0, 4'd0, 4'd0, 4'd0, 4'd1, 4'd6, 4'd3, 4'd2, 4'd2, 4'd6, 4'd5, 4'd2, 4'd6, 4'd5, 4'd5, 4'd2, 4'd5, 4'd3, 4'd5, 4'd5, 4'd3, 4'd1, 4'd6, 4'd2, 4'd3, 4'd5, 4'd5, 4'd2, 4'd5, 4'd8, 4'd7, 4'd0 },
        { 4'd7, 4'd0, 4'd0, 4'd1, 4'd7, 4'd6, 4'd5, 4'd5, 4'd7, 4'd7, 4'd5, 4'd3, 4'd6, 4'd7, 4'd5, 4'd5, 4'd5, 4'd5, 4'd5, 4'd3, 4'd7, 4'd0, 4'd1, 4'd6, 4'd5, 4'd3, 4'd2, 4'd6, 4'd2, 4'd8, 4'd5, 4'd7 },
        { 4'd7, 4'd0, 4'd1, 4'd7, 4'd6, 4'd2, 4'd5, 4'd4, 4'd6, 4'd7, 4'd2, 4'd4, 4'd7, 4'd6, 4'd2, 4'd5, 4'd5, 4'd2, 4'd5, 4'd5, 4'd3, 4'd7, 4'd6, 4'd3, 4'd5, 4'd2, 4'd5, 4'd3, 4'd2, 4'd5, 4'd8, 4'd1 },
        { 4'd6, 4'd7, 4'd7, 4'd4, 4'd2, 4'd5, 4'd3, 4'd4, 4'd4, 4'd3, 4'd5, 4'd3, 4'd4, 4'd3, 4'd5, 4'd2, 4'd5, 4'd2, 4'd5, 4'd6, 4'd5, 4'd4, 4'd4, 4'd3, 4'd5, 4'd2, 4'd4, 4'd4, 4'd5, 4'd5, 4'd4, 4'd1 },
        { 4'd5, 4'd4, 4'd4, 4'd3, 4'd2, 4'd5, 4'd2, 4'd3, 4'd5, 4'd2, 4'd2, 4'd3, 4'd5, 4'd5, 4'd2, 4'd6, 4'd6, 4'd2, 4'd5, 4'd7, 4'd7, 4'd7, 4'd6, 4'd5, 4'd2, 4'd5, 4'd5, 4'd2, 4'd5, 4'd5, 4'd3, 4'd1 },
        { 4'd6, 4'd5, 4'd2, 4'd2, 4'd5, 4'd6, 4'd2, 4'd5, 4'd2, 4'd6, 4'd7, 4'd6, 4'd5, 4'd2, 4'd6, 4'd7, 4'd7, 4'd5, 4'd7, 4'd0, 4'd0, 4'd0, 4'd7, 4'd6, 4'd5, 4'd6, 4'd7, 4'd6, 4'd6, 4'd2, 4'd1, 4'd0 },
        { 4'd7, 4'd6, 4'd7, 4'd7, 4'd6, 4'd6, 4'd7, 4'd6, 4'd7, 4'd7, 4'd6, 4'd7, 4'd7, 4'd6, 4'd7, 4'd7, 4'd7, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd7, 4'd6, 4'd7, 4'd6, 4'd7, 4'd7, 4'd1, 4'd0, 4'd0 }
    };

    texture[2] = {
        { 4'd0, 4'd1, 4'd1, 4'd3, 4'd3, 4'd6, 4'd4, 4'd1, 4'd0, 4'd1, 4'd3, 4'd1, 4'd0, 4'd1, 4'd3, 4'd3, 4'd3, 4'd4, 4'd5, 4'd3, 4'd4, 4'd1, 4'd0, 4'd2, 4'd3, 4'd2, 4'd1, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0 },
        { 4'd0, 4'd1, 4'd3, 4'd4, 4'd5, 4'd6, 4'd5, 4'd3, 4'd1, 4'd2, 4'd2, 4'd0, 4'd1, 4'd3, 4'd3, 4'd5, 4'd4, 4'd5, 4'd5, 4'd4, 4'd6, 4'd4, 4'd1, 4'd1, 4'd2, 4'd5, 4'd6, 4'd6, 4'd0, 4'd0, 4'd0, 4'd1 },
        { 4'd0, 4'd0, 4'd1, 4'd3, 4'd3, 4'd3, 4'd4, 4'd5, 4'd4, 4'd1, 4'd2, 4'd1, 4'd3, 4'd5, 4'd3, 4'd6, 4'd5, 4'd3, 4'd6, 4'd5, 4'd5, 4'd3, 4'd1, 4'd1, 4'd3, 4'd5, 4'd3, 4'd5, 4'd6, 4'd0, 4'd0, 4'd0 },
        { 4'd1, 4'd1, 4'd0, 4'd2, 4'd5, 4'd3, 4'd3, 4'd6, 4'd6, 4'd4, 4'd3, 4'd1, 4'd3, 4'd6, 4'd3, 4'd3, 4'd6, 4'd3, 4'd4, 4'd3, 4'd5, 4'd4, 4'd0, 4'd3, 4'd2, 4'd2, 4'd5, 4'd3, 4'd5, 4'd6, 4'd0, 4'd0 },
        { 4'd1, 4'd5, 4'd0, 4'd0, 4'd3, 4'd2, 4'd5, 4'd4, 4'd3, 4'd3, 4'd2, 4'd0, 4'd3, 4'd5, 4'd5, 4'd3, 4'd5, 4'd5, 4'd3, 4'd5, 4'd3, 4'd0, 4'd1, 4'd2, 4'd2, 4'd3, 4'd3, 4'd6, 4'd2, 4'd5, 4'd6, 4'd1 },
        { 4'd2, 4'd1, 4'd5, 4'd0, 4'd3, 4'd2, 4'd3, 4'd5, 4'd5, 4'd1, 4'd0, 4'd1, 4'd1, 4'd1, 4'd3, 4'd6, 4'd2, 4'd3, 4'd2, 4'd2, 4'd1, 4'd0, 4'd2, 4'd2, 4'd2, 4'd5, 4'd5, 4'd5, 4'd5, 4'd5, 4'd6, 4'd1 },
        { 4'd3, 4'd2, 4'd3, 4'd0, 4'd0, 4'd1, 4'd2, 4'd3, 4'd3, 4'd2, 4'd1, 4'd4, 4'd6, 4'd0, 4'd1, 4'd2, 4'd1, 4'd2, 4'd1, 4'd1, 4'd0, 4'd2, 4'd2, 4'd3, 4'd5, 4'd3, 4'd5, 4'd5, 4'd3, 4'd2, 4'd3, 4'd1 },
        { 4'd2, 4'd2, 4'd3, 4'd5, 4'd7, 4'd7, 4'd3, 4'd5, 4'd3, 4'd0, 4'd3, 4'd2, 4'd3, 4'd4, 4'd4, 4'd0, 4'd2, 4'd1, 4'd0, 4'd0, 4'd3, 4'd2, 4'd3, 4'd2, 4'd1, 4'd2, 4'd5, 4'd3, 4'd2, 4'd2, 4'd2, 4'd2 },
        { 4'd1, 4'd3, 4'd2, 4'd3, 4'd0, 4'd1, 4'd3, 4'd3, 4'd0, 4'd2, 4'd5, 4'd2, 4'd2, 4'd3, 4'd5, 4'd3, 4'd1, 4'd0, 4'd1, 4'd3, 4'd2, 4'd2, 4'd3, 4'd2, 4'd2, 4'd1, 4'd3, 4'd2, 4'd2, 4'd3, 4'd3, 4'd2 },
        { 4'd3, 4'd3, 4'd1, 4'd1, 4'd5, 4'd1, 4'd7, 4'd7, 4'd0, 4'd2, 4'd3, 4'd5, 4'd3, 4'd2, 4'd3, 4'd4, 4'd0, 4'd1, 4'd2, 4'd2, 4'd3, 4'd2, 4'd3, 4'd3, 4'd2, 4'd3, 4'd2, 4'd3, 4'd2, 4'd2, 4'd1, 4'd1 },
        { 4'd2, 4'd1, 4'd3, 4'd1, 4'd3, 4'd7, 4'd0, 4'd1, 4'd2, 4'd3, 4'd2, 4'd3, 4'd2, 4'd2, 4'd3, 4'd6, 4'd1, 4'd0, 4'd1, 4'd1, 4'd3, 4'd1, 4'd1, 4'd2, 4'd3, 4'd3, 4'd3, 4'd2, 4'd1, 4'd1, 4'd0, 4'd1 },
        { 4'd1, 4'd2, 4'd3, 4'd2, 4'd2, 4'd0, 4'd7, 4'd0, 4'd1, 4'd1, 4'd2, 4'd3, 4'd2, 4'd2, 4'd2, 4'd3, 4'd5, 4'd1, 4'd0, 4'd1, 4'd1, 4'd3, 4'd2, 4'd3, 4'd2, 4'd2, 4'd1, 4'd1, 4'd1, 4'd3, 4'd1, 4'd0 },
        { 4'd2, 4'd3, 4'd1, 4'd0, 4'd0, 4'd1, 4'd0, 4'd1, 4'd3, 4'd2, 4'd2, 4'd2, 4'd2, 4'd5, 4'd5, 4'd3, 4'd3, 4'd6, 4'd0, 4'd0, 4'd1, 4'd2, 4'd3, 4'd3, 4'd1, 4'd1, 4'd1, 4'd0, 4'd0, 4'd6, 4'd3, 4'd1 },
        { 4'd0, 4'd1, 4'd2, 4'd3, 4'd4, 4'd6, 4'd4, 4'd0, 4'd1, 4'd0, 4'd1, 4'd2, 4'd1, 4'd3, 4'd3, 4'd2, 4'd3, 4'd5, 4'd3, 4'd0, 4'd1, 4'd2, 4'd3, 4'd1, 4'd0, 4'd2, 4'd3, 4'd2, 4'd2, 4'd3, 4'd4, 4'd2 },
        { 4'd2, 4'd2, 4'd3, 4'd2, 4'd2, 4'd5, 4'd3, 4'd5, 4'd5, 4'd0, 4'd2, 4'd3, 4'd2, 4'd2, 4'd2, 4'd2, 4'd2, 4'd3, 4'd2, 4'd0, 4'd1, 4'd1, 4'd0, 4'd2, 4'd3, 4'd2, 4'd2, 4'd3, 4'd3, 4'd5, 4'd4, 4'd2 },
        { 4'd1, 4'd3, 4'd2, 4'd2, 4'd3, 4'd3, 4'd3, 4'd3, 4'd4, 4'd0, 4'd0, 4'd2, 4'd2, 4'd3, 4'd2, 4'd3, 4'd3, 4'd1, 4'd0, 4'd1, 4'd2, 4'd0, 4'd2, 4'd1, 4'd2, 4'd1, 4'd3, 4'd2, 4'd2, 4'd3, 4'd6, 4'd3 },
        { 4'd2, 4'd3, 4'd2, 4'd3, 4'd5, 4'd2, 4'd5, 4'd5, 4'd3, 4'd5, 4'd4, 4'd1, 4'd2, 4'd0, 4'd1, 4'd0, 4'd0, 4'd0, 4'd3, 4'd4, 4'd5, 4'd1, 4'd1, 4'd3, 4'd1, 4'd1, 4'd3, 4'd5, 4'd2, 4'd2, 4'd5, 4'd2 },
        { 4'd3, 4'd2, 4'd3, 4'd5, 4'd2, 4'd3, 4'd5, 4'd3, 4'd3, 4'd6, 4'd6, 4'd0, 4'd1, 4'd1, 4'd0, 4'd3, 4'd3, 4'd6, 4'd6, 4'd3, 4'd3, 4'd5, 4'd4, 4'd5, 4'd3, 4'd1, 4'd2, 4'd5, 4'd3, 4'd5, 4'd3, 4'd5 },
        { 4'd3, 4'd3, 4'd2, 4'd4, 4'd5, 4'd2, 4'd3, 4'd4, 4'd6, 4'd3, 4'd4, 4'd2, 4'd2, 4'd0, 4'd3, 4'd2, 4'd6, 4'd3, 4'd5, 4'd4, 4'd5, 4'd3, 4'd5, 4'd3, 4'd6, 4'd1, 4'd3, 4'd3, 4'd5, 4'd3, 4'd3, 4'd5 },
        { 4'd2, 4'd1, 4'd2, 4'd3, 4'd3, 4'd3, 4'd2, 4'd2, 4'd5, 4'd3, 4'd2, 4'd4, 4'd1, 4'd2, 4'd2, 4'd3, 4'd5, 4'd3, 4'd3, 4'd3, 4'd4, 4'd3, 4'd3, 4'd3, 4'd5, 4'd1, 4'd1, 4'd1, 4'd2, 4'd1, 4'd5, 4'd2 },
        { 4'd3, 4'd2, 4'd2, 4'd2, 4'd5, 4'd3, 4'd3, 4'd2, 4'd3, 4'd5, 4'd4, 4'd5, 4'd0, 4'd2, 4'd3, 4'd3, 4'd5, 4'd3, 4'd5, 4'd3, 4'd3, 4'd3, 4'd5, 4'd6, 4'd0, 4'd0, 4'd0, 4'd1, 4'd1, 4'd2, 4'd1, 4'd0 },
        { 4'd1, 4'd2, 4'd1, 4'd2, 4'd3, 4'd3, 4'd3, 4'd3, 4'd2, 4'd2, 4'd3, 4'd4, 4'd0, 4'd2, 4'd2, 4'd3, 4'd5, 4'd5, 4'd3, 4'd3, 4'd5, 4'd5, 4'd0, 4'd0, 4'd5, 4'd3, 4'd5, 4'd0, 4'd0, 4'd1, 4'd0, 4'd0 },
        { 4'd2, 4'd1, 4'd3, 4'd1, 4'd2, 4'd2, 4'd3, 4'd2, 4'd2, 4'd3, 4'd2, 4'd4, 4'd2, 4'd3, 4'd2, 4'd2, 4'd3, 4'd2, 4'd3, 4'd0, 4'd0, 4'd0, 4'd0, 4'd5, 4'd3, 4'd5, 4'd6, 4'd4, 4'd1, 4'd0, 4'd0, 4'd2 },
        { 4'd1, 4'd1, 4'd2, 4'd3, 4'd1, 4'd5, 4'd5, 4'd3, 4'd2, 4'd2, 4'd3, 4'd5, 4'd1, 4'd2, 4'd1, 4'd1, 4'd1, 4'd1, 4'd0, 4'd0, 4'd2, 4'd3, 4'd2, 4'd3, 4'd3, 4'd2, 4'd2, 4'd3, 4'd4, 4'd4, 4'd5, 4'd0 },
        { 4'd1, 4'd2, 4'd3, 4'd1, 4'd3, 4'd2, 4'd4, 4'd2, 4'd3, 4'd2, 4'd2, 4'd4, 4'd5, 4'd1, 4'd2, 4'd3, 4'd2, 4'd1, 4'd0, 4'd5, 4'd5, 4'd2, 4'd2, 4'd3, 4'd2, 4'd3, 4'd5, 4'd3, 4'd3, 4'd3, 4'd5, 4'd0 },
        { 4'd2, 4'd1, 4'd2, 4'd2, 4'd2, 4'd2, 4'd5, 4'd5, 4'd5, 4'd3, 4'd3, 4'd3, 4'd4, 4'd0, 4'd0, 4'd0, 4'd1, 4'd0, 4'd0, 4'd3, 4'd3, 4'd3, 4'd5, 4'd2, 4'd2, 4'd2, 4'd3, 4'd3, 4'd5, 4'd2, 4'd3, 4'd4 },
        { 4'd1, 4'd2, 4'd1, 4'd2, 4'd1, 4'd2, 4'd2, 4'd3, 4'd5, 4'd3, 4'd2, 4'd3, 4'd5, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd1, 4'd3, 4'd2, 4'd3, 4'd5, 4'd1, 4'd2, 4'd3, 4'd3, 4'd5, 4'd5, 4'd3, 4'd2, 4'd6 },
        { 4'd2, 4'd1, 4'd2, 4'd1, 4'd2, 4'd2, 4'd3, 4'd2, 4'd3, 4'd5, 4'd6, 4'd5, 4'd5, 4'd0, 4'd4, 4'd0, 4'd3, 4'd2, 4'd1, 4'd3, 4'd1, 4'd2, 4'd1, 4'd2, 4'd3, 4'd3, 4'd2, 4'd5, 4'd5, 4'd3, 4'd1, 4'd3 },
        { 4'd3, 4'd1, 4'd1, 4'd2, 4'd2, 4'd1, 4'd2, 4'd2, 4'd3, 4'd2, 4'd3, 4'd3, 4'd0, 4'd2, 4'd5, 4'd2, 4'd1, 4'd1, 4'd3, 4'd1, 4'd1, 4'd3, 4'd3, 4'd1, 4'd2, 4'd3, 4'd3, 4'd3, 4'd2, 4'd2, 4'd2, 4'd2 },
        { 4'd2, 4'd0, 4'd0, 4'd1, 4'd1, 4'd3, 4'd3, 4'd3, 4'd2, 4'd3, 4'd3, 4'd0, 4'd0, 4'd2, 4'd6, 4'd5, 4'd3, 4'd2, 4'd1, 4'd2, 4'd3, 4'd1, 4'd2, 4'd2, 4'd2, 4'd2, 4'd2, 4'd2, 4'd2, 4'd3, 4'd2, 4'd1 },
        { 4'd2, 4'd0, 4'd1, 4'd0, 4'd1, 4'd2, 4'd1, 4'd2, 4'd3, 4'd3, 4'd0, 4'd2, 4'd2, 4'd3, 4'd3, 4'd3, 4'd2, 4'd3, 4'd2, 4'd0, 4'd2, 4'd2, 4'd1, 4'd2, 4'd3, 4'd3, 4'd0, 4'd1, 4'd0, 4'd1, 4'd1, 4'd1 },
        { 4'd1, 4'd1, 4'd0, 4'd1, 4'd0, 4'd1, 4'd1, 4'd1, 4'd2, 4'd0, 4'd0, 4'd2, 4'd3, 4'd2, 4'd1, 4'd1, 4'd0, 4'd1, 4'd1, 4'd1, 4'd1, 4'd0, 4'd0, 4'd0, 4'd0, 4'd1, 4'd0, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0 }
    };

    texture[3] = {
        { 4'd4, 4'd3, 4'd0, 4'd1, 4'd0, 4'd1, 4'd0, 4'd0, 4'd1, 4'd1, 4'd1, 4'd0, 4'd1, 4'd1, 4'd1, 4'd1, 4'd0, 4'd2, 4'd0, 4'd0, 4'd0, 4'd1, 4'd1, 4'd1, 4'd1, 4'd1, 4'd2, 4'd1, 4'd0, 4'd1, 4'd1, 4'd0 },
        { 4'd8, 4'd7, 4'd3, 4'd3, 4'd3, 4'd3, 4'd3, 4'd6, 4'd6, 4'd6, 4'd3, 4'd5, 4'd3, 4'd5, 4'd5, 4'd3, 4'd6, 4'd3, 4'd6, 4'd3, 4'd3, 4'd3, 4'd3, 4'd6, 4'd6, 4'd3, 4'd5, 4'd5, 4'd3, 4'd5, 4'd3, 4'd1 },
        { 4'd10, 4'd4, 4'd9, 4'd9, 4'd8, 4'd8, 4'd10, 4'd9, 4'd9, 4'd9, 4'd9, 4'd10, 4'd8, 4'd10, 4'd9, 4'd9, 4'd10, 4'd9, 4'd10, 4'd9, 4'd9, 4'd10, 4'd9, 4'd9, 4'd9, 4'd9, 4'd9, 4'd10, 4'd9, 4'd9, 4'd3, 4'd1 },
        { 4'd8, 4'd7, 4'd10, 4'd9, 4'd7, 4'd3, 4'd3, 4'd9, 4'd8, 4'd6, 4'd8, 4'd9, 4'd10, 4'd6, 4'd10, 4'd4, 4'd10, 4'd4, 4'd5, 4'd8, 4'd7, 4'd3, 4'd3, 4'd2, 4'd9, 4'd8, 4'd3, 4'd2, 4'd10, 4'd9, 4'd3, 4'd0 },
        { 4'd8, 4'd4, 4'd8, 4'd7, 4'd4, 4'd10, 4'd9, 4'd9, 4'd10, 4'd8, 4'd6, 4'd10, 4'd6, 4'd10, 4'd5, 4'd10, 4'd6, 4'd8, 4'd9, 4'd7, 4'd8, 4'd7, 4'd7, 4'd2, 4'd9, 4'd10, 4'd7, 4'd3, 4'd2, 4'd10, 4'd6, 4'd0 },
        { 4'd10, 4'd5, 4'd8, 4'd7, 4'd7, 4'd7, 4'd3, 4'd9, 4'd9, 4'd7, 4'd6, 4'd10, 4'd7, 4'd5, 4'd2, 4'd10, 4'd7, 4'd6, 4'd10, 4'd4, 4'd9, 4'd9, 4'd8, 4'd3, 4'd2, 4'd9, 4'd8, 4'd7, 4'd2, 4'd9, 4'd6, 4'd1 },
        { 4'd10, 4'd5, 4'd8, 4'd9, 4'd4, 4'd10, 4'd9, 4'd6, 4'd3, 4'd3, 4'd9, 4'd5, 4'd7, 4'd5, 4'd6, 4'd9, 4'd10, 4'd10, 4'd7, 4'd6, 4'd5, 4'd4, 4'd9, 4'd7, 4'd2, 4'd8, 4'd7, 4'd7, 4'd5, 4'd8, 4'd3, 4'd1 },
        { 4'd10, 4'd4, 4'd10, 4'd9, 4'd7, 4'd3, 4'd9, 4'd7, 4'd7, 4'd3, 4'd6, 4'd6, 4'd9, 4'd7, 4'd10, 4'd4, 4'd5, 4'd3, 4'd6, 4'd10, 4'd8, 4'd9, 4'd10, 4'd8, 4'd4, 4'd9, 4'd10, 4'd3, 4'd7, 4'd10, 4'd5, 4'd1 },
        { 4'd10, 4'd7, 4'd9, 4'd9, 4'd10, 4'd3, 4'd9, 4'd10, 4'd7, 4'd9, 4'd10, 4'd7, 4'd6, 4'd9, 4'd10, 4'd7, 4'd2, 4'd4, 4'd9, 4'd7, 4'd3, 4'd9, 4'd8, 4'd7, 4'd3, 4'd10, 4'd8, 4'd5, 4'd5, 4'd10, 4'd3, 4'd0 },
        { 4'd9, 4'd4, 4'd9, 4'd10, 4'd7, 4'd4, 4'd4, 4'd9, 4'd7, 4'd6, 4'd10, 4'd7, 4'd4, 4'd6, 4'd10, 4'd7, 4'd2, 4'd8, 4'd8, 4'd7, 4'd2, 4'd10, 4'd10, 4'd9, 4'd7, 4'd5, 4'd8, 4'd7, 4'd4, 4'd10, 4'd5, 4'd1 },
        { 4'd10, 4'd7, 4'd9, 4'd10, 4'd4, 4'd10, 4'd7, 4'd5, 4'd9, 4'd4, 4'd3, 4'd9, 4'd7, 4'd6, 4'd9, 4'd10, 4'd10, 4'd9, 4'd7, 4'd2, 4'd9, 4'd7, 4'd9, 4'd7, 4'd9, 4'd7, 4'd4, 4'd10, 4'd9, 4'd9, 4'd5, 4'd1 },
        { 4'd9, 4'd4, 4'd10, 4'd4, 4'd3, 4'd10, 4'd10, 4'd9, 4'd8, 4'd7, 4'd7, 4'd10, 4'd9, 4'd9, 4'd10, 4'd8, 4'd7, 4'd7, 4'd10, 4'd9, 4'd4, 4'd2, 4'd9, 4'd10, 4'd8, 4'd9, 4'd9, 4'd10, 4'd5, 4'd9, 4'd5, 4'd0 },
        { 4'd9, 4'd4, 4'd10, 4'd7, 4'd2, 4'd9, 4'd8, 4'd8, 4'd4, 4'd6, 4'd9, 4'd10, 4'd7, 4'd6, 4'd3, 4'd2, 4'd2, 4'd6, 4'd7, 4'd10, 4'd9, 4'd4, 4'd2, 4'd9, 4'd10, 4'd9, 4'd8, 4'd7, 4'd2, 4'd10, 4'd3, 4'd1 },
        { 4'd10, 4'd7, 4'd8, 4'd7, 4'd7, 4'd9, 4'd7, 4'd7, 4'd4, 4'd9, 4'd7, 4'd3, 4'd6, 4'd9, 4'd8, 4'd9, 4'd7, 4'd10, 4'd2, 4'd6, 4'd4, 4'd10, 4'd9, 4'd4, 4'd2, 4'd8, 4'd9, 4'd7, 4'd2, 4'd9, 4'd3, 4'd0 },
        { 4'd9, 4'd5, 4'd8, 4'd10, 4'd4, 4'd3, 4'd4, 4'd9, 4'd9, 4'd7, 4'd8, 4'd10, 4'd9, 4'd4, 4'd6, 4'd9, 4'd6, 4'd7, 4'd10, 4'd8, 4'd2, 4'd8, 4'd10, 4'd9, 4'd4, 4'd8, 4'd2, 4'd4, 4'd6, 4'd10, 4'd3, 4'd2 },
        { 4'd10, 4'd4, 4'd9, 4'd10, 4'd7, 4'd4, 4'd10, 4'd10, 4'd7, 4'd3, 4'd2, 4'd9, 4'd9, 4'd9, 4'd4, 4'd2, 4'd4, 4'd10, 4'd9, 4'd10, 4'd10, 4'd6, 4'd7, 4'd10, 4'd9, 4'd9, 4'd3, 4'd7, 4'd10, 4'd9, 4'd5, 4'd2 },
        { 4'd10, 4'd4, 4'd9, 4'd9, 4'd10, 4'd8, 4'd9, 4'd9, 4'd9, 4'd10, 4'd7, 4'd2, 4'd6, 4'd10, 4'd9, 4'd10, 4'd10, 4'd9, 4'd9, 4'd4, 4'd4, 4'd10, 4'd10, 4'd9, 4'd9, 4'd8, 4'd10, 4'd10, 4'd8, 4'd10, 4'd5, 4'd1 },
        { 4'd9, 4'd4, 4'd9, 4'd10, 4'd4, 4'd7, 4'd7, 4'd4, 4'd9, 4'd9, 4'd9, 4'd10, 4'd8, 4'd6, 4'd6, 4'd2, 4'd2, 4'd3, 4'd4, 4'd8, 4'd10, 4'd9, 4'd9, 4'd7, 4'd5, 4'd2, 4'd2, 4'd3, 4'd8, 4'd9, 4'd4, 4'd1 },
        { 4'd9, 4'd4, 4'd10, 4'd4, 4'd3, 4'd9, 4'd4, 4'd2, 4'd7, 4'd10, 4'd10, 4'd9, 4'd10, 4'd7, 4'd7, 4'd8, 4'd4, 4'd8, 4'd10, 4'd9, 4'd9, 4'd9, 4'd9, 4'd5, 4'd5, 4'd4, 4'd10, 4'd7, 4'd5, 4'd9, 4'd3, 4'd0 },
        { 4'd8, 4'd5, 4'd10, 4'd4, 4'd2, 4'd9, 4'd9, 4'd7, 4'd2, 4'd7, 4'd7, 4'd10, 4'd9, 4'd9, 4'd10, 4'd10, 4'd10, 4'd9, 4'd10, 4'd9, 4'd4, 4'd9, 4'd9, 4'd2, 4'd9, 4'd9, 4'd10, 4'd7, 4'd6, 4'd9, 4'd3, 4'd1 },
        { 4'd8, 4'd3, 4'd10, 4'd4, 4'd3, 4'd9, 4'd9, 4'd10, 4'd2, 4'd9, 4'd9, 4'd6, 4'd2, 4'd2, 4'd6, 4'd9, 4'd10, 4'd7, 4'd4, 4'd2, 4'd8, 4'd9, 4'd9, 4'd9, 4'd9, 4'd10, 4'd7, 4'd3, 4'd2, 4'd9, 4'd5, 4'd1 },
        { 4'd9, 4'd5, 4'd9, 4'd10, 4'd4, 4'd9, 4'd4, 4'd5, 4'd9, 4'd7, 4'd6, 4'd2, 4'd7, 4'd4, 4'd9, 4'd8, 4'd5, 4'd8, 4'd7, 4'd2, 4'd9, 4'd9, 4'd9, 4'd8, 4'd7, 4'd4, 4'd3, 4'd2, 4'd9, 4'd9, 4'd5, 4'd1 },
        { 4'd9, 4'd4, 4'd9, 4'd10, 4'd10, 4'd9, 4'd9, 4'd9, 4'd4, 4'd5, 4'd5, 4'd7, 4'd4, 4'd6, 4'd9, 4'd7, 4'd5, 4'd9, 4'd7, 4'd4, 4'd6, 4'd10, 4'd9, 4'd8, 4'd7, 4'd7, 4'd7, 4'd6, 4'd9, 4'd9, 4'd3, 4'd1 },
        { 4'd10, 4'd5, 4'd9, 4'd7, 4'd10, 4'd10, 4'd10, 4'd4, 4'd5, 4'd7, 4'd10, 4'd10, 4'd6, 4'd9, 4'd9, 4'd7, 4'd4, 4'd5, 4'd9, 4'd7, 4'd7, 4'd10, 4'd7, 4'd9, 4'd8, 4'd4, 4'd8, 4'd9, 4'd8, 4'd9, 4'd3, 4'd0 },
        { 4'd10, 4'd4, 4'd9, 4'd4, 4'd7, 4'd10, 4'd7, 4'd4, 4'd3, 4'd10, 4'd9, 4'd9, 4'd9, 4'd7, 4'd5, 4'd10, 4'd7, 4'd7, 4'd9, 4'd9, 4'd9, 4'd9, 4'd10, 4'd9, 4'd8, 4'd4, 4'd9, 4'd9, 4'd5, 4'd8, 4'd5, 4'd0 },
        { 4'd8, 4'd4, 4'd9, 4'd3, 4'd3, 4'd9, 4'd10, 4'd4, 4'd4, 4'd3, 4'd7, 4'd10, 4'd2, 4'd2, 4'd4, 4'd5, 4'd10, 4'd10, 4'd7, 4'd4, 4'd2, 4'd2, 4'd7, 4'd9, 4'd9, 4'd8, 4'd9, 4'd7, 4'd2, 4'd8, 4'd4, 4'd1 },
        { 4'd10, 4'd4, 4'd9, 4'd7, 4'd3, 4'd9, 4'd10, 4'd2, 4'd4, 4'd7, 4'd3, 4'd3, 4'd3, 4'd9, 4'd9, 4'd7, 4'd9, 4'd9, 4'd3, 4'd2, 4'd9, 4'd4, 4'd5, 4'd7, 4'd9, 4'd9, 4'd7, 4'd5, 4'd2, 4'd8, 4'd5, 4'd0 },
        { 4'd8, 4'd5, 4'd9, 4'd7, 4'd7, 4'd3, 4'd2, 4'd3, 4'd7, 4'd10, 4'd9, 4'd9, 4'd4, 4'd9, 4'd2, 4'd10, 4'd9, 4'd4, 4'd9, 4'd9, 4'd9, 4'd4, 4'd6, 4'd5, 4'd7, 4'd7, 4'd5, 4'd2, 4'd4, 4'd9, 4'd5, 4'd0 },
        { 4'd10, 4'd3, 4'd9, 4'd9, 4'd7, 4'd3, 4'd4, 4'd4, 4'd3, 4'd2, 4'd2, 4'd3, 4'd10, 4'd4, 4'd6, 4'd10, 4'd7, 4'd10, 4'd4, 4'd7, 4'd9, 4'd4, 4'd7, 4'd5, 4'd6, 4'd6, 4'd6, 4'd5, 4'd7, 4'd9, 4'd4, 4'd1 },
        { 4'd10, 4'd3, 4'd9, 4'd10, 4'd10, 4'd8, 4'd10, 4'd10, 4'd9, 4'd10, 4'd8, 4'd10, 4'd9, 4'd8, 4'd10, 4'd9, 4'd10, 4'd10, 4'd10, 4'd9, 4'd10, 4'd8, 4'd10, 4'd9, 4'd9, 4'd9, 4'd8, 4'd9, 4'd9, 4'd8, 4'd4, 4'd1 },
        { 4'd9, 4'd5, 4'd5, 4'd4, 4'd4, 4'd5, 4'd3, 4'd5, 4'd3, 4'd5, 4'd3, 4'd3, 4'd3, 4'd5, 4'd4, 4'd5, 4'd3, 4'd3, 4'd3, 4'd5, 4'd5, 4'd3, 4'd3, 4'd3, 4'd5, 4'd5, 4'd3, 4'd3, 4'd3, 4'd5, 4'd4, 4'd3 },
        { 4'd9, 4'd9, 4'd8, 4'd8, 4'd10, 4'd10, 4'd9, 4'd10, 4'd9, 4'd9, 4'd10, 4'd10, 4'd9, 4'd9, 4'd9, 4'd10, 4'd10, 4'd9, 4'd10, 4'd9, 4'd9, 4'd10, 4'd9, 4'd9, 4'd10, 4'd8, 4'd9, 4'd9, 4'd10, 4'd9, 4'd9, 4'd5 }
    };

    texture[4] = {
        { 4'd6, 4'd5, 4'd5, 4'd5, 4'd4, 4'd4, 4'd3, 4'd3, 4'd2, 4'd2, 4'd2, 4'd2, 4'd1, 4'd1, 4'd1, 4'd0, 4'd6, 4'd5, 4'd5, 4'd5, 4'd4, 4'd4, 4'd3, 4'd3, 4'd2, 4'd2, 4'd2, 4'd2, 4'd1, 4'd1, 4'd1, 4'd0 },
        { 4'd8, 4'd6, 4'd7, 4'd7, 4'd7, 4'd7, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd4, 4'd3, 4'd3, 4'd0, 4'd1, 4'd8, 4'd6, 4'd7, 4'd7, 4'd7, 4'd7, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd4, 4'd3, 4'd3, 4'd0, 4'd1 },
        { 4'd6, 4'd8, 4'd6, 4'd7, 4'd7, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd4, 4'd4, 4'd3, 4'd9, 4'd2, 4'd1, 4'd6, 4'd8, 4'd6, 4'd7, 4'd7, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd4, 4'd4, 4'd3, 4'd9, 4'd2, 4'd1 },
        { 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd5, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd3, 4'd9, 4'd2, 4'd3, 4'd1, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd5, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd3, 4'd9, 4'd2, 4'd3, 4'd1 },
        { 4'd10, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd3, 4'd9, 4'd2, 4'd3, 4'd2, 4'd1, 4'd10, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd3, 4'd9, 4'd2, 4'd3, 4'd2, 4'd1 },
        { 4'd10, 4'd6, 4'd8, 4'd8, 4'd8, 4'd6, 4'd7, 4'd7, 4'd4, 4'd3, 4'd0, 4'd2, 4'd2, 4'd2, 4'd3, 4'd1, 4'd10, 4'd6, 4'd8, 4'd8, 4'd8, 4'd6, 4'd7, 4'd7, 4'd4, 4'd3, 4'd0, 4'd2, 4'd2, 4'd2, 4'd3, 4'd1 },
        { 4'd10, 4'd6, 4'd8, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd4, 4'd0, 4'd2, 4'd2, 4'd3, 4'd3, 4'd4, 4'd2, 4'd10, 4'd6, 4'd8, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd4, 4'd0, 4'd2, 4'd2, 4'd3, 4'd3, 4'd4, 4'd2 },
        { 4'd10, 4'd8, 4'd6, 4'd8, 4'd8, 4'd6, 4'd8, 4'd6, 4'd0, 4'd2, 4'd4, 4'd4, 4'd4, 4'd4, 4'd3, 4'd2, 4'd10, 4'd8, 4'd6, 4'd8, 4'd8, 4'd6, 4'd8, 4'd6, 4'd0, 4'd2, 4'd4, 4'd4, 4'd4, 4'd4, 4'd3, 4'd2 },
        { 4'd10, 4'd6, 4'd6, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd3, 4'd4, 4'd4, 4'd3, 4'd4, 4'd3, 4'd4, 4'd3, 4'd10, 4'd6, 4'd6, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd3, 4'd4, 4'd4, 4'd3, 4'd4, 4'd3, 4'd4, 4'd3 },
        { 4'd10, 4'd6, 4'd6, 4'd8, 4'd6, 4'd6, 4'd7, 4'd7, 4'd7, 4'd2, 4'd3, 4'd4, 4'd3, 4'd4, 4'd4, 4'd3, 4'd10, 4'd6, 4'd6, 4'd8, 4'd6, 4'd6, 4'd7, 4'd7, 4'd7, 4'd2, 4'd3, 4'd4, 4'd3, 4'd4, 4'd4, 4'd3 },
        { 4'd10, 4'd6, 4'd8, 4'd6, 4'd6, 4'd7, 4'd7, 4'd8, 4'd7, 4'd7, 4'd2, 4'd3, 4'd4, 4'd4, 4'd3, 4'd3, 4'd10, 4'd6, 4'd8, 4'd6, 4'd6, 4'd7, 4'd7, 4'd8, 4'd7, 4'd7, 4'd2, 4'd3, 4'd4, 4'd4, 4'd3, 4'd3 },
        { 4'd10, 4'd6, 4'd6, 4'd6, 4'd7, 4'd8, 4'd8, 4'd7, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd4, 4'd4, 4'd3, 4'd10, 4'd6, 4'd6, 4'd6, 4'd7, 4'd8, 4'd8, 4'd7, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd4, 4'd4, 4'd3 },
        { 4'd10, 4'd6, 4'd6, 4'd7, 4'd6, 4'd8, 4'd8, 4'd8, 4'd7, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd4, 4'd3, 4'd10, 4'd6, 4'd6, 4'd7, 4'd6, 4'd8, 4'd8, 4'd8, 4'd7, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd4, 4'd3 },
        { 4'd10, 4'd6, 4'd7, 4'd6, 4'd8, 4'd8, 4'd8, 4'd8, 4'd7, 4'd8, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd3, 4'd10, 4'd6, 4'd7, 4'd6, 4'd8, 4'd8, 4'd8, 4'd8, 4'd7, 4'd8, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd3 },
        { 4'd10, 4'd8, 4'd6, 4'd8, 4'd8, 4'd8, 4'd8, 4'd7, 4'd8, 4'd7, 4'd8, 4'd7, 4'd8, 4'd7, 4'd2, 4'd3, 4'd10, 4'd8, 4'd6, 4'd8, 4'd8, 4'd8, 4'd8, 4'd7, 4'd8, 4'd7, 4'd8, 4'd7, 4'd8, 4'd7, 4'd2, 4'd3 },
        { 4'd8, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd6, 4'd6, 4'd6, 4'd6, 4'd6, 4'd6, 4'd8, 4'd4, 4'd8, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd6, 4'd6, 4'd6, 4'd6, 4'd6, 4'd6, 4'd8, 4'd4 },
        { 4'd6, 4'd5, 4'd5, 4'd5, 4'd4, 4'd4, 4'd3, 4'd3, 4'd2, 4'd2, 4'd2, 4'd2, 4'd1, 4'd1, 4'd1, 4'd0, 4'd6, 4'd5, 4'd5, 4'd5, 4'd4, 4'd4, 4'd3, 4'd3, 4'd2, 4'd2, 4'd2, 4'd2, 4'd1, 4'd1, 4'd1, 4'd0 },
        { 4'd8, 4'd6, 4'd7, 4'd7, 4'd7, 4'd7, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd4, 4'd3, 4'd3, 4'd0, 4'd1, 4'd8, 4'd6, 4'd7, 4'd7, 4'd7, 4'd7, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd4, 4'd3, 4'd3, 4'd0, 4'd1 },
        { 4'd6, 4'd8, 4'd6, 4'd7, 4'd7, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd4, 4'd4, 4'd3, 4'd9, 4'd2, 4'd1, 4'd6, 4'd8, 4'd6, 4'd7, 4'd7, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd4, 4'd4, 4'd3, 4'd9, 4'd2, 4'd1 },
        { 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd5, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd3, 4'd9, 4'd2, 4'd3, 4'd1, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd5, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd3, 4'd9, 4'd2, 4'd3, 4'd1 },
        { 4'd10, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd3, 4'd9, 4'd2, 4'd3, 4'd2, 4'd1, 4'd10, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd5, 4'd4, 4'd5, 4'd4, 4'd3, 4'd9, 4'd2, 4'd3, 4'd2, 4'd1 },
        { 4'd10, 4'd6, 4'd8, 4'd8, 4'd8, 4'd6, 4'd7, 4'd7, 4'd4, 4'd3, 4'd0, 4'd2, 4'd2, 4'd2, 4'd3, 4'd1, 4'd10, 4'd6, 4'd8, 4'd8, 4'd8, 4'd6, 4'd7, 4'd7, 4'd4, 4'd3, 4'd0, 4'd2, 4'd2, 4'd2, 4'd3, 4'd1 },
        { 4'd10, 4'd6, 4'd8, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd4, 4'd0, 4'd2, 4'd2, 4'd3, 4'd3, 4'd4, 4'd2, 4'd10, 4'd6, 4'd8, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd4, 4'd0, 4'd2, 4'd2, 4'd3, 4'd3, 4'd4, 4'd2 },
        { 4'd10, 4'd8, 4'd6, 4'd8, 4'd8, 4'd6, 4'd8, 4'd6, 4'd0, 4'd2, 4'd4, 4'd4, 4'd4, 4'd4, 4'd3, 4'd2, 4'd10, 4'd8, 4'd6, 4'd8, 4'd8, 4'd6, 4'd8, 4'd6, 4'd0, 4'd2, 4'd4, 4'd4, 4'd4, 4'd4, 4'd3, 4'd2 },
        { 4'd10, 4'd6, 4'd6, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd3, 4'd4, 4'd4, 4'd3, 4'd4, 4'd3, 4'd4, 4'd3, 4'd10, 4'd6, 4'd6, 4'd6, 4'd8, 4'd8, 4'd6, 4'd7, 4'd3, 4'd4, 4'd4, 4'd3, 4'd4, 4'd3, 4'd4, 4'd3 },
        { 4'd10, 4'd6, 4'd6, 4'd8, 4'd6, 4'd6, 4'd7, 4'd7, 4'd7, 4'd2, 4'd3, 4'd4, 4'd3, 4'd4, 4'd4, 4'd3, 4'd10, 4'd6, 4'd6, 4'd8, 4'd6, 4'd6, 4'd7, 4'd7, 4'd7, 4'd2, 4'd3, 4'd4, 4'd3, 4'd4, 4'd4, 4'd3 },
        { 4'd10, 4'd6, 4'd8, 4'd6, 4'd6, 4'd7, 4'd7, 4'd8, 4'd7, 4'd7, 4'd2, 4'd3, 4'd4, 4'd4, 4'd3, 4'd3, 4'd10, 4'd6, 4'd8, 4'd6, 4'd6, 4'd7, 4'd7, 4'd8, 4'd7, 4'd7, 4'd2, 4'd3, 4'd4, 4'd4, 4'd3, 4'd3 },
        { 4'd10, 4'd6, 4'd6, 4'd6, 4'd7, 4'd8, 4'd8, 4'd7, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd4, 4'd4, 4'd3, 4'd10, 4'd6, 4'd6, 4'd6, 4'd7, 4'd8, 4'd8, 4'd7, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd4, 4'd4, 4'd3 },
        { 4'd10, 4'd6, 4'd6, 4'd7, 4'd6, 4'd8, 4'd8, 4'd8, 4'd7, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd4, 4'd3, 4'd10, 4'd6, 4'd6, 4'd7, 4'd6, 4'd8, 4'd8, 4'd8, 4'd7, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd4, 4'd3 },
        { 4'd10, 4'd6, 4'd7, 4'd6, 4'd8, 4'd8, 4'd8, 4'd8, 4'd7, 4'd8, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd3, 4'd10, 4'd6, 4'd7, 4'd6, 4'd8, 4'd8, 4'd8, 4'd8, 4'd7, 4'd8, 4'd7, 4'd7, 4'd7, 4'd2, 4'd4, 4'd3 },
        { 4'd10, 4'd8, 4'd6, 4'd8, 4'd8, 4'd8, 4'd8, 4'd7, 4'd8, 4'd7, 4'd8, 4'd7, 4'd8, 4'd7, 4'd2, 4'd3, 4'd10, 4'd8, 4'd6, 4'd8, 4'd8, 4'd8, 4'd8, 4'd7, 4'd8, 4'd7, 4'd8, 4'd7, 4'd8, 4'd7, 4'd2, 4'd3 },
        { 4'd8, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd6, 4'd6, 4'd6, 4'd6, 4'd6, 4'd6, 4'd8, 4'd4, 4'd8, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd10, 4'd6, 4'd6, 4'd6, 4'd6, 4'd6, 4'd6, 4'd8, 4'd4 }
    };

    texture[5] = {
        { 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0 },
        { 4'd1, 4'd3, 4'd3, 4'd1, 4'd0, 4'd5, 4'd1, 4'd2, 4'd2, 4'd2, 4'd1, 4'd3, 4'd1, 4'd2, 4'd0, 4'd6, 4'd5, 4'd5, 4'd5, 4'd4, 4'd0, 4'd1, 4'd1, 4'd3, 4'd2, 4'd1, 4'd0, 4'd2, 4'd3, 4'd2, 4'd1, 4'd0 },
        { 4'd4, 4'd7, 4'd7, 4'd1, 4'd0, 4'd7, 4'd5, 4'd7, 4'd5, 4'd5, 4'd7, 4'd4, 4'd5, 4'd1, 4'd0, 4'd4, 4'd4, 4'd4, 4'd6, 4'd5, 4'd0, 4'd6, 4'd5, 4'd5, 4'd5, 4'd1, 4'd6, 4'd7, 4'd5, 4'd5, 4'd3, 4'd0 },
        { 4'd6, 4'd4, 4'd7, 4'd3, 4'd0, 4'd7, 4'd4, 4'd4, 4'd7, 4'd7, 4'd4, 4'd6, 4'd7, 4'd1, 4'd0, 4'd8, 4'd4, 4'd8, 4'd4, 4'd7, 4'd0, 4'd4, 4'd6, 4'd4, 4'd5, 4'd1, 4'd6, 4'd6, 4'd7, 4'd5, 4'd3, 4'd0 },
        { 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd8, 4'd0, 4'd0, 4'd6, 4'd0, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd0, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0 },
        { 4'd8, 4'd6, 4'd7, 4'd5, 4'd5, 4'd7, 4'd4, 4'd0, 4'd5, 4'd1, 4'd5, 4'd3, 4'd2, 4'd0, 4'd5, 4'd1, 4'd3, 4'd1, 4'd2, 4'd5, 4'd3, 4'd2, 4'd0, 4'd5, 4'd1, 4'd5, 4'd1, 4'd2, 4'd1, 4'd2, 4'd0, 4'd6 },
        { 4'd4, 4'd4, 4'd4, 4'd4, 4'd6, 4'd6, 4'd5, 4'd0, 4'd7, 4'd4, 4'd7, 4'd7, 4'd1, 4'd0, 4'd4, 4'd7, 4'd7, 4'd7, 4'd4, 4'd7, 4'd7, 4'd1, 4'd0, 4'd4, 4'd4, 4'd7, 4'd7, 4'd4, 4'd5, 4'd2, 4'd0, 4'd6 },
        { 4'd8, 4'd4, 4'd6, 4'd6, 4'd8, 4'd4, 4'd7, 4'd8, 4'd4, 4'd7, 4'd4, 4'd4, 4'd1, 4'd8, 4'd4, 4'd7, 4'd4, 4'd4, 4'd4, 4'd7, 4'd4, 4'd5, 4'd6, 4'd4, 4'd4, 4'd7, 4'd4, 4'd5, 4'd5, 4'd3, 4'd0, 4'd6 },
        { 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd8, 4'd0, 4'd8, 4'd0, 4'd8, 4'd8, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd0, 4'd6, 4'd0, 4'd0, 4'd6, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0 },
        { 4'd5, 4'd1, 4'd5, 4'd3, 4'd2, 4'd3, 4'd2, 4'd1, 4'd5, 4'd0, 4'd4, 4'd7, 4'd7, 4'd7, 4'd4, 4'd6, 4'd5, 4'd1, 4'd2, 4'd1, 4'd2, 4'd1, 4'd1, 4'd6, 4'd5, 4'd1, 4'd1, 4'd1, 4'd5, 4'd1, 4'd3, 4'd0 },
        { 4'd4, 4'd6, 4'd7, 4'd7, 4'd4, 4'd7, 4'd4, 4'd7, 4'd1, 4'd0, 4'd4, 4'd4, 4'd4, 4'd4, 4'd7, 4'd0, 4'd6, 4'd6, 4'd4, 4'd4, 4'd4, 4'd5, 4'd5, 4'd0, 4'd6, 4'd4, 4'd7, 4'd7, 4'd5, 4'd5, 4'd1, 4'd0 },
        { 4'd6, 4'd4, 4'd6, 4'd4, 4'd7, 4'd4, 4'd7, 4'd4, 4'd5, 4'd0, 4'd6, 4'd4, 4'd4, 4'd8, 4'd7, 4'd0, 4'd4, 4'd7, 4'd4, 4'd6, 4'd4, 4'd7, 4'd5, 4'd0, 4'd4, 4'd6, 4'd7, 4'd4, 4'd7, 4'd5, 4'd1, 4'd0 },
        { 4'd0, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd0, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0 },
        { 4'd5, 4'd5, 4'd5, 4'd1, 4'd1, 4'd5, 4'd0, 4'd5, 4'd5, 4'd1, 4'd2, 4'd3, 4'd2, 4'd0, 4'd5, 4'd2, 4'd3, 4'd1, 4'd5, 4'd0, 4'd8, 4'd6, 4'd7, 4'd7, 4'd5, 4'd5, 4'd5, 4'd7, 4'd4, 4'd7, 4'd0, 4'd6 },
        { 4'd7, 4'd4, 4'd4, 4'd7, 4'd7, 4'd1, 4'd0, 4'd7, 4'd4, 4'd7, 4'd7, 4'd7, 4'd1, 4'd0, 4'd7, 4'd4, 4'd7, 4'd7, 4'd1, 4'd0, 4'd8, 4'd8, 4'd4, 4'd4, 4'd4, 4'd6, 4'd4, 4'd8, 4'd6, 4'd7, 4'd0, 4'd6 },
        { 4'd4, 4'd4, 4'd7, 4'd4, 4'd7, 4'd5, 4'd6, 4'd4, 4'd6, 4'd7, 4'd4, 4'd7, 4'd1, 4'd0, 4'd4, 4'd7, 4'd4, 4'd7, 4'd1, 4'd0, 4'd6, 4'd4, 4'd4, 4'd4, 4'd4, 4'd8, 4'd4, 4'd4, 4'd4, 4'd7, 4'd0, 4'd8 },
        { 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd0, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0 },
        { 4'd5, 4'd5, 4'd1, 4'd1, 4'd2, 4'd0, 4'd1, 4'd5, 4'd1, 4'd5, 4'd1, 4'd2, 4'd0, 4'd2, 4'd5, 4'd5, 4'd2, 4'd2, 4'd1, 4'd1, 4'd5, 4'd0, 4'd5, 4'd1, 4'd1, 4'd3, 4'd5, 4'd3, 4'd2, 4'd2, 4'd3, 4'd0 },
        { 4'd7, 4'd4, 4'd4, 4'd7, 4'd1, 4'd0, 4'd4, 4'd4, 4'd7, 4'd4, 4'd7, 4'd1, 4'd0, 4'd7, 4'd7, 4'd4, 4'd7, 4'd7, 4'd4, 4'd7, 4'd1, 4'd0, 4'd7, 4'd4, 4'd7, 4'd7, 4'd4, 4'd4, 4'd7, 4'd5, 4'd1, 4'd0 },
        { 4'd4, 4'd7, 4'd7, 4'd4, 4'd1, 4'd0, 4'd7, 4'd4, 4'd7, 4'd7, 4'd7, 4'd1, 4'd0, 4'd4, 4'd4, 4'd7, 4'd7, 4'd4, 4'd7, 4'd7, 4'd5, 4'd6, 4'd7, 4'd7, 4'd4, 4'd4, 4'd7, 4'd7, 4'd4, 4'd5, 4'd1, 4'd0 },
        { 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd0, 4'd0, 4'd0, 4'd6, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0 },
        { 4'd7, 4'd7, 4'd5, 4'd7, 4'd5, 4'd5, 4'd5, 4'd7, 4'd7, 4'd0, 4'd5, 4'd1, 4'd5, 4'd1, 4'd2, 4'd2, 4'd1, 4'd5, 4'd0, 4'd5, 4'd1, 4'd2, 4'd1, 4'd2, 4'd5, 4'd6, 4'd5, 4'd1, 4'd3, 4'd1, 4'd0, 4'd6 },
        { 4'd6, 4'd4, 4'd4, 4'd6, 4'd4, 4'd4, 4'd4, 4'd4, 4'd7, 4'd0, 4'd4, 4'd4, 4'd4, 4'd7, 4'd4, 4'd7, 4'd7, 4'd2, 4'd0, 4'd4, 4'd7, 4'd7, 4'd7, 4'd7, 4'd3, 4'd0, 4'd4, 4'd7, 4'd5, 4'd2, 4'd0, 4'd6 },
        { 4'd8, 4'd4, 4'd8, 4'd4, 4'd6, 4'd6, 4'd6, 4'd4, 4'd8, 4'd0, 4'd7, 4'd4, 4'd4, 4'd4, 4'd7, 4'd4, 4'd7, 4'd1, 4'd0, 4'd6, 4'd4, 4'd6, 4'd4, 4'd7, 4'd1, 4'd0, 4'd6, 4'd4, 4'd5, 4'd1, 4'd0, 4'd6 },
        { 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd6, 4'd0, 4'd0, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0 },
        { 4'd5, 4'd5, 4'd5, 4'd1, 4'd1, 4'd5, 4'd0, 4'd5, 4'd1, 4'd5, 4'd1, 4'd3, 4'd2, 4'd1, 4'd1, 4'd3, 4'd3, 4'd2, 4'd2, 4'd1, 4'd5, 4'd0, 4'd8, 4'd7, 4'd5, 4'd7, 4'd7, 4'd0, 4'd1, 4'd2, 4'd1, 4'd0 },
        { 4'd7, 4'd4, 4'd6, 4'd4, 4'd7, 4'd1, 4'd6, 4'd4, 4'd7, 4'd7, 4'd4, 4'd4, 4'd4, 4'd4, 4'd7, 4'd4, 4'd7, 4'd7, 4'd4, 4'd7, 4'd1, 4'd0, 4'd4, 4'd4, 4'd4, 4'd4, 4'd5, 4'd0, 4'd4, 4'd5, 4'd2, 4'd0 },
        { 4'd4, 4'd7, 4'd4, 4'd6, 4'd4, 4'd1, 4'd0, 4'd6, 4'd4, 4'd7, 4'd4, 4'd6, 4'd4, 4'd4, 4'd4, 4'd4, 4'd4, 4'd7, 4'd6, 4'd4, 4'd1, 4'd0, 4'd8, 4'd4, 4'd8, 4'd8, 4'd6, 4'd0, 4'd6, 4'd7, 4'd1, 4'd0 },
        { 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd6, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0 },
        { 4'd7, 4'd5, 4'd1, 4'd2, 4'd2, 4'd1, 4'd1, 4'd0, 4'd5, 4'd1, 4'd2, 4'd1, 4'd1, 4'd1, 4'd2, 4'd5, 4'd2, 4'd1, 4'd0, 4'd8, 4'd6, 4'd7, 4'd5, 4'd5, 4'd4, 4'd0, 4'd5, 4'd1, 4'd2, 4'd3, 4'd6, 4'd0 },
        { 4'd4, 4'd7, 4'd4, 4'd4, 4'd4, 4'd7, 4'd1, 4'd0, 4'd4, 4'd4, 4'd7, 4'd7, 4'd4, 4'd7, 4'd4, 4'd4, 4'd7, 4'd1, 4'd0, 4'd4, 4'd4, 4'd4, 4'd4, 4'd7, 4'd5, 4'd0, 4'd6, 4'd4, 4'd4, 4'd1, 4'd6, 4'd0 },
        { 4'd6, 4'd6, 4'd6, 4'd6, 4'd6, 4'd6, 4'd7, 4'd0, 4'd6, 4'd6, 4'd6, 4'd6, 4'd7, 4'd6, 4'd6, 4'd6, 4'd6, 4'd4, 4'd0, 4'd8, 4'd4, 4'd4, 4'd4, 4'd8, 4'd7, 4'd0, 4'd6, 4'd6, 4'd6, 4'd4, 4'd6, 4'd0 }
    };

    texture[6] = {
        { 4'd8, 4'd3, 4'd3, 4'd1, 4'd0, 4'd1, 4'd1, 4'd3, 4'd2, 4'd7, 4'd3, 4'd6, 4'd3, 4'd2, 4'd3, 4'd1, 4'd1, 4'd5, 4'd0, 4'd1, 4'd0, 4'd1, 4'd1, 4'd1, 4'd3, 4'd3, 4'd4, 4'd3, 4'd3, 4'd2, 4'd1, 4'd0 },
        { 4'd3, 4'd2, 4'd1, 4'd0, 4'd5, 4'd0, 4'd0, 4'd1, 4'd1, 4'd3, 4'd2, 4'd9, 4'd3, 4'd2, 4'd2, 4'd1, 4'd1, 4'd0, 4'd1, 4'd1, 4'd5, 4'd3, 4'd3, 4'd3, 4'd2, 4'd2, 4'd3, 4'd1, 4'd2, 4'd9, 4'd1, 4'd1 },
        { 4'd3, 4'd1, 4'd1, 4'd0, 4'd1, 4'd1, 4'd0, 4'd5, 4'd0, 4'd1, 4'd2, 4'd7, 4'd9, 4'd3, 4'd3, 4'd1, 4'd2, 4'd1, 4'd0, 4'd5, 4'd1, 4'd1, 4'd3, 4'd4, 4'd3, 4'd1, 4'd1, 4'd5, 4'd3, 4'd4, 4'd3, 4'd1 },
        { 4'd1, 4'd9, 4'd1, 4'd2, 4'd3, 4'd8, 4'd1, 4'd1, 4'd5, 4'd0, 4'd1, 4'd3, 4'd6, 4'd10, 4'd1, 4'd1, 4'd3, 4'd2, 4'd1, 4'd0, 4'd5, 4'd3, 4'd4, 4'd3, 4'd2, 4'd8, 4'd8, 4'd0, 4'd9, 4'd9, 4'd10, 4'd3 },
        { 4'd7, 4'd3, 4'd8, 4'd9, 4'd3, 4'd2, 4'd1, 4'd8, 4'd0, 4'd1, 4'd1, 4'd5, 4'd2, 4'd9, 4'd3, 4'd3, 4'd8, 4'd2, 4'd3, 4'd0, 4'd1, 4'd11, 4'd5, 4'd5, 4'd3, 4'd3, 4'd2, 4'd5, 4'd0, 4'd3, 4'd4, 4'd1 },
        { 4'd6, 4'd5, 4'd5, 4'd4, 4'd9, 4'd3, 4'd8, 4'd2, 4'd1, 4'd0, 4'd5, 4'd5, 4'd3, 4'd9, 4'd3, 4'd4, 4'd9, 4'd6, 4'd11, 4'd2, 4'd0, 4'd1, 4'd3, 4'd4, 4'd6, 4'd10, 4'd3, 4'd3, 4'd0, 4'd1, 4'd3, 4'd3 },
        { 4'd2, 4'd3, 4'd3, 4'd3, 4'd4, 4'd5, 4'd5, 4'd3, 4'd2, 4'd1, 4'd3, 4'd1, 4'd5, 4'd5, 4'd3, 4'd3, 4'd5, 4'd11, 4'd3, 4'd2, 4'd3, 4'd0, 4'd2, 4'd3, 4'd5, 4'd5, 4'd9, 4'd3, 4'd8, 4'd2, 4'd4, 4'd1 },
        { 4'd1, 4'd3, 4'd2, 4'd3, 4'd3, 4'd5, 4'd5, 4'd8, 4'd5, 4'd1, 4'd7, 4'd2, 4'd2, 4'd1, 4'd1, 4'd2, 4'd2, 4'd10, 4'd5, 4'd8, 4'd8, 4'd3, 4'd3, 4'd5, 4'd5, 4'd3, 4'd3, 4'd4, 4'd3, 4'd1, 4'd5, 4'd0 },
        { 4'd0, 4'd1, 4'd0, 4'd0, 4'd1, 4'd3, 4'd4, 4'd9, 4'd5, 4'd6, 4'd4, 4'd8, 4'd3, 4'd2, 4'd3, 4'd3, 4'd11, 4'd6, 4'd3, 4'd3, 4'd1, 4'd8, 4'd2, 4'd0, 4'd2, 4'd7, 4'd3, 4'd5, 4'd5, 4'd3, 4'd2, 4'd5 },
        { 4'd5, 4'd5, 4'd0, 4'd2, 4'd2, 4'd3, 4'd9, 4'd2, 4'd3, 4'd5, 4'd3, 4'd4, 4'd5, 4'd5, 4'd3, 4'd9, 4'd3, 4'd3, 4'd8, 4'd1, 4'd1, 4'd5, 4'd1, 4'd0, 4'd5, 4'd5, 4'd1, 4'd7, 4'd3, 4'd5, 4'd3, 4'd1 },
        { 4'd0, 4'd1, 4'd1, 4'd8, 4'd3, 4'd5, 4'd9, 4'd3, 4'd1, 4'd7, 4'd2, 4'd3, 4'd4, 4'd3, 4'd4, 4'd3, 4'd0, 4'd0, 4'd0, 4'd6, 4'd0, 4'd0, 4'd5, 4'd1, 4'd2, 4'd1, 4'd1, 4'd2, 4'd3, 4'd6, 4'd7, 4'd0 },
        { 4'd1, 4'd1, 4'd3, 4'd3, 4'd11, 4'd10, 4'd3, 4'd2, 4'd7, 4'd1, 4'd1, 4'd3, 4'd8, 4'd6, 4'd0, 4'd2, 4'd6, 4'd0, 4'd0, 4'd8, 4'd3, 4'd8, 4'd0, 4'd1, 4'd7, 4'd3, 4'd2, 4'd3, 4'd8, 4'd5, 4'd3, 4'd5 },
        { 4'd1, 4'd6, 4'd3, 4'd11, 4'd9, 4'd8, 4'd3, 4'd1, 4'd2, 4'd5, 4'd1, 4'd3, 4'd9, 4'd3, 4'd8, 4'd0, 4'd6, 4'd0, 4'd4, 4'd4, 4'd8, 4'd1, 4'd1, 4'd3, 4'd7, 4'd5, 4'd6, 4'd6, 4'd9, 4'd3, 4'd1, 4'd1 },
        { 4'd2, 4'd6, 4'd6, 4'd10, 4'd11, 4'd4, 4'd3, 4'd1, 4'd5, 4'd0, 4'd8, 4'd4, 4'd10, 4'd9, 4'd11, 4'd6, 4'd4, 4'd4, 4'd1, 4'd3, 4'd8, 4'd3, 4'd2, 4'd2, 4'd3, 4'd2, 4'd3, 4'd3, 4'd5, 4'd1, 4'd1, 4'd5 },
        { 4'd2, 4'd3, 4'd6, 4'd9, 4'd10, 4'd11, 4'd11, 4'd9, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd10, 4'd6, 4'd6, 4'd4, 4'd2, 4'd6, 4'd2, 4'd4, 4'd4, 4'd3, 4'd2, 4'd0, 4'd1, 4'd2, 4'd8, 4'd5, 4'd3, 4'd3, 4'd1 },
        { 4'd3, 4'd4, 4'd5, 4'd3, 4'd2, 4'd3, 4'd6, 4'd9, 4'd11, 4'd9, 4'd5, 4'd4, 4'd6, 4'd11, 4'd6, 4'd9, 4'd6, 4'd10, 4'd6, 4'd5, 4'd9, 4'd3, 4'd8, 4'd2, 4'd5, 4'd0, 4'd1, 4'd8, 4'd3, 4'd4, 4'd7, 4'd3 },
        { 4'd3, 4'd5, 4'd2, 4'd1, 4'd6, 4'd1, 4'd11, 4'd3, 4'd3, 4'd8, 4'd0, 4'd4, 4'd6, 4'd8, 4'd6, 4'd6, 4'd10, 4'd9, 4'd9, 4'd3, 4'd4, 4'd6, 4'd1, 4'd1, 4'd2, 4'd5, 4'd0, 4'd1, 4'd1, 4'd6, 4'd8, 4'd7 },
        { 4'd3, 4'd5, 4'd4, 4'd1, 4'd5, 4'd1, 4'd9, 4'd1, 4'd2, 4'd3, 4'd6, 4'd1, 4'd4, 4'd4, 4'd2, 4'd8, 4'd3, 4'd9, 4'd8, 4'd3, 4'd8, 4'd4, 4'd3, 4'd1, 4'd1, 4'd5, 4'd1, 4'd6, 4'd11, 4'd9, 4'd6, 4'd4 },
        { 4'd6, 4'd4, 4'd5, 4'd3, 4'd1, 4'd5, 4'd6, 4'd0, 4'd5, 4'd1, 4'd5, 4'd0, 4'd1, 4'd5, 4'd1, 4'd4, 4'd4, 4'd1, 4'd3, 4'd2, 4'd1, 4'd5, 4'd4, 4'd1, 4'd5, 4'd1, 4'd3, 4'd10, 4'd9, 4'd6, 4'd8, 4'd5 },
        { 4'd3, 4'd6, 4'd4, 4'd3, 4'd4, 4'd3, 4'd5, 4'd5, 4'd5, 4'd5, 4'd5, 4'd1, 4'd8, 4'd1, 4'd0, 4'd1, 4'd5, 4'd0, 4'd1, 4'd5, 4'd0, 4'd5, 4'd5, 4'd1, 4'd3, 4'd11, 4'd9, 4'd11, 4'd9, 4'd2, 4'd8, 4'd2 },
        { 4'd1, 4'd3, 4'd7, 4'd3, 4'd4, 4'd4, 4'd5, 4'd3, 4'd3, 4'd8, 4'd3, 4'd5, 4'd8, 4'd3, 4'd2, 4'd5, 4'd1, 4'd3, 4'd1, 4'd3, 4'd8, 4'd3, 4'd3, 4'd3, 4'd4, 4'd9, 4'd3, 4'd8, 4'd11, 4'd3, 4'd2, 4'd0 },
        { 4'd1, 4'd5, 4'd0, 4'd1, 4'd3, 4'd7, 4'd4, 4'd5, 4'd9, 4'd11, 4'd4, 4'd3, 4'd3, 4'd2, 4'd2, 4'd2, 4'd3, 4'd6, 4'd3, 4'd8, 4'd6, 4'd6, 4'd4, 4'd5, 4'd3, 4'd5, 4'd2, 4'd1, 4'd9, 4'd1, 4'd1, 4'd1 },
        { 4'd1, 4'd3, 4'd1, 4'd5, 4'd1, 4'd3, 4'd3, 4'd5, 4'd4, 4'd3, 4'd5, 4'd5, 4'd6, 4'd6, 4'd7, 4'd3, 4'd9, 4'd10, 4'd11, 4'd11, 4'd9, 4'd9, 4'd3, 4'd2, 4'd8, 4'd3, 4'd1, 4'd5, 4'd8, 4'd11, 4'd5, 4'd5 },
        { 4'd3, 4'd3, 4'd4, 4'd5, 4'd1, 4'd2, 4'd2, 4'd4, 4'd6, 4'd8, 4'd2, 4'd8, 4'd3, 4'd10, 4'd3, 4'd4, 4'd10, 4'd11, 4'd9, 4'd4, 4'd9, 4'd2, 4'd3, 4'd2, 4'd3, 4'd1, 4'd5, 4'd0, 4'd5, 4'd11, 4'd1, 4'd0 },
        { 4'd5, 4'd2, 4'd8, 4'd4, 4'd8, 4'd5, 4'd8, 4'd3, 4'd9, 4'd3, 4'd2, 4'd3, 4'd3, 4'd6, 4'd6, 4'd4, 4'd3, 4'd2, 4'd3, 4'd11, 4'd11, 4'd9, 4'd0, 4'd1, 4'd0, 4'd5, 4'd0, 4'd5, 4'd1, 4'd3, 4'd1, 4'd0 },
        { 4'd0, 4'd1, 4'd3, 4'd3, 4'd4, 4'd6, 4'd3, 4'd4, 4'd5, 4'd5, 4'd1, 4'd1, 4'd2, 4'd3, 4'd0, 4'd0, 4'd0, 4'd1, 4'd3, 4'd3, 4'd10, 4'd9, 4'd3, 4'd3, 4'd5, 4'd1, 4'd1, 4'd2, 4'd1, 4'd5, 4'd1, 4'd5 },
        { 4'd1, 4'd2, 4'd1, 4'd8, 4'd3, 4'd5, 4'd3, 4'd5, 4'd5, 4'd8, 4'd1, 4'd5, 4'd5, 4'd1, 4'd2, 4'd0, 4'd1, 4'd5, 4'd2, 4'd3, 4'd9, 4'd5, 4'd8, 4'd1, 4'd1, 4'd7, 4'd8, 4'd5, 4'd5, 4'd2, 4'd0, 4'd1 },
        { 4'd3, 4'd2, 4'd5, 4'd1, 4'd5, 4'd5, 4'd4, 4'd3, 4'd3, 4'd1, 4'd5, 4'd1, 4'd0, 4'd0, 4'd1, 4'd2, 4'd3, 4'd1, 4'd3, 4'd6, 4'd5, 4'd8, 4'd3, 4'd1, 4'd2, 4'd3, 4'd8, 4'd1, 4'd1, 4'd5, 4'd1, 4'd1 },
        { 4'd4, 4'd3, 4'd8, 4'd3, 4'd4, 4'd4, 4'd9, 4'd3, 4'd1, 4'd2, 4'd1, 4'd1, 4'd3, 4'd3, 4'd8, 4'd5, 4'd5, 4'd9, 4'd11, 4'd5, 4'd0, 4'd4, 4'd4, 4'd9, 4'd3, 4'd8, 4'd1, 4'd1, 4'd3, 4'd7, 4'd3, 4'd2 },
        { 4'd8, 4'd4, 4'd4, 4'd11, 4'd9, 4'd3, 4'd3, 4'd1, 4'd0, 4'd1, 4'd2, 4'd3, 4'd3, 4'd4, 4'd9, 4'd3, 4'd2, 4'd3, 4'd10, 4'd5, 4'd3, 4'd3, 4'd3, 4'd5, 4'd3, 4'd3, 4'd5, 4'd3, 4'd4, 4'd5, 4'd3, 4'd4 },
        { 4'd3, 4'd3, 4'd8, 4'd3, 4'd8, 4'd3, 4'd1, 4'd2, 4'd1, 4'd3, 4'd3, 4'd3, 4'd8, 4'd6, 4'd5, 4'd2, 4'd3, 4'd1, 4'd8, 4'd5, 4'd1, 4'd3, 4'd2, 4'd2, 4'd9, 4'd2, 4'd3, 4'd4, 4'd3, 4'd6, 4'd5, 4'd9 },
        { 4'd2, 4'd3, 4'd2, 4'd2, 4'd1, 4'd0, 4'd1, 4'd2, 4'd3, 4'd5, 4'd8, 4'd8, 4'd4, 4'd9, 4'd3, 4'd1, 4'd1, 4'd0, 4'd1, 4'd0, 4'd5, 4'd1, 4'd3, 4'd2, 4'd4, 4'd6, 4'd4, 4'd8, 4'd3, 4'd2, 4'd3, 4'd3 }
    };


    recode_lut [0] = {
        { 8'd16,  8'd16,  8'd16  },
        { 8'd32,  8'd32,  8'd32  },
        { 8'd176, 8'd176, 8'd176 },
        { 8'd160, 8'd160, 8'd160 },
        { 8'd112, 8'd112, 8'd112 },
        { 8'd0,   8'd160, 8'd80  },
        { 8'd144, 8'd144, 8'd144 },
        { 8'd128, 8'd128, 8'd128 },
        { 8'd0,   8'd192, 8'd96  },
        { 8'd0,   8'd64,  8'd32  },
        { 8'd80,  8'd80,  8'd80  },
        { 8'd0,   8'd96,  8'd48  },
        { 8'd64,  8'd64,  8'd64  },
        { 8'd96,  8'd96,  8'd96  },
        { 8'd0,   8'd48,  8'd24  }
    };

    recode_lut [1] = {
        { 8'd32,  8'd0, 8'd0 },
        { 8'd48,  8'd0, 8'd0 },
        { 8'd128, 8'd0, 8'd0 },
        { 8'd192, 8'd0, 8'd0 },
        { 8'd224, 8'd0, 8'd0 },
        { 8'd160, 8'd0, 8'd0 },
        { 8'd96,  8'd0, 8'd0 },
        { 8'd64,  8'd0, 8'd0 },
        { 8'd255, 8'd0, 8'd0 },
        { 8'd0,   8'd0, 8'd0 },
        { 8'd0,   8'd0, 8'd0 },
        { 8'd0,   8'd0, 8'd0 },
        { 8'd0,   8'd0, 8'd0 },
        { 8'd0,   8'd0, 8'd0 },
        { 8'd0,   8'd0, 8'd0 }
    };

    recode_lut [2] = {
        { 8'd24,  8'd24,  8'd0 },
        { 8'd64,  8'd48,  8'd0 },
        { 8'd96,  8'd72,  8'd0 },
        { 8'd128, 8'd96,  8'd0 },
        { 8'd192, 8'd144, 8'd0 },
        { 8'd160, 8'd120, 8'd0 },
        { 8'd224, 8'd168, 8'd0 },
        { 8'd48,  8'd36,  8'd0 },
        { 8'd0,   8'd0,   8'd0 },
        { 8'd0,   8'd0,   8'd0 },
        { 8'd0,   8'd0,   8'd0 },
        { 8'd0,   8'd0,   8'd0 },
        { 8'd0,   8'd0,   8'd0 },
        { 8'd0,   8'd0,   8'd0 },
        { 8'd0,   8'd0,   8'd0 }
    };

    recode_lut [3] = {
        { 8'd160, 8'd160, 8'd160 },
        { 8'd176, 8'd176, 8'd176 },
        { 8'd144, 8'd144, 8'd144 },
        { 8'd112, 8'd112, 8'd112 },
        { 8'd80,  8'd80,  8'd80  },
        { 8'd96,  8'd96,  8'd96  },
        { 8'd128, 8'd128, 8'd128 },
        { 8'd64,  8'd64,  8'd64  },
        { 8'd48,  8'd48,  8'd48  },
        { 8'd16,  8'd16,  8'd16  },
        { 8'd32,  8'd32,  8'd32  },
        { 8'd0,   8'd0,   8'd0   },
        { 8'd0,   8'd0,   8'd0   },
        { 8'd0,   8'd0,   8'd0   },
        { 8'd0,   8'd0,   8'd0   }
    };

    recode_lut [4] = {
        { 8'd128, 8'd255, 8'd255 },
        { 8'd0,   8'd255, 8'd255 },
        { 8'd0,   8'd224, 8'd224 },
        { 8'd0,   8'd192, 8'd192 },
        { 8'd0,   8'd160, 8'd160 },
        { 8'd0,   8'd128, 8'd128 },
        { 8'd0,   8'd48,  8'd48  },
        { 8'd0,   8'd96,  8'd96  },
        { 8'd0,   8'd64,  8'd64  },
        { 8'd192, 8'd255, 8'd255 },
        { 8'd0,   8'd32,  8'd32  },
        { 8'd0,   8'd0,   8'd0   },
        { 8'd0,   8'd0,   8'd0   },
        { 8'd0,   8'd0,   8'd0   },
        { 8'd0,   8'd0,   8'd0   }
    };

    recode_lut [5] = {
        { 8'd16,  8'd16,  8'd16  },
        { 8'd112, 8'd112, 8'd112 },
        { 8'd144, 8'd144, 8'd144 },
        { 8'd128, 8'd128, 8'd128 },
        { 8'd64,  8'd64,  8'd64  },
        { 8'd96,  8'd96,  8'd96  },
        { 8'd48,  8'd48,  8'd48  },
        { 8'd80,  8'd80,  8'd80  },
        { 8'd32,  8'd32,  8'd32  },
        { 8'd0,   8'd0,   8'd0   },
        { 8'd0,   8'd0,   8'd0   },
        { 8'd0,   8'd0,   8'd0   },
        { 8'd0,   8'd0,   8'd0   },
        { 8'd0,   8'd0,   8'd0   },
        { 8'd0,   8'd0,   8'd0   }
    };

    recode_lut [6] = {
        { 8'd32,  8'd0,   8'd0 },
        { 8'd64,  8'd0,   8'd0 },
        { 8'd96,  8'd0,   8'd0 },
        { 8'd128, 8'd0,   8'd0 },
        { 8'd255, 8'd0,   8'd0 },
        { 8'd48,  8'd0,   8'd0 },
        { 8'd255, 8'd64,  8'd0 },
        { 8'd160, 8'd0,   8'd0 },
        { 8'd192, 8'd0,   8'd0 },
        { 8'd255, 8'd128, 8'd0 },
        { 8'd255, 8'd255, 8'd0 },
        { 8'd255, 8'd192, 8'd0 },
        { 8'd0,   8'd0,   8'd0 },
        { 8'd0,   8'd0,   8'd0 },
        { 8'd0,   8'd0,   8'd0 }
    };

end


endmodule

`resetall
