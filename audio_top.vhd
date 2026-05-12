-- =============================================================================
-- audio_top.vhd
-- Top-level audio module. Ties together:
--   i2c_init     - configures SSM2603 codec at startup via I2C
--   melody_player - generates square wave Ken's theme note sequence
--   i2s_tx       - streams PCM samples to codec via I2S
--
-- play_en: connect to (screen = SCREEN_GAME) from game_ctrl
--          '1' = game screen → music plays
--          '0' = menu screen → silence
--
-- SSM2603 pins (connect in board_top and .xdc):
--   ac_scl   - I2C clock
--   ac_sda   - I2C data (bidirectional)
--   ac_mclk  - master clock
--   ac_bclk  - I2S bit clock
--   ac_lrclk - I2S word select
--   ac_sdata - I2S serial data
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_top is
  port (
    clk      : in    std_logic;   -- 125 MHz
    rst      : in    std_logic;
    play_en  : in    std_logic;   -- '1' when in game screen

    -- SSM2603 codec pins
    ac_scl   : out   std_logic;
    ac_sda   : inout std_logic;
    ac_mclk  : out   std_logic;
    ac_bclk  : out   std_logic;
    ac_pblrc : out   std_logic;
    ac_pbdat : out   std_logic;
    ac_muten : out   std_logic
  );
end entity audio_top;

architecture rtl of audio_top is

  component i2c_init is
    port (
      clk  : in    std_logic;
      rst  : in    std_logic;
      scl  : out   std_logic;
      sda  : inout std_logic;
      done : out   std_logic
    );
  end component;

  component i2s_tx is
    port (
      clk      : in  std_logic;
      rst      : in  std_logic;
      sample_in: in  std_logic_vector(15 downto 0);
      mclk     : out std_logic;
      bclk     : out std_logic;
      lrclk    : out std_logic;
      sdata    : out std_logic
    );
  end component;

  component melody_player is
    port (
      clk     : in  std_logic;
      rst     : in  std_logic;
      play_en : in  std_logic;
      sample  : out std_logic_vector(15 downto 0)
    );
  end component;

  signal codec_ready   : std_logic;
  signal audio_sample  : std_logic_vector(15 downto 0);
  signal play_en_gated : std_logic;

begin

  play_en_gated <= play_en and codec_ready;

  ac_muten <= '1';

  u_i2c : i2c_init
    port map (
      clk  => clk,
      rst  => rst,
      scl  => ac_scl,
      sda  => ac_sda,
      done => codec_ready
    );

  u_melody : melody_player
    port map (
      clk     => clk,
      rst     => rst,
      play_en => play_en_gated,
      sample  => audio_sample
    );

  u_i2s : i2s_tx
    port map (
      clk       => clk,
      rst       => rst,
      sample_in => audio_sample,
      mclk      => ac_mclk,
      bclk      => ac_bclk,
      lrclk     => ac_pblrc,
      sdata     => ac_pbdat
    );

end architecture rtl;