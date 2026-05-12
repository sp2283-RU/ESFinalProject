-- =============================================================================
-- melody_player.vhd
-- Square wave melody player — Ken's Theme from Street Fighter II.
--
-- Generates a 16-bit signed square wave at each note's frequency.
-- Notes are stored as (period_half, duration) pairs in a constant array.
-- period_half = (125_000_000 / frequency) / 2  (half-period in clock cycles)
-- duration    = note length in units of 1/8 note at ~140 BPM
--               one_eighth = 125_000_000 * 60 / (140 * 8) = 6_696_429 cycles
--
-- output goes to i2s_tx sample_in.
-- Plays when play_en = '1', restarts from beginning when play_en goes high.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity melody_player is
  port (
    clk      : in  std_logic;   -- 125 MHz
    rst      : in  std_logic;
    play_en  : in  std_logic;   -- '1' = playing, '0' = silent
    sample   : out std_logic_vector(15 downto 0)
  );
end entity melody_player;

architecture rtl of melody_player is

  -- =========================================================================
  -- Timing constants
  -- BPM = 140, quarter note = 60/140 s, eighth = 30/140 s
  -- one_eighth_cycles = 125_000_000 * 30 / 140 = 26_785_714
  -- We use 16th notes as base unit for finer resolution
  -- one_16th = 125_000_000 * 15 / 140 = 13_392_857
  -- =========================================================================
  constant ONE_16TH  : integer := 13_392_857;
  constant AMP       : integer := 16383;   -- square wave amplitude (half of 32767)

  -- =========================================================================
  -- Note frequency → half-period at 125 MHz
  -- period_half = 125_000_000 / (2 * freq)
  -- REST = 0 (no output)
  -- =========================================================================
  -- Common notes used in Ken's theme
  -- E4=330Hz, F#4=370Hz, G#4=415Hz, A4=440Hz, B4=494Hz
  -- C#5=554Hz, D#5=622Hz, E5=659Hz, F#5=740Hz, G#5=831Hz, A5=880Hz
  -- B5=988Hz, C#6=1109Hz, E3=165Hz, B3=247Hz, F#3=185Hz

  constant REST   : integer := 0;
  constant E3     : integer := 125_000_000 / (2 * 165);
  constant F3s    : integer := 125_000_000 / (2 * 185);
  constant B3     : integer := 125_000_000 / (2 * 247);
  constant E4     : integer := 125_000_000 / (2 * 330);
  constant Fs4    : integer := 125_000_000 / (2 * 370);
  constant Gs4    : integer := 125_000_000 / (2 * 415);
  constant A4     : integer := 125_000_000 / (2 * 440);
  constant B4     : integer := 125_000_000 / (2 * 494);
  constant Cs5    : integer := 125_000_000 / (2 * 554);
  constant Ds5    : integer := 125_000_000 / (2 * 622);
  constant E5     : integer := 125_000_000 / (2 * 659);
  constant Fs5    : integer := 125_000_000 / (2 * 740);
  constant Gs5    : integer := 125_000_000 / (2 * 831);
  constant A5     : integer := 125_000_000 / (2 * 880);
  constant B5     : integer := 125_000_000 / (2 * 988);
  constant Cs6    : integer := 125_000_000 / (2 * 1109);

  -- =========================================================================
  -- Note sequence — Ken's Theme (Street Fighter II)
  -- Each entry: (half_period, duration_in_16ths)
  -- =========================================================================
  type note_t is record
    half_period : integer range 0 to 400_000;
    dur_16ths   : integer range 1 to 32;
  end record;

  type melody_t is array(natural range <>) of note_t;

  -- Ken's Theme main melody (simplified, key of E)
  constant MELODY : melody_t := (
    -- Bar 1
    (E5,  2), (REST,1), (E5,  1), (REST,1), (E5,  2), (REST,1), (Cs5, 1),
    (E5,  2), (Gs5, 2), (REST,4),
    -- Bar 2
    (Gs4, 4), (REST,4), (REST,8),
    -- Bar 3
    (Cs5, 2), (REST,1), (Cs5, 1), (REST,1), (B4,  2), (REST,1), (A4,  1),
    (Cs5, 2), (B4,  2), (REST,2), (A4,  2),
    -- Bar 4
    (Gs5, 2), (Fs5, 2), (Ds5, 2), (E5,  2),
    (REST,2), (Gs4, 2), (A4,  2), (Cs5, 2),
    -- Bar 5
    (A4,  2), (Cs5, 2), (E5,  4),
    (A5,  2), (Gs5, 2), (E5,  2), (Cs5, 2),
    -- Bar 6
    (B4,  4), (REST,2), (B4,  2),
    (Cs5, 2), (B4,  2), (Cs5, 2), (E5,  2),
    -- Bar 7
    (A5,  4), (REST,4),
    (Gs5, 2), (E5,  2), (Gs5, 2), (A5,  2),
    -- Bar 8
    (B5,  8), (REST,8),
    -- Bar 9 — repeat bar 1
    (E5,  2), (REST,1), (E5,  1), (REST,1), (E5,  2), (REST,1), (Cs5, 1),
    (E5,  2), (Gs5, 2), (REST,4),
    -- Bar 10
    (Gs4, 4), (REST,4), (REST,8),
    -- Bar 11
    (Cs5, 2), (REST,1), (Cs5, 1), (REST,1), (B4,  2), (REST,1), (A4,  1),
    (Cs5, 2), (B4,  2), (REST,2), (A4,  2),
    -- Bar 12 — ending
    (Gs5, 2), (Fs5, 2), (Ds5, 2), (E5,  4),
    (E4,  4), (REST,4)
  );

  constant MELODY_LEN : integer := MELODY'length;

  -- =========================================================================
  -- Signals
  -- =========================================================================
  signal note_idx      : integer range 0 to MELODY_LEN - 1 := 0;
  signal half_per      : integer range 0 to 400_000 := 0;
  signal osc_cnt       : integer range 0 to 400_000 := 0;
  signal sq_wave       : std_logic := '0';

  signal dur_cnt       : integer range 0 to ONE_16TH * 32 := 0;
  signal dur_target    : integer range 0 to ONE_16TH * 32 := ONE_16TH;

  signal was_playing   : std_logic := '0';

begin

  -- Output: square wave amplitude or zero
  sample <= std_logic_vector(to_signed(AMP,  16)) when sq_wave = '1' and play_en = '1' and half_per /= 0 else
            std_logic_vector(to_signed(-AMP, 16)) when sq_wave = '0' and play_en = '1' and half_per /= 0 else
            (others => '0');

  -- =========================================================================
  -- Note sequencer
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        note_idx   <= 0;
        dur_cnt    <= 0;
        dur_target <= ONE_16TH * MELODY(0).dur_16ths;
        half_per   <= MELODY(0).half_period;
        osc_cnt    <= 0;
        sq_wave    <= '0';
        was_playing <= '0';

      elsif play_en = '0' then
        -- Pause: reset oscillator, keep position
        sq_wave     <= '0';
        osc_cnt     <= 0;
        was_playing <= '0';

      else
        -- Restart from beginning when play_en first goes high
        if was_playing = '0' then
          note_idx   <= 0;
          dur_cnt    <= 0;
          dur_target <= ONE_16TH * MELODY(0).dur_16ths;
          half_per   <= MELODY(0).half_period;
          osc_cnt    <= 0;
          sq_wave    <= '0';
        end if;
        was_playing <= '1';

        -- Advance note duration
        if dur_cnt = dur_target - 1 then
          dur_cnt <= 0;
          -- Next note
          if note_idx = MELODY_LEN - 1 then
            note_idx <= 0;   -- loop
          else
            note_idx <= note_idx + 1;
          end if;
          half_per   <= MELODY(note_idx + 1 when note_idx < MELODY_LEN - 1 else 0).half_period;
          dur_target <= ONE_16TH * MELODY(note_idx + 1 when note_idx < MELODY_LEN - 1 else 0).dur_16ths;
          osc_cnt    <= 0;
          sq_wave    <= '0';
        else
          dur_cnt <= dur_cnt + 1;
        end if;

        -- Square wave oscillator (only when not a REST)
        if half_per /= 0 then
          if osc_cnt = half_per - 1 then
            osc_cnt <= 0;
            sq_wave <= not sq_wave;
          else
            osc_cnt <= osc_cnt + 1;
          end if;
        end if;

      end if;
    end if;
  end process;

end architecture rtl;
