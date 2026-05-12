-- =============================================================================
-- board_top.vhd
-- Top-level. Two players, idle + attack ROMs.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity board_top is
  port (
    clk           : in  std_logic;
    btn           : in  std_logic_vector(3 downto 0);
    jc            : in  std_logic_vector(2 downto 0);
    hdmi_tx_clk_p : out std_logic;
    hdmi_tx_clk_n : out std_logic;
    hdmi_tx_p     : out std_logic_vector(2 downto 0);
    hdmi_tx_n     : out std_logic_vector(2 downto 0);
    -- Audio
    ac_scl        : out   std_logic;
    ac_sda        : inout std_logic;
    ac_mclk       : out   std_logic;
    ac_bclk       : out   std_logic;
    ac_pblrc      : out   std_logic;
    ac_pbdat      : out   std_logic;
    ac_muten      : out   std_logic
  );
end entity board_top;

architecture rtl of board_top is

  component HDMI_top is
    port (
      clk           : in  std_logic;
      douta         : in  std_logic_vector(7 downto 0);
      addra         : out std_logic_vector(17 downto 0);
      voutcount     : out std_logic_vector(9 downto 0);
      hdmi_tx_clk_p : out std_logic;
      hdmi_tx_clk_n : out std_logic;
      hdmi_tx_n     : out std_logic_vector(2 downto 0);
      hdmi_tx_p     : out std_logic_vector(2 downto 0)
    );
  end component;

  component game_ctrl is
    port (
      clk      : in  std_logic;
      rst      : in  std_logic;
      btn      : in  std_logic_vector(3 downto 0);
      jc       : in  std_logic_vector(2 downto 0);
      fb_addr  : in  std_logic_vector(17 downto 0);
      fb_data  : out std_logic_vector(7 downto 0);
      vcount   : in  std_logic_vector(9 downto 0);
      p1_addr  : out std_logic_vector(11 downto 0);
      p1_data  : in  std_logic_vector(7 downto 0);
      atk_addr : out std_logic_vector(11 downto 0);
      atk_data : in  std_logic_vector(7 downto 0);
      fb_wea   : out std_logic_vector(0 downto 0);
      fb_addra : out std_logic_vector(17 downto 0);
      fb_dina  : out std_logic_vector(7 downto 0);
      fb_doutb : in  std_logic_vector(7 downto 0);
      game_active : out std_logic
    );
  end component;

  component p1_rom is
    port (
      clka  : in  std_logic;
      addra : in  std_logic_vector(11 downto 0);
      douta : out std_logic_vector(7 downto 0)
    );
  end component;

  component playerattack_rom is
    port (
      clka  : in  std_logic;
      addra : in  std_logic_vector(11 downto 0);
      douta : out std_logic_vector(7 downto 0)
    );
  end component;

  component framebuffer is
    port (
      clka  : in  std_logic;
      wea   : in  std_logic_vector(0 downto 0);
      addra : in  std_logic_vector(17 downto 0);
      dina  : in  std_logic_vector(7 downto 0);
      clkb  : in  std_logic;
      addrb : in  std_logic_vector(17 downto 0);
      doutb : out std_logic_vector(7 downto 0)
    );
  end component;

  component audio_top is
    port (
      clk      : in    std_logic;
      rst      : in    std_logic;
      play_en  : in    std_logic;
      ac_scl   : out   std_logic;
      ac_sda   : inout std_logic;
      ac_mclk  : out   std_logic;
      ac_bclk  : out   std_logic;
      ac_pblrc : out   std_logic;
      ac_pbdat : out   std_logic;
      ac_muten : out   std_logic
    );
  end component;

  signal game_active : std_logic;
  signal hdmi_addr  : std_logic_vector(17 downto 0);
  signal hdmi_data  : std_logic_vector(7 downto 0);
  signal vcount     : std_logic_vector(9 downto 0);

  signal p1_addr    : std_logic_vector(11 downto 0);
  signal p1_data    : std_logic_vector(7 downto 0);

  signal atk_addr   : std_logic_vector(11 downto 0);
  signal atk_data   : std_logic_vector(7 downto 0);

  signal fb_wea     : std_logic_vector(0 downto 0);
  signal fb_addra   : std_logic_vector(17 downto 0);
  signal fb_dina    : std_logic_vector(7 downto 0);
  signal fb_doutb   : std_logic_vector(7 downto 0);

begin

  u_hdmi : HDMI_top
    port map (
      clk           => clk,
      douta         => hdmi_data,
      addra         => hdmi_addr,
      voutcount     => vcount,
      hdmi_tx_clk_p => hdmi_tx_clk_p,
      hdmi_tx_clk_n => hdmi_tx_clk_n,
      hdmi_tx_p     => hdmi_tx_p,
      hdmi_tx_n     => hdmi_tx_n
    );

  u_game_ctrl : game_ctrl
    port map (
      clk      => clk,
      rst      => '0',
      btn      => btn,
      jc       => jc,
      fb_addr  => hdmi_addr,
      fb_data  => hdmi_data,
      vcount   => vcount,
      p1_addr  => p1_addr,
      p1_data  => p1_data,
      atk_addr => atk_addr,
      atk_data => atk_data,
      fb_wea   => fb_wea,
      fb_addra => fb_addra,
      fb_dina  => fb_dina,
      fb_doutb => fb_doutb,
      game_active => game_active
    );

  u_audio : audio_top
    port map (
      clk      => clk,
      rst      => '0',
      play_en  => game_active,
      ac_scl   => ac_scl,
      ac_sda   => ac_sda,
      ac_mclk  => ac_mclk,
      ac_bclk  => ac_bclk,
      ac_pblrc => ac_pblrc,
      ac_pbdat => ac_pbdat,
      ac_muten => ac_muten
    );

  u_p1_rom : p1_rom
    port map (
      clka  => clk,
      addra => p1_addr,
      douta => p1_data
    );

  u_atk_rom : playerattack_rom
    port map (
      clka  => clk,
      addra => atk_addr,
      douta => atk_data
    );

  u_framebuffer : framebuffer
    port map (
      clka  => clk,
      wea   => fb_wea,
      addra => fb_addra,
      dina  => fb_dina,
      clkb  => clk,
      addrb => hdmi_addr,
      doutb => fb_doutb
    );

end architecture rtl;