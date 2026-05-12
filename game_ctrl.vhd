-- =============================================================================
-- game_ctrl.vhd
-- Two-player fighting game controller.
-- All screen state transitions consolidated into one process.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity game_ctrl is
  port (
    clk              : in  std_logic;
    rst              : in  std_logic;
    btn              : in  std_logic_vector(3 downto 0);
    jc               : in  std_logic_vector(2 downto 0);
    fb_addr          : in  std_logic_vector(17 downto 0);
    fb_data          : out std_logic_vector(7 downto 0);
    vcount           : in  std_logic_vector(9 downto 0);
    p1_addr          : out std_logic_vector(11 downto 0);
    p1_data          : in  std_logic_vector(7 downto 0);
    atk_addr         : out std_logic_vector(11 downto 0);
    atk_data         : in  std_logic_vector(7 downto 0);
    fb_wea           : out std_logic_vector(0 downto 0);
    fb_addra         : out std_logic_vector(17 downto 0);
    fb_dina          : out std_logic_vector(7 downto 0);
    fb_doutb         : in  std_logic_vector(7 downto 0);
    game_active      : out std_logic
  );
end entity game_ctrl;

architecture rtl of game_ctrl is

  -- =========================================================================
  -- Constants
  -- =========================================================================
  constant SCREEN_W      : integer := 480;
  constant SCREEN_H      : integer := 480;
  constant FB_SIZE       : integer := SCREEN_W * SCREEN_H;
  constant SPR_W         : integer := 64;
  constant SPR_H         : integer := 64;
  constant GROUND_Y      : integer := 416;
  constant P1_START_X    : integer := 10;
  constant P2_START_X    : integer := SCREEN_W - SPR_W - 10;
  constant MOVE_SPEED    : integer := 1;
  constant TRANSPARENT   : std_logic_vector(7 downto 0) := x"00";
  constant TICK_COUNT    : integer := 2_083_333;
  constant ATTACK_CYCLES : integer := 62_500_000;
  constant WIN_CYCLES    : integer := 375_000_000;

  constant HURT_H_IDLE   : integer := 64;
  constant HURT_H_ATTACK : integer := 64;
  constant HURT_W_IDLE   : integer := 56;
  constant HURT_W_ATTACK : integer := 64;
  constant HURT_Y_IDLE   : integer := (SPR_H - HURT_H_IDLE) / 2;
  constant HURT_Y_ATTACK : integer := (SPR_H - HURT_H_ATTACK) / 2;
  constant HIT_W         : integer := 20;
  constant HIT_H         : integer := 32;
  constant HIT_INSET     : integer := 1;  -- pixels inward from sprite edge
  constant HIT_Y_OFS     : integer := (SPR_H - HIT_H) / 2;

  constant HURTBOX_COLOR : std_logic_vector(7 downto 0) := x"AA";
  constant HITBOX_COLOR  : std_logic_vector(7 downto 0) := x"55";

  constant CHAR_W        : integer := 20;
  constant CHAR_H        : integer := 28;
  constant TEXT_Y        : integer := 200;
  constant TEXT_LEN      : integer := 14;
  constant TEXT_X        : integer := (SCREEN_W - TEXT_LEN * CHAR_W) / 2;

  -- =========================================================================
  -- Font
  -- =========================================================================
  type glyph_t is array(0 to 6) of std_logic_vector(4 downto 0);
  type font_t  is array(0 to 23) of glyph_t;

  constant FONT : font_t := (
    0  => ("01110","10001","10001","10001","10001","10001","01110"),
    1  => ("00100","01100","00100","00100","00100","00100","01110"),
    2  => ("01110","10001","00001","00010","00100","01000","11111"),
    3  => ("11111","00010","00100","00010","00001","10001","01110"),
    4  => ("00010","00110","01010","10010","11111","00010","00010"),
    5  => ("11111","10000","11110","00001","00001","10001","01110"),
    6  => ("00110","01000","10000","11110","10001","10001","01110"),
    7  => ("11111","00001","00010","00100","01000","01000","01000"),
    8  => ("01110","10001","10001","01110","10001","10001","01110"),
    9  => ("01110","10001","10001","01111","00001","00010","01100"),
    10 => ("11110","10001","10001","11110","10000","10000","10000"), -- P
    11 => ("01100","00100","00100","00100","00100","00100","01110"), -- l
    12 => ("00000","01110","10001","10011","10101","11001","01110"), -- a
    13 => ("10001","10001","10001","01111","00001","00010","11100"), -- y
    14 => ("01110","10001","10000","11110","10000","10001","01110"), -- e
    15 => ("11110","10001","10001","11110","10100","10010","10001"), -- r
    16 => ("00000","00000","00000","00000","00000","00000","00000"), -- space
    17 => ("10001","10001","10001","10101","10101","11011","10001"), -- W
    18 => ("00100","00000","00100","00100","00100","00100","00100"), -- i
    19 => ("10001","11001","10101","10011","10001","10001","10001"), -- n
    20 => ("01111","10000","10000","01110","00001","00001","11110"), -- s
    21 => ("00100","00100","00100","00100","00000","00000","00100"), -- !
    22 => ("00100","01100","00100","00100","00100","00100","01110"), -- 1
    23 => ("01110","10001","00001","00110","01000","10000","11111")  -- 2
  );

  type text_t is array(0 to 13) of integer range 0 to 23;
  constant P1_WIN_TEXT : text_t := (10,11,12,13,14,15,16,22,16,17,18,19,20,21);
  constant P2_WIN_TEXT : text_t := (10,11,12,13,14,15,16,23,16,17,18,19,20,21);

  -- =========================================================================
  -- Screen state
  -- =========================================================================
  type screen_t is (SCREEN_MENU, SCREEN_GAME, SCREEN_WIN);
  signal screen        : screen_t := SCREEN_MENU;
  signal first_frame   : std_logic := '1';
  signal winner        : integer range 1 to 2 := 1;
  signal win_timer     : integer range 0 to WIN_CYCLES := 0;

  -- =========================================================================
  -- Blanking
  -- =========================================================================
  signal in_blanking   : std_logic;
  signal blanking_r    : std_logic := '0';
  signal blanking_rise : std_logic;

  -- =========================================================================
  -- Debounce
  -- =========================================================================
  constant DEB_MAX     : integer := 1_250_000;
  type deb_cnt_t is array(0 to 4) of integer range 0 to DEB_MAX;
  signal deb_cnt       : deb_cnt_t := (others => 0);
  signal deb_sync      : std_logic_vector(4 downto 0) := (others => '0');
  signal deb_out       : std_logic_vector(4 downto 0) := (others => '0');
  signal deb_prev      : std_logic_vector(4 downto 0) := (others => '0');
  signal btn_rising    : std_logic_vector(4 downto 0);
  signal btn3_r        : std_logic := '0';
  signal jc2_r         : std_logic := '0';
  signal jc2_rising    : std_logic;

  -- =========================================================================
  -- Game tick
  -- =========================================================================
  signal tick_cnt      : integer range 0 to TICK_COUNT - 1 := 0;
  signal game_tick     : std_logic := '0';

  -- =========================================================================
  -- Player state
  -- =========================================================================
  signal p1_x          : integer range 0 to SCREEN_W - 1 := P1_START_X;
  signal p2_x          : integer range 0 to SCREEN_W - 1 := P2_START_X;
  signal prev_p1_x     : integer range 0 to SCREEN_W - 1 := P1_START_X;
  signal prev_p2_x     : integer range 0 to SCREEN_W - 1 := P2_START_X;
  signal p1_atk_timer  : integer range 0 to ATTACK_CYCLES := 0;
  signal p2_atk_timer  : integer range 0 to ATTACK_CYCLES := 0;
  signal p1_attacking  : std_logic := '0';
  signal p2_attacking  : std_logic := '0';

  -- =========================================================================
  -- Blitter FSM
  -- =========================================================================
  type blit_state_t is (
    BL_IDLE,
    BL_FULL_CLEAR,
    BL_ERASE_P1_FETCH,      BL_ERASE_P1_NEXT_COL, BL_ERASE_P1_NEXT_ROW,
    BL_ERASE_P2_FETCH,      BL_ERASE_P2_NEXT_COL, BL_ERASE_P2_NEXT_ROW,
    BL_SP1_FETCH,           BL_SP1_WRITE,          BL_SP1_NEXT_COL, BL_SP1_NEXT_ROW,
    BL_SP2_FETCH,           BL_SP2_WRITE,          BL_SP2_NEXT_COL, BL_SP2_NEXT_ROW,
    BL_WIN_FALLEN_FETCH,    BL_WIN_FALLEN_WRITE,
    BL_WIN_FALLEN_NEXT_COL, BL_WIN_FALLEN_NEXT_ROW,
    BL_WIN_WINNER_FETCH,    BL_WIN_WINNER_WRITE,
    BL_WIN_WINNER_NEXT_COL, BL_WIN_WINNER_NEXT_ROW,
    BL_WIN_TEXT,
    BL_DBG_HURT1,      BL_DBG_HURT1_NEXT_COL, BL_DBG_HURT1_NEXT_ROW,
    BL_DBG_HURT2,      BL_DBG_HURT2_NEXT_COL, BL_DBG_HURT2_NEXT_ROW,
    BL_DBG_HIT1,       BL_DBG_HIT1_NEXT_COL,  BL_DBG_HIT1_NEXT_ROW,
    BL_DBG_HIT2,       BL_DBG_HIT2_NEXT_COL,  BL_DBG_HIT2_NEXT_ROW,
    BL_DONE
  );
  signal blit_state    : blit_state_t := BL_IDLE;

  signal clear_cnt     : integer range 0 to FB_SIZE - 1 := 0;
  signal bl_col        : integer range 0 to 63 := 0;
  signal bl_row        : integer range 0 to 63 := 0;
  signal bl_p1_x       : integer range 0 to SCREEN_W - 1 := P1_START_X;
  signal bl_p2_x       : integer range 0 to SCREEN_W - 1 := P2_START_X;
  signal bl_prev_p1_x  : integer range 0 to SCREEN_W - 1 := P1_START_X;
  signal bl_prev_p2_x  : integer range 0 to SCREEN_W - 1 := P2_START_X;
  signal bl_p1_atk     : std_logic := '0';
  signal bl_p2_atk     : std_logic := '0';
  signal bl_winner     : integer range 1 to 2 := 1;

  signal blit_p2       : std_logic := '0';
  signal rom_col       : integer range 0 to 63;
  signal rom_addr      : std_logic_vector(11 downto 0);
  signal fallen_addr   : std_logic_vector(11 downto 0);
  signal cur_data      : std_logic_vector(7 downto 0);

  signal blit_we       : std_logic := '0';
  signal blit_addr     : std_logic_vector(17 downto 0) := (others => '0');
  signal blit_din      : std_logic_vector(7 downto 0)  := (others => '0');
  signal clear_done    : std_logic := '0';  -- pulses when full clear finishes

  signal txt_char      : integer range 0 to TEXT_LEN - 1 := 0;
  signal txt_col       : integer range 0 to CHAR_W - 1 := 0;
  signal txt_row       : integer range 0 to CHAR_H - 1 := 0;

  signal debug_mode    : std_logic := '0';
  signal dbg_col       : integer range 0 to 63 := 0;
  signal dbg_row       : integer range 0 to 63 := 0;
  signal bl_p1_hurt_top: integer range 0 to SCREEN_H - 1 := GROUND_Y;
  signal bl_p1_hurt_h  : integer range 0 to SPR_H := HURT_H_IDLE;
  signal bl_p1_hurt_w  : integer range 0 to SPR_W := HURT_W_IDLE;
  signal bl_p2_hurt_top: integer range 0 to SCREEN_H - 1 := GROUND_Y;
  signal bl_p2_hurt_h  : integer range 0 to SPR_H := HURT_H_IDLE;
  signal bl_p2_hurt_w  : integer range 0 to SPR_W := HURT_W_IDLE;

  -- =========================================================================
  -- Helper functions
  -- =========================================================================
  function p1_hits_p2(p1x, p2x : integer; p2_atk : std_logic) return boolean is
    variable atk_x1, atk_x2, atk_y1, atk_y2 : integer;  -- P1 hitbox
    variable def_x1, def_x2, def_y1, def_y2 : integer;  -- P2 hurtbox
  begin
    -- P1 hitbox: inset from P1's right edge
    atk_x1 := p1x + SPR_W - HIT_INSET - HIT_W;
    atk_x2 := p1x + SPR_W - HIT_INSET;
    atk_y1 := GROUND_Y + HIT_Y_OFS;
    atk_y2 := GROUND_Y + HIT_Y_OFS + HIT_H;
    -- P2 hurtbox (right-anchored)
    def_x2 := p2x + SPR_W;
    if p2_atk = '1' then
      def_x1 := p2x + SPR_W - HURT_W_ATTACK;
      def_y1 := GROUND_Y + HURT_Y_ATTACK;
      def_y2 := GROUND_Y + HURT_Y_ATTACK + HURT_H_ATTACK;
    else
      def_x1 := p2x + SPR_W - HURT_W_IDLE;
      def_y1 := GROUND_Y + HURT_Y_IDLE;
      def_y2 := GROUND_Y + HURT_Y_IDLE + HURT_H_IDLE;
    end if;
    -- AABB overlap
    if atk_x2 > def_x1 and atk_x1 < def_x2 and
       atk_y2 > def_y1 and atk_y1 < def_y2 then
      return true;
    end if;
    return false;
  end function;

  function p2_hits_p1(p1x, p2x : integer; p1_atk : std_logic) return boolean is
    variable atk_x1, atk_x2, atk_y1, atk_y2 : integer;  -- P2 hitbox
    variable def_x1, def_x2, def_y1, def_y2 : integer;  -- P1 hurtbox
  begin
    -- P2 hitbox: inset from P2's left edge
    atk_x1 := p2x + HIT_INSET;
    atk_x2 := p2x + HIT_INSET + HIT_W;
    atk_y1 := GROUND_Y + HIT_Y_OFS;
    atk_y2 := GROUND_Y + HIT_Y_OFS + HIT_H;
    -- P1 hurtbox
    def_x1 := p1x;
    def_x2 := p1x + SPR_W;
    if p1_atk = '1' then
      def_y1 := GROUND_Y + HURT_Y_ATTACK;
      def_y2 := GROUND_Y + HURT_Y_ATTACK + HURT_H_ATTACK;
    else
      def_y1 := GROUND_Y + HURT_Y_IDLE;
      def_y2 := GROUND_Y + HURT_Y_IDLE + HURT_H_IDLE;
    end if;
    -- AABB overlap
    if atk_x2 > def_x1 and atk_x1 < def_x2 and
       atk_y2 > def_y1 and atk_y1 < def_y2 then
      return true;
    end if;
    return false;
  end function;

begin

  -- Framebuffer Port A
  fb_wea   <= (0 => blit_we);
  fb_addra <= blit_addr;
  fb_dina  <= blit_din;

  -- ROM address
  rom_col     <= (SPR_W - 1 - bl_col) when blit_p2 = '1' else bl_col;
  rom_addr    <= std_logic_vector(to_unsigned(bl_row * SPR_W + rom_col, 12));
  fallen_addr <= std_logic_vector(to_unsigned(bl_col * SPR_W + (SPR_W - 1 - bl_row), 12));

  -- p1_addr mux
  p1_addr  <= fallen_addr when (blit_state = BL_WIN_FALLEN_FETCH or
                                blit_state = BL_WIN_FALLEN_WRITE)
              else rom_addr;
  atk_addr <= rom_addr;

  -- Sprite data mux
  cur_data <= atk_data when (blit_p2 = '0' and bl_p1_atk = '1') or
                            (blit_p2 = '1' and bl_p2_atk = '1')
              else p1_data;

  game_active <= '0' when screen = SCREEN_MENU else '1';

  -- Display reads from framebuffer
  process(clk)
  begin
    if rising_edge(clk) then
      fb_data <= fb_doutb;
    end if;
  end process;

  -- Blanking
  in_blanking   <= '1' when to_integer(unsigned(vcount)) >= 480 else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      blanking_r <= in_blanking;
    end if;
  end process;
  blanking_rise <= '1' when in_blanking = '1' and blanking_r = '0' else '0';

  -- jc(2) edge detect
  process(clk)
  begin
    if rising_edge(clk) then
      jc2_r <= jc(2);
    end if;
  end process;
  jc2_rising <= '1' when jc(2) = '1' and jc2_r = '0' else '0';

  -- =========================================================================
  -- Debouncer
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      deb_sync(0) <= jc(0);
      deb_sync(1) <= jc(1);
      deb_sync(2) <= btn(0);
      deb_sync(3) <= btn(1);
      deb_sync(4) <= btn(2);
      btn3_r      <= btn(3);
      for i in 0 to 4 loop
        if deb_sync(i) = deb_out(i) then
          deb_cnt(i) <= 0;
        else
          if deb_cnt(i) = DEB_MAX then
            deb_out(i) <= deb_sync(i);
            deb_cnt(i) <= 0;
          else
            deb_cnt(i) <= deb_cnt(i) + 1;
          end if;
        end if;
      end loop;
      deb_prev <= deb_out;
    end if;
  end process;
  btn_rising <= deb_out and not deb_prev;

  -- =========================================================================
  -- Debug toggle
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        debug_mode <= '0';
      elsif btn(3) = '1' and btn3_r = '0' then
        debug_mode <= not debug_mode;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- 60 Hz game tick
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        tick_cnt  <= 0;
        game_tick <= '0';
      else
        if tick_cnt = TICK_COUNT - 1 then
          tick_cnt  <= 0;
          game_tick <= '1';
        else
          tick_cnt  <= tick_cnt + 1;
          game_tick <= '0';
        end if;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- MASTER GAME STATE PROCESS
  -- Handles: screen transitions, attack timers, hit detection,
  --          win timer, player movement - all in one process
  --          so screen signal has exactly one driver.
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        screen       <= SCREEN_MENU;
        winner       <= 1;
        win_timer    <= 0;
        p1_x         <= P1_START_X;
        p2_x         <= P2_START_X;
        p1_atk_timer <= 0;
        p2_atk_timer <= 0;
        p1_attacking <= '0';
        p2_attacking <= '0';

      else
        case screen is

          -- -------------------------------------------------------------------
          when SCREEN_MENU =>
            win_timer    <= 0;
            p1_attacking <= '0';
            p2_attacking <= '0';
            p1_atk_timer <= 0;
            p2_atk_timer <= 0;
            if btn_rising(4) = '1' then
              screen <= SCREEN_GAME;
              p1_x   <= P1_START_X;
              p2_x   <= P2_START_X;
            end if;

          when SCREEN_GAME =>
            if p1_attacking = '1' then
              if p1_atk_timer > 0 then
                p1_atk_timer <= p1_atk_timer - 1;
              else
                p1_attacking <= '0';
              end if;
            elsif btn_rising(4) = '1' then
              p1_attacking <= '1';
              p1_atk_timer <= ATTACK_CYCLES;
              if p1_hits_p2(p1_x, p2_x, p2_attacking) then
                winner    <= 1;
                screen    <= SCREEN_WIN;
                win_timer <= 0;
              end if;
            end if;

            if p2_attacking = '1' then
              if p2_atk_timer > 0 then
                p2_atk_timer <= p2_atk_timer - 1;
              else
                p2_attacking <= '0';
              end if;
            elsif jc2_rising = '1' then
              p2_attacking <= '1';
              p2_atk_timer <= ATTACK_CYCLES;
              if p2_hits_p1(p1_x, p2_x, p1_attacking) then
                winner    <= 2;
                screen    <= SCREEN_WIN;
                win_timer <= 0;
              end if;
            end if;

            if game_tick = '1' then
              if p1_attacking = '0' then
                if deb_out(2) = '1' then
                  if p1_x >= MOVE_SPEED then p1_x <= p1_x - MOVE_SPEED;
                  else p1_x <= 0; end if;
                elsif deb_out(3) = '1' then
                  if p1_x <= SCREEN_W - SPR_W - MOVE_SPEED then
                    p1_x <= p1_x + MOVE_SPEED;
                  else p1_x <= SCREEN_W - SPR_W; end if;
                end if;
              end if;
              if p2_attacking = '0' then
                if deb_out(0) = '1' then
                  if p2_x >= MOVE_SPEED then p2_x <= p2_x - MOVE_SPEED;
                  else p2_x <= 0; end if;
                elsif deb_out(1) = '1' then
                  if p2_x <= SCREEN_W - SPR_W - MOVE_SPEED then
                    p2_x <= p2_x + MOVE_SPEED;
                  else p2_x <= SCREEN_W - SPR_W; end if;
                end if;
              end if;
            end if;

          when SCREEN_WIN =>
            if win_timer = WIN_CYCLES - 1 then
              screen    <= SCREEN_MENU;
              win_timer <= 0;
            else
              win_timer <= win_timer + 1;
            end if;

        end case;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- first_frame - single driver process
  -- '1' on reset or when screen changes to GAME or WIN
  -- '0' when blitter signals clear_done
  -- =========================================================================
  process(clk)
    variable prev_screen : screen_t := SCREEN_MENU;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        first_frame  <= '1';
        prev_screen  := SCREEN_MENU;
      elsif clear_done = '1' then
        first_frame  <= '0';
      elsif screen /= prev_screen then
        first_frame  <= '1';
      end if;
      prev_screen := screen;
    end if;
  end process;

  -- =========================================================================
  -- Blitter FSM
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        blit_state   <= BL_IDLE;
        blit_we      <= '0';
        blit_p2      <= '0';
        clear_done   <= '0';
        prev_p1_x    <= P1_START_X;
        prev_p2_x    <= P2_START_X;
      else
        blit_we    <= '0';
        clear_done <= '0';

        case blit_state is

          when BL_IDLE =>
            if blanking_rise = '1' and screen /= SCREEN_MENU then
              bl_p1_x      <= p1_x;
              bl_p2_x      <= p2_x;
              bl_prev_p1_x <= prev_p1_x;
              bl_prev_p2_x <= prev_p2_x;
              bl_p1_atk    <= p1_attacking;
              bl_p2_atk    <= p2_attacking;
              bl_winner    <= winner;
              if p1_attacking = '1' then
                bl_p1_hurt_top <= GROUND_Y + HURT_Y_ATTACK;
                bl_p1_hurt_h   <= HURT_H_ATTACK;
                bl_p1_hurt_w   <= HURT_W_ATTACK;
              else
                bl_p1_hurt_top <= GROUND_Y + HURT_Y_IDLE;
                bl_p1_hurt_h   <= HURT_H_IDLE;
                bl_p1_hurt_w   <= HURT_W_IDLE;
              end if;
              if p2_attacking = '1' then
                bl_p2_hurt_top <= GROUND_Y + HURT_Y_ATTACK;
                bl_p2_hurt_h   <= HURT_H_ATTACK;
                bl_p2_hurt_w   <= HURT_W_ATTACK;
              else
                bl_p2_hurt_top <= GROUND_Y + HURT_Y_IDLE;
                bl_p2_hurt_h   <= HURT_H_IDLE;
                bl_p2_hurt_w   <= HURT_W_IDLE;
              end if;
              if first_frame = '1' then
                clear_cnt  <= 0;
                blit_state <= BL_FULL_CLEAR;
              elsif screen = SCREEN_WIN then
                txt_char   <= 0;
                txt_col    <= 0;
                txt_row    <= 0;
                blit_state <= BL_WIN_TEXT;
              else
                bl_col     <= 0;
                bl_row     <= 0;
                blit_state <= BL_ERASE_P1_FETCH;
              end if;
            end if;

          when BL_FULL_CLEAR =>
            blit_we    <= '1';
            clear_done <= '0';
            blit_addr  <= std_logic_vector(to_unsigned(clear_cnt, 18));
            blit_din   <= x"00";
            if clear_cnt = FB_SIZE - 1 then
              clear_done <= '1';
              bl_col     <= 0;
              bl_row     <= 0;
              if screen = SCREEN_WIN then
                blit_state <= BL_WIN_FALLEN_FETCH;
              else
                blit_p2    <= '0';
                blit_state <= BL_SP1_FETCH;
              end if;
            else
              clear_cnt <= clear_cnt + 1;
            end if;

          -- Erase P1
          when BL_ERASE_P1_FETCH =>
            if (bl_prev_p1_x + bl_col) < SCREEN_W and
               (GROUND_Y     + bl_row) < SCREEN_H then
              blit_we   <= '1';
              blit_addr <= std_logic_vector(to_unsigned(
                (GROUND_Y + bl_row) * SCREEN_W + (bl_prev_p1_x + bl_col), 18));
              blit_din  <= x"00";
            end if;
            blit_state <= BL_ERASE_P1_NEXT_COL;

          when BL_ERASE_P1_NEXT_COL =>
            if bl_col = SPR_W - 1 then bl_col <= 0; blit_state <= BL_ERASE_P1_NEXT_ROW;
            else bl_col <= bl_col + 1; blit_state <= BL_ERASE_P1_FETCH; end if;

          when BL_ERASE_P1_NEXT_ROW =>
            if bl_row = SPR_H - 1 then bl_col <= 0; bl_row <= 0; blit_state <= BL_ERASE_P2_FETCH;
            else bl_row <= bl_row + 1; blit_state <= BL_ERASE_P1_FETCH; end if;

          -- Erase P2
          when BL_ERASE_P2_FETCH =>
            if (bl_prev_p2_x + bl_col) < SCREEN_W and
               (GROUND_Y     + bl_row) < SCREEN_H then
              blit_we   <= '1';
              blit_addr <= std_logic_vector(to_unsigned(
                (GROUND_Y + bl_row) * SCREEN_W + (bl_prev_p2_x + bl_col), 18));
              blit_din  <= x"00";
            end if;
            blit_state <= BL_ERASE_P2_NEXT_COL;

          when BL_ERASE_P2_NEXT_COL =>
            if bl_col = SPR_W - 1 then bl_col <= 0; blit_state <= BL_ERASE_P2_NEXT_ROW;
            else bl_col <= bl_col + 1; blit_state <= BL_ERASE_P2_FETCH; end if;

          when BL_ERASE_P2_NEXT_ROW =>
            if bl_row = SPR_H - 1 then
              bl_col <= 0; bl_row <= 0; blit_p2 <= '0'; blit_state <= BL_SP1_FETCH;
            else bl_row <= bl_row + 1; blit_state <= BL_ERASE_P2_FETCH; end if;

          -- Blit P1
          when BL_SP1_FETCH =>
            blit_p2 <= '0'; blit_state <= BL_SP1_WRITE;

          when BL_SP1_WRITE =>
            if cur_data /= TRANSPARENT and
               (bl_p1_x + bl_col) < SCREEN_W and
               (GROUND_Y + bl_row) < SCREEN_H then
              blit_we   <= '1';
              blit_addr <= std_logic_vector(to_unsigned(
                (GROUND_Y + bl_row) * SCREEN_W + (bl_p1_x + bl_col), 18));
              blit_din  <= cur_data;
            end if;
            blit_state <= BL_SP1_NEXT_COL;

          when BL_SP1_NEXT_COL =>
            if bl_col = SPR_W - 1 then bl_col <= 0; blit_state <= BL_SP1_NEXT_ROW;
            else bl_col <= bl_col + 1; blit_state <= BL_SP1_FETCH; end if;

          when BL_SP1_NEXT_ROW =>
            if bl_row = SPR_H - 1 then
              bl_col <= 0; bl_row <= 0; blit_p2 <= '1'; blit_state <= BL_SP2_FETCH;
            else bl_row <= bl_row + 1; blit_state <= BL_SP1_FETCH; end if;

          -- Blit P2
          when BL_SP2_FETCH =>
            blit_p2 <= '1'; blit_state <= BL_SP2_WRITE;

          when BL_SP2_WRITE =>
            if cur_data /= TRANSPARENT and
               (bl_p2_x + bl_col) < SCREEN_W and
               (GROUND_Y + bl_row) < SCREEN_H then
              blit_we   <= '1';
              blit_addr <= std_logic_vector(to_unsigned(
                (GROUND_Y + bl_row) * SCREEN_W + (bl_p2_x + bl_col), 18));
              blit_din  <= cur_data;
            end if;
            blit_state <= BL_SP2_NEXT_COL;

          when BL_SP2_NEXT_COL =>
            if bl_col = SPR_W - 1 then bl_col <= 0; blit_state <= BL_SP2_NEXT_ROW;
            else bl_col <= bl_col + 1; blit_state <= BL_SP2_FETCH; end if;

          when BL_SP2_NEXT_ROW =>
            if bl_row = SPR_H - 1 then
              prev_p1_x <= bl_p1_x;
              prev_p2_x <= bl_p2_x;
              if debug_mode = '1' then
                dbg_col <= 0; dbg_row <= 0; blit_state <= BL_DBG_HURT1;
              else
                blit_state <= BL_DONE;
              end if;
            else bl_row <= bl_row + 1; blit_state <= BL_SP2_FETCH; end if;

          -- Win: fallen sprite
          when BL_WIN_FALLEN_FETCH =>
            blit_state <= BL_WIN_FALLEN_WRITE;

          when BL_WIN_FALLEN_WRITE =>
            if p1_data /= TRANSPARENT then
              if bl_winner = 1 then
                if (bl_p2_x + bl_col) < SCREEN_W and (GROUND_Y + bl_row) < SCREEN_H then
                  blit_we   <= '1';
                  blit_addr <= std_logic_vector(to_unsigned(
                    (GROUND_Y + bl_row) * SCREEN_W + (bl_p2_x + bl_col), 18));
                  blit_din  <= p1_data;
                end if;
              else
                if (bl_p1_x + bl_col) < SCREEN_W and (GROUND_Y + bl_row) < SCREEN_H then
                  blit_we   <= '1';
                  blit_addr <= std_logic_vector(to_unsigned(
                    (GROUND_Y + bl_row) * SCREEN_W + (bl_p1_x + bl_col), 18));
                  blit_din  <= p1_data;
                end if;
              end if;
            end if;
            blit_state <= BL_WIN_FALLEN_NEXT_COL;

          when BL_WIN_FALLEN_NEXT_COL =>
            if bl_col = SPR_W - 1 then bl_col <= 0; blit_state <= BL_WIN_FALLEN_NEXT_ROW;
            else bl_col <= bl_col + 1; blit_state <= BL_WIN_FALLEN_FETCH; end if;

          when BL_WIN_FALLEN_NEXT_ROW =>
            if bl_row = SPR_H - 1 then
              bl_col <= 0; bl_row <= 0;
              blit_state <= BL_WIN_WINNER_FETCH;
            else bl_row <= bl_row + 1; blit_state <= BL_WIN_FALLEN_FETCH; end if;

          -- Win: winner sprite (attack animation, P2 flipped)
          when BL_WIN_WINNER_FETCH =>
            if bl_winner = 2 then blit_p2 <= '1';
            else blit_p2 <= '0'; end if;
            blit_state <= BL_WIN_WINNER_WRITE;

          when BL_WIN_WINNER_WRITE =>
            if atk_data /= TRANSPARENT then
              if bl_winner = 1 then
                if (bl_p1_x + bl_col) < SCREEN_W and (GROUND_Y + bl_row) < SCREEN_H then
                  blit_we   <= '1';
                  blit_addr <= std_logic_vector(to_unsigned(
                    (GROUND_Y + bl_row) * SCREEN_W + (bl_p1_x + bl_col), 18));
                  blit_din  <= atk_data;
                end if;
              else
                if (bl_p2_x + bl_col) < SCREEN_W and (GROUND_Y + bl_row) < SCREEN_H then
                  blit_we   <= '1';
                  blit_addr <= std_logic_vector(to_unsigned(
                    (GROUND_Y + bl_row) * SCREEN_W + (bl_p2_x + bl_col), 18));
                  blit_din  <= atk_data;
                end if;
              end if;
            end if;
            blit_state <= BL_WIN_WINNER_NEXT_COL;

          when BL_WIN_WINNER_NEXT_COL =>
            if bl_col = SPR_W - 1 then bl_col <= 0; blit_state <= BL_WIN_WINNER_NEXT_ROW;
            else bl_col <= bl_col + 1; blit_state <= BL_WIN_WINNER_FETCH; end if;

          when BL_WIN_WINNER_NEXT_ROW =>
            if bl_row = SPR_H - 1 then
              blit_p2  <= '0';
              txt_char <= 0; txt_col <= 0; txt_row <= 0;
              blit_state <= BL_WIN_TEXT;
            else bl_row <= bl_row + 1; blit_state <= BL_WIN_WINNER_FETCH; end if;

          -- Win: text
          when BL_WIN_TEXT =>
            blit_we   <= '1';
            blit_addr <= std_logic_vector(to_unsigned(
              (TEXT_Y + txt_row) * SCREEN_W +
              (TEXT_X + txt_char * CHAR_W + txt_col), 18));
            if bl_winner = 1 then
              if FONT(P1_WIN_TEXT(txt_char))(txt_row / 4)(4 - (txt_col / 4)) = '1' then
                blit_din <= x"FF";
              else
                blit_din <= x"00";
              end if;
            else
              if FONT(P2_WIN_TEXT(txt_char))(txt_row / 4)(4 - (txt_col / 4)) = '1' then
                blit_din <= x"FF";
              else
                blit_din <= x"00";
              end if;
            end if;
            if txt_col = CHAR_W - 1 then
              txt_col <= 0;
              if txt_row = CHAR_H - 1 then
                txt_row <= 0;
                if txt_char = TEXT_LEN - 1 then
                  blit_state <= BL_DONE;
                else
                  txt_char <= txt_char + 1;
                end if;
              else
                txt_row <= txt_row + 1;
              end if;
            else
              txt_col <= txt_col + 1;
            end if;

          -- Debug hurtboxes / hitboxes
          when BL_DBG_HURT1 =>
            if (bl_p1_x + dbg_col) < SCREEN_W and (bl_p1_hurt_top + dbg_row) < SCREEN_H then
              blit_we   <= '1';
              blit_addr <= std_logic_vector(to_unsigned(
                (bl_p1_hurt_top + dbg_row) * SCREEN_W + (bl_p1_x + dbg_col), 18));
              blit_din  <= HURTBOX_COLOR;
            end if;
            if dbg_col = bl_p1_hurt_w - 1 then dbg_col <= 0; blit_state <= BL_DBG_HURT1_NEXT_ROW;
            else dbg_col <= dbg_col + 1; blit_state <= BL_DBG_HURT1; end if;

          when BL_DBG_HURT1_NEXT_COL => blit_state <= BL_DBG_HURT1;

          when BL_DBG_HURT1_NEXT_ROW =>
            if dbg_row = bl_p1_hurt_h - 1 then dbg_col <= 0; dbg_row <= 0; blit_state <= BL_DBG_HURT2;
            else dbg_row <= dbg_row + 1; blit_state <= BL_DBG_HURT1; end if;

          when BL_DBG_HURT2 =>
            if (bl_p2_x + SPR_W - bl_p2_hurt_w + dbg_col) < SCREEN_W and
               (bl_p2_hurt_top + dbg_row) < SCREEN_H then
              blit_we   <= '1';
              blit_addr <= std_logic_vector(to_unsigned(
                (bl_p2_hurt_top + dbg_row) * SCREEN_W +
                (bl_p2_x + SPR_W - bl_p2_hurt_w + dbg_col), 18));
              blit_din  <= HURTBOX_COLOR;
            end if;
            if dbg_col = bl_p2_hurt_w - 1 then dbg_col <= 0; blit_state <= BL_DBG_HURT2_NEXT_ROW;
            else dbg_col <= dbg_col + 1; blit_state <= BL_DBG_HURT2; end if;

          when BL_DBG_HURT2_NEXT_COL => blit_state <= BL_DBG_HURT2;

          when BL_DBG_HURT2_NEXT_ROW =>
            if dbg_row = bl_p2_hurt_h - 1 then dbg_col <= 0; dbg_row <= 0; blit_state <= BL_DBG_HIT1;
            else dbg_row <= dbg_row + 1; blit_state <= BL_DBG_HURT2; end if;

          when BL_DBG_HIT1 =>
            if (bl_p1_x + SPR_W - HIT_INSET - HIT_W + dbg_col) < SCREEN_W and
               (GROUND_Y + HIT_Y_OFS + dbg_row) < SCREEN_H then
              blit_we   <= '1';
              blit_addr <= std_logic_vector(to_unsigned(
                (GROUND_Y + HIT_Y_OFS + dbg_row) * SCREEN_W +
                (bl_p1_x + SPR_W - HIT_INSET - HIT_W + dbg_col), 18));
              if bl_p1_atk = '1' then
                blit_din <= HITBOX_COLOR;
              else
                blit_din <= x"00";
              end if;
            end if;
            if dbg_col = HIT_W - 1 then dbg_col <= 0; blit_state <= BL_DBG_HIT1_NEXT_ROW;
            else dbg_col <= dbg_col + 1; blit_state <= BL_DBG_HIT1; end if;

          when BL_DBG_HIT1_NEXT_COL => blit_state <= BL_DBG_HIT1;

          when BL_DBG_HIT1_NEXT_ROW =>
            if dbg_row = HIT_H - 1 then dbg_col <= 0; dbg_row <= 0; blit_state <= BL_DBG_HIT2;
            else dbg_row <= dbg_row + 1; blit_state <= BL_DBG_HIT1; end if;

          when BL_DBG_HIT2 =>
            if (bl_p2_x + HIT_INSET + dbg_col) < SCREEN_W and
               (GROUND_Y + HIT_Y_OFS + dbg_row) < SCREEN_H then
              blit_we   <= '1';
              blit_addr <= std_logic_vector(to_unsigned(
                (GROUND_Y + HIT_Y_OFS + dbg_row) * SCREEN_W +
                (bl_p2_x + HIT_INSET + dbg_col), 18));
              if bl_p2_atk = '1' then
                blit_din <= HITBOX_COLOR;
              else
                blit_din <= x"00";
              end if;
            end if;
            if dbg_col = HIT_W - 1 then dbg_col <= 0; blit_state <= BL_DBG_HIT2_NEXT_ROW;
            else dbg_col <= dbg_col + 1; blit_state <= BL_DBG_HIT2; end if;

          when BL_DBG_HIT2_NEXT_COL => blit_state <= BL_DBG_HIT2;

          when BL_DBG_HIT2_NEXT_ROW =>
            if dbg_row = HIT_H - 1 then blit_state <= BL_DONE;
            else dbg_row <= dbg_row + 1; blit_state <= BL_DBG_HIT2; end if;

          when BL_DONE =>
            prev_p1_x  <= bl_p1_x;
            prev_p2_x  <= bl_p2_x;
            blit_p2    <= '0';
            blit_state <= BL_IDLE;

          when others => blit_state <= BL_IDLE;

        end case;
      end if;
    end if;
  end process;

end architecture rtl;