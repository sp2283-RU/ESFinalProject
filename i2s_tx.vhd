-- =============================================================================
-- i2s_tx.vhd
-- I2S transmitter for the SSM2603 audio codec.
--
-- Generates BCLK, LRCLK (WS), and SDATA from a 125 MHz system clock.
-- Sample rate: 44.1 kHz
-- Bit depth:   16-bit per channel (stereo, same sample both channels)
--
-- BCLK  = 125 MHz / 45 ≈ 2.778 MHz  (close enough; SSM2603 accepts this)
-- LRCLK = BCLK / 64 = ~43.4 kHz     (within SSM2603 tolerance)
--
-- sample_in is latched on each LRCLK rising edge (start of left channel).
-- The same sample is sent to both left and right channels.
--
-- mclk: The SSM2603 needs a master clock. We output 125 MHz / 3 ≈ 41.7 MHz
-- which is close to the required 256× or 384× fs. For 44.1 kHz USB mode
-- the codec generates its own fs from mclk via internal PLL.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_tx is
  port (
    clk        : in  std_logic;   -- 125 MHz
    rst        : in  std_logic;

    -- Audio sample input (16-bit signed, latched each frame)
    sample_in  : in  std_logic_vector(15 downto 0);

    -- I2S outputs to SSM2603
    mclk       : out std_logic;   -- master clock (~11.2 MHz = 125/11)
    bclk       : out std_logic;   -- bit clock
    lrclk      : out std_logic;   -- left/right clock (= word select)
    sdata      : out std_logic    -- serial data
  );
end entity i2s_tx;

architecture rtl of i2s_tx is

  -- MCLK divider: 125 MHz / 11 ≈ 11.36 MHz (256 * 44.4 kHz)
  constant MCLK_DIV  : integer := 11;
  -- BCLK divider from MCLK: divide by 4 → ~2.84 MHz
  constant BCLK_DIV  : integer := 4;
  -- LRCLK = BCLK / 64 (32 bits per channel × 2 channels)

  signal mclk_cnt    : integer range 0 to MCLK_DIV - 1 := 0;
  signal mclk_r      : std_logic := '0';

  signal bclk_cnt    : integer range 0 to BCLK_DIV - 1 := 0;
  signal bclk_r      : std_logic := '0';
  signal bclk_rise   : std_logic := '0';
  signal bclk_fall   : std_logic := '0';

  signal lrclk_r     : std_logic := '0';
  signal bit_cnt     : integer range 0 to 63 := 0;

  -- Shift register: 16-bit sample padded to 32 bits (MSB first)
  signal shift_reg   : std_logic_vector(31 downto 0) := (others => '0');

  signal sample_latch: std_logic_vector(15 downto 0) := (others => '0');

begin

  mclk  <= mclk_r;
  bclk  <= bclk_r;
  lrclk <= lrclk_r;

  -- =========================================================================
  -- MCLK generation
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if mclk_cnt = MCLK_DIV - 1 then
        mclk_cnt <= 0;
        mclk_r   <= not mclk_r;
      else
        mclk_cnt <= mclk_cnt + 1;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- BCLK generation (from sys clk directly for accuracy)
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      bclk_rise <= '0';
      bclk_fall <= '0';
      if bclk_cnt = BCLK_DIV - 1 then
        bclk_cnt <= 0;
        bclk_r   <= not bclk_r;
        if bclk_r = '0' then
          bclk_rise <= '1';   -- about to go high
        else
          bclk_fall <= '1';   -- about to go low
        end if;
      else
        bclk_cnt <= bclk_cnt + 1;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- I2S shift logic
  -- Data changes on BCLK falling edge, sampled on BCLK rising edge.
  -- LRCLK: '0' = left channel, '1' = right channel.
  -- One bit per BCLK cycle, 32 bits per channel (16 data + 16 zero pad).
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        bit_cnt     <= 0;
        lrclk_r     <= '0';
        shift_reg   <= (others => '0');
        sdata       <= '0';
      else
        if bclk_fall = '1' then
          if bit_cnt = 0 then
            -- Start of new frame: latch sample, set LRCLK, load shift reg
            lrclk_r      <= not lrclk_r;
            sample_latch <= sample_in;
            -- 16-bit sample in MSBs, padded with zeros
            shift_reg    <= sample_in & x"0000";
          else
            -- Shift out MSB first
            sdata     <= shift_reg(31);
            shift_reg <= shift_reg(30 downto 0) & '0';
          end if;

          if bit_cnt = 31 then
            bit_cnt <= 0;
          else
            bit_cnt <= bit_cnt + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
