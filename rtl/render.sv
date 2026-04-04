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
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam int unsigned     W_BUF_DATA        = W_NUM_TEX                        +  // texture
                                                1                                +  // tex_shade
                                                W_TEX_SIDE                       +  // tex_x
                                                TEX_STEP_W_INT + TEX_STEP_W_FRAC +  // tex_step
                                                (W_V_RES - 1);                      // tex_height (LSB is not used)

localparam int unsigned     N_PIPE_STAGES     = 6;                                  // 0 to 5
localparam int unsigned     W_VALIDS          = N_PIPE_STAGES - 1;                  // Don't need valid for the last stage

localparam int unsigned     BUF_DEPTH         = FRAME_WIDTH * 2;
localparam int unsigned     W_BUF_ADDR        = $clog2(BUF_DEPTH);

localparam int              ALIGN_SHIFT       = W_V_RES - (W_TEX_SIDE + 1);
localparam int unsigned     ALIGN_EXT_PAD     = W_TEX_SIDE + 1 + TEX_STEP_W_FRAC - W_V_RES;
localparam [W_TEX_SIDE-1:0] TEX_Y_MAX         = 2**W_TEX_SIDE - 1;

localparam int unsigned     RECODE_LUT_SIZE   = NUM_TEX * RECODE_LUT_LEN;
localparam int unsigned     W_RECODE_LUT_ADDR = $clog2(RECODE_LUT_SIZE);

localparam int unsigned     W_PX              = W_COLOR * 3;
localparam int unsigned     TEXTURES_SIZE     = NUM_TEX * TEX_SIDE * TEX_SIDE;
localparam int unsigned     W_TEXTURES_ADDR   = $clog2(TEXTURES_SIZE);
localparam logic [W_PX-1:0] SHADE_MASK        = { { W_COLOR     {1'b1} }, 1'b0,
                                                  { W_COLOR - 1 {1'b1} }, 1'b0,
                                                  { W_COLOR - 1 {1'b1} } };

localparam logic [W_PX-1:0] BG_TOP_COLOR      = { 8'd20, 8'd20, 8'd20 };
localparam logic [W_PX-1:0] BG_BOTTOM_COLOR   = { 8'd48, 8'd48, 8'd48 };


// ----------------------------------------------------------------------------
// Local types declaration
// ----------------------------------------------------------------------------

typedef logic [-1:-signed'(TEX_STEP_W_FRAC)] tex_frac_fixp_t;
typedef logic [W_RECODE_LUT_ADDR-1:0]        recode_lut_addr_t;
typedef logic [W_TEXTURES_ADDR-1:0]          textures_addr_t;

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
tex_frac_fixp_t        step_frac;
tex_frac_fixp_t        height_ext;
tex_frac_fixp_t        temp_mult;

// Stage 2
align_fixp_t           tex_align_ext;
align_fixp_t           tex_step_ext;
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
logic [W_NUM_TEX-1:0]  texture_p3;
logic                  in_texture_p3;
logic                  tex_shade_p3;
logic                  bg_top_p3;
logic [W_PX_CODE-1:0]  px_code_p3;

// Stage 4
logic                  in_texture_p4;
logic                  tex_shade_p4;
logic                  bg_top_p4;
logic [W_PX-1:0]       color_p4;

// Stage 5
logic [W_PX-1:0]       color_next;

// ROMs
logic [W_PX_CODE-1:0]  textures   [TEXTURES_SIZE];
logic [W_PX-1:0]       recode_lut [RECODE_LUT_SIZE];
recode_lut_addr_t      recode_lut_addr;
textures_addr_t        textures_addr;

// ----------------------------------------------------------------------------
// ROM initialization
// ----------------------------------------------------------------------------

// Cocotb runs simulation from sim_build directory, so it has different
// relative path to the memfiles
`ifdef SIMULATION

    initial begin
        $readmemh("../memfiles/textures.mem", textures);
        $readmemh("../memfiles/recode_lut.mem", recode_lut);
    end

`else

    initial begin
        $readmemh("memfiles/textures.mem", textures);
        $readmemh("memfiles/recode_lut.mem", recode_lut);
    end

`endif


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
// Every bit of valids shift register corresponds to validity of data on each
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
    tex_step_ext     = `FIXP_CAST(tex_step_p1, align_fixp_t);
    tex_align_scaled = `FIXP_MULT(tex_align_ext, tex_step_ext);

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
// Get pixel color code from the texture synchronous ROM
// ----------------------------------------------------------------------------

assign textures_addr = (textures_addr_t'(texture_p2) * textures_addr_t'(TEX_SIDE*TEX_SIDE)) +
                       (textures_addr_t'(tex_y_p2)   * textures_addr_t'(TEX_SIDE         )) +
                        textures_addr_t'(tex_x_p2);

always_ff @(posedge clk)
    if (valids[2]) begin
        in_texture_p3 <= in_texture_p2;
        texture_p3    <= texture_p2;
        tex_shade_p3  <= tex_shade_p2;
        bg_top_p3     <= bg_top_p2;

        // ROM
        px_code_p3    <= textures[textures_addr];
    end

// ----------------------------------------------------------------------------
// Stage 4
// Get pixel color value from compressed color code
// ----------------------------------------------------------------------------

assign recode_lut_addr = ((recode_lut_addr_t'(texture_p3)      *
                           recode_lut_addr_t'(RECODE_LUT_LEN)) +
                           recode_lut_addr_t'(px_code_p3));

always_ff @(posedge clk)
    if (valids[3]) begin
        in_texture_p4 <= in_texture_p3;
        tex_shade_p4  <= tex_shade_p3;
        bg_top_p4     <= bg_top_p3;

        // ROM
        color_p4      <= recode_lut[recode_lut_addr];
    end

// ----------------------------------------------------------------------------
// Stage 5
// Calculate RGB value based on color value and shade
// ----------------------------------------------------------------------------

always_comb begin
    if (bg_top_p4)
        color_next = BG_TOP_COLOR;
    else
        color_next = BG_BOTTOM_COLOR;

    if (in_texture_p4)
        if (tex_shade_p4)
            color_next = (color_p4 >> 1) & SHADE_MASK;
        else
            color_next = color_p4;
end

always_ff @(posedge clk)
    if (valids[4]) begin
        { red_o, green_o, blue_o } <= color_next;
    end

endmodule

`resetall
