-- =============================================================================
-- i2c_init.vhd
-- Configures the SSM2603 audio codec via I2C at startup.
--
-- The SSM2603 uses a 7-bit I2C address of 0x1A (fixed, no address pins).
-- Register writes are 16-bit: [7:9]=register address, [8:0]=register data.
-- I2C clock: ~100 kHz derived from 125 MHz sys_clk (divider = 625).
--
-- Sequence:
--   1. Reset codec
--   2. Power up (disable power-down bits)
--   3. Set ADC/DAC sample rate (USB mode, 44.1 kHz)
--   4. Set digital audio interface (I2S, 16-bit)
--   5. Set DAC volume
--   6. Activate audio interface
--
-- done goes high once all registers are written and stays high.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_init is
  port (
    clk      : in    std_logic;   -- 125 MHz
    rst      : in    std_logic;
    scl      : out   std_logic;
    sda      : inout std_logic;
    done     : out   std_logic
  );
end entity i2c_init;

architecture rtl of i2c_init is

  -- I2C clock divider: 125 MHz / (2 * 625) = 100 kHz
  constant CLK_DIV     : integer := 625;
  constant SSM2603_ADDR: std_logic_vector(6 downto 0) := "0011010"; -- 0x1A

  -- SSM2603 register init sequence: 7-bit reg addr & 9-bit data = 16 bits
  type reg_data_t is array(0 to 9) of std_logic_vector(15 downto 0);
  constant INIT_SEQ : reg_data_t := (
    0 => "0001111" & "000000000",   -- R15: reset
    1 => "0000110" & "000000000",   -- R6:  power up all
    2 => "0000000" & "010010111",   -- R0:  left in 0dB
    3 => "0000001" & "010010111",   -- R1:  right in 0dB
    4 => "0000010" & "001111001",   -- R2:  left hp 0dB
    5 => "0000011" & "001111001",   -- R3:  right hp 0dB
    6 => "0000100" & "000010010",   -- R4:  DAC sel
    7 => "0000101" & "000000000",   -- R5:  digital path
    8 => "0000111" & "000000010",   -- R7:  I2S 16-bit
    9 => "0001001" & "000000001"    -- R9:  activate
  );

  constant NUM_REGS : integer := 10;

  -- =========================================================================
  -- I2C bit-bang FSM
  -- =========================================================================
  type i2c_state_t is (
    I2C_IDLE,
    I2C_START,
    I2C_ADDR,       -- send 7-bit address + W bit
    I2C_ADDR_ACK,
    I2C_DATA_H,     -- send high byte of 16-bit register word
    I2C_DATA_H_ACK,
    I2C_DATA_L,     -- send low byte
    I2C_DATA_L_ACK,
    I2C_STOP,
    I2C_DONE
  );
  signal i2c_state  : i2c_state_t := I2C_IDLE;

  signal clk_cnt    : integer range 0 to CLK_DIV - 1 := 0;
  signal clk_en     : std_logic := '0';   -- pulses at 2× I2C clock rate
  signal scl_r      : std_logic := '1';
  signal sda_r      : std_logic := '1';

  signal reg_idx    : integer range 0 to NUM_REGS := 0;
  signal bit_cnt    : integer range 0 to 7 := 0;
  signal shift_reg  : std_logic_vector(7 downto 0) := (others => '0');

  signal phase      : std_logic := '0';  -- 0=SCL low half, 1=SCL high half

begin

  scl  <= scl_r;
  sda  <= sda_r when sda_r = '0' else 'Z';  -- open-drain
  done <= '1' when i2c_state = I2C_DONE else '0';

  -- =========================================================================
  -- Clock divider - generates clk_en at 2× I2C clock (200 kHz)
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      clk_en <= '0';
      if clk_cnt = CLK_DIV - 1 then
        clk_cnt <= 0;
        clk_en  <= '1';
      else
        clk_cnt <= clk_cnt + 1;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- I2C FSM
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        i2c_state <= I2C_IDLE;
        scl_r     <= '1';
        sda_r     <= '1';
        reg_idx   <= 0;
        bit_cnt   <= 0;
        phase     <= '0';
      elsif clk_en = '1' then

        case i2c_state is

          -- -----------------------------------------------------------------
          when I2C_IDLE =>
            scl_r     <= '1';
            sda_r     <= '1';
            phase     <= '0';
            i2c_state <= I2C_START;

          -- -----------------------------------------------------------------
          -- START: SDA falls while SCL is high
          when I2C_START =>
            if phase = '0' then
              sda_r <= '0';
              phase <= '1';
            else
              scl_r     <= '0';
              phase     <= '0';
              bit_cnt   <= 7;
              -- Load address byte: 7-bit addr + write bit (0)
              shift_reg <= SSM2603_ADDR & '0';
              i2c_state <= I2C_ADDR;
            end if;

          -- -----------------------------------------------------------------
          -- Send address byte (8 bits)
          when I2C_ADDR =>
            if phase = '0' then
              sda_r <= shift_reg(7);
              phase <= '1';
            else
              scl_r <= not scl_r;
              if scl_r = '1' then
                -- falling edge: advance
                if bit_cnt = 0 then
                  sda_r     <= '1';  -- release for ACK
                  i2c_state <= I2C_ADDR_ACK;
                else
                  bit_cnt   <= bit_cnt - 1;
                  shift_reg <= shift_reg(6 downto 0) & '0';
                end if;
              end if;
              phase <= '0';
            end if;

          -- -----------------------------------------------------------------
          when I2C_ADDR_ACK =>
            if phase = '0' then
              scl_r <= '1';
              phase <= '1';
            else
              scl_r     <= '0';
              phase     <= '0';
              -- Load high byte of current register word
              shift_reg <= INIT_SEQ(reg_idx)(15 downto 8);
              bit_cnt   <= 7;
              i2c_state <= I2C_DATA_H;
            end if;

          -- -----------------------------------------------------------------
          -- Send high byte
          when I2C_DATA_H =>
            if phase = '0' then
              sda_r <= shift_reg(7);
              phase <= '1';
            else
              scl_r <= not scl_r;
              if scl_r = '1' then
                if bit_cnt = 0 then
                  sda_r     <= '1';
                  i2c_state <= I2C_DATA_H_ACK;
                else
                  bit_cnt   <= bit_cnt - 1;
                  shift_reg <= shift_reg(6 downto 0) & '0';
                end if;
              end if;
              phase <= '0';
            end if;

          -- -----------------------------------------------------------------
          when I2C_DATA_H_ACK =>
            if phase = '0' then
              scl_r <= '1';
              phase <= '1';
            else
              scl_r     <= '0';
              phase     <= '0';
              shift_reg <= INIT_SEQ(reg_idx)(7 downto 0);
              bit_cnt   <= 7;
              i2c_state <= I2C_DATA_L;
            end if;

          -- -----------------------------------------------------------------
          -- Send low byte
          when I2C_DATA_L =>
            if phase = '0' then
              sda_r <= shift_reg(7);
              phase <= '1';
            else
              scl_r <= not scl_r;
              if scl_r = '1' then
                if bit_cnt = 0 then
                  sda_r     <= '1';
                  i2c_state <= I2C_DATA_L_ACK;
                else
                  bit_cnt   <= bit_cnt - 1;
                  shift_reg <= shift_reg(6 downto 0) & '0';
                end if;
              end if;
              phase <= '0';
            end if;

          -- -----------------------------------------------------------------
          when I2C_DATA_L_ACK =>
            if phase = '0' then
              scl_r <= '1';
              phase <= '1';
            else
              scl_r     <= '0';
              phase     <= '0';
              i2c_state <= I2C_STOP;
            end if;

          -- -----------------------------------------------------------------
          -- STOP: SDA rises while SCL is high
          when I2C_STOP =>
            if phase = '0' then
              sda_r <= '0';
              scl_r <= '1';
              phase <= '1';
            else
              sda_r <= '1';   -- STOP condition
              phase <= '0';
              if reg_idx = NUM_REGS - 1 then
                i2c_state <= I2C_DONE;
              else
                reg_idx   <= reg_idx + 1;
                i2c_state <= I2C_START;
              end if;
            end if;

          -- -----------------------------------------------------------------
          when I2C_DONE =>
            scl_r <= '1';
            sda_r <= '1';

          when others =>
            i2c_state <= I2C_IDLE;

        end case;
      end if;
    end if;
  end process;

end architecture rtl;